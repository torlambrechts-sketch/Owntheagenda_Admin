-- mail_invariants.sql — the mail provider (0060): the key only through the owner's intake, the generated secrets, the
-- connection only from the worker's verdict, ticket replies queued and claimed, the customer's emailed answer threaded,
-- invitations, alert emails, the MFA reminder, the queue take and the tick.
\ir _helpers.psql
begin;

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
create or replace function pg_temp.as_mfa(p_email text, p_age int default 30) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where lower(email) = lower(p_email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email,
                      'amr', jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - p_age)))::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $$;

create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create temp table t_ids as select
  (select id from app.admins where email = 'tor@orgpuls.no') tor, (select id from app.admins where email = 'hanna@orgpuls.no') hanna,
  (select id from app.tickets where not is_sample and deleted_at is null and requester_email is not null order by number limit 1) ticket;
grant all on t_ids to public;

-- ---------------------------------------------------------------------------
-- secrets: generated ones exist, the readable names are exactly these
select pg_temp.check(exists (select 1 from vault.secrets where name = 'mail_worker_secret') and exists (select 1 from vault.secrets where name = 'mail_events_secret'),
                     'the worker and events secrets are generated in Vault, nobody types them');
select pg_temp.check(char_length(public.product_secret('mail_worker_secret')) = 64 and public.product_secret('some_other_key') is null,
                     'product_secret reads the three mail names and the products'' secrets, nothing else');
select pg_temp.check(not has_function_privilege('authenticated', 'public.product_secret(text)', 'execute')
                     and not has_function_privilege('anon', 'public.store_product_secrets(text, jsonb)', 'execute'),
                     'only the service role reads or stores a secret');

-- the owner's intake: fresh second factor, owner only, bound to the key's one name
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.email_provider_intake()$$, 'forbidden', 'owner_only', 'only the owner opens an intake for the mail key');
select pg_temp.as_mfa('tor@orgpuls.no', 1800);
select pg_temp.expect_detail($$select public.email_provider_intake()$$, 'forbidden', 'fresh_mfa', 'the intake needs a fresh second factor');
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_code as select public.email_provider_intake() ->> 'intake_code' code;
select pg_temp.check((select purpose from app.intake_nonces where hash = extensions.digest((select code from t_code), 'sha256')) = 'brevo',
                     'the number is bound to the mail key');
select pg_temp.as_service();
select pg_temp.expect_detail(format($$select public.store_product_secrets(%L, '{"orgpuls_token_secret": "%s"}')$$, (select code from t_code), repeat('a', 40)),
                             'invalid', 'name', 'a mail number stores the mail key and nothing else');
select pg_temp.check((public.store_product_secrets((select code from t_code), jsonb_build_object('brevo_api_key', 'xkeysib-' || repeat('0a', 32) || '-TESTONLY0000aaaa')) ->> 'stored')::int = 1,
                     'the key is stored under its one name');
select pg_temp.check(char_length(public.product_secret('brevo_api_key')) > 32, 'mail-run can read the key (service role)');
select pg_temp.check((public.store_product_secrets((select code from t_code), '{"brevo_api_key": "x"}') ->> 'error') = 'unauthorized',
                     'the number works once');
select pg_temp.check((select status from app.integration_connections where provider = 'email') = 'not_connected',
                     'storing a key does not connect anything: only the worker''s verdict does');

-- ---------------------------------------------------------------------------
-- nothing is ready until the worker proves the key, and there is a verified sender
select pg_temp.check(not app.mail_ready(), 'not ready before the verdict');
select pg_temp.expect_detail($$select public.worker_email_provider_result(true, '{"code": "Not A Code"}')$$, 'invalid', 'code', 'a verdict''s code is a code, never text from Brevo');
select pg_temp.check((public.worker_email_provider_result(false, '{"code": "http_401"}') ->> 'status') = 'error', 'a refused key is an error');
select pg_temp.check((select last_error from app.mail_settings) = 'http_401', 'and the reason is kept as a code');
select pg_temp.check((public.worker_email_provider_result(true, '{"account": {"plan": "free"}, "webhook_ok": true}') ->> 'status') = 'connected', 'a proven key connects');
select pg_temp.check(app.connected('email') and (select webhook_ok from app.mail_settings), 'connected, with the webhook');
select pg_temp.check(not app.mail_ready(), 'connected is not enough: no verified sender yet');
update app.sender_domains set verified_at = null, spf_ok = false where deleted_at is null;
insert into app.sender_domains (domain, stream, sends_here, from_name, from_local, reply_to, spf_ok, dkim_ok, dmarc_policy, verified_at, product)
values ('other.example', 'transactional', true, 'Other app', 'support', null, true, true, 'none', now(), (select key from app.products where key <> (select product from app.tickets where id = (select ticket from t_ids)) limit 1));
select pg_temp.check(not app.mail_ready_for((select product from app.tickets where id = (select ticket from t_ids))),
                     'another application''s sender never sends this application''s mail');
