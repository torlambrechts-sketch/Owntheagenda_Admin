-- 0040_phase6_requests.sql — the Phase 6 screens' database requests (docs/crm-enrichment/requests/campaigns.md
-- R-CAMPAIGNS-02..05, projects.md R-PROJECTS-02 and 04, insights INS-01 / V-P6P-02 / V-P6C-17).
--
-- Campaigns: the active coupons for the promotion select (campaigns:see), a segment field for product activity at
-- tenant level (D-19), the campaign's language (frozen with the content), and the marketing template versions with a
-- restore. Projects: a template line's day is a task's start offset, and whether the PDF worker runs (provider «pdf»).
-- Insights: report entities «project» and «campaign».
--
-- Redefined in full from their newest bodies: app.filter_sql (0037), app.campaign_guard, app.campaign_row,
-- public.campaign_save, public.campaign_duplicate (0037), app.prj_template_row (0038), app.report_dim (0034),
-- app.report_measure, app.report_check (0024), app.report_run (0034), public.report_fields (0024); the provider check of
-- app.integration_connections with the full list of 0030.
--
-- Left open (storage buckets, edge functions, workers): R-CAMPAIGNS-01 (image upload), R-PROJECTS-01 (record-files
-- signer), R-PROJECTS-03 (AI worker), and the PDF worker itself (R-PROJECTS-02 gives the screen its state only).

-- ===========================================================================
-- R-CAMPAIGNS-02: the active coupons a promotion may carry, under campaigns:see (billing_overview needs global:see)
-- ===========================================================================
create function public.campaign_coupons() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('campaigns');
  return coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'description', c.description, 'percent', c.percent, 'months', c.months) order by c.code)
                   from app.coupons c where c.active), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- R-CAMPAIGNS-03: a segment field for product activity
