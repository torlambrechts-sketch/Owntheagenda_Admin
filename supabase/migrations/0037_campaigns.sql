-- 0037_campaigns.sql — email campaigns (Phase 6): the Campaigns, Email builder, Audience and consent and Deliverability
-- tabs (CMP-01..09, UF-17, SF-19, SF-39). Spec: docs/crm-enrichment/specs/marketing-documents.md §1, §3, §4 «NEW:
-- campaigns», §5–§11. Consent wording, suppressions, double opt-in, the consent log and the status summary are
-- 0031's and are reused; mail tracking conventions (tokens, client classes) are 0020's; the engine is 0021's. The
-- departures are logged in docs/crm-enrichment/deviations/campaigns-schema.md (V-P6C-*).
--
-- A campaign is an owned record in the campaigns scope behind the campaigns module. It is edited as a draft: a
-- design (rows of blocks, the footer fixed as the last row) or hand-written HTML, subjects A and B, a segment, a
-- sender domain, UTM. One TypeScript renderer turns the design into email HTML; scheduling receives that HTML,
-- checks it (no script, the unsubscribe token and the sender's postal address present, every merge field known)
-- and freezes it with the links it contains. From then on the content cannot change (app.campaign_guard): the
-- report shows what was sent. Status moves only along draft → scheduled → sending → sent (or scheduled → canceled),
-- and for automated campaigns draft → active ⇄ paused.
--
-- Fixed rules (D-27, campaign_rules): the footer with the unsubscribe link and sender identity is in every
-- campaign; nobody who is not subscribed, or whose address is suppressed, is ever mailed; nothing leaves from an
-- unauthenticated domain. They are enforced where a campaign is scheduled, where its audience is resolved, and
-- again for each recipient at the moment the send worker claims it. Double opt-in pending is not subscribed.
--
-- Providers. Building, scheduling and counting work without the email provider. Scheduling needs a sender domain
-- whose SPF, DKIM and DMARC records the DNS check found (no key needed); sending needs the provider and its domain
-- verification. A due campaign without them stays scheduled with a hold reason the screen shows, and its owner is
-- told once. Test sends and the send worker answer not_connected (email).
--
-- Respondents are never recipients (D-34): an audience is a segment of app.people, which holds no respondent by
-- construction; per-recipient events of Orgpuls's survey-invitation stream match no recipient and are dropped.
--
-- Privacy (§10). No IP: geo is the provider's city and country of a human open. The unsubscribe token is returned
-- once to the send worker and stored as SHA-256. Erasing a person blanks their recipient rows' address and place;
-- the suppression hash stays. Events and the audit carry ids, kinds and counts, never a recipient's words.

-- ---------------------------------------------------------------------------
-- segments: saved views of people with kind «segment», shared by sales and marketing
alter table app.saved_views
  add column kind        text not null default 'view' check (kind in ('view', 'segment')),
  add column description text check (description is null or char_length(description) <= 300),
  add column updated_at  timestamptz not null default now(),
  add constraint saved_views_segment_people check (kind = 'view' or screen = 'people');
create index saved_views_segments on app.saved_views (owner_id) where kind = 'segment';

-- marketing templates live in the one template store (Q4); the Inbox keeps seeing kind «sales» only
alter table app.email_templates
  add column kind            text not null default 'sales' check (kind in ('sales', 'marketing')),
  add column layout          boolean not null default false,
  add column design          jsonb check (design is null or jsonb_typeof(design) = 'object'),
  add column html            text check (html is null or char_length(html) <= 500000),
  add column category        text check (category is null or char_length(btrim(category)) between 1 and 40),
  add column current_version int not null default 1 check (current_version >= 1),
  add column version         int not null default 1,
  add constraint email_templates_layout_marketing check (not layout or kind = 'marketing'),
  add constraint email_templates_sales_plain check (kind = 'marketing' or (design is null and html is null));

create table app.email_template_versions (
  template_id uuid not null references app.email_templates (id) on delete cascade,
  version     int not null check (version >= 1),
  subject     text not null default '' check (char_length(subject) <= 500),
  body        text not null default '' check (char_length(body) <= 50000),
  design      jsonb check (design is null or jsonb_typeof(design) = 'object'),
  html        text check (html is null or char_length(html) <= 500000),
  created_by  uuid,
  created_at  timestamptz not null default now(),
  primary key (template_id, version)
);

-- ---------------------------------------------------------------------------
-- sender domains (CMP-08): the identity a campaign is sent under and the checks that authenticate it
create table app.sender_domains (
  id                 uuid primary key default gen_random_uuid(),
  domain             text not null check (domain = lower(domain) and char_length(domain) <= 253 and domain ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$'),
  stream             text not null check (stream in ('marketing', 'transactional')),
  sends_here         boolean not null default true,              -- false: another system sends (Orgpuls's invitations, Q6)
  product            text references app.products (key),
  from_name          text not null check (char_length(btrim(from_name)) between 1 and 120),
  from_local         text not null default 'news' check (from_local ~ '^[a-z0-9._-]{1,40}$'),
  reply_to           text check (reply_to is null or (char_length(reply_to) <= 254 and reply_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  postal_address     text check (postal_address is null or char_length(btrim(postal_address)) between 1 and 300),
  provider_domain_id text check (provider_domain_id is null or char_length(provider_domain_id) <= 200),
  spf_ok             boolean,
  dkim_ok            boolean,
  dmarc_policy       text check (dmarc_policy is null or dmarc_policy in ('none', 'quarantine', 'reject')),
  verified_at        timestamptz,                                -- the provider's domain verification; never without it
  check_detail       jsonb not null default '{}'::jsonb check (jsonb_typeof(check_detail) = 'object'),
  last_checked_at    timestamptz,
  warmup_started_at  date,
  warmup_days        int not null default 30 check (warmup_days between 0 and 120),
  version            int not null default 1,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create unique index sender_domains_domain on app.sender_domains (domain) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- campaigns (CMP-01..09)
create table app.campaigns (
  id               uuid primary key default gen_random_uuid(),
  seq              bigint generated always as identity unique,
  name             text not null check (char_length(btrim(name)) between 1 and 120),
  type             text not null check (type in ('newsletter', 'one_off', 'promotion', 'product_announcement', 'automated')),
  status           text not null default 'draft' check (status in ('draft', 'scheduled', 'sending', 'sent', 'active', 'paused', 'canceled')),
  segment_id       uuid references app.saved_views (id) on delete set null,
  audience_name    text check (audience_name is null or char_length(audience_name) <= 80),   -- the segment's name when scheduled
  template_id      uuid references app.email_templates (id) on delete set null,
  design           jsonb not null default '{"rows":[]}'::jsonb check (jsonb_typeof(design) = 'object'),
  html             text check (html is null or char_length(html) <= 500000),                  -- «Code your own HTML»
  rendered_html    text check (rendered_html is null or char_length(rendered_html) <= 500000), -- frozen when scheduled
  subject_a        text not null default '' check (char_length(subject_a) <= 200),
  subject_b        text check (subject_b is null or char_length(btrim(subject_b)) between 1 and 200),
  preheader        text check (preheader is null or char_length(preheader) <= 200),
  ab_percent       smallint check (ab_percent is null or ab_percent between 2 and 50),
  ab_metric        text check (ab_metric is null or ab_metric in ('opens', 'clicks')),
  ab_wait          interval check (ab_wait is null or ab_wait between interval '1 hour' and interval '72 hours'),
  ab_winner        text check (ab_winner is null or ab_winner in ('a', 'b')),
  ab_decided_at    timestamptz,
  sender_domain_id uuid references app.sender_domains (id),
  product          text references app.products (key),
  coupon_code      text references app.coupons (code),
  utm_source       text not null default 'newsletter' check (utm_source ~ '^[a-z0-9_-]{1,60}$'),
  utm_medium       text not null default 'email' check (utm_medium ~ '^[a-z0-9_-]{1,60}$'),
  utm_campaign     text not null check (utm_campaign ~ '^[a-z0-9_-]{1,60}$'),
  tracking         boolean not null default true,
  notify_owners    boolean not null default false,
  hold_reason      text check (hold_reason is null or hold_reason in ('not_connected:email', 'sender_domain', 'audience')),
  scheduled_at     timestamptz,
  started_at       timestamptz,
  sent_at          timestamptz,
  canceled_at      timestamptz,
  audience_count   int check (audience_count is null or audience_count >= 0),
  owner_id         uuid references app.admins (id) on delete set null,
  visibility       text not null default 'all' check (visibility in ('owner', 'group', 'group_sub', 'all')),
  labels           uuid[] not null default '{}',
  custom           jsonb not null default '{}'::jsonb check (jsonb_typeof(custom) = 'object'),
  is_sample        boolean not null default false,
  version          int not null default 1,
  created_at       timestamptz not null default now(),
  created_by       uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid,
  deleted_at       timestamptz,
  check (subject_b is null or (ab_percent is not null and ab_metric is not null and ab_wait is not null)),
  check (subject_b is null or type <> 'automated'),
  check (coupon_code is null or type = 'promotion'),
  check (status = 'draft' or rendered_html is not null),
  check (type = 'automated' or status not in ('active', 'paused')),
  check (type <> 'automated' or status not in ('scheduled', 'sending', 'sent', 'canceled'))
);
create unique index campaigns_utm on app.campaigns (utm_campaign) where deleted_at is null and not is_sample;
create index campaigns_due on app.campaigns (scheduled_at) where status = 'scheduled';
create index campaigns_list on app.campaigns (created_at desc) where deleted_at is null;

-- the links of the frozen HTML: a click names the link it came through
create table app.campaign_links (
  id          uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references app.campaigns (id) on delete cascade,
  url         text not null check (char_length(url) <= 2000 and url ~ '^https?://'),
  label       text check (label is null or char_length(label) <= 200),
  token       text not null unique check (token ~ '^[A-Za-z0-9_-]{22,64}$'),   -- the same in every recipient's copy; names a link, not a person
  unique (campaign_id, url)
);

-- one row per person a campaign was resolved for (skipped ones too, so the report shows who was left out and why)
create table app.campaign_recipients (
  id                 uuid primary key default gen_random_uuid(),
  campaign_id        uuid not null references app.campaigns (id) on delete cascade,
  person_id          uuid references app.people (id) on delete set null,
  email              text check (email is null or (email = lower(email) and char_length(email) <= 254)),   -- blanked on erasure
  send_key           text not null default 'once' check (send_key ~ '^[a-z0-9-]{1,64}$'),                 -- automated: the run step
  variant            text check (variant is null or variant in ('a', 'b', 'w')),
  state              text not null default 'queued' check (state in ('queued', 'sent', 'delivered', 'soft_bounced', 'bounced', 'complained', 'failed', 'skipped')),
  skip_reason        text check (skip_reason is null or skip_reason in ('not_subscribed', 'suppressed', 'no_email', 'duplicate', 'over_allowance')),
  claimed_at         timestamptz,
  provider_message_id text unique check (provider_message_id is null or char_length(provider_message_id) <= 200),
  unsub_token_sha256 bytea unique check (unsub_token_sha256 is null or length(unsub_token_sha256) = 32),
  failure_code       text check (failure_code is null or failure_code ~ '^[a-z0-9_.:-]{1,60}$'),
  sent_at            timestamptz,
  delivered_at       timestamptz,
  first_open_at      timestamptz,
  last_open_at       timestamptz,
  opens              int not null default 0 check (opens >= 0),
  first_click_at     timestamptz,
  last_click_at      timestamptz,
  clicks             int not null default 0 check (clicks >= 0),
  unsubscribed_at    timestamptz,
  complained_at      timestamptz,
  bounced_at         timestamptz,
  bounce_kind        text check (bounce_kind is null or bounce_kind in ('hard', 'soft')),
  city               text check (city is null or char_length(city) <= 80),        -- the provider's geo of a human open; never an IP
  country            char(2) check (country is null or country ~ '^[A-Z]{2}$'),
  is_sample          boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (campaign_id, person_id, send_key),
  check ((state = 'skipped') = (skip_reason is not null))
);
create index campaign_recipients_state on app.campaign_recipients (campaign_id, state);
create index campaign_recipients_person on app.campaign_recipients (person_id) where person_id is not null;

-- what the provider (or the public host) reported, idempotent on the provider's event id; pruned after 13 months
create table app.campaign_events (
  id                bigint generated always as identity primary key,
  recipient_id      uuid not null references app.campaign_recipients (id) on delete cascade,
  campaign_id       uuid not null,
  kind              text not null check (kind in ('sent', 'delivered', 'bounced', 'opened', 'clicked', 'unsubscribed', 'complained')),
  bounce_kind       text check (bounce_kind is null or bounce_kind in ('hard', 'soft')),
  smtp_code         text check (smtp_code is null or smtp_code ~ '^[245]\d\d$'),
  link_id           uuid references app.campaign_links (id) on delete set null,
  client_class      text not null default 'unknown' check (client_class in ('human', 'prefetch', 'unknown')),
  provider_event_id text unique check (provider_event_id is null or char_length(provider_event_id) <= 200),
  at                timestamptz not null
);
create index campaign_events_campaign on app.campaign_events (campaign_id, kind, at);
create index campaign_events_recipient on app.campaign_events (recipient_id, kind);
create index campaign_events_at on app.campaign_events (at);

-- suppressions name the campaign an unsubscribe or complaint came from (0031 left a plain uuid, V-P5-10)
update app.suppressions set campaign_id = null where campaign_id is not null and not exists (select 1 from app.campaigns c where c.id = campaign_id);
alter table app.suppressions add constraint suppressions_campaign_fk foreign key (campaign_id) references app.campaigns (id) on delete set null;

-- the coupon a promotion carries, as a merge token in campaigns only
insert into app.merge_fields (token, source_path, format, ord, contexts) values
  ('Kampanje.kode', 'campaign.coupon_code', 'text', 400, array['campaign']),
  ('campaign.code', 'campaign.coupon_code', 'text', 410, array['campaign']);

-- open and click figures follow the tracking rule here too (COM-06, CMP-06)
update app.settings_registry set applies_to = 'COM-06, CMP-06' where key = 'tracking';

-- ---------------------------------------------------------------------------
-- the record type «campaign» (written through campaign_*; the generic path may list, read and search them)
insert into app.entities (key, tbl, scope, module, owned, title_col, sub_cols, search, ord) values
  ('campaign', 'campaigns', 'campaigns', 'campaigns', true, 'name', array['type', 'status'], array['name', 'utm_campaign'], 85);
insert into app.entity_columns (entity, col, kind, writable, required, ref, ord) values
  ('campaign', 'name', 'text', false, false, null, 1),
  ('campaign', 'type', 'text', false, false, null, 2),
  ('campaign', 'status', 'text', false, false, null, 3),
  ('campaign', 'utm_campaign', 'text', false, false, null, 4),
  ('campaign', 'scheduled_at', 'timestamptz', false, false, null, 5),
  ('campaign', 'sent_at', 'timestamptz', false, false, null, 6),
  ('campaign', 'audience_count', 'int', false, false, null, 7);

-- the starting layouts (CMP-02): structure only, no product claims (Q18); Tor writes the words
insert into app.email_templates (name, scope, is_starter, kind, layout, category, design) values
  ('Newsletter', 'shared', true, 'marketing', true, 'newsletter',
   '{"rows":[{"kind":"header","bg":"card"},{"kind":"title","text":"","fs":26},{"kind":"paragraph","text":""},{"kind":"image"},{"kind":"list","text":""},{"kind":"button","text":""},{"kind":"divider"},{"kind":"social"},{"kind":"footer","bg":"cream"}]}'),
  ('Product announcement', 'shared', true, 'marketing', true, 'product_announcement',
   '{"rows":[{"kind":"header","bg":"card"},{"kind":"image"},{"kind":"title","text":"","fs":26},{"kind":"paragraph","text":""},{"kind":"button","text":""},{"kind":"footer","bg":"cream"}]}');
insert into app.email_template_versions (template_id, version, subject, design)
select id, 1, subject, design from app.email_templates where kind = 'marketing' and layout;

-- ---------------------------------------------------------------------------
-- append-only content and the campaign's state machine. Each rule is «nobody may change this content»; a delete is
-- allowed when the parent is already gone, and the database's own referential maintenance (set null) passes.
create function app.email_template_version_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.email_templates where id = old.template_id) then return old; end if;
  if tg_op = 'UPDATE' and (new.template_id, new.version, new.subject, new.body, new.design, new.html, new.created_at)
                          is not distinct from (old.template_id, old.version, old.subject, old.body, old.design, old.html, old.created_at) then return new; end if;
  raise exception 'a template version is fixed' using errcode = 'insufficient_privilege';
end $fn$;
create trigger email_template_version_fixed before update or delete on app.email_template_versions for each row execute function app.email_template_version_fixed();

create function app.campaign_link_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and not exists (select 1 from app.campaigns where id = old.campaign_id) then return old; end if;
  if tg_op = 'UPDATE' and (new.campaign_id, new.url, new.label, new.token) is not distinct from (old.campaign_id, old.url, old.label, old.token) then return new; end if;
  raise exception 'a sent campaign''s links are fixed' using errcode = 'insufficient_privilege';
end $fn$;
create trigger campaign_link_fixed before update or delete on app.campaign_links for each row execute function app.campaign_link_fixed();

-- an event row is evidence of what the provider reported: it goes with its recipient, or after 13 months (D-24);
-- a removed link may be set null by the foreign key
create function app.campaign_event_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if old.at < now() - interval '13 months' or not exists (select 1 from app.campaign_recipients where id = old.recipient_id) then return old; end if;
  elsif (new.recipient_id, new.campaign_id, new.kind, new.bounce_kind, new.smtp_code, new.client_class, new.provider_event_id, new.at)
        is not distinct from (old.recipient_id, old.campaign_id, old.kind, old.bounce_kind, old.smtp_code, old.client_class, old.provider_event_id, old.at)
        and (new.link_id is not distinct from old.link_id or new.link_id is null) then
    return new;
  end if;
  raise exception 'campaign events are append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger campaign_event_fixed before update or delete on app.campaign_events for each row execute function app.campaign_event_fixed();

-- a scheduled or sent campaign keeps what it sent (the report shows it); a segment or template removed later is set
-- null by its foreign key, never replaced; only a draft (or a sandbox sample) can be deleted
create function app.campaign_guard() returns trigger
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
        new.sender_domain_id, new.product, new.coupon_code, new.utm_source, new.utm_medium, new.utm_campaign, new.tracking, new.scheduled_at, new.audience_name)
       is distinct from
       (old.type, old.design, old.html, old.rendered_html, old.subject_a, old.subject_b, old.preheader, old.ab_percent, old.ab_metric, old.ab_wait,
        old.sender_domain_id, old.product, old.coupon_code, old.utm_source, old.utm_medium, old.utm_campaign, old.tracking, old.scheduled_at, old.audience_name)
       or (new.segment_id is distinct from old.segment_id and new.segment_id is not null)
       or (new.template_id is distinct from old.template_id and new.template_id is not null)
       or (old.ab_winner is not null and new.ab_winner is distinct from old.ab_winner) then
      raise exception 'a scheduled or sent campaign''s content is fixed' using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end $fn$;
create trigger campaign_guard before update or delete on app.campaigns for each row execute function app.campaign_guard();

-- ---------------------------------------------------------------------------
-- helpers
-- a UTM-safe slug: lower case, Norwegian letters spelled out, anything else a dash
create function app.slug(p text) returns text
  language sql immutable set search_path = ''
as $fn$
  select left(trim(both '-' from regexp_replace(replace(replace(replace(lower(coalesce(p, '')), 'æ', 'ae'), 'ø', 'o'), 'å', 'a'), '[^a-z0-9]+', '-', 'g')), 40)
$fn$;

-- why a person cannot receive marketing, or null when they can (D-27: subscribed, an address, not suppressed)
create function app.marketing_skip(p_status text, p_email text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select case when nullif(btrim(p_email), '') is null then 'no_email'
              when p_status is distinct from 'subscribed' then 'not_subscribed'
              when exists (select 1 from app.suppressions s where s.email_sha256 = app.email_hash(p_email)) then 'suppressed' end
$fn$;

-- a domain is authenticated when the DNS check found SPF, DKIM and a DMARC record; verified when the provider also
-- verified it. Scheduling needs the first, sending both (CMP-08).
create function app.domain_authenticated(d app.sender_domains) returns boolean
  language sql stable set search_path = ''
as $fn$ select d.id is not null and d.deleted_at is null and coalesce(d.spf_ok, false) and coalesce(d.dkim_ok, false) and d.dmarc_policy is not null $fn$;

create function app.domain_verified(d app.sender_domains) returns boolean
  language sql stable set search_path = ''
as $fn$ select app.domain_authenticated(d) and d.verified_at is not null $fn$;

-- a percentage with one decimal, or null when there is nothing to divide by (no fabricated 0 %)
create function app.pct(p_n numeric, p_d numeric) returns numeric
  language sql immutable set search_path = ''
as $fn$ select case when coalesce(p_d, 0) = 0 then null else round(100.0 * coalesce(p_n, 0) / p_d, 1) end $fn$;

-- the people a segment query matches, as the caller (or the acting owner) may see them: (id, email, marketing_status)
create function app.segment_sql(p_query jsonb, p_sample boolean) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare e app.entities;
begin
  if p_query is null or jsonb_typeof(p_query) <> 'object' or (p_query ? 'filters' and jsonb_typeof(p_query -> 'filters') <> 'array') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'query';
  end if;
  select * into e from app.entities where key = 'person';
  return format('select t.id, t.email, t.marketing_status from app.people t where t.deleted_at is null and t.is_sample = %L and %s %s',
                coalesce(p_sample, false), app.vis_sql(e), app.filter_sql(e, p_query -> 'filters'));
end $fn$;

-- CMP-03: matches, and the addresses that can receive marketing (one per address: a shared address is mailed once)
create function app.segment_counts(p_query jsonb, p_sample boolean) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_m bigint; v_r bigint;
begin
  execute format('select count(*), count(distinct lower(s.email)) filter (where app.marketing_skip(s.marketing_status, s.email) is null) from (%s) s',
                 app.segment_sql(p_query, p_sample)) into v_m, v_r;
  return jsonb_build_object('matches', v_m, 'receivable', v_r);
end $fn$;

-- the design model (CMP-01): {rows: [{kind, text?, fs?, bg?, padding?, border?, src?, href?, html?}]}. The footer is
-- fixed (D-27): exactly one, the last row, nothing but its background. The HTML block is sanitised by allowlist.
create function app.campaign_design_check(p_design jsonb) returns jsonb
  language plpgsql immutable set search_path = ''
as $fn$
declare r jsonb; i int := 0; n int; k text; x text;
begin
  if p_design is null or jsonb_typeof(p_design) <> 'object' or jsonb_typeof(p_design -> 'rows') <> 'array' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design';
  end if;
  n := jsonb_array_length(p_design -> 'rows');
  if n < 1 or n > 200 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.rows'; end if;
  for r in select value from jsonb_array_elements(p_design -> 'rows') loop
    if jsonb_typeof(r) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i; end if;
    k := r ->> 'kind';
    if k is null or k not in ('header', 'title', 'paragraph', 'list', 'image', 'button', 'divider', 'social', 'html', 'video', 'icons', 'menu', 'footer') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.kind';
    end if;
    for x in select jsonb_object_keys(r) loop
      if x not in ('kind', 'text', 'fs', 'bg', 'padding', 'border', 'src', 'href', 'alt', 'html', 'items') or (k = 'footer' and x not in ('kind', 'bg')) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.' || x;
      end if;
    end loop;
    if (k = 'footer') <> (i = n - 1) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.footer'; end if;
    if r ? 'bg' and coalesce(r ->> 'bg', '') not in ('card', 'soft_yellow', 'mint', 'cream') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.bg';
    end if;
    if r ? 'padding' and coalesce(r ->> 'padding', '') not in ('14', '22', '32') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.padding';
    end if;
    if r ? 'border' and coalesce(r ->> 'border', '') not in ('none', 'hairline') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.border';
    end if;
    if r ? 'fs' and (jsonb_typeof(r -> 'fs') <> 'number' or (r ->> 'fs')::numeric not between 10 and 48) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.fs';
    end if;
    if char_length(coalesce(r ->> 'text', '')) > 5000 or char_length(coalesce(r ->> 'alt', '')) > 300 then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.text';
    end if;
    if (r ? 'src' and (coalesce(r ->> 'src', '') !~ '^https://[^\s"<>]+$' or char_length(r ->> 'src') > 2000))
       or (r ? 'href' and (coalesce(r ->> 'href', '') !~ '^(https?://|mailto:)[^\s"<>]+$' or char_length(r ->> 'href') > 2000)) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.' || case when r ? 'src' and coalesce(r ->> 'src', '') !~ '^https://' then 'src' else 'href' end;
    end if;
    if r ? 'html' and (k <> 'html' or char_length(coalesce(r ->> 'html', '')) > 100000 or app.doc_html_unsafe(r ->> 'html')) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.html';
    end if;
    if r ? 'items' and (jsonb_typeof(r -> 'items') <> 'array' or jsonb_array_length(r -> 'items') > 50 or char_length((r -> 'items')::text) > 10000) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'design.' || i || '.items';
    end if;
    i := i + 1;
  end loop;
  return p_design;
end $fn$;

-- hand-written HTML (a campaign's or a template's): sanitised, and it must carry the footer's unsubscribe token
create function app.campaign_html_check(p_html text, p_field text default 'html') returns text
  language plpgsql immutable set search_path = ''
as $fn$
begin
  if coalesce(btrim(p_html), '') = '' or char_length(p_html) > 500000 or app.doc_html_unsafe(p_html) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = p_field;
  end if;
  if position('[Unsubscribe]' in p_html) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = p_field || '.footer'; end if;
  return p_html;
end $fn$;

-- the first merge token the registry does not hold for campaigns, or null
create function app.campaign_unknown_token(p_text text) returns text
  language sql stable security definer set search_path = ''
as $fn$ select app.merge_render(p_text, '{"context":"campaign"}'::jsonb) -> 'unknown' ->> 0 $fn$;

-- a unique UTM campaign: the given one, or the name's slug plus the month (okt-2026 style, by number: 2026-10)
create function app.campaign_utm(p_wanted text, p_name text, p_except uuid default null) returns text
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_base text := coalesce(nullif(p_wanted, ''), nullif(app.slug(p_name), '') || '-' || to_char(now() at time zone 'Europe/Oslo', 'YYYY-MM'), 'campaign');
        v text := v_base; i int := 1;
begin
  if v_base !~ '^[a-z0-9_-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'utm_campaign'; end if;
  while exists (select 1 from app.campaigns c where c.utm_campaign = v and c.deleted_at is null and not c.is_sample and c.id is distinct from p_except) loop
    if nullif(p_wanted, '') is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'utm_campaign'; end if;
    i := i + 1; v := left(v_base, 56) || '-' || i;
  end loop;
  return v;
end $fn$;

-- may the caller see this campaign's figures? Their own, or with reports of others (or edit of others)
create function app.campaign_reports_ok(c app.campaigns) returns boolean
  language sql stable security definer set search_path = ''
as $fn$ select c.owner_id = app.me() or app.can('campaigns', 'reports_others') or app.can('campaigns', 'edit_others') $fn$;

-- read a campaign for an action: see, edit (own with add, others' with edit_others), delete, reports
create function app.campaign_take(p_id uuid, p_action text) returns app.campaigns
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('campaigns', case p_action when 'edit' then 'add' when 'delete' then 'delete' else 'see' end);
  v_sandbox boolean := (select sandbox from app.admins where id = v_me); c app.campaigns;
begin
  perform app.require_module('campaigns');
  if p_action in ('edit', 'delete') then
    select * into c from app.campaigns where id = p_id and deleted_at is null for update;
  else
    select * into c from app.campaigns where id = p_id and deleted_at is null;
  end if;
  if not found or not app.visible(c.owner_id, c.visibility) or (c.is_sample and not v_sandbox) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  if p_action in ('edit', 'delete') and c.owner_id is distinct from v_me and not app.can('campaigns', 'edit_others') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:edit_others';
  end if;
  if p_action = 'reports' and not app.campaign_reports_ok(c) then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'campaigns:reports_others';
  end if;
  return c;
end $fn$;

-- ---------------------------------------------------------------------------
-- figures (CMP-06, CMP-09): one function, so the list, the card and the comparison print the same numbers.
-- Rates are over delivered (click-through over unique opens); open and click figures are null while tracking is off.
-- Signups and MRR won: last touch with the campaign's utm_campaign after sending started (Q14), NOK only.
create function app.campaign_stats(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare c app.campaigns; r record; v_track boolean; v_signups bigint; v_mrr numeric; v_excl bigint;
begin
  select * into c from app.campaigns where id = p_id;
  if not found or not exists (select 1 from app.campaign_recipients x where x.campaign_id = p_id) then return null; end if;
  v_track := c.tracking and app.setting('tracking') <> 'off';
  select count(*) recipients,
         count(*) filter (where state not in ('queued', 'skipped')) sent,
         count(*) filter (where state = 'queued') queued,
         count(*) filter (where state = 'skipped') skipped,
         count(*) filter (where state = 'failed') failed,
         count(delivered_at) delivered,
         count(*) filter (where state = 'bounced') hard,
         count(*) filter (where state = 'soft_bounced') soft,
         count(first_open_at) uo, coalesce(sum(opens), 0) tos, count(first_click_at) uc, coalesce(sum(clicks), 0) tc,
         count(unsubscribed_at) unsub, count(complained_at) compl,
         count(delivered_at) filter (where variant = 'a') a_d, count(first_open_at) filter (where variant = 'a') a_o, count(first_click_at) filter (where variant = 'a') a_c,
         count(delivered_at) filter (where variant = 'b') b_d, count(first_open_at) filter (where variant = 'b') b_o, count(first_click_at) filter (where variant = 'b') b_c
    into r from app.campaign_recipients where campaign_id = p_id;
  if c.started_at is not null then
    select count(distinct (ap.product, ap.tenant_id)),
           coalesce(sum(app.sub_mrr(s)) filter (where s.confirmed_at is not null and s.currency = 'NOK'), 0),
           count(*) filter (where s.confirmed_at is not null and s.currency <> 'NOK' and app.sub_mrr(s) > 0)
      into v_signups, v_mrr, v_excl
    from app.account_products ap left join app.subscriptions s on s.product = ap.product and s.tenant_id = ap.tenant_id
    where ap.created_at >= c.started_at
      and lower(coalesce(ap.attribution -> 'last_touch' ->> 'utm_campaign', ap.attribution ->> 'utm_campaign')) = c.utm_campaign;
  end if;
  return jsonb_build_object(
    'recipients', r.recipients, 'sent', r.sent, 'queued', r.queued, 'skipped', r.skipped, 'failed', r.failed, 'delivered', r.delivered,
    'bounced', r.hard + r.soft, 'bounced_hard', r.hard, 'bounced_soft', r.soft, 'bounce_rate', app.pct(r.hard + r.soft, r.sent),
    'tracking', v_track,
    'unique_opens', case when v_track then r.uo end, 'total_opens', case when v_track then r.tos end,
    'unique_clicks', case when v_track then r.uc end, 'total_clicks', case when v_track then r.tc end,
    'open_rate', case when v_track then app.pct(r.uo, r.delivered) end, 'click_rate', case when v_track then app.pct(r.uc, r.delivered) end,
    'ctor', case when v_track then app.pct(r.uc, r.uo) end,
    'unsubscribed', r.unsub, 'unsub_rate', app.pct(r.unsub, r.delivered), 'complaints', r.compl, 'complaint_rate', app.pct(r.compl, r.delivered),
    'a_metric', case when v_track and c.subject_b is not null then app.pct(case c.ab_metric when 'opens' then r.a_o else r.a_c end, r.a_d) end,
    'b_metric', case when v_track and c.subject_b is not null then app.pct(case c.ab_metric when 'opens' then r.b_o else r.b_c end, r.b_d) end,
    'signups', v_signups, 'mrr_won', case when c.started_at is not null then v_mrr end, 'mrr_excluded_currency', v_excl);
end $fn$;

-- the workflows whose current version has a campaign_action step on this campaign (the automated audience line)
create function app.campaign_workflows(p_id uuid) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name, 'state', w.state) order by w.name), '[]'::jsonb)
  from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
  where w.deleted_at is null and exists (select 1 from jsonb_each(v.flat) n(k, x) where n.k <> '_start' and x ->> 'kind' = 'campaign_action' and x -> 'config' ->> 'campaign_id' = p_id::text)
$fn$;

create function app.campaign_row(c app.campaigns, p_detail boolean default false) returns jsonb
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
      'postal_address', d.postal_address, 'product', c.product, 'coupon_code', c.coupon_code,
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

-- ---------------------------------------------------------------------------
-- campaigns: list, read, save, duplicate, delete
create function public.campaigns_get(p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
        q jsonb := coalesce(p_query, '{}'::jsonb);
begin
  perform app.require_module('campaigns');
  if jsonb_typeof(q) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'query'; end if;
  if q ? 'type' and q ->> 'type' not in ('newsletter', 'one_off', 'promotion', 'product_announcement', 'automated') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type';
  end if;
  if q ? 'status' and q ->> 'status' not in ('draft', 'scheduled', 'sending', 'sent', 'active', 'paused', 'canceled') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status';
  end if;
  select coalesce(jsonb_agg(app.campaign_row(c) order by coalesce(c.sent_at, c.started_at, c.scheduled_at, c.created_at) desc, c.seq desc), '[]'::jsonb) into v_rows
  from (select * from app.campaigns c where c.deleted_at is null and app.visible(c.owner_id, c.visibility) and (v_sandbox or not c.is_sample)
          and (not q ? 'type' or c.type = q ->> 'type') and (not q ? 'status' or c.status = q ->> 'status')
          and (coalesce(btrim(q ->> 'q'), '') = '' or c.name ilike '%' || replace(replace(btrim(q ->> 'q'), '%', '\%'), '_', '\_') || '%')
          and (coalesce(q ->> 'owner', '') <> 'me' or c.owner_id = v_me)
        order by coalesce(c.sent_at, c.started_at, c.scheduled_at, c.created_at) desc, c.seq desc
        limit least(greatest(coalesce((q ->> 'limit')::int, 100), 1), 200)) c;
  perform app.log('record.listed', 'campaign', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'provider_connected', app.connected('email'));
end $fn$;

create function public.campaign_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'see');
begin
  insert into app.recents (staff_id, entity, record_id) values (app.me(), 'campaign', p_id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'campaign', p_id::text);
  return app.campaign_row(c, true);
end $fn$;

-- create a draft (p_id null) or change one. A template starts a campaign by copying its design (CMP-02). Once
-- scheduled, only the name and the owner notice may change: the content is what was sent.
create function public.campaign_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
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
                 'sender_domain_id', 'product', 'coupon_code', 'utm_source', 'utm_medium', 'utm_campaign', 'tracking', 'notify_owners', 'visibility') then
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

  if p_id is null then
    insert into app.campaigns (name, type, segment_id, template_id, design, html, subject_a, subject_b, preheader, ab_percent, ab_metric, ab_wait,
                               sender_domain_id, product, coupon_code, utm_source, utm_medium, utm_campaign, tracking, notify_owners,
                               owner_id, visibility, created_by, updated_by, is_sample)
    values (v_name, v_type, (v ->> 'segment_id')::uuid, t.id, v_design, v_html, coalesce(btrim(v ->> 'subject_a'), nullif(t.subject, ''), ''), v_sb,
            nullif(btrim(v ->> 'preheader'), ''),
            case when v_sb is not null then coalesce((v ->> 'ab_percent')::smallint, 20) end,
            case when v_sb is not null then coalesce(v ->> 'ab_metric', 'clicks') end,
            case when v_sb is not null then make_interval(hours => coalesce((v ->> 'ab_wait_hours')::int, 4)) end,
            (v ->> 'sender_domain_id')::uuid, v ->> 'product', nullif(v ->> 'coupon_code', ''),
            coalesce(v ->> 'utm_source', 'newsletter'), coalesce(v ->> 'utm_medium', 'email'), app.campaign_utm(v ->> 'utm_campaign', v_name),
            coalesce((v ->> 'tracking')::boolean, true), coalesce((v ->> 'notify_owners')::boolean, false),
            v_me, coalesce(v ->> 'visibility', app.setting('visibility_default', 'campaign')), v_me, v_me, (select sandbox from app.admins where id = v_me))
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
        visibility = coalesce(v ->> 'visibility', visibility),
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

-- a copy as a new draft of mine (a sent campaign is kept; its copy is edited)
create function public.campaign_duplicate(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'see'); v_me uuid := app.require('campaigns', 'add'); v_id uuid;
begin
  insert into app.campaigns (name, type, segment_id, template_id, design, html, subject_a, subject_b, preheader, ab_percent, ab_metric, ab_wait,
                             sender_domain_id, product, coupon_code, utm_source, utm_medium, utm_campaign, tracking, notify_owners,
                             owner_id, visibility, created_by, updated_by, is_sample)
  select c.name, c.type,
         (select s.id from app.saved_views s where s.id = c.segment_id and (s.shared or s.owner_id = v_me)), c.template_id, c.design, c.html, c.subject_a, c.subject_b, c.preheader,
         c.ab_percent, c.ab_metric, c.ab_wait,
         (select d.id from app.sender_domains d where d.id = c.sender_domain_id and d.deleted_at is null), c.product,
         (select x.code from app.coupons x where x.code = c.coupon_code and x.active), c.utm_source, c.utm_medium,
         app.campaign_utm(null, c.name), c.tracking, c.notify_owners, v_me, c.visibility, v_me, v_me, (select sandbox from app.admins where id = v_me)
  returning id into v_id;
  insert into app.changelog (entity, record_id, field, new_value, actor_id, source) values ('campaign', v_id, '*created', jsonb_build_object('copy_of', c.id), v_me, 'ui');
  perform app.log('record.created', 'campaign', v_id::text, jsonb_build_object('copy_of', c.id));
  return app.campaign_row((select x from app.campaigns x where x.id = v_id), true);
end $fn$;

-- drafts only; a scheduled or sent campaign is kept for its report
create function public.campaign_delete(p_ids uuid[], p_reason text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'delete'); c app.campaigns; x uuid; n int := 0;
begin
  perform app.require_module('campaigns');
  perform app.take_reason(p_reason);
  if coalesce(cardinality(p_ids), 0) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
  if cardinality(p_ids) > 1 then perform app.require('campaigns', 'bulk'); end if;
  foreach x in array p_ids loop
    c := app.campaign_take(x, 'delete');
    if c.status <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
    update app.campaigns set deleted_at = now(), updated_at = now(), updated_by = v_me, version = version + 1 where id = x;
    insert into app.changelog (entity, record_id, field, actor_id, source) values ('campaign', x, '*deleted', v_me, 'ui');
    perform app.emit('campaign.deleted', 'campaign', x, '{}'::jsonb, c.is_sample);
    n := n + 1;
  end loop;
  perform app.log('record.deleted', 'campaign', case when n = 1 then p_ids[1]::text end, jsonb_build_object('count', n));
  return jsonb_build_object('deleted', n);
end $fn$;

-- ---------------------------------------------------------------------------
-- authoring: preview and test (SF-39). The renderer is the app's; these resolve the merge fields in its output.
-- → {subject_a, subject_b, preheader, html, missing, unknown, audience_missing: [{token, people}] when no person is given}
create function public.campaign_preview(p_id uuid, p_person uuid default null, p_html text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  c app.campaigns := app.campaign_take(p_id, 'see'); p app.people; v_ctx jsonb; v_html text; v_all text; r jsonb; v_missing jsonb := '[]'::jsonb;
  v_q jsonb; tok text; n bigint; v_aud jsonb := '[]'::jsonb; sa jsonb; sb jsonb; ph jsonb;
begin
  if p_person is not null then
    select * into p from app.people where id = p_person and deleted_at is null;
    if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'person'; end if;
  end if;
  v_html := coalesce(case when c.status = 'draft' then p_html end, c.rendered_html, c.html, '');
  if char_length(v_html) > 500000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'html'; end if;
  v_ctx := app.merge_context('person', p.id, p.id, c.owner_id) || jsonb_build_object('context', 'campaign', 'campaign', c.id);
  sa := app.merge_render(c.subject_a, v_ctx); sb := app.merge_render(c.subject_b, v_ctx); ph := app.merge_render(c.preheader, v_ctx);
  r := app.merge_render(v_html, v_ctx);
  v_all := concat_ws(' ', c.subject_a, c.subject_b, c.preheader, v_html);
  -- COM-05: before scheduling, how many receivable people of the segment have no value for each token
  if p_person is null and c.type <> 'automated' then
    select query into v_q from app.saved_views where id = c.segment_id;
    if v_q is not null then
      for tok in select x from unnest(app.doc_tokens(v_all)) x
                 where exists (select 1 from app.merge_fields f where f.token = x and 'campaign' = any (f.contexts) and f.format <> 'block')
                   and split_part((select f.source_path from app.merge_fields f where f.token = x), '.', 1) in ('person', 'organization') loop
        execute format('select count(*) from (%s) s where app.marketing_skip(s.marketing_status, s.email) is null
                          and app.merge_value(%L, app.merge_context(''person'', s.id, s.id) || %L::jsonb) is null',
                       app.segment_sql(v_q, c.is_sample), tok, jsonb_build_object('context', 'campaign')) into n;
        if n > 0 then v_aud := v_aud || jsonb_build_array(jsonb_build_object('token', tok, 'people', n)); end if;
      end loop;
    end if;
  end if;
  perform app.log('record.read', 'campaign', c.id::text, jsonb_build_object('preview', true));
  return jsonb_build_object('subject_a', sa ->> 'text', 'subject_b', sb ->> 'text', 'preheader', ph ->> 'text', 'html', r ->> 'text',
    'missing', to_jsonb(array(select distinct x from (select jsonb_array_elements_text(sa -> 'missing') x union select jsonb_array_elements_text(sb -> 'missing')
                                                      union select jsonb_array_elements_text(ph -> 'missing') union select jsonb_array_elements_text(r -> 'missing')) u order by 1)),
    'unknown', to_jsonb(array(select distinct x from (select jsonb_array_elements_text(sa -> 'unknown') x union select jsonb_array_elements_text(sb -> 'unknown')
                                                      union select jsonb_array_elements_text(ph -> 'unknown') union select jsonb_array_elements_text(r -> 'unknown')) u order by 1)),
    'audience_missing', v_aud);
end $fn$;

-- a test to the caller's own address through the marketing stream, merged with a person of their choice; not counted
create function public.campaign_test_send(p_id uuid, p_html text default null, p_person uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'edit'); d app.sender_domains; v_html text; v_to text; v_tok text; v_ctx jsonb; p app.people;
begin
  perform app.require_connected('email');
  select * into d from app.sender_domains where id = c.sender_domain_id;
  if not app.domain_verified(d) or d.stream <> 'marketing' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sender_domain'; end if;
  v_html := app.campaign_html_check(coalesce(case when c.status = 'draft' then p_html end, c.rendered_html));
  v_tok := app.campaign_unknown_token(concat_ws(' ', c.subject_a, c.subject_b, c.preheader, v_html));
  if v_tok is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || v_tok; end if;
  if btrim(c.subject_a) = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  if p_person is not null then
    select * into p from app.people where id = p_person and deleted_at is null;
    if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found', detail = 'person'; end if;
  end if;
  v_to := (select a.email from app.admins a where a.id = app.me());
  v_ctx := app.merge_context('person', p.id, p.id, c.owner_id) || jsonb_build_object('context', 'campaign', 'campaign', c.id);
  perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_test', 'campaign_id', c.id, 'to', v_to, 'stream', d.stream,
                                               'from', d.from_local || '@' || d.domain, 'from_name', d.from_name, 'reply_to', d.reply_to,
                                               'subjects', jsonb_build_array(app.merge_render(c.subject_a, v_ctx) ->> 'text', app.merge_render(c.subject_b, v_ctx) ->> 'text'),
                                               'html', app.merge_render(v_html, v_ctx) ->> 'text'));
  perform app.log('campaign.test_sent', 'campaign', c.id::text, null);
  return jsonb_build_object('queued', true, 'to', v_to);
end $fn$;

-- schedule (CMP-05) a broadcast, or switch on an automated campaign. The HTML is the renderer's output; it is
-- checked and frozen with its links. The provider is not needed to schedule: a due campaign waits for it.
create function public.campaign_schedule(p_id uuid, p_at timestamptz, p_version int, p_html text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'edit'); d app.sender_domains; sv app.saved_views; v_n jsonb; v_tok text; v_track boolean; v_at timestamptz;
        v_status text;
begin
  if p_version is not null and c.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = c.version::text; end if;
  if c.status <> 'draft' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if btrim(c.subject_a) = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  select * into d from app.sender_domains where id = c.sender_domain_id;
  if not app.domain_authenticated(d) or d.stream <> 'marketing' or not d.sends_here then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sender_domain';
  end if;
  if d.postal_address is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sender_domain.postal_address'; end if;
  perform app.campaign_html_check(p_html);
  -- sender identity (D-27): the footer carries the domain's postal address
  if position(d.postal_address in p_html) = 0 and position(app.html_escape(d.postal_address) in p_html) = 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'html.footer';
  end if;
  v_tok := app.campaign_unknown_token(concat_ws(' ', c.subject_a, c.subject_b, c.preheader, p_html));
  if v_tok is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || v_tok; end if;
  if c.coupon_code is not null and not exists (select 1 from app.coupons x where x.code = c.coupon_code and x.active) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'coupon_code';
  end if;
  v_track := case app.setting('tracking') when 'on' then true when 'off' then false else c.tracking end;
  if c.subject_b is not null and not v_track then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject_b'; end if;
  if c.type <> 'automated' then
    select * into sv from app.saved_views where id = c.segment_id and kind = 'segment';
    if not found then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'audience'; end if;
    v_n := app.segment_counts(sv.query, c.is_sample);
    if (v_n ->> 'receivable')::int = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'audience'; end if;
    v_at := coalesce(p_at, now());
    if v_at < now() - interval '5 minutes' or v_at > now() + interval '1 year' then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scheduled_at';
    end if;
  end if;
  v_status := case when c.type = 'automated' then 'active' else 'scheduled' end;
  update app.campaigns set status = v_status, rendered_html = p_html, tracking = v_track, scheduled_at = v_at, audience_name = sv.name,
    version = version + 1, updated_at = now(), updated_by = app.me()
  where id = c.id;
  insert into app.campaign_links (campaign_id, url, token)
  select c.id, u, app.token() from (select distinct m[1] u from regexp_matches(p_html, 'href\s*=\s*"(https?://[^"\s<>]+)"', 'gi') m
                                    where char_length(m[1]) <= 2000 limit 500) x
  on conflict (campaign_id, url) do nothing;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source)
  values ('campaign', c.id, 'status', to_jsonb(c.status), to_jsonb(v_status), app.me(), 'ui');
  perform app.log('campaign.scheduled', 'campaign', c.id::text, jsonb_build_object('status', v_status, 'at', v_at, 'audience', (v_n ->> 'receivable')::int));
  perform app.emit('campaign.scheduled', 'campaign', c.id, jsonb_build_object('type', c.type, 'audience_count', (v_n ->> 'receivable')::int), c.is_sample);
  return app.campaign_row((select x from app.campaigns x where x.id = c.id), true);
end $fn$;

-- a scheduled campaign is canceled (it was never sent; duplicate it to change and schedule again)
create function public.campaign_cancel(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'edit');
begin
  if c.status <> 'scheduled' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  update app.campaigns set status = 'canceled', canceled_at = now(), hold_reason = null, version = version + 1, updated_at = now(), updated_by = app.me() where id = c.id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('campaign', c.id, 'status', '"scheduled"', '"canceled"', app.me(), 'ui');
  perform app.log('campaign.canceled', 'campaign', c.id::text, null);
  perform app.emit('campaign.canceled', 'campaign', c.id, jsonb_build_object('type', c.type, 'audience_count', c.audience_count), c.is_sample);
  return app.campaign_row((select x from app.campaigns x where x.id = c.id), true);
end $fn$;

-- pause or resume an automated campaign: while paused, workflow steps still queue their recipients, nobody is sent
create function public.campaign_pause(p_id uuid, p_paused boolean) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'edit'); v_to text := case when p_paused then 'paused' else 'active' end;
begin
  if c.type <> 'automated' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type'; end if;
  if p_paused is null or c.status not in ('active', 'paused') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'status'; end if;
  if c.status = v_to then return app.campaign_row(c, true); end if;
  update app.campaigns set status = v_to, version = version + 1, updated_at = now(), updated_by = app.me() where id = c.id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('campaign', c.id, 'status', to_jsonb(c.status), to_jsonb(v_to), app.me(), 'ui');
  perform app.log(case when p_paused then 'campaign.paused' else 'campaign.resumed' end, 'campaign', c.id::text, null);
  if not p_paused and app.connected('email') and exists (select 1 from app.campaign_recipients r where r.campaign_id = c.id and r.state = 'queued') then
    perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_send', 'campaign_id', c.id));
  end if;
  return app.campaign_row((select x from app.campaigns x where x.id = c.id), true);
