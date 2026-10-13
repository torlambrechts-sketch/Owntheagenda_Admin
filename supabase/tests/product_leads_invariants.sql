-- product_leads_invariants.sql — a product's free-template download and demo request (0087): each becomes a ticket in the
-- Sales queue and a CRM lead with the person captured; the ticket keeps what the form asked (template, role, organisation,
-- the consent answer, language) and nothing else; the lead's title is the category and the template, never words of the
-- person's; the consent answer changes no marketing status; a request is taken once; a request received before there was a
-- way in is taken by the migration; the registry knows the kind.
\ir _helpers.psql
begin;

create or replace function pg_temp.ticket_of(p_source bigint) returns app.tickets language sql as $$
  select t.* from app.tickets t join app.events_in e on e.id = t.source_event_id where e.product = 'orgpuls' and e.source_id = p_source
$$;
create or replace function pg_temp.lead_of(p_source bigint) returns app.leads language sql as $$
  select l.* from app.leads l join app.ticket_links k on k.ref = l.id::text and k.kind = 'lead'
  where k.ticket_id = (select id from pg_temp.ticket_of(p_source))
$$;

insert into app.events_in (product, source_id, kind, payload, occurred_at) values
  ('orgpuls', 990000201, 'template.requested',
   '{"template": "qpsnordic-sporreskjema", "name": "Mal Test", "email": "Mal.Test@example.no", "role": "fysioterapeut", "consent": false, "lang": "no"}', now()),
  ('orgpuls', 990000202, 'template.requested',
   '{"template": "tiltaksbank", "name": "Samtykke Test", "email": "samtykke.test@example.no", "organisation": "Testbedriften AS", "consent": true, "lang": "no"}', now()),
  ('orgpuls', 990000203, 'demo.requested', '{"name": "Demo Test", "email": "demo.test@example.no", "company": "Demofirma AS", "role": "HR"}', now()),
  ('orgpuls', 990000204, 'template.requested', '{"template": "../../etc", "name": "Rar Test", "email": "rar.test@example.no", "message": "Ring meg på 99999999"}', now());

select pg_temp.check((select category_key = 'free_template' and queue_key = 'sales' and channel = 'contact_form'
                      from pg_temp.ticket_of(990000201)),
                     'a free-template download is a ticket in the Sales queue');
select pg_temp.check((select subject from pg_temp.ticket_of(990000201)) = 'Free template: qpsnordic-sporreskjema',
                     'its subject is the category and the template');
select pg_temp.check((select context = '{"template": "qpsnordic-sporreskjema", "role": "fysioterapeut", "consent": false, "lang": "no"}'::jsonb
                      from pg_temp.ticket_of(990000201)),
                     'the ticket keeps what the form asked, and the consent answer as given');
select pg_temp.check((select l.title = 'Free template: qpsnordic-sporreskjema' and l.source = 'Free template'
                             and l.form_data = '{"template": "qpsnordic-sporreskjema", "role": "fysioterapeut", "consent": false, "lang": "no"}'::jsonb
                      from pg_temp.lead_of(990000201) l),
                     'and makes a CRM lead with the same values');
select pg_temp.check((select p.email = 'mal.test@example.no' and p.name = 'Mal Test' and p.contact_type = 'prospect' and p.marketing_status = 'no_consent'
                      from app.people p where p.id = (select person_id from pg_temp.ticket_of(990000201))),
                     'the person is captured as a prospect, by the lower-cased address, without marketing consent');
select pg_temp.check((select p.marketing_status = 'no_consent' and not exists (select 1 from app.consent_events c where c.person_id = p.id)
                      from app.people p where p.id = (select person_id from pg_temp.ticket_of(990000202))),
                     'a «yes» in a product''s form does not make the person subscribed: no wording shown by Sentral, no double opt-in');
select pg_temp.check((select context ->> 'organisation' = 'Testbedriften AS' and (context -> 'consent') = 'true'::jsonb from pg_temp.ticket_of(990000202)),
                     'the «yes» and the organisation are kept for the person following up');
select pg_temp.check((select category_key = 'demo' and queue_key = 'sales' and subject = 'Demo request' and context ->> 'organisation' = 'Demofirma AS'
                      from pg_temp.ticket_of(990000203)),
                     'a demo request is a ticket in Sales, its company kept as the organisation');
select pg_temp.check((select title = 'Demo request' and source = 'Demo request' from pg_temp.lead_of(990000203)), 'and a CRM lead');
select pg_temp.check((select subject = 'Free template' and not (context ? 'template') from pg_temp.ticket_of(990000204)),
                     'a template name of the wrong shape is not kept');
select pg_temp.check(not exists (select 1 from app.ticket_messages m where m.ticket_id = (select id from pg_temp.ticket_of(990000204)))
                     and (select l.title not like '%99999999%' and coalesce(l.form_data::text, '') not like '%99999999%' from pg_temp.lead_of(990000204) l)
                     and (select subject not like '%99999999%' and context::text not like '%99999999%' from pg_temp.ticket_of(990000204)),
                     'a template request''s stray text is not read: not in the ticket, its subject or context, nor the lead');

-- taken once, and taken late: a request received while the trigger did not read its kind
select app.ticket_intake((select id from app.events_in where product = 'orgpuls' and source_id = 990000201));
alter table app.events_in disable trigger events_in_tickets;
insert into app.events_in (product, source_id, kind, payload, occurred_at) values
  ('orgpuls', 990000205, 'template.requested', '{"template": "tiltaksbank", "name": "Sen Test", "email": "sen.test@example.no", "consent": false}', now());
alter table app.events_in enable trigger events_in_tickets;
select pg_temp.check((select id from pg_temp.ticket_of(990000205)) is null, '(a request with no ticket)');
select app.ticket_intake((select id from app.events_in where product = 'orgpuls' and source_id = 990000205));
select pg_temp.check((select category_key = 'free_template' from pg_temp.ticket_of(990000205)) and (select id from pg_temp.lead_of(990000205)) is not null,
                     'app.ticket_intake takes a request received before there was a way in');
select pg_temp.check((select count(*) from app.tickets t join app.events_in e on e.id = t.source_event_id where e.source_id = 990000201) = 1
                     and (select count(*) from app.ticket_links k where k.ticket_id = (select id from pg_temp.ticket_of(990000201)) and k.kind = 'lead') = 1,
                     'a request is taken once');

-- the registry
select pg_temp.check((select uses = array['tickets', 'leads'] from app.product_event_kinds where product = 'orgpuls' and kind = 'template.requested')
                     and (select uses = array['tickets', 'leads'] from app.product_event_kinds where product = 'orgpuls' and kind = 'demo.requested'),
                     'the registry says what template and demo requests feed');

rollback;
