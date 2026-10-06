-- 0034_insights_analytics_requests.sql — the Insights and Analytics screens' database requests
-- (docs/crm-enrichment/requests/insights.md R-INSIGHTS-01..07, 09; analytics.md R-1, R-2 follow-up, R-3..R-9).
--
-- Insights: template tiles carry a key the screen translates, the role templates gain «Stage conversion»,
-- «Deals per stage» keeps to one pipeline, lost reasons are normalised to the configured list, Progress and
-- Products become real report types, filters gain «does not contain», a conversion row drills to its deals,
-- and the deal forecast says which deals it leaves out.
--
-- Analytics: sums of subscription money count NOK only and the reads say how many subscriptions they left out;
-- the first snapshot is returned as a date; activation medians run from signup; retention says «no figure»
-- instead of zero, churn gains its denominator, its lost MRR and a list that names each churn; usage per
-- application and over the period; customers by size; per-channel and per-campaign web figures; channels with
-- spend but no signups; Marketing may read web analytics and attribution.
--
-- Left out, with the reason in the request files: a dashboard-wide period (not drawn), feature adoption (no
-- registry of feature keys), signups per web session or landing page (the daily salt makes the join
-- impossible and the attribution carries no landing path), the funnel's page rules and failed lookups, the
-- bot filter (the tracker's edge function does not exist), the journey of a paying customer.

-- ===========================================================================
-- Insights
-- ===========================================================================

-- R-INSIGHTS-02: a template report carries a stable key; the screen renders insights.templateTiles.<key> and
-- falls back to the stored name. A staff member's own report (a duplicate included) has none.
alter table app.reports add column template_key text
  check (template_key is null or (is_template and template_key ~ '^[a-z][a-z0-9_]{1,39}$'));

update app.reports set template_key = case name
    when 'Won value · this quarter' then 'won_quarter'
    when 'Open pipeline' then 'open_pipeline'
    when 'Average sales cycle' then 'avg_sales_cycle'
    when 'Open value by owner' then 'open_by_owner'
    when 'Deals per stage' then 'deals_per_stage'
    when 'Lost reasons' then 'lost_reasons'
    when 'Deals by source' then 'deals_by_source'
    when 'Activities completed · month' then 'activities_month'
    when 'Weighted pipeline by owner' then 'weighted_by_owner'
    when 'Won value by owner · quarter' then 'won_by_owner_quarter'
    when 'Activities completed by owner · month' then 'activities_by_owner_month'
    when 'My open pipeline' then 'my_open_pipeline'
    when 'My activities this month' then 'my_activities_month'
    when 'Leads by source · 90 d' then 'leads_by_source_90'
  end
where is_template and source = 'template';

-- the pipeline a conversion report runs over: its own, or else the first pipeline the viewer can see (the
-- role templates are seeded before any pipeline may exist)
create function app.report_pipeline(p_def jsonb) returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_def ->> 'pipeline_id' is not null then
    if p_def ->> 'pipeline_id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id';
    end if;
    return (p_def ->> 'pipeline_id')::uuid;
  end if;
  return (select p.id from app.pipelines p
          where p.archived_at is null and app.pipeline_visible(p.id)
            and (coalesce((select a.sandbox from app.admins a where a.id = app.me()), false) or not p.is_sample)
          order by p.ord limit 1);
end $fn$;

-- R-INSIGHTS-01 and 03: «Stage conversion · Last 90 days» on Default and Sales manager, and «Deals per stage» /
-- «My open pipeline» on one pipeline. The pipeline is looked up by name; on a database built before its seed
-- there is none yet: the conversion tile then runs over the first pipeline (app.report_pipeline) and the stage
-- tiles span every pipeline, ordered pipeline by pipeline (report_dim below).
do $$
declare v_pipe uuid := (select id from app.pipelines where name = 'New business' and archived_at is null and not is_sample order by ord limit 1);
        v_def jsonb; d record; v_rep uuid;
begin
  v_def := '{"entity":"deal","type":"conversion","period":{"kind":"last_90"},"chart":"table"}'::jsonb
           || case when v_pipe is not null then jsonb_build_object('pipeline_id', v_pipe) else '{}'::jsonb end;
  for d in select id from app.dashboards where template_role in ('default', 'sales_manager') and deleted_at is null loop
    insert into app.reports (name, definition, source, is_template, template_key) values ('Stage conversion', v_def, 'template', true, 'stage_conversion')
    returning id into v_rep;
    insert into app.dashboard_tiles (dashboard_id, report_id, position, span)
    values (d.id, v_rep, (select coalesce(max(position), -1) + 1 from app.dashboard_tiles where dashboard_id = d.id), 4);
  end loop;
  if v_pipe is not null then
    update app.reports set definition = jsonb_set(definition, '{filters}',
             coalesce(definition -> 'filters', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('f', 'pipeline_id', 'op', 'eq', 'v', v_pipe)))
    where is_template and template_key in ('deals_per_stage', 'my_open_pipeline')
      and not coalesce(definition -> 'filters', '[]'::jsonb) @> '[{"f":"pipeline_id"}]';
  end if;
end $$;

-- a dimension (0024), with two changes: «stage» orders by pipeline first, then stage (R-INSIGHTS-03), and
-- «lost_reason» maps the free text to the configured lost reasons, case-insensitively, with anything else
-- under one «Other» key (R-INSIGHTS-04)
create or replace function app.report_dim(e app.entities, p_dim text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare ftype text;
begin
  if p_dim is null then return null; end if;
  if p_dim = 'owner' and e.owned then
    return jsonb_build_object('expr', 't.owner_id::text', 'label', '(select a.name from app.admins a where a.id::text = v)');
  elsif p_dim = 'stage' and e.key = 'deal' then
    return jsonb_build_object('expr', 't.stage_id::text', 'label', '(select s.name from app.stages s where s.id::text = v)',
                              'ord', '(select array[p.ord, s.ord] from app.stages s join app.pipelines p on p.id = s.pipeline_id where s.id::text = v)');
  elsif p_dim = 'lost_reason' and e.key = 'deal' then
    return jsonb_build_object('expr', $x$(select coalesce((select lr.label from app.lost_reasons lr where lower(lr.label) = lower(btrim(t.lost_reason)) order by lr.ord limit 1),
                                                   (select lr.label from app.lost_reasons lr where lower(lr.label) = 'other' order by lr.ord limit 1), 'Other')
                                          where nullif(btrim(t.lost_reason), '') is not null)$x$,
                              'label', 'v');
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

-- R-INSIGHTS-06: «does not contain» (ncontains); otherwise as 0023
create or replace function app.filter_sql(e app.entities, p_filters jsonb) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  x jsonb; f text; op text; v jsonb; kind text; col text; out text := ''; ftype text; g jsonb; parts text[];
begin
  if p_filters is null or jsonb_typeof(p_filters) <> 'array' then return ''; end if;
  for x in select * from jsonb_array_elements(p_filters) loop
    if jsonb_typeof(x -> 'or') = 'array' then
      parts := '{}';
      for g in select * from jsonb_array_elements(x -> 'or') loop
        if jsonb_typeof(g) <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'filter.or'; end if;
        parts := parts || ('(true' || app.filter_sql(e, g) || ')');
      end loop;
      if cardinality(parts) > 0 then out := out || ' and (' || array_to_string(parts, ' or ') || ')'; end if;
      continue;
    end if;
    f := x ->> 'f'; op := coalesce(x ->> 'op', 'eq'); v := x -> 'v';
    if f = 'idle_days' and e.key = 'deal' then
      col := 'floor(extract(epoch from now() - coalesce(t.last_activity_at, t.stage_entered_at)) / 86400)';
      kind := 'numeric';
    elsif f like 'custom.%' then
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
      when 'ncontains' then format('coalesce(%s::text, %L) not ilike %L', col, '', '%' || replace(replace(v #>> '{}', '%', '\%'), '_', '\_') || '%')
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

-- stage conversion (0024) over app.report_pipeline; a period of «all» runs over all time instead of nothing
create or replace function app.report_conversion(p_def jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity('deal'); v_pipe uuid := app.report_pipeline(p_def); r tstzrange := app.period_bounds(coalesce(p_def -> 'period', '{"kind":"last_90"}'::jsonb), 0);
        v_rows jsonb; w text;
begin
  if v_pipe is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id'; end if;
  w := app.report_where(e, p_def - 'period', null, 0);
  execute format($q$
    with st as (select s.id, s.name, s.ord, lead(s.id) over (order by s.ord) nxt from app.stages s where s.pipeline_id = %L),
         d as (select t.id, t.status from app.deals t where t.pipeline_id = %L and %s),
         e1 as (select h.deal_id, h.stage_id, h.entered_at from app.deal_stage_history h join d on d.id = h.deal_id where %s)
    select coalesce(jsonb_agg(jsonb_build_object('key', st.id, 'label', st.name, 'entered', x.entered, 'value',
             case when x.entered = 0 then null else round(100.0 * x.advanced / x.entered, 1) end) order by st.ord), '[]'::jsonb)
    from st cross join lateral (
      select count(distinct e1.deal_id) entered,
             count(distinct e1.deal_id) filter (where (st.nxt is not null and exists (select 1 from app.deal_stage_history h2 where h2.deal_id = e1.deal_id and h2.stage_id = st.nxt and h2.entered_at > e1.entered_at))
                                               or (st.nxt is null and exists (select 1 from d where d.id = e1.deal_id and d.status = 'won'))) advanced
      from e1 where e1.stage_id = st.id) x$q$, v_pipe, v_pipe, w,
    case when r is null then 'true' else format('h.entered_at >= %L and h.entered_at < %L', lower(r), upper(r)) end) into v_rows;
  return jsonb_build_object('rows', v_rows, 'unit', 'percent');
end $fn$;

-- R-INSIGHTS-05 Progress: the deals that entered a later stage of the same pipeline in the period, as
-- (deal_id, stage_id) rows over alias z; the period applies to the move, the filters to the deal
create function app.progress_sql(p_def jsonb, p_extra jsonb, p_shift int) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity('deal'); r tstzrange := app.period_bounds(p_def -> 'period', p_shift); v_pipe uuid;
begin
  if p_def ->> 'pipeline_id' is not null then v_pipe := app.report_pipeline(p_def); end if;
  return format($q$select m.deal_id, m.stage_id from (
      select h.deal_id, h.stage_id, h.entered_at, lag(h.stage_id) over (partition by h.deal_id order by h.entered_at, h.id) prev
      from app.deal_stage_history h where h.deal_id in (select t.id from app.deals t where %s %s)) m
    join app.stages s on s.id = m.stage_id join app.stages ps on ps.id = m.prev
    where s.pipeline_id = ps.pipeline_id and s.ord > ps.ord %s$q$,
    app.report_where(e, p_def - 'period', p_extra, 0),
    case when v_pipe is not null then format('and t.pipeline_id = %L', v_pipe) else '' end,
    case when r is not null then format('and m.entered_at >= %L and m.entered_at < %L', lower(r), upper(r)) else '' end);
end $fn$;

create function app.report_progress(p_def jsonb, p_extra jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare q text := app.progress_sql(p_def, p_extra, 0); v_rows jsonb; v_total numeric; v_prev numeric;
begin
  execute format($q$select coalesce(jsonb_agg(jsonb_build_object('key', x.stage_id, 'label', s.name, 'segment', null, 'segment_label', null, 'value', x.n) order by p.ord, s.ord), '[]'::jsonb)
    from (select z.stage_id, count(distinct z.deal_id)::numeric n from (%s) z group by z.stage_id) x
    join app.stages s on s.id = x.stage_id join app.pipelines p on p.id = s.pipeline_id$q$, q) into v_rows;
  execute format('select count(distinct z.deal_id)::numeric from (%s) z', q) into v_total;
  if app.period_bounds(p_def -> 'period', 0) is not null then
    execute format('select count(distinct z.deal_id)::numeric from (%s) z', app.progress_sql(p_def, p_extra, -1)) into v_prev;
  end if;
  return jsonb_build_object('rows', v_rows, 'total', v_total, 'previous', v_prev, 'excluded_currency', 0, 'unit', 'count');
end $fn$;

-- R-INSIGHTS-05 Products: the line items of won deals (alias i over deals t); the period runs on won_at unless
-- the definition names another field
create function app.products_where(p_def jsonb, p_extra jsonb, p_shift int) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_def jsonb := p_def;
begin
  if jsonb_typeof(p_def -> 'period') = 'object' and p_def -> 'period' ->> 'field' is null then
    v_def := jsonb_set(p_def, '{period,field}', '"won_at"');
  end if;
  return app.report_where(app.entity('deal'), v_def, p_extra, p_shift) || ' and t.status = ''won''';
end $fn$;

-- measure: count (lines), sum of quantity, or sum of line value (NOK only, the rest counted apart)
create function app.report_products(p_def jsonb, p_extra jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare fn text := coalesce(p_def -> 'measure' ->> 'fn', 'count'); f text := p_def -> 'measure' ->> 'field'; m text; w text := app.products_where(p_def, p_extra, 0);
        v_rows jsonb; v_total numeric; v_prev numeric; v_excl int := 0; v_money boolean := false;
begin
  if fn = 'count' then m := 'count(*)::numeric';
  elsif fn = 'sum' and f = 'quantity' then m := 'coalesce(sum(i.quantity), 0)';
  elsif fn = 'sum' and coalesce(f, 'value') = 'value' then
    m := 'coalesce(sum(i.quantity * i.unit_price * (1 - i.discount_pct / 100)) filter (where t.currency = ''NOK''), 0)'; v_money := true;
  else raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure';
  end if;
  execute format($q$select coalesce(jsonb_agg(jsonb_build_object('key', x.k, 'label', (select c.name from app.catalog_items c where c.id::text = x.k),
                                                               'segment', null, 'segment_label', null, 'value', x.val) order by x.val desc nulls last), '[]'::jsonb)
    from (select i.item_id::text k, %s val from app.deals t join app.deal_items i on i.deal_id = t.id where %s group by 1) x$q$, m, w) into v_rows;
  execute format('select %s from app.deals t join app.deal_items i on i.deal_id = t.id where %s', m, w) into v_total;
  if app.period_bounds(p_def -> 'period', 0) is not null then
    execute format('select %s from app.deals t join app.deal_items i on i.deal_id = t.id where %s', m, app.products_where(p_def, p_extra, -1)) into v_prev;
  end if;
  if v_money then
    execute format('select count(distinct t.id) from app.deals t join app.deal_items i on i.deal_id = t.id where %s and t.currency <> ''NOK''', w) into v_excl;
  end if;
  return jsonb_build_object('rows', v_rows, 'total', v_total, 'previous', v_prev, 'excluded_currency', v_excl, 'unit', case when v_money then 'nok' else 'count' end);
end $fn$;

-- run a definition (0024): progress and products are computed as themselves, no longer as performance
create or replace function app.report_run(p_def jsonb, p_extra jsonb default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare
  e app.entities := app.report_check(p_def); g jsonb; s jsonb; m text; w text; joins text := ''; v_rows jsonb; v_total numeric; v_prev numeric; v_excl int := 0;
  v_sql text;
begin
  if p_def ->> 'type' = 'conversion' then return app.report_conversion(p_def); end if;
  if p_def ->> 'type' in ('progress', 'products') then
    if e.key <> 'deal' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type'; end if;
    if p_def ->> 'type' = 'progress' then return app.report_progress(p_def, p_extra); end if;
    return app.report_products(p_def, p_extra);
  end if;
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

-- the rows behind a segment (0024). R-INSIGHTS-09: a conversion row ({key: stage}) opens the deals that entered
-- that stage in the period; a progress row the deals that moved into it; a products row the won deals with
-- that catalog item (key null: lines without one)
create or replace function app.report_rows(p_def jsonb, p_segment jsonb, p_limit int) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.report_check(p_def); g jsonb; s jsonb;
        w text; joins text; extra text := ''; v_rows jsonb; vcol text; v_ids text; v_key text; r tstzrange; v_pipe uuid;
        v_lim int := least(greatest(coalesce(p_limit, 200), 1), 5000);
begin
  if p_def ->> 'type' in ('conversion', 'progress', 'products') then
    if e.key <> 'deal' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type'; end if;
    v_key := p_segment ->> 'key';
    if v_key is not null and v_key !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'segment';
    end if;
    if p_def ->> 'type' = 'conversion' then
      v_pipe := app.report_pipeline(p_def);
      if v_pipe is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'pipeline_id'; end if;
      r := app.period_bounds(coalesce(p_def -> 'period', '{"kind":"last_90"}'::jsonb), 0);
      v_ids := format('select h.deal_id from app.deal_stage_history h join app.deals t on t.id = h.deal_id where t.pipeline_id = %L and %s %s %s',
                      v_pipe, app.report_where(e, p_def - 'period', null, 0),
                      case when r is null then '' else format('and h.entered_at >= %L and h.entered_at < %L', lower(r), upper(r)) end,
                      case when not p_segment ? 'key' then '' when v_key is null then 'and h.stage_id is null' else format('and h.stage_id = %L', v_key) end);
    elsif p_def ->> 'type' = 'progress' then
      v_ids := format('select z.deal_id from (%s) z %s', app.progress_sql(p_def, null, 0),
                      case when not p_segment ? 'key' then '' when v_key is null then 'where z.stage_id is null' else format('where z.stage_id = %L', v_key) end);
    else
      v_ids := format('select i.deal_id from app.deals t join app.deal_items i on i.deal_id = t.id where %s %s', app.products_where(p_def, null, 0),
                      case when not p_segment ? 'key' then '' when v_key is null then 'and i.item_id is null' else format('and i.item_id = %L', v_key) end);
    end if;
    execute format($q$select coalesce(jsonb_agg(x order by x ->> 'title'), '[]'::jsonb) from (
        select jsonb_build_object('id', t.id, 'title', t.title::text, 'owner', (select a.name from app.admins a where a.id = t.owner_id), 'value', t.value,
                                  'currency', t.currency, 'created_at', t.created_at) x
        from app.deals t where t.id in (%s) limit %s) z$q$, v_ids, v_lim) into v_rows;
    return v_rows;
  end if;
  g := app.report_dim(e, p_def ->> 'group_by'); s := app.report_dim(e, p_def ->> 'segment_by');
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
    case when e.key in ('deal', 'lead') then 't.currency' else 'null' end, e.tbl, joins, w, extra, v_lim) into v_rows;
  return v_rows;
end $fn$;

-- a dashboard (0024), each tile with its template_key (R-INSIGHTS-02); a conversion tile names the pipeline it ran over
create or replace function public.dashboard_get(p_id uuid, p_period jsonb default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); d app.dashboards; v_role text := app.dashboard_role(p_id); t record; v_tiles jsonb := '[]'::jsonb; v_def jsonb; v_res jsonb; v_pipe uuid;
begin
  select * into d from app.dashboards where id = p_id and deleted_at is null;
  if not found or v_role is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  for t in select dt.position, dt.span, r.id, r.name, r.definition, r.template_key from app.dashboard_tiles dt join app.reports r on r.id = dt.report_id
           where dt.dashboard_id = p_id and r.deleted_at is null order by dt.position loop
    v_def := t.definition || case when p_period is not null and t.definition ? 'period' then jsonb_build_object('period', (t.definition -> 'period') || p_period) else '{}'::jsonb end;
    begin
      if v_def ->> 'type' = 'conversion' and v_def ->> 'pipeline_id' is null then
        v_pipe := app.report_pipeline(v_def);
        if v_pipe is not null then v_def := v_def || jsonb_build_object('pipeline_id', v_pipe); end if;
      end if;
      if app.can((select e.scope from app.entities e where e.key = v_def ->> 'entity'), 'see') then
        v_res := app.report_run(v_def, null);
      else
        v_res := jsonb_build_object('error', 'forbidden');
      end if;
    exception when others then
      v_res := jsonb_build_object('error', case when sqlerrm in ('invalid', 'module_off', 'forbidden') then sqlerrm else 'failed' end);
    end;
    v_tiles := v_tiles || jsonb_build_array(jsonb_build_object('report_id', t.id, 'name', t.name, 'template_key', t.template_key, 'definition', v_def,
                                                               'position', t.position, 'span', t.span, 'result', v_res));
  end loop;
  return jsonb_build_object('id', d.id, 'name', d.name, 'template_role', d.template_role, 'role', v_role, 'tiles', v_tiles,
    'shares', case when v_role = 'owner' then coalesce((select jsonb_agg(jsonb_build_object('kind', s.grantee_kind, 'id', s.grantee_id, 'role', s.role,
                     'name', case s.grantee_kind when 'staff' then (select a.name from app.admins a where a.id = s.grantee_id)
                                                 when 'team' then (select tm.name from app.teams tm where tm.id = s.grantee_id)
                                                 else (select g.name from app.visibility_groups g where g.id = s.grantee_id) end))
                   from app.dashboard_shares s where s.dashboard_id = p_id), '[]'::jsonb) end);
end $fn$;

-- R-INSIGHTS-07: the deal forecast (0024) returns excluded_currency (open deals closing in the window in another
-- currency than NOK) and counts undated deals inside the sandbox rule like the months
create or replace function public.forecast_deals(p_months int default 4, p_pipeline uuid default null, p_owner uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); m0 date := date_trunc('month', now() at time zone 'Europe/Oslo')::date; n int := least(greatest(coalesce(p_months, 4), 1), 24);
        v_sandbox boolean := coalesce((select sandbox from app.admins where id = v_me), false); v_others boolean := app.can('deals', 'reports_others');
begin
  return jsonb_build_object('months', (select jsonb_agg(jsonb_build_object('month', to_char(mm, 'YYYY-MM'),
      'best', coalesce((select sum(d.value) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.currency = 'NOK'
                        and app.visible(d.owner_id, d.visibility) and d.is_sample = v_sandbox
                        and (v_others or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm), 0),
      'weighted', coalesce((select round(sum(d.value * s.probability / 100.0)) from app.deals d join app.stages s on s.id = d.stage_id
                        where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.currency = 'NOK'
                        and app.visible(d.owner_id, d.visibility) and d.is_sample = v_sandbox
                        and (v_others or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm), 0),
      'count', (select count(*) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null
                        and app.visible(d.owner_id, d.visibility) and d.is_sample = v_sandbox
                        and (v_others or d.owner_id = v_me)
                        and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                        and date_trunc('month', d.expected_close_date) = mm)) order by mm)
    from generate_series(m0, (m0 + make_interval(months => n - 1))::date, interval '1 month') mm),
    'undated', (select count(*) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.expected_close_date is null
                and app.visible(d.owner_id, d.visibility) and d.is_sample = v_sandbox and (v_others or d.owner_id = v_me)
                and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)),
    'excluded_currency', (select count(*) from app.deals d where d.status = 'open' and d.deleted_at is null and d.archived_at is null and d.currency <> 'NOK'
                and app.visible(d.owner_id, d.visibility) and d.is_sample = v_sandbox and (v_others or d.owner_id = v_me)
                and (p_pipeline is null or d.pipeline_id = p_pipeline) and (p_owner is null or d.owner_id = p_owner)
                and d.expected_close_date >= m0 and d.expected_close_date < (m0 + make_interval(months => n))::date));
end $fn$;

-- the product forecast (0024): today's subscription MRR in NOK only, the others counted (R-1's rule)
create or replace function public.forecast_products(p_months int default 6) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare m0 date := date_trunc('month', now() at time zone 'Europe/Oslo')::date; n int := least(greatest(coalesce(p_months, 6), 1), 36);
begin
  perform app.require('global', 'see');
  return jsonb_build_object('months', (select jsonb_agg(jsonb_build_object('month', to_char(mm, 'YYYY-MM'),
      'subscriptions', coalesce((select sum(app.sub_mrr(s)) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                                 where ap.status = 'active' and s.currency = 'NOK' and (s.cancel_effective_at is null or s.cancel_effective_at >= mm + interval '1 month')), 0),
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
    from generate_series(m0, (m0 + make_interval(months => n - 1))::date, interval '1 month') mm),
    'excluded_currency', (select count(*) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                          where ap.status = 'active' and s.currency <> 'NOK' and app.sub_mrr(s) > 0));
end $fn$;

-- ===========================================================================
-- Analytics
-- ===========================================================================

-- R-1: the daily MRR snapshot sums NOK only (paying and trials stay counts of every subscription)
create or replace function app.snapshot_mrr() returns void
  language sql volatile security definer set search_path = ''
as $fn$
  insert into app.mrr_daily (day, product, mrr, paying, trials)
  select current_date, p.key,
         coalesce(sum(app.sub_mrr(s)) filter (where s.currency = 'NOK'), 0),
         count(*) filter (where app.sub_mrr(s) > 0),
         count(*) filter (where app.sub_status(s) = 'trial')
  from app.products p
  left join app.subscriptions s on s.product = p.key
  left join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id and ap.status = 'active'
  group by p.key
  on conflict (day, product) do update set mrr = excluded.mrr, paying = excluded.paying, trials = excluded.trials;
$fn$;

-- R-1: a tenant whose subscription is in another currency than NOK; its movements and churned MRR are left out
-- of the sums (a tenant whose subscription is gone keeps its history)
create function app.non_nok(p_product text, p_tenant text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select exists (select 1 from app.subscriptions s where s.product = p_product and s.tenant_id = p_tenant and s.currency <> 'NOK')
$fn$;

create or replace view app.v_net_new_mrr with (security_invoker = true) as
  select mv.month, mv.product, sum(mv.delta) filter (where mv.kind in ('new', 'reactivation')) new_mrr, sum(mv.delta) filter (where mv.kind = 'expansion') expansion,
         sum(mv.delta) filter (where mv.kind = 'contraction') contraction, sum(mv.delta) filter (where mv.kind = 'churn') churn, sum(mv.delta) net
  from app.mrr_movements mv where not app.non_nok(mv.product, mv.tenant_id) group by 1, 2;
create or replace view app.v_revenue_churn with (security_invoker = true) as
  select mv.month, mv.product, -sum(mv.delta) filter (where mv.kind in ('churn', 'contraction')) lost
  from app.mrr_movements mv where not app.non_nok(mv.product, mv.tenant_id) group by 1, 2;
revoke all on app.v_net_new_mrr, app.v_revenue_churn from public, anon, authenticated;
update app.metric_definitions set version = version + 1, migration = '0034_insights_analytics_requests.sql'
where key in ('mrr', 'net_new_mrr', 'revenue_churn');

-- business: NOK sums with excluded_currency (R-1), first_snapshot (R-2), churn.paying_start (R-4), by_size (R-6)
create or replace function public.analytics_business(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end; v_mrr numeric; v_prev numeric; v_prev_day date;
begin
  perform app.require('global', 'reports_others');
  v_prev_day := (select max(day) from app.mrr_daily where day <= current_date - d);
  v_mrr := (select sum(mrr) from app.mrr_daily where day = (select max(day) from app.mrr_daily) and app.in_scope(p_product, product));
  v_prev := (select sum(mrr) from app.mrr_daily where day = v_prev_day and app.in_scope(p_product, product));
  return jsonb_build_object(
    'mrr', v_mrr, 'mrr_prev', v_prev,
    'excluded_currency', (select count(*) from app.subscriptions s where app.sub_mrr(s) > 0 and s.currency <> 'NOK' and app.in_scope(p_product, s.product)),
    'first_snapshot', (select min(day) from app.mrr_tenant_daily where app.in_scope(p_product, product)),
    'paying_accounts', (select count(distinct ap.account_id) from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
                        where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product)),
    'customers', (select count(distinct ap.account_id) from app.account_products ap where ap.status = 'active' and app.in_scope(p_product, ap.product)),
    'trials', (select count(*) from app.subscriptions s where app.sub_status(s) = 'trial' and app.in_scope(p_product, s.product)),
    'trials_ending_7', (select count(*) from app.subscriptions s where app.sub_status(s) = 'trial' and s.trial_ends_at < now() + interval '7 days' and app.in_scope(p_product, s.product)),
    'trial_conversion', (select jsonb_build_object('trials', sum(trials), 'converted', sum(converted)) from app.v_trial_conversion
                         where cohort >= date_trunc('month', now() - make_interval(days => d + 45)) and cohort < date_trunc('month', now() - interval '45 days') + interval '1 month'
                           and app.in_scope(p_product, product)),
    'movements', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'new', coalesce(new_mrr, 0), 'expansion', coalesce(expansion, 0),
                                                               'contraction', coalesce(contraction, 0), 'churn', coalesce(churn, 0), 'net', coalesce(net, 0)) order by month)
                           from (select month, sum(new_mrr) new_mrr, sum(expansion) expansion, sum(contraction) contraction, sum(churn) churn, sum(net) net
                                 from app.v_net_new_mrr where app.in_scope(p_product, product) and month > date_trunc('month', now()) - interval '12 months' group by month) x), '[]'::jsonb),
    'mrr_by_product', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'product', product, 'mrr', mrr) order by month, product)
                                from app.v_mrr_monthly where month > date_trunc('month', now()) - interval '12 months' and app.in_scope(p_product, product)), '[]'::jsonb),
    'trials_by_source', coalesce((select jsonb_agg(jsonb_build_object('channel', ch, 'trials', n, 'converted', c) order by n desc) from (
        select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) ch, count(*) n,
               count(*) filter (where s.confirmed_at is not null and s.confirmed_at <= s.trial_started_at + interval '45 days') c
        from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
        where s.trial_started_at > now() - make_interval(days => d) and app.in_scope(p_product, s.product) group by 1) x), '[]'::jsonb),
    'bands', coalesce((select jsonb_agg(jsonb_build_object('band', b.band_label, 'accounts', b.n, 'mrr', b.mrr) order by b.min_employees) from (
        select pv.band_label, pv.min_employees, count(*) n, sum(app.sub_mrr(s)) filter (where s.currency = 'NOK') mrr from app.subscriptions s
        join app.plan_versions pv on pv.product = s.product and s.seats between pv.min_employees and coalesce(pv.max_employees, 2147483647)
        where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product) group by pv.band_label, pv.min_employees) b), '[]'::jsonb),
    'by_industry', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'count', n) order by n desc) from (
        select coalesce(o.industry, '') k, count(distinct o.id) n from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        where ap.status = 'active' and app.in_scope(p_product, ap.product) and o.deleted_at is null and not o.is_sample group by 1) x), '[]'::jsonb),
    'by_fylke', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'count', n) order by n desc) from (
        select coalesce(o.fylke, '') k, count(distinct o.id) n from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        where ap.status = 'active' and app.in_scope(p_product, ap.product) and o.deleted_at is null and not o.is_sample group by 1) x), '[]'::jsonb),
    -- the employee bands of the price list (the product's own, else another product's); '' = no band (employees unknown or outside every band)
    'by_size', coalesce((select jsonb_agg(jsonb_build_object('key', k, 'count', n) order by lo nulls last) from (
        select coalesce(b.band_label, '') k, min(b.min_employees) lo, count(distinct o.id) n
        from app.organizations o join app.account_products ap on ap.account_id = o.account_id
        left join lateral (select pv.band_label, pv.min_employees from app.plan_versions pv
                           where pv.active and o.employees between pv.min_employees and coalesce(pv.max_employees, 2147483647)
                           order by app.in_scope(p_product, pv.product) desc, pv.product, pv.version desc limit 1) b on true
        where ap.status = 'active' and app.in_scope(p_product, ap.product) and o.deleted_at is null and not o.is_sample group by 1) x), '[]'::jsonb),
    'activated_after_result', (select jsonb_build_object('paying', count(*), 'tiltak_30d', count(*) filter (where t.reached_at <= r.reached_at + interval '30 days'))
                               from app.subscriptions s join app.activation_milestones r on r.product = s.product and r.tenant_id = s.tenant_id and r.key = 'result_unlocked'
                               left join app.activation_milestones t on t.product = s.product and t.tenant_id = s.tenant_id and t.key = 'first_tiltak'
                               where app.sub_mrr(s) > 0 and app.in_scope(p_product, s.product)),
    'churn', (select jsonb_build_object('logos', count(*), 'mrr_lost', coalesce(sum(c.mrr_lost) filter (where not app.non_nok(c.product, c.tenant_id)), 0),
                                        'paying_start', (select sum(m.paying) from app.mrr_daily m where m.day = v_prev_day and app.in_scope(p_product, m.product)))
              from app.account_churns c where c.churned_at > now() - make_interval(days => d) and app.in_scope(p_product, c.product)));
