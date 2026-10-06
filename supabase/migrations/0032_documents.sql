-- 0032_documents.sql — documents, document templates, trackable links and e-signature (DOC-01..06, UF-08, SF-20, SF-33).
-- Spec: docs/crm-enrichment/specs/marketing-documents.md §2, §4 (documents and e-signature), §5, §6, §7, §10, §11.
--
-- A document is made from a template on a deal (or uploaded onto one). Creating it renders the merge fields and
-- the deal's product table into its body, records the merge fields that have no value (they block sending, not
-- creation, DOC-01) and numbers it from a per-prefix counter. A document is visible exactly when its deal is (or,
-- without a deal, its organisation): there is no separate document visibility to keep in step (SF-33).
--
-- Public links (D-28, Q1): go.owntheagenda.com/d/<token> to view and /s/<token> to sign. A token is random, is
-- returned once to whoever made it (the link creator, or the invitation worker) and only its SHA-256 is stored.
-- A view records when and for how long, and never an IP address, a city or a «forwarded» guess (D-37, §10).
--
-- Built-in signing is a simple electronic signature (Q9): the signer's link plus a one-time code to their email,
-- stored hashed, at most five attempts. Every step is a row in signature_events, an append-only hash chain:
-- hash = sha256(prev_hash || canonical row). The chain verifies with app.signature_chain_ok.
--
-- Providers. PDF rendering and sealing need a worker that does not exist yet (Q11): until a document has a pdf_path
-- and its hash, document_file_url and signature_request_send answer not_connected (pdf). Drives (Google, Microsoft)
-- have no OAuth client: connecting, importing and choosing a drive as the default answer not_connected. Sending the
-- signing invitations needs the email provider, the external service the esign adapter (both registered in 0030).
--
-- Logs. No document body, decline reason or signer text is written to app.audit, the changelog or app.events: those
-- carry ids, kinds and counts.
--
-- Also here: the merge-field registry learns contexts and the document tokens (Q5), and the engine matches a
-- workflow's event against the full event kind as well as its suffix (§7 «Full-kind matching»), so a workflow on
-- deal with event «document.completed» starts when a contract is signed (UF-08 step 6).

-- ---------------------------------------------------------------------------
-- merge fields: contexts and the document tokens (Q5). The Norwegian tokens stay as aliases.
alter table app.merge_fields drop constraint merge_fields_token_check;
alter table app.merge_fields add constraint merge_fields_token_check check (token ~ '^[A-Za-zÆØÅæøå]+\.[A-Za-z0-9ÆØÅæøå_]+$');
alter table app.merge_fields drop constraint merge_fields_format_check;
alter table app.merge_fields add constraint merge_fields_format_check
  check (format in ('text', 'first_word', 'nok', 'int', 'url', 'block', 'orgnr', 'date'));
alter table app.merge_fields add column contexts text[] not null default '{email}'
  check (cardinality(contexts) >= 1 and contexts <@ array['email', 'campaign', 'document']);

update app.merge_fields set contexts = array['email', 'campaign', 'document'] where source_path not in ('staff.booking_link', 'mailbox.signature');
update app.merge_fields set contexts = array['email', 'campaign'] where source_path = 'staff.booking_link';

insert into app.merge_fields (token, source_path, format, ord, contexts) values
  ('Organisasjon.orgnr', 'organization.org_number', 'orgnr', 52, array['email', 'campaign', 'document']),
  ('Organisasjon.adresse', 'organization.address', 'text', 54, array['email', 'campaign', 'document']),
  ('Organisasjon.postnummer', 'organization.postal_code', 'text', 56, array['email', 'campaign', 'document']),
  ('Organisasjon.poststed', 'organization.city', 'text', 58, array['email', 'campaign', 'document']),
  ('Avtale.valuta', 'deal.currency', 'text', 75, array['email', 'campaign', 'document']),
  ('deal.title', 'deal.title', 'text', 200, array['email', 'campaign', 'document']),
  ('deal.value', 'deal.value', 'nok', 210, array['email', 'campaign', 'document']),
  ('deal.currency', 'deal.currency', 'text', 220, array['email', 'campaign', 'document']),
  ('person.name', 'person.name', 'text', 230, array['email', 'campaign', 'document']),
  ('person.email', 'person.email', 'text', 240, array['email', 'campaign', 'document']),
  ('organization.name', 'organization.name', 'text', 250, array['email', 'campaign', 'document']),
  ('organization.orgnr', 'organization.org_number', 'orgnr', 260, array['email', 'campaign', 'document']),
  ('organization.employees', 'organization.employees', 'int', 270, array['email', 'campaign', 'document']),
  ('organization.address', 'organization.address', 'text', 280, array['email', 'campaign', 'document']),
  ('organization.postal_code', 'organization.postal_code', 'text', 290, array['email', 'campaign', 'document']),
  ('organization.city', 'organization.city', 'text', 300, array['email', 'campaign', 'document']),
  ('document.number', 'document.number', 'text', 310, array['document']),
  ('document.date', 'document.created_at', 'date', 320, array['document']),
  ('document.valid_until', 'document.valid_until', 'date', 330, array['document']),
  ('product.table', 'product.table', 'block', 340, array['document']);
-- [signer.N] is not a merge field: it anchors a signature field for the E-signature tab. [project.*] stays unknown
-- until Projects (phase 6).

-- ---------------------------------------------------------------------------
-- tables
create table app.document_templates (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(btrim(name)) between 1 and 120),
  kind             text not null default 'document' check (kind in ('document', 'presentation', 'spreadsheet')),
  category         text not null default 'other' check (category in ('quotes', 'contracts', 'presentations', 'spreadsheets', 'other')),
  share            text not null default 'private' check (share in ('company', 'team', 'private')),
  team_id          uuid references app.teams (id) on delete set null,
  product          text references app.products (key),
  language         text not null default 'nb' check (language in ('nb', 'nn', 'en', 'sv')),
  source           text not null default 'platform' check (source in ('platform', 'google', 'microsoft')),
  external_file_id text check (external_file_id is null or char_length(external_file_id) <= 300),
  body_html        text check (body_html is null or char_length(body_html) <= 500000),
  product_table    jsonb check (product_table is null or jsonb_typeof(product_table) = 'object'),
  validity_days    int check (validity_days is null or validity_days between 1 and 365),
  number_prefix    text check (number_prefix is null or number_prefix ~ '^[A-Z]{1,4}-$'),
  placeholders     text[] not null default '{}',
  current_version  int not null default 1,
  owner_id         uuid references app.admins (id) on delete set null,
  visibility       text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels           uuid[] not null default '{}',
  custom           jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample        boolean not null default false,
  version          int not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  deleted_at       timestamptz,
  -- a team template whose team is removed becomes private (app.doc_template_guard)
  constraint document_templates_team check ((share = 'team') = (team_id is not null)),
  constraint document_templates_kind_source check (kind = 'document' or source <> 'platform'),
  constraint document_templates_spreadsheet check (kind <> 'spreadsheet' or product_table is null)
);
create index document_templates_share on app.document_templates (share, team_id) where deleted_at is null;

create table app.document_template_versions (
  template_id   uuid not null references app.document_templates (id) on delete cascade,
  version       int not null check (version >= 1),
  body_html     text,
  product_table jsonb,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  primary key (template_id, version)
);

-- the next number per prefix (T- → T-1, T-2 …); a number is never reused
create table app.document_counters (
  prefix text primary key check (prefix ~ '^[A-Z]{1,4}-$'),
  next   int not null default 1 check (next >= 1)
);

create table app.documents (
  id               uuid primary key default gen_random_uuid(),
  number           text unique check (number is null or char_length(number) <= 20),
  name             text not null check (char_length(btrim(name)) between 1 and 200),
  template_id      uuid references app.document_templates (id) on delete set null,
  template_version int,
  kind             text not null default 'document' check (kind in ('document', 'presentation', 'spreadsheet')),
  source           text not null check (source in ('template', 'upload')),
  deal_id          uuid references app.deals (id) on delete set null,
  organization_id  uuid references app.organizations (id) on delete set null,
  person_id        uuid references app.people (id) on delete set null,
  product          text references app.products (key),
  status           text not null default 'draft'
                   check (status in ('draft', 'sent', 'opened', 'awaiting_signature', 'signed', 'declined', 'expired', 'revoked')),
  body_html        text check (body_html is null or char_length(body_html) <= 1000000),
  merge_missing    text[] not null default '{}',
  totals           jsonb check (totals is null or jsonb_typeof(totals) = 'object'),
  valid_until      date,
  storage          text not null default 'platform' check (storage in ('platform', 'google', 'onedrive', 'sharepoint')),
  external_file_id text check (external_file_id is null or char_length(external_file_id) <= 300),
  external_url     text check (external_url is null or (external_url ~ '^https://' and char_length(external_url) <= 2000)),
  pdf_path         text check (pdf_path is null or (char_length(pdf_path) <= 500 and pdf_path !~ '\.\.')),
  pdf_sha256       bytea check (pdf_sha256 is null or length(pdf_sha256) = 32),
  size_bytes       bigint check (size_bytes is null or size_bytes between 0 and 26214400),
  sent_at          timestamptz,
  first_opened_at  timestamptz,
  last_opened_at   timestamptz,
  signed_at        timestamptz,
  owner_id         uuid references app.admins (id) on delete set null,
  visibility       text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels           uuid[] not null default '{}',
  custom           jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample        boolean not null default false,
  version          int not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  deleted_at       timestamptz
);
create index documents_deal on app.documents (deal_id) where deleted_at is null;
create index documents_org on app.documents (organization_id) where deleted_at is null;
create index documents_status on app.documents (status) where deleted_at is null;

create table app.document_links (
  id                  uuid primary key default gen_random_uuid(),
  document_id         uuid not null references app.documents (id) on delete cascade,
  token_sha256        bytea not null unique check (length(token_sha256) = 32),
  recipient_person_id uuid references app.people (id) on delete set null,
  label               text check (label is null or char_length(label) <= 120),
  notify_owner        boolean not null default true,
  expires_at          timestamptz,
  revoked_at          timestamptz,
  created_by          uuid,
  created_at          timestamptz not null default now()
);
create index document_links_document on app.document_links (document_id);

-- a view: when, for how long, and whether a person or a link scanner opened it. No IP, no city.
create table app.document_views (
  id               bigint generated always as identity primary key,
  link_id          uuid not null references app.document_links (id) on delete cascade,
  document_id      uuid not null references app.documents (id) on delete cascade,
  started_at       timestamptz not null default now(),
  duration_seconds int not null default 0 check (duration_seconds between 0 and 86400),
  client_class     text not null default 'unknown' check (client_class in ('human', 'prefetch', 'unknown'))
);
create index document_views_link on app.document_views (link_id, started_at desc);
create index document_views_document on app.document_views (document_id, started_at desc);

