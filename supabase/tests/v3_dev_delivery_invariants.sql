-- v3_dev_delivery_invariants.sql — Development, the delivery half (0080): deploys from Vercel's webhooks and build facts
-- from the products' CI arrive only through the service role's workers, which refuse a stale or repeated delivery and keep
-- ids, shas, states, counts and file names only; a rollback is recognised when Vercel promotes an older deployment; the
-- metrics are computed from those rows; a release's checklist comes from the same rows, its manual items are signed by a
-- named person (the anonymity check by the owner), and it is recorded only when every item passes (its notes are then
-- published and, with its checklist, frozen: no writer edits, unpublishes or deletes them); a CI post is taken only from a
-- repository the owner bound to the product it names;
-- the integrations register reads Sentral's own logs and keeps an owner, an upcoming change and planned upgrades typed by
-- a person. Every right is checked: Sales sees nothing, Read-only reads, Support adds, Admin configures.
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
-- a Vercel deployment as dev-events reduces it
create or replace function pg_temp.dep(p_id text, p_env text default 'production', p_sha text default null, p_ref text default 'main') returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'project_id', 'prj_orgpulsweb1', 'project_name', 'orgpuls-web', 'environment', p_env,
                            'sha', p_sha, 'ref', p_ref, 'pr', null, 'commit_title', 'Retry policy for greylisted domains',
                            'host', 'orgpuls-web-abc.vercel.app', 'inspector_url', 'https://vercel.com/orgpuls/orgpuls-web/' || p_id)
$$;

-- this suite's own world: the delivery tables start empty (rolled back at the end)
delete from app.dev_deliveries where true;
delete from app.dev_ci_runs where true;
delete from app.dev_ci_repos where true;
delete from app.dev_projects where true;
delete from app.dev_releases where true;
delete from app.dev_integration_plans where true;
update app.dev_integrations set owner_id = null, change_text = null, change_due_on = null, change_url = null, change_none = false where true;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('dev_projects', 'dev_deployments', 'dev_ci_runs', 'dev_ci_repos', 'dev_deliveries', 'dev_releases', 'dev_release_notes',
                      'dev_release_signoffs', 'dev_integrations', 'dev_integration_plans')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the delivery tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
                      and c.relname in ('dev_projects', 'dev_deployments', 'dev_ci_runs', 'dev_ci_repos', 'dev_deliveries', 'dev_releases', 'dev_release_notes',
                                        'dev_release_signoffs', 'dev_integrations', 'dev_integration_plans')) = 10, 'all ten exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute') and has_function_privilege('service_role', f::regprocedure, 'execute'),
                     'only the service role calls ' || f)
from unnest(array['public.worker_dev_vercel(text, text, timestamptz, jsonb)', 'public.worker_dev_ci(text, timestamptz, jsonb)']) f;
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.delivery_release_checks(uuid)', 'app.delivery_connection_json(text)', 'app.delivery_products_json()', 'app.delivery_line(text, integer)',
                  'app.release_note_frozen(uuid)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute') and has_function_privilege('authenticated', f::regprocedure, 'execute'),
                     'signed-in staff, not anon, call ' || f)
from unnest(array['public.dev_deploys()', 'public.dev_metrics(integer)', 'public.dev_releases_get(uuid)', 'public.dev_integrations_get()',
                  'public.dev_release_record(uuid, integer)', 'public.dev_project_set(text, text)', 'public.dev_ci_repo_set(text, text)']) f;
-- no column could hold a payload, a log or a person's words beyond a commit's first line
select pg_temp.check(not exists (select 1 from information_schema.columns c where c.table_schema = 'app'
                                  and c.table_name in ('dev_deployments', 'dev_ci_runs', 'dev_deliveries')
                                  and c.column_name ~ '(payload|body|log|message|output|author|email|meta)'),
                     'deployments, CI runs and deliveries keep no payload, log, message or author');

-- ---------------------------------------------------------------------------
-- rights
select pg_temp.as_staff('ingrid@orgpuls.no');   -- Sales: no Development right
select pg_temp.expect_detail('select public.dev_deploys()', 'forbidden', 'dev:see', 'Sales does not read deploys');
select pg_temp.expect_detail('select public.dev_metrics(30)', 'forbidden', 'dev:see', 'Sales does not read the metrics');
select pg_temp.expect_detail('select public.dev_releases_get(null)', 'forbidden', 'dev:see', 'Sales does not read releases');
select pg_temp.expect_detail('select public.dev_integrations_get()', 'forbidden', 'dev:see', 'Sales does not read the register');
select pg_temp.as_staff('sara@orgpuls.no');     -- Read-only: dev:see
select pg_temp.check(jsonb_typeof(public.dev_deploys() -> 'latest') = 'array' and not (public.dev_deploys() ->> 'can_configure')::boolean,
                     'Read-only reads the deploys and may not configure');
select pg_temp.expect_detail($$select public.dev_release_add('orgpuls', 'Orgpuls 2026.10')$$, 'forbidden', 'dev:add', 'Read-only records no release');
select pg_temp.as_staff('hanna@orgpuls.no', 'aal1');
select pg_temp.expect_error('select public.dev_deploys()', 'not_signed_in', 'without the second factor nothing is read');

