-- 0066_web_collect.sql — the website tracker reaches Sentral again (0025 stored visits; nothing sent them since the
-- application's own beacon left with D-230).
--
-- The edge function web-collect takes a page view or a press from the application's public site, drops bots and the
-- pages that carry a capability token, hashes the address and browser with the day's salt (worker_web_salt) and keeps
-- 128 bits of it, and hands one item to worker_web_track. Neither the address nor the browser string is stored; the
-- salt is destroyed every night (0025), so a hash cannot be recomputed or joined across days.

-- the sites the tracker may record, by hostname (the function maps www. and subdomains onto them)
create function public.worker_web_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(s.hostname order by s.hostname), '[]'::jsonb) from app.web_sites s where s.active
$fn$;

-- one item from web-collect: at most 300 page views and presses per visitor, site and day, then 0031's ingest
create function public.worker_web_track(p_item jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_site uuid; v_hash text := p_item ->> 'visitor_hash'; v_n int;
begin
  if jsonb_typeof(p_item) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'item'; end if;
  select id into v_site from app.web_sites where hostname = lower(p_item ->> 'site') and active;
  if v_site is null or coalesce(v_hash, '') !~ '^[0-9a-f]{32,64}$' then return jsonb_build_object('kept', 0); end if;
  select (select count(*) from app.web_pageviews p join app.web_sessions s on s.id = p.session_id
          where s.site_id = v_site and s.day = current_date and s.visitor_hash = v_hash)
       + (select count(*) from app.web_events e join app.web_sessions s on s.id = e.session_id
          where s.site_id = v_site and s.day = current_date and s.visitor_hash = v_hash) into v_n;
  if v_n >= 300 then return jsonb_build_object('kept', 0, 'reason', 'cap'); end if;
  return public.worker_web_ingest(jsonb_build_array(p_item || jsonb_build_object('at', now())));
end $fn$;

-- Growth › Analytics: «Viewed pricing» and «Started signup» come from the tracker (0058 left them empty); a visitor is
-- counted once a day, as «Visited the site» is
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
begin
  perform app.require_marketing_reports();
  if v_product is not null and not exists (select 1 from app.products where key = v_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  v_sites := array(select s.id from app.web_sites s where s.active and (v_product is null or s.product = v_product) order by s.hostname);
  v_live := exists (select 1 from app.web_sessions w where w.site_id = any (v_sites));
  return jsonb_build_object(
    'days', d,
    'site', (select jsonb_build_object('id', s.id, 'hostname', s.hostname) from app.web_sites s where s.id = v_sites[1]),
    'tracked', v_live,
    'kpis', jsonb_build_object(
      'visitors', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                         where w.site_id = any (v_sites) and w.day > current_date - d) end,
      'visitors_prev', case when v_live then (select count(distinct (w.day, w.visitor_hash)) from app.web_sessions w
                                              where w.site_id = any (v_sites) and w.day > current_date - 2 * d and w.day <= current_date - d) end,
      'signups', (select count(*) from app.account_products ap where ap.created_at > v_from and app.in_scope(v_product, ap.product)),
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
                'visitors', case when v_live then (select count(distinct w.visitor_hash) from app.web_sessions w where w.site_id = any (v_sites) and w.day = g.day) end)
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

revoke all on function public.worker_web_sites() from public, anon, authenticated;
revoke all on function public.worker_web_track(jsonb) from public, anon, authenticated;
grant execute on function public.worker_web_sites(), public.worker_web_track(jsonb) to service_role;
