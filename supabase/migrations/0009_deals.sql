-- 0009_deals.sql — pipelines, stages, deals, the sales catalog, and the generic parts every record uses:
-- notes, followers, saved views.
--
-- A deal's stage and status change only through deal_move / deal_status (they keep the stage history, check
-- the fields required from a stage, and emit deal.stage_changed / deal.won / deal.lost); every other field
-- goes through rec_save. Rotting and the activity state on a card are derived, never stored: a deal rots when
-- it has been idle longer than its stage's threshold. The deal score waits for the scoring model (phase 4):
-- until then it is null and the screen leaves it out.

-- ---------------------------------------------------------------------------
-- pipelines and stages (Settings › Pipelines and stages)
create table app.pipelines (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null check (char_length(btrim(name)) between 1 and 80),
  ord                  int not null default 0,
  visibility_group_ids uuid[],                             -- null: every staff member
  card_fields          text[] not null default array['organization', 'value', 'close', 'score'],
  archived_at          timestamptz,
  is_sample            boolean not null default false,
  created_at           timestamptz not null default now(),
  check (card_fields <@ array['organization', 'value', 'close', 'score', 'person', 'owner', 'labels'])
);

create table app.stages (
  id          uuid primary key default gen_random_uuid(),
  pipeline_id uuid not null references app.pipelines (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  ord         int not null default 0,
  probability smallint not null default 0 check (probability between 0 and 100),
  rot_days    int check (rot_days is null or rot_days > 0),
  created_at  timestamptz not null default now()
);
create index stages_pipeline on app.stages (pipeline_id, ord);

-- custom fields can be required from a stage
alter table app.fields add constraint fields_from_stage foreign key (from_stage_id) references app.stages (id) on delete set null;

create table app.lost_reasons (
  id     uuid primary key default gen_random_uuid(),
  label  text not null unique check (char_length(btrim(label)) between 1 and 60),
  ord    int not null default 0,
  active boolean not null default true
);
insert into app.lost_reasons (label, ord) values ('Price', 10), ('Timing', 20), ('Competitor', 30), ('No decision', 40), ('Product fit', 50), ('Other', 60);

insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, ord) values
  ('lost_reason_required', 'pipelines', array['off', 'on'], 'off', 'platform', 'PIP-07', 400),
  ('deal_capacity', 'pipelines', array['unlimited', 'number'], 'unlimited', 'platform', 'PIP-16', 410);
update app.settings_registry set numeric_option = 'number' where key = 'deal_capacity';

-- ---------------------------------------------------------------------------
-- the sales catalog (D-25: catalog_items, not products, which are the applications)
create table app.catalog_items (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(btrim(name)) between 1 and 120),
  code              text check (code is null or char_length(code) <= 40),
  unit              text check (unit is null or char_length(unit) <= 30),
  tax_rate          numeric(5, 2) not null default 25 check (tax_rate between 0 and 100),
  billing           text not null default 'one_off' check (billing in ('one_off', 'recurring', 'installments')),
  billing_frequency text check (billing_frequency is null or billing_frequency in ('monthly', 'quarterly', 'semiannual', 'annual')),
  color             text check (color is null or color ~ '^#[0-9A-F]{6}$'),
  description       text check (description is null or char_length(description) <= 1000),
  product           text references app.products (key),      -- the application it belongs to, if any
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
  deleted_at        timestamptz
);
create unique index catalog_items_code on app.catalog_items (code) where deleted_at is null and code is not null and not is_sample;

create table app.catalog_prices (
  item_id    uuid not null references app.catalog_items (id) on delete cascade,
  currency   text not null check (currency ~ '^[A-Z]{3}$'),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  primary key (item_id, currency)
);

-- ---------------------------------------------------------------------------
-- deals
create table app.deals (
  id                  uuid primary key default gen_random_uuid(),
  seq                 bigint generated always as identity unique,
  title               text not null check (char_length(btrim(title)) between 1 and 200),
  value               numeric(14, 2) not null default 0 check (value >= 0),
  currency            text not null default 'NOK' check (currency ~ '^[A-Z]{3}$'),
  value_source        text not null default 'manual' check (value_source in ('manual', 'items')),
  pipeline_id         uuid not null references app.pipelines (id),
  stage_id            uuid not null references app.stages (id),
  stage_entered_at    timestamptz not null default now(),
  status              text not null default 'open' check (status in ('open', 'won', 'lost')),
  won_at              timestamptz,
  lost_at             timestamptz,
  closed_by           uuid references app.admins (id) on delete set null,
  lost_reason         text check (lost_reason is null or char_length(lost_reason) <= 200),
  person_id           uuid references app.people (id) on delete set null,
  organization_id     uuid references app.organizations (id) on delete set null,
  expected_close_date date,
  source              text check (source is null or char_length(source) <= 60),
  product             text references app.products (key),
  last_activity_at    timestamptz,
  score               smallint check (score is null or score between 0 and 100),
  score_breakdown     jsonb,
  archived_at         timestamptz,
  owner_id            uuid references app.admins (id) on delete set null,
  visibility          text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels              uuid[] not null default '{}',
  custom              jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample           boolean not null default false,
  version             int not null default 1,
  created_at          timestamptz not null default now(),
  created_by          uuid,
  updated_at          timestamptz not null default now(),
  updated_by          uuid,
  deleted_at          timestamptz
);
create index deals_stage on app.deals (stage_id) where deleted_at is null;
create index deals_org on app.deals (organization_id);
create index deals_person on app.deals (person_id);

-- a deal's stage must belong to its pipeline
create function app.deal_stage_ok() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if not exists (select 1 from app.stages s where s.id = new.stage_id and s.pipeline_id = new.pipeline_id) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage_id';
  end if;
  return new;
end $fn$;
create trigger deal_stage_ok before insert or update of stage_id, pipeline_id on app.deals for each row execute function app.deal_stage_ok();

