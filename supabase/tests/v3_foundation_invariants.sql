-- v3_foundation_invariants.sql — what the v3 builders share (0078): a «dev» right scope (Support may see and add, Read-only
-- may see); feature requests with one vote per organisation and links to real tickets and deals; release notes that only
-- the right people write and that cannot be deleted once published; the Claude key, Vercel's and the CI's signing secrets
-- handed over only by the owner (fresh second factor, an intake number bound to its purpose, each name checked by shape)
-- and read only by the service role; the Claude gateway refuses without the feature's right, without a key and over the
-- hourly cap — which reserves each call before Claude is asked, under a per-person lock, completed by id and swept to a
-- timeout when its run died — builds its input only through a registered app.ai_ctx_* function, records calls with codes
-- only, and keeps a person's own subject's drafts (a test question) to that person. A request links only tickets and deals
-- the linker may see, and a reader is shown only the links they may see.
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
    and c.relname in ('feature_requests', 'feature_request_votes', 'feature_request_links', 'release_notes', 'ai_settings', 'ai_features', 'ai_outputs')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the shared tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('feature_requests', 'feature_request_votes', 'feature_request_links', 'release_notes', 'ai_settings', 'ai_features', 'ai_outputs')) = 7,
                     'all seven exist');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_ai_record(text, uuid, uuid, text, text, int, int, int, text, text, bigint)'::regprocedure, 'execute')
                     and has_function_privilege('service_role', 'public.worker_ai_record(text, uuid, uuid, text, text, int, int, int, text, text, bigint)'::regprocedure, 'execute'),
                     'only the service role records a Claude call');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute') and not has_function_privilege('anon', f::regprocedure, 'execute'),
                     'no client role calls ' || f)
from unnest(array['app.ai_calls_sweep()', 'app.ai_subject_ok(text, uuid)']) f;
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.store_v3_secrets(text, jsonb)', 'app.require_any(text, text)', 'app.dev_product_ok(text)', 'public.product_secret(text)',
                  'public.store_product_secrets(text, jsonb)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute'), 'nobody signed out calls ' || f)
from unnest(array['public.feature_requests_list(text, text)', 'public.release_notes_list(text, text)', 'public.ai_prepare(text, uuid)', 'public.v3_intake(text)']) f;

-- ---------------------------------------------------------------------------
-- the dev scope
select pg_temp.check(app.right_ok('dev:see') and app.right_ok('dev:add') and not app.right_ok('devs:see'), 'dev is a right scope');
select pg_temp.check((select rights @> array['dev:see', 'dev:add'] from app.permission_sets where key = 'support'), 'Support may see and add in Development');
select pg_temp.check((select rights @> array['dev:see'] and not rights @> array['dev:add'] from app.permission_sets where key = 'analyst'), 'Read-only may see Development');
select pg_temp.check((select not rights && array['dev:see', 'dev:add'] from app.permission_sets where key in ('sales')), 'Sales has no Development right');

-- ---------------------------------------------------------------------------
-- feature requests
select pg_temp.as_staff('ingrid@orgpuls.no');   -- Sales: global:add, no dev right
select pg_temp.check(jsonb_typeof(public.feature_requests_list('orgpuls')) = 'array', 'global:see reads the feature requests');
create temp table t_fr on commit drop as
  select (public.feature_request_add('orgpuls', 'Import employees from Visma', 'Asked in two renewals',
                                     (select id from app.organizations order by name limit 1)) ->> 'id')::uuid as id;
grant all on t_fr to authenticated;
select pg_temp.check((public.feature_requests_list('orgpuls') -> 0 ->> 'votes')::int = 1, 'the first organisation''s vote counts');
select pg_temp.check((public.feature_request_vote((select id from t_fr), (select id from app.organizations order by name limit 1), true) ->> 'votes')::int = 1,
                     'one vote per organisation: a second vote by the same organisation counts once');
select pg_temp.check((public.feature_request_vote((select id from t_fr), (select id from app.organizations order by name offset 1 limit 1), true) ->> 'votes')::int = 2,
                     'another organisation''s vote counts');
