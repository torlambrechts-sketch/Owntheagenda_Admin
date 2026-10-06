-- access_invariants.sql — who may do what, and see what (D-08, D-09, D-11). Runs on the design seed:
-- tor (Admin), ingrid and eirik (Sales, group Sales Norway), magnus (Support), ola (Read-only).
\ir _helpers.psql
begin;

-- without a second factor, nobody is staff
select pg_temp.as_staff('tor@orgpuls.no', 'aal1');
select pg_temp.check(app.me() is null, 'aal1 is not enough to be staff');
select pg_temp.expect_error($$select public.shell()$$, 'not_signed_in', 'the shell refuses aal1');
select pg_temp.expect_error($$select public.rec_list('organization')$$, 'not_signed_in', 'records refuse aal1');

-- an account that is not on the staff list is nobody, whatever its factor
select pg_temp.as_nobody();
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'stranger@example.com', now(), '{}', '{}', now(), now());
select pg_temp.as_staff('stranger@example.com');
select pg_temp.check(app.me() is null, 'an account outside the staff list is not staff');
select pg_temp.expect_error($$select public.search('lumio')$$, 'not_signed_in', 'search refuses a stranger');

-- a deactivated staff member is nobody
select pg_temp.as_nobody();
update app.admins set active = false where email = 'emma@orgpuls.no';
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.check(app.me() is null, 'a deactivated staff member is not staff');

-- the read-only analyst sees but cannot add, change or delete
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((public.rec_list('organization') ->> 'total')::int = 46, 'the analyst sees every organization');
select pg_temp.expect_error($$select public.rec_save('organization', null, '{"name":"X AS"}')$$, 'forbidden', 'the analyst cannot add');
select pg_temp.expect_error($$select public.rec_delete('organization', array[(select id from app.organizations limit 1)])$$, 'forbidden', 'the analyst cannot delete');
select pg_temp.expect_error($$select public.setting_set('tracking', 'off')$$, 'forbidden', 'the analyst cannot change settings');
select pg_temp.expect_error($$select public.staff_save(null, '{"email":"x@example.com"}')$$, 'forbidden', 'the analyst cannot add staff');

-- sales may add, edit their own, not another's
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_ids as select (public.rec_save('organization', null, '{"name":"Test Kunde AS","org_number":"912345678"}') ->> 'id')::uuid as id;
select pg_temp.check((select owner_id from app.organizations where id = (select id from t_ids)) = app.me(), 'a new record belongs to its creator');
select pg_temp.check((public.rec_save('organization', (select id from t_ids), '{"city":"Bergen"}', 1) ->> 'version')::int = 2, 'the owner can edit with the right version');
select pg_temp.expect_error(format($$select public.rec_save('organization', %L, '{"city":"Oslo"}', 1)$$, (select id from t_ids)), 'version_conflict', 'a stale version is refused');
select pg_temp.expect_error(format($$select public.rec_save('organization', %L, '{"city":"Oslo"}')$$,
  (select id from app.organizations where owner_id = (select id from app.admins where email = 'tor@orgpuls.no') limit 1)), 'forbidden', 'sales cannot edit another owner''s record');

-- visibility: a record kept to its owner is invisible to others, visible to the owner and an admin
select pg_temp.as_nobody();
update app.organizations set visibility = 'owner' where id = (select id from t_ids);
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_ids)))) ->> 'total')::int = 0, 'owner-only: another salesperson does not see it');
select pg_temp.expect_error(format($$select public.rec_get('organization', %L)$$, (select id from t_ids)), 'not_found', 'owner-only: another salesperson cannot open it');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_ids)))) ->> 'total')::int = 1, 'owner-only: an admin sees it');
-- the owner's group: eirik shares ingrid's group, magnus does not
select pg_temp.as_nobody();
update app.organizations set visibility = 'group' where id = (select id from t_ids);
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_ids)))) ->> 'total')::int = 1, 'group: a colleague in the owner''s group sees it');
select pg_temp.as_staff('magnus@orgpuls.no');
select pg_temp.check((public.rec_list('organization', jsonb_build_object('ids', jsonb_build_array((select id from t_ids)))) ->> 'total')::int = 0, 'group: someone outside the group does not');
-- the search follows visibility too
select pg_temp.check(not (public.search('Test Kunde')::text like '%Test Kunde AS%'), 'search does not reveal a record outside the group');

-- every write and read is audited with the actor
select pg_temp.as_nobody();
select pg_temp.check(exists (select 1 from app.audit where action = 'record.created' and target_id = (select id::text from t_ids) and staff_id = (select id from app.admins where email = 'ingrid@orgpuls.no')), 'the create is audited with its actor');
select pg_temp.check(exists (select 1 from app.audit where action = 'record.listed' and staff_id = (select id from app.admins where email = 'ola@orgpuls.no')), 'a list read is audited');
select pg_temp.check(exists (select 1 from app.changelog where record_id = (select id from t_ids) and field = 'city' and new_value = '"Bergen"'), 'the history holds the changed value');

-- a staff member cannot remove their own access
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error(format($$select public.staff_save(%L, '{"active":false}')$$, app.me()), 'forbidden', 'nobody deactivates themselves');
select pg_temp.expect_error($$select public.permission_set_save((select id from app.permission_sets where key = 'admin'), 'X', '{}')$$, 'forbidden', 'the admin set cannot be narrowed');
select pg_temp.expect_error($$select public.permission_set_save(null, 'Bad', array['deals:fly'])$$, 'new row for relation "permission_sets" violates check constraint "rights_known"', 'an unknown right cannot be granted');

rollback;
