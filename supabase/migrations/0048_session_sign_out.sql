-- 0048_session_sign_out.sql — signing out ends the session in the register (R-SECURITY-04).
--
-- The sign-in, the second factor and the middleware now report through the session-report edge function
-- (worker_login_event, worker_session_seen). Signing out is the person's own act on their own session, so it
-- needs no worker: the sign-out action calls this with the person's JWT before Auth forgets the session. The
-- row then reads «signed_out» in the login history instead of staying open until the idle rule ends it.

create function public.session_sign_out() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_session uuid := app.current_session(); v_staff uuid;
begin
  if v_session is null or auth.uid() is null then return jsonb_build_object('ended', false); end if;
  -- the caller's own row only: the account behind the JWT, whether or not the session is still good
  select a.id into v_staff from app.admins a join auth.users u on lower(u.email) = a.email where u.id = auth.uid();
  if v_staff is null or not exists (select 1 from app.staff_sessions s where s.session_id = v_session and s.staff_id = v_staff) then
    return jsonb_build_object('ended', false);
  end if;
  return jsonb_build_object('ended', app.session_end(v_session, 'signed_out', v_staff));
end $fn$;

revoke all on function public.session_sign_out() from public, anon;
grant execute on function public.session_sign_out() to authenticated;
