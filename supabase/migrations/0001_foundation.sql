-- 0001_foundation.sql — the platform's own database: who may sign in, which products are installed,
-- the customers they share, and what the products report.
--
-- Every table lives in `app`, which PostgREST does not expose, with row level security on and no
-- policy, and no grant to a client role. The admin UI reads through SECURITY DEFINER functions in
-- `public` that answer only an admin signed in with a second factor (aal2). The edge functions write
-- with the service role: orgpuls-events (signed events in) and product-command (signed commands out).
--
-- A product reports numbers and its customers' own contacts, never anything about a person who
-- answered a survey: Orgpuls' event registry (its 0205) cannot carry one, and nothing here asks.

create schema if not exists app;
revoke all on schema app from public, anon, authenticated;
grant usage on schema app to service_role;

-- ---------------------------------------------------------------------------
-- who may sign in: an address on this list, confirmed, with a second factor
create table app.admins (
  email      text primary key check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role       text not null default 'admin' check (role in ('owner', 'admin')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create function app.admin_email() returns text
  language sql stable security definer set search_path = ''
as $fn$
  select a.email from app.admins a join auth.users u on lower(u.email) = a.email
  where u.id = auth.uid() and u.email_confirmed_at is not null and a.active
$fn$;

create function app.is_admin() returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.admin_email() is not null and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$fn$;

-- ---------------------------------------------------------------------------
-- products and where they are reached. The secrets that sign commands and verify events are the edge
-- functions' environment (<PRODUCT>_TOKEN_SECRET, <PRODUCT>_WEBHOOK_SECRET), never a row.
create table app.products (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,30}$'),
  name       text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create table app.installations (
  product    text primary key references app.products (key) on delete cascade,
  api_url    text not null check (api_url ~ '^https://[^\s/]+$'),
  -- the product's public (anon) key: public by design, it only reaches the product's public functions
  public_key text not null check (char_length(public_key) between 20 and 2000),
  enabled    boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- customers: an account is a company; a product knows it as one of its own tenants
create table app.accounts (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  org_number text unique check (org_number is null or org_number ~ '^\d{9}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table app.account_products (
  product     text not null references app.products (key),
  tenant_id   text not null check (char_length(tenant_id) between 1 and 100),
  account_id  uuid not null references app.accounts (id) on delete cascade,
  status      text not null default 'active' check (status in ('active', 'deleted')),
  details     jsonb not null default '{}'::jsonb,
  attribution jsonb,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  primary key (product, tenant_id)
);
create index account_products_account on app.account_products (account_id);

-- the subscription as the product last reported it
create table app.subscriptions (
  product             text not null,
  tenant_id           text not null,
  plan                text,
  billing_interval    text,
  trial_started_at    timestamptz,
  trial_ends_at       timestamptz,
  confirmed_at        timestamptz,
  free_from           timestamptz,
  cancelled_at        timestamptz,
  cancel_effective_at timestamptz,
  deletion_due_at     timestamptz,
  updated_at          timestamptz not null default now(),
  primary key (product, tenant_id),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

-- a customer's own users (daglig leder, avdelingsleder, verneombud): contacts, never respondents
create table app.members (
  product    text not null,
  tenant_id  text not null,
  user_id    text not null,
  role       text,
  email      text,
  name       text,
  active     boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (product, tenant_id, user_id),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

create table app.usage_daily (
  product   text not null,
  tenant_id text not null,
  day       date not null,
  data      jsonb not null,
  primary key (product, tenant_id, day),
  foreign key (product, tenant_id) references app.account_products (product, tenant_id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- every event as it arrived, once: the product's own id makes a retried delivery a duplicate
create table app.events_in (
  id          bigint generated always as identity primary key,
  product     text not null references app.products (key),
  source_id   bigint not null,
  kind        text not null check (kind ~ '^[a-z]+\.[a-z_]+$'),
  tenant_id   text,
  payload     jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  unique (product, source_id)
);
create index events_in_kind on app.events_in (product, kind, received_at desc);

-- what an admin, or the platform itself, did to a product: a command, by name, with its argument names
create table app.audit (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor      text not null check (char_length(actor) between 1 and 254),
  product    text not null,
  command    text not null check (command ~ '^[a-z]+\.[a-z_]+$'),
  arg_names  text[] not null default '{}',
  ok         boolean not null,
  error      text check (error is null or char_length(error) <= 200)
);

-- an audit row is never changed or removed
create function app.audit_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  raise exception 'the audit is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger audit_fixed before update or delete on app.audit for each row execute function app.audit_fixed();

-- closed: every table, RLS on, no policy, no client grant
do $$
declare t text;
begin
  for t in select c.relname from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;
revoke all on function app.admin_email() from public, anon;
revoke all on function app.is_admin() from public, anon;
revoke all on function app.audit_fixed() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- the events in: stored once, then projected onto the customer they concern
create function public.ingest_events(p_product text, p_events jsonb) returns jsonb
  language plpgsql security definer set search_path = ''
as $fn$
declare
  e        jsonb;
  v_id     bigint;
  v_kind   text;
  v_tenant text;
  v_p      jsonb;
  v_at     timestamptz;
  v_acct   uuid;
  v_new    int := 0;
  v_dup    int := 0;
begin
  if not exists (select 1 from app.installations i where i.product = p_product and i.enabled) then
    raise exception 'ingest: % is not installed', p_product using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 500 then
    raise exception 'ingest: events must be an array of at most 500' using errcode = 'invalid_parameter_value';
  end if;
  for e in select * from jsonb_array_elements(p_events) loop
    v_kind := e ->> 'kind';
    v_tenant := nullif(e ->> 'org_id', '');
    v_p := coalesce(e -> 'payload', '{}'::jsonb);
    v_at := coalesce((e ->> 'created_at')::timestamptz, now());
    if jsonb_typeof(v_p) <> 'object' or (e ->> 'id') !~ '^\d{1,18}$' or v_kind !~ '^[a-z]+\.[a-z_]+$' then
      raise exception 'ingest: malformed event' using errcode = 'invalid_parameter_value';
    end if;
    insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at)
    values (p_product, (e ->> 'id')::bigint, v_kind, v_tenant, v_p, v_at)
    on conflict (product, source_id) do nothing
    returning id into v_id;
    if v_id is null then
      v_dup := v_dup + 1;
      continue;
    end if;
    v_new := v_new + 1;
    if v_tenant is null then
      continue;
    end if;

    -- the customer, made the first time a product names it
    if not exists (select 1 from app.account_products ap where ap.product = p_product and ap.tenant_id = v_tenant) then
      select a.id into v_acct from app.accounts a where a.org_number = v_p ->> 'org_number';
      if v_acct is null then
        insert into app.accounts (name, org_number)
        values (coalesce(nullif(v_p ->> 'name', ''), v_tenant), nullif(v_p ->> 'org_number', ''))
        returning id into v_acct;
      end if;
      insert into app.account_products (product, tenant_id, account_id) values (p_product, v_tenant, v_acct);
    end if;

    case v_kind
      when 'org.created' then
        update app.account_products set details = details || v_p where product = p_product and tenant_id = v_tenant;
        update app.accounts a set name = coalesce(nullif(v_p ->> 'name', ''), a.name),
                                  org_number = coalesce(a.org_number, nullif(v_p ->> 'org_number', '')), updated_at = now()
        from app.account_products ap where ap.product = p_product and ap.tenant_id = v_tenant and ap.account_id = a.id;
      when 'org.deleted' then
        update app.account_products set status = 'deleted', deleted_at = v_at where product = p_product and tenant_id = v_tenant;
      when 'org.attribution' then
        update app.account_products set attribution = coalesce(attribution, '{}'::jsonb) || v_p
        where product = p_product and tenant_id = v_tenant;
      when 'billing.changed' then
        insert into app.subscriptions (product, tenant_id, plan, billing_interval, trial_started_at, trial_ends_at, confirmed_at,
                                       free_from, cancelled_at, cancel_effective_at, deletion_due_at, updated_at)
        values (p_product, v_tenant, v_p ->> 'plan', v_p ->> 'billing_interval', (v_p ->> 'trial_started_at')::timestamptz,
                (v_p ->> 'trial_ends_at')::timestamptz, (v_p ->> 'confirmed_at')::timestamptz, (v_p ->> 'free_from')::timestamptz,
                (v_p ->> 'cancelled_at')::timestamptz, (v_p ->> 'cancel_effective_at')::timestamptz,
                (v_p ->> 'deletion_due_at')::timestamptz, v_at)
        on conflict (product, tenant_id) do update set
          plan = excluded.plan, billing_interval = excluded.billing_interval, trial_started_at = excluded.trial_started_at,
          trial_ends_at = excluded.trial_ends_at, confirmed_at = excluded.confirmed_at, free_from = excluded.free_from,
          cancelled_at = excluded.cancelled_at, cancel_effective_at = excluded.cancel_effective_at,
          deletion_due_at = excluded.deletion_due_at, updated_at = excluded.updated_at
        where app.subscriptions.updated_at <= excluded.updated_at;
      when 'member.joined' then
        insert into app.members (product, tenant_id, user_id, role, email, name, active, updated_at)
        values (p_product, v_tenant, v_p ->> 'user_id', v_p ->> 'role', v_p ->> 'email', v_p ->> 'name', true, v_at)
        on conflict (product, tenant_id, user_id) do update set role = excluded.role, email = coalesce(excluded.email, app.members.email),
          name = coalesce(excluded.name, app.members.name), active = true, updated_at = excluded.updated_at
        where app.members.updated_at <= excluded.updated_at;
      when 'member.left' then
        update app.members set active = false, updated_at = v_at
        where product = p_product and tenant_id = v_tenant and user_id = v_p ->> 'user_id' and updated_at <= v_at;
      when 'usage.daily' then
        insert into app.usage_daily (product, tenant_id, day, data) values (p_product, v_tenant, v_at::date, v_p)
        on conflict (product, tenant_id, day) do update set data = excluded.data;
      else
        null;  -- kept as it arrived; a later reader decides what it means
    end case;
  end loop;
  return jsonb_build_object('received', v_new, 'duplicate', v_dup);
end $fn$;
revoke all on function public.ingest_events(text, jsonb) from public, anon, authenticated;
grant execute on function public.ingest_events(text, jsonb) to service_role;

-- a command's outcome, written by product-command
create function public.record_command(p_actor text, p_product text, p_command text, p_arg_names text[], p_ok boolean, p_error text)
  returns void language sql security definer set search_path = ''
as $fn$
  insert into app.audit (actor, product, command, arg_names, ok, error)
  values (left(p_actor, 254), p_product, p_command, coalesce(p_arg_names, '{}'), p_ok, left(p_error, 200));
$fn$;
revoke all on function public.record_command(text, text, text, text[], boolean, text) from public, anon, authenticated;
grant execute on function public.record_command(text, text, text, text[], boolean, text) to service_role;

-- the installation a command goes to, for product-command
create function public.installation_of(p_product text) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('api_url', i.api_url, 'public_key', i.public_key)
  from app.installations i where i.product = p_product and i.enabled
$fn$;
revoke all on function public.installation_of(text) from public, anon, authenticated;
grant execute on function public.installation_of(text) to service_role;

-- ---------------------------------------------------------------------------
-- what the signed-in person is: an admin's account, and whether the second factor is done
create function public.admin_whoami() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('account', app.admin_email() is not null, 'aal2', coalesce(auth.jwt() ->> 'aal', '') = 'aal2',
                            'admin', app.is_admin(), 'email', app.admin_email())
$fn$;
revoke all on function public.admin_whoami() from public, anon;
grant execute on function public.admin_whoami() to authenticated;

-- the platform's state at a glance: installations, customers, events — kinds and times, never a payload
create function public.platform_status() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not app.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;
  return jsonb_build_object('ok', true,
    'installations', (select coalesce(jsonb_agg(jsonb_build_object('product', p.key, 'name', p.name, 'enabled', i.enabled,
                                                                   'host', substring(i.api_url from '^https://([^/]+)')) order by p.key), '[]')
                      from app.products p left join app.installations i on i.product = p.key),
    'accounts', (select count(*) from app.accounts),
    'tenants_active', (select count(*) from app.account_products where status = 'active'),
    'events', (select count(*) from app.events_in),
    'last_event_at', (select max(received_at) from app.events_in),
    'by_kind', (select coalesce(jsonb_object_agg(k.kind, k.n), '{}') from
                 (select kind, count(*) n from app.events_in where received_at > now() - interval '30 days' group by kind) k),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('product', r.product, 'kind', r.kind, 'received_at', r.received_at)
                                         order by r.id desc), '[]')
               from (select id, product, kind, received_at from app.events_in order by id desc limit 20) r),
    'commands', (select coalesce(jsonb_agg(jsonb_build_object('at', c.at, 'actor', c.actor, 'product', c.product,
                                                              'command', c.command, 'ok', c.ok, 'error', c.error) order by c.id desc), '[]')
                 from (select * from app.audit order by id desc limit 10) c));
end $fn$;
revoke all on function public.platform_status() from public, anon;
grant execute on function public.platform_status() to authenticated;

insert into app.products (key, name) values ('orgpuls', 'Orgpuls');