create table app.deal_stage_history (
  id         bigint generated always as identity primary key,
  deal_id    uuid not null references app.deals (id) on delete cascade,
  stage_id   uuid references app.stages (id) on delete set null,
  entered_at timestamptz not null,
  left_at    timestamptz,
  moved_by   uuid,
  source     text not null default 'ui'
);
create index deal_stage_history_deal on app.deal_stage_history (deal_id, entered_at);

create table app.deal_participants (
  deal_id   uuid not null references app.deals (id) on delete cascade,
  person_id uuid not null references app.people (id) on delete cascade,
  added_by  uuid,
  added_at  timestamptz not null default now(),
  primary key (deal_id, person_id)
);

create table app.deal_items (
  id                uuid primary key default gen_random_uuid(),
  deal_id           uuid not null references app.deals (id) on delete cascade,
  item_id           uuid references app.catalog_items (id) on delete set null,
  name              text not null check (char_length(btrim(name)) between 1 and 120),
  quantity          numeric(12, 2) not null default 1 check (quantity > 0),
  unit_price        numeric(14, 2) not null default 0 check (unit_price >= 0),
  discount_pct      numeric(5, 2) not null default 0 check (discount_pct between 0 and 100),
  tax_rate          numeric(5, 2) not null default 25 check (tax_rate between 0 and 100),
  billing           text not null default 'one_off' check (billing in ('one_off', 'recurring', 'installments')),
  billing_frequency text check (billing_frequency is null or billing_frequency in ('monthly', 'quarterly', 'semiannual', 'annual')),
  cycles            int check (cycles is null or cycles between 1 and 208),   -- null: until cancelled
  ord               int not null default 0
);
create index deal_items_deal on app.deal_items (deal_id, ord);

-- ---------------------------------------------------------------------------
-- generic: notes, followers, saved views
create table app.notes (
  id         uuid primary key default gen_random_uuid(),
  entity     text not null references app.entities (key) on delete cascade,
  record_id  uuid not null,
  body       text not null check (char_length(btrim(body)) between 1 and 10000),
  pinned     boolean not null default false,
  mentions   uuid[] not null default '{}',
  parent_id  uuid references app.notes (id) on delete cascade,
  author_id  uuid references app.admins (id) on delete set null,
  is_sample  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index notes_record on app.notes (entity, record_id, created_at desc);

create table app.followers (
  entity     text not null references app.entities (key) on delete cascade,
  record_id  uuid not null,
  staff_id   uuid not null references app.admins (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (entity, record_id, staff_id)
);

create table app.saved_views (
  id         uuid primary key default gen_random_uuid(),
  screen     text not null check (screen ~ '^[a-z_]{2,40}$'),
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  query      jsonb not null default '{}'::jsonb check (jsonb_typeof(query) = 'object'),
  owner_id   uuid references app.admins (id) on delete cascade,
  shared     boolean not null default false,
  ord        int not null default 0,
  created_at timestamptz not null default now()
);

-- per-staff view preferences (columns, sort, show won and lost, calendar mode …); staff_id null = default
create table app.view_prefs (
  staff_id   uuid references app.admins (id) on delete cascade,
  screen     text not null check (screen ~ '^[a-z_]{2,40}$'),
  key        text not null check (key ~ '^[a-z_]{2,40}$'),
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
create unique index view_prefs_key on app.view_prefs (coalesce(staff_id, '00000000-0000-0000-0000-000000000000'::uuid), screen, key);

-- ---------------------------------------------------------------------------
-- registry
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('deal', 'deals', 'deals', 'deals', true, 'title', array['status', 'source'], array['title', 'source'], 30),
  ('catalog_item', 'catalog_items', 'deals', 'deals', true, 'name', array['code', 'unit'], array['name', 'code'], 60);

insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('deal', 'title', 'text', true, true, null, 1),
  ('deal', 'value', 'numeric', true, false, null, 2),
  ('deal', 'currency', 'text', true, false, null, 3),
  ('deal', 'value_source', 'text', true, false, null, 4),
  ('deal', 'pipeline_id', 'uuid', false, false, null, 5),
  ('deal', 'stage_id', 'uuid', false, false, null, 6),
  ('deal', 'status', 'text', false, false, null, 7),
  ('deal', 'person_id', 'uuid', true, false, 'person', 8),
  ('deal', 'organization_id', 'uuid', true, false, 'organization', 9),
  ('deal', 'expected_close_date', 'date', true, false, null, 10),
  ('deal', 'source', 'text', true, false, null, 11),
  ('deal', 'product', 'text', true, false, null, 12),
  ('deal', 'last_activity_at', 'timestamptz', false, false, null, 13),
  ('deal', 'score', 'int', false, false, null, 14),
  ('deal', 'archived_at', 'timestamptz', false, false, null, 15),
  ('deal', 'won_at', 'timestamptz', false, false, null, 16),
  ('deal', 'lost_at', 'timestamptz', false, false, null, 17),
  ('deal', 'lost_reason', 'text', false, false, null, 18),
  ('deal', 'stage_entered_at', 'timestamptz', false, false, null, 19),
  ('deal', 'seq', 'int', false, false, null, 20),
  ('catalog_item', 'name', 'text', true, true, null, 1),
  ('catalog_item', 'code', 'text', true, false, null, 2),
  ('catalog_item', 'unit', 'text', true, false, null, 3),
  ('catalog_item', 'tax_rate', 'numeric', true, false, null, 4),
  ('catalog_item', 'billing', 'text', true, false, null, 5),
  ('catalog_item', 'billing_frequency', 'text', true, false, null, 6),
  ('catalog_item', 'color', 'text', true, false, null, 7),
  ('catalog_item', 'description', 'text', true, false, null, 8),
  ('catalog_item', 'product', 'text', true, false, null, 9);

-- ---------------------------------------------------------------------------
-- pipelines: read and configure
create function app.pipeline_visible(p_pipeline uuid) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select p.visibility_group_ids is null
                      or (select group_id from app.admins where id = app.me()) = any (p.visibility_group_ids)
                      or app.can('deals', 'configure')
                   from app.pipelines p where p.id = p_pipeline), false)
$fn$;

create function public.pipelines_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
begin
  perform app.require_module('deals');
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'ord', p.ord, 'card_fields', to_jsonb(p.card_fields),
      'visibility_group_ids', to_jsonb(p.visibility_group_ids),
      'stages', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'ord', s.ord, 'probability', s.probability, 'rot_days', s.rot_days,
                                  'open_deals', (select count(*) from app.deals d where d.stage_id = s.id and d.status = 'open' and d.deleted_at is null and (v_sandbox or not d.is_sample)))
                                order by s.ord, s.created_at) from app.stages s where s.pipeline_id = p.id), '[]'::jsonb))
    order by p.ord, p.created_at)
    from app.pipelines p where p.archived_at is null and app.pipeline_visible(p.id) and (v_sandbox or not p.is_sample)), '[]'::jsonb);
