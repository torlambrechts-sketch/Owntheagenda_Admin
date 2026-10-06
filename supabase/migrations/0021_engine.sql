-- 0021_engine.sql — the one workflow engine (D-06): workflows, sequences, lifecycle messages and assignment
-- rules run on the same tables and the same executor (AUT-01..12, SF-02).
--
-- Events. Every write emits a row in app.events (0004). Several subscribers read them, each once, behind
-- its own cursor (event_cursors): workflows, assignment and sequences here, feed and scores in 0022. The
-- dispatcher runs every minute; a subscriber that fails on one event records the failure and moves on.
--
-- Runs. A run pins the workflow's version, so editing an active workflow never breaks a run in flight. The
-- executor walks the graph step by step in SQL as the workflow's owner (app.acting_as), so a workflow can
-- never do more than its owner may. Steps that leave the database (webhook, Slack, Teams, accounting) go
-- on the job queue for an edge worker, which reports back; a step whose integration is not connected fails
-- with «not_connected», and activation refuses it up front.
--
-- Safeguards (setting «safeguards»): a rolling ten-minute window of 10 000 runs in all and 5 000 per
-- workflow (the source values), a custom number, or off. A workflow never triggers itself from its own run.
-- Limits on steps per path apply only when count_limits is set to a number (D-16).

