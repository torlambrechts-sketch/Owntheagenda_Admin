-- v3_dev_core_invariants.sql — Development, the core half (0079): the roadmap with evidence counted under each reader's
-- right, promote, the work board with sprints and points, bug triage on tickets and problems (due times from the
-- settings, merge, Mark fixed through problem_resolve), specs whose sign-offs lapse when the content changes, the Markdown
-- roadmap's records, and three Claude features whose context reads only Sentral's records and whose drafts become
-- records only when a person uses them.
\ir _helpers.psql
begin;

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
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('dev_keys', 'dev_roadmap_items', 'dev_roadmap_links', 'dev_sprints', 'dev_bugs', 'dev_bug_tickets', 'dev_work_items', 'dev_specs', 'dev_spec_signoffs')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the Development tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('dev_keys', 'dev_roadmap_items', 'dev_roadmap_links', 'dev_sprints', 'dev_bugs', 'dev_bug_tickets', 'dev_work_items', 'dev_specs', 'dev_spec_signoffs')) = 9,
                     'all nine exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.dev_next_seq(text)', 'app.dev_evidence(uuid)', 'app.dev_bug_due(timestamptz, text)', 'app.ai_ctx_spec_draft(uuid)',
                  'app.ai_ctx_task_plan(uuid)', 'app.ai_ctx_release_note_draft(uuid)', 'app.dev_ai_item(uuid)', 'app.dev_log(text, uuid)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute') and has_function_privilege('authenticated', f::regprocedure, 'execute'),
                     'only the signed-in call ' || f)
from unnest(array['public.dev_roadmap_get(text)', 'public.dev_board_get()', 'public.dev_bugs_get(text)', 'public.dev_specs_get()', 'public.dev_files_get()',
                  'public.dev_jobs_get()', 'public.dev_ai_apply(uuid, jsonb)', 'public.dev_bug_fix(uuid, int, text)', 'public.dev_open_bugs(text)']) f;
select pg_temp.check((select count(*) from app.ai_features where key in ('spec_draft', 'task_plan', 'release_note_draft') and scope = 'dev' and action = 'add'
                      and context_fn ~ '^app\.ai_ctx_') = 3, 'the three Claude features open with Development › Add through app.ai_ctx_* functions');
select pg_temp.check((select array_agg(default_value order by key) from app.settings_registry where key in ('dev_target_sev_one', 'dev_target_sev_two', 'dev_target_sev_three', 'dev_escaped_goal'))
                     = array['source_value', 'same_day', 'source_value', 'source_value'], 'the bug targets are settings with the decided defaults');

-- ---------------------------------------------------------------------------
-- rights
select pg_temp.as_staff('ingrid@orgpuls.no');   -- Sales: no dev right
select pg_temp.expect_detail($$select public.dev_roadmap_get(null)$$, 'forbidden', 'dev:see', 'Sales does not see the roadmap');
select pg_temp.expect_detail($$select public.dev_bugs_get(null)$$, 'forbidden', 'dev:see', 'Sales does not see the bugs');
select pg_temp.as_staff('sara@orgpuls.no');     -- Read-only: dev:see
select pg_temp.check(jsonb_typeof(public.dev_roadmap_get(null) -> 'items') = 'array' and not (public.dev_roadmap_get(null) ->> 'can_add')::boolean, 'Read-only reads the roadmap and may not add');
select pg_temp.expect_detail($$select public.dev_roadmap_add('orgpuls', 'Pulse surveys')$$, 'forbidden', 'dev:add', 'Read-only adds no roadmap item');
select pg_temp.expect_detail($$select public.dev_bug_create('orgpuls', 'Reminder sent twice', 's2', 'internal')$$, 'forbidden', 'dev:add', 'Read-only files no bug');
select pg_temp.as_staff('hanna@orgpuls.no', 'aal1');
select pg_temp.expect_detail($$select public.dev_roadmap_get(null)$$, 'not_signed_in', null, 'without the second factor nobody reads Development');

