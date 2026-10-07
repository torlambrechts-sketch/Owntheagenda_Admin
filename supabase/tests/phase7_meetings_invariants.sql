-- phase7_meetings_invariants.sql — Meetings and the AI gateway (0042; MTG-01..08, UF-07, SF-21, SF-24, SEC-11, §8.3 consent).
\ir _helpers.psql
begin;

-- the roles this suite was written for (0057 folded Projects into Sales): emma keeps the Projects set, which still exists
update app.admins set permission_set_id = (select id from app.permission_sets where key = 'project') where email = 'emma@orgpuls.no';

-- expect_detail(sql, message, detail): the statement must raise with this message and this detail
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

-- a calendar event as the adapter sends it
create or replace function pg_temp.ev(p_id text, p_start timestamptz, p_emails text[], p_url text default 'https://meet.google.com/abc-defg-hij') returns jsonb language sql as $$
  select jsonb_build_object('external_event_id', p_id, 'title', 'Møte ' || p_id, 'starts_at', p_start, 'ends_at', p_start + interval '30 minutes', 'join_url', p_url,
                            'attendees', (select jsonb_agg(jsonb_build_object('email', e, 'name', initcap(split_part(e, '@', 1)))) from unnest(p_emails) e))
$$;

-- the notices go out, the bot is sent and admitted; → the call's opt-out token
create or replace function pg_temp.admit(p_meeting uuid) returns text language plpgsql as $$
declare a jsonb;
begin
  for a in select value from jsonb_array_elements(public.worker_notice_claim(p_meeting) -> 'attendees') loop
    perform public.worker_notice_result(p_meeting, a ->> 'email', true);
  end loop;
  perform app.mtg_bots_due();
  return public.worker_bot_state(p_meeting, 'in_call') ->> 'opt_out_token';
end $$;

-- ---------------------------------------------------------------------------
-- structure: closed tables, client functions for signed-in staff, workers for the service role, helpers for nobody
create temp table t_tables as select unnest(array['ai_calls', 'meetings', 'meeting_attendees', 'recording_opt_outs', 'meeting_recordings', 'meeting_transcripts',
  'transcript_speakers', 'transcript_segments', 'meeting_briefs', 'meeting_brief_checks', 'meeting_recaps', 'meeting_suggestions', 'meeting_user_settings',
  'meeting_uploads']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 14, 'all fourteen meeting and AI tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no meeting table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 14, 'no client grant on a meeting table; the service role has them');
create temp table t_rpcs as select unnest(array['public.meetings_workspace(jsonb)', 'public.meeting_detail(uuid)', 'public.meeting_brief(uuid)',
  'public.meeting_transcript(uuid, int, int)', 'public.meeting_recap(uuid)', 'public.meeting_suggestions(uuid)', 'public.meeting_controls()', 'public.meeting_my_settings()',
  'public.meeting_link(uuid, jsonb, int)', 'public.meeting_capture_set(uuid, text)', 'public.meeting_bot_remove(uuid)', 'public.meeting_recording_delete(uuid, boolean)',
  'public.meeting_brief_check(uuid, text, boolean)', 'public.meeting_brief_regenerate(uuid)', 'public.meeting_transcript_upload_begin(uuid, text, text, bigint)',
  'public.meeting_transcript_upload_done(uuid)', 'public.meeting_transcript_retry(uuid)', 'public.meeting_speaker_map(uuid, text, jsonb)',
  'public.meeting_recap_regenerate(uuid)', 'public.meeting_recap_save_note(uuid, text, uuid)', 'public.meeting_next_step_activity(uuid, int, jsonb)',
  'public.meeting_suggestion_decide(uuid[], text)', 'public.meeting_user_set(uuid, jsonb)', 'public.meeting_my_settings_set(jsonb)',
  'public.meeting_opt_out_staff(uuid, text, boolean)', 'public.thread_insight_request(uuid)']) f;
select pg_temp.check(not exists (select 1 from t_rpcs where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')),
                     'every meeting function is for signed-in staff (' || (select count(*) from t_rpcs) || '), never anon');
select pg_temp.check(not exists (select 1 from t_rpcs r join pg_proc p on p.oid = r.f::regprocedure where not p.prosecdef or not ('search_path=""' = any (p.proconfig))),
                     'every meeting function is security definer with an empty search path');
select pg_temp.check(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')
                     and has_function_privilege('service_role', f, 'execute'), 'service role only: ' || f)
from unnest(array['public.meeting_opt_out(text, boolean)', 'public.worker_meeting_upsert(uuid, jsonb)', 'public.worker_notice_claim(uuid)',
  'public.worker_notice_result(uuid, text, boolean)', 'public.worker_bot_state(uuid, text, text)', 'public.worker_recording_ready(uuid, jsonb)',
  'public.worker_transcript_ready(uuid, jsonb, jsonb, text)', 'public.worker_upload_parsed(uuid, jsonb)', 'public.worker_brief_quotes_ready(uuid, jsonb)',
  'public.worker_recap_ready(uuid, jsonb, jsonb)', 'public.worker_meeting_ai_context(jsonb)', 'public.worker_ai_call(jsonb)',
  'public.worker_project_summary_ready(uuid, jsonb)']) f;
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'app'::regnamespace
                                 and (p.proname like 'mtg\_%' or p.proname in ('ai_call_fixed', 'ai_call_ok', 'recording_opt_out_fixed', 'transcript_segment_fixed',
                                                                               'meeting_link_purged', 'person_erased_meetings'))
                                 and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
                     'no app helper of 0042 is callable by a client role');
select pg_temp.check(not exists (select 1 from app.entities where key = 'meeting'), 'a meeting is not a record type: no rec_get, search or export path around the switch (Q19)');
select pg_temp.check(app.entity_route('meeting') = '/meetings' and app.entity_route('project') = '/projects' and app.entity_route('deal') = '/deals',
                     'the route register knows meetings and keeps the routes it had');
select pg_temp.check((select array_agg(provider order by provider) from app.integration_connections where provider in ('ai', 'meeting_bot', 'transcription', 'email'))
                     = array['ai', 'email', 'meeting_bot', 'transcription'] and not exists (select 1 from app.integration_connections where provider = 'llm'),
                     'the bot and transcription are providers beside «ai» (no «llm» row, V-P6P-03)');
select pg_temp.check(not exists (select 1 from app.integration_connections where provider in ('ai', 'meeting_bot', 'transcription', 'email') and status = 'connected'),
                     'nothing is connected');
select pg_temp.check((select default_value = '12_months' and options = array['12_months', 'custom', 'keep'] and numeric_option = 'custom' and not fixed
                      from app.settings_registry where key = 'rec_retention'), 'rec_retention is registered: 12 months, custom months, or keep');
select pg_temp.check((select applies_to like 'MTG-02, MTG-03, MTG-07, MTG-08%' from app.settings_registry where key = 'rec_notice'), 'rec_notice reaches MTG-03 and MTG-07');
select pg_temp.check(pg_get_constraintdef((select oid from pg_constraint where conname = 'changelog_source_check')) like '%''meeting''%', 'the history accepts the source «meeting»');
select pg_temp.check(exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'project_ai_summaries' and column_name = 'ai_call_id'),
                     'a project summary names its AI call');

-- the firewall (D-19, D-34): no meeting or AI function reads a product table other than the count mirrors and the
-- member's last sign-in
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace in ('app'::regnamespace, 'public'::regnamespace)
                                 and (p.proname like 'mtg\_%' or p.proname like 'meeting%' or p.proname like 'worker\_meeting%' or p.proname in ('worker_ai_call', 'ai_call_ok'))
                                 and p.prosrc ~ '\mapp\.(events_in|product_survey_rounds|usage_daily|product_logins_daily|installations|subscriptions|mrr_\w+|health_scores|activation_milestones|support_access_grants|product_counts|v_activated_orgs|plan_versions)\M'),
                     'no meeting or AI function references a product table beyond the count mirrors');

