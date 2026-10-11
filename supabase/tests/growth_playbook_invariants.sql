-- growth_playbook_invariants.sql — Growth › the playbook (0076): its tables are closed and its helpers nobody's; the reads
-- that carry money or accounts need a reports right, the others Campaigns › See, all of them the second factor; a budget is
-- set and moved by those who may enter spend, and the move is remembered for the month; experiments move through their
-- stages with ICE and a called result; blackout periods come and go; outcomes follow the first or the last touch and are
-- «—» without a source; trial flows are the product-event ones; the flow library lists what writes to people and names an
-- email step's email, never its content; deliverability counts what the engine did.
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

-- ---------------------------------------------------------------------------
-- closed
select pg_temp.check(not exists (
  select 1 from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r'
    and c.relname in ('marketing_budgets', 'growth_experiments', 'growth_blackouts')
    and (not c.relrowsecurity or has_table_privilege('authenticated', c.oid, 'select') or exists (select 1 from pg_policy p where p.polrelid = c.oid))),
  'the playbook''s tables have RLS, no policy and no grant');
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relname in ('marketing_budgets', 'growth_experiments', 'growth_blackouts')) = 3,
                     'all three exist');
select pg_temp.check(not has_function_privilege('authenticated', f::regprocedure, 'execute'), 'nobody signed in calls ' || f)
from unnest(array['app.account_touch(jsonb, text)', 'app.spend_channel(text, text, text)', 'app.growth_arpa(text)', 'app.flow_steps(uuid)', 'app.flow_campaigns(uuid)']) f;
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute') and has_function_privilege('authenticated', f::regprocedure, 'execute'),
                     'only the signed in call ' || f)
from unnest(array['public.growth_outcomes(text, text)', 'public.growth_budget(text)', 'public.marketing_budget_set(text, text, numeric)',
                  'public.marketing_budget_move(text, text, text, numeric)', 'public.growth_experiments_get(text)', 'public.growth_experiment_add(text, text, text, int, int, int)',
                  'public.growth_experiment_move(uuid, text)', 'public.growth_experiment_call(uuid, text, text)', 'public.growth_experiment_archive(uuid)',
                  'public.growth_calendar(text, int)', 'public.growth_blackout_add(text, text, date, date)', 'public.growth_blackout_remove(uuid)',
                  'public.growth_trial(text)', 'public.growth_flows()', 'public.growth_deliverability(text)']) f;

-- ---------------------------------------------------------------------------
-- reads: money and accounts need a reports right; the plan Campaigns › See; all the second factor
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format($$select public.%s('orgpuls')$$, f), 'forbidden', f || ' needs a reports right')
from unnest(array['growth_outcomes', 'growth_budget', 'growth_trial']) f;
select pg_temp.check(public.growth_experiments_get('orgpuls') ? 'items' and public.growth_calendar('orgpuls') ? 'ads'
                     and jsonb_typeof(public.growth_flows()) = 'array' and public.growth_deliverability('orgpuls') ? 'sends', 'Campaigns › See reads the plan, the flows and deliverability');
select pg_temp.as_staff('hanna@orgpuls.no');
select pg_temp.expect_error($$select public.growth_experiments_get('orgpuls')$$, 'forbidden', 'without Campaigns › See the plan is closed');
select pg_temp.as_staff('sara@orgpuls.no', 'aal1');
select pg_temp.expect_error($$select public.growth_outcomes('orgpuls')$$, 'not_signed_in', 'without the second factor nothing is read');

-- ---------------------------------------------------------------------------
-- a campaign of its own, with spend this month on the partner channel
insert into app.ad_campaigns (product, name, channel, utm_source, utm_medium, utm_campaign, state, starts_on, ends_on)
values ('orgpuls', 'QA partner', 'other', 'partner-qa', 'event', 'qa-pb-partner', 'live', (now() at time zone 'Europe/Oslo')::date - 3, (now() at time zone 'Europe/Oslo')::date + 3),
       ('orgpuls', 'QA sample', 'other', 'partner-qa', 'event', 'qa-pb-sample', 'live', (now() at time zone 'Europe/Oslo')::date - 3, null);
update app.ad_campaigns set is_sample = true where utm_campaign = 'qa-pb-sample';
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_b0 as select public.growth_budget('orgpuls') v;
insert into app.marketing_spend (campaign, month, channel, amount, currency)
values ('qa-pb-partner', date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date, null, 1234, 'NOK');
select pg_temp.check(app.spend_channel(null, 'partner-qa', 'event') = 'partner' and app.spend_channel('email', 'partner-qa', 'event') = 'email',
                     'a spend row''s channel: as typed, else where its campaign''s utm sends visits');