create temp table t_tk on commit drop as
  select (select id from app.tickets where queue_key = 'support' and visibility = 'all' and deleted_at is null order by number limit 1) as open_id,
         (select id from app.tickets where queue_key = 'personvern' and deleted_at is null order by number limit 1) as closed_id,
         (select id from app.deals where deleted_at is null and visibility = 'all' order by created_at, id limit 1) as private_deal,
         (select id from app.deals where deleted_at is null and visibility = 'all' order by created_at desc, id desc limit 1) as open_deal;
grant all on t_tk to authenticated;
select pg_temp.check((select open_id is not null and closed_id is not null and private_deal <> open_deal from t_tk), 'the seed has a Support ticket, a personvern one and two deals');
select pg_temp.check(jsonb_array_length(public.feature_request_link((select id from t_fr), 'ticket', (select open_id from t_tk), true) -> 'tickets') = 1,
                     'a request links to a real ticket the linker may see');
select pg_temp.expect_detail(format($$select public.feature_request_link(%L, 'ticket', %L, true)$$, (select id from t_fr), (select closed_id from t_tk)), 'not_found', 'ticket',
                             'a ticket in a queue the linker is not in is «not found» (Sales and personvern)');
update app.deals set visibility = 'owner', owner_id = (select id from app.admins where email = 'eirik@orgpuls.no') where id = (select private_deal from t_tk);
select pg_temp.expect_detail(format($$select public.feature_request_link(%L, 'deal', %L, true)$$, (select id from t_fr), (select private_deal from t_tk)), 'not_found', 'deal',
                             'another person''s private deal is «not found»');
select pg_temp.check(jsonb_array_length(public.feature_request_link((select id from t_fr), 'deal', (select open_deal from t_tk), true) -> 'deals') = 1,
                     'a deal the linker may see is linked');
select pg_temp.expect_detail(format($$select public.feature_request_link(%L, 'ticket', gen_random_uuid(), true)$$, (select id from t_fr)), 'not_found', 'ticket',
                             'a link to a ticket that does not exist is refused');
select pg_temp.expect_detail(format($$select public.feature_request_link(%L, 'invoice', gen_random_uuid(), true)$$, (select id from t_fr)), 'invalid', 'kind',
                             'only tickets and deals are linked');
select pg_temp.expect_detail($$select public.feature_request_add('nope', 'A title here')$$, 'invalid', 'product', 'an unknown product is refused');
select pg_temp.check(public.feature_request_set((select id from t_fr), '{"status": "shipped"}') ->> 'shipped_at' is not null, 'shipping stamps the date');
select pg_temp.check(public.feature_request_set((select id from t_fr), '{"status": "planned"}') ->> 'shipped_at' is null, 'un-shipping clears it');
select pg_temp.expect_detail(format($$select public.feature_request_set(%L, '{"ref": 5}')$$, (select id from t_fr)), 'invalid', 'ref', 'only title, problem and status change');
select pg_temp.check(public.feature_request_add('sentral', 'Help widget context payload') ->> 'product' = 'sentral', 'Sentral itself is a product in Development');
select pg_temp.as_staff('hanna@orgpuls.no');    -- Support: in the personvern queue
select pg_temp.check(jsonb_array_length(public.feature_request_link((select id from t_fr), 'ticket', (select closed_id from t_tk), true) -> 'tickets') = 2,
                     'someone in the personvern queue links its ticket and is shown both');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select r -> 'tickets' = jsonb_build_array((select open_id from t_tk)) from jsonb_array_elements(public.feature_requests_list('orgpuls')) r
                      where (r ->> 'id')::uuid = (select id from t_fr)), 'a reader outside the personvern queue is shown only the ticket they may see');
select pg_temp.expect_detail(format($$select public.feature_request_link(%L, 'ticket', %L, false)$$, (select id from t_fr), (select closed_id from t_tk)), 'not_found', 'ticket',
                             'nor can they remove a link they may not see');
select pg_temp.as_staff('sara@orgpuls.no');     -- Read-only: dev:see, global:see, no add
select pg_temp.check(jsonb_array_length(public.feature_requests_list('orgpuls')) >= 1, 'Read-only reads the requests');
select pg_temp.expect_detail($$select public.feature_request_add('orgpuls', 'Another one')$$, 'forbidden', 'dev:add|global:add', 'Read-only adds none');

