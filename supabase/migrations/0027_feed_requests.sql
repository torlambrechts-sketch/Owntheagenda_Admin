-- 0027_feed_requests.sql — what the Feed screen asked of the database (docs/crm-enrichment/requests/feed.md).

-- R-FEED-01, R-FEED-02: the deal's owner on each card; a score range filter while scores are shown
create or replace function public.feed_get(p_tab text default 'follow_ups', p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); sc app.feed_scope; v_ai boolean := app.setting('ai_scoring') = 'on'; v_sample boolean;
begin
  if p_tab not in ('follow_ups', 'overlooked', 'suggestions') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tab'; end if;
  select * into sc from app.feed_scope where staff_id = v_me;
  v_sample := (select sandbox from app.admins where id = v_me);
  return jsonb_build_object(
    'counts', (select jsonb_object_agg(k.tab, coalesce(x.n, 0)) from (select distinct tab from app.feed_card_kinds) k
               left join (select fk.tab, count(*) n from app.feed_cards c join app.feed_card_kinds fk on fk.kind = c.kind left join app.deals d on d.id = c.deal_id
                          where c.staff_id = v_me and c.resolved_at is null and c.is_sample = v_sample and (v_ai or fk.tone <> 'ai')
                            and (cardinality(coalesce(sc.pipeline_ids, '{}')) = 0 or d.pipeline_id = any (sc.pipeline_ids) or c.deal_id is null)
                            and (cardinality(coalesce(sc.stage_ids, '{}')) = 0 or d.stage_id = any (sc.stage_ids) or c.deal_id is null)
                          group by fk.tab) x on x.tab = k.tab),
    'scope', jsonb_build_object('pipeline_ids', to_jsonb(coalesce(sc.pipeline_ids, '{}')), 'stage_ids', to_jsonb(coalesce(sc.stage_ids, '{}'))),
    'ai_scoring', v_ai,
    'cards', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'kind', c.kind, 'tone', fk.tone, 'params', case when v_ai then c.params else c.params - 'readiness' end, 'created_at', c.created_at,
        'deal', case when d.id is not null then jsonb_build_object('id', d.id, 'title', d.title, 'value', d.value, 'currency', d.currency, 'stage_id', d.stage_id,
                                                                   'stage', (select s.name from app.stages s where s.id = d.stage_id), 'score', case when v_ai then d.score end,
                                                                   'person', (select p.name from app.people p where p.id = d.person_id),
                                                                   'person_id', d.person_id, 'owner_id', d.owner_id,
                                                                   'owner', (select a.name from app.admins a where a.id = d.owner_id)) end,
        'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'city', o.city) from app.organizations o where o.id = coalesce(c.organization_id, d.organization_id)))
        order by fk.ord, c.created_at desc)
      from app.feed_cards c join app.feed_card_kinds fk on fk.kind = c.kind left join app.deals d on d.id = c.deal_id
      where c.staff_id = v_me and c.resolved_at is null and fk.tab = p_tab and c.is_sample = v_sample and (v_ai or fk.tone <> 'ai')
        and (cardinality(coalesce(sc.pipeline_ids, '{}')) = 0 or d.pipeline_id = any (sc.pipeline_ids) or c.deal_id is null)
        and (cardinality(coalesce(sc.stage_ids, '{}')) = 0 or d.stage_id = any (sc.stage_ids) or c.deal_id is null)
        and (jsonb_typeof(p_filter -> 'stage_ids') is distinct from 'array' or d.stage_id in (select (x #>> '{}')::uuid from jsonb_array_elements(p_filter -> 'stage_ids') x))
        and (jsonb_typeof(p_filter -> 'kinds') is distinct from 'array' or c.kind in (select jsonb_array_elements_text(p_filter -> 'kinds')))
        -- a score range applies only while scores are shown; a card without a deal has no score
        and (not v_ai or p_filter ->> 'score_min' is null or d.score >= (p_filter ->> 'score_min')::int)
        and (not v_ai or p_filter ->> 'score_max' is null or d.score <= (p_filter ->> 'score_max')::int)), '[]'::jsonb));
end $fn$;