-- ---------------------------------------------------------------------------
-- the budget planner
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_b1 as select public.growth_budget('orgpuls') v;
select pg_temp.check((select jsonb_agg(r ->> 'channel') = '["paid_search", "paid_social", "email", "social", "partner", "organic_search"]' from t_b1, jsonb_array_elements(v -> 'rows') r),
                     'six channels, always, in the design''s order');
select pg_temp.check((select (r1 ->> 'spent')::numeric - (r0 ->> 'spent')::numeric = 1234
                      from t_b0, t_b1, jsonb_array_elements(t_b0.v -> 'rows') r0, jsonb_array_elements(t_b1.v -> 'rows') r1
                      where r0 ->> 'channel' = 'partner' and r1 ->> 'channel' = 'partner'), 'this month''s spend lands on its channel');
select pg_temp.check((select (v ->> 'day')::int between 1 and (v ->> 'days')::int and (v ->> 'month')::date = date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date from t_b1),
                     'the month and the day are Oslo''s');
select pg_temp.expect_detail($$select public.growth_budget('all')$$, 'invalid', 'product', 'a budget belongs to one application');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.marketing_budget_set('orgpuls', 'paid_search', 1000)$$, 'forbidden', 'a budget needs Campaigns › Reports on others''');
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_detail($$select public.marketing_budget_set('orgpuls', 'tv', 1000)$$, 'invalid', 'channel', 'a budget is for a known channel');
select pg_temp.expect_detail($$select public.marketing_budget_set('orgpuls', 'paid_search', -1)$$, 'invalid', 'amount', 'and never negative');
select public.marketing_budget_set('orgpuls', 'paid_search', 30000);
select public.marketing_budget_set('orgpuls', 'paid_search', 25000);
select pg_temp.check((select count(*) = 1 and min(amount) = 25000 from app.marketing_budgets where product = 'orgpuls' and channel = 'paid_search'
                        and month = date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date), 'one budget per channel and month: setting it again replaces it');
select pg_temp.expect_detail($$select public.marketing_budget_move('orgpuls', 'paid_search', 'paid_search', 100)$$, 'invalid', 'channel', 'a move goes somewhere else');
select pg_temp.expect_detail($$select public.marketing_budget_move('orgpuls', 'paid_search', 'email', 25001)$$, 'invalid', 'amount', 'and moves no more than there is');
create temp table t_email0 as select coalesce((select amount from app.marketing_budgets where product = 'orgpuls' and channel = 'email'
                                                and month = date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date), 0) n;
select public.marketing_budget_move('orgpuls', 'paid_search', 'email', 7200);
select pg_temp.check((select amount = 17800 from app.marketing_budgets where product = 'orgpuls' and channel = 'paid_search' and month = date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date)
                     and (select amount = (select n from t_email0) + 7200 from app.marketing_budgets where product = 'orgpuls' and channel = 'email'
                            and month = date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date),
                     'the move takes from one and adds to the other');
select pg_temp.check((select v -> 'last_move' @> '{"from": "paid_search", "to": "email", "amount": 7200}' from (select public.growth_budget('orgpuls') v) x),
                     'and the month remembers it, so the suggestion shows as applied');

-- ---------------------------------------------------------------------------
-- experiments
select pg_temp.as_staff('sara@orgpuls.no');
select pg_temp.expect_error($$select public.growth_experiment_add('orgpuls', 'Shorter form', 'signup', 5, 5, 5)$$, 'forbidden', 'adding an experiment needs Campaigns › Add');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.growth_experiment_add('orgpuls', 'ab', 'signup', 5, 5, 5)$$, 'invalid', 'hypothesis', 'a hypothesis has words');
select pg_temp.expect_detail($$select public.growth_experiment_add('orgpuls', 'Shorter form', 'tv', 5, 5, 5)$$, 'invalid', 'area', 'an area from the list');
select pg_temp.expect_detail($$select public.growth_experiment_add('orgpuls', 'Shorter form', 'signup', 11, 5, 5)$$, 'invalid', 'ice', 'ICE scores are 1 to 10');
create temp table t_x as select (public.growth_experiment_add('orgpuls', '  Shorter   form  ', 'signup', 9, 8, 7) ->> 'id')::uuid id;
select pg_temp.check((select hypothesis = 'Shorter form' and stage = 'backlog' and owner_id = (select id from app.admins where email = 'ingrid@orgpuls.no') from app.growth_experiments where id = (select id from t_x)),
                     'added to the backlog, its words tidied, owned by who added it');
