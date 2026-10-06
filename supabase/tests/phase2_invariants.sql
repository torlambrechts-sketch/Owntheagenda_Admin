-- phase2_invariants.sql — mail, the workflow engine (workflows, assignment, sequences), the feed, scoring,
-- enrichment and the manual call log (phase 2).
\ir _helpers.psql
begin;

-- only this suite's events reach the subscribers
update app.event_cursors set last_event_id = coalesce((select max(id) from app.events), 0);

-- ---------------------------------------------------------------------------
-- structure
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name in ('email_tracking_events', 'email_tracking_links')
                                 and column_name ~ '(^|_)(ip|ip_address|user_agent)($|_)'), 'tracking stores no IP address or user agent');
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_mail_sent(uuid, text, text, text)', 'execute')
                 and not has_function_privilege('authenticated', 'public.worker_mailbox_token(uuid)', 'execute')
                 and not has_function_privilege('authenticated', 'public.worker_step_done(uuid, boolean, int, text, jsonb)', 'execute')
                 and not has_function_privilege('authenticated', 'public.worker_enrich_done(uuid, jsonb)', 'execute')
                 and has_function_privilege('service_role', 'public.worker_mail_sent(uuid, text, text, text)', 'execute'), 'worker functions belong to the service role alone');
select pg_temp.check(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                 where n.nspname = 'app' and c.relkind = 'r' and not c.relrowsecurity), 'every app table has RLS on');

-- acting as a staff member works only in a database-internal session
select set_config('app.acting_as', (select id::text from app.admins where email = 'tor@orgpuls.no'), true);
select pg_temp.as_nobody();
select pg_temp.check(app.me() = (select id from app.admins where email = 'tor@orgpuls.no'), 'the executor acts as the workflow owner inside the database');
select pg_temp.check(pg_get_functiondef('app.me()'::regprocedure) like '%session_user not in (''authenticator'', ''anon'', ''authenticated'', ''service_role'')%',
                     'acting as someone is refused to sessions that came through the API');
select set_config('app.acting_as', '', true);

-- ---------------------------------------------------------------------------
-- mail
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.email_send(jsonb_build_object('mailbox_id', gen_random_uuid(), 'to', '["kari.nordmann@lumio.no"]'::jsonb, 'subject', 'Hei', 'body', 'x'))$$,
                            'mailbox_not_connected', 'sending without a connected mailbox is refused');
select pg_temp.check((public.inbox_folders() ->> 'connected')::boolean = false, 'the inbox reports no mailbox connected');

-- a connected mailbox, as the OAuth callback registers it
create temp table t_mb as select (public.worker_mailbox_connected((select id from app.admins where email = 'ingrid@orgpuls.no'), 'personal', 'google', 'Ingrid@Orgpuls.no', 'test-token') ->> 'id')::uuid id;
select pg_temp.check((select vault_secret_id is not null and address = 'ingrid@orgpuls.no' from app.mailboxes where id = (select id from t_mb)), 'the token goes to Vault and the address is stored lower-case');
select pg_temp.check(public.worker_mailbox_token((select id from t_mb)) = 'test-token', 'the worker reads the token back');
select public.worker_mailbox_status((select id from t_mb), 'synced');

create temp table t_deal as select d.id, d.person_id, d.organization_id from app.deals d where d.title = 'Kvamme Regnskap — HR suite for 3 sites';
select pg_temp.expect_error(format($$select public.email_send(jsonb_build_object('mailbox_id', %L, 'to', '["hakon.aas@valdresfjellst.no"]'::jsonb, 'subject', 'Hei', 'body', 'Hei [Person.fornavn], [Ukjent.felt]'))$$, (select id from t_mb)),
                            'invalid', 'an unknown merge field is refused');
update app.organizations set employees = null where id = (select organization_id from t_deal);
select pg_temp.expect_error(format($$select public.email_send(jsonb_build_object('mailbox_id', %L, 'to', '["hakon.aas@valdresfjellst.no"]'::jsonb, 'subject', 'Hei', 'body', 'Dere er [Organisasjon.ansatte]', 'entity', 'deal', 'record_id', %L))$$,
                                   (select id from t_mb), (select id from t_deal)), 'invalid', 'a merge field without a value refuses the send (COM-05)');
