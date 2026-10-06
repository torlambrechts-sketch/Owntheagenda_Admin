-- phase5_capture_invariants.sql — lead capture (0031): consent wording and suppressions, web forms, chat, prospect
-- reveals and web visitors. Ids and counts only in the audit and the outbox; no IP; tokens as SHA-256.
\ir _helpers.psql
begin;

-- expect_state(sql, sqlstate, label): the statement must fail with this SQLSTATE (a constraint, not a function's message)
create or replace function pg_temp.expect_state(p_sql text, p_state text, p_label text) returns void language plpgsql as $$
declare v text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v = returned_sqlstate;
    if v = p_state then raise notice 'ok %', p_label; return; end if;
    raise exception 'FAIL %: expected SQLSTATE %, got % (%)', p_label, p_state, v, sqlerrm;
  end;
  raise exception 'FAIL %: expected SQLSTATE %, but it succeeded', p_label, p_state;
end $$;

-- the detail of a function's error, to see which field was refused
create or replace function pg_temp.error_detail(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v = pg_exception_detail;
  return sqlerrm || ':' || coalesce(v, '');
end $$;

-- ---------------------------------------------------------------------------
-- structure: every new table closed to clients; workers are the service role's; no IP, tokens as hashes
create temp table t_tables (t text);
insert into t_tables values ('consent_texts'), ('consent_confirmations'), ('suppressions'), ('forms'), ('form_versions'), ('form_submissions'),
  ('form_stats_daily'), ('chat_playbooks'), ('chat_playbook_versions'), ('chat_conversations'), ('chat_messages'), ('chat_presence'),
  ('prospect_reveals'), ('web_companies');
select pg_temp.check((select count(*) from t_tables join pg_class c on c.relname = t_tables.t and c.relnamespace = 'app'::regnamespace and c.relrowsecurity) = 14,
                     'every capture table has row level security on');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g join t_tables on t_tables.t = g.table_name
                                 where g.table_schema = 'app' and g.grantee in ('anon', 'authenticated', 'PUBLIC')), 'no client role has a grant on a capture table');
select pg_temp.check(not exists (select 1 from pg_policies p join t_tables on t_tables.t = p.tablename where p.schemaname = 'app'), 'no capture table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.columns c join t_tables on t_tables.t = c.table_name
                                 where c.table_schema = 'app' and (c.column_name ~ '(^|_)(ip|ip_address|user_agent)($|_)'
                                                                   or (c.column_name ~ 'token' and c.column_name !~ '_sha256$'))),
                     'no capture table stores an IP, a user agent or a plaintext token');
select pg_temp.check((select data_type from information_schema.columns where table_schema = 'app' and table_name = 'chat_conversations' and column_name = 'visitor_token_sha256') = 'bytea'
                 and (select data_type from information_schema.columns where table_schema = 'app' and table_name = 'consent_confirmations' and column_name = 'token_sha256') = 'bytea',
                     'conversation and confirmation tokens are stored as SHA-256 only');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'worker\_%'
                                 and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
                     'every worker function belongs to the service role');
select pg_temp.check(has_function_privilege('service_role', 'public.worker_form_submit(text, jsonb, jsonb)', 'execute')
                 and has_function_privilege('service_role', 'public.worker_chat_start(text, text, text, text)', 'execute'), 'the edge functions can call the workers');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                 and p.proname in ('consent_log', 'suppressions_get', 'suppression_add', 'suppression_remove', 'marketing_status_summary', 'forms_get',
                                                   'form_get', 'form_create', 'form_save', 'form_publish', 'form_set_status', 'form_delete', 'form_stats', 'form_submissions',
                                                   'playbooks_get', 'playbook_save', 'playbook_publish', 'chats_queue', 'chat_get', 'chat_claim', 'chat_send', 'chat_close',
                                                   'prospect_search', 'prospect_reveal', 'prospect_usage', 'visitors_get', 'visitor_get', 'visitor_convert',
                                                   'web_sites_get', 'web_site_save', 'consent_set')
                                 and (not p.prosecdef or not coalesce('search_path=""' = any (p.proconfig), false) or not has_function_privilege('authenticated', p.oid, 'execute')
                                      or has_function_privilege('anon', p.oid, 'execute'))),
                     'the capture RPCs are security definers with an empty search path, for signed-in staff only');
select pg_temp.check(not exists (select 1 from information_schema.columns c where c.table_schema = 'app'
                                 and c.column_name ~ '(^|_)(answer|answers|respondent|respondents)(_|$)'), 'no capture column is named for answers or respondents (D-34)');
select pg_temp.check(exists (select 1 from app.entities where key = 'form' and tbl = 'forms' and scope = 'campaigns' and module = 'leadgen' and owned), 'form is a record type');

-- ---------------------------------------------------------------------------
-- consent: archived, the status before, the address's hash, the reference; the wording is append-only
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_p as select (public.rec_save('person', null, '{"name":"Consent Person","email":"Consent.P5@example.no"}') ->> 'id')::uuid id;
select public.consent_set((select id from t_p), 'subscribed', 'Event', 'Signed up at the stand');
select public.consent_set((select id from t_p), 'archived', 'List hygiene', null, 'list_hygiene');
select pg_temp.check((select marketing_status from app.people where id = (select id from t_p)) = 'archived', 'archived is a marketing status (Q2)');
select pg_temp.check(exists (select 1 from app.consent_events where person_id = (select id from t_p) and status = 'archived' and prev_status = 'subscribed'
                             and ref_type = 'list_hygiene' and email_sha256 = extensions.digest('consent.p5@example.no', 'sha256')),
                     'a consent row records the status before, the reference and the address it concerns');
