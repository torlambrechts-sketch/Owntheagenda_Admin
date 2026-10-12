-- v3_support_invariants.sql — Customers › Help centre and support (0081). The two production defects first (F-S1: a
-- contact's topic routes it, privacy gets its 30-day clock and makes no lead, the in-app request keeps its words; F-S2: the
-- reference header threads, an auto-reply never threads or reopens); then the help centre (per-product slugs, translation
-- groups, versions, publishing under tickets:configure, full-text search over published articles only); the reads (results,
-- channels, portal preview, widget, AI assist) under tickets:see and the queue rules; the «answer from published articles»
-- preview (the person's own question and published articles only, a switch per product); status components and incidents
-- (append-only updates, resolve and notify through problem_resolve, the site notice as Orgpuls really has it); CSAT (a
-- single-use token, issued on the resolving reply when a public page can take the answer, a score and nothing else).
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
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create or replace function pg_temp.ticket_of(p_source bigint) returns app.tickets language sql as $$
  select t.* from app.tickets t join app.events_in e on e.id = t.source_event_id where e.product = 'orgpuls' and e.source_id = p_source
$$;

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('contact_topic_routes', 'help_app_pages', 'support_settings', 'help_test_questions', 'status_components', 'status_incidents',
                      'status_incident_components', 'status_incident_updates')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the new tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace
                      and c.relname in ('contact_topic_routes', 'help_app_pages', 'support_settings', 'help_test_questions', 'status_components', 'status_incidents',
                                        'status_incident_components', 'status_incident_updates')) = 8, 'all eight exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute') and has_function_privilege('service_role', f::regprocedure, 'execute'),
                     'only the service role calls ' || f)
from unnest(array['public.worker_ticket_inbound(text, text, text, text, jsonb)', 'public.worker_ticket_inbound(text, text, text, text)',
                  'public.worker_csat_submit(text, int)', 'public.worker_csat_peek(text)', 'public.worker_ticket_mail_claim(int)',
                  'public.worker_ticket_mail_done(uuid, text, text, boolean)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute') and has_function_privilege('authenticated', f::regprocedure, 'execute'),
                     'signed-in staff only: ' || f)
from unnest(array['public.help_centre_get(text)', 'public.help_article_write(uuid, jsonb, int)', 'public.help_article_publish(uuid, boolean)',
                  'public.help_search(text, text, text)', 'public.support_results(text, int)', 'public.support_channels(text, int)',
                  'public.portal_preview(text, uuid)', 'public.support_widget_get(text)', 'public.support_assist_get(text, uuid)',
                  'public.help_question_ask(text, text, text)', 'public.support_settings_save(text, boolean)', 'public.status_get(text)',
                  'public.status_incident_resolve(uuid, text)']) f;
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.ai_ctx_help_answer_preview(uuid)', 'app.help_slug(text, text, text, uuid)', 'app.mail_auto_reply(jsonb, text)',
                  'app.support_ticket_ok(app.tickets)', 'app.help_questions_prune()', 'app.status_incident_notice(text, uuid, timestamptz)']) f;

-- ---------------------------------------------------------------------------
-- F-S1: the contact form's topic routes the ticket; privacy goes to personvern with its clock and makes no lead
insert into app.events_in (product, source_id, kind, payload, occurred_at) values
  ('orgpuls', 990000101, 'contact.submitted', '{"topic": "privacy", "name": "Test Person", "email": "test.person@example.no", "message": "Hvilke opplysninger har dere om meg?\nMvh"}', now() - interval '2 minutes'),
  ('orgpuls', 990000102, 'contact.submitted', '{"topic": "pricing", "name": "Kari Test", "email": "kari.test@example.no", "message": "Hva koster det for 40 ansatte?"}', now()),
  ('orgpuls', 990000103, 'contact.submitted', '{"topic": "product", "name": "Ola Test", "email": "ola.test@example.no", "message": "Hvordan legger jeg til ansatte?"}', now()),
  ('orgpuls', 990000104, 'contact.submitted', '{"topic": "first_send", "name": "Per Test", "email": "per.test@example.no", "message": "Når sendes invitasjonene?"}', now()),
  ('orgpuls', 990000105, 'contact.submitted', '{"topic": "unknown_topic", "name": "Siri Test", "email": "siri.test@example.no", "message": "Hei"}', now()),
  ('orgpuls', 990000106, 'support.requested', '{"category": "survey_delivery", "subject": "Invitasjoner mangler", "body": "Tre ansatte har ikke fått invitasjonen.", "email": "hjelp.test@example.no"}', now()),
  ('orgpuls', 990000107, 'support.requested', '{"category": "personvern", "subject": "Slett meg", "body": "Jeg vil slettes.", "email": "slett.test@example.no"}', now()),
  ('orgpuls', 990000108, 'contact.submitted', '{"topic": "product", "name": "Leder Test", "email": "leder.test@example.no", "message": "Min leder truer meg etter forrige undersøkelse, hvordan sletter jeg svaret mitt?"}', now()),
  ('orgpuls', 990000109, 'contact.submitted', '{"topic": "pricing", "name": "Truet Test", "email": "truet.test@example.no", "message": "Lederen min truer oss, hva koster det å bytte?"}', now());
select pg_temp.check((select category_key = 'personvern' and queue_key = 'personvern' and topic = 'privacy' and channel = 'contact_form' from pg_temp.ticket_of(990000101)),
                     'F-S1: a privacy contact lands in the personvern queue with its topic');
