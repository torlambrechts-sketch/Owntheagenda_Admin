-- 0076_growth_playbook.sql — Growth › Marketing campaigns and Email and automation, the playbook (GrowthPlaybook.dc.html of
-- 11 Oct 2026; docs/crm-enrichment/growth-v2-gap.md, deviations/growth-v2.md V-GR2-33 onwards).
--
-- Each view reads what Sentral holds and says what it does not:
--   Outcomes and attribution  spend (typed in per month), the tracker's signups per channel, accounts and paying customers by
--                             the product's first or last touch, MRR; journeys from first to last touch
--   Budget planner            a budget per channel and month (marketing_budgets), this month's spend against it, the cost
--                             per paying customer observed over 90 days, a suggested move and a scenario
--   Experiments               hypotheses with ICE, Backlog → Ready → Running → Done (growth_experiments)
--   Calendar and offers       the year's ad and email campaigns, and blackout periods (growth_blackouts)
--   Trial and abandoned signup  trial conversion, time to first survey, abandoned signups, the flows that start from a trial
--   Flow library              every workflow and sequence with its state, steps and 90 days of email figures
--   Deliverability            30 days of sends, bounces, complaints and unsubscribes, the suppression list, and what the
--                             engine does with email engagement
-- Audiences reads the CRM lists (segments_get, 0037) and the sender domains come from sender_domains_get (0037).
--
-- Nothing here is about a respondent; campaign figures are counts.

-- ===========================================================================
-- 1. What people record
-- ===========================================================================
-- a channel's budget for a month, per application
create table app.marketing_budgets (
  product    text not null references app.products (key) on delete cascade,
  month      date not null check (month = date_trunc('month', month)::date),
  channel    text not null check (channel in ('paid_search', 'paid_social', 'email', 'social', 'partner', 'organic_search')),
  amount     numeric(14, 2) not null check (amount >= 0),
  updated_by uuid references app.admins (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (product, month, channel)
);
alter table app.marketing_budgets enable row level security;
revoke all on app.marketing_budgets from public, anon, authenticated;

create table app.growth_experiments (
  id          uuid primary key default gen_random_uuid(),
  product     text not null references app.products (key) on delete cascade,
  hypothesis  text not null check (char_length(btrim(hypothesis)) between 3 and 300),
  area        text not null check (area in ('signup', 'landing_page', 'pricing', 'email', 'ads', 'content', 'referral', 'other')),
  impact      int not null check (impact between 1 and 10),
  confidence  int not null check (confidence between 1 and 10),
  ease        int not null check (ease between 1 and 10),
  stage       text not null default 'backlog' check (stage in ('backlog', 'ready', 'running', 'done')),
  outcome     text check (outcome is null or outcome in ('win', 'no_effect', 'loss')),
  result_note text check (result_note is null or char_length(result_note) <= 200),
  owner_id    uuid references app.admins (id) on delete set null,
  started_at  timestamptz,
  ended_at    timestamptz,
  archived_at timestamptz,
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check ((stage = 'done') = (outcome is not null))
);
alter table app.growth_experiments enable row level security;
revoke all on app.growth_experiments from public, anon, authenticated;
create index growth_experiments_product on app.growth_experiments (product, stage) where archived_at is null;

-- periods when nothing should go out (fellesferie, Christmas)
create table app.growth_blackouts (
  id         uuid primary key default gen_random_uuid(),
  product    text not null references app.products (key) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  starts_on  date not null,
  ends_on    date not null,
  created_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on and ends_on - starts_on <= 366)
);
alter table app.growth_blackouts enable row level security;
revoke all on app.growth_blackouts from public, anon, authenticated;

-- ===========================================================================
-- 2. Helpers
-- ===========================================================================
-- the touch an account is attributed to under a model: first touch, or the last one the product reported
create function app.account_touch(p_attribution jsonb, p_model text) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  select case when p_model = 'last' then coalesce(p_attribution -> 'last_touch', p_attribution -> 'first_touch', p_attribution, '{}'::jsonb)
              else coalesce(p_attribution -> 'first_touch', p_attribution, '{}'::jsonb) end
$fn$;

