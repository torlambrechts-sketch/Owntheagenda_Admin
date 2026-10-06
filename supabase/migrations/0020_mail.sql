-- 0020_mail.sql — mailboxes, threads and messages, links to records, tracking, templates and merge fields,
-- group sends and the outbox (Inbox, COM-01..14).
--
-- Mail moves through Gmail and Microsoft Graph directly (D-07). The provider adapters are edge workers that
-- hold the OAuth client; until a client is configured no mailbox can connect, and every mail view shows
-- «no mailbox connected» rather than sample mail. Tokens live in Vault, one secret per mailbox (D-18), read
-- only by the worker functions below, which only the service role may call.
--
-- Sending is asynchronous: email_send validates and renders, stores the message as queued (or scheduled)
-- and puts a job on the queue; the worker sends it and reports back (mail_mark_sent / mail_mark_failed).
-- The activity of type «email» is written when the message is actually sent (COM-02).
--
-- Tracking stores no IP address (in the spirit of D-37): an open or a click is a kind, a time and a client
-- class. The thread list's status is derived from the direction of the first and the last message.

-- ---------------------------------------------------------------------------
-- mailboxes
create table app.mailboxes (
  id                 uuid primary key default gen_random_uuid(),
  kind               text not null default 'personal' check (kind in ('personal', 'team')),
  provider           text not null check (provider in ('google', 'microsoft')),
  address            text not null unique check (address = lower(address) and address ~ '^[^@\s]+@[^@\s]+$' and char_length(address) <= 254),
  display_name       text check (display_name is null or char_length(btrim(display_name)) between 1 and 120),
  owner_id           uuid references app.admins (id) on delete set null,
  status             text not null default 'connecting' check (status in ('connecting', 'syncing', 'synced', 'reauth', 'error', 'disconnected')),
  status_detail      text check (status_detail is null or char_length(status_detail) <= 300),
  vault_secret_id    uuid,
  sync_from          date,
  default_visibility text not null default 'private' check (default_visibility in ('private', 'shared')),
  signature          text check (signature is null or char_length(signature) <= 4000),
  sync_cursor        text check (sync_cursor is null or char_length(sync_cursor) <= 2000),
  watch_expires_at   timestamptz,
  last_synced_at     timestamptz,
  throttle_per_min   int not null default 20 check (throttle_per_min between 1 and 600),
  is_sample          boolean not null default false,
  created_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  check (kind = 'team' or owner_id is not null or deleted_at is not null)
);

create table app.mailbox_members (
  mailbox_id uuid not null references app.mailboxes (id) on delete cascade,
  staff_id   uuid not null references app.admins (id) on delete cascade,
  can_reply  boolean not null default true,
  primary key (mailbox_id, staff_id)
);

-- addresses a staff member may send as, or that the drop-box accepts mail from
create table app.sender_aliases (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid not null references app.admins (id) on delete cascade,
  address     text not null check (address = lower(address) and address ~ '^[^@\s]+@[^@\s]+$' and char_length(address) <= 254),
  kind        text not null check (kind in ('send_as', 'bcc_accepted')),
  verified_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (staff_id, address, kind)
);