select pg_temp.check(exists (select 1 from app.privacy_requests r where r.ticket_id = (select id from pg_temp.ticket_of(990000101))
                             and r.due_at = r.received_at + interval '30 days' and r.received_at <= now() - interval '1 minute' and r.status = 'received'
                             and r.requester_category = 'contact_form'),
                     'F-S1: it starts the 30-day clock from the moment the customer sent it');
select pg_temp.check(not exists (select 1 from app.ticket_links l where l.ticket_id = (select id from pg_temp.ticket_of(990000101)) and l.kind = 'lead'),
                     'F-S1: a privacy request makes no CRM lead');
select pg_temp.check((select subject from pg_temp.ticket_of(990000101)) = 'Hvilke opplysninger har dere om meg?', 'the subject is the first line of the message');
select pg_temp.check((select category_key = 'sales' and queue_key = 'sales' from pg_temp.ticket_of(990000102)), 'pricing goes to Sales');
select pg_temp.check(exists (select 1 from app.ticket_links l where l.ticket_id = (select id from pg_temp.ticket_of(990000102)) and l.kind = 'lead'), 'and makes a lead');
select pg_temp.check((select l.title from app.leads l join app.ticket_links k on k.ref = l.id::text and k.kind = 'lead'
                      where k.ticket_id = (select id from pg_temp.ticket_of(990000102))) = 'Sales',
                     'a lead without a subject is titled by its category, never by the message');
select pg_temp.check(not exists (select 1 from app.ticket_links l where l.kind = 'lead'
                                 and l.ticket_id in ((select id from pg_temp.ticket_of(990000103)), (select id from pg_temp.ticket_of(990000104)),
                                                     (select id from pg_temp.ticket_of(990000108)))),
                     'a support topic makes no CRM lead: it is not a sale');
select pg_temp.check(not exists (select 1 from app.leads l join app.ticket_links k on k.ref = l.id::text and k.kind = 'lead'
                                 join app.tickets t on t.id = k.ticket_id join app.events_in e on e.id = t.source_event_id
                                 where e.product = 'orgpuls' and e.source_id between 990000101 and 990000109
                                   and exists (select 1 from regexp_split_to_table(lower(e.payload ->> 'message'), '[^a-zæøå]+') w
                                               where char_length(w) >= 4 and lower(l.title) like '%' || w || '%')),
                     'rule 6: no lead title carries a word of the customer''s message');
select pg_temp.as_staff('jonas@orgpuls.no');    -- Marketing: deals:see, no ticket right
select pg_temp.check(public.leads_get('{}')::text not like '%truer%', 'Marketing finds no contact message through the leads');
select pg_temp.as_nobody();
select pg_temp.check((select category_key = 'getting_started' and queue_key = 'support' from pg_temp.ticket_of(990000103)), 'product goes to Getting started in Support');
select pg_temp.check((select category_key from pg_temp.ticket_of(990000104)) = 'survey_delivery', 'first_send goes to Survey delivery');
select pg_temp.check((select category_key = 'sales' and topic = 'unknown_topic' from pg_temp.ticket_of(990000105)), 'an unknown topic falls back to Sales');
select pg_temp.check(not exists (select 1 from app.privacy_requests r where r.ticket_id = (select id from pg_temp.ticket_of(990000102))), 'only privacy starts a clock');
select pg_temp.check((select m.body from app.ticket_messages m where m.ticket_id = (select id from pg_temp.ticket_of(990000106)) and m.kind = 'customer')
                     = 'Tre ansatte har ikke fått invitasjonen.', 'F-S1: an in-app request keeps the customer''s words (body)');
select pg_temp.check(exists (select 1 from app.privacy_requests r where r.ticket_id = (select id from pg_temp.ticket_of(990000107)) and r.requester_category = 'in_app'),
                     'an in-app request in the personvern category starts the clock too');

-- ---------------------------------------------------------------------------
-- F-S2: the reference header first; an auto-reply never threads and never reopens
create temp table t_mail as
  with t as (insert into app.tickets (subject, category_key, queue_key, status, requester_email, product, channel, resolved_at)
             values ('Utvide prøveperioden', 'billing', 'billing', 'resolved', 'kunde.test@example.no', 'orgpuls', 'email', now()) returning id, number)
  select id, number from t;
insert into app.ticket_messages (ticket_id, kind, body, delivery_status, provider_message_id, email_message_id)
values ((select id from t_mail), 'reply', 'Dette er løst.', 'sent', '<ref-test-1@smtp-relay.mailin.fr>', '<ref-test-1@smtp-relay.mailin.fr>');
select pg_temp.as_service();
create temp table t_in1 as select public.worker_ticket_inbound('in-1', 'kunde.test@example.no', 'Automatisk svar: Re: [T-' || (select number from t_mail) || '] Utvide prøveperioden',
                                                                 'Jeg er på ferie.') r;
select pg_temp.check(((select r from t_in1) ->> 'auto_reply')::boolean and ((select r from t_in1) ->> 'kept')::boolean,
                     'F-S2: an out-of-office subject is an auto-reply, and its words are kept (a subject is only a guess)');
select pg_temp.check((select status = 'resolved' and reopened_count = 0 from app.tickets where id = (select id from t_mail)), 'F-S2: it leaves the resolved ticket resolved');
select pg_temp.check((public.worker_ticket_inbound('in-2', 'kunde.test@example.no', 'Re: [T-' || (select number from t_mail) || '] Utvide prøveperioden', 'Borte.',
                                                   '{"auto-submitted": "auto-replied"}') ->> 'auto_reply')::boolean, 'Auto-Submitted marks an auto-reply');
select pg_temp.check((public.worker_ticket_inbound('in-3', 'kunde.test@example.no', 'Re: hei', 'Borte.',
                                                   '{"precedence": "bulk", "in-reply-to": "<ref-test-1@smtp-relay.mailin.fr>"}') ->> 'auto_reply')::boolean, 'Precedence: bulk too');
