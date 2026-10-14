-- 0090_leaderpact.sql — LeaderPact, the second product, and the public site's content by API.
--
-- LeaderPact (repo torlambrechts-sketch/leaderpact, Supabase tgxjbshdjwoemsmrtkzw) is the platform's second
-- product (its REUSE_EVALUATION 2.0, E1–E8). Its owner chose neutral names for a second product (E2): one
-- `product-events` receiver for every product, `x-platform-*` headers, a `product` field and one key per product.
--
-- 1. **The product, its installation and its site.** `leaderpact` with its project's address and public key
--    (public by design). The installation is off until LeaderPact hands over both secrets through
--    secret-intake (store_product_secrets enables it then), so nothing is ingested before that.
--    leaderpact.com is its site, so the crawler, Search Console and PageSpeed pick it up like Orgpuls's.
-- 2. **A use for content.** `product_event_kinds.uses` gains `content`: the public site's own pages.
-- 3. **The lead guard.** `ingest_product_events` is the receiver's door into `ingest_events`: a request for a
--    template, a demo or a contact from one address is taken five times an hour at most, and two hundred
--    from one product. Orgpuls rate-limits in its own database (its 0208); LeaderPact sends at once and keeps
--    nothing, so the limit sits here. A refused event is counted, never stored.
-- 4. **The content inventory.** A `content.inventory` event from a product lists its public site's pages
--    (articles, templates, product pages) with the searches each answers, and the keywords it tracks. It is
--    projected into Growth › SEO: each page's first search becomes a content-plan row (an idea while planned,
--    published with its path once live, never moved back from a stage someone set), every search a tracked
--    keyword (at most 200 per site), and a page's first publication a change in the log. Nothing is
--    deleted: a page that leaves the inventory keeps its plan row for a person to decide.
--    A content event carries no person and no answer: titles, paths, dates and searches.

-- ===========================================================================
-- 1. the product, its installation and its site
-- ===========================================================================
insert into app.products (key, name, description, color, ink, ord, stage)
values ('leaderpact', 'LeaderPact', 'Leadership team performance', '#CCCBDC', '#3A3950', 20, 'beta')
on conflict (key) do nothing;

insert into app.installations (product, api_url, public_key, enabled, region, api_version)
values ('leaderpact', 'https://tgxjbshdjwoemsmrtkzw.supabase.co', 'sb_publishable_lixC6rd8xFC6P0dm_C0jbw_-toyRpJ-', false, 'eu-central-1', '1')
on conflict (product) do nothing;

insert into app.web_sites (hostname, key, product, ord)
values ('leaderpact.com', 'leaderpact-com', 'leaderpact', 30)
on conflict (hostname) do update set product = excluded.product, active = true;

-- ===========================================================================
-- 2. content as a use of an event kind, and LeaderPact's kinds
-- ===========================================================================
alter table app.product_event_kinds drop constraint if exists product_event_kinds_uses_check;
alter table app.product_event_kinds add constraint product_event_kinds_uses_check
  check (uses <@ array['crm', 'funnel', 'billing', 'health', 'activation', 'usage', 'tickets', 'leads', 'workflows', 'support_access', 'content']);

insert into app.product_event_kinds (product, kind, uses, label_key) values
  ('leaderpact', 'template.requested', array['tickets', 'leads'], 'platform.eventUse.template_requested'),
  ('leaderpact', 'content.inventory', array['content'], 'platform.eventUse.content_inventory')
on conflict (product, kind) do update set uses = excluded.uses, label_key = excluded.label_key;

-- ===========================================================================
-- 3. the receiver's door: the lead guard, then ingest_events
-- ===========================================================================
create or replace function public.ingest_product_events(p_product text, p_events jsonb) returns jsonb
  language plpgsql security definer set search_path = ''
as $fn$
declare
  e        jsonb;
  v_keep   jsonb := '[]'::jsonb;
  v_kind   text;
  v_mail   text;
  v_refused int := 0;
  v_seen   jsonb := '{}'::jsonb;
  v_result jsonb;
begin
  if jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 500 then
    raise exception 'ingest: events must be an array of at most 500' using errcode = 'invalid_parameter_value';
  end if;
  for e in select * from jsonb_array_elements(p_events) loop
    v_kind := e ->> 'kind';
    if v_kind in ('template.requested', 'demo.requested', 'contact.submitted') then
      v_mail := lower(btrim(coalesce(e -> 'payload' ->> 'email', '')));
      -- this batch's own requests count too, so one batch cannot carry a flood past the guard
      if (select count(*) from app.events_in x
          where x.product = p_product and x.kind = v_kind and lower(x.payload ->> 'email') = v_mail
            and x.received_at > now() - interval '1 hour') + coalesce((v_seen ->> v_mail)::int, 0) >= 5
         or (select count(*) from app.events_in x
             where x.product = p_product and x.kind in ('template.requested', 'demo.requested', 'contact.submitted')
               and x.received_at > now() - interval '1 hour') >= 200 then
        v_refused := v_refused + 1;
        continue;
      end if;
      v_seen := v_seen || jsonb_build_object(v_mail, coalesce((v_seen ->> v_mail)::int, 0) + 1);
    end if;
    v_keep := v_keep || jsonb_build_array(e);
  end loop;
  v_result := public.ingest_events(p_product, v_keep);
  return v_result || jsonb_build_object('refused', v_refused);
