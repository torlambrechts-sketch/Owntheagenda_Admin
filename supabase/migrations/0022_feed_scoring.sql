-- 0022_feed_scoring.sql — the Feed (follow-ups, overlooked deals, suggestions), scoring models, enrichment
-- from Brønnøysundregistrene, sender lookups, and the manual call log (PRO-01..07, AIA-02, COM-10).
--
-- Feed cards are never prose: a card is a kind and its parameters, generated from events (the «feed»
-- subscriber) and from an hourly check of conditions that time alone makes true (an activity becomes
-- overdue, a close date slips). A card resolves when the user acts or when its condition clears.
--
-- Scores are computed, never typed: an active model per pipeline (or per lead) adds its groups' points for
-- every criterion that holds, from a base that defaults to 0, kept within 0..100. They are recomputed when
-- a record they read changes (the «scores» subscriber) and nightly.
--
-- Enrichment writes empty fields only, with source «enrichment» in the history. Brønnøysund needs no key;
-- the edge worker fetches it. A contact-data provider is not chosen (D-07), so person enrichment, revenue
-- and LinkedIn show «not connected». Credits count provider usage only (D-17); nothing is sold.
--
-- Messaging channels (WhatsApp) and telephony providers are not chosen; their tables come with them. A call
-- can still be placed through the device's own calling app and logged by hand (call_log_save).

alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging'));
insert into app.integration_connections (provider) values ('contact_data'), ('telephony'), ('messaging');

-- the history names enrichment as a source of its own
alter table app.changelog drop constraint changelog_source_check;
alter table app.changelog add constraint changelog_source_check
  check (source in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'merge', 'enrichment'));

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('ai_scoring', 'ai', array['on', 'off'], 'on', 'platform', 'AIA-02', false, null, 400);

-- ---------------------------------------------------------------------------
-- more tests a condition can make (workflows and scoring alike)
--   {f: 'participant_label', v: label id}     a participant on the deal carries this person label
--   {f: 'org_products', op: gte|eq|lte, v: n}  the organisation's number of installed applications
--   {f: 'org_payment', v: 'past_due'|…}        a subscription of the organisation is in this payment state
--   {f: 'email.no_reply', v: days}            the last outbound email on a linked thread has had no answer for v days
create or replace function app.wf_match(p_entity text, p_id uuid, p_groups jsonb) returns boolean
  language plpgsql stable security definer set search_path = ''
as $fn$
declare g jsonb; fl jsonb; ok boolean; e app.entities; re app.entities; v_rel uuid; v_hit boolean; v_org uuid; n int;
begin
  if p_groups is null or jsonb_typeof(p_groups) <> 'array' or jsonb_array_length(p_groups) = 0 then return true; end if;
  select * into e from app.entities where key = p_entity;
  v_org := case p_entity when 'organization' then p_id
             when 'deal' then (select organization_id from app.deals where id = p_id)
             when 'lead' then (select organization_id from app.leads where id = p_id)
             when 'person' then (select organization_id from app.people where id = p_id) end;
  for g in select * from jsonb_array_elements(p_groups) loop
    ok := true;
    for fl in select * from jsonb_array_elements(case when jsonb_typeof(g) = 'array' then g else jsonb_build_array(g) end) loop
      if fl ->> 'f' = 'email.opened' then
        v_hit := exists (select 1 from app.email_links l join app.email_messages m on m.thread_id = l.thread_id join app.email_tracking_events te on te.message_id = m.id
                         where l.entity = p_entity and l.record_id = p_id and te.kind = 'open' and te.client_class <> 'prefetch'
                           and te.at >= now() - make_interval(days => coalesce((fl ->> 'v')::int, 7)));
      elsif fl ->> 'f' = 'email.replied' then
        v_hit := exists (select 1 from app.email_links l join app.email_messages m on m.thread_id = l.thread_id
                         where l.entity = p_entity and l.record_id = p_id and m.direction = 'in' and m.received_at >= now() - make_interval(days => coalesce((fl ->> 'v')::int, 7)));
      elsif fl ->> 'f' = 'email.no_reply' then
        v_hit := exists (select 1 from app.email_links l join app.email_threads t on t.id = l.thread_id
                         where l.entity = p_entity and l.record_id = p_id and t.last_direction = 'out' and t.deleted_at is null
                           and t.last_message_at <= now() - make_interval(days => coalesce((fl ->> 'v')::int, 5)));
      elsif fl ->> 'f' = 'participant_label' then
        v_hit := p_entity = 'deal' and exists (select 1 from app.deal_participants dp join app.people pe on pe.id = dp.person_id
                                               where dp.deal_id = p_id and (fl ->> 'v')::uuid = any (pe.labels));
      elsif fl ->> 'f' = 'org_products' then
        n := (select count(*) from app.organizations o join app.account_products ap on ap.account_id = o.account_id where o.id = v_org);
        v_hit := case coalesce(fl ->> 'op', 'gte') when 'eq' then n = (fl ->> 'v')::int when 'lte' then n <= (fl ->> 'v')::int
                                                   when 'gt' then n > (fl ->> 'v')::int when 'lt' then n < (fl ->> 'v')::int else n >= (fl ->> 'v')::int end;
      elsif fl ->> 'f' = 'org_payment' then
        v_hit := exists (select 1 from app.organizations o join app.account_products ap on ap.account_id = o.account_id
                         join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                         where o.id = v_org and s.payment_state = fl ->> 'v');
      elsif fl ? 'rel' then
        if not exists (select 1 from app.entity_columns c where c.entity = p_entity and c.col = fl ->> 'rel' and c.ref is not null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.rel';
        end if;
        select * into re from app.entities where key = (select c.ref from app.entity_columns c where c.entity = p_entity and c.col = fl ->> 'rel');
        execute format('select t.%I from app.%I t where t.id = %L', fl ->> 'rel', e.tbl, p_id) into v_rel;
        if v_rel is null then v_hit := false;
        else
          execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null %s)', re.tbl, v_rel, app.filter_sql(re, jsonb_build_array(fl - 'rel'))) into v_hit;
        end if;
      else
        execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null %s)', e.tbl, p_id, app.filter_sql(e, jsonb_build_array(fl))) into v_hit;
      end if;
      if coalesce(fl ->> 'op', '') = 'neq' and fl ->> 'f' in ('email.opened', 'email.replied', 'email.no_reply', 'participant_label', 'org_payment') then v_hit := not v_hit; end if;
      if not v_hit then ok := false; exit; end if;
    end loop;
    if ok then return true; end if;
  end loop;
  return false;