update app.organizations set employees = 54 where id = (select organization_id from t_deal);
create temp table t_send as select public.email_send(jsonb_build_object('mailbox_id', (select id from t_mb), 'to', '["hakon.aas@valdresfjellst.no"]'::jsonb, 'subject', 'Tilbud til [Organisasjon.navn]',
  'body', 'Hei [Person.fornavn], se https://owntheagenda.com/pris', 'entity', 'deal', 'record_id', (select id from t_deal))) r;
select pg_temp.check((select r ->> 'state' from t_send) = 'queued', 'a message without a time is queued');
select pg_temp.check((select subject = 'Tilbud til Kvamme Regnskap AS' and body_text like 'Hei Håkon,%' from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_send)), 'merge fields are rendered server-side');
select pg_temp.check(exists (select 1 from app.email_links where thread_id = (select (r ->> 'thread_id')::uuid from t_send) and entity = 'deal' and record_id = (select id from t_deal)), 'the thread is linked to the deal');
select pg_temp.check((select count(*) from app.email_tracking_links where message_id = (select (r ->> 'message_id')::uuid from t_send)) = 1, 'links become tracked redirects when tracking is on');
select pg_temp.check(exists (select 1 from pgmq.q_jobs where message ->> 'message_id' = (select r ->> 'message_id' from t_send)), 'the send job is on the queue');

-- the worker sends it
select pg_temp.as_nobody();
select pg_temp.check(public.worker_mail_claim((select (r ->> 'message_id')::uuid from t_send)) is not null, 'the worker claims a queued message');
select pg_temp.check(public.worker_mail_claim((select (r ->> 'message_id')::uuid from t_send)) is null, 'a message is claimed once');
select public.worker_mail_sent((select (r ->> 'message_id')::uuid from t_send), 'gm-1', 'gt-1', '<m1@test>');
select pg_temp.check(exists (select 1 from app.activities a join app.activity_types t on t.id = a.type_id where a.id = (select activity_id from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_send))
                             and t.key = 'email' and a.done and a.deal_id = (select id from t_deal)), 'a sent email becomes a done email activity on the deal (COM-02)');
select pg_temp.check(exists (select 1 from app.events where kind = 'email.sent' and subject_id = (select (r ->> 'thread_id')::uuid from t_send)), 'sending emits email.sent');
select pg_temp.check(app.thread_status((select t from app.email_threads t where t.id = (select (r ->> 'thread_id')::uuid from t_send))) = 'waiting_on_contact', 'a thread we started and wrote last waits on the contact');

-- an open, and the reply through sync
select public.worker_track((select track_token from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_send)), 'open', 'human');
select public.worker_track((select track_token from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_send)), 'open', 'prefetch');
select pg_temp.check((select count(*) from app.events where kind = 'email.opened' and subject_id = (select (r ->> 'thread_id')::uuid from t_send)) = 1, 'a prefetch open is stored but emits nothing');
select pg_temp.check(public.worker_track((select token from app.email_tracking_links where message_id = (select (r ->> 'message_id')::uuid from t_send)), 'click', 'human') = 'https://owntheagenda.com/pris', 'a click redirects to the link');
select public.worker_mail_ingest((select id from t_mb), jsonb_build_array(jsonb_build_object('provider_thread_id', 'gt-1', 'provider_message_id', 'gm-2', 'direction', 'in',
  'from', 'Hakon.Aas@valdresfjellst.no', 'from_name', 'Håkon Aas', 'to', jsonb_build_array(jsonb_build_object('address', 'ingrid@orgpuls.no')), 'subject', 'Re: Tilbud', 'body_text', 'Takk, ser bra ut')));
select pg_temp.check(app.thread_status((select t from app.email_threads t where t.id = (select (r ->> 'thread_id')::uuid from t_send))) = 'waiting_on_you', 'a reply makes the thread wait on us');
select pg_temp.check(exists (select 1 from app.events where kind = 'email.received' and subject_id = (select (r ->> 'thread_id')::uuid from t_send)
                             and payload -> 'links' @> jsonb_build_array(jsonb_build_object('entity', 'deal', 'id', (select id from t_deal)))), 'email.received carries the linked deal');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select (x ->> 'unread')::boolean from jsonb_array_elements(public.threads_get('inbox')) x where (x ->> 'id')::uuid = (select (r ->> 'thread_id')::uuid from t_send)), 'the reply is unread for the mailbox owner');
