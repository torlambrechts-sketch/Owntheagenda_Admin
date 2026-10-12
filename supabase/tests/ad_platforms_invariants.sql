-- ad_platforms_invariants.sql — Growth › the ad platforms (0077): their tables are closed and their workers the service
-- role's; only the owner hands over credentials (fresh second factor, an intake number bound to the platform, each name
-- checked by shape) and starts LinkedIn's sign-in (a one-time state, back only to the app's own addresses); an import
-- links each platform campaign to a Sentral campaign (by its utm_campaign, or one made for it), replaces whole months of
-- typed spend with the platform's and refuses typing over them; Campaigns › Edit others' may count a platform campaign as
-- another campaign; the read needs Campaigns › See and never carries a credential.
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
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('ad_accounts', 'ad_platform_campaigns', 'ad_platform_ads', 'ad_daily', 'ads_oauth_states')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the ad platforms'' tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('ad_accounts', 'ad_platform_campaigns', 'ad_platform_ads', 'ad_daily', 'ads_oauth_states')) = 5, 'all five exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute') and has_function_privilege('service_role', f::regprocedure, 'execute'),
                     'only the service role runs ' || f)
from unnest(array['public.worker_ads_targets()', 'public.worker_ads_accounts(text, jsonb)', 'public.worker_ads_import(uuid, date, date, jsonb, jsonb, jsonb)',
                  'public.worker_ads_failed(uuid, text)', 'public.worker_ads_result(text, boolean, text, uuid)', 'public.worker_ads_oauth_state(text)',
                  'public.worker_ads_tokens(text, text, int, int, uuid)']) f;
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.vault_put(text, text, text)', 'app.store_ad_secrets(text, jsonb)', 'app.ads_sync_spend(uuid)', 'app.ads_spend_wanted()', 'app.ads_tick()']) f;
select pg_temp.check(char_length(public.product_secret('ads_worker_secret')) = 64, 'the nightly job''s key is generated in Vault');

-- ---------------------------------------------------------------------------
-- credentials: the owner, a fresh second factor, an intake number bound to the platform
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.ads_intake('google_ads')$$, 'forbidden', 'owner_only', 'only the owner opens an intake for an ad platform');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.ads_intake('google_ads')$$, 'forbidden', 'fresh_mfa', 'the intake needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.ads_intake('tiktok_ads')$$, 'invalid', 'provider', 'a known platform');
create temp table t_codes as select public.ads_intake('google_ads') ->> 'intake_code' g1, public.ads_intake('google_ads') ->> 'intake_code' g2,
                                    public.ads_intake('meta_ads') ->> 'intake_code' m1, public.ads_intake('linkedin_ads') ->> 'intake_code' l1;
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"meta_ads_token": "%s"}')$$, (select g1 from t_codes), repeat('A', 60)), 'invalid', 'name',
                             'a Google Ads number stores Google Ads'' names and nothing else');
select pg_temp.check((public.store_product_secrets((select g2 from t_codes), jsonb_build_object('google_ads_developer_token', 'AbCdEf0123456789xyz')) ->> 'stored')::int = 1,
                     'a Google Ads number stores the developer token');
select pg_temp.check(public.product_secret('google_ads_developer_token') = 'AbCdEf0123456789xyz', 'it lands in Vault, readable by the service role');
select pg_temp.check((public.store_product_secrets((select g2 from t_codes), '{}') ->> 'ok')::boolean = false, 'an intake number is used once');
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"meta_ads_token": "short"}')$$, (select m1 from t_codes)), 'invalid', 'name', 'a token has its shape');
select pg_temp.check((public.store_product_secrets((select l1 from t_codes), jsonb_build_object('linkedin_ads_client_secret', 'S3cr3t.value')) ->> 'stored')::int = 1,
                     'LinkedIn''s client secret is stored');

select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.ads_settings_set('google_ads', '{"login_customer_id": "123-456-7890"}')$$, 'forbidden', 'owner_only', 'only the owner sets a platform');
select pg_temp.as_mfa('tor@orgpuls.no');
select public.ads_settings_set('google_ads', '{"login_customer_id": "123-456-7890", "key_source": "search_console"}');
select pg_temp.check((select config ->> 'login_customer_id' = '1234567890' and config ->> 'key_source' = 'search_console' from app.integration_connections where provider = 'google_ads'),
                     'the manager account is kept without dashes, with the key to sign in with');
