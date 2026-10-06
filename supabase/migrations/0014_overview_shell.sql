-- 0014_overview_shell.sql — the overview and the shell read tickets and deals now that they exist: open
-- tickets and SLA risk, the weighted pipeline, «Needs you today» from real sources, and the nav badges
-- (tickets waiting for a first response, open leads).

create or replace function public.overview(p_product text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('global', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  v_prods text[];
  v_month date := date_trunc('month', now())::date;
  r jsonb;
begin
  v_prods := case when p_product is null or p_product = 'all' then array(select key from app.products) else array[p_product] end;

  with subs as (
    select s.*, ap.account_id, app.sub_status(s) st, app.sub_mrr(s) mrr
    from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
    where s.product = any (v_prods) and ap.status = 'active'
  ), acct as (
    select a.id, bool_or(s.mrr > 0) paying, bool_or(s.st = 'trial') trial, min(s.trial_ends_at) filter (where s.st = 'trial') trial_ends
    from app.accounts a join subs s on s.account_id = a.id group by a.id
  )
  select jsonb_build_object(
    'mrr', jsonb_build_object(
      'now', (select coalesce(sum(mrr), 0) from subs),
      'priced', (select count(*) from subs where price is not null),
      'prev', (select sum(m.mrr) from app.mrr_daily m where m.product = any (v_prods)
               and m.day = (select max(day) from app.mrr_daily where day <= current_date - 30))),
    'paying', jsonb_build_object(
      'now', (select count(*) from acct where paying),
      'subs_now', (select count(*) from subs where mrr > 0),
      'prev', (select sum(m.paying) from app.mrr_daily m where m.product = any (v_prods)
               and m.day = (select max(day) from app.mrr_daily where day <= current_date - 30))),
    'trials', jsonb_build_object(
      'now', (select count(*) from acct where trial),
      'ending7', (select count(*) from acct where trial and trial_ends <= now() + interval '7 days'),
      'ended_month', (select count(*) from subs where trial_ends_at >= v_month and trial_ends_at < now()),
      'converted_month', (select count(*) from subs where trial_ends_at >= v_month and trial_ends_at < now() and confirmed_at is not null)),
    'apps', (select coalesce(jsonb_agg(jsonb_build_object(
               'key', p.key, 'name', p.name, 'color', p.color, 'ink', p.ink,
               'host', substring(i.api_url from '^https://([^/]+)'), 'enabled', coalesce(i.enabled, false), 'installed', i.product is not null,
               'orgs', (select count(distinct s.account_id) from subs s where s.product = p.key),
               'mrr', (select sum(s.mrr) from subs s where s.product = p.key and s.price is not null),
               'last_event_at', (select max(received_at) from app.events_in e where e.product = p.key)) order by p.ord, p.key), '[]'::jsonb)
             from app.products p left join app.installations i on i.product = p.key where p.key = any (v_prods)),
    'mrr_series', (select coalesce(jsonb_agg(jsonb_build_object('month', to_char(x.m, 'YYYY-MM'), 'by_product', x.by) order by x.m), '[]'::jsonb)
                   from (select date_trunc('month', d.day)::date m,
                                jsonb_object_agg(d.product, d.mrr) by
                         from app.mrr_daily d
                         where d.product = any (v_prods)
                           and d.day = (select max(d2.day) from app.mrr_daily d2 where date_trunc('month', d2.day) = date_trunc('month', d.day))
                           and d.day > (v_month - interval '11 months')
                         group by 1) x),
    'trials_list', (select coalesce(jsonb_agg(t order by t ->> 'ends'), '[]'::jsonb) from (
                      select jsonb_build_object('account_id', a.id, 'organization_id', o.id, 'name', coalesce(o.name, ac.name),
                                                'org_number', ac.org_number, 'employees', o.employees, 'ends', a.trial_ends,
                                                'source', o.source, 'owner', (select s.name from app.admins s where s.id = o.owner_id)) t
                      from acct a join app.accounts ac on ac.id = a.id
                      left join app.organizations o on o.account_id = a.id and o.deleted_at is null and (v_sandbox or not o.is_sample)
                      where a.trial order by a.trial_ends limit 6) z),
    'tickets', case when app.can('tickets', 'see') then (select jsonb_build_object(
        'open', count(*) filter (where t.status not in ('resolved', 'closed')),
        'at_risk', count(*) filter (where t.first_response_at is null and t.status not in ('resolved', 'closed') and now() > t.created_at + (t.first_response_due_at - t.created_at) * 0.7),
        'median_first_response_min', (select percentile_cont(0.5) within group (order by app.business_minutes(x.created_at, x.first_response_at))
                                      from app.tickets x where x.first_response_at is not null and x.created_at > now() - interval '30 days' and x.deleted_at is null and (v_sandbox or not x.is_sample)))
      from app.tickets t where t.deleted_at is null and app.queue_ok(t.queue_key) and (v_sandbox or not t.is_sample)
        and (p_product is null or p_product = 'all' or t.product = p_product)) end,
    'pipeline', case when app.can('deals', 'see') and app.module_on('deals') then (
      with pl as (select id from app.pipelines where archived_at is null and app.pipeline_visible(id) and (v_sandbox or not is_sample) order by ord limit 1),
           d as (select d.*, s.probability, s.rot_days, s.name stage_name, s.ord stage_ord from app.deals d join app.stages s on s.id = d.stage_id
                 where d.status = 'open' and d.deleted_at is null and d.archived_at is null and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample))
      select jsonb_build_object(
        'weighted', coalesce((select sum(value * probability / 100.0) from d), 0),
        'open', (select count(*) from d),
        'rotting', (select count(*) from d where rot_days is not null and now() - coalesce(last_activity_at, stage_entered_at) > make_interval(days => rot_days)),
        'stages', coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'n', (select count(*) from d where d.stage_id = s.id),
                                     'value', coalesce((select sum(value) from d where d.stage_id = s.id), 0)) order by s.ord)
                            from app.stages s where s.pipeline_id = (select id from pl)), '[]'::jsonb))) end,
    'at_risk', null,
    'todo', '[]'::jsonb
  ) into r;
  -- what needs the caller today, from sources that exist
  r := jsonb_set(r, '{todo}', coalesce((select jsonb_agg(x) from (
      (select jsonb_build_object('tone', 'alert', 'key', 'ticket_urgent', 'params', jsonb_build_object('id', 'T-' || t.number, 'subject', t.subject,
              'org', coalesce(o.name, ''), 'minutes', greatest(app.business_minutes(now(), t.first_response_due_at), 0)), 'href', '/tickets?ticket=' || t.id) x
       from app.tickets t left join app.organizations o on o.id = t.organization_id
       where app.can('tickets', 'see') and app.queue_ok(t.queue_key) and t.priority = 'urgent' and t.first_response_at is null and t.status not in ('resolved', 'closed')
         and t.deleted_at is null and (v_sandbox or not t.is_sample) order by t.first_response_due_at limit 1)
      union all
      (select jsonb_build_object('tone', 'alert', 'key', 'deals_rotting', 'params', jsonb_build_object('count', count(*) over (), 'title', d.title), 'href', '/deals') x
       from app.deals d join app.stages s on s.id = d.stage_id
       where app.can('deals', 'see') and app.module_on('deals') and d.status = 'open' and d.deleted_at is null and d.archived_at is null and s.rot_days is not null
         and now() - coalesce(d.last_activity_at, d.stage_entered_at) > make_interval(days => s.rot_days) and app.visible(d.owner_id, d.visibility) and (v_sandbox or not d.is_sample)
       order by coalesce(d.last_activity_at, d.stage_entered_at) limit 1)
      union all
      (select jsonb_build_object('tone', 'warn', 'key', 'privacy_due', 'params', jsonb_build_object('days', greatest(ceil(extract(epoch from p.due_at - now()) / 86400), 0)::int,
              'kind', p.kind, 'org', coalesce(o.name, '')), 'href', '/customers?tab=privacy') x
       from app.privacy_requests p left join app.organizations o on o.id = p.organization_id
       where app.can('tickets', 'see') and app.queue_ok('personvern') and p.status in ('received', 'in_progress') and p.due_at < now() + interval '7 days'
         and (v_sandbox or not p.is_sample) order by p.due_at limit 1)
    ) s), '[]'::jsonb));
  perform app.log('overview.read', null, null, jsonb_build_object('product', coalesce(p_product, 'all')));
  return r;