-- ===========================================================================
-- the people filter (0037), plus product activity (R-CAMPAIGNS-03): product.last_round_days, the days since a survey round last
-- opened in a tenant of the person's organisation (its account's products) or of their own product membership. Tenant-level dates
-- only (D-19): nothing about a round but when it opened. Null when no tenant ever ran one (test it with «empty»).
create or replace function app.filter_sql(e app.entities, p_filters jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    -- 0037: the audience fields of a person (CMP-03): the organization's columns and its subscription status, the
    -- product user's role, and the days since the person's last human open or click of any campaign
    elsif e.key = 'person' and f in ('organization.name', 'organization.employees', 'organization.industry', 'organization.nace', 'organization.city',
                                     'organization.fylke', 'organization.country', 'organization.postal_code') then
      col := format('(select o.%I from app.organizations o where o.id = t.organization_id and o.deleted_at is null)', substr(f, 14));
      kind := case when f = 'organization.employees' then 'int' else 'text' end;
    elsif e.key = 'person' and f = 'organization.status' then
      col := $c$(select x.st from (select app.sub_status(s) st from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.status = 'active'
                 join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id where o.id = t.organization_id and o.deleted_at is null) x
                 order by array_position(array['active', 'past_due', 'trial', 'suspended', 'free', 'cancelled', 'expired'], x.st) limit 1)$c$;
      kind := 'text';
    elsif e.key = 'person' and f = 'member.role' then
      col := '(select m.role from app.members m where m.product = t.member_product and m.tenant_id = t.member_tenant and m.user_id = t.member_user)';
      kind := 'text';
    elsif e.key = 'person' and f in ('engagement.opened_days', 'engagement.clicked_days') then
      col := format('(select floor(extract(epoch from now() - max(r.%I)) / 86400) from app.campaign_recipients r where r.person_id = t.id)',
                    case when f = 'engagement.opened_days' then 'last_open_at' else 'last_click_at' end);
      kind := 'numeric';
    elsif e.key = 'person' and f = 'product.last_round_days' then
      col := $c$(select floor(extract(epoch from now() - max(r.opens_at)) / 86400) from app.product_survey_rounds r
                 where r.opens_at <= now()
                   and ((r.product, r.tenant_id) in (select ap.product, ap.tenant_id from app.organizations o join app.account_products ap on ap.account_id = o.account_id
                                                     where o.id = t.organization_id and o.deleted_at is null)
                        or (r.product = t.member_product and r.tenant_id = t.member_tenant)))$c$;
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
end $function$;

-- ===========================================================================
-- R-CAMPAIGNS-04: the campaign's language — the renderer's own words (footer) follow it; frozen with the content
-- ===========================================================================
alter table app.campaigns add column language text not null default 'nb' check (language in ('nb', 'nn', 'en', 'sv'));

-- (0037; the language is now part of the fixed content) a scheduled or sent campaign keeps what it sent (the report shows it); a segment or template removed later is set
-- null by its foreign key, never replaced; only a draft (or a sandbox sample) can be deleted
create or replace function app.campaign_guard() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if old.status = 'draft' or old.is_sample then return old; end if;
    raise exception 'a sent campaign is kept for its report' using errcode = 'insufficient_privilege';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'draft' and new.status in ('scheduled', 'active'))
    or (old.status = 'scheduled' and new.status in ('sending', 'canceled'))
    or (old.status = 'sending' and new.status = 'sent')
    or (old.status = 'active' and new.status = 'paused')
    or (old.status = 'paused' and new.status = 'active')) then
    raise exception 'a campaign cannot move from % to %', old.status, new.status using errcode = 'insufficient_privilege';
  end if;
  if old.status <> 'draft' then
    if old.deleted_at is null and new.deleted_at is not null and not old.is_sample then
      raise exception 'a sent campaign is kept for its report' using errcode = 'insufficient_privilege';
    end if;
    if (new.type, new.design, new.html, new.rendered_html, new.subject_a, new.subject_b, new.preheader, new.ab_percent, new.ab_metric, new.ab_wait,
        new.sender_domain_id, new.product, new.coupon_code, new.utm_source, new.utm_medium, new.utm_campaign, new.tracking, new.scheduled_at, new.audience_name, new.language)
       is distinct from
       (old.type, old.design, old.html, old.rendered_html, old.subject_a, old.subject_b, old.preheader, old.ab_percent, old.ab_metric, old.ab_wait,
        old.sender_domain_id, old.product, old.coupon_code, old.utm_source, old.utm_medium, old.utm_campaign, old.tracking, old.scheduled_at, old.audience_name, old.language)
       or (new.segment_id is distinct from old.segment_id and new.segment_id is not null)
       or (new.template_id is distinct from old.template_id and new.template_id is not null)
       or (old.ab_winner is not null and new.ab_winner is distinct from old.ab_winner) then
      raise exception 'a scheduled or sent campaign''s content is fixed' using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end $fn$;