-- ---------------------------------------------------------------------------
-- release notes
select pg_temp.as_staff('hanna@orgpuls.no');    -- Support: dev:add
create temp table t_rn on commit drop as
  select (public.release_note_save(null, 'orgpuls', 'new', 'Pulse surveys with a five-question template', null, null, 'manual') ->> 'id')::uuid as id;
grant all on t_rn to authenticated;
select pg_temp.check(public.release_notes_list('orgpuls', 'draft') @> jsonb_build_array(jsonb_build_object('id', (select id from t_rn))), 'a draft is listed');
select pg_temp.check(public.release_note_publish((select id from t_rn), true) ->> 'state' = 'published', 'it is published');
select pg_temp.expect_detail(format($$select public.release_note_delete(%L)$$, (select id from t_rn)), 'conflict', 'published', 'a published note is not deleted');
select pg_temp.check(public.release_note_publish((select id from t_rn), false) ->> 'published_at' is null, 'unpublishing returns it to draft');
select pg_temp.check((public.release_note_delete((select id from t_rn)) ->> 'ok')::boolean, 'a draft is deleted');
select pg_temp.expect_detail($$select public.release_note_save(null, 'orgpuls', 'other', 'A title here')$$, 'invalid', 'kind', 'kind is new, improved or fixed');
select pg_temp.as_staff('ingrid@orgpuls.no');   -- Sales: neither dev:add nor tickets:edit_others
select pg_temp.expect_detail($$select public.release_note_save(null, 'orgpuls', 'new', 'A title here')$$, 'forbidden', 'dev:add|tickets:edit_others', 'Sales writes no release notes');

-- ---------------------------------------------------------------------------
-- secrets: the owner, a fresh second factor, an intake number bound to the purpose, each name by shape
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.v3_intake('anthropic')$$, 'forbidden', 'owner_only', 'only the owner opens an intake for Claude');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.v3_intake('vercel')$$, 'forbidden', 'fresh_mfa', 'the intake needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.v3_intake('github')$$, 'invalid', 'purpose', 'only the three purposes');
create temp table t_codes on commit drop as select p, public.v3_intake(p) ->> 'intake_code' as code from unnest(array['anthropic', 'vercel', 'ci', 'anthropic']) with ordinality u(p, n);
grant all on t_codes to authenticated;
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"vercel_signing_secret": "abcdefghijklmnopqrstuvwx"}')$$, (select code from t_codes where p = 'anthropic' limit 1)),
                             'invalid', 'name', 'an intake number takes only its own purpose''s name');
select pg_temp.check((public.store_product_secrets((select code from t_codes where p = 'vercel'), '{"vercel_signing_secret": "abcdefghijklmnopqrstuvwx"}') ->> 'stored')::int = 1,
                     'Vercel''s signing secret is stored');
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"ci_signing_secret": "short"}')$$, (select code from t_codes where p = 'ci')),
                             'invalid', 'name', 'a CI secret shorter than 32 characters is refused');
select pg_temp.check((public.store_product_secrets((select code from t_codes where p = 'anthropic' offset 1 limit 1),
                       jsonb_build_object('anthropic_api_key', 'sk-ant-' || repeat('a', 40))) ->> 'stored')::int = 1, 'the Claude key is stored');
select pg_temp.check(public.product_secret('anthropic_api_key') like 'sk-ant-%' and public.product_secret('vercel_signing_secret') is not null,
                     'the service role reads both');
select pg_temp.check((select status from app.integration_connections where provider = 'ai') = 'connected', 'Claude counts as connected once its key is stored');