select pg_temp.expect_detail($$select public.ads_settings_set('google_ads', '{"client_id": "abc"}')$$, 'invalid', 'client_id', 'a setting the platform does not have is refused');
select pg_temp.expect_detail($$select public.ads_oauth_start('https://admin.owntheagenda.com')$$, 'invalid', 'not_configured', 'LinkedIn''s sign-in needs the client id first');
select public.ads_settings_set('linkedin_ads', '{"client_id": "86abc123xyz"}');
update app.mail_settings set functions_url = coalesce(functions_url, 'https://qa.supabase.co') where id;
select pg_temp.expect_detail($$select public.ads_oauth_start('https://evil.example')$$, 'invalid', 'origin', 'the sign-in returns only to the app''s own addresses');
create temp table t_state as select public.ads_oauth_start('https://admin.owntheagenda.com') v;
select pg_temp.check((select v ->> 'client_id' = '86abc123xyz' and v ->> 'redirect_uri' like '%/functions/v1/ads-oauth' and v ->> 'scope' = 'r_ads r_ads_reporting'
                             and v ->> 'state' ~ '^[0-9a-f]{48}$' from t_state), 'a one-time state, the client id and the redirect address');

-- LinkedIn coming back: the state once, then the tokens into Vault
select pg_temp.as_service();
select pg_temp.check((select public.worker_ads_oauth_state(v ->> 'state') ->> 'origin' from t_state) = 'https://admin.owntheagenda.com', 'the state brings the owner back where they began');
select pg_temp.check((select public.worker_ads_oauth_state(v ->> 'state') from t_state) is null, 'and is used once');
select public.worker_ads_tokens(repeat('a', 40), repeat('r', 40), 5184000, 31536000, null);
select pg_temp.check(public.product_secret('linkedin_ads_access_token') = repeat('a', 40) and public.product_secret('linkedin_ads_refresh_token') = repeat('r', 40)
                     and (select (config ->> 'token_expires_at')::timestamptz > now() + interval '59 days' from app.integration_connections where provider = 'linkedin_ads'),
                     'the tokens land in Vault; only when they expire is kept outside');

-- ---------------------------------------------------------------------------
-- accounts, linked by the owner
select public.worker_ads_accounts('google_ads', '[{"id": "5550001111", "name": "QA Ads", "currency": "NOK", "time_zone": "Europe/Oslo"},
                                                  {"id": "5550002222", "name": "QA MCC", "manager": true}, {"id": "x", "name": "bad"}]');
select pg_temp.check((select count(*) from app.ad_accounts where provider = 'google_ads' and external_id in ('5550001111', '5550002222')) = 2
                     and not exists (select 1 from app.ad_accounts where name = 'bad'), 'the accounts the credentials may read; a bad id is ignored');
create temp table t_acc as select id from app.ad_accounts where provider = 'google_ads' and external_id = '5550001111';
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.ads_account_link(%L, 'orgpuls')$$, (select id from t_acc)), 'forbidden', 'owner_only', 'only the owner links an account');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_error(format($$select public.ads_account_link(%L, 'orgpuls')$$, (select id from app.ad_accounts where external_id = '5550002222')), 'not_found',
                            'a manager account counts for no application');
select public.ads_account_link((select id from t_acc), 'orgpuls');

-- ---------------------------------------------------------------------------
-- an import: a campaign matching a Sentral campaign by utm, one with none, one ended without activity
insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign, state) values ('orgpuls', 'QA lovkrav', 'google_ads', 'google-ads', 'cpc', 'qa-lovkrav', 'live');
-- typed spend for August (imported only in part) and September (imported whole)
create temp table t_m as select date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date m0;
insert into app.marketing_spend (campaign, month, channel, amount) select 'qa-lovkrav', m0 - interval '2 months', 'paid_search', 5000 from t_m;
insert into app.marketing_spend (campaign, month, channel, amount) select 'qa-lovkrav', m0 - interval '1 month', 'paid_search', 5000 from t_m;
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.worker_ads_import(%L, '2026-10-02', '2026-10-01', '[]', '[]', '[]')$$, (select id from t_acc)), 'invalid', 'window',
                             'a window runs forward');
