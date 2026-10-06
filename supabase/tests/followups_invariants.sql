-- followups_invariants.sql — the gaps closed after the Phase 2 screens (0026 onwards).
\ir _helpers.psql
begin;

select pg_temp.as_staff('tor@orgpuls.no');

-- a workflow cannot be switched on while it enrolls into a draft sequence
create temp table t_seq as select id from app.workflows where kind = 'sequence' and state = 'draft' and deleted_at is null limit 1;
create temp table t_wfs as select (public.workflow_save(null, '{"name":"Enroll in a draft","trigger_type":"event","trigger_config":{"entity":"deal","event":"created"}}',
  jsonb_build_object('steps', jsonb_build_array(jsonb_build_object('key', 'a', 'kind', 'enroll_sequence', 'config', jsonb_build_object('sequence_id', (select id from t_seq)))))) ->> 'id')::uuid id;
select pg_temp.check('sequence_inactive' = any (app.wf_blockers((select id from t_wfs))), 'a draft sequence is a blocker');
select pg_temp.expect_error(format($$select public.workflow_set_state(%L, 'active')$$, (select id from t_wfs)), 'invalid', 'switching on is refused while the sequence is a draft');
update app.workflows set state = 'active' where id = (select id from t_seq);
select pg_temp.check(not ('sequence_inactive' = any (app.wf_blockers((select id from t_wfs)))), 'an active sequence is no longer a blocker');

-- the deal panel explains its score
create temp table t_sd as select d.id from app.deals d join app.record_scores r on r.entity = 'deal' and r.record_id = d.id
  where d.deleted_at is null and d.score_breakdown is not null limit 1;
select pg_temp.check((public.deal_detail((select id from t_sd)) -> 'score_breakdown') = (select score_breakdown from app.deals where id = (select id from t_sd))
                 and (public.deal_detail((select id from t_sd)) -> 'score_model' ->> 'name') is not null, 'deal_detail carries the score breakdown and its model');

-- Feed (0027): the owner on a card, a score range, enrichment candidates, the clicked link's sequence, deleting a model
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.feed_get('overlooked') -> 'cards') c where c -> 'deal' is not null and not (c -> 'deal' ? 'owner'))
                     and exists (select 1 from jsonb_array_elements(public.feed_get('overlooked') -> 'cards') c where c -> 'deal' ->> 'owner' is not null)
                     or jsonb_array_length(public.feed_get('overlooked') -> 'cards') = 0, 'feed cards name the deal owner');
insert into app.setting_values (key, value) values ('ai_scoring', 'on') on conflict (key, scope_id) do update set value = 'on';
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.feed_get('overlooked', '{"score_min":101}') -> 'cards') c), 'a score range above every score leaves no card');
select pg_temp.check((select jsonb_array_length(e -> 'candidate_ids') = least((e ->> 'candidates')::int, 100) from (select public.enrichment_get() e) x), 'the candidate ids are the counted organizations');
create temp table t_m as select m.id, m.thread_id from app.email_messages m where m.direction = 'out' limit 1;
create temp table t_od as select id from app.deals where status = 'open' and deleted_at is null and owner_id is not null and not is_sample limit 1;
create temp table t_en as select app.seq_enroll((select id from t_seq), 'deal', (select id from t_od), 'one', (select id from app.admins where email = 'tor@orgpuls.no')) id;
insert into app.events (kind, subject_type, subject_id, payload)
values ('email.clicked', 'email_thread', (select thread_id from t_m),
        jsonb_build_object('message', (select id from t_m), 'label', 'Pris', 'enrollment', (select id from t_en), 'links', jsonb_build_array(jsonb_build_object('entity', 'deal', 'id', (select id from t_od)))));
select app.sub_feed(e) from app.events e where e.id = (select max(id) from app.events);
select pg_temp.check((select params ->> 'sequence' = (select name from app.workflows where id = (select id from t_seq)) and params ? 'step' from app.feed_cards
                      where kind = 'link_clicked' and deal_id = (select id from t_od) order by created_at desc limit 1), 'a clicked link in a sequence names the sequence and step');
create temp table t_sm as select id from app.score_models where state = 'draft' and deleted_at is null limit 1;
select public.score_model_delete((select id from t_sm));
select pg_temp.check((select deleted_at is not null from app.score_models where id = (select id from t_sm)), 'a draft scoring model can be deleted');
select pg_temp.expect_error(format($$select public.score_model_delete(%L)$$, (select id from app.score_models where state = 'active' and deleted_at is null limit 1)), 'invalid', 'an active model is set to draft before it is deleted');

-- Health in the Phase 1 screens (0028)
create temp table t_hs as select ap.product, ap.tenant_id, ap.account_id, (select o.id from app.organizations o where o.account_id = ap.account_id limit 1) org
  from app.account_products ap where ap.status = 'active' and exists (select 1 from app.organizations o where o.account_id = ap.account_id) limit 1;
