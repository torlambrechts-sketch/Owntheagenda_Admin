-- growth-sample.sql — LOCAL VISUAL QA ONLY. Never run against a hosted project.
--
-- Fills the local stack with website, Search Console and marketing rows shaped like SimpleGrowth.dc.html's own model (its
-- channel shares, device shares, hour profile, pages and keywords, at about a fifth of its volume) so every Growth screen
-- can be compared with the design in its populated state. The seed (supabase/seed.sql) stays as generated; this is laid on
-- top of it by `psql $DB -f scripts/visual/growth-sample.sql` and disappears with `supabase db reset`.
do $$
begin
  if current_setting('cluster_name', true) is distinct from '' and exists (select 1 from pg_settings where name = 'cluster_name' and setting like '%supabase%prod%') then
    raise exception 'refusing: not a local database';
  end if;
  if (select count(*) from auth.users) > 50 then raise exception 'refusing: this does not look like the local stack'; end if;
end $$;

select setseed(0.4242);

-- the application's site
update app.web_sites set product = 'orgpuls', last_seen_at = now() - interval '2 minutes' where hostname = 'orgpuls.com';

create temp table g_src (channel text, share numeric, conv numeric, utm jsonb, referrer text, ord int);
insert into g_src values
  ('organic_search', .46, 1.2, '{}', 'www.google.com', 1),
  ('paid_search', .18, 1.05, '{"utm_source": "google", "utm_medium": "cpc", "utm_campaign": "lovkrav-q4"}', null, 2),
  ('direct', .12, 0.9, '{}', null, 3),
  ('social', .09, 0.8, '{}', 'www.linkedin.com', 4),
  ('referral', .08, 1.5, '{}', null, 5),
  ('email', .04, 1.7, '{"utm_source": "newsletter", "utm_medium": "email", "utm_campaign": "oktober"}', null, 6),
  ('paid_social', .03, 0.55, '{"utm_source": "linkedin", "utm_medium": "paid_social", "utm_campaign": "hr-managers"}', null, 7);

create temp table g_pages (path text, title text, share numeric, bounce numeric, conv numeric);
insert into g_pages values
  ('/', 'Orgpuls — medarbeiderundersøkelse som oppfyller lovkravet', .27, .44, 1.3),
  ('/pris', 'Priser — Orgpuls', .14, .31, 4.1),
  ('/lovkrav', 'Lovkrav for arbeidsmiljøkartlegging', .19, .38, 2.1),
  ('/artikler/medarbeiderundersokelse-mal', 'Mal for medarbeiderundersøkelse', .145, .71, 0.6),
  ('/plattform', 'Plattformen', .06, .49, 1.2),
  ('/bruksomrader/verneombud', 'For verneombud', .068, .52, 1.3),
  ('/artikler/arbeidsmiljokartlegging', 'Slik kartlegger du arbeidsmiljøet', .055, .66, 0.7),
  ('/kom-i-gang', 'Kom i gang', .032, .18, 21.5),
  ('/skiftly', 'Skiftly — vaktplan', .025, .46, 1.9);

