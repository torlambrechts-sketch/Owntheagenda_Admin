-- 0060_brevo.sql — the mail provider: Brevo (D-07). Until now every screen queued or recorded mail and nothing sent it.
--
-- 1. The connection. The owner opens an intake number (fresh second factor) and pastes the Brevo API key into a field that
--    posts it straight to secret-intake: it lands in Vault as «brevo_api_key» and is never shown again (security rule 5).
--    The mail-run function then proves the key against Brevo and reports here; only that report marks «email» connected.
-- 2. Two secrets nobody types: «mail_worker_secret» (the cron's knock on mail-run) and «mail_events_secret» (Brevo's
--    webhook to mail-events), generated here in Vault.
-- 3. What the worker claims: the jobs other migrations put on the «jobs» queue for mail (campaign_send, campaign_test,
--    dns_check, mfa_reminder), ticket replies, staff invitations and security alert emails. Ticket replies, invitations
--    and alert emails are claimed from their own rows (a lease, never lost); queue jobs are taken off the queue.
-- 4. app.mail_tick (every minute, quiet): while connected and something waits, it calls mail-run through pg_net.
-- 5. Ticket replies are emailed from the transactional sender, and the customer's answer by email is threaded back onto
--    the ticket when it names it ([T-1234]) and comes from the ticket's requester.
-- 6. Events: delivered and bounced on ticket replies; campaigns keep worker_email_events (0037).
--
-- Nothing here logs an address or a body. Brevo's webhooks are account-wide, so mail-events drops every event whose tag is
-- not one of Sentral's before reading anything else (Orgpuls's survey invitations share the account: rule 6).

create extension if not exists pg_net with schema extensions;

-- ===========================================================================
-- 1. settings and secrets
-- ===========================================================================
create table app.mail_settings (
  id             boolean primary key default true check (id),
  -- where pg_net reaches the edge functions (hosted: the project URL; local: the API gateway inside Docker)
  functions_url  text not null default 'https://zuvqbaejoktpekfsiyyr.supabase.co' check (functions_url ~ '^https?://[A-Za-z0-9._-]+(:\d+)?$'),
  -- the public address unsubscribe and invitation links open (the app's own host, set by the owner when connecting)
  public_base    text check (public_base is null or public_base ~ '^https://[a-z0-9.-]+(:\d+)?$'),
  account        jsonb not null default '{}'::jsonb check (jsonb_typeof(account) = 'object'),
  webhook_ok     boolean not null default false,
  last_check_at  timestamptz,
  last_error     text check (last_error is null or last_error ~ '^[a-z0-9_.:-]{1,60}$'),
  last_run_at    timestamptz,
  updated_by     uuid references app.admins (id) on delete set null,
  updated_at     timestamptz not null default now()
);
insert into app.mail_settings default values;
alter table app.mail_settings enable row level security;
revoke all on app.mail_settings from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'mail_worker_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mail_worker_secret', 'The cron''s key to mail-run (0060). Generated; nobody types it.');
  end if;
  if not exists (select 1 from vault.secrets where name = 'mail_events_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mail_events_secret', 'Brevo''s key to mail-events (0060). Generated; nobody types it.');
  end if;
end $$;

-- the edge functions read these three names besides the products' secrets
create or replace function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and (p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or p_name in ('brevo_api_key', 'mail_worker_secret', 'mail_events_secret'))
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;

-- an intake number for the mail provider's key: bound to the purpose, not to a product
alter table app.intake_nonces add column purpose text check (purpose is null or purpose = 'brevo');

