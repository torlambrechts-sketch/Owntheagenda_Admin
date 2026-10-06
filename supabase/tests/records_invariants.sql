-- records_invariants.sql — the generic record path: custom fields, required fields, soft delete, restore,
-- purge, sandbox samples, typed reason, module switches.
\ir _helpers.psql
begin;

select pg_temp.as_staff('tor@orgpuls.no');
-- a custom field works end to end on organizations and people (the phase 0 gate)
create temp table t_f as select (public.field_save(null, '{"entity":"organization","key":"board_meeting","label":"Board meeting","type":"date"}') ->> 'id')::uuid id;
select public.field_save(null, '{"entity":"person","key":"tier","label":"Tier","type":"single_option","options":[{"key":"a","label":"A"},{"key":"b","label":"B"}]}');
create temp table t_o as select (public.rec_save('organization', null, '{"name":"Felt AS","custom":{"board_meeting":"2026-11-02"}}') ->> 'id')::uuid id;
select pg_temp.check((select custom ->> 'board_meeting' from app.organizations where id = (select id from t_o)) = '2026-11-02', 'a custom date is stored');
select pg_temp.check((public.rec_list('organization', '{"filters":[{"f":"custom.board_meeting","op":"gte","v":"2026-11-01"}]}') ->> 'total')::int = 1, 'a custom date can be filtered');
select pg_temp.expect_error(format($$select public.rec_save('organization', %L, '{"custom":{"board_meeting":"next week"}}')$$, (select id from t_o)), 'invalid', 'a malformed custom date is refused');
select pg_temp.expect_error(format($$select public.rec_save('organization', %L, '{"custom":{"nope":"x"}}')$$, (select id from t_o)), 'invalid', 'an unknown custom field is refused');
create temp table t_p as select (public.rec_save('person', null, jsonb_build_object('name', 'Per Felt', 'organization_id', (select id from t_o), 'custom', jsonb_build_object('tier', 'b'))) ->> 'id')::uuid id;
select pg_temp.expect_error(format($$select public.rec_save('person', %L, '{"custom":{"tier":"z"}}')$$, (select id from t_p)), 'invalid', 'an option outside the list is refused');
select pg_temp.check((public.rec_get('person', (select id from t_p)) ->> 'organization_id__title') = 'Felt AS', 'a person shows the title of their organization');
select pg_temp.check(exists (select 1 from app.changelog where record_id = (select id from t_p) and field = '*created'), 'a create is in the history');
-- removing a custom value with null
select public.rec_save('organization', (select id from t_o), '{"custom":{"board_meeting":null}}');
select pg_temp.check(not ((select custom from app.organizations where id = (select id from t_o)) ? 'board_meeting'), 'a null removes a custom value');
-- a required custom field must be given on create
select public.field_save((select id from t_f), '{"quality":"required"}');
select pg_temp.expect_error($$select public.rec_save('organization', null, '{"name":"Uten Felt AS"}')$$, 'invalid', 'a required custom field is required on create');
select public.field_save((select id from t_f), '{"quality":"optional"}');
-- a required column must be given
select pg_temp.expect_error($$select public.rec_save('organization', null, '{"city":"Oslo"}')$$, 'invalid', 'the name is required');
select pg_temp.expect_error($$select public.rec_save('organization', null, '{"name":"X","owner_id":"00000000-0000-0000-0000-000000000000"}')$$, 'invalid', 'the owner must be an active staff member');
select pg_temp.expect_error($$select public.rec_save('organization', null, '{"name":"X","account_id":"00000000-0000-0000-0000-000000000000"}')$$, 'invalid', 'a column the caller may not write is refused');

-- soft delete, restore, purge
select pg_temp.check((public.rec_delete('organization', array[(select id from t_o)]) ->> 'deleted')::int = 1, 'a record is soft-deleted');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_o)))) ->> 'total')::int = 0, 'a deleted record leaves the list');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('trash', true, 'ids', jsonb_build_array((select id from t_o)))) ->> 'total')::int = 1, 'and appears in the trash');
select pg_temp.check((public.rec_restore('organization', array[(select id from t_o)]) ->> 'restored')::int = 1, 'it can be restored');
select public.rec_delete('organization', array[(select id from t_o)]);
select pg_temp.as_nobody();
update app.organizations set deleted_at = now() - interval '31 days' where id = (select id from t_o);
select app.purge();
select pg_temp.check(not exists (select 1 from app.organizations where id = (select id from t_o)), 'the purge removes a record deleted over 30 days ago');
select pg_temp.check(not exists (select 1 from app.changelog where record_id = (select id from t_o)), 'and its history');
select pg_temp.check(exists (select 1 from app.people where id = (select id from t_p) and organization_id is null), 'a person of a purged organization stays, unlinked');

-- the sandbox: samples are visible only in sandbox mode, made there, and removed in one step
select pg_temp.as_staff('tor@orgpuls.no');
select public.sandbox_set(true);
create temp table t_s as select (public.rec_save('organization', null, '{"name":"Eksempel AS"}') ->> 'id')::uuid id;
select pg_temp.check((select is_sample from app.organizations where id = (select id from t_s)), 'a record made in the sandbox is a sample');
select public.sandbox_set(false);
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_s)))) ->> 'total')::int = 0, 'samples are hidden outside the sandbox');
select public.sandbox_clear();
select pg_temp.as_nobody();
select pg_temp.check(not exists (select 1 from app.organizations where is_sample), 'removing samples removes them all');

-- a typed reason, when the register asks for one
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('typed_reason', 'on');
select pg_temp.expect_error(format($$select public.rec_get('person', %L)$$, (select id from t_p)), 'reason_required', 'a read needs a reason when typed_reason is on');
select pg_temp.check((public.rec_get('person', (select id from t_p), 'T-2310 follow-up') ->> 'name') = 'Per Felt', 'with a reason it is allowed');
select pg_temp.check((select reason from app.audit where action = 'record.read' and target_id = (select id::text from t_p) order by id desc limit 1) = 'T-2310 follow-up', 'the reason is in the audit');
select public.setting_set('typed_reason', 'off');

-- labels belong to their record type
select pg_temp.expect_error(format($$select public.rec_save('person', %L, jsonb_build_object('labels', jsonb_build_array((select id from app.labels where entity = 'organization' limit 1))))$$, (select id from t_p)),
  'invalid', 'an organization label cannot go on a person');

rollback;
