-- 0051_ops_requests.sql — the open database requests of the Mobile, Platform and Security screens.
--
--   R-MOBILE-05    nearby() rows carry lat/lng of the organisation's place (the nearest of its geocoded addresses), never the device's
--   R-MOBILE-06    mobile_focus().today[] carries deal_id and organization_id
--   R-MOBILE-03    push_vapid_public_key(): the Web Push public key for signed-in staff, or null; never the private key
--   R-PLATFORM-02  api_scopes_get(): the scopes an OAuth app may ask for, from app.api_scopes
--   R-PLATFORM-03  problems_open(): open problem tickets the caller may see, for the status banner's link
--   R-PLATFORM-06  webhook_rotate_secret(): a new signing secret, kept in Vault, shown once; webhooks_get says whether one exists
--   R-SECURITY-02  security_dashboard().kpis.mfa.coverage_pct
--   R-SECURITY-05  privacy_requests_get(): open personvern requests with their 30-day due date, for privacy_export/erase's p_request
--   R-SECURITY-06  alerts_get().eligible: who may be named as an alert recipient (alert_recipients_set's own rule)
--   R-SECURITY-07  retention_get(): a rule tied to a setting reports the setting's period as its keep
--
-- Redefined (create or replace keeps their grants): public.nearby (0044 body, 0046 volatility), public.mobile_focus (0044),
-- public.webhooks_get (0049), public.security_dashboard (0043), public.alerts_get (0043), public.retention_get (0043).

-- ===========================================================================
-- R-MOBILE-05: Nearby (0044 body + the place of each row). Volatile: it writes the audit (0046)
-- ===========================================================================
create or replace function public.nearby(p_lat numeric, p_lng numeric, p_radius_km numeric default 10, p_entities text[] default array['organization'], p_filter jsonb default '{}'::jsonb)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.mobile_require(); f jsonb := coalesce(p_filter, '{}'::jsonb); v_out jsonb;
begin
  if not app.coords_ok(p_lat, p_lng) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coordinates'; end if;
  if p_radius_km is null or p_radius_km <= 0 or p_radius_km > 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'radius_km'; end if;
  if p_entities is null or not (p_entities <@ array['organization', 'person']) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entities'; end if;
  with near as (select n.organization_id, n.km from app.orgs_near(p_lat, p_lng, p_radius_km) n),
  rows as (
    select n.km, o.id, o.name, o.city, o.account_id, pl.lat, pl.lng,
      (select jsonb_build_object('id', d.id, 'title', d.title, 'stage', (select s.name from app.stages s where s.id = d.stage_id))
       from app.deals d where d.organization_id = o.id and d.deleted_at is null and d.archived_at is null and d.status = 'open' and app.visible(d.owner_id, d.visibility)
       order by d.last_activity_at desc nulls last, d.updated_at desc limit 1) deal,
      (select h.score from app.health_scores h join app.account_products ap on ap.product = h.product and ap.tenant_id = h.tenant_id
       where ap.account_id = o.account_id order by h.day desc limit 1) health,
      exists (select 1 from app.account_products ap where ap.account_id = o.account_id and ap.status = 'active') customer,
      (select max(a.done_at) from app.activities a join app.activity_types t on t.id = a.type_id
       where a.organization_id = o.id and a.done and a.deleted_at is null and t.key in ('visit', 'meeting')) last_visit_at
    from near n join app.organizations o on o.id = n.organization_id
    -- the organisation's place the distance was measured to (an organisation may have several geocoded addresses)
    left join lateral (select g.lat, g.lng from app.record_geo g where g.entity = 'organization' and g.record_id = o.id
                       order by app.km(p_lat, p_lng, g.lat, g.lng) limit 1) pl on true)
  select coalesce(jsonb_agg(x.j order by x.km), '[]'::jsonb) into v_out from (
    select r.km, jsonb_build_object('entity', 'organization', 'id', r.id, 'title', r.name, 'city', r.city, 'km', r.km, 'lat', r.lat, 'lng', r.lng,
                                    'deal', r.deal, 'health', r.health, 'customer', r.customer, 'last_visit_at', r.last_visit_at) j
    from rows r where 'organization' = any (p_entities)
      and (not coalesce((f ->> 'customers_only')::boolean, false) or r.customer)
      and (f ->> 'no_visit_days' is null or r.last_visit_at is null or r.last_visit_at < now() - make_interval(days => (f ->> 'no_visit_days')::int))
    union all
    select r.km, jsonb_build_object('entity', 'person', 'id', p.id, 'title', p.name, 'subtitle', p.title, 'organization', r.name, 'organization_id', r.id, 'km', r.km,
                                    'lat', r.lat, 'lng', r.lng)
    from rows r join app.people p on p.organization_id = r.id and p.deleted_at is null and app.visible(p.owner_id, p.visibility)
    where 'person' = any (p_entities) and (not p.is_sample or coalesce((select a.sandbox from app.admins a where a.id = v_me), false))
    order by 1 limit 200) x;
  perform app.log('record.listed', 'organization', null, jsonb_build_object('count', jsonb_array_length(v_out), 'view', 'nearby'));
  return v_out;
end $fn$;

-- ===========================================================================
-- R-MOBILE-06: Focus (0044 body); today[] adds deal_id and organization_id, so «Deal on the go» needs no second call
-- ===========================================================================
create or replace function public.mobile_focus(p_lat numeric default null, p_lng numeric default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.mobile_require(); v_tz text := (select time_zone from app.admins where id = v_me);
  v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_today date := (now() at time zone (select time_zone from app.admins where id = app.me()))::date;
  v_geo boolean := app.coords_ok(p_lat, p_lng); v_goal app.goals;
begin
  select * into v_goal from app.goals g where g.kind = 'deals_won' and g.assignee_kind = 'staff' and g.assignee_id = v_me and g.deleted_at is null
    and g.starts_on <= v_today and (g.ends_on is null or g.ends_on >= v_today) and (v_sandbox or not g.is_sample) order by g.created_at desc limit 1;
  return jsonb_build_object(
    'hour', extract(hour from now() at time zone v_tz)::int,
    'name', (select coalesce(a.name, a.email) from app.admins a where a.id = v_me),
    'overdue_activities', (select count(*) from app.activities a where a.deleted_at is null and app.visible(a.owner_id, a.visibility) and (v_sandbox or not a.is_sample)
                             and a.owner_id = v_me and not a.done and a.starts_at < now()),
    'deals_past_close', case when app.module_on('deals') then (select count(*) from app.deals d where d.deleted_at is null and d.archived_at is null
                             and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample) and d.owner_id = v_me and d.status = 'open'
                             and d.expected_close_date < v_today) end,
    'today', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'subject', a.subject, 'starts_at', a.starts_at, 'done', a.done,
                          'type', (select t.key from app.activity_types t where t.id = a.type_id),
                          'organization', (select o.name from app.organizations o where o.id = a.organization_id),
                          'organization_id', (select o.id from app.organizations o where o.id = a.organization_id and o.deleted_at is null and app.visible(o.owner_id, o.visibility)),
                          'deal', (select d.title from app.deals d where d.id = a.deal_id),
                          'deal_id', (select d.id from app.deals d where d.id = a.deal_id and d.deleted_at is null and app.visible(d.owner_id, d.visibility)),
                          'km', case when v_geo and a.organization_id is not null then (select min(app.km(p_lat, p_lng, g.lat, g.lng)) from app.record_geo g
                                                                                         where g.entity = 'organization' and g.record_id = a.organization_id) end)
                        order by a.starts_at)
                      from app.activities a where a.deleted_at is null and app.visible(a.owner_id, a.visibility) and (v_sandbox or not a.is_sample)
                        and a.owner_id = v_me and (a.starts_at at time zone v_tz)::date = v_today), '[]'::jsonb),
    'unread_threads', (select count(*) from app.email_threads t join app.mailboxes m on m.id = t.mailbox_id
                       where t.archived_at is null and t.deleted_at is null and m.deleted_at is null
                         and (m.owner_id = v_me or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = v_me))
                         and app.thread_unread(t.id, v_me)),
    'nearby_10km', case when v_geo then (select count(*) from app.orgs_near(p_lat, p_lng, 10)) end,
    'closing_this_week', case when app.module_on('deals') then (select jsonb_build_object('count', count(*), 'value_nok', coalesce(sum(d.value) filter (where d.currency = 'NOK'), 0),
                             'excluded_currency', count(*) filter (where d.currency <> 'NOK'))
                           from app.deals d where d.deleted_at is null and d.archived_at is null and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample)
                             and d.owner_id = v_me and d.status = 'open'
                             and d.expected_close_date between date_trunc('week', v_today)::date and date_trunc('week', v_today)::date + 6) end,
    'month', case when app.module_on('deals') then jsonb_build_object(
               'won_value_nok', (select coalesce(sum(d.value), 0) from app.deals d where d.deleted_at is null and d.owner_id = v_me and d.status = 'won' and d.currency = 'NOK'
                                   and (v_sandbox or not d.is_sample) and (d.won_at at time zone v_tz)::date >= date_trunc('month', v_today)::date),
               'new_deals', (select count(*) from app.deals d where d.deleted_at is null and d.owner_id = v_me and (v_sandbox or not d.is_sample)
                               and (d.created_at at time zone v_tz)::date >= date_trunc('month', v_today)::date),
               'goal', case when v_goal.id is not null then jsonb_build_object('id', v_goal.id, 'name', v_goal.name, 'progress', app.goal_progress(v_goal),
                                                                               'target_value', v_goal.target_value, 'target_count', v_goal.target_count) end) end,
    'tasks_due_today', case when app.module_on('projects') and app.can('projects', 'see') then
                         (select count(*) from app.project_items i join app.projects p on p.id = i.project_id
                          where i.deleted_at is null and p.deleted_at is null and i.kind = 'task' and not i.done and i.due_on = v_today
                            and (v_sandbox or not p.is_sample)
                            and (i.owner_id = v_me or exists (select 1 from app.project_item_assignees x where x.item_id = i.id and x.staff_id = v_me))) end,
    'chats_waiting', case when app.module_on('leadgen') then (select count(*) from app.chat_conversations c where c.state = 'queued' and c.is_sample = v_sandbox) end,
    'contact_rule', app.setting('contact_rule'));