select pg_temp.expect_error(format('select public.consent_set(%L, %L, %L)', (select id from t_p), 'maybe', 'x'), 'invalid', 'an unknown status is refused');
select public.consent_set((select id from t_p), 'subscribed', 'Event', 'Again');
select public.rec_save('person', (select id from t_p), '{"email":"new.address.p5@example.no"}');
select pg_temp.check((select marketing_status from app.people where id = (select id from t_p)) = 'no_consent'
                 and exists (select 1 from app.consent_events where person_id = (select id from t_p) and source = 'email_changed' and status = 'no_consent'
                             and email_sha256 = extensions.digest('new.address.p5@example.no', 'sha256')),
                     'a new address does not inherit the old one''s consent (CMP-04)');
select pg_temp.expect_error($$update app.consent_texts set body = 'Changed' where key = 'newsletter' and locale = 'nb'$$, 'consent wording is append-only', 'the wording shown cannot be edited');
select public.consent_text_save('newsletter', 'nb', 'Ja, send meg nyhetsbrev fra oss');
select pg_temp.check((select max(version) from app.consent_texts where key = 'newsletter' and locale = 'nb') = 2, 'a new wording is a new version');
select pg_temp.check(jsonb_array_length(public.consent_log(10) -> 'rows') between 1 and 10 and (public.consent_log(10) -> 'rows' -> 0) ? 'prev_status', 'the consent log lists the changes');
select pg_temp.check((select sum((x ->> 'n')::int) from jsonb_array_elements(public.marketing_status_summary() -> 'statuses') x)
                     = (select count(*) from app.people where email is not null and deleted_at is null and not is_sample), 'the summary counts every address once');

-- suppressions: hashes, added and lifted with campaigns:bulk; an unsubscribe cannot be lifted by staff
select public.suppression_add('Blocked.P5@example.no', null);
select pg_temp.check(exists (select 1 from app.suppressions where email_sha256 = extensions.digest('blocked.p5@example.no', 'sha256') and reason = 'manual'),
                     'a suppression is the address''s hash');
insert into app.suppressions (email_sha256, scope, reason) values (extensions.digest('gone.p5@example.no', 'sha256'), 'marketing', 'unsubscribed');
select pg_temp.expect_error($$select public.suppression_remove('gone.p5@example.no', 'marketing')$$, 'invalid', 'an unsubscribe suppression is not lifted by staff');
select public.suppression_remove('blocked.p5@example.no', 'marketing');
select pg_temp.check(not exists (select 1 from app.suppressions where email_sha256 = extensions.digest('blocked.p5@example.no', 'sha256')), 'a manual suppression can be lifted');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(jsonb_typeof(public.consent_log(5) -> 'rows') = 'array', 'the read-only analyst sees the consent log');
select pg_temp.expect_error($$select public.suppression_add('x.p5@example.no')$$, 'forbidden', 'the analyst cannot suppress an address');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.consent_log(5)$$, 'forbidden', 'Sales without campaigns:see cannot read the consent log');

