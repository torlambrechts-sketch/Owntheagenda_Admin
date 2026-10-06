# 07 — Implementation plan

Phase B (A4), written 2026-10-06 after Tor approved every recommendation (D-01 to D-42) and asked for the
full implementation of the design in `design-reference/sentral/`.

## Ground rules for the build

- **Branch.** Work happens on `build/sentral`. `main` deploys to production on Vercel. A migration cannot
  reach the hosted database until Supabase access is restored (Q-01), so `main` only receives the branch
  when its migrations can be applied in the same step.
- **Local first.** `supabase/config.toml` is in the repository with its own port block (544xx), TOTP on, and
  a seed for the demo tenant (D-02, D-33). Every migration is tested against a database rebuilt from zero.
- **One rule set.** RLS on, no policy and no client grant on every table. All access goes through
  security-definer functions that check staff, permission and visibility, and write the audit
  (D-09, D-12). MFA is always on (D-11). There is no survey data in this database (D-19, D-34).
- **Design fidelity.** Every screen is recreated from the bundle's source: its inline styles give exact
  sizes, colours, radii and type. Tokens are transcribed into `tailwind.config.ts`, and fonts are the bundle's
  own (D-36). The design's navigation buttons become real links (control substitution, logged).
- **No invented data.** A screen shows what the database holds. Where a source does not exist yet, the screen
  shows the design's empty treatment, never a placeholder that looks like data. Demo data exists only through
  the seed, in development and in the sandbox.
- **Language.** English is the default, bokmål is available, and the choice is per staff member (D-04). Every
  string is a message key.
- **Gates per package.** Typecheck, lint, unit tests, SQL suites on a fresh database, Playwright end-to-end and
  visual checks at 1440 and 390 px, and the security checklist (A7).

## Data model (mapping Part F to tables)

All tables are in schema `app`. Standard columns on business records: `id uuid`, `created_at`, `created_by`,
`updated_at`, `updated_by`, `deleted_at` (30-day soft delete), `version` (optimistic concurrency),
`owner_id` and `visibility` where the spec gives a record an owner, and `is_sample` (sandbox).

| Area | Tables (new unless noted) |
|---|---|
| Identity | `admins` → extended into the staff table: `user_id`, `name`, `initials`, `phone`, `locale`, `time_zone`, `team_id`, `permission_set_id`, `created_by`. Also `teams`, `permission_sets`, `permission_set_rights`, `visibility_groups`, `recovery_codes` |
| Audit and events | `audit` extended (action, target_type, target_id, account_id, reason, detail). `events` (outbox: kind, subject, payload, delivered_at). `changelog` (record, field, old, new, actor, source) |
| Configuration | `settings_registry` (key, type, options, default, scope, applies_to, fixed). `setting_values`. `modules` (switches). `fields` (custom field definitions per entity). `labels`. `pipelines`, `stages` |
| Customers | `accounts` (existing, the company by org.nr) ← `organizations` (CRM fields: address, industry, fylke, owner, labels, parent, custom). `people` (one person, optional link to `members`). `account_products`, `subscriptions`, `members`, `usage_daily` stay as product mirrors |
| Sales | `leads`, `deals`, `deal_participants`, `deal_products`, `catalog_items`, `activities`, `activity_types`, `notes`, `files`, `followers` |
| Support | `tickets`, `ticket_messages`, `ticket_links`, `ticket_events`, `canned_replies`, `help_articles`, `problems` (linking) |
| Engagement | `mailboxes`, `messages`, `threads`, `templates`, `scheduler_links`, `calls` |
| Automation | `workflows`, `workflow_versions`, `workflow_runs`, `run_steps`, `sequences`, `enrolments`, `assignment_rules`, `webhooks`, `webhook_deliveries` |
| Insights | `reports`, `dashboards`, `goals`, metric views |
| Growth | `forms`, `chatbots`, `chats`, `web_visits`, `visitor_companies`, `campaigns`, `campaign_sends`, `segments`, `consents`, `suppressions` |
| Delivery | `projects`, `project_boards`, `project_phases`, `tasks`, `documents`, `document_templates`, `signatures` |
| AI and meetings | `ai_calls` (gateway log), `meetings`, `transcripts` (provider-dependent) |
| Platform | `api_tokens`, `oauth_clients`, `apps` (catalog), `jobs` view over pgmq and pg_cron, `privacy_requests`, `subprocessors`, `incidents` |