insert into app.sender_domains (domain, stream, sends_here, from_name, from_local, reply_to, spf_ok, dkim_ok, dmarc_policy, verified_at, product)
values ('mailtest.example', 'transactional', true, 'Orgpuls', 'support', 'support@mailtest.example', true, true, 'none', now(), (select product from app.tickets where id = (select ticket from t_ids)));
select pg_temp.check(app.mail_ready() and app.mail_ready_for((select product from app.tickets where id = (select ticket from t_ids)))
                     and (app.mail_sender_for((select product from app.tickets where id = (select ticket from t_ids)))).domain = 'mailtest.example',
                     'the ticket''s own application''s verified sender makes its mail ready');

-- a campaign belongs to the application whose address sends it (0062)
insert into app.sender_domains (domain, stream, sends_here, from_name, from_local, spf_ok, dkim_ok, dmarc_policy, verified_at, product, postal_address)
values ('news.mailtest.example', 'marketing', true, 'Orgpuls', 'nyheter', true, true, 'none', now(), (select product from app.tickets where id = (select ticket from t_ids)), 'Gate 1, 0150 Oslo'),
       ('news.staff.example', 'marketing', true, 'Staff', 'nyheter', true, true, 'none', now(), null, 'Gate 1, 0150 Oslo');
select pg_temp.check((app.mail_sender()).stream = 'transactional', 'staff mail never goes from a marketing address');
insert into app.campaigns (name, type, utm_campaign, product, sender_domain_id)
values ('Mail test campaign', 'newsletter', 'mail_test_campaign', (select key from app.products where key <> (select product from app.tickets where id = (select ticket from t_ids)) limit 1),
        (select id from app.sender_domains where domain = 'news.mailtest.example'));
select pg_temp.check((select product from app.campaigns where utm_campaign = 'mail_test_campaign') = (select product from app.tickets where id = (select ticket from t_ids)),
                     'a campaign sent from an application''s address is that application''s campaign');
update app.campaigns set sender_domain_id = (select id from app.sender_domains where domain = 'news.staff.example') where utm_campaign = 'mail_test_campaign';
select pg_temp.check((select product from app.campaigns where utm_campaign = 'mail_test_campaign') = (select product from app.tickets where id = (select ticket from t_ids)),
                     'an address with no application leaves the campaign''s application as it was');

select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((public.email_provider_get() -> 'ready_products') ? (select product from app.tickets where id = (select ticket from t_ids)),
                     'the screens learn which applications can email their customers');
select pg_temp.check((public.email_provider_get() ->> 'connected')::boolean and not (public.email_provider_get() ->> 'can_manage')::boolean
                     and public.email_provider_get() -> 'account' = '{}'::jsonb,
                     'staff see the state; the account details and management are for those with the right');
select pg_temp.expect_detail($$select public.email_provider_settings('https://x.example')$$, 'forbidden', 'owner_only', 'only the owner sets the public address');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.email_provider_settings('http://x.example')$$, 'invalid', 'public_base', 'the public address is https');
select pg_temp.check((public.email_provider_settings('https://Admin.Example/') ->> 'public_base') = 'https://admin.example', 'the address is kept tidy');
select pg_temp.expect_detail($$select public.email_provider_settings('https://admin.example', 'not a domain')$$, 'invalid', 'inbound_domain', 'a reply domain is a domain');
select pg_temp.check((public.email_provider_settings('https://admin.example', 'Svar.Mailtest.Example') ->> 'inbound_domain') = 'svar.mailtest.example', 'the reply domain is kept');