end $fn$;

-- ---------------------------------------------------------------------------
-- feed
create table app.feed_card_kinds (
  kind text primary key check (kind ~ '^[a-z_]{2,40}$'),
  tab  text not null check (tab in ('follow_ups', 'overlooked', 'suggestions')),
  tone text not null check (tone in ('info', 'warn', 'good', 'ai')),
  ord  int not null default 0
);
insert into app.feed_card_kinds (kind, tab, tone, ord) values
  ('email_reply', 'follow_ups', 'info', 10), ('no_reply', 'follow_ups', 'warn', 20), ('planned_today', 'follow_ups', 'info', 30),
  ('email_opened', 'follow_ups', 'good', 40), ('link_clicked', 'follow_ups', 'good', 50), ('sequence_review', 'follow_ups', 'info', 60),
  ('overdue_activity', 'overlooked', 'warn', 110), ('no_followup', 'overlooked', 'warn', 120), ('slipping', 'overlooked', 'warn', 130), ('stalled', 'overlooked', 'warn', 140),
  ('new_no_activity', 'suggestions', 'info', 210), ('cross_sell', 'suggestions', 'good', 220), ('likely_to_advance', 'suggestions', 'ai', 230);

create table app.feed_cards (
  id              uuid primary key default gen_random_uuid(),
  staff_id        uuid not null references app.admins (id) on delete cascade,
  kind            text not null references app.feed_card_kinds (kind),
  deal_id         uuid references app.deals (id) on delete cascade,
  organization_id uuid references app.organizations (id) on delete cascade,
  source_type     text check (source_type is null or source_type ~ '^[a-z_]{2,40}$'),
  source_id       uuid,
  params          jsonb not null default '{}'::jsonb check (jsonb_typeof(params) = 'object'),
  dedupe_key      text not null unique check (char_length(dedupe_key) <= 200),
  is_sample       boolean not null default false,
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     text check (resolved_by is null or resolved_by in ('task', 'email', 'done', 'dismissed', 'cleared')),
  check ((resolved_at is null) = (resolved_by is null))
);
create index feed_cards_open on app.feed_cards (staff_id, created_at desc) where resolved_at is null;
create index feed_cards_deal on app.feed_cards (deal_id) where resolved_at is null;

create table app.feed_scope (
  staff_id     uuid primary key references app.admins (id) on delete cascade,
  pipeline_ids uuid[] not null default '{}',
  stage_ids    uuid[] not null default '{}',
  updated_at   timestamptz not null default now()
);

-- a card, once per dedupe key; the owner of the deal (or organisation) receives it
create function app.feed_card(p_kind text, p_staff uuid, p_deal uuid, p_org uuid, p_source_type text, p_source uuid, p_params jsonb, p_key text, p_sample boolean)
  returns void language sql volatile security definer set search_path = ''
as $fn$
  insert into app.feed_cards (staff_id, kind, deal_id, organization_id, source_type, source_id, params, dedupe_key, is_sample)
  select p_staff, p_kind, p_deal, p_org, p_source_type, p_source, coalesce(p_params, '{}'::jsonb), p_key, coalesce(p_sample, false)
  where p_staff is not null
  on conflict (dedupe_key) do update set params = excluded.params where app.feed_cards.resolved_at is null;
$fn$;

-- the feed subscriber: mail on a deal makes cards; a reply, a won or lost deal or a done activity resolves them.
-- Unmatched inbound senders become lookup suggestions (Enrichment › reverse lookup).
create function app.sub_feed(ev app.events) returns void
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
                              jsonb_build_object('thread', ev.subject_id, 'subject', m.subject, 'label', ev.payload ->> 'label', 'enrollment', ev.payload ->> 'enrollment'),
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

