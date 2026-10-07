-- storage_invariants.sql — the private buckets and the signer's question (0052; R-PROJECTS-01, R-MOBILE-04, R-MEETINGS-06,
-- R-SECURITY-03; CRM-05: no file without the record).
\ir _helpers.psql
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
begin;

-- ---------------------------------------------------------------------------
-- buckets: private, limited to what their RPCs accept; no client role reaches an object
select pg_temp.check((select count(*) from storage.buckets where id in ('record-files', 'meeting-files', 'privacy-exports') and not public) = 3,
                     'record-files, meeting-files and privacy-exports exist and are private');
select pg_temp.check((select file_size_limit = 26214400 and cardinality(allowed_mime_types) = 13 and 'audio/webm' = any (allowed_mime_types)
                             and 'application/pdf' = any (allowed_mime_types) and not 'text/html' = any (allowed_mime_types)
                      from storage.buckets where id = 'record-files'), 'record-files takes 25 MB and the thirteen types file_upload_begin accepts');
select pg_temp.check((select array(select x from unnest(allowed_mime_types) x order by x) from storage.buckets where id = 'record-files')
                     = (select array(select substring(m[1] from 2 for char_length(m[1]) - 2) from regexp_matches(pg_get_constraintdef(c.oid), '(''[^'']+'')', 'g') m order by 1)
                        from pg_constraint c where c.conname = 'record_files_mime_check' and c.conrelid = 'app.record_files'::regclass),
                     'record-files allows exactly the types record_files holds');
select pg_temp.check((select file_size_limit = 5242880 and allowed_mime_types @> array['text/vtt', 'application/x-subrip', 'text/plain'] and cardinality(allowed_mime_types) = 4
                      from storage.buckets where id = 'meeting-files'), 'meeting-files takes 5 MB of .vtt, .srt, .txt and .docx');
select pg_temp.check((select file_size_limit = 52428800 and allowed_mime_types = array['application/json', 'text/csv', 'application/zip']
                      from storage.buckets where id = 'privacy-exports'), 'privacy-exports takes the JSON/CSV package');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'storage' and tablename in ('objects', 'buckets')),
                     'no storage policy: objects are reached only through signed URLs');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_storage_check(text, uuid, text, text, text)', 'execute')
                     and not has_function_privilege('anon', 'public.worker_storage_check(text, uuid, text, text, text)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_storage_check(text, uuid, text, text, text)', 'execute'),
                     'only the service role may ask the signer''s question');

-- sessions as Auth holds them: tor and emma at aal2, tor's first factor only
create temp table t_s as select gen_random_uuid() tor, gen_random_uuid() tor1, gen_random_uuid() emma, gen_random_uuid() ingrid, gen_random_uuid() ola;
insert into auth.sessions (id, user_id, created_at, updated_at, aal)
select s.id, u.id, now(), now(), s.aal::auth.aal_level from (values
  ((select tor from t_s), 'tor@orgpuls.no', 'aal2'), ((select tor1 from t_s), 'tor@orgpuls.no', 'aal1'), ((select emma from t_s), 'emma@orgpuls.no', 'aal2'),
  ((select ingrid from t_s), 'ingrid@orgpuls.no', 'aal2'), ((select ola from t_s), 'ola@orgpuls.no', 'aal2')) s(id, email, aal)
join auth.users u on lower(u.email) = s.email;
create function pg_temp.chk(p_email text, p_session uuid, p_bucket text, p_path text, p_mode text) returns text language sql as $$
  select coalesce(r ->> 'reason', case when (r ->> 'allowed')::boolean then 'allowed' end) from (select public.worker_storage_check(p_email, p_session, p_bucket, p_path, p_mode) r) x
$$;

-- ---------------------------------------------------------------------------
-- record files: an upload is signed only for the caller's own pending row, once
create temp table t_rec as select id from app.deals where deleted_at is null order by created_at limit 1;
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_up as select public.file_upload_begin('deal', (select id from t_rec), 'Avtale.pdf', 'application/pdf', 1200) r;
create temp table t_p as select r ->> 'path' p, (r ->> 'id')::uuid id from t_up;
select pg_temp.as_nobody();
select pg_temp.check((select public.worker_storage_check('tor@orgpuls.no', (select tor from t_s), 'record-files', p, 'upload') from t_p)
                     @> '{"allowed": true, "mime": "application/pdf", "size": 1200}', 'the uploader may upload to the path their pending file names');
