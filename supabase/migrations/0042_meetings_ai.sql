-- 0042_meetings_ai.sql — Meetings and the AI gateway (Phase 7): meetings fed by the calendar, attendees and their
-- recording notices and opt-outs, recordings, transcripts (provider or upload) with speakers and segments, the pre-call
-- brief, the recap, CRM update suggestions, the per-user workspace switch, and one log of every AI call (ai_calls).
-- Spec: docs/crm-enrichment/specs/projects-meetings.md §2, §3.2, §4–§10 (it called this 0028); design:
-- design-reference/sentral/project/Meetings.dc.html. Departures: docs/crm-enrichment/deviations/meetings-schema.md.
--
-- Nothing is connected: no calendar adapter, no meeting bot, no transcription, no AI provider, no email provider. The
-- database models the whole flow anyway, and the worker_* functions stand in for the providers: a worker reports what
-- the provider did and the database decides what may happen. Every request that needs a provider refuses with
-- not_connected (detail = the provider) when its integration_connections row is not connected; the AI provider is the
-- existing «ai» row (0029, V-P6P-03), not a new «llm» row.
--
-- Consent (§8.3, D-39) is enforced here, not in a worker: a bot is allowed into a call only when the module and the
-- owner's workspace are on, the meeting has a link and external guests (or the owner chose «all»), nobody invited has
-- opted out (per meeting or «never record me», kept as a hash of the address), the provider is connected, and the
-- recording notice went out when the register requires one. A recording the rules do not allow is refused and its
-- file queued for deletion. Audio is kept for rec_retention; transcripts live with the meeting (spec Q12). Erasing a
-- person redacts what they said, deletes the audio of every meeting they attended and removes them from briefs.
--
-- Meetings are not a record type (spec §3.2, Q19): they are read only through the meetings functions, so the per-user
-- switch cannot be bypassed through rec_get, search or exports. A meeting is visible to its owner, to staff invited to
-- it, and as its visibility allows; new meetings are «owner» unless visibility_default is set for scope «meeting» (Q13).
--
-- Nothing a customer said goes into app.audit, an event payload or a notification: ids, counts and codes only. The AI
-- call log holds the feature, the caller, the subject, tokens, cost and the outcome — never a prompt or an output.

-- ===========================================================================
-- registers
-- ===========================================================================
-- providers: the meeting bot and transcription (one vendor or two, spec Q15); the AI provider is «ai» (0029). The list is
-- 0040's (with «pdf»), so either order of the two migrations keeps every provider.
alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai',
                      'email', 'ip_company', 'esign', 'pdf', 'meeting_bot', 'transcription'));
insert into app.integration_connections (provider) values ('meeting_bot'), ('transcription') on conflict do nothing;

-- an approved suggestion is written with the meeting as its source (MTG-05 A, spec §9.10)
alter table app.changelog drop constraint changelog_source_check;
alter table app.changelog add constraint changelog_source_check
  check (source in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'merge', 'enrichment', 'capture', 'meeting'));

-- settings (§7): the audio's retention, and rec_notice's reach
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('rec_retention', 'meetings', array['12_months', 'custom', 'keep'], '12_months', 'platform', 'SEC-11, MTG-02, MTG-03 (months; audio only, transcripts follow the meeting)', false, 'custom', 145);
update app.settings_registry set applies_to = 'MTG-02, MTG-03, MTG-07, MTG-08 (custom: hours before start, 0 = as soon as the meeting is known)' where key = 'rec_notice';

-- the screen a meeting opens on (0038's body plus meeting)
create or replace function app.entity_route(p_entity text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case p_entity when 'deal' then '/deals' when 'lead' then '/leads' when 'person' then '/contacts' when 'organization' then '/contacts'
                       when 'activity' then '/activities' when 'ticket' then '/tickets' when 'email_thread' then '/inbox'
                       when 'form' then '/lead-capture' when 'chat' then '/lead-capture' when 'campaign' then '/campaigns'
                       when 'document' then '/documents' when 'document_template' then '/documents' when 'project' then '/projects'
                       when 'meeting' then '/meetings' else null end
$fn$;

-- ===========================================================================
-- the AI call log (SF-24.5): one row per call to the AI provider, written by the gateway worker. Never the prompt or
-- the output (A7.13). Append-only: a deleted staff member's id empties (FK maintenance); nothing else changes it.
-- ===========================================================================
create table app.ai_calls (
  id            bigint generated always as identity primary key,
  feature       text not null check (feature ~ '^[a-z_]{2,40}$'),
  staff_id      uuid references app.admins (id) on delete set null,
  subject_type  text check (subject_type is null or subject_type ~ '^[a-z_]{2,40}$'),
  subject_id    uuid,
  provider      text check (provider is null or char_length(provider) between 1 and 40),
  model         text check (model is null or char_length(model) between 1 and 80),
  input_tokens  int check (input_tokens is null or input_tokens >= 0),
  output_tokens int check (output_tokens is null or output_tokens >= 0),
  cost_micros   bigint check (cost_micros is null or cost_micros >= 0),
  latency_ms    int check (latency_ms is null or latency_ms >= 0),
  attempts      smallint not null default 1 check (attempts between 1 and 5),
  state         text not null check (state in ('ok', 'retried_ok', 'invalid', 'error', 'not_connected')),
  error_code    text check (error_code is null or error_code ~ '^[a-z_]{1,80}$'),
  at            timestamptz not null default now(),
  check (state <> 'retried_ok' or attempts > 1),
  check (state not in ('ok', 'retried_ok') or error_code is null)
);
create index ai_calls_at on app.ai_calls (at desc);
create index ai_calls_subject on app.ai_calls (subject_type, subject_id);

-- project summaries name the call that made them (V-P6P-04)
alter table app.project_ai_summaries add column ai_call_id bigint references app.ai_calls (id) on delete set null;

-- ===========================================================================
-- meetings
-- ===========================================================================
create table app.meetings (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null check (char_length(btrim(title)) between 1 and 300),
  starts_at           timestamptz,
  ends_at             timestamptz,
  source              text not null check (source in ('calendar', 'adhoc', 'upload', 'desktop')),
  calendar_staff_id   uuid references app.admins (id) on delete set null,
  external_event_id   text check (external_event_id is null or char_length(external_event_id) between 1 and 500),
  conference          text check (conference in ('meet', 'teams', 'zoom', 'phone', 'in_person', 'other')),
  join_url            text check (join_url is null or (char_length(join_url) <= 1000 and join_url ~ '^https://')),
  capture             text not null default 'none' check (capture in ('bot', 'desktop', 'upload', 'none')),
  bot_state           text not null default 'none' check (bot_state in ('none', 'scheduled', 'joining', 'in_call', 'removed', 'left', 'failed', 'blocked')),
  bot_block_reason    text check (bot_block_reason in ('notice_not_sent', 'opted_out', 'not_connected', 'no_link', 'disabled', 'internal_only')),
  call_opt_out_sha256 bytea unique,                       -- the in-call opt-out link the bot posts (fixed rule, §8.3)
  notice_state        text not null default 'pending' check (notice_state in ('not_required', 'pending', 'sent', 'blocked')),
  notice_due_at       timestamptz,
  notice_sent_at      timestamptz,
  notice_queued_at    timestamptz,
  activity_id         uuid unique references app.activities (id) on delete set null,
  deal_id             uuid references app.deals (id) on delete set null,
  lead_id             uuid references app.leads (id) on delete set null,
  person_id           uuid references app.people (id) on delete set null,
  organization_id     uuid references app.organizations (id) on delete set null,
  cancelled_at        timestamptz,
  owner_id            uuid references app.admins (id) on delete set null,
  visibility          text not null default 'owner' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  is_sample           boolean not null default false,
  version             int not null default 1,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  updated_at          timestamptz not null default now(),
  updated_by          uuid,
  deleted_at          timestamptz,
  unique (calendar_staff_id, external_event_id),
  check (ends_at is null or starts_at is null or ends_at >= starts_at),
  check ((bot_state = 'blocked') = (bot_block_reason is not null)),
  check (source <> 'calendar' or external_event_id is not null),
  check (notice_state <> 'sent' or notice_sent_at is not null)
);
create index meetings_starts on app.meetings (starts_at) where deleted_at is null;
create index meetings_owner on app.meetings (owner_id) where deleted_at is null;
create index meetings_deal on app.meetings (deal_id);
create index meetings_lead on app.meetings (lead_id);
create index meetings_person on app.meetings (person_id);
create index meetings_org on app.meetings (organization_id);
create index meetings_notice_due on app.meetings (notice_due_at) where notice_state = 'pending';

create table app.meeting_attendees (
  meeting_id           uuid not null references app.meetings (id) on delete cascade,
  email                text not null check (email = lower(email) and char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+$'),
  name                 text check (name is null or char_length(name) <= 200),
  person_id            uuid references app.people (id) on delete set null,
  staff_id             uuid references app.admins (id) on delete set null,
  external             boolean not null default true,
  response             text not null default 'needs_action' check (response in ('needs_action', 'accepted', 'tentative', 'declined')),
  notice_sent_at       timestamptz,
  opt_out_token_sha256 bytea unique,
  opted_out_at         timestamptz,
  primary key (meeting_id, email),
  check (not (external and staff_id is not null))
);
create index meeting_attendees_person on app.meeting_attendees (person_id);
create index meeting_attendees_staff on app.meeting_attendees (staff_id);
create index meeting_attendees_email on app.meeting_attendees (email);

-- «never record me»: the SHA-256 of the lower-cased address; kept through erasure (that is the point of it)
create table app.recording_opt_outs (
  email_sha256 bytea primary key,
  via          text not null check (via in ('notice_link', 'staff')),
  created_at   timestamptz not null default now()
);

create table app.meeting_recordings (
  id                        uuid primary key default gen_random_uuid(),
  meeting_id                uuid not null references app.meetings (id) on delete cascade,
  method                    text not null check (method in ('bot', 'desktop')),
  provider                  text check (provider is null or char_length(provider) between 1 and 40),
  provider_ref              text check (provider_ref is null or char_length(provider_ref) <= 500),
  storage_path              text unique check (storage_path is null or char_length(storage_path) <= 500),
  duration_s                int check (duration_s is null or duration_s >= 0),
  started_at                timestamptz,
  ended_at                  timestamptz,
  participants_confirmed_at timestamptz,                 -- desktop capture: the user confirmed participants were told (MTG-03)
  state                     text not null check (state in ('recording', 'processing', 'ready', 'failed', 'deleted')),
  error_code                text check (error_code is null or error_code ~ '^[a-z_]{1,80}$'),
  purge_after               timestamptz,
  created_at                timestamptz not null default now(),
  deleted_at                timestamptz,
  check ((state = 'deleted') = (deleted_at is not null)),
  check (state = 'deleted' or storage_path is not null),
  check (method <> 'desktop' or participants_confirmed_at is not null)
);
create index meeting_recordings_meeting on app.meeting_recordings (meeting_id);
create index meeting_recordings_purge on app.meeting_recordings (purge_after) where state <> 'deleted';

create table app.meeting_transcripts (
  id            uuid primary key default gen_random_uuid(),
  meeting_id    uuid not null references app.meetings (id) on delete cascade,
  recording_id  uuid references app.meeting_recordings (id) on delete set null,
  source        text not null check (source in ('provider', 'upload')),
  language      text check (language is null or char_length(language) between 2 and 20),
  duration_s    int check (duration_s is null or duration_s >= 0),
  speaker_count smallint check (speaker_count is null or speaker_count >= 0),
  state         text not null default 'processing' check (state in ('processing', 'ready', 'failed')),
  error_code    text check (error_code is null or error_code ~ '^[a-z_]{1,80}$'),
  file_name     text check (file_name is null or char_length(file_name) <= 255),
  uploaded_by   uuid references app.admins (id) on delete set null,
  provider      text check (provider is null or char_length(provider) between 1 and 40),
  created_at    timestamptz not null default now(),
  ready_at      timestamptz,
  check ((state = 'ready') = (ready_at is not null))
);
create index meeting_transcripts_meeting on app.meeting_transcripts (meeting_id, created_at desc);

create table app.transcript_speakers (
  transcript_id uuid not null references app.meeting_transcripts (id) on delete cascade,
  label         text not null check (char_length(btrim(label)) between 1 and 120),
  staff_id      uuid references app.admins (id) on delete set null,
  person_id     uuid references app.people (id) on delete set null,
  email         text check (email is null or (email = lower(email) and char_length(email) <= 254)),
  primary key (transcript_id, label),
  check (num_nonnulls(staff_id, person_id) <= 1)
);
create index transcript_speakers_person on app.transcript_speakers (person_id);

-- the words: fixed once written; erasure may only replace a segment's text with «[removed]»; a segment goes only
-- with its transcript
create table app.transcript_segments (
  transcript_id uuid not null references app.meeting_transcripts (id) on delete cascade,
  seq           int not null check (seq >= 1),
  start_ms      int not null check (start_ms >= 0),
  end_ms        int check (end_ms is null or end_ms >= start_ms),
  speaker_label text check (speaker_label is null or char_length(speaker_label) <= 120),
  text          text not null check (char_length(text) between 1 and 4000),
  redacted_at   timestamptz,
  primary key (transcript_id, seq)
);

-- the pre-call brief (MTG-01): facts computed from records with their source, AI quotes only as verbatim excerpts
create table app.meeting_briefs (
  meeting_id      uuid primary key references app.meetings (id) on delete cascade,
  state           text not null default 'pending' check (state in ('pending', 'ready', 'failed')),
  generated_at    timestamptz,
  since_at        timestamptz,
  last_contact_at timestamptz,
  changes         jsonb not null default '[]'::jsonb check (jsonb_typeof(changes) = 'array'),
  people          jsonb not null default '[]'::jsonb check (jsonb_typeof(people) = 'array'),
  facts           jsonb not null default '[]'::jsonb check (jsonb_typeof(facts) = 'array'),
  quotes          jsonb not null default '[]'::jsonb check (jsonb_typeof(quotes) = 'array' and jsonb_array_length(quotes) <= 10),
  quotes_state    text not null default 'none' check (quotes_state in ('none', 'requested', 'ready', 'not_connected', 'failed')),
  ai_call_id      bigint references app.ai_calls (id) on delete set null
);

create table app.meeting_brief_checks (
  meeting_id uuid not null references app.meetings (id) on delete cascade,
  item_key   text not null check (item_key ~ '^[a-z]{3}:[A-Za-z0-9:_.-]{1,76}$'),
  staff_id   uuid not null references app.admins (id) on delete cascade,
  checked_at timestamptz not null default now(),
  primary key (meeting_id, item_key, staff_id)
);

create table app.meeting_recaps (
  transcript_id uuid primary key references app.meeting_transcripts (id) on delete cascade,
  meeting_id    uuid not null references app.meetings (id) on delete cascade,
  state         text not null check (state in ('requested', 'ready', 'failed', 'not_connected')),
  takeaways     jsonb not null default '[]'::jsonb check (jsonb_typeof(takeaways) = 'array' and jsonb_array_length(takeaways) <= 20),
  next_steps    jsonb not null default '[]'::jsonb check (jsonb_typeof(next_steps) = 'array' and jsonb_array_length(next_steps) <= 20),
  ai_call_id    bigint references app.ai_calls (id) on delete set null,
  requested_at  timestamptz not null default now(),
  generated_at  timestamptz,
  note_id       uuid references app.notes (id) on delete set null,
  saved_by      uuid references app.admins (id) on delete set null,
  saved_at      timestamptz,
  announced_at  timestamptz,
  check (saved_at is null or state = 'ready')
);
create index meeting_recaps_meeting on app.meeting_recaps (meeting_id);

create table app.meeting_suggestions (
  id                uuid primary key default gen_random_uuid(),
  meeting_id        uuid not null references app.meetings (id) on delete cascade,
  transcript_id     uuid not null references app.meeting_transcripts (id) on delete cascade,
  ord               int not null default 0,
  target_entity     text not null check (target_entity in ('deal', 'lead', 'person', 'organization')),
  target_id         uuid,                                                    -- null with field «*new»: a new person
  field             text not null check (field ~ '^(custom\.[a-z][a-z0-9_]{1,40}|labels|\*new|[a-z_][a-z0-9_]{0,40})$'),
  current_value     jsonb,
  base_version      int,
  proposed_value    jsonb not null,
  evidence          int[] not null default '{}',
  state             text not null default 'pending' check (state in ('pending', 'accepted', 'rejected', 'stale', 'failed')),
  error_code        text check (error_code is null or char_length(error_code) <= 80),
  decided_by        uuid references app.admins (id) on delete set null,
  decided_at        timestamptz,
  written_record_id uuid,
  created_at        timestamptz not null default now(),
  check ((field = '*new') = (target_id is null)),
  check (field <> '*new' or target_entity = 'person'),
  check ((state = 'pending') = (decided_at is null))
);
create index meeting_suggestions_transcript on app.meeting_suggestions (transcript_id, ord);
create index meeting_suggestions_meeting on app.meeting_suggestions (meeting_id) where state = 'pending';

-- the per-user switch and choices (MTG-08, MTG-01 RU, MTG-02): no row = on, auto-join external, no instructions, own mailbox
create table app.meeting_user_settings (
  staff_id           uuid primary key references app.admins (id) on delete cascade,
  enabled            boolean not null default true,
  bot_auto_join      text not null default 'external' check (bot_auto_join in ('external', 'all', 'off')),
  brief_instructions text check (brief_instructions is null or char_length(brief_instructions) <= 2000),
  mailbox_id         uuid references app.mailboxes (id) on delete set null,
  updated_by         uuid,
  updated_at         timestamptz not null default now()
);

-- an uploaded transcript file: parsed by the worker, then deleted from storage (bucket «meeting-files»)
create table app.meeting_uploads (
  id            uuid primary key default gen_random_uuid(),
  meeting_id    uuid not null references app.meetings (id) on delete cascade,
  transcript_id uuid references app.meeting_transcripts (id) on delete set null,
  storage_path  text not null unique check (char_length(storage_path) <= 500),
  filename      text not null check (char_length(btrim(filename)) between 1 and 255),
  mime          text not null check (mime in ('text/vtt', 'application/x-subrip', 'text/plain',
                                              'application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size_bytes    int not null check (size_bytes between 1 and 5242880),
  state         text not null default 'pending' check (state in ('pending', 'uploaded', 'parsed', 'failed')),
  uploaded_by   uuid references app.admins (id) on delete set null,
  created_at    timestamptz not null default now(),
  parsed_at     timestamptz
);
create index meeting_uploads_meeting on app.meeting_uploads (meeting_id);

-- ===========================================================================
-- guards
-- ===========================================================================
create function app.ai_call_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if coalesce(current_setting('app.purging', true), '') = 'on' then return old; end if;
  elsif (to_jsonb(new) - 'staff_id') = (to_jsonb(old) - 'staff_id') and new.staff_id is null
        and not exists (select 1 from app.admins a where a.id = old.staff_id) then
    return new;
  end if;
  raise exception 'the AI call log is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger ai_call_fixed before update or delete on app.ai_calls for each row execute function app.ai_call_fixed();

create function app.recording_opt_out_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  raise exception 'an opt-out is kept' using errcode = 'insufficient_privilege';
end $fn$;
create trigger recording_opt_out_fixed before update or delete on app.recording_opt_outs for each row execute function app.recording_opt_out_fixed();

create function app.transcript_segment_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from app.meeting_transcripts t where t.id = old.transcript_id) then return old; end if;
  elsif new.transcript_id = old.transcript_id and new.seq = old.seq and new.start_ms = old.start_ms and new.end_ms is not distinct from old.end_ms
        and new.speaker_label is not distinct from old.speaker_label
        and ((new.text = old.text and new.redacted_at is not distinct from old.redacted_at)
             or (old.redacted_at is null and new.redacted_at is not null and new.text = '[removed]')) then
    return new;
  end if;
  raise exception 'a transcript is fixed' using errcode = 'insufficient_privilege';
end $fn$;
create trigger transcript_segment_fixed before update or delete on app.transcript_segments for each row execute function app.transcript_segment_fixed();

-- a meeting whose linked records were all purged goes with them (spec Q12: transcripts live as long as the linked
-- record). Only the purge (app.purging) empties a link this way; a user's unlink does not delete anything.
create function app.meeting_link_purged() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if coalesce(current_setting('app.purging', true), '') = 'on' and new.deleted_at is null
     and num_nonnulls(old.deal_id, old.lead_id, old.person_id, old.organization_id) > 0
     and num_nonnulls(new.deal_id, new.lead_id, new.person_id, new.organization_id) = 0 then
    new.deleted_at := now();
  end if;
  return new;
end $fn$;
create trigger meeting_link_purged before update of deal_id, lead_id, person_id, organization_id on app.meetings
  for each row execute function app.meeting_link_purged();

-- ===========================================================================
-- the generic record save (0006) with the source «meeting» (spec §9.10); nothing else changed
-- ===========================================================================
create or replace function public.rec_save(p_entity text, p_id uuid, p_values jsonb, p_version int default null,
                                p_reason text default null, p_source text default 'ui')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid;
  v_sandbox boolean;
  v_old jsonb; v_new jsonb;
  k text; v jsonb; kind text; w boolean;
  v_cols text[] := '{}'; v_vals text[] := '{}'; v_sets text[] := '{}';
  v_id uuid; v_changed text[] := '{}'; v_req record;
  v_source text := coalesce(p_source, 'ui');
  v_has_edited boolean;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end if;
  if v_source not in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'meeting') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
  end if;
  v_me := app.require(e.scope, case when p_id is null then 'add' else 'see' end);
  v_sandbox := (select sandbox from app.admins where id = v_me);
  perform app.take_reason(p_reason);
  v_has_edited := exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name = e.tbl and c.column_name = 'edited_fields');

  if p_id is not null then
    execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null and %s for update', e.tbl, p_id, app.vis_sql(e)) into v_old;
    if v_old is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and (v_old ->> 'version')::int <> p_version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = v_old ->> 'version';
    end if;
    if e.owned and (v_old ->> 'owner_id') is distinct from v_me::text and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
    if not e.owned and not app.can(e.scope, 'add') and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
  end if;

  for k, v in select * from jsonb_each(p_values) loop
    if k = 'custom' then
      perform app.check_custom(e.key, v);
      if p_id is null then
        v_cols := v_cols || 'custom'::text; v_vals := v_vals || format('jsonb_strip_nulls(%L::jsonb)', v::text);
      else
        v_sets := v_sets || format('custom = jsonb_strip_nulls(t.custom || %L::jsonb)', v::text);
      end if;
      continue;
    elsif k in ('owner_id', 'visibility') and e.owned then
      kind := case k when 'owner_id' then 'uuid' else 'text' end; w := true;
      if k = 'owner_id' and jsonb_typeof(v) = 'string' and not exists (select 1 from app.admins a where a.id::text = v #>> '{}' and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id';
      end if;
    elsif k = 'labels' then
      kind := 'uuid[]'; w := true;
      if exists (select 1 from jsonb_array_elements_text(v) x where not exists (select 1 from app.labels l where l.id::text = x and l.entity = e.key)) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'labels';
      end if;
    else
      select c.kind, c.writable into kind, w from app.entity_columns c where c.entity = e.key and c.col = k;
      if kind is null or not w then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
    end if;
    if p_id is null then
      v_cols := v_cols || k; v_vals := v_vals || app.lit(v, kind);
    else
      v_sets := v_sets || format('%I = %s', k, app.lit(v, kind));
    end if;
  end loop;

  if p_id is null then
    -- required columns and required custom fields on create
    for v_req in select c.col from app.entity_columns c where c.entity = e.key and c.required loop
      if coalesce(btrim(p_values ->> v_req.col), '') = '' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_req.col || ':required';
      end if;
    end loop;
    for v_req in select f.key from app.fields f where f.entity = e.key and f.quality = 'required' and f.from_stage_id is null and f.archived_at is null loop
      if jsonb_typeof(p_values #> array['custom', v_req.key]) is null or jsonb_typeof(p_values #> array['custom', v_req.key]) = 'null' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || v_req.key || ':required';
      end if;
    end loop;
    if e.owned and not (p_values ? 'owner_id') then v_cols := v_cols || 'owner_id'::text; v_vals := v_vals || quote_literal(v_me); end if;
    if e.owned and not (p_values ? 'visibility') then
      v_cols := v_cols || 'visibility'::text; v_vals := v_vals || quote_literal(app.setting('visibility_default', e.key));
    end if;
    v_cols := v_cols || array['created_by', 'updated_by', 'is_sample'];
    v_vals := v_vals || array[quote_literal(v_me), quote_literal(v_me), quote_literal(v_sandbox)];
    if v_has_edited and v_source = 'ui' then
      v_cols := v_cols || 'edited_fields'::text; v_vals := v_vals || app.lit(to_jsonb(array(select jsonb_object_keys(p_values))), 'text[]');
    end if;
    execute format('insert into app.%I as t (%s) values (%s) returning to_jsonb(t)', e.tbl,
                   (select string_agg(format('%I', c), ', ') from unnest(v_cols) c), array_to_string(v_vals, ', ')) into v_new;
    v_id := (v_new ->> 'id')::uuid;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
    values (e.key, v_id, '*created', null, null, v_me, v_source);
    perform app.log('record.created', e.key, v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
    perform app.emit(e.key || '.created', e.key, v_id, '{}'::jsonb, v_sandbox);
    return jsonb_build_object('id', v_id, 'version', 1);
  end if;

  if cardinality(v_sets) = 0 then
    return jsonb_build_object('id', p_id, 'version', (v_old ->> 'version')::int);
  end if;
  v_sets := v_sets || array['version = t.version + 1', 'updated_at = now()', format('updated_by = %L', v_me)];
  if v_has_edited and v_source = 'ui' then
    v_sets := v_sets || format('edited_fields = array(select distinct x from unnest(t.edited_fields || %s) x)',
                               app.lit(to_jsonb(array(select jsonb_object_keys(p_values - 'custom'))), 'text[]'));
  end if;
  execute format('update app.%I as t set %s where t.id = %L returning to_jsonb(t)', e.tbl, array_to_string(v_sets, ', '), p_id) into v_new;

  -- the history: one row per field whose value changed
  for k in select jsonb_object_keys(p_values) loop
    if k = 'custom' then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      select e.key, p_id, 'custom.' || ck, v_old #> array['custom', ck], v_new #> array['custom', ck], v_me, v_source
      from jsonb_object_keys(p_values -> 'custom') ck
      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]);
      v_changed := v_changed || array(select 'custom.' || ck from jsonb_object_keys(p_values -> 'custom') ck
                                      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]));
    elsif (v_old -> k) is distinct from (v_new -> k) then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      values (e.key, p_id, k, v_old -> k, v_new -> k, v_me, v_source);
      v_changed := v_changed || k;
    end if;
  end loop;
  perform app.log('record.updated', e.key, p_id::text, jsonb_build_object('fields', to_jsonb(v_changed)));
  if cardinality(v_changed) > 0 then
    perform app.emit(e.key || '.updated', e.key, p_id, jsonb_build_object('fields', to_jsonb(v_changed)), (v_new ->> 'is_sample')::boolean);
  end if;
  return jsonb_build_object('id', p_id, 'version', (v_new ->> 'version')::int);
end $fn$;

-- ===========================================================================
-- helpers
-- ===========================================================================
-- the workspace (MTG-08, spec §4): «deals:see», the module, and the caller's own switch (no row = on)
create function app.mtg_require() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.require('deals', 'see');
begin
  perform app.require_module('meetings');
  if not coalesce((select s.enabled from app.meeting_user_settings s where s.staff_id = v), true) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'meetings:disabled';
  end if;
  return v;
end $fn$;

-- may the caller see this meeting: its visibility, or they were invited (spec §5)
create function app.mtg_visible(m app.meetings) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.me() is not null and (app.visible(m.owner_id, m.visibility)
         or exists (select 1 from app.meeting_attendees a where a.meeting_id = m.id and a.staff_id = app.me()))
$fn$;

-- one meeting the caller may see, through the workspace gate, or not_found
create function app.mtg_get(p_id uuid, p_lock boolean default false) returns app.meetings
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings;
begin
  perform app.mtg_require();
  if p_lock then
    select * into m from app.meetings where id = p_id and deleted_at is null for update;
  else
    select * into m from app.meetings where id = p_id and deleted_at is null;
  end if;
  if not found or not app.mtg_visible(m) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return m;
end $fn$;

-- the owner, or «Edit others' records» in deals (link, remove the bot, delete a recording, map speakers: spec §5)
create function app.mtg_can_edit(m app.meetings) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select (app.me() is not null and m.owner_id is not distinct from app.me()) or app.can('deals', 'edit_others')
$fn$;

create function app.mtg_require_edit(m app.meetings) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not app.mtg_can_edit(m) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
end $fn$;

-- rec_notice: hours before the start the notice goes out; null = no advance email (the in-call disclosure stays)
create function app.mtg_notice_hours() returns int
  language sql stable security definer set search_path = ''
as $fn$
  select case app.setting('rec_notice')
           when 'off' then null
           when 'custom' then greatest(0, least(168, coalesce((select v.value_number from app.setting_values v where v.key = 'rec_notice' and v.scope_id = '')::int, 24)))
           else 24 end
$fn$;

-- rec_retention: how long audio is kept; null = kept (transcripts follow the meeting, spec Q12)
create function app.mtg_retention_months() returns int
  language sql stable security definer set search_path = ''
as $fn$
  select case app.setting('rec_retention')
           when 'keep' then null
           when 'custom' then greatest(1, least(120, coalesce((select v.value_number from app.setting_values v where v.key = 'rec_retention' and v.scope_id = '')::int, 12)))
           else 12 end
$fn$;

create function app.mtg_retention() returns interval
  language sql stable security definer set search_path = ''
as $fn$ select make_interval(months => app.mtg_retention_months()) $fn$;

-- a new meeting's visibility: «owner» (spec Q13, an exception to D-16), unless visibility_default is set for «meeting»
create function app.mtg_visibility_default() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select v.value from app.setting_values v where v.key = 'visibility_default' and v.scope_id = 'meeting'), 'owner')
$fn$;

