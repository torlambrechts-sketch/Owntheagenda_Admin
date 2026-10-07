-- 0064_search_console.sql — Google Search Console feeds Growth › SEO (0058 left «Connect Search Console» without a way to).
--
-- The owner creates a service account in Google Cloud, adds its address as a user on the site's Search Console property,
-- and pastes the account's JSON key in Growth › SEO after a fresh second factor. The key goes from the owner's browser
-- straight to secret-intake under a one-time number bound to «search_console», lands in Vault as `search_console_key`, and
-- is read only by the edge function search-console-run (product_secret). The function proves the key, finds each site's
-- property among those the account may read, and imports clicks, impressions and position per day (totals) and per day and
-- query. A daily cron asks it to import again. Nothing here is about a person: search queries are what people typed into
-- Google, counted by Google, without any address or identity.

-- ===========================================================================
-- 1. what is stored
-- ===========================================================================
-- the property each site maps to, and how its import went
create table app.search_console_sites (
  site_id        uuid primary key references app.web_sites (id) on delete cascade,
  property       text check (property is null or property ~ '^(sc-domain:[a-z0-9.-]+|https?://[a-z0-9.-]+(:\d+)?/)$'),
  last_import_at timestamptz,
  last_day       date,
  last_error     text check (last_error is null or last_error ~ '^[a-z0-9_.:-]{1,60}$'),
  updated_at     timestamptz not null default now()
);
alter table app.search_console_sites enable row level security;
revoke all on app.search_console_sites from public, anon, authenticated;

-- the day's totals as Search Console counts them: the per-query rows leave out anonymised queries, so they never add up
create table app.search_console_totals (
  day         date not null,
  site_id     uuid not null references app.web_sites (id) on delete cascade,
  impressions int not null check (impressions >= 0),
  clicks      int not null check (clicks >= 0),
  position    numeric check (position is null or position > 0),
  primary key (day, site_id)
);
alter table app.search_console_totals enable row level security;
revoke all on app.search_console_totals from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'search_console_worker_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'search_console_worker_secret',
                                'The cron''s key to search-console-run (0064). Generated; nobody types it.');
  end if;
end $$;

create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
                             or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret', 'search_console_key', 'search_console_worker_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

-- ===========================================================================
-- 2. the key: an intake number bound to «search_console», and its one name
-- ===========================================================================
alter table app.intake_nonces drop constraint if exists intake_nonces_purpose_check;
alter table app.intake_nonces add constraint intake_nonces_purpose_check check (purpose is null or purpose in ('brevo', 'search_console'));

create or replace function public.store_product_secrets(p_nonce text, p_secrets jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare k text; v text; n int := 0; v_product text; v_purpose text; v_key jsonb;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now() returning product, purpose into v_product, v_purpose;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
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
      update app.mail_settings set last_error = null, last_check_at = null, updated_at = now();
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
end $fn$;
revoke all on function public.store_product_secrets(text, jsonb) from public, anon, authenticated;
grant execute on function public.store_product_secrets(text, jsonb) to service_role;

-- the owner: an intake number for the key (fresh second factor)
create function public.search_console_intake() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform app.require_fresh_mfa(10);
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at, purpose) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', 'search_console');
  perform app.log('search_console.intake_opened', 'integration', 'search_console');
  return jsonb_build_object('intake_code', v, 'expires_in', 900);
end $fn$;

-- search-console-run asks with the owner's own token: is this the owner?
create function public.search_console_check_ready() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  return jsonb_build_object('me', v_me, 'key_stored', exists (select 1 from vault.secrets where name = 'search_console_key'));
end $fn$;

-- the owner: disconnect (fresh second factor). The figures already imported stay; nothing new is imported.
create function public.search_console_disconnect() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  perform app.require_fresh_mfa(10);
  update app.integration_connections set status = 'not_connected', connected_at = null where provider = 'search_console';
  perform app.log('search_console.disconnected', 'integration', 'search_console', '{}'::jsonb);
  return jsonb_build_object('status', 'not_connected');