-- ---------------------------------------------------------------------------
-- the gateway
create function app.ai_ctx_test_note(p_subject uuid) returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('system', 'Write a release note.', 'prompt', r.title) from app.feature_requests r where r.id = p_subject
$$;
insert into app.ai_features (key, scope, action, subject_type, context_fn) values ('test_note', 'dev', 'add', 'feature_request', 'app.ai_ctx_test_note');
select pg_temp.check((select count(*) from app.ai_features where context_fn !~ '^app\.ai_ctx_') = 0, 'every context function is an app.ai_ctx_* function');
do $$
begin
  insert into app.ai_features (key, scope, action, subject_type, context_fn) values ('test_bad', 'dev', 'add', 'x', 'public.anything');
  raise exception 'FAIL a context function outside app.ai_ctx_* was accepted';
exception when check_violation then raise notice 'ok a context function outside app.ai_ctx_* is refused';
end $$;
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format($$select public.ai_prepare('test_note', %L)$$, (select id from t_fr)), 'forbidden', 'dev:add', 'the feature''s right is required');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((select provolatile = 'v' and prosrc ~ 'pg_advisory_xact_lock' from pg_proc where oid = 'public.ai_prepare(text, uuid)'::regprocedure),
                     'ai_prepare writes its reservation (volatile) under a lock, so parallel requests are counted one after another');
create temp table t_prep on commit drop as select public.ai_prepare('test_note', (select id from t_fr)) as p;
grant all on t_prep to authenticated;
select pg_temp.check((select p ->> 'prompt' = 'Import employees from Visma' and p ->> 'model' = 'claude-opus-5-5' from t_prep), 'the input comes from the context function');
select pg_temp.check((select c.state = 'pending' and c.feature = 'test_note' and c.staff_id = app.me() and c.subject_id = (select id from t_fr)
                             and c.input_tokens is null and c.error_code is null
                      from app.ai_calls c where c.id = (select (p ->> 'call')::bigint from t_prep)),
                     'the call is reserved before Claude is asked: a pending row of the person''s');
select pg_temp.expect_detail($$select public.ai_prepare('test_note', gen_random_uuid())$$, 'not_found', 'subject', 'an unknown subject builds no request');
select pg_temp.expect_detail(format($$select public.ai_prepare('nothing', %L)$$, (select id from t_fr)), 'not_found', 'feature', 'an unknown feature is refused');
select pg_temp.check(not (public.ai_status() ? 'anthropic_api_key') and (public.ai_status() ->> 'connected')::boolean
                     and not (public.ai_status() ->> 'can_manage')::boolean, 'the status names the connection, never the key; only the owner manages');
select pg_temp.as_service();
create temp table t_rec on commit drop as
  select public.worker_ai_record('test_note', (select id from t_fr), (select id from app.admins where email = 'hanna@orgpuls.no'), 'Draft text', 'claude-opus-5-5',
                                 120, 80, 900, 'ok', null, (select (p ->> 'call')::bigint from t_prep)) as r;
grant all on t_rec to authenticated;
select pg_temp.check((select (r ->> 'output') is not null and (r ->> 'call')::bigint = (select (p ->> 'call')::bigint from t_prep) from t_rec), 'an answer becomes a draft');
select pg_temp.check((select c.state = 'ok' and c.input_tokens = 120 and c.output_tokens = 80 and c.latency_ms = 900 and c.error_code is null
                      from app.ai_calls c where c.id = (select (p ->> 'call')::bigint from t_prep))
                     and (select o.ai_call_id from app.ai_outputs o where o.id = (select (r ->> 'output')::uuid from t_rec)) = (select (p ->> 'call')::bigint from t_prep),
                     'the reserved row is completed by its id, and the draft names it');
select pg_temp.expect_detail(format($$select public.worker_ai_record('test_note', %L, %L, 'Again', 'claude-opus-5-5', 1, 1, 1, 'ok', null, %s)$$,
                                    (select id from t_fr), (select id from app.admins where email = 'hanna@orgpuls.no'), (select (p ->> 'call')::bigint from t_prep)),
                             'conflict', 'call', 'a completed call is not completed again');
select pg_temp.expect_error(format($$update app.ai_calls set state = 'error', error_code = 'timeout' where id = %s$$, (select (p ->> 'call')::bigint from t_prep)),
                            'the AI call log is append-only', 'a completed call never changes');
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_prep2 on commit drop as select public.ai_prepare('test_note', (select id from t_fr)) as p;
grant all on t_prep2 to authenticated;
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.worker_ai_record('test_note', gen_random_uuid(), %L, 'X', 'claude-opus-5-5', 1, 1, 1, 'ok', null, %s)$$,
                                    (select id from app.admins where email = 'hanna@orgpuls.no'), (select (p ->> 'call')::bigint from t_prep2)),
                             'invalid', 'call', 'a reserved call is completed only for its own subject');
