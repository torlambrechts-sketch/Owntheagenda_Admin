-- 0029_inbox_automation_requests.sql — what the Inbox and Automation screens asked of the database
-- (docs/crm-enrichment/requests/inbox.md, automation.md).

-- a record's title when the caller may see it, null otherwise; for lists that name records of any type
create function app.record_title(p_entity text, p_id uuid) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v_title text;
begin
  select * into e from app.entities where key = p_entity;
  if not found or p_id is null then return null; end if;
  execute format('select t.%I::text from app.%I t where t.id = %L and %s', e.title_col, e.tbl, p_id, app.vis_sql(e)) into v_title;
  return v_title;
end $fn$;
revoke all on function app.record_title(text, uuid) from public, anon, authenticated;

-- R-INBOX-03: the AI provider is an integration like the others; «not_connected» until a key is configured
alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai'));
insert into app.integration_connections (provider) values ('ai') on conflict do nothing;

-- R-INBOX-01: send as a verified alias
create or replace function public.email_send(p_draft jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see'); v_mailbox uuid := (p_draft ->> 'mailbox_id')::uuid; v_thread uuid := (p_draft ->> 'thread_id')::uuid;
  v_entity text := p_draft ->> 'entity'; v_record uuid := (p_draft ->> 'record_id')::uuid; v_msg uuid; v_person uuid; e app.entities; v_ok boolean;
  v_to jsonb := app.address_list(p_draft -> 'to'); v_alias text;
begin
  if v_mailbox is null or v_mailbox not in (select app.my_mailboxes()) then
    raise exception 'mailbox_not_connected' using errcode = 'invalid_parameter_value', detail = 'none';
  end if;
  -- sending as an alias: one of the caller's own verified send-as addresses
  if p_draft ->> 'from_alias_id' is not null then
    select a.address into v_alias from app.sender_aliases a
    where a.id = (p_draft ->> 'from_alias_id')::uuid and a.staff_id = v_me and a.kind = 'send_as' and a.verified_at is not null;
    if v_alias is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'from_alias_id'; end if;
  end if;
  if v_thread is not null and not app.thread_visible(v_thread) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if v_entity is not null then
    if v_entity not in ('deal', 'lead', 'person', 'organization') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
    e := app.entity(v_entity);
    execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, v_record, app.vis_sql(e)) into v_ok;
    if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  v_person := (select p.id from app.people p where lower(p.email) = v_to -> 0 ->> 'address' and p.deleted_at is null order by p.created_at limit 1);
  v_msg := app.mail_enqueue(v_me, v_mailbox, v_thread, v_to, app.address_list(p_draft -> 'cc'), app.address_list(p_draft -> 'bcc'),
                            p_draft ->> 'subject', p_draft ->> 'body', app.merge_context(v_entity, v_record, v_person, v_me),
                            (p_draft ->> 'template_id')::uuid, (p_draft ->> 'track')::boolean, (p_draft ->> 'send_at')::timestamptz, 'crm',
                            null, null, null, null, v_entity, v_record, v_person);
  if v_alias is not null then update app.email_messages set from_addr = v_alias where id = v_msg; end if;
  perform app.log('email.queued', 'email_message', v_msg::text, jsonb_build_object('scheduled', (p_draft ->> 'send_at') is not null));
  return jsonb_build_object('message_id', v_msg, 'thread_id', (select thread_id from app.email_messages where id = v_msg),
                            'state', (select state from app.email_messages where id = v_msg));
end $fn$;

-- R-INBOX-02: the call's organisation
create or replace function public.call_log_get(p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  return jsonb_build_object('telephony', (select status from app.integration_connections where provider = 'telephony'),
    'calls', coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (
      select jsonb_build_object('activity_id', a.id, 'at', a.starts_at, 'direction', c.direction, 'outcome', c.outcome, 'duration_s', c.duration_s, 'number', c.number,
                                'person_id', a.person_id, 'person', (select p.name from app.people p where p.id = a.person_id),
                                'organization_id', a.organization_id, 'organization', (select o.name from app.organizations o where o.id = a.organization_id),
                                'deal_id', a.deal_id, 'note', a.note, 'source', c.source) x
      from app.call_logs c join app.activities a on a.id = c.activity_id
      where a.deleted_at is null and app.visible(a.owner_id, a.visibility) order by a.starts_at desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) s), '[]'::jsonb));
