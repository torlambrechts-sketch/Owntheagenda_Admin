-- 0024_insights.sql — reports, dashboards, goals and forecasts (Insights, INS-01..10).
--
-- A report is a definition, never numbers: an entity, a measure, a dimension to view by (and one to
-- segment by), filters in the list syntax (0006, with OR groups and idle days from 0023), a period and a
-- chart. app.report_run compiles it over a whitelist — the entity registry's columns, the standard
-- dimensions below and custom fields with the type the registry gives — and runs it inside the caller's
-- visibility. Without «See reports of others» a staff member sees their own records only. A drill-down
-- re-runs the same definition with the segment as one more filter, so exported rows are the rows behind
-- the chart (INS-08).
--
-- Sums of money count NOK only; a record in another currency is counted apart («excluded_currency»)
-- until exchange rates exist (SF-32 needs a rate source). Goals and forecasts are computed when read.
-- The public live link waits for the public host (D-28); PNG and PDF are the browser's print.

create table app.reports (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references app.admins (id) on delete set null,
  name        text not null check (char_length(btrim(name)) between 1 and 120),
  definition  jsonb not null check (jsonb_typeof(definition) = 'object'),
  source      text not null default 'builder' check (source in ('builder', 'ai', 'template')),
  is_template boolean not null default false,
  is_sample   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table app.dashboards (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references app.admins (id) on delete set null,
  name          text not null check (char_length(btrim(name)) between 1 and 120),
  template_role text check (template_role is null or template_role in ('default', 'sales_manager', 'sales_rep', 'marketing')),
  filters       jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  is_sample     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table app.dashboard_tiles (
  dashboard_id uuid not null references app.dashboards (id) on delete cascade,
  report_id    uuid not null references app.reports (id) on delete cascade,
  position     int not null default 0,
  span         smallint not null default 6 check (span between 3 and 12),
  primary key (dashboard_id, report_id)
);

create table app.dashboard_shares (
  dashboard_id uuid not null references app.dashboards (id) on delete cascade,
  grantee_kind text not null check (grantee_kind in ('staff', 'team', 'group')),
  grantee_id   uuid not null,
  role         text not null default 'viewer' check (role in ('viewer', 'editor')),
  created_by   uuid references app.admins (id) on delete set null,
  created_at   timestamptz not null default now(),
  primary key (dashboard_id, grantee_kind, grantee_id)
);

create table app.goals (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(btrim(name)) between 1 and 120),
  kind          text not null check (kind in ('deals_added', 'deals_progressed', 'deals_won', 'activities_added', 'activities_completed', 'forecast_weighted')),
  assignee_kind text not null check (assignee_kind in ('staff', 'team', 'company')),
  assignee_id   uuid,
  pipeline_id   uuid references app.pipelines (id) on delete set null,
  activity_type_id uuid references app.activity_types (id) on delete set null,
  frequency     text not null check (frequency in ('weekly', 'monthly', 'quarterly', 'yearly')),
  starts_on     date not null default current_date,
  ends_on       date,
  target_count  int check (target_count is null or target_count > 0),
  target_value  numeric(14, 2) check (target_value is null or target_value > 0),
  created_by    uuid references app.admins (id) on delete set null,
  is_sample     boolean not null default false,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check ((assignee_kind = 'company') = (assignee_id is null)),
  check ((target_count is null) <> (target_value is null)),
  check (ends_on is null or ends_on >= starts_on)
);

-- the open pipeline at the end of each day, for «Open pipeline» against the period before
create table app.pipeline_snapshots_daily (
  day         date not null,
  pipeline_id uuid not null references app.pipelines (id) on delete cascade,
  stage_id    uuid not null references app.stages (id) on delete cascade,
  owner_id    uuid,
  open_count  int not null,
  open_value  numeric not null,
  is_sample   boolean not null default false,
  primary key (day, pipeline_id, stage_id, owner_id, is_sample)
);

create function app.snapshot_pipeline() returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.pipeline_snapshots_daily (day, pipeline_id, stage_id, owner_id, open_count, open_value, is_sample)
  select current_date, d.pipeline_id, d.stage_id, coalesce(d.owner_id, '00000000-0000-0000-0000-000000000000'::uuid), count(*),
         coalesce(sum(d.value) filter (where d.currency = 'NOK'), 0), d.is_sample
  from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null
  group by d.pipeline_id, d.stage_id, d.owner_id, d.is_sample
  on conflict (day, pipeline_id, stage_id, owner_id, is_sample) do update set open_count = excluded.open_count, open_value = excluded.open_value;
$fn$;
select cron.schedule('platform-pipeline-snapshot', '55 23 * * *', 'select app.snapshot_pipeline()');

-- ---------------------------------------------------------------------------
-- the report compiler
-- a period → [from, to) in Europe/Oslo; kind: month | quarter | year | last_30 | last_90 | last_365 | custom | all
create function app.period_bounds(p_period jsonb, p_shift int default 0) returns tstzrange
  language plpgsql stable set search_path = ''
as $fn$
declare k text := coalesce(p_period ->> 'kind', 'all'); n timestamp := now() at time zone 'Europe/Oslo'; a timestamp; b timestamp; len interval;
begin
  case k
    when 'month' then a := date_trunc('month', n); b := a + interval '1 month';
    when 'quarter' then a := date_trunc('quarter', n); b := a + interval '3 months';
    when 'year' then a := date_trunc('year', n); b := a + interval '1 year';
    when 'last_30' then b := date_trunc('day', n) + interval '1 day'; a := b - interval '30 days';
    when 'last_90' then b := date_trunc('day', n) + interval '1 day'; a := b - interval '90 days';
    when 'last_365' then b := date_trunc('day', n) + interval '1 day'; a := b - interval '365 days';
    when 'custom' then a := (p_period ->> 'from')::date; b := (p_period ->> 'to')::date + 1;
    else return null;
  end case;
  if p_shift <> 0 then
    len := case k when 'month' then interval '1 month' when 'quarter' then interval '3 months' when 'year' then interval '1 year' else b - a end;
    a := a + p_shift * len; b := b + p_shift * len;
  end if;
  return tstzrange(a at time zone 'Europe/Oslo', b at time zone 'Europe/Oslo', '[)');
end $fn$;

-- a dimension: {expr (the grouping value as text), label (sql over the value v), ord (sql), from (an extra join)}
create function app.report_dim(e app.entities, p_dim text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare ftype text;
begin
  if p_dim is null then return null; end if;
  if p_dim = 'owner' and e.owned then
    return jsonb_build_object('expr', 't.owner_id::text', 'label', '(select a.name from app.admins a where a.id::text = v)');
  elsif p_dim = 'stage' and e.key = 'deal' then
    return jsonb_build_object('expr', 't.stage_id::text', 'label', '(select s.name from app.stages s where s.id::text = v)', 'ord', '(select s.ord from app.stages s where s.id::text = v)');
  elsif p_dim = 'pipeline' and e.key = 'deal' then
    return jsonb_build_object('expr', 't.pipeline_id::text', 'label', '(select p.name from app.pipelines p where p.id::text = v)');
  elsif p_dim = 'type' and e.key = 'activity' then
    return jsonb_build_object('expr', 't.type_id::text', 'label', '(select x.name from app.activity_types x where x.id::text = v)', 'ord', '(select x.ord from app.activity_types x where x.id::text = v)');
  elsif p_dim = 'label' then
    return jsonb_build_object('expr', 'lbl.id::text', 'label', '(select l.name from app.labels l where l.id::text = v)',
                              'from', 'left join lateral unnest(t.labels) lbl(id) on true');
  elsif p_dim in ('created_month', 'won_month', 'done_month', 'close_month') then
    return jsonb_build_object('expr', format('to_char(date_trunc(''month'', (t.%I) at time zone ''Europe/Oslo''), ''YYYY-MM'')',
                                             case p_dim when 'created_month' then 'created_at' when 'won_month' then 'won_at' when 'done_month' then 'done_at' else 'expected_close_date' end),
                              'label', 'v', 'ord', 'v');
  elsif p_dim like 'custom.%' then
    select type into ftype from app.fields where entity = e.key and key = substr(p_dim, 8) and archived_at is null;
    if ftype is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_by'; end if;
    return jsonb_build_object('expr', format('(t.custom ->> %L)', substr(p_dim, 8)), 'label', 'v');
  elsif exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = p_dim and c.kind in ('text', 'boolean', 'int') and c.ref is null) then
    return jsonb_build_object('expr', format('t.%I::text', p_dim), 'label', 'v');
  elsif exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = p_dim and c.ref is not null) then
    return jsonb_build_object('expr', format('t.%I::text', p_dim),
                              'label', (select format('(select r.%I::text from app.%I r where r.id::text = v)', re.title_col, re.tbl)
                                        from app.entity_columns c join app.entities re on re.key = c.ref where c.entity = e.key and c.col = p_dim));
  end if;
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'group_by';
end $fn$;