-- the controller named in a notice: the sender of the transactional stream (art. 13); none → no notice can go out
create function app.mtg_controller() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select d.from_name from app.sender_domains d
  where d.stream = 'transactional' and d.sends_here and d.verified_at is not null and d.deleted_at is null
  order by d.created_at limit 1
$fn$;

create function app.mtg_user(p_staff uuid) returns app.meeting_user_settings
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select s from app.meeting_user_settings s where s.staff_id = p_staff),
                  row(p_staff, true, 'external', null, null, null, now())::app.meeting_user_settings)
$fn$;

create function app.mtg_has_external(p_meeting uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select exists (select 1 from app.meeting_attendees a where a.meeting_id = p_meeting and a.external) $fn$;

-- somebody invited said no: for this meeting, or «never record me»
create function app.mtg_opted_out(p_meeting uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.meeting_attendees a where a.meeting_id = p_meeting
                 and (a.opted_out_at is not null or exists (select 1 from app.recording_opt_outs o where o.email_sha256 = app.email_hash(a.email))))
$fn$;

-- why the bot may not record this meeting, or null (§2.7 «Bot scheduling», §8.3). p_at_join: the notice must be out.
create function app.mtg_bot_block(m app.meetings, p_at_join boolean) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare u app.meeting_user_settings := app.mtg_user(m.owner_id);
begin
  if not app.module_on('meetings') or m.owner_id is null or not u.enabled
     or not exists (select 1 from app.admins a where a.id = m.owner_id and a.active) then return 'disabled'; end if;
  if m.join_url is null then return 'no_link'; end if;
  if not app.mtg_has_external(m.id) and u.bot_auto_join <> 'all' then return 'internal_only'; end if;
  if app.mtg_opted_out(m.id) then return 'opted_out'; end if;
  if not app.connected('meeting_bot') then return 'not_connected'; end if;
  if m.notice_state = 'blocked' or (p_at_join and m.notice_state = 'pending') then return 'notice_not_sent'; end if;
  return null;
end $fn$;

-- recompute a meeting's notice and bot plan from the register, its attendees and its capture choice
create function app.mtg_refresh(p_id uuid) returns app.meetings
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; v_hours int := app.mtg_notice_hours(); v_required boolean; v_reason text; v_due timestamptz;
begin
  select * into m from app.meetings where id = p_id for update;
  if not found then return m; end if;
  v_required := m.capture = 'bot' and v_hours is not null and m.starts_at is not null and m.cancelled_at is null and m.deleted_at is null
                and app.mtg_has_external(m.id);
  if not v_required then
    if m.notice_state <> 'sent' then m.notice_state := 'not_required'; m.notice_due_at := null; end if;
  elsif not exists (select 1 from app.meeting_attendees a where a.meeting_id = m.id and a.external and a.notice_sent_at is null) then
    m.notice_state := 'sent';
    m.notice_sent_at := coalesce(m.notice_sent_at, (select max(a.notice_sent_at) from app.meeting_attendees a where a.meeting_id = m.id and a.external));
  else
    v_due := case when v_hours = 0 then coalesce(m.notice_due_at, now()) else m.starts_at - make_interval(hours => v_hours) end;
    if m.notice_state <> 'blocked' or v_due > now() then
      m.notice_state := 'pending'; m.notice_due_at := v_due;
    end if;
  end if;
  if m.capture = 'bot' and m.cancelled_at is null and m.deleted_at is null and m.starts_at > now() and m.bot_state in ('none', 'scheduled', 'blocked') then
    v_reason := app.mtg_bot_block(m, false);
    m.bot_state := case when v_reason is null then 'scheduled' else 'blocked' end;
    m.bot_block_reason := v_reason;
  elsif (m.capture <> 'bot' or m.cancelled_at is not null or m.deleted_at is not null) and m.bot_state in ('scheduled', 'blocked') then
    m.bot_state := 'none'; m.bot_block_reason := null;
  end if;
  update app.meetings set notice_state = m.notice_state, notice_due_at = m.notice_due_at, notice_sent_at = m.notice_sent_at,
    bot_state = m.bot_state, bot_block_reason = m.bot_block_reason
  where id = m.id;
  return m;
end $fn$;

-- refresh every future meeting of one owner (their switch or auto-join choice changed)
create function app.mtg_refresh_owner(p_staff uuid) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  for r in select id from app.meetings where owner_id = p_staff and starts_at > now() and deleted_at is null and cancelled_at is null loop
    perform app.mtg_refresh(r.id); n := n + 1;
  end loop;
  return n;
end $fn$;

-- is a record of a linkable type there and visible to the caller (module and deleted checked)
create function app.mtg_target_ok(p_entity text, p_id uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v boolean;
begin
  if p_id is null then return false; end if;
  e := app.entity(p_entity);
  execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, p_id, app.vis_sql(e)) into v;
  return coalesce(v, false);
end $fn$;

-- the meeting's links as the caller may see them, and the primary for «Linked to» (deal → lead → person → organization)
create function app.mtg_links(m app.meetings) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with l as (
    select (select jsonb_build_object('entity', 'deal', 'id', d.id, 'title', d.title, 'seq', d.seq) from app.deals d
            where d.id = m.deal_id and d.deleted_at is null and app.visible(d.owner_id, d.visibility)) deal,
           (select jsonb_build_object('entity', 'lead', 'id', x.id, 'title', x.title, 'seq', x.seq) from app.leads x
            where x.id = m.lead_id and x.deleted_at is null and app.visible(x.owner_id, x.visibility)) lead,
           (select jsonb_build_object('entity', 'person', 'id', p.id, 'title', p.name) from app.people p
            where p.id = m.person_id and p.deleted_at is null and app.visible(p.owner_id, p.visibility)) person,
           (select jsonb_build_object('entity', 'organization', 'id', o.id, 'title', o.name) from app.organizations o
            where o.id = m.organization_id and o.deleted_at is null and app.visible(o.owner_id, o.visibility)) organization)
  select jsonb_build_object('deal', l.deal, 'lead', l.lead, 'person', l.person, 'organization', l.organization,
                            'primary', coalesce(l.deal, l.lead, l.person, l.organization),
                            'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0)
  from l
$fn$;

-- the newest transcript of a meeting
create function app.mtg_transcript(p_meeting uuid) returns app.meeting_transcripts
  language sql stable security definer set search_path = ''
as $fn$ select t from app.meeting_transcripts t where t.meeting_id = p_meeting order by t.created_at desc, t.id limit 1 $fn$;

-- the label the list and the header show (§2.1), derived in this order; never stored
create function app.mtg_state(m app.meetings) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts := app.mtg_transcript(m.id); r app.meeting_recaps; n int; v_up boolean := m.starts_at > now() and m.cancelled_at is null;
begin
  if t.id is not null then select * into r from app.meeting_recaps where transcript_id = t.id; end if;
  n := (select count(*) from app.meeting_suggestions s where s.transcript_id = t.id and s.state = 'pending');
  return case
    when m.cancelled_at is not null then jsonb_build_object('key', 'cancelled')
    when m.bot_state = 'blocked' then jsonb_build_object('key', 'recording_blocked', 'reason', m.bot_block_reason)
    when v_up and m.notice_state = 'pending' then jsonb_build_object('key', 'notice_due', 'at', m.notice_due_at)
    when v_up and m.bot_state = 'scheduled' then jsonb_build_object('key', 'bot_joins')
    when m.bot_state in ('joining', 'in_call') then jsonb_build_object('key', 'bot_in_call')
    when t.state = 'processing' then jsonb_build_object('key', 'processing')
    when t.state = 'failed' then jsonb_build_object('key', 'transcription_failed', 'reason', t.error_code)
    when n > 0 then jsonb_build_object('key', 'suggestions', 'n', n)
    when r.saved_at is not null then jsonb_build_object('key', 'recap_saved')
    when r.state = 'ready' then jsonb_build_object('key', 'recap_ready')
    when t.state = 'ready' then jsonb_build_object('key', 'transcript_ready')
    else null end;
end $fn$;

-- the list group (§2.1): upcoming, needs your review, history
create function app.mtg_group(m app.meetings) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts := app.mtg_transcript(m.id);
begin
  if m.starts_at > now() and m.cancelled_at is null then return 'upcoming'; end if;
  if t.state = 'ready' and (exists (select 1 from app.meeting_suggestions s where s.transcript_id = t.id and s.state = 'pending')
                            or exists (select 1 from app.meeting_recaps r where r.transcript_id = t.id and r.state = 'ready' and r.saved_at is null)) then
    return 'review';
  end if;
  return 'history';
end $fn$;

-- a list row (§2.1): when, state, title, org · via, attendees, the link
create function app.mtg_row(m app.meetings) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', m.id, 'title', m.title, 'at', coalesce(m.starts_at, m.created_at), 'starts_at', m.starts_at, 'ends_at', m.ends_at,
    'source', m.source, 'conference', m.conference, 'capture', m.capture, 'group', app.mtg_group(m), 'state', app.mtg_state(m),
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o
                     where o.id = coalesce(m.organization_id, (select d.organization_id from app.deals d where d.id = m.deal_id),
                                           (select x.organization_id from app.leads x where x.id = m.lead_id),
                                           (select p.organization_id from app.people p where p.id = m.person_id))
                       and o.deleted_at is null and app.visible(o.owner_id, o.visibility)),
    'attendees', (select jsonb_build_object('first', (array_agg(coalesce(p.name, a.name, split_part(a.email, '@', 1)) order by a.external desc, coalesce(p.name, a.name, a.email)))[1],
                                            'others', greatest(count(*) - 1, 0), 'total', count(*), 'external', count(*) filter (where a.external))
                  from app.meeting_attendees a left join app.people p on p.id = a.person_id and p.deleted_at is null
                  where a.meeting_id = m.id and (a.staff_id is null or a.staff_id is distinct from m.owner_id)),
    'link', app.mtg_links(m) -> 'primary', 'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0,
    'owner', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = m.owner_id),
    'is_sample', m.is_sample, 'version', m.version)
$fn$;

-- the providers as the workspace shows them (§4 capabilities)
create function app.mtg_capabilities() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'calendar', coalesce((select c.status from app.calendar_connections c where c.staff_id = app.me()), 'not_connected'),
    'meeting_bot', (select c.status from app.integration_connections c where c.provider = 'meeting_bot'),
    'transcription', (select c.status from app.integration_connections c where c.provider = 'transcription'),
    'ai', (select c.status from app.integration_connections c where c.provider = 'ai'),
    'email', (select c.status from app.integration_connections c where c.provider = 'email'),
    'slack', (select c.status from app.integration_connections c where c.provider = 'slack'),
    'desktop', 'not_available')
$fn$;

-- a source a brief item cites, still there and visible to the caller
create function app.mtg_source_visible(p_source jsonb) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_entity text := p_source ->> 'entity'; v_id uuid;
begin
  if p_source is null or v_entity is null then return true; end if;
  v_id := (p_source ->> 'id')::uuid;
  if v_entity = 'ticket' then
    return exists (select 1 from app.tickets t where t.id = v_id and t.deleted_at is null) and app.can('tickets', 'see');
  end if;
  if v_entity not in ('deal', 'lead', 'person', 'organization') then return false; end if;
  return app.mtg_target_ok(v_entity, v_id);
end $fn$;

-- the queued deletion of storage objects in the private bucket «meeting-files»
create function app.mtg_storage_forget(p_paths text[]) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if cardinality(array_remove(p_paths, null)) > 0 then
    perform pgmq.send('jobs', jsonb_build_object('job', 'files_purge', 'bucket', 'meeting-files', 'paths', to_jsonb(array_remove(p_paths, null))));
  end if;
end $fn$;

-- the people around a meeting: external attendees known to the CRM and the linked person
create function app.mtg_people(m app.meetings) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(distinct x), '{}') from (
    select a.person_id x from app.meeting_attendees a where a.meeting_id = m.id and a.external and a.person_id is not null
    union all select m.person_id
    union all select d.person_id from app.deals d where d.id = m.deal_id
    union all select l.person_id from app.leads l where l.id = m.lead_id) s
  where x is not null