-- ---------------------------------------------------------------------------
-- Vercel's deployment events
select pg_temp.as_service();
select pg_temp.check(public.worker_dev_vercel('evt_created_000001', 'deployment.created', now(), pg_temp.dep('dpl_aaaaaaaa1', 'production', repeat('a', 40))) ->> 'applied' = 'true',
                     'a created deployment is applied');
select pg_temp.check((select state from app.dev_deployments where id = 'dpl_aaaaaaaa1') = 'building', 'it is building');
select pg_temp.check(public.worker_dev_vercel('evt_created_000001', 'deployment.created', now(), pg_temp.dep('dpl_aaaaaaaa1')) ->> 'duplicate' = 'true',
                     'the same event id again is a duplicate');
select pg_temp.check((select count(*) from app.dev_deliveries where source = 'vercel' and delivery_id = 'evt_created_000001') = 1, 'and is kept once');
select pg_temp.expect_detail($$select public.worker_dev_vercel('evt_old_00000001', 'deployment.created', now() - interval '6 minutes', pg_temp.dep('dpl_aaaaaaaa2'))$$,
                             'stale', 'at', 'an event older than five minutes is refused');
select pg_temp.expect_detail($$select public.worker_dev_vercel('evt_future_00001', 'deployment.created', now() + interval '6 minutes', pg_temp.dep('dpl_aaaaaaaa2'))$$,
                             'stale', 'at', 'an event from the future is refused');
select pg_temp.expect_detail($$select public.worker_dev_vercel('evt_badid_000001', 'deployment.created', now(), pg_temp.dep('nope'))$$,
                             'invalid', 'id', 'a deployment id that is not Vercel''s shape is refused');
select pg_temp.expect_detail($$select public.worker_dev_vercel('x', 'deployment.created', now(), pg_temp.dep('dpl_aaaaaaaa2'))$$,
                             'invalid', 'delivery', 'a delivery id that is not an id is refused');
select pg_temp.check(public.worker_dev_vercel('evt_other_0000001', 'project.created', now(), pg_temp.dep('dpl_aaaaaaaa9')) ->> 'ignored' = 'true'
                     and not exists (select 1 from app.dev_deployments where id = 'dpl_aaaaaaaa9'), 'another kind of event is recorded as ignored and changes nothing');
select pg_temp.check(public.worker_dev_vercel('evt_ready_0000001', 'deployment.succeeded', now() - interval '4 minutes',
                                              pg_temp.dep('dpl_aaaaaaaa1', 'production', repeat('a', 40))) ->> 'applied' = 'true', 'succeeded is applied');
select pg_temp.check((select state = 'ready' and ready_at = now() - interval '4 minutes' from app.dev_deployments where id = 'dpl_aaaaaaaa1'),
                     'succeeded makes it ready at the event''s time');
-- what is kept: the first line of a commit message, capped; a host in lower case; no foreign link
select pg_temp.check(public.worker_dev_vercel('evt_prev_00000001', 'deployment.created', now(),
                       pg_temp.dep('dpl_bbbbbbbb1', 'preview', repeat('b', 40), 'op-412-email-first')
                       || jsonb_build_object('commit_title', 'First line ' || repeat('x', 300) || E'\nSecond line with a person''s words',
                                             'host', 'ORGPULS-web-git-op-412.vercel.app', 'inspector_url', 'https://evil.example/steal', 'pr', '881')) ->> 'applied' = 'true',
                     'a preview is applied');
select pg_temp.check((select char_length(commit_title) = 200 and commit_title not like '%Second line%' and host = 'orgpuls-web-git-op-412.vercel.app'
                             and inspector_url is null and pr = 881 and environment = 'preview' from app.dev_deployments where id = 'dpl_bbbbbbbb1'),
                     'only the first line, 200 characters; the host lower-cased; a link outside vercel.com dropped');
select pg_temp.check((select status from app.integration_connections where provider = 'vercel') = 'connected', 'the first applied event marks Vercel connected');

-- a second production deployment goes live, then Vercel promotes the first again: an instant rollback
select pg_temp.check(public.worker_dev_vercel('evt_c2_0000000001', 'deployment.created', now() - interval '3 minutes',
                                              pg_temp.dep('dpl_cccccccc2', 'production', repeat('c', 40))) ->> 'applied' = 'true', 'a second production deployment');
select pg_temp.check(public.worker_dev_vercel('evt_c2_0000000002', 'deployment.succeeded', now() - interval '2 minutes',
                                              pg_temp.dep('dpl_cccccccc2', 'production', repeat('c', 40))) ->> 'applied' = 'true', 'goes live');
select pg_temp.check(public.worker_dev_vercel('evt_rb_0000000001', 'deployment.promoted', now() - interval '30 seconds',
                                              pg_temp.dep('dpl_aaaaaaaa1', 'production', repeat('a', 40))) ->> 'rolled_back' = 'dpl_cccccccc2',
                     'promoting the older one rolls back the live one');
select pg_temp.check((select rolled_back_at = now() - interval '30 seconds' from app.dev_deployments where id = 'dpl_cccccccc2')
                     and (select rolled_back_at is null and promoted_at is not null from app.dev_deployments where id = 'dpl_aaaaaaaa1'),
                     'the rollback is recorded on the deployment that was live');
