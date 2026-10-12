-- v3_growth_invariants.sql — Growth v3 (0083): Google Ads keywords imported read only by the worker alone; the campaign
-- card's days (spend only from the ad platforms, signups from the tracker), ads and keywords with their own figures and
-- signups by utm_content / utm_term only where the links carry them, under the campaigns' report rights; an email sequence's
-- results per step under each email's report rights; the open rate by send weekday and hour (Oslo, a cell needs 20
-- delivered, the best time and its window derived from the cells); and «Send all steps at the best time»: a per-sequence
-- window (none by default) that only the editor's rights set, and that the engine honours — an email step reached outside
-- it waits for the next slot, asks «stop when» again then, and sends inside it.
\ir _helpers.psql
begin;

create or replace function pg_temp.expect_detail(p_sql text, p_message text, p_detail text, p_label text) returns void language plpgsql as $$
declare v_msg text; v_det text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg = p_message and coalesce(v_det, '') = coalesce(p_detail, '') then raise notice 'ok %', p_label; return; end if;
    raise exception 'FAIL %: expected «%» («%»), got «%» («%»)', p_label, p_message, p_detail, v_msg, v_det;
  end;
  raise exception 'FAIL %: expected «%», but it succeeded', p_label, p_message;
end $$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('ad_platform_keywords', 'ad_keyword_daily', 'sequence_send_windows')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select')
         or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the new tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('ad_platform_keywords', 'ad_keyword_daily', 'sequence_send_windows')) = 3, 'all three exist');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_ads_keywords(uuid, date, date, jsonb, jsonb, jsonb)'::regprocedure, 'execute')
                     and has_function_privilege('service_role', 'public.worker_ads_keywords(uuid, date, date, jsonb, jsonb, jsonb)'::regprocedure, 'execute'),
                     'only the worker imports keywords');
select pg_temp.check(has_function_privilege('authenticated', f::regprocedure, 'execute') and not has_function_privilege('anon', f::regprocedure, 'execute'),
                     'signed in only: ' || f)
from unnest(array['public.ad_campaign_detail(uuid, int)', 'public.email_send_times(text, int)', 'public.simple_sequence_results(uuid, int)',
                  'public.simple_sequence_send_window(uuid, text, boolean)']) f;
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.send_window_open(timestamptz, smallint[], int)', 'app.send_window_next(timestamptz, smallint[], int)',
                  'app.sequence_send_hold(app.workflow_runs, text)', 'app.email_send_cells(text, int)', 'app.email_best_time(text, int)',
                  'app.sequence_email_figures(app.campaigns, timestamptz)']) f;
select pg_temp.check(position('app.sequence_send_hold(p_run, p_key)' in pg_get_functiondef('app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)'::regprocedure)) > 0
                     and app.project_actions_wired(), 'the engine''s email step asks for the send window, and keeps its other actions');

-- ---------------------------------------------------------------------------
-- fixtures: an application's site, two Sentral campaigns (one platform-linked, one with typed spend), a Google account
create temp table t_ids (k text primary key, id uuid);
create temp table t_days as select (now() at time zone 'Europe/Oslo')::date today;
insert into t_ids select 'tor', id from app.admins where email = 'tor@orgpuls.no';
insert into t_ids select 'jonas', id from app.admins where email = 'jonas@orgpuls.no';
with s as (insert into app.web_sites (hostname, product) values ('v3-growth.example', 'skiftly') returning id) insert into t_ids select 'site', id from s;
with c as (insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign, starts_on, state, created_by)
           values ('skiftly', 'V3 Search', 'google_ads', 'google-ads', 'cpc', 'v3-search', (select today from t_days) - 10, 'live', (select id from t_ids where k = 'tor'))
           returning id) insert into t_ids select 'google', id from c;
with c as (insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign, state, created_by)
           values ('skiftly', 'V3 Typed', 'linkedin', 'linkedin', 'paid_social', 'v3-typed', 'live', (select id from t_ids where k = 'jonas'))
           returning id) insert into t_ids select 'typed', id from c;
