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

rollback;