-- ---------------------------------------------------------------------------
-- fixture: an organisation, a person, an open deal (Ingrid's), a second deal, a lead, a label; a calendar for Tor
select pg_temp.as_nobody();
create temp table t_ids as select gen_random_uuid() org, gen_random_uuid() kari, gen_random_uuid() deal, gen_random_uuid() deal2, gen_random_uuid() deal3,
  gen_random_uuid() lead, gen_random_uuid() lbl,
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid,
  (select id from app.admins where email = 'ola@orgpuls.no') ola, (select id from app.admins where email = 'emma@orgpuls.no') emma;
insert into app.organizations (id, name, owner_id, employees) select org, 'Kystlinje Transport P7', ingrid, 180 from t_ids;
insert into app.people (id, name, email, title, organization_id, owner_id) select kari, 'Kari Kystlinje', 'kari@kyst.example', 'Leder', org, ingrid from t_ids;
insert into app.deals (id, title, value, currency, pipeline_id, stage_id, person_id, organization_id, owner_id, visibility)
select x.id, x.title, 120000, 'NOK', p.id, (select s.id from app.stages s where s.pipeline_id = p.id order by s.ord limit 1), x.person, x.org, i.ingrid, 'all'
from t_ids i cross join app.pipelines p cross join lateral (values (i.deal, 'Kystlinje — Skiftly P7', i.kari, i.org), (i.deal2, 'Annen avtale P7', null::uuid, null::uuid),
                                                                 (i.deal3, 'Kortvarig P7', null::uuid, null::uuid)) x(id, title, person, org)
where p.name = 'New business';
insert into app.leads (id, title, person_id, organization_id, owner_id) select lead, 'Kystlinje lead P7', kari, org, ingrid from t_ids;
insert into app.labels (id, entity, name, bg, ink) select lbl, 'deal', 'Multi-product P7', '#CFE7E4', '#20431C' from t_ids;

-- ---------------------------------------------------------------------------
-- rights (MTG-08, SEC-07): deals:see, the module, the per-user switch; Workspace and controls for global:configure
select pg_temp.as_staff('emma@orgpuls.no');
select pg_temp.expect_detail($$select public.meetings_workspace()$$, 'forbidden', 'deals:see', 'a projects-only user has no meeting workspace');
select pg_temp.check(not (public.shell() ->> 'meetings_workspace')::boolean, 'and the shell hides «Meetings» from them (R-MEETINGS-02)');
select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.meetings_workspace()$$, 'not_signed_in', 'nobody signed in reads nothing');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(jsonb_typeof(public.meetings_workspace() -> 'upcoming') = 'array'
                     and public.meetings_workspace() -> 'capabilities' = jsonb_build_object('calendar', 'not_connected', 'meeting_bot', 'not_connected', 'transcription', 'not_connected',
                                                                                         'ai', 'not_connected', 'email', 'not_connected', 'slack', 'not_connected', 'desktop', 'not_available'),
                     'a sales user opens the workspace; every provider reads not connected, the desktop app not available');
select pg_temp.expect_detail($$select public.meeting_controls()$$, 'forbidden', 'global:configure', 'Workspace and controls need global:configure');
select pg_temp.expect_detail(format($$select public.meeting_user_set(%L, '{"enabled":false}')$$, (select tor from t_ids)), 'forbidden', 'global:configure', 'and so does another user''s switch');
select pg_temp.expect_detail($$select public.meeting_my_settings_set('{"enabled":false}')$$, 'invalid', 'enabled', 'nobody switches their own workspace');
select public.meeting_my_settings_set('{"bot_auto_join":"all","brief_instructions":"Kort og konkret"}');
select pg_temp.check((select bot_auto_join = 'all' and brief_instructions = 'Kort og konkret' from app.meeting_user_settings where staff_id = (select ingrid from t_ids)),
                     'a user keeps their own auto-join choice and brief instructions');
select pg_temp.as_staff('tor@orgpuls.no');
select public.meeting_user_set((select ingrid from t_ids), '{"enabled":false}');
select pg_temp.check((select detail -> 'fields' ? 'enabled' from app.audit where action = 'meeting_user.changed' order by id desc limit 1), 'the switch is audited by field name');
select pg_temp.check(jsonb_path_exists(public.meeting_controls(), '$.users[*] ? (@.name == "Ingrid Solberg" && @.enabled == false)')
                     and not jsonb_path_exists(public.meeting_controls(), '$.users[*] ? (@.name == "Emma Lie")'),
                     'the controls list staff with deals:see and their switch');
select pg_temp.check(public.meeting_controls() ? 'controller' and public.meeting_controls() -> 'controller' = 'null'::jsonb,
                     'without a verified transactional sender the controls name no controller (R-MEETINGS-01)');
select pg_temp.check((public.shell() ->> 'meetings_workspace')::boolean, 'the shell offers «Meetings» to a user with the workspace (R-MEETINGS-02)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.meetings_workspace()$$, 'forbidden', 'meetings:disabled', 'a user switched off sees no workspace (MTG-08 A)');
select pg_temp.check(not (public.shell() ->> 'meetings_workspace')::boolean, 'and the shell hides «Meetings» from them (R-MEETINGS-02)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.meeting_user_set((select ingrid from t_ids), '{"enabled":true}');
select pg_temp.expect_detail(format($$select public.meeting_user_set(%L, jsonb_build_object('mailbox_id', gen_random_uuid()))$$, (select ingrid from t_ids)), 'invalid', 'mailbox_id',
                             'a mailbox must be one the user may use');
select public.module_set('meetings', false);
select pg_temp.expect_error($$select public.meetings_workspace()$$, 'module_off', 'the module switch turns the workspace off');
select pg_temp.check(not (public.shell() ->> 'meetings_workspace')::boolean, 'with the module off the shell hides «Meetings» (R-MEETINGS-02)');
select public.module_set('meetings', true);

-- ---------------------------------------------------------------------------
-- the calendar (SF-21.1): only from a connected calendar; kept with a link or an external guest; linked by attendee
select pg_temp.as_nobody();
select pg_temp.expect_detail(format($$select public.worker_meeting_upsert(%L, %L)$$, (select tor from t_ids), pg_temp.ev('ev0', now() + interval '2 days', array['kari@kyst.example'])),
                             'not_connected', 'calendar', 'no calendar, no meetings');
insert into app.calendar_connections (staff_id, provider, account_email, status) select tor, 'google', 'tor@orgpuls.no', 'connected' from t_ids;
select pg_temp.check(public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('ev0', now() + interval '2 days', array['tor@orgpuls.no', 'ingrid@orgpuls.no'], null)) ->> 'skipped' = 'not_relevant',
                     'an internal event without a link is not a meeting');
create temp table t_m (k text primary key, id uuid);
insert into t_m select 'A', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evA', now() + interval '2 days', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
select pg_temp.check((select capture = 'none' and bot_state = 'none' and notice_state = 'not_required' and visibility = 'owner' and owner_id = (select tor from t_ids)
                             and conference = 'meet' and deal_id = (select deal from t_ids) and person_id = (select kari from t_ids) and organization_id = (select org from t_ids)
                      from app.meetings where id = (select id from t_m where k = 'A')),
                     'without a bot provider nothing records; the meeting is the owner''s (Q13), on Meet, linked to the guest''s open deal, person and organisation');
select pg_temp.check((select count(*) = 2 and bool_and(external = (email = 'kari@kyst.example')) and bool_or(person_id = (select kari from t_ids))
                      from app.meeting_attendees where meeting_id = (select id from t_m where k = 'A')), 'attendees are matched to staff and people by address');
select pg_temp.check(exists (select 1 from app.events where kind = 'meeting.scheduled' and subject_id = (select id from t_m where k = 'A')
                             and payload ->> 'deal' = (select deal::text from t_ids) and not payload ? 'title'), 'meeting.scheduled carries ids, never the title');

update app.integration_connections set status = 'connected' where provider = 'meeting_bot';
insert into t_m select 'B', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evB', now() + interval '3 minutes', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
select pg_temp.check((select capture = 'bot' and notice_state = 'pending' and notice_due_at = starts_at - interval '24 hours' and bot_state = 'scheduled'
                      from app.meetings where id = (select id from t_m where k = 'B')),
                     'with the bot provider a meeting with external guests gets the notetaker, a notice due 24 h before, and a scheduled bot');
insert into t_m select 'I', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evI', now() + interval '2 days', array['tor@orgpuls.no', 'ingrid@orgpuls.no'])) ->> 'id')::uuid;
select pg_temp.check((select capture = 'none' and notice_state = 'not_required' from app.meetings where id = (select id from t_m where k = 'I')),
                     'an internal meeting is not recorded by default (auto-join «external», arbeidsmiljøloven ch. 9)');

-- visibility: owner, or an invited staff member
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error(format($$select public.meeting_detail(%L)$$, (select id from t_m where k = 'A')), 'not_found', 'another user''s meeting is not found');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(public.meeting_detail((select id from t_m where k = 'I')) ->> 'id' = (select id::text from t_m where k = 'I'), 'an invited staff member sees the meeting');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select d ->> 'default_tab' = 'brief' and d -> 'state' ->> 'key' = 'notice_due' and d -> 'link' ->> 'entity' = 'deal' and d -> 'attendees' ->> 'first' = 'Kari Kystlinje'
                      from (select public.meeting_detail((select id from t_m where k = 'B')) d) x),
                     'the header: «Notice due», linked to the deal, the external guest first; an upcoming meeting opens on its brief');

-- ---------------------------------------------------------------------------
-- consent (§8.3, D-39): no notice, no bot — fail closed
select pg_temp.as_nobody();
select pg_temp.check((app.mtg_notices_due() ->> 'blocked')::int >= 1, 'a due notice without an email provider is blocked');
select pg_temp.check((select notice_state = 'blocked' and bot_state = 'blocked' and bot_block_reason = 'notice_not_sent' from app.meetings where id = (select id from t_m where k = 'B')),
                     'and the bot is blocked: «notice_not_sent»');