insert into app.marketing_spend (campaign, month, channel, amount) values ('v3-typed', date_trunc('month', (select today from t_days))::date, 'paid_social', 5000);
with a as (insert into app.ad_accounts (provider, external_id, name, currency, time_zone, product) values ('google_ads', '5550001111', 'V3 Google', 'NOK', 'Europe/Oslo', 'skiftly')
           returning id) insert into t_ids select 'acc', id from a;
with a as (insert into app.ad_accounts (provider, external_id, name, currency, product) values ('meta_ads', '5550002222', 'V3 Meta', 'NOK', 'skiftly')
           returning id) insert into t_ids select 'meta', id from a;
-- the import: campaign 901 carries v3-search, so it counts as «V3 Search»; a day with spend, a day with none, a missing day
select public.worker_ads_import((select id from t_ids where k = 'acc'), (select today from t_days) - 20, (select today from t_days) - 1,
  '[{"id": "901", "name": "V3 Search (Google)", "status": "live", "utm_campaign": "v3-search"}]',
  '[{"id": "9901", "campaign": "901", "headline": "Vaktplan på minutter", "status": "live"}, {"id": "9902", "campaign": "901", "name": "Turnus uten Excel", "status": "live"}]',
  jsonb_build_array(
    jsonb_build_object('level', 'campaign', 'id', '901', 'day', (select today from t_days) - 3, 'impressions', 900, 'clicks', 60, 'spend', 100),
    jsonb_build_object('level', 'campaign', 'id', '901', 'day', (select today from t_days) - 2, 'impressions', 10, 'clicks', 0, 'spend', 0),
    jsonb_build_object('level', 'campaign', 'id', '901', 'day', (select today from t_days) - 15, 'impressions', 10, 'clicks', 1, 'spend', 7),
    jsonb_build_object('level', 'ad', 'id', '9901', 'day', (select today from t_days) - 3, 'impressions', 600, 'clicks', 40, 'spend', 70),
    jsonb_build_object('level', 'ad', 'id', '9902', 'day', (select today from t_days) - 3, 'impressions', 300, 'clicks', 20, 'spend', 30)));
select pg_temp.check((select ad_campaign_id from app.ad_platform_campaigns where account_id = (select id from t_ids where k = 'acc') and external_id = '901')
                     = (select id from t_ids where k = 'google'), 'the platform campaign counts as the Sentral campaign with its utm_campaign');

-- ---------------------------------------------------------------------------
-- keywords: the worker alone, Google only, the window replaced, a keyword no longer listed ended, the bidding kept
select pg_temp.expect_detail(format($$select public.worker_ads_keywords(%L, current_date - 5, current_date - 1, '[]', '[]')$$, (select id from t_ids where k = 'meta')),
                             'invalid', 'provider', 'keywords are Google''s only');
select pg_temp.expect_detail(format($$select public.worker_ads_keywords(%L, current_date - 1, current_date - 5, '[]', '[]')$$, (select id from t_ids where k = 'acc')),
                             'invalid', 'window', 'a window that ends before it starts is refused');
select public.worker_ads_keywords((select id from t_ids where k = 'acc'), (select today from t_days) - 20, (select today from t_days) - 1,
  '[{"id": "1", "ad_group": "77", "campaign": "901", "text": "Vaktplan app", "match_type": "exact", "status": "live"},
    {"id": "2", "ad_group": "77", "campaign": "901", "text": "turnus", "match_type": "BROAD", "status": "paused"},
    {"id": "x", "ad_group": "77", "campaign": "901", "text": "not an id", "status": "live"},
    {"id": "3", "ad_group": "77", "campaign": "901", "text": "  ", "status": "live"}]',
  jsonb_build_array(
    jsonb_build_object('id', '1', 'ad_group', '77', 'day', (select today from t_days) - 3, 'impressions', 500, 'clicks', 55, 'spend', 60.5, 'conversions', 2),
    jsonb_build_object('id', '1', 'ad_group', '77', 'day', (select today from t_days) - 2, 'impressions', 100, 'clicks', 5, 'spend', 4.5),
    jsonb_build_object('id', '2', 'ad_group', '77', 'day', (select today from t_days) - 3, 'impressions', 400, 'clicks', 10, 'spend', 39.5),
    jsonb_build_object('id', '2', 'ad_group', '77', 'day', (select today from t_days) - 30, 'impressions', 400, 'clicks', 10, 'spend', 39.5)),
  '[{"id": "901", "bidding": "MANUAL_CPC"}]');
