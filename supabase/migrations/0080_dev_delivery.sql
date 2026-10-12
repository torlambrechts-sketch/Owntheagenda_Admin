-- 0080_dev_delivery.sql — Development, the delivery half (docs/crm-enrichment/v3/PLAN.md, wave 1, builder dev-delivery)
--
-- Releases, Release gate, Integrations register, Code and environments, Delivery metrics, Vercel and Supabase.
--
-- 1. Deploys come from Vercel, pushed (X-V3-1). Vercel's deployment webhooks reach the edge function dev-events, which
--    checks the HMAC (vercel_signing_secret, 0078) before it parses the body, refuses an event older than five minutes and
--    hands worker_dev_vercel ids, shas, states, a branch name, a PR number and a commit's first line (200 characters).
--    The event id makes a repeat a duplicate. Sentral holds no Vercel token: «Roll back» stays in Vercel.
-- 2. Build facts come from the products' CI, pushed: a signed POST to dev-events (ci_signing_secret, 0078) with the commit,
--    suite names and pass and fail counts, dependency findings by severity, migration file names waiting for production and
--    a coverage figure. Never test output, never a log. Sentral holds no Supabase Management token for a product.
--    There is one CI secret (X-V3-1: the setup is per account), so each repository is bound to its product by the owner
--    (dev_ci_repos): a post from a repository nobody bound, or one naming another product than its binding, is refused.
-- 3. A release is a named record per product (PLAN default: continuous deploys stay; no deploy button, no rollout). Its
--    checklist is computed from the CI run and the production deployment of its commit, its changelog is release_notes
--    (0078), and the manual items are signed by a named person (the anonymity check by the owner, D-DEV-08). Recording it
--    freezes the checklist and publishes its notes; from then on those notes cannot be edited, unpublished or deleted
--    (0078's release_note_* are re-defined here with that check, and two triggers hold it for any other writer).
-- 4. The integrations register: Sentral's own integrations, their failure rates from the logs they already write
--    (growth_sync_log, job_runs, integration_calls, ai_calls), token expiry where a connection records one, an owner and the
--    upcoming change typed by a person, and «Plan upgrade» as a record with an owner and a due date.
-- 5. Delivery metrics from the deployments (and commit times from CI when it sends them).
-- Every table: app schema, RLS on, no policy, no grant. Every reader and writer: SECURITY DEFINER with search_path ''.
-- Workers: service role only.

-- ===========================================================================
-- 1. tables
-- ===========================================================================
-- the Vercel projects that have sent a deployment; the application each one is, set by a person
create table app.dev_projects (
  id            text primary key check (id ~ '^prj_[A-Za-z0-9]{6,64}$'),
  name          text not null check (name ~ '^[A-Za-z0-9._-]{1,100}$'),
  product       text check (product is null or product ~ '^[a-z][a-z0-9_]{1,30}$'),
  first_seen_at timestamptz not null default now(),
  last_event_at timestamptz not null default now(),
  updated_by    uuid references app.admins (id) on delete set null
);

-- a deployment as Vercel reported it: ids, a commit, a branch, states and times
create table app.dev_deployments (
  id             text primary key check (id ~ '^dpl_[A-Za-z0-9]{6,64}$'),
  project_id     text not null references app.dev_projects (id) on delete cascade,
  environment    text not null check (environment ~ '^[a-z][a-z0-9-]{0,39}$'),
  state          text not null default 'building' check (state in ('building', 'ready', 'error', 'canceled')),
  sha            text check (sha is null or sha ~ '^[0-9a-f]{7,40}$'),
  ref            text check (ref is null or (char_length(ref) between 1 and 200 and ref !~ '[[:cntrl:]]')),
  pr             int check (pr is null or pr between 1 and 99999999),
  commit_title   text check (commit_title is null or (char_length(commit_title) between 1 and 200 and commit_title !~ '[[:cntrl:]]')),
  host           text check (host is null or host ~ '^[a-z0-9.-]{3,253}$'),
  inspector_url  text check (inspector_url is null or inspector_url ~ '^https://vercel\.com/[A-Za-z0-9._~/-]{1,250}$'),
  created_at     timestamptz,
  seen_at        timestamptz not null default clock_timestamp(),
  ready_at       timestamptz,
  failed_at      timestamptz,
  promoted_at    timestamptz,
  rolled_back_at timestamptz,
  -- «promote»: first heard of when Vercel promoted it (an older deployment brought back), so not a deploy of its own
  origin         text not null default 'build' check (origin in ('build', 'promote')),
  updated_at     timestamptz not null default now()
);
create index dev_deployments_project on app.dev_deployments (project_id, environment, seen_at desc);
create index dev_deployments_sha on app.dev_deployments (sha) where sha is not null;

-- one CI run of a product: the commit, the suites' counts, the dependency findings, the migrations not yet in production
create table app.dev_ci_runs (
  id                 uuid primary key default gen_random_uuid(),
  delivery_id        text not null unique check (delivery_id ~ '^[A-Za-z0-9._:-]{6,120}$'),
  product            text not null check (product ~ '^[a-z][a-z0-9_]{1,30}$'),
  sha                text not null check (sha ~ '^[0-9a-f]{7,40}$'),
  ref                text check (ref is null or (char_length(ref) between 1 and 200 and ref !~ '[[:cntrl:]]')),
  pr                 int check (pr is null or pr between 1 and 99999999),
  commit_at          timestamptz,
  commit_title       text check (commit_title is null or (char_length(commit_title) between 1 and 200 and commit_title !~ '[[:cntrl:]]')),
  run_url            text check (run_url is null or run_url ~ '^https://[A-Za-z0-9.-]{3,100}/[A-Za-z0-9._~/-]{1,250}$'),
  repository         text check (repository is null or repository ~ '^[a-z0-9][a-z0-9_-]{0,38}/(?!\.\.?$)[a-z0-9_.-]{1,100}$'),
  finished_at        timestamptz not null,
  received_at        timestamptz not null default now(),
  suites             jsonb not null default '[]'::jsonb check (jsonb_typeof(suites) = 'array'),
  migrations_pending text[] not null default '{}',
  deps               jsonb check (deps is null or jsonb_typeof(deps) = 'object'),
  coverage           numeric(5, 2) check (coverage is null or coverage between 0 and 100)
);
create index dev_ci_runs_product on app.dev_ci_runs (product, finished_at desc);
create index dev_ci_runs_sha on app.dev_ci_runs (sha);

-- the repositories whose CI may post, each bound by the owner to the one product its posts are about (one CI secret for
-- every repository, X-V3-1, so the binding is what keeps one product's CI from posting another product's gate facts)
create table app.dev_ci_repos (
  repository text primary key check (repository ~ '^[a-z0-9][a-z0-9_-]{0,38}/(?!\.\.?$)[a-z0-9_.-]{1,100}$'),
  product    text not null check (product ~ '^[a-z][a-z0-9_]{1,30}$'),
  bound_by   uuid references app.admins (id) on delete set null,
  bound_at   timestamptz not null default now()
);

-- inbound deliveries: the duplicate key, the kind and what came of it; never a payload
create table app.dev_deliveries (
  source      text not null check (source in ('vercel', 'ci')),
  delivery_id text not null check (delivery_id ~ '^[A-Za-z0-9._:-]{6,120}$'),
  kind        text not null check (kind ~ '^[a-z][a-z_.-]{1,59}$'),
  outcome     text not null check (outcome in ('applied', 'ignored')),
  received_at timestamptz not null default now(),
  primary key (source, delivery_id)
);
create index dev_deliveries_at on app.dev_deliveries (received_at desc);

-- a named release of a product: a record, not a deploy
create table app.dev_releases (
  id          uuid primary key default gen_random_uuid(),
  product     text not null check (product ~ '^[a-z][a-z0-9_]{1,30}$'),
  name        text not null check (char_length(btrim(name)) between 1 and 80 and name !~ '[[:cntrl:]]'),
  planned_on  date,
  sha         text check (sha is null or sha ~ '^[0-9a-f]{7,40}$'),
  state       text not null default 'open' check (state in ('open', 'recorded')),
  checks      jsonb check (checks is null or jsonb_typeof(checks) = 'array'),
  recorded_at timestamptz,
  recorded_by uuid references app.admins (id) on delete set null,
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  version     int not null default 1,
  check ((state = 'recorded') = (recorded_at is not null)),
  check ((state = 'recorded') = (checks is not null)),
  unique (product, name)
);

-- the changelog of a release: release notes (0078), one release each
create table app.dev_release_notes (
  release_id uuid not null references app.dev_releases (id) on delete cascade,
  note_id    uuid not null unique references app.release_notes (id) on delete cascade,
  ord        int not null default 0,
  added_by   uuid references app.admins (id) on delete set null,
  added_at   timestamptz not null default now(),
  primary key (release_id, note_id)
);

-- a manual checklist item signed by a named person
create table app.dev_release_signoffs (
  release_id uuid not null references app.dev_releases (id) on delete cascade,
  item       text not null check (item in ('flag', 'anonymity', 'preview', 'rollback', 'help')),
  signed_by  uuid references app.admins (id) on delete set null,
  signed_at  timestamptz not null default now(),
  note       text check (note is null or (char_length(btrim(note)) between 1 and 500)),
  primary key (release_id, item),
  check (item <> 'rollback' or note is not null)
);

-- the integrations register: Sentral's own, with where each one's runs are logged
create table app.dev_integrations (
  key           text primary key check (key ~ '^[a-z_]{2,40}$'),
  ord           int not null,
  direction     text not null default 'out' check (direction in ('out', 'in')),
  provider      text,
  job_keys      text[] not null default '{}',
  sync_sources  text[] not null default '{}',
  call_product  text,
  ai_provider   text,
  owner_id      uuid references app.admins (id) on delete set null,
  change_text   text check (change_text is null or (char_length(btrim(change_text)) between 1 and 200 and change_text !~ '[[:cntrl:]]')),
  change_due_on date,
  change_url    text check (change_url is null or change_url ~ '^https://[^[:space:]]{3,250}$'),
  change_none   boolean not null default false,
  change_by     uuid references app.admins (id) on delete set null,
  change_at     timestamptz,
  updated_at    timestamptz not null default now(),
  check (not (change_none and change_text is not null)),
  check (change_text is not null or (change_due_on is null and change_url is null))
);

-- «Plan upgrade»: a planned piece of work for an integration's upcoming change, with an owner and a due date
create table app.dev_integration_plans (
  id           uuid primary key default gen_random_uuid(),
  integration  text not null references app.dev_integrations (key) on delete cascade,
  change_text  text not null check (char_length(change_text) between 1 and 200),
  owner_id     uuid references app.admins (id) on delete set null,
  due_on       date,
  planned_by   uuid references app.admins (id) on delete set null,
  planned_at   timestamptz not null default now(),
  closed_at    timestamptz,
  closed_by    uuid references app.admins (id) on delete set null,
  closed_as    text check (closed_as is null or closed_as in ('done', 'superseded')),
  check ((closed_at is null) = (closed_as is null))
);
create unique index dev_integration_plans_open on app.dev_integration_plans (integration) where closed_at is null;

alter table app.dev_projects enable row level security;
alter table app.dev_deployments enable row level security;
alter table app.dev_ci_runs enable row level security;
alter table app.dev_ci_repos enable row level security;
alter table app.dev_deliveries enable row level security;
alter table app.dev_releases enable row level security;
alter table app.dev_release_notes enable row level security;
alter table app.dev_release_signoffs enable row level security;
alter table app.dev_integrations enable row level security;
alter table app.dev_integration_plans enable row level security;
revoke all on app.dev_projects, app.dev_deployments, app.dev_ci_runs, app.dev_ci_repos, app.dev_deliveries, app.dev_releases, app.dev_release_notes,
              app.dev_release_signoffs, app.dev_integrations, app.dev_integration_plans from public, anon, authenticated;

-- Sentral's own integrations (PLAN: the register lists what Sentral itself calls; product-side ones wait for an event)
insert into app.dev_integrations (key, ord, direction, provider, job_keys, sync_sources, call_product, ai_provider) values
  ('search_console', 10, 'out', 'search_console', '{}', '{search_console,url_inspection}', null, null),
  ('pagespeed', 20, 'out', 'pagespeed', '{}', '{pagespeed}', null, null),
  ('google_ads', 30, 'out', 'google_ads', '{}', '{google_ads}', null, null),
  ('linkedin_ads', 40, 'out', 'linkedin_ads', '{}', '{linkedin_ads}', null, null),
  ('meta_ads', 50, 'out', 'meta_ads', '{}', '{meta_ads}', null, null),
  ('email', 60, 'out', 'email', '{mail_send}', '{email}', null, null),
  ('ai', 70, 'out', 'ai', '{}', '{}', null, 'anthropic'),
  ('orgpuls_api', 80, 'out', null, '{}', '{}', 'orgpuls', null),
  ('vercel', 90, 'in', 'vercel', '{}', '{}', null, null),
  ('ci', 100, 'in', 'ci', '{}', '{}', null, null)
on conflict (key) do nothing;

-- ===========================================================================
-- 2. helpers
-- ===========================================================================
-- a line of text from outside: control characters out, trimmed, capped; empty is null
create function app.delivery_line(p text, p_max int) returns text
  language sql immutable set search_path = ''
as $fn$
  select nullif(left(btrim(regexp_replace(split_part(coalesce(p, ''), E'\n', 1), '[[:cntrl:]]+', ' ', 'g')), p_max), '')
$fn$;

-- the staff member's name, or null
create function app.delivery_staff_name(p uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(a.name, a.email) from app.admins a where a.id = p
$fn$;

-- the newest CI run of a product on its main line (a branch run, main or master first)
create function app.delivery_ci_main(p_product text) returns app.dev_ci_runs
  language sql stable security definer set search_path = ''
as $fn$
  select r.* from app.dev_ci_runs r where r.product = p_product and r.pr is null
  order by (r.ref in ('main', 'master')) desc nulls last, r.finished_at desc limit 1
$fn$;

-- a CI run as the views show it
create function app.delivery_ci_json(r app.dev_ci_runs) returns jsonb
  language sql stable set search_path = ''
as $fn$
  select case when r.id is null then null else jsonb_build_object(
    'product', r.product, 'sha', r.sha, 'ref', r.ref, 'pr', r.pr, 'commit_at', r.commit_at, 'commit_title', r.commit_title,
    'run_url', r.run_url, 'repository', r.repository, 'finished_at', r.finished_at, 'suites', r.suites, 'migrations_pending', to_jsonb(r.migrations_pending),
    'deps', r.deps, 'coverage', r.coverage) end
$fn$;

create function app.delivery_deployment_json(d app.dev_deployments) returns jsonb
  language sql stable set search_path = ''
as $fn$
  select jsonb_build_object('id', d.id, 'project_id', d.project_id, 'environment', d.environment, 'state', d.state, 'sha', d.sha,
    'ref', d.ref, 'pr', d.pr, 'commit_title', d.commit_title, 'host', d.host, 'inspector_url', d.inspector_url,
    'created_at', d.created_at, 'seen_at', d.seen_at, 'ready_at', d.ready_at, 'failed_at', d.failed_at,
    'promoted_at', d.promoted_at, 'rolled_back_at', d.rolled_back_at)
$fn$;

-- the counts of a run's suites of the given kinds: {passed, failed, n}; null when it has none
create function app.delivery_suite_sum(p_suites jsonb, p_kinds text[]) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  select case when count(*) = 0 then null else jsonb_build_object(
    'n', count(*), 'passed', coalesce(sum((s ->> 'passed')::int), 0), 'failed', coalesce(sum((s ->> 'failed')::int), 0)) end
  from jsonb_array_elements(coalesce(p_suites, '[]'::jsonb)) s where s ->> 'kind' = any (p_kinds)
$fn$;

-- the connection of Vercel's webhook or the CI: the secret stored, the last delivery, deliveries in 30 days
create function app.delivery_connection_json(p_source text) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'key_stored', exists (select 1 from vault.secrets s where s.name = case p_source when 'vercel' then 'vercel_signing_secret' else 'ci_signing_secret' end),
    'status', (select c.status from app.integration_connections c where c.provider = p_source),
    'key_stored_at', (select c.config ->> 'key_stored_at' from app.integration_connections c where c.provider = p_source),
    'last_delivery_at', (select max(d.received_at) from app.dev_deliveries d where d.source = p_source),
    'applied_30d', (select count(*) from app.dev_deliveries d where d.source = p_source and d.outcome = 'applied' and d.received_at > now() - interval '30 days'),
    'ignored_30d', (select count(*) from app.dev_deliveries d where d.source = p_source and d.outcome = 'ignored' and d.received_at > now() - interval '30 days'))
$fn$;

-- the applications Development knows, with Sentral itself
create function app.delivery_products_json() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name, 'color', p.color) order by p.ord, p.key), '[]'::jsonb)
         || jsonb_build_array(jsonb_build_object('key', 'sentral', 'name', null, 'color', null))
  from app.products p