end $fn$;

-- ===========================================================================
-- R-MOBILE-03: the Web Push public key (VAPID) a browser subscribes with. Only the public half, and only while push is
-- configured (the private key is in Vault, V-P8P-12): without it a subscription could never be delivered to, so null
-- ===========================================================================
create function public.push_vapid_public_key() returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  if not app.push_ready() then return null; end if;
  return (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'vapid_public_key');
end $fn$;
revoke all on function public.push_vapid_public_key() from public, anon;
grant execute on function public.push_vapid_public_key() to authenticated;

-- ===========================================================================
-- R-PLATFORM-02: the API scopes an OAuth app may ask for (app.scopes_ok accepts exactly these)
-- ===========================================================================
create function public.api_scopes_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('scope', s.scope) order by s.ord, s.scope) from app.api_scopes s), '[]'::jsonb);
end $fn$;
revoke all on function public.api_scopes_get() from public, anon;
grant execute on function public.api_scopes_get() to authenticated;

-- ===========================================================================
-- R-PLATFORM-03: open problem tickets for the status banner's link (global:see, as status_notice_get). Only the problems
-- the caller may see under the tickets' own rules (queue and visibility), so a subject never reaches someone it is hidden from
-- ===========================================================================
create function public.problems_open() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'see'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'number', t.number, 'subject', t.subject, 'problem_status', t.problem_status) order by t.number desc)
                   from (select * from app.tickets x
                         where x.type = 'problem' and x.deleted_at is null and x.problem_status <> 'resolved' and x.status not in ('resolved', 'closed')
                           and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility) and (v_sandbox or not x.is_sample)
                         order by x.number desc limit 100) t), '[]'::jsonb);