select pg_temp.expect_detail(format($$select public.growth_experiment_call(%L, 'win', null)$$, (select id from t_x)), 'invalid', 'not_running', 'only a running test is called');
select pg_temp.expect_detail(format($$select public.growth_experiment_move(%L, 'done')$$, (select id from t_x)), 'invalid', 'stage', 'Done is reached by calling the result');
select public.growth_experiment_move((select id from t_x), 'running');
select pg_temp.check((select started_at is not null from app.growth_experiments where id = (select id from t_x)), 'running, it knows when it started');
select pg_temp.check((select (v ->> 'running')::int >= 1 and v -> 'items' @> jsonb_build_array(jsonb_build_object('id', (select id from t_x), 'stage', 'running', 'impact', 9))
                      from (select public.growth_experiments_get('orgpuls') v) x), 'the board shows it running, with its scores');
select public.growth_experiment_call((select id from t_x), 'win', ' +11 % clicks ');
select pg_temp.check((select stage = 'done' and outcome = 'win' and result_note = '+11 % clicks' and ended_at is not null from app.growth_experiments where id = (select id from t_x)),
                     'called: Done, the outcome and the note');
select pg_temp.expect_error(format($$update app.growth_experiments set outcome = null where id = %L$$, (select id from t_x)),
                            'new row for relation "growth_experiments" violates check constraint "growth_experiments_check"', 'a done experiment always has its outcome');
select public.growth_experiment_move((select id from t_x), 'running');
select pg_temp.check((select stage = 'running' and outcome is null and ended_at is null and started_at is not null from app.growth_experiments where id = (select id from t_x)),
                     'back from Done reopens it, keeping its start');
select pg_temp.expect_error(format($$select public.growth_experiment_archive(%L)$$, (select id from t_x)), 'not_found', 'only a done experiment is archived');
select public.growth_experiment_call((select id from t_x), 'no_effect', null);
select public.growth_experiment_archive((select id from t_x));
select pg_temp.check(not (select public.growth_experiments_get('orgpuls') -> 'items' @> jsonb_build_array(jsonb_build_object('id', (select id from t_x)))),
                     'archived, it leaves the board');

-- ---------------------------------------------------------------------------
-- the calendar
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.growth_blackout_add('orgpuls', 'Påske', '2026-04-06', '2026-03-30')$$, 'invalid', 'dates', 'a period ends after it starts');
select pg_temp.expect_detail($$select public.growth_blackout_add('orgpuls', ' ', '2026-03-30', '2026-04-06')$$, 'invalid', 'name', 'and has a name');
create temp table t_bo as select (public.growth_blackout_add('orgpuls', 'Påske', make_date(extract(year from now() at time zone 'Europe/Oslo')::int, 3, 30),
                                                             make_date(extract(year from now() at time zone 'Europe/Oslo')::int, 4, 6)) ->> 'id')::uuid id;
create temp table t_cal as select public.growth_calendar('orgpuls') v;
select pg_temp.check((select v -> 'blackouts' @> jsonb_build_array(jsonb_build_object('id', (select id from t_bo), 'name', 'Påske')) from t_cal), 'the blackout is on this year''s plan');
select pg_temp.check((select v -> 'ads' @> '[{"name": "QA partner", "state": "live"}]' and not v -> 'ads' @> '[{"name": "QA sample"}]' from t_cal),
                     'the year''s campaigns, without sample ones');
select pg_temp.expect_detail($$select public.growth_calendar('orgpuls', 1999)$$, 'invalid', 'year', 'a year Sentral could hold');
select public.growth_blackout_remove((select id from t_bo));
select pg_temp.expect_error(format($$select public.growth_blackout_remove(%L)$$, (select id from t_bo)), 'not_found', 'removed once');

-- ---------------------------------------------------------------------------
-- outcomes: «—» without a source; then first and last touch on one paying account
update app.account_products set attribution = '{"heard": "venn"}' where product = 'orgpuls';
select pg_temp.as_staff('sara@orgpuls.no');
create temp table t_o0 as select public.growth_outcomes('orgpuls', 'position') v;
select pg_temp.check((select v ->> 'model' = 'first' and not (v ->> 'attributed')::boolean and v -> 'journeys' = 'null'::jsonb
                        and not exists (select 1 from jsonb_array_elements(v -> 'channels') c where c -> 'paying' <> 'null'::jsonb or c -> 'accounts' <> 'null'::jsonb) from t_o0),
                     'an unknown model is first touch; without a source accounts, paying customers and journeys are «—»');