end $fn$;

-- activation (0025) with the hero's medians from signup (R-3): to the first survey sent, and to conversion
create or replace function public.analytics_activation(p_product text default null, p_cohort date default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare c date := coalesce(date_trunc('month', p_cohort)::date, date_trunc('month', now())::date - interval '1 month');
        keys text[] := array['account_created', 'employees_uploaded', 'survey_scheduled', 'survey_sent', 'result_unlocked', 'results_viewed', 'first_tiltak', 'converted'];
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object('cohort', to_char(c, 'YYYY-MM'),
    'cohorts', (select jsonb_agg(to_char(m, 'YYYY-MM') order by m desc) from generate_series(date_trunc('month', now()) - interval '3 months', date_trunc('month', now()), interval '1 month') m),
    'target_min', case when app.setting('activation_target') = 'custom' then (select value_number from app.setting_values where key = 'activation_target' and scope_id = '') else 20 end,
    'first_send_median_min', (select percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - a.reached_at) / 60)
                              from app.activation_milestones a join app.activation_milestones m on m.product = a.product and m.tenant_id = a.tenant_id and m.key = 'survey_sent'
                              where a.key = 'account_created' and date_trunc('month', a.reached_at) = c and app.in_scope(p_product, a.product)),
    'paid_median_min', (select percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - a.reached_at) / 60)
                        from app.activation_milestones a join app.activation_milestones m on m.product = a.product and m.tenant_id = a.tenant_id and m.key = 'converted'
                        where a.key = 'account_created' and date_trunc('month', a.reached_at) = c and app.in_scope(p_product, a.product)),
    'steps', (with t as (select a.product, a.tenant_id from app.activation_milestones a where a.key = 'account_created' and date_trunc('month', a.reached_at) = c
                         and app.in_scope(p_product, a.product))
              select jsonb_agg(jsonb_build_object('key', k, 'count', (select count(*) from t join app.activation_milestones m on m.product = t.product and m.tenant_id = t.tenant_id and m.key = k),
                     'median_min', (select percentile_cont(0.5) within group (order by extract(epoch from m.reached_at - p.reached_at) / 60)
                                    from t join app.activation_milestones m on m.product = t.product and m.tenant_id = t.tenant_id and m.key = k
                                    join app.activation_milestones p on p.product = t.product and p.tenant_id = t.tenant_id and p.key = keys[greatest(i - 1, 1)::int]
                                    where i > 1)) order by i)
              from unnest(keys) with ordinality u(k, i)));