-- a month's spend row's channel: as typed, or where its campaign's utm sends visits
create function app.spend_channel(p_typed text, p_source text, p_medium text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(nullif(p_typed, ''), app.channel_of(jsonb_build_object('utm_source', p_source, 'utm_medium', p_medium)))
$fn$;

-- revenue per paying account now (MRR ÷ paying, the latest snapshot), null without paying accounts
create function app.growth_arpa(p_product text) returns numeric
  language sql stable security definer set search_path = ''
as $fn$
  select round(sum(md.mrr) / nullif(sum(md.paying), 0), 2) from app.mrr_daily md
  where md.day = (select max(day) from app.mrr_daily) and app.in_scope(p_product, md.product)
$fn$;

-- ===========================================================================
-- 3. Outcomes and attribution
-- ===========================================================================
create function public.growth_outcomes(p_product text default null, p_model text default 'first') returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'));
  v_model text := case when p_model = 'last' then 'last' else 'first' end;
  v_attr boolean := exists (select 1 from app.account_products ap where app.in_scope(nullif(p_product, 'all'), ap.product) and app.has_source(ap.attribution));
  v_t0 timestamptz := now() - interval '90 days';
begin
  return jsonb_build_object(
    'model', v_model, 'days', 90, 'attributed', v_attr, 'arpa', app.growth_arpa(v_product),
    'tracked_since', (select min(x.started_at) from app.web_sessions x where x.site_id = any (v_sites)),
    'channels', coalesce((
      with sp as (
        select app.spend_channel(ms.channel, c.utm_source, c.utm_medium) channel, sum(ms.amount * app.month_share(ms.month, v_t0, now())) amount
        from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
        where ms.currency = 'NOK' and app.in_scope(v_product, c.product)
          and ms.month::timestamp at time zone 'Europe/Oslo' < now() and (ms.month + interval '1 month')::timestamp at time zone 'Europe/Oslo' > v_t0
        group by 1
      ), sg as (
        select coalesce(x.channel, 'direct') channel, count(*) n from app.web_sessions x
        where x.site_id = any (v_sites) and x.started_at > v_t0 and exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_completed')
        group by 1
      ), ac as (
        select app.channel_of(app.account_touch(ap.attribution, v_model)) channel, count(*) n from app.account_products ap
        where v_attr and app.in_scope(v_product, ap.product) and ap.created_at > v_t0
        group by 1
      ), pa as (
        select app.channel_of(app.account_touch(ap.attribution, v_model)) channel, count(*) n, sum(app.sub_mrr(sb)) mrr
        from app.subscriptions sb join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
        where v_attr and app.in_scope(v_product, sb.product) and sb.confirmed_at > v_t0
        group by 1
      ), ch as (select channel from sp union select channel from sg union select channel from ac union select channel from pa)
      select jsonb_agg(jsonb_build_object('channel', ch.channel, 'spend', round(sp.amount), 'signups', sg.n,
                                          'accounts', case when v_attr then coalesce(ac.n, 0) end, 'paying', case when v_attr then coalesce(pa.n, 0) end,
                                          'mrr', case when v_attr then coalesce(pa.mrr, 0) end)
                       order by coalesce(pa.n, 0) desc, coalesce(sg.n, 0) desc, ch.channel)
      from ch left join sp using (channel) left join sg using (channel) left join ac using (channel) left join pa using (channel)), '[]'::jsonb),
    -- the paths of paying accounts: their first touch, their last if it differs, and the days from signup to paying
    'journeys', case when v_attr then coalesce((
      select jsonb_agg(jsonb_build_object('first', j.f, 'last', j.l, 'paying', j.n, 'days', j.days) order by j.n desc, j.f, j.l)
      from (select app.channel_of(app.account_touch(ap.attribution, 'first')) f, app.channel_of(app.account_touch(ap.attribution, 'last')) l, count(*) n,
                   round(percentile_cont(0.5) within group (order by extract(epoch from sb.confirmed_at - ap.created_at) / 86400)::numeric, 0) days
            from app.subscriptions sb join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
            where app.in_scope(v_product, sb.product) and sb.confirmed_at > v_t0 and app.has_source(ap.attribution)
            group by 1, 2 order by 3 desc limit 6) j), '[]'::jsonb) end);
end $fn$;

-- ===========================================================================
-- 4. Budget planner
-- ===========================================================================
create function public.growth_budget(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_today date := (now() at time zone 'Europe/Oslo')::date;
  v_month date := date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date;
  v_attr boolean := exists (select 1 from app.account_products ap where app.in_scope(nullif(p_product, 'all'), ap.product) and app.has_source(ap.attribution));
  v_t0 timestamptz := now() - interval '90 days';
begin
  if v_product is null or not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  return jsonb_build_object(
    'month', v_month, 'day', v_today - v_month + 1, 'days', ((v_month + interval '1 month')::date - v_month),
    'attributed', v_attr, 'arpa', app.growth_arpa(v_product),
    -- this month's last «Apply move», so the suggestion it answered shows as applied
    'last_move', (select jsonb_build_object('from', a.detail ->> 'from', 'to', a.detail ->> 'to', 'amount', (a.detail ->> 'amount')::numeric, 'at', a.at)
                  from app.audit a
                  where a.action = 'growth.budget_moved' and a.target_type = 'product' and a.target_id = v_product
                    and a.at >= v_month::timestamp at time zone 'Europe/Oslo'
                  order by a.at desc limit 1),
    'rows', (
      with chs(channel, ord) as (values ('paid_search', 1), ('paid_social', 2), ('email', 3), ('social', 4), ('partner', 5), ('organic_search', 6)),
      sp as (
        select app.spend_channel(ms.channel, c.utm_source, c.utm_medium) channel,
               sum(ms.amount) filter (where ms.month = v_month) month_spend,
               sum(ms.amount * app.month_share(ms.month, v_t0, now())) spend90
        from app.marketing_spend ms left join app.ad_campaigns c on c.utm_campaign = ms.campaign
        where ms.currency = 'NOK' and app.in_scope(v_product, c.product) and ms.month >= (v_t0 at time zone 'Europe/Oslo')::date - 31
        group by 1
      ), pa as (
        select app.channel_of(app.account_touch(ap.attribution, 'first')) channel, count(*) n
        from app.subscriptions sb join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
        where v_attr and app.in_scope(v_product, sb.product) and sb.confirmed_at > v_t0
        group by 1
      )
      select jsonb_agg(jsonb_build_object('channel', chs.channel,
               'budget', (select b.amount from app.marketing_budgets b where b.product = v_product and b.month = v_month and b.channel = chs.channel),
               'spent', coalesce(round(sp.month_spend), 0), 'spend90', round(sp.spend90),
               'paying90', case when v_attr then coalesce(pa.n, 0) end) order by chs.ord)
      from chs left join sp using (channel) left join pa using (channel)));
end $fn$;

-- a channel's budget for the current month; nothing removes it
create function public.marketing_budget_set(p_product text, p_channel text, p_amount numeric) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'reports_others'); v_month date := date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date;
begin
  if p_product is null or not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if p_channel is null or p_channel not in ('paid_search', 'paid_social', 'email', 'social', 'partner', 'organic_search') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channel';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 100000000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'amount'; end if;
  insert into app.marketing_budgets (product, month, channel, amount, updated_by) values (p_product, v_month, p_channel, round(p_amount, 2), v_me)
  on conflict (product, month, channel) do update set amount = excluded.amount, updated_by = excluded.updated_by, updated_at = now();
  perform app.log('growth.budget_set', 'product', p_product, jsonb_build_object('channel', p_channel, 'amount', round(p_amount, 2)));
  return jsonb_build_object('channel', p_channel, 'amount', round(p_amount, 2));
end $fn$;

-- «Apply move»: part of one channel's budget to another, in one step
create function public.marketing_budget_move(p_product text, p_from text, p_to text, p_amount numeric) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'reports_others'); v_month date := date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date; v_has numeric;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'channel'; end if;
  select amount into v_has from app.marketing_budgets where product = p_product and month = v_month and channel = p_from for update;
  if v_has is null or p_amount is null or p_amount <= 0 or p_amount > v_has then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'amount'; end if;
  perform public.marketing_budget_set(p_product, p_from, v_has - p_amount);
  perform public.marketing_budget_set(p_product, p_to, coalesce((select amount from app.marketing_budgets where product = p_product and month = v_month and channel = p_to), 0) + p_amount);
  perform app.log('growth.budget_moved', 'product', p_product, jsonb_build_object('from', p_from, 'to', p_to, 'amount', round(p_amount, 2)));
  return jsonb_build_object('moved', round(p_amount, 2));
