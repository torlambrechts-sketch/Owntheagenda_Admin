-- 0050_crm_requests.sql — the Meetings screen's database requests (docs/crm-enrichment/requests/meetings.md R-MEETINGS-01..05).
--
-- R-MEETINGS-01: meeting_controls() names the controller a recording notice speaks for (app.mtg_controller(), the verified
--                transactional sender; null when there is none, and then no notice can go out).
-- R-MEETINGS-02: public.shell() says whether the caller has the meeting workspace (meetings_workspace), so the navigation
--                hides «Meetings» from a staff member without deals:see, with the module off or with their switch off (MTG-08 A).
-- R-MEETINGS-03: a brief's «health:<product>» and «applications» facts carry the organisation's name; «applications» is one
--                line per organisation (it was one line for all of them, cited to the first).
-- R-MEETINGS-04: a CRM update suggestion on a money column (`value` of a deal or a lead) carries the record's currency.
-- R-MEETINGS-05: meeting_transcript().speakers[] carries the address a label is mapped to (a guest unknown to the CRM),
--                left out when the label names a person the caller may not see.
--
-- Redefined in full from their newest bodies: public.shell() (0014), app.mtg_brief_build, public.meeting_transcript,
-- public.meeting_suggestions, public.meeting_controls (0042).
--
-- The campaigns and projects requests named with these (R-CAMPAIGNS-02, 04, 05, R-PROJECTS-04, and R-CAMPAIGNS-03 at tenant
-- level) were done in 0040; R-CAMPAIGNS-01, R-PROJECTS-01..03 and R-MEETINGS-06 need storage or workers, not a migration.

-- ===========================================================================
-- R-MEETINGS-02: the shell knows whether the caller has the meeting workspace
-- ===========================================================================
-- (0014, plus meetings_workspace)
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
                    and t.status not in ('resolved', 'closed') and app.queue_ok(t.queue_key) and (v_sandbox or not t.is_sample)), 0) end)),
    -- R-MEETINGS-02: the meeting workspace as app.mtg_require() decides it (deals:see, the module, the caller's own switch)
    'meetings_workspace', app.can('deals', 'see') and app.module_on('meetings')
                          and coalesce((select s.enabled from app.meeting_user_settings s where s.staff_id = v_me), true));
end $fn$;