create table app.signature_requests (
  id              uuid primary key default gen_random_uuid(),
  document_id     uuid not null references app.documents (id) on delete cascade,
  status          text not null default 'draft' check (status in ('draft', 'sent', 'in_progress', 'completed', 'declined', 'canceled', 'expired')),
  service         text not null default 'builtin' check (service in ('builtin', 'external')),
  external_id     text unique check (external_id is null or char_length(external_id) <= 200),
  message         text check (message is null or char_length(message) <= 2000),
  language        text not null default 'nb' check (language in ('nb', 'en', 'sv')),
  otp_required    boolean not null default true,
  signing_order   text not null default 'parallel' check (signing_order in ('parallel', 'sequential')),
  expires_at      timestamptz,
  original_sha256 bytea check (original_sha256 is null or length(original_sha256) = 32),
  sealed_pdf_path text check (sealed_pdf_path is null or char_length(sealed_pdf_path) <= 500),
  sealed_sha256   bytea check (sealed_sha256 is null or length(sealed_sha256) = 32),
  evidence_path   text check (evidence_path is null or char_length(evidence_path) <= 500),
  sent_at         timestamptz,
  completed_at    timestamptz,
  created_by      uuid,
  version         int not null default 1,
  is_sample       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index signature_requests_document on app.signature_requests (document_id);
create index signature_requests_open on app.signature_requests (expires_at) where status in ('sent', 'in_progress');

create table app.signature_signers (
  id             uuid primary key default gen_random_uuid(),
  request_id     uuid not null references app.signature_requests (id) on delete cascade,
  ord            int not null check (ord >= 1),
  person_id      uuid references app.people (id) on delete set null,
  name           text not null check (char_length(btrim(name)) between 1 and 200),
  email          text not null check (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+$'),
  color          text check (color is null or color ~ '^#[0-9A-F]{6}$'),
  status         text not null default 'waiting' check (status in ('waiting', 'sent', 'opened', 'code_verified', 'signed', 'declined')),
  token_sha256   bytea unique check (token_sha256 is null or length(token_sha256) = 32),
  otp_hash       bytea check (otp_hash is null or length(otp_hash) = 32),
  otp_expires_at timestamptz,
  otp_attempts   smallint not null default 0 check (otp_attempts between 0 and 5),
  invited_at     timestamptz,
  opened_at      timestamptz,
  verified_at    timestamptz,
  signed_at      timestamptz,
  declined_at    timestamptz,
  decline_reason text check (decline_reason is null or char_length(decline_reason) <= 500),
  unique (request_id, ord)
);

create table app.signature_fields (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references app.signature_requests (id) on delete cascade,
  signer_id  uuid not null references app.signature_signers (id) on delete cascade,
  kind       text not null check (kind in ('signature', 'date', 'initials', 'text', 'checkbox')),
  page       int not null default 1 check (page >= 1),
  x          numeric(5, 2) not null check (x between 0 and 100),
  y          numeric(5, 2) not null check (y between 0 and 100),
  w          numeric(5, 2) not null check (w between 0 and 100),
  h          numeric(5, 2) not null check (h between 0 and 100),
  required   boolean not null default true,
  value      text check (value is null or char_length(value) <= 500),
  filled_at  timestamptz,
  check (x + w <= 100 and y + h <= 100)
);
create index signature_fields_signer on app.signature_fields (signer_id);

-- the evidence: append-only, hash-chained per request, no IP. seq orders the chain under a lock on the request.
create table app.signature_events (
  id              bigint generated always as identity primary key,
  request_id      uuid not null references app.signature_requests (id) on delete cascade,
  seq             int not null,
  signer_id       uuid,
  kind            text not null check (kind in ('created', 'sent', 'opened', 'otp_sent', 'otp_verified', 'otp_failed', 'field_filled',
                                                'signed', 'declined', 'reminded', 'canceled', 'completed', 'sealed', 'expired')),
  at              timestamptz not null default now(),
  document_sha256 bytea,
  prev_hash       bytea,
  hash            bytea not null,
  detail          jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  unique (request_id, seq)
);

-- a staff member's own drive (Q22: kept apart from the calendar and mailbox connections until phase 8)
create table app.drive_connections (
  id              uuid primary key default gen_random_uuid(),
  staff_id        uuid not null references app.admins (id) on delete cascade,
  provider        text not null check (provider in ('google', 'microsoft')),
  account_email   text check (account_email is null or char_length(account_email) <= 254),
  vault_secret_id uuid,
  status          text not null default 'not_connected' check (status in ('not_connected', 'connected', 'error')),
  connected_at    timestamptz,
  unique (staff_id, provider)
);

-- where new documents are stored (DOC-03): one row
create table app.document_storage_default (
  id       boolean primary key default true check (id),
  provider text not null default 'platform' check (provider in ('platform', 'google', 'onedrive', 'sharepoint')),
  location jsonb not null default '{}'::jsonb check (jsonb_typeof(location) = 'object'),
  set_by   uuid references app.admins (id) on delete set null,
  set_at   timestamptz
);
insert into app.document_storage_default (id) values (true);

-- ---------------------------------------------------------------------------
-- registry: documents and templates are record types in the deals scope, behind the documents module
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('document', 'documents', 'deals', 'documents', true, 'name', array['number', 'status'], array['name', 'number'], 90),
  ('document_template', 'document_templates', 'deals', 'documents', true, 'name', array['category', 'kind'], array['name'], 95);

-- what the generic record path may write: names only. Status, body, numbers and links move through the functions below.
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('document', 'name', 'text', true, true, null, 1),
  ('document', 'number', 'text', false, false, null, 2),
  ('document', 'status', 'text', false, false, null, 3),
  ('document', 'kind', 'text', false, false, null, 4),
  ('document', 'source', 'text', false, false, null, 5),
  ('document', 'deal_id', 'uuid', false, false, 'deal', 6),
  ('document', 'organization_id', 'uuid', false, false, 'organization', 7),
  ('document', 'person_id', 'uuid', false, false, 'person', 8),
  ('document', 'template_id', 'uuid', false, false, 'document_template', 9),
  ('document', 'product', 'text', false, false, null, 10),
  ('document', 'storage', 'text', false, false, null, 11),
  ('document', 'valid_until', 'date', false, false, null, 12),
  ('document', 'sent_at', 'timestamptz', false, false, null, 13),
  ('document', 'last_opened_at', 'timestamptz', false, false, null, 14),
  ('document', 'signed_at', 'timestamptz', false, false, null, 15),
  ('document_template', 'name', 'text', false, true, null, 1),
  ('document_template', 'kind', 'text', false, false, null, 2),
  ('document_template', 'category', 'text', false, false, null, 3),
  ('document_template', 'share', 'text', false, false, null, 4),
  ('document_template', 'language', 'text', false, false, null, 5),
  ('document_template', 'product', 'text', false, false, null, 6),
  ('document_template', 'source', 'text', false, false, null, 7);

-- ---------------------------------------------------------------------------
-- visibility. A document is visible when its deal is; without a deal, when its organisation is; with neither
-- (both removed later) to its owner by its own visibility. A template: company-wide to everyone, a team's to its
-- members, a private one to its owner; an admin sees all.
create function app.document_visible(p_deal uuid, p_org uuid, p_owner uuid, p_visibility text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select case
    when p_deal is not null then coalesce((select app.visible(d.owner_id, d.visibility) from app.deals d where d.id = p_deal), false)
    when p_org is not null then coalesce((select app.visible(o.owner_id, o.visibility) from app.organizations o where o.id = p_org), false)
    else app.visible(p_owner, p_visibility) end
$fn$;

create function app.doc_template_visible(p_share text, p_team uuid, p_owner uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.me() is not null and (
    p_share = 'company' or p_owner = app.me()
    or (p_share = 'team' and exists (select 1 from app.team_members tm where tm.team_id = p_team and tm.staff_id = app.me()))
    or exists (select 1 from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = app.me() and ps.kind = 'admin'))
$fn$;

create or replace function app.vis_sql(e app.entities) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when e.key = 'email_thread' then 'app.thread_visible(t.id)'
              when e.key = 'document' then 'app.document_visible(t.deal_id, t.organization_id, t.owner_id, t.visibility)'
              when e.key = 'document_template' then 'app.doc_template_visible(t.share, t.team_id, t.owner_id)'
              when e.owned then 'app.visible(t.owner_id, t.visibility)' else 'true' end
$fn$;

-- ---------------------------------------------------------------------------
-- guards
-- a document belongs to a deal or an organisation when it is made (either may be removed later)
create function app.document_anchor() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.deal_id is null and new.organization_id is null then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'deal_id';
  end if;
  return new;
end $fn$;
create trigger document_anchor before insert on app.documents for each row execute function app.document_anchor();

-- a signed contract and its evidence are kept (Bokføringsloven, 5 years; §10): it cannot be deleted, softly or for good
create function app.document_retention() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    if old.deleted_at is null and new.deleted_at is not null and old.status = 'signed' and not old.is_sample then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'retention';
    end if;
    return new;
  end if;
  if old.status = 'signed' and not old.is_sample and coalesce(old.signed_at, now()) > now() - interval '5 years' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'retention';
  end if;
  return old;
end $fn$;
create trigger document_retention before update of deleted_at or delete on app.documents for each row execute function app.document_retention();

-- a company-wide template is changed only with Deals › configure, whichever path the change takes (rec_save,
-- rec_delete, the template functions). A team template whose team is removed becomes private.
create function app.doc_template_guard() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  if new.share = 'team' and new.team_id is null then new.share := 'private'; end if;
  if app.me() is not null and (old.share = 'company' or new.share = 'company') and not app.can('deals', 'configure')
     and (old.share, old.name, old.body_html, old.product_table, old.deleted_at, old.category, old.language, old.validity_days, old.number_prefix)
         is distinct from (new.share, new.name, new.body_html, new.product_table, new.deleted_at, new.category, new.language, new.validity_days, new.number_prefix) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:configure';
  end if;
  return new;
end $fn$;
create trigger doc_template_guard before update on app.document_templates for each row execute function app.doc_template_guard();

-- signature evidence: the hash chain, computed here so no caller can supply a hash
create function app.signature_event_hash(p_prev bytea, p_request uuid, p_seq int, p_signer uuid, p_kind text, p_at timestamptz,
                                         p_doc bytea, p_detail jsonb) returns bytea
  language sql immutable set search_path = ''
as $fn$
  select sha256(coalesce(p_prev, '\x'::bytea) || convert_to(concat_ws('|', p_request::text, p_seq::text, coalesce(p_signer::text, ''), p_kind,
                to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), coalesce(encode(p_doc, 'hex'), ''),
                coalesce(p_detail, '{}'::jsonb)::text), 'UTF8'))
$fn$;

create function app.signature_event_chain() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_prev bytea; v_seq int;
begin
  perform 1 from app.signature_requests where id = new.request_id for update;
  select e.hash, e.seq into v_prev, v_seq from app.signature_events e where e.request_id = new.request_id order by e.seq desc limit 1;
  new.seq := coalesce(v_seq, 0) + 1;
  new.prev_hash := v_prev;
  new.at := coalesce(new.at, now());
  new.detail := coalesce(new.detail, '{}'::jsonb);
  new.hash := app.signature_event_hash(v_prev, new.request_id, new.seq, new.signer_id, new.kind, new.at, new.document_sha256, new.detail);
  return new;
end $fn$;
create trigger signature_event_chain before insert on app.signature_events for each row execute function app.signature_event_chain();

-- nobody may change this content; a delete is allowed only when the request (and so the document) is already gone
create function app.signature_events_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.signature_requests where id = old.request_id) then return old; end if;
  raise exception 'the signature evidence is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger signature_events_fixed before update or delete on app.signature_events for each row execute function app.signature_events_fixed();

create function app.signature_events_no_truncate() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  raise exception 'the signature evidence is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger signature_events_no_truncate before truncate on app.signature_events for each statement execute function app.signature_events_no_truncate();

-- does the chain of one request verify?
create function app.signature_chain_ok(p_request uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e record; v_prev bytea; n int := 0;
begin
  for e in select * from app.signature_events where request_id = p_request order by seq loop
    n := n + 1;
    if e.seq <> n or e.prev_hash is distinct from v_prev
       or e.hash <> app.signature_event_hash(v_prev, e.request_id, e.seq, e.signer_id, e.kind, e.at, e.document_sha256, e.detail) then
      return false;
    end if;
    v_prev := e.hash;
  end loop;
  return true;
end $fn$;

create function app.sig_event(p_request uuid, p_signer uuid, p_kind text, p_doc bytea default null, p_detail jsonb default '{}'::jsonb) returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.signature_events (request_id, signer_id, kind, document_sha256, detail, seq, hash)
  values (p_request, p_signer, p_kind, p_doc, coalesce(p_detail, '{}'::jsonb), 0, '\x'::bytea);
$fn$;

-- ---------------------------------------------------------------------------
-- rendering helpers. Values merged into a body are HTML-escaped; the body itself is sanitised at the edge (and
-- refused here when it carries script, frames, forms or event handlers).
create function app.html_escape(p text) returns text
  language sql immutable set search_path = ''
as $fn$
  select replace(replace(replace(replace(replace(p, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;')
$fn$;

create function app.doc_html_unsafe(p text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select coalesce(p, '') ~* '<\s*/?\s*(script|iframe|frame|object|embed|form|input|meta|link|base|style)\M|\son[a-z]+\s*=|javascript:|vbscript:|data:text/html'
$fn$;

-- the words a rendered product table prints, in the template's language (document content, not UI)
create function app.doc_label(p_key text, p_lang text) returns text
  language sql immutable set search_path = ''
as $fn$
  select coalesce($j${
    "nb": {"col.name": "Beskrivelse", "col.qty": "Antall", "col.price": "Pris", "col.discount": "Rabatt", "col.tax": "Mva", "col.total": "Sum", "col.period": "Periode",
           "per_month": "Per måned", "one_off": "Engangs", "tcv": "Total kontraktsverdi eks. mva", "vat": "Mva", "total": "Totalt inkl. mva",
           "freq.monthly": "per måned", "freq.quarterly": "per kvartal", "freq.semiannual": "per halvår", "freq.annual": "per år", "freq.one_off": "engangs"},
    "nn": {"col.name": "Skildring", "col.qty": "Tal", "col.price": "Pris", "col.discount": "Rabatt", "col.tax": "Mva", "col.total": "Sum", "col.period": "Periode",
           "per_month": "Per månad", "one_off": "Eingongs", "tcv": "Total kontraktsverdi ekskl. mva", "vat": "Mva", "total": "Totalt inkl. mva",
           "freq.monthly": "per månad", "freq.quarterly": "per kvartal", "freq.semiannual": "per halvår", "freq.annual": "per år", "freq.one_off": "eingongs"},
    "en": {"col.name": "Description", "col.qty": "Qty", "col.price": "Unit price", "col.discount": "Discount", "col.tax": "VAT", "col.total": "Total", "col.period": "Period",
           "per_month": "Per month", "one_off": "One-off", "tcv": "Total contract value ex. VAT", "vat": "VAT", "total": "Total incl. VAT",
           "freq.monthly": "per month", "freq.quarterly": "per quarter", "freq.semiannual": "per half-year", "freq.annual": "per year", "freq.one_off": "one-off"},
    "sv": {"col.name": "Beskrivning", "col.qty": "Antal", "col.price": "Pris", "col.discount": "Rabatt", "col.tax": "Moms", "col.total": "Summa", "col.period": "Period",
           "per_month": "Per månad", "one_off": "Engångs", "tcv": "Totalt kontraktsvärde exkl. moms", "vat": "Moms", "total": "Totalt inkl. moms",
           "freq.monthly": "per månad", "freq.quarterly": "per kvartal", "freq.semiannual": "per halvår", "freq.annual": "per år", "freq.one_off": "engångs"}
  }$j$::jsonb -> coalesce(p_lang, 'nb') ->> p_key, p_key)
$fn$;

-- 1234.5 → «1 234,50» (nb, nn, sv) or «1,234.50» (en)
create function app.doc_num(p_n numeric, p_lang text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when p_lang = 'en' then regexp_replace(split_part(x, '.', 1), '(\d)(?=(\d{3})+$)', '\1,', 'g') || '.' || split_part(x, '.', 2)
              else regexp_replace(split_part(x, '.', 1), '(\d)(?=(\d{3})+$)', '\1 ', 'g') || ',' || split_part(x, '.', 2) end
  from (select to_char(round(coalesce(p_n, 0), 2), 'FM999999999999990.00') x) s
$fn$;

create function app.doc_money(p_n numeric, p_currency text, p_lang text) returns text
  language sql immutable set search_path = ''
as $fn$
  select app.doc_num(p_n, p_lang) || ' ' || coalesce(p_currency, 'NOK')
$fn$;

-- 25.00 → «25», 12.50 → «12,5»
create function app.doc_trim(p_n numeric, p_lang text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when p_lang = 'en' then x else replace(x, '.', ',') end
  from (select rtrim(rtrim(to_char(coalesce(p_n, 0), 'FM999999999990.00'), '0'), '.') x) s
$fn$;

create function app.doc_date(p_d date, p_lang text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when p_d is null then null
    when p_lang = 'en' then extract(day from p_d)::int || ' ' || (array['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'])[extract(month from p_d)::int] || ' ' || extract(year from p_d)::int
    when p_lang = 'sv' then extract(day from p_d)::int || ' ' || (array['januari', 'februari', 'mars', 'april', 'maj', 'juni', 'juli', 'augusti', 'september', 'oktober', 'november', 'december'])[extract(month from p_d)::int] || ' ' || extract(year from p_d)::int
    else extract(day from p_d)::int || '. ' || (array['januar', 'februar', 'mars', 'april', 'mai', 'juni', 'juli', 'august', 'september', 'oktober', 'november', 'desember'])[extract(month from p_d)::int] || ' ' || extract(year from p_d)::int end
$fn$;

-- the distinct [tokens] of a text, in order of appearance
create function app.doc_tokens(p_text text) returns text[]
  language sql immutable set search_path = ''
as $fn$
  select coalesce(array_agg(t order by n), '{}') from (
    select m[1] t, min(o) n from regexp_matches(coalesce(p_text, ''), '\[([A-Za-zÆØÅæøå]+\.[A-Za-z0-9ÆØÅæøå_]+)\]', 'g') with ordinality r(m, o) group by m[1]) s
$fn$;

-- ---------------------------------------------------------------------------
-- merge values: address parts, the deal's currency, the org number and the document's own number and dates
create or replace function app.merge_value(p_token text, p_ctx jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.merge_fields; v text; src text; col text; v_cur text;
begin
  select * into f from app.merge_fields where token = p_token;
  if not found or f.format = 'block' then return null; end if;
  src := split_part(f.source_path, '.', 1); col := split_part(f.source_path, '.', 2);
  v := case src
    when 'person' then (select case col when 'name' then p.name when 'email' then p.email end from app.people p where p.id = (p_ctx ->> 'person')::uuid)
    when 'organization' then (select case col when 'name' then o.name when 'employees' then o.employees::text when 'org_number' then o.org_number
                                              when 'address' then o.address when 'postal_code' then o.postal_code when 'city' then o.city end
                              from app.organizations o where o.id = (p_ctx ->> 'organization')::uuid)
    when 'deal' then (select case col when 'title' then d.title when 'value' then d.value::text when 'currency' then d.currency
                                      when 'stage' then (select s.name from app.stages s where s.id = d.stage_id) end
                      from app.deals d where d.id = (p_ctx ->> 'deal')::uuid)
    when 'staff' then (select case col when 'name' then a.name
                                       when 'booking_link' then (select b.slug from app.booking_links b where b.staff_id = a.id and b.kind = 'general' order by b.id limit 1) end
                       from app.admins a where a.id = (p_ctx ->> 'staff')::uuid)
    when 'mailbox' then (select m.signature from app.mailboxes m where m.id = (p_ctx ->> 'mailbox')::uuid)
    when 'document' then (select case col when 'number' then x.number when 'created_at' then (x.created_at at time zone 'Europe/Oslo')::date::text
                                          when 'valid_until' then x.valid_until::text end
                          from app.documents x where x.id = (p_ctx ->> 'document')::uuid)
  end;
  if v is null or btrim(v) = '' then return null; end if;
  if f.format = 'nok' and src = 'deal' then
    select d.currency into v_cur from app.deals d where d.id = (p_ctx ->> 'deal')::uuid;
  end if;
  return case f.format
    when 'first_word' then split_part(btrim(v), ' ', 1)
    when 'nok' then replace(to_char(round(v::numeric), 'FM999G999G999G990'), ',', ' ') || case when coalesce(v_cur, 'NOK') = 'NOK' then ' kr' else ' ' || v_cur end
    when 'url' then 'booking:' || v            -- the app turns a booking slug into the public link (D-28 host)
    when 'orgnr' then case when v ~ '^\d{9}$' then substr(v, 1, 3) || ' ' || substr(v, 4, 3) || ' ' || substr(v, 7, 3) else v end
    when 'date' then app.doc_date(v::date, coalesce(p_ctx ->> 'language', 'nb'))
    else v end;
end $fn$;

-- render [Token] merge fields in one context (email unless the context says otherwise). A token the registry does
-- not hold for that context is unknown. → {text, missing, unknown}
create or replace function app.merge_render(p_text text, p_ctx jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m text[]; tok text; v text; out text := coalesce(p_text, ''); v_missing text[] := '{}'; v_unknown text[] := '{}';
  v_context text := coalesce(p_ctx ->> 'context', 'email');
begin
  for m in select regexp_matches(coalesce(p_text, ''), '\[([A-Za-zÆØÅæøå]+\.[A-Za-z0-9ÆØÅæøå_]+)\]', 'g') loop
    tok := m[1];
    if not exists (select 1 from app.merge_fields f where f.token = tok and v_context = any (f.contexts) and f.format <> 'block') then
      v_unknown := array_append(v_unknown, tok); continue;
    end if;
    v := app.merge_value(tok, p_ctx);
    if v is null then v_missing := array_append(v_missing, tok); continue; end if;
    out := replace(out, '[' || tok || ']', v);
  end loop;
  return jsonb_build_object('text', out, 'missing', to_jsonb(array(select distinct x from unnest(v_missing) x)),
                            'unknown', to_jsonb(array(select distinct x from unnest(v_unknown) x)));
end $fn$;

drop function public.merge_fields_get();
create function public.merge_fields_get(p_context text default 'email') returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('token', token, 'source', source_path, 'format', format, 'contexts', to_jsonb(contexts)) order by ord)
                   from app.merge_fields where p_context is null or p_context = any (contexts)), '[]'::jsonb);
end $fn$;

-- the deal's product table (DOC-02): the template's columns, a line per deal item, then per month (MRR), one-off,
-- the total contract value ex. VAT — which is deals.value when the value comes from the items (Q13) — VAT by
-- each line's rate, and the total incl. VAT. → {html, totals}; null without lines.
create function app.doc_product_table(p_deal uuid, p_columns text[], p_lang text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  d app.deals; i record; g record; v_rev jsonb; v_cols text[]; v_n int; v_head text; v_rows text := ''; v_foot text := '';
  v_vat jsonb; v_vat_sum numeric := 0; v_tcv numeric; v_span text;
begin
  select * into d from app.deals where id = p_deal;
  if not found then return null; end if;
  v_rev := app.deal_revenue(p_deal);
  if coalesce((v_rev ->> 'lines')::int, 0) = 0 then return null; end if;
  v_cols := coalesce(nullif(p_columns, '{}'), array['name', 'qty', 'price', 'discount', 'tax', 'total', 'period']);
  v_n := cardinality(v_cols);
  v_span := case when v_n > 1 then format(' colspan="%s"', v_n - 1) else '' end;
  v_head := (select string_agg(format('<th class="col-%s">%s</th>', c, app.html_escape(app.doc_label('col.' || c, p_lang))), '' order by o)
             from unnest(v_cols) with ordinality u(c, o));
  for i in select it.*, it.quantity * it.unit_price * (1 - it.discount_pct / 100) line_total from app.deal_items it where it.deal_id = p_deal order by it.ord, it.id loop
    v_rows := v_rows || '<tr>' || (select string_agg(format('<td class="col-%s">', c) || coalesce(case c
        when 'name' then app.html_escape(i.name)
        when 'qty' then app.doc_trim(i.quantity, p_lang)
        when 'price' then app.doc_money(i.unit_price, d.currency, p_lang)
        when 'discount' then case when i.discount_pct > 0 then app.doc_trim(i.discount_pct, p_lang) || ' %' else '' end
        when 'tax' then app.doc_trim(i.tax_rate, p_lang) || ' %'
        when 'total' then app.doc_money(i.line_total, d.currency, p_lang)
        when 'period' then app.doc_label(case when i.billing = 'recurring' then 'freq.' || coalesce(i.billing_frequency, 'monthly') else 'freq.one_off' end, p_lang)
      end, '') || '</td>', '' order by o) from unnest(v_cols) with ordinality u(c, o)) || '</tr>';
  end loop;
  -- VAT per rate on each line's contract amount (a recurring line over its cycles, as deal_revenue counts the TCV)
  select coalesce(jsonb_agg(jsonb_build_object('rate', x.rate, 'base', round(x.base, 2), 'vat', round(x.base * x.rate / 100, 2)) order by x.rate), '[]'::jsonb),
         coalesce(sum(round(x.base * x.rate / 100, 2)), 0)
    into v_vat, v_vat_sum
  from (select it.tax_rate rate,
               sum(it.quantity * it.unit_price * (1 - it.discount_pct / 100)
                   * case when it.billing = 'recurring'
                          then coalesce(it.cycles, 12 / case it.billing_frequency when 'quarterly' then 3 when 'semiannual' then 6 when 'annual' then 12 else 1 end)
                          else 1 end) base
        from app.deal_items it where it.deal_id = p_deal group by it.tax_rate) x;
  v_tcv := round((v_rev ->> 'tcv')::numeric, 2);
  if (v_rev ->> 'mrr')::numeric > 0 then
    v_foot := v_foot || format('<tr class="per-month"><td%s>%s</td><td>%s</td></tr>', v_span, app.html_escape(app.doc_label('per_month', p_lang)), app.doc_money((v_rev ->> 'mrr')::numeric, d.currency, p_lang));
  end if;
  if (v_rev ->> 'one_off')::numeric > 0 then
    v_foot := v_foot || format('<tr class="one-off"><td%s>%s</td><td>%s</td></tr>', v_span, app.html_escape(app.doc_label('one_off', p_lang)), app.doc_money((v_rev ->> 'one_off')::numeric, d.currency, p_lang));
  end if;
  v_foot := v_foot || format('<tr class="tcv"><td%s>%s</td><td>%s</td></tr>', v_span, app.html_escape(app.doc_label('tcv', p_lang)), app.doc_money(v_tcv, d.currency, p_lang));
  for g in select (x ->> 'rate')::numeric rate, (x ->> 'vat')::numeric vat from jsonb_array_elements(v_vat) x loop
    v_foot := v_foot || format('<tr class="vat"><td%s>%s %s %%</td><td>%s</td></tr>', v_span, app.html_escape(app.doc_label('vat', p_lang)), app.doc_trim(g.rate, p_lang), app.doc_money(g.vat, d.currency, p_lang));
  end loop;
  v_foot := v_foot || format('<tr class="total"><td%s>%s</td><td>%s</td></tr>', v_span, app.html_escape(app.doc_label('total', p_lang)), app.doc_money(v_tcv + v_vat_sum, d.currency, p_lang));
  return jsonb_build_object(
    'html', '<table class="doc-products" data-block="product.table"><thead><tr>' || v_head || '</tr></thead><tbody>' || v_rows || '</tbody><tfoot>' || v_foot || '</tfoot></table>',
    'totals', jsonb_build_object('currency', d.currency, 'lines', (v_rev ->> 'lines')::int, 'mrr', round((v_rev ->> 'mrr')::numeric, 2),
                                 'one_off', round((v_rev ->> 'one_off')::numeric, 2), 'tcv', v_tcv, 'vat', v_vat, 'total_incl_vat', v_tcv + v_vat_sum,
                                 'deal_value', d.value, 'value_source', d.value_source));
end $fn$;

-- render a template body for a document: merge fields (HTML-escaped), the product table block, signer anchors kept
-- as they are. → {html, missing, unknown, anchors}
create function app.doc_render(p_html text, p_ctx jsonb, p_table text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare tok text; f app.merge_fields; v text; out text := coalesce(p_html, ''); v_missing text[] := '{}'; v_unknown text[] := '{}'; v_anchors text[] := '{}';
begin
  foreach tok in array app.doc_tokens(p_html) loop
    if tok ~ '^signer\.[1-9][0-9]?$' then v_anchors := v_anchors || tok; continue; end if;
    select * into f from app.merge_fields x where x.token = tok and 'document' = any (x.contexts);
    if not found then v_unknown := v_unknown || tok; continue; end if;
    if f.format = 'block' then
      if p_table is null then v_missing := v_missing || tok; else out := replace(out, '[' || tok || ']', p_table); end if;
      continue;
    end if;
    v := app.merge_value(tok, p_ctx || jsonb_build_object('context', 'document'));
    if v is null then v_missing := v_missing || tok; continue; end if;
    out := replace(out, '[' || tok || ']', app.html_escape(v));
  end loop;
  return jsonb_build_object('html', out, 'missing', to_jsonb(v_missing), 'unknown', to_jsonb(v_unknown), 'anchors', to_jsonb(v_anchors));
end $fn$;

-- ---------------------------------------------------------------------------
-- document helpers
create function app.doc_row(p_id uuid) returns app.documents
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d app.documents;
begin
  select * into d from app.documents where id = p_id and deleted_at is null;
  if not found or not app.document_visible(d.deal_id, d.organization_id, d.owner_id, d.visibility) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  return d;
end $fn$;

create function app.doc_require_edit(p_owner uuid) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_owner is distinct from app.me() and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
end $fn$;

-- events about a document are about its deal (or its organisation); the payload carries ids only
create function app.doc_emit(p_kind text, p_doc uuid, p_payload jsonb default '{}'::jsonb) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.documents;
begin
  select * into d from app.documents where id = p_doc;
  if not found or (d.deal_id is null and d.organization_id is null) then return; end if;
  perform app.emit(p_kind, case when d.deal_id is not null then 'deal' else 'organization' end, coalesce(d.deal_id, d.organization_id),
                   jsonb_build_object('document', d.id) || coalesce(p_payload, '{}'::jsonb), d.is_sample);
end $fn$;

-- the deal's history gets a line for what happened to its documents (PIP-04)
create function app.doc_history(p_doc uuid, p_field text, p_value jsonb default '{}'::jsonb) returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
  select 'deal', d.deal_id, p_field, jsonb_build_object('document', d.id) || coalesce(p_value, '{}'::jsonb), app.me(),
         case when app.me() is null then 'system' else 'ui' end
  from app.documents d where d.id = p_doc and d.deal_id is not null;
$fn$;

create function app.doc_status_set(p_doc uuid, p_status text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_old text;
begin
  select status into v_old from app.documents where id = p_doc for update;
  if v_old is null or v_old = p_status then return; end if;
  update app.documents set status = p_status, version = version + 1, updated_at = now(),
    sent_at = case when p_status in ('sent', 'awaiting_signature') then coalesce(sent_at, now()) else sent_at end,
    signed_at = case when p_status = 'signed' then coalesce(signed_at, now()) else signed_at end
  where id = p_doc;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('document', p_doc, 'status', to_jsonb(v_old), to_jsonb(p_status), app.me(), case when app.me() is null then 'system' else 'ui' end);
end $fn$;

-- ---------------------------------------------------------------------------
-- documents
create function public.documents_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
  v_q text; v_status text := q ->> 'status'; v_deal uuid; v_org uuid; v_limit int; v_offset int; v_total bigint; v_rows jsonb;
begin
  perform app.require_module('documents');
  if v_status is not null and v_status not in ('draft', 'sent', 'opened', 'awaiting_signature', 'signed', 'declined', 'expired', 'revoked') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  begin
    v_deal := (q ->> 'deal_id')::uuid; v_org := (q ->> 'organization_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter';
  end;
  v_q := nullif(btrim(coalesce(q ->> 'q', '')), '');
  if v_q is not null then v_q := '%' || replace(replace(replace(left(v_q, 100), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  v_limit := least(greatest(coalesce((q ->> 'limit')::int, 50), 1), 200);
  v_offset := greatest(coalesce((q ->> 'offset')::int, 0), 0);

  select count(*) into v_total from app.documents d
  where d.deleted_at is null and (v_sandbox or not d.is_sample) and app.document_visible(d.deal_id, d.organization_id, d.owner_id, d.visibility)
    and (v_status is null or d.status = v_status) and (v_deal is null or d.deal_id = v_deal) and (v_org is null or d.organization_id = v_org)
    and (v_q is null or d.name ilike v_q or d.number ilike v_q);

  select coalesce(jsonb_agg(x.j order by x.created_at desc, x.id), '[]'::jsonb) into v_rows from (
    select d.id, d.created_at, jsonb_build_object(
      'id', d.id, 'number', d.number, 'name', d.name, 'status', d.status, 'kind', d.kind, 'source', d.source,
      'template_id', d.template_id, 'template', (select t.name from app.document_templates t where t.id = d.template_id),
      'deal_id', d.deal_id, 'deal_title', (select dl.title from app.deals dl where dl.id = d.deal_id),
      'organization_id', d.organization_id, 'organization_name', (select o.name from app.organizations o where o.id = d.organization_id),
      'opens', (select count(*) from app.document_views v where v.document_id = d.id and v.client_class <> 'prefetch'),
      'storage', d.storage, 'merge_missing', to_jsonb(d.merge_missing), 'valid_until', d.valid_until, 'created_at', d.created_at,
      'sent_at', d.sent_at, 'last_opened_at', d.last_opened_at, 'signed_at', d.signed_at, 'has_pdf', d.pdf_path is not null,
      'owner_id', d.owner_id, 'owner_name', (select a.name from app.admins a where a.id = d.owner_id),
      'signature_status', (select r.status from app.signature_requests r where r.document_id = d.id order by r.created_at desc limit 1)) j
    from app.documents d
    where d.deleted_at is null and (v_sandbox or not d.is_sample) and app.document_visible(d.deal_id, d.organization_id, d.owner_id, d.visibility)
      and (v_status is null or d.status = v_status) and (v_deal is null or d.deal_id = v_deal) and (v_org is null or d.organization_id = v_org)
      and (v_q is null or d.name ilike v_q or d.number ilike v_q)
    order by d.created_at desc, d.id limit v_limit offset v_offset) x;
  perform app.log('record.listed', 'document', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $fn$;

create function public.document_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.documents;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'document', d.id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'document', d.id::text);
  return (to_jsonb(d) - 'pdf_sha256') || jsonb_build_object(
    'has_pdf', d.pdf_path is not null and d.pdf_sha256 is not null,
    'pdf_sha256', encode(d.pdf_sha256, 'hex'),
    'template', (select jsonb_build_object('id', t.id, 'name', t.name, 'category', t.category, 'language', t.language) from app.document_templates t where t.id = d.template_id),
    'deal', (select jsonb_build_object('id', dl.id, 'title', dl.title, 'value', dl.value, 'currency', dl.currency) from app.deals dl where dl.id = d.deal_id),
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number) from app.organizations o where o.id = d.organization_id),
    'person', (select jsonb_build_object('id', p.id, 'name', p.name) from app.people p where p.id = d.person_id),
    'owner_name', (select a.name from app.admins a where a.id = d.owner_id),
    'can_edit', d.owner_id = v_me or app.can('deals', 'edit_others'),
    'links', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'label', l.label, 'recipient_person_id', l.recipient_person_id,
                         'recipient_name', (select p.name from app.people p where p.id = l.recipient_person_id),
                         'created_at', l.created_at, 'expires_at', l.expires_at, 'revoked_at', l.revoked_at,
                         'active', l.revoked_at is null and (l.expires_at is null or l.expires_at > now()),
                         'opens', (select count(*) from app.document_views v where v.link_id = l.id and v.client_class <> 'prefetch')) order by l.created_at)
                       from app.document_links l where l.document_id = d.id), '[]'::jsonb),
    'opens', (select count(*) from app.document_views v where v.document_id = d.id and v.client_class <> 'prefetch'),
    'signature_requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'service', r.service, 'created_at', r.created_at,
                                      'sent_at', r.sent_at, 'completed_at', r.completed_at, 'sealed', r.sealed_pdf_path is not null) order by r.created_at)
                                    from app.signature_requests r where r.document_id = d.id), '[]'::jsonb));
end $fn$;

-- a document from a template on a deal (DOC-01, DOC-02): numbered, rendered, missing values listed
create function public.document_create(p_template uuid, p_deal uuid, p_name text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add');
  t app.document_templates; dl app.deals; v_sandbox boolean; v_number text; v_id uuid; v_table jsonb; r jsonb; v_cols text[];
  v_missing text[]; v_store text;
begin
  perform app.require_module('documents');
  select * into t from app.document_templates where id = p_template and deleted_at is null;
  if not found or not app.doc_template_visible(t.share, t.team_id, t.owner_id) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'template';
  end if;
  -- a drive template is copied in the drive, which needs its adapter
  if t.source <> 'platform' then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = t.source; end if;
  select * into dl from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(dl.owner_id, dl.visibility) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal';
  end if;
  if p_name is not null and char_length(btrim(p_name)) not between 1 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end if;
  v_sandbox := coalesce((select sandbox from app.admins where id = v_me), false);
  if t.number_prefix is not null then
    insert into app.document_counters as c (prefix, next) values (t.number_prefix, 2)
    on conflict (prefix) do update set next = c.next + 1
    returning t.number_prefix || (c.next - 1) into v_number;
  end if;
  insert into app.documents (number, name, template_id, template_version, kind, source, deal_id, organization_id, person_id, product, status,
                             valid_until, storage, owner_id, visibility, is_sample, created_by, updated_by)
  values (v_number, coalesce(nullif(btrim(p_name), ''), t.name), t.id, t.current_version, t.kind, 'template', dl.id, dl.organization_id, dl.person_id,
          coalesce(dl.product, t.product), 'draft',
          case when t.validity_days is not null then (now() at time zone 'Europe/Oslo')::date + t.validity_days end,
          'platform', v_me, 'all', v_sandbox or dl.is_sample, v_me, v_me)
  returning id into v_id;
  v_cols := case when t.product_table is not null then array(select jsonb_array_elements_text(t.product_table -> 'columns')) end;
  v_table := app.doc_product_table(dl.id, v_cols, t.language);
  r := app.doc_render(t.body_html, app.merge_context('deal', dl.id, null, v_me)
                                   || jsonb_build_object('document', v_id, 'language', t.language), v_table ->> 'html');
  v_missing := array(select jsonb_array_elements_text(r -> 'missing')) || array(select jsonb_array_elements_text(r -> 'unknown'));
  update app.documents set body_html = r ->> 'html', merge_missing = v_missing, totals = v_table -> 'totals' where id = v_id;

  insert into app.changelog (entity, record_id, field, actor_id, source) values ('document', v_id, '*created', v_me, 'ui');
  perform app.doc_history(v_id, 'document.generated', jsonb_build_object('number', v_number));
  perform app.log('document.created', 'document', v_id::text,
                  jsonb_build_object('template', t.id, 'deal', dl.id, 'missing', cardinality(v_missing)));
  perform app.doc_emit('document.generated', v_id, '{}'::jsonb);
  -- the PDF worker renders the PDF into the documents bucket (DOC-03: generated PDFs live on the platform); a drive
  -- default also gets a copy in the drive
  perform pgmq.send('jobs', jsonb_build_object('job', 'document_render', 'document_id', v_id));
  select provider into v_store from app.document_storage_default;
  if v_store <> 'platform' then perform pgmq.send('jobs', jsonb_build_object('job', 'document_store', 'document_id', v_id, 'storage', v_store)); end if;
  return jsonb_build_object('id', v_id, 'number', v_number, 'status', 'draft', 'missing', r -> 'missing', 'unknown', r -> 'unknown',
                            'anchors', r -> 'anchors', 'totals', v_table -> 'totals');
end $fn$;

-- an uploaded PDF on a deal (SF-33): the edge function stores the file under the deal's folder, then records it here
create function public.document_upload(p_deal uuid, p_path text, p_name text, p_size bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); dl app.deals; v_id uuid;
begin
  perform app.require_module('documents');
  select * into dl from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(dl.owner_id, dl.visibility) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal'; end if;
  if p_path is null or p_path !~ ('^' || p_deal::text || '/[A-Za-z0-9][A-Za-z0-9._-]{0,150}\.pdf$') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path';
  end if;
  if p_size is null or p_size not between 1 and 26214400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'size'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  insert into app.documents (name, kind, source, deal_id, organization_id, person_id, product, status, storage, pdf_path, size_bytes,
                             owner_id, visibility, is_sample, created_by, updated_by)
  values (btrim(p_name), 'document', 'upload', dl.id, dl.organization_id, dl.person_id, dl.product, 'draft', 'platform', p_path, p_size,
          v_me, 'all', coalesce((select sandbox from app.admins where id = v_me), false) or dl.is_sample, v_me, v_me)
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('document', v_id, '*created', v_me, 'ui');
  perform app.doc_history(v_id, 'document.uploaded');
  perform app.log('document.uploaded', 'document', v_id::text, jsonb_build_object('deal', dl.id, 'size', p_size));
  perform app.doc_emit('document.generated', v_id, jsonb_build_object('upload', true));
  perform pgmq.send('jobs', jsonb_build_object('job', 'document_render', 'document_id', v_id));    -- hashes the uploaded file
  return jsonb_build_object('id', v_id, 'status', 'draft');
end $fn$;

-- a draft's name, body (edited in the rich-text panel, Q11), validity and recipient
create function public.document_update(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add'); d app.documents; n app.documents; v jsonb := coalesce(p_values, '{}'::jsonb); k text; r jsonb;
  v_changed text[] := '{}'; v_lang text;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  perform app.doc_require_edit(d.owner_id);
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if p_version is not null and d.version <> p_version then
    raise exception 'version_conflict' using errcode = 'serialization_failure', detail = d.version::text;
  end if;
  if d.status <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('name', 'body_html', 'valid_until', 'person_id') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if v ? 'name' and char_length(btrim(coalesce(v ->> 'name', ''))) not between 1 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end if;
  if v ? 'body_html' and (d.source <> 'template' or app.doc_html_unsafe(v ->> 'body_html') or char_length(coalesce(v ->> 'body_html', '')) > 1000000) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body_html';
  end if;
  if v ? 'person_id' and v ->> 'person_id' is not null and not exists (select 1 from app.people p where p.id::text = v ->> 'person_id' and p.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'person_id';
  end if;
  begin
    update app.documents set
      name = case when v ? 'name' then btrim(v ->> 'name') else name end,
      valid_until = case when v ? 'valid_until' then (v ->> 'valid_until')::date else valid_until end,
      person_id = case when v ? 'person_id' then (v ->> 'person_id')::uuid else person_id end,
      body_html = case when v ? 'body_html' then v ->> 'body_html' else body_html end,
      version = version + 1, updated_at = now(), updated_by = v_me
    where id = d.id returning * into n;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end;
  -- an edited body is rendered again: tokens left in it are merged, and what is still missing is listed
  if v ? 'body_html' then
    v_lang := coalesce((select t.language from app.document_templates t where t.id = n.template_id), 'nb');
    r := app.doc_render(n.body_html, app.merge_context(case when n.deal_id is not null then 'deal' else 'organization' end, coalesce(n.deal_id, n.organization_id), n.person_id, v_me)
                                     || jsonb_build_object('document', n.id, 'language', v_lang),
                        (app.doc_product_table(n.deal_id, (select array(select jsonb_array_elements_text(t.product_table -> 'columns')) from app.document_templates t where t.id = n.template_id and t.product_table is not null), v_lang)) ->> 'html');
    update app.documents set body_html = r ->> 'html',
      merge_missing = array(select jsonb_array_elements_text(r -> 'missing')) || array(select jsonb_array_elements_text(r -> 'unknown'))
    where id = n.id returning * into n;
  end if;
  -- the history names the fields; a body is never copied into it
  foreach k in array array['name', 'valid_until', 'person_id', 'body_html'] loop
    if (to_jsonb(d) -> k) is distinct from (to_jsonb(n) -> k) then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      values ('document', d.id, k, case when k = 'body_html' then null else to_jsonb(d) -> k end, case when k = 'body_html' then null else to_jsonb(n) -> k end, v_me, 'ui');
      v_changed := v_changed || k;
    end if;
  end loop;
  perform app.log('record.updated', 'document', d.id::text, jsonb_build_object('fields', to_jsonb(v_changed)));
  return jsonb_build_object('id', n.id, 'version', n.version, 'missing', to_jsonb(n.merge_missing));
end $fn$;

create function public.document_delete(p_ids uuid[], p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'delete'); x uuid; d app.documents; n int := 0;
begin
  perform app.require_module('documents');
  perform app.take_reason(p_reason);
  if cardinality(p_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  if cardinality(p_ids) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  foreach x in array coalesce(p_ids, '{}') loop
    d := app.doc_row(x);
    perform app.doc_require_edit(d.owner_id);
    update app.documents set deleted_at = now(), updated_at = now(), updated_by = v_me, version = version + 1 where id = x;
    insert into app.changelog (entity, record_id, field, actor_id, source) values ('document', x, '*deleted', v_me, 'ui');
    -- open links stop working at once
    update app.document_links set revoked_at = now() where document_id = x and revoked_at is null;
    n := n + 1;
  end loop;
  perform app.log('record.deleted', 'document', case when n = 1 then p_ids[1]::text end, jsonb_build_object('count', n));
  return jsonb_build_object('deleted', n);
end $fn$;

-- a trackable link (DOC-04). The token is returned once, as a go.owntheagenda.com path; only its hash is kept (Q1).
create function public.document_link_create(p_id uuid, p_recipient uuid default null, p_label text default null,
                                            p_expires_at timestamptz default null, p_notify boolean default true) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); d app.documents; v_token text := app.token(); v_id uuid;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  perform app.doc_require_edit(d.owner_id);
  if cardinality(d.merge_missing) > 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge'; end if;
  if d.status in ('declined', 'expired') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if p_recipient is not null and not exists (select 1 from app.people p where p.id = p_recipient and p.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recipient';
  end if;
  if p_label is not null and char_length(p_label) > 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'label'; end if;
  if p_expires_at is not null and p_expires_at <= now() then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'expires_at'; end if;
  insert into app.document_links (document_id, token_sha256, recipient_person_id, label, notify_owner, expires_at, created_by)
  values (d.id, sha256(convert_to(v_token, 'UTF8')), p_recipient, nullif(btrim(p_label), ''), coalesce(p_notify, true), p_expires_at, v_me)
  returning id into v_id;
  if d.status in ('draft', 'revoked') then
    perform app.doc_status_set(d.id, 'sent');
    perform app.doc_emit('document.sent', d.id, jsonb_build_object('link', v_id));
  end if;
  perform app.doc_history(d.id, 'document.link_created', jsonb_build_object('link', v_id));
  perform app.log('document.link_created', 'document', d.id::text, jsonb_build_object('link', v_id, 'recipient', p_recipient is not null));
  return jsonb_build_object('id', v_id, 'path', '/d/' || v_token, 'token', v_token);
end $fn$;

create function public.document_link_revoke(p_link uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); l app.document_links; d app.documents;
begin
  perform app.require_module('documents');
  select * into l from app.document_links where id = p_link;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  d := app.doc_row(l.document_id);
  perform app.doc_require_edit(d.owner_id);
  if l.revoked_at is null then
    update app.document_links set revoked_at = now() where id = l.id;
    perform app.doc_emit('document.revoked', d.id, jsonb_build_object('link', l.id));
    perform app.doc_history(d.id, 'document.link_revoked', jsonb_build_object('link', l.id));
    -- a sent document whose every link is revoked reads «revoked»
    if d.status in ('sent', 'opened') and not exists (select 1 from app.document_links x where x.document_id = d.id and x.revoked_at is null
                                                       and (x.expires_at is null or x.expires_at > now())) then
      perform app.doc_status_set(d.id, 'revoked');
    end if;
    perform app.log('document.link_revoked', 'document', d.id::text, jsonb_build_object('link', l.id));
  end if;
  return jsonb_build_object('revoked', true);
end $fn$;

-- who opened, when and for how long. No place, no IP (§10).
create function public.document_views(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.documents;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  perform app.log('record.read', 'document', d.id::text, jsonb_build_object('views', true));
  return coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'link_id', v.link_id, 'label', l.label,
                     'recipient_name', (select p.name from app.people p where p.id = l.recipient_person_id),
                     'started_at', v.started_at, 'duration_seconds', v.duration_seconds, 'client_class', v.client_class) order by v.started_at desc)
                   from app.document_views v join app.document_links l on l.id = v.link_id where v.document_id = d.id), '[]'::jsonb);
end $fn$;

-- the file behind a document, for a short-lived signed URL. The RPC checks the record's visibility (CRM-05, SF-33);
-- the edge function signs the object it names. Without a PDF (no PDF worker yet) the answer is not_connected.
create function public.document_file_url(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.documents; v_sealed text;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  select r.sealed_pdf_path into v_sealed from app.signature_requests r where r.document_id = d.id and r.status = 'completed' and r.sealed_pdf_path is not null
  order by r.completed_at desc limit 1;
  if coalesce(v_sealed, d.pdf_path) is null then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'pdf'; end if;
  perform app.log('document.file_read', 'document', d.id::text, jsonb_build_object('sealed', v_sealed is not null));
  return jsonb_build_object('bucket', 'documents', 'path', coalesce(v_sealed, d.pdf_path), 'expires_in', 300, 'sealed', v_sealed is not null);
end $fn$;

-- ---------------------------------------------------------------------------
-- document templates (DOC-01)
create function public.doc_templates_get(p_category text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false); v_rows jsonb;
begin
  perform app.require_module('documents');
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'kind', t.kind, 'category', t.category, 'share', t.share,
           'team_id', t.team_id, 'team_name', (select tm.name from app.teams tm where tm.id = t.team_id), 'product', t.product, 'language', t.language,
           'source', t.source, 'placeholders', to_jsonb(t.placeholders), 'validity_days', t.validity_days, 'number_prefix', t.number_prefix,
           'current_version', t.current_version, 'version', t.version, 'owner_id', t.owner_id,
           'owner_name', (select a.name from app.admins a where a.id = t.owner_id), 'updated_at', t.updated_at,
           'can_edit', case when t.share = 'company' then app.can('deals', 'configure') else t.owner_id = v_me or app.can('deals', 'edit_others') end)
         order by t.category, t.name), '[]'::jsonb)
    into v_rows
  from app.document_templates t
  where t.deleted_at is null and (v_sandbox or not t.is_sample) and app.doc_template_visible(t.share, t.team_id, t.owner_id)
    and (p_category is null or t.category = p_category);
  perform app.log('record.listed', 'document_template', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

create function public.doc_template_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.document_templates;
begin
  perform app.require_module('documents');
  select * into t from app.document_templates where id = p_id and deleted_at is null;
  if not found or not app.doc_template_visible(t.share, t.team_id, t.owner_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('record.read', 'document_template', t.id::text);
  return to_jsonb(t) || jsonb_build_object(
    'team_name', (select tm.name from app.teams tm where tm.id = t.team_id),
    'owner_name', (select a.name from app.admins a where a.id = t.owner_id),
    'unknown', to_jsonb(array(select x from unnest(t.placeholders) x where x !~ '^signer\.[1-9][0-9]?$'
                               and not exists (select 1 from app.merge_fields f where f.token = x and 'document' = any (f.contexts)))),
    'can_edit', case when t.share = 'company' then app.can('deals', 'configure') else t.owner_id = v_me or app.can('deals', 'edit_others') end,
    'versions', coalesce((select jsonb_agg(jsonb_build_object('version', v.version, 'created_at', v.created_at,
                                                              'created_by', (select a.name from app.admins a where a.id = v.created_by)) order by v.version desc)
                          from app.document_template_versions v where v.template_id = t.id), '[]'::jsonb));
end $fn$;

-- create or change a platform template. Private and team templates need Deals › add (others' need edit_others);
-- a company-wide one needs Deals › configure (§6). Every change to the body or the table is a new version.
create function public.doc_template_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see'); v jsonb := coalesce(p_values, '{}'::jsonb); t app.document_templates; k text;
  v_share text; v_team uuid; v_body text; v_pt jsonb; v_tokens text[]; v_unknown text[]; v_content boolean; v_col text; v_cn text;
begin
  perform app.require_module('documents');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('name', 'kind', 'category', 'share', 'team_id', 'product', 'language', 'body_html', 'product_table', 'validity_days', 'number_prefix') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_id is not null then
    select * into t from app.document_templates where id = p_id and deleted_at is null for update;
    if not found or not app.doc_template_visible(t.share, t.team_id, t.owner_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and t.version <> p_version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = t.version::text;
    end if;
    if t.source <> 'platform' and (v ? 'body_html' or v ? 'product_table') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
    end if;
    if t.share = 'company' then perform app.require('deals', 'configure');
    elsif t.owner_id is distinct from v_me then perform app.require('deals', 'edit_others'); end if;
  else
    perform app.require('deals', 'add');
  end if;
  -- platform templates are documents; presentations and spreadsheets come from a drive (doc_template_import)
  if coalesce(v ->> 'kind', t.kind, 'document') <> coalesce(t.kind, 'document') or (p_id is null and coalesce(v ->> 'kind', 'document') <> 'document') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  v_share := coalesce(v ->> 'share', t.share, 'private');
  if v_share not in ('company', 'team', 'private') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'share'; end if;
  if v_share = 'company' then perform app.require('deals', 'configure'); end if;
  begin
    v_team := case when v ? 'team_id' then nullif(v ->> 'team_id', '')::uuid else t.team_id end;
  exception when invalid_text_representation then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'team_id';
  end;
  if v_share <> 'team' then v_team := null; end if;
  if v_share = 'team' and (v_team is null or not exists (select 1 from app.teams x where x.id = v_team)
                           or not (app.can('deals', 'configure') or exists (select 1 from app.team_members tm where tm.team_id = v_team and tm.staff_id = v_me))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'team_id';
  end if;
  v_body := case when v ? 'body_html' then v ->> 'body_html' else t.body_html end;
  if app.doc_html_unsafe(v_body) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body_html'; end if;
  v_pt := case when v ? 'product_table' then v -> 'product_table' else t.product_table end;
  if v_pt is not null and jsonb_typeof(v_pt) = 'null' then v_pt := null; end if;
  if v_pt is not null and (jsonb_typeof(v_pt) <> 'object' or jsonb_typeof(v_pt -> 'columns') <> 'array' or jsonb_array_length(v_pt -> 'columns') = 0
                           or exists (select 1 from jsonb_array_elements(v_pt -> 'columns') c
                                      where jsonb_typeof(c) <> 'string' or c #>> '{}' not in ('name', 'qty', 'price', 'discount', 'tax', 'total', 'period'))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product_table';
  end if;
  if v_pt is not null then v_pt := jsonb_build_object('columns', v_pt -> 'columns'); end if;
  v_tokens := app.doc_tokens(v_body);
  v_unknown := array(select x from unnest(v_tokens) x where x !~ '^signer\.[1-9][0-9]?$'
                       and not exists (select 1 from app.merge_fields f where f.token = x and 'document' = any (f.contexts)));
  begin
    if p_id is null then
      insert into app.document_templates (name, kind, category, share, team_id, product, language, source, body_html, product_table, validity_days,
                                          number_prefix, placeholders, owner_id, visibility, is_sample, created_by, updated_by)
      values (btrim(v ->> 'name'), 'document', coalesce(v ->> 'category', 'other'), v_share, v_team, nullif(v ->> 'product', ''), coalesce(v ->> 'language', 'nb'),
              'platform', v_body, v_pt, (v ->> 'validity_days')::int, nullif(v ->> 'number_prefix', ''), v_tokens, v_me, 'all',
              coalesce((select sandbox from app.admins where id = v_me), false), v_me, v_me)
      returning * into t;
      insert into app.document_template_versions (template_id, version, body_html, product_table, created_by) values (t.id, 1, v_body, v_pt, v_me);
    else
      v_content := v_body is distinct from t.body_html or v_pt is distinct from t.product_table;
      update app.document_templates set
        name = case when v ? 'name' then btrim(v ->> 'name') else name end,
        category = coalesce(v ->> 'category', category), share = v_share, team_id = v_team,
        product = case when v ? 'product' then nullif(v ->> 'product', '') else product end,
        language = coalesce(v ->> 'language', language), body_html = v_body, product_table = v_pt,
        validity_days = case when v ? 'validity_days' then (v ->> 'validity_days')::int else validity_days end,
        number_prefix = case when v ? 'number_prefix' then nullif(v ->> 'number_prefix', '') else number_prefix end,
        placeholders = v_tokens, current_version = current_version + case when v_content then 1 else 0 end,
        version = version + 1, updated_at = now(), updated_by = v_me
      where id = t.id returning * into t;
      if v_content then
        insert into app.document_template_versions (template_id, version, body_html, product_table, created_by) values (t.id, t.current_version, v_body, v_pt, v_me);
      end if;
    end if;
  exception when check_violation or not_null_violation or foreign_key_violation or invalid_text_representation or numeric_value_out_of_range then
    get stacked diagnostics v_col = column_name, v_cn = constraint_name;
    raise exception 'invalid' using errcode = 'invalid_parameter_value',
      detail = coalesce(nullif(v_col, ''), nullif(regexp_replace(coalesce(v_cn, ''), '^document_templates_(.*?)(_check|_fkey)?$', '\1'), ''), 'values');
  end;
  perform app.log(case when p_id is null then 'record.created' else 'record.updated' end, 'document_template', t.id::text,
                  jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v))), 'share', t.share));
  return jsonb_build_object('id', t.id, 'version', t.version, 'current_version', t.current_version, 'placeholders', to_jsonb(t.placeholders),
                            'unknown', to_jsonb(v_unknown));
end $fn$;

-- a presentation, spreadsheet or document template from the caller's drive: needs their drive connection
create function public.doc_template_import(p_provider text, p_file_ref text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add');
begin
  perform app.require_module('documents');
  if p_provider not in ('google', 'microsoft') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  if coalesce(btrim(p_file_ref), '') = '' or char_length(p_file_ref) > 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'file_ref'; end if;
  if not exists (select 1 from app.drive_connections c where c.staff_id = v_me and c.provider = p_provider and c.status = 'connected') then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = p_provider;
  end if;
  perform pgmq.send('jobs', jsonb_build_object('job', 'doc_template_import', 'staff_id', v_me, 'provider', p_provider, 'file_ref', p_file_ref));
  perform app.log('document_template.import_requested', 'document_template', null, jsonb_build_object('provider', p_provider));
  return jsonb_build_object('queued', true);
end $fn$;

create function public.doc_template_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.document_templates;
begin
  perform app.require_module('documents');
  select * into t from app.document_templates where id = p_id and deleted_at is null for update;
  if not found or not app.doc_template_visible(t.share, t.team_id, t.owner_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.share = 'company' then perform app.require('deals', 'configure');
  elsif t.owner_id is distinct from v_me then perform app.require('deals', 'edit_others');
  else perform app.require('deals', 'add'); end if;
  update app.document_templates set deleted_at = now(), updated_at = now(), updated_by = v_me, version = version + 1 where id = t.id;
  insert into app.changelog (entity, record_id, field, actor_id, source) values ('document_template', t.id, '*deleted', v_me, 'ui');
  perform app.log('record.deleted', 'document_template', t.id::text, jsonb_build_object('count', 1));
  return jsonb_build_object('deleted', 1);
end $fn$;

-- ---------------------------------------------------------------------------
-- e-signature (DOC-05, SF-20)
-- a draft request: its signers (no cap unless count_limits is a number, Q24) and their fields
create function public.signature_request_save(p_id uuid, p_document uuid, p_signers jsonb, p_fields jsonb, p_message text default null,
                                              p_language text default 'nb', p_otp boolean default true, p_version int default null,
                                              p_signing_order text default 'parallel') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add'); r app.signature_requests; d app.documents; s jsonb; f jsonb; v_n int; v_limit numeric := app.count_limit();
  v_ids uuid[] := '{}'; v_sid uuid; i int := 0; v_out jsonb := '[]'::jsonb;
begin
  perform app.require_module('documents');
  if p_id is not null then
    select * into r from app.signature_requests where id = p_id for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    d := app.doc_row(r.document_id);
    if p_version is not null and r.version <> p_version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = r.version::text;
    end if;
    if r.status <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  else
    d := app.doc_row(p_document);
    if exists (select 1 from app.signature_requests x where x.document_id = d.id and x.status in ('draft', 'sent', 'in_progress')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'request_open';
    end if;
  end if;
  perform app.doc_require_edit(d.owner_id);
  if d.status in ('signed', 'revoked') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'document_status'; end if;
  if jsonb_typeof(coalesce(p_signers, '[]'::jsonb)) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers'; end if;
  if jsonb_typeof(coalesce(p_fields, '[]'::jsonb)) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields'; end if;
  v_n := jsonb_array_length(coalesce(p_signers, '[]'::jsonb));
  if v_limit is not null and v_n > v_limit then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.limit'; end if;
  if coalesce(p_language, 'nb') not in ('nb', 'en', 'sv') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'language'; end if;
  if coalesce(p_signing_order, 'parallel') not in ('parallel', 'sequential') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signing_order'; end if;
  if p_message is not null and char_length(p_message) > 2000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'message'; end if;
  for s in select * from jsonb_array_elements(coalesce(p_signers, '[]'::jsonb)) loop
    if jsonb_typeof(s) <> 'object' or char_length(btrim(coalesce(s ->> 'name', ''))) not between 1 and 200 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.name';
    end if;
    if coalesce(s ->> 'email', '') !~ '^[^@\s]+@[^@\s]+$' or char_length(s ->> 'email') > 254 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.email';
    end if;
    if s ->> 'color' is not null and s ->> 'color' !~ '^#[0-9A-F]{6}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.color'; end if;
    if s ->> 'person_id' is not null and not exists (select 1 from app.people p where p.id::text = s ->> 'person_id' and p.deleted_at is null) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.person_id';
    end if;
  end loop;
  for f in select * from jsonb_array_elements(coalesce(p_fields, '[]'::jsonb)) loop
    if jsonb_typeof(f) <> 'object' or jsonb_typeof(f -> 'signer') <> 'number' or (f ->> 'signer')::numeric not between 1 and v_n
       or (f ->> 'signer')::numeric % 1 <> 0 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.signer';
    end if;
    if coalesce(f ->> 'kind', '') not in ('signature', 'date', 'initials', 'text', 'checkbox') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.kind';
    end if;
    if jsonb_typeof(f -> 'x') <> 'number' or jsonb_typeof(f -> 'y') <> 'number' or jsonb_typeof(f -> 'w') <> 'number' or jsonb_typeof(f -> 'h') <> 'number'
       or (f ->> 'x')::numeric not between 0 and 100 or (f ->> 'y')::numeric not between 0 and 100 or (f ->> 'w')::numeric not between 0 and 100
       or (f ->> 'h')::numeric not between 0 and 100 or (f ->> 'x')::numeric + (f ->> 'w')::numeric > 100 or (f ->> 'y')::numeric + (f ->> 'h')::numeric > 100
       or coalesce((f ->> 'page')::numeric, 1) < 1 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.position';
    end if;
  end loop;

  if p_id is null then
    insert into app.signature_requests (document_id, service, message, language, otp_required, signing_order, created_by, is_sample)
    values (d.id, app.setting('esign_service'), p_message, coalesce(p_language, 'nb'), coalesce(p_otp, true), coalesce(p_signing_order, 'parallel'), v_me, d.is_sample)
    returning * into r;
    perform app.sig_event(r.id, null, 'created', null, '{}'::jsonb);
  else
    update app.signature_requests set message = p_message, language = coalesce(p_language, 'nb'), otp_required = coalesce(p_otp, true),
      signing_order = coalesce(p_signing_order, 'parallel'), version = version + 1, updated_at = now()
    where id = r.id returning * into r;
    delete from app.signature_signers where request_id = r.id;
  end if;
  for s in select * from jsonb_array_elements(coalesce(p_signers, '[]'::jsonb)) loop
    i := i + 1;
    insert into app.signature_signers (request_id, ord, person_id, name, email, color)
    values (r.id, i, (s ->> 'person_id')::uuid, btrim(s ->> 'name'), lower(btrim(s ->> 'email')), s ->> 'color')
    returning id into v_sid;
    v_ids := v_ids || v_sid;
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_sid, 'ord', i));
  end loop;
  insert into app.signature_fields (request_id, signer_id, kind, page, x, y, w, h, required)
  select r.id, v_ids[(fx ->> 'signer')::int], fx ->> 'kind', coalesce((fx ->> 'page')::int, 1), (fx ->> 'x')::numeric, (fx ->> 'y')::numeric,
         (fx ->> 'w')::numeric, (fx ->> 'h')::numeric, coalesce((fx ->> 'required')::boolean, true)
  from jsonb_array_elements(coalesce(p_fields, '[]'::jsonb)) fx;
  perform app.log('signature_request.saved', 'document', d.id::text,
                  jsonb_build_object('request', r.id, 'signers', v_n, 'fields', jsonb_array_length(coalesce(p_fields, '[]'::jsonb))));
  return jsonb_build_object('id', r.id, 'version', r.version, 'signers', v_out);
end $fn$;

-- send for signature: the document's hash is frozen, the document awaits signatures, the invitations are queued
create function public.signature_request_send(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add'); r app.signature_requests; d app.documents; v_service text := app.setting('esign_service');
  v_limit numeric := app.count_limit(); x record; n int := 0;
begin
  perform app.require_module('documents');
  select * into r from app.signature_requests where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  d := app.doc_row(r.document_id);
  perform app.doc_require_edit(d.owner_id);
  if r.status <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if cardinality(d.merge_missing) > 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge'; end if;
  if not exists (select 1 from app.signature_signers s where s.request_id = r.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers';
  end if;
  if v_limit is not null and (select count(*) from app.signature_signers s where s.request_id = r.id) > v_limit then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'signers.limit';
  end if;
  if exists (select 1 from app.signature_signers s where s.request_id = r.id
             and not exists (select 1 from app.signature_fields f where f.signer_id = s.id and f.kind = 'signature')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields';
  end if;
  if d.pdf_path is null or d.pdf_sha256 is null then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'pdf'; end if;
  if v_service = 'builtin' and not exists (select 1 from app.integration_connections c where c.provider = 'email' and c.status = 'connected') then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'email';
  end if;
  if v_service = 'external' and not exists (select 1 from app.integration_connections c where c.provider = 'esign' and c.status = 'connected') then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'esign';
  end if;
  update app.signature_requests set status = 'sent', service = v_service, sent_at = now(), original_sha256 = d.pdf_sha256,
    expires_at = coalesce(expires_at, now() + interval '30 days'), version = version + 1, updated_at = now()
  where id = r.id returning * into r;
  perform app.sig_event(r.id, null, 'sent', r.original_sha256, jsonb_build_object('signers', (select count(*) from app.signature_signers s where s.request_id = r.id),
                                                                                   'service', r.service, 'otp', r.otp_required));
  perform app.doc_status_set(d.id, 'awaiting_signature');
  if r.service = 'builtin' then
    for x in select s.id from app.signature_signers s where s.request_id = r.id and (r.signing_order = 'parallel' or s.ord = 1) order by s.ord loop
      perform pgmq.send('jobs', jsonb_build_object('job', 'sign_invite', 'signer_id', x.id));
      n := n + 1;
    end loop;
  else
    perform pgmq.send('jobs', jsonb_build_object('job', 'esign_send', 'request_id', r.id));
  end if;
  perform app.doc_emit('document.sent', d.id, jsonb_build_object('request', r.id));
  perform app.doc_history(d.id, 'document.signature_sent', jsonb_build_object('request', r.id));
  perform app.log('signature_request.sent', 'document', d.id::text, jsonb_build_object('request', r.id, 'service', r.service, 'invitations', n));
  return jsonb_build_object('id', r.id, 'status', r.status, 'version', r.version, 'invitations', n);
end $fn$;

create function public.signature_request_remind(p_id uuid, p_signer uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); r app.signature_requests; d app.documents; s app.signature_signers;
begin
  perform app.require_module('documents');
  select * into r from app.signature_requests where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  d := app.doc_row(r.document_id);
  perform app.doc_require_edit(d.owner_id);
  select * into s from app.signature_signers where id = p_signer and request_id = r.id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'signer'; end if;
  if r.status not in ('sent', 'in_progress') or r.service <> 'builtin' or s.status not in ('sent', 'opened', 'code_verified') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  perform pgmq.send('jobs', jsonb_build_object('job', 'sign_invite', 'signer_id', s.id, 'reminder', true));
  perform app.sig_event(r.id, s.id, 'reminded', null, '{}'::jsonb);
  perform app.log('signature_request.reminded', 'document', d.id::text, jsonb_build_object('request', r.id, 'signer', s.id));
  return jsonb_build_object('queued', true);
end $fn$;

create function public.signature_request_cancel(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); r app.signature_requests; d app.documents;
begin
  perform app.require_module('documents');
  select * into r from app.signature_requests where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  d := app.doc_row(r.document_id);
  perform app.doc_require_edit(d.owner_id);
  if r.status not in ('draft', 'sent', 'in_progress') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  update app.signature_requests set status = 'canceled', version = version + 1, updated_at = now() where id = r.id;
  update app.signature_signers set token_sha256 = null, otp_hash = null where request_id = r.id;
  perform app.sig_event(r.id, null, 'canceled', null, '{}'::jsonb);
  if d.status = 'awaiting_signature' then
    perform app.doc_status_set(d.id, case when exists (select 1 from app.document_links l where l.document_id = d.id) then 'sent' else 'draft' end);
  end if;
  if r.service = 'external' and r.external_id is not null then
    perform pgmq.send('jobs', jsonb_build_object('job', 'esign_cancel', 'request_id', r.id));
  end if;
  perform app.log('signature_request.canceled', 'document', d.id::text, jsonb_build_object('request', r.id));
  return jsonb_build_object('status', 'canceled');
end $fn$;

create function public.signature_request_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); r app.signature_requests; d app.documents;
begin
  perform app.require_module('documents');
  select * into r from app.signature_requests where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  d := app.doc_row(r.document_id);
  perform app.log('record.read', 'document', d.id::text, jsonb_build_object('request', r.id));
  return (to_jsonb(r) - 'original_sha256' - 'sealed_sha256') || jsonb_build_object(
    'original_sha256', encode(r.original_sha256, 'hex'), 'sealed_sha256', encode(r.sealed_sha256, 'hex'),
    'document', jsonb_build_object('id', d.id, 'name', d.name, 'number', d.number, 'status', d.status),
    'signer_limit', app.count_limit(),
    'signers', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'ord', s.ord, 'name', s.name, 'email', s.email, 'color', s.color,
                           'person_id', s.person_id, 'status', s.status, 'invited_at', s.invited_at, 'opened_at', s.opened_at, 'verified_at', s.verified_at,
                           'signed_at', s.signed_at, 'declined_at', s.declined_at, 'decline_reason', s.decline_reason) order by s.ord)
                         from app.signature_signers s where s.request_id = r.id), '[]'::jsonb),
    'fields', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'signer_id', f.signer_id, 'kind', f.kind, 'page', f.page, 'x', f.x, 'y', f.y,
                          'w', f.w, 'h', f.h, 'required', f.required, 'filled', f.filled_at is not null) order by f.page, f.y, f.x)
                        from app.signature_fields f where f.request_id = r.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('seq', e.seq, 'kind', e.kind, 'at', e.at, 'signer_id', e.signer_id,
                          'signer_name', (select s.name from app.signature_signers s where s.id = e.signer_id),
                          'hash', encode(e.hash, 'hex')) order by e.seq)
                        from app.signature_events e where e.request_id = r.id), '[]'::jsonb),
    'chain_ok', app.signature_chain_ok(r.id));
end $fn$;

-- ---------------------------------------------------------------------------
-- storage and branding (DOC-03, DOC-06). Branding and the e-sign service are settings (0030), set with setting_set.
create function public.doc_storage_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  perform app.require_module('documents');
  return jsonb_build_object(
    'default', (select jsonb_build_object('provider', s.provider, 'location', s.location, 'set_at', s.set_at,
                                          'set_by', (select a.name from app.admins a where a.id = s.set_by)) from app.document_storage_default s),
    'connections', coalesce((select jsonb_agg(jsonb_build_object('provider', c.provider, 'account_email', c.account_email, 'status', c.status,
                                                                 'connected_at', c.connected_at) order by c.provider)
                             from app.drive_connections c where c.staff_id = v_me), '[]'::jsonb),
    'branding', app.setting('doc_branding'),
    'esign_service', app.setting('esign_service'),
    'esign_connected', exists (select 1 from app.integration_connections c where c.provider = 'esign' and c.status = 'connected'),
    'email_connected', exists (select 1 from app.integration_connections c where c.provider = 'email' and c.status = 'connected'),
    'signer_limit', app.count_limit(),
    'can_configure', app.can('global', 'configure'));
end $fn$;

-- the OAuth URL for the caller's own drive. No drive OAuth client is configured yet (the adapter is an edge worker
-- that does not exist), so the answer is not_connected for the provider.
create function public.doc_storage_connect(p_provider text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  perform app.require_module('documents');
  if p_provider not in ('google', 'microsoft') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = p_provider;
end $fn$;

create function public.doc_storage_set_default(p_provider text, p_location jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'configure'); v_loc jsonb := coalesce(p_location, '{}'::jsonb); v_drive text;
begin
  perform app.require_module('documents');
  if p_provider not in ('platform', 'google', 'onedrive', 'sharepoint') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  if p_provider = 'platform' then
    v_loc := '{}'::jsonb;
  else
    if jsonb_typeof(v_loc) <> 'object' or coalesce(v_loc ->> 'kind', '') not in ('shared', 'personal')
       or char_length(coalesce(v_loc ->> 'label', '')) > 120 or char_length(coalesce(v_loc ->> 'drive_id', '')) > 200
       or char_length(coalesce(v_loc ->> 'folder_id', '')) > 200
       or exists (select 1 from jsonb_object_keys(v_loc) k where k not in ('kind', 'drive_id', 'folder_id', 'label')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'location';
    end if;
    v_drive := case p_provider when 'google' then 'google' else 'microsoft' end;
    if not exists (select 1 from app.drive_connections c where c.staff_id = v_me and c.provider = v_drive and c.status = 'connected') then
      raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = v_drive;
    end if;
  end if;
  update app.document_storage_default set provider = p_provider, location = v_loc, set_by = v_me, set_at = now() where id;
  perform app.log('document_storage.default_set', 'setting', 'document_storage_default', jsonb_build_object('provider', p_provider));
  return jsonb_build_object('provider', p_provider);
end $fn$;

-- ---------------------------------------------------------------------------
-- workers (service role only): the public host's viewer and signing pages, the PDF worker and the adapters

-- a view of a link (go.owntheagenda.com/d/<token>): refused when revoked or expired (the page answers 410). A view
-- records the time and the client class; document.opened is emitted once per link per day (Oslo time).
create function public.worker_doc_view(p_token text, p_client_class text default 'unknown') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  l app.document_links; d app.documents; v_cls text := case when p_client_class in ('human', 'prefetch', 'unknown') then p_client_class else 'unknown' end;
  v_day timestamptz := (date_trunc('day', now() at time zone 'Europe/Oslo')) at time zone 'Europe/Oslo'; v_first boolean; v_view bigint;
begin
  select * into l from app.document_links where token_sha256 = sha256(convert_to(coalesce(p_token, ''), 'UTF8'));
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if l.revoked_at is not null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'revoked'; end if;
  if l.expires_at is not null and l.expires_at <= now() then raise exception 'not_found' using errcode = 'no_data_found', detail = 'expired'; end if;
  select * into d from app.documents where id = l.document_id and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'revoked'; end if;
  v_first := not exists (select 1 from app.document_views v where v.link_id = l.id and v.client_class <> 'prefetch' and v.started_at >= v_day);
  insert into app.document_views (link_id, document_id, client_class) values (l.id, d.id, v_cls) returning id into v_view;
  if v_cls <> 'prefetch' then
    update app.documents set first_opened_at = coalesce(first_opened_at, now()), last_opened_at = now() where id = d.id;
    if d.status = 'sent' then perform app.doc_status_set(d.id, 'opened'); end if;
    if v_first then perform app.doc_emit('document.opened', d.id, jsonb_build_object('link', l.id)); end if;
    perform app.doc_history(d.id, 'document.opened', jsonb_build_object('link', l.id));
    if l.notify_owner and d.owner_id is not null then
      perform app.notify(d.owner_id, 'system', 'document.opened', jsonb_build_object('document', d.id, 'number', d.number,
                         'recipient', (select p.name from app.people p where p.id = l.recipient_person_id)), '/documents', 'document', d.id);
    end if;
  end if;
  return jsonb_build_object('view', v_view, 'document', jsonb_build_object('id', d.id, 'name', d.name, 'number', d.number, 'kind', d.kind,
                              'product', d.product, 'valid_until', d.valid_until, 'body_html', d.body_html, 'has_pdf', d.pdf_path is not null,
                              'pdf_path', d.pdf_path, 'external_url', d.external_url),
                            'branding', app.setting('doc_branding'));
end $fn$;

-- the viewer page's heartbeat: how long the page stayed open
create function public.worker_doc_heartbeat(p_view bigint, p_seconds int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v int;
begin
  update app.document_views set duration_seconds = greatest(duration_seconds, least(greatest(coalesce(p_seconds, 0), 0), 86400))
  where id = p_view and started_at > now() - interval '1 day' returning duration_seconds into v;
  if v is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('duration_seconds', v);
end $fn$;

-- the signer behind a signing token, while their request is open
create function app.sign_signer(p_token text) returns app.signature_signers
  language plpgsql stable security definer set search_path = ''
as $fn$
declare s app.signature_signers; r app.signature_requests;
begin
  select * into s from app.signature_signers where token_sha256 = sha256(convert_to(coalesce(p_token, ''), 'UTF8'));
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into r from app.signature_requests where id = s.request_id;
  if r.status not in ('sent', 'in_progress') then raise exception 'not_found' using errcode = 'no_data_found', detail = r.status; end if;
  if r.expires_at is not null and r.expires_at <= now() then raise exception 'not_found' using errcode = 'no_data_found', detail = 'expired'; end if;
  if s.status in ('signed', 'declined') then raise exception 'not_found' using errcode = 'no_data_found', detail = s.status; end if;
  return s;
end $fn$;

-- the invitation (and a reminder): a fresh signing token, returned once to the email worker, which sends the
-- go.owntheagenda.com/s/<token> link. A sequential request invites a signer only after everyone before them signed.
create function public.worker_sign_invite(p_signer uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.signature_signers; r app.signature_requests; d app.documents; v_token text := app.token(); v_reminder boolean;
begin
  select * into s from app.signature_signers where id = p_signer for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into r from app.signature_requests where id = s.request_id;
  if r.status not in ('sent', 'in_progress') or r.service <> 'builtin' or s.status in ('signed', 'declined') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  if r.signing_order = 'sequential' and exists (select 1 from app.signature_signers x where x.request_id = r.id and x.ord < s.ord and x.status <> 'signed') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'order';
  end if;
  select * into d from app.documents where id = r.document_id;
  v_reminder := s.token_sha256 is not null;
  update app.signature_signers set token_sha256 = sha256(convert_to(v_token, 'UTF8')), invited_at = now(),
    status = case when status = 'waiting' then 'sent' else status end
  where id = s.id;
  if not v_reminder then perform app.sig_event(r.id, s.id, 'sent', r.original_sha256, '{}'::jsonb); end if;
  return jsonb_build_object('path', '/s/' || v_token, 'token', v_token, 'email', s.email, 'name', s.name, 'language', r.language,
                            'message', r.message, 'document_name', d.name, 'document_number', d.number, 'product', d.product,
                            'otp_required', r.otp_required, 'reminder', v_reminder, 'branding', app.setting('doc_branding'));
end $fn$;

-- the signing page opens (SF-20 step 3)
create function public.worker_sign_view(p_token text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.signature_signers := app.sign_signer(p_token); r app.signature_requests; d app.documents;
begin
  select * into r from app.signature_requests where id = s.request_id;
  select * into d from app.documents where id = r.document_id;
  if s.opened_at is null then
    update app.signature_signers set opened_at = now(), status = case when status in ('waiting', 'sent') then 'opened' else status end where id = s.id;
    perform app.sig_event(r.id, s.id, 'opened', r.original_sha256, '{}'::jsonb);
  end if;
  if r.status = 'sent' then update app.signature_requests set status = 'in_progress', updated_at = now() where id = r.id; end if;
  return jsonb_build_object('request', r.id, 'signer', jsonb_build_object('id', s.id, 'name', s.name, 'ord', s.ord,
                                                                           'verified', s.verified_at is not null),
                            'otp_required', r.otp_required, 'language', r.language, 'message', r.message,
                            'document', jsonb_build_object('id', d.id, 'name', d.name, 'number', d.number, 'product', d.product, 'pdf_path', d.pdf_path,
                                                           'sha256', encode(r.original_sha256, 'hex')),
                            'fields', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'page', f.page, 'x', f.x, 'y', f.y, 'w', f.w,
                                                                                    'h', f.h, 'required', f.required) order by f.page, f.y, f.x)
                                                from app.signature_fields f where f.signer_id = s.id), '[]'::jsonb),
                            'branding', app.setting('doc_branding'));
end $fn$;

-- a one-time code by email: returned once to the email worker, stored only as a hash, valid 10 minutes. After five
-- wrong attempts the signer is locked until that code has expired; then a new code may be sent.
create function public.worker_sign_otp_send(p_token text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.signature_signers := app.sign_signer(p_token); v_code text;
begin
  if s.otp_attempts >= 5 and s.otp_expires_at > now() then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'otp_locked';
  end if;
  v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  update app.signature_signers set otp_hash = sha256(convert_to(s.id::text || ':' || v_code, 'UTF8')), otp_expires_at = now() + interval '10 minutes',
    otp_attempts = 0
  where id = s.id;
  perform app.sig_event(s.request_id, s.id, 'otp_sent', null, '{}'::jsonb);
  return jsonb_build_object('code', v_code, 'email', s.email, 'name', s.name, 'expires_in', 600);
end $fn$;

-- the code typed in. A wrong code is counted (and kept: the answer is a result, not an error, so the count survives).
create function public.worker_sign_otp_verify(p_token text, p_code text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.signature_signers := app.sign_signer(p_token); v_n smallint;
begin
  if s.otp_attempts >= 5 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'otp_locked'; end if;
  if s.otp_hash is null or s.otp_expires_at <= now() then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'otp_expired';
  end if;
  if sha256(convert_to(s.id::text || ':' || coalesce(btrim(p_code), ''), 'UTF8')) <> s.otp_hash then
    update app.signature_signers set otp_attempts = otp_attempts + 1 where id = s.id returning otp_attempts into v_n;
    perform app.sig_event(s.request_id, s.id, 'otp_failed', null, jsonb_build_object('attempt', v_n));
    return jsonb_build_object('verified', false, 'attempts_left', 5 - v_n, 'locked', v_n >= 5);
  end if;
  update app.signature_signers set verified_at = now(), otp_hash = null, status = 'code_verified' where id = s.id;
  -- SF-20 «time and address»: the address is the verified email address (Q9); no IP
  perform app.sig_event(s.request_id, s.id, 'otp_verified', null, jsonb_build_object('email', s.email));
  return jsonb_build_object('verified', true, 'attempts_left', 5 - s.otp_attempts, 'locked', false);
end $fn$;

-- the signer fills their fields and signs (SF-20 steps 5–6). When the last signer signs, the request completes.
create function public.worker_sign_submit(p_token text, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  s app.signature_signers := app.sign_signer(p_token); r app.signature_requests; d app.documents; f app.signature_fields; v text;
  v_vals jsonb := coalesce(p_values, '{}'::jsonb); v_done boolean; v_next uuid;
begin
  select * into r from app.signature_requests where id = s.request_id for update;
  if r.otp_required and s.verified_at is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'otp'; end if;
  if r.signing_order = 'sequential' and exists (select 1 from app.signature_signers x where x.request_id = r.id and x.ord < s.ord and x.status <> 'signed') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'order';
  end if;
  if jsonb_typeof(v_vals) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if exists (select 1 from jsonb_object_keys(v_vals) k where not exists (select 1 from app.signature_fields x where x.signer_id = s.id and x.id::text = k)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields';
  end if;
  -- validate every field before writing any
  for f in select * from app.signature_fields where signer_id = s.id order by page, y, x loop
    v := case when f.kind = 'date' then coalesce(nullif(btrim(v_vals ->> f.id::text), ''), (now() at time zone 'Europe/Oslo')::date::text)
              else nullif(btrim(v_vals ->> f.id::text), '') end;
    if (f.required or f.kind = 'signature') and v is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || f.id; end if;
    if v is not null and (char_length(v) > 500 or (f.kind = 'checkbox' and v not in ('true', 'false'))
                          or (f.kind = 'date' and v !~ '^\d{4}-\d{2}-\d{2}$')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fields.' || f.id;
    end if;
  end loop;
  for f in select * from app.signature_fields where signer_id = s.id order by page, y, x loop
    v := case when f.kind = 'date' then coalesce(nullif(btrim(v_vals ->> f.id::text), ''), (now() at time zone 'Europe/Oslo')::date::text)
              else nullif(btrim(v_vals ->> f.id::text), '') end;
    continue when v is null;
    update app.signature_fields set value = v, filled_at = now() where id = f.id;
    -- the evidence names the field, never what was typed into it
    perform app.sig_event(r.id, s.id, 'field_filled', null, jsonb_build_object('field', f.id, 'kind', f.kind));
  end loop;
  update app.signature_signers set status = 'signed', signed_at = now(), otp_hash = null where id = s.id;
  perform app.sig_event(r.id, s.id, 'signed', r.original_sha256, jsonb_build_object('email', s.email));
  perform app.doc_emit('document.signed', r.document_id, jsonb_build_object('request', r.id, 'signer', s.id));
  perform app.doc_history(r.document_id, 'document.signed', jsonb_build_object('request', r.id, 'signer', s.id));
  v_done := not exists (select 1 from app.signature_signers x where x.request_id = r.id and x.status <> 'signed');
  if v_done then
    update app.signature_requests set status = 'completed', completed_at = now(), version = version + 1, updated_at = now() where id = r.id;
    perform app.sig_event(r.id, null, 'completed', r.original_sha256, jsonb_build_object('signers', (select count(*) from app.signature_signers x where x.request_id = r.id)));
    perform app.doc_status_set(r.document_id, 'signed');
    perform app.doc_emit('document.completed', r.document_id, jsonb_build_object('request', r.id));
    perform app.doc_history(r.document_id, 'document.completed', jsonb_build_object('request', r.id));
    select * into d from app.documents where id = r.document_id;
    if d.owner_id is not null then
      perform app.notify(d.owner_id, 'system', 'document.completed', jsonb_build_object('document', d.id, 'number', d.number), '/documents', 'document', d.id);
    end if;
    -- the PDF worker seals the signed PDF with the audit trail and reports through worker_sign_sealed
    perform pgmq.send('jobs', jsonb_build_object('job', 'sign_seal', 'request_id', r.id));
  else
    update app.signature_requests set status = 'in_progress', updated_at = now() where id = r.id and status = 'sent';
    if r.signing_order = 'sequential' then
      select x.id into v_next from app.signature_signers x where x.request_id = r.id and x.status <> 'signed' order by x.ord limit 1;
      if v_next is not null then perform pgmq.send('jobs', jsonb_build_object('job', 'sign_invite', 'signer_id', v_next)); end if;
    end if;
  end if;
  return jsonb_build_object('signed', true, 'completed', v_done);
end $fn$;

-- a decline, with a reason kept on the signer (shown to staff) and never in logs, events or the evidence detail
create function public.worker_sign_decline(p_token text, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.signature_signers := app.sign_signer(p_token); r app.signature_requests; d app.documents;
begin
  if p_reason is not null and char_length(p_reason) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reason'; end if;
  select * into r from app.signature_requests where id = s.request_id for update;
  update app.signature_signers set status = 'declined', declined_at = now(), decline_reason = nullif(btrim(p_reason), ''), otp_hash = null where id = s.id;
  update app.signature_requests set status = 'declined', version = version + 1, updated_at = now() where id = r.id;
  perform app.sig_event(r.id, s.id, 'declined', r.original_sha256, jsonb_build_object('reason_given', nullif(btrim(coalesce(p_reason, '')), '') is not null));
  perform app.doc_status_set(r.document_id, 'declined');
  perform app.doc_emit('document.declined', r.document_id, jsonb_build_object('request', r.id, 'signer', s.id));
  perform app.doc_history(r.document_id, 'document.declined', jsonb_build_object('request', r.id, 'signer', s.id));
  select * into d from app.documents where id = r.document_id;
  if d.owner_id is not null then
    perform app.notify(d.owner_id, 'system', 'document.declined', jsonb_build_object('document', d.id, 'number', d.number), '/documents', 'document', d.id);
  end if;
  return jsonb_build_object('declined', true);
end $fn$;

-- the PDF worker's sealed result: the signed PDF and the evidence page, kept on the platform (DOC-05)
create function public.worker_sign_sealed(p_request uuid, p_path text, p_sha256 bytea, p_evidence_path text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.signature_requests;
begin
  select * into r from app.signature_requests where id = p_request for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.status <> 'completed' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if p_path is null or p_evidence_path is null or p_sha256 is null or length(p_sha256) <> 32 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sealed';
  end if;
  update app.signature_requests set sealed_pdf_path = p_path, sealed_sha256 = p_sha256, evidence_path = p_evidence_path, updated_at = now() where id = r.id;
  perform app.sig_event(r.id, null, 'sealed', p_sha256, '{}'::jsonb);
  perform app.doc_history(r.document_id, 'document.sealed', jsonb_build_object('request', r.id));
  insert into app.audit (actor, action, target_type, target_id, detail, ok) values ('system', 'signature_request.sealed', 'document', r.document_id::text,
                                                                                   jsonb_build_object('request', r.id), true);
  return jsonb_build_object('sealed', true);
end $fn$;

-- the external service took the request (DOC-06)
create function public.worker_esign_sent(p_request uuid, p_external_id text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if coalesce(btrim(p_external_id), '') = '' or char_length(p_external_id) > 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'external_id';
  end if;
  update app.signature_requests set external_id = p_external_id, updated_at = now() where id = p_request and service = 'external' and external_id is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('ok', true);
end $fn$;

-- the external service's status, shown on the deal (DOC-06 acceptance)
create function public.worker_esign_status(p_external_id text, p_status text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.signature_requests;
begin
  if p_status not in ('sent', 'in_progress', 'completed', 'declined', 'canceled', 'expired') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  select * into r from app.signature_requests where external_id = p_external_id and service = 'external' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.status in ('completed', 'declined', 'canceled', 'expired') or r.status = p_status then return jsonb_build_object('status', r.status); end if;
  update app.signature_requests set status = p_status, completed_at = case when p_status = 'completed' then now() else completed_at end,
    version = version + 1, updated_at = now()
  where id = r.id;
  perform app.sig_event(r.id, null, case p_status when 'in_progress' then 'opened' else p_status end, r.original_sha256, jsonb_build_object('external', true));
  if p_status = 'completed' then
    perform app.doc_status_set(r.document_id, 'signed');
    perform app.doc_emit('document.completed', r.document_id, jsonb_build_object('request', r.id));
  elsif p_status = 'declined' then
    perform app.doc_status_set(r.document_id, 'declined');
    perform app.doc_emit('document.declined', r.document_id, jsonb_build_object('request', r.id));
  elsif p_status = 'expired' then
    perform app.doc_status_set(r.document_id, 'expired');
  end if;
  perform app.doc_history(r.document_id, 'document.signature_' || p_status, jsonb_build_object('request', r.id));
  return jsonb_build_object('status', p_status);
end $fn$;

-- the PDF worker (and the drive adapter) report where a document now lives and its hash. A document out for
-- signature keeps the PDF that was frozen.
create function public.worker_document_stored(p_id uuid, p_storage text, p_external_id text, p_url text, p_pdf_path text, p_sha256 bytea) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.documents;
begin
  select * into d from app.documents where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if coalesce(p_storage, d.storage) not in ('platform', 'google', 'onedrive', 'sharepoint') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'storage';
  end if;
  if p_sha256 is not null and length(p_sha256) <> 32 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sha256'; end if;
  if (p_pdf_path is not null or p_sha256 is not null) and d.status in ('awaiting_signature', 'signed')
     and (p_pdf_path is distinct from d.pdf_path or p_sha256 is distinct from d.pdf_sha256) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  update app.documents set storage = coalesce(p_storage, storage), external_file_id = coalesce(p_external_id, external_file_id),
    external_url = coalesce(p_url, external_url), pdf_path = coalesce(p_pdf_path, pdf_path), pdf_sha256 = coalesce(p_sha256, pdf_sha256), updated_at = now()
  where id = p_id;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'document.stored', 'document', p_id::text, jsonb_build_object('storage', coalesce(p_storage, d.storage), 'pdf', p_pdf_path is not null), true);
  return jsonb_build_object('ok', true);
end $fn$;

-- a staff member's drive, connected by the drive adapter's OAuth callback; the token goes into Vault (D-18)
create function public.worker_drive_connected(p_staff uuid, p_provider text, p_email text, p_token text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_old uuid; v_secret uuid; v_id uuid;
begin
  if not exists (select 1 from app.admins where id = p_staff and active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'staff'; end if;
  if p_provider not in ('google', 'microsoft') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  if coalesce(p_token, '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'token'; end if;
  select vault_secret_id into v_old from app.drive_connections where staff_id = p_staff and provider = p_provider;
  if v_old is not null then delete from vault.secrets where id = v_old; end if;
  v_secret := vault.create_secret(p_token, 'drive:' || p_provider || ':' || p_staff || ':' || extract(epoch from now())::bigint,
                                  'Drive OAuth token (0032): read by the drive adapter only.');
  insert into app.drive_connections (staff_id, provider, account_email, vault_secret_id, status, connected_at)
  values (p_staff, p_provider, lower(p_email), v_secret, 'connected', now())
  on conflict (staff_id, provider) do update set account_email = excluded.account_email, vault_secret_id = excluded.vault_secret_id,
    status = 'connected', connected_at = now()
  returning id into v_id;
  insert into app.audit (actor, action, target_type, target_id, detail, ok) values ('system', 'drive.connected', 'staff', p_staff::text,
                                                                                   jsonb_build_object('provider', p_provider), true);
  return jsonb_build_object('id', v_id);
end $fn$;

-- daily: requests past their expiry expire, and so does a document still waiting for them
create function app.signature_expire() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.signature_requests; n int := 0;
begin
  for r in select * from app.signature_requests where status in ('sent', 'in_progress') and expires_at <= now() for update skip locked loop
    update app.signature_requests set status = 'expired', version = version + 1, updated_at = now() where id = r.id;
    update app.signature_signers set token_sha256 = null, otp_hash = null where request_id = r.id;
    perform app.sig_event(r.id, null, 'expired', r.original_sha256, '{}'::jsonb);
    if (select status from app.documents where id = r.document_id) = 'awaiting_signature' then perform app.doc_status_set(r.document_id, 'expired'); end if;
    n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-signature-expire', '37 4 * * *', 'select app.signature_expire()');

-- ---------------------------------------------------------------------------
-- the engine: a workflow's event matches the event's suffix (deal + «won» ← deal.won) or its full kind (deal +
-- «document.completed» ← document.completed about a deal; lead + «form.submitted»; person + «campaign.clicked»).
create or replace function app.sub_workflows(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  r app.workflow_runs; w app.workflows; v_suffix text := split_part(ev.kind, '.', 2); v_parent uuid := nullif(ev.payload ->> '_run', '')::uuid;
  v_fields text[]; v_kind text := case when ev.kind = 'email.received' then 'email.replied' else ev.kind end;
begin
  -- waiting runs
  for r in select * from app.workflow_runs x where x.state = 'waiting' and x.wait_event = v_kind
             and (case when x.wait_event = 'email.sent' then x.wait_ref = ev.payload ->> 'message'
                       else (x.subject_type = ev.subject_type and x.subject_id = ev.subject_id)
                            or coalesce(ev.payload -> 'links', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('entity', x.subject_type, 'id', x.subject_id)) end)
           for update skip locked loop
    update app.workflow_run_steps set state = 'succeeded', finished_at = now() where run_id = r.id and state = 'waiting';
    update app.workflow_runs set state = 'running', wait_event = null, wait_ref = null, wait_deadline = null where id = r.id;
    perform app.wf_advance(r.id);
  end loop;
  -- new runs
  v_fields := array(select jsonb_array_elements_text(coalesce(ev.payload -> 'fields', '[]'::jsonb)));
  for w in select * from app.workflows x where x.state = 'active' and x.deleted_at is null and x.kind in ('workflow', 'lifecycle')
             and x.is_sample = ev.is_sample
             and ((x.trigger_type = 'event' and coalesce(ev.payload ->> 'source', '') <> 'product'
                   and x.trigger_config ->> 'entity' = ev.subject_type and x.trigger_config ->> 'event' in (v_suffix, ev.kind))
               or (x.trigger_type = 'product_event' and ev.payload ->> 'source' = 'product' and x.trigger_config ->> 'kind' = ev.kind))
           order by x.created_at loop
    continue when jsonb_typeof(w.trigger_config -> 'fields') = 'array' and jsonb_array_length(w.trigger_config -> 'fields') > 0
                  and not (v_fields && array(select jsonb_array_elements_text(w.trigger_config -> 'fields')));
    -- a product event may carry conditions on its data: {data: {key: value}}
    continue when w.trigger_type = 'product_event' and jsonb_typeof(w.trigger_config -> 'data') = 'object'
                  and not (coalesce(ev.payload -> 'data', '{}'::jsonb) @> (w.trigger_config -> 'data'));
    continue when not app.wf_in_scope(w, ev.subject_type, ev.subject_id);
    continue when ev.subject_id is null or not app.wf_match(ev.subject_type, ev.subject_id, w.trigger_config -> 'groups');
    perform app.wf_start(w.id, ev.subject_type, ev.subject_id, ev.id, v_parent);
  end loop;
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['document_templates', 'document_template_versions', 'document_counters', 'documents', 'document_links', 'document_views',
                           'signature_requests', 'signature_signers', 'signature_fields', 'signature_events', 'drive_connections',
                           'document_storage_default'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.document_visible(uuid, uuid, uuid, text)', 'app.doc_template_visible(text, uuid, uuid)', 'app.document_anchor()',
                           'app.document_retention()', 'app.doc_template_guard()',
                           'app.signature_event_hash(bytea, uuid, int, uuid, text, timestamptz, bytea, jsonb)', 'app.signature_event_chain()',
                           'app.signature_events_fixed()', 'app.signature_events_no_truncate()', 'app.signature_chain_ok(uuid)',
                           'app.sig_event(uuid, uuid, text, bytea, jsonb)', 'app.html_escape(text)', 'app.doc_html_unsafe(text)', 'app.doc_label(text, text)',
                           'app.doc_num(numeric, text)', 'app.doc_money(numeric, text, text)', 'app.doc_trim(numeric, text)', 'app.doc_date(date, text)',
                           'app.doc_tokens(text)', 'app.doc_product_table(uuid, text[], text)', 'app.doc_render(text, jsonb, text)', 'app.doc_row(uuid)',
                           'app.doc_require_edit(uuid)', 'app.doc_emit(text, uuid, jsonb)', 'app.doc_history(uuid, text, jsonb)', 'app.doc_status_set(uuid, text)',
                           'app.sign_signer(text)', 'app.signature_expire()', 'app.merge_value(text, jsonb)', 'app.merge_render(text, jsonb)',
                           'app.vis_sql(app.entities)', 'app.sub_workflows(app.events)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.merge_fields_get(text)', 'public.documents_get(jsonb)', 'public.document_get(uuid)', 'public.document_create(uuid, uuid, text)',
                           'public.document_upload(uuid, text, text, bigint)', 'public.document_update(uuid, jsonb, int)', 'public.document_delete(uuid[], text)',
                           'public.document_link_create(uuid, uuid, text, timestamptz, boolean)', 'public.document_link_revoke(uuid)',
                           'public.document_views(uuid)', 'public.document_file_url(uuid)', 'public.doc_templates_get(text)', 'public.doc_template_get(uuid)',
                           'public.doc_template_save(uuid, jsonb, int)', 'public.doc_template_import(text, text)', 'public.doc_template_delete(uuid)',
                           'public.signature_request_save(uuid, uuid, jsonb, jsonb, text, text, boolean, int, text)', 'public.signature_request_send(uuid)',
                           'public.signature_request_remind(uuid, uuid)', 'public.signature_request_cancel(uuid)', 'public.signature_request_get(uuid)',
                           'public.doc_storage_get()', 'public.doc_storage_connect(text)', 'public.doc_storage_set_default(text, jsonb)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_doc_view(text, text)', 'public.worker_doc_heartbeat(bigint, int)', 'public.worker_sign_invite(uuid)',
                           'public.worker_sign_view(text)', 'public.worker_sign_otp_send(text)', 'public.worker_sign_otp_verify(text, text)',
                           'public.worker_sign_submit(text, jsonb)', 'public.worker_sign_decline(text, text)',
                           'public.worker_sign_sealed(uuid, text, bytea, text)', 'public.worker_esign_sent(uuid, text)', 'public.worker_esign_status(text, text)',
                           'public.worker_document_stored(uuid, text, text, text, text, bytea)', 'public.worker_drive_connected(uuid, text, text, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