-- ---------------------------------------------------------------------------
-- the roadmap
select pg_temp.as_staff('hanna@orgpuls.no');    -- Support: dev:see and dev:add, tickets and deals, no campaigns, no marketing reports
create temp table t_item on commit drop as select (public.dev_roadmap_add('orgpuls', 'Pulse surveys', 'Pulse adoption 40 %', 'now') ->> 'id')::uuid as id;
grant all on t_item to authenticated;
select pg_temp.check((select (app.dev_item_json(i) ->> 'key') ~ '^OP-[0-9]+$' from app.dev_roadmap_items i where i.id = (select id from t_item)), 'an Orgpuls item is numbered OP-n');
select pg_temp.check(public.dev_roadmap_add('sentral', 'Help widget and help centre') ->> 'key' ~ '^SE-[0-9]+$' , 'Sentral''s own work is numbered SE-n');
select pg_temp.expect_detail($$select public.dev_roadmap_add('nope', 'A title here')$$, 'invalid', 'product', 'an unknown product is refused');
select pg_temp.expect_detail($$select public.dev_roadmap_add('orgpuls', 'A title here', null, 'soon')$$, 'invalid', 'lane', 'the lanes are Now, Next and Later');
select pg_temp.expect_detail(format($$select public.dev_roadmap_move(%L, 'next', 7)$$, (select id from t_item)), 'version_conflict', null, 'a stale version is refused');
select pg_temp.check(public.dev_roadmap_move((select id from t_item), 'next', 1) ->> 'lane' = 'next', '→ moves the item to Next');
select pg_temp.check((select count(*) from app.audit where target_type = 'dev_roadmap_item' and target_id = (select id::text from t_item) and action = 'dev_roadmap.moved') = 1,
                     'the move is audited');
select pg_temp.check(public.dev_roadmap_move((select id from t_item), 'now', 2) ->> 'lane' = 'now', '← moves it back to Now');
select pg_temp.expect_detail(format($$select public.dev_roadmap_set(%L, 3, '{"lane": "later"}')$$, (select id from t_item)), 'invalid', 'lane', 'the lane changes only by a move');
select pg_temp.check(public.dev_roadmap_set((select id from t_item), 3, '{"goal": "Pulse adoption 45 %", "status": "in_progress"}') ->> 'status' = 'in_progress',
                     'goal and delivery status are set');

-- evidence: a feature request with two organisations' votes and a ticket of its own, a ticket of the item, a deal
create temp table t_fr on commit drop as
  select (public.feature_request_add('orgpuls', 'Pulse surveys with a five-question template', null, (select id from app.organizations order by name limit 1)) ->> 'id')::uuid as id;
grant all on t_fr to authenticated;
select public.feature_request_vote((select id from t_fr), (select id from app.organizations order by name offset 1 limit 1), true);
select public.feature_request_link((select id from t_fr), 'ticket', (select id from app.tickets where number = 2311), true);
select public.dev_roadmap_link((select id from t_item), 'feature_request', (select id from t_fr), null, true);
select pg_temp.check((public.dev_roadmap_link((select id from t_item), 'ticket', null, 2312, true) -> 'evidence' ->> 'tickets')::int = 2,
                     'tickets count: the item''s own and its request''s');
select pg_temp.check((app.dev_evidence((select id from t_item)) ->> 'votes')::int = 2 and (app.dev_evidence((select id from t_item)) ->> 'requests')::int = 1,
                     'votes are counted once per organisation from the linked requests');
select pg_temp.expect_detail(format($$select public.dev_roadmap_link(%L, 'ticket', null, 999999, true)$$, (select id from t_item)), 'not_found', 'ticket', 'a ticket that does not exist is refused');
select pg_temp.expect_detail(format($$select public.dev_roadmap_link(%L, 'invoice', gen_random_uuid(), null, true)$$, (select id from t_item)), 'invalid', 'kind', 'only the five kinds link');
select pg_temp.check(public.dev_roadmap_link((select id from t_item), 'deal', (select id from app.deals where status = 'open' order by created_at, id limit 1), null, true)
                     -> 'evidence' -> 'deals' ->> 'mrr' is null, 'a deal valued by hand has no MRR');