select pg_temp.check((public.worker_ticket_inbound('in-4', 'kunde.test@example.no', 'Re: hei', 'Fravær.', '{"x-auto-response-suppress": "All"}') ->> 'matched')::boolean = false,
                     'without a reference or a number nothing matches');
select pg_temp.check((select count(*) = 1 and min(m.body) = 'Jeg er på ferie.' and min(m.inbound_id) = 'in-1' from app.ticket_messages m
                      where m.ticket_id = (select id from t_mail) and m.kind = 'customer'),
                     'no auto-reply by its headers entered the thread; the one by its subject alone is kept');
select pg_temp.check((select count(*) from app.audit a where a.action = 'ticket.auto_reply_ignored' and a.target_id = (select id::text from t_mail)) = 2
                     and (select count(*) from app.audit a where a.action = 'ticket.auto_reply_kept' and a.target_id = (select id::text from t_mail)) = 1
                     and not exists (select 1 from app.audit a where a.action in ('ticket.auto_reply_ignored', 'ticket.auto_reply_kept')
                                     and a.target_id = (select id::text from t_mail) and a.detail is not null),
                     'each auto-reply is audited by its ticket only');
select pg_temp.check((public.worker_ticket_inbound('in-5', 'kunde.test@example.no', 'Re: svar på saken', 'Takk, men det virker fortsatt ikke.',
                                                   '{"in-reply-to": "<ref-test-1@smtp-relay.mailin.fr>"}') ->> 'matched')::boolean,
                     'the hidden reference header threads an answer whose subject lost the number');
select pg_temp.check((select status = 'waiting_us' and reopened_count = 1 from app.tickets where id = (select id from t_mail)), 'a real answer reopens the ticket');
select pg_temp.check((public.worker_ticket_inbound('in-6', 'kunde.test@example.no', 'Re: svar', 'Mer.', '{"references": "<x@y> ref-test-1@smtp-relay.mailin.fr"}') ->> 'matched')::boolean = false,
                     'a reference must be a whole Message-ID');
select pg_temp.check((public.worker_ticket_inbound('in-7', 'noen.annen@example.no', 'Re: svar', 'Hei', '{"in-reply-to": "<ref-test-1@smtp-relay.mailin.fr>"}') ->> 'matched')::boolean = false,
                     'only the requester threads into the ticket');
select pg_temp.check((public.worker_ticket_inbound('in-5', 'kunde.test@example.no', 'Re: svar på saken', 'Takk.', '{}') ->> 'duplicate')::boolean, 'a repeated delivery is a duplicate');
select pg_temp.check(not app.mail_auto_reply('{}', 'Re: [T-12] Fravær av ansatte i rapporten') and app.mail_auto_reply('{}', 'Fraværsmelding: [T-12]')
                     and app.mail_auto_reply('{}', 'Automatic reply: Re: [T-12] x') and app.mail_auto_reply('{"x-autoreply": "yes"}', 'Re: [T-12]')
                     and not app.mail_auto_reply('{"auto-submitted": "no"}', 'Re: [T-12]'), 'the auto-reply rule reads headers and the start of the subject');
select pg_temp.check(not app.mail_auto_reply('{}', s), 'a customer''s subject is not an auto-reply: ' || s)
from unnest(array['Fravær i rapporten [T-12]', 'Fraværsprosent stemmer ikke [T-12]', 'Ikke til stede-knappen virker ikke [T-12]',
                  'Autosvar på epost fra dere?', 'Out of office-meldinger i rapporten']) s;
select pg_temp.check(app.mail_auto_reply('{}', s), 'an auto-reply''s subject shape: ' || s)
from unnest(array['Autosvar: Re: [T-12] x', 'Fravær: [T-12]', 'Out of Office: Re: x', 'Automatisk svar: x', 'Automatische Antwort: x',
                  'Ikke til stede: x', '  Automatic Reply : x']) s;

-- ---------------------------------------------------------------------------
-- help centre
select pg_temp.as_staff('jonas@orgpuls.no');    -- Marketing: no ticket right
select pg_temp.expect_detail($$select public.help_centre_get('orgpuls')$$, 'forbidden', 'tickets:see', 'the help centre needs tickets:see');
select pg_temp.as_staff('sara@orgpuls.no');     -- Read-only
select pg_temp.check(jsonb_array_length(public.help_centre_get('orgpuls') -> 'articles') >= 6, 'Read-only reads the help centre');
select pg_temp.check(not (public.help_centre_get('orgpuls') ->> 'measured')::boolean, 'nothing records views yet: they are not measured');
select pg_temp.check((public.help_centre_get('orgpuls') -> 'pages') @> '["/malinger", "/resultater"]', 'the editor offers the product''s app pages');
select pg_temp.check((public.help_centre_get('orgpuls') -> 'articles' -> 0 -> 'views') = 'null'::jsonb, 'so no article shows a view count');
select pg_temp.expect_detail($$select public.help_article_write(null, '{"product": "orgpuls", "title": "Ny artikkel"}')$$, 'forbidden', 'tickets:edit_others',
                             'Read-only writes no article');
select pg_temp.expect_detail($$select public.help_centre_get('nope')$$, 'invalid', 'product', 'an unknown product is refused');

select pg_temp.as_staff('hanna@orgpuls.no');    -- Support: edit_others, no configure
create temp table t_art as select public.help_article_write(null, '{"product": "orgpuls", "title": "Bytte språk på undersøkelsen", "category_key": "getting_started",
  "body": "Gå til Oppsett og velg språk for hver ansatt. Undersøkelsen sendes på språket den ansatte har valgt."}') a;