-- an application's own link address (0063)
create temp table t_app as select product p from app.tickets where id = (select ticket from t_ids);
select pg_temp.expect_detail(format($$select public.email_provider_app_base(%L, 'https://orgpuls.example')$$, (select p from t_app)), 'invalid', 'app_base',
                             'a link address is a post. host, the one the app serves only the unsubscribe page on');
select pg_temp.expect_detail($$select public.email_provider_app_base('no_such_app', 'https://post.x.example')$$, 'invalid', 'product', 'for an application that exists');
select pg_temp.check((public.email_provider_app_base((select p from t_app), 'https://Post.Mailtest.Example/') ->> 'base') = 'https://post.mailtest.example', 'the link address is kept tidy');
select pg_temp.check(public.email_provider_get() -> 'app_bases' ->> (select p from t_app) = 'https://post.mailtest.example', 'and the screen shows it back');
select pg_temp.as_service();
select pg_temp.check(public.worker_campaign_base((select id from app.campaigns where utm_campaign = 'mail_test_campaign')) = 'https://post.mailtest.example',
                     'the application''s campaign links open on the application''s own address');
update app.campaigns set product = null where utm_campaign = 'mail_test_campaign';
select pg_temp.check(public.worker_campaign_base((select id from app.campaigns where utm_campaign = 'mail_test_campaign')) = 'https://admin.example',
                     'a campaign of no application links to Sentral''s public address');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.email_provider_app_base((select p from t_app), '') ->> 'base') is null, 'an empty address clears it');
select pg_temp.check(not ((public.email_provider_get() -> 'app_bases') ? (select p from t_app)), 'and the application goes back to Sentral''s own');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail(format($$select public.email_provider_app_base(%L, 'https://post.x.example')$$, (select p from t_app)), 'forbidden', 'owner_only',
                             'only the owner sets a link address');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.as_service();
select public.worker_email_provider_result(true, '{"inbound_ok": true}');
select pg_temp.as_staff('tor@orgpuls.no');

-- ---------------------------------------------------------------------------
-- ticket replies
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_reply as select public.ticket_message((select ticket from t_ids), 'reply', 'Hei, dette er løst nå.', 'waiting_customer') r;
select pg_temp.check(((select r from t_reply) ->> 'delivery') = 'queued', 'a reply is queued for email once mail is ready');
select pg_temp.check((select delivery_status from app.ticket_messages where id = ((select r from t_reply) ->> 'id')::uuid) = 'queued', 'and stored queued');
create temp table t_note as select public.ticket_message((select ticket from t_ids), 'note', 'intern') r;
select pg_temp.check(((select r from t_note) ->> 'delivery') is null, 'a note is never emailed');
select pg_temp.as_service();
create temp table t_claim as select public.worker_ticket_mail_claim(50) c;
select pg_temp.check(exists (select 1 from jsonb_array_elements((select c from t_claim)) x where (x ->> 'id')::uuid = ((select r from t_reply) ->> 'id')::uuid
                              and x ->> 'from' = 'support@mailtest.example' and x ->> 'from_name' = 'Orgpuls' and x ->> 'reply_to' = 'support@svar.mailtest.example' and x ->> 'ref' like 'T-%' and x ->> 'to' is not null),
                     'the worker claims it with the sender, the ticket''s reference and the requester''s address');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.worker_ticket_mail_claim(50)) x where (x ->> 'id')::uuid = ((select r from t_reply) ->> 'id')::uuid),
                     'a claimed reply is leased: a second run does not take it');
select public.worker_ticket_mail_done(((select r from t_reply) ->> 'id')::uuid, '<abc@smtp-relay.mailin.fr>');
select pg_temp.check((select delivery_status = 'sent' and provider_message_id = '<abc@smtp-relay.mailin.fr>' from app.ticket_messages where id = ((select r from t_reply) ->> 'id')::uuid),
                     'sent, with Brevo''s message id');