-- ===========================================================================
-- R-MEETINGS-03: the brief's health and applications facts name their organisation
-- ===========================================================================
-- (0042; 0050: «health:<product>» carries params.organization, and «applications» is one line per organisation with its name)
create or replace function app.mtg_brief_build(p_meeting uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  m app.meetings; v_people uuid[]; v_orgs uuid[]; v_last timestamptz; v_since timestamptz; v_changes jsonb; v_who jsonb; v_facts jsonb;
  v_quotes_state text;
begin
  select * into m from app.meetings where id = p_meeting and deleted_at is null;
  if not found then return; end if;
  v_people := app.mtg_people(m);
  v_orgs := app.mtg_orgs(m);
  v_last := greatest(
    (select max(coalesce(a.done_at, a.starts_at)) from app.activities a
     where a.done and a.deleted_at is null and coalesce(a.done_at, a.starts_at) < now() and a.id is distinct from m.activity_id
       and (a.deal_id = m.deal_id or a.lead_id = m.lead_id or a.person_id = any (v_people))),
    (select max(coalesce(em.received_at, em.sent_at)) from app.email_messages em
     where em.state in ('sent', 'received') and coalesce(em.received_at, em.sent_at) < now()
       and (em.person_id = any (v_people) or exists (select 1 from app.email_links el where el.thread_id = em.thread_id
              and ((el.entity = 'deal' and el.record_id = m.deal_id) or (el.entity = 'lead' and el.record_id = m.lead_id))))),
    (select max(o.starts_at) from app.meetings o
     where o.id <> m.id and o.deleted_at is null and o.cancelled_at is null and o.starts_at < least(now(), coalesce(m.starts_at, now()))
       and (o.deal_id = m.deal_id or o.lead_id = m.lead_id
            or exists (select 1 from app.meeting_attendees oa where oa.meeting_id = o.id and oa.person_id = any (v_people)))));
  v_since := coalesce(v_last, now() - interval '30 days');

  select coalesce(jsonb_agg(c order by c ->> 'at' desc), '[]'::jsonb) into v_changes from (
    -- field changes on the deal, the lead, the organisations and the people (a custom field included)
    (select jsonb_build_object('key', 'chg:' || l.id, 'kind', 'field_changed', 'at', l.at,
                               'params', jsonb_build_object('entity', l.entity, 'field', l.field, 'old', l.old_value, 'new', l.new_value),
                               'source', jsonb_build_object('entity', l.entity, 'id', l.record_id)) c
     from app.changelog l
     where l.at > v_since and l.field !~ '^\*' and l.field not like 'items.%'
       and ((l.entity = 'deal' and l.record_id = m.deal_id) or (l.entity = 'lead' and l.record_id = m.lead_id)
            or (l.entity = 'organization' and l.record_id = any (v_orgs)) or (l.entity = 'person' and l.record_id = any (v_people)))
     order by l.at desc limit 12)
    union all
    -- opens and clicks on mail to the people (prefetches excluded)
    select jsonb_build_object('key', 'trk:' || em.person_id, 'kind', 'email_engagement', 'at', max(t.at),
                              'params', jsonb_build_object('person', max(p.name), 'opens', count(*) filter (where t.kind = 'open'), 'clicks', count(*) filter (where t.kind = 'click')),
                              'source', jsonb_build_object('entity', 'person', 'id', em.person_id))
    from app.email_tracking_events t join app.email_messages em on em.id = t.message_id join app.people p on p.id = em.person_id
    where t.at > v_since and t.client_class <> 'prefetch' and em.person_id = any (v_people)
    group by em.person_id
    union all
    -- the organisations' tickets resolved since, with their CSAT
    select jsonb_build_object('key', 'tkt:' || k.id, 'kind', 'ticket_resolved', 'at', k.resolved_at,
                              'params', jsonb_build_object('number', k.number, 'csat', k.csat_score),
                              'source', jsonb_build_object('entity', 'ticket', 'id', k.id))
    from app.tickets k where k.organization_id = any (v_orgs) and k.resolved_at > v_since and k.deleted_at is null
    union all
    -- people added to the deal
    select jsonb_build_object('key', 'prt:' || dp.person_id, 'kind', 'participant_added', 'at', dp.added_at,
                              'params', jsonb_build_object('person', p.name), 'source', jsonb_build_object('entity', 'person', 'id', dp.person_id))
    from app.deal_participants dp join app.people p on p.id = dp.person_id
    where dp.deal_id = m.deal_id and dp.added_at > v_since
    union all
    -- product counts that changed (D-19: counts only)
    select jsonb_build_object('key', 'cnt:' || x.product || ':' || x.metric, 'kind', 'count_changed', 'at', x.day,
                              'params', jsonb_build_object('product', x.product, 'metric', x.metric, 'from', x.v_from, 'to', x.v_to),
                              'source', jsonb_build_object('entity', 'organization', 'id', x.org))
    from (select o.id org, ap.product, c.metric,
                 (select c2.value from app.product_counts_daily c2 where c2.product = ap.product and c2.tenant_id = ap.tenant_id and c2.metric = c.metric
                  and c2.day <= v_since::date order by c2.day desc limit 1) v_from,
                 (select c3.value from app.product_counts_daily c3 where c3.product = ap.product and c3.tenant_id = ap.tenant_id and c3.metric = c.metric
                  order by c3.day desc limit 1) v_to,
                 max(c.day) as day
          from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
          join app.product_counts_daily c on c.product = ap.product and c.tenant_id = ap.tenant_id and c.day > v_since::date
          where o.id = any (v_orgs) group by o.id, ap.product, ap.tenant_id, c.metric) x
    where x.v_from is not null and x.v_to is distinct from x.v_from) s;

  -- who you meet: external attendees, with what the CRM holds about them
  select coalesce(jsonb_agg(jsonb_build_object(
           'person_id', p.id, 'name', coalesce(p.name, a.name, split_part(a.email, '@', 1)), 'title', p.title,
           'labels', coalesce((select jsonb_agg(lb.name order by lb.ord) from app.labels lb where lb.id = any (p.labels)), '[]'::jsonb),
           'first_meeting', p.id is null or not (
              exists (select 1 from app.meeting_attendees oa join app.meetings o on o.id = oa.meeting_id
                      where oa.person_id = p.id and o.id <> m.id and o.deleted_at is null and o.starts_at < coalesce(m.starts_at, now()))
              or exists (select 1 from app.activities ac where ac.person_id = p.id and ac.done and ac.deleted_at is null)),
           'last_signed_in', (select mb.last_login_at from app.members mb
                              where mb.product = p.member_product and mb.tenant_id = p.member_tenant and mb.user_id = p.member_user),
           'source', case when p.id is not null then jsonb_build_object('entity', 'person', 'id', p.id) end)
         order by coalesce(p.name, a.name, a.email)), '[]'::jsonb)
  into v_who
  from app.meeting_attendees a left join app.people p on p.id = a.person_id and p.deleted_at is null
  where a.meeting_id = m.id and a.external;

  -- deal and organisation facts; a line is omitted when its value is null
  select coalesce(jsonb_agg(f order by f ->> 'ord'), '[]'::jsonb) into v_facts from (
    select jsonb_build_object('key', 'deal', 'ord', '1', 'params', jsonb_build_object('title', d.title, 'value', d.value, 'currency', d.currency,
                              'stage', (select s.name from app.stages s where s.id = d.stage_id), 'status', d.status),
                              'source', jsonb_build_object('entity', 'deal', 'id', d.id)) f
    from app.deals d where d.id = m.deal_id and d.deleted_at is null
    union all
    select jsonb_build_object('key', 'lead', 'ord', '1', 'params', jsonb_build_object('title', x.title, 'seq', x.seq, 'value', x.value, 'currency', x.currency),
                              'source', jsonb_build_object('entity', 'lead', 'id', x.id))
    from app.leads x where x.id = m.lead_id and m.deal_id is null and x.deleted_at is null
    union all
    select jsonb_build_object('key', 'score', 'ord', '2', 'params', jsonb_build_object('score', d.score), 'source', jsonb_build_object('entity', 'deal', 'id', d.id))
    from app.deals d where d.id = m.deal_id and d.deleted_at is null and d.score is not null
    union all
    select jsonb_build_object('key', 'score', 'ord', '2', 'params', jsonb_build_object('score', max(rs.score)), 'source', jsonb_build_object('entity', 'lead', 'id', m.lead_id))
    from app.record_scores rs where m.deal_id is null and rs.entity = 'lead' and rs.record_id = m.lead_id having max(rs.score) is not null
    union all
    select jsonb_build_object('key', 'health:' || h.product, 'ord', '3', 'params', jsonb_build_object('product', h.product, 'score', h.score, 'day', h.day, 'organization', o.name),
                              'source', jsonb_build_object('entity', 'organization', 'id', o.id))
    from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
    join app.v_health_latest h on h.product = ap.product and h.tenant_id = ap.tenant_id
    where o.id = any (v_orgs) and h.score is not null
    union all
    select jsonb_build_object('key', 'applications', 'ord', '4', 'params', jsonb_build_object('products', jsonb_agg(distinct ap.product), 'organization', o.name),
                              'source', jsonb_build_object('entity', 'organization', 'id', o.id))
    from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.deleted_at is null
    where o.id = any (v_orgs) group by o.id, o.name
    union all
    select jsonb_build_object('key', 'custom.' || fd.key, 'ord', '5' || lpad(fd.ord::text, 4, '0'), 'params', jsonb_build_object('label', fd.label, 'value', d.custom -> fd.key),
                              'source', jsonb_build_object('entity', 'deal', 'id', d.id))
    from app.deals d join app.fields fd on fd.entity = 'deal' and fd.quality in ('important', 'required') and fd.archived_at is null
    where d.id = m.deal_id and d.deleted_at is null and jsonb_typeof(d.custom -> fd.key) is not null and jsonb_typeof(d.custom -> fd.key) <> 'null') s;

  -- quotes from earlier conversations need the AI provider; without it the card says so
  v_quotes_state := case when app.connected('ai') then 'requested' else 'not_connected' end;
  insert into app.meeting_briefs (meeting_id, state, generated_at, since_at, last_contact_at, changes, people, facts, quotes, quotes_state)
  values (m.id, 'ready', now(), v_since, v_last, v_changes, v_who, v_facts, '[]'::jsonb, v_quotes_state)
  on conflict (meeting_id) do update set state = 'ready', generated_at = now(), since_at = excluded.since_at, last_contact_at = excluded.last_contact_at,
    changes = excluded.changes, people = excluded.people, facts = excluded.facts,
    quotes = case when excluded.quotes_state = 'requested' then app.meeting_briefs.quotes else '[]'::jsonb end,
    quotes_state = excluded.quotes_state;
  if v_quotes_state = 'requested' then
    perform pgmq.send('jobs', jsonb_build_object('job', 'meeting_brief_quotes', 'meeting_id', m.id, 'staff_id', m.owner_id));
  end if;
  insert into app.audit (actor, action, target_type, target_id, detail, ok)
  values ('system', 'meeting.brief_built', 'meeting', m.id::text,
          jsonb_build_object('changes', jsonb_array_length(v_changes), 'people', jsonb_array_length(v_who), 'facts', jsonb_array_length(v_facts), 'quotes', v_quotes_state), true);
end $fn$;

-- ===========================================================================
-- R-MEETINGS-05: a speaker mapped to an address shows that address
-- ===========================================================================
-- the transcript (§2.3), paged by seq. Text is the speakers' own words: the app escapes it as untrusted (A7.4).
-- → {transcript | null, speakers: [{label, name, kind, staff_id, person_id, email}], segments: [{seq, start_ms, end_ms, label, text, redacted}], next}
-- (0042; 0050: speakers carry the mapped address, except for a person the caller may not see)
create or replace function public.meeting_transcript(p_id uuid, p_cursor int default 0, p_limit int default 200) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); v_limit int := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_rows jsonb; v_last int;
begin
  if t.id is null then return jsonb_build_object('transcript', null, 'speakers', '[]'::jsonb, 'segments', '[]'::jsonb, 'next', null); end if;
  select coalesce(jsonb_agg(jsonb_build_object('seq', s.seq, 'start_ms', s.start_ms, 'end_ms', s.end_ms, 'label', s.speaker_label,
                                               'text', s.text, 'redacted', s.redacted_at is not null) order by s.seq), '[]'::jsonb), max(s.seq)
  into v_rows, v_last
  from (select * from app.transcript_segments where transcript_id = t.id and seq > coalesce(p_cursor, 0) order by seq limit v_limit) s;
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'transcript', 'count', jsonb_array_length(v_rows)));
  return jsonb_build_object(
    'transcript', jsonb_build_object('id', t.id, 'source', t.source, 'state', t.state, 'error_code', t.error_code, 'duration_s', t.duration_s,
                                     'speaker_count', t.speaker_count, 'language', t.language, 'file_name', t.file_name, 'ready_at', t.ready_at),
    'speakers', coalesce((select jsonb_agg(jsonb_build_object('label', sp.label, 'staff_id', sp.staff_id, 'person_id', sp.person_id,
                                                              'name', coalesce(ad.name, case when app.mtg_target_ok('person', sp.person_id) then p.name end),
                                                              'kind', case when sp.staff_id is not null then 'staff' when sp.person_id is not null then 'external' else 'unknown' end,
                                                              'email', case when sp.person_id is null or app.mtg_target_ok('person', sp.person_id) then sp.email end)
                                           order by sp.label)
                          from app.transcript_speakers sp left join app.admins ad on ad.id = sp.staff_id left join app.people p on p.id = sp.person_id
                          where sp.transcript_id = t.id), '[]'::jsonb),
    'segments', v_rows,
    'next', case when exists (select 1 from app.transcript_segments where transcript_id = t.id and seq > v_last) then v_last end);