insert into app.health_scores (product, tenant_id, day, score, factors, model_id)
select product, tenant_id, current_date, 20, '[]', (select id from app.health_models where active) from t_hs
on conflict (product, tenant_id, day) do update set score = 20;
update app.subscriptions s set current_period_end = now() + interval '10 days' from t_hs h where s.product = h.product and s.tenant_id = h.tenant_id;
create temp table t_tk as select id from app.tickets where queue_key = 'support' and deleted_at is null limit 1;
update app.tickets set organization_id = (select org from t_hs) where id = (select id from t_tk);
select pg_temp.check((public.ticket_detail((select id from t_tk)) #>> '{ticket,organization,health}')::int = app.org_health((select org from t_hs))
                     or (public.ticket_detail((select id from t_tk)) #>> '{organization,health}')::int = app.org_health((select org from t_hs)), 'a ticket names its company''s health');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.customers_get('{}') -> 'rows') x where (x ->> 'id')::uuid = (select org from t_hs) and x ? 'renews_at'), 'a company row names its next renewal');
select pg_temp.check(
  (select (x ->> 'status') = 'cancelled' or exists (select 1 from jsonb_array_elements(public.customers_get('{"view":"at_risk"}') -> 'rows') y where (y ->> 'id')::uuid = (select org from t_hs))
   from jsonb_array_elements(public.customers_get('{}') -> 'rows') x where (x ->> 'id')::uuid = (select org from t_hs)),
  'a low score with a renewal inside the window is at risk');
update app.subscriptions s set current_period_end = now() + interval '200 days' from t_hs h where s.product = h.product and s.tenant_id = h.tenant_id;
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.customers_get('{"view":"at_risk"}') -> 'rows') y
                                 where (y ->> 'id')::uuid = (select org from t_hs) and y ->> 'status' in ('active', 'past_due')), 'a renewal far away is not at risk yet');

-- Inbox and Automation (0029)
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.integrations_get()) x where x ->> 'provider' = 'ai' and x ->> 'status' <> 'connected'), 'the AI provider is listed as not connected');
insert into app.sender_aliases (staff_id, address, kind) values ((select id from app.admins where email = 'tor@orgpuls.no'), 'salg@orgpuls.no', 'send_as');
create temp table t_al as select id from app.sender_aliases where address = 'salg@orgpuls.no' and kind = 'send_as';
update app.mailboxes set status = 'synced', vault_secret_id = gen_random_uuid() where id = (select id from app.mailboxes where owner_id = (select id from app.admins where email = 'tor@orgpuls.no') and deleted_at is null limit 1);
create temp table t_mb as select id from app.mailboxes where status = 'synced' and owner_id = (select id from app.admins where email = 'tor@orgpuls.no') limit 1;
select pg_temp.expect_error(format($$select public.email_send(jsonb_build_object('mailbox_id', %L, 'from_alias_id', %L, 'to', '["kari@lumio.no"]'::jsonb, 'subject', 'x', 'body', 'y'))$$, (select id from t_mb), (select id from t_al)),
                            'invalid', 'an unverified alias cannot be sent from');
update app.sender_aliases set verified_at = now() where id = (select id from t_al);
create temp table t_sent as select public.email_send(jsonb_build_object('mailbox_id', (select id from t_mb), 'from_alias_id', (select id from t_al), 'to', '["kari@lumio.no"]'::jsonb, 'subject', 'Alias', 'body', 'Hei')) r;
select pg_temp.check((select from_addr = 'salg@orgpuls.no' from app.email_messages where id = (select (r ->> 'message_id')::uuid from t_sent)), 'a verified alias becomes the sender');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.call_log_get() -> 'calls') c where not (c ? 'organization')), 'call rows carry their organisation');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.workflows_get('{"kind":"assignment"}')) x where x -> 'options' is null or x -> 'options' = 'null'::jsonb)
                     and exists (select 1 from jsonb_array_elements(public.workflows_get('{"kind":"assignment"}')) x), 'assignment rules come with their options');
insert into app.workflow_runs (workflow_id, version, subject_type, subject_id, state) values ((select id from t_wfs), 1, 'deal', (select id from t_od), 'completed');
select pg_temp.check((select x ->> 'subject_title' from jsonb_array_elements(public.workflow_runs_get(jsonb_build_object('workflow_id', (select id from t_wfs)))) x limit 1)
                     = (select title from app.deals where id = (select id from t_od)), 'a run names its record');
select pg_temp.check((select bool_and((x ->> 'mine')::boolean) from jsonb_array_elements(public.sequence_get((select id from t_seq)) -> 'enrolled') x where (x ->> 'id')::uuid = (select id from t_en)), 'an enrolment says whether it is mine');
insert into app.setting_values (key, value, value_number) values ('safeguards', 'custom', 250) on conflict (key, scope_id) do update set value = 'custom', value_number = 250;
select pg_temp.check((public.workflow_monitor() ->> 'loop_protection_runs')::int = 250, 'the monitor shows the custom safeguard number');
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.entity_columns_get('deal')) c where c ->> 'col' = 'value' and c ->> 'kind' = 'numeric'), 'record columns are readable as data');

rollback;