-- the campaign row (0037); the detail carries the language
create or replace function app.campaign_row(c app.campaigns, p_detail boolean default false) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare sv app.saved_views; d app.sender_domains; v_live jsonb; v_reports boolean := app.campaign_reports_ok(c); out jsonb;
begin
  select * into sv from app.saved_views where id = c.segment_id;
  select * into d from app.sender_domains where id = c.sender_domain_id;
  if c.type <> 'automated' and c.audience_count is null and sv.id is not null and c.status in ('draft', 'scheduled') then
    v_live := app.segment_counts(sv.query, c.is_sample);
  end if;
  out := jsonb_build_object(
    'id', c.id, 'seq', c.seq, 'name', c.name, 'type', c.type, 'status', c.status, 'hold_reason', c.hold_reason,
    'owner_id', c.owner_id, 'owner', (select a.name from app.admins a where a.id = c.owner_id), 'mine', c.owner_id = app.me(),
    'audience', case when c.type = 'automated' then jsonb_build_object('kind', 'workflow', 'workflows', app.campaign_workflows(c.id))
                     else jsonb_build_object('kind', 'segment', 'segment_id', c.segment_id, 'name', coalesce(c.audience_name, sv.name),
                                             'count', coalesce(c.audience_count, (v_live ->> 'receivable')::int), 'matches', (v_live ->> 'matches')::int,
                                             'live', c.audience_count is null) end,
    'scheduled_at', c.scheduled_at, 'started_at', c.started_at, 'sent_at', c.sent_at, 'canceled_at', c.canceled_at,
    'stream', d.stream, 'sender_domain', d.domain, 'subject_a', c.subject_a, 'subject_b', c.subject_b,
    'ab', case when c.subject_b is not null then jsonb_build_object('percent', c.ab_percent, 'metric', c.ab_metric, 'wait_hours', extract(epoch from c.ab_wait)::int / 3600,
                                                                     'winner', c.ab_winner, 'decided_at', c.ab_decided_at,
                                                                     'decides_at', case when c.started_at is not null then c.started_at + c.ab_wait end) end,
    'notify_owners', c.notify_owners, 'version', c.version, 'updated_at', c.updated_at,
    'stats', case when v_reports then app.campaign_stats(c.id) end, 'reports', v_reports);
  if p_detail then
    out := out || jsonb_build_object(
      'segment', case when sv.id is not null then jsonb_build_object('id', sv.id, 'name', sv.name, 'query', sv.query) end,
      'template_id', c.template_id, 'design', c.design, 'html', c.html, 'rendered_html', c.rendered_html, 'preheader', c.preheader,
      'sender_domain_id', c.sender_domain_id, 'from_name', d.from_name, 'from', case when d.id is not null then d.from_local || '@' || d.domain end,
      'postal_address', d.postal_address, 'product', c.product, 'coupon_code', c.coupon_code, 'language', c.language,
      'utm', jsonb_build_object('source', c.utm_source, 'medium', c.utm_medium, 'campaign', c.utm_campaign), 'tracking', c.tracking,
      'tracking_rule', app.setting('tracking'), 'visibility', c.visibility, 'labels', to_jsonb(c.labels),
      'links', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'label', l.label,
                                                             'clicks', case when v_reports then (select count(distinct e.recipient_id) from app.campaign_events e
                                                                                                 where e.link_id = l.id and e.kind = 'clicked' and e.client_class <> 'prefetch') end)
                                          order by l.url) from app.campaign_links l where l.campaign_id = c.id), '[]'::jsonb),
      -- the provider's city of human opens; omitted (empty) when the provider sends no geo. Never an IP.
      'top_locations', case when v_reports then coalesce((select jsonb_agg(x.city order by x.n desc, x.city) from (
                                 select r.city, count(*) n from app.campaign_recipients r where r.campaign_id = c.id and r.first_open_at is not null and r.city is not null
                                 group by r.city order by count(*) desc, r.city limit 4) x), '[]'::jsonb) end,
      'provider_connected', app.connected('email'),
      'domain', case when d.id is not null then jsonb_build_object('authenticated', app.domain_authenticated(d), 'verified', app.domain_verified(d)) end);
  end if;
  return out;
end $fn$;

-- (0037, plus the language) create a draft (p_id null) or change one. A template starts a campaign by copying its design (CMP-02). Once
-- scheduled, only the name and the owner notice may change: the content is what was sent.
create or replace function public.campaign_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', 'add'); c app.campaigns; v jsonb := coalesce(p_values, '{}'::jsonb); t app.email_templates;
  v_type text; v_name text; v_design jsonb; v_html text; v_sb text; v_id uuid; k text;
