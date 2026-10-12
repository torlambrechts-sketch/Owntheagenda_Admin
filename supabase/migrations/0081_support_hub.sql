-- 0081_support_hub.sql — Customers › Help centre and support (docs/crm-enrichment/v3/support-gap.md, PLAN.md wave 1)
--
-- 1. Two production defects, fixed first:
--    F-S1  Orgpuls' contact form sends a topic (product, pricing, first_send, privacy) and no category, and its in-app Hjelp
--          sends the customer's words as «body», not «message». The intake ignored both: every contact landed in Sales,
--          a privacy request too, with no 30-day clock, and an in-app request arrived without its text. Topics now route
--          through app.contact_topic_routes; a ticket in the personvern category gets its privacy_requests row (the clock);
--          only a contact routed to the Sales queue makes a CRM lead, titled by its subject or its category and never by
--          the customer's message (rule 6: a lead is read by roles that may not see the ticket).
--    F-S2  An out-of-office answer from the requester reopened a resolved ticket. Inbound mail now matches the hidden
--          reference header (In-Reply-To, References) before the [T-n] subject. An auto-reply by its headers (Auto-Submitted,
--          Precedence, X-Autoreply, X-Autorespond, X-Auto-Response-Suppress) neither threads nor reopens; a subject in the
--          auto-reply shape («Automatisk svar:», «Out of office:» …, colon required) is kept in the thread without reopening,
--          so a customer whose subject merely starts with «Fravær» is never lost.
-- 2. Help centre: help_articles gains a product, a translation group, a per-product slug, an SEO title, app pages,
--    a review stamp, a source and a generated Norwegian/English full-text vector; readers, an editor, review, publish
--    (publishing stays tickets:configure, as before) and search.
-- 3. Support results, channels and the portal preview, from tickets and CSAT. Help sessions, self-service, AI acceptance,
--    views and «solved within 24 h» have no source until the widget is embedded: nothing here invents them.
-- 4. AI (X-V3-2: ticket text is never sent to Claude): one feature, «answer from published articles», whose input is a
--    staff member's own typed test question and the product's published articles; a per-product switch for it.
-- 5. Status: components, incidents with append-only updates, «Resolve and notify» on problem_resolve; the changelog reads
--    release_notes (0078). Nothing is public yet (no host decided).
-- 6. CSAT: the resolving reply carries a single-use token (only its hash is stored); the csat edge function takes a score
--    for it and nothing else.
-- Every table: app schema, RLS on, no policy, no grant. Every reader and writer: SECURITY DEFINER, search_path ''.

-- ===========================================================================
-- 0. helpers
-- ===========================================================================
create function app.support_product(p_product text) returns void
  language plpgsql stable security definer set search_path = ''
as $fn$
begin
  if p_product is null or not exists (select 1 from app.products p where p.key = p_product) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
end $fn$;

-- a ticket the signed-in staff member may see: its queue, its visibility, samples only in the sandbox
create function app.support_ticket_ok(t app.tickets) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select t.deleted_at is null and app.queue_ok(t.queue_key) and app.visible(t.owner_id, t.visibility)
     and (not t.is_sample or coalesce((select a.sandbox from app.admins a where a.id = app.me()), false))
$fn$;

-- ===========================================================================
-- 1. F-S1: the contact form's topic decides the category; privacy gets its clock
-- ===========================================================================
create table app.contact_topic_routes (
  product      text not null references app.products (key) on delete cascade,
  topic        text not null check (topic ~ '^[a-z][a-z_]{1,30}$'),
  category_key text not null references app.ticket_categories (key),
  ord          int not null default 0,
  -- since when the topic is recorded: a count over a period that began earlier would be a false number (support_channels)
  created_at   timestamptz not null default now(),
  primary key (product, topic)
);
alter table app.contact_topic_routes enable row level security;
revoke all on app.contact_topic_routes from public, anon, authenticated;
-- Orgpuls' «Skriv til oss» (submit_contact, Orgpuls 0206): its four topics, in its own order
insert into app.contact_topic_routes (product, topic, category_key, ord) values
  ('orgpuls', 'product', 'getting_started', 10), ('orgpuls', 'pricing', 'sales', 20),
  ('orgpuls', 'first_send', 'survey_delivery', 30), ('orgpuls', 'privacy', 'personvern', 40)
on conflict do nothing;

create or replace function app.ticket_intake(p_event bigint) returns uuid
  language plpgsql security definer set search_path = ''
as $fn$
declare e app.events_in; v_id uuid; v_org uuid; v_cat text; v_person uuid; v_lead uuid; v_email text; v_req jsonb;
        v_topic text; v_message text; v_subject text;
begin
  select * into e from app.events_in where id = p_event;
  if not found or e.kind not in ('support.requested', 'contact.submitted') then return null; end if;
  if exists (select 1 from app.tickets where source_event_id = p_event) then return null; end if;
  select o.id into v_org from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  where ap.product = e.product and ap.tenant_id = e.tenant_id and o.deleted_at is null limit 1;
  -- the customer's words: Orgpuls' in-app Hjelp sends them as «body», the contact form as «message» (F-S1)
  v_message := coalesce(nullif(btrim(e.payload ->> 'message'), ''), nullif(btrim(e.payload ->> 'body'), ''));
  -- the contact form's topic, when it is one (F-S1)
  if e.kind = 'contact.submitted' then
    v_topic := nullif(lower(btrim(coalesce(e.payload ->> 'topic', ''))), '');
    if v_topic !~ '^[a-z][a-z_]{1,30}$' then v_topic := null; end if;
  end if;
  v_cat := coalesce(
    (select c.key from app.ticket_categories c where c.key = e.payload ->> 'category' and c.active),
    (select r.category_key from app.contact_topic_routes r join app.ticket_categories c on c.key = r.category_key and c.active
     where r.product = e.product and r.topic = v_topic),
    case e.kind when 'contact.submitted' then 'sales' else 'getting_started' end);
  v_subject := coalesce(nullif(btrim(e.payload ->> 'subject'), ''),
                        nullif(left(btrim(split_part(coalesce(v_message, ''), E'\n', 1)), 120), ''),
                        (select c.name from app.ticket_categories c where c.key = v_cat), e.kind);
  v_id := app.ticket_from_capture(v_cat, v_subject, e.payload ->> 'email', v_org, v_message,
                                  case e.kind when 'contact.submitted' then 'contact_form' else 'in_app' end, null, e.product,
                                  jsonb_strip_nulls(jsonb_build_object('role', e.payload ->> 'role', 'page', e.payload ->> 'page', 'browser', e.payload ->> 'browser',
                                                                       'app_version', e.payload ->> 'app_version')),
                                  p_event);
  if v_topic is not null then
    update app.tickets set topic = v_topic where id = v_id;
  end if;
  -- a request in the personvern category starts the 30-day clock (F-S1). The form does not say which right is asked for:
  -- it is recorded as access, the widest, until a person reads it (V-V3S-02).
  if v_cat = 'personvern' then
    insert into app.privacy_requests (ticket_id, organization_id, kind, requester_category, received_at)
    values (v_id, v_org, 'access', case e.kind when 'contact.submitted' then 'contact_form' else 'in_app' end, least(coalesce(e.occurred_at, now()), now()));
    insert into app.audit (actor, action, target_type, target_id, ok, detail)
    values ('system', 'privacy_request.received', 'ticket', v_id::text, true, jsonb_build_object('event', p_event));
  end if;
  if e.kind = 'support.requested' then
    v_req := app.ticket_request(e.payload -> 'request');
    if v_req is not null then
      update app.tickets set type = 'service_request', request = v_req where id = v_id;
    end if;
  end if;
  -- a contact routed to the Sales queue becomes a CRM lead. A support topic or a privacy request is not a sale. The lead's
  -- title is the form's subject or the category, never the message: a lead is read under deals:see, by roles that may not
  -- see the ticket's queue, and the message is the customer's own words (rule 6).
  if e.kind = 'contact.submitted' and (select c.queue_key from app.ticket_categories c where c.key = v_cat) = 'sales' then
    begin
      v_email := lower(nullif(btrim(e.payload ->> 'email'), ''));
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
      v_person := app.capture_person(v_email, case when v_email is not null then e.payload ->> 'name' end, null, v_org, 'Contact form', null);
      if v_person is not null or v_org is not null then
        v_lead := app.capture_lead(coalesce(nullif(btrim(e.payload ->> 'subject'), ''), (select c.name from app.ticket_categories c where c.key = v_cat), e.kind),
                                   v_person, v_org, 'Contact form', null, null);
        insert into app.ticket_links (ticket_id, kind, ref) values (v_id, 'lead', v_lead::text) on conflict do nothing;
        update app.tickets set person_id = coalesce(person_id, v_person) where id = v_id;
      end if;
    exception when others then
      -- the ticket stands: a lead that cannot be made never loses the request
      insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'lead.skipped', 'ticket', v_id::text, false, jsonb_build_object('event', p_event));
    end;
  end if;
  return v_id;