end $fn$;

create function public.pipeline_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; v_sandbox boolean;
begin
  perform app.require('deals', 'configure');
  v_sandbox := (select sandbox from app.admins where id = app.me());
  if p_id is null then
    insert into app.pipelines (name, ord, is_sample) values (btrim(p_values ->> 'name'),
      coalesce((p_values ->> 'ord')::int, (select coalesce(max(ord), 0) + 10 from app.pipelines)), v_sandbox) returning id into v_id;
  else
    update app.pipelines set
      name = coalesce(nullif(btrim(p_values ->> 'name'), ''), name),
      ord = coalesce((p_values ->> 'ord')::int, ord),
      card_fields = case when p_values ? 'card_fields' then array(select jsonb_array_elements_text(p_values -> 'card_fields')) else card_fields end,
      visibility_group_ids = case when p_values ? 'visibility_group_ids' then
          case when jsonb_typeof(p_values -> 'visibility_group_ids') = 'array' then array(select jsonb_array_elements_text(p_values -> 'visibility_group_ids'))::uuid[] end
        else visibility_group_ids end,
      archived_at = case when (p_values ->> 'archived')::boolean then now() when p_values ? 'archived' then null else archived_at end
    where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('pipeline.saved', 'pipeline', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.stage_save(p_id uuid, p_pipeline uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid;
begin
  perform app.require('deals', 'configure');
  if p_id is null then
    insert into app.stages (pipeline_id, name, ord, probability, rot_days)
    values (p_pipeline, btrim(p_values ->> 'name'), coalesce((p_values ->> 'ord')::int, (select coalesce(max(ord), 0) + 10 from app.stages where pipeline_id = p_pipeline)),
            coalesce((p_values ->> 'probability')::smallint, 0), nullif(p_values ->> 'rot_days', '')::int)
    returning id into v_id;
  else
    update app.stages set
      name = coalesce(nullif(btrim(p_values ->> 'name'), ''), name),
      probability = coalesce((p_values ->> 'probability')::smallint, probability),
      rot_days = case when p_values ? 'rot_days' then nullif(p_values ->> 'rot_days', '')::int else rot_days end
    where id = p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('stage.saved', 'stage', v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.stages_reorder(p_pipeline uuid, p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'configure');
  if (select count(*) from app.stages where pipeline_id = p_pipeline) <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) x where not exists (select 1 from app.stages s where s.id = x and s.pipeline_id = p_pipeline)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids';
  end if;
  update app.stages s set ord = x.n * 10 from unnest(p_ids) with ordinality x(id, n) where s.id = x.id;
  perform app.log('stage.reordered', 'pipeline', p_pipeline::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- deleting a stage moves its deals to a target stage of the same pipeline first (PIP-02)
create function public.stage_delete(p_stage uuid, p_target uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'configure'); v_pipeline uuid; n int := 0; d record;
begin
  select pipeline_id into v_pipeline from app.stages where id = p_stage;
  if v_pipeline is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_target is null or p_target = p_stage or not exists (select 1 from app.stages where id = p_target and pipeline_id = v_pipeline) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'target';
  end if;
  for d in select id from app.deals where stage_id = p_stage loop
    update app.deal_stage_history set left_at = now() where deal_id = d.id and left_at is null;
    insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by, source) values (d.id, p_target, now(), v_me, 'system');
    update app.deals set stage_id = p_target, stage_entered_at = now(), version = version + 1, updated_at = now(), updated_by = v_me where id = d.id;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
    values ('deal', d.id, 'stage_id', to_jsonb(p_stage), to_jsonb(p_target), v_me, 'system');
    perform app.emit('deal.stage_changed', 'deal', d.id, jsonb_build_object('from', p_stage, 'to', p_target));
    n := n + 1;
  end loop;
  update app.fields set from_stage_id = null where from_stage_id = p_stage;
  delete from app.stages where id = p_stage;
  perform app.log('stage.deleted', 'stage', p_stage::text, jsonb_build_object('target', p_target, 'moved', n));
  return jsonb_build_object('moved', n);
end $fn$;

-- ---------------------------------------------------------------------------
-- deals: the activity state and rotting of a card
create function app.deal_act(p_deal uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$ select 'none' $fn$;   -- replaced in 0010 when activities exist

create function app.deal_card(d app.deals) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', d.id, 'seq', d.seq, 'title', d.title, 'value', d.value, 'currency', d.currency, 'status', d.status,
    'pipeline_id', d.pipeline_id, 'stage_id', d.stage_id, 'expected_close_date', d.expected_close_date, 'score', d.score,
    'source', d.source, 'product', d.product, 'labels', to_jsonb(d.labels), 'version', d.version, 'archived_at', d.archived_at,
    'owner_id', d.owner_id, 'owner', (select jsonb_build_object('name', a.name, 'initials', a.initials) from app.admins a where a.id = d.owner_id),
    'organization_id', d.organization_id, 'organization', (select o.name from app.organizations o where o.id = d.organization_id),
    'person_id', d.person_id, 'person', (select p.name from app.people p where p.id = d.person_id),
    'idle_days', floor(extract(epoch from now() - coalesce(d.last_activity_at, d.stage_entered_at)) / 86400)::int,
    'rotting', d.status = 'open' and s.rot_days is not null and now() - coalesce(d.last_activity_at, d.stage_entered_at) > make_interval(days => s.rot_days),
    'act', app.deal_act(d.id), 'probability', s.probability, 'is_sample', d.is_sample,
    'won_at', d.won_at, 'lost_at', d.lost_at, 'lost_reason', d.lost_reason, 'created_at', d.created_at, 'updated_at', d.updated_at, 'deleted_at', d.deleted_at)
  from app.stages s where s.id = d.stage_id
$fn$;

-- the board, the list and the forecast read the same filter (rec_list's filters on deals)
create function public.deal_board(p_pipeline uuid, p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('deal');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_cards jsonb;
begin
  if not app.pipeline_visible(p_pipeline) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_where := format('where t.deleted_at is null and t.archived_at is null and t.pipeline_id = %L and %s', p_pipeline, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if not coalesce((q ->> 'closed')::boolean, false) then v_where := v_where || ' and t.status = ''open'''; end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  execute format('select coalesce(jsonb_agg(app.deal_card(t) order by t.value desc, t.seq), ''[]''::jsonb) from app.deals t %s', v_where) into v_cards;
  perform app.log('record.listed', 'deal', null, jsonb_build_object('count', jsonb_array_length(v_cards), 'view', 'board'));
  return jsonb_build_object(
    'stages', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'probability', s.probability, 'rot_days', s.rot_days) order by s.ord, s.created_at)
                        from app.stages s where s.pipeline_id = p_pipeline), '[]'::jsonb),
    'cards', v_cards,
    'capacity', app.setting('deal_capacity'));
end $fn$;

-- deals as a list across pipelines, sorted, with the card fields
create function public.deal_list(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('deal');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_rows jsonb; v_total bigint; v_order text := '';
  s jsonb;
begin
  v_where := format('where %s and %s', case when (q ->> 'trash')::boolean then 't.deleted_at is not null'
                                             when (q ->> 'archived')::boolean then 't.deleted_at is null and t.archived_at is not null'
                                             else 't.deleted_at is null and t.archived_at is null' end, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if q ? 'pipeline_id' then v_where := v_where || format(' and t.pipeline_id = %L', (q ->> 'pipeline_id')::uuid); end if;
  if q ->> 'status' in ('open', 'won', 'lost') then v_where := v_where || format(' and t.status = %L', q ->> 'status'); end if;
  if btrim(coalesce(q ->> 'q', '')) <> '' then v_where := v_where || format(' and t.title ilike %L', '%' || replace(replace(btrim(q ->> 'q'), '%', '\%'), '_', '\_') || '%'); end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  for s in select * from jsonb_array_elements(coalesce(q -> 'sort', '[{"f":"value","dir":"desc"}]'::jsonb)) loop
    if s ->> 'f' = 'stage' then
      v_order := v_order || format('(select st.probability from app.stages st where st.id = t.stage_id) %s, ', case when s ->> 'dir' = 'asc' then 'asc' else 'desc' end);
    elsif exists (select 1 from app.entity_columns c where c.entity = 'deal' and c.col = s ->> 'f') or s ->> 'f' in ('created_at', 'updated_at') then
      v_order := v_order || format('t.%I %s nulls last, ', s ->> 'f', case when s ->> 'dir' = 'asc' then 'asc' else 'desc' end);
    else
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sort';
    end if;
  end loop;
  execute format('select count(*) from app.deals t %s', v_where) into v_total;
  execute format('select coalesce(jsonb_agg(x.c order by x.n), ''[]''::jsonb) from (select app.deal_card(t) c, row_number() over (order by %s t.seq) n from app.deals t %s order by 2 limit %s offset %s) x',
                 v_order, v_where, least(greatest(coalesce((q ->> 'limit')::int, 100), 1), 500), greatest(coalesce((q ->> 'offset')::int, 0), 0)) into v_rows;
  perform app.log('record.listed', 'deal', null, jsonb_build_object('count', jsonb_array_length(v_rows), 'view', 'list'));
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $fn$;

-- the forecast: open, won and projected per month of expected close
create function public.deal_forecast(p_pipeline uuid, p_from date, p_months int default 4, p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('deal');
  v_where text; v_cards jsonb;
  v_start date := date_trunc('month', coalesce(p_from, current_date))::date;
  v_end date := (date_trunc('month', coalesce(p_from, current_date)) + make_interval(months => least(greatest(coalesce(p_months, 4), 1), 12)))::date;
begin
  v_where := format('where t.deleted_at is null and t.archived_at is null and t.status <> ''lost'' and t.expected_close_date >= %L and t.expected_close_date < %L and %s', v_start, v_end, app.vis_sql(e));
  if p_pipeline is not null then v_where := v_where || format(' and t.pipeline_id = %L', p_pipeline); end if;
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  v_where := v_where || app.filter_sql(e, coalesce(p_query, '{}'::jsonb) -> 'filters');
  execute format('select coalesce(jsonb_agg(app.deal_card(t) order by t.expected_close_date, t.value desc), ''[]''::jsonb) from app.deals t %s', v_where) into v_cards;
  return jsonb_build_object('from', v_start, 'to', v_end, 'cards', v_cards);
end $fn$;

-- move a deal to a stage. Fields required from that stage (or an earlier one) must be filled, or the move
-- is refused with the list of missing fields; p_fields may fill them in the same call.
create function public.deal_move(p_id uuid, p_stage uuid, p_version int default null, p_fields jsonb default null, p_source text default 'ui') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  e app.entities := app.entity('deal');
  d app.deals; v_ok boolean; v_target app.stages; v_missing jsonb; v_custom jsonb;
begin
  select * into d from app.deals where id = p_id and deleted_at is null for update;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others';
  end if;
  if p_version is not null and d.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = d.version::text; end if;
  select * into v_target from app.stages where id = p_stage;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'stage'; end if;
  if v_target.id = d.stage_id then return jsonb_build_object('id', d.id, 'version', d.version); end if;
  if p_fields is not null then
    perform app.check_custom('deal', p_fields);
  end if;
  v_custom := jsonb_strip_nulls(d.custom || coalesce(p_fields, '{}'::jsonb));
  select coalesce(jsonb_agg(jsonb_build_object('key', f.key, 'label', f.label, 'type', f.type, 'options', f.options)), '[]'::jsonb) into v_missing
  from app.fields f join app.stages fs on fs.id = f.from_stage_id
  where f.entity = 'deal' and f.quality = 'required' and f.archived_at is null
    and fs.pipeline_id = v_target.pipeline_id and fs.ord <= v_target.ord
    and (f.pipeline_ids is null or v_target.pipeline_id = any (f.pipeline_ids))
    and (v_custom -> f.key) is null;
  if jsonb_array_length(v_missing) > 0 then
    return jsonb_build_object('id', d.id, 'version', d.version, 'missing', v_missing);
  end if;
  update app.deal_stage_history set left_at = now() where deal_id = d.id and left_at is null;
  insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by, source) values (d.id, v_target.id, now(), v_me, coalesce(p_source, 'ui'));
  update app.deals set stage_id = v_target.id, pipeline_id = v_target.pipeline_id, stage_entered_at = now(), last_activity_at = now(),
    custom = v_custom, version = version + 1, updated_at = now(), updated_by = v_me
  where id = d.id returning * into d;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('deal', d.id, 'stage_id', to_jsonb((select stage_id from app.deal_stage_history where deal_id = d.id and left_at is not null order by left_at desc limit 1)), to_jsonb(v_target.id), v_me, coalesce(p_source, 'ui'));
  if p_fields is not null then
    insert into app.changelog (entity, record_id, field, new_value, actor_id, source)
    select 'deal', d.id, 'custom.' || k, p_fields -> k, v_me, coalesce(p_source, 'ui') from jsonb_object_keys(p_fields) k;
  end if;
  perform app.log('deal.moved', 'deal', d.id::text, jsonb_build_object('stage', v_target.id));
  perform app.emit('deal.stage_changed', 'deal', d.id, jsonb_build_object('to', v_target.id), d.is_sample);
  -- followers hear about it
  perform app.notify(f.staff_id, 'system', 'deal_stage', jsonb_build_object('record', d.title, 'stage', v_target.name, 'actor', (select name from app.admins where id = v_me)),
                     '/deals?deal=' || d.id, 'deal', d.id)
  from app.followers f where f.entity = 'deal' and f.record_id = d.id and f.staff_id <> v_me;
  return jsonb_build_object('id', d.id, 'version', d.version);
end $fn$;

-- won, lost or open again
create function public.deal_status(p_id uuid, p_status text, p_reason text default null, p_comment text default null, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.deals; v_old text;
begin
  if p_status not in ('open', 'won', 'lost') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  select * into d from app.deals where id = p_id and deleted_at is null for update;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  if p_version is not null and d.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = d.version::text; end if;
  if p_status = 'lost' and app.setting('lost_reason_required') = 'on' and coalesce(btrim(p_reason), '') = '' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'lost_reason:required';
  end if;
  v_old := d.status;
  update app.deals set status = p_status,
    won_at = case when p_status = 'won' then now() end, lost_at = case when p_status = 'lost' then now() end,
    lost_reason = case when p_status = 'lost' then nullif(btrim(p_reason), '') end,
    closed_by = case when p_status = 'open' then null else v_me end,
    last_activity_at = now(), version = version + 1, updated_at = now(), updated_by = v_me
  where id = d.id returning * into d;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('deal', d.id, 'status', to_jsonb(v_old), to_jsonb(p_status), v_me, 'ui');
  if coalesce(btrim(p_comment), '') <> '' then
    insert into app.notes (entity, record_id, body, author_id, is_sample) values ('deal', d.id, btrim(p_comment), v_me, d.is_sample);
  end if;
  perform app.log('deal.status', 'deal', d.id::text, jsonb_build_object('from', v_old, 'to', p_status));
  perform app.emit(case p_status when 'won' then 'deal.won' when 'lost' then 'deal.lost' else 'deal.reopened' end, 'deal', d.id, '{}'::jsonb, d.is_sample);
  return jsonb_build_object('id', d.id, 'version', d.version);
end $fn$;

create function public.deal_archive(p_ids uuid[], p_archived boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); n int;
begin
  if cardinality(p_ids) > 1 then perform app.require('deals', 'bulk'); end if;
  with u as (
    update app.deals d set archived_at = case when p_archived then now() end, version = version + 1, updated_at = now(), updated_by = v_me
    where d.id = any (p_ids) and d.deleted_at is null and app.visible(d.owner_id, d.visibility)
      and (d.owner_id = v_me or app.can('deals', 'edit_others')) and (d.archived_at is null) = p_archived
    returning d.id, d.is_sample)
  select count(*) into n from u;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) select 'deal', x, '*archived', to_jsonb(p_archived), v_me from unnest(p_ids) x;
  perform app.log(case when p_archived then 'deal.archived' else 'deal.unarchived' end, 'deal', null, jsonb_build_object('count', n));
  return jsonb_build_object('changed', n);
end $fn$;

-- copy a deal with its fields and lines; no history, notes or followers (PIP-10)
create function public.deal_duplicate(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); d app.deals; v_new uuid;
begin
  select * into d from app.deals where id = p_id and deleted_at is null;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.deals (title, value, currency, value_source, pipeline_id, stage_id, person_id, organization_id, expected_close_date, source, product,
                         owner_id, visibility, labels, custom, is_sample, created_by, updated_by)
  values (left(d.title || ' (copy)', 200), d.value, d.currency, d.value_source, d.pipeline_id, d.stage_id, d.person_id, d.organization_id, d.expected_close_date,
          d.source, d.product, v_me, d.visibility, d.labels, d.custom, (select sandbox from app.admins where id = v_me), v_me, v_me)
  returning id into v_new;
  insert into app.deal_items (deal_id, item_id, name, quantity, unit_price, discount_pct, tax_rate, billing, billing_frequency, cycles, ord)
  select v_new, item_id, name, quantity, unit_price, discount_pct, tax_rate, billing, billing_frequency, cycles, ord from app.deal_items where deal_id = d.id;
  insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by) values (v_new, d.stage_id, now(), v_me);
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('deal', v_new, '*created', jsonb_build_object('duplicate_of', d.id), v_me);
  perform app.log('record.created', 'deal', v_new::text, jsonb_build_object('duplicate_of', d.id));
  perform app.emit('deal.created', 'deal', v_new, jsonb_build_object('source', 'duplicate'));
  return jsonb_build_object('id', v_new);
end $fn$;

-- a new deal starts in a stage of a pipeline (rec_save cannot set the stage)
create function public.deal_create(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'add'); v_stage uuid; v_pipeline uuid; r jsonb;
begin
  perform app.require_module('deals');
  v_pipeline := coalesce((p_values ->> 'pipeline_id')::uuid, (select id from app.pipelines where archived_at is null order by ord limit 1));
  v_stage := coalesce((p_values ->> 'stage_id')::uuid, (select id from app.stages where pipeline_id = v_pipeline order by ord limit 1));
  if v_pipeline is null or v_stage is null or not app.pipeline_visible(v_pipeline) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id'; end if;
  perform set_config('app.deal_pipeline', v_pipeline::text, true);
  perform set_config('app.deal_stage', v_stage::text, true);
  r := public.rec_save('deal', null, (p_values - 'pipeline_id' - 'stage_id') || jsonb_build_object('source', coalesce(p_values ->> 'source', 'Manual')));
  insert into app.deal_stage_history (deal_id, stage_id, entered_at, moved_by) values ((r ->> 'id')::uuid, v_stage, now(), v_me);
  return r;
end $fn$;

-- rec_save inserts a deal without pipeline and stage; deal_create passes them through the transaction
create function app.deal_defaults() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if new.pipeline_id is null then new.pipeline_id := nullif(current_setting('app.deal_pipeline', true), '')::uuid; end if;
  if new.stage_id is null then new.stage_id := nullif(current_setting('app.deal_stage', true), '')::uuid; end if;
  if new.pipeline_id is null or new.stage_id is null then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage_id';
  end if;
  return new;
end $fn$;
create trigger deal_defaults before insert on app.deals for each row execute function app.deal_defaults();
-- deal_defaults must run before deal_stage_ok: triggers fire in name order, and «deal_defaults» < «deal_stage_ok»

-- ---------------------------------------------------------------------------
-- the deal's lines and its value from them (MRR, ARR, ACV, TCV as the drawer shows them)
create function app.deal_revenue(p_deal uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  with l as (
    select i.*, i.quantity * i.unit_price * (1 - i.discount_pct / 100) total,
           case i.billing_frequency when 'monthly' then 1 when 'quarterly' then 3 when 'semiannual' then 6 when 'annual' then 12 else 1 end months
    from app.deal_items i where i.deal_id = p_deal)
  select jsonb_build_object(
    'mrr', coalesce(sum(total / months) filter (where billing = 'recurring'), 0),
    'arr', coalesce(sum(total / months) filter (where billing = 'recurring'), 0) * 12,
    'one_off', coalesce(sum(total) filter (where billing <> 'recurring'), 0),
    'acv', coalesce(sum(total / months) filter (where billing = 'recurring'), 0) * 12 + coalesce(sum(total) filter (where billing <> 'recurring'), 0),
    'tcv', coalesce(sum(total * coalesce(cycles, 12 / months)) filter (where billing = 'recurring'), 0) + coalesce(sum(total) filter (where billing <> 'recurring'), 0),
    'lines', count(*))
  from l
$fn$;

create function app.deal_recalc(p_deal uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_old numeric; v_new numeric;
begin
  select value into v_old from app.deals where id = p_deal and value_source = 'items';
  if not found then return; end if;
  v_new := round((app.deal_revenue(p_deal) ->> 'tcv')::numeric, 2);
  if v_new is distinct from v_old then
    update app.deals set value = v_new, version = version + 1, updated_at = now(), updated_by = app.me() where id = p_deal;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('deal', p_deal, 'value', to_jsonb(v_old), to_jsonb(v_new), app.me(), 'system');
  end if;
end $fn$;

create function public.deal_item_save(p_deal uuid, p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.deals; v_id uuid; c app.catalog_items;
begin
  select * into d from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  if p_id is null then
    if p_values ? 'item_id' then select * into c from app.catalog_items where id = (p_values ->> 'item_id')::uuid and deleted_at is null; end if;
    insert into app.deal_items (deal_id, item_id, name, quantity, unit_price, discount_pct, tax_rate, billing, billing_frequency, cycles, ord)
    values (p_deal, c.id, coalesce(nullif(btrim(p_values ->> 'name'), ''), c.name),
            coalesce((p_values ->> 'quantity')::numeric, 1),
            coalesce((p_values ->> 'unit_price')::numeric, (select unit_price from app.catalog_prices where item_id = c.id and currency = d.currency), 0),
            coalesce((p_values ->> 'discount_pct')::numeric, 0), coalesce((p_values ->> 'tax_rate')::numeric, c.tax_rate, 25),
            coalesce(p_values ->> 'billing', c.billing, 'one_off'), coalesce(p_values ->> 'billing_frequency', c.billing_frequency),
            (p_values ->> 'cycles')::int, (select coalesce(max(ord), 0) + 10 from app.deal_items where deal_id = p_deal))
    returning id into v_id;
  else
    update app.deal_items set
      name = coalesce(nullif(btrim(p_values ->> 'name'), ''), name), quantity = coalesce((p_values ->> 'quantity')::numeric, quantity),
      unit_price = coalesce((p_values ->> 'unit_price')::numeric, unit_price), discount_pct = coalesce((p_values ->> 'discount_pct')::numeric, discount_pct),
      tax_rate = coalesce((p_values ->> 'tax_rate')::numeric, tax_rate), billing = coalesce(p_values ->> 'billing', billing),
      billing_frequency = case when p_values ? 'billing_frequency' then p_values ->> 'billing_frequency' else billing_frequency end,
      cycles = case when p_values ? 'cycles' then (p_values ->> 'cycles')::int else cycles end
    where id = p_id and deal_id = p_deal returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('deal', p_deal, 'items', jsonb_build_object('line', v_id), v_me);
  perform app.deal_recalc(p_deal);
  perform app.log('deal.items_changed', 'deal', p_deal::text);
  return jsonb_build_object('id', v_id, 'revenue', app.deal_revenue(p_deal));
end $fn$;

create function public.deal_item_delete(p_deal uuid, p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.deals;
begin
  select * into d from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  delete from app.deal_items where id = p_id and deal_id = p_deal;
  insert into app.changelog (entity, record_id, field, old_value, actor_id) values ('deal', p_deal, 'items', jsonb_build_object('line', p_id), v_me);
  perform app.deal_recalc(p_deal);
  return jsonb_build_object('revenue', app.deal_revenue(p_deal));
end $fn$;

-- everything the deal drawer shows besides history and activities
create function public.deal_detail(p_id uuid) returns jsonb
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
    'value_source', d.value_source);
end $fn$;

create function public.participant_set(p_deal uuid, p_person uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.deals;
begin
  select * into d from app.deals where id = p_deal and deleted_at is null;
  if not found or not app.visible(d.owner_id, d.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if d.owner_id is distinct from v_me and not app.can('deals', 'edit_others') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'deals:edit_others'; end if;
  if p_on then insert into app.deal_participants (deal_id, person_id, added_by) values (p_deal, p_person, v_me) on conflict do nothing;
  else delete from app.deal_participants where deal_id = p_deal and person_id = p_person; end if;
  insert into app.changelog (entity, record_id, field, new_value, actor_id) values ('deal', p_deal, 'participants', jsonb_build_object('person', p_person, 'on', p_on), v_me);
  perform app.log('deal.participant', 'deal', p_deal::text, jsonb_build_object('on', p_on));
  return jsonb_build_object('ok', true);
end $fn$;

-- ---------------------------------------------------------------------------
-- following a record gives notifications, never rights
create function public.follow_set(p_entity text, p_id uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity); v_me uuid := app.require(e.scope, 'see'); v_ok boolean;
begin
  execute format('select exists (select 1 from app.%I t where t.id = %L and t.deleted_at is null and %s)', e.tbl, p_id, app.vis_sql(e)) into v_ok;
  if not v_ok then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_on then insert into app.followers (entity, record_id, staff_id) values (e.key, p_id, v_me) on conflict do nothing;
  else delete from app.followers where entity = e.key and record_id = p_id and staff_id = v_me; end if;
  perform app.log('record.followed', e.key, p_id::text, jsonb_build_object('on', p_on));
  return jsonb_build_object('following', p_on, 'count', (select count(*) from app.followers where entity = e.key and record_id = p_id));
end $fn$;

-- notes on any record type
create function public.notes_list(p_entity text, p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity); v_ok boolean;
begin
  perform app.require(e.scope, 'see');
  execute format('select exists (select 1 from app.%I t where t.id = %L and %s)', e.tbl, p_id, app.vis_sql(e)) into v_ok;
  if not v_ok then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'body', n.body, 'pinned', n.pinned, 'parent_id', n.parent_id, 'created_at', n.created_at,
                                                       'author', a.name, 'author_id', n.author_id) order by n.pinned desc, n.created_at desc)
                   from app.notes n left join app.admins a on a.id = n.author_id
                   where n.entity = e.key and n.record_id = p_id and n.deleted_at is null), '[]'::jsonb);
end $fn$;

create function public.note_save(p_entity text, p_id uuid, p_note uuid, p_body text, p_pinned boolean default null, p_parent uuid default null, p_mentions uuid[] default '{}')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity); v_me uuid := app.require(e.scope, 'see'); v_ok boolean; v_id uuid; v_title text;
begin
  execute format('select t.%I::text from app.%I t where t.id = %L and t.deleted_at is null and %s', e.title_col, e.tbl, p_id, app.vis_sql(e)) into v_title;
  if v_title is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_note is null then
    insert into app.notes (entity, record_id, body, pinned, parent_id, mentions, author_id, is_sample)
    values (e.key, p_id, btrim(p_body), coalesce(p_pinned, false), p_parent, coalesce(p_mentions, '{}'), v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
    -- @mentions notify: the excerpt is the note's opening, staff-written, never a customer's message
    perform app.notify(m, 'mention', 'mention', jsonb_build_object('actor', (select name from app.admins where id = v_me), 'record', v_title, 'excerpt', left(btrim(p_body), 80)),
                       '/' || case e.key when 'deal' then 'deals?deal=' when 'person' then 'contacts?person=' when 'organization' then 'customers?org=' when 'lead' then 'leads?lead=' else '?' end || p_id, e.key, p_id)
    from unnest(coalesce(p_mentions, '{}')) m where m <> v_me and exists (select 1 from app.admins a where a.id = m and a.active);
    if e.key = 'deal' then update app.deals set last_activity_at = now() where id = p_id; end if;
    perform app.emit('note.created', e.key, p_id, jsonb_build_object('note', v_id));
  else
    update app.notes set body = coalesce(nullif(btrim(p_body), ''), body), pinned = coalesce(p_pinned, pinned), updated_at = now()
    where id = p_note and entity = e.key and record_id = p_id and deleted_at is null and (author_id = v_me or app.can(e.scope, 'edit_others'))
    returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  perform app.log('note.saved', e.key, p_id::text, jsonb_build_object('note', v_id));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.note_delete(p_note uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n app.notes; e app.entities;
begin
  select * into n from app.notes where id = p_note and deleted_at is null;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  e := app.entity(n.entity);
  if n.author_id is distinct from app.me() then perform app.require(e.scope, 'edit_others'); else perform app.require(e.scope, 'see'); end if;
  update app.notes set deleted_at = now() where id = p_note;
  perform app.log('note.deleted', n.entity, n.record_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- saved views and preferences
create function public.views_get(p_screen text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return jsonb_build_object(
    'views', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'query', v.query, 'shared', v.shared, 'mine', v.owner_id = v_me) order by v.ord, v.created_at)
                       from app.saved_views v where v.screen = p_screen and (v.owner_id = v_me or v.shared)), '[]'::jsonb),
    'prefs', coalesce((select jsonb_object_agg(p.key, p.value) from (
                        select distinct on (key) key, value from app.view_prefs where screen = p_screen and (staff_id = v_me or staff_id is null)
                        order by key, staff_id nulls last) p), '{}'::jsonb));
end $fn$;

create function public.view_save(p_id uuid, p_screen text, p_name text, p_query jsonb, p_shared boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  if p_id is null then
    insert into app.saved_views (screen, name, query, owner_id, shared) values (p_screen, btrim(p_name), coalesce(p_query, '{}'::jsonb), v_me, coalesce(p_shared, false)) returning id into v_id;
  else
    update app.saved_views set name = coalesce(nullif(btrim(p_name), ''), name), query = coalesce(p_query, query), shared = coalesce(p_shared, shared)
    where id = p_id and owner_id = v_me returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.view_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  delete from app.saved_views where id = p_id and owner_id = app.require_staff();
  return jsonb_build_object('ok', found);
end $fn$;

create function public.pref_set(p_screen text, p_key text, p_value jsonb, p_default boolean default false) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_staff uuid;
begin
  if p_default then perform app.require('global', 'configure'); v_staff := null; else v_staff := v_me; end if;
  delete from app.view_prefs where staff_id is not distinct from v_staff and screen = p_screen and key = p_key;
  insert into app.view_prefs (staff_id, screen, key, value) values (v_staff, p_screen, p_key, p_value);
  return jsonb_build_object('ok', true);
end $fn$;

create function public.lost_reasons_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', label) order by ord) from app.lost_reasons where active), '[]'::jsonb);
end $fn$;

create function public.catalog_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me);
begin
  return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('prices', coalesce((select jsonb_object_agg(p.currency, p.unit_price) from app.catalog_prices p where p.item_id = c.id), '{}'::jsonb)) order by c.name)
                   from app.catalog_items c where c.deleted_at is null and app.visible(c.owner_id, c.visibility) and (v_sandbox or not c.is_sample)), '[]'::jsonb);