begin
  perform app.require_module('campaigns');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('type', 'name', 'segment_id', 'template_id', 'design', 'html', 'subject_a', 'subject_b', 'preheader', 'ab_percent', 'ab_metric', 'ab_wait_hours',
                 'sender_domain_id', 'product', 'coupon_code', 'utm_source', 'utm_medium', 'utm_campaign', 'tracking', 'notify_owners', 'visibility', 'language') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_id is not null then
    c := app.campaign_take(p_id, 'edit');
    if p_version is not null and c.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = c.version::text; end if;
    if c.status <> 'draft' and exists (select 1 from jsonb_object_keys(v) x where x not in ('name', 'notify_owners')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
    end if;
  end if;
  v_type := coalesce(v ->> 'type', c.type);
  if v_type is null or v_type not in ('newsletter', 'one_off', 'promotion', 'product_announcement', 'automated') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type';
  end if;
  v_name := btrim(coalesce(v ->> 'name', c.name));
  if coalesce(v_name, '') = '' or char_length(v_name) > 120 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  -- the template a campaign starts from: a layout, a shared template or one of mine
  if v ? 'template_id' and v ->> 'template_id' is not null then
    select * into t from app.email_templates x where x.id = (v ->> 'template_id')::uuid and x.kind = 'marketing' and x.deleted_at is null
      and (x.layout or x.scope = 'shared' or x.owner_id = v_me);
    if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'template_id'; end if;
  end if;
  v_html := case when v ? 'html' then nullif(v ->> 'html', '') when v ? 'design' then null when t.id is not null then t.html else c.html end;
  v_design := case when v ? 'design' then v -> 'design' when v ? 'html' then '{"rows":[]}'::jsonb when t.id is not null then coalesce(t.design, '{"rows":[]}'::jsonb)
                   else coalesce(c.design, '{"rows":[{"kind":"header","bg":"card"},{"kind":"footer","bg":"cream"}]}'::jsonb) end;
  if v_html is not null then
    perform app.campaign_html_check(v_html);
  else
    perform app.campaign_design_check(v_design);
  end if;
  if v ? 'segment_id' and v ->> 'segment_id' is not null and not exists (
       select 1 from app.saved_views s where s.id = (v ->> 'segment_id')::uuid and s.kind = 'segment' and (s.shared or s.owner_id = v_me)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'segment_id';
  end if;
  if v ? 'sender_domain_id' and v ->> 'sender_domain_id' is not null and not exists (
       select 1 from app.sender_domains d where d.id = (v ->> 'sender_domain_id')::uuid and d.deleted_at is null and d.stream = 'marketing' and d.sends_here) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sender_domain_id';
  end if;
  if v ? 'product' and v ->> 'product' is not null and not exists (select 1 from app.products p where p.key = v ->> 'product') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  if (v ? 'coupon_code' and v ->> 'coupon_code' is not null and not exists (select 1 from app.coupons x where x.code = v ->> 'coupon_code' and x.active))
     or (v_type <> 'promotion' and coalesce(case when v ? 'coupon_code' then v ->> 'coupon_code' else c.coupon_code end, '') <> '') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coupon_code';
  end if;
  if char_length(coalesce(v ->> 'subject_a', '')) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject_a'; end if;
  v_sb := case when v ? 'subject_b' then nullif(btrim(v ->> 'subject_b'), '') else c.subject_b end;
  if char_length(coalesce(v_sb, '')) > 200 or (v_sb is not null and v_type = 'automated') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject_b';
  end if;
  if char_length(coalesce(v ->> 'preheader', '')) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'preheader'; end if;
  if v ? 'ab_percent' and v ->> 'ab_percent' is not null and (jsonb_typeof(v -> 'ab_percent') <> 'number' or (v ->> 'ab_percent')::numeric not between 2 and 50) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ab_percent';
  end if;
  if v ? 'ab_metric' and v ->> 'ab_metric' is not null and v ->> 'ab_metric' not in ('opens', 'clicks') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ab_metric';
  end if;
  if v ? 'ab_wait_hours' and v ->> 'ab_wait_hours' is not null and (jsonb_typeof(v -> 'ab_wait_hours') <> 'number' or (v ->> 'ab_wait_hours')::numeric not between 1 and 72) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ab_wait_hours';
  end if;
  foreach k in array array['utm_source', 'utm_medium'] loop
    if v ? k and coalesce(v ->> k, '') !~ '^[a-z0-9_-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if v ? 'utm_campaign' and coalesce(v ->> 'utm_campaign', '') !~ '^[a-z0-9_-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'utm_campaign'; end if;
  foreach k in array array['tracking', 'notify_owners'] loop
    if v ? k and jsonb_typeof(v -> k) <> 'boolean' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if v ? 'visibility' and coalesce(v ->> 'visibility', '') not in ('owner', 'group', 'group_sub', 'all') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'visibility';
  end if;
  if v ? 'language' and coalesce(v ->> 'language', '') not in ('nb', 'nn', 'en', 'sv') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'language';
  end if;

  if p_id is null then
    insert into app.campaigns (name, type, segment_id, template_id, design, html, subject_a, subject_b, preheader, ab_percent, ab_metric, ab_wait,
                               sender_domain_id, product, coupon_code, utm_source, utm_medium, utm_campaign, tracking, notify_owners,
                               owner_id, visibility, created_by, updated_by, is_sample, language)
    values (v_name, v_type, (v ->> 'segment_id')::uuid, t.id, v_design, v_html, coalesce(btrim(v ->> 'subject_a'), nullif(t.subject, ''), ''), v_sb,
            nullif(btrim(v ->> 'preheader'), ''),
            case when v_sb is not null then coalesce((v ->> 'ab_percent')::smallint, 20) end,
            case when v_sb is not null then coalesce(v ->> 'ab_metric', 'clicks') end,
            case when v_sb is not null then make_interval(hours => coalesce((v ->> 'ab_wait_hours')::int, 4)) end,
            (v ->> 'sender_domain_id')::uuid, v ->> 'product', nullif(v ->> 'coupon_code', ''),
            coalesce(v ->> 'utm_source', 'newsletter'), coalesce(v ->> 'utm_medium', 'email'), app.campaign_utm(v ->> 'utm_campaign', v_name),
            coalesce((v ->> 'tracking')::boolean, true), coalesce((v ->> 'notify_owners')::boolean, false),
            v_me, coalesce(v ->> 'visibility', app.setting('visibility_default', 'campaign')), v_me, v_me, (select sandbox from app.admins where id = v_me),
            coalesce(v ->> 'language', 'nb'))
    returning id into v_id;
    insert into app.changelog (entity, record_id, field, actor_id, source) values ('campaign', v_id, '*created', v_me, 'ui');
    perform app.log('record.created', 'campaign', v_id::text, jsonb_build_object('type', v_type, 'template', t.id is not null));
  else
    v_id := c.id;
    if c.status = 'draft' then
      update app.campaigns set name = v_name, type = v_type,
        segment_id = case when v ? 'segment_id' then (v ->> 'segment_id')::uuid else segment_id end,
        template_id = case when v ? 'template_id' then t.id else template_id end,
        design = v_design, html = v_html,
        subject_a = case when v ? 'subject_a' then coalesce(btrim(v ->> 'subject_a'), '') when t.id is not null and subject_a = '' then t.subject else subject_a end,
        subject_b = v_sb,
        preheader = case when v ? 'preheader' then nullif(btrim(v ->> 'preheader'), '') else preheader end,
        ab_percent = case when v_sb is null then null else coalesce((v ->> 'ab_percent')::smallint, ab_percent, 20) end,
        ab_metric = case when v_sb is null then null else coalesce(v ->> 'ab_metric', ab_metric, 'clicks') end,
        ab_wait = case when v_sb is null then null else coalesce(make_interval(hours => (v ->> 'ab_wait_hours')::int), ab_wait, interval '4 hours') end,
        sender_domain_id = case when v ? 'sender_domain_id' then (v ->> 'sender_domain_id')::uuid else sender_domain_id end,
        product = case when v ? 'product' then v ->> 'product' else product end,
        coupon_code = case when v ? 'coupon_code' then nullif(v ->> 'coupon_code', '') else coupon_code end,
        utm_source = coalesce(v ->> 'utm_source', utm_source), utm_medium = coalesce(v ->> 'utm_medium', utm_medium),
        utm_campaign = case when v ? 'utm_campaign' then app.campaign_utm(v ->> 'utm_campaign', v_name, c.id) else utm_campaign end,
        tracking = coalesce((v ->> 'tracking')::boolean, tracking), notify_owners = coalesce((v ->> 'notify_owners')::boolean, notify_owners),
        visibility = coalesce(v ->> 'visibility', visibility), language = coalesce(v ->> 'language', language),
        version = version + 1, updated_at = now(), updated_by = v_me
      where id = c.id;
    else
      update app.campaigns set name = v_name, notify_owners = coalesce((v ->> 'notify_owners')::boolean, notify_owners), version = version + 1, updated_at = now(), updated_by = v_me
      where id = c.id;
    end if;
    if v_name is distinct from c.name then
      insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('campaign', c.id, 'name', to_jsonb(c.name), to_jsonb(v_name), v_me, 'ui');
    end if;
    perform app.log('record.updated', 'campaign', c.id::text, jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(v) x)));
  end if;
  return app.campaign_row((select x from app.campaigns x where x.id = v_id), true);
end $fn$;

-- (0037, plus the language) a copy as a new draft of mine (a sent campaign is kept; its copy is edited)
create or replace function public.campaign_duplicate(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'see'); v_me uuid := app.require('campaigns', 'add'); v_id uuid;
begin
  insert into app.campaigns (name, type, segment_id, template_id, design, html, subject_a, subject_b, preheader, ab_percent, ab_metric, ab_wait,
                             sender_domain_id, product, coupon_code, utm_source, utm_medium, utm_campaign, tracking, notify_owners,
                             owner_id, visibility, created_by, updated_by, is_sample, language)
  select c.name, c.type,
         (select s.id from app.saved_views s where s.id = c.segment_id and (s.shared or s.owner_id = v_me)), c.template_id, c.design, c.html, c.subject_a, c.subject_b, c.preheader,
         c.ab_percent, c.ab_metric, c.ab_wait,
         (select d.id from app.sender_domains d where d.id = c.sender_domain_id and d.deleted_at is null), c.product,
         (select x.code from app.coupons x where x.code = c.coupon_code and x.active), c.utm_source, c.utm_medium,
         app.campaign_utm(null, c.name), c.tracking, c.notify_owners, v_me, c.visibility, v_me, v_me, (select sandbox from app.admins where id = v_me), c.language
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values ('campaign', v_id, '*created', jsonb_build_object('copy_of', c.id), v_me, 'ui');
  perform app.log('record.created', 'campaign', v_id::text, jsonb_build_object('copy_of', c.id));
  return app.campaign_row((select x from app.campaigns x where x.id = v_id), true);
end $fn$;

-- ===========================================================================
-- R-CAMPAIGNS-05: a marketing template's versions, and restoring one as the next version
-- ===========================================================================
create function public.marketing_template_versions(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); t app.email_templates;
begin
  perform app.require_module('campaigns');
  select * into t from app.email_templates where id = p_id and kind = 'marketing' and deleted_at is null
    and (coalesce((select sandbox from app.admins where id = v_me), false) or not is_sample);
  if not found or not (t.layout or t.scope = 'shared' or t.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('version', x.version, 'subject', x.subject, 'created_at', x.created_at,
                                                       'by', (select a.name from app.admins a where a.id = x.created_by)) order by x.version desc)
                   from app.email_template_versions x where x.template_id = t.id), '[]'::jsonb);