select public.worker_ticket_mail_event('<abc@smtp-relay.mailin.fr>', 'delivered');
select pg_temp.check((select delivery_status from app.ticket_messages where id = ((select r from t_reply) ->> 'id')::uuid) = 'delivered', 'Brevo''s «delivered» shows on the reply');
select pg_temp.check((public.worker_ticket_mail_event('<nobody@x>', 'delivered') ->> 'matched')::boolean = false, 'an unknown id matches nothing');

-- a failure: retried while retryable, failed with a notice when not
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_reply2 as select public.ticket_message((select ticket from t_ids), 'reply', 'Andre svar.') r;
select pg_temp.as_service();
select public.worker_ticket_mail_claim(50);
select public.worker_ticket_mail_done(((select r from t_reply2) ->> 'id')::uuid, null, 'http_503', true);
select pg_temp.check((select delivery_status = 'queued' and mail_error = 'http_503' from app.ticket_messages where id = ((select r from t_reply2) ->> 'id')::uuid),
                     'a retryable failure stays queued');
select public.worker_ticket_mail_done(((select r from t_reply2) ->> 'id')::uuid, null, 'http_400', false);
select pg_temp.check((select delivery_status = 'failed' from app.ticket_messages where id = ((select r from t_reply2) ->> 'id')::uuid)
                     and exists (select 1 from app.notifications where staff_id = (select tor from t_ids) and key = 'tickets.mail_failed'),
                     'a refused one fails and its author hears of it');

-- the customer's answer by email
select pg_temp.check((public.worker_ticket_inbound('in-1', 'stranger@example.org', 'Re: [T-' || (select number from app.tickets where id = (select ticket from t_ids)) || '] x', 'hei') ->> 'matched')::boolean = false,
                     'an answer from anyone but the requester is dropped');
select pg_temp.check(not exists (select 1 from app.ticket_messages where inbound_id = 'in-1'), 'and nothing of it is stored');
select pg_temp.check((public.worker_ticket_inbound('in-2', upper((select app.ticket_recipient(t) from app.tickets t where id = (select ticket from t_ids))),
                      'Re: [T-' || (select number from app.tickets where id = (select ticket from t_ids)) || '] x', 'Takk, det virker!') ->> 'matched')::boolean,
                     'the requester''s answer naming the ticket is threaded');
select pg_temp.check((select kind = 'customer' and body = 'Takk, det virker!' from app.ticket_messages where inbound_id = 'in-2')
                     and (select status from app.tickets where id = (select ticket from t_ids)) = 'waiting_us',
                     'as the customer''s message, and the ticket waits on us again');
select pg_temp.check((public.worker_ticket_inbound('in-2', 'x', 'y', 'z') ->> 'duplicate')::boolean, 'Brevo''s retry of the same answer is a duplicate');

-- a sample ticket never sends
select pg_temp.as_staff('tor@orgpuls.no');
update app.tickets set is_sample = true where id = (select ticket from t_ids);
select pg_temp.check((public.ticket_message((select ticket from t_ids), 'reply', 'eksempel') ->> 'delivery') = 'not_configured', 'a sample ticket''s reply is never emailed');
update app.tickets set is_sample = false where id = (select ticket from t_ids);

-- ---------------------------------------------------------------------------
-- invitations
select pg_temp.as_mfa('tor@orgpuls.no');
create temp table t_new as select public.staff_save(null, jsonb_build_object('email', 'ny.ansatt@mailtest.example', 'name', 'Ny Ansatt')) r;
select pg_temp.check(((select r from t_new) ->> 'invite') = 'queued', 'a new staff member''s invitation is queued');
select pg_temp.check((select invite_state = 'queued' and invited_by = (select tor from t_ids) from app.admins where email = 'ny.ansatt@mailtest.example'),
                     'with who asked');
select pg_temp.expect_detail(format($$select public.staff_invite_send(%L)$$, (select tor from t_ids)), 'invalid', 'has_login', 'someone with a login gets no invitation');
select pg_temp.as_service();
create temp table t_inv as select public.worker_invite_claim(10) c;
select pg_temp.check(exists (select 1 from jsonb_array_elements((select c from t_inv)) x where x ->> 'email' = 'ny.ansatt@mailtest.example'
                              and x ->> 'public_base' = 'https://admin.example' and x ->> 'by_name' is not null), 'the worker claims it with the address the link opens');
