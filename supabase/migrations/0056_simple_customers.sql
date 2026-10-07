-- 0056_simple_customers.sql — what Sentral Simple's Customers section reads (design-reference/sentral-simple/SimpleCustomers.dc.html).
--
-- 1. A structured service request on a ticket (app.tickets.request): {kind, args}, filled at intake when the product's
--    support.requested payload carries one ({"request": {"kind": "extend_trial", "args": {"days": 14}}}). The kinds are the
--    ones the product can ask for; only the arguments a command needs are kept (days, plan), never free text. ticket_row
--    returns it with the row (to_jsonb), so tickets_get and ticket_detail carry it.
-- 2. tickets_get: a «requests» view (open service requests) and its count beside open / unassigned / closed.
-- 3. The company row scoped to one application: customers_get with a product now reports that application's status, plan,
--    MRR, trial and renewal (the list «Orgpuls · …» shows Orgpuls' figures, not the sum of the company's applications);
--    «products» still lists every application the company uses. Without a product (or «all») nothing changes.
-- 4. customer_timeline: admin rows carry their outcome (ok), and reads (*.read, *.listed) stay out of the timeline.
-- 5. simple_customers_summary(product): the KPI row (MRR, ARR, paying accounts, trials, trial → paid, open tickets, median
--    first reply) for whoever may open the section (deals:see or tickets:see), without the reports rights.

-- ---------------------------------------------------------------------------
-- 1. the service request
alter table app.tickets add column request jsonb
  check (request is null or (jsonb_typeof(request) = 'object'
                             and request ->> 'kind' in ('extend_trial', 'change_plan', 'suspend', 'reactivate', 'cancel', 'other')
                             and jsonb_typeof(coalesce(request -> 'args', '{}'::jsonb)) = 'object'
                             and char_length(request::text) <= 500));

-- a payload's request, normalised: a known kind and only the arguments its command takes; anything else is null
create function app.ticket_request(p jsonb) returns jsonb
  language sql immutable set search_path = ''
