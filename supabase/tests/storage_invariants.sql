-- storage_invariants.sql — the private buckets and the signer's question (0052; R-PROJECTS-01, R-MOBILE-04, R-MEETINGS-06,
-- R-SECURITY-03; CRM-05: no file without the record).
\ir _helpers.psql
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

rollback;