end $fn$;

-- ===========================================================================
-- 3. the worker (service role)
-- ===========================================================================
-- the sites to look for in Search Console
create function public.worker_search_console_sites() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', s.id, 'hostname', s.hostname) order by s.hostname), '[]'::jsonb)
  from app.web_sites s where s.active
$fn$;

-- the verdict of a connect: the key works (or the code why not), and which property each site maps to
create function public.worker_search_console_result(p_ok boolean, p_info jsonb, p_by uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_code text := p_info ->> 'code'; v_was text; x jsonb;
begin
  if p_info is null or jsonb_typeof(p_info) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'info'; end if;
  if v_code is not null and v_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  select status into v_was from app.integration_connections where provider = 'search_console';
  if p_ok then
    for x in select * from jsonb_array_elements(coalesce(p_info -> 'sites', '[]'::jsonb)) loop
      insert into app.search_console_sites (site_id, property, last_error, updated_at)
      select s.id, nullif(x ->> 'property', ''), case when nullif(x ->> 'property', '') is null then 'no_property' end, now()
      from app.web_sites s where s.id = (x ->> 'site_id')::uuid
      on conflict (site_id) do update set property = excluded.property, updated_at = now(),
        last_error = case when excluded.property is null then 'no_property' else null end;
    end loop;
  end if;
  update app.integration_connections set
    status = case when p_ok then 'connected' when status = 'connected' and v_code like 'network%' then status else 'error' end,
    connected_at = case when p_ok then coalesce(connected_at, now()) else connected_at end,
    connected_by = case when p_ok and status <> 'connected' then coalesce(p_by, connected_by) else connected_by end,
    config = config || jsonb_build_object('provider', 'google', 'last_check_at', now(), 'last_error', case when p_ok then null else coalesce(v_code, 'failed') end)
  where provider = 'search_console';
  if p_ok and v_was is distinct from 'connected' then perform app.log('search_console.connected', 'integration', 'search_console', '{}'::jsonb); end if;
  return jsonb_build_object('status', (select status from app.integration_connections where provider = 'search_console'));
end $fn$;

-- what to import: each site with a property, from a few days before its last imported day (Search Console revises the
-- last days) or, the first time, from 180 days back (the longest period Growth › SEO compares: 2 × 90 days)
create function public.worker_search_console_targets() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('site_id', c.site_id, 'property', c.property,
           'from', greatest(coalesce(c.last_day - 4, current_date - 180), current_date - 480), 'to', current_date - 1) order by c.site_id), '[]'::jsonb)
  from app.search_console_sites c join app.web_sites s on s.id = c.site_id
  where s.active and c.property is not null and app.connected('search_console')
$fn$;