end $fn$;

-- ===========================================================================
-- 5. Experiments
-- ===========================================================================
create function public.growth_experiments_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see');
begin
  return jsonb_build_object(
    'running', (select count(*) from app.growth_experiments x where x.product = p_product and x.archived_at is null and x.stage = 'running'),
    'called_30', (select count(*) from app.growth_experiments x where x.product = p_product and x.ended_at > now() - interval '30 days'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'hypothesis', x.hypothesis, 'area', x.area, 'impact', x.impact, 'confidence', x.confidence,
                                                           'ease', x.ease, 'stage', x.stage, 'outcome', x.outcome, 'note', x.result_note,
                                                           'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = coalesce(x.owner_id, x.created_by)),
                                                           'started_at', x.started_at, 'ended_at', x.ended_at, 'created_at', x.created_at)
                                        order by (x.impact + x.confidence + x.ease) desc, x.created_at)
                       from app.growth_experiments x where x.product = p_product and x.archived_at is null), '[]'::jsonb));
end $fn$;

create function public.growth_experiment_add(p_product text, p_hypothesis text, p_area text, p_impact int, p_confidence int, p_ease int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); v_id uuid; v_h text := btrim(regexp_replace(coalesce(p_hypothesis, ''), '\s+', ' ', 'g'));
begin
  if p_product is null or not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(v_h) not between 3 and 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hypothesis'; end if;
  if p_area is null or p_area not in ('signup', 'landing_page', 'pricing', 'email', 'ads', 'content', 'referral', 'other') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'area';
  end if;
  if p_impact is null or p_confidence is null or p_ease is null or least(p_impact, p_confidence, p_ease) < 1 or greatest(p_impact, p_confidence, p_ease) > 10 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ice';
  end if;
  insert into app.growth_experiments (product, hypothesis, area, impact, confidence, ease, owner_id, created_by)
  values (p_product, v_h, p_area, p_impact, p_confidence, p_ease, v_me, v_me) returning id into v_id;
  perform app.log('growth.experiment_added', 'product', p_product, jsonb_build_object('area', p_area));
  return jsonb_build_object('id', v_id);
