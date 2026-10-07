-- 0055_session_ok_reported.sql — a session must be in the register (V-SR-03; supersedes 0047's hotfix).
--
-- 0047 let a session the register does not know stay good while Auth had it, because nothing reported sessions. Since
-- 0048 the sign-in, the second factor and the middleware report through session-report, and the middleware enters an
-- unknown session at its next page view. Reports are now seen arriving in production. So an unreported session is good
-- only in its first ten minutes (the sign-in report, or the first page view, writes the row long before that); after
-- that it is nobody, so a session that only ever calls the API directly cannot stay outside the register, its idle rule
-- and its revocation. A session the register knows keeps every rule: ended, idle, outside the hours.
create or replace function app.session_ok(p_session uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select case when p_session is null then false else coalesce(
    (select s.ended_at is null
            and (app.setting('session_idle') <> 'on_30' or s.last_seen_at >= now() - interval '30 minutes')
            and app.time_allowed(now())
     from app.staff_sessions s where s.session_id = p_session),
    exists (select 1 from auth.sessions a where a.id = p_session and a.created_at > now() - interval '10 minutes')
      and app.time_allowed(now())) end
$fn$;