-- hour profile (the design's HP)
create temp table g_hours (h int, w numeric);
insert into g_hours select h - 1, w from unnest(array[2, 1, 1, 1, 1, 2, 4, 8, 14, 17, 16, 15, 13, 14, 15, 14, 12, 9, 8, 9, 10, 8, 5, 3]) with ordinality t(w, h);

-- sessions: about 150 a weekday, fewer at weekends, for 180 days
create temp table g_sess as
with days as (
  select off, (now() at time zone 'Europe/Oslo')::date - off d,
         round((150 - off * 0.3 + sin(off / 2.3) * 14 + random() * 24) * case when extract(dow from (now() at time zone 'Europe/Oslo')::date - off) in (0, 6) then 0.55 else 1 end)::int n
  from generate_series(0, 179) off
), sess as (
  select d.d, d.off, i, random() r_src, random() r_dev, random() r_hour, random() r_min, random() r_page, random() r_step, random() r_x
  from days d cross join lateral generate_series(1, greatest(d.n, 1)) i
)
select s.*, (select row(c.channel, c.share, c.conv, c.utm, c.referrer, c.ord)::g_src from (select g_src.*, sum(share) over (order by ord) - share lo, sum(share) over (order by ord) hi from g_src) c where s.r_src >= c.lo and s.r_src < c.hi) src,
       case when s.r_dev < .62 then 'desktop' when s.r_dev < .96 then 'mobile' else 'tablet' end device,
       (select h from (select h, sum(w) over (order by h) / (select sum(w) from g_hours) hi, (sum(w) over (order by h) - w) / (select sum(w) from g_hours) lo from g_hours) x where s.r_hour >= x.lo and s.r_hour < x.hi) hr,
       (select row(p.path, p.title, p.share, p.bounce, p.conv)::g_pages from (select g_pages.*, sum(share) over (order by share desc, path) / (select sum(share) from g_pages) hi,
                              (sum(share) over (order by share desc, path) - share) / (select sum(share) from g_pages) lo from g_pages) p where s.r_page >= p.lo and s.r_page < p.hi) pg
from sess s;

alter table g_sess add column id uuid default gen_random_uuid(), add column at timestamptz, add column reached int, add column referrer text, add column utm jsonb;
update g_sess set at = (d::timestamp + make_interval(hours => coalesce(hr, 12), mins => floor(r_min * 60)::int)) at time zone 'Europe/Oslo',
  referrer = case when (src).channel = 'referral' then (array['hrnorge.no', 'ks.no', 'bedriftshelsetjenesten.no', 'dagensperspektiv.no', 'arbeidsrett.no'])[1 + floor(r_x * 5)::int]
                  else (src).referrer end,
  utm = case when (src).channel = 'paid_search' then (src).utm || jsonb_build_object('utm_term', (array['lovkrav arbeidsmiljø', 'medarbeiderundersøkelse', 'hms system pris', 'pulsundersøkelse'])[1 + floor(r_x * 4)::int])
             else (src).utm end;
delete from g_sess where at > now();
-- how far each visit went: 1 visit, 2 pricing, 3 press, 4 org.nr sent, 5 done on the site
update g_sess set reached = case
  when r_step < 0.68 then 1
  when r_step < 0.68 + 0.32 * (1 - 0.2) * 0.85 then 2
  when r_step < 0.985 then 3
  when r_step < 0.993 * (case when device = 'mobile' then 0.998 else 1 end) then 4
  else 5 end;

insert into app.web_sessions (id, site_id, day, visitor_hash, started_at, entry_path, referrer_host, utm, channel, pageviews, device, host)
select s.id, w.id, s.at::date, md5(s.id::text), s.at, (s.pg).path, s.referrer, s.utm,
       app.channel_of(s.utm || jsonb_build_object('referrer_host', s.referrer)),
       case when s.reached = 1 and s.r_x < (s.pg).bounce then 1 else 1 + s.reached end, s.device, 'orgpuls.com'
from g_sess s cross join (select id from app.web_sites where hostname = 'orgpuls.com') w;

-- page views: the landing page, then pricing, then the signup page as far as each visit went
insert into app.web_pageviews (session_id, at, path)
select id, at, (pg).path from g_sess
union all select id, at + make_interval(secs => 30 + r_min * 60), '/pris' from g_sess where reached >= 2 or (reached = 1 and r_x >= (pg).bounce)
union all select id, at + make_interval(secs => 120 + r_min * 90), '/kom-i-gang' from g_sess where reached >= 3;
-- presses and signup steps
insert into app.web_events (session_id, at, name, value, path)
select id, at + make_interval(secs => 100 + r_min * 80), 'cta', (array['kom-i-gang-hero', 'se-priser-meny', 'last-ned-malen', 'book-demo', 'prov-gratis-boks'])[1 + floor(r_x * 5)::int],
       case when r_x < .2 then '/' when r_x < .4 then '/pris' when r_x < .6 then '/artikler/medarbeiderundersokelse-mal' when r_x < .8 then '/pris' else '/lovkrav' end
from g_sess where reached >= 3
union all select id, at + make_interval(secs => 400 + r_min * 200), 'signup_started', null, '/kom-i-gang' from g_sess where reached >= 4
union all select id, at + make_interval(secs => 900 + r_min * 400), 'signup_completed', null, '/kom-i-gang' from g_sess where reached >= 5
union all select id, at + make_interval(secs => 500 + r_min * 100), 'signup_error', (array['brreg_not_found', 'org_registered', 'brreg_not_found'])[1 + floor(r_x * 3)::int], '/kom-i-gang'
  from g_sess where reached = 4 and r_x < .5
union all select id, at + make_interval(secs => 200 + r_min * 100), 'signup_error', 'org_invalid', '/kom-i-gang' from g_sess where reached = 3 and r_x < .2;

-- what the crawler read, and Core Web Vitals
insert into app.seo_pages (site_id, path, title, description, h1, status, ms, noindex)
select w.id, p.path, p.title, 'Om ' || lower(p.title), 1, 200, 400 + (random() * 900)::int, false from g_pages p cross join (select id from app.web_sites where hostname = 'orgpuls.com') w
on conflict do nothing;
insert into app.page_vitals (site_id, path, strategy, lcp_ms, inp_ms, cls, score, field)
select w.id, p.path, 'mobile', v.lcp, v.inp, v.cls, v.score, v.inp is not null
from g_pages p cross join (select id from app.web_sites where hostname = 'orgpuls.com') w
join (values ('/', 1900, 140, .02, 91), ('/pris', 2200, 160, .03, 88), ('/lovkrav', 1700, 120, .01, 94), ('/artikler/medarbeiderundersokelse-mal', 2900, 210, .08, 71),
             ('/plattform', 4100, 310, .19, 52), ('/bruksomrader/verneombud', 2100, 150, .04, 89), ('/artikler/arbeidsmiljokartlegging', 2400, null, .05, 84),
             ('/kom-i-gang', 1400, 90, .01, 97), ('/skiftly', 2600, 200, .06, 79)) v(path, lcp, inp, cls, score) on v.path = p.path
on conflict do nothing;

-- accounts: a first touch on each seeded account, by the same shares
update app.account_products ap set attribution = jsonb_build_object('first_touch',
  case when x.r < .46 then jsonb_build_object('referrer_host', 'www.google.com', 'landing', '/lovkrav')
       when x.r < .64 then jsonb_build_object('utm_source', 'google', 'utm_medium', 'cpc', 'utm_campaign', 'lovkrav-q4')
       when x.r < .76 then jsonb_build_object()
       when x.r < .85 then jsonb_build_object('referrer_host', 'www.linkedin.com')
       when x.r < .93 then jsonb_build_object('referrer_host', 'hrnorge.no')
       when x.r < .97 then jsonb_build_object('utm_source', 'newsletter', 'utm_medium', 'email')
       else jsonb_build_object('utm_source', 'linkedin', 'utm_medium', 'paid_social') end)
from (select product, tenant_id, random() r from app.account_products) x
where x.product = ap.product and x.tenant_id = ap.tenant_id;

-- Search Console: connected, the property, totals, queries and pages for 180 days
update app.integration_connections set status = 'connected', config = '{"client_email": "sentral@orgpuls-sc.iam.gserviceaccount.com"}' where provider = 'search_console';
insert into app.search_console_sites (site_id, property, last_import_at, last_day)
select id, 'sc-domain:orgpuls.com', now() - interval '6 hours', current_date - 2 from app.web_sites where hostname = 'orgpuls.com'
on conflict (site_id) do update set property = excluded.property, last_import_at = excluded.last_import_at, last_day = excluded.last_day;
create temp table g_kw (q text, vol int, pos numeric, prev numeric, page text, ctr numeric);
insert into g_kw values
  ('medarbeiderundersøkelse', 18400, 4.2, 5.5, '/artikler/medarbeiderundersokelse-mal', .041), ('arbeidsmiljøkartlegging', 9200, 2.8, 3.4, '/artikler/arbeidsmiljokartlegging', .13),
  ('psykososialt arbeidsmiljø lovkrav', 6100, 1.9, 2.3, '/lovkrav', .31), ('verneombud plikter', 11800, 8.4, 7.2, '/bruksomrader/verneombud', .019),
  ('medarbeiderundersøkelse mal gratis', 3400, 11.6, 13.7, '/artikler/medarbeiderundersokelse-mal', .006), ('pulsundersøkelse', 2900, 14.2, 13.4, '/plattform', .004),
  ('orgpuls', 1300, 1.0, 1.0, '/', .62), ('qps nordic', 2400, 6.1, 7.9, '/artikler/arbeidsmiljokartlegging', .033),
  ('kartlegging psykososialt arbeidsmiljø mal', 2100, 3.3, 4.1, '/lovkrav', .052), ('hms system pris', 1600, 17.8, 15.2, '/pris', .003),
  ('vaktplan app', 4800, 22.4, 26.1, '/skiftly', .001), ('arbeidsmiljøundersøkelse', 5300, 5.4, 5.1, '/artikler/medarbeiderundersokelse-mal', .028),
  ('hvordan gjennomføre en medarbeiderundersøkelse', 6200, 23.5, 25.0, '/artikler/medarbeiderundersokelse-mal', .002),
  ('sjekkliste for vernerunde', 4100, 18.1, 19.0, '/bruksomrader/verneombud', .003), ('vaktplan mal excel', 3900, 31.0, 33.0, '/skiftly', .001);
insert into app.search_console_daily (day, site_id, query, impressions, clicks, position)
select current_date - 2 - off, w.id, k.q, i, round(i * k.ctr * (0.7 + random() * 0.6))::int,
       round((k.prev + (k.pos - k.prev) * (1 - least(off, 30) / 30.0) + (random() - 0.5) * 1.2)::numeric, 1)
from g_kw k cross join generate_series(0, 177) off cross join (select id from app.web_sites where hostname = 'orgpuls.com') w
cross join lateral (select greatest(1, round(k.vol / 30.0 * greatest(0.15, 1 - k.pos / 40) * (0.6 + random() * 0.8) / 5))::int i) x
on conflict do nothing;
insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
select d.day, d.site_id, d.query, k.page, d.impressions, d.clicks, d.position from app.search_console_daily d join g_kw k on k.q = d.query
on conflict do nothing;
-- the second page «medarbeiderundersøkelse» ranks with (cannibalization)
insert into app.search_console_pages (day, site_id, query, page, impressions, clicks, position)
select d.day, d.site_id, d.query, '/artikler/mal-2024', greatest(1, d.impressions / 2), d.clicks / 3, d.position + 3 from app.search_console_daily d
where d.query = 'medarbeiderundersøkelse' on conflict do nothing;
insert into app.search_console_totals (day, site_id, impressions, clicks, position)
select day, site_id, sum(impressions) * 3, sum(clicks) * 3, round(sum(position * impressions) / nullif(sum(impressions), 0), 1)
from app.search_console_daily group by 1, 2 on conflict do nothing;
-- each page's own figures (0090): its named searches and the rare ones Search Console does not name
insert into app.search_console_page_totals (day, site_id, page, impressions, clicks, position)
select day, site_id, page, sum(impressions) * 2, sum(clicks) * 2 + 1, round(sum(position * impressions) / nullif(sum(impressions), 0), 1)
from app.search_console_pages group by 1, 2, 3 on conflict do nothing;
-- the countries and devices the searches came from (0090)
insert into app.search_console_segments (day, site_id, kind, key, impressions, clicks, position)
select t.day, t.site_id, c.kind, c.key, greatest(1, round(t.impressions * c.share))::int, round(t.clicks * c.share)::int, t.position + c.dpos
from app.search_console_totals t
cross join (values ('country', 'nor', .86, 0), ('country', 'swe', .05, 6), ('country', 'dnk', .03, 8), ('country', 'gbr', .02, 12),
                   ('country', 'usa', .015, 15), ('country', 'deu', .01, 14), ('country', 'zzz', .005, 20),
                   ('device', 'mobile', .58, 1.4), ('device', 'desktop', .39, 0.5), ('device', 'tablet', .03, 2)) c(kind, key, share, dpos)
on conflict do nothing;
insert into app.seo_keywords (site_id, query)
select w.id, k.q from g_kw k cross join (select id from app.web_sites where hostname = 'orgpuls.com') w where k.pos < 23 on conflict do nothing;

-- the crawl and its issues
select public.worker_seo_crawl_result((select id from app.web_sites where hostname = 'orgpuls.com'), 55, 8500,
  '[{"kind":"missing_description","severity":"high","count":3,"paths":["/pris","/kom-i-gang","/bruksomrader/bygg"]},{"kind":"slow_page","severity":"high","count":1,"paths":["/plattform"],"ms":4100},{"kind":"broken_link","severity":"medium","count":2,"paths":["/gammel-side","/artikler/arbeidsmiljo-2025"],"value":"/artikler/arbeidsmiljo-2025"},{"kind":"duplicate_title","severity":"medium","count":4,"paths":["/artikler/a","/artikler/b","/artikler/c","/artikler/d"],"value":"Orgpuls — artikler"}]'::jsonb, null);

-- marketing campaigns and their spend
insert into app.ad_campaigns (product, name, channel, landing_path, utm_source, utm_medium, utm_campaign, budget, currency, starts_on, ends_on, state)
values ('orgpuls', 'Lovkrav — Q4', 'google_ads', '/lovkrav', 'google', 'cpc', 'lovkrav-q4', 56000, 'NOK', current_date - 40, current_date + 50, 'live'),
       ('orgpuls', 'HR managers', 'linkedin', '/lp/hr', 'linkedin', 'paid_social', 'hr-managers', 30000, 'NOK', current_date - 60, current_date + 20, 'live')
on conflict do nothing;
insert into app.marketing_spend (campaign, month, channel, amount, currency)
select c, date_trunc('month', current_date - m * 30)::date, ch, a, 'NOK'
from (values ('lovkrav-q4', 'paid_search', 12400), ('hr-managers', 'paid_social', 9600)) v(c, ch, a) cross join generate_series(0, 3) m
on conflict do nothing;

-- a product event now and then, so the sync log has the products' lines
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at, received_at)
select 'orgpuls', 900000 + g, (array['usage.daily', 'member.joined', 'billing.changed'])[1 + g % 3], null, '{}', now() - make_interval(hours => g * 5), now() - make_interval(hours => g * 5)
from generate_series(1, 12) g
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- SEO suite (0074): pages, index coverage, the link graph and mentions, a content plan, changes and alerts
create temp table g_site as select id from app.web_sites where hostname = 'orgpuls.com';
insert into app.seo_pages (site_id, path, title, description, h1, status, ms, noindex)
select g_site.id, v.path, v.title, v.title, 1, 200, 600, v.noindex
from g_site, (values ('/artikler/qps-nordic', 'QPS Nordic forklart', false), ('/artikler/anonymitet', 'Anonymitet i undersøkelser', false),
                     ('/artikler/sporsmal', 'Spørsmål til medarbeiderundersøkelse', false), ('/artikler/mal-2024', 'Mal for medarbeiderundersøkelse 2024', false),
                     ('/artikler/tiltaksplan-eksempel', 'Tiltaksplan — eksempel', false), ('/kampanje/hms2026', 'HMS 2026', true)) v(path, title, noindex)
