-- 0060_simple_sequences.sql — Sentral Simple › Growth › Email and automation (GrowthMarketing.dc.html, view «email»).
--
-- An email campaign of the simple interface is a workflow of the one engine (0021, D-06): the editor's own model is kept in
-- workflows.options.simple and compiled here, in one transaction, into the engine's graph:
--   email → campaign_action on an automated campaign (a draft per step, created and named here; CMP-07)
--   wait  → delay (days)
--   condition → condition (a run whose condition does not hold ends)
--   task for sales → create_activity (a task for the record's owner)
-- «Stop when» becomes a condition before every email and task that follows a wait. «Starts when» is an event trigger:
-- a deal entering a stage, or a form submission that made a lead (the engine emails a person: a deal's or lead's contact).
-- Account triggers (trial started, trial ending, cancelled) have no person to email, the engine has no list-entry trigger,
-- and a one-off send is a broadcast campaign: those are refused as not available. Nothing is sent before an email provider
-- is connected (campaign_action is blocked with not_connected:email, so activation refuses it).
--
-- 1. wf_match learns three tests: {f:'segment', v:id} (the record's person is in the segment), {f:'org_paying'} (the
--    record's organisation has a paying subscription) and {f:'org_milestone', v:key} (one of its tenants reached the
--    activation milestone). Each also takes op 'neq'.
-- 2. simple_sequence_save / simple_sequences_get.

-- ---------------------------------------------------------------------------
-- 1. three tests for conditions and triggers
-- the person a record is about: the person itself, a deal's or a lead's contact
create function app.wf_person(p_entity text, p_id uuid) returns uuid
  language sql stable security definer set search_path = ''
as $fn$
  select case p_entity when 'person' then p_id
           when 'deal' then (select d.person_id from app.deals d where d.id = p_id)
           when 'lead' then (select l.person_id from app.leads l where l.id = p_id) end
$fn$;

-- is the record's person in the segment? The segment's filters decide, not who may see the person: a list says who someone
-- is, and matching happens in the dispatcher, outside anyone's session (the audience of an automated campaign is its
-- workflow's subjects, V-P6C-20 applies to broadcasts)
create function app.in_segment(p_entity text, p_id uuid, p_segment uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_person uuid := app.wf_person(p_entity, p_id); v_q jsonb; e app.entities; v_hit boolean;
begin
  select s.query into v_q from app.saved_views s where s.id = p_segment and s.kind = 'segment';
  if v_person is null or v_q is null then return false; end if;
  select * into e from app.entities where key = 'person';
  execute format('select exists (select 1 from app.people t where t.id = %L and t.deleted_at is null %s)', v_person, app.filter_sql(e, v_q -> 'filters')) into v_hit;
  return coalesce(v_hit, false);
end $fn$;

-- paying: a subscription of the organisation's account with recurring revenue (app.sub_mrr)
create function app.org_paying(p_org uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.organizations o join app.account_products ap on ap.account_id = o.account_id
                 join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                 where o.id = p_org and app.sub_mrr(s) > 0)
$fn$;

create function app.org_milestone(p_org uuid, p_key text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.organizations o join app.account_products ap on ap.account_id = o.account_id
                 join app.activation_milestones m on m.product = ap.product and m.tenant_id = ap.tenant_id
                 where o.id = p_org and m.key = p_key)
$fn$;

do $$
declare src text; out text;
begin
  -- wf_match gains the three tests next to org_payment (the way 0025 added org_health), and their negation
  src := pg_get_functiondef('app.wf_match(text, uuid, jsonb)'::regprocedure);
  out := replace(src, $r$      elsif fl ->> 'f' = 'org_payment' then$r$,
                      $r$      elsif fl ->> 'f' = 'segment' then
        v_hit := app.in_segment(p_entity, p_id, nullif(fl ->> 'v', '')::uuid);
      elsif fl ->> 'f' = 'org_paying' then
        v_hit := v_org is not null and app.org_paying(v_org);
      elsif fl ->> 'f' = 'org_milestone' then
        v_hit := v_org is not null and app.org_milestone(v_org, fl ->> 'v');
      elsif fl ->> 'f' = 'org_payment' then$r$);
  out := replace(out, $r$'participant_label', 'org_payment') then v_hit := not v_hit;$r$,
                      $r$'participant_label', 'org_payment', 'segment', 'org_paying', 'org_milestone') then v_hit := not v_hit;$r$);
  if position('app.org_milestone(v_org' in out) = 0 or position($r$'org_paying', 'org_milestone') then v_hit := not v_hit;$r$ in out) = 0 then
    raise exception 'wf_match has changed shape: the simple sequence tests could not be added';
  end if;
  execute out;