end $fn$;

-- retention (0025): a logos cell without any snapshot for the cohort that month is null, not 0 (R-4); churn per
-- month with paying_start and mrr_lost (NOK); first_snapshot (R-2)
create or replace function public.analytics_retention(p_product text default null, p_mode text default 'logos') returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('global', 'reports_others');
  if p_mode not in ('logos', 'revenue') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'mode'; end if;
  return jsonb_build_object('mode', p_mode,
    'first_snapshot', (select min(day) from app.mrr_tenant_daily where app.in_scope(p_product, product)),
    'cohorts', coalesce((with co as (select s.product, s.tenant_id, date_trunc('month', s.confirmed_at)::date cohort from app.subscriptions s
                                     where s.confirmed_at > now() - interval '12 months' and app.in_scope(p_product, s.product)),
                              me as (select t.product, t.tenant_id, date_trunc('month', t.day)::date as month, max(t.mrr) mrr from app.mrr_tenant_daily t group by 1, 2, 3)
      select jsonb_agg(jsonb_build_object('cohort', to_char(cohort, 'YYYY-MM'), 'size', size, 'cells', cells) order by cohort) from (
        select co.cohort, count(distinct (co.product, co.tenant_id)) size,
               (select jsonb_agg(v order by k) from (
                  select k, case when p_mode = 'logos' then case when count(me.month) = 0 then null
                                                                 else round(100.0 * count(*) filter (where me.mrr > 0) / nullif(count(distinct (c2.product, c2.tenant_id)), 0), 1) end
                                 else round(100.0 * sum(me.mrr) / nullif(sum(m0.mrr), 0), 1) end v
                  from generate_series(0, (extract(year from age(date_trunc('month', now()), co.cohort)) * 12 + extract(month from age(date_trunc('month', now()), co.cohort)))::int) k
                  join co c2 on c2.cohort = co.cohort
                  left join me on me.product = c2.product and me.tenant_id = c2.tenant_id and me.month = (co.cohort + make_interval(months => k))::date
                  left join me m0 on m0.product = c2.product and m0.tenant_id = c2.tenant_id and m0.month = co.cohort
                  group by k) z) cells
        from co group by co.cohort) x), '[]'::jsonb),
    -- paying_start: paying subscriptions in the last daily snapshot before the month began (null without one)
    'churn_by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(x.month, 'YYYY-MM'), 'logos', x.churned, 'mrr_lost', x.lost,
                                                                    'paying_start', (select sum(m.paying) from app.mrr_daily m
                                                                                     where m.day = (select max(m2.day) from app.mrr_daily m2 where m2.day < x.month)
                                                                                       and app.in_scope(p_product, m.product))) order by x.month) from (
        select date_trunc('month', c.churned_at)::date as month, count(*) churned, coalesce(sum(c.mrr_lost) filter (where not app.non_nok(c.product, c.tenant_id)), 0) lost
        from app.account_churns c where app.in_scope(p_product, c.product) and date_trunc('month', c.churned_at) > date_trunc('month', now()) - interval '12 months'
        group by 1) x), '[]'::jsonb),
    'reasons', coalesce((select jsonb_agg(jsonb_build_object('code', coalesce(r.code, 'unknown'), 'count', n) order by n desc) from (
        select c.reason_id, count(*) n from app.account_churns c where c.churned_at > now() - interval '6 months' and app.in_scope(p_product, c.product) group by c.reason_id) x
        left join app.churn_reasons r on r.id = x.reason_id), '[]'::jsonb));