end $fn$;

-- ← and →: Backlog, Ready, Running; going back from Done reopens it
create function public.growth_experiment_move(p_id uuid, p_stage text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); x app.growth_experiments;
begin
  if p_stage is null or p_stage not in ('backlog', 'ready', 'running') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage'; end if;
  select * into x from app.growth_experiments where id = p_id and archived_at is null for update;
  if x.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.growth_experiments
     set stage = p_stage, outcome = null, result_note = null, ended_at = null, updated_at = now(),
         started_at = case when p_stage = 'running' then coalesce(started_at, now()) when p_stage in ('backlog', 'ready') then null else started_at end
   where id = p_id;
  return jsonb_build_object('stage', p_stage);
end $fn$;

-- «Call result»: Win, No effect or Loss, with a line on what was seen
create function public.growth_experiment_call(p_id uuid, p_outcome text, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); x app.growth_experiments; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if p_outcome is null or p_outcome not in ('win', 'no_effect', 'loss') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'outcome'; end if;
  if char_length(v_note) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'note'; end if;
  select * into x from app.growth_experiments where id = p_id and archived_at is null for update;
  if x.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if x.stage <> 'running' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_running'; end if;
  update app.growth_experiments set stage = 'done', outcome = p_outcome, result_note = v_note, ended_at = now(), updated_at = now() where id = p_id;
  perform app.log('growth.experiment_called', 'product', x.product, jsonb_build_object('outcome', p_outcome));
  return jsonb_build_object('outcome', p_outcome);
end $fn$;