-- R-FEED-03, R-FEED-06: the lookup's subject and time; candidates in the staff member's own world, their ids, and the month in their time zone
create or replace function public.enrichment_get(p_org uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_tz text := (select time_zone from app.admins where id = v_me);
  -- the month starts where the staff member lives, as in feed_progress
  v_mon0 timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_sample boolean := (select sandbox from app.admins where id = v_me);
begin
  return jsonb_build_object(
    -- the organizations with gaps the staff member may see, in their own world (sandbox or not); the first 100 ids are what a bulk request sends
    'candidates', (select count(*) from app.organizations o where o.deleted_at is null and o.org_number is not null and o.is_sample = v_sample and app.visible(o.owner_id, o.visibility)
                     and (o.address is null or o.postal_code is null or o.city is null or o.nace is null or o.industry is null or o.employees is null or o.website is null)),
    'candidate_ids', coalesce((select jsonb_agg(x.id) from (select o.id from app.organizations o where o.deleted_at is null and o.org_number is not null and o.is_sample = v_sample
                     and app.visible(o.owner_id, o.visibility)
                     and (o.address is null or o.postal_code is null or o.city is null or o.nace is null or o.industry is null or o.employees is null or o.website is null)
                     order by o.name limit 100) x), '[]'::jsonb),
    'contact_data', (select status from app.integration_connections where provider = 'contact_data'),
    'credits', jsonb_build_object('used_month', (select coalesce(-sum(delta), 0) from app.credit_ledger where at >= v_mon0 and delta < 0), 'limit', app.count_limit()),
    'requests', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'organization_id', r.record_id, 'organization', o.name, 'state', r.state, 'error', r.error, 'created_at', r.created_at,
        'fields', (select coalesce(jsonb_agg(jsonb_build_object('field', f, 'current', to_jsonb(o) -> f, 'proposed', r.proposed -> f,
                                                                'writable', (to_jsonb(o) -> f) is null or (to_jsonb(o) ->> f) = '') order by array_position(app.enrich_fields(), f)), '[]'::jsonb)
                   from unnest(app.enrich_fields()) f where r.proposed ? f and (r.proposed -> f) is distinct from (to_jsonb(o) -> f)))
        order by r.created_at desc)
      from app.enrichment_requests r join app.organizations o on o.id = r.record_id
      where r.entity = 'organization' and r.state in ('requested', 'ready', 'failed') and app.visible(o.owner_id, o.visibility)
        and (p_org is null or r.record_id = p_org) and r.created_at > now() - interval '30 days'), '[]'::jsonb),
    'lookups', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'thread_id', s.thread_id, 'from', s.from_addr, 'name', s.from_name, 'domain', s.domain,
                                                             'proposed', s.proposed, 'at', s.created_at,
                                                             'subject', (select t.subject from app.email_threads t where t.id = s.thread_id),
                                                             'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o
                                                                              where o.deleted_at is null and lower(o.website) like '%' || s.domain || '%' limit 1))
                                          order by s.created_at desc)
                         from app.lookup_suggestions s where s.state = 'open' and (s.thread_id is null or app.thread_visible(s.thread_id))), '[]'::jsonb));
end $fn$;