end $fn$;

-- R-4: the churns themselves, so the reason can be set with analytics_set_churn_reason. p_days: 30 | 90 | 180 | 365.
create function public.analytics_churns(p_product text default null, p_days int default 90) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 180, 365) then p_days else 90 end;
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object(
    'churns', coalesce((select jsonb_agg(jsonb_build_object('product', c.product, 'tenant_id', c.tenant_id, 'organization_id', o.id, 'organization', o.name,
                                                            'churned_at', c.churned_at, 'mrr_lost', c.mrr_lost, 'currency', s.currency,
                                                            'payment_failure', c.payment_failure, 'reason', r.code) order by c.churned_at desc)
                        from app.account_churns c
                        left join app.churn_reasons r on r.id = c.reason_id
                        left join app.subscriptions s on s.product = c.product and s.tenant_id = c.tenant_id
                        left join app.account_products ap on ap.product = c.product and ap.tenant_id = c.tenant_id
                        left join lateral (select o.id, o.name from app.organizations o where o.account_id = ap.account_id and o.deleted_at is null
                                           order by o.created_at limit 1) o on true
                        where c.churned_at > now() - make_interval(days => d) and app.in_scope(p_product, c.product)), '[]'::jsonb),
    'reasons', coalesce((select jsonb_agg(code order by ord) from app.churn_reasons), '[]'::jsonb));