end $fn$;

-- R-AUTOMATION-01: an assignment rule's condition, assignee and order in the list
create or replace function app.wf_row(w app.workflows) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', w.id, 'kind', w.kind, 'name', w.name, 'description', w.description, 'state', w.state, 'trigger_type', w.trigger_type, 'trigger_config', w.trigger_config,
    'owner_id', w.owner_id, 'owner', (select a.name from app.admins a where a.id = w.owner_id),
    'activation_scope', w.activation_scope,
    'activation', coalesce((select jsonb_agg(jsonb_build_object('staff_id', a.staff_id, 'team_id', a.team_id,
                                                                'name', coalesce((select s.name from app.admins s where s.id = a.staff_id), (select t.name from app.teams t where t.id = a.team_id))))
                            from app.workflow_activation a where a.workflow_id = w.id), '[]'::jsonb),
    'runs_7d', (select count(*) from app.workflow_runs r where r.workflow_id = w.id and r.started_at > now() - interval '7 days'),
    'failed_7d', (select count(*) from app.workflow_runs r where r.workflow_id = w.id and r.state = 'failed' and r.started_at > now() - interval '7 days'),
    'blockers', to_jsonb(app.wf_blockers(w.id)), 'template_key', w.template_key, 'version', w.version, 'updated_at', w.updated_at,
    'mine', w.owner_id = app.me(),
    -- an assignment rule is its options (condition, assignee) and its place in the order
    'options', case when w.kind = 'assignment' then w.options end, 'priority', case when w.kind = 'assignment' then w.priority end)
$fn$;

-- R-AUTOMATION-02: the record a run is about, by name
create or replace function public.workflow_runs_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_limit int := least(greatest(coalesce((p_filter ->> 'limit')::int, 50), 1), 200);
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(x order by (x ->> 'started_at') desc) from (
    select jsonb_build_object('id', r.id, 'workflow_id', r.workflow_id, 'workflow', w.name, 'state', r.state, 'error', r.error,
      'started_at', r.started_at, 'finished_at', r.finished_at, 'retry_of', r.retry_of,
      'subject_type', r.subject_type, 'subject_id', r.subject_id, 'subject_title', app.record_title(r.subject_type, r.subject_id),
      'retried', exists (select 1 from app.workflow_runs x where x.retry_of = r.id),
      'steps', coalesce((select jsonb_agg(jsonb_build_object('key', s.step_key, 'kind', s.kind, 'state', s.state, 'error', s.error, 'status', s.response_status) order by s.started_at)
                         from app.workflow_run_steps s where s.run_id = r.id), '[]'::jsonb)) x
    from app.workflow_runs r join app.workflows w on w.id = r.workflow_id
    where w.deleted_at is null and ((p_filter ->> 'workflow_id') is null or r.workflow_id = (p_filter ->> 'workflow_id')::uuid)
      and ((p_filter ->> 'state') is null or r.state = p_filter ->> 'state')
    order by r.started_at desc limit v_limit) s), '[]'::jsonb);
end $fn$;