end $fn$;
comment on function public.ingest_product_events(text, jsonb) is
  'product-events'' door into ingest_events (0090): at most five lead requests an hour from one address, two hundred from one product.';

-- ===========================================================================
-- 4. the content inventory, projected into Growth › SEO
-- ===========================================================================
create or replace function app.content_inventory_apply(p_event bigint) returns void
  language plpgsql security definer set search_path = ''
as $fn$
declare
  ev       app.events_in;
  v_site   uuid;
  v_host   text;
  it       jsonb;
  q        text;
  v_query  text;
  v_path   text;
  v_status text;
  v_day    date;
  v_count  int;
  v_plan   app.seo_content_plan;
begin
  select * into ev from app.events_in where id = p_event;
  if not found then return; end if;
  v_host := lower(btrim(coalesce(ev.payload ->> 'site', '')));
  v_host := regexp_replace(v_host, '^www\.', '');
  -- the product's own site only: a product never writes another's
  select s.id into v_site from app.web_sites s
  where s.product = ev.product and s.active and (s.hostname = v_host or v_host = any (s.aliases))
  order by s.ord limit 1;
  if v_site is null then
    insert into app.audit (actor, action, target_type, target_id, ok, detail)
    values ('system', 'content.skipped', 'event', p_event::text, false, jsonb_build_object('reason', 'site'));
    return;
  end if;

  for it in select * from jsonb_array_elements(case when jsonb_typeof(ev.payload -> 'items') = 'array' then ev.payload -> 'items' else '[]'::jsonb end) loop
    v_path := it ->> 'path';
    v_status := it ->> 'status';
    v_query := lower(btrim(coalesce(it -> 'queries' ->> 0, '')));
    -- a path on the site, of the plan's shape (a regex repeat may not exceed 255, so the length is its own test)
    if coalesce(v_path, '') !~ '^/[a-z0-9/-]*$' or char_length(v_path) > 300 or coalesce(v_status, '') not in ('published', 'planned')
       or char_length(v_query) not between 1 and 200 then
      continue;
    end if;
    v_day := case when (it ->> 'published') ~ '^\d{4}-\d{2}-\d{2}$' then (it ->> 'published')::date end;

    select * into v_plan from app.seo_content_plan p where p.site_id = v_site and p.query = v_query;
    if not found then
      insert into app.seo_content_plan (site_id, query, kind, path, stage, published_at)
      values (v_site, v_query, 'gap', v_path, case when v_status = 'published' then 'published' else 'idea' end,
              case when v_status = 'published' then coalesce(v_day, current_date)::timestamptz end);
    else
      -- a stage someone set is never moved back; a page that went live moves on to published
      update app.seo_content_plan p set
        path = coalesce(p.path, v_path),
        stage = case when v_status = 'published' and p.stage in ('idea', 'writing') then 'published' else p.stage end,
        published_at = case when v_status = 'published' then coalesce(p.published_at, coalesce(v_day, current_date)::timestamptz) else p.published_at end,
        updated_at = now()
      where p.id = v_plan.id;
    end if;

    -- a page's first publication is a change in the log, on the day it went live
    if v_status = 'published' and not exists (select 1 from app.seo_changes c where c.site_id = v_site and c.path = v_path and c.kind = 'new_page') then
      insert into app.seo_changes (site_id, day, path, query, kind, note, source)
      values (v_site, coalesce(v_day, current_date), v_path, v_query, 'new_page', left(nullif(btrim(it ->> 'title'), ''), 200), 'plan');
    end if;
  end loop;

  -- tracked keywords: every search named, at most 200 per site
  for q in select lower(btrim(x)) from jsonb_array_elements_text(case when jsonb_typeof(ev.payload -> 'keywords') = 'array' then ev.payload -> 'keywords' else '[]'::jsonb end) x loop
    continue when char_length(q) not between 1 and 200;
    select count(*) into v_count from app.seo_keywords k where k.site_id = v_site;
    exit when v_count >= 200;
    insert into app.seo_keywords (site_id, query) values (v_site, q) on conflict (site_id, query) do nothing;
  end loop;
exception when others then
  -- the event stands: an inventory that cannot be applied never loses what was received
  insert into app.audit (actor, action, target_type, target_id, ok, detail)
  values ('system', 'content.skipped', 'event', p_event::text, false, jsonb_build_object('reason', sqlstate));
end $fn$;

create or replace function app.content_inventory_trigger() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
begin
  perform app.content_inventory_apply(new.id);
  return new;
end $fn$;

create or replace trigger events_in_content after insert on app.events_in for each row
  when (new.kind = 'content.inventory')
  execute function app.content_inventory_trigger();

-- ===========================================================================
-- 5. rights
-- ===========================================================================
revoke all on function public.ingest_product_events(text, jsonb) from public, anon, authenticated;
grant execute on function public.ingest_product_events(text, jsonb) to service_role;
revoke all on function app.content_inventory_apply(bigint) from public, anon, authenticated;
revoke all on function app.content_inventory_trigger() from public, anon, authenticated;