$fn$;

-- ===========================================================================
-- 3. the workers: dev-events hands over what it verified (service role only)
-- ===========================================================================
-- one Vercel deployment event. The edge function checked the signature and the five minutes; this checks them again
-- where it can (the time), refuses a repeat by the event id and keeps only ids, a commit, a branch, states and times.
create function public.worker_dev_vercel(p_delivery text, p_kind text, p_at timestamptz, p_d jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_id text := p_d ->> 'id'; v_proj text := p_d ->> 'project_id'; v_name text := p_d ->> 'project_name';
  v_env text := coalesce(nullif(p_d ->> 'environment', ''), 'preview');
  v_sha text := lower(p_d ->> 'sha'); v_pr text := p_d ->> 'pr'; v_host text := lower(p_d ->> 'host'); v_insp text := p_d ->> 'inspector_url';
  v_new boolean; v_seen timestamptz; v_live text;
begin
  if p_delivery is null or p_delivery !~ '^[A-Za-z0-9._:-]{6,120}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'delivery'; end if;
  if p_kind is null or p_kind !~ '^[a-z][a-z_.-]{1,59}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if p_at is null or p_at < now() - interval '5 minutes' or p_at > now() + interval '5 minutes' then
    raise exception 'stale' using errcode = 'invalid_parameter_value', detail = 'at';
  end if;
  if jsonb_typeof(p_d) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'deployment'; end if;
  if v_id is null or v_id !~ '^dpl_[A-Za-z0-9]{6,64}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'id'; end if;
  if v_proj is null or v_proj !~ '^prj_[A-Za-z0-9]{6,64}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'project_id'; end if;
  if v_name is null or v_name !~ '^[A-Za-z0-9._-]{1,100}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'project_name'; end if;

  insert into app.dev_deliveries (source, delivery_id, kind, outcome) values ('vercel', p_delivery, p_kind, 'applied') on conflict do nothing;
  if not found then return jsonb_build_object('duplicate', true); end if;
  delete from app.dev_deliveries d where d.received_at < now() - interval '30 days';
  if p_kind not in ('deployment.created', 'deployment.succeeded', 'deployment.ready', 'deployment.error', 'deployment.canceled', 'deployment.promoted') then
    update app.dev_deliveries set outcome = 'ignored' where source = 'vercel' and delivery_id = p_delivery;
    return jsonb_build_object('ignored', true);
  end if;

  if v_env !~ '^[a-z][a-z0-9-]{0,39}$' then v_env := 'preview'; end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{7,40}$' then v_sha := null; end if;
  if v_pr is not null and v_pr !~ '^[1-9][0-9]{0,7}$' then v_pr := null; end if;
  if v_host is not null and v_host !~ '^[a-z0-9.-]{3,253}$' then v_host := null; end if;
  if v_insp is not null and v_insp !~ '^https://vercel\.com/[A-Za-z0-9._~/-]{1,250}$' then v_insp := null; end if;

  insert into app.dev_projects (id, name) values (v_proj, v_name)
  on conflict (id) do update set name = excluded.name, last_event_at = now();

  v_new := not exists (select 1 from app.dev_deployments d where d.id = v_id);
  insert into app.dev_deployments (id, project_id, environment, sha, ref, pr, commit_title, host, inspector_url, created_at, origin)
  values (v_id, v_proj, v_env, v_sha, app.delivery_line(p_d ->> 'ref', 200), v_pr::int, app.delivery_line(p_d ->> 'commit_title', 200), v_host, v_insp,
          case when p_kind = 'deployment.created' then p_at end, case when p_kind = 'deployment.promoted' then 'promote' else 'build' end)
  on conflict (id) do update set
    environment = case when app.dev_deployments.environment = 'production' then 'production' else excluded.environment end,
    sha = coalesce(excluded.sha, app.dev_deployments.sha), ref = coalesce(excluded.ref, app.dev_deployments.ref),
    pr = coalesce(excluded.pr, app.dev_deployments.pr), commit_title = coalesce(excluded.commit_title, app.dev_deployments.commit_title),
    host = coalesce(excluded.host, app.dev_deployments.host), inspector_url = coalesce(excluded.inspector_url, app.dev_deployments.inspector_url),
    created_at = coalesce(app.dev_deployments.created_at, excluded.created_at), updated_at = now();

  if p_kind in ('deployment.succeeded', 'deployment.ready') then
    update app.dev_deployments set state = 'ready', ready_at = coalesce(ready_at, p_at), updated_at = now() where id = v_id;
  elsif p_kind = 'deployment.error' then
    update app.dev_deployments set state = 'error', failed_at = coalesce(failed_at, p_at), updated_at = now() where id = v_id;
  elsif p_kind = 'deployment.canceled' then
    update app.dev_deployments set state = 'canceled', failed_at = coalesce(failed_at, p_at), updated_at = now() where id = v_id;
  elsif p_kind = 'deployment.promoted' then
    -- the deployment production now serves. When an older one is promoted (Vercel's instant rollback), the one that was
    -- live is rolled back: the newest ready production deployment seen after it, or any live one when this is older than
    -- everything Sentral has heard of.
    select d.seen_at into v_seen from app.dev_deployments d where d.id = v_id;
    select d.id into v_live from app.dev_deployments d
    where d.project_id = v_proj and d.id <> v_id and d.environment = 'production' and d.state = 'ready' and d.rolled_back_at is null
      and (v_new or d.seen_at > v_seen)
    order by coalesce(d.ready_at, d.seen_at) desc limit 1;
    if v_live is not null then
      update app.dev_deployments set rolled_back_at = p_at, updated_at = now() where id = v_live;
    end if;
    update app.dev_deployments set environment = 'production', state = 'ready', ready_at = coalesce(ready_at, p_at), promoted_at = p_at, updated_at = now()
    where id = v_id;
  end if;

  update app.integration_connections set status = 'connected', connected_at = coalesce(connected_at, now()),
    config = config || jsonb_build_object('last_delivery_at', now())
  where provider = 'vercel';
  return jsonb_build_object('applied', true, 'rolled_back', v_live);
end $fn$;

-- one CI run: every field checked again by shape and size, unknown fields dropped. The repository it names must be bound
-- to the product it names (dev_ci_repos): one secret signs every repository's posts, so the binding decides what a
-- repository's CI may speak for.
create function public.worker_dev_ci(p_delivery text, p_at timestamptz, p_run jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_product text := p_run ->> 'product'; v_sha text := lower(p_run ->> 'sha'); v_pr text := p_run ->> 'pr';
  v_url text := p_run ->> 'run_url'; v_suites jsonb := '[]'::jsonb; v_pending text[] := '{}'; v_deps jsonb; v_cov numeric;
  v_finished timestamptz; v_commit timestamptz; s jsonb; f text; k text; v_repo text := lower(p_run ->> 'repository'); v_bound text;
begin
  if p_delivery is null or p_delivery !~ '^[A-Za-z0-9._:-]{6,120}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'delivery'; end if;
  if p_at is null or p_at < now() - interval '5 minutes' or p_at > now() + interval '5 minutes' then
    raise exception 'stale' using errcode = 'invalid_parameter_value', detail = 'at';
  end if;
  if jsonb_typeof(p_run) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'run'; end if;
  if (p_run ->> 'v') is distinct from '1' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'v'; end if;
  if v_product is null or v_product !~ '^[a-z][a-z0-9_]{1,30}$' or not app.dev_product_ok(v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  if v_repo is null or v_repo !~ '^[a-z0-9][a-z0-9_-]{0,38}/(?!\.\.?$)[a-z0-9_.-]{1,100}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'repository';
  end if;
  select b.product into v_bound from app.dev_ci_repos b where b.repository = v_repo;
  if v_bound is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'repository_unbound'; end if;
  if v_bound <> v_product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'repository_product'; end if;
  if v_sha is null or v_sha !~ '^[0-9a-f]{7,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sha'; end if;
  if v_pr is not null and v_pr !~ '^[1-9][0-9]{0,7}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pr'; end if;
  if v_url is not null and v_url !~ '^https://[A-Za-z0-9.-]{3,100}/[A-Za-z0-9._~/-]{1,250}$' then v_url := null; end if;
  begin
    v_finished := coalesce((p_run ->> 'finished_at')::timestamptz, now());
    v_commit := (p_run ->> 'commit_at')::timestamptz;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'time';
  end;
  if v_finished > now() + interval '5 minutes' then v_finished := now(); end if;
  if v_commit is not null and v_commit > v_finished + interval '5 minutes' then v_commit := null; end if;

  if p_run ? 'suites' then
    if jsonb_typeof(p_run -> 'suites') <> 'array' or jsonb_array_length(p_run -> 'suites') > 40 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'suites';
    end if;
    for s in select x from jsonb_array_elements(p_run -> 'suites') x loop
      if jsonb_typeof(s) <> 'object' or coalesce(s ->> 'name', '') !~ '^[A-Za-z0-9 ._:/()-]{1,60}$'
         or coalesce(s ->> 'kind', '') not in ('test', 'security', 'anonymity', 'lint', 'build', 'other')
         or coalesce(s ->> 'passed', '') !~ '^[0-9]{1,7}$' or coalesce(s ->> 'failed', '') !~ '^[0-9]{1,7}$'
         or coalesce(s ->> 'skipped', '0') !~ '^[0-9]{1,7}$' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'suites';
      end if;
      v_suites := v_suites || jsonb_build_array(jsonb_build_object('name', s ->> 'name', 'kind', s ->> 'kind', 'passed', (s ->> 'passed')::int,
                                                                   'failed', (s ->> 'failed')::int, 'skipped', coalesce((s ->> 'skipped')::int, 0)));
    end loop;
  end if;
  if p_run ? 'migrations_pending' then
    if jsonb_typeof(p_run -> 'migrations_pending') <> 'array' or jsonb_array_length(p_run -> 'migrations_pending') > 100 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'migrations_pending';
    end if;
    for f in select x from jsonb_array_elements_text(p_run -> 'migrations_pending') x loop
      if f !~ '^[0-9]{3,14}_[a-z0-9_]{1,80}\.sql$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'migrations_pending'; end if;
      v_pending := v_pending || f;
    end loop;
  end if;
  if jsonb_typeof(p_run -> 'dependencies') = 'object' then
    v_deps := '{}'::jsonb;
    foreach k in array array['critical', 'high', 'moderate', 'low'] loop
      if coalesce(p_run -> 'dependencies' ->> k, '0') !~ '^[0-9]{1,6}$' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependencies';
      end if;
      v_deps := v_deps || jsonb_build_object(k, coalesce((p_run -> 'dependencies' ->> k)::int, 0));
    end loop;
  end if;
  if p_run ? 'coverage' and jsonb_typeof(p_run -> 'coverage') = 'number' then
    v_cov := (p_run ->> 'coverage')::numeric;
    if v_cov < 0 or v_cov > 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coverage'; end if;
  end if;

  insert into app.dev_deliveries (source, delivery_id, kind, outcome) values ('ci', p_delivery, 'ci.run', 'applied') on conflict do nothing;
  if not found then return jsonb_build_object('duplicate', true); end if;
  delete from app.dev_deliveries d where d.received_at < now() - interval '30 days';
  delete from app.dev_ci_runs r where r.received_at < now() - interval '400 days';

  insert into app.dev_ci_runs (delivery_id, product, sha, ref, pr, commit_at, commit_title, run_url, repository, finished_at, suites, migrations_pending, deps, coverage)
  values (p_delivery, v_product, v_sha, app.delivery_line(p_run ->> 'ref', 200), v_pr::int, v_commit, app.delivery_line(p_run ->> 'commit_title', 200), v_url,
          v_repo, v_finished, v_suites, v_pending, v_deps, round(v_cov, 2));

  update app.integration_connections set status = 'connected', connected_at = coalesce(connected_at, now()),
    config = config || jsonb_build_object('last_delivery_at', now())
  where provider = 'ci';
  return jsonb_build_object('applied', true, 'suites', jsonb_array_length(v_suites), 'migrations_pending', cardinality(v_pending));
end $fn$;

-- ===========================================================================
-- 4. deploys: Code and environments, Vercel and Supabase
-- ===========================================================================
create function public.dev_deploys() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see');
begin
  return jsonb_build_object(
    'can_configure', app.can('dev', 'configure'),
    'can_manage', exists (select 1 from app.admins a where a.id = v_me and a.role = 'owner'),
    'vercel', app.delivery_connection_json('vercel'),
    'ci', app.delivery_connection_json('ci'),
    'products', app.delivery_products_json(),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'product', p.product, 'last_event_at', p.last_event_at,
                                                              'deployments', (select count(*) from app.dev_deployments d where d.project_id = p.id))
                                           order by p.name) from app.dev_projects p), '[]'::jsonb),
    -- the newest deployment per project and environment, and the newest live production deployment
    'latest', coalesce((select jsonb_agg(app.delivery_deployment_json(x) order by x.project_id, x.environment) from app.dev_deployments x
        where x.id in (select distinct on (d.project_id, d.environment) d.id from app.dev_deployments d
                       order by d.project_id, d.environment, d.seen_at desc)), '[]'::jsonb),
    'live', coalesce((select jsonb_agg(app.delivery_deployment_json(x) order by x.project_id) from app.dev_deployments x
        where x.id in (select distinct on (d.project_id) d.id from app.dev_deployments d
                       where d.environment = 'production' and d.state = 'ready' and d.rolled_back_at is null
                       order by d.project_id, coalesce(d.promoted_at, d.ready_at, d.seen_at) desc)), '[]'::jsonb),
    -- previews: the newest per project and branch in 14 days
    'previews', coalesce((select jsonb_agg(app.delivery_deployment_json(x) order by x.seen_at desc) from app.dev_deployments x
        where x.id in (select y.id from (
                         select distinct on (d.project_id, coalesce(d.ref, d.id)) d.id, d.seen_at from app.dev_deployments d
                         where d.environment = 'preview' and d.seen_at > now() - interval '14 days'
                         order by d.project_id, coalesce(d.ref, d.id), d.seen_at desc) y
                       order by y.seen_at desc limit 30)), '[]'::jsonb),
    -- the repositories bound to a product, with their newest post
    'ci_repos', coalesce((select jsonb_agg(jsonb_build_object('repository', b.repository, 'product', b.product, 'bound_by', app.delivery_staff_name(b.bound_by),
                                                              'bound_at', b.bound_at, 'last_run_at', (select max(r.finished_at) from app.dev_ci_runs r where r.repository = b.repository))
                                           order by b.repository) from app.dev_ci_repos b), '[]'::jsonb),
    -- the newest CI run per product on its main line
    'ci_runs', coalesce((select jsonb_agg(app.delivery_ci_json(app.delivery_ci_main(p.product)) order by p.product)
                         from (select distinct r.product from app.dev_ci_runs r where r.pr is null) p), '[]'::jsonb));