-- ---------------------------------------------------------------------------
-- forms: create, draft rules, rights
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.check(jsonb_typeof(public.forms_get()) = 'array', 'campaigns:see lists the forms');
select pg_temp.expect_error($$select public.form_create('contact', 'Nope')$$, 'forbidden', 'the analyst cannot create a form');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_f as select (public.form_create('contact', 'Kontakt oss P5', 'nb') ->> 'id')::uuid id;
select pg_temp.check((select draft #>> '{fields,0,label}' from app.forms where id = (select id from t_f)) = 'Navn'
                 and (select draft #>> '{intro,title}' from app.forms where id = (select id from t_f)) = 'Kontakt oss P5'
                 and (select draft #>> '{after_submit,ticket}' from app.forms where id = (select id from t_f)) = 'true', 'a contact form starts with the design''s fields and a Sales ticket');
select pg_temp.expect_error(format('select public.form_save(%L, %L, null)', (select id from t_f), '{"fields":[]}'), 'invalid', 'the introduction cannot be removed (LGN-03)');
select pg_temp.check(pg_temp.error_detail(format('select public.form_save(%L, (select draft from app.forms where id = %L) || %L, null)', (select id from t_f), (select id from t_f),
                     '{"hidden":["utm","cookie_id"]}')) = 'invalid:hidden', 'no cookie id among the tracking fields (Q7, D-37)');
select pg_temp.expect_error(format('select public.form_save(%L, (select draft from app.forms where id = %L) || %L, null)', (select id from t_f), (select id from t_f),
                     '{"consent":{"text_key":"newsletter","double_opt_in":false}}'), 'invalid', 'a form cannot turn double opt-in off (Q3)');
select pg_temp.expect_error(format('select public.form_save(%L, %L, 99)', (select id from t_f), '{}'), 'version_conflict', 'a stale version is refused');
select pg_temp.expect_error(format('select public.form_set_status(%L, %L)', (select id from t_f), 'active'), 'invalid', 'an unpublished form cannot be activated');
select pg_temp.expect_error(format('update app.forms set language = %L where id = %L', 'en', (select id from t_f)), 'invalid', 'a form''s language is fixed at creation');
create temp table t_fu as select (public.form_create('file_upload', 'Opplasting P5', 'nb') ->> 'id')::uuid id;
select public.form_save((select id from t_fu), (select draft - 'notice' from app.forms where id = (select id from t_fu)), null);
select pg_temp.check((select draft ->> 'notice' from app.forms where id = (select id from t_fu)) = 'employee_list',
                     'a file-upload form keeps the fixed notice that employee lists belong in the product (Q8)');
select pg_temp.check(not exists (select 1 from app.forms where lower(name) like '%ansattlist%'), 'no employee-list form is seeded');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format('select public.form_publish(%L)', (select id from t_f)), 'forbidden', 'Sales cannot publish a form (campaigns:configure)');
select pg_temp.expect_error($$select public.forms_get()$$, 'forbidden', 'Sales without campaigns:see does not reach the forms');

-- publishing freezes a version
select pg_temp.as_staff('tor@orgpuls.no');
select public.form_publish((select id from t_f));
select public.form_set_status((select id from t_f), 'active');
create temp table t_fv as select definition from app.form_versions where form_id = (select id from t_f) and version = 1;
select public.form_save((select id from t_f), (select draft from app.forms where id = (select id from t_f)) || '{"intro":{"title":"Ny tittel","body":""}}', null);
select pg_temp.check((select definition from app.form_versions where form_id = (select id from t_f) and version = 1) = (select definition from t_fv)
                 and (select current_version from app.forms where id = (select id from t_f)) = 1, 'editing the draft leaves the published version as it was');
select pg_temp.expect_error(format('update app.form_versions set definition = %L where form_id = %L', '{}', (select id from t_f)), 'a published form version is fixed',
                            'a published version cannot be changed');
create temp table t_pub as select public_id from app.forms where id = (select id from t_f);

-- ---------------------------------------------------------------------------
-- the public side: views, a submission, consent pending under double opt-in, the lead, the ticket
select pg_temp.as_nobody();
select public.worker_form_event((select public_id from t_pub), 'view');
select public.worker_form_event((select public_id from t_pub), 'view');
select public.worker_form_event((select public_id from t_pub), 'start');
select pg_temp.check((select views from app.form_stats_daily where form_id = (select id from t_f)) = 2
                 and (select starts from app.form_stats_daily where form_id = (select id from t_f)) = 1, 'views and starts are counted, without a visitor id');
select pg_temp.check((public.worker_form_definition((select public_id from t_pub)) #>> '{consent,body}') = 'Ja, send meg nyhetsbrev fra oss'
                 and not (public.worker_form_definition((select public_id from t_pub)) -> 'fields' -> 0 ? 'map'), 'the public definition shows the wording, not the mapping');
create temp table t_s1 as select public.worker_form_submit((select public_id from t_pub),
  '{"name":"Kari Formsen","email":"Kari.Form.P5@Example.no","phone":"+47 900 00 000","org_number":"923 609 016","message":"Hemmelig melding 4711","consent":true}',
  jsonb_build_object('fill_ms', 9000, 'consent_text_id', (select id from app.consent_texts where key = 'newsletter' and locale = 'nb' and version = 2),
                     'tracking', '{"utm":{"utm_source":"linkedin","utm_campaign":"host","evil":"x"},"referrer_host":"www.linkedin.com","landing_path":"/kontakt","cookie_id":"abc"}'::jsonb)) r;
create temp table t_sub as select * from app.form_submissions where form_id = (select id from t_f) and state = 'accepted';
select pg_temp.check((select count(*) from t_sub) = 1 and (select form_version from t_sub) = 1 and (select field_values ->> 'message' from t_sub) = 'Hemmelig melding 4711',
                     'a submission stores its values against the published version');
select pg_temp.check((select tracking from t_sub) = '{"utm":{"utm_source":"linkedin","utm_campaign":"host"},"referrer_host":"www.linkedin.com","landing_path":"/kontakt"}'::jsonb,
                     'tracking keeps UTM, referrer host and landing path, and nothing undeclared');
select pg_temp.check((select p.email from app.people p where p.id = (select person_id from t_sub)) = 'kari.form.p5@example.no'
                 and (select p.contact_type from app.people p where p.id = (select person_id from t_sub)) = 'prospect', 'the person is found or created by lower(email)');
select pg_temp.check((select o.org_number from app.organizations o where o.id = (select organization_id from t_sub)) = '923609016'
                 and exists (select 1 from app.enrichment_requests r where r.record_id = (select organization_id from t_sub) and r.provider = 'brreg'),
                     'the organization is made by org number and Brønnøysund enrichment is queued');
select pg_temp.check((select l.source from app.leads l where l.id = (select lead_id from t_sub)) = 'Web form'
                 and (select l.form_data ->> 'message' from app.leads l where l.id = (select lead_id from t_sub)) = 'Hemmelig melding 4711'
                 and (select c.source from app.changelog c where c.entity = 'lead' and c.record_id = (select lead_id from t_sub) and c.field = '*created') = 'capture',
                     'a lead is created with source «Web form», the values and the history source capture (LGN-03, V-20)');
select pg_temp.check((select t.queue_key from app.tickets t where t.id = (select ticket_id from t_sub)) = 'sales'
                 and exists (select 1 from app.ticket_messages m where m.ticket_id = (select ticket_id from t_sub) and m.kind = 'customer' and m.body = 'Hemmelig melding 4711')
                 and exists (select 1 from app.ticket_links k where k.ticket_id = (select ticket_id from t_sub) and k.kind = 'lead' and k.ref = (select lead_id from t_sub)::text),
                     'a contact form makes a Sales ticket with the message in the thread, linked to the lead');
select pg_temp.check((select marketing_status from app.people where id = (select person_id from t_sub)) = 'pending'
                 and exists (select 1 from app.consent_events c where c.person_id = (select person_id from t_sub) and c.status = 'pending' and c.basis = 'consent'
                             and c.ref_type = 'form_submission' and c.ref_id = (select id from t_sub)
                             and c.text_id = (select id from app.consent_texts where key = 'newsletter' and locale = 'nb' and version = 2)),
                     'a ticked box under double opt-in is pending, with the wording version shown and the submission as reference');
select pg_temp.check((select r ->> 'confirm_token' from t_s1) is not null
                 and exists (select 1 from app.consent_confirmations c where c.token_sha256 = extensions.digest((select r ->> 'confirm_token' from t_s1), 'sha256')
                             and c.person_id = (select person_id from t_sub) and c.confirmed_at is null and c.expires_at > now() + interval '6 days'),
                     'the confirmation link is returned once and stored as its hash, valid seven days');
select pg_temp.check((select submissions from app.form_stats_daily where form_id = (select id from t_f)) = 1, 'the submission is counted');
select pg_temp.check(exists (select 1 from app.events e where e.kind = 'form.submitted' and e.subject_type = 'lead' and e.subject_id = (select lead_id from t_sub)
                             and e.payload ->> 'submission' = (select id from t_sub)::text and e.payload ->> 'ticket' = (select ticket_id from t_sub)::text),
                     'form.submitted is emitted on the lead with ids');

-- confirmation
select pg_temp.expect_error($$select public.worker_consent_confirm('not-a-token')$$, 'not_found', 'an unknown confirmation token is not found');
select public.worker_consent_confirm((select r ->> 'confirm_token' from t_s1));
select pg_temp.check((select marketing_status from app.people where id = (select person_id from t_sub)) = 'subscribed'
                 and exists (select 1 from app.consent_events c where c.person_id = (select person_id from t_sub) and c.status = 'subscribed' and c.prev_status = 'pending'
                             and c.ref_type = 'confirmation'), 'confirming the link subscribes the address');
select pg_temp.check((public.worker_consent_confirm((select r ->> 'confirm_token' from t_s1)) ->> 'already')::boolean, 'a used link changes nothing');

-- a resubmission updates the open lead; identical values are a duplicate; a honeypot is spam
select public.worker_form_submit((select public_id from t_pub),
  '{"name":"Kari Formsen","email":"kari.form.p5@example.no","org_number":"923609016","message":"Andre melding"}', '{"fill_ms":5000}');
select pg_temp.check((select count(distinct lead_id) from app.form_submissions where form_id = (select id from t_f) and state = 'accepted') = 1
                 and (select l.form_data ->> 'message' from app.leads l where l.id = (select lead_id from t_sub)) = 'Andre melding',
                     'a resubmission updates the open lead from the same form (SF-17 step 6)');
select public.worker_form_submit((select public_id from t_pub),
  '{"name":"Kari Formsen","email":"kari.form.p5@example.no","org_number":"923609016","message":"Andre melding"}', '{"fill_ms":5000}');
select pg_temp.check(exists (select 1 from app.form_submissions where form_id = (select id from t_f) and state = 'duplicate' and field_values = '{}'
                             and lead_id = (select lead_id from t_sub)), 'identical values within a day are a duplicate, stored without content');
select public.worker_form_submit((select public_id from t_pub), '{"name":"Bot","email":"bot.p5@example.no","org_number":"923609016"}', '{"honeypot":"filled"}');
select public.worker_form_submit((select public_id from t_pub), '{"name":"Fast","email":"fast.p5@example.no","org_number":"923609016"}', '{"fill_ms":300}');
select pg_temp.check((select count(*) from app.form_submissions where form_id = (select id from t_f) and state = 'spam' and field_values = '{}' and person_id is null) = 2
                 and not exists (select 1 from app.people where email in ('bot.p5@example.no', 'fast.p5@example.no')),
                     'a honeypot or a too-fast fill is spam: no person, no lead, no content');
select pg_temp.expect_error(format('select public.worker_form_submit(%L, %L)', (select public_id from t_pub), '{"email":"x.p5@example.no","password":"x"}'),
                            'invalid', 'a value for a field the version does not have is refused');
select pg_temp.expect_error(format('select public.worker_form_submit(%L, %L, %L)', (select public_id from t_pub), '{"name":"Nei","email":"not-an-address","org_number":"923609016"}', '{"fill_ms":5000}'),
                            'invalid', 'an invalid address is refused');

-- form_tracking off stores no tracking; double opt-in off subscribes at once
insert into app.setting_values (key, scope_id, value) values ('form_tracking', '', 'off'), ('double_opt_in', '', 'off')
on conflict (key, scope_id) do update set value = excluded.value;
create temp table t_s2 as select public.worker_form_submit((select public_id from t_pub),
  '{"name":"Ola Sporløs","email":"ola.sporlos.p5@example.no","org_number":"923609016","consent":true}',
  '{"fill_ms":5000,"tracking":{"utm":{"utm_source":"x"},"landing_path":"/kontakt"}}') r;
select pg_temp.check((select tracking from app.form_submissions s join app.people p on p.id = s.person_id where p.email = 'ola.sporlos.p5@example.no') = '{}'::jsonb,
                     'with form_tracking off a submission stores no tracking');
select pg_temp.check((select marketing_status from app.people where email = 'ola.sporlos.p5@example.no') = 'subscribed' and (select r ->> 'confirm_token' from t_s2) is null,
                     'with double opt-in off a ticked box subscribes at once');
select pg_temp.check((public.worker_form_definition((select public_id from t_pub)) -> 'hidden') = '[]'::jsonb, 'the public form asks for no tracking while it is off');
delete from app.setting_values where key in ('form_tracking', 'double_opt_in') and scope_id = '';

-- an inactive form takes nothing
select pg_temp.as_staff('tor@orgpuls.no');
select public.form_set_status((select id from t_f), 'inactive');
select pg_temp.as_nobody();
select pg_temp.expect_error(format('select public.worker_form_submit(%L, %L, %L)', (select public_id from t_pub), '{"name":"Sent","email":"late.p5@example.no","org_number":"923609016"}', '{"fill_ms":5000}'),
                            'not_found', 'a submission on an inactive form is refused');
select pg_temp.expect_error(format('select public.worker_form_definition(%L)', (select public_id from t_pub)), 'not_found', 'an inactive form is not served');

select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select (x ->> 'submissions_month')::int from jsonb_array_elements(public.forms_get()) x where (x ->> 'id')::uuid = (select id from t_f)) = 3
                 and (select (x ->> 'landing') from jsonb_array_elements(public.forms_get()) x where (x ->> 'id')::uuid = (select id from t_f)) = '/kontakt',
                     'the form list counts this month''s submissions and names the landing page');
select pg_temp.check((public.form_stats((select id from t_f), 7) ->> 'conversion')::numeric = 1.5, 'conversion is submissions over views');
select pg_temp.check((select x ->> 'values' from jsonb_array_elements(public.form_submissions((select id from t_f))) x where x ->> 'state' = 'spam' limit 1) is null
                 and exists (select 1 from jsonb_array_elements(public.form_submissions((select id from t_f))) x where x -> 'values' ->> 'message' = 'Andre melding'),
                     'staff read the values through the lead; spam carries none');

-- ---------------------------------------------------------------------------
-- the products' contact.submitted takes the same path: a ticket and, now, a lead (D-20)
select pg_temp.as_nobody();
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at)
values ('orgpuls', 999531, 'contact.submitted', 'orgpuls-o1', '{"subject":"Kontakt fra nettsiden P5","message":"Ring meg","email":"kontakt.p5@example.no","name":"Kontakt Person"}', now());
select pg_temp.check(exists (select 1 from app.tickets t join app.ticket_links k on k.ticket_id = t.id and k.kind = 'lead'
                             join app.leads l on l.id::text = k.ref
                             where t.subject = 'Kontakt fra nettsiden P5' and t.channel = 'contact_form' and l.source = 'Contact form'),
                     'contact.submitted becomes a ticket and a lead');

-- ---------------------------------------------------------------------------
-- chat: a playbook, the bot flow, the claim, the transcript
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format('select public.web_site_save(%L, %L)', (select id from app.web_sites where hostname = 'orgpuls.com'), '{"chat_enabled":true}'),
                            'forbidden', 'Sales cannot configure a site (campaigns:configure)');