on conflict do nothing;
update app.seo_crawls set origin = 'https://www.orgpuls.com' where id = (select id from app.seo_crawls where site_id = (select id from g_site) order by finished_at desc limit 1);
select public.worker_seo_index_result((select id from g_site), (
  select jsonb_agg(jsonb_build_object('path', sp.path, 'last_crawl_at', now() - interval '3 days',
         'coverage', case sp.path when '/kampanje/hms2026' then 'noindex' when '/artikler/tiltaksplan-eksempel' then 'crawled_not_indexed'
                                  when '/artikler/mal-2024' then 'duplicate' else 'indexed' end))
  from app.seo_pages sp where sp.site_id = (select id from g_site)) || '[{"path": "/gammel-side", "coverage": "not_found"}]'::jsonb);
-- every page links to the main navigation; a few articles link to each other
select public.worker_seo_links((select id from g_site), 'https://www.orgpuls.com', (
  select jsonb_agg(l) from (
    select jsonb_build_object('from', sp.path, 'to', n.to_path, 'anchor', n.anchor) l
    from app.seo_pages sp cross join (values ('/', 'Orgpuls'), ('/pris', 'Priser'), ('/kom-i-gang', 'Kom i gang'), ('/lovkrav', 'Lovkrav'),
                                             ('/plattform', 'Plattform'), ('/skiftly', 'Skiftly')) n(to_path, anchor)
    where sp.site_id = (select id from g_site) and sp.path not in ('/artikler/mal-2024', '/artikler/tiltaksplan-eksempel', '/kampanje/hms2026')
    union all
    select jsonb_build_object('from', f, 'to', t, 'anchor', a) from (values
      ('/lovkrav', '/artikler/medarbeiderundersokelse-mal', 'mal'), ('/', '/bruksomrader/verneombud', 'verneombud'),
      ('/artikler/arbeidsmiljokartlegging', '/artikler/qps-nordic', 'QPS Nordic'), ('/artikler/medarbeiderundersokelse-mal', '/artikler/anonymitet', 'anonymitet'),
      ('/artikler/medarbeiderundersokelse-mal', '/artikler/sporsmal', 'spørsmål'), ('/plattform', '/artikler/arbeidsmiljokartlegging', 'kartlegging')) x(f, t, a)) q),
  '[{"path": "/artikler/qps-nordic", "term": "medarbeiderundersøkelse"}, {"path": "/artikler/anonymitet", "term": "medarbeiderundersøkelse"},
    {"path": "/artikler/arbeidsmiljokartlegging", "term": "psykososialt arbeidsmiljø lovkrav"}, {"path": "/bruksomrader/verneombud", "term": "arbeidsmiljøkartlegging"},
    {"path": "/artikler/sporsmal", "term": "medarbeiderundersøkelse mal gratis"}, {"path": "/lovkrav", "term": "verneombud plikter"},
    {"path": "/artikler/qps-nordic", "term": "qps nordic"}]'::jsonb);