-- the BCC drop-box: a random local part per staff member, and per record. The domain is the inbound route
-- of the email provider (an MX record on the inbox subdomain); the app shows «not configured» without it.
create table app.dropbox_addresses (
  local_part text primary key check (local_part ~ '^[a-z0-9.-]{6,64}$'),
  staff_id   uuid not null references app.admins (id) on delete cascade,
  entity     text references app.entities (key) on delete cascade,
  record_id  uuid,
  created_at timestamptz not null default now(),
  check ((entity is null) = (record_id is null))
);
create unique index dropbox_one_per_target on app.dropbox_addresses (staff_id, coalesce(entity, ''), coalesce(record_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- ---------------------------------------------------------------------------
-- threads and messages
create table app.email_threads (
  id                 uuid primary key default gen_random_uuid(),
  mailbox_id         uuid references app.mailboxes (id) on delete set null,
  provider_thread_id text check (provider_thread_id is null or char_length(provider_thread_id) <= 200),
  subject            text not null default '' check (char_length(subject) <= 500),
  snippet            text not null default '' check (char_length(snippet) <= 300),
  first_direction    text check (first_direction is null or first_direction in ('in', 'out')),
  last_direction     text check (last_direction is null or last_direction in ('in', 'out')),
  last_message_at    timestamptz,
  visibility         text check (visibility is null or visibility in ('private', 'shared')),   -- null: the mailbox's default
  archived_at        timestamptz,
  labels             uuid[] not null default '{}',
  custom             jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample          boolean not null default false,
  version            int not null default 1,
  created_at         timestamptz not null default now(),
  created_by         uuid,
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  deleted_at         timestamptz,
  unique (mailbox_id, provider_thread_id)
);
create index email_threads_recent on app.email_threads (mailbox_id, last_message_at desc) where deleted_at is null;

create table app.email_thread_reads (
  thread_id uuid not null references app.email_threads (id) on delete cascade,
  staff_id  uuid not null references app.admins (id) on delete cascade,
  read_at   timestamptz not null default now(),
  primary key (thread_id, staff_id)
);

create table app.email_thread_participants (
  thread_id uuid not null references app.email_threads (id) on delete cascade,
  address   text not null check (address = lower(address) and char_length(address) <= 254),
  name      text check (name is null or char_length(name) <= 200),
  person_id uuid references app.people (id) on delete set null,
  primary key (thread_id, address)
);
create index email_participants_person on app.email_thread_participants (person_id) where person_id is not null;

create table app.email_templates (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 120),
  scope      text not null default 'private' check (scope in ('private', 'shared')),
  is_starter boolean not null default false,
  owner_id   uuid references app.admins (id) on delete set null,
  subject    text not null default '' check (char_length(subject) <= 500),
  body       text not null default '' check (char_length(body) <= 50000),
  is_sample  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table app.group_sends (
  id           uuid primary key default gen_random_uuid(),
  mailbox_id   uuid not null references app.mailboxes (id),
  template_id  uuid references app.email_templates (id) on delete set null,
  subject      text not null check (char_length(subject) <= 500),
  source_kind  text not null check (source_kind in ('people', 'view', 'deals')),
  source_ref   jsonb not null default '{}'::jsonb,
  total        int not null check (total >= 0),
  excluded     jsonb not null default '[]'::jsonb check (jsonb_typeof(excluded) = 'array'),
  consent_mode text not null check (consent_mode in ('off', 'warn', 'block')),
  state        text not null default 'sending' check (state in ('sending', 'done', 'canceled')),
  created_by   uuid references app.admins (id) on delete set null,
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now()
);

create table app.email_messages (
  id                  uuid primary key default gen_random_uuid(),
  thread_id           uuid not null references app.email_threads (id) on delete cascade,
  mailbox_id          uuid references app.mailboxes (id) on delete set null,
  provider_message_id text check (provider_message_id is null or char_length(provider_message_id) <= 200),
  rfc_message_id      text check (rfc_message_id is null or char_length(rfc_message_id) <= 500),
  in_reply_to         text check (in_reply_to is null or char_length(in_reply_to) <= 500),
  direction           text not null check (direction in ('in', 'out')),
  from_addr           text not null check (char_length(from_addr) <= 254),
  from_name           text check (from_name is null or char_length(from_name) <= 200),
  to_addrs            jsonb not null default '[]'::jsonb check (jsonb_typeof(to_addrs) = 'array'),
  cc                  jsonb not null default '[]'::jsonb check (jsonb_typeof(cc) = 'array'),
  bcc                 jsonb not null default '[]'::jsonb check (jsonb_typeof(bcc) = 'array'),
  subject             text not null default '' check (char_length(subject) <= 500),
  body_text           text check (body_text is null or char_length(body_text) <= 200000),
  body_html           text check (body_html is null or char_length(body_html) <= 500000),
  source              text not null check (source in ('sync', 'crm', 'dropbox', 'group', 'sequence', 'workflow')),
  state               text not null check (state in ('draft', 'awaiting_review', 'scheduled', 'queued', 'sending', 'sent', 'failed', 'canceled', 'received')),
  scheduled_at        timestamptz,
  sent_at             timestamptz,
  received_at         timestamptz,
  sent_by             uuid references app.admins (id) on delete set null,
  template_id         uuid references app.email_templates (id) on delete set null,
  tracking            boolean not null default false,
  track_token         text unique check (track_token is null or track_token ~ '^[A-Za-z0-9_-]{22,64}$'),
  attempt             int not null default 0 check (attempt between 0 and 20),
  failure_code        text check (failure_code is null or char_length(failure_code) <= 60),
  failure_reason      text check (failure_reason is null or char_length(failure_reason) <= 300),
  group_send_id       uuid references app.group_sends (id) on delete set null,
  enrollment_id       uuid,                        -- app.sequence_enrollments (0021)
  run_step_id         uuid,                        -- app.workflow_run_steps (0021)
  activity_id         uuid references app.activities (id) on delete set null,
  person_id           uuid references app.people (id) on delete set null,   -- the recipient of a group or sequence email
  is_sample           boolean not null default false,
  created_at          timestamptz not null default now(),
  check ((direction = 'in') = (state = 'received'))
);
create index email_messages_thread on app.email_messages (thread_id, created_at);
create index email_messages_outbox on app.email_messages (sent_by, state) where state in ('scheduled', 'queued', 'sending', 'failed', 'awaiting_review');
create index email_messages_due on app.email_messages (scheduled_at) where state = 'scheduled';
create unique index email_messages_provider on app.email_messages (mailbox_id, provider_message_id) where provider_message_id is not null;

create table app.email_attachments (
  id                     uuid primary key default gen_random_uuid(),
  message_id             uuid not null references app.email_messages (id) on delete cascade,
  storage_path           text check (storage_path is null or char_length(storage_path) <= 500),
  filename               text not null check (char_length(filename) between 1 and 255),
  mime                   text not null check (char_length(mime) <= 120),
  size_bytes             bigint not null check (size_bytes between 0 and 26214400),
  provider_attachment_id text check (provider_attachment_id is null or char_length(provider_attachment_id) <= 500)
);

create table app.email_links (
  thread_id  uuid not null references app.email_threads (id) on delete cascade,
  entity     text not null references app.entities (key) on delete cascade,
  record_id  uuid not null,
  linked_by  text not null check (linked_by in ('auto', 'manual', 'dropbox')),
  staff_id   uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (thread_id, entity, record_id)
);
create index email_links_record on app.email_links (entity, record_id);

create table app.email_tracking_links (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references app.email_messages (id) on delete cascade,
  url        text not null check (char_length(url) <= 2000 and url ~ '^https?://'),
  label      text check (label is null or char_length(label) <= 200),
  token      text not null unique check (token ~ '^[A-Za-z0-9_-]{22,64}$')
);

create table app.email_tracking_events (
  id           bigint generated always as identity primary key,
  message_id   uuid not null references app.email_messages (id) on delete cascade,
  link_id      uuid references app.email_tracking_links (id) on delete cascade,
  kind         text not null check (kind in ('open', 'click')),
  client_class text not null default 'unknown' check (client_class in ('human', 'prefetch', 'unknown')),
  at           timestamptz not null default now(),
  check ((kind = 'click') = (link_id is not null))
);
create index email_tracking_message on app.email_tracking_events (message_id, at desc);

-- merge fields: a seeded registry. A token resolves through a source path; the format says how it prints.
create table app.merge_fields (
  token       text primary key check (token ~ '^[A-Za-zÆØÅæøå]+\.[A-Za-zÆØÅæøå]+$'),
  source_path text not null check (source_path ~ '^[a-z_]+\.[a-z_]+$'),
  format      text not null default 'text' check (format in ('text', 'first_word', 'nok', 'int', 'url')),
  ord         int not null default 0
);
insert into app.merge_fields (token, source_path, format, ord) values
  ('Person.fornavn', 'person.name', 'first_word', 10),
  ('Person.navn', 'person.name', 'text', 20),
  ('Person.epost', 'person.email', 'text', 30),
  ('Organisasjon.navn', 'organization.name', 'text', 40),
  ('Organisasjon.ansatte', 'organization.employees', 'int', 50),
  ('Avtale.tittel', 'deal.title', 'text', 60),
  ('Avtale.verdi', 'deal.value', 'nok', 70),
  ('Avtale.fase', 'deal.stage', 'text', 80),
  ('Bruker.navn', 'staff.name', 'text', 90),
  ('Bruker.bookinglenke', 'staff.booking_link', 'url', 100),
  ('Bruker.signatur', 'mailbox.signature', 'text', 110);

-- AI insight per thread (AIA-04): written by the AI worker on request, never canned
create table app.email_thread_insights (
  thread_id         uuid primary key references app.email_threads (id) on delete cascade,
  upto_message_id   uuid references app.email_messages (id) on delete set null,
  summary           text check (summary is null or char_length(summary) <= 4000),
  sentiment         text check (sentiment is null or sentiment in ('positive', 'neutral', 'negative')),
  readiness         smallint check (readiness is null or readiness between 1 and 10),
  reason            text check (reason is null or char_length(reason) <= 1000),
  action_items      jsonb not null default '[]'::jsonb check (jsonb_typeof(action_items) = 'array'),
  suggested_replies jsonb not null default '[]'::jsonb check (jsonb_typeof(suggested_replies) = 'array'),
  model             text check (model is null or char_length(model) <= 80),
  state             text not null default 'requested' check (state in ('requested', 'ready', 'failed')),
  generated_at      timestamptz,
  requested_by      uuid references app.admins (id) on delete set null,
  requested_at      timestamptz not null default now()
);

-- email threads take labels like any record (Proposal, Follow-up, Billing …). The record API sees only the
-- threads the caller may see (app.vis_sql below); the mail functions are the normal way in.
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('email_thread', 'email_threads', 'deals', null, false, 'subject', array['snippet'], '{}', 70);

-- ---------------------------------------------------------------------------
-- visibility. A thread is visible to its mailbox's owner and members; a shared thread to every staff member
-- who may see deals; a thread without a mailbox (written from the CRM before a mailbox existed, or dropped
-- in through the BCC address) to its creator and, when shared, the same way.
create function app.thread_visible(p_thread uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (
    select 1 from app.email_threads t left join app.mailboxes m on m.id = t.mailbox_id
    where t.id = p_thread and (
      m.owner_id = app.me()
      or t.created_by = app.me()
      or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = app.me())
      or (coalesce(t.visibility, m.default_visibility, 'private') = 'shared' and app.can('deals', 'see'))))
$fn$;

create or replace function app.vis_sql(e app.entities) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when e.key = 'email_thread' then 'app.thread_visible(t.id)'
              when e.owned then 'app.visible(t.owner_id, t.visibility)' else 'true' end
$fn$;

-- the screen a notification about a record opens
create function app.entity_route(p_entity text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case p_entity when 'deal' then '/deals' when 'lead' then '/leads' when 'person' then '/contacts' when 'organization' then '/contacts'
                       when 'activity' then '/activities' when 'ticket' then '/tickets' when 'email_thread' then '/inbox' else null end
$fn$;

-- the mailboxes the caller may send from
create function app.my_mailboxes() returns setof uuid
  language sql stable security definer set search_path = ''
as $fn$
  select m.id from app.mailboxes m
  where m.deleted_at is null and (m.owner_id = app.me()
    or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = app.me() and mm.can_reply))
$fn$;

create function app.token() returns text
  language sql volatile set search_path = ''
as $fn$
  select translate(rtrim(encode(extensions.gen_random_bytes(18), 'base64'), '='), '+/', '-_')
$fn$;

-- the records a thread is linked to, as an event payload carries them
create function app.thread_links(p_thread uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('entity', l.entity, 'id', l.record_id)), '[]'::jsonb) from app.email_links l where l.thread_id = p_thread
$fn$;

-- the derived status of a thread (Waiting on you / New / Replied / Waiting on contact)
create function app.thread_status(t app.email_threads) returns text
  language sql stable set search_path = ''
as $fn$
  select case
    when not exists (select 1 from app.email_messages m where m.thread_id = t.id and m.direction = 'out' and m.state = 'sent') then 'new'
    when t.last_direction = 'in' then 'waiting_on_you'
    when t.first_direction = 'in' then 'replied'
    else 'waiting_on_contact' end
$fn$;

create function app.thread_unread(p_thread uuid, p_staff uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.email_messages m where m.thread_id = p_thread and m.direction = 'in'
                 and m.created_at > coalesce((select r.read_at from app.email_thread_reads r where r.thread_id = p_thread and r.staff_id = p_staff), '-infinity'))
$fn$;

-- the thread's linked records with their titles, only those the caller may see
create function app.thread_link_titles(p_thread uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare l record; e app.entities; v_title text; out jsonb := '[]'::jsonb;
begin
  for l in select * from app.email_links where thread_id = p_thread order by created_at loop
    select * into e from app.entities where key = l.entity;
    execute format('select t.%I::text from app.%I t where t.id = %L and t.deleted_at is null and %s', e.title_col, e.tbl, l.record_id, app.vis_sql(e)) into v_title;
    if v_title is not null then
      out := out || jsonb_build_array(jsonb_build_object('entity', l.entity, 'id', l.record_id, 'title', v_title, 'linked_by', l.linked_by));
    end if;
  end loop;
  return out;
end $fn$;

-- ---------------------------------------------------------------------------
-- merge fields. The context is the record a message is about (deal, lead, person, organisation), the
-- recipient person, the sending staff member and the sending mailbox.
create function app.merge_context(p_entity text, p_record uuid, p_person uuid default null, p_staff uuid default null, p_mailbox uuid default null)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare v_deal uuid; v_person uuid := p_person; v_org uuid;
begin
  if p_entity = 'deal' then
    select id, coalesce(v_person, person_id), organization_id into v_deal, v_person, v_org from app.deals where id = p_record;
  elsif p_entity = 'lead' then
    select coalesce(v_person, person_id), organization_id into v_person, v_org from app.leads where id = p_record;
  elsif p_entity = 'person' then
    v_person := coalesce(v_person, p_record);
  elsif p_entity = 'organization' then
    v_org := p_record;
  end if;
  if v_org is null and v_person is not null then select organization_id into v_org from app.people where id = v_person; end if;
  return jsonb_build_object('deal', v_deal, 'person', v_person, 'organization', v_org, 'staff', p_staff, 'mailbox', p_mailbox);
end $fn$;

create function app.merge_value(p_token text, p_ctx jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.merge_fields; v text; src text; col text;
begin
  select * into f from app.merge_fields where token = p_token;
  if not found then return null; end if;
  src := split_part(f.source_path, '.', 1); col := split_part(f.source_path, '.', 2);
  v := case src
    when 'person' then (select case col when 'name' then p.name when 'email' then p.email end from app.people p where p.id = (p_ctx ->> 'person')::uuid)
    when 'organization' then (select case col when 'name' then o.name when 'employees' then o.employees::text end from app.organizations o where o.id = (p_ctx ->> 'organization')::uuid)
    when 'deal' then (select case col when 'title' then d.title when 'value' then d.value::text
                                      when 'stage' then (select s.name from app.stages s where s.id = d.stage_id) end
                      from app.deals d where d.id = (p_ctx ->> 'deal')::uuid)
    when 'staff' then (select case col when 'name' then a.name
                                       when 'booking_link' then (select b.slug from app.booking_links b where b.staff_id = a.id and b.kind = 'general' order by b.id limit 1) end
                       from app.admins a where a.id = (p_ctx ->> 'staff')::uuid)
    when 'mailbox' then (select m.signature from app.mailboxes m where m.id = (p_ctx ->> 'mailbox')::uuid)
  end;
  if v is null or btrim(v) = '' then return null; end if;
  return case f.format
    when 'first_word' then split_part(btrim(v), ' ', 1)
    when 'nok' then replace(to_char(round(v::numeric), 'FM999G999G999G990'), ',', ' ') || ' kr'
    when 'url' then 'booking:' || v            -- the app turns a booking slug into the public link (D-28 host)
    else v end;
end $fn$;

-- render [Token] merge fields; → {text, missing: [tokens without a value], unknown: [tokens not in the registry]}
create function app.merge_render(p_text text, p_ctx jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m text[]; tok text; v text; out text := coalesce(p_text, ''); v_missing text[] := '{}'; v_unknown text[] := '{}';
begin
  for m in select regexp_matches(coalesce(p_text, ''), '\[([A-Za-zÆØÅæøå]+\.[A-Za-zÆØÅæøå]+)\]', 'g') loop
    tok := m[1];
    if not exists (select 1 from app.merge_fields f where f.token = tok) then
      v_unknown := array_append(v_unknown, tok); continue;
    end if;
    v := app.merge_value(tok, p_ctx);
    if v is null then v_missing := array_append(v_missing, tok); continue; end if;
    out := replace(out, '[' || tok || ']', v);
  end loop;
  return jsonb_build_object('text', out, 'missing', to_jsonb(array(select distinct x from unnest(v_missing) x)),
                            'unknown', to_jsonb(array(select distinct x from unnest(v_unknown) x)));
end $fn$;

create function public.merge_fields_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('token', token, 'source', source_path, 'format', format) order by ord) from app.merge_fields), '[]'::jsonb);
end $fn$;

-- render a body and subject for a record, as the composer previews it
create function public.merge_preview(p_subject text, p_body text, p_entity text default null, p_record uuid default null,
                                     p_person uuid default null, p_mailbox uuid default null)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_ctx jsonb; s jsonb; b jsonb;
begin
  v_ctx := app.merge_context(p_entity, p_record, p_person, v_me, p_mailbox);
  s := app.merge_render(p_subject, v_ctx); b := app.merge_render(p_body, v_ctx);
  return jsonb_build_object('subject', s ->> 'text', 'body', b ->> 'text',
    'missing', to_jsonb(array(select distinct x from (select jsonb_array_elements_text(s -> 'missing') x union select jsonb_array_elements_text(b -> 'missing')) u)),
    'unknown', to_jsonb(array(select distinct x from (select jsonb_array_elements_text(s -> 'unknown') x union select jsonb_array_elements_text(b -> 'unknown')) u)));
end $fn$;

-- ---------------------------------------------------------------------------
-- templates
create function public.templates_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'scope', t.scope, 'is_starter', t.is_starter,
                                                       'owner_id', t.owner_id, 'owner', (select a.name from app.admins a where a.id = t.owner_id),
                                                       'subject', t.subject, 'body', t.body, 'updated_at', t.updated_at,
                                                       'mine', t.owner_id = v_me)
                                    order by t.is_starter desc, t.name)
                   from app.email_templates t where t.deleted_at is null and (t.scope = 'shared' or t.owner_id = v_me)), '[]'::jsonb);
