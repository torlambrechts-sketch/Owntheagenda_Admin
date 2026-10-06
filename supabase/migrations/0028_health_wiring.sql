-- 0028_health_wiring.sql — the health score (0025) where the Phase 1 screens wait for it.
-- Customers: «At risk before renewal» means a low score with a renewal inside the renewal window, so the company
-- row carries its next renewal. Tickets: the side panel shows the requester's company score.

-- the renewal window in days (setting renewal_window, 60 by default); analytics_health used the same rule inline
create function app.renewal_days() returns int
  language sql stable security definer set search_path = ''
as $fn$
  select case when app.setting('renewal_window') = 'custom'
              then coalesce((select value_number from app.setting_values where key = 'renewal_window' and scope_id = '')::int, 60) else 60 end
$fn$;
revoke all on function app.renewal_days() from public, anon, authenticated;

-- the company row names its next renewal: the earliest period end of a paying subscription
do $$
declare src text;
begin
  src := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'org_customer'));
  if position($r$'trial_ends_at', (select min(s.trial_ends_at) from subs s where s.st = 'trial'),$r$ in src) = 0 then raise exception 'org_customer changed: trial_ends_at line not found'; end if;
  src := replace(src, $r$'trial_ends_at', (select min(s.trial_ends_at) from subs s where s.st = 'trial'),$r$,
                 $r$'trial_ends_at', (select min(s.trial_ends_at) from subs s where s.st = 'trial'),
    'renews_at', (select min(s.current_period_end) from subs s where s.st in ('active', 'past_due') and s.current_period_end is not null),$r$);
  execute src;
end $$;

create or replace function public.customers_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_rows jsonb; v_views jsonb;
begin
  with base as (
    select app.org_customer(o, q ->> 'product') j from app.organizations o
    where o.deleted_at is null and app.visible(o.owner_id, o.visibility) and (v_sandbox or not o.is_sample)
      and (q ->> 'product' is null or q ->> 'product' = 'all'
           or exists (select 1 from app.account_products ap where ap.account_id = o.account_id and ap.product = q ->> 'product' and ap.status = 'active'))
      and (q ->> 'customers_only' is null or o.account_id is not null)
  ), viewed as (
    select j, jsonb_build_object(
      'trials_week_no_survey', j ->> 'status' = 'trial' and (j ->> 'trial_ends_at')::timestamptz <= now() + interval '7 days' and j ->> 'last_survey_at' is null,
      -- at risk before renewal: a low score and a renewal (or the trial's end) inside the renewal window
      'at_risk', (j ->> 'health')::int < 40 and j ->> 'status' <> 'cancelled'
                 and coalesce((j ->> 'renews_at')::timestamptz, (j ->> 'trial_ends_at')::timestamptz) <= now() + make_interval(days => app.renewal_days()),
      'past_due', j ->> 'status' = 'past_due',
      'multi_product', jsonb_array_length(j -> 'products') > 1,
      'ehf', (j ->> 'ehf')::boolean) v
    from base
  )
  select
    coalesce((select jsonb_agg(j order by j ->> 'name') from viewed
      where (q ->> 'view' is null or q ->> 'view' = 'all' or coalesce((v ->> (q ->> 'view'))::boolean, false))
        and (btrim(coalesce(q ->> 'q', '')) = '' or (j ->> 'name') ilike '%' || btrim(q ->> 'q') || '%' or (j ->> 'org_number') like '%' || regexp_replace(q ->> 'q', '\s', '', 'g') || '%'
             or exists (select 1 from app.members m join app.account_products ap on ap.product = m.product and ap.tenant_id = m.tenant_id
                        where ap.account_id = (j ->> 'account_id')::uuid and m.email ilike '%' || btrim(q ->> 'q') || '%'))
        and (q #>> '{f,status}' is null or j ->> 'status' = q #>> '{f,status}')
        and (q #>> '{f,plan}' is null or j ->> 'plan' = q #>> '{f,plan}')
        and (q #>> '{f,industry}' is null or j ->> 'industry' = q #>> '{f,industry}')
        and (q #>> '{f,fylke}' is null or j ->> 'fylke' = q #>> '{f,fylke}')
        and (q #>> '{f,source}' is null or j ->> 'source' = q #>> '{f,source}')
        and (q #>> '{f,product}' is null or (j -> 'products') @> jsonb_build_array(jsonb_build_object('key', q #>> '{f,product}')))
        and (q #>> '{f,health}' is null or case q #>> '{f,health}' when 'risk' then (j ->> 'health')::int < 40 when 'watch' then (j ->> 'health')::int between 40 and 69
                                                                    when 'healthy' then (j ->> 'health')::int >= 70 else true end)), '[]'::jsonb),
    jsonb_build_object('all', (select count(*) from viewed),
      'trials_week_no_survey', (select count(*) from viewed where (v ->> 'trials_week_no_survey')::boolean),
      'at_risk', (select count(*) from viewed where coalesce((v ->> 'at_risk')::boolean, false)),
      'past_due', (select count(*) from viewed where (v ->> 'past_due')::boolean),
      'multi_product', (select count(*) from viewed where (v ->> 'multi_product')::boolean),
      'ehf', (select count(*) from viewed where (v ->> 'ehf')::boolean))
  into v_rows, v_views;
  perform app.log('record.listed', 'organization', null, jsonb_build_object('count', jsonb_array_length(v_rows), 'view', 'customers'));
  return jsonb_build_object('rows', v_rows, 'views', v_views,
    'facets', jsonb_build_object(
      'plans', coalesce((select jsonb_agg(distinct s.plan) from app.subscriptions s where s.plan is not null), '[]'::jsonb),
      'industries', coalesce((select jsonb_agg(distinct o.industry) from app.organizations o where o.industry is not null and o.deleted_at is null), '[]'::jsonb),
      'fylker', coalesce((select jsonb_agg(distinct o.fylke) from app.organizations o where o.fylke is not null and o.deleted_at is null), '[]'::jsonb),
      'sources', coalesce((select jsonb_agg(distinct o.source) from app.organizations o where o.source is not null and o.deleted_at is null), '[]'::jsonb)));
end $fn$;

create or replace function app.ticket_row(t app.tickets) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select to_jsonb(t) - 'csat_token_hash' - 'custom' || jsonb_build_object(
    'ref', 'T-' || t.number,
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'employees', o.employees, 'account_id', o.account_id,
                                               'health', app.org_health(o.id)) from app.organizations o where o.id = t.organization_id),
    'person', (select jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title, 'email', p.email) from app.people p where p.id = t.person_id),
    'assignee', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = t.assignee_id),
    'problem_ref', (select 'T-' || p.number from app.tickets p where p.id = t.problem_id),
    'incidents', (select count(*) from app.tickets i where i.problem_id = t.id and i.deleted_at is null),
    'responded', t.first_response_at is not null,
    'first_response_left_min', case when t.first_response_at is null then
        case when t.first_response_due_at > now() then app.business_minutes(now(), t.first_response_due_at) else -app.business_minutes(t.first_response_due_at, now()) end end,
    'first_response_used_min', case when t.first_response_at is not null then app.business_minutes(t.created_at, t.first_response_at) end,
    'resolution_left_min', case when t.resolved_at is null then
        case when t.resolution_due_at > now() then app.business_minutes(now(), t.resolution_due_at) else -app.business_minutes(t.resolution_due_at, now()) end end,
    'sla_risk', t.first_response_at is null and t.status not in ('resolved', 'closed') and t.first_response_due_at is not null
                and now() > t.created_at + (t.first_response_due_at - t.created_at) * 0.7)
$fn$;
