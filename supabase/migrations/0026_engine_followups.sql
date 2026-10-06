-- 0026_engine_followups.sql — two gaps found while building the Phase 2 screens.
-- 1. A workflow whose «enroll in sequence» step points at a draft sequence could be switched on, and every run
--    then failed in seq_enroll (sequence_inactive). The step is now a blocker, like a missing connection.
-- 2. deal_detail carries the score's hits and the model behind them, so the deal panel explains its score
--    without a second read.

create or replace function app.wf_blockers(p_wf uuid) returns text[]
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(array_agg(distinct b) filter (where b is not null), '{}') from (
    select case
      when n.v ->> 'kind' = 'slack' and not exists (select 1 from app.integration_connections c where c.provider = 'slack' and c.status = 'connected') then 'not_connected:slack'
      when n.v ->> 'kind' = 'teams' and not exists (select 1 from app.integration_connections c where c.provider = 'teams' and c.status = 'connected') then 'not_connected:teams'
      when n.v ->> 'kind' = 'accounting_invoice' and not exists (select 1 from app.integration_connections c where c.provider = 'accounting' and c.status = 'connected') then 'not_connected:accounting'
      when n.v ->> 'kind' = 'campaign_action' then 'not_available:campaigns'
      when n.v ->> 'kind' = 'project_action' then 'not_available:projects'
      -- a sequence that is still a draft refuses every enrollment (seq_enroll: sequence_inactive)
      when n.v ->> 'kind' = 'enroll_sequence'
           and not exists (select 1 from app.workflows s where s.id::text = n.v -> 'config' ->> 'sequence_id' and s.kind = 'sequence' and s.state = 'active' and s.deleted_at is null) then 'sequence_inactive'
      -- sending as the workflow's owner needs their mailbox; sending as the record's owner is checked per run,
      -- but at least one mailbox must be connected
      when n.v ->> 'kind' in ('send_email', 'email_auto', 'email_manual')
           and not exists (select 1 from app.mailboxes m where m.deleted_at is null and m.status in ('syncing', 'synced')
                           and (coalesce(n.v -> 'config' ->> 'from', '@record_owner') = '@record_owner'
                                or m.owner_id = w.owner_id or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = w.owner_id and mm.can_reply))) then 'mailbox_not_connected'
      end b
    from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
    cross join lateral jsonb_each(v.flat) n(k, v)
    where w.id = p_wf and n.k <> '_start') s
$fn$;

create or replace function public.deal_detail(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.deals;
begin
  select * into d from app.deals where id = p_id;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'deal', p_id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'deal', p_id::text);
  return app.deal_card(d) || jsonb_build_object(
    'custom', d.custom,
    'pipeline', (select name from app.pipelines where id = d.pipeline_id),
    'person_detail', (select jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title, 'email', p.email, 'phone', p.phone) from app.people p where p.id = d.person_id),
    'organization_detail', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'city', o.city, 'employees', o.employees) from app.organizations o where o.id = d.organization_id),
    'stages', (select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'probability', s.probability,
                 'days', (select floor(extract(epoch from sum(coalesce(h.left_at, now()) - h.entered_at)) / 86400)::int from app.deal_stage_history h where h.deal_id = d.id and h.stage_id = s.id))
               order by s.ord) from app.stages s where s.pipeline_id = d.pipeline_id),
    'participants', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title) order by dp.added_at)
                              from app.deal_participants dp join app.people p on p.id = dp.person_id where dp.deal_id = d.id), '[]'::jsonb),
    'followers', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials)) from app.followers f join app.admins a on a.id = f.staff_id
                           where f.entity = 'deal' and f.record_id = d.id), '[]'::jsonb),
    'following', exists (select 1 from app.followers f where f.entity = 'deal' and f.record_id = d.id and f.staff_id = v_me),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by i.ord) from app.deal_items i where i.deal_id = d.id), '[]'::jsonb),
    'revenue', app.deal_revenue(d.id),
    'value_source', d.value_source,
    -- the score's hits, so the panel explains the number (R-DEALS: no second read through rec_get)
    'score_breakdown', d.score_breakdown,
    'score_model', (select jsonb_build_object('id', m.id, 'name', m.name) from app.record_scores r join app.score_models m on m.id = r.model_id
                    where r.entity = 'deal' and r.record_id = d.id));
end $fn$;