$fn$;

create function app.mtg_orgs(m app.meetings) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(distinct x), '{}') from (
    select m.organization_id x
    union all select d.organization_id from app.deals d where d.id = m.deal_id
    union all select l.organization_id from app.leads l where l.id = m.lead_id
    union all select p.organization_id from app.people p where p.id = any (app.mtg_people(m))) s
  where x is not null
$fn$;

-- the records a suggestion may target (A7.10: a transcript can never point a write at an arbitrary record)
create function app.mtg_targets(m app.meetings) returns table (entity text, id uuid)
  language sql stable security definer set search_path = ''
as $fn$
  select 'deal', m.deal_id where m.deal_id is not null
  union select 'lead', m.lead_id where m.lead_id is not null
  union select 'person', x from unnest(app.mtg_people(m)) x
  union select 'organization', x from unnest(app.mtg_orgs(m)) x
$fn$;

-- a staff member's meeting settings as Workspace and controls shows them; «own» = their personal mailbox
create function app.mtg_user_row(p_staff uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', a.id, 'name', a.name, 'title', a.title, 'initials', a.initials, 'enabled', u.enabled, 'bot_auto_join', u.bot_auto_join,
    'mailbox', case when u.mailbox_id is not null then (select jsonb_build_object('id', mb.id, 'address', mb.address, 'status', mb.status, 'kind', mb.kind, 'own', false)
                                                         from app.mailboxes mb where mb.id = u.mailbox_id and mb.deleted_at is null)
                    else (select jsonb_build_object('id', mb.id, 'address', mb.address, 'status', mb.status, 'kind', mb.kind, 'own', true)
                          from app.mailboxes mb where mb.owner_id = a.id and mb.kind = 'personal' and mb.deleted_at is null order by mb.created_at limit 1) end,
    'calendar', coalesce((select c.status from app.calendar_connections c where c.staff_id = a.id), 'not_connected'))
  from app.admins a cross join lateral (select (app.mtg_user(a.id)).*) u
  where a.id = p_staff
$fn$;

-- the value a suggestion's field holds now (null: the record is gone)
create function app.mtg_suggestion_current(s app.meeting_suggestions) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v jsonb;
begin
  if s.target_id is null then return null; end if;
  select * into e from app.entities where key = s.target_entity;
  execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null', e.tbl, s.target_id) into v;
  if v is null then return null; end if;
  return case when s.field like 'custom.%' then v -> 'custom' -> substr(s.field, 8) else v -> s.field end;
end $fn$;

-- ===========================================================================
-- the brief (MTG-01, spec §2.2, Q17): facts from records first, each with its source; AI only for verbatim quotes
-- ===========================================================================
-- last contact = the latest done activity, mail or earlier meeting touching the linked deal or lead or an external
-- attendee, before now. Items since then are {key, kind, params, source, at}, rendered from message keys, never prose.
create function app.mtg_brief_build(p_meeting uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  m app.meetings; v_people uuid[]; v_orgs uuid[]; v_last timestamptz; v_since timestamptz; v_changes jsonb; v_who jsonb; v_facts jsonb;
  v_quotes_state text;
begin
  select * into m from app.meetings where id = p_meeting and deleted_at is null;
  if not found then return; end if;
  v_people := app.mtg_people(m);
  v_orgs := app.mtg_orgs(m);
  v_last := greatest(
    (select max(coalesce(a.done_at, a.starts_at)) from app.activities a
     where a.done and a.deleted_at is null and coalesce(a.done_at, a.starts_at) < now() and a.id is distinct from m.activity_id
       and (a.deal_id = m.deal_id or a.lead_id = m.lead_id or a.person_id = any (v_people))),
    (select max(coalesce(em.received_at, em.sent_at)) from app.email_messages em
     where em.state in ('sent', 'received') and coalesce(em.received_at, em.sent_at) < now()
       and (em.person_id = any (v_people) or exists (select 1 from app.email_links el where el.thread_id = em.thread_id
              and ((el.entity = 'deal' and el.record_id = m.deal_id) or (el.entity = 'lead' and el.record_id = m.lead_id))))),
    (select max(o.starts_at) from app.meetings o
     where o.id <> m.id and o.deleted_at is null and o.cancelled_at is null and o.starts_at < least(now(), coalesce(m.starts_at, now()))
       and (o.deal_id = m.deal_id or o.lead_id = m.lead_id
            or exists (select 1 from app.meeting_attendees oa where oa.meeting_id = o.id and oa.person_id = any (v_people)))));
  v_since := coalesce(v_last, now() - interval '30 days');

  select coalesce(jsonb_agg(c order by c ->> 'at' desc), '[]'::jsonb) into v_changes from (
    -- field changes on the deal, the lead, the organisations and the people (a custom field included)
    (select jsonb_build_object('key', 'chg:' || l.id, 'kind', 'field_changed', 'at', l.at,
                               'params', jsonb_build_object('entity', l.entity, 'field', l.field, 'old', l.old_value, 'new', l.new_value),
                               'source', jsonb_build_object('entity', l.entity, 'id', l.record_id)) c
     from app.changelog l
     where l.at > v_since and l.field !~ '^\*' and l.field not like 'items.%'
       and ((l.entity = 'deal' and l.record_id = m.deal_id) or (l.entity = 'lead' and l.record_id = m.lead_id)
            or (l.entity = 'organization' and l.record_id = any (v_orgs)) or (l.entity = 'person' and l.record_id = any (v_people)))
     order by l.at desc limit 12)
    union all
    -- opens and clicks on mail to the people (prefetches excluded)
    select jsonb_build_object('key', 'trk:' || em.person_id, 'kind', 'email_engagement', 'at', max(t.at),
                              'params', jsonb_build_object('person', max(p.name), 'opens', count(*) filter (where t.kind = 'open'), 'clicks', count(*) filter (where t.kind = 'click')),
                              'source', jsonb_build_object('entity', 'person', 'id', em.person_id))
    from app.email_tracking_events t join app.email_messages em on em.id = t.message_id join app.people p on p.id = em.person_id
    where t.at > v_since and t.client_class <> 'prefetch' and em.person_id = any (v_people)
    group by em.person_id
    union all
    -- the organisations' tickets resolved since, with their CSAT
    select jsonb_build_object('key', 'tkt:' || k.id, 'kind', 'ticket_resolved', 'at', k.resolved_at,
                              'params', jsonb_build_object('number', k.number, 'csat', k.csat_score),
                              'source', jsonb_build_object('entity', 'ticket', 'id', k.id))
    from app.tickets k where k.organization_id = any (v_orgs) and k.resolved_at > v_since and k.deleted_at is null
    union all
    -- people added to the deal
    select jsonb_build_object('key', 'prt:' || dp.person_id, 'kind', 'participant_added', 'at', dp.added_at,
                              'params', jsonb_build_object('person', p.name), 'source', jsonb_build_object('entity', 'person', 'id', dp.person_id))
    from app.deal_participants dp join app.people p on p.id = dp.person_id
    where dp.deal_id = m.deal_id and dp.added_at > v_since
    union all
    -- product counts that changed (D-19: counts only)
    select jsonb_build_object('key', 'cnt:' || x.product || ':' || x.metric, 'kind', 'count_changed', 'at', x.day,
                              'params', jsonb_build_object('product', x.product, 'metric', x.metric, 'from', x.v_from, 'to', x.v_to),
                              'source', jsonb_build_object('entity', 'organization', 'id', x.org))
    from (select o.id org, ap.product, c.metric,
                 (select c2.value from app.product_counts_daily c2 where c2.product = ap.product and c2.tenant_id = ap.tenant_id and c2.metric = c.metric
                  and c2.day <= v_since::date order by c2.day desc limit 1) v_from,
                 (select c3.value from app.product_counts_daily c3 where c3.product = ap.product and c3.tenant_id = ap.tenant_id and c3.metric = c.metric
                  order by c3.day desc limit 1) v_to,
                 max(c.day) as day
          from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
          join app.product_counts_daily c on c.product = ap.product and c.tenant_id = ap.tenant_id and c.day > v_since::date
          where o.id = any (v_orgs) group by o.id, ap.product, ap.tenant_id, c.metric) x
    where x.v_from is not null and x.v_to is distinct from x.v_from) s;

  -- who you meet: external attendees, with what the CRM holds about them
  select coalesce(jsonb_agg(jsonb_build_object(
           'person_id', p.id, 'name', coalesce(p.name, a.name, split_part(a.email, '@', 1)), 'title', p.title,
           'labels', coalesce((select jsonb_agg(lb.name order by lb.ord) from app.labels lb where lb.id = any (p.labels)), '[]'::jsonb),
           'first_meeting', p.id is null or not (
              exists (select 1 from app.meeting_attendees oa join app.meetings o on o.id = oa.meeting_id
                      where oa.person_id = p.id and o.id <> m.id and o.deleted_at is null and o.starts_at < coalesce(m.starts_at, now()))
              or exists (select 1 from app.activities ac where ac.person_id = p.id and ac.done and ac.deleted_at is null)),
           'last_signed_in', (select mb.last_login_at from app.members mb
                              where mb.product = p.member_product and mb.tenant_id = p.member_tenant and mb.user_id = p.member_user),
           'source', case when p.id is not null then jsonb_build_object('entity', 'person', 'id', p.id) end)
         order by coalesce(p.name, a.name, a.email)), '[]'::jsonb)
  into v_who
  from app.meeting_attendees a left join app.people p on p.id = a.person_id and p.deleted_at is null
  where a.meeting_id = m.id and a.external;

  -- deal and organisation facts; a line is omitted when its value is null
  select coalesce(jsonb_agg(f order by f ->> 'ord'), '[]'::jsonb) into v_facts from (
    select jsonb_build_object('key', 'deal', 'ord', '1', 'params', jsonb_build_object('title', d.title, 'value', d.value, 'currency', d.currency,
                              'stage', (select s.name from app.stages s where s.id = d.stage_id), 'status', d.status),
                              'source', jsonb_build_object('entity', 'deal', 'id', d.id)) f
    from app.deals d where d.id = m.deal_id and d.deleted_at is null
    union all
    select jsonb_build_object('key', 'lead', 'ord', '1', 'params', jsonb_build_object('title', x.title, 'seq', x.seq, 'value', x.value, 'currency', x.currency),
                              'source', jsonb_build_object('entity', 'lead', 'id', x.id))
    from app.leads x where x.id = m.lead_id and m.deal_id is null and x.deleted_at is null
    union all
    select jsonb_build_object('key', 'score', 'ord', '2', 'params', jsonb_build_object('score', d.score), 'source', jsonb_build_object('entity', 'deal', 'id', d.id))
    from app.deals d where d.id = m.deal_id and d.deleted_at is null and d.score is not null
    union all
    select jsonb_build_object('key', 'score', 'ord', '2', 'params', jsonb_build_object('score', max(rs.score)), 'source', jsonb_build_object('entity', 'lead', 'id', m.lead_id))
    from app.record_scores rs where m.deal_id is null and rs.entity = 'lead' and rs.record_id = m.lead_id having max(rs.score) is not null
    union all
    select jsonb_build_object('key', 'health:' || h.product, 'ord', '3', 'params', jsonb_build_object('product', h.product, 'score', h.score, 'day', h.day),
                              'source', jsonb_build_object('entity', 'organization', 'id', o.id))
    from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
    join app.v_health_latest h on h.product = ap.product and h.tenant_id = ap.tenant_id
    where o.id = any (v_orgs) and h.score is not null
    union all
    select jsonb_build_object('key', 'applications', 'ord', '4', 'params', jsonb_build_object('products', jsonb_agg(distinct ap.product)),
                              'source', jsonb_build_object('entity', 'organization', 'id', min(o.id::text)::uuid))
    from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
    where o.id = any (v_orgs) having count(*) > 0
    union all
    select jsonb_build_object('key', 'custom.' || fd.key, 'ord', '5' || lpad(fd.ord::text, 4, '0'), 'params', jsonb_build_object('label', fd.label, 'value', d.custom -> fd.key),
                              'source', jsonb_build_object('entity', 'deal', 'id', d.id))
    from app.deals d join app.fields fd on fd.entity = 'deal' and fd.quality in ('important', 'required') and fd.archived_at is null
    where d.id = m.deal_id and d.deleted_at is null and jsonb_typeof(d.custom -> fd.key) is not null and jsonb_typeof(d.custom -> fd.key) <> 'null') s;

  -- quotes from earlier conversations need the AI provider; without it the card says so
  v_quotes_state := case when app.connected('ai') then 'requested' else 'not_connected' end;
  insert into app.meeting_briefs (meeting_id, state, generated_at, since_at, last_contact_at, changes, people, facts, quotes, quotes_state)
  values (m.id, 'ready', now(), v_since, v_last, v_changes, v_who, v_facts, '[]'::jsonb, v_quotes_state)
  on conflict (meeting_id) do update set state = 'ready', generated_at = now(), since_at = excluded.since_at, last_contact_at = excluded.last_contact_at,
    changes = excluded.changes, people = excluded.people, facts = excluded.facts,
    quotes = case when excluded.quotes_state = 'requested' then app.meeting_briefs.quotes else '[]'::jsonb end,
    quotes_state = excluded.quotes_state;
  if v_quotes_state = 'requested' then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_brief_quotes', 'meeting_id', m.id, 'staff_id', m.owner_id));
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.brief_built', 'meeting', m.id::text,
          jsonb_build_object('changes', jsonb_array_length(v_changes), 'people', jsonb_array_length(v_who), 'facts', jsonb_array_length(v_facts), 'quotes', v_quotes_state), true);
end $fn$;

-- ===========================================================================
-- transcripts: segments, speakers, the recap request
-- ===========================================================================
-- segments [{start_ms, end_ms?, speaker?, text}] in order; seq is their position. → the count
create function app.mtg_segments_store(p_transcript uuid, p_segments jsonb) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; i int := 0;
begin
  if jsonb_typeof(p_segments) is distinct from 'array' or jsonb_array_length(p_segments) not between 1 and 20000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'segments';
  end if;
  for x in select value from jsonb_array_elements(p_segments) loop
    if jsonb_typeof(x) <> 'object' or jsonb_typeof(x -> 'text') is distinct from 'string' or char_length(btrim(x ->> 'text')) not between 1 and 4000
       or jsonb_typeof(x -> 'start_ms') is distinct from 'number' or (x ->> 'start_ms') !~ '^\d{1,9}$'
       or (coalesce(jsonb_typeof(x -> 'end_ms'), 'null') <> 'null'
           and (jsonb_typeof(x -> 'end_ms') <> 'number' or (x ->> 'end_ms') !~ '^\d{1,9}$' or (x ->> 'end_ms')::bigint < (x ->> 'start_ms')::bigint))
       or coalesce(jsonb_typeof(x -> 'speaker'), 'null') not in ('string', 'null') or coalesce(char_length(btrim(x ->> 'speaker')), 0) > 120 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'segments[' || i || ']';
    end if;
    i := i + 1;
    insert into app.transcript_segments (transcript_id, seq, start_ms, end_ms, speaker_label, text)
    values (p_transcript, i, (x ->> 'start_ms')::int, (x ->> 'end_ms')::int, nullif(btrim(x ->> 'speaker'), ''), btrim(x ->> 'text'));
  end loop;
  insert into app.transcript_speakers (transcript_id, label)
  select distinct p_transcript, s.speaker_label from app.transcript_segments s where s.transcript_id = p_transcript and s.speaker_label is not null
  on conflict do nothing;
  return i;
end $fn$;

-- map speaker labels: provider hints [{label, email}], then an attendee, a staff member or a person by address, then
-- an attendee or the owner by exact name. Anything else stays the raw label for the owner to map.
create function app.mtg_speakers_map(p_transcript uuid, p_hints jsonb) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; v_meeting uuid := (select meeting_id from app.meeting_transcripts where id = p_transcript); v_owner uuid := (select owner_id from app.meetings where id = v_meeting);
begin
  if p_hints is not null and jsonb_typeof(p_hints) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'speakers'; end if;
  for x in select value from jsonb_array_elements(coalesce(p_hints, '[]'::jsonb)) loop
    if jsonb_typeof(x) <> 'object' or coalesce(x ->> 'email', '') !~ '^[^@\s]+@[^@\s]+$' or char_length(x ->> 'email') > 254 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'speakers';
    end if;
    update app.transcript_speakers set email = lower(btrim(x ->> 'email')) where transcript_id = p_transcript and label = btrim(x ->> 'label');
  end loop;
  update app.transcript_speakers sp set
    staff_id = coalesce((select a.staff_id from app.meeting_attendees a where a.meeting_id = v_meeting and a.email = sp.email and a.staff_id is not null),
                        (select ad.id from app.admins ad where ad.email = sp.email)),
    person_id = case when exists (select 1 from app.meeting_attendees a where a.meeting_id = v_meeting and a.email = sp.email and a.staff_id is not null)
                       or exists (select 1 from app.admins ad where ad.email = sp.email) then null
                     else coalesce((select a.person_id from app.meeting_attendees a where a.meeting_id = v_meeting and a.email = sp.email),
                                   (select min(p.id::text)::uuid from app.people p where lower(p.email) = sp.email and p.deleted_at is null having count(*) = 1)) end
  where sp.transcript_id = p_transcript and sp.email is not null and sp.staff_id is null and sp.person_id is null;
  update app.transcript_speakers sp set
    staff_id = coalesce(n.staff_id, case when n.person_id is null then (select ad.id from app.admins ad where ad.id = v_owner and lower(ad.name) = lower(sp.label)) end),
    person_id = n.person_id, email = coalesce(sp.email, n.email)
  from (select sp2.label, (array_agg(a.staff_id))[1] staff_id, (array_agg(a.person_id))[1] person_id, (array_agg(a.email))[1] email
        from app.transcript_speakers sp2 left join app.meeting_attendees a on a.meeting_id = v_meeting
             and lower(sp2.label) in (lower(a.name), lower((select p.name from app.people p where p.id = a.person_id)))
        where sp2.transcript_id = p_transcript group by sp2.label having count(a.email) <= 1) n
  where sp.transcript_id = p_transcript and sp.label = n.label and sp.staff_id is null and sp.person_id is null;
end $fn$;

-- after a transcript is ready: the recap and the suggestions are one AI call (§2.7); without the provider the recap
-- reads «not connected» and the transcript stays readable
create function app.mtg_recap_queue(p_transcript uuid) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; v_state text := case when app.connected('ai') then 'requested' else 'not_connected' end;
begin
  select * into t from app.meeting_transcripts where id = p_transcript;
  insert into app.meeting_recaps (transcript_id, meeting_id, state, requested_at)
  values (t.id, t.meeting_id, v_state, now())
  on conflict (transcript_id) do update set state = excluded.state, requested_at = now();
  if v_state = 'requested' then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_recap', 'transcript_id', t.id, 'meeting_id', t.meeting_id));
  end if;
  return v_state;
end $fn$;

