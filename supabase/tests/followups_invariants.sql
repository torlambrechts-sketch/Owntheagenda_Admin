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

rollback;