select pg_temp.check(pg_temp.chk('TOR@orgpuls.no ', (select tor from t_s), 'record-files', (select p from t_p), 'upload') = 'allowed', 'the address is matched without case or spaces');
select pg_temp.check(pg_temp.chk('emma@orgpuls.no', (select emma from t_s), 'record-files', (select p from t_p), 'upload') = 'not_found', 'nobody else may upload to it');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select emma from t_s), 'record-files', (select p from t_p), 'upload') = 'not_allowed', 'a session that is not the caller''s is refused');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor1 from t_s), 'record-files', (select p from t_p), 'upload') = 'not_allowed', 'a session without the second factor is refused');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', gen_random_uuid(), 'record-files', (select p from t_p), 'upload') = 'not_allowed', 'a session Auth does not hold is refused');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', null, 'record-files', (select p from t_p), 'upload') = 'not_allowed', 'no session, no signature');
select pg_temp.check(pg_temp.chk('nobody@example.com', (select tor from t_s), 'record-files', (select p from t_p), 'upload') = 'not_allowed', 'an address that is not staff is refused');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', 'deal/../etc/passwd', 'upload') = 'invalid'
                     and pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', '/' || (select p from t_p), 'upload') = 'invalid'
                     and pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'avatars', (select p from t_p), 'upload') = 'invalid'
                     and pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'delete') = 'invalid',
                     'a climbing or absolute path, another bucket or another mode is invalid');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'download') = 'not_found', 'a file still pending cannot be downloaded');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'meeting-files', (select p from t_p), 'upload') = 'not_found', 'the path belongs to its own bucket');
-- an object already there is not overwritten
insert into storage.objects (bucket_id, name, owner_id, metadata) select 'record-files', p, null, '{"mimetype": "application/pdf", "size": 1200}' from t_p;
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'upload') = 'exists', 'an upload that landed is not signed again');
-- a pending row past its five minutes
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_old as select public.file_upload_begin('deal', (select id from t_rec), 'Gammel.txt', 'text/plain', 10) r;
update app.record_files set created_at = now() - interval '6 minutes' where id = (select (r ->> 'id')::uuid from t_old);
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select r ->> 'path' from t_old), 'upload') = 'expired', 'a pending upload older than its five minutes is not signed');
-- a download follows a read the database allowed and recorded
select public.file_upload_done((select id from t_p));
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'download') = 'not_allowed', 'a download without a read just now is refused');
select pg_temp.check((public.file_download_url((select id from t_p)) ->> 'path') = (select p from t_p), 'the viewer asks the database for the file');
select pg_temp.as_nobody();
select pg_temp.check((select public.worker_storage_check('tor@orgpuls.no', (select tor from t_s), 'record-files', p, 'download') from t_p)
                     @> '{"allowed": true, "filename": "Avtale.pdf", "mime": "application/pdf"}', 'after the audited read the download is signed');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'upload') = 'not_found', 'a ready file is not uploaded again');
select pg_temp.check(pg_temp.chk('emma@orgpuls.no', (select emma from t_s), 'record-files', (select p from t_p), 'download') = 'not_allowed', 'another staff member''s read does not sign for you');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_gone as select public.file_upload_begin('deal', (select id from t_rec), 'Borte.txt', 'text/plain', 10) r;
select public.file_upload_done((select (r ->> 'id')::uuid from t_gone));
select public.file_download_url((select (r ->> 'id')::uuid from t_gone));
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select r ->> 'path' from t_gone), 'download') = 'missing', 'a file whose object never landed is not signed');
select public.file_delete((select id from t_p));
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'record-files', (select p from t_p), 'download') = 'not_found', 'a removed file is not signed');

-- ---------------------------------------------------------------------------
-- meeting files: the uploader's pending transcript only; the original is never downloaded
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_mu as select public.meeting_transcript_upload_begin(null, 'Samtale.vtt', 'text/vtt', 4096) r;
select pg_temp.as_nobody();
select pg_temp.check((select public.worker_storage_check('ingrid@orgpuls.no', (select ingrid from t_s), 'meeting-files', r ->> 'path', 'upload') from t_mu)
                     @> '{"allowed": true, "mime": "text/vtt", "size": 4096}', 'the uploader may upload the transcript they started');
select pg_temp.check(pg_temp.chk('emma@orgpuls.no', (select emma from t_s), 'meeting-files', (select r ->> 'path' from t_mu), 'upload') = 'not_found', 'nobody else may');
select pg_temp.check(pg_temp.chk('ingrid@orgpuls.no', (select ingrid from t_s), 'meeting-files', (select r ->> 'path' from t_mu), 'download') = 'not_allowed', 'a transcript original is never downloaded');
update app.meeting_uploads set created_at = now() - interval '11 minutes' where id = (select (r ->> 'id')::uuid from t_mu);
select pg_temp.check(pg_temp.chk('ingrid@orgpuls.no', (select ingrid from t_s), 'meeting-files', (select r ->> 'path' from t_mu), 'upload') = 'expired', 'past its ten minutes it is not signed');