end $fn$;

-- ===========================================================================
-- R-MEETINGS-04: a suggestion on a money column carries the record's currency
-- ===========================================================================
-- CRM update suggestions (§2.4) of the newest transcript; stale_now: the record moved since the proposal
-- (0042; 0050: currency — the deal's or lead's own — when the field is its «value», else null)
create or replace function public.meeting_suggestions(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); t app.meeting_transcripts := app.mtg_transcript(p_id); v_out jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'ord', s.ord, 'target_entity', s.target_entity, 'target_id', s.target_id,
      'target_title', case when s.target_id is not null then app.record_title(s.target_entity, s.target_id) end,
      'field', s.field, 'field_label', case when s.field like 'custom.%' then (select f.label from app.fields f where f.entity = s.target_entity and f.key = substr(s.field, 8)) end,
      'currency', case when s.field = 'value' and s.target_id is not null then
                    case s.target_entity when 'deal' then (select d.currency from app.deals d where d.id = s.target_id)
                                         when 'lead' then (select l.currency from app.leads l where l.id = s.target_id) end end,
      'current_value', s.current_value, 'proposed_value', s.proposed_value, 'evidence', to_jsonb(s.evidence), 'state', s.state, 'error_code', s.error_code,
      'decided_by', (select a.name from app.admins a where a.id = s.decided_by), 'decided_at', s.decided_at, 'written_record_id', s.written_record_id,
      'stale_now', s.state = 'pending' and app.mtg_suggestion_current(s) is distinct from s.current_value)
    order by s.ord), '[]'::jsonb)
  into v_out
  from app.meeting_suggestions s where s.transcript_id = t.id and (s.target_id is null or app.mtg_target_ok(s.target_entity, s.target_id));
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'suggestions', 'count', jsonb_array_length(v_out)));
  return jsonb_build_object('transcript_id', t.id, 'suggestions', v_out);