-- R-FEED-04: a clicked link in a sequence names the sequence and step
create or replace function app.sub_feed(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare l jsonb; d app.deals; v_subject text; v_from text; m app.email_messages; p record;
begin
  if ev.kind in ('email.received', 'email.opened', 'email.clicked', 'email.sent') then
    select * into m from app.email_messages where id = (ev.payload ->> 'message')::uuid;
    for l in select * from jsonb_array_elements(coalesce(ev.payload -> 'links', '[]'::jsonb)) where value ->> 'entity' = 'deal' loop
      select * into d from app.deals where id = (l ->> 'id')::uuid and deleted_at is null and status = 'open';
      continue when not found;
      if ev.kind = 'email.received' then
        perform app.feed_card('email_reply', d.owner_id, d.id, d.organization_id, 'email_thread', ev.subject_id,
                              jsonb_build_object('thread', ev.subject_id, 'from', coalesce(m.from_name, m.from_addr), 'subject', m.subject,
                                                 'readiness', (select i.readiness from app.email_thread_insights i where i.thread_id = ev.subject_id and i.state = 'ready')),
                              'email_reply:' || ev.subject_id || ':' || m.id, ev.is_sample);
        update app.feed_cards set resolved_at = now(), resolved_by = 'cleared' where deal_id = d.id and kind = 'no_reply' and resolved_at is null;
      elsif ev.kind = 'email.opened' then
        perform app.feed_card('email_opened', d.owner_id, d.id, d.organization_id, 'email_thread', ev.subject_id,
                              jsonb_build_object('thread', ev.subject_id, 'subject', m.subject, 'last_at', now(),
                                                 'count', (select count(*) from app.email_tracking_events te where te.message_id = m.id and te.kind = 'open' and te.client_class <> 'prefetch')),
                              'opened:' || m.id, ev.is_sample);
      elsif ev.kind = 'email.clicked' then
        perform app.feed_card('link_clicked', d.owner_id, d.id, d.organization_id, 'email_thread', ev.subject_id,
                              jsonb_build_object('thread', ev.subject_id, 'subject', m.subject, 'label', ev.payload ->> 'label', 'enrollment', ev.payload ->> 'enrollment')
                              -- the sequence and the step the link was sent from, as they were when it was clicked
                              || coalesce((select jsonb_build_object('sequence', w.name, 'step', se.current_ord) from app.sequence_enrollments se join app.workflows w on w.id = se.workflow_id
                                           where se.id::text = ev.payload ->> 'enrollment'), '{}'::jsonb),
                              'clicked:' || m.id || ':' || md5(coalesce(ev.payload ->> 'label', '')), ev.is_sample);
      elsif ev.kind = 'email.sent' then
        update app.feed_cards set resolved_at = now(), resolved_by = 'email'
        where deal_id = d.id and kind = 'email_reply' and source_id = ev.subject_id and resolved_at is null;
      end if;
    end loop;
    -- reverse lookup: an inbound sender nobody knows, from a domain that is not a free-mail domain
    if ev.kind = 'email.received' and m.id is not null and not exists (select 1 from app.people pe where lower(pe.email) = lower(m.from_addr) and pe.deleted_at is null)
       and split_part(lower(m.from_addr), '@', 2) not in ('gmail.com', 'hotmail.com', 'outlook.com', 'live.com', 'yahoo.com', 'icloud.com', 'me.com', 'online.no', 'live.no', 'hotmail.no', 'msn.com', 'proton.me', 'protonmail.com') then
      insert into app.lookup_suggestions (thread_id, from_addr, from_name, domain, is_sample)
      values (ev.subject_id, lower(m.from_addr), m.from_name, split_part(lower(m.from_addr), '@', 2), ev.is_sample)
      on conflict (from_addr) do nothing;
    end if;
  elsif ev.kind in ('deal.won', 'deal.lost', 'deal.deleted') then
    update app.feed_cards set resolved_at = now(), resolved_by = 'cleared' where deal_id = ev.subject_id and resolved_at is null;
  elsif ev.kind = 'deal.stage_changed' then
    update app.feed_cards set resolved_at = now(), resolved_by = 'cleared' where deal_id = ev.subject_id and kind in ('stalled', 'likely_to_advance') and resolved_at is null;
  elsif ev.kind = 'activity.completed' then
    update app.feed_cards set resolved_at = now(), resolved_by = 'done' where source_type = 'activity' and source_id = ev.subject_id and resolved_at is null;
  end if;
end $fn$;

-- R-FEED-05: a scoring model made by mistake can be removed. An active model is the one scoring its pipeline,
-- so it is set to draft first; its scores are cleared with it.
create function public.score_model_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'configure'); m app.score_models;
begin
  select * into m from app.score_models where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if m.state = 'active' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  update app.score_models set deleted_at = now(), updated_at = now() where id = p_id;
  delete from app.record_scores where model_id = p_id;
  perform app.log('score_model.deleted', 'score_model', p_id::text, jsonb_build_object('name', m.name));
  return jsonb_build_object('id', p_id, 'deleted', true);
end $fn$;
revoke all on function public.score_model_delete(uuid) from public, anon;
grant execute on function public.score_model_delete(uuid) to authenticated;