select pg_temp.check((select count(*) from app.ad_platform_keywords where account_id = (select id from t_ids where k = 'acc')) = 2,
                     'only keywords with an id and a text are kept');
select pg_temp.check((select match_type is null from app.ad_platform_keywords where account_id = (select id from t_ids where k = 'acc') and criterion_id = '2'),
                     'a match type outside exact, phrase and broad is not guessed');
select pg_temp.check((select count(*) from app.ad_keyword_daily where account_id = (select id from t_ids where k = 'acc')) = 3, 'a day outside the window is not stored');
select pg_temp.check((select bidding from app.ad_platform_campaigns where account_id = (select id from t_ids where k = 'acc') and external_id = '901') = 'manual_cpc',
                     'the campaign''s bidding strategy is kept, lower case');
select public.worker_ads_keywords((select id from t_ids where k = 'acc'), (select today from t_days) - 2, (select today from t_days) - 1,
  '[{"id": "1", "ad_group": "77", "campaign": "901", "text": "Vaktplan app", "match_type": "exact", "status": "live"}]',
  jsonb_build_array(jsonb_build_object('id', '1', 'ad_group', '77', 'day', (select today from t_days) - 2, 'impressions', 100, 'clicks', 6, 'spend', 5)));
select pg_temp.check((select status from app.ad_platform_keywords where account_id = (select id from t_ids where k = 'acc') and criterion_id = '2') = 'ended',
                     'a keyword Google no longer lists is kept as ended');
select pg_temp.check((select clicks from app.ad_keyword_daily where account_id = (select id from t_ids where k = 'acc') and criterion_id = '1' and day = (select today from t_days) - 2) = 6
                 and (select clicks from app.ad_keyword_daily where account_id = (select id from t_ids where k = 'acc') and criterion_id = '1' and day = (select today from t_days) - 3) = 55,
                     'the window is replaced; days before it stay');
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name in ('ad_platform_keywords', 'ad_keyword_daily')
                                 and column_name ~ 'search|query|term'), 'no search term is stored, only the advertiser''s keywords');

-- ---------------------------------------------------------------------------
-- the tracker: a visit from the keyword that finished signing up three days ago, one that did not, one that finished today
create or replace function pg_temp.visit(p_utm jsonb, p_day date, p_done boolean) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into app.web_sessions (site_id, day, visitor_hash, started_at, utm)
  values ((select id from t_ids where k = 'site'), p_day, md5(random()::text), (p_day + time '10:00') at time zone 'Europe/Oslo', p_utm) returning id into v;
  if p_done then insert into app.web_events (session_id, at, name) values (v, (p_day + time '10:05') at time zone 'Europe/Oslo', 'signup_completed'); end if;
  return v;
end $$;
select pg_temp.visit('{"utm_campaign": "v3-search", "utm_term": "vaktplan APP"}', (select today from t_days) - 3, true);
select pg_temp.visit('{"utm_campaign": "v3-search", "utm_term": "turnus"}', (select today from t_days) - 3, false);
select pg_temp.visit('{"utm_campaign": "v3-search"}', (select today from t_days), true);

select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_d as select public.ad_campaign_detail((select id from t_ids where k = 'google')) d;
select pg_temp.check((select d ->> 'spend_source' = 'platform' and d ->> 'currency' = 'NOK' and jsonb_array_length(d -> 'days') = 21
                             and (d ->> 'to')::date = (select today from t_days) - 1 from t_d), '21 days to yesterday, spend from the platform, in its currency');
