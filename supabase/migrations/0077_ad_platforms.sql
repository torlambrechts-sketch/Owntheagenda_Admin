-- 0077_ad_platforms.sql — Google Ads, LinkedIn Ads and Meta Ads feed Growth (GrowthPlaybook.dc.html; V-GR2-33 to 41 left
-- them out for want of a connection). Read only: Sentral never changes a campaign, a bid or an audience on a platform.
--
-- Each platform is connected by the owner after a fresh second factor, and its credentials go from the owner's form straight
-- to secret-intake under a one-time number bound to the platform, into this project's Vault; only ads-run reads them
-- (product_secret):
--   Google Ads    a developer token, and a service account added as a user on the ad account (its own key, or Search
--                 Console's); an optional manager account id
--   LinkedIn Ads  the app's client id (kept in the open) and client secret (Vault); the owner then signs in with LinkedIn,
--                 and ads-oauth exchanges the code for tokens itself, so no token passes through a person
--   Meta Ads      a system user's access token, and optionally the app secret for appsecret_proof
-- ads-run lists the ad accounts the credentials may read; the owner links each to an application. Every night (and on
-- «Import now») it imports each linked account's campaigns, ads and daily figures: impressions, clicks, spend, conversions
-- as the platform counts them, and reach where it reports it. A platform campaign counts as one Sentral campaign
-- (ad_campaigns): the one carrying the same utm_campaign, one chosen by hand, or one made for it; its monthly spend then
-- replaces what was typed in, so Outcomes, the Budget planner, Campaigns and the Calendar read real spend.
--
-- Nothing here is about a person: platforms report counts per campaign and ad. Logs carry kinds, counts and status codes.

-- ===========================================================================
-- 1. connections, intake and Vault names
-- ===========================================================================
alter table app.integration_connections drop constraint if exists integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check check (provider in (
  'slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai', 'email',
  'ip_company', 'esign', 'pdf', 'meeting_bot', 'transcription', 'pagespeed', 'google_ads', 'linkedin_ads', 'meta_ads'));
insert into app.integration_connections (provider, status) values ('google_ads', 'not_connected'), ('linkedin_ads', 'not_connected'), ('meta_ads', 'not_connected')
on conflict (provider) do nothing;
alter table app.intake_nonces drop constraint if exists intake_nonces_purpose_check;
alter table app.intake_nonces add constraint intake_nonces_purpose_check check (purpose is null or purpose in (
  'brevo', 'search_console', 'pagespeed', 'google_ads', 'linkedin_ads', 'meta_ads'));

alter table app.growth_sync_log drop constraint growth_sync_log_source_check;
alter table app.growth_sync_log add constraint growth_sync_log_source_check
  check (source in ('search_console', 'pagespeed', 'crawler', 'tracker', 'product_events', 'email', 'url_inspection', 'google_ads', 'linkedin_ads', 'meta_ads'));

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'ads_worker_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'ads_worker_secret',
                                'The nightly job''s key to ads-run (0077). Generated; nobody types it.');
  end if;
end $$;

create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
                             or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret', 'search_console_key', 'search_console_worker_secret',
                                           'seo_crawl_worker_secret', 'pagespeed_api_key', 'pagespeed_worker_secret',
                                           'google_ads_developer_token', 'google_ads_key', 'linkedin_ads_client_secret', 'linkedin_ads_access_token',
                                           'linkedin_ads_refresh_token', 'meta_ads_token', 'meta_ads_app_secret', 'ads_worker_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

