-- phase1_invariants.sql — deals, activities, leads, consent, merge, import, tickets (phase 1).
\ir _helpers.psql
begin;

select pg_temp.as_staff('ingrid@orgpuls.no');
-- a deal starts in a stage, moves, and keeps its stage history
create temp table t_d as select (public.deal_create(jsonb_build_object('title', 'Testavtale', 'value', 10000, 'pipeline_id', (select id from app.pipelines where name = 'New business'))) ->> 'id')::uuid id;
select pg_temp.check((select s.name from app.deals d join app.stages s on s.id = d.stage_id where d.id = (select id from t_d)) = 'Qualified', 'a new deal starts in the first stage');
select public.deal_move((select id from t_d), (select id from app.stages where name = 'Demo'));
select pg_temp.check((select count(*) from app.deal_stage_history where deal_id = (select id from t_d)) = 2, 'a move closes one history row and opens another');
select pg_temp.check(exists (select 1 from app.events where kind = 'deal.stage_changed' and subject_id = (select id from t_d)), 'a move emits deal.stage_changed');
-- a field required from a stage blocks the move until it is filled
select pg_temp.as_staff('tor@orgpuls.no');
select public.field_save(null, jsonb_build_object('entity', 'deal', 'key', 'decision_maker', 'label', 'Decision maker', 'type', 'text', 'quality', 'required',
  'from_stage_id', (select id from app.stages where name = 'Negotiation')));
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(jsonb_array_length(public.deal_move((select id from t_d), (select id from app.stages where name = 'Negotiation')) -> 'missing') = 1, 'a required field is reported missing');
select pg_temp.check((select s.name from app.deals d join app.stages s on s.id = d.stage_id where d.id = (select id from t_d)) = 'Demo', 'and the deal stays where it was');
select public.deal_move((select id from t_d), (select id from app.stages where name = 'Negotiation'), null, '{"decision_maker":"Kari"}');
select pg_temp.check((select custom ->> 'decision_maker' from app.deals where id = (select id from t_d)) = 'Kari', 'the move fills the field and goes through');
-- rotting is derived from idle days against the stage threshold
select pg_temp.as_nobody();
update app.deals set last_activity_at = now() - interval '30 days' where id = (select id from t_d);
select pg_temp.check((app.deal_card((select d from app.deals d where d.id = (select id from t_d))) ->> 'rotting')::boolean, 'a deal idle past its stage threshold is rotting');
-- an activity completed resets the idle clock; the card shows planned while one is open
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_a as select (public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'call'), 'subject', 'Ring', 'deal_id', (select id from t_d),
  'starts_at', now() + interval '1 day')) ->> 'id')::uuid id;
select pg_temp.check(app.deal_act((select id from t_d)) = 'planned', 'an open future activity makes the card planned');
select public.activity_done((select id from t_a), true);
select pg_temp.check((select last_activity_at > now() - interval '1 minute' from app.deals where id = (select id from t_d)), 'completing an activity resets the idle clock');
select pg_temp.check(app.deal_act((select id from t_d)) = 'none', 'with nothing open the card shows no next step');
-- lost with a reason, required when the register says so
select pg_temp.as_staff('tor@orgpuls.no');
select public.setting_set('lost_reason_required', 'on');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format($$select public.deal_status(%L, 'lost')$$, (select id from t_d)), 'invalid', 'a lost reason is required when the setting is on');
select public.deal_status((select id from t_d), 'lost', 'Price', 'They chose a cheaper tool');
select pg_temp.check((select status = 'lost' and lost_reason = 'Price' from app.deals where id = (select id from t_d)), 'a deal is lost with its reason');
select pg_temp.check(exists (select 1 from app.notes where entity = 'deal' and record_id = (select id from t_d) and body = 'They chose a cheaper tool'), 'the comment becomes a note');
-- deal lines recalculate the value when the deal takes its value from lines
select public.rec_save('deal', (select id from t_d), '{"value_source":"items"}');
select public.deal_item_save((select id from t_d), null, '{"name":"Seats","quantity":10,"unit_price":39,"billing":"recurring","billing_frequency":"monthly","cycles":12}');
select pg_temp.check((select value from app.deals where id = (select id from t_d)) = 4680, 'the value is the lines'' total contract value');

-- a lead converts to a deal; notes and activities move with it
create temp table t_l as select (public.rec_save('lead', null, jsonb_build_object('title', 'Testlead', 'organization_id', (select id from app.organizations order by name limit 1), 'value', 5000)) ->> 'id')::uuid id;
select public.note_save('lead', (select id from t_l), null, 'Spør om pris');
select pg_temp.expect_error($$select public.rec_save('lead', null, '{"title":"Uten kobling"}')$$, 'new row for relation "leads" violates check constraint "leads_check"', 'a lead needs a person or an organization');
create temp table t_c as select (public.lead_convert((select id from t_l), (select id from app.pipelines where name = 'New business'), null) ->> 'deal_id')::uuid id;
select pg_temp.check(exists (select 1 from app.notes where entity = 'deal' and record_id = (select id from t_c) and body = 'Spør om pris'), 'the lead''s note moves to the deal');
select pg_temp.check((select archived_at is not null and converted_deal_id = (select id from t_c) from app.leads where id = (select id from t_l)), 'the lead is archived and points at its deal');