create function public.growth_experiment_archive(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add');
begin
  update app.growth_experiments set archived_at = now(), updated_at = now() where id = p_id and archived_at is null and stage = 'done';
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('archived', true);
end $fn$;

-- ===========================================================================
-- 6. Calendar
-- ===========================================================================
create function public.growth_calendar(p_product text, p_year int default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'see');
  v_year int := coalesce(p_year, extract(year from (now() at time zone 'Europe/Oslo'))::int);
  v_from date; v_to date;
begin
  if v_year not between 2020 and 2100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'year'; end if;
  v_from := make_date(v_year, 1, 1); v_to := make_date(v_year, 12, 31);
  return jsonb_build_object(
    'year', v_year, 'today', (now() at time zone 'Europe/Oslo')::date,
    'ads', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'channel', c.channel, 'from', coalesce(c.starts_on, c.created_at::date),
                                                         'to', coalesce(c.ends_on, greatest(coalesce(c.starts_on, c.created_at::date), (now() at time zone 'Europe/Oslo')::date)),
                                                         'state', app.ad_state(c)) order by c.starts_on nulls last, c.name)
                     from app.ad_campaigns c
                     where c.product = p_product and not c.is_sample
                       and coalesce(c.starts_on, c.created_at::date) <= v_to and coalesce(c.ends_on, (now() at time zone 'Europe/Oslo')::date) >= v_from), '[]'::jsonb),
    'emails', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status,
                                                            'on', (coalesce(c.sent_at, c.started_at, c.scheduled_at) at time zone 'Europe/Oslo')::date) order by coalesce(c.sent_at, c.started_at, c.scheduled_at))
                        from app.campaigns c
                        where c.deleted_at is null and not c.is_sample and c.type <> 'automated' and c.product = p_product
                          and (coalesce(c.sent_at, c.started_at, c.scheduled_at) at time zone 'Europe/Oslo')::date between v_from and v_to), '[]'::jsonb),
    'blackouts', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'from', b.starts_on, 'to', b.ends_on) order by b.starts_on)
                           from app.growth_blackouts b where b.product = p_product and b.starts_on <= v_to and b.ends_on >= v_from), '[]'::jsonb));
end $fn$;

create function public.growth_blackout_add(p_product text, p_name text, p_from date, p_to date) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); v_id uuid; v_name text := btrim(coalesce(p_name, ''));
begin
  if p_product is null or not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  if char_length(v_name) not between 1 and 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dates'; end if;
  insert into app.growth_blackouts (product, name, starts_on, ends_on, created_by) values (p_product, v_name, p_from, p_to, v_me) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.growth_blackout_remove(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add');
begin
  delete from app.growth_blackouts where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('removed', true);
end $fn$;

-- ===========================================================================
-- 7. Trial and abandoned signup
-- ===========================================================================
-- a workflow's steps in order, as kind and what they carry (the name of the campaign or template an email step sends, a
-- delay's length), without the content
create function app.flow_steps(p_wf uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('kind', s.v ->> 'kind',
           'email', coalesce((select c.name from app.campaigns c where c.id::text = s.v -> 'config' ->> 'campaign_id'),
                             (select t.name from app.email_templates t where t.id::text = s.v -> 'config' ->> 'template_id')),
           'amount', case when s.v ->> 'kind' = 'delay' and (s.v -> 'config' ->> 'amount') ~ '^\d{1,4}$' then (s.v -> 'config' ->> 'amount')::int end,
           'unit', case when s.v ->> 'kind' = 'delay' and s.v -> 'config' ->> 'unit' in ('minutes', 'hours', 'days', 'weeks') then s.v -> 'config' ->> 'unit' end) order by s.o), '[]'::jsonb)
  from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
  cross join lateral jsonb_array_elements(coalesce(v.graph -> 'steps', '[]'::jsonb)) with ordinality s(v, o)
  where w.id = p_wf
$fn$;

-- the automated campaigns a workflow sends: its campaign steps, and a simple sequence's email steps
create function app.flow_campaigns(p_wf uuid) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select (n.v -> 'config' ->> 'campaign_id')::uuid id
    from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
    cross join lateral jsonb_each(v.flat) n(k, v)
    where w.id = p_wf and n.v ->> 'kind' = 'campaign_action' and (n.v -> 'config' ->> 'campaign_id') ~ '^[0-9a-f-]{36}$'
    union
    select (s ->> 'campaign_id')::uuid from app.workflows w cross join lateral jsonb_array_elements(coalesce(w.options -> 'simple' -> 'steps', '[]'::jsonb)) s
    where w.id = p_wf and s ->> 'kind' = 'email' and (s ->> 'campaign_id') ~ '^[0-9a-f-]{36}$'
  ) x