select pg_temp.check((select c -> 'spend' <> 'null'::jsonb from t_o0, jsonb_array_elements(v -> 'channels') c where c ->> 'channel' = 'partner'), 'spend is shown regardless');
create temp table t_pay as
  select sb.product, sb.tenant_id from app.subscriptions sb join app.account_products ap on ap.product = sb.product and ap.tenant_id = sb.tenant_id
  where sb.product = 'orgpuls' and sb.confirmed_at > now() - interval '90 days' order by sb.confirmed_at desc limit 1;
select pg_temp.check((select count(*) = 1 from t_pay), 'the seed has an account that became paying in 90 days');
update app.account_products ap set attribution = '{"first_touch": {"utm_source": "partner-qa"}, "last_touch": {"utm_medium": "email"}}'
from t_pay where ap.product = t_pay.product and ap.tenant_id = t_pay.tenant_id;
create temp table t_of as select public.growth_outcomes('orgpuls', 'first') v;
create temp table t_ol as select public.growth_outcomes('orgpuls', 'last') v;
select pg_temp.check((select (v ->> 'attributed')::boolean and (c ->> 'paying')::int = 1 and (c ->> 'mrr')::numeric >= 0 from t_of, jsonb_array_elements(v -> 'channels') c where c ->> 'channel' = 'partner'),
                     'first touch: the paying account counts on its first channel');
select pg_temp.check((select (c ->> 'paying')::int = 1 from t_ol, jsonb_array_elements(v -> 'channels') c where c ->> 'channel' = 'email')
                     and (select coalesce((c ->> 'paying')::int, 0) = 0 from t_ol, jsonb_array_elements(v -> 'channels') c where c ->> 'channel' = 'partner'),
                     'last touch: on its last');
select pg_temp.check((select v -> 'journeys' @> '[{"first": "partner", "last": "email", "paying": 1}]' from t_of), 'the journey runs from the first touch to the last');
select pg_temp.check(app.account_touch('{"first_touch": {"a": 1}}', 'last') = '{"a": 1}' and app.account_touch('{"utm_source": "x"}', 'first') = '{"utm_source": "x"}',
                     'a missing last touch falls back to the first; an old flat attribution is its own first touch');

-- ---------------------------------------------------------------------------
-- trial, flows and deliverability
create temp table t_tr as select public.growth_trial('orgpuls') v;
select pg_temp.check((select v ? 'trials' and v ? 'first_survey' and v ? 'abandoned' and (v -> 'trials' ->> 'converted')::int <= (v -> 'trials' ->> 'ended')::int from t_tr),
                     'trial conversion, time to first survey and abandoned signups');
select pg_temp.check((select bool_and(f ->> 'trigger' in ('org.created', 'milestone.reached', 'billing.changed')) from t_tr, jsonb_array_elements(v -> 'flows') f)
                     and (select v -> 'flows' @> '[{"trigger": "org.created"}]' from t_tr), 'the trial flows are the ones a product event starts');
create temp table t_fl as select public.growth_flows() v;
select pg_temp.check((select bool_and(f ->> 'kind' in ('workflow', 'sequence', 'lifecycle')) from t_fl, jsonb_array_elements(v) f)
                     and not exists (select 1 from t_fl, jsonb_array_elements(v) f where f ->> 'name' = 'Rotting deal alert'),
                     'the library holds what writes to people, not an internal alert');
select pg_temp.check((select bool_and((select bool_and(k in ('kind', 'email', 'amount', 'unit')) from jsonb_object_keys(s) k))
                      from app.workflows w, jsonb_array_elements(app.flow_steps(w.id)) s where w.deleted_at is null),
                     'a flow''s steps carry kind, the email''s name and a delay, never content');
select pg_temp.check(exists (select 1 from app.workflows w, jsonb_array_elements(app.flow_steps(w.id)) s where s ->> 'kind' = 'email_auto' and s ->> 'email' is not null),
                     'a sequence''s email step names its template');
create temp table t_dl as select public.growth_deliverability('orgpuls') v;
select pg_temp.check((select (v -> 'signals' ->> 'unsubscribed')::int = (select count(*) from app.suppressions where reason = 'unsubscribed'
                        and created_at >= date_trunc('month', now() at time zone 'Europe/Oslo') at time zone 'Europe/Oslo') from t_dl),
                     'the signals count what the engine did this month');
select pg_temp.check((select coalesce((select sum(value::int) from jsonb_each_text(v -> 'suppressions')), 0) = (select count(*) from app.suppressions) from t_dl),
                     'the suppression list by reason');

rollback;