end $fn$;

-- a Vercel project is one of the applications (or Sentral), or none
create function public.dev_project_set(p_id text, p_product text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'configure');
begin
  if p_product is not null and not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  update app.dev_projects set product = p_product, updated_by = v_me where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('dev_project.changed', 'dev_project', p_id, jsonb_build_object('product', p_product));
  return jsonb_build_object('ok', true);
end $fn$;

-- the owner binds a repository (GitHub's owner/name) to the product its CI posts are about, or unbinds it (product null);
-- a fresh second factor, as for the CI secret itself (0078 v3_intake)
create function public.dev_ci_repo_set(p_repository text, p_product text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v_repo text := lower(btrim(coalesce(p_repository, '')));
begin
  perform app.require_fresh_mfa(10);
  if v_repo !~ '^[a-z0-9][a-z0-9_-]{0,38}/(?!\.\.?$)[a-z0-9_.-]{1,100}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'repository'; end if;
  if p_product is null then
    delete from app.dev_ci_repos b where b.repository = v_repo;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('dev_ci_repo.unbound', 'dev_ci_repo', v_repo);
    return jsonb_build_object('ok', true);
  end if;
  if not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  insert into app.dev_ci_repos (repository, product, bound_by) values (v_repo, p_product, v_me)
  on conflict (repository) do update set product = excluded.product, bound_by = excluded.bound_by, bound_at = now();
  perform app.log('dev_ci_repo.bound', 'dev_ci_repo', v_repo, jsonb_build_object('product', p_product));
  return jsonb_build_object('ok', true);
end $fn$;

-- ===========================================================================
-- 5. delivery metrics
-- ===========================================================================
-- Deploy frequency: production deployments that became ready, per day of the window Sentral has heard Vercel in: history
-- starts at connection (X-V3-1), so the days are counted from the first Vercel project's first event when that is later
-- than the window's start ('covered_days', 'since', 'complete'). Change failure rate: production deployments that
-- failed or were rolled back ÷ production deployments that finished. Time to restore (90 days): a rollback, from the moment
-- the deployment went live to the rollback; a failed production build, from the failure to the project's next ready
-- production deployment. Lead time: from the commit (CI's commit time) to the first ready production deployment of it.
create function public.dev_metrics(p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); v_from timestamptz; v_ready int; v_final int; v_failed int; v_rolled int;
        v_since timestamptz; v_covered int;
begin
  if p_days is null or p_days not between 7 and 365 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'days'; end if;
  v_from := now() - make_interval(days => p_days);
  select min(p.first_seen_at) into v_since from app.dev_projects p;
  -- whole days heard, at least one, at most the window
  v_covered := case when v_since is null then 0 else least(p_days, greatest(1, ceil(extract(epoch from now() - v_since) / 86400.0)::int)) end;
  select count(*) filter (where d.state = 'ready' and d.ready_at >= v_from),
         count(*) filter (where d.state in ('ready', 'error') and coalesce(d.created_at, d.seen_at) >= v_from),
         count(*) filter (where d.state = 'error' and coalesce(d.created_at, d.seen_at) >= v_from),
         count(*) filter (where d.state = 'ready' and d.rolled_back_at is not null and coalesce(d.created_at, d.seen_at) >= v_from)
    into v_ready, v_final, v_failed, v_rolled
  from app.dev_deployments d where d.environment = 'production' and d.origin = 'build';
  return jsonb_build_object(
    'days', p_days,
    'since', v_since,
    'covered_days', v_covered,
    'complete', v_since is not null and v_since <= v_from,
    'sources', jsonb_build_object('deploys', exists (select 1 from app.dev_deployments), 'ci', exists (select 1 from app.dev_ci_runs)),
    'deploys', jsonb_build_object('ready', v_ready, 'per_day', case when v_covered > 0 then round(v_ready::numeric / v_covered, 2) end,
                                  'finished', v_final, 'failed', v_failed, 'rolled_back', v_rolled,
                                  'failure_rate', case when v_final > 0 then round(100.0 * (v_failed + v_rolled) / v_final, 1) end),
    'lead', (select jsonb_build_object('n', count(*), 'median_hours', round((percentile_cont(0.5) within group (order by h))::numeric, 2))
             from (select extract(epoch from (f.first_ready - f.commit_at)) / 3600.0 h from (
                     select d.sha, min(d.ready_at) first_ready, (select min(r.commit_at) from app.dev_ci_runs r where r.sha = d.sha) commit_at
                     from app.dev_deployments d
                     where d.environment = 'production' and d.state = 'ready' and d.origin = 'build' and d.sha is not null
                     group by d.sha) f
                   where f.first_ready >= v_from and f.commit_at is not null and f.first_ready >= f.commit_at) x),
    'restore', (select jsonb_build_object('n', count(*), 'days', 90, 'median_minutes', round((percentile_cont(0.5) within group (order by m))::numeric, 1))
                from (
                  select extract(epoch from (d.rolled_back_at - coalesce(d.ready_at, d.seen_at))) / 60.0 m
                  from app.dev_deployments d
                  where d.environment = 'production' and d.rolled_back_at is not null and d.rolled_back_at >= now() - interval '90 days'
                  union all
                  select extract(epoch from (n.ready_at - d.failed_at)) / 60.0
                  from app.dev_deployments d
                  cross join lateral (select min(x.ready_at) ready_at from app.dev_deployments x
                                      where x.project_id = d.project_id and x.environment = 'production' and x.state = 'ready' and x.ready_at > d.failed_at) n
                  where d.environment = 'production' and d.state = 'error' and d.failed_at >= now() - interval '90 days' and n.ready_at is not null) y
                where m >= 0),
    'coverage', coalesce((select jsonb_agg(jsonb_build_object('product', c.product, 'coverage', c.coverage, 'at', c.finished_at) order by c.product)
                          from (select (app.delivery_ci_main(p.product)).* from (select distinct r.product from app.dev_ci_runs r where r.pr is null) p) c
                          where c.coverage is not null), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 6. releases and the gate
-- ===========================================================================
-- the commit a release is about: its own, else the product's live production deployment, else its newest CI run on main
create function app.delivery_release_commit(r app.dev_releases) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v text;
begin
  if r.sha is not null then return jsonb_build_object('sha', r.sha, 'source', 'release'); end if;
  select d.sha into v from app.dev_deployments d join app.dev_projects p on p.id = d.project_id
  where p.product = r.product and d.environment = 'production' and d.state = 'ready' and d.rolled_back_at is null and d.sha is not null
  order by coalesce(d.promoted_at, d.ready_at, d.seen_at) desc limit 1;
  if v is not null then return jsonb_build_object('sha', v, 'source', 'deploy'); end if;
  v := (app.delivery_ci_main(r.product)).sha;
  if v is not null then return jsonb_build_object('sha', v, 'source', 'ci'); end if;
  return null;
end $fn$;

-- the checklist, computed from the same rows for Releases and the Release gate: each item pass, fail or unknown (no source)
create function app.delivery_release_checks(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  r app.dev_releases; v_commit jsonb; v_sha text; ci app.dev_ci_runs; v_dep app.dev_deployments;
  v_tests jsonb; v_rls jsonb; v_anon jsonb; v_notes int; v_prev timestamptz; v_help int; v_items jsonb := '[]'::jsonb;
  v_state text; k text;
begin
  select * into r from app.dev_releases x where x.id = p_id;
  if not found then return null; end if;
  if r.state = 'recorded' then return r.checks; end if;
  v_commit := app.delivery_release_commit(r);
  v_sha := v_commit ->> 'sha';
  if v_sha is not null then
    select x.* into ci from app.dev_ci_runs x where x.product = r.product and x.sha like v_sha || '%' order by x.finished_at desc limit 1;
    select d.* into v_dep from app.dev_deployments d join app.dev_projects p on p.id = d.project_id
    where p.product = r.product and d.environment = 'production' and d.sha like v_sha || '%'
    order by (d.state = 'ready') desc, d.seen_at desc limit 1;
  end if;

  -- tests: every suite of kind «test» in the commit's CI run passed (what the CI names a test suite; Sentral cannot tell
  -- unit from end-to-end, so the label says «CI test suites»)
  v_tests := app.delivery_suite_sum(ci.suites, array['test']);
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'tests', 'kind', 'auto', 'source', 'ci',
    'state', case when v_tests is null then 'unknown' when (v_tests ->> 'failed')::int = 0 then 'pass' else 'fail' end,
    -- a run without a test suite says so ({n: 0}), apart from no run at all (null)
    'detail', case when v_tests is null and ci.id is not null then jsonb_build_object('n', 0) else v_tests end));
  -- migrations: none of the product's migrations waits for production
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'migrations', 'kind', 'auto', 'source', 'ci',
    'state', case when ci.id is null then 'unknown' when cardinality(ci.migrations_pending) = 0 then 'pass' else 'fail' end,
    'detail', case when ci.id is null then null else jsonb_build_object('pending', to_jsonb(ci.migrations_pending)) end));
  -- row-level security and anonymity suites: a pass needs an anonymity suite in the run, and nothing failing; without one
  -- the item is unknown (detail.anonymity false), whatever the security suites say
  v_rls := app.delivery_suite_sum(ci.suites, array['security', 'anonymity']);
  v_anon := app.delivery_suite_sum(ci.suites, array['anonymity']);
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'rls', 'kind', 'auto', 'source', 'ci',
    'state', case when v_rls is null then 'unknown' when (v_rls ->> 'failed')::int > 0 then 'fail' when v_anon is null then 'unknown' else 'pass' end,
    'detail', case when v_rls is null then null else v_rls || jsonb_build_object('anonymity', v_anon is not null) end));
  -- dependency findings: no high or critical
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'deps', 'kind', 'auto', 'source', 'ci',
    'state', case when ci.deps is null then 'unknown' when (ci.deps ->> 'high')::int + (ci.deps ->> 'critical')::int = 0 then 'pass' else 'fail' end,
    'detail', ci.deps));
  -- the commit is live in production
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'deploy', 'kind', 'auto', 'source', 'vercel',
    'state', case when v_dep.id is null then 'unknown' when v_dep.state = 'ready' and v_dep.rolled_back_at is null then 'pass'
                  when v_dep.state = 'building' then 'unknown' else 'fail' end,
    'detail', case when v_dep.id is null then null else jsonb_build_object('state', v_dep.state, 'rolled_back', v_dep.rolled_back_at is not null,
                                                                          'at', coalesce(v_dep.ready_at, v_dep.failed_at, v_dep.seen_at)) end));
  -- the changelog has at least one line
  select count(*) into v_notes from app.dev_release_notes n where n.release_id = r.id;
  v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'notes', 'kind', 'auto', 'source', 'changelog',
    'state', case when v_notes > 0 then 'pass' else 'fail' end, 'detail', jsonb_build_object('n', v_notes)));
  -- the manual items, each signed by a named person; the product's own published help articles changed since its previous
  -- release, as evidence (sample articles only in the sandbox, as every other reader of them)
  select max(x.recorded_at) into v_prev from app.dev_releases x where x.product = r.product and x.state = 'recorded';
  select count(*) into v_help from app.help_articles a
  where a.product = r.product and a.status = 'published' and (app.dev_sandbox() or not a.is_sample) and a.updated_at > coalesce(v_prev, r.created_at);
  foreach k in array array['flag', 'anonymity', 'preview', 'rollback', 'help'] loop
    select case when s.release_id is null then 'fail' else 'pass' end into v_state
    from (select 1) one left join app.dev_release_signoffs s on s.release_id = r.id and s.item = k;
    v_items := v_items || jsonb_build_array(jsonb_build_object('key', k, 'kind', 'manual', 'source', null, 'state', v_state,
      'signed', (select jsonb_build_object('by', app.delivery_staff_name(s.signed_by), 'at', s.signed_at, 'note', s.note)
                 from app.dev_release_signoffs s where s.release_id = r.id and s.item = k),
      'detail', case k when 'anonymity' then v_anon when 'help' then jsonb_build_object('changed', v_help, 'since', coalesce(v_prev, r.created_at))
                       when 'preview' then (select jsonb_build_object('host', d.host, 'ref', d.ref, 'pr', d.pr, 'same_commit', coalesce(d.sha like v_sha || '%', false))
                                            from app.dev_deployments d join app.dev_projects p on p.id = d.project_id
                                            where p.product = r.product and d.environment = 'preview' and d.state = 'ready' and d.host is not null
                                            order by coalesce(d.sha like v_sha || '%', false) desc, d.seen_at desc limit 1) end));
  end loop;
  return v_items;
