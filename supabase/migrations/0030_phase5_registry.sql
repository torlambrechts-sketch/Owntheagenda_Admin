-- 0030_phase5_registry.sql — the shared registers Phase 5 (lead capture, web visitors, documents) extends, in one
-- place so 0031 (capture) and 0032 (documents) do not redefine the same constraint. Spec:
-- docs/crm-enrichment/specs/marketing-documents.md §4, §8.

-- providers: the email provider (two streams, D-07), IP-to-company resolution and an external e-signature service
alter table app.integration_connections drop constraint integration_connections_provider_check;
alter table app.integration_connections add constraint integration_connections_provider_check
  check (provider in ('slack', 'teams', 'accounting', 'asana', 'trello', 'contact_data', 'telephony', 'messaging', 'search_console', 'ai',
                      'email', 'ip_company', 'esign'));
insert into app.integration_connections (provider) values ('email'), ('ip_company'), ('esign') on conflict do nothing;

-- records made by a form, a chat, a reveal or a visitor conversion carry the source «capture»
alter table app.changelog drop constraint changelog_source_check;
alter table app.changelog add constraint changelog_source_check
  check (source in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'merge', 'enrichment', 'capture'));

-- settings (D-15/D-16). double_opt_in defaults to on against D-16's «unrestricted»: D-27's consent rules win
-- (spec Q3, logged in DEVIATIONS). campaign_rules and survey_flow_block are fixed rules shown read-only.
insert into app.settings_registry (key, grp, options, default_value, scope, applies_to, fixed, numeric_option, ord) values
  ('double_opt_in', 'contacts_consent', array['on', 'off'], 'on', 'platform', 'CMP-04, LGN-03', false, null, 30),
  ('list_hygiene', 'contacts_consent', array['source_values', 'custom', 'off'], 'source_values', 'platform', 'CMP-04, CMP-08 (months without engagement; 12 by default)', false, 'custom', 40),
  ('doc_branding', 'documents', array['hidden', 'shown'], 'hidden', 'platform', 'DOC-06', false, null, 500),
  ('esign_service', 'documents', array['builtin', 'external'], 'builtin', 'platform', 'DOC-05, DOC-06', false, null, 510),
  ('campaign_rules', 'platform_constant', array['fixed'], 'fixed', 'platform', 'CMP-01, CMP-03, CMP-04, CMP-08', true, null, 170),
  ('survey_flow_block', 'platform_constant', array['fixed'], 'fixed', 'platform', 'LGN-05, WEB-01', true, null, 180);

-- the screen each new record type opens on (notification links, ⌘K, feed cards)
create or replace function app.entity_route(p_entity text) returns text
  language sql immutable set search_path = ''
as $fn$
  select case p_entity when 'deal' then '/deals' when 'lead' then '/leads' when 'person' then '/contacts' when 'organization' then '/contacts'
                       when 'activity' then '/activities' when 'ticket' then '/tickets' when 'email_thread' then '/inbox'
                       when 'form' then '/lead-capture' when 'chat' then '/lead-capture' when 'campaign' then '/campaigns'
                       when 'document' then '/documents' when 'document_template' then '/documents' else null end
$fn$;

-- web sites: a key for the embed snippet, a last-seen time, chat on or off, and never a survey host (fixed rule)
alter table app.web_sites
  add column key text unique check (key ~ '^[a-z0-9-]{2,40}$'),
  add column last_seen_at timestamptz,
  add column chat_enabled boolean not null default false,
  add constraint web_sites_not_survey check (hostname !~ '(^|\.)svar\.');
update app.web_sites set key = regexp_replace(regexp_replace(hostname, '^www\.', ''), '[^a-z0-9]+', '-', 'g') where key is null;
create index web_sessions_company on app.web_sessions (company_org_number, day) where company_org_number is not null;
