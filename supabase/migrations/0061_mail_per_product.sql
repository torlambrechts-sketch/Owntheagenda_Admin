-- 0061_mail_per_product.sql — a customer's mail comes from the customer's application (0060 used one sender for all).
--
-- A ticket belongs to an application (tickets.product); its reply goes from that application's own verified sending
-- address (sender_domains.product), never from another application's. Without one, the reply is stored and says
-- «not emailed», as before. Staff mail (invitations, alerts, MFA reminders) keeps a shared sender: one with no
-- application first, else any verified transactional one.

-- the sender for one application's mail: its own verified address, the transactional stream first
create or replace function app.mail_sender_for(p_product text) returns app.sender_domains
  language sql stable security definer set search_path = ''
as $fn$
  select d.* from app.sender_domains d
  where d.deleted_at is null and d.sends_here and app.domain_verified(d) and d.product is not distinct from p_product
  order by (d.stream = 'transactional') desc, d.created_at limit 1
$fn$;

-- staff mail: a shared address first, else any verified transactional one
create or replace function app.mail_sender() returns app.sender_domains
  language sql stable security definer set search_path = ''
as $fn$
  select d.* from app.sender_domains d
  where d.deleted_at is null and d.sends_here and app.domain_verified(d)
  order by (d.product is null) desc, (d.stream = 'transactional') desc, d.created_at limit 1
$fn$;

create or replace function app.mail_ready_for(p_product text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select app.connected('email') and (app.mail_sender_for(p_product)).id is not null
$fn$;

-- 0060's ticket_message, with the reply's delivery decided by the ticket's own application
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
                     when not t.is_sample and app.mail_ready_for(t.product) and app.ticket_recipient(t) is not null then 'queued'
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

-- 0060's claim: each reply from its ticket's application; the customer reads Norwegian (Orgpuls' customers do; a
-- language per customer is not stored)
create or replace function public.worker_ticket_mail_claim(p_limit int default 20) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m record; t app.tickets; d app.sender_domains; out jsonb := '[]'::jsonb; v_to text;
        v_inbound text := (select s.inbound_domain from app.mail_settings s where s.inbound_ok and s.inbound_domain is not null);
begin
  if not app.connected('email') then return out; end if;
  for m in select x.* from app.ticket_messages x where x.delivery_status = 'queued' and x.kind = 'reply'
             and (x.mail_claimed_at is null or x.mail_claimed_at < now() - interval '10 minutes')
           order by x.created_at limit least(greatest(coalesce(p_limit, 20), 1), 100) for update skip locked loop
    select * into t from app.tickets where id = m.ticket_id;
    v_to := app.ticket_recipient(t);
    d := app.mail_sender_for(t.product);
    if v_to is null or t.deleted_at is not null or d.id is null then
      update app.ticket_messages set delivery_status = 'failed', mail_error = case when d.id is null then 'no_sender' else 'no_recipient' end, mail_claimed_at = null
      where id = m.id;
      continue;
    end if;
    update app.ticket_messages set mail_claimed_at = now(), mail_attempts = mail_attempts + 1 where id = m.id;
    out := out || jsonb_build_array(jsonb_build_object(
      'id', m.id, 'ref', 'T-' || t.number, 'subject', t.subject, 'body', m.body,
      'to', v_to, 'to_name', (select p.name from app.people p where p.id = t.person_id),
      'agent', (select coalesce(a.name, a.email) from app.admins a where a.id = m.author_staff_id),
      'from', d.from_local || '@' || d.domain, 'from_name', d.from_name,
      'reply_to', coalesce(case when v_inbound is not null then 'support@' || v_inbound end, d.reply_to, d.from_local || '@' || d.domain),
      'locale', 'no'));
  end loop;
  return out;
end $fn$;

-- 0060's provider state plus which applications can email their customers
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

revoke all on function app.mail_sender_for(text) from public, anon, authenticated;
revoke all on function app.mail_ready_for(text) from public, anon, authenticated;
