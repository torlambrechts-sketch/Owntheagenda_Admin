-- 0038_projects.sql — Projects (Phase 6): boards and phases, projects with their deals, work items with subtasks,
-- assignees and dependencies, templates, the phase history, AI summaries and status reports as requests to a worker,
-- and the generic record files (CRM-05). Spec: docs/crm-enrichment/specs/projects-meetings.md §1, §3.1, §4–§10;
-- design: design-reference/sentral/project/Projects.dc.html. Departures: docs/crm-enrichment/deviations/projects-schema.md.
--
-- A project is a record type (app.entities 'project', scope «projects», module «projects»): custom fields, labels,
-- notes, followers, mail links, saved views, recents, ⌘K search, the changelog, soft delete and purge, the
-- visibility default and date triggers all work through the generic paths. Its phase, health and status move only
-- through their own functions (as deal_move / deal_status do), which keep the phase history and emit the events
-- workflows start on. Work items are not a record type: app.vis_sql returns true for an unowned type, so the generic
-- rec_get would show items of a project the caller may not see. Their changes are written into the project's history
-- (field «items.<item>.<column>»), and they are read only through the project.
--
-- Nothing on the board, the timeline or the reports is stored as a figure: progress, lateness, the bars, the counts
-- per health and the median days per phase are computed from rows when read. A project's health starts unset; nobody
-- has judged it yet (spec Q1).
--
-- Not here, on purpose: the executor's project_action, the INS-01 report type and the 0037 campaign functions. 0037 is
-- written in parallel and redefines app.wf_step, app.wf_blockers, app.wf_validate and the report builder; this
-- migration ships the project side of each as functions of its own (app.wf_project_action, app.wf_project_validate,
-- app.wf_project_blocker) for the merge to call (V-P6P-01, V-P6P-02).

-- ---------------------------------------------------------------------------
-- boards and phases (Settings for «projects:configure»)
create table app.project_boards (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 80),
  ord         int not null default 0,
  archived_at timestamptz,
  is_sample   boolean not null default false,
  created_at  timestamptz not null default now(),
  created_by  uuid
);
create unique index project_boards_name on app.project_boards (lower(name)) where archived_at is null;

create table app.project_phases (
  id         uuid primary key default gen_random_uuid(),
  board_id   uuid not null references app.project_boards (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  ord        int not null default 0,
  color      text not null default '#F2EAD6' check (color ~ '^#[0-9A-F]{6}$'),
  created_at timestamptz not null default now(),
  unique (board_id, name)
);
create index project_phases_board on app.project_phases (board_id, ord);

-- ---------------------------------------------------------------------------
-- templates: groups, items with day offsets, activities at a time of day, dependencies. The creator owns a template
-- (spec Q7: «projects:add» saves one's own, «projects:configure» changes anybody's).
create table app.project_templates (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(btrim(name)) between 1 and 120),
  description       text check (description is null or char_length(description) <= 500),
  organized_by      text not null default 'phases' check (organized_by in ('phases', 'groups')),
  board_id          uuid references app.project_boards (id) on delete set null,
  source_project_id uuid,                                            -- references app.projects, below
  is_sample         boolean not null default false,
  version           int not null default 1,
  created_at        timestamptz not null default now(),
  created_by        uuid references app.admins (id) on delete set null,
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  deleted_at        timestamptz
);
create unique index project_templates_name on app.project_templates (lower(name)) where deleted_at is null;

create table app.project_template_groups (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references app.project_templates (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 80),
  ord         int not null default 0,
  phase_id    uuid references app.project_phases (id) on delete set null
);

create table app.project_template_items (
  id                      uuid primary key default gen_random_uuid(),
  template_id             uuid not null references app.project_templates (id) on delete cascade,
  group_id                uuid references app.project_template_groups (id) on delete set null,
  parent_id               uuid references app.project_template_items (id) on delete cascade,
  kind                    text not null check (kind in ('task', 'milestone', 'activity')),
  name                    text not null check (char_length(btrim(name)) between 1 and 300),
  start_offset_days       int check (start_offset_days between 0 and 3650),
  due_offset_days         int check (due_offset_days between 0 and 3650),
  activity_type_id        uuid references app.activity_types (id),
  activity_time           time,
  activity_duration_min   int check (activity_duration_min between 0 and 1440),
  assignee                text not null default 'unassigned' check (assignee in ('owner', 'unassigned')),
  completes_with_subtasks boolean not null default false,
  ord                     int not null default 0,
  check (due_offset_days is null or start_offset_days is null or due_offset_days >= start_offset_days),
  check ((kind = 'activity') = (activity_type_id is not null and activity_time is not null)),
  check (kind <> 'milestone' or start_offset_days is null),
  check (parent_id is null or kind = 'task'),
  check (parent_id is distinct from id)
);
create index project_template_items_template on app.project_template_items (template_id, ord);

create table app.project_template_dependencies (
  template_id    uuid not null references app.project_templates (id) on delete cascade,
  predecessor_id uuid not null references app.project_template_items (id) on delete cascade,
  successor_id   uuid not null references app.project_template_items (id) on delete cascade,
  lag_days       int not null default 0 check (lag_days between -365 and 365),
  primary key (predecessor_id, successor_id),
  check (predecessor_id <> successor_id)
);

-- ---------------------------------------------------------------------------
-- projects
create table app.projects (
  id               uuid primary key default gen_random_uuid(),
  seq              bigint generated always as identity unique,             -- «P-8» where a reference is needed (spec Q21)
  name             text not null check (char_length(btrim(name)) between 1 and 200),
  board_id         uuid not null references app.project_boards (id),
  phase_id         uuid not null references app.project_phases (id),
  phase_entered_at timestamptz not null default now(),
  status           text not null default 'open' check (status in ('open', 'done', 'canceled')),
  closed_at        timestamptz,
  closed_by        uuid references app.admins (id) on delete set null,
  health           text check (health in ('on_track', 'at_risk', 'off_track', 'on_hold')),
  health_set_at    timestamptz,
  health_set_by    uuid references app.admins (id) on delete set null,
  health_source    text check (health_source in ('manual', 'ai_suggestion')),
  starts_on        date,
  ends_on          date,
  description      text check (description is null or char_length(description) <= 20000),
  brief_state      text not null default 'none' check (brief_state in ('none', 'drafting', 'draft', 'reviewed', 'failed')),
  person_id        uuid references app.people (id) on delete set null,
  organization_id  uuid references app.organizations (id) on delete set null,
  template_id      uuid references app.project_templates (id) on delete set null,
  created_source   text not null default 'ui' check (created_source in ('ui', 'deal', 'workflow', 'import', 'api')),
  owner_id         uuid references app.admins (id) on delete set null,
  visibility       text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels           uuid[] not null default '{}',
  custom           jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample        boolean not null default false,
  version          int not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  deleted_at       timestamptz,
  check (ends_on is null or starts_on is null or ends_on >= starts_on),
  check ((status = 'open') = (closed_at is null)),
  check ((health is null) = (health_source is null))
);
create index projects_board on app.projects (board_id, phase_id) where deleted_at is null;
create index projects_org on app.projects (organization_id);
create index projects_person on app.projects (person_id);
alter table app.project_templates add constraint project_templates_source foreign key (source_project_id) references app.projects (id) on delete set null;

create table app.project_deals (
  project_id uuid not null references app.projects (id) on delete cascade,
  deal_id    uuid not null references app.deals (id) on delete cascade,
  is_primary boolean not null default false,
  linked_by  uuid references app.admins (id) on delete set null,
  linked_at  timestamptz not null default now(),
  primary key (project_id, deal_id)
);
create unique index project_deals_one_primary on app.project_deals (project_id) where is_primary;
create index project_deals_deal on app.project_deals (deal_id);

-- the phase history: one row per stay in a phase. Content is fixed; left_at is set once; a deleted phase empties
-- phase_id (FK maintenance); a row goes only with its project (purge, sandbox).
create table app.project_phase_history (
  id         bigint generated always as identity primary key,
  project_id uuid not null references app.projects (id) on delete cascade,
  board_id   uuid not null,
  phase_id   uuid references app.project_phases (id) on delete set null,
  entered_at timestamptz not null,
  left_at    timestamptz,
  moved_by   uuid,
  source     text not null default 'ui' check (source in ('ui', 'workflow', 'system', 'api', 'import')),
  check (left_at is null or left_at >= entered_at)
);
create index project_phase_history_project on app.project_phase_history (project_id, entered_at);
create index project_phase_history_phase on app.project_phase_history (phase_id, left_at);

create table app.project_groups (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references app.projects (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  ord        int not null default 0,
  phase_id   uuid references app.project_phases (id) on delete set null,
  created_at timestamptz not null default now()
);
create index project_groups_project on app.project_groups (project_id, ord);

-- project-linked activities (ACT-01): created from the project or its templates
alter table app.activities add column project_id uuid references app.projects (id) on delete set null;
create index activities_project on app.activities (project_id) where deleted_at is null;

create table app.project_items (
  id                      uuid primary key default gen_random_uuid(),
  project_id              uuid not null references app.projects (id) on delete cascade,
  kind                    text not null check (kind in ('task', 'milestone', 'activity')),
  parent_id               uuid references app.project_items (id) on delete cascade,
  group_id                uuid references app.project_groups (id) on delete set null,
  name                    text check (name is null or char_length(btrim(name)) between 1 and 300),
  description             text check (description is null or char_length(description) <= 10000),
  owner_id                uuid references app.admins (id) on delete set null,
  starts_on               date,
  due_on                  date,
  done                    boolean not null default false,
  done_at                 timestamptz,
  done_by                 uuid references app.admins (id) on delete set null,
  completes_with_subtasks boolean not null default false,
  activity_id             uuid unique references app.activities (id) on delete cascade,
  ord                     int not null default 0,
  source                  text not null default 'ui' check (source in ('ui', 'template', 'paste', 'import', 'workflow', 'api')),
  template_item_id        uuid,
  is_sample               boolean not null default false,
  version                 int not null default 1,
  created_at              timestamptz not null default now(),
  created_by              uuid,
  updated_at              timestamptz not null default now(),
  updated_by              uuid,
  deleted_at              timestamptz,
  check (due_on is null or starts_on is null or due_on >= starts_on),
  check (done = (done_at is not null)),
  check ((kind = 'activity') = (activity_id is not null)),
  check (kind = 'activity' or name is not null),
  check (kind <> 'milestone' or starts_on is null),
  check (parent_id is null or kind = 'task'),
  check (parent_id is distinct from id)
);
create index project_items_project on app.project_items (project_id, ord) where deleted_at is null;

create table app.project_item_assignees (
  item_id   uuid not null references app.project_items (id) on delete cascade,
  staff_id  uuid references app.admins (id) on delete cascade,
  person_id uuid references app.people (id) on delete cascade,     -- a customer-side assignee: no notice, no access (spec Q2)
  check ((staff_id is null) <> (person_id is null))
);
create unique index project_item_assignees_one on app.project_item_assignees (item_id, coalesce(staff_id, person_id));

create table app.project_item_dependencies (
  predecessor_id uuid not null references app.project_items (id) on delete cascade,
  successor_id   uuid not null references app.project_items (id) on delete cascade,
  lag_days       int not null default 0 check (lag_days between -365 and 365),
  created_by     uuid,
  created_at     timestamptz not null default now(),
  primary key (predecessor_id, successor_id),
  check (predecessor_id <> successor_id)
);
create index project_item_dependencies_succ on app.project_item_dependencies (successor_id);

-- AI health summaries: requested here, written by the AI worker (never the prompt or the output in a log)
create table app.project_ai_summaries (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references app.projects (id) on delete cascade,
  state            text not null default 'requested' check (state in ('requested', 'ready', 'failed')),
  suggested_health text check (suggested_health in ('on_track', 'at_risk', 'off_track', 'on_hold')),
  summary          text check (summary is null or char_length(summary) <= 4000),
  recommendations  jsonb not null default '[]'::jsonb check (jsonb_typeof(recommendations) = 'array' and jsonb_array_length(recommendations) <= 5),
  sources          jsonb not null default '[]'::jsonb check (jsonb_typeof(sources) = 'array'),
  requested_by     uuid references app.admins (id) on delete set null,
  requested_at     timestamptz not null default now(),
  generated_at     timestamptz,
  applied_at       timestamptz,
  applied_by       uuid references app.admins (id) on delete set null
);
create index project_ai_summaries_project on app.project_ai_summaries (project_id, requested_at desc);

-- ---------------------------------------------------------------------------
-- record files (CRM-05, SF-33): one table for every record type, bucket «record-files», private. A row is made
-- pending by file_upload_begin and becomes ready when the upload is confirmed; only ready rows are listed.
create table app.record_files (
  id           uuid primary key default gen_random_uuid(),
  entity       text not null references app.entities (key) on delete cascade,
  record_id    uuid not null,
  storage_path text not null unique check (char_length(storage_path) <= 500),
  filename     text not null check (char_length(btrim(filename)) between 1 and 255),
  mime         text not null check (mime in ('application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
                                             'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                             'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                             'application/vnd.openxmlformats-officedocument.presentationml.presentation')),
  size_bytes   bigint not null check (size_bytes between 1 and 26214400),
  source       text not null default 'upload' check (source in ('upload', 'status_report', 'email', 'generated')),
  uploaded_by  uuid references app.admins (id) on delete set null,
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now(),
  ready_at     timestamptz,
  deleted_at   timestamptz
);
create index record_files_record on app.record_files (entity, record_id) where deleted_at is null;

create table app.project_status_reports (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references app.projects (id) on delete cascade,
  sections     jsonb not null check (jsonb_typeof(sections) = 'object'),
  summary      text check (summary is null or char_length(summary) <= 4000),
  ai_drafted   boolean not null default false,
  state        text not null default 'requested' check (state in ('requested', 'ready', 'failed')),
  file_id      uuid references app.record_files (id) on delete set null,
  requested_by uuid references app.admins (id) on delete set null,
  requested_at timestamptz not null default now(),
  ready_at     timestamptz
);
create index project_status_reports_project on app.project_status_reports (project_id, requested_at desc);

-- ---------------------------------------------------------------------------
-- the register
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('project', 'projects', 'projects', 'projects', true, 'name', array['status'], array['name'], 60);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('project', 'name', 'text', true, true, null, 1),
  ('project', 'starts_on', 'date', true, false, null, 2),
  ('project', 'ends_on', 'date', true, false, null, 3),
  ('project', 'description', 'text', true, false, null, 4),
  ('project', 'person_id', 'uuid', true, false, 'person', 5),
  ('project', 'organization_id', 'uuid', true, false, 'organization', 6),
  ('project', 'board_id', 'uuid', false, false, null, 7),
  ('project', 'phase_id', 'uuid', false, false, null, 8),
  ('project', 'status', 'text', false, false, null, 9),
  ('project', 'health', 'text', false, false, null, 10),
  ('project', 'seq', 'int', false, false, null, 11),
  ('project', 'phase_entered_at', 'timestamptz', false, false, null, 12),
  ('project', 'closed_at', 'timestamptz', false, false, null, 13),
  ('project', 'brief_state', 'text', false, false, null, 14),
  ('project', 'created_source', 'text', false, false, null, 15),
  ('project', 'template_id', 'uuid', false, false, null, 16),
  ('activity', 'project_id', 'uuid', false, false, 'project', 16);

-- settings (D-15/D-16): the AI summary, brief and report draft, on by default (spec §9.4)
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('project_ai', 'ai', array['on', 'off'], 'on', 'platform', 'PRJ-02, PRJ-06, PRJ-07', false, null, 410);

-- the screen a project opens on (0030's body plus project)
create or replace function app.entity_route(p_entity text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case p_entity when 'deal' then '/deals' when 'lead' then '/leads' when 'person' then '/contacts' when 'organization' then '/contacts'
                       when 'activity' then '/activities' when 'ticket' then '/tickets' when 'email_thread' then '/inbox'
                       when 'form' then '/lead-capture' when 'chat' then '/lead-capture' when 'campaign' then '/campaigns'
                       when 'document' then '/documents' when 'document_template' then '/documents' when 'project' then '/projects' else null end
$fn$;

-- ---------------------------------------------------------------------------
-- guards
-- a project is made only by project_create (and its siblings): the generic insert has no board
create function app.project_defaults() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.board_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'board_id'; end if;
  if new.phase_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'phase_id'; end if;
  return new;
end $fn$;
create trigger project_defaults before insert on app.projects for each row execute function app.project_defaults();

-- a project's phase belongs to its board («project_defaults» < «project_phase_ok»: name order is firing order)
create function app.project_phase_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if not exists (select 1 from app.project_phases ph where ph.id = new.phase_id and ph.board_id = new.board_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'phase_id';
  end if;
  return new;
end $fn$;
create trigger project_phase_ok before insert or update of phase_id, board_id on app.projects for each row execute function app.project_phase_ok();

create function app.project_history_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from app.projects p where p.id = old.project_id) then return old; end if;
  elsif new.id = old.id and new.project_id = old.project_id and new.board_id = old.board_id and new.entered_at = old.entered_at
        and new.moved_by is not distinct from old.moved_by and new.source = old.source
        and (new.left_at is not distinct from old.left_at or (old.left_at is null and new.left_at is not null))
        and (new.phase_id is not distinct from old.phase_id
             or (new.phase_id is null and not exists (select 1 from app.project_phases ph where ph.id = old.phase_id))) then
    return new;
  end if;
  raise exception 'the phase history is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger project_history_fixed before update or delete on app.project_phase_history for each row execute function app.project_history_fixed();

-- an item's parent is a top-level task of the same project (one level, PRJ-03); its group is the project's; an
-- activity item points at an activity of the same project
create function app.project_item_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.parent_id is not null and (
       not exists (select 1 from app.project_items p where p.id = new.parent_id and p.project_id = new.project_id and p.kind = 'task'
                   and p.parent_id is null and p.deleted_at is null)
       or exists (select 1 from app.project_items c where c.parent_id = new.id and c.deleted_at is null)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'parent_id';
  end if;
  if new.group_id is not null and not exists (select 1 from app.project_groups g where g.id = new.group_id and g.project_id = new.project_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id';
  end if;
  if new.activity_id is not null and not exists (select 1 from app.activities a where a.id = new.activity_id and a.project_id = new.project_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'activity_id';
  end if;
  return new;
end $fn$;
create trigger project_item_ok before insert or update of project_id, parent_id, group_id, activity_id, kind on app.project_items
  for each row execute function app.project_item_ok();

-- dependencies: tasks and milestones of one project, and never a cycle (PRJ-04 RU)
create function app.project_dependency_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
declare a app.project_items; b app.project_items;
begin
  select * into a from app.project_items where id = new.predecessor_id;
  select * into b from app.project_items where id = new.successor_id;
  if a.project_id is distinct from b.project_id then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependency.project'; end if;
  if a.kind not in ('task', 'milestone') or b.kind not in ('task', 'milestone') or a.deleted_at is not null or b.deleted_at is not null then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependency.kind';
  end if;
  if exists (with recursive r(id) as (select new.successor_id
                                      union select d.successor_id from app.project_item_dependencies d join r on d.predecessor_id = r.id)
             select 1 from r where r.id = new.predecessor_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependency.cycle';
  end if;
  return new;
end $fn$;
create trigger project_dependency_ok before insert or update on app.project_item_dependencies for each row execute function app.project_dependency_ok();

create function app.project_template_item_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.parent_id is not null and not exists (select 1 from app.project_template_items p where p.id = new.parent_id and p.template_id = new.template_id
                                                and p.kind = 'task' and p.parent_id is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'parent_id';
  end if;
  if new.group_id is not null and not exists (select 1 from app.project_template_groups g where g.id = new.group_id and g.template_id = new.template_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id';
  end if;
  return new;
end $fn$;
create trigger project_template_item_ok before insert or update on app.project_template_items for each row execute function app.project_template_item_ok();

create function app.project_template_dependency_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if exists (select 1 from app.project_template_items i where i.id in (new.predecessor_id, new.successor_id)
             and (i.template_id <> new.template_id or i.kind not in ('task', 'milestone'))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependency.kind';
  end if;
  if exists (with recursive r(id) as (select new.successor_id
                                      union select d.successor_id from app.project_template_dependencies d join r on d.predecessor_id = r.id)
             select 1 from r where r.id = new.predecessor_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dependency.cycle';
  end if;
  return new;
end $fn$;
create trigger project_template_dependency_ok before insert or update on app.project_template_dependencies
  for each row execute function app.project_template_dependency_ok();

-- a purged or removed record takes its files with it: the rows go, the storage objects go to the worker
create function app.record_files_forget() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_paths text[];
begin
  with d as (delete from app.record_files f where f.entity = tg_argv[0] and f.record_id = old.id returning f.storage_path)
  select array_agg(storage_path) into v_paths from d;
  if cardinality(v_paths) > 0 then
    perform pgmq.send('jobs', jsonb_build_object('job', 'files_purge', 'bucket', 'record-files', 'paths', to_jsonb(v_paths)));
  end if;
  return old;
end $fn$;
create trigger project_files_forget after delete on app.projects for each row execute function app.record_files_forget('project');

-- ---------------------------------------------------------------------------
-- helpers: typed values out of a jsonb argument, each refused as invalid with the field named
create function app.prj_uuid(p_values jsonb, p_key text, p_detail text default null) returns uuid
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_values is null or jsonb_typeof(p_values -> p_key) is null or jsonb_typeof(p_values -> p_key) = 'null' then return null; end if;
  if jsonb_typeof(p_values -> p_key) <> 'string' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key);
  end if;
  return (p_values ->> p_key)::uuid;
exception when invalid_text_representation then
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key);
end $fn$;

create function app.prj_uuids(p_arr jsonb, p_detail text) returns uuid[]
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_arr is null or jsonb_typeof(p_arr) = 'null' then return '{}'; end if;
  if jsonb_typeof(p_arr) <> 'array' or exists (select 1 from jsonb_array_elements(p_arr) x where jsonb_typeof(x) <> 'string') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = p_detail;
  end if;
  return array(select jsonb_array_elements_text(p_arr))::uuid[];
exception when invalid_text_representation then
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = p_detail;
end $fn$;

create function app.prj_date(p_values jsonb, p_key text, p_detail text default null) returns date
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_values is null or jsonb_typeof(p_values -> p_key) is null or jsonb_typeof(p_values -> p_key) = 'null' then return null; end if;
  if jsonb_typeof(p_values -> p_key) <> 'string' or (p_values ->> p_key) !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key);
  end if;
  return (p_values ->> p_key)::date;
exception when invalid_datetime_format or datetime_field_overflow then
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key);
end $fn$;

create function app.prj_int(p_values jsonb, p_key text, p_min int, p_max int, p_detail text default null) returns int
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_values is null or jsonb_typeof(p_values -> p_key) is null or jsonb_typeof(p_values -> p_key) = 'null' then return null; end if;
  if jsonb_typeof(p_values -> p_key) <> 'number' or (p_values ->> p_key) !~ '^-?\d{1,9}$' or (p_values ->> p_key)::int not between p_min and p_max then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key);
  end if;
  return (p_values ->> p_key)::int;
end $fn$;

create function app.prj_text(p_values jsonb, p_key text, p_min int, p_max int, p_detail text default null) returns text
  language plpgsql immutable set search_path = ''
as $fn$
declare v text;
begin
  if p_values is null or jsonb_typeof(p_values -> p_key) is null or jsonb_typeof(p_values -> p_key) = 'null' then
    if p_min > 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key); end if;
    return null;
  end if;
  if jsonb_typeof(p_values -> p_key) <> 'string' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key); end if;
  v := btrim(p_values ->> p_key);
  if char_length(v) = 0 and p_min = 0 then return null; end if;
  if char_length(v) not between p_min and p_max then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = coalesce(p_detail, p_key); end if;
  return v;
end $fn$;

-- refuses keys outside a list
create function app.prj_keys(p_values jsonb, p_allowed text[]) returns void
  language plpgsql immutable set search_path = ''
as $fn$
declare k text;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  select x into k from jsonb_object_keys(p_values) x where not (x = any (p_allowed)) limit 1;
  if k is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
end $fn$;

-- today in the caller's time zone (lateness, the timeline's today line)
create function app.prj_today() returns date
  language sql stable security definer set search_path = ''
as $fn$
  select (now() at time zone coalesce((select a.time_zone from app.admins a where a.id = app.me()), 'Europe/Oslo'))::date
$fn$;

-- the same questions app.can and app.visible answer, for another staff member (who may a mention notify?)
create function app.can_for(p_staff uuid, p_scope text, p_action text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select (ps.kind = 'admin' or (p_scope || ':' || p_action) = any (ps.rights))
                   from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = p_staff and a.active), false)
$fn$;

create function app.visible_for(p_staff uuid, p_owner uuid, p_visibility text) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_kind text; v_group uuid; v_owner_group uuid;
begin
  if p_staff is null then return false; end if;
  if p_visibility = 'all' or p_owner = p_staff then return true; end if;
  select ps.kind, a.group_id into v_kind, v_group from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = p_staff;
  if v_kind = 'admin' then return true; end if;
  if p_owner is null then return p_visibility <> 'owner'; end if;
  select group_id into v_owner_group from app.admins where id = p_owner;
  return case p_visibility when 'group' then v_owner_group = v_group
                           when 'group_sub' then v_group in (select app.group_and_below(v_owner_group)) else false end;
end $fn$;

-- one project the caller may see (module on, «projects:see», visibility), or not_found
create function app.prj_get(p_id uuid, p_lock boolean default false) returns app.projects
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects;
begin
  perform app.require_module('projects');
  perform app.require('projects', 'see');
  if p_lock then
    select * into p from app.projects where id = p_id and deleted_at is null for update;
  else
    select * into p from app.projects where id = p_id and deleted_at is null;
  end if;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return p;
end $fn$;

-- the project's owner, or «Edit others' records»
create function app.prj_can_edit(p app.projects) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select p.owner_id is not distinct from app.me() and app.me() is not null or app.can('projects', 'edit_others')
$fn$;

create function app.prj_require_edit(p app.projects) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if not app.prj_can_edit(p) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'projects:edit_others'; end if;
end $fn$;

-- an item's owner or staff assignee (or its activity's owner) works their own item without edit_others (UF-20 step 4)
create function app.prj_item_mine(i app.project_items) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(app.me() is not null and (i.owner_id = app.me()
         or exists (select 1 from app.project_item_assignees x where x.item_id = i.id and x.staff_id = app.me())
         or exists (select 1 from app.activities a where a.id = i.activity_id and a.owner_id = app.me())), false)
$fn$;

-- one line of the project's history for a work item
create function app.prj_item_log(p_project uuid, p_item uuid, p_field text, p_old jsonb, p_new jsonb, p_source text default 'ui') returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('project', p_project, 'items.' || p_item || '.' || p_field, p_old, p_new, app.me(), coalesce(p_source, 'ui'));
$fn$;

-- refusals that name their cause: the right, the setting, then the connection (spec §5)
create function app.prj_ai_check() returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('projects', 'ai');
  if app.setting('project_ai') <> 'on' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'setting:project_ai'; end if;
  perform app.require_connected('ai');
end $fn$;

-- the card the board shows (§1.1)
create function app.prj_card(t app.projects) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', t.id, 'seq', t.seq, 'name', t.name, 'board_id', t.board_id, 'phase_id', t.phase_id, 'phase_entered_at', t.phase_entered_at,
    'status', t.status, 'closed_at', t.closed_at, 'health', t.health, 'health_source', t.health_source,
    'organization_id', t.organization_id, 'organization', (select o.name from app.organizations o where o.id = t.organization_id and o.deleted_at is null),
    'person_id', t.person_id, 'person', (select pe.name from app.people pe where pe.id = t.person_id and pe.deleted_at is null),
    'starts_on', t.starts_on, 'ends_on', t.ends_on,
    'done', (select count(*) filter (where i.done) from app.project_items i where i.project_id = t.id and i.kind in ('task', 'milestone') and i.deleted_at is null),
    'total', (select count(*) from app.project_items i where i.project_id = t.id and i.kind in ('task', 'milestone') and i.deleted_at is null),
    'overdue', (select count(*) from app.project_items i where i.project_id = t.id and i.deleted_at is null and not i.done and i.due_on < app.prj_today()),
    'owner_id', t.owner_id, 'owner', (select jsonb_build_object('name', a.name, 'initials', a.initials) from app.admins a where a.id = t.owner_id),
    'deal', (select jsonb_build_object('id', d.id, 'title', d.title) from app.project_deals pd join app.deals d on d.id = pd.deal_id
             where pd.project_id = t.id and pd.is_primary and d.deleted_at is null),
    'deals_more', greatest((select count(*) from app.project_deals pd join app.deals d on d.id = pd.deal_id where pd.project_id = t.id and d.deleted_at is null) - 1, 0),
    'labels', to_jsonb(t.labels), 'version', t.version, 'is_sample', t.is_sample, 'updated_at', t.updated_at)
