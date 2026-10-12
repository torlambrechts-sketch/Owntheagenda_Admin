-- 0083_growth_v3.sql — Growth v3: the campaign card and Email and automation (GrowthMarketing.dc.html of 12 Oct 2026;
-- docs/crm-enrichment/v3/growth-v3-gap.md, PLAN.md wave 1 «growth»).
--
-- 1. Google Ads keywords, read only. ads-run reads each keyword (ad_group_criterion: text, match type, status) and its days
--    from keyword_view (impressions, clicks, cost, conversions), and each Google campaign's bidding strategy, so a tip about
--    a keyword's bid is offered only where bids are set by hand. Never search_term_view: what people typed can carry a name.
--    Keyword text is the advertiser's own.
-- 2. A marketing campaign's card (ad_campaign_detail): 21 days to yesterday (Europe/Oslo) of spend from the ad platforms'
--    days (only for a campaign the platform campaigns count as; typed spend is per month and is never spread over days) and
--    of signups the website tracker saw complete with the campaign's utm_campaign; the ads and keywords of its platform
--    campaigns with their own clicks, cost and conversions, and signups by utm_content (an ad's id) and utm_term (a keyword)
--    where the platform's tracking template carries them (else null, «—»). The tips are rules in the app over this answer
--    (lib/growth/v3.ts); every tip links to the platform, nothing is written to one (X-V3-3).
-- 3. Email and automation: each email step's last 30 days (simple_sequence_results), the open rate by send weekday and hour
--    over 90 days in Europe/Oslo with at least 20 delivered per cell (email_send_times), and «Send all steps at the best time»:
--    a per-sequence send window (sequence_send_windows; none by default) derived from those cells. The engine honours it: an
--    email step of a sequence with a window, reached outside it, waits for the window's next slot and asks «stop when» again
--    then (wf_step's campaign_action, patched below the way 0059 patched wf_match).
-- Every new table: app, RLS on, no policy, no grant. Logs and audit carry ids, counts and codes.

-- ===========================================================================
-- 1. Google Ads keywords and the campaigns' bidding
-- ===========================================================================
create table app.ad_platform_keywords (
  id                   uuid primary key default gen_random_uuid(),
  account_id           uuid not null references app.ad_accounts (id) on delete cascade,
  campaign_external_id text not null check (campaign_external_id ~ '^[0-9]{1,20}$'),
  ad_group_external_id text not null check (ad_group_external_id ~ '^[0-9]{1,20}$'),
  criterion_id         text not null check (criterion_id ~ '^[0-9]{1,20}$'),
  text                 text not null check (char_length(text) between 1 and 80),
  match_type           text check (match_type is null or match_type in ('exact', 'phrase', 'broad')),
  status               text not null check (status in ('live', 'paused', 'ended')),
  updated_at           timestamptz not null default now(),
  -- a criterion id is unique only within its ad group
  unique (account_id, ad_group_external_id, criterion_id)
);
create index ad_platform_keywords_campaign on app.ad_platform_keywords (account_id, campaign_external_id);
alter table app.ad_platform_keywords enable row level security;
revoke all on app.ad_platform_keywords from public, anon, authenticated;

-- a keyword's day, as Google counts it, in the account's currency
create table app.ad_keyword_daily (
  account_id           uuid not null references app.ad_accounts (id) on delete cascade,
  ad_group_external_id text not null check (ad_group_external_id ~ '^[0-9]{1,20}$'),
  criterion_id         text not null check (criterion_id ~ '^[0-9]{1,20}$'),
  day                  date not null,
  impressions          bigint not null default 0 check (impressions >= 0),
  clicks               bigint not null default 0 check (clicks >= 0),
  spend                numeric(14, 2) not null default 0 check (spend >= 0),
  conversions          numeric(14, 2) check (conversions is null or conversions >= 0),
  primary key (account_id, ad_group_external_id, criterion_id, day)
);
alter table app.ad_keyword_daily enable row level security;
revoke all on app.ad_keyword_daily from public, anon, authenticated;

-- Google's bidding_strategy_type, lower case (manual_cpc, maximize_conversions, target_cpa …); null for the other platforms
alter table app.ad_platform_campaigns add column bidding text check (bidding is null or bidding ~ '^[a-z0-9_]{1,40}$');

-- an account's keywords as they are now and their days in the window, replaced whole (the worker, after worker_ads_import).
-- A keyword the listing no longer carries was removed in Google Ads: it is kept as ended with its days.
create function public.worker_ads_keywords(p_account uuid, p_from date, p_to date, p_keywords jsonb, p_daily jsonb, p_bidding jsonb default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.ad_accounts; v_kw int; v_rows int;
begin
  select * into a from app.ad_accounts where id = p_account for update;
  if a.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if a.provider <> 'google_ads' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'window'; end if;
  if p_keywords is not null and jsonb_typeof(p_keywords) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'keywords'; end if;
  insert into app.ad_platform_keywords (account_id, campaign_external_id, ad_group_external_id, criterion_id, text, match_type, status)
  select a.id, x ->> 'campaign', x ->> 'ad_group', x ->> 'id', left(btrim(x ->> 'text'), 80),
         case when x ->> 'match_type' in ('exact', 'phrase', 'broad') then x ->> 'match_type' end, x ->> 'status'
  from jsonb_array_elements(coalesce(p_keywords, '[]'::jsonb)) x
  where x ->> 'id' ~ '^[0-9]{1,20}$' and x ->> 'ad_group' ~ '^[0-9]{1,20}$' and x ->> 'campaign' ~ '^[0-9]{1,20}$'
    and char_length(btrim(coalesce(x ->> 'text', ''))) > 0 and x ->> 'status' in ('live', 'paused', 'ended')
  on conflict (account_id, ad_group_external_id, criterion_id) do update set campaign_external_id = excluded.campaign_external_id, text = excluded.text,
                                                                         match_type = excluded.match_type, status = excluded.status, updated_at = now();
  get diagnostics v_kw = row_count;
  if p_keywords is not null then
    update app.ad_platform_keywords k set status = 'ended', updated_at = now()
    where k.account_id = a.id and k.status <> 'ended'
      and not exists (select 1 from jsonb_array_elements(p_keywords) x where x ->> 'id' = k.criterion_id and x ->> 'ad_group' = k.ad_group_external_id);
  end if;
  delete from app.ad_keyword_daily where account_id = a.id and day between p_from and p_to;
  insert into app.ad_keyword_daily (account_id, ad_group_external_id, criterion_id, day, impressions, clicks, spend, conversions)
  select a.id, x ->> 'ad_group', x ->> 'id', (x ->> 'day')::date, greatest(coalesce((x ->> 'impressions')::bigint, 0), 0), greatest(coalesce((x ->> 'clicks')::bigint, 0), 0),
         greatest(round(coalesce((x ->> 'spend')::numeric, 0), 2), 0),
         case when x ->> 'conversions' is not null then greatest(round((x ->> 'conversions')::numeric, 2), 0) end
  from jsonb_array_elements(coalesce(p_daily, '[]'::jsonb)) x
  where x ->> 'id' ~ '^[0-9]{1,20}$' and x ->> 'ad_group' ~ '^[0-9]{1,20}$' and x ->> 'day' ~ '^\d{4}-\d{2}-\d{2}$' and (x ->> 'day')::date between p_from and p_to
  on conflict (account_id, ad_group_external_id, criterion_id, day) do update set impressions = excluded.impressions, clicks = excluded.clicks,
                                                                                spend = excluded.spend, conversions = excluded.conversions;
  get diagnostics v_rows = row_count;
  if p_bidding is not null and jsonb_typeof(p_bidding) = 'array' then
    update app.ad_platform_campaigns pc set bidding = x.bidding, updated_at = now()
    from (select y ->> 'id' id, lower(y ->> 'bidding') bidding from jsonb_array_elements(p_bidding) y
          where y ->> 'id' ~ '^[0-9]{1,20}$' and lower(y ->> 'bidding') ~ '^[a-z0-9_]{1,40}$') x
    where pc.account_id = a.id and pc.external_id = x.id and pc.bidding is distinct from x.bidding;
  end if;
  insert into app.growth_sync_log (source, rows, state, info)
  values (a.provider, v_rows, 'ok', jsonb_build_object('account', a.external_id, 'from', p_from, 'to', p_to, 'keywords', v_kw));
  return jsonb_build_object('keywords', v_kw, 'rows', v_rows);
end $fn$;

-- ===========================================================================
-- 2. the campaign card
-- ===========================================================================
-- A campaign's days, ads and keywords. The figures follow ad_campaigns_get: one's own campaign, or another's with Campaigns ›
-- See reports of others or Edit others (or Global › reports of others).
--   days[]: {day, spend (null: no platform row that day, or the spend is typed, or in several currencies), signups}
--   spend_source: platform | typed | null;  currency: the platform accounts' one currency (null when mixed or none)
--   platforms[]: the platform campaigns it counts as (for the links to them); time_zones: the accounts' when not Oslo
--   ads[] and keywords[]: clicks, spend and conversions in the window; signups only where sessions carry utm_content / utm_term
create function public.ad_campaign_detail(p_campaign uuid, p_days int default 21) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'see');
  v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
  v_others boolean := app.can('campaigns', 'reports_others') or app.can('global', 'reports_others') or app.can('campaigns', 'edit_others');
  c app.ad_campaigns;
  v_days int := least(greatest(coalesce(p_days, 21), 7), 60);
  v_to date := (now() at time zone 'Europe/Oslo')::date - 1;
  v_from date;
  v_sites uuid[];
  v_out jsonb;
begin
  v_from := v_to - v_days + 1;
  select * into c from app.ad_campaigns x where x.id = p_campaign and (not x.is_sample or v_sandbox);
  if c.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not (c.created_by is not distinct from v_me or v_others) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:reports_others';
  end if;
  v_sites := app.growth_sites(c.product);
  with pcs as (
    select pc.account_id, pc.external_id, pc.name, pc.status, pc.bidding, a.provider, a.external_id account, a.currency, a.time_zone
    from app.ad_platform_campaigns pc join app.ad_accounts a on a.id = pc.account_id
    where pc.ad_campaign_id = c.id
  ), cur as (
    select count(distinct p.currency) n, min(p.currency) currency from pcs p
  ), ss as (
    -- the campaign's visits that may count in the window (a signup can finish the day after the visit began)
    select w.id, w.utm from app.web_sessions w
    where w.site_id = any (v_sites) and w.utm ->> 'utm_campaign' = c.utm_campaign and w.day between v_from - 1 and v_to
  ), sg as (
    -- the visits that finished signup in the window, by the day (Oslo) they finished
    select s.id, s.utm, (min(e.at) at time zone 'Europe/Oslo')::date done_on
    from ss s join app.web_events e on e.session_id = s.id and e.name = 'signup_completed'
    group by s.id, s.utm
    having (min(e.at) at time zone 'Europe/Oslo')::date between v_from and v_to
  ), conv as (
    -- does the platforms' tracking template put the ad's id (utm_content) and the keyword (utm_term) on the links?
    select coalesce(bool_or(nullif(s.utm ->> 'utm_content', '') is not null), false) content,
           coalesce(bool_or(nullif(s.utm ->> 'utm_term', '') is not null), false) term
    from ss s
  )
  select jsonb_build_object(
    'id', c.id, 'from', v_from, 'to', v_to, 'days_n', v_days,
    'starts_on', c.starts_on, 'ends_on', c.ends_on,
    'tracked', cardinality(v_sites) > 0 and exists (select 1 from app.web_sessions w where w.site_id = any (v_sites)),
    'spend_source', case when exists (select 1 from pcs) then 'platform'
                         when exists (select 1 from app.marketing_spend ms where ms.campaign = c.utm_campaign) then 'typed' end,
    'currency', case when (select n from cur) = 1 then (select currency from cur) end,
    'time_zones', coalesce((select jsonb_agg(distinct p.time_zone) from pcs p where p.time_zone is not null and p.time_zone <> 'Europe/Oslo'), '[]'::jsonb),
    'utm_content', (select content from conv), 'utm_term', (select term from conv),
    'platforms', coalesce((select jsonb_agg(jsonb_build_object('provider', p.provider, 'account', p.account, 'campaign', p.external_id, 'name', p.name,
                                                               'status', p.status, 'bidding', p.bidding) order by p.status = 'live' desc, p.name) from pcs p), '[]'::jsonb),
    'days', (select jsonb_agg(jsonb_build_object(
               'day', d::date,
               'spend', case when (select n from cur) = 1 then
                          (select sum(x.spend) from app.ad_daily x join pcs p on p.account_id = x.account_id and p.external_id = x.external_id
                           where x.level = 'campaign' and x.day = d::date) end,
               'signups', (select count(*) from sg where sg.done_on = d::date)) order by d)
             from generate_series(v_from, v_to, interval '1 day') d),
    'ads', coalesce((select jsonb_agg(y.o order by y.clicks desc, y.o ->> 'name') from (
        select jsonb_build_object('id', ad.external_id, 'provider', p.provider, 'account', p.account, 'campaign', p.external_id,
                                  'name', coalesce(ad.name, ad.headline, ad.external_id), 'status', ad.status, 'currency', p.currency,
                                  'clicks', coalesce(m.clicks, 0), 'spend', coalesce(m.spend, 0), 'conversions', m.conversions,
                                  'signups', case when (select content from conv) then (select count(*) from sg where sg.utm ->> 'utm_content' = ad.external_id) end) o,
               coalesce(m.clicks, 0) clicks
        from pcs p join app.ad_platform_ads ad on ad.account_id = p.account_id and ad.campaign_external_id = p.external_id
        left join lateral (select sum(d.clicks) clicks, sum(d.spend) spend, sum(d.conversions) conversions from app.ad_daily d
                           where d.account_id = ad.account_id and d.level = 'ad' and d.external_id = ad.external_id and d.day between v_from and v_to) m on true
        where ad.status = 'live' or coalesce(m.clicks, 0) > 0
        order by coalesce(m.clicks, 0) desc limit 20) y), '[]'::jsonb),
    'keywords', coalesce((select jsonb_agg(y.o order by y.clicks desc, y.o ->> 'name') from (
        select jsonb_build_object('id', k.criterion_id, 'ad_group', k.ad_group_external_id, 'provider', p.provider, 'account', p.account, 'campaign', p.external_id,
                                  'name', k.text, 'match_type', k.match_type, 'status', k.status, 'currency', p.currency,
                                  'clicks', coalesce(m.clicks, 0), 'spend', coalesce(m.spend, 0), 'conversions', m.conversions,
                                  'signups', case when (select term from conv) then (select count(*) from sg where lower(btrim(sg.utm ->> 'utm_term')) = lower(k.text)) end) o,
               coalesce(m.clicks, 0) clicks
        from pcs p join app.ad_platform_keywords k on k.account_id = p.account_id and k.campaign_external_id = p.external_id
        left join lateral (select sum(d.clicks) clicks, sum(d.spend) spend, sum(d.conversions) conversions from app.ad_keyword_daily d
                           where d.account_id = k.account_id and d.ad_group_external_id = k.ad_group_external_id and d.criterion_id = k.criterion_id
                             and d.day between v_from and v_to) m on true
        where k.status = 'live' or coalesce(m.clicks, 0) > 0
        order by coalesce(m.clicks, 0) desc limit 20) y), '[]'::jsonb))
  into v_out;
  return v_out;
end $fn$;

-- ===========================================================================
-- 3. Email and automation
-- ===========================================================================
-- the send window of a simple sequence (none: each email goes when its step is reached). Derived from the application's
-- best send time by simple_sequence_send_window; the engine reads it at every email step (sequence_send_hold).
create table app.sequence_send_windows (
  workflow_id uuid primary key references app.workflows (id) on delete cascade,
  days        smallint[] not null check (cardinality(days) between 1 and 7 and days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  hour        smallint not null check (hour between 0 and 23),
  product     text references app.products (key) on delete set null,
  set_by      uuid references app.admins (id) on delete set null,
  set_at      timestamptz not null default now()
);
alter table app.sequence_send_windows enable row level security;
revoke all on app.sequence_send_windows from public, anon, authenticated;

-- is a moment inside a send window (ISO weekdays and an hour, Europe/Oslo)?
create function app.send_window_open(p_at timestamptz, p_days smallint[], p_hour int) returns boolean
  language sql stable set search_path = ''
as $fn$
  select extract(isodow from p_at at time zone 'Europe/Oslo')::smallint = any (p_days)
     and extract(hour from p_at at time zone 'Europe/Oslo')::int = p_hour
$fn$;

-- the window's next slot after a moment: the hour's start on the next day it names, in Oslo's clock (08:00 stays 08:00
-- across a change of clock)
create function app.send_window_next(p_from timestamptz, p_days smallint[], p_hour int) returns timestamptz
  language sql stable set search_path = ''
as $fn$
  select min(x.t) from (
    select (d + make_interval(hours => p_hour)) at time zone 'Europe/Oslo' t
    from generate_series((p_from at time zone 'Europe/Oslo')::date::timestamp, (p_from at time zone 'Europe/Oslo')::date::timestamp + interval '7 days', interval '1 day') d
    where extract(isodow from d)::smallint = any (p_days)) x
  where x.t > p_from
$fn$;

-- the engine at an email step of a run: null to send now; else {until, cursor}: the next slot, and the step to go on from
-- then — the «stop when» check right before the email when there is one, so it is asked again at the slot
create function app.sequence_send_hold(p_run app.workflow_runs, p_key text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare s app.sequence_send_windows; v_prev text;
begin
  select * into s from app.sequence_send_windows where workflow_id = p_run.workflow_id;
  if s.workflow_id is null or app.send_window_open(now(), s.days, s.hour) then return null; end if;
  select n.k into v_prev
  from app.workflow_versions v cross join lateral jsonb_each(v.flat) n(k, x)
  where v.workflow_id = p_run.workflow_id and v.version = p_run.version and n.k ~ '^x[0-9]+$' and jsonb_typeof(n.x) = 'object'
    and n.x ->> 'kind' = 'condition' and n.x ->> 'next' = p_key
  limit 1;
  return jsonb_build_object('until', app.send_window_next(now(), s.days, s.hour), 'cursor', coalesce(v_prev, p_key));
end $fn$;

-- wf_step's campaign_action learns the send window, after its right check and before the person is queued
do $$
declare src text; v_anchor text := $a$      if not app.can('campaigns', 'workflows') then raise exception 'forbidden'; end if;$a$;
begin
  src := pg_get_functiondef('app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)'::regprocedure);
  if (length(src) - length(replace(src, v_anchor, ''))) / length(v_anchor) <> 1 or position('v_facts jsonb' in src) = 0 then
    raise exception 'wf_step has changed shape: the send window could not be added';
  end if;
  execute replace(src, v_anchor, v_anchor || $r$
      -- a sequence with a send window (0083): outside it the run waits for the next slot, then asks «stop when» again
      v_facts := app.sequence_send_hold(p_run, p_key);
      if v_facts is not null then
        update app.workflow_runs set state = 'waiting', cursor = v_facts ->> 'cursor', resume_at = (v_facts ->> 'until')::timestamptz where id = p_run.id;
        update app.workflow_run_steps set state = 'succeeded', finished_at = now(), output = jsonb_build_object('held_until', v_facts ->> 'until') where id = p_step;
        return null;
      end if;$r$);
end $$;

-- each delivered send of the application's email in the window, by send weekday and hour (Europe/Oslo): delivered and
-- opened (human opens; a prefetch is not an open, 0060). Only campaigns that track opens, and whose reports the caller may see.
create function app.email_send_cells(p_product text, p_days int) returns table (dow int, hour int, delivered bigint, opened bigint)
  language sql stable security definer set search_path = ''
as $fn$
  select extract(isodow from r.sent_at at time zone 'Europe/Oslo')::int, extract(hour from r.sent_at at time zone 'Europe/Oslo')::int,
         count(*), count(r.first_open_at)
  from app.campaign_recipients r join app.campaigns c on c.id = r.campaign_id
  where c.product = p_product and not c.is_sample and not r.is_sample and c.tracking and app.setting('tracking') <> 'off'
    and r.delivered_at is not null and r.sent_at > now() - make_interval(days => p_days) and app.campaign_reports_ok(c)
  group by 1, 2
$fn$;

-- the best send time: the cell with the highest open rate among those with at least 20 delivered (ties: more delivered,
-- then the earlier weekday and hour); the window is that hour on every weekday whose cell at it has 20 delivered and an open
-- rate within five points of the best (V-V3G-12). Null while no cell has 20 delivered.
create function app.email_best_time(p_product text, p_days int) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare b record; v_days int[];
begin
  select x.* into b from app.email_send_cells(p_product, p_days) x where x.delivered >= 20
  order by x.opened::numeric / x.delivered desc, x.delivered desc, x.dow, x.hour limit 1;
  if b.dow is null then return null; end if;
  select array_agg(x.dow order by x.dow) into v_days from app.email_send_cells(p_product, p_days) x
  where x.hour = b.hour and x.delivered >= 20 and x.opened::numeric / x.delivered >= b.opened::numeric / b.delivered - 0.05;
  return jsonb_build_object('dow', b.dow, 'hour', b.hour, 'delivered', b.delivered, 'opened', b.opened, 'days', to_jsonb(v_days));
end $fn$;

-- the heatmap: Campaigns › See; the application's cells over the window, the minimum per cell and the best time
create function public.email_send_times(p_product text, p_days int default 90) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_days int := least(greatest(coalesce(p_days, 90), 30), 180);
begin
  if not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  return jsonb_build_object(
    'days', v_days, 'min', 20,
    'cells', coalesce((select jsonb_agg(jsonb_build_object('dow', x.dow, 'hour', x.hour, 'delivered', x.delivered, 'opened', x.opened) order by x.dow, x.hour)
                       from app.email_send_cells(p_product, v_days) x), '[]'::jsonb),
    'best', app.email_best_time(p_product, v_days));
end $fn$;

-- one email's sends in the window: sent, delivered, unique human opens and clicks (null when it does not track), unsubscribes,
-- the delivered sends whose organisation had uploaded its employee list before the send (the «Add condition» tip; a CRM
-- join, no respondent data), and signups: the tracker's visits with the email's utm_campaign that finished signup in it
create function app.sequence_email_figures(c app.campaigns, p_t0 timestamptz) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'tracking', c.tracking and app.setting('tracking') <> 'off',
    'sent', count(*) filter (where r.state not in ('queued', 'skipped')),
    'delivered', count(r.delivered_at),
    'opens', case when c.tracking and app.setting('tracking') <> 'off' then count(r.first_open_at) filter (where r.delivered_at is not null) end,
    'clicks', case when c.tracking and app.setting('tracking') <> 'off' then count(r.first_click_at) filter (where r.delivered_at is not null) end,
    'unsubscribed', count(r.unsubscribed_at) filter (where r.delivered_at is not null),
    'with_org', count(*) filter (where r.delivered_at is not null and p.organization_id is not null),
    'past_employees', count(*) filter (where r.delivered_at is not null and p.organization_id is not null and exists (
        select 1 from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        join app.activation_milestones m on m.product = ap.product and m.tenant_id = ap.tenant_id
        where o.id = p.organization_id and m.key = 'employees_uploaded' and m.reached_at <= r.sent_at)),
    'signups', (select count(distinct w.id) from app.web_sessions w join app.web_events e on e.session_id = w.id and e.name = 'signup_completed'
                where w.utm ->> 'utm_campaign' = c.utm_campaign and w.started_at > p_t0 - interval '1 day' and e.at > p_t0))
  from app.campaign_recipients r left join app.people p on p.id = r.person_id
  where r.campaign_id = c.id and r.sent_at > p_t0 and not r.is_sample
$fn$;

-- Results per step: every staff member reads the list of sequences (simple_sequences_get); an email's figures need its
-- reports (one's own, or Campaigns › See reports of others / Edit others), else they are null
create function public.simple_sequence_results(p_id uuid, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); w app.workflows; v_days int := least(greatest(coalesce(p_days, 30), 7), 90); v_t0 timestamptz;
begin
  v_t0 := now() - make_interval(days => v_days);
  select * into w from app.workflows x where x.id = p_id and x.deleted_at is null and x.kind = 'workflow' and x.options ? 'simple';
  if w.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object(
    'id', w.id, 'days', v_days,
    'send_window', (select jsonb_build_object('days', to_jsonb(s.days), 'hour', s.hour, 'set_at', s.set_at) from app.sequence_send_windows s where s.workflow_id = w.id),
    'emails', coalesce((select jsonb_agg(q.o order by q.n) from (
        select t.n, jsonb_build_object('step', t.n - 1, 'campaign_id', c.id, 'subject', t.x ->> 'text',
                                       'figures', case when c.id is not null and app.campaign_reports_ok(c) then app.sequence_email_figures(c, v_t0) end) o
        from jsonb_array_elements(w.options -> 'simple' -> 'steps') with ordinality t(x, n)
        left join app.campaigns c on c.id::text = t.x ->> 'campaign_id'
        where t.x ->> 'kind' = 'email') q), '[]'::jsonb));
end $fn$;

-- «Send all steps at the best time» on (the application's best window now, from email_best_time) or off. The rights are
-- the editor's: the trigger's scope › Manage workflows and Campaigns › Manage workflows; another person's sequence needs
-- Global › Configure. Refused with no_best_time while no cell has enough sends.
create function public.simple_sequence_send_window(p_id uuid, p_product text, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); w app.workflows; v_best jsonb; v_days smallint[];
begin
  select * into w from app.workflows x where x.id = p_id and x.deleted_at is null and x.kind = 'workflow' and x.options ? 'simple' for update;
  if w.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if w.owner_id is distinct from v_me and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  perform app.require(coalesce((select e.scope from app.entities e where e.key = w.trigger_config ->> 'entity'), 'deals'), 'workflows');
  perform app.require('campaigns', 'workflows');
  if p_on is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'on'; end if;
  if p_on then
    if not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
    v_best := app.email_best_time(p_product, 90);
    if v_best is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'no_best_time'; end if;
    v_days := array(select x::smallint from jsonb_array_elements_text(v_best -> 'days') x);
    insert into app.sequence_send_windows (workflow_id, days, hour, product, set_by, set_at)
    values (w.id, v_days, (v_best ->> 'hour')::smallint, p_product, v_me, now())
    on conflict (workflow_id) do update set days = excluded.days, hour = excluded.hour, product = excluded.product, set_by = excluded.set_by, set_at = now();
  else
    delete from app.sequence_send_windows where workflow_id = w.id;
  end if;
  perform app.log('sequence.send_window_set', 'workflow', w.id::text,
                  jsonb_build_object('on', p_on, 'days', case when p_on then to_jsonb(v_days) end, 'hour', case when p_on then v_best -> 'hour' end));
  return jsonb_build_object('id', w.id,
    'send_window', (select jsonb_build_object('days', to_jsonb(s.days), 'hour', s.hour, 'set_at', s.set_at) from app.sequence_send_windows s where s.workflow_id = w.id));
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
do $$
declare f text;
begin
  foreach f in array array['app.send_window_open(timestamptz, smallint[], int)', 'app.send_window_next(timestamptz, smallint[], int)',
                           'app.sequence_send_hold(app.workflow_runs, text)', 'app.email_send_cells(text, int)', 'app.email_best_time(text, int)',
                           'app.sequence_email_figures(app.campaigns, timestamptz)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.ad_campaign_detail(uuid, int)', 'public.email_send_times(text, int)', 'public.simple_sequence_results(uuid, int)',
                           'public.simple_sequence_send_window(uuid, text, boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  revoke all on function public.worker_ads_keywords(uuid, date, date, jsonb, jsonb, jsonb) from public, anon, authenticated;
  grant execute on function public.worker_ads_keywords(uuid, date, date, jsonb, jsonb, jsonb) to service_role;
end $$;