-- the content plan, the change log and a few alerts
insert into app.seo_content_plan (site_id, query, kind, path, stage, created_by, owner_id, published_at, updated_at)
select (select id from g_site), v.q, v.k, v.p, v.s, a.id, a.id, case when v.s in ('published', 'measuring') then now() - make_interval(days => v.days) end, now() - make_interval(hours => v.days)
from (values ('hvordan gjennomføre en medarbeiderundersøkelse', 'gap', null, 'writing', 0, 'sara@orgpuls.no'),
             ('sjekkliste for vernerunde', 'striking', '/bruksomrader/verneombud', 'idea', 0, 'ola@orgpuls.no'),
             ('psykososialt arbeidsmiljø lovkrav', 'low_ctr', '/lovkrav', 'published', 6, 'sara@orgpuls.no'),
             ('medarbeiderundersøkelse mal gratis', 'striking', '/artikler/medarbeiderundersokelse-mal', 'measuring', 45, 'sara@orgpuls.no'),
             ('qps nordic', 'striking', '/artikler/qps-nordic', 'measuring', 38, 'ola@orgpuls.no')) v(q, k, p, s, days, who)
join app.admins a on a.email = v.who
on conflict (site_id, query) do update set kind = excluded.kind, path = excluded.path, stage = excluded.stage, published_at = excluded.published_at;
insert into app.seo_changes (site_id, day, path, kind, note, source, created_by)
select (select id from g_site), current_date - v.days, v.p, v.k, v.note, 'manual', (select id from app.admins where email = 'sara@orgpuls.no')
from (values (48, '/artikler/medarbeiderundersokelse-mal', 'content', 'Oppdatert for 2026 og mal til nedlasting'), (41, '/lovkrav', 'schema', 'FAQ-skjema med seks spørsmål'),
             (34, '/plattform', 'speed', 'Hovedbildet til WebP'), (27, '/artikler/qps-nordic', 'title_meta', '«2026» og nytte i tittelen'),
             (20, '/bruksomrader/verneombud', 'links', 'Fem lenker fra artikler'), (13, '/pris', 'title_meta', 'Pris i metabeskrivelsen')) v(days, p, k, note)