$fn$;

create function public.growth_trial(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  v_product text := nullif(p_product, 'all');
  v_sites uuid[] := app.growth_sites(nullif(p_product, 'all'));
begin
  return jsonb_build_object(
    -- trials that ended in the window, and how many of them became paying
    'trials', (select jsonb_build_object(
        'ended', count(*) filter (where sb.trial_ends_at > now() - interval '90 days'),
        'converted', count(*) filter (where sb.trial_ends_at > now() - interval '90 days' and sb.confirmed_at is not null),
        'ended_prev', count(*) filter (where sb.trial_ends_at <= now() - interval '90 days'),
        'converted_prev', count(*) filter (where sb.trial_ends_at <= now() - interval '90 days' and sb.confirmed_at is not null))
      from app.subscriptions sb
      where app.in_scope(v_product, sb.product) and sb.trial_started_at is not null and sb.trial_ends_at <= now() and sb.trial_ends_at > now() - interval '180 days'),
    -- days from the account to its first survey (median), for accounts started in the window
    'first_survey', (select jsonb_build_object(
        'days', round((percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - ap.created_at) / 86400) filter (where ap.created_at > now() - interval '90 days'))::numeric, 1),
        'days_prev', round((percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - ap.created_at) / 86400) filter (where ap.created_at <= now() - interval '90 days'))::numeric, 1),
        'accounts', count(*) filter (where ap.created_at > now() - interval '90 days'))
      from app.account_products ap join app.activation_milestones m on m.product = ap.product and m.tenant_id = ap.tenant_id and m.key = 'survey_sent'
      where app.in_scope(v_product, ap.product) and ap.created_at > now() - interval '180 days' and m.reached_at >= ap.created_at),
    -- the tracker's visits that began the signup and did not finish it
    'abandoned', (select jsonb_build_object(
        'n', count(*) filter (where x.started_at > now() - interval '30 days'),
        'n_prev', count(*) filter (where x.started_at <= now() - interval '30 days'))
      from app.web_sessions x
      where x.site_id = any (v_sites) and x.started_at > now() - interval '60 days'
        and exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_started')
        and not exists (select 1 from app.web_events e where e.session_id = x.id and e.name = 'signup_completed')),
    'tracked_since', (select min(x.started_at) from app.web_sessions x where x.site_id = any (v_sites)),
    -- the flows that start from what a trial does in the product
    'flows', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'kind', w.kind, 'state', w.state, 'activated', w.activated_at is not null,
                                                           'trigger', w.trigger_config ->> 'kind', 'trigger_data', w.trigger_config -> 'data',
                                                           'steps', app.flow_steps(w.id),
                                                           'in_flow', (select count(*) from app.workflow_runs r where r.workflow_id = w.id and r.state in ('running', 'waiting')),
                                                           'completed_90', (select count(*) from app.workflow_runs r where r.workflow_id = w.id and r.state = 'completed' and r.finished_at > now() - interval '90 days'))
                                        order by w.state = 'active' desc, w.name)
                       from app.workflows w
                       where w.deleted_at is null and not w.is_sample and w.kind <> 'assignment' and w.trigger_type = 'product_event'
                         and w.trigger_config ->> 'kind' in ('org.created', 'milestone.reached', 'billing.changed')), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- 8. Flow library