select pg_temp.as_staff('tor@orgpuls.no');
select public.web_site_save((select id from app.web_sites where hostname = 'orgpuls.com'), '{"chat_enabled":true}');
select pg_temp.expect_error($$select public.web_site_save(null, '{"hostname":"svar.orgpuls.no"}')$$, 'invalid', 'a survey host can never be a tracked site');
create temp table t_pb as select (public.playbook_save(null, jsonb_build_object('name', 'Leads P5', 'template', 'leads', 'pages', '["/pris*"]'::jsonb,
  'steps', '[{"key":"hello","kind":"message","text":"Hei!"},{"key":"name","kind":"question","text":"Hva heter du?","map":"person.name"},
             {"key":"email","kind":"question","text":"E-post?","map":"person.email"},{"key":"thanks","kind":"message","text":"Takk!"}]'::jsonb)) ->> 'id')::uuid id;
select pg_temp.expect_error(format('select public.playbook_set_state(%L, %L)', (select id from t_pb), 'live'), 'invalid', 'an unpublished playbook cannot go live');
select public.playbook_publish((select id from t_pb));
select public.playbook_set_state((select id from t_pb), 'live');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format('select public.playbook_publish(%L)', (select id from t_pb)), 'forbidden', 'Sales cannot publish a playbook');

select pg_temp.as_nobody();
select pg_temp.expect_error($$select public.worker_chat_start('owntheagenda-com', '/pris', null, 'nb')$$, 'not_found', 'chat starts only on a site with chat on');
create temp table t_c1 as select public.worker_chat_start('orgpuls-com', '/priser', '923609016', 'nb') r;
create temp table t_cv as select * from app.chat_conversations where visitor_token_sha256 = extensions.digest((select r ->> 'token' from t_c1), 'sha256');
select pg_temp.check((select count(*) from t_cv) = 1 and (select company_org_number from t_cv) = '923609016' and (select last_step_key from t_cv) = 'name'
                 and (select jsonb_array_length(r -> 'messages') from t_c1) = 2, 'a chat starts with the bot''s first question, keyed by the token''s hash');
select public.worker_chat_message((select r ->> 'token' from t_c1), 'Kari Chattesen');
select pg_temp.check((select last_step_key from app.chat_conversations where id = (select id from t_cv)) = 'email', 'an answer moves the bot to the next question');
select public.worker_chat_message((select r ->> 'token' from t_c1), 'Kari.Chat.P5@example.no');
create temp table t_cv2 as select * from app.chat_conversations where id = (select id from t_cv);
select pg_temp.check((select completed from t_cv2) and (select l.source from app.leads l where l.id = (select lead_id from t_cv2)) = 'Chatbot'
                 and (select l.form_data ->> 'name' from app.leads l where l.id = (select lead_id from t_cv2)) = 'Kari Chattesen'
                 and (select p.email from app.people p where p.id = (select person_id from t_cv2)) = 'kari.chat.p5@example.no',
                     'a completed conversation creates a lead with the answers stored (LGN-01)');
select pg_temp.check(exists (select 1 from app.events where kind = 'chat.completed' and subject_type = 'lead' and subject_id = (select lead_id from t_cv2)
                             and payload ->> 'conversation' = (select id from t_cv2)::text), 'chat.completed is emitted on the lead');
select pg_temp.expect_error($$select public.worker_chat_poll('nope', 0)$$, 'not_found', 'an unknown chat token is not found');

-- live chat: the first claim wins; the panel is read-only for everyone else
create temp table t_c2 as select public.worker_chat_start('orgpuls-com', '/pris', null, null) r;
create temp table t_cid as select id from app.chat_conversations where visitor_token_sha256 = extensions.digest((select r ->> 'token' from t_c2), 'sha256');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error(format('select public.chat_claim(%L)', (select id from t_cid)), 'forbidden', 'the analyst cannot take over a chat (deals:add)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.chats_queue() -> 'rows') x where (x ->> 'id')::uuid = (select id from t_cid)), 'Sales sees the chat in the queue');
select public.chat_presence_set(true);
select public.chat_claim((select id from t_cid));
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(pg_temp.error_detail(format('select public.chat_claim(%L)', (select id from t_cid))) = 'invalid:claimed', 'a claimed chat is locked to one rep (LGN-02)');
select pg_temp.check(pg_temp.error_detail(format('select public.chat_send(%L, %L)', (select id from t_cid), 'Hei fra Tor')) = 'invalid:claimed', 'another rep cannot write in it');
select pg_temp.check((public.chat_get((select id from t_cid)) ->> 'read_only')::boolean, 'the panel is read-only for another rep');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.chat_send((select id from t_cid), 'Hei, Ingrid her');
select pg_temp.as_nobody();
select public.worker_chat_message((select r ->> 'token' from t_c2), 'Min e-post er live.chat.p5@example.no');
select pg_temp.check((public.worker_chat_poll((select r ->> 'token' from t_c2), 0) ->> 'state') = 'live'
                 and (public.worker_chat_poll((select r ->> 'token' from t_c2), 0) ->> 'online')::boolean
                 and exists (select 1 from jsonb_array_elements(public.worker_chat_poll((select r ->> 'token' from t_c2), 0) -> 'messages') m
                             where m ->> 'sender' = 'staff' and m ->> 'body' = 'Hei, Ingrid her'), 'the visitor''s poll returns the rep''s reply');
select pg_temp.expect_state(format('update app.chat_conversations set claimed_by = null where id = %L', (select id from t_cid)), '23514',
                            'a live chat must have a claim (the live-state check)');
select pg_temp.expect_state(format('update app.chat_conversations set state = %L where id = %L', 'live', (select id from t_cv)), '23514',
                            'an unclaimed chat cannot be live');
select pg_temp.expect_error($$update app.chat_messages set body = 'rewritten' where id = (select max(id) from app.chat_messages)$$, 'a chat transcript is append-only',
                            'a transcript cannot be rewritten');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.chat_close((select id from t_cid));
select pg_temp.check((select l.source from app.chat_conversations c join app.leads l on l.id = c.lead_id where c.id = (select id from t_cid)) = 'Live chat'
                 and (select count(*) from app.chat_messages where conversation_id = (select id from t_cid)) >= 3,
                     'a closed live chat is saved on a lead with its transcript');

-- the queue falls back to the bot when nobody answers
select pg_temp.as_nobody();
create temp table t_c3 as select public.worker_chat_start('orgpuls-com', '/pris', null, null) r;
update app.chat_conversations set state = 'queued', queued_at = now() - interval '10 minutes' where visitor_token_sha256 = extensions.digest((select r ->> 'token' from t_c3), 'sha256');
create temp table t_fb as select app.chat_fallback() n;
select pg_temp.check((select n from t_fb) >= 1 and (select state from app.chat_conversations where visitor_token_sha256 = extensions.digest((select r ->> 'token' from t_c3), 'sha256')) = 'bot',
                     'an unclaimed queued chat returns to the bot after the playbook''s wait');

-- ---------------------------------------------------------------------------
-- prospects: not connected, the contact rule, one credit per new reveal
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.prospect_reveal('ref-p5-1')$$, 'forbidden', 'the analyst cannot reveal a prospect (deals:add)');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(pg_temp.error_detail($$select public.prospect_reveal('ref-p5-1')$$) = 'not_connected:contact_data', 'reveal is not_connected without the prospect database');
select pg_temp.check(pg_temp.error_detail($$select public.prospect_search('{"title":"HR"}')$$) = 'not_connected:contact_data', 'search is not_connected without the prospect database');
insert into app.setting_values (key, scope_id, value) values ('contact_rule', '', 'opt_in_only') on conflict (key, scope_id) do update set value = excluded.value;
select pg_temp.check(pg_temp.error_detail($$select public.prospect_reveal('ref-p5-1')$$) = 'invalid:contact_rule', 'contact_rule opt_in_only refuses a reveal');
delete from app.setting_values where key = 'contact_rule' and scope_id = '';
update app.integration_connections set status = 'connected' where provider = 'contact_data';
create temp table t_rv as select (public.prospect_reveal('ref-p5-1') ->> 'reveal')::uuid id;
select pg_temp.check(not exists (select 1 from app.credit_ledger where reveal_id = (select id from t_rv)), 'nothing is charged before the contact arrives');
select pg_temp.as_nobody();
select public.worker_prospect_revealed((select id from t_rv), '{"name":"Per Prospekt","email":"per.prospekt.p5@example.no","title":"HR-leder","organization":{"name":"Prospekt AS","org_number":"987654321"}}');
select pg_temp.check((select l.source from app.prospect_reveals r join app.leads l on l.id = r.lead_id where r.id = (select id from t_rv)) = 'Prospect search'
                 and (select p.marketing_status from app.prospect_reveals r join app.people p on p.id = r.person_id where r.id = (select id from t_rv)) = 'no_consent'
                 and (select l.owner_id from app.prospect_reveals r join app.leads l on l.id = r.lead_id where r.id = (select id from t_rv)) = (select id from app.admins where email = 'ingrid@orgpuls.no'),
                     'a reveal creates the person without consent and a lead for the one who revealed (LGN-04)');
select pg_temp.check((select sum(delta) from app.credit_ledger where reveal_id = (select id from t_rv)) = -1, 'a reveal uses one credit');
select pg_temp.check(exists (select 1 from app.events where kind = 'prospect.revealed' and payload ->> 'reveal' = (select id from t_rv)::text), 'prospect.revealed is emitted');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.prospect_reveal('ref-p5-1') ->> 'repeat')::boolean and (select count(*) from app.credit_ledger where reveal_id = (select id from t_rv)) = 1,
                     'a repeat reveal of the same reference costs nothing');