select pg_temp.check(public.worker_dev_vercel('evt_rb_0000000002', 'deployment.promoted', now() - interval '20 seconds',
                                              pg_temp.dep('dpl_aaaaaaaa1', 'production', repeat('a', 40))) ->> 'rolled_back' is null,
                     'promoting the live one again rolls nothing back');
-- a failed production build, then the next good one
select pg_temp.check(public.worker_dev_vercel('evt_err_000000001', 'deployment.error', now() - interval '1 minute',
                                              pg_temp.dep('dpl_dddddddd3', 'production', repeat('d', 40))) ->> 'applied' = 'true', 'a failed production build');
select pg_temp.check(public.worker_dev_vercel('evt_ok_0000000001', 'deployment.succeeded', now() + interval '4 minutes',
                                              pg_temp.dep('dpl_eeeeeeee4', 'production', repeat('e', 40))) ->> 'applied' = 'true', 'the next one is ready');

-- ---------------------------------------------------------------------------
-- the repositories the CI posts from: one CI secret for all of them, so the owner binds each one to its product
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('torlambrechts-sketch/orgpuls', 'orgpuls')$$, 'forbidden', 'owner_only', 'Support binds no repository');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('torlambrechts-sketch/orgpuls', 'orgpuls')$$, 'forbidden', 'fresh_mfa', 'the owner binds with a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('not a repository', 'orgpuls')$$, 'invalid', 'repository', 'a repository is owner/name');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('../etc', 'orgpuls')$$, 'invalid', 'repository', 'and not a path');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('torlambrechts-sketch/orgpuls', 'nope')$$, 'invalid', 'product', 'only an application or Sentral');
select pg_temp.check((public.dev_ci_repo_set('TorLambrechts-Sketch/Orgpuls', 'orgpuls') ->> 'ok')::boolean
                     and (public.dev_ci_repo_set('torlambrechts-sketch/owntheagenda_admin', 'sentral') ->> 'ok')::boolean
                     and (public.dev_ci_repo_set('torlambrechts-sketch/skiftly', 'skiftly') ->> 'ok')::boolean, 'the owner binds three repositories');
select pg_temp.check((select product from app.dev_ci_repos where repository = 'torlambrechts-sketch/orgpuls') = 'orgpuls', 'a repository is kept in lower case, as GitHub matches it');
select pg_temp.check((public.dev_ci_repo_set('torlambrechts-sketch/skiftly', null) ->> 'ok')::boolean, 'and unbinds one');
select pg_temp.check(not exists (select 1 from app.dev_ci_repos where repository = 'torlambrechts-sketch/skiftly'), 'which is then gone');
select pg_temp.expect_detail($$select public.dev_ci_repo_set('torlambrechts-sketch/skiftly', null)$$, 'not_found', null, 'an unbound repository is not unbound twice');

-- ---------------------------------------------------------------------------
-- the CI's results
create temp table t_run as select jsonb_build_object('v', 1, 'product', 'orgpuls', 'repository', 'TorLambrechts-Sketch/orgpuls', 'sha', repeat('e', 40), 'ref', 'main',
  'commit_at', now() - interval '3 hours', 'commit_title', 'Retry policy', 'run_url', 'https://github.com/torlambrechts-sketch/orgpuls/actions/runs/1',
  'finished_at', now(), 'suites', jsonb_build_array(jsonb_build_object('name', 'unit', 'kind', 'test', 'passed', 120, 'failed', 0),
                                                     jsonb_build_object('name', 'respondent_invariants', 'kind', 'anonymity', 'passed', 21, 'failed', 0)),
  'migrations_pending', jsonb_build_array('0231_retry_queue.sql'), 'dependencies', jsonb_build_object('critical', 0, 'high', 1, 'moderate', 6, 'low', 2),
  'coverage', 84.2, 'log', 'ignored text') as r;
select pg_temp.check(public.worker_dev_ci('1001-1-orgpuls', now(), (select r from t_run)) ->> 'applied' = 'true', 'a CI run is applied');
select pg_temp.check(public.worker_dev_ci('1001-1-orgpuls', now(), (select r from t_run)) ->> 'duplicate' = 'true', 'the same delivery again is a duplicate');
select pg_temp.check((select suites -> 0 = '{"name": "unit", "kind": "test", "passed": 120, "failed": 0, "skipped": 0}'::jsonb
                             and migrations_pending = array['0231_retry_queue.sql'] and (deps ->> 'high')::int = 1 and coverage = 84.2
                             and repository = 'torlambrechts-sketch/orgpuls'
                      from app.dev_ci_runs where delivery_id = '1001-1-orgpuls'), 'its suites, pending migrations, findings, coverage and repository are kept by shape');
select pg_temp.expect_detail($$select public.worker_dev_ci('1002-1-orgpuls', now() - interval '6 minutes', (select r from t_run))$$, 'stale', 'at', 'a stale CI post is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1003-1-orgpuls', now(), (select r || '{"v": 2}' from t_run))$$, 'invalid', 'v', 'another payload version is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1004-1-orgpuls', now(), (select r || '{"product": "nope"}' from t_run))$$, 'invalid', 'product', 'an unknown product is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1011-1-orgpuls', now(), (select r - 'repository' from t_run))$$, 'invalid', 'repository', 'a post names its repository');
select pg_temp.expect_detail($$select public.worker_dev_ci('1012-1-orgpuls', now(), (select r || '{"repository": "someone/else"}' from t_run))$$,
                             'invalid', 'repository_unbound', 'a post from a repository nobody bound is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1013-1-orgpuls', now(), (select r || '{"product": "sentral"}' from t_run))$$,
                             'invalid', 'repository_product', 'Orgpuls'' repository does not post Sentral''s gate facts');
