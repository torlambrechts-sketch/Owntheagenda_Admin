-- 0011_leads_contacts.sql — leads and their conversion, marketing consent, related organizations,
-- duplicates and merging, imports with revert, and the restore list.
--
-- A person's marketing status changes only through consent_set, which writes the consent ledger with the
-- time, source and basis (CRM-05): rec_save cannot set it. A merge moves every link to the record kept and
-- soft-deletes the other (changelog source «merge»). With the second-admin rule on, a merge or a bulk delete
-- is refused with approval_required until the approvals queue exists (phase 8).

-- ---------------------------------------------------------------------------
create table app.leads (
  id                uuid primary key default gen_random_uuid(),
  title             text not null check (char_length(btrim(title)) between 1 and 200),
  person_id         uuid references app.people (id) on delete set null,
  organization_id   uuid references app.organizations (id) on delete set null,
  value             numeric(14, 2) check (value is null or value >= 0),
  currency          text not null default 'NOK' check (currency ~ '^[A-Z]{3}$'),
  source            text check (source is null or char_length(source) <= 60),
  form_data      jsonb check (form_data is null or jsonb_typeof(form_data) in ('object', 'array')),
  archived_at       timestamptz,
  converted_deal_id uuid references app.deals (id) on delete set null,
  converted_at      timestamptz,
  owner_id          uuid references app.admins (id) on delete set null,
  visibility        text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels            uuid[] not null default '{}',
  custom            jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample         boolean not null default false,
  version           int not null default 1,
  created_at        timestamptz not null default now(),
  created_by        uuid,
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  deleted_at        timestamptz,
  check (person_id is not null or organization_id is not null)
);
create index leads_open on app.leads (created_at desc) where deleted_at is null and archived_at is null;
alter table app.activities add constraint activities_lead foreign key (lead_id) references app.leads (id) on delete set null;

insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('lead', 'leads', 'deals', 'leads', true, 'title', array['source'], array['title', 'source'], 25);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('lead', 'title', 'text', true, true, null, 1),
  ('lead', 'person_id', 'uuid', true, false, 'person', 2),
  ('lead', 'organization_id', 'uuid', true, false, 'organization', 3),
  ('lead', 'value', 'numeric', true, false, null, 4),
  ('lead', 'currency', 'text', true, false, null, 5),
  ('lead', 'source', 'text', true, false, null, 6),
  ('lead', 'form_data', 'jsonb', true, false, null, 7),
  ('lead', 'archived_at', 'timestamptz', true, false, null, 8),
  ('lead', 'converted_deal_id', 'uuid', false, false, 'deal', 9),
  ('lead', 'converted_at', 'timestamptz', false, false, null, 10);
update app.entity_columns set ref = 'lead' where entity = 'activity' and col = 'lead_id';