select pg_temp.check((public.prospect_usage() ->> 'used_month')::int >= 1, 'usage counts the month''s credits');
update app.integration_connections set status = 'not_connected' where provider = 'contact_data';

-- ---------------------------------------------------------------------------
-- web visitors: company level, ENK excluded, survey hosts dropped, visitor.identified once a day
select pg_temp.as_nobody();
select public.worker_company_upsert('[{"org_number":"931000001","name":"Bergheim Bygg AS","org_form":"AS","industry":"Bygg","city":"Bergen"},
                                      {"org_number":"931000002","name":"Kari Enkeltperson","org_form":"ENK","city":"Oslo"},
                                      {"org_number":"931000003","name":"Fjord Data AS","org_form":"AS","city":"Ålesund"}]');
insert into app.organizations (name, org_number) values ('Bergheim Bygg (CRM)', '931000001');
create temp table t_ing as select public.worker_web_ingest(jsonb_build_array(
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('c', 32), 'at', now() - interval '20 minutes', 'path', '/pris', 'company_org_number', '931000001'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('c', 32), 'at', now() - interval '19 minutes', 'path', '/om'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('d', 32), 'at', now() - interval '15 minutes', 'path', '/', 'company_org_number', '931000001'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('e', 32), 'at', now() - interval '12 minutes', 'path', '/', 'company_org_number', '931000002'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('f', 32), 'at', now() - interval '10 minutes', 'path', '/a', 'company_org_number', '931000003'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('f', 32), 'at', now() - interval '9 minutes', 'path', '/b'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('f', 32), 'at', now() - interval '8 minutes', 'path', '/c'),
  jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('f', 32), 'at', now() - interval '7 minutes', 'path', '/d'),
  jsonb_build_object('site', 'svar.orgpuls.no', 'visitor_hash', repeat('9', 32), 'at', now(), 'path', '/s/abc'))) r;