$fn$;

-- move a project into a phase (any board): the history, the record, the changelog, the event, the followers
create function app.prj_move_to(p app.projects, p_phase uuid, p_source text) returns app.projects
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); ph app.project_phases; r app.projects;
begin
  select * into ph from app.project_phases where id = p_phase;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'phase'; end if;
  if ph.id = p.phase_id then return p; end if;
  update app.project_phase_history set left_at = now() where project_id = p.id and left_at is null;
  insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, moved_by, source) values (p.id, ph.board_id, ph.id, now(), v_me, p_source);
  update app.projects set board_id = ph.board_id, phase_id = ph.id, phase_entered_at = now(), version = version + 1, updated_at = now(), updated_by = v_me
  where id = p.id returning * into r;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('project', p.id, 'phase_id', to_jsonb(p.phase_id), to_jsonb(ph.id), v_me, case when p_source = 'workflow' then 'workflow' when p_source = 'system' then 'system' else 'ui' end);
  if ph.board_id <> p.board_id then
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
    values ('project', p.id, 'board_id', to_jsonb(p.board_id), to_jsonb(ph.board_id), v_me, case when p_source = 'workflow' then 'workflow' when p_source = 'system' then 'system' else 'ui' end);
  end if;
  perform app.log('project.moved', 'project', p.id::text, jsonb_build_object('phase', ph.id, 'board', ph.board_id));
  perform app.emit('project.phase_changed', 'project', p.id, jsonb_build_object('from', p.phase_id, 'to', ph.id, 'board', ph.board_id), p.is_sample);
  perform app.notify(f.staff_id, 'system', 'project.phase_changed', jsonb_build_object('record', p.name, 'phase', ph.name, 'actor', (select name from app.admins where id = v_me)),
                     '/projects?project=' || p.id, 'project', p.id)
  from app.followers f where f.entity = 'project' and f.record_id = p.id and f.staff_id is distinct from v_me;
  return r;
end $fn$;

-- instantiate a template into a project (PRJ-05): groups, items dated from the project's start, activities at their
-- time of day in the owner's time zone, dependencies. p_group puts every item into one group of the project instead.
create function app.prj_apply_template(p_project uuid, p_template uuid, p_group uuid default null, p_source text default 'template') returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.me(); p app.projects; t app.project_templates; g record; it record; v_gmap jsonb := '{}'::jsonb; v_imap jsonb := '{}'::jsonb;
  v_gord int; v_iord int; v_new uuid; v_act uuid; v_date date; v_tz text; v_deal uuid; n int := 0;
begin
  select * into p from app.projects where id = p_project;
  select * into t from app.project_templates where id = p_template and deleted_at is null;
  if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'template_id'; end if;
  if p.starts_on is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_on'; end if;
  v_tz := coalesce((select a.time_zone from app.admins a where a.id = p.owner_id), 'Europe/Oslo');
  v_deal := (select pd.deal_id from app.project_deals pd where pd.project_id = p.id and pd.is_primary);
  v_gord := coalesce((select max(ord) from app.project_groups where project_id = p.id), 0);
  v_iord := coalesce((select max(ord) from app.project_items where project_id = p.id), 0);
  if p_group is null then
    for g in select * from app.project_template_groups where template_id = t.id order by ord, name loop
      v_gord := v_gord + 10;
      insert into app.project_groups (project_id, name, ord, phase_id)
      values (p.id, g.name, v_gord, case when exists (select 1 from app.project_phases ph where ph.id = g.phase_id and ph.board_id = p.board_id) then g.phase_id end)
      returning id into v_new;
      v_gmap := v_gmap || jsonb_build_object(g.id::text, v_new);
    end loop;
  end if;
  for it in select * from app.project_template_items where template_id = t.id
            order by (parent_id is not null), coalesce(due_offset_days, start_offset_days) nulls last, ord, name loop
    v_iord := v_iord + 10;
    if it.kind = 'activity' then
      v_date := p.starts_on + coalesce(it.due_offset_days, it.start_offset_days, 0);
      insert into app.activities (type_id, subject, starts_at, duration_min, owner_id, visibility, project_id, deal_id, organization_id, person_id,
                                  is_sample, created_by, updated_by)
      values (it.activity_type_id, left(it.name, 200), (v_date + it.activity_time) at time zone v_tz, coalesce(it.activity_duration_min, 30),
              p.owner_id, p.visibility, p.id, v_deal, p.organization_id, p.person_id, p.is_sample, v_me, v_me)
      returning id into v_act;
      insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values ('activity', v_act, '*created', jsonb_build_object('project', p.id), v_me, 'system');
      perform app.emit('activity.created', 'activity', v_act, jsonb_build_object('project', p.id, 'deal', v_deal), p.is_sample);
      insert into app.project_items (project_id, kind, group_id, activity_id, ord, source, template_item_id, is_sample, created_by, updated_by)
      values (p.id, 'activity', coalesce(p_group, (v_gmap ->> it.group_id::text)::uuid), v_act, v_iord, p_source, it.id, p.is_sample, v_me, v_me)
      returning id into v_new;
    else
      insert into app.project_items (project_id, kind, parent_id, group_id, name, owner_id, starts_on, due_on, completes_with_subtasks, ord, source,
                                     template_item_id, is_sample, created_by, updated_by)
      values (p.id, it.kind, (v_imap ->> it.parent_id::text)::uuid, coalesce(p_group, (v_gmap ->> it.group_id::text)::uuid), it.name,
              case when it.assignee = 'owner' then p.owner_id end,
              case when it.kind = 'milestone' then null else p.starts_on + it.start_offset_days end, p.starts_on + it.due_offset_days,
              it.completes_with_subtasks, v_iord, p_source, it.id, p.is_sample, v_me, v_me)
      returning id into v_new;
    end if;
    v_imap := v_imap || jsonb_build_object(it.id::text, v_new);
    n := n + 1;
  end loop;
  insert into app.project_item_dependencies (predecessor_id, successor_id, lag_days, created_by)
  select (v_imap ->> d.predecessor_id::text)::uuid, (v_imap ->> d.successor_id::text)::uuid, d.lag_days, v_me
  from app.project_template_dependencies d where d.template_id = t.id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
  values ('project', p.id, 'items', jsonb_build_object('template', t.id, 'count', n), v_me, case when p_source = 'workflow' then 'workflow' else 'ui' end);
  perform app.emit('project.template_applied', 'project', p.id, jsonb_build_object('template', t.id, 'items', n), p.is_sample);
  return n;
end $fn$;