select pg_temp.check((select a ->> 'slug' from t_art) = 'bytte-sprak-pa-undersokelsen' and (select a ->> 'status' from t_art) = 'draft'
                     and (select a ->> 'locale' from t_art) = 'nb', 'Support drafts an article; the slug spells out the Norwegian letters');
select pg_temp.check((public.help_article_write(null, '{"product": "orgpuls", "title": "Bytte språk på undersøkelsen"}') ->> 'slug') = 'bytte-sprak-pa-undersokelsen-2',
                     'a slug is unique within the product and language');
select pg_temp.check((public.help_article_write(null, '{"product": "skiftly", "title": "Bytte språk på undersøkelsen"}') ->> 'slug') = 'bytte-sprak-pa-undersokelsen',
                     'another product has its own slugs');
select pg_temp.expect_detail(format($$select public.help_article_write(%L, '{"title": "Endret"}', 99)$$, (select a ->> 'id' from t_art)), 'version_conflict', null,
                             'an edit on an old version is refused');
create temp table t_art2 as select public.help_article_write((select (a ->> 'id')::uuid from t_art), '{"title": "Velge språk for undersøkelsen", "app_pages": ["/oppsett"]}',
                                                             (select (a ->> 'version')::int from t_art)) a;
select pg_temp.check((select a ->> 'slug' from t_art2) = 'velge-sprak-for-undersokelsen' and (select a -> 'app_pages' from t_art2) = '["/oppsett"]'::jsonb,
                     'a draft''s slug follows its title; its app page is kept');
select pg_temp.expect_detail(format($$select public.help_article_write(%L, '{"app_pages": ["/s/abc"]}', %s)$$, (select a ->> 'id' from t_art), (select a ->> 'version' from t_art2)),
                             'invalid', 'app_pages', 'a respondent page is never an app page');
select pg_temp.expect_detail(format($$select public.help_article_write(%L, '{"locale": "en"}', %s)$$, (select a ->> 'id' from t_art), (select a ->> 'version' from t_art2)),
                             'invalid', 'fixed', 'an article''s language and group do not change');
create temp table t_tr as select public.help_article_write(null, jsonb_build_object('product', 'orgpuls', 'locale', 'en', 'group_id', (select a ->> 'group_id' from t_art),
                                                                                   'title', 'Choosing the survey language', 'body', 'Open Setup and choose a language for each employee.')) a;
select pg_temp.check((select a ->> 'group_id' from t_tr) = (select a ->> 'group_id' from t_art) and (select a ->> 'category_key' from t_tr) = 'getting_started'
                     and jsonb_array_length((select a -> 'siblings' from t_tr)) = 2, 'a translation joins the group and takes its category');
select pg_temp.expect_detail(format($$select public.help_article_write(null, %L)$$, jsonb_build_object('product', 'orgpuls', 'locale', 'en', 'group_id', (select a ->> 'group_id' from t_art), 'title', 'Again')),
                             'invalid', 'locale', 'a group has one article per language');
select pg_temp.expect_detail(format($$select public.help_article_publish(%L, true)$$, (select a ->> 'id' from t_art)), 'forbidden', 'tickets:configure',
                             'publishing stays with tickets:configure');
select pg_temp.check((public.help_article_review((select (a ->> 'id')::uuid from t_art)) ->> 'reviewed_by') is not null, 'Support marks an article reviewed');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.help_article_publish((select (a ->> 'id')::uuid from t_art), true) ->> 'status') = 'published', 'the admin publishes it');
create temp table t_art3 as select public.help_article_get((select (a ->> 'id')::uuid from t_art)) a;
select pg_temp.check((public.help_article_write((select (a ->> 'id')::uuid from t_art3), '{"title": "Språk i undersøkelsen"}', (select (a ->> 'version')::int from t_art3)) ->> 'slug')
                     = 'velge-sprak-for-undersokelsen', 'once published, the address stays');
select pg_temp.expect_detail(format($$select public.help_article_publish(%L, true)$$,
                                    (select (public.help_article_write(null, '{"product": "orgpuls", "title": "Tom artikkel"}') ->> 'id'))), 'invalid', 'body',
                             'an article without a body is not published');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.check((public.help_search('orgpuls', 'nb', 'språk ansat') -> 0 ->> 'id') = (select a ->> 'id' from t_art), 'search finds a published article by the start of its words');
select pg_temp.check((public.help_search('orgpuls', 'nb', 'språk') -> 0 ->> 'snippet') like '%⟦%', 'the snippet marks the hit');
select pg_temp.check(jsonb_array_length(public.help_search('orgpuls', 'en', 'language')) = 0, 'a draft translation is not found');
select pg_temp.check(jsonb_array_length(public.help_search('orgpuls', 'nb', 'x')) = 0, 'one letter is no search');
select pg_temp.check(jsonb_typeof(public.help_get() -> 'articles') = 'array', 'the old help reader still answers');

-- ---------------------------------------------------------------------------
-- settings and the «answer from published articles» preview (X-V3-2)
insert into app.help_test_questions (product, locale, question, created_by, created_at) values
  ('orgpuls', 'nb', 'Et gammelt spørsmål fra noen andre', (select id from app.admins where email = 'tor@orgpuls.no'), now() - interval '91 days'),
  ('orgpuls', 'nb', 'Et nyere spørsmål fra noen andre', (select id from app.admins where email = 'tor@orgpuls.no'), now() - interval '89 days');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.support_settings_save('orgpuls', false)$$, 'forbidden', 'tickets:configure', 'only tickets:configure changes the widget settings');