select pg_temp.check((select (r ->> 'dropped_survey')::int from t_ing) = 1 and not exists (select 1 from app.web_sessions where visitor_hash = repeat('9', 32)),
                     'worker_web_ingest ignores a survey host (survey_flow_block)');
select pg_temp.check((select company_org_number from app.web_sessions where visitor_hash = repeat('e', 32)) is null, 'an ENK visit keeps no org number (Q16)');
select pg_temp.check((select count(*) from app.events where kind = 'visitor.identified' and subject_id = (select id from app.organizations where name = 'Bergheim Bygg (CRM)')) = 1
                 and (select (payload ->> 'high_intent')::boolean from app.events where kind = 'visitor.identified' and subject_id = (select id from app.organizations where name = 'Bergheim Bygg (CRM)')),
                     'visitor.identified is emitted once per CRM organization per day');
select pg_temp.check(not exists (select 1 from app.events where kind = 'visitor.identified' and payload ->> 'org_number' = '931000003'), 'a company not in the CRM emits nothing');
select pg_temp.check((select last_seen_at from app.web_sites where hostname = 'www.owntheagenda.com') > now() - interval '1 hour', 'the site''s last-seen time follows its visits');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_vis as select public.visitors_get(30) v;
select pg_temp.check((select x ->> 'org_number' from t_vis, jsonb_array_elements(v -> 'rows') x where (x ->> 'rank')::int = 1) = '931000003'
                 and (select (x ->> 'pages')::int from t_vis, jsonb_array_elements(v -> 'rows') x where x ->> 'org_number' = '931000001') = 3
                 and (select (x ->> 'sessions')::int from t_vis, jsonb_array_elements(v -> 'rows') x where x ->> 'org_number' = '931000001') = 2,
                     'visitors aggregate by company, most active first (WEB-03)');