-- the hourly check: cards that time makes true, and cards whose condition cleared. Also emits deal.no_reply
-- once per unanswered message, for the «No reply in 5 days» template.
create function app.feed_checks() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  -- no reply in 5 days on a deal thread
  for r in select d.id deal_id, d.owner_id, d.organization_id, d.is_sample, t.id thread_id, t.subject, t.last_message_at,
                  (select m.id from app.email_messages m where m.thread_id = t.id and m.direction = 'out' and m.state = 'sent' order by m.sent_at desc limit 1) msg
           from app.deals d join app.email_links l on l.entity = 'deal' and l.record_id = d.id join app.email_threads t on t.id = l.thread_id
           where d.status = 'open' and d.deleted_at is null and t.deleted_at is null and t.last_direction = 'out' and t.last_message_at <= now() - interval '5 days'
             and exists (select 1 from app.email_messages m where m.thread_id = t.id and m.direction = 'out' and m.state = 'sent') loop
    if not exists (select 1 from app.feed_cards c where c.dedupe_key = 'no_reply:' || r.deal_id || ':' || r.msg) then
      perform app.feed_card('no_reply', r.owner_id, r.deal_id, r.organization_id, 'email_thread', r.thread_id,
                            jsonb_build_object('thread', r.thread_id, 'subject', r.subject, 'since', r.last_message_at), 'no_reply:' || r.deal_id || ':' || r.msg, r.is_sample);
      insert into app.events (kind, subject_type, subject_id, payload, is_sample) values ('deal.no_reply', 'deal', r.deal_id, jsonb_build_object('thread', r.thread_id, 'message', r.msg), r.is_sample);
      n := n + 1;
    end if;
  end loop;
  -- planned today (the owner's day, in their time zone)
  for r in select a.id, a.subject, a.starts_at, a.priority, a.deal_id, a.owner_id, a.is_sample, d.organization_id, t.key type_key
           from app.activities a join app.admins s on s.id = a.owner_id join app.activity_types t on t.id = a.type_id left join app.deals d on d.id = a.deal_id
           where not a.done and a.deleted_at is null and a.deal_id is not null and (a.starts_at at time zone s.time_zone)::date = (now() at time zone s.time_zone)::date loop
    perform app.feed_card('planned_today', r.owner_id, r.deal_id, r.organization_id, 'activity', r.id,
                          jsonb_build_object('subject', r.subject, 'type', r.type_key, 'starts_at', r.starts_at, 'priority', r.priority), 'planned:' || r.id, r.is_sample);
  end loop;
  -- sequence emails waiting for review
  for r in select m.id, m.subject, m.sent_by, m.is_sample, se.record_id, se.entity, w.name seq
           from app.email_messages m join app.sequence_enrollments se on se.id = m.enrollment_id join app.workflows w on w.id = se.workflow_id
           where m.state = 'awaiting_review' loop
    perform app.feed_card('sequence_review', r.sent_by, case when r.entity = 'deal' then r.record_id end, null, 'email_message', r.id,
                          jsonb_build_object('subject', r.subject, 'sequence', r.seq, 'message', r.id), 'review:' || r.id, r.is_sample);
  end loop;
  -- overdue activities on open deals
  for r in select a.id, a.subject, a.starts_at, d.id deal_id, d.owner_id, d.organization_id, d.is_sample,
                  extract(day from now() - coalesce(d.last_activity_at, d.created_at))::int idle
           from app.activities a join app.deals d on d.id = a.deal_id
           where not a.done and a.deleted_at is null and a.starts_at < now() and d.status = 'open' and d.deleted_at is null loop
    perform app.feed_card('overdue_activity', r.owner_id, r.deal_id, r.organization_id, 'activity', r.id,
                          jsonb_build_object('subject', r.subject, 'due', r.starts_at, 'idle_days', r.idle), 'overdue:' || r.id, r.is_sample);
  end loop;
  -- open deals with nothing planned
  for r in select d.id, d.owner_id, d.organization_id, d.is_sample, coalesce(d.last_activity_at, d.created_at) since
           from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.created_at < now() - interval '1 day'
             and not exists (select 1 from app.activities a where a.deal_id = d.id and not a.done and a.deleted_at is null) loop
    perform app.feed_card('no_followup', r.owner_id, r.id, r.organization_id, 'deal', r.id,
                          jsonb_build_object('idle_days', extract(day from now() - r.since)::int), 'nofollow:' || r.id || ':' || r.since::date, r.is_sample);
  end loop;
  -- slipping: the close date is within 7 days or past and the deal has been idle beyond its stage's threshold
  for r in select d.id, d.owner_id, d.organization_id, d.is_sample, d.expected_close_date, extract(day from now() - coalesce(d.last_activity_at, d.created_at))::int idle
           from app.deals d join app.stages s on s.id = d.stage_id
           where d.status = 'open' and d.deleted_at is null and d.expected_close_date <= current_date + 7
             and coalesce(d.last_activity_at, d.created_at) < now() - make_interval(days => coalesce(s.rot_days, 14)) loop
    perform app.feed_card('slipping', r.owner_id, r.id, r.organization_id, 'deal', r.id,
                          jsonb_build_object('close_date', r.expected_close_date, 'idle_days', r.idle), 'slipping:' || r.id || ':' || r.expected_close_date, r.is_sample);
  end loop;
  -- stalled: longer in the stage than its threshold
  for r in select d.id, d.owner_id, d.organization_id, d.is_sample, d.stage_entered_at, s.name stage, extract(day from now() - d.stage_entered_at)::int days
           from app.deals d join app.stages s on s.id = d.stage_id
           where d.status = 'open' and d.deleted_at is null and s.rot_days is not null and d.stage_entered_at < now() - make_interval(days => s.rot_days) loop
    perform app.feed_card('stalled', r.owner_id, r.id, r.organization_id, 'deal', r.id,
                          jsonb_build_object('stage', r.stage, 'days_in_stage', r.days), 'stalled:' || r.id || ':' || r.stage_entered_at::date, r.is_sample);
  end loop;
  -- new deals with no activity at all
  for r in select d.id, d.owner_id, d.organization_id, d.is_sample from app.deals d
           where d.status = 'open' and d.deleted_at is null and d.created_at between now() - interval '14 days' and now() - interval '1 day'
             and not exists (select 1 from app.activities a where a.deal_id = d.id and a.deleted_at is null) loop
    perform app.feed_card('new_no_activity', r.owner_id, r.id, r.organization_id, 'deal', r.id, '{}'::jsonb, 'new:' || r.id, r.is_sample);
  end loop;
  -- cross-sell: a customer with one application and 50 or more employees
  for r in select o.id, o.owner_id, o.is_sample, o.employees, min(ap.product) product from app.organizations o join app.account_products ap on ap.account_id = o.account_id
           where o.deleted_at is null and coalesce(o.employees, 0) >= 50 group by o.id having count(*) = 1 loop
    perform app.feed_card('cross_sell', r.owner_id, null, r.id, 'organization', r.id,
                          jsonb_build_object('employees', r.employees, 'product', r.product), 'xsell:' || r.id, r.is_sample);
  end loop;
  -- conditions that cleared
  update app.feed_cards c set resolved_at = now(), resolved_by = 'cleared' where c.resolved_at is null and (
       (c.kind = 'overdue_activity' and not exists (select 1 from app.activities a where a.id = c.source_id and not a.done and a.deleted_at is null))
    or (c.kind = 'planned_today' and not exists (select 1 from app.activities a join app.admins s on s.id = a.owner_id where a.id = c.source_id and not a.done and a.deleted_at is null
                                                 and (a.starts_at at time zone s.time_zone)::date = (now() at time zone s.time_zone)::date))
    or (c.kind = 'no_followup' and exists (select 1 from app.activities a where a.deal_id = c.deal_id and not a.done and a.deleted_at is null))
    or (c.kind = 'new_no_activity' and exists (select 1 from app.activities a where a.deal_id = c.deal_id and a.deleted_at is null))
    or (c.kind = 'sequence_review' and not exists (select 1 from app.email_messages m where m.id = c.source_id and m.state = 'awaiting_review'))
    or (c.kind = 'no_reply' and not exists (select 1 from app.email_threads t where t.id = c.source_id and t.last_direction = 'out'))
    or (c.kind = 'cross_sell' and (select count(*) from app.organizations o join app.account_products ap on ap.account_id = o.account_id where o.id = c.organization_id) <> 1));
  return n;
end $fn$;

-- the Feed screen: cards for a tab, with their deal; filters {stage_ids, kinds}. Scope (pipelines, stages)
-- is the user's own setting.
create function public.feed_get(p_tab text default 'follow_ups', p_filter jsonb default '{}'::jsonb) returns jsonb
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
                                                                   'person_id', d.person_id) end,
        'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'city', o.city) from app.organizations o where o.id = coalesce(c.organization_id, d.organization_id)))
        order by fk.ord, c.created_at desc)
      from app.feed_cards c join app.feed_card_kinds fk on fk.kind = c.kind left join app.deals d on d.id = c.deal_id
      where c.staff_id = v_me and c.resolved_at is null and fk.tab = p_tab and c.is_sample = v_sample and (v_ai or fk.tone <> 'ai')
        and (cardinality(coalesce(sc.pipeline_ids, '{}')) = 0 or d.pipeline_id = any (sc.pipeline_ids) or c.deal_id is null)
        and (cardinality(coalesce(sc.stage_ids, '{}')) = 0 or d.stage_id = any (sc.stage_ids) or c.deal_id is null)
        and (jsonb_typeof(p_filter -> 'stage_ids') is distinct from 'array' or d.stage_id in (select (x #>> '{}')::uuid from jsonb_array_elements(p_filter -> 'stage_ids') x))
        and (jsonb_typeof(p_filter -> 'kinds') is distinct from 'array' or c.kind in (select jsonb_array_elements_text(p_filter -> 'kinds')))), '[]'::jsonb));