create temp table t_q as select public.help_question_ask('orgpuls', 'nb', 'Hvordan velger jeg språk for undersøkelsen?') q;
select pg_temp.check(not exists (select 1 from app.help_test_questions q where q.question = 'Et gammelt spørsmål fra noen andre')
                     and exists (select 1 from app.help_test_questions q where q.question = 'Et nyere spørsmål fra noen andre'),
                     'a test question goes after 90 days, whoever asked it');
insert into app.help_test_questions (product, locale, question, created_by, created_at)
values ('orgpuls', 'nb', 'Et spørsmål ingen spør etter igjen', (select id from app.admins where email = 'sara@orgpuls.no'), now() - interval '120 days');
select pg_temp.check(app.help_questions_prune() = 1, 'the nightly prune removes what is older than 90 days');
select pg_temp.check(not exists (select 1 from app.help_test_questions q where q.question = 'Et spørsmål ingen spør etter igjen'),
                     'although nobody asks again');
select pg_temp.check(exists (select 1 from app.job_defs d where d.key = 'help_questions_prune' and d.fn = 'app.help_questions_prune' and d.source = 'cron')
                     and exists (select 1 from cron.job j where j.jobname = 'platform-help-questions-prune' and j.command = 'select app.run_job(''help_questions_prune'')'),
                     'the prune runs every night through the job monitor');
create temp table t_ctx as select app.ai_ctx_help_answer_preview(((select q from t_q) ->> 'id')::uuid) c;
select pg_temp.check((select c ->> 'prompt' from t_ctx) like '%Hvordan velger jeg språk for undersøkelsen?%'
                     and (select c ->> 'prompt' from t_ctx) like '%Språk i undersøkelsen%', 'Claude reads the person''s question and the published articles');
select pg_temp.check((select c ->> 'prompt' from t_ctx) not like '%Choosing the survey language%' and (select c ->> 'prompt' from t_ctx) not like '%Importere ansatte%',
                     'never a draft, never another language');
select pg_temp.check(not exists (select 1 from app.tickets t, t_ctx where t.subject <> '' and (select c ->> 'prompt' from t_ctx) like '%' || t.subject || '%' and char_length(t.subject) > 20),
                     'no ticket text reaches the prompt');
select pg_temp.check((select (a.detail ->> 'locale') = 'nb' and a.detail::text not like '%språk%' from app.audit a where a.action = 'help_question.asked' order by a.at desc limit 1),
                     'the audit names the question, never its words');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(app.ai_ctx_help_answer_preview(((select q from t_q) ->> 'id')::uuid) is null, 'nobody runs another person''s question');
select pg_temp.check((public.support_settings_save('orgpuls', false) ->> 'ai_enabled')::boolean = false, 'the admin switches answers off');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_detail($$select public.help_question_ask('orgpuls', 'nb', 'Hvordan virker dette?')$$, 'module_off', 'ai_enabled', 'switched off, nothing is asked');
select pg_temp.check(app.ai_ctx_help_answer_preview(((select q from t_q) ->> 'id')::uuid) is null, 'and a question asked before is not sent either');
select pg_temp.as_staff('tor@orgpuls.no');
select public.support_settings_save('orgpuls', true);
select pg_temp.as_staff('ingrid@orgpuls.no');   -- Sales: no tickets:ai
select pg_temp.expect_detail($$select public.help_question_ask('orgpuls', 'nb', 'Hvordan virker dette?')$$, 'forbidden', 'tickets:ai', 'the preview needs tickets:ai');
select pg_temp.check((select key from app.ai_features where context_fn = 'app.ai_ctx_help_answer_preview') = 'help_answer_preview', 'the feature is registered with its context function');

-- ---------------------------------------------------------------------------
-- reads: results, channels, portal preview, widget, AI assist
select pg_temp.as_staff('jonas@orgpuls.no');
select pg_temp.expect_detail(format($$select public.%s$$, f), 'forbidden', 'tickets:see', 'Marketing reads no ' || split_part(f, '(', 1))
from unnest(array['support_results(''orgpuls'')', 'support_channels(''orgpuls'')', 'portal_preview(''orgpuls'')', 'support_widget_get(''orgpuls'')',
                  'support_assist_get(''orgpuls'')', 'status_get(''orgpuls'')']) f;
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_res as select public.support_results('orgpuls') r;
select pg_temp.check(((select r from t_res) -> 'tickets' ->> 'created')::int = (select count(*) from app.tickets t where t.product = 'orgpuls' and t.type <> 'problem'
                       and t.deleted_at is null and not t.is_sample and t.created_at >= now() - interval '30 days'), 'tickets created count the product''s tickets of 30 days');
select pg_temp.check(not ((select r from t_res) -> 'tickets' ->> 'previous_complete')::boolean, 'no delta while the previous period was not collected');
select pg_temp.check(not exists (select 1 from jsonb_array_elements((select r from t_res) -> 'gaps') g
                                 where exists (select 1 from app.help_articles a where a.product = 'orgpuls' and a.status = 'published' and a.category_key = g ->> 'category_key')),
                     'a gap is a category with tickets and no published article');
select pg_temp.check(not ((select r from t_res) -> 'gaps') @> '[{"category_key": "personvern"}]', 'a privacy request is never a help gap');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.support_results('orgpuls') -> 'tickets' ->> 'created')::int < ((select r from t_res) -> 'tickets' ->> 'created')::int,
                     'Sales counts no ticket of the personvern queue');
select pg_temp.check((public.portal_preview('orgpuls') ->> 'privacy_open') is null, 'nor the organisation''s privacy requests');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_ch as select public.support_channels('orgpuls') c;
select pg_temp.check((select sum((x ->> 'tickets')::int) from jsonb_array_elements((select c from t_ch) -> 'channels') x) = ((select c from t_ch) ->> 'total')::int,
                     'the channels add up to the total');