end $$;

-- ---------------------------------------------------------------------------
-- 2. the editor's save. values: {name, trigger, stage_id?, list?, exit, steps: [{kind, text?, days?, cond?, campaign_id?}]}
--   trigger: deal_stage (with stage_id) | form_submitted; trial_started | trial_ending | list_added | account_cancels | send_now
--            are not available (invalid, detail trigger.not_available)
--   list:    a segment the caller may use, or null (everyone the trigger starts)
--   exit:    reply_unsub (a reply to the record's linked mail since the run began; unsubscribed people are never mailed,
--            D-27) | paying | never
--   steps:   email {text = subject} | wait {days 1–365} | cond {cond: not_paying | employees_missing | on_list} | task {text}
-- Rights are the engine's and the campaigns': workflow_save (the trigger's scope › Manage workflows; another person's
-- needs Global › Configure), campaign_save (Campaigns › Add) and campaign_action (Campaigns › Manage workflows).
-- Returns {id, version, simple}: the model as stored, with each email's campaign_id.
create function public.simple_sequence_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff();
  v jsonb := coalesce(p_values, '{}'::jsonb);
  w app.workflows;
  v_old jsonb := '[]'::jsonb;
  v_name text; v_trigger text; v_stage uuid; v_list uuid; v_exit text; v_tc jsonb; v_groups jsonb := '[]'::jsonb; v_exitf jsonb;
  v_steps jsonb := '[]'::jsonb; v_graph jsonb := '[]'::jsonb; v_keep uuid[] := '{}';
  s jsonb; i int; v_elapsed int := 0; v_kind text; v_text text; v_days int; v_cond jsonb; v_cid uuid; c app.campaigns; v_cname text; v_r jsonb; k text;