select pg_temp.check(exists (select 1 from app.notifications where key = 'meeting.notice_blocked' and route = '/meetings?meeting=' || (select id from t_m where k = 'B')),
                     'the owner is told the notice could not go out');
create temp table t_refB as select public.worker_recording_ready((select id from t_m where k = 'B'), jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'B') || '/x.webm')) r;
select pg_temp.check((select r ->> 'refused' from t_refB) = 'notice_not_sent'
                     and not exists (select 1 from app.meeting_recordings where meeting_id = (select id from t_m where k = 'B'))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message ->> 'bucket' = 'meeting-files'
                                 and message -> 'paths' ? ('recording/' || (select id from t_m where k = 'B') || '/x.webm')),
                     'a recording the rules do not allow is refused, not stored, and its file is queued for deletion');

update app.integration_connections set status = 'connected' where provider = 'email';
select pg_temp.check(app.mtg_controller() is null, 'no transactional sender: no controller to name');
insert into app.sender_domains (domain, stream, from_name, from_local, verified_at) values ('varsel.p7.example', 'transactional', 'Owntheagenda P7 AS', 'noreply', now());
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(public.meeting_controls() ->> 'controller' = 'Owntheagenda P7 AS', 'the controls name the controller a notice speaks for (R-MEETINGS-01)');
select pg_temp.as_nobody();
insert into t_m select 'C', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evC', now() + interval '4 minutes', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
create temp table t_nd as select app.mtg_notices_due() r;
select pg_temp.check((select (r ->> 'queued')::int from t_nd) = 1 and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_notices' and message ->> 'meeting_id' = (select id::text from t_m where k = 'C')),
                     'a due notice goes to the mailer as a job with the meeting id only');
select pg_temp.check((select notice_state = 'blocked' from app.meetings where id = (select id from t_m where k = 'B')), 'a blocked notice stays blocked');
create temp table t_claim as select public.worker_notice_claim((select id from t_m where k = 'C')) c;
select pg_temp.check((select jsonb_array_length(c -> 'attendees') = 1 and c -> 'attendees' -> 0 ->> 'email' = 'kari@kyst.example' and char_length(c -> 'attendees' -> 0 ->> 'token') >= 40
                             and c ->> 'controller' = 'Owntheagenda P7 AS' and (c ->> 'retention_months')::int = 12 and c ->> 'bot_name_suffix' = '(recording)' from t_claim)
                     and (select opt_out_token_sha256 = app.token_hash((select c -> 'attendees' -> 0 ->> 'token' from t_claim)) from app.meeting_attendees
                          where meeting_id = (select id from t_m where k = 'C') and email = 'kari@kyst.example'),
                     'the claim gives each external guest a fresh opt-out token (only its hash is kept) and what art. 13 needs: controller, retention');
create temp table t_nr as select public.worker_notice_result((select id from t_m where k = 'C'), 'kari@kyst.example', true) r;
select pg_temp.check((select r ->> 'notice_state' from t_nr) = 'sent'
                     and exists (select 1 from app.events where kind = 'meeting.notice_sent' and subject_id = (select id from t_m where k = 'C') and payload = '{"count":1}'),
                     'once every external guest is told, the notice is sent (meeting.notice_sent, a count)');
create temp table t_bd as select app.mtg_bots_due() r;
select pg_temp.check((select (r ->> 'joining')::int from t_bd) = 1 and (select bot_state = 'joining' from app.meetings where id = (select id from t_m where k = 'C'))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_bot_join' and message ->> 'meeting_id' = (select id::text from t_m where k = 'C')
                                 and message ->> 'display_name_suffix' = '(recording)'),
                     'with the notice out the bot is sent, its name saying it records');
create temp table t_call as select public.worker_bot_state((select id from t_m where k = 'C'), 'in_call') r;
select pg_temp.check((select (r ->> 'leave')::boolean = false and char_length(r ->> 'opt_out_token') >= 40 from t_call)
                     and (select call_opt_out_sha256 = app.token_hash((select r ->> 'opt_out_token' from t_call)) from app.meetings where id = (select id from t_m where k = 'C')),
                     'in the call the bot gets its opt-out link for the chat line, once');
create temp table t_rec as select public.worker_recording_ready((select id from t_m where k = 'C'),
  jsonb_build_object('method', 'bot', 'provider', 'vendor', 'storage_path', 'recording/' || (select id from t_m where k = 'C') || '/a.webm', 'duration_s', 1680)) r;
select pg_temp.check((select (r ->> 'ok')::boolean and r ->> 'transcript_id' is null from t_rec)
                     and (select state = 'ready' and purge_after between now() + interval '11 months' and now() + interval '13 months' from app.meeting_recordings where id = (select (r ->> 'recording_id')::uuid from t_rec)),
                     'an admitted recording is kept 12 months (rec_retention); without transcription it stays unprocessed');
select pg_temp.check(exists (select 1 from app.events where kind = 'meeting.recorded' and subject_id = (select id from t_m where k = 'C') and payload ->> 'duration_s' = '1680'),
                     'meeting.recorded carries the duration');
select public.worker_bot_state((select id from t_m where k = 'C'), 'left');
select pg_temp.check((public.worker_recording_ready((select id from t_m where k = 'C'), jsonb_build_object('method', 'desktop', 'storage_path', 'recording/' || (select id from t_m where k = 'C') || '/d.m4a')) ->> 'refused') = 'not_confirmed',
                     'a desktop recording needs the user''s confirmation that participants were told (MTG-03)');
select pg_temp.expect_detail(format($$select public.worker_recording_ready(%L, '{"method":"bot","storage_path":"recording/other/a.webm"}')$$, (select id from t_m where k = 'C')),
                             'invalid', 'storage_path', 'a recording lives under its own meeting''s path');

-- rec_notice: its effect on the plan
insert into t_m select 'D', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evD', now() + interval '3 days', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('rec_notice', 'custom', '', 48);
select app.mtg_notices_due();
select pg_temp.check((select notice_state = 'pending' and notice_due_at = starts_at - interval '48 hours' from app.meetings where id = (select id from t_m where k = 'D')),
                     'rec_notice custom 48: the notice is due 48 hours before');
select public.setting_set('rec_notice', 'off');
select app.mtg_notices_due();
select pg_temp.check((select notice_state = 'not_required' and notice_due_at is null and bot_state = 'scheduled' from app.meetings where id = (select id from t_m where k = 'D')),
                     'rec_notice off: no advance email; the bot may still join, visibly');
select public.setting_set('rec_notice', 'on_24h');
select app.mtg_notices_due();
select pg_temp.check((select notice_state = 'pending' and notice_due_at = starts_at - interval '24 hours' from app.meetings where id = (select id from t_m where k = 'D')),
                     'back on: due 24 hours before');

-- the per-user switch blocks the owner's bots
select public.meeting_user_set((select tor from t_ids), '{"enabled":false}');
select pg_temp.check((select bot_state = 'blocked' and bot_block_reason = 'disabled' from app.meetings where id = (select id from t_m where k = 'D')), 'a workspace switched off blocks its bots');
select public.meeting_user_set((select tor from t_ids), '{"enabled":true}');
select pg_temp.check((select bot_state = 'scheduled' from app.meetings where id = (select id from t_m where k = 'D')), 'switched on again, the bot is scheduled');

-- opt-out (art. 21): per meeting, «never record me», and the call's link
select pg_temp.as_nobody();
insert into t_m select 'E', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evE', now() + interval '3 days', array['tor@orgpuls.no', 'kari@kyst.example', 'ole@kyst.example'])) ->> 'id')::uuid;
create temp table t_claim_e as select public.worker_notice_claim((select id from t_m where k = 'E')) c;
create temp table t_oo as select public.meeting_opt_out((select a ->> 'token' from t_claim_e, jsonb_array_elements(c -> 'attendees') a where a ->> 'email' = 'ole@kyst.example'), true) r;
select pg_temp.check((select (select array_agg(k order by k) from jsonb_object_keys(r) k) = array['date', 'organiser_company'] and r ->> 'organiser_company' = 'Owntheagenda P7 AS' from t_oo),
                     'the opt-out page learns the date and the organiser''s company, nothing else');
select pg_temp.check((select opted_out_at is not null from app.meeting_attendees where meeting_id = (select id from t_m where k = 'E') and email = 'ole@kyst.example')
                     and exists (select 1 from app.recording_opt_outs where email_sha256 = app.email_hash('ole@kyst.example') and via = 'notice_link'),
                     'the guest is opted out of this meeting, and «always» keeps the hash of the address');
select pg_temp.check((select bot_state = 'blocked' and bot_block_reason = 'opted_out' from app.meetings where id = (select id from t_m where k = 'E'))
                     and exists (select 1 from app.notifications where key = 'meeting.opted_out' and record_id = (select id from t_m where k = 'E') and params = jsonb_build_object('record', 'Møte evE')),
                     'the bot is blocked and the owner told, without the address');