-- a transcript became ready: the recap, the event, the owner told
create function app.mtg_transcript_done(p_transcript uuid, p_ok boolean, p_error text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; m app.meetings;
begin
  select * into t from app.meeting_transcripts where id = p_transcript;
  select * into m from app.meetings where id = t.meeting_id;
  if p_ok then
    update app.meeting_transcripts set state = 'ready', ready_at = now(), error_code = null,
      speaker_count = (select count(distinct s.speaker_label) from app.transcript_segments s where s.transcript_id = t.id),
      duration_s = coalesce(t.duration_s, (select max(coalesce(s.end_ms, s.start_ms)) / 1000 from app.transcript_segments s where s.transcript_id = t.id))
    where id = t.id;
    perform app.mtg_recap_queue(t.id);
    insert into app.events (kind, subject_type, subject_id, payload, is_sample)
    values ('meeting.transcribed', 'meeting', m.id, jsonb_build_object('transcript', t.id, 'duration_s', (select duration_s from app.meeting_transcripts where id = t.id)), m.is_sample);
  else
    update app.meeting_transcripts set state = 'failed', error_code = coalesce(p_error, 'failed'), ready_at = null where id = t.id;
  end if;
  if m.owner_id is not null then
    perform app.notify(m.owner_id, 'system', case when p_ok then 'meeting.transcript_ready' else 'meeting.transcript_failed' end,
                       jsonb_build_object('record', m.title), '/meetings?meeting=' || m.id, 'meeting', m.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.transcript', 'meeting', m.id::text, jsonb_build_object('transcript', t.id, 'source', t.source, 'ok', p_ok, 'error', p_error), true);
end $fn$;

-- ===========================================================================
-- reads
-- ===========================================================================
-- the workspace (§2.1): three groups and the providers. Query {history_before (ISO time), history_limit 1..100, mine}.
-- → {upcoming: [row], review: [row], history: [row], history_next: time | null, capabilities, calendar}
create function public.meetings_workspace(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mtg_require(); q jsonb := coalesce(p_query, '{}'::jsonb); v_sandbox boolean := (select sandbox from app.admins where id = app.me());
  v_before timestamptz; v_limit int; v_mine boolean; v_out jsonb; v_hist jsonb; v_next timestamptz;
begin
  perform app.prj_keys(q, array['history_before', 'history_limit', 'mine']);
  begin
    v_before := (q ->> 'history_before')::timestamptz;
  exception when others then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'history_before';
  end;
  v_limit := coalesce(app.prj_int(q, 'history_limit', 1, 100), 30);
  if jsonb_typeof(q -> 'mine') not in ('boolean', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mine'; end if;
  v_mine := coalesce((q ->> 'mine')::boolean, false);
  create temp table if not exists pg_temp.mtg_ws (at_ timestamptz, g text, r jsonb) on commit drop;
  truncate pg_temp.mtg_ws;
  insert into pg_temp.mtg_ws
  select x.at_, app.mtg_group(x.m), app.mtg_row(x.m)
  from (select m, coalesce(m.starts_at, m.created_at) at_ from app.meetings m
        where m.deleted_at is null and (v_sandbox or not m.is_sample) and (not v_mine or m.owner_id = v_me) and app.mtg_visible(m)) x;
  select coalesce(jsonb_agg(r order by at_ desc), '[]'::jsonb) into v_hist
  from (select at_, r from pg_temp.mtg_ws where g = 'history' and (v_before is null or at_ < v_before) order by at_ desc limit v_limit) h;
  select min(at_) into v_next from (select at_ from pg_temp.mtg_ws where g = 'history' and (v_before is null or at_ < v_before) order by at_ desc limit v_limit) h;
  if not exists (select 1 from pg_temp.mtg_ws where g = 'history' and at_ < v_next) then v_next := null; end if;
  v_out := jsonb_build_object(
    'upcoming', coalesce((select jsonb_agg(r order by at_) from pg_temp.mtg_ws where g = 'upcoming'), '[]'::jsonb),
    'review', coalesce((select jsonb_agg(r order by at_ desc) from pg_temp.mtg_ws where g = 'review'), '[]'::jsonb),
    'history', v_hist, 'history_next', v_next,
    'capabilities', app.mtg_capabilities(),
    'can_configure', app.can('global', 'configure'));
  perform app.log('record.listed', 'meeting', null, jsonb_build_object('count', (select count(*) from pg_temp.mtg_ws)));
  return v_out;
end $fn$;

-- one meeting's header (§2.1) and everything the right-hand side needs to choose its tab
create function public.meeting_detail(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); r app.meeting_recaps; rec app.meeting_recordings; v_out jsonb;
begin
  if t.id is not null then select * into r from app.meeting_recaps where transcript_id = t.id; end if;
  select * into rec from app.meeting_recordings where meeting_id = m.id order by created_at desc limit 1;
  v_out := app.mtg_row(m) || jsonb_build_object(
    'join_url', m.join_url, 'visibility', m.visibility, 'cancelled_at', m.cancelled_at, 'can_edit', app.mtg_can_edit(m),
    'links', app.mtg_links(m), 'activity_id', m.activity_id,
    'attendee_list', coalesce((select jsonb_agg(jsonb_build_object('email', a.email, 'name', coalesce(p.name, ad.name, a.name), 'person_id', a.person_id,
                                                                   'staff_id', a.staff_id, 'external', a.external, 'response', a.response,
                                                                   'notice_sent_at', a.notice_sent_at, 'opted_out', a.opted_out_at is not null
                                                                     or exists (select 1 from app.recording_opt_outs o where o.email_sha256 = app.email_hash(a.email))) order by a.external desc, coalesce(p.name, ad.name, a.name, a.email))
                               from app.meeting_attendees a left join app.people p on p.id = a.person_id and p.deleted_at is null left join app.admins ad on ad.id = a.staff_id
                               where a.meeting_id = m.id), '[]'::jsonb),
    'notice', jsonb_build_object('state', m.notice_state, 'due_at', m.notice_due_at, 'sent_at', m.notice_sent_at, 'setting', app.setting('rec_notice'),
                                 'hours', app.mtg_notice_hours()),
    'bot', jsonb_build_object('state', m.bot_state, 'reason', m.bot_block_reason),
    'recording', case when rec.id is not null then jsonb_build_object('id', rec.id, 'method', rec.method, 'state', rec.state, 'duration_s', rec.duration_s,
                                                                     'purge_after', rec.purge_after, 'deleted_at', rec.deleted_at) end,
    'transcript', case when t.id is not null then jsonb_build_object('id', t.id, 'source', t.source, 'state', t.state, 'error_code', t.error_code,
                                                                    'duration_s', t.duration_s, 'speaker_count', t.speaker_count, 'language', t.language,
                                                                    'file_name', t.file_name, 'ready_at', t.ready_at) end,
    'recap', case when r.transcript_id is not null then jsonb_build_object('state', r.state, 'saved_at', r.saved_at, 'note_id', r.note_id) end,
    'suggestions_pending', (select count(*) from app.meeting_suggestions s where s.transcript_id = t.id and s.state = 'pending'),
    'brief', (select jsonb_build_object('state', b.state, 'generated_at', b.generated_at, 'quotes_state', b.quotes_state) from app.meeting_briefs b where b.meeting_id = m.id),
    'default_tab', case when m.starts_at > now() and m.cancelled_at is null then 'brief' else 'transcript' end,
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'field', l.field, 'old', l.old_value, 'new', l.new_value, 'source', l.source,
                                                            'actor', (select a.name from app.admins a where a.id = l.actor_id)) order by l.id desc)
                         from (select * from app.changelog where entity = 'meeting' and record_id = m.id order by id desc limit 20) l), '[]'::jsonb),
    'created_at', m.created_at, 'updated_at', m.updated_at);
  perform app.log('record.read', 'meeting', m.id::text);
  return v_out;
end $fn$;

-- the pre-call brief (§2.2). Items whose source the caller may not see are left out; checks are the caller's own.
create function public.meeting_brief(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); b app.meeting_briefs;
begin
  select * into b from app.meeting_briefs where meeting_id = m.id;
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'brief'));
  if not found then
    return jsonb_build_object('state', 'none', 'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0, 'ai', app.connected('ai'));
  end if;
  return jsonb_build_object(
    'state', b.state, 'generated_at', b.generated_at, 'since_at', b.since_at, 'last_contact_at', b.last_contact_at,
    'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0,
    'changes', coalesce((select jsonb_agg(c || jsonb_build_object('checked', exists (select 1 from app.meeting_brief_checks k
                                                                                       where k.meeting_id = m.id and k.staff_id = app.me() and k.item_key = c ->> 'key')))
                         from jsonb_array_elements(b.changes) c where app.mtg_source_visible(c -> 'source')), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(p) from jsonb_array_elements(b.people) p where app.mtg_source_visible(p -> 'source')), '[]'::jsonb),
    'facts', coalesce((select jsonb_agg(f) from jsonb_array_elements(b.facts) f where app.mtg_source_visible(f -> 'source')), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(x) from jsonb_array_elements(b.quotes) x where app.mtg_source_visible(x -> 'record')), '[]'::jsonb),
    'quotes_state', b.quotes_state, 'ai', app.connected('ai'),
    'instructions_set', (select s.brief_instructions is not null from app.meeting_user_settings s where s.staff_id = app.me()));
end $fn$;

-- the transcript (§2.3), paged by seq. Text is the speakers' own words: the app escapes it as untrusted (A7.4).
-- → {transcript | null, speakers: [{label, name, kind, staff_id, person_id}], segments: [{seq, start_ms, end_ms, label, text, redacted}], next}
create function public.meeting_transcript(p_id uuid, p_cursor int default 0, p_limit int default 200) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); v_limit int := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_rows jsonb; v_last int;
begin
  if t.id is null then return jsonb_build_object('transcript', null, 'speakers', '[]'::jsonb, 'segments', '[]'::jsonb, 'next', null); end if;
  select coalesce(jsonb_agg(jsonb_build_object('seq', s.seq, 'start_ms', s.start_ms, 'end_ms', s.end_ms, 'label', s.speaker_label,
                                               'text', s.text, 'redacted', s.redacted_at is not null) order by s.seq), '[]'::jsonb), max(s.seq)
  into v_rows, v_last
  from (select * from app.transcript_segments where transcript_id = t.id and seq > coalesce(p_cursor, 0) order by seq limit v_limit) s;
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'transcript', 'count', jsonb_array_length(v_rows)));
  return jsonb_build_object(
    'transcript', jsonb_build_object('id', t.id, 'source', t.source, 'state', t.state, 'error_code', t.error_code, 'duration_s', t.duration_s,
                                     'speaker_count', t.speaker_count, 'language', t.language, 'file_name', t.file_name, 'ready_at', t.ready_at),
    'speakers', coalesce((select jsonb_agg(jsonb_build_object('label', sp.label, 'staff_id', sp.staff_id, 'person_id', sp.person_id,
                                                              'name', coalesce(ad.name, case when app.mtg_target_ok('person', sp.person_id) then p.name end),
                                                              'kind', case when sp.staff_id is not null then 'staff' when sp.person_id is not null then 'external' else 'unknown' end)
                                           order by sp.label)
                          from app.transcript_speakers sp left join app.admins ad on ad.id = sp.staff_id left join app.people p on p.id = sp.person_id
                          where sp.transcript_id = t.id), '[]'::jsonb),
    'segments', v_rows,
    'next', case when exists (select 1 from app.transcript_segments where transcript_id = t.id and seq > v_last) then v_last end);
end $fn$;

-- the recap (§2.3) of the newest transcript
create function public.meeting_recap(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); r app.meeting_recaps; n app.notes;
begin
  if t.id is not null then select * into r from app.meeting_recaps where transcript_id = t.id; end if;
  if r.note_id is not null then select * into n from app.notes where id = r.note_id and deleted_at is null; end if;
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'recap'));
  return jsonb_build_object(
    'transcript_id', t.id, 'state', coalesce(r.state, 'none'), 'takeaways', coalesce(r.takeaways, '[]'::jsonb), 'next_steps', coalesce(r.next_steps, '[]'::jsonb),
    'generated_at', r.generated_at, 'saved_at', r.saved_at, 'announced_at', r.announced_at,
    'note', case when n.id is not null then jsonb_build_object('id', n.id, 'entity', n.entity, 'record_id', n.record_id) end,
    'save_target', app.mtg_links(m) -> 'primary', 'ai', app.connected('ai'), 'can_edit', app.mtg_can_edit(m));
end $fn$;

-- CRM update suggestions (§2.4) of the newest transcript; stale_now: the record moved since the proposal
create function public.meeting_suggestions(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); v_out jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'ord', s.ord, 'target_entity', s.target_entity, 'target_id', s.target_id,
      'target_title', case when s.target_id is not null then app.record_title(s.target_entity, s.target_id) end,
      'field', s.field, 'field_label', case when s.field like 'custom.%' then (select f.label from app.fields f where f.entity = s.target_entity and f.key = substr(s.field, 8)) end,
      'current_value', s.current_value, 'proposed_value', s.proposed_value, 'evidence', to_jsonb(s.evidence), 'state', s.state, 'error_code', s.error_code,
      'decided_by', (select a.name from app.admins a where a.id = s.decided_by), 'decided_at', s.decided_at, 'written_record_id', s.written_record_id,
      'stale_now', s.state = 'pending' and app.mtg_suggestion_current(s) is distinct from s.current_value)
    order by s.ord), '[]'::jsonb)
  into v_out
  from app.meeting_suggestions s where s.transcript_id = t.id and (s.target_id is null or app.mtg_target_ok(s.target_entity, s.target_id));
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'suggestions', 'count', jsonb_array_length(v_out)));
  return jsonb_build_object('transcript_id', t.id, 'suggestions', v_out);
end $fn$;

-- Workspace and controls (§2.6, global:configure): every active staff member with deals:see, their switch, auto-join and mailbox
create function public.meeting_controls() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'configure');
  perform app.require_module('meetings');
  return jsonb_build_object(
    'users', coalesce((select jsonb_agg(app.mtg_user_row(a.id) order by a.name) from app.admins a where a.active and app.can_for(a.id, 'deals', 'see')), '[]'::jsonb),
    'rec_notice', jsonb_build_object('value', app.setting('rec_notice'), 'hours', app.mtg_notice_hours()),
    'rec_retention', jsonb_build_object('value', app.setting('rec_retention'), 'months', app.mtg_retention_months()),
    'visibility_default', app.mtg_visibility_default(),
    'capabilities', app.mtg_capabilities());
end $fn$;

-- the caller's own settings
create function public.meeting_my_settings() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.mtg_require();
begin
  return app.mtg_user_row(v_me) || jsonb_build_object('brief_instructions', (select s.brief_instructions from app.meeting_user_settings s where s.staff_id = v_me));
end $fn$;