-- a secret under its one name, replaced when it exists
create function app.vault_put(p_name text, p_value text, p_note text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if exists (select 1 from vault.secrets s where s.name = p_name) then
    perform vault.update_secret((select s.id from vault.secrets s where s.name = p_name), p_value);
  else
    perform vault.create_secret(p_value, p_name, p_note);
  end if;
end $fn$;

-- an ad platform's credentials, by the intake number bound to it: only the names that platform has, each checked by shape
create function app.store_ad_secrets(p_purpose text, p_secrets jsonb) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare k text; v text; n int := 0; v_key jsonb; v_cfg jsonb := '{}'::jsonb;
begin
  for k, v in select key, btrim(value) from jsonb_each_text(p_secrets) loop
    if p_purpose = 'google_ads' and k = 'google_ads_developer_token' and v ~ '^[A-Za-z0-9_-]{15,64}$' then
      perform app.vault_put(k, v, 'The Google Ads developer token (0077): read by ads-run only.');
    elsif p_purpose = 'google_ads' and k = 'google_ads_key' then
      begin
        v_key := v::jsonb;
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end;
      if char_length(v) > 6000 or jsonb_typeof(v_key) <> 'object' or v_key ->> 'type' is distinct from 'service_account'
         or coalesce(v_key ->> 'client_email', '') !~ '^[a-z0-9._-]{1,100}@[a-z0-9.-]{1,100}\.iam\.gserviceaccount\.com$'
         or coalesce(v_key ->> 'private_key', '') !~ '^-----BEGIN PRIVATE KEY-----' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      perform app.vault_put(k, v, 'A Google service account key for Google Ads (0077): read by ads-run only.');
      v_cfg := v_cfg || jsonb_build_object('client_email', v_key ->> 'client_email');
    elsif p_purpose = 'linkedin_ads' and k = 'linkedin_ads_client_secret' and v ~ '^[A-Za-z0-9_.=-]{8,200}$' then
      perform app.vault_put(k, v, 'The LinkedIn app''s client secret (0077): read by ads-run and ads-oauth only.');
    elsif p_purpose = 'meta_ads' and k = 'meta_ads_token' and v ~ '^[A-Za-z0-9]+$' and char_length(v) between 40 and 800 then
      perform app.vault_put(k, v, 'A Meta system user''s access token (0077): read by ads-run only.');
    elsif p_purpose = 'meta_ads' and k = 'meta_ads_app_secret' and v ~ '^[a-f0-9]{32}$' then
      perform app.vault_put(k, v, 'The Meta app secret, for appsecret_proof (0077): read by ads-run only.');
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
    end if;
    n := n + 1;
  end loop;
  if n > 0 then
    update app.integration_connections set config = config || v_cfg || jsonb_build_object('key_stored_at', now(), 'last_error', null) where provider = p_purpose;
  end if;
  return n;
end $fn$;

-- 0073's store_product_secrets, with the ad platforms' branch
CREATE OR REPLACE FUNCTION public.store_product_secrets(p_nonce text, p_secrets jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k text; v text; n int := 0; v_product text; v_purpose text; v_key jsonb;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now() returning product, purpose into v_product, v_purpose;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  -- an ad platform's credentials (0077)
  if v_purpose in ('google_ads', 'linkedin_ads', 'meta_ads') then
    return jsonb_build_object('ok', true, 'stored', app.store_ad_secrets(v_purpose, p_secrets));
  end if;
  -- the mail provider's key: that one name only, replaced when it exists (the owner rotates it this way)
  if v_purpose = 'brevo' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'brevo_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]+$' or char_length(btrim(v)) not between 32 and 300 then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'The Brevo API key (0060): read by mail-run only.');
      end if;
      n := n + 1;
    end loop;
    if n > 0 then
      update app.integration_connections set status = 'not_connected', config = config || jsonb_build_object('provider', 'brevo', 'key_stored_at', now())
      where provider = 'email';
      update app.mail_settings set last_error = null, last_check_at = null, updated_at = now() where id;
    end if;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google service account's JSON key (0064): that one name only; only its address is kept outside Vault
  if v_purpose = 'search_console' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      begin
        v_key := v::jsonb;
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end;
      if k <> 'search_console_key' or char_length(v) > 6000 or jsonb_typeof(v_key) <> 'object' or v_key ->> 'type' is distinct from 'service_account'
         or coalesce(v_key ->> 'client_email', '') !~ '^[a-z0-9._-]{1,100}@[a-z0-9.-]{1,100}\.iam\.gserviceaccount\.com$'
         or coalesce(v_key ->> 'private_key', '') !~ '^-----BEGIN PRIVATE KEY-----' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
      else
        perform vault.create_secret(v, k, 'A Google service account key for Search Console (0064): read by search-console-run only.');
      end if;
      update app.integration_connections set status = 'not_connected',
        config = config || jsonb_build_object('provider', 'google', 'client_email', v_key ->> 'client_email', 'key_stored_at', now(), 'last_error', null)
      where provider = 'search_console';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  -- a Google API key for PageSpeed Insights (0073): that one name only; the integration is on once it is stored
  if v_purpose = 'pagespeed' then
    for k, v in select key, value from jsonb_each_text(p_secrets) loop
      if k <> 'pagespeed_api_key' or btrim(coalesce(v, '')) !~ '^[A-Za-z0-9_-]{30,80}$' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        perform vault.update_secret((select s.id from vault.secrets s where s.name = k), btrim(v));
      else
        perform vault.create_secret(btrim(v), k, 'A Google API key for PageSpeed Insights (0073): read by pagespeed-run only.');
      end if;
      update app.integration_connections set status = 'connected', connected_at = now(),
        config = config || jsonb_build_object('key_stored_at', now(), 'last_error', null)
      where provider = 'pagespeed';
      n := n + 1;
    end loop;
    return jsonb_build_object('ok', true, 'stored', n);
  end if;
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    if k !~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or char_length(coalesce(v, '')) < 32 or char_length(v) > 500 then
      raise exception 'store_product_secrets: % is not a product secret', k using errcode = 'invalid_parameter_value';
    end if;
    if v_product is not null then
      if k not in (v_product || '_token_secret', v_product || '_webhook_secret') then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
      end if;
      if exists (select 1 from vault.secrets s where s.name = k) then
        raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'exists';
      end if;
    end if;
    if exists (select 1 from vault.secrets s where s.name = k) then
      perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
    else
      perform vault.create_secret(v, k, 'A product''s shared secret (0002): read by the edge functions only.');
    end if;
    n := n + 1;
  end loop;
  if v_product is not null and exists (select 1 from vault.secrets s where s.name = v_product || '_token_secret')
     and exists (select 1 from vault.secrets s where s.name = v_product || '_webhook_secret') then
    update app.installations set enabled = true, updated_at = now() where product = v_product and not enabled;
  end if;
  return jsonb_build_object('ok', true, 'stored', n);
end $function$;
revoke all on function public.store_product_secrets(text, jsonb) from public, anon, authenticated;
grant execute on function public.store_product_secrets(text, jsonb) to service_role;

-- ===========================================================================
-- 2. what is imported
-- ===========================================================================
-- the ad accounts the credentials may read, and the application each counts for
create table app.ad_accounts (
  id             uuid primary key default gen_random_uuid(),
  provider       text not null check (provider in ('google_ads', 'linkedin_ads', 'meta_ads')),
  external_id    text not null check (external_id ~ '^[0-9]{1,20}$'),
  name           text not null check (char_length(name) between 1 and 200),
  currency       text check (currency is null or currency ~ '^[A-Z]{3}$'),
  time_zone      text check (time_zone is null or time_zone ~ '^[A-Za-z0-9_+/-]{1,60}$'),
  manager        boolean not null default false,
  product        text references app.products (key) on delete set null,
  seen_at        timestamptz not null default now(),
  last_import_at timestamptz,
  last_day       date,
  -- the earliest day any import asked for: a month from then on is the platform's whole month
  first_day      date,
  last_error     text check (last_error is null or last_error ~ '^[a-z0-9_.:-]{1,60}$'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (provider, external_id)
);
alter table app.ad_accounts enable row level security;
revoke all on app.ad_accounts from public, anon, authenticated;

-- a platform's campaigns, and the Sentral campaign each counts as
create table app.ad_platform_campaigns (
  id             uuid primary key default gen_random_uuid(),
  account_id     uuid not null references app.ad_accounts (id) on delete cascade,
  external_id    text not null check (external_id ~ '^[0-9]{1,20}$'),
  name           text not null check (char_length(name) between 1 and 300),
  status         text not null check (status in ('live', 'paused', 'ended')),
  kind           text check (kind is null or kind ~ '^[a-z0-9_]{1,40}$'),
  starts_on      date,
  ends_on        date,
  utm_campaign   text check (utm_campaign is null or utm_campaign ~ '^[a-z0-9_-]{1,60}$'),
  ad_campaign_id uuid references app.ad_campaigns (id) on delete set null,
  -- the campaign it counts as by itself (its utm_campaign's, or the one made for it), to return to after a link by hand
  own_ad_campaign_id uuid references app.ad_campaigns (id) on delete set null,
  linked_by_hand boolean not null default false,
  updated_at     timestamptz not null default now(),
  unique (account_id, external_id)
);
alter table app.ad_platform_campaigns enable row level security;
revoke all on app.ad_platform_campaigns from public, anon, authenticated;
create index ad_platform_campaigns_link on app.ad_platform_campaigns (ad_campaign_id) where ad_campaign_id is not null;

-- a platform's ads: a name and the first headline, as written by whoever made the ad
create table app.ad_platform_ads (
  id                   uuid primary key default gen_random_uuid(),
  account_id           uuid not null references app.ad_accounts (id) on delete cascade,
  campaign_external_id text not null check (campaign_external_id ~ '^[0-9]{1,20}$'),
  external_id          text not null check (external_id ~ '^[0-9]{1,24}$'),
  name                 text check (name is null or char_length(name) <= 300),
  headline             text check (headline is null or char_length(headline) <= 300),
  status               text not null check (status in ('live', 'paused', 'ended')),
  updated_at           timestamptz not null default now(),
  unique (account_id, external_id)
);
alter table app.ad_platform_ads enable row level security;
revoke all on app.ad_platform_ads from public, anon, authenticated;

-- a campaign's or an ad's day, as the platform counts it, in the account's currency
create table app.ad_daily (
  account_id  uuid not null references app.ad_accounts (id) on delete cascade,
  level       text not null check (level in ('campaign', 'ad')),
  external_id text not null check (external_id ~ '^[0-9]{1,24}$'),
  day         date not null,
  impressions bigint not null default 0 check (impressions >= 0),
  clicks      bigint not null default 0 check (clicks >= 0),
  spend       numeric(14, 2) not null default 0 check (spend >= 0),
  conversions numeric(14, 2) check (conversions is null or conversions >= 0),
  reach       bigint check (reach is null or reach >= 0),
  primary key (account_id, level, external_id, day)
);
alter table app.ad_daily enable row level security;
revoke all on app.ad_daily from public, anon, authenticated;

-- the one-time number LinkedIn's sign-in carries back (state), bound to the owner and the address to return to
create table app.ads_oauth_states (
  hash       bytea primary key,
  provider   text not null check (provider = 'linkedin_ads'),
  staff_id   uuid not null references app.admins (id) on delete cascade,
  origin     text not null check (origin ~ '^(https://admin\.owntheagenda\.com|https://[a-z0-9-]{1,63}\.vercel\.app|http://localhost:[0-9]{2,5})$'),
  expires_at timestamptz not null
);
alter table app.ads_oauth_states enable row level security;
revoke all on app.ads_oauth_states from public, anon, authenticated;

-- spend typed in or imported: an imported month is the platform's, and typing does not change it
alter table app.marketing_spend add column source text not null default 'typed' check (source in ('typed', 'google_ads', 'linkedin_ads', 'meta_ads'));
create function app.marketing_spend_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if old.source <> 'typed' and coalesce(current_setting('app.ads_import', true), '') <> 'on' then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'imported';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $fn$;
create trigger marketing_spend_guard before update or delete on app.marketing_spend for each row execute function app.marketing_spend_guard();

-- ===========================================================================
-- 3. the owner: credentials, settings, LinkedIn's sign-in, accounts, disconnect
-- ===========================================================================
create function app.ad_provider(p text) returns text
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p is null or p not in ('google_ads', 'linkedin_ads', 'meta_ads') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider'; end if;
  return p;
end $fn$;

create function public.ads_intake(p_provider text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v_p text := app.ad_provider(p_provider); v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform app.require_fresh_mfa(10);
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at, purpose) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', v_p);
  perform app.log('ads.intake_opened', 'integration', v_p);
  return jsonb_build_object('intake_code', v, 'expires_in', 900);
end $fn$;

-- what is not secret: Google's manager account, LinkedIn's client id, which key Google Ads signs in with
create function public.ads_settings_set(p_provider text, p_settings jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v_p text := app.ad_provider(p_provider); v jsonb := coalesce(p_settings, '{}'::jsonb); v_out jsonb := '{}'::jsonb; k text;
begin
  for k in select jsonb_object_keys(v) loop
    if v_p = 'google_ads' and k = 'login_customer_id' and (v -> k = 'null'::jsonb or replace(v ->> k, '-', '') ~ '^[0-9]{10}$') then
      v_out := v_out || jsonb_build_object(k, nullif(replace(coalesce(v ->> k, ''), '-', ''), ''));
    elsif v_p = 'google_ads' and k = 'key_source' and v ->> k in ('own', 'search_console') then
      v_out := v_out || jsonb_build_object(k, v ->> k);
    elsif v_p = 'linkedin_ads' and k = 'client_id' and v ->> k ~ '^[A-Za-z0-9]{8,40}$' then
      v_out := v_out || jsonb_build_object(k, v ->> k);
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  update app.integration_connections set config = config || v_out where provider = v_p;
  perform app.log('ads.settings_set', 'integration', v_p, jsonb_build_object('keys', (select jsonb_agg(x) from jsonb_object_keys(v_out) x)));
  return jsonb_build_object('provider', v_p);
end $fn$;

-- LinkedIn's sign-in: a one-time state for the owner, the client id and the address LinkedIn sends the code back to
create function public.ads_oauth_start(p_origin text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := encode(extensions.gen_random_bytes(24), 'hex');
        v_client text := (select config ->> 'client_id' from app.integration_connections where provider = 'linkedin_ads');
        v_url text := (select functions_url from app.mail_settings);
begin
  perform app.require_fresh_mfa(10);
  if v_client is null or not exists (select 1 from vault.secrets where name = 'linkedin_ads_client_secret') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'not_configured';
  end if;
  if v_url is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'functions_url'; end if;
  if p_origin is null or p_origin !~ '^(https://admin\.owntheagenda\.com|https://[a-z0-9-]{1,63}\.vercel\.app|http://localhost:[0-9]{2,5})$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'origin';
  end if;
  delete from app.ads_oauth_states where expires_at < now();
  insert into app.ads_oauth_states (hash, provider, staff_id, origin, expires_at) values (extensions.digest(v, 'sha256'), 'linkedin_ads', v_me, p_origin, now() + interval '15 minutes');
  perform app.log('ads.oauth_started', 'integration', 'linkedin_ads');
  return jsonb_build_object('state', v, 'client_id', v_client, 'redirect_uri', v_url || '/functions/v1/ads-oauth', 'scope', 'r_ads r_ads_reporting');
end $fn$;

-- ads-run asks with the owner's own token: is this the owner?
create function public.ads_check_ready() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  return jsonb_build_object('me', v_me);
end $fn$;

-- the owner: an account counts for an application, or for none (nothing more is imported for it)
create function public.ads_account_link(p_account uuid, p_product text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  if p_product is not null and not exists (select 1 from app.products where key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  update app.ad_accounts set product = p_product, updated_at = now() where id = p_account and not manager;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  -- another application, or none: campaigns of the old one let go, they link again, and the imported spend follows
  update app.ad_platform_campaigns pc set ad_campaign_id = null, own_ad_campaign_id = null, linked_by_hand = false, updated_at = now()
  where pc.account_id = p_account and pc.ad_campaign_id is not null
    and not exists (select 1 from app.ad_campaigns c where c.id = pc.ad_campaign_id and c.product is not distinct from p_product);
  perform app.ads_sync_spend(p_account);
  perform app.log('ads.account_linked', 'integration', (select provider from app.ad_accounts where id = p_account), jsonb_build_object('product', p_product));
  return jsonb_build_object('id', p_account, 'product', p_product);
end $fn$;

-- the owner: disconnect (fresh second factor). The credentials leave Vault; what was imported stays
create function public.ads_disconnect(p_provider text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v_p text := app.ad_provider(p_provider);
begin
  perform app.require_fresh_mfa(10);
  delete from vault.secrets where name = any (case v_p
    when 'google_ads' then array['google_ads_developer_token', 'google_ads_key']
    when 'linkedin_ads' then array['linkedin_ads_client_secret', 'linkedin_ads_access_token', 'linkedin_ads_refresh_token']
    else array['meta_ads_token', 'meta_ads_app_secret'] end);
  update app.integration_connections set status = 'not_connected', connected_at = null,
    config = config - 'key_stored_at' - 'token_expires_at' - 'refresh_expires_at' - 'client_email' || jsonb_build_object('last_error', null)
  where provider = v_p;
  perform app.log('ads.disconnected', 'integration', v_p, '{}'::jsonb);
  return jsonb_build_object('status', 'not_connected');
end $fn$;

-- a platform campaign counts as another Sentral campaign of the same application (Campaigns › Edit others'), or as its own again
create function public.ads_campaign_link(p_campaign uuid, p_ad_campaign uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'edit_others'); pc app.ad_platform_campaigns; a app.ad_accounts;
begin
  select * into pc from app.ad_platform_campaigns where id = p_campaign for update;
  if pc.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into a from app.ad_accounts where id = pc.account_id;
  if p_ad_campaign is not null and not exists (select 1 from app.ad_campaigns c where c.id = p_ad_campaign and c.product = a.product and not c.is_sample) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'campaign';
  end if;
  update app.ad_platform_campaigns set ad_campaign_id = p_ad_campaign, linked_by_hand = p_ad_campaign is not null, updated_at = now() where id = p_campaign;
  perform app.ads_sync_spend(a.id);
  perform app.log('ads.campaign_linked', 'integration', a.provider, jsonb_build_object('campaign', p_campaign, 'ad_campaign', p_ad_campaign));
  return jsonb_build_object('id', p_campaign, 'ad_campaign_id', (select ad_campaign_id from app.ad_platform_campaigns where id = p_campaign));
end $fn$;

-- ===========================================================================
-- 4. a platform campaign's Sentral campaign, and its spend
-- ===========================================================================
-- what the imports say each Sentral campaign spent per month: the platform campaigns that count as it, summed, from the
-- first month each account's imports cover whole
create function app.ads_spend_wanted() returns table (campaign text, month date, channel text, amount numeric, currency text, source text)
  language sql stable security definer set search_path = ''
as $fn$
  select c.utm_campaign, date_trunc('month', d.day)::date, app.ad_utm(c.channel) ->> 'spend', round(sum(d.spend), 2), min(ac.currency), min(ac.provider)
  from app.ad_daily d
  join app.ad_accounts ac on ac.id = d.account_id
  join app.ad_platform_campaigns pc on pc.account_id = d.account_id and pc.external_id = d.external_id
  join app.ad_campaigns c on c.id = pc.ad_campaign_id
  where d.level = 'campaign' and ac.product is not null and ac.first_day is not null
    and d.day >= case when extract(day from ac.first_day) = 1 then ac.first_day else (date_trunc('month', ac.first_day) + interval '1 month')::date end
  group by 1, 2, 3
$fn$;

create function app.ad_channel_of(p_provider text) returns text
  language sql immutable set search_path = ''
as $fn$ select case p_provider when 'google_ads' then 'google_ads' when 'linkedin_ads' then 'linkedin' else 'facebook' end $fn$;

-- each platform campaign with activity or still running gets a Sentral campaign: the one it had before, the one carrying
-- its utm_campaign in the same application, or one made for it. Then every imported month is computed again from what is
-- imported now: a Sentral campaign's month is the sum of the platform campaigns that count as it, from the first month the
-- account's imports cover from its first day (a month imported only in part keeps what was typed in); an imported month
-- nothing counts for any more is removed, so spend never counts twice
create function app.ads_sync_spend(p_account uuid) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.ad_accounts; r record; v_id uuid; v_utm text; v_ch text; n int := 0;
begin
  select * into a from app.ad_accounts where id = p_account;
  if a.id is not null and a.product is not null then
    v_ch := app.ad_channel_of(a.provider);
    for r in
      select * from app.ad_platform_campaigns x
      where x.account_id = a.id and x.ad_campaign_id is null
        and (x.status = 'live' or exists (select 1 from app.ad_daily d where d.account_id = a.id and d.level = 'campaign' and d.external_id = x.external_id
                                                                       and (d.spend > 0 or d.impressions > 0)))
    loop
      v_id := (select c.id from app.ad_campaigns c where c.id = r.own_ad_campaign_id and c.product = a.product);
      if v_id is null then
        select c.id into v_id from app.ad_campaigns c where c.product = a.product and c.utm_campaign = r.utm_campaign and not c.is_sample;
      end if;
      if v_id is null then
        v_utm := case when r.utm_campaign is not null and not exists (select 1 from app.ad_campaigns c where c.utm_campaign = r.utm_campaign)
                           and not exists (select 1 from app.campaigns c where c.utm_campaign = r.utm_campaign and c.deleted_at is null)
                      then r.utm_campaign else app.ad_utm_campaign(r.name) end;
        insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign, starts_on, ends_on, state)
        values (a.product, left(btrim(r.name), 120), v_ch, (app.ad_utm(v_ch) ->> 'source'), (app.ad_utm(v_ch) ->> 'medium'), v_utm,
                r.starts_on, case when r.ends_on >= r.starts_on or r.starts_on is null then r.ends_on end,
                case r.status when 'live' then 'live' when 'paused' then 'paused' else 'ended' end)
        returning id into v_id;
      end if;
      update app.ad_platform_campaigns set ad_campaign_id = v_id, own_ad_campaign_id = v_id, updated_at = now() where id = r.id;
    end loop;
    -- a linked campaign follows the platform's state
    update app.ad_campaigns c set state = x.state, version = c.version + 1, updated_at = now()
    from (select pc.ad_campaign_id id, case when bool_or(pc.status = 'live') then 'live' when bool_or(pc.status = 'paused') then 'paused' else 'ended' end state
          from app.ad_platform_campaigns pc where pc.account_id = a.id and pc.ad_campaign_id is not null group by 1) x
    where c.id = x.id and c.state is distinct from x.state;
  end if;
  perform set_config('app.ads_import', 'on', true);
  insert into app.marketing_spend (campaign, month, channel, amount, currency, source, entered_by, entered_at)
  select w.campaign, w.month, w.channel, w.amount, w.currency, w.source, null, now() from app.ads_spend_wanted() w
  on conflict (campaign, month) do update set amount = excluded.amount, channel = excluded.channel, currency = excluded.currency, source = excluded.source,
                                              entered_by = null, entered_at = now()
  where (app.marketing_spend.amount, app.marketing_spend.channel, app.marketing_spend.currency, app.marketing_spend.source)
        is distinct from (excluded.amount, excluded.channel, excluded.currency, excluded.source);
  get diagnostics n = row_count;
  delete from app.marketing_spend ms
  where ms.source <> 'typed' and not exists (select 1 from app.ads_spend_wanted() w where w.campaign = ms.campaign and w.month = ms.month);
  perform set_config('app.ads_import', '', true);
  return n;
end $fn$;

-- ===========================================================================
-- 5. the worker (service role)
-- ===========================================================================
-- what ads-run needs to know: each connected platform's settings (no secret), its accounts, and where each import starts
create function public.worker_ads_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'providers', coalesce((select jsonb_agg(jsonb_build_object('provider', ic.provider, 'status', ic.status,
                             'login_customer_id', ic.config ->> 'login_customer_id', 'key_source', coalesce(ic.config ->> 'key_source', 'own'),
                             'client_id', ic.config ->> 'client_id', 'token_expires_at', ic.config ->> 'token_expires_at'))
                           from app.integration_connections ic where ic.provider in ('google_ads', 'linkedin_ads', 'meta_ads')), '[]'::jsonb),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'provider', a.provider, 'external_id', a.external_id, 'currency', a.currency,
                            -- a week back from the last day imported, for conversions counted late; 90 days the first time
                            'from', greatest(coalesce(a.last_day - 7, (now() at time zone 'Europe/Oslo')::date - 90), (now() at time zone 'Europe/Oslo')::date - 400),
                            'to', (now() at time zone 'Europe/Oslo')::date) order by a.last_import_at nulls first)
                          from app.ad_accounts a where a.product is not null and not a.manager), '[]'::jsonb))
$fn$;

-- the ad accounts a platform's credentials may read; one no longer listed keeps its figures
create function public.worker_ads_accounts(p_provider text, p_accounts jsonb) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_p text := app.ad_provider(p_provider); n int;
begin
  insert into app.ad_accounts (provider, external_id, name, currency, time_zone, manager)
  select v_p, x ->> 'id', left(coalesce(nullif(btrim(x ->> 'name'), ''), x ->> 'id'), 200),
         case when x ->> 'currency' ~ '^[A-Z]{3}$' then x ->> 'currency' end,
         case when x ->> 'time_zone' ~ '^[A-Za-z0-9_+/-]{1,60}$' then x ->> 'time_zone' end, coalesce((x ->> 'manager')::boolean, false)
  from jsonb_array_elements(coalesce(p_accounts, '[]'::jsonb)) x
  where x ->> 'id' ~ '^[0-9]{1,20}$'
  on conflict (provider, external_id) do update set name = excluded.name, currency = excluded.currency, time_zone = excluded.time_zone,
                                                     manager = excluded.manager, seen_at = now(), updated_at = now();
  get diagnostics n = row_count;
  -- an application with one account of this platform links itself; otherwise the owner chooses
  update app.ad_accounts a set product = (select key from app.products order by key limit 1), updated_at = now()
  where a.provider = v_p and a.product is null and not a.manager and (select count(*) from app.products) = 1
    and (select count(*) from app.ad_accounts b where b.provider = v_p and not b.manager) = 1;
  return n;
end $fn$;

-- an account's import: its campaigns and ads as they are now, and its days in the window replaced whole
create function public.worker_ads_import(p_account uuid, p_from date, p_to date, p_campaigns jsonb, p_ads jsonb, p_daily jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.ad_accounts; v_rows int; v_spend int; v_last date;
begin
  select * into a from app.ad_accounts where id = p_account for update;
  if a.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'window'; end if;
  insert into app.ad_platform_campaigns (account_id, external_id, name, status, kind, starts_on, ends_on, utm_campaign)
  select a.id, x ->> 'id', left(coalesce(nullif(btrim(x ->> 'name'), ''), x ->> 'id'), 300), x ->> 'status',
         case when x ->> 'kind' ~ '^[a-z0-9_]{1,40}$' then x ->> 'kind' end,
         case when x ->> 'starts_on' ~ '^\d{4}-\d{2}-\d{2}$' then (x ->> 'starts_on')::date end,
         case when x ->> 'ends_on' ~ '^\d{4}-\d{2}-\d{2}$' then (x ->> 'ends_on')::date end,
         case when lower(x ->> 'utm_campaign') ~ '^[a-z0-9_-]{1,60}$' then lower(x ->> 'utm_campaign') end
  from jsonb_array_elements(coalesce(p_campaigns, '[]'::jsonb)) x
  where x ->> 'id' ~ '^[0-9]{1,20}$' and x ->> 'status' in ('live', 'paused', 'ended')
  on conflict (account_id, external_id) do update set name = excluded.name, status = excluded.status, kind = excluded.kind, starts_on = excluded.starts_on,
                                                      ends_on = excluded.ends_on, utm_campaign = coalesce(excluded.utm_campaign, app.ad_platform_campaigns.utm_campaign), updated_at = now();
  insert into app.ad_platform_ads (account_id, campaign_external_id, external_id, name, headline, status)
  select a.id, x ->> 'campaign', x ->> 'id', left(nullif(btrim(x ->> 'name'), ''), 300), left(nullif(btrim(x ->> 'headline'), ''), 300), x ->> 'status'
  from jsonb_array_elements(coalesce(p_ads, '[]'::jsonb)) x
  where x ->> 'id' ~ '^[0-9]{1,24}$' and x ->> 'campaign' ~ '^[0-9]{1,20}$' and x ->> 'status' in ('live', 'paused', 'ended')
  on conflict (account_id, external_id) do update set campaign_external_id = excluded.campaign_external_id, name = excluded.name, headline = excluded.headline,
                                                      status = excluded.status, updated_at = now();
  delete from app.ad_daily where account_id = a.id and day between p_from and p_to;
  insert into app.ad_daily (account_id, level, external_id, day, impressions, clicks, spend, conversions, reach)
  select a.id, x ->> 'level', x ->> 'id', (x ->> 'day')::date, greatest(coalesce((x ->> 'impressions')::bigint, 0), 0), greatest(coalesce((x ->> 'clicks')::bigint, 0), 0),
         greatest(round(coalesce((x ->> 'spend')::numeric, 0), 2), 0),
         case when x ->> 'conversions' is not null then greatest(round((x ->> 'conversions')::numeric, 2), 0) end,
         case when x ->> 'reach' is not null then greatest((x ->> 'reach')::bigint, 0) end
  from jsonb_array_elements(coalesce(p_daily, '[]'::jsonb)) x
  where x ->> 'level' in ('campaign', 'ad') and x ->> 'id' ~ '^[0-9]{1,24}$' and x ->> 'day' ~ '^\d{4}-\d{2}-\d{2}$' and (x ->> 'day')::date between p_from and p_to
  on conflict (account_id, level, external_id, day) do update set impressions = excluded.impressions, clicks = excluded.clicks, spend = excluded.spend,
                                                                 conversions = excluded.conversions, reach = excluded.reach;
  get diagnostics v_rows = row_count;
  update app.ad_accounts set first_day = least(coalesce(first_day, p_from), p_from) where id = a.id;
  v_spend := app.ads_sync_spend(a.id);
  v_last := least(p_to, (now() at time zone 'Europe/Oslo')::date - 1);
  update app.ad_accounts set last_import_at = now(), last_day = greatest(coalesce(last_day, v_last), v_last), last_error = null, updated_at = now() where id = a.id;
  insert into app.growth_sync_log (source, rows, state, info) values (a.provider, v_rows, 'ok', jsonb_build_object('account', a.external_id, 'from', p_from, 'to', p_to, 'months', v_spend));
  return jsonb_build_object('rows', v_rows, 'months', v_spend);
end $fn$;

-- an account the platform refused: the reason as a code, kept on the account and in the log
create function public.worker_ads_failed(p_account uuid, p_code text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_code text := case when p_code ~ '^[a-z0-9_.:-]{1,60}$' then p_code else 'failed' end;
begin
  update app.ad_accounts set last_error = v_code, updated_at = now() where id = p_account;
  insert into app.growth_sync_log (source, state, info)
  select provider, 'failed', jsonb_build_object('account', external_id, 'code', v_code) from app.ad_accounts where id = p_account;
end $fn$;

-- a platform's verdict on its credentials: connected, or the reason it is not
create function public.worker_ads_result(p_provider text, p_ok boolean, p_code text, p_by uuid default null) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_p text := app.ad_provider(p_provider); v_code text := case when p_code ~ '^[a-z0-9_.:-]{1,60}$' then p_code end;
begin
  update app.integration_connections set status = case when p_ok then 'connected' else 'error' end,
    connected_at = case when p_ok then coalesce(connected_at, now()) else connected_at end,
    config = config || jsonb_build_object('last_error', case when p_ok then null else coalesce(v_code, 'failed') end, 'last_check_at', now())
  where provider = v_p;
  if not p_ok then
    insert into app.growth_sync_log (source, state, info) values (v_p, 'failed', jsonb_build_object('code', coalesce(v_code, 'failed')));
  end if;
  if p_by is not null then perform app.log(case when p_ok then 'ads.connected' else 'ads.connect_failed' end, 'integration', v_p, jsonb_build_object('code', v_code)); end if;
end $fn$;

-- LinkedIn's sign-in coming back: the state, used once and within fifteen minutes; the owner and where to send them
create function public.worker_ads_oauth_state(p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v app.ads_oauth_states;
begin
  delete from app.ads_oauth_states where hash = extensions.digest(coalesce(p_state, ''), 'sha256') returning * into v;
  if v.hash is null or v.expires_at < now() then return null; end if;
  return jsonb_build_object('staff_id', v.staff_id, 'origin', v.origin,
                            'client_id', (select config ->> 'client_id' from app.integration_connections where provider = 'linkedin_ads'),
                            'redirect_uri', (select functions_url from app.mail_settings) || '/functions/v1/ads-oauth');
end $fn$;

-- LinkedIn's tokens, from the sign-in or a refresh: into Vault; only when they expire is kept outside it
create function public.worker_ads_tokens(p_access text, p_refresh text, p_expires_in int, p_refresh_expires_in int, p_by uuid default null) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_access is null or char_length(p_access) not between 20 and 4000 or (p_refresh is not null and char_length(p_refresh) not between 20 and 4000) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'token';
  end if;
  perform app.vault_put('linkedin_ads_access_token', p_access, 'A LinkedIn access token for the Advertising API (0077): read by ads-run only.');
  if p_refresh is not null then
    perform app.vault_put('linkedin_ads_refresh_token', p_refresh, 'A LinkedIn refresh token (0077): read by ads-run only.');
  end if;
  update app.integration_connections set
    config = config || jsonb_build_object('token_expires_at', now() + make_interval(secs => greatest(coalesce(p_expires_in, 0), 0)), 'last_error', null)
             || case when p_refresh is not null then jsonb_build_object('refresh_expires_at', now() + make_interval(secs => greatest(coalesce(p_refresh_expires_in, 0), 0))) else '{}'::jsonb end
  where provider = 'linkedin_ads';
  if p_by is not null then perform app.log('ads.signed_in', 'integration', 'linkedin_ads', '{}'::jsonb); end if;
end $fn$;

-- the nightly import, when a platform is connected
create function app.ads_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text; v_url text := (select functions_url from app.mail_settings);
begin
  if v_url is null or not exists (select 1 from app.integration_connections where provider in ('google_ads', 'linkedin_ads', 'meta_ads') and status = 'connected') then
    return jsonb_build_object('called', 0);
  end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'ads_worker_secret';
  perform net.http_post(url := v_url || '/functions/v1/ads-run', body := '{"kind": "run"}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 150000);
  return jsonb_build_object('called', 1);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('ads', 'jobs.ads', '7 5 * * *', 'cron', 'app.ads_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-ads', '7 5 * * *', 'select app.run_job(''ads'')');

-- ===========================================================================
-- 6. the read: connections, accounts, campaigns and ads with their figures
-- ===========================================================================
create function public.growth_ads(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_today date := (now() at time zone 'Europe/Oslo')::date;
begin
  return jsonb_build_object(
    'today', v_today,
    'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'),
    -- the address to register as LinkedIn's redirect URL
    'oauth_redirect', (select functions_url from app.mail_settings) || '/functions/v1/ads-oauth',
    -- the application's own campaigns, for counting a platform campaign as one of them
    'sentral_campaigns', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'utm_campaign', c.utm_campaign) order by c.name)
                                   from app.ad_campaigns c where c.product = p_product and not c.is_sample), '[]'::jsonb),
    'providers', coalesce((select jsonb_agg(jsonb_build_object(
        'provider', ic.provider, 'status', ic.status, 'connected_at', ic.connected_at,
        'last_error', ic.config ->> 'last_error', 'last_check_at', ic.config ->> 'last_check_at',
        'client_email', ic.config ->> 'client_email', 'login_customer_id', ic.config ->> 'login_customer_id', 'key_source', coalesce(ic.config ->> 'key_source', 'own'),
        'client_id', ic.config ->> 'client_id', 'token_expires_at', ic.config ->> 'token_expires_at', 'refresh_expires_at', ic.config ->> 'refresh_expires_at',
        'stored', (select coalesce(jsonb_agg(s.name order by s.name), '[]'::jsonb) from vault.secrets s
                   where s.name = any (array['google_ads_developer_token', 'google_ads_key', 'linkedin_ads_client_secret', 'linkedin_ads_access_token',
                                             'linkedin_ads_refresh_token', 'meta_ads_token', 'meta_ads_app_secret'])
                     and s.name like (case ic.provider when 'google_ads' then 'google_ads_%' when 'linkedin_ads' then 'linkedin_ads_%' else 'meta_ads_%' end)))
      order by array_position(array['google_ads', 'linkedin_ads', 'meta_ads'], ic.provider))
      from app.integration_connections ic where ic.provider in ('google_ads', 'linkedin_ads', 'meta_ads')), '[]'::jsonb),
    'search_console_email', (select config ->> 'client_email' from app.integration_connections where provider = 'search_console'
                             and exists (select 1 from vault.secrets where name = 'search_console_key')),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'provider', a.provider, 'external_id', a.external_id, 'name', a.name, 'currency', a.currency,
                            'manager', a.manager, 'product', a.product, 'last_import_at', a.last_import_at, 'last_day', a.last_day, 'last_error', a.last_error,
                            'campaigns', (select count(*) from app.ad_platform_campaigns pc where pc.account_id = a.id))
                          order by a.provider, a.manager, a.name)
                          from app.ad_accounts a), '[]'::jsonb),
    'campaigns', coalesce((select jsonb_agg(jsonb_build_object('id', pc.id, 'provider', a.provider, 'account', a.name, 'currency', a.currency, 'name', pc.name,
                             'status', pc.status, 'kind', pc.kind, 'utm_campaign', pc.utm_campaign, 'ad_campaign_id', pc.ad_campaign_id, 'linked_by_hand', pc.linked_by_hand,
                             'ad_campaign', (select c.name from app.ad_campaigns c where c.id = pc.ad_campaign_id),
                             'd30', (select jsonb_build_object('impressions', coalesce(sum(d.impressions), 0), 'clicks', coalesce(sum(d.clicks), 0),
                                                               'spend', coalesce(sum(d.spend), 0), 'conversions', sum(d.conversions))
                                     from app.ad_daily d where d.account_id = a.id and d.level = 'campaign' and d.external_id = pc.external_id and d.day > v_today - 30))
                           order by pc.status = 'live' desc, pc.name)
                           from app.ad_platform_campaigns pc join app.ad_accounts a on a.id = pc.account_id
                           where a.product = p_product), '[]'::jsonb),
    -- each ad's last seven days against the seven before, and its reach, for fatigue
    'ads', coalesce((select jsonb_agg(y.o order by y.n desc) from (select x.o, (x.o -> 'last7' ->> 'impressions')::bigint n from (
        select jsonb_build_object('id', ad.id, 'provider', a.provider, 'currency', a.currency, 'name', ad.name, 'headline', ad.headline, 'status', ad.status,
          'campaign', (select pc.name from app.ad_platform_campaigns pc where pc.account_id = a.id and pc.external_id = ad.campaign_external_id),
          'last7', (select jsonb_build_object('impressions', coalesce(sum(d.impressions), 0), 'clicks', coalesce(sum(d.clicks), 0), 'spend', coalesce(sum(d.spend), 0),
                                              'reach', sum(d.reach), 'conversions', sum(d.conversions))
                    from app.ad_daily d where d.account_id = a.id and d.level = 'ad' and d.external_id = ad.external_id and d.day between v_today - 7 and v_today - 1),
          'prev7', (select jsonb_build_object('impressions', coalesce(sum(d.impressions), 0), 'clicks', coalesce(sum(d.clicks), 0))
                    from app.ad_daily d where d.account_id = a.id and d.level = 'ad' and d.external_id = ad.external_id and d.day between v_today - 14 and v_today - 8)) o
        from app.ad_platform_ads ad join app.ad_accounts a on a.id = ad.account_id
        where a.product = p_product and (ad.status = 'live' or exists (select 1 from app.ad_daily d where d.account_id = a.id and d.level = 'ad'
                                                                        and d.external_id = ad.external_id and d.day > v_today - 30 and d.impressions > 0))) x
        order by 2 desc limit 200) y), '[]'::jsonb));