-- ---------------------------------------------------------------------------
-- privacy packages: the worker writes them; a security holder downloads after the audited read, while the link lives
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_job as select (public.privacy_export(jsonb_build_object('people', jsonb_build_array((select id from app.people where deleted_at is null order by created_at limit 1))))
                                   ->> 'job')::uuid id;
select pg_temp.as_nobody();
select public.worker_privacy_package((select id from t_job)) is not null;
select public.worker_privacy_done((select id from t_job), 'privacy/' || (select id from t_job) || '/package.json');
create temp table t_pp as select 'privacy/' || id || '/package.json' p, id from t_job;
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'privacy-exports', (select p from t_pp), 'upload') = 'not_allowed', 'nothing is uploaded into the privacy bucket from outside');
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'privacy-exports', (select p from t_pp), 'download') = 'not_allowed', 'a package download needs the read just now');
select pg_temp.as_staff('tor@orgpuls.no');
select public.privacy_export_url((select id from t_job));
select pg_temp.as_nobody();
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'privacy-exports', (select p from t_pp), 'download') = 'missing', 'a package the worker did not store is not signed');
insert into storage.objects (bucket_id, name, metadata) select 'privacy-exports', p, '{"mimetype": "application/json", "size": 10}' from t_pp;
select pg_temp.check((select public.worker_storage_check('tor@orgpuls.no', (select tor from t_s), 'privacy-exports', p, 'download') from t_pp)
                     @> '{"allowed": true, "filename": "package.json"}', 'after the audited read the package is signed');
select pg_temp.check(pg_temp.chk('ola@orgpuls.no', (select ola from t_s), 'privacy-exports', (select p from t_pp), 'download') = 'not_allowed', 'without global:security, no package');
update app.privacy_jobs set url_expires_at = now() - interval '1 second' where id = (select id from t_job);
select pg_temp.check(pg_temp.chk('tor@orgpuls.no', (select tor from t_s), 'privacy-exports', (select p from t_pp), 'download') = 'expired', 'past its 24 hours the package is not signed');

-- ---------------------------------------------------------------------------
-- 0054: the jobs-run function's one question. The caller's own landed upload, or an export they asked for with
-- global:security; one run at a time (a claim lives five minutes), a finished job answers «done», three attempts at most
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_jobs_claim(text, uuid, text, uuid, int)', 'execute')
                     and not has_function_privilege('anon', 'public.worker_jobs_claim(text, uuid, text, uuid, int)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_jobs_claim(text, uuid, text, uuid, int)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_upload_failed(uuid, text)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_upload_failed(uuid, text)', 'execute')
                     and not has_function_privilege('authenticated', 'app.worker_caller(text, uuid)', 'execute')
                     and not has_function_privilege('authenticated', 'app.jobs_upload_fail(uuid, text)', 'execute'),
                     '0054: only the service role may claim a job or fail an upload');
select pg_temp.check((select bool_and(p.prosecdef and 'search_path=""' = any (p.proconfig) and p.provolatile = 'v') from pg_proc p
                      where p.oid in ('public.worker_jobs_claim(text, uuid, text, uuid, int)'::regprocedure, 'public.worker_upload_failed(uuid, text)'::regprocedure,
                                      'app.jobs_upload_fail(uuid, text)'::regprocedure)),
                     '0054: the writing functions are volatile security definers with an empty search_path');
create function pg_temp.claim(p_email text, p_session uuid, p_kind text, p_id uuid, p_more int default 0) returns jsonb language sql as $$
  select public.worker_jobs_claim(p_email, p_session, p_kind, p_id, p_more)
$$;
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'recap', gen_random_uuid()) ->> 'reason' = 'invalid'
                     and pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', null) ->> 'reason' = 'invalid', '0054: an unknown kind or no id is invalid');

