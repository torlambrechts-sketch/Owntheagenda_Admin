-- phase6_projects_invariants.sql — Projects (0038; PRJ-01..09, UF-20, SF-42, CRM-05, CRM-06, AUT-02, INS-01 screen side).
\ir _helpers.psql
begin;

-- expect_detail(sql, message, detail): the statement must raise with this message and this detail
create or replace function pg_temp.expect_detail(p_sql text, p_message text, p_detail text, p_label text) returns void language plpgsql as $$
declare v_msg text; v_det text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg = p_message and coalesce(v_det, '') = coalesce(p_detail, '') then raise notice 'ok %', p_label; return; end if;
    raise exception 'FAIL %: expected «%» («%»), got «%» («%»)', p_label, p_message, p_detail, v_msg, v_det;
  end;
  raise exception 'FAIL %: expected «%», but it succeeded', p_label, p_message;
end $$;

-- ---------------------------------------------------------------------------
-- structure: closed tables, client functions for signed-in staff, workers for the service role, helpers for nobody
create temp table t_tables as select unnest(array['project_boards', 'project_phases', 'project_templates', 'project_template_groups', 'project_template_items',
  'project_template_dependencies', 'projects', 'project_deals', 'project_phase_history', 'project_groups', 'project_items', 'project_item_assignees',
  'project_item_dependencies', 'project_ai_summaries', 'record_files', 'project_status_reports']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 16, 'all sixteen project tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no project table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 16, 'no client grant on a project table; the service role has them');
create temp table t_rpcs as select unnest(array['public.project_boards_get(boolean)', 'public.projects_board(uuid, jsonb)', 'public.project_detail(uuid)',
  'public.project_timeline(uuid, date, int)', 'public.project_templates_get()', 'public.project_template_get(uuid)', 'public.project_reports(uuid, date, date)',
  'public.project_create(jsonb)', 'public.project_create_from_deal(uuid, jsonb)', 'public.project_move(uuid, uuid, int)', 'public.project_health_set(uuid, text, int, uuid)',
  'public.project_close(uuid, text, int)', 'public.project_deal_link(uuid, uuid, boolean, boolean)', 'public.project_brief_review(uuid, int)',
  'public.project_item_save(uuid, uuid, jsonb, int)', 'public.project_item_done(uuid, boolean)', 'public.project_items_add(uuid, uuid, jsonb)',
  'public.project_items_bulk(uuid, uuid[], jsonb)', 'public.project_items_delete(uuid[])', 'public.project_items_reorder(uuid, uuid[])',
  'public.project_activity_add(uuid, uuid, jsonb)', 'public.project_dependency_set(uuid, uuid, boolean, int)', 'public.project_group_save(uuid, uuid, text, int)',
  'public.project_group_delete(uuid)', 'public.project_group_shift(uuid, uuid, int)', 'public.project_template_save(uuid, jsonb, int)',
  'public.project_template_from_project(uuid, text)', 'public.project_template_delete(uuid)', 'public.project_board_save(uuid, jsonb)',
  'public.project_phase_save(uuid, uuid, jsonb)', 'public.project_phases_reorder(uuid, uuid[])', 'public.project_phase_delete(uuid, uuid)',
  'public.project_ai_summary_request(uuid)', 'public.project_brief_request(uuid)', 'public.project_status_report_request(uuid, jsonb, text, boolean)',
  'public.project_export(uuid, uuid, text)', 'public.files_list(text, uuid)', 'public.file_upload_begin(text, uuid, text, text, bigint)',
  'public.file_upload_done(uuid)', 'public.file_download_url(uuid)', 'public.file_delete(uuid)', 'public.note_save(text, uuid, uuid, text, boolean, uuid, uuid[])',
  'public.workflow_save(uuid, jsonb, jsonb, int)']) f;
select pg_temp.check(not exists (select 1 from t_rpcs where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
                     'every project function is for signed-in staff (' || (select count(*) from t_rpcs) || '), never anon');
select pg_temp.check(not exists (select 1 from t_rpcs r join pg_proc p on p.oid = r.f::regprocedure where not p.prosecdef or not ('search_path=""' = any (p.proconfig))),
                     'every project function is security definer with an empty search path');
select pg_temp.check(not has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute'), 'worker for the service role only: ' || f)
from unnest(array['public.worker_project_summary_ready(uuid, jsonb)', 'public.worker_project_brief_ready(uuid, text)', 'public.worker_status_report_ready(uuid, text, bigint)']) f;
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace
                                 and (p.proname like 'prj\_%' or p.proname like 'project\_%' or p.proname like 'wf\_project\_%' or p.proname in ('can_for', 'visible_for', 'file_entity', 'record_visible', 'record_editable', 'files_purge', 'record_files_forget'))
                                 and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
                     'no app helper of 0038 is callable by a client role');
select pg_temp.check(exists (select 1 from app.entities where key = 'project' and tbl = 'projects' and scope = 'projects' and module = 'projects' and owned),
                     'a project is a record type in the projects scope behind the projects module');
select pg_temp.check(app.entity_route('project') = '/projects' and app.entity_route('document') = '/documents' and app.entity_route('deal') = '/deals',
                     'the route register knows projects and keeps the routes it had');
select pg_temp.check(exists (select 1 from app.entity_columns where entity = 'activity' and col = 'project_id' and ref = 'project' and not writable),
                     'an activity points at its project');
select pg_temp.check((select default_value = 'on' and options = array['on', 'off'] and not fixed from app.settings_registry where key = 'project_ai'),
                     'project_ai is registered, on by default (D-16)');

-- ---------------------------------------------------------------------------
-- fixture: an organisation, a person, two deals; a staff member with projects see/add only
select pg_temp.as_nobody();
create temp table t_ids as select gen_random_uuid() org, gen_random_uuid() person, gen_random_uuid() deal, gen_random_uuid() deal2,
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'emma@orgpuls.no') emma,
  (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid, (select id from app.admins where email = 'magnus@orgpuls.no') magnus,
  (select id from app.admins where email = 'ola@orgpuls.no') ola, (select id from app.admins where email = 'eirik@orgpuls.no') eirik;
insert into app.organizations (id, name, owner_id) select org, 'Lumio Prosjekt AS', ingrid from t_ids;
insert into app.people (id, name, email, organization_id, owner_id) select person, 'Kari Prosjektsen', 'kari@lumio.example', org, ingrid from t_ids;
insert into app.deals (id, title, value, currency, pipeline_id, stage_id, person_id, organization_id, owner_id, visibility)
select x.id, x.title, 64000, 'NOK', p.id, (select s.id from app.stages s where s.pipeline_id = p.id order by s.ord limit 1), i.person, i.org, i.ingrid, 'all'
from t_ids i cross join app.pipelines p cross join lateral (values (i.deal, 'Lumio — Skiftly P6'), (i.deal2, 'Lumio — tillegg P6')) x(id, title)
where p.name = 'New business';
insert into app.permission_sets (key, name, kind, rights) values ('proj_limited', 'P6 test — projects see and add', 'custom', array['projects:see', 'projects:add']);
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'proj_limited') where email = 'magnus@orgpuls.no';

-- ---------------------------------------------------------------------------
-- rights per scope and action (SEC-07)
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.project_boards_get()$$, 'forbidden', 'projects:see', 'a sales user without projects:see cannot read boards');
select pg_temp.expect_detail($$select public.project_create('{"name":"X"}')$$, 'forbidden', 'projects:add', 'nor make a project');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail($$select public.project_create('{"name":"X"}')$$, 'forbidden', 'projects:add', 'a read-only analyst cannot make a project');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.project_board_save(null, '{"name":"Mitt brett"}')$$, 'forbidden', 'projects:configure', 'boards need projects:configure');
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.project_boards_get()$$, 'not_signed_in', 'nobody signed in reads nothing');

-- boards and phases
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_b as select (public.project_board_save(null, '{"name":"Leveranse P6","phases":[{"name":"Kickoff","color":"#F6D9C6"},{"name":"Setup","color":"#dcebd3"},{"name":"Survey"}]}') ->> 'id')::uuid id;
create temp table t_ph as select (select id from app.project_phases where board_id = (select id from t_b) and name = 'Kickoff') kickoff,
  (select id from app.project_phases where board_id = (select id from t_b) and name = 'Setup') setup,
  (select id from app.project_phases where board_id = (select id from t_b) and name = 'Survey') survey;
select pg_temp.check((select array_agg(color order by ord) from app.project_phases where board_id = (select id from t_b)) = array['#F6D9C6', '#DCEBD3', '#F2EAD6'],
                     'a board brings its phases in order, colours upper-cased, the default colour where none was given');
select pg_temp.expect_detail($$select public.project_board_save(null, '{"name":"leveranse p6"}')$$, 'invalid', 'name', 'board names are unique, case-insensitively');
select pg_temp.expect_detail(format($$select public.project_phase_save(null, %L, '{"name":"Ny","color":"blue"}')$$, (select id from t_b)), 'invalid', 'color', 'a phase colour is a hex colour');
select pg_temp.expect_detail(format($$select public.project_phases_reorder(%L, array[%L]::uuid[])$$, (select id from t_b), (select kickoff from t_ph)), 'invalid', 'ids',
                             'a reorder names every phase of the board');
create temp table t_b2 as select (public.project_board_save(null, '{"name":"Rapport P6","phases":[{"name":"R1"},{"name":"R2"},{"name":"R3"}]}') ->> 'id')::uuid id;
select pg_temp.check(jsonb_path_exists(public.project_boards_get(), '$[*] ? (@.name == "Leveranse P6" && @.phases.size() == 3)'), 'the board select lists the board with its phases');

-- ---------------------------------------------------------------------------
-- projects (PRJ-02): ＋ Project and the visibility rule
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'X', 'deal_ids', jsonb_build_array(%L)))$$, (select deal from t_ids)),
                             'forbidden', 'deals:see', 'linking a deal needs deals:see');
