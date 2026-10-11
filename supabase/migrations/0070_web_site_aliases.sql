-- 0070_web_site_aliases.sql — Empvibe is counted as Orgpuls' site, as se.orgpuls.com and de.orgpuls.com already are, and
-- every visit says which host it came to.
--
-- Orgpuls opened www.empvibe.com on 11 October (its D-275) with the same beacon, but web-collect reads only an origin that
-- belongs to a registered site, so every Empvibe visit was dropped. A site now carries aliases: other domains whose
-- visits are the site's own (orgpuls.com: empvibe.com, and with it www.empvibe.com and its subdomains). The collector
-- learns them with the hostnames (worker_web_sites), worker_web_track files an alias's visit under its site, and the
-- session keeps the host it came to (web_sessions.host, from the collector, 0070), so Growth › Analytics can tell
-- orgpuls.com, se.orgpuls.com and empvibe.com apart. Empvibe's sign-up page is /sign-up, which «opened the form» now
-- counts beside /registrer.

-- ===========================================================================
-- 1. aliases and the host
-- ===========================================================================
alter table app.web_sites add column if not exists aliases text[] not null default '{}'
  check (array_position(aliases, null) is null and aliases::text = lower(aliases::text));
alter table app.web_sessions add column if not exists host text check (host is null or host ~ '^[a-z0-9.-]{1,253}$');
update app.web_sites set aliases = array['empvibe.com'] where hostname = 'orgpuls.com';

-- the hostnames and aliases web-collect may read an origin as
create or replace function public.worker_web_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(distinct h), '[]'::jsonb)
  from (select s.hostname h from app.web_sites s where s.active
        union all select a from app.web_sites s, unnest(s.aliases) a where s.active) x
$fn$;

-- an alias's visit is filed under its site; the rest is 0066's
create or replace function public.worker_web_track(p_item jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_site uuid; v_host text; v_hash text := p_item ->> 'visitor_hash'; v_n int;
begin
  if jsonb_typeof(p_item) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'item'; end if;
  select id, hostname into v_site, v_host from app.web_sites
  where active and (hostname = lower(p_item ->> 'site') or lower(p_item ->> 'site') = any (aliases))
  order by hostname = lower(p_item ->> 'site') desc limit 1;
  if v_site is null or coalesce(v_hash, '') !~ '^[0-9a-f]{32,64}$' then return jsonb_build_object('kept', 0); end if;
  select (select count(*) from app.web_pageviews p join app.web_sessions s on s.id = p.session_id
          where s.site_id = v_site and s.day = current_date and s.visitor_hash = v_hash)
       + (select count(*) from app.web_events e join app.web_sessions s on s.id = e.session_id
          where s.site_id = v_site and s.day = current_date and s.visitor_hash = v_hash) into v_n;
  if v_n >= 300 then return jsonb_build_object('kept', 0, 'reason', 'cap'); end if;
  return public.worker_web_ingest(jsonb_build_array(p_item || jsonb_build_object('site', v_host, 'at', now())));
end $fn$;

revoke all on function public.worker_web_sites() from public, anon, authenticated;
revoke all on function public.worker_web_track(jsonb) from public, anon, authenticated;
grant execute on function public.worker_web_sites(), public.worker_web_track(jsonb) to service_role;

-- the session keeps its host
CREATE OR REPLACE FUNCTION public.worker_web_ingest(p_batch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x jsonb; v_site uuid; v_sess uuid; v_utm jsonb; n int := 0; v_survey int := 0; v_org text; v_at timestamptz; v_crm uuid; v_new boolean;
  v_ident boolean := app.setting('web_ident') = 'on';
begin
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch'; end if;
  for x in select * from jsonb_array_elements(p_batch) loop
    -- never a survey host, even if one were registered (fixed rule, LGN-05)
    if lower(coalesce(x ->> 'site', '')) ~ '(^|\.)svar\.' then v_survey := v_survey + 1; continue; end if;
    select id into v_site from app.web_sites where hostname = lower(x ->> 'site') and active;
    -- the hash is the tracker's daily-salted digest; anything else (an address, a cookie) is dropped
    continue when v_site is null or coalesce(x ->> 'visitor_hash', '') !~ '^[0-9a-f]{32,64}$';
    v_at := (x ->> 'at')::timestamptz;
    v_utm := case when jsonb_typeof(x -> 'utm') = 'object' then x -> 'utm' else '{}'::jsonb end;
    v_org := case when v_ident and x ->> 'company_org_number' ~ '^\d{9}$'
                       and not exists (select 1 from app.web_companies w where w.org_number = x ->> 'company_org_number' and w.excluded)
                  then x ->> 'company_org_number' end;
    v_new := false;
    -- a session: the same visitor hash on the same day, within 30 minutes of its last page
    select s.id into v_sess from app.web_sessions s
    where s.site_id = v_site and s.day = v_at::date and s.visitor_hash = x ->> 'visitor_hash'
      and exists (select 1 from app.web_pageviews p where p.session_id = s.id and p.at > v_at - interval '30 minutes')
    order by s.started_at desc limit 1;
    if v_sess is null then
      insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, company_org_number, pageviews, device, host)
      values (v_site, v_at::date, x ->> 'visitor_hash', v_at, left(x ->> 'path', 500), left(x ->> 'referrer_host', 200),
              v_utm, app.channel_of(v_utm || jsonb_build_object('referrer_host', x ->> 'referrer_host')), v_org, 0,
              case when x ->> 'device' in ('mobile', 'tablet', 'desktop') then x ->> 'device' end,
              case when x ->> 'host' ~ '^[a-z0-9.-]{1,253}$' then x ->> 'host' end)
      returning id into v_sess;
      v_new := true;
    end if;
    if jsonb_typeof(x -> 'event') = 'object' then
      insert into app.web_events (session_id, at, name, value) values (v_sess, v_at, x -> 'event' ->> 'name', left(x -> 'event' ->> 'value', 120));
    else
      insert into app.web_pageviews (session_id, at, path) values (v_sess, v_at, left(coalesce(x ->> 'path', '/'), 500));
      update app.web_sessions set pageviews = pageviews + 1 where id = v_sess;
    end if;
    update app.web_sites set last_seen_at = greatest(coalesce(last_seen_at, v_at), v_at) where id = v_site;
    if v_new and v_org is not null then
      -- an unknown company: the register lookup (Brønnøysund, no key) runs in the edge worker
      if not exists (select 1 from app.web_companies w where w.org_number = v_org)
         and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.id <> v_sess and s.day > current_date - 30) then
        perform pgmq.send('jobs', jsonb_build_object('job', 'company_lookup', 'org_number', v_org));
      end if;
      -- visitor.identified: once per CRM organization per day, on its first session
      select o.id into v_crm from app.organizations o where o.org_number = v_org and o.deleted_at is null and not o.is_sample order by o.created_at limit 1;
      if v_crm is not null and not exists (select 1 from app.web_sessions s where s.company_org_number = v_org and s.day = v_at::date and s.id <> v_sess) then
        perform app.emit('visitor.identified', 'organization', v_crm,
                         jsonb_build_object('org_number', v_org, 'pages', (select pageviews from app.web_sessions where id = v_sess),
                                            'high_intent', coalesce(x ->> 'path', '') ~* '^/(pris|priser|pricing|demo|kontakt|contact)(/|$)'));
      end if;
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('stored', n, 'dropped_survey', v_survey);
end $function$;