select pg_temp.check(jsonb_array_length(public.thread_get((select (r ->> 'thread_id')::uuid from t_send)) -> 'messages') = 2, 'the thread shows both messages');
select pg_temp.check(not app.thread_unread((select (r ->> 'thread_id')::uuid from t_send), (select id from app.admins where email = 'ingrid@orgpuls.no')), 'opening the thread marks it read');

-- a private thread is not someone else's
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_error(format('select public.thread_get(%L)', (select r ->> 'thread_id' from t_send)), 'not_found', 'another staff member cannot open a private thread');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.rec_list('email_thread') -> 'rows') x where (x ->> 'id')::uuid = (select (r ->> 'thread_id')::uuid from t_send)),
                     'the record API does not list a private thread either');
select pg_temp.as_staff('ingrid@orgpuls.no');
update app.email_threads set visibility = 'shared' where id = (select (r ->> 'thread_id')::uuid from t_send);
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.check(public.thread_get((select (r ->> 'thread_id')::uuid from t_send)) ->> 'id' is not null, 'a shared thread is visible to staff who see deals');

-- scheduling and the outbox
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_sched as select public.email_send(jsonb_build_object('mailbox_id', (select id from t_mb), 'to', '["kari.nordmann@lumio.no"]'::jsonb, 'subject', 'Senere', 'body', 'Hei',
  'send_at', now() + interval '1 hour')) r;
select pg_temp.check((select r ->> 'state' from t_sched) = 'scheduled', 'a message with a time is scheduled');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.outbox_get() -> 'messages') x where x ->> 'id' = (select r ->> 'message_id' from t_sched)), 'the outbox shows it');
update app.email_messages set scheduled_at = now() - interval '1 minute' where id = (select (r ->> 'message_id')::uuid from t_sched);
select app.mail_due();
select pg_temp.check((select state from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_sched)) = 'queued', 'a due scheduled message moves to the queue');
select public.email_change((select (r ->> 'message_id')::uuid from t_sched), 'cancel');
select pg_temp.check((select state from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_sched)) = 'canceled', 'a message not yet sent can be cancelled');

-- group email follows sales_consent
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('sales_consent', 'block');
update app.people set marketing_status = 'unsubscribed' where email = 'kari.nordmann@lumio.no';
select pg_temp.check((select x ->> 'excluded' from jsonb_array_elements(public.group_send_preview(jsonb_build_object('kind', 'people', 'ids', jsonb_build_array((select id from app.people where email = 'kari.nordmann@lumio.no')))) -> 'recipients') x) = 'unsubscribed',
                     'an unsubscribed person is excluded when consent is enforced');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.group_send_preview('{"kind":"people","ids":[]}')$$, 'forbidden', 'group email needs the bulk right');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('sales_consent', 'off');

-- ---------------------------------------------------------------------------
-- the engine
select pg_temp.check(not app.url_public('http://example.com') and not app.url_public('https://10.0.0.5/x') and not app.url_public('https://192.168.1.1')
                 and not app.url_public('https://localhost/x') and not app.url_public('https://169.254.169.254/latest') and not app.url_public('https://[::1]/')
                 and not app.url_public('https://intranet.internal/x') and app.url_public('https://api.example.com/v1/provision'), 'webhooks reach public https addresses only (D-32)');
select pg_temp.expect_error($$select public.workflow_save(null, '{"name":"Bad hook","trigger_type":"event","trigger_config":{"entity":"deal","event":"won"}}',
  '{"steps":[{"key":"h","kind":"webhook","config":{"url":"https://127.0.0.1/x"}}]}')$$, 'invalid', 'a webhook to a private address is refused at save');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.workflow_save(null, '{"name":"x","trigger_type":"event","trigger_config":{"entity":"deal","event":"won"}}', '{"steps":[{"key":"a","kind":"notify","config":{"message":"x"}}]}')$$, 'forbidden', 'building workflows needs the workflows right');

-- deal won → task for the owner and a note
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_wf as select (public.workflow_save(null, '{"name":"Won → handover","trigger_type":"event","trigger_config":{"entity":"deal","event":"won"}}',
  '{"steps":[{"key":"c","kind":"condition","config":{"groups":[[{"f":"value","op":"gt","v":1000}]]}},
             {"key":"t","kind":"create_activity","config":{"type":"task","subject":"Handover {deal.title}","due_in_days":1,"owner":"@record_owner"}},
             {"key":"n","kind":"add_note","config":{"body":"Handover started"}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_wf), 'active');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.deal_status((select id from t_deal), 'won');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select state from app.workflow_runs where workflow_id = (select id from t_wf) order by started_at desc limit 1) = 'completed', 'the run completes');
