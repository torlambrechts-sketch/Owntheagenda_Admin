-- 0086_web_visit_join.sql — a signup's press joins the visit it belongs to, so it is not counted as a second «Direct» visit.
--
-- Checked on 13 Oct 2026 (Tor: «still shows Direct»). The website sends the page view and, on the signup page, the
-- «signup started» event at the same moment. web-collect stores each in its own call, so the two can reach
-- worker_web_ingest side by side: each looked for the visitor's open visit, neither saw the other's uncommitted row, and
-- the event made a visit of its own. That visit had no page view, no referrer and no tag (the event beacon carries
-- none; only the page view says where the visitor came from), so it was counted as one more «Direct» visit and the
-- signup was credited to it instead of to the visit that came from Google or a campaign. A visit started by an event
-- could not be found again either: a visit was matched only by a page view in the last thirty minutes.
--
-- Now, as 0073 otherwise:
-- - one visitor's hits are taken one at a time (a transaction lock on the site and the visitor code), so the second
--   finds the first's visit;
-- - a visit is matched by its start, a page view or an event in the last thirty minutes;
-- - when a visit an event started gets its first page view, the page view's landing page, referring host and tags are
--   the visit's (where it had none), and its channel is read again.
-- Rows (looked at first): the one visit made this way (se.orgpuls.com /registrera, 12 Oct 12:20) is merged into its
-- visitor's visit of the same minute, its event moved there; and the test visit to /e2e-check-0070 that 0070's release
-- check left on www.empvibe.com (11 Oct) is removed with its page view. Nothing else is touched.

CREATE OR REPLACE FUNCTION public.worker_web_ingest(p_batch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x jsonb; v_site uuid; v_sess uuid; v_utm jsonb; n int := 0; v_survey int := 0; v_org text; v_at timestamptz; v_crm uuid; v_new boolean;
  v_ident boolean := app.setting('web_ident') = 'on'; v_ref text; v_views int;
begin
  if jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch'; end if;
  for x in select * from jsonb_array_elements(p_batch) loop
    -- never a survey host, even if one were registered (fixed rule, LGN-05)
    if lower(coalesce(x ->> 'site', '')) ~ '(^|\.)svar\.' then v_survey := v_survey + 1; continue; end if;
    select id into v_site from app.web_sites where hostname = lower(x ->> 'site') and active;
    -- the hash is the tracker's daily-salted digest; anything else (an address, a cookie) is dropped
    continue when v_site is null or coalesce(x ->> 'visitor_hash', '') !~ '^[0-9a-f]{32,64}$';
    -- one visitor's hits one at a time: a page view and an event sent together find the same visit (0086)
    perform pg_advisory_xact_lock(hashtextextended('web_visit:' || v_site::text || ':' || (x ->> 'visitor_hash'), 0));
    v_at := (x ->> 'at')::timestamptz;
    v_utm := case when jsonb_typeof(x -> 'utm') = 'object' then x -> 'utm' else '{}'::jsonb end;
    v_ref := app.web_foreign_referrer(v_site, left(x ->> 'referrer_host', 200));
    v_org := case when v_ident and x ->> 'company_org_number' ~ '^\d{9}$'
                       and not exists (select 1 from app.web_companies w where w.org_number = x ->> 'company_org_number' and w.excluded)
                  then x ->> 'company_org_number' end;
    v_new := false;
    -- a visit: the same visitor hash on the same day, within 30 minutes of its start, a page view or an event (0086)
    select s.id into v_sess from app.web_sessions s
    where s.site_id = v_site and s.day = v_at::date and s.visitor_hash = x ->> 'visitor_hash'
      and (s.started_at > v_at - interval '30 minutes'
           or exists (select 1 from app.web_pageviews p where p.session_id = s.id and p.at > v_at - interval '30 minutes')
           or exists (select 1 from app.web_events e where e.session_id = s.id and e.at > v_at - interval '30 minutes'))
    order by s.started_at desc limit 1;
    if v_sess is null then
      insert into app.web_sessions (site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, company_org_number, pageviews, device, host)
      values (v_site, v_at::date, x ->> 'visitor_hash', v_at, left(x ->> 'path', 500), v_ref,
              v_utm, app.channel_of(v_utm || jsonb_build_object('referrer_host', v_ref)), v_org, 0,
              case when x ->> 'device' in ('mobile', 'tablet', 'desktop') then x ->> 'device' end,
              case when x ->> 'host' ~ '^[a-z0-9.-]{1,253}$' then x ->> 'host' end)
      returning id into v_sess;
      v_new := true;
    end if;
    if jsonb_typeof(x -> 'event') = 'object' then
      -- the page the press or the step happened on (0073)
      insert into app.web_events (session_id, at, name, value, path)
      values (v_sess, v_at, x -> 'event' ->> 'name', left(x -> 'event' ->> 'value', 120),
              case when x ->> 'path' ~ '^/' then left(x ->> 'path', 500) end);
    else
      insert into app.web_pageviews (session_id, at, path) values (v_sess, v_at, left(coalesce(x ->> 'path', '/'), 500));
      update app.web_sessions set pageviews = pageviews + 1 where id = v_sess returning pageviews into v_views;
      -- the first page view of a visit an event started says where the visit came from (0086)
      if v_views = 1 and not v_new then
        update app.web_sessions s
        set entry_path = left(coalesce(x ->> 'path', s.entry_path), 500),
            referrer_host = coalesce(s.referrer_host, v_ref),
            utm = case when s.utm = '{}'::jsonb then v_utm else s.utm end,
            channel = app.channel_of((case when s.utm = '{}'::jsonb then v_utm else s.utm end)
                                     || jsonb_build_object('referrer_host', coalesce(s.referrer_host, v_ref))),
            device = coalesce(s.device, case when x ->> 'device' in ('mobile', 'tablet', 'desktop') then x ->> 'device' end),
            host = coalesce(s.host, case when x ->> 'host' ~ '^[a-z0-9.-]{1,253}$' then x ->> 'host' end)
        where s.id = v_sess;
      end if;
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

-- a visit with no page view, made by an event beside its visitor's visit, joins that visit: its events move there
update app.web_events ev
set session_id = k.keep_id
from (select e.id as empty_id,
             (select s.id from app.web_sessions s
              where s.site_id = e.site_id and s.day = e.day and s.visitor_hash = e.visitor_hash and s.id <> e.id and s.pageviews > 0
                and abs(extract(epoch from s.started_at - e.started_at)) < 1800
              order by abs(extract(epoch from s.started_at - e.started_at)), s.started_at limit 1) as keep_id
      from app.web_sessions e where e.pageviews = 0) k
where ev.session_id = k.empty_id and k.keep_id is not null;

delete from app.web_sessions e
where e.pageviews = 0
  and not exists (select 1 from app.web_events ev where ev.session_id = e.id)
  and exists (select 1 from app.web_sessions s
              where s.site_id = e.site_id and s.day = e.day and s.visitor_hash = e.visitor_hash and s.id <> e.id and s.pageviews > 0
                and abs(extract(epoch from s.started_at - e.started_at)) < 1800);

-- the release check's test visit (0070), not a visitor
delete from app.web_sessions where entry_path = '/e2e-check-0070';