select pg_temp.expect_detail($$select public.project_create('{"name":"X","colour":"red"}')$$, 'invalid', 'colour', 'an unknown value key is refused');
select pg_temp.expect_detail($$select public.project_create('{"name":"  "}')$$, 'invalid', 'name', 'a project needs a name');
select pg_temp.expect_detail($$select public.project_create('{"name":"X","starts_on":"2026-12-01","ends_on":"2026-11-01"}')$$, 'invalid', 'ends_on', 'it cannot end before it starts');
select pg_temp.expect_detail($$select public.project_create('{"name":"X","starts_on":"1 Oct"}')$$, 'invalid', 'starts_on', 'dates are ISO dates');
select pg_temp.expect_detail($$select public.project_create('{"name":"X","board_id":"nope"}')$$, 'invalid', 'board_id', 'a malformed id is invalid, named');
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'X', 'board_id', %L, 'phase_id', %L))$$, (select id from t_b), (select id from app.project_phases where board_id = (select id from t_b2) limit 1)),
                             'invalid', 'phase_id', 'the phase belongs to the board');

select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_p as select
  (public.project_create(jsonb_build_object('name', 'Lumio AS — Skiftly onboarding', 'board_id', (select id from t_b), 'owner_id', (select emma from t_ids),
     'organization_id', (select org from t_ids), 'person_id', (select person from t_ids), 'deal_ids', jsonb_build_array((select deal from t_ids)),
     'starts_on', '2026-10-05', 'ends_on', '2026-12-18')) ->> 'id')::uuid p1,
  (public.project_create(jsonb_build_object('name', 'Fjellheim skole P6', 'board_id', (select id from t_b), 'phase_id', (select setup from t_ph))) ->> 'id')::uuid p2,
  (public.project_create(jsonb_build_object('name', 'Privat P6', 'board_id', (select id from t_b), 'phase_id', (select setup from t_ph), 'visibility', 'owner')) ->> 'id')::uuid p3;
select pg_temp.check((select phase_id = (select kickoff from t_ph) and status = 'open' and health is null and health_source is null and visibility = 'all' and created_source = 'ui'
                      from app.projects where id = (select p1 from t_p)),
                     'a new project starts in the board''s first phase, open, with no health (spec Q1) and the visibility default «all»');
select pg_temp.check((select count(*) = 1 and bool_and(left_at is null and phase_id = (select kickoff from t_ph)) from app.project_phase_history where project_id = (select p1 from t_p)),
                     'the phase history opens with the creation');
select pg_temp.check(exists (select 1 from app.project_deals where project_id = (select p1 from t_p) and deal_id = (select deal from t_ids) and is_primary),
                     'the first linked deal is the primary');
select pg_temp.check(exists (select 1 from app.events where kind = 'project.created' and subject_id = (select p1 from t_p) and payload ->> 'source' = 'ui'
                             and payload ->> 'deal' = (select deal::text from t_ids)), 'project.created carries its source and deal, ids only');
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select emma from t_ids) and key = 'project.assigned' and route = '/projects?project=' || (select p1 from t_p)),
                     'the owner it was made for is told, with a link to the project');
select pg_temp.check(exists (select 1 from app.changelog where entity = 'project' and record_id = (select p1 from t_p) and field = '*created'), 'the creation is in the history');
select pg_temp.expect_detail($$select public.rec_save('project', null, '{"name":"Uten brett"}')$$, 'invalid', 'board_id', 'the generic create cannot make a project without a board');
select pg_temp.expect_detail(format($$select public.rec_save('project', %L, jsonb_build_object('board_id', %L))$$, (select p2 from t_p), (select id from t_b2)), 'invalid', 'board_id',
                             'the board is not a plain field');

select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_detail(%L)$$, (select p3 from t_p)), 'not_found', null, 'a project visible only to its owner is not found by others');
select pg_temp.expect_detail(format($$select public.rec_get('project', %L)$$, (select p3 from t_p)), 'not_found', null, 'nor through the generic read');
select pg_temp.check(public.search('Skiftly onboarding') @> '[{"group":"project"}]' and not public.search('Privat P6') @> '[{"group":"project"}]',
                     '⌘K finds the projects the caller may see, and no other');
select public.rec_save('project', (select p1 from t_p), '{"description":"Oppstart for Skiftly."}');
select pg_temp.check(exists (select 1 from app.events where kind = 'project.updated' and subject_id = (select p1 from t_p) and payload -> 'fields' ? 'description'),
                     'plain fields go through rec_save and emit project.updated with the fields');

-- items on the first project: tasks, a milestone, a subtask, an activity (done/total counts tasks and milestones)
create temp table t_i as select
  (public.project_item_save((select p1 from t_p), null, '{"name":"Kickoff meeting","starts_on":"2026-10-05","due_on":"2026-10-07"}') ->> 'id')::uuid kick,
  (public.project_item_save((select p1 from t_p), null, jsonb_build_object('name', 'Upload employee list', 'starts_on', '2026-10-08', 'due_on', '2026-10-16',
     'assignees', jsonb_build_array(jsonb_build_object('staff_id', (select magnus from t_ids)), jsonb_build_object('person_id', (select person from t_ids))))) ->> 'id')::uuid upload,
  (public.project_item_save((select p1 from t_p), null, '{"kind":"milestone","name":"Employee list ready","due_on":"2026-10-16"}') ->> 'id')::uuid mile,
  (public.project_item_save((select p1 from t_p), null, '{"name":"Configure departments","starts_on":"2026-10-17","due_on":"2026-10-22","completes_with_subtasks":true}') ->> 'id')::uuid conf;
create temp table t_i2 as select (public.project_item_save((select p1 from t_p), null, jsonb_build_object('name', 'Agree department list', 'parent_id', (select conf from t_i))) ->> 'id')::uuid sub;
select pg_temp.expect_detail(format($$select public.project_item_save(%L, null, jsonb_build_object('name', 'Deeper', 'parent_id', %L))$$, (select p1 from t_p), (select sub from t_i2)),
                             'invalid', 'parent_id', 'a subtask has no subtasks (one level)');
select pg_temp.expect_detail(format($$select public.project_item_save(%L, null, '{"kind":"milestone","name":"M","starts_on":"2026-10-01","due_on":"2026-10-02"}')$$, (select p1 from t_p)),
                             'invalid', 'starts_on', 'a milestone is a day, not a span');
select pg_temp.expect_detail(format($$select public.project_item_save(%L, null, '{"kind":"activity","name":"A"}')$$, (select p1 from t_p)), 'invalid', 'kind',
                             'an activity item is made by project_activity_add');
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select magnus from t_ids) and key = 'project.item_assigned'
                             and params ->> 'item' = 'Upload employee list'), 'a staff assignee is told; a customer-side assignee is only listed (spec Q2)');
select pg_temp.expect_detail(format($$select public.project_activity_add(%L, null, jsonb_build_object('type', 'meeting', 'subject', 'Training call', 'starts_at', '2026-10-15'))$$, (select p1 from t_p)),
                             'invalid', 'starts_at', 'an activity needs a time (PRJ-03 RU)');
select pg_temp.expect_detail(format($$select public.project_activity_add(%L, null, jsonb_build_object('type', 'meeting', 'subject', 'Training call', 'starts_at', '2026-10-15T10:00:00+02:00'))$$, (select p1 from t_p)),
                             'invalid', 'owner_id', 'and an owner');
create temp table t_act as select public.project_activity_add((select p1 from t_p), null, jsonb_build_object('type', 'meeting', 'subject', 'Training call with shift leads',
  'starts_at', '2026-10-15T10:00:00+02:00', 'owner_id', (select magnus from t_ids), 'duration_min', 60)) r;
select pg_temp.check((select a.project_id = (select p1 from t_p) and a.deal_id = (select deal from t_ids) and a.owner_id = (select magnus from t_ids) and a.organization_id = (select org from t_ids)
                      from app.activities a where a.id = (select (r ->> 'activity_id')::uuid from t_act)),
                     'a project activity is a real activity on the primary deal, owned as asked');

-- the board (§1.1)
create temp table t_board as select public.projects_board((select id from t_b)) r;
select pg_temp.check((select (c ->> 'done')::int = 0 and (c ->> 'total')::int = 5 and c -> 'deal' ->> 'title' = 'Lumio — Skiftly P6' and c ->> 'organization' = 'Lumio Prosjekt AS'
                             and c -> 'owner' ->> 'name' = 'Emma Lie' and c ->> 'health' is null and c ->> 'starts_on' = '2026-10-05' and c ->> 'ends_on' = '2026-12-18'
                      from t_board, jsonb_array_elements(r -> 'cards') c where c ->> 'id' = (select p1::text from t_p)),
                     'a card: 0/5 (four tasks with the subtask, one milestone; the activity does not count), the primary deal''s title, organisation, owner, dates, no pill');
select pg_temp.check((select jsonb_agg(jsonb_build_object(ph ->> 'name', (ph ->> 'count')::int) order by (ph ->> 'ord')::int) from t_board, jsonb_array_elements(r -> 'phases') ph)
                     = '[{"Kickoff":1},{"Setup":1},{"Survey":0}]', 'Emma''s columns count the open projects she may see (the private one is not hers)');
select pg_temp.check((select r -> 'workflow_hint' = 'null'::jsonb from t_board), 'no hint while no active workflow creates projects (V-DEALS-15)');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (ph ->> 'count')::int from jsonb_array_elements(public.projects_board((select id from t_b)) -> 'phases') ph where ph ->> 'name' = 'Setup') = 2,
                     'the owner of the private project counts it');
select pg_temp.check((public.projects_board((select id from t_b), '{"filters":[{"f":"name","op":"contains","v":"Fjellheim"}]}') -> 'cards') @> jsonb_build_array(jsonb_build_object('id', (select p2 from t_p)))
                 and jsonb_array_length(public.projects_board((select id from t_b), '{"filters":[{"f":"name","op":"contains","v":"Fjellheim"}]}') -> 'cards') = 1,
                     'the board takes the generic filters (PIP-12)');