select pg_temp.check((select x ->> 'name' from t_vis, jsonb_array_elements(v -> 'rows') x where x ->> 'org_number' = '931000001') = 'Bergheim Bygg (CRM)'
                 and (select (x ->> 'in_crm')::boolean from t_vis, jsonb_array_elements(v -> 'rows') x where x ->> 'org_number' = '931000001'),
                     'a company in the CRM shows its CRM name');
select pg_temp.check(not exists (select 1 from t_vis, jsonb_array_elements(v -> 'rows') x where x ->> 'org_number' = '931000002'), 'an ENK is never a visitor');
select pg_temp.check((select v ->> 'connected' from t_vis) = 'false', 'the inbox says the IP-to-company provider is not connected');
-- an ENK learned after its visits loses the org number from them
select pg_temp.as_nobody();
select public.worker_web_ingest(jsonb_build_array(jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('7', 32), 'at', now() - interval '5 minutes',
                                                                     'path', '/', 'company_org_number', '931000005')));
select public.worker_company_upsert('[{"org_number":"931000005","name":"Ola Enkel","org_form":"ENK"}]');
select pg_temp.check((select company_org_number from app.web_sessions where visitor_hash = repeat('7', 32)) is null and (select excluded from app.web_companies where org_number = '931000005'),
                     'an org number found to be an ENK is removed from its sessions');