where not exists (select 1 from app.seo_changes);
insert into app.seo_alerts (site_id, rule, subject, key, params, at, acknowledged_at)
select (select id from g_site), v.rule, v.subj, v.subj || '@sample', v.params::jsonb, now() - make_interval(hours => v.h), case when v.ack then now() end
from (values ('rank', 'verneombud plikter', '{"query": "verneombud plikter", "from": 6.1, "to": 9.4}', 3, false),
             ('cwv', '/plattform', '{"path": "/plattform", "metric": "lcp", "value": 4.1}', 50, false),
             ('deindex', '/artikler/mal-2024', '{"path": "/artikler/mal-2024", "coverage": "duplicate"}', 75, true),
             ('traffic', 'organic', '{"hour": "09:00", "now": 4, "before": 11}', 130, false)) v(rule, subj, params, h, ack)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Playbook (0076): more campaigns and their spend, last touches, budgets, experiments, blackout periods and a sent newsletter
insert into app.ad_campaigns (product, name, channel, landing_path, utm_source, utm_medium, utm_campaign, budget, currency, starts_on, ends_on, state)
values ('orgpuls', 'Meta retargeting', 'facebook', '/pris', 'facebook', 'paid_social', 'meta-retarget', 8000, 'NOK', current_date - 25, current_date + 30, 'live'),
       ('orgpuls', 'Verneombud webinar', 'webinar', '/webinar/verneombud', 'webinar', 'partner', 'verneombud-webinar', 6000, 'NOK', current_date - 70, current_date - 69, 'ended'),
       ('orgpuls', 'Årsplan', 'google_ads', '/lovkrav', 'google', 'cpc', 'arsplan', 20000, 'NOK', make_date(extract(year from current_date)::int, 1, 3), make_date(extract(year from current_date)::int, 2, 20), 'ended')
