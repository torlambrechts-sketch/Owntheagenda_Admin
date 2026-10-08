-- 0067 — An application's customers are Sentral's customers, from the day they started (V-CUS-01..04)
--
-- Tor, 2026-10-08, with Customers showing «No accounts use Orgpuls yet», Growth showing 3 signups in 7 days and the header
-- «API degraded»:
--
-- 1. Customers lists CRM companies (app.organizations) that are linked to an account. ingest_events made the account and
--    its product link, never the company, so every product customer was invisible. org.created now links the account to
--    the company with its organisation number, or makes the company (link_product_org); the accounts already here get
--    theirs below.
-- 2. account_products.created_at was the moment Sentral first heard of a tenant (the platform split's first delivery,
--    5 October), so every existing organisation counted as a signup that week. org.created carries the product's own
--    created_at; it is used, and the rows already here take theirs from the events they arrived with.
-- 3. A tenant whose first event is its deletion (a test's own organisation on the hosted product, 7 October) was made into
--    an account named by its id. It no longer is, and the one that was is removed.
-- 4. The header's health said «degraded» whenever no event had arrived for 10 minutes. Orgpuls sends events when something
--    happens and its usage once a day (03:35), never a heartbeat: a quiet day is not a fault. Degraded is now a day and two
--    hours without any event, besides the error rate and latency the calls show.
-- 5. Growth › Analytics divided seven days of signups by the visitors of the one day the tracker had run. The overview says
--    since when the tracker counts (tracked_since), the signups of those days (signups_tracked), no previous period's
--    visitors before it had a full one, and no daily visitors before the first day.

-- a product's timestamp, when it is one and not in the future
create function app.product_created_at(p text) returns timestamptz
  language plpgsql stable set search_path = ''
as $fn$
declare v timestamptz;
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' then return null; end if;
  v := p::timestamptz;
  return case when v <= statement_timestamp() then v end;
exception when others then
  return null;
end $fn$;

-- the CRM company of an account a product announced: the one already linked, else the unlinked company with its
-- organisation number, else a new one. When the number belongs to a company already linked to another account, nothing
-- is guessed: a person links it.
create function app.link_product_org(p_account uuid, p_product text) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.accounts; v_org uuid; v_emp int;
begin
  select * into a from app.accounts where id = p_account;
  if not found then return null; end if;
  select o.id into v_org from app.organizations o where o.account_id = a.id and o.deleted_at is null order by o.created_at limit 1;
  if v_org is not null then return v_org; end if;
  if a.org_number is not null then
    update app.organizations o set account_id = a.id, updated_at = now()
    where o.id = (select x.id from app.organizations x where x.org_number = a.org_number and x.deleted_at is null and not x.is_sample
                    and x.account_id is null order by x.created_at limit 1)
    returning o.id into v_org;
    if v_org is not null then return v_org; end if;
    if exists (select 1 from app.organizations x where x.org_number = a.org_number and x.deleted_at is null and not x.is_sample) then
      return null;
    end if;
  end if;
  select max(case when (ap.details ->> 'employee_count') ~ '^\d{1,7}$' then (ap.details ->> 'employee_count')::int end) into v_emp
  from app.account_products ap where ap.account_id = a.id;
  insert into app.organizations (name, org_number, account_id, employees, source)
  values (left(btrim(a.name), 200), a.org_number, a.id, v_emp, left(p_product, 60))
  returning id into v_org;
  return v_org;
end $fn$;
revoke all on function app.product_created_at(text) from public;
revoke all on function app.link_product_org(uuid, text) from public;

CREATE OR REPLACE FUNCTION public.ingest_events(p_product text, p_events jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      -- a tenant deleted before Sentral ever heard of it (a test's own organisation) leaves the event, not a customer
      continue when v_kind = 'org.deleted';
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
        -- created_at is when the organisation started in the product, not when Sentral first heard of it (0067)
        update app.account_products set details = details || v_p,
          created_at = coalesce(app.product_created_at(v_p ->> 'created_at'), created_at)
        where product = p_product and tenant_id = v_tenant;
        update app.accounts a set name = coalesce(nullif(v_p ->> 'name', ''), a.name),
                                  org_number = coalesce(a.org_number, nullif(v_p ->> 'org_number', '')), updated_at = now()
        from app.account_products ap where ap.product = p_product and ap.tenant_id = v_tenant and ap.account_id = a.id;
        perform app.link_product_org(ap.account_id, p_product) from app.account_products ap where ap.product = p_product and ap.tenant_id = v_tenant;
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
end $function$;

CREATE OR REPLACE FUNCTION app.application_health(p_product text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i app.installations; v_n bigint; v_err numeric; v_p95 numeric; v_last timestamptz; v_status text;
begin
  select * into i from app.installations where product = p_product;
  select count(*), avg(case when ok then 0 else 1 end), percentile_cont(0.95) within group (order by duration_ms) filter (where direction = 'out' and duration_ms is not null)
    into v_n, v_err, v_p95 from app.integration_calls where product = p_product and at > now() - interval '15 minutes';
  select max(received_at) into v_last from app.events_in where product = p_product;
  v_status := case when i.product is null then 'not_installed'
                   when not i.enabled then 'disabled'
                   when i.last_ping_ok is false then 'unreachable'
                   when v_n = 0 and v_last is null then 'no_data'
                   when v_err > 0.015 or v_p95 > 500 or v_last < now() - interval '26 hours' then 'degraded'
                   else 'operational' end;
  return jsonb_build_object('status', v_status, 'calls_15m', v_n, 'calls_per_min', round(v_n / 15.0, 1), 'p95_ms', round(v_p95), 'error_rate', round(v_err, 4),
                            'last_event_at', v_last, 'last_ping_at', i.last_ping_at, 'last_ping_ok', i.last_ping_ok, 'last_ping_ms', i.last_ping_ms);
end $function$;

CREATE OR REPLACE FUNCTION public.growth_overview(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d int := case when p_days in (7, 30, 90) then p_days else 30 end;
  v_from timestamptz := now() - make_interval(days => d);
  v_prev timestamptz := now() - make_interval(days => 2 * d);
  v_month date := date_trunc('month', now() - make_interval(days => d))::date;
  v_product text := nullif(p_product, 'all');
  v_sites uuid[];
  v_live boolean;
  v_since date;
begin
  perform app.require_marketing_reports();
  if v_product is not null and not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  v_sites := array(select s.id from app.web_sites s where s.active and (v_product is null or s.product = v_product) order by s.hostname);
  v_live := exists (select 1 from app.web_sessions w where w.site_id = any (v_sites));
  -- the first day the tracker counted: before it, «no visitors» is not a fact (0067)
  v_since := (select min(w.day) from app.web_sessions w where w.site_id = any (v_sites));
  return jsonb_build_object(
    'days', d,
    'site', (select jsonb_build_object('id', s.id, 'hostname', s.hostname) from app.web_sites s where s.id = v_sites[1]),
    'tracked', v_live,
    'tracked_since', v_since,
    'kpis', jsonb_build_object(
      'visitors', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                         where w.site_id = any (v_sites) and w.day > current_date - d) end,
      'visitors_prev', case when v_live and v_since <= current_date - 2 * d + 1 then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                              where w.site_id = any (v_sites) and w.day > current_date - 2 * d and w.day <= current_date - d) end,
      'signups', (select count(*) from app.account_products ap where ap.created_at > v_from and app.in_scope(v_product, ap.product)),
      -- the signups of the days the tracker counted, the only ones a visit → signup share may divide
      'signups_tracked', case when v_live then (select count(*) from app.account_products ap where ap.created_at > greatest(v_from, v_since::timestamptz)
                                                and app.in_scope(v_product, ap.product)) end,
      'signups_prev', (select count(*) from app.account_products ap where ap.created_at > v_prev and ap.created_at <= v_from and app.in_scope(v_product, ap.product)),
      -- the definition analytics_business uses: trials started in the cohort months, converted within 45 days
      'trial_conversion', (select jsonb_build_object('trials', sum(t.trials), 'converted', sum(t.converted)) from app.v_trial_conversion t
                           where t.cohort >= date_trunc('month', now() - make_interval(days => d + 45))
                             and t.cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'
                             and app.in_scope(v_product, t.product)),
      'spend', (select sum(ms.amount) from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
                where ms.month >= v_month and ms.currency = 'NOK' and app.in_scope(v_product, c.product)),
      'spend_excluded_currency', (select count(*) from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
                                  where ms.month >= v_month and ms.currency <> 'NOK' and app.in_scope(v_product, c.product)),
      'spend_from', v_month,
      'paying_new', (select count(*) from app.subscriptions s where s.confirmed_at >= v_month and app.in_scope(v_product, s.product))),
    'daily', (select jsonb_agg(jsonb_build_object(
                'day', g.day,
                'signups', (select count(*) from app.account_products ap where ap.created_at::date = g.day and app.in_scope(v_product, ap.product)),
                'visitors', case when v_live and g.day >= v_since then (select count(distinct w.visitor_hash) from app.web_sessions w where w.site_id = any (v_sites) and w.day = g.day) end)
              order by g.day)
              from (select generate_series(current_date - d + 1, current_date, interval '1 day')::date as day) g),
    'funnel', (with c as (select ap.product, ap.tenant_id from app.account_products ap where ap.created_at > v_from and app.in_scope(v_product, ap.product))
               select jsonb_build_array(
                 jsonb_build_object('key', 'visited', 'count', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                                                                      where w.site_id = any (v_sites) and w.day > current_date - d) end),
                 jsonb_build_object('key', 'viewed_pricing', 'count', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                                                                      where w.site_id = any (v_sites) and w.day > current_date - d
                                                                                        and exists (select 1 from app.web_pageviews p where p.session_id = w.id and p.path ~* '^/(en/)?(priser|pricing)(/|$)')) end),
                 jsonb_build_object('key', 'started_signup', 'count', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                                                                      where w.site_id = any (v_sites) and w.day > current_date - d
                                                                                        and (exists (select 1 from app.web_events e where e.session_id = w.id and e.name in ('signup_started', 'cta'))
                                                                                             or exists (select 1 from app.web_pageviews p where p.session_id = w.id and p.path ~* '^/(en/)?(registrer|signup)(/|$)'))) end),
                 jsonb_build_object('key', 'account_created', 'count', (select count(*) from c)),
                 jsonb_build_object('key', 'survey_sent', 'count', (select count(*) from c join app.activation_milestones m
                                                                     on m.product = c.product and m.tenant_id = c.tenant_id and m.key = 'survey_sent')),
                 jsonb_build_object('key', 'paying', 'count', (select count(*) from c join app.subscriptions s
                                                                on s.product = c.product and s.tenant_id = c.tenant_id and s.confirmed_at is not null)))),
    -- signups by the first touch's channel; visits are the site's sessions by channel, null without the tracker
    'sources', coalesce((select jsonb_agg(jsonb_build_object('channel', coalesce(v.ch, g.ch), 'visits', case when v_live then coalesce(v.n, 0) end, 'signups', coalesce(g.n, 0))
                                          order by coalesce(g.n, 0) desc, coalesce(v.n, 0) desc, coalesce(v.ch, g.ch)) from
        (select coalesce(w.channel, 'direct') ch, count(*) n from app.web_sessions w where w.site_id = any (v_sites) and w.day > current_date - d group by 1) v
        full join (select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) ch, count(*) n from app.account_products ap
                   where ap.created_at > v_from and app.in_scope(v_product, ap.product) group by 1) g on g.ch = v.ch), '[]'::jsonb),
    -- a session cannot be joined to a signup (cookieless, D-37), so a landing page carries visits only
    'pages', coalesce((select jsonb_agg(jsonb_build_object('path', x.entry_path, 'visits', x.n) order by x.n desc, x.entry_path) from (
        select w.entry_path, count(*) n from app.web_sessions w where w.site_id = any (v_sites) and w.day > current_date - d and w.entry_path is not null
        group by 1 order by 2 desc limit 10) x), '[]'::jsonb));