insert into app.setting_values (key, scope_id, value) values ('web_ident', '', 'off') on conflict (key, scope_id) do update set value = excluded.value;
select public.worker_web_ingest(jsonb_build_array(jsonb_build_object('site', 'www.owntheagenda.com', 'visitor_hash', repeat('8', 32), 'at', now() - interval '4 minutes',
                                                                     'path', '/', 'company_org_number', '931000003')));
select pg_temp.check((select company_org_number from app.web_sessions where visitor_hash = repeat('8', 32)) is null, 'with identification off no company is stored');
delete from app.setting_values where key = 'web_ident' and scope_id = '';
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.visitor_get('931000001') -> 'pageviews') = 3 and (public.visitor_get('931000001') ->> 'visits_30d')::int = 2,
                     'a company''s visit history lists its pages and counts the company''s visits (Q23)');
select pg_temp.expect_error($$select public.visitor_get('931000002')$$, 'not_found', 'an ENK has no visit history');
create temp table t_conv as select public.visitor_convert('931000003', 'lead') r;
select pg_temp.check((select l.source from app.leads l where l.id = (select (r ->> 'lead_id')::uuid from t_conv)) = 'Web visitors'
                 and (select o.org_number from app.organizations o where o.id = (select (r ->> 'organization_id')::uuid from t_conv)) = '931000003'
                 and (select o.name from app.organizations o where o.id = (select (r ->> 'organization_id')::uuid from t_conv)) = 'Fjord Data AS',
                     'converting a visitor makes the organization from the register and a lead (WEB-04)');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.visitor_convert('931000001', 'lead')$$, 'forbidden', 'the analyst cannot convert a visitor');

-- ---------------------------------------------------------------------------
-- privacy: no answer, message or chat text in the outbox or the audit; erasure takes values and transcripts
select pg_temp.check(not exists (select 1 from app.events where payload::text ~* '(Hemmelig|Andre melding|Kari Chattesen|Ingrid her|live\.chat\.p5|kari\.form\.p5|Ring meg)'),
                     'no answer, message, chat text or address appears in event payloads');
select pg_temp.check(not exists (select 1 from app.audit where detail::text ~* '(Hemmelig|Andre melding|Kari Chattesen|Ingrid her|live\.chat\.p5|kari\.form\.p5|Ring meg)'),
                     'no answer, message, chat text or address appears in the audit');
select pg_temp.as_nobody();
create temp table t_erase as select person_id id from t_cv2;
delete from app.people where id = (select person_id from t_sub);
select pg_temp.check((select field_values from app.form_submissions where id = (select id from t_sub)) = '{}'::jsonb
                 and exists (select 1 from app.suppressions where email_sha256 = extensions.digest('kari.form.p5@example.no', 'sha256') and reason = 'erasure'),
                     'erasing a person removes their form values and keeps the address suppressed by its hash (SEC-11)');
delete from app.people where id = (select id from t_erase);
select pg_temp.check(not exists (select 1 from app.chat_conversations where id = (select id from t_cv2))
                 and not exists (select 1 from app.chat_messages where conversation_id = (select id from t_cv2)), 'erasing a person removes their chat transcripts');

rollback;