select pg_temp.check(jsonb_array_length((select c from t_ch) -> 'topics') = 4
                     and not exists (select 1 from jsonb_array_elements((select c from t_ch) -> 'topics') x
                                     where (x ->> 'since')::timestamptz > now() - interval '30 days' and x -> 'tickets' <> 'null'::jsonb),
                     'the contact form''s four topics; a topic recorded for less than the period has no count (it would be a false number)');
update app.contact_topic_routes set created_at = now() - interval '60 days' where product = 'orgpuls';
select pg_temp.check((public.support_channels('orgpuls') -> 'topics') @> '[{"topic": "privacy", "privacy": true, "visible": true, "tickets": 1}, {"topic": "pricing", "tickets": 2}]',
                     'once recorded for the whole period, each topic counts what it brought');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.support_channels('orgpuls') -> 'topics') @> '[{"topic": "privacy", "visible": false, "tickets": null}, {"topic": "pricing", "visible": true, "tickets": 2}]',
                     'a topic whose queue the reader does not see has no count, never a false 0');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_pp as select public.portal_preview('orgpuls') p;
select pg_temp.check(jsonb_array_length((select p from t_pp) -> 'organizations') > 0 and (select p from t_pp) -> 'organization' ->> 'id' = (select p from t_pp) -> 'organizations' -> 0 ->> 'id',
                     'the portal preview opens the organisation with the newest ticket');
select pg_temp.check(not exists (select 1 from jsonb_array_elements((select p from t_pp) -> 'tickets') x
                                 where (x ->> 'state') <> case when x ->> 'status' in ('resolved', 'closed') then 'done' when x ->> 'status' = 'waiting_customer' then 'you' else 'us' end),
                     'statuses are put in the customer''s words');
select pg_temp.check((public.portal_preview('orgpuls', gen_random_uuid()) -> 'organization' ->> 'id') = (select p from t_pp) -> 'organization' ->> 'id',
                     'an organisation without visible tickets is not previewed');
create temp table t_wg as select public.support_widget_get('orgpuls') w;
select pg_temp.check(((select w from t_wg) -> 'pages') @> '["/malinger", "/resultater"]' and not ((select w from t_wg) -> 'pages') @> '["/s"]', 'the app pages, never a respondent page');
select pg_temp.check(((select w from t_wg) -> 'last_request' ->> 'ref') like 'T-%', 'the widget card reads the newest in-app request');
create temp table t_band as
  select ap.tenant_id, s.plan from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
  join app.organizations o on o.account_id = ap.account_id and o.deleted_at is null
  where ap.product = 'orgpuls' and ap.status = 'active' and s.plan in (select pv.band_label from app.plan_versions pv where pv.product = 'orgpuls') limit 1;
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at)
values ('orgpuls', 990000110, 'support.requested', (select tenant_id from t_band),
        '{"category": "getting_started", "subject": "Hjelp", "body": "Hvor finner jeg rapporten?", "email": "band.test@example.no", "role": "Daglig leder"}', now());
-- every ticket of this transaction has the same created_at: make this one the newest
update app.tickets set created_at = now() + interval '1 second' where id = (select id from pg_temp.ticket_of(990000110));
select pg_temp.check((public.support_widget_get('orgpuls') -> 'last_request' -> 'organization' ->> 'band') = (select plan from t_band),
                     'its organisation carries the size band of its subscription to this product');
create temp table t_as as select public.support_assist_get('orgpuls') a;
select pg_temp.check((select a -> 'ticket' from t_as) is not null and not ((select a -> 'ticket' from t_as) ? 'messages'), 'AI assist names the ticket, never its thread');
select pg_temp.check(((select a from t_as) -> 'usage' ->> 'previews')::int = 0, 'no preview has reached Claude here');
select pg_temp.check(((select a from t_as) -> 'titles') ? 'Invitasjoner kommer ikke frem' and not (((select a from t_as) -> 'titles') ? 'Importere ansatte fra Visma'),
                     'an answer may cite a published title, never a draft''s');

-- ---------------------------------------------------------------------------
-- status: components, incidents, resolve and notify
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail($$select public.status_component_save(null, 'orgpuls', 'Orgpuls app')$$, 'forbidden', 'tickets:edit_others', 'Read-only adds no component');
select pg_temp.as_staff('hanna@orgpuls.no');
create temp table t_comp as select (public.status_component_save(null, 'orgpuls', 'Utsending (e-post)') ->> 'id')::uuid id;
select pg_temp.expect_detail($$select public.status_component_save(null, 'orgpuls', 'utsending (E-POST)')$$, 'invalid', 'name', 'a component name is unique per product');
select pg_temp.check((public.status_component_set((select id from t_comp), 'degraded') ->> 'ok')::boolean, 'a component''s state is set');
select pg_temp.expect_detail(format($$select public.status_component_set(%L, 'down')$$, (select id from t_comp)), 'invalid', 'state', 'only the four states');
create temp table t_inc as select (public.status_incident_open('orgpuls', 'Forsinkede invitasjoner til kommunale domener', 'Noen kommunale e-postservere holder igjen e-post.',
                                                               (select id from app.tickets where number = 2316), array[(select id from t_comp)]) ->> 'id')::uuid id;