-- make a project. p_values: name, board_id, phase_id, owner_id, visibility, labels, custom, starts_on, ends_on, description,
-- person_id, organization_id, template_id, deal_ids (the first is the primary). → {id, version, seq}
create function app.prj_create(p_values jsonb, p_source text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('projects', 'add');
  v_sandbox boolean; v_name text; v_board uuid; v_phase uuid; v_starts date; v_ends date; v_desc text; v_owner uuid; v_vis text;
  v_labels uuid[] := '{}'; v_custom jsonb := '{}'::jsonb; v_person uuid; v_org uuid; v_tpl uuid; v_deals uuid[] := '{}'; v_req record;
  v_id uuid; v_seq bigint; d uuid; i int := 0;
begin
  perform app.entity('project');
  perform app.prj_keys(p_values, array['name', 'board_id', 'phase_id', 'owner_id', 'visibility', 'labels', 'custom', 'starts_on', 'ends_on', 'description',
                                       'person_id', 'organization_id', 'template_id', 'deal_ids']);
  v_sandbox := coalesce((select sandbox from app.admins where id = v_me), false);
  v_name := app.prj_text(p_values, 'name', 1, 200);
  v_board := coalesce(app.prj_uuid(p_values, 'board_id'),
                      (select b.id from app.project_boards b where b.archived_at is null and (v_sandbox or not b.is_sample) order by b.ord, b.created_at limit 1));
  if v_board is null or not exists (select 1 from app.project_boards b where b.id = v_board and b.archived_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'board_id';
  end if;
  v_phase := coalesce(app.prj_uuid(p_values, 'phase_id'), (select ph.id from app.project_phases ph where ph.board_id = v_board order by ph.ord, ph.created_at limit 1));
  if v_phase is null or not exists (select 1 from app.project_phases ph where ph.id = v_phase and ph.board_id = v_board) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'phase_id';
  end if;
  v_starts := app.prj_date(p_values, 'starts_on');
  v_ends := app.prj_date(p_values, 'ends_on');
  if v_ends < v_starts then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ends_on'; end if;
  v_desc := app.prj_text(p_values, 'description', 0, 20000);
  v_owner := coalesce(app.prj_uuid(p_values, 'owner_id'), v_me);
  if not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
  v_vis := coalesce(p_values ->> 'visibility', app.setting('visibility_default', 'project'));
  if v_vis not in ('owner', 'group', 'group_sub', 'all') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'visibility'; end if;
  v_labels := app.prj_uuids(p_values -> 'labels', 'labels');
  if exists (select 1 from unnest(v_labels) x where not exists (select 1 from app.labels l where l.id = x and l.entity = 'project')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'labels';
  end if;
  if p_values ? 'custom' then v_custom := jsonb_strip_nulls(app.check_custom('project', p_values -> 'custom')); end if;
  for v_req in select f.key from app.fields f where f.entity = 'project' and f.quality = 'required' and f.archived_at is null loop
    if not (v_custom ? v_req.key) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || v_req.key || ':required'; end if;
  end loop;
  v_person := app.prj_uuid(p_values, 'person_id');
  if v_person is not null and not exists (select 1 from app.people x where x.id = v_person and x.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'person_id';
  end if;
  v_org := app.prj_uuid(p_values, 'organization_id');
  if v_org is not null and not exists (select 1 from app.organizations x where x.id = v_org and x.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'organization_id';
  end if;
  v_tpl := app.prj_uuid(p_values, 'template_id');
  if v_tpl is not null and not exists (select 1 from app.project_templates x where x.id = v_tpl and x.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'template_id';
  end if;
  if v_tpl is not null and v_starts is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_on'; end if;
  v_deals := array(select x from unnest(app.prj_uuids(p_values -> 'deal_ids', 'deal_ids')) with ordinality u(x, n)
                   where n = (select min(n2) from unnest(app.prj_uuids(p_values -> 'deal_ids', 'deal_ids')) with ordinality u2(x2, n2) where x2 = x) order by n);
  if cardinality(v_deals) > 0 then
    perform app.require('deals', 'see');
    foreach d in array v_deals loop
      if not exists (select 1 from app.deals x where x.id = d and x.deleted_at is null and app.visible(x.owner_id, x.visibility)) then
        raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal';
      end if;
    end loop;
  end if;

  insert into app.projects (name, board_id, phase_id, starts_on, ends_on, description, person_id, organization_id, template_id, created_source,
                            owner_id, visibility, labels, custom, is_sample, created_by, updated_by)
  values (v_name, v_board, v_phase, v_starts, v_ends, v_desc, v_person, v_org, v_tpl, p_source, v_owner, v_vis, v_labels, v_custom, v_sandbox, v_me, v_me)
  returning id, seq into v_id, v_seq;
  insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, moved_by, source)
  values (v_id, v_board, v_phase, now(), v_me, case when p_source = 'workflow' then 'workflow' else 'ui' end);
  insert into app.project_deals (project_id, deal_id, is_primary, linked_by)
  select v_id, x.d, x.n = 1, v_me from unnest(v_deals) with ordinality x(d, n);
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
  values ('project', v_id, '*created', jsonb_build_object('source', p_source), v_me, case when p_source = 'workflow' then 'workflow' else 'ui' end);
  if v_tpl is not null then perform app.prj_apply_template(v_id, v_tpl, null, case when p_source = 'workflow' then 'workflow' else 'template' end); end if;
  perform app.log('record.created', 'project', v_id::text, jsonb_build_object('source', p_source, 'template', v_tpl, 'deals', cardinality(v_deals)));
  perform app.emit('project.created', 'project', v_id, jsonb_build_object('source', p_source, 'template', v_tpl, 'deal', v_deals[1]), v_sandbox);
  if v_owner <> v_me then
    perform app.notify(v_owner, 'system', 'project.assigned', jsonb_build_object('record', v_name, 'actor', (select name from app.admins where id = v_me)),
                       '/projects?project=' || v_id, 'project', v_id);
  end if;
  return jsonb_build_object('id', v_id, 'version', 1, 'seq', v_seq);
end $fn$;

-- a project's AI and connection state as the drawer needs it (§1.5): the banner shows only when all three hold
create function app.prj_ai_state() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('enabled', app.can('projects', 'ai') and app.setting('project_ai') = 'on' and app.connected('ai'),
                            'reason', case when not app.can('projects', 'ai') then 'forbidden:projects:ai'
                                           when app.setting('project_ai') <> 'on' then 'forbidden:setting:project_ai'
                                           when not app.connected('ai') then 'not_connected:ai' end)
$fn$;

-- the automation hooks the Reports tab names (§1.4), from one place: the trigger events the engine accepts for a
-- project and the project_action actions. The actions run only once the executor calls app.wf_project_action.
create function app.project_actions_wired() returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select position('app.wf_project_action' in p.prosrc) > 0 from pg_proc p
                   where p.oid = 'app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)'::regprocedure), false)
$fn$;

create function app.prj_hooks() returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'triggers', '["created","updated","deleted","phase_changed","health_changed","task_completed","milestone_reached","completed"]'::jsonb,
    'actions', '["create_from_template","move_phase","add_tasks_from_template","assign_task"]'::jsonb,
    'actions_available', app.project_actions_wired())
$fn$;

-- ===========================================================================
-- reads
-- ===========================================================================

-- boards with their phases and the open projects in each (the board select, Settings)
create function public.project_boards_get(p_archived boolean default false) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'see'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
begin
  perform app.require_module('projects');
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'ord', b.ord, 'archived_at', b.archived_at,
      'phases', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'name', ph.name, 'ord', ph.ord, 'color', ph.color,
                                  'open_projects', (select count(*) from app.projects t where t.phase_id = ph.id and t.status = 'open' and t.deleted_at is null
                                                    and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample)))
                                order by ph.ord, ph.created_at) from app.project_phases ph where ph.board_id = b.id), '[]'::jsonb))
    order by b.ord, b.created_at)
    from app.project_boards b where (coalesce(p_archived, false) or b.archived_at is null) and (v_sandbox or not b.is_sample)), '[]'::jsonb);
end $fn$;

-- the board (§1.1): phases with their open count, the cards, and the workflow hint. p_query: {filters, q, mine, closed}.
-- The board and the timeline read the same predicate (PIP-12).
create function public.projects_board(p_board uuid, p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('projects', 'see');
  e app.entities := app.entity('project');
  v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
  q jsonb := coalesce(p_query, '{}'::jsonb); b app.project_boards; v_where text; v_cards jsonb; v_q text;
begin
  select * into b from app.project_boards where id = p_board and (v_sandbox or not is_sample);
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'board'; end if;
  v_where := format('where t.deleted_at is null and t.board_id = %L and %s', p_board, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if not coalesce((q ->> 'closed')::boolean, false) then v_where := v_where || ' and t.status = ''open'''; end if;
  if coalesce((q ->> 'mine')::boolean, false) then v_where := v_where || format(' and t.owner_id = %L', v_me); end if;
  v_q := btrim(coalesce(q ->> 'q', ''));
  if v_q <> '' then v_where := v_where || format(' and t.name ilike %L', '%' || replace(replace(left(v_q, 100), '%', '\%'), '_', '\_') || '%'); end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  execute format('select coalesce(jsonb_agg(app.prj_card(t) order by t.seq), ''[]''::jsonb) from app.projects t %s', v_where) into v_cards;
  perform app.log('record.listed', 'project', null, jsonb_build_object('count', jsonb_array_length(v_cards), 'view', 'board'));
  return jsonb_build_object(
    'board', jsonb_build_object('id', b.id, 'name', b.name, 'archived_at', b.archived_at),
    'phases', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'name', ph.name, 'ord', ph.ord, 'color', ph.color,
                                  'count', (select count(*) from jsonb_array_elements(v_cards) c where c ->> 'phase_id' = ph.id::text and c ->> 'status' = 'open'))
                                order by ph.ord, ph.created_at) from app.project_phases ph where ph.board_id = b.id), '[]'::jsonb),
    'cards', v_cards,
    -- shown only while an active workflow creates projects from a template (precedent V-DEALS-15)
    'workflow_hint', (select jsonb_build_object('id', w.id, 'name', w.name) from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
                      where w.state = 'active' and w.deleted_at is null and (v_sandbox or not w.is_sample)
                        and exists (select 1 from jsonb_each(v.flat) n(k, x) where n.k <> '_start' and n.x ->> 'kind' = 'project_action'
                                    and n.x -> 'config' ->> 'action' = 'create_from_template')
                      order by w.activated_at limit 1));
end $fn$;

-- everything the drawer shows (§1.5)
create function public.project_detail(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  p app.projects := app.prj_get(p_id);
  v_me uuid := app.me(); v_today date := app.prj_today(); v_edit boolean := app.prj_can_edit(p); v_deals_see boolean := app.can('deals', 'see');
begin
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'project', p.id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'project', p.id::text);
  return app.prj_card(p) || jsonb_build_object(
    'description', p.description, 'brief_state', p.brief_state, 'custom', p.custom, 'visibility', p.visibility, 'created_source', p.created_source,
    'health_set_at', p.health_set_at, 'health_set_by', (select a.name from app.admins a where a.id = p.health_set_by), 'created_at', p.created_at, 'can_edit', v_edit,
    'board', (select jsonb_build_object('id', b.id, 'name', b.name) from app.project_boards b where b.id = p.board_id),
    'phase', (select jsonb_build_object('id', ph.id, 'name', ph.name, 'color', ph.color) from app.project_phases ph where ph.id = p.phase_id),
    'template', (select jsonb_build_object('id', t.id, 'name', t.name) from app.project_templates t where t.id = p.template_id and t.deleted_at is null),
    -- a project-only user sees the deal's title; value and stage need «deals:see» (spec Q6)
    'deals', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'is_primary', pd.is_primary,
                                                           'value', case when v_deals_see then d.value end, 'currency', case when v_deals_see then d.currency end,
                                                           'status', case when v_deals_see then d.status end,
                                                           'stage', case when v_deals_see then (select s.name from app.stages s where s.id = d.stage_id) end)
                                        order by pd.is_primary desc, pd.linked_at)
                       from app.project_deals pd join app.deals d on d.id = pd.deal_id where pd.project_id = p.id and d.deleted_at is null), '[]'::jsonb),
    'groups', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'ord', g.ord, 'phase_id', g.phase_id) order by g.ord, g.created_at)
                        from app.project_groups g where g.project_id = p.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'kind', i.kind, 'name', coalesce(i.name, a.subject), 'parent_id', i.parent_id, 'group_id', i.group_id, 'description', i.description,
        'owner_id', coalesce(i.owner_id, a.owner_id), 'owner', (select s.name from app.admins s where s.id = coalesce(i.owner_id, a.owner_id)),
        'assignees', coalesce((select jsonb_agg(jsonb_build_object('staff_id', x.staff_id, 'person_id', x.person_id,
                                                                   'name', coalesce((select s.name from app.admins s where s.id = x.staff_id),
                                                                                    (select pe.name from app.people pe where pe.id = x.person_id and pe.deleted_at is null))))
                               from app.project_item_assignees x where x.item_id = i.id), '[]'::jsonb),
        'starts_on', i.starts_on, 'due_on', i.due_on, 'done', i.done, 'done_at', i.done_at,
        'late_days', case when not i.done and i.due_on < v_today then v_today - i.due_on end,
        'depends_on', coalesce((select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name, 'kind', pr.kind, 'lag_days', dp.lag_days) order by pr.ord)
                                from app.project_item_dependencies dp join app.project_items pr on pr.id = dp.predecessor_id
                                where dp.successor_id = i.id and pr.deleted_at is null), '[]'::jsonb),
        'completes_with_subtasks', i.completes_with_subtasks, 'source', i.source, 'ord', i.ord, 'version', i.version,
        'activity', case when a.id is not null then jsonb_build_object('id', a.id, 'subject', a.subject, 'starts_at', a.starts_at, 'duration_min', a.duration_min,
                                                                       'type', (select jsonb_build_object('key', ty.key, 'glyph', ty.glyph) from app.activity_types ty where ty.id = a.type_id)) end,
        'can_edit', v_edit or app.prj_item_mine(i))
      order by (select g.ord from app.project_groups g where g.id = i.group_id) nulls last, coalesce((select pi.ord from app.project_items pi where pi.id = i.parent_id), i.ord),
               i.parent_id is not null, i.ord)
      from app.project_items i left join app.activities a on a.id = i.activity_id and a.deleted_at is null
      where i.project_id = p.id and i.deleted_at is null and (i.kind <> 'activity' or a.id is not null)), '[]'::jsonb),
    -- notes, and messages of linked threads the caller may read (private threads stay private, COM-02), newest first
    'timeline', coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (
        select jsonb_build_object('kind', 'note', 'id', n.id, 'at', n.created_at, 'author', s.name, 'author_id', n.author_id, 'body', n.body, 'pinned', n.pinned) x
        from app.notes n left join app.admins s on s.id = n.author_id where n.entity = 'project' and n.record_id = p.id and n.deleted_at is null
        union all
        select jsonb_build_object('kind', 'email', 'id', m.id, 'thread_id', m.thread_id, 'at', coalesce(m.received_at, m.created_at), 'author', coalesce(m.from_name, m.from_addr),
                                  'direction', m.direction, 'subject', m.subject, 'excerpt', left(m.body_text, 500))
        from app.email_links l join app.email_messages m on m.thread_id = l.thread_id
        where l.entity = 'project' and l.record_id = p.id and app.thread_visible(l.thread_id)
        order by 1 limit 100) s), '[]'::jsonb),
    'files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'filename', f.filename, 'mime', f.mime, 'size_bytes', f.size_bytes, 'source', f.source,
                                                           'created_at', f.created_at) order by f.created_at desc)
                       from app.record_files f where f.entity = 'project' and f.record_id = p.id and f.deleted_at is null and f.ready_at is not null), '[]'::jsonb),
    -- sharing is the project's visibility and its followers; there is no second sharing rule (§1.5)
    'sharing', jsonb_build_object('visibility', p.visibility,
                                  'group', case when p.visibility in ('group', 'group_sub') then (select g.name from app.admins a join app.visibility_groups g on g.id = a.group_id where a.id = p.owner_id) end,
                                  'followers', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name) order by a.name)
                                                         from app.followers f join app.admins a on a.id = f.staff_id where f.entity = 'project' and f.record_id = p.id), '[]'::jsonb),
                                  'following', exists (select 1 from app.followers f where f.entity = 'project' and f.record_id = p.id and f.staff_id = v_me)),
    'ai', app.prj_ai_state() || jsonb_build_object('summary',
            case when (app.prj_ai_state() ->> 'enabled')::boolean then
              (select jsonb_build_object('id', s.id, 'suggested_health', s.suggested_health, 'summary', s.summary, 'recommendations', s.recommendations,
                                         'sources', s.sources, 'generated_at', s.generated_at, 'applied_at', s.applied_at)
               from app.project_ai_summaries s where s.project_id = p.id and s.state = 'ready' order by s.generated_at desc limit 1) end,
            'pending', exists (select 1 from app.project_ai_summaries s where s.project_id = p.id and s.state = 'requested')),
    'status_reports', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'state', r.state, 'requested_at', r.requested_at, 'ready_at', r.ready_at, 'file_id', r.file_id,
                                                                    'ai_drafted', r.ai_drafted) order by r.requested_at desc)
                                from app.project_status_reports r where r.project_id = p.id), '[]'::jsonb));
end $fn$;

-- the timeline (§1.2). Range R: month start of the earliest date to month end of the latest, at least three months
-- (or p_from and p_months). x% = (start − R.start) ÷ R.days × 100, w% = (end − start + 1) ÷ R.days × 100. p_id null: the
-- project the caller opened last.
create function public.project_timeline(p_id uuid default null, p_from date default null, p_months int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('projects', 'see'); v_id uuid := p_id; p app.projects; v_today date; v_min date; v_max date; v_start date; v_end date; v_days int; v_months int;
begin
  perform app.require_module('projects');
  if v_id is null then
    v_id := (select r.record_id from app.recents r join app.projects t on t.id = r.record_id
             where r.staff_id = v_me and r.entity = 'project' and t.deleted_at is null and app.visible(t.owner_id, t.visibility) order by r.at desc limit 1);
    if v_id is null then return jsonb_build_object('project', null); end if;
  end if;
  p := app.prj_get(v_id);
  v_today := app.prj_today();
  if p_months is not null and p_months not between 1 and 36 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'months'; end if;
  create temp table if not exists pg_temp.prj_tl (id uuid, kind text, name text, parent_id uuid, group_id uuid, s date, e date, done boolean, due_on date, ord int, gord int) on commit drop;
  truncate pg_temp.prj_tl;
  insert into pg_temp.prj_tl
  select i.id, i.kind, coalesce(i.name, a.subject), i.parent_id, i.group_id,
         case when i.kind = 'activity' then (a.starts_at at time zone coalesce((select x.time_zone from app.admins x where x.id = v_me), 'Europe/Oslo'))::date
              else coalesce(i.starts_on, i.due_on) end,
         case when i.kind = 'activity' then (a.starts_at at time zone coalesce((select x.time_zone from app.admins x where x.id = v_me), 'Europe/Oslo'))::date
              else coalesce(i.due_on, i.starts_on) end,
         i.done, i.due_on, i.ord, (select g.ord from app.project_groups g where g.id = i.group_id)
  from app.project_items i left join app.activities a on a.id = i.activity_id and a.deleted_at is null
  where i.project_id = p.id and i.deleted_at is null and (i.kind <> 'activity' or a.id is not null);
  select least(p.starts_on, min(s)), greatest(p.ends_on, max(e)) into v_min, v_max from pg_temp.prj_tl;
  v_min := coalesce(v_min, p.starts_on, p.ends_on); v_max := coalesce(v_max, p.ends_on, p.starts_on);
  if p_from is not null then
    v_start := date_trunc('month', p_from)::date;
  elsif v_min is not null then
    v_start := date_trunc('month', v_min)::date;
  end if;
  if v_start is not null then
    v_months := coalesce(p_months, greatest(3, ((extract(year from v_max) * 12 + extract(month from v_max)) - (extract(year from v_start) * 12 + extract(month from v_start)))::int + 1));
    v_end := (v_start + make_interval(months => v_months) - interval '1 day')::date;
    v_days := v_end - v_start + 1;
  end if;
  perform app.log('record.read', 'project', p.id::text, jsonb_build_object('view', 'timeline'));
  return jsonb_build_object(
    'project', jsonb_build_object('id', p.id, 'seq', p.seq, 'name', p.name, 'starts_on', p.starts_on, 'ends_on', p.ends_on, 'status', p.status,
                                  'organization', (select o.name from app.organizations o where o.id = p.organization_id), 'can_edit', app.prj_can_edit(p)),
    'range', case when v_start is null then null else jsonb_build_object('from', v_start, 'to', v_end, 'days', v_days,
               'months', (select jsonb_agg(to_char(m, 'YYYY-MM-DD') order by m) from generate_series(v_start, v_end, interval '1 month') m)) end,
    'today', v_today,
    'today_pct', case when v_start is not null and v_today between v_start and v_end then round((v_today - v_start) * 100.0 / v_days, 2) end,
    'groups', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'ord', g.ord, 'start', x.s, 'end', x.e,
                                  'x', case when v_start is not null and x.s is not null then round((x.s - v_start) * 100.0 / v_days, 2) end,
                                  'w', case when v_start is not null and x.s is not null then round((x.e - x.s + 1) * 100.0 / v_days, 2) end) order by g.ord, g.created_at)
                        from app.project_groups g cross join lateral (select min(t.s) s, max(t.e) e from pg_temp.prj_tl t where t.group_id = g.id) x
                        where g.project_id = p.id), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'name', t.name, 'parent_id', t.parent_id, 'group_id', t.group_id,
                                 'start', t.s, 'end', t.e, 'done', t.done, 'overdue', not t.done and t.due_on < v_today,
                                 'x', case when v_start is not null and t.s is not null then round((t.s - v_start) * 100.0 / v_days, 2) end,
                                 'w', case when v_start is not null and t.s is not null then round((t.e - t.s + 1) * 100.0 / v_days, 2) end)
                               order by t.gord nulls last, coalesce((select pt.ord from pg_temp.prj_tl pt where pt.id = t.parent_id), t.ord), t.parent_id is not null, t.ord)
                      from pg_temp.prj_tl t), '[]'::jsonb),
    -- predecessor end → successor start; a successor that starts before its predecessor ends (plus lag) is flagged (spec Q3)
    'dependencies', coalesce((select jsonb_agg(jsonb_build_object('predecessor', d.predecessor_id, 'successor', d.successor_id, 'lag_days', d.lag_days,
                                        'violated', b.s < a.e + d.lag_days))
                              from app.project_item_dependencies d join pg_temp.prj_tl a on a.id = d.predecessor_id join pg_temp.prj_tl b on b.id = d.successor_id), '[]'::jsonb));