select pg_temp.expect_error(format($$update app.ai_calls set feature = 'spec_draft', state = 'ok' where id = %s$$, (select (p ->> 'call')::bigint from t_prep2)),
                            'the AI call log is append-only', 'completing a reserved call never changes what it was for');
select pg_temp.check((public.worker_ai_record('test_note', (select id from t_fr), (select id from app.admins where email = 'hanna@orgpuls.no'), null, 'claude-opus-5-5',
                                              0, 0, 1200, 'not_connected', 'not_connected', (select (p ->> 'call')::bigint from t_prep2)) ->> 'output') is null,
                     'a reserved call that never reached Claude leaves no draft');
select pg_temp.check((select state = 'not_connected' and error_code = 'not_connected' from app.ai_calls where id = (select (p ->> 'call')::bigint from t_prep2)),
                     'and is completed with its code');
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_prep3 on commit drop as select public.ai_prepare('test_note', (select id from t_fr)) as p;
grant all on t_prep3 to authenticated;
select pg_temp.as_service();
select public.worker_ai_record('test_note', (select id from t_fr), null, null, null, 0, 0, 0, 'invalid', 'prepare_shape', (select (p ->> 'call')::bigint from t_prep3));
select pg_temp.check((select state = 'invalid' and error_code = 'prepare_shape' and model = 'claude-opus-5-5'
                             and staff_id = (select id from app.admins where email = 'hanna@orgpuls.no')
                      from app.ai_calls where id = (select (p ->> 'call')::bigint from t_prep3)),
                     'a request ai-run could not parse completes its reservation as invalid, keeping who reserved it and the model');
select pg_temp.check((public.worker_ai_record('test_note', (select id from t_fr), null, null, 'claude-opus-5-5', 10, 0, 300, 'invalid', 'refusal') ->> 'output') is null,
                     'a refusal leaves no draft');
select pg_temp.check((select error_code from app.ai_calls order by id desc limit 1) = 'refusal', 'a refusal is recorded by its code');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check(public.ai_outputs_get('test_note', (select id from t_fr)) -> 0 ->> 'body' = 'Draft text', 'the draft is read under the feature''s right');
select pg_temp.check((public.ai_output_set((select (r ->> 'output')::uuid from t_rec), 'used') ->> 'ok')::boolean, 'a draft is marked used');
select pg_temp.as_staff('magnus@orgpuls.no');   -- Support too: the same right, another person
select pg_temp.check(public.ai_outputs_get('test_note', (select id from t_fr)) -> 0 ->> 'body' = 'Draft text', 'a shared subject''s drafts are read by anyone with the right');

-- the hourly cap counts reservations: with room for one more call, the first is prepared and the second refused
select pg_temp.as_staff('hanna@orgpuls.no');
update app.ai_settings set hourly_cap = (select count(*) + 1 from app.ai_calls c where c.staff_id = app.me() and c.at > now() - interval '1 hour');
select pg_temp.check(public.ai_prepare('test_note', (select id from t_fr)) ? 'call', 'the last call of the hour is prepared and reserved');
select pg_temp.expect_detail(format($$select public.ai_prepare('test_note', %L)$$, (select id from t_fr)), 'rate_limited', null,
                             'the next one in the same hour is refused while the first has not answered: the reservation counts');
update app.ai_settings set hourly_cap = 1;
select pg_temp.expect_detail(format($$select public.ai_prepare('test_note', %L)$$, (select id from t_fr)), 'rate_limited', null, 'the hourly cap holds');
update app.ai_settings set hourly_cap = 30;
create temp table t_n on commit drop as select count(*) as n from app.ai_calls;
grant all on t_n to authenticated;
select pg_temp.expect_detail($$select public.ai_prepare('test_note', gen_random_uuid())$$, 'not_found', 'subject', 'a subject that builds no request is refused');
select pg_temp.check((select count(*) from app.ai_calls) = (select n from t_n), 'and reserves nothing');