-- the measure as SQL: count | sum | avg | weighted | cycle_days, over a field
create function app.report_measure(e app.entities, p_measure jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare fn text := coalesce(p_measure ->> 'fn', 'count'); f text := p_measure ->> 'field'; col text; ftype text;
begin
  if fn = 'count' then return 'count(*)::numeric'; end if;
  if fn = 'weighted' then
    if e.key <> 'deal' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure'; end if;
    return 'coalesce(sum(t.value * (select s.probability from app.stages s where s.id = t.stage_id) / 100.0) filter (where t.currency = ''NOK''), 0)';
  end if;
  if fn = 'cycle_days' then
    if e.key <> 'deal' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure'; end if;
    return 'round(avg(extract(epoch from t.won_at - t.created_at) / 86400) filter (where t.won_at is not null), 1)';
  end if;
  if fn not in ('sum', 'avg') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure'; end if;
  if f like 'custom.%' then
    select type into ftype from app.fields where entity = e.key and key = substr(f, 8) and archived_at is null;
    if ftype is distinct from 'numerical' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure.field'; end if;
    col := format('(t.custom ->> %L)::numeric', substr(f, 8));
  elsif exists (select 1 from app.entity_columns c where c.entity = e.key and c.col = f and c.kind in ('numeric', 'int')) then
    col := format('t.%I', f);
  else
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure.field';
  end if;
  -- money: NOK only (no exchange rates yet)
  if f = 'value' and e.key in ('deal', 'lead') then
    return format('coalesce(%s(%s) filter (where t.currency = ''NOK''), 0)', fn, col);
  end if;
  return format('coalesce(%s(%s), 0)', fn, col);
end $fn$;

-- validate a definition; returns the entity
create function app.report_check(p_def jsonb) returns app.entities
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities;
begin
  if p_def is null or jsonb_typeof(p_def) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'definition'; end if;
  if p_def ->> 'entity' not in ('deal', 'activity', 'lead', 'person', 'organization') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity';
  end if;
  e := app.entity(p_def ->> 'entity');
  if coalesce(p_def ->> 'type', 'performance') not in ('performance', 'conversion', 'duration', 'progress', 'products') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type';
  end if;
  if coalesce(p_def ->> 'chart', 'column') not in ('column', 'bar', 'pie', 'scorecard', 'table', 'stacked') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'chart';
  end if;
  if p_def ? 'period' and coalesce(p_def -> 'period' ->> 'kind', 'all') not in ('month', 'quarter', 'year', 'last_30', 'last_90', 'last_365', 'custom', 'all') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'period';
  end if;
  if p_def -> 'period' ->> 'field' is not null and not exists (
       select 1 from app.entity_columns c where c.entity = e.key and c.col = p_def -> 'period' ->> 'field' and c.kind in ('date', 'timestamptz'))
     and p_def -> 'period' ->> 'field' not in ('created_at', 'updated_at') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'period.field';
  end if;
  return e;
end $fn$;

-- the WHERE clause of a definition: visibility, sandbox, own records without «See reports of others»,
-- filters, the period (shifted by p_shift periods) and extra filters
create function app.report_where(e app.entities, p_def jsonb, p_extra jsonb, p_shift int) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare w text; r tstzrange; pf text := coalesce(p_def -> 'period' ->> 'field', 'created_at');
begin
  w := format('t.deleted_at is null and %s', app.vis_sql(e));
  if not coalesce((select sandbox from app.admins where id = app.me()), false) then w := w || ' and not t.is_sample'; end if;
  if e.owned and not app.can(e.scope, 'reports_others') then w := w || format(' and t.owner_id = %L', app.me()); end if;
  if e.key = 'deal' and not coalesce((p_def ->> 'include_archived')::boolean, false) then w := w || ' and t.archived_at is null'; end if;
  w := w || app.filter_sql(e, p_def -> 'filters') || app.filter_sql(e, p_extra);
  r := app.period_bounds(p_def -> 'period', p_shift);
  if r is not null then
    w := w || format(' and (t.%I)::timestamptz >= %L and (t.%I)::timestamptz < %L', pf, lower(r), pf, upper(r));
  end if;
  return w;
end $fn$;

-- stage conversion: of the deals that entered stage i in the period, the share later in stage i+1 (the
-- last stage: the share won)
create function app.report_conversion(p_def jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity('deal'); v_pipe uuid := (p_def ->> 'pipeline_id')::uuid; r tstzrange := app.period_bounds(coalesce(p_def -> 'period', '{"kind":"last_90"}'::jsonb), 0);
        v_rows jsonb; w text;
begin
  if v_pipe is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id'; end if;
  w := app.report_where(e, p_def - 'period', null, 0);
  execute format($q$
    with st as (select s.id, s.name, s.ord, lead(s.id) over (order by s.ord) nxt from app.stages s where s.pipeline_id = %L),
         d as (select t.id, t.status from app.deals t where t.pipeline_id = %L and %s),
         e1 as (select h.deal_id, h.stage_id, h.entered_at from app.deal_stage_history h join d on d.id = h.deal_id where h.entered_at >= %L and h.entered_at < %L)
    select coalesce(jsonb_agg(jsonb_build_object('key', st.id, 'label', st.name, 'entered', x.entered, 'value',
             case when x.entered = 0 then null else round(100.0 * x.advanced / x.entered, 1) end) order by st.ord), '[]'::jsonb)
    from st cross join lateral (
      select count(distinct e1.deal_id) entered,
             count(distinct e1.deal_id) filter (where (st.nxt is not null and exists (select 1 from app.deal_stage_history h2 where h2.deal_id = e1.deal_id and h2.stage_id = st.nxt and h2.entered_at > e1.entered_at))
                                               or (st.nxt is null and exists (select 1 from d where d.id = e1.deal_id and d.status = 'won'))) advanced
      from e1 where e1.stage_id = st.id) x$q$, v_pipe, v_pipe, w, lower(r), upper(r)) into v_rows;
  return jsonb_build_object('rows', v_rows, 'unit', 'percent');
end $fn$;

-- run a definition → {rows: [{key, label, segment, segment_label, value}], total, previous, excluded_currency}
create function app.report_run(p_def jsonb, p_extra jsonb default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  e app.entities := app.report_check(p_def); g jsonb; s jsonb; m text; w text; joins text := ''; v_rows jsonb; v_total numeric; v_prev numeric; v_excl int := 0;
  v_sql text;
begin
  if p_def ->> 'type' = 'conversion' then return app.report_conversion(p_def); end if;
  g := app.report_dim(e, p_def ->> 'group_by');
  s := app.report_dim(e, p_def ->> 'segment_by');
  if s is not null and s ? 'from' and g ? 'from' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'segment_by'; end if;
  m := app.report_measure(e, coalesce(p_def -> 'measure', '{"fn":"count"}'::jsonb));
  if p_def ->> 'type' = 'duration' and e.key = 'deal' then m := app.report_measure(e, '{"fn":"cycle_days"}'); end if;
  w := app.report_where(e, p_def, p_extra, 0);
  joins := coalesce(g ->> 'from', '') || ' ' || coalesce(s ->> 'from', '');
  execute format('select %s from app.%I t %s where %s', m, e.tbl, joins, w) into v_total;
  if app.period_bounds(p_def -> 'period', 0) is not null then
    execute format('select %s from app.%I t %s where %s', m, e.tbl, joins, app.report_where(e, p_def, p_extra, -1)) into v_prev;
  elsif e.key = 'deal' and p_def -> 'filters' @> '[{"f":"status","op":"eq","v":"open"}]' and m like '%sum(t.value%' then
    -- open pipeline against 30 days ago, from the nightly snapshots
    v_prev := (select sum(open_value) from app.pipeline_snapshots_daily where day = current_date - 30 and not is_sample);
  end if;
  if e.key in ('deal', 'lead') and m like '%currency = ''NOK''%' then
    execute format('select count(*) from app.%I t where %s and t.currency <> ''NOK''', e.tbl, w) into v_excl;
  end if;
  if g is not null then
    v_sql := format($q$select coalesce(jsonb_agg(jsonb_build_object('key', k, 'label', lbl, 'segment', sg, 'segment_label', sgl, 'value', val) order by %s), '[]'::jsonb)
      from (select x.k, (select %s from (select x.k v) z) lbl, x.sg, (select %s from (select x.sg v) z) sgl, x.val, (select %s from (select x.k v) z) o
            from (select %s k, %s sg, %s val from app.%I t %s where %s group by 1, 2) x) y$q$,
      case when coalesce(p_def ->> 'sort', '') = 'label' or g ? 'ord' then 'o nulls last, lbl' else 'val desc nulls last' end,
      g ->> 'label', coalesce(s ->> 'label', 'null'), coalesce(g ->> 'ord', 'null'),
      g ->> 'expr', coalesce(s ->> 'expr', 'null::text'), m, e.tbl, joins, w);
    execute v_sql into v_rows;
  end if;
  return jsonb_build_object('rows', coalesce(v_rows, '[]'::jsonb), 'total', v_total, 'previous', v_prev, 'excluded_currency', v_excl,
                            'unit', case when m like '%cycle%' or p_def -> 'measure' ->> 'fn' = 'cycle_days' then 'days'
                                         when m like '%t.value%' then 'nok' else 'count' end);
end $fn$;

-- the rows behind a segment: {key, segment} of a row the chart shows
create function app.report_rows(p_def jsonb, p_segment jsonb, p_limit int) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.report_check(p_def); g jsonb := app.report_dim(e, p_def ->> 'group_by'); s jsonb := app.report_dim(e, p_def ->> 'segment_by');
        w text; joins text; extra text := ''; v_rows jsonb; vcol text;
begin
  w := app.report_where(e, p_def, null, 0);
  joins := coalesce(g ->> 'from', '') || ' ' || coalesce(s ->> 'from', '');
  if g is not null and p_segment ? 'key' then
    extra := extra || case when p_segment ->> 'key' is null then format(' and %s is null', g ->> 'expr') else format(' and %s = %L', g ->> 'expr', p_segment ->> 'key') end;
  end if;
  if s is not null and p_segment ? 'segment' then
    extra := extra || case when p_segment ->> 'segment' is null then format(' and %s is null', s ->> 'expr') else format(' and %s = %L', s ->> 'expr', p_segment ->> 'segment') end;
  end if;
  vcol := case when e.key in ('deal', 'lead') then 't.value' else 'null::numeric' end;
  execute format($q$select coalesce(jsonb_agg(x order by x ->> 'title'), '[]'::jsonb) from (
      select distinct jsonb_build_object('id', t.id, 'title', t.%I::text, 'owner', %s, 'value', %s, 'currency', %s, 'created_at', t.created_at) x
      from app.%I t %s where %s %s limit %s) z$q$,
    e.title_col, case when e.owned then '(select a.name from app.admins a where a.id = t.owner_id)' else 'null' end, vcol,
    case when e.key in ('deal', 'lead') then 't.currency' else 'null' end, e.tbl, joins, w, extra, least(greatest(coalesce(p_limit, 200), 1), 5000)) into v_rows;
  return v_rows;
end $fn$;

-- ---------------------------------------------------------------------------
-- reports, public
create function public.report_run(p_def jsonb, p_extra jsonb default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.report_check(p_def);
begin
  perform app.require(e.scope, 'see');
  return app.report_run(p_def, p_extra);
end $fn$;

create function public.report_drill(p_def jsonb, p_segment jsonb default '{}'::jsonb, p_limit int default 200) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.report_check(p_def); v jsonb;
begin
  perform app.require(e.scope, 'see');
  v := app.report_rows(p_def, coalesce(p_segment, '{}'::jsonb), p_limit);
  perform app.log('report.drilled', e.key, null, jsonb_build_object('rows', jsonb_array_length(v)));
  return v;
end $fn$;

-- the rows for an export (CSV/XLSX built by the app), with the export right, audited
create function public.report_export(p_def jsonb, p_segment jsonb default '{}'::jsonb, p_format text default 'csv') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare e app.entities := app.report_check(p_def); v jsonb;
begin
  perform app.require(e.scope, 'export');
  if p_format not in ('csv', 'xlsx') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'format'; end if;
  v := app.report_rows(p_def, coalesce(p_segment, '{}'::jsonb), 5000);
  perform app.log('report.exported', e.key, null, jsonb_build_object('rows', jsonb_array_length(v), 'format', p_format));
  return v;
end $fn$;

create function public.reports_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'definition', r.definition, 'source', r.source, 'owner_id', r.owner_id,
                                                       'mine', r.owner_id = v_me, 'updated_at', r.updated_at) order by r.updated_at desc)
                   from app.reports r where r.deleted_at is null and not r.is_template
                     and (r.owner_id = v_me or exists (select 1 from app.dashboard_tiles dt where dt.report_id = r.id and app.dashboard_role(dt.dashboard_id) is not null))), '[]'::jsonb);