select pg_temp.check((select (x ->> 'spend')::numeric from t_d, jsonb_array_elements(d -> 'days') x where (x ->> 'day')::date = (select today from t_days) - 3) = 100
                 and (select (x ->> 'spend')::numeric from t_d, jsonb_array_elements(d -> 'days') x where (x ->> 'day')::date = (select today from t_days) - 2) = 0
                 and (select x -> 'spend' from t_d, jsonb_array_elements(d -> 'days') x where (x ->> 'day')::date = (select today from t_days) - 4) = 'null'::jsonb,
                     'a day''s spend is the platform''s: a zero day is 0, a day without a row has none');
select pg_temp.check((select (x ->> 'signups')::int from t_d, jsonb_array_elements(d -> 'days') x where (x ->> 'day')::date = (select today from t_days) - 3) = 1
                 and (select sum((x ->> 'signups')::int) from t_d, jsonb_array_elements(d -> 'days') x) = 1,
                     'signups per day are the tracker''s finished signups with the utm_campaign; today''s is outside the window');
select pg_temp.check((select (d ->> 'utm_term')::boolean and not (d ->> 'utm_content')::boolean from t_d), 'the links carry utm_term, not utm_content');
select pg_temp.check((select (k ->> 'signups')::int = 1 and (k ->> 'clicks')::int = 61 and (k ->> 'spend')::numeric = 65.5 from t_d, jsonb_array_elements(d -> 'keywords') k where k ->> 'id' = '1')
                 and (select (k ->> 'signups')::int = 0 from t_d, jsonb_array_elements(d -> 'keywords') k where k ->> 'id' = '2'),
                     'a keyword''s clicks and cost are its own; its signups match utm_term');
select pg_temp.check((select bool_and(a -> 'signups' = 'null'::jsonb) and count(*) = 2 from t_d, jsonb_array_elements(d -> 'ads') a),
                     'without utm_content an ad has no signups («—»), never an allocation');
select pg_temp.visit('{"utm_campaign": "v3-search", "utm_content": "9901"}', (select today from t_days) - 3, true);
select pg_temp.check((select (a ->> 'signups')::int from jsonb_array_elements(public.ad_campaign_detail((select id from t_ids where k = 'google')) -> 'ads') a where a ->> 'id' = '9901') = 1
                 and (select (a ->> 'signups')::int from jsonb_array_elements(public.ad_campaign_detail((select id from t_ids where k = 'google')) -> 'ads') a where a ->> 'id' = '9902') = 0,
                     'once the links carry utm_content, each ad counts its own signups');
select pg_temp.check((select (d -> 'platforms' -> 0 ->> 'bidding') = 'manual_cpc' and (d -> 'platforms' -> 0 ->> 'account') = '5550001111' from t_d),
                     'the platform campaign and its bidding come along, for the tips and their links');
create temp table t_ty as select public.ad_campaign_detail((select id from t_ids where k = 'typed')) d;
select pg_temp.check((select d ->> 'spend_source' = 'typed' and jsonb_array_length(d -> 'platforms') = 0 and jsonb_array_length(d -> 'ads') = 0
                             and not exists (select 1 from jsonb_array_elements(d -> 'days') x where x -> 'spend' <> 'null'::jsonb) from t_ty),
                     'typed spend is per month: no day has spend, never a share of the month');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error(format('select public.ad_campaign_detail(%L)', (select id from t_ids where k = 'google')), 'forbidden', 'without Campaigns › See there is no card');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format('select public.ad_campaign_detail(%L)', (select id from t_ids where k = 'typed')), 'forbidden', 'campaigns:reports_others',
                             'another person''s campaign needs the reports of others');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(public.ad_campaign_detail((select id from t_ids where k = 'typed')) ->> 'spend_source' = 'typed', 'Read-only with the reports of others reads it');