end $fn$;

-- ---------------------------------------------------------------------------
-- reports (CMP-06, CMP-09)
-- compare: the given campaigns, or the last six sent (of a type); the figures are each campaign's own
create function public.campaigns_compare(p_ids uuid[] default null, p_type text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); c app.campaigns; v_rows jsonb := '[]'::jsonb; x uuid;
begin
  perform app.require_module('campaigns');
  if p_type is not null and p_type not in ('newsletter', 'one_off', 'promotion', 'product_announcement', 'automated') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'type';
  end if;
  if p_ids is null then
    for c in select * from app.campaigns z where z.deleted_at is null and z.status in ('sent', 'sending', 'active', 'paused') and app.visible(z.owner_id, z.visibility)
               and (v_sandbox or not z.is_sample) and (p_type is null or z.type = p_type) and app.campaign_reports_ok(z)
               and exists (select 1 from app.campaign_recipients r where r.campaign_id = z.id)
             order by coalesce(z.sent_at, z.started_at) desc nulls last limit 6 loop
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('id', c.id, 'name', c.name, 'type', c.type, 'status', c.status, 'sent_at', c.sent_at, 'stats', app.campaign_stats(c.id)));
    end loop;
  else
    if cardinality(p_ids) > 20 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'ids'; end if;
    foreach x in array p_ids loop
      c := app.campaign_take(x, 'reports');
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('id', c.id, 'name', c.name, 'type', c.type, 'status', c.status, 'sent_at', c.sent_at, 'stats', app.campaign_stats(c.id)));
    end loop;
  end if;
  perform app.log('record.listed', 'campaign', null, jsonb_build_object('compare', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'axis_max', 100);
end $fn$;

-- the recipients of a campaign; a person the caller may not see is listed without name or address
create function public.campaign_recipients(p_id uuid, p_state text default null, p_limit int default 100) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns := app.campaign_take(p_id, 'reports'); v_rows jsonb;
begin
  if p_state is not null and p_state not in ('queued', 'sent', 'delivered', 'soft_bounced', 'bounced', 'complained', 'failed', 'skipped') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'state';
  end if;
  select coalesce(jsonb_agg(x.j order by x.created_at, x.id), '[]'::jsonb) into v_rows from (
    select r.created_at, r.id, jsonb_build_object('id', r.id, 'person_id', case when ok.v then r.person_id end, 'name', case when ok.v then p.name end,
             'email', case when ok.v then r.email end, 'state', r.state, 'skip_reason', r.skip_reason, 'variant', r.variant, 'sent_at', r.sent_at,
             'delivered_at', r.delivered_at, 'opened_at', case when c.tracking then r.first_open_at end, 'clicked_at', case when c.tracking then r.first_click_at end,
             'unsubscribed_at', r.unsubscribed_at, 'complained_at', r.complained_at, 'bounce_kind', r.bounce_kind) j
    from app.campaign_recipients r left join app.people p on p.id = r.person_id and p.deleted_at is null
    cross join lateral (select p.id is not null and app.visible(p.owner_id, p.visibility) v) ok
    where r.campaign_id = c.id and (p_state is null or r.state = p_state)
    order by r.created_at, r.id limit least(greatest(coalesce(p_limit, 100), 1), 1000)) x;
  perform app.log('record.listed', 'campaign_recipient', c.id::text, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'stats', app.campaign_stats(c.id));
end $fn$;

-- the recipients as CSV (campaigns:export); people the caller may not see keep their row without name or address
create function public.campaign_export(p_id uuid, p_format text default 'csv') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; v_me uuid := app.require('campaigns', 'export'); v_csv text; n int;
begin
  c := app.campaign_take(p_id, 'reports');
  if p_format is distinct from 'csv' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'format'; end if;
  select count(*), 'email,name,state,skip_reason,variant,sent_at,delivered_at,opened_at,clicked_at,unsubscribed_at,complained_at,bounce_kind' || chr(10)
         || coalesce(string_agg(concat_ws(',',
              app.csv_cell(case when ok.v then r.email end), app.csv_cell(case when ok.v then p.name end), r.state, r.skip_reason, r.variant,
              r.sent_at, r.delivered_at, case when c.tracking then r.first_open_at end, case when c.tracking then r.first_click_at end,
              r.unsubscribed_at, r.complained_at, r.bounce_kind), chr(10) order by r.created_at, r.id), '')
    into n, v_csv
  from app.campaign_recipients r left join app.people p on p.id = r.person_id and p.deleted_at is null
  cross join lateral (select p.id is not null and app.visible(p.owner_id, p.visibility) v) ok
  where r.campaign_id = c.id;
  perform app.log('record.exported', 'campaign_recipient', c.id::text, jsonb_build_object('count', n, 'format', 'csv'));
  return jsonb_build_object('filename', 'campaign-' || c.seq || '-recipients.csv', 'mime', 'text/csv', 'rows', n, 'content', v_csv);
end $fn$;

create function app.csv_cell(p text) returns text
  language sql immutable set search_path = ''
as $fn$ select case when p is null then '' when p ~ '[",\n\r]' or p ~ '^[=+@-]' then '"' || replace(case when p ~ '^[=+@-]' then '''' || p else p end, '"', '""') || '"' else p end $fn$;

-- ---------------------------------------------------------------------------
-- sending (SF-19). campaign_due starts what is due; the edge worker drains batches through the provider's marketing
-- stream and reports back; provider webhooks arrive through worker_email_events.

-- resolve a broadcast's audience into recipients, as the campaign's owner sees people (D-09). One queued row per
-- receivable address; everyone else in the segment is a skipped row with the reason. Returns the number queued.
create function app.campaign_resolve(c app.campaigns) returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_q jsonb; v_n int; v_test int;
begin
  select query into v_q from app.saved_views where id = c.segment_id and kind = 'segment';
  if v_q is null then return 0; end if;
  execute format($q$
    insert into app.campaign_recipients (campaign_id, person_id, email, state, skip_reason, is_sample)
    select %L, s.id, case when x.reason is null then lower(btrim(s.email)) end, case when x.reason is null then 'queued' else 'skipped' end, x.reason, %L
    from (select s.*, app.marketing_skip(s.marketing_status, s.email) own,
                 row_number() over (partition by lower(btrim(s.email)) order by (app.marketing_skip(s.marketing_status, s.email) is null) desc, s.id) rn
          from (%s) s) s
    cross join lateral (select case when s.own is null and s.rn > 1 then 'duplicate' else s.own end reason) x
    on conflict (campaign_id, person_id, send_key) do nothing$q$, c.id, c.is_sample, app.segment_sql(v_q, c.is_sample));
  select count(*) into v_n from app.campaign_recipients where campaign_id = c.id and state = 'queued';
  -- A/B (CMP-05): ab_percent of the audience is split between subject A and B; the rest waits for the winner
  if c.subject_b is not null and v_n > 0 then
    v_test := least(v_n, greatest(2, round(v_n * c.ab_percent / 100.0)::int));
    update app.campaign_recipients r set variant = case when q.rn <= v_test then case when q.rn % 2 = 1 then 'a' else 'b' end else 'w' end
    from (select id, row_number() over (order by random()) rn from app.campaign_recipients where campaign_id = c.id and state = 'queued') q
    where q.id = r.id;
  end if;
  return v_n;
end $fn$;

-- one person for an automated campaign (a workflow's campaign_action step, CMP-07). → null when queued, else the
-- reason it was skipped: not_subscribed, suppressed, no_email (never to unsubscribed people, D-27) or duplicate
create function app.campaign_enqueue(p_campaign uuid, p_person uuid, p_send_key text) returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; p app.people; v_skip text; v_key text := lower(left(regexp_replace(coalesce(p_send_key, 'once'), '[^a-zA-Z0-9-]', '-', 'g'), 64));
begin
  select * into c from app.campaigns where id = p_campaign and deleted_at is null;
  if not found or c.type <> 'automated' then raise exception 'campaign_missing'; end if;
  if c.status not in ('active', 'paused') then raise exception 'campaign_inactive'; end if;
  select * into p from app.people where id = p_person and deleted_at is null;
  if p.id is null then return 'no_email'; end if;
  if exists (select 1 from app.campaign_recipients r where r.campaign_id = c.id and r.person_id = p.id and r.send_key = v_key) then return 'duplicate'; end if;
  v_skip := app.marketing_skip(p.marketing_status, p.email);
  insert into app.campaign_recipients (campaign_id, person_id, email, send_key, state, skip_reason, is_sample)
  values (c.id, p.id, case when v_skip is null then lower(btrim(p.email)) end, v_key, case when v_skip is null then 'queued' else 'skipped' end, v_skip, c.is_sample);
  if v_skip is null and c.status = 'active' and app.connected('email') then
    perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_send', 'campaign_id', c.id));
  end if;
  return v_skip;
end $fn$;

-- a broadcast is sent when nobody is left in the queue; the owner hears how it went (send failures and bounces alert)
create function app.campaign_finish(p_id uuid) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; s jsonb;
begin
  select * into c from app.campaigns where id = p_id for update;
  if not found or c.status <> 'sending' then return; end if;
  if exists (select 1 from app.campaign_recipients r where r.campaign_id = p_id and r.state = 'queued') then return; end if;
  update app.campaigns set status = 'sent', sent_at = now(), updated_at = now() where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, source) values ('campaign', p_id, 'status', '"sending"', '"sent"', 'system');
  s := app.campaign_stats(p_id);
  perform app.emit('campaign.sent', 'campaign', p_id, jsonb_build_object('type', c.type, 'audience_count', c.audience_count), c.is_sample);
  perform app.log('campaign.sent', 'campaign', p_id::text, jsonb_build_object('sent', s -> 'sent', 'failed', s -> 'failed', 'bounced', s -> 'bounced'));
  if c.owner_id is not null then
    perform app.notify(c.owner_id, 'system',
                       case when coalesce((s ->> 'failed')::int, 0) > 0 or coalesce((s ->> 'bounce_rate')::numeric, 0) > 3 then 'campaign.sent_with_problems' else 'campaign.sent' end,
                       jsonb_build_object('campaign', c.name, 'sent', s -> 'sent', 'failed', s -> 'failed', 'bounce_rate', s -> 'bounce_rate'),
                       '/campaigns', 'campaign', p_id);
  end if;
end $fn$;

-- every minute: start what is due. Without the provider, or with an unverified domain, or with nobody left to
-- receive it, a due campaign stays scheduled with its hold reason, and the owner is told once per reason.
create function app.campaign_due() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; d app.sender_domains; v_hold text; v_q jsonb; v_n int; n int := 0; v_prev text := current_setting('app.acting_as', true); x uuid;
begin
  for c in select * from app.campaigns where status = 'scheduled' and scheduled_at <= now() and deleted_at is null order by scheduled_at for update skip locked loop
    select * into d from app.sender_domains where id = c.sender_domain_id;
    select query into v_q from app.saved_views where id = c.segment_id and kind = 'segment';
    v_hold := case when not app.connected('email') then 'not_connected:email'
                   when not app.domain_verified(d) then 'sender_domain'
                   when v_q is null then 'audience' end;
    if v_hold is null then
      perform set_config('app.acting_as', coalesce(c.owner_id::text, ''), true);
      if coalesce((app.segment_counts(v_q, c.is_sample) ->> 'receivable')::int, 0) = 0 then
        v_hold := 'audience';
      else
        v_n := app.campaign_resolve(c);
      end if;
      perform set_config('app.acting_as', coalesce(v_prev, ''), true);
    end if;
    if v_hold is not null then
      if c.hold_reason is distinct from v_hold then
        update app.campaigns set hold_reason = v_hold where id = c.id;
        perform app.log('campaign.held', 'campaign', c.id::text, jsonb_build_object('reason', v_hold));
        if c.owner_id is not null then
          perform app.notify(c.owner_id, 'system', 'campaign.held', jsonb_build_object('campaign', c.name, 'reason', v_hold), '/campaigns', 'campaign', c.id);
        end if;
      end if;
      continue;
    end if;
    update app.campaigns set status = 'sending', started_at = now(), hold_reason = null, audience_count = v_n, updated_at = now() where id = c.id;
    insert into app.changelog (entity, record_id, field, old_value, new_value, source) values ('campaign', c.id, 'status', '"scheduled"', '"sending"', 'system');
    perform app.log('campaign.started', 'campaign', c.id::text, jsonb_build_object('audience', v_n));
    perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_send', 'campaign_id', c.id));
    n := n + 1;
  end loop;
  -- queued recipients nobody has claimed (a lost job, a decided A/B test, automated steps): one job per campaign
  if app.connected('email') then
    for x in select distinct r.campaign_id from app.campaign_recipients r join app.campaigns z on z.id = r.campaign_id
             where z.status in ('sending', 'active') and r.state = 'queued' and (r.claimed_at is null or r.claimed_at < now() - interval '15 minutes')
               and (r.variant is distinct from 'w' or z.ab_winner is not null) loop
      perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_send', 'campaign_id', x));
    end loop;
  end if;
  for x in select id from app.campaigns where status = 'sending' loop perform app.campaign_finish(x); end loop;
  return n;
end $fn$;
select cron.schedule('platform-campaign-due', '* * * * *', 'select app.campaign_due()');

-- every ten minutes: an A/B test whose wait is over picks its winner by its metric over delivered (Q17: clicks by
-- default, opens counting human opens only); a tie keeps A. The rest of the audience then gets the winner.
create function app.campaign_ab_decide() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; s jsonb; v_w text; n int := 0;
begin
  for c in select * from app.campaigns where status = 'sending' and subject_b is not null and ab_winner is null and started_at + ab_wait <= now() for update skip locked loop
    s := app.campaign_stats(c.id);
    v_w := case when coalesce((s ->> 'b_metric')::numeric, -1) > coalesce((s ->> 'a_metric')::numeric, -1) then 'b' else 'a' end;
    update app.campaigns set ab_winner = v_w, ab_decided_at = now(), updated_at = now() where id = c.id;
    perform app.log('campaign.ab_decided', 'campaign', c.id::text, jsonb_build_object('winner', v_w, 'a', s -> 'a_metric', 'b', s -> 'b_metric'));
    if c.owner_id is not null then
      perform app.notify(c.owner_id, 'system', 'campaign.ab_decided', jsonb_build_object('campaign', c.name, 'winner', v_w, 'a', s -> 'a_metric', 'b', s -> 'b_metric'),
                         '/campaigns', 'campaign', c.id);
    end if;
    if app.connected('email') then perform pgmq.send('jobs', jsonb_build_object('job', 'campaign_send', 'campaign_id', c.id)); end if;
    n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-campaign-ab', '*/10 * * * *', 'select app.campaign_ab_decide()');

-- the send worker's batch: up to p_limit queued recipients, each checked again at this moment (an unsubscribe or a
-- bounce since the audience was resolved skips them), each with the subject and HTML merged for them and a fresh
-- unsubscribe token returned once (only its SHA-256 is kept). The worker puts [Unsubscribe] → go.owntheagenda.com/u/<token>
-- and the List-Unsubscribe headers (RFC 8058) into each message.
create function public.worker_campaign_batch(p_campaign uuid, p_limit int default 50) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.campaigns; d app.sender_domains; r app.campaign_recipients; p app.people; v_skip text; v_tok text; v_ctx jsonb; v_subj text; out jsonb := '[]'::jsonb;
begin
  perform app.require_connected('email');
  select * into c from app.campaigns where id = p_campaign;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into d from app.sender_domains where id = c.sender_domain_id;
  if c.status not in ('sending', 'active') then return jsonb_build_object('campaign', jsonb_build_object('id', c.id, 'status', c.status), 'recipients', out); end if;
  if not app.domain_verified(d) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sender_domain'; end if;
  for r in select * from app.campaign_recipients x where x.campaign_id = c.id and x.state = 'queued'
             and (x.claimed_at is null or x.claimed_at < now() - interval '15 minutes') and (x.variant is distinct from 'w' or c.ab_winner is not null)
           order by x.created_at, x.id limit least(greatest(coalesce(p_limit, 50), 1), 500) for update skip locked loop
    select * into p from app.people where id = r.person_id and deleted_at is null;
    v_skip := case when p.id is null then 'no_email' else app.marketing_skip(p.marketing_status, p.email) end;
    if v_skip is null and exists (select 1 from app.campaign_recipients y where y.campaign_id = c.id and y.id <> r.id and y.email = lower(btrim(p.email))
                                  and y.state not in ('queued', 'skipped', 'failed')) then
      v_skip := 'duplicate';
    end if;
    if v_skip is not null then
      update app.campaign_recipients set state = 'skipped', skip_reason = v_skip, email = null, claimed_at = null where id = r.id;
      continue;
    end if;
    v_tok := app.token();
    update app.campaign_recipients set claimed_at = now(), email = lower(btrim(p.email)), unsub_token_sha256 = app.token_hash(v_tok) where id = r.id;
    v_subj := case when r.variant = 'b' or (r.variant = 'w' and c.ab_winner = 'b') then c.subject_b else c.subject_a end;
    v_ctx := app.merge_context('person', p.id, p.id, c.owner_id) || jsonb_build_object('context', 'campaign', 'campaign', c.id);
    out := out || jsonb_build_array(jsonb_build_object(
      'id', r.id, 'email', lower(btrim(p.email)), 'name', p.name, 'variant', r.variant, 'unsub_token', v_tok,
      'subject', app.merge_render(v_subj, v_ctx) ->> 'text', 'preheader', app.merge_render(c.preheader, v_ctx) ->> 'text',
      'html', app.merge_render(c.rendered_html, v_ctx) ->> 'text',
      -- the footer's wording follows the basis (Q19): existing customer or consent
      'basis', case when (select ce.basis from app.consent_events ce where ce.person_id = p.id and ce.status = 'subscribed' order by ce.id desc limit 1) = 'existing_customer'
                    then 'existing_customer' else 'consent' end));
  end loop;
  perform app.campaign_finish(c.id);
  return jsonb_build_object(
    'campaign', jsonb_build_object('id', c.id, 'status', c.status, 'stream', d.stream, 'from', d.from_local || '@' || d.domain, 'from_name', d.from_name,
                                   'reply_to', d.reply_to, 'postal_address', d.postal_address, 'tracking', c.tracking,
                                   'utm', jsonb_build_object('utm_source', c.utm_source, 'utm_medium', c.utm_medium, 'utm_campaign', c.utm_campaign),
                                   'links', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'token', l.token)) from app.campaign_links l where l.campaign_id = c.id), '[]'::jsonb)),
    'recipients', out);
end $fn$;

create function public.worker_campaign_sent(p_recipient uuid, p_provider_message_id text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.campaign_recipients;
begin
  if coalesce(btrim(p_provider_message_id), '') = '' or char_length(p_provider_message_id) > 200 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'provider_message_id';
  end if;
  update app.campaign_recipients set state = 'sent', sent_at = coalesce(sent_at, now()), provider_message_id = p_provider_message_id, claimed_at = null
  where id = p_recipient and state = 'queued' returning * into r;
  if not found then
    if exists (select 1 from app.campaign_recipients where id = p_recipient and provider_message_id = p_provider_message_id) then return jsonb_build_object('already', true); end if;
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  insert into app.campaign_events (recipient_id, campaign_id, kind, at) values (r.id, r.campaign_id, 'sent', now());
  perform app.campaign_finish(r.campaign_id);
  return jsonb_build_object('ok', true);
end $fn$;

create function public.worker_campaign_failed(p_recipient uuid, p_code text) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.campaign_recipients;
begin
  if coalesce(p_code, '') !~ '^[a-z0-9_.:-]{1,60}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'code'; end if;
  update app.campaign_recipients set state = 'failed', failure_code = p_code, claimed_at = null where id = p_recipient and state = 'queued' returning * into r;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.campaign_finish(r.campaign_id);
  return jsonb_build_object('ok', true);
end $fn$;

-- an address the provider says is dead: suppressed for everything, the person «bounced» (CMP-06 RU)
create function app.campaign_address_down(r app.campaign_recipients, p_reason text, p_code text) returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.people;
begin
  if r.email is not null then
    insert into app.suppressions (email_sha256, scope, reason, campaign_id) values (app.email_hash(r.email), 'all', p_reason, r.campaign_id) on conflict do nothing;
  end if;
  select * into p from app.people where id = r.person_id and deleted_at is null;
  if p.id is not null and p.marketing_status not in ('bounced', 'unsubscribed') then
    perform app.consent_write(p.id, 'bounced', 'provider', null, 'provider', r.campaign_id, null, coalesce(p_code, p_reason), 'system');
  end if;
end $fn$;

-- an unsubscribe, honoured in the same transaction: the recipient, the suppression by hash, the person's status
create function app.campaign_unsubscribe(r app.campaign_recipients, p_scope text, p_method text) returns boolean
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare p app.people; c app.campaigns;
begin
  select * into c from app.campaigns where id = r.campaign_id;
  update app.campaign_recipients set unsubscribed_at = coalesce(unsubscribed_at, now()) where id = r.id;
  if r.email is not null then
    insert into app.suppressions (email_sha256, scope, reason, campaign_id) values (app.email_hash(r.email), p_scope, 'unsubscribed', r.campaign_id) on conflict do nothing;
  end if;
  select * into p from app.people where id = r.person_id and deleted_at is null;
  if p.id is not null and p.marketing_status <> 'unsubscribed' then
    perform app.consent_write(p.id, 'unsubscribed', 'unsubscribe', null, 'campaign', r.campaign_id, null, p_method, 'system');
  end if;
  if r.unsubscribed_at is null and r.person_id is not null then
    perform app.emit('campaign.unsubscribed', 'person', r.person_id, jsonb_build_object('campaign', r.campaign_id), c.is_sample);
  end if;
  return r.unsubscribed_at is null;
end $fn$;

-- the public unsubscribe page and the one-click POST (go.owntheagenda.com/u/<token>)
create function public.worker_unsubscribe(p_token text, p_scope text default 'marketing', p_method text default 'link') returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r app.campaign_recipients; d app.sender_domains;
begin
  if p_scope is null or p_scope not in ('marketing', 'all') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope'; end if;
  if p_method is null or p_method not in ('link', 'one_click') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'method'; end if;
  select * into r from app.campaign_recipients where unsub_token_sha256 = app.token_hash(p_token) for update;
  if not found or coalesce(p_token, '') = '' then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  perform app.campaign_unsubscribe(r, p_scope, p_method);
  select d2.* into d from app.campaigns c join app.sender_domains d2 on d2.id = c.sender_domain_id where c.id = r.campaign_id;
  return jsonb_build_object('unsubscribed', true, 'from_name', d.from_name);
end $fn$;

-- provider webhooks (idempotent on the provider's event id). An event that names no recipient of a campaign — the
-- survey-invitation stream, a test send — is counted as unknown and never stored (D-19, D-34).
-- Each item: {event_id, kind, message_id | token, at, bounce_kind, smtp_code, link_token | url, client_class, city, country}
create function public.worker_email_events(p_batch jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  e jsonb; r app.campaign_recipients; c app.campaigns; p app.people; v_kind text; v_at timestamptz; v_class text; v_link uuid; v_first boolean;
  n_ok int := 0; n_dup int := 0; n_unknown int := 0; v_soft int;
begin
  if p_batch is null or jsonb_typeof(p_batch) <> 'array' or jsonb_array_length(p_batch) > 1000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'batch';
  end if;
  for e in select value from jsonb_array_elements(p_batch) loop
    v_kind := e ->> 'kind';
    if jsonb_typeof(e) <> 'object' or v_kind is null or v_kind not in ('sent', 'delivered', 'bounced', 'opened', 'clicked', 'unsubscribed', 'complained') then
      n_unknown := n_unknown + 1; continue;
    end if;
    r := null;
    if e ->> 'message_id' is not null then
      select * into r from app.campaign_recipients where provider_message_id = e ->> 'message_id' for update;
    elsif e ->> 'token' is not null then
      select * into r from app.campaign_recipients where unsub_token_sha256 = app.token_hash(e ->> 'token') for update;
    end if;
    if r.id is null then n_unknown := n_unknown + 1; continue; end if;
    if e ->> 'event_id' is not null and exists (select 1 from app.campaign_events where provider_event_id = e ->> 'event_id') then n_dup := n_dup + 1; continue; end if;
    select * into c from app.campaigns where id = r.campaign_id;
    v_at := case when coalesce(e ->> 'at', '') ~ '^\d{4}-\d\d-\d\d' then (e ->> 'at')::timestamptz else now() end;
    v_class := case when e ->> 'client_class' in ('human', 'prefetch', 'unknown') then e ->> 'client_class' else 'unknown' end;
    -- opens and clicks are not recorded at all while the campaign is not tracked (COM-06)
    if v_kind in ('opened', 'clicked') and not c.tracking then n_ok := n_ok + 1; continue; end if;
    v_link := null;
    if v_kind = 'clicked' then
      select l.id into v_link from app.campaign_links l where l.campaign_id = c.id
        and (l.token = e ->> 'link_token' or (e ->> 'link_token' is null and l.url = e ->> 'url')) limit 1;
    end if;
    v_first := false;
    if v_kind = 'clicked' and v_class <> 'prefetch' then
      v_first := not exists (select 1 from app.campaign_events x where x.recipient_id = r.id and x.kind = 'clicked' and x.client_class <> 'prefetch'
                             and x.link_id is not distinct from v_link);
    end if;
    insert into app.campaign_events (recipient_id, campaign_id, kind, bounce_kind, smtp_code, link_id, client_class, provider_event_id, at)
    values (r.id, r.campaign_id, v_kind, case when v_kind = 'bounced' then case when e ->> 'bounce_kind' = 'soft' then 'soft' else 'hard' end end,
            case when coalesce(e ->> 'smtp_code', '') ~ '^[245]\d\d$' then e ->> 'smtp_code' end, v_link, v_class, left(e ->> 'event_id', 200), v_at);
    case v_kind
      when 'sent' then
        update app.campaign_recipients set state = case when state = 'queued' then 'sent' else state end, sent_at = coalesce(sent_at, v_at), claimed_at = null where id = r.id;
        perform app.campaign_finish(c.id);
      when 'delivered' then
        update app.campaign_recipients set delivered_at = coalesce(delivered_at, v_at), sent_at = coalesce(sent_at, v_at),
          state = case when state in ('queued', 'sent', 'soft_bounced') then 'delivered' else state end where id = r.id;
        if r.delivered_at is null and r.person_id is not null then
          perform app.emit('campaign.delivered', 'person', r.person_id, jsonb_build_object('campaign', c.id), c.is_sample);
        end if;
      when 'bounced' then
        if coalesce(e ->> 'bounce_kind', 'hard') = 'soft' then
          update app.campaign_recipients set bounced_at = v_at, bounce_kind = 'soft',
            state = case when state in ('queued', 'sent') then 'soft_bounced' else state end where id = r.id;
          -- five soft bounces since the last delivery to the person count as a hard one (CMP-06 RU)
          select count(*) into v_soft from app.campaign_recipients x where x.person_id = r.person_id and x.state = 'soft_bounced'
            and x.bounced_at > coalesce((select max(y.delivered_at) from app.campaign_recipients y where y.person_id = r.person_id), '-infinity');
          if r.person_id is not null and v_soft >= 5 then
            perform app.campaign_address_down(r, 'soft_bounces', 'soft_bounces');
          end if;
        else
          update app.campaign_recipients set bounced_at = v_at, bounce_kind = 'hard', state = 'bounced' where id = r.id;
          perform app.campaign_address_down(r, 'hard_bounce', case when coalesce(e ->> 'smtp_code', '') ~ '^[245]\d\d$' then e ->> 'smtp_code' end);
        end if;
        if r.person_id is not null then
          perform app.emit('campaign.bounced', 'person', r.person_id,
                           jsonb_build_object('campaign', c.id, 'bounce_kind', case when e ->> 'bounce_kind' = 'soft' then 'soft' else 'hard' end), c.is_sample);
        end if;
      when 'opened', 'clicked' then
        if v_class <> 'prefetch' then
          update app.campaign_recipients set
            opens = opens + case when v_kind = 'opened' then 1 else 0 end,
            first_open_at = case when v_kind = 'opened' then coalesce(first_open_at, v_at) else first_open_at end,
            last_open_at = case when v_kind = 'opened' then greatest(last_open_at, v_at) else last_open_at end,
            clicks = clicks + case when v_kind = 'clicked' then 1 else 0 end,
            first_click_at = case when v_kind = 'clicked' then coalesce(first_click_at, v_at) else first_click_at end,
            last_click_at = case when v_kind = 'clicked' then greatest(last_click_at, v_at) else last_click_at end,
            -- the provider's geo of the first human open (never an IP)
            city = case when v_kind = 'opened' and first_open_at is null and city is null then left(nullif(btrim(e ->> 'city'), ''), 80) else city end,
            country = case when v_kind = 'opened' and first_open_at is null and country is null and e ->> 'country' ~ '^[A-Z]{2}$' then e ->> 'country' else country end
          where id = r.id;
          if r.person_id is not null and ((v_kind = 'opened' and r.first_open_at is null) or v_first) then
            perform app.emit('campaign.' || v_kind, 'person', r.person_id,
                             jsonb_build_object('campaign', c.id) || case when v_link is not null then jsonb_build_object('link', v_link) else '{}'::jsonb end, c.is_sample);
          end if;
          -- the owner hears of a person's first engagement with a campaign that asks for it
          if c.notify_owners and r.first_open_at is null and r.first_click_at is null and r.person_id is not null then
            select * into p from app.people where id = r.person_id and deleted_at is null;
            if p.owner_id is not null then
              perform app.notify(p.owner_id, 'system', 'campaign.engaged', jsonb_build_object('campaign', c.name, 'person', p.name, 'kind', v_kind),
                                 app.entity_route('person'), 'person', p.id);
            end if;
          end if;
        end if;
      when 'unsubscribed' then
        perform app.campaign_unsubscribe(r, 'marketing', 'provider');
      when 'complained' then
        update app.campaign_recipients set complained_at = coalesce(complained_at, v_at), state = 'complained' where id = r.id;
        if r.email is not null then
          insert into app.suppressions (email_sha256, scope, reason, campaign_id) values (app.email_hash(r.email), 'marketing', 'complaint', c.id) on conflict do nothing;
        end if;
        select * into p from app.people where id = r.person_id and deleted_at is null;
        if p.id is not null and p.marketing_status not in ('unsubscribed', 'bounced') then
          perform app.consent_write(p.id, 'unsubscribed', 'complaint', null, 'campaign', c.id, null, 'complaint', 'system');
        end if;
        if r.complained_at is null and r.person_id is not null then
          perform app.emit('campaign.complained', 'person', r.person_id, jsonb_build_object('campaign', c.id), c.is_sample);
        end if;
    end case;
    n_ok := n_ok + 1;
  end loop;
  return jsonb_build_object('processed', n_ok, 'duplicates', n_dup, 'unknown', n_unknown);
end $fn$;

-- retention (D-24, §10): provider events 13 months; the recipients' rollup stays
create function app.campaign_prune() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare n int;
begin
  delete from app.campaign_events where at < now() - interval '13 months';
  get diagnostics n = row_count;
  return n;
end $fn$;
select cron.schedule('platform-campaign-prune', '44 3 * * *', 'select app.campaign_prune()');

-- ---------------------------------------------------------------------------
-- marketing templates (CMP-02): layouts (configured), shared and private templates; every save is a version
create function public.marketing_templates_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('campaigns');
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'layout', t.layout, 'category', t.category, 'scope', t.scope, 'subject', t.subject,
                                               'design', t.design, 'html', t.html, 'current_version', t.current_version, 'version', t.version, 'updated_at', t.updated_at,
                                               'owner', (select a.name from app.admins a where a.id = t.owner_id), 'mine', t.owner_id = v_me)
                            order by t.layout desc, t.name), '[]'::jsonb) into v_rows
  from app.email_templates t where t.kind = 'marketing' and t.deleted_at is null and (t.layout or t.scope = 'shared' or t.owner_id = v_me) and (v_sandbox or not t.is_sample);
  perform app.log('record.listed', 'email_template', null, jsonb_build_object('kind', 'marketing', 'count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

create function public.marketing_template_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); t app.email_templates; v jsonb := coalesce(p_values, '{}'::jsonb); v_id uuid; v_html text; v_design jsonb;
        v_tok text; k text; v_layout boolean;
begin
  perform app.require_module('campaigns');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('name', 'scope', 'category', 'subject', 'design', 'html', 'layout') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k; end if;
  end loop;
  if p_id is not null then
    select * into t from app.email_templates where id = p_id and kind = 'marketing' and deleted_at is null for update;
    if not found or not (t.layout or t.scope = 'shared' or t.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and t.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = t.version::text; end if;
    if v ? 'layout' and (v ->> 'layout')::boolean is distinct from t.layout then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'layout'; end if;
  end if;
  v_layout := coalesce(t.layout, (v ->> 'layout')::boolean, false);
  if v_layout then perform app.require('campaigns', 'configure');
  elsif t.id is not null and t.owner_id is distinct from v_me then perform app.require('campaigns', 'edit_others'); end if;
  if coalesce(btrim(coalesce(v ->> 'name', t.name)), '') = '' or char_length(btrim(coalesce(v ->> 'name', t.name))) > 120 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name';
  end if;
  if v ? 'scope' and coalesce(v ->> 'scope', '') not in ('private', 'shared') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope'; end if;
  if v ? 'category' and v ->> 'category' is not null and char_length(btrim(v ->> 'category')) not between 1 and 40 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'category';
  end if;
  if char_length(coalesce(v ->> 'subject', '')) > 500 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'subject'; end if;
  -- a template is a design (the footer fixed) or hand-written HTML carrying [Unsubscribe] (spec: invalid html.footer)
  v_html := case when v ? 'html' then nullif(v ->> 'html', '') when v ? 'design' then null else t.html end;
  v_design := case when v_html is not null then null when v ? 'design' then v -> 'design'
                   else coalesce(t.design, '{"rows":[{"kind":"header","bg":"card"},{"kind":"footer","bg":"cream"}]}'::jsonb) end;
  if v_html is not null then perform app.campaign_html_check(v_html); else perform app.campaign_design_check(v_design); end if;
  v_tok := app.campaign_unknown_token(concat_ws(' ', coalesce(v ->> 'subject', t.subject), v_html, v_design::text));
  if v_tok is not null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || v_tok; end if;
  if p_id is null then
    insert into app.email_templates (name, scope, owner_id, subject, kind, layout, design, html, category, is_starter, is_sample)
    values (btrim(v ->> 'name'), coalesce(v ->> 'scope', case when v_layout then 'shared' else 'private' end), case when not v_layout then v_me end,
            coalesce(v ->> 'subject', ''), 'marketing', v_layout, v_design, v_html, nullif(btrim(v ->> 'category'), ''), v_layout,
            (select sandbox from app.admins where id = v_me))
    returning * into t;
  else
    update app.email_templates set name = coalesce(btrim(v ->> 'name'), name), scope = coalesce(v ->> 'scope', scope), subject = coalesce(v ->> 'subject', subject),
      design = v_design, html = v_html, category = case when v ? 'category' then nullif(btrim(v ->> 'category'), '') else category end,
      current_version = current_version + 1, version = version + 1, updated_at = now()
    where id = p_id returning * into t;
  end if;
  insert into app.email_template_versions (template_id, version, subject, body, design, html, created_by)
  values (t.id, t.current_version, t.subject, t.body, t.design, t.html, v_me);
  perform app.log(case when p_id is null then 'template.created' else 'template.updated' end, 'email_template', t.id::text,
                  jsonb_build_object('kind', 'marketing', 'version', t.current_version, 'layout', t.layout));
  return jsonb_build_object('id', t.id, 'version', t.version, 'current_version', t.current_version);
end $fn$;

create function public.marketing_template_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'delete'); t app.email_templates;
begin
  perform app.require_module('campaigns');
  select * into t from app.email_templates where id = p_id and kind = 'marketing' and deleted_at is null for update;
  if not found or not (t.layout or t.scope = 'shared' or t.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.layout then perform app.require('campaigns', 'configure');
  elsif t.owner_id is distinct from v_me then perform app.require('campaigns', 'edit_others'); end if;
  update app.email_templates set deleted_at = now(), updated_at = now() where id = p_id;
  perform app.log('template.deleted', 'email_template', p_id::text, jsonb_build_object('kind', 'marketing'));
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
-- segments and audience (CMP-03, CMP-04)
create function public.segment_count(p_query jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see');
begin
  perform app.require_module('campaigns');
  return app.segment_counts(p_query, (select sandbox from app.admins where id = v_me));
end $fn$;

create function public.segments_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('campaigns');
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'description', s.description, 'query', s.query, 'shared', s.shared,
                                               'mine', s.owner_id = v_me, 'owner', (select a.name from app.admins a where a.id = s.owner_id), 'updated_at', s.updated_at)
                            || app.segment_counts(s.query, v_sandbox) order by s.ord, s.name), '[]'::jsonb) into v_rows
  from app.saved_views s where s.kind = 'segment' and (s.shared or s.owner_id = v_me);
  perform app.log('record.listed', 'segment', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

-- a segment is a shared saved view of people; usable as a campaign audience
create function public.segment_save(p_id uuid, p_name text, p_query jsonb, p_description text default null, p_shared boolean default true) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'add'); s app.saved_views; v_id uuid; v_counts jsonb;
begin
  perform app.require_module('campaigns');
  if coalesce(btrim(p_name), '') = '' or char_length(btrim(p_name)) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if char_length(coalesce(p_description, '')) > 300 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'description'; end if;
  -- the query must run: an unknown field or operator is refused with its own detail (filter.<field>)
  v_counts := app.segment_counts(coalesce(p_query, '{}'::jsonb), (select sandbox from app.admins where id = v_me));
  if p_id is null then
    insert into app.saved_views (screen, kind, name, query, owner_id, shared, description)
    values ('people', 'segment', btrim(p_name), coalesce(p_query, '{}'::jsonb), v_me, coalesce(p_shared, true), nullif(btrim(p_description), ''))
    returning id into v_id;
  else
    select * into s from app.saved_views where id = p_id and kind = 'segment' for update;
    if not found or not (s.shared or s.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if s.owner_id is distinct from v_me then perform app.require('campaigns', 'edit_others'); end if;
    update app.saved_views set name = btrim(p_name), query = coalesce(p_query, query), shared = coalesce(p_shared, shared),
      description = nullif(btrim(p_description), ''), updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  perform app.log(case when p_id is null then 'segment.created' else 'segment.updated' end, 'segment', v_id::text, v_counts);
  return jsonb_build_object('id', v_id) || v_counts;
end $fn$;

-- a segment a scheduled campaign still has to resolve cannot be deleted
create function public.segment_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'delete'); s app.saved_views;
begin
  perform app.require_module('campaigns');
  select * into s from app.saved_views where id = p_id and kind = 'segment' for update;
  if not found or not (s.shared or s.owner_id = v_me) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if s.owner_id is distinct from v_me then perform app.require('campaigns', 'edit_others'); end if;
  if exists (select 1 from app.campaigns c where c.segment_id = p_id and c.status = 'scheduled' and c.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'in_use';
  end if;
  delete from app.saved_views where id = p_id;
  perform app.log('segment.deleted', 'segment', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- list hygiene (CMP-04): subscribed people with no human open or click in list_hygiene months who were sent a
-- campaign in that window. The setting is the consumer's: off → no candidates; custom → 6..24 months.
create function app.hygiene_months() returns int
  language sql stable security definer set search_path = ''
as $fn$
  select case app.setting('list_hygiene') when 'off' then null
              when 'custom' then greatest(6, least(24, coalesce((select value_number from app.setting_values where key = 'list_hygiene' and scope_id = ''), 12)))::int
              else 12 end
$fn$;

create function app.hygiene_ids() returns setof uuid
  language sql stable security definer set search_path = ''
as $fn$
  select p.id from app.people p, (select app.hygiene_months() m) h
  where h.m is not null and p.marketing_status = 'subscribed' and p.email is not null and p.deleted_at is null and not p.is_sample
    and app.visible(p.owner_id, p.visibility)
    and exists (select 1 from app.campaign_recipients r where r.person_id = p.id and r.sent_at > now() - make_interval(months => h.m))
    and not exists (select 1 from app.campaign_recipients r where r.person_id = p.id
                    and greatest(r.last_open_at, r.last_click_at) > now() - make_interval(months => h.m))
$fn$;

create function public.hygiene_candidates() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_m int := app.hygiene_months(); v_ids uuid[];
begin
  perform app.require_module('campaigns');
  v_ids := array(select app.hygiene_ids());
  perform app.log('record.listed', 'person', null, jsonb_build_object('hygiene', coalesce(cardinality(v_ids), 0)));
  return jsonb_build_object('enabled', v_m is not null, 'months', v_m, 'count', case when v_m is not null then cardinality(v_ids) end,
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email) order by p.name)
                        from (select * from app.people where id = any (v_ids) order by name limit 50) p), '[]'::jsonb));
end $fn$;

-- archiving is a staff action (campaigns:bulk), never automatic; refused when the count changed since it was shown
create function public.hygiene_archive(p_expected int) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'bulk'); v_ids uuid[]; x uuid;
begin
  perform app.require_module('campaigns');
  if app.hygiene_months() is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'list_hygiene'; end if;
  v_ids := array(select app.hygiene_ids());
  if p_expected is distinct from cardinality(v_ids) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'expected'; end if;
  foreach x in array v_ids loop
    perform app.consent_write(x, 'archived', 'list_hygiene', null, 'list_hygiene', null, null, null, 'ui');
  end loop;
  perform app.log('hygiene.archived', 'person', null, jsonb_build_object('count', cardinality(v_ids), 'months', app.hygiene_months()));
  return jsonb_build_object('archived', cardinality(v_ids));
end $fn$;

-- ---------------------------------------------------------------------------
-- deliverability (CMP-08)
create function app.sender_domain_row(d app.sender_domains) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', d.id, 'domain', d.domain, 'stream', d.stream, 'sends_here', d.sends_here, 'product', d.product, 'from_name', d.from_name,
    'from_local', d.from_local, 'reply_to', d.reply_to, 'postal_address', d.postal_address, 'spf_ok', d.spf_ok, 'dkim_ok', d.dkim_ok, 'dmarc_policy', d.dmarc_policy,
    'verified_at', d.verified_at, 'authenticated', app.domain_authenticated(d), 'verified', app.domain_verified(d), 'last_checked_at', d.last_checked_at,
    'check_detail', d.check_detail, 'version', d.version,
    'warmup', case when d.warmup_started_at is not null then jsonb_build_object('day', current_date - d.warmup_started_at + 1, 'days', d.warmup_days,
                                                                               'done', current_date - d.warmup_started_at + 1 > d.warmup_days) end,
    -- last 30 days, only where this platform sends (Q6): a domain another system sends from shows no rates
    'rates', case when d.sends_here then (
      select jsonb_build_object('sent', count(*) filter (where r.state not in ('queued', 'skipped')), 'delivered', count(r.delivered_at),
                                'bounce_rate', app.pct(count(*) filter (where r.state in ('bounced', 'soft_bounced')), count(*) filter (where r.state not in ('queued', 'skipped'))),
                                'complaint_rate', app.pct(count(r.complained_at), count(r.delivered_at)))
      from app.campaign_recipients r join app.campaigns c on c.id = r.campaign_id
      where c.sender_domain_id = d.id and r.sent_at > now() - interval '30 days' and not r.is_sample) end)
$fn$;

create function public.sender_domains_get() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); v_rows jsonb;
begin
  perform app.require_module('campaigns');
  select coalesce(jsonb_agg(app.sender_domain_row(d) order by d.stream, d.domain), '[]'::jsonb) into v_rows from app.sender_domains d where d.deleted_at is null;
  perform app.log('record.listed', 'sender_domain', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'provider_connected', app.connected('email'));
end $fn$;

-- a domain's identity (from name, local part, reply-to, postal address), stream and warm-up; the name of the domain
-- is fixed once created (its checks belong to it). The checks themselves come only from the workers.
create function public.sender_domain_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); d app.sender_domains; v jsonb := coalesce(p_values, '{}'::jsonb); k text; v_id uuid;
begin
  perform app.require_module('campaigns');
  if jsonb_typeof(v) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  for k in select jsonb_object_keys(v) loop
    if k not in ('domain', 'stream', 'sends_here', 'product', 'from_name', 'from_local', 'reply_to', 'postal_address', 'warmup_started_at', 'warmup_days') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = k;
    end if;
  end loop;
  if p_id is not null then
    select * into d from app.sender_domains where id = p_id and deleted_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if p_version is not null and d.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = d.version::text; end if;
    if v ? 'domain' and lower(btrim(v ->> 'domain')) is distinct from d.domain then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'domain'; end if;
  elsif coalesce(lower(btrim(v ->> 'domain')), '') !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$'
        or exists (select 1 from app.sender_domains x where x.domain = lower(btrim(v ->> 'domain')) and x.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'domain';
  end if;
  if coalesce(v ->> 'stream', d.stream, '') not in ('marketing', 'transactional') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stream'; end if;
  if v ? 'sends_here' and jsonb_typeof(v -> 'sends_here') <> 'boolean' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'sends_here'; end if;
  if coalesce(btrim(coalesce(v ->> 'from_name', d.from_name)), '') = '' or char_length(btrim(coalesce(v ->> 'from_name', d.from_name))) > 120 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'from_name';
  end if;
  if v ? 'from_local' and coalesce(v ->> 'from_local', '') !~ '^[a-z0-9._-]{1,40}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'from_local'; end if;
  if v ? 'reply_to' and v ->> 'reply_to' is not null and (char_length(v ->> 'reply_to') > 254 or v ->> 'reply_to' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'reply_to';
  end if;
  if v ? 'postal_address' and v ->> 'postal_address' is not null and char_length(btrim(v ->> 'postal_address')) not between 1 and 300 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'postal_address';
  end if;
  if v ? 'product' and v ->> 'product' is not null and not exists (select 1 from app.products p where p.key = v ->> 'product') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'product';
  end if;
  if v ? 'warmup_days' and (jsonb_typeof(v -> 'warmup_days') <> 'number' or (v ->> 'warmup_days')::numeric not between 0 and 120) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'warmup_days';
  end if;
  if v ? 'warmup_started_at' and v ->> 'warmup_started_at' is not null and coalesce(v ->> 'warmup_started_at', '') !~ '^\d{4}-\d\d-\d\d$' then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'warmup_started_at';
  end if;
  if p_id is null then
    insert into app.sender_domains (domain, stream, sends_here, product, from_name, from_local, reply_to, postal_address, warmup_started_at, warmup_days, created_by)
    values (lower(btrim(v ->> 'domain')), v ->> 'stream', coalesce((v ->> 'sends_here')::boolean, true), v ->> 'product', btrim(v ->> 'from_name'),
            coalesce(v ->> 'from_local', 'news'), v ->> 'reply_to', nullif(btrim(v ->> 'postal_address'), ''), (v ->> 'warmup_started_at')::date,
            coalesce((v ->> 'warmup_days')::int, 30), v_me)
    returning id into v_id;
    -- the DNS check runs at once (no key needed)
    perform pgmq.send('jobs', jsonb_build_object('job', 'dns_check', 'sender_domain_id', v_id));
  else
    update app.sender_domains set stream = coalesce(v ->> 'stream', stream), sends_here = coalesce((v ->> 'sends_here')::boolean, sends_here),
      product = case when v ? 'product' then v ->> 'product' else product end, from_name = coalesce(btrim(v ->> 'from_name'), from_name),
      from_local = coalesce(v ->> 'from_local', from_local), reply_to = case when v ? 'reply_to' then v ->> 'reply_to' else reply_to end,
      postal_address = case when v ? 'postal_address' then nullif(btrim(v ->> 'postal_address'), '') else postal_address end,
      warmup_started_at = case when v ? 'warmup_started_at' then (v ->> 'warmup_started_at')::date else warmup_started_at end,
      warmup_days = coalesce((v ->> 'warmup_days')::int, warmup_days), version = version + 1, updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  perform app.log(case when p_id is null then 'sender_domain.created' else 'sender_domain.updated' end, 'sender_domain', v_id::text,
                  jsonb_build_object('fields', (select jsonb_agg(x) from jsonb_object_keys(v) x)));
  return app.sender_domain_row((select x from app.sender_domains x where x.id = v_id));
end $fn$;

-- a domain a scheduled or running campaign sends from cannot be removed
create function public.sender_domain_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure');
begin
  perform app.require_module('campaigns');
  if not exists (select 1 from app.sender_domains where id = p_id and deleted_at is null) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if exists (select 1 from app.campaigns c where c.sender_domain_id = p_id and c.status in ('scheduled', 'sending', 'active', 'paused') and c.deleted_at is null) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'in_use';
  end if;
  update app.sender_domains set deleted_at = now(), updated_at = now(), version = version + 1 where id = p_id;
  perform app.log('sender_domain.deleted', 'sender_domain', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- «Re-check DNS» queues the checks; the rows change when the worker reports
create function public.sender_domain_recheck(p_id uuid default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); x uuid; n int := 0;
begin
  perform app.require_module('campaigns');
  if p_id is not null and not exists (select 1 from app.sender_domains where id = p_id and deleted_at is null) then
    raise exception 'not_found' using errcode = 'no_data_found';
  end if;
  for x in select id from app.sender_domains where deleted_at is null and (p_id is null or id = p_id) loop
    perform pgmq.send('jobs', jsonb_build_object('job', 'dns_check', 'sender_domain_id', x));
    n := n + 1;
  end loop;
  perform app.log('sender_domain.recheck', 'sender_domain', p_id::text, jsonb_build_object('queued', n));
  return jsonb_build_object('queued', n);
end $fn$;

-- nightly: every domain is checked again
create function app.sender_domains_check_all() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare x uuid; n int := 0;
begin
  for x in select id from app.sender_domains where deleted_at is null loop
    perform pgmq.send('jobs', jsonb_build_object('job', 'dns_check', 'sender_domain_id', x)); n := n + 1;
  end loop;
  return n;
end $fn$;
select cron.schedule('platform-dns-check', '13 2 * * *', 'select app.sender_domains_check_all()');

-- the DNS-check worker (DNS over HTTPS) and the provider's domain verification report here. «verified» counts only
-- while the provider is connected: without it a domain is never shown verified.
-- p_checks: {spf_ok, dkim_ok, dmarc_policy, verified?, provider_domain_id?, detail?}
create function public.worker_sender_domain_status(p_id uuid, p_checks jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare d app.sender_domains;
begin
  if p_checks is null or jsonb_typeof(p_checks) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'checks'; end if;
  if p_checks ? 'dmarc_policy' and p_checks ->> 'dmarc_policy' is not null and p_checks ->> 'dmarc_policy' not in ('none', 'quarantine', 'reject') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'dmarc_policy';
  end if;
  if (p_checks ? 'detail' and jsonb_typeof(p_checks -> 'detail') <> 'object') or char_length(coalesce((p_checks -> 'detail')::text, '')) > 4000 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'detail';
  end if;
  update app.sender_domains set
    spf_ok = case when p_checks ? 'spf_ok' then (p_checks ->> 'spf_ok')::boolean else spf_ok end,
    dkim_ok = case when p_checks ? 'dkim_ok' then (p_checks ->> 'dkim_ok')::boolean else dkim_ok end,
    dmarc_policy = case when p_checks ? 'dmarc_policy' then p_checks ->> 'dmarc_policy' else dmarc_policy end,
    verified_at = case when not app.connected('email') then null
                       when p_checks ? 'verified' then case when (p_checks ->> 'verified')::boolean then coalesce(verified_at, now()) end
                       else verified_at end,
    provider_domain_id = case when p_checks ? 'provider_domain_id' then left(p_checks ->> 'provider_domain_id', 200) else provider_domain_id end,
    check_detail = coalesce(p_checks -> 'detail', check_detail), last_checked_at = now(), updated_at = now()
  where id = p_id and deleted_at is null returning * into d;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('authenticated', app.domain_authenticated(d), 'verified', app.domain_verified(d));
end $fn$;

-- the recommendations (computed, never canned): missing DNS records and high bounce rates per sending domain, the
-- hygiene candidates, and the sender-identity check (true by construction for templates; it names any marketing
-- domain without a postal address, since every footer prints it)
create function public.deliverability_recommendations() returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'see'); d app.sender_domains; v_rows jsonb := '[]'::jsonb; v_rate numeric; v_h int; v_missing jsonb;
begin
  perform app.require_module('campaigns');
  for d in select * from app.sender_domains where deleted_at is null order by stream, domain loop
    if not coalesce(d.spf_ok, false) or not coalesce(d.dkim_ok, false) or d.dmarc_policy is null then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('kind', 'dns_missing', 'level', 'high', 'domain', d.domain,
        'records', to_jsonb(array_remove(array[case when not coalesce(d.spf_ok, false) then 'spf' end, case when not coalesce(d.dkim_ok, false) then 'dkim' end,
                                               case when d.dmarc_policy is null then 'dmarc' end], null))));
    elsif d.dmarc_policy = 'none' then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('kind', 'dmarc_none', 'level', 'medium', 'domain', d.domain));
    end if;
    if d.sends_here then
      v_rate := (app.sender_domain_row(d) -> 'rates' ->> 'bounce_rate')::numeric;
      if v_rate > 3 then v_rows := v_rows || jsonb_build_array(jsonb_build_object('kind', 'bounce_rate', 'level', 'high', 'domain', d.domain, 'rate', v_rate)); end if;
    end if;
  end loop;
  if app.hygiene_months() is not null then
    v_h := (select count(*) from app.hygiene_ids());
    if v_h > 0 then v_rows := v_rows || jsonb_build_array(jsonb_build_object('kind', 'hygiene', 'level', 'medium', 'count', v_h, 'months', app.hygiene_months())); end if;
  end if;
  v_missing := coalesce((select jsonb_agg(x.domain order by x.domain) from app.sender_domains x
                         where x.deleted_at is null and x.stream = 'marketing' and x.sends_here and x.postal_address is null), '[]'::jsonb);
  v_rows := v_rows || jsonb_build_array(jsonb_build_object('kind', 'identity', 'level', case when jsonb_array_length(v_missing) = 0 then 'ok' else 'high' end,
                                                           'ok', jsonb_array_length(v_missing) = 0, 'domains_missing_address', v_missing));
  perform app.log('record.listed', 'sender_domain', null, jsonb_build_object('recommendations', jsonb_array_length(v_rows)));
  return v_rows;
end $fn$;

-- ---------------------------------------------------------------------------
-- existing functions, redefined with their full bodies (never edit an applied migration)
-- merge values learn the campaign's coupon (0032's body otherwise unchanged)
CREATE OR REPLACE FUNCTION app.merge_value(p_token text, p_ctx jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f app.merge_fields; v text; src text; col text; v_cur text;
begin
  select * into f from app.merge_fields where token = p_token;
  if not found or f.format = 'block' then return null; end if;
  src := split_part(f.source_path, '.', 1); col := split_part(f.source_path, '.', 2);
  v := case src
    when 'person' then (select case col when 'name' then p.name when 'email' then p.email end from app.people p where p.id = (p_ctx ->> 'person')::uuid)
    when 'organization' then (select case col when 'name' then o.name when 'employees' then o.employees::text when 'org_number' then o.org_number
                                              when 'address' then o.address when 'postal_code' then o.postal_code when 'city' then o.city end
                              from app.organizations o where o.id = (p_ctx ->> 'organization')::uuid)
    when 'deal' then (select case col when 'title' then d.title when 'value' then d.value::text when 'currency' then d.currency
                                      when 'stage' then (select s.name from app.stages s where s.id = d.stage_id) end
                      from app.deals d where d.id = (p_ctx ->> 'deal')::uuid)
    when 'staff' then (select case col when 'name' then a.name
                                       when 'booking_link' then (select b.slug from app.booking_links b where b.staff_id = a.id and b.kind = 'general' order by b.id limit 1) end
                       from app.admins a where a.id = (p_ctx ->> 'staff')::uuid)
    when 'mailbox' then (select m.signature from app.mailboxes m where m.id = (p_ctx ->> 'mailbox')::uuid)
    when 'document' then (select case col when 'number' then x.number when 'created_at' then (x.created_at at time zone 'Europe/Oslo')::date::text
                                          when 'valid_until' then x.valid_until::text end
                          from app.documents x where x.id = (p_ctx ->> 'document')::uuid)
    -- a promotion's coupon (0037): [Kampanje.kode]
    when 'campaign' then (select case col when 'coupon_code' then x.coupon_code end from app.campaigns x where x.id = (p_ctx ->> 'campaign')::uuid)
  end;
  if v is null or btrim(v) = '' then return null; end if;
  if f.format = 'nok' and src = 'deal' then
    select d.currency into v_cur from app.deals d where d.id = (p_ctx ->> 'deal')::uuid;
  end if;
  return case f.format
    when 'first_word' then split_part(btrim(v), ' ', 1)
    when 'nok' then replace(to_char(round(v::numeric), 'FM999G999G999G990'), ',', ' ') || case when coalesce(v_cur, 'NOK') = 'NOK' then ' kr' else ' ' || v_cur end
    when 'url' then 'booking:' || v            -- the app turns a booking slug into the public link (D-28 host)
    when 'orgnr' then case when v ~ '^\d{9}$' then substr(v, 1, 3) || ' ' || substr(v, 4, 3) || ' ' || substr(v, 7, 3) else v end
    when 'date' then app.doc_date(v::date, coalesce(p_ctx ->> 'language', 'nb'))
    else v end;
end $function$;

-- the people filter learns the audience fields (0034's body otherwise unchanged)
CREATE OR REPLACE FUNCTION app.filter_sql(e app.entities, p_filters jsonb)
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

-- workflow validation: campaign_action names an automated campaign; an email step names a sales template
CREATE OR REPLACE FUNCTION app.wf_validate(p_kind text, p_graph jsonb, p_entity text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s record; v_keys text[] := '{}'; c jsonb; k text; v_limit numeric := app.count_limit(); pc jsonb; x jsonb;
begin
  if p_kind = 'assignment' then return; end if;
  if jsonb_typeof(p_graph -> 'steps') <> 'array' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.steps'; end if;
  for s in with recursive w(step) as (
             select e1.value from jsonb_array_elements(p_graph -> 'steps') e1
             union all
             select e2.value from w, jsonb_array_elements(coalesce(w.step -> 'then', '[]'::jsonb) || coalesce(w.step -> 'else', '[]'::jsonb)) e2)
           select step from w loop
    k := s.step ->> 'key'; c := coalesce(s.step -> 'config', '{}'::jsonb);
    if k is null or k !~ '^[a-z0-9_]{1,24}$' or k = any (v_keys) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.key'; end if;
    v_keys := v_keys || k;
    if not ((s.step ->> 'kind') = any (app.wf_kinds(p_kind))) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.kind'; end if;
    case s.step ->> 'kind'
      when 'condition', 'if_else' then
        if jsonb_typeof(c -> 'groups') <> 'array' or jsonb_array_length(c -> 'groups') = 0 then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.groups';
        end if;
      when 'delay' then
        if coalesce((c ->> 'amount')::numeric, -1) < 0 or coalesce(c ->> 'unit', 'days') not in ('minutes', 'hours', 'days') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.amount';
        end if;
      when 'wait_for' then
        if c ->> 'event' not in ('email.replied', 'email.opened', 'email.clicked', 'deal.stage_changed', 'deal.won', 'deal.lost', 'activity.completed')
           or coalesce((c ->> 'timeout_days')::numeric, 7) not between 1 and 365 or coalesce(c ->> 'then', 'continue') not in ('continue', 'stop') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.event';
        end if;
      when 'update_record' then
        if jsonb_typeof(c -> 'values') <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.values'; end if;
        for x in select to_jsonb(kk) from jsonb_object_keys(c -> 'values') kk loop
          if x #>> '{}' not in ('owner_id', 'labels', 'custom') and not exists (select 1 from app.entity_columns ec where ec.entity = p_entity and ec.col = x #>> '{}' and ec.writable) then
            raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.values.' || (x #>> '{}');
          end if;
        end loop;
      when 'create_record' then
        if c ->> 'entity' not in ('deal', 'lead', 'person', 'organization') or jsonb_typeof(c -> 'values') <> 'object' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.entity';
        end if;
      when 'create_activity', 'activity' then
        if not exists (select 1 from app.activity_types t where t.key = coalesce(c ->> 'type', 'task') and t.active) or coalesce(btrim(c ->> 'subject'), '') = '' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.subject';
        end if;
      when 'add_note' then
        if coalesce(btrim(c ->> 'body'), '') = '' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.body'; end if;
      when 'notify' then
        if coalesce(btrim(c ->> 'message'), '') = '' or char_length(c ->> 'message') > 500 then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.message';
        end if;
      when 'send_email', 'email_auto', 'email_manual' then
        if not exists (select 1 from app.email_templates t where t.id::text = c ->> 'template_id' and t.kind = 'sales' and t.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.template_id';
        end if;
      when 'enroll_sequence' then
        if not exists (select 1 from app.workflows w where w.id::text = c ->> 'sequence_id' and w.kind = 'sequence' and w.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.sequence_id';
        end if;
      when 'create_ticket' then
        if not exists (select 1 from app.ticket_categories t where t.key = c ->> 'category_key' and t.active) or coalesce(btrim(c ->> 'subject'), '') = '' then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.category_key';
        end if;
      when 'webhook' then
        if not app.url_public(c ->> 'url') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.url'; end if;
        if coalesce(c ->> 'method', 'POST') not in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE') then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.method';
        end if;
        if char_length(coalesce(c ->> 'body', '')) > 20000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.body'; end if;
      when 'campaign_action' then
        -- CMP-07, AUT-07: an automated campaign; the workflow's author needs Campaigns › workflows
        perform app.require('campaigns', 'workflows');
        if not exists (select 1 from app.campaigns x where x.id::text = c ->> 'campaign_id' and x.type = 'automated' and x.deleted_at is null) then
          raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.' || k || '.campaign_id';
        end if;
      else null;
    end case;
  end loop;
  if cardinality(v_keys) = 0 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.steps'; end if;
  if v_limit is not null then
    pc := app.wf_path_counts(p_graph -> 'steps');
    if (pc ->> 'actions')::int > v_limit or (pc ->> 'delays')::int > v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'graph.limit';
    end if;
  end if;
end $function$;

-- what a workflow with a campaign step still lacks (replaces not_available:campaigns)
CREATE OR REPLACE FUNCTION app.wf_blockers(p_wf uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct b) filter (where b is not null), '{}') from (
    select case
      when n.v ->> 'kind' = 'slack' and not exists (select 1 from app.integration_connections c where c.provider = 'slack' and c.status = 'connected') then 'not_connected:slack'
      when n.v ->> 'kind' = 'teams' and not exists (select 1 from app.integration_connections c where c.provider = 'teams' and c.status = 'connected') then 'not_connected:teams'
      when n.v ->> 'kind' = 'accounting_invoice' and not exists (select 1 from app.integration_connections c where c.provider = 'accounting' and c.status = 'connected') then 'not_connected:accounting'
      -- campaign_action (0037): the provider, an automated campaign that is switched on, a verified sender domain
      when n.v ->> 'kind' = 'campaign_action' and not app.connected('email') then 'not_connected:email'
      when n.v ->> 'kind' = 'campaign_action'
           and not exists (select 1 from app.campaigns c where c.id::text = n.v -> 'config' ->> 'campaign_id' and c.type = 'automated' and c.status in ('active', 'paused')
                           and c.deleted_at is null) then 'campaign_inactive'
      when n.v ->> 'kind' = 'campaign_action'
           and not exists (select 1 from app.campaigns c join app.sender_domains d on d.id = c.sender_domain_id
                           where c.id::text = n.v -> 'config' ->> 'campaign_id' and app.domain_verified(d)) then 'sender_domain_unverified'
      when n.v ->> 'kind' = 'project_action' then 'not_available:projects'
      -- a sequence that is still a draft refuses every enrollment (seq_enroll: sequence_inactive)
      when n.v ->> 'kind' = 'enroll_sequence'
           and not exists (select 1 from app.workflows s where s.id::text = n.v -> 'config' ->> 'sequence_id' and s.kind = 'sequence' and s.state = 'active' and s.deleted_at is null) then 'sequence_inactive'
      -- sending as the workflow's owner needs their mailbox; sending as the record's owner is checked per run,
      -- but at least one mailbox must be connected
      when n.v ->> 'kind' in ('send_email', 'email_auto', 'email_manual')
           and not exists (select 1 from app.mailboxes m where m.deleted_at is null and m.status in ('syncing', 'synced')
                           and (coalesce(n.v -> 'config' ->> 'from', '@record_owner') = '@record_owner'
                                or m.owner_id = w.owner_id or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = w.owner_id and mm.can_reply))) then 'mailbox_not_connected'
      end b
    from app.workflows w join app.workflow_versions v on v.workflow_id = w.id and v.version = w.current_version
    cross join lateral jsonb_each(v.flat) n(k, v)
    where w.id = p_wf and n.k <> '_start') s
$function$;

-- the executor runs campaign_action (0021's body otherwise unchanged)
CREATE OR REPLACE FUNCTION app.wf_step(p_run app.workflow_runs, p_wf app.workflows, p_key text, p_node jsonb, p_step uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c jsonb := coalesce(p_node -> 'config', '{}'::jsonb); k text := p_node ->> 'kind'; e app.entities; v jsonb := '{}'::jsonb; kk text; r jsonb; v_id uuid;
  v_owner uuid; v_mailbox uuid; v_person uuid; v_to text; v_msg uuid; v_tpl app.email_templates; v_seq uuid; v_facts jsonb; v_assignee uuid; v_title text;
  v_ref text; v_deal uuid;
begin
  if p_run.subject_type is not null then select * into e from app.entities where key = p_run.subject_type; end if;
  case k
    when 'condition' then
      if app.wf_match(p_run.subject_type, p_run.subject_id, c -> 'groups') then
        update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step;
        return coalesce(p_node ->> 'next', '');
      end if;
      update app.workflow_run_steps set state = 'not_met', finished_at = now() where id = p_step;
      return '';
    when 'if_else' then
      update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step;
      return coalesce(case when app.wf_match(p_run.subject_type, p_run.subject_id, c -> 'groups') then p_node ->> 'then' else p_node ->> 'else' end, '');
    when 'delay' then
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''),
        resume_at = app.wf_delay_until(now(), coalesce((c ->> 'amount')::numeric, 0), c ->> 'unit', (c ->> 'skip_weekends')::boolean)
      where id = p_run.id;
      update app.workflow_run_steps set state = 'succeeded', finished_at = now(), output = jsonb_build_object('until', (select resume_at from app.workflow_runs where id = p_run.id)) where id = p_step;
      return null;
    when 'wait_for' then
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = c ->> 'event',
        wait_deadline = now() + make_interval(days => coalesce((c ->> 'timeout_days')::int, 7)), wait_then = coalesce(c ->> 'then', 'continue')
      where id = p_run.id;
      update app.workflow_run_steps set state = 'waiting' where id = p_step;
      return null;
    when 'update_record' then
      for kk in select jsonb_object_keys(c -> 'values') loop
        v := v || jsonb_build_object(kk, app.wf_value(c -> 'values' -> kk, p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      end loop;
      perform public.rec_save(p_run.subject_type, p_run.subject_id, v, null, null, 'workflow');
    when 'delete_record' then
      perform public.rec_delete(p_run.subject_type, array[p_run.subject_id]);
    when 'create_record' then
      for kk in select jsonb_object_keys(c -> 'values') loop
        v := v || jsonb_build_object(kk, app.wf_value(c -> 'values' -> kk, p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      end loop;
      -- link to the subject when the new record has a column that points at the subject's type
      select col into kk from app.entity_columns where entity = c ->> 'entity' and ref = p_run.subject_type and writable order by ord limit 1;
      if kk is not null and not (v ? kk) then v := v || jsonb_build_object(kk, p_run.subject_id); end if;
      r := public.rec_save(c ->> 'entity', null, v, null, null, 'workflow');
      update app.workflow_run_steps set output = jsonb_build_object('entity', c ->> 'entity', 'id', r ->> 'id') where id = p_step;
    when 'create_activity', 'activity' then
      v := jsonb_build_object('type_id', (select t.id from app.activity_types t where t.key = coalesce(c ->> 'type', 'task')),
                              'subject', left(app.wf_render(c ->> 'subject', p_run.subject_type, p_run.subject_id), 200),
                              'starts_at', now() + make_interval(days => coalesce((c ->> 'due_in_days')::int, 0)),
                              'priority', coalesce(c ->> 'priority', 'medium'),
                              'owner_id', app.wf_value(to_jsonb(coalesce(c ->> 'owner', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id));
      if p_run.subject_type in ('deal', 'person', 'organization') then v := v || jsonb_build_object(p_run.subject_type || '_id', p_run.subject_id); end if;
      if p_run.subject_type = 'lead' then v := v || jsonb_build_object('lead_id', p_run.subject_id); end if;
      r := public.rec_save('activity', null, v, null, null, 'workflow');
      update app.activities set created_by_workflow = p_wf.id where id = (r ->> 'id')::uuid;
      update app.workflow_run_steps set output = jsonb_build_object('activity', r ->> 'id') where id = p_step;
    when 'add_note' then
      perform public.note_save(p_run.subject_type, p_run.subject_id, null, left(app.wf_render(c ->> 'body', p_run.subject_type, p_run.subject_id), 10000));
    when 'notify' then
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'to', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id)) #>> '{}';
      if e.key is not null then
        execute format('select t.%I::text from app.%I t where t.id = %L', e.title_col, e.tbl, p_run.subject_id) into v_title;
      end if;
      perform app.notify(v_owner, 'system', 'workflow.notice',
                         jsonb_build_object('workflow', p_wf.name, 'message', left(app.wf_render(c ->> 'message', p_run.subject_type, p_run.subject_id), 500), 'record', v_title),
                         app.entity_route(p_run.subject_type), p_run.subject_type, p_run.subject_id);
    when 'create_ticket' then
      v := jsonb_build_object('category_key', c ->> 'category_key', 'subject', left(app.wf_render(c ->> 'subject', p_run.subject_type, p_run.subject_id), 200));
      if p_run.subject_type = 'organization' then v := v || jsonb_build_object('organization_id', p_run.subject_id); end if;
      if p_run.subject_type = 'deal' then v := v || jsonb_build_object('organization_id', (select d.organization_id from app.deals d where d.id = p_run.subject_id)); end if;
      r := public.ticket_create(v);
      update app.workflow_run_steps set output = jsonb_build_object('ticket', r ->> 'id') where id = p_step;
    when 'assign_owner' then
      v_facts := app.assign_facts(p_run.subject_type, p_run.subject_id);
      v_assignee := app.assign_pick(c -> 'assignee', v_facts, true);
      if v_assignee is null then raise exception 'no_assignee'; end if;
      perform public.rec_save(p_run.subject_type, p_run.subject_id, jsonb_build_object('owner_id', v_assignee), null, null, 'workflow');
      perform app.notify(v_assignee, 'system', 'assignment.assigned', jsonb_build_object('workflow', p_wf.name), app.entity_route(p_run.subject_type), p_run.subject_type, p_run.subject_id);
    when 'enroll_sequence' then
      perform app.seq_enroll((c ->> 'sequence_id')::uuid, p_run.subject_type, p_run.subject_id, 'workflow', p_wf.owner_id);
    when 'send_email', 'email_auto', 'email_manual' then
      select * into v_tpl from app.email_templates where id = (c ->> 'template_id')::uuid and deleted_at is null;
      if not found then raise exception 'template_missing'; end if;
      -- the recipient: the subject person, or the deal's or lead's person
      v_person := case p_run.subject_type when 'person' then p_run.subject_id
                    when 'deal' then (select d.person_id from app.deals d where d.id = p_run.subject_id)
                    when 'lead' then (select l.person_id from app.leads l where l.id = p_run.subject_id) end;
      v_to := (select lower(p.email) from app.people p where p.id = v_person and p.deleted_at is null);
      if v_to is null then raise exception 'no_recipient'; end if;
      if app.setting('sales_consent') = 'block'
         and ((select p.marketing_status from app.people p where p.id = v_person) in ('unsubscribed', 'bounced')
              or not exists (select 1 from app.consent_events ce where ce.person_id = v_person and ce.basis is not null)) then
        raise exception 'consent';
      end if;
      -- the sender: the record's owner's mailbox when the step says so, else the workflow owner's
      v_owner := (app.wf_value(to_jsonb(coalesce(c ->> 'from', '@record_owner')), p_run.subject_type, p_run.subject_id, p_wf.owner_id)) #>> '{}';
      v_mailbox := (select m.id from app.mailboxes m where m.deleted_at is null and m.status in ('syncing', 'synced')
                    and (m.owner_id = v_owner or exists (select 1 from app.mailbox_members mm where mm.mailbox_id = m.id and mm.staff_id = v_owner and mm.can_reply))
                    order by m.kind = 'personal' desc, m.created_at limit 1);
      if v_mailbox is null then raise exception 'mailbox_not_connected'; end if;
      v_msg := app.mail_enqueue(v_owner, v_mailbox, null, jsonb_build_array(jsonb_build_object('address', v_to)), null, null, v_tpl.subject, v_tpl.body,
                                app.merge_context(p_run.subject_type, p_run.subject_id, v_person, v_owner), v_tpl.id, null, null,
                                case when k = 'send_email' then 'workflow' else 'sequence' end,
                                case when k = 'email_manual' then 'awaiting_review' end, null, p_run.enrollment_id, p_step,
                                p_run.subject_type, p_run.subject_id, v_person);
      update app.workflow_run_steps set output = jsonb_build_object('message', v_msg) where id = p_step;
      if k = 'email_manual' then
        -- a manual email waits for its sender to review and send it
        update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = 'email.sent', wait_ref = v_msg::text, wait_deadline = null where id = p_run.id;
        update app.workflow_run_steps set state = 'waiting' where id = p_step;
        return null;
      end if;
    when 'webhook', 'slack', 'teams', 'accounting_invoice' then
      if k <> 'webhook' and not exists (select 1 from app.integration_connections ic where ic.provider = case k when 'accounting_invoice' then 'accounting' else k end and ic.status = 'connected') then
        raise exception 'not_connected';
      end if;
      if k = 'webhook' and not app.url_public(c ->> 'url') then raise exception 'blocked_address'; end if;
      update app.workflow_run_steps set state = 'queued',
        request = case when k = 'webhook' then jsonb_build_object('method', coalesce(c ->> 'method', 'POST'), 'url', c ->> 'url',
                                                                 'body', app.wf_render(c ->> 'body', p_run.subject_type, p_run.subject_id, true))
                       else jsonb_build_object('message', app.wf_render(c ->> 'message', p_run.subject_type, p_run.subject_id), 'channel', c ->> 'channel') end
      where id = p_step;
      update app.workflow_runs set state = 'waiting', cursor = coalesce(p_node ->> 'next', ''), wait_event = 'step.done', wait_ref = p_step::text where id = p_run.id;
      perform pgmq.send('jobs', jsonb_build_object('job', 'workflow_step', 'step_id', p_step, 'kind', k));
      return null;
    when 'campaign_action' then
      -- CMP-07: the subject's person gets the automated campaign, or the step is skipped with the reason (never to
      -- people who are not subscribed or are suppressed, D-27); the run goes on either way
      if not app.can('campaigns', 'workflows') then raise exception 'forbidden'; end if;
      v_person := case p_run.subject_type when 'person' then p_run.subject_id
                    when 'deal' then (select d.person_id from app.deals d where d.id = p_run.subject_id)
                    when 'lead' then (select l.person_id from app.leads l where l.id = p_run.subject_id) end;
      v_ref := app.campaign_enqueue((c ->> 'campaign_id')::uuid, v_person, p_step::text);
      if v_ref is not null then
        update app.workflow_run_steps set state = 'skipped', finished_at = now(), output = jsonb_build_object('skip_reason', v_ref) where id = p_step;
      else
        update app.workflow_run_steps set output = jsonb_build_object('campaign', c ->> 'campaign_id', 'queued', true) where id = p_step;
      end if;
    when 'project_action' then
      raise exception 'not_available';
    else
      raise exception 'unknown_step';
  end case;
  update app.workflow_run_steps set state = 'succeeded', finished_at = now() where id = p_step and state = 'running';
  if p_run.enrollment_id is not null then
    update app.sequence_enrollments set current_ord = current_ord + 1, current_key = p_node ->> 'next' where id = p_run.enrollment_id;
  end if;
  return coalesce(p_node ->> 'next', '');
end $function$;

-- the consent log names the campaign an unsubscribe, complaint or bounce came from
CREATE OR REPLACE FUNCTION public.consent_log(p_limit integer DEFAULT 50, p_before bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require('campaigns', 'see'); v_sandbox boolean := (select sandbox from app.admins where id = v_me); v_rows jsonb;
begin
  perform app.require_module('campaigns');
  select coalesce(jsonb_agg(x.j order by x.id desc), '[]'::jsonb) into v_rows from (
    select c.id, jsonb_build_object('id', c.id, 'at', c.at, 'person_id', p.id, 'name', p.name, 'email', p.email, 'prev_status', c.prev_status, 'status', c.status,
             'source', c.source, 'basis', c.basis, 'ref_type', c.ref_type, 'ref_id', c.ref_id, 'detail', c.detail,
             'ref_label', case when c.ref_type in ('form_submission', 'confirmation')
                               then (select f.name from app.form_submissions s join app.forms f on f.id = s.form_id where s.id = c.ref_id)
                               when c.ref_type in ('campaign', 'provider') then (select x.name from app.campaigns x where x.id = c.ref_id) end,
             'text_version', (select t.version from app.consent_texts t where t.id = c.text_id),
             'actor', (select a.name from app.admins a where a.id = c.actor_id)) j
    from app.consent_events c join app.people p on p.id = c.person_id
    where (p_before is null or c.id < p_before) and p.deleted_at is null and app.visible(p.owner_id, p.visibility) and (v_sandbox or not p.is_sample)
    order by c.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) x;
  perform app.log('record.listed', 'consent_event', null, jsonb_build_object('count', jsonb_array_length(v_rows)));
  return jsonb_build_object('rows', v_rows, 'next', (select min((r ->> 'id')::bigint) from jsonb_array_elements(v_rows) r));
end $function$;

-- erasure (SEC-11) also blanks the person's campaign recipient rows
CREATE OR REPLACE FUNCTION app.person_erased()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update app.form_submissions set field_values = '{}'::jsonb, fingerprint = null, tracking = '{}'::jsonb, consent = '{}'::jsonb, files = '[]'::jsonb
  where person_id = old.id;
  delete from app.chat_conversations where person_id = old.id;
  -- campaign recipients keep their figures, not the address or the provider's place (0037); person_id is set null by the key
  update app.campaign_recipients set email = null, city = null, country = null where person_id = old.id;
  if old.email is not null and not old.is_sample and coalesce(current_setting('app.purging', true), '') <> 'on'
     and not exists (select 1 from app.suppressions s where s.email_sha256 = app.email_hash(old.email)) then
    insert into app.suppressions (email_sha256, scope, reason, created_by) values (app.email_hash(old.email), 'marketing', 'erasure', app.me());
  end if;
  return old;
end $function$;

-- the generic saved views leave segments alone: a segment is changed and deleted through segment_* (0037)
CREATE OR REPLACE FUNCTION public.view_save(p_id uuid, p_screen text, p_name text, p_query jsonb, p_shared boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require_staff(); v_id uuid;
begin
  if p_id is null then
    insert into app.saved_views (screen, name, query, owner_id, shared) values (p_screen, btrim(p_name), coalesce(p_query, '{}'::jsonb), v_me, coalesce(p_shared, false)) returning id into v_id;
  else
    update app.saved_views set name = coalesce(nullif(btrim(p_name), ''), name), query = coalesce(p_query, query), shared = coalesce(p_shared, shared)
    where id = p_id and owner_id = v_me and kind = 'view' returning id into v_id;
  end if;
  if v_id is null then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.view_delete(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  delete from app.saved_views where id = p_id and owner_id = app.require_staff() and kind = 'view';
  return jsonb_build_object('ok', found);
end $function$;

-- the Inbox's templates stay the sales ones (spec §4: templates_get returns kind sales only)
CREATE OR REPLACE FUNCTION public.templates_get()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := app.require('deals', 'see');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'scope', t.scope, 'is_starter', t.is_starter,
                                                       'owner_id', t.owner_id, 'owner', (select a.name from app.admins a where a.id = t.owner_id),
                                                       'subject', t.subject, 'body', t.body, 'updated_at', t.updated_at,
                                                       'mine', t.owner_id = v_me)
                                    order by t.is_starter desc, t.name)
                   from app.email_templates t where t.deleted_at is null and t.kind = 'sales' and (t.scope = 'shared' or t.owner_id = v_me)), '[]'::jsonb);
end $function$;

create or replace function public.template_save(p_id uuid, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_templates; v_id uuid; r jsonb;
begin
  if p_id is not null then
    select * into t from app.email_templates where id = p_id and kind = 'sales' and deleted_at is null for update;
    if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
    if t.owner_id is distinct from v_me and not app.can('global', 'configure') then
      raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
    end if;
  end if;
  if p_values ? 'scope' and p_values ->> 'scope' not in ('private', 'shared') then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scope';
  end if;
  r := app.merge_render(coalesce(p_values ->> 'subject', t.subject, '') || ' ' || coalesce(p_values ->> 'body', t.body, ''), '{}'::jsonb);
  if jsonb_array_length(r -> 'unknown') > 0 then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'merge:' || (r -> 'unknown' ->> 0);
  end if;
  if p_id is null then
    insert into app.email_templates (name, scope, owner_id, subject, body, is_sample)
    values (btrim(p_values ->> 'name'), coalesce(p_values ->> 'scope', 'private'), v_me, coalesce(p_values ->> 'subject', ''), coalesce(p_values ->> 'body', ''),
            (select sandbox from app.admins where id = v_me))
    returning id into v_id;
  else
    update app.email_templates set name = coalesce(btrim(p_values ->> 'name'), name), scope = coalesce(p_values ->> 'scope', scope),
      subject = coalesce(p_values ->> 'subject', subject), body = coalesce(p_values ->> 'body', body), updated_at = now()
    where id = p_id returning id into v_id;
  end if;
  perform app.log(case when p_id is null then 'template.created' else 'template.updated' end, 'email_template', v_id::text, null);
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function public.template_delete(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); t app.email_templates;
begin
  select * into t from app.email_templates where id = p_id and kind = 'sales' and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if t.owner_id is distinct from v_me and not app.can('global', 'configure') then
    raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure';
  end if;
  update app.email_templates set deleted_at = now() where id = p_id;
  perform app.log('template.deleted', 'email_template', p_id::text, null);
  return jsonb_build_object('id', p_id);
end $fn$;

-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['email_template_versions', 'sender_domains', 'campaigns', 'campaign_links', 'campaign_recipients', 'campaign_events'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;

do $$
declare f text;
begin
  foreach f in array array['app.email_template_version_fixed()', 'app.campaign_link_fixed()', 'app.campaign_event_fixed()', 'app.campaign_guard()',
                           'app.slug(text)', 'app.marketing_skip(text, text)', 'app.domain_authenticated(app.sender_domains)', 'app.domain_verified(app.sender_domains)',
                           'app.pct(numeric, numeric)', 'app.segment_sql(jsonb, boolean)', 'app.segment_counts(jsonb, boolean)', 'app.campaign_design_check(jsonb)',
                           'app.campaign_html_check(text, text)', 'app.campaign_unknown_token(text)', 'app.campaign_utm(text, text, uuid)',
                           'app.campaign_reports_ok(app.campaigns)', 'app.campaign_take(uuid, text)', 'app.campaign_stats(uuid)', 'app.campaign_workflows(uuid)',
                           'app.campaign_row(app.campaigns, boolean)', 'app.csv_cell(text)', 'app.campaign_resolve(app.campaigns)', 'app.campaign_enqueue(uuid, uuid, text)',
                           'app.campaign_finish(uuid)', 'app.campaign_due()', 'app.campaign_ab_decide()',
                           'app.campaign_address_down(app.campaign_recipients, text, text)', 'app.campaign_unsubscribe(app.campaign_recipients, text, text)',
                           'app.campaign_prune()', 'app.hygiene_months()', 'app.hygiene_ids()', 'app.sender_domain_row(app.sender_domains)',
                           'app.sender_domains_check_all()', 'app.merge_value(text, jsonb)', 'app.filter_sql(app.entities, jsonb)', 'app.wf_validate(text, jsonb, text)',
                           'app.wf_blockers(uuid)', 'app.wf_step(app.workflow_runs, app.workflows, text, jsonb, uuid)', 'app.person_erased()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.campaigns_get(jsonb)', 'public.campaign_get(uuid)', 'public.campaign_save(uuid, jsonb, int)', 'public.campaign_duplicate(uuid)',
                           'public.campaign_delete(uuid[], text)', 'public.campaign_preview(uuid, uuid, text)', 'public.campaign_test_send(uuid, text, uuid)',
                           'public.campaign_schedule(uuid, timestamptz, int, text)', 'public.campaign_cancel(uuid)', 'public.campaign_pause(uuid, boolean)',
                           'public.campaigns_compare(uuid[], text)', 'public.campaign_recipients(uuid, text, int)', 'public.campaign_export(uuid, text)',
                           'public.marketing_templates_get()', 'public.marketing_template_save(uuid, jsonb, int)', 'public.marketing_template_delete(uuid)',
                           'public.segment_count(jsonb)', 'public.segments_get()', 'public.segment_save(uuid, text, jsonb, text, boolean)', 'public.segment_delete(uuid)',
                           'public.hygiene_candidates()', 'public.hygiene_archive(int)', 'public.sender_domains_get()', 'public.sender_domain_save(uuid, jsonb, int)',
                           'public.sender_domain_delete(uuid)', 'public.sender_domain_recheck(uuid)', 'public.deliverability_recommendations()',
                           'public.consent_log(int, bigint)', 'public.view_save(uuid, text, text, jsonb, boolean)', 'public.view_delete(uuid)',
                           'public.templates_get()', 'public.template_save(uuid, jsonb)', 'public.template_delete(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.worker_campaign_batch(uuid, int)', 'public.worker_campaign_sent(uuid, text)', 'public.worker_campaign_failed(uuid, text)',
                           'public.worker_unsubscribe(text, text, text)', 'public.worker_email_events(jsonb)', 'public.worker_sender_domain_status(uuid, jsonb)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