end $fn$;

-- the chosen version's subject and design (or HTML) saved as the next version, through marketing_template_save (its rights:
-- add; another's template edit_others; a layout configure); the history is never rewritten
create function public.marketing_template_restore(p_id uuid, p_version int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); t app.email_templates; x app.email_template_versions; r jsonb;
begin
  perform app.require_module('campaigns');
  select * into t from app.email_templates where id = p_id and kind = 'marketing' and deleted_at is null;
  if not found or not (t.layout or t.scope = 'shared' or t.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into x from app.email_template_versions where template_id = t.id and version = p_version;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'version'; end if;
  if x.version = t.current_version then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'version'; end if;
  r := public.marketing_template_save(t.id, jsonb_build_object('subject', x.subject)
         || case when x.html is not null then jsonb_build_object('html', x.html) else jsonb_build_object('design', x.design) end, t.version);
  perform app.log('template.restored', 'email_template', t.id::text, jsonb_build_object('kind', 'marketing', 'from_version', x.version, 'version', r -> 'current_version'));
  return r;
end $fn$;

-- ===========================================================================
-- R-PROJECTS-04: a template line's day is the day it starts
-- ===========================================================================
-- the template cards (0038): counts computed, the first five items as «Day N», N the day an item starts: a task's start offset
-- when it has one, else its due offset; a milestone's or an activity's due offset (R-PROJECTS-04)
create or replace function app.prj_template_row(t app.project_templates) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', t.id, 'name', t.name, 'description', t.description, 'organized_by', t.organized_by, 'board_id', t.board_id,
    'source_project_id', t.source_project_id, 'version', t.version, 'updated_at', t.updated_at,
    'created_by', t.created_by, 'creator', (select a.name from app.admins a where a.id = t.created_by),
    'groups', (select count(*) from app.project_template_groups g where g.template_id = t.id),
    'tasks', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'task'),
    'milestones', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'milestone'),
    'activities', (select count(*) from app.project_template_items i where i.template_id = t.id and i.kind = 'activity'),
    'dependencies', (select count(*) from app.project_template_dependencies d where d.template_id = t.id),
    'preview', coalesce((select jsonb_agg(jsonb_build_object('day', x.day, 'kind', x.kind, 'name', x.name) order by x.day nulls last, x.ord) from (
                select case when i.kind = 'task' then coalesce(i.start_offset_days, i.due_offset_days) else coalesce(i.due_offset_days, i.start_offset_days) end as day, i.kind, i.name, i.ord from app.project_template_items i where i.template_id = t.id
                order by case when i.kind = 'task' then coalesce(i.start_offset_days, i.due_offset_days) else coalesce(i.due_offset_days, i.start_offset_days) end nulls last, i.ord limit 5) x), '[]'::jsonb),
    'can_edit', (t.created_by = app.me() and app.can('projects', 'add')) or app.can('projects', 'configure'))