select pg_temp.expect_error(format('select public.ad_campaign_detail(%L)', gen_random_uuid()), 'not_found', 'an unknown campaign is not found');
select pg_temp.as_nobody();
select pg_temp.expect_error(format('select public.ad_campaign_detail(%L)', (select id from t_ids where k = 'google')), 'not_signed_in', 'nobody signed out reads it');

-- ---------------------------------------------------------------------------
-- email: one sequence of two emails, sends last week; the application's best time; results per step
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_seq as select public.simple_sequence_save(null, '{"name": "V3 onboarding", "trigger": "form_submitted", "exit": "never",
  "steps": [{"kind": "email", "text": "Velkommen"}, {"kind": "wait", "days": 2}, {"kind": "email", "text": "Last opp ansattlisten"}]}') r;
insert into t_ids select 'seq', (r ->> 'id')::uuid from t_seq;
insert into t_ids select 'mail_a', (r -> 'simple' -> 'steps' -> 0 ->> 'campaign_id')::uuid from t_seq;
insert into t_ids select 'mail_b', (r -> 'simple' -> 'steps' -> 2 ->> 'campaign_id')::uuid from t_seq;
select pg_temp.check((select send_window from (select public.simple_sequence_results((select id from t_ids where k = 'seq')) ->> 'send_window' send_window) x) is null,
                     'a sequence has no send window by default');
select pg_temp.expect_detail(format('select public.simple_sequence_send_window(%L, %L, true)', (select id from t_ids where k = 'seq'), 'skiftly'), 'invalid', 'no_best_time',
                             'without 20 delivered in a cell there is no best time to set');
update app.campaigns set product = 'skiftly' where id in (select id from t_ids where k in ('mail_a', 'mail_b'));
-- two people in different organisations: one uploaded its employee list long ago, the other only now
create temp table t_pp as
select (select p.id from app.people p where p.organization_id is not null and p.deleted_at is null and p.email is not null order by p.id limit 1) early,
       (select p.id from app.people p where p.organization_id is not null and p.deleted_at is null and p.email is not null
          and p.organization_id <> (select q.organization_id from app.people q where q.organization_id is not null and q.deleted_at is null and q.email is not null order by q.id limit 1)
        order by p.id limit 1) late;
create temp table t_acc as
select (select o.account_id from app.organizations o join app.people p on p.organization_id = o.id where p.id = (select early from t_pp)) early,
       (select o.account_id from app.organizations o join app.people p on p.organization_id = o.id where p.id = (select late from t_pp)) late;
select pg_temp.check((select early is not null and late is not null and early <> late from t_acc)
                 and app.org_milestone((select organization_id from app.people where id = (select early from t_pp)), 'employees_uploaded'),
                     'fixture: two organisations of their own accounts, the first with its employee list uploaded');
update app.activation_milestones m set reached_at = case when ap.account_id = (select early from t_acc) then now() - interval '200 days' else now() end
from app.account_products ap
where ap.product = m.product and ap.tenant_id = m.tenant_id and m.key = 'employees_uploaded' and ap.account_id in ((select early from t_acc), (select late from t_acc));
-- last week's Tuesday, Wednesday and Thursday at 08 (Oslo), and a Monday at 13
create temp table t_tue as select (date_trunc('week', now() at time zone 'Europe/Oslo') - interval '6 days')::date d;
create or replace function pg_temp.sends(p_mail text, p_person uuid, p_day date, p_hour int, p_n int, p_opened int, p_clicked int, p_tag text) returns void language sql as $$
  insert into app.campaign_recipients (campaign_id, person_id, email, send_key, state, sent_at, delivered_at, first_open_at, first_click_at)
  select (select id from t_ids where k = p_mail), p_person, 'v3-' || p_tag || g || '@example.invalid', 'v3' || p_tag || '-' || g, 'delivered',
         (p_day + make_time(p_hour, 10, 0)) at time zone 'Europe/Oslo', (p_day + make_time(p_hour, 11, 0)) at time zone 'Europe/Oslo',
         case when g <= p_opened then (p_day + make_time(p_hour, 30, 0)) at time zone 'Europe/Oslo' end,
         case when g <= p_clicked then (p_day + make_time(p_hour, 40, 0)) at time zone 'Europe/Oslo' end
  from generate_series(1, p_n) g