-- ---------------------------------------------------------------------------
-- acting as a staff member: the executor and the dispatcher run in pg_cron, outside any request. app.me()
-- honours app.acting_as only in such a database-internal session, never in one that came through the API.
create or replace function app.me() returns uuid
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(
    (select a.id from app.admins a
     where session_user not in ('authenticator', 'anon', 'authenticated', 'service_role')
       and a.id = nullif(current_setting('app.acting_as', true), '')::uuid and a.active),
    (select a.id from app.admins a join auth.users u on lower(u.email) = a.email
     where u.id = auth.uid() and u.email_confirmed_at is not null and a.active
       and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'))
$fn$;

-- events written inside a run carry the run, so the dispatcher can bound chains of workflows
create or replace function app.emit(p_kind text, p_subject_type text, p_subject_id uuid, p_payload jsonb default '{}'::jsonb,
                                    p_sample boolean default false)
  returns bigint language sql volatile security definer set search_path = ''
as $fn$
  insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
  values (p_kind, p_subject_type, p_subject_id, app.me(),
          coalesce(p_payload, '{}'::jsonb) || case when nullif(current_setting('app.run_id', true), '') is not null
                                                   then jsonb_build_object('_run', current_setting('app.run_id', true)) else '{}'::jsonb end,
          coalesce(p_sample, false))
  returning id;
$fn$;

-- product events reach the subscribers as platform events about the organisation (source «product»)
create function app.product_event_out() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_org uuid;
begin
  if new.kind !~ '^[a-z_]+\.[a-z_]+$' then return new; end if;
  select o.id into v_org from app.account_products ap join app.organizations o on o.account_id = ap.account_id
  where ap.product = new.product and ap.tenant_id = new.tenant_id and o.deleted_at is null order by o.created_at limit 1;
  if v_org is null then return new; end if;
  insert into app.events (kind, subject_type, subject_id, payload, is_sample)
  values (new.kind, 'organization', v_org,
          jsonb_build_object('source', 'product', 'product', new.product, 'event_in', new.id,
                             'data', (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(new.payload) as x(k, v)
                                      where jsonb_typeof(v) in ('string', 'number', 'boolean') and k !~ '(name|email|phone)')),
          false);
  return new;
end $fn$;
create trigger events_in_out after insert on app.events_in for each row execute function app.product_event_out();

-- ---------------------------------------------------------------------------
create table app.event_subscribers (
  name    text primary key check (name ~ '^[a-z_]{2,40}$'),
  fn      text not null check (fn ~ '^app\.[a-z_]+$'),
  ord     int not null default 0,
  enabled boolean not null default true
);

create table app.event_cursors (
  subscriber    text primary key references app.event_subscribers (name) on delete cascade,
  last_event_id bigint not null default 0,
  updated_at    timestamptz not null default now()
);

create table app.event_failures (
  id         bigint generated always as identity primary key,
  subscriber text not null,
  event_id   bigint not null,
  error      text not null check (char_length(error) <= 500),
  at         timestamptz not null default now()
);

create table app.workflows (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null default 'workflow' check (kind in ('workflow', 'sequence', 'lifecycle', 'assignment')),
  name             text not null check (char_length(btrim(name)) between 1 and 120),
  description      text check (description is null or char_length(description) <= 500),
  owner_id         uuid not null references app.admins (id),
  state            text not null default 'draft' check (state in ('draft', 'active')),
  trigger_type     text not null default 'event' check (trigger_type in ('event', 'date', 'product_event', 'enrollment')),
  trigger_config   jsonb not null default '{}'::jsonb check (jsonb_typeof(trigger_config) = 'object'),
  options          jsonb not null default '{}'::jsonb check (jsonb_typeof(options) = 'object'),
  priority         int,
  activation_scope text not null default 'everyone' check (activation_scope in ('owner', 'users', 'team', 'everyone')),
  template_key     text,
  current_version  int not null default 0,
  activated_at     timestamptz,
  is_sample        boolean not null default false,
  version          int not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  deleted_at       timestamptz
);
create index workflows_active on app.workflows (kind, trigger_type) where state = 'active' and deleted_at is null;

create table app.workflow_versions (
  workflow_id  uuid not null references app.workflows (id) on delete cascade,
  version      int not null check (version >= 1),
  graph        jsonb not null check (jsonb_typeof(graph) = 'object'),
  flat         jsonb not null check (jsonb_typeof(flat) = 'object'),
  published_at timestamptz not null default now(),
  published_by uuid,
  primary key (workflow_id, version)
);

create table app.workflow_activation (
  workflow_id uuid not null references app.workflows (id) on delete cascade,
  staff_id    uuid references app.admins (id) on delete cascade,
  team_id     uuid references app.teams (id) on delete cascade,
  check ((staff_id is null) <> (team_id is null))
);
create unique index workflow_activation_one on app.workflow_activation (workflow_id, coalesce(staff_id, team_id));

create table app.workflow_runs (
  id            uuid primary key default gen_random_uuid(),
  workflow_id   uuid not null references app.workflows (id) on delete cascade,
  version       int not null,
  event_id      bigint,
  subject_type  text check (subject_type is null or subject_type ~ '^[a-z_]{2,40}$'),
  subject_id    uuid,
  state         text not null default 'running' check (state in ('running', 'waiting', 'completed', 'failed', 'stopped', 'loop_blocked')),
  cursor        text,
  resume_at     timestamptz,
  wait_event    text,
  wait_ref      text,
  wait_deadline timestamptz,
  wait_then     text check (wait_then is null or wait_then in ('continue', 'stop')),
  depth         int not null default 0,
  origin_run_id uuid,
  retry_of      uuid references app.workflow_runs (id) on delete set null,
  enrollment_id uuid,
  error         text check (error is null or char_length(error) <= 300),
  is_sample     boolean not null default false,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index workflow_runs_recent on app.workflow_runs (started_at desc);
create index workflow_runs_wf on app.workflow_runs (workflow_id, started_at desc);
create index workflow_runs_waiting on app.workflow_runs (wait_event) where state = 'waiting';
create index workflow_runs_resume on app.workflow_runs (resume_at) where state = 'waiting';
create index workflow_runs_subject on app.workflow_runs (subject_type, subject_id);

create table app.workflow_run_steps (
  id              uuid primary key default gen_random_uuid(),
  run_id          uuid not null references app.workflow_runs (id) on delete cascade,
  step_key        text not null,
  kind            text not null,
  state           text not null default 'running' check (state in ('running', 'succeeded', 'failed', 'not_met', 'waiting', 'queued', 'skipped')),
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  error           text check (error is null or char_length(error) <= 300),
  request         jsonb,
  response_status int,
  output          jsonb
);
create index workflow_run_steps_run on app.workflow_run_steps (run_id, started_at);

create table app.workflow_templates (
  key            text primary key check (key ~ '^[a-z_]{2,40}$'),
  group_key      text not null check (group_key ~ '^[a-z_]{2,40}$'),
  kind           text not null default 'workflow',
  trigger_type   text not null,
  trigger_config jsonb not null default '{}'::jsonb,
  graph          jsonb not null,
  ord            int not null default 0
);

create table app.sequence_enrollments (
  id           uuid primary key default gen_random_uuid(),
  workflow_id  uuid not null references app.workflows (id) on delete cascade,
  entity       text not null check (entity in ('deal', 'lead')),
  record_id    uuid not null,
  enrolled_via text not null check (enrolled_via in ('one', 'bulk', 'workflow')),
  enrolled_by  uuid references app.admins (id) on delete set null,
  run_id       uuid references app.workflow_runs (id) on delete set null,
  state        text not null default 'in_progress' check (state in ('in_progress', 'completed', 'failed', 'exited')),
  current_ord  int not null default 0,
  current_key  text,
  exit_reason  text check (exit_reason is null or exit_reason in ('reply', 'stage_change', 'manual', 'record_closed', 'record_deleted')),
  error        text check (error is null or char_length(error) <= 300),
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now(),
  ended_at     timestamptz
);
create unique index sequence_enrollment_once on app.sequence_enrollments (workflow_id, entity, record_id) where state = 'in_progress';
create index sequence_enrollments_record on app.sequence_enrollments (entity, record_id) where state = 'in_progress';
alter table app.email_messages add constraint email_messages_enrollment_fk foreign key (enrollment_id) references app.sequence_enrollments (id) on delete set null;
alter table app.email_messages add constraint email_messages_step_fk foreign key (run_step_id) references app.workflow_run_steps (id) on delete set null;
alter table app.workflow_runs add constraint workflow_runs_enrollment_fk foreign key (enrollment_id) references app.sequence_enrollments (id) on delete set null;

create table app.assignment_rotation (
  team_id       uuid primary key references app.teams (id) on delete cascade,
  last_staff_id uuid references app.admins (id) on delete set null,
  updated_at    timestamptz not null default now()
);

create table app.assignment_evaluations (
  id          bigint generated always as identity primary key,
  workflow_id uuid references app.workflows (id) on delete set null,
  entity      text not null,
  record_id   uuid not null,
  assignee_id uuid references app.admins (id) on delete set null,
  at          timestamptz not null default now()
);
create index assignment_evaluations_record on app.assignment_evaluations (entity, record_id, at desc);

create table app.integration_connections (
  provider        text primary key check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello')),
  status          text not null default 'not_connected' check (status in ('not_connected', 'connected', 'error')),
  vault_secret_id uuid,
  config          jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  connected_by    uuid references app.admins (id) on delete set null,
  connected_at    timestamptz
);
insert into app.integration_connections (provider) values ('slack'), ('teams'), ('accounting'), ('asana'), ('trello');

-- ---------------------------------------------------------------------------
-- the graph. Steps are a list; an if/else step holds two lists. Each step: {key, kind, config, then?, else?}.
-- Publishing flattens it into a map key → {kind, config, next, then, else} with «_start».
create function app.wf_flatten(p_steps jsonb, p_after text) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
declare out jsonb := '{}'::jsonb; n int := coalesce(jsonb_array_length(p_steps), 0); i int; s jsonb; nxt text;
begin
  for i in 0 .. n - 1 loop
    s := p_steps -> i;
    nxt := case when i < n - 1 then (p_steps -> (i + 1)) ->> 'key' else p_after end;
    if s ->> 'kind' = 'if_else' then
      out := out || jsonb_build_object(s ->> 'key', jsonb_build_object('kind', 'if_else', 'config', coalesce(s -> 'config', '{}'::jsonb), 'next', nxt,
                                                                       'then', coalesce((s -> 'then' -> 0) ->> 'key', nxt), 'else', coalesce((s -> 'else' -> 0) ->> 'key', nxt)))
             || app.wf_flatten(coalesce(s -> 'then', '[]'::jsonb), nxt) || app.wf_flatten(coalesce(s -> 'else', '[]'::jsonb), nxt);
    else
      out := out || jsonb_build_object(s ->> 'key', jsonb_build_object('kind', s ->> 'kind', 'config', coalesce(s -> 'config', '{}'::jsonb), 'next', nxt));
    end if;
  end loop;
  return out;
end $fn$;

-- the most actions, delays and delay days along any path
create function app.wf_path_counts(p_steps jsonb) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
declare s jsonb; a int := 0; d int := 0; dd numeric := 0; t jsonb; e jsonb; best jsonb;
begin
  for s in select * from jsonb_array_elements(coalesce(p_steps, '[]'::jsonb)) loop
    if s ->> 'kind' = 'if_else' then
      t := app.wf_path_counts(s -> 'then'); e := app.wf_path_counts(s -> 'else');
      a := a + greatest((t ->> 'actions')::int, (e ->> 'actions')::int);
      d := d + greatest((t ->> 'delays')::int, (e ->> 'delays')::int);
      dd := dd + greatest((t ->> 'days')::numeric, (e ->> 'days')::numeric);
    elsif s ->> 'kind' in ('delay', 'wait_for') then
      d := d + 1;
      dd := dd + case when s ->> 'kind' = 'wait_for' then coalesce((s -> 'config' ->> 'timeout_days')::numeric, 7)
                      else coalesce((s -> 'config' ->> 'amount')::numeric, 0) / case coalesce(s -> 'config' ->> 'unit', 'days') when 'minutes' then 1440 when 'hours' then 24 else 1 end end;
    elsif s ->> 'kind' not in ('condition') then
      a := a + 1;
    end if;
  end loop;
  return jsonb_build_object('actions', a, 'delays', d, 'days', dd);
end $fn$;

create function app.count_limit() returns numeric
  language sql stable security definer set search_path = ''
as $fn$
  select case when app.setting('count_limits') = 'number' then (select value_number from app.setting_values where key = 'count_limits' and scope_id = '') end
$fn$;

-- is a URL one a webhook may call? https only, no private, loopback, link-local or internal host. The
-- worker checks the resolved address again before connecting and follows no redirect into these ranges.
create function app.url_public(p_url text) returns boolean
  language plpgsql immutable set search_path = ''
as $fn$
declare h text;
begin
  if p_url is null or p_url !~ '^https://[^/\s?#]+' or char_length(p_url) > 2000 then return false; end if;
  h := lower(substring(p_url from '^https://(?:[^@/]*@)?(\[[^\]]+\]|[^:/?#]+)'));
  if h is null or h ~ '@' then return false; end if;
  if h in ('localhost') or h ~ '\.(local|internal|localhost|lan|home|corp)$' or h !~ '\.' and h !~ '^\[' then return false; end if;
  if h ~ '^\[' then return false; end if;                                       -- literal IPv6: refused outright
  if h ~ '^\d+\.\d+\.\d+\.\d+$' then
    if h ~ '^(10|127|0)\.' or h ~ '^169\.254\.' or h ~ '^192\.168\.' or h ~ '^172\.(1[6-9]|2\d|3[01])\.' or h ~ '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.' then
      return false;
    end if;
  end if;
  return true;
end $fn$;

-- step kinds by workflow kind, and the external ones
create function app.wf_kinds(p_kind text) returns text[]
  language sql immutable set search_path = ''
as $fn$
  select case p_kind
    when 'sequence' then array['email_auto', 'email_manual', 'delay', 'activity']
    when 'assignment' then array[]::text[]
    else array['condition', 'if_else', 'delay', 'wait_for', 'create_record', 'update_record', 'delete_record', 'create_activity', 'add_note',
               'notify', 'send_email', 'enroll_sequence', 'assign_owner', 'create_ticket', 'campaign_action', 'project_action', 'webhook',
               'slack', 'teams', 'accounting_invoice'] end
$fn$;

-- validate a graph; raises invalid with detail «graph.<key>.<field>»
create function app.wf_validate(p_kind text, p_graph jsonb, p_entity text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
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
        if not exists (select 1 from app.email_templates t where t.id::text = c ->> 'template_id' and t.deleted_at is null) then
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
end $fn$;

-- what an active workflow still lacks to run: integrations not connected, features not built yet
create function app.wf_blockers(p_wf uuid) returns text[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(distinct b) filter (where b is not null), '{}') from (
    select case
      when n.v ->> 'kind' = 'slack' and not exists (select 1 from app.integration_connections c where c.provider = 'slack' and c.status = 'connected') then 'not_connected:slack'
      when n.v ->> 'kind' = 'teams' and not exists (select 1 from app.integration_connections c where c.provider = 'teams' and c.status = 'connected') then 'not_connected:teams'
      when n.v ->> 'kind' = 'accounting_invoice' and not exists (select 1 from app.integration_connections c where c.provider = 'accounting' and c.status = 'connected') then 'not_connected:accounting'
      when n.v ->> 'kind' = 'campaign_action' then 'not_available:campaigns'
      when n.v ->> 'kind' = 'project_action' then 'not_available:projects'
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
$fn$;

-- ---------------------------------------------------------------------------
-- matching. A condition is groups of filters: a group matches when all its filters match; the condition
-- when any group matches (AND inside a group, OR between groups). A filter is {f, op, v}, on the subject,
-- or {rel, f, op, v} on a record it points at (rel = organization_id, person_id …), or a mail test
-- {f: 'email.opened' | 'email.replied', v: days}.
create function app.wf_match(p_entity text, p_id uuid, p_groups jsonb) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare g jsonb; fl jsonb; ok boolean; e app.entities; re app.entities; v_rel uuid; v_hit boolean;
begin
  if p_groups is null or jsonb_typeof(p_groups) <> 'array' or jsonb_array_length(p_groups) = 0 then return true; end if;
  select * into e from app.entities where key = p_entity;
  for g in select * from jsonb_array_elements(p_groups) loop
    ok := true;
    for fl in select * from jsonb_array_elements(case when jsonb_typeof(g) = 'array' then g else jsonb_build_array(g) end) loop
      if fl ->> 'f' in ('email.opened', 'email.replied') then
        v_hit := exists (select 1 from app.email_links l join app.email_messages m on m.thread_id = l.thread_id
                         where l.entity = p_entity and l.record_id = p_id and m.direction = case fl ->> 'f' when 'email.replied' then 'in' else 'out' end
                           and (fl ->> 'f' = 'email.replied' or exists (select 1 from app.email_tracking_events te where te.message_id = m.id and te.kind = 'open' and te.client_class <> 'prefetch'
                                                                       and te.at >= now() - make_interval(days => coalesce((fl ->> 'v')::int, 7))))
                           and (fl ->> 'f' = 'email.opened' or m.received_at >= now() - make_interval(days => coalesce((fl ->> 'v')::int, 7))));
        if coalesce(fl ->> 'op', 'eq') = 'neq' then v_hit := not v_hit; end if;
      elsif fl ? 'rel' then
        if not exists (select 1 from app.entity_columns c where c.entity = p_entity and c.col = fl ->> 'rel' and c.ref is not null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.rel';
        end if;
        select * into re from app.entities where key = (select c.ref from app.entity_columns c where c.entity = p_entity and c.col = fl ->> 'rel');
        execute format('select t.%I from app.%I t where t.id = %L', fl ->> 'rel', e.tbl, p_id) into v_rel;
        if v_rel is null then v_hit := false;
        else
          execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null %s)', re.tbl, v_rel, app.filter_sql(re, jsonb_build_array(fl - 'rel'))) into v_hit;
        end if;
      else
        execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null %s)', e.tbl, p_id, app.filter_sql(e, jsonb_build_array(fl))) into v_hit;
      end if;
      if not v_hit then ok := false; exit; end if;
    end loop;
    if ok then return true; end if;
  end loop;
  return false;
end $fn$;

-- a value in a step's config: «@record_owner», «@workflow_owner», «@today+N», «@now» or a literal
create function app.wf_value(p_v jsonb, p_entity text, p_id uuid, p_owner uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare s text; e app.entities; v uuid;
begin
  if jsonb_typeof(p_v) <> 'string' then return p_v; end if;
  s := p_v #>> '{}';
  if s = '@workflow_owner' then return to_jsonb(p_owner); end if;
  if s = '@record_owner' then
    select * into e from app.entities where key = p_entity;
    if e.owned then execute format('select t.owner_id from app.%I t where t.id = %L', e.tbl, p_id) into v; end if;
    return to_jsonb(coalesce(v, p_owner));
  end if;
  if s = '@now' then return to_jsonb(now()); end if;
  if s ~ '^@today([+-]\d{1,3})?$' then return to_jsonb(current_date + coalesce(nullif(substr(s, 7), '')::int, 0)); end if;
  return p_v;
end $fn$;

-- {deal.org.orgnr}-style merges for webhook bodies: the first part is the subject's type, then columns,
-- following references (org = organization_id, person = person_id, owner = owner_id) one step at a time
create function app.wf_render(p_text text, p_entity text, p_id uuid, p_json boolean default false) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m text[]; parts text[]; out text := coalesce(p_text, ''); cur_e text; cur_id uuid; v text; i int; e app.entities; v_col text; r text;
begin
  for m in select regexp_matches(coalesce(p_text, ''), '\{([a-z_]+(?:\.[a-z_]+){1,3})\}', 'g') loop
    parts := string_to_array(m[1], '.');
    v := null;
    if parts[1] = p_entity then
      cur_e := p_entity; cur_id := p_id;
      for i in 2 .. array_length(parts, 1) loop
        exit when cur_id is null;
        select * into e from app.entities where key = cur_e;
        v_col := case parts[i] when 'org' then 'organization_id' when 'person' then 'person_id' when 'owner' then 'owner_id' when 'orgnr' then 'org_number' else parts[i] end;
        if i < array_length(parts, 1) then
          if v_col = 'owner_id' and e.owned then
            execute format('select t.owner_id from app.%I t where t.id = %L', e.tbl, cur_id) into cur_id; cur_e := 'staff';
          else
            select c.ref into r from app.entity_columns c where c.entity = cur_e and c.col = v_col;
            if r is null then cur_id := null; exit; end if;
            execute format('select t.%I from app.%I t where t.id = %L', v_col, e.tbl, cur_id) into cur_id; cur_e := r;
          end if;
        elsif cur_e = 'staff' then
          v := (select case v_col when 'email' then a.email when 'name' then a.name end from app.admins a where a.id = cur_id);
        elsif v_col in ('id', 'created_at', 'updated_at') or exists (select 1 from app.entity_columns c where c.entity = cur_e and c.col = v_col) then
          execute format('select t.%I::text from app.%I t where t.id = %L', v_col, e.tbl, cur_id) into v;
        end if;
      end loop;
    end if;
    out := replace(out, '{' || m[1] || '}', case when p_json then coalesce(substr(to_json(coalesce(v, ''))::text, 2, char_length(to_json(coalesce(v, ''))::text) - 2), '')
                                                 else coalesce(v, '') end);
  end loop;
  return out;
end $fn$;

-- the time a delay ends; business days skip Saturday and Sunday (Europe/Oslo)
create function app.wf_delay_until(p_from timestamptz, p_amount numeric, p_unit text, p_skip_weekends boolean) returns timestamptz
  language plpgsql stable set search_path = ''
as $fn$
declare t timestamptz := p_from; n int; d int;
begin
  if coalesce(p_unit, 'days') <> 'days' or not coalesce(p_skip_weekends, false) then
    return p_from + case coalesce(p_unit, 'days') when 'minutes' then make_interval(mins => p_amount::int) when 'hours' then make_interval(hours => p_amount::int)
                                                  else make_interval(days => p_amount::int) end;
  end if;
  n := p_amount::int;
  while n > 0 loop
    t := t + interval '1 day';
    d := extract(isodow from t at time zone 'Europe/Oslo');
    if d < 6 then n := n - 1; end if;
  end loop;
  while extract(isodow from t at time zone 'Europe/Oslo') >= 6 loop t := t + interval '1 day'; end loop;
  return t;
end $fn$;

-- the facts an assignment rule is tested against: from a record, or typed into «Test a record»
create function app.assign_facts(p_entity text, p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_org uuid; v_person uuid; v_source text;
begin
  if p_entity = 'lead' then select organization_id, person_id, source into v_org, v_person, v_source from app.leads where id = p_id;
  elsif p_entity = 'deal' then select organization_id, person_id, source into v_org, v_person, v_source from app.deals where id = p_id;
  elsif p_entity = 'person' then select organization_id, id, source into v_org, v_person, v_source from app.people where id = p_id;
  elsif p_entity = 'organization' then select id, null, source into v_org, v_person, v_source from app.organizations where id = p_id;
  end if;
  return jsonb_build_object('entity', p_entity, 'source', v_source,
    'org_exists', v_org is not null and exists (select 1 from app.organizations o where o.id = v_org and o.created_at < now() - interval '1 minute'),
    'employees', (select o.employees from app.organizations o where o.id = v_org),
    'org_labels', coalesce((select to_jsonb(o.labels) from app.organizations o where o.id = v_org), '[]'::jsonb),
    'org_owner', (select o.owner_id from app.organizations o where o.id = v_org),
    'person_owner', (select p.owner_id from app.people p where p.id = v_person));
end $fn$;

-- does a rule's condition hold? {sources: [..], employees_min, employees_max, org_exists: bool, org_labels_any: [..]}; {} is «everything else»
create function app.assign_match(p_cond jsonb, p_facts jsonb) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select (not (p_cond ? 'sources') or lower(coalesce(p_facts ->> 'source', '')) in (select lower(x) from jsonb_array_elements_text(p_cond -> 'sources') x))
     and (not (p_cond ? 'employees_min') or coalesce((p_facts ->> 'employees')::int, -1) >= (p_cond ->> 'employees_min')::int)
     and (not (p_cond ? 'employees_max') or coalesce((p_facts ->> 'employees')::int, 2147483647) <= (p_cond ->> 'employees_max')::int)
     and (not (p_cond ? 'org_exists') or (p_facts ->> 'org_exists')::boolean = (p_cond ->> 'org_exists')::boolean)
     and (not (p_cond ? 'org_labels_any') or exists (select 1 from jsonb_array_elements_text(p_cond -> 'org_labels_any') a
                                                    where a in (select jsonb_array_elements_text(coalesce(p_facts -> 'org_labels', '[]'::jsonb)))))
$fn$;

-- the staff member a rule assigns to. Round-robin takes the next active team member after the pointer;
-- p_advance moves the pointer (a test does not).
create function app.assign_pick(p_assignee jsonb, p_facts jsonb, p_advance boolean) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_team uuid; v_last uuid; v_next uuid;
begin
  case p_assignee ->> 'kind'
    when 'user' then
      return (select a.id from app.admins a where a.id = (p_assignee ->> 'staff_id')::uuid and a.active);
    when 'org_owner' then return (p_facts ->> 'org_owner')::uuid;
    when 'person_owner' then return (p_facts ->> 'person_owner')::uuid;
    when 'team_rr' then
      v_team := (p_assignee ->> 'team_id')::uuid;
      select last_staff_id into v_last from app.assignment_rotation where team_id = v_team for update;
      select a.id into v_next from app.team_members tm join app.admins a on a.id = tm.staff_id
      where tm.team_id = v_team and a.active and (v_last is null or a.id > v_last) order by a.id limit 1;
      if v_next is null then
        select a.id into v_next from app.team_members tm join app.admins a on a.id = tm.staff_id where tm.team_id = v_team and a.active order by a.id limit 1;
      end if;
      if p_advance and v_next is not null then
        insert into app.assignment_rotation (team_id, last_staff_id, updated_at) values (v_team, v_next, now())
        on conflict (team_id) do update set last_staff_id = excluded.last_staff_id, updated_at = now();
      end if;
      return v_next;
    else return null;
  end case;
end $fn$;

-- ---------------------------------------------------------------------------
-- the executor
create function app.wf_finish(p_run uuid, p_state text, p_error text default null) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.workflow_runs; w app.workflows;
begin
  update app.workflow_runs set state = p_state, error = left(p_error, 300), finished_at = now(), cursor = case when p_state = 'completed' then null else cursor end,
    resume_at = null, wait_event = null, wait_ref = null, wait_deadline = null
  where id = p_run returning * into r;
  if r.enrollment_id is not null then
    update app.sequence_enrollments set state = case p_state when 'completed' then 'completed' when 'failed' then 'failed' else state end,
      error = case when p_state = 'failed' then left(p_error, 300) else error end, ended_at = case when p_state in ('completed', 'failed') then now() else ended_at end
    where id = r.enrollment_id and state = 'in_progress';
  end if;
  if p_state = 'failed' then
    select * into w from app.workflows where id = r.workflow_id;
    perform app.notify(w.owner_id, 'system', 'workflow.failed', jsonb_build_object('workflow', w.name, 'error', left(p_error, 120)), '/automation', w.kind, w.id);
  end if;
end $fn$;

-- one step. Returns the next key ('' = finished), or null when the run now waits.
create function app.wf_step(p_run app.workflow_runs, p_wf app.workflows, p_key text, p_node jsonb, p_step uuid) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
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
    when 'campaign_action', 'project_action' then
      raise exception 'not_available';
    else
      raise exception 'unknown_step';
  end case;
  update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step and state = 'running';
  if p_run.enrollment_id is not null then
    update app.sequence_enrollments set current_ord = current_ord + 1, current_key = p_node ->> 'next' where id = p_run.enrollment_id;
  end if;
  return coalesce(p_node ->> 'next', '');
end $fn$;

-- walk a run until it waits, fails or finishes (at most 50 steps at a time)
create function app.wf_advance(p_run uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  r app.workflow_runs; w app.workflows; v_flat jsonb; v_key text; v_node jsonb; v_step uuid; v_next text; i int := 0; v_err text;
  v_prev_actor text := current_setting('app.acting_as', true); v_prev_run text := current_setting('app.run_id', true);
begin
  select * into r from app.workflow_runs where id = p_run for update;
  if not found or r.state <> 'running' then return; end if;
  select * into w from app.workflows where id = r.workflow_id;
  select flat into v_flat from app.workflow_versions where workflow_id = r.workflow_id and version = r.version;
  perform set_config('app.acting_as', w.owner_id::text, true);
  perform set_config('app.run_id', r.id::text, true);
  v_key := coalesce(r.cursor, v_flat ->> '_start');
  loop
    if v_key is null or v_key = '' then perform app.wf_finish(r.id, 'completed'); exit; end if;
    i := i + 1;
    if i > 50 then update app.workflow_runs set cursor = v_key where id = r.id; perform pgmq.send('jobs', jsonb_build_object('job', 'workflow_advance', 'run_id', r.id)); exit; end if;
    v_node := v_flat -> v_key;
    if v_node is null then perform app.wf_finish(r.id, 'failed', 'unknown_step'); exit; end if;
    insert into app.workflow_run_steps (run_id, step_key, kind) values (r.id, v_key, v_node ->> 'kind') returning id into v_step;
    update app.workflow_runs set cursor = v_key where id = r.id;
    select * into r from app.workflow_runs where id = r.id;
    begin
      v_next := app.wf_step(r, w, v_key, v_node, v_step);
    exception when others then
      v_err := sqlerrm;
      update app.workflow_run_steps set state = 'failed', finished_at = now(), error = left(v_err, 300) where id = v_step;
      perform app.wf_finish(r.id, 'failed', v_err);
      exit;
    end;
    exit when v_next is null;           -- waiting
    if (select state from app.workflow_run_steps where id = v_step) = 'not_met' then perform app.wf_finish(r.id, 'completed'); exit; end if;
    v_key := v_next;
  end loop;
  perform set_config('app.acting_as', coalesce(v_prev_actor, ''), true);
  perform set_config('app.run_id', coalesce(v_prev_run, ''), true);
end $fn$;

-- start a run, subject to the safeguards
create function app.wf_start(p_wf uuid, p_subject_type text, p_subject uuid, p_event bigint, p_parent_run uuid, p_enrollment uuid default null)
  returns uuid language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  w app.workflows; v_mode text := app.setting('safeguards'); v_cap_wf numeric; v_cap_all numeric; v_parent app.workflow_runs; v_id uuid; v_blocked boolean := false;
begin
  select * into w from app.workflows where id = p_wf and deleted_at is null;
  if not found or w.current_version = 0 then return null; end if;
  if p_parent_run is not null then select * into v_parent from app.workflow_runs where id = p_parent_run; end if;
  if v_mode <> 'off' then
    if v_parent.workflow_id = p_wf then return null; end if;          -- never trigger yourself
    v_cap_wf := case v_mode when 'custom' then coalesce((select value_number from app.setting_values where key = 'safeguards' and scope_id = ''), 5000) else 5000 end;
    v_cap_all := case v_mode when 'custom' then coalesce((select value_number from app.setting_values where key = 'safeguards' and scope_id = ''), 10000) else 10000 end;
    v_blocked := (select count(*) from app.workflow_runs where workflow_id = p_wf and started_at > now() - interval '10 minutes') >= v_cap_wf
              or (select count(*) from app.workflow_runs where started_at > now() - interval '10 minutes') >= v_cap_all;
  end if;
  if v_blocked then
    if not exists (select 1 from app.workflow_runs where workflow_id = p_wf and state = 'loop_blocked' and started_at > now() - interval '10 minutes') then
      perform app.notify(w.owner_id, 'system', 'workflow.loop_blocked', jsonb_build_object('workflow', w.name), '/automation', w.kind, w.id);
    end if;
    insert into app.workflow_runs (workflow_id, version, event_id, subject_type, subject_id, state, depth, origin_run_id, enrollment_id, error, finished_at, is_sample)
    values (p_wf, w.current_version, p_event, p_subject_type, p_subject, 'loop_blocked', coalesce(v_parent.depth + 1, 0), coalesce(v_parent.origin_run_id, v_parent.id),
            p_enrollment, 'loop_protection', now(), w.is_sample)
    returning id into v_id;
    return v_id;
  end if;
  insert into app.workflow_runs (workflow_id, version, event_id, subject_type, subject_id, depth, origin_run_id, enrollment_id, is_sample)
  values (p_wf, w.current_version, p_event, p_subject_type, p_subject, coalesce(v_parent.depth + 1, 0), coalesce(v_parent.origin_run_id, v_parent.id), p_enrollment, w.is_sample)
  returning id into v_id;
  perform app.wf_advance(v_id);
  return v_id;
end $fn$;

-- is the subject inside the workflow's activation scope («Active for»)?
create function app.wf_in_scope(w app.workflows, p_entity text, p_id uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities; v_owner uuid;
begin
  if w.activation_scope = 'everyone' then return true; end if;
  select * into e from app.entities where key = p_entity;
  if e.key is null or not e.owned then return w.activation_scope = 'everyone'; end if;
  execute format('select t.owner_id from app.%I t where t.id = %L', e.tbl, p_id) into v_owner;
  return case w.activation_scope
    when 'owner' then v_owner = w.owner_id
    when 'users' then exists (select 1 from app.workflow_activation a where a.workflow_id = w.id and a.staff_id = v_owner)
    when 'team' then exists (select 1 from app.workflow_activation a join app.team_members tm on tm.team_id = a.team_id where a.workflow_id = w.id and tm.staff_id = v_owner)
    else true end;
end $fn$;

-- ---------------------------------------------------------------------------
-- sequences
create function app.seq_enroll(p_seq uuid, p_entity text, p_id uuid, p_via text, p_by uuid) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.workflows; v_id uuid; v_run uuid; v_sample boolean;
begin
  select * into w from app.workflows where id = p_seq and kind = 'sequence' and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'sequence'; end if;
  if w.state <> 'active' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sequence_inactive'; end if;
  if p_entity not in ('deal', 'lead') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  if exists (select 1 from app.sequence_enrollments where workflow_id = p_seq and entity = p_entity and record_id = p_id and state = 'in_progress') then return null; end if;
  execute format('select t.is_sample from app.%I t where t.id = %L and t.deleted_at is null', case p_entity when 'deal' then 'deals' else 'leads' end, p_id) into v_sample;
  if v_sample is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.sequence_enrollments (workflow_id, entity, record_id, enrolled_via, enrolled_by, is_sample)
  values (p_seq, p_entity, p_id, p_via, p_by, v_sample) returning id into v_id;
  v_run := app.wf_start(p_seq, p_entity, p_id, null, nullif(current_setting('app.run_id', true), '')::uuid, v_id);
  update app.sequence_enrollments set run_id = v_run where id = v_id;
  if (select state from app.workflow_runs where id = v_run) = 'loop_blocked' then
    update app.sequence_enrollments set state = 'failed', error = 'loop_protection', ended_at = now() where id = v_id;
  end if;
  return v_id;
end $fn$;

create function app.seq_exit(p_enrollment uuid, p_reason text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare en app.sequence_enrollments;
begin
  update app.sequence_enrollments set state = 'exited', exit_reason = p_reason, ended_at = now() where id = p_enrollment and state = 'in_progress' returning * into en;
  if not found then return; end if;
  update app.workflow_runs set state = 'stopped', finished_at = now(), resume_at = null, wait_event = null, wait_ref = null, wait_deadline = null
  where id = en.run_id and state in ('running', 'waiting');
  update app.email_messages set state = 'canceled', failure_code = 'sequence_exited' where enrollment_id = p_enrollment and state in ('scheduled', 'queued', 'awaiting_review');
end $fn$;

-- ---------------------------------------------------------------------------
-- subscribers
-- workflows: resume runs that wait for this event, then start the workflows this event triggers
create function app.sub_workflows(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  r app.workflow_runs; w app.workflows; v_suffix text := split_part(ev.kind, '.', 2); v_parent uuid := nullif(ev.payload ->> '_run', '')::uuid;
  v_fields text[]; v_kind text := case when ev.kind = 'email.received' then 'email.replied' else ev.kind end;
begin
  -- waiting runs
  for r in select * from app.workflow_runs x where x.state = 'waiting' and x.wait_event = v_kind
             and (case when x.wait_event = 'email.sent' then x.wait_ref = ev.payload ->> 'message'
                       else (x.subject_type = ev.subject_type and x.subject_id = ev.subject_id)
                            or coalesce(ev.payload -> 'links', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('entity', x.subject_type, 'id', x.subject_id)) end)
           for update skip locked loop
    update app.workflow_run_steps set state = 'succeeded', finished_at = now() where run_id = r.id and state = 'waiting';
    update app.workflow_runs set state = 'running', wait_event = null, wait_ref = null, wait_deadline = null where id = r.id;
    perform app.wf_advance(r.id);
  end loop;
  -- new runs
  v_fields := array(select jsonb_array_elements_text(coalesce(ev.payload -> 'fields', '[]'::jsonb)));
  for w in select * from app.workflows x where x.state = 'active' and x.deleted_at is null and x.kind in ('workflow', 'lifecycle')
             and x.is_sample = ev.is_sample
             and ((x.trigger_type = 'event' and coalesce(ev.payload ->> 'source', '') <> 'product'
                   and x.trigger_config ->> 'entity' = ev.subject_type and x.trigger_config ->> 'event' = v_suffix)
               or (x.trigger_type = 'product_event' and ev.payload ->> 'source' = 'product' and x.trigger_config ->> 'kind' = ev.kind))
           order by x.created_at loop
    continue when jsonb_typeof(w.trigger_config -> 'fields') = 'array' and jsonb_array_length(w.trigger_config -> 'fields') > 0
                  and not (v_fields && array(select jsonb_array_elements_text(w.trigger_config -> 'fields')));
    -- a product event may carry conditions on its data: {data: {key: value}}
    continue when w.trigger_type = 'product_event' and jsonb_typeof(w.trigger_config -> 'data') = 'object'
                  and not (coalesce(ev.payload -> 'data', '{}'::jsonb) @> (w.trigger_config -> 'data'));
    continue when not app.wf_in_scope(w, ev.subject_type, ev.subject_id);
    continue when ev.subject_id is null or not app.wf_match(ev.subject_type, ev.subject_id, w.trigger_config -> 'groups');
    perform app.wf_start(w.id, ev.subject_type, ev.subject_id, ev.id, v_parent);
  end loop;
end $fn$;

-- assignment: the first rule that matches a new lead, deal or organisation assigns its owner and notifies
-- them. Rules apply to records that did not come from a person in the app (forms, imports, the API, product
-- events, workflows), where the creator is not a meaningful owner.
create function app.sub_assignment(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  w app.workflows; v_facts jsonb; v_to uuid; e app.entities; v_source text; v_old uuid;
begin
  if ev.kind not in ('lead.created', 'deal.created', 'organization.created', 'person.created') then return; end if;
  select c.source into v_source from app.changelog c where c.entity = ev.subject_type and c.record_id = ev.subject_id and c.field = '*created' order by c.id limit 1;
  if coalesce(v_source, 'system') = 'ui' then return; end if;
  v_facts := app.assign_facts(ev.subject_type, ev.subject_id);
  for w in select * from app.workflows x where x.kind = 'assignment' and x.state = 'active' and x.deleted_at is null and x.is_sample = ev.is_sample
             and ev.subject_type in (select jsonb_array_elements_text(coalesce(x.trigger_config -> 'entities', '["lead","deal"]'::jsonb)))
           order by x.priority nulls last, x.created_at loop
    if app.assign_match(coalesce(w.options -> 'condition', '{}'::jsonb), v_facts) then
      v_to := app.assign_pick(w.options -> 'assignee', v_facts, true);
      exit when v_to is null;
      select * into e from app.entities where key = ev.subject_type;
      execute format('select t.owner_id from app.%I t where t.id = %L', e.tbl, ev.subject_id) into v_old;
      execute format('update app.%I set owner_id = %L, version = version + 1, updated_at = now() where id = %L', e.tbl, v_to, ev.subject_id);
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      values (ev.subject_type, ev.subject_id, 'owner_id', to_jsonb(v_old), to_jsonb(v_to), w.owner_id, 'workflow');
      insert into app.assignment_evaluations (workflow_id, entity, record_id, assignee_id) values (w.id, ev.subject_type, ev.subject_id, v_to);
      perform app.notify(v_to, 'system', 'assignment.assigned', jsonb_build_object('workflow', w.name), app.entity_route(ev.subject_type), ev.subject_type, ev.subject_id);
      insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
      values (ev.subject_type || '.updated', ev.subject_type, ev.subject_id, w.owner_id, jsonb_build_object('fields', jsonb_build_array('owner_id'), 'assignment', w.id), ev.is_sample);
      exit;
    end if;
  end loop;
end $fn$;

-- sequences: exit on a reply to a linked thread, a stage change, or a closed or deleted record
create function app.sub_sequences(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare en record; l jsonb;
begin
  if ev.kind = 'email.received' then
    for l in select * from jsonb_array_elements(coalesce(ev.payload -> 'links', '[]'::jsonb)) loop
      for en in select se.id from app.sequence_enrollments se join app.workflows w on w.id = se.workflow_id
                where se.state = 'in_progress' and se.entity = l ->> 'entity' and se.record_id = (l ->> 'id')::uuid
                  and coalesce(w.options -> 'exit_on', '["reply","stage_change"]'::jsonb) ? 'reply' loop
        perform app.seq_exit(en.id, 'reply');
      end loop;
    end loop;
  elsif ev.kind = 'deal.stage_changed' then
    for en in select se.id from app.sequence_enrollments se join app.workflows w on w.id = se.workflow_id
              where se.state = 'in_progress' and se.entity = 'deal' and se.record_id = ev.subject_id
                and coalesce(w.options -> 'exit_on', '["reply","stage_change"]'::jsonb) ? 'stage_change' loop
      perform app.seq_exit(en.id, 'stage_change');
    end loop;
  elsif ev.kind in ('deal.won', 'deal.lost', 'lead.converted') then
    for en in select se.id from app.sequence_enrollments se where se.state = 'in_progress' and se.entity = ev.subject_type and se.record_id = ev.subject_id loop
      perform app.seq_exit(en.id, 'record_closed');
    end loop;
  elsif ev.kind in ('deal.deleted', 'lead.deleted') then
    for en in select se.id from app.sequence_enrollments se where se.state = 'in_progress' and se.entity = ev.subject_type and se.record_id = ev.subject_id loop
      perform app.seq_exit(en.id, 'record_deleted');
    end loop;
  end if;
end $fn$;

insert into app.event_subscribers (name, fn, ord) values ('sequences', 'app.sub_sequences', 10), ('assignment', 'app.sub_assignment', 20), ('workflows', 'app.sub_workflows', 30);
insert into app.event_cursors (subscriber) select name from app.event_subscribers;

-- the dispatcher: every subscriber reads past its cursor, up to 500 events a tick
create function app.dispatch_events() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.event_subscribers; ev app.events; v_last bigint; n int := 0;
begin
  for s in select * from app.event_subscribers where enabled order by ord loop
    select last_event_id into v_last from app.event_cursors where subscriber = s.name for update skip locked;
    continue when not found;
    for ev in select * from app.events where id > v_last order by id limit 500 loop
      begin
        execute format('select %s($1)', s.fn) using ev;
      exception when others then
        insert into app.event_failures (subscriber, event_id, error) values (s.name, ev.id, left(sqlerrm, 500));
      end;
      v_last := ev.id; n := n + 1;
    end loop;
    update app.event_cursors set last_event_id = v_last, updated_at = now() where subscriber = s.name;
  end loop;
  return n;
end $fn$;

-- delays that are over, and waits that have run out
create function app.wf_resume_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.workflow_runs; n int := 0;
begin
  for r in select * from app.workflow_runs where state = 'waiting' and resume_at <= now() order by resume_at limit 500 for update skip locked loop
    update app.workflow_runs set state = 'running', resume_at = null where id = r.id;
    perform app.wf_advance(r.id); n := n + 1;
  end loop;
  for r in select * from app.workflow_runs where state = 'waiting' and wait_deadline <= now() order by wait_deadline limit 500 for update skip locked loop
    update app.workflow_run_steps set state = 'succeeded', finished_at = now(), output = jsonb_build_object('timed_out', true) where run_id = r.id and state = 'waiting';
    if r.wait_then = 'stop' then
      perform app.wf_finish(r.id, 'completed');
    else
      update app.workflow_runs set state = 'running', wait_event = null, wait_ref = null, wait_deadline = null where id = r.id;
      perform app.wf_advance(r.id);
    end if;
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- the next renewal of a confirmed, uncancelled subscription: the next anniversary of its confirmation by
-- its billing interval (a year, else a month)
create function app.sub_renewal(s app.subscriptions) returns timestamptz
  language sql stable set search_path = ''
as $fn$
  select case when s.confirmed_at is null or s.cancelled_at is not null then null
              when s.billing_interval = 'year' then s.confirmed_at + make_interval(years => extract(year from age(now(), s.confirmed_at))::int + 1)
              else s.confirmed_at + make_interval(months => (extract(year from age(now(), s.confirmed_at)) * 12 + extract(month from age(now(), s.confirmed_at)))::int + 1) end
$fn$;

-- date triggers (AUT-03): a record whose date, offset by N days, is today starts the workflow once.
-- Dates: a date or timestamptz column of the record, or the derived «rots_at» of a deal (entered the
-- stage + the stage's threshold) and «renewal_at» of an organisation (the subscription's next renewal).
create function app.wf_dates() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare w app.workflows; e app.entities; v_expr text; v_off int; v_ids uuid[]; v_id uuid; n int := 0;
begin
  for w in select * from app.workflows where state = 'active' and deleted_at is null and trigger_type = 'date' and kind in ('workflow', 'lifecycle') loop
    select * into e from app.entities where key = w.trigger_config ->> 'entity';
    continue when e.key is null;
    v_off := coalesce((w.trigger_config ->> 'offset_days')::int, 0);
    v_expr := case
      when e.key = 'deal' and w.trigger_config ->> 'date' = 'rots_at' then '(t.stage_entered_at + make_interval(days => (select s.rot_days from app.stages s where s.id = t.stage_id)))::date'
      when e.key = 'organization' and w.trigger_config ->> 'date' = 'renewal_at' then
        '(select min(app.sub_renewal(s))::date from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id where ap.account_id = t.account_id)'
      when exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = w.trigger_config ->> 'date' and c.kind in ('date', 'timestamptz'))
        then format('(t.%I)::date', w.trigger_config ->> 'date')
      end;
    continue when v_expr is null;
    execute format('select array_agg(t.id) from app.%I t where t.deleted_at is null and t.is_sample = %L and %s + %s = current_date',
                   e.tbl, w.is_sample, v_expr, v_off) into v_ids;
    foreach v_id in array coalesce(v_ids, '{}') loop
      continue when exists (select 1 from app.workflow_runs x where x.workflow_id = w.id and x.subject_id = v_id and x.started_at::date = current_date);
      continue when not app.wf_in_scope(w, e.key, v_id) or not app.wf_match(e.key, v_id, w.trigger_config -> 'groups');
      perform app.wf_start(w.id, e.key, v_id, null, null); n := n + 1;
    end loop;
  end loop;
  return n;
end $fn$;

select cron.schedule('platform-dispatch', '* * * * *', 'select app.dispatch_events()');
select cron.schedule('platform-workflow-resume', '* * * * *', 'select app.wf_resume_due()');
select cron.schedule('platform-workflow-dates', '7 * * * *', 'select app.wf_dates()');

-- ---------------------------------------------------------------------------
-- templates (eight, in four groups). Names and descriptions are message keys in the app.
insert into app.workflow_templates (key, group_key, kind, trigger_type, trigger_config, graph, ord) values
  ('no_reply_task', 'follow_up', 'workflow', 'event', '{"entity":"deal","event":"no_reply"}',
   '{"steps":[{"key":"s1","kind":"create_activity","config":{"type":"task","subject":"Follow up: no reply to {deal.title}","due_in_days":0,"owner":"@record_owner"}}]}', 10),
  ('trial_nurture', 'follow_up', 'lifecycle', 'product_event', '{"kind":"org.created"}',
   '{"steps":[{"key":"s1","kind":"delay","config":{"amount":2,"unit":"days","skip_weekends":true}},{"key":"s2","kind":"notify","config":{"to":"@record_owner","message":"Trial started two business days ago for {organization.name}"}}]}', 20),
  ('rotting_alert', 'hygiene', 'workflow', 'date', '{"entity":"deal","date":"rots_at","offset_days":2,"groups":[[{"f":"status","op":"eq","v":"open"}]]}',
   '{"steps":[{"key":"s1","kind":"notify","config":{"to":"@record_owner","message":"{deal.title} has passed its stage threshold"}}]}', 30),
  ('close_date_passed', 'hygiene', 'workflow', 'date', '{"entity":"deal","date":"expected_close_date","offset_days":1,"groups":[[{"f":"status","op":"eq","v":"open"}]]}',
   '{"steps":[{"key":"s1","kind":"create_activity","config":{"type":"task","subject":"Move the close date or close {deal.title}","due_in_days":0,"owner":"@record_owner"}}]}', 40),
  ('won_project', 'handover', 'workflow', 'event', '{"entity":"deal","event":"won"}',
   '{"steps":[{"key":"s1","kind":"project_action","config":{"action":"create_from_template"}}]}', 50),
  ('won_invoice', 'handover', 'workflow', 'event', '{"entity":"deal","event":"won"}',
   '{"steps":[{"key":"s1","kind":"accounting_invoice","config":{}}]}', 60),
  ('health_drop', 'health', 'workflow', 'event', '{"entity":"organization","event":"health_dropped"}',
   '{"steps":[{"key":"s1","kind":"create_activity","config":{"type":"task","subject":"Health dropped: {organization.name}","due_in_days":0,"owner":"@record_owner"}},{"key":"s2","kind":"create_ticket","config":{"category_key":"getting_started","subject":"Health dropped: {organization.name}"}}]}', 70),
  ('payment_failed', 'health', 'workflow', 'product_event', '{"kind":"billing.changed","data":{"payment_state":"past_due"}}',
   '{"steps":[{"key":"s1","kind":"create_ticket","config":{"category_key":"billing","subject":"Payment failed: {organization.name}"}}]}', 80);

-- ---------------------------------------------------------------------------
-- the scope a workflow belongs to: that of the record type it runs on (Manage workflows is per scope)
create function app.wf_scope(w app.workflows) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select e.scope from app.entities e where e.key = case when w.trigger_type in ('event', 'date') then w.trigger_config ->> 'entity' else 'deal' end), 'deals')
$fn$;

-- the Automation screen
create function app.wf_row(w app.workflows) returns jsonb
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
    'mine', w.owner_id = app.me())
$fn$;

-- filter: {kind, mine: true|false|null}
create function public.workflows_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_kind text := coalesce(p_filter ->> 'kind', 'workflow');
begin
  return coalesce((select jsonb_agg(app.wf_row(w) order by w.priority nulls last, w.created_at)
                   from app.workflows w where w.deleted_at is null
                     and (w.kind = v_kind or (v_kind = 'workflow' and w.kind = 'lifecycle'))
                     and ((p_filter ->> 'mine') is null or (w.owner_id = v_me) = (p_filter ->> 'mine')::boolean)), '[]'::jsonb);
end $fn$;

create function public.workflow_get(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare w app.workflows;
begin
  perform app.require_staff();
  select * into w from app.workflows where id = p_id and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return app.wf_row(w) || jsonb_build_object('options', w.options, 'priority', w.priority, 'current_version', w.current_version,
    'graph', (select v.graph from app.workflow_versions v where v.workflow_id = w.id and v.version = w.current_version),
    'versions', (select count(*) from app.workflow_versions v where v.workflow_id = w.id));
end $fn$;

-- create or update. values: name, description, kind (create only), trigger_type, trigger_config, options,
-- activation_scope, activation [{staff_id}|{team_id}]. A changed graph publishes a new version.
create function public.workflow_save(p_id uuid, p_values jsonb, p_graph jsonb default null, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff(); w app.workflows; v_id uuid := p_id; v_kind text; v_tt text; v_tc jsonb; v_ent text; v_graph jsonb; v_new int;
begin
  if p_id is not null then
    select * into w from app.workflows where id = p_id and deleted_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and w.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = w.version::text; end if;
    if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  end if;
  v_kind := coalesce(w.kind, p_values ->> 'kind', 'workflow');
  if v_kind not in ('workflow', 'sequence', 'lifecycle', 'assignment') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if jsonb_typeof(coalesce(p_values -> 'trigger_config', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(p_values -> 'options', '{}'::jsonb)) <> 'object' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger_config';
  end if;
  v_tt := coalesce(p_values ->> 'trigger_type', w.trigger_type, case v_kind when 'sequence' then 'enrollment' else 'event' end);
  v_tc := coalesce(p_values -> 'trigger_config', w.trigger_config, '{}'::jsonb);
  if v_kind = 'sequence' and v_tt <> 'enrollment' or v_kind <> 'sequence' and v_tt = 'enrollment' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger_type';
  end if;
  if v_tt not in ('event', 'date', 'product_event', 'enrollment') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger_type'; end if;
  if v_kind <> 'assignment' and v_tt in ('event', 'date') and not exists (select 1 from app.entities e where e.key = v_tc ->> 'entity' and e.key in ('deal', 'lead', 'person', 'organization', 'activity', 'ticket')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger_config.entity';
  end if;
  if v_tt = 'product_event' and coalesce(v_tc ->> 'kind', '') !~ '^[a-z_]+\.[a-z_]+$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'trigger_config.kind';
  end if;
  v_ent := case when v_tt in ('event', 'date') then v_tc ->> 'entity' when v_tt = 'product_event' then 'organization' else 'deal' end;
  perform app.require(coalesce((select e.scope from app.entities e where e.key = case when v_tt in ('event', 'date') then v_ent else 'deal' end), 'deals'), 'workflows');
  if v_kind = 'assignment' then
    if jsonb_typeof(coalesce(p_values -> 'options', w.options) -> 'assignee') <> 'object'
       or coalesce(p_values -> 'options', w.options) -> 'assignee' ->> 'kind' not in ('user', 'team_rr', 'org_owner', 'person_owner') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'options.assignee';
    end if;
  end if;
  if p_values ? 'activation_scope' and p_values ->> 'activation_scope' not in ('owner', 'users', 'team', 'everyone') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'activation_scope';
  end if;
  if p_id is null then
    insert into app.workflows (kind, name, description, owner_id, trigger_type, trigger_config, options, activation_scope, priority, template_key, created_by, updated_by, is_sample)
    values (v_kind, btrim(p_values ->> 'name'), nullif(btrim(p_values ->> 'description'), ''), v_me, v_tt, v_tc, coalesce(p_values -> 'options', '{}'::jsonb),
            coalesce(p_values ->> 'activation_scope', 'everyone'),
            case when v_kind = 'assignment' then coalesce((select max(priority) from app.workflows where kind = 'assignment' and deleted_at is null), 0) + 1 end,
            p_values ->> 'template_key', v_me, v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.workflows set name = coalesce(btrim(p_values ->> 'name'), name),
      description = case when p_values ? 'description' then nullif(btrim(p_values ->> 'description'), '') else description end,
      trigger_type = v_tt, trigger_config = v_tc, options = coalesce(p_values -> 'options', options),
      activation_scope = coalesce(p_values ->> 'activation_scope', activation_scope), version = version + 1, updated_at = now(), updated_by = v_me
    where id = p_id;
  end if;
  if p_values ? 'activation' then
    delete from app.workflow_activation where workflow_id = v_id;
    insert into app.workflow_activation (workflow_id, staff_id, team_id)
    select v_id, (x ->> 'staff_id')::uuid, (x ->> 'team_id')::uuid from jsonb_array_elements(p_values -> 'activation') x;
  end if;
  v_graph := coalesce(p_graph, case when v_kind = 'assignment' then '{"steps":[]}'::jsonb end);
  if v_graph is not null and v_graph is distinct from (select v.graph from app.workflow_versions v join app.workflows x on x.id = v.workflow_id and v.version = x.current_version where x.id = v_id) then
    perform app.wf_validate(v_kind, v_graph, v_ent);
    v_new := coalesce((select max(version) from app.workflow_versions where workflow_id = v_id), 0) + 1;
    insert into app.workflow_versions (workflow_id, version, graph, flat, published_by)
    values (v_id, v_new, v_graph, app.wf_flatten(v_graph -> 'steps', null) || jsonb_build_object('_start', v_graph -> 'steps' -> 0 ->> 'key'), v_me);
    update app.workflows set current_version = v_new where id = v_id;
  end if;
  perform app.log(case when p_id is null then 'workflow.created' else 'workflow.updated' end, 'workflow', v_id::text,
                  jsonb_build_object('kind', v_kind, 'graph_changed', v_new is not null));
  return jsonb_build_object('id', v_id, 'version', (select version from app.workflows where id = v_id), 'graph_version', (select current_version from app.workflows where id = v_id));
end $fn$;

-- activate or deactivate (UF-11): activation is refused, with the reason, when a step cannot run or a limit is reached
create function public.workflow_set_state(p_id uuid, p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); w app.workflows; v_block text[]; v_limit numeric := app.count_limit();
begin
  select * into w from app.workflows where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.require(app.wf_scope(w), 'workflows');
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  if p_state not in ('draft', 'active') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if p_state = 'active' and w.state <> 'active' then
    if w.current_version = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.steps'; end if;
    v_block := app.wf_blockers(p_id);
    if cardinality(v_block) > 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_block[1]; end if;
    if v_limit is not null and (select count(*) from app.workflows where state = 'active' and deleted_at is null and kind = w.kind) >= v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'limit';
    end if;
  end if;
  update app.workflows set state = p_state, activated_at = case when p_state = 'active' then now() else activated_at end, version = version + 1, updated_at = now(), updated_by = v_me
  where id = p_id;
  perform app.log(case when p_state = 'active' then 'workflow.activated' else 'workflow.deactivated' end, 'workflow', p_id::text, null);
  return jsonb_build_object('id', p_id, 'state', p_state);
end $fn$;

-- transfer ownership (AUT-10): both people are notified; the change is audited
create function public.workflow_transfer(p_id uuid, p_to uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); w app.workflows;
begin
  select * into w from app.workflows where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.require(app.wf_scope(w), 'workflows');
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  if not exists (select 1 from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id
                 where a.id = p_to and a.active and (ps.kind = 'admin' or (app.wf_scope(w) || ':workflows') = any (ps.rights))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner';
  end if;
  update app.workflows set owner_id = p_to, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  perform app.notify(p_to, 'system', 'workflow.transferred_to', jsonb_build_object('workflow', w.name), '/automation', w.kind, w.id);
  if w.owner_id <> v_me then
    perform app.notify(w.owner_id, 'system', 'workflow.transferred_from', jsonb_build_object('workflow', w.name), '/automation', w.kind, w.id);
  end if;
  perform app.log('workflow.transferred', 'workflow', p_id::text, jsonb_build_object('from', w.owner_id, 'to', p_to));
  return jsonb_build_object('id', p_id, 'owner_id', p_to);
end $fn$;

create function public.workflow_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); w app.workflows;
begin
  select * into w from app.workflows where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.require(app.wf_scope(w), 'workflows');
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  update app.workflows set deleted_at = now(), state = 'draft' where id = p_id;
  update app.workflow_runs set state = 'stopped', finished_at = now() where workflow_id = p_id and state in ('running', 'waiting');
  perform app.log('workflow.deleted', 'workflow', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

create function public.workflow_templates_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'group', t.group_key, 'kind', t.kind, 'trigger_type', t.trigger_type)
                                    order by t.ord) from app.workflow_templates t), '[]'::jsonb);
end $fn$;

-- «Use template →»: a draft from the template's graph
create function public.workflow_from_template(p_key text, p_name text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare t app.workflow_templates;
begin
  select * into t from app.workflow_templates where key = p_key;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return public.workflow_save(null, jsonb_build_object('name', p_name, 'kind', t.kind, 'trigger_type', t.trigger_type, 'trigger_config', t.trigger_config, 'template_key', t.key),
                              t.graph);
end $fn$;

-- the monitoring view: health, most failed, most active, never run, loop protection
create function public.workflow_monitor() returns jsonb
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

-- run history: newest first, with step chips. filter: {workflow_id, state, limit}
create function public.workflow_runs_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_limit int := least(greatest(coalesce((p_filter ->> 'limit')::int, 50), 1), 200);
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(x order by (x ->> 'started_at') desc) from (
    select jsonb_build_object('id', r.id, 'workflow_id', r.workflow_id, 'workflow', w.name, 'state', r.state, 'error', r.error,
      'started_at', r.started_at, 'finished_at', r.finished_at, 'retry_of', r.retry_of,
      'subject_type', r.subject_type, 'subject_id', r.subject_id,
      'retried', exists (select 1 from app.workflow_runs x where x.retry_of = r.id),
      'steps', coalesce((select jsonb_agg(jsonb_build_object('key', s.step_key, 'kind', s.kind, 'state', s.state, 'error', s.error, 'status', s.response_status) order by s.started_at)
                         from app.workflow_run_steps s where s.run_id = r.id), '[]'::jsonb)) x
    from app.workflow_runs r join app.workflows w on w.id = r.workflow_id
    where w.deleted_at is null and ((p_filter ->> 'workflow_id') is null or r.workflow_id = (p_filter ->> 'workflow_id')::uuid)
      and ((p_filter ->> 'state') is null or r.state = p_filter ->> 'state')
    order by r.started_at desc limit v_limit) s), '[]'::jsonb);
end $fn$;

-- retry a failed run: a new attempt resumes from the step that failed, on the same version
create function public.workflow_run_retry(p_run uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r app.workflow_runs; v_id uuid; v_key text;
begin
  select * into r from app.workflow_runs where id = p_run;
  if not found or r.state <> 'failed' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  perform app.require(app.wf_scope((select w from app.workflows w where w.id = r.workflow_id)), 'workflows');
  if exists (select 1 from app.workflow_runs x where x.retry_of = p_run) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'retried'; end if;
  v_key := (select s.step_key from app.workflow_run_steps s where s.run_id = p_run and s.state = 'failed' order by s.started_at desc limit 1);
  insert into app.workflow_runs (workflow_id, version, event_id, subject_type, subject_id, cursor, depth, origin_run_id, retry_of, enrollment_id, is_sample)
  values (r.workflow_id, r.version, r.event_id, r.subject_type, r.subject_id, v_key, r.depth, r.origin_run_id, r.id, r.enrollment_id, r.is_sample)
  returning id into v_id;
  if r.enrollment_id is not null then
    update app.sequence_enrollments set state = 'in_progress', error = null, ended_at = null, run_id = v_id where id = r.enrollment_id and state = 'failed';
  end if;
  perform app.log('workflow.run_retried', 'workflow', r.workflow_id::text, jsonb_build_object('run', p_run));
  perform app.wf_advance(v_id);
  return jsonb_build_object('id', v_id, 'state', (select state from app.workflow_runs where id = v_id));
end $fn$;

create function public.integrations_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('provider', c.provider, 'status', c.status, 'connected_at', c.connected_at) order by c.provider)
                   from app.integration_connections c), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- assignment rules
create function public.assignment_rules_reorder(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'workflows'); i int;
begin
  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update app.workflows set priority = i, updated_at = now(), updated_by = v_me where id = p_ids[i] and kind = 'assignment' and deleted_at is null;
  end loop;
  perform app.log('assignment.reordered', 'workflow', null, jsonb_build_object('count', cardinality(p_ids)));
  return jsonb_build_object('ok', true);
end $fn$;

-- «Test a record»: read-only. input: {entity, record_id} or {entity, source, employees, org_exists, org_labels}
create function public.assignment_test(p_input jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_facts jsonb; w app.workflows; v_to uuid; e app.entities; v_ok boolean; v_team uuid; v_last uuid;
begin
  perform app.require_staff();
  if p_input ? 'record_id' then
    e := app.entity(p_input ->> 'entity');
    execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, (p_input ->> 'record_id')::uuid, app.vis_sql(e)) into v_ok;
    if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    v_facts := app.assign_facts(e.key, (p_input ->> 'record_id')::uuid);
  else
    v_facts := jsonb_build_object('entity', coalesce(p_input ->> 'entity', 'lead'), 'source', p_input ->> 'source',
                                  'employees', (p_input ->> 'employees')::int, 'org_exists', coalesce((p_input ->> 'org_exists')::boolean, false),
                                  'org_labels', coalesce(p_input -> 'org_labels', '[]'::jsonb));
  end if;
  for w in select * from app.workflows x where x.kind = 'assignment' and x.state = 'active' and x.deleted_at is null
             and v_facts ->> 'entity' in (select jsonb_array_elements_text(coalesce(x.trigger_config -> 'entities', '["lead","deal"]'::jsonb)))
           order by x.priority nulls last, x.created_at loop
    if app.assign_match(coalesce(w.options -> 'condition', '{}'::jsonb), v_facts) then
      if w.options -> 'assignee' ->> 'kind' = 'team_rr' then
        v_team := (w.options -> 'assignee' ->> 'team_id')::uuid;
        v_last := (select last_staff_id from app.assignment_rotation where team_id = v_team);
        v_to := coalesce((select a.id from app.team_members tm join app.admins a on a.id = tm.staff_id where tm.team_id = v_team and a.active and (v_last is null or a.id > v_last) order by a.id limit 1),
                         (select a.id from app.team_members tm join app.admins a on a.id = tm.staff_id where tm.team_id = v_team and a.active order by a.id limit 1));
      else
        v_to := app.assign_pick(w.options -> 'assignee', v_facts, false);
      end if;
      return jsonb_build_object('rule_id', w.id, 'rule', w.name, 'assignee_kind', w.options -> 'assignee' ->> 'kind',
                                'assignee_id', v_to, 'assignee', (select a.name from app.admins a where a.id = v_to));
    end if;
  end loop;
  return jsonb_build_object('rule_id', null);
end $fn$;

create function public.assignment_history(p_entity text default null, p_record uuid default null, p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('at', ev.at, 'rule', w.name, 'entity', ev.entity, 'record_id', ev.record_id, 'assignee', a.name) x
    from app.assignment_evaluations ev left join app.workflows w on w.id = ev.workflow_id left join app.admins a on a.id = ev.assignee_id
    where (p_entity is null or ev.entity = p_entity) and (p_record is null or ev.record_id = p_record)
    order by ev.at desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) s), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- sequences
create function public.sequence_get(p_id uuid) returns jsonb
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
        'created_at', se.created_at) x
      from app.sequence_enrollments se where se.workflow_id = p_id
        and case se.entity when 'deal' then exists (select 1 from app.deals d where d.id = se.record_id and app.visible(d.owner_id, d.visibility))
                           else exists (select 1 from app.leads l where l.id = se.record_id and app.visible(l.owner_id, l.visibility)) end
      order by se.created_at desc limit 200) s), '[]'::jsonb));
end $fn$;

-- enrol records one by one, in bulk (ids) or from a saved view
create function public.sequence_enroll(p_id uuid, p_entity text, p_ids uuid[] default null, p_view uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_ids uuid[] := coalesce(p_ids, '{}'); e app.entities; v_q jsonb; x uuid; n int := 0; v_ok boolean; v_en uuid;
begin
  e := app.entity(p_entity);
  if p_view is not null then
    select sv.query into v_q from app.saved_views sv where sv.id = p_view and (sv.shared or sv.owner_id = v_me);
    if v_q is null then raise exception 'not_found' using errcode = 'no_data_found', detail = 'view'; end if;
    execute format('select array_agg(t.id) from app.%I t where t.deleted_at is null and %s %s', e.tbl, app.vis_sql(e), app.filter_sql(e, v_q -> 'filters')) into v_ids;
    v_ids := coalesce(v_ids, '{}');
  end if;
  if cardinality(v_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  if cardinality(v_ids) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  foreach x in array v_ids loop
    execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, x, app.vis_sql(e)) into v_ok;
    continue when v_ok is null;
    v_en := app.seq_enroll(p_id, p_entity, x, case when cardinality(v_ids) > 1 then 'bulk' else 'one' end, v_me);
    if v_en is not null then n := n + 1; end if;
  end loop;
  perform app.log('sequence.enrolled', 'workflow', p_id::text, jsonb_build_object('count', n));
  return jsonb_build_object('enrolled', n, 'skipped', cardinality(v_ids) - n);
end $fn$;

create function public.sequence_exit(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); x uuid; n int := 0;
begin
  if cardinality(p_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  foreach x in array coalesce(p_ids, '{}') loop
    if exists (select 1 from app.sequence_enrollments se where se.id = x and se.state = 'in_progress'
               and (se.enrolled_by = v_me or app.can('deals', 'edit_others'))) then
      perform app.seq_exit(x, 'manual'); n := n + 1;
    end if;
  end loop;
  perform app.log('sequence.exited', 'sequence_enrollment', null, jsonb_build_object('count', n));
  return jsonb_build_object('exited', n);
end $fn$;

-- skip the step an enrolment waits on (a delay, or a manual email in review)
create function public.sequence_skip_step(p_enrollment uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); en app.sequence_enrollments; r app.workflow_runs;
begin
  select * into en from app.sequence_enrollments where id = p_enrollment and state = 'in_progress';
  if not found or (en.enrolled_by is distinct from v_me and not app.can('deals', 'edit_others')) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into r from app.workflow_runs where id = en.run_id for update;
  if r.state <> 'waiting' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.workflow_run_steps set state = 'skipped', finished_at = now() where run_id = r.id and state in ('waiting', 'running');
  update app.email_messages set state = 'canceled', failure_code = 'skipped' where enrollment_id = p_enrollment and state = 'awaiting_review';
  update app.workflow_runs set state = 'running', resume_at = null, wait_event = null, wait_ref = null, wait_deadline = null where id = r.id;
  update app.sequence_enrollments set current_ord = current_ord + 1 where id = p_enrollment;
  perform app.log('sequence.step_skipped', 'sequence_enrollment', p_enrollment::text, null);
  perform app.wf_advance(r.id);
  return jsonb_build_object('id', p_enrollment);
end $fn$;

-- ---------------------------------------------------------------------------
-- worker functions (service role): an external step's request and its result
create function public.worker_step_get(p_step uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.workflow_run_steps;
begin
  select * into s from app.workflow_run_steps where id = p_step and state = 'queued';
  if not found then return null; end if;
  return jsonb_build_object('id', s.id, 'kind', s.kind, 'request', s.request,
    'secret_id', case when s.kind in ('slack', 'teams', 'accounting_invoice') then (select c.vault_secret_id from app.integration_connections c
                                                                                    where c.provider = case s.kind when 'accounting_invoice' then 'accounting' else s.kind end) end);
end $fn$;

create function public.worker_step_done(p_step uuid, p_ok boolean, p_status int, p_error text, p_request jsonb default null) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.workflow_run_steps; r app.workflow_runs;
begin
  update app.workflow_run_steps set state = case when p_ok then 'succeeded' else 'failed' end, finished_at = now(), response_status = p_status,
    error = case when p_ok then null else left(coalesce(p_error, 'failed'), 300) end, request = coalesce(p_request, request)
  where id = p_step and state = 'queued' returning * into s;
  if not found then return; end if;
  select * into r from app.workflow_runs where id = s.run_id for update;
  if r.state <> 'waiting' or r.wait_ref is distinct from p_step::text then return; end if;
  if p_ok then
    update app.workflow_runs set state = 'running', wait_event = null, wait_ref = null where id = r.id;
    perform app.wf_advance(r.id);
  else
    perform app.wf_finish(r.id, 'failed', coalesce(p_error, 'failed'));
  end if;
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['event_subscribers', 'event_cursors', 'event_failures', 'workflows', 'workflow_versions', 'workflow_activation', 'workflow_runs',
                           'workflow_run_steps', 'workflow_templates', 'sequence_enrollments', 'assignment_rotation', 'assignment_evaluations', 'integration_connections'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.product_event_out()', 'app.wf_flatten(jsonb, text)', 'app.wf_path_counts(jsonb)', 'app.count_limit()', 'app.url_public(text)',
                           'app.wf_kinds(text)', 'app.wf_validate(text, jsonb, text)', 'app.wf_blockers(uuid)', 'app.wf_match(text, uuid, jsonb)',
                           'app.wf_value(jsonb, text, uuid, uuid)', 'app.wf_render(text, text, uuid, boolean)', 'app.wf_delay_until(timestamptz, numeric, text, boolean)',
                           'app.assign_facts(text, uuid)', 'app.assign_match(jsonb, jsonb)', 'app.assign_pick(jsonb, jsonb, boolean)', 'app.wf_finish(uuid, text, text)',
                           'app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)', 'app.wf_advance(uuid)', 'app.wf_start(uuid, text, uuid, bigint, uuid, uuid)',
                           'app.wf_in_scope(app.workflows, text, uuid)', 'app.seq_enroll(uuid, text, uuid, text, uuid)', 'app.seq_exit(uuid, text)',
                           'app.sub_workflows(app.events)', 'app.sub_assignment(app.events)', 'app.sub_sequences(app.events)', 'app.dispatch_events()',
                           'app.wf_resume_due()', 'app.sub_renewal(app.subscriptions)', 'app.wf_dates()', 'app.wf_row(app.workflows)', 'app.wf_scope(app.workflows)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.workflows_get(jsonb)', 'public.workflow_get(uuid)', 'public.workflow_save(uuid, jsonb, jsonb, int)', 'public.workflow_set_state(uuid, text)',
                           'public.workflow_transfer(uuid, uuid)', 'public.workflow_delete(uuid)', 'public.workflow_templates_get()', 'public.workflow_from_template(text, text)',
                           'public.workflow_monitor()', 'public.workflow_runs_get(jsonb)', 'public.workflow_run_retry(uuid)', 'public.integrations_get()',
                           'public.assignment_rules_reorder(uuid[])', 'public.assignment_test(jsonb)', 'public.assignment_history(text, uuid, int)',
                           'public.sequence_get(uuid)', 'public.sequence_enroll(uuid, text, uuid[], uuid)', 'public.sequence_exit(uuid[])', 'public.sequence_skip_step(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_step_get(uuid)', 'public.worker_step_done(uuid, boolean, int, text, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