end $fn$;

-- ===========================================================================
-- R-MEETINGS-01: the controls name the controller a notice speaks for
-- ===========================================================================
-- Workspace and controls (§2.6, global:configure): every active staff member with deals:see, their switch, auto-join and mailbox
-- (0042; 0050: controller — app.mtg_controller(), null while no verified transactional sender exists)
create or replace function public.meeting_controls() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'configure');
  perform app.require_module('meetings');
  return jsonb_build_object(
    'users', coalesce((select jsonb_agg(app.mtg_user_row(a.id) order by a.name) from app.admins a where a.active and app.can_for(a.id, 'deals', 'see')), '[]'::jsonb),
    'rec_notice', jsonb_build_object('value', app.setting('rec_notice'), 'hours', app.mtg_notice_hours()),
    'rec_retention', jsonb_build_object('value', app.setting('rec_retention'), 'months', app.mtg_retention_months()),
    'visibility_default', app.mtg_visibility_default(),
    'controller', app.mtg_controller(),
    'capabilities', app.mtg_capabilities());
end $fn$;

-- ===========================================================================
-- grants: internal functions for nobody, the public ones for signed-in staff
-- ===========================================================================
revoke all on function app.mtg_brief_build(uuid) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.shell()', 'public.meeting_transcript(uuid, int, int)', 'public.meeting_suggestions(uuid)', 'public.meeting_controls()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