$fn$;

-- ===========================================================================
-- R-PROJECTS-02: whether the PDF worker runs — provider «pdf», connected when the worker is deployed with its key
-- ===========================================================================
alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai',
                      'email', 'ip_company', 'esign', 'pdf'));
insert into app.integration_connections (provider) values ('pdf') on conflict do nothing;

-- the status-report dialog's «Create PDF» follows this: a report requested while no worker runs would stay «requested» for ever
create function public.project_pdf_status() returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  perform app.require('projects', 'see');
  perform app.require_module('projects');
  return jsonb_build_object('pdf_connected', app.connected('pdf'));
end $fn$;

-- ===========================================================================
-- INS-01 (V-P6P-02, V-P6C-17): report entities «project» and «campaign»
-- ===========================================================================
-- a dimension (0024), with two changes: «stage» orders by pipeline first, then stage (R-INSIGHTS-03), and
-- «lost_reason» maps the free text to the configured lost reasons, case-insensitively, with anything else
-- under one «Other» key (R-INSIGHTS-04). 0040: a project's «board» and «phase» (labels and order from their tables);
-- its status and health, and a campaign's type and status, are columns of the registry and take the generic rule
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
  elsif p_dim = 'board' and e.key = 'project' then
    return jsonb_build_object('expr', 't.board_id::text', 'label', '(select b.name from app.project_boards b where b.id::text = v)',
                              'ord', '(select b.ord from app.project_boards b where b.id::text = v)');
  elsif p_dim = 'phase' and e.key = 'project' then
    return jsonb_build_object('expr', 't.phase_id::text', 'label', '(select ph.name from app.project_phases ph where ph.id::text = v)',
                              'ord', '(select array[b.ord, ph.ord] from app.project_phases ph join app.project_boards b on b.id = ph.board_id where ph.id::text = v)');
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

