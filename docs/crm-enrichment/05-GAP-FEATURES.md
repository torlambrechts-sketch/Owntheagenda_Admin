# 05 — Gap against the specification

Phase A, A3.5. Every feature (183), user flow (29, with 169 steps), system flow (45, with 238 steps),
setting in the register (15), Part F item (199) and Part G non-functional requirement (17), judged
against **this repository only** (`main` `8c01aec`, 2026-10-06). Statuses and row format follow A3.5.
Each row also has an extra column: the design screen that shows the feature (`design-reference/sentral/`).
Per decision D-01, everything is built new; no earlier system is used as a source or reference. The "Work package" column is
filled in during Phase B.

Each part was written by a separate reviewer who read its line range of `INSTRUCTIONS.md` in full.
The Partial and Conflict rows were checked against the cited lines before this file was assembled.

## Summary

**Nothing is Implemented.** The repository has no database or end-to-end tests, and no CRM screen exists.
The platform is the foundation from 5 October: sign-in with TOTP, product events in, signed commands out,
an append-only command audit and a status page.

### Features per module

| Module | Features | Implemented | Partial | Missing | Conflict | Unknown |
|---|---|---|---|---|---|---|
| PIP Pipeline and deals | 17 | 0 | 0 | 17 | 0 | 0 |
| ACT Activities | 9 | 0 | 0 | 9 | 0 | 0 |
| CRM Records | 15 | 0 | 1 | 14 | 0 | 0 |
| CUS Customization | 8 | 0 | 0 | 7 | 1 | 0 |
| LEA Leads | 6 | 0 | 0 | 6 | 0 | 0 |
| COM Email and communications | 14 | 0 | 0 | 14 | 0 | 0 |
| AUT Automation | 12 | 0 | 0 | 12 | 0 | 0 |
| INS Insights and reports | 10 | 0 | 0 | 10 | 0 | 0 |
| PRO Prospecting | 7 | 0 | 0 | 7 | 0 | 0 |
| AIA AI assistant | 7 | 0 | 0 | 7 | 0 | 0 |
| MTG Meeting intelligence | 8 | 0 | 0 | 8 | 0 | 0 |
| MCP AI connector | 3 | 0 | 0 | 3 | 0 | 0 |
| CMP Email marketing | 9 | 0 | 0 | 9 | 0 | 0 |
| PRJ Projects | 9 | 0 | 0 | 9 | 0 | 0 |
| LGN Lead generation | 5 | 0 | 0 | 5 | 0 | 0 |
| WEB Web visitors | 4 | 0 | 0 | 4 | 0 | 0 |
| DOC Documents and e-sign | 6 | 0 | 0 | 6 | 0 | 0 |
| SEC Security and permissions | 11 | 0 | 3 | 8 | 0 | 0 |
| INT Integrations and API | 11 | 0 | 0 | 11 | 0 | 0 |
| MOB Mobile app | 8 | 0 | 0 | 8 | 0 | 0 |
| ENT Plans and entitlements | 4 | 0 | 0 | 4 | 0 | 0 |
| **Total** | **183** | **0** | **4** | **178** | **1** | **0** |

Partial: CRM-01 (organisation and person records exist as `app.accounts`/`app.members`, without the
fields, views or ownership the spec asks for), SEC-06 (TOTP enforced for every admin; no email-code
factor, no recovery, no admin control), SEC-09 (staff list `app.admins` with deactivation; no invite,
teams or screens), SEC-10 (EU hosting, a database separate from survey data, secrets in Vault; no
backup or restore evidence). Conflict: CUS-05 (the spec makes English the default and the locale a
per-user setting; the platform defaults to bokmål with a cookie, see 06-QUESTIONS, Q-04).

### Flows, settings, data model and non-functional requirements

| Part | Rows | Implemented | Partial | Missing | Conflict | Unknown |
|---|---|---|---|---|---|---|
| User flows (whole flows) | 29 | 0 | 4 | 25 | 0 | 0 |
| User-flow steps | 169 | 0 | 4 | 165 | 0 | 0 |
| System flows (whole flows) | 45 | 0 | 9 | 35 | 1 | 0 |
| System-flow steps | 238 | 0 | 13 | 223 | 1 | 1 |
| Settings register | 15 | 0 | 1 | 14 | 0 | 0 |
| Part F conventions | 8 | 0 | 3 | 4 | 1 | 0 |
| Part F entities | 123 | 0 | 6 | 116 | 1 | 0 |
| Part F events | 60 | 0 | 4 | 56 | 0 | 0 |
| Part F API surface | 8 | 0 | 0 | 8 | 0 | 0 |
| Part G non-functional requirements | 17 | 0 | 4 | 11 | 1 | 1 |

All 29 user flows are gate flows for Part G's phases 1–8 (`INSTRUCTIONS.md:2515-2525`). The design
bundle's `coverage-data.js` contains the same 29 flows word for word (checked by script: 0 differences),
so the design was made from this specification.

### The ten largest gaps

1. **Staff roles and permissions** (SEC-07, SEC-08, SEC-09; Appendix 2 Access model). Only `owner`/`admin`
   exist and nothing reads the role. Every module depends on roles, visibility and permission sets.
2. **The CRM record model** (CRM-01..15, LEA, PIP). There are no contacts, leads, deals, pipelines,
   activities, custom fields, owners or visibility. Everything else is built on these.
3. **Settings registry** (CUS-07, SF-34, A9). It does not exist, yet every feature must ask it for its limits.
4. **Audit for writes and reads with reasons; changelog; events** (SF-02, SEC-11, Part F conventions).
   `app.audit` only records product commands.
5. **Job runtime and workflow engine** (AUT-01..12, SF-03.., open point 3). There is no runner, no
   schedule and no "lifecycle-messaging engine" to extend, although Part G assumes one exists.
6. **Email: mailbox sync, sending, templates, campaigns, consent and suppression** (COM, CMP, AUT-07).
   There is no provider and no consent model.
7. **Ticketing and the inbound path** (Appendix 2 Ticketing; LGN-03, LEA-04). `support.requested` and
   `contact.submitted` arrive and are stored raw, but nothing turns them into tickets or leads.
8. **Insights and reports on business figures** (INS-01..10; Appendix 2 Analytics). There are no metric
   views, no prices in the billing mirror, and the funnel events are not emitted by Orgpuls.
9. **Integrations, API, webhooks and the AI connector** (INT, MCP, AIA). There is no public API, no tokens and no outbound webhooks.
10. **Test and seed infrastructure** (A8, R8). There are no database tests, no end-to-end tool, no demo
    tenant, and the repository cannot start a local database by its own commands.

The full question list is `06-QUESTIONS.md`. The part-reviews' own question lists were merged into it.

---

## Part 1 — Features: PIP, ACT, CRM, CUS and the settings register

Repository judged: `/home/user/owntheagenda_admin` at `8c01aec`. Phase A: no file in the repository changed.

**Abbreviations used in Evidence**
- **No table.**: no table, column, function or seed for this exists. The whole schema is `supabase/migrations/0001_foundation.sql` (tables at l.18 admins, l.41 products, l.47 installations, l.58 accounts, l.66 account_products, l.80 subscriptions, l.98 members, l.111 usage_daily, l.122 events_in, l.136 audit) plus `0002_product_secrets.sql` (Vault secrets/intake). `supabase/tests/` is empty, there is no seeds folder, and there are no storage buckets, cron jobs or notification channels.
- **No route**: no route, server action or component exists. The app consists of `app/page.tsx` (status page), `app/login/*`, `app/mfa/*`, `app/ingen-tilgang/page.tsx`, `app/actions.ts` and `app/TestButton.tsx`. The only tests are `tests/signing.test.ts` (4 unit tests, signing only).
- **Settings that apply to every row**: `firewall` (fixed) and `typed_reason` ("Every CRM write and read of customer data") apply to every PIP, ACT, CRM and CUS feature. They are not repeated in each row. Setting keys come from the design's `admin-data.js` (`SA.settings`), because the brief's register defines no keys.
- **Design screen** names the screen that shows the feature, confirmed by grepping the concept. `coverage-data.js` also maps every ID in scope to a route (PIP → deals, ACT → activities, CRM → contacts except CRM-07/08 → deals, CUS → settings).