end $fn$;

create function public.template_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_templates; v_id uuid; r jsonb;
begin
  if p_id is not null then
    select * into t from app.email_templates where id = p_id and deleted_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if t.owner_id is distinct from v_me and not app.can('global', 'configure') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
    end if;
  end if;
  if p_values ? 'scope' and p_values ->> 'scope' not in ('private', 'shared') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope';
  end if;
  r := app.merge_render(coalesce(p_values ->> 'subject', t.subject, '') || ' ' || coalesce(p_values ->> 'body', t.body, ''), '{}'::jsonb);
  if jsonb_array_length(r -> 'unknown') > 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || (r -> 'unknown' ->> 0);
  end if;
  if p_id is null then
    insert into app.email_templates (name, scope, owner_id, subject, body, is_sample)
    values (btrim(p_values ->> 'name'), coalesce(p_values ->> 'scope', 'private'), v_me, coalesce(p_values ->> 'subject', ''), coalesce(p_values ->> 'body', ''),
            (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.email_templates set name = coalesce(btrim(p_values ->> 'name'), name), scope = coalesce(p_values ->> 'scope', scope),
      subject = coalesce(p_values ->> 'subject', subject), body = coalesce(p_values ->> 'body', body), updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  perform app.log(case when p_id is null then 'template.created' else 'template.updated' end, 'email_template', v_id::text, null);
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.template_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_templates;
begin
  select * into t from app.email_templates where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.owner_id is distinct from v_me and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  update app.email_templates set deleted_at = now() where id = p_id;
  perform app.log('template.deleted', 'email_template', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- mailboxes as the Inbox's setup view shows them
create function public.mailboxes_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'mailboxes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'kind', m.kind, 'provider', m.provider, 'address', m.address, 'display_name', m.display_name,
        'owner_id', m.owner_id, 'owner', (select a.name from app.admins a where a.id = m.owner_id),
        'status', m.status, 'last_synced_at', m.last_synced_at, 'sync_from', m.sync_from,
        'default_visibility', m.default_visibility, 'signature', m.signature,
        'mine', m.owner_id = v_me, 'can_reply', m.id in (select app.my_mailboxes()),
        'members', coalesce((select jsonb_agg(jsonb_build_object('staff_id', mm.staff_id, 'name', a.name, 'can_reply', mm.can_reply) order by a.name)
                             from app.mailbox_members mm join app.admins a on a.id = mm.staff_id where mm.mailbox_id = m.id), '[]'::jsonb))
        order by m.kind, m.address)
      from app.mailboxes m
      where m.deleted_at is null and (m.owner_id = v_me or m.kind = 'team' or app.can('global', 'configure'))), '[]'::jsonb),
    'aliases', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'address', s.address, 'kind', s.kind, 'verified_at', s.verified_at) order by s.address)
                         from app.sender_aliases s where s.staff_id = v_me), '[]'::jsonb),
    'dropbox', (select d.local_part from app.dropbox_addresses d where d.staff_id = v_me and d.entity is null),
    'tracking', app.setting('tracking'));
end $fn$;