-- a reservation nobody completed is a timeout after ten minutes, and still counts
insert into app.ai_calls (feature, staff_id, subject_type, subject_id, provider, model, state, at)
values ('test_note', (select id from app.admins where email = 'hanna@orgpuls.no'), 'feature_request', (select id from t_fr), 'anthropic', 'claude-opus-5-5', 'pending', now() - interval '11 minutes'),
       ('test_note', (select id from app.admins where email = 'hanna@orgpuls.no'), 'feature_request', (select id from t_fr), 'anthropic', 'claude-opus-5-5', 'pending', now() - interval '2 minutes');
select pg_temp.check((app.ai_calls_sweep() ->> 'timed_out')::int >= 1, 'the sweep reports what it timed out');
select pg_temp.check((select state = 'error' and error_code = 'timeout' from app.ai_calls where feature = 'test_note' and at = now() - interval '11 minutes')
                     and (select state = 'pending' from app.ai_calls where feature = 'test_note' and at = now() - interval '2 minutes'),
                     'the sweep turns a reservation older than ten minutes into error/timeout and leaves a recent one');
select pg_temp.check(exists (select 1 from app.job_defs where key = 'ai_sweep' and fn = 'app.ai_calls_sweep' and source = 'cron' and quiet)
                     and exists (select 1 from cron.job where jobname = 'platform-ai-sweep' and command = 'select app.run_job(''ai_sweep'')'),
                     'the sweep runs every five minutes through the job monitor');
select pg_temp.check((public.ai_status() ->> 'failed_30d')::int
                     = (select count(*) from app.ai_calls c where c.provider = 'anthropic' and c.at > now() - interval '30 days' and c.state not in ('ok', 'retried_ok', 'pending')),
                     'a call in flight is not counted as failed');

-- a person's own subject (a test question, 0081): its drafts are theirs alone
create temp table t_hq on commit drop as
  with q as (insert into app.help_test_questions (product, locale, question, created_by)
             values ('orgpuls', 'nb', 'Hvordan legger jeg til ansatte?', (select id from app.admins where email = 'hanna@orgpuls.no')) returning id)
  select id from q;
grant all on t_hq to authenticated;
select pg_temp.as_service();
create temp table t_hrec on commit drop as
  select public.worker_ai_record('help_answer_preview', (select id from t_hq), (select id from app.admins where email = 'hanna@orgpuls.no'), 'Svar', 'claude-opus-5-5',
                                 50, 20, 700, 'ok', null) as r;
grant all on t_hrec to authenticated;
select pg_temp.as_staff('magnus@orgpuls.no');   -- Support, tickets:ai, not the asker
select pg_temp.check(public.ai_outputs_get('help_answer_preview', (select id from t_hq)) = '[]'::jsonb, 'another person with the right does not read the asker''s draft');
select pg_temp.expect_detail(format($$select public.ai_output_set(%L, 'discarded')$$, (select (r ->> 'output')::uuid from t_hrec)), 'not_found', null, 'nor decides it');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.check(public.ai_outputs_get('help_answer_preview', (select id from t_hq)) = '[]'::jsonb, 'nor does the owner');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check(public.ai_outputs_get('help_answer_preview', (select id from t_hq)) -> 0 ->> 'body' = 'Svar'
                     and (public.ai_output_set((select (r ->> 'output')::uuid from t_hrec), 'used') ->> 'ok')::boolean, 'the asker reads and decides it');
select pg_temp.as_mfa('tor@orgpuls.no');
select pg_temp.check((public.v3_disconnect('anthropic') ->> 'ok')::boolean, 'the owner disconnects Claude');
select pg_temp.check(not exists (select 1 from vault.secrets where name = 'anthropic_api_key')
                     and (select status from app.integration_connections where provider = 'ai') = 'not_connected', 'disconnecting removes the key');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.ai_prepare('test_note', %L)$$, (select id from t_fr)), 'not_connected', null, 'without a key nothing is prepared');

rollback;