-- consent: only through consent_set, and the ledger cannot be changed
create temp table t_p as select (public.rec_save('person', null, '{"name":"Samtykke Test","email":"samtykke@example.com"}') ->> 'id')::uuid id;
select pg_temp.expect_error(format($$select public.rec_save('person', %L, '{"marketing_status":"subscribed"}')$$, (select id from t_p)), 'invalid', 'marketing status cannot be written directly');
select public.consent_set((select id from t_p), 'subscribed', 'Event', 'Signed up at the stand');
select pg_temp.check((select marketing_status from app.people where id = (select id from t_p)) = 'subscribed', 'consent_set changes the status');
select pg_temp.as_nobody();
select pg_temp.expect_error(format($$update app.consent_events set status = 'bounced' where person_id = %L$$, (select id from t_p)), 'the consent ledger is append-only', 'the consent ledger cannot be changed');

-- duplicates and merge
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_p2 as select (public.rec_save('person', null, '{"name":"Samtykke Test","email":"SAMTYKKE@example.com","phone":"+47 400 00 000"}') ->> 'id')::uuid id;
select pg_temp.check(jsonb_array_length(public.duplicates_get(true)) >= 1, 'the scan finds people with the same email');
select public.records_merge('person', (select id from t_p), (select id from t_p2));
select pg_temp.check((select phone from app.people where id = (select id from t_p)) = '+47 400 00 000', 'the kept person gains the other''s missing value');
select pg_temp.check((select deleted_at is not null from app.people where id = (select id from t_p2)), 'the merged person is soft-deleted');
select public.setting_set('second_admin', 'on');
select pg_temp.expect_error(format($$select public.records_merge('person', %L, %L)$$, (select id from t_p), (select id from app.people where id <> (select id from t_p) and deleted_at is null limit 1)), 'approval_required', 'with second-admin approval on, a merge waits for approval');
select public.setting_set('second_admin', 'off');

-- import: every row accounted for, and revertable
create temp table t_i as select public.import_run('person', '[{"name":"Import En","email":"en@example.com"},{"name":"Samtykke","email":"samtykke@example.com","title":"HR"},{"email":"mangler-navn@example.com"}]'::jsonb, 'merge') r;
select pg_temp.check(((select r from t_i) ->> 'created')::int = 1 and ((select r from t_i) ->> 'merged')::int = 1 and ((select r from t_i) ->> 'skipped')::int = 1, 'an import accounts for every row');
select public.import_revert(((select r from t_i) ->> 'id')::uuid);
select pg_temp.check((select deleted_at is not null from app.people where email = 'en@example.com'), 'a revert deletes what the import created');
select pg_temp.check((select title is null from app.people where id = (select id from t_p)), 'and gives a merged record its earlier values');

-- tickets: priority follows impact × urgency, SLA due times are set, queues are restricted
create temp table t_t as select (public.ticket_create('{"category_key":"survey_delivery","subject":"Testsak","impact":"many_orgs","urgency":"blocking"}') ->> 'id')::uuid id;
select pg_temp.check((select priority from app.tickets where id = (select id from t_t)) = 'urgent', 'many organizations and blocking is urgent');
select pg_temp.check((select first_response_due_at is not null and resolution_due_at > first_response_due_at from app.tickets where id = (select id from t_t)), 'SLA due times are set');
select public.ticket_message((select id from t_t), 'reply', 'Vi ser på det.', 'waiting_customer');
select pg_temp.check((select first_response_at is not null and status = 'waiting_customer' from app.tickets where id = (select id from t_t)), 'a reply sets the first response and the chosen status');
select pg_temp.check(not exists (select 1 from app.audit where target_id = (select id::text from t_t) and detail::text like '%Vi ser på det%'), 'a message body never goes into the audit');
select public.rec_save('ticket', (select id from t_t), '{"status":"resolved"}');
select public.rec_save('ticket', (select id from t_t), '{"status":"open"}');
select pg_temp.check((select reopened_count from app.tickets where id = (select id from t_t)) = 1, 'reopening a resolved ticket is counted');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.tickets_get('{"view":"closed"}') -> 'rows') r where r ->> 'queue_key' = 'personvern')
  and not exists (select 1 from jsonb_array_elements(public.tickets_get() -> 'rows') r where r ->> 'queue_key' = 'personvern'), 'sales does not see the personvern queue');
select pg_temp.expect_error(format($$select public.ticket_detail(%L)$$, (select id from app.tickets where queue_key = 'personvern' limit 1)), 'not_found', 'nor open a personvern ticket');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_error($$select public.ticket_create('{"category_key":"bug","subject":"x"}')$$, 'forbidden', 'the analyst cannot create a ticket');

-- a product event creates a ticket (D-20)
select pg_temp.as_nobody();
insert into app.events_in (product, source_id, kind, tenant_id, payload, occurred_at)
values ('orgpuls', 999001, 'support.requested', 'orgpuls-o1', '{"subject":"Fra appen","message":"Hjelp, takk","page":"/oppsett"}', now());
select pg_temp.check(exists (select 1 from app.tickets t join app.ticket_messages m on m.ticket_id = t.id where t.subject = 'Fra appen' and t.channel = 'in_app' and m.kind = 'customer'), 'support.requested becomes a ticket with the message in the thread');

rollback;