select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_j1 as select public.meeting_transcript_upload_begin(null, 'Jobb.vtt', 'text/vtt', 120) r;
create temp table t_j1d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j1)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j1) u;
select pg_temp.as_nobody();
select pg_temp.check(pg_temp.claim('emma@orgpuls.no', (select emma from t_s), 'transcript', (select t from t_j1d)) ->> 'reason' = 'not_found', '0054: nobody but the uploader runs their transcript');
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select tor from t_s), 'transcript', (select t from t_j1d)) ->> 'reason' = 'not_allowed'
                     and pg_temp.claim('tor@orgpuls.no', (select tor1 from t_s), 'transcript', (select t from t_j1d)) ->> 'reason' = 'not_allowed'
                     and pg_temp.claim('ingrid@orgpuls.no', gen_random_uuid(), 'transcript', (select t from t_j1d)) ->> 'reason' = 'not_allowed',
                     '0054: someone else''s session, a first factor only or an unknown session claims nothing');
create temp table t_c1 as select pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j1d)) r;
select pg_temp.check((select (r ->> 'allowed')::boolean and jsonb_array_length(r -> 'jobs') = 1
                             and r -> 'jobs' -> 0 @> jsonb_build_object('kind', 'transcript', 'own', true, 'upload_id', (select u from t_j1d), 'transcript_id', (select t from t_j1d),
                                                                        'bucket', 'meeting-files', 'mime', 'text/vtt', 'size', 120, 'stored', false)
                             and r -> 'jobs' -> 0 ->> 'path' = (select r ->> 'path' from t_j1) from t_c1),
                     '0054: the uploader claims their landed upload: where it is and what it claims to be');
select pg_temp.check((select claimed_at = now() and attempts = 1 from app.meeting_uploads where id = (select u from t_j1d)), '0054: the claim is stamped and counted');
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j1d)) @> '{"allowed": false, "reason": "busy", "state": "processing"}',
                     '0054: a job already running is not run twice');
update app.meeting_uploads set claimed_at = now() - interval '6 minutes' where id = (select u from t_j1d);
select pg_temp.check((pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j1d)) ->> 'allowed')::boolean, '0054: a claim past its five minutes may be taken again');
select pg_temp.check((select attempts = 2 and claimed_at = now() from app.meeting_uploads where id = (select u from t_j1d)), '0054: and it counts as a second attempt');
select public.worker_upload_parsed((select u from t_j1d), '[{"start_ms": 0, "end_ms": 1500, "speaker": "Ingrid", "text": "Hei."}]');
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j1d)) @> '{"allowed": false, "reason": "done", "state": "ready"}',
                     '0054: a parsed transcript answers done');

-- the reader's error path: a reason code, never the text
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_j2 as select public.meeting_transcript_upload_begin(null, 'Tom.txt', 'text/plain', 3) r;
create temp table t_j2d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j2)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j2) u;
select pg_temp.as_nobody();
select pg_temp.expect_detail(format($$select public.worker_upload_failed(%L, 'Hei, dette er teksten')$$, (select u from t_j2d)), 'invalid', 'reason', '0054: a failure carries a code, not words');
select pg_temp.check(public.worker_upload_failed((select u from t_j2d), 'no_segments') = '{"ok": true, "state": "failed"}', '0054: the reader reports a failure by code');
select pg_temp.check((select state = 'failed' and error_code = 'no_segments' from app.meeting_transcripts where id = (select t from t_j2d))
                     and (select state = 'failed' and parsed_at is not null from app.meeting_uploads where id = (select u from t_j2d))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message -> 'paths' ? (select r ->> 'path' from t_j2)),
                     '0054: an unreadable file fails its transcript with the reason and its original is forgotten');
select pg_temp.check(exists (select 1 from app.notifications n where n.key = 'meeting.transcript_failed' and n.record_id = (select meeting_id from app.meeting_transcripts where id = (select t from t_j2d))),
                     '0054: the owner is told');
select pg_temp.expect_detail(format($$select public.worker_upload_failed(%L, 'no_segments')$$, (select u from t_j2d)), 'invalid', 'state', '0054: an upload fails once');
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j2d)) @> '{"reason": "done", "state": "failed"}', '0054: and then answers done');

-- three attempts, then it is failed rather than tried forever
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_j3 as select public.meeting_transcript_upload_begin(null, 'Tung.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 900) r;
create temp table t_j3d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j3)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j3) u;
select pg_temp.as_nobody();
update app.meeting_uploads set attempts = 3, claimed_at = now() - interval '6 minutes' where id = (select u from t_j3d);
select pg_temp.check(pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j3d)) @> '{"reason": "done", "state": "failed"}', '0054: a fourth claim answers done');
select pg_temp.check((select error_code = 'too_many_attempts' from app.meeting_transcripts where id = (select t from t_j3d)),
                     '0054: a file claimed three times without finishing fails with too_many_attempts');