-- ===========================================================================
create function public.growth_flows() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see');
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', w.id, 'name', w.name, 'description', w.description, 'kind', w.kind, 'state', w.state, 'activated', w.activated_at is not null,
      'trigger_type', w.trigger_type, 'trigger', coalesce(w.trigger_config ->> 'kind', w.trigger_config ->> 'event', w.trigger_config ->> 'date'),
      'simple', w.options ? 'simple',
      'steps', coalesce(nullif((select count(*) from app.workflow_versions v cross join lateral jsonb_object_keys(v.flat) k
                                where v.workflow_id = w.id and v.version = w.current_version and k <> '_start'), 0),
                        jsonb_array_length(coalesce(w.options -> 'simple' -> 'steps', '[]'::jsonb))),
      'blockers', to_jsonb(app.wf_blockers(w.id)),
      'in_flow', (select count(*) from app.workflow_runs r where r.workflow_id = w.id and r.state in ('running', 'waiting')),
      -- the last 90 days of what it sent
      'mail', (select jsonb_build_object('sent', count(*) filter (where r.state not in ('queued', 'skipped')),
                                         'opened', count(r.first_open_at), 'clicked', count(r.first_click_at), 'unsubscribed', count(r.unsubscribed_at))
               from app.campaign_recipients r
               where r.campaign_id = any (app.flow_campaigns(w.id)) and r.sent_at > now() - interval '90 days' and not r.is_sample))
    order by w.state = 'active' desc, w.name)
    -- the flows that write to people: sequences, lifecycle flows, and workflows with an email or campaign step
    from app.workflows w where w.deleted_at is null and not w.is_sample and w.kind in ('workflow', 'sequence', 'lifecycle')
      and (w.kind <> 'workflow' or cardinality(app.flow_campaigns(w.id)) > 0 or app.flow_steps(w.id) @> '[{"kind": "send_email"}]')), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- 9. Deliverability
-- ===========================================================================
create function public.growth_deliverability(p_product text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_product text := nullif(p_product, 'all'); v_m timestamptz := date_trunc('month', now() at time zone 'Europe/Oslo') at time zone 'Europe/Oslo';
begin
  return jsonb_build_object(
    -- the last 30 days of the application's campaigns and flows
    'sends', (select jsonb_build_object('sent', count(*) filter (where r.state not in ('queued', 'skipped')), 'delivered', count(r.delivered_at),
                                        'bounced', count(*) filter (where r.state in ('bounced', 'soft_bounced')), 'hard', count(*) filter (where r.bounce_kind = 'hard'),
                                        'complained', count(r.complained_at), 'unsubscribed', count(r.unsubscribed_at))
              from app.campaign_recipients r join app.campaigns c on c.id = r.campaign_id
              where app.in_scope(v_product, c.product) and r.sent_at > now() - interval '30 days' and not r.is_sample),
    'suppressions', coalesce((select jsonb_object_agg(s.reason, s.n) from (select reason, count(*) n from app.suppressions group by 1) s), '{}'::jsonb),
    -- what the engine does with email engagement, counted this month
    'signals', jsonb_build_object(
      'engaged', (select count(*) from app.notifications n where n.key = 'campaign.engaged' and n.created_at >= v_m),
      'replied', (select count(*) from app.sequence_enrollments e where e.exit_reason = 'reply' and e.ended_at >= v_m and not e.is_sample),
      'unsubscribed', (select count(*) from app.suppressions s where s.reason = 'unsubscribed' and s.created_at >= v_m),
      'hard_bounce', (select count(*) from app.suppressions s where s.reason = 'hard_bounce' and s.created_at >= v_m),
      'complaint', (select count(*) from app.suppressions s where s.reason = 'complaint' and s.created_at >= v_m)));
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.account_touch(jsonb, text) from public, anon, authenticated;
revoke all on function app.spend_channel(text, text, text) from public, anon, authenticated;
revoke all on function app.growth_arpa(text) from public, anon, authenticated;
revoke all on function app.flow_steps(uuid) from public, anon, authenticated;
revoke all on function app.flow_campaigns(uuid) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.growth_outcomes(text, text)', 'public.growth_budget(text)', 'public.marketing_budget_set(text, text, numeric)',
                           'public.marketing_budget_move(text, text, text, numeric)', 'public.growth_experiments_get(text)',
                           'public.growth_experiment_add(text, text, text, int, int, int)', 'public.growth_experiment_move(uuid, text)',
                           'public.growth_experiment_call(uuid, text, text)', 'public.growth_experiment_archive(uuid)', 'public.growth_calendar(text, int)',
                           'public.growth_blackout_add(text, text, date, date)', 'public.growth_blackout_remove(uuid)', 'public.growth_trial(text)',
                           'public.growth_flows()', 'public.growth_deliverability(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