-- done and its rules (PRJ-03), own items without edit_others (UF-20 step 4)
select pg_temp.as_staff('magnus@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_item_done(%L, true)$$, (select kick from t_i)), 'forbidden', 'projects:edit_others', 'someone else''s item needs edit_others');
select pg_temp.check((public.project_item_done((select upload from t_i), true) ->> 'done')::boolean, 'an assignee completes their own item');
select pg_temp.check((public.project_item_save((select p1 from t_p), (select upload from t_i), '{"name":"Upload employee list (v2)"}') ->> 'version')::int = 3, 'and may rename it');
select pg_temp.expect_detail(format($$select public.project_item_save(%L, %L, jsonb_build_object('owner_id', %L))$$, (select p1 from t_p), (select upload from t_i), (select magnus from t_ids)),
                             'forbidden', 'projects:edit_others', 'but not reassign it');
select pg_temp.expect_detail(format($$select public.project_move(%L, %L)$$, (select p2 from t_p), (select survey from t_ph)), 'forbidden', 'projects:edit_others',
                             'moving someone else''s project needs edit_others');
select pg_temp.check(exists (select 1 from app.events where kind = 'project.task_completed' and subject_id = (select p1 from t_p) and payload ->> 'item' = (select upload::text from t_i)),
                     'project.task_completed names the item');
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_dn as select public.project_item_done((select mile from t_i), true) a, public.project_item_done((select sub from t_i2), true) b;
select pg_temp.check((select not (a ->> 'parent_completed')::boolean from t_dn)
                 and exists (select 1 from app.events where kind = 'project.milestone_reached' and payload ->> 'item' = (select mile::text from t_i)),
                     'a milestone done reports «milestone reached»');
select pg_temp.check((select (b ->> 'parent_completed')::boolean from t_dn)
                 and (select done from app.project_items where id = (select conf from t_i)), 'a parent set to complete with its subtasks completes with the last one');
select pg_temp.check(not (public.project_item_done((select kick from t_i), true) ->> 'parent_completed')::boolean, 'a top-level task completes alone');
create temp table t_i3 as select (public.project_item_save((select p1 from t_p), null, '{"name":"Parent without rule"}') ->> 'id')::uuid par;
create temp table t_i4 as select (public.project_item_save((select p1 from t_p), null, jsonb_build_object('name', 'Only child', 'parent_id', (select par from t_i3))) ->> 'id')::uuid kid;
create temp table t_dn2 as select public.project_item_done((select kid from t_i4), true) r;
select pg_temp.check(not (select (r ->> 'parent_completed')::boolean from t_dn2) and not (select done from app.project_items where id = (select par from t_i3)),
                     'completing all subtasks does not complete the parent unless it says so (PRJ-03 acceptance)');
select public.project_item_done((select (r ->> 'id')::uuid from t_act), true);
select pg_temp.check((select done and done_by = (select emma from t_ids) from app.activities where id = (select (r ->> 'activity_id')::uuid from t_act))
                 and (select last_activity_at > now() - interval '1 minute' from app.deals where id = (select deal from t_ids))
                 and exists (select 1 from app.events where kind = 'activity.completed' and subject_id = (select (r ->> 'activity_id')::uuid from t_act)),
                     'an activity item completes its activity and resets the deal''s idle clock (ACT-01)');
select public.project_item_done((select kick from t_i), false);
select pg_temp.check(exists (select 1 from app.events where kind = 'project_item.reopened' and subject_id = (select kick from t_i)), 'reopening an item is an event of its own');
select pg_temp.check(exists (select 1 from app.changelog where entity = 'project' and record_id = (select p1 from t_p) and field = 'items.' || (select upload from t_i) || '.done'),
                     'item work is written into the project''s history');

-- dependencies (PRJ-04)
select pg_temp.check(public.project_dependency_set((select upload from t_i), (select mile from t_i), true) ->> 'ok' = 'true', 'a task can precede a milestone');
select public.project_dependency_set((select mile from t_i), (select conf from t_i), true, 0);
select pg_temp.expect_detail(format($$select public.project_dependency_set(%L, %L, true)$$, (select conf from t_i), (select upload from t_i)), 'invalid', 'dependency.cycle',
                             'a dependency that closes a cycle is refused');
select pg_temp.expect_detail(format($$select public.project_dependency_set(%L, %L, true)$$, (select (r ->> 'id')::uuid from t_act), (select conf from t_i)), 'invalid', 'dependency.kind',
                             'activities take no dependencies');
select pg_temp.expect_detail(format($$select public.project_dependency_set(%L, %L, true, 400)$$, (select kick from t_i), (select conf from t_i)), 'invalid', 'lag_days', 'lag is within a year');
create temp table t_det as select public.project_detail((select p1 from t_p)) r;
select pg_temp.check((select i -> 'depends_on' -> 0 ->> 'name' = 'Upload employee list (v2)' from t_det, jsonb_array_elements(r -> 'items') i where i ->> 'id' = (select mile::text from t_i)),
                     'the drawer names the first predecessor');
select pg_temp.check((select i -> 'assignees' @> jsonb_build_array(jsonb_build_object('name', 'Kari Prosjektsen'), jsonb_build_object('name', 'Magnus Berg'))
                      from t_det, jsonb_array_elements(r -> 'items') i where i ->> 'id' = (select upload::text from t_i)), 'assignees are staff and customer-side people by name');
select pg_temp.check((select (r -> 'deals' -> 0 ->> 'title') = 'Lumio — Skiftly P6' and (r -> 'deals' -> 0 -> 'value') = 'null'::jsonb from t_det),
                     'a project-only user sees the deal''s title, not its value (spec Q6)');
select pg_temp.check((select (r -> 'ai' ->> 'enabled')::boolean = false and r -> 'ai' ->> 'reason' = 'not_connected:ai' and r -> 'ai' -> 'summary' = 'null'::jsonb from t_det),
                     'no AI banner while the AI connection is missing; the reason is named');
select pg_temp.check(exists (select 1 from app.recents where staff_id = (select emma from t_ids) and entity = 'project' and record_id = (select p1 from t_p))
                 and exists (select 1 from app.audit where action = 'record.read' and target_type = 'project' and target_id = (select p1::text from t_p)),
                     'opening a project is audited and remembered as recent');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (r -> 'deals' -> 0 ->> 'value')::numeric = 64000 from (select public.project_detail((select p1 from t_p)) r) x), 'with deals:see the value shows');

-- move, health, close (PRJ-01, PRJ-06, UF-20 step 6)
select public.follow_set('project', (select p1 from t_p), true);
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_move(%L, %L, 1)$$, (select p1 from t_p), (select setup from t_ph)), 'version_conflict',
                             (select version::text from app.projects where id = (select p1 from t_p)), 'a stale version is a conflict, with the current version');
create temp table t_mv as select public.project_move((select p1 from t_p), (select setup from t_ph), (select version from app.projects where id = (select p1 from t_p))) r;
select pg_temp.check((select phase_id = (select setup from t_ph) from app.projects where id = (select p1 from t_p))
                 and (select count(*) = 2 and count(*) filter (where left_at is not null and phase_id = (select kickoff from t_ph)) = 1
                             and count(*) filter (where left_at is null and phase_id = (select setup from t_ph)) = 1 from app.project_phase_history where project_id = (select p1 from t_p)),
                     'dragging a project changes its phase and logs it (PRJ-01 acceptance)');
select pg_temp.check(exists (select 1 from app.changelog where entity = 'project' and record_id = (select p1 from t_p) and field = 'phase_id' and new_value = to_jsonb((select setup from t_ph)))
                 and exists (select 1 from app.events where kind = 'project.phase_changed' and subject_id = (select p1 from t_p)
                             and payload ->> 'from' = (select kickoff::text from t_ph) and payload ->> 'to' = (select setup::text from t_ph)),
                     'the move is in the history and emits project.phase_changed from → to');
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select tor from t_ids) and key = 'project.phase_changed' and route = '/projects?project=' || (select p1 from t_p)),
                     'followers hear about it');
select pg_temp.expect_detail(format($$select public.project_health_set(%L, 'great')$$, (select p1 from t_p)), 'invalid', 'health', 'health is one of four values');
select public.project_health_set((select p1 from t_p), 'at_risk');
select pg_temp.check((select health = 'at_risk' and health_source = 'manual' and health_set_by = (select emma from t_ids) from app.projects where id = (select p1 from t_p))
                 and exists (select 1 from app.events where kind = 'project.health_changed' and subject_id = (select p1 from t_p) and payload ->> 'to' = 'at_risk' and payload ->> 'source' = 'manual'),
                     'health is set by hand and emits project.health_changed');
select pg_temp.check((select (c ->> 'health') = 'at_risk' from jsonb_array_elements(public.projects_board((select id from t_b)) -> 'cards') c where c ->> 'id' = (select p1::text from t_p)),
                     'the status shows on the board (PRJ-06)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.project_close((select p2 from t_p), 'done');
select pg_temp.check((select status = 'done' and closed_at is not null and closed_by = (select tor from t_ids) from app.projects where id = (select p2 from t_p))
                 and not exists (select 1 from app.project_phase_history where project_id = (select p2 from t_p) and left_at is null)
                 and exists (select 1 from app.events where kind = 'project.completed' and subject_id = (select p2 from t_p) and payload ->> 'status' = 'done'),
                     'closing ends the stay in the phase and emits project.completed');
select pg_temp.expect_detail(format($$select public.project_move(%L, %L)$$, (select p2 from t_p), (select survey from t_ph)), 'invalid', 'status', 'a closed project does not move');
select pg_temp.expect_detail(format($$select public.project_close(%L, 'archived')$$, (select p2 from t_p)), 'invalid', 'status', 'only open, done and canceled');
select pg_temp.check(not (public.projects_board((select id from t_b)) -> 'cards') @> jsonb_build_array(jsonb_build_object('id', (select p2 from t_p)))
                 and (public.projects_board((select id from t_b), '{"closed":true}') -> 'cards') @> jsonb_build_array(jsonb_build_object('id', (select p2 from t_p))),
                     'closed projects leave the board and come back with the closed filter (spec Q5)');
select public.project_close((select p2 from t_p), 'open');
select pg_temp.check((select status = 'open' and closed_at is null from app.projects where id = (select p2 from t_p))
                 and exists (select 1 from app.project_phase_history where project_id = (select p2 from t_p) and left_at is null)
                 and exists (select 1 from app.events where kind = 'project.reopened' and subject_id = (select p2 from t_p)), 'reopening starts a new stay');

-- configuration round: rename a phase, reorder, archive a board
select pg_temp.as_staff('tor@orgpuls.no');
select public.project_phase_save((select survey from t_ph), null, '{"name":"First survey","color":"#cfe0f5"}');
select public.project_phases_reorder((select id from t_b), array[(select survey from t_ph), (select kickoff from t_ph), (select setup from t_ph)]);
select pg_temp.check((select array_agg(name order by ord) from app.project_phases where board_id = (select id from t_b)) = array['First survey', 'Kickoff', 'Setup']
                 and (select color = '#CFE0F5' from app.project_phases where id = (select survey from t_ph)), 'phases are renamed, recoloured and reordered');
select public.project_phases_reorder((select id from t_b), array[(select kickoff from t_ph), (select setup from t_ph), (select survey from t_ph)]);
create temp table t_b3 as select (public.project_board_save(null, '{"name":"Arkiv P6","phases":[{"name":"Eneste"}]}') ->> 'id')::uuid id;
select public.project_board_save((select id from t_b3), '{"archived":true}');
select pg_temp.check(not public.project_boards_get() @> jsonb_build_array(jsonb_build_object('id', (select id from t_b3)))
                 and public.project_boards_get(true) @> jsonb_build_array(jsonb_build_object('id', (select id from t_b3))), 'an archived board leaves the select');
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'X', 'board_id', %L))$$, (select id from t_b3)), 'invalid', 'board_id', 'no new project on an archived board');
-- deals (spec §1.6)
select public.project_deal_link((select p1 from t_p), (select deal2 from t_ids), true, true);
select pg_temp.check((select array_agg(deal_id order by is_primary desc) from app.project_deals where project_id = (select p1 from t_p)) = array[(select deal2 from t_ids), (select deal from t_ids)],
                     'a second deal can become the primary');