end $fn$;

-- act on a card: task (a task due tomorrow on the deal, owned by me), email (the composer opened), done, dismissed
create function public.feed_resolve(p_id uuid, p_how text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); c app.feed_cards; r jsonb;
begin
  if p_how not in ('task', 'email', 'done', 'dismissed') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'how'; end if;
  select * into c from app.feed_cards where id = p_id and staff_id = v_me and resolved_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_how = 'task' then
    if c.deal_id is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'deal'; end if;
    r := public.rec_save('activity', null, jsonb_build_object('type_id', (select id from app.activity_types where key = 'task'),
           'subject', left('Follow up: ' || (select d.title from app.deals d where d.id = c.deal_id), 200),
           'starts_at', (date_trunc('day', now() at time zone (select time_zone from app.admins where id = v_me)) + interval '1 day 9 hours') at time zone (select time_zone from app.admins where id = v_me),
           'deal_id', c.deal_id, 'owner_id', v_me));
  end if;
  update app.feed_cards set resolved_at = now(), resolved_by = p_how where id = p_id;
  return jsonb_build_object('id', p_id, 'activity_id', r ->> 'id');
end $fn$;

-- the progress panel: today and this month, for me
create function public.feed_progress() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see'); v_tz text := (select time_zone from app.admins where id = v_me);
  v_day0 timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_mon0 timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_sample boolean := (select sandbox from app.admins where id = v_me);
begin
  return jsonb_build_object(
    'done_today', (select count(*) from app.feed_cards where staff_id = v_me and resolved_at >= v_day0 and resolved_by in ('task', 'email', 'done')),
    'today', (select jsonb_build_object(
        'all', jsonb_build_object('done', count(*) filter (where a.done), 'total', count(*)),
        'task', jsonb_build_object('done', count(*) filter (where a.done and t.key = 'task'), 'total', count(*) filter (where t.key = 'task')),
        'call', jsonb_build_object('done', count(*) filter (where a.done and t.key = 'call'), 'total', count(*) filter (where t.key = 'call')))
      from app.activities a join app.activity_types t on t.id = a.type_id
      where a.owner_id = v_me and a.deleted_at is null and a.is_sample = v_sample and a.starts_at >= v_day0 and a.starts_at < v_day0 + interval '1 day'),
    'month', jsonb_build_object(
      'new_deals', (select count(*) from app.deals d where d.owner_id = v_me and d.deleted_at is null and d.is_sample = v_sample and d.created_at >= v_mon0),
      'won_count', (select count(*) from app.deals d where d.owner_id = v_me and d.deleted_at is null and d.is_sample = v_sample and d.status = 'won' and d.won_at >= v_mon0),
      'won_value', (select coalesce(sum(d.value), 0) from app.deals d where d.owner_id = v_me and d.deleted_at is null and d.is_sample = v_sample and d.status = 'won' and d.won_at >= v_mon0),
      'forecast', (select coalesce(round(sum(d.value * s.probability / 100.0)), 0) from app.deals d join app.stages s on s.id = d.stage_id
                   where d.owner_id = v_me and d.deleted_at is null and d.is_sample = v_sample and d.status = 'open'
                     and d.expected_close_date >= v_mon0::date and d.expected_close_date < (v_mon0 + interval '1 month')::date)));
end $fn$;

