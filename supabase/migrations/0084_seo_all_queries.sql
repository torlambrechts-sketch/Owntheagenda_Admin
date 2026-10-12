-- 0084_seo_all_queries.sql — SEO › Keywords lists every search Google shows the site for, not only those tracked by hand.
--
-- Until now the list held app.seo_keywords alone, so a site with 28 searches in Search Console showed its five tracked
-- keywords, all «No impressions yet»: Google reports what people typed («verneombud psykososialt arbeidsmiljø»), and a
-- tracked head term («arbeidsmiljø») matched only an identical search. Now:
-- - every search with impressions in the period is a row (the 200 with most impressions; keywords_total says how many
--   there are), with its position, click rate, change and the page Google showed most for it;
-- - a tracked keyword stays a row of its own (tracked = true) and counts the longer searches that contain it (variants);
-- - nothing is stored: the searches are read from search_console_daily as imported, so a new search appears with the next
--   import without anyone tracking it. Tracking is now for watching a term, not for seeing it.

CREATE OR REPLACE FUNCTION public.seo_get(p_product text DEFAULT NULL::text, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days when p_days = 1 then 7 else 30 end;
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'));
  v_conn boolean := app.connected('search_console');
  c app.integration_connections;
  sc app.search_console_sites;
  v_pages boolean;
  v_pages_prev boolean;
begin
  select * into c from app.integration_connections where provider = 'search_console';
  select * into sc from app.search_console_sites where site_id = v_site.id;
  -- a period counts pages only once pages were imported for it (0072 starts the import)
  v_pages := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - d);
  v_pages_prev := exists (select 1 from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d);
  return jsonb_build_object(
    'connected', v_conn, 'days', d,
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'search_console', jsonb_build_object(
      'status', c.status,
      'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'),
      'key_stored', exists (select 1 from vault.secrets where name = 'search_console_key'),
      'client_email', c.config ->> 'client_email',
      'last_error', c.config ->> 'last_error',
      'property', sc.property,
      'site_error', sc.last_error,
      'last_import_at', sc.last_import_at,
      'last_day', sc.last_day),
    'totals', case when v_conn and v_site.id is not null and sc.property is not null then (
      select jsonb_build_object(
        'clicks', sum(t.clicks) filter (where t.day > current_date - d),
        'clicks_prev', sum(t.clicks) filter (where t.day <= current_date - d),
        'impressions', sum(t.impressions) filter (where t.day > current_date - d),
        'impressions_prev', sum(t.impressions) filter (where t.day <= current_date - d),
        'position', round(sum(t.position * t.impressions) filter (where t.day > current_date - d and t.position is not null)
                          / nullif(sum(t.impressions) filter (where t.day > current_date - d and t.position is not null), 0), 1),
        'position_prev', round(sum(t.position * t.impressions) filter (where t.day <= current_date - d and t.position is not null)
                               / nullif(sum(t.impressions) filter (where t.day <= current_date - d and t.position is not null), 0), 1))
        -- pages Google showed in search in the period (0072), the honest stand-in for «Indexed pages»; null before pages are imported
        || jsonb_build_object(
             'pages', case when v_pages then (select count(distinct p.page) from app.search_console_pages p
                                              where p.site_id = v_site.id and p.day > current_date - d and p.impressions > 0) end,
             'pages_prev', case when v_pages_prev then (select count(distinct p.page) from app.search_console_pages p
                                                        where p.site_id = v_site.id and p.day > current_date - 2 * d and p.day <= current_date - d and p.impressions > 0) end)
      from app.search_console_totals t where t.site_id = v_site.id and t.day > current_date - 2 * d) end,
    -- every search Google showed the site for in the period (the 200 with most impressions) and the keywords tracked by
    -- hand (0084); a tracked keyword also counts the longer searches that contain it, since Google rarely reports a
    -- head term like «arbeidsmiljø» on its own
    'keywords_total', case when v_conn and v_site.id is not null then (select count(distinct s.query) from app.search_console_daily s
                        where s.site_id = v_site.id and s.day > current_date - d and s.impressions > 0) end,
    'keywords', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'query', k.query, 'tracked', k.id is not null, 'created_at', k.created_at, 'mine', k.created_by = v_me,
        'impressions', case when v_conn then x.i end, 'clicks', case when v_conn then x.c end,
        'position', case when v_conn then x.p end, 'position_prev', case when v_conn then x.pp end,
        -- the page Google showed most for it in the period (0072)
        'page', case when v_conn then (select p.page from app.search_console_pages p where p.site_id = v_site.id and p.query = k.query and p.day > current_date - d
                                       group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) end,
        'variants', case when v_conn and k.id is not null then (
            select jsonb_build_object('queries', count(distinct v.query), 'impressions', coalesce(sum(v.impressions), 0))
            from app.search_console_daily v
            where v.site_id = v_site.id and v.day > current_date - d and v.impressions > 0 and v.query <> k.query
              and strpos(lower(v.query), lower(k.query)) > 0) end) order by k.id is null, k.created_at, x.i desc nulls last, k.query)
      from (select t.id, t.query, t.created_at, t.created_by from app.seo_keywords t where t.site_id = v_site.id
            union all
            select null::uuid, q.query, null::timestamptz, null::uuid from (
              select s.query from app.search_console_daily s
              where v_conn and s.site_id = v_site.id and s.day > current_date - d
                and not exists (select 1 from app.seo_keywords t where t.site_id = v_site.id and t.query = s.query)
              group by s.query having sum(s.impressions) > 0
              order by sum(s.impressions) desc, s.query limit 200) q) k
      left join lateral (
        select sum(sc2.impressions) filter (where sc2.day > current_date - d) i, sum(sc2.clicks) filter (where sc2.day > current_date - d) c,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null), 0), 1) p,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null), 0), 1) pp
        from app.search_console_daily sc2 where sc2.site_id = v_site.id and sc2.query = k.query and sc2.day > current_date - 2 * d) x on true
      where v_site.id is not null), '[]'::jsonb),
    -- Site health (0072): the last crawl and its open issues; an issue marked fixed waits for the next crawl to agree
    'health', case when v_site.id is not null then jsonb_build_object(
      'last_crawl_at', (select max(cr.finished_at) from app.seo_crawls cr where cr.site_id = v_site.id),
      'last_error', (select cr.error from app.seo_crawls cr where cr.site_id = v_site.id order by cr.finished_at desc limit 1),
      'pages', (select cr.pages from app.seo_crawls cr where cr.site_id = v_site.id and cr.pages > 0 order by cr.finished_at desc limit 1),
      'awaiting_check', (select count(*) from app.seo_issues i where i.site_id = v_site.id and i.resolved_at is null and i.fixed_at is not null),
      'issues', coalesce((select jsonb_agg(jsonb_build_object('kind', i.kind, 'severity', i.severity, 'count', i.count, 'paths', i.paths, 'value', i.value,
                                                              'ms', i.ms, 'first_seen_at', i.first_seen_at, 'reopened', i.reopened_at is not null)
                                           order by case i.severity when 'high' then 0 else 1 end, i.first_seen_at, i.kind)
                          from app.seo_issues i where i.site_id = v_site.id and i.resolved_at is null and i.fixed_at is null), '[]'::jsonb)) end,
    -- Content ideas (0072): searches Google already shows the site for, outside its top ten, not tracked yet; the last
    -- 28 days at least, so a 7-day range still has something to go on
    'ideas', case when v_conn and v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('query', q.query, 'impressions', q.i, 'position', q.p, 'days', q.days,
                                                                                   'page', q.page, 'planned', q.planned) order by q.planned, q.i desc, q.query)
      from (select s.query, sum(s.impressions) i, greatest(d, 28) days,
                   round(sum(s.position * s.impressions) filter (where s.position is not null) / nullif(sum(s.impressions) filter (where s.position is not null), 0), 1) p,
                   (select p.page from app.search_console_pages p where p.site_id = v_site.id and p.query = s.query and p.day > current_date - greatest(d, 28)
                    group by p.page having sum(p.impressions) > 0 order by sum(p.impressions) desc, p.page limit 1) page,
                   exists (select 1 from app.seo_content_plan cp where cp.site_id = v_site.id and cp.query = s.query) planned
            from app.search_console_daily s
            where s.site_id = v_site.id and s.day > current_date - greatest(d, 28)
              and not exists (select 1 from app.seo_keywords k where k.site_id = v_site.id and k.query = s.query)
            group by s.query
            having sum(s.impressions) >= 3
               and sum(s.position * s.impressions) filter (where s.position is not null) / nullif(sum(s.impressions) filter (where s.position is not null), 0) > 10
            order by sum(s.impressions) desc, s.query limit 6) q), '[]'::jsonb) end,
    -- Technical SEO beyond the crawl (0073): searches two or more of the site's pages split (each with at least a fifth of
    -- the impressions), and landing pages PageSpeed Insights measured slow on mobile
    'cannibal', case when v_conn and v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('query', cb.query, 'pages', cb.pages) order by cb.i desc, cb.query) from (
        select x.query, sum(x.i) i, jsonb_agg(jsonb_build_object('page', x.page, 'impressions', x.i) order by x.i desc, x.page) pages
        from (select p.query, p.page, sum(p.impressions) i, sum(sum(p.impressions)) over (partition by p.query) qt
              from app.search_console_pages p where p.site_id = v_site.id and p.day > current_date - greatest(d, 28)
              group by 1, 2) x
        where x.qt >= 10 and x.i >= x.qt * 0.2
        group by x.query having count(*) >= 2
        order by 2 desc, 1 limit 5) cb), '[]'::jsonb) end,
    'slow', case when v_site.id is not null then coalesce((select jsonb_agg(jsonb_build_object('path', v.path, 'lcp_ms', v.lcp_ms, 'inp_ms', v.inp_ms, 'field', v.field) order by v.lcp_ms desc)
        from app.page_vitals v where v.site_id = v_site.id and v.strategy = 'mobile' and (v.lcp_ms > 2500 or v.inp_ms > 200)), '[]'::jsonb) end);
end $function$;
