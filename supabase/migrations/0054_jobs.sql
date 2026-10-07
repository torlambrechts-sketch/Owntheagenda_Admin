-- 0054_jobs.sql — the two jobs that need no outside provider run now: the transcript upload parser and the privacy
-- package (R-MEETINGS-06 parser part, R-SECURITY-03 worker part; V-MEETINGS-07, V-SECURITY-17, V-STORAGE-05).
--
-- There is no cron and no new secret. The app's server calls the jobs-run edge function right after the action that made a
-- job runnable (meeting_transcript_upload_done, privacy_export), with the person's own aal2 JWT. The function checks the token
-- with Auth and then asks this database one question, worker_jobs_claim, before it runs anything with the service role:
--
--   worker_jobs_claim(email, session, kind, id, more) → {allowed, reason, state, jobs: [...]}
--     * who: an active staff member with a confirmed account, in their own aal2 session the register accepts (the same test
--       as worker_storage_check, 0052, now in app.worker_caller);
--     * kind «transcript», id = a transcript: the caller's own upload behind it, landed (meeting_uploads.state «uploaded»)
--       and its transcript still processing;
--     * kind «privacy», id = an export job: the caller holds global:security (or is an admin) and requested or approved it,
--       and it is approved or running;
--     * a job runs once at a time: the claim stamps claimed_at and counts attempts. A claim younger than five minutes answers
--       «busy»; a finished job answers «done» with its state, so a second call never runs it twice. A job claimed three
--       times without finishing is failed here («too_many_attempts»), so a file that crashes the reader cannot loop;
--     * with more > 0 (at most 5) the answer also carries other jobs of the same kind that nobody's call ran: landed at least
--       two minutes ago, unclaimed or past their claim. They need no caller (the function returns nothing of them to the
--       caller but a count), and they are claimed the same way. Their ids come from here, never from the request body.
--   Reasons: invalid, not_allowed, not_found, busy, done. A transcript exists only once its upload was confirmed, and an
--   export is created approved, so neither can be named before it is runnable.
--
--   worker_upload_failed(upload, reason): the reader could not use the file. The reason is a code (^[a-z_]{1,80}$), never
--     the file's text; the transcript fails with it, the owner is told, the original is forgotten as worker_upload_parsed
--     does. A parsed file still goes through worker_upload_parsed (0042): worker_transcript_ready is the provider's path
--     and refuses an upload's transcript.
--
-- The package and the parse themselves are written by the existing worker functions (worker_privacy_package/_done,
-- worker_upload_parsed). Nothing here is reachable by a client role.

alter table app.meeting_uploads
  add column claimed_at timestamptz,
  add column attempts   smallint not null default 0 check (attempts between 0 and 10);
alter table app.privacy_jobs
  add column claimed_at timestamptz,
  add column attempts   smallint not null default 0 check (attempts between 0 and 10);

-- who is calling: the staff member behind a token Auth accepted, in that token's own session (0052's test)
create function app.worker_caller(p_staff_email text, p_session uuid, out staff uuid, out security boolean)
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_user uuid;
begin
  select a.id, u.id, coalesce(ps.kind = 'admin' or 'global:security' = any (ps.rights), false) into staff, v_user, security
  from app.admins a join auth.users u on lower(u.email) = a.email left join app.permission_sets ps on ps.id = a.permission_set_id
  where a.email = lower(btrim(coalesce(p_staff_email, ''))) and a.active and u.email_confirmed_at is not null;
  if staff is null or p_session is null
     or not exists (select 1 from auth.sessions s where s.id = p_session and s.user_id = v_user and s.aal = 'aal2')
     or not app.session_ok(p_session) then
    staff := null; security := false;
  end if;
end $fn$;

