-- requests_invariants.sql — what the Phase 1 screens asked of the database (0023).
\ir _helpers.psql
begin;

-- a note with an @mention is stored and the mentioned person notified with a link to the record
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_p as select id from app.people where email = 'kari.nordmann@lumio.no';
select public.note_save('person', (select id from t_p), null, 'Se på dette @Tor', null, null, array[(select id from app.admins where email = 'tor@orgpuls.no')]);
select pg_temp.check(exists (select 1 from app.notifications where staff_id = (select id from app.admins where email = 'tor@orgpuls.no') and route like '/contacts?person=%'),
                     'a note with an @mention notifies, linking to the record');

-- reminders: the owner or someone who may edit others' records
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_act as select (public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'call'), 'subject', 'Tors samtale',
  'starts_at', now() + interval '2 days 3 hours')) ->> 'id')::uuid id;
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format($$select public.activity_reminders_set(%L, '[{"channel":"app","offset_min":5}]')$$, (select id from t_act)), 'forbidden',
                            'someone else cannot replace the reminders of an activity they may only see');

-- tickets: no change outside the queues a staff member may see
create temp table t_pv as select id, version from app.tickets where queue_key = 'personvern' and deleted_at is null limit 1;
select pg_temp.expect_error(format($$select public.rec_save('ticket', %L, '{"subject":"Endret"}')$$, (select id from t_pv)), 'forbidden',
                            'a sales user cannot change a personvern ticket');
create temp table t_sup as select id from app.tickets where queue_key = 'support' and deleted_at is null
  and owner_id is distinct from (select id from app.admins where email = 'ingrid@orgpuls.no')
  and assignee_id is distinct from (select id from app.admins where email = 'ingrid@orgpuls.no') limit 1;
select pg_temp.expect_error(format($$select public.ticket_link(%L, 'survey', 'r-1')$$, (select id from t_sup)), 'forbidden',
                            'linking needs the same edit right as replying');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_error(format($$select public.ticket_action_note(%L, 'billing.extend_trial', true)$$, (select id from t_sup)), 'invalid',
                            'a thread line for an action needs the action in the audit');
select public.customer_action_log((select organization_id from app.tickets where id = (select id from t_sup)), 'billing.extend_trial', 'T-test', false);
select public.ticket_action_note((select id from t_sup), 'billing.extend_trial', false);
select pg_temp.check(exists (select 1 from app.ticket_messages where ticket_id = (select id from t_sup) and kind = 'admin_action' and body = 'billing.extend_trial:failed'),
                     'an executed action becomes a thread line with its outcome');
select pg_temp.check((public.ticket_reports(365) ->> 'csat_avg') is null
                     or (select count(*) from app.tickets where csat_at is not null and created_at > now() - interval '365 days' and not is_sample) > 0, 'CSAT averages answered surveys only');

-- scheduling
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.calendar_connection_save('{"provider":"microsoft","mode":"one_way"}');
select pg_temp.check((select provider = 'microsoft' and mode = 'one_way' and status = 'not_connected' from app.calendar_connections
                      where staff_id = (select id from app.admins where email = 'ingrid@orgpuls.no')), 'the calendar choice is stored, still not connected');
select pg_temp.expect_error($$select public.booking_link_save(null, jsonb_build_object('title', 'Forslag', 'kind', 'proposed', 'proposed_times', jsonb_build_array(now() - interval '1 day')))$$,
                            'invalid', 'a proposed time in the past is refused');
create temp table t_bl as select (public.booking_link_save(null, jsonb_build_object('title', 'Forslag', 'kind', 'proposed', 'proposed_times', jsonb_build_array(now() + interval '3 days'))) ->> 'id')::uuid id;
select pg_temp.check((select cardinality(proposed_times) from app.booking_links where id = (select id from t_bl)) = 1, 'proposed times are stored on the link');
create temp table t_mine as select (public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'task'), 'subject', 'Flytt meg',
  'starts_at', date_trunc('hour', now()) + interval '1 day 2 hours')) ->> 'id')::uuid id, date_trunc('hour', now()) + interval '1 day 2 hours' due;
select public.activities_shift(array[(select id from t_mine)], 1);
select pg_temp.check((select starts_at from app.activities where id = (select id from t_mine)) = (select due + interval '1 day' from t_mine), 'shifting keeps the time of day');

-- lists: sort by owner, OR groups, idle days
select pg_temp.check(jsonb_array_length(public.deal_list('{"sort":[{"f":"owner","dir":"asc"}]}') -> 'rows') > 0, 'the deal list sorts by owner');
create temp table t_or as select '[{"or":[[{"f":"status","op":"eq","v":"won"}],[{"f":"status","op":"eq","v":"lost"}]]}]'::jsonb f;
select pg_temp.check((public.deal_list(jsonb_build_object('filters', (select f from t_or))) ->> 'total')::int
                     = (select count(*) from app.deals where status in ('won', 'lost') and deleted_at is null and archived_at is null and not is_sample and app.visible(owner_id, visibility)),
                     'an OR group matches either condition');
select pg_temp.check((public.deal_list('{"filters":[{"f":"idle_days","op":"gte","v":0}]}') ->> 'total')::int >= 1, 'idle days filter deals');

-- a deal back to a lead
create temp table t_dl as select (public.deal_create(jsonb_build_object('title', 'Tilbake til lead', 'value', 1000, 'pipeline_id', (select id from app.pipelines where name = 'New business'),
  'person_id', (select id from t_p))) ->> 'id')::uuid id;
select public.note_save('deal', (select id from t_dl), null, 'Notat på avtalen');
create temp table t_lead as select (public.deal_to_lead((select id from t_dl)) ->> 'lead_id')::uuid id;
select pg_temp.check((select archived_at is not null from app.deals where id = (select id from t_dl))
                 and exists (select 1 from app.notes where entity = 'lead' and record_id = (select id from t_lead) and body = 'Notat på avtalen'), 'converting archives the deal and moves its notes to the lead');
select pg_temp.check((select seq >= 501 from app.leads where id = (select id from t_lead)), 'leads are numbered from 501');

-- settings
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.entities_get()) x where x ->> 'key' = 'deal' and x ->> 'scope' = 'deals'), 'the registry is readable');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_f as select (public.field_save(null, '{"entity":"person","key":"test_key","label":"Test key","type":"text"}') ->> 'id')::uuid id;
update app.fields set archived_at = now() where id = (select id from t_f);
select pg_temp.expect_error($$select public.field_save(null, '{"entity":"person","key":"test_key","label":"Test key","type":"text"}')$$, 'invalid', 'a key taken by an archived field is refused as invalid');

rollback;