end $fn$;

create function app.delivery_release_json(r app.dev_releases) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', r.id, 'product', r.product, 'name', r.name, 'planned_on', r.planned_on, 'sha', r.sha, 'state', r.state,
    'recorded_at', r.recorded_at, 'recorded_by', app.delivery_staff_name(r.recorded_by), 'created_at', r.created_at, 'version', r.version,
    'notes', (select count(*) from app.dev_release_notes n where n.release_id = r.id),
    -- production deployments of the product rolled back between this release and the next one
    'rollbacks', case when r.state = 'recorded' then (
       select count(*) from app.dev_deployments d join app.dev_projects p on p.id = d.project_id
       where p.product = r.product and d.environment = 'production' and d.rolled_back_at >= r.recorded_at
         and d.rolled_back_at < coalesce((select min(x.recorded_at) from app.dev_releases x where x.product = r.product and x.state = 'recorded' and x.recorded_at > r.recorded_at), 'infinity'::timestamptz)) end,
    'watching', exists (select 1 from app.dev_projects p where p.product = r.product))
$fn$;

-- the releases (open first, then the recorded ones, newest first) and one of them in full
create function public.dev_releases_get(p_release uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); r app.dev_releases; v_checks jsonb; v_commit jsonb; ci app.dev_ci_runs;
begin
  if p_release is not null then select * into r from app.dev_releases x where x.id = p_release; end if;
  if r.id is null then
    select * into r from app.dev_releases x order by x.state = 'open' desc, x.planned_on nulls last, coalesce(x.recorded_at, x.created_at) desc limit 1;
  end if;
  if r.id is not null then
    v_checks := app.delivery_release_checks(r.id);
    v_commit := case when r.state = 'recorded' then jsonb_build_object('sha', r.sha, 'source', 'release') else app.delivery_release_commit(r) end;
    if v_commit ->> 'sha' is not null then
      select x.* into ci from app.dev_ci_runs x where x.product = r.product and x.sha like (v_commit ->> 'sha') || '%' order by x.finished_at desc limit 1;
    end if;
  end if;
  return jsonb_build_object(
    'can_add', app.can('dev', 'add'),
    -- the anonymity check is the owner's to sign (D-DEV-08)
    'can_sign_anonymity', app.can('dev', 'add') and exists (select 1 from app.admins a where a.id = v_me and a.role = 'owner'),
    'products', app.delivery_products_json(),
    'releases', coalesce((select jsonb_agg(app.delivery_release_json(x) order by x.state = 'open' desc, coalesce(x.recorded_at, x.created_at) desc)
                          from app.dev_releases x
                          where x.id in (select y.id from app.dev_releases y order by y.state = 'open' desc, coalesce(y.recorded_at, y.created_at) desc limit 30)), '[]'::jsonb),
    'current', case when r.id is null then null else app.delivery_release_json(r) || jsonb_build_object(
      'checks', v_checks,
      'commit', v_commit,
      'ci', case when ci.id is null then null else jsonb_build_object('finished_at', ci.finished_at, 'run_url', ci.run_url, 'ref', ci.ref) end,
      'changelog', coalesce((select jsonb_agg(app.release_note_json(n) || jsonb_build_object('ord', l.ord) order by l.ord, l.added_at)
                             from app.dev_release_notes l join app.release_notes n on n.id = l.note_id where l.release_id = r.id), '[]'::jsonb),
      'drafts', case when r.state = 'open' then coalesce((select jsonb_agg(app.release_note_json(n) order by n.updated_at desc)
                             from app.release_notes n where n.product = r.product and n.state = 'draft'
                               and not exists (select 1 from app.dev_release_notes l where l.note_id = n.id)), '[]'::jsonb) else '[]'::jsonb end) end);