update app.deals set value_source = 'items' where id = (select id from app.deals where status = 'open' order by created_at, id limit 1);
insert into app.deal_items (deal_id, name, quantity, unit_price, billing, billing_frequency)
values ((select id from app.deals where status = 'open' order by created_at, id limit 1), 'Orgpuls', 1, 4340, 'recurring', 'monthly');
select pg_temp.check((app.dev_evidence((select id from t_item)) -> 'deals' ->> 'mrr')::numeric = 4340 and (app.dev_evidence((select id from t_item)) -> 'deals' ->> 'n')::int = 1,
                     'a deal valued from its items brings its MRR');
select pg_temp.check(not (app.dev_evidence((select id from t_item)) ? 'experiments') and not (app.dev_evidence((select id from t_item)) ? 'seo'),
                     'experiments and SEO are left out for a reader without their rights');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check(app.dev_evidence((select id from t_item)) ? 'experiments' and app.dev_evidence((select id from t_item)) ? 'seo',
                     'Read-only with marketing reports sees them');
select pg_temp.check(jsonb_array_length(app.dev_item_links((select id from t_item))) = 3, 'the item''s own links are listed by name');

-- progress: done ÷ all work items linked
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((select (x -> 'work' ->> 'total')::int = 0 from jsonb_array_elements(public.dev_roadmap_get('orgpuls') -> 'items') x where x ->> 'id' = (select id::text from t_item)),
                     'without work items there is no progress to show');
create temp table t_w on commit drop as
  select (public.dev_work_item_save(null, null, jsonb_build_object('roadmap_item_id', (select id from t_item), 'title', 'Five-question template', 'kind', 'story', 'points', 3)) ->> 'id')::uuid as id;
grant all on t_w to authenticated;
select public.dev_work_item_save(null, null, jsonb_build_object('roadmap_item_id', (select id from t_item), 'title', 'Scheduler', 'kind', 'task', 'points', 2, 'status', 'done'));
select pg_temp.check((select (app.dev_item_json(i) -> 'work') = '{"total": 2, "done": 1}'::jsonb from app.dev_roadmap_items i where i.id = (select id from t_item)),
                     'progress counts done and all linked work items');

-- promote
select pg_temp.check(public.dev_roadmap_get('orgpuls') -> 'candidates' -> 'feature_request' is not null, 'an unpromoted request is a candidate');
create temp table t_fr2 on commit drop as select (public.feature_request_add('orgpuls', 'Import employees from Visma') ->> 'id')::uuid as id;
grant all on t_fr2 to authenticated;
create temp table t_pr on commit drop as select public.dev_roadmap_promote('feature_request', (select id from t_fr2)) as j;
grant all on t_pr to authenticated;
select pg_temp.check((select j ->> 'lane' = 'later' and j ->> 'source' = 'feature_request' and j ->> 'title' = 'Import employees from Visma' from t_pr),
                     'a promoted request lands in Later under its own title');
select pg_temp.check((select (j -> 'evidence' ->> 'requests')::int = 1 from t_pr), 'with its evidence linked');
select pg_temp.expect_detail(format($$select public.dev_roadmap_promote('feature_request', %L)$$, (select id from t_fr2)), 'invalid', 'promoted', 'a source is promoted once');
select pg_temp.check(coalesce(public.dev_roadmap_get('orgpuls') -> 'candidates' -> 'feature_request' ->> 'id', '') <> (select id::text from t_fr2),
                     'a promoted request is no longer a candidate');