create function public.mailbox_update(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); m app.mailboxes;
begin
  select * into m from app.mailboxes where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if m.owner_id is distinct from v_me and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  if p_values ? 'default_visibility' and p_values ->> 'default_visibility' not in ('private', 'shared') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'default_visibility';
  end if;
  update app.mailboxes set
    display_name = case when p_values ? 'display_name' then nullif(btrim(p_values ->> 'display_name'), '') else display_name end,
    signature = case when p_values ? 'signature' then nullif(p_values ->> 'signature', '') else signature end,
    default_visibility = coalesce(p_values ->> 'default_visibility', default_visibility),
    sync_from = case when p_values ? 'sync_from' then (p_values ->> 'sync_from')::date else sync_from end
  where id = p_id;
  perform app.log('mailbox.updated', 'mailbox', p_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', p_id);
end $fn$;

create function public.mailbox_members_set(p_id uuid, p_members jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure');
begin
  if not exists (select 1 from app.mailboxes where id = p_id and kind = 'team' and deleted_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if jsonb_typeof(p_members) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'members'; end if;
  delete from app.mailbox_members where mailbox_id = p_id;
  insert into app.mailbox_members (mailbox_id, staff_id, can_reply)
  select p_id, (x ->> 'staff_id')::uuid, coalesce((x ->> 'can_reply')::boolean, true) from jsonb_array_elements(p_members) x
  where exists (select 1 from app.admins a where a.id = (x ->> 'staff_id')::uuid and a.active);
  perform app.log('mailbox.members_set', 'mailbox', p_id::text, jsonb_build_object('count', jsonb_array_length(p_members)));
  return jsonb_build_object('id', p_id);
end $fn$;

-- disconnecting removes the token from Vault; the mail already synced stays with its records
create function public.mailbox_disconnect(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); m app.mailboxes;
begin
  select * into m from app.mailboxes where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if m.owner_id is distinct from v_me and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  if m.vault_secret_id is not null then delete from vault.secrets where id = m.vault_secret_id; end if;
  update app.mailboxes set status = 'disconnected', vault_secret_id = null, sync_cursor = null, watch_expires_at = null where id = p_id;
  update app.email_messages set state = 'canceled', failure_code = 'mailbox_disconnected' where mailbox_id = p_id and state in ('scheduled', 'queued', 'awaiting_review');
  perform app.log('mailbox.disconnected', 'mailbox', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

create function public.sender_alias_add(p_address text, p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  if p_kind not in ('send_as', 'bcc_accepted') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if lower(btrim(coalesce(p_address, ''))) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'address'; end if;
  insert into app.sender_aliases (staff_id, address, kind) values (v_me, lower(btrim(p_address)), p_kind)
  on conflict (staff_id, address, kind) do update set kind = excluded.kind returning id into v_id;
  perform app.log('sender_alias.added', 'sender_alias', v_id::text, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.sender_alias_remove(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  delete from app.sender_aliases where id = p_id and staff_id = v_me;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('sender_alias.removed', 'sender_alias', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- the drop-box local part for me, or for a record I may see; created on first use
create function public.dropbox_address_get(p_entity text default null, p_record uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); e app.entities; v_ok boolean; v_local text;
begin
  if (p_entity is null) <> (p_record is null) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'record'; end if;
  if p_entity is not null then
    e := app.entity(p_entity);
    execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, p_record, app.vis_sql(e)) into v_ok;
    if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  select local_part into v_local from app.dropbox_addresses
  where staff_id = v_me and entity is not distinct from p_entity and record_id is not distinct from p_record;
  if v_local is null then
    v_local := lower(translate(left(app.token(), 10), '-_', 'xy'));
    v_local := coalesce(case when p_entity is null then v_local else p_entity || '-' || v_local end, v_local);
    insert into app.dropbox_addresses (local_part, staff_id, entity, record_id) values (v_local, v_me, p_entity, p_record);
  end if;
  return jsonb_build_object('local_part', v_local);
end $fn$;

-- ---------------------------------------------------------------------------
-- folders and threads
create function public.inbox_folders() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  return jsonb_build_object(
    'connected', exists (select 1 from app.mailboxes m where m.id in (select app.my_mailboxes()) and m.status in ('syncing', 'synced')),
    'inbox', (select count(*) from app.email_threads t join app.mailboxes m on m.id = t.mailbox_id
              where m.owner_id = v_me and m.kind = 'personal' and t.archived_at is null and t.deleted_at is null and app.thread_unread(t.id, v_me)),
    'teams', coalesce((select jsonb_agg(jsonb_build_object('mailbox_id', m.id, 'address', m.address,
                                         'unread', (select count(*) from app.email_threads t where t.mailbox_id = m.id and t.archived_at is null and t.deleted_at is null and app.thread_unread(t.id, v_me))))
                       from app.mailboxes m where m.kind = 'team' and m.deleted_at is null
                         and exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = v_me)), '[]'::jsonb),
    'outbox', (select count(*) from app.email_messages x where x.sent_by = v_me and x.state in ('scheduled', 'queued', 'sending', 'failed')),
    'review', (select count(*) from app.email_messages x where x.sent_by = v_me and x.state = 'awaiting_review'),
    'group', (select count(*) from app.group_sends g where g.created_by = v_me and g.state = 'sending'),
    'unlinked', (select count(*) from app.email_threads t join app.mailboxes m on m.id = t.mailbox_id
                 where m.owner_id = v_me and t.deleted_at is null and t.archived_at is null
                   and not exists (select 1 from app.email_links l where l.thread_id = t.id)));
end $fn$;

-- one thread as the list shows it
create function app.thread_row(t app.email_threads, p_me uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', t.id, 'subject', t.subject, 'snippet', t.snippet, 'last_message_at', t.last_message_at,
    'from_name', (select coalesce(m.from_name, m.from_addr) from app.email_messages m where m.thread_id = t.id and m.state in ('sent', 'received')
                  order by m.direction = 'in' desc, coalesce(m.received_at, m.sent_at, m.created_at) desc limit 1),
    'unread', app.thread_unread(t.id, p_me),
    'status', app.thread_status(t),
    'archived', t.archived_at is not null,
    'labels', to_jsonb(t.labels),
    'links', app.thread_link_titles(t.id),
    'mailbox', (select jsonb_build_object('id', mb.id, 'address', mb.address, 'provider', mb.provider, 'kind', mb.kind) from app.mailboxes mb where mb.id = t.mailbox_id),
    'opens', (select count(*) from app.email_tracking_events e where e.kind = 'open' and e.client_class <> 'prefetch'
              and e.message_id = (select m.id from app.email_messages m where m.thread_id = t.id and m.direction = 'out' and m.state = 'sent' order by m.sent_at desc limit 1)))
$fn$;

-- folder: inbox | team | archive | unlinked | all; filters: label, mailbox, q. Newest first, keyset on last_message_at.
create function public.threads_get(p_folder text default 'inbox', p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_label uuid := (p_query ->> 'label')::uuid;
  v_mailbox uuid := (p_query ->> 'mailbox')::uuid;
  v_q text := nullif(btrim(coalesce(p_query ->> 'q', '')), '');
  v_before timestamptz := (p_query ->> 'before')::timestamptz;
  v_limit int := least(greatest(coalesce((p_query ->> 'limit')::int, 50), 1), 200);
begin
  if p_folder not in ('inbox', 'team', 'archive', 'unlinked', 'all') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'folder';
  end if;
  return coalesce((select jsonb_agg(app.thread_row(t, v_me) order by t.last_message_at desc nulls last)
    from (select t.* from app.email_threads t left join app.mailboxes mb on mb.id = t.mailbox_id
          where t.deleted_at is null and app.thread_visible(t.id)
            and case p_folder
                  when 'inbox' then t.archived_at is null and mb.kind = 'personal' and mb.owner_id = v_me
                  when 'team' then t.archived_at is null and mb.kind = 'team' and (v_mailbox is null or mb.id = v_mailbox)
                  when 'archive' then t.archived_at is not null
                  when 'unlinked' then t.archived_at is null and not exists (select 1 from app.email_links l where l.thread_id = t.id)
                  else true end
            and (v_label is null or v_label = any (t.labels))
            and (v_q is null or t.subject ilike '%' || replace(replace(v_q, '%', '\%'), '_', '\_') || '%'
                 or exists (select 1 from app.email_thread_participants p where p.thread_id = t.id
                            and (p.address ilike '%' || replace(replace(v_q, '%', '\%'), '_', '\_') || '%' or p.name ilike '%' || replace(replace(v_q, '%', '\%'), '_', '\_') || '%')))
            and (v_before is null or t.last_message_at < v_before)
          order by t.last_message_at desc nulls last limit v_limit) t), '[]'::jsonb);
end $fn$;

-- a thread with its messages; marks it read for the caller
create function public.thread_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_threads; v_deal uuid; v_org uuid;
begin
  select * into t from app.email_threads where id = p_id and deleted_at is null;
  if not found or not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.email_thread_reads (thread_id, staff_id, read_at) values (p_id, v_me, now())
  on conflict (thread_id, staff_id) do update set read_at = now();
  v_deal := (select l.record_id from app.email_links l where l.thread_id = p_id and l.entity = 'deal' order by l.created_at limit 1);
  v_org := coalesce((select d.organization_id from app.deals d where d.id = v_deal),
                    (select l.record_id from app.email_links l where l.thread_id = p_id and l.entity = 'organization' order by l.created_at limit 1));
  return app.thread_row(t, v_me) || jsonb_build_object(
    'visibility', coalesce(t.visibility, (select m.default_visibility from app.mailboxes m where m.id = t.mailbox_id), 'private'),
    'version', t.version,
    'participants', coalesce((select jsonb_agg(jsonb_build_object('address', p.address, 'name', p.name, 'person_id', p.person_id) order by p.address)
                              from app.email_thread_participants p where p.thread_id = p_id), '[]'::jsonb),
    -- people on the linked deal, or at the linked organisation, who are not on the thread yet
    'suggested', coalesce((select jsonb_agg(jsonb_build_object('person_id', s.id, 'name', s.name, 'email', s.email) order by s.name)
                           from (select distinct pe.id, pe.name, pe.email from app.people pe
                                 where pe.deleted_at is null and pe.email is not null and app.visible(pe.owner_id, pe.visibility)
                                   and (pe.id in (select dp.person_id from app.deal_participants dp where dp.deal_id = v_deal)
                                        or (v_org is not null and pe.organization_id = v_org))
                                   and not exists (select 1 from app.email_thread_participants p where p.thread_id = p_id and p.address = lower(pe.email))
                                 limit 6) s), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'direction', m.direction, 'from_addr', m.from_addr, 'from_name', m.from_name, 'to', m.to_addrs, 'cc', m.cc,
        'subject', m.subject, 'body_text', m.body_text, 'body_html', m.body_html, 'state', m.state,
        'at', coalesce(m.received_at, m.sent_at, m.scheduled_at, m.created_at), 'scheduled_at', m.scheduled_at,
        'failure_code', m.failure_code, 'tracking', m.tracking,
        'attachments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'filename', a.filename, 'mime', a.mime, 'size', a.size_bytes))
                                 from app.email_attachments a where a.message_id = m.id), '[]'::jsonb),
        'track', case when m.direction = 'out' and m.tracking then jsonb_build_object(
            'opens', (select count(*) from app.email_tracking_events e where e.message_id = m.id and e.kind = 'open' and e.client_class <> 'prefetch'),
            'prefetch', (select count(*) from app.email_tracking_events e where e.message_id = m.id and e.kind = 'open' and e.client_class = 'prefetch'),
            'last_open', (select max(e.at) from app.email_tracking_events e where e.message_id = m.id and e.kind = 'open' and e.client_class <> 'prefetch'),
            'clicks', coalesce((select jsonb_agg(jsonb_build_object('label', coalesce(l.label, l.url), 'count', c.n, 'last', c.last))
                                from (select e.link_id, count(*) n, max(e.at) last from app.email_tracking_events e where e.message_id = m.id and e.kind = 'click' group by e.link_id) c
                                join app.email_tracking_links l on l.id = c.link_id), '[]'::jsonb)) end)
        order by coalesce(m.received_at, m.sent_at, m.scheduled_at, m.created_at))
      from app.email_messages m where m.thread_id = p_id and m.state <> 'draft'), '[]'::jsonb),
    'insight', (select jsonb_build_object('state', i.state, 'summary', i.summary, 'sentiment', i.sentiment, 'readiness', i.readiness, 'reason', i.reason,
                                          'action_items', i.action_items, 'suggested_replies', i.suggested_replies, 'generated_at', i.generated_at,
                                          'stale', i.upto_message_id is distinct from (select m.id from app.email_messages m where m.thread_id = p_id and m.state in ('sent', 'received')
                                                                                       order by coalesce(m.received_at, m.sent_at) desc limit 1))
                from app.email_thread_insights i where i.thread_id = p_id));
end $fn$;

create function public.thread_archive(p_id uuid, p_archived boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_threads;
begin
  select * into t from app.email_threads where id = p_id and deleted_at is null for update;
  if not found or not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.email_threads set archived_at = case when p_archived then coalesce(archived_at, now()) end, version = version + 1, updated_at = now(), updated_by = v_me
  where id = p_id;
  -- the provider side follows through the worker (Gmail drops the INBOX label, Graph moves to Archive)
  if t.mailbox_id is not null and t.provider_thread_id is not null then
    perform pgmq.send('jobs', jsonb_build_object('job', 'mail_archive', 'thread_id', p_id, 'archived', p_archived));
  end if;
  perform app.log(case when p_archived then 'thread.archived' else 'thread.unarchived' end, 'email_thread', p_id::text, null);
  return jsonb_build_object('id', p_id, 'archived', p_archived);
end $fn$;

create function public.thread_link(p_id uuid, p_entity text, p_record uuid, p_linked boolean default true) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); e app.entities; v_ok boolean;
begin
  if not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_entity not in ('deal', 'lead', 'person', 'organization', 'project') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  e := app.entity(p_entity);
  execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, p_record, app.vis_sql(e)) into v_ok;
  if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_linked then
    insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) values (p_id, p_entity, p_record, 'manual', v_me) on conflict do nothing;
  else
    delete from app.email_links where thread_id = p_id and entity = p_entity and record_id = p_record;
  end if;
  perform app.log(case when p_linked then 'thread.linked' else 'thread.unlinked' end, 'email_thread', p_id::text, jsonb_build_object('entity', p_entity, 'record', p_record));
  return jsonb_build_object('id', p_id, 'links', app.thread_link_titles(p_id));
