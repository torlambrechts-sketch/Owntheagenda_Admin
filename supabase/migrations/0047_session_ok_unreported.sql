-- 0047_session_ok_unreported.sql — HOTFIX. 0043's app.session_ok accepted an Auth session missing from
-- app.staff_sessions only for its first two minutes, expecting the sign-in to report it (worker_login_event /
-- worker_session_seen). Nothing reports sessions yet, and 0044's app.me() refuses a JWT whose session is not good, so
-- every signed-in staff member became nobody two minutes after signing in (R-SECURITY-04). Until sessions are
-- reported, a session the register does not know is good while Auth still has it (and within the sign-in hours); a
-- session the register knows keeps every rule: ended, idle, outside the hours. Revoking still works: session_end
-- marks the row and deletes the Auth session.
create or replace function app.session_ok(p_session uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_session is null then false else coalesce(
    (select s.ended_at is null
            and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')
            and app.time_allowed(now())
     from app.staff_sessions s where s.session_id = p_session),
    exists (select 1 from auth.sessions a where a.id = p_session) and app.time_allowed(now())) end
$fn$;