end $fn$;

-- ===========================================================================
-- 2. F-S2: the reference header first; an auto-reply never threads and never reopens
-- ===========================================================================
-- p_headers: the lower-cased header names mail-events passes (a whitelist), each a string. p_subject: an auto-reply's subject
-- shape, a known prefix followed by a colon («Automatisk svar: …», «Out of office: …», «Fravær: …»); a subject that only
-- begins with such a word («Fravær i rapporten [T-12]») is a customer's. Either argument may be empty: the caller asks about
-- the headers and the subject separately, because they are trusted differently.
create function app.mail_auto_reply(p_headers jsonb, p_subject text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select lower(btrim(coalesce(p_headers ->> 'auto-submitted', 'no'))) not in ('no', '')
      or lower(btrim(coalesce(p_headers ->> 'precedence', ''))) in ('auto_reply', 'bulk', 'junk', 'list')
      or btrim(coalesce(p_headers ->> 'x-autoreply', '')) <> ''
      or btrim(coalesce(p_headers ->> 'x-autorespond', '')) <> ''
      or lower(coalesce(p_headers ->> 'x-auto-response-suppress', '')) ~ '(^|[,\s])(all|oof|autoreply)([,\s]|$)'
      or lower(coalesce(p_subject, '')) ~ '^\s*(auto(matic|matisk|matiskt|matische)?[ -]?(reply|response|svar|antwort)|automatisk svar|automatiskt svar|automatische antwort|out of (the )?office( reply)?|fraværsmelding|fravær|frånvaro(meddelande)?|abwesenheit(snotiz)?|ikke til stede|ikkje til stades)\s*:'
$fn$;

create function public.worker_ticket_inbound(p_inbound_id text, p_from text, p_subject text, p_body text, p_headers jsonb)
  returns jsonb language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_num bigint; t app.tickets; v_tid uuid; v_body text := btrim(coalesce(p_body, '')); v_msg uuid; v_refs text[];
        h jsonb := case when jsonb_typeof(p_headers) = 'object' then p_headers else '{}'::jsonb end;
begin
  if coalesce(btrim(p_inbound_id), '') = '' or char_length(p_inbound_id) > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'id'; end if;
  if exists (select 1 from app.ticket_messages where inbound_id = p_inbound_id) then return jsonb_build_object('matched', true, 'duplicate', true); end if;
  if v_body = '' then return jsonb_build_object('matched', false); end if;
  -- the hidden reference header: the Message-ID of a reply Sentral sent, with or without its angle brackets
  v_refs := array(select x from (select m[1] x from regexp_matches(left(coalesce(h ->> 'in-reply-to', '') || ' ' || coalesce(h ->> 'references', ''), 4000),
                                                                   '<([^<>\s]{3,250})>', 'g') m) s
                  union select '<' || x || '>' from (select m[1] x from regexp_matches(left(coalesce(h ->> 'in-reply-to', '') || ' ' || coalesce(h ->> 'references', ''), 4000),
                                                                                  '<([^<>\s]{3,250})>', 'g') m) s2);
  if cardinality(v_refs) > 0 then
    select x.ticket_id into v_tid from app.ticket_messages x where x.provider_message_id = any (v_refs) and x.kind = 'reply' order by x.created_at desc limit 1;
  end if;
  -- then the ticket number in the subject
  if v_tid is null then
    v_num := nullif(substring(coalesce(p_subject, '') from '\[T-(\d{1,12})\]'), '')::bigint;
    if v_num is not null then select x.id into v_tid from app.tickets x where x.number = v_num and x.deleted_at is null; end if;
  end if;
  if v_tid is null then return jsonb_build_object('matched', false); end if;
  select * into t from app.tickets where id = v_tid and deleted_at is null for update;
  if not found or app.ticket_recipient(t) is distinct from lower(btrim(coalesce(p_from, ''))) then return jsonb_build_object('matched', false); end if;
  -- an auto-reply by its headers is a machine's, not the customer's answer: it is not kept (F-S2)
  if app.mail_auto_reply(h, null) then
    insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'ticket.auto_reply_ignored', 'ticket', t.id::text, true, null);
    return jsonb_build_object('matched', true, 'auto_reply', true);
  end if;
  insert into app.ticket_messages (ticket_id, kind, author_person_id, body, inbound_id)
  values (t.id, 'customer', t.person_id, left(v_body, 20000), p_inbound_id) returning id into v_msg;
  -- a subject in the auto-reply shape alone is a guess: the words are kept in the thread, but the ticket is not reopened
  -- and nobody is called to it
  if app.mail_auto_reply('{}'::jsonb, p_subject) then
    insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'ticket.auto_reply_kept', 'ticket', t.id::text, true, null);
    return jsonb_build_object('matched', true, 'auto_reply', true, 'kept', true);
  end if;
  update app.tickets set status = case when status in ('waiting_customer', 'resolved') then 'waiting_us' when status = 'closed' then 'open' else status end,
    reopened_count = reopened_count + case when status in ('resolved', 'closed') then 1 else 0 end, version = version + 1, updated_at = now()
  where id = t.id;
  perform app.emit('ticket.customer_replied', 'ticket', t.id, jsonb_build_object('message', v_msg), t.is_sample);
  if t.assignee_id is not null then
    perform app.notify(t.assignee_id, 'system', 'tickets.customer_replied', jsonb_build_object('record', 'T-' || t.number),
                       '/tickets?ticket=' || t.id, 'ticket', t.id);
  end if;
  return jsonb_build_object('matched', true);
end $fn$;

-- the four-argument form (0060) answers the same way, without headers: the subject rule still holds
create or replace function public.worker_ticket_inbound(p_inbound_id text, p_from text, p_subject text, p_body text)
  returns jsonb language sql volatile security definer set search_path = ''
as $fn$
  select public.worker_ticket_inbound(p_inbound_id, p_from, p_subject, p_body, '{}'::jsonb)
$fn$;

-- ===========================================================================
-- 3. help articles: product, translation group, per-product slug, SEO title, app pages, review, source, full text
-- ===========================================================================
-- an app path a help article may be suggested on: a path only, never a respondent page (/s/…)
create function app.help_path_ok(p text) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select p is not null and p ~ '^/[a-z0-9/_-]{0,120}$' and p !~ '^/s(/|$)'
$fn$;
create function app.help_pages_ok(p text[]) returns boolean
  language sql immutable set search_path = ''
as $fn$
  select coalesce(cardinality(p), 0) <= 10 and coalesce((select bool_and(app.help_path_ok(x)) from unnest(p) x), true)
$fn$;

alter table app.help_articles
  add column product          text not null default 'orgpuls' references app.products (key),
  add column group_id         uuid not null default gen_random_uuid(),
  add column seo_title        text check (seo_title is null or char_length(btrim(seo_title)) between 1 and 200),
  add column app_pages        text[] not null default '{}' check (app.help_pages_ok(app_pages)),
  add column reviewed_at      timestamptz,
  add column reviewed_by      uuid references app.admins (id) on delete set null,
  add column source           text not null default 'staff' check (source in ('staff', 'gap', 'ticket_reply', 'ai')),
  add column source_ticket_id uuid references app.tickets (id) on delete set null,
  add column created_by       uuid references app.admins (id) on delete set null,
  add column updated_by       uuid references app.admins (id) on delete set null,
  add column search_vector    tsvector generated always as (
    case when locale = 'en'
      then setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') || setweight(to_tsvector('english'::regconfig, coalesce(body, '')), 'B')
      else setweight(to_tsvector('norwegian'::regconfig, coalesce(title, '')), 'A') || setweight(to_tsvector('norwegian'::regconfig, coalesce(body, '')), 'B')
    end) stored;
-- one slug space per product and language (it was global), one row per language in a group
alter table app.help_articles drop constraint if exists help_articles_slug_key;
alter table app.help_articles add constraint help_articles_slug_per_product unique (product, locale, slug);
alter table app.help_articles add constraint help_articles_group_locale unique (group_id, locale);
create index help_articles_search on app.help_articles using gin (search_vector);
create index help_articles_product on app.help_articles (product, status);

-- the app pages a product's articles can be suggested on (Orgpuls' signed-in pages, its repository on 2026-10-12)
create table app.help_app_pages (
  product text not null references app.products (key) on delete cascade,
  path    text not null check (app.help_path_ok(path)),
  ord     int not null default 0,
  primary key (product, path)
);
alter table app.help_app_pages enable row level security;
revoke all on app.help_app_pages from public, anon, authenticated;
insert into app.help_app_pages (product, path, ord) values
  ('orgpuls', '/malinger', 10), ('orgpuls', '/resultater', 20), ('orgpuls', '/tiltak', 30), ('orgpuls', '/rapport', 40),
  ('orgpuls', '/innsikt', 50), ('orgpuls', '/kommentarer', 60), ('orgpuls', '/oppsett', 70), ('orgpuls', '/maleoppsett', 80),
  ('orgpuls', '/integrasjoner', 90), ('orgpuls', '/hjelp', 100)