insert into t_m select 'F', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evF', now() + interval '5 days', array['tor@orgpuls.no', 'ole@kyst.example'])) ->> 'id')::uuid;
select pg_temp.check((select bot_state = 'blocked' and bot_block_reason = 'opted_out' from app.meetings where id = (select id from t_m where k = 'F')),
                     '«never record me» blocks the bot in every later meeting with that address');
select pg_temp.expect_error($$select public.meeting_opt_out('not-a-token-but-long-enough-xx', false)$$, 'not_found', 'an unknown token finds nothing');
select pg_temp.expect_error($$update app.recording_opt_outs set via = 'staff'$$, 'an opt-out is kept', 'an opt-out cannot be changed');
select pg_temp.expect_error($$delete from app.recording_opt_outs$$, 'an opt-out is kept', 'nor removed');
insert into t_m select 'H', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evH', now() + interval '4 minutes', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
create temp table t_htok as select pg_temp.admit((select id from t_m where k = 'H')) tok;
select public.meeting_opt_out((select tok from t_htok), false);
select pg_temp.check((select bot_state = 'blocked' and bot_block_reason = 'opted_out' from app.meetings where id = (select id from t_m where k = 'H'))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_bot_leave' and message ->> 'meeting_id' = (select id::text from t_m where k = 'H')),
                     'the in-call link makes the bot leave at once');
select pg_temp.check((public.worker_recording_ready((select id from t_m where k = 'H'), jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'H') || '/a.webm')) ->> 'refused') = 'opted_out',
                     'and what it recorded is refused');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error(format($$select public.meeting_opt_out_staff(%L, 'kari@kyst.example')$$, (select id from t_m where k = 'D')), 'not_found', 'staff record an objection only on a meeting they see');

-- ---------------------------------------------------------------------------
-- the pre-call brief (MTG-01): facts with sources before the meeting, quotes only with the AI provider
select pg_temp.as_staff('tor@orgpuls.no');
select public.rec_save('deal', (select deal from t_ids), '{"expected_close_date":"2026-12-15"}');
select pg_temp.check((public.meeting_brief_regenerate((select id from t_m where k = 'D')) ->> 'quotes_state') = 'not_connected', 'without the AI provider the quotes say so');
create temp table t_brief as select public.meeting_brief((select id from t_m where k = 'D')) b;
select pg_temp.check((select b ->> 'state' = 'ready' and jsonb_path_exists(b, '$.facts[*] ? (@.key == "deal" && @.params.value == 120000 && @.source.entity == "deal")')
                             and jsonb_path_exists(b, '$.changes[*] ? (@.kind == "field_changed" && @.params.field == "expected_close_date")')
                             and jsonb_path_exists(b, '$.people[*] ? (@.name == "Kari Kystlinje" && @.title == "Leder")') from t_brief),
                     'the brief cites the deal, the change since the last contact, and who you meet');
select pg_temp.expect_detail(format($$select public.meeting_brief_check(%L, 'chg:0', true)$$, (select id from t_m where k = 'D')), 'invalid', 'item_key', 'only an item of the brief can be ticked');
select public.meeting_brief_check((select id from t_m where k = 'D'), (select c ->> 'key' from t_brief, jsonb_array_elements(b -> 'changes') c limit 1), true);
select pg_temp.check(jsonb_path_exists(public.meeting_brief((select id from t_m where k = 'D')), '$.changes[*] ? (@.checked == true)'), 'a tick is kept per user (Q18)');
-- two organisations with the same product: each health and applications line names its organisation (R-MEETINGS-03)
create temp table t_ho as select gen_random_uuid() acct1, gen_random_uuid() acct2, gen_random_uuid() org2;
insert into app.accounts (id, name) select acct1, 'Kystlinje Konto P7' from t_ho union all select acct2, 'Mjøsa Konto P7' from t_ho;
update app.organizations set account_id = (select acct1 from t_ho) where id = (select org from t_ids);
insert into app.organizations (id, name, account_id) select org2, 'Mjøsa Energi P7', acct2 from t_ho;
insert into app.account_products (product, tenant_id, account_id) select 'orgpuls', 'p7-tenant-1', acct1 from t_ho union all select 'orgpuls', 'p7-tenant-2', acct2 from t_ho;
insert into app.health_scores (product, tenant_id, day, score, factors, model_id)
select 'orgpuls', t, current_date, s, '[]', (select id from app.health_models where active) from (values ('p7-tenant-1', 71), ('p7-tenant-2', 44)) v(t, s);
update app.meetings set organization_id = (select org2 from t_ho) where id = (select id from t_m where k = 'D');
select public.meeting_brief_regenerate((select id from t_m where k = 'D'));
create temp table t_bf as select f from jsonb_array_elements(public.meeting_brief((select id from t_m where k = 'D')) -> 'facts') f;
select pg_temp.check((select count(*) from t_bf where f ->> 'key' = 'health:orgpuls') = 2
                     and exists (select 1 from t_bf where f ->> 'key' = 'health:orgpuls' and f -> 'params' ->> 'organization' = 'Kystlinje Transport P7' and (f -> 'params' ->> 'score')::int = 71
                                 and f -> 'source' ->> 'id' = (select org::text from t_ids))
                     and exists (select 1 from t_bf where f ->> 'key' = 'health:orgpuls' and f -> 'params' ->> 'organization' = 'Mjøsa Energi P7' and (f -> 'params' ->> 'score')::int = 44),
                     'each organisation''s health line names the organisation (R-MEETINGS-03)');
select pg_temp.check((select count(*) from t_bf where f ->> 'key' = 'applications') = 2
                     and exists (select 1 from t_bf where f ->> 'key' = 'applications' and f -> 'params' ->> 'organization' = 'Mjøsa Energi P7'
                                 and f -> 'params' -> 'products' = '["orgpuls"]'::jsonb and f -> 'source' ->> 'id' = (select org2::text from t_ho)),
                     'applications is one line per organisation, named and cited to it (R-MEETINGS-03)');
update app.meetings set organization_id = null where id = (select id from t_m where k = 'D');
select pg_temp.as_nobody();
create temp table t_bj as select app.mtg_briefs_due() n;
select pg_temp.check((select n from t_bj) >= 1 and exists (select 1 from app.meeting_briefs where meeting_id = (select id from t_m where k = 'C') and state = 'ready'),
                     'the brief job builds a brief for every meeting within 24 hours');
select pg_temp.check(app.mtg_briefs_due() = 0, 'a brief already built for T−24 h is not rebuilt');

-- ---------------------------------------------------------------------------
-- transcription (SF-21): provider transcript, speakers, the recap that waits for the AI provider
update app.integration_connections set status = 'connected' where provider = 'transcription';
insert into t_m select 'H2', (public.worker_meeting_upsert((select tor from t_ids), pg_temp.ev('evH2', now() + interval '4 minutes', array['tor@orgpuls.no', 'kari@kyst.example'])) ->> 'id')::uuid;
update app.meetings set visibility = 'all' where id = (select id from t_m where k = 'H2');
select pg_temp.admit((select id from t_m where k = 'H2'));
create temp table t_t as select (public.worker_recording_ready((select id from t_m where k = 'H2'),
  jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'H2') || '/a.webm', 'duration_s', 425)) ->> 'transcript_id')::uuid id;
-- the call is over (the suite's clock stands still, so the meeting is moved into the past)
select public.worker_bot_state((select id from t_m where k = 'H2'), 'left');
update app.meetings set starts_at = now() - interval '1 hour', ends_at = now() - interval '30 minutes' where id = (select id from t_m where k = 'H2');
select pg_temp.check((select state = 'processing' and source = 'provider' from app.meeting_transcripts where id = (select id from t_t))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_transcribe' and message ->> 'transcript_id' = (select id::text from t_t)),
                     'with transcription connected a recording is sent to be transcribed');
select pg_temp.check((public.worker_transcript_ready((select id from t_t),
  jsonb_build_object('language', 'nb-NO', 'segments', jsonb_build_array(
    jsonb_build_object('start_ms', 12000, 'end_ms', 30000, 'speaker', 'Tor', 'text', 'Takk for at dere tok dere tid.'),
    jsonb_build_object('start_ms', 31000, 'end_ms', 120000, 'speaker', 'Kari', 'text', 'Vi er 220 sjåfører fordelt på tre depoter, og budsjettet er godkjent for fire hundre tusen.'),
    jsonb_build_object('start_ms', 318000, 'speaker', 'Kari', 'text', 'HR-sjefen vår, Nora Berg, må være med på neste møte.'))),
  '[{"label":"Tor","email":"tor@orgpuls.no"},{"label":"Kari","email":"kari@kyst.example"}]'::jsonb) ->> 'segments')::int = 3,
                     'the provider''s segments are stored');
select pg_temp.check((select state = 'ready' and language = 'nb-NO' and speaker_count = 2 and duration_s = 425 from app.meeting_transcripts where id = (select id from t_t))
                     and (select staff_id = (select tor from t_ids) from app.transcript_speakers where transcript_id = (select id from t_t) and label = 'Tor')
                     and (select person_id = (select kari from t_ids) from app.transcript_speakers where transcript_id = (select id from t_t) and label = 'Kari'),
                     '«28 min · 2 speakers · nb-NO» is computed; speakers are mapped to staff and people by address');
select pg_temp.check((select state = 'not_connected' from app.meeting_recaps where transcript_id = (select id from t_t))
                     and exists (select 1 from app.notifications where key = 'meeting.transcript_ready' and record_id = (select id from t_m where k = 'H2'))
                     and exists (select 1 from app.events where kind = 'meeting.transcribed' and subject_id = (select id from t_m where k = 'H2') and payload ->> 'duration_s' = '425'),
                     'without the AI provider the recap reads «not connected»; the transcript is ready and the owner told');
select pg_temp.expect_error($$update app.transcript_segments set text = 'endret' where seq = 1$$, 'a transcript is fixed', 'nobody changes what was said');
select pg_temp.expect_error($$delete from app.transcript_segments where seq = 1$$, 'a transcript is fixed', 'nor removes a line while the transcript stands');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select jsonb_array_length(r -> 'segments') = 2 and (r ->> 'next')::int = 2 and jsonb_path_exists(r, '$.speakers[*] ? (@.label == "Kari" && @.kind == "external")')
                      from (select public.meeting_transcript((select id from t_m where k = 'H2'), 0, 2) r) x), 'the transcript is paged, speakers named and kinded');