select public.project_deal_link((select p1 from t_p), (select deal2 from t_ids), false);
select pg_temp.check((select bool_and(is_primary) and count(*) = 1 from app.project_deals where project_id = (select p1 from t_p)), 'unlinking the primary promotes the other');

-- ---------------------------------------------------------------------------
-- paste, bulk, groups, shift (PRJ-08, PRJ-04)
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_g as select (public.project_group_save((select p1 from t_p), null, 'Kickoff') ->> 'id')::uuid id;
select pg_temp.expect_detail(format($$select public.project_items_add(%L, %L, (select jsonb_agg(jsonb_build_object('name', 'L' || n)) from generate_series(1, 201) n))$$, (select p1 from t_p), (select id from t_g)),
                             'invalid', 'items', 'at most 200 lines at a time');
select pg_temp.expect_detail(format($$select public.project_items_add(%L, %L, '[{"name":"A"},{"name":"B","due_on":"16.10"}]')$$, (select p1 from t_p), (select id from t_g)),
                             'invalid', 'items[1].due_on', 'a line the app did not parse to a date is named');
create temp table t_paste as select public.project_items_add((select p1 from t_p), (select id from t_g), '[{"name":"Send invitation","due_on":"2026-10-20"},{"name":"Book room"},{"name":"Order coffee"}]') r;
select pg_temp.check((select count(*) = 3 and bool_and(source = 'paste' and group_id = (select id from t_g)) from app.project_items where id in (select jsonb_array_elements_text(r -> 'ids')::uuid from t_paste))
                 and (select due_on = '2026-10-20' from app.project_items where name = 'Send invitation' and project_id = (select p1 from t_p)),
                     'pasted lines become tasks in the chosen group (PRJ-08 acceptance)');
select pg_temp.check((select count(*) = 1 from app.events where kind = 'project.updated' and subject_id = (select p1 from t_p) and payload -> 'fields' = '["items"]' and (payload ->> 'count')::int = 3),
                     'one project.updated event for the paste');
select pg_temp.expect_detail(format($$select public.project_items_bulk(%L, array(select jsonb_array_elements_text(r -> 'ids')::uuid from t_paste), '{"shift_days":2}')$$, (select p1 from t_p)),
                             'forbidden', 'projects:bulk', 'bulk edit needs projects:bulk');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_bulk as select public.project_items_bulk((select p1 from t_p), array(select jsonb_array_elements_text(r -> 'ids')::uuid from t_paste),
                                                jsonb_build_object('shift_days', 2, 'owner_id', (select emma from t_ids))) r;
select pg_temp.check((select (r ->> 'updated')::int = 3 from t_bulk)
                 and (select due_on = '2026-10-22' and owner_id = (select emma from t_ids) from app.project_items where name = 'Send invitation' and project_id = (select p1 from t_p)),
                     'bulk shifts due dates and sets the owner');

select public.project_items_reorder((select p1 from t_p), array(select x::uuid from t_paste, jsonb_array_elements_text(r -> 'ids') with ordinality y(x, n) order by n desc));
select pg_temp.check((select array_agg(name order by ord) from app.project_items where id in (select jsonb_array_elements_text(r -> 'ids')::uuid from t_paste))
                     = array['Order coffee', 'Book room', 'Send invitation'], 'items can be reordered');
-- a shift keeps the spacing inside a group; a successor outside is flagged, not moved (spec Q3)
create temp table t_s as select (public.project_create(jsonb_build_object('name', 'Shift P6', 'board_id', (select id from t_b), 'starts_on', '2026-10-05')) ->> 'id')::uuid p;
create temp table t_sg as select (public.project_group_save((select p from t_s), null, 'G') ->> 'id')::uuid g;
create temp table t_si as select
  (public.project_item_save((select p from t_s), null, jsonb_build_object('name', 'T1', 'group_id', (select g from t_sg), 'starts_on', '2026-10-05', 'due_on', '2026-10-08')) ->> 'id')::uuid t1,
  (public.project_item_save((select p from t_s), null, jsonb_build_object('name', 'T2', 'group_id', (select g from t_sg), 'starts_on', '2026-10-08', 'due_on', '2026-10-16')) ->> 'id')::uuid t2,
  (public.project_item_save((select p from t_s), null, jsonb_build_object('kind', 'milestone', 'name', 'M', 'group_id', (select g from t_sg), 'due_on', '2026-10-16')) ->> 'id')::uuid m,
  (public.project_item_save((select p from t_s), null, '{"name":"After","starts_on":"2026-10-17","due_on":"2026-10-20"}') ->> 'id')::uuid s;
select public.project_dependency_set((select m from t_si), (select s from t_si), true);
create temp table t_shift as select public.project_group_shift((select p from t_s), (select g from t_sg), 5) r;
select pg_temp.check((select (r ->> 'shifted')::int = 3 from t_shift)
                 and (select starts_on = '2026-10-10' and due_on = '2026-10-13' from app.project_items where id = (select t1 from t_si))
                 and (select starts_on = '2026-10-13' and due_on = '2026-10-21' from app.project_items where id = (select t2 from t_si))
                 and (select due_on = '2026-10-21' from app.project_items where id = (select m from t_si))
                 and (select starts_on = '2026-10-17' from app.project_items where id = (select s from t_si)),
                     'shifting a phase keeps the spacing between its items (PRJ-04 acceptance); the successor stays');
select pg_temp.check((select r -> 'flagged' = jsonb_build_array(jsonb_build_object('predecessor', (select m from t_si), 'successor', (select s from t_si))) from t_shift),
                     'the successor that now starts before its predecessor ends is flagged');
select pg_temp.expect_detail(format($$select public.project_group_shift(%L, %L, 0)$$, (select p from t_s), (select g from t_sg)), 'invalid', 'days', 'a shift moves by at least a day');

-- removing items takes their subtasks and dependencies; an activity stays on its deal
create temp table t_del as select public.project_items_delete(array[(select conf from t_i)]) r;
select pg_temp.check((select (r ->> 'deleted')::int = 1 from t_del)
                 and (select deleted_at is not null from app.project_items where id = (select sub from t_i2))
                 and not exists (select 1 from app.project_item_dependencies where successor_id = (select conf from t_i)),
                     'removing a task removes its subtasks and its dependencies');
select public.project_items_delete(array[(select (r ->> 'id')::uuid from t_act)]);
select pg_temp.check((select project_id is null and deleted_at is null from app.activities where id = (select (r ->> 'activity_id')::uuid from t_act)),
                     'a removed activity item leaves the activity on its deal, unlinked');

-- ---------------------------------------------------------------------------
-- the timeline (§1.2), against hand-computed figures: range 1 Oct – 31 Dec 2026, 92 days
create temp table t_tl as select (public.project_create(jsonb_build_object('name', 'Tidslinje P6', 'board_id', (select id from t_b), 'starts_on', '2026-10-05', 'ends_on', '2026-12-18')) ->> 'id')::uuid p;
create temp table t_tlg as select (public.project_group_save((select p from t_tl), null, 'Kickoff') ->> 'id')::uuid g;
select public.project_item_save((select p from t_tl), null, jsonb_build_object('name', 'Kickoff meeting', 'group_id', (select g from t_tlg), 'starts_on', '2026-10-05', 'due_on', '2026-10-08'));
select public.project_item_save((select p from t_tl), null, jsonb_build_object('name', 'Upload employee list', 'group_id', (select g from t_tlg), 'starts_on', '2026-10-08', 'due_on', '2026-10-16'));
select public.project_item_save((select p from t_tl), null, jsonb_build_object('kind', 'milestone', 'name', 'Employee list ready', 'group_id', (select g from t_tlg), 'due_on', '2026-10-16'));
select public.project_item_save((select p from t_tl), null, '{"name":"Undated"}');
create temp table t_tlr as select public.project_timeline((select p from t_tl)) r;
select pg_temp.check((select r -> 'range' ->> 'from' = '2026-10-01' and r -> 'range' ->> 'to' = '2026-12-31' and (r -> 'range' ->> 'days')::int = 92
                             and r -> 'range' -> 'months' = '["2026-10-01","2026-11-01","2026-12-01"]' from t_tlr), 'the range runs from the first month to the last, 92 days');
select pg_temp.check((select (x ->> 'x')::numeric = 4.35 and (x ->> 'w')::numeric = 4.35 from t_tlr, jsonb_array_elements(r -> 'rows') x where x ->> 'name' = 'Kickoff meeting')
                 and (select (x ->> 'x')::numeric = 7.61 and (x ->> 'w')::numeric = 9.78 from t_tlr, jsonb_array_elements(r -> 'rows') x where x ->> 'name' = 'Upload employee list')
                 and (select (x ->> 'x')::numeric = 16.30 and (x ->> 'w')::numeric = 1.09 from t_tlr, jsonb_array_elements(r -> 'rows') x where x ->> 'name' = 'Employee list ready'),
                     'bars: x = (start − 1 Oct) ÷ 92, w = (end − start + 1) ÷ 92, a milestone one day');