begin
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('name', 'trigger', 'stage_id', 'list', 'exit', 'steps') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if p_id is not null then
    select * into w from app.workflows where id = p_id and deleted_at is null and kind = 'workflow' and options ? 'simple';
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    v_old := coalesce(w.options -> 'simple' -> 'steps', '[]'::jsonb);
  end if;

  v_name := btrim(coalesce(v ->> 'name', ''));
  if char_length(v_name) not between 1 and 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;

  v_trigger := v ->> 'trigger';
  if v_trigger = 'deal_stage' then
    v_stage := (select st.id from app.stages st where st.id::text = v ->> 'stage_id');
    if v_stage is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage_id'; end if;
    v_tc := jsonb_build_object('entity', 'deal', 'event', 'stage_changed');
    v_groups := jsonb_build_array(jsonb_build_object('f', 'stage_id', 'op', 'eq', 'v', v_stage));
  elsif v_trigger = 'form_submitted' then
    v_tc := jsonb_build_object('entity', 'lead', 'event', 'form.submitted');
  elsif v_trigger in ('trial_started', 'trial_ending', 'list_added', 'account_cancels', 'send_now') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger.not_available';
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger';
  end if;

  if v ->> 'list' is not null then
    v_list := (select sv.id from app.saved_views sv where sv.id::text = v ->> 'list' and sv.kind = 'segment' and (sv.shared or sv.owner_id = v_me));
    if v_list is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'list'; end if;
    v_groups := v_groups || jsonb_build_array(jsonb_build_object('f', 'segment', 'v', v_list));
  end if;
  if jsonb_array_length(v_groups) > 0 then v_tc := v_tc || jsonb_build_object('groups', jsonb_build_array(v_groups)); end if;

  v_exit := v ->> 'exit';
  if v_exit is null or v_exit not in ('reply_unsub', 'paying', 'never') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'exit'; end if;

  if jsonb_typeof(v -> 'steps') <> 'array' or jsonb_array_length(v -> 'steps') not between 1 and 30 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps';
  end if;
  for s, i in select x, n::int from jsonb_array_elements(v -> 'steps') with ordinality t(x, n) loop
    v_kind := s ->> 'kind';
    -- «stop when»: checked before each email and task that follows a wait (a run that fails it ends)
    if v_kind in ('email', 'task') and v_elapsed > 0 and v_exit <> 'never' then
      v_exitf := case v_exit when 'paying' then jsonb_build_object('f', 'org_paying', 'op', 'neq')
                             else jsonb_build_object('f', 'email.replied', 'op', 'neq', 'v', v_elapsed + 1) end;
      -- the same test right before it (a «not paying» condition step) is not repeated
      if v_graph -> -1 -> 'config' is distinct from jsonb_build_object('groups', jsonb_build_array(jsonb_build_array(v_exitf))) then
        v_graph := v_graph || jsonb_build_array(jsonb_build_object('key', 'x' || i, 'kind', 'condition', 'config', jsonb_build_object('groups', jsonb_build_array(jsonb_build_array(v_exitf)))));
      end if;
    end if;
    case v_kind
      when 'email' then
        v_text := btrim(coalesce(s ->> 'text', ''));
        if char_length(v_text) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i || '.text'; end if;
        v_cname := left(v_name || ' · ' || v_text, 120);
        -- an email this sequence made before keeps its campaign; any other id is ignored and a new draft is made
        select * into c from app.campaigns x
        where x.id::text = s ->> 'campaign_id' and x.type = 'automated' and x.deleted_at is null
          and exists (select 1 from jsonb_array_elements(v_old) o where o ->> 'campaign_id' = x.id::text);
        if c.id is null or c.id = any (v_keep) then
          v_cid := (public.campaign_save(null, jsonb_build_object('type', 'automated', 'name', v_cname, 'subject_a', v_text)) ->> 'id')::uuid;
        else
          v_cid := c.id;
          if c.name is distinct from v_cname or (c.status = 'draft' and c.subject_a is distinct from v_text) then
            perform public.campaign_save(c.id, case when c.status = 'draft' then jsonb_build_object('name', v_cname, 'subject_a', v_text)
                                                   else jsonb_build_object('name', v_cname) end);
          end if;
        end if;
        c := null;
        v_keep := v_keep || v_cid;
        v_steps := v_steps || jsonb_build_array(jsonb_build_object('kind', 'email', 'text', v_text, 'campaign_id', v_cid));
        v_graph := v_graph || jsonb_build_array(jsonb_build_object('key', 's' || i, 'kind', 'campaign_action', 'config', jsonb_build_object('campaign_id', v_cid)));
      when 'wait' then
        v_days := case when jsonb_typeof(s -> 'days') = 'number' and (s ->> 'days') ~ '^\d+$' then (s ->> 'days')::int end;
        if v_days is null or v_days not between 1 and 365 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i || '.days'; end if;
        v_elapsed := v_elapsed + v_days;
        v_steps := v_steps || jsonb_build_array(jsonb_build_object('kind', 'wait', 'days', v_days));
        v_graph := v_graph || jsonb_build_array(jsonb_build_object('key', 's' || i, 'kind', 'delay', 'config', jsonb_build_object('amount', v_days, 'unit', 'days', 'skip_weekends', false)));
      when 'cond' then
        v_cond := case s ->> 'cond'
          when 'not_paying' then jsonb_build_object('f', 'org_paying', 'op', 'neq')
          when 'employees_missing' then jsonb_build_object('f', 'org_milestone', 'op', 'neq', 'v', 'employees_uploaded')
          when 'on_list' then case when v_list is not null then jsonb_build_object('f', 'segment', 'v', v_list) end end;
        if v_cond is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i || '.cond'; end if;
        v_steps := v_steps || jsonb_build_array(jsonb_build_object('kind', 'cond', 'cond', s ->> 'cond'));
        v_graph := v_graph || jsonb_build_array(jsonb_build_object('key', 's' || i, 'kind', 'condition', 'config', jsonb_build_object('groups', jsonb_build_array(jsonb_build_array(v_cond)))));
      when 'task' then
        v_text := btrim(coalesce(s ->> 'text', ''));
        if char_length(v_text) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i || '.text'; end if;
        v_steps := v_steps || jsonb_build_array(jsonb_build_object('kind', 'task', 'text', v_text));
        v_graph := v_graph || jsonb_build_array(jsonb_build_object('key', 's' || i, 'kind', 'create_activity',
                                                'config', jsonb_build_object('type', 'task', 'subject', v_text, 'due_in_days', 0, 'owner', '@record_owner')));
      else
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'steps.' || i || '.kind';
    end case;
  end loop;

  v_r := public.workflow_save(p_id,
    jsonb_build_object('name', v_name, 'kind', 'workflow', 'trigger_type', 'event', 'trigger_config', v_tc, 'template_key', 'simple_sequence',
                       'options', jsonb_build_object('simple', jsonb_build_object('trigger', v_trigger, 'stage_id', v_stage, 'list', v_list, 'exit', v_exit, 'steps', v_steps))),
    jsonb_build_object('steps', v_graph), p_version);

  -- an email taken out of the sequence takes its draft with it (a campaign that has been activated is kept for its report)
  update app.campaigns x set deleted_at = now(), updated_at = now(), updated_by = v_me, version = x.version + 1
  where x.id in (select (o ->> 'campaign_id')::uuid from jsonb_array_elements(v_old) o where o ->> 'kind' = 'email')
    and not x.id = any (v_keep) and x.status = 'draft' and x.type = 'automated' and x.deleted_at is null
    and not exists (select 1 from app.workflows w2 join app.workflow_versions wv on wv.workflow_id = w2.id and wv.version = w2.current_version
                    cross join lateral jsonb_each(wv.flat) n(kk, xx)
                    where w2.deleted_at is null and n.kk <> '_start' and xx ->> 'kind' = 'campaign_action' and xx -> 'config' ->> 'campaign_id' = x.id::text);
  return jsonb_build_object('id', v_r ->> 'id', 'version', (v_r ->> 'version')::int,
                            'simple', (select options -> 'simple' from app.workflows where id = (v_r ->> 'id')::uuid));