end $fn$;

-- the template cards (§1.3): counts computed, the first five items as «Day N»
create function app.prj_template_row(t app.project_templates) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', t.id, 'name', t.name, 'description', t.description, 'organized_by', t.organized_by, 'board_id', t.board_id,
    'source_project_id', t.source_project_id, 'version', t.version, 'updated_at', t.updated_at,
    'created_by', t.created_by, 'creator', (select a.name from app.admins a where a.id = t.created_by),
    'groups', (select count(*) from app.project_template_groups g where g.template_id = t.id),
    'tasks', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'task'),
    'milestones', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'milestone'),
    'activities', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'activity'),
    'dependencies', (select count(*) from app.project_template_dependencies d where d.template_id = t.id),
    'preview', coalesce((select jsonb_agg(jsonb_build_object('day', x.day, 'kind', x.kind, 'name', x.name) order by x.day nulls last, x.ord) from (
                select coalesce(i.due_offset_days, i.start_offset_days) as day, i.kind, i.name, i.ord from app.project_template_items i where i.template_id = t.id
                order by coalesce(i.due_offset_days, i.start_offset_days) nulls last, i.ord limit 5) x), '[]'::jsonb),
    'can_edit', (t.created_by = app.me() and app.can('projects', 'add')) or app.can('projects', 'configure'))
$fn$;

create function public.project_templates_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'see'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
begin
  perform app.require_module('projects');
  return coalesce((select jsonb_agg(app.prj_template_row(t) order by t.name) from app.project_templates t
                   where t.deleted_at is null and (v_sandbox or not t.is_sample)), '[]'::jsonb);
end $fn$;

-- one template with its groups, items and dependencies (the template editor)
create function public.project_template_get(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.project_templates;
begin
  perform app.require('projects', 'see');
  perform app.require_module('projects');
  select * into t from app.project_templates where id = p_id and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return app.prj_template_row(t) || jsonb_build_object(
    'group_list', coalesce((select jsonb_agg(jsonb_build_object('key', g.id, 'name', g.name, 'ord', g.ord, 'phase_id', g.phase_id) order by g.ord) from app.project_template_groups g
                            where g.template_id = t.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', i.id, 'group', i.group_id, 'parent', i.parent_id, 'kind', i.kind, 'name', i.name,
                                 'start_offset_days', i.start_offset_days, 'due_offset_days', i.due_offset_days,
                                 'activity_type', (select ty.key from app.activity_types ty where ty.id = i.activity_type_id),
                                 'activity_time', to_char(i.activity_time, 'HH24:MI'), 'activity_duration_min', i.activity_duration_min,
                                 'assignee', i.assignee, 'completes_with_subtasks', i.completes_with_subtasks, 'ord', i.ord) order by i.parent_id is not null, i.ord)
                       from app.project_template_items i where i.template_id = t.id), '[]'::jsonb),
    'dependency_list', coalesce((select jsonb_agg(jsonb_build_object('pred', d.predecessor_id, 'succ', d.successor_id, 'lag_days', d.lag_days))
                                 from app.project_template_dependencies d where d.template_id = t.id), '[]'::jsonb));
end $fn$;

-- the Reports tab (§1.4). Performance: open, visible projects per health (a «not set» bucket included), on one board or
-- all; width = n ÷ max × 100. Duration: the median days of finished stays per phase, in the period [from, to] by the
-- day the stay ended (default the last twelve months), with n. Without «projects:reports_others», own projects only.
create function public.project_reports(p_board uuid default null, p_from date default null, p_to date default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('projects', 'see');
  v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
  v_own boolean := not app.can('projects', 'reports_others');
  v_to date := coalesce(p_to, app.prj_today()); v_from date := coalesce(p_from, (coalesce(p_to, app.prj_today()) - interval '12 months')::date);
  v_perf jsonb; v_max int;
begin
  perform app.require_module('projects');
  if v_to < v_from then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'to'; end if;
  if p_board is not null and not exists (select 1 from app.project_boards b where b.id = p_board) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'board'; end if;
  with c as (select t.health, count(*) n from app.projects t
             where t.deleted_at is null and t.status = 'open' and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample)
               and (p_board is null or t.board_id = p_board) and (not v_own or t.owner_id = v_me) group by t.health),
       h(health, ord) as (values ('on_track', 1), ('at_risk', 2), ('off_track', 3), ('on_hold', 4), (null, 5))
  select jsonb_agg(jsonb_build_object('health', h.health, 'n', coalesce(c.n, 0)) order by h.ord), max(coalesce(c.n, 0))
  into v_perf, v_max from h left join c on c.health is not distinct from h.health;
  return jsonb_build_object(
    'board_id', p_board, 'from', v_from, 'to', v_to, 'own_only', v_own,
    'performance', (select jsonb_agg(x || jsonb_build_object('w', case when v_max > 0 then round((x ->> 'n')::numeric * 100 / v_max, 1) else 0 end)) from jsonb_array_elements(v_perf) x),
    'duration', coalesce((select jsonb_agg(jsonb_build_object('phase_id', ph.id, 'phase', ph.name, 'board_id', b.id, 'board', b.name, 'n', x.n,
                                    'median_days', case when x.n > 0 then round(x.med::numeric, 1) end) order by b.ord, b.created_at, ph.ord)
                          from app.project_phases ph join app.project_boards b on b.id = ph.board_id
                          cross join lateral (
                            select count(*) n, percentile_cont(0.5) within group (order by extract(epoch from h.left_at - h.entered_at) / 86400) med
                            from app.project_phase_history h join app.projects t on t.id = h.project_id
                            where h.phase_id = ph.id and h.left_at is not null
                              and (h.left_at at time zone 'Europe/Oslo')::date between v_from and v_to
                              and t.deleted_at is null and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample)
                              and (not v_own or t.owner_id = v_me)) x
                          where (p_board is null and b.archived_at is null or ph.board_id = p_board) and (v_sandbox or not b.is_sample)), '[]'::jsonb),
    'hooks', app.prj_hooks());
end $fn$;

-- ===========================================================================
-- projects
-- ===========================================================================
-- ＋ Project and «Use template» (§1.6). Plain fields later through rec_save('project', …); delete and restore through
-- rec_delete / rec_restore.
create function public.project_create(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require_module('projects');
  return app.prj_create(p_values, 'ui');
end $fn$;

-- from a won deal (PRJ-02, UF-20): the deal, its person and organisation; p_values may add or override fields and ask
-- for an AI brief ({draft_brief: true}), which needs «projects:ai», project_ai on and the AI connection
create function public.project_create_from_deal(p_deal uuid, p_values jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'add'); d app.deals; v jsonb := coalesce(p_values, '{}'::jsonb); v_brief boolean; r jsonb;
begin
  perform app.require_module('projects');
  perform app.require('deals', 'see');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  select * into d from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal'; end if;
  v_brief := coalesce((v ->> 'draft_brief')::boolean, false);
  if v_brief then perform app.prj_ai_check(); end if;
  r := app.prj_create(jsonb_strip_nulls(jsonb_build_object('name', left(d.title, 200), 'person_id', d.person_id, 'organization_id', d.organization_id))
                      || (v - 'draft_brief' - 'deal_ids')
                      || jsonb_build_object('deal_ids', jsonb_build_array(d.id) || coalesce(case when jsonb_typeof(v -> 'deal_ids') = 'array' then v -> 'deal_ids' end, '[]'::jsonb)),
                      'deal');
  if v_brief then
    update app.projects set brief_state = 'drafting' where id = (r ->> 'id')::uuid;
    perform pgmq.send('jobs', jsonb_build_object('job', 'project_brief', 'project_id', r ->> 'id', 'deal_id', d.id, 'staff_id', v_me));
  end if;
  return r;
end $fn$;

-- drag a card (PRJ-01), or choose a phase of another board in the drawer (spec Q20)
create function public.project_move(p_id uuid, p_phase uuid, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true);
begin
  perform app.prj_require_edit(p);
  if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
  if p.status <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  p := app.prj_move_to(p, p_phase, 'ui');
  return jsonb_build_object('id', p.id, 'version', p.version, 'board_id', p.board_id, 'phase_id', p.phase_id);
end $fn$;

-- health (PRJ-06): set by hand, cleared (null: «Not set»), or taken from a ready AI summary
create function public.project_health_set(p_id uuid, p_health text, p_version int default null, p_from_summary uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true); v_me uuid := app.me(); s app.project_ai_summaries; v_health text := p_health; v_source text;
begin
  perform app.prj_require_edit(p);
  if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
  if p.status <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if v_health is not null and v_health not in ('on_track', 'at_risk', 'off_track', 'on_hold') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'health';
  end if;
  if p_from_summary is not null then
    select * into s from app.project_ai_summaries where id = p_from_summary and project_id = p.id and state = 'ready' for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'summary'; end if;
    v_health := coalesce(v_health, s.suggested_health);
    if v_health is null or v_health is distinct from s.suggested_health then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'health'; end if;
    v_source := 'ai_suggestion';
    update app.project_ai_summaries set applied_at = now(), applied_by = v_me where id = s.id;
  elsif v_health is not null then
    v_source := 'manual';
  end if;
  if v_health is not distinct from p.health and v_source is not distinct from p.health_source then
    return jsonb_build_object('id', p.id, 'version', p.version, 'health', p.health);
  end if;
  update app.projects set health = v_health, health_source = v_source, health_set_at = now(), health_set_by = v_me,
    version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('project', p.id, 'health', to_jsonb(p.health), to_jsonb(v_health), v_me, case when v_source = 'ai_suggestion' then 'assistant' else 'ui' end);
  perform app.log('project.health_set', 'project', p.id::text, jsonb_build_object('from', p.health, 'to', v_health, 'source', v_source));
  perform app.emit('project.health_changed', 'project', p.id, jsonb_build_object('from', p.health, 'to', v_health, 'source', v_source), p.is_sample);
  perform app.notify(f.staff_id, 'system', 'project.health_changed', jsonb_build_object('record', p.name, 'health', v_health, 'actor', (select name from app.admins where id = v_me)),
                     '/projects?project=' || p.id, 'project', p.id)
  from app.followers f where f.entity = 'project' and f.record_id = p.id and f.staff_id <> v_me;
  return jsonb_build_object('id', p.id, 'version', p.version + 1, 'health', v_health);
end $fn$;

-- close as done or cancelled, or open again (UF-20 step 6). Closing ends the stay in the phase; reopening starts one.
create function public.project_close(p_id uuid, p_status text, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true); v_me uuid := app.me();
begin
  if p_status is null or p_status not in ('open', 'done', 'canceled') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  perform app.prj_require_edit(p);
  if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
  if p.status = p_status then return jsonb_build_object('id', p.id, 'version', p.version, 'status', p.status); end if;
  if p_status = 'open' then
    update app.projects set status = 'open', closed_at = null, closed_by = null, version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
    insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, moved_by, source) values (p.id, p.board_id, p.phase_id, now(), v_me, 'ui');
    update app.projects set phase_entered_at = now() where id = p.id;
  else
    update app.projects set status = p_status, closed_at = now(), closed_by = v_me, version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
    update app.project_phase_history set left_at = now() where project_id = p.id and left_at is null;
  end if;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('project', p.id, 'status', to_jsonb(p.status), to_jsonb(p_status), v_me, 'ui');
  perform app.log(case when p_status = 'open' then 'project.reopened' else 'project.closed' end, 'project', p.id::text, jsonb_build_object('from', p.status, 'to', p_status));
  perform app.emit(case when p_status = 'open' then 'project.reopened' else 'project.completed' end, 'project', p.id, jsonb_build_object('status', p_status), p.is_sample);
  perform app.notify(f.staff_id, 'system', case when p_status = 'open' then 'project.reopened' else 'project.closed' end,
                     jsonb_build_object('record', p.name, 'status', p_status, 'actor', (select name from app.admins where id = v_me)), '/projects?project=' || p.id, 'project', p.id)
  from app.followers f where f.entity = 'project' and f.record_id = p.id and f.staff_id <> v_me;
  return jsonb_build_object('id', p.id, 'version', p.version + 1, 'status', p_status);
end $fn$;

-- link or unlink a deal; linking needs the deal visible (deals:see). One deal is primary: the first, or the one chosen.
create function public.project_deal_link(p_id uuid, p_deal uuid, p_on boolean, p_primary boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true); v_me uuid := app.me(); v_was boolean;
begin
  perform app.prj_require_edit(p);
  if p_on then
    perform app.require('deals', 'see');
    if not exists (select 1 from app.deals d where d.id = p_deal and d.deleted_at is null and app.visible(d.owner_id, d.visibility)) then
      raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal';
    end if;
    if coalesce(p_primary, false) then update app.project_deals set is_primary = false where project_id = p.id and deal_id <> p_deal and is_primary; end if;
    insert into app.project_deals (project_id, deal_id, is_primary, linked_by)
    values (p.id, p_deal, coalesce(p_primary, false) or not exists (select 1 from app.project_deals where project_id = p.id and is_primary), v_me)
    on conflict (project_id, deal_id) do update set is_primary = app.project_deals.is_primary or excluded.is_primary;
  else
    delete from app.project_deals where project_id = p.id and deal_id = p_deal returning is_primary into v_was;
    if coalesce(v_was, false) then
      update app.project_deals set is_primary = true
      where project_id = p.id and deal_id = (select deal_id from app.project_deals where project_id = p.id order by linked_at limit 1);
    end if;
  end if;
  update app.projects set version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
  values ('project', p.id, 'deals', jsonb_build_object('deal', p_deal, 'on', p_on, 'primary', coalesce(p_primary, false)), v_me, 'ui');
  perform app.log('project.deal_link', 'project', p.id::text, jsonb_build_object('deal', p_deal, 'on', p_on));
  return jsonb_build_object('id', p.id, 'version', p.version + 1,
    'deals', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'is_primary', pd.is_primary) order by pd.is_primary desc, pd.linked_at)
                       from app.project_deals pd join app.deals d on d.id = pd.deal_id where pd.project_id = p.id and d.deleted_at is null), '[]'::jsonb));
end $fn$;

-- the user has read the AI brief (PRJ-02): draft → reviewed
create function public.project_brief_review(p_id uuid, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true); v_me uuid := app.me();
begin
  perform app.prj_require_edit(p);
  if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
  if p.brief_state <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'brief_state'; end if;
  update app.projects set brief_state = 'reviewed', version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('project', p.id, 'brief_state', '"draft"', '"reviewed"', v_me, 'ui');
  return jsonb_build_object('id', p.id, 'version', p.version + 1, 'brief_state', 'reviewed');
end $fn$;

