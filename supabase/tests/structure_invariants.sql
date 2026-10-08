-- structure_invariants.sql — the platform's closed shape (CLAUDE.md rules 1, 6; D-34).
\ir _helpers.psql
begin;

-- every table in app: RLS on, no policy, nothing granted to a client role
select pg_temp.check(not exists (select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
  'every app table has row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app'), 'no app table has a policy');
select pg_temp.check(not exists (
  select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.grantee in ('anon', 'authenticated', 'PUBLIC')),
  'no client role has a grant on an app table');
select pg_temp.check(not exists (
  select 1 from information_schema.usage_privileges u where u.object_schema is null and u.object_name = 'app' and u.grantee in ('anon', 'authenticated')),
  'client roles cannot resolve the app schema');
select pg_temp.check(not has_schema_privilege('authenticated', 'app', 'usage'), 'authenticated has no usage on schema app');
select pg_temp.check(not has_schema_privilege('anon', 'app', 'usage'), 'anon has no usage on schema app');

-- every function a client may call is security definer with an empty search path
select pg_temp.check(not exists (
  select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
    and has_function_privilege('authenticated', p.oid, 'execute')
    and p.proname not like 'pgmq%'
    and (not p.prosecdef or not coalesce('search_path=""' = any (p.proconfig), false))
    and p.oid not in (select objid from pg_depend where deptype = 'e')),
  'every function authenticated can call is security definer with search_path empty');
select pg_temp.check(not exists (
  select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute')
    and p.oid not in (select objid from pg_depend where deptype = 'e')),
  'anon can call no platform function');

-- the anonymity firewall (D-34): no table or column here could hold survey answers or respondents
select pg_temp.check(not exists (
  select 1 from information_schema.columns c where c.table_schema = 'app'
    and c.column_name ~ '(^|_)(answer|answers|respondent|respondents|response_value|score_item|survey_comment)(_|$)'),
  'no column is named for survey answers or respondents');
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind in ('r', 'v', 'm')
    and c.relname ~ '(answer|respondent|survey_response|response_comment|extra_answer)'),
  'no table is named for survey answers or respondents');

-- the audit and the record history cannot be changed, deleted or emptied
select pg_temp.check(exists (select 1 from pg_trigger where tgname = 'audit_fixed' and tgrelid = 'app.audit'::regclass), 'audit has its append-only trigger');
select pg_temp.check(exists (select 1 from pg_trigger where tgname = 'audit_no_truncate' and tgrelid = 'app.audit'::regclass), 'audit has its truncate guard');
select pg_temp.check(exists (select 1 from pg_trigger where tgname = 'changelog_fixed' and tgrelid = 'app.changelog'::regclass), 'changelog has its append-only trigger');
insert into app.audit (actor, action, ok) values ('test', 'test.row', true);
select pg_temp.expect_error($$update app.audit set ok = ok$$, 'the audit is append-only', 'an audit row cannot be updated');
select pg_temp.expect_error($$truncate app.audit$$, 'the audit is append-only', 'the audit cannot be truncated');
insert into app.changelog (entity, record_id, field) values ('organization', gen_random_uuid(), 'name');
select pg_temp.expect_error($$delete from app.changelog$$, 'the record history is append-only', 'a history row cannot be deleted outside a purge');

-- the register: every setting defaults to an allowed value; the fixed ones are the firewall, MFA, the marketing rules
-- of D-27 and the survey-host block (0030)
select pg_temp.check((select array_agg(key order by key) from app.settings_registry where fixed) = array['campaign_rules', 'firewall', 'mfa', 'survey_flow_block'],
                     'the fixed settings are the firewall, MFA, the campaign rules and the survey-host block');
select pg_temp.check(not exists (select 1 from app.settings_registry where key in ('contact_rule', 'import_consent', 'sales_consent', 'second_admin', 'typed_reason', 'count_limits', 'plan_gates', 'api_rate')
  and default_value not in ('no_rule', 'off', 'unlimited', 'all_on')), 'the feature rules default to unrestricted (D-16)');

-- every record type names a table that exists and has the standard columns
select pg_temp.check(not exists (
  select 1 from app.entities e cross join unnest(array['id', 'version', 'created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at', 'is_sample', 'custom', 'labels']) col
  where not exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name = e.tbl and c.column_name = col)),
  'every record type has the standard columns');
select pg_temp.check(not exists (
  select 1 from app.entities e cross join unnest(array['owner_id', 'visibility']) col
  where e.owned and not exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name = e.tbl and c.column_name = col)),
  'every owned record type has owner and visibility');
select pg_temp.check(not exists (
  select 1 from app.entity_columns ec where not exists (select 1 from information_schema.columns c join app.entities e on e.tbl = c.table_name
    where c.table_schema = 'app' and e.key = ec.entity and c.column_name = ec.col)),
  'every registered column exists');

-- PostgREST runs a STABLE/IMMUTABLE function read-only: a public function that writes must be volatile (0046)
select pg_temp.check(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                 where n.nspname = 'public' and p.provolatile in ('s', 'i')
                                   and (p.prosrc ~* 'app\.log\(' or p.prosrc ~* '\minsert\s+into' or p.prosrc ~* '\mupdate\s+app\.'
                                        or p.prosrc ~* '\mdelete\s+from' or p.prosrc ~* 'app\.notify\(' or p.prosrc ~* 'pgmq\.send')),
                     'no stable or immutable public function writes (PostgREST would run it read-only)');

-- the hosted authenticator loads pg-safeupdate (0065): an UPDATE or DELETE with no WHERE at its top level is refused there,
-- even inside a security definer function, while these suites (run as postgres) would pass it. Parenthesised parts
-- (subqueries, case arguments) are dropped before looking for the WHERE.
select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral regexp_matches(p.prosrc, '((?:\mupdate|\mdelete\s+from)\s+(?:only\s+)?[a-z_]+\.[a-z_]+[^;]*;)', 'gi') m
  where n.nspname in ('app', 'public') and p.prokind = 'f'
    and regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(m[1],
          '\([^()]*\)', '', 'g'), '\([^()]*\)', '', 'g'), '\([^()]*\)', '', 'g'), '\([^()]*\)', '', 'g'), '\([^()]*\)', '', 'g'), '\([^()]*\)', '', 'g')
        !~* '\mwhere\M'),
  'every UPDATE and DELETE in a function has a WHERE clause (the hosted project refuses one without)');

rollback;