create function public.feed_scope_set(p_pipeline_ids uuid[], p_stage_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  insert into app.feed_scope (staff_id, pipeline_ids, stage_ids) values (v_me, coalesce(p_pipeline_ids, '{}'), coalesce(p_stage_ids, '{}'))
  on conflict (staff_id) do update set pipeline_ids = excluded.pipeline_ids, stage_ids = excluded.stage_ids, updated_at = now();
  return jsonb_build_object('ok', true);
end $fn$;

-- ---------------------------------------------------------------------------
-- scoring models
create table app.score_models (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 120),
  entity      text not null default 'deal' check (entity in ('deal', 'lead')),
  pipeline_id uuid references app.pipelines (id) on delete cascade,
  state       text not null default 'draft' check (state in ('draft', 'active')),
  base        smallint not null default 0 check (base between 0 and 100),
  points      jsonb not null default '{"high":25,"slight":10,"negative":-10}'::jsonb,
  created_by  uuid references app.admins (id) on delete set null,
  is_sample   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  check (entity = 'deal' or pipeline_id is null)
);
create unique index score_models_one_active on app.score_models (entity, coalesce(pipeline_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where state = 'active' and deleted_at is null;

create table app.score_criteria (
  id        uuid primary key default gen_random_uuid(),
  model_id  uuid not null references app.score_models (id) on delete cascade,
  grp       text not null check (grp in ('high', 'slight', 'negative')),
  ord       int not null default 0,
  label     text check (label is null or char_length(label) <= 120),
  condition jsonb not null check (jsonb_typeof(condition) = 'array')      -- groups: OR of AND, as app.wf_match reads them
);

create table app.record_scores (
  entity      text not null check (entity in ('deal', 'lead')),
  record_id   uuid not null,
  model_id    uuid not null references app.score_models (id) on delete cascade,
  score       smallint not null check (score between 0 and 100),
  hits        jsonb not null default '[]'::jsonb,
  computed_at timestamptz not null default now(),
  primary key (entity, record_id)
);

create function app.score_eval(p_model uuid, p_entity text, p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m app.score_models; c app.score_criteria; v_total int; v_hits jsonb := '[]'::jsonb; v_pts int;
begin
  select * into m from app.score_models where id = p_model;
  v_total := m.base;
  for c in select * from app.score_criteria where model_id = p_model order by grp, ord loop
    if app.wf_match(p_entity, p_id, c.condition) then
      v_pts := coalesce((m.points ->> c.grp)::int, 0);
      v_total := v_total + v_pts;
      v_hits := v_hits || jsonb_build_array(jsonb_build_object('criterion', c.id, 'group', c.grp, 'label', c.label, 'points', v_pts));
    end if;
  end loop;
  return jsonb_build_object('score', greatest(0, least(100, v_total)), 'hits', v_hits);
end $fn$;

-- the active model for a record, its score stored (and on the deal card)
create function app.score_record(p_entity text, p_id uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_model uuid; r jsonb;
begin
  if p_entity = 'deal' then
    select m.id into v_model from app.score_models m join app.deals d on d.id = p_id
    where m.entity = 'deal' and m.state = 'active' and m.deleted_at is null and (m.pipeline_id = d.pipeline_id or m.pipeline_id is null)
    order by m.pipeline_id is null limit 1;
  elsif p_entity = 'lead' then
    select m.id into v_model from app.score_models m where m.entity = 'lead' and m.state = 'active' and m.deleted_at is null limit 1;
  else return;
  end if;
  if v_model is null then
    delete from app.record_scores where entity = p_entity and record_id = p_id;
    if p_entity = 'deal' then update app.deals set score = null, score_breakdown = null where id = p_id and score is not null; end if;
    return;
  end if;
  r := app.score_eval(v_model, p_entity, p_id);
  insert into app.record_scores (entity, record_id, model_id, score, hits, computed_at) values (p_entity, p_id, v_model, (r ->> 'score')::smallint, r -> 'hits', now())
  on conflict (entity, record_id) do update set model_id = excluded.model_id, score = excluded.score, hits = excluded.hits, computed_at = now();
  if p_entity = 'deal' then
    update app.deals set score = (r ->> 'score')::smallint, score_breakdown = r -> 'hits' where id = p_id and (score, score_breakdown) is distinct from ((r ->> 'score')::smallint, r -> 'hits');
  end if;
end $fn$;

-- the scores subscriber: a record that changed, or mail and activities on it, is scored again
create function app.sub_scores(ev app.events) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare l jsonb; v_id uuid;
begin
  if not exists (select 1 from app.score_models where state = 'active' and deleted_at is null) then return; end if;
  if ev.subject_type in ('deal', 'lead') and ev.kind !~ '\.deleted$' then
    perform app.score_record(ev.subject_type, ev.subject_id);
  elsif ev.subject_type = 'email_thread' then
    for l in select * from jsonb_array_elements(coalesce(ev.payload -> 'links', '[]'::jsonb)) where value ->> 'entity' in ('deal', 'lead') loop
      perform app.score_record(l ->> 'entity', (l ->> 'id')::uuid);
    end loop;
  elsif ev.subject_type = 'organization' then
    for v_id in select id from app.deals where organization_id = ev.subject_id and status = 'open' and deleted_at is null loop perform app.score_record('deal', v_id); end loop;
    for v_id in select id from app.leads where organization_id = ev.subject_id and deleted_at is null and converted_at is null loop perform app.score_record('lead', v_id); end loop;
  elsif ev.subject_type = 'activity' then
    v_id := (ev.payload ->> 'deal')::uuid;
    if v_id is not null then perform app.score_record('deal', v_id); end if;
  end if;
end $fn$;

create function app.scores_nightly() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; n int := 0;
begin
  for v_id in select id from app.deals where status = 'open' and deleted_at is null loop perform app.score_record('deal', v_id); n := n + 1; end loop;
  for v_id in select id from app.leads where deleted_at is null and converted_at is null and archived_at is null loop perform app.score_record('lead', v_id); n := n + 1; end loop;
  return n;
end $fn$;

create function public.score_models_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  return jsonb_build_object('limit', app.count_limit(), 'models', coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'entity', m.entity, 'pipeline_id', m.pipeline_id, 'pipeline', (select p.name from app.pipelines p where p.id = m.pipeline_id),
      'state', m.state, 'base', m.base, 'points', m.points,
      'scored', (select count(*) from app.record_scores rs where rs.model_id = m.id),
      'criteria', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'group', c.grp, 'ord', c.ord, 'label', c.label, 'condition', c.condition) order by c.grp, c.ord)
                            from app.score_criteria c where c.model_id = m.id), '[]'::jsonb))
      order by m.created_at) from app.score_models m where m.deleted_at is null), '[]'::jsonb));
