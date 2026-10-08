-- 0065_safeupdate.sql — every UPDATE and DELETE a client call can reach has a WHERE clause.
--
-- The hosted project loads pg-safeupdate for the authenticator role (session_preload_libraries = supautils, safeupdate):
-- an UPDATE or DELETE without a WHERE clause is refused («UPDATE requires a WHERE clause», 21000), also inside a SECURITY
-- DEFINER function called through PostgREST. The single-row app.mail_settings (0060) was updated without one, so on the
-- hosted project the Brevo key could not be stored, the public address not saved, the provider not disconnected, and
-- mail-run's verdicts and run stamps were refused; app.mcp_index was emptied without one (0044). The local stack runs the
-- suites as postgres directly, which safeupdate does not watch, so they passed. Redefined from their current bodies with
-- «where id» (mail_settings' primary key is the constant true) and «where true»; structure_invariants now refuses any
-- function body with an UPDATE or DELETE that has no WHERE at its top level.

CREATE OR REPLACE FUNCTION public.email_provider_app_base(p_product text, p_base text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require_owner(); v text := nullif(lower(rtrim(btrim(coalesce(p_base, '')), '/')), '');
begin
  if not exists (select 1 from app.products p where p.key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  if v is not null and v !~ '^https://post\.[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'app_base';
  end if;
  update app.mail_settings set app_bases = case when v is null then app_bases - p_product else app_bases || jsonb_build_object(p_product, v) end,
    updated_by = v_me, updated_at = now() where id;
  perform app.log('email_provider.settings', 'integration', 'email', jsonb_build_object('fields', jsonb_build_array('app_bases'), 'product', p_product));
  return jsonb_build_object('product', p_product, 'base', v);
end $function$
;

CREATE OR REPLACE FUNCTION public.email_provider_disconnect()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require_owner();
begin
  perform app.require_fresh_mfa(10);
  update app.integration_connections set status = 'not_connected', connected_at = null where provider = 'email';
  update app.mail_settings set webhook_ok = false, updated_by = v_me, updated_at = now() where id;
  perform app.log('email_provider.disconnected', 'integration', 'email');
  return jsonb_build_object('connected', false);
end $function$
;

CREATE OR REPLACE FUNCTION public.email_provider_settings(p_public_base text, p_inbound_domain text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require_owner(); v text := lower(rtrim(btrim(coalesce(p_public_base, '')), '/'));
        v_in text := nullif(lower(btrim(coalesce(p_inbound_domain, ''))), '');
begin
  if v !~ '^https://[a-z0-9.-]+(:\d+)?$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'public_base'; end if;
  if v_in is not null and v_in !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'inbound_domain';
  end if;
  update app.mail_settings set public_base = v,
    inbound_ok = case when inbound_domain is distinct from v_in then false else inbound_ok end, inbound_domain = v_in,
    updated_by = v_me, updated_at = now() where id;
  perform app.log('email_provider.settings', 'integration', 'email', jsonb_build_object('fields', jsonb_build_array('public_base', 'inbound_domain')));
  return jsonb_build_object('public_base', v, 'inbound_domain', v_in);
end $function$
;

CREATE OR REPLACE FUNCTION app.mcp_index_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e app.entities; n int := 0; m int; v_txt text;
begin
  if app.setting('mcp_sync') <> 'on' then
    delete from app.mcp_index where true;
    return 0;
  end if;
  for e in select * from app.api_entities() x where x.owned loop
    v_txt := (select string_agg(format('coalesce(t.%I::text, '''')', s), ' || '' '' || ') from unnest(e.search) s);
    execute format($q$insert into app.mcp_index (entity, record_id, title, body, owner_id, visibility, updated_at)
                      select %L, t.id, left(coalesce(t.%I::text, ''), 300), to_tsvector('simple', coalesce(t.%I::text, '') || ' ' || %s), t.owner_id, t.visibility, t.updated_at
                      from app.%I t where t.deleted_at is null and not t.is_sample
                      on conflict (entity, record_id) do update set title = excluded.title, body = excluded.body, owner_id = excluded.owner_id,
                        visibility = excluded.visibility, updated_at = excluded.updated_at where app.mcp_index.updated_at < excluded.updated_at$q$,
                   e.key, e.title_col, e.title_col, coalesce(v_txt, ''''''), e.tbl);
    get diagnostics m = row_count; n := n + m;
    execute format('delete from app.mcp_index i where i.entity = %L and not exists (select 1 from app.%I t where t.id = i.record_id and t.deleted_at is null and not t.is_sample)',
                   e.key, e.tbl);
  end loop;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.mcp_sync_set(p_on boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform app.require('global', 'configure');
  if p_on is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'on'; end if;
  perform public.setting_set('mcp_sync', case when p_on then 'on' else 'off' end);
  if not p_on then delete from app.mcp_index where true; end if;
  return jsonb_build_object('sync', case when p_on then 'on' else 'off' end);
end $function$
;

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
end $function$
;

CREATE OR REPLACE FUNCTION public.worker_email_provider_result(p_ok boolean, p_info jsonb, p_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_code text := p_info ->> 'code'; v_was text;
begin
  if p_info is null or jsonb_typeof(p_info) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'info'; end if;
  if v_code is not null and v_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  select status into v_was from app.integration_connections where provider = 'email';
  update app.integration_connections set
    status = case when p_ok then 'connected' when status = 'connected' and v_code like 'network%' then status else 'error' end,
    connected_at = case when p_ok then coalesce(connected_at, now()) else connected_at end,
    connected_by = case when p_ok and status <> 'connected' then coalesce(p_by, connected_by) else connected_by end,
    config = config || jsonb_build_object('provider', 'brevo')
  where provider = 'email';
  update app.mail_settings set
    account = case when p_ok and jsonb_typeof(p_info -> 'account') = 'object' then p_info -> 'account' else account end,
    webhook_ok = coalesce((p_info ->> 'webhook_ok')::boolean, webhook_ok),
    inbound_ok = coalesce((p_info ->> 'inbound_ok')::boolean, inbound_ok),
    last_check_at = now(), last_error = case when p_ok then null else coalesce(v_code, 'failed') end, updated_at = now() where id;
  if p_ok and v_was is distinct from 'connected' then
    perform app.log('email_provider.connected', 'integration', 'email', '{}'::jsonb);
    -- what waited for the provider goes now: held campaigns are due again, held alerts are queued
    update app.campaigns set hold_reason = null where hold_reason = 'not_connected:email';
    update app.security_alert_deliveries set status = 'queued' where channel = 'email' and status = 'not_connected'
      and event_id in (select id from app.security_events where at > now() - interval '1 day');
  elsif not p_ok then
    perform app.log('email_provider.check_failed', 'integration', 'email', jsonb_build_object('code', coalesce(v_code, 'failed')));
  end if;
  return jsonb_build_object('status', (select status from app.integration_connections where provider = 'email'));
end $function$
;

CREATE OR REPLACE FUNCTION public.worker_mail_run_done(p_info jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update app.mail_settings set last_run_at = now() where id;
  if p_error is not null or exists (select 1 from jsonb_each(coalesce(p_info, '{}'::jsonb)) x(k, v) where jsonb_typeof(v) = 'number' and (v #>> '{}')::numeric <> 0) then
    return public.worker_job_run('mail_send', case when p_error is null then 'succeeded' else 'failed' end, coalesce(p_info, '{}'::jsonb), p_error);
  end if;
  return '{}'::jsonb;
end $function$
;