end $fn$;

-- the role a staff member has on a dashboard: owner, editor, viewer, or null
create function app.dashboard_role(p_dashboard uuid) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case
    when d.template_role is not null then 'viewer'
    when d.owner_id = app.me() then 'owner'
    when exists (select 1 from app.dashboard_shares s where s.dashboard_id = d.id and s.role = 'editor' and (
           (s.grantee_kind = 'staff' and s.grantee_id = app.me())
        or (s.grantee_kind = 'team' and exists (select 1 from app.team_members tm where tm.team_id = s.grantee_id and tm.staff_id = app.me()))
        or (s.grantee_kind = 'group' and (select a.group_id from app.admins a where a.id = app.me()) in (select app.group_and_below(s.grantee_id))))) then 'editor'
    when exists (select 1 from app.dashboard_shares s where s.dashboard_id = d.id and (
           (s.grantee_kind = 'staff' and s.grantee_id = app.me())
        or (s.grantee_kind = 'team' and exists (select 1 from app.team_members tm where tm.team_id = s.grantee_id and tm.staff_id = app.me()))
        or (s.grantee_kind = 'group' and (select a.group_id from app.admins a where a.id = app.me()) in (select app.group_and_below(s.grantee_id))))) then 'viewer'
    end
  from app.dashboards d where d.id = p_dashboard and d.deleted_at is null