-- convert a lead to a deal: notes and activities move with it; the lead is archived and points at the deal
create function public.lead_convert(p_lead uuid, p_pipeline uuid, p_stage uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); l app.leads; v_deal uuid; v_labels uuid[];
begin
  perform app.require_module('deals');
  select * into l from app.leads where id = p_lead and deleted_at is null for update;
  if not found or not app.visible(l.owner_id, l.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if l.converted_deal_id is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'converted'; end if;
  -- labels carry over by name where the deal has a label of the same name
  select coalesce(array_agg(dl.id), '{}') into v_labels from app.labels ll join app.labels dl on dl.entity = 'deal' and lower(dl.name) = lower(ll.name)
  where ll.id = any (l.labels);
  v_deal := (public.deal_create(jsonb_build_object('title', l.title, 'value', coalesce(l.value, 0), 'currency', l.currency, 'person_id', l.person_id,
              'organization_id', l.organization_id, 'source', coalesce(l.source, 'Lead'), 'labels', to_jsonb(v_labels), 'owner_id', coalesce(l.owner_id, v_me),
              'pipeline_id', p_pipeline, 'stage_id', p_stage, 'custom', '{}'::jsonb)) ->> 'id')::uuid;
  update app.notes set entity = 'deal', record_id = v_deal where entity = 'lead' and record_id = l.id;
  update app.activities set deal_id = v_deal where lead_id = l.id;
  update app.followers set entity = 'deal', record_id = v_deal where entity = 'lead' and record_id = l.id;
  update app.leads set converted_deal_id = v_deal, converted_at = now(), archived_at = now(), version = version + 1, updated_at = now(), updated_by = v_me where id = l.id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('lead', l.id, '*converted', to_jsonb(v_deal), v_me);
  perform app.log('lead.converted', 'lead', l.id::text, jsonb_build_object('deal', v_deal));
  perform app.emit('lead.converted', 'lead', l.id, jsonb_build_object('deal', v_deal), l.is_sample);
  return jsonb_build_object('deal_id', v_deal);
end $fn$;

-- the lead inbox: next activity per lead
create function public.leads_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('lead');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_rows jsonb;
begin
  v_where := format('where t.deleted_at is null and %s and %s', case when (q ->> 'archived')::boolean then 't.archived_at is not null' else 't.archived_at is null' end, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if btrim(coalesce(q ->> 'q', '')) <> '' then v_where := v_where || format(' and t.title ilike %L', '%' || replace(replace(btrim(q ->> 'q'), '%', '\%'), '_', '\_') || '%'); end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  execute format($q$select coalesce(jsonb_agg(x order by x ->> 'created_at' desc), '[]'::jsonb) from (
      select to_jsonb(t) || jsonb_build_object(
        'person', (select jsonb_build_object('id', p.id, 'name', p.name, 'title', p.title, 'email', p.email) from app.people p where p.id = t.person_id),
        'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'industry', o.industry, 'city', o.city, 'employees', o.employees) from app.organizations o where o.id = t.organization_id),
        'owner', (select jsonb_build_object('name', a.name, 'initials', a.initials) from app.admins a where a.id = t.owner_id),
        'next_activity', (select jsonb_build_object('id', a.id, 'subject', a.subject, 'starts_at', a.starts_at, 'overdue', a.starts_at < now())
                          from app.activities a where a.lead_id = t.id and not a.done and a.deleted_at is null order by a.starts_at nulls last limit 1)) x
      from app.leads t %s) s$q$, v_where) into v_rows;
  perform app.log('record.listed', 'lead', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

-- ---------------------------------------------------------------------------
-- marketing consent (the ledger is append-only: nobody may change its content)
alter table app.people add column marketing_status text not null default 'no_consent'
  check (marketing_status in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced'));
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values ('person', 'marketing_status', 'text', false, false, null, 12);

create table app.consent_events (
  id         bigint generated always as identity primary key,
  person_id  uuid references app.people (id) on delete cascade,
  status     text not null check (status in ('subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced')),
  source     text not null check (char_length(source) between 1 and 60),
  basis      text check (basis is null or char_length(basis) <= 200),
  actor_id   uuid,
  at         timestamptz not null default now()
);
create index consent_events_person on app.consent_events (person_id, at desc);

create function app.consent_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  -- a cascade from a deleted person (erasure) may remove rows; nothing else may change or remove them
  if tg_op = 'DELETE' and not exists (select 1 from app.people where id = old.person_id) then return old; end if;
  raise exception 'the consent ledger is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger consent_fixed before update or delete on app.consent_events for each row execute function app.consent_fixed();

create function public.consent_set(p_person uuid, p_status text, p_source text, p_basis text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); p app.people;
begin
  select * into p from app.people where id = p_person and deleted_at is null for update;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p.owner_id is distinct from v_me and not app.can('deals', 'edit_others') and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  if app.setting('contact_rule') <> 'no_rule' and p_status = 'subscribed' and coalesce(btrim(p_basis), '') = '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'basis:required';
  end if;
  insert into app.consent_events (person_id, status, source, basis, actor_id) values (p_person, p_status, btrim(p_source), nullif(btrim(p_basis), ''), v_me);
  update app.people set marketing_status = p_status, version = version + 1, updated_at = now(), updated_by = v_me where id = p_person;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id) values ('person', p_person, 'marketing_status', to_jsonb(p.marketing_status), to_jsonb(p_status), v_me);
  perform app.log('consent.changed', 'person', p_person::text, jsonb_build_object('from', p.marketing_status, 'to', p_status, 'source', btrim(p_source)));
  perform app.emit('consent.changed', 'person', p_person, jsonb_build_object('status', p_status), p.is_sample);
  return jsonb_build_object('status', p_status);
end $fn$;

create function public.consent_history(p_person uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare p app.people;
begin
  perform app.require('deals', 'see');
  select * into p from app.people where id = p_person;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('status', c.status, 'source', c.source, 'basis', c.basis, 'at', c.at, 'actor', a.name) order by c.at desc)
                   from app.consent_events c left join app.admins a on a.id = c.actor_id where c.person_id = p_person), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- related organizations (parent and daughter are organizations.parent_id)
create table app.organization_relations (
  a_id       uuid not null references app.organizations (id) on delete cascade,
  b_id       uuid not null references app.organizations (id) on delete cascade,
  note       text check (note is null or char_length(note) <= 200),
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (a_id, b_id),
  check (a_id < b_id)
);

create function public.org_relation_set(p_a uuid, p_b uuid, p_kind text, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  if p_a = p_b then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'self'; end if;
  case p_kind
    when 'parent' then perform public.rec_save('organization', p_a, jsonb_build_object('parent_id', p_b));
    when 'daughter' then perform public.rec_save('organization', p_b, jsonb_build_object('parent_id', p_a));
    when 'related' then insert into app.organization_relations (a_id, b_id, note, created_by) values (least(p_a, p_b), greatest(p_a, p_b), p_note, v_me) on conflict do nothing;
    when 'none' then delete from app.organization_relations where a_id = least(p_a, p_b) and b_id = greatest(p_a, p_b);
    else raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind';
  end case;
  perform app.log('organization.related', 'organization', p_a::text, jsonb_build_object('other', p_b, 'kind', p_kind));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.org_relations(p_org uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); o app.organizations;
begin
  select * into o from app.organizations where id = p_org;
  if not found or not app.visible(o.owner_id, o.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object(
    'parent', (select jsonb_build_object('id', x.id, 'name', x.name) from app.organizations x where x.id = o.parent_id and x.deleted_at is null),
    'daughters', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name)) from app.organizations x where x.parent_id = o.id and x.deleted_at is null), '[]'::jsonb),
    'related', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'note', r.note)) from app.organization_relations r
                         join app.organizations x on x.id = case when r.a_id = o.id then r.b_id else r.a_id end
                         where (r.a_id = o.id or r.b_id = o.id) and x.deleted_at is null), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