end $fn$;


create or replace function public.shell() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); r jsonb; v_sandbox boolean;
begin
  update app.admins set last_seen_at = now() where id = v_me and (last_seen_at is null or last_seen_at < now() - interval '1 minute');
  v_sandbox := (select sandbox from app.admins where id = v_me);
  select jsonb_build_object('id', a.id, 'email', a.email, 'name', coalesce(a.name, a.email), 'initials', a.initials, 'title', a.title,
           'locale', a.locale, 'time_zone', a.time_zone, 'number_format', a.number_format, 'sandbox', a.sandbox,
           'permission_set', ps.name, 'permission_kind', ps.kind, 'rights', to_jsonb(ps.rights), 'owner', a.role = 'owner')
    into r
  from app.admins a join app.permission_sets ps on ps.id = a.permission_set_id where a.id = v_me;
  return jsonb_build_object(
    'me', r,
    'products', coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name, 'description', p.description, 'color', p.color, 'ink', p.ink,
                                                              'installed', i.product is not null, 'enabled', coalesce(i.enabled, false)) order by p.ord, p.key)
                          from app.products p left join app.installations i on i.product = p.key), '[]'::jsonb),
    'modules', (select coalesce(jsonb_object_agg(m.key, m.enabled), '{}'::jsonb) from app.modules m),
    'settings', jsonb_build_object('session_idle', app.setting('session_idle'), 'ip_allowlist', app.setting('ip_allowlist')),
    'unread', (select count(*) from app.notifications where staff_id = v_me and read_at is null),
    'badges', jsonb_strip_nulls(jsonb_build_object(
      'tickets', case when app.can('tickets', 'see') then nullif((select count(*) from app.tickets t where t.deleted_at is null and t.first_response_at is null
                    and t.status not in ('resolved', 'closed') and app.queue_ok(t.queue_key) and (v_sandbox or not t.is_sample)), 0) end)));
end $fn$;