as $fn$
  select case
    when p is null or jsonb_typeof(p) <> 'object'
         or coalesce(p ->> 'kind', '') not in ('extend_trial', 'change_plan', 'suspend', 'reactivate', 'cancel', 'other') then null
    else jsonb_build_object('kind', p ->> 'kind', 'args', case p ->> 'kind'
      when 'extend_trial' then
        case when jsonb_typeof(p #> '{args,days}') = 'number' and (p #>> '{args,days}') ~ '^[0-9]{1,2}$' and (p #>> '{args,days}')::int between 1 and 60
             then jsonb_build_object('days', (p #>> '{args,days}')::int) else '{}'::jsonb end
      when 'change_plan' then
        case when jsonb_typeof(p #> '{args,plan}') = 'string' and char_length(btrim(p #>> '{args,plan}')) between 1 and 40
             then jsonb_build_object('plan', btrim(p #>> '{args,plan}')) else '{}'::jsonb end
      else '{}'::jsonb end)
  end
$fn$;

-- intake (0031 body): a support.requested that carries a request becomes a service request with it
create or replace function app.ticket_intake(p_event bigint) returns uuid
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.events_in; v_id uuid; v_org uuid; v_cat text; v_person uuid; v_lead uuid; v_email text; v_req jsonb;
begin
  select * into e from app.events_in where id = p_event;
  if not found or e.kind not in ('support.requested', 'contact.submitted') then return null; end if;
  if exists (select 1 from app.tickets where source_event_id = p_event) then return null; end if;
  select o.id into v_org from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  where ap.product = e.product and ap.tenant_id = e.tenant_id and o.deleted_at is null limit 1;
  v_cat := coalesce((select key from app.ticket_categories where key = e.payload ->> 'category' and active), case e.kind when 'contact.submitted' then 'sales' else 'getting_started' end);
  v_id := app.ticket_from_capture(v_cat, coalesce(nullif(btrim(e.payload ->> 'subject'), ''), e.kind), e.payload ->> 'email', v_org, e.payload ->> 'message',
                                  case e.kind when 'contact.submitted' then 'contact_form' else 'in_app' end, null, e.product,
                                  jsonb_strip_nulls(jsonb_build_object('role', e.payload ->> 'role', 'page', e.payload ->> 'page', 'browser', e.payload ->> 'browser',
                                                                       'app_version', e.payload ->> 'app_version')),
                                  p_event);
  if e.kind = 'support.requested' then
    v_req := app.ticket_request(e.payload -> 'request');
    if v_req is not null then
      update app.tickets set type = 'service_request', request = v_req where id = v_id;
    end if;
  end if;
  if e.kind = 'contact.submitted' then
    begin
      v_email := lower(nullif(btrim(e.payload ->> 'email'), ''));
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
      v_person := app.capture_person(v_email, case when v_email is not null then e.payload ->> 'name' end, null, v_org, 'Contact form', null);
      if v_person is not null or v_org is not null then
        v_lead := app.capture_lead(coalesce(nullif(btrim(e.payload ->> 'subject'), ''), e.kind), v_person, v_org, 'Contact form', null, null);
        insert into app.ticket_links (ticket_id, kind, ref) values (v_id, 'lead', v_lead::text) on conflict do nothing;
        update app.tickets set person_id = coalesce(person_id, v_person) where id = v_id;
      end if;
    exception when others then
      -- the ticket stands: a lead that cannot be made never loses the request
      insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'lead.skipped', 'ticket', v_id::text, false, jsonb_build_object('event', p_event));
    end;
  end if;
  return v_id;
end $fn$;

-- ---------------------------------------------------------------------------
-- 2. the inbox (0012 body) with the «requests» view and count
create or replace function public.tickets_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('tickets', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_view text := coalesce(q ->> 'view', 'open');
  v_rows jsonb; v_counts jsonb;
begin
  with base as (
    select t.* from app.tickets t
    where t.deleted_at is null and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility) and (v_sandbox or not t.is_sample)
      and (q ->> 'product' is null or q ->> 'product' = 'all' or t.product = q ->> 'product')
      and (q ->> 'organization_id' is null or t.organization_id = (q ->> 'organization_id')::uuid)
  ), r as (select b.*, app.ticket_row(b) j from base b)
  select
    coalesce((select jsonb_agg(r.j order by
                case when coalesce(q ->> 'sort', 'sla') = 'priority' then array_position(array['urgent', 'high', 'normal', 'low'], r.priority) end,
                case when coalesce(q ->> 'sort', 'sla') = 'newest' then extract(epoch from r.created_at) end desc,
                case when coalesce(q ->> 'sort', 'sla') = 'sla' then coalesce(r.first_response_due_at, r.resolution_due_at) end nulls last,
                r.number desc)
              from r where case v_view
                when 'open' then r.status not in ('resolved', 'closed')
                when 'mine' then r.assignee_id = v_me and r.status not in ('resolved', 'closed')
                when 'unassigned' then r.assignee_id is null and r.status not in ('resolved', 'closed')
                when 'requests' then r.type = 'service_request' and r.status not in ('resolved', 'closed')
                when 'sla' then (r.j ->> 'sla_risk')::boolean
                when 'closed' then r.status in ('resolved', 'closed')
                when 'problems' then r.type = 'problem'
                else r.queue_key = v_view and r.status not in ('resolved', 'closed') end
                and (btrim(coalesce(q ->> 'q', '')) = '' or r.subject ilike '%' || btrim(q ->> 'q') || '%' or ('T-' || r.number) ilike '%' || btrim(q ->> 'q') || '%'
                     or (r.j #>> '{organization,name}') ilike '%' || btrim(q ->> 'q') || '%')), '[]'::jsonb),
    jsonb_build_object(
      'open', (select count(*) from r where status not in ('resolved', 'closed')),
      'mine', (select count(*) from r where assignee_id = v_me and status not in ('resolved', 'closed')),
      'unassigned', (select count(*) from r where assignee_id is null and status not in ('resolved', 'closed')),
      'requests', (select count(*) from r where type = 'service_request' and status not in ('resolved', 'closed')),
      'sla', (select count(*) from r where (j ->> 'sla_risk')::boolean),
      'closed', (select count(*) from r where status in ('resolved', 'closed')),
      'queues', (select coalesce(jsonb_object_agg(k.key, (select count(*) from r where r.queue_key = k.key and r.status not in ('resolved', 'closed'))), '{}'::jsonb)
                 from app.ticket_queues k where app.queue_ok(k.key)))
  into v_rows, v_counts;
  perform app.log('record.listed', 'ticket', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'counts', v_counts);
end $fn$;

-- ---------------------------------------------------------------------------
-- 3. the company row (0013, 0025, 0028 body), scoped to one application when one is named
create or replace function app.org_customer(o app.organizations, p_product text default null) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with all_subs as (
    select s.*, ap.created_at ap_created, app.sub_status(s) st, app.sub_mrr(s) mrr, ap.details
    from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
    where ap.account_id = o.account_id and ap.status = 'active'
  ), subs as (
    select * from all_subs where p_product is null or p_product = 'all' or product = p_product
  ), rounds as (
    select r.* from app.product_survey_rounds r join app.account_products ap on ap.product = r.product and ap.tenant_id = r.tenant_id
    where ap.account_id = o.account_id
  )
  select jsonb_build_object(
    'id', o.id, 'name', o.name, 'org_number', o.org_number, 'account_id', o.account_id, 'industry', o.industry, 'fylke', o.fylke, 'city', o.city,
    'source', o.source, 'ehf', o.ehf, 'labels', to_jsonb(o.labels), 'owner_id', o.owner_id, 'csm_id', o.csm_id, 'version', o.version,
    'owner', (select a.name from app.admins a where a.id = o.owner_id),
    'employees', coalesce((select max((s.details ->> 'employees')::int) from subs s where s.details ? 'employees'), o.employees),
    -- every application the company uses, whatever the scope
    'products', coalesce((select jsonb_agg(jsonb_build_object('key', s.product, 'status', s.st) order by s.product) from all_subs s), '[]'::jsonb),
    -- one status per company: the worst state across its products in scope, in this order
    'status', (select s.st from subs s order by array_position(array['suspended', 'past_due', 'active', 'free', 'trial', 'expired', 'cancelled'], s.st) limit 1),
    'plan', (select s.plan from subs s where s.product = coalesce(nullif(p_product, 'all'), 'orgpuls') limit 1),
    'mrr', (select coalesce(sum(s.mrr), 0) from subs s),
    'priced', exists (select 1 from subs s where s.price is not null),
    'trial_ends_at', (select min(s.trial_ends_at) from subs s where s.st = 'trial'),
    'renews_at', (select min(s.current_period_end) from subs s where s.st in ('active', 'past_due') and s.current_period_end is not null),
    'signup_at', (select min(s.ap_created) from subs s),
    'last_survey_at', (select max(coalesce(r.opens_at, r.closes_at)) from rounds r where r.delivered is not null),
    'response', (select round(100.0 * r.answered / nullif(r.delivered, 0)) from rounds r where r.closes_at < now() and r.delivered > 0 order by r.closes_at desc limit 1),
    'health', app.org_health(o.id), 'health_parts', app.org_health_parts(o.id),
    'is_sample', o.is_sample)
$fn$;

-- ---------------------------------------------------------------------------
-- 4. the company's timeline (0013 body): admin rows say whether they worked; reads are not events
create or replace function public.customer_timeline(p_org uuid, p_limit int default 60) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare o app.organizations;
begin
  perform app.require('deals', 'see');
  select * into o from app.organizations where id = p_org;
  if not found or not app.visible(o.owner_id, o.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
      (select jsonb_build_object('at', e.occurred_at, 'kind', case when e.kind like 'billing.%' then 'billing' when e.kind like 'member.%' then 'logins' else 'activation' end,
              'event', e.kind, 'product', e.product) x
       from app.events_in e join app.account_products ap on ap.product = e.product and ap.tenant_id = e.tenant_id where ap.account_id = o.account_id
       order by e.occurred_at desc limit p_limit)
      union all
      (select jsonb_build_object('at', a.at, 'kind', 'admin', 'event', coalesce(a.action, a.command), 'actor', coalesce(s.name, a.actor), 'reason', a.reason, 'ok', a.ok)
       from app.audit a left join app.admins s on s.id = a.staff_id
       where (a.account_id = o.account_id or (a.target_type = 'organization' and a.target_id = o.id::text)) and coalesce(a.action, '') !~ '\.(read|listed)$'
       order by a.at desc limit p_limit)
      union all
      (select jsonb_build_object('at', t.created_at, 'kind', 'support', 'event', 'ticket.created', 'ref', 'T-' || t.number, 'status', t.status)
       from app.tickets t where t.organization_id = o.id and t.deleted_at is null order by t.created_at desc limit p_limit)
    ) s), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- 5. the KPI row. Accounts are the companies using the application that the caller may see (as customers_get lists them);
-- MRR is NOK and null while no subscription in scope carries a price; trial → paid is the share of the trials that started
-- 45–135 days ago and were confirmed within 45 days (v_trial_conversion, as analytics_business reads it over 90 days), null
-- without trials; open tickets follow tickets_get (queues and visibility) and the median first reply follows ticket_reports
-- (30 days, business minutes). The ticket figures are null for a caller without tickets:see.
create function public.simple_customers_summary(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.me();
  v_tickets boolean := app.can('tickets', 'see');
  v_sandbox boolean;
begin
  if v_me is null then raise exception 'not_signed_in' using errcode = 'insufficient_privilege'; end if;
  if not (app.can('deals', 'see') or v_tickets) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:see';
  end if;
  if p_product is null or not exists (select 1 from app.products where key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  v_sandbox := (select sandbox from app.admins where id = v_me);
  return (with s as (
      select o.id org, app.sub_status(x) st, app.sub_mrr(x) mrr, x.price, x.currency
      from app.organizations o
      join app.account_products ap on ap.account_id = o.account_id and ap.status = 'active' and ap.product = p_product
      join app.subscriptions x on x.product = ap.product and x.tenant_id = ap.tenant_id
      where o.deleted_at is null and app.visible(o.owner_id, o.visibility) and (v_sandbox or not o.is_sample)
    ), m as (
      select case when exists (select 1 from s where price is not null) then (select coalesce(sum(mrr), 0) from s where currency = 'NOK') end mrr
    ), c as (
      select sum(trials) trials, sum(converted) converted from app.v_trial_conversion
      where product = p_product and cohort >= date_trunc('month', now() - interval '135 days')
        and cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'
    )
    select jsonb_build_object(
      'mrr', (select mrr from m),
      'arr', (select mrr * 12 from m),
      'paying', (select count(distinct org) from s where st in ('active', 'past_due') and mrr > 0),
      'trials', (select count(distinct org) from s where st = 'trial'),
      'trial_conversion', (select case when coalesce(trials, 0) > 0 then round(100.0 * converted / trials, 1) end from c),
      'open_tickets', case when v_tickets then (select count(*) from app.tickets t
                        where t.deleted_at is null and t.product = p_product and t.status not in ('resolved', 'closed') and (v_sandbox or not t.is_sample)
                          and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility)) end,
      'median_first_response_min', case when v_tickets then (select percentile_cont(0.5) within group (order by app.business_minutes(t.created_at, t.first_response_at))
                        from app.tickets t where t.created_at >= now() - interval '30 days' and t.deleted_at is null and not t.is_sample
                          and t.product = p_product and t.first_response_at is not null) end));
end $fn$;

-- ---------------------------------------------------------------------------
revoke all on function app.ticket_request(jsonb) from public, anon, authenticated;
revoke all on function app.ticket_intake(bigint) from public, anon, authenticated;
revoke all on function app.org_customer(app.organizations, text) from public, anon, authenticated;
revoke all on function public.tickets_get(jsonb) from public, anon;
grant execute on function public.tickets_get(jsonb) to authenticated;
revoke all on function public.customer_timeline(uuid, int) from public, anon;
grant execute on function public.customer_timeline(uuid, int) to authenticated;
revoke all on function public.simple_customers_summary(text) from public, anon;
grant execute on function public.simple_customers_summary(text) to authenticated;