-- duplicates: rules in the register, candidates found by a scan, merged or dismissed by a person
create extension if not exists pg_trgm with schema extensions;

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, ord) values
  ('dedupe_name', 'duplicates', array['on', 'off'], 'on', 'platform', 'CRM-11', 500),
  ('dedupe_email', 'duplicates', array['on', 'off'], 'on', 'platform', 'CRM-11', 510),
  ('dedupe_orgnr', 'duplicates', array['on', 'off'], 'on', 'platform', 'CRM-11', 520),
  ('dedupe_phone', 'duplicates', array['off', 'on'], 'off', 'platform', 'CRM-11', 530);

create table app.duplicate_candidates (
  id         uuid primary key default gen_random_uuid(),
  entity     text not null check (entity in ('person', 'organization')),
  keep_id    uuid not null,
  merge_id   uuid not null,
  rule       text not null check (rule in ('name', 'email', 'orgnr', 'phone')),
  score      numeric(4, 3),
  status     text not null default 'open' check (status in ('open', 'merged', 'dismissed')),
  decided_by uuid,
  decided_at timestamptz,
  found_at   timestamptz not null default now(),
  unique (entity, keep_id, merge_id)
);

create function app.duplicates_scan() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int := 0; k int;
begin
  if app.setting('dedupe_email') = 'on' then
    insert into app.duplicate_candidates (entity, keep_id, merge_id, rule, score)
    select 'person', a.id, b.id, 'email', 1 from app.people a join app.people b on lower(a.email) = lower(b.email) and a.id < b.id
    where a.deleted_at is null and b.deleted_at is null and a.email is not null and a.is_sample = b.is_sample on conflict do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if app.setting('dedupe_phone') = 'on' then
    insert into app.duplicate_candidates (entity, keep_id, merge_id, rule, score)
    select 'person', a.id, b.id, 'phone', 1 from app.people a join app.people b
      on regexp_replace(a.phone, '\D', '', 'g') = regexp_replace(b.phone, '\D', '', 'g') and a.id < b.id
    where a.deleted_at is null and b.deleted_at is null and length(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g')) >= 8 and a.is_sample = b.is_sample on conflict do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if app.setting('dedupe_orgnr') = 'on' then
    insert into app.duplicate_candidates (entity, keep_id, merge_id, rule, score)
    select 'organization', a.id, b.id, 'orgnr', 1 from app.organizations a join app.organizations b on a.org_number = b.org_number and a.id < b.id
    where a.deleted_at is null and b.deleted_at is null and a.is_sample = b.is_sample on conflict do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if app.setting('dedupe_name') = 'on' then
    insert into app.duplicate_candidates (entity, keep_id, merge_id, rule, score)
    select 'person', a.id, b.id, 'name', round(extensions.similarity(lower(a.name), lower(b.name))::numeric, 3)
    from app.people a join app.people b on a.id < b.id and extensions.similarity(lower(a.name), lower(b.name)) >= 0.9
    where a.deleted_at is null and b.deleted_at is null and a.is_sample = b.is_sample on conflict do nothing;
    get diagnostics k = row_count; n := n + k;
    insert into app.duplicate_candidates (entity, keep_id, merge_id, rule, score)
    select 'organization', a.id, b.id, 'name', round(extensions.similarity(lower(a.name), lower(b.name))::numeric, 3)
    from app.organizations a join app.organizations b on a.id < b.id and extensions.similarity(lower(a.name), lower(b.name)) >= 0.9
    where a.deleted_at is null and b.deleted_at is null and a.is_sample = b.is_sample on conflict do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end $fn$;
select cron.schedule('platform-duplicates', '23 2 * * *', 'select app.duplicates_scan()');

create function public.duplicates_get(p_scan boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  if p_scan then perform app.duplicates_scan(); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'entity', c.entity, 'rule', c.rule, 'score', c.score, 'found_at', c.found_at,
      'keep', case c.entity when 'person' then (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email, 'phone', p.phone, 'organization', (select name from app.organizations where id = p.organization_id), 'updated_at', p.updated_at) from app.people p where p.id = c.keep_id)
                            else (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'city', o.city, 'updated_at', o.updated_at) from app.organizations o where o.id = c.keep_id) end,
      'merge', case c.entity when 'person' then (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email, 'phone', p.phone, 'organization', (select name from app.organizations where id = p.organization_id), 'updated_at', p.updated_at) from app.people p where p.id = c.merge_id)
                            else (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number, 'city', o.city, 'updated_at', o.updated_at) from app.organizations o where o.id = c.merge_id) end)
    order by c.found_at desc)
    from app.duplicate_candidates c where c.status = 'open'
      and exists (select 1 from app.people p where p.id = c.keep_id and p.deleted_at is null and app.visible(p.owner_id, p.visibility) union all
                  select 1 from app.organizations o where o.id = c.keep_id and o.deleted_at is null and app.visible(o.owner_id, o.visibility))), '[]'::jsonb);