select pg_temp.check((select (x ->> 'x')::numeric = 4.35 and (x ->> 'w')::numeric = 13.04 and x ->> 'start' = '2026-10-05' and x ->> 'end' = '2026-10-16'
                      from t_tlr, jsonb_array_elements(r -> 'groups') x), 'the group bar spans its items'' earliest start to latest due');
select pg_temp.check((select x -> 'x' = 'null'::jsonb from t_tlr, jsonb_array_elements(r -> 'rows') x where x ->> 'name' = 'Undated'), 'an undated item is listed without a bar');
select pg_temp.check((select (r -> 'today_pct') is not distinct from (case when app.prj_today() between '2026-10-01' and '2026-12-31'
                             then to_jsonb(round((app.prj_today() - date '2026-10-01') * 100.0 / 92, 2)) else 'null'::jsonb end) from t_tlr),
                     'the today line sits at (today − 1 Oct) ÷ 92, and is absent outside the range');
select pg_temp.check((public.project_timeline((select p from t_tl), '2026-09-15', 6) -> 'range' ->> 'from') = '2026-09-01'
                 and (public.project_timeline((select p from t_tl), '2026-09-15', 6) -> 'range' ->> 'to') = '2027-02-28', 'the range can be chosen');
create temp table t_od as select (public.project_create(jsonb_build_object('name', 'Forsinket P6', 'board_id', (select id from t_b))) ->> 'id')::uuid p;
select public.project_item_save((select p from t_od), null, jsonb_build_object('name', 'Late', 'due_on', app.prj_today() - 3));
select pg_temp.check((select (x ->> 'late_days')::int = 3 from jsonb_array_elements(public.project_detail((select p from t_od)) -> 'items') x)
                 and (select (x ->> 'overdue')::boolean from jsonb_array_elements(public.project_timeline((select p from t_od)) -> 'rows') x)
                 and (select (c ->> 'overdue')::int = 1 from jsonb_array_elements(public.projects_board((select id from t_b)) -> 'cards') c where c ->> 'id' = (select p::text from t_od)),
                     'lateness is today − due date, derived when read (PRJ-04 RU)');
create temp table t_empty as select (public.project_create(jsonb_build_object('name', 'Udatert P6', 'board_id', (select id from t_b))) ->> 'id')::uuid p;
select pg_temp.check((public.project_timeline((select p from t_empty)) -> 'range') = 'null'::jsonb, 'a project without dates has an empty timeline');
update app.recents set at = now() + interval '1 minute' where record_id = (select p from t_od);   -- one transaction: every recent has the same now()
select pg_temp.check((public.project_timeline(null) -> 'project' ->> 'id') = (select p::text from t_od), 'without a project the timeline opens the one opened last');

-- ---------------------------------------------------------------------------
-- templates (PRJ-05)
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"Mal"}')$$, 'forbidden', 'projects:add', 'a read-only analyst cannot save a template');
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_tpl as select (public.project_template_save(null, jsonb_build_object('name', 'Kundeoppstart P6', 'organized_by', 'phases', 'board_id', (select id from t_b),
  'groups', jsonb_build_array(jsonb_build_object('key', 'g1', 'name', 'Kickoff', 'phase_id', (select kickoff from t_ph)), jsonb_build_object('key', 'g2', 'name', 'Setup')),
  'items', jsonb_build_array(
    jsonb_build_object('key', 'i1', 'group', 'g1', 'name', 'Kickoff meeting', 'start_offset_days', 0, 'due_offset_days', 2),
    jsonb_build_object('key', 'i2', 'group', 'g1', 'name', 'Upload employee list', 'start_offset_days', 3, 'due_offset_days', 8, 'assignee', 'owner'),
    jsonb_build_object('key', 'm1', 'group', 'g1', 'kind', 'milestone', 'name', 'Employee list ready', 'due_offset_days', 11),
    jsonb_build_object('key', 'a1', 'group', 'g2', 'kind', 'activity', 'name', 'Training call', 'activity_type', 'meeting', 'activity_time', '10:00', 'activity_duration_min', 60, 'due_offset_days', 14),
    jsonb_build_object('key', 's1', 'parent', 'i2', 'name', 'Check columns', 'due_offset_days', 5),
    jsonb_build_object('key', 'i3', 'group', 'g2', 'name', 'Schedule baseline', 'start_offset_days', 30, 'due_offset_days', 32)),
  'dependencies', jsonb_build_array(jsonb_build_object('pred', 'i2', 'succ', 'm1'), jsonb_build_object('pred', 'm1', 'succ', 'i3', 'lag_days', 1)))) ->> 'id')::uuid id;
select pg_temp.check((select (x ->> 'groups')::int = 2 and (x ->> 'tasks')::int = 4 and (x ->> 'milestones')::int = 1 and (x ->> 'activities')::int = 1 and (x ->> 'dependencies')::int = 2
                             and (select array_agg((y ->> 'day')::int) from jsonb_array_elements(x -> 'preview') y) = array[2, 5, 8, 11, 14] and (x ->> 'can_edit')::boolean
                      from jsonb_array_elements(public.project_templates_get()) x where x ->> 'id' = (select id::text from t_tpl)),
                     'a template card counts its groups, tasks, milestones, activities and dependencies, and previews five items as «Day N»');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"kundeoppstart p6"}')$$, 'invalid', 'name', 'template names are unique');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"T2","items":[{"key":"a","kind":"activity","name":"Call","activity_type":"call"}]}')$$,
                             'invalid', 'items[0].activity_time', 'an activity in a template has a time of day');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"T2","items":[{"key":"m","kind":"milestone","name":"M"},{"key":"s","parent":"m","name":"S"}]}')$$,
                             'invalid', 'items[1].parent', 'a subtask''s parent is a task');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"T2","items":[{"key":"a","name":"A"},{"key":"b","name":"B"}],"dependencies":[{"pred":"a","succ":"b"},{"pred":"b","succ":"a"}]}')$$,
                             'invalid', 'dependency.cycle', 'template dependencies cannot loop');
select pg_temp.expect_detail($$select public.project_template_save(null, '{"name":"T2","items":[{"key":"a","name":"A","start_offset_days":5,"due_offset_days":2}]}')$$,
                             'invalid', 'items[0]', 'an item is due on or after its start');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_tpl_tor as select (public.project_template_save(null, '{"name":"Tors mal P6","items":[{"key":"x","name":"X","due_offset_days":1}]}') ->> 'id')::uuid id;
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_template_save(%L, '{"name":"Endret"}')$$, (select id from t_tpl_tor)), 'forbidden', 'projects:configure',
                             'someone else''s template needs projects:configure (spec Q7)');
select pg_temp.expect_detail(format($$select public.project_template_save(%L, '{"name":"Kundeoppstart P6"}', 9)$$, (select id from t_tpl)), 'version_conflict', '1', 'a stale template version is a conflict');

create temp table t_tget as select public.project_template_get((select id from t_tpl)) r;
select pg_temp.check((select jsonb_array_length(r -> 'items') = 6 and jsonb_array_length(r -> 'dependency_list') = 2 and jsonb_array_length(r -> 'group_list') = 2
                             and r -> 'items' @> '[{"kind":"activity","activity_type":"meeting","activity_time":"10:00"}]' from t_tget),
                     'the template editor reads groups, items and dependencies');
select pg_temp.check((public.project_template_save((select id from t_tpl), jsonb_build_object('groups', (select r -> 'group_list' from t_tget), 'items', (select r -> 'items' from t_tget),
                        'dependencies', (select r -> 'dependency_list' from t_tget))) ->> 'version')::int = 2,
                     'and what it reads can be saved back as the new set');
-- instantiation: dated from the start
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'Uten start', 'board_id', %L, 'template_id', %L))$$, (select id from t_b), (select id from t_tpl)),
                             'invalid', 'starts_on', 'a template needs a start date');
create temp table t_fromtpl as select (public.project_create(jsonb_build_object('name', 'Fra mal P6', 'board_id', (select id from t_b), 'template_id', (select id from t_tpl),
                                                                                 'starts_on', '2026-11-02')) ->> 'id')::uuid p;
create temp table t_ft as select i.*, coalesce(i.name, a.subject) nm, a.starts_at from app.project_items i left join app.activities a on a.id = i.activity_id where i.project_id = (select p from t_fromtpl);
select pg_temp.check((select starts_on = '2026-11-02' and due_on = '2026-11-04' and source = 'template' from t_ft where nm = 'Kickoff meeting')
                 and (select starts_on = '2026-11-05' and due_on = '2026-11-10' and owner_id = (select emma from t_ids) from t_ft where nm = 'Upload employee list')
                 and (select starts_on is null and due_on = '2026-11-13' from t_ft where nm = 'Employee list ready')
                 and (select starts_on = '2026-12-02' and due_on = '2026-12-04' from t_ft where nm = 'Schedule baseline')
                 and (select due_on = '2026-11-07' and parent_id = (select id from t_ft where nm = 'Upload employee list') from t_ft where nm = 'Check columns'),
                     'a project from a template gets dated items from its start date (PRJ-05 acceptance)');
select pg_temp.check((select kind = 'activity' and starts_at = timestamptz '2026-11-16 10:00 Europe/Oslo' from t_ft where nm = 'Training call')
                 and (select a.duration_min = 60 and a.owner_id = (select emma from t_ids) from app.activities a where a.project_id = (select p from t_fromtpl)),
                     'its activity is at the day and time the template says, for the project''s owner');
select pg_temp.check((select count(*) from app.project_item_dependencies d join t_ft x on x.id = d.predecessor_id) = 2
                 and (select count(*) = 2 and count(*) filter (where phase_id = (select kickoff from t_ph)) = 1 from app.project_groups where project_id = (select p from t_fromtpl))
                 and exists (select 1 from app.events where kind = 'project.template_applied' and subject_id = (select p from t_fromtpl) and payload ->> 'template' = (select id::text from t_tpl)),
                     'its groups (with their phase on the same board) and dependencies are copied, and project.template_applied is emitted');
