-- 0008_billing_overview.sql — what a subscription is worth (D-22), the MRR history, and the overview.
--
-- Orgpuls adds price, currency and seats to billing.changed (D-22), and the payment state when a payment
-- fails. The platform stores them on the subscription mirror and takes a daily MRR snapshot per product,
-- so the overview's twelve-month chart is history, not a reconstruction. Status is derived, never typed.
-- The overview reads only what exists; a section without a source is null and the screen leaves it out.

alter table app.subscriptions
  add column price         numeric check (price is null or price >= 0),           -- per billing interval
  add column currency      text not null default 'NOK' check (currency ~ '^[A-Z]{3}$'),
  add column seats         int check (seats is null or seats >= 0),
  add column payment_state text not null default 'ok' check (payment_state in ('ok', 'past_due', 'suspended'));

-- monthly recurring revenue of one subscription: the price per month while it is paid for
create function app.sub_mrr(s app.subscriptions) returns numeric
  language sql stable set search_path = ''
as $fn$
  select case
    when s.confirmed_at is null or s.price is null then 0
    when s.cancel_effective_at is not null and s.cancel_effective_at <= now() then 0
    when s.free_from is not null and s.free_from <= now() then 0
    when s.billing_interval = 'year' then round(s.price / 12, 2)
    else s.price end
$fn$;

-- trial, active, past_due, suspended, cancelled, expired, free
create function app.sub_status(s app.subscriptions) returns text
  language sql stable set search_path = ''
as $fn$
  select case
    when s.cancel_effective_at is not null and s.cancel_effective_at <= now() then 'cancelled'
    when s.confirmed_at is null and s.trial_ends_at is not null and s.trial_ends_at > now() then 'trial'
    when s.confirmed_at is null then 'expired'
    when s.free_from is not null and s.free_from <= now() then 'free'
    when s.payment_state = 'suspended' then 'suspended'
    when s.payment_state = 'past_due' then 'past_due'
    else 'active' end
$fn$;

-- the daily MRR snapshot per product
create table app.mrr_daily (
  day     date not null,
  product text not null references app.products (key) on delete cascade,
  mrr     numeric not null default 0,
  paying  int not null default 0,
  trials  int not null default 0,
  primary key (day, product)
);

create function app.snapshot_mrr() returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.mrr_daily (day, product, mrr, paying, trials)
  select current_date, p.key,
         coalesce(sum(app.sub_mrr(s)), 0),
         count(*) filter (where app.sub_mrr(s) > 0),
         count(*) filter (where app.sub_status(s) = 'trial')
  from app.products p
  left join app.subscriptions s on s.product = p.key
  left join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id and ap.status = 'active'
  group by p.key
  on conflict (day, product) do update set mrr = excluded.mrr, paying = excluded.paying, trials = excluded.trials;
$fn$;
select cron.schedule('platform-mrr-snapshot', '5 0 * * *', 'select app.snapshot_mrr()');

-- ---------------------------------------------------------------------------
-- billing.changed now carries price, currency, seats and payment_state
create or replace function public.ingest_events(p_product text, p_events jsonb) returns jsonb
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
                                       free_from, cancelled_at, cancel_effective_at, deletion_due_at, price, currency, seats, payment_state, updated_at)
        values (p_product, v_tenant, v_p ->> 'plan', v_p ->> 'billing_interval', (v_p ->> 'trial_started_at')::timestamptz,
                (v_p ->> 'trial_ends_at')::timestamptz, (v_p ->> 'confirmed_at')::timestamptz, (v_p ->> 'free_from')::timestamptz,
                (v_p ->> 'cancelled_at')::timestamptz, (v_p ->> 'cancel_effective_at')::timestamptz,
                (v_p ->> 'deletion_due_at')::timestamptz,
                case when (v_p ->> 'price') ~ '^\d+(\.\d+)?$' then (v_p ->> 'price')::numeric end,
                coalesce(case when (v_p ->> 'currency') ~ '^[A-Z]{3}$' then v_p ->> 'currency' end, 'NOK'),
                case when (v_p ->> 'seats') ~ '^\d{1,7}$' then (v_p ->> 'seats')::int end,
                coalesce(case when (v_p ->> 'payment_state') in ('ok', 'past_due', 'suspended') then v_p ->> 'payment_state' end, 'ok'),
                v_at)
        on conflict (product, tenant_id) do update set
          plan = excluded.plan, billing_interval = excluded.billing_interval, trial_started_at = excluded.trial_started_at,
          trial_ends_at = excluded.trial_ends_at, confirmed_at = excluded.confirmed_at, free_from = excluded.free_from,
          cancelled_at = excluded.cancelled_at, cancel_effective_at = excluded.cancel_effective_at,
          deletion_due_at = excluded.deletion_due_at,
          price = coalesce(excluded.price, app.subscriptions.price), currency = excluded.currency,
          seats = coalesce(excluded.seats, app.subscriptions.seats), payment_state = excluded.payment_state,
          updated_at = excluded.updated_at
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
        null;
    end case;
  end loop;
  return jsonb_build_object('received', v_new, 'duplicate', v_dup);
