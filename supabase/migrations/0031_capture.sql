-- 0031_capture.sql — lead capture (Phase 5): consent wording and suppressions, web forms, chatbot and live chat,
-- prospect reveals and web visitors. Spec: docs/crm-enrichment/specs/marketing-documents.md §1 (Web forms, Chatbot
-- and live chat, Prospect search, Web visitors), §4, §5, §6, §7, §10 and §11 answers 2, 3, 7, 8, 10, 15, 16, 20, 21, 23.
-- The registers this extends (providers, the changelog source «capture», settings, routes, web site keys) are
-- 0030's. Campaigns, segments, sender domains and documents are not here.
--
-- Consent. A person's marketing status is set only by consent_set and the workers, each writing the append-only
-- ledger with the status before, the address it concerns (SHA-256 of the lower-cased address), the reference and
-- the wording version shown (consent_texts, art. 7(1) proof). 'archived' is added; 'pending' keeps meaning «pending
-- double opt-in» (Q2). Double opt-in is on by default (0030, Q3): a form submission with the box ticked stays
-- pending until the single-use, expiring link is confirmed. Suppressions are keyed by the address hash, so they
-- survive erasure. suppressions.campaign_id is a plain uuid: campaigns arrive in phase 6.
--
-- Forms. A form's draft is edited; publishing freezes it as a version, and every submission is stored against the
-- version it answered. The public edge function on go.owntheagenda.com (D-28) calls the worker_* functions with
-- the service role. Spam (honeypot, minimum fill time, the edge's rate limit) and duplicates are stored as states
-- without their content. Tracking (UTM, referrer host, landing path, declared page variables; no cookie id, Q7)
-- is stored only while form_tracking is on. A file-upload form carries a fixed notice that employee lists belong
-- in the product (Q8, D-34); no such form is seeded.
--
-- Chat. Polling, not Realtime (Q10): staff read chats_queue/chat_get, the visitor's edge function polls
-- worker_chat_poll with its conversation token, of which only the SHA-256 is stored. The first claim wins and
-- locks the chat to one rep (LGN-02); a check constraint ties the live state to an open claim.
--
-- Prospects. The prospect database (contact_data) is not connected: search and reveal raise not_connected.
-- contact_rule = opt_in_only refuses a reveal; source_and_basis requires a basis. A reveal costs one credit when
-- the worker reports the contact; a repeat reveal of the same reference costs nothing.
--
-- Web visitors. Company level only (Q15: Norwegian org numbers only). An ENK org number identifies a natural
-- person: web_companies.excluded, and such sessions keep no org number (Q16). «Nth visit» counts the company's
-- sessions (Q23). worker_web_ingest drops survey hosts (survey_flow_block) and emits visitor.identified once per
-- CRM organization per day.
--
-- Privacy (§10). No IP anywhere; tokens only as SHA-256; no answer, chat text or consent wording in app.log
-- detail or event payloads — ids and counts only. The column names avoid «answers» (structure suite, D-34):
-- form_submissions.field_values and chat_conversations.collected hold a capture's values.

-- ---------------------------------------------------------------------------
-- consent: the wording shown, the ledger widened, suppressions
create table app.consent_texts (
  id         uuid primary key default gen_random_uuid(),
  key        text not null check (key ~ '^[a-z_]{2,40}$'),
  locale     text not null check (locale in ('nb', 'nn', 'en', 'sv')),
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  version    int not null check (version >= 1),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (key, locale, version)
);
-- the design's checkbox wording, without the canvas annotation; Tor edits it (a new version each time)
insert into app.consent_texts (key, locale, body, version) values
  ('newsletter', 'nb', 'Ja, send meg nyhetsbrev', 1),
  ('newsletter', 'nn', 'Ja, send meg nyheitsbrev', 1),
  ('newsletter', 'en', 'Yes, send me the newsletter', 1),
  ('newsletter', 'sv', 'Ja, skicka mig nyhetsbrevet', 1);

alter table app.people drop constraint people_marketing_status_check;
alter table app.people add constraint people_marketing_status_check
  check (marketing_status in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived'));
alter table app.consent_events drop constraint consent_events_status_check;
alter table app.consent_events add constraint consent_events_status_check
  check (status in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived'));
alter table app.consent_events
  add column prev_status  text check (prev_status is null or prev_status in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived')),
  add column email_sha256 bytea check (email_sha256 is null or length(email_sha256) = 32),
  add column ref_type     text check (ref_type is null or ref_type in ('form_submission', 'campaign', 'chat', 'import', 'prospect', 'staff', 'provider',
                                                                       'confirmation', 'list_hygiene', 'email_changed')),
  add column ref_id       uuid,
  add column detail       text check (detail is null or (char_length(detail) <= 120 and detail ~ '^[a-z0-9_.:-]+$')),   -- a code, never free text
  add column text_id      uuid references app.consent_texts (id);
create index consent_events_email on app.consent_events (email_sha256, id desc) where email_sha256 is not null;
create index consent_events_recent on app.consent_events (id desc);

create table app.suppressions (
  email_sha256 bytea not null check (length(email_sha256) = 32),
  scope        text not null check (scope in ('marketing', 'all')),
  reason       text not null check (reason in ('unsubscribed', 'complaint', 'hard_bounce', 'soft_bounces', 'manual', 'erasure')),
  campaign_id  uuid,                                   -- phase 6 adds campaigns; no foreign key until then
  created_by   uuid,
  created_at   timestamptz not null default now(),
  primary key (email_sha256, scope)
);

-- ---------------------------------------------------------------------------
-- web companies: a Brønnøysund cache of the companies the IP-to-company provider names
create table app.web_companies (
  org_number text primary key check (org_number ~ '^\d{9}$'),
  name       text not null check (char_length(btrim(name)) between 1 and 200),
  org_form   text check (org_form is null or char_length(org_form) <= 10),
  nace       text check (nace is null or char_length(nace) <= 10),
  industry   text check (industry is null or char_length(industry) <= 200),
  city       text check (city is null or char_length(city) <= 80),
  fylke      text check (fylke is null or char_length(fylke) <= 60),
  country    char(2) not null default 'NO' check (country ~ '^[A-Z]{2}$'),
  employees  int check (employees is null or employees >= 0),
  website    text check (website is null or char_length(website) <= 200),
  excluded   boolean not null default false,          -- ENK: a natural person (Q16)
  source     text not null default 'brreg' check (source in ('brreg')),
  fetched_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- forms (LGN-03, SF-17)
create table app.forms (
  id              uuid primary key default gen_random_uuid(),
  public_id       text not null unique default app.token() check (public_id ~ '^[A-Za-z0-9_-]{16,64}$'),
  name            text not null check (char_length(btrim(name)) between 1 and 120),
  kind            text not null check (kind in ('contact', 'registration', 'gated_download', 'file_upload', 'blank')),
  language        text not null check (language in ('nb', 'nn', 'en', 'sv')),
  status          text not null default 'inactive' check (status in ('active', 'inactive')),
  draft           jsonb not null check (jsonb_typeof(draft) = 'object'),
  current_version int not null default 0 check (current_version >= 0),
  site_id         uuid references app.web_sites (id) on delete set null,
  owner_id        uuid references app.admins (id) on delete set null,
  visibility      text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels          uuid[] not null default '{}',
  custom          jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample       boolean not null default false,
  version         int not null default 1,
  created_at      timestamptz not null default now(),
  created_by      uuid,
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  deleted_at      timestamptz,
  check (status = 'inactive' or current_version > 0)
);

-- a form's language is fixed at creation: its consent wording and its versions are in that language
create function app.form_language_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.language is distinct from old.language or new.kind is distinct from old.kind then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = case when new.language is distinct from old.language then 'language' else 'kind' end;
  end if;
  return new;
end $fn$;
create trigger form_language_fixed before update on app.forms for each row execute function app.form_language_fixed();

create table app.form_versions (
  form_id      uuid not null references app.forms (id) on delete cascade,
  version      int not null check (version >= 1),
  definition   jsonb not null check (jsonb_typeof(definition) = 'object'),
  published_by uuid,
  published_at timestamptz not null default now(),
  primary key (form_id, version)
);

create table app.form_submissions (
  id              uuid primary key default gen_random_uuid(),
  form_id         uuid not null references app.forms (id) on delete cascade,
  form_version    int not null,
  state           text not null check (state in ('accepted', 'spam', 'duplicate')),
  field_values    jsonb not null default '{}'::jsonb check (jsonb_typeof(field_values) = 'object'),   -- {} for spam and duplicates
  fingerprint     bytea check (fingerprint is null or length(fingerprint) = 32),                     -- SHA-256 of the values, for duplicates
  tracking        jsonb not null default '{}'::jsonb check (jsonb_typeof(tracking) = 'object'),     -- {} while form_tracking is off
  consent         jsonb not null default '{}'::jsonb check (jsonb_typeof(consent) = 'object'),      -- {given, text_id, status, double_opt_in}
  person_id       uuid references app.people (id) on delete set null,
  organization_id uuid references app.organizations (id) on delete set null,
  lead_id         uuid references app.leads (id) on delete set null,
  deal_id         uuid references app.deals (id) on delete set null,
  ticket_id       uuid references app.tickets (id) on delete set null,
  files           jsonb not null default '[]'::jsonb check (jsonb_typeof(files) = 'array'),
  is_sample       boolean not null default false,
  created_at      timestamptz not null default now(),
  foreign key (form_id, form_version) references app.form_versions (form_id, version) on delete cascade,
  check (state = 'accepted' or field_values = '{}'::jsonb)
);
create index form_submissions_form on app.form_submissions (form_id, created_at desc);
create index form_submissions_person on app.form_submissions (person_id) where person_id is not null;
create index form_submissions_lead on app.form_submissions (lead_id) where lead_id is not null;

create table app.form_stats_daily (
  form_id     uuid not null references app.forms (id) on delete cascade,
  day         date not null,
  views       int not null default 0 check (views >= 0),
  starts      int not null default 0 check (starts >= 0),
  submissions int not null default 0 check (submissions >= 0),
  primary key (form_id, day)
);

-- double opt-in links: single use, valid 7 days, only the token's SHA-256 is stored
create table app.consent_confirmations (
  token_sha256  bytea primary key check (length(token_sha256) = 32),
  person_id     uuid not null references app.people (id) on delete cascade,
  email_sha256  bytea not null check (length(email_sha256) = 32),
  submission_id uuid references app.form_submissions (id) on delete set null,
  text_id       uuid references app.consent_texts (id),
  expires_at    timestamptz not null,
  confirmed_at  timestamptz,
  created_at    timestamptz not null default now()
);
create index consent_confirmations_person on app.consent_confirmations (person_id);

-- ---------------------------------------------------------------------------
-- chat (LGN-01, LGN-02, LGN-05, SF-30)
create table app.chat_playbooks (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (char_length(btrim(name)) between 1 and 120),
  template           text not null check (template in ('leads', 'meetings', 'qualify_route', 'live_chat')),
  state              text not null default 'draft' check (state in ('draft', 'live')),
  site_ids           uuid[] not null default '{}',
  pages              text[] not null default '{}' check (cardinality(pages) <= 50),       -- path patterns, '*' suffix allowed
  theme              jsonb not null default '{}'::jsonb check (jsonb_typeof(theme) = 'object'),
  profile            jsonb not null default '{}'::jsonb check (jsonb_typeof(profile) = 'object'),
  steps              jsonb not null default '[]'::jsonb check (jsonb_typeof(steps) = 'array'),
  creates            text not null default 'lead' check (creates in ('lead', 'deal')),
  pipeline_id        uuid references app.pipelines (id),
  stage_id           uuid references app.stages (id),
  booking_link_id    uuid references app.booking_links (id) on delete set null,
  queue_wait_seconds int not null default 60 check (queue_wait_seconds between 10 and 900),
  offline_message    text check (offline_message is null or char_length(offline_message) between 1 and 500),
  current_version    int not null default 0 check (current_version >= 0),
  owner_id           uuid references app.admins (id) on delete set null,
  visibility         text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels             uuid[] not null default '{}',
  custom             jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample          boolean not null default false,
  version            int not null default 1,
  created_at         timestamptz not null default now(),
  created_by         uuid,
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  deleted_at         timestamptz,
  check (state = 'draft' or current_version > 0),
  check (creates = 'lead' or pipeline_id is not null)
);

create table app.chat_playbook_versions (
  playbook_id  uuid not null references app.chat_playbooks (id) on delete cascade,
  version      int not null check (version >= 1),
  definition   jsonb not null check (jsonb_typeof(definition) = 'object'),
  published_by uuid,
  published_at timestamptz not null default now(),
  primary key (playbook_id, version)
);

create table app.chat_conversations (
  id                   uuid primary key default gen_random_uuid(),
  playbook_id          uuid references app.chat_playbooks (id) on delete set null,
  playbook_version     int,
  site_id              uuid references app.web_sites (id) on delete set null,
  page_path            text check (page_path is null or char_length(page_path) <= 500),
  company_org_number   text check (company_org_number is null or company_org_number ~ '^\d{9}$'),
  visitor_token_sha256 bytea not null unique check (length(visitor_token_sha256) = 32),
  language             text check (language is null or language in ('nb', 'nn', 'en', 'sv')),
  state                text not null default 'bot' check (state in ('bot', 'queued', 'live', 'closed')),
  queued_at            timestamptz,
  claimed_by           uuid references app.admins (id) on delete set null,
  claimed_at           timestamptz,
  closed_at            timestamptz,
  last_step_key        text check (last_step_key is null or last_step_key ~ '^[a-z][a-z0-9_]{0,40}$'),
  completed            boolean not null default false,
  collected            jsonb not null default '{}'::jsonb check (jsonb_typeof(collected) = 'object'),
  person_id            uuid references app.people (id) on delete set null,
  lead_id              uuid references app.leads (id) on delete set null,
  deal_id              uuid references app.deals (id) on delete set null,
  is_sample            boolean not null default false,
  started_at           timestamptz not null default now(),
  check ((state = 'live') = (claimed_by is not null and closed_at is null)),
  check ((state = 'closed') = (closed_at is not null)),
  check (state <> 'queued' or queued_at is not null)
);
create index chat_conversations_open on app.chat_conversations (state, started_at desc) where state <> 'closed';
create index chat_conversations_lead on app.chat_conversations (lead_id) where lead_id is not null;

create table app.chat_messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references app.chat_conversations (id) on delete cascade,
  sender          text not null check (sender in ('bot', 'visitor', 'staff', 'system')),
  staff_id        uuid references app.admins (id) on delete set null,
  body            text not null check (char_length(body) between 1 and 4000),
  at              timestamptz not null default now(),
  check (sender = 'staff' or staff_id is null)
);
create index chat_messages_conversation on app.chat_messages (conversation_id, id);

create table app.chat_presence (
  staff_id     uuid primary key references app.admins (id) on delete cascade,
  online_until timestamptz not null
);

-- ---------------------------------------------------------------------------
-- prospect reveals (LGN-04): a result is never stored until revealed
create table app.prospect_reveals (
  id              uuid primary key default gen_random_uuid(),
  provider        text not null default 'contact_data' check (provider in ('contact_data')),
  provider_ref    text not null check (char_length(btrim(provider_ref)) between 1 and 200),
  state           text not null default 'requested' check (state in ('requested', 'revealed', 'failed')),
  basis           text check (basis is null or char_length(basis) <= 200),
  person_id       uuid references app.people (id) on delete set null,
  organization_id uuid references app.organizations (id) on delete set null,
  lead_id         uuid references app.leads (id) on delete set null,
  credits         int not null default 1 check (credits >= 0),
  error           text check (error is null or error ~ '^[a-z0-9_.:-]{1,60}$'),
  revealed_by     uuid references app.admins (id) on delete set null,
  revealed_at     timestamptz not null default now(),
  unique (provider, provider_ref)
);
alter table app.credit_ledger add column reveal_id uuid references app.prospect_reveals (id) on delete set null;

-- ---------------------------------------------------------------------------
-- the record type «form» (forms are written through form_*; the generic path may only list, read and delete them)
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('form', 'forms', 'campaigns', 'leadgen', true, 'name', array['kind', 'status'], array['name'], 60);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('form', 'name', 'text', false, false, null, 1),
  ('form', 'kind', 'text', false, false, null, 2),
  ('form', 'language', 'text', false, false, null, 3),
  ('form', 'status', 'text', false, false, null, 4),
  ('form', 'current_version', 'int', false, false, null, 5),
  ('form', 'public_id', 'text', false, false, null, 6);

-- ---------------------------------------------------------------------------
-- append-only content: nobody may change it; a delete is allowed only when the parent is already gone
create function app.consent_text_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' and (new.key, new.locale, new.body, new.version, new.created_at) is not distinct from (old.key, old.locale, old.body, old.version, old.created_at) then
    return new;
  end if;
  raise exception 'consent wording is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger consent_text_fixed before update or delete on app.consent_texts for each row execute function app.consent_text_fixed();

create function app.form_version_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.forms where id = old.form_id) then return old; end if;
  if tg_op = 'UPDATE' and (new.form_id, new.version, new.definition, new.published_by, new.published_at)
                          is not distinct from (old.form_id, old.version, old.definition, old.published_by, old.published_at) then return new; end if;
  raise exception 'a published form version is fixed' using errcode = 'insufficient_privilege';
end $fn$;
create trigger form_version_fixed before update or delete on app.form_versions for each row execute function app.form_version_fixed();

create function app.playbook_version_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.chat_playbooks where id = old.playbook_id) then return old; end if;
  if tg_op = 'UPDATE' and (new.playbook_id, new.version, new.definition, new.published_by, new.published_at)
                          is not distinct from (old.playbook_id, old.version, old.definition, old.published_by, old.published_at) then return new; end if;
  raise exception 'a published playbook version is fixed' using errcode = 'insufficient_privilege';
end $fn$;
create trigger playbook_version_fixed before update or delete on app.chat_playbook_versions for each row execute function app.playbook_version_fixed();

create function app.chat_message_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.chat_conversations where id = old.conversation_id) then return old; end if;
  -- the staff member may be removed (on delete set null); the words, the sender and the time may not change
  if tg_op = 'UPDATE' and (new.conversation_id, new.sender, new.body, new.at) is not distinct from (old.conversation_id, old.sender, old.body, old.at) then return new; end if;
  raise exception 'a chat transcript is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger chat_message_fixed before update or delete on app.chat_messages for each row execute function app.chat_message_fixed();

-- a form can enroll its lead in a sequence (SF-05)
alter table app.sequence_enrollments drop constraint sequence_enrollments_enrolled_via_check;
alter table app.sequence_enrollments add constraint sequence_enrollments_enrolled_via_check check (enrolled_via in ('one', 'bulk', 'workflow', 'form'));

-- ---------------------------------------------------------------------------
-- helpers
create function app.email_hash(p_email text) returns bytea
  language sql immutable set search_path = ''
as $fn$ select case when nullif(btrim(p_email), '') is not null then extensions.digest(lower(btrim(p_email)), 'sha256') end $fn$;

create function app.token_hash(p_token text) returns bytea
  language sql immutable set search_path = ''
as $fn$ select extensions.digest(coalesce(p_token, ''), 'sha256') $fn$;

create function app.connected(p_provider text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select exists (select 1 from app.integration_connections where provider = p_provider and status = 'connected') $fn$;

create function app.require_connected(p_provider text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not app.connected(p_provider) then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = p_provider;
  end if;
end $fn$;

-- every consent change: the ledger row (status before, the address's hash, reference, wording), the status, the history
create function app.consent_write(p_person uuid, p_status text, p_source text, p_basis text, p_ref_type text, p_ref_id uuid,
                                  p_text_id uuid default null, p_detail text default null, p_history_source text default 'capture')
  returns void language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.people; v_me uuid := app.me();
begin
  select * into p from app.people where id = p_person for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.consent_events (person_id, status, prev_status, email_sha256, source, basis, actor_id, ref_type, ref_id, detail, text_id)
  values (p_person, p_status, p.marketing_status, app.email_hash(p.email), left(btrim(p_source), 60), nullif(left(btrim(p_basis), 200), ''), v_me,
          p_ref_type, p_ref_id, p_detail, p_text_id);
  update app.people set marketing_status = p_status, version = version + 1, updated_at = now(), updated_by = coalesce(v_me, updated_by) where id = p_person;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('person', p_person, 'marketing_status', to_jsonb(p.marketing_status), to_jsonb(p_status), v_me, p_history_source);
  perform app.log('consent.changed', 'person', p_person::text, jsonb_build_object('from', p.marketing_status, 'to', p_status, 'ref_type', p_ref_type));
  perform app.emit('consent.changed', 'person', p_person, jsonb_build_object('status', p_status, 'ref_type', p_ref_type), p.is_sample);
end $fn$;

-- records made by a capture: changelog source «capture», so assignment rules apply to them (V-20)
create function app.capture_org(p_org_number text, p_name text, p_source text, p_owner uuid, p_sample boolean default false) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_id uuid; v_req uuid; w app.web_companies;
  v_nr text := nullif(regexp_replace(coalesce(p_org_number, ''), '\D', '', 'g'), '');
  v_name text := nullif(btrim(p_name), '');
begin
  if v_nr is not null and v_nr !~ '^\d{9}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'org_number'; end if;
  if v_nr is null and v_name is null then return null; end if;
  if v_nr is not null then
    select id into v_id from app.organizations where org_number = v_nr and deleted_at is null and is_sample = p_sample order by created_at limit 1;
    select * into w from app.web_companies where org_number = v_nr and not excluded;
  else
    select id into v_id from app.organizations where lower(name) = lower(v_name) and deleted_at is null and is_sample = p_sample order by created_at limit 1;
  end if;
  if v_id is not null then return v_id; end if;
  insert into app.organizations (name, org_number, city, fylke, industry, nace, employees, website, source, owner_id, visibility, created_by, updated_by, is_sample)
  values (left(coalesce(v_name, w.name, v_nr), 200), v_nr, left(w.city, 80), left(w.fylke, 60), left(w.industry, 80),
          case when w.nace ~ '^\d{2}\.\d{1,3}$' then w.nace end, w.employees, w.website, left(p_source, 60), p_owner,
          app.setting('visibility_default', 'organization'), app.me(), app.me(), p_sample)
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('organization', v_id, '*created', app.me(), 'capture');
  perform app.log('record.created', 'organization', v_id::text, jsonb_build_object('source', 'capture'));
  perform app.emit('organization.created', 'organization', v_id, '{}'::jsonb, p_sample);
  -- the register's data: Brønnøysund needs no key, the enrichment worker fetches it (0022)
  if v_nr is not null then
    insert into app.enrichment_requests (entity, record_id, kind, provider) values ('organization', v_id, 'company', 'brreg') returning id into v_req;
    perform pgmq.send('jobs', jsonb_build_object('job', 'enrich', 'request_id', v_req));
  end if;
  return v_id;
end $fn$;

create function app.capture_person(p_email text, p_name text, p_phone text, p_org uuid, p_source text, p_owner uuid, p_sample boolean default false)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_id uuid;
  v_email text := lower(nullif(btrim(p_email), ''));
  v_phone text := left(nullif(btrim(p_phone), ''), 40);
begin
  if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'email';
  end if;
  if v_email is null and nullif(btrim(p_name), '') is null then return null; end if;
  if v_email is not null then
    select id into v_id from app.people where lower(email) = v_email and deleted_at is null and is_sample = p_sample order by created_at limit 1;
    if v_id is not null then
      -- an existing person keeps their values; only empty links and numbers are filled
      update app.people set organization_id = coalesce(organization_id, p_org), phone = coalesce(phone, v_phone), version = version + 1, updated_at = now()
      where id = v_id and ((organization_id is null and p_org is not null) or (phone is null and v_phone is not null));
      return v_id;
    end if;
  end if;
  insert into app.people (name, email, phone, organization_id, contact_type, source, owner_id, visibility, created_by, updated_by, is_sample)
  values (left(coalesce(nullif(btrim(p_name), ''), split_part(v_email, '@', 1)), 200), v_email, v_phone, p_org, 'prospect', left(p_source, 60), p_owner,
          app.setting('visibility_default', 'person'), app.me(), app.me(), p_sample)
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('person', v_id, '*created', app.me(), 'capture');
  perform app.log('record.created', 'person', v_id::text, jsonb_build_object('source', 'capture'));
  perform app.emit('person.created', 'person', v_id, '{}'::jsonb, p_sample);
  return v_id;
end $fn$;

create function app.capture_lead(p_title text, p_person uuid, p_org uuid, p_source text, p_owner uuid, p_form_data jsonb, p_sample boolean default false)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  insert into app.leads (title, person_id, organization_id, source, form_data, owner_id, visibility, created_by, updated_by, is_sample)
  values (left(btrim(p_title), 200), p_person, p_org, left(p_source, 60), p_form_data, p_owner, app.setting('visibility_default', 'lead'), app.me(), app.me(), p_sample)
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('lead', v_id, '*created', app.me(), 'capture');
  perform app.log('record.created', 'lead', v_id::text, jsonb_build_object('source', 'capture'));
  perform app.emit('lead.created', 'lead', v_id, '{}'::jsonb, p_sample);
  return v_id;
end $fn$;

create function app.capture_deal(p_title text, p_person uuid, p_org uuid, p_source text, p_owner uuid, p_pipeline uuid, p_stage uuid, p_sample boolean default false)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_id uuid;
  v_pipeline uuid := coalesce(p_pipeline, (select id from app.pipelines where archived_at is null and not is_sample order by ord limit 1));
  v_stage uuid := coalesce(p_stage, (select id from app.stages where pipeline_id = v_pipeline order by ord limit 1));
begin
  if v_pipeline is null or v_stage is null or not exists (select 1 from app.stages where id = v_stage and pipeline_id = v_pipeline) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id';
  end if;
  insert into app.deals (title, person_id, organization_id, source, owner_id, visibility, pipeline_id, stage_id, created_by, updated_by, is_sample)
  values (left(btrim(p_title), 200), p_person, p_org, left(p_source, 60), p_owner, app.setting('visibility_default', 'deal'), v_pipeline, v_stage, app.me(), app.me(), p_sample)
  returning id into v_id;
  insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by) values (v_id, v_stage, now(), app.me());
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('deal', v_id, '*created', app.me(), 'capture');
  perform app.log('record.created', 'deal', v_id::text, jsonb_build_object('source', 'capture'));
  perform app.emit('deal.created', 'deal', v_id, '{}'::jsonb, p_sample);
  return v_id;
end $fn$;

-- one path from a capture to a ticket: forms, and the products' support.requested / contact.submitted (D-20).
-- The message is the requester's own words: it goes into the thread, never into the audit.
create function app.ticket_from_capture(p_category text, p_subject text, p_email text, p_organization uuid, p_message text, p_channel text,
                                        p_source_ref uuid default null, p_product text default null, p_context jsonb default '{}'::jsonb,
                                        p_source_event bigint default null, p_person uuid default null, p_sample boolean default false)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_cat text; v_queue text; v_id uuid;
begin
  v_cat := coalesce((select key from app.ticket_categories where key = p_category and active), 'sales');
  v_queue := (select queue_key from app.ticket_categories where key = v_cat);
  insert into app.tickets (type, category_key, queue_key, subject, organization_id, person_id, requester_email, product, channel, context, source_event_id,
                           org_stage_at_open, is_sample)
  values ('question', v_cat, v_queue, left(coalesce(nullif(btrim(p_subject), ''), v_cat), 200), p_organization, p_person, left(p_email, 254), p_product, p_channel,
          coalesce(p_context, '{}'::jsonb) || case when p_source_ref is not null then jsonb_build_object('form_submission', p_source_ref) else '{}'::jsonb end,
          p_source_event, 'none', coalesce(p_sample, false))
  returning id into v_id;
  if coalesce(btrim(p_message), '') <> '' then
    insert into app.ticket_messages (ticket_id, kind, author_person_id, body) values (v_id, 'customer', p_person, left(btrim(p_message), 20000));
  end if;
  insert into app.audit (actor, action, target_type, target_id, ok, detail)
  values ('system', 'ticket.created', 'ticket', v_id::text, true, jsonb_strip_nulls(jsonb_build_object('event', p_source_event, 'form_submission', p_source_ref)));
  return v_id;
end $fn$;

-- intake from product events, now on the shared path; contact.submitted also gets its lead (D-20, 0012's note)
create or replace function app.ticket_intake(p_event bigint) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.events_in; v_id uuid; v_org uuid; v_cat text; v_person uuid; v_lead uuid; v_email text;
begin
  select * into e from app.events_in where id = p_event;
  if not found or e.kind not in ('support.requested', 'contact.submitted') then return null; end if;
  if exists (select 1 from app.tickets where source_event_id = p_event) then return null; end if;
  select o.id into v_org from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  where ap.product = e.product and ap.tenant_id = e.tenant_id and o.deleted_at is null limit 1;
  v_cat := coalesce((select key from app.ticket_categories where key = e.payload ->> 'category' and active), case e.kind when 'contact.submitted' then 'sales' else 'getting_started' end);
  v_id := app.ticket_from_capture(v_cat, coalesce(nullif(btrim(e.payload ->> 'subject'), ''), e.kind), e.payload ->> 'email', v_org, e.payload ->> 'message',
                                  case e.kind when 'contact.submitted' then 'contact_form' else 'in_app' end, null, e.product,
                                  jsonb_strip_nulls(jsonb_build_object('role', e.payload ->> 'role', 'page', e.payload ->> 'page', 'browser', e.payload ->> 'browser',
                                                                       'app_version', e.payload ->> 'app_version')),
                                  p_event);
  if e.kind = 'contact.submitted' then
    begin
      v_email := lower(nullif(btrim(e.payload ->> 'email'), ''));
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
      v_person := app.capture_person(v_email, case when v_email is not null then e.payload ->> 'name' end, null, v_org, 'Contact form', null);
      if v_person is not null or v_org is not null then
        v_lead := app.capture_lead(coalesce(nullif(btrim(e.payload ->> 'subject'), ''), e.kind), v_person, v_org, 'Contact form', null, null);
        insert into app.ticket_links (ticket_id, kind, ref) values (v_id, 'lead', v_lead::text) on conflict do nothing;
        update app.tickets set person_id = coalesce(person_id, v_person) where id = v_id;
      end if;
    exception when others then
      -- the ticket stands: a lead that cannot be made never loses the request
      insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'lead.skipped', 'ticket', v_id::text, false, jsonb_build_object('event', p_event));
    end;
  end if;
  return v_id;
end $fn$;

-- product events reach the subscribers as platform events (0021); their data now also leaves out a person's own words
-- (a contact request's subject and message), so no free text reaches an event payload (§10)
create or replace function app.product_event_out() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_org uuid;
begin
  if new.kind !~ '^[a-z_]+\.[a-z_]+$' then return new; end if;
  select o.id into v_org from app.account_products ap join app.organizations o on o.account_id = ap.account_id
  where ap.product = new.product and ap.tenant_id = new.tenant_id and o.deleted_at is null order by o.created_at limit 1;
  if v_org is null then return new; end if;
  insert into app.events (kind, subject_type, subject_id, payload, is_sample)
  values (new.kind, 'organization', v_org,
          jsonb_build_object('source', 'product', 'product', new.product, 'event_in', new.id,
                             'data', (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(new.payload) as x(k, v)
                                      where jsonb_typeof(v) in ('string', 'number', 'boolean') and k !~ '(name|email|phone|message|subject|body|comment|text)')),
          false);
  return new;
end $fn$;

-- ---------------------------------------------------------------------------
-- address-level consent (CMP-04): a new address does not inherit the old one's consent
create function app.person_email_changed() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_latest text; v_status text;
begin
  if lower(coalesce(new.email, '')) = lower(coalesce(old.email, '')) or old.marketing_status = 'no_consent' then return new; end if;
  if new.email is not null then
    select c.status into v_latest from app.consent_events c where c.email_sha256 = app.email_hash(new.email) order by c.id desc limit 1;
  end if;
  v_status := case when v_latest = 'subscribed' then 'subscribed' else 'no_consent' end;
  if v_status = old.marketing_status then return new; end if;
  insert into app.consent_events (person_id, status, prev_status, email_sha256, source, actor_id, ref_type, detail)
  values (new.id, v_status, old.marketing_status, app.email_hash(new.email), 'email_changed', app.me(), 'email_changed',
          case when v_status = 'subscribed' then 'address_consented' end);
  new.marketing_status := v_status;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('person', new.id, 'marketing_status', to_jsonb(old.marketing_status), to_jsonb(v_status), app.me(), 'system');
  perform app.emit('consent.changed', 'person', new.id, jsonb_build_object('status', v_status, 'ref_type', 'email_changed'), new.is_sample);
  return new;
end $fn$;
create trigger person_email_changed before update of email on app.people for each row execute function app.person_email_changed();

-- erasure (SEC-11): a person's form values and chat transcripts go with them; the address stays suppressed by its
-- hash. The routine purge of soft-deleted records (app.purging) and the sandbox are not an erasure request.
create function app.person_erased() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  update app.form_submissions set field_values = '{}'::jsonb, fingerprint = null, tracking = '{}'::jsonb, consent = '{}'::jsonb, files = '[]'::jsonb
  where person_id = old.id;
  delete from app.chat_conversations where person_id = old.id;
  if old.email is not null and not old.is_sample and coalesce(current_setting('app.purging', true), '') <> 'on'
     and not exists (select 1 from app.suppressions s where s.email_sha256 = app.email_hash(old.email)) then
    insert into app.suppressions (email_sha256, scope, reason, created_by) values (app.email_hash(old.email), 'marketing', 'erasure', app.me());
  end if;
  return old;
end $fn$;
create trigger person_erased before delete on app.people for each row execute function app.person_erased();

-- ---------------------------------------------------------------------------
-- consent and suppressions (CMP-03, CMP-04)
drop function public.consent_set(uuid, text, text, text);
create function public.consent_set(p_person uuid, p_status text, p_source text, p_basis text default null,
                                   p_ref_type text default 'staff', p_ref_id uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); p app.people;
begin
  select * into p from app.people where id = p_person and deleted_at is null;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p.owner_id is distinct from v_me and not app.can('deals', 'edit_others') and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  if p_status is null or p_status not in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  if coalesce(btrim(p_source), '') = '' or char_length(btrim(p_source)) > 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
  if coalesce(p_ref_type, 'staff') not in ('staff', 'import', 'list_hygiene', 'provider') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ref_type';
  end if;
  if app.setting('contact_rule') <> 'no_rule' and p_status = 'subscribed' and coalesce(btrim(p_basis), '') = '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'basis:required';
  end if;
  perform app.consent_write(p_person, p_status, p_source, p_basis, coalesce(p_ref_type, 'staff'), p_ref_id, null, null, 'ui');
  return jsonb_build_object('status', p_status);
end $fn$;

-- the wordings: the latest version of each key and locale; a change is a new version, never an edit
create function public.consent_texts_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('campaigns', 'see');
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'key', t.key, 'locale', t.locale, 'body', t.body, 'version', t.version, 'created_at', t.created_at,
                                                       'by', (select a.name from app.admins a where a.id = t.created_by)) order by t.key, t.locale)
                   from (select distinct on (key, locale) * from app.consent_texts order by key, locale, version desc) t), '[]'::jsonb);