select pg_temp.expect_detail($$select public.worker_dev_ci('1014-1-orgpuls', now(), (select r || '{"repository": "torlambrechts-sketch/owntheagenda_admin"}' from t_run))$$,
                             'invalid', 'repository_product', 'nor does Sentral''s repository post Orgpuls''');
select pg_temp.check(not exists (select 1 from app.dev_ci_runs where delivery_id in ('1011-1-orgpuls', '1012-1-orgpuls', '1013-1-orgpuls', '1014-1-orgpuls'))
                     and not exists (select 1 from app.dev_deliveries where delivery_id in ('1011-1-orgpuls', '1012-1-orgpuls', '1013-1-orgpuls', '1014-1-orgpuls')),
                     'a refused post leaves nothing behind');
select pg_temp.expect_detail($$select public.worker_dev_ci('1005-1-orgpuls', now(), (select r || '{"sha": "main"}' from t_run))$$, 'invalid', 'sha', 'a sha must be a sha');
select pg_temp.expect_detail($$select public.worker_dev_ci('1006-1-orgpuls', now(), (select r || '{"suites": [{"name": "unit", "kind": "vibes", "passed": 1, "failed": 0}]}' from t_run))$$,
                             'invalid', 'suites', 'a suite kind outside the list is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1007-1-orgpuls', now(), (select r || '{"suites": [{"name": "<script>", "kind": "test", "passed": 1, "failed": 0}]}' from t_run))$$,
                             'invalid', 'suites', 'a suite name outside the safe characters is refused');
select pg_temp.expect_detail($$select public.worker_dev_ci('1008-1-orgpuls', now(), (select r || '{"migrations_pending": ["../etc/passwd"]}' from t_run))$$,
                             'invalid', 'migrations_pending', 'a pending migration must be a migration file name');
select pg_temp.check(public.worker_dev_ci('1009-1-sentral', now(), jsonb_build_object('v', 1, 'product', 'sentral', 'repository', 'torlambrechts-sketch/owntheagenda_admin',
                                          'sha', repeat('f', 40), 'ref', '12/merge', 'pr', 12,
                                          'suites', jsonb_build_array(jsonb_build_object('name', 'unit', 'kind', 'test', 'passed', 3, 'failed', 1)))) ->> 'applied' = 'true',
                     'Sentral''s own CI posts too');
select pg_temp.check((select status from app.integration_connections where provider = 'ci') = 'connected', 'the first CI post marks the CI connected');

-- ---------------------------------------------------------------------------
-- deploys and metrics as staff read them
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.dev_deploys() -> 'projects') = 1 and public.dev_deploys() -> 'projects' -> 0 ->> 'product' is null,
                     'the Vercel project is listed and belongs to no application until someone says so');
select pg_temp.check((select count(*) from jsonb_array_elements(public.dev_deploys() -> 'live') x where x ->> 'id' = 'dpl_eeeeeeee4') = 1,
                     'the live production deployment is the newest ready one');
select pg_temp.check(jsonb_array_length(public.dev_deploys() -> 'previews') = 1, 'previews are listed per branch');
select pg_temp.check(jsonb_array_length(public.dev_deploys() -> 'ci_runs') = 1 and public.dev_deploys() -> 'ci_runs' -> 0 ->> 'product' = 'orgpuls',
                     'the CI rows are each product''s newest run on its main line (a PR run is not one)');
select pg_temp.check(not (public.dev_deploys() -> 'vercel' ? 'secret') and (public.dev_deploys() -> 'vercel' ->> 'applied_30d')::int >= 7,
                     'the connection is described by counts, never by its secret');
select pg_temp.check((select count(*) = 2 and bool_and(x ->> 'bound_by' is not null) and count(*) filter (where x ->> 'last_run_at' is not null) = 2
                      from jsonb_array_elements(public.dev_deploys() -> 'ci_repos') x), 'the bound repositories are listed with who bound them and their newest post');
create temp table t_m as select public.dev_metrics(30) as m;
select pg_temp.check((select (m -> 'deploys' ->> 'ready')::int = 3 and (m -> 'deploys' ->> 'finished')::int = 4 and (m -> 'deploys' ->> 'failed')::int = 1
                             and (m -> 'deploys' ->> 'rolled_back')::int = 1 and (m -> 'deploys' ->> 'failure_rate')::numeric = 50.0 from t_m),
                     'deploys: three ready, four finished, one failed and one rolled back: 50 %');
select pg_temp.check((select (m ->> 'covered_days')::int = 1 and not (m ->> 'complete')::boolean and (m -> 'deploys' ->> 'per_day')::numeric = 3.00 from t_m),
                     'Vercel was heard today: the frequency is per day heard (3 a day), not per 30 days, and the window is not complete');