on conflict do nothing;
insert into app.marketing_spend (campaign, month, channel, amount, currency)
values ('meta-retarget', date_trunc('month', current_date)::date, 'paid_social', 2100, 'NOK'),
       ('meta-retarget', date_trunc('month', current_date - 30)::date, 'paid_social', 1900, 'NOK'),
       ('verneombud-webinar', date_trunc('month', current_date - 70)::date, 'partner', 6000, 'NOK'),
       ('oktober', date_trunc('month', current_date)::date, 'email', 1200, 'NOK')
on conflict do nothing;
-- the last touch the product reported, on two accounts in five
update app.account_products ap set attribution = ap.attribution || jsonb_build_object('last_touch',
  case when x.r < .2 then jsonb_build_object('utm_source', 'newsletter', 'utm_medium', 'email') else jsonb_build_object('referrer_host', 'www.google.com') end)
from (select product, tenant_id, random() r from app.account_products) x
where x.product = ap.product and x.tenant_id = ap.tenant_id and x.r < .4 and ap.attribution ? 'first_touch';
-- one paying account each from paid social and the webinar, so the planner has costs to compare
update app.account_products ap set attribution = jsonb_set(ap.attribution, '{first_touch}', x.touch)
from (select sb.product, sb.tenant_id, (array['{"utm_source": "linkedin", "utm_medium": "paid_social"}', '{"utm_source": "partner-webinar", "utm_medium": "event"}'])[row_number() over (order by sb.confirmed_at desc)]::jsonb touch
      from app.subscriptions sb where sb.confirmed_at > now() - interval '90 days' order by sb.confirmed_at desc limit 2) x
where x.product = ap.product and x.tenant_id = ap.tenant_id;
insert into app.marketing_budgets (product, month, channel, amount)
values ('orgpuls', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, 'paid_search', 30000),
       ('orgpuls', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, 'paid_social', 24000),
       ('orgpuls', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, 'email', 2000),
       ('orgpuls', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, 'partner', 6000),
       ('orgpuls', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, 'organic_search', 15000)
on conflict do nothing;
insert into app.growth_experiments (product, hypothesis, area, impact, confidence, ease, stage, outcome, result_note, owner_id, started_at, ended_at, created_at)
select 'orgpuls', h, a, i, c, e, s, o, n, (select id from app.admins order by created_at limit 1),
       case when s in ('running', 'done') then now() - make_interval(days => d) end, case when s = 'done' then now() - make_interval(days => d / 3) end, now() - make_interval(days => d + 5)