select pg_temp.check((public.meeting_transcript((select id from t_m where k = 'H2'), 2, 200) -> 'segments' -> 0 ->> 'seq')::int = 3, 'the cursor continues after the last seq');

-- a failed transcription keeps the recording; Retry needs the provider (SF-21.7)
select pg_temp.as_nobody();
create temp table t_tf as select (public.worker_recording_ready((select id from t_m where k = 'C'),
  jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'C') || '/b.webm')) ->> 'transcript_id')::uuid id;
select public.worker_transcript_ready((select id from t_tf), null, null, 'audio_unreadable');
select pg_temp.check((select state = 'failed' and error_code = 'audio_unreadable' from app.meeting_transcripts where id = (select id from t_tf))
                     and (select state = 'failed' from app.meeting_recordings where storage_path = 'recording/' || (select id from t_m where k = 'C') || '/b.webm'),
                     'a failed transcription is kept as failed, with the recording');
select pg_temp.as_staff('tor@orgpuls.no');
update app.integration_connections set status = 'not_connected' where provider = 'transcription';
select pg_temp.expect_detail(format($$select public.meeting_transcript_retry(%L)$$, (select id from t_tf)), 'not_connected', 'transcription', 'Retry needs transcription');
update app.integration_connections set status = 'connected' where provider = 'transcription';
create temp table t_rt as select public.meeting_transcript_retry((select id from t_tf)) r;
select pg_temp.check((select r ->> 'state' from t_rt) = 'processing'
                     and exists (select 1 from app.meeting_transcripts where meeting_id = (select id from t_m where k = 'C') and state = 'processing'), 'Retry sends it again');

-- ---------------------------------------------------------------------------
-- the AI gateway (SF-24): refused while not connected; every call logged without prompt or output
select pg_temp.expect_detail(format($$select public.meeting_recap_regenerate(%L)$$, (select id from t_t)), 'not_connected', 'ai', 'a recap needs the AI provider');
select pg_temp.as_nobody();
select pg_temp.expect_detail($$select public.worker_ai_call('{"feature":"meeting_recap","state":"ok"}')$$, 'not_connected', 'ai', 'no call is logged as made while the provider is not connected');
select pg_temp.check((public.worker_ai_call('{"feature":"meeting_recap","state":"not_connected"}') ->> 'id') is not null, 'the refusal itself is logged');
select pg_temp.expect_error($$update app.ai_calls set cost_micros = 1$$, 'the AI call log is append-only', 'the log is append-only');
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name = 'ai_calls' and column_name ~ '^(prompt|output|text|content|body|completion|messages)$'),
                     'the log has no column for a prompt or an output (A7.13)');
update app.integration_connections set status = 'connected' where provider = 'ai';
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_rg as select public.meeting_recap_regenerate((select id from t_t)) r;
select pg_temp.check((select r ->> 'state' from t_rg) = 'requested'
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_recap' and message ->> 'transcript_id' = (select id::text from t_t)),
                     'with the provider the recap and suggestions are one AI job');
select pg_temp.as_nobody();
select pg_temp.check((select jsonb_array_length(c -> 'segments') = 3 and jsonb_path_exists(c, '$.records[*] ? (@.entity == "deal")') and not c ? 'instructions'
                      from (select public.worker_meeting_ai_context(jsonb_build_object('feature', 'meeting_recap', 'transcript_id', (select id from t_t))) c) x),
                     'the AI context holds the transcript and the linked records');
create temp table t_ai as select (public.worker_ai_call(jsonb_build_object('feature', 'meeting_recap', 'subject_type', 'meeting_transcript', 'subject_id', (select id from t_t),
  'provider', 'anthropic', 'model', 'claude', 'input_tokens', 5200, 'output_tokens', 700, 'cost_micros', 31000, 'latency_ms', 8200, 'state', 'ok')) ->> 'id')::bigint recap,
  (public.worker_ai_call('{"feature":"meeting_brief","state":"retried_ok","attempts":2}') ->> 'id')::bigint brief,
  (public.worker_ai_call('{"feature":"project_summary","state":"ok"}') ->> 'id')::bigint project;
select pg_temp.expect_detail($$select public.worker_ai_call('{"feature":"meeting_recap","state":"ok","prompt":"x"}')$$, 'invalid', 'prompt', 'a prompt is refused, by name');
select pg_temp.expect_detail(format($$select public.worker_recap_ready(%L, jsonb_build_object('state', 'ready', 'ai_call_id', %s))$$, (select id from t_t), (select brief from t_ai)),
                             'invalid', 'ai_call_id', 'a recap names a meeting_recap call');
create temp table t_rr as select public.worker_recap_ready((select id from t_t),
  jsonb_build_object('state', 'ready', 'ai_call_id', (select recap from t_ai),
    'takeaways', jsonb_build_array(jsonb_build_object('text', '220 sjåfører på tre depoter', 'seq', 2), jsonb_build_object('text', 'Budsjett godkjent', 'seq', 99)),
    'next_steps', jsonb_build_array(jsonb_build_object('text', 'Send forslag innen fredag'), jsonb_build_object('text', 'Book demo med Nora Berg', 'seq', 3))),
  jsonb_build_array(
    jsonb_build_object('target_entity', 'deal', 'target_id', (select deal from t_ids), 'field', 'value', 'value', 400000, 'evidence', jsonb_build_array(2, 77)),
    jsonb_build_object('target_entity', 'person', 'target_id', (select kari from t_ids), 'field', 'expected_close', 'value', '2026-12-15'),
    jsonb_build_object('target_entity', 'person', 'target_id', (select kari from t_ids), 'field', 'title', 'value', 'Driftssjef'),
    jsonb_build_object('target_entity', 'organization', 'target_id', (select org from t_ids), 'field', 'employees', 'value', 220),
    jsonb_build_object('target_entity', 'person', 'field', '*new', 'value', jsonb_build_object('name', 'Nora Berg', 'title', 'HR-leder', 'organization_id', (select org from t_ids))),
    jsonb_build_object('target_entity', 'deal', 'target_id', (select deal2 from t_ids), 'field', 'value', 'value', 1),
    jsonb_build_object('target_entity', 'deal', 'target_id', (select deal from t_ids), 'field', 'owner_id', 'value', (select ola from t_ids)),
    jsonb_build_object('target_entity', 'deal', 'target_id', (select deal from t_ids), 'field', 'labels', 'value', jsonb_build_array((select lbl from t_ids))),
    jsonb_build_object('target_entity', 'organization', 'target_id', (select org from t_ids), 'field', 'employees', 'value', 'mange'))) r;
select pg_temp.check((select (r ->> 'suggestions')::int = 5 and (r ->> 'dropped')::int = 4 from t_rr),
                     'suggestions are checked against the register: no such field, a record not linked to the meeting, the owner, a wrong type are dropped');
select pg_temp.check((select state = 'ready' and ai_call_id = (select recap from t_ai) and takeaways -> 1 -> 'seq' = 'null'::jsonb and next_steps -> 1 ->> 'seq' = '3'
                      from app.meeting_recaps where transcript_id = (select id from t_t)), 'the recap is stored with its call; a seq not in the transcript is dropped');
select pg_temp.check((select current_value = '120000'::jsonb and base_version is not null and evidence = array[2] from app.meeting_suggestions
                      where transcript_id = (select id from t_t) and field = 'value'), 'the current value and version are snapshotted; evidence keeps real lines only');