select pg_temp.check(exists (select 1 from app.activities a where a.deal_id = (select id from t_deal) and a.subject = 'Handover Kvamme Regnskap — HR suite for 3 sites'
                             and a.created_by_workflow = (select id from t_wf) and a.owner_id = (select id from app.admins where email = 'ingrid@orgpuls.no')), 'the task goes to the record owner, with {deal.title} rendered');
select pg_temp.check(exists (select 1 from app.notes where entity = 'deal' and record_id = (select id from t_deal) and body = 'Handover started'
                             and author_id = (select id from app.admins where email = 'tor@orgpuls.no')), 'the note is written as the workflow owner');
select pg_temp.check((select count(*) from app.workflow_run_steps s join app.workflow_runs r on r.id = s.run_id where r.workflow_id = (select id from t_wf) and s.state = 'succeeded') = 3, 'each step is recorded');

-- a condition that does not hold ends the run without acting
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_small as select (public.deal_create(jsonb_build_object('title', 'Liten avtale', 'value', 500, 'pipeline_id', (select id from app.pipelines where name = 'New business'))) ->> 'id')::uuid id;
select public.deal_status((select id from t_small), 'won');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check(exists (select 1 from app.workflow_run_steps s join app.workflow_runs r on r.id = s.run_id where r.subject_id = (select id from t_small) and s.step_key = 'c' and s.state = 'not_met')
                 and not exists (select 1 from app.activities where deal_id = (select id from t_small) and created_by_workflow is not null), 'a condition not met stops the run');

-- a workflow can never do more than its owner: an analyst owner cannot add activities
update app.workflows set owner_id = (select id from app.admins where email = 'ola@orgpuls.no') where id = (select id from t_wf);
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_big as select (public.deal_create(jsonb_build_object('title', 'Stor avtale', 'value', 90000, 'pipeline_id', (select id from app.pipelines where name = 'New business'))) ->> 'id')::uuid id;
select public.deal_status((select id from t_big), 'won');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select state from app.workflow_runs where subject_id = (select id from t_big) order by started_at desc limit 1) = 'failed', 'a step the owner may not do fails the run');
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select id from app.admins where email = 'ola@orgpuls.no') and key = 'workflow.failed'), 'the owner is alerted on failure');
update app.workflows set owner_id = (select id from app.admins where email = 'tor@orgpuls.no') where id = (select id from t_wf);
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_retry as select public.workflow_run_retry((select id from app.workflow_runs where subject_id = (select id from t_big) order by started_at desc limit 1)) r;
select pg_temp.check((select r ->> 'state' from t_retry) = 'completed', 'a retry resumes from the failed step and completes');
select pg_temp.check((select count(*) from app.workflow_run_steps where run_id = (select (r ->> 'id')::uuid from t_retry) and step_key = 'c') = 0, 'the retry does not repeat the steps that succeeded');
select public.workflow_set_state((select id from t_wf), 'draft');

-- a workflow never triggers itself
create temp table t_self as select (public.workflow_save(null, '{"name":"Self","trigger_type":"event","trigger_config":{"entity":"deal","event":"updated"}}',
  '{"steps":[{"key":"u","kind":"update_record","config":{"values":{"source":"workflow"}}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_self), 'active');
select public.rec_save('deal', (select id from t_small), '{"expected_close_date":"2026-12-01"}');
select pg_temp.as_nobody();
select app.dispatch_events(); select app.dispatch_events();
select pg_temp.check((select count(*) from app.workflow_runs where workflow_id = (select id from t_self)) = 1, 'the update a workflow makes does not start it again');
-- and the rolling window caps runs
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('safeguards', 'custom', '', 1);
select public.rec_save('deal', (select id from t_big), '{"expected_close_date":"2026-12-02"}');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select state from app.workflow_runs where workflow_id = (select id from t_self) and subject_id = (select id from t_big)) = 'loop_blocked', 'past the safeguard the run is blocked');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('safeguards', 'source_values');
select public.workflow_set_state((select id from t_self), 'draft');