from (values
  ('Email-only first signup step (org.nr later)', 'signup', 9, 8, 8, 'running', null, null, 12),
  ('Price calculator on /pris', 'pricing', 8, 7, 6, 'running', null, null, 9),
  ('Behaviour-based trial emails', 'email', 9, 7, 7, 'ready', null, null, 4),
  ('LinkedIn video vs image', 'ads', 6, 6, 9, 'ready', null, null, 3),
  ('«Book demo» next to «Kom i gang»', 'landing_page', 7, 6, 9, 'backlog', null, null, 2),
  ('Referral: give a month, get a month', 'referral', 8, 5, 6, 'backlog', null, null, 1),
  ('Subject line with employee count', 'email', 5, 7, 10, 'done', 'win', '+11 % clicks, rolled out', 30),
  ('Free template behind email', 'content', 7, 8, 8, 'done', 'no_effect', null, 24)
) v(h, a, i, c, e, s, o, n, d)
where not exists (select 1 from app.growth_experiments);
insert into app.growth_blackouts (product, name, starts_on, ends_on)
select 'orgpuls', n, f, t from (values
  ('Fellesferie', make_date(extract(year from current_date)::int, 7, 1), make_date(extract(year from current_date)::int, 8, 9)),
  ('Jul', make_date(extract(year from current_date)::int, 12, 20), make_date(extract(year from current_date)::int, 12, 31))) v(n, f, t)
where not exists (select 1 from app.growth_blackouts);
-- the October newsletter, sent twelve days ago to 640 addresses
update app.campaigns set status = 'scheduled', rendered_html = coalesce(rendered_html, '<p>Oktober</p>'), scheduled_at = now() - interval '12 days'
where id = 'c5d7c291-0ce6-4d8b-aa5f-347788b5df55' and status = 'draft';
update app.campaigns set status = 'sending', started_at = now() - interval '12 days' where id = 'c5d7c291-0ce6-4d8b-aa5f-347788b5df55' and status = 'scheduled';
update app.campaigns set status = 'sent', sent_at = now() - interval '12 days' where id = 'c5d7c291-0ce6-4d8b-aa5f-347788b5df55' and status = 'sending';
insert into app.campaign_recipients (campaign_id, email, send_key, state, sent_at, delivered_at, first_open_at, first_click_at, unsubscribed_at, complained_at, bounced_at, bounce_kind)
select 'c5d7c291-0ce6-4d8b-aa5f-347788b5df55', 'sample' || g || '@example.invalid', 'g' || g,
       case when g % 70 = 0 then 'bounced' when g % 320 = 0 then 'complained' else 'delivered' end,
       now() - interval '12 days', case when g % 70 <> 0 then now() - interval '12 days' end,
       case when g % 3 = 0 then now() - interval '11 days' end, case when g % 11 = 0 then now() - interval '11 days' end,
       case when g % 160 = 0 then now() - interval '10 days' end, case when g % 320 = 0 then now() - interval '10 days' end,
       case when g % 70 = 0 then now() - interval '12 days' end, case when g % 70 = 0 then (case when g % 140 = 0 then 'hard' else 'soft' end) end
from generate_series(1, 640) g
where not exists (select 1 from app.campaign_recipients where campaign_id = 'c5d7c291-0ce6-4d8b-aa5f-347788b5df55');
insert into app.suppressions (email_sha256, scope, reason, created_at)
select sha256(convert_to('sample' || g || '@example.invalid', 'UTF8')), 'marketing', r, now() - make_interval(days => g % 9)
from (values (160, 'unsubscribed'), (320, 'unsubscribed'), (480, 'unsubscribed'), (140, 'hard_bounce'), (280, 'hard_bounce'), (420, 'hard_bounce'), (321, 'complaint'), (7, 'manual')) v(g, r)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Ad platforms (0077): Google Ads and Meta connected with one account each, sixty days through the import itself
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'google_ads_developer_token') then
    perform vault.create_secret('sample-developer-token-local', 'google_ads_developer_token', 'LOCAL SAMPLE ONLY');
    perform vault.create_secret('sampletokenforlocalvisualqaonlynotarealmetatoken0000', 'meta_ads_token', 'LOCAL SAMPLE ONLY');
  end if;
end $$;
update app.integration_connections set status = 'connected', connected_at = now() - interval '3 days',
  config = config || jsonb_build_object('last_check_at', now() - interval '2 hours', 'key_source', 'search_console', 'last_error', null)