on conflict do nothing;

-- a slug from a title, Norwegian letters spelled out, unique within the product and language
create function app.help_slug(p_product text, p_locale text, p_title text, p_except uuid) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_base text; v text; n int := 1;
begin
  v_base := lower(coalesce(p_title, ''));
  v_base := replace(replace(replace(replace(v_base, 'æ', 'ae'), 'ø', 'o'), 'å', 'a'), 'é', 'e');
  v_base := btrim(regexp_replace(v_base, '[^a-z0-9]+', '-', 'g'), '-');
  v_base := btrim(left(v_base, 72), '-');
  if char_length(v_base) < 2 then v_base := 'artikkel'; end if;
  v := v_base;
  while exists (select 1 from app.help_articles a where a.product = p_product and a.locale = p_locale and a.slug = v and a.id is distinct from p_except) loop
    n := n + 1;
    v := v_base || '-' || n;
  end loop;
  return v;
end $fn$;

create function app.help_article_json(p_id uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object(
    'id', a.id, 'product', a.product, 'group_id', a.group_id, 'locale', a.locale, 'slug', a.slug, 'title', a.title, 'body', a.body,
    'category_key', a.category_key, 'status', a.status, 'version', a.version, 'problem_id', a.problem_id,
    'problem_number', (select t.number from app.tickets t where t.id = a.problem_id),
    'seo_title', a.seo_title, 'app_pages', to_jsonb(a.app_pages), 'source', a.source, 'published_at', a.published_at,
    'reviewed_at', a.reviewed_at, 'reviewed_by', (select coalesce(x.name, x.email) from app.admins x where x.id = a.reviewed_by),
    'updated_at', a.updated_at,
    'linked_tickets', (select count(*) from app.ticket_links l where l.kind = 'article' and l.ref = a.id::text),
    'siblings', coalesce((select jsonb_agg(jsonb_build_object('locale', s.locale, 'id', s.id, 'status', s.status) order by s.locale)
                          from app.help_articles s where s.group_id = a.group_id), '[]'::jsonb))
  from app.help_articles a where a.id = p_id
$fn$;

-- the help centre of one product: one row per article group (bokmål first), its languages, measured views and links
create function public.help_centre_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
        v_measured boolean;
begin
  perform app.support_product(p_product);
  -- views exist only once something records them (the public help centre and widget, not built: V-V3S-05)
  v_measured := exists (select 1 from app.help_article_stats_daily s join app.help_articles a on a.id = s.article_id
                        where a.product = p_product and s.day > current_date - 30);
  return jsonb_build_object(
    'measured', v_measured,
    'can_edit', app.can('tickets', 'edit_others'),
    'can_publish', app.can('tickets', 'configure'),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key', c.key, 'name', c.name) order by c.ord)
                            from app.ticket_categories c where c.active and c.key not in ('personvern', 'sales')), '[]'::jsonb),
    'pages', coalesce((select jsonb_agg(p.path order by p.ord, p.path) from app.help_app_pages p where p.product = p_product), '[]'::jsonb),
    'articles', coalesce((select jsonb_agg(jsonb_build_object(
        'id', g.id, 'group_id', g.group_id, 'title', g.title, 'category_key', g.category_key, 'status', g.status, 'locale', g.locale,
        'locales', g.locales, 'problem', g.problem_id is not null, 'updated_at', g.updated_at,
        'views', case when v_measured then g.views end, 'linked_tickets', g.linked) order by g.updated_at desc)
      from (select distinct on (a.group_id) a.id, a.group_id, a.title, a.category_key, a.status, a.locale, a.problem_id, a.updated_at,
                   (select jsonb_agg(s.locale order by case s.locale when 'nb' then 1 when 'nn' then 2 else 3 end) from app.help_articles s where s.group_id = a.group_id) locales,
                   (select coalesce(sum(st.views), 0) from app.help_article_stats_daily st join app.help_articles s on s.id = st.article_id
                    where s.group_id = a.group_id and st.day > current_date - 30) views,
                   (select count(*) from app.ticket_links l join app.help_articles s on l.ref = s.id::text where l.kind = 'article' and s.group_id = a.group_id) linked
            from app.help_articles a
            where a.product = p_product and (v_sandbox or not a.is_sample)
            order by a.group_id, case a.locale when 'nb' then 1 when 'nn' then 2 else 3 end) g), '[]'::jsonb));
end $fn$;

create function public.help_article_get(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v jsonb;
begin
  v := app.help_article_json(p_id);
  if v is null or ((v ->> 'id') is not null and exists (select 1 from app.help_articles a where a.id = p_id and a.is_sample
                                                       and not coalesce((select x.sandbox from app.admins x where x.id = v_me), false))) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  return v;
end $fn$;

-- create (p_id null) or edit an article; an edit names the version it was made on
create function public.help_article_write(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others'); a app.help_articles; k text; v_id uuid; v_title text; v_locale text; v_product text;
        v_group uuid; v_cat text; v_pages text[]; v_problem uuid; v_source text;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(p_values) loop
    if k not in ('product', 'locale', 'group_id', 'title', 'body', 'category_key', 'seo_title', 'app_pages', 'problem_id', 'source') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_values ? 'title' then
    v_title := btrim(coalesce(p_values ->> 'title', ''));
    if char_length(v_title) not between 1 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  end if;
  if p_values ? 'body' and char_length(coalesce(p_values ->> 'body', '')) > 20000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  if p_values ? 'seo_title' and nullif(btrim(coalesce(p_values ->> 'seo_title', '')), '') is not null and char_length(btrim(p_values ->> 'seo_title')) > 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'seo_title';
  end if;
  if p_values ? 'category_key' then
    v_cat := nullif(p_values ->> 'category_key', '');
    if v_cat is not null and not exists (select 1 from app.ticket_categories c where c.key = v_cat and c.active) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'category_key';
    end if;
  end if;
  if p_values ? 'app_pages' then
    if jsonb_typeof(p_values -> 'app_pages') is distinct from 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'app_pages'; end if;
    v_pages := array(select jsonb_array_elements_text(p_values -> 'app_pages'));
    if not app.help_pages_ok(v_pages) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'app_pages'; end if;
  end if;
  if p_values ? 'problem_id' then
    v_problem := nullif(p_values ->> 'problem_id', '')::uuid;
    if v_problem is not null and not exists (select 1 from app.tickets t where t.id = v_problem and t.type = 'problem' and t.deleted_at is null) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'problem_id';
    end if;
  end if;

  if p_id is null then
    v_product := p_values ->> 'product';
    perform app.support_product(v_product);
    v_locale := coalesce(p_values ->> 'locale', 'nb');
    if v_locale not in ('nb', 'nn', 'en') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'locale'; end if;
    if v_title is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
    v_source := coalesce(p_values ->> 'source', 'staff');
    if v_source not in ('staff', 'gap') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'source'; end if;
    -- a translation joins its group: same product, a language the group does not have yet
    if p_values ? 'group_id' then
      v_group := (p_values ->> 'group_id')::uuid;
      if not exists (select 1 from app.help_articles x where x.group_id = v_group and x.product = v_product) then
        raise exception 'not_found' using errcode = 'no_data_found', detail = 'group_id';
      end if;
      if exists (select 1 from app.help_articles x where x.group_id = v_group and x.locale = v_locale) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'locale';
      end if;
      v_cat := coalesce(v_cat, (select x.category_key from app.help_articles x where x.group_id = v_group limit 1));
      v_problem := coalesce(v_problem, (select x.problem_id from app.help_articles x where x.group_id = v_group and x.problem_id is not null limit 1));
    end if;
    insert into app.help_articles (product, locale, group_id, slug, title, body, category_key, seo_title, app_pages, problem_id, source, created_by, updated_by)
    values (v_product, v_locale, coalesce(v_group, gen_random_uuid()), app.help_slug(v_product, v_locale, v_title, null), v_title,
            coalesce(p_values ->> 'body', ''), v_cat, nullif(btrim(coalesce(p_values ->> 'seo_title', '')), ''), coalesce(v_pages, '{}'), v_problem, v_source, v_me, v_me)
    returning id into v_id;
    perform app.log('help_article.created', 'help_article', v_id::text, jsonb_build_object('product', v_product, 'locale', v_locale, 'source', v_source));
    return app.help_article_json(v_id);
  end if;

  select * into a from app.help_articles x where x.id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is null or p_version <> a.version then raise exception 'version_conflict' using errcode = 'serialization_failure'; end if;
  if p_values ? 'product' or p_values ? 'locale' or p_values ? 'group_id' or p_values ? 'source' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'fixed';
  end if;
  update app.help_articles x set
    title = coalesce(v_title, x.title),
    -- a slug follows the title until the article has been published once, then its address stays
    slug = case when v_title is not null and x.published_at is null and v_title <> x.title then app.help_slug(x.product, x.locale, v_title, x.id) else x.slug end,
    body = case when p_values ? 'body' then coalesce(p_values ->> 'body', '') else x.body end,
    category_key = case when p_values ? 'category_key' then v_cat else x.category_key end,
    seo_title = case when p_values ? 'seo_title' then nullif(btrim(coalesce(p_values ->> 'seo_title', '')), '') else x.seo_title end,
    app_pages = case when p_values ? 'app_pages' then v_pages else x.app_pages end,
    problem_id = case when p_values ? 'problem_id' then v_problem else x.problem_id end,
    version = x.version + 1, updated_at = now(), updated_by = v_me
  where x.id = p_id;
  perform app.log('help_article.saved', 'help_article', p_id::text, jsonb_build_object('fields', (select jsonb_agg(f) from jsonb_object_keys(p_values) f)));
  return app.help_article_json(p_id);
end $fn$;

-- publishing stays where it was (0012: tickets:configure); a published article needs a body
create function public.help_article_publish(p_id uuid, p_on boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'configure'); a app.help_articles;
begin
  select * into a from app.help_articles x where x.id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if coalesce(p_on, false) and char_length(btrim(a.body)) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  update app.help_articles x set status = case when p_on then 'published' else 'draft' end,
    published_at = case when p_on then coalesce(x.published_at, now()) else x.published_at end,
    version = x.version + 1, updated_at = now(), updated_by = v_me
  where x.id = p_id;
  perform app.log(case when p_on then 'help_article.published' else 'help_article.unpublished' end, 'help_article', p_id::text);
  return app.help_article_json(p_id);
end $fn$;

create function public.help_article_review(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others');
begin
  update app.help_articles x set reviewed_at = now(), reviewed_by = v_me where x.id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('help_article.reviewed', 'help_article', p_id::text);
  return app.help_article_json(p_id);
end $fn$;

-- full-text search over published articles of one product and language; each word may be the start of a longer one.
-- The words are not stored (PLAN: typed help-search questions are not kept).
create function public.help_search(p_product text, p_locale text, p_q text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_cfg regconfig; v_words text; v_q tsquery;
begin
  perform app.support_product(p_product);
  if p_locale is null or p_locale not in ('nb', 'nn', 'en') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'locale'; end if;
  if char_length(btrim(coalesce(p_q, ''))) not between 2 and 200 then return '[]'::jsonb; end if;
  v_cfg := case when p_locale = 'en' then 'english'::regconfig else 'norwegian'::regconfig end;
  v_words := array_to_string(array(select w || ':*' from regexp_split_to_table(lower(p_q), '[^a-z0-9æøåéü]+') w where char_length(w) >= 2 limit 8), ' & ');
  if v_words = '' then return '[]'::jsonb; end if;
  v_q := to_tsquery(v_cfg, v_words);
  if numnode(v_q) = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title,
                                                       'snippet', ts_headline(v_cfg, r.body, v_q, 'MaxFragments=1, MaxWords=22, MinWords=10, StartSel=⟦, StopSel=⟧'))
                                    order by r.rank desc)
                   from (select a.id, a.title, a.body, ts_rank(a.search_vector, v_q) rank from app.help_articles a
                         where a.product = p_product and a.locale = p_locale and a.status = 'published' and not a.is_sample and a.search_vector @@ v_q
                         order by ts_rank(a.search_vector, v_q) desc limit 6) r), '[]'::jsonb);
