-- 0078_v3_foundation.sql — what the v3 builders share (docs/crm-enrichment/v3/PLAN.md, wave 0)
--
-- 1. A «dev» right scope for the Development section: Admin has every right; Support may see and add (Bug triage);
--    Read-only may see.
-- 2. Feature requests, recorded by staff on behalf of an organisation (one vote per organisation), linked to the tickets
--    and deals that asked for them (only ones the linker may see; a reader is shown only the ones they may see).
--    Development › Roadmap and Platform › Customer success read the same rows.
-- 3. Release notes (the changelog): Development › Releases, Customers › Status and changelog and Customer success
--    write and read the same rows. Nothing is published outside Sentral yet (no public host, PLAN.md).
-- 4. One gateway to Claude (X-V3-2): the key arrives through secret-intake into Vault; a feature registers a context
--    function that assembles its input from Sentral's own records — never ticket text, never survey data (rule 6);
--    ai-run calls Claude and records the call in ai_calls (0042) and the draft in ai_outputs. Nothing a person types
--    reaches Claude except through a feature's context function. The hourly cap reserves each call before Claude is
--    asked (a pending row, completed by id, swept to a timeout when its run died); a person's own subject's drafts
--    (a test question) are theirs alone.
-- 5. The signing secrets Vercel's deployment webhooks (X-V3-1) and the products' CI post with, by intake number into
--    Vault. dev-events (the Development builder's) reads them; nothing else does.
-- Every table: app schema, RLS on, no policy, no grant. Every reader and writer: SECURITY DEFINER with search_path ''.

-- ===========================================================================
-- 1. the «dev» scope
-- ===========================================================================
create or replace function app.right_ok(p_right text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select split_part(p_right, ':', 1) in ('deals', 'projects', 'campaigns', 'global', 'tickets', 'dev')
     and split_part(p_right, ':', 2) in ('see', 'add', 'edit_others', 'delete', 'bulk', 'export', 'configure',
                                         'workflows', 'reports_others', 'ai', 'security')
     and p_right ~ '^[a-z]+:[a-z_]+$'
$fn$;
update app.permission_sets set rights = rights || array(select x from unnest(array['dev:see', 'dev:add']) x where not x = any (rights)), updated_at = now()
where key = 'support';
update app.permission_sets set rights = rights || array(select x from unnest(array['dev:see']) x where not x = any (rights)), updated_at = now()
where key = 'analyst';

-- the products Development knows: the applications, and Sentral itself for the platform's own work
create function app.dev_product_ok(p text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select p = 'sentral' or exists (select 1 from app.products x where x.key = p)
$fn$;

-- either of two rights (a row two sections share)
create function app.require_any(p_a text, p_b text) returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.me();
begin
  if v is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  if not (app.can(split_part(p_a, ':', 1), split_part(p_a, ':', 2)) or app.can(split_part(p_b, ':', 1), split_part(p_b, ':', 2))) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = p_a || '|' || p_b;
  end if;
  return v;
end $fn$;

-- ===========================================================================
-- 2. feature requests
-- ===========================================================================
create table app.feature_requests (
  id          uuid primary key default gen_random_uuid(),
  ref         int generated always as identity unique,
  product     text not null check (product ~ '^[a-z]{2,20}$'),
  title       text not null check (char_length(btrim(title)) between 3 and 200),
  problem     text check (problem is null or char_length(problem) <= 4000),
  status      text not null default 'under_review' check (status in ('under_review', 'planned', 'in_progress', 'shipped', 'declined')),
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  shipped_at  timestamptz,
  check (status <> 'shipped' or shipped_at is not null)
);
create index feature_requests_product on app.feature_requests (product, status);

create table app.feature_request_votes (
  request_id      uuid not null references app.feature_requests (id) on delete cascade,
  organization_id uuid not null references app.organizations (id) on delete cascade,
  recorded_by     uuid references app.admins (id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (request_id, organization_id)
);
create index feature_request_votes_org on app.feature_request_votes (organization_id);

create table app.feature_request_links (
  request_id uuid not null references app.feature_requests (id) on delete cascade,
  kind       text not null check (kind in ('ticket', 'deal')),
  ref        uuid not null,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (request_id, kind, ref)
);

alter table app.feature_requests enable row level security;
alter table app.feature_request_votes enable row level security;
alter table app.feature_request_links enable row level security;
revoke all on app.feature_requests, app.feature_request_votes, app.feature_request_links from public, anon, authenticated;

-- one request with its votes and links (organisation names; ids of the tickets and deals the reader may see, by the
-- same reading as Development's roadmap links: app.dev_ticket_ok and app.dev_deal_ok, 0079 — a queue the reader is not
-- in, a private deal, a deleted one is not listed). plpgsql, so the two helpers resolve when it runs.
create function app.feature_request_json(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  return (select jsonb_build_object(
    'id', r.id, 'ref', r.ref, 'product', r.product, 'title', r.title, 'problem', r.problem, 'status', r.status,
    'created_at', r.created_at, 'updated_at', r.updated_at, 'shipped_at', r.shipped_at,
    'votes', (select count(*) from app.feature_request_votes v where v.request_id = r.id),
    'organizations', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name) order by o.name)
                               from app.feature_request_votes v join app.organizations o on o.id = v.organization_id where v.request_id = r.id), '[]'::jsonb),
    'tickets', coalesce((select jsonb_agg(l.ref order by l.created_at) from app.feature_request_links l join app.tickets t on t.id = l.ref
                         where l.request_id = r.id and l.kind = 'ticket' and app.dev_ticket_ok(t)), '[]'::jsonb),
    'deals', coalesce((select jsonb_agg(l.ref order by l.created_at) from app.feature_request_links l join app.deals d on d.id = l.ref
                       where l.request_id = r.id and l.kind = 'deal' and app.dev_deal_ok(d)), '[]'::jsonb))
  from app.feature_requests r where r.id = p_id);
end $fn$;

create function public.feature_requests_list(p_product text, p_status text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_any('dev:see', 'global:see');
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if p_status is not null and p_status not in ('under_review', 'planned', 'in_progress', 'shipped', 'declined') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  return coalesce((select jsonb_agg(app.feature_request_json(r.id) order by r.status = 'shipped', r.updated_at desc)
                   from app.feature_requests r where r.product = p_product and (p_status is null or r.status = p_status)), '[]'::jsonb);
end $fn$;

create function public.feature_request_add(p_product text, p_title text, p_problem text default null, p_organization uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'global:add'); v_id uuid;
begin
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if p_problem is not null and char_length(p_problem) > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'problem'; end if;
  insert into app.feature_requests (product, title, problem, created_by) values (p_product, btrim(p_title), nullif(btrim(p_problem), ''), v_me) returning id into v_id;
  if p_organization is not null then
    if not exists (select 1 from app.organizations o where o.id = p_organization) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization'; end if;
    insert into app.feature_request_votes (request_id, organization_id, recorded_by) values (v_id, p_organization, v_me);
  end if;
  perform app.log('feature_request.added', 'feature_request', v_id::text);
  return app.feature_request_json(v_id);
end $fn$;

create function public.feature_request_set(p_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'global:add'); k text; v_status text;
begin
  if not exists (select 1 from app.feature_requests r where r.id = p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if jsonb_typeof(p_patch) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('title', 'problem', 'status') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if p_patch ? 'title' and char_length(btrim(coalesce(p_patch ->> 'title', ''))) not between 3 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title';
  end if;
  if p_patch ? 'problem' and char_length(coalesce(p_patch ->> 'problem', '')) > 4000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'problem';
  end if;
  v_status := p_patch ->> 'status';
  if p_patch ? 'status' and (v_status is null or v_status not in ('under_review', 'planned', 'in_progress', 'shipped', 'declined')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  update app.feature_requests r set
    title = case when p_patch ? 'title' then btrim(p_patch ->> 'title') else r.title end,
    problem = case when p_patch ? 'problem' then nullif(btrim(p_patch ->> 'problem'), '') else r.problem end,
    status = coalesce(v_status, r.status),
    shipped_at = case when coalesce(v_status, r.status) = 'shipped' then coalesce(r.shipped_at, now()) else null end,
    updated_at = now()
  where r.id = p_id;
  perform app.log('feature_request.changed', 'feature_request', p_id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_patch) x)));
  return app.feature_request_json(p_id);
end $fn$;

create function public.feature_request_vote(p_id uuid, p_organization uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'global:add');
begin
  if not exists (select 1 from app.feature_requests r where r.id = p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not exists (select 1 from app.organizations o where o.id = p_organization) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'organization'; end if;
  if coalesce(p_on, false) then
    insert into app.feature_request_votes (request_id, organization_id, recorded_by) values (p_id, p_organization, v_me) on conflict do nothing;
  else
    delete from app.feature_request_votes v where v.request_id = p_id and v.organization_id = p_organization;
  end if;
  update app.feature_requests set updated_at = now() where id = p_id;
  perform app.log(case when p_on then 'feature_request.voted' else 'feature_request.unvoted' end, 'feature_request', p_id::text);
  return app.feature_request_json(p_id);
end $fn$;

-- a link (or its removal) names only a ticket or deal the caller may see: one outside their queues or visibility is
-- «not found», as Development's roadmap links answer (app.dev_ticket_ok, app.dev_deal_ok, 0079)
create function public.feature_request_link(p_id uuid, p_kind text, p_ref uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'global:add');
begin
  if not exists (select 1 from app.feature_requests r where r.id = p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_kind = 'ticket' then
    if not exists (select 1 from app.tickets t where t.id = p_ref and app.dev_ticket_ok(t)) then
      raise exception 'not_found' using errcode = 'no_data_found', detail = 'ticket';
    end if;
  elsif p_kind = 'deal' then
    if not exists (select 1 from app.deals d where d.id = p_ref and app.dev_deal_ok(d)) then
      raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal';
    end if;
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end if;
  if coalesce(p_on, false) then
    insert into app.feature_request_links (request_id, kind, ref, created_by) values (p_id, p_kind, p_ref, v_me) on conflict do nothing;
  else
    delete from app.feature_request_links l where l.request_id = p_id and l.kind = p_kind and l.ref = p_ref;
  end if;
  update app.feature_requests set updated_at = now() where id = p_id;
  perform app.log('feature_request.linked', 'feature_request', p_id::text, jsonb_build_object('kind', p_kind, 'on', coalesce(p_on, false)));
  return app.feature_request_json(p_id);
end $fn$;

-- ===========================================================================
-- 3. release notes
-- ===========================================================================
create table app.release_notes (
  id                 uuid primary key default gen_random_uuid(),
  product            text not null check (product ~ '^[a-z]{2,20}$'),
  kind               text not null check (kind in ('new', 'improved', 'fixed')),
  title              text not null check (char_length(btrim(title)) between 3 and 200),
  body               text check (body is null or char_length(body) <= 4000),
  state              text not null default 'draft' check (state in ('draft', 'published')),
  source             text not null default 'manual' check (source in ('manual', 'release', 'ai', 'request')),
  feature_request_id uuid references app.feature_requests (id) on delete set null,
  published_at       timestamptz,
  published_by       uuid references app.admins (id) on delete set null,
  created_by         uuid references app.admins (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check ((state = 'published') = (published_at is not null))
);
create index release_notes_product on app.release_notes (product, state, published_at desc);
alter table app.release_notes enable row level security;
revoke all on app.release_notes from public, anon, authenticated;

create function app.release_note_json(n app.release_notes) returns jsonb
  language sql stable set search_path = ''
as $fn$
  select jsonb_build_object('id', n.id, 'product', n.product, 'kind', n.kind, 'title', n.title, 'body', n.body, 'state', n.state,
                            'source', n.source, 'feature_request_id', n.feature_request_id, 'published_at', n.published_at,
                            'created_at', n.created_at, 'updated_at', n.updated_at)
$fn$;

create function public.release_notes_list(p_product text, p_state text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if app.me() is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  if not (app.can('dev', 'see') or app.can('tickets', 'see') or app.can('global', 'see')) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'dev:see';
  end if;
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if p_state is not null and p_state not in ('draft', 'published') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  return coalesce((select jsonb_agg(app.release_note_json(n) order by n.state = 'draft' desc, coalesce(n.published_at, n.updated_at) desc)
                   from app.release_notes n where n.product = p_product and (p_state is null or n.state = p_state)), '[]'::jsonb);
end $fn$;

create function public.release_note_save(p_id uuid, p_product text, p_kind text, p_title text, p_body text default null,
                                         p_feature_request uuid default null, p_source text default 'manual') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'tickets:edit_others'); v_row app.release_notes;
begin
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if p_kind is null or p_kind not in ('new', 'improved', 'fixed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if p_body is not null and char_length(p_body) > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  if p_source is null or p_source not in ('manual', 'release', 'ai', 'request') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
  if p_feature_request is not null and not exists (select 1 from app.feature_requests r where r.id = p_feature_request) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'feature_request';
  end if;
  if p_id is null then
    insert into app.release_notes (product, kind, title, body, source, feature_request_id, created_by)
    values (p_product, p_kind, btrim(p_title), nullif(btrim(p_body), ''), p_source, p_feature_request, v_me) returning * into v_row;
    perform app.log('release_note.added', 'release_note', v_row.id::text);
  else
    update app.release_notes n set product = p_product, kind = p_kind, title = btrim(p_title), body = nullif(btrim(p_body), ''),
      feature_request_id = p_feature_request, updated_at = now()
    where n.id = p_id returning * into v_row;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('release_note.changed', 'release_note', p_id::text);
  end if;
  return app.release_note_json(v_row);
end $fn$;

create function public.release_note_publish(p_id uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'tickets:edit_others'); v_row app.release_notes;
begin
  update app.release_notes n set state = case when p_on then 'published' else 'draft' end,
    published_at = case when p_on then coalesce(n.published_at, now()) else null end,
    published_by = case when p_on then coalesce(n.published_by, v_me) else null end, updated_at = now()
  where n.id = p_id returning * into v_row;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log(case when p_on then 'release_note.published' else 'release_note.unpublished' end, 'release_note', p_id::text);
  return app.release_note_json(v_row);
end $fn$;

create function public.release_note_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'tickets:edit_others');
begin
  delete from app.release_notes n where n.id = p_id and n.state = 'draft';
  if not found then
    if exists (select 1 from app.release_notes n where n.id = p_id) then raise exception 'conflict' using errcode = 'check_violation', detail = 'published'; end if;
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  perform app.log('release_note.deleted', 'release_note', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- ===========================================================================
-- 4. connections, intake and Vault names: Claude (ai), Vercel's webhook and the products' CI
-- ===========================================================================
alter table app.integration_connections drop constraint if exists integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check check (provider in (
  'slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai', 'email',
  'ip_company', 'esign', 'pdf', 'meeting_bot', 'transcription', 'pagespeed', 'google_ads', 'linkedin_ads', 'meta_ads', 'vercel', 'ci'));
insert into app.integration_connections (provider, status) values ('ai', 'not_connected'), ('vercel', 'not_connected'), ('ci', 'not_connected')
on conflict (provider) do nothing;
alter table app.intake_nonces drop constraint if exists intake_nonces_purpose_check;
alter table app.intake_nonces add constraint intake_nonces_purpose_check check (purpose is null or purpose in (
  'brevo', 'search_console', 'pagespeed', 'google_ads', 'linkedin_ads', 'meta_ads', 'anthropic', 'vercel', 'ci'));

create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
                             or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret', 'search_console_key', 'search_console_worker_secret',
                                           'seo_crawl_worker_secret', 'pagespeed_api_key', 'pagespeed_worker_secret',
                                           'google_ads_developer_token', 'google_ads_key', 'linkedin_ads_client_secret', 'linkedin_ads_access_token',
                                           'linkedin_ads_refresh_token', 'meta_ads_token', 'meta_ads_app_secret', 'ads_worker_secret',
                                           'anthropic_api_key', 'vercel_signing_secret', 'ci_signing_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

-- one of the three by the intake number bound to it: that one name only, checked by shape
create function app.store_v3_secrets(p_purpose text, p_secrets jsonb) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare k text; v text; n int := 0; v_provider text;
begin
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    v := btrim(coalesce(v, ''));
    if p_purpose = 'anthropic' and k = 'anthropic_api_key' and v ~ '^sk-ant-[A-Za-z0-9_-]+$' and char_length(v) between 30 and 300 then
      perform app.vault_put(k, v, 'The Claude API key (0078): read by ai-run only.');
      v_provider := 'ai';
    elsif p_purpose = 'vercel' and k = 'vercel_signing_secret' and v ~ '^[A-Za-z0-9_-]+$' and char_length(v) between 16 and 256 then
      perform app.vault_put(k, v, 'The secret Vercel signs deployment webhooks with (0078): read by dev-events only.');
      v_provider := 'vercel';
    elsif p_purpose = 'ci' and k = 'ci_signing_secret' and v ~ '^[A-Za-z0-9_-]+$' and char_length(v) between 32 and 256 then
      perform app.vault_put(k, v, 'The secret the products'' CI signs its results with (0078): read by dev-events only.');
      v_provider := 'ci';
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
    end if;
    n := n + 1;
  end loop;
  if n > 0 then
    update app.integration_connections set
      status = case when v_provider = 'ai' then 'connected' else status end,
      connected_at = case when v_provider = 'ai' then now() else connected_at end,
      config = config || jsonb_build_object('key_stored_at', now(), 'last_error', null)
    where provider = v_provider;
  end if;
  return n;
end $fn$;
revoke all on function app.store_v3_secrets(text, jsonb) from public, anon, authenticated;

-- the owner opens an intake number for one of the three (fresh second factor)
create function public.v3_intake(p_purpose text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  if p_purpose is null or p_purpose not in ('anthropic', 'vercel', 'ci') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'purpose'; end if;
  perform app.require_fresh_mfa(10);
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at, purpose) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', p_purpose);
  perform app.log('integration.intake_opened', 'integration', p_purpose);
  return jsonb_build_object('intake_code', v, 'expires_in', 900);
end $fn$;

-- the owner removes one of the three (fresh second factor): the Vault secret goes, the connection says so
create function public.v3_disconnect(p_purpose text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v_name text; v_provider text;
begin
  perform app.require_fresh_mfa(10);
  v_name := case p_purpose when 'anthropic' then 'anthropic_api_key' when 'vercel' then 'vercel_signing_secret' when 'ci' then 'ci_signing_secret' end;
  v_provider := case p_purpose when 'anthropic' then 'ai' else p_purpose end;
  if v_name is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'purpose'; end if;
  delete from vault.secrets s where s.name = v_name;
  update app.integration_connections set status = 'not_connected', connected_at = null, config = config - 'key_stored_at' where provider = v_provider;
  perform app.log('integration.disconnected', 'integration', p_purpose);
  return jsonb_build_object('ok', true);
end $fn$;

-- ===========================================================================
-- 5. the Claude gateway
-- ===========================================================================
create table app.ai_settings (
  id         boolean primary key default true check (id),
  model      text not null default 'claude-opus-5-5' check (model ~ '^claude-[a-z0-9-]{3,40}$'),
  effort     text not null default 'medium' check (effort in ('low', 'medium', 'high')),
  hourly_cap int not null default 30 check (hourly_cap between 1 and 500),
  updated_at timestamptz not null default now(),
  updated_by uuid references app.admins (id) on delete set null
);
insert into app.ai_settings (id) values (true) on conflict do nothing;

-- a feature: the right that opens it, and the context function that builds its input from Sentral's records
create table app.ai_features (
  key          text primary key check (key ~ '^[a-z][a-z_]{2,39}$'),
  scope        text not null check (scope in ('deals', 'projects', 'campaigns', 'global', 'tickets', 'dev')),
  action       text not null check (action ~ '^[a-z_]{2,20}$'),
  subject_type text not null check (subject_type ~ '^[a-z_]{2,40}$'),
  context_fn   text not null check (context_fn ~ '^app\.ai_ctx_[a-z_]{2,40}$'),
  max_tokens   int not null default 4000 check (max_tokens between 256 and 16000),
  enabled      boolean not null default true
);

create table app.ai_outputs (
  id           uuid primary key default gen_random_uuid(),
  feature      text not null references app.ai_features (key),
  subject_type text not null,
  subject_id   uuid not null,
  staff_id     uuid references app.admins (id) on delete set null,
  body         text not null check (char_length(body) between 1 and 60000),
  state        text not null default 'ready' check (state in ('ready', 'used', 'discarded')),
  ai_call_id   bigint references app.ai_calls (id) on delete set null,
  created_at   timestamptz not null default now(),
  decided_at   timestamptz
);
create index ai_outputs_subject on app.ai_outputs (feature, subject_id, created_at desc);

alter table app.ai_settings enable row level security;
alter table app.ai_features enable row level security;
alter table app.ai_outputs enable row level security;
revoke all on app.ai_settings, app.ai_features, app.ai_outputs from public, anon, authenticated;

-- The hourly cap is the only spend control on the key, so it holds before Claude is asked: ai_prepare reserves the call as
-- a «pending» row in ai_calls (0042), counted from that moment; ai-run completes that row by its id; a row nobody completed
-- (the run was killed) becomes error/timeout after ten minutes and still counts.
alter table app.ai_calls drop constraint ai_calls_state_check,
  add constraint ai_calls_state_check check (state in ('ok', 'retried_ok', 'invalid', 'error', 'not_connected', 'pending'));
create index ai_calls_pending on app.ai_calls (at) where state = 'pending';

-- the log stays append-only (0042): besides the FK's own maintenance, a reserved call is completed once — its outcome
-- (model, tokens, latency, state, code) only; who, what, which subject and when never change
create or replace function app.ai_call_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if coalesce(current_setting('app.purging', true), '') = 'on' then return old; end if;
  elsif (to_jsonb(new) - 'staff_id') = (to_jsonb(old) - 'staff_id') and new.staff_id is null
        and not exists (select 1 from app.admins a where a.id = old.staff_id) then
    return new;
  elsif old.state = 'pending' and new.state <> 'pending'
        and (to_jsonb(new) - array['model', 'input_tokens', 'output_tokens', 'latency_ms', 'state', 'error_code'])
          = (to_jsonb(old) - array['model', 'input_tokens', 'output_tokens', 'latency_ms', 'state', 'error_code']) then
    return new;
  end if;
  raise exception 'the AI call log is append-only' using errcode = 'insufficient_privilege';
end $fn$;

-- a subject that belongs to one person: a staff member's own test question (0081). Its drafts are read and decided by
-- that person alone, whoever else holds the feature's right; every other subject's drafts are shared under the right.
create function app.ai_subject_ok(p_type text, p_subject uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_type = 'help_test_question' then
    return exists (select 1 from app.help_test_questions q where q.id = p_subject and q.created_by = app.me());
  end if;
  return true;
end $fn$;

-- the connection, the model and the features, for anyone who may use at least one feature (never the key)
create function public.ai_status() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.me();
begin
  if v_me is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  return jsonb_build_object(
    'connected', exists (select 1 from vault.secrets s where s.name = 'anthropic_api_key'),
    'key_stored_at', (select c.config ->> 'key_stored_at' from app.integration_connections c where c.provider = 'ai'),
    'can_manage', exists (select 1 from app.admins a where a.id = v_me and a.role = 'owner'),
    'model', (select s.model from app.ai_settings s), 'effort', (select s.effort from app.ai_settings s),
    'features', coalesce((select jsonb_agg(jsonb_build_object('key', f.key, 'enabled', f.enabled, 'allowed', app.can(f.scope, f.action)) order by f.key)
                          from app.ai_features f), '[]'::jsonb),
    'calls_30d', (select count(*) from app.ai_calls c where c.provider = 'anthropic' and c.at > now() - interval '30 days'),
    'failed_30d', (select count(*) from app.ai_calls c where c.provider = 'anthropic' and c.at > now() - interval '30 days'
                   and c.state not in ('ok', 'retried_ok', 'pending')),
    'tokens_30d', (select coalesce(sum(coalesce(c.input_tokens, 0) + coalesce(c.output_tokens, 0)), 0) from app.ai_calls c
                   where c.provider = 'anthropic' and c.at > now() - interval '30 days'));
end $fn$;

create function public.ai_settings_set(p_model text, p_effort text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  if p_model is null or p_model !~ '^claude-[a-z0-9-]{3,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'model'; end if;
  if p_effort is null or p_effort not in ('low', 'medium', 'high') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'effort'; end if;
  update app.ai_settings set model = p_model, effort = p_effort, updated_at = now(), updated_by = v_me where id;
  perform app.log('ai.settings_changed', 'integration', 'ai', jsonb_build_object('model', p_model, 'effort', p_effort));
  return jsonb_build_object('ok', true);
end $fn$;

-- ai-run asks this with the person's own token: may they, is it connected, within the hourly cap; then the feature's
-- context function assembles the input from Sentral's records, and the call is reserved (a pending ai_calls row) so it
-- counts against the cap before Claude is asked. Under a per-person advisory lock, so parallel requests are counted one
-- after another. Returns the request to send and the reserved call's id; the key never leaves Vault. A refusal or a
-- subject that builds no request rolls the reservation back with everything else.
create function public.ai_prepare(p_feature text, p_subject uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); f app.ai_features; s app.ai_settings; v_ctx jsonb; v_call bigint;
begin
  if v_me is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  select * into f from app.ai_features x where x.key = p_feature;
  if not found or not f.enabled then raise exception 'not_found' using errcode = 'no_data_found', detail = 'feature'; end if;
  perform app.require(f.scope, f.action);
  if not exists (select 1 from vault.secrets x where x.name = 'anthropic_api_key') then
    raise exception 'not_connected' using errcode = 'object_not_in_prerequisite_state';
  end if;
  select * into s from app.ai_settings;
  perform pg_advisory_xact_lock(hashtext('app.ai_cap'), hashtext(v_me::text));
  if (select count(*) from app.ai_calls c where c.staff_id = v_me and c.at > now() - interval '1 hour') >= s.hourly_cap then
    raise exception 'rate_limited' using errcode = 'program_limit_exceeded';
  end if;
  execute format('select %s($1)', f.context_fn) into v_ctx using p_subject;
  if v_ctx is null or jsonb_typeof(v_ctx -> 'system') <> 'string' or jsonb_typeof(v_ctx -> 'prompt') <> 'string' then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'subject';
  end if;
  insert into app.ai_calls (feature, staff_id, subject_type, subject_id, provider, model, state)
  values (f.key, v_me, f.subject_type, p_subject, 'anthropic', s.model, 'pending') returning id into v_call;
  return jsonb_build_object('call', v_call, 'feature', f.key, 'subject_type', f.subject_type, 'subject', p_subject, 'staff', v_me,
                            'model', s.model, 'effort', s.effort, 'max_tokens', f.max_tokens,
                            'system', v_ctx ->> 'system', 'prompt', v_ctx ->> 'prompt');
end $fn$;

-- ai-run completes the call ai_prepare reserved (p_call): kinds, counts and codes only, and the draft when there is one.
-- The reserved row decides the feature, subject and person; the ones passed must match it (a person not passed is the
-- one who reserved it; a model not passed is the one reserved). Without p_call (a call made outside ai-run, as the
-- suites record one) the call is a new row.
create function public.worker_ai_record(p_feature text, p_subject uuid, p_staff uuid, p_body text, p_model text, p_input int, p_output int,
                                        p_latency int, p_state text, p_error text, p_call bigint default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.ai_features; c app.ai_calls; v_call bigint; v_out uuid; v_staff uuid := p_staff;
begin
  select * into f from app.ai_features x where x.key = p_feature;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'feature'; end if;
  if p_state is null or p_state not in ('ok', 'retried_ok', 'invalid', 'error', 'not_connected') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state';
  end if;
  if p_call is not null then
    select * into c from app.ai_calls x where x.id = p_call for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'call'; end if;
    if c.feature <> p_feature or c.subject_id is distinct from p_subject or (p_staff is not null and c.staff_id is not null and c.staff_id <> p_staff) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'call';
    end if;
    if c.state <> 'pending' then raise exception 'conflict' using errcode = 'object_not_in_prerequisite_state', detail = 'call'; end if;
    update app.ai_calls x set model = coalesce(left(p_model, 80), x.model), input_tokens = greatest(p_input, 0), output_tokens = greatest(p_output, 0),
      latency_ms = greatest(p_latency, 0), state = p_state,
      error_code = case when p_state in ('ok', 'retried_ok') then null else left(coalesce(p_error, 'error'), 80) end
    where x.id = p_call;
    v_call := p_call;
    v_staff := c.staff_id;
  else
    insert into app.ai_calls (feature, staff_id, subject_type, subject_id, provider, model, input_tokens, output_tokens, latency_ms, state, error_code)
    values (p_feature, p_staff, f.subject_type, p_subject, 'anthropic', left(p_model, 80), greatest(p_input, 0), greatest(p_output, 0), greatest(p_latency, 0),
            p_state, case when p_state in ('ok', 'retried_ok') then null else left(coalesce(p_error, 'error'), 80) end)
    returning id into v_call;
  end if;
  if p_state in ('ok', 'retried_ok') and char_length(coalesce(p_body, '')) between 1 and 60000 then
    insert into app.ai_outputs (feature, subject_type, subject_id, staff_id, body, ai_call_id)
    values (p_feature, f.subject_type, p_subject, v_staff, p_body, v_call) returning id into v_out;
  end if;
  return jsonb_build_object('call', v_call, 'output', v_out);
end $fn$;

-- a reserved call nobody completed in ten minutes (ai-run gives up well before: its own budget is under the app's
-- 150 s) was killed with its run: it becomes error/timeout and keeps counting against the cap. Every five minutes,
-- through the job monitor.
create function app.ai_calls_sweep() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  update app.ai_calls c set state = 'error', error_code = 'timeout'
  where c.state = 'pending' and c.at < now() - interval '10 minutes';
  get diagnostics n = row_count;
  return jsonb_build_object('timed_out', n);
end $fn$;
insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('ai_sweep', 'jobs.ai_sweep', '*/5 * * * *', 'cron', 'app.ai_calls_sweep', true)
on conflict (key) do nothing;
select cron.schedule('platform-ai-sweep', '*/5 * * * *', 'select app.run_job(''ai_sweep'')');

-- the drafts made for one subject, newest first, under the feature's right; a person's own subject's drafts to them only
create function public.ai_outputs_get(p_feature text, p_subject uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.ai_features;
begin
  select * into f from app.ai_features x where x.key = p_feature;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'feature'; end if;
  perform app.require(f.scope, f.action);
  if not app.ai_subject_ok(f.subject_type, p_subject) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'body', o.body, 'state', o.state, 'created_at', o.created_at,
                                                       'by', (select a.name from app.admins a where a.id = o.staff_id)) order by o.created_at desc)
                   from (select * from app.ai_outputs o where o.feature = p_feature and o.subject_id = p_subject order by o.created_at desc limit 5) o), '[]'::jsonb);
end $fn$;

-- a person accepts or discards a draft under the feature's right; another person's own subject's draft is not found
create function public.ai_output_set(p_id uuid, p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.ai_features; o app.ai_outputs;
begin
  select * into o from app.ai_outputs x where x.id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into f from app.ai_features x where x.key = o.feature;
  perform app.require(f.scope, f.action);
  if not app.ai_subject_ok(o.subject_type, o.subject_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_state not in ('used', 'discarded') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.ai_outputs x set state = p_state, decided_at = now() where x.id = p_id;
  return jsonb_build_object('ok', true);
end $fn$;

-- the intake hands the three to store_v3_secrets
CREATE OR REPLACE FUNCTION public.store_product_secrets(p_nonce text, p_secrets jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k text; v text; n int := 0; v_product text; v_purpose text; v_key jsonb;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now() returning product, purpose into v_product, v_purpose;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  -- an ad platform's credentials (0077)
  if v_purpose in ('google_ads', 'linkedin_ads', 'meta_ads') then
    return jsonb_build_object('ok', true, 'stored', app.store_ad_secrets(v_purpose, p_secrets));
  end if;
  -- the Claude key, Vercel's webhook secret and the products' CI secret (0078)
  if v_purpose in ('anthropic', 'vercel', 'ci') then
    return jsonb_build_object('ok', true, 'stored', app.store_v3_secrets(v_purpose, p_secrets));
  end if;
  -- the mail provider's key: that one name only, replaced when it exists (the owner rotates it this way)
  if v_purpose = 'brevo' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'brevo_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]+$' or char_length(btrim(v)) not between 32 and 300 then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'The Brevo API key (0060): read by mail-run only.');
      end if;
      n := n + 1;
    end loop;
    if n > 0 then
      update app.integration_connections set status = 'not_connected', config = config || jsonb_build_object('provider', 'brevo', 'key_stored_at', now())
      where provider = 'email';
      update app.mail_settings set last_error = null, last_check_at = null, updated_at = now() where id;
    end if;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google service account's JSON key (0064): that one name only; only its address is kept outside Vault
  if v_purpose = 'search_console' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      begin
        v_key := v::jsonb;
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end;
      if k <> 'search_console_key' or char_length(v) > 6000 or jsonb_typeof(v_key) <> 'object' or v_key ->> 'type' is distinct from 'service_account'
         or coalesce(v_key ->> 'client_email', '') !~ '^[a-z0-9._-]{1,100}@[a-z0-9.-]{1,100}\.iam\.gserviceaccount\.com$'
         or coalesce(v_key ->> 'private_key', '') !~ '^-----BEGIN PRIVATE KEY-----' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
      else
        perform vault.create_secret(v, k, 'A Google service account key for Search Console (0064): read by search-console-run only.');
      end if;
      update app.integration_connections set status = 'not_connected',
        config = config || jsonb_build_object('provider', 'google', 'client_email', v_key ->> 'client_email', 'key_stored_at', now(), 'last_error', null)
      where provider = 'search_console';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google API key for PageSpeed Insights (0073): that one name only; the integration is on once it is stored
  if v_purpose = 'pagespeed' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'pagespeed_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]{30,80}$' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'A Google API key for PageSpeed Insights (0073): read by pagespeed-run only.');
      end if;
      update app.integration_connections set status = 'connected', connected_at = now(),
        config = config || jsonb_build_object('key_stored_at', now(), 'last_error', null)
      where provider = 'pagespeed';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    if k !~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or char_length(coalesce(v, '')) < 32 or char_length(v) > 500 then
      raise exception 'store_product_secrets: % is not a product secret', k using errcode = 'invalid_parameter_value';
    end if;
    if v_product is not null then
      if k not in (v_product || '_token_secret', v_product || '_webhook_secret') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'exists';
      end if;
    end if;
    if exists (select 1 from vault.secrets s where s.name = k) then
      perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
    else
      perform vault.create_secret(v, k, 'A product''s shared secret (0002): read by the edge functions only.');
    end if;
    n := n + 1;
  end loop;
  if v_product is not null and exists (select 1 from vault.secrets s where s.name = v_product || '_token_secret')
     and exists (select 1 from vault.secrets s where s.name = v_product || '_webhook_secret') then
    update app.installations set enabled = true, updated_at = now() where product = v_product and not enabled;
  end if;
  return jsonb_build_object('ok', true, 'stored', n);
end $function$;

-- ===========================================================================
-- 6. rights on the functions
-- ===========================================================================
revoke all on function app.dev_product_ok(text) from public, anon, authenticated;
revoke all on function app.require_any(text, text) from public, anon, authenticated;
revoke all on function app.feature_request_json(uuid) from public, anon, authenticated;
revoke all on function app.release_note_json(app.release_notes) from public, anon, authenticated;
revoke all on function app.ai_subject_ok(text, uuid) from public, anon, authenticated;
revoke all on function app.ai_calls_sweep() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.feature_requests_list(text, text)', 'public.feature_request_add(text, text, text, uuid)',
                           'public.feature_request_set(uuid, jsonb)', 'public.feature_request_vote(uuid, uuid, boolean)',
                           'public.feature_request_link(uuid, text, uuid, boolean)', 'public.release_notes_list(text, text)',
                           'public.release_note_save(uuid, text, text, text, text, uuid, text)', 'public.release_note_publish(uuid, boolean)',
                           'public.release_note_delete(uuid)', 'public.v3_intake(text)', 'public.v3_disconnect(text)', 'public.ai_status()',
                           'public.ai_settings_set(text, text)', 'public.ai_prepare(text, uuid)', 'public.ai_outputs_get(text, uuid)',
                           'public.ai_output_set(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  revoke all on function public.worker_ai_record(text, uuid, uuid, text, text, int, int, int, text, text, bigint) from public, anon, authenticated;
  grant execute on function public.worker_ai_record(text, uuid, uuid, text, text, int, int, int, text, text, bigint) to service_role;
end $$;
revoke all on function public.store_product_secrets(text, jsonb) from public, anon, authenticated;
grant execute on function public.store_product_secrets(text, jsonb) to service_role;