-- the measure as SQL (0024): count | sum | avg | weighted | cycle_days, over a field; 0040: duration_days (project), sent,
-- open_rate, click_rate (campaign)
create or replace function app.report_measure(e app.entities, p_measure jsonb) returns text
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
  -- 0040: a project's average duration in days, from creation to closing (or today while open)
  if fn = 'duration_days' then
    if e.key <> 'project' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure'; end if;
    return 'round(avg(extract(epoch from coalesce(t.closed_at, now()) - t.created_at) / 86400), 1)';
  end if;
  -- 0040: a campaign's figures from app.campaign_stats, the same function as the campaign screens (CMP-09). Sent is summed; the
  -- open and click rates are pooled over the tracked campaigns only (unique opens or clicks ÷ delivered), null with none
  if fn in ('sent', 'open_rate', 'click_rate') then
    if e.key <> 'campaign' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'measure'; end if;
    if fn = 'sent' then return 'coalesce(sum((app.campaign_stats(t.id) ->> ''sent'')::numeric), 0)'; end if;
    return format('round(100.0 * sum((app.campaign_stats(t.id) ->> %L)::numeric) / nullif(sum((app.campaign_stats(t.id) ->> ''delivered'')::numeric) '
                  || 'filter (where (app.campaign_stats(t.id) ->> ''tracking'')::boolean), 0), 1)', case fn when 'open_rate' then 'unique_opens' else 'unique_clicks' end);
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