end $fn$;

-- ===========================================================================
-- 4. support settings (per product) and the «answer from published articles» preview (X-V3-2)
-- ===========================================================================
create table app.support_settings (
  product    text primary key references app.products (key) on delete cascade,
  ai_enabled boolean not null default true,   -- answers from published articles (the widget preview; the widget once embedded)
  updated_by uuid references app.admins (id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table app.support_settings enable row level security;
revoke all on app.support_settings from public, anon, authenticated;

create function app.support_ai_on(p_product text) returns boolean
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select s.ai_enabled from app.support_settings s where s.product = p_product), true)
$fn$;

create function public.support_settings_save(p_product text, p_ai_enabled boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'configure');
begin
  perform app.support_product(p_product);
  if p_ai_enabled is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ai_enabled'; end if;
  insert into app.support_settings (product, ai_enabled, updated_by) values (p_product, p_ai_enabled, v_me)
  on conflict (product) do update set ai_enabled = excluded.ai_enabled, updated_by = v_me, updated_at = now();
  perform app.log('support_settings.changed', 'product', p_product, jsonb_build_object('ai_enabled', p_ai_enabled));
  return jsonb_build_object('ai_enabled', p_ai_enabled);
end $fn$;

-- a staff member's own test question: the only typed text this feature sends, never a customer's
create table app.help_test_questions (
  id         uuid primary key default gen_random_uuid(),
  product    text not null references app.products (key) on delete cascade,
  locale     text not null check (locale in ('nb', 'nn', 'en')),
  question   text not null check (char_length(btrim(question)) between 3 and 500),
  created_by uuid not null references app.admins (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index help_test_questions_by on app.help_test_questions (created_by, created_at desc);
alter table app.help_test_questions enable row level security;
revoke all on app.help_test_questions from public, anon, authenticated;

-- a test question is kept 90 days, whoever asked it and whether or not they ask again (staff may paste a customer's words
-- into one); the nightly job and every new question remove the older ones
create function app.help_questions_prune() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  delete from app.help_test_questions q where q.created_at < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $fn$;
insert into app.job_defs (key, label_key, schedule, source, fn, quiet)
values ('help_questions_prune', 'jobs.help_questions_prune', '33 3 * * *', 'cron', 'app.help_questions_prune', true)
on conflict (key) do nothing;
select cron.schedule('platform-help-questions-prune', '33 3 * * *', 'select app.run_job(''help_questions_prune'')');

create function public.help_question_ask(p_product text, p_locale text, p_question text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'ai'); v_id uuid;
begin
  perform app.support_product(p_product);
  if p_locale is null or p_locale not in ('nb', 'nn', 'en') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'locale'; end if;
  if char_length(btrim(coalesce(p_question, ''))) not between 3 and 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'question'; end if;
  if not app.support_ai_on(p_product) then raise exception 'module_off' using errcode = 'object_not_in_prerequisite_state', detail = 'ai_enabled'; end if;
  -- a test question is kept 90 days, then it goes: everyone's, here and every night (app.help_questions_prune)
  perform app.help_questions_prune();
  insert into app.help_test_questions (product, locale, question, created_by) values (p_product, p_locale, btrim(p_question), v_me) returning id into v_id;
  perform app.log('help_question.asked', 'help_test_question', v_id::text, jsonb_build_object('product', p_product, 'locale', p_locale));
  return jsonb_build_object('id', v_id);
end $fn$;

-- Claude's input: the person's own question and the product's published articles in that language, nothing else
create function app.ai_ctx_help_answer_preview(p_subject uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare q app.help_test_questions; v_cfg regconfig; v_q tsquery; v_docs text := ''; r record; n int := 0; v_name text;
begin
  select * into q from app.help_test_questions x where x.id = p_subject and x.created_by = app.me();
  if not found or not app.support_ai_on(q.product) then return null; end if;
  v_cfg := case when q.locale = 'en' then 'english'::regconfig else 'norwegian'::regconfig end;
  v_q := websearch_to_tsquery(v_cfg, q.question);
  v_name := (select p.name from app.products p where p.key = q.product);
  for r in select a.title, a.body from app.help_articles a
           where a.product = q.product and a.locale = q.locale and a.status = 'published' and not a.is_sample and char_length(btrim(a.body)) > 0
           order by case when numnode(v_q) > 0 then ts_rank(a.search_vector, v_q) else 0 end desc, a.published_at desc nulls last
           limit 6 loop
    exit when char_length(v_docs) > 24000;
    n := n + 1;
    v_docs := v_docs || format(E'<article index="%s">\n<title>%s</title>\n<body>\n%s\n</body>\n</article>\n', n, r.title, left(r.body, 6000));
  end loop;
  return jsonb_build_object(
    'system', 'You answer customers of ' || coalesce(v_name, q.product) || ' in a help widget. Use ONLY the help articles inside <articles>. '
              || 'Answer in the language of the question, in plain text without Markdown, in at most 120 words. Never state anything about a '
              || 'particular customer, their account, their plan or their data: you know nothing about who is asking. If the articles do not '
              || 'answer the question, reply with exactly NO_ARTICLE and nothing else. Otherwise end with one last line: SOURCE: followed by '
              || 'the exact title of the article you used most.',
    'prompt', format(E'<articles>\n%s</articles>\n\n<question>\n%s\n</question>', v_docs, q.question));
end $fn$;

insert into app.ai_features (key, scope, action, subject_type, context_fn, max_tokens)
values ('help_answer_preview', 'tickets', 'ai', 'help_test_question', 'app.ai_ctx_help_answer_preview', 1200)
on conflict (key) do nothing;

-- ===========================================================================
-- 5. reads for the tabs: results, widget preview, channels, portal preview, AI assist
-- ===========================================================================
create function public.support_results(p_product text, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_days int := least(greatest(coalesce(p_days, 30), 7), 365);
        v_from timestamptz; v_prev timestamptz; v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
        v_measured boolean;
begin
  perform app.support_product(p_product);
  v_from := now() - make_interval(days => v_days);
  v_prev := v_from - make_interval(days => v_days);
  v_measured := exists (select 1 from app.help_article_stats_daily s join app.help_articles a on a.id = s.article_id
                        where a.product = p_product and s.day > current_date - v_days);
  return (with t as (
      select x.* from app.tickets x
      where x.product = p_product and x.type <> 'problem' and x.deleted_at is null and (v_sandbox or not x.is_sample)
        and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility)
    )
    select jsonb_build_object(
      'days', v_days,
      'tickets', jsonb_build_object(
        'created', (select count(*) from t where t.created_at >= v_from),
        'previous', (select count(*) from t where t.created_at >= v_prev and t.created_at < v_from),
        -- a delta only when Sentral received the product's tickets for the whole previous period
        'previous_complete', exists (select 1 from app.tickets y where y.product = p_product and y.created_at < v_prev)),
      'csat', jsonb_build_object(
        'avg', (select round(avg(t.csat_score)::numeric, 1) from t where t.csat_at >= v_from and t.csat_score is not null),
        'answered', (select count(*) from t where t.csat_at >= v_from and t.csat_score is not null),
        'requested', (select count(*) from t where t.csat_requested_at >= v_from),
        'previous_avg', (select round(avg(t.csat_score)::numeric, 1) from t where t.csat_at >= v_prev and t.csat_at < v_from and t.csat_score is not null)),
      -- categories that brought tickets and have no published article (search text is not stored: no «searches»)
      'gaps', coalesce((select jsonb_agg(jsonb_build_object('category_key', g.category_key, 'name', g.name, 'tickets', g.n) order by g.n desc, g.name)
                        from (select t.category_key, c.name, count(*) n from t join app.ticket_categories c on c.key = t.category_key
                              where t.created_at >= v_from and t.category_key <> 'personvern'
                                and not exists (select 1 from app.help_articles a where a.product = p_product and a.status = 'published' and a.category_key = t.category_key)
                              group by t.category_key, c.name order by count(*) desc, c.name limit 4) g), '[]'::jsonb),
      'measured', v_measured,
      'articles', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'views', case when v_measured then g.views end,
                                                               'linked_tickets', g.linked) order by g.views desc, g.title)
                            from (select distinct on (a.group_id) a.id, a.group_id, a.title,
                                         (select coalesce(sum(st.views), 0) from app.help_article_stats_daily st join app.help_articles s on s.id = st.article_id
                                          where s.group_id = a.group_id and st.day > current_date - v_days) views,
                                         (select count(*) from app.ticket_links l join app.help_articles s on l.ref = s.id::text where l.kind = 'article' and s.group_id = a.group_id) linked
                                  from app.help_articles a
                                  where a.product = p_product and a.status = 'published' and (v_sandbox or not a.is_sample)
                                  order by a.group_id, case a.locale when 'nb' then 1 when 'nn' then 2 else 3 end) g), '[]'::jsonb),
      'can_write', app.can('tickets', 'edit_others')));