$$;
select pg_temp.sends('mail_a', (select early from t_pp), (select d from t_tue), 8, 25, 15, 2, 'a');
select pg_temp.sends('mail_a', (select early from t_pp), (select d from t_tue) + 1, 8, 30, 16, 3, 'b');
select pg_temp.sends('mail_b', (select early from t_pp), (select d from t_tue), 8, 22, 11, 1, 'c');
select pg_temp.sends('mail_b', (select late from t_pp), (select d from t_tue) + 2, 8, 20, 5, 1, 'd');
select pg_temp.sends('mail_b', (select late from t_pp), (select d from t_tue) - 1, 13, 10, 9, 0, 'e');
update app.campaign_recipients set unsubscribed_at = sent_at + interval '1 day' where send_key = 'v3c-1';
select pg_temp.visit(jsonb_build_object('utm_campaign', (select utm_campaign from app.campaigns where id = (select id from t_ids where k = 'mail_a'))), (select d from t_tue), true);

create temp table t_t as select public.email_send_times('skiftly') t;
select pg_temp.check((select (t ->> 'min')::int = 20 and (t ->> 'days')::int = 90 from t_t), 'the window is 90 days and a cell needs 20 delivered');
select pg_temp.check((select (c ->> 'delivered')::int = 47 and (c ->> 'opened')::int = 26 from t_t, jsonb_array_elements(t -> 'cells') c where (c ->> 'dow')::int = 2 and (c ->> 'hour')::int = 8),
                     'a cell is delivered and human opens by the send''s Oslo weekday and hour, over the application''s email');
select pg_temp.check((select t -> 'best' ->> 'dow' = '2' and t -> 'best' ->> 'hour' = '8' and t -> 'best' -> 'days' = '[2, 3]'::jsonb from t_t),
                     'best is the highest open rate with 20 delivered (Mon 13 has too few); the window adds days at that hour within five points (Thu is not)');
update app.campaigns set tracking = false where id = (select id from t_ids where k = 'mail_b');
select pg_temp.check((select (c ->> 'delivered')::int from jsonb_array_elements(public.email_send_times('skiftly') -> 'cells') c where (c ->> 'dow')::int = 2 and (c ->> 'hour')::int = 8) = 25,
                     'an email that does not track opens is left out');
update app.campaigns set tracking = true where id = (select id from t_ids where k = 'mail_b');

create temp table t_r as select public.simple_sequence_results((select id from t_ids where k = 'seq')) r;
select pg_temp.check((select jsonb_array_length(r -> 'emails') = 2 and (r -> 'emails' -> 0 ->> 'step')::int = 0 and (r -> 'emails' -> 1 ->> 'step')::int = 2
                             and (r ->> 'days')::int = 30 from t_r), 'one row per email step, in order, over 30 days');
select pg_temp.check((select f ->> 'sent' = '55' and f ->> 'delivered' = '55' and f ->> 'opens' = '31' and f ->> 'clicks' = '5' and f ->> 'signups' = '1'
                      from (select r -> 'emails' -> 0 -> 'figures' f from t_r) x), 'an email''s sends, human opens, clicks and the tracker''s signups from its links');
select pg_temp.check((select f ->> 'sent' = '52' and f ->> 'unsubscribed' = '1' and (f ->> 'with_org')::int = 52 and (f ->> 'past_employees')::int = 22
                      from (select r -> 'emails' -> 1 -> 'figures' f from t_r) x),
                     'unsubscribes, and the sends whose organisation had uploaded its employee list before the send');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select bool_and(e -> 'figures' = 'null'::jsonb) from jsonb_array_elements(public.simple_sequence_results((select id from t_ids where k = 'seq')) -> 'emails') e),
                     'another person''s email figures need the reports of others');