end $fn$;

-- create or update a model and replace its criteria [{group, label, condition}]
create function public.score_model_save(p_id uuid, p_values jsonb, p_criteria jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'configure'); v_id uuid := p_id; x jsonb; i int := 0; v_limit numeric := app.count_limit(); v_entity text;
begin
  if jsonb_typeof(p_criteria) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'criteria'; end if;
  v_entity := coalesce(p_values ->> 'entity', (select entity from app.score_models where id = p_id), 'deal');
  if v_entity not in ('deal', 'lead') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  for x in select * from jsonb_array_elements(p_criteria) loop
    if x ->> 'group' not in ('high', 'slight', 'negative') or jsonb_typeof(x -> 'condition') <> 'array' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'criteria';
    end if;
  end loop;
  if p_id is null then
    if v_limit is not null and (select count(*) from app.score_models where deleted_at is null) >= v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'limit';
    end if;
    insert into app.score_models (name, entity, pipeline_id, base, created_by, is_sample)
    values (btrim(p_values ->> 'name'), v_entity, case when v_entity = 'deal' then (p_values ->> 'pipeline_id')::uuid end,
            coalesce((p_values ->> 'base')::smallint, 0), v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.score_models set name = coalesce(btrim(p_values ->> 'name'), name),
      pipeline_id = case when p_values ? 'pipeline_id' and entity = 'deal' then (p_values ->> 'pipeline_id')::uuid else pipeline_id end,
      base = coalesce((p_values ->> 'base')::smallint, base), updated_at = now()
    where id = p_id and deleted_at is null;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  delete from app.score_criteria where model_id = v_id;
  for x in select * from jsonb_array_elements(p_criteria) loop
    i := i + 1;
    insert into app.score_criteria (model_id, grp, ord, label, condition) values (v_id, x ->> 'group', i, left(x ->> 'label', 120), x -> 'condition');
  end loop;
  -- the conditions must be readable: try them once on no record
  perform app.score_eval(v_id, v_entity, '00000000-0000-0000-0000-000000000000'::uuid);
  perform app.log(case when p_id is null then 'score_model.created' else 'score_model.updated' end, 'score_model', v_id::text, jsonb_build_object('criteria', i));
  if (select state from app.score_models where id = v_id) = 'active' then perform app.scores_nightly(); end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.score_model_activate(p_id uuid, p_active boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'configure'); m app.score_models;
begin
  select * into m from app.score_models where id = p_id and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_active then
    update app.score_models set state = 'draft', updated_at = now()
    where id <> p_id and entity = m.entity and pipeline_id is not distinct from m.pipeline_id and state = 'active' and deleted_at is null;
  end if;
  update app.score_models set state = case when p_active then 'active' else 'draft' end, updated_at = now() where id = p_id;
  perform app.log(case when p_active then 'score_model.activated' else 'score_model.deactivated' end, 'score_model', p_id::text, null);
  perform app.scores_nightly();
  return jsonb_build_object('id', p_id, 'state', case when p_active then 'active' else 'draft' end);
end $fn$;

create function public.score_preview(p_model uuid, p_record uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m app.score_models; e app.entities; v_ok boolean;
begin
  perform app.require('deals', 'see');
  select * into m from app.score_models where id = p_model and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  e := app.entity(m.entity);
  execute format('select true from app.%I t where t.id = %L and t.deleted_at is null and %s', e.tbl, p_record, app.vis_sql(e)) into v_ok;
  if v_ok is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return app.score_eval(p_model, m.entity, p_record);
end $fn$;

-- ---------------------------------------------------------------------------
-- enrichment
create table app.enrichment_requests (
  id             uuid primary key default gen_random_uuid(),
  entity         text not null check (entity in ('organization', 'person')),
  record_id      uuid not null,
  kind           text not null check (kind in ('company', 'person')),
  provider       text not null check (provider in ('brreg', 'contact_data')),
  state          text not null default 'requested' check (state in ('requested', 'ready', 'applied', 'failed', 'dismissed')),
  proposed       jsonb not null default '{}'::jsonb check (jsonb_typeof(proposed) = 'object'),
  applied_fields text[] not null default '{}',
  credits        int not null default 0 check (credits >= 0),
  error          text check (error is null or char_length(error) <= 300),
  requested_by   uuid references app.admins (id) on delete set null,
  created_at     timestamptz not null default now(),
  applied_at     timestamptz
);
create index enrichment_record on app.enrichment_requests (entity, record_id, created_at desc);

create table app.credit_ledger (
  id         bigint generated always as identity primary key,
  delta      int not null,
  provider   text not null check (provider in ('contact_data')),
  request_id uuid references app.enrichment_requests (id) on delete set null,
  staff_id   uuid references app.admins (id) on delete set null,
  at         timestamptz not null default now()
);

create table app.lookup_suggestions (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid references app.email_threads (id) on delete cascade,
  from_addr  text not null unique check (char_length(from_addr) <= 254),
  from_name  text check (from_name is null or char_length(from_name) <= 200),
  domain     text not null check (char_length(domain) <= 200),
  proposed   jsonb not null default '{}'::jsonb check (jsonb_typeof(proposed) = 'object'),
  state      text not null default 'open' check (state in ('open', 'accepted', 'dismissed')),
  is_sample  boolean not null default false,
  created_at timestamptz not null default now(),
  decided_by uuid references app.admins (id) on delete set null,
  decided_at timestamptz
);

-- the fields Brønnøysund can fill on an organisation
create function app.enrich_fields() returns text[]
  language sql immutable set search_path = ''
as $fn$ select array['address', 'postal_code', 'city', 'nace', 'industry', 'employees', 'website'] $fn$;

-- ask for the register's data on an organisation (or many, at most 100)
create function public.enrich_request(p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); x uuid; n int := 0; v_id uuid;
begin
  if cardinality(p_ids) > 100 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  if cardinality(p_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  foreach x in array coalesce(p_ids, '{}') loop
    continue when not exists (select 1 from app.organizations o where o.id = x and o.deleted_at is null and o.org_number is not null and app.visible(o.owner_id, o.visibility));
    continue when exists (select 1 from app.enrichment_requests r where r.entity = 'organization' and r.record_id = x and r.state = 'requested');
    insert into app.enrichment_requests (entity, record_id, kind, provider, requested_by) values ('organization', x, 'company', 'brreg', v_me) returning id into v_id;
    perform pgmq.send('jobs', jsonb_build_object('job', 'enrich', 'request_id', v_id));
    n := n + 1;
  end loop;
  perform app.log('enrichment.requested', 'organization', case when cardinality(p_ids) = 1 then p_ids[1]::text end, jsonb_build_object('count', n));
  return jsonb_build_object('requested', n);
end $fn$;

-- person enrichment needs the contact-data provider
create function public.enrich_person(p_person uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  if not exists (select 1 from app.integration_connections where provider = 'contact_data' and status = 'connected') then
    raise exception 'not_connected' using errcode = 'invalid_parameter_value', detail = 'contact_data';
  end if;
  raise exception 'not_available' using errcode = 'invalid_parameter_value', detail = 'contact_data';
end $fn$;

-- the Enrichment view: candidates, the open diffs, suggestions and usage
create function public.enrichment_get(p_org uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_mon0 timestamptz := date_trunc('month', now());
begin
  return jsonb_build_object(
    'candidates', (select count(*) from app.organizations o where o.deleted_at is null and o.org_number is not null and app.visible(o.owner_id, o.visibility)
                     and (o.address is null or o.postal_code is null or o.city is null or o.nace is null or o.industry is null or o.employees is null or o.website is null)),
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
                                                             'proposed', s.proposed,
                                                             'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o
                                                                              where o.deleted_at is null and lower(o.website) like '%' || s.domain || '%' limit 1))
                                          order by s.created_at desc)
                         from app.lookup_suggestions s where s.state = 'open' and (s.thread_id is null or app.thread_visible(s.thread_id))), '[]'::jsonb));