end $fn$;

create function public.dev_release_add(p_product text, p_name text, p_planned_on date default null, p_sha text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v_id uuid;
begin
  if p_product is null or not app.dev_product_ok(p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 80 or p_name ~ '[[:cntrl:]]' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_sha is not null and lower(btrim(p_sha)) !~ '^[0-9a-f]{7,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sha'; end if;
  if exists (select 1 from app.dev_releases x where x.product = p_product and x.name = btrim(p_name)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name_taken';
  end if;
  insert into app.dev_releases (product, name, planned_on, sha, created_by)
  values (p_product, btrim(p_name), p_planned_on, nullif(lower(btrim(p_sha)), ''), v_me) returning id into v_id;
  perform app.log('dev_release.added', 'dev_release', v_id::text, jsonb_build_object('product', p_product));
  return jsonb_build_object('id', v_id);
end $fn$;

-- name, planned date and commit of an open release
create function public.dev_release_set(p_id uuid, p_patch jsonb, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); r app.dev_releases; k text; v_name text; v_sha text; v_date date;
begin
  select * into r from app.dev_releases x where x.id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  if r.version <> coalesce(p_version, -1) then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if jsonb_typeof(p_patch) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name', 'planned_on', 'sha') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  v_name := case when p_patch ? 'name' then btrim(coalesce(p_patch ->> 'name', '')) else r.name end;
  if char_length(v_name) not between 1 and 80 or v_name ~ '[[:cntrl:]]' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if v_name <> r.name and exists (select 1 from app.dev_releases x where x.product = r.product and x.name = v_name) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name_taken';
  end if;
  v_sha := case when p_patch ? 'sha' then nullif(lower(btrim(coalesce(p_patch ->> 'sha', ''))), '') else r.sha end;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{7,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sha'; end if;
  begin
    v_date := case when p_patch ? 'planned_on' then nullif(p_patch ->> 'planned_on', '')::date else r.planned_on end;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'planned_on';
  end;
  update app.dev_releases set name = v_name, sha = v_sha, planned_on = v_date, updated_at = now(), version = version + 1 where id = p_id;
  perform app.log('dev_release.changed', 'dev_release', p_id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(p_patch) x)));
  return jsonb_build_object('ok', true);
end $fn$;

-- an open release that will not happen; its notes stay drafts
create function public.dev_release_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add');
begin
  delete from app.dev_releases x where x.id = p_id and x.state = 'open';
  if not found then
    if exists (select 1 from app.dev_releases x where x.id = p_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  perform app.log('dev_release.deleted', 'dev_release', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- a draft release note of the same product joins or leaves an open release's changelog
create function public.dev_release_note_attach(p_release uuid, p_note uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); r app.dev_releases; n app.release_notes;
begin
  select * into r from app.dev_releases x where x.id = p_release for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  select * into n from app.release_notes x where x.id = p_note;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'note'; end if;
  if coalesce(p_on, false) then
    if n.product <> r.product then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
    if n.state <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'published'; end if;
    if exists (select 1 from app.dev_release_notes l where l.note_id = p_note and l.release_id <> p_release) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'other_release';
    end if;
    insert into app.dev_release_notes (release_id, note_id, ord, added_by)
    values (p_release, p_note, coalesce((select max(l.ord) + 1 from app.dev_release_notes l where l.release_id = p_release), 0), v_me)
    on conflict do nothing;
  else
    delete from app.dev_release_notes l where l.release_id = p_release and l.note_id = p_note;
  end if;
  update app.dev_releases set updated_at = now(), version = version + 1 where id = p_release;
  perform app.log('dev_release.changelog', 'dev_release', p_release::text, jsonb_build_object('on', coalesce(p_on, false)));
  return jsonb_build_object('ok', true);
end $fn$;

-- a manual item signed (or the signature withdrawn) by the person calling; the rollback plan needs its text, and the
-- anonymity check is signed or withdrawn by the owner only (D-DEV-08: the firewall's sign-off is not anyone's with dev:add)
create function public.dev_release_sign(p_release uuid, p_item text, p_on boolean, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); r app.dev_releases; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into r from app.dev_releases x where x.id = p_release for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  if p_item is null or p_item not in ('flag', 'anonymity', 'preview', 'rollback', 'help') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'item'; end if;
  if p_item = 'anonymity' then perform app.require_owner(); end if;
  if v_note is not null and char_length(v_note) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
  if coalesce(p_on, false) then
    if p_item = 'rollback' and v_note is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
    insert into app.dev_release_signoffs (release_id, item, signed_by, note) values (p_release, p_item, v_me, v_note)
    on conflict (release_id, item) do update set signed_by = excluded.signed_by, signed_at = now(), note = excluded.note;
  else
    delete from app.dev_release_signoffs s where s.release_id = p_release and s.item = p_item;
  end if;
  update app.dev_releases set updated_at = now(), version = version + 1 where id = p_release;
  perform app.log(case when coalesce(p_on, false) then 'dev_release.signed' else 'dev_release.unsigned' end, 'dev_release', p_release::text,
                  jsonb_build_object('item', p_item));
  return jsonb_build_object('ok', true);
end $fn$;

-- «Record release»: only when every item passes. The checklist is frozen as it stood, the commit with it, and the
-- changelog's drafts are published (Customers › Status and changelog reads them). Nothing is deployed, nothing rolled out.
create function public.dev_release_record(p_id uuid, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); r app.dev_releases; v_checks jsonb; v_commit jsonb; v_published int;
begin
  select * into r from app.dev_releases x where x.id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  if r.version <> coalesce(p_version, -1) then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  v_checks := app.delivery_release_checks(p_id);
  if exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'state' <> 'pass') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'checklist';
  end if;
  v_commit := app.delivery_release_commit(r);
  update app.release_notes n set state = 'published', published_at = now(), published_by = v_me, updated_at = now()
  where n.state = 'draft' and n.id in (select l.note_id from app.dev_release_notes l where l.release_id = p_id);
  get diagnostics v_published = row_count;
  update app.dev_releases set state = 'recorded', recorded_at = now(), recorded_by = v_me, checks = v_checks,
    sha = coalesce(v_commit ->> 'sha', sha), updated_at = now(), version = version + 1
  where id = p_id;
  perform app.log('dev_release.recorded', 'dev_release', p_id::text, jsonb_build_object('notes_published', v_published));
  return jsonb_build_object('ok', true, 'published', v_published);
end $fn$;

-- ---------------------------------------------------------------------------
-- a recorded release's changelog is frozen: its notes keep the product, kind, line, body and state they were released with
create function app.release_note_frozen(p_id uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.dev_release_notes l join app.dev_releases r on r.id = l.release_id where l.note_id = p_id and r.state = 'recorded')
$fn$;

-- 0078's writers, each with the «recorded» refusal; everything else as 0078 has it
create or replace function public.release_note_save(p_id uuid, p_product text, p_kind text, p_title text, p_body text default null,
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
    if app.release_note_frozen(p_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
    update app.release_notes n set product = p_product, kind = p_kind, title = btrim(p_title), body = nullif(btrim(p_body), ''),
      feature_request_id = p_feature_request, updated_at = now()
    where n.id = p_id returning * into v_row;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('release_note.changed', 'release_note', p_id::text);
  end if;
  return app.release_note_json(v_row);
end $fn$;

create or replace function public.release_note_publish(p_id uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'tickets:edit_others'); v_row app.release_notes;
begin
  if not coalesce(p_on, false) and app.release_note_frozen(p_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  update app.release_notes n set state = case when p_on then 'published' else 'draft' end,
    published_at = case when p_on then coalesce(n.published_at, now()) else null end,
    published_by = case when p_on then coalesce(n.published_by, v_me) else null end, updated_at = now()
  where n.id = p_id returning * into v_row;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log(case when p_on then 'release_note.published' else 'release_note.unpublished' end, 'release_note', p_id::text);
  return app.release_note_json(v_row);
end $fn$;

create or replace function public.release_note_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_any('dev:add', 'tickets:edit_others');
begin
  if app.release_note_frozen(p_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded'; end if;
  delete from app.release_notes n where n.id = p_id and n.state = 'draft';
  if not found then
    if exists (select 1 from app.release_notes n where n.id = p_id) then raise exception 'conflict' using errcode = 'check_violation', detail = 'published'; end if;
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  perform app.log('release_note.deleted', 'release_note', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- the same rule for any other writer, written as «nobody may change this content» (CLAUDE.md): a frozen note's meaning
-- does not change, and its changelog row is neither moved nor removed while its recorded release exists. Referential
-- maintenance passes: a person's row going (added_by, published_by, feature_request_id set null) changes no compared
-- column, and when the release itself is gone its rows go with it.
create function app.release_note_freeze() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if (old.product, old.kind, old.title, old.body, old.state, old.published_at) is distinct from
     (new.product, new.kind, new.title, new.body, new.state, new.published_at) and app.release_note_frozen(old.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded';
  end if;
  return new;
end $fn$;
create trigger release_notes_frozen before update on app.release_notes
  for each row execute function app.release_note_freeze();

create function app.dev_release_notes_freeze() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if (tg_op = 'DELETE' or (old.release_id, old.note_id, old.ord) is distinct from (new.release_id, new.note_id, new.ord))
     and exists (select 1 from app.dev_releases r where r.id = old.release_id and r.state = 'recorded') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recorded';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $fn$;
create trigger dev_release_notes_frozen before update or delete on app.dev_release_notes
  for each row execute function app.dev_release_notes_freeze();

-- ===========================================================================
-- 7. the integrations register
-- ===========================================================================
create function public.dev_integrations_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'see'); v_from timestamptz := now() - interval '30 days';
begin
  return jsonb_build_object(
    'can_configure', app.can('dev', 'configure'),
    'can_add', app.can('dev', 'add'),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by coalesce(a.name, a.email))
                       from app.admins a where a.active), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'key', i.key, 'direction', i.direction,
        'status', (select c.status from app.integration_connections c where c.provider = i.provider),
        'owner', case when i.owner_id is null then null else jsonb_build_object('id', i.owner_id, 'name', app.delivery_staff_name(i.owner_id)) end,
        'runs', case when i.direction = 'in' then null else (
           select jsonb_build_object('total', sum(t), 'failed', sum(f)) from (
             select count(*) t, count(*) filter (where j.state = 'failed') f from app.job_runs j
             where j.job_key = any (i.job_keys) and j.state in ('succeeded', 'failed') and coalesce(j.finished_at, j.queued_at) >= v_from
             union all
             select count(*), count(*) filter (where g.state = 'failed') from app.growth_sync_log g where g.source = any (i.sync_sources) and g.at >= v_from
             union all
             select count(*), count(*) filter (where not c.ok) from app.integration_calls c
             where i.call_product is not null and c.product = i.call_product and c.direction = 'out' and c.at >= v_from
             union all
             select count(*), count(*) filter (where a.state not in ('ok', 'retried_ok')) from app.ai_calls a
             where i.ai_provider is not null and a.provider = i.ai_provider and a.at >= v_from) u) end,
        'deliveries_30d', case when i.direction = 'in' then (select count(*) from app.dev_deliveries d where d.source = i.key and d.received_at >= v_from) end,
        'token_expires_at', (select coalesce(c.config ->> 'refresh_expires_at', c.config ->> 'token_expires_at') from app.integration_connections c where c.provider = i.provider),
        'api_version', case when i.call_product is not null then (select x.api_version from app.installations x where x.product = i.call_product) end,
        'change', jsonb_build_object('text', i.change_text, 'due_on', i.change_due_on, 'url', i.change_url, 'none', i.change_none,
                                     'by', app.delivery_staff_name(i.change_by), 'at', i.change_at),
        'plan', (select jsonb_build_object('id', p.id, 'change_text', p.change_text, 'due_on', p.due_on, 'owner', app.delivery_staff_name(p.owner_id),
                                           'planned_by', app.delivery_staff_name(p.planned_by), 'planned_at', p.planned_at)
                 from app.dev_integration_plans p where p.integration = i.key and p.closed_at is null))
      order by i.ord) from app.dev_integrations i), '[]'::jsonb));
end $fn$;

-- the owner and the upcoming change, typed by a person; a changed change closes an open plan as superseded
create function public.dev_integration_set(p_key text, p_owner uuid, p_change_text text, p_change_due_on date, p_change_url text, p_change_none boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'configure'); i app.dev_integrations; v_text text := nullif(btrim(coalesce(p_change_text, '')), '');
        v_url text := nullif(btrim(coalesce(p_change_url, '')), '');
begin
  select * into i from app.dev_integrations x where x.key = p_key for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_owner is not null and not exists (select 1 from app.admins a where a.id = p_owner and a.active) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner';
  end if;
  if v_text is not null and (char_length(v_text) > 200 or v_text ~ '[[:cntrl:]]') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change_text'; end if;
  if v_url is not null and v_url !~ '^https://[^[:space:]]{3,250}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change_url'; end if;
  if v_text is null and (p_change_due_on is not null or v_url is not null) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change_text'; end if;
  if coalesce(p_change_none, false) and v_text is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'change_none'; end if;
  update app.dev_integrations set owner_id = p_owner, change_text = v_text, change_due_on = p_change_due_on, change_url = v_url,
    change_none = coalesce(p_change_none, false),
    change_by = case when (v_text, p_change_due_on, v_url, coalesce(p_change_none, false)) is distinct from (i.change_text, i.change_due_on, i.change_url, i.change_none) then v_me else change_by end,
    change_at = case when (v_text, p_change_due_on, v_url, coalesce(p_change_none, false)) is distinct from (i.change_text, i.change_due_on, i.change_url, i.change_none) then now() else change_at end,
    updated_at = now()
  where key = p_key;
  if v_text is distinct from i.change_text then
    update app.dev_integration_plans set closed_at = now(), closed_by = v_me, closed_as = 'superseded' where integration = p_key and closed_at is null;
  end if;
  perform app.log('dev_integration.changed', 'dev_integration', p_key, jsonb_build_object('owner', p_owner is not null, 'change', v_text is not null));
  return jsonb_build_object('ok', true);
end $fn$;

-- «Plan upgrade»: a plan for the current upcoming change, owned by the integration's owner, with a due date
create function public.dev_integration_plan(p_key text, p_due_on date default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); i app.dev_integrations; v_id uuid;
begin
  select * into i from app.dev_integrations x where x.key = p_key for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if i.change_text is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_change'; end if;
  select p.id into v_id from app.dev_integration_plans p where p.integration = p_key and p.closed_at is null;
  if v_id is not null then return jsonb_build_object('id', v_id, 'existing', true); end if;
  insert into app.dev_integration_plans (integration, change_text, owner_id, due_on, planned_by)
  values (p_key, i.change_text, i.owner_id, coalesce(p_due_on, i.change_due_on), v_me) returning id into v_id;
  perform app.log('dev_integration.planned', 'dev_integration', p_key);
  return jsonb_build_object('id', v_id, 'existing', false);
end $fn$;

-- the planned upgrade is done
create function public.dev_integration_plan_done(p_plan uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('dev', 'add'); v_key text;
begin
  update app.dev_integration_plans set closed_at = now(), closed_by = v_me, closed_as = 'done' where id = p_plan and closed_at is null
  returning integration into v_key;
  if v_key is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('dev_integration.plan_done', 'dev_integration', v_key);
  return jsonb_build_object('ok', true);
end $fn$;

-- ===========================================================================
-- 8. rights on the functions
-- ===========================================================================
do $$
declare f text;
begin
  foreach f in array array['app.delivery_line(text, integer)', 'app.delivery_staff_name(uuid)', 'app.delivery_ci_main(text)', 'app.delivery_ci_json(app.dev_ci_runs)',
                           'app.delivery_deployment_json(app.dev_deployments)', 'app.delivery_suite_sum(jsonb, text[])', 'app.delivery_connection_json(text)',
                           'app.delivery_products_json()', 'app.delivery_release_commit(app.dev_releases)', 'app.delivery_release_checks(uuid)',
                           'app.delivery_release_json(app.dev_releases)', 'app.release_note_frozen(uuid)', 'app.release_note_freeze()',
                           'app.dev_release_notes_freeze()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.dev_deploys()', 'public.dev_project_set(text, text)', 'public.dev_ci_repo_set(text, text)', 'public.dev_metrics(integer)',
                           'public.dev_releases_get(uuid)', 'public.dev_release_add(text, text, date, text)', 'public.dev_release_set(uuid, jsonb, integer)',
                           'public.dev_release_delete(uuid)', 'public.dev_release_note_attach(uuid, uuid, boolean)',
                           'public.dev_release_sign(uuid, text, boolean, text)', 'public.dev_release_record(uuid, integer)',
                           'public.dev_integrations_get()', 'public.dev_integration_set(text, uuid, text, date, text, boolean)',
                           'public.dev_integration_plan(text, date)', 'public.dev_integration_plan_done(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_dev_vercel(text, text, timestamptz, jsonb)', 'public.worker_dev_ci(text, timestamptz, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