end $fn$;
revoke all on function public.problems_open() from public, anon;
grant execute on function public.problems_open() to authenticated;

-- ===========================================================================
-- R-PLATFORM-06: rotate a webhook's signing secret. The owner or global:configure (webhook_mine), and the export right of
-- the event's area, as creating it does (0049). The new secret replaces the old in Vault (webhook:<id>), is returned once
-- and never logged. A webhook whose secret was never created (V-PLATFORM-19) gets one
-- ===========================================================================
create function public.webhook_rotate_secret(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.webhooks := app.webhook_mine(p_id); v_secret text := app.random_token('whsec_', 32); v_vault uuid;
begin
  perform app.require(app.webhook_scope(w.event_kind), 'export');
  select w2.* into w from app.webhooks w2 where w2.id = w.id for update;
  select s.id into v_vault from vault.secrets s where s.id = w.vault_secret_id;
  if v_vault is null then select s.id into v_vault from vault.secrets s where s.name = 'webhook:' || w.id; end if;
  if v_vault is null then
    v_vault := vault.create_secret(v_secret, 'webhook:' || w.id, 'A webhook''s signing secret (0044): read only by the database to sign its deliveries.');
  else
    perform vault.update_secret(v_vault, v_secret);
  end if;
  update app.webhooks set vault_secret_id = v_vault, updated_at = now(), version = version + 1 where id = w.id returning * into w;
  perform app.log('webhook.secret_rotated', 'webhook', w.id::text, null);
  return jsonb_build_object('id', w.id, 'version', w.version, 'secret', v_secret);
end $fn$;
revoke all on function public.webhook_rotate_secret(uuid) from public, anon;
grant execute on function public.webhook_rotate_secret(uuid) to authenticated;

-- webhooks_get (0049 body) + has_secret: whether Vault holds the webhook's signing secret (a seeded one has none)
create or replace function public.webhooks_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_all boolean := app.can('global', 'configure'); f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  return jsonb_build_object(
    'webhooks', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'owner_id', w.owner_id, 'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = w.owner_id),
                            'event_kind', w.event_kind, 'url', w.url, 'state', w.state, 'banned_until', w.banned_until, 'retrying',
                            exists (select 1 from app.webhook_deliveries d where d.webhook_id = w.id and d.state = 'queued' and d.attempt > 1),
                            'last_success_at', w.last_success_at, 'failing_since', w.failing_since, 'created_at', w.created_at, 'version', w.version,
                            'mine', w.owner_id = v_me, 'has_secret', exists (select 1 from vault.secrets s where s.id = w.vault_secret_id),
                            'can_export', app.can(app.webhook_scope(w.event_kind), 'export')) order by w.created_at desc)
                          from app.webhooks w where w.state <> 'deleted' and (w.owner_id = v_me or v_all)
                            and (f ->> 'owner_id' is null or w.owner_id::text = f ->> 'owner_id')
                            and w.is_sample = coalesce((select sandbox from app.admins where id = v_me), false)), '[]'::jsonb),
    'deliveries', coalesce((select jsonb_agg(x.j order by x.at desc) from (
                     select d.scheduled_at at, jsonb_build_object('id', d.id, 'webhook_id', d.webhook_id, 'at', coalesce(d.sent_at, d.scheduled_at),
                              'event', w.event_kind, 'host', substring(w.url from '^https://(?:[^@/]*@)?([^:/?#]+)'), 'status', d.response_status,
                              'state', d.state, 'attempt', d.attempt, 'attempts', 4, 'error', d.error_code) j
                     from app.webhook_deliveries d join app.webhooks w on w.id = d.webhook_id
                     where (w.owner_id = v_me or v_all) and d.state <> 'queued' or (w.owner_id = v_me or v_all) and d.attempt > 1
                     order by d.scheduled_at desc limit 20) x), '[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(c.kind order by c.family, c.kind) from app.event_catalog c
                       where c.webhookable and app.can(app.webhook_scope(c.kind), 'export')), '[]'::jsonb),
    'limit', app.count_limit(),
    'count_limits', app.setting('count_limits'),
    'policy', app.webhook_policy(),
    'can_manage_all', v_all);
