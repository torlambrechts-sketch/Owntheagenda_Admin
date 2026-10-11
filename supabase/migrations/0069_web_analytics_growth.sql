-- 0069_web_analytics_growth.sql — Growth › Analytics shows the web detail of 0068 itself (V-WEB-05), over its own ranges
-- (7, 30 or 90 days) and scoped to the application's site. analytics_web took 30, 90 or 365 days; it now takes 7 too.
-- Nothing else changes.

create or replace function public.analytics_web(p_site uuid default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (7, 30, 90, 365) then p_days else 30 end; v_tracked boolean;
begin
  perform app.require_marketing_reports();
  v_tracked := exists (select 1 from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site));
  return (
    with s as (
      select w.id, w.day, w.visitor_hash, w.started_at, w.entry_path, coalesce(w.channel, 'direct') channel, coalesce(w.device, 'unknown') device, w.pageviews,
             coalesce(nullif(lower(btrim(w.utm ->> 'utm_source')), ''), w.referrer_host) source,
             nullif(lower(btrim(w.utm ->> 'utm_medium')), '') medium, nullif(btrim(w.utm ->> 'utm_campaign'), '') campaign,
             nullif(lower(btrim(w.utm ->> 'utm_term')), '') term,
             exists (select 1 from app.web_events e where e.session_id = w.id and e.name = 'cta') cta,
             exists (select 1 from app.web_pageviews p where p.session_id = w.id and p.path ~* '^/(en/)?(registrer|signup)(/|$)') opened,
             exists (select 1 from app.web_events e where e.session_id = w.id and e.name = 'signup_started') started,
             exists (select 1 from app.web_events e where e.session_id = w.id and e.name = 'signup_completed') completed,
             greatest((select max(p.at) from app.web_pageviews p where p.session_id = w.id), (select max(e.at) from app.web_events e where e.session_id = w.id)) last_at
      from app.web_sessions w where w.day > current_date - d and (p_site is null or w.site_id = p_site)
    ),
    prev as (select w.day, w.visitor_hash from app.web_sessions w where w.day > current_date - 2 * d and w.day <= current_date - d and (p_site is null or w.site_id = p_site)),
    pv as (select p.session_id, p.path, row_number() over (partition by p.session_id order by p.at desc) rn from app.web_pageviews p join s on s.id = p.session_id)
    select jsonb_build_object(
      'sites', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'hostname', hostname) order by hostname) from app.web_sites where active), '[]'::jsonb),
      'search_console', (select status from app.integration_connections where provider = 'search_console'),
      'visitors', (select count(distinct (day, visitor_hash)) from s),
      'sessions', (select count(*) from s),
      'pageviews', (select coalesce(sum(pageviews), 0) from s),
      'bounces', (select count(*) filter (where pageviews <= 1) from s),
      -- null while the tracker had not started in the previous period, so a first month shows no change it cannot know
      'visitors_prev', case when exists (select 1 from prev) then (select count(distinct (day, visitor_hash)) from prev) end,
      'sessions_prev', case when exists (select 1 from prev) then (select count(*) from prev) end,
      -- a one-page visit has no length a cookieless tracker can see; the average is over the visits with a second hit
      'avg_seconds', (select round(avg(extract(epoch from (last_at - started_at))))::int from s where last_at > started_at),
      'signups', (select count(*) from app.account_products where created_at > now() - make_interval(days => d)),
      'daily', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visitors', v, 'sessions', n, 'pageviews', pv,
                                                             'signups', (select count(*) from app.account_products ap where ap.created_at::date = x.day)) order by day) from (
          select day, count(distinct visitor_hash) v, count(*) n, sum(pageviews) pv from s group by day) x), '[]'::jsonb),
      'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', x.channel, 'sessions', x.n, 'bounce', x.b, 'signups', coalesce(g.n, 0),
                                                                'started', x.st, 'completed', x.co) order by x.n desc) from (
          select channel, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b,
                 count(*) filter (where started) st, count(*) filter (where completed) co from s group by 1) x
          left join (select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) channel, count(*) n from app.account_products ap
                     where ap.created_at > now() - make_interval(days => d) group by 1) g on g.channel = x.channel), '[]'::jsonb),
      'sources', coalesce((select jsonb_agg(jsonb_build_object('source', source, 'medium', medium, 'campaign', campaign, 'channel', channel, 'sessions', n,
                                                               'bounce', b, 'started', st, 'completed', co) order by n desc, source nulls last) from (
          select source, medium, campaign, min(channel) channel, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b,
                 count(*) filter (where started) st, count(*) filter (where completed) co
          from s group by 1, 2, 3 order by 5 desc, 1 nulls last limit 25) x), '[]'::jsonb),
      'landing', coalesce((select jsonb_agg(jsonb_build_object('path', entry_path, 'sessions', n, 'bounce', b, 'pages', pg, 'opened', op, 'started', st, 'completed', co)
                                            order by n desc, entry_path) from (
          select entry_path, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b, round(avg(pageviews), 1) pg,
                 count(*) filter (where opened) op, count(*) filter (where started) st, count(*) filter (where completed) co
          from s group by 1 order by 2 desc, 1 limit 20) x), '[]'::jsonb),
      'top_pages', coalesce((select jsonb_agg(jsonb_build_object('path', path, 'views', v, 'sessions', n) order by v desc, path) from (
          select path, count(*) v, count(distinct session_id) n from pv group by 1 order by 2 desc, 1 limit 20) x), '[]'::jsonb),
      -- the page a visit ended on, against the visits that saw it
      'exits', coalesce((select jsonb_agg(jsonb_build_object('path', path, 'exits', e, 'sessions', n, 'rate', round(100.0 * e / n, 1)) order by e desc, path) from (
          select path, count(*) filter (where rn = 1) e, count(distinct session_id) n from pv group by 1 having count(*) filter (where rn = 1) > 0
          order by 2 desc, 1 limit 15) x), '[]'::jsonb),
      'devices', coalesce((select jsonb_agg(jsonb_build_object('device', device, 'sessions', n, 'bounce', b, 'opened', op, 'started', st, 'completed', co) order by n desc) from (
          select device, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b,
                 count(*) filter (where opened) op, count(*) filter (where started) st, count(*) filter (where completed) co from s group by 1) x), '[]'::jsonb),
      -- sessions are null while no session was tracked in the period, so a campaign is never shown with 0 visits it may have had
      'campaigns', coalesce((select jsonb_agg(jsonb_build_object('campaign', coalesce(v.c, g.c), 'sessions', case when v.c is not null then v.n when v_tracked then 0 end,
                                                                 'signups', coalesce(g.n, 0), 'paid', coalesce(g.paid, 0)) order by coalesce(g.n, 0) desc, coalesce(v.n, 0) desc) from
          (select campaign c, count(*) n from s where campaign is not null group by 1) v
          full join (select coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign' c, count(*) n, count(*) filter (where sb.confirmed_at is not null) paid
                     from app.account_products ap left join app.subscriptions sb on sb.product = ap.product and sb.tenant_id = ap.tenant_id
                     where ap.created_at > now() - make_interval(days => d) and nullif(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign', '') is not null
                     group by 1) g on g.c = v.c), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'value', value, 'count', n) order by n desc) from (
          select e.name, e.value, count(*) n from app.web_events e join s on s.id = e.session_id group by 1, 2 order by 3 desc limit 20) x), '[]'::jsonb),
      'companies', (select count(distinct w.company_org_number) from app.web_sessions w join s on s.id = w.id where w.company_org_number is not null),
      -- Search Console's queries by impressions (a young site is seen long before it is clicked); position weighted by impressions
      'search', coalesce((select jsonb_agg(jsonb_build_object('query', query, 'impressions', i, 'clicks', c, 'position', p,
                                                              'ctr', case when i > 0 then round(100.0 * c / i, 1) end) order by i desc, c desc, query) from (
          select query, sum(impressions) i, sum(clicks) c,
                 round(sum(position * impressions) filter (where position is not null) / nullif(sum(impressions) filter (where position is not null), 0), 1) p
          from app.search_console_daily where day > current_date - d and (p_site is null or site_id = p_site)
          group by 1 order by 2 desc, 3 desc, 1 limit 25) x), '[]'::jsonb),
      -- what the ads were shown for: utm_term, which Google Ads fills from {keyword}
      'paid_terms', coalesce((select jsonb_agg(jsonb_build_object('term', term, 'sessions', n, 'bounce', b, 'started', st, 'completed', co) order by n desc, term) from (
          select term, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b,
                 count(*) filter (where started) st, count(*) filter (where completed) co
          from s where term is not null group by 1 order by 2 desc, 1 limit 20) x), '[]'::jsonb),
      'signup', jsonb_build_object(
        'cta', (select count(*) filter (where cta) from s),
        'opened', (select count(*) filter (where opened) from s),
        'started', (select count(*) filter (where started) from s),
        'completed', (select count(*) filter (where completed) from s),
        'ctas', coalesce((select jsonb_agg(jsonb_build_object('value', value, 'sessions', n) order by n desc, value) from (
            select e.value, count(distinct e.session_id) n from app.web_events e join s on s.id = e.session_id where e.name = 'cta' and e.value is not null
            group by 1 order by 2 desc, 1 limit 10) x), '[]'::jsonb),
        'steps', coalesce((select jsonb_agg(jsonb_build_object('value', value, 'sessions', n) order by n desc, value) from (
            select e.value, count(distinct e.session_id) n from app.web_events e join s on s.id = e.session_id where e.name = 'signup_step' and e.value is not null
            group by 1 order by 2 desc, 1 limit 10) x), '[]'::jsonb),
        'errors', coalesce((select jsonb_agg(jsonb_build_object('value', value, 'count', n, 'sessions', ns) order by n desc, value) from (
            select e.value, count(*) n, count(distinct e.session_id) ns from app.web_events e join s on s.id = e.session_id where e.name = 'signup_error' and e.value is not null
            group by 1 order by 2 desc, 1 limit 10) x), '[]'::jsonb)),
      'attempts', coalesce((select jsonb_agg(j order by started_at desc) from (
          select s.started_at, jsonb_build_object(
                   'at', s.started_at, 'channel', s.channel, 'source', s.source, 'device', s.device, 'entry', s.entry_path,
                   'seconds', case when s.last_at > s.started_at then round(extract(epoch from (s.last_at - s.started_at)))::int end,
                   'outcome', case when s.completed then 'completed' when s.started then 'started' else 'opened' end,
                   'steps', coalesce((select jsonb_agg(z.j order by z.at, z.k) from (
                       select h.at, h.k, h.j from (
                         select p.at, 0 k, jsonb_build_object('kind', 'view', 'path', p.path, 'seconds', round(extract(epoch from (p.at - s.started_at)))::int) j
                         from app.web_pageviews p where p.session_id = s.id
                         union all
                         select e.at, 1 k, jsonb_build_object('kind', 'event', 'name', e.name, 'value', e.value, 'seconds', round(extract(epoch from (e.at - s.started_at)))::int) j
                         from app.web_events e where e.session_id = s.id) h
                       order by h.at, h.k limit 30) z), '[]'::jsonb)) j
          from s where s.opened or s.started or s.completed order by s.started_at desc limit 25) x), '[]'::jsonb))
  );
end $fn$;