$fn$;

create function public.report_save(p_id uuid, p_name text, p_def jsonb, p_source text default 'builder') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); e app.entities := app.report_check(p_def); v_id uuid; v_limit numeric := app.count_limit();
begin
  perform app.require(e.scope, 'see');
  perform app.report_run(p_def, null);                 -- it must compile
  if p_source not in ('builder', 'ai') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
  if p_id is null then
    if v_limit is not null and (select count(*) from app.reports where owner_id = v_me and deleted_at is null and not is_template) >= v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'limit';
    end if;
    insert into app.reports (owner_id, name, definition, source, is_sample) values (v_me, btrim(p_name), p_def, p_source, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.reports set name = btrim(p_name), definition = p_def, updated_at = now()
    where id = p_id and deleted_at is null and (owner_id = v_me or exists (select 1 from app.dashboard_tiles dt where dt.report_id = p_id and app.dashboard_role(dt.dashboard_id) in ('owner', 'editor')))
    returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  perform app.log(case when p_id is null then 'report.created' else 'report.updated' end, 'report', v_id::text, jsonb_build_object('entity', e.key));
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.report_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  update app.reports set deleted_at = now() where id = p_id and owner_id = v_me and deleted_at is null and not is_template;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  delete from app.dashboard_tiles where report_id = p_id and dashboard_id in (select id from app.dashboards where owner_id = v_me);
  perform app.log('report.deleted', 'report', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- dashboards
create function public.dashboards_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'template_role', d.template_role, 'role', app.dashboard_role(d.id),
                                                       'owner', (select a.name from app.admins a where a.id = d.owner_id)) order by d.template_role is null, d.created_at)
                   from app.dashboards d where d.deleted_at is null and app.dashboard_role(d.id) is not null), '[]'::jsonb);