select pg_temp.check((select jsonb_array_length(public.email_send_times('skiftly') -> 'cells') = 0 and public.email_send_times('skiftly') -> 'best' = 'null'::jsonb),
                     'the heatmap counts only emails whose reports the caller may see');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error($$select public.email_send_times('skiftly')$$, 'forbidden', 'the heatmap needs Campaigns › See');
select pg_temp.as_nobody();
select pg_temp.expect_error(format('select public.simple_sequence_results(%L)', (select id from t_ids where k = 'seq')), 'not_signed_in', 'nobody signed out reads results');

-- ---------------------------------------------------------------------------
-- «Send all steps at the best time»: the editor's rights; the window is the application's best now
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format('select public.simple_sequence_send_window(%L, %L, true)', (select id from t_ids where k = 'seq'), 'skiftly'), 'forbidden', 'global:configure',
                             'Read-only does not set another person''s window');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format('select public.simple_sequence_send_window(%L, %L, true)', (select id from t_ids where k = 'seq'), 'skiftly'), 'forbidden', 'global:configure',
                             'nor does Marketing without Global › Configure');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format('select public.simple_sequence_send_window(%L, %L, true)', (select id from t_ids where k = 'seq'), 'nowhere'), 'invalid', 'product',
                             'an unknown application is refused');
select pg_temp.expect_error(format('select public.simple_sequence_send_window(%L, %L, true)', gen_random_uuid(), 'skiftly'), 'not_found', 'an unknown sequence is not found');
select public.simple_sequence_send_window((select id from t_ids where k = 'seq'), 'skiftly', true);
select pg_temp.check((select days = array[2, 3]::smallint[] and hour = 8 and product = 'skiftly' and set_by = (select id from t_ids where k = 'tor')
                      from app.sequence_send_windows where workflow_id = (select id from t_ids where k = 'seq')), 'the window is the best time''s days and hour');
select pg_temp.check((public.simple_sequence_results((select id from t_ids where k = 'seq')) -> 'send_window' ->> 'hour')::int = 8, 'the results carry the window');
select pg_temp.check(exists (select 1 from app.audit where action = 'sequence.send_window_set' and target_id = (select id from t_ids where k = 'seq')::text
                             and detail ->> 'on' = 'true' and detail ->> 'hour' = '8' and not detail ? 'name'), 'the change is audited with ids and the slot only');
select public.simple_sequence_send_window((select id from t_ids where k = 'seq'), 'skiftly', false);
select pg_temp.check(not exists (select 1 from app.sequence_send_windows where workflow_id = (select id from t_ids where k = 'seq')), 'off removes the window');

-- ---------------------------------------------------------------------------
-- the slot: Oslo's clock, across the change from summer time (25 Oct 2026) and to it (28 Mar 2027)
select pg_temp.check(app.send_window_next('2026-10-24 12:00+02', array[1]::smallint[], 8) = '2026-10-26 07:00+00'
                 and app.send_window_next('2026-10-26 07:30+01', array[1]::smallint[], 8) = '2026-10-26 07:00+00'
                 and app.send_window_next('2026-10-26 08:30+01', array[1]::smallint[], 8) = '2026-11-02 07:00+00'
                 and app.send_window_next('2026-10-20 09:00+02', array[2, 3, 4]::smallint[], 8) = '2026-10-21 06:00+00'
                 and app.send_window_next('2027-03-27 12:00+01', array[7]::smallint[], 8) = '2027-03-28 06:00+00',
                     'the next slot is 08:00 Oslo on the next day the window names, summer or winter');
select pg_temp.check(app.send_window_open('2026-10-27 08:59+01', array[2]::smallint[], 8) and not app.send_window_open('2026-10-27 09:00+01', array[2]::smallint[], 8)
                 and not app.send_window_open('2026-10-28 08:10+01', array[2]::smallint[], 8), 'inside the window is that hour on those days');