end $fn$;

create function public.duplicate_dismiss(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  update app.duplicate_candidates set status = 'dismissed', decided_by = app.require('deals', 'see'), decided_at = now() where id = p_id and status = 'open';
  perform app.log('duplicate.dismissed', 'duplicate', p_id::text);
  return jsonb_build_object('ok', found);
end $fn$;

-- merge two people or two organizations: links move to the kept record, chosen values are applied, the
-- other is soft-deleted (restorable for 30 days)
create function public.records_merge(p_entity text, p_keep uuid, p_merge uuid, p_values jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'bulk');
begin
  if p_entity not in ('person', 'organization') or p_keep = p_merge then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity'; end if;
  if app.setting('second_admin') = 'on' then raise exception 'approval_required' using errcode = 'insufficient_privilege'; end if;
  perform public.rec_get(p_entity, p_keep); perform public.rec_get(p_entity, p_merge);   -- both visible
  if p_entity = 'person' then
    update app.deals set person_id = p_keep where person_id = p_merge;
    update app.leads set person_id = p_keep where person_id = p_merge;
    update app.activities set person_id = p_keep where person_id = p_merge;
    update app.activity_guests set person_id = p_keep where person_id = p_merge;
    insert into app.deal_participants (deal_id, person_id, added_by) select deal_id, p_keep, added_by from app.deal_participants where person_id = p_merge on conflict do nothing;
    delete from app.deal_participants where person_id = p_merge;
    update app.people k set labels = array(select distinct x from unnest(k.labels || m.labels) x), custom = m.custom || k.custom,
      email = coalesce(k.email, m.email), phone = coalesce(k.phone, m.phone), organization_id = coalesce(k.organization_id, m.organization_id),
      title = coalesce(k.title, m.title)
    from app.people m where k.id = p_keep and m.id = p_merge;
  else
    update app.people set organization_id = p_keep where organization_id = p_merge;
    update app.deals set organization_id = p_keep where organization_id = p_merge;
    update app.leads set organization_id = p_keep where organization_id = p_merge;
    update app.activities set organization_id = p_keep where organization_id = p_merge;
    update app.organizations set parent_id = p_keep where parent_id = p_merge;
    update app.organizations k set labels = array(select distinct x from unnest(k.labels || m.labels) x), custom = m.custom || k.custom,
      org_number = coalesce(k.org_number, m.org_number), account_id = coalesce(k.account_id, m.account_id), address = coalesce(k.address, m.address),
      city = coalesce(k.city, m.city), phone = coalesce(k.phone, m.phone), email = coalesce(k.email, m.email)
    from app.organizations m where k.id = p_keep and m.id = p_merge;
  end if;
  update app.notes set record_id = p_keep where entity = p_entity and record_id = p_merge;
  insert into app.followers (entity, record_id, staff_id) select entity, p_keep, staff_id from app.followers where entity = p_entity and record_id = p_merge on conflict do nothing;
  delete from app.followers where entity = p_entity and record_id = p_merge;
  if p_values is not null and p_values <> '{}'::jsonb then perform public.rec_save(p_entity, p_keep, p_values, null, null, 'ui'); end if;
  execute format('update app.%I set deleted_at = now(), updated_at = now(), updated_by = %L, version = version + 1 where id = %L',
                 case p_entity when 'person' then 'people' else 'organizations' end, v_me, p_merge);
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values
    (p_entity, p_keep, '*merged', jsonb_build_object('merged', p_merge), v_me, 'merge'),
    (p_entity, p_merge, '*deleted', jsonb_build_object('merged_into', p_keep), v_me, 'merge');
  update app.duplicate_candidates set status = 'merged', decided_by = v_me, decided_at = now()
  where entity = p_entity and status = 'open' and (keep_id in (p_keep, p_merge) or merge_id in (p_keep, p_merge));
  perform app.log('record.merged', p_entity, p_keep::text, jsonb_build_object('merged', p_merge));
  perform app.emit(p_entity || '.merged', p_entity, p_keep, jsonb_build_object('merged', p_merge));
  return jsonb_build_object('kept', p_keep);
end $fn$;

-- ---------------------------------------------------------------------------
-- imports: rows already parsed and mapped by the app; every row is accounted for, and an import can be
-- reverted (created records deleted, updated records given back their earlier values)
create table app.imports (
  id              uuid primary key default gen_random_uuid(),
  entity          text not null check (entity in ('person', 'organization', 'lead', 'deal')),
  file_name       text check (file_name is null or char_length(file_name) <= 200),
  mapping         jsonb not null default '{}'::jsonb,
  dup_mode        text not null check (dup_mode in ('merge', 'create', 'skip')),
  require_consent boolean not null default false,
  rows_read       int not null default 0,
  created         int not null default 0,
  merged          int not null default 0,
  skipped         int not null default 0,
  status          text not null default 'done' check (status in ('done', 'reverted')),
  staff_id        uuid,
  created_at      timestamptz not null default now(),
  reverted_at     timestamptz
);

create table app.import_rows (
  import_id uuid not null references app.imports (id) on delete cascade,
  row_no    int not null,
  outcome   text not null check (outcome in ('created', 'merged', 'skipped')),
  reason    text,
  record_id uuid,
  before    jsonb,
  primary key (import_id, row_no)
);

create function public.import_run(p_entity text, p_rows jsonb, p_dup_mode text, p_file text default null, p_mapping jsonb default '{}'::jsonb, p_require_consent boolean default false)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'add');
  v_import uuid; r jsonb; i int := 0; v_match uuid; v_id uuid; v_before jsonb; v_err text;
  c_created int := 0; c_merged int := 0; c_skipped int := 0;