update app.dev_projects set first_seen_at = now() - interval '12 days' where true;
select pg_temp.check((select (m ->> 'covered_days')::int = 12 and not (m ->> 'complete')::boolean and (m -> 'deploys' ->> 'per_day')::numeric = 0.25
                      from (select public.dev_metrics(30) m) x), 'heard for 12 days: 3 ÷ 12');
update app.dev_projects set first_seen_at = now() - interval '45 days' where true;
select pg_temp.check((select (m ->> 'covered_days')::int = 30 and (m ->> 'complete')::boolean and (m -> 'deploys' ->> 'per_day')::numeric = 0.10
                      from (select public.dev_metrics(30) m) x), 'heard for longer than the window: 3 ÷ 30, complete');
select pg_temp.check((select (m -> 'lead' ->> 'n')::int = 1 and (m -> 'lead' ->> 'median_hours')::numeric between 3.0 and 3.1 from t_m),
                     'lead time from CI''s commit time to the first ready production deployment');
select pg_temp.check((select (m -> 'restore' ->> 'n')::int = 2 and (m -> 'restore' ->> 'median_minutes')::numeric = 3.3 from t_m),
                     'time to restore: the rollback (1,5 min live) and the failed build (5 min to the next good one), median 3,25');
select pg_temp.check((select m -> 'coverage' -> 0 ->> 'coverage' = '84.20' from t_m), 'coverage as CI reports it');
select pg_temp.expect_detail('select public.dev_metrics(3)', 'invalid', 'days', 'a window under a week is refused');

-- a Vercel project belongs to an application: configure only
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_project_set('prj_orgpulsweb1', 'orgpuls')$$, 'forbidden', 'dev:configure', 'Support does not map projects');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_project_set('prj_orgpulsweb1', 'nope')$$, 'invalid', 'product', 'only an application or Sentral');
select pg_temp.check((public.dev_project_set('prj_orgpulsweb1', 'orgpuls') ->> 'ok')::boolean, 'the owner maps the project to Orgpuls');

-- ---------------------------------------------------------------------------
-- releases
select pg_temp.as_staff('hanna@orgpuls.no');    -- Support: dev:add
create temp table t_rel as select (public.dev_release_add('orgpuls', 'Orgpuls 2026.10.2', current_date + 3) ->> 'id')::uuid as id;
grant all on t_rel to authenticated;
select pg_temp.expect_detail($$select public.dev_release_add('orgpuls', 'Orgpuls 2026.10.2')$$, 'invalid', 'name_taken', 'a product''s release names are unique');
select pg_temp.expect_detail($$select public.dev_release_add('nope', 'X 1')$$, 'invalid', 'product', 'an unknown product is refused');
select pg_temp.expect_detail($$select public.dev_release_add('orgpuls', 'X 2', null, 'zzz')$$, 'invalid', 'sha', 'a commit must be a sha');
create temp table t_g as select public.dev_releases_get((select id from t_rel)) as g;
select pg_temp.check((select g -> 'current' -> 'commit' ->> 'sha' = repeat('e', 40) and g -> 'current' -> 'commit' ->> 'source' = 'deploy' from t_g),
                     'without its own commit a release is about the live production deployment');
select pg_temp.check((select (select c ->> 'state' from jsonb_array_elements(g -> 'current' -> 'checks') c where c ->> 'key' = k) from t_g) = s,
                     'checklist ' || k || ' is ' || s)
from (values ('tests', 'pass'), ('migrations', 'fail'), ('rls', 'pass'), ('deps', 'fail'), ('deploy', 'pass'), ('notes', 'fail'), ('rollback', 'fail')) v(k, s);
select pg_temp.check((select jsonb_array_length(g -> 'current' -> 'checks') = 11 from t_g), 'eleven items, auto and manual');
select pg_temp.expect_detail(format($$select public.dev_release_sign(%L, 'rollback', true)$$, (select id from t_rel)), 'invalid', 'note', 'a rollback plan needs its text');
select pg_temp.expect_detail(format($$select public.dev_release_sign(%L, 'tests', true)$$, (select id from t_rel)), 'invalid', 'item', 'an auto item is not signed by hand');
select pg_temp.check((public.dev_release_sign((select id from t_rel), item, true, case when item = 'rollback' then 'Promote the previous deployment in Vercel' end) ->> 'ok')::boolean,
                     'Support signs ' || item)
from unnest(array['flag', 'preview', 'rollback', 'help']) item;
select pg_temp.expect_detail(format($$select public.dev_release_sign(%L, 'anonymity', true)$$, (select id from t_rel)), 'forbidden', 'owner_only',
                             'the anonymity check is not Support''s to sign (D-DEV-08)');
select pg_temp.check(not (public.dev_releases_get((select id from t_rel)) ->> 'can_sign_anonymity')::boolean, 'and Support is told so');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.dev_releases_get((select id from t_rel)) ->> 'can_sign_anonymity')::boolean
                     and (public.dev_release_sign((select id from t_rel), 'anonymity', true) ->> 'ok')::boolean, 'the owner signs the anonymity check');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.dev_release_sign(%L, 'anonymity', false)$$, (select id from t_rel)), 'forbidden', 'owner_only',
                             'nor does Support withdraw the owner''s signature');