select pg_temp.expect_detail($$select public.status_incident_open('orgpuls', 'Tittel her', 'Tekst', gen_random_uuid(), '{}')$$, 'invalid', 'problem', 'the problem must be a problem ticket');
select pg_temp.check((public.status_incident_update((select id from t_inc), 'identified', 'Vi har funnet årsaken.') ->> 'ok')::boolean, 'an update is posted');
select pg_temp.expect_error(format($$update app.status_incident_updates set body = 'endret' where incident_id = %L$$, (select id from t_inc)), 'a status update is append-only',
                            'an update cannot be changed');
select pg_temp.expect_error(format($$delete from app.status_incident_updates where incident_id = %L$$, (select id from t_inc)), 'a status update is append-only',
                            'an update cannot be deleted while its incident exists');
create temp table t_st as select public.status_get('orgpuls') s;
select pg_temp.check(((select s from t_st) -> 'incidents' -> 0 -> 'notice' ->> 'state') = 'not_delivered' and ((select s from t_st) -> 'incidents' -> 0 ->> 'linked')::int = 3
                     and ((select s from t_st) -> 'incidents' -> 0 ->> 'customers')::int >= 1 and jsonb_array_length((select s from t_st) -> 'incidents' -> 0 -> 'updates') = 2,
                     'the incident shows its linked tickets, customers and updates; a notice Orgpuls never took is «not delivered», not «on the website»');
create temp table t_notice as select n.id from app.status_notices n where n.problem_ticket_id = (select id from app.tickets where number = 2316) and n.cleared_at is null and n.text is not null;
select pg_temp.as_service();
select public.worker_status_notice_pushed((select id from t_notice), false, 'http_500');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((public.status_get('orgpuls') -> 'incidents') @> jsonb_build_array(jsonb_build_object('id', (select id from t_inc), 'notice', jsonb_build_object('state', 'not_delivered', 'error', 'http_500'))),
                     'a failed push says why');
select pg_temp.as_service();
select public.worker_status_notice_pushed((select id from t_notice), true);
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check((public.status_get('orgpuls') -> 'incidents') @> jsonb_build_array(jsonb_build_object('id', (select id from t_inc), 'notice', jsonb_build_object('state', 'shown'))),
                     'only a delivered notice is on the public website');
select pg_temp.expect_detail(format($$select public.status_incident_resolve(%L, '  ')$$, (select id from t_inc)), 'invalid', 'message', 'resolving needs a message for the customers');
create temp table t_open as select count(*) n from app.tickets t where t.problem_id = (select id from app.tickets where number = 2316) and t.status not in ('resolved', 'closed');
create temp table t_rs as select public.status_incident_resolve((select id from t_inc), 'Problemet er løst. Invitasjonene er sendt på nytt.') r;
select pg_temp.check(((select r from t_rs) ->> 'notified')::int = (select n from t_open) and (select n from t_open) > 0, 'resolve and notify answers every open ticket of the problem');
select pg_temp.check(((select r from t_rs) ->> 'mail_ready')::boolean is not distinct from app.mail_ready_for('orgpuls'),
                     'and says whether those replies can be emailed at all');
select pg_temp.check((select problem_status from app.tickets where number = 2316) = 'resolved'
                     and not exists (select 1 from app.tickets t where t.problem_id = (select id from app.tickets where number = 2316) and t.status not in ('resolved', 'closed')),
                     'the problem and its tickets are resolved');
select pg_temp.check((select state from app.status_components where id = (select id from t_comp)) = 'operational', 'the component returns to operational');
select pg_temp.check(not exists (select 1 from app.status_notices n where n.problem_ticket_id = (select id from app.tickets where number = 2316) and n.cleared_at is null and n.text is not null),
                     'the site notice tied to the problem is cleared');
select pg_temp.check(((public.status_get('orgpuls') -> 'incidents') @> jsonb_build_array(jsonb_build_object('id', (select id from t_inc), 'state', 'resolved',
                                                                                                             'notice', jsonb_build_object('state', 'removal_not_delivered')))),
                     'the incident says the removal is saved and not yet delivered');
select pg_temp.as_service();
select public.worker_status_notice_pushed((select n.id from app.status_notices n where n.product = 'orgpuls' and n.text is null order by n.set_at desc limit 1), true);
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.check(((public.status_get('orgpuls') -> 'incidents') @> jsonb_build_array(jsonb_build_object('id', (select id from t_inc), 'notice', jsonb_build_object('state', 'removed')))),
                     'and «removed» once the clearing push is delivered');
select pg_temp.expect_detail(format($$select public.status_incident_resolve(%L, 'Igjen')$$, (select id from t_inc)), 'invalid', 'state', 'a resolved incident is not resolved twice');
select pg_temp.check((public.status_incident_resolve((public.status_incident_open('orgpuls', 'Planlagt vedlikehold', 'Kort nedetid i natt.', null, '{}') ->> 'id')::uuid,
                                                     'Ferdig.') ->> 'notified')::int = 0, 'an incident without a problem resolves and tells nobody');
select pg_temp.check((public.status_component_remove((select id from t_comp)) ->> 'ok')::boolean, 'a component is removed');

-- ---------------------------------------------------------------------------
-- CSAT: the resolving reply asks once; a single-use token takes a score and nothing else
update app.integration_connections set status = 'connected' where provider = 'email';
update app.sender_domains set sends_here = true, spf_ok = true, dkim_ok = true, dmarc_policy = 'none', verified_at = now() where domain = 'varsler.orgpuls.no';
create temp table t_cs as
  with t as (insert into app.tickets (subject, category_key, queue_key, status, requester_email, product, channel)
             values ('CSAT-test', 'billing', 'billing', 'open', 'csat.test@example.no', 'orgpuls', 'email') returning id)
  select id from t;
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_r1 as select public.ticket_message((select id from t_cs), 'reply', 'Vi ser på det.', 'waiting_customer') r;
select pg_temp.as_service();
create temp table t_c1 as select public.worker_ticket_mail_claim(100) c;
select pg_temp.check(exists (select 1 from jsonb_array_elements((select c from t_c1)) x where x ->> 'id' = (select r ->> 'id' from t_r1) and x ->> 'csat_token' is null),
                     'a reply that does not resolve asks nothing');