end $fn$;

-- 0058's campaigns read, with where each month's spend came from and the platform campaigns a campaign counts as
create or replace function public.ad_campaigns_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  v_site app.web_sites := app.product_site(p_product);
  v_live boolean;
  v_others boolean := app.can('campaigns', 'reports_others') or app.can('global', 'reports_others') or app.can('campaigns', 'edit_others');
begin
  if not exists (select 1 from app.products where key = p_product) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product'; end if;
  v_live := v_site.id is not null and exists (select 1 from app.web_sessions w where w.site_id = v_site.id);
  return jsonb_build_object(
    'site', case when v_site.id is not null then jsonb_build_object('id', v_site.id, 'hostname', v_site.hostname) end,
    'tracked', v_live,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'channel', c.channel, 'landing_path', c.landing_path,
        'utm', jsonb_build_object('source', c.utm_source, 'medium', c.utm_medium, 'campaign', c.utm_campaign),
        'budget', c.budget, 'currency', c.currency, 'starts_on', c.starts_on, 'ends_on', c.ends_on,
        'state', app.ad_state(c), 'version', c.version, 'created_at', c.created_at, 'mine', c.created_by = v_me,
        'platform', (select jsonb_build_object('provider', a.provider, 'name', pc.name, 'count', count(*) over ())
                     from app.ad_platform_campaigns pc join app.ad_accounts a on a.id = pc.account_id
                     where pc.ad_campaign_id = c.id order by pc.status = 'live' desc, pc.name limit 1),
        'figures', case when c.created_by = v_me or v_others then jsonb_build_object(
          'spend', (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(ms.month, 'YYYY-MM'), 'amount', ms.amount, 'currency', ms.currency, 'source', ms.source) order by ms.month), '[]'::jsonb)
                    from app.marketing_spend ms where ms.campaign = c.utm_campaign),
          'spent', (select sum(ms.amount) from app.marketing_spend ms where ms.campaign = c.utm_campaign and ms.currency = 'NOK'),
          'visits', case when v_live then (select count(*) from app.web_sessions w where w.site_id = v_site.id and w.utm ->> 'utm_campaign' = c.utm_campaign) end,
          'signups', (select count(*) from app.account_products ap
                      where lower(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign') = c.utm_campaign),
          'paid', (select count(*) from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                   where lower(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign') = c.utm_campaign and s.confirmed_at is not null)) end)
      order by c.created_at, c.name)
      from app.ad_campaigns c where c.product = p_product and (not c.is_sample or v_sandbox)), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.vault_put(text, text, text) from public, anon, authenticated;
revoke all on function app.store_ad_secrets(text, jsonb) from public, anon, authenticated;
revoke all on function app.marketing_spend_guard() from public, anon, authenticated;
revoke all on function app.ad_provider(text) from public, anon, authenticated;
revoke all on function app.ad_channel_of(text) from public, anon, authenticated;
revoke all on function app.ads_sync_spend(uuid) from public, anon, authenticated;
revoke all on function app.ads_spend_wanted() from public, anon, authenticated;
revoke all on function app.ads_tick() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.ads_intake(text)', 'public.ads_settings_set(text, jsonb)', 'public.ads_oauth_start(text)', 'public.ads_check_ready()',
                           'public.ads_account_link(uuid, text)', 'public.ads_disconnect(text)', 'public.ads_campaign_link(uuid, uuid)', 'public.growth_ads(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_ads_targets()', 'public.worker_ads_accounts(text, jsonb)', 'public.worker_ads_import(uuid, date, date, jsonb, jsonb, jsonb)',
                           'public.worker_ads_failed(uuid, text)', 'public.worker_ads_result(text, boolean, text, uuid)', 'public.worker_ads_oauth_state(text)',
                           'public.worker_ads_tokens(text, text, int, int, uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