end $fn$;

-- usage (0025): counts_by_product, counts_delta over the period and response_rate.all (R-5). A metric's delta is
-- null unless every tenant has a count on or before the period's start (a tenant that signed up inside the
-- period starts from zero).
create or replace function public.analytics_usage(p_product text default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end;
begin
  perform app.require('global', 'reports_others');
  return jsonb_build_object(
    'rounds', (select jsonb_build_object('main', count(*) filter (where kind = 'main'), 'pulse', count(*) filter (where kind = 'pulse')) from app.product_survey_rounds
               where opens_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'response_rate', (select jsonb_build_object('main', round(100.0 * sum(answered) filter (where kind = 'main') / nullif(sum(invited) filter (where kind = 'main'), 0), 1),
                                                'pulse', round(100.0 * sum(answered) filter (where kind = 'pulse') / nullif(sum(invited) filter (where kind = 'pulse'), 0), 1),
                                                'all', round(100.0 * sum(answered) / nullif(sum(invited), 0), 1))
                      from app.product_survey_rounds where closes_at < now() and closes_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'reminder_gain', (select round(100.0 * sum(gained_after_reminders) / nullif(sum(answered - gained_after_reminders), 0), 1) from app.product_survey_rounds
                      where closes_at > now() - make_interval(days => d) and app.in_scope(p_product, product)),
    'rounds_by_month', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'main', mn, 'pulse', pu) order by m) from (
        select date_trunc('month', opens_at) m, count(*) filter (where kind = 'main') mn, count(*) filter (where kind = 'pulse') pu from app.product_survey_rounds
        where opens_at > date_trunc('month', now()) - interval '12 months' and app.in_scope(p_product, product) group by 1) x), '[]'::jsonb),
    'logins', coalesce((select jsonb_object_agg(role, n) from (select role, sum(logins) n from app.product_logins_daily
                        where day > current_date - d and app.in_scope(p_product, product) group by role) x), '{}'::jsonb),
    'counts', coalesce((select jsonb_object_agg(metric, n) from (select metric, sum(value) n from app.product_counts where app.in_scope(p_product, product) group by metric) x), '{}'::jsonb),
    'counts_by_product', coalesce((select jsonb_object_agg(product, m) from (
        select product, jsonb_object_agg(metric, n) m from (select product, metric, sum(value) n from app.product_counts where app.in_scope(p_product, product) group by 1, 2) y
        group by product) x), '{}'::jsonb),
    'counts_delta', coalesce((select jsonb_object_agg(metric, delta) from (
        select x.metric, case when bool_and(x.base is not null) then sum(x.latest - x.base) end delta from (
          select pc.metric, pc.value latest,
                 coalesce((select h.value from app.product_counts_daily h where h.product = pc.product and h.tenant_id = pc.tenant_id and h.metric = pc.metric
                           and h.day <= current_date - d order by h.day desc limit 1),
                          case when ap.created_at > now() - make_interval(days => d) then 0 end) base
          from app.product_counts pc join app.account_products ap on ap.product = pc.product and ap.tenant_id = pc.tenant_id
          where app.in_scope(p_product, pc.product)) x group by x.metric) y), '{}'::jsonb));