select pg_temp.check((select c -> 'signed' ->> 'by' from jsonb_array_elements(public.dev_releases_get((select id from t_rel)) -> 'current' -> 'checks') c
                      where c ->> 'key' = 'rollback') = (select coalesce(name, email) from app.admins where email = 'hanna@orgpuls.no'), 'a sign-off names the person');
-- the changelog: a draft of the same product joins; another product's or a published one does not
create temp table t_notes as select (public.release_note_save(null, 'orgpuls', 'fixed', 'Invitations to municipal domains retry correctly') ->> 'id')::uuid as id, 'own' k
  union all select (public.release_note_save(null, 'skiftly', 'new', 'Shift swap marketplace') ->> 'id')::uuid, 'other';
grant all on t_notes to authenticated;
select pg_temp.expect_detail(format($$select public.dev_release_note_attach(%L, %L, true)$$, (select id from t_rel), (select id from t_notes where k = 'other')),
                             'invalid', 'product', 'another product''s note does not join');
select pg_temp.check((select count(*) from jsonb_array_elements(public.dev_releases_get((select id from t_rel)) -> 'current' -> 'drafts') d
                      where d ->> 'id' = (select id::text from t_notes where k = 'own')) = 1, 'the product''s unattached drafts are offered');
select pg_temp.check((public.dev_release_note_attach((select id from t_rel), (select id from t_notes where k = 'own'), true) ->> 'ok')::boolean, 'a draft joins the changelog');
-- not yet: migrations wait and a high finding is open
select pg_temp.expect_detail(format($$select public.dev_release_record(%L, %s)$$, (select id from t_rel), (select version from app.dev_releases where id = (select id from t_rel))),
                             'invalid', 'checklist', 'a release is not recorded while an item fails');
select pg_temp.expect_detail(format($$select public.dev_release_record(%L, 1)$$, (select id from t_rel)), 'version_conflict', null, 'an old version is refused');
-- CI says the migration is applied and the finding is fixed
select pg_temp.as_service();
select pg_temp.check(public.worker_dev_ci('1010-1-orgpuls', now(), (select r || jsonb_build_object('finished_at', now() + interval '1 minute', 'migrations_pending', '[]'::jsonb, 'dependencies',
                                          jsonb_build_object('critical', 0, 'high', 0, 'moderate', 6, 'low', 2)) from t_run)) ->> 'applied' = 'true', 'a newer CI run of the commit');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.dev_releases_get((select id from t_rel)) -> 'current' -> 'checks') c where c ->> 'state' <> 'pass'),
                     'every item passes');
select pg_temp.check((public.dev_release_record((select id from t_rel), (select version from app.dev_releases where id = (select id from t_rel))) ->> 'published')::int = 1,
                     'the release is recorded and its note published');
select pg_temp.check((select state = 'published' and published_by = (select id from app.admins where email = 'hanna@orgpuls.no') from app.release_notes
                      where id = (select id from t_notes where k = 'own')), 'the note is published by the person who recorded');
select pg_temp.check((select state = 'recorded' and sha = repeat('e', 40) and jsonb_array_length(checks) = 11 from app.dev_releases where id = (select id from t_rel)),
                     'the commit and the checklist are frozen with it');
select pg_temp.expect_detail(format($$select public.dev_release_sign(%L, 'flag', false)$$, (select id from t_rel)), 'invalid', 'recorded', 'a recorded release''s sign-offs stay');
select pg_temp.expect_detail(format($$select public.dev_release_delete(%L)$$, (select id from t_rel)), 'invalid', 'recorded', 'a recorded release is not deleted');
-- its changelog is frozen: no writer edits, unpublishes or deletes a note it was recorded with
select pg_temp.expect_detail(format($$select public.release_note_save(%L, 'skiftly', 'fixed', 'Something else entirely')$$, (select id from t_notes where k = 'own')),
                             'invalid', 'recorded', 'a recorded note is not rewritten');
select pg_temp.expect_detail(format($$select public.release_note_publish(%L, false)$$, (select id from t_notes where k = 'own')),
                             'invalid', 'recorded', 'a recorded note is not unpublished');
select pg_temp.expect_detail(format($$select public.release_note_delete(%L)$$, (select id from t_notes where k = 'own')),
                             'invalid', 'recorded', 'a recorded note is not deleted');
select pg_temp.expect_detail(format($$update app.release_notes set title = 'Edited behind the functions' where id = %L$$, (select id from t_notes where k = 'own')),
                             'invalid', 'recorded', 'nor is it rewritten by any other writer');
select pg_temp.expect_detail(format($$delete from app.release_notes where id = %L$$, (select id from t_notes where k = 'own')),
                             'invalid', 'recorded', 'or deleted by one');
select pg_temp.expect_detail(format($$delete from app.dev_release_notes where release_id = %L$$, (select id from t_rel)),
                             'invalid', 'recorded', 'or taken out of the recorded changelog');
update app.release_notes set feature_request_id = null, published_by = null where id = (select id from t_notes where k = 'own');
select pg_temp.check((select state = 'published' and title = 'Invitations to municipal domains retry correctly' from app.release_notes where id = (select id from t_notes where k = 'own')),
                     'referential maintenance (a person or a request gone) still passes, and the note is as released');