where provider in ('google_ads', 'meta_ads');
insert into app.ad_accounts (provider, external_id, name, currency, time_zone, product)
values ('google_ads', '1234567890', 'Orgpuls — Google Ads', 'NOK', 'Europe/Oslo', 'orgpuls'), ('meta_ads', '987654321', 'Orgpuls', 'NOK', 'Europe/Oslo', 'orgpuls')
on conflict do nothing;
create temp table g_ad (provider text, campaign text, ad text, headline text, imp int, ctr0 numeric, ctr1 numeric, cpc numeric, reach numeric);
insert into g_ad values
  ('google_ads', '111', '9001', 'Er dere dekket av lovkravet fra 1. januar?', 900, .062, .060, 9.5, null),
  ('google_ads', '111', '9002', 'Gratis mal for medarbeiderundersøkelse', 700, .079, .078, 6.0, null),
  ('google_ads', '112', '9003', 'Orgpuls — medarbeiderundersøkelse', 300, .041, .040, 4.0, null),
  ('meta_ads', '211', '8001', 'Prøv gratis i 30 dager', 1400, .011, .005, 12.0, .55),
  ('meta_ads', '212', '8002', 'Medarbeiderundersøkelse på 18 minutter', 1100, .009, .009, 14.0, .7),
  ('meta_ads', '212', '8003', 'Fem er gulvet. Anonymt, alltid.', 800, .014, .013, 11.0, .72);
-- each ad's day: impressions with a weekday swing; its click-through moves from ctr0 (two weeks back) to ctr1 (this week)
create temp table g_ad_day as
select a.*, d::date as day, (a.imp * (case when extract(dow from d) in (0, 6) then .6 else 1 end) * (0.85 + random() * .3))::int impressions,
       a.ctr0 + (a.ctr1 - a.ctr0) * greatest(0, least(1, (14 - ((now() at time zone 'Europe/Oslo')::date - d::date)) / 7.0)) ctr
from g_ad a cross join generate_series((now() at time zone 'Europe/Oslo')::date - 60, (now() at time zone 'Europe/Oslo')::date - 1, interval '1 day') d;
select public.worker_ads_import((select id from app.ad_accounts where provider = 'google_ads' and external_id = '1234567890'),
  (now() at time zone 'Europe/Oslo')::date - 60, (now() at time zone 'Europe/Oslo')::date - 1,
  '[{"id": "111", "name": "Lovkrav — Q4 (Search)", "status": "live", "kind": "search", "utm_campaign": "lovkrav-q4"},
    {"id": "112", "name": "Merkevare — Orgpuls", "status": "live", "kind": "search"},
    {"id": "113", "name": "Høstundersøkelse 2025", "status": "ended", "kind": "search", "starts_on": "2025-09-01", "ends_on": "2025-10-15"}]',
  (select jsonb_agg(jsonb_build_object('id', ad, 'campaign', campaign, 'headline', headline, 'status', 'live')) from g_ad where provider = 'google_ads'),
  (select jsonb_agg(x) from (
     select jsonb_build_object('level', 'ad', 'id', ad, 'day', day, 'impressions', impressions, 'clicks', round(impressions * ctr), 'spend', round(impressions * ctr * cpc, 2),
                               'conversions', round(impressions * ctr * .08)) x from g_ad_day where provider = 'google_ads'
     union all
     select jsonb_build_object('level', 'campaign', 'id', campaign, 'day', day, 'impressions', sum(impressions), 'clicks', sum(round(impressions * ctr)),
                               'spend', sum(round(impressions * ctr * cpc, 2)), 'conversions', sum(round(impressions * ctr * .08)))
     from g_ad_day where provider = 'google_ads' group by campaign, day) y));
select public.worker_ads_import((select id from app.ad_accounts where provider = 'meta_ads' and external_id = '987654321'),
  (now() at time zone 'Europe/Oslo')::date - 60, (now() at time zone 'Europe/Oslo')::date - 1,
  '[{"id": "211", "name": "Retargeting /pris", "status": "live", "kind": "outcome_traffic", "utm_campaign": "meta-retarget"},
    {"id": "212", "name": "HR-ledere — video", "status": "paused", "kind": "outcome_leads"}]',
  (select jsonb_agg(jsonb_build_object('id', ad, 'campaign', campaign, 'headline', headline, 'status', 'live')) from g_ad where provider = 'meta_ads'),
  (select jsonb_agg(x) from (
     select jsonb_build_object('level', 'ad', 'id', ad, 'day', day, 'impressions', impressions, 'clicks', round(impressions * ctr), 'spend', round(impressions * ctr * cpc, 2),
                               'conversions', round(impressions * ctr * .05), 'reach', round(impressions * reach)) x from g_ad_day where provider = 'meta_ads'
     union all
     select jsonb_build_object('level', 'campaign', 'id', campaign, 'day', day, 'impressions', sum(impressions), 'clicks', sum(round(impressions * ctr)),
                               'spend', sum(round(impressions * ctr * cpc, 2)), 'conversions', sum(round(impressions * ctr * .05)), 'reach', sum(round(impressions * reach)))
     from g_ad_day where provider = 'meta_ads' group by campaign, day) y));