select public.worker_ticket_mail_done(((select r from t_r1) ->> 'id')::uuid, '<csat-1@x>');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_r2 as select public.ticket_message((select id from t_cs), 'reply', 'Dette er løst nå.', 'resolved') r;
select pg_temp.as_service();
-- without a public address there is no page to answer on: nothing is asked
update app.mail_settings set public_base = null, app_bases = '{}'::jsonb where true;
create temp table t_c0 as select (select x from jsonb_array_elements(public.worker_ticket_mail_claim(100)) x where x ->> 'id' = (select r ->> 'id' from t_r2)) m;
select pg_temp.check((select m is not null and m ->> 'csat_token' is null and m ->> 'csat_base' is null from t_c0)
                     and (select csat_requested_at is null and csat_token_hash is null from app.tickets where id = (select id from t_cs)),
                     'no public address: the reply goes without the question, and nothing counts as asked');
update app.ticket_messages set mail_claimed_at = null where id = ((select r from t_r2) ->> 'id')::uuid;
update app.mail_settings set public_base = 'https://sentral.example.no', app_bases = '{"orgpuls": "https://post.orgpuls.no"}'::jsonb where true;
create temp table t_c2m as select (select x from jsonb_array_elements(public.worker_ticket_mail_claim(100)) x where x ->> 'id' = (select r ->> 'id' from t_r2)) m;
create temp table t_c2 as select m ->> 'csat_token' tok from t_c2m;
select pg_temp.check((select tok from t_c2) ~ '^[A-Za-z0-9_-]{32}$', 'the resolving reply carries a token');
select pg_temp.check((select m ->> 'csat_base' from t_c2m) = 'https://post.orgpuls.no', 'its links open on the application''s own link address');
select pg_temp.check((public.worker_csat_peek((select tok from t_c2)) ->> 'open')::boolean
                     and (public.worker_csat_peek((select tok from t_c2)) ->> 'from_name') is not null
                     and public.worker_csat_peek((select tok from t_c2)) - 'open' - 'from_name' = '{}'::jsonb,
                     'the page may ask whether a token is open: the answer names the sender and nothing else');
select pg_temp.check(not (public.worker_csat_peek('short') ->> 'open')::boolean and not (public.worker_csat_peek(repeat('x', 32)) ->> 'open')::boolean,
                     'a malformed or unknown token is not open');
select pg_temp.check((select csat_token_hash = extensions.digest((select tok from t_c2), 'sha256') and csat_requested_at is not null from app.tickets where id = (select id from t_cs)),
                     'the ticket keeps only its hash');
-- the send fails for good: nobody was asked, so the request is taken back
select public.worker_ticket_mail_done(((select r from t_r2) ->> 'id')::uuid, null, 'http_400', false);
select pg_temp.check((select csat_token_hash is null and csat_requested_at is null from app.tickets where id = (select id from t_cs)), 'a reply that never went out asks nothing');
update app.ticket_messages set delivery_status = 'queued', mail_claimed_at = null where id = ((select r from t_r2) ->> 'id')::uuid;
create temp table t_c3 as select (select x ->> 'csat_token' from jsonb_array_elements(public.worker_ticket_mail_claim(100)) x where x ->> 'id' = (select r ->> 'id' from t_r2)) tok;
select public.worker_ticket_mail_done(((select r from t_r2) ->> 'id')::uuid, '<csat-2@x>');
select pg_temp.check((select tok from t_c3) is not null and (select tok from t_c3) <> (select tok from t_c2), 'a new send gets a new token');
select pg_temp.check(((public.worker_csat_submit((select tok from t_c2), 5)) ->> 'ok')::boolean = false, 'the old token is void');
select pg_temp.check((public.worker_csat_submit((select tok from t_c3), 6) ->> 'code') = 'invalid', 'a score is 1 to 5');
select pg_temp.check((public.worker_csat_submit('short', 4) ->> 'code') = 'unknown', 'a malformed token is unknown');
select pg_temp.check((public.worker_csat_submit((select tok from t_c3), 4) ->> 'score')::int = 4, 'one click records the score');
select pg_temp.check((select csat_score = 4 and csat_at is not null and csat_token_hash is null from app.tickets where id = (select id from t_cs)), 'the ticket has its score; the token is spent');
select pg_temp.check((public.worker_csat_submit((select tok from t_c3), 1) ->> 'code') = 'used_or_unknown', 'the token works once');
select pg_temp.check(not (public.worker_csat_peek((select tok from t_c3)) ->> 'open')::boolean, 'and a spent token is no longer open');
select pg_temp.check((select a.detail is null from app.audit a where a.action = 'ticket.csat_answered' and a.target_id = (select id::text from t_cs)), 'the audit names the ticket only');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check((public.support_results('orgpuls') -> 'csat' ->> 'answered')::int >= 1, 'Support results count the answer');
-- an answer to a token older than 30 days is refused
update app.tickets set csat_at = null, csat_score = null, csat_token_hash = extensions.digest('A' || repeat('b', 31), 'sha256'), csat_requested_at = now() - interval '31 days'
where id = (select id from t_cs);
select pg_temp.as_service();
select pg_temp.check((public.worker_csat_submit('A' || repeat('b', 31), 3) ->> 'code') = 'used_or_unknown', 'a token older than 30 days is refused');

rollback;