end $fn$;

-- a dashboard with each tile's report run for the viewer (their own visibility)
create function public.dashboard_get(p_id uuid, p_period jsonb default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); d app.dashboards; v_role text := app.dashboard_role(p_id); t record; v_tiles jsonb := '[]'::jsonb; v_def jsonb; v_res jsonb;
begin
  select * into d from app.dashboards where id = p_id and deleted_at is null;
  if not found or v_role is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  for t in select dt.position, dt.span, r.id, r.name, r.definition from app.dashboard_tiles dt join app.reports r on r.id = dt.report_id
           where dt.dashboard_id = p_id and r.deleted_at is null order by dt.position loop
    v_def := t.definition || case when p_period is not null and t.definition ? 'period' then jsonb_build_object('period', (t.definition -> 'period') || p_period) else '{}'::jsonb end;
    begin
      if app.can((select e.scope from app.entities e where e.key = v_def ->> 'entity'), 'see') then
        v_res := app.report_run(v_def, null);
      else
        v_res := jsonb_build_object('error', 'forbidden');
      end if;
    exception when others then
      v_res := jsonb_build_object('error', case when sqlerrm in ('invalid', 'module_off', 'forbidden') then sqlerrm else 'failed' end);
    end;
    v_tiles := v_tiles || jsonb_build_array(jsonb_build_object('report_id', t.id, 'name', t.name, 'definition', v_def, 'position', t.position, 'span', t.span, 'result', v_res));
  end loop;
  return jsonb_build_object('id', d.id, 'name', d.name, 'template_role', d.template_role, 'role', v_role, 'tiles', v_tiles,
    'shares', case when v_role = 'owner' then coalesce((select jsonb_agg(jsonb_build_object('kind', s.grantee_kind, 'id', s.grantee_id, 'role', s.role,
                     'name', case s.grantee_kind when 'staff' then (select a.name from app.admins a where a.id = s.grantee_id)
                                                 when 'team' then (select tm.name from app.teams tm where tm.id = s.grantee_id)
                                                 else (select g.name from app.visibility_groups g where g.id = s.grantee_id) end))
                   from app.dashboard_shares s where s.dashboard_id = p_id), '[]'::jsonb) end);
end $fn$;