end $fn$;

-- ---------------------------------------------------------------------------
-- the overview, for one product or all. Sections without a source are null.
create function public.overview(p_product text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  v_prods text[];
  v_month date := date_trunc('month', now())::date;
  r jsonb;
begin
  v_prods := case when p_product is null or p_product = 'all' then array(select key from app.products) else array[p_product] end;

  with subs as (
    select s.*, ap.account_id, app.sub_status(s) st, app.sub_mrr(s) mrr
    from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
    where s.product = any (v_prods) and ap.status = 'active'
  ), acct as (
    select a.id, bool_or(s.mrr > 0) paying, bool_or(s.st = 'trial') trial, min(s.trial_ends_at) filter (where s.st = 'trial') trial_ends
    from app.accounts a join subs s on s.account_id = a.id group by a.id
  )
  select jsonb_build_object(
    'mrr', jsonb_build_object(
      'now', (select coalesce(sum(mrr), 0) from subs),
      'priced', (select count(*) from subs where price is not null),
      'prev', (select sum(m.mrr) from app.mrr_daily m where m.product = any (v_prods)
               and m.day = (select max(day) from app.mrr_daily where day <= current_date - 30))),
    'paying', jsonb_build_object(
      'now', (select count(*) from acct where paying),
      'subs_now', (select count(*) from subs where mrr > 0),
      'prev', (select sum(m.paying) from app.mrr_daily m where m.product = any (v_prods)
               and m.day = (select max(day) from app.mrr_daily where day <= current_date - 30))),
    'trials', jsonb_build_object(
      'now', (select count(*) from acct where trial),
      'ending7', (select count(*) from acct where trial and trial_ends <= now() + interval '7 days'),
      'ended_month', (select count(*) from subs where trial_ends_at >= v_month and trial_ends_at < now()),
      'converted_month', (select count(*) from subs where trial_ends_at >= v_month and trial_ends_at < now() and confirmed_at is not null)),
    'apps', (select coalesce(jsonb_agg(jsonb_build_object(
               'key', p.key, 'name', p.name, 'color', p.color, 'ink', p.ink,
               'host', substring(i.api_url from '^https://([^/]+)'), 'enabled', coalesce(i.enabled, false), 'installed', i.product is not null,
               'orgs', (select count(distinct s.account_id) from subs s where s.product = p.key),
               'mrr', (select sum(s.mrr) from subs s where s.product = p.key and s.price is not null),
               'last_event_at', (select max(received_at) from app.events_in e where e.product = p.key)) order by p.ord, p.key), '[]'::jsonb)
             from app.products p left join app.installations i on i.product = p.key where p.key = any (v_prods)),
    'mrr_series', (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(x.m, 'YYYY-MM'), 'by_product', x.by) order by x.m), '[]'::jsonb)
                   from (select date_trunc('month', d.day)::date m,
                                jsonb_object_agg(d.product, d.mrr) by
                         from app.mrr_daily d
                         where d.product = any (v_prods)
                           and d.day = (select max(d2.day) from app.mrr_daily d2 where date_trunc('month', d2.day) = date_trunc('month', d.day))
                           and d.day > (v_month - interval '11 months')
                         group by 1) x),
    'trials_list', (select coalesce(jsonb_agg(t order by t ->> 'ends'), '[]'::jsonb) from (
                      select jsonb_build_object('account_id', a.id, 'organization_id', o.id, 'name', coalesce(o.name, ac.name),
                                                'org_number', ac.org_number, 'employees', o.employees, 'ends', a.trial_ends,
                                                'source', o.source, 'owner', (select s.name from app.admins s where s.id = o.owner_id)) t
                      from acct a join app.accounts ac on ac.id = a.id
                      left join app.organizations o on o.account_id = a.id and o.deleted_at is null and (v_sandbox or not o.is_sample)
                      where a.trial order by a.trial_ends limit 6) z),
    'tickets', null,
    'pipeline', null,
    'at_risk', null,
    'todo', '[]'::jsonb
  ) into r;
  perform app.log('overview.read', null, null, jsonb_build_object('product', coalesce(p_product, 'all')));
  return r;
end $fn$;

do $$
begin
  execute 'alter table app.mrr_daily enable row level security';
  execute 'revoke all on app.mrr_daily from public, anon, authenticated';
  execute 'grant all on app.mrr_daily to service_role';
end $$;
revoke all on function app.sub_mrr(app.subscriptions) from public, anon, authenticated;
revoke all on function app.sub_status(app.subscriptions) from public, anon, authenticated;
revoke all on function app.snapshot_mrr() from public, anon, authenticated;
revoke all on function public.overview(text) from public, anon;
grant execute on function public.overview(text) to authenticated;