select pg_temp.expect_detail(format($$select public.dev_roadmap_promote('experiment', %L)$$, (select id from app.growth_experiments limit 1)), 'forbidden', 'campaigns:see',
                             'promoting an experiment needs the right to see experiments');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(public.dev_roadmap_promote('experiment', (select id from app.growth_experiments where outcome = 'win' limit 1)) ->> 'product' = 'orgpuls',
                     'a winning experiment is promoted for its product');
select pg_temp.check((public.dev_roadmap_archive((select (j ->> 'id')::uuid from t_pr), 1) ->> 'ok')::boolean, 'an item is archived');
select pg_temp.check((select count(*) from jsonb_array_elements(public.dev_roadmap_get(null) -> 'items') x where x ->> 'id' = (select j ->> 'id' from t_pr)) = 0,
                     'an archived item leaves the lanes');

-- ---------------------------------------------------------------------------
-- the work board
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_work_item_save(null, null, '{"product": "skiftly", "title": "x"}')$$, 'invalid', 'title', 'a title has three letters at least');
select pg_temp.expect_detail(format($$select public.dev_work_item_save(null, null, '{"product": "skiftly", "title": "Calendar sync", "roadmap_item_id": %s}')$$,
                                    to_jsonb((select id from t_item))), 'invalid', 'roadmap_item_id', 'an epic belongs to the same product');
select pg_temp.expect_detail($$select public.dev_work_item_save(null, null, '{"product": "skiftly", "title": "Calendar sync", "points": 101}')$$, 'invalid', 'points', 'points are 0 to 100');
select pg_temp.expect_detail(format($$select public.dev_work_item_save(%L, 1, '{"product": "skiftly"}')$$, (select id from t_w)), 'invalid', 'product', 'a work item keeps its product');
select pg_temp.expect_detail(format($$select public.dev_work_item_move(%L, 'review', 9)$$, (select id from t_w)), 'version_conflict', null, 'a stale card is not moved');
select pg_temp.check(public.dev_work_item_move((select id from t_w), 'review', 1) ->> 'status' = 'review', 'a card moves to Review');
select pg_temp.check(public.dev_work_item_move((select id from t_w), 'done', 2) ->> 'done_at' is not null, 'Done stamps the time');
select pg_temp.check(public.dev_work_item_move((select id from t_w), 'rollout', 3) ->> 'done_at' is null, 'leaving Done clears it');
-- the suite owns the calendar: any sprint already in this database is set aside (rolled back at the end)
update app.dev_work_items set sprint_id = null where sprint_id is not null;
delete from app.dev_sprints where id is not null;
select pg_temp.expect_detail($$select public.dev_sprint_save(null, 'Sprint 41', current_date, current_date - 1)$$, 'invalid', 'dates', 'a sprint ends after it starts');
create temp table t_sp on commit drop as select (public.dev_sprint_save(null, 'Sprint 41', app.dev_today() - 2, app.dev_today() + 11) ->> 'id')::uuid as id;
grant all on t_sp to authenticated;
select pg_temp.expect_detail($$select public.dev_sprint_save(null, 'Sprint 42', app.dev_today() + 5, app.dev_today() + 15)$$, 'invalid', 'overlap', 'sprints do not overlap');
select public.dev_work_item_save((select id from t_w), 4, jsonb_build_object('sprint_id', (select id from t_sp)));
select public.dev_work_item_save(null, null, jsonb_build_object('product', 'orgpuls', 'title', 'Nynorsk survey strings', 'points', 5, 'sprint_id', (select id from t_sp)));
select pg_temp.check((public.dev_board_get() -> 'sprint' ->> 'committed')::int = 8 and (public.dev_board_get() -> 'sprint' ->> 'done')::int = 3,
                     'committed and done points are summed from the sprint''s rows (Rollout and Done count as done)');
select pg_temp.check((public.dev_board_get() -> 'sprint' ->> 'days')::int = app.dev_business_days(app.dev_today() - 2, app.dev_today() + 11)
                     and (public.dev_board_get() -> 'sprint' ->> 'day')::int between 0 and 3, 'the sprint''s days are business days');