select pg_temp.check(exists (select 1 from app.notifications where key = 'meeting.recap_ready' and record_id = (select id from t_m where k = 'H2') and params ->> 'suggestions' = '5'),
                     'the owner is told the recap is ready (in-app; Slack is not connected)');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select r -> 'state' ->> 'key' = 'suggestions' and (r -> 'state' ->> 'n')::int = 5 and r ->> 'group' = 'review'
                      from (select public.meeting_detail((select id from t_m where k = 'H2')) r) x), 'the meeting needs review: «5 suggestions»');
create temp table t_sg as select x from jsonb_array_elements(public.meeting_suggestions((select id from t_m where k = 'H2')) -> 'suggestions') x;
select pg_temp.check(exists (select 1 from t_sg where x ->> 'field' = 'value' and x ->> 'target_entity' = 'deal' and x ->> 'currency' = 'NOK')
                     and not exists (select 1 from t_sg where x ->> 'field' <> 'value' and x -> 'currency' <> 'null'::jsonb)
                     and (select count(*) from t_sg where x ? 'currency') = (select count(*) from t_sg),
                     'a suggestion on a deal''s value carries the deal''s currency; other fields carry none (R-MEETINGS-04)');

-- ---------------------------------------------------------------------------
-- CRM update suggestions (MTG-05): nothing written without approval; written with the meeting as source; stale never overwritten
create temp table t_s as select field, id from app.meeting_suggestions where transcript_id = (select id from t_t);
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check((select r -> 'results' -> 0 ->> 'state' = 'pending' and r -> 'results' -> 0 ->> 'error' = 'forbidden' and r -> 'results' -> 0 ->> 'detail' = 'deals:edit_others'
                             and (r ->> 'written')::int = 0
                      from (select public.meeting_suggestion_decide(array[(select id from t_s where field = 'value')], 'accept') r) x),
                     'a read-only user cannot accept a change to someone else''s deal: it stays pending');
select pg_temp.as_staff('tor@orgpuls.no');
select public.rec_save('person', (select kari from t_ids), '{"title":"Daglig leder"}');
select pg_temp.check(jsonb_path_exists(public.meeting_suggestions((select id from t_m where k = 'H2')), '$.suggestions[*] ? (@.field == "title" && @.stale_now == true)'),
                     'a suggestion whose record moved is flagged stale');
create temp table t_dec as select public.meeting_suggestion_decide(array[(select id from t_s where field = 'value'), (select id from t_s where field = 'labels'),
  (select id from t_s where field = 'title')], 'accept') r;
select pg_temp.check((select (r ->> 'written')::int = 2 and r -> 'results' -> 2 ->> 'state' = 'stale' from t_dec)
                     and (select value = 400000 and labels = array[(select lbl from t_ids)] from app.deals where id = (select deal from t_ids))
                     and (select title = 'Daglig leder' from app.people where id = (select kari from t_ids)),
                     'accepted items are written; the stale one is not overwritten');
select pg_temp.check(exists (select 1 from app.changelog where entity = 'deal' and record_id = (select deal from t_ids) and field = 'value' and source = 'meeting'
                             and new_value = '400000'::jsonb and actor_id = (select tor from t_ids)), 'and logged with the meeting as source (MTG-05 A)');
select public.meeting_suggestion_decide(array[(select id from t_s where field = 'employees')], 'reject');
select pg_temp.check((select employees = 180 from app.organizations where id = (select org from t_ids))
                     and (select state = 'rejected' and decided_by = (select tor from t_ids) from app.meeting_suggestions where id = (select id from t_s where field = 'employees')),
                     'a rejected item writes nothing');
select public.setting_set('contact_rule', 'opt_in_only');
create temp table t_cr as select public.meeting_suggestion_decide(array[(select id from t_s where field = '*new')], 'accept') r;
select pg_temp.check((select r -> 'results' -> 0 ->> 'state' = 'failed' and r -> 'results' -> 0 ->> 'detail' = 'setting:contact_rule' from t_cr)
                     and not exists (select 1 from app.people where name = 'Nora Berg'),
                     'a new contact follows contact_rule: refused under «opt_in_only», the setting named');
select public.setting_set('contact_rule', 'no_rule');
select pg_temp.check((select r -> 'results' -> 0 ->> 'error' = 'invalid' and r -> 'results' -> 0 ->> 'detail' = 'state'
                      from (select public.meeting_suggestion_decide(array[(select id from t_s where field = 'value')], 'reject') r) x), 'a decided item stays decided');
select pg_temp.check(exists (select 1 from app.events where kind = 'meeting.updates_approved' and subject_id = (select id from t_m where k = 'H2')
                             and payload = '{"accepted":2,"rejected":0,"stale":1,"failed":0}'::jsonb), 'meeting.updates_approved carries counts only');

-- the recap as a note on the record (MTG-04), and the next step as an activity
select pg_temp.expect_detail(format($$select public.meeting_recap_save_note(%L, 'person', %L)$$, (select id from t_m where k = 'H2'), (select deal2 from t_ids)),
                             'invalid', 'link', 'a recap is saved only on one of the meeting''s own links');
create temp table t_note as select public.meeting_recap_save_note((select id from t_m where k = 'H2')) r;
select pg_temp.check((select r ->> 'entity' = 'deal' and (r ->> 'record_id')::uuid = (select deal from t_ids) from t_note)
                     and (select body like '· 220 sjåfører på tre depoter%' and body like '%○ Send forslag innen fredag%' and body like '%/meetings?meeting=' || (select id from t_m where k = 'H2')
                          from app.notes where id = (select (r ->> 'note_id')::uuid from t_note)),
                     'Save recap as note: on the deal (deal → lead → organisation → person), takeaways, next steps and a link back');
select pg_temp.check((public.meeting_recap_save_note((select id from t_m where k = 'H2')) ->> 'already')::boolean, 'saving again returns the saved note');
select pg_temp.check((select r ->> 'key' = 'recap_saved' from (select public.meeting_detail((select id from t_m where k = 'H2')) -> 'state' r) x)
                     and exists (select 1 from app.events where kind = 'meeting.recap_saved' and subject_id = (select id from t_m where k = 'H2')),
                     'the meeting reads «Recap saved»');
select pg_temp.expect_detail(format($$select public.meeting_recap_regenerate(%L)$$, (select id from t_t)), 'invalid', 'saved', 'a saved recap is not regenerated');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format($$select public.meeting_next_step_activity(%L, 0)$$, (select id from t_m where k = 'H2')), 'forbidden', 'deals:add', 'planning an activity needs deals:add');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_na as select public.meeting_next_step_activity((select id from t_m where k = 'H2'), 0, jsonb_build_object('starts_at', now() + interval '2 days')) r;
select pg_temp.check((select subject = 'Send forslag innen fredag' and deal_id = (select deal from t_ids) and not done from app.activities where id = (select (r ->> 'activity_id')::uuid from t_na))
                     and (select next_steps -> 0 ->> 'activity_id' = (select r ->> 'activity_id' from t_na) from app.meeting_recaps where transcript_id = (select id from t_t))
                     and exists (select 1 from app.changelog where entity = 'activity' and record_id = (select (r ->> 'activity_id')::uuid from t_na) and field = '*created' and source = 'meeting'),
                     'Plan next activity: the step becomes an activity on the deal, remembered on the step');
select pg_temp.expect_detail(format($$select public.meeting_next_step_activity(%L, 9)$$, (select id from t_m where k = 'H2')), 'invalid', 'step', 'only a real step');

-- quotes: an exact excerpt of a related conversation is kept; anything else is dropped (anti-fabrication)
create temp table t_br2 as select public.meeting_brief_regenerate((select id from t_m where k = 'D')) r;
select pg_temp.check((select r ->> 'quotes_state' from t_br2) = 'requested'
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_brief_quotes' and message ->> 'meeting_id' = (select id::text from t_m where k = 'D')),
                     'with the provider the quotes are requested');
select pg_temp.as_nobody();
select pg_temp.check((select c ->> 'instructions' is null and jsonb_path_exists(c, '$.segments[*] ? (@.seq == 2)') from (select public.worker_meeting_ai_context(jsonb_build_object('feature', 'meeting_brief', 'meeting_id', (select id from t_m where k = 'D'))) c) x),
                     'the brief context holds earlier conversations on the same deal');
create temp table t_q as select public.worker_brief_quotes_ready((select id from t_m where k = 'D'), jsonb_build_object('state', 'ready', 'ai_call_id', (select brief from t_ai), 'quotes', jsonb_build_array(
  jsonb_build_object('text', 'budsjettet er godkjent for fire hundre tusen', 'source', jsonb_build_object('kind', 'segment', 'transcript_id', (select id from t_t), 'seq', 2)),
  jsonb_build_object('text', 'budsjettet er godkjent for en million', 'source', jsonb_build_object('kind', 'segment', 'transcript_id', (select id from t_t), 'seq', 2)),
  jsonb_build_object('text', 'Send forslag innen fredag', 'source', jsonb_build_object('kind', 'note', 'note_id', (select (r ->> 'note_id')::uuid from t_note)))))) r;
