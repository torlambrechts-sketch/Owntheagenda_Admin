-- 0039_phase6_engine_wiring.sql — 0037 (campaigns) and 0038 (projects) were written in parallel. 0037 redefined the
-- workflow engine for campaign_action; 0038 built the project step as app.wf_project_validate/_blocker/_action but
-- left the engine alone so neither migration would erase the other's step (V-P6P-01). This wires the project step
-- into 0037's bodies: validation, the blocker (instead of not_available:projects) and the executor.

CREATE OR REPLACE FUNCTION app.wf_validate(p_kind text, p_graph jsonb, p_entity text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s record; v_keys text[] := '{}'; c jsonb; k text; v_limit numeric := app.count_limit(); pc jsonb; x jsonb;
begin
  if p_kind = 'assignment' then return; end if;
  if jsonb_typeof(p_graph -> 'steps') <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.steps'; end if;
  for s in with recursive w(step) as (
             select e1.value from jsonb_array_elements(p_graph -> 'steps') e1
             union all
             select e2.value from w, jsonb_array_elements(coalesce(w.step -> 'then', '[]'::jsonb) || coalesce(w.step -> 'else', '[]'::jsonb)) e2)
           select step from w loop
    k := s.step ->> 'key'; c := coalesce(s.step -> 'config', '{}'::jsonb);
    if k is null or k !~ '^[a-z0-9_]{1,24}$' or k = any (v_keys) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.key'; end if;
    v_keys := v_keys || k;
    if not ((s.step ->> 'kind') = any (app.wf_kinds(p_kind))) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.kind'; end if;
    case s.step ->> 'kind'
      when 'condition', 'if_else' then
        if jsonb_typeof(c -> 'groups') <> 'array' or jsonb_array_length(c -> 'groups') = 0 then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.groups';
        end if;
      when 'delay' then
        if coalesce((c ->> 'amount')::numeric, -1) < 0 or coalesce(c ->> 'unit', 'days') not in ('minutes', 'hours', 'days') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.amount';
        end if;
      when 'wait_for' then
        if c ->> 'event' not in ('email.replied', 'email.opened', 'email.clicked', 'deal.stage_changed', 'deal.won', 'deal.lost', 'activity.completed')
           or coalesce((c ->> 'timeout_days')::numeric, 7) not between 1 and 365 or coalesce(c ->> 'then', 'continue') not in ('continue', 'stop') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.event';
        end if;
      when 'update_record' then
        if jsonb_typeof(c -> 'values') <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.values'; end if;
        for x in select to_jsonb(kk) from jsonb_object_keys(c -> 'values') kk loop
          if x #>> '{}' not in ('owner_id', 'labels', 'custom') and not exists (select 1 from app.entity_columns ec where ec.entity = p_entity and ec.col = x #>> '{}' and ec.writable) then
            raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.values.' || (x #>> '{}');
          end if;
        end loop;
      when 'create_record' then
        if c ->> 'entity' not in ('deal', 'lead', 'person', 'organization') or jsonb_typeof(c -> 'values') <> 'object' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.entity';
        end if;
      when 'create_activity', 'activity' then
        if not exists (select 1 from app.activity_types t where t.key = coalesce(c ->> 'type', 'task') and t.active) or coalesce(btrim(c ->> 'subject'), '') = '' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.subject';
        end if;
      when 'add_note' then
        if coalesce(btrim(c ->> 'body'), '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.body'; end if;
      when 'notify' then
        if coalesce(btrim(c ->> 'message'), '') = '' or char_length(c ->> 'message') > 500 then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.message';
        end if;
      when 'send_email', 'email_auto', 'email_manual' then
        if not exists (select 1 from app.email_templates t where t.id::text = c ->> 'template_id' and t.kind = 'sales' and t.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.template_id';
        end if;
      when 'enroll_sequence' then
        if not exists (select 1 from app.workflows w where w.id::text = c ->> 'sequence_id' and w.kind = 'sequence' and w.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.sequence_id';
        end if;
      when 'create_ticket' then
        if not exists (select 1 from app.ticket_categories t where t.key = c ->> 'category_key' and t.active) or coalesce(btrim(c ->> 'subject'), '') = '' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.category_key';
        end if;
      when 'webhook' then
        if not app.url_public(c ->> 'url') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.url'; end if;
        if coalesce(c ->> 'method', 'POST') not in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.method';
        end if;
        if char_length(coalesce(c ->> 'body', '')) > 20000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.body'; end if;
      when 'campaign_action' then
        -- CMP-07, AUT-07: an automated campaign; the workflow's author needs Campaigns › workflows
        perform app.require('campaigns', 'workflows');
        if not exists (select 1 from app.campaigns x where x.id::text = c ->> 'campaign_id' and x.type = 'automated' and x.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.campaign_id';
        end if;
      when 'project_action' then perform app.wf_project_validate(k, c);
      else null;
    end case;
  end loop;
  if cardinality(v_keys) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.steps'; end if;
  if v_limit is not null then
    pc := app.wf_path_counts(p_graph -> 'steps');
    if (pc ->> 'actions')::int > v_limit or (pc ->> 'delays')::int > v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.limit';
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION app.wf_blockers(p_wf uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct b) filter (where b is not null), '{}') from (
    select case
      when n.v ->> 'kind' = 'slack' and not exists (select 1 from app.integration_connections c where c.provider = 'slack' and c.status = 'connected') then 'not_connected:slack'
      when n.v ->> 'kind' = 'teams' and not exists (select 1 from app.integration_connections c where c.provider = 'teams' and c.status = 'connected') then 'not_connected:teams'
      when n.v ->> 'kind' = 'accounting_invoice' and not exists (select 1 from app.integration_connections c where c.provider = 'accounting' and c.status = 'connected') then 'not_connected:accounting'
      -- campaign_action (0037): the provider, an automated campaign that is switched on, a verified sender domain
      when n.v ->> 'kind' = 'campaign_action' and not app.connected('email') then 'not_connected:email'
      when n.v ->> 'kind' = 'campaign_action'
           and not exists (select 1 from app.campaigns c where c.id::text = n.v -> 'config' ->> 'campaign_id' and c.type = 'automated' and c.status in ('active', 'paused')
                           and c.deleted_at is null) then 'campaign_inactive'
      when n.v ->> 'kind' = 'campaign_action'
           and not exists (select 1 from app.campaigns c join app.sender_domains d on d.id = c.sender_domain_id
                           where c.id::text = n.v -> 'config' ->> 'campaign_id' and app.domain_verified(d)) then 'sender_domain_unverified'
      when n.v ->> 'kind' = 'project_action' then app.wf_project_blocker(n.v -> 'config')
      -- a sequence that is still a draft refuses every enrollment (seq_enroll: sequence_inactive)
      when n.v ->> 'kind' = 'enroll_sequence'
           and not exists (select 1 from app.workflows s where s.id::text = n.v -> 'config' ->> 'sequence_id' and s.kind = 'sequence' and s.state = 'active' and s.deleted_at is null) then 'sequence_inactive'
      -- sending as the workflow's owner needs their mailbox; sending as the record's owner is checked per run,
      -- but at least one mailbox must be connected
      when n.v ->> 'kind' in ('send_email', 'email_auto', 'email_manual')
           and not exists (select 1 from app.mailboxes m where m.deleted_at is null and m.status in ('syncing', 'synced')
                           and (coalesce(n.v -> 'config' ->> 'from', '@record_owner') = '@record_owner'
                                or m.owner_id = w.owner_id or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = w.owner_id and mm.can_reply))) then 'mailbox_not_connected'
      end b
    from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
    cross join lateral jsonb_each(v.flat) n(k, v)
    where w.id = p_wf and n.k <> '_start') s
$function$;

CREATE OR REPLACE FUNCTION app.wf_step(p_run app.workflow_runs, p_wf app.workflows, p_key text, p_node jsonb, p_step uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c jsonb := coalesce(p_node -> 'config', '{}'::jsonb); k text := p_node ->> 'kind'; e app.entities; v jsonb := '{}'::jsonb; kk text; r jsonb; v_id uuid;
  v_owner uuid; v_mailbox uuid; v_person uuid; v_to text; v_msg uuid; v_tpl app.email_templates; v_seq uuid; v_facts jsonb; v_assignee uuid; v_title text;
  v_ref text; v_deal uuid;
begin
  if p_run.subject_type is not null then select * into e from app.entities where key = p_run.subject_type; end if;
  case k
    when 'condition' then
      if app.wf_match(p_run.subject_type, p_run.subject_id, c -> 'groups') then
        update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step;
        return coalesce(p_node ->> 'next', '');
      end if;
      update app.workflow_run_steps set state = 'not_met', finished_at = now() where id = p_step;
      return '';
    when 'if_else' then
      update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step;
      return coalesce(case when app.wf_match(p_run.subject_type, p_run.subject_id, c -> 'groups') then p_node ->> 'then' else p_node ->> 'else' end, '');
    when 'delay' then
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''),
        resume_at = app.wf_delay_until(now(), coalesce((c ->> 'amount')::numeric, 0), c ->> 'unit', (c ->> 'skip_weekends')::boolean)
      where id = p_run.id;
      update app.workflow_run_steps set state = 'succeeded', finished_at = now(), output = jsonb_build_object('until', (select resume_at from app.workflow_runs where id = p_run.id)) where id = p_step;
      return null;
    when 'wait_for' then
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = c ->> 'event',
        wait_deadline = now() + make_interval(days => coalesce((c ->> 'timeout_days')::int, 7)), wait_then = coalesce(c ->> 'then', 'continue')
      where id = p_run.id;
      update app.workflow_run_steps set state = 'waiting' where id = p_step;
      return null;
    when 'update_record' then
      for kk in select jsonb_object_keys(c -> 'values') loop
        v := v || jsonb_build_object(kk, app.wf_value(c -> 'values' -> kk, p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      end loop;
      perform public.rec_save(p_run.subject_type, p_run.subject_id, v, null, null, 'workflow');
    when 'delete_record' then
      perform public.rec_delete(p_run.subject_type, array[p_run.subject_id]);
    when 'create_record' then
      for kk in select jsonb_object_keys(c -> 'values') loop
        v := v || jsonb_build_object(kk, app.wf_value(c -> 'values' -> kk, p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      end loop;
      -- link to the subject when the new record has a column that points at the subject's type
      select col into kk from app.entity_columns where entity = c ->> 'entity' and ref = p_run.subject_type and writable order by ord limit 1;
      if kk is not null and not (v ? kk) then v := v || jsonb_build_object(kk, p_run.subject_id); end if;
      r := public.rec_save(c ->> 'entity', null, v, null, null, 'workflow');
      update app.workflow_run_steps set output = jsonb_build_object('entity', c ->> 'entity', 'id', r ->> 'id') where id = p_step;
    when 'create_activity', 'activity' then
      v := jsonb_build_object('type_id', (select t.id from app.activity_types t where t.key = coalesce(c ->> 'type', 'task')),
                              'subject', left(app.wf_render(c ->> 'subject', p_run.subject_type, p_run.subject_id), 200),
                              'starts_at', now() + make_interval(days => coalesce((c ->> 'due_in_days')::int, 0)),
                              'priority', coalesce(c ->> 'priority', 'medium'),
                              'owner_id', app.wf_value(to_jsonb(coalesce(c ->> 'owner', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      if p_run.subject_type in ('deal', 'person', 'organization') then v := v || jsonb_build_object(p_run.subject_type || '_id', p_run.subject_id); end if;
      if p_run.subject_type = 'lead' then v := v || jsonb_build_object('lead_id', p_run.subject_id); end if;
      r := public.rec_save('activity', null, v, null, null, 'workflow');
      update app.activities set created_by_workflow = p_wf.id where id = (r ->> 'id')::uuid;
      update app.workflow_run_steps set output = jsonb_build_object('activity', r ->> 'id') where id = p_step;
    when 'add_note' then
      perform public.note_save(p_run.subject_type, p_run.subject_id, null, left(app.wf_render(c ->> 'body', p_run.subject_type, p_run.subject_id), 10000));
    when 'notify' then
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'to', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id)) #>> '{}';
      if e.key is not null then
        execute format('select t.%I::text from app.%I t where t.id = %L', e.title_col, e.tbl, p_run.subject_id) into v_title;
      end if;
      perform app.notify(v_owner, 'system', 'workflow.notice',
                         jsonb_build_object('workflow', p_wf.name, 'message', left(app.wf_render(c ->> 'message', p_run.subject_type, p_run.subject_id), 500), 'record', v_title),
                         app.entity_route(p_run.subject_type), p_run.subject_type, p_run.subject_id);
    when 'create_ticket' then
      v := jsonb_build_object('category_key', c ->> 'category_key', 'subject', left(app.wf_render(c ->> 'subject', p_run.subject_type, p_run.subject_id), 200));
      if p_run.subject_type = 'organization' then v := v || jsonb_build_object('organization_id', p_run.subject_id); end if;
      if p_run.subject_type = 'deal' then v := v || jsonb_build_object('organization_id', (select d.organization_id from app.deals d where d.id = p_run.subject_id)); end if;
      r := public.ticket_create(v);
      update app.workflow_run_steps set output = jsonb_build_object('ticket', r ->> 'id') where id = p_step;
    when 'assign_owner' then
      v_facts := app.assign_facts(p_run.subject_type, p_run.subject_id);
      v_assignee := app.assign_pick(c -> 'assignee', v_facts, true);
      if v_assignee is null then raise exception 'no_assignee'; end if;
      perform public.rec_save(p_run.subject_type, p_run.subject_id, jsonb_build_object('owner_id', v_assignee), null, null, 'workflow');
      perform app.notify(v_assignee, 'system', 'assignment.assigned', jsonb_build_object('workflow', p_wf.name), app.entity_route(p_run.subject_type), p_run.subject_type, p_run.subject_id);
    when 'enroll_sequence' then
      perform app.seq_enroll((c ->> 'sequence_id')::uuid, p_run.subject_type, p_run.subject_id, 'workflow', p_wf.owner_id);
    when 'send_email', 'email_auto', 'email_manual' then
      select * into v_tpl from app.email_templates where id = (c ->> 'template_id')::uuid and deleted_at is null;
      if not found then raise exception 'template_missing'; end if;
      -- the recipient: the subject person, or the deal's or lead's person
      v_person := case p_run.subject_type when 'person' then p_run.subject_id
                    when 'deal' then (select d.person_id from app.deals d where d.id = p_run.subject_id)
                    when 'lead' then (select l.person_id from app.leads l where l.id = p_run.subject_id) end;
      v_to := (select lower(p.email) from app.people p where p.id = v_person and p.deleted_at is null);
      if v_to is null then raise exception 'no_recipient'; end if;
      if app.setting('sales_consent') = 'block'
         and ((select p.marketing_status from app.people p where p.id = v_person) in ('unsubscribed', 'bounced')
              or not exists (select 1 from app.consent_events ce where ce.person_id = v_person and ce.basis is not null)) then
        raise exception 'consent';
      end if;
      -- the sender: the record's owner's mailbox when the step says so, else the workflow owner's
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'from', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id)) #>> '{}';
      v_mailbox := (select m.id from app.mailboxes m where m.deleted_at is null and m.status in ('syncing', 'synced')
                    and (m.owner_id = v_owner or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = v_owner and mm.can_reply))
                    order by m.kind = 'personal' desc, m.created_at limit 1);
      if v_mailbox is null then raise exception 'mailbox_not_connected'; end if;
      v_msg := app.mail_enqueue(v_owner, v_mailbox, null, jsonb_build_array(jsonb_build_object('address', v_to)), null, null, v_tpl.subject, v_tpl.body,
                                app.merge_context(p_run.subject_type, p_run.subject_id, v_person, v_owner), v_tpl.id, null, null,
                                case when k = 'send_email' then 'workflow' else 'sequence' end,
                                case when k = 'email_manual' then 'awaiting_review' end, null, p_run.enrollment_id, p_step,
                                p_run.subject_type, p_run.subject_id, v_person);
      update app.workflow_run_steps set output = jsonb_build_object('message', v_msg) where id = p_step;
      if k = 'email_manual' then
        -- a manual email waits for its sender to review and send it
        update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = 'email.sent', wait_ref = v_msg::text, wait_deadline = null where id = p_run.id;
        update app.workflow_run_steps set state = 'waiting' where id = p_step;
        return null;
      end if;
    when 'webhook', 'slack', 'teams', 'accounting_invoice' then
      if k <> 'webhook' and not exists (select 1 from app.integration_connections ic where ic.provider = case k when 'accounting_invoice' then 'accounting' else k end and ic.status = 'connected') then
        raise exception 'not_connected';
      end if;
      if k = 'webhook' and not app.url_public(c ->> 'url') then raise exception 'blocked_address'; end if;
      update app.workflow_run_steps set state = 'queued',
        request = case when k = 'webhook' then jsonb_build_object('method', coalesce(c ->> 'method', 'POST'), 'url', c ->> 'url',
                                                                 'body', app.wf_render(c ->> 'body', p_run.subject_type, p_run.subject_id, true))
                       else jsonb_build_object('message', app.wf_render(c ->> 'message', p_run.subject_type, p_run.subject_id), 'channel', c ->> 'channel') end
      where id = p_step;
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = 'step.done', wait_ref = p_step::text where id = p_run.id;
      perform pgmq.send('jobs', jsonb_build_object('job', 'workflow_step', 'step_id', p_step, 'kind', k));
      return null;
    when 'campaign_action' then
      -- CMP-07: the subject's person gets the automated campaign, or the step is skipped with the reason (never to
      -- people who are not subscribed or are suppressed, D-27); the run goes on either way
      if not app.can('campaigns', 'workflows') then raise exception 'forbidden'; end if;
      v_person := case p_run.subject_type when 'person' then p_run.subject_id
                    when 'deal' then (select d.person_id from app.deals d where d.id = p_run.subject_id)
                    when 'lead' then (select l.person_id from app.leads l where l.id = p_run.subject_id) end;
      v_ref := app.campaign_enqueue((c ->> 'campaign_id')::uuid, v_person, p_step::text);
      if v_ref is not null then
        update app.workflow_run_steps set state = 'skipped', finished_at = now(), output = jsonb_build_object('skip_reason', v_ref) where id = p_step;
      else
        update app.workflow_run_steps set output = jsonb_build_object('campaign', c ->> 'campaign_id', 'queued', true) where id = p_step;
      end if;
    when 'project_action' then
      update app.workflow_run_steps set output = app.wf_project_action(p_run, p_wf, c) where id = p_step;
    else
      raise exception 'unknown_step';
  end case;
  update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step and state = 'running';
  if p_run.enrollment_id is not null then
    update app.sequence_enrollments set current_ord = current_ord + 1, current_key = p_node ->> 'next' where id = p_run.enrollment_id;
  end if;
  return coalesce(p_node ->> 'next', '');
end $function$;