-- ===========================================================================
-- writes
-- ===========================================================================
-- link a meeting to a deal, lead, person or organisation (MTG-01 RU, MTG-07 A). The meeting then has a «meeting»
-- activity on those records, done when it is in the past, so it shows in their history (ACT-01 A).
-- p_values: any of {deal_id, lead_id, person_id, organization_id} (null unlinks). → {id, version, activity_id, links}
create function public.meeting_link(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  m app.meetings := app.mtg_get(p_id, true); n app.meetings; v_me uuid := app.me(); k text; v_new uuid; v_old uuid; v_changed text[] := '{}';
  v_act uuid; v_done boolean; v_at timestamptz;
begin
  perform app.mtg_require_edit(m);
  if p_version is not null and m.version <> p_version then
    raise exception 'version_conflict' using errcode = 'serialization_failure', detail = m.version::text;
  end if;
  perform app.prj_keys(p_values, array['deal_id', 'lead_id', 'person_id', 'organization_id']);
  if not exists (select 1 from jsonb_object_keys(p_values)) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'link'; end if;
  n := m;
  foreach k in array array['deal_id', 'lead_id', 'person_id', 'organization_id'] loop
    continue when not (p_values ? k);
    v_new := app.prj_uuid(p_values, k);
    if v_new is not null and not app.mtg_target_ok(replace(k, '_id', ''), v_new) then raise exception 'not_found' using errcode = 'no_data_found', detail = k; end if;
    case k
      when 'deal_id' then v_old := n.deal_id; n.deal_id := v_new;
      when 'lead_id' then v_old := n.lead_id; n.lead_id := v_new;
      when 'person_id' then v_old := n.person_id; n.person_id := v_new;
      else v_old := n.organization_id; n.organization_id := v_new;
    end case;
    if v_old is distinct from v_new then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('meeting', m.id, k, to_jsonb(v_old), to_jsonb(v_new), v_me, 'ui');
      v_changed := v_changed || k;
    end if;
  end loop;
  if cardinality(v_changed) = 0 then
    return jsonb_build_object('id', m.id, 'version', m.version, 'activity_id', m.activity_id, 'links', app.mtg_links(m));
  end if;
  update app.meetings set deal_id = n.deal_id, lead_id = n.lead_id, person_id = n.person_id, organization_id = n.organization_id,
    version = version + 1, updated_at = now(), updated_by = v_me
  where id = m.id returning * into n;
  v_act := n.activity_id;
  if num_nonnulls(n.deal_id, n.lead_id, n.person_id, n.organization_id) > 0 then
    v_at := coalesce(n.starts_at, n.created_at);
    v_done := v_at <= now();
    if v_act is null then
      insert into app.activities (type_id, subject, starts_at, duration_min, deal_id, lead_id, person_id, organization_id, video_provider, video_url,
                                  done, done_at, done_by, owner_id, visibility, is_sample, created_by, updated_by)
      values ((select t.id from app.activity_types t where t.key = 'meeting'), left(n.title, 200), v_at,
              coalesce(least(1440, greatest(0, (extract(epoch from (n.ends_at - n.starts_at)) / 60)::int)), 30),
              n.deal_id, n.lead_id, n.person_id, n.organization_id,
              case when n.conference in ('meet', 'teams', 'zoom') then n.conference end, case when char_length(n.join_url) <= 500 then n.join_url end,
              v_done, case when v_done then coalesce(n.ends_at, v_at) end, case when v_done then n.owner_id end,
              n.owner_id, n.visibility, n.is_sample, v_me, v_me)
      returning id into v_act;
      update app.meetings set activity_id = v_act where id = n.id;
      insert into app.changelog (entity, record_id, field, actor_id, source) values ('activity', v_act, '*created', v_me, 'meeting');
      perform app.emit('activity.created', 'activity', v_act, jsonb_build_object('meeting', n.id, 'deal', n.deal_id), n.is_sample);
    else
      update app.activities set deal_id = n.deal_id, lead_id = n.lead_id, person_id = n.person_id, organization_id = n.organization_id,
        version = version + 1, updated_at = now(), updated_by = v_me
      where id = v_act;
    end if;
    if v_done and n.deal_id is not null then
      update app.deals set last_activity_at = greatest(coalesce(last_activity_at, '-infinity'::timestamptz), coalesce(n.ends_at, v_at)) where id = n.deal_id;
    end if;
  end if;
  perform app.log('meeting.linked', 'meeting', m.id::text, jsonb_build_object('fields', to_jsonb(v_changed)));
  perform app.emit('meeting.linked', 'meeting', m.id, jsonb_build_object('deal', n.deal_id, 'lead', n.lead_id, 'person', n.person_id, 'organization', n.organization_id), m.is_sample);
  return jsonb_build_object('id', m.id, 'version', n.version, 'activity_id', v_act, 'links', app.mtg_links(n));
end $fn$;

-- the capture choice of a future meeting: the notetaker or nothing (desktop capture is not available, D-38)
create function public.meeting_capture_set(p_id uuid, p_capture text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id, true);
begin
  perform app.mtg_require_edit(m);
  if p_capture = 'desktop' then raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'desktop'; end if;
  if p_capture is null or p_capture not in ('bot', 'none') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'capture'; end if;
  if not coalesce(m.starts_at > now(), false) or m.cancelled_at is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at'; end if;
  if p_capture = 'bot' then perform app.require_connected('meeting_bot'); end if;
  if p_capture <> m.capture then
    if p_capture = 'none' and m.bot_state in ('joining', 'in_call') then
      perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_leave', 'meeting_id', m.id));
      update app.meetings set bot_state = 'removed', bot_block_reason = null where id = m.id;
    elsif p_capture = 'bot' and m.bot_state in ('removed', 'failed', 'left') then
      update app.meetings set bot_state = 'none', bot_block_reason = null where id = m.id;
    end if;
    update app.meetings set capture = p_capture, version = version + 1, updated_at = now(), updated_by = app.me() where id = m.id;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('meeting', m.id, 'capture', to_jsonb(m.capture), to_jsonb(p_capture), app.me(), 'ui');
    perform app.log('meeting.capture_set', 'meeting', m.id::text, jsonb_build_object('from', m.capture, 'to', p_capture));
  end if;
  m := app.mtg_refresh(m.id);
  select * into m from app.meetings where id = m.id;
  return jsonb_build_object('id', m.id, 'version', m.version, 'capture', m.capture, 'bot', jsonb_build_object('state', m.bot_state, 'reason', m.bot_block_reason),
                            'notice', jsonb_build_object('state', m.notice_state, 'due_at', m.notice_due_at));
end $fn$;

-- Remove bot (MTG-02 A «leaves when removed»): at once, whatever the provider says
create function public.meeting_bot_remove(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id, true);
begin
  perform app.mtg_require_edit(m);
  if m.bot_state not in ('scheduled', 'joining', 'in_call') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'bot_state'; end if;
  if m.bot_state in ('joining', 'in_call') then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_leave', 'meeting_id', m.id));
  end if;
  update app.meetings set bot_state = 'removed', bot_block_reason = null, updated_at = now(), updated_by = app.me() where id = m.id;
  perform app.log('meeting.bot_removed', 'meeting', m.id::text, jsonb_build_object('from', m.bot_state));
  perform app.emit('meeting.bot_removed', 'meeting', m.id, jsonb_build_object('from', m.bot_state), m.is_sample);
  return jsonb_build_object('id', m.id, 'bot_state', 'removed');
end $fn$;

-- Stop and delete recording (UF-07 step 3): the audio goes from storage; with p_with_transcript the transcript, its
-- recap and suggestions go too, and quotes citing it leave every brief. A note already saved on a record stays there.
create function public.meeting_recording_delete(p_id uuid, p_with_transcript boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id, true); v_paths text[]; n_rec int; n_tr int := 0; v_tr uuid[];
begin
  perform app.mtg_require_edit(m);
  select array_agg(storage_path) into v_paths from app.meeting_recordings where meeting_id = m.id and state <> 'deleted';
  update app.meeting_recordings set state = 'deleted', deleted_at = now(), storage_path = null where meeting_id = m.id and state <> 'deleted';
  get diagnostics n_rec = row_count;
  if m.bot_state in ('joining', 'in_call') then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_leave', 'meeting_id', m.id));
    update app.meetings set bot_state = 'removed', bot_block_reason = null where id = m.id;
  end if;
  if coalesce(p_with_transcript, false) then
    v_tr := array(select id from app.meeting_transcripts where meeting_id = m.id);
    update app.meeting_briefs b set quotes = coalesce((select jsonb_agg(q) from jsonb_array_elements(b.quotes) q where not coalesce((q ->> 'transcript_id')::uuid = any (v_tr), false)), '[]'::jsonb)
    where exists (select 1 from jsonb_array_elements(b.quotes) q where (q ->> 'transcript_id')::uuid = any (v_tr));
    delete from app.meeting_transcripts where meeting_id = m.id;
    get diagnostics n_tr = row_count;
  end if;
  if n_rec = 0 and n_tr = 0 then raise exception 'not_found' using errcode = 'no_data_found', detail = 'recording'; end if;
  perform app.mtg_storage_forget(v_paths);
  perform app.log('meeting.recording_deleted', 'meeting', m.id::text, jsonb_build_object('recordings', n_rec, 'transcripts', n_tr));
  perform app.emit('meeting.recording_deleted', 'meeting', m.id, jsonb_build_object('recordings', n_rec, 'transcripts', n_tr), m.is_sample);
  return jsonb_build_object('id', m.id, 'recordings', n_rec, 'transcripts', n_tr);
end $fn$;

-- tick an item of «Since the last contact» (spec Q18: per user)
create function public.meeting_brief_check(p_id uuid, p_item_key text, p_checked boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id);
begin
  if not exists (select 1 from app.meeting_briefs b, jsonb_array_elements(b.changes) c where b.meeting_id = m.id and c ->> 'key' = p_item_key) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'item_key';
  end if;
  if coalesce(p_checked, false) then
    insert into app.meeting_brief_checks (meeting_id, item_key, staff_id) values (m.id, p_item_key, app.me()) on conflict do nothing;
  else
    delete from app.meeting_brief_checks where meeting_id = m.id and item_key = p_item_key and staff_id = app.me();
  end if;
  return jsonb_build_object('key', p_item_key, 'checked', coalesce(p_checked, false));
end $fn$;

-- rebuild the facts now and ask for the quotes again (they need the AI provider)
create function public.meeting_brief_regenerate(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); b app.meeting_briefs;
begin
  perform app.mtg_brief_build(m.id);
  select * into b from app.meeting_briefs where meeting_id = m.id;
  perform app.log('meeting.brief_regenerated', 'meeting', m.id::text, jsonb_build_object('quotes', b.quotes_state));
  return jsonb_build_object('id', m.id, 'state', b.state, 'generated_at', b.generated_at, 'quotes_state', b.quotes_state);
end $fn$;

-- Upload transcript (MTG-06): .vtt, .srt, .txt or .docx up to 5 MB, the extension matching the type. Without a meeting a
-- new unlinked one is made (source «upload»). → {id, meeting_id, bucket, path, expires_in}; the edge function signs it.
create function public.meeting_transcript_upload_begin(p_meeting uuid, p_filename text, p_mime text, p_size bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mtg_require(); m app.meetings; v_name text := btrim(p_filename); v_ext text; v_id uuid := gen_random_uuid(); v_path text; v_title text;
begin
  if v_name is null or char_length(v_name) not between 1 and 255 or v_name ~ '[/\\]' or v_name ~ '^\.' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filename';
  end if;
  if p_mime is null or p_mime not in ('text/vtt', 'application/x-subrip', 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mime';
  end if;
  v_ext := lower(substring(v_name from '\.([A-Za-z0-9]{1,5})$'));
  if v_ext is distinct from (case p_mime when 'text/vtt' then 'vtt' when 'application/x-subrip' then 'srt' when 'text/plain' then 'txt' else 'docx' end) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filename';
  end if;
  if p_size is null or p_size not between 1 and 5242880 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'size'; end if;
  if p_meeting is null then
    v_title := left(btrim(regexp_replace(v_name, '\.[A-Za-z0-9]{1,5}$', '')), 300);
    insert into app.meetings (title, source, capture, notice_state, owner_id, visibility, is_sample, created_by, updated_by)
    values (coalesce(nullif(v_title, ''), v_name), 'upload', 'upload', 'not_required', v_me, app.mtg_visibility_default(),
            (select sandbox from app.admins where id = v_me), v_me, v_me)
    returning * into m;
    insert into app.changelog (entity, record_id, field, actor_id, source) values ('meeting', m.id, '*created', v_me, 'ui');
    perform app.emit('meeting.created', 'meeting', m.id, jsonb_build_object('source', 'upload'), m.is_sample);
  else
    m := app.mtg_get(p_meeting, true);
    perform app.mtg_require_edit(m);
  end if;
  v_path := 'upload/' || m.id || '/' || v_id || '.' || v_ext;
  insert into app.meeting_uploads (id, meeting_id, storage_path, filename, mime, size_bytes, uploaded_by)
  values (v_id, m.id, v_path, v_name, p_mime, p_size, v_me);
  perform app.log('meeting.upload_started', 'meeting', m.id::text, jsonb_build_object('upload', v_id, 'size', p_size, 'mime', p_mime));
  return jsonb_build_object('id', v_id, 'meeting_id', m.id, 'bucket', 'meeting-files', 'path', v_path, 'expires_in', 600);
end $fn$;

-- the upload landed: a transcript in processing and a parse job (the original file is deleted after parsing)
create function public.meeting_transcript_upload_done(p_upload uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mtg_require(); u app.meeting_uploads; m app.meetings; v_t uuid;
begin
  select * into u from app.meeting_uploads where id = p_upload for update;
  if not found or u.uploaded_by is distinct from v_me then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if u.state <> 'pending' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  m := app.mtg_get(u.meeting_id, true);
  insert into app.meeting_transcripts (meeting_id, source, state, file_name, uploaded_by) values (m.id, 'upload', 'processing', u.filename, v_me) returning id into v_t;
  update app.meeting_uploads set state = 'uploaded', transcript_id = v_t where id = u.id;
  update app.meetings set capture = 'upload' where id = m.id and capture = 'none';
  perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_upload_parse', 'upload_id', u.id, 'transcript_id', v_t, 'meeting_id', m.id,
                                               'bucket', 'meeting-files', 'path', u.storage_path, 'mime', u.mime));
  perform app.log('meeting.upload_done', 'meeting', m.id::text, jsonb_build_object('upload', u.id, 'transcript', v_t));
  return jsonb_build_object('id', u.id, 'transcript_id', v_t, 'state', 'processing');
end $fn$;

-- Retry a failed transcription (SF-21.7): the recording is kept, so the provider can try again
create function public.meeting_transcript_retry(p_transcript uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; m app.meetings;
begin
  perform app.mtg_require();
  select * into t from app.meeting_transcripts where id = p_transcript;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  m := app.mtg_get(t.meeting_id, true);
  perform app.mtg_require_edit(m);
  if t.state <> 'failed' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if t.source = 'upload' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
  if not exists (select 1 from app.meeting_recordings r where r.id = t.recording_id and r.state <> 'deleted') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recording';
  end if;
  perform app.require_connected('transcription');
  delete from app.meeting_transcripts where id = t.id;        -- a failed transcript holds no words; the retry starts a new one
  insert into app.meeting_transcripts (meeting_id, recording_id, source, state, provider)
  values (m.id, t.recording_id, 'provider', 'processing', t.provider) returning * into t;
  update app.meeting_recordings set state = 'processing', error_code = null where id = t.recording_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_transcribe', 'transcript_id', t.id, 'recording_id', t.recording_id, 'meeting_id', m.id));
  perform app.log('meeting.transcript_retry', 'meeting', m.id::text, jsonb_build_object('transcript', t.id));
  return jsonb_build_object('id', t.id, 'state', 'processing');
end $fn$;

-- map a speaker label to a staff member, a person or an address (or clear it with {})
create function public.meeting_speaker_map(p_transcript uuid, p_label text, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; m app.meetings; v_staff uuid; v_person uuid; v_email text;
begin
  perform app.mtg_require();
  select * into t from app.meeting_transcripts where id = p_transcript;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  m := app.mtg_get(t.meeting_id);
  perform app.mtg_require_edit(m);
  perform app.prj_keys(p_values, array['staff_id', 'person_id', 'email']);
  if not exists (select 1 from app.transcript_speakers where transcript_id = t.id and label = p_label) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'label';
  end if;
  v_staff := app.prj_uuid(p_values, 'staff_id'); v_person := app.prj_uuid(p_values, 'person_id');
  v_email := lower(app.prj_text(p_values, 'email', 0, 254));
  if num_nonnulls(v_staff, v_person, v_email) > 1 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if v_staff is not null and not exists (select 1 from app.admins a where a.id = v_staff) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'staff_id'; end if;
  if v_person is not null and not app.mtg_target_ok('person', v_person) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'person_id'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'email'; end if;
  update app.transcript_speakers set staff_id = v_staff, person_id = v_person, email = coalesce(v_email, (select p.email from app.people p where p.id = v_person))
  where transcript_id = t.id and label = p_label;
  perform app.log('meeting.speaker_mapped', 'meeting', m.id::text, jsonb_build_object('transcript', t.id, 'kind', case when v_staff is not null then 'staff' when v_person is not null then 'person' when v_email is not null then 'email' else 'cleared' end));
  return jsonb_build_object('label', p_label, 'staff_id', v_staff, 'person_id', v_person, 'email', v_email);
end $fn$;

-- ask the AI worker for the recap and suggestions again (not after the recap was saved as a note)
create function public.meeting_recap_regenerate(p_transcript uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; m app.meetings; r app.meeting_recaps;
begin
  perform app.mtg_require();
  select * into t from app.meeting_transcripts where id = p_transcript;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  m := app.mtg_get(t.meeting_id, true);
  perform app.mtg_require_edit(m);
  if t.state <> 'ready' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into r from app.meeting_recaps where transcript_id = t.id for update;
  if r.saved_at is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'saved'; end if;
  perform app.require_connected('ai');
  if r.state is distinct from 'requested' then perform app.mtg_recap_queue(t.id); end if;
  perform app.log('meeting.recap_requested', 'meeting', m.id::text, jsonb_build_object('transcript', t.id));
  return jsonb_build_object('transcript_id', t.id, 'state', 'requested');
end $fn$;

-- Save recap as note (§2.3): on the primary link (deal → lead → organization → person) or a named one of the
-- meeting's links. note_save checks the record's scope and visibility. → {note_id, entity, record_id, already}
create function public.meeting_recap_save_note(p_id uuid, p_entity text default null, p_record uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id, true); t app.meeting_transcripts := app.mtg_transcript(p_id); r app.meeting_recaps; v_entity text; v_record uuid;
  v_body text; v_note uuid;
begin
  select * into r from app.meeting_recaps where transcript_id = t.id for update;
  if r.state is distinct from 'ready' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recap'; end if;
  if r.saved_at is not null and exists (select 1 from app.notes n where n.id = r.note_id and n.deleted_at is null) then
    return jsonb_build_object('note_id', r.note_id, 'entity', (select entity from app.notes where id = r.note_id),
                              'record_id', (select record_id from app.notes where id = r.note_id), 'already', true);
  end if;
  if p_entity is null then
    select e, i into v_entity, v_record from (values (1, 'deal', m.deal_id), (2, 'lead', m.lead_id), (3, 'organization', m.organization_id), (4, 'person', m.person_id)) x(o, e, i)
    where i is not null order by o limit 1;
  elsif p_entity = 'deal' and p_record = m.deal_id or p_entity = 'lead' and p_record = m.lead_id
        or p_entity = 'organization' and p_record = m.organization_id or p_entity = 'person' and p_record = m.person_id then
    v_entity := p_entity; v_record := p_record;
  end if;
  if v_record is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'link'; end if;
  v_body := left(concat_ws(E'\n',
              (select string_agg('· ' || (x ->> 'text'), E'\n' order by o) from jsonb_array_elements(r.takeaways) with ordinality s(x, o)),
              (select string_agg('○ ' || (x ->> 'text'), E'\n' order by o) from jsonb_array_elements(r.next_steps) with ordinality s(x, o)),
              '/meetings?meeting=' || m.id), 10000);
  v_note := (public.note_save(v_entity, v_record, null, v_body) ->> 'id')::uuid;
  update app.meeting_recaps set note_id = v_note, saved_by = app.me(), saved_at = now() where transcript_id = t.id;
  perform app.log('meeting.recap_saved', 'meeting', m.id::text, jsonb_build_object('note', v_note, 'entity', v_entity));
  perform app.emit('meeting.recap_saved', 'meeting', m.id, jsonb_build_object('note', v_note, 'entity', v_entity, 'record', v_record), m.is_sample);
  return jsonb_build_object('note_id', v_note, 'entity', v_entity, 'record_id', v_record, 'already', false);
end $fn$;

-- Plan next activity (UF-07 step 6): an activity from a next step (p_step = its position, 0-based), linked like the
-- meeting, through the generic save (deals:add). p_values {type (key, default task), starts_at, duration_min, owner_id}
create function public.meeting_next_step_activity(p_id uuid, p_step int, p_values jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); r app.meeting_recaps; v_step jsonb; v_type uuid;
  v_values jsonb; v_res jsonb; v_at timestamptz;
begin
  perform app.prj_keys(coalesce(p_values, '{}'::jsonb), array['type', 'starts_at', 'duration_min', 'owner_id']);
  select * into r from app.meeting_recaps where transcript_id = t.id for update;
  if r.state is distinct from 'ready' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recap'; end if;
  v_step := r.next_steps -> p_step;
  if p_step is null or p_step < 0 or v_step is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'step'; end if;
  select id into v_type from app.activity_types where key = coalesce(p_values ->> 'type', 'task') and active;
  if v_type is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type'; end if;
  begin
    v_at := (p_values ->> 'starts_at')::timestamptz;
  exception when others then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at';
  end;
  v_values := jsonb_strip_nulls(jsonb_build_object('type_id', v_type, 'subject', left(v_step ->> 'text', 200), 'starts_at', v_at,
                                                   'duration_min', app.prj_int(p_values, 'duration_min', 0, 1440), 'owner_id', app.prj_uuid(p_values, 'owner_id'),
                                                   'deal_id', m.deal_id, 'lead_id', m.lead_id, 'person_id', m.person_id, 'organization_id', m.organization_id));
  v_res := public.rec_save('activity', null, v_values, null, null, 'meeting');
  update app.meeting_recaps set next_steps = jsonb_set(next_steps, array[p_step::text, 'activity_id'], v_res -> 'id') where transcript_id = t.id;
  perform app.log('meeting.next_step_planned', 'meeting', m.id::text, jsonb_build_object('activity', v_res -> 'id', 'step', p_step));
  return jsonb_build_object('activity_id', v_res -> 'id', 'step', p_step);
end $fn$;

-- write one accepted suggestion as the caller (rec_save, source «meeting»). A value that moved since the proposal is
-- stale and is never overwritten. → the record written
create function app.mtg_suggestion_write(s app.meeting_suggestions) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_cur jsonb; v_vals jsonb; v_res jsonb;
begin
  if s.field = '*new' then
    if app.setting('contact_rule') = 'opt_in_only' then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'setting:contact_rule';
    end if;
    v_res := public.rec_save('person', null, s.proposed_value || jsonb_build_object('source', 'Meeting'), null, null, 'meeting');
    return (v_res ->> 'id')::uuid;
  end if;
  if not app.mtg_target_ok(s.target_entity, s.target_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_cur := app.mtg_suggestion_current(s);
  if v_cur is distinct from s.current_value then
    raise exception 'version_conflict' using errcode = 'serialization_failure', detail = 'value';
  end if;
  v_vals := case when s.field like 'custom.%' then jsonb_build_object('custom', jsonb_build_object(substr(s.field, 8), s.proposed_value))
                 else jsonb_build_object(s.field, s.proposed_value) end;
  perform public.rec_save(s.target_entity, s.target_id, v_vals, null, null, 'meeting');
  return s.target_id;
end $fn$;

-- Accept / Reject / «Accept all remaining» (MTG-05). Each id is decided on its own: accepted, rejected, stale (the record
-- moved), failed (refused by a rule), or left pending when the caller may not write it. → {results: [{id, state, error, detail}], written}
create function public.meeting_suggestion_decide(p_ids uuid[], p_decision text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mtg_require(); v_id uuid; s app.meeting_suggestions; m app.meetings; v_out jsonb := '[]'::jsonb; v_written uuid; v_msg text; v_det text;
  v_counts jsonb := '{}'::jsonb; v_key text; n_written int := 0;
begin
  if p_decision is null or p_decision not in ('accept', 'reject') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'decision'; end if;
  if p_ids is null or cardinality(p_ids) not between 1 and 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  foreach v_id in array p_ids loop
    select * into s from app.meeting_suggestions where id = v_id for update;
    select * into m from app.meetings where id = s.meeting_id and deleted_at is null;
    if s.id is null or m.id is null or not app.mtg_visible(m) then
      v_out := v_out || jsonb_build_object('id', v_id, 'state', null, 'error', 'not_found'); continue;
    end if;
    if s.state <> 'pending' then
      v_out := v_out || jsonb_build_object('id', v_id, 'state', s.state, 'error', 'invalid', 'detail', 'state'); continue;
    end if;
    if p_decision = 'reject' then
      update app.meeting_suggestions set state = 'rejected', decided_by = v_me, decided_at = now() where id = s.id;
      v_out := v_out || jsonb_build_object('id', v_id, 'state', 'rejected');
    else
      begin
        v_written := app.mtg_suggestion_write(s);
        update app.meeting_suggestions set state = 'accepted', decided_by = v_me, decided_at = now(), written_record_id = v_written, error_code = null where id = s.id;
        v_out := v_out || jsonb_build_object('id', v_id, 'state', 'accepted', 'record_id', v_written);
        n_written := n_written + 1;
      exception
        when serialization_failure then
          update app.meeting_suggestions set state = 'stale', decided_by = v_me, decided_at = now(), error_code = 'version_conflict' where id = s.id;
          v_out := v_out || jsonb_build_object('id', v_id, 'state', 'stale', 'error', 'version_conflict');
        when insufficient_privilege or no_data_found or invalid_parameter_value then
          get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
          if v_det like 'setting:%' or v_msg = 'invalid' or v_msg = 'not_found' then
            update app.meeting_suggestions set state = 'failed', decided_by = v_me, decided_at = now(), error_code = left(v_msg || ':' || coalesce(v_det, ''), 80) where id = s.id;
            v_out := v_out || jsonb_build_object('id', v_id, 'state', 'failed', 'error', v_msg, 'detail', v_det);
          else
            v_out := v_out || jsonb_build_object('id', v_id, 'state', 'pending', 'error', v_msg, 'detail', v_det);
          end if;
      end;
    end if;
    v_key := m.id::text;
    v_counts := jsonb_set(v_counts, array[v_key], coalesce(v_counts -> v_key, '{"accepted":0,"rejected":0,"stale":0,"failed":0,"sample":false}'::jsonb));
    v_counts := jsonb_set(v_counts, array[v_key, 'sample'], to_jsonb(m.is_sample));
    if (v_out -> -1 ->> 'state') in ('accepted', 'rejected', 'stale', 'failed') then
      v_counts := jsonb_set(v_counts, array[v_key, v_out -> -1 ->> 'state'], to_jsonb((v_counts #>> array[v_key, v_out -> -1 ->> 'state'])::int + 1));
    end if;
  end loop;
  -- one event per meeting, counts only (Part F «updates_approved»)
  perform app.emit('meeting.updates_approved', 'meeting', k::uuid, (v - 'sample'), (v ->> 'sample')::boolean) from jsonb_each(v_counts) x(k, v)
  where (v ->> 'accepted')::int + (v ->> 'rejected')::int + (v ->> 'stale')::int + (v ->> 'failed')::int > 0;
  perform app.log('meeting.suggestions_decided', 'meeting', null, jsonb_build_object('decision', p_decision, 'count', cardinality(p_ids), 'written', n_written));
  return jsonb_build_object('results', v_out, 'written', n_written);
end $fn$;

-- Workspace and controls (§2.6, global:configure): a staff member's switch, auto-join choice and mailbox
create function public.meeting_user_set(p_staff uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure');
begin
  perform app.require_module('meetings');
  if not exists (select 1 from app.admins a where a.id = p_staff and a.active) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.mtg_user_write(p_staff, p_values, array['enabled', 'bot_auto_join', 'mailbox_id'], v_me);
  perform app.log('meeting_user.changed', 'staff', p_staff::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values))),
                                                                                  'enabled', (app.mtg_user(p_staff)).enabled));
  return app.mtg_user_row(p_staff);
end $fn$;

-- the caller's own choices: auto-join, brief instructions, the mailbox briefs read (not the switch itself)
create function public.meeting_my_settings_set(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mtg_require();
begin
  perform app.mtg_user_write(v_me, p_values, array['bot_auto_join', 'brief_instructions', 'mailbox_id'], v_me);
  perform app.log('meeting_user.changed', 'staff', v_me::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return public.meeting_my_settings();
end $fn$;

create function app.mtg_user_write(p_staff uuid, p_values jsonb, p_allowed text[], p_actor uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare u app.meeting_user_settings := app.mtg_user(p_staff); v_mb uuid;
begin
  perform app.prj_keys(p_values, p_allowed);
  if p_values ? 'enabled' then
    if jsonb_typeof(p_values -> 'enabled') <> 'boolean' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'enabled'; end if;
    u.enabled := (p_values ->> 'enabled')::boolean;
  end if;
  if p_values ? 'bot_auto_join' then
    if coalesce(p_values ->> 'bot_auto_join', '') not in ('external', 'all', 'off') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'bot_auto_join'; end if;
    u.bot_auto_join := p_values ->> 'bot_auto_join';
  end if;
  if p_values ? 'brief_instructions' then u.brief_instructions := app.prj_text(p_values, 'brief_instructions', 0, 2000); end if;
  if p_values ? 'mailbox_id' then
    v_mb := app.prj_uuid(p_values, 'mailbox_id');
    if v_mb is not null and not exists (select 1 from app.mailboxes mb where mb.id = v_mb and mb.deleted_at is null
                                        and (mb.owner_id = p_staff or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = mb.id and mm.staff_id = p_staff))) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mailbox_id';
    end if;
    u.mailbox_id := v_mb;
  end if;
  insert into app.meeting_user_settings (staff_id, enabled, bot_auto_join, brief_instructions, mailbox_id, updated_by, updated_at)
  values (p_staff, u.enabled, u.bot_auto_join, u.brief_instructions, u.mailbox_id, p_actor, now())
  on conflict (staff_id) do update set enabled = excluded.enabled, bot_auto_join = excluded.bot_auto_join, brief_instructions = excluded.brief_instructions,
    mailbox_id = excluded.mailbox_id, updated_by = excluded.updated_by, updated_at = now();
  perform app.mtg_refresh_owner(p_staff);
end $fn$;

-- an attendee's objection told to the owner (art. 21): recorded like the link in the notice; «always» keeps the hash
create function public.meeting_opt_out_staff(p_id uuid, p_email text, p_always boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id, true);
begin
  perform app.mtg_require_edit(m);
  update app.meeting_attendees set opted_out_at = coalesce(opted_out_at, now()) where meeting_id = m.id and email = lower(btrim(p_email));
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'email'; end if;
  if coalesce(p_always, false) then
    insert into app.recording_opt_outs (email_sha256, via) values (app.email_hash(p_email), 'staff') on conflict do nothing;
  end if;
  perform app.mtg_after_opt_out(m.id);
  perform app.log('meeting.opted_out', 'meeting', m.id::text, jsonb_build_object('via', 'staff', 'always', coalesce(p_always, false)));
  return jsonb_build_object('id', m.id, 'opted_out', true);
end $fn$;

-- after an opt-out: a bot in the call leaves, a scheduled one is blocked, the owner is told (counts only)
create function app.mtg_after_opt_out(p_meeting uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings;
begin
  select * into m from app.meetings where id = p_meeting for update;
  if m.bot_state in ('joining', 'in_call') then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_leave', 'meeting_id', m.id));
    update app.meetings set bot_state = 'blocked', bot_block_reason = 'opted_out' where id = m.id;
  else
    perform app.mtg_refresh(m.id);
  end if;
  if m.owner_id is not null then
    perform app.notify(m.owner_id, 'system', 'meeting.opted_out', jsonb_build_object('record', m.title), '/meetings?meeting=' || m.id, 'meeting', m.id);
  end if;
  insert into app.events (kind, subject_type, subject_id, payload, is_sample) values ('meeting.opted_out', 'meeting', m.id, jsonb_build_object('count', 1), m.is_sample);
end $fn$;

-- the opt-out link in a notice or the in-call chat line (D-28: go.owntheagenda.com, the edge function calls this with the
-- service role). An attendee's token opts that address out of this meeting, and with p_always out of every meeting; the
-- call's token makes the bot leave this meeting. → {date, organiser_company}; nothing else (no title, no attendees).
create function public.meeting_opt_out(p_token text, p_always boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.meeting_attendees; m app.meetings; v_hash bytea := app.token_hash(p_token);
begin
  if p_token is null or char_length(p_token) not between 20 and 200 then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into a from app.meeting_attendees where opt_out_token_sha256 = v_hash;
  if found then
    update app.meeting_attendees set opted_out_at = coalesce(opted_out_at, now()) where meeting_id = a.meeting_id and email = a.email;
    if coalesce(p_always, false) then
      insert into app.recording_opt_outs (email_sha256, via) values (app.email_hash(a.email), 'notice_link') on conflict do nothing;
    end if;
    select * into m from app.meetings where id = a.meeting_id;
  else
    select * into m from app.meetings where call_opt_out_sha256 = v_hash;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if m.bot_state not in ('joining', 'in_call') then
      update app.meetings set bot_state = 'blocked', bot_block_reason = 'opted_out' where id = m.id and bot_state in ('scheduled', 'left', 'none');
    end if;
  end if;
  if m.deleted_at is not null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.mtg_after_opt_out(m.id);
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.opted_out', 'meeting', m.id::text, jsonb_build_object('via', case when a.email is not null then 'notice_link' else 'call_link' end, 'always', coalesce(p_always, false) and a.email is not null), true);
  return jsonb_build_object('date', (m.starts_at at time zone 'Europe/Oslo')::date, 'organiser_company', app.mtg_controller());
end $fn$;

-- ===========================================================================
-- workers (service role only): what the calendar, the mailer, the bot, transcription and the AI provider did
-- ===========================================================================
-- a calendar event (§2.7 «Calendar scan», SF-21.1). p_event {external_event_id, title, starts_at, ends_at, join_url,
-- conference, attendees: [{email, name, response}], cancelled}. Kept when it has a join link or an external guest.
-- → {id | null, created, skipped}
create function public.worker_meeting_upsert(p_staff uuid, p_event jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  m app.meetings; v_ext_id text; v_title text; v_start timestamptz; v_end timestamptz; v_url text; v_conf text; v_created boolean := false;
  x jsonb; v_email text; v_staff uuid; v_person uuid; v_has_ext boolean := false; u app.meeting_user_settings := app.mtg_user(p_staff);
  v_cal text; v_act app.activities; v_deal uuid; v_old_start timestamptz;
begin
  if not exists (select 1 from app.admins a where a.id = p_staff and a.active) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'staff'; end if;
  select c.account_email into v_cal from app.calendar_connections c where c.staff_id = p_staff and c.status = 'connected';
  if not found then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'calendar'; end if;
  if not app.module_on('meetings') then return jsonb_build_object('id', null, 'created', false, 'skipped', 'module_off'); end if;
  if not u.enabled then return jsonb_build_object('id', null, 'created', false, 'skipped', 'disabled'); end if;
  perform app.prj_keys(p_event, array['external_event_id', 'title', 'starts_at', 'ends_at', 'join_url', 'conference', 'attendees', 'cancelled']);
  v_ext_id := app.prj_text(p_event, 'external_event_id', 1, 500);
  v_title := coalesce(app.prj_text(p_event, 'title', 0, 300), '—');
  begin
    v_start := (p_event ->> 'starts_at')::timestamptz; v_end := (p_event ->> 'ends_at')::timestamptz;
  exception when others then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at';
  end;
  if v_start is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at'; end if;
  if v_end < v_start then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ends_at'; end if;
  v_url := app.prj_text(p_event, 'join_url', 0, 1000);
  if v_url is not null and v_url !~ '^https://' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'join_url'; end if;
  v_conf := coalesce(p_event ->> 'conference', case when v_url ~ '^https://meet\.google\.com/' then 'meet'
                                                    when v_url ~ '^https://([a-z0-9-]+\.)?teams\.(microsoft|live)\.com/' then 'teams'
                                                    when v_url ~ '^https://([a-z0-9-]+\.)?zoom\.us/' then 'zoom'
                                                    when v_url is not null then 'other' end);
  if v_conf is not null and v_conf not in ('meet', 'teams', 'zoom', 'phone', 'in_person', 'other') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'conference'; end if;
  if jsonb_typeof(coalesce(p_event -> 'attendees', '[]'::jsonb)) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'attendees'; end if;
  for x in select value from jsonb_array_elements(coalesce(p_event -> 'attendees', '[]'::jsonb)) loop
    v_email := lower(btrim(x ->> 'email'));
    if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+$' or char_length(v_email) > 254 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'attendees'; end if;
    if not exists (select 1 from app.admins a where a.email = v_email) and v_email is distinct from lower(v_cal) then v_has_ext := true; end if;
  end loop;

  select * into m from app.meetings where calendar_staff_id = p_staff and external_event_id = v_ext_id for update;
  if not found then
    if v_url is null and not v_has_ext then return jsonb_build_object('id', null, 'created', false, 'skipped', 'not_relevant'); end if;
    insert into app.meetings (title, starts_at, ends_at, source, calendar_staff_id, external_event_id, conference, join_url, capture, owner_id, visibility, created_by, updated_by)
    values (v_title, v_start, v_end, 'calendar', p_staff, v_ext_id, v_conf, v_url,
            case when app.connected('meeting_bot') and v_url is not null and (u.bot_auto_join = 'all' or (u.bot_auto_join = 'external' and v_has_ext)) then 'bot' else 'none' end,
            p_staff, app.mtg_visibility_default(), p_staff, p_staff)
    returning * into m;
    v_created := true;
  else
    v_old_start := m.starts_at;
    update app.meetings set title = v_title, starts_at = v_start, ends_at = v_end, conference = v_conf, join_url = v_url,
      version = version + 1, updated_at = now(), updated_by = p_staff,
      notice_queued_at = case when v_start is distinct from v_old_start then null else notice_queued_at end
    where id = m.id returning * into m;
  end if;

  -- attendees: matched to staff (their address or the calendar account) and to people by address
  delete from app.meeting_attendees a where a.meeting_id = m.id
    and a.email not in (select lower(btrim(y ->> 'email')) from jsonb_array_elements(coalesce(p_event -> 'attendees', '[]'::jsonb)) y);
  for x in select value from jsonb_array_elements(coalesce(p_event -> 'attendees', '[]'::jsonb)) loop
    v_email := lower(btrim(x ->> 'email'));
    v_staff := coalesce((select a.id from app.admins a where a.email = v_email), case when v_email = lower(v_cal) then p_staff end);
    v_person := case when v_staff is null then (select min(p.id::text)::uuid from app.people p where lower(p.email) = v_email and p.deleted_at is null) end;
    insert into app.meeting_attendees (meeting_id, email, name, person_id, staff_id, external, response)
    values (m.id, v_email, left(nullif(btrim(x ->> 'name'), ''), 200), v_person, v_staff, v_staff is null,
            case when x ->> 'response' in ('needs_action', 'accepted', 'tentative', 'declined') then x ->> 'response' else 'needs_action' end)
    on conflict (meeting_id, email) do update set name = excluded.name, person_id = excluded.person_id, staff_id = excluded.staff_id,
      external = excluded.external, response = excluded.response;
  end loop;

  -- a new meeting is linked like its calendar activity, else to the open deal of an attendee or their organisation
  if v_created then
    select * into v_act from app.activities a where a.owner_id = p_staff and a.deleted_at is null and v_url is not null and a.video_url = v_url
    order by a.starts_at desc nulls last limit 1;
    if v_act.id is not null and not exists (select 1 from app.meetings o where o.activity_id = v_act.id) then
      update app.meetings set activity_id = v_act.id, deal_id = v_act.deal_id, lead_id = v_act.lead_id, person_id = v_act.person_id, organization_id = v_act.organization_id
      where id = m.id;
    else
      select a.person_id into v_person from app.meeting_attendees a join app.people p on p.id = a.person_id
      where a.meeting_id = m.id and a.external order by p.created_at limit 1;
      if v_person is not null then
        v_deal := coalesce((select d.id from app.deals d where d.person_id = v_person and d.status = 'open' and d.deleted_at is null order by d.updated_at desc limit 1),
                           (select d.id from app.deals d join app.people p on p.organization_id = d.organization_id
                            where p.id = v_person and d.status = 'open' and d.deleted_at is null order by d.updated_at desc limit 1));
        update app.meetings set person_id = v_person, organization_id = (select p.organization_id from app.people p where p.id = v_person), deal_id = v_deal
        where id = m.id;
      end if;
    end if;
  end if;

  -- cancelled: the bot does not go
  if coalesce((p_event ->> 'cancelled')::boolean, false) and m.cancelled_at is null then
    if m.bot_state in ('joining', 'in_call') then perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_leave', 'meeting_id', m.id)); end if;
    update app.meetings set cancelled_at = now(), bot_state = case when bot_state in ('joining', 'in_call', 'scheduled', 'blocked') then 'none' else bot_state end,
      bot_block_reason = null where id = m.id;
  end if;
  m := app.mtg_refresh(m.id);
  select * into m from app.meetings where id = m.id;
  insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
  values (case when v_created then 'meeting.scheduled' else 'meeting.updated' end, 'meeting', m.id, p_staff,
          jsonb_build_object('deal', m.deal_id, 'lead', m.lead_id, 'person', m.person_id, 'organization', m.organization_id), m.is_sample);
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', case when v_created then 'meeting.scheduled' else 'meeting.updated' end, 'meeting', m.id::text,
          jsonb_build_object('attendees', (select count(*) from app.meeting_attendees where meeting_id = m.id), 'capture', m.capture), true);
  return jsonb_build_object('id', m.id, 'created', v_created, 'skipped', null);
end $fn$;

-- the mailer claims a meeting's notices: the external guests not yet told and not opted out, each with a fresh opt-out
-- token (only its SHA-256 is stored), and what the notice must say (art. 13: who records, why, how long, the controller)
create function public.worker_notice_claim(p_meeting uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; v_list jsonb := '[]'::jsonb; a record; v_token text;
begin
  select * into m from app.meetings where id = p_meeting and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if m.notice_state <> 'pending' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'notice_state'; end if;
  perform app.require_connected('email');
  for a in select * from app.meeting_attendees where meeting_id = m.id and external and notice_sent_at is null and opted_out_at is null order by email loop
    v_token := app.token() || app.token();
    update app.meeting_attendees set opt_out_token_sha256 = app.token_hash(v_token) where meeting_id = m.id and email = a.email;
    v_list := v_list || jsonb_build_object('email', a.email, 'name', a.name, 'token', v_token);
  end loop;
  return jsonb_build_object('meeting_id', m.id, 'starts_at', m.starts_at, 'ends_at', m.ends_at,
    'owner', (select jsonb_build_object('name', ad.name, 'email', ad.email, 'locale', ad.locale) from app.admins ad where ad.id = m.owner_id),
    'controller', app.mtg_controller(), 'retention_months', app.mtg_retention_months(), 'bot_name_suffix', '(recording)',
    'attendees', v_list);
end $fn$;

-- one notice sent or failed. A failure blocks the bot (fail closed, §2.7); when every external guest is told the
-- meeting's notice is «sent».
create function public.worker_notice_result(p_meeting uuid, p_email text, p_ok boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings;
begin
  select * into m from app.meetings where id = p_meeting for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not exists (select 1 from app.meeting_attendees where meeting_id = m.id and email = lower(btrim(p_email)) and external) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'email';
  end if;
  if coalesce(p_ok, false) then
    update app.meeting_attendees set notice_sent_at = now() where meeting_id = m.id and email = lower(btrim(p_email));
    m := app.mtg_refresh(m.id);
    if m.notice_state = 'sent' then
      insert into app.events (kind, subject_type, subject_id, payload, is_sample)
      values ('meeting.notice_sent', 'meeting', m.id, jsonb_build_object('count', (select count(*) from app.meeting_attendees where meeting_id = m.id and notice_sent_at is not null)), m.is_sample);
    end if;
  else
    update app.meetings set notice_state = 'blocked' where id = m.id;
    m := app.mtg_refresh(m.id);
    if m.owner_id is not null then
      perform app.notify(m.owner_id, 'system', 'meeting.notice_blocked', jsonb_build_object('record', m.title), '/meetings?meeting=' || m.id, 'meeting', m.id);
    end if;
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.notice', 'meeting', m.id::text, jsonb_build_object('ok', coalesce(p_ok, false), 'state', m.notice_state), true);
  return jsonb_build_object('ok', true, 'notice_state', m.notice_state, 'bot_state', m.bot_state);
end $fn$;

-- the bot's state as the provider reports it. Joining a call re-checks consent: a guest who opted out since makes the
-- bot leave. In the call the bot posts its fixed chat line with the call's opt-out link (§8.3): the token is returned
-- here, once. → {ok, leave, opt_out_token?}
create function public.worker_bot_state(p_meeting uuid, p_state text, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; v_reason text; v_token text;
begin
  select * into m from app.meetings where id = p_meeting for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_state is null or p_state not in ('in_call', 'left', 'failed', 'removed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if p_reason is not null and p_reason !~ '^[a-z_]{1,80}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reason'; end if;
  if m.bot_state not in ('joining', 'in_call') then
    -- removed or blocked meanwhile: whatever the bot is doing, it leaves
    return jsonb_build_object('ok', true, 'leave', p_state = 'in_call', 'bot_state', m.bot_state);
  end if;
  if p_state = 'in_call' then
    v_reason := app.mtg_bot_block(m, true);
    if v_reason is not null then
      update app.meetings set bot_state = 'blocked', bot_block_reason = v_reason where id = m.id;
      insert into app.audit (actor, action, target_type, target_id, detail, ok)
      values ('system', 'meeting.bot_blocked', 'meeting', m.id::text, jsonb_build_object('reason', v_reason), true);
      return jsonb_build_object('ok', true, 'leave', true, 'bot_state', 'blocked');
    end if;
    v_token := app.token() || app.token();
    update app.meetings set bot_state = 'in_call', call_opt_out_sha256 = app.token_hash(v_token) where id = m.id;
  else
    update app.meetings set bot_state = p_state where id = m.id;
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.bot_state', 'meeting', m.id::text, jsonb_build_object('from', m.bot_state, 'to', p_state, 'reason', p_reason), true);
  return jsonb_build_object('ok', true, 'leave', false, 'bot_state', p_state, 'opt_out_token', v_token);
end $fn$;

-- a recording is in storage (bucket «meeting-files», path recording/<meeting>/…). The consent gate (§8.3): a bot
-- recording only from a bot that was admitted and with every rule still holding; a desktop recording only with the
-- user's confirmation that participants were told, and never over an opt-out. A refused recording is not stored and its
-- file is queued for deletion. p_values {method, provider, provider_ref, storage_path, duration_s, started_at, ended_at,
-- participants_confirmed_at}. → {ok, recording_id?, transcript_id?, refused?}
create function public.worker_recording_ready(p_meeting uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; v_method text := p_values ->> 'method'; v_path text := p_values ->> 'storage_path'; v_reason text; v_rec uuid; v_t uuid;
  v_confirmed timestamptz; v_dur int;
begin
  select * into m from app.meetings where id = p_meeting and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.prj_keys(p_values, array['method', 'provider', 'provider_ref', 'storage_path', 'duration_s', 'started_at', 'ended_at', 'participants_confirmed_at']);
  if v_method is null or v_method not in ('bot', 'desktop') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'method'; end if;
  if v_path is null or v_path !~ ('^recording/' || m.id || '/[A-Za-z0-9][A-Za-z0-9._-]{0,200}$') or v_path ~ '\.\.' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'storage_path';
  end if;
  v_dur := app.prj_int(p_values, 'duration_s', 0, 86400);
  begin
    v_confirmed := (p_values ->> 'participants_confirmed_at')::timestamptz;
  exception when others then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'participants_confirmed_at';
  end;
  v_reason := case
    when not app.module_on('meetings') or not (app.mtg_user(m.owner_id)).enabled then 'disabled'
    when app.mtg_opted_out(m.id) then 'opted_out'
    when v_method = 'bot' and m.bot_state not in ('in_call', 'left') then coalesce(m.bot_block_reason, 'bot_not_admitted')
    when v_method = 'bot' then app.mtg_bot_block(m, true)
    when v_method = 'desktop' and v_confirmed is null then 'not_confirmed'
    else null end;
  if v_reason is not null then
    perform app.mtg_storage_forget(array[v_path]);
    insert into app.audit (actor, action, target_type, target_id, detail, ok)
    values ('system', 'meeting.recording_refused', 'meeting', m.id::text, jsonb_build_object('method', v_method, 'reason', v_reason), true);
    return jsonb_build_object('ok', false, 'refused', v_reason);
  end if;
  insert into app.meeting_recordings (meeting_id, method, provider, provider_ref, storage_path, duration_s, started_at, ended_at, participants_confirmed_at, state, purge_after)
  values (m.id, v_method, left(p_values ->> 'provider', 40), left(p_values ->> 'provider_ref', 500), v_path, v_dur,
          (p_values ->> 'started_at')::timestamptz, (p_values ->> 'ended_at')::timestamptz, v_confirmed,
          case when app.connected('transcription') then 'processing' else 'ready' end, now() + app.mtg_retention())
  returning id into v_rec;
  update app.meetings set capture = v_method where id = m.id and capture <> v_method;
  if app.connected('transcription') then
    insert into app.meeting_transcripts (meeting_id, recording_id, source, state, duration_s, provider)
    values (m.id, v_rec, 'provider', 'processing', v_dur, (select provider from app.meeting_recordings where id = v_rec)) returning id into v_t;
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_transcribe', 'transcript_id', v_t, 'recording_id', v_rec, 'meeting_id', m.id));
  end if;
  insert into app.events (kind, subject_type, subject_id, payload, is_sample) values ('meeting.recorded', 'meeting', m.id, jsonb_build_object('duration_s', v_dur, 'method', v_method), m.is_sample);
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.recorded', 'meeting', m.id::text, jsonb_build_object('recording', v_rec, 'method', v_method, 'transcribing', v_t is not null), true);
  return jsonb_build_object('ok', true, 'recording_id', v_rec, 'transcript_id', v_t);
end $fn$;

-- the provider's transcript: p_segments [{start_ms, end_ms, speaker, text}] or {language, segments}; p_speakers
-- [{label, email}] hints; null segments or p_error = failed (the recording is kept for Retry). → {ok, segments}
create function public.worker_transcript_ready(p_transcript uuid, p_segments jsonb, p_speakers jsonb default null, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.meeting_transcripts; n int := 0; v_segs jsonb := case when jsonb_typeof(p_segments) = 'object' then p_segments -> 'segments' else p_segments end;
  v_lang text := case when jsonb_typeof(p_segments) = 'object' then p_segments ->> 'language' end;
begin
  select * into t from app.meeting_transcripts where id = p_transcript for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.state <> 'processing' or t.source <> 'provider' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if p_error is not null and p_error !~ '^[a-z_]{1,80}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'error'; end if;
  if v_lang is not null and char_length(v_lang) not between 2 and 20 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'language'; end if;
  if p_error is not null or v_segs is null then
    update app.meeting_recordings set state = 'failed', error_code = coalesce(p_error, 'provider_failed') where id = t.recording_id and state = 'processing';
    perform app.mtg_transcript_done(t.id, false, coalesce(p_error, 'provider_failed'));
    return jsonb_build_object('ok', true, 'segments', 0);
  end if;
  n := app.mtg_segments_store(t.id, v_segs);
  perform app.mtg_speakers_map(t.id, p_speakers);
  update app.meeting_transcripts set language = v_lang where id = t.id;
  update app.meeting_recordings set state = 'ready', error_code = null where id = t.recording_id and state = 'processing';
  perform app.mtg_transcript_done(t.id, true, null);
  return jsonb_build_object('ok', true, 'segments', n);
end $fn$;

-- an uploaded file parsed (VTT voices, SRT timings, TXT «Name: text», DOCX paragraphs); null = it could not be read.
-- Either way the original file is deleted from storage now.
create function public.worker_upload_parsed(p_upload uuid, p_segments jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare u app.meeting_uploads; n int := 0; v_segs jsonb := case when jsonb_typeof(p_segments) = 'object' then p_segments -> 'segments' else p_segments end;
  v_lang text := case when jsonb_typeof(p_segments) = 'object' then p_segments ->> 'language' end;
begin
  select * into u from app.meeting_uploads where id = p_upload for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if u.state <> 'uploaded' or u.transcript_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if v_lang is not null and char_length(v_lang) not between 2 and 20 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'language'; end if;
  perform app.mtg_storage_forget(array[u.storage_path]);
  if v_segs is null or jsonb_typeof(v_segs) <> 'array' or jsonb_array_length(v_segs) = 0 then
    update app.meeting_uploads set state = 'failed', parsed_at = now() where id = u.id;
    perform app.mtg_transcript_done(u.transcript_id, false, 'parse_failed');
    return jsonb_build_object('ok', true, 'segments', 0);
  end if;
  n := app.mtg_segments_store(u.transcript_id, v_segs);
  perform app.mtg_speakers_map(u.transcript_id, null);
  update app.meeting_transcripts set language = v_lang where id = u.transcript_id;
  update app.meeting_uploads set state = 'parsed', parsed_at = now() where id = u.id;
  perform app.mtg_transcript_done(u.transcript_id, true, null);
  return jsonb_build_object('ok', true, 'segments', n);
end $fn$;

-- an AI call checked against the log: it exists, it was for this feature, and it succeeded
create function app.ai_call_ok(p_id bigint, p_feature text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select p_id is null or exists (select 1 from app.ai_calls c where c.id = p_id and c.feature = p_feature and c.state in ('ok', 'retried_ok')) $fn$;

-- quotes for «From earlier conversations» (§2.2). p_quotes {state: 'ready' | 'failed', ai_call_id, quotes: [{text,
-- source: {kind: 'segment', transcript_id, seq} | {kind: 'note', note_id}}]}. The anti-fabrication check: a quote is
-- kept only when it is an exact substring of the source it cites, and that source belongs to the same deal, lead,
-- organisation or people; speaker and date come from the source, never from the model. → {ok, kept, dropped}
create function public.worker_brief_quotes_ready(p_meeting uuid, p_quotes jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; b app.meeting_briefs; x jsonb; v_kept jsonb := '[]'::jsonb; v_dropped int := 0; v_people uuid[]; v_orgs uuid[]; v_q jsonb;
  v_ok boolean := coalesce(p_quotes ->> 'state', '') = 'ready'; v_call bigint;
begin
  select * into m from app.meetings where id = p_meeting and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into b from app.meeting_briefs where meeting_id = m.id for update;
  if not found or b.quotes_state <> 'requested' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'quotes_state'; end if;
  if jsonb_typeof(p_quotes) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'quotes'; end if;
  v_call := (p_quotes ->> 'ai_call_id')::bigint;
  if not app.ai_call_ok(v_call, 'meeting_brief') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ai_call_id'; end if;
  if v_ok then
    if jsonb_typeof(coalesce(p_quotes -> 'quotes', '[]'::jsonb)) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'quotes'; end if;
    v_people := app.mtg_people(m); v_orgs := app.mtg_orgs(m);
    for x in select value from jsonb_array_elements(coalesce(p_quotes -> 'quotes', '[]'::jsonb)) loop
      v_q := null;
      if jsonb_typeof(x) = 'object' and jsonb_typeof(x -> 'text') = 'string' and char_length(btrim(x ->> 'text')) between 3 and 500 then
        if x #>> '{source,kind}' = 'segment' and (x #>> '{source,seq}') ~ '^\d{1,9}$' and (x #>> '{source,transcript_id}') ~ '^[0-9a-f-]{36}$' then
          select jsonb_build_object('text', btrim(x ->> 'text'), 'kind', 'segment', 'transcript_id', s.transcript_id, 'seq', s.seq, 'meeting_id', o.id,
                                    'speaker', coalesce(ad.name, p.name, s.speaker_label), 'person_id', sp.person_id, 'at', o.starts_at,
                                    'record', case when o.deal_id is not null then jsonb_build_object('entity', 'deal', 'id', o.deal_id)
                                                   when o.lead_id is not null then jsonb_build_object('entity', 'lead', 'id', o.lead_id)
                                                   when o.organization_id is not null then jsonb_build_object('entity', 'organization', 'id', o.organization_id) end)
          into v_q
          from app.transcript_segments s join app.meeting_transcripts t on t.id = s.transcript_id join app.meetings o on o.id = t.meeting_id
          left join app.transcript_speakers sp on sp.transcript_id = s.transcript_id and sp.label = s.speaker_label
          left join app.admins ad on ad.id = sp.staff_id left join app.people p on p.id = sp.person_id
          where s.transcript_id = (x #>> '{source,transcript_id}')::uuid and s.seq = (x #>> '{source,seq}')::int and s.redacted_at is null
            and o.deleted_at is null and position(btrim(x ->> 'text') in s.text) > 0
            and (o.deal_id = m.deal_id or o.lead_id = m.lead_id or o.organization_id = any (v_orgs)
                 or exists (select 1 from app.meeting_attendees oa where oa.meeting_id = o.id and oa.person_id = any (v_people)));
        elsif x #>> '{source,kind}' = 'note' and (x #>> '{source,note_id}') ~ '^[0-9a-f-]{36}$' then
          select jsonb_build_object('text', btrim(x ->> 'text'), 'kind', 'note', 'note_id', n.id, 'speaker', ad.name, 'person_id', null, 'at', n.created_at,
                                    'record', jsonb_build_object('entity', n.entity, 'id', n.record_id))
          into v_q
          from app.notes n left join app.admins ad on ad.id = n.author_id
          where n.id = (x #>> '{source,note_id}')::uuid and n.deleted_at is null and position(btrim(x ->> 'text') in n.body) > 0
            and ((n.entity = 'deal' and n.record_id = m.deal_id) or (n.entity = 'lead' and n.record_id = m.lead_id)
                 or (n.entity = 'organization' and n.record_id = any (v_orgs)) or (n.entity = 'person' and n.record_id = any (v_people)));
        end if;
      end if;
      if v_q is null or jsonb_array_length(v_kept) >= 10 then v_dropped := v_dropped + 1; else v_kept := v_kept || v_q; end if;
    end loop;
  end if;
  update app.meeting_briefs set quotes = case when v_ok then v_kept else '[]'::jsonb end, quotes_state = case when v_ok then 'ready' else 'failed' end,
    ai_call_id = coalesce(v_call, ai_call_id)
  where meeting_id = m.id;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.brief_quotes', 'meeting', m.id::text, jsonb_build_object('ok', v_ok, 'kept', jsonb_array_length(v_kept), 'dropped', v_dropped), true);
  return jsonb_build_object('ok', true, 'kept', jsonb_array_length(v_kept), 'dropped', v_dropped);
end $fn$;

-- the recap and the suggestions from one AI call (§2.3, §2.4). p_recap {state: 'ready' | 'failed', ai_call_id,
-- takeaways: [{text, seq?}], next_steps: [{text, seq?}]}; p_suggestions [{target_entity, target_id, field, value, evidence}].
-- Every suggestion is checked against the register: a target linked to the meeting, a writable plain field, a live
-- custom field or the labels, a value of the right type; a new person only with a name. The rest are dropped. The
-- current value and version are taken now. → {ok, suggestions, dropped}
create function public.worker_recap_ready(p_transcript uuid, p_recap jsonb, p_suggestions jsonb default '[]'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  t app.meeting_transcripts; m app.meetings; r app.meeting_recaps; v_ok boolean := coalesce(p_recap ->> 'state', '') = 'ready'; v_call bigint;
  v_take jsonb; v_next jsonb; x jsonb; v_kind text; v_field text; v_entity text; v_target uuid; v_value jsonb; v_good boolean; v_cur jsonb; v_ver int;
  e app.entities; v_row jsonb; n int := 0; v_dropped int := 0;
begin
  select * into t from app.meeting_transcripts where id = p_transcript;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into m from app.meetings where id = t.meeting_id;
  select * into r from app.meeting_recaps where transcript_id = t.id for update;
  if not found or r.state <> 'requested' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if jsonb_typeof(p_recap) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recap'; end if;
  v_call := (p_recap ->> 'ai_call_id')::bigint;
  if not app.ai_call_ok(v_call, 'meeting_recap') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ai_call_id'; end if;
  if not v_ok then
    update app.meeting_recaps set state = 'failed', generated_at = now(), ai_call_id = coalesce(v_call, ai_call_id) where transcript_id = t.id;
  else
    -- takeaways and next steps: text ≤ 500; a seq that is not in the transcript is dropped
    foreach v_kind in array array['takeaways', 'next_steps'] loop
      if jsonb_typeof(coalesce(p_recap -> v_kind, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_recap -> v_kind, '[]'::jsonb)) > 20
         or exists (select 1 from jsonb_array_elements(coalesce(p_recap -> v_kind, '[]'::jsonb)) y
                    where jsonb_typeof(y) <> 'object' or jsonb_typeof(y -> 'text') <> 'string' or char_length(btrim(y ->> 'text')) not between 1 and 500) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_kind;
      end if;
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object('text', btrim(y ->> 'text'), 'seq',
             case when (y ->> 'seq') ~ '^\d{1,9}$' and exists (select 1 from app.transcript_segments s where s.transcript_id = t.id and s.seq = (y ->> 'seq')::int) then (y ->> 'seq')::int end)
             order by o), '[]'::jsonb) into v_take from jsonb_array_elements(coalesce(p_recap -> 'takeaways', '[]'::jsonb)) with ordinality q(y, o);
    select coalesce(jsonb_agg(jsonb_build_object('text', btrim(y ->> 'text'), 'seq',
             case when (y ->> 'seq') ~ '^\d{1,9}$' and exists (select 1 from app.transcript_segments s where s.transcript_id = t.id and s.seq = (y ->> 'seq')::int) then (y ->> 'seq')::int end)
             order by o), '[]'::jsonb) into v_next from jsonb_array_elements(coalesce(p_recap -> 'next_steps', '[]'::jsonb)) with ordinality q(y, o);
    update app.meeting_recaps set state = 'ready', takeaways = v_take, next_steps = v_next, generated_at = now(), ai_call_id = v_call where transcript_id = t.id;

    if jsonb_typeof(coalesce(p_suggestions, '[]'::jsonb)) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'suggestions'; end if;
    delete from app.meeting_suggestions where transcript_id = t.id and state = 'pending';
    for x in select value from jsonb_array_elements(coalesce(p_suggestions, '[]'::jsonb)) limit 50 loop
      v_good := false; v_cur := null; v_ver := null;
      v_entity := x ->> 'target_entity'; v_field := x ->> 'field'; v_value := x -> 'value';
      begin
        v_target := (x ->> 'target_id')::uuid;
      exception when others then v_target := null; v_entity := null;
      end;
      if jsonb_typeof(x) = 'object' and v_entity in ('deal', 'lead', 'person', 'organization') and v_value is not null
         and v_field ~ '^(custom\.[a-z][a-z0-9_]{1,40}|labels|\*new|[a-z_][a-z0-9_]{0,40})$' then
        if v_field = '*new' then
          v_good := v_entity = 'person' and v_target is null and jsonb_typeof(v_value) = 'object'
                    and jsonb_typeof(v_value -> 'name') = 'string' and char_length(btrim(v_value ->> 'name')) between 1 and 200
                    and not exists (select 1 from jsonb_object_keys(v_value) k where k not in ('name', 'title', 'email', 'phone', 'organization_id'))
                    and not exists (select 1 from jsonb_each(v_value) kv where jsonb_typeof(kv.value) not in ('string', 'null') or char_length(kv.value #>> '{}') > 254)
                    and (v_value ->> 'organization_id' is null or (v_value ->> 'organization_id')::text in (select id::text from app.mtg_targets(m) where entity = 'organization'));
        elsif v_target is not null and exists (select 1 from app.mtg_targets(m) g where g.entity = v_entity and g.id = v_target) then
          select * into e from app.entities where key = v_entity;
          execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null', e.tbl, v_target) into v_row;
          if v_row is not null then
            if v_field = 'labels' then
              v_good := jsonb_typeof(v_value) = 'array'
                        and not exists (select 1 from jsonb_array_elements(v_value) l where jsonb_typeof(l) <> 'string'
                                        or not exists (select 1 from app.labels lb where lb.id::text = l #>> '{}' and lb.entity = v_entity));
              v_cur := v_row -> 'labels';
            elsif v_field like 'custom.%' then
              begin
                perform app.check_custom(v_entity, jsonb_build_object(substr(v_field, 8), v_value));
                v_good := jsonb_typeof(v_value) <> 'null';
              exception when invalid_parameter_value or insufficient_privilege then v_good := false;
              end;
              v_cur := v_row -> 'custom' -> substr(v_field, 8);
            else
              select case c.kind when 'text' then jsonb_typeof(v_value) = 'string' and char_length(v_value #>> '{}') <= 10000
                                 when 'int' then jsonb_typeof(v_value) = 'number' and (v_value #>> '{}') ~ '^-?\d{1,9}$'
                                 when 'numeric' then jsonb_typeof(v_value) = 'number'
                                 when 'boolean' then jsonb_typeof(v_value) = 'boolean'
                                 when 'date' then jsonb_typeof(v_value) = 'string' and (v_value #>> '{}') ~ '^\d{4}-\d{2}-\d{2}$'
                                 else false end
              into v_good
              from app.entity_columns c where c.entity = v_entity and c.col = v_field and c.writable and c.col not in ('owner_id', 'visibility');
              v_cur := v_row -> v_field;
            end if;
            v_ver := (v_row ->> 'version')::int;
          end if;
        end if;
      end if;
      if coalesce(v_good, false) then
        n := n + 1;
        insert into app.meeting_suggestions (meeting_id, transcript_id, ord, target_entity, target_id, field, current_value, base_version, proposed_value, evidence)
        values (m.id, t.id, n, v_entity, case when v_field = '*new' then null else v_target end, v_field, v_cur, v_ver, v_value,
                array(select (ev #>> '{}')::int from jsonb_array_elements(case when jsonb_typeof(x -> 'evidence') = 'array' then x -> 'evidence' else '[]'::jsonb end) ev
                      where (ev #>> '{}') ~ '^\d{1,9}$' and exists (select 1 from app.transcript_segments s where s.transcript_id = t.id and s.seq = (ev #>> '{}')::int)));
      else
        v_dropped := v_dropped + 1;
      end if;
    end loop;
    v_dropped := v_dropped + greatest(jsonb_array_length(coalesce(p_suggestions, '[]'::jsonb)) - 50, 0);
    insert into app.events (kind, subject_type, subject_id, payload, is_sample)
    values ('meeting.recap_ready', 'meeting', m.id, jsonb_build_object('transcript', t.id, 'suggestions', n), m.is_sample);
    -- the announcement in Slack (MTG-04 RU, INT-07) when it is connected; in-app otherwise
    if app.connected('slack') then
      perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_recap_announce', 'meeting_id', m.id, 'transcript_id', t.id));
      update app.meeting_recaps set announced_at = now() where transcript_id = t.id;
    end if;
  end if;
  if m.owner_id is not null then
    perform app.notify(m.owner_id, 'system', case when v_ok then 'meeting.recap_ready' else 'meeting.recap_failed' end,
                       jsonb_build_object('record', m.title, 'suggestions', n), '/meetings?meeting=' || m.id, 'meeting', m.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.recap', 'meeting', m.id::text, jsonb_build_object('ok', v_ok, 'suggestions', n, 'dropped', v_dropped), true);
  return jsonb_build_object('ok', true, 'suggestions', n, 'dropped', v_dropped);
end $fn$;

-- what the AI worker may send the provider (SF-24.2, the firewall of D-19/D-34): CRM tables only, never a product table.
-- p_job {feature: 'meeting_recap', transcript_id} → the transcript, the linked records' writable values, the field
-- register and the labels; {feature: 'meeting_brief', meeting_id} → earlier segments and notes on the same deal, lead,
-- organisations and people, and the owner's brief instructions. Redacted segments are never sent.
create function public.worker_meeting_ai_context(p_job jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m app.meetings; t app.meeting_transcripts; v_people uuid[]; v_orgs uuid[]; g record; e app.entities; v_row jsonb; v_records jsonb := '[]'::jsonb;
begin
  perform app.require_connected('ai');
  if p_job ->> 'feature' = 'meeting_recap' then
    select * into t from app.meeting_transcripts where id = (p_job ->> 'transcript_id')::uuid and state = 'ready';
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    select * into m from app.meetings where id = t.meeting_id and deleted_at is null;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    for g in select * from app.mtg_targets(m) loop
      select * into e from app.entities where key = g.entity;
      execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null', e.tbl, g.id) into v_row;
      continue when v_row is null;
      v_records := v_records || jsonb_build_object('entity', g.entity, 'id', g.id, 'version', v_row -> 'version', 'labels', v_row -> 'labels', 'custom', v_row -> 'custom',
        'values', (select coalesce(jsonb_object_agg(c.col, v_row -> c.col), '{}'::jsonb) from app.entity_columns c
                   where c.entity = g.entity and c.writable and c.kind in ('text', 'int', 'numeric', 'boolean', 'date')));
    end loop;
    return jsonb_build_object('feature', 'meeting_recap', 'meeting_id', m.id, 'transcript_id', t.id, 'language', t.language,
      'segments', coalesce((select jsonb_agg(jsonb_build_object('seq', s.seq, 'start_ms', s.start_ms, 'speaker', coalesce(ad.name, p.name, s.speaker_label), 'text', s.text) order by s.seq)
                            from app.transcript_segments s left join app.transcript_speakers sp on sp.transcript_id = s.transcript_id and sp.label = s.speaker_label
                            left join app.admins ad on ad.id = sp.staff_id left join app.people p on p.id = sp.person_id
                            where s.transcript_id = t.id and s.redacted_at is null), '[]'::jsonb),
      'records', v_records,
      'fields', coalesce((select jsonb_agg(jsonb_build_object('entity', f.entity, 'key', 'custom.' || f.key, 'label', f.label, 'type', f.type, 'options', f.options))
                          from app.fields f where f.entity in ('deal', 'lead', 'person', 'organization') and f.archived_at is null and f.type <> 'formula'), '[]'::jsonb),
      'labels', coalesce((select jsonb_agg(jsonb_build_object('entity', l.entity, 'id', l.id, 'name', l.name)) from app.labels l
                          where l.entity in ('deal', 'lead', 'person', 'organization')), '[]'::jsonb));
  elsif p_job ->> 'feature' = 'meeting_brief' then
    select * into m from app.meetings where id = (p_job ->> 'meeting_id')::uuid and deleted_at is null;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    v_people := app.mtg_people(m); v_orgs := app.mtg_orgs(m);
    return jsonb_build_object('feature', 'meeting_brief', 'meeting_id', m.id,
      'instructions', (select s.brief_instructions from app.meeting_user_settings s where s.staff_id = m.owner_id),
      'segments', coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
          select jsonb_build_object('transcript_id', s.transcript_id, 'seq', s.seq, 'speaker', s.speaker_label, 'at', o.starts_at, 'text', s.text) x
          from app.transcript_segments s join app.meeting_transcripts tt on tt.id = s.transcript_id join app.meetings o on o.id = tt.meeting_id
          where o.id <> m.id and o.deleted_at is null and s.redacted_at is null and tt.state = 'ready'
            and (o.deal_id = m.deal_id or o.lead_id = m.lead_id or o.organization_id = any (v_orgs)
                 or exists (select 1 from app.meeting_attendees oa where oa.meeting_id = o.id and oa.person_id = any (v_people)))
          order by o.starts_at desc nulls last, s.seq limit 500) q), '[]'::jsonb),
      'notes', coalesce((select jsonb_agg(jsonb_build_object('note_id', n.id, 'entity', n.entity, 'record_id', n.record_id, 'at', n.created_at, 'body', n.body) order by n.created_at desc)
                         from (select * from app.notes n where n.deleted_at is null
                                 and ((n.entity = 'deal' and n.record_id = m.deal_id) or (n.entity = 'lead' and n.record_id = m.lead_id)
                                      or (n.entity = 'organization' and n.record_id = any (v_orgs)) or (n.entity = 'person' and n.record_id = any (v_people)))
                               order by n.created_at desc limit 100) n), '[]'::jsonb));
  end if;
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'feature';
end $fn$;

-- one call to the AI provider, logged by the gateway (SF-24.5): feature, staff, subject, provider, model, tokens, cost,
-- latency, attempts and outcome — never the prompt or the output. Nothing may be logged as a successful call while the
-- provider is not connected. p_values: those keys. → {id}
create function public.worker_ai_call(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id bigint; v_state text := p_values ->> 'state';
begin
  perform app.prj_keys(p_values, array['feature', 'staff_id', 'subject_type', 'subject_id', 'provider', 'model', 'input_tokens', 'output_tokens',
                                       'cost_micros', 'latency_ms', 'attempts', 'state', 'error_code']);
  if v_state is null or v_state not in ('ok', 'retried_ok', 'invalid', 'error', 'not_connected') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state';
  end if;
  if v_state <> 'not_connected' then perform app.require_connected('ai'); end if;
  if coalesce(p_values ->> 'feature', '') !~ '^[a-z_]{2,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'feature'; end if;
  if p_values ->> 'subject_type' is not null and (p_values ->> 'subject_type') !~ '^[a-z_]{2,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject_type'; end if;
  begin
    insert into app.ai_calls (feature, staff_id, subject_type, subject_id, provider, model, input_tokens, output_tokens, cost_micros, latency_ms, attempts, state, error_code)
    values (p_values ->> 'feature', app.prj_uuid(p_values, 'staff_id'), p_values ->> 'subject_type', app.prj_uuid(p_values, 'subject_id'),
            left(p_values ->> 'provider', 40), left(p_values ->> 'model', 80), app.prj_int(p_values, 'input_tokens', 0, 100000000), app.prj_int(p_values, 'output_tokens', 0, 100000000),
            (p_values ->> 'cost_micros')::bigint, app.prj_int(p_values, 'latency_ms', 0, 3600000), coalesce(app.prj_int(p_values, 'attempts', 1, 5), 1),
            v_state, p_values ->> 'error_code')
    returning id into v_id;
  exception
    when check_violation then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
    when foreign_key_violation then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'staff_id';
  end;
  return jsonb_build_object('id', v_id);
end $fn$;

-- ===========================================================================
-- jobs (pg_cron + pgmq, §8.2)
-- ===========================================================================
-- every 10 minutes: one scan job per connected calendar (the adapter fetches the next 14 days → worker_meeting_upsert)
create function app.mtg_calendar_scan() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  if not app.module_on('meetings') then return 0; end if;
  for r in select c.staff_id from app.calendar_connections c join app.admins a on a.id = c.staff_id
           where c.status = 'connected' and a.active and (app.mtg_user(c.staff_id)).enabled loop
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_calendar_scan', 'staff_id', r.staff_id, 'days', 14));
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- every 5 minutes: the register may have changed (rec_notice), so pending plans are recomputed; notices that are due go
-- to the mailer, or are blocked when no mail can go out (no provider or no controller to name): then the bot stays out
create function app.mtg_notices_due() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n_sent int := 0; n_blocked int := 0; m app.meetings;
begin
  for r in select id from app.meetings where deleted_at is null and cancelled_at is null and starts_at > now() and capture = 'bot' and notice_state in ('pending', 'not_required') loop
    perform app.mtg_refresh(r.id);
  end loop;
  for r in select id from app.meetings where notice_state = 'pending' and notice_due_at <= now() and deleted_at is null and cancelled_at is null and starts_at > now()
             and (notice_queued_at is null or notice_queued_at < now() - interval '1 hour') loop
    if not app.connected('email') or app.mtg_controller() is null then
      update app.meetings set notice_state = 'blocked' where id = r.id;
      m := app.mtg_refresh(r.id);
      if m.owner_id is not null then
        perform app.notify(m.owner_id, 'system', 'meeting.notice_blocked', jsonb_build_object('record', m.title), '/meetings?meeting=' || m.id, 'meeting', m.id);
      end if;
      n_blocked := n_blocked + 1;
    else
      update app.meetings set notice_queued_at = now() where id = r.id;
      perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_notices', 'meeting_id', r.id));
      n_sent := n_sent + 1;
    end if;
  end loop;
  return jsonb_build_object('queued', n_sent, 'blocked', n_blocked);
end $fn$;

-- every minute: meetings starting within five minutes whose bot passes every rule are sent to the provider; the rest are
-- blocked with the reason (MTG-02 RU: joins about two minutes before)
create function app.mtg_bots_due() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings; v_reason text; n_join int := 0; n_block int := 0;
begin
  for m in select * from app.meetings where capture = 'bot' and bot_state = 'scheduled' and deleted_at is null and cancelled_at is null
             and starts_at between now() and now() + interval '5 minutes' for update skip locked loop
    v_reason := app.mtg_bot_block(m, true);
    if v_reason is null then
      update app.meetings set bot_state = 'joining' where id = m.id;
      perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_bot_join', 'meeting_id', m.id, 'join_url', m.join_url, 'conference', m.conference,
                                                   'starts_at', m.starts_at, 'display_name_suffix', '(recording)'));
      n_join := n_join + 1;
    else
      update app.meetings set bot_state = 'blocked', bot_block_reason = v_reason where id = m.id;
      if m.owner_id is not null then
        perform app.notify(m.owner_id, 'system', 'meeting.recording_blocked', jsonb_build_object('record', m.title, 'reason', v_reason), '/meetings?meeting=' || m.id, 'meeting', m.id);
      end if;
      n_block := n_block + 1;
    end if;
  end loop;
  return jsonb_build_object('joining', n_join, 'blocked', n_block);
end $fn$;

-- every 10 minutes: briefs at T−24 h, refreshed at T−1 h, for meetings with a link or an external guest (MTG-01 A)
create function app.mtg_briefs_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  if not app.module_on('meetings') then return 0; end if;
  for r in select m.id from app.meetings m left join app.meeting_briefs b on b.meeting_id = m.id
           where m.deleted_at is null and m.cancelled_at is null and m.starts_at between now() and now() + interval '24 hours'
             and (num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0 or app.mtg_has_external(m.id))
             and (b.meeting_id is null or b.generated_at < m.starts_at - interval '24 hours'
                  or (m.starts_at <= now() + interval '1 hour' and b.generated_at < m.starts_at - interval '1 hour')) loop
    perform app.mtg_brief_build(r.id);
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- nightly: audio past rec_retention, uploads never confirmed, and meetings deleted 30 days ago (with their history).
-- Storage objects go to the worker. → counts
create function app.mtg_purge() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_paths text[] := '{}'; n_rec int; n_up int; n_meet int;
begin
  perform set_config('app.purging', 'on', true);
  v_paths := v_paths || array(select storage_path from app.meeting_recordings where purge_after < now() and state <> 'deleted' and storage_path is not null);
  update app.meeting_recordings set state = 'deleted', deleted_at = now(), storage_path = null where purge_after < now() and state <> 'deleted';
  get diagnostics n_rec = row_count;
  v_paths := v_paths || array(select storage_path from app.meeting_uploads where state = 'pending' and created_at < now() - interval '1 day');
  delete from app.meeting_uploads where state = 'pending' and created_at < now() - interval '1 day';
  get diagnostics n_up = row_count;
  v_paths := v_paths || array(select r.storage_path from app.meeting_recordings r join app.meetings m on m.id = r.meeting_id
                              where m.deleted_at < now() - interval '30 days' and r.storage_path is not null);
  with d as (delete from app.meetings where deleted_at < now() - interval '30 days' returning id),
       c as (delete from app.changelog l using d where l.entity = 'meeting' and l.record_id = d.id)
  select count(*) into n_meet from d;
  perform app.mtg_storage_forget(v_paths);
  perform set_config('app.purging', 'off', true);
  insert into app.audit (actor, action, ok, detail) values ('system', 'job.meetings_purged', true, jsonb_build_object('recordings', n_rec, 'uploads', n_up, 'meetings', n_meet));
  return jsonb_build_object('recordings', n_rec, 'uploads', n_up, 'meetings', n_meet);
end $fn$;

select cron.schedule('platform-meeting-calendar-scan', '*/10 * * * *', 'select app.mtg_calendar_scan()');
select cron.schedule('platform-meeting-notices', '*/5 * * * *', 'select app.mtg_notices_due()');
select cron.schedule('platform-meeting-bots', '* * * * *', 'select app.mtg_bots_due()');
select cron.schedule('platform-meeting-briefs', '*/10 * * * *', 'select app.mtg_briefs_due()');
select cron.schedule('platform-meeting-purge', '23 3 * * *', 'select app.mtg_purge()');

-- ===========================================================================
-- erasure (SEC-11, SF-15, §8.3): what a person said is redacted, the audio of every meeting they attended is deleted
-- (audio cannot be partly redacted), their attendance, speaker mapping, brief entries and the suggestions about them go.
-- The «never record me» hash stays. A trigger of its own beside app.person_erased (0031/0037), which stays as it is.
-- ===========================================================================
create function app.person_erased_meetings() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_email text := lower(btrim(old.email)); v_meetings uuid[]; v_paths text[]; n_seg int;
begin
  v_meetings := array(select distinct a.meeting_id from app.meeting_attendees a where a.person_id = old.id or (v_email is not null and a.email = v_email));
  update app.transcript_segments s set text = '[removed]', redacted_at = now()
  from app.transcript_speakers sp
  where sp.transcript_id = s.transcript_id and sp.label = s.speaker_label and s.redacted_at is null
    and (sp.person_id = old.id or (v_email is not null and sp.email = v_email));
  get diagnostics n_seg = row_count;
  delete from app.transcript_speakers where person_id = old.id or (v_email is not null and email = v_email);
  delete from app.meeting_attendees where person_id = old.id or (v_email is not null and email = v_email);
  select array_agg(storage_path) into v_paths from app.meeting_recordings where meeting_id = any (v_meetings) and state <> 'deleted';
  update app.meeting_recordings set state = 'deleted', deleted_at = now(), storage_path = null where meeting_id = any (v_meetings) and state <> 'deleted';
  update app.meeting_briefs b set
    quotes = coalesce((select jsonb_agg(q) from jsonb_array_elements(b.quotes) q where (q ->> 'person_id') is distinct from old.id::text), '[]'::jsonb),
    people = coalesce((select jsonb_agg(p) from jsonb_array_elements(b.people) p where (p ->> 'person_id') is distinct from old.id::text), '[]'::jsonb)
  where b.quotes @> jsonb_build_array(jsonb_build_object('person_id', old.id)) or b.people @> jsonb_build_array(jsonb_build_object('person_id', old.id));
  delete from app.meeting_suggestions where target_entity = 'person' and target_id = old.id;
  perform app.mtg_storage_forget(v_paths);
  if cardinality(v_meetings) > 0 or n_seg > 0 then
    insert into app.audit (actor, action, target_type, target_id, detail, ok)
    values ('system', 'meeting.erasure', 'person', old.id::text, jsonb_build_object('meetings', cardinality(v_meetings), 'segments', n_seg), true);
  end if;
  return old;
end $fn$;
create trigger person_erased_meetings before delete on app.people for each row execute function app.person_erased_meetings();

-- ===========================================================================
-- the other AI calls (spec §8, SF-24): project summaries name their call; the inbox insight needs the provider
-- ===========================================================================
-- 0038's body, plus p_result.ai_call_id (optional; when given, a successful «project_summary» call in the log)
create or replace function public.worker_project_summary_ready(p_id uuid, p_result jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.project_ai_summaries; v_ok boolean := coalesce(p_result ->> 'state', '') = 'ready'; p app.projects; v_call bigint;
begin
  select * into s from app.project_ai_summaries where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if s.state <> 'requested' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  begin
    v_call := (p_result ->> 'ai_call_id')::bigint;
  exception when others then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ai_call_id';
  end;
  if v_call is not null and not exists (select 1 from app.ai_calls c where c.id = v_call and c.feature = 'project_summary'
                                        and (c.state in ('ok', 'retried_ok') or not v_ok)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ai_call_id';
  end if;
  if v_ok then
    if coalesce(p_result ->> 'suggested_health', 'on_track') not in ('on_track', 'at_risk', 'off_track', 'on_hold') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'suggested_health';
    end if;
    if char_length(p_result ->> 'summary') > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'summary'; end if;
    if jsonb_typeof(coalesce(p_result -> 'recommendations', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_result -> 'recommendations', '[]'::jsonb)) > 5
       or exists (select 1 from jsonb_array_elements(coalesce(p_result -> 'recommendations', '[]'::jsonb)) x where jsonb_typeof(x) <> 'string' or char_length(x #>> '{}') > 300) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recommendations';
    end if;
    if jsonb_typeof(coalesce(p_result -> 'sources', '[]'::jsonb)) <> 'array'
       or exists (select 1 from jsonb_array_elements(coalesce(p_result -> 'sources', '[]'::jsonb)) x where jsonb_typeof(x) <> 'object' or not (x ? 'entity' and x ? 'id')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sources';
    end if;
  end if;
  update app.project_ai_summaries set state = case when v_ok then 'ready' else 'failed' end, generated_at = now(), ai_call_id = v_call,
    suggested_health = case when v_ok then p_result ->> 'suggested_health' end, summary = case when v_ok then p_result ->> 'summary' end,
    recommendations = case when v_ok then coalesce(p_result -> 'recommendations', '[]'::jsonb) else '[]'::jsonb end,
    sources = case when v_ok then coalesce(p_result -> 'sources', '[]'::jsonb) else '[]'::jsonb end
  where id = s.id;
  select * into p from app.projects where id = s.project_id;
  if s.requested_by is not null then
    perform app.notify(s.requested_by, 'system', case when v_ok then 'project.ai_summary_ready' else 'project.ai_summary_failed' end,
                       jsonb_build_object('record', p.name), '/projects?project=' || p.id, 'project', p.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'project.ai_summary', 'project', p.id::text, jsonb_build_object('state', case when v_ok then 'ready' else 'failed' end, 'ai_call', v_call), true);
  return jsonb_build_object('ok', true);
end $fn$;

-- 0020's body; the AI provider must be connected (spec Q16: integration_connections is the single source)
create or replace function public.thread_insight_request(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'ai');
begin
  if not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.require_connected('ai');
  insert into app.email_thread_insights (thread_id, state, requested_by, requested_at) values (p_id, 'requested', v_me, now())
  on conflict (thread_id) do update set state = 'requested', requested_by = v_me, requested_at = now();
  perform pgmq.send('jobs', jsonb_build_object('job', 'ai_thread_insight', 'thread_id', p_id));
  perform app.log('ai.thread_insight', 'email_thread', p_id::text, null);
  return jsonb_build_object('id', p_id, 'state', 'requested');
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['ai_calls', 'meetings', 'meeting_attendees', 'recording_opt_outs', 'meeting_recordings', 'meeting_transcripts', 'transcript_speakers',
                           'transcript_segments', 'meeting_briefs', 'meeting_brief_checks', 'meeting_recaps', 'meeting_suggestions', 'meeting_user_settings',
                           'meeting_uploads'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.ai_call_fixed()', 'app.recording_opt_out_fixed()', 'app.transcript_segment_fixed()', 'app.meeting_link_purged()',
                           'app.mtg_require()', 'app.mtg_visible(app.meetings)', 'app.mtg_get(uuid, boolean)', 'app.mtg_can_edit(app.meetings)',
                           'app.mtg_require_edit(app.meetings)', 'app.mtg_notice_hours()', 'app.mtg_retention_months()', 'app.mtg_retention()',
                           'app.mtg_visibility_default()', 'app.mtg_controller()', 'app.mtg_user(uuid)', 'app.mtg_has_external(uuid)', 'app.mtg_opted_out(uuid)',
                           'app.mtg_bot_block(app.meetings, boolean)', 'app.mtg_refresh(uuid)', 'app.mtg_refresh_owner(uuid)', 'app.mtg_target_ok(text, uuid)',
                           'app.mtg_links(app.meetings)', 'app.mtg_transcript(uuid)', 'app.mtg_state(app.meetings)', 'app.mtg_group(app.meetings)',
                           'app.mtg_row(app.meetings)', 'app.mtg_capabilities()', 'app.mtg_source_visible(jsonb)', 'app.mtg_storage_forget(text[])',
                           'app.mtg_people(app.meetings)', 'app.mtg_orgs(app.meetings)', 'app.mtg_targets(app.meetings)', 'app.mtg_user_row(uuid)',
                           'app.mtg_suggestion_current(app.meeting_suggestions)', 'app.mtg_brief_build(uuid)', 'app.mtg_segments_store(uuid, jsonb)',
                           'app.mtg_speakers_map(uuid, jsonb)', 'app.mtg_recap_queue(uuid)', 'app.mtg_transcript_done(uuid, boolean, text)',
                           'app.mtg_suggestion_write(app.meeting_suggestions)', 'app.mtg_user_write(uuid, jsonb, text[], uuid)', 'app.mtg_after_opt_out(uuid)',
                           'app.ai_call_ok(bigint, text)', 'app.mtg_calendar_scan()', 'app.mtg_notices_due()', 'app.mtg_bots_due()', 'app.mtg_briefs_due()',
                           'app.mtg_purge()', 'app.person_erased_meetings()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.meetings_workspace(jsonb)', 'public.meeting_detail(uuid)', 'public.meeting_brief(uuid)', 'public.meeting_transcript(uuid, int, int)',
                           'public.meeting_recap(uuid)', 'public.meeting_suggestions(uuid)', 'public.meeting_controls()', 'public.meeting_my_settings()',
                           'public.meeting_link(uuid, jsonb, int)', 'public.meeting_capture_set(uuid, text)', 'public.meeting_bot_remove(uuid)',
                           'public.meeting_recording_delete(uuid, boolean)', 'public.meeting_brief_check(uuid, text, boolean)', 'public.meeting_brief_regenerate(uuid)',
                           'public.meeting_transcript_upload_begin(uuid, text, text, bigint)', 'public.meeting_transcript_upload_done(uuid)',
                           'public.meeting_transcript_retry(uuid)', 'public.meeting_speaker_map(uuid, text, jsonb)', 'public.meeting_recap_regenerate(uuid)',
                           'public.meeting_recap_save_note(uuid, text, uuid)', 'public.meeting_next_step_activity(uuid, int, jsonb)',
                           'public.meeting_suggestion_decide(uuid[], text)', 'public.meeting_user_set(uuid, jsonb)', 'public.meeting_my_settings_set(jsonb)',
                           'public.meeting_opt_out_staff(uuid, text, boolean)', 'public.thread_insight_request(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.meeting_opt_out(text, boolean)', 'public.worker_meeting_upsert(uuid, jsonb)', 'public.worker_notice_claim(uuid)',
                           'public.worker_notice_result(uuid, text, boolean)', 'public.worker_bot_state(uuid, text, text)', 'public.worker_recording_ready(uuid, jsonb)',
                           'public.worker_transcript_ready(uuid, jsonb, jsonb, text)', 'public.worker_upload_parsed(uuid, jsonb)',
                           'public.worker_brief_quotes_ready(uuid, jsonb)', 'public.worker_recap_ready(uuid, jsonb, jsonb)', 'public.worker_meeting_ai_context(jsonb)',
                           'public.worker_ai_call(jsonb)', 'public.worker_project_summary_ready(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