select pg_temp.check((select (r ->> 'kept')::int = 2 and (r ->> 'dropped')::int = 1 from t_q)
                     and (select quotes_state = 'ready' and quotes -> 0 ->> 'speaker' = 'Kari Kystlinje' and ai_call_id = (select brief from t_ai) from app.meeting_briefs where meeting_id = (select id from t_m where k = 'D')),
                     'a quote that is not an exact substring of its source is dropped; the speaker comes from the source');

-- ---------------------------------------------------------------------------
-- upload (MTG-06), linking afterwards (MTG-07), speaker mapping
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.meeting_transcript_upload_begin(null, 'samtale.pdf', 'application/pdf', 100)$$, 'invalid', 'mime', 'only .vtt, .srt, .txt and .docx');
select pg_temp.expect_detail($$select public.meeting_transcript_upload_begin(null, 'samtale.txt', 'text/vtt', 100)$$, 'invalid', 'filename', 'the extension matches the type');
select pg_temp.expect_detail($$select public.meeting_transcript_upload_begin(null, 'samtale.vtt', 'text/vtt', 5242881)$$, 'invalid', 'size', 'up to 5 MB');
create temp table t_up as select public.meeting_transcript_upload_begin(null, 'Kystlinje discovery.vtt', 'text/vtt', 4096) r;
insert into t_m select 'U', (select (r ->> 'meeting_id')::uuid from t_up);
select pg_temp.check((select title = 'Kystlinje discovery' and source = 'upload' and capture = 'upload' and owner_id = (select ingrid from t_ids) and visibility = 'owner'
                             and num_nonnulls(deal_id, lead_id, person_id, organization_id) = 0 from app.meetings where id = (select id from t_m where k = 'U'))
                     and (select r ->> 'bucket' = 'meeting-files' and r ->> 'path' like 'upload/' || (r ->> 'meeting_id') || '/%.vtt' from t_up),
                     'an upload without a meeting makes an unlinked one; the path is signed by the edge');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('visibility_default', 'all', 'meeting');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_ub as select (public.meeting_transcript_upload_begin(null, 'b.txt', 'text/plain', 10) ->> 'meeting_id')::uuid id;
select pg_temp.check((select visibility = 'all' from app.meetings where id = (select id from t_ub)),
                     'visibility_default for «meeting» changes a new meeting''s visibility');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error(format($$select public.meeting_transcript_upload_done(%L)$$, (select (r ->> 'id')::uuid from t_up)), 'not_found', 'only the uploader confirms an upload');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_ud as select public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_up)) r;
select pg_temp.check(exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'meeting_upload_parse' and message ->> 'upload_id' = (select r ->> 'id' from t_up)), 'the parse is queued');
select pg_temp.as_nobody();
select public.worker_upload_parsed((select (r ->> 'id')::uuid from t_up), jsonb_build_array(
  jsonb_build_object('start_ms', 0, 'speaker', 'Lars', 'text', 'I dag går alt på telefon og en delt Excel.'),
  jsonb_build_object('start_ms', 5000, 'speaker', 'Ingrid Solberg', 'text', 'Da passer Skiftly per depot.')));
select pg_temp.check((select state = 'ready' and speaker_count = 2 from app.meeting_transcripts where id = (select (r ->> 'transcript_id')::uuid from t_ud))
                     and (select state = 'parsed' from app.meeting_uploads where id = (select (r ->> 'id')::uuid from t_up))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message -> 'paths' ? (select r ->> 'path' from t_up)),
                     'the parsed transcript is ready and the original file goes from storage');
select pg_temp.check((select staff_id = (select ingrid from t_ids) from app.transcript_speakers where transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and label = 'Ingrid Solberg')
                     and (select staff_id is null and person_id is null from app.transcript_speakers where transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and label = 'Lars'),
                     'the owner''s name is mapped; an unknown label waits for mapping');
select pg_temp.expect_detail(format($$select public.worker_upload_parsed(%L, '[]')$$, (select (r ->> 'id')::uuid from t_up)), 'invalid', 'state', 'an upload is parsed once');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_up2 as select public.meeting_transcript_upload_begin((select id from t_m where k = 'U'), 'del2.srt', 'application/x-subrip', 500) r;
create temp table t_ud2 as select public.meeting_transcript_upload_done((select (r ->> 'id')::uuid from t_up2)) r;
select pg_temp.as_nobody();
select public.worker_upload_parsed((select (r ->> 'id')::uuid from t_up2), null);
select pg_temp.check((select state = 'failed' and error_code = 'parse_failed' from app.meeting_transcripts where id = (select (r ->> 'transcript_id')::uuid from t_ud2)), 'an unreadable file fails as parse_failed');
delete from app.meeting_transcripts where id = (select (r ->> 'transcript_id')::uuid from t_ud2);
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.meeting_recap((select id from t_m where k = 'U')) ->> 'state') = 'requested', 'the upload''s recap follows the AI provider (connected here)');
select public.meeting_speaker_map((select (r ->> 'transcript_id')::uuid from t_ud), 'Lars', '{"email":"Lars@Gjest.example"}');
select pg_temp.check(jsonb_path_exists(public.meeting_transcript((select id from t_m where k = 'U')),
                                       '$.speakers[*] ? (@.label == "Lars" && @.email == "lars@gjest.example" && @.kind == "unknown" && @.name == null)')
                     and jsonb_path_exists(public.meeting_transcript((select id from t_m where k = 'U')), '$.speakers[*] ? (@.label == "Ingrid Solberg" && @.kind == "staff")'),
                     'a label mapped to an address only reads back with that address (R-MEETINGS-05)');
select public.meeting_speaker_map((select (r ->> 'transcript_id')::uuid from t_ud), 'Lars', jsonb_build_object('person_id', (select kari from t_ids)));
select pg_temp.check(jsonb_path_exists(public.meeting_transcript((select id from t_m where k = 'U')), '$.speakers[*] ? (@.label == "Lars" && @.email == "kari@kyst.example" && @.kind == "external")'),
                     'a label mapped to a visible person carries the person''s address (R-MEETINGS-05)');
select pg_temp.check((select person_id = (select kari from t_ids) and email = 'kari@kyst.example' from app.transcript_speakers where transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and label = 'Lars'),
                     'the owner maps a speaker to a person');
select pg_temp.expect_detail(format($$select public.meeting_speaker_map(%L, 'Nobody', '{}')$$, (select (r ->> 'transcript_id')::uuid from t_ud)), 'not_found', 'label', 'only a label of the transcript');
select pg_temp.expect_detail(format($$select public.meeting_link(%L, jsonb_build_object('deal_id', gen_random_uuid()))$$, (select id from t_m where k = 'U')), 'not_found', 'deal_id', 'linking needs a visible record');
select pg_temp.expect_detail(format($$select public.meeting_link(%L, jsonb_build_object('deal_id', %L), 99)$$, (select id from t_m where k = 'U'), (select deal from t_ids)),
                             'version_conflict', '1', 'a stale version is refused with the current one');
create temp table t_ln as select public.meeting_link((select id from t_m where k = 'U'), jsonb_build_object('deal_id', (select deal from t_ids)), 1) r;
select pg_temp.check((select (r ->> 'version')::int = 2 and r -> 'links' -> 'primary' ->> 'id' = (select deal::text from t_ids) from t_ln)
                     and (select done and deal_id = (select deal from t_ids) and type_id = (select id from app.activity_types where key = 'meeting') from app.activities where id = (select (r ->> 'activity_id')::uuid from t_ln))
                     and exists (select 1 from app.changelog where entity = 'meeting' and record_id = (select id from t_m where k = 'U') and field = 'deal_id'),
                     'a recorded call is linked afterwards (MTG-07 A): a done meeting activity on the deal, the change in the meeting''s history');
select pg_temp.check(exists (select 1 from app.events where kind = 'meeting.linked' and subject_id = (select id from t_m where k = 'U') and payload ->> 'deal' = (select deal::text from t_ids)),
                     'meeting.linked carries the ids');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error(format($$select public.meeting_link(%L, '{"deal_id":null}')$$, (select id from t_m where k = 'U')), 'not_found', 'another user''s private meeting cannot be linked');

-- ---------------------------------------------------------------------------
-- capture, bot removal, deleting a recording
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail(format($$select public.meeting_capture_set(%L, 'desktop')$$, (select id from t_m where k = 'A')), 'not_available', 'desktop', 'desktop capture is not available (D-38)');
update app.integration_connections set status = 'not_connected' where provider = 'meeting_bot';
select pg_temp.expect_detail(format($$select public.meeting_capture_set(%L, 'bot')$$, (select id from t_m where k = 'A')), 'not_connected', 'meeting_bot', 'the notetaker needs the bot provider');
update app.integration_connections set status = 'connected' where provider = 'meeting_bot';
create temp table t_cs as select public.meeting_capture_set((select id from t_m where k = 'A'), 'bot') r;
select pg_temp.check((select r -> 'bot' ->> 'state' = 'scheduled' and r -> 'notice' ->> 'state' = 'pending' from t_cs),
                     'choosing the notetaker plans the notice and the bot');