create temp table t_imp as
select public.worker_ads_import((select id from t_acc), (m0 - interval '2 months' + interval '14 days')::date, (now() at time zone 'Europe/Oslo')::date - 1,
  '[{"id": "9111", "name": "Lovkrav (Search)", "status": "live", "utm_campaign": "QA-Lovkrav"},
    {"id": "9112", "name": "QA Merkevare", "status": "live"},
    {"id": "9113", "name": "QA Old", "status": "ended"}]',
  '[{"id": "99001", "campaign": "9111", "headline": "Er dere dekket?", "status": "live"}]',
  (select jsonb_agg(jsonb_build_object('level', 'campaign', 'id', c, 'day', d::date, 'impressions', 100, 'clicks', 5, 'spend', 10.5, 'conversions', 1))
   from generate_series((m0 - interval '2 months' + interval '14 days')::date, (now() at time zone 'Europe/Oslo')::date - 1, interval '1 day') d, unnest(array['9111', '9112']) c)) v
from t_m;
select pg_temp.check((select (v ->> 'rows')::int > 0 from t_imp), 'the days are imported');
select pg_temp.check((select ad_campaign_id = (select id from app.ad_campaigns where utm_campaign = 'qa-lovkrav') from app.ad_platform_campaigns where external_id = '9111'),
                     'a platform campaign carrying a Sentral campaign''s utm counts as it (in lower case)');
select pg_temp.check((select c.channel = 'google_ads' and c.utm_source = 'google-ads' and c.utm_medium = 'cpc' and c.state = 'live' and c.product = 'orgpuls'
                      from app.ad_platform_campaigns pc join app.ad_campaigns c on c.id = pc.ad_campaign_id where pc.external_id = '9112'),
                     'one without a match gets a Sentral campaign of its own');
select pg_temp.check((select ad_campaign_id is null from app.ad_platform_campaigns where external_id = '9113'), 'an ended one without activity gets none');
select pg_temp.check((select source = 'typed' and amount = 5000 from app.marketing_spend, t_m where campaign = 'qa-lovkrav' and month = m0 - interval '2 months'),
                     'a month imported only in part keeps what was typed in');
select pg_temp.check((select source = 'google_ads' and amount = round(10.5 * extract(day from (m0 - interval '1 day'))::numeric, 2) and channel = 'paid_search'
                      from app.marketing_spend, t_m where campaign = 'qa-lovkrav' and month = m0 - interval '1 month'), 'a whole month is the platform''s spend');
select pg_temp.check(exists (select 1 from app.growth_sync_log where source = 'google_ads' and state = 'ok'), 'the import is in the sync log');
-- typing over an imported month is refused
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.analytics_set_spend('qa-lovkrav', %L, 1)$$, (select m0 - interval '1 month' from t_m)), 'forbidden', 'imported',
                             'an imported month is not typed over');
select pg_temp.expect_detail(format($$select public.analytics_set_spend('qa-lovkrav', %L, null)$$, (select m0 - interval '1 month' from t_m)), 'forbidden', 'imported',
                             'nor removed');
-- the same window again replaces its days
select pg_temp.as_service();
select public.worker_ads_import((select id from t_acc), (now() at time zone 'Europe/Oslo')::date - 3, (now() at time zone 'Europe/Oslo')::date - 1, '[]', '[]',
  jsonb_build_array(jsonb_build_object('level', 'campaign', 'id', '9111', 'day', (now() at time zone 'Europe/Oslo')::date - 2, 'impressions', 7, 'clicks', 1, 'spend', 3)));
select pg_temp.check((select count(*) from app.ad_daily d join t_acc on d.account_id = t_acc.id where d.day between (now() at time zone 'Europe/Oslo')::date - 3 and (now() at time zone 'Europe/Oslo')::date - 1) = 1,
                     'a window imported again replaces its days whole');

-- ---------------------------------------------------------------------------
-- counting a platform campaign as another Sentral campaign
insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign) values ('orgpuls', 'QA other', 'google_ads', 'google-ads', 'cpc', 'qa-other'),
                                                                                               ('skiftly', 'QA skiftly', 'google_ads', 'google-ads', 'cpc', 'qa-skiftly');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format($$select public.ads_campaign_link(%L, %L)$$, (select id from app.ad_platform_campaigns where external_id = '9112'),
                                   (select id from app.ad_campaigns where utm_campaign = 'qa-other')), 'forbidden', 'counting needs Campaigns › Edit others''');
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format($$select public.ads_campaign_link(%L, %L)$$, (select id from app.ad_platform_campaigns where external_id = '9112'),
                                    (select id from app.ad_campaigns where utm_campaign = 'qa-skiftly')), 'invalid', 'campaign', 'only a campaign of the same application');
