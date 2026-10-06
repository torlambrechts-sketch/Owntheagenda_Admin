-- 0006_records_core.sql — business records and the one generic path that reads and writes them.
--
-- A record type is data: a row in app.entities names its table, the scope its rights are checked in,
-- whether it has an owner and visibility, and which columns may be searched. app.entity_columns lists the
-- columns a caller may write or filter, with their type. Custom fields (app.fields) live in each record's
-- `custom` object and are validated against their definition. Labels (app.labels) are per record type.
--
-- public.rec_list / rec_get / rec_save / rec_delete / rec_restore / rec_history / rec_group are the
-- generic functions. Each checks the caller's right in the record type's scope, the record's visibility,
-- the version (optimistic concurrency), writes the record history and the audit, and emits an event.
-- Dynamic SQL uses only identifiers from the registry (format %I) and literals quoted by format %L.
--
-- Standard columns on every business table: id, version, created_at, created_by, updated_at, updated_by,
-- deleted_at (soft delete, purged after 30 days), is_sample (sandbox), custom, labels; and owner_id,
-- visibility where the record type is owned.

create table app.entities (
  key       text primary key check (key ~ '^[a-z_]{2,40}$'),
  tbl       text not null unique check (tbl ~ '^[a-z_]{2,40}$'),
  scope     text not null check (scope in ('deals', 'projects', 'campaigns', 'global')),
  module    text,                                  -- the module switch that turns the record type off
  owned     boolean not null default true,
  title_col text not null default 'name',
  sub_cols  text[] not null default '{}',          -- shown under the title in search
  search    text[] not null default '{}',          -- searched by the ⌘K search and a list's q
  ord       int not null default 0
);

create table app.entity_columns (
  entity   text not null references app.entities (key) on delete cascade,
  col      text not null check (col ~ '^[a-z_][a-z0-9_]{0,40}$'),
  kind     text not null check (kind in ('text', 'int', 'numeric', 'boolean', 'date', 'timestamptz', 'uuid', 'uuid[]', 'text[]', 'jsonb')),
  writable boolean not null default true,
  required boolean not null default false,
  ref      text references app.entities (key),     -- a uuid column that points at another record type
  ord      int not null default 0,
  primary key (entity, col)
);

-- ---------------------------------------------------------------------------
-- custom fields (Settings › Data fields): the design's sixteen types plus formula
create table app.fields (
  id            uuid primary key default gen_random_uuid(),
  entity        text not null references app.entities (key) on delete cascade,
  key           text not null check (key ~ '^[a-z][a-z0-9_]{1,40}$'),
  label         text not null check (char_length(btrim(label)) between 1 and 80),
  type          text not null check (type in ('text', 'large_text', 'single_option', 'multiple_options', 'autocomplete',
                                              'numerical', 'monetary', 'user', 'organization', 'person', 'phone', 'time',
                                              'time_range', 'date', 'date_range', 'address', 'formula')),
  options       jsonb not null default '[]'::jsonb check (jsonb_typeof(options) = 'array'),
  quality       text not null default 'optional' check (quality in ('optional', 'important', 'required')),
  from_stage_id uuid,                              -- quality applies from this pipeline stage (deals)
  pipeline_ids  uuid[],                            -- null: all pipelines
  hidden_for    uuid[] not null default '{}',      -- permission sets that do not see the field
  readonly_for  uuid[] not null default '{}',      -- permission sets that see but cannot change it
  description   text check (description is null or char_length(description) <= 300),
  formula       text check (formula is null or char_length(formula) <= 500),
  ord           int not null default 0,
  archived_at   timestamptz,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (entity, key),
  check ((type = 'formula') = (formula is not null))
);

create table app.labels (
  id         uuid primary key default gen_random_uuid(),
  entity     text not null references app.entities (key) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  bg         text not null check (bg ~ '^#[0-9A-F]{6}$'),
  ink        text not null check (ink ~ '^#[0-9A-F]{6}$'),
  ord        int not null default 0,
  created_at timestamptz not null default now(),
  unique (entity, name)
);

-- ---------------------------------------------------------------------------
-- organizations: the CRM's company. account_id links it to the customer the products know (org.nr).
create table app.organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(btrim(name)) between 1 and 200),
  org_number    text check (org_number is null or org_number ~ '^\d{9}$'),
  account_id    uuid references app.accounts (id) on delete set null,
  address       text check (address is null or char_length(address) <= 200),
  postal_code   text check (postal_code is null or char_length(postal_code) <= 12),
  city          text check (city is null or char_length(city) <= 80),
  fylke         text check (fylke is null or char_length(fylke) <= 60),
  country       text not null default 'NO' check (country ~ '^[A-Z]{2}$'),
  industry      text check (industry is null or char_length(industry) <= 80),
  nace          text check (nace is null or nace ~ '^\d{2}\.\d{1,3}$'),
  employees     int check (employees is null or employees >= 0),
  website       text check (website is null or char_length(website) <= 200),
  phone         text check (phone is null or char_length(phone) <= 40),
  email         text check (email is null or char_length(email) <= 254),
  source        text check (source is null or char_length(source) <= 60),
  parent_id     uuid references app.organizations (id) on delete set null,
  ehf           boolean not null default false,
  csm_id        uuid references app.admins (id) on delete set null,
  brreg_synced_at timestamptz,
  edited_fields text[] not null default '{}',
  owner_id      uuid references app.admins (id) on delete set null,
  visibility    text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels        uuid[] not null default '{}',
  custom        jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample     boolean not null default false,
  version       int not null default 1,
  created_at    timestamptz not null default now(),
  created_by    uuid,
  updated_at    timestamptz not null default now(),
  updated_by    uuid,
  deleted_at    timestamptz,
  check (parent_id is distinct from id)
);
create unique index organizations_org_number on app.organizations (org_number) where deleted_at is null and org_number is not null and not is_sample;
create index organizations_account on app.organizations (account_id);
create index organizations_name on app.organizations (lower(name));