select pg_temp.check((public.meeting_bot_remove((select id from t_m where k = 'A')) ->> 'bot_state') = 'removed', 'Remove bot (MTG-02 A)');
select pg_temp.expect_detail(format($$select public.meeting_bot_remove(%L)$$, (select id from t_m where k = 'A')), 'invalid', 'bot_state', 'a removed bot is not removed twice');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format($$select public.meeting_recording_delete(%L, true)$$, (select id from t_m where k = 'H2')), 'forbidden', 'deals:edit_others',
                             'only the owner (or edit_others) deletes a recording');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_del as select public.meeting_recording_delete((select id from t_m where k = 'H2'), true) r;
select pg_temp.check((select (r ->> 'recordings')::int = 1 and (r ->> 'transcripts')::int = 1 from t_del)
                     and not exists (select 1 from app.meeting_transcripts where meeting_id = (select id from t_m where k = 'H2'))
                     and (select state = 'deleted' and storage_path is null from app.meeting_recordings where meeting_id = (select id from t_m where k = 'H2'))
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message -> 'paths' ? ('recording/' || (select id from t_m where k = 'H2') || '/a.webm')),
                     'Stop and delete recording: the audio goes from storage, the transcript and its recap and suggestions with it');
select pg_temp.check((select jsonb_array_length(quotes) = 1 and quotes -> 0 ->> 'kind' = 'note' from app.meeting_briefs where meeting_id = (select id from t_m where k = 'D')),
                     'quotes citing the deleted transcript leave the brief');
select pg_temp.check(exists (select 1 from app.notes where id = (select (r ->> 'note_id')::uuid from t_note) and deleted_at is null), 'a note already saved on the deal stays');

-- ---------------------------------------------------------------------------
-- retention (rec_retention) and the nightly purge
select public.setting_set('rec_retention', 'custom', '', 1);
select pg_temp.as_nobody();
create temp table t_r1 as select (public.worker_recording_ready((select id from t_m where k = 'C'), jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'C') || '/r1.webm')) ->> 'recording_id')::uuid id;
select pg_temp.check((select purge_after between now() + interval '27 days' and now() + interval '32 days' from app.meeting_recordings where id = (select id from t_r1)),
                     'rec_retention custom 1: the audio is kept one month');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('rec_retention', 'keep');
select pg_temp.as_nobody();
create temp table t_r2 as select (public.worker_recording_ready((select id from t_m where k = 'C'), jsonb_build_object('method', 'bot', 'storage_path', 'recording/' || (select id from t_m where k = 'C') || '/r2.webm')) ->> 'recording_id')::uuid id;
select pg_temp.check((select purge_after is null from app.meeting_recordings where id = (select id from t_r2)),
                     'rec_retention keep: no purge date');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('rec_retention', '12_months');
select pg_temp.as_nobody();
update app.meeting_recordings set purge_after = now() - interval '1 day' where storage_path = 'recording/' || (select id from t_m where k = 'C') || '/r1.webm';
update app.meetings set deleted_at = now() - interval '31 days' where id = (select id from t_m where k = 'A');
create temp table t_purge as select app.mtg_purge() r;
select pg_temp.check((select (r ->> 'recordings')::int >= 1 and (r ->> 'meetings')::int = 1 from t_purge)
                     and exists (select 1 from app.meeting_recordings where meeting_id = (select id from t_m where k = 'C') and state = 'deleted' and storage_path is null and purge_after < now())
                     and exists (select 1 from pgmq.q_jobs where message ->> 'job' = 'files_purge' and message -> 'paths' ? ('recording/' || (select id from t_m where k = 'C') || '/r1.webm')),
                     'the nightly purge deletes audio past its retention and queues the storage delete');
select pg_temp.check(not exists (select 1 from app.meetings where id = (select id from t_m where k = 'A'))
                     and not exists (select 1 from app.changelog where entity = 'meeting' and record_id = (select id from t_m where k = 'A')),
                     'a meeting deleted 30 days ago goes, with its history');
select pg_temp.check(coalesce(current_setting('app.purging', true), '') <> 'on', 'the purge does not leave the purge flag on');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_u3 as select (public.meeting_transcript_upload_begin(null, 'kort.txt', 'text/plain', 10) ->> 'meeting_id')::uuid id;
select public.meeting_link((select id from t_u3), jsonb_build_object('deal_id', (select deal3 from t_ids)));
select pg_temp.as_nobody();
select set_config('app.purging', 'on', true);
delete from app.deals where id = (select deal3 from t_ids);
select set_config('app.purging', 'off', true);
select pg_temp.check((select deleted_at is not null and deal_id is null from app.meetings where id = (select id from t_u3)),
                     'a meeting whose only linked record is purged goes with it (Q12)');

-- ---------------------------------------------------------------------------
-- erasure (SEC-11, §8.3): what the person said is redacted, the audio of meetings they attended deleted
select pg_temp.check(exists (select 1 from app.meeting_attendees where email = 'kari@kyst.example'), 'before erasure Kari attends meetings');
delete from app.people where id = (select kari from t_ids);
select pg_temp.check(not exists (select 1 from app.meeting_attendees where email = 'kari@kyst.example'), 'erasure removes the person''s attendance');
select pg_temp.check((select text = '[removed]' and redacted_at is not null from app.transcript_segments where transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and speaker_label = 'Lars')
                     and (select text <> '[removed]' from app.transcript_segments where transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and speaker_label = 'Ingrid Solberg')
                     and not exists (select 1 from app.transcript_speakers where label = 'Lars' and transcript_id = (select (r ->> 'transcript_id')::uuid from t_ud) and email is not null),
                     'their lines are redacted, everyone else''s kept; the mapping goes');
select pg_temp.check(not exists (select 1 from app.meeting_recordings where meeting_id = (select id from t_m where k = 'C') and state <> 'deleted'),
                     'the audio of every meeting they attended is deleted');
select pg_temp.check(not exists (select 1 from app.meeting_suggestions where target_entity = 'person' and target_id = (select kari from t_ids)), 'suggestions about them go');
select pg_temp.check(exists (select 1 from app.recording_opt_outs where email_sha256 = app.email_hash('ole@kyst.example')), 'the opt-out hashes stay');
select pg_temp.check(exists (select 1 from app.audit where action = 'meeting.erasure' and target_id = (select kari::text from t_ids) and not detail ? 'email'), 'the erasure is audited with counts');

-- ---------------------------------------------------------------------------
-- the other AI calls: project summaries name their call; the inbox insight needs the provider
insert into app.project_boards (id, name) values ('00000000-0000-0000-0000-0000000000b7', 'P7 brett');
insert into app.project_phases (id, board_id, name) values ('00000000-0000-0000-0000-0000000000c7', '00000000-0000-0000-0000-0000000000b7', 'Kickoff');
insert into app.projects (id, name, board_id, phase_id) values ('00000000-0000-0000-0000-0000000000d7', 'P7 prosjekt', '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000c7');
insert into app.project_ai_summaries (id, project_id) values ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000d7');
select pg_temp.expect_detail(format($$select public.worker_project_summary_ready('00000000-0000-0000-0000-0000000000e7', jsonb_build_object('state', 'ready', 'summary', 'x', 'ai_call_id', %s))$$, (select recap from t_ai)),
                             'invalid', 'ai_call_id', 'a project summary names a project_summary call');
select public.worker_project_summary_ready('00000000-0000-0000-0000-0000000000e7', jsonb_build_object('state', 'ready', 'suggested_health', 'at_risk', 'summary', 'x', 'ai_call_id', (select project from t_ai)));
select pg_temp.check((select state = 'ready' and ai_call_id = (select project from t_ai) from app.project_ai_summaries where id = '00000000-0000-0000-0000-0000000000e7'),
                     'the project worker''s call is recorded on the summary (V-P6P-04)');
select pg_temp.as_staff('tor@orgpuls.no');
update app.integration_connections set status = 'not_connected' where provider = 'ai';
select pg_temp.expect_detail(format($$select public.thread_insight_request(%L)$$, (select id from app.email_threads where deleted_at is null order by created_at limit 1)),
                             'not_connected', 'ai', 'the inbox insight is refused while the AI provider is not connected (Q16)');

-- ---------------------------------------------------------------------------
-- no transcript or customer words in logs, event payloads or notifications
select pg_temp.check(not exists (select 1 from app.audit where detail::text like '%sjåfører%' or detail::text like '%Excel%')
                     and not exists (select 1 from app.events where payload::text like '%sjåfører%' or payload::text like '%Excel%')
                     and not exists (select 1 from app.notifications where params::text like '%sjåfører%' or params::text like '%Excel%'),
                     'what was said never reaches the audit, an event or a notification');

-- 0053 (R-MEETINGS-07): a meeting without a brief answers «none», not null
delete from app.meeting_briefs where meeting_id = (select id from t_m where k = 'D');
select pg_temp.check(public.meeting_brief((select id from t_m where k = 'D')) ->> 'state' = 'none', 'a meeting without a brief answers state none (0053)');

rollback;