-- the engine: an email step outside the window waits for the slot, asks «stop when» again, then sends
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_s2 as select public.simple_sequence_save(null, '{"name": "V3 timed", "trigger": "form_submitted", "exit": "paying",
  "steps": [{"kind": "wait", "days": 1}, {"kind": "email", "text": "Hei"}]}') r;
create temp table t_s3 as select public.simple_sequence_save(null, '{"name": "V3 untimed", "trigger": "form_submitted", "exit": "never",
  "steps": [{"kind": "email", "text": "Hei igjen"}]}') r;
update app.campaigns set status = 'active', rendered_html = '<p>Hei</p>'
where id in ((select (r -> 'simple' -> 'steps' -> 1 ->> 'campaign_id')::uuid from t_s2), (select (r -> 'simple' -> 'steps' -> 0 ->> 'campaign_id')::uuid from t_s3));
create temp table t_lead as
select l.id, l.person_id from app.leads l join app.people p on p.id = l.person_id
where p.deleted_at is null and p.email is not null and not app.wf_match('lead', l.id, '[[{"f":"org_paying"}]]') order by l.id limit 1;
create temp table t_hour as select (extract(hour from now() at time zone 'Europe/Oslo')::int + 3) % 24 closed, extract(hour from now() at time zone 'Europe/Oslo')::int open;
insert into app.sequence_send_windows (workflow_id, days, hour) select (r ->> 'id')::uuid, array[1, 2, 3, 4, 5, 6, 7]::smallint[], (select closed from t_hour) from t_s2;
select pg_temp.as_nobody();
create temp table t_run as select app.wf_start((select (r ->> 'id')::uuid from t_s2), 'lead', (select id from t_lead), null, null) id;
select pg_temp.check((select state = 'waiting' and cursor = 'x2' from app.workflow_runs where id = (select id from t_run)), 'the wait comes first');
update app.workflow_runs set resume_at = now() - interval '1 second' where id = (select id from t_run);
select app.wf_resume_due();
select pg_temp.check((select state = 'waiting' and cursor = 'x2' and resume_at = app.send_window_next(now(), array[1, 2, 3, 4, 5, 6, 7]::smallint[], (select closed from t_hour))
                      from app.workflow_runs where id = (select id from t_run)),
                     'outside the window the email waits for the next slot, and «stop when» is asked again then');
select pg_temp.check(not exists (select 1 from app.campaign_recipients where campaign_id = (select (r -> 'simple' -> 'steps' -> 1 ->> 'campaign_id')::uuid from t_s2)),
                     'nothing is queued before the slot');
select pg_temp.check(exists (select 1 from app.workflow_run_steps where run_id = (select id from t_run) and kind = 'campaign_action' and output ? 'held_until'),
                     'the run''s log says until when it is held');
update app.sequence_send_windows set hour = (select open from t_hour) where workflow_id = (select (r ->> 'id')::uuid from t_s2);
update app.workflow_runs set resume_at = now() - interval '1 second' where id = (select id from t_run);
select app.wf_resume_due();
select pg_temp.check(exists (select 1 from app.campaign_recipients where campaign_id = (select (r -> 'simple' -> 'steps' -> 1 ->> 'campaign_id')::uuid from t_s2)
                                                                      and person_id = (select person_id from t_lead))
                 and (select state from app.workflow_runs where id = (select id from t_run)) = 'completed',
                     'at the slot the email goes out (queued, or skipped for a reason of its own) and the run completes');
create temp table t_run3 as select app.wf_start((select (r ->> 'id')::uuid from t_s3), 'lead', (select id from t_lead), null, null) id;
select pg_temp.check(exists (select 1 from app.campaign_recipients where campaign_id = (select (r -> 'simple' -> 'steps' -> 0 ->> 'campaign_id')::uuid from t_s3))
                 and (select state from app.workflow_runs where id = (select id from t_run3)) = 'completed',
                     'without a window (the default) the email goes when its step is reached');

rollback;