-- delays and waits resume
create temp table t_wait as select (public.workflow_save(null, '{"name":"Wait","trigger_type":"event","trigger_config":{"entity":"deal","event":"lost"}}',
  '{"steps":[{"key":"d","kind":"delay","config":{"amount":0,"unit":"minutes"}},{"key":"w","kind":"wait_for","config":{"event":"email.replied","timeout_days":7,"then":"continue"}},
             {"key":"n","kind":"notify","config":{"to":"@workflow_owner","message":"Done waiting"}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_wait), 'active');
select public.deal_status((select id from t_small), 'open');
select public.deal_status((select id from t_small), 'lost');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select state from app.workflow_runs where workflow_id = (select id from t_wait)) = 'waiting', 'a delay makes the run wait');
select app.wf_resume_due();
select pg_temp.check((select wait_event from app.workflow_runs where workflow_id = (select id from t_wait)) = 'email.replied', 'after the delay it waits for a reply');
update app.workflow_runs set wait_deadline = now() - interval '1 minute' where workflow_id = (select id from t_wait);
select app.wf_resume_due();
select pg_temp.check((select state from app.workflow_runs where workflow_id = (select id from t_wait)) = 'completed', 'a wait that runs out continues');

-- external steps: queued for the worker; a Slack step needs a connection before activation
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_hook as select (public.workflow_save(null, '{"name":"Hook","trigger_type":"event","trigger_config":{"entity":"deal","event":"reopened"}}',
  '{"steps":[{"key":"h","kind":"webhook","config":{"method":"POST","url":"https://api.example.com/x","body":"{\"orgnr\":\"{deal.org.orgnr}\"}"}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_hook), 'active');
select public.deal_status((select id from t_small), 'open');
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select s.state from app.workflow_run_steps s join app.workflow_runs r on r.id = s.run_id where r.workflow_id = (select id from t_hook)) = 'queued', 'a webhook step is queued for the worker');
select pg_temp.check((select s.request ->> 'body' from app.workflow_run_steps s join app.workflow_runs r on r.id = s.run_id where r.workflow_id = (select id from t_hook)) = '{"orgnr":""}',
                     'the body is rendered, an empty value as an empty string');
select public.worker_step_done((select s.id from app.workflow_run_steps s join app.workflow_runs r on r.id = s.run_id where r.workflow_id = (select id from t_hook)), true, 200, null);
select pg_temp.check((select state from app.workflow_runs where workflow_id = (select id from t_hook)) = 'completed', 'the worker''s answer completes the run');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_slack as select (public.workflow_save(null, '{"name":"Slack","trigger_type":"event","trigger_config":{"entity":"deal","event":"won"}}',
  '{"steps":[{"key":"s","kind":"slack","config":{"message":"Won {deal.title}","channel":"#sales"}}]}') ->> 'id')::uuid id;
select pg_temp.expect_error(format($$select public.workflow_set_state(%L, 'active')$$, (select id from t_slack)), 'invalid', 'a Slack step without a connection cannot be activated');
select pg_temp.check((select blockers from (select app.wf_blockers((select id from t_slack)) blockers) s) = array['not_connected:slack'], 'the blocker names the missing connection');

-- transfer notifies both and is audited; the new owner needs Manage workflows in the workflow's scope
update app.permission_sets set rights = rights || '{deals:workflows}' where key = 'sales';
select public.workflow_transfer((select id from t_slack), (select id from app.admins where email = 'ingrid@orgpuls.no'));
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select id from app.admins where email = 'ingrid@orgpuls.no') and key = 'workflow.transferred_to')
                 and exists (select 1 from app.audit where action = 'workflow.transferred' and target_id = (select id::text from t_slack)), 'a transfer notifies the new owner and is audited');

-- product events reach workflows: payment failed → a billing ticket
create temp table t_pay as select (public.workflow_from_template('payment_failed', 'Payment failed → ticket') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_pay), 'active');
select pg_temp.as_nobody();
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at)
values ('orgpuls', 990001, 'billing.changed', 'orgpuls-o1', '{"payment_state":"past_due","plan":"standard","contact_email":"x@y.no"}', now());
select pg_temp.check((select payload -> 'data' ->> 'payment_state' from app.events where kind = 'billing.changed' order by id desc limit 1) = 'past_due'
                 and (select not (payload -> 'data' ? 'contact_email') from app.events where kind = 'billing.changed' order by id desc limit 1), 'a product event reaches the platform without personal fields');