-- other landed uploads nobody ran come along, claimed the same way; a fresh one is left to its own caller
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_j4 as select public.meeting_transcript_upload_begin(null, 'Glemt.srt', 'application/x-subrip', 50) r;
create temp table t_j4d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j4)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j4) u;
create temp table t_j6 as select public.meeting_transcript_upload_begin(null, 'Fersk.srt', 'application/x-subrip', 50) r;
create temp table t_j6d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j6)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j6) u;
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_j5 as select public.meeting_transcript_upload_begin(null, 'Ny.vtt', 'text/vtt', 50) r;
create temp table t_j5d as select (public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_j5)) ->> 'transcript_id')::uuid t, (select (r ->> 'id')::uuid from t_j5) u;
select pg_temp.as_nobody();
update app.meeting_uploads set created_at = now() - interval '3 minutes' where id = (select u from t_j4d);
create temp table t_c5 as select pg_temp.claim('ingrid@orgpuls.no', (select ingrid from t_s), 'transcript', (select t from t_j5d), 5) r;
select pg_temp.check((select r -> 'jobs' -> 0 ->> 'upload_id' = (select u::text from t_j5d) and (r -> 'jobs' -> 0 ->> 'own')::boolean
                             and exists (select 1 from jsonb_array_elements(r -> 'jobs') x where x ->> 'upload_id' = (select u::text from t_j4d) and not (x ->> 'own')::boolean)
                             and not exists (select 1 from jsonb_array_elements(r -> 'jobs') x where x ->> 'upload_id' = (select u::text from t_j6d))
                             and jsonb_array_length(r -> 'jobs') <= 6 from t_c5),
                     '0054: an orphaned upload comes along with the caller''s own (at most five); one landed just now is left to its caller');
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'transcript', (select t from t_j4d)) ->> 'reason' = 'busy', '0054: an upload taken along is claimed like any other');
select pg_temp.check((pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'transcript', (select t from t_j6d)) ->> 'allowed')::boolean, '0054: the fresh one is still its uploader''s to run');

-- privacy: an export the caller asked for, with global:security
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_pj as select (public.privacy_export(jsonb_build_object('people', jsonb_build_array((select id from app.people where deleted_at is null order by created_at limit 1))))
                                  ->> 'job')::uuid id;
select pg_temp.as_nobody();
select pg_temp.check(pg_temp.claim('ola@orgpuls.no', (select ola from t_s), 'privacy', (select id from t_pj)) ->> 'reason' = 'not_allowed', '0054: without global:security, no package is run');
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', gen_random_uuid()) ->> 'reason' = 'not_found', '0054: an unknown job is not found');
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select t from t_j5d)) ->> 'reason' = 'not_found', '0054: a transcript id is not a privacy job');
create temp table t_pc as select pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select id from t_pj)) r;
select pg_temp.check((select (r ->> 'allowed')::boolean and r ->> 'state' = 'approved'
                             and r -> 'jobs' -> 0 = jsonb_build_object('kind', 'privacy', 'own', true, 'job_id', (select id from t_pj), 'bucket', 'privacy-exports') from t_pc),
                     '0054: the requester claims their export');
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select id from t_pj)) ->> 'reason' = 'busy', '0054: an export being built is not built twice');
select public.worker_privacy_package((select id from t_pj)) is not null;
select public.worker_privacy_done((select id from t_pj), 'privacy/' || (select id from t_pj) || '/access-package.zip');
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select id from t_pj)) @> '{"reason": "done", "state": "done"}', '0054: a written package answers done');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_pj2 as select (public.privacy_export(jsonb_build_object('people', jsonb_build_array((select id from app.people where deleted_at is null order by created_at limit 1))))
                                   ->> 'job')::uuid id;
select pg_temp.as_nobody();
update app.privacy_jobs set created_by = (select id from app.admins where email = 'hanna@orgpuls.no') where id = (select id from t_pj2);
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select id from t_pj2)) ->> 'reason' = 'not_allowed',
                     '0054: a security holder runs only an export they asked for or approved');
update app.privacy_jobs set created_by = (select id from app.admins where email = 'tor@orgpuls.no'), attempts = 3 where id = (select id from t_pj2);
select pg_temp.check(pg_temp.claim('tor@orgpuls.no', (select tor from t_s), 'privacy', (select id from t_pj2)) @> '{"reason": "done", "state": "failed"}', '0054: a fourth export claim answers done');
select pg_temp.check((select state = 'failed' and error = 'too_many_attempts' and finished_at is not null from app.privacy_jobs where id = (select id from t_pj2)),
                     '0054: an export tried three times fails');

rollback;