end $fn$;

-- R-9: web analytics and attribution are Marketing's too (campaigns:reports_others, the right analytics_set_spend asks)
create function app.require_marketing_reports() returns uuid
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v uuid := app.require_staff();
begin
  if not (app.can('global', 'reports_others') or app.can('campaigns', 'reports_others')) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:reports_others';
  end if;
  return v;
end $fn$;

-- web (0025): bounce and signups per channel (signups by the signup's attributed channel; a session cannot be
-- joined to a signup), campaigns by utm_campaign, signups per day, the average search position (R-7)
create or replace function public.analytics_web(p_site uuid default null, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 30 end; v_tracked boolean;
begin
  perform app.require_marketing_reports();
  v_tracked := exists (select 1 from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site));
  return jsonb_build_object(
    'sites', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'hostname', hostname) order by hostname) from app.web_sites where active), '[]'::jsonb),
    'search_console', (select status from app.integration_connections where provider = 'search_console'),
    'visitors', (select count(distinct (day, visitor_hash)) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'sessions', (select count(*) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'pageviews', (select coalesce(sum(pageviews), 0) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'bounces', (select count(*) filter (where pageviews <= 1) from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site)),
    'signups', (select count(*) from app.account_products where created_at > now() - make_interval(days => d)),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visitors', v, 'sessions', s,
                                                           'signups', (select count(*) from app.account_products ap where ap.created_at::date = x.day)) order by day) from (
        select day, count(distinct visitor_hash) v, count(*) s from app.web_sessions where day > current_date - d and (p_site is null or site_id = p_site) group by day) x), '[]'::jsonb),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', x.channel, 'sessions', x.n, 'bounce', x.b, 'signups', coalesce(g.n, 0)) order by x.n desc) from (
        select coalesce(channel, 'direct') channel, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b from app.web_sessions
        where day > current_date - d and (p_site is null or site_id = p_site) group by 1) x
        left join (select app.channel_of(coalesce(ap.attribution -> 'first_touch', ap.attribution, '{}'::jsonb)) channel, count(*) n from app.account_products ap
                   where ap.created_at > now() - make_interval(days => d) group by 1) g on g.channel = x.channel), '[]'::jsonb),
    'landing', coalesce((select jsonb_agg(jsonb_build_object('path', entry_path, 'sessions', n, 'bounce', b) order by n desc) from (
        select entry_path, count(*) n, round(100.0 * count(*) filter (where pageviews <= 1) / count(*), 1) b from app.web_sessions
        where day > current_date - d and (p_site is null or site_id = p_site) group by 1 order by 2 desc limit 10) x), '[]'::jsonb),
    -- sessions are null while no session was tracked in the period, so a campaign is never shown with 0 visits it may have had
    'campaigns', coalesce((select jsonb_agg(jsonb_build_object('campaign', coalesce(v.c, g.c), 'sessions', case when v.c is not null then v.n when v_tracked then 0 end,
                                                               'signups', coalesce(g.n, 0), 'paid', coalesce(g.paid, 0)) order by coalesce(g.n, 0) desc, coalesce(v.n, 0) desc) from
        (select s.utm ->> 'utm_campaign' c, count(*) n from app.web_sessions s
         where s.day > current_date - d and (p_site is null or s.site_id = p_site) and nullif(s.utm ->> 'utm_campaign', '') is not null group by 1) v
        full join (select coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign' c, count(*) n, count(*) filter (where sb.confirmed_at is not null) paid
                   from app.account_products ap left join app.subscriptions sb on sb.product = ap.product and sb.tenant_id = ap.tenant_id
                   where ap.created_at > now() - make_interval(days => d) and nullif(coalesce(ap.attribution -> 'first_touch', ap.attribution) ->> 'utm_campaign', '') is not null
                   group by 1) g on g.c = v.c), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'value', value, 'count', n) order by n desc) from (
        select e.name, e.value, count(*) n from app.web_events e join app.web_sessions s on s.id = e.session_id
        where s.day > current_date - d and (p_site is null or s.site_id = p_site) group by 1, 2 order by 3 desc limit 20) x), '[]'::jsonb),
    'companies', (select count(distinct company_org_number) from app.web_sessions where day > current_date - d and company_org_number is not null and (p_site is null or site_id = p_site)),
    -- position: Search Console's average, weighted by impressions; null where it reported none
    'search', coalesce((select jsonb_agg(jsonb_build_object('query', query, 'impressions', i, 'clicks', c, 'position', p) order by c desc) from (
        select query, sum(impressions) i, sum(clicks) c,
               round(sum(position * impressions) filter (where position is not null) / nullif(sum(impressions) filter (where position is not null), 0), 1) p
        from app.search_console_daily where day > current_date - d and (p_site is null or site_id = p_site)
        group by 1 order by 3 desc limit 10) x), '[]'::jsonb));
