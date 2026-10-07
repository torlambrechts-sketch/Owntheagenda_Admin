-- 0052_storage.sql — the private buckets the file RPCs name, and the signer's one question to the database
-- (R-PROJECTS-01, R-MOBILE-04, R-MEETINGS-06, R-SECURITY-03).
--
-- Buckets. Three private buckets, each limited to what the RPC that names it accepts:
--   * record-files     file_upload_begin (0044 body; capture_save uses the same rows): 25 MB, its thirteen types;
--   * meeting-files    meeting_transcript_upload_begin (0042): 5 MB, .vtt · .srt · .txt · .docx. A recording worker that
--                      stores audio here widens the bucket in its own migration;
--   * privacy-exports  the access package worker_privacy_done reports (0043): the object's name is the path it reports,
--                      verbatim (`privacy/<job>/<file>`); JSON, CSV or a ZIP of them, 50 MB (the project's own limit).
-- There is no storage.objects policy: no client role reads or writes an object. An upload or a download goes through a
-- URL the storage-sign edge function signs with the service role, and only after this database said yes.
--
-- worker_storage_check(email, session, bucket, path, mode): may this staff member, in this session, upload to or download
-- from this exact path now? The path never comes from the browser alone: the app's server reads it from the RPC that
-- checked the rights (file_upload_begin, file_download_url, meeting_transcript_upload_begin, privacy_export_url), and this
-- function finds the row behind it again:
--   * upload   a pending row the caller started moments ago (within the expiry the begin RPC promised) and whose object
--              does not exist yet. Nothing may be uploaded to the privacy bucket from outside: the worker writes it;
--   * download a ready file (or a finished, unexpired package) whose object exists, which the caller asked the database
--              for less than two minutes ago — file_download_url and privacy_export_url check visibility (or
--              global:security) and write the read to the audit in the same transaction, and that audit row is what is
--              looked up here, so a signature never outruns a read the database allowed and recorded. The original of
--              an uploaded transcript is read by the upload parser only (service role), never downloaded.
-- The staff member must be active with a confirmed account, and the session must be theirs, at aal2, and good by the
-- session register (app.session_ok). The answer is {allowed, reason, …}; the reasons are invalid, not_allowed, not_found,
-- expired, exists and missing. Nothing is logged here: the RPCs above already wrote the start or the read.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('record-files', 'record-files', false, 26214400,
   array['application/pdf', 'image/png', 'image/jpeg', 'text/csv', 'text/plain',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation',
         'image/webp', 'image/heic', 'audio/webm', 'audio/mp4', 'audio/mpeg']),
  ('meeting-files', 'meeting-files', false, 5242880,
   array['text/vtt', 'application/x-subrip', 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('privacy-exports', 'privacy-exports', false, 52428800,
   array['application/json', 'text/csv', 'application/zip'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create function public.worker_storage_check(p_staff_email text, p_session uuid, p_bucket text, p_path text, p_mode text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_staff uuid; v_user uuid; v_rights boolean;
  f app.record_files; u app.meeting_uploads; j app.privacy_jobs;
  v_object boolean;
begin
  if p_mode is null or p_mode not in ('upload', 'download') or p_bucket is null or p_bucket not in ('record-files', 'meeting-files', 'privacy-exports')
     or p_path is null or char_length(p_path) not between 3 and 500 or p_path ~ '(^/|\.\.|//|[[:cntrl:]\\])' then
    return jsonb_build_object('allowed', false, 'reason', 'invalid');
  end if;

  -- who: an active staff member with a confirmed account, in their own aal2 session the register accepts
  select a.id, u2.id, (ps.kind = 'admin' or 'global:security' = any (ps.rights)) into v_staff, v_user, v_rights
  from app.admins a join auth.users u2 on lower(u2.email) = a.email left join app.permission_sets ps on ps.id = a.permission_set_id
  where a.email = lower(btrim(coalesce(p_staff_email, ''))) and a.active and u2.email_confirmed_at is not null;
  if v_staff is null or p_session is null
     or not exists (select 1 from auth.sessions s where s.id = p_session and s.user_id = v_user and s.aal = 'aal2')
     or not app.session_ok(p_session) then
    return jsonb_build_object('allowed', false, 'reason', 'not_allowed');
  end if;

  v_object := exists (select 1 from storage.objects o where o.bucket_id = p_bucket and o.name = p_path);

  if p_bucket = 'record-files' and p_mode = 'upload' then
    select * into f from app.record_files where storage_path = p_path and uploaded_by = v_staff and ready_at is null and deleted_at is null;
    if not found then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
    if f.created_at < now() - interval '300 seconds' then return jsonb_build_object('allowed', false, 'reason', 'expired'); end if;
    if v_object then return jsonb_build_object('allowed', false, 'reason', 'exists'); end if;
    return jsonb_build_object('allowed', true, 'reason', null, 'mime', f.mime, 'size', f.size_bytes);
  end if;

  if p_bucket = 'record-files' then
    select * into f from app.record_files where storage_path = p_path and ready_at is not null and deleted_at is null;
    if not found then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
    if not exists (select 1 from app.audit x where x.staff_id = v_staff and x.action = 'file.read' and x.at > now() - interval '2 minutes'
                     and x.detail ->> 'file' = f.id::text) then
      return jsonb_build_object('allowed', false, 'reason', 'not_allowed');
    end if;
    if not v_object then return jsonb_build_object('allowed', false, 'reason', 'missing'); end if;
    return jsonb_build_object('allowed', true, 'reason', null, 'mime', f.mime, 'filename', f.filename);
  end if;

  if p_bucket = 'meeting-files' and p_mode = 'upload' then
    select * into u from app.meeting_uploads where storage_path = p_path and uploaded_by = v_staff and state = 'pending';
    if not found then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
    if u.created_at < now() - interval '600 seconds' then return jsonb_build_object('allowed', false, 'reason', 'expired'); end if;
    if v_object then return jsonb_build_object('allowed', false, 'reason', 'exists'); end if;
    return jsonb_build_object('allowed', true, 'reason', null, 'mime', u.mime, 'size', u.size_bytes);
  end if;

  if p_bucket = 'privacy-exports' and p_mode = 'download' then
    select * into j from app.privacy_jobs where storage_path = p_path and kind = 'export' and state = 'done';
    if not found then return jsonb_build_object('allowed', false, 'reason', 'not_found'); end if;
    if j.url_expires_at <= now() then return jsonb_build_object('allowed', false, 'reason', 'expired'); end if;
    if not coalesce(v_rights, false)
       or not exists (select 1 from app.audit x where x.staff_id = v_staff and x.action = 'privacy_package.viewed' and x.at > now() - interval '2 minutes'
                        and x.target_type = 'privacy_job' and x.target_id = j.id::text) then
      return jsonb_build_object('allowed', false, 'reason', 'not_allowed');
    end if;
    if not v_object then return jsonb_build_object('allowed', false, 'reason', 'missing'); end if;
    return jsonb_build_object('allowed', true, 'reason', null, 'mime', null, 'filename', substring(p_path from '[^/]+$'));
  end if;

  -- a transcript original is never downloaded; nothing is uploaded into the privacy bucket from outside
  return jsonb_build_object('allowed', false, 'reason', 'not_allowed');
end $fn$;
revoke all on function public.worker_storage_check(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.worker_storage_check(text, uuid, text, text, text) to service_role;