select pg_temp.check((public.dev_work_item_archive((select id from t_w), 5) ->> 'ok')::boolean, 'a card is archived');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.dev_board_get() -> 'items') x where x ->> 'id' = (select id::text from t_w)),
                     'an archived card leaves the board');

-- ---------------------------------------------------------------------------
-- bug triage
select pg_temp.check(app.dev_bug_due('2026-10-12 09:00+02', 's1') = '2026-10-12 16:00+02', 'S1 found on a business morning is due 16:00 that day');
select pg_temp.check(app.dev_bug_due('2026-10-12 17:00+02', 's1') = '2026-10-13 16:00+02', 'S1 found after 16:00 is due 16:00 the next business day');
select pg_temp.check(app.dev_bug_due('2026-10-10 11:00+02', 's1') = '2026-10-12 16:00+02', 'S1 found on a Saturday is due Monday 16:00');
select pg_temp.check(app.dev_bug_due('2026-10-15 10:00+02', 's2') = '2026-10-20 10:00+02', 'S2 is due three business days later (over a weekend)');
select pg_temp.check(app.dev_bug_due('2026-10-12 10:00+02', 's3') = '2026-10-26 10:00+02', 'S3 is due fourteen days later');
insert into app.setting_values (key, scope_id, value, value_number) values ('dev_target_sev_two', '', 'custom', 5);
select pg_temp.check(app.dev_bug_due('2026-10-12 10:00+02', 's2') = '2026-10-19 10:00+02', 'the S2 target follows its setting');
delete from app.setting_values where key = 'dev_target_sev_two';

select pg_temp.expect_detail($$select public.dev_bug_create('orgpuls', 'Reminder sent twice', 's2', 'ticket')$$, 'invalid', 'tickets', 'a bug from customers names a ticket or a problem');
select pg_temp.expect_detail($$select public.dev_bug_create('orgpuls', 'Reminder sent twice', 's4', 'internal')$$, 'invalid', 'severity', 'severity is S1 to S3');
select pg_temp.expect_detail($$select public.dev_bug_create('orgpuls', 'Reminder sent twice', 's2', 'ticket', null, array[999999]::bigint[])$$, 'not_found', 'ticket',
                             'a ticket that does not exist is refused');
create temp table t_base on commit drop as
  select public.dev_bugs_get('orgpuls') -> 'kpi' as k, public.dev_open_bugs('orgpuls') as o, public.dev_open_bugs('skiftly') as s, public.dev_jobs_get() -> 'kpi' as j;
grant all on t_base to authenticated;
create temp table t_bug on commit drop as
  select (public.dev_bug_create('orgpuls', 'Invitations not delivered to kommune.no domains', 's1', 'ticket',
                                (select id from app.tickets where number = 2316), array[2311, 2312]::bigint[]) ->> 'id')::uuid as id;
grant all on t_bug to authenticated;
select pg_temp.check((select (b ->> 'tickets')::int = 5 and (b ->> 'customers')::int = 5 and (b -> 'problem' ->> 'number')::int = 2316
                             and (b -> 'problem' ->> 'open_incidents')::int = 2
                      from (select app.dev_bug_json(x) b from app.dev_bugs x where x.id = (select id from t_bug)) y),
                     'its tickets are the linked ones and the problem''s open incidents; customers are their organisations');
create temp table t_dup on commit drop as
  select (public.dev_bug_create('orgpuls', 'Invites bounce for municipal domains', 's2', 'ticket', null, array[2323]::bigint[]) ->> 'id')::uuid as id;
grant all on t_dup to authenticated;
select pg_temp.check(public.dev_open_bugs('orgpuls') = (select o + 2 from t_base) and public.dev_open_bugs('skiftly') = (select s from t_base),
                     'the pill counts the application''s open bugs');