### Feature rows

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PIP-01 Kanban pipeline view | Missing | No table. no deal/stage table; No route; no event emitter for `deal.stage_changed` (ingest only receives events, 0001 l.173) | All of it: stage columns with drag-to-move, count and value per column, card content, optimistic save with rollback, changelog plus `deal.stage_changed`, paging per stage, visibility rules, no drop without edit rights | — | PIP-02, PIP-03, PIP-04 (changelog), SEC (visibility, edit rights), CUS-07 | — | Deals.dc.html (pipeline view, drag, column sums) |
| PIP-02 Pipelines and stages | Missing | No table, no route | All of it: unlimited pipelines; ordered stages with name, probability 0–100 and optional rotting threshold; add, rename, reorder and delete with a target stage; pipeline visibility groups | (pipeline count via `plan_gates`, not listed in register) | SEC-visibility groups, PIP-05 | — | Settings.dc.html («Pipelines and stages»: stages, prob, rot); Deals.dc.html |
| PIP-03 Deal record | Missing | No table. (no deal entity; `app.accounts` l.58 is a customer, not a deal) | All of it: deal fields incl. currency, probability, labels, source, status, custom fields; one primary person and one org; value derived from products; create with title only; history of every change | — | CRM-01, PIP-08, CRM-07, CUS-01, CUS-06, CRM-15, PIP-04 | — | Deals.dc.html |
| PIP-04 Deal detail view | Missing | No table. (no changelog table; `app.audit` l.136 only records product commands, with no field or old/new values); No route | All of it: header (owner, followers, Won/Lost), stage bar, sidebar sections that can be reordered and hidden, tabs (notes … invoice), Focus list, paginated and filterable History, changelog entry (field, old, new, user, time, source) | — | PIP-03, PIP-09, PIP-08, CRM-05, CRM-06, ACT-01, COM (email), DOC, invoicing provider (unnamed) | — | Deals.dc.html (detail, changelog, history, participants) |
| PIP-05 Deal rotting | Missing | No table. (no per-stage threshold, no idle clock); no notification channel or job exists | All of it: per-stage optional threshold, red card with idle days, owner notified, clock reset on stage move, completed activity, email or note | — | PIP-02, ACT-01, COM, CRM-06, notifications (unspecified module) | — | Deals.dc.html («Rotting · idle N days»); Settings.dc.html (stage `rot`) |
| PIP-06 Deal labels | Missing | No table, no route | All of it: colored labels (several per deal) on cards, rows and detail; label filter; managing labels requires a settings permission; deleting a label removes it from all deals | — | SEC (settings permission), PIP-12 | — | Deals.dc.html (labels, «Any label» quick filter) |
| PIP-07 Won, lost and lost reasons | Missing | No table. | All of it: close as won or lost; lost reason as free text or from a list; optional comment saved as a note; admin-managed list; a reason can be made mandatory; reopening keeps history; reason as a reporting dimension | (mandatory reason is a rule with no register row, see 06-QUESTIONS) | PIP-03, CRM-06, INS | — | Deals.dc.html (`lostReasons`, won/lost modal); Insights.dc.html |
| PIP-08 Participants | Missing | No table. (`app.members` l.98 are a tenant's product users, not deal participants) | All of it: extra people per deal (not the primary person); suggested in the scheduler and composer; added from an email's recipients; bulk import; removed when the person is deleted | — | CRM-01, COM, ACT-08, CRM-09 | — | Deals.dc.html («Person · organization · participants», addParticipant) |
| PIP-09 Followers | Missing | No table; no notifications | All of it: following deals, people, orgs, products and users; grants visibility and notifications only; follower notified on a stage change | — | SEC (visibility), notifications, CRM-07 | — | Deals.dc.html (follow button, «followers notified») |
| PIP-10 List view | Missing | No table, no route; no export | All of it: selectable columns, multi-column sort, inline, bulk edit and bulk delete, CSV/XLSX export, system ID shown and addressable, admin default columns, bulk-edit permission, exports respect visibility, one changelog entry per deal on bulk edit | `second_admin` | PIP-04, CRM-10, SEC-02, SEC (bulk-edit permission) | — | Deals.dc.html (List view, column picker incl. System ID, bulk bar, CSV) |
| PIP-11 Forecast view | Missing | No table, no route | All of it: date columns by close date or a custom date field; open, won and projected per column; drag changes the date; week, month or quarter; pipeline and owner filters; stage bar on cards | — | PIP-03, CUS-01, PIP-12 | — | Deals.dc.html (forecast by `closeMonth`); Insights.dc.html |
| PIP-12 Filters | Missing | No table, no route (no search function) | All of it: global search (name, email, phone, field value); quick and advanced ALL/ANY filters; saved filters with visibility and favorite; across 7 entities; operators by field type; configurable listing; same set in pipeline, list and forecast | — | CUS-01, LEA, PRJ, CRM-07, ACT-01 | — | Deals.dc.html (quick filters, `conds`, `savedFilters`); Contacts.dc.html (search name/email/phone); Sentral Admin.dc.html (search) |
| PIP-13 Archive | Missing | No table. (`account_products.status` 'deleted' l.70 is product deletion, not archive) | All of it: archive and unarchive leads and deals with history kept; excluded from default views and from capacity; archive view | (capacity via `plan_gates`/ENT-02, not listed) | ENT-02, LEA, PIP-16 | — | Deals.dc.html («Archive and restore» view) |
| PIP-14 Deal card customization | Missing | No table, no route | All of it: configurable card fields per pipeline, rendered on every card | — | PIP-01, PIP-02, CUS-01 | — | Deals.dc.html («Fields on cards in {pipeline}») |
| PIP-15 Closed deals toggle and stage timing | Missing | No table. (no stage history; no per-user preference store) | All of it: won/lost toggle remembered per user; progress bar with days per stage from stage history | — | PIP-01, PIP-10, PIP-04 | — | Deals.dc.html (`showClosed` toggle; `progress` with «N d») |
| PIP-16 Capacity and waitlist | Missing | No table, no route | All of it: when a capacity is set, manual adds are blocked and automation, API, chatbot, form and import adds go to a filterable waitlist that can be bulk-added; no payload lost; no limit by default | `plan_gates` (ENT-02; register lists ENT only) | ENT-02, AUT, INT, LGN, CRM-09, CRM-15 | — | Deals.dc.html («Capacity: unlimited (setting) · waitlist»); Settings.dc.html (overflow to waitlist) |
| PIP-17 Duplicate and restore | Missing | No table. (no soft delete) | All of it: duplicate with fields and products, without history or emails; restore within 30 days back to the deal's stage | (30-day window has no register row, see 06-QUESTIONS) | CRM-12, CRM-07 | — | Deals.dc.html («Duplicate with products», «Deleted — restorable for 30 days») |
| ACT-01 Activities | Missing | No table, no route | All of it: activity with type, subject, date, time, duration, owner, note, done, and a link to deal, lead, person, org or project (one deal); completion stamps time and user and can trigger automations; workflow-created flag; shows in the linked record's history | — | PIP-03, CRM-01, LEA, PRJ, AUT | — | Activities.dc.html |
| ACT-02 Custom activity types and fields | Missing | No table. | All of it: add, rename, order and deactivate types; custom outcome fields; deactivated type kept on past activities; new type immediately selectable and reportable | — | ACT-01, CUS-01, INS | — | Settings.dc.html («Activity types») |
| ACT-03 Calendar and list views | Missing | No route | All of it: day, week and month calendar plus to-do list; filters by user, type and status; drag to reschedule (updates the synced event); manager visibility; project tasks shown alongside | — | ACT-01, ACT-09, SEC, PRJ | — | Activities.dc.html («Calendar», «To-do list») |
| ACT-04 Reminders | Missing | No email provider, push, desktop notification or job (context file; nothing in the repo) | All of it: reminders in app, by email, desktop and push, combined per user; per-user timing; optional daily summary; productivity tips in the notification center; fires once per channel | — | ACT-01, email provider, MOB (push), notifications | — | Activities.dc.html («Reminders and sync») |
| ACT-05 Priority labels | Missing | No table. | All of it: high, medium and low; inline and bulk edit; shown in calendar and list; filterable and sortable | — | ACT-01, ACT-03, ACT-06 | — | Activities.dc.html (priority) |
| ACT-06 Bulk activities | Missing | No route | All of it: create or edit activities for many records from list views or inbox; bulk-edit permission; one activity per selected record | — | ACT-01, PIP-10, COM (inbox), SEC | — | Activities.dc.html (selection) |
| ACT-07 Next-step prompt | Missing | No table. | All of it: prompt for the next activity on done (switchable per user); warning icon on cards of deals with no planned activity | — | ACT-01, PIP-01 | — | Activities.dc.html; Deals.dc.html (next step, «No planned» warning) |
| ACT-08 Activity invites | Missing | No calendar integration | All of it: guests get invites through the synced calendar; responses tracked on the activity | — | ACT-09, PIP-08 | — | Activities.dc.html (guests, invite) |
| ACT-09 Calendar sync | Missing | No Google or Microsoft integration; no OAuth tokens table | All of it: one- or two-way Google/Microsoft sync; choice of calendar and activity types; private stays private; recurring external events read-only, not created natively; changes on either side propagate | — | ACT-01, INT, providers (Google, Microsoft) | — | Activities.dc.html (sync tab); Meetings.dc.html |
| CRM-01 People and organizations | Partial | Met: an organization has a name (`app.accounts.name` 0001 l.60, also org_number l.61); a person has a name and one email (`app.members.name`, `email` l.103–104); a person's organization comes through `(product, tenant_id) → account_products.account_id` (l.69, l.108); respondents stay outside by construction, since ingest projects only `member.*` users (l.249–257, comment l.97 «contacts, never respondents», l.9–10), but no database test proves this. Shown in the UI only as a count (`app/page.tsx:54`, `platform_status` l.313) | Not met: several emails, phones, owner, labels, marketing status and custom fields on a person; address, owner, labels and custom fields on an org; detail views with history, deals, activities, files and emails; "opening a person shows every linked deal…"; contact rule setting; no person entity across tenants (one row per product+tenant+user, so "at most one organization" is undefined, see 06-QUESTIONS). Records are product projections, not admin-owned | `contact_rule` | SEC (visibility), CUS-01, CRM-14, PIP-03, ACT-01, CRM-05, COM | — | Contacts.dc.html (people and orgs tabs, marketing status); Customers.dc.html |
| CRM-02 Contacts timeline | Missing | No route | All of it: one row per person or org with activity icons on a time axis, today marker, overdue in red; controls for look-back, follow-up frequency, type and owner; matches the record's history | — | ACT-01, CRM-01 | — | Contacts.dc.html («Timeline» tab) |
| CRM-03 Contacts map | Missing | No table. (no address or geocode columns); No route | All of it: map by address, filter by city, region and country; geocode once and cache; records without an address listed separately | — | CRM-01, geocoding/map provider (unnamed) | — | Contacts.dc.html («Map», «map tiles · provider adapter») |
| CRM-04 Contact sync | Missing | No Google or Microsoft integration | All of it: two-way address book sync; user picks contacts; match by email; new contacts follow the contact rule | `contact_rule` | CRM-01, INT, providers | — | Contacts.dc.html («Two-way sync · Google Contacts · Microsoft 365») |
| CRM-05 File attachments | Missing | No storage bucket (context file; no `storage.buckets` in migrations) | All of it: files on leads, deals, people, orgs, products and projects; listed in history; same visibility as the record; no fetch without record access | — | storage, SEC, all record types | — | Deals.dc.html (files tab); Contacts.dc.html (files) |
| CRM-06 Notes, mentions and comments | Missing | No table; no notifications | All of it: rich-text notes on any record; @mention notifications that respect visibility and open the record; threaded comments; pinned notes | — | SEC, notifications, all record types | — | Deals.dc.html (notes, pin, comments); Contacts.dc.html (notes, pin) |
| CRM-07 Product catalog | Missing | No table. (`app.products` l.41 is the platform's installed software products, not a sales catalog) | All of it: catalog (code, unit, prices per currency, tax, variations, notes, custom fields); deal lines with quantity, price and discount; deal value recalculated; default tax mode per user; spreadsheet import | — | PIP-03, CUS-01, CUS-06, CRM-09 | — | Deals.dc.html («Products» view) |
| CRM-08 Subscriptions and installments | Missing | No table. for product lines. Billing mirror exists (`app.subscriptions` 0001 l.80–95: plan, billing_interval, trial/cancel dates) but holds no amount or currency (ingest l.237–242), so it cannot yield MRR, ARR, ACV or TCV | All of it: recurring lines (frequency, until cancelled or N cycles up to 208); installments; MRR, ARR, ACV and TCV computed; Orgpuls subscriptions from the billing mirror; feeds INS-06 | — | CRM-07, billing mirror, INS-06 | — | Deals.dc.html (installment); Customers.dc.html, Analytics.dc.html (MRR/ARR) |
| CRM-09 Import | Missing | No route, no table | All of it: spreadsheet import of all entities in one session; mapping (AI suggestion); duplicate detection with merge or create; skip file with reasons; import history; rows over capacity to the skip file; consent source per row as a setting | `import_consent`; (capacity via `plan_gates`) | AIA-05, CRM-11, ENT-02, all record types | — | Contacts.dc.html («Import», skip file); Settings.dc.html |
| CRM-10 Export | Missing | No route | All of it: export of any list view and full data sets to CSV/XLSX; export permission; logged for SEC-02; exactly the rows and columns visible | — | SEC, SEC-02, PIP-10 | — | Contacts.dc.html («Export», XLSX); Deals.dc.html (CSV) |
| CRM-11 Merge duplicates | Missing | No table. (only exact `org_number` match when ingest creates an account, 0001 l.216, which is not configurable and has no review) | All of it: admin-configured matching rules; review list; flag on detail; compare view; pick surviving values; move deals, activities, emails and files; one record with combined history | `second_admin` | CRM-01, PIP-03, ACT-01, CRM-05 | — | Contacts.dc.html («Duplicates», merge) |
| CRM-12 Restore data | Missing | No table. (no soft delete; `app.audit` is append-only, l.148–154, but only records commands) | All of it: 30-day deleted list with who, when and source; restore with links intact; revert bulk changes; covers 6 entities; permission-based; bulk delete preview; second-admin approval setting | `second_admin` | SEC, PIP-17, all record types | — | Contacts.dc.html («Restore»); Deals.dc.html |
| CRM-13 Related organizations | Missing | No table. | All of it: parent, daughter and related links between orgs, shown on detail both ways | — | CRM-01 | — | Contacts.dc.html («Related organizations», add as parent/daughter/related) |
| CRM-14 Contact labels | Missing | No table. | All of it: colored labels on people and orgs, separate from deal and lead labels, filterable | — | CRM-01, PIP-12 | — | Contacts.dc.html (labels) |
| CRM-15 Source fields | Missing | No table. for leads and deals. `account_products.attribution` (l.72, filled from `org.attribution` l.233–235) records where a customer came from, which is not a lead or deal source | All of it: source on leads and deals from the 13 listed origins; filled automatically on creation; kept through conversion and archive; a reporting dimension | — | LEA, PIP-03, PIP-13, INS | — | Deals.dc.html (Source column/option); Contacts.dc.html |
| CUS-01 Custom fields | Missing | No table, no route | All of it: 16 field types on 6 entity groups; field groups; shown in add forms and details; options per field (reference 1,000); field count as entitlement; appears in forms, filters, reports, import and API without a deploy | `count_limits`; (field count via `plan_gates`, not listed) | ENT-02, PIP-12, CRM-09, INT, INS | — | Settings.dc.html («Data fields», types, 1,000) |
| CUS-02 Field quality rules | Missing | No table. | All of it: important/required, optionally from a stage; description info icon; required enforced on manual edits and reported on API/import; stage move blocked by empty required fields | (a required rule blocks; no register row, see 06-QUESTIONS) | CUS-01, PIP-02 | — | Settings.dc.html (required/important); Deals.dc.html |
| CUS-03 Pipeline-specific and read-only fields | Missing | No table. (no per-field access; DB access model is admin-only via `app.is_admin()` l.32) | All of it: field limited to pipelines; read-only or hidden per user; enforced in the database; no channel leaks a hidden field | — | CUS-01, PIP-02, SEC, INT, MCP, CRM-10 | — | Settings.dc.html (read-only, visibility) |
| CUS-04 Formula fields | Missing | No table. | All of it: numeric/monetary deal fields computed from others; recalculated on input change; no self-reference; stored value equals formula | — | CUS-01, PIP-03 | — | Settings.dc.html (`[deal.value] * [deal.probability] / 100`); Deals.dc.html («formula · value × probability») |
| CUS-05 Languages and locale | Conflict | Platform: locale is `no` unless cookie `lang=en` (`lib/i18n/request.ts:9`); time zone fixed `Europe/Oslo` for everyone (`request.ts:10`); `no` is the source language (`CLAUDE.md:12–13`); catalog is `messages/no.json`, `messages/en.json`; `<html lang>` follows it (`app/layout.tsx:18`) | Spec: English is the default; language, date and number format and time zone are per user; catalog-extensible; switch without reloading data. Code: Norwegian default, per-browser cookie (not per user), fixed time zone, no date or number format choice. Partly met: a translation catalog exists with two languages and no locale routing | — | Appendix 2 decision, SEC (user profile) | — | Settings.dc.html («Language and currencies», state `lang: 'English'`); the design is authored in English |
| CUS-06 Currencies | Missing | No table. | All of it: deals and products in major and custom currencies; company default; stored exchange rates; report-time conversion | — | PIP-03, CRM-07, INS | — | Settings.dc.html (currencies, exchange rates) |
| CUS-07 Module switches and rule settings | Missing | No table. (no settings registry, no module table; `app.installations.enabled` l.52 switches a product connection, not a module; `app.audit` l.136 requires a product and a `x.y` command, l.140–141, and is written only by `record_command`, l.271). Orgpuls `settings.*` commands set Orgpuls's own notice/indexing, not this register | All of it: module on/off (hidden from nav, API returns a disabled error); registry of every rule in the register below with defaults unrestricted; changes logged; Products off hides it for all users; no feature blocked by defaults | all register keys | A9, SF-34, UF-29, SEC | — | Settings.dc.html («Rules and limits», «Modules», change log); Sentral Admin.dc.html |
| CUS-08 Sandbox | Missing | No seed, demo tenant or sample-record flag in the repo (no `supabase/seed*`; grep for Lumio/Kari outside `design-reference/` finds nothing) | All of it: a separate test company; optional sample records marked and removable in one step; equals the seeded demo tenant (Lumio AS / Kari Nordmann per R8); never customer data; sandbox changes never touch live | — | R8, Appendix 2 (seeded demo tenant), AUT | — | Settings.dc.html («Sandbox»); Sentral Admin.dc.html (sample data) |

### Settings register (from "Settings managed in CUS-07", l.684–702)

There is no settings registry in the platform (No table; context file). Keys are taken from the design (`admin-data.js` `SA.settings`). The brief gives none.

| Key | Default per spec | Applies to | Status | Evidence |
| --- | --- | --- | --- | --- |
| `contact_rule`: Contact rule (No rule; source and basis required; opt-in only) | No rule | CRM-01, CRM-04, LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, MTG-05, MOB-01 | Missing |
| `import_consent`: Consent source on import (Off; required per row) | Off | CRM-09 | Missing |
| `sales_consent`: Consent and suppression checks on sales email (Off; warn; block) | Off | COM-07, AUT-07, AUT-12 | Missing |
| `tracking`: Email open and click tracking (On; off; per email) | On | COM-06 | Missing |
| `form_tracking`: Form tracking fields (UTM, cookies, referrer) (On; off) | On | LGN-03 | Missing |
| `web_ident`: Web visitor identification (On; off) | On | WEB-01 to WEB-04 | Missing |
| `second_admin`: Second-admin approval for bulk deletes and merges (Off; on) | Off | PIP-10, CRM-11, CRM-12 | Missing |
| `count_limits`: Count limits from the source (Unlimited; a number) | Unlimited | AUT-05, AUT-07, COM-07, INT-04, DOC-05, CUS-01, PRO-03 | Missing |
| `plan_gates`: Plan gates and usage limits (All on and unlimited; per plan) | All on and unlimited | ENT-01, ENT-02 | Missing |
| `api_rate`: API rate limits (Off; source values; custom) | Off | INT-03 | Missing |
| `safeguards`: Workflow loop protection, webhook retry and ban policy (Source values; custom; off) | Source values | AUT-09, INT-04 | Missing |
| `firewall`: Anonymity firewall (Fixed) | Fixed | Every feature (platform constant) | Partial |
| `typed_reason`: Typed reason for CRM actions (Off; on) | Off | Every CRM write and read of customer data; the audit row itself is always written | Missing |
| `widget_consent`: Consent-gated loading of site widgets (Off; on) | Off | LGN-05 | Missing |
| `rec_notice`: Recording consent notices to attendees (On with 24 h; custom; off) | On with 24 hours' notice | MTG-02, MTG-08 | Missing |

### Counts per status

Features (49): Implemented 0 · Partial 1 (CRM-01) · Missing 47 · Conflict 1 (CUS-05) · Unknown 0.
Settings (15): Implemented 0 · Partial 1 (`firewall`) · Missing 14 · Conflict 0 · Unknown 0.
Questions: 18.

## Part 2 — Features: LEA, COM, AUT, INS, PRO

Phase A, A3.5 rows for INSTRUCTIONS.md lines 704–1017 (49 feature IDs). Judged against the repository
`/home/user/owntheagenda_admin` only (HEAD `8c01aec`). Settings keys come from the table "Settings managed in
CUS-07" (INSTRUCTIONS.md l.684–702). Design screen comes from grepping `design-reference/sentral/project/*.dc.html`;
every ID's `r` (route) in `coverage-data.js` agrees with it, and that file's description, rules and acceptance text

**E0: common evidence for every row (searched, absent).** The platform's tables are only `app.admins`,
`app.products`, `app.installations`, `app.accounts`, `app.account_products`, `app.subscriptions`, `app.members`,
`app.usage_daily`, `app.events_in` and `app.audit` (`supabase/migrations/0001_foundation.sql` l.18–145), plus
`app.intake_nonces` (`0002_product_secrets.sql` l.9). It has no view, no trigger other than `audit_fixed`
(0001 l.148–154), no cron and no storage bucket. Its functions are `public.ingest_events` (0001 l.173),
`record_command` (l.271), `installation_of` (l.281), `admin_whoami` (l.292), `platform_status` (l.302),
`store_product_secrets` and `product_secret` (0002 l.27, l.58). Its routes are `app/page.tsx` (the status page),
`app/login`, `app/mfa` and `app/ingen-tilgang`. Public paths are `/login` and `/ingen-tilgang` only
(`middleware.ts` l.10). The runtime dependencies (`package.json` l.17–26) include no mail, calendar,
telephony, chart, export or AI library. The only tests are `tests/signing.test.ts`, and `supabase/tests/` is
empty. No lead, email, mailbox, template, workflow, sequence, report, dashboard, goal, feed, score or
enrichment object exists anywhere in the repository.

All rows have Work package "—" (Phase B).

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LEA-01 Leads inbox | Missing | E0. The only customer object is `app.accounts` (0001 l.58–64: name, org_number). People exist only as `app.members`, a product's own users (l.98–109). | All of it: a separate lead object linked to a person or organization; a list with title, person/org, value, labels, owner, source and next activity; sortable columns, filters and an archive toggle; custom fields shared with deals; never shown in a pipeline before conversion. | — (Plan gates and usage limits only if leads become a module switch, CUS-07) | CRM-01, CRM-15, CUS-01, PIP-01, ACT-01, LEA-02 | — | Contacts.dc.html (Leads tab, lead archive toggle, columns Lead/Value/Labels/Source) |
| LEA-02 Lead labels | Missing | E0 | All of it: colour-coded labels (several per lead), bulk edit, label sets editable with the settings permission, and a label filter. | — | LEA-01, SEC (settings permission), PIP-06 (shared label model?) | — | Contacts.dc.html (lead labels, leadLabelFilter) |
| LEA-03 Convert lead and deal | Missing | E0 | All of it: lead → deal in a chosen pipeline and stage; deal → lead; notes, activities, emails and files follow in both directions; the converted deal shows the full history. | — | LEA-01, PIP-02, PIP-03, ACT-01, CRM-05, CRM-06, COM-02 | — | Contacts.dc.html ("Convert to deal" dialog); Deals.dc.html ("Convert back to lead · history kept") |
| LEA-04 Lead creation and import | Missing | E0. Orgpuls' `contact.submitted` and `demo.requested` events can arrive in `app.events_in`, but `ingest_events` keeps unknown kinds unprojected (0001 l.261–262). No lead is created from them. | All of it: lead creation manually, by import, the API, web forms, chatbot, live chat, prospect search and web visitors, each setting the source field. | Web visitor identification and Form tracking fields apply through the channels (WEB, LGN); Contact rule (if the lead's person is created as a contact) | CRM-09, CRM-15, INT-03, LGN-01..05, WEB-01..04, PRO (prospect search), LEA-01 | — | Contacts.dc.html (Leads, import column "Lead · source"); Automation.dc.html ("Lead added · source = chatbot"); Inbox.dc.html ("Create lead") |
| LEA-05 Lead email | Missing | E0 (no mail provider, no mailbox, no email table) | All of it: send and receive email on a lead, linked after conversion, through sync or the BCC drop-box; a reply appears on the lead. | — | LEA-01, LEA-03, COM-01, COM-02 | — | Contacts.dc.html ("Email" on the lead); Inbox.dc.html (thread linked to "Lead L-503") |
| LEA-06 Messaging inbox and social connector | Missing | E0 | All of it: a shared inbox for messaging channels, each conversation linked to a lead or contact and convertible to a lead; a LinkedIn connector listed beside it. The connector's functions are undefined in the spec. | — | COM-13, LEA-01, CRM-01, INT (connector platform) | — | Inbox.dc.html (WhatsApp channel, "LinkedIn connector" panel: "leads and contacts the same way once defined") |
| COM-01 BCC drop-box | Missing | E0. No inbound-mail endpoint among `supabase/functions/` (orgpuls-events, product-command, secret-intake). | All of it: a private address per user and per deal; storing and matching mail to person and open deal; registered alternative sender addresses; an unlinked list for manual linking. | — | CRM-01, PIP-03, mail provider adapter (inbound), ACT-01 | — | Inbox.dc.html ("BCC", "drop-box", "sender addresses") |
| COM-02 Two-way email sync and inbox | Missing | E0. Only reusable piece: Vault holding secrets (0002 l.27–65), scoped to product secrets by the name regex in l.43 and l.62. It cannot hold mailbox tokens as written. | All of it: Gmail/M365/Exchange/IMAP connection; read, send and reply inside the CRM; automatic and manual linking to deals, leads and projects; private or shared visibility per conversation; folder, start-date and alias choice; sent mail logged as an activity; tokens encrypted. | — | CRM-01, PIP-03, LEA-01, PRJ, ACT-01, mail/calendar provider adapters, SEC (visibility) | — | Inbox.dc.html ("＋ Gmail · Microsoft 365 · Exchange · IMAP", "Connected mailboxes", "two-way sync") |
| COM-03 Multiple mailboxes | Missing | E0 | All of it: several accounts in one inbox, sender chosen per email, and the sending account recorded; an account-count entitlement. | Plan gates and usage limits (the register lists only ENT-01/02; see 06-QUESTIONS) | COM-02, ENT-01, ENT-02 | — | Inbox.dc.html (Connected mailboxes list, sender select) |
| COM-04 Team inbox | Missing | E0 | All of it: a shared mailbox read and answered by several users; settings for viewers and repliers, default visibility, sync start and folders; a team-inbox entitlement. | Plan gates and usage limits | COM-02, SEC-07/SEC-09 (who can view/reply), ENT-01 | — | Inbox.dc.html ("Team inbox · salg@"); Settings.dc.html |
| COM-05 Templates, signatures and merge fields | Missing | E0 | All of it: private and shared templates and starter templates; merge fields for deal, person, organization and user; personalized hyperlinks; a signature per account; a missing merge value flagged before sending. | — | COM-02, CRM-01, PIP-03, CMP-02 (shared template store) | — | Inbox.dc.html (Template select, "Merge field", signature «Tor · Orgpuls») |
| COM-06 Open and click tracking | Missing | E0 | All of it: open and click tracking with real-time notice to the sender; per-email switch-off; reports caveat prefetch opens; on by default, switchable in settings. | Email open and click tracking (default On) | COM-02, CUS-07, mail provider adapter, notifications | — | Inbox.dc.html ("Track opens and clicks", "Open and click tracking: on (setting)") |
| COM-07 Group emailing | Missing | E0 | All of it: one email sent individually to many recipients from list views or the timeline with a template; each copy linked to the record; needs sync and the bulk-edit permission; optional consent and suppression check. | Consent and suppression checks on sales email (Off); Count limits: recipients per group email (Unlimited) | COM-02, COM-05, CRM-02, PIP-10, SEC (bulk-edit permission), CMP-04/CMP-08 (suppression model) | — | Inbox.dc.html ("recipients · template … · merge field", group source "Segment") |
| COM-08 Email scheduling and outbox | Missing | E0 (no scheduler or cron) | All of it: scheduled send; edit or cancel until sent; failed sends show the provider's reason and can be retried. | — | COM-02, a job runner, mail provider adapter | — | Inbox.dc.html (outbox "Scheduled", "failed", "Retry") |
| COM-09 Labels, archiving and warnings | Missing | E0 | All of it: email labels; two-way archive state with Gmail; thread status; missing-attachment warning. | — | COM-02 | — | Inbox.dc.html (label options, Archive, status "Waiting on you"/"Replied", "Missing attachment?") |
| COM-10 Meeting scheduler | Missing | E0. Middleware lets only `/login` and `/ingen-tilgang` through without aal2 (middleware.ts l.10–14), so no page reachable by a contact exists. | All of it: a booking page from availability; general and proposed-times links; confirmation to both; linked activity; configurable duration, hours, time zone and questions; booked slots vanish at once; links usable in signatures, templates and automated email. | — | ACT-01, ACT-09, COM-05, COM-11, a public booking route | — | Activities.dc.html ("Meeting scheduler" tab, "Confirm booking", "Recent bookings") |
| COM-11 Video call links | Missing | E0 | All of it: a video link created automatically for a scheduled meeting via Zoom, Teams or Meet adapters. | — | COM-10, ACT-01, video provider adapters | — | Activities.dc.html (videoOpts "Google Meet", "Teams", "Zoom") |
| COM-12 Calling | Missing | E0 | All of it: click-to-call through a telephony adapter with a default provider; calls logged as activities with outcome, duration and recording link; web-to-phone handoff; incoming caller matching. | — | ACT-01, CRM-01, MOB-01, telephony adapter | — | Inbox.dc.html ("Calls" channel, call button) |
| COM-13 Messaging | Missing | E0 | All of it: WhatsApp Business conversations linked to deals and contacts with approved templates, quick replies, labels, delivery/read status, reactions, media, attachments and owner notification. | — | LEA-06, CRM-01, PIP-03, messaging provider adapter, notifications | — | Inbox.dc.html ("WhatsApp" channel, chats list) |
| COM-14 Mail client add-ons | Missing | E0 | All of it: a Gmail side panel and a browser extension to view and add contacts, deals, notes and activities. | — | CRM-01, PIP-03, ACT-01, CRM-06, INT-03 (API) | — | Inbox.dc.html ("Gmail side panel and browser extension") |
| AUT-01 Workflow builder | Missing | E0. The "lifecycle-messaging engine" that AUT says already exists (INSTRUCTIONS.md l.834) is not in this repository. | All of it: a canvas with trigger, conditions and steps; name, description, owner, draft/active; copy-paste of steps; active-workflow entitlement; runs on the next matching event. | Plan gates and usage limits | AUT-02..07, a job runner, ENT-01 | — | Automation.dc.html (Workflows, Builder tabs) |
| AUT-02 Event triggers | Missing | E0. `app.events_in` (0001 l.122–133) is a table of product events in, unique on (product, source_id) with `product` referencing `app.products`. Under CLAUDE.md rule 4 events enter only through a product's events function. No CRM entity events exist. | All of it: workflow start on add, update or delete of deal, person, activity, lead, organization or project (18 pairs); field-change filter on update; workflow-made changes chain within loop limits. | Technical safeguards: workflow loop protection (Source values) | AUT-01, AUT-09, PIP, CRM-01, ACT-01, LEA-01, PRJ, events model | — | Automation.dc.html (triggers "Deal update", "Organization update", "Lead added") |
| AUT-03 Date triggers | Missing | E0 (no cron or scheduled job) | All of it: start on, before or after a date field of a deal, person, activity or organization, evaluated on a schedule at run time; a 30-days-before-renewal case. | — | AUT-01, CUS-01 (date fields), a scheduler | — | Automation.dc.html ("before" date option) |
| AUT-04 Conditions | Missing | E0 | All of it: AND/OR filters on the trigger and related records; email opened/answered conditions; re-check where a step says so; suggested and custom conditions; a failing record starts no run. | — | AUT-01, COM-06, PIP-12 (filter model) | — | Automation.dc.html ("Condition" node) |
| AUT-05 Delay and wait-for | Missing | E0 | All of it: a duration or until-date delay with weekend skip; wait-for until a condition holds; up to 10 delays and 90 days per path; wait-for gives up after 7 days with a stated reason. | Count limits: delays per workflow path (Unlimited). The 90-day and 7-day caps are not in the register. | AUT-01, AUT-04, a scheduler | — | Automation.dc.html ("Delay", "Wait" nodes) |
| AUT-06 If/else branches | Missing | E0 | All of it: condition split into paths, one path per branch per run; branch-count entitlement. | Plan gates and usage limits | AUT-01, AUT-04 | — | Automation.dc.html ("branch") |
| AUT-07 Actions | Missing | E0. The platform's only outbound call is `product-command` to Orgpuls (supabase/functions/product-command/index.ts). | All of it: create, update or delete person, org, lead, deal, activity; email from template with preview, sent from the sender's synced mailbox; add note; campaign and project actions; webhook POST/PUT/DELETE with key-value or raw JSON; Slack/Teams post; Asana/Trello task; ≤10 actions per path; field values from the trigger; errors in run history. | Consent and suppression checks on sales email (Off); Count limits: actions per workflow path (Unlimited) | AUT-01, AUT-09, COM-02, COM-05, CMP, PRJ, INT-04, Slack/Teams/Asana/Trello adapters | — | Automation.dc.html (actions list ends 'Campaign action', 'Project action', 'Webhook', 'Slack', 'Teams'; no Asana or Trello found) |
| AUT-08 Workflow templates | Missing | E0 | All of it: a purpose-grouped template library; short setup that saves an editable draft; the starting set is a product decision. | — | AUT-01 | — | Automation.dc.html (Templates tab, e.g. 'Churn prevention', 'Pipeline hygiene', 'Delivery handover') |
| AUT-09 Monitoring and limits | Missing | E0. `app.audit` records product commands with ok/error (0001 l.136–145), not workflow runs. No job monitor exists. | All of it: per-run history with step results; overview of most failed, most active and never-run workflows; health trend for today, 7 and 14 days; owner alert on failure; rolling 10-minute loop caps (10,000 per company, 5,000 per workflow); webhook step history with final body and path; failing step linked. | Technical safeguards: workflow loop protection, webhook retry and ban policy (Source values) | AUT-01, AUT-07, INT-04, notifications, job monitor (admin spec) | — | Automation.dc.html (Monitoring tab, "health", "Failed", "Loop protection · On · Source values") |
| AUT-10 Ownership and sharing | Missing | E0. Roles are only owner/admin (0001 l.20). No users-as-sales-reps, no teams, no permission sets. | All of it: workflow runs with the owner's permissions; share, activate for users or a team, transfer; global admins edit any; a create permission held only by admins by default; transfer prompt on user deactivation; owned-by filters; notice to both on transfer. | — | AUT-01, SEC-07, SEC-09, notifications | — | Automation.dc.html (Owner column, Transfer) |
| AUT-11 Automatic assignment | Missing | E0 | All of it: rules on lead added and deal added/updated (pipeline/stage change); assignee user, team round-robin, org owner or person owner; priority order with first match; conditions on deal, lead, person and org fields; evaluation history. | — | LEA-01, PIP-03, CRM-01, SEC-09 (teams) | — | Automation.dc.html (Assignment rules tab: 'Sales team · round-robin', organization's owner) |
| AUT-12 Sequences | Missing | E0 | All of it: a drag-and-drop linear flow of email steps (auto or manual) and activity steps, with weekend-skipping delays; enrol one, bulk or by workflow; end on reply, stage change or manually; skip or stop; automatic signature; sequence entitlement; per-record step and status. | Consent and suppression checks on sales email (Off); Plan gates and usage limits | AUT-01, COM-02, COM-05, ACT-01, LEA-01, PIP-03 | — | Automation.dc.html (Sequences tab); Feed.dc.html (sequence emails waiting) |
| INS-01 Report builder and types | Missing | E0. No SQL view exists in 0001 or 0002, so the "admin's SQL views" (INSTRUCTIONS.md l.915, l.340) are absent. `platform_status` returns counts only (0001 l.302–325). | All of it: 17 report types; measure, view-by, segment-by, filters (incl. does-not-contain), period; measures incl. weighted value, conversion rate, time to win, sales velocity; visibility-scoped; one definition per metric; figures match list views. | — | PIP, ACT, LEA, CRM-01, CMP, PRJ, PIP-11, SEC (visibility), metric views | — | Insights.dc.html (Report builder tab) |
| INS-02 Charts | Missing | E0 (no chart library in package.json l.17–26) | All of it: column, bar, pie, scorecard (with change against the previous period) and table (configurable, sortable columns); editable colours; pie has no view-by; switching type keeps data and filters. | — | INS-01 | — | Insights.dc.html (isColumn, Bar, Pie, scorecard) |
| INS-03 Dashboards | Missing | E0 | All of it: a grid with move and resize; a default dashboard, custom dashboards and role templates; duplicating reports, goals and dashboards; copying a shared report; dashboard-wide period/user filters; custom-dashboard entitlement; reopens as arranged. | Plan gates and usage limits | INS-01, INS-02, INS-05, SEC-07 (roles) | — | Insights.dc.html (Dashboards tab, Duplicate) |
| INS-04 Sharing and collaboration | Missing | E0. Every page except `/login` and `/ingen-tilgang` requires a session with aal2 (middleware.ts l.10–46). CLAUDE.md rule 2 allows a new public path only "with a reason written beside it". | All of it: viewer/editor sharing; a public live link for people without an account, revocable at once, showing the owner's data scope. | — | INS-01, INS-03, SEC (users), a public route | — | Insights.dc.html (Share, "Public live" link) |
| INS-05 Goals | Missing | E0. No users-as-reps or teams (0001 l.18–23). | All of it: goals on deals (added, progressed, won), activities (added, completed) and forecast (weighted revenue); assignee user, team or company; pipeline, frequency, duration, count or value target; team goals need teams; stage goals in the pipeline view; progress equals matching records. | — | PIP-02, ACT-01, PIP-11, SEC-09, INS-03 | — | Insights.dc.html (Goals tab) |
| INS-06 Forecast reports | Missing | E0. `app.subscriptions` holds plan, interval and dates but no amount (0001 l.80–95), so a product revenue forecast cannot be computed from it. | All of it: deal revenue forecast from value and expected close date, optionally weighted by stage probability; product revenue forecast from recurring products and installments; totals reconcile with PIP-11. | — | PIP-03, PIP-11, CRM-07, CRM-08, billing mirror | — | Insights.dc.html (Forecast tab, "Product revenue", "installments on won deals · MRR by month") |
| INS-07 Custom-field reporting | Missing | E0 (no custom fields, CUS-01) | All of it: custom fields as dimensions, filters and measures (averages of numeric/monetary); several conditions per field; new fields reportable without configuration; an entitlement in the source. | Plan gates and usage limits | CUS-01, INS-01 | — | Insights.dc.html ("Custom field") |
| INS-08 Export | Missing | E0 (no export library) | All of it: chart export as PNG or PDF; data as CSV or XLSX; drill-down from a chart segment to its rows with export; follows the export permission; exported rows equal the chart's rows. | — | INS-01, INS-02, CRM-10, SEC (export permission) | — | Insights.dc.html (PNG, XLSX export) |
| INS-09 AI report generation | Missing | E0 (no language-model adapter) | All of it: a typed request produces an editable report definition; ready-made prompts; refinement in chat; custom fields named in the request; the model returns a definition, never numbers. | Anonymity firewall (Fixed: AI context reaches CRM data only, R6) | INS-01, INS-07, AIA, language-model adapter | — | Insights.dc.html ("Ask for a report" tab) |
| INS-10 Capacity and freshness | Missing | E0. `app.usage_daily` (0001 l.111–118) is an event-fed daily table for product usage, not a report rollup. | All of it: live data in reports; a reports-per-user entitlement; rollup tables refreshed by events; a deal change shows without manual refresh. | Plan gates and usage limits | INS-01, events model, ENT-01 | — | Insights.dc.html ("Live data · same visibility rules · reports per user: unlimited") |
| PRO-01 Feed | Missing | E0 | All of it: three tabs of next-best steps on open deals (follow-ups: replies, no reply after 5 days, today's activities, opens, clicks, waiting sequence emails; overlooked: no follow-up, overdue; opportunities: new deals with no activity); scope set once; cards generated from events, appearing and leaving with their condition. | — | PIP-03, ACT-01, COM-02, COM-06, AUT-12, events model | — | Feed.dc.html (Feed tab: Follow-ups, Overlooked, Opportunities) |
| PRO-02 Feed actions | Missing | E0 | All of it: quick actions (schedule task, send email, open deal); side panel with deal, activities and contacts; done-today counter; filters by stage, card type and score; completing removes the card. | — | PRO-01, PRO-03, ACT-01, COM-02, PIP-04 | — | Feed.dc.html ("done today", side panel) |
| PRO-03 Scoring models | Missing | E0. No health score exists in this repository. `app.usage_daily` and `app.events_in` hold product signals (0001 l.111–133) but nothing computes a score. | All of it: a 0–100 deal score from +25/+10/−10 criteria with AND/OR; matched-criteria preview; one pipeline per model, one active model per pipeline; model-count entitlement; health score and product events as criteria; score updates on field change. | Count limits: score models (Unlimited); Plan gates and usage limits | PIP-02, PIP-03, CUS-01, health score (admin spec), events model | — | Feed.dc.html (Scoring models tab, "+25", "+10", "−10", Health); Settings.dc.html ('Scoring models', 3) |
| PRO-04 Company enrichment | Missing | E0. `app.accounts` has only name and org_number (0001 l.58–64). No register sync or data-provider adapter exists, so the "existing register sync" (INSTRUCTIONS.md l.350) is absent. | All of it: fill empty address, industry, employees, revenue, LinkedIn and website; never overwrite; hideable default fields; data provider or public register via adapter; credits; source logged. | Plan gates and usage limits (credit allowance; see 06-QUESTIONS) | CRM-01, CUS-01, PRO-06, data-provider/register adapter | — | Feed.dc.html (Enrichment tab: "Brønnøysund", "register", "provider (adapter)", "Apply … fields · 1 credit") |
| PRO-05 Person enrichment | Missing | E0 | All of it: find email and phone from name, organization and LinkedIn; stored with source and date; new contact data follows the contact-rule setting; credits. | Contact rule (No rule); Plan gates and usage limits (credits; see 06-QUESTIONS) | CRM-01, PRO-06, data-provider adapter | — | Feed.dc.html (Enrichment tab) |
| PRO-06 Bulk enrichment and credits | Missing | E0. `app.subscriptions` (0001 l.80–95) mirrors Orgpuls customers' billing, not this platform's own credit cycle. | All of it: up to 100 records at once from a list view; monthly allowance reset per billing cycle; top-ups; refusal before any provider call when credits are short; credits used equal records enriched. | Plan gates and usage limits (credits); the 100-record cap is not in the register | PRO-04, PRO-05, PIP-10 (list views), ENT-01, ENT-02 | — | Feed.dc.html ("Credits this cycle"); Settings.dc.html (Plans and usage: 'Enrichment credit…') |
| PRO-07 Reverse lookup | Missing | E0 | All of it: for mail from an unknown sender, propose a new person and organization with enriched fields; accepting creates linked records; uses PRO-04/05 limits. | Contact rule (No rule); Plan gates and usage limits (credits) | COM-01, COM-02, PRO-04, PRO-05, CRM-01 | — | Feed.dc.html ("Reverse lookup · email from an unknown sender") |

### Counts

- Implemented: 0
- Partial: 0
- Missing: 49
- Conflict: 0
- Unknown: 0

## Part 3 — Features: AIA, MTG, MCP, CMP, PRJ, LGN, WEB, DOC

Scope: `docs/crm-enrichment/INSTRUCTIONS.md` lines 1018–1355 (51 feature IDs), judged against the platform
repository `/home/user/owntheagenda_admin` only. Settings register: INSTRUCTIONS.md lines 684–702
("Settings managed in CUS-07").

### What the platform has that these modules could touch (read in full for this part)

- `supabase/migrations/0001_foundation.sql`: tables `app.admins` (l.18, role `owner|admin` only, l.20),
  `app.accounts` (l.58), `app.account_products` (l.66), `app.subscriptions` (l.80), `app.members` (l.98,
  customer users: email, name, role — no consent field), `app.usage_daily` (l.111), `app.events_in` (l.122),
  `app.audit` (l.136, append-only trigger l.154; shape is product-command only: `product not null`,
  `command ~ '^[a-z]+\.[a-z_]+$'`, l.139–141). `public.ingest_events` (l.173) stores unknown event kinds raw
  and does nothing else with them (l.262 "kept as it arrived") — this is where Orgpuls'
  `contact.submitted`, `demo.requested` and `support.requested` land today.
- No AI/LLM provider, transcription, mail provider, storage bucket, cron/job runtime, OAuth server, native
  app, design tokens (`tailwind.config.ts` l.3 "Placeholder tokens"), CRM table, settings registry or
  per-user permission model exists in the repository (tracked-file list; `git ls-files`).
- Tests: `tests/signing.test.ts` only (HMAC/JWT signing). No test touches any feature in this part.

Every row below is therefore **Missing**. No sentence of any of these 51 specifications is met by code in
this repository. Where the brief says "the admin already has" something (CMP intro l.1140, WEB intro

Settings that apply to **every** row and are not repeated per row: *Anonymity firewall* (fixed),
*Typed reason for CRM actions* (every CRM write and read of customer data), and the CUS-07 module
switch for the row's module (a switched-off module disappears from navigation and its API returns a
disabled error, l.674–676).

Design screens are named from `design-reference/sentral/project/*.dc.html` by grepping each feature's
concepts; `coverage-data.js` (which carries a route key `r` per feature ID) was used to confirm the

### Table

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AIA-01 Assistant chat | Missing | No AI gateway, model provider, chat route or history table in repo. `app.audit` (0001:136–146) cannot record a CRM read (product/command-shaped). | All of it: chat on every screen (text and voice), answers on account data, summaries, drafts, explanations, history; retrieval under the asking user's permissions; cited records; survey data out of reach; audited reads; never returns data the user cannot open. | Anonymity firewall; Typed reason for CRM actions | AI gateway (SF-24), SEC (per-user permissions), CRM-01, LLM provider (open point 2) | — | Sentral Admin.dc.html (global "Assistant" panel, "Reads CRM data you may see"); coverage-data.js r=assistant |
| AIA-02 AI notifications | Missing | Nothing in repo (no deals, activities, forecast, AI). | All of it: deal-advance estimate cards with reason, stalled/slipping flags, one-click next action; daily progress panel (tasks, calls, activities) and month panel (new, won, forecast); account-wide switch to hide AI scoring; each card links to the deal and its action works. | Not in register: "hide AI scoring" | PIP-03, PIP-11, ACT-01, AI gateway, job runtime | — | Feed.dc.html (Stalled, Slipping, Forecast, progress today/month) |
| AIA-03 Email writer | Missing | No composer, no AI. | All of it: prompt + tone (professional, formal, friendly) + length (short, standard, long) draft in the prompt's language; inserted for editing, never sent; uses linked deal and person context. | — | COM (composer), PIP-03, CRM-01, AI gateway | — | Inbox.dc.html (tone/length selects, aiPrompt) |
| AIA-04 Email summary and replies | Missing | No mail threads, no AI. | All of it: per-thread summary, sentiment, readiness-to-buy 1–10 with reason, action items, suggested replies; on demand; reflects the latest message. | — | COM-01/02 (threads), AI gateway | — | Inbox.dc.html (summary, score /10, sentiment, Readiness, Action items, Suggested replies) |
| AIA-05 Import mapping | Missing | No import, no field definitions. | All of it: suggested column→field mapping incl. option fields; user confirms; mappings editable and logged. | — | CRM-09, CUS-01, AI gateway | — | Contacts.dc.html (import, mapping, Suggested) |
| AIA-06 Integration recommendations | Missing | No integration catalog; Platform screen not built. | All of it: suggestions from the catalog, natural-language search over it, drawing on tools in use and what similar companies use; search returns matching entries. | — | INT-11, AI gateway | — | Platform.dc.html (catalog, Recommend) |
| AIA-07 Card scanner | Missing | No mobile app, no storage bucket, no contacts table. | All of it: mobile photo of a business card → contact draft with several phones/emails; user reviews before save; image stored on contact; follows contact rule; correct editable draft. | Contact rule | MOB-01, MOB-06, CRM-01, CRM-05, OCR/AI provider, storage | — | Mobile.dc.html ("Capture … AIA-07 … card scanner", "Business card", "Contact draft saved") |
| MTG-01 Pre-call brief | Missing | No meetings, calendar, mail or AI. | All of it: brief from deal history, past emails, earlier conversations, contact and organization data; changed-since checklist; user free-form instructions; unlinked meetings flagged; exists before start and cites sources. | — | ACT-01, ACT-09, COM-01/02, MTG-08 mailbox, AI gateway, job runtime | — | Meetings.dc.html (brief, "Since the last contact", "Who you meet") |
| MTG-02 Notetaker bot | Missing | No calendar integration, no bot provider. | All of it: bot joins Meet/Zoom/Teams from calendar as visible participant ~2 min before start, records; owner can remove it; consent notice emails to attendees (24 h default); joins meetings with a link, leaves when removed. | Recording consent notices to attendees | ACT-09, INT-05/06, meeting-bot provider (open point 2), job runtime (open point 3), open point 5 | — | Meetings.dc.html (notetaker, "Bot joins", "Notice due tomorrow"); Settings.dc.html (notetaker) |
| MTG-03 Desktop capture | Missing | Repo is a Next.js web app only; no desktop client. | All of it: macOS/Windows desktop app recording system audio without a bot (VoIP, phone, in person); user controls participant notices; recording appears in the same workspace. | Recording consent notices (applicability unclear, see 06-QUESTIONS) | MTG-08, transcription provider, desktop client toolchain | — | Meetings.dc.html ("Desktop capture") |
| MTG-04 Transcript and recap | Missing | No transcription, notes or Slack integration. | All of it: timestamped speaker transcript; recap with takeaways and next steps saved as a note on the linked deal/person/org; action item jumps to the moment; Slack message when ready; attached to the right record. | — | MTG-02/03/06, CRM-06, INT-07 (Slack), transcription provider, AI gateway | — | Meetings.dc.html (transcript, Recap) |
| MTG-05 CRM update suggestions | Missing | No CRM records, no custom fields, no approval flow. | All of it: proposed field/label/new-contact changes beside current values; nothing written until approved (item or all); new contact follows contact rule; approved items written and logged with the meeting as source. | Contact rule | MTG-04, CUS-01, CRM-01, CRM-14, PIP-04 (changelog with source), AI gateway | — | Meetings.dc.html ("6 suggestions", Accept) |
| MTG-06 Transcript upload | Missing | No upload handling, no storage. | All of it: upload an externally recorded transcript and get the same recap and suggestions. | — | MTG-04, MTG-05, storage | — | Meetings.dc.html ("Upload transcript") |
| MTG-07 Unscheduled calls | Missing | No desktop client. | All of it: ad hoc recording without a calendar event from the desktop app, no maximum duration, linkable to a deal afterwards. | Recording consent notices (applicability unclear, see 06-QUESTIONS) | MTG-03, PIP-03 | — | Meetings.dc.html ("Unscheduled calls", "Start recording") |
| MTG-08 Workspace and controls | Missing | No per-user permission model: `app.admins.role` is `owner\|admin` only (0001:20). No mailbox connection. | All of it: workspace with upcoming, post-meeting actions and history; on by default per user, admins switch off per user; one permission for all features; own mailbox connection for briefs; user without permission sees no workspace. | Recording consent notices to attendees; not in register: per-user on/off | SEC-07 (roles/permissions, open point 10), INT-05/06, open point 5 | — | none found |
| MCP-01 MCP server | Missing | No OAuth server, no MCP endpoint, no API, no sync index, no job runtime. | All of it: MCP endpoint with OAuth login; 30-minute sync index over deals, leads, contacts, pipelines, activities, email, products, users, custom fields, automations, reports; every call as the connected user, counts against API limits; CRM data only; assistant can only see/change what the user can. | API rate limits; Anonymity firewall | INT-01..03, SEC, job runtime, all CRM entities | — | Platform.dc.html ("AI connector (MCP)", "https://sentral.orgpuls.no/mcp · OAuth login"); Security.dc.html (audit row "Claude (MCP)") |
| MCP-02 Tool catalog | Missing | No API definitions to generate from. | All of it: get/list/add/update/search tools for activities, deals, people, orgs, leads, products, stages, notes, plus lead→deal; names and schemas generated from API definitions; every tool has a schema and structured results. | — | MCP-01, INT-01/02, LEA-03 | — | Platform.dc.html (MCP block) |
| MCP-03 Admin controls | Missing | No settings registry. | All of it: company-level MCP switch; off blocks new connections and removes existing; does not affect API tokens or other integrations; after switch-off no assistant call succeeds. | Not in register | MCP-01, CUS-07 | — | Platform.dc.html (toggleMcp switch) |
| CMP-01 Email builder | Missing | No templates, mail, or editor. | All of it: drag-and-drop rows and blocks (title, paragraph, list, image, button, divider, social, HTML, video, icons, menu); row border/background/padding; blank or layout start; desktop and mobile preview; non-removable footer with postal address and unsubscribe; preview equals delivery. | Not in register: fixed footer | CMP-02, storage (images), sending provider | — | Marketing.dc.html (builder, Block, footer, html) |
| CMP-02 Templates | Missing | Nothing. | All of it: ready-made layouts, saved template library, code-your-own HTML; stored as data and versioned; a template starts a campaign. | — | CMP-01, COM-05 (shared template store per Part B l.345) | — | Marketing.dc.html (template) |
| CMP-03 Audience | Missing | No people/contacts table (only `app.members`, 0001:98, customer users with no consent or engagement field). | All of it: recipients by CRM filters over people incl. engagement and location; one shared contact list; only subscribed addresses receive mail; count equals subscribed matches. | Not in register: subscribed-only rule | CRM-01, PIP-12 (segments), CMP-04 | — | Marketing.dc.html |
| CMP-04 Marketing status and consent | Missing | No consent record, status or suppression list. | All of it: seven statuses (no consent, subscribed, unsubscribed, bounced, pending DOI, pending upgrade, archived); single/double opt-in; every change logged with time and source; derived from the consent record (basis, date); suppression on every campaign; unsubscribed never mailed. | Consent and suppression checks on sales email (for the sales-email part only) | CRM-01, consent record (Appendix 2), CMP-06 (bounces) | — | Marketing.dc.html (Subscribed, double opt-in, Pending, Bounced, No consent); Contacts.dc.html |
| CMP-05 Scheduling and sending | Missing | No sending provider, no marketing stream, no job runtime. | All of it: send now or at set time via a provider on a marketing stream separate from transactional; subscriber allowance is an entitlement, overflow waits as pending; scheduled campaign leaves on time. | Plan gates and usage limits (subscriber allowance via ENT-01/02) | Sending provider (open point 2), job runtime (open point 3), ENT-01/02 | — | Marketing.dc.html (Schedule, stream, Transactional) |
| CMP-06 Campaign analytics | Missing | No provider events ingestion for mail. | All of it: delivered, bounced, unsubscribed, spam, total/unique opens and clicks, open/click/CTR, top locations; owner engagement notifications; needs tracking on; hard bounce or 5 soft bounces → bounced; figures match provider events. | Email open and click tracking (register lists COM-06 only; see 06-QUESTIONS) | CMP-05, provider webhooks, CMP-04 | — | Marketing.dc.html (open rate, click rate, Spam, Top locations) |
| CMP-07 Automated campaigns | Missing | No workflow engine. | All of it: campaign email as a workflow step with delays; audience from the workflow; obeys consent status. | — | AUT-01..07, CMP-04, open point 1 (one engine) | — | Automation.dc.html (Campaign); Marketing.dc.html |
| CMP-08 Deliverability | Missing | No sender domain, DNS check or provider account. | All of it: sender domain authentication with DNS checks, account verification before first send, compliance recommendations, list hygiene warnings; unauthenticated domain cannot send. | Not in register: send block on unauthenticated domain | Sending provider, CMP-05 | — | Marketing.dc.html (DKIM, SPF, DMARC, Verif, hygiene) |
| CMP-09 Campaign insights | Missing | No Insights, no campaigns. | All of it: campaign performance and conversion reports in Insights, filter by campaign type, comparison of two or more campaigns in one chart matching each campaign's report. | Plan gates and usage limits (comparison is a higher tier in source) | INS-01..10, CMP-06 | — | Marketing.dc.html (Compare); Insights.dc.html (Campaign) |
| PRJ-01 Boards and phases | Missing | Nothing. | All of it: kanban boards with phases, several boards; phases added/renamed/reordered/deleted like stages; drag changes phase and logs it. | — | PIP-02 (stage pattern), audit/changelog | — | Projects.dc.html (board, phase, drag) |
| PRJ-02 Project record | Missing | Nothing. | All of it: title, board, phase, owner, dates, labels, description, custom fields, links to deals, one person, one org; create from won deal with AI-drafted brief reviewed by the user; shows the deal and contacts. | — | PIP-03, PIP-07, CRM-01, CUS-01, AI gateway | — | Projects.dc.html ("Won deal", brief) |
| PRJ-03 Work items | Missing | Nothing. | All of it: tasks (optional owner, start/due, several assignees), subtasks with mandatory parent, milestones, activities (date, time, owner, calendar sync); parent not auto-completed unless set. | — | ACT-01, ACT-09 | — | Projects.dc.html (task, milestone); subtasks not found in screens (coverage-data.js only) |
| PRJ-04 Dependencies and timeline | Missing | Nothing. | All of it: dependencies between tasks/milestones without cycles; Gantt by month with dependency lines; drag a phase/group to shift it keeping spacing; overdue highlighted. | — | PRJ-03 | — | Projects.dc.html (gantt, Depend, shift, Timeline) |
| PRJ-05 Project templates | Missing | Nothing. | All of it: reusable plans with relative due dates by phase/group; save a project as template; template project gets dated items from its start date. | — | PRJ-01..04 | — | Projects.dc.html (template) |
| PRJ-06 Project health | Missing | Nothing. | All of it: on track / at risk / off track / on hold, manual or AI-suggested from emails, notes, tasks, activities with recommendations; AI summary enabled per account, regenerable; status on board and in reports. | Not in register: "AI summary enabled per account" | AI gateway, INS | — | Projects.dc.html (On track, At risk, Off track, On hold) |
| PRJ-07 Collaboration and sharing | Missing | No notes, files, mentions, notifications or PDF generation. | All of it: notes, files, @mentions, emails on a project; one-click AI status report PDF with only what the sender includes; mention notifies the user. | — | CRM-05, CRM-06, COM, AI gateway, storage | — | Projects.dc.html (Note, file, mention, Status report, PDF) |
| PRJ-08 Bulk work and import | Missing | Nothing. | All of it: paste a list into tasks (date in a line becomes due date) in the chosen phase; bulk edit; import/export incl. from other project tools. | — | PRJ-03, CRM-09, CRM-10 | — | Projects.dc.html (Paste, Import) |
| PRJ-09 Automation and reports | Missing | No workflow engine, no Insights. | All of it: projects/tasks as workflow triggers and actions; project performance and duration reports; workflow creates a project when a deal is won. | — | AUT, INS, PIP-07 | — | Projects.dc.html (Workflow, Duration, Report); Automation.dc.html ("Create project") |
| LGN-01 Chatbot | Missing | No site widget, no leads. | All of it: playbook bot in three steps (theme, profile, template: leads, meetings, qualify/route, live chat); per-page questions; creates lead/deal, assigns owner, books meetings; qualified leads top of owner's inbox; per-step drop-off; completed conversation stores answers on a lead. | — (widget loading governed by LGN-05's setting) | LEA-01, AUT-11, COM-10, LGN-05 | — | Marketing.dc.html (Chatbot, playbook); Automation.dc.html; Settings.dc.html |
| LGN-02 Live chat | Missing | No realtime channel, no mobile app. | All of it: rep takes over in real time (web or mobile); unassigned queue for a set time then bot fallback; online message; claimed chat locked to one rep and saved on the lead. | — | LGN-01, MOB, LEA-01 | — | Marketing.dc.html (Live chat); Mobile.dc.html; Settings.dc.html |
| LGN-03 Web forms | Missing | Orgpuls' `contact.submitted` events reach `app.events_in` (0001:122) but are stored raw only (0001:262); no ticket, prospect, lead, form builder or notification follows. | All of it: form builder (input/message blocks; contact, registration, gated download, file upload, blank; mandatory intro block); fields incl. marketing status and custom fields, optionally required; embed/link/share; ID and active status; submission → lead/deal, owner emailed, owner kept on resubmission; UTM, cookies, referrer, landing page, hidden page variables; fixed language; reuse of the contact-form → ticket + consented prospect path (which does not exist here, see 06-QUESTIONS); views/interactions/submissions/conversion counted. | Form tracking fields (UTM, cookies, referrer) | LEA-01, LEA-04, CUS-01, CMP-04, tickets (Appendix 2), storage (file upload) | — | Marketing.dc.html (form, UTM, Gated, Introduction) |
| LGN-04 Prospect search | Missing | No external data provider, no credits, no leads. | All of it: person and organization filters over a licensed database, saved filters, credit-based reveal adding to leads inbox; one credit per reveal creates a lead; follows contact rule. | Contact rule; Plan gates and usage limits (credits) | Prospect data provider (open point 2), LEA-01, ENT | — | Marketing.dc.html (prospect, reveal, credit, Job title) |
| LGN-05 Embedding and consent | Missing | No script, no public site in this repo. | All of it: one script loading chatbot, live chat and tracking; consent wording and cookie notice on forms/widgets; consent-gated loading setting off by default; with it on and consent declined no tracking cookie; never loaded in the survey flow (fixed). | Consent-gated loading of site widgets; Anonymity firewall | LGN-01..03, WEB-01, Orgpuls public site | — | Marketing.dc.html (script, consent, cookie, survey) |
| WEB-01 Tracker | Missing | No tracker, no web events table. | All of it: script on one or more sites recording visits and pages, sites told apart by hostname, never in the survey flow; visits appear under their site. | Web visitor identification; Anonymity firewall | LGN-05, Orgpuls public site | — | Marketing.dc.html (visitor, site); Analytics.dc.html |
| WEB-02 Organization identification | Missing | Nothing; no IP-to-company source. | All of it: match visits to companies, filter ISPs/crawlers/irrelevant traffic; company counted once per month for billing; hourly refresh; known company IP → named visitor. | Web visitor identification; Plan gates and usage limits (monthly company count) | WEB-01, IP-to-company provider (open point 2), job runtime | — | Marketing.dc.html (visitor list, ISP filtering) |
| WEB-03 Visitor inbox and ranking | Missing | Nothing. | All of it: company list with location, industry, last visit, source, pages, activity ranking; filters for period, country, campaign, page, already-in-CRM; quality sort puts most active first. | Web visitor identification | WEB-02, CRM-01 | — | Marketing.dc.html (Visitor, "in CRM") |
| WEB-04 Convert and reveal | Missing | Nothing. | All of it: visitor → lead, deal or organization linked to visit history; prospect search for people at the company using credits. | Web visitor identification; Contact rule | WEB-03, LEA-03, LGN-04, CRM-01 | — | Marketing.dc.html (reveal, prospect) |
| DOC-01 Templates and merge fields | Missing | No templates, products, deals, or drive connection. | All of it: document/spreadsheet/presentation templates with deal, person, org, product, project placeholders; named, categorized, company-wide; import from drive; split address fields; missing value flagged before sending; generated document contains deal data. | — | PIP-03, CRM-07, PRJ-02, DOC-03 | — | Documents.dc.html (Template, placeholders); Deals.dc.html (merge field) |
| DOC-02 Product tables | Missing | No product catalog. | All of it: template table filled with the deal's products, prices, discounts, tax, totals; configurable columns; not in spreadsheet templates; totals equal deal value. | — | CRM-07, PIP-03, CUS-06 | — | Documents.dc.html (Product, Total); Deals.dc.html |
| DOC-03 Cloud storage | Missing | No storage bucket, no Google/Microsoft OAuth. | All of it: create/store in Google Drive, OneDrive, SharePoint (personal or shared); company default shared location; generated PDFs always stored in platform; new document appears in drive. | — | INT-05, INT-06, platform storage | — | Documents.dc.html (Drive, OneDrive, SharePoint); Platform.dc.html |
| DOC-04 Trackable links | Missing | No public link endpoint, no deal timeline. | All of it: share document/PDF through a link recording each open and notifying the owner; links can be disabled; open logged with time on the deal. | — | DOC-01/03, PIP-04, notifications | — | Documents.dc.html (Link, Open); Deals.dc.html; Feed.dc.html |
| DOC-05 E-signatures | Missing | Nothing. | All of it: requests to up to 10 signers with one-time email code, custom message, invite language, drag-and-drop signer fields; sealed document with audit trail; signed PDF and trail stored on the deal; legal signature level to be confirmed. | Count limits taken from the source (signers) | DOC-01, storage, mail provider, e-signature evidence provider (open point 2), open point 5 | — | Documents.dc.html (Signer, One-time code, audit trail, Invite language, drag) |
| DOC-06 Branding and external signing | Missing | Nothing. | All of it: removable platform branding; external e-signature service through an adapter; status of an externally sent document shown on the deal. | — | DOC-05, adapter pattern (Part G l.2508) | — | Documents.dc.html (Branding, External, adapter) |

### Counts

- Implemented: 0
- Partial: 0
- Missing: 51 (AIA 7, MTG 8, MCP 3, CMP 9, PRJ 9, LGN 5, WEB 4, DOC 6)
- Conflict: 0
- Unknown: 0

Questions: 17

## Part 4 — Features: SEC, INT, MOB, ENT; Part F data model and API; Part G non-functional requirements

Phase A, read-only. Platform repository `/home/user/owntheagenda_admin` at `8c01aec`. Sources read in full: INSTRUCTIONS.md
l.41–370 (A1–A12, Part B), l.632–703 (CUS and the CUS-07 register), l.1356–1577 (SEC, INT, MOB, ENT), l.2385–2600
(Part F, Part G); every tracked file outside `design-reference/` (47 files). `supabase/tests/` exists but is empty. No
database was introspected (the remote project was not queried; Phase A forbids changes and no local database exists), so
drift between `0001`/`0002` and the live schema is not established.

Abbreviations: `0001` = `supabase/migrations/0001_foundation.sql`, `0002` = `supabase/migrations/0002_product_secrets.sql`,
`PC` = `supabase/functions/product-command/index.ts`, `OE` = `supabase/functions/orgpuls-events/index.ts`.

Two register rows apply to every ID and are not repeated per row: **Anonymity firewall** (fixed) and **Typed reason for CRM
actions** (off). Nothing in this scope can be Implemented: the repository has 4 vitest unit tests (`tests/signing.test.ts`),
no database tests, no end-to-end tests and no screenshots.

---

#### 1. Features — SEC, INT, MOB, ENT

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SEC-01 Security dashboard | Missing | No login log table, no sessions read, no security page. Only page is the status page `app/page.tsx:12-106` (installations, counts, events, commands) | All of it: live sessions and locations; 7-day new devices/locations/security events/forced logouts; risk assessment with fixes; admin-only; each figure opens its list; figures match the login log | — | SEC-04 (login log), SEC-02, SF-27, UF-15 | — | `Security.dc.html` tab "Security dashboard" |
| SEC-02 Security alerts | Missing | No email provider, no job runtime, no security events (`0001` has no such table; `ingest_events` handles product events only, `0001:225-263`) | All of it: email alerts on new device/location, invite, >3 failed logins, password reset, large exports/deletions; immediate or digest; one alert per trigger to admins | none in register (the ">3 failed logins" threshold is a number from the source — see 06-QUESTIONS) | SEC-04, email provider (open point 2), job runtime (open point 3), SF-27 | — | `Security.dc.html` tab "Alerts and rules" |
| SEC-03 Security rules | Missing | Password sign-in only `app/login/actions.ts:16`; no IP/time check in `middleware.ts:12-52`; no Supabase Auth config in the repo (no `supabase/config.toml`) | All of it: company-wide password strength/expiry/reuse; IP and time restrictions; preview of affected users; a login from a blocked IP is refused. Supabase project-level password policy, if any, is not in the repo | none in register; IP/time restrictions are restrictions under R5 but are not listed | SEC-04, SF-27, UF-15 | — | `Security.dc.html` tab "Alerts and rules" (Security rules list) |
| SEC-04 Device and login history | Missing | No login log. `signOut` ends only the local session: `app/login/actions.ts:21-25` (`scope: 'local'`) | All of it: per user devices, locations, IPs, time, method, session end for 60 days; remote log-out that ends a session at once; separate from record changelogs | — | SF-27, login_log entity (Part F) | — | `Security.dc.html` tab "Device and login history" |
| SEC-05 Single sign-on | Missing | Email + password only `app/login/actions.ts:9-19`; no OAuth/SAML provider code or callback route | All of it: SAML (Entra ID, Okta), Google sign-in; fallback admin login; IdP-provisioned user logs in without local password | — | SEC-06, SF-27 | — | `Security.dc.html` tab "SSO and two-factor" |
| SEC-06 Two-factor authentication | Partial | **Met:** "a second factor at login by … authenticator app" — TOTP enrol/verify `app/mfa/actions.ts:14-23` (TOTP only, l.20), `:27-33` (`challengeAndVerify` l.31), `app/mfa/page.tsx:9-11`. **Met in effect:** "with enforcement on, no user can log in without the second factor" — every non-public path requires aal2 `middleware.ts:43-46` (public: `/login`, `/ingen-tilgang`, l.10; fails closed l.22-26, 48-51); every RPC requires aal2 via `app.is_admin()` `0001:32-36`; `PC:53-57` refuses non-admin. No test covers any of it | Not met: email-code factor; an admin control to enforce it (enforcement is hard-wired, always on — CLAUDE.md:21-22); account recovery (no recovery codes; a lost device has no path); remembered login email (only browser `autoComplete`, `app/login/LoginForm.tsx:16`). No test | none in register; MFA cannot be a switch that lowers protection (R7) — see 06-QUESTIONS | SEC-05, SF-27, UF-15 | — | `Security.dc.html` tab "SSO and two-factor" |
| SEC-07 Permission sets | Missing | `app.admins.role` is `owner`\|`admin` `0001:20` but is never read: `app.is_admin()` ignores it `0001:32-36`; no other role check in `app/`, `lib/`, `supabase/` | All of it: named sets of actions per app (deals, projects, campaigns) and global; admin/regular/custom; actions create/edit/delete/import/export/bulk edit/change visibility/view reports; custom-set count an entitlement; enforced in UI and API. The four baseline roles (super-admin, support, finance, analyst) do not exist | Plan gates and usage limits (number of custom sets) | SEC-08, SEC-09, ENT-02, SF-01, open point 10 | — | Orgpuls `0049`: enum `app.platform_role` (super_admin, support, finance, analyst), `app.is_platform_admin(roles[])`; `marketing` added in `0055_crm.sql:37`, `editor` in `0125_editor_role.sql:6`; route `app/(admin)/admin/admins` |
| SEC-08 Visibility groups | Missing | No groups, no owner columns. Every table RLS on with **no policy** `0001:156-165`; reads go through SECURITY DEFINER functions (`0001:4-7`, CLAUDE.md:17-20), which bypass RLS | All of it: groups and sub-groups; per-item visibility (owner, group, group+sub-groups, everyone); defaults per record type; pipelines limited to groups; placeholder setting; custom-group count an entitlement; "enforced by row-level security" conflicts with the repository's definer-function pattern | Plan gates and usage limits (custom groups) | SEC-07, SF-01, all record modules | — | `Settings.dc.html` section "Visibility groups" |
| SEC-09 Users and teams | Partial | **Met (partly):** staff list = `app.admins` (email, role, active) `0001:18-23`; a deactivated admin (`active=false`) gets no admin identity `0001:29`, so every RPC refuses and the page sends them to `/ingen-tilgang` `app/page.tsx:13-15` — "a deactivated user cannot log in" holds for access, though Supabase Auth still signs them in. Users are added by hand in the Supabase dashboard + SQL (README.md:27-28) | Not met: invite, deactivate, replace and reassign screens/RPCs; teams with manager and members; copy access; user overview (followed items, last login); own profile and phone; workflow-transfer prompt (AUT-10); "records keep an owner" (no owned records exist). No test | — | SEC-07, SEC-08, AUT-10, SF-43, UF-15 | — | `Settings.dc.html` section "Users and teams" |
| SEC-10 Data protection | Partial | **Met:** EU hosting for the database — eu-central-1 (README.md:11, CLAUDE.md:11); isolation of CRM data from survey data — a separate project/database holding no survey table (`0001` table list l.18-136; `0001:9-10`; CLAUDE.md:33-35); in transit — HSTS `next.config.ts:28`, https-only Supabase URL `lib/supabase/env.ts:8`, https-only product URL `0001:49`; secrets at rest in Vault `0002:46-50`, `0002:58-65` | Not met / not established: encryption at rest of the database (provider-managed, not in repo — see 06-QUESTIONS); backups and stated RPO/RTO (not in repo); restore test (AC) — none. Vercel and edge-function regions not configured in repo (no `vercel.json`). Design shows "EU · Stockholm (eu-north-1)" and "RPO 1 h · RTO 4 h" | — | open point 8, SF-43 | — | `Security.dc.html` tab "Data protection" |
| SEC-11 Privacy compliance | Missing | No export/erasure function, no consent log, no retention job, no sub-processor list. `org.deleted` only marks `account_products.status='deleted'` `0001:231-232`; `app.members` email/name rows stay (cascade only fires if `account_products` rows are deleted, `0001:108`, which nothing does); `member.left` keeps email/name `0001:255-257` | All of it: export and erasure of a person on request; consent logs; retention rules; sub-processor list; erasure across emails, recordings, transcripts, enrichment; AC "removes the person from every module". Today's ingest retains customer users' personal data indefinitely | Contact rule / Consent source on import are adjacent (CRM-01, CRM-09), not listed for SEC-11 | CRM-12, SF-15, SF-43, MTG-08 | — | `Security.dc.html` tab "Privacy compliance" |
| INT-01 REST API | Missing | Only endpoints: `PC` (one POST that forwards an allow-listed Orgpuls command, `PC:21-95`), `OE` (inbound events), `secret-intake`; and RPCs `admin_whoami`, `platform_status` `0001:292-327` | All of it: versioned list/get/create/update/delete/search for every entity incl. custom fields; filtering, pagination; published reference, client libraries, collections; generated from the registry; every UI record action available | API rate limits; Plan gates and usage limits | SEC, ENT, event catalog, CUS-01 registry, SF-22 | — | `Platform.dc.html` tab "REST API and tokens" |
| INT-02 Authentication | Missing | No API tokens or OAuth apps. Existing tokens are internal: a 2-minute HS256 command token to Orgpuls `supabase/functions/_shared/orgpuls.ts:51-53`, `_shared/signing.ts:62-67`; staff Supabase session JWT | All of it: one personal API token per user in a header; OAuth 2.0 with scopes; rotation invalidates at once; revoked token/grant refused | Plan gates and usage limits (API tokens, ENT-02) | SEC-07, SF-22, UF-16 | — | `Platform.dc.html` tab "REST API and tokens" |
| INT-03 Rate limits | Missing | No rate limiting. Only size caps: ingest ≤500 events `0001:190`, `OE:48`; body ≤200 kB `PC:32`, ≤1 MB `OE:118-120` | All of it: daily token budget (base × plan multiplier × seats), cost per endpoint type, 2-second burst limit, 429 with limit headers, 75 %/100 % emails, usage dashboard; off by default | API rate limits (default Off) | INT-01, INT-02, ENT-03 (plan multiplier), SF-22 | — | `Platform.dc.html` tab "REST API and tokens" ("Rate limits Off (setting)") |
| INT-04 Webhooks | Missing | Inbound only: `OE` verifies an HMAC-signed POST from Orgpuls (`OE:30-40`, `_shared/signing.ts:41-58`). No outbound subscriptions, deliveries or retries | All of it: subscriptions by action and object; POST with current and previous state; source limits as settings (40 per user, 10 s timeout, retries 3/30/150 s, 30-min ban after 10 failures, deletion after 3 days); SSRF block (A7.7). `hmacHex` (`signing.ts:27`) could sign payloads if Tor decides to (A4) | Count limits (webhooks per user); Technical safeguards (retry and ban policy) | event catalog, outbox (SF-02), SF-23, job runtime | — | `Platform.dc.html` tab "Webhooks" |
| INT-05 Google Workspace | Missing | No provider connection, no OAuth client, no token storage | All of it: contacts, calendar, tasks, Drive, Gmail, Meet, sign-in; connect and revoke per user | Contact rule (via CRM-04) | COM-02, ACT-09, CRM-04, DOC-03, SEC-05, A7.8 token encryption | — | `Platform.dc.html` tab "Integration catalog" |
| INT-06 Microsoft 365 | Missing | As INT-05 | All of it: Outlook/Exchange mail, calendar, contacts, Teams links and notifications, OneDrive, SharePoint; connect and revoke per user | Contact rule (via CRM-04) | As INT-05 | — | `Platform.dc.html` tab "Integration catalog" |
| INT-07 Team chat | Missing | Nothing | All of it: deal events to Slack/Teams channels or DMs; search from chat; also a workflow action; won deal posts | — | PIP-07, AUT-07, event catalog | — | `Platform.dc.html` tab "Integration catalog" (Team chat); `Automation.dc.html` |
| INT-08 Invoicing | Missing | No accounting adapter. `app.subscriptions` mirrors Orgpuls billing `0001:80-95`, not invoices | All of it: invoice in the accounting system from a deal with person, organization and products; status on the deal; adapter; carries the deal's lines | — | PIP-03, CRM-07, open point 2 | — | `Platform.dc.html` catalog "Accounting system (EHF)"; `Deals.dc.html` (Invoice composer tab, Invoices history) |
| INT-09 Automation platforms | Missing | Nothing | All of it: no-code platform connectors on the API and webhooks; a new deal triggers an external automation | — | INT-01, INT-02, INT-04 | — | `Platform.dc.html` catalog "No-code automation platforms" |
| INT-10 App extensions | Missing | Nothing | All of it: panels in deal and contact views; link/dialog/embedded actions; sandboxed; scope-limited data | — | INT-02, PIP-04, CRM-01 | — | `Platform.dc.html` catalog "App extensions" |
| INT-11 Integration catalog | Missing | `app.installations` (product, api_url, public_key, enabled) `0001:47-54` lists connected *products*, shown read-only on `app/page.tsx:39-50`; that matches the design's "Applications" tab, not the catalog | All of it: catalog grouped in collections and tagged; access shown; install, settings, per-user management, removal that revokes access; third-party apps beside first-party | — | INT-02, INT-10, AIA-06 | — | `Platform.dc.html` tab "Integration catalog" |
| MOB-01 Core app | Missing | No mobile client, no public API to serve one | All of it: iOS/Android pipeline, deals, leads, contacts, activities, detail, filters, search, real-time sync, portrait/landscape, phone-contact import; same permissions; change on mobile appears on web without refresh | Contact rule (MOB-01 listed) | INT-01, PIP, ACT, CRM, LEA, SF-44, UF-21 | — | `Mobile.dc.html` ("Deal on the go") |
| MOB-02 Focus view | Missing | Nothing | All of it: overdue, unread count, nearby count, today/week, home-screen widget; counts match web filters | — | MOB-01, ACT, COM-02, MOB-03 | — | `Mobile.dc.html` ("Focus") |
| MOB-03 Nearby | Missing | Nothing | All of it: map of nearby deals/orgs/people, filters incl. address custom fields, navigation hand-off, location permission; tap opens record | — | MOB-01, CRM-03, CUS-01 | — | `Mobile.dc.html` ("Nearby") |
| MOB-04 Calls and texts | Missing | Nothing | All of it: in-app calls logged as activities (iOS outgoing only), caller matching, text hand-off | — | MOB-01, COM-12, ACT-01 | — | `Mobile.dc.html` ("Deal on the go") |
| MOB-05 Offline mode | Missing | Nothing | All of it: offline edits of deals, notes, activities; sync on reconnect and manual; latest change wins with earlier value in changelog | — | MOB-01, CRM-02 changelog, SF-31 | — | `Mobile.dc.html` (offline toggle) |
| MOB-06 Capture | Missing | Nothing; no storage buckets | All of it: audio notes with transcription, note scanner, photo/file upload, share-in, card scanner; scanned note saved on chosen record | Contact rule (via AIA-07) | MOB-01, AIA-07, CRM-05, transcription provider | — | `Mobile.dc.html` ("Capture") |
| MOB-07 Push notifications | Missing | Nothing; no `device_token` | All of it: reminders, assignments, mentions, chat requests; per-type configuration; one push per assignment | — | MOB-01, ACT-04, AUT-11, CRM-06, LGN-02 | — | `Mobile.dc.html` ("Notifications") |
| MOB-08 Mobile extras | Missing | Nothing | All of it: live chat takeover, project tasks, statistics dashboard; rep answers live chat from phone | Consent-gated loading of site widgets (via LGN-05) | MOB-01, LGN-02, PRJ-03, INS-03 | — | `Mobile.dc.html` ("Extras") |
| ENT-01 Feature gating | Missing | No entitlement table, no feature flags | All of it: feature on/off per plan and add-on; checked in UI, API and workflow engine; gated feature unavailable everywhere; default all on | Plan gates and usage limits (default all on, unlimited) | SEC, billing, CUS-07, SF-16, UF-28 | — | `Settings.dc.html` ("Entitlements — features per plan and add-on"); `Platform.dc.html` tab "Feature flags" |
| ENT-02 Usage limits | Missing | No counters. `app.usage_daily` `0001:111-118` holds Orgpuls customers' daily counts, not CRM limits | All of it: metered limits per company/seat (leads and deals … API tokens); unlimited until set; enforced at creation | Plan gates and usage limits; Count limits taken from the source | ENT-01, every counted module, SF-16 | — | `Settings.dc.html` section "Plans and usage" |
| ENT-03 Plans, add-ons and top-ups | Missing | "Existing billing" here is only the mirror `app.subscriptions` (plan, trial, cancel fields) `0001:80-95` fed by `billing.changed` `0001:236-248`, plus Orgpuls `billing.*` commands `orgpuls.ts:14-17`; none of it models CRM plans | All of it: seat plans; add-ons per company/seat/volume; credit top-ups; free trial; buying an add-on enables at once. Whose plans these are in an internal back-office is unclear | Plan gates and usage limits | ENT-01, ENT-02, PRO-06 credits, billing | — | `Settings.dc.html` ("Add-on" column); `Feed.dc.html` (credit top-up) |
| ENT-04 Usage screen and limit handling | Missing | Nothing | All of it: consumption against every limit; block new additions at a limit, delete nothing; overflow to waitlist/import skip file; warnings; matches actual counts | Plan gates and usage limits | ENT-02, PIP-16, CRM-09, SF-16 | — | `Settings.dc.html` ("Usage against every limit") |

---

#### 2. Part F — Data model and API

#### 2.1 Conventions

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Product ID on every row | Partial | `product` column on `app.installations` `0001:48`, `account_products` `:67`, `subscriptions` `:81`, `members` `:99`, `usage_daily` `:112`, `events_in` `:124`, `audit` `:140` | Absent on `app.admins` `0001:18`, `app.accounts` `0001:58` (cross-product by design, README.md:3), `app.intake_nonces` `0002:9`. Column is named `product`, Appendix 2 says product ID |
| Access only through role checks, never bypassing RLS | Conflict | `app.is_admin()` `0001:32-36`; RLS on/no policy `0001:156-165` | The repository's rule is RLS-on-no-policy plus SECURITY DEFINER RPCs (`0001:4-7`, CLAUDE.md:17-20). Definer functions bypass RLS by construction, so "never by bypassing RLS" and A8's per-role RLS tests contradict the established pattern |
| No FK or grant from any CRM table to survey response tables | Partial | whole database | Holds structurally today: no survey table exists in this project; the product's event registry forbids respondent fields (Orgpuls `0205_platform_api.sql:76-99`); command allow-list excludes answer exports (`orgpuls.ts:8-44`, test `tests/signing.test.ts:43`). Not met: the database test A8/R6 demands (none) |
| Owner, visibility, created, updated, deleted on business records | Partial | `app.accounts` created/updated `0001:62-63`; `app.account_products` created/deleted_at `0001:73-74` | No owner, visibility or version on any table; `members`/`subscriptions` have only `updated_at` |
| Custom field values in JSON keyed by field ID, indexed; definitions in `custom_field` | Missing | none (`jsonb` columns `account_products.details/attribution` `0001:71-72` are product payloads, not field-keyed) | No `custom_field` table, no per-field index |
| Configuration as versioned rows | Missing | none | No pipelines, workflows, sequences, reports, templates, score models or permission sets |
| Soft delete 30 days, then permanent removal | Missing | `account_products.status`/`deleted_at` `0001:70,74` mark a product-side deletion only | No purge job, no cron, no restore |
| Row + changelog + event in one transaction; read audit row; version column | Missing | `public.ingest_events` `0001:173-266` writes event + projection in one function call (inbound only); `public.record_command` `0001:271-276` | No changelog, no outbox; the command audit is written after the remote call in a separate RPC and a failed audit is only logged (`PC:84-92`); reads (e.g. `platform_status`) are not audited; no version column |

#### 2.2 Entities

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Identity: platform admin with role and MFA | Partial | `app.admins` `0001:18-23`; `app.admin_email()` `:25-30`; `app.is_admin()` `:32-36` | Role is owner/admin and unused; MFA is session-level (aal2), not a column. Baseline 4 roles absent |
| Identity: audit log | Partial | `app.audit` `0001:136-145`, trigger `:148-154` | Records product commands only (actor, product, command, arg names, ok, error). No reads, no target org/record, no reason column. `service_role` holds ALL incl. TRUNCATE `0001:163` and the trigger covers UPDATE/DELETE only, so TRUNCATE bypasses append-only |
| Identity relationship: staff identities separate from customer logins; admin role never derived from a customer role | Partial | `app.admins` matched to `auth.users` of this project `0001:28`; customers are `app.members` rows, not auth users `0001:98-109` | Holds structurally (separate project). No test |
| Identity: team | Missing | none | |
| Identity: team_member | Missing | none | |
| Identity: visibility_group | Missing | none | |
| Identity: permission_set | Missing | none (extend `app.admins.role` `0001:20`) | |
| Records: organization (org.nr, product ID) | Partial | `app.accounts` (name, `org_number` 9 digits unique) `0001:58-64`; product link via `app.account_products` `0001:66-77` | Org.nr present; product ID on the link table, not on the account. No notes, tags, owner, deleted, version. Created only by product events `0001:215-223` |
| Records: contact (type, role, source, consent basis) | Partial | `app.members` (product, tenant_id, user_id, role, email, name, active) `0001:98-109` | Customer users only (member.joined/left). No type, source, consent basis; keyed by product user id, not a person; no prospects. Part B says contacts exist with these fields — not here |
| Records: suppression list | Missing | none |
| Records: organization_relation | Missing | none |
| Records: label | Missing | none |
| Records: follower | Missing | none |
| Sales: pipeline | Missing | none |
| Sales: stage | Missing | none |
| Sales: deal | Missing | none |
| Sales: deal_participant | Missing | none |
| Sales: deal_stage_history | Missing | none |
| Sales: lead | Missing | none |
| Sales: lost_reason | Missing | none |
| Sales: saved_filter | Missing | none |
| Products: product | Conflict | `app.products` `0001:41-45` already means *installed software products* (key, name; seeded `orgpuls` `0001:329`) |
| Products: product_price | Missing | none |
| Products: deal_product | Missing | none |
| Products: revenue_schedule | Missing | none; recurring revenue source would be `app.subscriptions` `0001:80-95` (Part B: "comes from the billing mirror") |
| Products: currency | Missing | none |
| Products: exchange_rate | Missing | none |
| Activities: activity | Missing | none |
| Activities: activity_type | Missing | none |
| Activities: activity_guest | Missing | none |
| History: note | Missing | none |
| History: comment | Missing | none |
| History: file | Missing | none (no storage bucket) |
| History: mention | Missing | none |
| History: changelog | Missing | none |
| Email: mail_account | Missing | none |
| Email: mail_thread | Missing | none |
| Email: mail_message | Missing | none |
| Email: mail_link | Missing | none |
| Email: mail_event | Missing | none |
| Email: mail_template | Missing | none |
| Email: signature | Missing | none |
| Scheduling: availability | Missing | none |
| Scheduling: booking_link | Missing | none |
| Scheduling: booking | Missing | none |
| Calls: call_log | Missing | none |
| Messaging: message_thread | Missing | none |
| Messaging: message | Missing | none |
| Automation: workflow | Missing | none |
| Automation: workflow_version | Missing | none |
| Automation: workflow_run | Missing | none |
| Automation: workflow_step_run | Missing | none |
| Automation: assignment_rule | Missing | none |
| Automation: assignment_log | Missing | none |
| Automation: sequence | Missing | none |
| Automation: sequence_step | Missing | none |
| Automation: enrollment | Missing | none |
| Insights: report | Missing | none |
| Insights: dashboard | Missing | none |
| Insights: dashboard_item | Missing | none |
| Insights: goal | Missing | none |
| Insights: public_link | Missing | none |
| Insights: rollup tables | Missing | `app.usage_daily` `0001:111-118` is a per-tenant daily product rollup, a possible source |
| Prospecting: score_model | Missing | none |
| Prospecting: score_criterion | Missing | none |
| Prospecting: deal_score | Missing | none |
| Prospecting: feed_card | Missing | none |
| Prospecting: enrichment_request | Missing | none |
| Prospecting: credit_ledger | Missing | none |
| Marketing: consent record (existing) | Missing | none |
| Marketing: suppression list (existing) | Missing | none |
| Marketing: segment (existing) | Missing | none |
| Marketing: campaign | Missing | none |
| Marketing: campaign_recipient | Missing | none |
| Marketing: campaign_event | Missing | none |
| Marketing: sender_domain | Missing | none |
| Projects: board | Missing | none |
| Projects: phase | Missing | none |
| Projects: project | Missing | none |
| Projects: project_deal | Missing | none |
| Projects: task | Missing | none |
| Projects: milestone | Missing | none |
| Projects: dependency | Missing | none |
| Projects: project_template | Missing | none |
| Lead generation: chatbot_playbook | Missing | none |
| Lead generation: chat_conversation | Missing | none |
| Lead generation: chat_message | Missing | none |
| Lead generation: web_form | Missing | none |
| Lead generation: form_submission | Missing | none; Orgpuls `contact.submitted` and `demo.requested` events land in `app.events_in` unprojected `0001:261-262` |
| Web visitors: tracked_site | Missing | none |
| Web visitors: visitor_company | Missing | none |
| Web visitors: visit | Missing | none |
| Documents: document_template | Missing | none |
| Documents: document | Missing | none |
| Documents: document_link | Missing | none |
| Documents: signature_request | Missing | none |
| Documents: signer | Missing | none |
| Documents: signature_event | Missing | none |
| Meetings: meeting | Missing | none |
| Meetings: recording | Missing | none |
| Meetings: transcript | Missing | none |
| Meetings: brief | Missing | none |
| Meetings: recap | Missing | none |
| Meetings: update_suggestion | Missing | none |
| Platform: custom_field | Missing | none |
| Platform: translation | Missing | none; UI strings are files `messages/no.json`, `messages/en.json` loaded by `lib/i18n/request.ts:9-10` |
| Platform: setting | Missing | none |
| Platform: import_job | Missing | none |
| Platform: waitlist_item | Missing | none |
| Platform: integration | Missing | `app.installations` `0001:47-54` (per product) is the nearest |
| Platform: installed_app | Missing | as above |
| Platform: device_token | Missing | none |
| Platform: event | Partial | `app.events_in` `0001:122-133` |
| Platform: notification | Missing | none |
| Platform: webhook | Missing | none |
| Platform: webhook_delivery | Missing | none |
| Platform: api_token | Missing | none |
| Platform: oauth_app | Missing | none |
| Platform: oauth_grant | Missing | none |
| Platform: entitlement | Missing | none |
| Platform: usage_counter | Missing | none (`app.usage_daily` is customer product usage) |
| Platform: login_log | Missing | none (Supabase's own `auth.audit_log_entries` is not read by any code) |
| Platform: security_rule | Missing | none |

#### 2.3 Event catalog

The "single typed events table" is `app.events_in` `0001:122-133`. Its kind check `^[a-z]+\.[a-z_]+$` (`0001:126`) is
object.action with a dot; Part F says "object_action naming". Consumers named in Part F (workflows, assignment,
scoring, feed, rollups, webhooks, notifications, alerts, usage page) exist for none of these events.

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Deal: added | Missing | none (`app.events_in` to extend) | |
| Deal: updated | Missing | as above | |
| Deal: stage_changed | Missing | as above | |
| Deal: won | Missing | as above | |
| Deal: lost | Missing | as above | |
| Deal: archived | Missing | as above | |
| Deal: deleted | Missing | as above | |
| Deal: restored | Missing | as above | |
| Lead: added | Missing | as above | |
| Lead: updated | Missing | as above | |
| Lead: converted | Missing | as above | |
| Lead: archived | Missing | as above | |
| Lead: deleted | Missing | as above | |
| Person, organization: added | Missing | as above | Product-side `org.created` / `member.joined` exist (below), not CRM events |
| Person, organization: updated | Missing | as above | |
| Person, organization: merged | Missing | as above | |
| Person, organization: deleted | Missing | as above | Product-side `org.deleted`, `member.left` exist |
| Activity: added | Missing | as above | |
| Activity: updated | Missing | as above | |
| Activity: completed | Missing | as above | |
| Activity: deleted | Missing | as above | |
| Email: received | Missing | as above | |
| Email: sent | Missing | as above | |
| Email: opened | Missing | as above | |
| Email: link_clicked | Missing | as above | |
| Email: replied | Missing | as above | |
| Email: send_failed | Missing | as above | |
| Project, task: added | Missing | as above | |
| Project, task: updated | Missing | as above | |
| Project, task: phase_changed | Missing | as above | |
| Project, task: completed | Missing | as above | |
| Capture: form_submitted | Missing | as above | Orgpuls `contact.submitted` / `demo.requested` arrive and are stored unprojected `0001:261-262` |
| Capture: chat_completed | Missing | as above | |
| Capture: visitor_identified | Missing | as above | |
| Campaign: sent | Missing | as above | |
| Campaign: delivered | Missing | as above | |
| Campaign: bounced | Missing | as above | |
| Campaign: unsubscribed | Missing | as above | |
| Campaign: complained | Missing | as above | |
| Document: generated | Missing | as above | |
| Document: opened | Missing | as above | |
| Document: signed | Missing | as above | |
| Document: completed | Missing | as above | |
| Meeting: scheduled | Missing | as above | |
| Meeting: recorded | Missing | as above | |
| Meeting: recap_ready | Missing | as above | |
| Meeting: updates_approved | Missing | as above | |
| Security: login | Missing | as above | No login log (SEC-04) |
| Security: login_failed | Missing | as above | Login failure returns `{problem:'failed'}` and records nothing `app/login/actions.ts:16-17` |
| Security: user_invited | Missing | as above | |
| Security: password_reset_requested | Missing | as above | No reset flow exists |
| Security: export_run | Missing | as above | |
| Usage: limit_warning | Missing | as above | |
| Usage: limit_reached | Missing | as above | |
| Product (existing): signup | Partial | `org.created` → `app.events_in` + `app.accounts`/`account_products` projection `0001:214-230` | Received and stored; not yet a workflow trigger, scoring signal or feed item |
| Product (existing): trial day | Partial | `billing.changed` `trial_started_at`/`trial_ends_at` → `app.subscriptions` `0001:236-248` | Derivable; no per-day event |
| Product (existing): conversion | Partial | `billing.changed` `confirmed_at` `0001:236-248` | As above |
| Product (existing): churn | Partial | `billing.changed` `cancelled_at`/`cancel_effective_at`; `org.deleted` `0001:231-232` | As above |
| Product (existing): payment status | Missing | none | Not a field of `billing.changed` in Orgpuls' registry (Orgpuls `0205_platform_api.sql:88-90`) |
| Product (existing): organization-level survey aggregates | Missing | none | Orgpuls `usage.daily` is "counts … nothing about any answer or any group" (Orgpuls `0205:91-93`); Part F/G allow aggregates of ≥5 |

#### 2.4 API surface

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Resources (deals … permission sets and settings) | Missing | none | No public API; existing RPCs are `admin_whoami`, `platform_status` (`0001:292-327`), plus service-role-only `ingest_events`, `record_command`, `installation_of`, `store_product_secrets`, `product_secret` |
| Operations (list, get, create, update, delete, search; convert; merge) | Missing | none | |
| Conventions (versioned paths, cursor pagination, field selection, custom fields by key, idempotency keys) | Missing | none | Idempotency exists only inbound: `unique (product, source_id)` `0001:131`, `on conflict do nothing` `0001:203` |
| Authentication (personal token, OAuth 2.0 scopes) | Missing | none | Internal command tokens only (`orgpuls.ts:51-53`) |
| Rate limits (daily budget, 2-s burst; off by default) | Missing | none | Setting "API rate limits" absent |
| Reference values from the source | Missing | none | Only as setting reference values (A9) |
| Webhooks (create/change/delete, current + previous state, retry/ban) | Missing | none | Inbound HMAC verification exists (`signing.ts:41-58`) |
| AI connector (tools generated from API definitions) | Missing | none | Depends on INT-01 registry |

---

#### 3. Part G — Non-functional requirements

| Area | Status | Evidence | Missing or different |
| --- | --- | --- | --- |
| Anonymity firewall | Partial | Separate database with no survey table (`0001` l.18-136); product registry forbids respondent data (Orgpuls `0205:76-99`); command allow-list (`orgpuls.ts:8-44`) and unit test that `answers.export` is refused (`tests/signing.test.ts:41-50`); logs carry no payloads (`OE:10-11`, `PC:93`) | "Proven by automated tests" at the database level: none (`supabase/tests/` empty). Organization-level aggregates of ≥5: not received at all |
| Rule settings | Missing | none | No registry; no setting from the CUS-07 register exists |
| Access | Partial | Mandatory MFA (`middleware.ts:43-46`, `0001:35`); deny-by-default tables (`0001:156-165`); product column on most tables (2.1) | Staff roles from the admin's role model: only owner/admin, unused (`0001:20`, `:32-36`); least privilege per role: none; product ID not on every table |
| Audit | Partial | `app.audit` append-only for UPDATE/DELETE (`0001:136-154`), written per product command (`PC:84-92`) | Not every write (ingest projections, admin table changes) nor any read is audited; no reason column/setting; no run histories; TRUNCATE not blocked (`0001:154`, `:163`); audit failure after the action is only logged (`PC:92`) |
| Data residency | Partial | Database eu-central-1 (README.md:11, CLAUDE.md:11) | Storage (none yet), logs, Vercel region, edge-function region, AI and sub-processors: not stated in repo. Design says Stockholm eu-north-1 |
| Sending | Missing | none | No email provider; no streams |
| Job runtime | Missing | none (no `pg_cron`, no queue, no worker). Orgpuls pushes events every five minutes (README.md:20-21) | Open decision (open point 3) |
| Recovery | Unknown | not in repo | RPO/RTO and restore tests not established (see 06-QUESTIONS, open point 8) |
| Scale | Missing | Only an ingest batch cap of 500 (`0001:190`) | No sizing; source ceilings are reference only |
| Performance | Missing | Timeouts only: 5 s Supabase calls (`lib/supabase/env.ts:18-22`), 20 s product call (`PC:77`), 25 s app→function (`lib/platform/command.ts:28`) | No targets, no measurements (A8 asks Tor) |
| Monitoring | Missing | Status page shows last event time, counts by kind, last 10 commands with errors (`app/page.tsx:51-101`, `0001:302-325`) | No alerts on failed jobs, sync lag, send failures or error rates; no job monitor |
| AI governance | Missing | none | No AI features |
| Privacy | Missing | none | Erasure, recording consent, sub-processor list absent; personal data of customer users retained after `org.deleted` (`0001:231-232`) |
| Destructive actions | Missing | none in the platform UI. `orgs.delete_now` is in the command allow-list (`orgpuls.ts:12`), reachable through `runCommand` by any admin, not yet called from any screen | No preview, soft delete or approval setting in the platform; Orgpuls' `orgs.deletions` (read) could serve as preview |
| Interface language | Conflict | `no` is the source and default; English only by cookie (`lib/i18n/request.ts:9`; CLAUDE.md:12-13) | Spec: English is the default (CUS-05, Part G) |
| Test data | Missing | No seed, no demo tenant; no "Lumio AS"/"Kari Nordmann" outside `design-reference/` and `docs/` | R8 requires the seeded demo tenant; the only configured project is the production one (`.env.example`) |
| Provider independence | Missing | Product connection is per-product (`app.installations`, `orgpuls.ts`), not a third-party adapter layer | No adapters for mail, calendar, sending, telephony, transcription, LLM, data, e-signature |

#### 3.1 Part G architecture choices (verifiable claims about the existing admin)

| Design choice | Status | Evidence / note |
| --- | --- | --- |
| One API for every client | Missing | No public API (2.4) |
| Configuration as data | Missing | No registry |
| Outbox events | Missing | No outbox/dispatcher; inbound events only |
| One workflow engine on the admin's lifecycle-messaging engine | Conflict | No such engine exists in this repository |
| Adapters for providers | Missing | none |
| AI gateway | Missing | none |

#### 5. Counts

Features (34 IDs: SEC 11, INT 11, MOB 8, ENT 4): Implemented 0 · Partial 3 (SEC-06, SEC-09, SEC-10) · Missing 31 · Conflict 0 · Unknown 0.

Part F (199 rows): conventions 8 — Partial 3, Missing 4, Conflict 1; entities 123 — Partial 6, Missing 116, Conflict 1;
events 60 — Partial 4, Missing 56; API surface 8 — Missing 8. Total: Implemented 0 · Partial 13 · Missing 184 · Conflict 2 · Unknown 0.

Part G non-functional requirements (17): Implemented 0 · Partial 4 · Missing 11 · Conflict 1 (Interface language) · Unknown 1 (Recovery).
Architecture choices (6, supplementary): Missing 5 · Conflict 1.

Questions: merged into `06-QUESTIONS.md`.

## Part 5 — User flows UF-01 to UF-29

Phase A, read-only. Target: `/home/user/owntheagenda_admin` (the platform), HEAD `8c01aec`. Statuses per A3.5.
Row format as asked: `Flow / step | Status | Evidence | Missing or different | Feature IDs it needs | Design screen`.
Setting keys are the design's register keys (`admin-data.js` `SA.settings`), which carry the 15 rows of
"Settings managed in CUS-07" (INSTRUCTIONS.md:684–702) one to one; the brief itself gives the settings names, not keys.

### Shared evidence

- **E0 — what exists, used as the evidence of absence.** The platform's only tables are `app.admins`, `app.products`,
  `app.installations`, `app.accounts`, `app.account_products`, `app.subscriptions`, `app.members`, `app.usage_daily`,
  `app.events_in`, `app.audit` (`supabase/migrations/0001_foundation.sql:18–145`) and the Vault product secrets
  (`0002_product_secrets.sql`). Its only routes are `app/page.tsx` (status page), `app/login/*`, `app/mfa/*`,
  `app/ingen-tilgang/page.tsx`. No CRM table (lead, deal, pipeline, activity, note, file, label, workflow, sequence,
  report, setting), no settings registry, no jobs/cron, no email or other provider, no storage bucket, no seed.
  Tests: `tests/signing.test.ts` only (vitest, `package.json:12`); `supabase/tests/` is an empty directory; no
  end-to-end tool in `package.json`. A step marked Missing with evidence "E0" means nothing in this list implements it.
- **Nothing in Part D can be Implemented**: no flow has an end-to-end test and no CRM screen exists to be seen.
- **The design reproduces every flow verbatim.** `design-reference/sentral/project/coverage-data.js` (`SA_COVERAGE.flows`)
  holds UF-01..UF-29 with the same headers and steps as INSTRUCTIONS.md:1578–1905 (compared programmatically: 29 flows,
  0 differing steps). `Coverage.dc.html` lists them as text; it is not a flow screen. The per-step design screen below is
  the screen that `coverage-data.js` assigns to the step's features (field `r`), checked against the screen's tab list and
  a grep for the step's concept. "Not found" means the concept was grepped for and is absent from that screen.

### Gate flows (Part G, INSTRUCTIONS.md:2515–2525)

Every one of the 29 user flows is a gate flow. Part G's phase table names them as exit gates:

| Phase | Gate user flows |
| --- | --- |
| 0 · Foundations | none (gate is "a custom field works end to end…" + SF-01, SF-02, SF-34, SF-38) |
| 1 · Sales core | UF-01, UF-02, UF-09, UF-10, UF-23, UF-24, UF-29 |
| 2 · Engagement | UF-04, UF-06, UF-25 |
| 3 · Automation | UF-05, UF-11, UF-12 |
| 4 · Insight | UF-03, UF-13, UF-14, UF-26 |
| 5 · Capture and close | UF-08, UF-18, UF-19 |
| 6 · Market and deliver | UF-17, UF-20 |
| 7 · AI | UF-07, UF-27 |
| 8 · Platform and channels | UF-15, UF-16, UF-21, UF-22, UF-28 |

A10/A5 require each gate flow to pass end to end before a phase closes; the platform has no end-to-end tool.

### Table


| Flow / step | Status | Evidence | Missing or different | Feature IDs it needs | Design screen |
| --- | --- | --- | --- | --- | --- |
| **UF-01 Capture and qualify a lead** (gate, phase 1) | Missing | E0 | LEA-01..05, AUT-11, PRO-04, CRM-15, ACT-07 | Contacts.dc.html (Leads tab), Automation.dc.html, Feed.dc.html, Marketing.dc.html |
| UF-01 · 1 Lead arrives from form, chatbot, import, prospect search or manual entry, source recorded | Missing | E0. Note: Orgpuls' `contact.submitted` and `demo.requested` events are stored raw in `app.events_in` (`0001:201–204`) and fall into the no-op branch (`0001:261–262`); no lead is made | LEA-04, CRM-15; channels LGN-01, LGN-03, LGN-04, CRM-09 (not in the flow's "Uses" list, see 06-QUESTIONS) · Settings: form_tracking, contact_rule | Contacts.dc.html (Leads); Marketing.dc.html (Web forms, Chatbot and live chat, Prospect search) |
| UF-01 · 2 Assignment rule sets owner; owner notified | Missing | E0 | AUT-11, SF-06, SF-07 | Automation.dc.html (Assignment rules) |
| UF-01 · 3 Rep opens lead, reads enriched company data and chat/form answers | Missing | E0 | LEA-01, PRO-04 | Contacts.dc.html (Leads); Feed.dc.html (Enrichment) |
| UF-01 · 4 Rep emails or calls; contact logged on the lead | Missing | E0 | LEA-05; COM-12 for calls (not in "Uses", see 06-QUESTIONS) | Contacts.dc.html; Inbox.dc.html |
| UF-01 · 5 Not relevant: label and archive; flow ends | Missing | E0 | LEA-02, LEA-01 | Contacts.dc.html (Leads) |
| UF-01 · 6 Qualified: convert to deal, pick pipeline and stage | Missing | E0 | LEA-03 | Contacts.dc.html; Deals.dc.html |
| UF-01 · 7 Notes, emails, files, activities move to the deal; next-activity prompt | Missing | E0 | LEA-03, ACT-07 | Contacts.dc.html; Activities.dc.html |
| **UF-02 Work a deal to won or lost** (gate, phase 1) | Missing | E0 | PIP-01..07, CUS-02, CRM-07, ACT-01, ACT-04, ACT-07 | Deals.dc.html |
| UF-02 · 1 Pipeline opens; no-activity warning; idle deals rotting | Missing | E0 | PIP-01, PIP-05, ACT-01, SF-26 | Deals.dc.html (Pipeline; "rotting" present) |
| UF-02 · 2 Deal opens with Focus and History | Missing | E0 | PIP-04 | Deals.dc.html ("Focus", "History" present) |
| UF-02 · 3 Complete due activity, plan next when prompted | Missing | E0 | ACT-01, ACT-04, ACT-07 | Deals.dc.html; Activities.dc.html |
| UF-02 · 4 Drag to next stage; blocked while a required field is empty | Missing | E0 | PIP-01, CUS-02 | Deals.dc.html; Settings.dc.html (Data fields: "Required from Negotiation") |
| UF-02 · 5 Add products; value recalculates | Missing | E0 | CRM-07, PIP-03, SF-32 | Deals.dc.html (Products) |
| UF-02 · 6 Mark won, or lost with reason | Missing | E0 | PIP-07 | Deals.dc.html |
| UF-02 · 7 Workflows listening for the change run (e.g. create project) | Missing | E0 | AUT-02, AUT-07, PRJ-01 (not in "Uses", see 06-QUESTIONS) | Automation.dc.html |
| **UF-03 Daily routine in the feed** (gate, phase 4) | Missing | E0 | PRO-01, PRO-02, PRO-03, COM-06 | Feed.dc.html |
| UF-03 · 1 Feed on Follow-ups: replies, opened emails, today's activities, emails waiting to send | Missing | E0 | PRO-01, COM-06, SF-13 · Settings: tracking | Feed.dc.html ("Follow-ups" tab) |
| UF-03 · 2 Act from the card or the side panel | Missing | E0 | PRO-02 | Feed.dc.html |
| UF-03 · 3 Overlooked deals: no follow-up or overdue; schedule next step | Missing | E0 | PRO-01, PRO-02 | Feed.dc.html ("Overlooked deals") |
| UF-03 · 4 Opportunities: new deals without activity; plan first step | Missing | E0 | PRO-01 | Feed.dc.html |
| UF-03 · 5 Filter by score; counter shows what is done | Missing | E0 | PRO-03, PRO-01 | Feed.dc.html |
| **UF-04 Email outreach with tracking** (gate, phase 2) | Missing | E0 (no mail provider, no mailbox connection) | COM-02, COM-05, COM-06, COM-08, AIA-03, AIA-04 | Inbox.dc.html |
| UF-04 · 1 Composer from a deal; template or AI draft | Missing | E0 | COM-05, AIA-03, SF-24 | Inbox.dc.html |
| UF-04 · 2 Merge fields fill; missing value flagged | Missing | E0 | COM-05 | Inbox.dc.html ("missing" present) |
| UF-04 · 3 Send now or schedule | Missing | E0 | COM-08 | Inbox.dc.html ("Scheduled and failed") |
| UF-04 · 4 Failure shows reason in outbox; retry | Missing | E0 | COM-08 | Inbox.dc.html (outbox, "retry") |
| UF-04 · 5 Open or click notifies the rep | Missing | E0 | COM-06, SF-07 · Settings: tracking | Inbox.dc.html |
| UF-04 · 6 Reply links to deal; summary and suggested reply | Missing | E0 | COM-02, AIA-04, SF-03 | Inbox.dc.html ("summar…" present) |
| UF-04 · 7 No reply after 5 days: follow-up card in feed | Missing | E0 | PRO-01, SF-26 (not in "Uses", see 06-QUESTIONS) | Feed.dc.html |
| **UF-05 Nurture with a sequence** (gate, phase 3) | Missing | E0 (no scheduler, no job runtime) | AUT-12, COM-05, ACT-01 | Automation.dc.html (Sequences) |
| UF-05 · 1 Build a sequence of email and activity steps with delays | Missing | E0 | AUT-12, COM-05 | Automation.dc.html (Sequences) |
| UF-05 · 2 Enroll one, bulk, or by workflow | Missing | E0 | AUT-12; AUT-07 for workflow enrollment (not in "Uses", see 06-QUESTIONS) | Automation.dc.html (Sequences) |
| UF-05 · 3 Auto email steps send on time; manual ones wait for review | Missing | E0 | AUT-12, COM-05, SF-05 · Settings: sales_consent | Automation.dc.html; Feed.dc.html (sequence emails waiting) |
| UF-05 · 4 Activity steps create activities for the owner | Missing | E0 | AUT-12, ACT-01 | Automation.dc.html |
| UF-05 · 5 Reply or stage change ends enrollment | Missing | E0 | AUT-12 | Automation.dc.html |
| UF-05 · 6 Completes; failed step marks enrollment failed with reason | Missing | E0 | AUT-12 | Automation.dc.html |
| **UF-06 Book a meeting** (gate, phase 2) | Missing | E0 (no calendar provider, no public surface) | COM-10, COM-11, ACT-08, ACT-09 | Activities.dc.html (Meeting scheduler) |
| UF-06 · 1 Set availability; booking link in email, signature or automated message | Missing | E0 | COM-10; COM-05 signature | Activities.dc.html (Meeting scheduler; "booking" present) |
| UF-06 · 2 Contact opens booking page, sees free slots in own time zone, picks one | Missing | E0 | COM-10 | Activities.dc.html; time-zone display not found |
| UF-06 · 3 Both confirmed; activity with video link on the deal | Missing | E0 | COM-10, COM-11, ACT-08, SF-40 | Activities.dc.html |
| UF-06 · 4 Slot disappears; event syncs to the rep's calendar | Missing | E0 | COM-10, ACT-09, SF-08 | Activities.dc.html (Reminders and sync) |
| UF-06 · 5 Reschedule/cancel updates activity and calendar event | Missing | E0 | COM-10, ACT-08, ACT-09 | Activities.dc.html ("reschedul/cancel" present) |
| **UF-07 Run a meeting with meeting intelligence** (gate, phase 7) | Missing | E0 (no AI gateway, no recording provider) | MTG-01..08, AIA-03 | Meetings.dc.html |
| UF-07 · 1 Rep reads the brief | Missing | E0 | MTG-01 | Meetings.dc.html (Pre-call brief) |
| UF-07 · 2 Attendees notified of recording; bot joins or desktop app records | Missing | E0 | MTG-02, MTG-03, MTG-08 · Settings: rec_notice | Meetings.dc.html (Ways to capture; "notice" present) |
| UF-07 · 3 Attendee objects: remove bot or stop recording | Missing | E0 | MTG-02, MTG-08 | Meetings.dc.html (Workspace and controls); objection path not found |
| UF-07 · 4 Recap and transcript saved on deal; chat message announces it | Missing | E0 | MTG-04, INT-07 | Meetings.dc.html (Transcript and recap) |
| UF-07 · 5 Review suggested CRM updates; approve the right ones | Missing | E0 | MTG-05 · Settings: contact_rule | Meetings.dc.html (CRM update suggestions) |
| UF-07 · 6 Follow-up drafted from recap; plan next activity | Missing | E0 | AIA-03; ACT-07 (not in "Uses", see 06-QUESTIONS) | Meetings.dc.html; Inbox.dc.html |
| **UF-08 Quote to signature** (gate, phase 5) | Missing | E0 (no document generation, no storage bucket, no public surface) | DOC-01..06, CRM-07, AUT-01 | Documents.dc.html; Deals.dc.html |
| UF-08 · 1 Documents tab on the deal; pick a template | Missing | E0 | DOC-01 | Documents.dc.html (Templates); Deals.dc.html |
| UF-08 · 2 Generated with deal data and product table; opens for editing | Missing | E0 | DOC-01, DOC-02, CRM-07 | Documents.dc.html |
| UF-08 · 3 Share by trackable link or request signatures | Missing | E0 | DOC-04, DOC-05 · Settings: count_limits (signers) | Documents.dc.html (E-signature) |
| UF-08 · 4 Customer opens; rep notified | Missing | E0 | DOC-04, SF-07 | Documents.dc.html |
| UF-08 · 5 Each signer enters emailed code and signs | Missing | E0 | DOC-05, DOC-06, SF-20 | Documents.dc.html ("code" present) |
| UF-08 · 6 Signed PDF and audit trail on the deal; workflow can move to won | Missing | E0 | DOC-05, DOC-03, AUT-01, AUT-07 | Documents.dc.html ("audit trail" present) |
| UF-08 · 7 Nobody opens or signs: rep sees status and follows up | Missing | E0 | DOC-04, DOC-05 | Documents.dc.html |
| **UF-09 Set up the sales process** (gate, phase 1) | Partial | Only step 4, partly: `app.admins` (`0001:18–23`) | PIP-02, PIP-14, CUS-01..08, ACT-02, SEC-07..09 | Settings.dc.html |
| UF-09 · 1 Create pipelines and stages with probabilities and rotting thresholds | Missing | E0 | PIP-02 | Settings.dc.html (Pipelines and stages; "probabilit", "rotting" present) |
| UF-09 · 2 Add custom fields, group them, mark important and required | Missing | E0 | CUS-01, CUS-02, CUS-03, PIP-14 · Settings: count_limits (options per field) | Settings.dc.html (Data fields) |
| UF-09 · 3 Set activity types, currencies, modules on/off | Missing | E0 | ACT-02, CUS-05, CUS-06, CUS-07 | Settings.dc.html (Activity types, Language and currencies, Modules) |
| UF-09 · 4 Invite users, place in teams and visibility groups, assign permission sets | Partial | Met: a staff user list with a role exists — `app.admins` (email pk, `role in ('owner','admin')`, `active`; `0001:18–23`), checked by `app.admin_email()`/`app.is_admin()` (`0001:25–36`) | SEC-09, SEC-08, SEC-07 | Settings.dc.html (Users and teams, Permission sets, Visibility groups; "invite" present) |
| UF-09 · 5 Test with a sample deal; in a sandbox nothing reaches the live company | Missing | E0; no seed (no `supabase/seed*`, R8) | CUS-08 | Settings.dc.html (Sandbox) |
| **UF-10 Import and clean data** (gate, phase 1) | Missing | E0 | CRM-09, AIA-05, CRM-11, CRM-12, ENT-04 | Contacts.dc.html (Import, Duplicates, Restore) |
| UF-10 · 1 Upload spreadsheet; confirm or correct suggested mapping | Missing | E0 | CRM-09, AIA-05 · Settings: import_consent | Contacts.dc.html (Import) |
| UF-10 · 2 Duplicates previewed; merge or create | Missing | E0. Note: `app.accounts.org_number` is unique (`0001:61`) and ingest matches accounts by it (`0001:216`) — a dedupe key import could reuse | CRM-09, CRM-11 | Contacts.dc.html (Duplicates: "Same org.nr") |
| UF-10 · 3 Import runs; invalid or over-capacity rows to skip file | Missing | E0 | CRM-09, ENT-04, SF-09 · Settings: plan_gates | Contacts.dc.html ("skip" present) |
| UF-10 · 4 Download skip file, fix, re-import | Missing | E0 | CRM-09 | Contacts.dc.html |
| UF-10 · 5 Review suggested duplicates and merge | Missing | E0 | CRM-11, SF-10 · Settings: second_admin | Contacts.dc.html (Duplicates) |
| UF-10 · 6 Revert a wrong import from history | Missing | E0 | CRM-09, CRM-12 | Contacts.dc.html ("revert" present; Restore) |
| **UF-11 Build a workflow** (gate, phase 3) | Missing | E0 (no job runtime; open point 3) | AUT-01..10 | Automation.dc.html |
| UF-11 · 1 Start from template or blank canvas | Missing | E0 | AUT-01, AUT-08 | Automation.dc.html (Builder, Templates) |
| UF-11 · 2 Event or date trigger plus conditions | Missing | E0 | AUT-02, AUT-03, AUT-04 | Automation.dc.html (Builder) |
| UF-11 · 3 Actions, delays, wait-for, branches | Missing | E0 | AUT-07, AUT-05, AUT-06 · Settings: count_limits | Automation.dc.html (Builder) |
| UF-11 · 4 Save draft; activate for self, selected users or team | Missing | E0 | AUT-01, AUT-10 | Automation.dc.html (Workflows) |
| UF-11 · 5 Matching events start runs; history shows each | Missing | E0 | AUT-09, SF-04 | Automation.dc.html (Monitoring) |
| UF-11 · 6 Failed step alerts owner; opens failing step from overview | Missing | E0 | AUT-09 | Automation.dc.html (Monitoring) |
| UF-11 · 7 A set limit is reached: activation refused with reason | Missing | E0 | AUT-09 · Settings: count_limits, safeguards, plan_gates | Automation.dc.html |
| **UF-12 Set up automatic assignment** (gate, phase 3) | Missing | E0 | AUT-11, SEC-09 | Automation.dc.html (Assignment rules) |
| UF-12 · 1 Rule for lead added, deal added or deal updated | Missing | E0 | AUT-11 | Automation.dc.html (Assignment rules) |
| UF-12 · 2 Conditions and assignee: user, team, org owner, person owner | Missing | E0 | AUT-11, SEC-09 | Automation.dc.html |
| UF-12 · 3 Order by priority; activate | Missing | E0 | AUT-11 | Automation.dc.html |
| UF-12 · 4 First matching rule assigns; no match leaves creator | Missing | E0 | AUT-11, SF-06 | Automation.dc.html |
| UF-12 · 5 Assignment history shows which rule fired | Missing | E0 | AUT-11 | Automation.dc.html |
| **UF-13 Reports, dashboards and goals** (gate, phase 4) | Missing | E0. `public.platform_status` (`0001:302–325`) returns counts only and is not a report | INS-01..10 | Insights.dc.html |
| UF-13 · 1 Create report by type or AI request | Missing | E0 | INS-01, INS-09 | Insights.dc.html (Report builder, Ask for a report) |
| UF-13 · 2 Measure, dimensions, filters, chart type | Missing | E0 | INS-01, INS-02, INS-07, SF-14 | Insights.dc.html (Report builder) |
| UF-13 · 3 Add to dashboard, arrange, share with team or public link | Missing | E0 | INS-03, INS-04 | Insights.dc.html (Dashboards; "Public" present) |
| UF-13 · 4 Goals for users or teams; track progress | Missing | E0 | INS-05 | Insights.dc.html (Goals) |
| UF-13 · 5 Export chart or rows | Missing | E0 | INS-08 · Settings: typed_reason | Insights.dc.html ("export" present) |
| **UF-14 Scoring and enrichment** (gate, phase 4) | Missing | E0 (no enrichment provider) | PRO-03..06 | Feed.dc.html (Scoring models, Enrichment) |
| UF-14 · 1 Scoring model for a pipeline; criteria in three groups | Missing | E0 | PRO-03 · Settings: count_limits (score models) | Feed.dc.html (Scoring models) |
| UF-14 · 2 Preview on sample deals; activate | Missing | E0 | PRO-03 | Feed.dc.html ("preview" present) |
| UF-14 · 3 Scores on deals and in the feed filter | Missing | E0 | PRO-03, PRO-01, SF-12 | Feed.dc.html; Deals.dc.html (Deal score) |
| UF-14 · 4 Enrich one organization or up to 100 records in bulk | Missing | E0 | PRO-04, PRO-05, PRO-06, SF-11 · Settings: contact_rule (PRO-05) | Feed.dc.html (Enrichment; "100" present) |
| UF-14 · 5 Credit allowance set and short: refused; admin can buy top-up | Missing | E0 | PRO-06; ENT-03 (not in "Uses", see 06-QUESTIONS) · Settings: plan_gates | Feed.dc.html ("credit" present) |
| UF-14 · 6 Enriched fields update dependent scores | Missing | E0 | PRO-03, PRO-04, PRO-05 | Feed.dc.html |
| **UF-15 Security administration** (gate, phase 8) | Partial | Only step 2, partly: mandatory TOTP for every admin (`middleware.ts:43–45`, `0001:32–36`, `app/mfa/actions.ts:14–34`) | SEC-01..06, SEC-10, SEC-11 | Security.dc.html |
| UF-15 · 1 Security dashboard; work through the assessment | Missing | E0 | SEC-01, SF-27 | Security.dc.html (Security dashboard; "Assessment" present) |
| UF-15 · 2 Configure single sign-on; enforce two-factor | Partial | Met: a second factor is enforced for every admin, without exception: middleware sends any session below aal2 to `/mfa` (`middleware.ts:43–45`); `app.is_admin()` requires `aal = 'aal2'` (`0001:32–36`); TOTP enrol/verify (`app/mfa/actions.ts:14–34`); fails closed (`middleware.ts:22–26, 48–51`) | SEC-05, SEC-06 | Security.dc.html (SSO and two-factor; "Single sign-on", "enforce" present) |
| UF-15 · 3 Password, IP and time rules; preview affected; enforce | Missing | E0 | SEC-03 | Security.dc.html (Alerts and rules; "IP", "password" present); preview of affected users not found |
| UF-15 · 4 Choose alerts and delivery | Missing | E0; no email provider | SEC-02 | Security.dc.html (Alerts and rules); digest not found |
| UF-15 · 5 On alert: check login history, log the device out | Missing | E0. Only self sign-out exists: `signOut({ scope: 'local' })` (`app/login/actions.ts:22–25`) | SEC-04 | Security.dc.html (Device and login history; "Log out of all devices") |
| UF-15 · 6 Privacy request: export or erase the person's data | Missing | E0 | SEC-11, SF-15 | Security.dc.html (Privacy compliance; "Erase from every module") |
| **UF-16 Connect systems** (gate, phase 8) | Missing | E0 for every CRM part. Present but different: signed inbound product events (`supabase/functions/orgpuls-events/index.ts`) and signed outbound product commands (`supabase/functions/product-command/index.ts`, `_shared/signing.ts`) — platform-to-product plumbing, not a public API, OAuth app, webhook subscription or catalog | INT-01..11, MCP-01..03, AIA-06 | Platform.dc.html |
| UF-16 · 1 Connect Google or Microsoft for mail, calendar, contacts, files | Missing | E0 | INT-05, INT-06 (serving COM-02, ACT-09, CRM-04, DOC-03) | Platform.dc.html (Applications, Integration catalog) |
| UF-16 · 2 Create API token or register OAuth app; read API reference | Missing | E0. `product-command` signs 2-minute HS256 tokens for Orgpuls commands only (`_shared/signing.ts`; `_shared/orgpuls.ts:52`) | INT-01, INT-02 | Platform.dc.html (REST API and tokens; "OAuth" present) |
| UF-16 · 3 Subscribe webhooks to events | Missing | E0 | INT-04, SF-23 · Settings: count_limits (webhooks per user) | Platform.dc.html (Webhooks) |
| UF-16 · 4 Failing endpoint banned then removed; visible in list | Missing | E0 | INT-04 · Settings: safeguards | Platform.dc.html (Webhooks; "ban" present) |
| UF-16 · 5 Find integrations by search or recommendation; install; review access | Missing | E0 | INT-11, INT-10, AIA-06, SF-41 | Platform.dc.html (Integration catalog) |
| UF-16 · 6 Switch the AI connector on or off | Missing | E0 | MCP-03 | Platform.dc.html (AI connector) |
| **UF-17 Send an email campaign** (gate, phase 6) | Missing | E0 (no sending provider, no marketing stream) | CMP-01..09 | Marketing.dc.html |
| UF-17 · 1 Authenticate sender domain; sending blocked until it passes | Missing | E0 | CMP-08 | Marketing.dc.html (Deliverability; "domain" present) |
| UF-17 · 2 Build from template; preview desktop and mobile | Missing | E0 | CMP-01, CMP-02, SF-39 | Marketing.dc.html (Email builder) |
| UF-17 · 3 Audience by filter; only subscribed addresses counted | Missing | E0 | CMP-03, CMP-04 | Marketing.dc.html (Audience and consent) |
| UF-17 · 4 Send now or schedule | Missing | E0 | CMP-05, SF-19 · Settings: plan_gates (subscriber allowance) | Marketing.dc.html (Campaigns) |
| UF-17 · 5 Bounces, unsubscribes, spam reports update status | Missing | E0 | CMP-04, CMP-08 | Marketing.dc.html ("unsubscrib" present) |
| UF-17 · 6 Campaign report; compare with earlier campaigns | Missing | E0 | CMP-06, CMP-09 | Marketing.dc.html ("compare" present) |
| **UF-18 Website visitor to lead** (gate, phase 5) | Missing | E0 (no public widget, no tracker) | LGN-01..05, LEA-01, AUT-11, COM-10 | Marketing.dc.html (Chatbot and live chat, Web forms) |
| UF-18 · 1 Widget loads; by consent if consent-gated loading is on | Missing | E0 | LGN-05 · Settings: widget_consent | Marketing.dc.html (Chatbot and live chat) |
| UF-18 · 2 Chatbot asks its questions for that page | Missing | E0 | LGN-01 | Marketing.dc.html |
| UF-18 · 3 Qualified: bot offers a meeting slot or live chat | Missing | E0 | LGN-01, LGN-02, COM-10 | Marketing.dc.html; Activities.dc.html |
| UF-18 · 4 Rep online claims within waiting time, else bot continues | Missing | E0 | LGN-02, SF-30 | Marketing.dc.html ("live chat" present); waiting time/claim not found |
| UF-18 · 5 Lead created with answers, source, tracking; assigned by rule | Missing | E0 | LGN-01, LGN-02, LEA-01, LEA-04, CRM-15, AUT-11, SF-17 · Settings: form_tracking | Marketing.dc.html; Contacts.dc.html (Leads) |
| UF-18 · 6 Or a web form creates the lead the same way | Missing | E0. Note: Orgpuls site forms already emit `contact.submitted`/`demo.requested`, stored raw only (`0001:201–204, 261–262`) | LGN-03, LEA-01, SF-17 · Settings: form_tracking | Marketing.dc.html (Web forms) |
| **UF-19 Identify web visitors** (gate, phase 5) | Missing | E0 | WEB-01..04, LGN-04 | Marketing.dc.html (Web visitors) |
| UF-19 · 1 Admin installs the tracker | Missing | E0 | WEB-01, SF-18 · Settings: web_ident | Marketing.dc.html (Web visitors) |
| UF-19 · 2 Visiting companies in the visitor inbox, ranked | Missing | E0 | WEB-02, WEB-03 | Marketing.dc.html (Web visitors) |
| UF-19 · 3 Filter by country, campaign, page; open visit history | Missing | E0 | WEB-03 | Marketing.dc.html |
| UF-19 · 4 Company already in CRM: existing record shown | Missing | E0 | WEB-04 | Marketing.dc.html |
| UF-19 · 5 Else convert to lead/organization; prospect search for contacts | Missing | E0 | WEB-04, LGN-04 · Settings: contact_rule | Marketing.dc.html (Web visitors, Prospect search) |
| **UF-20 Hand over a won deal to delivery** (gate, phase 6) | Missing | E0 | PRJ-01..09, AUT-07 | Projects.dc.html |
| UF-20 · 1 Deal won; workflow or rep creates project, optionally from template | Missing | E0 | PRJ-02, PRJ-05, AUT-07; PIP-07 (not in "Uses", see 06-QUESTIONS) | Projects.dc.html (Templates); Deals.dc.html |
| UF-20 · 2 Brief drafted from the deal and reviewed | Missing | E0 | PRJ-02, SF-24 | Projects.dc.html |
| UF-20 · 3 Adjust tasks, owners, dates, dependencies on timeline | Missing | E0 | PRJ-03, PRJ-04 | Projects.dc.html (Timeline) |
| UF-20 · 4 Team works tasks; board shows phase and health | Missing | E0 | PRJ-01, PRJ-03, PRJ-06 | Projects.dc.html (Board; "health" present) |
| UF-20 · 5 Slipping: set health or request AI summary | Missing | E0 | PRJ-06 | Projects.dc.html |
| UF-20 · 6 Share status report with client; close project | Missing | E0 | PRJ-07, PRJ-09, SF-42 | Projects.dc.html (Reports) |
| **UF-21 Field visit on mobile** (gate, phase 8) | Missing | E0 (web app only; no mobile client) | MOB-01..08, AIA-07 | Mobile.dc.html |
| UF-21 · 1 App opens on focus view; the day | Missing | E0 | MOB-02, SF-44 | Mobile.dc.html ("Focus") |
| UF-21 · 2 Nearby contacts around next meeting; navigate | Missing | E0 | MOB-03 | Mobile.dc.html ("Nearby") |
| UF-21 · 3 Offline: open deal, add notes | Missing | E0 | MOB-05 | Mobile.dc.html ("Offline") |
| UF-21 · 4 Audio note, business card scan, plan next activity | Missing | E0 | MOB-06, AIA-07; ACT-07 (not in "Uses", see 06-QUESTIONS) · Settings: contact_rule | Mobile.dc.html ("Audio note", "Scan") |
| UF-21 · 5 Changes sync when connection returns | Missing | E0 | MOB-05, SF-31 | Mobile.dc.html ("sync") |
| **UF-22 Work through an external AI assistant** (gate, phase 8) | Missing | E0 | MCP-01..03, INT-03 | Platform.dc.html (AI connector) |
| UF-22 · 1 Add connector in assistant; log in | Missing | E0 | MCP-01, INT-02 | Platform.dc.html (AI connector) |
| UF-22 · 2 Ask to find, create or update records | Missing | E0 | MCP-01, MCP-02 | Platform.dc.html |
| UF-22 · 3 Each call runs with user's permissions, counts against API limits | Missing | E0 | MCP-01, INT-03, SF-22 · Settings: api_rate | Platform.dc.html |
| UF-22 · 4 Connector switched off: connection refused | Missing | E0 | MCP-03 | Platform.dc.html |
| UF-22 · 5 Changes appear in changelog with connector as source | Missing | E0 | MCP-01, PIP-04, SF-02 | Platform.dc.html ("source" present); Deals.dc.html (History) |
| **UF-23 Manage contacts and organizations** (gate, phase 1) | Partial | Only step 1, partly: organization and contact data exist (`app.accounts` `0001:58–64`, `app.account_products` `0001:66–77`, `app.members` `0001:97–109`), filled by `public.ingest_events` (`0001:214–257`) | CRM-01..06, CRM-10, CRM-13, CRM-14 | Contacts.dc.html; Customers.dc.html |
| UF-23 · 1 Open an organization: its contacts, deals, tickets, activities, files | Partial | Met: an organization record (`app.accounts`: name, org_number) linked to product tenants (`app.account_products`) with the tenant's users as contacts (`app.members`: email, name, role; comment "contacts, never respondents" `0001:97`), created and updated from product events (`0001:214–257`) | CRM-01; tickets (Appendix 2) | Contacts.dc.html (Organizations); Customers.dc.html (Overview, Users and roles, Tickets, Timeline) |
| UF-23 · 2 Add a contact; source and basis optional unless contact rule on | Missing | E0. `app.members` rows come only from `member.joined` events (`0001:249–254`) | CRM-01, CRM-15, SF-37 · Settings: contact_rule | Contacts.dc.html (People; contact rule present) |
| UF-23 · 3 Note, mention a colleague, attach a file | Missing | E0 (no storage bucket) | CRM-06, CRM-05, SF-33 | Contacts.dc.html |
| UF-23 · 4 Link parent organization; apply labels | Missing | E0 | CRM-13, CRM-14 | Contacts.dc.html ("parent" present) |
| UF-23 · 5 Timeline of no-contact in period; map of contacts near a place | Missing | E0 | CRM-02, CRM-03 | Contacts.dc.html (Timeline, Map) |
| UF-23 · 6 Contact sync with the address book | Missing | E0 | CRM-04, SF-29 · Settings: contact_rule | Contacts.dc.html ("sync" present) |
| UF-23 · 7 Export a filtered list; export is logged | Missing | E0. `app.audit` logs product commands only (`0001:136–145`, `public.record_command` `0001:271–276`) | CRM-10 · Settings: typed_reason | Contacts.dc.html (Export; "logged" present) |
| **UF-24 Review and maintain the pipeline** (gate, phase 1) | Missing | E0 | PIP-08..13, PIP-15, PIP-17, ACT-03, ACT-05, ACT-06 | Deals.dc.html; Activities.dc.html |
| UF-24 · 1 Search or apply a saved filter | Missing | E0 | PIP-12, SF-25 | Deals.dc.html |
| UF-24 · 2 List view: columns, sort, inline edit | Missing | E0 | PIP-10 | Deals.dc.html (List) |
| UF-24 · 3 Bulk edit owner or label; activity for all | Missing | E0 | PIP-10, ACT-06 | Deals.dc.html ("bulk" present); Activities.dc.html |
| UF-24 · 4 Add participants; follow a colleague's deal | Missing | E0 | PIP-08, PIP-09 | Deals.dc.html ("follow" present) |
| UF-24 · 5 Calendar: reschedule activities, set priorities | Missing | E0 | ACT-03, ACT-05 | Activities.dc.html (Calendar; "priority" present) |
| UF-24 · 6 Archive, show closed, duplicate, restore deleted | Missing | E0 | PIP-13, PIP-15, PIP-17, SF-35 | Deals.dc.html (Archive and restore) |
| UF-24 · 7 Bulk delete: preview; second-admin approval only if setting on | Missing | E0 | PIP-10, CRM-12 · Settings: second_admin | Deals.dc.html ("approv" present) |
| **UF-25 Calls, messages and shared inboxes** (gate, phase 2) | Missing | E0 (no telephony, messaging or mail provider) | COM-01, COM-03, COM-04, COM-07, COM-09, COM-12, COM-13, COM-14, LEA-06 | Inbox.dc.html |
| UF-25 · 1 Click a number; call via provider, logged with outcome and duration | Missing | E0 | COM-12, SF-28 | Inbox.dc.html ("call" present) |
| UF-25 · 2 Message arrives in messaging inbox; owner notified | Missing | E0. Orgpuls `support.requested` events are stored raw only (`0001:261–262`) | COM-13, LEA-06 | Inbox.dc.html ("messaging") |
| UF-25 · 3 Answer in a shared inbox; colleagues see the reply | Missing | E0 | COM-04 | Inbox.dc.html ("Shared") |
| UF-25 · 4 Pick sending mailbox; label and archive thread | Missing | E0 | COM-03, COM-09 | Inbox.dc.html |
| UF-25 · 5 One email to a list; all receive by default; consent setting filters and reports | Missing | E0 | COM-07 · Settings: sales_consent, count_limits (recipients) | Inbox.dc.html; suppression not found there |
| UF-25 · 6 Add deal from mail-client side panel; else BCC address | Missing | E0 | COM-14, COM-01, SF-40 | Inbox.dc.html ("BCC drop-box", add-on) |
| **UF-26 Recurring revenue and forecast** (gate, phase 4) | Partial | Only step 5, partly: billing mirror `app.subscriptions` (`0001:80–95`) fed by `billing.changed` (`0001:236–248`) | CRM-08, PIP-11, INS-06 | Deals.dc.html; Insights.dc.html; Customers.dc.html (Billing) |
| UF-26 · 1 Add recurring product or installment plan to a deal | Missing | E0 | CRM-08, CRM-07 | Deals.dc.html ("installment" present; Products) |
| UF-26 · 2 Deal shows MRR, ARR, ACV, TCV | Missing | E0 | CRM-08, SF-32 | Deals.dc.html ("MRR" present) |
| UF-26 · 3 Forecast view; drag a deal to a later month | Missing | E0 | PIP-11 | Deals.dc.html (Forecast) |
| UF-26 · 4 Forecast reports by month from deals and recurring products | Missing | E0 | INS-06 | Insights.dc.html (Forecast) |
| UF-26 · 5 For existing Orgpuls customers recurring figures come from billing | Partial | Met: a per-tenant billing mirror exists — plan, billing_interval, trial/confirmed/free/cancel/deletion dates (`0001:80–95`), upserted newest-wins from `billing.changed` (`0001:236–248`) | CRM-08 | Customers.dc.html (Billing; "MRR" present); Analytics.dc.html ("MRR") |
| **UF-27 Work with the AI assistant** (gate, phase 7) | Missing | E0 (no AI gateway, SF-24). Firewall precondition holds today: the platform stores no survey responses or respondents (`0001:9–10`; table list E0), but no firewall test exists (A8) | AIA-01, AIA-02, PRO-07 | Sentral Admin.dc.html (Assistant, Notifications); Feed.dc.html |
| UF-27 · 1 Ask about deals or contacts; answer cites records | Missing | E0 | AIA-01, SF-24 | Sentral Admin.dc.html (Assistant) |
| UF-27 · 2 Survey-answer question refused; data outside reach | Missing | E0. Design text: "Survey responses and respondent identities are outside my reach…" (Sentral Admin.dc.html) | AIA-01 · Settings: firewall (fixed) | Sentral Admin.dc.html |
| UF-27 · 3 Notifications panel: stalled deals with suggested next step | Missing | E0 | AIA-02 | Sentral Admin.dc.html (Notifications); "stalled" found only in Inbox/Feed/Platform.dc.html |
| UF-27 · 4 Accept a suggestion; action runs and is logged | Missing | E0 | AIA-02, SF-02 | Sentral Admin.dc.html |
| UF-27 · 5 Unknown sender: assistant proposes a contact; accept to create | Missing | E0 | PRO-07 · Settings: contact_rule | Sentral Admin.dc.html ("propos…" present); Inbox.dc.html |
| **UF-28 Plans and limits** (gate, phase 8) | Missing | E0. `app.usage_daily` (`0001:111–118`) is a product's per-tenant usage, not CRM consumption against limits | ENT-01..03, PIP-16 | Settings.dc.html (Plans and usage); Deals.dc.html |
| UF-28 · 1 Usage page: consumption against each limit | Missing | E0 | ENT-04 (not in "Uses", see 06-QUESTIONS), SF-16 · Settings: plan_gates | Settings.dc.html ("Usage against every limit") |
| UF-28 · 2 At a limit manual creation refused; automated lead/deal creation to waitlist | Missing | E0 | ENT-01, ENT-02, PIP-16 · Settings: plan_gates | Settings.dc.html:146 ("overflow goes to the waitlist"); Deals.dc.html ("waitlist") |
| UF-28 · 3 Upgrade plan or buy top-up; available at once | Missing | E0 | ENT-03 | Settings.dc.html (Entitlements "plan and add-on"); upgrade/top-up action not found |
| UF-28 · 4 Add waitlisted deals back | Missing | E0 | PIP-16 | Deals.dc.html ("waitlist") |
| **UF-29 Set rules and limits** (gate, phase 1) | Missing | E0 (no settings registry, SF-34). `app.audit` records commands to products only (`0001:136–145`) | CUS-07, ENT-01, ENT-02 | Settings.dc.html (Rules and limits) |
| UF-29 · 1 Settings shows every rule with current value; all unrestricted by default | Missing | E0 | CUS-07, SF-34 · Settings: all 15 | Settings.dc.html (Rules and limits; "Default — unrestricted") |
| UF-29 · 2 Switch on a rule; pick warn or block where offered | Missing | E0 | CUS-07 · Settings: contact_rule, sales_consent (Off; Warn; Block) | Settings.dc.html (Rules and limits) |
| UF-29 · 3 Set a limit or plan gate if wanted | Missing | E0 | ENT-01, ENT-02 · Settings: count_limits, plan_gates, api_rate | Settings.dc.html (Rules and limits, Plans and usage) |
| UF-29 · 4 Applies at once; logged with who and when | Missing | E0. The only log is `app.audit` (actor, product NOT NULL, command matching `^[a-z]+\.[a-z_]+$`; `0001:136–145`), written only by `public.record_command` for product commands (`0001:271–276`) | CUS-07 | Settings.dc.html:35, 185–188 (rule log: when, who, what) |
| UF-29 · 5 A user hitting a rule sees which setting stopped the action | Missing | E0 | SF-34 | Settings.dc.html; none found on feature screens |
| UF-29 · 6 Switching the rule off restores full function | Missing | E0 | CUS-07 | Settings.dc.html |

### Counts

- Rows: 198 (29 flow rows + 169 step rows).
- Implemented: 0
- Partial: 8 (flows UF-09, UF-15, UF-23, UF-26; steps UF-09·4, UF-15·2, UF-23·1, UF-26·5)
- Missing: 190 (25 flows, 165 steps)
- Conflict: 0
- Unknown: 0
- Questions: 22

## Part 6 — System flows SF-01 to SF-45

Scope: `docs/crm-enrichment/INSTRUCTIONS.md` lines 1906–2384 (Part E, read in full). Judged against the
platform repository `/home/user/owntheagenda_admin` only (HEAD as of 2026-10-06). Phase A: no code or
database changed.

**Path legend** (used in the Evidence and Mechanism columns):
`M1` = `supabase/migrations/0001_foundation.sql` · `M2` = `supabase/migrations/0002_product_secrets.sql` ·
`EV` = `supabase/functions/orgpuls-events/index.ts` · `PC` = `supabase/functions/product-command/index.ts` ·
`SI` = `supabase/functions/secret-intake/index.ts` · `SG` = `supabase/functions/_shared/signing.ts` ·
`OC` = `supabase/functions/_shared/orgpuls.ts` · `SC` = `supabase/functions/_shared/secrets.ts` ·
`MW` = `middleware.ts` · `RD` = `lib/platform/read.ts` · `CMD` = `lib/platform/command.ts` ·
`LOGIN` = `app/login/actions.ts` · `MFA` = `app/mfa/actions.ts` · `I18N` = `lib/i18n/request.ts` ·
listed verbatim (identical name, trigger and steps — checked programmatically) in `coverage-data.js`, rendered
by `Coverage.dc.html`. The per-flow design screen is derived from the routes (`r`) of the features each flow
serves in `coverage-data.js`, plus a grep for the flow's concepts.

**Verification facts that apply to every row:** the only tests are `tests/signing.test.ts` (vitest, HMAC/JWT
unit tests). There are no database tests, no end-to-end tests and no screenshots, so no row can be
Implemented (A3.5). No scheduler (no `cron.schedule` in M1/M2), no email provider, no storage bucket, no
settings registry, no CRM table, no seed or demo tenant exist in the repository.

**Status rule used for flow rows:** a flow is Partial if at least one of its steps is Partial, Conflict if a
step is Conflict, otherwise Missing (or Unknown where a step cannot be determined and nothing else exists).

### Table

| Flow / step | Status | Evidence | Missing or different | Feature IDs it needs | Existing platform mechanism it can build on (path:line) or "none" | Design screen |
| --- | --- | --- | --- | --- | --- | --- |
| **SF-01 Permission and visibility check** | Conflict | MW:98-140; M1:25-36, 156-166, 302-307; PC:83-114; OC:8-44 | Steps 2, 4, 5 missing; step 3 contradicts the repo's access pattern; steps 1, 6 partial. Settings: Typed reason for CRM actions; Plan gates and usage limits; Anonymity firewall (fixed) | SEC-07, SEC-08, CUS-03, ENT-01 | `app.is_admin()` M1:32-36; deny-all RLS M1:156-166; definer RPC gate M1:306-307 | Settings.dc.html; Security.dc.html |
| SF-01.1 Request authenticated, tied to staff user, role and product | Partial | MW:129-134 (session + aal2); M1:25-36 (`admins` row, confirmed email, aal2); M1:20 (`role owner/admin`); PC:95 (product fixed to `orgpuls`) | Met: authenticated, tied to a staff user (`app.admins`). Not met: role is stored (M1:20) but never read by any function (`is_admin` ignores it); UI reads (`platform_status` M1:302) are not tied to a product | SEC-07 | M1:25-36; MW:100-140 | — |
| SF-01.2 Permission sets decide whether the action is allowed | Missing | none | All of it: no permission sets; `is_admin()` is all-or-nothing. OC scopes (OC:8-44) are product-side scopes for commands, not staff permissions | SEC-07 | none (OC:8-44 is a per-command scope map that a permission model could mirror) | — |
| SF-01.3 RLS decides rows by visibility: owner, group, group+sub-groups, everyone | Conflict | M1:4-7, 156-166; CLAUDE.md rule 1 | Spec: RLS policies select rows by visibility. Repo: every `app` table has RLS on with **no policy and no client grant**; clients read only via SECURITY DEFINER functions that check `app.is_admin()` (CLAUDE.md rule 1). Visibility would have to live in definer functions, or the repo rule changes. No owner/group columns exist | SEC-08 | definer-RPC pattern M1:302-325 | — |
| SF-01.4 Field rules hide fields and reject writes to read-only ones | Missing | none | All of it: no field registry, no field rules | CUS-01, CUS-03 | none | — |
| SF-01.5 Entitlement check where in use | Missing | none | All of it: no entitlements/registry (default "all on" would mean no check, but the check point does not exist) | ENT-01, CUS-07 | none | — |
| SF-01.6 Refusal returns clear error and is logged; read of customer data writes audit row; typed reason only if setting on; survey tables unreachable | Partial | M1:306-307 (`not_allowed`); PC:84, 114 (401/403); EV:37-40; PC:141-148 + M1:271-276 (audit of every command that reaches the product, e.g. `orgs.list` from ACT:119); M1:9-10, 136-145; CLAUDE.md rule 6 | Met: refusals return a clear error code; a read of customer data **through a product command** writes `app.audit` (actor, command, arg names). Not met: refusals are not logged to the audit (PC returns 401/403 before `record_command`; EV only `console.error`); direct reads (`platform_status`) write no audit row; `app.audit` has no reason column and no setting exists. Firewall: structurally true today (no response table in the platform DB, M1:9-10; no key to Orgpuls' DB) but no test proves it (R6/A8) and whether every allow-listed command (OC:8-44) is response-free is decided in Orgpuls, not verifiable here | SEC-07, SEC-11, CUS-07 | `app.audit` + `record_command` M1:136-154, 271-278; append-only trigger M1:148-154 | — |
| **SF-02 Record change and event publication** | Missing | none for CRM records | All of it: no CRM records, no changelog, no outbound event table, no dispatcher. Inbound product events exist (`app.events_in`) and are a different direction | PIP-04, AUT-01–AUT-10, INT-04, INS-10 | `app.events_in` M1:122-133 (typed events table Part F says to extend); one-transaction projection M1:173-266 | Automation.dc.html; Deals.dc.html; Insights.dc.html; Platform.dc.html |
| SF-02.1 Change, changelog entry and event in one transaction | Missing | none | All of it. `ingest_events` writes event + projection in one function call (M1:173-266) but for inbound product events only; no changelog table | PIP-04 | M1:173-266 (single-transaction pattern) | — |
| SF-02.2 Dispatcher delivers new events to subscribers | Missing | M1:262 (`else null; -- a later reader decides`) | All of it: no dispatcher, no subscribers, no job runtime | AUT, INT-04, INS-10, PRO-01, SEC (notifications) | none (no scheduler in repo) | — |
| SF-02.3 Each subscriber processes an event once by ID | Missing | M1:131, 203 | All of it. Only receipt is idempotent (unique `(product, source_id)`), not per-subscriber processing | AUT, INT-04 | idempotent receipt M1:131, 201-208 | — |
| SF-02.4 Failing subscriber retries without blocking others | Missing | none | All of it | AUT, INT-04 | none | — |
| **SF-03 Email sync** | Missing | none | All of it: no mailbox connection, no mail tables, no provider. Settings: Email open and click tracking; Consent and suppression checks on sales email | COM-01–COM-09 | Vault-held secrets M2:27-65, SC:69-78 (encryption at rest per A7.8) | Inbox.dc.html |
| SF-03.1 Mailbox authorized; tokens stored encrypted | Missing | none | All of it. Vault exists but `product_secret` / `store_product_secrets` accept only names matching `^[a-z][a-z0-9_]{1,30}_(token\|webhook)_secret$` (M2:43, 62) — product secrets, not per-user OAuth tokens | COM-01 | Vault M2:46-50, 58-63 | — |
| SF-03.2 History loaded back to chosen start date | Missing | none | All of it | COM-01 | none | — |
| SF-03.3 New mail by notification or polling, stored | Missing | none | All of it | COM-01, COM-02 | signed inbound endpoint pattern EV:20-57, SG:119-136 | — |
| SF-03.4 Senders/recipients matched to people; thread linked to open deal/lead or waits | Missing | none | All of it; `app.members` (M1:98-109) holds customer users' emails but there are no deals/leads | COM-03, CRM-01 | `app.members.email` M1:103 | — |
| SF-03.5 Outgoing mail sent with tracking, stored | Missing | none | All of it | COM-04, COM-06 | none | — |
| SF-03.6 Opens/clicks return as events, notify sender | Missing | none | All of it | COM-06, SF-07 | none | — |
| SF-03.7 Expired token / failed send: reconnect prompt or outbox reason | Missing | none | All of it | COM-01 | none | — |
| **SF-04 Workflow execution** | Missing | none | All of it. Settings: Count limits (actions and delays per path); Technical safeguards: workflow loop protection | AUT-01–AUT-10 | none (no scheduler, no outbound events) | Automation.dc.html |
| SF-04.1 Engine finds active workflows whose trigger matches | Missing | none | All of it | AUT-01, AUT-02, AUT-03 | none | — |
| SF-04.2 Conditions evaluated; failure ends silently | Missing | none | All of it | AUT-04 | none | — |
| SF-04.3 Run created; steps execute in order with owner's permissions | Missing | none | All of it; no per-user permission model to run as (see SF-01.2) | AUT-05, SEC-07 | PC:101-114 shows actor resolution (admin or `platform`) | — |
| SF-04.4 Delay schedules next step; wait-for stops after 7 days | Missing | none | All of it (7 days is a reference value for a setting per A9) | AUT-06 | none | — |
| SF-04.5 Branch picks one path | Missing | none | All of it | AUT-06 | none | — |
| SF-04.6 Step result written to run history | Missing | none | All of it | AUT-08 | none | — |
| SF-04.7 Failed action marks run failed, alerts owner; run counters stop loops | Missing | none | All of it | AUT-09, SF-07 | none | — |
| **SF-05 Sequence scheduler** | Missing | none | All of it. Settings: Consent and suppression checks on sales email (default Off) | AUT-12 | none | Automation.dc.html; Contacts.dc.html; Feed.dc.html |
| SF-05.1 First step time computed on enrollment, skipping weekends if set | Missing | none | All of it | AUT-12 | none | — |
| SF-05.2 Consent/suppression checked if setting on; then auto email, queued manual email, or activity | Missing | none | All of it | AUT-12, COM-07, ACT-01, PRO-01, CUS-07 | none | — |
| SF-05.3 Next step scheduled | Missing | none | All of it | AUT-12 | none | — |
| SF-05.4 Reply or stage change ends enrollment | Missing | none | All of it | AUT-12, SF-03, SF-35 | none | — |
| SF-05.5 After last step completed; failed send marks failed | Missing | none | All of it | AUT-12 | none | — |
| **SF-06 Assignment engine** | Missing | none | All of it | AUT-11 | none | Automation.dc.html |
| SF-06.1 Active rules for the event loaded in priority order | Missing | none | All of it | AUT-11 | none | — |
| SF-06.2 First matching rule chosen | Missing | none | All of it | AUT-11 | none | — |
| SF-06.3 Assignee resolved: user, team rotation, org owner, person's owner | Missing | none | All of it; no teams, no owners on `app.accounts` (M1:58-64) | AUT-11, SEC-09 | none | — |
| SF-06.4 Owner set, evaluation logged, new owner notified | Missing | none | All of it | AUT-11, SF-07 | none | — |
| SF-06.5 No match keeps owner | Missing | none | All of it | AUT-11 | none | — |
| **SF-07 Notifications and reminders** | Missing | none | All of it: no notification table, no email provider, no push | ACT-04, CRM-06, MOB-07 | none | Activities.dc.html; Contacts.dc.html; Mobile.dc.html |
| SF-07.1 Source emits notification request | Missing | none | All of it | ACT-04, CRM-06 | none | — |
| SF-07.2 User's channel preferences applied | Missing | none | All of it | ACT-04 | none | — |
| SF-07.3 Delivered in app, by email or by push | Missing | none | All of it | ACT-04, MOB-07 | none | — |
| SF-07.4 Duplicates in short window merged | Missing | none | All of it | ACT-04 | none | — |
| **SF-08 Calendar sync** | Missing | none | All of it | ACT-08, ACT-09, COM-10 | Vault M2 for tokens | Activities.dc.html; Meetings.dc.html |
| SF-08.1 User connects calendar, picks direction and activity types | Missing | none | All of it | ACT-09 | none | — |
| SF-08.2 Activity changes pushed to calendar | Missing | none | All of it | ACT-09 | none | — |
| SF-08.3 Calendar changes arrive by notification, update activities | Missing | none | All of it | ACT-09 | EV:20-57 (signed inbound endpoint pattern) | — |
| SF-08.4 Private events stored as busy time | Missing | none | All of it | ACT-09 | none | — |
| SF-08.5 Conflicts resolve to latest change | Missing | none | All of it | ACT-09 | last-write-wins guard M1:248, 254, 257 | — |
| **SF-09 Import pipeline** | Missing | none | All of it. Settings: Consent source on import; Plan gates and usage limits (capacity) | CRM-09, AIA-05, ENT-04 | none (no storage bucket) | Contacts.dc.html; Settings.dc.html |
| SF-09.1 File parsed, column mapping suggested | Missing | none | All of it | CRM-09, AIA-05 | none | — |
| SF-09.2 User confirms mapping and duplicate rule | Missing | none | All of it | CRM-09, CRM-11 | none | — |
| SF-09.3 Rows validated; capacity checked | Missing | none | All of it | CRM-09, ENT-04 | zod at boundaries (RD:150, LOGIN:132) | — |
| SF-09.4 Valid rows written in batches tagged with import ID | Missing | none | All of it | CRM-09 | batch-of-500 ingest pattern M1:190-193 | — |
| SF-09.5 Rejected rows to skip file with reasons | Missing | none | All of it | CRM-09 | none | — |
| SF-09.6 History records counts; revert by import ID | Missing | none | All of it | CRM-09, CRM-12 | none | — |
| **SF-10 Duplicate detection and merge** | Partial | M1:214-223 | Only step 1 partly met (organizations arriving from a product are matched by org number). Settings: Second-admin approval for bulk deletes and merges (default Off) | CRM-11 | M1:216 (match by `org_number`, unique M1:61) | Contacts.dc.html |
| SF-10.1 New people/orgs compared by configured matching rules | Partial | M1:214-223 | Met: an organisation a product names for the first time is matched to an existing `app.accounts` row by `org_number` before a new one is made. Not met: people are not compared; the rule is hard-coded, not configured; staff-created records do not exist | CRM-11 | M1:216-221 | — |
| SF-10.2 Matches listed as suggestions | Missing | none | All of it (the org-number match links automatically, no suggestion) | CRM-11 | none | — |
| SF-10.3 On merge user picks surviving values | Missing | none | All of it | CRM-11 | none | — |
| SF-10.4 Linked deals/activities/emails/files move; other record soft-deleted | Missing | none | All of it; no soft delete on `app.accounts` | CRM-11, CRM-12 | FK cascade from accounts M1:69 | — |
| **SF-11 Enrichment** | Missing | none | All of it. Settings: Contact rule (PRO-05, PRO-07); Plan gates and usage limits (credits) | PRO-04–PRO-07 | none | Feed.dc.html; Contacts.dc.html |
| SF-11.1 Credit balance checked where allowance set | Missing | none | All of it | PRO-04, ENT-02 | none | — |
| SF-11.2 Provider adapter called | Missing | none | All of it; provider not chosen (open point 2) | PRO-04 | outbound fetch with timeout PC:126-139 | — |
| SF-11.3 Returned values mapped to fields | Missing | none | All of it | PRO-04, CUS-01 | none | — |
| SF-11.4 Only empty fields written, with source and date | Missing | none | All of it (cf. `coalesce(a.org_number, …)` fill-if-empty M1:229, product events only) | PRO-04, CRM-15 | fill-if-empty pattern M1:229 | — |
| SF-11.5 Credits deducted; scoring re-run | Missing | none | All of it | PRO-04, PRO-03, SF-12 | none | — |
| SF-11.6 Provider error leaves record unchanged, no credit | Missing | none | All of it | PRO-04 | none | — |
| **SF-12 Scoring** | Missing | none | All of it. Settings: Count limits (score models) | PRO-03 | none | Feed.dc.html; Deals.dc.html |
| SF-12.1 Active model for the deal's pipeline loaded | Missing | none | All of it | PRO-03, PIP-02 | none | — |
| SF-12.2 Each criterion evaluated, group points added | Missing | none | All of it | PRO-03 | none | — |
| SF-12.3 Total normalized to 0–100 | Missing | none | All of it | PRO-03 | none | — |
| SF-12.4 Score and matched criteria stored; score-changed event published | Missing | none | All of it | PRO-03, SF-02 | none | — |
| **SF-13 Feed generation** | Missing | none | All of it | PRO-01, PRO-02 | none | Feed.dc.html |
| SF-13.1 Events (reply, open, click, new deal) create cards for owner | Missing | none | All of it | PRO-01 | none | — |
| SF-13.2 Scheduled checks create no-reply-5-days, no-follow-up, overdue cards | Missing | none | All of it (5 days = reference value for a setting) | PRO-01, SF-26 | none | — |
| SF-13.3 Card resolved when condition no longer holds or user acts | Missing | none | All of it | PRO-01 | none | — |
| SF-13.4 Daily counter updated | Missing | none | All of it | PRO-02 | none | — |
| **SF-14 Report query** | Missing | none | All of it | INS-01–INS-10 | aggregate definer RPC M1:302-325; `app.usage_daily` M1:111-118 (product usage rollup) | Insights.dc.html; Analytics.dc.html |
| SF-14.1 Report definition turned into a query | Missing | none | All of it | INS-01, INS-02 | none | — |
| SF-14.2 Query runs under viewer's visibility on live tables or rollups | Missing | none | All of it; no visibility model (SF-01.3) | INS-01, SEC-08 | M1:302-325 runs under `is_admin()` only | — |
| SF-14.3 Results cached per definition and scope | Missing | none | All of it | INS-01 | none | — |
| SF-14.4 Related events invalidate cache | Missing | none | All of it | INS-01, SF-02 | none | — |
| SF-14.5 Public link runs with owner's scope only | Missing | MW:98 | All of it. Only `/login` and `/ingen-tilgang` are public (MW:98); CLAUDE.md rule 2 requires a written reason for any new public path | INS-08 | none | — |
| **SF-15 Delete, restore and erasure** | Partial | M1:70, 74, 231-232 | Step 1 partly met for product-reported deletions only; steps 2-5 missing | CRM-12, SEC-11 | `account_products.status/deleted_at` M1:70-74; FK cascades M1:69, 94, 108, 117; `orgs.delete_now` OC:12 | Contacts.dc.html; Deals.dc.html; Security.dc.html |
| SF-15.1 Delete marks the row and records who, when, from where | Partial | M1:231-232 | Met: `app.account_products` is marked `status='deleted'` with `deleted_at` when the product reports `org.deleted`. Not met: no staff delete action, no who/from-where, no `deleted_at` on any other table | CRM-12 | M1:70-75, 231-232 | — |
| SF-15.2 Listed for restore for 30 days | Missing | none | All of it (30 days = reference value) | CRM-12 | none | — |
| SF-15.3 Restore brings back row and links | Missing | none | All of it | CRM-12 | none | — |
| SF-15.4 After 30 days a job removes it permanently | Missing | none | All of it; no job runtime | CRM-12, SF-26 | none | — |
| SF-15.5 Erasure removes a person from every module at once, logged | Missing | M1:122-133, 98-109 | All of it. Personal data today sits in `app.members` (email, name) and in raw `app.events_in.payload` (e.g. `contact.submitted` name/email/message, `member.joined`), with no erasure function and no retention | SEC-11 | `orgs.delete_now` OC:12 erases an org in Orgpuls, not a person in the platform | — |
| **SF-16 Entitlements and metering** | Missing | none | All of it. Settings: Plan gates and usage limits (default all on, unlimited) | ENT-01–ENT-04, PIP-16 | none (`app.subscriptions` M1:80-95 mirrors customers' product plans, not CRM entitlements) | Settings.dc.html; Deals.dc.html |
| SF-16.1 Counter compared with limit if set; none by default | Missing | none | All of it | ENT-01 | none | — |
| SF-16.2 Under limit creation proceeds, counter rises | Missing | none | All of it | ENT-01 | none | — |
| SF-16.3 At limit manual creation refused with reason | Missing | none | All of it | ENT-01, SF-34 | none | — |
| SF-16.4 Automated lead/deal creation goes to waitlist | Missing | none | All of it | PIP-16 | none | — |
| SF-16.5 Usage page reads same counters | Missing | none | All of it | ENT-03 | `app.usage_daily` M1:111 (product usage, not CRM counters) | — |
| **SF-17 Lead capture from forms and chat** | Missing | M1:261-262; EV:50 | All of it in the platform. Contact submissions from Orgpuls' site arrive as `contact.submitted` events and are stored raw in `app.events_in`; nothing reads them (M1:210-212 skips projection when there is no tenant). Settings: Consent-gated loading of site widgets; Form tracking fields; Contact rule | LGN-01–LGN-05, LEA-04 | `app.events_in` + `contact.submitted`/`demo.requested` kinds (README:12; EV) | Marketing.dc.html; Contacts.dc.html |
| SF-17.1 Widget loads (consent-gated if on); never in survey flow | Missing | none | All of it: no widget. "Never in the survey flow" is unprovable until a widget exists (R6 test required) | LGN-01, LGN-05 | none | — |
| SF-17.2 Submission validated and checked for spam | Missing | none in platform | All of it in the platform; only the HMAC of the batch is checked (EV:30-40). Orgpuls validates its own form (honeypot, length, 3/hour per address, 60/hour total) before emitting (Orgpuls HEAD 0206:411-426) | LGN-01 | EV:30-40 | — |
| SF-17.3 Contact and org found or created; source and consent recorded; admin's contact-form path (opens a ticket) reused | Missing | M1:261-262 | All of it. There is no contact-form path and no ticket table in the platform to reuse; see Questions | LGN-01, LEA-04, CRM-01, CRM-15 | `contact.submitted` in `app.events_in` M1:201-204 | — |
| SF-17.4 Lead or deal created with answers, source, tracking data | Missing | none | All of it | LEA-04, LGN-03 | none | — |
| SF-17.5 Assignment runs, owner notified, workflows fire | Missing | none | All of it | AUT-11, SF-06, SF-07, SF-04 | none | — |
| SF-17.6 Resubmission updates existing record, keeps owner | Missing | none | All of it | LEA-04 | upsert pattern M1:250-254 | — |
| **SF-18 Web visitor identification** | Missing | M1:233-235 | All of it. `org.attribution` events fill `account_products.attribution` (signup attribution), which is not visitor identification. Settings: Web visitor identification (default On); Contact rule (WEB-04) | WEB-01–WEB-04 | `account_products.attribution` M1:72, 233-235 | Marketing.dc.html |
| SF-18.1 Tracker sends page, referrer, network address | Missing | none | All of it | WEB-01 | none | — |
| SF-18.2 Address matched to company through data source | Missing | none | All of it; provider undecided (open point 2) | WEB-01 | none | — |
| SF-18.3 ISPs, crawlers, unmatched dropped | Missing | none | All of it | WEB-01 | none | — |
| SF-18.4 Visit stored; monthly unique count and ranking updated | Missing | none | All of it | WEB-02 | none | — |
| SF-18.5 Visitor inbox refreshes hourly | Missing | none | All of it; no scheduler | WEB-03, SF-26 | none | — |
| **SF-19 Campaign send** | Missing | none | All of it: no campaigns, segments, sending provider or domain authentication check | CMP-03–CMP-08 | none | Marketing.dc.html |
| SF-19.1 Audience filter resolved, reduced to subscribed addresses | Missing | none | All of it | CMP-03, CMP-05 | none | — |
| SF-19.2 Each email rendered with recipient data | Missing | none | All of it | CMP-01, CMP-03 | none | — |
| SF-19.3 Sent to provider on marketing stream | Missing | none | All of it | CMP-04 | none | — |
| SF-19.4 Provider events return (delivered…complaint) | Missing | none | All of it | CMP-06 | signed inbound endpoint pattern EV, SG:119-136 | — |
| SF-19.5 Events update campaign figures and address status | Missing | none | All of it | CMP-06, CMP-09 | none | — |
| SF-19.6 Unauthenticated domain or suspended account blocks send | Missing | none | All of it | CMP-07 | none | — |
| **SF-20 Document and signature** | Missing | none | All of it: no storage, no drive connection, no signature. Settings: Count limits (signers) | DOC-01–DOC-06 | none | Documents.dc.html; Deals.dc.html |
| SF-20.1 Template filled from deal, saved to connected drive | Missing | none | All of it | DOC-01, DOC-02 | none | — |
| SF-20.2 Share link created; opens logged and notified | Missing | none | All of it (public surface: A7.9 token) | DOC-03 | none | — |
| SF-20.3 Signature request emails link and one-time code | Missing | none | All of it | DOC-05 | one-time hashed nonce pattern M2:9-24, 35 | — |
| SF-20.4 Each signature recorded with time and address | Missing | none | All of it | DOC-05 | none | — |
| SF-20.5 All signed: PDF sealed with audit trail, stored on deal | Missing | none | All of it | DOC-05, DOC-06 | none | — |
| SF-20.6 Event published for workflows | Missing | none | All of it | DOC-06, SF-02 | none | — |
| **SF-21 Meeting intelligence pipeline** | Missing | none | All of it. Settings: Recording consent notices to attendees; Contact rule (MTG-05) | MTG-01–MTG-08 | none | Meetings.dc.html |
| SF-21.1 Upcoming meetings read from calendar, linked to deals | Missing | none | All of it | MTG-01, SF-08 | none | — |
| SF-21.2 Brief generated from deal history, stored before meeting | Missing | none | All of it | MTG-01, SF-24 | none | — |
| SF-21.3 Bot joins or desktop app captures audio | Missing | none | All of it | MTG-02 | none | — |
| SF-21.4 Audio transcribed with speakers and timestamps | Missing | none | All of it | MTG-03 | none | — |
| SF-21.5 AI gateway produces recap and proposed field changes | Missing | none | All of it | MTG-04, MTG-05, SF-24 | none | — |
| SF-21.6 Recap saved as note and announced | Missing | none | All of it | MTG-04, CRM-06 | none | — |
| SF-21.7 Only approved changes written; failed transcription keeps recording | Missing | none | All of it | MTG-05 | none | — |
| **SF-22 API request and rate limiting** | Partial | PC:83-114 | Steps 1 and 4 partly met by the platform's one internal endpoint; no public CRM API, no OAuth, no rate limiting. Settings: API rate limits (default Off) | INT-01–INT-03, MCP-01 | PC:83-114 (bearer check), MW, size caps EV:22-25, PC:89 | Platform.dc.html |
| SF-22.1 Token or OAuth grant verified | Partial | PC:83-114 | Met: `product-command` verifies its bearer (admin session via `admin_whoami`, or the service role key compared in constant time, PC:103). Not met: no API tokens or OAuth grants for external clients or connectors | INT-01, INT-02, MCP-01 | PC:101-114; SG:110-115 | — |
| SF-22.2 If rate limits on, burst limiter checks 2-second window | Missing | none | All of it (default Off means no limiter; the setting does not exist) | INT-03, CUS-07 | none | — |
| SF-22.3 With limits on, token cost deducted from daily budget | Missing | none | All of it | INT-03 | none | — |
| SF-22.4 SF-01 permission check runs | Partial | PC:110-114; M1:32-36 | Met to the extent of SF-01.1 (admin + aal2). Not met: permission sets, visibility (SF-01.2/3) | SEC-07 | M1:32-36 | — |
| SF-22.5 Handler responds with limit headers | Missing | none | All of it | INT-03 | none | — |
| SF-22.6 Over limit HTTP 429; admins emailed at 75%/100% | Missing | none | All of it; no email provider | INT-03, SF-07 | none | — |
| **SF-23 Webhook delivery** | Missing | none | All of it: no outbound webhooks. Settings: Technical safeguards: webhook retry and ban policy (default source values); Count limits (webhooks per user) | INT-04, AUT-07 | HMAC signing SG:100-107 (for signed payloads, an A4 decision); timeout pattern PC:134 | Platform.dc.html; Automation.dc.html |
| SF-23.1 Matching subscriptions found | Missing | none | All of it | INT-04 | none | — |
| SF-23.2 Payload posted with 10-second timeout | Missing | none | All of it; no private/link-local address blocking exists (A7.7) | INT-04 | `AbortSignal.timeout` PC:134 | — |
| SF-23.3 Retried after 3, 30, 150 seconds | Missing | none | All of it; no job runtime | INT-04 | none | — |
| SF-23.4 Ten first-attempt failures ban for 30 minutes | Missing | none | All of it | INT-04 | none | — |
| SF-23.5 Three days without success deletes it, notifies owner | Missing | none | All of it | INT-04, SF-07 | none | — |
| **SF-24 AI gateway call** | Missing | none | All of it: no model provider, no AI code | AIA-01–AIA-05, MTG-01–MTG-08, PRJ-06, INS-09 | audit row pattern M1:271-276 | Sentral Admin.dc.html (Assistant panel); Feed.dc.html; Inbox.dc.html; Meetings.dc.html; Insights.dc.html; Projects.dc.html; Contacts.dc.html |
| SF-24.1 Feature sends request with user and records in scope | Missing | none | All of it | AIA-01 | none | — |
| SF-24.2 Context retrieved under user's permissions, never from survey tables | Missing | none | All of it; firewall test required (R6) | AIA-01, SEC-07 | none | — |
| SF-24.3 Prompt sent to provider under no-training agreement | Missing | none | All of it; provider undecided (open point 2) | AIA-01 | none | — |
| SF-24.4 Output validated against expected structure | Missing | none | All of it | AIA-01 | zod validation pattern CMD:192, RD:150-171 | — |
| SF-24.5 Call logged with feature, user, cost | Missing | none | All of it | AIA-01 | M1:136-145 (audit columns lack feature/cost) | — |
| SF-24.6 Invalid output retried once, then error | Missing | none | All of it | AIA-01 | none | — |
| **SF-25 Search** | Missing | none | All of it: no search index (no `tsvector`/`pg_trgm` in M1/M2) | PIP-12 | none | Deals.dc.html; Sentral Admin.dc.html (search) |
| SF-25.1 Each write updates index (name, emails, phones, text) | Missing | none | All of it | PIP-12 | none | — |
| SF-25.2 Query matched against index | Missing | none | All of it | PIP-12 | none | — |
| SF-25.3 Results filtered by role and visibility | Missing | none | All of it | PIP-12, SEC-08 | none | — |
| SF-25.4 Ranked and grouped by record type | Missing | none | All of it | PIP-12 | none | — |
| SF-25.5 Survey data never indexed | Missing | M1:9-10 | No index exists to check; structurally no survey data is in the platform DB (M1:9-10), but no test (R6) | PIP-12 | none | — |
| **SF-26 Scheduled checks** | Missing | none | All of it: no scheduler in the repo. PC:5 names "scheduled work: a nightly sync" as a service-role use, but no such job exists | PIP-05, AUT-03, INS-05, PRO-01 | service-role actor `platform` in PC:103-104 | Deals.dc.html (rotting); Automation.dc.html (rotting alert, date triggers); Feed.dc.html; Insights.dc.html |
| SF-26.1 Scheduler starts each check at its interval | Missing | none | All of it; job runtime undecided (open point 3) | SF-26 | none | — |
| SF-26.2 Rotting check flags idle deals, notifies owners | Missing | none | All of it | PIP-05 | none | — |
| SF-26.3 Date-trigger check starts workflows | Missing | none | All of it | AUT-03 | none | — |
| SF-26.4 Goal check recomputes progress | Missing | none | All of it | INS-05 | none | — |
| SF-26.5 Feed check creates no-reply/no-follow-up cards | Missing | none | All of it | PRO-01 | none | — |
| SF-26.6 Each check records its run; failure raises alert | Missing | none | All of it | SF-07 | none | — |
| **SF-27 Sign-in and security events** | Partial | LOGIN:132-142; MFA:162-182; MW:129-134; M1:32-36 | Steps 1-2 partly met in code (no tests, not seen on screen); steps 3-6 missing | SEC-01–SEC-06 | `app.is_admin()` aal2 M1:35; MW:131-134 | Security.dc.html (SSO, IP allowlist, login history, new device) |
| SF-27.1 Sign in with password or single sign-on | Partial | LOGIN:135-142 | Met: password sign-in (zod-validated). Not met: single sign-on | SEC-01 | LOGIN:135-142 | — |
| SF-27.2 Second factor checked; mandatory in admin | Partial | MW:131-134; M1:35; MFA:162-182 | Met in code: every page but `/login` and `/ingen-tilgang` requires aal2 and fails closed; `is_admin()` requires aal2 in the database; TOTP enrol/verify. Not met for Implemented: no test covers it and it has not been seen on screen in this phase | SEC-02 | MW:100-140; M1:32-36 | — |
| SF-27.3 Security rules applied: IP allowlist, time window, password age | Missing | none | All of it. These are restrictions but are not in the CUS-07 register (see Questions) | SEC-03, SEC-04 | none | — |
| SF-27.4 Login written to login log with device and location | Missing | LOGIN:139-140 | All of it; failures return `failed` without a record. Whether Supabase Auth's own audit log can serve is Unknown (not in repo) | SEC-05 | none | — |
| SF-27.5 New device/location or repeated failures sends alert | Missing | none | All of it | SEC-05, SF-07 | none | — |
| SF-27.6 Security dashboard reads the same log | Missing | none | All of it | SEC-06 | none | — |
| **SF-28 Calls and messages** | Missing | none | All of it: no telephony or messaging adapter | COM-12, COM-13, MOB-04 | none | Inbox.dc.html; Mobile.dc.html |
| SF-28.1 Click-to-call goes to telephony adapter | Missing | none | All of it | COM-12 | none | — |
| SF-28.2 Provider reports result; activity written with outcome, duration, recording | Missing | none | All of it | COM-12, ACT-01 | none | — |
| SF-28.3 Incoming number matched to contact | Missing | none | All of it | COM-12 | none | — |
| SF-28.4 Incoming message stored on thread, linked to open deal, owner notified | Missing | none | All of it | COM-13, SF-07 | none | — |
| SF-28.5 Unmatched number/sender listed for manual linking | Missing | none | All of it | COM-12, COM-13 | none | — |
| **SF-29 Contact sync** | Missing | none | All of it. Settings: Contact rule (default No rule) | CRM-04 | none | Contacts.dc.html |
| SF-29.1 User connects address book, chooses what syncs | Missing | none | All of it | CRM-04 | Vault M2 for tokens | — |
| SF-29.2 Records matched by email | Missing | none | All of it | CRM-04 | none | — |
| SF-29.3 Change on one side updates the other | Missing | none | All of it | CRM-04 | none | — |
| SF-29.4 New external contact imported; contact rule if on | Missing | none | All of it | CRM-04, CUS-07 | none | — |
| **SF-30 Live chat routing** | Missing | none | All of it: no chat, no realtime | LGN-02 | none | Marketing.dc.html; Inbox.dc.html |
| SF-30.1 Chat enters unassigned queue; online reps notified | Missing | none | All of it | LGN-02 | none | — |
| SF-30.2 First rep to claim gets it, locked to that rep | Missing | none | All of it | LGN-02 | none | — |
| SF-30.3 Nobody claims within waiting time: bot continues | Missing | none | All of it | LGN-02 | none | — |
| SF-30.4 Real-time delivery both directions | Missing | none | All of it | LGN-02 | none | — |
| SF-30.5 Transcript saved on the lead | Missing | none | All of it | LGN-02, LEA-01 | none | — |
| **SF-31 Mobile offline sync** | Missing | none | All of it: no mobile client, no changelog | MOB-05 | last-write-wins guard M1:248, 254, 257 | Mobile.dc.html |
| SF-31.1 Offline changes queued on device with time | Missing | none | All of it | MOB-05 | none | — |
| SF-31.2 Sent in order on reconnect | Missing | none | All of it | MOB-05 | none | — |
| SF-31.3 Applied if unchanged; else latest wins, earlier kept in changelog | Missing | none | All of it; no version column, no changelog | MOB-05, SF-02 | M1:248, 254 (`updated_at <=` guard) | — |
| SF-31.4 Device pulls changes made elsewhere | Missing | none | All of it | MOB-05 | none | — |
| **SF-32 Derived values** | Missing | none | All of it | CRM-07, CRM-08, CUS-04, CUS-06, PIP-15 | none | Deals.dc.html; Settings.dc.html |
| SF-32.1 Product line change recalculates deal value | Missing | none | All of it | CRM-07 | none | — |
| SF-32.2 Schedule change recalculates MRR, ARR, ACV, TCV | Missing | none | All of it (`app.subscriptions` M1:80-95 holds plan/interval, no amounts) | CRM-08 | none | — |
| SF-32.3 Formula input change recalculates formula field | Missing | none | All of it | CUS-04 | none | — |
| SF-32.4 Reports convert with stored exchange rate | Missing | none | All of it | CUS-06 | none | — |
| SF-32.5 Stage change closes previous stage time, opens next | Missing | none | All of it | PIP-15 | none | — |
| **SF-33 Files** | Missing | none | All of it: no storage bucket, no file table | CRM-05, DOC-03, MOB-06 | none | Contacts.dc.html; Deals.dc.html; Documents.dc.html; Mobile.dc.html |
| SF-33.1 Uploaded to storage under record's access rules | Missing | none | All of it | CRM-05 | none | — |
| SF-33.2 File row links to record and history | Missing | none | All of it | CRM-05 | none | — |
| SF-33.3 Download only if user may see the record | Missing | none | All of it | CRM-05, SEC-08 | none | — |
| SF-33.4 Deleting record soft-deletes its files | Missing | none | All of it | CRM-05, CRM-12 | none | — |
| **SF-34 Rule settings** | Partial | M1:9-10; CLAUDE.md rule 6 | Only step 6 partly met (the firewall is structural and has no switch). No registry exists | CUS-07, ENT-01, ENT-02 | `app.audit` M1:136-154 for logging changes | Settings.dc.html |
| SF-34.1 Feature asks registry for applicable rules | Missing | none | All of it | CUS-07 | none | — |
| SF-34.2 Default: no rule applies, action proceeds | Missing | none | All of it | CUS-07 | none | — |
| SF-34.3 Rule on: evaluated, returns allow/warn/block | Missing | none | All of it | CUS-07 | none | — |
| SF-34.4 Block names the setting | Missing | none | All of it | CUS-07 | none | — |
| SF-34.5 Every setting change logged | Missing | none | All of it; `app.audit.command` must match `^[a-z]+\.[a-z_]+$` and has no product-less form (M1:140-141) | CUS-07 | M1:136-154 | — |
| SF-34.6 Firewall not in registry, cannot be switched off | Partial | M1:9-10; CLAUDE.md rule 6 | Met: the platform DB holds no response-level table and nothing can switch that on. Not met: no database test proves it (R6, A8), and there is no registry yet to be absent from | CUS-07 | M1:9-10 | — |
| **SF-35 Deal lifecycle** | Missing | none | All of it: no deals, pipelines, stages | PIP-01, PIP-02, PIP-03, PIP-06, PIP-07, PIP-11, PIP-13, PIP-14, PIP-17 | none | Deals.dc.html |
| SF-35.1 Deal created in pipeline/stage with owner; quality rules checked | Missing | none | All of it | PIP-03, CUS-02 | none | — |
| SF-35.2 Stage move or forecast date change saved optimistically, stage history, event | Missing | none | All of it | PIP-01, PIP-11, SF-02 | none | — |
| SF-35.3 Deleting a stage moves deals to target | Missing | none | All of it | PIP-02 | none | — |
| SF-35.4 Won/lost stores status and lost reason | Missing | none | All of it | PIP-07 | none | — |
| SF-35.5 Archive removes from active views; unarchive returns | Missing | none | All of it | PIP-13 | none | — |
| SF-35.6 Duplicate copies fields and products; restore returns to former stage | Missing | none | All of it | PIP-17 | none | — |
| **SF-36 Activity lifecycle** | Missing | none | All of it: no activities | ACT-01, ACT-02, ACT-03, ACT-05, ACT-06, ACT-07 | none | Activities.dc.html |
| SF-36.1 Activity created with type, owner, time, record; bulk creates one per record | Missing | none | All of it | ACT-01, ACT-06 | none | — |
| SF-36.2 Custom types and fields from registry | Missing | none | All of it | ACT-02, SF-38 | none | — |
| SF-36.3 Calendar reschedule updates activity and synced event | Missing | none | All of it | ACT-03, SF-08 | none | — |
| SF-36.4 Completing stamps time and user, publishes event | Missing | none | All of it | ACT-01, SF-02 | none | — |
| SF-36.5 No open activity: next-step prompt and warning icon | Missing | none | All of it | ACT-07 | none | — |
| **SF-37 Records, links and list operations** | Partial | M1:58-64, 98-109, 214-230, 249-257 | Step 1 partly met by product-event projection; steps 2-6 missing. Settings: Contact rule; Second-admin approval for bulk deletes and merges | CRM-01, CRM-02, CRM-03, CRM-10, CRM-13, CRM-14, CRM-15, PIP-08, PIP-09, PIP-10 | `app.accounts` M1:58; `app.members` M1:98; `ingest_events` M1:173-266 | Contacts.dc.html; Customers.dc.html; Deals.dc.html |
| SF-37.1 Person/org created or updated on admin's records with source stored | Partial | M1:214-230, 249-257, 66-76 | Met: organisations (`app.accounts`) and customer users (`app.members`, email/name/role) are created and updated from product events; the product and tenant that reported them are kept (`account_products`), and signup attribution in `attribution` jsonb. Not met: no staff create/update path; no person record beyond product members (no prospects); no source field per CUS/CRM-15 | CRM-01, CRM-15 | M1:58-76, 98-109, 214-257 | — |
| SF-37.2 Labels, related orgs, participants, followers stored as links; followers notified | Missing | none | All of it | CRM-13, CRM-14, PIP-08, PIP-09, SF-07 | none | — |
| SF-37.3 New address geocoded once for map | Missing | none | All of it; no address columns | CRM-03 | none | — |
| SF-37.4 Timeline built from activities and messages | Missing | none | All of it | CRM-02 | none | — |
| SF-37.5 Bulk edit one changelog entry per record; bulk delete preview | Missing | none | All of it | PIP-10 | none | — |
| SF-37.6 Export writes visible rows/columns to file, logged | Missing | none | All of it (formula neutralization A7.6) | CRM-10 | audit M1:136 | — |
| **SF-38 Field and configuration registry** | Partial | I18N:9-12; messages/no.json, messages/en.json | Step 4 partly met (interface text from message catalogs); steps 1-3, 5 missing | CUS-01, CUS-02, CUS-05, CUS-08 | next-intl I18N:9-12; `scripts/verify-i18n.mjs` | Settings.dc.html (demo tenant, Lumio) |
| SF-38.1 Field, quality rule or translation saved as versioned row | Missing | none | All of it | CUS-01, CUS-02, CUS-05 | none | — |
| SF-38.2 Forms, filters, reports, import, API read registry; no deploy | Missing | none | All of it | CUS-01 | none | — |
| SF-38.3 Quality rules evaluated on save and stage move | Missing | none | All of it | CUS-02, SF-35 | none | — |
| SF-38.4 Interface text served from translation catalog in user's language | Partial | I18N:9-12 | Met: every UI string comes from `messages/<lang>.json` (no, en), chosen per request. Not met: the language comes from a `lang` cookie, not a user profile; the catalog is files in the repo, not saved rows (step 1) | CUS-05 | I18N:9-12 | — |
| SF-38.5 Demo tenant has own config and sample data apart from live | Missing | none | All of it: no seed, no demo tenant (R8 names Lumio AS / Kari Nordmann; the design shows Lumio) | CUS-08 | none | — |
| **SF-39 Campaign authoring and insights** | Missing | none | All of it | CMP-01, CMP-02, CMP-09 | none | Marketing.dc.html; Insights.dc.html |
| SF-39.1 Builder saves rows and blocks; footer added automatically | Missing | none | All of it | CMP-01 | none | — |
| SF-39.2 Design saved to/loaded from template store | Missing | none | All of it | CMP-02 | none | — |
| SF-39.3 Test send and previews render same output as final | Missing | none | All of it | CMP-01 | none | — |
| SF-39.4 Provider events rolled up per campaign | Missing | none | All of it | CMP-09, SF-19 | none | — |
| SF-39.5 Insights reads rollups | Missing | none | All of it | CMP-09, INS-01 | none | — |
| **SF-40 Video links and mail client add-ons** | Missing | none | All of it | COM-11, COM-14 | none | Activities.dc.html; Inbox.dc.html |
| SF-40.1 Video provider link stored on activity and invite | Missing | none | All of it | COM-11 | none | — |
| SF-40.2 Provider failure: activity saved without link, user told | Missing | none | All of it | COM-11 | none | — |
| SF-40.3 Add-on signs in as user, calls same API | Missing | none | All of it; no public API (SF-22) | COM-14, INT-01 | none | — |
| SF-40.4 Add-on records carry add-on as source | Missing | none | All of it | COM-14, CRM-15 | none | — |
| **SF-41 Connectors, app platform and AI connector tools** | Partial | M1:47-54, 302-324; PAGE:39-50, 88-101 | Step 2 partly met by the product-installation status; the rest missing | INT-05–INT-11, AIA-06, MCP-02, MCP-03 | `app.installations` M1:47-54 (`enabled` gate M1:187, 285); `platform_status` M1:302-325 | Platform.dc.html; Settings.dc.html |
| SF-41.1 Install connector from catalog, grant scopes via OAuth | Missing | none | All of it; installations are SQL rows plus `secret-intake` (M2, SI), no catalog or OAuth | INT-05 | M1:47-54; per-command scopes OC:8-44 | — |
| SF-41.2 Connector status and error rate reported to admin's integrations status | Partial | M1:310-312, 322-324; PAGE:39-50, 88-101 | Met: the status page shows each installed product (enabled, host) and the last ten commands with ok/error. Not met: no error rate; applies to installed products, not catalog connectors | INT-05, INT-11 | M1:302-325; PAGE | — |
| SF-41.3 Deal events to team chat; invoice request to accounting adapter, status back | Missing | none | All of it | INT-06, INT-07 | none | — |
| SF-41.4 Extension panels in sandbox with scoped data | Missing | none | All of it | INT-08, INT-09 | none | — |
| SF-41.5 AI connector tools generated from API definitions; company switch blocks all | Missing | none | All of it | MCP-02, MCP-03, AIA-06 | none | — |
| SF-41.6 Removing connector revokes grants | Missing | M1:187, 285 | All of it for connectors. (Setting `installations.enabled=false` stops commands and events for a product, M1:187, 285 — a kill switch, not grant revocation) | INT-05 | M1:52, 187, 285 | — |
| **SF-42 Project lifecycle** | Missing | none | All of it | PRJ-01–PRJ-05, PRJ-07, PRJ-08, PRJ-09 | none | Projects.dc.html |
| SF-42.1 Project from won deal or scratch, optional template dated from start | Missing | none | All of it | PRJ-01, PRJ-02 | none | — |
| SF-42.2 Tasks, subtasks, milestones, activities added, pasted or imported | Missing | none | All of it | PRJ-03 | none | — |
| SF-42.3 Dependency saved unless it forms a cycle | Missing | none | All of it | PRJ-04 | none | — |
| SF-42.4 Dragging phase shifts items keeping spacing | Missing | none | All of it | PRJ-05 | none | — |
| SF-42.5 Phase change publishes event | Missing | none | All of it | PRJ-07, SF-02 | none | — |
| SF-42.6 Notes, files, mentions, emails attach; status report PDF | Missing | none | All of it | PRJ-08, PRJ-09, SF-33 | none | — |
| **SF-43 User administration and data protection** | Partial | M1:18-23, 29; LOGIN:144-148; README:27-29 | Step 2 partly met; step 4 Unknown; steps 1, 3, 5 missing | SEC-09, SEC-10 | `app.admins` M1:18-23 (`active` read by `admin_email` M1:29) | Security.dc.html (backup, restore test); Settings.dc.html |
| SF-43.1 Admin invites user, assigns role, team, visibility group | Missing | README:27-29 | All of it: users are created by hand in the Supabase dashboard and rows added to `app.admins` by SQL; role is owner/admin only; no team or visibility group | SEC-09 | M1:18-23 | — |
| SF-43.2 Deactivating ends sessions, prompts workflow transfer, reassigns records | Partial | M1:21, 29, 35 | Met: `active=false` makes `admin_email()`/`is_admin()` false, so every RPC and command is refused immediately. Not met: sessions are not ended (sign-out is `scope: 'local'` only, LOGIN:146); no transfer or reassignment; no UI | SEC-09 | M1:29 | — |
| SF-43.3 Access settings copied from another user | Missing | none | All of it | SEC-09 | none | — |
| SF-43.4 Backups run on schedule; last success recorded | Unknown | none in repo | Whether Supabase backups run for project `zuvqbaejoktpekfsiyyr` depends on its plan and is not visible from the repository. Recording the last success: missing | SEC-10 | none | — |
| SF-43.5 Restore test run and recorded against recovery targets | Missing | none | All of it; recovery targets not defined (Part G open) | SEC-10 | none | — |
| **SF-44 Mobile client** | Missing | none | All of it: no mobile app, no public API | MOB-01, MOB-02, MOB-03, MOB-08, AIA-07 | none | Mobile.dc.html |
| SF-44.1 App signs in, loads focus view from same API | Missing | none | All of it | MOB-01, INT-01 | none | — |
| SF-44.2 Real-time changes while open | Missing | none | All of it | MOB-02 | none | — |
| SF-44.3 Nearby asks for location, queries by distance | Missing | none | All of it | MOB-03, CRM-03 | none | — |
| SF-44.4 Business card read on device as contact draft | Missing | none | All of it | AIA-07 | none | — |
| SF-44.5 Chat takeover, project tasks, statistics use same endpoints | Missing | none | All of it | MOB-08, LGN-02, PRJ-03 | none | — |
| **SF-45 Lead lifecycle** | Missing | none | All of it: no leads. `demo.requested` / `contact.submitted` events arrive and are stored raw (M1:261-262) but become nothing | LEA-01, LEA-02, LEA-03, LEA-05, LEA-06 | `app.events_in` M1:122-133 | Contacts.dc.html; Inbox.dc.html |
| SF-45.1 Lead created with source, linked to person or org | Missing | none | All of it | LEA-01, LEA-04 | none | — |
| SF-45.2 Labels and owner set, by hand or assignment rule | Missing | none | All of it | LEA-02, SF-06 | none | — |
| SF-45.3 Emails/messages stored on lead; connected-channel message arrives in inbox | Missing | none | All of it | LEA-05, LEA-06, SF-03, SF-28 | none | — |
| SF-45.4 Convert to deal in chosen pipeline/stage, moving notes, activities, emails, files | Missing | none | All of it | LEA-03, SF-35 | none | — |
| SF-45.5 Convert back returns to inbox with history | Missing | none | All of it | LEA-03 | none | — |
| SF-45.6 Archiving removes from inbox without deleting | Missing | none | All of it | LEA-01 | none | — |

### Counts per status

Flow rows (45): Implemented 0 · Partial 9 (SF-10, SF-15, SF-22, SF-27, SF-34, SF-37, SF-38, SF-41, SF-43) ·
Missing 35 · Conflict 1 (SF-01) · Unknown 0.

Step rows (238): Implemented 0 · Partial 13 · Missing 223 · Conflict 1 (SF-01.3) · Unknown 1 (SF-43.4).

## Part 7 — Coverage check: Part H against Appendix 1

Source: `/home/user/owntheagenda_admin/docs/crm-enrichment/INSTRUCTIONS.md` (4141 lines). No repository file was edited.

What I read, in full and in consecutive chunks: A2 (53–81), A12 (288–292), Part C (368–1577), Part H (2601–2728), Appendix 1 (2729–3776). For Parts D (1578–1905) and E (1906–2384) I extracted the headings and the IDs they cite with grep. I did not read their step text.

Method: I counted Appendix 1 rows by hand, section by section, and matched each row to its Part H entry. I extracted IDs with `grep '^#### XXX-NN'` over Part C. I took the IDs Part H cites from lines 2601–2728 and expanded ranges such as "INT-01 to INT-03". I compared set differences with a Python script. I checked mappings against the Part C row text, which I read in full.

#### 1. Counts

| Item | Claimed | Found | Numbering |
| --- | --- | --- | --- |
| Feature specs (Part C, `#### XXX-NN`) | 183 in 21 modules | **183** in 21 prefixes | Every prefix runs from 01 with no gaps and no duplicates. All 21 module counts match the feature-map table (lines 2472–2492): PIP 17, ACT 9, CRM 15, CUS 8, LEA 6, COM 14, AUT 12, INS 10, PRO 7, AIA 7, LGN 5, WEB 4, CMP 9, DOC 6, PRJ 9, MTG 8, SEC 11, ENT 4, INT 11, MCP 3, MOB 8 |
| User flows (Part D) | 29, UF-01..UF-29 | **29** | UF-01..UF-29, consecutive, no duplicates anywhere in the file |
| System flows (Part E) | 45, SF-01..SF-45 | **45** | SF-01..SF-45, consecutive, no duplicates anywhere in the file |
| Inventory rows (Appendix 1) | 276 (273 mapped + 3 not carried) | **276** | 18 sections in 21 tables or lists. AI CRM has 3 tables and Marketplace has 2, which gives the "21 inventory tables" |

Rows per section in Appendix 1. Each matches the "Rows:" figure in Part H: Automation 17, CRM 16, Customization 16, Email/comms 19, Insights 20, Integrations 17, Leads 13, Prospecting 10, Processes 18, AI CRM 20 (10+8+2), Email marketing 15, Projects 19, Lead generation 9, Web visitors 8, Documents 9, Privacy/security 14, Marketplace 16 (9 categories + 7 mechanics), Mobile 20. Total 276.

The two Part H "Result" claims also hold, checked by whether the ID string appears. Every one of the 183 IDs appears in Part D and in Part E, and neither part cites an ID that Part C does not define.

#### 2. Unmapped research rows

**None.** Every one of the 276 rows has a Part H entry. Three are declared "not carried": Named migration sources, Mailchimp migration and Partnership discounts. Part G open point 7 (line 2594) raises them as well.

Two rows are split across two entries, and both halves are covered:
- Mobile "Manual data sync and landscape view" goes to MOB-05 (sync) and MOB-01 (landscape).
- Mobile "Leads Inbox, Live Chat and Projects on mobile" goes to MOB-01 (leads) and MOB-08 (live chat, projects).

Part H mapped no rows from the Recent releases, Screenshots or Reviews sections, which is by design ("feature rows" only). A spot check showed that almost all release items appear in Part C anyway. One exception is in M11.

#### 3. Dangling IDs

- **Cited by Part H but not defined in Part C:** none.
- **Defined in Part C but not cited by any Part H row mapping:** 6 IDs, all justified in Part H prose:
  - ENT-01 (plan gating, line 2723)
  - CRM-14, ENT-04, LGN-05, PIP-15, PIP-17 (the "Five specifications cite no feature row" paragraph, line 2725)
- **Unjustified:** none. Issues I1 and I2 cover the justification paragraph itself.
- Over the whole file, no 3-letter-prefix ID appears that Part C does not define.

#### 4. Mismatches and inconsistencies

I sample-checked about 95 mappings against the Part C row text, more than the 25 required. The large majority agree in substance and in the source figures. Examples:
- AUT-05: 10 delays, 90 days, 7-day wait
- INT-04: 40 webhooks, 10 s timeout, retries at 3/30/150 s, 30-minute ban
- CRM-08: 208 cycles
- INS-01: 17 report types
- PRO-03: +25/+10/−10
- COM-07: 100 recipients
- DOC-05: 10 signers
- SEC-04: 60 days
- MCP-01: 30-minute sync
- AUT-02: 18 entity-event pairs

Issues found:

### Internal consistency of Part H

| # | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| I1 | Medium | PIP-17 is justified as "(deal duplication and the restore data row)". The Restore data row is a feature row, already mapped to CRM-12 (line 2641). Deal duplication appears nowhere in Appendix 1: the only duplication rows are Insights "Duplicate reports, goals and dashboards" and "Merge duplicates". So the duplication half of PIP-17 has no research source. | 476–478, 2641, 2725; grep "duplicat" over 2729–3776 |
| I2 | Low | The paragraph says "Five specifications cite no feature row", but ENT-01 cites none either. It is justified only by the plans sentence on line 2723. The count is six if ENT-01 is included. | 2723, 2725 |
| I3 | Low | The gap table says "Six user flows (UF-23 to UF-28) and nine system flows (SF-25 to SF-33) added" in the quality review. Under the "Flows added in the quality review" headings, Part D has UF-23..**UF-29** (7) and Part E has SF-25..**SF-34** (10). UF-29 and SF-34 are not in the history. The totals of 29 and 45 are still correct. | 2624; Part D heading at 1827, UF-29 at 1893; Part E heading at 2165, SF-34 at 2256 |
| I4 | Low | "The check found four gaps in the first draft … all four are now closed", but the gap table has 8 rows. Four came from the first draft, two from the quality review and two from the team review. The wording is ambiguous, not wrong. | 2605, 2618–2627 |

### Research row against its specification

| # | Severity | Research row (Appendix 1) | Mapped spec | Difference |
| --- | --- | --- | --- | --- |
| M1 | Medium | Marketplace "Nine app categories" (3411–3419) | INT-05..INT-09, COM-11, COM-12, DOC-06 | The cited IDs cover Accounting, Phone, Proposals and Remote work. They do not cover the **Chatbots** (Intercom, LiveChat, Crisp, WhatsApp Business), **Email marketing** (Mailchimp, Outfunnel …), **Lead generation** (Surfe, Jotform, Leadfeeder, Facebook Lead Ads …), **Resource management** (backup, export, dedupe) or **Task management** (Asana, Trello, monday) categories. INT-09 covers only no-code automation platforms. First-party equivalents exist (COM-13, LGN-01/02, CMP-*, LGN/PRO/WEB, CRM-10/11, AUT-07), but Part H does not cite them. |
| M2 | Medium | Integrations "Named app integrations" (3045–3049) | INT-09, INT-11 | INT-09 is automation platforms only, and INT-11 is a catalog. No spec defines connectors for Zendesk, monday, Facebook Lead Ads, Livestorm, Mailchimp, PandaDoc, Stripe, Dear Lucy, Dedupely or Textline. Zoom, Meet, Asana, Trello, DocuSign, Aircall and CloudTalk are covered elsewhere (COM-11, AUT-07, DOC-06, COM-12). |
| M3 | Low | Google Workspace (3021–3025): Google Tasks | INT-05 | INT-05 lists "tasks" but says it "Uses COM-02, ACT-09, CRM-04 and DOC-03". None of those defines Tasks sync. |
| M4 | Low | Email and phone enrichment (3158): inputs are name, LinkedIn, organization **and email address** | PRO-05 | PRO-05 lists name, organization and LinkedIn profile. The email-address input is missing. |
| M5 | Low | MCP tools (3235): includes convertLeadToDeal **and getLeadConversionStatus** | MCP-02 | MCP-02 names only "convert lead to deal". |
| M6 | Low–Med | Sample data **and tailored setup** (2946): a sign-up questionnaire on company size and industry, and removal from Quick help, the import page or Insights | CUS-08 | CUS-08 covers the sample records only. The tailored setup and questionnaire are missing, although the gap table (2627) says this row was added to CUS-08. |
| M7 | Low–Med | Languages (2940): 22 or 24 interface languages per user, including Norwegian, Swedish, Finnish, Estonian, German, French, Dutch and Polish | CUS-05 | CUS-05 commits only to English as default plus "further languages through the catalog". It names no set or count. |
| M8 | Medium | Campaigns editor (3676): footer "pre-filled" with sender address and unsubscribe link. Deliverability (3261) and Marketing status (3252) | CMP-01, CMP-03, CMP-08 | CMP-01 hard-codes "cannot be removed", which is stricter than the research ("pre-filled"). CMP-08 ("unauthenticated domain cannot send") and CMP-03 ("only subscribed") are hard gates. R5 and the Part C preamble (372) say every compliance rule is a setting with an unrestricted default. None of these three rules is in the CUS-07 settings register (686–702). |
| M9 | Low | "Team filters and goals" (3006), plus the "Team filters" tab in the Manage users screenshot (3711) | INS-05 | INS-05 covers team goals only. Team filters as a reporting filter are not explicit. SEC-09 says teams are "used by … reports" but Part H does not cite it for this row. |
| M10 | Low | Reverse email lookup (3163): the marketing page promises job titles, and the Knowledge Base fields have none (a discrepancy the research records) | PRO-07 | PRO-07 says "enriched fields" and does not settle whether job title is included. |
| M11 | Low (outside Part H scope) | Release Feb 2026 (3486): "participants on activities" | — | No Part C row makes activity participants explicit. ACT-01 links one deal, lead, person or organization. PIP-08 participants are suggested when scheduling, and ACT-08 covers guests. |

#### 6. Issue count

**15 issues**: 4 in Part H's internal consistency (I1–I4) and 11 research-to-spec mismatches (M1–M11). By severity:
- **Medium (4):** I1, M1, M2, M8
- **Low to medium (2):** M6, M7
- **Low (9):** I2, I3, I4, M3, M4, M5, M9, M10, M11

There are no unmapped rows, no dangling IDs and no number gaps or duplicates in the 183 features, 29 user flows or 45 system flows.