create or replace function public.store_product_secrets(p_nonce text, p_secrets jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare k text; v text; n int := 0; v_product text; v_purpose text;
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

-- ===========================================================================
-- 2. the connection, as the owner and the screens see it
-- ===========================================================================
-- the sender transactional mail goes from: a verified domain that sends here, the transactional stream first
create function app.mail_sender() returns app.sender_domains
  language sql stable security definer set search_path = ''
as $fn$
  select d.* from app.sender_domains d
  where d.deleted_at is null and d.sends_here and app.domain_verified(d)
  order by (d.stream = 'transactional') desc, d.created_at limit 1
$fn$;

-- can transactional mail go out right now (connected, a verified sender, a public address for links)?
create function app.mail_ready() returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.connected('email') and (app.mail_sender()).id is not null
$fn$;

create function public.email_provider_get() returns jsonb
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
    'account', case when app.can('global', 'configure') then s.account else '{}'::jsonb end,
    'webhook_ok', s.webhook_ok,
    'last_check_at', s.last_check_at,
    'last_error', s.last_error,
    'last_run_at', s.last_run_at,
    'ready', app.mail_ready(),
    'sender', case when d.id is not null then jsonb_build_object('id', d.id, 'address', d.from_local || '@' || d.domain, 'name', d.from_name,
                                                               'reply_to', d.reply_to, 'stream', d.stream) end,
    'senders', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'domain', x.domain, 'stream', x.stream, 'sends_here', x.sends_here,
                          'address', x.from_local || '@' || x.domain, 'name', x.from_name, 'reply_to', x.reply_to,
                          'authenticated', app.domain_authenticated(x), 'verified', app.domain_verified(x), 'last_checked_at', x.last_checked_at,
                          'version', x.version) order by x.created_at)
                         from app.sender_domains x where x.deleted_at is null), '[]'::jsonb),
    'waiting', jsonb_build_object(
      'tickets', (select count(*) from app.ticket_messages where delivery_status = 'queued'),
      'invites', (select count(*) from app.admins where invite_state = 'queued'),
      'alerts', (select count(*) from app.security_alert_deliveries where channel = 'email' and status = 'queued'),
      'jobs', (select count(*) from pgmq.q_jobs where message ->> 'job' = any (app.mail_job_kinds()))),
    'failed_24h', (select count(*) from app.ticket_messages where delivery_status in ('failed', 'bounced') and created_at > now() - interval '1 day'),
    'can_manage', exists (select 1 from app.admins where id = v_me and role = 'owner'));
end $fn$;

-- the owner: an intake number for the key (fresh second factor). The answer is used by the owner's own browser to post the
-- key to secret-intake; it never reaches a log or another person.
create function public.email_provider_intake() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform app.require_fresh_mfa(10);
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at, purpose) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes', 'brevo');
  perform app.log('email_provider.intake_opened', 'integration', 'email');
  return jsonb_build_object('intake_code', v, 'expires_in', 900);
end $fn$;