end $function$;

-- the rows already here: the product's own start, the tenant that only ever announced its deletion, the companies
update app.account_products ap set created_at = x.at
from (select distinct on (e.product, e.tenant_id) e.product, e.tenant_id, app.product_created_at(e.payload ->> 'created_at') at
      from app.events_in e where e.kind = 'org.created' order by e.product, e.tenant_id, e.occurred_at desc) x
where ap.product = x.product and ap.tenant_id = x.tenant_id and x.at is not null and ap.created_at is distinct from x.at;

delete from app.account_products ap
where ap.status = 'deleted'
  and not exists (select 1 from app.events_in e where e.product = ap.product and e.tenant_id = ap.tenant_id and e.kind <> 'org.deleted');
-- its account carried the tenant's id for a name, having never been told one; nothing else points at it
delete from app.accounts a
where a.name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and a.org_number is null
  and not exists (select 1 from app.account_products ap where ap.account_id = a.id)
  and not exists (select 1 from app.organizations o where o.account_id = a.id);

select app.link_product_org(ap.account_id, ap.product)
from (select distinct on (ap.account_id) ap.account_id, ap.product from app.account_products ap
      where exists (select 1 from app.events_in e where e.product = ap.product and e.tenant_id = ap.tenant_id and e.kind = 'org.created')
      order by ap.account_id, ap.created_at) ap;