end $fn$;

-- the widget preview: the pages, the published articles with their pages, the newest, the settings, and what the newest
-- in-app request really carried (the fields support.requested has; nothing is sent from Sentral)
create function public.support_widget_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
        t app.tickets;
begin
  perform app.support_product(p_product);
  select x.* into t from app.tickets x
  where x.product = p_product and x.channel = 'in_app' and x.deleted_at is null and (v_sandbox or not x.is_sample)
    and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility)
  order by x.created_at desc limit 1;
  return jsonb_build_object(
    'pages', coalesce((select jsonb_agg(p.path order by p.ord, p.path) from app.help_app_pages p where p.product = p_product), '[]'::jsonb),
    'articles', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'app_pages', to_jsonb(a.app_pages)) order by a.published_at desc nulls last)
                          from (select * from app.help_articles x where x.product = p_product and x.locale = 'nb' and x.status = 'published'
                                  and (v_sandbox or not x.is_sample) order by x.published_at desc nulls last limit 100) a), '[]'::jsonb),
    'ai_enabled', app.support_ai_on(p_product),
    'can_configure', app.can('tickets', 'configure'),
    'can_ask', app.can('tickets', 'ai'),
    'last_request', case when t.id is null then null else jsonb_build_object(
      'ref', 'T-' || t.number,
      'person', (select p.name from app.people p where p.id = t.person_id),
      'role', t.context ->> 'role', 'page', t.context ->> 'page', 'browser', t.context ->> 'browser', 'app_version', t.context ->> 'app_version',
      -- the organisation, with its size band: the plan of its subscription to this product, when that plan is one of the
      -- product's bands (Customers › Accounts shows the same)
      'organization', (select jsonb_build_object('name', o.name, 'org_number', o.org_number,
                                                 'band', (select s.plan from app.account_products ap join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                                                          where ap.account_id = o.account_id and ap.product = p_product and ap.status = 'active'
                                                            and exists (select 1 from app.plan_versions pv where pv.product = p_product and pv.band_label = s.plan)
                                                          limit 1))
                       from app.organizations o where o.id = t.organization_id),
      'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('product', p.name, 'status', app.sub_status(s), 'plan', s.plan) order by p.ord, p.name)
                                 from app.organizations o join app.account_products ap on ap.account_id = o.account_id and ap.status = 'active'
                                 join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
                                 join app.products p on p.key = ap.product
                                 where o.id = t.organization_id), '[]'::jsonb)) end);
end $fn$;

create function public.support_channels(p_product text, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_days int := least(greatest(coalesce(p_days, 30), 7), 365);
        v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 30), 7), 365));
        v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
begin
  perform app.support_product(p_product);
  return (with t as (
      select x.* from app.tickets x
      where x.product = p_product and x.type <> 'problem' and x.deleted_at is null and x.created_at >= v_from and (v_sandbox or not x.is_sample)
        and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility)
    )
    select jsonb_build_object(
      'days', v_days,
      'total', (select count(*) from t),
      'channels', (select jsonb_agg(jsonb_build_object('channel', ch.k, 'tickets', (select count(*) from t where t.channel = ch.k),
                                                       'queues', coalesce((select jsonb_agg(distinct q.name) from t join app.ticket_queues q on q.key = t.queue_key where t.channel = ch.k), '[]'::jsonb))
                                    order by ch.o)
                   from (values ('in_app', 1), ('contact_form', 2), ('email', 3), ('staff', 4)) ch(k, o)),
      -- a topic's count only when it is true: the reader sees its queue (else every ticket of it would be missing, a false 0),
      -- and the topic has been recorded for the whole period (it is new in 0081: older tickets carry none)
      'topics', coalesce((select jsonb_agg(jsonb_build_object('topic', r.topic, 'category_key', r.category_key, 'category', c.name, 'queue', q.name,
                                                              'privacy', r.category_key = 'personvern',
                                                              'visible', app.queue_ok(c.queue_key), 'since', r.created_at,
                                                              'tickets', case when app.queue_ok(c.queue_key) and r.created_at <= v_from
                                                                              then (select count(*) from t where t.channel = 'contact_form' and t.topic = r.topic) end)
                                            order by r.ord)
                          from app.contact_topic_routes r join app.ticket_categories c on c.key = r.category_key join app.ticket_queues q on q.key = c.queue_key
                          where r.product = p_product), '[]'::jsonb),
      'mail', (select jsonb_build_object('ready', app.mail_ready_for(p_product), 'inbound_ok', s.inbound_ok and s.inbound_domain is not null,
                                         'inbound_domain', case when s.inbound_ok then s.inbound_domain end, 'webhook_ok', s.webhook_ok)
               from app.mail_settings s where s.id)));
end $fn$;