-- one site's import: the day totals and the day × query rows, replacing what was there for those days
create function public.worker_search_console_import(p_site uuid, p_totals jsonb, p_rows jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_days date[]; n_t int; n_r int;
begin
  if not exists (select 1 from app.search_console_sites where site_id = p_site and property is not null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if jsonb_typeof(p_totals) <> 'array' or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 100000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  select array_agg(distinct (x ->> 'day')::date) into v_days from jsonb_array_elements(p_totals) x;
  delete from app.search_console_totals where site_id = p_site and day = any (coalesce(v_days, '{}'));
  delete from app.search_console_daily where site_id = p_site and day = any (coalesce(v_days, '{}'));
  insert into app.search_console_totals (day, site_id, impressions, clicks, position)
  select (x ->> 'day')::date, p_site, greatest((x ->> 'impressions')::int, 0), greatest((x ->> 'clicks')::int, 0), nullif((x ->> 'position')::numeric, 0)
  from jsonb_array_elements(p_totals) x
  on conflict (day, site_id) do update set impressions = excluded.impressions, clicks = excluded.clicks, position = excluded.position;
  get diagnostics n_t = row_count;
  insert into app.search_console_daily (day, site_id, query, impressions, clicks, position)
  select (x ->> 'day')::date, p_site, left(lower(btrim(x ->> 'query')), 200), greatest(sum((x ->> 'impressions')::int), 0), greatest(sum((x ->> 'clicks')::int), 0),
         round(sum((x ->> 'position')::numeric * (x ->> 'impressions')::int) / nullif(sum((x ->> 'impressions')::int), 0), 2)
  from jsonb_array_elements(p_rows) x
  where (x ->> 'day')::date = any (coalesce(v_days, '{}')) and coalesce(btrim(x ->> 'query'), '') <> ''
  group by 1, 3;
  get diagnostics n_r = row_count;
  update app.search_console_sites set last_import_at = now(), last_error = null,
    last_day = greatest(last_day, (select max(d) from unnest(v_days) d)), updated_at = now()
  where site_id = p_site;
  return jsonb_build_object('totals', n_t, 'rows', n_r);
end $fn$;

-- a site's import failed: the code, never Google's words
create function public.worker_search_console_failed(p_site uuid, p_code text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  update app.search_console_sites set last_error = p_code, updated_at = now() where site_id = p_site;
end $fn$;

-- ===========================================================================
-- 4. the daily import: while connected, knock on search-console-run
-- ===========================================================================
create function app.search_console_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_key text; v_url text := (select functions_url from app.mail_settings);
begin
  if not app.connected('search_console') then return jsonb_build_object('called', 0); end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'search_console_worker_secret';
  perform net.http_post(url := v_url || '/functions/v1/search-console-run', body := '{"kind":"run"}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 60000);
  return jsonb_build_object('called', 1);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('search_console_import', 'jobs.search_console_import', '41 4 * * *', 'cron', 'app.search_console_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-search-console', '41 4 * * *', 'select app.run_job(''search_console_import'')');

-- ===========================================================================
-- 5. Growth › SEO: 0058's reader, with the totals from Search Console's own day totals and the connection's state
-- ===========================================================================
create or replace function public.seo_get(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_marketing_reports();
  d int := case when p_days in (7, 30, 90) then p_days else 30 end;
  v_site app.web_sites := app.product_site(nullif(p_product, 'all'));
  v_conn boolean := app.connected('search_console');
  c app.integration_connections;
  sc app.search_console_sites;
begin
  select * into c from app.integration_connections where provider = 'search_console';
  select * into sc from app.search_console_sites where site_id = v_site.id;
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
      from app.search_console_totals t where t.site_id = v_site.id and t.day > current_date - 2 * d) end,
    'keywords', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'query', k.query, 'created_at', k.created_at, 'mine', k.created_by = v_me,
        'impressions', case when v_conn then x.i end, 'clicks', case when v_conn then x.c end,
        'position', case when v_conn then x.p end, 'position_prev', case when v_conn then x.pp end) order by k.created_at, k.query)
      from app.seo_keywords k
      left join lateral (
        select sum(sc2.impressions) filter (where sc2.day > current_date - d) i, sum(sc2.clicks) filter (where sc2.day > current_date - d) c,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day > current_date - d and sc2.position is not null), 0), 1) p,
               round(sum(sc2.position * sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null)
                     / nullif(sum(sc2.impressions) filter (where sc2.day <= current_date - d and sc2.position is not null), 0), 1) pp
        from app.search_console_daily sc2 where sc2.site_id = k.site_id and sc2.query = k.query and sc2.day > current_date - 2 * d) x on true
      where k.site_id = v_site.id), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- grants
-- ===========================================================================
revoke all on function app.search_console_tick() from public, anon, authenticated;
revoke all on function public.search_console_intake() from public, anon;
revoke all on function public.search_console_check_ready() from public, anon;
revoke all on function public.search_console_disconnect() from public, anon;
grant execute on function public.search_console_intake(), public.search_console_check_ready(), public.search_console_disconnect() to authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.worker_search_console_sites()', 'public.worker_search_console_result(boolean, jsonb, uuid)', 'public.worker_search_console_targets()',
    'public.worker_search_console_import(uuid, jsonb, jsonb)', 'public.worker_search_console_failed(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