select app.dispatch_events();
select pg_temp.check(exists (select 1 from app.tickets t join app.organizations o on o.id = t.organization_id where o.name = 'Lumio AS' and t.category_key = 'billing' and t.subject = 'Payment failed: Lumio AS'),
                     'payment failed opens a billing ticket on the organisation');

-- ---------------------------------------------------------------------------
-- assignment
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_rr as select (public.workflow_save(null, jsonb_build_object('name', 'Chatbot and forms', 'kind', 'assignment', 'trigger_config', '{"entities":["lead"]}'::jsonb,
  'options', jsonb_build_object('condition', '{"sources":["chatbot","web form"]}'::jsonb, 'assignee', jsonb_build_object('kind', 'team_rr', 'team_id', (select id from app.teams where name = 'Sales Norway'))))) ->> 'id')::uuid id;
create temp table t_big_rule as select (public.workflow_save(null, jsonb_build_object('name', 'Large orgs', 'kind', 'assignment', 'trigger_config', '{"entities":["lead"]}'::jsonb,
  'options', jsonb_build_object('condition', '{"employees_min":101}'::jsonb, 'assignee', jsonb_build_object('kind', 'user', 'staff_id', (select id from app.admins where email = 'ingrid@orgpuls.no'))))) ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_rr), 'active');
select public.workflow_set_state((select id from t_big_rule), 'active');
select public.assignment_rules_reorder(array[(select id from t_big_rule), (select id from t_rr)]);
select pg_temp.check(public.assignment_test('{"entity":"lead","source":"chatbot","employees":20}') ->> 'rule' = 'Chatbot and forms', 'the test finds the first matching rule');
select pg_temp.check(public.assignment_test('{"entity":"lead","source":"chatbot","employees":150}') ->> 'rule' = 'Large orgs', 'priority decides between two that match');
create temp table t_next as select public.assignment_test('{"entity":"lead","source":"chatbot"}') ->> 'assignee_id' a;
select pg_temp.check((select a from t_next) = public.assignment_test('{"entity":"lead","source":"chatbot"}') ->> 'assignee_id', 'a test does not move the round-robin pointer');
create temp table t_lead as select (public.rec_save('lead', null, jsonb_build_object('title', 'Fra chatbot', 'source', 'chatbot', 'organization_id', (select id from app.organizations where name = 'Lumio AS')), null, null, 'api') ->> 'id')::uuid id;
create temp table t_lead_ui as select (public.rec_save('lead', null, jsonb_build_object('title', 'Lagt inn selv', 'source', 'chatbot', 'organization_id', (select id from app.organizations where name = 'Lumio AS'))) ->> 'id')::uuid id;
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select owner_id::text from app.leads where id = (select id from t_lead)) = (select a from t_next), 'a lead from the API goes to the next in the rotation');
select pg_temp.check(exists (select 1 from app.assignment_evaluations where record_id = (select id from t_lead)) and exists (select 1 from app.notifications where record_id = (select id from t_lead) and key = 'assignment.assigned'),
                     'the assignment is recorded and the assignee notified');
select pg_temp.check((select owner_id from app.leads where id = (select id from t_lead_ui)) = (select id from app.admins where email = 'tor@orgpuls.no'), 'a lead someone created in the app keeps its owner');

-- ---------------------------------------------------------------------------
-- sequences
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_tpl as select (public.template_save(null, '{"name":"Velkommen","subject":"Velkommen, [Person.fornavn]","body":"Hei [Person.fornavn]"}') ->> 'id')::uuid id;
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_seq as select (public.workflow_save(null, '{"name":"Post-demo","kind":"sequence"}',
  jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 'e1', 'kind', 'email_auto', 'config', jsonb_build_object('template_id', (select id from t_tpl), 'from', '@record_owner')),
                                                jsonb_build_object('key', 'd1', 'kind', 'delay', 'config', '{"amount":3,"unit":"days","skip_weekends":true}'::jsonb),
                                                jsonb_build_object('key', 'a1', 'kind', 'activity', 'config', '{"type":"call","subject":"Call: questions?"}'::jsonb)))) ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_seq), 'active');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_sdeal as select (public.deal_create(jsonb_build_object('title', 'Sekvensavtale', 'value', 5000, 'pipeline_id', (select id from app.pipelines where name = 'New business'),
  'person_id', (select id from app.people where email = 'jon.olsen@solstrandhelse.no'))) ->> 'id')::uuid id;