end $fn$;

-- apply: empty fields only, history source «enrichment»
create function public.enrich_apply(p_request uuid, p_fields text[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); r app.enrichment_requests; o jsonb; f text; v_applied text[] := '{}'; v_sets text[] := '{}';
begin
  select * into r from app.enrichment_requests where id = p_request and state = 'ready' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select to_jsonb(x) into o from app.organizations x where x.id = r.record_id and x.deleted_at is null and app.visible(x.owner_id, x.visibility);
  if o is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if (o ->> 'owner_id') is distinct from v_me::text and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  foreach f in array coalesce(p_fields, '{}') loop
    continue when not (f = any (app.enrich_fields())) or not (r.proposed ? f) or ((o -> f) is not null and (o ->> f) <> '');
    v_sets := v_sets || format('%I = %s', f, app.lit(r.proposed -> f, case f when 'employees' then 'int' else 'text' end));
    v_applied := v_applied || f;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('organization', r.record_id, f, o -> f, r.proposed -> f, v_me, 'enrichment');
  end loop;
  if cardinality(v_sets) > 0 then
    execute format('update app.organizations set %s, brreg_synced_at = now(), version = version + 1, updated_at = now(), updated_by = %L where id = %L',
                   array_to_string(v_sets, ', '), v_me, r.record_id);
    perform app.emit('organization.updated', 'organization', r.record_id, jsonb_build_object('fields', to_jsonb(v_applied), 'source', 'enrichment'));
  end if;
  update app.enrichment_requests set state = 'applied', applied_fields = v_applied, applied_at = now() where id = p_request;
  perform app.log('enrichment.applied', 'organization', r.record_id::text, jsonb_build_object('fields', to_jsonb(v_applied)));
  return jsonb_build_object('applied', to_jsonb(v_applied));
end $fn$;

create function public.enrich_dismiss(p_request uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  update app.enrichment_requests set state = 'dismissed' where id = p_request and state in ('ready', 'failed', 'requested');
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('id', p_request);
end $fn$;

-- a suggestion becomes a person (and the organisation, when named and new), linked to the thread
create function public.lookup_decide(p_id uuid, p_accept boolean, p_values jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); s app.lookup_suggestions; v_org uuid := (p_values ->> 'organization_id')::uuid; r jsonb; v_person uuid;
begin
  select * into s from app.lookup_suggestions where id = p_id and state = 'open' for update;
  if not found or (s.thread_id is not null and not app.thread_visible(s.thread_id)) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_accept then
    perform app.require('deals', 'add');
    if v_org is null and coalesce(btrim(p_values ->> 'organization_name'), '') <> '' then
      r := public.rec_save('organization', null, jsonb_build_object('name', btrim(p_values ->> 'organization_name'), 'website', s.domain, 'source', 'email'));
      v_org := (r ->> 'id')::uuid;
    end if;
    r := public.rec_save('person', null, jsonb_build_object('name', coalesce(nullif(btrim(p_values ->> 'name'), ''), s.from_name, split_part(s.from_addr, '@', 1)),
                                                            'email', s.from_addr, 'organization_id', v_org, 'source', 'email'));
    v_person := (r ->> 'id')::uuid;
    if s.thread_id is not null then
      update app.email_thread_participants set person_id = v_person where thread_id = s.thread_id and address = s.from_addr;
      insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) values (s.thread_id, 'person', v_person, 'manual', v_me) on conflict do nothing;
      if v_org is not null then
        insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) values (s.thread_id, 'organization', v_org, 'manual', v_me) on conflict do nothing;
      end if;
    end if;
  end if;
  update app.lookup_suggestions set state = case when p_accept then 'accepted' else 'dismissed' end, decided_by = v_me, decided_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'person_id', v_person, 'organization_id', v_org);
end $fn$;

-- the enrichment worker reports the register's answer: {address, postal_code, city, nace, industry, employees, website} or {error}
create function public.worker_enrich_done(p_request uuid, p_result jsonb) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.enrichment_requests set
    state = case when p_result ? 'error' then 'failed' else 'ready' end,
    error = left(p_result ->> 'error', 300),
    proposed = (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(p_result) as x(k, v) where k = any (app.enrich_fields()) and jsonb_typeof(v) in ('string', 'number'))
  where id = p_request and state = 'requested';