-- validate a definition; returns the entity (0024; 0040: project and campaign, each with its module on)
create or replace function app.report_check(p_def jsonb) returns app.entities
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities;
begin
  if p_def is null or jsonb_typeof(p_def) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'definition'; end if;
  if p_def ->> 'entity' not in ('deal', 'activity', 'lead', 'person', 'organization', 'project', 'campaign') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'entity';
  end if;
  e := app.entity(p_def ->> 'entity');
  if e.key in ('project', 'campaign') then perform app.require_module(e.module); end if;
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

-- run a definition (0034): progress and products are computed as themselves; 0040: a project's Duration report is its average
-- duration, rates are percent and durations days
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
  if p_def ->> 'type' = 'duration' and e.key = 'project' then m := app.report_measure(e, '{"fn":"duration_days"}'); end if;
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
                            'unit', case when p_def -> 'measure' ->> 'fn' in ('open_rate', 'click_rate') then 'percent'
                                         when m like '%cycle%' or p_def -> 'measure' ->> 'fn' in ('cycle_days', 'duration_days')
                                              or (p_def ->> 'type' = 'duration' and e.key = 'project') then 'days'
                                         when m like '%t.value%' then 'nok' else 'count' end);
end $fn$;

-- the fields a report can use, from the registry (0024; 0040: a project's board and phase, and the extra measures)
create or replace function public.report_fields(p_entity text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities := app.entity(p_entity);
begin
  perform app.require(e.scope, 'see');
  return jsonb_build_object(
    'dimensions', to_jsonb(array_remove(array[case when e.owned then 'owner' end, case when e.key = 'deal' then 'stage' end, case when e.key = 'deal' then 'pipeline' end,
                                              case when e.key = 'activity' then 'type' end,
                                              case when e.key = 'project' then 'board' end, case when e.key = 'project' then 'phase' end, 'label', 'created_month',
                                              case when e.key = 'deal' then 'won_month' end, case when e.key = 'deal' then 'close_month' end,
                                              case when e.key = 'activity' then 'done_month' end], null)
                   || array(select c.col from app.entity_columns c where c.entity = e.key and ((c.kind in ('text', 'boolean', 'int') and c.ref is null) or c.ref is not null) order by c.ord)),
    'numeric', to_jsonb(array(select c.col from app.entity_columns c where c.entity = e.key and c.kind in ('numeric', 'int') order by c.ord)),
    'dates', to_jsonb(array['created_at'] || array(select c.col from app.entity_columns c where c.entity = e.key and c.kind in ('date', 'timestamptz') order by c.ord)),
    -- 0040: the measures beyond count, sum and avg this record type offers
    'measures', to_jsonb(case e.key when 'deal' then array['weighted', 'cycle_days'] when 'project' then array['duration_days']
                                    when 'campaign' then array['sent', 'open_rate', 'click_rate'] else array[]::text[] end),
    'custom', coalesce((select jsonb_agg(jsonb_build_object('key', 'custom.' || f.key, 'label', f.label, 'type', f.type) order by f.ord)
                        from app.fields f where f.entity = e.key and f.archived_at is null), '[]'::jsonb));
end $fn$;

-- ===========================================================================
-- grants: internal functions for nobody, the public ones for signed-in staff
-- ===========================================================================
do $$
declare f text;
begin
  foreach f in array array['app.filter_sql(app.entities, jsonb)', 'app.campaign_guard()', 'app.campaign_row(app.campaigns, boolean)',
                           'app.prj_template_row(app.project_templates)', 'app.report_dim(app.entities, text)', 'app.report_measure(app.entities, jsonb)',
                           'app.report_check(jsonb)', 'app.report_run(jsonb, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.campaign_coupons()', 'public.campaign_save(uuid, jsonb, int)', 'public.campaign_duplicate(uuid)',
                           'public.marketing_template_versions(uuid)', 'public.marketing_template_restore(uuid, int)', 'public.project_pdf_status()',
                           'public.report_fields(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