select public.sequence_enroll((select id from t_seq), 'deal', array[(select id from t_sdeal)]);
select pg_temp.check((select state from app.email_messages where enrollment_id = (select id from app.sequence_enrollments where record_id = (select id from t_sdeal))) = 'queued'
                 and (select subject from app.email_messages where enrollment_id = (select id from app.sequence_enrollments where record_id = (select id from t_sdeal))) = 'Velkommen, Jon',
                     'the first email is queued from the template, merged');
select pg_temp.check((select r.state from app.workflow_runs r join app.sequence_enrollments e on e.run_id = r.id where e.record_id = (select id from t_sdeal)) = 'waiting', 'then the delay waits');
select pg_temp.check(public.sequence_enroll((select id from t_seq), 'deal', array[(select id from t_sdeal)]) ->> 'enrolled' = '0', 'a record is enrolled once at a time');
select public.deal_move((select id from t_sdeal), (select id from app.stages where name = 'Demo'));
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select state = 'exited' and exit_reason = 'stage_change' from app.sequence_enrollments where record_id = (select id from t_sdeal)), 'a stage change exits the sequence');
select pg_temp.check((select r.state from app.workflow_runs r join app.sequence_enrollments e on e.run_id = r.id where e.record_id = (select id from t_sdeal)) = 'stopped', 'and stops its run');

-- ---------------------------------------------------------------------------
-- feed
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_od as select (public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'call'), 'subject', 'Ring tilbake',
  'deal_id', (select id from t_sdeal), 'starts_at', now() - interval '2 days')) ->> 'id')::uuid id;
select pg_temp.as_nobody();
select app.feed_checks();
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.feed_get('overlooked') -> 'cards') x where x ->> 'kind' = 'overdue_activity' and x -> 'params' ->> 'subject' = 'Ring tilbake'),
                     'an overdue activity on my deal is an overlooked card');
select pg_temp.as_nobody();
insert into app.email_links (thread_id, entity, record_id, linked_by) values ((select (r ->> 'thread_id')::uuid from t_send), 'deal', (select id from t_sdeal), 'manual');
select public.worker_mail_ingest((select id from t_mb), jsonb_build_array(jsonb_build_object('provider_thread_id', 'gt-1', 'provider_message_id', 'gm-3', 'direction', 'in',
  'from', 'hakon.aas@valdresfjellst.no', 'subject', 'Re: Tilbud', 'body_text', 'Et spørsmål til')));
select app.dispatch_events();
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.feed_get('follow_ups') -> 'cards') x where x ->> 'kind' = 'email_reply' and x -> 'deal' ->> 'id' = (select id::text from t_sdeal)),
                     'a reply on my open deal is a follow-up card');
select public.activity_done((select id from t_od), true);
select pg_temp.as_nobody();
select app.dispatch_events();
select pg_temp.check((select resolved_by from app.feed_cards where source_id = (select id from t_od) and kind = 'overdue_activity') = 'done', 'completing the activity resolves the card');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_card as select id from app.feed_cards where staff_id = (select id from app.admins where email = 'ingrid@orgpuls.no') and resolved_at is null and deal_id is not null limit 1;
create temp table t_res as select public.feed_resolve((select id from t_card), 'task') r;
select pg_temp.check(exists (select 1 from app.activities a join app.activity_types t on t.id = a.type_id where a.id = (select (r ->> 'activity_id')::uuid from t_res) and t.key = 'task'
                             and a.owner_id = (select id from app.admins where email = 'ingrid@orgpuls.no') and a.starts_at > now()), 'Schedule task creates my task on the deal');
select pg_temp.check((public.feed_progress() ->> 'done_today')::int >= 1, 'a resolved card counts as done today');
select pg_temp.check((public.feed_progress() -> 'month' ->> 'won_count')::int = (select count(*) from app.deals where owner_id = (select id from app.admins where email = 'ingrid@orgpuls.no')
                     and status = 'won' and won_at >= date_trunc('month', now() at time zone 'Europe/Oslo') at time zone 'Europe/Oslo' and not is_sample), 'won this month is counted from the deals');