begin
  if p_entity not in ('person', 'organization', 'lead', 'deal') or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 50000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'rows';
  end if;
  if app.setting('import_consent') = 'required_per_row' then p_require_consent := true; end if;
  insert into app.imports (entity, file_name, mapping, dup_mode, require_consent, staff_id) values (p_entity, p_file, coalesce(p_mapping, '{}'::jsonb), p_dup_mode, p_require_consent, v_me)
  returning id into v_import;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; v_match := null; v_before := null;
    if p_require_consent and p_entity = 'person' and coalesce(btrim(r ->> '_consent_source'), '') = '' then
      insert into app.import_rows values (v_import, i, 'skipped', 'consent_source_missing', null, null); c_skipped := c_skipped + 1; continue;
    end if;
    if p_entity = 'person' and coalesce(r ->> 'email', '') <> '' then
      select id into v_match from app.people where lower(email) = lower(btrim(r ->> 'email')) and deleted_at is null and app.visible(owner_id, visibility) limit 1;
    elsif p_entity = 'organization' and coalesce(r ->> 'org_number', '') <> '' then
      select id into v_match from app.organizations where org_number = regexp_replace(r ->> 'org_number', '\D', '', 'g') and deleted_at is null and app.visible(owner_id, visibility) limit 1;
    end if;
    if p_entity = 'organization' and r ? 'org_number' then r := jsonb_set(r, '{org_number}', to_jsonb(nullif(regexp_replace(r ->> 'org_number', '\D', '', 'g'), ''))); end if;
    begin
      if v_match is not null and p_dup_mode = 'skip' then
        insert into app.import_rows values (v_import, i, 'skipped', 'duplicate', v_match, null); c_skipped := c_skipped + 1;
      elsif v_match is not null and p_dup_mode = 'merge' then
        execute format('select to_jsonb(t) from app.%I t where id = %L', case p_entity when 'person' then 'people' else 'organizations' end, v_match) into v_before;
        perform public.rec_save(p_entity, v_match, jsonb_strip_nulls(r - '_consent_source' - '_consent_basis'), null, null, 'import');
        insert into app.import_rows values (v_import, i, 'merged', null, v_match, v_before); c_merged := c_merged + 1;
      else
        if p_entity = 'deal' then v_id := (public.deal_create(jsonb_strip_nulls(r)) ->> 'id')::uuid;
        else v_id := (public.rec_save(p_entity, null, jsonb_strip_nulls(r - '_consent_source' - '_consent_basis'), null, null, 'import') ->> 'id')::uuid; end if;
        if p_entity = 'person' and coalesce(r ->> '_consent_source', '') <> '' then
          insert into app.consent_events (person_id, status, source, basis, actor_id) values (v_id, 'subscribed', left(r ->> '_consent_source', 60), left(r ->> '_consent_basis', 200), v_me);
          update app.people set marketing_status = 'subscribed' where id = v_id;
        end if;
        insert into app.import_rows values (v_import, i, 'created', null, v_id, null); c_created := c_created + 1;
      end if;
    exception when others then
      get stacked diagnostics v_err = message_text;
      insert into app.import_rows values (v_import, i, 'skipped', left(v_err, 60), null, null); c_skipped := c_skipped + 1;
    end;
  end loop;
  update app.imports set rows_read = i, created = c_created, merged = c_merged, skipped = c_skipped where id = v_import;
  perform app.log('import.completed', p_entity, v_import::text, jsonb_build_object('rows', i, 'created', c_created, 'merged', c_merged, 'skipped', c_skipped));
  return jsonb_build_object('id', v_import, 'rows_read', i, 'created', c_created, 'merged', c_merged, 'skipped', c_skipped);