end $fn$;

-- a thread becomes a lead: the sender becomes a person when nobody matches, and the thread is linked
create function public.thread_to_lead(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add'); t app.email_threads; m app.email_messages; v_person uuid; v_org uuid; r jsonb; v_lead uuid;
begin
  perform app.require_module('leads');
  select * into t from app.email_threads where id = p_id and deleted_at is null;
  if not found or not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into m from app.email_messages where thread_id = p_id and direction = 'in' order by received_at limit 1;
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_inbound'; end if;
  select id, organization_id into v_person, v_org from app.people where lower(email) = lower(m.from_addr) and deleted_at is null order by created_at limit 1;
  if v_person is null then
    r := public.rec_save('person', null, jsonb_build_object('name', coalesce(nullif(btrim(m.from_name), ''), split_part(m.from_addr, '@', 1)), 'email', lower(m.from_addr), 'source', 'email'));
    v_person := (r ->> 'id')::uuid;
    update app.email_thread_participants set person_id = v_person where thread_id = p_id and address = lower(m.from_addr);
  end if;
  r := public.rec_save('lead', null, jsonb_build_object('title', coalesce(nullif(btrim(t.subject), ''), m.from_addr), 'person_id', v_person, 'organization_id', v_org, 'source', 'email'));
  v_lead := (r ->> 'id')::uuid;
  insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) values (p_id, 'lead', v_lead, 'manual', v_me), (p_id, 'person', v_person, 'manual', v_me)
  on conflict do nothing;
  return jsonb_build_object('lead_id', v_lead, 'person_id', v_person);
end $fn$;

-- ---------------------------------------------------------------------------
-- compose and send
create function app.address_list(p jsonb) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
declare x jsonb; out jsonb := '[]'::jsonb; a text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return out; end if;
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 50 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recipients'; end if;
  for x in select * from jsonb_array_elements(p) loop
    a := lower(btrim(case when jsonb_typeof(x) = 'string' then x #>> '{}' else x ->> 'address' end));
    if a is null or a !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(a) > 254 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recipients';
    end if;
    out := out || jsonb_build_array(jsonb_build_object('address', a, 'name', case when jsonb_typeof(x) = 'object' then left(x ->> 'name', 200) end));
  end loop;
  return out;
end $fn$;

-- the internal send path shared by the composer, group sends, sequences and workflows. Validates the
-- mailbox, renders merge fields (a missing value refuses, COM-05), stores the message and queues it.
create function app.mail_enqueue(p_staff uuid, p_mailbox uuid, p_thread uuid, p_to jsonb, p_cc jsonb, p_bcc jsonb, p_subject text, p_body text,
                                 p_ctx jsonb, p_template uuid, p_track boolean, p_send_at timestamptz, p_source text,
                                 p_state text default null, p_group uuid default null, p_enrollment uuid default null, p_step uuid default null,
                                 p_link_entity text default null, p_link_record uuid default null, p_person uuid default null)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  mb app.mailboxes; v_thread uuid := p_thread; v_msg uuid; s jsonb; b jsonb; v_state text; v_track boolean;
  v_reply text; v_sample boolean := coalesce((select sandbox from app.admins where id = p_staff), false); x jsonb;
begin
  select * into mb from app.mailboxes where id = p_mailbox and deleted_at is null;
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mailbox'; end if;
  if mb.status not in ('syncing', 'synced') or mb.vault_secret_id is null then
    raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value', detail = mb.status;
  end if;
  if jsonb_array_length(coalesce(p_to, '[]'::jsonb)) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'to'; end if;
  s := app.merge_render(p_subject, p_ctx || jsonb_build_object('mailbox', p_mailbox));
  b := app.merge_render(p_body, p_ctx || jsonb_build_object('mailbox', p_mailbox));
  if jsonb_array_length(s -> 'unknown') + jsonb_array_length(b -> 'unknown') > 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || coalesce(s -> 'unknown' ->> 0, b -> 'unknown' ->> 0);
  end if;
  if jsonb_array_length(s -> 'missing') + jsonb_array_length(b -> 'missing') > 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge_missing:' || coalesce(s -> 'missing' ->> 0, b -> 'missing' ->> 0);
  end if;
  if char_length(btrim(s ->> 'text')) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  v_track := case app.setting('tracking') when 'on' then true when 'off' then false else coalesce(p_track, false) end;
  v_state := coalesce(p_state, case when p_send_at is not null and p_send_at > now() then 'scheduled' else 'queued' end);
  if v_thread is null then
    insert into app.email_threads (mailbox_id, subject, snippet, first_direction, created_by, is_sample)
    values (p_mailbox, s ->> 'text', left(regexp_replace(b ->> 'text', '\s+', ' ', 'g'), 300), 'out', p_staff, v_sample)
    returning id into v_thread;
    insert into app.email_thread_participants (thread_id, address, name, person_id)
    select v_thread, x2 ->> 'address', x2 ->> 'name', (select p.id from app.people p where lower(p.email) = x2 ->> 'address' and p.deleted_at is null order by p.created_at limit 1)
    from jsonb_array_elements(p_to || coalesce(p_cc, '[]'::jsonb)) x2 on conflict do nothing;
  else
    v_reply := (select m.rfc_message_id from app.email_messages m where m.thread_id = v_thread and m.state in ('sent', 'received') order by coalesce(m.received_at, m.sent_at) desc limit 1);
  end if;
  if p_link_entity is not null then
    insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) values (v_thread, p_link_entity, p_link_record, 'auto', p_staff) on conflict do nothing;
  end if;
  insert into app.email_messages (thread_id, mailbox_id, in_reply_to, direction, from_addr, from_name, to_addrs, cc, bcc, subject, body_text, source, state,
                                  scheduled_at, sent_by, template_id, tracking, track_token, group_send_id, enrollment_id, run_step_id, person_id, is_sample)
  values (v_thread, p_mailbox, v_reply, 'out', mb.address, coalesce(mb.display_name, (select a.name from app.admins a where a.id = p_staff)),
          p_to, coalesce(p_cc, '[]'::jsonb), coalesce(p_bcc, '[]'::jsonb), s ->> 'text', b ->> 'text', p_source, v_state,
          case when v_state = 'scheduled' then p_send_at end, p_staff, p_template, v_track, case when v_track then app.token() end,
          p_group, p_enrollment, p_step, p_person, v_sample)
  returning id into v_msg;
  -- links become tracked redirects when tracking is on
  if v_track then
    insert into app.email_tracking_links (message_id, url, token)
    select v_msg, u, app.token() from (select distinct (regexp_matches(b ->> 'text', '(https?://[^\s<>"'')\]]+)', 'g'))[1] u) s2 limit 50;
  end if;
  if v_state = 'queued' then perform pgmq.send('jobs', jsonb_build_object('job', 'mail_send', 'message_id', v_msg)); end if;
  return v_msg;
end $fn$;

-- the composer. draft: {thread_id?, mailbox_id, to, cc, bcc, subject, body, template_id, track, send_at, entity, record_id}
create function public.email_send(p_draft jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see'); v_mailbox uuid := (p_draft ->> 'mailbox_id')::uuid; v_thread uuid := (p_draft ->> 'thread_id')::uuid;
  v_entity text := p_draft ->> 'entity'; v_record uuid := (p_draft ->> 'record_id')::uuid; v_msg uuid; v_person uuid; e app.entities; v_ok boolean;
  v_to jsonb := app.address_list(p_draft -> 'to');
begin
  if v_mailbox is null or v_mailbox not in (select app.my_mailboxes()) then
    raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value', detail = 'none';
  end if;
  if v_thread is not null and not app.thread_visible(v_thread) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if v_entity is not null then
    if v_entity not in ('deal', 'lead', 'person', 'organization') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
    e := app.entity(v_entity);
    execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, v_record, app.vis_sql(e)) into v_ok;
    if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  v_person := (select p.id from app.people p where lower(p.email) = v_to -> 0 ->> 'address' and p.deleted_at is null order by p.created_at limit 1);
  v_msg := app.mail_enqueue(v_me, v_mailbox, v_thread, v_to, app.address_list(p_draft -> 'cc'), app.address_list(p_draft -> 'bcc'),
                            p_draft ->> 'subject', p_draft ->> 'body', app.merge_context(v_entity, v_record, v_person, v_me),
                            (p_draft ->> 'template_id')::uuid, (p_draft ->> 'track')::boolean, (p_draft ->> 'send_at')::timestamptz, 'crm',
                            null, null, null, null, v_entity, v_record, v_person);
  perform app.log('email.queued', 'email_message', v_msg::text, jsonb_build_object('scheduled', (p_draft ->> 'send_at') is not null));
  return jsonb_build_object('message_id', v_msg, 'thread_id', (select thread_id from app.email_messages where id = v_msg),
                            'state', (select state from app.email_messages where id = v_msg));
end $fn$;

-- change a message that has not been picked up yet (COM-08): cancel, reschedule, send now, retry, or send a reviewed one
create function public.email_change(p_id uuid, p_action text, p_at timestamptz default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); m app.email_messages;
begin
  select * into m from app.email_messages where id = p_id for update;
  if not found or (m.sent_by is distinct from v_me and not app.can('deals', 'edit_others')) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_action = 'cancel' and m.state in ('scheduled', 'queued', 'awaiting_review', 'failed') then
    update app.email_messages set state = 'canceled' where id = p_id;
  elsif p_action = 'reschedule' and m.state in ('scheduled', 'awaiting_review') and p_at > now() then
    update app.email_messages set state = 'scheduled', scheduled_at = p_at where id = p_id;
  elsif p_action = 'send_now' and m.state in ('scheduled', 'awaiting_review') then
    if not exists (select 1 from app.mailboxes mb where mb.id = m.mailbox_id and mb.status in ('syncing', 'synced')) then
      raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value';
    end if;
    update app.email_messages set state = 'queued', scheduled_at = null where id = p_id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'mail_send', 'message_id', p_id));
  elsif p_action = 'retry' and m.state = 'failed' then
    if not exists (select 1 from app.mailboxes mb where mb.id = m.mailbox_id and mb.status in ('syncing', 'synced')) then
      raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value';
    end if;
    update app.email_messages set state = 'queued', attempt = attempt + 1, failure_code = null, failure_reason = null where id = p_id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'mail_send', 'message_id', p_id));
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'action';
  end if;
  perform app.log('email.' || p_action, 'email_message', p_id::text, null);
  return jsonb_build_object('id', p_id, 'state', (select state from app.email_messages where id = p_id));