end $fn$;

-- attribution (0025): MRR in NOK only with excluded_currency (R-1); the channels of the period's spend appear even
-- without signups, and spend sums NOK only (R-8); each spend row says its currency; Marketing may read it (R-9)
create or replace function public.analytics_attribution(p_touch text default 'first', p_days int default 90) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare d int := case when p_days in (30, 90, 365) then p_days else 90 end;
begin
  perform app.require_marketing_reports();
  if p_touch not in ('first', 'last') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'touch'; end if;
  return jsonb_build_object('touch', p_touch,
    'has_last_touch', exists (select 1 from app.account_products where attribution ? 'last_touch'),
    'excluded_currency', (select count(*) from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                          where ap.created_at > now() - make_interval(days => d) and app.sub_mrr(s) > 0 and s.currency <> 'NOK'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('channel', ch, 'signups', coalesce(x.signups, 0), 'activated', coalesce(x.act, 0), 'paid', coalesce(x.paid, 0),
                                                              'mrr', coalesce(x.mrr, 0), 'spend', sp.amount)
                                    order by coalesce(x.signups, 0) desc, sp.amount desc nulls last) from (
      select app.channel_of(coalesce(ap.attribution -> (p_touch || '_touch'), case when p_touch = 'first' then ap.attribution end, '{}'::jsonb)) ch,
             count(*) signups,
             count(*) filter (where exists (select 1 from app.activation_milestones m where m.product = ap.product and m.tenant_id = ap.tenant_id and m.key = 'result_unlocked')) act,
             count(*) filter (where s.confirmed_at is not null) paid,
             coalesce(sum(app.sub_mrr(s)) filter (where s.currency = 'NOK'), 0) mrr
      from app.account_products ap left join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
      where ap.created_at > now() - make_interval(days => d) group by 1) x
      full join (select ms.channel ch, sum(ms.amount) filter (where ms.currency = 'NOK') amount from app.marketing_spend ms
                 where ms.channel is not null and ms.month > date_trunc('month', now() - make_interval(days => d)) group by 1) sp using (ch)), '[]'::jsonb),
    'spend', coalesce((select jsonb_agg(jsonb_build_object('campaign', campaign, 'month', to_char(month, 'YYYY-MM'), 'channel', channel, 'amount', amount, 'currency', currency)
                                        order by month desc, campaign)
                       from app.marketing_spend where month > date_trunc('month', now() - make_interval(days => d))), '[]'::jsonb));
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['app.report_pipeline(jsonb)', 'app.progress_sql(jsonb, jsonb, int)', 'app.report_progress(jsonb, jsonb)',
                           'app.products_where(jsonb, jsonb, int)', 'app.report_products(jsonb, jsonb)', 'app.non_nok(text, text)',
                           'app.require_marketing_reports()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.analytics_churns(text, int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