-- the owner: the public address links in mail open (unsubscribe, invitations)
create function public.email_provider_settings(p_public_base text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner(); v text := lower(rtrim(btrim(coalesce(p_public_base, '')), '/'));
begin
  if v !~ '^https://[a-z0-9.-]+(:\d+)?$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'public_base'; end if;
  update app.mail_settings set public_base = v, updated_by = v_me, updated_at = now();
  perform app.log('email_provider.settings', 'integration', 'email', jsonb_build_object('fields', jsonb_build_array('public_base')));
  return jsonb_build_object('public_base', v);
end $fn$;

-- the owner: disconnect. The key stays in Vault until replaced; nothing sends while disconnected.
create function public.email_provider_disconnect() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_owner();
begin
  perform app.require_fresh_mfa(10);
  update app.integration_connections set status = 'not_connected', connected_at = null where provider = 'email';
  update app.mail_settings set webhook_ok = false, updated_by = v_me, updated_at = now();
  perform app.log('email_provider.disconnected', 'integration', 'email');
  return jsonb_build_object('connected', false);
end $fn$;

-- mail-run's verdict on the key (connect probe). p_info: {account:{plan, company?}, webhook_ok, code?}. Only counts and names
-- of plans are kept, never an address.
create function public.worker_email_provider_result(p_ok boolean, p_info jsonb, p_by uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
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
    last_check_at = now(), last_error = case when p_ok then null else coalesce(v_code, 'failed') end, updated_at = now();
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
end $fn$;

-- the owner asks for a check now (after pasting the key): mail-run is called with the owner's own token by the app, this
-- only says whether a key is there to check
create function public.email_provider_check_ready() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_owner();
  return jsonb_build_object('key_stored', exists (select 1 from vault.secrets where name = 'brevo_api_key'));
end $fn$;

-- ===========================================================================
-- 3. what the worker claims
-- ===========================================================================
create function app.mail_job_kinds() returns text[]
  language sql immutable set search_path = ''
as $fn$ select array['campaign_send', 'campaign_test', 'dns_check', 'mfa_reminder'] $fn$;

-- take up to p_limit mail jobs off the queue (each underlying row keeps its own state: a campaign's recipients are leased
-- by worker_campaign_batch and requeued by campaign_due; a lost test send or DNS check is simply asked for again)
create function public.worker_mail_take(p_limit int default 20) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare out jsonb;
begin
  with picked as (
    select q.msg_id from pgmq.q_jobs q where q.message ->> 'job' = any (app.mail_job_kinds()) and q.vt <= clock_timestamp()
    order by q.msg_id limit least(greatest(coalesce(p_limit, 20), 1), 200) for update skip locked
  ), gone as (
    delete from pgmq.q_jobs q using picked where q.msg_id = picked.msg_id returning q.msg_id, q.message
  )
  select coalesce(jsonb_agg(gone.message order by gone.msg_id), '[]'::jsonb) into out from gone;
  return out;
end $fn$;

-- the run as the registry sees it (Settings › jobs): counts only
insert into app.job_defs (key, label_key, source) values ('mail_send', 'jobs.mail_send', 'queue') on conflict (key) do nothing;

create function public.worker_mail_run_done(p_info jsonb, p_error text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.mail_settings set last_run_at = now();
  if p_error is not null or exists (select 1 from jsonb_each(coalesce(p_info, '{}'::jsonb)) x(k, v) where jsonb_typeof(v) = 'number' and (v #>> '{}')::numeric <> 0) then
    return public.worker_job_run('mail_send', case when p_error is null then 'succeeded' else 'failed' end, coalesce(p_info, '{}'::jsonb), p_error);
  end if;
  return '{}'::jsonb;
end $fn$;

-- the staff member a mail is about (MFA reminder, invitation): address, name, language, and who asked
create function public.worker_staff_mail(p_staff uuid, p_by uuid default null) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select case when a.id is null then null else jsonb_build_object(
    'id', a.id, 'email', a.email, 'name', a.name, 'locale', coalesce(a.locale, 'en'), 'active', a.active,
    'login', exists (select 1 from auth.users u where lower(u.email) = a.email and u.email_confirmed_at is not null),
    'mfa', app.staff_mfa_verified(a.email),
    'by_name', (select coalesce(b.name, b.email) from app.admins b where b.id = p_by)) end
  from (select 1) one left join app.admins a on a.id = p_staff
$fn$;

-- ===========================================================================
-- 4. ticket replies by email, and the customer's answer back onto the ticket
-- ===========================================================================
alter table app.ticket_messages drop constraint ticket_messages_delivery_status_check;
alter table app.ticket_messages add constraint ticket_messages_delivery_status_check
  check (delivery_status is null or delivery_status in ('queued', 'sent', 'delivered', 'bounced', 'failed', 'not_configured'));
alter table app.ticket_messages
  add column mail_claimed_at timestamptz,
  add column mail_attempts smallint not null default 0 check (mail_attempts between 0 and 20),
  add column mail_error text check (mail_error is null or mail_error ~ '^[a-z0-9_.:-]{1,60}$'),
  add column mail_sent_at timestamptz,
  add column provider_message_id text check (provider_message_id is null or char_length(provider_message_id) <= 200),
  add column inbound_id text check (inbound_id is null or char_length(inbound_id) <= 200);
create unique index ticket_messages_provider_id on app.ticket_messages (provider_message_id) where provider_message_id is not null;
create unique index ticket_messages_inbound_id on app.ticket_messages (inbound_id) where inbound_id is not null;
create index ticket_messages_mail_queue on app.ticket_messages (created_at) where delivery_status = 'queued';

-- where a ticket's reply goes: the requester's address, else the person's
create function app.ticket_recipient(t app.tickets) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select nullif(lower(btrim(coalesce(t.requester_email, (select p.email from app.people p where p.id = t.person_id and p.deleted_at is null)))), '')
$fn$;

-- 0012's ticket_message, unchanged except the reply's delivery: queued when the provider and a sender are ready and the
-- ticket has an address, else «not_configured» as before. Sample tickets never send.
create or replace function public.ticket_message(p_id uuid, p_kind text, p_body text, p_after text default null, p_macro uuid default null, p_mentions uuid[] default '{}')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); t app.tickets; v_msg uuid; v_delivery text;
begin
  if p_kind not in ('reply', 'note') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  select * into t from app.tickets where id = p_id and deleted_at is null for update;
  if not found or not app.queue_ok(t.queue_key) or not app.visible(t.owner_id, t.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.assignee_id is distinct from v_me and t.owner_id is distinct from v_me and not app.can('tickets', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'tickets:edit_others';
  end if;
  v_delivery := case when p_kind <> 'reply' then null
                     when not t.is_sample and app.mail_ready() and app.ticket_recipient(t) is not null then 'queued'
                     else 'not_configured' end;
  insert into app.ticket_messages (ticket_id, kind, author_staff_id, body, macro_id, mentions, delivery_status)
  values (p_id, p_kind, v_me, btrim(p_body), p_macro, coalesce(p_mentions, '{}'), v_delivery)
  returning id into v_msg;
  if p_kind = 'reply' then
    update app.tickets set first_response_at = coalesce(first_response_at, now()),
      status = case when p_after in ('waiting_customer', 'resolved', 'open', 'waiting_us', 'closed') then p_after when status = 'new' then 'open' else status end,
      assignee_id = coalesce(assignee_id, v_me), version = version + 1, updated_at = now(), updated_by = v_me
    where id = p_id;
    perform app.emit('ticket.replied', 'ticket', p_id, jsonb_build_object('message', v_msg), t.is_sample);
  else
    perform app.notify(m, 'mention', 'mention', jsonb_build_object('actor', (select name from app.admins where id = v_me), 'record', 'T-' || t.number, 'excerpt', ''),
                       '/tickets?ticket=' || p_id, 'ticket', p_id)
    from unnest(coalesce(p_mentions, '{}')) m where m <> v_me;
  end if;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('ticket', p_id, '*' || p_kind, jsonb_build_object('message', v_msg), v_me);
  perform app.log(case p_kind when 'reply' then 'ticket.replied' else 'ticket.noted' end, 'ticket', p_id::text, jsonb_build_object('message', v_msg),
                  (select account_id from app.organizations where id = t.organization_id));
  return jsonb_build_object('id', v_msg, 'delivery', v_delivery);
end $fn$;

-- the worker's lease on queued replies (ten minutes; a reply that failed twenty times stays failed)
create function public.worker_ticket_mail_claim(p_limit int default 20) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m record; t app.tickets; d app.sender_domains := app.mail_sender(); out jsonb := '[]'::jsonb; v_to text;
begin
  if not app.mail_ready() then return out; end if;
  for m in select x.* from app.ticket_messages x where x.delivery_status = 'queued' and x.kind = 'reply'
             and (x.mail_claimed_at is null or x.mail_claimed_at < now() - interval '10 minutes')
           order by x.created_at limit least(greatest(coalesce(p_limit, 20), 1), 100) for update skip locked loop
    select * into t from app.tickets where id = m.ticket_id;
    v_to := app.ticket_recipient(t);
    if v_to is null or t.deleted_at is not null then
      update app.ticket_messages set delivery_status = 'failed', mail_error = 'no_recipient', mail_claimed_at = null where id = m.id;
      continue;
    end if;
    update app.ticket_messages set mail_claimed_at = now(), mail_attempts = mail_attempts + 1 where id = m.id;
    out := out || jsonb_build_array(jsonb_build_object(
      'id', m.id, 'ref', 'T-' || t.number, 'subject', t.subject, 'body', m.body,
      'to', v_to, 'to_name', (select p.name from app.people p where p.id = t.person_id),
      'agent', (select coalesce(a.name, a.email) from app.admins a where a.id = m.author_staff_id),
      'from', d.from_local || '@' || d.domain, 'from_name', d.from_name, 'reply_to', coalesce(d.reply_to, d.from_local || '@' || d.domain),
      'locale', coalesce((select a.locale from app.admins a where a.id = m.author_staff_id), 'no')));
  end loop;
  return out;
end $fn$;

-- the outcome of one reply. p_code: null when sent; a retryable failure keeps it queued until the twentieth attempt.
create function public.worker_ticket_mail_done(p_message uuid, p_provider_message_id text, p_code text default null, p_retry boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.ticket_messages;
begin
  if p_code is not null and p_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  select * into m from app.ticket_messages where id = p_message for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_code is null then
    update app.ticket_messages set delivery_status = 'sent', mail_sent_at = now(), mail_claimed_at = null, mail_error = null,
      provider_message_id = left(nullif(btrim(p_provider_message_id), ''), 200), email_message_id = left(nullif(btrim(p_provider_message_id), ''), 200)
    where id = p_message;
  elsif p_retry and m.mail_attempts < 20 then
    update app.ticket_messages set mail_claimed_at = now() - interval '9 minutes' + least(m.mail_attempts, 10) * interval '1 minute', mail_error = p_code where id = p_message;
  else
    update app.ticket_messages set delivery_status = 'failed', mail_claimed_at = null, mail_error = p_code where id = p_message;
    perform app.notify(m.author_staff_id, 'system', 'tickets.mail_failed', jsonb_build_object('code', p_code),
                       '/tickets?ticket=' || m.ticket_id, 'ticket', m.ticket_id)
    where m.author_staff_id is not null;
  end if;
  return jsonb_build_object('ok', true);
end $fn$;

-- Brevo's events about a reply (delivered, bounced): matched by the message id Brevo gave at send
create function public.worker_ticket_mail_event(p_provider_message_id text, p_kind text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.ticket_messages;
begin
  if p_kind not in ('delivered', 'bounced', 'failed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  select * into m from app.ticket_messages where provider_message_id = p_provider_message_id for update;
  if not found then return jsonb_build_object('matched', false); end if;
  update app.ticket_messages set delivery_status = case
      when p_kind = 'delivered' and delivery_status in ('sent', 'queued') then 'delivered'
      when p_kind in ('bounced', 'failed') then 'bounced' else delivery_status end,
    mail_error = case when p_kind <> 'delivered' then p_kind else mail_error end
  where id = m.id;
  if p_kind <> 'delivered' and m.delivery_status <> 'bounced' and m.author_staff_id is not null then
    perform app.notify(m.author_staff_id, 'system', 'tickets.mail_failed', jsonb_build_object('code', p_kind),
                       '/tickets?ticket=' || m.ticket_id, 'ticket', m.ticket_id);
  end if;
  return jsonb_build_object('matched', true);
end $fn$;

-- the customer's answer by email (Brevo inbound parsing): threaded onto the ticket its subject names, only when it comes
-- from that ticket's requester. Anything else is dropped and counted, never stored (a person's own words go only where
-- they wrote them). Idempotent on Brevo's inbound id.
create function public.worker_ticket_inbound(p_inbound_id text, p_from text, p_subject text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_num bigint; t app.tickets; v_body text := btrim(coalesce(p_body, '')); v_msg uuid;
begin
  if coalesce(btrim(p_inbound_id), '') = '' or char_length(p_inbound_id) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'id'; end if;
  if exists (select 1 from app.ticket_messages where inbound_id = p_inbound_id) then return jsonb_build_object('matched', true, 'duplicate', true); end if;
  v_num := nullif(substring(coalesce(p_subject, '') from '\[T-(\d{1,12})\]'), '')::bigint;
  if v_num is null or v_body = '' then return jsonb_build_object('matched', false); end if;
  select * into t from app.tickets where number = v_num and deleted_at is null for update;
  if not found or app.ticket_recipient(t) is distinct from lower(btrim(coalesce(p_from, ''))) then return jsonb_build_object('matched', false); end if;
  insert into app.ticket_messages (ticket_id, kind, author_person_id, body, inbound_id)
  values (t.id, 'customer', t.person_id, left(v_body, 20000), p_inbound_id) returning id into v_msg;
  update app.tickets set status = case when status in ('waiting_customer', 'resolved') then 'waiting_us' when status = 'closed' then 'open' else status end,
    reopened_count = reopened_count + case when status in ('resolved', 'closed') then 1 else 0 end, version = version + 1, updated_at = now()
  where id = t.id;
  perform app.emit('ticket.customer_replied', 'ticket', t.id, jsonb_build_object('message', v_msg), t.is_sample);
  if t.assignee_id is not null then
    perform app.notify(t.assignee_id, 'system', 'tickets.customer_replied', jsonb_build_object('record', 'T-' || t.number),
                       '/tickets?ticket=' || t.id, 'ticket', t.id);
  end if;
  return jsonb_build_object('matched', true);
end $fn$;

-- ===========================================================================
-- 5. staff invitations
-- ===========================================================================
alter table app.admins
  add column invite_state text check (invite_state is null or invite_state in ('queued', 'sent', 'failed')),
  add column invite_requested_at timestamptz,
  add column invite_claimed_at timestamptz,
  add column invite_sent_at timestamptz,
  add column invite_error text check (invite_error is null or invite_error ~ '^[a-z0-9_.:-]{1,60}$'),
  add column invited_by uuid references app.admins (id) on delete set null;

-- queue an invitation for a staff member without a confirmed login
create function app.staff_invite_queue(p_staff uuid, p_by uuid) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.admins;
begin
  select * into a from app.admins where id = p_staff for update;
  if not found or not a.active or a.is_sample then return 'skipped'; end if;
  if exists (select 1 from auth.users u where lower(u.email) = a.email and u.email_confirmed_at is not null and u.encrypted_password is not null and u.encrypted_password <> '') then
    return 'has_login';
  end if;
  if not app.mail_ready() or (select public_base from app.mail_settings) is null then return 'not_connected'; end if;
  update app.admins set invite_state = 'queued', invite_requested_at = now(), invite_claimed_at = null, invite_error = null, invited_by = p_by where id = p_staff;
  return 'queued';
end $fn$;

-- 0057's staff_save, unchanged except that a new staff member's invitation is queued (and the answer says whether)
create or replace function public.staff_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_id uuid; v_email text; v_set uuid := (p_values ->> 'permission_set_id')::uuid;
        v_current uuid; v_role text; v_invite text;
begin
  if p_id is null then
    if v_set is not null and not exists (select 1 from app.permission_sets where id = v_set and offered) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'permission_set';
    end if;
    v_email := lower(btrim(p_values ->> 'email'));
    insert into app.admins (email, name, initials, title, permission_set_id, group_id, team_id, locale, time_zone, created_by)
    values (v_email, nullif(btrim(p_values ->> 'name'), ''), nullif(btrim(p_values ->> 'initials'), ''), nullif(btrim(p_values ->> 'title'), ''),
            coalesce(v_set, (select id from app.permission_sets where key = 'analyst')),
            coalesce((p_values ->> 'group_id')::uuid, (select id from app.visibility_groups where parent_id is null)),
            (p_values ->> 'team_id')::uuid, coalesce(p_values ->> 'locale', 'en'), coalesce(p_values ->> 'time_zone', 'Europe/Oslo'), v_me)
    returning id into v_id;
    perform app.log('staff.invited', 'staff', v_id::text);
    v_invite := app.staff_invite_queue(v_id, v_me);
  else
    if p_id = v_me and (p_values ? 'active' or p_values ? 'permission_set_id') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'self';
    end if;
    select permission_set_id, role into v_current, v_role from app.admins where id = p_id;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if v_role = 'owner' and (p_values ? 'active' or (v_set is not null and v_set <> v_current)) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'owner';
    end if;
    if v_set is not null and v_set <> v_current and not exists (select 1 from app.permission_sets where id = v_set and offered) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'permission_set';
    end if;
    update app.admins set
      name = case when p_values ? 'name' then nullif(btrim(p_values ->> 'name'), '') else name end,
      initials = case when p_values ? 'initials' then nullif(btrim(p_values ->> 'initials'), '') else initials end,
      title = case when p_values ? 'title' then nullif(btrim(p_values ->> 'title'), '') else title end,
      permission_set_id = coalesce(v_set, permission_set_id),
      group_id = coalesce((p_values ->> 'group_id')::uuid, group_id),
      team_id = case when p_values ? 'team_id' then (p_values ->> 'team_id')::uuid else team_id end,
      active = coalesce((p_values ->> 'active')::boolean, active),
      updated_at = now()
    where id = p_id returning id into v_id;
    perform app.log('staff.updated', 'staff', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  end if;
  return jsonb_build_object('id', v_id) || case when v_invite is not null then jsonb_build_object('invite', v_invite) else '{}'::jsonb end;
end $fn$;

-- send (or send again) an invitation to someone without a login
create function public.staff_invite_send(p_staff uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v text;
begin
  if not exists (select 1 from app.admins where id = p_staff) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v := app.staff_invite_queue(p_staff, v_me);
  if v = 'not_connected' then raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'email'; end if;
  if v = 'has_login' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'has_login'; end if;
  if v = 'skipped' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'inactive'; end if;
  perform app.log('staff.invite_sent', 'staff', p_staff::text);
  return jsonb_build_object('invite', v);
end $fn$;

create function public.worker_invite_claim(p_limit int default 10) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.admins; d app.sender_domains := app.mail_sender(); out jsonb := '[]'::jsonb; v_base text := (select public_base from app.mail_settings);
begin
  if not app.mail_ready() or v_base is null then return out; end if;
  for a in select * from app.admins x where x.invite_state = 'queued' and x.active
             and (x.invite_claimed_at is null or x.invite_claimed_at < now() - interval '10 minutes')
           order by x.invite_requested_at limit least(greatest(coalesce(p_limit, 10), 1), 50) for update skip locked loop
    update app.admins set invite_claimed_at = now() where id = a.id;
    out := out || jsonb_build_array(jsonb_build_object('id', a.id, 'email', a.email, 'name', a.name, 'locale', coalesce(a.locale, 'en'),
      'by_name', (select coalesce(b.name, b.email) from app.admins b where b.id = a.invited_by), 'public_base', v_base,
      'from', d.from_local || '@' || d.domain, 'from_name', d.from_name, 'reply_to', d.reply_to));
  end loop;
  return out;
end $fn$;

create function public.worker_invite_done(p_staff uuid, p_code text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if p_code is not null and p_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  update app.admins set invite_state = case when p_code is null then 'sent' else 'failed' end,
    invite_sent_at = case when p_code is null then now() else invite_sent_at end, invite_error = p_code, invite_claimed_at = null
  where id = p_staff and invite_state = 'queued';
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('ok', true);
end $fn$;

-- 0057's staff_list plus the invitation's state (security right)
create or replace function public.staff_list() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_full boolean := app.can('global', 'security');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'initials', a.initials, 'title', a.title,
           'email', case when v_full or a.id = v_me then a.email end, 'active', a.active, 'permission_set_id', a.permission_set_id,
           'permission_set', ps.name, 'permission_set_key', ps.key, 'owner', a.role = 'owner',
           'group_id', a.group_id, 'group', g.name, 'team_id', a.team_id, 'last_seen_at', case when v_full then a.last_seen_at end,
           'is_sample', a.is_sample,
           'mfa', case when v_full then (select coalesce(bool_or(f.status = 'verified'), false) from auth.mfa_factors f join auth.users u on u.id = f.user_id
                                         where lower(u.email) = a.email and f.factor_type = 'totp') end,
           'login', case when v_full then exists (select 1 from auth.users u where lower(u.email) = a.email and u.email_confirmed_at is not null) end,
           'invite_state', case when v_full then a.invite_state end,
           'invite_sent_at', case when v_full then a.invite_sent_at end)
         order by a.active desc, coalesce(a.name, a.email))
    from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id join app.visibility_groups g on g.id = a.group_id
    where not a.is_sample or (select sandbox from app.admins where id = v_me)), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- 6. security alert emails and the MFA reminder
-- ===========================================================================
alter table app.security_alert_deliveries add column claimed_at timestamptz;

create function public.worker_alert_mail_claim(p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; d app.sender_domains := app.mail_sender(); out jsonb := '[]'::jsonb;
begin
  if not app.mail_ready() then return out; end if;
  for r in select x.event_id, x.recipient_id, e.kind, e.severity, e.at, e.detail, e.subject_staff_id, a.email, coalesce(a.locale, 'en') locale
           from app.security_alert_deliveries x join app.security_events e on e.id = x.event_id join app.admins a on a.id = x.recipient_id
           where x.channel = 'email' and x.status = 'queued' and a.active
             and (x.claimed_at is null or x.claimed_at < now() - interval '10 minutes')
           order by x.event_id limit least(greatest(coalesce(p_limit, 50), 1), 200) for update of x skip locked loop
    update app.security_alert_deliveries set claimed_at = now() where event_id = r.event_id and channel = 'email' and recipient_id = r.recipient_id;
    out := out || jsonb_build_array(jsonb_build_object('event', r.event_id, 'recipient', r.recipient_id, 'kind', r.kind, 'severity', r.severity, 'at', r.at,
      'staff', (select coalesce(s.name, s.email) from app.admins s where s.id = r.subject_staff_id),
      'to', r.email, 'locale', r.locale, 'from', d.from_local || '@' || d.domain, 'from_name', d.from_name));
  end loop;
  return out;
end $fn$;

create function public.worker_alert_mail_done(p_event bigint, p_recipient uuid, p_ok boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.security_alert_deliveries set status = case when p_ok then 'sent' else 'failed' end, sent_at = case when p_ok then now() end, claimed_at = null
  where event_id = p_event and channel = 'email' and recipient_id = p_recipient and status = 'queued';
  return jsonb_build_object('ok', found);
end $fn$;

-- 0043's reminder, now also by email when the provider is ready
create or replace function public.staff_mfa_reminder(p_staff uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_email text; v_mail text := 'not_connected';
begin
  select email into v_email from app.admins where id = p_staff and active;
  if v_email is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if app.staff_mfa_verified(v_email) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'enrolled'; end if;
  perform app.notify(p_staff, 'security', 'security.mfa_reminder', jsonb_build_object('by', v_me), '/settings');
  if app.mail_ready() then
    perform pgmq.send('jobs', jsonb_build_object('job', 'mfa_reminder', 'staff', p_staff, 'by', v_me));
    v_mail := 'queued';
  end if;
  perform app.log('mfa.reminded', 'staff', p_staff::text, jsonb_build_object('email', v_mail));
  return jsonb_build_object('in_app', true, 'email', v_mail);
end $fn$;

-- what transactional mail needs that a queue job does not carry: the sender
create function public.worker_mail_sender() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select case when d.id is null then null else jsonb_build_object('from', d.from_local || '@' || d.domain, 'from_name', d.from_name, 'reply_to', d.reply_to) end
  from (select (app.mail_sender()).*) d
$fn$;

-- the sender domains mail-run checks against Brevo after connecting
create function public.worker_sender_domains() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'domain', d.domain)), '[]'::jsonb) from app.sender_domains d where d.deleted_at is null
$fn$;

-- the unsubscribe page shows who the mail came from before the person confirms (it changes nothing)
create function public.worker_unsubscribe_peek(p_token text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare r app.campaign_recipients; d app.sender_domains;
begin
  select * into r from app.campaign_recipients where unsub_token_sha256 = app.token_hash(p_token);
  if not found or coalesce(p_token, '') = '' then return jsonb_build_object('found', false); end if;
  select d2.* into d from app.campaigns c join app.sender_domains d2 on d2.id = c.sender_domain_id where c.id = r.campaign_id;
  return jsonb_build_object('found', true, 'from_name', d.from_name, 'done', r.unsubscribed_at is not null);
end $fn$;

-- ===========================================================================
-- 7. the tick: while connected and something waits, knock on mail-run
-- ===========================================================================
create function app.mail_tick() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.mail_settings; v_key text; v_waiting boolean;
begin
  if not app.connected('email') then return jsonb_build_object('called', 0); end if;
  v_waiting := exists (select 1 from pgmq.q_jobs where message ->> 'job' = any (app.mail_job_kinds()) and vt <= clock_timestamp())
    or exists (select 1 from app.ticket_messages where delivery_status = 'queued' and (mail_claimed_at is null or mail_claimed_at < now() - interval '10 minutes'))
    or exists (select 1 from app.admins where invite_state = 'queued' and (invite_claimed_at is null or invite_claimed_at < now() - interval '10 minutes'))
    or exists (select 1 from app.security_alert_deliveries where channel = 'email' and status = 'queued' and (claimed_at is null or claimed_at < now() - interval '10 minutes'));
  if not v_waiting then return jsonb_build_object('called', 0); end if;
  select * into s from app.mail_settings;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'mail_worker_secret';
  perform net.http_post(url := s.functions_url || '/functions/v1/mail-run', body := '{"kind":"run"}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-worker-key', v_key), timeout_milliseconds := 30000);
  return jsonb_build_object('called', 1);
end $fn$;

insert into app.job_defs (key, label_key, schedule, source, fn, quiet) values ('mail_tick', 'jobs.mail_tick', '* * * * *', 'cron', 'app.mail_tick', true)
on conflict (key) do nothing;
select cron.schedule('platform-mail-tick', '* * * * *', 'select app.run_job(''mail_tick'')');

-- ===========================================================================
-- grants: the screens' functions to signed-in staff (each checks its own right); the worker's to the service role only
-- ===========================================================================
revoke all on function app.mail_sender() from public, anon, authenticated;
revoke all on function app.mail_ready() from public, anon, authenticated;
revoke all on function app.mail_job_kinds() from public, anon, authenticated;
revoke all on function app.ticket_recipient(app.tickets) from public, anon, authenticated;
revoke all on function app.staff_invite_queue(uuid, uuid) from public, anon, authenticated;
revoke all on function app.mail_tick() from public, anon, authenticated;

revoke all on function public.email_provider_get() from public, anon;
revoke all on function public.email_provider_intake() from public, anon;
revoke all on function public.email_provider_settings(text) from public, anon;
revoke all on function public.email_provider_disconnect() from public, anon;
revoke all on function public.email_provider_check_ready() from public, anon;
revoke all on function public.staff_invite_send(uuid) from public, anon;
grant execute on function public.email_provider_get(), public.email_provider_intake(), public.email_provider_settings(text),
  public.email_provider_disconnect(), public.email_provider_check_ready(), public.staff_invite_send(uuid) to authenticated;
revoke all on function public.ticket_message(uuid, text, text, text, uuid, uuid[]) from public, anon;
grant execute on function public.ticket_message(uuid, text, text, text, uuid, uuid[]) to authenticated;
revoke all on function public.staff_save(uuid, jsonb) from public, anon;
grant execute on function public.staff_save(uuid, jsonb) to authenticated;
revoke all on function public.staff_list() from public, anon;
grant execute on function public.staff_list() to authenticated;
revoke all on function public.staff_mfa_reminder(uuid) from public, anon;
grant execute on function public.staff_mfa_reminder(uuid) to authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'public.worker_email_provider_result(boolean, jsonb, uuid)', 'public.worker_mail_take(int)', 'public.worker_mail_run_done(jsonb, text)',
    'public.worker_staff_mail(uuid, uuid)', 'public.worker_ticket_mail_claim(int)', 'public.worker_ticket_mail_done(uuid, text, text, boolean)',
    'public.worker_ticket_mail_event(text, text)', 'public.worker_ticket_inbound(text, text, text, text)', 'public.worker_invite_claim(int)',
    'public.worker_invite_done(uuid, text)', 'public.worker_alert_mail_claim(int)', 'public.worker_alert_mail_done(bigint, uuid, boolean)',
    'public.worker_mail_sender()', 'public.worker_sender_domains()', 'public.worker_unsubscribe_peek(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
