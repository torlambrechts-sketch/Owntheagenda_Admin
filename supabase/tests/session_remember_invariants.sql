-- session_remember_invariants.sql — «Remember this device for 30 days» (0071): a session that proved its second factor
-- and asked to be remembered is exempt from the idle rule for 30 days, and nothing else; the owner's switch takes it
-- away at once; a session without the second factor cannot ask; Security › Live sessions shows it.
\ir _helpers.psql
begin;

create or replace function pg_temp.as_s(p_email text, p_session uuid, p_aal text default 'aal2') returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', p_aal, 'email', p_email, 'session_id', p_session)::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;
create or replace function pg_temp.signin(p_email text) returns uuid language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) select v_sid, u.id, now(), now(), 'aal2' from auth.users u where lower(u.email) = p_email;
  perform public.worker_login_event(jsonb_build_object('email', p_email, 'outcome', 'success', 'session_id', v_sid, 'method', 'password_totp', 'ip', '10.0.0.1',
                                                       'device_id', 'dev-' || p_email, 'user_agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Chrome/129.0 Safari/537.36'));
  return v_sid;
end $$;

create temp table t_s as select pg_temp.signin('tor@orgpuls.no') tor, pg_temp.signin('ingrid@orgpuls.no') ingrid;

-- without the second factor there is nobody to remember
select pg_temp.as_s('tor@orgpuls.no', (select tor from t_s), 'aal1');
select pg_temp.expect_error('select public.session_remember()', 'forbidden', 'a session without its second factor cannot be remembered');

select pg_temp.as_s('tor@orgpuls.no', (select tor from t_s));
select pg_temp.check((public.session_remember() ->> 'ok')::boolean
                     and (select trusted_until between now() + interval '29 days' and now() + interval '31 days' from app.staff_sessions where session_id = (select tor from t_s)),
                     'the person''s own session is remembered for 30 days');
select pg_temp.check((select trusted_until is null from app.staff_sessions where session_id = (select ingrid from t_s)), 'nobody else''s');

-- two hours idle: the remembered session stands, the other is ended
update app.staff_sessions set last_seen_at = now() - interval '2 hours' where session_id in (select tor from t_s union select ingrid from t_s);
select pg_temp.check(app.session_ok((select tor from t_s)) and not app.session_ok((select ingrid from t_s)), 'only the remembered session survives the idle rule');
select pg_temp.check((public.worker_session_seen((select tor from t_s), '10.0.0.1') ->> 'ok')::boolean, 'the middleware''s report keeps it');
select app.sessions_expire();
select pg_temp.check((select ended_at is null from app.staff_sessions where session_id = (select tor from t_s))
                     and (select end_reason = 'idle_timeout' from app.staff_sessions where session_id = (select ingrid from t_s)),
                     'the sweep ends the idle session and not the remembered one');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.security_dashboard() -> 'live') x
                             where (x ->> 'session_id')::uuid = (select tor from t_s) and x ->> 'remembered_until' is not null),
                     'Live sessions shows it, remembered, where it can be ended');

-- the owner's switch takes it away at once
select public.setting_set('session_remember', 'off', '', null);
select pg_temp.check(not app.session_ok((select tor from t_s)), 'with the option off, the idle rule applies again');

rollback;