select pg_temp.expect_detail(format($$select public.dev_bug_merge(%L, %L, 1)$$, (select id from t_dup), (select id from t_dup)), 'not_found', 'into', 'a bug does not duplicate itself');
select pg_temp.check(public.dev_bug_merge((select id from t_dup), (select id from t_bug), 1) ->> 'state' = 'duplicate', 'Merge duplicate closes the duplicate');
select pg_temp.check(exists (select 1 from app.dev_bug_tickets bt join app.tickets t on t.id = bt.ticket_id where bt.bug_id = (select id from t_bug) and t.number = 2323)
                     and not exists (select 1 from app.dev_bug_tickets where bug_id = (select id from t_dup)), 'its tickets move to the bug that stays');
select pg_temp.check((select (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 'open')::int = (k ->> 'open')::int + 1
                             and (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 's1')::int = (k ->> 's1')::int + 1
                             and (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 'escaped_30')::int = (k ->> 'escaped_30')::int + 1 from t_base),
                     'the KPIs are counted from the rows (a merged duplicate does not count)');
select pg_temp.check(public.dev_bug_set((select id from t_bug), 2, jsonb_build_object('assignee_id', (select id from app.admins where email = 'magnus@orgpuls.no')))
                     -> 'assignee' ->> 'name' is not null, 'a bug is assigned to a staff member');
select public.dev_bug_set((select id from t_bug), 3, '{"severity": "s2"}');
select pg_temp.check((select b.due_at = app.dev_bug_due(b.created_at, 's2') and b.severity = 's2' from app.dev_bugs b where b.id = (select id from t_bug)),
                     'a new severity moves the due time');
select pg_temp.expect_detail(format($$select public.dev_bug_fix(%L, 4)$$, (select id from t_bug)), 'invalid', 'body', 'customers on open incidents are told: a message is required');
update app.permission_sets set rights = array_remove(rights, 'tickets:edit_others') where key = 'support';
select pg_temp.expect_detail(format($$select public.dev_bug_fix(%L, 4, 'It is fixed.')$$, (select id from t_bug)), 'forbidden', 'tickets:edit_others',
                             'resolving the problem needs Tickets › Edit others');
update app.permission_sets set rights = rights || array['tickets:edit_others'] where key = 'support';
create temp table t_fix on commit drop as select public.dev_bug_fix((select id from t_bug), 4, 'It is fixed. Thank you for your patience.') as j;
grant all on t_fix to authenticated;
select pg_temp.check((select j ->> 'state' = 'fixed' and (j ->> 'notified')::int = 2 and (j ->> 'problem_resolved')::boolean from t_fix),
                     'Mark fixed closes the bug and resolves the problem, replying to its open incidents');
select pg_temp.check((select problem_status from app.tickets where number = 2316) = 'resolved', 'the problem is resolved');
select pg_temp.expect_detail(format($$select public.dev_bug_fix(%L, 5)$$, (select id from t_bug)), 'invalid', 'state', 'a fixed bug is not fixed again');
select pg_temp.check((select (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 'fixed_30')::int = (k ->> 'fixed_30')::int + 1
                             and (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 'within_30')::int = (k ->> 'within_30')::int + 1
                             and (public.dev_bugs_get('orgpuls') -> 'kpi' ->> 'median_h') is not null from t_base),
                     'within target and time to fix come from the fixed rows');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.dev_bug_link(%L, 2313, true)$$, (select id from t_bug)), 'forbidden', 'dev:add', 'Read-only links no ticket');

-- ---------------------------------------------------------------------------
-- specs
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_spec on commit drop as
  select (public.dev_spec_save(null, null, jsonb_build_object('roadmap_item_id', (select id from t_item), 'title', 'Pulse surveys', 'problem', 'Customers want a short pulse.')) ->> 'id')::uuid as id;
grant all on t_spec to authenticated;
select pg_temp.check((select s.product = 'orgpuls' and s.revision = 1 and s.status = 'draft' from app.dev_specs s where s.id = (select id from t_spec)),
                     'a spec takes its product from the roadmap item and starts as a draft');