-- one organisation's tickets as its customers would see them (an admin preview: the portal itself waits for Orgpuls)
create function public.portal_preview(p_product text, p_organization uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
        v_org uuid; v_orgs jsonb;
begin
  perform app.support_product(p_product);
  v_orgs := coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'tickets', g.n) order by g.last desc)
                      from (select x.organization_id, count(*) n, max(x.updated_at) last from app.tickets x
                            where x.product = p_product and x.organization_id is not null and x.type <> 'problem' and x.deleted_at is null
                              and (v_sandbox or not x.is_sample) and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility)
                            group by x.organization_id order by max(x.updated_at) desc limit 50) g
                      join app.organizations o on o.id = g.organization_id and o.deleted_at is null), '[]'::jsonb);
  v_org := case when p_organization is not null and v_orgs @> jsonb_build_array(jsonb_build_object('id', p_organization)) then p_organization
                else (v_orgs -> 0 ->> 'id')::uuid end;
  return jsonb_build_object(
    'organizations', v_orgs,
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name) from app.organizations o where o.id = v_org),
    'tickets', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'ref', 'T-' || x.number, 'subject', x.subject,
                                                             'requester', (select p.name from app.people p where p.id = x.person_id),
                                                             'status', x.status,
                                                             'state', case when x.status in ('resolved', 'closed') then 'done' when x.status = 'waiting_customer' then 'you' else 'us' end)
                                          order by case when x.status in ('resolved', 'closed') then 1 else 0 end, x.updated_at desc)
                         from (select * from app.tickets y
                               where y.organization_id = v_org and y.product = p_product and y.type <> 'problem' and y.deleted_at is null
                                 and (v_sandbox or not y.is_sample) and app.queue_ok(y.queue_key) and app.visible(y.owner_id, y.visibility)
                               order by y.updated_at desc limit 20) x), '[]'::jsonb),
    -- open privacy requests, counted only for those who may see the personvern queue; never a name
    'privacy_open', case when app.queue_ok('personvern') then (select count(*) from app.privacy_requests r
                                                                 where r.organization_id = v_org and r.status in ('received', 'in_progress')) end);
end $fn$;

-- AI assist: the ticket in view (its own line only: no thread), and Claude's use in the last 30 days, from ai_calls
create function public.support_assist_get(p_product text, p_ticket uuid default null) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
        t app.tickets;
begin
  perform app.support_product(p_product);
  if p_ticket is not null then
    select x.* into t from app.tickets x where x.id = p_ticket and x.product = p_product and x.type <> 'problem' and app.support_ticket_ok(x);
  end if;
  if t.id is null then
    select x.* into t from app.tickets x
    where x.product = p_product and x.type <> 'problem' and x.status not in ('resolved', 'closed') and x.deleted_at is null
      and (v_sandbox or not x.is_sample) and app.queue_ok(x.queue_key) and app.visible(x.owner_id, x.visibility)
    order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object(
    'ticket', case when t.id is null then null else jsonb_build_object(
      'id', t.id, 'ref', 'T-' || t.number, 'subject', t.subject,
      'organization', (select o.name from app.organizations o where o.id = t.organization_id),
      'problem', (select 'T-' || p.number from app.tickets p where p.id = t.problem_id)) end,
    'tickets', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'ref', 'T-' || x.number, 'subject', x.subject) order by x.created_at desc)
                         from (select * from app.tickets y
                               where y.product = p_product and y.type <> 'problem' and y.status not in ('resolved', 'closed') and y.deleted_at is null
                                 and (v_sandbox or not y.is_sample) and app.queue_ok(y.queue_key) and app.visible(y.owner_id, y.visibility)
                               order by y.created_at desc limit 50) x), '[]'::jsonb),
    'usage', jsonb_build_object(
      'previews', (select count(*) from app.ai_calls c join app.help_test_questions q on q.id = c.subject_id
                   where c.feature = 'help_answer_preview' and q.product = p_product and c.at > now() - interval '30 days' and c.state in ('ok', 'retried_ok')),
      'used', (select count(*) from app.ai_outputs o join app.help_test_questions q on q.id = o.subject_id
               where o.feature = 'help_answer_preview' and q.product = p_product and o.created_at > now() - interval '30 days' and o.state = 'used'),
      'calls', (select count(*) from app.ai_calls c where c.provider = 'anthropic' and c.at > now() - interval '30 days'),
      'failed', (select count(*) from app.ai_calls c where c.provider = 'anthropic' and c.at > now() - interval '30 days' and c.state not in ('ok', 'retried_ok'))),
    -- the published titles an answer may name as its source
    'titles', coalesce((select jsonb_agg(distinct a.title) from app.help_articles a
                        where a.product = p_product and a.status = 'published' and (v_sandbox or not a.is_sample)), '[]'::jsonb),
    'ai_enabled', app.support_ai_on(p_product),
    'can_ask', app.can('tickets', 'ai'));
end $fn$;

-- ===========================================================================
-- 6. status: components, incidents with updates, resolve and notify
-- ===========================================================================
create table app.status_components (
  id         uuid primary key default gen_random_uuid(),
  product    text not null references app.products (key) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 2 and 80),
  ord        int not null default 0,
  state      text not null default 'operational' check (state in ('operational', 'degraded', 'partial_outage', 'maintenance')),
  created_by uuid references app.admins (id) on delete set null,
  updated_by uuid references app.admins (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index status_components_name on app.status_components (product, lower(name));

create table app.status_incidents (
  id                uuid primary key default gen_random_uuid(),
  product           text not null references app.products (key) on delete cascade,
  title             text not null check (char_length(btrim(title)) between 3 and 200),
  body              text check (body is null or char_length(body) <= 4000),
  state             text not null default 'investigating' check (state in ('investigating', 'identified', 'monitoring', 'resolved')),
  problem_ticket_id uuid references app.tickets (id) on delete set null,
  started_at        timestamptz not null default now(),
  resolved_at       timestamptz,
  notified          int,
  created_by        uuid references app.admins (id) on delete set null,
  updated_at        timestamptz not null default now(),
  check ((state = 'resolved') = (resolved_at is not null))
);
create index status_incidents_product on app.status_incidents (product, state, started_at desc);

create table app.status_incident_components (
  incident_id  uuid not null references app.status_incidents (id) on delete cascade,
  component_id uuid not null references app.status_components (id) on delete cascade,
  primary key (incident_id, component_id)
);

create table app.status_incident_updates (
  id          uuid primary key default gen_random_uuid(),
  incident_id uuid not null references app.status_incidents (id) on delete cascade,
  state       text not null check (state in ('investigating', 'identified', 'monitoring', 'resolved')),
  body        text not null check (char_length(btrim(body)) between 1 and 4000),
  created_by  uuid references app.admins (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index status_incident_updates_incident on app.status_incident_updates (incident_id, created_at);

-- an update is a record of what was said: nobody may change its content; it goes only with its incident
create function app.status_update_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    if new.incident_id is distinct from old.incident_id or new.state is distinct from old.state or new.body is distinct from old.body
       or new.created_at is distinct from old.created_at then
      raise exception 'a status update is append-only' using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if exists (select 1 from app.status_incidents i where i.id = old.incident_id) then
    raise exception 'a status update is append-only' using errcode = 'check_violation';
  end if;
  return old;
end $fn$;
create trigger status_incident_updates_fixed before update or delete on app.status_incident_updates
  for each row execute function app.status_update_fixed();

alter table app.status_components enable row level security;
alter table app.status_incidents enable row level security;
alter table app.status_incident_components enable row level security;
alter table app.status_incident_updates enable row level security;
revoke all on app.status_components, app.status_incidents, app.status_incident_components, app.status_incident_updates from public, anon, authenticated;

-- what the product's public site shows of the notice tied to a problem: null (no notice), or {state, error} with state
-- shown | not_delivered (an open notice: delivered or only saved in Sentral) or removed | removal_not_delivered (after the
-- incident was resolved: the clearing push delivered, or not yet). A later delivered push replaces the site's banner.
create function app.status_incident_notice(p_product text, p_problem uuid, p_resolved_at timestamptz) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare n app.status_notices; c app.status_notices;
begin
  if p_problem is null then return null; end if;
  select * into n from app.status_notices x where x.product = p_product and x.problem_ticket_id = p_problem and x.cleared_at is null and x.text is not null
  order by x.set_at desc limit 1;
  if found then
    return jsonb_build_object('state', case when n.pushed_at is not null then 'shown' else 'not_delivered' end, 'error', n.push_error);
  end if;
  if p_resolved_at is null then return null; end if;
  select * into n from app.status_notices x where x.product = p_product and x.problem_ticket_id = p_problem and x.text is not null and x.cleared_at >= p_resolved_at
  order by x.cleared_at desc limit 1;
  if not found then return null; end if;
  if exists (select 1 from app.status_notices y where y.product = p_product and y.set_at >= n.cleared_at and y.pushed_at is not null) then
    return jsonb_build_object('state', 'removed', 'error', null);
  end if;
  -- the row that replaced it (written in the same transaction as the clearing)
  select * into c from app.status_notices y where y.product = p_product and y.set_at >= n.cleared_at order by y.set_at limit 1;
  return jsonb_build_object('state', 'removal_not_delivered', 'error', c.push_error);
end $fn$;

create function public.status_get(p_product text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'see'); v_sandbox boolean := coalesce((select a.sandbox from app.admins a where a.id = v_me), false);
begin
  perform app.support_product(p_product);
  return jsonb_build_object(
    'can_edit', app.can('tickets', 'edit_others'),
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'state', c.state, 'updated_at', c.updated_at) order by c.ord, c.name)
                            from app.status_components c where c.product = p_product), '[]'::jsonb),
    'incidents', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'title', i.title, 'body', i.body, 'state', i.state, 'started_at', i.started_at, 'resolved_at', i.resolved_at,
        'notified', i.notified,
        'problem', (select jsonb_build_object('id', p.id, 'ref', 'T-' || p.number, 'resolved', p.problem_status = 'resolved') from app.tickets p where p.id = i.problem_ticket_id),
        'linked', (select count(*) from app.tickets x where x.problem_id = i.problem_ticket_id and x.deleted_at is null and (v_sandbox or not x.is_sample)),
        'customers', (select count(distinct x.organization_id) from app.tickets x where x.problem_id = i.problem_ticket_id and x.deleted_at is null and (v_sandbox or not x.is_sample)),
        -- the notice tied to this incident's problem, as the product's site really has it: «shown» only once Orgpuls took it
        -- (pushed_at), «removed» only once a later push replaced it; otherwise saved in Sentral and not delivered (push_error)
        'notice', app.status_incident_notice(p_product, i.problem_ticket_id, i.resolved_at),
        -- the resolution replies that really went out by email
        'emailed', case when i.resolved_at is not null then (select count(*) from app.ticket_messages m join app.tickets x on x.id = m.ticket_id
                        where x.problem_id = i.problem_ticket_id and m.kind = 'reply' and m.created_at = i.resolved_at and m.delivery_status in ('sent', 'delivered')) end,
        'components', coalesce((select jsonb_agg(ic.component_id) from app.status_incident_components ic where ic.incident_id = i.id), '[]'::jsonb),
        'updates', coalesce((select jsonb_agg(jsonb_build_object('state', u.state, 'body', u.body, 'at', u.created_at,
                                                                 'by', (select coalesce(a.name, a.email) from app.admins a where a.id = u.created_by)) order by u.created_at desc)
                             from app.status_incident_updates u where u.incident_id = i.id), '[]'::jsonb))
        order by i.state = 'resolved', i.started_at desc)
      from (select * from app.status_incidents x where x.product = p_product and (x.state <> 'resolved' or x.resolved_at > now() - interval '30 days')
            order by x.state = 'resolved', x.started_at desc limit 10) i), '[]'::jsonb),
    'problems', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'ref', 'T-' || p.number, 'subject', p.subject) order by p.number desc)
                          from app.tickets p where p.type = 'problem' and p.deleted_at is null and p.problem_status <> 'resolved'
                            and (p.product = p_product or p.product is null) and app.support_ticket_ok(p)), '[]'::jsonb),
    'changelog', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title', n.title, 'published_at', n.published_at) order by n.published_at desc)
                           from (select * from app.release_notes r where r.product = p_product and r.state = 'published' order by r.published_at desc limit 12) n), '[]'::jsonb));