end $fn$;

create function public.import_revert(p_import uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'delete'); im app.imports; r record; v_tbl text;
begin
  select * into im from app.imports where id = p_import and status = 'done' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_tbl := (select tbl from app.entities where key = im.entity);
  for r in select * from app.import_rows where import_id = p_import and outcome in ('created', 'merged') loop
    if r.outcome = 'created' then
      execute format('update app.%I set deleted_at = now(), updated_by = %L where id = %L and deleted_at is null', v_tbl, v_me, r.record_id);
    else
      execute format('update app.%I t set (%s) = (select %s from jsonb_populate_record(null::app.%I, %L) x) where t.id = %L', v_tbl,
        (select string_agg(format('%I', k), ', ') from jsonb_object_keys(r.before) k where k not in ('id', 'created_at', 'created_by')),
        (select string_agg(format('x.%I', k), ', ') from jsonb_object_keys(r.before) k where k not in ('id', 'created_at', 'created_by')),
        v_tbl, r.before::text, r.record_id);
    end if;
  end loop;
  update app.imports set status = 'reverted', reverted_at = now() where id = p_import;
  perform app.log('import.reverted', im.entity, p_import::text);
  return jsonb_build_object('ok', true);
end $fn$;

create function public.imports_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  return coalesce((select jsonb_agg(to_jsonb(i) || jsonb_build_object('by', (select name from app.admins where id = i.staff_id)) order by i.created_at desc)
                   from (select * from app.imports order by created_at desc limit 50) i), '[]'::jsonb);