end $fn$;

-- the outbox: my scheduled, queued, sending, failed and review messages, and my group sends in progress
create function public.outbox_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  return jsonb_build_object(
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'thread_id', m.thread_id, 'subject', m.subject, 'to', m.to_addrs, 'state', m.state,
                                                              'scheduled_at', m.scheduled_at, 'failure_code', m.failure_code, 'failure_reason', m.failure_reason,
                                                              'attempt', m.attempt, 'source', m.source, 'created_at', m.created_at)
                                           order by coalesce(m.scheduled_at, m.created_at))
                          from app.email_messages m where m.sent_by = v_me and m.group_send_id is null
                            and m.state in ('scheduled', 'queued', 'sending', 'failed', 'awaiting_review')), '[]'::jsonb),
    'groups', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'subject', g.subject, 'total', g.total, 'state', g.state, 'created_at', g.created_at,
                                                            'sent', (select count(*) from app.email_messages m where m.group_send_id = g.id and m.state = 'sent'),
                                                            'failed', (select count(*) from app.email_messages m where m.group_send_id = g.id and m.state = 'failed'))
                                         order by g.created_at desc)
                        from app.group_sends g where g.created_by = v_me and g.state = 'sending'), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
-- group email (COM-07). Recipients come from a selection of people, a saved view of people, or deals
-- (their person). Consent follows sales_consent: off sends to all with an address; warn shows who would
-- be excluded but sends; block drops people without a basis or who unsubscribed or bounced.
create function app.group_recipients(p_source jsonb) returns table (person_id uuid, name text, email text, excluded text)
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_kind text := p_source ->> 'kind'; v_ids uuid[]; v_mode text := app.setting('sales_consent'); e app.entities; v_q jsonb;
begin
  if v_kind = 'people' then
    v_ids := array(select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(p_source -> 'ids', '[]'::jsonb)) x);
  elsif v_kind = 'deals' then
    v_ids := array(select d.person_id from app.deals d where d.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(p_source -> 'ids', '[]'::jsonb)) x)
                   and d.deleted_at is null and d.person_id is not null and app.visible(d.owner_id, d.visibility));
  elsif v_kind = 'view' then
    select sv.query into v_q from app.saved_views sv where sv.id = (p_source ->> 'view_id')::uuid and (sv.shared or sv.owner_id = app.me());
    if v_q is null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'view'; end if;
    e := app.entity('person');
    execute format('select array_agg(t.id) from app.people t where t.deleted_at is null and %s %s', app.vis_sql(e), app.filter_sql(e, v_q -> 'filters')) into v_ids;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
  end if;
  return query
    select p.id, p.name, lower(p.email),
      case when p.email is null then 'no_address'
           when v_mode <> 'off' and p.marketing_status in ('unsubscribed', 'bounced') then p.marketing_status
           when v_mode <> 'off' and not exists (select 1 from app.consent_events c where c.person_id = p.id and c.basis is not null) then 'no_basis'
           end
    from app.people p where p.id = any (coalesce(v_ids, '{}')) and p.deleted_at is null and app.visible(p.owner_id, p.visibility)
    order by p.name;
end $fn$;

create function public.group_send_preview(p_source jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'bulk'); v_limit numeric;
begin
  v_limit := case when app.setting('count_limits') = 'number' then (select value_number from app.setting_values where key = 'count_limits' and scope_id = '') end;
  return jsonb_build_object(
    'consent_mode', app.setting('sales_consent'), 'limit', v_limit,
    'recipients', coalesce((select jsonb_agg(jsonb_build_object('person_id', r.person_id, 'name', r.name, 'email', r.email, 'excluded', r.excluded))
                            from app.group_recipients(p_source) r), '[]'::jsonb));
end $fn$;

-- start: one message per recipient, staggered by the mailbox's throttle
create function public.group_send_start(p_source jsonb, p_mailbox uuid, p_subject text, p_body text, p_template uuid default null, p_track boolean default null)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'bulk'); v_mode text := app.setting('sales_consent'); mb app.mailboxes; v_group uuid; r record; i int := 0;
  v_limit numeric; v_send int; v_excluded jsonb;
begin
  if p_mailbox is null or p_mailbox not in (select app.my_mailboxes()) then
    raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value', detail = 'none';
  end if;
  select * into mb from app.mailboxes where id = p_mailbox;
  if mb.status <> 'synced' then raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value', detail = mb.status; end if;
  select count(*) filter (where excluded is null or (v_mode = 'warn' and excluded <> 'no_address')),
         coalesce(jsonb_agg(jsonb_build_object('person_id', person_id, 'reason', excluded)) filter (where excluded is not null), '[]'::jsonb)
    into v_send, v_excluded from app.group_recipients(p_source);
  v_limit := case when app.setting('count_limits') = 'number' then (select value_number from app.setting_values where key = 'count_limits' and scope_id = '') end;
  if v_limit is not null and v_send > v_limit then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'limit'; end if;
  if v_send = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recipients'; end if;
  insert into app.group_sends (mailbox_id, template_id, subject, source_kind, source_ref, total, excluded, consent_mode, created_by, is_sample)
  values (p_mailbox, p_template, p_subject, p_source ->> 'kind', p_source - 'kind', v_send, v_excluded, v_mode, v_me, (select sandbox from app.admins where id = v_me))
  returning id into v_group;
  for r in select * from app.group_recipients(p_source) where excluded is null or (v_mode = 'warn' and excluded <> 'no_address') loop
    perform app.mail_enqueue(v_me, p_mailbox, null, jsonb_build_array(jsonb_build_object('address', r.email, 'name', r.name)), null, null, p_subject, p_body,
                             app.merge_context('person', r.person_id, r.person_id, v_me), p_template, p_track,
                             now() + make_interval(secs => (i * 60.0 / mb.throttle_per_min)), 'group', 'scheduled', v_group, null, null, 'person', r.person_id, r.person_id);
    i := i + 1;
  end loop;
  perform app.log('group_send.started', 'group_send', v_group::text, jsonb_build_object('total', v_send, 'excluded', jsonb_array_length(v_excluded)));
  return jsonb_build_object('id', v_group, 'total', v_send, 'excluded', jsonb_array_length(v_excluded));
end $fn$;