select pg_temp.expect_detail(format($$select public.dev_spec_save(null, null, '{"title": "Second spec", "roadmap_item_id": "%s"}')$$, (select id from t_item)),
                             'invalid', 'roadmap_item_id', 'one spec per roadmap item');
select pg_temp.expect_detail(format($$select public.dev_spec_status(%L, 'approved', 1)$$, (select id from t_spec)), 'invalid', 'signoffs', 'approval needs the four sign-offs');
select public.dev_spec_sign((select id from t_spec), r, true) from unnest(array['product', 'engineering', 'security_privacy', 'support']) r;
select pg_temp.check(public.dev_spec_status((select id from t_spec), 'approved', 1) ->> 'status' = 'approved', 'with all four it is approved');
select pg_temp.check((select (j ->> 'revision')::int = 2 and j ->> 'status' = 'in_review'
                             and not exists (select 1 from jsonb_array_elements(j -> 'signoffs') g where (g ->> 'current')::boolean)
                      from (select public.dev_spec_save((select id from t_spec), 2, '{"decision": "Option B."}') j) x),
                     'a changed section is a new revision: the sign-offs lapse and the spec goes back to review');
select pg_temp.check((select (j ->> 'revision')::int = 2 from (select public.dev_spec_save((select id from t_spec), 3, '{"decision": "Option B."}') j) x),
                     'saving the same text is not a new revision');
select pg_temp.expect_detail(format($$select public.dev_spec_sign(%L, 'legal', true)$$, (select id from t_spec)), 'invalid', 'role', 'the four roles only');

-- ---------------------------------------------------------------------------
-- the Markdown roadmap's records
select pg_temp.check((select jsonb_array_length(x -> 'tasks') = 1 and jsonb_array_length(x -> 'log') >= 3 and x ->> 'problem' = 'Customers want a short pulse.'
                      from jsonb_array_elements(public.dev_files_get() -> 'items') x where x ->> 'id' = (select id::text from t_item)),
                     'a file carries its tasks, its spec''s problem and its log from the audit');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.dev_files_get() -> 'items') x, jsonb_array_elements(x -> 'log') l
                                 where l -> 'detail' ? 'title' or l -> 'detail' ? 'goal'), 'the log carries codes, never what someone typed');

-- ---------------------------------------------------------------------------
-- Claude: context from Sentral's records only; a draft becomes records only when used
select pg_temp.check(app.ai_ctx_spec_draft((select id from t_item)) ->> 'prompt' like '%Pulse surveys with a five-question template%'
                     and app.ai_ctx_spec_draft((select id from t_item)) ->> 'prompt' like '%2 organisations voted%', 'the spec context names the requests and counts the votes');
select pg_temp.check(app.ai_ctx_spec_draft((select id from t_item)) ->> 'prompt' not like '%' || (select name from app.organizations order by name limit 1) || '%'
                     and app.ai_ctx_spec_draft((select id from t_item)) ->> 'prompt' not like '%' || (select subject from app.tickets where number = 2311) || '%'
                     and app.ai_ctx_spec_draft((select id from t_item)) ->> 'prompt' not like '%' || (select title from app.deals where status = 'open' order by created_at, id limit 1) || '%',
                     'no organisation, ticket subject or deal reaches Claude');