-- save as template
create temp table t_sat as select (public.project_template_from_project((select p from t_tl), 'Fra prosjekt P6') ->> 'id')::uuid id;
select pg_temp.check((select source_project_id = (select p from t_tl) from app.project_templates where id = (select id from t_sat))
                 and (select start_offset_days = 0 and due_offset_days = 3 from app.project_template_items where template_id = (select id from t_sat) and name = 'Kickoff meeting')
                 and (select start_offset_days = 3 and due_offset_days = 11 from app.project_template_items where template_id = (select id from t_sat) and name = 'Upload employee list')
                 and (select kind = 'milestone' and due_offset_days = 11 from app.project_template_items where template_id = (select id from t_sat) and name = 'Employee list ready'),
                     'a project saved as a template keeps its offsets from the start');
select public.project_template_delete((select id from t_sat));
select pg_temp.check(not public.project_templates_get() @> jsonb_build_array(jsonb_build_object('id', (select id from t_sat))),
                     'a creator removes their own template');

-- ---------------------------------------------------------------------------
-- reports (§1.4): performance per health and median days per phase, hand-computed
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_r as select
  (public.project_create(jsonb_build_object('name', 'RA P6', 'board_id', (select id from t_b2), 'owner_id', (select emma from t_ids))) ->> 'id')::uuid ra,
  (public.project_create(jsonb_build_object('name', 'RB P6', 'board_id', (select id from t_b2))) ->> 'id')::uuid rb,
  (public.project_create(jsonb_build_object('name', 'RC P6', 'board_id', (select id from t_b2))) ->> 'id')::uuid rc;
select public.project_health_set((select ra from t_r), 'on_track');
select public.project_health_set((select rb from t_r), 'at_risk');
select pg_temp.as_nobody();
insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, left_at, source)
select x.p, (select id from t_b2), (select id from app.project_phases where board_id = (select id from t_b2) and name = x.ph), now() - interval '40 days', now() - interval '40 days' + make_interval(days => x.d), 'system'
from t_r, lateral (values (t_r.ra, 'R1', 2), (t_r.rb, 'R1', 4), (t_r.rc, 'R1', 9), (t_r.ra, 'R2', 1), (t_r.rb, 'R2', 3)) x(p, ph, d);
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_rep as select public.project_reports((select id from t_b2)) r;
select pg_temp.check((select jsonb_agg(jsonb_build_object(coalesce(x ->> 'health', 'none'), (x ->> 'n')::int) order by ord) from t_rep, jsonb_array_elements(r -> 'performance') with ordinality y(x, ord))
                     = '[{"on_track":1},{"at_risk":1},{"off_track":0},{"on_hold":0},{"none":1}]', 'performance counts open projects per health, with a «not set» bucket');
select pg_temp.check((select bool_and((x ->> 'w')::numeric = case when (x ->> 'n')::int = 1 then 100 else 0 end) from t_rep, jsonb_array_elements(r -> 'performance') x),
                     'bar width is n ÷ max × 100 (the design''s v × 22 % overflowed)');
select pg_temp.check((select jsonb_agg(jsonb_build_object(x ->> 'phase', jsonb_build_array((x ->> 'n')::int, (x -> 'median_days')))) from t_rep, jsonb_array_elements(r -> 'duration') x)
                     = '[{"R1":[3,4.0]},{"R2":[2,2.0]},{"R3":[0,null]}]', 'duration by phase: the median days of finished stays, with n; a phase with none shows nothing');
select pg_temp.check((select r -> 'hooks' -> 'triggers' ? 'phase_changed' and r -> 'hooks' -> 'actions' ? 'create_from_template' and not (r -> 'hooks' ->> 'actions_available')::boolean from t_rep),
                     'the hooks come from the registry, and say the actions are not live until the executor calls them (V-P6P-01)');
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_rep_e as select public.project_reports((select id from t_b2)) r;
select pg_temp.check((select (r ->> 'own_only')::boolean and (select jsonb_agg((x ->> 'n')::int) from jsonb_array_elements(r -> 'performance') x) = '[1,0,0,0,0]'
                             and (select jsonb_agg(x -> 'median_days') from jsonb_array_elements(r -> 'duration') x) = '[2.0,1.0,null]' from t_rep_e),
                     'without projects:reports_others the reports count own projects only (the Insights rule)');
select pg_temp.expect_detail(format($$select public.project_reports(%L, '2026-10-01', '2026-09-01')$$, (select id from t_b2)), 'invalid', 'to', 'a period ends after it starts');

-- ---------------------------------------------------------------------------
-- events start workflows (AUT-02); the project_action step (AUT-07, PRJ-09) as it will run
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_wf as select (public.workflow_save(null, '{"name":"P6 fase-varsel","trigger_type":"event","trigger_config":{"entity":"project","event":"phase_changed"}}',
  '{"steps":[{"key":"s1","kind":"notify","config":{"to":"@record_owner","message":"Fase endret for {project.name}"}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_wf), 'active');
select public.project_move((select ra from t_r), (select id from app.project_phases where board_id = (select id from t_b2) and name = 'R2'));
select app.sub_workflows(e) from app.events e where e.kind = 'project.phase_changed' and e.subject_id = (select ra from t_r);
select pg_temp.check(exists (select 1 from app.workflow_runs where workflow_id = (select id from t_wf) and subject_type = 'project' and subject_id = (select ra from t_r) and state = 'completed')
                 and exists (select 1 from app.notifications where staff_id = (select emma from t_ids) and key = 'workflow.notice' and route = '/projects'
                             and params ->> 'message' = 'Fase endret for RA P6'), 'a project event starts a workflow on «project · phase changed»');
create temp table t_wf2 as select (public.workflow_save(null, '{"name":"P6 vunnet → prosjekt","trigger_type":"event","trigger_config":{"entity":"deal","event":"won"}}',
  jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 's1', 'kind', 'project_action', 'config',
    jsonb_build_object('action', 'create_from_template', 'template_id', (select id from t_tpl), 'board_id', (select id from t_b)))))) ->> 'id')::uuid id;
select pg_temp.expect_detail(format($$select public.workflow_set_state(%L, 'active')$$, (select id from t_wf2)), 'invalid', 'not_available:projects',
                             'until the merge wires the executor, a project_action workflow cannot be activated (V-P6P-01)');
select pg_temp.expect_detail($$select app.wf_project_validate('s1', '{"action":"explode"}')$$, 'invalid', 'graph.s1.action', 'an unknown action is refused');
select pg_temp.expect_detail($$select app.wf_project_validate('s1', '{"action":"move_phase"}')$$, 'invalid', 'graph.s1.phase_id', 'move_phase names its phase');
select pg_temp.check(app.wf_project_blocker('{"action":"create_from_template"}') = 'project_template_missing'
                 and app.wf_project_blocker(jsonb_build_object('action', 'create_from_template', 'template_id', (select id from t_tpl))) is null,
                     'the seeded «won_project» step is blocked until a template is chosen');
select app.wf_project_validate('s1', jsonb_build_object('action', 'create_from_template', 'template_id', (select id from t_tpl), 'board_id', (select id from t_b), 'start', 'won_at'));
select pg_temp.as_nobody();
insert into app.workflow_runs (workflow_id, version, subject_type, subject_id) select (select id from t_wf2), 1, 'deal', (select deal from t_ids);
select set_config('app.acting_as', (select tor::text from t_ids), true);
create temp table t_run as select app.wf_project_action(r, w, jsonb_build_object('action', 'create_from_template', 'template_id', (select id from t_tpl), 'board_id', (select id from t_b),
  'owner', '@workflow_owner', 'start', 'today')) out
from app.workflow_runs r join app.workflows w on w.id = r.workflow_id where r.workflow_id = (select id from t_wf2) and r.subject_id = (select deal from t_ids);
select pg_temp.check((select created_source = 'workflow' and owner_id = (select tor from t_ids) and organization_id = (select org from t_ids) and starts_on = current_date
                      from app.projects where id = (select (out ->> 'project')::uuid from t_run))
                 and exists (select 1 from app.project_deals where project_id = (select (out ->> 'project')::uuid from t_run) and deal_id = (select deal from t_ids) and is_primary)
                 and (select count(*) = 6 from app.project_items where project_id = (select (out ->> 'project')::uuid from t_run))
                 and exists (select 1 from app.changelog where entity = 'project' and record_id = (select (out ->> 'project')::uuid from t_run) and field = '*created' and source = 'workflow'),
                     'a workflow can create a project when a deal is won: the deal, its organisation, the template''s items (PRJ-09 acceptance)');
insert into app.workflow_runs (workflow_id, version, subject_type, subject_id) select (select id from t_wf2), 1, 'project', (select (out ->> 'project')::uuid from t_run) from t_run;
create temp table t_run2 as select
  app.wf_project_action(r, w, jsonb_build_object('action', 'move_phase', 'phase_id', (select survey from t_ph))) mv,
  app.wf_project_action(r, w, '{"action":"assign_task","item_name":"kickoff meeting","assignee":"@workflow_owner"}') asg,
  app.wf_project_action(r, w, jsonb_build_object('action', 'add_tasks_from_template', 'template_id', (select id from t_tpl_tor), 'group', 'Ekstra')) add
from app.workflow_runs r join app.workflows w on w.id = r.workflow_id where r.workflow_id = (select id from t_wf2) and r.subject_type = 'project';
select pg_temp.check((select phase_id = (select survey from t_ph) from app.projects where id = (select (out ->> 'project')::uuid from t_run))
                 and exists (select 1 from app.project_phase_history where project_id = (select (out ->> 'project')::uuid from t_run) and source = 'workflow')
                 and (select owner_id = (select tor from t_ids) from app.project_items where id = (select (asg ->> 'item')::uuid from t_run2))
                 and (select (add ->> 'items')::int = 1 from t_run2)
                 and exists (select 1 from app.project_items i join app.project_groups g on g.id = i.group_id where i.project_id = (select (out ->> 'project')::uuid from t_run) and g.name = 'Ekstra' and i.name = 'X'),
                     'move phase, assign task and add tasks from a template work on the project subject');
update app.workflows set owner_id = (select ingrid from t_ids) where id = (select id from t_wf2);
select set_config('app.acting_as', (select ingrid::text from t_ids), true);
select pg_temp.expect_detail(format($$select app.wf_project_action(r, w, %L) from app.workflow_runs r join app.workflows w on w.id = r.workflow_id where r.workflow_id = %L and r.subject_type = 'deal'$$,
                                    jsonb_build_object('action', 'create_from_template', 'template_id', (select id from t_tpl), 'board_id', (select id from t_b)), (select id from t_wf2)),
                             'forbidden', 'projects:add', 'a workflow never does more than its owner may');