end $fn$;

create function public.catalog_price_set(p_item uuid, p_currency text, p_price numeric) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require('deals', 'configure');
  if p_price is null then delete from app.catalog_prices where item_id = p_item and currency = p_currency;
  else insert into app.catalog_prices (item_id, currency, unit_price) values (p_item, upper(p_currency), p_price)
       on conflict (item_id, currency) do update set unit_price = excluded.unit_price; end if;
  perform app.log('catalog.price_set', 'catalog_item', p_item::text, jsonb_build_object('currency', upper(p_currency)));
  return jsonb_build_object('ok', true);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['pipelines', 'stages', 'lost_reasons', 'catalog_items', 'catalog_prices', 'deals', 'deal_stage_history', 'deal_participants',
                           'deal_items', 'notes', 'followers', 'saved_views', 'view_prefs'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.pipeline_visible(uuid)', 'app.deal_act(uuid)', 'app.deal_card(app.deals)', 'app.deal_revenue(uuid)', 'app.deal_recalc(uuid)',
                           'app.deal_stage_ok()', 'app.deal_defaults()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.pipelines_get()', 'public.pipeline_save(uuid, jsonb)', 'public.stage_save(uuid, uuid, jsonb)', 'public.stages_reorder(uuid, uuid[])',
                           'public.stage_delete(uuid, uuid)', 'public.deal_board(uuid, jsonb)', 'public.deal_list(jsonb)', 'public.deal_forecast(uuid, date, int, jsonb)',
                           'public.deal_move(uuid, uuid, int, jsonb, text)', 'public.deal_status(uuid, text, text, text, int)', 'public.deal_archive(uuid[], boolean)',
                           'public.deal_duplicate(uuid)', 'public.deal_create(jsonb)', 'public.deal_item_save(uuid, uuid, jsonb)', 'public.deal_item_delete(uuid, uuid)',
                           'public.deal_detail(uuid)', 'public.participant_set(uuid, uuid, boolean)', 'public.follow_set(text, uuid, boolean)',
                           'public.notes_list(text, uuid)', 'public.note_save(text, uuid, uuid, text, boolean, uuid, uuid[])', 'public.note_delete(uuid)',
                           'public.views_get(text)', 'public.view_save(uuid, text, text, jsonb, boolean)', 'public.view_delete(uuid)',
                           'public.pref_set(text, text, jsonb, boolean)', 'public.lost_reasons_get()', 'public.catalog_get()', 'public.catalog_price_set(uuid, text, numeric)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