end $fn$;

create function public.consent_text_save(p_key text, p_locale text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); v_id uuid; v_version int;
begin
  if coalesce(p_key, '') !~ '^[a-z_]{2,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key'; end if;
  if p_locale is null or p_locale not in ('nb', 'nn', 'en', 'sv') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'locale'; end if;
  if coalesce(btrim(p_body), '') = '' or char_length(btrim(p_body)) > 2000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  v_version := coalesce((select max(version) from app.consent_texts where key = p_key and locale = p_locale), 0) + 1;
  insert into app.consent_texts (key, locale, body, version, created_by) values (p_key, p_locale, btrim(p_body), v_version, v_me) returning id into v_id;
  perform app.log('consent_text.saved', 'consent_text', v_id::text, jsonb_build_object('key', p_key, 'locale', p_locale, 'version', v_version));
  return jsonb_build_object('id', v_id, 'version', v_version);
end $fn$;

-- the consent log: newest changes first, with the address, the change and its source
create function public.consent_log(p_limit int default 50, p_before bigint default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('campaigns');
  select coalesce(jsonb_agg(x.j order by x.id desc), '[]'::jsonb) into v_rows from (
    select c.id, jsonb_build_object('id', c.id, 'at', c.at, 'person_id', p.id, 'name', p.name, 'email', p.email, 'prev_status', c.prev_status, 'status', c.status,
             'source', c.source, 'basis', c.basis, 'ref_type', c.ref_type, 'ref_id', c.ref_id, 'detail', c.detail,
             'ref_label', case when c.ref_type in ('form_submission', 'confirmation')
                               then (select f.name from app.form_submissions s join app.forms f on f.id = s.form_id where s.id = c.ref_id) end,
             'text_version', (select t.version from app.consent_texts t where t.id = c.text_id),
             'actor', (select a.name from app.admins a where a.id = c.actor_id)) j
    from app.consent_events c join app.people p on p.id = c.person_id
    where (p_before is null or c.id < p_before) and p.deleted_at is null and app.visible(p.owner_id, p.visibility) and (v_sandbox or not p.is_sample)
    order by c.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) x;
  perform app.log('record.listed', 'consent_event', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'next', (select min((r ->> 'id')::bigint) from jsonb_array_elements(v_rows) r));
end $fn$;

-- the marketing status of every address (people with an email, not deleted, not sample)
create function public.marketing_status_summary() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('campaigns');
  return jsonb_build_object(
    'statuses', (select jsonb_agg(jsonb_build_object('status', s.st, 'n', (select count(*) from app.people p where p.marketing_status = s.st and p.email is not null
                                                                                 and p.deleted_at is null and not p.is_sample)) order by s.ord)
                 from unnest(array['subscribed', 'pending', 'no_consent', 'unsubscribed', 'bounced', 'archived']) with ordinality s(st, ord)),
    'suppressed', (select count(*) from app.suppressions),
    'double_opt_in', app.setting('double_opt_in'));
end $fn$;

-- suppressions are hashes: a search is by the full address; a row names a person only where one has that address
create function public.suppressions_get(p_q text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_hash bytea := case when btrim(coalesce(p_q, '')) like '%@%' then app.email_hash(p_q) end; v_rows jsonb;
begin
  perform app.require_module('campaigns');
  if btrim(coalesce(p_q, '')) <> '' and v_hash is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'q'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('hash', left(encode(s.email_sha256, 'hex'), 12), 'scope', s.scope, 'reason', s.reason, 'campaign_id', s.campaign_id,
                                               'created_at', s.created_at, 'by', (select a.name from app.admins a where a.id = s.created_by),
                                               'email', (select p.email from app.people p where p.email is not null and app.email_hash(p.email) = s.email_sha256
                                                           and p.deleted_at is null and app.visible(p.owner_id, p.visibility) limit 1))
                            order by s.created_at desc), '[]'::jsonb)
  into v_rows from (select * from app.suppressions where v_hash is null or email_sha256 = v_hash order by created_at desc limit 200) s;
  perform app.log('record.listed', 'suppression', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

create function public.suppression_add(p_email text, p_reason text default null, p_scope text default 'marketing') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'bulk'); n int;
begin
  perform app.require_module('campaigns');
  perform app.take_reason(p_reason);
  if coalesce(btrim(p_email), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(btrim(p_email)) > 254 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'email';
  end if;
  if p_scope is null or p_scope not in ('marketing', 'all') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope'; end if;
  insert into app.suppressions (email_sha256, scope, reason, created_by) values (app.email_hash(p_email), p_scope, 'manual', v_me) on conflict do nothing;
  get diagnostics n = row_count;
  perform app.log('suppression.added', 'suppression', null, jsonb_build_object('scope', p_scope, 'added', n));
  return jsonb_build_object('added', n = 1);
end $fn$;

-- only a manual or bounce suppression can be lifted; an unsubscribe or a complaint is the person's own decision
create function public.suppression_remove(p_email text, p_scope text, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'bulk'); v_why text;
begin
  perform app.require_module('campaigns');
  perform app.take_reason(p_reason);
  select reason into v_why from app.suppressions where email_sha256 = app.email_hash(p_email) and scope = p_scope for update;
  if v_why is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if v_why not in ('manual', 'hard_bounce', 'soft_bounces') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reason'; end if;
  delete from app.suppressions where email_sha256 = app.email_hash(p_email) and scope = p_scope;
  perform app.log('suppression.removed', 'suppression', null, jsonb_build_object('scope', p_scope, 'reason', v_why));
  return jsonb_build_object('removed', true);
end $fn$;

-- the double opt-in link (go.owntheagenda.com/c/<token>): single use, seven days, for the address it was sent to
create function public.worker_consent_confirm(p_token text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.consent_confirmations; p app.people;
begin
  select * into c from app.consent_confirmations where token_sha256 = app.token_hash(p_token) for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.confirmed_at is not null then return jsonb_build_object('status', 'subscribed', 'already', true); end if;
  if c.expires_at < now() then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'expired'; end if;
  select * into p from app.people where id = c.person_id and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if app.email_hash(p.email) is distinct from c.email_sha256 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'email'; end if;
  if p.marketing_status not in ('pending', 'subscribed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  update app.consent_confirmations set confirmed_at = now() where token_sha256 = c.token_sha256;
  if p.marketing_status = 'pending' then
    perform app.consent_write(p.id, 'subscribed', 'double_opt_in', 'consent', 'confirmation', c.submission_id, c.text_id, null, 'capture');
  end if;
  -- a confirmed new opt-in lifts the address's earlier unsubscribe; a complaint or a bounce stays
  delete from app.suppressions where email_sha256 = c.email_sha256 and scope = 'marketing' and reason = 'unsubscribed';
  update app.form_submissions set consent = consent || jsonb_build_object('status', 'subscribed', 'confirmed_at', now()) where id = c.submission_id;
  return jsonb_build_object('status', 'subscribed');
end $fn$;

-- ---------------------------------------------------------------------------
-- forms: the draft's shape. Fields map to a person, an organization or a custom field (app.fields); the intro is
-- mandatory (LGN-03); the consent box shows a wording from consent_texts; tracking never holds a cookie id (Q7).
create function app.form_check(p_kind text, p_language text, p_draft jsonb, p_publish boolean default false) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  d jsonb := p_draft; f jsonb; a jsonb; i int := 0; k text; v_kind text; v_map text; v_req boolean;
  v_keys text[] := '{}'; v_maps text[] := '{}'; v_fields jsonb := '[]'::jsonb;
  v_consent int := 0; v_files int := 0; v_email boolean := false; v_contact boolean := false;
begin
  if d is null or jsonb_typeof(d) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'draft'; end if;
  if jsonb_typeof(d -> 'intro') is distinct from 'object' or coalesce(btrim(d #>> '{intro,title}'), '') = '' or char_length(d #>> '{intro,title}') > 200
     or char_length(coalesce(d #>> '{intro,body}', '')) > 2000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'intro';
  end if;
  if jsonb_typeof(coalesce(d -> 'fields', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(d -> 'fields', '[]'::jsonb)) > 50 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields';
  end if;
  for f in select * from jsonb_array_elements(coalesce(d -> 'fields', '[]'::jsonb)) loop
    i := i + 1;
    if jsonb_typeof(f) <> 'object' or coalesce(f ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,40}$' or (f ->> 'key') = any (v_keys)
       or coalesce(f ->> 'kind', '') not in ('short_text', 'email', 'phone', 'marketing_status', 'custom_field', 'file_upload', 'message') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || i;
    end if;
    k := f ->> 'key'; v_kind := f ->> 'kind'; v_keys := v_keys || k;
    if v_kind <> 'marketing_status' and (coalesce(btrim(f ->> 'label'), '') = '' or char_length(f ->> 'label') > 200) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || k || '.label';
    end if;
    if jsonb_typeof(f -> 'required') not in ('boolean', 'null') or char_length(coalesce(f ->> 'placeholder', '')) > 200 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || k;
    end if;
    v_req := coalesce((f ->> 'required')::boolean, false);
    v_map := case v_kind when 'email' then 'person.email' when 'phone' then 'person.phone'
                         when 'short_text' then f ->> 'map' when 'custom_field' then f ->> 'map' end;
    if (v_kind = 'short_text' and v_map is not null and v_map not in ('person.name', 'person.title', 'organization.name', 'organization.org_number'))
       or (v_kind = 'custom_field' and (coalesce(v_map, '') !~ '^custom\.(person|organization|lead)\.[a-z][a-z0-9_]{1,40}$'
           or not exists (select 1 from app.fields x where x.entity = split_part(v_map, '.', 2) and x.key = split_part(v_map, '.', 3)
                            and x.archived_at is null and x.type <> 'formula')))
       or (v_map is not null and v_map = any (v_maps)) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || k || '.map';
    end if;
    if v_map is not null then v_maps := v_maps || v_map; end if;
    if v_kind = 'marketing_status' then v_consent := v_consent + 1; v_req := false; end if;
    if v_kind = 'file_upload' then v_files := v_files + 1; end if;
    if v_map = 'person.email' then v_email := true; end if;
    if v_req and v_map in ('person.email', 'organization.org_number', 'organization.name') then v_contact := true; end if;
    v_fields := v_fields || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('key', k, 'kind', v_kind, 'label', btrim(f ->> 'label'), 'map', v_map,
                                                                                   'required', v_req, 'placeholder', nullif(btrim(f ->> 'placeholder'), ''))));
  end loop;
  if v_consent > 1 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.marketing_status'; end if;
  if v_files > 0 and p_kind <> 'file_upload' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.file_upload'; end if;
  -- consent: a wording in the form's language; the form may only turn double opt-in on (Q3)
  if jsonb_typeof(coalesce(d -> 'consent', '{}'::jsonb)) <> 'object'
     or (d #>> '{consent,text_key}') !~ '^[a-z_]{2,40}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'consent';
  end if;
  if jsonb_typeof(d #> '{consent,double_opt_in}') not in ('null') and (d #> '{consent,double_opt_in}') <> 'true'::jsonb then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'consent.double_opt_in';
  end if;
  if jsonb_typeof(coalesce(d -> 'hidden', '[]'::jsonb)) <> 'array'
     or exists (select 1 from jsonb_array_elements(coalesce(d -> 'hidden', '[]'::jsonb)) h
                where jsonb_typeof(h) <> 'string' or (h #>> '{}') not in ('utm', 'referrer_host', 'landing_path', 'page_vars')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hidden';
  end if;
  a := coalesce(d -> 'after_submit', '{}'::jsonb);
  if jsonb_typeof(a) <> 'object' or coalesce(a ->> 'creates', 'lead') not in ('lead', 'deal') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.creates';
  end if;
  if (a ->> 'pipeline_id') is not null and not exists (select 1 from app.pipelines p where p.id::text = a ->> 'pipeline_id' and p.archived_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.pipeline_id';
  end if;
  if (a ->> 'stage_id') is not null and not exists (select 1 from app.stages s where s.id::text = a ->> 'stage_id' and s.pipeline_id::text = a ->> 'pipeline_id') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.stage_id';
  end if;
  if jsonb_typeof(a -> 'ticket') not in ('boolean', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.ticket'; end if;
  if (a ->> 'sequence_id') is not null and not exists (select 1 from app.workflows w where w.id::text = a ->> 'sequence_id' and w.kind = 'sequence' and w.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.sequence_id';
  end if;
  if char_length(coalesce(a ->> 'thank_you', '')) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.thank_you'; end if;
  if (a ->> 'redirect_url') is not null and ((a ->> 'redirect_url') !~ '^https://[^\s<>"]+$' or char_length(a ->> 'redirect_url') > 2000) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.redirect_url';
  end if;
  if (a ->> 'asset_path') is not null and (p_kind <> 'gated_download' or (a ->> 'asset_path') !~ '^[A-Za-z0-9][A-Za-z0-9/_.-]{0,299}$' or (a ->> 'asset_path') like '%..%') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.asset_path';
  end if;
  if p_publish then
    -- a lead needs a person or an organization: a required email, org number or company name
    if not v_contact then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.contact'; end if;
    if v_consent = 1 and not v_email then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'consent.email'; end if;
    if v_consent = 1 and not exists (select 1 from app.consent_texts t where t.key = d #>> '{consent,text_key}' and t.locale = p_language) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'consent.text_key';
    end if;
    if p_kind = 'gated_download' and (a ->> 'asset_path') is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.asset_path'; end if;
    if (a ->> 'creates') = 'deal' and (a ->> 'pipeline_id') is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'after_submit.pipeline_id'; end if;
  end if;
  return jsonb_build_object(
    'intro', jsonb_build_object('title', btrim(d #>> '{intro,title}'), 'body', coalesce(d #>> '{intro,body}', '')),
    'fields', v_fields,
    'hidden', coalesce(d -> 'hidden', '[]'::jsonb),
    'consent', jsonb_strip_nulls(jsonb_build_object('text_key', d #>> '{consent,text_key}',
                                                    'double_opt_in', case when (d #> '{consent,double_opt_in}') = 'true'::jsonb then true end)),
    'after_submit', jsonb_strip_nulls(jsonb_build_object('creates', coalesce(a ->> 'creates', 'lead'), 'pipeline_id', a ->> 'pipeline_id', 'stage_id', a ->> 'stage_id',
                                                         'ticket', coalesce((a ->> 'ticket')::boolean, p_kind = 'contact'), 'sequence_id', a ->> 'sequence_id',
                                                         'thank_you', nullif(btrim(a ->> 'thank_you'), ''), 'redirect_url', a ->> 'redirect_url', 'asset_path', a ->> 'asset_path')))
    -- employee lists belong in the product, never in the platform (Q8, D-34): a fixed notice on every file-upload form
    || case when p_kind = 'file_upload' then jsonb_build_object('notice', 'employee_list') else '{}'::jsonb end;
end $fn$;

-- the fields a new form starts with, labelled in the form's language (the design's «Kontakt oss»: Navn, E-post, Telefon,
-- Organisasjonsnummer); the staff member edits them
create function app.form_seed(p_kind text, p_language text) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  with l(k, nb, nn, en, sv) as (values
    ('name', 'Navn', 'Namn', 'Name', 'Namn'), ('email', 'E-post', 'E-post', 'Email', 'E-post'), ('phone', 'Telefon', 'Telefon', 'Phone', 'Telefon'),
    ('org_number', 'Organisasjonsnummer', 'Organisasjonsnummer', 'Organisation number', 'Organisationsnummer'),
    ('company', 'Bedrift', 'Bedrift', 'Company', 'Företag'), ('message', 'Melding', 'Melding', 'Message', 'Meddelande'), ('file', 'Fil', 'Fil', 'File', 'Fil')),
  lab as (select l.k key, case p_language when 'nn' then l.nn when 'en' then l.en when 'sv' then l.sv else l.nb end label from l)
  select coalesce(jsonb_agg(x.f order by x.ord), '[]'::jsonb) from (
    select s.ord, jsonb_strip_nulls(jsonb_build_object('key', s.key, 'kind', s.kind, 'label', (select label from lab where lab.key = s.lk), 'map', s.map, 'required', s.req)) f
    from (values
      ('contact', 1, 'name', 'short_text', 'name', 'person.name', true), ('contact', 2, 'email', 'email', 'email', null, true),
      ('contact', 3, 'phone', 'phone', 'phone', null, false), ('contact', 4, 'org_number', 'short_text', 'org_number', 'organization.org_number', true),
      ('contact', 5, 'message', 'message', 'message', null, false), ('contact', 6, 'consent', 'marketing_status', null, null, false),
      ('registration', 1, 'name', 'short_text', 'name', 'person.name', true), ('registration', 2, 'email', 'email', 'email', null, true),
      ('registration', 3, 'company', 'short_text', 'company', 'organization.name', false), ('registration', 4, 'consent', 'marketing_status', null, null, false),
      ('gated_download', 1, 'name', 'short_text', 'name', 'person.name', true), ('gated_download', 2, 'email', 'email', 'email', null, true),
      ('gated_download', 3, 'company', 'short_text', 'company', 'organization.name', false), ('gated_download', 4, 'consent', 'marketing_status', null, null, false),
      ('file_upload', 1, 'name', 'short_text', 'name', 'person.name', true), ('file_upload', 2, 'email', 'email', 'email', null, true),
      ('file_upload', 3, 'file', 'file_upload', 'file', null, true),
      ('blank', 1, 'email', 'email', 'email', null, true)
    ) as s(fkind, ord, key, kind, lk, map, req)
    where s.fkind = p_kind) x
$fn$;

create function app.form_row(f app.forms) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', f.id, 'name', f.name, 'kind', f.kind, 'language', f.language, 'status', f.status, 'current_version', f.current_version,
    'public_id', f.public_id, 'public_url', 'https://go.owntheagenda.com/f/' || f.public_id, 'version', f.version, 'updated_at', f.updated_at,
    'owner', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = f.owner_id),
    'submissions_month', (select coalesce(sum(s.submissions), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', current_date)::date),
    'views_month', (select coalesce(sum(s.views), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', current_date)::date),
    -- the page the form is embedded on: the most frequent landing path of the last 30 days (only while form_tracking was on)
    'landing', (select x.tracking ->> 'landing_path' from app.form_submissions x where x.form_id = f.id and x.created_at > now() - interval '30 days'
                and x.tracking ? 'landing_path' group by 1 order by count(*) desc limit 1))
$fn$;

create function app.form_take(p_id uuid, p_edit boolean) returns app.forms
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.forms; v_me uuid := app.me();
begin
  select * into f from app.forms where id = p_id and deleted_at is null for update;
  if not found or not app.visible(f.owner_id, f.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_edit and f.owner_id is distinct from v_me and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
  end if;
  return f;
end $fn$;

create function public.forms_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('leadgen');
  select coalesce(jsonb_agg(app.form_row(f) order by f.updated_at desc), '[]'::jsonb) into v_rows
  from app.forms f where f.deleted_at is null and app.visible(f.owner_id, f.visibility) and (v_sandbox or not f.is_sample);
  perform app.log('record.listed', 'form', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

create function public.form_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.forms;
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('leadgen');
  f := app.form_take(p_id, false);
  perform app.log('record.read', 'form', p_id::text);
  return app.form_row(f) || jsonb_build_object(
    'draft', f.draft,
    'published', (select v.definition from app.form_versions v where v.form_id = f.id and v.version = f.current_version),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'published_at', v.published_at,
                                                              'by', (select a.name from app.admins a where a.id = v.published_by)) order by v.version desc), '[]'::jsonb)
                 from app.form_versions v where v.form_id = f.id),
    'consent_texts', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'key', t.key, 'body', t.body, 'version', t.version) order by t.key), '[]'::jsonb)
                      from (select distinct on (key) * from app.consent_texts where locale = f.language order by key, version desc) t),
    'settings', jsonb_build_object('double_opt_in', app.setting('double_opt_in'), 'form_tracking', app.setting('form_tracking'),
                                   'email_connected', app.connected('email')));
end $fn$;

create function public.form_create(p_kind text, p_name text, p_language text default 'nb') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); v_id uuid; v_public text;
begin
  perform app.require_module('leadgen');
  if p_kind is null or p_kind not in ('contact', 'registration', 'gated_download', 'file_upload', 'blank') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if p_language is null or p_language not in ('nb', 'nn', 'en', 'sv') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'language'; end if;
  if coalesce(btrim(p_name), '') = '' or char_length(btrim(p_name)) > 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  insert into app.forms (name, kind, language, draft, owner_id, visibility, created_by, updated_by, is_sample)
  values (btrim(p_name), p_kind, p_language,
          app.form_check(p_kind, p_language, jsonb_build_object('intro', jsonb_build_object('title', btrim(p_name), 'body', ''), 'fields', app.form_seed(p_kind, p_language),
                                                                'hidden', '["utm", "referrer_host", "landing_path"]'::jsonb,
                                                                'consent', jsonb_build_object('text_key', 'newsletter'), 'after_submit', '{}'::jsonb)),
          v_me, app.setting('visibility_default', 'form'), v_me, v_me, (select sandbox from app.admins where id = v_me))
  returning id, public_id into v_id, v_public;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('form', v_id, '*created', v_me, 'ui');
  perform app.log('record.created', 'form', v_id::text, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('id', v_id, 'version', 1, 'public_id', v_public);
end $fn$;

create function public.form_save(p_id uuid, p_draft jsonb, p_version int, p_name text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); f app.forms; v_draft jsonb; v_version int;
begin
  perform app.require_module('leadgen');
  f := app.form_take(p_id, true);
  if p_version is not null and f.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = f.version::text; end if;
  if p_name is not null and (btrim(p_name) = '' or char_length(btrim(p_name)) > 120) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  v_draft := app.form_check(f.kind, f.language, coalesce(p_draft, f.draft), false);
  update app.forms set draft = v_draft, name = coalesce(btrim(p_name), name), version = version + 1, updated_at = now(), updated_by = v_me
  where id = p_id returning version into v_version;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('form', p_id, '*draft', null, jsonb_build_object('fields', jsonb_array_length(v_draft -> 'fields')), v_me, 'ui');
  if p_name is not null and btrim(p_name) <> f.name then
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('form', p_id, 'name', to_jsonb(f.name), to_jsonb(btrim(p_name)), v_me, 'ui');
  end if;
  perform app.log('record.updated', 'form', p_id::text, jsonb_build_object('fields', jsonb_array_length(v_draft -> 'fields')));
  return jsonb_build_object('id', p_id, 'version', v_version);
end $fn$;

-- publishing freezes the draft as the next version; submissions are stored against the version they answered
create function public.form_publish(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); f app.forms; v_def jsonb;
begin
  perform app.require_module('leadgen');
  f := app.form_take(p_id, false);
  v_def := app.form_check(f.kind, f.language, f.draft, true);
  insert into app.form_versions (form_id, version, definition, published_by) values (p_id, f.current_version + 1, v_def, v_me);
  update app.forms set current_version = f.current_version + 1, draft = v_def, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('form', p_id, '*published', to_jsonb(f.current_version), to_jsonb(f.current_version + 1), v_me, 'ui');
  perform app.log('form.published', 'form', p_id::text, jsonb_build_object('version', f.current_version + 1));
  return jsonb_build_object('id', p_id, 'current_version', f.current_version + 1);
end $fn$;

create function public.form_set_status(p_id uuid, p_status text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); f app.forms;
begin
  perform app.require_module('leadgen');
  if p_status is null or p_status not in ('active', 'inactive') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  f := app.form_take(p_id, false);
  if p_status = 'active' and f.current_version = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'unpublished'; end if;
  if f.status = p_status then return jsonb_build_object('id', p_id, 'status', p_status); end if;
  update app.forms set status = p_status, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('form', p_id, 'status', to_jsonb(f.status), to_jsonb(p_status), v_me, 'ui');
  perform app.log('form.status_set', 'form', p_id::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('id', p_id, 'status', p_status);
end $fn$;

create function public.form_delete(p_id uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'delete'); f app.forms;
begin
  perform app.require_module('leadgen');
  perform app.take_reason(p_reason);
  f := app.form_take(p_id, false);
  update app.forms set deleted_at = now(), status = 'inactive', version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('form', p_id, '*deleted', v_me, 'ui');
  perform app.log('record.deleted', 'form', p_id::text, jsonb_build_object('count', 1));
  perform app.emit('form.deleted', 'form', p_id, '{}'::jsonb, f.is_sample);
  return jsonb_build_object('deleted', 1);
end $fn$;

-- views, starts and submissions per day; conversion = submissions ÷ views (LGN-03)
create function public.form_stats(p_id uuid, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.forms; v_days int := least(greatest(coalesce(p_days, 30), 1), 365); v_rows jsonb;
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('leadgen');
  select * into f from app.forms where id = p_id and deleted_at is null;
  if not found or not app.visible(f.owner_id, f.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select jsonb_agg(jsonb_build_object('day', g.day, 'views', coalesce(s.views, 0), 'starts', coalesce(s.starts, 0), 'submissions', coalesce(s.submissions, 0)) order by g.day)
  into v_rows
  from generate_series(current_date - (v_days - 1), current_date, interval '1 day') g(day)
  left join app.form_stats_daily s on s.form_id = p_id and s.day = g.day::date;
  return jsonb_build_object('days', v_rows,
    'views', (select coalesce(sum((r ->> 'views')::int), 0) from jsonb_array_elements(v_rows) r),
    'starts', (select coalesce(sum((r ->> 'starts')::int), 0) from jsonb_array_elements(v_rows) r),
    'submissions', (select coalesce(sum((r ->> 'submissions')::int), 0) from jsonb_array_elements(v_rows) r),
    'conversion', (select case when sum((r ->> 'views')::int) > 0 then round(sum((r ->> 'submissions')::int)::numeric / sum((r ->> 'views')::int), 4) end
                   from jsonb_array_elements(v_rows) r));
end $fn$;

-- submissions read through the lead's visibility (deals:see + app.visible); spam and duplicates carry no content
create function public.form_submissions(p_id uuid, p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.forms; v_rows jsonb;
begin
  perform app.require('campaigns', 'see');
  perform app.require('deals', 'see');
  perform app.require_module('leadgen');
  select * into f from app.forms where id = p_id and deleted_at is null;
  if not found or not app.visible(f.owner_id, f.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) into v_rows from (
    select s.created_at, jsonb_build_object('id', s.id, 'state', s.state, 'created_at', s.created_at, 'form_version', s.form_version,
             'consent', s.consent, 'tracking', s.tracking, 'files', jsonb_array_length(s.files), 'ticket_id', s.ticket_id,
             'person', (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email) from app.people p where p.id = s.person_id and app.visible(p.owner_id, p.visibility)),
             'lead_id', case when l.id is not null and app.visible(l.owner_id, l.visibility) then l.id end,
             'deal_id', (select d.id from app.deals d where d.id = s.deal_id and app.visible(d.owner_id, d.visibility)),
             'values', case when (l.id is not null and app.visible(l.owner_id, l.visibility))
                              or (s.deal_id is not null and exists (select 1 from app.deals d where d.id = s.deal_id and app.visible(d.owner_id, d.visibility)))
                            then s.field_values end) j
    from app.form_submissions s left join app.leads l on l.id = s.lead_id
    where s.form_id = p_id order by s.created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) x;
  perform app.log('record.listed', 'form_submission', p_id::text, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

-- ---------------------------------------------------------------------------
-- the public form (go.owntheagenda.com/f/<public_id>, D-28), through the edge function with the service role
create function public.worker_form_definition(p_public_id text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.forms; d jsonb; t app.consent_texts;
begin
  select * into f from app.forms where public_id = p_public_id and deleted_at is null and status = 'active';
  if not found or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select definition into d from app.form_versions where form_id = f.id and version = f.current_version;
  if exists (select 1 from jsonb_array_elements(d -> 'fields') x where x ->> 'kind' = 'marketing_status') then
    select * into t from app.consent_texts where key = d #>> '{consent,text_key}' and locale = f.language order by version desc limit 1;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('public_id', f.public_id, 'version', f.current_version, 'language', f.language, 'kind', f.kind,
    'intro', d -> 'intro',
    'fields', (select coalesce(jsonb_agg(x - 'map' order by o), '[]'::jsonb) from jsonb_array_elements(d -> 'fields') with ordinality as e(x, o)),
    'consent', case when t.id is not null then jsonb_build_object('text_id', t.id, 'body', t.body) end,
    'hidden', case when app.setting('form_tracking') = 'on' then d -> 'hidden' else '[]'::jsonb end,
    'notice', d ->> 'notice'));
end $fn$;

-- views and starts: counters only, no visitor id
create function public.worker_form_event(p_public_id text, p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_form uuid; v_day date := (now() at time zone 'Europe/Oslo')::date;
begin
  if p_kind is null or p_kind not in ('view', 'start') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  select id into v_form from app.forms where public_id = p_public_id and deleted_at is null and status = 'active';
  if v_form is null or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.form_stats_daily (form_id, day, views, starts) values (v_form, v_day, case when p_kind = 'view' then 1 else 0 end, case when p_kind = 'start' then 1 else 0 end)
  on conflict (form_id, day) do update set views = app.form_stats_daily.views + excluded.views, starts = app.form_stats_daily.starts + excluded.starts;
  return jsonb_build_object('ok', true);
end $fn$;

-- the submit path (SF-17), one transaction: validate against the published version, spam, the person and the
-- organization, consent, the lead (or deal), the ticket, the sequence, the counters and form.submitted.
-- p_meta: {honeypot, fill_ms, rate_limited, consent_text_id, tracking: {utm, referrer_host, landing_path, page_vars}, files: [{path, name, size}]}
create function public.worker_form_submit(p_public_id text, p_answers jsonb, p_meta jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  f app.forms; d jsonb; a jsonb; fld jsonb; v jsonb; s text; k text; v_map text; v_type text;
  m jsonb := coalesce(p_meta, '{}'::jsonb);
  vals jsonb := '{}'::jsonb; c_person jsonb := '{}'::jsonb; c_org jsonb := '{}'::jsonb; c_lead jsonb := '{}'::jsonb;
  v_email text; v_name text; v_phone text; v_title text; v_org_nr text; v_org_name text; v_message text; v_consent boolean := false;
  v_fp bytea; v_dup app.form_submissions; v_sub uuid; v_person uuid; v_org uuid; v_lead uuid; v_deal uuid; v_ticket uuid;
  v_tracking jsonb := '{}'::jsonb; v_files jsonb := '[]'::jsonb; v_doi boolean; v_text app.consent_texts; v_token text; v_status text;
  v_day date := (now() at time zone 'Europe/Oslo')::date;
begin
  select * into f from app.forms where public_id = p_public_id and deleted_at is null;
  if not found or f.status <> 'active' or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers'; end if;
  if jsonb_typeof(m) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'meta'; end if;
  select definition into d from app.form_versions where form_id = f.id and version = f.current_version;
  a := coalesce(d -> 'after_submit', '{}'::jsonb);

  -- spam: the honeypot, a fill time under two seconds, or the edge's per-day-hash rate limit. Stored as a state only.
  if coalesce(m ->> 'honeypot', '') <> '' or (case when (m ->> 'fill_ms') ~ '^\d{1,9}$' then (m ->> 'fill_ms')::int end) < 2000
     or coalesce(m ->> 'rate_limited', '') = 'true' then
    insert into app.form_submissions (form_id, form_version, state, is_sample) values (f.id, f.current_version, 'spam', f.is_sample) returning id into v_sub;
    perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'spam'));
    return jsonb_build_object('ok', true);
  end if;

  -- the values, checked against the version the form was published as (the edge checked them with Zod first)
  for k in select jsonb_object_keys(p_answers) loop
    if not exists (select 1 from jsonb_array_elements(d -> 'fields') x where x ->> 'key' = k and x ->> 'kind' <> 'file_upload') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || left(k, 40);
    end if;
  end loop;
  for fld in select * from jsonb_array_elements(d -> 'fields') loop
    k := fld ->> 'key'; v := p_answers -> k; v_map := fld ->> 'map';
    continue when fld ->> 'kind' = 'file_upload';
    if fld ->> 'kind' = 'marketing_status' then
      if v is not null and jsonb_typeof(v) not in ('boolean', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_consent := coalesce(v = 'true'::jsonb, false);
      vals := vals || jsonb_build_object(k, v_consent);
      continue;
    end if;
    if v is not null and jsonb_typeof(v) not in ('string', 'number', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
    s := nullif(btrim(coalesce(v #>> '{}', '')), '');
    if s is null then
      if coalesce((fld ->> 'required')::boolean, false) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      continue;
    end if;
    if char_length(s) > (case when fld ->> 'kind' = 'message' then 5000 else 500 end) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k;
    end if;
    if v_map = 'person.email' then
      s := lower(s);
      if char_length(s) > 254 or s !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_email := s;
    elsif v_map = 'person.phone' then
      if char_length(s) > 40 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_phone := s;
    elsif v_map = 'person.name' then v_name := left(s, 200);
    elsif v_map = 'person.title' then v_title := left(s, 80);
    elsif v_map = 'organization.org_number' then
      s := regexp_replace(s, '\D', '', 'g');
      if s !~ '^\d{9}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_org_nr := s;
    elsif v_map = 'organization.name' then v_org_name := left(s, 200);
    elsif v_map like 'custom.%' then
      select x.type into v_type from app.fields x where x.entity = split_part(v_map, '.', 2) and x.key = split_part(v_map, '.', 3) and x.archived_at is null;
      v := case when v_type in ('numerical') and s ~ '^-?\d+(\.\d+)?$' then to_jsonb(s::numeric) else to_jsonb(s) end;
      begin
        perform app.check_custom(split_part(v_map, '.', 2), jsonb_build_object(split_part(v_map, '.', 3), v));
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k;
      end;
      case split_part(v_map, '.', 2)
        when 'person' then c_person := c_person || jsonb_build_object(split_part(v_map, '.', 3), v);
        when 'organization' then c_org := c_org || jsonb_build_object(split_part(v_map, '.', 3), v);
        else c_lead := c_lead || jsonb_build_object(split_part(v_map, '.', 3), v);
      end case;
    elsif fld ->> 'kind' = 'message' then v_message := s;
    end if;
    vals := vals || jsonb_build_object(k, s);
  end loop;

  -- a duplicate: the same values on the same form within a day. Stored as a state, linked to the first.
  v_fp := extensions.digest(f.id::text || vals::text, 'sha256');
  select * into v_dup from app.form_submissions where form_id = f.id and state = 'accepted' and fingerprint = v_fp and created_at > now() - interval '24 hours'
  order by created_at desc limit 1;
  if found then
    insert into app.form_submissions (form_id, form_version, state, person_id, organization_id, lead_id, deal_id, ticket_id, is_sample)
    values (f.id, f.current_version, 'duplicate', v_dup.person_id, v_dup.organization_id, v_dup.lead_id, v_dup.deal_id, v_dup.ticket_id, f.is_sample) returning id into v_sub;
    perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'duplicate'));
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'thank_you', a ->> 'thank_you', 'redirect_url', a ->> 'redirect_url'));
  end if;

  -- the organization (Brønnøysund enrichment queued for a new one), then the person (SF-17 step 3)
  v_org := app.capture_org(v_org_nr, v_org_name, 'Web form', null, f.is_sample);
  v_person := app.capture_person(v_email, v_name, v_phone, v_org, 'Web form', null, f.is_sample);
  if v_person is null and v_org is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers'; end if;
  if v_person is not null and (v_title is not null or c_person <> '{}'::jsonb) then
    update app.people set title = coalesce(title, v_title), custom = c_person || custom, version = version + 1, updated_at = now() where id = v_person;
  end if;
  if v_org is not null and c_org <> '{}'::jsonb then
    update app.organizations set custom = c_org || custom, version = version + 1, updated_at = now() where id = v_org;
  end if;

  -- files of a file-upload form: paths in the private form-uploads bucket, written by the edge function
  if f.kind = 'file_upload' and jsonb_typeof(m -> 'files') = 'array' then
    select coalesce(jsonb_agg(jsonb_build_object('path', x ->> 'path', 'name', left(x ->> 'name', 200), 'size', (x ->> 'size')::bigint)), '[]'::jsonb) into v_files
    from (select x from jsonb_array_elements(m -> 'files') x limit 10) q
    where jsonb_typeof(x) = 'object' and (x ->> 'path') ~ '^form-uploads/[A-Za-z0-9/_.-]{1,300}$' and (x ->> 'path') not like '%..%'
      and (x ->> 'size') ~ '^\d{1,8}$' and (x ->> 'size')::bigint <= 26214400;
  end if;

  -- tracking only while form_tracking is on: UTM, referrer host, landing path and declared page variables (Q7)
  if app.setting('form_tracking') = 'on' and jsonb_typeof(m -> 'tracking') = 'object' then
    v_tracking := jsonb_strip_nulls(jsonb_build_object(
      'utm', case when jsonb_typeof(m #> '{tracking,utm}') = 'object' then
               (select nullif(coalesce(jsonb_object_agg(e.key, left(e.value, 120)), '{}'::jsonb), '{}'::jsonb) from jsonb_each_text(m #> '{tracking,utm}') e
                where e.key in ('utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content')) end,
      'referrer_host', case when (m #>> '{tracking,referrer_host}') ~ '^[a-z0-9.-]{1,200}$' then m #>> '{tracking,referrer_host}' end,
      'landing_path', case when (m #>> '{tracking,landing_path}') ~ '^/' then left(m #>> '{tracking,landing_path}', 500) end,
      'page_vars', case when jsonb_typeof(m #> '{tracking,page_vars}') = 'object' then
                     (select nullif(coalesce(jsonb_object_agg(e.key, left(e.value, 120)), '{}'::jsonb), '{}'::jsonb)
                      from (select * from jsonb_each_text(m #> '{tracking,page_vars}') limit 20) e where e.key ~ '^[a-z][a-z0-9_]{0,40}$') end));
  end if;

  insert into app.form_submissions (form_id, form_version, state, field_values, fingerprint, tracking, person_id, organization_id, files, consent, is_sample)
  values (f.id, f.current_version, 'accepted', vals, v_fp, v_tracking, v_person, v_org, v_files, jsonb_build_object('given', v_consent), f.is_sample)
  returning id into v_sub;

  -- consent (step 4): only when the box was ticked; with double opt-in the status stays pending until the link is confirmed
  if v_consent and v_person is not null and v_email is not null then
    select * into v_text from app.consent_texts where key = d #>> '{consent,text_key}' and locale = f.language and id::text = m ->> 'consent_text_id';
    if v_text.id is null then
      select * into v_text from app.consent_texts where key = d #>> '{consent,text_key}' and locale = f.language order by version desc limit 1;
    end if;
    v_doi := app.setting('double_opt_in') = 'on' or (d #> '{consent,double_opt_in}') = 'true'::jsonb;
    v_status := (select marketing_status from app.people where id = v_person);
    if v_status <> 'subscribed' then
      if v_doi then
        perform app.consent_write(v_person, 'pending', 'Web form', 'consent', 'form_submission', v_sub, v_text.id, null, 'capture');
        v_token := app.token() || app.token();
        insert into app.consent_confirmations (token_sha256, person_id, email_sha256, submission_id, text_id, expires_at)
        values (app.token_hash(v_token), v_person, app.email_hash(v_email), v_sub, v_text.id, now() + interval '7 days');
        v_status := 'pending';
      else
        perform app.consent_write(v_person, 'subscribed', 'Web form', 'consent', 'form_submission', v_sub, v_text.id, null, 'capture');
        v_status := 'subscribed';
      end if;
    end if;
    update app.form_submissions set consent = jsonb_build_object('given', true, 'text_id', v_text.id, 'text_version', v_text.version, 'double_opt_in', v_doi, 'status', v_status)
    where id = v_sub;
  end if;

  -- the lead or the deal (step 5). A resubmission updates the open lead from the same form for the same person, owner kept.
  if a ->> 'creates' = 'deal' then
    v_deal := app.capture_deal(f.name || ' · ' || coalesce(v_org_name, v_name, v_email, v_org_nr), v_person, v_org, 'Web form', null,
                               (a ->> 'pipeline_id')::uuid, (a ->> 'stage_id')::uuid, f.is_sample);
  else
    if v_person is not null then
      select s2.lead_id into v_lead from app.form_submissions s2 join app.leads l on l.id = s2.lead_id
      where s2.form_id = f.id and s2.person_id = v_person and s2.id <> v_sub and l.deleted_at is null and l.archived_at is null and l.converted_deal_id is null
      order by s2.created_at desc limit 1;
    end if;
    if v_lead is not null then
      update app.leads set form_data = vals, custom = custom || c_lead, version = version + 1, updated_at = now() where id = v_lead;
      insert into app.changelog (entity, record_id, field, new_value, source) values ('lead', v_lead, '*resubmitted', jsonb_build_object('submission', v_sub), 'capture');
      perform app.emit('lead.updated', 'lead', v_lead, jsonb_build_object('fields', jsonb_build_array('form_data')), f.is_sample);
    else
      v_lead := app.capture_lead(f.name || ' · ' || coalesce(v_name, v_org_name, v_email, v_org_nr), v_person, v_org, 'Web form', null, vals, f.is_sample);
      if c_lead <> '{}'::jsonb then update app.leads set custom = c_lead where id = v_lead; end if;
    end if;
  end if;

  -- the ticket in Sales (step 6), on the path the products' contact.submitted also takes
  if coalesce((a ->> 'ticket')::boolean, false) then
    v_ticket := app.ticket_from_capture('sales', f.name, v_email, v_org, v_message, 'contact_form', v_sub, null, '{}'::jsonb, null, v_person, f.is_sample);
    if v_lead is not null then insert into app.ticket_links (ticket_id, kind, ref) values (v_ticket, 'lead', v_lead::text) on conflict do nothing; end if;
    if v_deal is not null then insert into app.ticket_links (ticket_id, kind, ref) values (v_ticket, 'deal', v_deal::text) on conflict do nothing; end if;
  end if;
  update app.form_submissions set lead_id = v_lead, deal_id = v_deal, ticket_id = v_ticket where id = v_sub;

  -- the sequence (SF-05): only an active one; a sequence that cannot start never loses the submission
  if v_lead is not null and (a ->> 'sequence_id') is not null then
    begin
      perform app.seq_enroll((a ->> 'sequence_id')::uuid, 'lead', v_lead, 'form', null);
    exception when others then
      perform app.log('form.sequence_skipped', 'form', f.id::text, jsonb_build_object('submission', v_sub));
    end;
  end if;

  insert into app.form_stats_daily (form_id, day, submissions) values (f.id, v_day, 1)
  on conflict (form_id, day) do update set submissions = app.form_stats_daily.submissions + 1;
  perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'accepted'));
  perform app.emit('form.submitted', case when v_deal is not null then 'deal' else 'lead' end, coalesce(v_deal, v_lead),
                   jsonb_strip_nulls(jsonb_build_object('form', f.id, 'submission', v_sub, 'person', v_person, 'organization', v_org, 'ticket', v_ticket)), f.is_sample);
  -- the confirmation link goes out by the email provider from the edge function; only its hash is stored here
  return jsonb_strip_nulls(jsonb_build_object('ok', true, 'thank_you', a ->> 'thank_you', 'redirect_url', a ->> 'redirect_url', 'asset_path', a ->> 'asset_path',
                                              'confirm_token', v_token, 'email_connected', case when v_token is not null then app.connected('email') end));
end $fn$;

-- ---------------------------------------------------------------------------
-- chat playbooks (LGN-01): a theme, a profile and a template with its steps; publishing freezes a version
create function app.chat_steps_check(p_steps jsonb) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
declare x jsonb; i int := 0; v_keys text[] := '{}'; out jsonb := '[]'::jsonb;
begin
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) > 30 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps';
  end if;
  for x in select * from jsonb_array_elements(p_steps) loop
    i := i + 1;
    if jsonb_typeof(x) <> 'object' or coalesce(x ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,40}$' or (x ->> 'key') = any (v_keys)
       or coalesce(x ->> 'kind', '') not in ('message', 'question', 'handoff')
       or coalesce(btrim(x ->> 'text'), '') = '' or char_length(x ->> 'text') > 1000
       or ((x ->> 'map') is not null and (x ->> 'kind' <> 'question'
           or (x ->> 'map') not in ('person.name', 'person.email', 'person.phone', 'organization.name', 'organization.org_number'))) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i;
    end if;
    v_keys := v_keys || (x ->> 'key');
    out := out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('key', x ->> 'key', 'kind', x ->> 'kind', 'text', btrim(x ->> 'text'), 'map', x ->> 'map')));
  end loop;
  return out;
end $fn$;

create function app.playbook_row(p app.chat_playbooks) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select to_jsonb(p) - 'custom' - 'labels' || jsonb_build_object(
    'owner', (select jsonb_build_object('id', a.id, 'name', a.name) from app.admins a where a.id = p.owner_id),
    'conversations_30d', (select count(*) from app.chat_conversations c where c.playbook_id = p.id and c.started_at > now() - interval '30 days'),
    'completed_30d', (select count(*) from app.chat_conversations c where c.playbook_id = p.id and c.completed and c.started_at > now() - interval '30 days'))
$fn$;

create function public.playbooks_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('leadgen');
  select coalesce(jsonb_agg(app.playbook_row(p) order by p.updated_at desc), '[]'::jsonb) into v_rows
  from app.chat_playbooks p where p.deleted_at is null and app.visible(p.owner_id, p.visibility) and (v_sandbox or not p.is_sample);
  perform app.log('record.listed', 'chat_playbook', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

create function public.playbook_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.chat_playbooks;
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('leadgen');
  select * into p from app.chat_playbooks where id = p_id and deleted_at is null;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('record.read', 'chat_playbook', p_id::text);
  return app.playbook_row(p) || jsonb_build_object(
    'published', (select v.definition from app.chat_playbook_versions v where v.playbook_id = p.id and v.version = p.current_version),
    'embed', (select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname,
                     'snippet', format('<script async src="https://go.owntheagenda.com/w.js" data-site="%s"></script>', s.key)) order by s.hostname), '[]'::jsonb)
              from app.web_sites s where s.active and s.chat_enabled and (cardinality(p.site_ids) = 0 or s.id = any (p.site_ids))),
    'widget_consent', app.setting('widget_consent'));
end $fn$;

create function public.playbook_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add'); p app.chat_playbooks; v jsonb := coalesce(p_values, '{}'::jsonb); k text; v_id uuid; v_version int;
begin
  perform app.require_module('leadgen');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('name', 'template', 'site_ids', 'pages', 'theme', 'profile', 'steps', 'creates', 'pipeline_id', 'stage_id', 'booking_link_id',
                 'queue_wait_seconds', 'offline_message') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if (v ? 'name' or p_id is null) and (coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 120) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end if;
  if v ? 'template' and coalesce(v ->> 'template', '') not in ('leads', 'meetings', 'qualify_route', 'live_chat') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'template';
  end if;
  if v ? 'creates' and coalesce(v ->> 'creates', '') not in ('lead', 'deal') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'creates'; end if;
  if v ? 'queue_wait_seconds' and (jsonb_typeof(v -> 'queue_wait_seconds') <> 'number' or (v ->> 'queue_wait_seconds')::numeric not between 10 and 900) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'queue_wait_seconds';
  end if;
  if v ? 'offline_message' and char_length(coalesce(v ->> 'offline_message', '')) > 500 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'offline_message';
  end if;
  if p_id is null then
    insert into app.chat_playbooks (name, template, owner_id, visibility, created_by, updated_by, is_sample)
    values (left(btrim(v ->> 'name'), 120), coalesce(v ->> 'template', 'leads'), v_me, app.setting('visibility_default', 'chat_playbook'), v_me, v_me,
            (select sandbox from app.admins where id = v_me))
    returning * into p;
    insert into app.changelog (entity, record_id, field, actor_id, source) values ('chat_playbook', p.id, '*created', v_me, 'ui');
  else
    select * into p from app.chat_playbooks where id = p_id and deleted_at is null for update;
    if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
    if p.owner_id is distinct from v_me and not app.can('campaigns', 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
    end if;
  end if;
  if v ? 'site_ids' and (jsonb_typeof(v -> 'site_ids') <> 'array'
      or exists (select 1 from jsonb_array_elements_text(v -> 'site_ids') x where not exists (select 1 from app.web_sites s where s.id::text = x))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'site_ids';
  end if;
  if v ? 'pages' and (jsonb_typeof(v -> 'pages') <> 'array' or jsonb_array_length(v -> 'pages') > 50
      or exists (select 1 from jsonb_array_elements(v -> 'pages') x where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^/[A-Za-z0-9/_.~%-]{0,199}\*?$')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pages';
  end if;
  if v ? 'theme' and (jsonb_typeof(v -> 'theme') <> 'object' or char_length((v -> 'theme')::text) > 2000) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'theme';
  end if;
  if v ? 'profile' and (jsonb_typeof(v -> 'profile') <> 'object' or char_length((v -> 'profile')::text) > 2000
      or coalesce(v #>> '{profile,language}', 'nb') not in ('nb', 'nn', 'en', 'sv')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'profile';
  end if;
  if v ? 'stage_id' and (v ->> 'stage_id') is not null
     and not exists (select 1 from app.stages s where s.id::text = v ->> 'stage_id' and s.pipeline_id::text = coalesce(v ->> 'pipeline_id', p.pipeline_id::text)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage_id';
  end if;
  begin
    update app.chat_playbooks t set
      name = case when v ? 'name' then left(btrim(v ->> 'name'), 120) else t.name end,
      template = case when v ? 'template' then v ->> 'template' else t.template end,
      site_ids = case when v ? 'site_ids' then array(select jsonb_array_elements_text(v -> 'site_ids'))::uuid[] else t.site_ids end,
      pages = case when v ? 'pages' then array(select jsonb_array_elements_text(v -> 'pages')) else t.pages end,
      theme = case when v ? 'theme' then v -> 'theme' else t.theme end,
      profile = case when v ? 'profile' then v -> 'profile' else t.profile end,
      steps = case when v ? 'steps' then app.chat_steps_check(v -> 'steps') else t.steps end,
      creates = case when v ? 'creates' then v ->> 'creates' else t.creates end,
      pipeline_id = case when v ? 'pipeline_id' then (v ->> 'pipeline_id')::uuid else t.pipeline_id end,
      stage_id = case when v ? 'stage_id' then (v ->> 'stage_id')::uuid else t.stage_id end,
      booking_link_id = case when v ? 'booking_link_id' then (v ->> 'booking_link_id')::uuid else t.booking_link_id end,
      queue_wait_seconds = case when v ? 'queue_wait_seconds' then (v ->> 'queue_wait_seconds')::int else t.queue_wait_seconds end,
      offline_message = case when v ? 'offline_message' then nullif(btrim(v ->> 'offline_message'), '') else t.offline_message end,
      version = t.version + case when p_id is null then 0 else 1 end, updated_at = now(), updated_by = v_me
    where t.id = p.id returning t.id, t.version into v_id, v_version;
  exception when check_violation or foreign_key_violation or invalid_text_representation or not_null_violation then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end;
  if p_id is not null then
    insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
    values ('chat_playbook', v_id, '*updated', to_jsonb(array(select jsonb_object_keys(v))), v_me, 'ui');
  end if;
  perform app.log(case when p_id is null then 'record.created' else 'record.updated' end, 'chat_playbook', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v)))));
  return jsonb_build_object('id', v_id, 'version', v_version);
end $fn$;

create function public.playbook_publish(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); p app.chat_playbooks;
begin
  perform app.require_module('leadgen');
  select * into p from app.chat_playbooks where id = p_id and deleted_at is null for update;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p.template <> 'live_chat' and jsonb_array_length(p.steps) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps'; end if;
  insert into app.chat_playbook_versions (playbook_id, version, definition, published_by)
  values (p_id, p.current_version + 1, jsonb_build_object('template', p.template, 'steps', p.steps, 'creates', p.creates, 'pipeline_id', p.pipeline_id,
                                                          'stage_id', p.stage_id, 'booking_link_id', p.booking_link_id, 'queue_wait_seconds', p.queue_wait_seconds,
                                                          'offline_message', p.offline_message, 'theme', p.theme, 'profile', p.profile, 'pages', to_jsonb(p.pages),
                                                          'site_ids', to_jsonb(p.site_ids)), v_me);
  update app.chat_playbooks set current_version = p.current_version + 1, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('chat_playbook', p_id, '*published', to_jsonb(p.current_version), to_jsonb(p.current_version + 1), v_me, 'ui');
  perform app.log('chat_playbook.published', 'chat_playbook', p_id::text, jsonb_build_object('version', p.current_version + 1));
  return jsonb_build_object('id', p_id, 'current_version', p.current_version + 1);
end $fn$;

create function public.playbook_set_state(p_id uuid, p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); p app.chat_playbooks;
begin
  perform app.require_module('leadgen');
  if p_state is null or p_state not in ('draft', 'live') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into p from app.chat_playbooks where id = p_id and deleted_at is null for update;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_state = 'live' and p.current_version = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'unpublished'; end if;
  update app.chat_playbooks set state = p_state, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('chat_playbook', p_id, 'state', to_jsonb(p.state), to_jsonb(p_state), v_me, 'ui');
  perform app.log('chat_playbook.state_set', 'chat_playbook', p_id::text, jsonb_build_object('state', p_state));
  return jsonb_build_object('id', p_id, 'state', p_state);
end $fn$;

-- per-step drop-off (LGN-01): conversations that stopped at each step without completing
create function public.playbook_stats(p_id uuid, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare p app.chat_playbooks; v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 365));
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('leadgen');
  select * into p from app.chat_playbooks where id = p_id and deleted_at is null;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object(
    'conversations', (select count(*) from app.chat_conversations c where c.playbook_id = p_id and c.started_at >= v_from),
    'completed', (select count(*) from app.chat_conversations c where c.playbook_id = p_id and c.started_at >= v_from and c.completed),
    'live', (select count(*) from app.chat_conversations c where c.playbook_id = p_id and c.started_at >= v_from and c.claimed_by is not null),
    'drop_off', (select coalesce(jsonb_agg(jsonb_build_object('step', x.k, 'n', x.n) order by x.n desc), '[]'::jsonb)
                 from (select c.last_step_key k, count(*) n from app.chat_conversations c
                       where c.playbook_id = p_id and c.started_at >= v_from and not c.completed and c.last_step_key is not null group by 1) x));
end $fn$;

-- ---------------------------------------------------------------------------
-- the bot: post the steps after the current one until a question, a hand-off or the end
create function app.chat_complete(p_conv uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c app.chat_conversations; d jsonb; v_email text; v_name text; v_phone text; v_org_nr text; v_org_name text; x jsonb;
  v_org uuid; v_person uuid; v_lead uuid; v_deal uuid; v_title text;
begin
  select * into c from app.chat_conversations where id = p_conv for update;
  select definition into d from app.chat_playbook_versions where playbook_id = c.playbook_id and version = c.playbook_version;
  for x in select * from jsonb_array_elements(coalesce(d -> 'steps', '[]'::jsonb)) loop
    continue when (x ->> 'map') is null or not (c.collected ? (x ->> 'key'));
    case x ->> 'map'
      when 'person.email' then v_email := lower(btrim(c.collected ->> (x ->> 'key')));
      when 'person.name' then v_name := c.collected ->> (x ->> 'key');
      when 'person.phone' then v_phone := c.collected ->> (x ->> 'key');
      when 'organization.org_number' then v_org_nr := regexp_replace(c.collected ->> (x ->> 'key'), '\D', '', 'g');
      when 'organization.name' then v_org_name := c.collected ->> (x ->> 'key');
      else null;
    end case;
  end loop;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
  if v_org_nr !~ '^\d{9}$' then v_org_nr := null; end if;
  v_org := app.capture_org(v_org_nr, v_org_name, 'Chatbot', null, c.is_sample);
  -- the company the visit was identified as names the organization only when the CRM already has it
  if v_org is null and c.company_org_number is not null then
    select id into v_org from app.organizations where org_number = c.company_org_number and deleted_at is null and is_sample = c.is_sample order by created_at limit 1;
  end if;
  v_person := app.capture_person(v_email, case when v_email is not null then v_name end, v_phone, v_org, 'Chatbot', null, c.is_sample);
  v_title := left(coalesce((select name from app.chat_playbooks where id = c.playbook_id), 'Chat') || ' · ' || coalesce(v_name, v_org_name, v_email, v_org_nr, c.page_path, ''), 200);
  if v_person is not null or v_org is not null then
    if d ->> 'creates' = 'deal' then
      v_deal := app.capture_deal(v_title, v_person, v_org, 'Chatbot', null, (d ->> 'pipeline_id')::uuid, (d ->> 'stage_id')::uuid, c.is_sample);
    else
      v_lead := app.capture_lead(v_title, v_person, v_org, 'Chatbot', null, c.collected, c.is_sample);
    end if;
  end if;
  update app.chat_conversations set completed = true, person_id = coalesce(person_id, v_person), lead_id = coalesce(lead_id, v_lead), deal_id = coalesce(deal_id, v_deal)
  where id = p_conv;
  perform app.log('chat.completed', 'chat', p_conv::text, jsonb_build_object('lead', v_lead, 'deal', v_deal));
  if v_lead is not null or v_deal is not null then
    perform app.emit('chat.completed', case when v_deal is not null then 'deal' else 'lead' end, coalesce(v_deal, v_lead),
                     jsonb_build_object('conversation', p_conv, 'playbook', c.playbook_id), c.is_sample);
  end if;
end $fn$;

create function app.chat_advance(p_conv uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.chat_conversations; v_steps jsonb; st jsonb; i int := 0; n int;
begin
  select * into c from app.chat_conversations where id = p_conv for update;
  select coalesce(v.definition -> 'steps', '[]'::jsonb) into v_steps from app.chat_playbook_versions v where v.playbook_id = c.playbook_id and v.version = c.playbook_version;
  v_steps := coalesce(v_steps, '[]'::jsonb);
  n := jsonb_array_length(v_steps);
  if c.last_step_key is not null then
    i := coalesce((select e.o::int from jsonb_array_elements(v_steps) with ordinality e(x, o) where e.x ->> 'key' = c.last_step_key), n);
  end if;
  while i < n loop
    st := v_steps -> i;
    insert into app.chat_messages (conversation_id, sender, body) values (p_conv, 'bot', st ->> 'text');
    if st ->> 'kind' = 'handoff' then
      update app.chat_conversations set last_step_key = st ->> 'key', state = 'queued', queued_at = now() where id = p_conv;
      return;
    end if;
    update app.chat_conversations set last_step_key = st ->> 'key' where id = p_conv;
    if st ->> 'kind' = 'question' then return; end if;
    i := i + 1;
  end loop;
  if not c.completed then perform app.chat_complete(p_conv); end if;
end $fn$;

-- a queued chat that nobody claimed in the playbook's wait returns to the bot, with the offline message (SF-30)
create function app.chat_fallback() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  for r in select c.id, nullif(v.definition ->> 'offline_message', '') om from app.chat_conversations c
           left join app.chat_playbook_versions v on v.playbook_id = c.playbook_id and v.version = c.playbook_version
           where c.state = 'queued' and c.queued_at < now() - make_interval(secs => coalesce((v.definition ->> 'queue_wait_seconds')::int, 60))
           for update of c skip locked loop
    update app.chat_conversations set state = 'bot', queued_at = null where id = r.id;
    if r.om is not null then insert into app.chat_messages (conversation_id, sender, body) values (r.id, 'system', left(r.om, 4000)); end if;
    n := n + 1;
  end loop;
  -- presence that ran out is gone
  delete from app.chat_presence where online_until < now() - interval '1 day';
  return n;
end $fn$;
select cron.schedule('platform-chat-fallback', '* * * * *', 'select app.chat_fallback()');

-- ---------------------------------------------------------------------------
-- live chat for staff (LGN-02): Sales handles chats (deals scope, Q21); polling every few seconds (Q10)
create function app.chat_visible(c app.chat_conversations) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select (c.lead_id is null or exists (select 1 from app.leads l where l.id = c.lead_id and app.visible(l.owner_id, l.visibility)))
     and (c.deal_id is null or exists (select 1 from app.deals d where d.id = c.deal_id and app.visible(d.owner_id, d.visibility)))
$fn$;

create function app.chat_row(c app.chat_conversations) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', c.id, 'state', c.state, 'page_path', c.page_path, 'started_at', c.started_at, 'queued_at', c.queued_at,
    'completed', c.completed, 'last_step_key', c.last_step_key, 'lead_id', c.lead_id, 'deal_id', c.deal_id, 'person_id', c.person_id, 'language', c.language,
    'playbook', (select jsonb_build_object('id', p.id, 'name', p.name, 'template', p.template) from app.chat_playbooks p where p.id = c.playbook_id),
    'site', (select s.hostname from app.web_sites s where s.id = c.site_id),
    'company', case when c.company_org_number is not null then jsonb_build_object('org_number', c.company_org_number,
                 'name', coalesce((select o.name from app.organizations o where o.org_number = c.company_org_number and o.deleted_at is null and not o.is_sample limit 1),
                                  (select w.name from app.web_companies w where w.org_number = c.company_org_number)),
                 -- the company's sessions in the last 30 days: «3rd visit» counts the company's visits, not a visitor's (Q23, D-37)
                 'visits_30d', (select count(*) from app.web_sessions ws where ws.company_org_number = c.company_org_number and ws.day > current_date - 30)) end,
    'claimed_by', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = c.claimed_by),
    'messages', (select count(*) from app.chat_messages m where m.conversation_id = c.id),
    'last_message_at', (select max(m.at) from app.chat_messages m where m.conversation_id = c.id))
$fn$;

create function public.chats_queue() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('leadgen');
  select coalesce(jsonb_agg(app.chat_row(c) order by (c.state = 'queued') desc, c.started_at desc), '[]'::jsonb) into v_rows
  from app.chat_conversations c
  where c.state <> 'closed' and (c.state in ('queued', 'live') or c.started_at > now() - interval '24 hours') and app.chat_visible(c) and (v_sandbox or not c.is_sample);
  perform app.log('record.listed', 'chat', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows,
    'online', exists (select 1 from app.chat_presence where staff_id = v_me and online_until > now()),
    'staff_online', (select count(*) from app.chat_presence where online_until > now()));
end $fn$;

create function public.chat_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); c app.chat_conversations;
begin
  perform app.require_module('leadgen');
  select * into c from app.chat_conversations where id = p_id;
  if not found or not app.chat_visible(c) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('record.read', 'chat', p_id::text);
  return app.chat_row(c) || jsonb_build_object(
    'collected', c.collected,
    'read_only', c.claimed_by is not null and c.claimed_by <> v_me,
    'transcript', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'sender', m.sender, 'body', m.body, 'at', m.at,
                                                                'staff', (select a.name from app.admins a where a.id = m.staff_id)) order by m.id), '[]'::jsonb)
                   from app.chat_messages m where m.conversation_id = c.id));
end $fn$;

-- the first claim wins and locks the chat to one rep
create function public.chat_claim(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); c app.chat_conversations;
begin
  perform app.require_module('leadgen');
  select * into c from app.chat_conversations where id = p_id;
  if not found or not app.chat_visible(c) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.chat_conversations set state = 'live', claimed_by = v_me, claimed_at = now()
  where id = p_id and claimed_by is null and state in ('bot', 'queued') returning * into c;
  if not found then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = case when (select state from app.chat_conversations where id = p_id) = 'closed' then 'closed' else 'claimed' end;
  end if;
  perform app.log('chat.claimed', 'chat', p_id::text);
  if coalesce(c.lead_id, c.deal_id) is not null then
    perform app.emit('chat.claimed', case when c.deal_id is not null then 'deal' else 'lead' end, coalesce(c.deal_id, c.lead_id),
                     jsonb_build_object('conversation', p_id, 'playbook', c.playbook_id), c.is_sample);
  end if;
  return jsonb_build_object('id', p_id, 'state', 'live');
end $fn$;

create function public.chat_send(p_id uuid, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); c app.chat_conversations; v_msg bigint;
begin
  perform app.require_module('leadgen');
  select * into c from app.chat_conversations where id = p_id;
  if not found or not app.chat_visible(c) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.state <> 'live' or c.claimed_by is distinct from v_me then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = case when c.state = 'live' then 'claimed' else 'state' end;
  end if;
  if coalesce(btrim(p_body), '') = '' or char_length(btrim(p_body)) > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  insert into app.chat_messages (conversation_id, sender, staff_id, body) values (p_id, 'staff', v_me, btrim(p_body)) returning id into v_msg;
  perform app.log('chat.sent', 'chat', p_id::text, jsonb_build_object('message', v_msg));
  return jsonb_build_object('id', v_msg);
end $fn$;

-- closing a live chat saves it on a lead when the visitor left an address or the company is known (LGN-02)
create function public.chat_close(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); c app.chat_conversations; v_person uuid; v_org uuid; v_lead uuid; v_email text;
begin
  perform app.require_module('leadgen');
  select * into c from app.chat_conversations where id = p_id for update;
  if not found or not app.chat_visible(c) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.state = 'closed' then return jsonb_build_object('id', p_id, 'state', 'closed'); end if;
  if c.claimed_by is distinct from v_me and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  if c.claimed_by is not null and c.lead_id is null and c.deal_id is null then
    -- the address the visitor gave: an answer, else the first address they wrote in the chat
    select lower(btrim(value)) into v_email from jsonb_each_text(c.collected) where value ~ '^\s*[^@\s]+@[^@\s]+\.[^@\s]+\s*$' limit 1;
    if v_email is null then
      select lower(substring(m.body from '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) into v_email from app.chat_messages m
      where m.conversation_id = c.id and m.sender = 'visitor' and m.body ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' order by m.id limit 1;
    end if;
    select id into v_org from app.organizations where org_number = c.company_org_number and deleted_at is null and is_sample = c.is_sample order by created_at limit 1;
    v_person := coalesce(c.person_id, app.capture_person(v_email, null, null, v_org, 'Live chat', c.claimed_by, c.is_sample));
    if v_person is not null or v_org is not null then
      v_lead := app.capture_lead(coalesce((select name from app.chat_playbooks where id = c.playbook_id), 'Live chat') || ' · ' || coalesce(c.page_path, ''),
                                 v_person, v_org, 'Live chat', c.claimed_by, c.collected, c.is_sample);
    end if;
  end if;
  update app.chat_conversations set state = 'closed', closed_at = now(), person_id = coalesce(person_id, v_person), lead_id = coalesce(lead_id, v_lead) where id = p_id;
  perform app.log('chat.closed', 'chat', p_id::text, jsonb_build_object('lead', v_lead));
  return jsonb_build_object('id', p_id, 'state', 'closed', 'lead_id', coalesce(c.lead_id, v_lead));
end $fn$;

create function public.chat_presence_set(p_online boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  if coalesce(p_online, false) then
    insert into app.chat_presence (staff_id, online_until) values (v_me, now() + interval '2 minutes')
    on conflict (staff_id) do update set online_until = excluded.online_until;
  else
    delete from app.chat_presence where staff_id = v_me;
  end if;
  return jsonb_build_object('online', coalesce(p_online, false));
end $fn$;

-- ---------------------------------------------------------------------------
-- the visitor's side, through the public edge function (D-28). The token is returned once; only its hash is kept.
create function public.worker_chat_start(p_site_key text, p_page text, p_org_number text default null, p_language text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  s app.web_sites; p app.chat_playbooks; d jsonb; v_token text; v_id uuid; v_org text;
  v_page text := case when p_page ~ '^/' then left(p_page, 500) else '/' end;
begin
  select * into s from app.web_sites where key = p_site_key and active and chat_enabled;
  if not found or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into p from app.chat_playbooks pb
  where pb.state = 'live' and pb.deleted_at is null and pb.current_version > 0 and (cardinality(pb.site_ids) = 0 or s.id = any (pb.site_ids))
    and (cardinality(pb.pages) = 0 or exists (select 1 from unnest(pb.pages) pt
                                              where v_page = pt or (right(pt, 1) = '*' and left(v_page, char_length(pt) - 1) = left(pt, char_length(pt) - 1))))
  order by pb.created_at limit 1;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'playbook'; end if;
  select definition into d from app.chat_playbook_versions where playbook_id = p.id and version = p.current_version;
  -- the company, resolved from the IP in memory at the edge; never with identification off, never an ENK (Q16)
  v_org := case when app.setting('web_ident') = 'on' and p_org_number ~ '^\d{9}$'
                     and not exists (select 1 from app.web_companies w where w.org_number = p_org_number and w.excluded) then p_org_number end;
  v_token := app.token() || app.token();
  insert into app.chat_conversations (playbook_id, playbook_version, site_id, page_path, company_org_number, visitor_token_sha256, language, is_sample)
  values (p.id, p.current_version, s.id, v_page, v_org, app.token_hash(v_token),
          case when p_language in ('nb', 'nn', 'en', 'sv') then p_language when (d #>> '{profile,language}') in ('nb', 'nn', 'en', 'sv') then d #>> '{profile,language}' end,
          p.is_sample)
  returning id into v_id;
  if d ->> 'template' = 'live_chat' and jsonb_array_length(coalesce(d -> 'steps', '[]'::jsonb)) = 0 then
    update app.chat_conversations set state = 'queued', queued_at = now() where id = v_id;
  else
    perform app.chat_advance(v_id);
  end if;
  perform app.log('chat.started', 'chat', v_id::text, jsonb_build_object('playbook', p.id));
  return jsonb_build_object('token', v_token, 'theme', d -> 'theme', 'profile', d -> 'profile') || public.worker_chat_poll(v_token, 0);
end $fn$;

create function public.worker_chat_poll(p_token text, p_since bigint default 0) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.chat_conversations;
begin
  select * into c from app.chat_conversations where visitor_token_sha256 = app.token_hash(p_token);
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('state', c.state,
    'rep', (select split_part(a.name, ' ', 1) from app.admins a where a.id = c.claimed_by and c.state = 'live'),
    'online', exists (select 1 from app.chat_presence where online_until > now()),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'sender', m.sender, 'body', m.body, 'at', m.at,
                                                              'staff', (select split_part(a.name, ' ', 1) from app.admins a where a.id = m.staff_id)) order by m.id), '[]'::jsonb)
                 from (select * from app.chat_messages where conversation_id = c.id and id > coalesce(p_since, 0) order by id limit 200) m));
end $fn$;

create function public.worker_chat_message(p_token text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.chat_conversations; v_msg bigint; v_step jsonb; v_body text := left(btrim(coalesce(p_body, '')), 4000);
begin
  select * into c from app.chat_conversations where visitor_token_sha256 = app.token_hash(p_token) for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if c.state = 'closed' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'closed'; end if;
  if v_body = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  insert into app.chat_messages (conversation_id, sender, body) values (c.id, 'visitor', v_body) returning id into v_msg;
  if c.state = 'bot' and not c.completed and c.last_step_key is not null then
    select x into v_step from app.chat_playbook_versions v, jsonb_array_elements(v.definition -> 'steps') x
    where v.playbook_id = c.playbook_id and v.version = c.playbook_version and x ->> 'key' = c.last_step_key;
    if v_step ->> 'kind' = 'question' then
      update app.chat_conversations set collected = collected || jsonb_build_object(v_step ->> 'key', left(v_body, 1000)) where id = c.id;
      perform app.chat_advance(c.id);
    end if;
  end if;
  return public.worker_chat_poll(p_token, v_msg);
end $fn$;

-- ---------------------------------------------------------------------------
-- prospect search (LGN-04). The provider (contact_data) is called by an edge adapter; results are never stored
-- until revealed. A revealed person carries the GDPR art. 14 duty (Q20): the result says so.
create function public.prospect_search(p_filters jsonb, p_page int default 1) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  perform app.require_module('leadgen');
  if p_filters is null or jsonb_typeof(p_filters) <> 'object' or char_length(p_filters::text) > 4000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filters';
  end if;
  perform app.require_connected('contact_data');
  perform app.log('prospect.searched', 'prospect', null, jsonb_build_object('filters', to_jsonb(array(select jsonb_object_keys(p_filters))), 'page', greatest(coalesce(p_page, 1), 1)));
  -- the adapter runs the query; the database holds no result
  return jsonb_build_object('provider', 'contact_data', 'page', greatest(coalesce(p_page, 1), 1));
end $fn$;

create function public.prospect_reveal(p_provider_ref text, p_basis text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); r app.prospect_reveals; v_limit numeric; v_used bigint;
begin
  perform app.require_module('leadgen');
  if coalesce(btrim(p_provider_ref), '') = '' or char_length(btrim(p_provider_ref)) > 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider_ref';
  end if;
  -- the contact rule first: opt-in only means a bought contact may never be added; source and basis needs a basis
  if app.setting('contact_rule') = 'opt_in_only' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'contact_rule'; end if;
  if app.setting('contact_rule') = 'source_and_basis' and coalesce(btrim(p_basis), '') = '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'basis:required';
  end if;
  perform app.require_connected('contact_data');
  -- a repeat reveal of the same reference costs nothing
  select * into r from app.prospect_reveals where provider = 'contact_data' and provider_ref = btrim(p_provider_ref);
  if found then
    return jsonb_build_object('reveal', r.id, 'state', r.state, 'lead_id', r.lead_id, 'repeat', true, 'notice', 'art14');
  end if;
  -- credits: unlimited unless count_limits sets a number (D-16, D-17); the limit holds at the moment of the reveal (ENT-02)
  v_limit := app.count_limit();
  if v_limit is not null then
    select coalesce(-sum(delta), 0) into v_used from app.credit_ledger where at >= date_trunc('month', now()) and delta < 0;
    if v_used + 1 > v_limit then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'credits'; end if;
  end if;
  insert into app.prospect_reveals (provider_ref, basis, revealed_by) values (btrim(p_provider_ref), nullif(btrim(p_basis), ''), v_me) returning * into r;
  perform pgmq.send('jobs', jsonb_build_object('job', 'prospect_reveal', 'reveal_id', r.id));
  perform app.log('prospect.reveal_requested', 'prospect', r.id::text);
  return jsonb_build_object('reveal', r.id, 'state', r.state, 'repeat', false, 'notice', 'art14');
end $fn$;

create function public.prospect_usage() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  perform app.require_module('leadgen');
  return jsonb_build_object(
    'connected', app.connected('contact_data'),
    'contact_rule', app.setting('contact_rule'),
    'used_month', (select coalesce(-sum(delta), 0) from app.credit_ledger where at >= date_trunc('month', now()) and delta < 0),
    'limit', app.count_limit(),
    'revealed_month', (select count(*) from app.prospect_reveals where state = 'revealed' and revealed_at >= date_trunc('month', now())));
end $fn$;

-- the adapter reports the revealed contact: {name, email, phone, title, organization: {name, org_number}} or {error}
create function public.worker_prospect_revealed(p_reveal uuid, p_contact jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.prospect_reveals; v_org uuid; v_person uuid; v_lead uuid; v_email text;
begin
  select * into r from app.prospect_reveals where id = p_reveal for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'requested' then return jsonb_build_object('reveal', r.id, 'state', r.state, 'lead_id', r.lead_id); end if;
  if p_contact is null or jsonb_typeof(p_contact) <> 'object' or p_contact ? 'error' then
    update app.prospect_reveals set state = 'failed', credits = 0,
      error = case when (p_contact ->> 'error') ~ '^[a-z0-9_.:-]{1,60}$' then p_contact ->> 'error' else 'provider_error' end where id = r.id;
    perform app.log('prospect.reveal_failed', 'prospect', r.id::text);
    return jsonb_build_object('reveal', r.id, 'state', 'failed');
  end if;
  v_email := lower(nullif(btrim(p_contact ->> 'email'), ''));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
  v_org := app.capture_org(case when regexp_replace(coalesce(p_contact #>> '{organization,org_number}', ''), '\D', '', 'g') ~ '^\d{9}$'
                                then p_contact #>> '{organization,org_number}' end,
                           p_contact #>> '{organization,name}', 'Prospect search', r.revealed_by);
  v_person := app.capture_person(v_email, p_contact ->> 'name', p_contact ->> 'phone', v_org, 'Prospect search', r.revealed_by);
  if v_person is null and v_org is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'contact'; end if;
  if v_person is not null and nullif(btrim(p_contact ->> 'title'), '') is not null then
    update app.people set title = coalesce(title, left(btrim(p_contact ->> 'title'), 80)) where id = v_person;
  end if;
  v_lead := app.capture_lead(left(coalesce(nullif(btrim(p_contact ->> 'name'), ''), nullif(btrim(p_contact #>> '{organization,name}'), ''), 'Prospect'), 200),
                             v_person, v_org, 'Prospect search', r.revealed_by, null);
  update app.prospect_reveals set state = 'revealed', person_id = v_person, organization_id = v_org, lead_id = v_lead where id = r.id;
  insert into app.credit_ledger (delta, provider, staff_id, reveal_id) values (-r.credits, 'contact_data', r.revealed_by, r.id);
  perform app.log('prospect.revealed', 'prospect', r.id::text, jsonb_build_object('lead', v_lead, 'credits', r.credits));
  perform app.emit('prospect.revealed', 'lead', v_lead, jsonb_build_object('reveal', r.id, 'provider', r.provider));
  return jsonb_build_object('reveal', r.id, 'state', 'revealed', 'lead_id', v_lead);
end $fn$;

-- ---------------------------------------------------------------------------
-- web visitors (WEB-01..04, SF-18, D-37)
-- the register's answer for the companies the IP-to-company provider names; an ENK identifies a person (Q16)
create function public.worker_company_upsert(p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x jsonb; n int := 0; v_excluded int := 0; v_enk boolean;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    continue when jsonb_typeof(x) <> 'object' or coalesce(x ->> 'org_number', '') !~ '^\d{9}$' or coalesce(btrim(x ->> 'name'), '') = '';
    v_enk := upper(coalesce(x ->> 'org_form', '')) = 'ENK';
    insert into app.web_companies (org_number, name, org_form, nace, industry, city, fylke, employees, website, excluded, fetched_at)
    values (x ->> 'org_number', left(btrim(x ->> 'name'), 200), left(upper(x ->> 'org_form'), 10), left(x ->> 'nace', 10), left(x ->> 'industry', 200),
            left(x ->> 'city', 80), left(x ->> 'fylke', 60), case when (x ->> 'employees') ~ '^\d{1,9}$' then (x ->> 'employees')::int end,
            left(x ->> 'website', 200), v_enk, now())
    on conflict (org_number) do update set name = excluded.name, org_form = excluded.org_form, nace = excluded.nace, industry = excluded.industry,
      city = excluded.city, fylke = excluded.fylke, employees = excluded.employees, website = excluded.website, excluded = excluded.excluded, fetched_at = now();
    if v_enk then
      -- a natural person's business: the visits and chats keep no org number
      update app.web_sessions set company_org_number = null where company_org_number = x ->> 'org_number';
      update app.chat_conversations set company_org_number = null where company_org_number = x ->> 'org_number';
      v_excluded := v_excluded + 1;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('upserted', n, 'excluded', v_excluded);
end $fn$;

-- the tracker's batch (0025), now also: survey hosts dropped (survey_flow_block), no company with identification off
-- or for an ENK, a lookup queued for an unknown company, the site's last-seen time, and visitor.identified once per
-- CRM organization per day
create or replace function public.worker_web_ingest(p_batch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  x jsonb; v_site uuid; v_sess uuid; v_utm jsonb; n int := 0; v_survey int := 0; v_org text; v_at timestamptz; v_crm uuid; v_new boolean;
  v_ident boolean := app.setting('web_ident') = 'on';
begin
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch'; end if;
  for x in select * from jsonb_array_elements(p_batch) loop
    -- never a survey host, even if one were registered (fixed rule, LGN-05)
    if lower(coalesce(x ->> 'site', '')) ~ '(^|\.)svar\.' then v_survey := v_survey + 1; continue; end if;
    select id into v_site from app.web_sites where hostname = lower(x ->> 'site') and active;
    -- the hash is the tracker's daily-salted digest; anything else (an address, a cookie) is dropped
    continue when v_site is null or coalesce(x ->> 'visitor_hash', '') !~ '^[0-9a-f]{32,64}$';
    v_at := (x ->> 'at')::timestamptz;
    v_utm := case when jsonb_typeof(x -> 'utm') = 'object' then x -> 'utm' else '{}'::jsonb end;
    v_org := case when v_ident and x ->> 'company_org_number' ~ '^\d{9}$'
                       and not exists (select 1 from app.web_companies w where w.org_number = x ->> 'company_org_number' and w.excluded)
                  then x ->> 'company_org_number' end;
    v_new := false;
    -- a session: the same visitor hash on the same day, within 30 minutes of its last page
    select s.id into v_sess from app.web_sessions s
    where s.site_id = v_site and s.day = v_at::date and s.visitor_hash = x ->> 'visitor_hash'
      and exists (select 1 from app.web_pageviews p where p.session_id = s.id and p.at > v_at - interval '30 minutes')
    order by s.started_at desc limit 1;
    if v_sess is null then
      insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, company_org_number, pageviews)
      values (v_site, v_at::date, x ->> 'visitor_hash', v_at, left(x ->> 'path', 500), left(x ->> 'referrer_host', 200),
              v_utm, app.channel_of(v_utm || jsonb_build_object('referrer_host', x ->> 'referrer_host')), v_org, 0)
      returning id into v_sess;
      v_new := true;
    end if;
    if jsonb_typeof(x -> 'event') = 'object' then
      insert into app.web_events (session_id, at, name, value) values (v_sess, v_at, x -> 'event' ->> 'name', left(x -> 'event' ->> 'value', 120));
    else
      insert into app.web_pageviews (session_id, at, path) values (v_sess, v_at, left(coalesce(x ->> 'path', '/'), 500));
      update app.web_sessions set pageviews = pageviews + 1 where id = v_sess;
    end if;
    update app.web_sites set last_seen_at = greatest(coalesce(last_seen_at, v_at), v_at) where id = v_site;
    if v_new and v_org is not null then
      -- an unknown company: the register lookup (Brønnøysund, no key) runs in the edge worker
      if not exists (select 1 from app.web_companies w where w.org_number = v_org)
         and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.id <> v_sess and s.day > current_date - 30) then
        perform pgmq.send('jobs', jsonb_build_object('job', 'company_lookup', 'org_number', v_org));
      end if;
      -- visitor.identified: once per CRM organization per day, on its first session
      select o.id into v_crm from app.organizations o where o.org_number = v_org and o.deleted_at is null and not o.is_sample order by o.created_at limit 1;
      if v_crm is not null and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.day = v_at::date and s.id <> v_sess) then
        perform app.emit('visitor.identified', 'organization', v_crm,
                         jsonb_build_object('org_number', v_org, 'pages', (select pageviews from app.web_sessions where id = v_sess),
                                            'high_intent', coalesce(x ->> 'path', '') ~* '^/(pris|priser|pricing|demo|kontakt|contact)(/|$)'));
      end if;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('stored', n, 'dropped_survey', v_survey);
end $fn$;

-- the visitor inbox: companies, most active first (WEB-03), company level only
create function public.visitors_get(p_days int default 30, p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_days int := case when p_days in (30, 90, 365) then p_days else 30 end; q jsonb := coalesce(p_filters, '{}'::jsonb); v_rows jsonb;
begin
  perform app.require('deals', 'see');
  perform app.require_module('visitors');
  if jsonb_typeof(q) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filters'; end if;
  with s as (
    select ws.* from app.web_sessions ws
    where ws.company_org_number is not null and ws.day > current_date - v_days
      and (q ->> 'campaign' is null or ws.utm ->> 'utm_campaign' = q ->> 'campaign')
      and (q ->> 'page' is null or exists (select 1 from app.web_pageviews p where p.session_id = ws.id
                                           and p.path like replace(replace(q ->> 'page', '%', '\%'), '_', '\_') || '%'))),
  g as (
    select s.company_org_number org, sum(s.pageviews) pages, count(*) sessions, max(s.started_at) last_visit,
           (array_agg(s.channel order by s.started_at desc))[1] channel
    from s group by 1),
  r as (
    select g.*, w.name w_name, w.industry, w.city, w.country, w.employees,
           (select o.id from app.organizations o where o.org_number = g.org and o.deleted_at is null and not o.is_sample order by o.created_at limit 1) crm_id
    from g left join app.web_companies w on w.org_number = g.org
    where coalesce(w.excluded, false) = false)
  select coalesce(jsonb_agg(jsonb_build_object('rank', x.rk, 'org_number', x.org,
           'name', coalesce((select o.name from app.organizations o where o.id = x.crm_id), x.w_name),
           'industry', x.industry, 'city', x.city, 'country', x.country, 'employees', x.employees,
           'source', x.channel, 'last_visit', x.last_visit, 'pages', x.pages, 'sessions', x.sessions,
           'in_crm', x.crm_id is not null, 'organization_id', x.crm_id) order by x.rk), '[]'::jsonb)
  into v_rows
  from (select r.*, row_number() over (order by r.pages desc, r.last_visit desc) rk from r
        where q ->> 'in_crm' is null or (r.crm_id is not null) = (q ->> 'in_crm')::boolean
        order by r.pages desc, r.last_visit desc limit 200) x;
  perform app.log('record.listed', 'visitor', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'days', v_days,
    'connected', app.connected('ip_company'),
    'identification', app.setting('web_ident'),
    'sites', (select coalesce(jsonb_agg(jsonb_build_object('id', ws.id, 'hostname', ws.hostname, 'last_seen_at', ws.last_seen_at) order by ws.hostname), '[]'::jsonb)
              from app.web_sites ws where ws.active and ws.last_seen_at > now() - interval '7 days'));
end $fn$;

-- one company's visits, newest first; time on page = the next page's time within the session
create function public.visitor_get(p_org_number text, p_days int default 30) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.web_companies; v_days int := least(greatest(coalesce(p_days, 30), 1), 365); v_crm uuid;
begin
  perform app.require('deals', 'see');
  perform app.require_module('visitors');
  if coalesce(p_org_number, '') !~ '^\d{9}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'org_number'; end if;
  select * into w from app.web_companies where org_number = p_org_number;
  if w.excluded or not exists (select 1 from app.web_sessions s where s.company_org_number = p_org_number and s.day > current_date - v_days) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  select o.id into v_crm from app.organizations o where o.org_number = p_org_number and o.deleted_at is null and not o.is_sample order by o.created_at limit 1;
  perform app.log('record.read', 'visitor', p_org_number);
  return jsonb_build_object('org_number', p_org_number,
    'name', coalesce((select o.name from app.organizations o where o.id = v_crm), w.name), 'industry', w.industry,
    -- the registered address, not the visitor's location
    'city', w.city, 'country', w.country, 'employees', w.employees, 'website', w.website,
    'in_crm', v_crm is not null, 'organization_id', v_crm,
    'visits_30d', (select count(*) from app.web_sessions s where s.company_org_number = p_org_number and s.day > current_date - 30),
    'pageviews', (select coalesce(jsonb_agg(jsonb_build_object('at', y.at, 'path', y.path, 'channel', y.channel, 'seconds', y.secs) order by y.at desc), '[]'::jsonb)
                  from (select p.at, p.path, s.channel, extract(epoch from (lead(p.at) over (partition by p.session_id order by p.at) - p.at))::int secs
                        from app.web_pageviews p join app.web_sessions s on s.id = p.session_id
                        where s.company_org_number = p_org_number and s.day > current_date - v_days
                        order by p.at desc limit 500) y));
end $fn$;

-- convert a visiting company: the organization (found or made from web_companies), then a lead or a deal (WEB-04).
-- The visits link through organizations.org_number; no link table.
create function public.visitor_convert(p_org_number text, p_kind text, p_pipeline uuid default null, p_stage uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); w app.web_companies; v_org uuid; v_lead uuid; v_deal uuid;
begin
  perform app.require_module('visitors');
  if p_kind is null or p_kind not in ('lead', 'deal', 'organization') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if coalesce(p_org_number, '') !~ '^\d{9}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'org_number'; end if;
  select * into w from app.web_companies where org_number = p_org_number;
  if w.excluded or not exists (select 1 from app.web_sessions s where s.company_org_number = p_org_number) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  v_org := app.capture_org(p_org_number, w.name, 'Web visitors', v_me);
  if p_kind = 'lead' then
    v_lead := app.capture_lead(coalesce(w.name, p_org_number), null, v_org, 'Web visitors', v_me, null);
  elsif p_kind = 'deal' then
    if p_pipeline is not null and not app.pipeline_visible(p_pipeline) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id'; end if;
    v_deal := app.capture_deal(coalesce(w.name, p_org_number), null, v_org, 'Web visitors', v_me, p_pipeline, p_stage);
  end if;
  perform app.log('visitor.converted', 'visitor', p_org_number, jsonb_build_object('kind', p_kind, 'organization', v_org, 'lead', v_lead, 'deal', v_deal));
  return jsonb_strip_nulls(jsonb_build_object('organization_id', v_org, 'lead_id', v_lead, 'deal_id', v_deal));
end $fn$;

-- tracked sites and their embed snippet (go.owntheagenda.com, D-28; Q1)
create function public.web_sites_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('campaigns', 'see');
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'hostname', s.hostname, 'key', s.key, 'active', s.active, 'chat_enabled', s.chat_enabled,
                                                       'last_seen_at', s.last_seen_at,
                                                       'sessions_7d', (select count(*) from app.web_sessions ws where ws.site_id = s.id and ws.day > current_date - 7),
                                                       'snippet', format('<script async src="https://go.owntheagenda.com/w.js" data-site="%s"></script>', s.key))
                                    order by s.hostname) from app.web_sites s), '[]'::jsonb);
end $fn$;

create function public.web_site_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); v jsonb := coalesce(p_values, '{}'::jsonb); s app.web_sites; v_host text; v_key text;
begin
  if jsonb_typeof(v) <> 'object' or exists (select 1 from jsonb_object_keys(v) k where k not in ('hostname', 'key', 'active', 'chat_enabled')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end if;
  v_host := lower(btrim(v ->> 'hostname'));
  -- survey hosts can never be tracked (survey_flow_block); the table's check says the same
  if v_host ~ '(^|\.)svar\.' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hostname'; end if;
  if v ? 'active' and jsonb_typeof(v -> 'active') <> 'boolean' or v ? 'chat_enabled' and jsonb_typeof(v -> 'chat_enabled') <> 'boolean' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end if;
  begin
    if p_id is null then
      if v_host is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hostname'; end if;
      v_key := coalesce(v ->> 'key', left(trim(both '-' from regexp_replace(regexp_replace(v_host, '^www\.', ''), '[^a-z0-9]+', '-', 'g')), 40));
      insert into app.web_sites (hostname, key, active, chat_enabled) values (v_host, v_key, coalesce((v ->> 'active')::boolean, true), coalesce((v ->> 'chat_enabled')::boolean, false))
      returning * into s;
    else
      update app.web_sites t set hostname = coalesce(v_host, t.hostname), key = coalesce(v ->> 'key', t.key),
        active = coalesce((v ->> 'active')::boolean, t.active), chat_enabled = coalesce((v ->> 'chat_enabled')::boolean, t.chat_enabled)
      where t.id = p_id returning * into s;
      if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    end if;
  exception
    when check_violation then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = case when v_host is not null then 'hostname' else 'key' end;
    when unique_violation then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'duplicate';
  end;
  perform app.log('web_site.saved', 'web_site', s.id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v)))));
  return jsonb_build_object('id', s.id, 'hostname', s.hostname, 'key', s.key, 'active', s.active, 'chat_enabled', s.chat_enabled,
                            'snippet', format('<script async src="https://go.owntheagenda.com/w.js" data-site="%s"></script>', s.key));
end $fn$;

-- ---------------------------------------------------------------------------
-- retention (§10): form tracking metadata 13 months; unconfirmed double opt-in links a month after they expire
create function app.capture_prune() returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.form_submissions set tracking = '{}'::jsonb where tracking <> '{}'::jsonb and created_at < now() - interval '13 months';
  delete from app.consent_confirmations where confirmed_at is null and expires_at < now() - interval '30 days';
end $fn$;
select cron.schedule('platform-capture-prune', '52 3 * * *', 'select app.capture_prune()');

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['consent_texts', 'suppressions', 'web_companies', 'forms', 'form_versions', 'form_submissions', 'form_stats_daily',
                           'consent_confirmations', 'chat_playbooks', 'chat_playbook_versions', 'chat_conversations', 'chat_messages', 'chat_presence',
                           'prospect_reveals'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.form_language_fixed()', 'app.consent_text_fixed()', 'app.form_version_fixed()', 'app.playbook_version_fixed()', 'app.chat_message_fixed()',
                           'app.email_hash(text)', 'app.token_hash(text)', 'app.connected(text)', 'app.require_connected(text)',
                           'app.consent_write(uuid, text, text, text, text, uuid, uuid, text, text)',
                           'app.capture_org(text, text, text, uuid, boolean)', 'app.capture_person(text, text, text, uuid, text, uuid, boolean)',
                           'app.capture_lead(text, uuid, uuid, text, uuid, jsonb, boolean)', 'app.capture_deal(text, uuid, uuid, text, uuid, uuid, uuid, boolean)',
                           'app.ticket_from_capture(text, text, text, uuid, text, text, uuid, text, jsonb, bigint, uuid, boolean)', 'app.ticket_intake(bigint)',
                           'app.person_email_changed()', 'app.person_erased()', 'app.product_event_out()', 'app.form_check(text, text, jsonb, boolean)', 'app.form_seed(text, text)',
                           'app.form_row(app.forms)', 'app.form_take(uuid, boolean)', 'app.chat_steps_check(jsonb)', 'app.playbook_row(app.chat_playbooks)',
                           'app.chat_complete(uuid)', 'app.chat_advance(uuid)', 'app.chat_fallback()', 'app.chat_visible(app.chat_conversations)',
                           'app.chat_row(app.chat_conversations)', 'app.capture_prune()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.consent_set(uuid, text, text, text, text, uuid)', 'public.consent_texts_get()', 'public.consent_text_save(text, text, text)',
                           'public.consent_log(int, bigint)', 'public.marketing_status_summary()', 'public.suppressions_get(text)',
                           'public.suppression_add(text, text, text)', 'public.suppression_remove(text, text, text)',
                           'public.forms_get()', 'public.form_get(uuid)', 'public.form_create(text, text, text)', 'public.form_save(uuid, jsonb, int, text)',
                           'public.form_publish(uuid)', 'public.form_set_status(uuid, text)', 'public.form_delete(uuid, text)', 'public.form_stats(uuid, int)',
                           'public.form_submissions(uuid, int)',
                           'public.playbooks_get()', 'public.playbook_get(uuid)', 'public.playbook_save(uuid, jsonb, int)', 'public.playbook_publish(uuid)',
                           'public.playbook_set_state(uuid, text)', 'public.playbook_stats(uuid, int)', 'public.chats_queue()', 'public.chat_get(uuid)',
                           'public.chat_claim(uuid)', 'public.chat_send(uuid, text)', 'public.chat_close(uuid)', 'public.chat_presence_set(boolean)',
                           'public.prospect_search(jsonb, int)', 'public.prospect_reveal(text, text)', 'public.prospect_usage()',
                           'public.visitors_get(int, jsonb)', 'public.visitor_get(text, int)', 'public.visitor_convert(text, text, uuid, uuid)',
                           'public.web_sites_get()', 'public.web_site_save(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_consent_confirm(text)', 'public.worker_form_definition(text)', 'public.worker_form_event(text, text)',
                           'public.worker_form_submit(text, jsonb, jsonb)', 'public.worker_chat_start(text, text, text, text)',
                           'public.worker_chat_message(text, text)', 'public.worker_chat_poll(text, bigint)', 'public.worker_company_upsert(jsonb)',
                           'public.worker_web_ingest(jsonb)', 'public.worker_prospect_revealed(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