end $fn$;

-- ===========================================================================
-- R-SECURITY-02: the dashboard (0043 body); kpis.mfa adds coverage_pct, rounded, null with no active staff
-- ===========================================================================
create or replace function public.security_dashboard() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_issues jsonb := app.security_issues(); v_enrolled int; v_active int;
begin
  select count(*) filter (where app.staff_mfa_verified(a.email)), count(*) into v_enrolled, v_active from app.admins a where a.active and not a.is_sample;
  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'signed_in_now', (select count(*) from app.staff_sessions s where s.ended_at is null
                        and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')),
      'new_devices_7d', jsonb_build_object(
        'count', (select count(*) from app.login_log l where l.outcome = 'success' and l.new_device and l.at > now() - interval '7 days'),
        'staff', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by a.name)
                           from app.admins a where a.id in (select l.staff_id from app.login_log l where l.outcome = 'success' and l.new_device
                                                            and l.at > now() - interval '7 days')), '[]'::jsonb)),
      'new_locations_7d', jsonb_build_object(
        'count', (select count(*) from app.login_log l where l.outcome = 'success' and l.new_location and l.at > now() - interval '7 days'),
        'places', coalesce((select jsonb_agg(distinct jsonb_build_object('city', l.city, 'country', l.country))
                            from app.login_log l where l.outcome = 'success' and l.new_location and l.at > now() - interval '7 days'), '[]'::jsonb)),
      'security_events_7d', jsonb_build_object(
        'count', (select count(*) from app.security_events e where e.at > now() - interval '7 days'),
        'critical', (select count(*) from app.security_events e where e.at > now() - interval '7 days' and e.severity = 'critical')),
      'forced_logouts_7d', (select count(*) from app.staff_sessions s where s.end_reason = 'forced' and s.ended_at > now() - interval '7 days'),
      'mfa', jsonb_build_object('enrolled', v_enrolled, 'active', v_active,
                                'coverage_pct', case when v_active > 0 then round(100.0 * v_enrolled / v_active)::int end)),
    'settings', jsonb_build_object('session_idle', app.setting('session_idle'), 'ip_allowlist', app.setting('ip_allowlist'),
                                   'signin_hours', app.setting('signin_hours'), 'ip_rules', cardinality(app.ip_ranges())),
    'live', coalesce((select jsonb_agg(jsonb_build_object('session_id', s.session_id, 'staff_id', s.staff_id, 'name', coalesce(a.name, a.email),
                                                          'city', s.city, 'country', s.country, 'device', s.device_label, 'method', s.method,
                                                          'since', s.created_at, 'last_seen_at', s.last_seen_at,
                                                          'current', s.session_id = app.current_session()) order by s.created_at)
                      from app.staff_sessions s join app.admins a on a.id = s.staff_id
                      where s.ended_at is null and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')), '[]'::jsonb),
    'issues', v_issues,
    'issues_open', jsonb_array_length(v_issues),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'kind', e.kind, 'severity', e.severity,
                                                            'subject_id', e.subject_staff_id, 'subject', (select coalesce(a.name, a.email) from app.admins a where a.id = e.subject_staff_id),
                                                            'actor_id', e.actor_id, 'actor', (select coalesce(a.name, a.email) from app.admins a where a.id = e.actor_id),
                                                            'detail', e.detail, 'alert_state', e.alert_state) order by e.id desc)
                        from app.security_events e where e.at > now() - interval '7 days'), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- R-SECURITY-05: open personvern requests (received, in progress) with their 30-day due date, so an export or an erasure