-- ai_scoring off hides AI cards and scores
select pg_temp.as_nobody();
insert into app.feed_cards (staff_id, kind, deal_id, params, dedupe_key) values ((select id from app.admins where email = 'ingrid@orgpuls.no'), 'likely_to_advance', (select id from t_sdeal), '{"reason":"x"}', 'test:ai');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.feed_get('suggestions') -> 'cards') x where x ->> 'kind' = 'likely_to_advance'), 'an AI card shows while AI scoring is on');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('ai_scoring', 'off');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.feed_get('suggestions') -> 'cards') x where x ->> 'kind' = 'likely_to_advance'), 'with AI scoring off the card is hidden');
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('ai_scoring', 'on');

-- ---------------------------------------------------------------------------
-- scoring
create temp table t_model as select (public.score_model_save(null, jsonb_build_object('name', 'Deal fit', 'entity', 'deal', 'pipeline_id', (select id from app.pipelines where name = 'New business')),
  '[{"group":"high","label":"Employees 26–250","condition":[[{"rel":"organization_id","f":"employees","op":"gte","v":26},{"rel":"organization_id","f":"employees","op":"lte","v":250}]]},
    {"group":"negative","label":"Payment past due","condition":[[{"f":"org_payment","v":"past_due"}]]}]') ->> 'id')::uuid id;
select public.score_model_activate((select id from t_model), true);
create temp table t_sc as select d.id from app.deals d join app.organizations o on o.id = d.organization_id join app.pipelines p on p.id = d.pipeline_id
  where p.name = 'New business' and d.status = 'open' and d.deleted_at is null and o.employees between 26 and 250 and not exists (select 1 from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id where ap.account_id = o.account_id and s.payment_state = 'past_due') limit 1;
select pg_temp.check((select score from app.deals where id = (select id from t_sc)) = 25, 'an active model scores open deals in its pipeline from base 0');
select pg_temp.check(jsonb_array_length(public.score_preview((select id from t_model), (select id from t_sc)) -> 'hits') = 1, 'the preview names the criteria that hold');
create temp table t_model2 as select (public.score_model_save(null, jsonb_build_object('name', 'Other', 'entity', 'deal', 'pipeline_id', (select id from app.pipelines where name = 'New business')), '[]') ->> 'id')::uuid id;
select public.score_model_activate((select id from t_model2), true);
select pg_temp.check((select state from app.score_models where id = (select id from t_model)) = 'draft', 'one active model per pipeline');

-- ---------------------------------------------------------------------------
-- enrichment and calls
select pg_temp.as_staff('tor@orgpuls.no');
update app.organizations set nace = null, website = 'https://kvamme.no' where id = (select organization_id from t_deal);
select public.enrich_request(array[(select organization_id from t_deal)]);
create temp table t_er as select id from app.enrichment_requests where record_id = (select organization_id from t_deal) and state = 'requested';
select pg_temp.as_nobody();
select public.worker_enrich_done((select id from t_er), '{"nace":"69.201","website":"https://other.no","employees":60,"secret":"x"}');
select pg_temp.as_staff('tor@orgpuls.no');
select public.enrich_apply((select id from t_er), array['nace', 'website']);
select pg_temp.check((select nace = '69.201' and website = 'https://kvamme.no' from app.organizations where id = (select organization_id from t_deal)), 'enrichment fills empty fields and leaves filled ones');
select pg_temp.check(exists (select 1 from app.changelog where record_id = (select organization_id from t_deal) and field = 'nace' and source = 'enrichment'), 'the history says the value came from enrichment');
select pg_temp.expect_error(format('select public.enrich_person(%L)', (select person_id from t_deal)), 'not_connected', 'person enrichment needs the contact-data provider');
create temp table t_call as select public.call_log_save(jsonb_build_object('person_id', (select id from app.people where email = 'kari.nordmann@lumio.no'), 'number', '+47 505 61 574',
  'direction', 'outbound', 'outcome', 'connected', 'duration_s', 240, 'note', 'Snakket om fornyelse')) r;
select pg_temp.check(exists (select 1 from app.activities a join app.activity_types t on t.id = a.type_id join app.call_logs c on c.activity_id = a.id
                             where a.id = (select (r ->> 'activity_id')::uuid from t_call) and t.key = 'call' and a.done and c.outcome = 'connected'), 'a call logged by hand is a done call activity');
select pg_temp.check(public.phone_match('50561574') -> 0 ->> 'name' = 'Kari Nordmann', 'a number finds its person');

rollback;