select pg_temp.check((select count(*) from app.dev_release_notes where release_id = (select id from t_rel)) = 1
                     and (public.release_note_publish((select id from t_notes where k = 'other'), true) ->> 'state') = 'published'
                     and (public.release_note_publish((select id from t_notes where k = 'other'), false) ->> 'state') = 'draft',
                     'the recorded changelog keeps its line, and a note in no recorded release is still published and withdrawn');
-- a later rollback is counted against the release
select pg_temp.as_service();
select pg_temp.check(public.worker_dev_vercel('evt_rb_0000000003', 'deployment.promoted', now() + interval '4 minutes',
                                              pg_temp.dep('dpl_cccccccc2', 'production', repeat('c', 40))) ->> 'rolled_back' = 'dpl_eeeeeeee4', 'a rollback after the release');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((select (r ->> 'rollbacks')::int from jsonb_array_elements(public.dev_releases_get(null) -> 'releases') r where r ->> 'id' = (select id::text from t_rel)) = 1,
                     'recent releases count the rollbacks after each');
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_rel2 as select (public.dev_release_add('sentral', 'Sentral 2026.10') ->> 'id')::uuid as id;
grant all on t_rel2 to authenticated;
select pg_temp.check((select c ->> 'state' from jsonb_array_elements(public.dev_releases_get((select id from t_rel2)) -> 'current' -> 'checks') c where c ->> 'key' = 'deploy') = 'unknown',
                     'with no Vercel project for Sentral the deploy item is unknown, not passed');
select pg_temp.check((public.dev_release_delete((select id from t_rel2)) ->> 'ok')::boolean, 'an open release is deleted');
-- «RLS and anonymity tests pass» needs an anonymity suite; security suites alone leave it unknown
create temp table t_rel3 as select (public.dev_release_add('orgpuls', 'Orgpuls 2026.10.3', null, repeat('9', 40)) ->> 'id')::uuid as id;
grant all on t_rel3 to authenticated;
select pg_temp.as_service();
select pg_temp.check(public.worker_dev_ci('1020-1-orgpuls', now(), (select r || jsonb_build_object('sha', repeat('9', 40), 'suites', jsonb_build_array(
                       jsonb_build_object('name', 'rls', 'kind', 'security', 'passed', 12, 'failed', 0),
                       jsonb_build_object('name', 'unit', 'kind', 'test', 'passed', 40, 'failed', 0))) from t_run)) ->> 'applied' = 'true', 'a run with security suites only');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((select c ->> 'state' = 'unknown' and (c -> 'detail' ->> 'anonymity')::boolean = false and (c -> 'detail' ->> 'passed')::int = 12
                      from jsonb_array_elements(public.dev_releases_get((select id from t_rel3)) -> 'current' -> 'checks') c where c ->> 'key' = 'rls'),
                     'without an anonymity suite the RLS and anonymity item is unknown, not passed');
select pg_temp.as_service();
select pg_temp.check(public.worker_dev_ci('1021-1-orgpuls', now(), (select r || jsonb_build_object('sha', repeat('9', 40), 'finished_at', now() + interval '1 minute', 'suites', jsonb_build_array(
                       jsonb_build_object('name', 'rls', 'kind', 'security', 'passed', 12, 'failed', 0),
                       jsonb_build_object('name', 'respondent_invariants', 'kind', 'anonymity', 'passed', 20, 'failed', 1))) from t_run)) ->> 'applied' = 'true',
                     'a newer run with a failing anonymity suite');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((select c ->> 'state' from jsonb_array_elements(public.dev_releases_get((select id from t_rel3)) -> 'current' -> 'checks') c where c ->> 'key' = 'rls') = 'fail',
                     'a failing anonymity suite fails it');
select pg_temp.check((select c ->> 'state' = 'unknown' and (c -> 'detail' ->> 'n')::int = 0
                      from jsonb_array_elements(public.dev_releases_get((select id from t_rel3)) -> 'current' -> 'checks') c where c ->> 'key' = 'tests'),
                     'a run with no suite of kind test says nothing about tests, and says it had none');
-- the help evidence counts the release's own product's published articles, not another product's or the samples
insert into app.help_articles (slug, title, product, status, published_at, is_sample, updated_at) values
  ('devfix-orgpuls-one', 'Orgpuls one', 'orgpuls', 'published', now(), false, now() + interval '1 minute'),
  ('devfix-orgpuls-sample', 'Orgpuls sample', 'orgpuls', 'published', now(), true, now() + interval '1 minute'),
  ('devfix-orgpuls-draft', 'Orgpuls draft', 'orgpuls', 'draft', null, false, now() + interval '1 minute'),
  ('devfix-skiftly-one', 'Skiftly one', 'skiftly', 'published', now(), false, now() + interval '1 minute'),
  ('devfix-skiftly-two', 'Skiftly two', 'skiftly', 'published', now(), false, now() + interval '1 minute');
create temp table t_rel4 as select (public.dev_release_add('skiftly', 'Skiftly 1.0') ->> 'id')::uuid as id;
grant all on t_rel4 to authenticated;
select pg_temp.check((select (c -> 'detail' ->> 'changed')::int from jsonb_array_elements(public.dev_releases_get((select id from t_rel3)) -> 'current' -> 'checks') c
                      where c ->> 'key' = 'help') = 1, 'Orgpuls'' release counts its one published article changed since its previous release');