select public.ads_campaign_link((select id from app.ad_platform_campaigns where external_id = '9112'), (select id from app.ad_campaigns where utm_campaign = 'qa-other'));
select pg_temp.check((select linked_by_hand from app.ad_platform_campaigns where external_id = '9112')
                     and exists (select 1 from app.marketing_spend where campaign = 'qa-other' and source = 'google_ads'), 'counted by hand, and its spend goes with it');
create temp table t_own as select own_ad_campaign_id id from app.ad_platform_campaigns where external_id = '9112';
select public.ads_campaign_link((select id from app.ad_platform_campaigns where external_id = '9112'), null);
select pg_temp.check((select ad_campaign_id = (select id from t_own) and not linked_by_hand from app.ad_platform_campaigns where external_id = '9112')
                     and (select count(*) from app.ad_campaigns where name = 'QA Merkevare') = 1, 'back by itself: the campaign made for it before, not a new one');
select pg_temp.check(not exists (select 1 from app.marketing_spend where campaign = 'qa-other' and source <> 'typed'),
                     'and the spend it gave the other campaign leaves it, so nothing counts twice');

-- ---------------------------------------------------------------------------
-- the read: Campaigns › See, no credential in it
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error($$select public.growth_ads('orgpuls')$$, 'forbidden', 'the read needs Campaigns › See');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_read as select public.growth_ads('orgpuls') v;
select pg_temp.check((select not (v ->> 'can_manage')::boolean and v -> 'campaigns' @> '[{"name": "Lovkrav (Search)", "status": "live"}]'
                             and v -> 'ads' @> '[{"headline": "Er dere dekket?"}]' and v -> 'accounts' @> '[{"external_id": "5550001111", "product": "orgpuls"}]' from t_read),
                     'accounts, campaigns and ads with their figures');
select pg_temp.check((select v::text !~ 'AbCdEf0123456789xyz' and v::text !~ 'S3cr3t' and v::text !~ repeat('a', 40)
                             and v -> 'providers' @> '[{"provider": "google_ads", "stored": ["google_ads_developer_token"]}]' from t_read),
                     'which credentials are stored, never their values');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((select r -> 'platform' ->> 'provider' = 'google_ads' and r -> 'figures' -> 'spend' @> '[{"source": "google_ads"}]'
                          from jsonb_array_elements(public.ad_campaigns_get('orgpuls') -> 'rows') r where r ->> 'name' = 'QA lovkrav'),
                     'Campaigns says which platform a campaign follows and where each month''s spend came from');

-- an account that counts for no application any more: its imported spend leaves the campaigns
select pg_temp.as_mfa('tor@orgpuls.no');
select public.ads_account_link((select id from t_acc), null);
select pg_temp.check(not exists (select 1 from app.marketing_spend where campaign in ('qa-lovkrav', 'qa-other') and source <> 'typed')
                     and (select bool_and(ad_campaign_id is null) from app.ad_platform_campaigns pc join t_acc on pc.account_id = t_acc.id),
                     'an account linked to no application gives no spend and counts as no campaign');

-- ---------------------------------------------------------------------------
-- a refusal, then disconnect
select pg_temp.as_service();
select public.worker_ads_failed((select id from t_acc), 'http_403');
select public.worker_ads_result('google_ads', false, 'http_403', null);
select pg_temp.check((select last_error = 'http_403' from app.ad_accounts a join t_acc on a.id = t_acc.id)
                     and (select status = 'error' and config ->> 'last_error' = 'http_403' from app.integration_connections where provider = 'google_ads')
                     and exists (select 1 from app.growth_sync_log where source = 'google_ads' and state = 'failed'), 'a refusal is kept as a code on the account, the connection and the log');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.ads_disconnect('google_ads')$$, 'forbidden', 'fresh_mfa', 'disconnecting needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select public.ads_disconnect('google_ads');
select pg_temp.check(not exists (select 1 from vault.secrets where name in ('google_ads_developer_token', 'google_ads_key'))
                     and (select status from app.integration_connections where provider = 'google_ads') = 'not_connected'
                     and exists (select 1 from app.ad_daily d join t_acc on d.account_id = t_acc.id), 'off: the credentials leave Vault, what was imported stays');

rollback;