-- can name the request it answers (privacy_export/privacy_erase p_request; the request is closed when the job is done).
-- global:security, as those two. No requester text: the kind, the ticket's number, the organisation, the dates
-- ===========================================================================
create function public.privacy_requests_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('global', 'security'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'status', p.status, 'received_at', p.received_at, 'due_at', p.due_at,
                                                       'overdue', p.due_at < now(), 'ticket_number', t.number, 'organization', o.name) order by p.due_at, p.id)
                   from app.privacy_requests p left join app.tickets t on t.id = p.ticket_id left join app.organizations o on o.id = p.organization_id
                   where p.status in ('received', 'in_progress') and (v_sandbox or not p.is_sample)), '[]'::jsonb);
end $fn$;
revoke all on function public.privacy_requests_get() from public, anon;
grant execute on function public.privacy_requests_get() to authenticated;

-- ===========================================================================
-- R-SECURITY-06: alerts_get (0043 body) + eligible: the active staff alert_recipients_set accepts (global:security holders)
-- ===========================================================================
create or replace function public.alerts_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return jsonb_build_object(
    'settings', (select jsonb_object_agg(k, app.setting(k)) from unnest(array['alert_new_device', 'alert_user_invited', 'alert_failed_logins',
                 'alert_password_reset', 'alert_large_export', 'login_alerts', 'alert_digest_time', 'security_alert_recipients']) k),
    'failed_logins_count', app.setting_number('alert_failed_logins_count', 3),
    'large_export_rows', app.setting_number('alert_large_export_rows', 1000),
    'recipients', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email), 'email', a.email) order by a.name)
                            from app.admins a where a.id in (select * from app.security_recipients())), '[]'::jsonb),
    'listed', coalesce((select jsonb_agg(r.staff_id) from app.security_alert_recipients r), '[]'::jsonb),
    'eligible', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.name, a.email)) order by coalesce(a.name, a.email))
                          from app.admins a where a.active and not a.is_sample and app.staff_has_security(a.id)), '[]'::jsonb),
    'email', case when app.connected('email') then 'connected' else 'not_connected' end,
    'slack', case when app.connected('slack') then 'connected' else 'not_connected' end,
    'slack_channel', (select c.config ->> 'channel' from app.integration_connections c where c.provider = 'slack' and c.status = 'connected'));