end $fn$;

-- the simple interface's email campaigns: the model, the state (a draft that was active before is paused), what still blocks
-- activation, the runs started (enrolled) and each email's figures (campaign_stats; null until it has recipients, and for
-- another person's campaign without Campaigns › See reports of others or Edit others)
create function public.simple_sequences_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', w.id, 'name', w.name, 'state', w.state, 'activated', w.activated_at is not null, 'version', w.version,
      'owner', (select a.name from app.admins a where a.id = w.owner_id), 'mine', w.owner_id = v_me,
      'blockers', to_jsonb(app.wf_blockers(w.id)),
      'simple', w.options -> 'simple',
      'enrolled', (select count(*) from app.workflow_runs r where r.workflow_id = w.id),
      'emails', coalesce((select jsonb_agg(jsonb_build_object('campaign_id', c.id, 'status', c.status,
                                                              'stats', case when app.campaign_reports_ok(c) then app.campaign_stats(c.id) end))
                          from app.campaigns c
                          where c.id in (select (x ->> 'campaign_id')::uuid from jsonb_array_elements(w.options -> 'simple' -> 'steps') x where x ->> 'kind' = 'email')), '[]'::jsonb))
    order by w.created_at, w.name)
    from app.workflows w where w.deleted_at is null and w.kind = 'workflow' and w.options ? 'simple'), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['app.wf_person(text, uuid)', 'app.in_segment(text, uuid, uuid)', 'app.org_paying(uuid)', 'app.org_milestone(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.simple_sequence_save(uuid, jsonb, int)', 'public.simple_sequences_get()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