select set_config('app.acting_as', '', true);

-- ---------------------------------------------------------------------------
-- settings with their effect: project_ai (with the AI connection) and the visibility default
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_ai_summary_request(%L)$$, (select p1 from t_p)), 'forbidden', 'projects:ai', 'the AI summary needs projects:ai');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_ai_summary_request(%L)$$, (select p1 from t_p)), 'not_connected', 'ai', 'without the AI connection it is not_connected, never faked');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('project_ai', 'off');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_ai_summary_request(%L)$$, (select p1 from t_p)), 'forbidden', 'setting:project_ai', 'with project_ai off it is refused, the setting named');
select pg_temp.check((public.project_detail((select p1 from t_p)) -> 'ai' ->> 'reason') = 'forbidden:setting:project_ai', 'and the drawer says why there is no banner');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('project_ai', 'on');
select pg_temp.as_nobody();
update app.integration_connections set status = 'connected' where provider = 'ai';
select pg_temp.as_staff('emma@orgpuls.no');
create temp table t_ai as select public.project_ai_summary_request((select p1 from t_p)) r;
select pg_temp.check((select r ->> 'state' = 'requested' from t_ai) and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'project_ai_summary' and message ->> 'summary_id' = (select r ->> 'id' from t_ai))
                 and (public.project_ai_summary_request((select p1 from t_p)) ->> 'id') = (select r ->> 'id' from t_ai),
                     'with the connection a summary is queued for the AI worker, once');
select pg_temp.as_nobody();
select public.worker_project_summary_ready((select (r ->> 'id')::uuid from t_ai), jsonb_build_object('state', 'ready', 'suggested_health', 'off_track',
  'summary', 'Importen er forsinket.', 'recommendations', jsonb_build_array('Bekreft ny dato'), 'sources', jsonb_build_array(jsonb_build_object('entity', 'project', 'id', (select p1 from t_p)))));
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check((select (r -> 'ai' ->> 'enabled')::boolean and r -> 'ai' -> 'summary' ->> 'suggested_health' = 'off_track' from (select public.project_detail((select p1 from t_p)) r) x),
                     'the ready summary shows in the drawer');
select pg_temp.expect_detail(format($$select public.project_health_set(%L, 'on_track', null, %L)$$, (select p1 from t_p), (select r ->> 'id' from t_ai)), 'invalid', 'health',
                             '«Use suggestion» takes the suggested health, not another');
select public.project_health_set((select p1 from t_p), null, null, (select (r ->> 'id')::uuid from t_ai));
select pg_temp.check((select health = 'off_track' and health_source = 'ai_suggestion' from app.projects where id = (select p1 from t_p))
                 and (select applied_by = (select emma from t_ids) from app.project_ai_summaries where id = (select (r ->> 'id')::uuid from t_ai)),
                     '«Use suggestion» sets the health with source ai_suggestion and marks the summary applied');
-- the brief from a deal (PRJ-02, UF-20 step 2)
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_fd as select public.project_create_from_deal((select deal from t_ids), jsonb_build_object('draft_brief', true, 'board_id', (select id from t_b))) r;
select pg_temp.check((select name = 'Lumio — Skiftly P6' and person_id = (select person from t_ids) and organization_id = (select org from t_ids) and created_source = 'deal' and brief_state = 'drafting'
                      from app.projects where id = (select (r ->> 'id')::uuid from t_fd))
                 and exists (select 1 from app.project_deals where project_id = (select (r ->> 'id')::uuid from t_fd) and deal_id = (select deal from t_ids))
                 and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'project_brief' and message ->> 'project_id' = (select r ->> 'id' from t_fd)),
                     'a project created from a deal shows the deal and its contacts (PRJ-02 acceptance), with its brief queued');
select pg_temp.as_nobody();
select public.worker_project_brief_ready((select (r ->> 'id')::uuid from t_fd), 'Kunden ønsker oppstart i uke 42.');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select brief_state = 'draft' and description = 'Kunden ønsker oppstart i uke 42.' from app.projects where id = (select (r ->> 'id')::uuid from t_fd)), 'the brief arrives as a draft');
select public.project_brief_review((select (r ->> 'id')::uuid from t_fd));
select pg_temp.check((select brief_state = 'reviewed' from app.projects where id = (select (r ->> 'id')::uuid from t_fd)), 'and is marked reviewed by a person');
select pg_temp.as_nobody();
update app.integration_connections set status = 'not_connected' where provider = 'ai';
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_cnt as select count(*) n from app.projects;
select pg_temp.expect_detail(format($$select public.project_create_from_deal(%L, '{"draft_brief":true}')$$, (select deal from t_ids)), 'not_connected', 'ai', 'asking for a brief without the AI is not_connected');
select pg_temp.check((select count(*) from app.projects) = (select n from t_cnt), 'and makes no project');
-- the visibility default (setting visibility_default, scope project)
select public.setting_set('visibility_default', 'owner', 'project');
create temp table t_vis as select (public.project_create(jsonb_build_object('name', 'Synlighet P6', 'board_id', (select id from t_b))) ->> 'id')::uuid p;
select pg_temp.check((select visibility = 'owner' from app.projects where id = (select p from t_vis)),
                     'a new project takes the visibility default for projects');
select public.setting_set('visibility_default', 'all', 'project');

-- ---------------------------------------------------------------------------
-- status reports (PRJ-07) and files (CRM-05)
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_status_report_request(%L, '{"summary":false}')$$, (select p1 from t_p)), 'invalid', 'sections', 'a report includes something');
select pg_temp.expect_detail(format($$select public.project_status_report_request(%L, jsonb_build_object('note_ids', jsonb_build_array(%L)))$$, (select p1 from t_p), gen_random_uuid()),
                             'invalid', 'sections.note_ids', 'only this project''s notes can be included');
create temp table t_sr as select public.project_status_report_request((select p1 from t_p), '{"summary":true,"milestones":true,"done_since":"2026-10-01"}', 'Alt går etter planen.') r;
select pg_temp.check((select state = 'requested' and summary = 'Alt går etter planen.' and not ai_drafted from app.project_status_reports where id = (select (r ->> 'id')::uuid from t_sr))
                 and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'project_status_report' and message ->> 'report_id' = (select r ->> 'id' from t_sr)),
                     'a status report with a hand-written summary needs no AI and goes to the PDF worker');
select pg_temp.expect_detail(format($$select public.project_status_report_request(%L, '{"summary":true}', null, true)$$, (select p1 from t_p)), 'not_connected', 'ai', 'an AI draft needs the connection');
select pg_temp.as_nobody();
select pg_temp.expect_detail(format($$select public.worker_status_report_ready(%L, '../etc/x.pdf', 10)$$, (select r ->> 'id' from t_sr)), 'invalid', 'path', 'the worker''s path is the project''s own');
select public.worker_status_report_ready((select (r ->> 'id')::uuid from t_sr), 'project/' || (select p1 from t_p) || '/reports/r1.pdf', 4321);
select pg_temp.check((select r.state = 'ready' and f.source = 'status_report' and f.mime = 'application/pdf' and f.ready_at is not null
                      from app.project_status_reports r join app.record_files f on f.id = r.file_id where r.id = (select (r ->> 'id')::uuid from t_sr))
                 and exists (select 1 from app.events where kind = 'project.status_report_created' and subject_id = (select p1 from t_p)),
                     'the PDF lands in the project''s files and project.status_report_created is emitted');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.file_upload_begin('project', %L, 'plan.pdf', 'application/x-msdownload', 100)$$, (select p1 from t_p)), 'invalid', 'mime', 'only the allowed types');
select pg_temp.expect_detail(format($$select public.file_upload_begin('project', %L, 'plan.exe', 'application/pdf', 100)$$, (select p1 from t_p)), 'invalid', 'filename', 'the extension matches the type');
select pg_temp.expect_detail(format($$select public.file_upload_begin('project', %L, 'plan.pdf', 'application/pdf', 26214401)$$, (select p1 from t_p)), 'invalid', 'size', 'at most 25 MB');
select pg_temp.expect_detail(format($$select public.file_upload_begin('email_thread', %L, 'plan.pdf', 'application/pdf', 10)$$, gen_random_uuid()), 'invalid', 'entity', 'threads and documents keep their own files');
create temp table t_up as select public.file_upload_begin('project', (select p1 from t_p), 'Oppstartsplan.pdf', 'application/pdf', 188000) r;
select pg_temp.check((select r ->> 'bucket' = 'record-files' and r ->> 'path' = 'project/' || (select p1 from t_p) || '/' || (r ->> 'id') || '/Oppstartsplan.pdf' from t_up)
                 and not public.files_list('project', (select p1 from t_p)) @> jsonb_build_array(jsonb_build_object('id', (select r ->> 'id' from t_up))),
                     'an upload starts as a pending row with a private path; it is not listed until confirmed');
select public.file_upload_done((select (r ->> 'id')::uuid from t_up));
select pg_temp.check(public.files_list('project', (select p1 from t_p)) @> jsonb_build_array(jsonb_build_object('id', (select r ->> 'id' from t_up), 'filename', 'Oppstartsplan.pdf'))
                 and exists (select 1 from app.events where kind = 'file.attached' and subject_type = 'project' and subject_id = (select p1 from t_p))
                 and (public.project_detail((select p1 from t_p)) -> 'files') @> jsonb_build_array(jsonb_build_object('filename', 'Oppstartsplan.pdf')),
                     'a confirmed file is listed, in the drawer too, and file.attached is emitted');
select pg_temp.check((public.file_download_url((select (r ->> 'id')::uuid from t_up)) ->> 'path') = (select r ->> 'path' from t_up), 'a viewer gets the path to sign a download for');
select pg_temp.as_staff('magnus@orgpuls.no');
select pg_temp.expect_detail(format($$select public.file_upload_begin('project', %L, 'x.pdf', 'application/pdf', 10)$$, (select p1 from t_p)), 'forbidden', 'projects:edit_others',
                             'uploading to someone else''s project needs edit_others');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.file_download_url(%L)$$, (select r ->> 'id' from t_up)), 'forbidden', 'projects:see', 'no file without the record''s scope');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_up3 as select public.file_upload_begin('project', (select p3 from t_p), 'privat.txt', 'text/plain', 10) r;