-- create (p_id null) or rename, and lay out: tiles [{report_id, position, span}]
create function public.dashboard_save(p_id uuid, p_name text, p_tiles jsonb default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_id uuid := p_id; x jsonb;
begin
  if p_id is null then
    insert into app.dashboards (owner_id, name, is_sample) values (v_me, btrim(p_name), (select sandbox from app.admins where id = v_me)) returning id into v_id;
  else
    if app.dashboard_role(p_id) not in ('owner', 'editor') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'dashboard'; end if;
    update app.dashboards set name = coalesce(nullif(btrim(p_name), ''), name), updated_at = now() where id = p_id;
  end if;
  if p_tiles is not null then
    if jsonb_typeof(p_tiles) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'tiles'; end if;
    delete from app.dashboard_tiles where dashboard_id = v_id;
    for x in select * from jsonb_array_elements(p_tiles) loop
      if not exists (select 1 from app.reports r where r.id = (x ->> 'report_id')::uuid and r.deleted_at is null
                     and (r.owner_id = v_me or r.is_template or exists (select 1 from app.dashboard_tiles dt where dt.report_id = r.id and app.dashboard_role(dt.dashboard_id) is not null))) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'report';
      end if;
      insert into app.dashboard_tiles (dashboard_id, report_id, position, span)
      values (v_id, (x ->> 'report_id')::uuid, coalesce((x ->> 'position')::int, 0), coalesce((x ->> 'span')::smallint, 6));
    end loop;
  end if;
  perform app.log(case when p_id is null then 'dashboard.created' else 'dashboard.updated' end, 'dashboard', v_id::text, null);
  return jsonb_build_object('id', v_id);
end $fn$;

-- duplicate: the dashboard, its tiles and their reports, to the caller as «<name> (copy)» (p_name is the new name)
create function public.dashboard_duplicate(p_id uuid, p_name text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_new uuid; t record; v_rep uuid;
begin
  if app.dashboard_role(p_id) is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  insert into app.dashboards (owner_id, name, filters, is_sample) select v_me, btrim(p_name), filters, (select sandbox from app.admins where id = v_me) from app.dashboards where id = p_id
  returning id into v_new;
  for t in select dt.position, dt.span, r.name, r.definition from app.dashboard_tiles dt join app.reports r on r.id = dt.report_id where dt.dashboard_id = p_id and r.deleted_at is null loop
    insert into app.reports (owner_id, name, definition, source) values (v_me, t.name, t.definition, 'builder') returning id into v_rep;
    insert into app.dashboard_tiles (dashboard_id, report_id, position, span) values (v_new, v_rep, t.position, t.span);
  end loop;
  perform app.log('dashboard.duplicated', 'dashboard', v_new::text, jsonb_build_object('from', p_id));
  return jsonb_build_object('id', v_new);
end $fn$;

create function public.dashboard_share(p_id uuid, p_kind text, p_grantee uuid, p_role text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_ok boolean;
begin
  if app.dashboard_role(p_id) is distinct from 'owner' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'dashboard'; end if;
  if p_kind not in ('staff', 'team', 'group') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'kind'; end if;
  if p_role is null then
    delete from app.dashboard_shares where dashboard_id = p_id and grantee_kind = p_kind and grantee_id = p_grantee;
  else
    if p_role not in ('viewer', 'editor') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'role'; end if;
    v_ok := case p_kind when 'staff' then exists (select 1 from app.admins where id = p_grantee and active)
                        when 'team' then exists (select 1 from app.teams where id = p_grantee)
                        else exists (select 1 from app.visibility_groups where id = p_grantee) end;
    if not v_ok then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'grantee'; end if;
    insert into app.dashboard_shares (dashboard_id, grantee_kind, grantee_id, role, created_by) values (p_id, p_kind, p_grantee, p_role, v_me)
    on conflict (dashboard_id, grantee_kind, grantee_id) do update set role = excluded.role;
  end if;
  perform app.log('dashboard.shared', 'dashboard', p_id::text, jsonb_build_object('kind', p_kind, 'role', p_role));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.dashboard_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
begin
  perform app.require_staff();
  if app.dashboard_role(p_id) is distinct from 'owner' then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'dashboard'; end if;
  update app.dashboards set deleted_at = now() where id = p_id;
  perform app.log('dashboard.deleted', 'dashboard', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- goals (INS-05): progress is the count or sum of matching records in the current interval; pace is
-- progress against the share of the interval gone
create function app.goal_interval(g app.goals) returns tstzrange
  language plpgsql stable set search_path = ''
as $fn$
declare n date := (now() at time zone 'Europe/Oslo')::date; a date;
begin
  a := case g.frequency when 'weekly' then date_trunc('week', n)::date when 'monthly' then date_trunc('month', n)::date
                        when 'quarterly' then date_trunc('quarter', n)::date else date_trunc('year', n)::date end;
  a := greatest(a, g.starts_on);
  return tstzrange(a::timestamp at time zone 'Europe/Oslo',
                   (case g.frequency when 'weekly' then date_trunc('week', n) + interval '1 week' when 'monthly' then date_trunc('month', n) + interval '1 month'
                                     when 'quarterly' then date_trunc('quarter', n) + interval '3 months' else date_trunc('year', n) + interval '1 year' end) at time zone 'Europe/Oslo', '[)');
end $fn$;

create function app.goal_owners(g app.goals) returns uuid[]
  language sql stable security definer set search_path = ''
as $fn$
  select case g.assignee_kind when 'staff' then array[g.assignee_id]
                              when 'team' then array(select tm.staff_id from app.team_members tm where tm.team_id = g.assignee_id)
                              else null end
$fn$;

create function app.goal_progress(g app.goals) returns numeric
  language plpgsql stable security definer set search_path = ''
as $fn$
declare r tstzrange := app.goal_interval(g); o uuid[] := app.goal_owners(g); v numeric; byval boolean := g.target_value is not null;
begin
  case g.kind
    when 'deals_added' then
      select case when byval then coalesce(sum(value) filter (where currency = 'NOK'), 0) else count(*) end into v from app.deals
      where deleted_at is null and not is_sample and created_at <@ r and (o is null or owner_id = any (o)) and (g.pipeline_id is null or pipeline_id = g.pipeline_id);
    when 'deals_won' then
      select case when byval then coalesce(sum(value) filter (where currency = 'NOK'), 0) else count(*) end into v from app.deals
      where deleted_at is null and not is_sample and status = 'won' and won_at <@ r and (o is null or owner_id = any (o)) and (g.pipeline_id is null or pipeline_id = g.pipeline_id);
    when 'deals_progressed' then
      select count(distinct h.deal_id) into v from app.deal_stage_history h join app.deals d on d.id = h.deal_id
      where d.deleted_at is null and not d.is_sample and h.entered_at <@ r and h.entered_at > d.created_at + interval '1 minute'
        and (o is null or d.owner_id = any (o)) and (g.pipeline_id is null or d.pipeline_id = g.pipeline_id);
    when 'activities_added' then
      select count(*) into v from app.activities where deleted_at is null and not is_sample and created_at <@ r and (o is null or owner_id = any (o))
        and (g.activity_type_id is null or type_id = g.activity_type_id);
    when 'activities_completed' then
      select count(*) into v from app.activities where deleted_at is null and not is_sample and done and done_at <@ r and (o is null or owner_id = any (o))
        and (g.activity_type_id is null or type_id = g.activity_type_id);
    when 'forecast_weighted' then
      select coalesce(sum(d.value * s.probability / 100.0) filter (where d.currency = 'NOK'), 0) into v from app.deals d join app.stages s on s.id = d.stage_id
      where d.deleted_at is null and not d.is_sample and d.status = 'open' and d.expected_close_date >= lower(r)::date and d.expected_close_date < upper(r)::date
        and (o is null or d.owner_id = any (o)) and (g.pipeline_id is null or d.pipeline_id = g.pipeline_id);
  end case;
  return v;
end $fn$;

create function public.goals_get() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_all boolean := app.can('deals', 'reports_others');
begin
  return coalesce((select jsonb_agg(x order by x ->> 'name') from (
    select jsonb_build_object('id', g.id, 'name', g.name, 'kind', g.kind, 'assignee_kind', g.assignee_kind, 'assignee_id', g.assignee_id,
      'assignee', case g.assignee_kind when 'staff' then (select a.name from app.admins a where a.id = g.assignee_id)
                                       when 'team' then (select t.name from app.teams t where t.id = g.assignee_id) end,
      'pipeline_id', g.pipeline_id, 'activity_type_id', g.activity_type_id, 'frequency', g.frequency, 'starts_on', g.starts_on, 'ends_on', g.ends_on,
      'target', coalesce(g.target_value, g.target_count), 'by_value', g.target_value is not null,
      'current', app.goal_progress(g),
      'interval_start', lower(app.goal_interval(g)), 'interval_end', upper(app.goal_interval(g)),
      'elapsed_pct', round(100.0 * extract(epoch from now() - lower(app.goal_interval(g))) / nullif(extract(epoch from upper(app.goal_interval(g)) - lower(app.goal_interval(g))), 0), 1),
      'mine', g.created_by = v_me) x
    from app.goals g where g.deleted_at is null and (g.ends_on is null or g.ends_on >= current_date)
      and (v_all or g.assignee_kind = 'company' or (g.assignee_kind = 'staff' and g.assignee_id = v_me)
           or (g.assignee_kind = 'team' and exists (select 1 from app.team_members tm where tm.team_id = g.assignee_id and tm.staff_id = v_me)))) s), '[]'::jsonb);
end $fn$;

create function public.goal_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); v_id uuid; v_kind text := p_values ->> 'assignee_kind'; v_who uuid := (p_values ->> 'assignee_id')::uuid;
begin
  -- a goal for oneself needs nothing more; for a team or the company it needs «Manage pipelines and fields»
  if not (v_kind = 'staff' and v_who = v_me) then perform app.require('deals', 'configure'); end if;
  if p_id is null then
    insert into app.goals (name, kind, assignee_kind, assignee_id, pipeline_id, activity_type_id, frequency, starts_on, ends_on, target_count, target_value, created_by, is_sample)
    values (btrim(p_values ->> 'name'), p_values ->> 'kind', v_kind, v_who, (p_values ->> 'pipeline_id')::uuid, (p_values ->> 'activity_type_id')::uuid,
            p_values ->> 'frequency', coalesce((p_values ->> 'starts_on')::date, current_date), (p_values ->> 'ends_on')::date,
            (p_values ->> 'target_count')::int, (p_values ->> 'target_value')::numeric, v_me, (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.goals set name = btrim(p_values ->> 'name'), kind = p_values ->> 'kind', assignee_kind = v_kind, assignee_id = v_who,
      pipeline_id = (p_values ->> 'pipeline_id')::uuid, activity_type_id = (p_values ->> 'activity_type_id')::uuid, frequency = p_values ->> 'frequency',
      starts_on = coalesce((p_values ->> 'starts_on')::date, starts_on), ends_on = (p_values ->> 'ends_on')::date,
      target_count = (p_values ->> 'target_count')::int, target_value = (p_values ->> 'target_value')::numeric
    where id = p_id and deleted_at is null and (created_by = v_me or app.can('deals', 'configure')) returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  end if;
  perform app.log(case when p_id is null then 'goal.created' else 'goal.updated' end, 'goal', v_id::text, null);
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'goal';
end $fn$;

create function public.goal_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see');
begin
  update app.goals set deleted_at = now() where id = p_id and deleted_at is null and (created_by = v_me or app.can('deals', 'configure'));
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('goal.deleted', 'goal', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- forecasts
-- deal revenue: open deals by close month for the next N months; best case and weighted (PIP-11)
create function public.forecast_deals(p_months int default 4, p_pipeline uuid default null, p_owner uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); m0 date := date_trunc('month', now() at time zone 'Europe/Oslo')::date; n int := least(greatest(coalesce(p_months, 4), 1), 24);
begin
  return jsonb_build_object('months', (select jsonb_agg(jsonb_build_object('month', to_char(mm, 'YYYY-MM'),
      'best', coalesce((select sum(d.value) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.currency = 'NOK'
                        and app.visible(d.owner_id, d.visibility) and (d.is_sample = (select sandbox from app.admins where id = v_me))
                        and (app.can('deals', 'reports_others') or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm), 0),
      'weighted', coalesce((select round(sum(d.value * s.probability / 100.0)) from app.deals d join app.stages s on s.id = d.stage_id
                        where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.currency = 'NOK'
                        and app.visible(d.owner_id, d.visibility) and (d.is_sample = (select sandbox from app.admins where id = v_me))
                        and (app.can('deals', 'reports_others') or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm), 0),
      'count', (select count(*) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null
                        and app.visible(d.owner_id, d.visibility) and (d.is_sample = (select sandbox from app.admins where id = v_me))
                        and (app.can('deals', 'reports_others') or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm)) order by mm)
    from generate_series(m0, (m0 + make_interval(months => n - 1))::date, interval '1 month') mm),
    'undated', (select count(*) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.expected_close_date is null
                and app.visible(d.owner_id, d.visibility) and (app.can('deals', 'reports_others') or d.owner_id = v_me)));
end $fn$;

-- product revenue (UF-26, CRM-08): recurring = today's subscription MRR carried forward until a cancellation
-- takes effect, plus won deals' recurring lines normalised to a month from the deal's won date for their
-- cycles; installments = won deals' instalment lines spread over their cycles
create function public.forecast_products(p_months int default 6) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m0 date := date_trunc('month', now() at time zone 'Europe/Oslo')::date; n int := least(greatest(coalesce(p_months, 6), 1), 36);
begin
  perform app.require('global', 'see');
  return jsonb_build_object('months', (select jsonb_agg(jsonb_build_object('month', to_char(mm, 'YYYY-MM'),
      'subscriptions', coalesce((select sum(app.sub_mrr(s)) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                                 where ap.status = 'active' and (s.cancel_effective_at is null or s.cancel_effective_at >= mm + interval '1 month')), 0),
      'recurring', coalesce((select round(sum(i.quantity * i.unit_price * (1 - i.discount_pct / 100) /
                                        case i.billing_frequency when 'quarterly' then 3 when 'semiannual' then 6 when 'annual' then 12 else 1 end))
                            from app.deal_items i join app.deals d on d.id = i.deal_id
                            where i.billing = 'recurring' and d.status = 'won' and d.deleted_at is null and not d.is_sample and d.currency = 'NOK'
                              and date_trunc('month', d.won_at) <= mm
                              and (i.cycles is null or mm < date_trunc('month', d.won_at) + make_interval(months => i.cycles *
                                   case i.billing_frequency when 'quarterly' then 3 when 'semiannual' then 6 when 'annual' then 12 else 1 end))), 0),
      'installments', coalesce((select round(sum(i.quantity * i.unit_price * (1 - i.discount_pct / 100) / coalesce(i.cycles, 1)))
                            from app.deal_items i join app.deals d on d.id = i.deal_id
                            where i.billing = 'installments' and d.status = 'won' and d.deleted_at is null and not d.is_sample and d.currency = 'NOK'
                              and mm >= date_trunc('month', d.won_at) and mm < date_trunc('month', d.won_at) + make_interval(months => coalesce(i.cycles, 1))), 0))
      order by mm)
    from generate_series(m0, (m0 + make_interval(months => n - 1))::date, interval '1 month') mm));
end $fn$;

-- the fields a report can use, from the registry (the builder's pickers and the AI's context)
create function public.report_fields(p_entity text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity);
begin
  perform app.require(e.scope, 'see');
  return jsonb_build_object(
    'dimensions', to_jsonb(array_remove(array[case when e.owned then 'owner' end, case when e.key = 'deal' then 'stage' end, case when e.key = 'deal' then 'pipeline' end,
                                              case when e.key = 'activity' then 'type' end, 'label', 'created_month',
                                              case when e.key = 'deal' then 'won_month' end, case when e.key = 'deal' then 'close_month' end,
                                              case when e.key = 'activity' then 'done_month' end], null)
                   || array(select c.col from app.entity_columns c where c.entity = e.key and ((c.kind in ('text', 'boolean', 'int') and c.ref is null) or c.ref is not null) order by c.ord)),
    'numeric', to_jsonb(array(select c.col from app.entity_columns c where c.entity = e.key and c.kind in ('numeric', 'int') order by c.ord)),
    'dates', to_jsonb(array['created_at'] || array(select c.col from app.entity_columns c where c.entity = e.key and c.kind in ('date', 'timestamptz') order by c.ord)),
    'custom', coalesce((select jsonb_agg(jsonb_build_object('key', 'custom.' || f.key, 'label', f.label, 'type', f.type) order by f.ord)
                        from app.fields f where f.entity = e.key and f.archived_at is null), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
-- the role templates (INS-03): reports and dashboards anyone can open and duplicate
do $$
declare d uuid; r record; t record; pos int; v_rep uuid;
begin
  for t in select * from (values
    ('default', 'Default'), ('sales_manager', 'Sales manager'), ('sales_rep', 'Sales rep'), ('marketing', 'Marketing')) x(role, name) loop
    insert into app.dashboards (name, template_role) values (t.name, t.role) returning id into d;
    pos := 0;
    for r in
      with defs(role, name, def, span) as (values
        ('default', 'Won value · this quarter', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"filters":[{"f":"status","op":"eq","v":"won"}],"period":{"kind":"quarter","field":"won_at"},"chart":"scorecard"}'::jsonb, 4),
        ('default', 'Open pipeline', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"filters":[{"f":"status","op":"eq","v":"open"}],"chart":"scorecard"}', 4),
        ('default', 'Average sales cycle', '{"entity":"deal","type":"duration","measure":{"fn":"cycle_days"},"filters":[{"f":"status","op":"eq","v":"won"}],"period":{"kind":"quarter","field":"won_at"},"chart":"scorecard"}', 4),
        ('default', 'Open value by owner', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"group_by":"owner","filters":[{"f":"status","op":"eq","v":"open"}],"chart":"bar"}', 6),
        ('default', 'Deals per stage', '{"entity":"deal","measure":{"fn":"count"},"group_by":"stage","filters":[{"f":"status","op":"eq","v":"open"}],"chart":"column"}', 6),
        ('default', 'Lost reasons', '{"entity":"deal","measure":{"fn":"count"},"group_by":"lost_reason","filters":[{"f":"status","op":"eq","v":"lost"}],"chart":"pie"}', 4),
        ('default', 'Deals by source', '{"entity":"deal","measure":{"fn":"count"},"group_by":"source","chart":"pie"}', 4),
        ('default', 'Activities completed · month', '{"entity":"activity","measure":{"fn":"count"},"group_by":"type","filters":[{"f":"done","op":"eq","v":true}],"period":{"kind":"month","field":"done_at"},"chart":"column"}', 4),
        ('sales_manager', 'Open value by owner', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"group_by":"owner","filters":[{"f":"status","op":"eq","v":"open"}],"chart":"bar"}', 6),
        ('sales_manager', 'Weighted pipeline by owner', '{"entity":"deal","measure":{"fn":"weighted"},"group_by":"owner","filters":[{"f":"status","op":"eq","v":"open"}],"chart":"bar"}', 6),
        ('sales_manager', 'Won value by owner · quarter', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"group_by":"owner","filters":[{"f":"status","op":"eq","v":"won"}],"period":{"kind":"quarter","field":"won_at"},"chart":"column"}', 6),
        ('sales_manager', 'Activities completed by owner · month', '{"entity":"activity","measure":{"fn":"count"},"group_by":"owner","filters":[{"f":"done","op":"eq","v":true}],"period":{"kind":"month","field":"done_at"},"chart":"column"}', 6),
        ('sales_rep', 'My open pipeline', '{"entity":"deal","measure":{"fn":"sum","field":"value"},"group_by":"stage","filters":[{"f":"status","op":"eq","v":"open"}],"chart":"column"}', 6),
        ('sales_rep', 'My activities this month', '{"entity":"activity","measure":{"fn":"count"},"group_by":"type","filters":[{"f":"done","op":"eq","v":true}],"period":{"kind":"month","field":"done_at"},"chart":"column"}', 6),
        ('marketing', 'Leads by source · 90 d', '{"entity":"lead","measure":{"fn":"count"},"group_by":"source","period":{"kind":"last_90","field":"created_at"},"chart":"bar"}', 6),
        ('marketing', 'Deals by source', '{"entity":"deal","measure":{"fn":"count"},"group_by":"source","chart":"pie"}', 6))
      select defs.name, defs.def, defs.span from defs where defs.role = t.role loop
      insert into app.reports (name, definition, source, is_template) values (r.name, r.def, 'template', true) returning id into v_rep;
      insert into app.dashboard_tiles (dashboard_id, report_id, position, span) values (d, v_rep, pos, r.span);
      pos := pos + 1;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['reports', 'dashboards', 'dashboard_tiles', 'dashboard_shares', 'goals', 'pipeline_snapshots_daily'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array['app.snapshot_pipeline()', 'app.period_bounds(jsonb, int)', 'app.report_dim(app.entities, text)', 'app.report_measure(app.entities, jsonb)',
                           'app.report_check(jsonb)', 'app.report_where(app.entities, jsonb, jsonb, int)', 'app.report_conversion(jsonb)', 'app.report_run(jsonb, jsonb)',
                           'app.report_rows(jsonb, jsonb, int)', 'app.dashboard_role(uuid)', 'app.goal_interval(app.goals)', 'app.goal_owners(app.goals)', 'app.goal_progress(app.goals)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.report_run(jsonb, jsonb)', 'public.report_drill(jsonb, jsonb, int)', 'public.report_export(jsonb, jsonb, text)', 'public.reports_get()',
                           'public.report_save(uuid, text, jsonb, text)', 'public.report_delete(uuid)', 'public.dashboards_get()', 'public.dashboard_get(uuid, jsonb)',
                           'public.dashboard_save(uuid, text, jsonb)', 'public.dashboard_duplicate(uuid, text)', 'public.dashboard_share(uuid, text, uuid, text)',
                           'public.dashboard_delete(uuid)', 'public.goals_get()', 'public.goal_save(uuid, jsonb)', 'public.goal_delete(uuid)',
                           'public.forecast_deals(int, uuid, uuid)', 'public.forecast_products(int)', 'public.report_fields(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