-- ===========================================================================
-- work items
-- ===========================================================================
-- replace an item's assignees: [{staff_id} | {person_id}]; staff are told, customer-side people are not (spec Q2)
create function app.prj_assignees_set(p app.projects, p_item uuid, p_name text, p_list jsonb) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); x jsonb; v_new uuid[] := '{}'; v_old uuid[];
begin
  if p_list is null or jsonb_typeof(p_list) = 'null' then p_list := '[]'::jsonb; end if;
  if jsonb_typeof(p_list) <> 'array' or jsonb_array_length(p_list) > 50 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignees'; end if;
  v_old := array(select staff_id from app.project_item_assignees where item_id = p_item and staff_id is not null);
  delete from app.project_item_assignees where item_id = p_item;
  for x in select * from jsonb_array_elements(p_list) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignees'; end if;
    if x ? 'staff_id' then
      if not exists (select 1 from app.admins a where a.id = app.prj_uuid(x, 'staff_id', 'assignees') and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignees';
      end if;
      insert into app.project_item_assignees (item_id, staff_id) values (p_item, app.prj_uuid(x, 'staff_id', 'assignees')) on conflict do nothing;
      v_new := v_new || app.prj_uuid(x, 'staff_id', 'assignees');
    elsif x ? 'person_id' then
      if not exists (select 1 from app.people pe where pe.id = app.prj_uuid(x, 'person_id', 'assignees') and pe.deleted_at is null) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignees';
      end if;
      insert into app.project_item_assignees (item_id, person_id) values (p_item, app.prj_uuid(x, 'person_id', 'assignees')) on conflict do nothing;
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignees';
    end if;
  end loop;
  perform app.notify(s, 'system', 'project.item_assigned', jsonb_build_object('record', p.name, 'item', p_name, 'actor', (select name from app.admins where id = v_me)),
                     '/projects?project=' || p.id, 'project', p.id)
  from unnest(v_new) s where s <> v_me and not s = any (v_old);
end $fn$;

-- create (p_id null) or change a task or milestone. Values: kind (create), name, description, owner_id, starts_on, due_on,
-- group_id, parent_id, completes_with_subtasks, assignees. The item's owner or staff assignee may change its content and
-- dates; who does it and where it sits need the project's edit right. → {id, version}
create function public.project_item_save(p_project uuid, p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  p app.projects := app.prj_get(p_project); v_me uuid := app.me(); i app.project_items; n app.project_items; v_editor boolean := app.prj_can_edit(p);
  v_kind text; c text; v_fields text[] := '{}'; v_owner uuid;
begin
  perform app.prj_keys(p_values, array['kind', 'name', 'description', 'owner_id', 'starts_on', 'due_on', 'group_id', 'parent_id', 'completes_with_subtasks', 'assignees']);
  if p_id is null then
    perform app.prj_require_edit(p);
    v_kind := coalesce(p_values ->> 'kind', 'task');
    if v_kind not in ('task', 'milestone') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
    v_owner := app.prj_uuid(p_values, 'owner_id');
    if v_owner is not null and not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
    if v_kind = 'milestone' and app.prj_date(p_values, 'starts_on') is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_on'; end if;
    if app.prj_date(p_values, 'due_on') < app.prj_date(p_values, 'starts_on') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'due_on'; end if;
    insert into app.project_items (project_id, kind, parent_id, group_id, name, description, owner_id, starts_on, due_on, completes_with_subtasks, ord, source,
                                   is_sample, created_by, updated_by)
    values (p.id, v_kind, app.prj_uuid(p_values, 'parent_id'), app.prj_uuid(p_values, 'group_id'), app.prj_text(p_values, 'name', 1, 300),
            app.prj_text(p_values, 'description', 0, 10000), v_owner, app.prj_date(p_values, 'starts_on'), app.prj_date(p_values, 'due_on'),
            coalesce((p_values ->> 'completes_with_subtasks')::boolean, false),
            coalesce((select max(ord) from app.project_items where project_id = p.id), 0) + 10, 'ui', p.is_sample, v_me, v_me)
    returning * into n;
    if p_values ? 'assignees' then perform app.prj_assignees_set(p, n.id, n.name, p_values -> 'assignees'); end if;
    if v_owner is not null and v_owner <> v_me then
      perform app.notify(v_owner, 'system', 'project.item_assigned', jsonb_build_object('record', p.name, 'item', n.name, 'actor', (select name from app.admins where id = v_me)),
                         '/projects?project=' || p.id, 'project', p.id);
    end if;
    perform app.prj_item_log(p.id, n.id, '*created', null, jsonb_build_object('kind', v_kind, 'name', n.name));
    perform app.emit('project_item.created', 'project_item', n.id, jsonb_build_object('project', p.id), p.is_sample);
    return jsonb_build_object('id', n.id, 'version', 1);
  end if;

  select * into i from app.project_items where id = p_id and project_id = p.id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not v_editor and not app.prj_item_mine(i) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'projects:edit_others'; end if;
  if not v_editor and (p_values ?| array['owner_id', 'assignees', 'group_id', 'parent_id']) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'projects:edit_others';
  end if;
  if p_version is not null and i.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = i.version::text; end if;
  if p_values ? 'kind' and p_values ->> 'kind' is distinct from i.kind then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if i.kind = 'activity' and (p_values - 'group_id' - 'kind') <> '{}'::jsonb then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = (select k from jsonb_object_keys(p_values - 'group_id' - 'kind') k limit 1);
  end if;
  n := i;
  if p_values ? 'name' then n.name := app.prj_text(p_values, 'name', 1, 300); end if;
  if p_values ? 'description' then n.description := app.prj_text(p_values, 'description', 0, 10000); end if;
  if p_values ? 'owner_id' then
    n.owner_id := app.prj_uuid(p_values, 'owner_id');
    if n.owner_id is not null and not exists (select 1 from app.admins a where a.id = n.owner_id and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
  end if;
  if p_values ? 'starts_on' then n.starts_on := app.prj_date(p_values, 'starts_on'); end if;
  if p_values ? 'due_on' then n.due_on := app.prj_date(p_values, 'due_on'); end if;
  if p_values ? 'group_id' then n.group_id := app.prj_uuid(p_values, 'group_id'); end if;
  if p_values ? 'parent_id' then n.parent_id := app.prj_uuid(p_values, 'parent_id'); end if;
  if p_values ? 'completes_with_subtasks' then n.completes_with_subtasks := coalesce((p_values ->> 'completes_with_subtasks')::boolean, false); end if;
  if n.kind = 'milestone' and n.starts_on is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_on'; end if;
  if n.due_on < n.starts_on then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'due_on'; end if;
  update app.project_items set name = n.name, description = n.description, owner_id = n.owner_id, starts_on = n.starts_on, due_on = n.due_on, group_id = n.group_id,
    parent_id = n.parent_id, completes_with_subtasks = n.completes_with_subtasks, version = version + 1, updated_at = now(), updated_by = v_me
  where id = i.id returning * into n;
  foreach c in array array['name', 'description', 'owner_id', 'starts_on', 'due_on', 'group_id', 'parent_id', 'completes_with_subtasks'] loop
    if (to_jsonb(i) -> c) is distinct from (to_jsonb(n) -> c) then
      perform app.prj_item_log(p.id, i.id, c, to_jsonb(i) -> c, to_jsonb(n) -> c);
      v_fields := v_fields || c;
    end if;
  end loop;
  if n.owner_id is distinct from i.owner_id and n.owner_id is not null and n.owner_id <> v_me then
    perform app.notify(n.owner_id, 'system', 'project.item_assigned', jsonb_build_object('record', p.name, 'item', n.name, 'actor', (select name from app.admins where id = v_me)),
                       '/projects?project=' || p.id, 'project', p.id);
  end if;
  if p_values ? 'assignees' then
    perform app.prj_assignees_set(p, i.id, n.name, p_values -> 'assignees');
    perform app.prj_item_log(p.id, i.id, 'assignees', null, p_values -> 'assignees');
    v_fields := v_fields || 'assignees'::text;
  end if;
  if cardinality(v_fields) > 0 then
    perform app.emit('project_item.updated', 'project_item', i.id, jsonb_build_object('project', p.id, 'fields', to_jsonb(v_fields)), p.is_sample);
  end if;
  return jsonb_build_object('id', n.id, 'version', n.version);
end $fn$;

-- done or not (PRJ-03): a milestone also reports «milestone reached»; an activity item completes its activity (ACT-01: the
-- deal's idle clock resets); a parent completes with its last subtask only when it says so. → {id, done, parent_completed}
create function app.prj_item_set_done(p app.projects, i app.project_items, p_done boolean) returns boolean
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.me(); a app.activities; par app.project_items; v_parent boolean := false;
begin
  if i.done = p_done then return false; end if;
  update app.project_items set done = p_done, done_at = case when p_done then now() end, done_by = case when p_done then v_me end,
    version = version + 1, updated_at = now(), updated_by = v_me where id = i.id;
  perform app.prj_item_log(p.id, i.id, 'done', to_jsonb(i.done), to_jsonb(p_done));
  if i.kind = 'activity' then
    select * into a from app.activities where id = i.activity_id for update;
    if found and a.done <> p_done then
      update app.activities set done = p_done, done_at = case when p_done then now() end, done_by = case when p_done then v_me end,
        version = version + 1, updated_at = now(), updated_by = v_me where id = a.id;
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id) values ('activity', a.id, 'done', to_jsonb(a.done), to_jsonb(p_done), v_me);
      if p_done and a.deal_id is not null then update app.deals set last_activity_at = now() where id = a.deal_id; end if;
      perform app.emit(case when p_done then 'activity.completed' else 'activity.reopened' end, 'activity', a.id, jsonb_build_object('deal', a.deal_id, 'project', p.id), a.is_sample);
    end if;
  end if;
  if p_done then
    perform app.emit('project.task_completed', 'project', p.id, jsonb_build_object('item', i.id, 'kind', i.kind), p.is_sample);
    if i.kind = 'milestone' then perform app.emit('project.milestone_reached', 'project', p.id, jsonb_build_object('item', i.id), p.is_sample); end if;
    if i.parent_id is not null then
      select * into par from app.project_items where id = i.parent_id and deleted_at is null for update;
      if found and par.completes_with_subtasks and not par.done
         and not exists (select 1 from app.project_items s where s.parent_id = par.id and s.deleted_at is null and not s.done) then
        perform app.prj_item_set_done(p, par, true);
        v_parent := true;
      end if;
    end if;
  else
    perform app.emit('project_item.reopened', 'project_item', i.id, jsonb_build_object('project', p.id), p.is_sample);
  end if;
  return v_parent;
end $fn$;

create function public.project_item_done(p_id uuid, p_done boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare i app.project_items; p app.projects; v_parent boolean;
begin
  perform app.require_module('projects');
  perform app.require('projects', 'see');
  select * into i from app.project_items where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  p := app.prj_get(i.project_id);
  if not app.prj_can_edit(p) and not app.prj_item_mine(i) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'projects:edit_others'; end if;
  if p_done is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'done'; end if;
  v_parent := app.prj_item_set_done(p, i, p_done);
  return jsonb_build_object('id', i.id, 'done', p_done, 'parent_completed', v_parent);
end $fn$;

-- «Paste a list» (PRJ-08): the app parses the lines (dates included) and sends the structured list, at most 200, into
-- one group. Items: [{name, due_on?, starts_on?, kind?, owner_id?}]. One project.updated event. → {ids, count}
create function public.project_items_add(p_project uuid, p_group uuid, p_items jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_me uuid := app.me(); x jsonb; k int := 0; v_ord int; v_id uuid; v_ids uuid[] := '{}'; v_kind text; v_owner uuid;
begin
  perform app.prj_require_edit(p);
  if p_group is not null and not exists (select 1 from app.project_groups g where g.id = p_group and g.project_id = p.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'items';
  end if;
  v_ord := coalesce((select max(ord) from app.project_items where project_id = p.id), 0);
  for x in select * from jsonb_array_elements(p_items) loop
    perform app.prj_keys(x, array['name', 'due_on', 'starts_on', 'kind', 'owner_id']);
    v_kind := coalesce(x ->> 'kind', 'task');
    if v_kind not in ('task', 'milestone') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].kind', k); end if;
    if v_kind = 'milestone' and app.prj_date(x, 'starts_on', format('items[%s].starts_on', k)) is not null then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].starts_on', k);
    end if;
    if app.prj_date(x, 'due_on', format('items[%s].due_on', k)) < app.prj_date(x, 'starts_on', format('items[%s].starts_on', k)) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].due_on', k);
    end if;
    v_owner := app.prj_uuid(x, 'owner_id', format('items[%s].owner_id', k));
    if v_owner is not null and not exists (select 1 from app.admins a where a.id = v_owner and a.active) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].owner_id', k);
    end if;
    v_ord := v_ord + 10;
    insert into app.project_items (project_id, kind, group_id, name, owner_id, starts_on, due_on, ord, source, is_sample, created_by, updated_by)
    values (p.id, v_kind, p_group, app.prj_text(x, 'name', 1, 300, format('items[%s].name', k)), v_owner,
            app.prj_date(x, 'starts_on', format('items[%s].starts_on', k)), app.prj_date(x, 'due_on', format('items[%s].due_on', k)), v_ord, 'paste', p.is_sample, v_me, v_me)
    returning id into v_id;
    perform app.prj_item_log(p.id, v_id, '*created', null, jsonb_build_object('kind', v_kind, 'source', 'paste'));
    v_ids := v_ids || v_id; k := k + 1;
  end loop;
  perform app.log('project.items_added', 'project', p.id::text, jsonb_build_object('count', k));
  perform app.emit('project.updated', 'project', p.id, jsonb_build_object('fields', jsonb_build_array('items'), 'count', k), p.is_sample);
  return jsonb_build_object('ids', to_jsonb(v_ids), 'count', k);
end $fn$;

-- bulk edit (D-41, «projects:bulk»): owner, a due-date shift in days, group, done
create function public.project_items_bulk(p_project uuid, p_ids uuid[], p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_me uuid := app.me(); i app.project_items; n int := 0; v_shift int; v_owner uuid; v_group uuid;
begin
  perform app.require('projects', 'bulk');
  perform app.prj_require_edit(p);
  perform app.prj_keys(p_values, array['owner_id', 'shift_days', 'group_id', 'done']);
  if p_ids is null or cardinality(p_ids) not between 1 and 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  if (select count(*) from app.project_items where id = any (p_ids) and project_id = p.id and deleted_at is null) <> cardinality(array(select distinct unnest(p_ids))) then
    raise exception 'not_found' using errcode = 'no_data_found', detail = 'ids';
  end if;
  v_shift := app.prj_int(p_values, 'shift_days', -3650, 3650);
  v_owner := app.prj_uuid(p_values, 'owner_id');
  if v_owner is not null and not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
  v_group := app.prj_uuid(p_values, 'group_id');
  if v_group is not null and not exists (select 1 from app.project_groups g where g.id = v_group and g.project_id = p.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id';
  end if;
  for i in select * from app.project_items where id = any (p_ids) and project_id = p.id and deleted_at is null order by ord for update loop
    if p_values ? 'owner_id' and i.kind <> 'activity' and i.owner_id is distinct from v_owner then
      update app.project_items set owner_id = v_owner, version = version + 1, updated_at = now(), updated_by = v_me where id = i.id;
      perform app.prj_item_log(p.id, i.id, 'owner_id', to_jsonb(i.owner_id), to_jsonb(v_owner));
    end if;
    if coalesce(v_shift, 0) <> 0 and i.kind <> 'activity' and (i.starts_on is not null or i.due_on is not null) then
      update app.project_items set starts_on = starts_on + v_shift, due_on = due_on + v_shift, version = version + 1, updated_at = now(), updated_by = v_me where id = i.id;
      perform app.prj_item_log(p.id, i.id, 'due_on', to_jsonb(i.due_on), to_jsonb(i.due_on + v_shift));
    end if;
    if p_values ? 'group_id' and i.group_id is distinct from v_group then
      update app.project_items set group_id = v_group, version = version + 1, updated_at = now(), updated_by = v_me where id = i.id;
      perform app.prj_item_log(p.id, i.id, 'group_id', to_jsonb(i.group_id), to_jsonb(v_group));
    end if;
    if p_values ? 'done' and jsonb_typeof(p_values -> 'done') = 'boolean' then
      select * into i from app.project_items where id = i.id;
      perform app.prj_item_set_done(p, i, (p_values ->> 'done')::boolean);
    end if;
    n := n + 1;
  end loop;
  perform app.log('project.items_bulk', 'project', p.id::text, jsonb_build_object('count', n, 'fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  perform app.emit('project.updated', 'project', p.id, jsonb_build_object('fields', jsonb_build_array('items'), 'count', n), p.is_sample);
  return jsonb_build_object('updated', n);
end $fn$;

-- remove items (with their subtasks and dependencies); an activity stays on its deal, unlinked from the project
create function public.project_items_delete(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'see'); i app.project_items; p app.projects; n int := 0;
begin
  perform app.require_module('projects');
  if p_ids is null or cardinality(p_ids) not between 1 and 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  for i in select * from app.project_items where id = any (p_ids) and deleted_at is null order by parent_id nulls first for update loop
    p := app.prj_get(i.project_id);
    perform app.prj_require_edit(p);
    continue when exists (select 1 from app.project_items x where x.id = i.id and x.deleted_at is not null);
    update app.project_items set deleted_at = now(), updated_at = now(), updated_by = v_me, version = version + 1
    where (id = i.id or parent_id = i.id) and deleted_at is null;
    delete from app.project_item_dependencies d where d.predecessor_id in (select x.id from app.project_items x where x.id = i.id or x.parent_id = i.id)
                                                  or d.successor_id in (select x.id from app.project_items x where x.id = i.id or x.parent_id = i.id);
    if i.kind = 'activity' then update app.activities set project_id = null where id = i.activity_id; end if;
    perform app.prj_item_log(p.id, i.id, '*deleted', null, null);
    perform app.emit('project_item.deleted', 'project_item', i.id, jsonb_build_object('project', p.id), p.is_sample);
    n := n + 1;
  end loop;
  return jsonb_build_object('deleted', n);
end $fn$;

create function public.project_items_reorder(p_project uuid, p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project);
begin
  perform app.prj_require_edit(p);
  if p_ids is null or cardinality(p_ids) = 0
     or exists (select 1 from unnest(p_ids) x where not exists (select 1 from app.project_items i where i.id = x and i.project_id = p.id and i.deleted_at is null)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids';
  end if;
  update app.project_items i set ord = x.n * 10 from unnest(p_ids) with ordinality x(id, n) where i.id = x.id;
  return jsonb_build_object('ok', true);
end $fn$;

-- an activity in the project (PRJ-03 RU: date, time and owner required). It is a real activity: on the primary deal,
-- in the calendar of its owner, in the deal's history. Values: type (key), subject, starts_at, owner_id, duration_min.
create function public.project_activity_add(p_project uuid, p_group uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_me uuid := app.me(); v_type uuid; v_owner uuid; v_at timestamptz; v_act uuid; v_id uuid; v_deal uuid; v_subject text;
begin
  perform app.prj_require_edit(p);
  perform app.prj_keys(p_values, array['type', 'subject', 'starts_at', 'owner_id', 'duration_min']);
  v_type := (select t.id from app.activity_types t where t.key = p_values ->> 'type' and t.active);
  if v_type is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type'; end if;
  v_subject := app.prj_text(p_values, 'subject', 1, 200);
  begin
    v_at := (p_values ->> 'starts_at')::timestamptz;
  exception when others then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at';
  end;
  if v_at is null or (p_values ->> 'starts_at') !~ 'T\d{2}:\d{2}' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'starts_at'; end if;
  v_owner := app.prj_uuid(p_values, 'owner_id');
  if v_owner is null or not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id'; end if;
  if p_group is not null and not exists (select 1 from app.project_groups g where g.id = p_group and g.project_id = p.id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id';
  end if;
  v_deal := (select pd.deal_id from app.project_deals pd where pd.project_id = p.id and pd.is_primary);
  insert into app.activities (type_id, subject, starts_at, duration_min, owner_id, visibility, project_id, deal_id, organization_id, person_id, is_sample, created_by, updated_by)
  values (v_type, v_subject, v_at, coalesce(app.prj_int(p_values, 'duration_min', 0, 1440), 30), v_owner, p.visibility, p.id, v_deal, p.organization_id, p.person_id,
          p.is_sample, v_me, v_me)
  returning id into v_act;
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values ('activity', v_act, '*created', jsonb_build_object('project', p.id), v_me, 'ui');
  perform app.emit('activity.created', 'activity', v_act, jsonb_build_object('project', p.id, 'deal', v_deal), p.is_sample);
  insert into app.project_items (project_id, kind, group_id, activity_id, ord, source, is_sample, created_by, updated_by)
  values (p.id, 'activity', p_group, v_act, coalesce((select max(ord) from app.project_items where project_id = p.id), 0) + 10, 'ui', p.is_sample, v_me, v_me)
  returning id into v_id;
  perform app.prj_item_log(p.id, v_id, '*created', null, jsonb_build_object('kind', 'activity', 'activity', v_act));
  perform app.emit('project_item.created', 'project_item', v_id, jsonb_build_object('project', p.id), p.is_sample);
  if v_owner <> v_me then
    perform app.notify(v_owner, 'system', 'project.item_assigned', jsonb_build_object('record', p.name, 'item', v_subject, 'actor', (select name from app.admins where id = v_me)),
                       '/projects?project=' || p.id, 'project', p.id);
  end if;
  return jsonb_build_object('id', v_id, 'activity_id', v_act);
end $fn$;

-- a dependency on or off (PRJ-04): tasks and milestones of one project, no cycle; → {ok, violated}
create function public.project_dependency_set(p_pred uuid, p_succ uuid, p_on boolean, p_lag int default 0) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare a app.project_items; b app.project_items; p app.projects; v_lag int := coalesce(p_lag, 0);
begin
  perform app.require_module('projects');
  perform app.require('projects', 'see');
  select * into a from app.project_items where id = p_pred and deleted_at is null;
  select * into b from app.project_items where id = p_succ and deleted_at is null;
  if a.id is null or b.id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  p := app.prj_get(b.project_id);
  perform app.prj_require_edit(p);
  if v_lag not between -365 and 365 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'lag_days'; end if;
  if p_on then
    insert into app.project_item_dependencies (predecessor_id, successor_id, lag_days, created_by) values (a.id, b.id, v_lag, app.me())
    on conflict (predecessor_id, successor_id) do update set lag_days = excluded.lag_days;
  else
    delete from app.project_item_dependencies where predecessor_id = a.id and successor_id = b.id;
  end if;
  perform app.prj_item_log(p.id, b.id, 'depends_on', null, jsonb_build_object('item', a.id, 'on', p_on, 'lag_days', v_lag));
  return jsonb_build_object('ok', true, 'violated', p_on and coalesce(b.starts_on, b.due_on) < coalesce(a.due_on, a.starts_on) + v_lag);
end $fn$;

create function public.project_group_save(p_project uuid, p_id uuid, p_name text, p_ord int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_id uuid;
begin
  perform app.prj_require_edit(p);
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_id is null then
    insert into app.project_groups (project_id, name, ord) values (p.id, btrim(p_name), coalesce(p_ord, (select coalesce(max(ord), 0) + 10 from app.project_groups where project_id = p.id)))
    returning id into v_id;
  else
    update app.project_groups set name = btrim(p_name), ord = coalesce(p_ord, ord) where id = p_id and project_id = p.id returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('project', p.id, 'groups', jsonb_build_object('group', v_id, 'name', btrim(p_name)), app.me());
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.project_group_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare g app.project_groups; p app.projects;
begin
  select * into g from app.project_groups where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  p := app.prj_get(g.project_id);
  perform app.prj_require_edit(p);
  delete from app.project_groups where id = g.id;              -- its items stay, ungrouped
  insert into app.changelog (entity, record_id, field, old_value, actor_id) values ('project', p.id, 'groups', jsonb_build_object('group', g.id, 'name', g.name), app.me());
  return jsonb_build_object('ok', true);
end $fn$;

-- drag a group bar (PRJ-04): every dated item in it moves by the same days, so its spacing is kept. Successors are not
-- moved (spec Q3); those that now start before their predecessor ends are returned as flagged.
create function public.project_group_shift(p_project uuid, p_group uuid, p_days int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_me uuid := app.me(); i app.project_items; a app.activities; n int := 0;
begin
  perform app.prj_require_edit(p);
  if not exists (select 1 from app.project_groups g where g.id = p_group and g.project_id = p.id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_id'; end if;
  if p_days is null or p_days = 0 or p_days not between -3650 and 3650 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'days'; end if;
  for i in select * from app.project_items where project_id = p.id and group_id = p_group and deleted_at is null for update loop
    if i.kind = 'activity' then
      select * into a from app.activities where id = i.activity_id and deleted_at is null and starts_at is not null for update;
      continue when not found;
      update app.activities set starts_at = starts_at + make_interval(days => p_days), version = version + 1, updated_at = now(), updated_by = v_me where id = a.id;
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id) values ('activity', a.id, 'starts_at', to_jsonb(a.starts_at), to_jsonb(a.starts_at + make_interval(days => p_days)), v_me);
    else
      continue when i.starts_on is null and i.due_on is null;
      update app.project_items set starts_on = starts_on + p_days, due_on = due_on + p_days, version = version + 1, updated_at = now(), updated_by = v_me where id = i.id;
      if i.starts_on is not null then perform app.prj_item_log(p.id, i.id, 'starts_on', to_jsonb(i.starts_on), to_jsonb(i.starts_on + p_days)); end if;
      if i.due_on is not null then perform app.prj_item_log(p.id, i.id, 'due_on', to_jsonb(i.due_on), to_jsonb(i.due_on + p_days)); end if;
    end if;
    n := n + 1;
  end loop;
  perform app.emit('project.updated', 'project', p.id, jsonb_build_object('fields', jsonb_build_array('items'), 'count', n), p.is_sample);
  return jsonb_build_object('shifted', n, 'flagged', coalesce((
    select jsonb_agg(jsonb_build_object('predecessor', d.predecessor_id, 'successor', d.successor_id))
    from app.project_item_dependencies d join app.project_items x on x.id = d.predecessor_id join app.project_items y on y.id = d.successor_id
    where x.project_id = p.id and x.deleted_at is null and y.deleted_at is null and (x.group_id = p_group or y.group_id = p_group)
      and coalesce(y.starts_on, y.due_on) < coalesce(x.due_on, x.starts_on) + d.lag_days), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- templates (PRJ-05) and configuration
-- ===========================================================================
-- create or replace a template with its groups, items and dependencies as one set. Values: name, description,
-- organized_by, board_id, groups [{key, name, ord, phase_id}], items [{key, group, parent, kind, name, start_offset_days,
-- due_offset_days, activity_type, activity_time 'HH:MM', activity_duration_min, assignee, completes_with_subtasks, ord}],
-- dependencies [{pred, succ, lag_days}] (keys are the caller's own strings). → {id, version}
create function public.project_template_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('projects', 'see'); t app.project_templates; v_id uuid := p_id; v_name text; v_board uuid; v_org text;
  x jsonb; k int; v_gmap jsonb := '{}'::jsonb; v_imap jsonb := '{}'::jsonb; v_pass int; v_new uuid; v_type uuid; v_detail text; v_msg text;
begin
  perform app.require_module('projects');
  perform app.prj_keys(p_values, array['name', 'description', 'organized_by', 'board_id', 'groups', 'items', 'dependencies']);
  if p_id is null then
    perform app.require('projects', 'add');
  else
    select * into t from app.project_templates where id = p_id and deleted_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if t.created_by is not distinct from v_me then perform app.require('projects', 'add'); else perform app.require('projects', 'configure'); end if;
    if p_version is not null and t.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = t.version::text; end if;
  end if;
  v_name := case when p_id is null or p_values ? 'name' then app.prj_text(p_values, 'name', 1, 120) else t.name end;
  v_org := coalesce(p_values ->> 'organized_by', t.organized_by, 'phases');
  if v_org not in ('phases', 'groups') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'organized_by'; end if;
  v_board := case when p_values ? 'board_id' then app.prj_uuid(p_values, 'board_id') else t.board_id end;
  if v_board is not null and not exists (select 1 from app.project_boards b where b.id = v_board) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'board_id'; end if;
  begin
    if p_id is null then
      insert into app.project_templates (name, description, organized_by, board_id, is_sample, created_by, updated_by)
      values (v_name, app.prj_text(p_values, 'description', 0, 500), v_org, v_board, coalesce((select sandbox from app.admins where id = v_me), false), v_me, v_me)
      returning id into v_id;
    else
      update app.project_templates set name = v_name,
        description = case when p_values ? 'description' then app.prj_text(p_values, 'description', 0, 500) else description end,
        organized_by = v_org, board_id = v_board, version = version + 1, updated_at = now(), updated_by = v_me
      where id = p_id;
    end if;
  exception when unique_violation then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end;

  if p_id is null or p_values ?| array['groups', 'items', 'dependencies'] then
    delete from app.project_template_items where template_id = v_id;
    delete from app.project_template_groups where template_id = v_id;
    if jsonb_typeof(coalesce(p_values -> 'groups', '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_values -> 'items', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_values -> 'dependencies', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_values -> 'items', '[]'::jsonb)) > 500 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'items';
    end if;
    k := 0;
    for x in select * from jsonb_array_elements(coalesce(p_values -> 'groups', '[]'::jsonb)) loop
      perform app.prj_keys(x, array['key', 'name', 'ord', 'phase_id']);
      if jsonb_typeof(x -> 'key') not in ('string', 'number') or v_gmap ? (x ->> 'key') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('groups[%s].key', k); end if;
      if app.prj_uuid(x, 'phase_id', format('groups[%s].phase_id', k)) is not null
         and not exists (select 1 from app.project_phases ph where ph.id = app.prj_uuid(x, 'phase_id', format('groups[%s].phase_id', k))) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('groups[%s].phase_id', k);
      end if;
      insert into app.project_template_groups (template_id, name, ord, phase_id)
      values (v_id, app.prj_text(x, 'name', 1, 80, format('groups[%s].name', k)), coalesce(app.prj_int(x, 'ord', -100000, 100000, format('groups[%s].ord', k)), (k + 1) * 10),
              app.prj_uuid(x, 'phase_id', format('groups[%s].phase_id', k)))
      returning id into v_new;
      v_gmap := v_gmap || jsonb_build_object(x ->> 'key', v_new);
      k := k + 1;
    end loop;
    -- items: those without a parent first, so a subtask finds its parent
    for v_pass in 1 .. 2 loop
      k := 0;
      for x in select * from jsonb_array_elements(coalesce(p_values -> 'items', '[]'::jsonb)) loop
        if (v_pass = 1) = (jsonb_typeof(x -> 'parent') is null or jsonb_typeof(x -> 'parent') = 'null') then
          perform app.prj_keys(x, array['key', 'group', 'parent', 'kind', 'name', 'start_offset_days', 'due_offset_days', 'activity_type', 'activity_time',
                                        'activity_duration_min', 'assignee', 'completes_with_subtasks', 'ord']);
          if jsonb_typeof(x -> 'key') not in ('string', 'number') or v_imap ? (x ->> 'key') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].key', k); end if;
          if x ->> 'group' is not null and not v_gmap ? (x ->> 'group') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].group', k); end if;
          if x ->> 'parent' is not null and not v_imap ? (x ->> 'parent') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].parent', k); end if;
          if coalesce(x ->> 'kind', 'task') not in ('task', 'milestone', 'activity') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].kind', k); end if;
          if coalesce(x ->> 'assignee', 'unassigned') not in ('owner', 'unassigned') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].assignee', k); end if;
          v_type := null;
          if x ->> 'kind' = 'activity' then
            v_type := (select ty.id from app.activity_types ty where ty.key = x ->> 'activity_type' and ty.active);
            if v_type is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].activity_type', k); end if;
            if coalesce(x ->> 'activity_time', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].activity_time', k); end if;
          end if;
          begin
            insert into app.project_template_items (template_id, group_id, parent_id, kind, name, start_offset_days, due_offset_days, activity_type_id, activity_time,
                                                    activity_duration_min, assignee, completes_with_subtasks, ord)
            values (v_id, (v_gmap ->> (x ->> 'group'))::uuid, (v_imap ->> (x ->> 'parent'))::uuid, coalesce(x ->> 'kind', 'task'),
                    app.prj_text(x, 'name', 1, 300, format('items[%s].name', k)),
                    app.prj_int(x, 'start_offset_days', 0, 3650, format('items[%s].start_offset_days', k)), app.prj_int(x, 'due_offset_days', 0, 3650, format('items[%s].due_offset_days', k)),
                    v_type, case when x ->> 'kind' = 'activity' then (x ->> 'activity_time')::time end,
                    app.prj_int(x, 'activity_duration_min', 0, 1440, format('items[%s].activity_duration_min', k)),
                    coalesce(x ->> 'assignee', 'unassigned'), coalesce((x ->> 'completes_with_subtasks')::boolean, false),
                    coalesce(app.prj_int(x, 'ord', -100000, 100000, format('items[%s].ord', k)), (k + 1) * 10))
            returning id into v_new;
          exception when check_violation then
            raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s]', k);
          when invalid_parameter_value then
            get stacked diagnostics v_detail = pg_exception_detail, v_msg = message_text;
            if v_msg <> 'invalid' or v_detail like 'items[%' then raise; end if;
            raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('items[%s].%s', k, replace(v_detail, '_id', ''));
          end;
          v_imap := v_imap || jsonb_build_object(x ->> 'key', v_new);
        end if;
        k := k + 1;
      end loop;
    end loop;
    k := 0;
    for x in select * from jsonb_array_elements(coalesce(p_values -> 'dependencies', '[]'::jsonb)) loop
      perform app.prj_keys(x, array['pred', 'succ', 'lag_days']);
      if not v_imap ? coalesce(x ->> 'pred', '') or not v_imap ? coalesce(x ->> 'succ', '') or x ->> 'pred' = x ->> 'succ' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('dependencies[%s]', k);
      end if;
      insert into app.project_template_dependencies (template_id, predecessor_id, successor_id, lag_days)
      values (v_id, (v_imap ->> (x ->> 'pred'))::uuid, (v_imap ->> (x ->> 'succ'))::uuid, coalesce(app.prj_int(x, 'lag_days', -365, 365, format('dependencies[%s].lag_days', k)), 0))
      on conflict do nothing;
      k := k + 1;
    end loop;
  end if;
  perform app.log('template.saved', 'project_template', v_id::text, jsonb_build_object('created', p_id is null,
                  'items', (select count(*) from app.project_template_items where template_id = v_id)));
  return jsonb_build_object('id', v_id, 'version', (select version from app.project_templates where id = v_id));
end $fn$;

-- «Save as template» (D-41): groups, items with offsets from the project's start (items before it at day 0), activities
-- with their day and time of day, dependencies
create function public.project_template_from_project(p_project uuid, p_name text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_project); v_tz text; r jsonb;
begin
  perform app.require('projects', 'add');
  v_tz := coalesce((select a.time_zone from app.admins a where a.id = p.owner_id), 'Europe/Oslo');
  r := public.project_template_save(null, jsonb_build_object(
    'name', p_name, 'organized_by', 'groups', 'board_id', p.board_id,
    'groups', coalesce((select jsonb_agg(jsonb_build_object('key', g.id, 'name', g.name, 'ord', g.ord, 'phase_id', g.phase_id) order by g.ord)
                        from app.project_groups g where g.project_id = p.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'key', i.id, 'group', i.group_id, 'parent', i.parent_id, 'kind', i.kind, 'name', coalesce(i.name, a.subject),
        'start_offset_days', case when i.kind = 'task' and i.starts_on is not null and p.starts_on is not null then greatest(0, i.starts_on - p.starts_on) end,
        'due_offset_days', case when i.kind = 'activity' and p.starts_on is not null then greatest(0, (a.starts_at at time zone v_tz)::date - p.starts_on)
                                when i.due_on is not null and p.starts_on is not null then greatest(0, i.due_on - p.starts_on) end,
        'activity_type', (select ty.key from app.activity_types ty where ty.id = a.type_id),
        'activity_time', case when a.id is not null then to_char(a.starts_at at time zone v_tz, 'HH24:MI') end,
        'activity_duration_min', a.duration_min,
        'assignee', case when coalesce(i.owner_id, a.owner_id) is not distinct from p.owner_id and p.owner_id is not null then 'owner' else 'unassigned' end,
        'completes_with_subtasks', i.completes_with_subtasks, 'ord', i.ord)) order by i.ord)
      from app.project_items i left join app.activities a on a.id = i.activity_id
      where i.project_id = p.id and i.deleted_at is null and (i.kind <> 'activity' or (a.id is not null and a.starts_at is not null))), '[]'::jsonb),
    'dependencies', coalesce((select jsonb_agg(jsonb_build_object('pred', d.predecessor_id, 'succ', d.successor_id, 'lag_days', d.lag_days))
                              from app.project_item_dependencies d join app.project_items x on x.id = d.predecessor_id join app.project_items y on y.id = d.successor_id
                              where x.project_id = p.id and x.deleted_at is null and y.deleted_at is null), '[]'::jsonb)));
  update app.project_templates set source_project_id = p.id where id = (r ->> 'id')::uuid;
  return r;
end $fn$;

create function public.project_template_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'see'); t app.project_templates;
begin
  perform app.require_module('projects');
  select * into t from app.project_templates where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.created_by is not distinct from v_me then perform app.require('projects', 'add'); else perform app.require('projects', 'configure'); end if;
  update app.project_templates set deleted_at = now(), updated_at = now(), updated_by = v_me, version = version + 1 where id = t.id;
  perform app.log('template.deleted', 'project_template', t.id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- boards and phases («projects:configure»); a new board may bring its phases: {name, ord, archived, phases: [{name, color}]}
create function public.project_board_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'configure'); v_id uuid; x jsonb; k int := 0;
begin
  perform app.require_module('projects');
  perform app.prj_keys(p_values, array['name', 'ord', 'archived', 'phases']);
  begin
    if p_id is null then
      insert into app.project_boards (name, ord, is_sample, created_by)
      values (app.prj_text(p_values, 'name', 1, 80), coalesce(app.prj_int(p_values, 'ord', -100000, 100000), (select coalesce(max(ord), 0) + 10 from app.project_boards)),
              coalesce((select sandbox from app.admins where id = v_me), false), v_me)
      returning id into v_id;
      for x in select * from jsonb_array_elements(case when jsonb_typeof(p_values -> 'phases') = 'array' then p_values -> 'phases' else '[]'::jsonb end) loop
        perform app.prj_keys(x, array['name', 'color']);
        if coalesce(x ->> 'color', '#F2EAD6') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = format('phases[%s].color', k); end if;
        insert into app.project_phases (board_id, name, ord, color) values (v_id, app.prj_text(x, 'name', 1, 60, format('phases[%s].name', k)), (k + 1) * 10, upper(coalesce(x ->> 'color', '#F2EAD6')));
        k := k + 1;
      end loop;
    else
      if p_values ? 'phases' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'phases'; end if;
      update app.project_boards set
        name = case when p_values ? 'name' then app.prj_text(p_values, 'name', 1, 80) else name end,
        ord = coalesce(app.prj_int(p_values, 'ord', -100000, 100000), ord),
        archived_at = case when (p_values ->> 'archived')::boolean then coalesce(archived_at, now()) when p_values ? 'archived' then null else archived_at end
      where id = p_id returning id into v_id;
      if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    end if;
  exception when unique_violation then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = case when k > 0 then format('phases[%s].name', k) else 'name' end;
  end;
  perform app.log('project_board.saved', 'project_board', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.project_phase_save(p_id uuid, p_board uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('projects', 'configure');
  perform app.require_module('projects');
  perform app.prj_keys(p_values, array['name', 'color', 'ord']);
  if p_values ? 'color' and coalesce(p_values ->> 'color', '') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'color'; end if;
  begin
    if p_id is null then
      if not exists (select 1 from app.project_boards b where b.id = p_board) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'board'; end if;
      insert into app.project_phases (board_id, name, ord, color)
      values (p_board, app.prj_text(p_values, 'name', 1, 60), coalesce(app.prj_int(p_values, 'ord', -100000, 100000), (select coalesce(max(ord), 0) + 10 from app.project_phases where board_id = p_board)),
              upper(coalesce(p_values ->> 'color', '#F2EAD6')))
      returning id into v_id;
    else
      update app.project_phases set name = case when p_values ? 'name' then app.prj_text(p_values, 'name', 1, 60) else name end,
        color = upper(coalesce(p_values ->> 'color', color)), ord = coalesce(app.prj_int(p_values, 'ord', -100000, 100000), ord)
      where id = p_id returning id into v_id;
      if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    end if;
  exception when unique_violation then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end;
  perform app.log('project_phase.saved', 'project_phase', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.project_phases_reorder(p_board uuid, p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('projects', 'configure');
  perform app.require_module('projects');
  if p_ids is null or (select count(*) from app.project_phases where board_id = p_board) <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) x where not exists (select 1 from app.project_phases ph where ph.id = x and ph.board_id = p_board)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids';
  end if;
  update app.project_phases ph set ord = x.n * 10 from unnest(p_ids) with ordinality x(id, n) where ph.id = x.id;
  perform app.log('project_phase.reordered', 'project_board', p_board::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- deleting a phase moves its projects to another phase of the same board first (as stage_delete)
create function public.project_phase_delete(p_phase uuid, p_target uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'configure'); ph app.project_phases; p app.projects; n int := 0;
begin
  perform app.require_module('projects');
  select * into ph from app.project_phases where id = p_phase;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_target is null or p_target = p_phase or not exists (select 1 from app.project_phases x where x.id = p_target and x.board_id = ph.board_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'target';
  end if;
  for p in select * from app.projects where phase_id = p_phase for update loop
    if p.status = 'open' and p.deleted_at is null then
      perform app.prj_move_to(p, p_target, 'system');
    else
      update app.projects set phase_id = p_target, version = version + 1, updated_at = now(), updated_by = v_me where id = p.id;
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('project', p.id, 'phase_id', to_jsonb(p_phase), to_jsonb(p_target), v_me, 'system');
    end if;
    n := n + 1;
  end loop;
  delete from app.project_phases where id = p_phase;
  perform app.log('project_phase.deleted', 'project_phase', p_phase::text, jsonb_build_object('target', p_target, 'moved', n));
  return jsonb_build_object('moved', n);
end $fn$;

-- ===========================================================================
-- AI, status reports, export
-- ===========================================================================
-- an AI health summary (PRJ-06): queued for the AI worker; one pending request per project
create function public.project_ai_summary_request(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id); v_id uuid;
begin
  perform app.prj_ai_check();
  select id into v_id from app.project_ai_summaries where project_id = p.id and state = 'requested';
  if v_id is not null then return jsonb_build_object('id', v_id, 'state', 'requested'); end if;
  insert into app.project_ai_summaries (project_id, requested_by) values (p.id, app.me()) returning id into v_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'project_ai_summary', 'summary_id', v_id, 'project_id', p.id));
  perform app.log('project.ai_summary_requested', 'project', p.id::text);
  return jsonb_build_object('id', v_id, 'state', 'requested');
end $fn$;

-- an AI brief into the description (PRJ-02), from the linked deal's notes, mails and files
create function public.project_brief_request(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id, true);
begin
  perform app.prj_require_edit(p);
  perform app.prj_ai_check();
  if p.brief_state <> 'drafting' then
    update app.projects set brief_state = 'drafting' where id = p.id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'project_brief', 'project_id', p.id, 'staff_id', app.me()));
    perform app.log('project.brief_requested', 'project', p.id::text);
  end if;
  return jsonb_build_object('id', p.id, 'brief_state', 'drafting');
end $fn$;

-- a status report (PRJ-07): «the PDF contains only what the sender chooses». Sections: summary, milestones, done_since
-- (a date), open_overdue, upcoming, note_ids (notes of this project). A hand-written summary needs no AI; p_ai_draft
-- asks the AI worker to draft it. The PDF worker renders it into the project's files. → {id, state}
create function public.project_status_report_request(p_id uuid, p_sections jsonb, p_summary text default null, p_ai_draft boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects := app.prj_get(p_id); v_id uuid; v_notes uuid[];
begin
  perform app.prj_keys(p_sections, array['summary', 'milestones', 'done_since', 'open_overdue', 'upcoming', 'note_ids']);
  if exists (select 1 from jsonb_each(p_sections - 'done_since' - 'note_ids') x where jsonb_typeof(x.value) <> 'boolean') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sections';
  end if;
  perform app.prj_date(p_sections, 'done_since', 'sections.done_since');
  v_notes := app.prj_uuids(p_sections -> 'note_ids', 'sections.note_ids');
  if exists (select 1 from unnest(v_notes) x where not exists (select 1 from app.notes n where n.id = x and n.entity = 'project' and n.record_id = p.id and n.deleted_at is null)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sections.note_ids';
  end if;
  if not exists (select 1 from jsonb_each(p_sections - 'done_since' - 'note_ids') x where x.value = 'true'::jsonb)
     and p_sections ->> 'done_since' is null and cardinality(v_notes) = 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sections';
  end if;
  if char_length(p_summary) > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'summary'; end if;
  if coalesce(p_ai_draft, false) then perform app.prj_ai_check(); end if;
  insert into app.project_status_reports (project_id, sections, summary, ai_drafted, requested_by)
  values (p.id, p_sections, nullif(btrim(p_summary), ''), coalesce(p_ai_draft, false), app.me()) returning id into v_id;
  perform pgmq.send('jobs', jsonb_build_object('job', 'project_status_report', 'report_id', v_id, 'project_id', p.id, 'ai_draft', coalesce(p_ai_draft, false)));
  perform app.log('project.status_report_requested', 'project', p.id::text, jsonb_build_object('report', v_id, 'ai_draft', coalesce(p_ai_draft, false)));
  return jsonb_build_object('id', v_id, 'state', 'requested');
end $fn$;

-- a cell as text a spreadsheet will not run as a formula (A7.6)
create function app.prj_cell(p_value text) returns text
  language sql immutable set search_path = ''
as $fn$ select case when p_value ~ '^[=+\-@\t\r]' then '''' || p_value else p_value end $fn$;

-- export (PRJ-08, «projects:export», audited): a board's projects, or one project's items, as columns and rows the app
-- writes to CSV or XLSX. Column keys are message keys.
create function public.project_export(p_board uuid, p_project uuid, p_format text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('projects', 'export'); v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false);
        p app.projects; v_rows jsonb; v_cols jsonb; v_scope text;
begin
  perform app.require_module('projects');
  if p_format is null or p_format not in ('csv', 'xlsx') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'format'; end if;
  if p_project is not null then
    p := app.prj_get(p_project);
    v_scope := 'project';
    v_cols := '["kind","name","group","parent","owner","assignees","starts_on","due_on","done","done_at","depends_on"]';
    select coalesce(jsonb_agg(jsonb_build_array(i.kind, app.prj_cell(coalesce(i.name, a.subject)), app.prj_cell(g.name), app.prj_cell(par.name),
             app.prj_cell((select s.name from app.admins s where s.id = coalesce(i.owner_id, a.owner_id))),
             app.prj_cell((select string_agg(coalesce(s.name, pe.name), ', ') from app.project_item_assignees x left join app.admins s on s.id = x.staff_id
                           left join app.people pe on pe.id = x.person_id where x.item_id = i.id)),
             coalesce(i.starts_on, (a.starts_at at time zone 'Europe/Oslo')::date), i.due_on, i.done, i.done_at,
             app.prj_cell((select string_agg(pr.name, ', ') from app.project_item_dependencies d join app.project_items pr on pr.id = d.predecessor_id
                           where d.successor_id = i.id and pr.deleted_at is null))) order by g.ord nulls last, i.ord), '[]'::jsonb)
    into v_rows
    from app.project_items i left join app.activities a on a.id = i.activity_id left join app.project_groups g on g.id = i.group_id
         left join app.project_items par on par.id = i.parent_id
    where i.project_id = p.id and i.deleted_at is null;
  else
    perform app.require('projects', 'see');
    if not exists (select 1 from app.project_boards b where b.id = p_board) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'board'; end if;
    v_scope := 'board';
    v_cols := '["seq","name","phase","status","health","owner","organization","person","deal","starts_on","ends_on","done","total"]';
    select coalesce(jsonb_agg(jsonb_build_array('P-' || t.seq, app.prj_cell(t.name), app.prj_cell(ph.name), t.status, t.health,
             app.prj_cell((select s.name from app.admins s where s.id = t.owner_id)), app.prj_cell((select o.name from app.organizations o where o.id = t.organization_id)),
             app.prj_cell((select pe.name from app.people pe where pe.id = t.person_id)), app.prj_cell(app.prj_card(t) -> 'deal' ->> 'title'),
             t.starts_on, t.ends_on, (app.prj_card(t) ->> 'done')::int, (app.prj_card(t) ->> 'total')::int) order by ph.ord, t.seq), '[]'::jsonb)
    into v_rows
    from app.projects t join app.project_phases ph on ph.id = t.phase_id
    where t.board_id = p_board and t.deleted_at is null and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample);
  end if;
  perform app.log('record.exported', 'project', p_project::text, jsonb_build_object('rows', jsonb_array_length(v_rows), 'format', p_format, 'scope', v_scope));
  perform app.emit('export.created', 'project', p_project, jsonb_build_object('rows', jsonb_array_length(v_rows), 'format', p_format));
  return jsonb_build_object('format', p_format, 'scope', v_scope, 'columns', v_cols, 'rows', v_rows);
end $fn$;

-- ===========================================================================
-- record files (generic, CRM-05): a file goes with its record and is fetched only by someone who may see the record
-- ===========================================================================
create function app.file_entity(p_entity text) returns app.entities
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity);
begin
  if e.key in ('email_thread', 'document', 'document_template') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  perform app.require(e.scope, 'see');
  return e;
end $fn$;

create function app.record_visible(e app.entities, p_id uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v boolean;
begin
  execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null and %s)', e.tbl, p_id, app.vis_sql(e)) into v;
  return v;
end $fn$;

-- the owner, or «Edit others' records» (an unowned type: add or edit_others), as rec_save decides
create function app.record_editable(e app.entities, p_id uuid) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_owner uuid;
begin
  if not e.owned then return app.can(e.scope, 'add') or app.can(e.scope, 'edit_others'); end if;
  execute format('select t.owner_id from app.%I t where t.id = %L', e.tbl, p_id) into v_owner;
  return v_owner is not distinct from app.me() and app.me() is not null or app.can(e.scope, 'edit_others');
end $fn$;

create function public.files_list(p_entity text, p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.file_entity(p_entity);
begin
  if not app.record_visible(e, p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'filename', f.filename, 'mime', f.mime, 'size_bytes', f.size_bytes, 'source', f.source,
                                                       'uploaded_by', (select a.name from app.admins a where a.id = f.uploaded_by), 'created_at', f.created_at,
                                                       'can_delete', f.uploaded_by = app.me() or app.record_editable(e, p_id)) order by f.created_at desc)
                   from app.record_files f where f.entity = e.key and f.record_id = p_id and f.deleted_at is null and f.ready_at is not null), '[]'::jsonb);
end $fn$;

-- a pending file row and the place the edge function signs an upload for (A7.5: type, extension and size checked)
create function public.file_upload_begin(p_entity text, p_id uuid, p_filename text, p_mime text, p_size bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.file_entity(p_entity); v_me uuid := app.me(); v_name text := btrim(p_filename); v_id uuid := gen_random_uuid(); v_path text; v_ext text; v_want text;
begin
  if not app.record_visible(e, p_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if not app.record_editable(e, p_id) then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others'; end if;
  if p_mime is null or p_mime not in ('application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
                                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                      'application/vnd.openxmlformats-officedocument.presentationml.presentation') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mime';
  end if;
  v_ext := lower(substring(coalesce(v_name, '') from '\.([A-Za-z0-9]{1,5})$'));
  v_want := case p_mime when 'application/pdf' then 'pdf' when 'image/png' then 'png' when 'text/csv' then 'csv' when 'text/plain' then 'txt'
                        when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx'
                        when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'xlsx'
                        when 'application/vnd.openxmlformats-officedocument.presentationml.presentation' then 'pptx'
                        when 'image/jpeg' then case when v_ext = 'jpeg' then 'jpeg' else 'jpg' end end;
  if v_name is null or char_length(v_name) not between 1 and 255 or v_name ~ '[/\\[:cntrl:]]' or v_ext is distinct from v_want then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filename';
  end if;
  if p_size is null or p_size not between 1 and 26214400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'size'; end if;
  v_path := e.key || '/' || p_id || '/' || v_id || '/' || left(regexp_replace(v_name, '[^A-Za-z0-9._-]', '_', 'g'), 200);
  insert into app.record_files (id, entity, record_id, storage_path, filename, mime, size_bytes, source, uploaded_by, is_sample)
  values (v_id, e.key, p_id, v_path, v_name, p_mime, p_size, 'upload', v_me, coalesce((select sandbox from app.admins where id = v_me), false));
  perform app.log('file.upload_started', e.key, p_id::text, jsonb_build_object('file', v_id, 'size', p_size, 'mime', p_mime));
  return jsonb_build_object('id', v_id, 'bucket', 'record-files', 'path', v_path, 'expires_in', 300);
end $fn$;

create function public.file_upload_done(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.record_files; e app.entities; v_me uuid := app.require_staff();
begin
  select * into f from app.record_files where id = p_id and deleted_at is null and ready_at is null and uploaded_by = v_me for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  e := app.file_entity(f.entity);
  if not app.record_visible(e, f.record_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  update app.record_files set ready_at = now() where id = f.id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values (e.key, f.record_id, 'files', jsonb_build_object('file', f.id, 'filename', f.filename), v_me);
  perform app.log('file.attached', e.key, f.record_id::text, jsonb_build_object('file', f.id, 'size', f.size_bytes));
  perform app.emit('file.attached', e.key, f.record_id, jsonb_build_object('file', f.id), f.is_sample);
  return jsonb_build_object('id', f.id);
end $fn$;

-- where the edge function signs a download (SQL cannot sign a Storage URL, V-P5-06)
create function public.file_download_url(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.record_files; e app.entities;
begin
  perform app.require_staff();
  select * into f from app.record_files where id = p_id and deleted_at is null and ready_at is not null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  e := app.file_entity(f.entity);
  if not app.record_visible(e, f.record_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('file.read', e.key, f.record_id::text, jsonb_build_object('file', f.id));
  return jsonb_build_object('bucket', 'record-files', 'path', f.storage_path, 'expires_in', 300, 'filename', f.filename, 'mime', f.mime);
end $fn$;

create function public.file_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare f app.record_files; e app.entities; v_me uuid := app.require_staff();
begin
  select * into f from app.record_files where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  e := app.file_entity(f.entity);
  if not app.record_visible(e, f.record_id) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if f.uploaded_by is distinct from v_me and not app.record_editable(e, f.record_id) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
  end if;
  update app.record_files set deleted_at = now() where id = f.id;
  if f.ready_at is not null then
    insert into app.changelog (entity, record_id, field, old_value, actor_id) values (e.key, f.record_id, 'files', jsonb_build_object('file', f.id, 'filename', f.filename), v_me);
  end if;
  perform app.log('file.deleted', e.key, f.record_id::text, jsonb_build_object('file', f.id));
  return jsonb_build_object('ok', true);
end $fn$;

-- files-purge (§8.2): removed files after 30 days, uploads never confirmed after a day; the worker deletes the objects
create function app.files_purge() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_paths text[];
begin
  with d as (delete from app.record_files where deleted_at < now() - interval '30 days' or (ready_at is null and deleted_at is null and created_at < now() - interval '1 day')
             returning storage_path)
  select array_agg(storage_path) into v_paths from d;
  if cardinality(v_paths) > 0 then
    perform pgmq.send('jobs', jsonb_build_object('job', 'files_purge', 'bucket', 'record-files', 'paths', to_jsonb(v_paths)));
  end if;
  return coalesce(cardinality(v_paths), 0);
end $fn$;
select cron.schedule('platform-files-purge', '41 3 * * *', 'select app.files_purge()');

-- ===========================================================================
-- workers (service role only)
-- ===========================================================================
-- p_result: {state: 'ready' | 'failed', suggested_health, summary, recommendations: [text ≤ 300] (≤ 5), sources: [{entity, id, kind}]}
create function public.worker_project_summary_ready(p_id uuid, p_result jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare s app.project_ai_summaries; v_ok boolean := coalesce(p_result ->> 'state', '') = 'ready'; p app.projects;
begin
  select * into s from app.project_ai_summaries where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if s.state <> 'requested' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if v_ok then
    if coalesce(p_result ->> 'suggested_health', 'on_track') not in ('on_track', 'at_risk', 'off_track', 'on_hold') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'suggested_health';
    end if;
    if char_length(p_result ->> 'summary') > 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'summary'; end if;
    if jsonb_typeof(coalesce(p_result -> 'recommendations', '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_result -> 'recommendations', '[]'::jsonb)) > 5
       or exists (select 1 from jsonb_array_elements(coalesce(p_result -> 'recommendations', '[]'::jsonb)) x where jsonb_typeof(x) <> 'string' or char_length(x #>> '{}') > 300) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'recommendations';
    end if;
    if jsonb_typeof(coalesce(p_result -> 'sources', '[]'::jsonb)) <> 'array'
       or exists (select 1 from jsonb_array_elements(coalesce(p_result -> 'sources', '[]'::jsonb)) x where jsonb_typeof(x) <> 'object' or not (x ? 'entity' and x ? 'id')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sources';
    end if;
  end if;
  update app.project_ai_summaries set state = case when v_ok then 'ready' else 'failed' end, generated_at = now(),
    suggested_health = case when v_ok then p_result ->> 'suggested_health' end, summary = case when v_ok then p_result ->> 'summary' end,
    recommendations = case when v_ok then coalesce(p_result -> 'recommendations', '[]'::jsonb) else '[]'::jsonb end,
    sources = case when v_ok then coalesce(p_result -> 'sources', '[]'::jsonb) else '[]'::jsonb end
  where id = s.id;
  select * into p from app.projects where id = s.project_id;
  if s.requested_by is not null then
    perform app.notify(s.requested_by, 'system', case when v_ok then 'project.ai_summary_ready' else 'project.ai_summary_failed' end,
                       jsonb_build_object('record', p.name), '/projects?project=' || p.id, 'project', p.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'project.ai_summary', 'project', p.id::text, jsonb_build_object('state', case when v_ok then 'ready' else 'failed' end), true);
  return jsonb_build_object('ok', true);
end $fn$;

-- the brief text (null: the draft failed). It becomes the description, marked as a draft to review.
create function public.worker_project_brief_ready(p_project uuid, p_text text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.projects;
begin
  select * into p from app.projects where id = p_project and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p.brief_state <> 'drafting' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'brief_state'; end if;
  if p_text is null or btrim(p_text) = '' then
    update app.projects set brief_state = 'failed' where id = p.id;
  else
    if char_length(p_text) > 20000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'text'; end if;
    update app.projects set description = p_text, brief_state = 'draft', version = version + 1, updated_at = now() where id = p.id;
    insert into app.changelog (entity, record_id, field, old_value, new_value, source) values ('project', p.id, 'description', to_jsonb(p.description), to_jsonb(p_text), 'assistant');
  end if;
  if p.owner_id is not null then
    perform app.notify(p.owner_id, 'system', case when p_text is null or btrim(p_text) = '' then 'project.brief_failed' else 'project.brief_ready' end,
                       jsonb_build_object('record', p.name), '/projects?project=' || p.id, 'project', p.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'project.brief', 'project', p.id::text, jsonb_build_object('ok', p_text is not null and btrim(p_text) <> ''), true);
  return jsonb_build_object('ok', true);
end $fn$;

-- the rendered PDF (path null: rendering failed). It lands in the project's files.
create function public.worker_status_report_ready(p_report uuid, p_storage_path text, p_size bigint) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.project_status_reports; p app.projects; v_file uuid;
begin
  select * into r from app.project_status_reports where id = p_report for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if r.state <> 'requested' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  select * into p from app.projects where id = r.project_id;
  if p_storage_path is null then
    update app.project_status_reports set state = 'failed', ready_at = now() where id = r.id;
  else
    if p_storage_path !~ ('^project/' || p.id || '/[A-Za-z0-9][A-Za-z0-9._/-]{0,200}\.pdf$') or p_storage_path ~ '\.\.' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'path';
    end if;
    if p_size is null or p_size not between 1 and 26214400 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'size'; end if;
    insert into app.record_files (entity, record_id, storage_path, filename, mime, size_bytes, source, uploaded_by, is_sample, ready_at)
    values ('project', p.id, p_storage_path, 'status-report-P' || p.seq || '-' || to_char(now() at time zone 'Europe/Oslo', 'YYYY-MM-DD') || '.pdf',
            'application/pdf', p_size, 'status_report', r.requested_by, p.is_sample, now())
    returning id into v_file;
    update app.project_status_reports set state = 'ready', file_id = v_file, ready_at = now() where id = r.id;
    insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values ('project', p.id, 'files', jsonb_build_object('file', v_file, 'report', r.id), r.requested_by, 'system');
    insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
    values ('project.status_report_created', 'project', p.id, r.requested_by, jsonb_build_object('file', v_file, 'report', r.id), p.is_sample);
  end if;
  if r.requested_by is not null then
    perform app.notify(r.requested_by, 'system', case when p_storage_path is null then 'project.status_report_failed' else 'project.status_report_ready' end,
                       jsonb_build_object('record', p.name), '/projects?project=' || p.id, 'project', p.id);
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'project.status_report', 'project', p.id::text, jsonb_build_object('report', r.id, 'ok', p_storage_path is not null), true);
  return jsonb_build_object('ok', true, 'file_id', v_file);
end $fn$;

-- ===========================================================================
-- the engine (§6). Project events start workflows through the generic subscriber once «project» is a trigger entity
-- (workflow_save below). The project_action step is implemented here; wf_validate, wf_blockers and wf_step call these
-- three functions when 0037's versions of them are merged (V-P6P-01). Until then wf_blockers still answers
-- «not_available:projects» and app.project_actions_wired() is false, so the Reports tab says the actions are not live.
-- ===========================================================================
-- validate a project_action config at save; raises invalid with detail «graph.<key>.<field>»
create function app.wf_project_validate(p_key text, c jsonb) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_det text := 'graph.' || p_key || '.';
begin
  if c is null or jsonb_typeof(c) <> 'object' or not (app.prj_hooks() -> 'actions') ? coalesce(c ->> 'action', '') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'action';
  end if;
  if c ->> 'template_id' is not null and not exists (select 1 from app.project_templates t where t.id = app.prj_uuid(c, 'template_id', v_det || 'template_id') and t.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'template_id';
  end if;
  if c ->> 'board_id' is not null and not exists (select 1 from app.project_boards b where b.id = app.prj_uuid(c, 'board_id', v_det || 'board_id') and b.archived_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'board_id';
  end if;
  if c ->> 'phase_id' is not null and not exists (select 1 from app.project_phases ph where ph.id = app.prj_uuid(c, 'phase_id', v_det || 'phase_id')
                                                   and (c ->> 'board_id' is null or ph.board_id = app.prj_uuid(c, 'board_id', v_det || 'board_id'))) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'phase_id';
  end if;
  case c ->> 'action'
    when 'create_from_template' then
      if coalesce(c ->> 'start', 'today') not in ('today', 'won_at') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'start'; end if;
      if coalesce(c ->> 'owner', '@record_owner') not in ('@record_owner', '@workflow_owner')
         and not exists (select 1 from app.admins a where a.id::text = c ->> 'owner' and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'owner';
      end if;
    when 'move_phase' then
      if c ->> 'phase_id' is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'phase_id'; end if;
    when 'add_tasks_from_template' then
      if c ->> 'template_id' is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'template_id'; end if;
      if c ? 'group' and (jsonb_typeof(c -> 'group') <> 'string' or char_length(btrim(c ->> 'group')) not between 1 and 80) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'group';
      end if;
    when 'assign_task' then
      if coalesce(btrim(c ->> 'item_name'), '') = '' and c ->> 'template_item_id' is null then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'item_name';
      end if;
      if coalesce(c ->> 'assignee', '@record_owner') not in ('@record_owner', '@workflow_owner')
         and not exists (select 1 from app.admins a where a.id::text = c ->> 'assignee' and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_det || 'assignee';
      end if;
  end case;
end $fn$;

-- what an active workflow's project step still lacks: a template (the seeded «won_project» has none until one is chosen)
create function app.wf_project_blocker(c jsonb) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case when c ->> 'action' in ('create_from_template', 'add_tasks_from_template')
                   and not exists (select 1 from app.project_templates t where t.id::text = c ->> 'template_id' and t.deleted_at is null) then 'project_template_missing'
              when c ->> 'action' = 'move_phase' and not exists (select 1 from app.project_phases ph where ph.id::text = c ->> 'phase_id') then 'project_phase_missing' end
$fn$;

-- run a project_action step as the workflow's owner (app.acting_as): rights and visibility are theirs. → the step's output
create function app.wf_project_action(p_run app.workflow_runs, p_wf app.workflows, c jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  d app.deals; p app.projects; r jsonb; v_owner uuid; v_start date; i app.project_items; v_group uuid; n int;
begin
  case c ->> 'action'
    when 'create_from_template' then
      if p_run.subject_type is distinct from 'deal' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
      select * into d from app.deals where id = p_run.subject_id and deleted_at is null;
      if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'deal'; end if;
      if app.wf_project_blocker(c) is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'template_id'; end if;
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'owner', '@record_owner')), 'deal', d.id, p_wf.owner_id)) #>> '{}';
      v_start := case when c ->> 'start' = 'won_at' and d.won_at is not null then (d.won_at at time zone 'Europe/Oslo')::date else current_date end;
      r := app.prj_create(jsonb_strip_nulls(jsonb_build_object('name', left(d.title, 200), 'board_id', c -> 'board_id', 'phase_id', c -> 'phase_id', 'owner_id', v_owner,
                                                               'starts_on', v_start, 'template_id', c -> 'template_id', 'person_id', d.person_id,
                                                               'organization_id', d.organization_id, 'deal_ids', jsonb_build_array(d.id))), 'workflow');
      return jsonb_build_object('project', r ->> 'id');
    when 'move_phase' then
      if p_run.subject_type is distinct from 'project' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
      p := app.prj_get(p_run.subject_id, true);
      perform app.prj_require_edit(p);
      if p.status <> 'open' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
      p := app.prj_move_to(p, app.prj_uuid(c, 'phase_id'), 'workflow');
      return jsonb_build_object('project', p.id, 'phase', p.phase_id);
    when 'add_tasks_from_template' then
      if p_run.subject_type is distinct from 'project' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
      p := app.prj_get(p_run.subject_id, true);
      perform app.prj_require_edit(p);
      if coalesce(btrim(c ->> 'group'), '') <> '' then
        v_group := (select g.id from app.project_groups g where g.project_id = p.id and lower(g.name) = lower(btrim(c ->> 'group')) order by g.ord limit 1);
        if v_group is null then
          insert into app.project_groups (project_id, name, ord) values (p.id, btrim(c ->> 'group'), coalesce((select max(ord) from app.project_groups where project_id = p.id), 0) + 10)
          returning id into v_group;
        end if;
      end if;
      n := app.prj_apply_template(p.id, app.prj_uuid(c, 'template_id'), v_group, 'workflow');
      perform app.emit('project.updated', 'project', p.id, jsonb_build_object('fields', jsonb_build_array('items'), 'count', n), p.is_sample);
      return jsonb_build_object('project', p.id, 'items', n);
    when 'assign_task' then
      if p_run.subject_type is distinct from 'project' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
      p := app.prj_get(p_run.subject_id, true);
      perform app.prj_require_edit(p);
      select * into i from app.project_items x where x.project_id = p.id and x.deleted_at is null and x.kind <> 'activity'
        and (x.template_item_id::text = c ->> 'template_item_id' or (c ->> 'template_item_id' is null and lower(x.name) = lower(btrim(c ->> 'item_name'))))
      order by x.ord limit 1 for update;
      if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'item'; end if;
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'assignee', '@record_owner')), 'project', p.id, p_wf.owner_id)) #>> '{}';
      if v_owner is null or not exists (select 1 from app.admins a where a.id = v_owner and a.active) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'assignee'; end if;
      if i.owner_id is distinct from v_owner then
        update app.project_items set owner_id = v_owner, version = version + 1, updated_at = now(), updated_by = app.me() where id = i.id;
        perform app.prj_item_log(p.id, i.id, 'owner_id', to_jsonb(i.owner_id), to_jsonb(v_owner), 'workflow');
        perform app.notify(v_owner, 'system', 'project.item_assigned', jsonb_build_object('record', p.name, 'item', i.name, 'actor', p_wf.name),
                           '/projects?project=' || p.id, 'project', p.id);
        perform app.emit('project_item.updated', 'project_item', i.id, jsonb_build_object('project', p.id, 'fields', jsonb_build_array('owner_id')), p.is_sample);
      end if;
      return jsonb_build_object('project', p.id, 'item', i.id, 'assignee', v_owner);
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'action';
  end case;
end $fn$;

-- ---------------------------------------------------------------------------
-- notes on any record (0009), two fixes (spec §9.11, CRM-06 RU): a mention links to the record's own screen
-- (/projects?project=…, from app.entity_route, instead of «/?<uuid>», which notifications_route_check refuses), and it
-- notifies only mentioned staff who may see the record (its scope's «see» and its visibility)
create or replace function public.note_save(p_entity text, p_id uuid, p_note uuid, p_body text, p_pinned boolean default null, p_parent uuid default null, p_mentions uuid[] default '{}')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity); v_me uuid := app.require(e.scope, 'see'); v_id uuid; v_title text; v_owner uuid; v_vis text; v_route text;
begin
  execute format('select t.%I::text from app.%I t where t.id = %L and t.deleted_at is null and %s', e.title_col, e.tbl, p_id, app.vis_sql(e)) into v_title;
  if v_title is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if e.owned and e.key not in ('email_thread', 'document', 'document_template') then
    execute format('select t.owner_id, t.visibility from app.%I t where t.id = %L', e.tbl, p_id) into v_owner, v_vis;
  end if;
  if p_note is null then
    insert into app.notes (entity, record_id, body, pinned, parent_id, mentions, author_id, is_sample)
    values (e.key, p_id, btrim(p_body), coalesce(p_pinned, false), p_parent, coalesce(p_mentions, '{}'), v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
    v_route := case e.key when 'deal' then '/deals?deal=' when 'person' then '/contacts?person=' when 'organization' then '/customers?org=' when 'lead' then '/leads?lead='
                          else app.entity_route(e.key) || '?' || e.key || '=' end || p_id;
    -- @mentions notify: the excerpt is the note's opening, staff-written, never a customer's message
    perform app.notify(m, 'mention', 'mention', jsonb_build_object('actor', (select name from app.admins where id = v_me), 'record', v_title, 'excerpt', left(btrim(p_body), 80)),
                       v_route, e.key, p_id)
    from unnest(coalesce(p_mentions, '{}')) m
    where m <> v_me and exists (select 1 from app.admins a where a.id = m and a.active)
      and app.can_for(m, e.scope, 'see') and (v_vis is null or app.visible_for(m, v_owner, v_vis));
    if e.key = 'deal' then update app.deals set last_activity_at = now() where id = p_id; end if;
    perform app.emit('note.created', e.key, p_id, jsonb_build_object('note', v_id));
  else
    update app.notes set body = coalesce(nullif(btrim(p_body), ''), body), pinned = coalesce(p_pinned, pinned), updated_at = now()
    where id = p_note and entity = e.key and record_id = p_id and deleted_at is null and (author_id = v_me or app.can(e.scope, 'edit_others'))
    returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  perform app.log('note.saved', e.key, p_id::text, jsonb_build_object('note', v_id));
  return jsonb_build_object('id', v_id);
end $fn$;

-- workflows (0021) with «project» among the trigger entities (AUT-02); nothing else changed
create or replace function public.workflow_save(p_id uuid, p_values jsonb, p_graph jsonb default null, p_version int default null) returns jsonb
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
  if v_kind <> 'assignment' and v_tt in ('event', 'date') and not exists (select 1 from app.entities e where e.key = v_tc ->> 'entity' and e.key in ('deal', 'lead', 'person', 'organization', 'activity', 'ticket', 'project')) then
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


-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['project_boards', 'project_phases', 'project_templates', 'project_template_groups', 'project_template_items',
                           'project_template_dependencies', 'projects', 'project_deals', 'project_phase_history', 'project_groups', 'project_items',
                           'project_item_assignees', 'project_item_dependencies', 'project_ai_summaries', 'record_files', 'project_status_reports'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.project_defaults()', 'app.project_phase_ok()', 'app.project_history_fixed()', 'app.project_item_ok()', 'app.project_dependency_ok()',
                           'app.project_template_item_ok()', 'app.project_template_dependency_ok()', 'app.record_files_forget()',
                           'app.prj_uuid(jsonb, text, text)', 'app.prj_uuids(jsonb, text)', 'app.prj_date(jsonb, text, text)', 'app.prj_int(jsonb, text, int, int, text)',
                           'app.prj_text(jsonb, text, int, int, text)', 'app.prj_keys(jsonb, text[])', 'app.prj_today()', 'app.can_for(uuid, text, text)',
                           'app.visible_for(uuid, uuid, text)', 'app.prj_get(uuid, boolean)', 'app.prj_can_edit(app.projects)', 'app.prj_require_edit(app.projects)',
                           'app.prj_item_mine(app.project_items)', 'app.prj_item_log(uuid, uuid, text, jsonb, jsonb, text)', 'app.prj_ai_check()', 'app.prj_card(app.projects)',
                           'app.prj_move_to(app.projects, uuid, text)', 'app.prj_apply_template(uuid, uuid, uuid, text)', 'app.prj_create(jsonb, text)', 'app.prj_ai_state()',
                           'app.project_actions_wired()', 'app.prj_hooks()', 'app.prj_template_row(app.project_templates)', 'app.prj_assignees_set(app.projects, uuid, text, jsonb)',
                           'app.prj_item_set_done(app.projects, app.project_items, boolean)', 'app.prj_cell(text)', 'app.file_entity(text)',
                           'app.record_visible(app.entities, uuid)', 'app.record_editable(app.entities, uuid)', 'app.files_purge()',
                           'app.wf_project_validate(text, jsonb)', 'app.wf_project_blocker(jsonb)', 'app.wf_project_action(app.workflow_runs, app.workflows, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.project_boards_get(boolean)', 'public.projects_board(uuid, jsonb)', 'public.project_detail(uuid)',
                           'public.project_timeline(uuid, date, int)', 'public.project_templates_get()', 'public.project_template_get(uuid)',
                           'public.project_reports(uuid, date, date)', 'public.project_create(jsonb)', 'public.project_create_from_deal(uuid, jsonb)',
                           'public.project_move(uuid, uuid, int)', 'public.project_health_set(uuid, text, int, uuid)', 'public.project_close(uuid, text, int)',
                           'public.project_deal_link(uuid, uuid, boolean, boolean)', 'public.project_brief_review(uuid, int)',
                           'public.project_item_save(uuid, uuid, jsonb, int)', 'public.project_item_done(uuid, boolean)', 'public.project_items_add(uuid, uuid, jsonb)',
                           'public.project_items_bulk(uuid, uuid[], jsonb)', 'public.project_items_delete(uuid[])', 'public.project_items_reorder(uuid, uuid[])',
                           'public.project_activity_add(uuid, uuid, jsonb)', 'public.project_dependency_set(uuid, uuid, boolean, int)',
                           'public.project_group_save(uuid, uuid, text, int)', 'public.project_group_delete(uuid)', 'public.project_group_shift(uuid, uuid, int)',
                           'public.project_template_save(uuid, jsonb, int)', 'public.project_template_from_project(uuid, text)', 'public.project_template_delete(uuid)',
                           'public.project_board_save(uuid, jsonb)', 'public.project_phase_save(uuid, uuid, jsonb)', 'public.project_phases_reorder(uuid, uuid[])',
                           'public.project_phase_delete(uuid, uuid)', 'public.project_ai_summary_request(uuid)', 'public.project_brief_request(uuid)',
                           'public.project_status_report_request(uuid, jsonb, text, boolean)', 'public.project_export(uuid, uuid, text)',
                           'public.files_list(text, uuid)', 'public.file_upload_begin(text, uuid, text, text, bigint)', 'public.file_upload_done(uuid)',
                           'public.file_download_url(uuid)', 'public.file_delete(uuid)',
                           'public.note_save(text, uuid, uuid, text, boolean, uuid, uuid[])', 'public.workflow_save(uuid, jsonb, jsonb, int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_project_summary_ready(uuid, jsonb)', 'public.worker_project_brief_ready(uuid, text)',
                           'public.worker_status_report_ready(uuid, text, bigint)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
