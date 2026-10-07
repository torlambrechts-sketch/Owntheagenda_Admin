-- 0063_mail_link_hosts.sql — an application's campaigns link to an address of its own (0062 made the campaign the
-- application's; its unsubscribe link still opened on Sentral's host).
--
-- The owner saves, per application, a link address: https://post.<the application's domain>. It is the same deployment
-- as Sentral (the domain is added to the Vercel project and pointed there in DNS), and on a «post.» host the app serves
-- the unsubscribe page and nothing else (middleware.ts). A campaign's unsubscribe link opens on its application's link
-- address; without one, on Sentral's public address as before.

alter table app.mail_settings add column app_bases jsonb not null default '{}'::jsonb check (jsonb_typeof(app_bases) = 'object');

-- the owner: one application's link address, or null to go back to Sentral's own
create function public.email_provider_app_base(p_product text, p_base text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := nullif(lower(rtrim(btrim(coalesce(p_base, '')), '/')), '');
begin
  if not exists (select 1 from app.products p where p.key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  if v is not null and v !~ '^https://post\.[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'app_base';
  end if;
  update app.mail_settings set app_bases = case when v is null then app_bases - p_product else app_bases || jsonb_build_object(p_product, v) end,
    updated_by = v_me, updated_at = now();
  perform app.log('email_provider.settings', 'integration', 'email', jsonb_build_object('fields', jsonb_build_array('app_bases'), 'product', p_product));
  return jsonb_build_object('product', p_product, 'base', v);
end $fn$;

-- mail-run: where one campaign's links open (its application's address, else Sentral's)
create function public.worker_campaign_base(p_campaign uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(s.app_bases ->> c.product, s.public_base) from app.campaigns c cross join app.mail_settings s where c.id = p_campaign
$fn$;

-- 0061's provider state plus each application's link address
create or replace function public.email_provider_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); s app.mail_settings; c app.integration_connections; d app.sender_domains := app.mail_sender();
begin
  select * into s from app.mail_settings;
  select * into c from app.integration_connections where provider = 'email';
  return jsonb_build_object(
    'provider', 'brevo',
    'status', c.status,
    'connected', c.status = 'connected',
    'connected_at', c.connected_at,
    'key_stored', exists (select 1 from vault.secrets where name = 'brevo_api_key'),
    'public_base', s.public_base,
    'app_bases', coalesce(s.app_bases, '{}'::jsonb),
    'inbound_domain', s.inbound_domain,
    'inbound_ok', s.inbound_ok,
    'account', case when app.can('global', 'configure') then s.account else '{}'::jsonb end,
    'webhook_ok', s.webhook_ok,
    'last_check_at', s.last_check_at,
    'last_error', s.last_error,
    'last_run_at', s.last_run_at,
    'ready', app.mail_ready(),
    'ready_products', coalesce((select jsonb_agg(p.key order by p.key) from app.products p where app.mail_ready_for(p.key)), '[]'::jsonb),
    'sender', case when d.id is not null then jsonb_build_object('id', d.id, 'address', d.from_local || '@' || d.domain, 'name', d.from_name,
                                                               'reply_to', d.reply_to, 'stream', d.stream) end,
    'senders', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'domain', x.domain, 'stream', x.stream, 'sends_here', x.sends_here,
                          'address', x.from_local || '@' || x.domain, 'name', x.from_name, 'reply_to', x.reply_to, 'product', x.product,
                          'authenticated', app.domain_authenticated(x), 'verified', app.domain_verified(x), 'last_checked_at', x.last_checked_at,
                          'version', x.version) order by x.product nulls first, x.created_at)
                         from app.sender_domains x where x.deleted_at is null), '[]'::jsonb),
    'waiting', jsonb_build_object(
      'tickets', (select count(*) from app.ticket_messages where delivery_status = 'queued'),
      'invites', (select count(*) from app.admins where invite_state = 'queued'),
      'alerts', (select count(*) from app.security_alert_deliveries where channel = 'email' and status = 'queued'),
      'jobs', (select count(*) from pgmq.q_jobs where message ->> 'job' = any (app.mail_job_kinds()))),
    'failed_24h', (select count(*) from app.ticket_messages where delivery_status in ('failed', 'bounced') and created_at > now() - interval '1 day'),
    'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'));
end $fn$;

revoke all on function public.email_provider_app_base(text, text) from public, anon;
grant execute on function public.email_provider_app_base(text, text) to authenticated;
revoke all on function public.worker_campaign_base(uuid) from public, anon, authenticated;
grant execute on function public.worker_campaign_base(uuid) to service_role;