-- people: one person. member_* links them to a product user when they are one (D-13).
create table app.people (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (char_length(btrim(name)) between 1 and 200),
  email           text check (email is null or (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+$')),
  phone           text check (phone is null or char_length(phone) <= 40),
  organization_id uuid references app.organizations (id) on delete set null,
  title           text check (title is null or char_length(title) <= 80),
  contact_type    text check (contact_type is null or contact_type in ('prospect', 'trial_user', 'customer_user', 'former_customer', 'partner', 'other')),
  source          text check (source is null or char_length(source) <= 60),
  city            text check (city is null or char_length(city) <= 80),
  fylke           text check (fylke is null or char_length(fylke) <= 60),
  linkedin        text check (linkedin is null or char_length(linkedin) <= 200),
  member_product  text,
  member_tenant   text,
  member_user     text,
  last_touch_at   timestamptz,
  edited_fields   text[] not null default '{}',
  owner_id        uuid references app.admins (id) on delete set null,
  visibility      text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels          uuid[] not null default '{}',
  custom          jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample       boolean not null default false,
  version         int not null default 1,
  created_at      timestamptz not null default now(),
  created_by      uuid,
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  deleted_at      timestamptz,
  foreign key (member_product, member_tenant, member_user) references app.members (product, tenant_id, user_id) on delete set null (member_product, member_tenant, member_user),
  check ((member_product is null) = (member_user is null) and (member_tenant is null) = (member_user is null))
);
create index people_org on app.people (organization_id);
create index people_email on app.people (lower(email));

insert into app.entities (key, tbl, scope, owned, title_col, sub_cols, search, ord) values
  ('organization', 'organizations', 'deals', true, 'name', array['org_number', 'city'], array['name', 'org_number', 'email', 'phone', 'city'], 10),
  ('person', 'people', 'deals', true, 'name', array['title', 'email'], array['name', 'email', 'phone'], 20);

insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('organization', 'name', 'text', true, true, null, 1),
  ('organization', 'org_number', 'text', true, false, null, 2),
  ('organization', 'account_id', 'uuid', false, false, null, 3),
  ('organization', 'address', 'text', true, false, null, 4),
  ('organization', 'postal_code', 'text', true, false, null, 5),
  ('organization', 'city', 'text', true, false, null, 6),
  ('organization', 'fylke', 'text', true, false, null, 7),
  ('organization', 'country', 'text', true, false, null, 8),
  ('organization', 'industry', 'text', true, false, null, 9),
  ('organization', 'nace', 'text', true, false, null, 10),
  ('organization', 'employees', 'int', true, false, null, 11),
  ('organization', 'website', 'text', true, false, null, 12),
  ('organization', 'phone', 'text', true, false, null, 13),
  ('organization', 'email', 'text', true, false, null, 14),
  ('organization', 'source', 'text', true, false, null, 15),
  ('organization', 'parent_id', 'uuid', true, false, 'organization', 16),
  ('organization', 'ehf', 'boolean', true, false, null, 17),
  ('organization', 'csm_id', 'uuid', true, false, null, 18),
  ('organization', 'brreg_synced_at', 'timestamptz', false, false, null, 19),
  ('person', 'name', 'text', true, true, null, 1),
  ('person', 'email', 'text', true, false, null, 2),
  ('person', 'phone', 'text', true, false, null, 3),
  ('person', 'organization_id', 'uuid', true, false, 'organization', 4),
  ('person', 'title', 'text', true, false, null, 5),
  ('person', 'contact_type', 'text', true, false, null, 6),
  ('person', 'source', 'text', true, false, null, 7),
  ('person', 'city', 'text', true, false, null, 8),
  ('person', 'fylke', 'text', true, false, null, 9),
  ('person', 'linkedin', 'text', true, false, null, 10),
  ('person', 'last_touch_at', 'timestamptz', false, false, null, 11);

-- recently opened records, for the search's «Recent» group
create table app.recents (
  staff_id  uuid not null references app.admins (id) on delete cascade,
  entity    text not null references app.entities (key) on delete cascade,
  record_id uuid not null,
  at        timestamptz not null default now(),
  primary key (staff_id, entity, record_id)
);

-- ---------------------------------------------------------------------------
-- helpers
create function app.entity(p_key text) returns app.entities
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities;
begin
  select * into e from app.entities where key = p_key;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'entity'; end if;
  if e.module is not null then perform app.require_module(e.module); end if;
  return e;
end $fn$;

-- the reason a caller typed; required when the register says so (typed_reason)
create function app.take_reason(p_reason text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  if app.setting('typed_reason') = 'on' and coalesce(btrim(p_reason), '') = '' then
    raise exception 'reason_required' using errcode = 'invalid_parameter_value';
  end if;
  perform set_config('app.reason', left(coalesce(btrim(p_reason), ''), 300), true);
end $fn$;

-- a jsonb value as a SQL literal of the column's type
create function app.lit(p_value jsonb, p_kind text) returns text
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then return 'null'; end if;
  if p_kind in ('uuid[]', 'text[]') then
    if jsonb_typeof(p_value) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
    return format('array(select jsonb_array_elements_text(%L::jsonb))::%s', p_value::text, p_kind);
  end if;
  if p_kind = 'jsonb' then return format('%L::jsonb', p_value::text); end if;
  if jsonb_typeof(p_value) in ('object', 'array') then raise exception 'invalid' using errcode = 'invalid_parameter_value'; end if;
  return format('%L::%s', p_value #>> '{}', p_kind);
end $fn$;

-- a custom-field object checked against the definitions: unknown keys, wrong types, unknown options
create function app.check_custom(p_entity text, p_custom jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  k text; v jsonb; f app.fields; v_ok boolean;
  v_me uuid := app.me();
  v_set uuid := (select permission_set_id from app.admins where id = v_me);
begin
  if p_custom is null then return '{}'::jsonb; end if;
  if jsonb_typeof(p_custom) <> 'object' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom';
  end if;
  for k, v in select * from jsonb_each(p_custom) loop
    select * into f from app.fields where entity = p_entity and key = k and archived_at is null;
    if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || k; end if;
    if f.type = 'formula' or v_set = any (f.readonly_for) or v_set = any (f.hidden_for) then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'custom.' || k;
    end if;
    continue when jsonb_typeof(v) = 'null';
    v_ok := case f.type
      when 'numerical' then jsonb_typeof(v) = 'number'
      when 'monetary' then jsonb_typeof(v) = 'object' and jsonb_typeof(v -> 'amount') = 'number'
                           and coalesce(v ->> 'currency', '') ~ '^[A-Z]{3}$'
      when 'single_option' then jsonb_typeof(v) = 'string' and exists (select 1 from jsonb_array_elements(f.options) o where o ->> 'key' = v #>> '{}')
      when 'multiple_options' then jsonb_typeof(v) = 'array' and not exists (
             select 1 from jsonb_array_elements_text(v) x where not exists (select 1 from jsonb_array_elements(f.options) o where o ->> 'key' = x))
      when 'date' then jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\d{4}-\d{2}-\d{2}$'
      when 'date_range' then jsonb_typeof(v) = 'object' and coalesce(v ->> 'from', '') ~ '^\d{4}-\d{2}-\d{2}$' and coalesce(v ->> 'to', '') ~ '^\d{4}-\d{2}-\d{2}$'
      when 'time' then jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\d{2}:\d{2}$'
      when 'time_range' then jsonb_typeof(v) = 'object' and coalesce(v ->> 'from', '') ~ '^\d{2}:\d{2}$' and coalesce(v ->> 'to', '') ~ '^\d{2}:\d{2}$'
      when 'user' then jsonb_typeof(v) = 'string' and exists (select 1 from app.admins a where a.id::text = v #>> '{}')
      when 'organization' then jsonb_typeof(v) = 'string' and exists (select 1 from app.organizations o where o.id::text = v #>> '{}' and o.deleted_at is null)
      when 'person' then jsonb_typeof(v) = 'string' and exists (select 1 from app.people p where p.id::text = v #>> '{}' and p.deleted_at is null)
      when 'address' then jsonb_typeof(v) = 'object'
      else jsonb_typeof(v) = 'string' and char_length(v #>> '{}') <= case when f.type = 'large_text' then 10000 else 500 end
    end;
    if not coalesce(v_ok, false) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || k;
    end if;
  end loop;
  return p_custom;
end $fn$;

-- the visibility condition of a record type, as SQL over alias t
create function app.vis_sql(e app.entities) returns text
  language sql immutable set search_path = ''
as $fn$
  select case when e.owned then 'app.visible(t.owner_id, t.visibility)' else 'true' end
$fn$;

-- a filter list as SQL over alias t. Each filter: {f, op, v}; f is a registered column, a standard column,
-- or custom.<key>. Values are quoted literals of the column's type.
create function app.filter_sql(e app.entities, p_filters jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  x jsonb; f text; op text; v jsonb; kind text; col text; out text := ''; ftype text;
begin
  if p_filters is null or jsonb_typeof(p_filters) <> 'array' then return ''; end if;
  for x in select * from jsonb_array_elements(p_filters) loop
    f := x ->> 'f'; op := coalesce(x ->> 'op', 'eq'); v := x -> 'v';
    if f like 'custom.%' then
      select type into ftype from app.fields where entity = e.key and key = substr(f, 8) and archived_at is null;
      if ftype is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.' || f; end if;
      col := format('(t.custom ->> %L)', substr(f, 8));
      kind := case when ftype in ('numerical') then 'numeric' when ftype = 'date' then 'date' else 'text' end;
      if kind <> 'text' then col := format('(%s)::%s', col, kind); end if;
      if ftype = 'multiple_options' then
        col := format('(t.custom -> %L)', substr(f, 8)); kind := 'jsonb';
      end if;
    else
      select c.kind into kind from app.entity_columns c where c.entity = e.key and c.col = f;
      if kind is null then
        kind := case f when 'owner_id' then 'uuid' when 'visibility' then 'text' when 'labels' then 'uuid[]'
                       when 'created_at' then 'timestamptz' when 'updated_at' then 'timestamptz' when 'created_by' then 'uuid'
                       when 'id' then 'uuid' else null end;
        if kind is null or (f in ('owner_id', 'visibility') and not e.owned) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.' || f;
        end if;
      end if;
      col := format('t.%I', f);
    end if;
    out := out || ' and ' || case op
      when 'eq' then format('%s = %s', col, app.lit(v, kind))
      when 'neq' then format('%s is distinct from %s', col, app.lit(v, kind))
      when 'in' then format('%s = any (%s)', col, app.lit(v, case when kind like '%[]' then kind else kind || '[]' end))
      when 'nin' then format('not (%s = any (%s))', col, app.lit(v, case when kind like '%[]' then kind else kind || '[]' end))
      when 'contains' then format('%s::text ilike %L', col, '%' || replace(replace(v #>> '{}', '%', '\%'), '_', '\_') || '%')
      when 'gt' then format('%s > %s', col, app.lit(v, kind))
      when 'gte' then format('%s >= %s', col, app.lit(v, kind))
      when 'lt' then format('%s < %s', col, app.lit(v, kind))
      when 'lte' then format('%s <= %s', col, app.lit(v, kind))
      when 'empty' then case when kind like '%[]' then format('coalesce(cardinality(%s), 0) = 0', col) else format('(%s is null or %s::text = %L)', col, col, '') end
      when 'notempty' then case when kind like '%[]' then format('cardinality(%s) > 0', col) else format('(%s is not null and %s::text <> %L)', col, col, '') end
      when 'has' then case when kind = 'jsonb' then format('%s ?| array(select jsonb_array_elements_text(%L::jsonb))', col, v::text)
                           else format('%s && %s', col, app.lit(v, kind)) end
      when 'within_days' then format('%s >= now() - make_interval(days => %s)', col, (v #>> '{}')::int)
      else null end;
    if out is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.op'; end if;
  end loop;
  return out;
end $fn$;

-- the select list that adds the titles of referenced records (owner, organization …) as <col>__title
create function app.refs_sql(e app.entities) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare r record; out text := '';
begin
  if e.owned then
    out := out || ', ''owner_id__title'', (select a.name from app.admins a where a.id = t.owner_id)';
  end if;
  for r in select c.col, re.tbl, re.title_col from app.entity_columns c join app.entities re on re.key = c.ref where c.entity = e.key loop
    out := out || format(', %L, (select r.%I from app.%I r where r.id = t.%I)', r.col || '__title', r.title_col, r.tbl, r.col);
  end loop;
  return out;
end $fn$;

-- ---------------------------------------------------------------------------
-- list: {q, filters, sort: {f, dir}, limit, offset, trash, ids, mine} → {total, rows}
create function public.rec_list(p_entity text, p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid := app.require(e.scope, 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_sort text; v_dir text; v_limit int; v_offset int; v_total bigint; v_rows jsonb; v_q text;
begin
  v_where := format('where %s and %s', case when (q ->> 'trash')::boolean then 't.deleted_at is not null' else 't.deleted_at is null' end,
                    app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  v_q := btrim(coalesce(q ->> 'q', ''));
  if v_q <> '' and cardinality(e.search) > 0 then
    v_where := v_where || ' and (' || (select string_agg(format('t.%I::text ilike %L', s, '%' || replace(replace(v_q, '%', '\%'), '_', '\_') || '%'), ' or ')
                                       from unnest(e.search) s) || ')';
  end if;
  if q ? 'ids' then v_where := v_where || format(' and t.id = any (%s)', app.lit(q -> 'ids', 'uuid[]')); end if;
  if coalesce((q ->> 'mine')::boolean, false) and e.owned then v_where := v_where || format(' and t.owner_id = %L', v_me); end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');

  v_sort := coalesce(q #>> '{sort,f}', 'updated_at');
  v_dir := case when lower(coalesce(q #>> '{sort,dir}', 'desc')) = 'asc' then 'asc' else 'desc' end;
  if v_sort not in ('updated_at', 'created_at') and not exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = v_sort) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sort';
  end if;
  v_limit := least(greatest(coalesce((q ->> 'limit')::int, 50), 1), 500);
  v_offset := greatest(coalesce((q ->> 'offset')::int, 0), 0);

  execute format('select count(*) from app.%I t %s', e.tbl, v_where) into v_total;
  execute format('select coalesce(jsonb_agg(x.j - ''__x'' order by x.n), ''[]''::jsonb) from (select row_number() over (order by t.%I %s nulls last, t.id) n, to_jsonb(t) || jsonb_build_object(''__x'', 1 %s) j from app.%I t %s order by 1 limit %s offset %s) x',
                 v_sort, v_dir, app.refs_sql(e), e.tbl, v_where, v_limit, v_offset) into v_rows;
  perform app.log('record.listed', e.key, null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $fn$;

-- counts and sums per value of one column (tabs, board columns): → [{key, n, sum}]
create function public.rec_group(p_entity text, p_by text, p_query jsonb default '{}'::jsonb, p_sum text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid := app.require(e.scope, 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_out jsonb;
begin
  if not exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = p_by) and p_by not in ('owner_id', 'visibility') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'by';
  end if;
  if p_sum is not null and not exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = p_sum and c.kind in ('int', 'numeric')) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sum';
  end if;
  v_where := format('where t.deleted_at is null and %s', app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  execute format('select coalesce(jsonb_agg(jsonb_build_object(''key'', g.k, ''n'', g.n, ''sum'', g.s)), ''[]''::jsonb) from (select t.%I::text k, count(*) n, %s s from app.%I t %s group by 1) g',
                 p_by, case when p_sum is null then 'null::numeric' else format('sum(t.%I)', p_sum) end, e.tbl, v_where) into v_out;
  return v_out;
end $fn$;

-- one record, with the titles of what it points at; the read is audited and remembered as recent
create function public.rec_get(p_entity text, p_id uuid, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid := app.require(e.scope, 'see');
  v_row jsonb;
begin
  perform app.take_reason(p_reason);
  execute format('select to_jsonb(t) || jsonb_build_object(''__x'', 1 %s) from app.%I t where t.id = %L and %s',
                 app.refs_sql(e), e.tbl, p_id, app.vis_sql(e)) into v_row;
  if v_row is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.recents (staff_id, entity, record_id) values (v_me, e.key, p_id)
  on conflict (staff_id, entity, record_id) do update set at = now();
  delete from app.recents r where r.staff_id = v_me and r.at < (select min(x.at) from (select at from app.recents where staff_id = v_me order by at desc limit 20) x);
  perform app.log('record.read', e.key, p_id::text);
  return v_row - '__x';
end $fn$;

-- create (p_id null) or update one record. p_values holds registered columns, owner_id, visibility, labels
-- and custom (merged; a null removes a key). p_version must match on update. → {id, version}
create function public.rec_save(p_entity text, p_id uuid, p_values jsonb, p_version int default null,
                                p_reason text default null, p_source text default 'ui')
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid;
  v_sandbox boolean;
  v_old jsonb; v_new jsonb;
  k text; v jsonb; kind text; w boolean;
  v_cols text[] := '{}'; v_vals text[] := '{}'; v_sets text[] := '{}';
  v_id uuid; v_changed text[] := '{}'; v_req record;
  v_source text := coalesce(p_source, 'ui');
  v_has_edited boolean;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values';
  end if;
  if v_source not in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source';
  end if;
  v_me := app.require(e.scope, case when p_id is null then 'add' else 'see' end);
  v_sandbox := (select sandbox from app.admins where id = v_me);
  perform app.take_reason(p_reason);
  v_has_edited := exists (select 1 from information_schema.columns c where c.table_schema = 'app' and c.table_name = e.tbl and c.column_name = 'edited_fields');

  if p_id is not null then
    execute format('select to_jsonb(t) from app.%I t where t.id = %L and t.deleted_at is null and %s for update', e.tbl, p_id, app.vis_sql(e)) into v_old;
    if v_old is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and (v_old ->> 'version')::int <> p_version then
      raise exception 'version_conflict' using errcode = 'serialization_failure', detail = v_old ->> 'version';
    end if;
    if e.owned and (v_old ->> 'owner_id') is distinct from v_me::text and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
    if not e.owned and not app.can(e.scope, 'add') and not app.can(e.scope, 'edit_others') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = e.scope || ':edit_others';
    end if;
  end if;

  for k, v in select * from jsonb_each(p_values) loop
    if k = 'custom' then
      perform app.check_custom(e.key, v);
      if p_id is null then
        v_cols := v_cols || 'custom'::text; v_vals := v_vals || format('jsonb_strip_nulls(%L::jsonb)', v::text);
      else
        v_sets := v_sets || format('custom = jsonb_strip_nulls(t.custom || %L::jsonb)', v::text);
      end if;
      continue;
    elsif k in ('owner_id', 'visibility') and e.owned then
      kind := case k when 'owner_id' then 'uuid' else 'text' end; w := true;
      if k = 'owner_id' and jsonb_typeof(v) = 'string' and not exists (select 1 from app.admins a where a.id::text = v #>> '{}' and a.active) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'owner_id';
      end if;
    elsif k = 'labels' then
      kind := 'uuid[]'; w := true;
      if exists (select 1 from jsonb_array_elements_text(v) x where not exists (select 1 from app.labels l where l.id::text = x and l.entity = e.key)) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'labels';
      end if;
    else
      select c.kind, c.writable into kind, w from app.entity_columns c where c.entity = e.key and c.col = k;
      if kind is null or not w then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
    end if;
    if p_id is null then
      v_cols := v_cols || k; v_vals := v_vals || app.lit(v, kind);
    else
      v_sets := v_sets || format('%I = %s', k, app.lit(v, kind));
    end if;
  end loop;

  if p_id is null then
    -- required columns and required custom fields on create
    for v_req in select c.col from app.entity_columns c where c.entity = e.key and c.required loop
      if coalesce(btrim(p_values ->> v_req.col), '') = '' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = v_req.col || ':required';
      end if;
    end loop;
    for v_req in select f.key from app.fields f where f.entity = e.key and f.quality = 'required' and f.from_stage_id is null and f.archived_at is null loop
      if jsonb_typeof(p_values #> array['custom', v_req.key]) is null or jsonb_typeof(p_values #> array['custom', v_req.key]) = 'null' then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'custom.' || v_req.key || ':required';
      end if;
    end loop;
    if e.owned and not (p_values ? 'owner_id') then v_cols := v_cols || 'owner_id'::text; v_vals := v_vals || quote_literal(v_me); end if;
    if e.owned and not (p_values ? 'visibility') then
      v_cols := v_cols || 'visibility'::text; v_vals := v_vals || quote_literal(app.setting('visibility_default', e.key));
    end if;
    v_cols := v_cols || array['created_by', 'updated_by', 'is_sample'];
    v_vals := v_vals || array[quote_literal(v_me), quote_literal(v_me), quote_literal(v_sandbox)];
    if v_has_edited and v_source = 'ui' then
      v_cols := v_cols || 'edited_fields'::text; v_vals := v_vals || app.lit(to_jsonb(array(select jsonb_object_keys(p_values))), 'text[]');
    end if;
    execute format('insert into app.%I as t (%s) values (%s) returning to_jsonb(t)', e.tbl,
                   (select string_agg(format('%I', c), ', ') from unnest(v_cols) c), array_to_string(v_vals, ', ')) into v_new;
    v_id := (v_new ->> 'id')::uuid;
    insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
    values (e.key, v_id, '*created', null, null, v_me, v_source);
    perform app.log('record.created', e.key, v_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
    perform app.emit(e.key || '.created', e.key, v_id, '{}'::jsonb, v_sandbox);
    return jsonb_build_object('id', v_id, 'version', 1);
  end if;

  if cardinality(v_sets) = 0 then
    return jsonb_build_object('id', p_id, 'version', (v_old ->> 'version')::int);
  end if;
  v_sets := v_sets || array['version = t.version + 1', 'updated_at = now()', format('updated_by = %L', v_me)];
  if v_has_edited and v_source = 'ui' then
    v_sets := v_sets || format('edited_fields = array(select distinct x from unnest(t.edited_fields || %s) x)',
                               app.lit(to_jsonb(array(select jsonb_object_keys(p_values - 'custom'))), 'text[]'));
  end if;
  execute format('update app.%I as t set %s where t.id = %L returning to_jsonb(t)', e.tbl, array_to_string(v_sets, ', '), p_id) into v_new;

  -- the history: one row per field whose value changed
  for k in select jsonb_object_keys(p_values) loop
    if k = 'custom' then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      select e.key, p_id, 'custom.' || ck, v_old #> array['custom', ck], v_new #> array['custom', ck], v_me, v_source
      from jsonb_object_keys(p_values -> 'custom') ck
      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]);
      v_changed := v_changed || array(select 'custom.' || ck from jsonb_object_keys(p_values -> 'custom') ck
                                      where (v_old #> array['custom', ck]) is distinct from (v_new #> array['custom', ck]));
    elsif (v_old -> k) is distinct from (v_new -> k) then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
      values (e.key, p_id, k, v_old -> k, v_new -> k, v_me, v_source);
      v_changed := v_changed || k;
    end if;
  end loop;
  perform app.log('record.updated', e.key, p_id::text, jsonb_build_object('fields', to_jsonb(v_changed)));
  if cardinality(v_changed) > 0 then
    perform app.emit(e.key || '.updated', e.key, p_id, jsonb_build_object('fields', to_jsonb(v_changed)), (v_new ->> 'is_sample')::boolean);
  end if;
  return jsonb_build_object('id', p_id, 'version', (v_new ->> 'version')::int);
end $fn$;

-- the same values on many records (bulk edit, «Bulk edit and merge» right). → {updated}
create function public.rec_bulk(p_entity text, p_ids uuid[], p_values jsonb, p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_id uuid; n int := 0;
begin
  perform app.require(e.scope, 'bulk');
  if cardinality(p_ids) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  foreach v_id in array coalesce(p_ids, '{}') loop
    perform public.rec_save(p_entity, v_id, p_values, null, p_reason, 'ui');
    n := n + 1;
  end loop;
  return jsonb_build_object('updated', n);
end $fn$;

-- soft delete; restored within 30 days, purged after
create function public.rec_delete(p_entity text, p_ids uuid[], p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid := app.require(e.scope, 'delete');
  v_ids uuid[];
begin
  perform app.take_reason(p_reason);
  if cardinality(p_ids) > 1 then perform app.require(e.scope, 'bulk'); end if;
  execute format('with u as (update app.%I t set deleted_at = now(), updated_at = now(), updated_by = %L, version = t.version + 1 where t.id = any (%L::uuid[]) and t.deleted_at is null and %s returning t.id) select array_agg(id) from u',
                 e.tbl, v_me, p_ids, app.vis_sql(e))
    into v_ids;
  v_ids := coalesce(v_ids, '{}');
  insert into app.changelog (entity, record_id, field, actor_id, source) select e.key, x, '*deleted', v_me, 'ui' from unnest(v_ids) x;
  perform app.log('record.deleted', e.key, case when cardinality(v_ids) = 1 then v_ids[1]::text end, jsonb_build_object('count', cardinality(v_ids)));
  perform app.emit(e.key || '.deleted', e.key, x, '{}'::jsonb) from unnest(v_ids) x;
  return jsonb_build_object('deleted', cardinality(v_ids));
end $fn$;

create function public.rec_restore(p_entity text, p_ids uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_me uuid := app.require(e.scope, 'delete');
  n int;
begin
  execute format('with u as (update app.%I t set deleted_at = null, updated_at = now(), updated_by = %L, version = t.version + 1 where t.id = any (%L::uuid[]) and t.deleted_at is not null and %s returning t.id) select count(*) from u',
                 e.tbl, v_me, p_ids, app.vis_sql(e)) into n;
  insert into app.changelog (entity, record_id, field, actor_id, source) select e.key, x, '*restored', v_me, 'ui' from unnest(p_ids) x;
  perform app.log('record.restored', e.key, null, jsonb_build_object('count', n));
  return jsonb_build_object('restored', n);
end $fn$;

-- the history of one record, newest first, with the actor's name
create function public.rec_history(p_entity text, p_id uuid, p_limit int default 100) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  e app.entities := app.entity(p_entity);
  v_ok boolean;
begin
  perform app.require(e.scope, 'see');
  execute format('select exists (select 1 from app.%I t where t.id = %L and %s)', e.tbl, p_id, app.vis_sql(e)) into v_ok;
  if not v_ok then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('at', c.at, 'field', c.field, 'old', c.old_value, 'new', c.new_value,
                                                       'source', c.source, 'actor', a.name) order by c.id desc)
                   from (select * from app.changelog where entity = e.key and record_id = p_id order by id desc
                         limit least(greatest(coalesce(p_limit, 100), 1), 500)) c
                   left join app.admins a on a.id = c.actor_id), '[]'::jsonb);
end $fn$;

-- ---------------------------------------------------------------------------
-- fields and labels: definitions, read by every staff member, managed with «configure»
create function public.fields_get(p_entity text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_set uuid;
begin
  perform app.require_staff();
  v_set := (select permission_set_id from app.admins where id = app.me());
  return coalesce((select jsonb_agg(to_jsonb(f) || jsonb_build_object('readonly', v_set = any (f.readonly_for)) order by f.entity, f.ord, f.created_at)
                   from app.fields f where (p_entity is null or f.entity = p_entity) and f.archived_at is null
                     and not (v_set = any (f.hidden_for))), '[]'::jsonb);
end $fn$;

create function public.field_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid;
  v_entity text := p_values ->> 'entity';
  v_scope text;
  f app.fields;
begin
  if p_id is not null then
    select entity into v_entity from app.fields where id = p_id;
    if v_entity is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  v_scope := (app.entity(v_entity)).scope;
  v_me := app.require(v_scope, 'configure');
  if p_id is null then
    insert into app.fields (entity, key, label, type, options, quality, from_stage_id, pipeline_ids, hidden_for, readonly_for, description, formula, ord, created_by)
    values (v_entity,
            coalesce(nullif(p_values ->> 'key', ''), 'f_' || substr(md5(random()::text), 1, 8)),
            p_values ->> 'label', p_values ->> 'type', coalesce(p_values -> 'options', '[]'::jsonb),
            coalesce(p_values ->> 'quality', 'optional'), (p_values ->> 'from_stage_id')::uuid,
            case when p_values ? 'pipeline_ids' and jsonb_typeof(p_values -> 'pipeline_ids') = 'array' then array(select jsonb_array_elements_text(p_values -> 'pipeline_ids'))::uuid[] end,
            coalesce(array(select jsonb_array_elements_text(p_values -> 'hidden_for'))::uuid[], '{}'),
            coalesce(array(select jsonb_array_elements_text(p_values -> 'readonly_for'))::uuid[], '{}'),
            p_values ->> 'description', p_values ->> 'formula',
            coalesce((p_values ->> 'ord')::int, (select coalesce(max(ord), 0) + 10 from app.fields where entity = v_entity)), v_me)
    returning * into f;
    perform app.log('field.created', 'field', f.id::text, jsonb_build_object('entity', f.entity, 'key', f.key, 'type', f.type));
  else
    update app.fields set
      label = coalesce(p_values ->> 'label', label),
      options = coalesce(p_values -> 'options', options),
      quality = coalesce(p_values ->> 'quality', quality),
      from_stage_id = case when p_values ? 'from_stage_id' then (p_values ->> 'from_stage_id')::uuid else from_stage_id end,
      pipeline_ids = case when p_values ? 'pipeline_ids' then
                       case when jsonb_typeof(p_values -> 'pipeline_ids') = 'array' then array(select jsonb_array_elements_text(p_values -> 'pipeline_ids'))::uuid[] end
                     else pipeline_ids end,
      hidden_for = case when p_values ? 'hidden_for' then array(select jsonb_array_elements_text(p_values -> 'hidden_for'))::uuid[] else hidden_for end,
      readonly_for = case when p_values ? 'readonly_for' then array(select jsonb_array_elements_text(p_values -> 'readonly_for'))::uuid[] else readonly_for end,
      description = case when p_values ? 'description' then p_values ->> 'description' else description end,
      formula = case when p_values ? 'formula' and type = 'formula' then p_values ->> 'formula' else formula end,
      ord = coalesce((p_values ->> 'ord')::int, ord),
      archived_at = case when (p_values ->> 'archived')::boolean then now() when p_values ? 'archived' then null else archived_at end,
      updated_at = now()
    where id = p_id returning * into f;
    perform app.log('field.updated', 'field', f.id::text, jsonb_build_object('entity', f.entity, 'key', f.key,
                    'changed', to_jsonb(array(select jsonb_object_keys(p_values)))));
  end if;
  return to_jsonb(f);
end $fn$;

create function public.labels_get(p_entity text default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  return coalesce((select jsonb_agg(to_jsonb(l) order by l.entity, l.ord, l.name) from app.labels l
                   where p_entity is null or l.entity = p_entity), '[]'::jsonb);
end $fn$;

create function public.label_save(p_id uuid, p_entity text, p_name text, p_bg text, p_ink text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare l app.labels;
begin
  perform app.require((app.entity(coalesce(p_entity, (select entity from app.labels where id = p_id)))).scope, 'configure');
  if p_id is null then
    insert into app.labels (entity, name, bg, ink, ord) values (p_entity, btrim(p_name), upper(p_bg), upper(p_ink),
      (select coalesce(max(ord), 0) + 10 from app.labels where entity = p_entity)) returning * into l;
  else
    update app.labels set name = btrim(p_name), bg = upper(p_bg), ink = upper(p_ink) where id = p_id returning * into l;
  end if;
  perform app.log('label.saved', 'label', l.id::text, jsonb_build_object('entity', l.entity));
  return to_jsonb(l);
end $fn$;

-- ---------------------------------------------------------------------------
-- ⌘K search across every searchable record type the caller may see; empty q → the caller's recent records
create function public.search(p_q text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff();
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  q text := btrim(coalesce(p_q, ''));
  e app.entities; v_items jsonb; v_out jsonb := '[]'::jsonb; v_cond text; v_digits text;
begin
  if char_length(q) > 100 then q := left(q, 100); end if;
  if q = '' then
    for e in select * from app.entities en where cardinality(en.search) > 0 and app.can(en.scope, 'see') and (en.module is null or app.module_on(en.module)) order by en.ord loop
      execute format('select coalesce(jsonb_agg(jsonb_build_object(''entity'', %L, ''id'', t.id, ''title'', t.%I::text, ''sub'', concat_ws('' · '', %s), ''at'', r.at) order by r.at desc), ''[]''::jsonb)
                      from app.recents r join app.%I t on t.id = r.record_id where r.staff_id = %L and r.entity = %L and t.deleted_at is null and %s',
                     e.key, e.title_col, coalesce((select string_agg(format('t.%I::text', s), ', ') from unnest(e.sub_cols) s), 'null'),
                     e.tbl, v_me, e.key, app.vis_sql(e)) into v_items;
      v_out := v_out || v_items;
    end loop;
    v_out := coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (select x from jsonb_array_elements(v_out) x order by (x ->> 'at') desc limit 6) s), '[]'::jsonb);
    return case when jsonb_array_length(v_out) = 0 then '[]'::jsonb else jsonb_build_array(jsonb_build_object('group', 'recent', 'items', v_out)) end;
  end if;
  v_digits := regexp_replace(q, '\s', '', 'g');
  for e in select * from app.entities en where cardinality(en.search) > 0 and app.can(en.scope, 'see') and (en.module is null or app.module_on(en.module)) order by en.ord loop
    v_cond := (select string_agg(format('replace(t.%I::text, '' '', '''') ilike %L', s, '%' || replace(replace(v_digits, '%', '\%'), '_', '\_') || '%')
                                   || format(' or t.%I::text ilike %L', s, '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%'), ' or ')
               from unnest(e.search) s);
    v_cond := v_cond || format(' or t.custom::text ilike %L', '%' || replace(replace(q, '%', '\%'), '_', '\_') || '%');
    execute format('select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select jsonb_build_object(''entity'', %L, ''id'', t.id, ''title'', t.%I::text, ''sub'', concat_ws('' · '', %s)) x
                    from app.%I t where t.deleted_at is null and (%s) and %s %s order by t.updated_at desc limit 4) s',
                   e.key, e.title_col, coalesce((select string_agg(format('t.%I::text', s), ', ') from unnest(e.sub_cols) s), 'null'),
                   e.tbl, v_cond, app.vis_sql(e), case when v_sandbox then '' else 'and not t.is_sample' end) into v_items;
    if jsonb_array_length(v_items) > 0 then
      v_out := v_out || jsonb_build_array(jsonb_build_object('group', e.key, 'items', v_items));
    end if;
  end loop;
  return v_out;
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['entities', 'entity_columns', 'fields', 'labels', 'organizations', 'people', 'recents'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.entity(text)', 'app.take_reason(text)', 'app.lit(jsonb, text)', 'app.check_custom(text, jsonb)',
                           'app.vis_sql(app.entities)', 'app.filter_sql(app.entities, jsonb)', 'app.refs_sql(app.entities)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.rec_list(text, jsonb)', 'public.rec_group(text, text, jsonb, text)', 'public.rec_get(text, uuid, text)',
                           'public.rec_save(text, uuid, jsonb, int, text, text)', 'public.rec_bulk(text, uuid[], jsonb, text)',
                           'public.rec_delete(text, uuid[], text)', 'public.rec_restore(text, uuid[])', 'public.rec_history(text, uuid, int)',
                           'public.fields_get(text)', 'public.field_save(uuid, jsonb)', 'public.labels_get(text)',
                           'public.label_save(uuid, text, text, text, text)', 'public.search(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