-- ===========================================================================
-- 2. Analytics › Web: visits per host, and Empvibe's /sign-up as the form opened
-- ===========================================================================
create or replace function public.analytics_web(p_site uuid default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (7, 30, 90, 365) then p_days else 30 end; v_tracked boolean;
begin
  perform app.require_marketing_reports();
  v_tracked := exists (select 1 from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site));
  return (
    with s as (
      select w.id, w.day, w.visitor_hash, w.started_at, w.entry_path, w.host, coalesce(w.channel, 'direct') channel, coalesce(w.device, 'unknown') device, w.pageviews,
             coalesce(nullif(lower(btrim(w.utm ->> 'utm_source')), ''), w.referrer_host) source,
             nullif(lower(btrim(w.utm ->> 'utm_medium')), '') medium, nullif(btrim(w.utm ->> 'utm_campaign'), '') campaign,
             nullif(lower(btrim(w.utm ->> 'utm_term')), '') term,
             exists (select 1 from app.web_events e where e.session_id = w.id and e.name = 'cta') cta,
             exists (select 1 from app.web_pageviews p where p.session_id = w.id and p.path ~* '^/(en/)?(registrer|signup|sign-up)(/|$)') opened,
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
      -- which of the application's hosts the visit came to (0070): orgpuls.com, se.orgpuls.com, empvibe.com …; null before 0070
      'hosts', coalesce((select jsonb_agg(jsonb_build_object('host', host, 'sessions', n, 'bounce', b, 'opened', op, 'started', st, 'completed', co) order by n desc, host nulls last) from (
          select host, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b,
                 count(*) filter (where opened) op, count(*) filter (where started) st, count(*) filter (where completed) co from s group by 1) x), '[]'::jsonb),
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