-- an upload the reader gave up on: failed with a reason code, the owner told, the original forgotten
create function app.jobs_upload_fail(p_upload uuid, p_reason text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare u app.meeting_uploads;
begin
  select * into u from app.meeting_uploads where id = p_upload for update;
  if not found or u.state <> 'uploaded' or u.transcript_id is null then return; end if;
  perform app.mtg_storage_forget(array[u.storage_path]);
  update app.meeting_uploads set state = 'failed', parsed_at = now(), claimed_at = null where id = u.id;
  if exists (select 1 from app.meeting_transcripts t where t.id = u.transcript_id and t.state = 'processing') then
    perform app.mtg_transcript_done(u.transcript_id, false, p_reason);
  end if;
end $fn$;

-- what the function needs to run one claimed upload: where the file is and what it claims to be
create function app.jobs_upload_row(u app.meeting_uploads, p_own boolean) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('kind', 'transcript', 'own', p_own, 'transcript_id', u.transcript_id, 'upload_id', u.id, 'bucket', 'meeting-files',
                            'path', u.storage_path, 'mime', u.mime, 'size', u.size_bytes,
                            'stored', exists (select 1 from storage.objects o where o.bucket_id = 'meeting-files' and o.name = u.storage_path))
$fn$;

create function public.worker_jobs_claim(p_staff_email text, p_session uuid, p_kind text, p_id uuid, p_more int default 0) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c record; v_more int := least(greatest(coalesce(p_more, 0), 0), 5);
  u app.meeting_uploads; j app.privacy_jobs; v_tstate text; v_jobs jsonb := '[]'::jsonb; x record;
  v_stale constant interval := interval '5 minutes'; v_orphan constant interval := interval '2 minutes'; v_max constant int := 3;
begin
  if p_kind is null or p_kind not in ('transcript', 'privacy') or p_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'invalid');
  end if;
  c := app.worker_caller(p_staff_email, p_session);
  if c.staff is null then return jsonb_build_object('allowed', false, 'reason', 'not_allowed'); end if;

  if p_kind = 'transcript' then
    select * into u from app.meeting_uploads where transcript_id = p_id for update;
    if not found or u.uploaded_by is distinct from c.staff then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
    select t.state into v_tstate from app.meeting_transcripts t where t.id = u.transcript_id;
    if u.state <> 'uploaded' or v_tstate is distinct from 'processing' then
      return jsonb_build_object('allowed', false, 'reason', 'done', 'state', coalesce(v_tstate, 'failed'));
    end if;
    if u.claimed_at > now() - v_stale then return jsonb_build_object('allowed', false, 'reason', 'busy', 'state', 'processing'); end if;
    if u.attempts >= v_max then
      perform app.jobs_upload_fail(u.id, 'too_many_attempts');
      return jsonb_build_object('allowed', false, 'reason', 'done', 'state', 'failed');
    end if;
    update app.meeting_uploads set claimed_at = now(), attempts = attempts + 1 where id = u.id returning * into u;
    v_jobs := v_jobs || app.jobs_upload_row(u, true);
    if v_more > 0 then
      for x in select m.id, m.attempts from app.meeting_uploads m join app.meeting_transcripts t on t.id = m.transcript_id
               where m.state = 'uploaded' and t.state = 'processing' and m.id <> u.id and m.created_at < now() - v_orphan
                 and (m.claimed_at is null or m.claimed_at < now() - v_stale)
               order by m.created_at limit v_more for update of m skip locked loop
        if x.attempts >= v_max then
          perform app.jobs_upload_fail(x.id, 'too_many_attempts');
        else
          update app.meeting_uploads set claimed_at = now(), attempts = attempts + 1 where id = x.id returning * into u;
          v_jobs := v_jobs || app.jobs_upload_row(u, false);
        end if;
      end loop;
    end if;
    return jsonb_build_object('allowed', true, 'reason', null, 'state', 'processing', 'jobs', v_jobs);
  end if;

  -- privacy: an export the caller asked for or approved, with the right to see packages
  select * into j from app.privacy_jobs where id = p_id and kind = 'export' for update;
  if not found then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
  if not c.security or (j.created_by is distinct from c.staff and j.approved_by is distinct from c.staff) then
    return jsonb_build_object('allowed', false, 'reason', 'not_allowed');
  end if;
  if j.state in ('done', 'failed') then return jsonb_build_object('allowed', false, 'reason', 'done', 'state', j.state); end if;
  if j.claimed_at > now() - v_stale then return jsonb_build_object('allowed', false, 'reason', 'busy', 'state', j.state); end if;
  if j.attempts >= v_max then
    update app.privacy_jobs set state = 'failed', error = 'too_many_attempts', finished_at = now(), claimed_at = null where id = j.id;
    return jsonb_build_object('allowed', false, 'reason', 'done', 'state', 'failed');
  end if;
  update app.privacy_jobs set claimed_at = now(), attempts = attempts + 1 where id = j.id;
  v_jobs := v_jobs || jsonb_build_object('kind', 'privacy', 'own', true, 'job_id', j.id, 'bucket', 'privacy-exports');
  if v_more > 0 then
    for x in select p.id, p.attempts from app.privacy_jobs p
             where p.kind = 'export' and p.state in ('approved', 'running') and p.id <> j.id and p.created_at < now() - v_orphan
               and (p.claimed_at is null or p.claimed_at < now() - v_stale)
             order by p.created_at limit v_more for update skip locked loop
      if x.attempts >= v_max then
        update app.privacy_jobs set state = 'failed', error = 'too_many_attempts', finished_at = now(), claimed_at = null where id = x.id;
      else
        update app.privacy_jobs set claimed_at = now(), attempts = attempts + 1 where id = x.id;
        v_jobs := v_jobs || jsonb_build_object('kind', 'privacy', 'own', false, 'job_id', x.id, 'bucket', 'privacy-exports');
      end if;
    end loop;
  end if;
  return jsonb_build_object('allowed', true, 'reason', null, 'state', j.state, 'jobs', v_jobs);
end $fn$;

-- the reader could not use the file: a reason code, never its text. → {ok, state}
create function public.worker_upload_failed(p_upload uuid, p_reason text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare u app.meeting_uploads;
begin
  if p_reason is null or p_reason !~ '^[a-z_]{1,80}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reason'; end if;
  select * into u from app.meeting_uploads where id = p_upload for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if u.state <> 'uploaded' or u.transcript_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  perform app.jobs_upload_fail(u.id, p_reason);
  return jsonb_build_object('ok', true, 'state', 'failed');
end $fn$;

do $$
declare f text;
begin
  foreach f in array array['app.worker_caller(text, uuid)', 'app.jobs_upload_fail(uuid, text)', 'app.jobs_upload_row(app.meeting_uploads, boolean)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.worker_jobs_claim(text, uuid, text, uuid, int)', 'public.worker_upload_failed(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