Relationship rules:
- An `organizations` row has `account_id → accounts` (org.nr), when the company is also a customer.
- A `people` row has `member_ref (product, tenant_id, user_id)`, when the person is a product user.
- Product events update only the mirror tables. A CRM field a person has edited is never overwritten (D-13).

## Phases and work packages

The order follows Part G. Each phase ends with its gate flows and a phase report in `reports/`.

| Phase | Packages | Screens (design file) | Gate |
|---|---|---|---|
| **0 Foundations** | P0.1 dev infra (config.toml, seed, SQL test runner, Playwright, CI on local DB) · P0.2 tokens, fonts, components, app shell (sidebar, product picker, header, ⌘K search, sandbox, notifications, account menu, language) · P0.3 staff, teams, permission sets, visibility · P0.4 audit extension, outbox, changelog · P0.5 settings registry and module switches · P0.6 custom fields, labels, organizations, people, soft delete and purge job, pg_cron/pgmq · P0.7 Overview from real data · P0.8 SQL suites (structure, roles, firewall, settings, audit) and the F-1..F-6 fixes | Sentral Admin (shell, Overview) | A custom field works end to end on organisations and people; SF-01, SF-02, SF-34, SF-38 |
| **1 Sales core** | Organizations (list, detail tabs, actions via product commands) · Contacts and Leads · Deals (pipelines, board, list, forecast, rotting, products) · Activities (calendar, list, types) · Tickets (Appendix 2, D-20, inbound events) · Settings (fields, pipelines, users and teams, register) · Spec coverage | Customers, Contacts, Deals, Activities, Tickets, Settings, Coverage | UF-01, 02, 09, 10, 23, 24, 29; SF-07, 09, 10, 15, 25, 26, 32, 33, 35, 36, 37, 45 |
| **2 Engagement** | Mailbox sync (Gmail/Graph), Inbox, templates, tracking, scheduler, calls · Feed | Inbox, Feed | UF-04, 06, 25; SF-03, 08, 28, 29, 40 |
| **3 Automation** | The single engine: workflows, sequences, assignment, date triggers, loop protection | Automation | UF-05, 11, 12; SF-04, 05, 06 |
| **4 Insight** | Reports, dashboards, goals, forecast · Analytics (business KPIs, funnel, attribution, health) · Prospecting | Insights, Analytics | UF-03, 13, 14, 26; SF-11..14 |
| **5 Capture and close** | Forms, chatbot, live chat, web visitors, documents and e-sign | Marketing (forms, visitors), Documents | UF-08, 18, 19; SF-17, 18, 20, 30 |
| **6 Market and deliver** | Campaigns, segments, consent, suppression · Projects | Marketing (campaigns), Projects | UF-17, 20; SF-19, 39, 42 |
| **7 AI** | AI gateway (Claude), Assistant panel, meetings and transcripts | Shell assistant, Meetings | UF-07, 27; SF-21, 24 |
| **8 Platform and channels** | Applications, API tokens, webhooks, OAuth, MCP, Security and privacy, entitlements, mobile PWA | Platform, Security, Mobile | UF-15, 16, 21, 22, 28; SF-16, 22, 23, 27, 31, 41, 43, 44 |

Orgpuls-side work that the platform needs (each is a small Orgpuls migration with a test):
- D-21: count-only events for the funnel and health score.
- D-22: price, currency and seats on `billing.changed`.
- D-40: commands the design shows (suspend, export, support access, flags) when their feature is built.

## Provider-dependent features

These are built with their adapters. Without credentials they show their real unconnected state, never fake
output:
- mailbox sync (Gmail, Microsoft Graph)
- email sending (one provider, two streams)
- LLM (Claude)
- transcription and meeting bot
- e-signature evidence
- IP-to-company
- person data
- telephony
- accounting

Each needs a key from Tor before it can run.

## Test plan per package

- **Database:** structure; RLS on and no client grant; allow and deny per permission set on each function;
  visibility; firewall; settings defaults in both states; soft delete and purge; version conflicts; audit
  rows.
- **Unit:** pure logic (filters, scoring, schedules, merge fields, formulas, setting evaluation).
- **End-to-end:** each user flow in the phase's gate, run against the seeded demo tenant.
- **Visual:** each screen and state at 1440 and 390 px, inspected, then added to regression snapshots.
- **Accessibility:** axe on each screen, plus a keyboard pass.