select public.file_upload_done((select (r ->> 'id')::uuid from t_up3));
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.file_download_url(%L)$$, (select r ->> 'id' from t_up3)), 'not_found', null,
                             'a user who cannot see the record cannot fetch the file (CRM-05 acceptance)');
select public.file_delete((select (r ->> 'id')::uuid from t_up));
select pg_temp.check(not public.files_list('project', (select p1 from t_p)) @> jsonb_build_array(jsonb_build_object('id', (select r ->> 'id' from t_up))),
                     'the uploader removes a file');

-- ---------------------------------------------------------------------------
-- mentions (PRJ-07, CRM-06): a link to the project, only to staff who may see it
select pg_temp.as_staff('emma@orgpuls.no');
select public.note_save('project', (select p1 from t_p), null, '@Magnus kan du ta opplæringen torsdag?', null, null, array[(select magnus from t_ids), (select ingrid from t_ids)]);
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select magnus from t_ids) and kind = 'mention' and route = '/projects?project=' || (select p1 from t_p)),
                     'a mention on a project notifies the user, with a link that opens it (PRJ-07 acceptance)');
select pg_temp.check(not exists (select 1 from app.notifications where staff_id = (select ingrid from t_ids) and kind = 'mention' and record_id = (select p1 from t_p)),
                     'a mentioned user who may not see projects is not notified');
select pg_temp.as_staff('tor@orgpuls.no');
select public.note_save('project', (select p3 from t_p), null, 'Privat notat', null, null, array[(select emma from t_ids)]);
select pg_temp.check(not exists (select 1 from app.notifications where staff_id = (select emma from t_ids) and kind = 'mention' and record_id = (select p3 from t_p)),
                     'nor one who may not see this project');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.note_save('deal', (select deal from t_ids), null, 'Se på dette', null, null, array[(select eirik from t_ids), (select emma from t_ids)]);
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select eirik from t_ids) and kind = 'mention' and route = '/deals?deal=' || (select deal from t_ids))
                 and not exists (select 1 from app.notifications where staff_id = (select emma from t_ids) and kind = 'mention' and record_id = (select deal from t_ids)),
                     'on a deal too: the route is unchanged, and staff without deals:see are not told');
-- notes and mail in the drawer, private threads stay private (COM-02)
select pg_temp.as_staff('tor@orgpuls.no');
select public.thread_link((select id from app.email_threads order by created_at limit 1), 'project', (select p1 from t_p), true);
select pg_temp.check((public.project_detail((select p1 from t_p)) -> 'timeline') @> '[{"kind":"email"},{"kind":"note"}]', 'the drawer merges notes and linked mail');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check((public.project_detail((select p1 from t_p)) -> 'timeline') @> '[{"kind":"note"}]'
                 and not (public.project_detail((select p1 from t_p)) -> 'timeline') @> '[{"kind":"email"}]', 'mail the caller may not read stays out');

-- ---------------------------------------------------------------------------
-- export (PRJ-08): audited, formulas neutralised
select pg_temp.expect_detail(format($$select public.project_export(%L, null, 'csv')$$, (select id from t_b)), 'forbidden', 'projects:export', 'export needs projects:export');
select pg_temp.as_staff('tor@orgpuls.no');
select public.project_create(jsonb_build_object('name', '=HYPERLINK("x")', 'board_id', (select id from t_b)));
create temp table t_exp as select public.project_export((select id from t_b), null, 'csv') r;
select pg_temp.check((select r -> 'rows' @> jsonb_build_array(jsonb_build_array('''=HYPERLINK("x")')) and r -> 'columns' ->> 0 = 'seq' from t_exp)
                 and exists (select 1 from app.audit where action = 'record.exported' and target_type = 'project' and detail ->> 'scope' = 'board'),
                     'a cell that would run as a formula is neutralised, and the export is audited');
select pg_temp.check((select jsonb_array_length(r -> 'rows') >= 5 from (select public.project_export(null, (select p1 from t_p), 'xlsx') r) x), 'one project''s items export too');
select pg_temp.expect_detail(format($$select public.project_export(%L, null, 'pdf')$$, (select id from t_b)), 'invalid', 'format', 'CSV or XLSX');

-- ---------------------------------------------------------------------------
-- the generic record paths: custom fields, labels, delete and restore, module switch, sandbox
select public.field_save(null, '{"entity":"project","key":"contract_ref","label":"Contract","type":"text","quality":"required"}');
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'Uten kontrakt', 'board_id', %L))$$, (select id from t_b)), 'invalid', 'custom.contract_ref:required',
                             'a required custom field on projects is required on create (CUS-01)');
create temp table t_cf as select (public.project_create(jsonb_build_object('name', 'Med kontrakt', 'board_id', (select id from t_b), 'custom', jsonb_build_object('contract_ref', 'K-77'))) ->> 'id')::uuid p;
select pg_temp.check((select custom ->> 'contract_ref' = 'K-77' from app.projects where id = (select p from t_cf)),
                     'and stored in custom');
update app.fields set archived_at = now() where entity = 'project' and key = 'contract_ref';
create temp table t_lab as select (public.label_save(null, 'project', 'Pilot P6', '#F5DC96', '#5C4600') ->> 'id')::uuid id;
create temp table t_lp as select (public.project_create(jsonb_build_object('name', 'Merket', 'board_id', (select id from t_b), 'labels', jsonb_build_array((select id from t_lab)))) ->> 'id')::uuid p;
select pg_temp.check((select labels = array[(select id from t_lab)] from app.projects where id = (select p from t_lp)),
                     'project labels apply');
select pg_temp.expect_detail(format($$select public.project_create(jsonb_build_object('name', 'Feil merke', 'board_id', %L, 'labels', jsonb_build_array((select id from app.labels where entity = 'deal' limit 1))))$$, (select id from t_b)),
                             'invalid', 'labels', 'a deal label does not go on a project');
select pg_temp.expect_detail(format($$select public.rec_save('project', %L, '{"name":"Ny"}', 1)$$, (select p1 from t_p)), 'version_conflict', (select version::text from app.projects where id = (select p1 from t_p)),
                             'the generic save checks the version too');
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail(format($$select public.rec_delete('project', array[%L]::uuid[])$$, (select p1 from t_p)), 'forbidden', 'projects:delete', 'deleting needs projects:delete');
select pg_temp.as_staff('tor@orgpuls.no');
select public.rec_delete('project', array[(select p2 from t_p)]);
select pg_temp.check(not (public.projects_board((select id from t_b)) -> 'cards') @> jsonb_build_array(jsonb_build_object('id', (select p2 from t_p)))
                 and exists (select 1 from app.events where kind = 'project.deleted' and subject_id = (select p2 from t_p)), 'a deleted project leaves the board and emits project.deleted');
select public.rec_restore('project', array[(select p2 from t_p)]);
select public.module_set('projects', false);
select pg_temp.expect_detail(format($$select public.projects_board(%L)$$, (select id from t_b)), 'module_off', 'projects', 'with the module off the board is refused (CUS-07)');
select pg_temp.expect_detail(format($$select public.project_detail(%L)$$, (select p1 from t_p)), 'module_off', 'projects', 'and the drawer');
select public.module_set('projects', true);
select public.sandbox_set(true);
create temp table t_sb as select (public.project_create(jsonb_build_object('name', 'Eksempelprosjekt P6', 'board_id', (select id from t_b))) ->> 'id')::uuid p;
select public.sandbox_set(false);
select pg_temp.check((select is_sample from app.projects where id = (select p from t_sb))
                 and not (public.projects_board((select id from t_b)) -> 'cards') @> jsonb_build_array(jsonb_build_object('id', (select p from t_sb))),
                     'a project made in the sandbox is a sample and hidden outside it');

-- ---------------------------------------------------------------------------
-- the phase history is append-only, but lets referential maintenance through
select pg_temp.as_nobody();
select pg_temp.expect_error(format($$update app.project_phase_history set entered_at = now() - interval '1 year' where project_id = %L$$, (select p1 from t_p)), 'the phase history is append-only',
                            'a stay''s start cannot be rewritten');
select pg_temp.expect_error(format($$update app.project_phase_history set left_at = now() + interval '1 hour' where project_id = %L and left_at is not null$$, (select p1 from t_p)), 'the phase history is append-only',
                            'an ended stay cannot be ended again');
select pg_temp.expect_error(format($$delete from app.project_phase_history where project_id = %L$$, (select p1 from t_p)), 'the phase history is append-only',
                            'history is not deleted while its project exists');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.project_phase_delete(%L, %L)$$, (select kickoff from t_ph), (select id from app.project_phases where board_id = (select id from t_b2) limit 1)),
                             'invalid', 'target', 'a phase''s projects move within its board');
create temp table t_pd as select public.project_phase_delete((select kickoff from t_ph), (select setup from t_ph)) r;
select pg_temp.check((select (r ->> 'moved')::int >= 1 from t_pd) and not exists (select 1 from app.projects where phase_id = (select kickoff from t_ph))
                 and exists (select 1 from app.project_phase_history where project_id = (select p1 from t_p) and phase_id is null)
                 and not exists (select 1 from app.project_phases where id = (select kickoff from t_ph)),
                     'deleting a phase moves its projects first; its history rows keep their dates, the phase emptied by the database');
-- purge: the project goes with its items, history and files; the storage objects go to the worker
select public.rec_delete('project', array[(select p1 from t_p)]);
select pg_temp.as_nobody();
update app.projects set deleted_at = now() - interval '31 days' where id = (select p1 from t_p);
select app.purge();
select pg_temp.check(not exists (select 1 from app.projects where id = (select p1 from t_p)) and not exists (select 1 from app.project_items where project_id = (select p1 from t_p))
                 and not exists (select 1 from app.project_phase_history where project_id = (select p1 from t_p))
                 and not exists (select 1 from app.record_files where entity = 'project' and record_id = (select p1 from t_p))
                 and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message -> 'paths' ? ('project/' || (select p1 from t_p) || '/reports/r1.pdf')),
                     'a purged project takes its items, history and files with it (the delete passes the append-only trigger)');

rollback;