end $fn$;

create function public.import_skips(p_import uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'see');
  return coalesce((select jsonb_agg(jsonb_build_object('row', row_no, 'reason', reason) order by row_no) from app.import_rows where import_id = p_import and outcome = 'skipped'), '[]'::jsonb);
end $fn$;

-- an export is the visible rows of a list; the app builds the file, this records it (SEC-02)
create function public.export_log(p_entity text, p_rows int, p_format text, p_scope text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity);
begin
  perform app.require(e.scope, 'export');
  perform app.log('record.exported', e.key, null, jsonb_build_object('rows', p_rows, 'format', p_format, 'scope', p_scope));
  perform app.emit('export.created', e.key, null, jsonb_build_object('rows', p_rows, 'format', p_format));
  return jsonb_build_object('ok', true);
end $fn$;

-- deleted records across the record types, restorable for 30 days
create function public.deleted_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); e app.entities; v jsonb; v_out jsonb := '[]'::jsonb;
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
begin
  for e in select * from app.entities en where app.can(en.scope, 'delete') and (en.module is null or app.module_on(en.module)) order by en.ord loop
    execute format($q$select coalesce(jsonb_agg(jsonb_build_object('entity', %L, 'id', t.id, 'title', t.%I::text, 'deleted_at', t.deleted_at,
                       'by', (select name from app.admins a where a.id = t.updated_by),
                       'source', (select c.source from app.changelog c where c.entity = %L and c.record_id = t.id and c.field = '*deleted' order by c.id desc limit 1),
                       'purge_at', t.deleted_at + interval '30 days')), '[]'::jsonb)
                   from app.%I t where t.deleted_at > now() - interval '30 days' and %s %s$q$,
                   e.key, e.title_col, e.key, e.tbl, app.vis_sql(e), case when v_sandbox then '' else 'and not t.is_sample' end) into v;
    v_out := v_out || v;
  end loop;
  return coalesce((select jsonb_agg(x order by x ->> 'deleted_at' desc) from jsonb_array_elements(v_out) x), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['leads', 'consent_events', 'organization_relations', 'duplicate_candidates', 'imports', 'import_rows'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.consent_fixed()', 'app.duplicates_scan()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.lead_convert(uuid, uuid, uuid)', 'public.leads_get(jsonb)', 'public.consent_set(uuid, text, text, text)', 'public.consent_history(uuid)',
                           'public.org_relation_set(uuid, uuid, text, text)', 'public.org_relations(uuid)', 'public.duplicates_get(boolean)', 'public.duplicate_dismiss(uuid)',
                           'public.records_merge(text, uuid, uuid, jsonb)', 'public.import_run(text, jsonb, text, text, jsonb, boolean)', 'public.import_revert(uuid)',
                           'public.imports_get()', 'public.import_skips(uuid)', 'public.export_log(text, int, text, text)', 'public.deleted_get()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