-- R-AUTOMATION-03: who enrolled a record, so only they (or edit-others) are offered skip and exit
create or replace function public.sequence_get(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare w app.workflows; v_graph jsonb;
begin
  perform app.require('deals', 'see');
  select * into w from app.workflows where id = p_id and kind = 'sequence' and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_graph := (select v.graph from app.workflow_versions v where v.workflow_id = w.id and v.version = w.current_version);
  return app.wf_row(w) || jsonb_build_object('options', w.options, 'graph', v_graph,
    'counts', (select jsonb_build_object('in_progress', count(*) filter (where state = 'in_progress'), 'completed', count(*) filter (where state = 'completed'),
                                         'failed', count(*) filter (where state = 'failed'), 'exited', count(*) filter (where state = 'exited'))
               from app.sequence_enrollments where workflow_id = p_id),
    'enrolled', coalesce((select jsonb_agg(x order by (x ->> 'created_at') desc) from (
      select jsonb_build_object('id', se.id, 'entity', se.entity, 'record_id', se.record_id,
        'title', case se.entity when 'deal' then (select d.title from app.deals d where d.id = se.record_id) else (select l.title from app.leads l where l.id = se.record_id) end,
        'step', se.current_ord + 1, 'step_key', se.current_key, 'via', se.enrolled_via, 'state', se.state, 'exit_reason', se.exit_reason, 'error', se.error,
        'created_at', se.created_at, 'enrolled_by', se.enrolled_by, 'mine', se.enrolled_by = app.me()) x
      from app.sequence_enrollments se where se.workflow_id = p_id
        and case se.entity when 'deal' then exists (select 1 from app.deals d where d.id = se.record_id and app.visible(d.owner_id, d.visibility))
                           else exists (select 1 from app.leads l where l.id = se.record_id and app.visible(l.owner_id, l.visibility)) end
      order by se.created_at desc limit 200) s), '[]'::jsonb));
end $fn$;

-- R-AUTOMATION-05: the custom safeguard number beside the mode
create or replace function public.workflow_monitor() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Europe/Oslo') at time zone 'Europe/Oslo';
begin
  perform app.require_staff();
  return jsonb_build_object(
    'today', (select jsonb_build_object('runs', count(*), 'completed', count(*) filter (where state = 'completed'), 'failed', count(*) filter (where state = 'failed'))
              from app.workflow_runs where started_at >= v_today),
    'd7', (select jsonb_build_object('runs', count(*), 'failed', count(*) filter (where state = 'failed'), 'retried', count(*) filter (where retry_of is not null))
           from app.workflow_runs where started_at > now() - interval '7 days'),
    'd14', (select jsonb_build_object('runs', count(*), 'prev7', count(*) filter (where started_at <= now() - interval '7 days'),
                                      'last7', count(*) filter (where started_at > now() - interval '7 days'))
            from app.workflow_runs where started_at > now() - interval '14 days'),
    'loop_protection', app.setting('safeguards'),
    'loop_protection_runs', case when app.setting('safeguards') = 'custom' then (select value_number from app.setting_values where key = 'safeguards' and scope_id = '') end,
    'loop_blocked_7d', (select count(*) from app.workflow_runs where state = 'loop_blocked' and started_at > now() - interval '7 days'),
    'most_failed', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', w.id, 'name', w.name, 'count', count(*)) x
                              from app.workflow_runs r join app.workflows w on w.id = r.workflow_id
                              where r.state = 'failed' and r.started_at > now() - interval '7 days' and w.deleted_at is null
                              group by w.id, w.name order by count(*) desc limit 3) s), '[]'::jsonb),
    'most_active', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', w.id, 'name', w.name, 'count', count(*)) x
                              from app.workflow_runs r join app.workflows w on w.id = r.workflow_id
                              where r.started_at > now() - interval '7 days' and w.deleted_at is null
                              group by w.id, w.name order by count(*) desc limit 3) s), '[]'::jsonb),
    'never_run', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'state', w.state) order by w.name)
                           from app.workflows w where w.deleted_at is null and w.kind in ('workflow', 'lifecycle')
                             and not exists (select 1 from app.workflow_runs r where r.workflow_id = w.id)), '[]'::jsonb),
    'subscribers', coalesce((select jsonb_agg(jsonb_build_object('name', c.subscriber, 'behind', (select count(*) from app.events e where e.id > c.last_event_id),
                                                                 'failures_7d', (select count(*) from app.event_failures f where f.subscriber = c.subscriber and f.at > now() - interval '7 days')))
                             from app.event_cursors c), '[]'::jsonb));
end $fn$;

-- R-AUTOMATION-04: the columns a condition, a date trigger or an update step may use, as data
create function public.entity_columns_get(p_entity text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity);
begin
  perform app.require(e.scope, 'see');
  return coalesce((select jsonb_agg(jsonb_build_object('col', c.col, 'kind', c.kind, 'writable', c.writable, 'required', c.required, 'ref', c.ref) order by c.ord, c.col)
                   from app.entity_columns c where c.entity = e.key), '[]'::jsonb);
end $fn$;
revoke all on function public.entity_columns_get(text) from public, anon;
grant execute on function public.entity_columns_get(text) to authenticated;