end $fn$;

create function public.worker_enrich_get(p_request uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', r.id, 'provider', r.provider, 'org_number', o.org_number)
  from app.enrichment_requests r join app.organizations o on o.id = r.record_id where r.id = p_request and r.state = 'requested'
$fn$;

-- ---------------------------------------------------------------------------
-- calls without a provider: a match by number, and a call logged by hand as a done activity (COM-10)
create table app.call_logs (
  activity_id      uuid primary key references app.activities (id) on delete cascade,
  direction        text not null check (direction in ('outbound', 'inbound')),
  outcome          text not null check (outcome in ('connected', 'no_answer', 'missed', 'busy', 'voicemail')),
  duration_s       int check (duration_s is null or duration_s between 0 and 86400),
  number           text check (number is null or char_length(number) <= 40),
  provider_call_id text,
  source           text not null default 'manual' check (source in ('manual', 'provider'))
);

create function public.phone_match(p_number text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_digits text := right(regexp_replace(coalesce(p_number, ''), '\D', '', 'g'), 8);
begin
  perform app.require('deals', 'see');
  if char_length(v_digits) < 6 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('person_id', p.id, 'name', p.name, 'organization', (select o.name from app.organizations o where o.id = p.organization_id),
                                                       'deal_id', (select d.id from app.deals d where d.person_id = p.id and d.status = 'open' and d.deleted_at is null order by d.updated_at desc limit 1)))
                   from (select * from app.people p where p.deleted_at is null and app.visible(p.owner_id, p.visibility)
                         and right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 8) = v_digits limit 5) p), '[]'::jsonb);
end $fn$;

-- {person_id, deal_id, number, direction, outcome, duration_s, note}
create function public.call_log_save(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); r jsonb; v_act uuid; v_person uuid := (p_values ->> 'person_id')::uuid; v_deal uuid := (p_values ->> 'deal_id')::uuid;
begin
  if coalesce(p_values ->> 'direction', 'outbound') not in ('outbound', 'inbound') or coalesce(p_values ->> 'outcome', '') not in ('connected', 'no_answer', 'missed', 'busy', 'voicemail') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'outcome';
  end if;
  r := public.rec_save('activity', null, jsonb_strip_nulls(jsonb_build_object(
         'type_id', (select id from app.activity_types where key = 'call'),
         'subject', left(coalesce(nullif(btrim(p_values ->> 'subject'), ''), 'Call'), 200),
         'starts_at', now() - make_interval(secs => coalesce((p_values ->> 'duration_s')::int, 0)),
         'duration_min', greatest(0, round(coalesce((p_values ->> 'duration_s')::int, 0) / 60.0))::int,
         'note', nullif(btrim(p_values ->> 'note'), ''), 'person_id', v_person, 'deal_id', v_deal,
         'organization_id', (select organization_id from app.people where id = v_person))));
  v_act := (r ->> 'id')::uuid;
  perform public.activity_done(v_act, true);
  insert into app.call_logs (activity_id, direction, outcome, duration_s, number)
  values (v_act, coalesce(p_values ->> 'direction', 'outbound'), p_values ->> 'outcome', (p_values ->> 'duration_s')::int, left(p_values ->> 'number', 40));
  return jsonb_build_object('activity_id', v_act);
end $fn$;

create function public.call_log_get(p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  return jsonb_build_object('telephony', (select status from app.integration_connections where provider = 'telephony'),
    'calls', coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (
      select jsonb_build_object('activity_id', a.id, 'at', a.starts_at, 'direction', c.direction, 'outcome', c.outcome, 'duration_s', c.duration_s, 'number', c.number,
                                'person_id', a.person_id, 'person', (select p.name from app.people p where p.id = a.person_id),
                                'deal_id', a.deal_id, 'note', a.note, 'source', c.source) x
      from app.call_logs c join app.activities a on a.id = c.activity_id
      where a.deleted_at is null and app.visible(a.owner_id, a.visibility) order by a.starts_at desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) s), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
insert into app.event_subscribers (name, fn, ord) values ('feed', 'app.sub_feed', 40), ('scores', 'app.sub_scores', 50);
insert into app.event_cursors (subscriber, last_event_id) values ('feed', 0), ('scores', 0);

select cron.schedule('platform-feed-checks', '23 * * * *', 'select app.feed_checks()');
select cron.schedule('platform-scores', '41 2 * * *', 'select app.scores_nightly()');

do $$
declare t text;
begin
  foreach t in array array['feed_card_kinds', 'feed_cards', 'feed_scope', 'score_models', 'score_criteria', 'record_scores', 'enrichment_requests', 'credit_ledger',
                           'lookup_suggestions', 'call_logs'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.wf_match(text, uuid, jsonb)', 'app.feed_card(text, uuid, uuid, uuid, text, uuid, jsonb, text, boolean)', 'app.sub_feed(app.events)',
                           'app.feed_checks()', 'app.score_eval(uuid, text, uuid)', 'app.score_record(text, uuid)', 'app.sub_scores(app.events)',
                           'app.scores_nightly()', 'app.enrich_fields()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.feed_get(text, jsonb)', 'public.feed_resolve(uuid, text)', 'public.feed_progress()', 'public.feed_scope_set(uuid[], uuid[])',
                           'public.score_models_get()', 'public.score_model_save(uuid, jsonb, jsonb)', 'public.score_model_activate(uuid, boolean)',
                           'public.score_preview(uuid, uuid)', 'public.enrich_request(uuid[])', 'public.enrich_person(uuid)', 'public.enrichment_get(uuid)',
                           'public.enrich_apply(uuid, text[])', 'public.enrich_dismiss(uuid)', 'public.lookup_decide(uuid, boolean, jsonb)',
                           'public.phone_match(text)', 'public.call_log_save(jsonb)', 'public.call_log_get(int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_enrich_done(uuid, jsonb)', 'public.worker_enrich_get(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