select pg_temp.check((select (c -> 'detail' ->> 'changed')::int from jsonb_array_elements(public.dev_releases_get((select id from t_rel4)) -> 'current' -> 'checks') c
                      where c ->> 'key' = 'help') = 2, 'Skiftly''s release counts Skiftly''s two, not Orgpuls''');
-- an open release's changelog still changes
create temp table t_pulse as select (public.release_note_save(null, 'orgpuls', 'new', 'Pulse surveys') ->> 'id')::uuid as id;
grant all on t_pulse to authenticated;
select pg_temp.check((public.dev_release_note_attach((select id from t_rel3), (select id from t_pulse), true) ->> 'ok')::boolean
                     and (public.dev_release_note_attach((select id from t_rel3), (select id from t_pulse), false) ->> 'ok')::boolean
                     and (public.release_note_delete((select id from t_pulse)) ->> 'ok')::boolean,
                     'a draft joins an open release, leaves it, and is deleted');

-- ---------------------------------------------------------------------------
-- the integrations register
insert into app.growth_sync_log (source, state, rows) values ('google_ads', 'ok', 10), ('google_ads', 'failed', null), ('google_ads', 'ok', 4), ('google_ads', 'ok', 4);
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_i as select public.dev_integrations_get() as i;
select pg_temp.check((select jsonb_array_length(i -> 'rows') = 10 from t_i), 'ten of Sentral''s own integrations');
select pg_temp.check((select (r -> 'runs' ->> 'failed')::int >= 1 and (r -> 'runs' ->> 'total')::int >= 4 from t_i, jsonb_array_elements(i -> 'rows') r where r ->> 'key' = 'google_ads'),
                     'failure rates come from the integration''s own log');
select pg_temp.check((select r -> 'runs' is null or r -> 'runs' = 'null'::jsonb from t_i, jsonb_array_elements(i -> 'rows') r where r ->> 'key' = 'vercel')
                     and (select (r ->> 'deliveries_30d')::int >= 7 from t_i, jsonb_array_elements(i -> 'rows') r where r ->> 'key' = 'vercel'),
                     'an inbound integration counts deliveries, not errors');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_integration_set('google_ads', null, 'v25 sunsets', null, null, false)$$, 'forbidden', 'dev:configure',
                             'Support does not edit the register');
select pg_temp.expect_detail($$select public.dev_integration_plan('google_ads')$$, 'invalid', 'no_change', 'nothing to plan without an upcoming change');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.dev_integration_set('google_ads', null, 'v25 sunsets', null, 'http://insecure.example', false)$$, 'invalid', 'change_url',
                             'a change''s link is https');
select pg_temp.expect_detail($$select public.dev_integration_set('google_ads', null, 'v25 sunsets', null, null, true)$$, 'invalid', 'change_none',
                             '«None announced» and a change are not both');
select pg_temp.check((public.dev_integration_set('google_ads', (select id from app.admins where email = 'jonas@orgpuls.no'), 'v25 sunsets in January — upgrade to v26',
                                                 current_date + 90, 'https://developers.google.com/google-ads/api/docs/sunset-dates', false) ->> 'ok')::boolean,
                     'the owner records the owner and the upcoming change');
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_plan as select (public.dev_integration_plan('google_ads') ->> 'id')::uuid as id;
grant all on t_plan to authenticated;
select pg_temp.check((public.dev_integration_plan('google_ads') ->> 'existing')::boolean, 'one open plan per integration');
select pg_temp.check((select r -> 'plan' ->> 'owner' from jsonb_array_elements(public.dev_integrations_get() -> 'rows') r where r ->> 'key' = 'google_ads')
                     = (select coalesce(name, email) from app.admins where email = 'jonas@orgpuls.no'), 'the plan is the integration owner''s');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.dev_integration_set('google_ads', (select id from app.admins where email = 'jonas@orgpuls.no'), 'v26 sunsets in July', null, null, false) ->> 'ok')::boolean,
                     'the owner records a new change');
select pg_temp.check((select closed_as = 'superseded' from app.dev_integration_plans where id = (select id from t_plan)), 'a new change supersedes the open plan');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((public.dev_integration_plan_done((public.dev_integration_plan('google_ads') ->> 'id')::uuid) ->> 'ok')::boolean, 'a planned upgrade is marked done');
select pg_temp.expect_detail(format($$select public.dev_integration_plan_done(%L)$$, (select id from t_plan)), 'not_found', null, 'a closed plan is not closed twice');

-- ---------------------------------------------------------------------------
-- the audit names actions and fields, never values
select pg_temp.check(not exists (select 1 from app.audit where action like 'dev\_%' escape '\' and action !~ '^[a-z_]+\.[a-z_]+$'), 'every audit action has the platform''s shape');
select pg_temp.check((select count(distinct action) from app.audit where action in ('dev_release.added', 'dev_release.signed', 'dev_release.recorded', 'dev_release.changelog',
                                                                                   'dev_project.changed', 'dev_integration.changed', 'dev_integration.planned',
                                                                                   'dev_ci_repo.bound', 'dev_ci_repo.unbound')) = 9,
                     'every write is audited');
select pg_temp.check(not exists (select 1 from app.audit where action like 'dev\_%' escape '\' and detail::text ~ '(Promote the previous|municipal|sunsets)'),
                     'no audit row carries a person''s text');

rollback;