select pg_temp.check(app.ai_ctx_task_plan((select id from t_item)) ->> 'prompt' like '%Option B.%', 'the task plan reads the spec');
select pg_temp.check(app.ai_ctx_release_note_draft((select id from t_item)) ->> 'prompt' like '%Scheduler%', 'the release note reads the finished work');
select pg_temp.check(app.ai_ctx_release_note_draft((select (j ->> 'id')::uuid from t_pr)) is null, 'without finished work there is no release note to draft');
select pg_temp.check(app.ai_ctx_spec_draft(gen_random_uuid()) is null, 'an unknown item builds no context');
select pg_temp.as_service();
create temp table t_out on commit drop as select
  (public.worker_ai_record('spec_draft', (select id from t_item), (select id from app.admins where email = 'hanna@orgpuls.no'), '## Problem\nA', 'claude-opus-5-5', 900, 400, 8000, 'ok', null) ->> 'output')::uuid as spec,
  (public.worker_ai_record('task_plan', (select id from t_item), (select id from app.admins where email = 'hanna@orgpuls.no'), '- Task: Write the scheduler', 'claude-opus-5-5', 700, 100, 4000, 'ok', null) ->> 'output')::uuid as plan,
  (public.worker_ai_record('release_note_draft', (select id from t_item), (select id from app.admins where email = 'hanna@orgpuls.no'), '- New: Pulse surveys', 'claude-opus-5-5', 500, 60, 3000, 'ok', null) ->> 'output')::uuid as note;
grant all on t_out to authenticated;
select public.worker_ai_record('task_plan', (select id from t_item), null, null, 'claude-opus-5-5', 0, 0, 900, 'error', 'network');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail(format($$select public.dev_ai_apply(%L, '{"tasks": []}')$$, (select plan from t_out)), 'forbidden', 'dev:add', 'Read-only uses no draft');
select pg_temp.check((select (public.dev_jobs_get() -> 'kpi' ->> 'drafts')::int = (j ->> 'drafts')::int + 3 and (public.dev_jobs_get() -> 'kpi' ->> 'failed')::int = (j ->> 'failed')::int + 1
                             and (public.dev_jobs_get() -> 'kpi' ->> 'tokens_month')::int = (j ->> 'tokens_month')::int + 2660 from t_base),
                     'the usage is counted from the calls and drafts');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.dev_ai_apply(%L, '{"tasks": [{"kind": "epic", "title": "Write it"}]}')$$, (select plan from t_out)), 'invalid', 'tasks',
                             'a task''s kind is checked again');
select pg_temp.check((public.dev_ai_apply((select plan from t_out), '{"tasks": [{"kind": "task", "title": "Write the scheduler"}, {"kind": "spike", "title": "Time zones"}]}') ->> 'created')::int = 2,
                     'a used task plan is applied');
select pg_temp.check((select count(*) from app.dev_work_items where roadmap_item_id = (select id from t_item) and status = 'backlog' and archived_at is null) = 2,
                     'it becomes work items in Backlog');
select pg_temp.expect_detail(format($$select public.dev_ai_apply(%L, '{"tasks": [{"kind": "task", "title": "Again"}]}')$$, (select plan from t_out)), 'invalid', 'state',
                             'a draft is used once');
select pg_temp.check((select (j ->> 'spec')::uuid = (select id from t_spec)
                      from (select public.dev_ai_apply((select spec from t_out), '{"problem": "P", "options": "O", "decision": "D", "privacy": "No survey data.", "rollout": "R"}') j) x),
                     'a used spec draft goes into the item''s spec');
select pg_temp.check((select revision = 3 and decision = 'D' from app.dev_specs where id = (select id from t_spec)), 'as a new revision');
select pg_temp.check((public.dev_ai_apply((select note from t_out), '{"notes": [{"kind": "new", "title": "Pulse surveys with a five-question template"}]}') ->> 'created')::int = 1,
                     'a used release note draft is applied');
select pg_temp.check(exists (select 1 from app.release_notes where source = 'ai' and state = 'draft' and title = 'Pulse surveys with a five-question template'),
                     'as a draft release note');
select pg_temp.check((select (public.dev_jobs_get() -> 'kpi' ->> 'used')::int = (j ->> 'used')::int + 3 from t_base), 'acceptance counts the used drafts');
select pg_temp.check(not exists (select 1 from app.audit where target_type in ('dev_roadmap_item', 'dev_work_item', 'dev_bug', 'dev_spec', 'dev_sprint')
                                 and action !~ '^[a-z_]+\.[a-z_]+$'), 'every audit action has the shape scope.verb');

rollback;