select public.worker_invite_done(((select r from t_new) ->> 'id')::uuid);
select pg_temp.check((select invite_state = 'sent' and invite_sent_at is not null from app.admins where email = 'ny.ansatt@mailtest.example'), 'sent');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((select x ->> 'invite_state' from jsonb_array_elements(public.staff_list()) x where x ->> 'email' = 'ny.ansatt@mailtest.example') = 'sent',
                     'the team list shows the invitation''s state');

-- ---------------------------------------------------------------------------
-- security alerts and the MFA reminder
insert into app.security_events (kind, severity, subject_staff_id, detail, alert_state) values ('user_invited', 'high', (select tor from t_ids), '{}', 'queued');
select app.security_alerts_run();
select pg_temp.check(exists (select 1 from app.security_alert_deliveries where channel = 'email' and status = 'queued'), 'an alert''s email is queued once mail is ready');
select pg_temp.as_service();
create temp table t_alerts as select public.worker_alert_mail_claim(100) c;
-- the seed's own alerts from the last day that waited for the provider are released too (0060), so this one is looked for
-- among them; which seed alerts fall inside the day depends on the hour the suite runs
select pg_temp.check(exists (select 1 from jsonb_array_elements((select c from t_alerts)) x where x ->> 'kind' = 'user_invited')
                     and (select bool_and(x ->> 'to' is not null) from jsonb_array_elements((select c from t_alerts)) x),
                     'the worker claims each recipient''s alert email');
select public.worker_alert_mail_done((x ->> 'event')::bigint, (x ->> 'recipient')::uuid, true) from jsonb_array_elements((select c from t_alerts)) x;
select pg_temp.check(not exists (select 1 from app.security_alert_deliveries d join jsonb_array_elements((select c from t_alerts)) x
                                 on d.event_id = (x ->> 'event')::bigint and d.recipient_id = (x ->> 'recipient')::uuid and d.channel = 'email' where d.status <> 'sent'),
                     'and marks them sent');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.staff_mfa_reminder(((select r from t_new) ->> 'id')::uuid) ->> 'email') = 'queued', 'an MFA reminder is emailed once mail is ready');
select pg_temp.as_service();
create temp table t_jobs as select public.worker_mail_take(200) j;
select pg_temp.check(exists (select 1 from jsonb_array_elements((select j from t_jobs)) x where x ->> 'job' = 'mfa_reminder' and (x ->> 'staff')::uuid = ((select r from t_new) ->> 'id')::uuid),
                     'the worker takes the reminder off the queue');
select pg_temp.check(not exists (select 1 from pgmq.q_jobs where message ->> 'job' = any (app.mail_job_kinds())), 'taken means gone: no mail job is left behind');
select pg_temp.check(not exists (select 1 from jsonb_array_elements((select j from t_jobs)) x where x ->> 'job' not in ('campaign_send', 'campaign_test', 'dns_check', 'mfa_reminder')),
                     'only mail jobs are taken; the other workers'' jobs stay');
select pg_temp.check((public.worker_staff_mail(((select r from t_new) ->> 'id')::uuid, (select tor from t_ids)) ->> 'by_name') is not null, 'the reminder names who asked');

-- the tick knocks only while connected and something waits
select pg_temp.check((app.mail_tick() ->> 'called')::int in (0, 1), 'the tick runs');
update app.integration_connections set status = 'not_connected' where provider = 'email';
select pg_temp.check((app.mail_tick() ->> 'called')::int = 0, 'disconnected: the tick never calls out');

-- grants
select pg_temp.check(not has_function_privilege('authenticated', 'public.worker_ticket_mail_claim(int)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_mail_take(int)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_ticket_inbound(text, text, text, text)', 'execute')
                     and not has_function_privilege('authenticated', 'public.worker_campaign_base(uuid)', 'execute')
                     and has_function_privilege('service_role', 'public.worker_invite_claim(int)', 'execute'),
                     'the worker functions are the service role''s alone');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'app.mail_settings'::regclass)
                     and not has_table_privilege('authenticated', 'app.mail_settings', 'select'), 'mail_settings: RLS on, no grant');

rollback;