end $fn$;

create function public.status_component_save(p_id uuid, p_product text, p_name text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others'); v_id uuid;
begin
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if p_id is null then
    perform app.support_product(p_product);
    if exists (select 1 from app.status_components c where c.product = p_product and lower(c.name) = lower(btrim(p_name))) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
    end if;
    insert into app.status_components (product, name, ord, created_by, updated_by)
    values (p_product, btrim(p_name), coalesce((select max(c.ord) + 10 from app.status_components c where c.product = p_product), 10), v_me, v_me)
    returning id into v_id;
    perform app.log('status_component.added', 'status_component', v_id::text, jsonb_build_object('product', p_product));
  else
    update app.status_components c set name = btrim(p_name), updated_by = v_me, updated_at = now() where c.id = p_id returning c.id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    perform app.log('status_component.renamed', 'status_component', v_id::text);
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create function public.status_component_set(p_id uuid, p_state text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others');
begin
  if p_state is null or p_state not in ('operational', 'degraded', 'partial_outage', 'maintenance') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state';
  end if;
  update app.status_components c set state = p_state, updated_by = v_me, updated_at = now() where c.id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('status_component.changed', 'status_component', p_id::text, jsonb_build_object('state', p_state));
  return jsonb_build_object('ok', true);
end $fn$;

create function public.status_component_remove(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others');
begin
  delete from app.status_components c where c.id = p_id;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.log('status_component.removed', 'status_component', p_id::text);
  return jsonb_build_object('ok', true);
end $fn$;

-- open an incident: a public title and text, the problem behind it, the components it touches; the opening is its
-- first update
create function public.status_incident_open(p_product text, p_title text, p_body text, p_problem uuid, p_components uuid[]) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others'); v_id uuid;
begin
  perform app.support_product(p_product);
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'title'; end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 1 and 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  if p_problem is not null and not exists (select 1 from app.tickets t where t.id = p_problem and t.type = 'problem' and t.deleted_at is null and app.support_ticket_ok(t)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'problem';
  end if;
  if exists (select 1 from unnest(coalesce(p_components, '{}')) c where not exists (select 1 from app.status_components x where x.id = c and x.product = p_product)) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'components';
  end if;
  insert into app.status_incidents (product, title, body, problem_ticket_id, created_by)
  values (p_product, btrim(p_title), btrim(p_body), p_problem, v_me) returning id into v_id;
  insert into app.status_incident_components (incident_id, component_id) select v_id, c from unnest(coalesce(p_components, '{}')) c on conflict do nothing;
  insert into app.status_incident_updates (incident_id, state, body, created_by) values (v_id, 'investigating', btrim(p_body), v_me);
  perform app.log('status_incident.opened', 'status_incident', v_id::text, jsonb_build_object('product', p_product, 'problem', p_problem));
  return jsonb_build_object('id', v_id);
end $fn$;

-- a new update on an open incident (investigating, identified, monitoring)
create function public.status_incident_update(p_id uuid, p_state text, p_body text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others');
begin
  if p_state is null or p_state not in ('investigating', 'identified', 'monitoring') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 1 and 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'body'; end if;
  update app.status_incidents i set state = p_state, updated_at = now() where i.id = p_id and i.state <> 'resolved';
  if not found then
    if exists (select 1 from app.status_incidents i where i.id = p_id) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  insert into app.status_incident_updates (incident_id, state, body, created_by) values (p_id, p_state, btrim(p_body), v_me);
  perform app.log('status_incident.updated', 'status_incident', p_id::text, jsonb_build_object('state', p_state));
  return jsonb_build_object('ok', true);
end $fn$;

-- «Resolve and notify affected customers»: the problem is resolved with this message (problem_resolve replies to every
-- open incident ticket and resolves it, emailed where mail is ready), the incident and its components return to normal,
-- and a notice tied to the problem is cleared on the product's site (status_notices_due)
create function public.status_incident_resolve(p_id uuid, p_message text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('tickets', 'edit_others'); i app.status_incidents; v_notified int := 0; v_cleared int := 0;
begin
  select * into i from app.status_incidents x where x.id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if i.state = 'resolved' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state'; end if;
  if char_length(btrim(coalesce(p_message, ''))) not between 1 and 4000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'message'; end if;
  if i.problem_ticket_id is not null and exists (select 1 from app.tickets t where t.id = i.problem_ticket_id and t.problem_status <> 'resolved' and t.deleted_at is null) then
    v_notified := coalesce((public.problem_resolve(i.problem_ticket_id, btrim(p_message)) ->> 'notified')::int, 0);
  end if;
  update app.status_incidents x set state = 'resolved', resolved_at = now(), notified = v_notified, updated_at = now() where x.id = p_id;
  insert into app.status_incident_updates (incident_id, state, body, created_by) values (p_id, 'resolved', btrim(p_message), v_me);
  update app.status_components c set state = 'operational', updated_by = v_me, updated_at = now()
  where c.id in (select ic.component_id from app.status_incident_components ic where ic.incident_id = p_id) and c.state <> 'operational';
  if i.problem_ticket_id is not null then v_cleared := app.status_notices_due(); end if;
  perform app.log('status_incident.resolved', 'status_incident', p_id::text, jsonb_build_object('notified', v_notified, 'notices_cleared', v_cleared));
  -- «notified» is the number of tickets resolved with the reply; whether a reply can be emailed at all is said beside it
  return jsonb_build_object('notified', v_notified, 'notices_cleared', v_cleared, 'mail_ready', app.mail_ready_for(i.product));
end $fn$;

-- ===========================================================================
-- 7. CSAT: the resolving reply asks, once; a single-use token answers with a score and nothing else
-- ===========================================================================
alter table app.ticket_messages add column csat_request boolean not null default false;
create index tickets_csat_token on app.tickets (csat_token_hash) where csat_token_hash is not null;

-- 0061's claim, plus the CSAT token on the reply that resolves the ticket. The token's plaintext exists only in this
-- answer and in the email; the ticket keeps its hash. A retried send gets a fresh token (the unsent one is void). The five
-- links open the public page /u/csat/<token> on the ticket's application's link address (0063), else on Sentral's public
-- address: without either there is no page to answer on, so nothing is asked.
create or replace function public.worker_ticket_mail_claim(p_limit integer default 20) returns jsonb
  language plpgsql security definer set search_path = ''
as $fn$
declare m record; t app.tickets; d app.sender_domains; out jsonb := '[]'::jsonb; v_to text; v_csat text; v_base text;
        v_inbound text := (select s.inbound_domain from app.mail_settings s where s.inbound_ok and s.inbound_domain is not null);
begin
  if not app.connected('email') then return out; end if;
  for m in select x.* from app.ticket_messages x where x.delivery_status = 'queued' and x.kind = 'reply'
             and (x.mail_claimed_at is null or x.mail_claimed_at < now() - interval '10 minutes')
           order by x.created_at limit least(greatest(coalesce(p_limit, 20), 1), 100) for update skip locked loop
    select * into t from app.tickets where id = m.ticket_id;
    v_to := app.ticket_recipient(t);
    d := app.mail_sender_for(t.product);
    if v_to is null or t.deleted_at is not null or d.id is null then
      update app.ticket_messages set delivery_status = 'failed', mail_error = case when d.id is null then 'no_sender' else 'no_recipient' end, mail_claimed_at = null
      where id = m.id;
      continue;
    end if;
    update app.ticket_messages set mail_claimed_at = now(), mail_attempts = mail_attempts + 1 where id = m.id;
    v_csat := null;
    v_base := (select coalesce(s.app_bases ->> t.product, s.public_base) from app.mail_settings s);
    if v_base is not null and t.status = 'resolved' and t.csat_at is null and (t.csat_requested_at is null or m.csat_request)
       and not exists (select 1 from app.ticket_messages y where y.ticket_id = t.id and y.kind = 'reply' and y.created_at > m.created_at) then
      v_csat := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/=', '-_');
      update app.tickets set csat_token_hash = extensions.digest(v_csat, 'sha256'), csat_requested_at = now() where id = t.id;
      update app.ticket_messages set csat_request = true where id = m.id;
    end if;
    out := out || jsonb_build_array(jsonb_build_object(
      'id', m.id, 'ref', 'T-' || t.number, 'subject', t.subject, 'body', m.body,
      'to', v_to, 'to_name', (select p.name from app.people p where p.id = t.person_id),
      'agent', (select coalesce(a.name, a.email) from app.admins a where a.id = m.author_staff_id),
      'from', d.from_local || '@' || d.domain, 'from_name', d.from_name,
      'reply_to', coalesce(case when v_inbound is not null then 'support@' || v_inbound end, d.reply_to, d.from_local || '@' || d.domain),
      'locale', 'no', 'csat_token', v_csat, 'csat_base', case when v_csat is not null then v_base end));
  end loop;
  return out;
end $fn$;

-- 0060's outcome, plus: a reply that finally fails takes its CSAT request back (nobody was asked)
create or replace function public.worker_ticket_mail_done(p_message uuid, p_provider_message_id text, p_code text default null, p_retry boolean default false)
  returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare m app.ticket_messages;
begin
  if p_code is not null and p_code !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  select * into m from app.ticket_messages where id = p_message for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_code is null then
    update app.ticket_messages set delivery_status = 'sent', mail_sent_at = now(), mail_claimed_at = null, mail_error = null,
      provider_message_id = left(nullif(btrim(p_provider_message_id), ''), 200), email_message_id = left(nullif(btrim(p_provider_message_id), ''), 200)
    where id = p_message;
  elsif p_retry and m.mail_attempts < 20 then
    update app.ticket_messages set mail_claimed_at = now() - interval '9 minutes' + least(m.mail_attempts, 10) * interval '1 minute', mail_error = p_code where id = p_message;
  else
    update app.ticket_messages set delivery_status = 'failed', mail_claimed_at = null, mail_error = p_code, csat_request = false where id = p_message;
    if m.csat_request then
      update app.tickets set csat_token_hash = null, csat_requested_at = null where id = m.ticket_id and csat_at is null;
    end if;
    perform app.notify(m.author_staff_id, 'system', 'tickets.mail_failed', jsonb_build_object('code', p_code),
                       '/tickets?ticket=' || m.ticket_id, 'ticket', m.ticket_id)
    where m.author_staff_id is not null;
  end if;
  return jsonb_build_object('ok', true);
end $fn$;

-- the csat edge function's question for the public page: may this token still answer? It changes nothing (mail scanners
-- open links), and it says no more than that and the application's sender name the email already carried.
create function public.worker_csat_peek(p_token text) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare t app.tickets;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{32}$' then return jsonb_build_object('open', false); end if;
  select x.* into t from app.tickets x
  where x.csat_token_hash = extensions.digest(p_token, 'sha256') and x.csat_at is null and x.deleted_at is null
    and x.csat_requested_at > now() - interval '30 days';
  if not found then return jsonb_build_object('open', false); end if;
  return jsonb_build_object('open', true, 'from_name', (app.mail_sender_for(t.product)).from_name);
end $fn$;

-- the csat edge function's one door: a token from the email and a score 1–5; the token works once, for 30 days
create function public.worker_csat_submit(p_token text, p_score int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_id uuid; v_sample boolean;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{32}$' then return jsonb_build_object('ok', false, 'code', 'unknown'); end if;
  if p_score is null or p_score not between 1 and 5 then return jsonb_build_object('ok', false, 'code', 'invalid'); end if;
  update app.tickets t set csat_score = p_score, csat_at = now(), csat_token_hash = null
  where t.csat_token_hash = extensions.digest(p_token, 'sha256') and t.csat_at is null and t.deleted_at is null
    and t.csat_requested_at > now() - interval '30 days'
  returning t.id, t.is_sample into v_id, v_sample;
  if v_id is null then return jsonb_build_object('ok', false, 'code', 'used_or_unknown'); end if;
  insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'ticket.csat_answered', 'ticket', v_id::text, true, null);
  perform app.emit('ticket.csat_answered', 'ticket', v_id, jsonb_build_object('score', p_score), v_sample);
  return jsonb_build_object('ok', true, 'score', p_score);
end $fn$;

-- ===========================================================================
-- 8. rights on the functions
-- ===========================================================================
revoke all on function app.support_product(text) from public, anon, authenticated;
revoke all on function app.support_ticket_ok(app.tickets) from public, anon, authenticated;
revoke all on function app.mail_auto_reply(jsonb, text) from public, anon, authenticated;
revoke all on function app.help_path_ok(text) from public, anon, authenticated;
revoke all on function app.help_pages_ok(text[]) from public, anon, authenticated;
revoke all on function app.help_slug(text, text, text, uuid) from public, anon, authenticated;
revoke all on function app.help_article_json(uuid) from public, anon, authenticated;
revoke all on function app.support_ai_on(text) from public, anon, authenticated;
revoke all on function app.help_questions_prune() from public, anon, authenticated;
revoke all on function app.ai_ctx_help_answer_preview(uuid) from public, anon, authenticated;
revoke all on function app.status_update_fixed() from public, anon, authenticated;
revoke all on function app.status_incident_notice(text, uuid, timestamptz) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.help_centre_get(text)', 'public.help_article_get(uuid)', 'public.help_article_write(uuid, jsonb, int)',
                           'public.help_article_publish(uuid, boolean)', 'public.help_article_review(uuid)', 'public.help_search(text, text, text)',
                           'public.support_settings_save(text, boolean)', 'public.help_question_ask(text, text, text)',
                           'public.support_results(text, int)', 'public.support_widget_get(text)', 'public.support_channels(text, int)',
                           'public.portal_preview(text, uuid)', 'public.support_assist_get(text, uuid)', 'public.status_get(text)',
                           'public.status_component_save(uuid, text, text)', 'public.status_component_set(uuid, text)', 'public.status_component_remove(uuid)',
                           'public.status_incident_open(text, text, text, uuid, uuid[])', 'public.status_incident_update(uuid, text, text)',
                           'public.status_incident_resolve(uuid, text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_ticket_inbound(text, text, text, text, jsonb)', 'public.worker_ticket_inbound(text, text, text, text)',
                           'public.worker_ticket_mail_claim(integer)', 'public.worker_ticket_mail_done(uuid, text, text, boolean)',
                           'public.worker_csat_submit(text, int)', 'public.worker_csat_peek(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