end $fn$;

-- ===========================================================================
-- R-SECURITY-07: retention_get (0043 body). A rule tied to a setting keeps what the setting says: meeting recordings follow
-- rec_retention (app.mtg_retention_months: 12 months, the custom number, or null = kept until deleted). Written in months
-- («12 mons») so the register's own unit survives; the fixed interval is kept as `default_keep`
-- ===========================================================================
create or replace function public.retention_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'security');
  return coalesce((select jsonb_agg(jsonb_build_object('key', r.key,
                     'keep', case when r.setting_key = 'rec_retention' then (select m || ' mons' from app.mtg_retention_months() m) else r.keep::text end,
                     'default_keep', r.keep::text, 'basis', r.basis, 'job', r.job_key,
                     'setting', case when r.setting_key is not null then jsonb_build_object('key', r.setting_key, 'value', app.setting(r.setting_key)) end,
                     'in_force', r.basis = 'platform' and exists (select 1 from cron.job c where c.jobname = r.job_key and c.active),
                     'last_run_at', coalesce(r.last_run_at, (select max(d.end_time) from cron.job_run_details d join cron.job c on c.jobid = d.jobid
                                                             where c.jobname = r.job_key and d.status = 'succeeded')),
                     'last_purged', r.last_purged) order by r.ord)
                   from app.retention_rules r), '[]'::jsonb);
end $fn$;