-- ---------------------------------------------------------------------------
-- AI insight on request (AIA-04). The worker calls Claude with the thread and writes the result back; the
-- app shows «AI not configured» when the key is absent and never calls this.
create function public.thread_insight_request(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'ai');
begin
  if not app.thread_visible(p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.email_thread_insights (thread_id, state, requested_by, requested_at) values (p_id, 'requested', v_me, now())
  on conflict (thread_id) do update set state = 'requested', requested_by = v_me, requested_at = now();
  perform pgmq.send('jobs', jsonb_build_object('job', 'ai_thread_insight', 'thread_id', p_id));
  perform app.log('ai.thread_insight', 'email_thread', p_id::text, null);
  return jsonb_build_object('id', p_id, 'state', 'requested');
end $fn$;

-- ---------------------------------------------------------------------------
-- worker functions (service role only): the mail adapters report what the provider did

-- a connected mailbox: the OAuth callback stores the token in Vault and registers the mailbox
create function public.worker_mailbox_connected(p_staff uuid, p_kind text, p_provider text, p_address text, p_token text, p_display_name text default null)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; v_secret uuid; v_old uuid;
begin
  if not exists (select 1 from app.admins where id = p_staff and active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'staff'; end if;
  select id, vault_secret_id into v_id, v_old from app.mailboxes where address = lower(p_address);
  if v_old is not null then delete from vault.secrets where id = v_old; end if;
  v_secret := vault.create_secret(p_token, 'mailbox:' || lower(p_address) || ':' || extract(epoch from now())::bigint, 'Mailbox OAuth token (0020): read by the mail worker only.');
  insert into app.mailboxes (kind, provider, address, display_name, owner_id, status, vault_secret_id, sync_from)
  values (coalesce(p_kind, 'personal'), p_provider, lower(p_address), p_display_name, p_staff, 'syncing', v_secret, current_date - 90)
  on conflict (address) do update set provider = excluded.provider, status = 'syncing', status_detail = null, vault_secret_id = excluded.vault_secret_id,
    owner_id = coalesce(app.mailboxes.owner_id, excluded.owner_id), deleted_at = null
  returning id into v_id;
  insert into app.audit (actor, action, target_type, target_id, detail, ok) values ('system', 'mailbox.connected', 'mailbox', v_id::text, jsonb_build_object('provider', p_provider), true);
  perform pgmq.send('jobs', jsonb_build_object('job', 'mail_sync', 'mailbox_id', v_id));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.worker_mailbox_token(p_mailbox uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from app.mailboxes m join vault.decrypted_secrets s on s.id = m.vault_secret_id where m.id = p_mailbox and m.deleted_at is null
$fn$;

create function public.worker_mailbox_status(p_mailbox uuid, p_status text, p_detail text default null, p_cursor text default null, p_watch_expires timestamptz default null)
  returns void language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_owner uuid;
begin
  update app.mailboxes set status = p_status, status_detail = left(p_detail, 300), sync_cursor = coalesce(p_cursor, sync_cursor),
    watch_expires_at = coalesce(p_watch_expires, watch_expires_at), last_synced_at = case when p_status = 'synced' then now() else last_synced_at end
  where id = p_mailbox returning owner_id into v_owner;
  if p_status = 'reauth' and v_owner is not null then
    perform app.notify(v_owner, 'system', 'mail.reauth', jsonb_build_object('mailbox', p_mailbox), '/inbox');
  end if;
end $fn$;

-- the message the send worker needs, and its claim (queued → sending)
create function public.worker_mail_claim(p_message uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.email_messages;
begin
  update app.email_messages set state = 'sending' where id = p_message and state = 'queued' returning * into m;
  if not found then return null; end if;
  return jsonb_build_object('id', m.id, 'mailbox_id', m.mailbox_id, 'thread_id', m.thread_id,
    'provider_thread_id', (select t.provider_thread_id from app.email_threads t where t.id = m.thread_id),
    'in_reply_to', m.in_reply_to, 'from', m.from_addr, 'from_name', m.from_name, 'to', m.to_addrs, 'cc', m.cc, 'bcc', m.bcc, 'subject', m.subject,
    'body_text', m.body_text, 'signature', (select mb.signature from app.mailboxes mb where mb.id = m.mailbox_id),
    'track_token', m.track_token, 'links', coalesce((select jsonb_agg(jsonb_build_object('url', l.url, 'token', l.token)) from app.email_tracking_links l where l.message_id = m.id), '[]'::jsonb),
    'attachments', coalesce((select jsonb_agg(jsonb_build_object('path', a.storage_path, 'filename', a.filename, 'mime', a.mime)) from app.email_attachments a where a.message_id = m.id), '[]'::jsonb));
end $fn$;

-- sent: the activity of type email is written now (COM-02), and email.sent is emitted
create function public.worker_mail_sent(p_message uuid, p_provider_message_id text, p_provider_thread_id text, p_rfc_message_id text)
  returns void language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.email_messages; v_act uuid; v_deal uuid; v_person uuid; v_org uuid;
begin
  update app.email_messages set state = 'sent', sent_at = now(), provider_message_id = p_provider_message_id, rfc_message_id = p_rfc_message_id
  where id = p_message and state = 'sending' returning * into m;
  if not found then return; end if;
  update app.email_threads set provider_thread_id = coalesce(provider_thread_id, p_provider_thread_id), last_direction = 'out', last_message_at = now(),
    first_direction = coalesce(first_direction, 'out'), snippet = left(regexp_replace(coalesce(m.body_text, ''), '\s+', ' ', 'g'), 300)
  where id = m.thread_id;
  v_deal := (select l.record_id from app.email_links l where l.thread_id = m.thread_id and l.entity = 'deal' order by l.created_at limit 1);
  v_person := coalesce(m.person_id, (select p.person_id from app.email_thread_participants p where p.thread_id = m.thread_id and p.person_id is not null limit 1));
  v_org := coalesce((select d.organization_id from app.deals d where d.id = v_deal), (select pe.organization_id from app.people pe where pe.id = v_person));
  insert into app.activities (type_id, subject, starts_at, done, done_at, done_by, deal_id, person_id, organization_id, owner_id, created_by, updated_by, is_sample)
  values ((select id from app.activity_types where key = 'email'), left(coalesce(nullif(m.subject, ''), '(no subject)'), 200), now(), true, now(), m.sent_by,
          v_deal, v_person, v_org, m.sent_by, m.sent_by, m.sent_by, m.is_sample)
  returning id into v_act;
  update app.email_messages set activity_id = v_act where id = p_message;
  if v_deal is not null then update app.deals set last_activity_at = now() where id = v_deal; end if;
  if m.group_send_id is not null and not exists (select 1 from app.email_messages x where x.group_send_id = m.group_send_id and x.state in ('scheduled', 'queued', 'sending')) then
    update app.group_sends set state = 'done' where id = m.group_send_id;
  end if;
  insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
  values ('email.sent', 'email_thread', m.thread_id, m.sent_by,
          jsonb_build_object('message', m.id, 'links', app.thread_links(m.thread_id), 'source', m.source, 'enrollment', m.enrollment_id, 'step', m.run_step_id), m.is_sample);
end $fn$;

create function public.worker_mail_failed(p_message uuid, p_code text, p_reason text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.email_messages;
begin
  update app.email_messages set state = 'failed', failure_code = left(p_code, 60), failure_reason = left(p_reason, 300)
  where id = p_message and state in ('sending', 'queued') returning * into m;
  if not found then return; end if;
  if m.sent_by is not null and m.group_send_id is null then
    perform app.notify(m.sent_by, 'system', 'mail.failed', jsonb_build_object('subject', m.subject, 'code', m.failure_code), '/inbox');
  end if;
  insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
  values ('email.failed', 'email_thread', m.thread_id, m.sent_by, jsonb_build_object('message', m.id, 'code', m.failure_code, 'enrollment', m.enrollment_id, 'step', m.run_step_id), m.is_sample);
end $fn$;

-- synced mail from the provider: threads and messages upserted, participants matched to people, threads
-- auto-linked to the person's open deal or lead, email.received emitted for each new inbound message.
-- p_messages: [{provider_thread_id, provider_message_id, rfc_message_id, in_reply_to, direction, from, from_name, to, cc, subject, body_text, body_html, at, archived}]
create function public.worker_mail_ingest(p_mailbox uuid, p_messages jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  mb app.mailboxes; x jsonb; v_thread uuid; v_msg uuid; n_new int := 0; a jsonb; v_person uuid; v_deal uuid; v_lead uuid; v_dir text; v_at timestamptz;
begin
  select * into mb from app.mailboxes where id = p_mailbox and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_messages, '[]'::jsonb)) loop
    if exists (select 1 from app.email_messages where mailbox_id = p_mailbox and provider_message_id = x ->> 'provider_message_id') then continue; end if;
    v_dir := case when x ->> 'direction' = 'out' then 'out' else 'in' end;
    v_at := coalesce((x ->> 'at')::timestamptz, now());
    insert into app.email_threads (mailbox_id, provider_thread_id, subject, first_direction, is_sample)
    values (p_mailbox, x ->> 'provider_thread_id', left(coalesce(x ->> 'subject', ''), 500), v_dir, mb.is_sample)
    on conflict (mailbox_id, provider_thread_id) do update set subject = app.email_threads.subject
    returning id into v_thread;
    insert into app.email_messages (thread_id, mailbox_id, provider_message_id, rfc_message_id, in_reply_to, direction, from_addr, from_name, to_addrs, cc,
                                    subject, body_text, body_html, source, state, sent_at, received_at, is_sample)
    values (v_thread, p_mailbox, x ->> 'provider_message_id', left(x ->> 'rfc_message_id', 500), left(x ->> 'in_reply_to', 500), v_dir,
            lower(left(x ->> 'from', 254)), left(x ->> 'from_name', 200), coalesce(x -> 'to', '[]'::jsonb), coalesce(x -> 'cc', '[]'::jsonb),
            left(coalesce(x ->> 'subject', ''), 500), left(x ->> 'body_text', 200000), left(x ->> 'body_html', 500000), 'sync',
            case v_dir when 'in' then 'received' else 'sent' end, case when v_dir = 'out' then v_at end, case when v_dir = 'in' then v_at end, mb.is_sample)
    returning id into v_msg;
    update app.email_threads set last_direction = case when last_message_at is null or v_at >= last_message_at then v_dir else last_direction end,
      last_message_at = greatest(coalesce(last_message_at, v_at), v_at),
      snippet = case when last_message_at is null or v_at >= last_message_at then left(regexp_replace(coalesce(x ->> 'body_text', ''), '\s+', ' ', 'g'), 300) else snippet end,
      archived_at = case when (x ->> 'archived')::boolean then coalesce(archived_at, now()) when v_dir = 'in' then null else archived_at end
    where id = v_thread;
    -- participants and matching
    for a in select * from jsonb_array_elements(jsonb_build_array(jsonb_build_object('address', x ->> 'from', 'name', x ->> 'from_name'))
                                                 || coalesce(x -> 'to', '[]'::jsonb) || coalesce(x -> 'cc', '[]'::jsonb)) loop
      continue when lower(a ->> 'address') = mb.address or coalesce(a ->> 'address', '') = '';
      v_person := (select p.id from app.people p where lower(p.email) = lower(a ->> 'address') and p.deleted_at is null order by p.created_at limit 1);
      insert into app.email_thread_participants (thread_id, address, name, person_id)
      values (v_thread, lower(left(a ->> 'address', 254)), left(a ->> 'name', 200), v_person)
      on conflict (thread_id, address) do update set person_id = coalesce(app.email_thread_participants.person_id, excluded.person_id);
      if v_person is not null then
        insert into app.email_links (thread_id, entity, record_id, linked_by) values (v_thread, 'person', v_person, 'auto') on conflict do nothing;
        v_deal := (select d.id from app.deals d where d.deleted_at is null and d.status = 'open'
                   and (d.person_id = v_person or d.id in (select dp.deal_id from app.deal_participants dp where dp.person_id = v_person))
                   order by d.updated_at desc limit 1);
        if v_deal is not null then
          insert into app.email_links (thread_id, entity, record_id, linked_by) values (v_thread, 'deal', v_deal, 'auto') on conflict do nothing;
        else
          v_lead := (select l.id from app.leads l where l.deleted_at is null and l.archived_at is null and l.converted_at is null and l.person_id = v_person order by l.updated_at desc limit 1);
          if v_lead is not null then
            insert into app.email_links (thread_id, entity, record_id, linked_by) values (v_thread, 'lead', v_lead, 'auto') on conflict do nothing;
          end if;
        end if;
        update app.people set last_touch_at = greatest(coalesce(last_touch_at, v_at), v_at) where id = v_person;
      end if;
    end loop;
    if v_dir = 'in' then
      n_new := n_new + 1;
      insert into app.events (kind, subject_type, subject_id, payload, is_sample)
      values ('email.received', 'email_thread', v_thread, jsonb_build_object('message', v_msg, 'mailbox', p_mailbox, 'links', app.thread_links(v_thread)), mb.is_sample);
      if mb.owner_id is not null then
        perform app.notify(mb.owner_id, 'system', 'mail.received', jsonb_build_object('thread', v_thread), '/inbox', 'email_thread', v_thread);
      end if;
    end if;
  end loop;
  update app.mailboxes set last_synced_at = now(), status = case when status in ('connecting', 'syncing') then 'synced' else status end where id = p_mailbox;
  return jsonb_build_object('new_inbound', n_new);
end $fn$;

-- an open or a click from the public tracking endpoint. No IP is stored; the sender is notified.
create function public.worker_track(p_token text, p_kind text, p_client_class text default 'unknown') returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.email_messages; l app.email_tracking_links;
begin
  if p_kind = 'click' then
    select * into l from app.email_tracking_links where token = p_token;
    if not found then return null; end if;
    select * into m from app.email_messages where id = l.message_id;
  elsif p_kind = 'open' then
    select * into m from app.email_messages where track_token = p_token;
    if not found then return null; end if;
  else
    return null;
  end if;
  if m.state <> 'sent' then return l.url; end if;
  insert into app.email_tracking_events (message_id, link_id, kind, client_class)
  values (m.id, l.id, p_kind, case when p_client_class in ('human', 'prefetch') then p_client_class else 'unknown' end);
  if coalesce(p_client_class, 'unknown') <> 'prefetch' then
    insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
    values (case p_kind when 'open' then 'email.opened' else 'email.clicked' end, 'email_thread', m.thread_id, null,
            jsonb_build_object('message', m.id, 'links', app.thread_links(m.thread_id), 'label', coalesce(l.label, l.url), 'enrollment', m.enrollment_id), m.is_sample);
    if m.sent_by is not null then
      perform app.notify(m.sent_by, 'system', case p_kind when 'open' then 'mail.opened' else 'mail.clicked' end,
                         jsonb_build_object('subject', m.subject, 'label', l.label), '/inbox', 'email_thread', m.thread_id);
    end if;
  end if;
  return l.url;
end $fn$;

create function public.worker_insight_done(p_thread uuid, p_result jsonb) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.email_thread_insights set
    state = case when p_result ? 'error' then 'failed' else 'ready' end,
    summary = left(p_result ->> 'summary', 4000),
    sentiment = case when p_result ->> 'sentiment' in ('positive', 'neutral', 'negative') then p_result ->> 'sentiment' end,
    readiness = case when (p_result ->> 'readiness') ~ '^\d+$' and (p_result ->> 'readiness')::int between 1 and 10 then (p_result ->> 'readiness')::smallint end,
    reason = left(p_result ->> 'reason', 1000),
    action_items = case when jsonb_typeof(p_result -> 'action_items') = 'array' then p_result -> 'action_items' else '[]'::jsonb end,
    suggested_replies = case when jsonb_typeof(p_result -> 'suggested_replies') = 'array' then p_result -> 'suggested_replies' else '[]'::jsonb end,
    model = left(p_result ->> 'model', 80),
    upto_message_id = (select m.id from app.email_messages m where m.thread_id = p_thread and m.state in ('sent', 'received') order by coalesce(m.received_at, m.sent_at) desc limit 1),
    generated_at = now()
  where thread_id = p_thread;
end $fn$;

-- ---------------------------------------------------------------------------
-- jobs: due scheduled messages move to the queue every minute
create function app.mail_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  for r in select m.id from app.email_messages m join app.mailboxes mb on mb.id = m.mailbox_id
           where m.state = 'scheduled' and m.scheduled_at <= now() and mb.status in ('syncing', 'synced') order by m.scheduled_at limit 500 for update of m skip locked loop
    update app.email_messages set state = 'queued' where id = r.id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'mail_send', 'message_id', r.id));
    n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-mail-due', '* * * * *', 'select app.mail_due()');

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['mailboxes', 'mailbox_members', 'sender_aliases', 'dropbox_addresses', 'email_threads', 'email_thread_reads',
                           'email_thread_participants', 'email_templates', 'group_sends', 'email_messages', 'email_attachments', 'email_links',
                           'email_tracking_links', 'email_tracking_events', 'merge_fields', 'email_thread_insights'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.entity_route(text)', 'app.thread_visible(uuid)', 'app.my_mailboxes()', 'app.token()', 'app.thread_links(uuid)', 'app.thread_status(app.email_threads)',
                           'app.thread_unread(uuid, uuid)', 'app.thread_link_titles(uuid)', 'app.merge_context(text, uuid, uuid, uuid, uuid)',
                           'app.merge_value(text, jsonb)', 'app.merge_render(text, jsonb)', 'app.thread_row(app.email_threads, uuid)', 'app.address_list(jsonb)',
                           'app.mail_enqueue(uuid, uuid, uuid, jsonb, jsonb, jsonb, text, text, jsonb, uuid, boolean, timestamptz, text, text, uuid, uuid, uuid, text, uuid, uuid)',
                           'app.group_recipients(jsonb)', 'app.mail_due()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.merge_fields_get()', 'public.merge_preview(text, text, text, uuid, uuid, uuid)', 'public.templates_get()',
                           'public.template_save(uuid, jsonb)', 'public.template_delete(uuid)', 'public.mailboxes_get()', 'public.mailbox_update(uuid, jsonb)',
                           'public.mailbox_members_set(uuid, jsonb)', 'public.mailbox_disconnect(uuid)', 'public.sender_alias_add(text, text)',
                           'public.sender_alias_remove(uuid)', 'public.dropbox_address_get(text, uuid)', 'public.inbox_folders()', 'public.threads_get(text, jsonb)',
                           'public.thread_get(uuid)', 'public.thread_archive(uuid, boolean)', 'public.thread_link(uuid, text, uuid, boolean)',
                           'public.thread_to_lead(uuid)', 'public.email_send(jsonb)', 'public.email_change(uuid, text, timestamptz)', 'public.outbox_get()',
                           'public.group_send_preview(jsonb)', 'public.group_send_start(jsonb, uuid, text, text, uuid, boolean)', 'public.thread_insight_request(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_mailbox_connected(uuid, text, text, text, text, text)', 'public.worker_mailbox_token(uuid)',
                           'public.worker_mailbox_status(uuid, text, text, text, timestamptz)', 'public.worker_mail_claim(uuid)',
                           'public.worker_mail_sent(uuid, text, text, text)', 'public.worker_mail_failed(uuid, text, text)',
                           'public.worker_mail_ingest(uuid, jsonb)', 'public.worker_track(text, text, text)', 'public.worker_insight_done(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
