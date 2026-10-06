# 05 — Gap against the specification

Phase A, A3.5. Every feature (183), user flow (29, with 169 steps), system flow (45, with 238 steps),
setting in the register (15), Part F item (199) and Part G non-functional requirement (17), judged
against **this repository only** (`main` `8c01aec`, 2026-10-06). Statuses and row format follow A3.5.
Each row also has two extra columns: the design screen that shows the feature (`design-reference/sentral/`)
and prior art in Orgpuls before migration 0206 (portable, but not counted). The "Work package" column is
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
per-user setting; the platform defaults to bokmål with a cookie, see Q-15).

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

The full question list is `06-QUESTIONS.md`.

---

## Part 1 — Features: PIP, ACT, CRM, CUS and the settings register

Repository judged: `/home/user/owntheagenda_admin` at `8c01aec`. Phase A: no file in the repository changed.

**Abbreviations used in Evidence**
- **[NOTAB]**: no table, column, function or seed for this exists. The whole schema is `supabase/migrations/0001_foundation.sql` (tables at l.18 admins, l.41 products, l.47 installations, l.58 accounts, l.66 account_products, l.80 subscriptions, l.98 members, l.111 usage_daily, l.122 events_in, l.136 audit) plus `0002_product_secrets.sql` (Vault secrets/intake). `supabase/tests/` is empty, there is no seeds folder, and there are no storage buckets, cron jobs or notification channels.
- **[NORT]**: no route, server action or component exists. The app consists of `app/page.tsx` (status page), `app/login/*`, `app/mfa/*`, `app/ingen-tilgang/page.tsx`, `app/actions.ts` and `app/TestButton.tsx`. The only tests are `tests/signing.test.ts` (4 unit tests, signing only).
- **Prior art** points to Orgpuls commit `ced4af2` (the parent of 0206). That code was removed and is not in the platform.
- **Settings that apply to every row**: `firewall` (fixed) and `typed_reason` ("Every CRM write and read of customer data") apply to every PIP, ACT, CRM and CUS feature. They are not repeated in each row. Setting keys come from the design's `admin-data.js` (`SA.settings`), because the brief's register defines no keys (see Q1).
- **Design screen** names the screen that shows the feature, confirmed by grepping the concept. `coverage-data.js` also maps every ID in scope to a route (PIP → deals, ACT → activities, CRM → contacts except CRM-07/08 → deals, CUS → settings).

### Feature rows

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen | Prior art (Orgpuls ≤0206) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PIP-01 Kanban pipeline view | Missing | [NOTAB] no deal/stage table; [NORT]; no event emitter for `deal.stage_changed` (ingest only receives events, 0001 l.173) | All of it: stage columns with drag-to-move, count and value per column, card content, optimistic save with rollback, changelog plus `deal.stage_changed`, paging per stage, visibility rules, no drop without edit rights | — | PIP-02, PIP-03, PIP-04 (changelog), SEC (visibility, edit rights), CUS-07 | — | Deals.dc.html (pipeline view, drag, column sums) | `app/(admin)/admin/crm/pipeline/page.tsx`; `crm_companies.stage` (0056) was a company stage, not a deal |
| PIP-02 Pipelines and stages | Missing | [NOTAB]; [NORT] | All of it: unlimited pipelines; ordered stages with name, probability 0–100 and optional rotting threshold; add, rename, reorder and delete with a target stage; pipeline visibility groups | (pipeline count via `plan_gates`, not listed in register) | SEC-visibility groups, PIP-05 | — | Settings.dc.html («Pipelines and stages»: stages, prob, rot); Deals.dc.html | `crm_stages` (0093: key, name, sort, kind; one global stage list, no pipelines or probability) |
| PIP-03 Deal record | Missing | [NOTAB] (no deal entity; `app.accounts` l.58 is a customer, not a deal) | All of it: deal fields incl. currency, probability, labels, source, status, custom fields; one primary person and one org; value derived from products; create with title only; history of every change | — | CRM-01, PIP-08, CRM-07, CUS-01, CUS-06, CRM-15, PIP-04 | — | Deals.dc.html | none (prior CRM tracked companies, not deals) |
| PIP-04 Deal detail view | Missing | [NOTAB] (no changelog table; `app.audit` l.136 only records product commands, with no field or old/new values); [NORT] | All of it: header (owner, followers, Won/Lost), stage bar, sidebar sections that can be reordered and hidden, tabs (notes … invoice), Focus list, paginated and filterable History, changelog entry (field, old, new, user, time, source) | — | PIP-03, PIP-09, PIP-08, CRM-05, CRM-06, ACT-01, COM (email), DOC, invoicing provider (unnamed) | — | Deals.dc.html (detail, changelog, history, participants) | `admin/crm/prospects/[id]/page.tsx`, `crm_activities` (0056) |
| PIP-05 Deal rotting | Missing | [NOTAB] (no per-stage threshold, no idle clock); no notification channel or job exists | All of it: per-stage optional threshold, red card with idle days, owner notified, clock reset on stage move, completed activity, email or note | — | PIP-02, ACT-01, COM, CRM-06, notifications (unspecified module) | — | Deals.dc.html («Rotting · idle N days»); Settings.dc.html (stage `rot`) | `crm_companies.last_activity_at` (0056), no threshold |
| PIP-06 Deal labels | Missing | [NOTAB]; [NORT] | All of it: colored labels (several per deal) on cards, rows and detail; label filter; managing labels requires a settings permission; deleting a label removes it from all deals | — | SEC (settings permission), PIP-12 | — | Deals.dc.html (labels, «Any label» quick filter) | `crm_companies.tags text[]` (0056), not colored and not managed |
| PIP-07 Won, lost and lost reasons | Missing | [NOTAB] | All of it: close as won or lost; lost reason as free text or from a list; optional comment saved as a note; admin-managed list; a reason can be made mandatory; reopening keeps history; reason as a reporting dimension | (mandatory reason is a rule with no register row, Q6) | PIP-03, CRM-06, INS | — | Deals.dc.html (`lostReasons`, won/lost modal); Insights.dc.html | `crm_companies.lost_reason` text (0056); `crm_stages.kind` won/lost (0093) |
| PIP-08 Participants | Missing | [NOTAB] (`app.members` l.98 are a tenant's product users, not deal participants) | All of it: extra people per deal (not the primary person); suggested in the scheduler and composer; added from an email's recipients; bulk import; removed when the person is deleted | — | CRM-01, COM, ACT-08, CRM-09 | — | Deals.dc.html («Person · organization · participants», addParticipant) | none |
| PIP-09 Followers | Missing | [NOTAB]; no notifications | All of it: following deals, people, orgs, products and users; grants visibility and notifications only; follower notified on a stage change | — | SEC (visibility), notifications, CRM-07 | — | Deals.dc.html (follow button, «followers notified») | none |
| PIP-10 List view | Missing | [NOTAB]; [NORT]; no export | All of it: selectable columns, multi-column sort, inline, bulk edit and bulk delete, CSV/XLSX export, system ID shown and addressable, admin default columns, bulk-edit permission, exports respect visibility, one changelog entry per deal on bulk edit | `second_admin` | PIP-04, CRM-10, SEC-02, SEC (bulk-edit permission) | — | Deals.dc.html (List view, column picker incl. System ID, bulk bar, CSV) | none |
| PIP-11 Forecast view | Missing | [NOTAB]; [NORT] | All of it: date columns by close date or a custom date field; open, won and projected per column; drag changes the date; week, month or quarter; pipeline and owner filters; stage bar on cards | — | PIP-03, CUS-01, PIP-12 | — | Deals.dc.html (forecast by `closeMonth`); Insights.dc.html | none |
| PIP-12 Filters | Missing | [NOTAB]; [NORT] (no search function) | All of it: global search (name, email, phone, field value); quick and advanced ALL/ANY filters; saved filters with visibility and favorite; across 7 entities; operators by field type; configurable listing; same set in pipeline, list and forecast | — | CUS-01, LEA, PRJ, CRM-07, ACT-01 | — | Deals.dc.html (quick filters, `conds`, `savedFilters`); Contacts.dc.html (search name/email/phone); Sentral Admin.dc.html (search) | `crm_segments.filter jsonb` (0055), contacts only |
| PIP-13 Archive | Missing | [NOTAB] (`account_products.status` 'deleted' l.70 is product deletion, not archive) | All of it: archive and unarchive leads and deals with history kept; excluded from default views and from capacity; archive view | (capacity via `plan_gates`/ENT-02, not listed) | ENT-02, LEA, PIP-16 | — | Deals.dc.html («Archive and restore» view) | `crm_lists.archived_at`, `crm_stages.archived_at` (lists and stages, not deals) |
| PIP-14 Deal card customization | Missing | [NOTAB]; [NORT] | All of it: configurable card fields per pipeline, rendered on every card | — | PIP-01, PIP-02, CUS-01 | — | Deals.dc.html («Fields on cards in {pipeline}») | none |
| PIP-15 Closed deals toggle and stage timing | Missing | [NOTAB] (no stage history; no per-user preference store) | All of it: won/lost toggle remembered per user; progress bar with days per stage from stage history | — | PIP-01, PIP-10, PIP-04 | — | Deals.dc.html (`showClosed` toggle; `progress` with «N d») | `crm_stage_changes` (0137) |
| PIP-16 Capacity and waitlist | Missing | [NOTAB]; [NORT] | All of it: when a capacity is set, manual adds are blocked and automation, API, chatbot, form and import adds go to a filterable waitlist that can be bulk-added; no payload lost; no limit by default | `plan_gates` (ENT-02; register lists ENT only) | ENT-02, AUT, INT, LGN, CRM-09, CRM-15 | — | Deals.dc.html («Capacity: unlimited (setting) · waitlist»); Settings.dc.html (overflow to waitlist) | none |
| PIP-17 Duplicate and restore | Missing | [NOTAB] (no soft delete) | All of it: duplicate with fields and products, without history or emails; restore within 30 days back to the deal's stage | (30-day window has no register row, Q7) | CRM-12, CRM-07 | — | Deals.dc.html («Duplicate with products», «Deleted — restorable for 30 days») | none |
| ACT-01 Activities | Missing | [NOTAB]; [NORT] | All of it: activity with type, subject, date, time, duration, owner, note, done, and a link to deal, lead, person, org or project (one deal); completion stamps time and user and can trigger automations; workflow-created flag; shows in the linked record's history | — | PIP-03, CRM-01, LEA, PRJ, AUT | — | Activities.dc.html | `crm_activities` (0056: kind note/call/meeting/email/task, due_at, done_at, company link) |
| ACT-02 Custom activity types and fields | Missing | [NOTAB] | All of it: add, rename, order and deactivate types; custom outcome fields; deactivated type kept on past activities; new type immediately selectable and reportable | — | ACT-01, CUS-01, INS | — | Settings.dc.html («Activity types») | none (kinds were a check constraint) |
| ACT-03 Calendar and list views | Missing | [NORT] | All of it: day, week and month calendar plus to-do list; filters by user, type and status; drag to reschedule (updates the synced event); manager visibility; project tasks shown alongside | — | ACT-01, ACT-09, SEC, PRJ | — | Activities.dc.html («Calendar», «To-do list») | `admin/crm/tasks/page.tsx` |
| ACT-04 Reminders | Missing | No email provider, push, desktop notification or job (context file; nothing in the repo) | All of it: reminders in app, by email, desktop and push, combined per user; per-user timing; optional daily summary; productivity tips in the notification center; fires once per channel | — | ACT-01, email provider, MOB (push), notifications | — | Activities.dc.html («Reminders and sync») | none |
| ACT-05 Priority labels | Missing | [NOTAB] | All of it: high, medium and low; inline and bulk edit; shown in calendar and list; filterable and sortable | — | ACT-01, ACT-03, ACT-06 | — | Activities.dc.html (priority) | none |
| ACT-06 Bulk activities | Missing | [NORT] | All of it: create or edit activities for many records from list views or inbox; bulk-edit permission; one activity per selected record | — | ACT-01, PIP-10, COM (inbox), SEC | — | Activities.dc.html (selection) | none |
| ACT-07 Next-step prompt | Missing | [NOTAB] | All of it: prompt for the next activity on done (switchable per user); warning icon on cards of deals with no planned activity | — | ACT-01, PIP-01 | — | Activities.dc.html; Deals.dc.html (next step, «No planned» warning) | `crm_companies.next_step`, `next_step_at` (0056) |
| ACT-08 Activity invites | Missing | No calendar integration | All of it: guests get invites through the synced calendar; responses tracked on the activity | — | ACT-09, PIP-08 | — | Activities.dc.html (guests, invite) | none |
| ACT-09 Calendar sync | Missing | No Google or Microsoft integration; no OAuth tokens table | All of it: one- or two-way Google/Microsoft sync; choice of calendar and activity types; private stays private; recurring external events read-only, not created natively; changes on either side propagate | — | ACT-01, INT, providers (Google, Microsoft) | — | Activities.dc.html (sync tab); Meetings.dc.html | none |
| CRM-01 People and organizations | Partial | Met: an organization has a name (`app.accounts.name` 0001 l.60, also org_number l.61); a person has a name and one email (`app.members.name`, `email` l.103–104); a person's organization comes through `(product, tenant_id) → account_products.account_id` (l.69, l.108); respondents stay outside by construction, since ingest projects only `member.*` users (l.249–257, comment l.97 «contacts, never respondents», l.9–10), but no database test proves this. Shown in the UI only as a count (`app/page.tsx:54`, `platform_status` l.313) | Not met: several emails, phones, owner, labels, marketing status and custom fields on a person; address, owner, labels and custom fields on an org; detail views with history, deals, activities, files and emails; "opening a person shows every linked deal…"; contact rule setting; no person entity across tenants (one row per product+tenant+user, so "at most one organization" is undefined, Q3). Records are product projections, not admin-owned (Q2) | `contact_rule` | SEC (visibility), CUS-01, CRM-14, PIP-03, ACT-01, CRM-05, COM | — | Contacts.dc.html (people and orgs tabs, marketing status); Customers.dc.html | `crm_contacts` (0055), `crm_companies` (0056), `admin_org_notes` (0049), `account_owners` (0118) |
| CRM-02 Contacts timeline | Missing | [NORT] | All of it: one row per person or org with activity icons on a time axis, today marker, overdue in red; controls for look-back, follow-up frequency, type and owner; matches the record's history | — | ACT-01, CRM-01 | — | Contacts.dc.html («Timeline» tab) | none |
| CRM-03 Contacts map | Missing | [NOTAB] (no address or geocode columns); [NORT] | All of it: map by address, filter by city, region and country; geocode once and cache; records without an address listed separately | — | CRM-01, geocoding/map provider (unnamed) | — | Contacts.dc.html («Map», «map tiles · provider adapter») | `crm_companies.municipality` (0056) only |
| CRM-04 Contact sync | Missing | No Google or Microsoft integration | All of it: two-way address book sync; user picks contacts; match by email; new contacts follow the contact rule | `contact_rule` | CRM-01, INT, providers | — | Contacts.dc.html («Two-way sync · Google Contacts · Microsoft 365») | none |
| CRM-05 File attachments | Missing | No storage bucket (context file; no `storage.buckets` in migrations) | All of it: files on leads, deals, people, orgs, products and projects; listed in history; same visibility as the record; no fetch without record access | — | storage, SEC, all record types | — | Deals.dc.html (files tab); Contacts.dc.html (files) | `0124_media.sql` (CMS media, not record attachments) |
| CRM-06 Notes, mentions and comments | Missing | [NOTAB]; no notifications | All of it: rich-text notes on any record; @mention notifications that respect visibility and open the record; threaded comments; pinned notes | — | SEC, notifications, all record types | — | Deals.dc.html (notes, pin, comments); Contacts.dc.html (notes, pin) | `admin_org_notes` (0049), `crm_activities` kind 'note' |
| CRM-07 Product catalog | Missing | [NOTAB] (`app.products` l.41 is the platform's installed software products, not a sales catalog) | All of it: catalog (code, unit, prices per currency, tax, variations, notes, custom fields); deal lines with quantity, price and discount; deal value recalculated; default tax mode per user; spreadsheet import | — | PIP-03, CUS-01, CUS-06, CRM-09 | — | Deals.dc.html («Products» view) | none |
| CRM-08 Subscriptions and installments | Missing | [NOTAB] for product lines. Billing mirror exists (`app.subscriptions` 0001 l.80–95: plan, billing_interval, trial/cancel dates) but holds no amount or currency (ingest l.237–242), so it cannot yield MRR, ARR, ACV or TCV | All of it: recurring lines (frequency, until cancelled or N cycles up to 208); installments; MRR, ARR, ACV and TCV computed; Orgpuls subscriptions from the billing mirror; feeds INS-06 | — | CRM-07, billing mirror, INS-06 | — | Deals.dc.html (installment); Customers.dc.html, Analytics.dc.html (MRR/ARR) | none in CRM (billing lived in Orgpuls itself) |
| CRM-09 Import | Missing | [NORT]; [NOTAB] | All of it: spreadsheet import of all entities in one session; mapping (AI suggestion); duplicate detection with merge or create; skip file with reasons; import history; rows over capacity to the skip file; consent source per row as a setting | `import_consent`; (capacity via `plan_gates`) | AIA-05, CRM-11, ENT-02, all record types | — | Contacts.dc.html («Import», skip file); Settings.dc.html | Orgpuls 0055 l.10: import required a consent source per row (default on there) |
| CRM-10 Export | Missing | [NORT] | All of it: export of any list view and full data sets to CSV/XLSX; export permission; logged for SEC-02; exactly the rows and columns visible | — | SEC, SEC-02, PIP-10 | — | Contacts.dc.html («Export», XLSX); Deals.dc.html (CSV) | `admin/crm/consent/export/route.ts`, `admin/audit/export/route.ts` |
| CRM-11 Merge duplicates | Missing | [NOTAB] (only exact `org_number` match when ingest creates an account, 0001 l.216, which is not configurable and has no review) | All of it: admin-configured matching rules; review list; flag on detail; compare view; pick surviving values; move deals, activities, emails and files; one record with combined history | `second_admin` | CRM-01, PIP-03, ACT-01, CRM-05 | — | Contacts.dc.html («Duplicates», merge) | none |
| CRM-12 Restore data | Missing | [NOTAB] (no soft delete; `app.audit` is append-only, l.148–154, but only records commands) | All of it: 30-day deleted list with who, when and source; restore with links intact; revert bulk changes; covers 6 entities; permission-based; bulk delete preview; second-admin approval setting | `second_admin` | SEC, PIP-17, all record types | — | Contacts.dc.html («Restore»); Deals.dc.html | none |
| CRM-13 Related organizations | Missing | [NOTAB] | All of it: parent, daughter and related links between orgs, shown on detail both ways | — | CRM-01 | — | Contacts.dc.html («Related organizations», add as parent/daughter/related) | none |
| CRM-14 Contact labels | Missing | [NOTAB] | All of it: colored labels on people and orgs, separate from deal and lead labels, filterable | — | CRM-01, PIP-12 | — | Contacts.dc.html (labels) | `crm_contacts.tags` (0055), `crm_companies.tags` (0056) |
| CRM-15 Source fields | Missing | [NOTAB] for leads and deals. `account_products.attribution` (l.72, filled from `org.attribution` l.233–235) records where a customer came from, which is not a lead or deal source | All of it: source on leads and deals from the 13 listed origins; filled automatically on creation; kept through conversion and archive; a reporting dimension | — | LEA, PIP-03, PIP-13, INS | — | Deals.dc.html (Source column/option); Contacts.dc.html | `crm_contacts.source`, `crm_companies.source` (0055/0056); `org_attribution` |
| CUS-01 Custom fields | Missing | [NOTAB]; [NORT] | All of it: 16 field types on 6 entity groups; field groups; shown in add forms and details; options per field (reference 1,000); field count as entitlement; appears in forms, filters, reports, import and API without a deploy | `count_limits`; (field count via `plan_gates`, not listed) | ENT-02, PIP-12, CRM-09, INT, INS | — | Settings.dc.html («Data fields», types, 1,000) | none |
| CUS-02 Field quality rules | Missing | [NOTAB] | All of it: important/required, optionally from a stage; description info icon; required enforced on manual edits and reported on API/import; stage move blocked by empty required fields | (a required rule blocks; no register row, Q6) | CUS-01, PIP-02 | — | Settings.dc.html (required/important); Deals.dc.html | none |
| CUS-03 Pipeline-specific and read-only fields | Missing | [NOTAB] (no per-field access; DB access model is admin-only via `app.is_admin()` l.32) | All of it: field limited to pipelines; read-only or hidden per user; enforced in the database; no channel leaks a hidden field | — | CUS-01, PIP-02, SEC, INT, MCP, CRM-10 | — | Settings.dc.html (read-only, visibility) | none |
| CUS-04 Formula fields | Missing | [NOTAB] | All of it: numeric/monetary deal fields computed from others; recalculated on input change; no self-reference; stored value equals formula | — | CUS-01, PIP-03 | — | Settings.dc.html (`[deal.value] * [deal.probability] / 100`); Deals.dc.html («formula · value × probability») | none |
| CUS-05 Languages and locale | Conflict | Platform: locale is `no` unless cookie `lang=en` (`lib/i18n/request.ts:9`); time zone fixed `Europe/Oslo` for everyone (`request.ts:10`); `no` is the source language (`CLAUDE.md:12–13`); catalog is `messages/no.json`, `messages/en.json`; `<html lang>` follows it (`app/layout.tsx:18`) | Spec: English is the default; language, date and number format and time zone are per user; catalog-extensible; switch without reloading data. Code: Norwegian default, per-browser cookie (not per user), fixed time zone, no date or number format choice. Partly met: a translation catalog exists with two languages and no locale routing | — | Appendix 2 decision, SEC (user profile) | — | Settings.dc.html («Language and currencies», state `lang: 'English'`); the design is authored in English | Orgpuls `crm_contacts.lang` default 'no' (0055) |
| CUS-06 Currencies | Missing | [NOTAB] | All of it: deals and products in major and custom currencies; company default; stored exchange rates; report-time conversion | — | PIP-03, CRM-07, INS | — | Settings.dc.html (currencies, exchange rates) | none |
| CUS-07 Module switches and rule settings | Missing | [NOTAB] (no settings registry, no module table; `app.installations.enabled` l.52 switches a product connection, not a module; `app.audit` l.136 requires a product and a `x.y` command, l.140–141, and is written only by `record_command`, l.271). Orgpuls `settings.*` commands set Orgpuls's own notice/indexing, not this register | All of it: module on/off (hidden from nav, API returns a disabled error); registry of every rule in the register below with defaults unrestricted; changes logged; Products off hides it for all users; no feature blocked by defaults | all register keys | A9, SF-34, UF-29, SEC | — | Settings.dc.html («Rules and limits», «Modules», change log); Sentral Admin.dc.html | `crm_settings` (0055: single flag `customer_exception` with changed_by and changed_at) |
| CUS-08 Sandbox | Missing | No seed, demo tenant or sample-record flag in the repo (no `supabase/seed*`; grep for Lumio/Kari outside `design-reference/` finds nothing) | All of it: a separate test company; optional sample records marked and removable in one step; equals the seeded demo tenant (Lumio AS / Kari Nordmann per R8); never customer data; sandbox changes never touch live | — | R8, Appendix 2 (seeded demo tenant), AUT | — | Settings.dc.html («Sandbox»); Sentral Admin.dc.html (sample data) | Orgpuls fixture `scripts/seed/design-fixture.mjs` (a product fixture, not an admin sandbox) |

### Settings register (from "Settings managed in CUS-07", l.684–702)

There is no settings registry in the platform ([NOTAB]; context file). Keys are taken from the design (`admin-data.js` `SA.settings`). The brief gives none (Q1).

| Key | Default per spec | Applies to | Status | Evidence |
| --- | --- | --- | --- | --- |
| `contact_rule`: Contact rule (No rule; source and basis required; opt-in only) | No rule | CRM-01, CRM-04, LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, MTG-05, MOB-01 | Missing | [NOTAB]. Design: Settings.dc.html rules list; Contacts.dc.html. Prior art: Orgpuls `crm_contacts.basis` + `crm_settings.customer_exception` (0055) |
| `import_consent`: Consent source on import (Off; required per row) | Off | CRM-09 | Missing | [NOTAB]. Prior Orgpuls behavior required it (0055 l.10), the opposite default (Q9) |
| `sales_consent`: Consent and suppression checks on sales email (Off; warn; block) | Off | COM-07, AUT-07, AUT-12 | Missing | [NOTAB]. Prior art: Orgpuls `crm_suppression` (0055) |
| `tracking`: Email open and click tracking (On; off; per email) | On | COM-06 | Missing | [NOTAB]; no email provider |
| `form_tracking`: Form tracking fields (UTM, cookies, referrer) (On; off) | On | LGN-03 | Missing | [NOTAB] |
| `web_ident`: Web visitor identification (On; off) | On | WEB-01 to WEB-04 | Missing | [NOTAB] |
| `second_admin`: Second-admin approval for bulk deletes and merges (Off; on) | Off | PIP-10, CRM-11, CRM-12 | Missing | [NOTAB]; `app.admins.role` owner/admin only (0001 l.20), no approval flow |
| `count_limits`: Count limits from the source (Unlimited; a number) | Unlimited | AUT-05, AUT-07, COM-07, INT-04, DOC-05, CUS-01, PRO-03 | Missing | [NOTAB]. Note: `ingest_events` caps a batch at 500 events (0001 l.190). That is a hard-coded intake cap, but not one of the listed count limits (Q10) |
| `plan_gates`: Plan gates and usage limits (All on and unlimited; per plan) | All on and unlimited | ENT-01, ENT-02 | Missing | [NOTAB]. `app.subscriptions.plan` (l.83) mirrors the customer's plan in the product, not admin entitlements |
| `api_rate`: API rate limits (Off; source values; custom) | Off | INT-03 | Missing | [NOTAB]; no public CRM API |
| `safeguards`: Workflow loop protection, webhook retry and ban policy (Source values; custom; off) | Source values | AUT-09, INT-04 | Missing | [NOTAB]. Event intake has its own fixed safeguards (5-minute age limit, duplicate refusal: CLAUDE.md rule 4; `events_in` unique l.131). These cover inbound product events, not CRM webhooks |
| `firewall`: Anonymity firewall (Fixed) | Fixed | Every feature (platform constant) | Partial | Met by construction: no response-level table in the platform (0001 l.18–136); comment l.9–10; ingest projects only listed kinds (l.225–263); CLAUDE.md rule 6. Not met: `events_in` keeps any payload "as it arrived" (l.201, l.262), so exclusion relies on Orgpuls's event registry; no database test proves it (A8, R6); `supabase/tests/` is empty. Design lists it as a fixed register row (Q4) |
| `typed_reason`: Typed reason for CRM actions (Off; on) | Off | Every CRM write and read of customer data; the audit row itself is always written | Missing | [NOTAB]. `app.audit` (l.136) records only product commands (`record_command` l.271), not CRM reads or writes |
| `widget_consent`: Consent-gated loading of site widgets (Off; on) | Off | LGN-05 | Missing | [NOTAB] |
| `rec_notice`: Recording consent notices to attendees (On with 24 h; custom; off) | On with 24 hours' notice | MTG-02, MTG-08 | Missing | [NOTAB] |

### Questions and conflicts

1. **The register has no keys, types or scopes.** A9 says each registry entry has "a key, a type, its options, its default, its scope and the IDs it applies to". The Part C register (l.684–702) gives only setting, options, default and applies-to. The design's `admin-data.js` supplies keys and groups but no scope (company, user, pipeline). Should the design keys be adopted, and what is each setting's scope? Affects CUS-07 and every register row.
2. **Who is the source of truth for org and contact records?** CRM-01 says "The admin's organization and contact records stay the source of truth; this module adds columns and related tables". In the platform, `app.accounts` and `app.members` are projections that `ingest_events` writes from product events: `org.created` overwrites `accounts.name` (0001 l.228) and `member.joined` overwrites `members.name`, `email` and `role` (l.252). Does the CRM edit these rows (and get overwritten by events), or keep its own person and org tables linked to them? Affects CRM-01, CRM-11, CRM-13, CRM-14, PIP-03.
3. **What is a "person" in the platform?** `app.members` is keyed by (product, tenant_id, user_id) (l.107), so the same human in two tenants or products is two rows, and there is no email uniqueness. CRM-01 requires "a person belongs to at most one organization". How should a person entity map onto members, and can a CRM person exist without being a product user (a prospect)? Affects CRM-01, CRM-04, CRM-09, CRM-11, PIP-08.
4. **Is the firewall in the registry or not?** A9 (l.253) says "The anonymity firewall is not in the registry and cannot be switched off". The register in Part C (l.700) lists it as a row, and the design's Settings shows it as a fixed row. Should it be shown read-only in the settings screen or kept out of the registry entirely? Affects CUS-07, UF-29.
5. **Locale and time zone (Conflict, CUS-05).** The spec and design say English is the default and language, format and time zone are per user. The platform makes `no` the source and default and fixes Europe/Oslo (`lib/i18n/request.ts:9–10`, `CLAUDE.md:12–13`, and the latest commit `8c01aec` "Show times in Norwegian time"). Which wins, and should the locale move from a cookie to a per-admin profile? Affects CUS-05 and every UI string.
6. **Restrictions with no register row.** R5 says every limit, approval step and compliance rule is a setting that is off by default. These Part C rules have no register entry: PIP-07 "can make a reason mandatory", CUS-02 "required (blocks saving)", PIP-06 "Label management needs a settings permission", PIP-10/ACT-06 "bulk-edit permission", CRM-10 "export permission", CRM-11 admin matching rules. Are admin-configured field and record rules and permissions outside R5's scope (data configured per company), or should each have a register row? Affects PIP-06, PIP-07, PIP-10, ACT-06, CRM-10, CRM-11, CUS-02, CUS-03.
7. **Numbers from the source with no register row.** A9 says "a number from the source product is a reference value for a setting". These numbers have no register entry: the 30-day restore window (PIP-17, CRM-12), "up to 208" billing cycles (CRM-08), recurring external events read-only and not created natively (ACT-09), and pipelines "Unlimited" (PIP-02). Should they be added to `count_limits` or as new rows? Affects PIP-02, PIP-17, CRM-08, CRM-12, ACT-09.
8. **Capacity and entitlements.** The register maps `plan_gates` only to ENT-01 and ENT-02, but PIP-13, PIP-16, CRM-09 (capacity) and CUS-01 (field count) all depend on ENT-02. Confirm that these features read `plan_gates`. Affects PIP-13, PIP-16, CRM-09, CUS-01.
9. **Consent defaults versus earlier Orgpuls decisions.** In Orgpuls before 0206, imports had to name a consent source per row, and the customer exception under markedsføringsloven § 15 was a setting off by default, turned on only with a reason (0055 l.10, l.14–17). The brief defaults `import_consent` and `sales_consent` to Off, which is less restrictive than that legal reading. Confirm the defaults are intended for the platform. Affects CRM-09, CRM-01, COM-07.
10. **A hard-coded intake cap in existing code.** `ingest_events` refuses a batch over 500 events (0001 l.190). R5 forbids hard-coded caps that block a feature, but this is a technical limit on inbound product events. Is it outside the register (like the firewall), or should it become a `safeguards` value? Affects the `safeguards` and `count_limits` rows.
11. **Demo tenant and sandbox are missing.** R8 says "verify that seed exists and ask if it does not". No seed exists in the platform (no `supabase/seed*`, and `supabase/tests/` is empty). CUS-08 says the sandbox "is the seeded demo tenant" and "a separate test company", but the platform is one database shared across products. Should the sandbox be a flagged account (Lumio AS / Kari Nordmann) in the same database, a separate Supabase branch, or a tenant in Orgpuls? Affects CUS-08 and all verification (A8).
12. **Brief says "Orgpuls admin", target is a multi-product platform.** CUS-08 and CRM-01 refer to "the Orgpuls admin". The target repository serves several products (`app.products`, l.41). Should CRM records (deals, products and so on) be scoped per product, per company, or be global? Affects PIP-03, CRM-01, CRM-07, CUS-08.
13. **Name clash on "products".** The platform's `app.products` (l.41) is the installed software products. CRM-07's "Product catalog" is a sales catalog, and CUS-07's acceptance test says "Turning Products off". The two need distinct names in schema and UI. Affects CRM-07, CUS-07.
14. **The billing mirror holds no amounts.** CRM-08 says Orgpuls subscription figures (MRR, ARR, ACV, TCV) come from the billing mirror, but `billing.changed` carries no price, amount or currency (0001 l.237–242). Should Orgpuls's event registry be extended, or should plan prices be held in the platform? Affects CRM-08, INS-06.
15. **Recording consent default versus A9.** A9 says "consent checks … default to off". `rec_notice` defaults to On (24 hours), justified as "as in the source". Confirm that a notice is not a "consent check" under A9. Affects MTG-02, MTG-08.
16. **Providers are unnamed.** Invoicing (PIP-04 invoice tab), map and geocoding (CRM-03), calendar and contacts (ACT-08, ACT-09, CRM-04: Google, Microsoft), push and desktop (ACT-04) and email (ACT-04, PIP-05) have no provider in the platform. R9 requires asking before adding a dependency. Affects PIP-04, PIP-05, ACT-04, ACT-08, ACT-09, CRM-03, CRM-04.
17. **Roles are only owner and admin.** `app.admins.role` allows only owner and admin (l.20). The spec refers to managers, visibility groups, settings, bulk-edit and export permissions, and per-user read-only fields (SEC module). Until SEC is specified for the platform, the visibility and permission sentences in PIP-01, PIP-02, PIP-10, ACT-03, CRM-05, CRM-06, CRM-10, CRM-12 and CUS-03 cannot be met. Affects those IDs.
18. **Who are the "users" of the CRM?** PIP-09 (follow "another user"), ACT-04 and ACT-07 (per-user preferences) and CUS-05 (per user) assume user profiles. The platform has only `app.admins` (email, role, active) and no profile or preferences table. Confirm that CRM users equal platform admins. Affects PIP-09, PIP-15, ACT-04, ACT-07, CRM-07 (tax mode per user), CUS-05.

### Counts per status

Features (49): Implemented 0 · Partial 1 (CRM-01) · Missing 47 · Conflict 1 (CUS-05) · Unknown 0.
Settings (15): Implemented 0 · Partial 1 (`firewall`) · Missing 14 · Conflict 0 · Unknown 0.
Questions: 18.

## Part 2 — Features: LEA, COM, AUT, INS, PRO

Phase A, A3.5 rows for INSTRUCTIONS.md lines 704–1017 (49 feature IDs). Judged against the repository
`/home/user/owntheagenda_admin` only (HEAD `8c01aec`). Settings keys come from the table "Settings managed in
CUS-07" (INSTRUCTIONS.md l.684–702). Design screen comes from grepping `design-reference/sentral/project/*.dc.html`;
every ID's `r` (route) in `coverage-data.js` agrees with it, and that file's description, rules and acceptance text
is word for word the same as INSTRUCTIONS.md for all 49 IDs (checked by script). Prior art means Orgpuls git
commit `ced4af2`, the parent of migration 0206. Prior art is never counted as Implemented or Partial.

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

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen | Prior art (Orgpuls ≤0206) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LEA-01 Leads inbox | Missing | E0. The only customer object is `app.accounts` (0001 l.58–64: name, org_number). People exist only as `app.members`, a product's own users (l.98–109). | All of it: a separate lead object linked to a person or organization; a list with title, person/org, value, labels, owner, source and next activity; sortable columns, filters and an archive toggle; custom fields shared with deals; never shown in a pipeline before conversion. | — (Plan gates and usage limits only if leads become a module switch, CUS-07) | CRM-01, CRM-15, CUS-01, PIP-01, ACT-01, LEA-02 | — | Contacts.dc.html (Leads tab, lead archive toggle, columns Lead/Value/Labels/Source) | Leads were not a separate object. `crm_companies` acted as prospects with a stage (0056, 0093), and `/admin/crm/inbox` listed inbound leads with a first-response clock (0112). |
| LEA-02 Lead labels | Missing | E0 | All of it: colour-coded labels (several per lead), bulk edit, label sets editable with the settings permission, and a label filter. | — | LEA-01, SEC (settings permission), PIP-06 (shared label model?) | — | Contacts.dc.html (lead labels, leadLabelFilter) | `tags text[]` on `crm_contacts` (0055 l.81) and `crm_companies` (0056 l.58). Free tags with no colour or label set. |
| LEA-03 Convert lead and deal | Missing | E0 | All of it: lead → deal in a chosen pipeline and stage; deal → lead; notes, activities, emails and files follow in both directions; the converted deal shows the full history. | — | LEA-01, PIP-02, PIP-03, ACT-01, CRM-05, CRM-06, COM-02 | — | Contacts.dc.html ("Convert to deal" dialog); Deals.dc.html ("Convert back to lead · history kept") | None found (Orgpuls never had a separate lead object) |
| LEA-04 Lead creation and import | Missing | E0. Orgpuls' `contact.submitted` and `demo.requested` events can arrive in `app.events_in`, but `ingest_events` keeps unknown kinds unprojected (0001 l.261–262). No lead is created from them. | All of it: lead creation manually, by import, the API, web forms, chatbot, live chat, prospect search and web visitors, each setting the source field. | Web visitor identification and Form tracking fields apply through the channels (WEB, LGN); Contact rule (if the lead's person is created as a contact) | CRM-09, CRM-15, INT-03, LGN-01..05, WEB-01..04, PRO (prospect search), LEA-01 | — | Contacts.dc.html (Leads, import column "Lead · source"); Automation.dc.html ("Lead added · source = chatbot"); Inbox.dc.html ("Create lead") | `/admin/crm/inbox` (0112) built inbound leads from trial sign-ups, the contact form and demo requests. The contact form went through `submit_contact` into tickets (0051). |
| LEA-05 Lead email | Missing | E0 (no mail provider, no mailbox, no email table) | All of it: send and receive email on a lead, linked after conversion, through sync or the BCC drop-box; a reply appears on the lead. | — | LEA-01, LEA-03, COM-01, COM-02 | — | Contacts.dc.html ("Email" on the lead); Inbox.dc.html (thread linked to "Lead L-503") | Campaign mail only (`crm_sends` 0055, Brevo); no personal mail on a record |
| LEA-06 Messaging inbox and social connector | Missing | E0 | All of it: a shared inbox for messaging channels, each conversation linked to a lead or contact and convertible to a lead; a LinkedIn connector listed beside it. The connector's functions are undefined in the spec. | — | COM-13, LEA-01, CRM-01, INT (connector platform) | — | Inbox.dc.html (WhatsApp channel, "LinkedIn connector" panel: "leads and contacts the same way once defined") | 0137 added "call and LinkedIn steps" to sequences (manual tasks, not a connector) |
| COM-01 BCC drop-box | Missing | E0. No inbound-mail endpoint among `supabase/functions/` (orgpuls-events, product-command, secret-intake). | All of it: a private address per user and per deal; storing and matching mail to person and open deal; registered alternative sender addresses; an unlinked list for manual linking. | — | CRM-01, PIP-03, mail provider adapter (inbound), ACT-01 | — | Inbox.dc.html ("BCC", "drop-box", "sender addresses") | None found |
| COM-02 Two-way email sync and inbox | Missing | E0. Only reusable piece: Vault holding secrets (0002 l.27–65), scoped to product secrets by the name regex in l.43 and l.62. It cannot hold mailbox tokens as written. | All of it: Gmail/M365/Exchange/IMAP connection; read, send and reply inside the CRM; automatic and manual linking to deals, leads and projects; private or shared visibility per conversation; folder, start-date and alias choice; sent mail logged as an activity; tokens encrypted. | — | CRM-01, PIP-03, LEA-01, PRJ, ACT-01, mail/calendar provider adapters, SEC (visibility) | — | Inbox.dc.html ("＋ Gmail · Microsoft 365 · Exchange · IMAP", "Connected mailboxes", "two-way sync") | None found (campaign sending only) |
| COM-03 Multiple mailboxes | Missing | E0 | All of it: several accounts in one inbox, sender chosen per email, and the sending account recorded; an account-count entitlement. | Plan gates and usage limits (the register lists only ENT-01/02; see Q4) | COM-02, ENT-01, ENT-02 | — | Inbox.dc.html (Connected mailboxes list, sender select) | `crm_senders` (0093): send-as identities on the marketing domain, not synced mailboxes |
| COM-04 Team inbox | Missing | E0 | All of it: a shared mailbox read and answered by several users; settings for viewers and repliers, default visibility, sync start and folders; a team-inbox entitlement. | Plan gates and usage limits (see Q4) | COM-02, SEC-07/SEC-09 (who can view/reply), ENT-01 | — | Inbox.dc.html ("Team inbox · salg@"); Settings.dc.html | None found |
| COM-05 Templates, signatures and merge fields | Missing | E0 | All of it: private and shared templates and starter templates; merge fields for deal, person, organization and user; personalized hyperlinks; a signature per account; a missing merge value flagged before sending. | — | COM-02, CRM-01, PIP-03, CMP-02 (shared template store) | — | Inbox.dc.html (Template select, "Merge field", signature «Tor · Orgpuls») | `crm_templates` (0056) and the template library with "no placeholder left behind" (0113); `crm_senders.signature` (0093); `mail_templates` (0144) |
| COM-06 Open and click tracking | Missing | E0 | All of it: open and click tracking with real-time notice to the sender; per-email switch-off; reports caveat prefetch opens; on by default, switchable in settings. | Email open and click tracking (default On) | COM-02, CUS-07, mail provider adapter, notifications | — | Inbox.dc.html ("Track opens and clicks", "Open and click tracking: on (setting)") | `crm_sends.opened_at` / `clicked_at` (0055 l.155–156, l.485–486). Apple proxy opens were excluded (0053, 0111). |
| COM-07 Group emailing | Missing | E0 | All of it: one email sent individually to many recipients from list views or the timeline with a template; each copy linked to the record; needs sync and the bulk-edit permission; optional consent and suppression check. | Consent and suppression checks on sales email (Off); Count limits: recipients per group email (Unlimited) | COM-02, COM-05, CRM-02, PIP-10, SEC (bulk-edit permission), CMP-04/CMP-08 (suppression model) | — | Inbox.dc.html ("recipients · template … · merge field", group source "Segment") | Campaign sends to lists/segments (0055, 0056) with a suppression list (`crm_suppression` 0055); not personal group mail |
| COM-08 Email scheduling and outbox | Missing | E0 (no scheduler or cron) | All of it: scheduled send; edit or cancel until sent; failed sends show the provider's reason and can be retried. | — | COM-02, a job runner, mail provider adapter | — | Inbox.dc.html (outbox "Scheduled", "failed", "Retry") | Campaign scheduling and provider events (0053 `mail_events`, 0055) |
| COM-09 Labels, archiving and warnings | Missing | E0 | All of it: email labels; two-way archive state with Gmail; thread status; missing-attachment warning. | — | COM-02 | — | Inbox.dc.html (label options, Archive, status "Waiting on you"/"Replied", "Missing attachment?") | None found |
| COM-10 Meeting scheduler | Missing | E0. Middleware lets only `/login` and `/ingen-tilgang` through without aal2 (middleware.ts l.10–14), so no page reachable by a contact exists (see Q7). | All of it: a booking page from availability; general and proposed-times links; confirmation to both; linked activity; configurable duration, hours, time zone and questions; booked slots vanish at once; links usable in signatures, templates and automated email. | — | ACT-01, ACT-09, COM-05, COM-11, a public booking route | — | Activities.dc.html ("Meeting scheduler" tab, "Confirm booking", "Recent bookings") | None found |
| COM-11 Video call links | Missing | E0 | All of it: a video link created automatically for a scheduled meeting via Zoom, Teams or Meet adapters. | — | COM-10, ACT-01, video provider adapters | — | Activities.dc.html (videoOpts "Google Meet", "Teams", "Zoom") | None found |
| COM-12 Calling | Missing | E0 | All of it: click-to-call through a telephony adapter with a default provider; calls logged as activities with outcome, duration and recording link; web-to-phone handoff; incoming caller matching. | — | ACT-01, CRM-01, MOB-01, telephony adapter | — | Inbox.dc.html ("Calls" channel, call button) | Call activities logged by hand (0056 activity log; 0137 call steps) |
| COM-13 Messaging | Missing | E0 | All of it: WhatsApp Business conversations linked to deals and contacts with approved templates, quick replies, labels, delivery/read status, reactions, media, attachments and owner notification. | — | LEA-06, CRM-01, PIP-03, messaging provider adapter, notifications | — | Inbox.dc.html ("WhatsApp" channel, chats list) | None found |
| COM-14 Mail client add-ons | Missing | E0 | All of it: a Gmail side panel and a browser extension to view and add contacts, deals, notes and activities. | — | CRM-01, PIP-03, ACT-01, CRM-06, INT-03 (API) | — | Inbox.dc.html ("Gmail side panel and browser extension") | None found |
| AUT-01 Workflow builder | Missing | E0. The "lifecycle-messaging engine" that AUT says already exists (INSTRUCTIONS.md l.834) is not in this repository (see Q1). | All of it: a canvas with trigger, conditions and steps; name, description, owner, draft/active; copy-paste of steps; active-workflow entitlement; runs on the next matching event. | Plan gates and usage limits (see Q4) | AUT-02..07, a job runner, ENT-01 | — | Automation.dc.html (Workflows, Builder tabs) | Lifecycle mail (0060), auto follow-ups (0111/0115) and journeys (0120, a read-only view over campaigns, "adds no engine"). No general builder. |
| AUT-02 Event triggers | Missing | E0. `app.events_in` (0001 l.122–133) is a table of product events in, unique on (product, source_id) with `product` referencing `app.products`. Under CLAUDE.md rule 4 events enter only through a product's events function (see Q2). No CRM entity events exist. | All of it: workflow start on add, update or delete of deal, person, activity, lead, organization or project (18 pairs); field-change filter on update; workflow-made changes chain within loop limits. | Technical safeguards: workflow loop protection (Source values) | AUT-01, AUT-09, PIP, CRM-01, ACT-01, LEA-01, PRJ, events model | — | Automation.dc.html (triggers "Deal update", "Organization update", "Lead added") | `product_events` (0049), `event_catalogue` / `growth_events` (0141), Brønnøysund triggers (`brreg_triggers` 0143) |
| AUT-03 Date triggers | Missing | E0 (no cron or scheduled job) | All of it: start on, before or after a date field of a deal, person, activity or organization, evaluated on a schedule at run time; a 30-days-before-renewal case. | — | AUT-01, CUS-01 (date fields), a scheduler | — | Automation.dc.html ("before" date option) | Time-based lifecycle mails (trial_ending etc., 0060) |
| AUT-04 Conditions | Missing | E0 | All of it: AND/OR filters on the trigger and related records; email opened/answered conditions; re-check where a step says so; suggested and custom conditions; a failing record starts no run. | — | AUT-01, COM-06, PIP-12 (filter model) | — | Automation.dc.html ("Condition" node) | follow_when no_reply/no_click/no_open (0111) |
| AUT-05 Delay and wait-for | Missing | E0 | All of it: a duration or until-date delay with weekend skip; wait-for until a condition holds; up to 10 delays and 90 days per path; wait-for gives up after 7 days with a stated reason. | Count limits: delays per workflow path (Unlimited). The 90-day and 7-day caps are not in the register (see Q5). | AUT-01, AUT-04, a scheduler | — | Automation.dc.html ("Delay", "Wait" nodes) | Weekday 08–16 Oslo sending window and follow_days (0111) |
| AUT-06 If/else branches | Missing | E0 | All of it: condition split into paths, one path per branch per run; branch-count entitlement. | Plan gates and usage limits (see Q4) | AUT-01, AUT-04 | — | Automation.dc.html ("branch") | None found |
| AUT-07 Actions | Missing | E0. The platform's only outbound call is `product-command` to Orgpuls (supabase/functions/product-command/index.ts). | All of it: create, update or delete person, org, lead, deal, activity; email from template with preview, sent from the sender's synced mailbox; add note; campaign and project actions; webhook POST/PUT/DELETE with key-value or raw JSON; Slack/Teams post; Asana/Trello task; ≤10 actions per path; field values from the trigger; errors in run history. | Consent and suppression checks on sales email (Off); Count limits: actions per workflow path (Unlimited) | AUT-01, AUT-09, COM-02, COM-05, CMP, PRJ, INT-04, Slack/Teams/Asana/Trello adapters | — | Automation.dc.html (actions list ends 'Campaign action', 'Project action', 'Webhook', 'Slack', 'Teams'; no Asana or Trello found) | None found |
| AUT-08 Workflow templates | Missing | E0 | All of it: a purpose-grouped template library; short setup that saves an editable draft; the starting set is a product decision. | — | AUT-01 | — | Automation.dc.html (Templates tab, e.g. 'Churn prevention', 'Pipeline hygiene', 'Delivery handover') | None found |
| AUT-09 Monitoring and limits | Missing | E0. `app.audit` records product commands with ok/error (0001 l.136–145), not workflow runs. No job monitor exists. | All of it: per-run history with step results; overview of most failed, most active and never-run workflows; health trend for today, 7 and 14 days; owner alert on failure; rolling 10-minute loop caps (10,000 per company, 5,000 per workflow); webhook step history with final body and path; failing step linked. | Technical safeguards: workflow loop protection, webhook retry and ban policy (Source values) | AUT-01, AUT-07, INT-04, notifications, job monitor (admin spec) | — | Automation.dc.html (Monitoring tab, "health", "Failed", "Loop protection · On · Source values") | Admin ops/health pages (`/admin/ops`, `/admin/health`) existed. No workflow monitor. |
| AUT-10 Ownership and sharing | Missing | E0. Roles are only owner/admin (0001 l.20). No users-as-sales-reps, no teams, no permission sets. | All of it: workflow runs with the owner's permissions; share, activate for users or a team, transfer; global admins edit any; a create permission held only by admins by default; transfer prompt on user deactivation; owned-by filters; notice to both on transfer. | — | AUT-01, SEC-07, SEC-09, notifications | — | Automation.dc.html (Owner column, Transfer) | None found |
| AUT-11 Automatic assignment | Missing | E0 | All of it: rules on lead added and deal added/updated (pipeline/stage change); assignee user, team round-robin, org owner or person owner; priority order with first match; conditions on deal, lead, person and org fields; evaluation history. | — | LEA-01, PIP-03, CRM-01, SEC-09 (teams) | — | Automation.dc.html (Assignment rules tab: 'Sales team · round-robin', organization's owner) | Brønnøysund tasks "queued, not assigned" until an admin switches it (0143 l.38, l.105). No assignment rules. |
| AUT-12 Sequences | Missing | E0 | All of it: a drag-and-drop linear flow of email steps (auto or manual) and activity steps, with weekend-skipping delays; enrol one, bulk or by workflow; end on reply, stage change or manually; skip or stop; automatic signature; sequence entitlement; per-record step and status. | Consent and suppression checks on sales email (Off); Plan gates and usage limits (see Q4) | AUT-01, COM-02, COM-05, ACT-01, LEA-01, PIP-03 | — | Automation.dc.html (Sequences tab); Feed.dc.html (sequence emails waiting) | Auto follow-ups with reply/unsubscribe/bounce/stage exits (0111, 0115), journeys (0120), call and LinkedIn steps (0137) |
| INS-01 Report builder and types | Missing | E0. No SQL view exists in 0001 or 0002, so the "admin's SQL views" (INSTRUCTIONS.md l.915, l.340) are absent (see Q3). `platform_status` returns counts only (0001 l.302–325). | All of it: 17 report types; measure, view-by, segment-by, filters (incl. does-not-contain), period; measures incl. weighted value, conversion rate, time to win, sales velocity; visibility-scoped; one definition per metric; figures match list views. | — | PIP, ACT, LEA, CRM-01, CMP, PRJ, PIP-11, SEC (visibility), metric views | — | Insights.dc.html (Report builder tab) | `kpi_daily` and admin_kpis definitions (0062), `admin_crm_pipeline_summary` and win rate (0137), `/admin/growth/funnel` |
| INS-02 Charts | Missing | E0 (no chart library in package.json l.17–26) | All of it: column, bar, pie, scorecard (with change against the previous period) and table (configurable, sortable columns); editable colours; pie has no view-by; switching type keeps data and filters. | — | INS-01 | — | Insights.dc.html (isColumn, Bar, Pie, scorecard) | None found |
| INS-03 Dashboards | Missing | E0 | All of it: a grid with move and resize; a default dashboard, custom dashboards and role templates; duplicating reports, goals and dashboards; copying a shared report; dashboard-wide period/user filters; custom-dashboard entitlement; reopens as arranged. | Plan gates and usage limits (see Q4) | INS-01, INS-02, INS-05, SEC-07 (roles) | — | Insights.dc.html (Dashboards tab, Duplicate) | Admin overview dashboard (fixed KPIs, 0062) |
| INS-04 Sharing and collaboration | Missing | E0. Every page except `/login` and `/ingen-tilgang` requires a session with aal2 (middleware.ts l.10–46). CLAUDE.md rule 2 allows a new public path only "with a reason written beside it" (see Q7). | All of it: viewer/editor sharing; a public live link for people without an account, revocable at once, showing the owner's data scope. | — | INS-01, INS-03, SEC (users), a public route | — | Insights.dc.html (Share, "Public live" link) | None found |
| INS-05 Goals | Missing | E0. No users-as-reps or teams (0001 l.18–23). | All of it: goals on deals (added, progressed, won), activities (added, completed) and forecast (weighted revenue); assignee user, team or company; pipeline, frequency, duration, count or value target; team goals need teams; stage goals in the pipeline view; progress equals matching records. | — | PIP-02, ACT-01, PIP-11, SEC-09, INS-03 | — | Insights.dc.html (Goals tab) | None found |
| INS-06 Forecast reports | Missing | E0. `app.subscriptions` holds plan, interval and dates but no amount (0001 l.80–95), so a product revenue forecast cannot be computed from it. | All of it: deal revenue forecast from value and expected close date, optionally weighted by stage probability; product revenue forecast from recurring products and installments; totals reconcile with PIP-11. | — | PIP-03, PIP-11, CRM-07, CRM-08, billing mirror | — | Insights.dc.html (Forecast tab, "Product revenue", "installments on won deals · MRR by month") | MRR in `kpi_daily` (0062); deal value (0119) |
| INS-07 Custom-field reporting | Missing | E0 (no custom fields, CUS-01) | All of it: custom fields as dimensions, filters and measures (averages of numeric/monetary); several conditions per field; new fields reportable without configuration; an entitlement in the source. | Plan gates and usage limits (see Q4, Q9) | CUS-01, INS-01 | — | Insights.dc.html ("Custom field") | None found |
| INS-08 Export | Missing | E0 (no export library) | All of it: chart export as PNG or PDF; data as CSV or XLSX; drill-down from a chart segment to its rows with export; follows the export permission; exported rows equal the chart's rows. | — | INS-01, INS-02, CRM-10, SEC (export permission) | — | Insights.dc.html (PNG, XLSX export) | `/admin/audit/export`, `/admin/growth/export`, `/admin/crm/consent/export` (CSV, not reports) |
| INS-09 AI report generation | Missing | E0 (no language-model adapter) | All of it: a typed request produces an editable report definition; ready-made prompts; refinement in chat; custom fields named in the request; the model returns a definition, never numbers. | Anonymity firewall (Fixed: AI context reaches CRM data only, R6) | INS-01, INS-07, AIA, language-model adapter | — | Insights.dc.html ("Ask for a report" tab) | None found |
| INS-10 Capacity and freshness | Missing | E0. `app.usage_daily` (0001 l.111–118) is an event-fed daily table for product usage, not a report rollup. | All of it: live data in reports; a reports-per-user entitlement; rollup tables refreshed by events; a deal change shows without manual refresh. | Plan gates and usage limits (see Q4) | INS-01, events model, ENT-01 | — | Insights.dc.html ("Live data · same visibility rules · reports per user: unlimited") | `kpi_daily` captured nightly (0062) |
| PRO-01 Feed | Missing | E0 | All of it: three tabs of next-best steps on open deals (follow-ups: replies, no reply after 5 days, today's activities, opens, clicks, waiting sequence emails; overlooked: no follow-up, overdue; opportunities: new deals with no activity); scope set once; cards generated from events, appearing and leaving with their condition. | — | PIP-03, ACT-01, COM-02, COM-06, AUT-12, events model | — | Feed.dc.html (Feed tab: Follow-ups, Overlooked, Opportunities) | `/admin/crm/tasks` with task SLA (0143), follow-up due dates (0093, 0115) |
| PRO-02 Feed actions | Missing | E0 | All of it: quick actions (schedule task, send email, open deal); side panel with deal, activities and contacts; done-today counter; filters by stage, card type and score; completing removes the card. | — | PRO-01, PRO-03, ACT-01, COM-02, PIP-04 | — | Feed.dc.html ("done today", side panel) | None found |
| PRO-03 Scoring models | Missing | E0. No health score exists in this repository. `app.usage_daily` and `app.events_in` hold product signals (0001 l.111–133) but nothing computes a score (see Q6). | All of it: a 0–100 deal score from +25/+10/−10 criteria with AND/OR; matched-criteria preview; one pipeline per model, one active model per pipeline; model-count entitlement; health score and product events as criteria; score updates on field change. | Count limits: score models (Unlimited); Plan gates and usage limits | PIP-02, PIP-03, CUS-01, health score (admin spec), events model | — | Feed.dc.html (Scoring models tab, "+25", "+10", "−10", Health); Settings.dc.html ('Scoring models', 3) | Fit × intent lead scoring (0143, `/admin/crm/scoring`); account health 0–100 `admin_account_health` (0060 l.23, l.194) |
| PRO-04 Company enrichment | Missing | E0. `app.accounts` has only name and org_number (0001 l.58–64). No register sync or data-provider adapter exists, so the "existing register sync" (INSTRUCTIONS.md l.350) is absent (see Q6). | All of it: fill empty address, industry, employees, revenue, LinkedIn and website; never overwrite; hideable default fields; data provider or public register via adapter; credits; source logged. | Plan gates and usage limits (credit allowance; see Q8) | CRM-01, CUS-01, PRO-06, data-provider/register adapter | — | Feed.dc.html (Enrichment tab: "Brønnøysund", "register", "provider (adapter)", "Apply … fields · 1 credit") | `brreg_entities` and related tables (0143, 0145), NACE label (0056 l.44), general manager from the roles API (0110) |
| PRO-05 Person enrichment | Missing | E0 | All of it: find email and phone from name, organization and LinkedIn; stored with source and date; new contact data follows the contact-rule setting; credits. | Contact rule (No rule); Plan gates and usage limits (credits; see Q8) | CRM-01, PRO-06, data-provider adapter | — | Feed.dc.html (Enrichment tab) | None found (0110 deliberately kept only the manager's name) |
| PRO-06 Bulk enrichment and credits | Missing | E0. `app.subscriptions` (0001 l.80–95) mirrors Orgpuls customers' billing, not this platform's own credit cycle. | All of it: up to 100 records at once from a list view; monthly allowance reset per billing cycle; top-ups; refusal before any provider call when credits are short; credits used equal records enriched. | Plan gates and usage limits (credits); the 100-record cap is not in the register (see Q5, Q8) | PRO-04, PRO-05, PIP-10 (list views), ENT-01, ENT-02 | — | Feed.dc.html ("Credits this cycle"); Settings.dc.html (Plans and usage: 'Enrichment credit…') | None found |
| PRO-07 Reverse lookup | Missing | E0 | All of it: for mail from an unknown sender, propose a new person and organization with enriched fields; accepting creates linked records; uses PRO-04/05 limits. | Contact rule (No rule); Plan gates and usage limits (credits) | COM-01, COM-02, PRO-04, PRO-05, CRM-01 | — | Feed.dc.html ("Reverse lookup · email from an unknown sender") | None found |

### Questions and conflicts

1. **The lifecycle-messaging engine that AUT extends does not exist here** (AUT-01..12, also CMP-07). Part C
   l.834 says "All three extend the admin's lifecycle-messaging engine, which already runs event-triggered
   sequences; no second engine is built". Part B (l.332) says the same. This repository has no engine, job
   runner, cron or mail provider (E0). Orgpuls had one (0060 lifecycle mail, 0111 auto follow-ups, 0120
   journeys), and 0206 deleted it. Should Phase B port that engine from Orgpuls `ced4af2` and extend it, or
   build the workflow engine fresh as the single engine? Where do jobs run (Supabase cron, an edge function,
   Vercel cron)? Each is a new dependency under R9.
2. **Where CRM events go** (AUT-02, AUT-09, PRO-01, PRO-03, INS-10). Part B (l.334) says to register CRM
   events in "one typed events table". The nearest table is `app.events_in` (0001 l.122–133). It requires
   `product` to reference `app.products`, a product-supplied `source_id`, and uniqueness on (product,
   source_id). Platform CLAUDE.md rule 4 says "Events come in only through the product's events function".
   Writing CRM entity events into it would break that rule. Should a separate CRM events table be added, or
   should rule 4 be amended?
3. **Metrics "defined once as SQL views kept in git" do not exist** (INS-01, INS-06, INS-10). Part B l.340 and
   INS-01 (l.915) say reports reuse the admin's views. 0001 and 0002 define no view. Orgpuls had `admin_kpis` and
   `kpi_daily` (0062). Which business metrics (MRR, paying, trials, churn) does Phase B define, and from what?
   `app.subscriptions` holds no price or amount (0001 l.80–95).
4. **Entitlements are not all in the register** (COM-03, COM-04, AUT-01, AUT-06, AUT-12, INS-03, INS-07,
   INS-10, PRO-03). These features call a count "an entitlement". The register row "Plan gates and usage
   limits" lists only ENT-01, ENT-02 under "Applies to" (l.696). Confirm that every "is an entitlement"
   sentence falls under that row with the default "All on and unlimited". The rows above assume this.
5. **Hard caps outside the register** (AUT-05, PRO-06, AUT-09, against R5). R5 says every limit is a setting
   defaulting to unrestricted. Three caps are not in the register: AUT-05's "90 days in total per path" and
   "wait-for gives up after 7 days", and PRO-06's "up to 100 people or organizations". Should they be added as
   count limits (default Unlimited), or kept fixed? Separately, the "Technical safeguards" row defaults to
   "Source values" (loop caps 10,000/5,000), which restricts by default. Confirm that this exception to R5 is
   intended. The design shows "Loop protection · On · Source values" (Automation.dc.html).
6. **The health score and register sync that PRO builds on do not exist** (PRO-03, PRO-04). Part B l.335 and
   l.350 say PRO-03 uses the "health score per organization" and PRO-04 "uses the existing register sync". The
   platform has neither: no score, no Brønnøysund adapter, and `app.accounts` has only name and org_number.
   Orgpuls had both (0060 `admin_account_health`, 0143 `brreg_*`). Should they be ported? Is the health score
   to be computed from `app.usage_daily` and `app.members`, which is what Orgpuls now sends?
7. **Public pages against an MFA-only admin** (INS-04, COM-10; also LEA-04 web forms, chatbot and live chat if
   hosted here). INS-04 needs a "public live link for people without an account". COM-10 needs a booking page
   a contact opens. `middleware.ts` l.10–46 sends every other path to sign-in and aal2. Platform CLAUDE.md
   rule 2 allows a public path only "with a reason written beside it", and R7 forbids weakening MFA. Approve
   these public routes, which domain they live on, and what data a public report link may expose (the spec
   says the owner's data scope).
8. **Credits and whose billing** (PRO-04..07). PRO-04/05 say "Consumes credits", but PRO-06 refuses only
   "where a credit allowance is set". The register has no credit setting. The design puts "Enrichment
   credits" under Settings › Plans and usage. Is the allowance a "Plan gates and usage limits" value
   (default unlimited, so never refused)? Whose billing cycle resets it? The platform's `app.subscriptions`
   mirrors product customers, not the platform's own plan.
9. **Ambiguous gate on custom-field reporting** (INS-07). Its rules say only "An entitlement in the source
   product". Is it gated here (under Q4) or always on?
10. **Permissions that restrict by default** (AUT-10, COM-07, LEA-02, INS-08). Four features require a
    permission. AUT-10 says "Creating workflows needs a permission that only admins have by default". COM-07
    needs "the bulk-edit permission", LEA-02 "the settings permission" and INS-08 "the export permission". The
    platform has only owner and admin (0001 l.20), both full admins. Are these permissions under R5's "no
    restriction by default", or SEC permission sets with these defaults?
11. **Design omits part of AUT-07.** AUT-07 lists "Create an Asana or Trello task". Automation.dc.html's action
    list ends with 'Campaign action', 'Project action', 'Webhook', 'Slack', 'Teams', and Asana and Trello are
    found nowhere in the design. AUT-07's "Run campaign and project actions" is also unspecified: which
    actions?
12. **The LinkedIn connector is undefined** (LEA-06). The spec says its functions "must be defined before its
    phase". The design says "leads and contacts the same way once defined" (Inbox.dc.html). What should it do?
    LinkedIn's API terms may limit it.
13. **Two-way archive covers only Gmail** (COM-09). Archiving is two-way "with Gmail". COM-02 also syncs
    Microsoft 365, Exchange and IMAP. Should archive state sync for those too?
14. **Leads from Orgpuls events** (LEA-04, ACT-01). Orgpuls sends `contact.submitted` and `demo.requested`.
    `ingest_events` stores them without projecting them (0001 l.261–262). Part B l.336 says "the contact form
    creates a ticket and a consented prospect". Should these events create leads, with what source value? Is
    "consented" a requirement, given the Contact rule defaults to No rule?
15. **Mailbox and provider tokens** (COM-02, COM-11, COM-12, COM-13, PRO-04). COM-02 says tokens are "stored
    encrypted". The platform's Vault access is limited to product secrets: `store_product_secrets` and
    `product_secret` accept only names matching `*_(token|webhook)_secret` (0002 l.43, l.62), and platform
    CLAUDE.md rule 5 reserves Vault for product shared secrets. Phase B needs a separate, decided
    per-user token store. Which mail, calendar, telephony, messaging, video and data providers are chosen
    (each is a new dependency under R9)?
16. **Firewall reach of product signals** (PRO-03, INS-09, AUT-02). Product events as scoring and trigger
    signals are safe as far as this repository shows: `app.events_in` receives only what Orgpuls' registry
    sends, and CLAUDE.md rule 6 excludes respondent data. A database test proving R6 for the new CRM tables
    still has to be written (A8). `supabase/tests/` is empty today.

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
l.1290, LGN-03 l.1273, Part B table l.326–351), that refers to the Orgpuls admin removed by Orgpuls
migration 0206; it does not exist in the platform (see Q1).

Settings that apply to **every** row and are not repeated per row: *Anonymity firewall* (fixed),
*Typed reason for CRM actions* (every CRM write and read of customer data), and the CUS-07 module
switch for the row's module (a switched-off module disappears from navigation and its API returns a
disabled error, l.674–676).

Design screens are named from `design-reference/sentral/project/*.dc.html` by grepping each feature's
concepts; `coverage-data.js` (which carries a route key `r` per feature ID) was used to confirm the
screen. Prior art = Orgpuls commit `ced4af2` (parent of 0206).

### Table

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen | Prior art (Orgpuls ≤0206) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AIA-01 Assistant chat | Missing | No AI gateway, model provider, chat route or history table in repo. `app.audit` (0001:136–146) cannot record a CRM read (product/command-shaped). | All of it: chat on every screen (text and voice), answers on account data, summaries, drafts, explanations, history; retrieval under the asking user's permissions; cited records; survey data out of reach; audited reads; never returns data the user cannot open. | Anonymity firewall; Typed reason for CRM actions | AI gateway (SF-24), SEC (per-user permissions), CRM-01, LLM provider (open point 2) | — | Sentral Admin.dc.html (global "Assistant" panel, "Reads CRM data you may see"); coverage-data.js r=assistant | none found |
| AIA-02 AI notifications | Missing | Nothing in repo (no deals, activities, forecast, AI). | All of it: deal-advance estimate cards with reason, stalled/slipping flags, one-click next action; daily progress panel (tasks, calls, activities) and month panel (new, won, forecast); account-wide switch to hide AI scoring; each card links to the deal and its action works. | Not in register: "hide AI scoring" (see Q5) | PIP-03, PIP-11, ACT-01, AI gateway, job runtime | — | Feed.dc.html (Stalled, Slipping, Forecast, progress today/month) | none found |
| AIA-03 Email writer | Missing | No composer, no AI. | All of it: prompt + tone (professional, formal, friendly) + length (short, standard, long) draft in the prompt's language; inserted for editing, never sent; uses linked deal and person context. | — | COM (composer), PIP-03, CRM-01, AI gateway | — | Inbox.dc.html (tone/length selects, aiPrompt) | none found |
| AIA-04 Email summary and replies | Missing | No mail threads, no AI. | All of it: per-thread summary, sentiment, readiness-to-buy 1–10 with reason, action items, suggested replies; on demand; reflects the latest message. | — | COM-01/02 (threads), AI gateway | — | Inbox.dc.html (summary, score /10, sentiment, Readiness, Action items, Suggested replies) | none found |
| AIA-05 Import mapping | Missing | No import, no field definitions. | All of it: suggested column→field mapping incl. option fields; user confirms; mappings editable and logged. | — | CRM-09, CUS-01, AI gateway | — | Contacts.dc.html (import, mapping, Suggested) | none found (Orgpuls had CSV import of contacts, but no AI mapping) |
| AIA-06 Integration recommendations | Missing | No integration catalog; Platform screen not built. | All of it: suggestions from the catalog, natural-language search over it, drawing on tools in use and what similar companies use; search returns matching entries. | — | INT-11, AI gateway | — | Platform.dc.html (catalog, Recommend) | none found |
| AIA-07 Card scanner | Missing | No mobile app, no storage bucket, no contacts table. | All of it: mobile photo of a business card → contact draft with several phones/emails; user reviews before save; image stored on contact; follows contact rule; correct editable draft. | Contact rule | MOB-01, MOB-06, CRM-01, CRM-05, OCR/AI provider, storage | — | Mobile.dc.html ("Capture … AIA-07 … card scanner", "Business card", "Contact draft saved") | none found |
| MTG-01 Pre-call brief | Missing | No meetings, calendar, mail or AI. | All of it: brief from deal history, past emails, earlier conversations, contact and organization data; changed-since checklist; user free-form instructions; unlinked meetings flagged; exists before start and cites sources. | — | ACT-01, ACT-09, COM-01/02, MTG-08 mailbox, AI gateway, job runtime | — | Meetings.dc.html (brief, "Since the last contact", "Who you meet") | none found |
| MTG-02 Notetaker bot | Missing | No calendar integration, no bot provider. | All of it: bot joins Meet/Zoom/Teams from calendar as visible participant ~2 min before start, records; owner can remove it; consent notice emails to attendees (24 h default); joins meetings with a link, leaves when removed. | Recording consent notices to attendees | ACT-09, INT-05/06, meeting-bot provider (open point 2), job runtime (open point 3), open point 5 | — | Meetings.dc.html (notetaker, "Bot joins", "Notice due tomorrow"); Settings.dc.html (notetaker) | none found |
| MTG-03 Desktop capture | Missing | Repo is a Next.js web app only; no desktop client. | All of it: macOS/Windows desktop app recording system audio without a bot (VoIP, phone, in person); user controls participant notices; recording appears in the same workspace. | Recording consent notices (applicability unclear, Q5) | MTG-08, transcription provider, desktop client toolchain (Q10) | — | Meetings.dc.html ("Desktop capture") | none found |
| MTG-04 Transcript and recap | Missing | No transcription, notes or Slack integration. | All of it: timestamped speaker transcript; recap with takeaways and next steps saved as a note on the linked deal/person/org; action item jumps to the moment; Slack message when ready; attached to the right record. | — | MTG-02/03/06, CRM-06, INT-07 (Slack), transcription provider, AI gateway | — | Meetings.dc.html (transcript, Recap) | none found |
| MTG-05 CRM update suggestions | Missing | No CRM records, no custom fields, no approval flow. | All of it: proposed field/label/new-contact changes beside current values; nothing written until approved (item or all); new contact follows contact rule; approved items written and logged with the meeting as source. | Contact rule | MTG-04, CUS-01, CRM-01, CRM-14, PIP-04 (changelog with source), AI gateway | — | Meetings.dc.html ("6 suggestions", Accept) | none found |
| MTG-06 Transcript upload | Missing | No upload handling, no storage. | All of it: upload an externally recorded transcript and get the same recap and suggestions. | — | MTG-04, MTG-05, storage | — | Meetings.dc.html ("Upload transcript") | none found |
| MTG-07 Unscheduled calls | Missing | No desktop client. | All of it: ad hoc recording without a calendar event from the desktop app, no maximum duration, linkable to a deal afterwards. | Recording consent notices (applicability unclear, Q5) | MTG-03, PIP-03 | — | Meetings.dc.html ("Unscheduled calls", "Start recording") | none found |
| MTG-08 Workspace and controls | Missing | No per-user permission model: `app.admins.role` is `owner\|admin` only (0001:20). No mailbox connection. | All of it: workspace with upcoming, post-meeting actions and history; on by default per user, admins switch off per user; one permission for all features; own mailbox connection for briefs; user without permission sees no workspace. | Recording consent notices to attendees; not in register: per-user on/off (Q5) | SEC-07 (roles/permissions, open point 10), INT-05/06, open point 5 | — | Meetings.dc.html (Upcoming, History); Settings.dc.html | none found |
| MCP-01 MCP server | Missing | No OAuth server, no MCP endpoint, no API, no sync index, no job runtime. | All of it: MCP endpoint with OAuth login; 30-minute sync index over deals, leads, contacts, pipelines, activities, email, products, users, custom fields, automations, reports; every call as the connected user, counts against API limits; CRM data only; assistant can only see/change what the user can. | API rate limits; Anonymity firewall | INT-01..03, SEC, job runtime, all CRM entities | — | Platform.dc.html ("AI connector (MCP)", "https://sentral.orgpuls.no/mcp · OAuth login"); Security.dc.html (audit row "Claude (MCP)") | none found |
| MCP-02 Tool catalog | Missing | No API definitions to generate from. | All of it: get/list/add/update/search tools for activities, deals, people, orgs, leads, products, stages, notes, plus lead→deal; names and schemas generated from API definitions; every tool has a schema and structured results. | — | MCP-01, INT-01/02, LEA-03 | — | Platform.dc.html (MCP block) | none found |
| MCP-03 Admin controls | Missing | No settings registry. | All of it: company-level MCP switch; off blocks new connections and removes existing; does not affect API tokens or other integrations; after switch-off no assistant call succeeds. | Not in register (Q5) | MCP-01, CUS-07 | — | Platform.dc.html (toggleMcp switch) | none found |
| CMP-01 Email builder | Missing | No templates, mail, or editor. | All of it: drag-and-drop rows and blocks (title, paragraph, list, image, button, divider, social, HTML, video, icons, menu); row border/background/padding; blank or layout start; desktop and mobile preview; non-removable footer with postal address and unsubscribe; preview equals delivery. | Not in register: fixed footer (Q6) | CMP-02, storage (images), sending provider | — | Marketing.dc.html (builder, Block, footer, html) | app.crm_campaigns (0055_crm.sql), app.mail_templates (0144); routes app/(admin)/admin/crm/campaigns, /cms/templates |
| CMP-02 Templates | Missing | Nothing. | All of it: ready-made layouts, saved template library, code-your-own HTML; stored as data and versioned; a template starts a campaign. | — | CMP-01, COM-05 (shared template store per Part B l.345) | — | Marketing.dc.html (template) | app.crm_templates (0056_crm_pipeline.sql), app.mail_templates (0144), cms_templates/cms_revisions; route admin/crm/templates |
| CMP-03 Audience | Missing | No people/contacts table (only `app.members`, 0001:98, customer users with no consent or engagement field). | All of it: recipients by CRM filters over people incl. engagement and location; one shared contact list; only subscribed addresses receive mail; count equals subscribed matches. | Not in register: subscribed-only rule (Q6) | CRM-01, PIP-12 (segments), CMP-04 | — | Marketing.dc.html | app.crm_segments, app.crm_contacts (0055), app.crm_lists, app.crm_list_members (0056); routes admin/crm/segments, /lists |
| CMP-04 Marketing status and consent | Missing | No consent record, status or suppression list. | All of it: seven statuses (no consent, subscribed, unsubscribed, bounced, pending DOI, pending upgrade, archived); single/double opt-in; every change logged with time and source; derived from the consent record (basis, date); suppression on every campaign; unsubscribed never mailed. | Consent and suppression checks on sales email (for the sales-email part only) | CRM-01, consent record (Appendix 2), CMP-06 (bounces) | — | Marketing.dc.html (Subscribed, double opt-in, Pending, Bounced, No consent); Contacts.dc.html | crm_contacts consent fields and double opt-in (0055_crm.sql l.298–356), app.crm_suppression (0055 l.97), consent_purposes/consent_records (0141); route admin/crm/consent |
| CMP-05 Scheduling and sending | Missing | No sending provider, no marketing stream, no job runtime. | All of it: send now or at set time via a provider on a marketing stream separate from transactional; subscriber allowance is an entitlement, overflow waits as pending; scheduled campaign leaves on time. | Plan gates and usage limits (subscriber allowance via ENT-01/02) | Sending provider (open point 2), job runtime (open point 3), ENT-01/02 | — | Marketing.dc.html (Schedule, stream, Transactional) | app.crm_sends (0055), app.mail_streams (0144: marketing mail only on the marketing stream) |
| CMP-06 Campaign analytics | Missing | No provider events ingestion for mail. | All of it: delivered, bounced, unsubscribed, spam, total/unique opens and clicks, open/click/CTR, top locations; owner engagement notifications; needs tracking on; hard bounce or 5 soft bounces → bounced; figures match provider events. | Email open and click tracking (register lists COM-06 only; Q5) | CMP-05, provider webhooks, CMP-04 | — | Marketing.dc.html (open rate, click rate, Spam, Top locations) | crm_sends delivery events and reporting (0055 l.489–492, l.858), app.crm_clicks (0056) |
| CMP-07 Automated campaigns | Missing | No workflow engine. | All of it: campaign email as a workflow step with delays; audience from the workflow; obeys consent status. | — | AUT-01..07, CMP-04, open point 1 (one engine) | — | Automation.dc.html (Campaign); Marketing.dc.html | crm journeys (0120_crm_journeys.sql), brreg_triggers (0143); routes admin/crm/journeys, /triggers |
| CMP-08 Deliverability | Missing | No sender domain, DNS check or provider account. | All of it: sender domain authentication with DNS checks, account verification before first send, compliance recommendations, list hygiene warnings; unauthenticated domain cannot send. | Not in register: send block on unauthenticated domain (Q6) | Sending provider, CMP-05 | — | Marketing.dc.html (DKIM, SPF, DMARC, Verif, hygiene) | app.mail_auth_checks, app.mail_auth_runs (0144); route admin/deliverability |
| CMP-09 Campaign insights | Missing | No Insights, no campaigns. | All of it: campaign performance and conversion reports in Insights, filter by campaign type, comparison of two or more campaigns in one chart matching each campaign's report. | Plan gates and usage limits (comparison is a higher tier in source) | INS-01..10, CMP-06 | — | Marketing.dc.html (Compare); Insights.dc.html (Campaign) | app.marketing_spend (0062), A/B subject test subject_b/variant (0056 l.226–237) |
| PRJ-01 Boards and phases | Missing | Nothing. | All of it: kanban boards with phases, several boards; phases added/renamed/reordered/deleted like stages; drag changes phase and logs it. | — | PIP-02 (stage pattern), audit/changelog | — | Projects.dc.html (board, phase, drag) | none found |
| PRJ-02 Project record | Missing | Nothing. | All of it: title, board, phase, owner, dates, labels, description, custom fields, links to deals, one person, one org; create from won deal with AI-drafted brief reviewed by the user; shows the deal and contacts. | — | PIP-03, PIP-07, CRM-01, CUS-01, AI gateway | — | Projects.dc.html ("Won deal", brief) | none found |
| PRJ-03 Work items | Missing | Nothing. | All of it: tasks (optional owner, start/due, several assignees), subtasks with mandatory parent, milestones, activities (date, time, owner, calendar sync); parent not auto-completed unless set. | — | ACT-01, ACT-09 | — | Projects.dc.html (task, milestone); subtasks not found in screens (coverage-data.js only) | none found |
| PRJ-04 Dependencies and timeline | Missing | Nothing. | All of it: dependencies between tasks/milestones without cycles; Gantt by month with dependency lines; drag a phase/group to shift it keeping spacing; overdue highlighted. | — | PRJ-03 | — | Projects.dc.html (gantt, Depend, shift, Timeline) | none found |
| PRJ-05 Project templates | Missing | Nothing. | All of it: reusable plans with relative due dates by phase/group; save a project as template; template project gets dated items from its start date. | — | PRJ-01..04 | — | Projects.dc.html (template) | none found |
| PRJ-06 Project health | Missing | Nothing. | All of it: on track / at risk / off track / on hold, manual or AI-suggested from emails, notes, tasks, activities with recommendations; AI summary enabled per account, regenerable; status on board and in reports. | Not in register: "AI summary enabled per account" (Q5) | AI gateway, INS | — | Projects.dc.html (On track, At risk, Off track, On hold) | none found |
| PRJ-07 Collaboration and sharing | Missing | No notes, files, mentions, notifications or PDF generation. | All of it: notes, files, @mentions, emails on a project; one-click AI status report PDF with only what the sender includes; mention notifies the user. | — | CRM-05, CRM-06, COM, AI gateway, storage | — | Projects.dc.html (Note, file, mention, Status report, PDF) | none found |
| PRJ-08 Bulk work and import | Missing | Nothing. | All of it: paste a list into tasks (date in a line becomes due date) in the chosen phase; bulk edit; import/export incl. from other project tools. | — | PRJ-03, CRM-09, CRM-10 | — | Projects.dc.html (Paste, Import) | none found |
| PRJ-09 Automation and reports | Missing | No workflow engine, no Insights. | All of it: projects/tasks as workflow triggers and actions; project performance and duration reports; workflow creates a project when a deal is won. | — | AUT, INS, PIP-07 | — | Projects.dc.html (Workflow, Duration, Report); Automation.dc.html ("Create project") | none found |
| LGN-01 Chatbot | Missing | No site widget, no leads. | All of it: playbook bot in three steps (theme, profile, template: leads, meetings, qualify/route, live chat); per-page questions; creates lead/deal, assigns owner, books meetings; qualified leads top of owner's inbox; per-step drop-off; completed conversation stores answers on a lead. | — (widget loading governed by LGN-05's setting) | LEA-01, AUT-11, COM-10, LGN-05 | — | Marketing.dc.html (Chatbot, playbook); Automation.dc.html; Settings.dc.html | none found |
| LGN-02 Live chat | Missing | No realtime channel, no mobile app. | All of it: rep takes over in real time (web or mobile); unassigned queue for a set time then bot fallback; online message; claimed chat locked to one rep and saved on the lead. | — | LGN-01, MOB, LEA-01 | — | Marketing.dc.html (Live chat); Mobile.dc.html; Settings.dc.html | none found |
| LGN-03 Web forms | Missing | Orgpuls' `contact.submitted` events reach `app.events_in` (0001:122) but are stored raw only (0001:262); no ticket, prospect, lead, form builder or notification follows. | All of it: form builder (input/message blocks; contact, registration, gated download, file upload, blank; mandatory intro block); fields incl. marketing status and custom fields, optionally required; embed/link/share; ID and active status; submission → lead/deal, owner emailed, owner kept on resubmission; UTM, cookies, referrer, landing page, hidden page variables; fixed language; reuse of the contact-form → ticket + consented prospect path (which does not exist here, Q1); views/interactions/submissions/conversion counted. | Form tracking fields (UTM, cookies, referrer) | LEA-01, LEA-04, CUS-01, CMP-04, tickets (Appendix 2), storage (file upload) | — | Marketing.dc.html (form, UTM, Gated, Introduction) | contact form submit_contact → app.tickets (0051_tickets.sql l.7, l.280), growth_magnets gated downloads (0144 l.62); routes admin/tickets, /cms/magnets |
| LGN-04 Prospect search | Missing | No external data provider, no credits, no leads. | All of it: person and organization filters over a licensed database, saved filters, credit-based reveal adding to leads inbox; one credit per reveal creates a lead; follows contact rule. | Contact rule; Plan gates and usage limits (credits) | Prospect data provider (open point 2), LEA-01, ENT | — | Marketing.dc.html (prospect, reveal, credit, Job title) | app.brreg_entities, app.brreg_outreach, brreg_dnc (0143_growth_crm.sql); routes admin/crm/prospects — Brønnøysund register, organizations only (Q11) |
| LGN-05 Embedding and consent | Missing | No script, no public site in this repo. | All of it: one script loading chatbot, live chat and tracking; consent wording and cookie notice on forms/widgets; consent-gated loading setting off by default; with it on and consent declined no tracking cookie; never loaded in the survey flow (fixed). | Consent-gated loading of site widgets; Anonymity firewall | LGN-01..03, WEB-01, Orgpuls public site (Q2) | — | Marketing.dc.html (script, consent, cookie, survey) | web beacon refuses survey paths /s, /bli-med, /auth, /admin (0050_web_analytics.sql header) |
| WEB-01 Tracker | Missing | No tracker, no web events table. | All of it: script on one or more sites recording visits and pages, sites told apart by hostname, never in the survey flow; visits appear under their site. | Web visitor identification; Anonymity firewall | LGN-05, Orgpuls public site (Q2) | — | Marketing.dc.html (visitor, site); Analytics.dc.html | app.web_events, web_salts, org_attribution (0050_web_analytics.sql: cookieless, no IP stored, daily salt); route admin/web |
| WEB-02 Organization identification | Missing | Nothing; no IP-to-company source. | All of it: match visits to companies, filter ISPs/crawlers/irrelevant traffic; company counted once per month for billing; hourly refresh; known company IP → named visitor. | Web visitor identification; Plan gates and usage limits (monthly company count) | WEB-01, IP-to-company provider (open point 2), job runtime | — | Marketing.dc.html (visitor list, ISP filtering) | none found (0050 deliberately never stores an IP; Q3) |
| WEB-03 Visitor inbox and ranking | Missing | Nothing. | All of it: company list with location, industry, last visit, source, pages, activity ranking; filters for period, country, campaign, page, already-in-CRM; quality sort puts most active first. | Web visitor identification | WEB-02, CRM-01 | — | Marketing.dc.html (Visitor, "in CRM") | none found |
| WEB-04 Convert and reveal | Missing | Nothing. | All of it: visitor → lead, deal or organization linked to visit history; prospect search for people at the company using credits. | Web visitor identification; Contact rule | WEB-03, LEA-03, LGN-04, CRM-01 | — | Marketing.dc.html (reveal, prospect) | none found |
| DOC-01 Templates and merge fields | Missing | No templates, products, deals, or drive connection. | All of it: document/spreadsheet/presentation templates with deal, person, org, product, project placeholders; named, categorized, company-wide; import from drive; split address fields; missing value flagged before sending; generated document contains deal data. | — | PIP-03, CRM-07, PRJ-02, DOC-03 | — | Documents.dc.html (Template, placeholders); Deals.dc.html (merge field) | none found |
| DOC-02 Product tables | Missing | No product catalog. | All of it: template table filled with the deal's products, prices, discounts, tax, totals; configurable columns; not in spreadsheet templates; totals equal deal value. | — | CRM-07, PIP-03, CUS-06 | — | Documents.dc.html (Product, Total); Deals.dc.html | none found |
| DOC-03 Cloud storage | Missing | No storage bucket, no Google/Microsoft OAuth. | All of it: create/store in Google Drive, OneDrive, SharePoint (personal or shared); company default shared location; generated PDFs always stored in platform; new document appears in drive. | — | INT-05, INT-06, platform storage | — | Documents.dc.html (Drive, OneDrive, SharePoint); Platform.dc.html | none found |
| DOC-04 Trackable links | Missing | No public link endpoint, no deal timeline. | All of it: share document/PDF through a link recording each open and notifying the owner; links can be disabled; open logged with time on the deal. | — | DOC-01/03, PIP-04, notifications | — | Documents.dc.html (Link, Open); Deals.dc.html; Feed.dc.html | none found |
| DOC-05 E-signatures | Missing | Nothing. | All of it: requests to up to 10 signers with one-time email code, custom message, invite language, drag-and-drop signer fields; sealed document with audit trail; signed PDF and trail stored on the deal; legal signature level to be confirmed. | Count limits taken from the source (signers) | DOC-01, storage, mail provider, e-signature evidence provider (open point 2), open point 5 | — | Documents.dc.html (Signer, One-time code, audit trail, Invite language, drag) | none found (Orgpuls product-side DPA click-sign 0047_dpa.sql is not an admin e-sign) |
| DOC-06 Branding and external signing | Missing | Nothing. | All of it: removable platform branding; external e-signature service through an adapter; status of an externally sent document shown on the deal. | — | DOC-05, adapter pattern (Part G l.2508) | — | Documents.dc.html (Branding, External, adapter) | none found |

### Questions and conflicts

**Q1. "Already has" refers to a deleted system.** The CMP intro (l.1140), WEB intro (l.1290), LGN-03 rules
(l.1273: "The admin's contact form already creates a ticket and a consented prospect, and forms reuse that
path") and the Part B table (l.326–351: segments, campaign editor, consent and suppression, streams,
deliverability, cookieless analytics, ticketing) describe the Orgpuls admin removed by Orgpuls 0206. In the
platform none exists; `contact.submitted` is stored raw in `app.events_in` and nothing projects it
(0001_foundation.sql l.262). Should Phase B port the prior art from Orgpuls `ced4af2` (0050, 0051, 0055,
0056, 0120, 0141, 0143, 0144) or build these modules fresh in the platform? This changes "extend, not
rebuild" into "build". Affects CMP-01..09, LGN-03, LGN-04, LGN-05, WEB-01..04.

**Q2. Where does the "never in the survey flow" rule live?** LGN-05 and WEB-01 make it a fixed rule, and R6
asks for database tests. The survey flow and the public site are in Orgpuls, not in this repository. The
script would have to be mounted on Orgpuls' public site (prior art: the 0050 beacon refused /s, /bli-med,
/auth, /admin). Is the tracker/widget script served by the platform and embedded on Orgpuls' site, and who
proves the rule (an Orgpuls test, a platform test, both)? Affects LGN-01, LGN-02, LGN-05, WEB-01.

**Q3. Company identification vs cookieless analytics.** WEB-02 needs the visitor's IP to match a company,
and WEB intro says this goes "on top of" cookieless analytics. The prior art was designed never to hold an
IP, user agent or cookie, with a daily-rotating salt (Orgpuls 0050 header). Should identification resolve
the IP at ingest and keep only the company (never the IP), or store IPs? Does Appendix 2's "cookieless"
constrain this? Also LGN-03 captures "cookie values" while LGN-05 promises "no tracking cookie" when
consent is declined: which cookies may the platform set by default? Affects WEB-01, WEB-02, LGN-03, LGN-05.

**Q4. Roles and per-user permissions do not exist.** `app.admins.role` allows only `owner|admin`
(0001_foundation.sql l.20); Appendix 2 names four roles; the plan's actors have none (open point 10).
AIA-01 ("user's permissions"), MCP-01 ("as the connected user"), MTG-08 ("one permission", "per user
switch"), LGN-02 (reps), PRJ (project managers) all need a permission model. Which roles/permission sets?
Affects AIA-01, MCP-01, MCP-02, MTG-08, LGN-01, LGN-02, PRJ-01..09.

**Q5. Settings named in features but absent from the CUS-07 register.** CUS-07 says the register manages
"every rule that can restrict a feature". Not listed: AIA-02 "hide AI scoring for the whole account";
PRJ-06 "AI summary must be enabled per account" (default on or off?); MCP-03 MCP access switch (default?);
MTG-08 per-user on/off; MTG-03/MTG-07 "user controls participant notices" (does the register's recording
consent setting apply to desktop capture?); CMP-06 "needs engagement tracking switched on" (the register's
"Email open and click tracking" lists COM-06 only); LGN-02 unassigned-queue wait time. Should each become a
register row, and with which default? Affects AIA-02, PRJ-06, MCP-03, MTG-03, MTG-07, MTG-08, CMP-06, LGN-02.

**Q6. Hard rules in CMP that R5 would make settings.** R5: "Every limit, plan gate, quota, approval step and
compliance rule is a setting … default leaves the feature fully working and unrestricted." CMP-01 (footer
cannot be removed), CMP-03 (only subscribed receive mail), CMP-04 (unsubscribed cannot be mailed by any
campaign), CMP-07 (triggered email obeys consent) and CMP-08 (unauthenticated domain cannot send) are
fixed blocks with no register row; the register's consent setting covers only sales email (COM-07, AUT-07,
AUT-12). Are these fixed rules like the anonymity firewall, or settings? Note CMP-08's block is also imposed
by the provider. Affects CMP-01, CMP-03, CMP-04, CMP-07, CMP-08.

**Q7. Source limits vs "Unlimited" defaults.** DOC-05 says "up to 10 signers"; the register's count-limit row
defaults to Unlimited for signers. CMP-05 says addresses over the subscriber allowance "wait as pending";
the register's plan gates default to "All on and unlimited". CMP-09's comparison is "a higher tier in the
source"; WEB-02 counts companies per month "for billing"; LGN-04 uses credits. Confirm the defaults are
unlimited (so 10 signers, pending overflow and credits are only applied when a setting is set), and what a
credit means when the default is unlimited but the provider bills per reveal. Affects DOC-05, CMP-05,
CMP-09, WEB-02, WEB-04, LGN-04.

**Q8. Providers and new stacks (R9, open point 2).** Needed and absent: LLM provider (AIA, MTG, PRJ-02/06/07),
transcription and meeting-bot provider (MTG-02..07), IP-to-company source (WEB-02), prospect database
(LGN-04), marketing sending provider (CMP-05/06/08), e-signature evidence (DOC-05/06), Google/Microsoft
drive OAuth (DOC-03), Slack (MTG-04), OCR for cards (AIA-07). Each needs Tor's choice before Phase B.

**Q9. Job runtime (open point 3).** No cron, queue or worker exists in the platform. Needed by MCP-01 (30-min
sync), WEB-02 (hourly refresh), CMP-05 (scheduled send), MTG-02 (join 2 min before start, notices 24 h
before), MTG-01 (brief before the meeting), AIA-02 (cards). Affects those IDs.

**Q10. Native clients outside the stack.** MTG-03/MTG-07 need a macOS and Windows desktop app; AIA-07 and
LGN-02 need the mobile app (MOB). The repository is a Next.js web app with no native toolchain. Is a
desktop client in scope, built or bought (open point 2), and in which repository? Affects MTG-03, MTG-07,
AIA-07, LGN-02.

**Q11. Prospect data source.** LGN-04 requires a licensed provider with person data; the prior art used the
Brønnøysund register (organizations, no persons; brreg_dnc for reservation). Is Brønnøysund one source,
the only source, or replaced? Affects LGN-04, WEB-04.

**Q12. "Company" and "account" in a single-company internal admin.** MCP-03 "company-level switch", PRJ-06
"enabled per account", AIA-02 "for the whole account", DOC-01 "shared company-wide", DOC-03 "per company",
AIA-06 "what similar companies use". In the platform `app.accounts` are customers (0001:58), not the admin's
own organisation. Do these mean one platform-wide setting? And AIA-06's peer-usage signal has no source in
a single-tenant admin — drop it or define it? Affects MCP-03, PRJ-06, AIA-02, AIA-06, DOC-01, DOC-03.

**Q13. Audit shape.** AIA-01 (audited reads), MTG-05 (logged with meeting as source), AIA-05 (mappings
logged), PRJ-01 (phase move logged), DOC-05 (audit trail) need audit rows for CRM entities. `app.audit` only
fits product commands (`product not null`, `command ~ '^[a-z]+\.[a-z_]+$'`, 0001:139–141). Extend it (needs
a migration; R7 forbids loosening the append-only trigger) or add a CRM changelog? Affects AIA-01, AIA-05,
MTG-05, PRJ-01, DOC-05.

**Q14. Consent source of truth for campaigns.** CMP-04 derives statuses from "the admin's consent record,
with its basis and date". The platform's only person-like rows are `app.members` (0001:98, customer users
from Orgpuls `member.joined`, no consent field). May `app.members` become marketing contacts, and where
does their consent come from? Affects CMP-03, CMP-04, CMP-07.

**Q15. Recording consent and signature level (open point 5).** MTG-02/MTG-08 default to notices on, 24 h;
recording law varies by country. DOC-05 says the legal weight must be confirmed. Which consent policy and
which signature level? Affects MTG-02, MTG-03, MTG-07, MTG-08, DOC-05.

**Q16. Design shows the MCP endpoint under the Orgpuls domain.** Platform.dc.html shows
`https://sentral.orgpuls.no/mcp`, while the admin now lives in a separate repository and Supabase project
(`zuvqbaejoktpekfsiyyr`). Which host serves the MCP endpoint and OAuth? Affects MCP-01, MCP-03.

**Q17. Subtasks have no screen.** PRJ-03 subtasks and PRJ-04 cycle prevention appear only in
`coverage-data.js`, not in Projects.dc.html. Build without a design, or wait for one? Affects PRJ-03.

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
drift between `0001`/`0002` and the live schema is not established (see Q-30).

Abbreviations: `0001` = `supabase/migrations/0001_foundation.sql`, `0002` = `supabase/migrations/0002_product_secrets.sql`,
`PC` = `supabase/functions/product-command/index.ts`, `OE` = `supabase/functions/orgpuls-events/index.ts`.
Design files are in `design-reference/sentral/project/`. Prior art is Orgpuls at `ced4af2` (removed by Orgpuls 0206).

Two register rows apply to every ID and are not repeated per row: **Anonymity firewall** (fixed) and **Typed reason for CRM
actions** (off). Nothing in this scope can be Implemented: the repository has 4 vitest unit tests (`tests/signing.test.ts`),
no database tests, no end-to-end tests and no screenshots.

---

#### 1. Features — SEC, INT, MOB, ENT

| ID and name | Status | Evidence | Missing or different | Settings | Depends on | Work package | Design screen | Prior art (Orgpuls ≤0206) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SEC-01 Security dashboard | Missing | No login log table, no sessions read, no security page. Only page is the status page `app/page.tsx:12-106` (installations, counts, events, commands) | All of it: live sessions and locations; 7-day new devices/locations/security events/forced logouts; risk assessment with fixes; admin-only; each figure opens its list; figures match the login log | — | SEC-04 (login log), SEC-02, SF-27, UF-15 | — | `Security.dc.html` tab "Security dashboard" | none found |
| SEC-02 Security alerts | Missing | No email provider, no job runtime, no security events (`0001` has no such table; `ingest_events` handles product events only, `0001:225-263`) | All of it: email alerts on new device/location, invite, >3 failed logins, password reset, large exports/deletions; immediate or digest; one alert per trigger to admins | none in register (the ">3 failed logins" threshold is a number from the source — see Q-05) | SEC-04, email provider (open point 2), job runtime (open point 3), SF-27 | — | `Security.dc.html` tab "Alerts and rules" | none found |
| SEC-03 Security rules | Missing | Password sign-in only `app/login/actions.ts:16`; no IP/time check in `middleware.ts:12-52`; no Supabase Auth config in the repo (no `supabase/config.toml`) | All of it: company-wide password strength/expiry/reuse; IP and time restrictions; preview of affected users; a login from a blocked IP is refused. Supabase project-level password policy, if any, is not in the repo (Q-04) | none in register; IP/time restrictions are restrictions under R5 but are not listed (Q-05) | SEC-04, SF-27, UF-15 | — | `Security.dc.html` tab "Alerts and rules" (Security rules list) | Orgpuls admin had an idle-session cookie, `lib/admin/actions.ts:36` (session timeout) |
| SEC-04 Device and login history | Missing | No login log. `signOut` ends only the local session: `app/login/actions.ts:21-25` (`scope: 'local'`) | All of it: per user devices, locations, IPs, time, method, session end for 60 days; remote log-out that ends a session at once; separate from record changelogs | — | SF-27, login_log entity (Part F) | — | `Security.dc.html` tab "Device and login history" | none found |
| SEC-05 Single sign-on | Missing | Email + password only `app/login/actions.ts:9-19`; no OAuth/SAML provider code or callback route | All of it: SAML (Entra ID, Okta), Google sign-in; fallback admin login; IdP-provisioned user logs in without local password | — | SEC-06, SF-27 | — | `Security.dc.html` tab "SSO and two-factor" | Product-side only: Orgpuls `0155_entra_signin.sql` (customer leaders' Microsoft sign-in, still in Orgpuls) — not admin |
| SEC-06 Two-factor authentication | Partial | **Met:** "a second factor at login by … authenticator app" — TOTP enrol/verify `app/mfa/actions.ts:14-23` (TOTP only, l.20), `:27-33` (`challengeAndVerify` l.31), `app/mfa/page.tsx:9-11`. **Met in effect:** "with enforcement on, no user can log in without the second factor" — every non-public path requires aal2 `middleware.ts:43-46` (public: `/login`, `/ingen-tilgang`, l.10; fails closed l.22-26, 48-51); every RPC requires aal2 via `app.is_admin()` `0001:32-36`; `PC:53-57` refuses non-admin. No test covers any of it | Not met: email-code factor; an admin control to enforce it (enforcement is hard-wired, always on — CLAUDE.md:21-22); account recovery (no recovery codes; a lost device has no path); remembered login email (only browser `autoComplete`, `app/login/LoginForm.tsx:16`). No test | none in register; MFA cannot be a switch that lowers protection (R7) — Q-06 | SEC-05, SF-27, UF-15 | — | `Security.dc.html` tab "SSO and two-factor" | Orgpuls `0049_platform_admin.sql`: `platform_admins.mfa_enforced` per admin, `app.admin_role()` aal2 check |
| SEC-07 Permission sets | Missing | `app.admins.role` is `owner`\|`admin` `0001:20` but is never read: `app.is_admin()` ignores it `0001:32-36`; no other role check in `app/`, `lib/`, `supabase/` | All of it: named sets of actions per app (deals, projects, campaigns) and global; admin/regular/custom; actions create/edit/delete/import/export/bulk edit/change visibility/view reports; custom-set count an entitlement; enforced in UI and API. The four baseline roles (super-admin, support, finance, analyst) do not exist (Q-01) | Plan gates and usage limits (number of custom sets) | SEC-08, SEC-09, ENT-02, SF-01, open point 10 | — | `Settings.dc.html` section "Permission sets" | Orgpuls `0049`: enum `app.platform_role` (super_admin, support, finance, analyst), `app.is_platform_admin(roles[])`; `marketing` added in `0055_crm.sql:37`, `editor` in `0125_editor_role.sql:6`; route `app/(admin)/admin/admins` |
| SEC-08 Visibility groups | Missing | No groups, no owner columns. Every table RLS on with **no policy** `0001:156-165`; reads go through SECURITY DEFINER functions (`0001:4-7`, CLAUDE.md:17-20), which bypass RLS | All of it: groups and sub-groups; per-item visibility (owner, group, group+sub-groups, everyone); defaults per record type; pipelines limited to groups; placeholder setting; custom-group count an entitlement; "enforced by row-level security" conflicts with the repository's definer-function pattern (Q-02) | Plan gates and usage limits (custom groups) | SEC-07, SF-01, all record modules | — | `Settings.dc.html` section "Visibility groups" | none found |
| SEC-09 Users and teams | Partial | **Met (partly):** staff list = `app.admins` (email, role, active) `0001:18-23`; a deactivated admin (`active=false`) gets no admin identity `0001:29`, so every RPC refuses and the page sends them to `/ingen-tilgang` `app/page.tsx:13-15` — "a deactivated user cannot log in" holds for access, though Supabase Auth still signs them in. Users are added by hand in the Supabase dashboard + SQL (README.md:27-28) | Not met: invite, deactivate, replace and reassign screens/RPCs; teams with manager and members; copy access; user overview (followed items, last login); own profile and phone; workflow-transfer prompt (AUT-10); "records keep an owner" (no owned records exist). No test | — | SEC-07, SEC-08, AUT-10, SF-43, UF-15 | — | `Settings.dc.html` section "Users and teams" | Orgpuls `0049` `platform_admins` (user_id, role, active, created_by), route `app/(admin)/admin/admins` |
| SEC-10 Data protection | Partial | **Met:** EU hosting for the database — eu-central-1 (README.md:11, CLAUDE.md:11); isolation of CRM data from survey data — a separate project/database holding no survey table (`0001` table list l.18-136; `0001:9-10`; CLAUDE.md:33-35); in transit — HSTS `next.config.ts:28`, https-only Supabase URL `lib/supabase/env.ts:8`, https-only product URL `0001:49`; secrets at rest in Vault `0002:46-50`, `0002:58-65` | Not met / not established: encryption at rest of the database (provider-managed, not in repo — Q-31); backups and stated RPO/RTO (not in repo); restore test (AC) — none. Vercel and edge-function regions not configured in repo (no `vercel.json`). Design shows "EU · Stockholm (eu-north-1)" and "RPO 1 h · RTO 4 h" (Q-20) | — | open point 8, SF-43 | — | `Security.dc.html` tab "Data protection" | none found |
| SEC-11 Privacy compliance | Missing | No export/erasure function, no consent log, no retention job, no sub-processor list. `org.deleted` only marks `account_products.status='deleted'` `0001:231-232`; `app.members` email/name rows stay (cascade only fires if `account_products` rows are deleted, `0001:108`, which nothing does); `member.left` keeps email/name `0001:255-257` | All of it: export and erasure of a person on request; consent logs; retention rules; sub-processor list; erasure across emails, recordings, transcripts, enrichment; AC "removes the person from every module". Today's ingest retains customer users' personal data indefinitely (Q-21) | Contact rule / Consent source on import are adjacent (CRM-01, CRM-09), not listed for SEC-11 | CRM-12, SF-15, SF-43, MTG-08 | — | `Security.dc.html` tab "Privacy compliance" | Orgpuls `0141_growth_foundations.sql` (`consent_purposes` l.668, `consent_records` l.697, erasure logic), routes `app/(admin)/admin/crm/consent` + `/export`; customer-side retention in Orgpuls `0136_retention.sql` (still in Orgpuls) |
| INT-01 REST API | Missing | Only endpoints: `PC` (one POST that forwards an allow-listed Orgpuls command, `PC:21-95`), `OE` (inbound events), `secret-intake`; and RPCs `admin_whoami`, `platform_status` `0001:292-327` | All of it: versioned list/get/create/update/delete/search for every entity incl. custom fields; filtering, pagination; published reference, client libraries, collections; generated from the registry; every UI record action available | API rate limits; Plan gates and usage limits | SEC, ENT, event catalog, CUS-01 registry, SF-22 | — | `Platform.dc.html` tab "REST API and tokens" | none found |
| INT-02 Authentication | Missing | No API tokens or OAuth apps. Existing tokens are internal: a 2-minute HS256 command token to Orgpuls `supabase/functions/_shared/orgpuls.ts:51-53`, `_shared/signing.ts:62-67`; staff Supabase session JWT | All of it: one personal API token per user in a header; OAuth 2.0 with scopes; rotation invalidates at once; revoked token/grant refused | Plan gates and usage limits (API tokens, ENT-02) | SEC-07, SF-22, UF-16 | — | `Platform.dc.html` tab "REST API and tokens" | none found |
| INT-03 Rate limits | Missing | No rate limiting. Only size caps: ingest ≤500 events `0001:190`, `OE:48`; body ≤200 kB `PC:32`, ≤1 MB `OE:118-120` | All of it: daily token budget (base × plan multiplier × seats), cost per endpoint type, 2-second burst limit, 429 with limit headers, 75 %/100 % emails, usage dashboard; off by default | API rate limits (default Off) | INT-01, INT-02, ENT-03 (plan multiplier), SF-22 | — | `Platform.dc.html` tab "REST API and tokens" ("Rate limits Off (setting)") | none found |
| INT-04 Webhooks | Missing | Inbound only: `OE` verifies an HMAC-signed POST from Orgpuls (`OE:30-40`, `_shared/signing.ts:41-58`). No outbound subscriptions, deliveries or retries | All of it: subscriptions by action and object; POST with current and previous state; source limits as settings (40 per user, 10 s timeout, retries 3/30/150 s, 30-min ban after 10 failures, deletion after 3 days); SSRF block (A7.7). `hmacHex` (`signing.ts:27`) could sign payloads if Tor decides to (A4) | Count limits (webhooks per user); Technical safeguards (retry and ban policy) | event catalog, outbox (SF-02), SF-23, job runtime | — | `Platform.dc.html` tab "Webhooks" | Inbound mail-provider webhooks only (Orgpuls `0053_mail_events.sql`) |
| INT-05 Google Workspace | Missing | No provider connection, no OAuth client, no token storage | All of it: contacts, calendar, tasks, Drive, Gmail, Meet, sign-in; connect and revoke per user | Contact rule (via CRM-04) | COM-02, ACT-09, CRM-04, DOC-03, SEC-05, A7.8 token encryption | — | `Platform.dc.html` tab "Integration catalog" | none found |
| INT-06 Microsoft 365 | Missing | As INT-05 | All of it: Outlook/Exchange mail, calendar, contacts, Teams links and notifications, OneDrive, SharePoint; connect and revoke per user | Contact rule (via CRM-04) | As INT-05 | — | `Platform.dc.html` tab "Integration catalog" | none found (Orgpuls `0155`/`0165` Entra are customer-side) |
| INT-07 Team chat | Missing | Nothing | All of it: deal events to Slack/Teams channels or DMs; search from chat; also a workflow action; won deal posts | — | PIP-07, AUT-07, event catalog | — | `Platform.dc.html` tab "Integration catalog" (Team chat); `Automation.dc.html` | none found |
| INT-08 Invoicing | Missing | No accounting adapter. `app.subscriptions` mirrors Orgpuls billing `0001:80-95`, not invoices | All of it: invoice in the accounting system from a deal with person, organization and products; status on the deal; adapter; carries the deal's lines | — | PIP-03, CRM-07, open point 2 | — | `Platform.dc.html` catalog "Accounting system (EHF)"; `Deals.dc.html` (Invoice composer tab, Invoices history) | none found |
| INT-09 Automation platforms | Missing | Nothing | All of it: no-code platform connectors on the API and webhooks; a new deal triggers an external automation | — | INT-01, INT-02, INT-04 | — | `Platform.dc.html` catalog "No-code automation platforms" | none found |
| INT-10 App extensions | Missing | Nothing | All of it: panels in deal and contact views; link/dialog/embedded actions; sandboxed; scope-limited data | — | INT-02, PIP-04, CRM-01 | — | `Platform.dc.html` catalog "App extensions" | none found |
| INT-11 Integration catalog | Missing | `app.installations` (product, api_url, public_key, enabled) `0001:47-54` lists connected *products*, shown read-only on `app/page.tsx:39-50`; that matches the design's "Applications" tab, not the catalog | All of it: catalog grouped in collections and tagged; access shown; install, settings, per-user management, removal that revokes access; third-party apps beside first-party | — | INT-02, INT-10, AIA-06 | — | `Platform.dc.html` tab "Integration catalog" | none found |
| MOB-01 Core app | Missing | No mobile client, no public API to serve one | All of it: iOS/Android pipeline, deals, leads, contacts, activities, detail, filters, search, real-time sync, portrait/landscape, phone-contact import; same permissions; change on mobile appears on web without refresh | Contact rule (MOB-01 listed) | INT-01, PIP, ACT, CRM, LEA, SF-44, UF-21 | — | `Mobile.dc.html` ("Deal on the go") | none found |
| MOB-02 Focus view | Missing | Nothing | All of it: overdue, unread count, nearby count, today/week, home-screen widget; counts match web filters | — | MOB-01, ACT, COM-02, MOB-03 | — | `Mobile.dc.html` ("Focus") | none found |
| MOB-03 Nearby | Missing | Nothing | All of it: map of nearby deals/orgs/people, filters incl. address custom fields, navigation hand-off, location permission; tap opens record | — | MOB-01, CRM-03, CUS-01 | — | `Mobile.dc.html` ("Nearby") | none found |
| MOB-04 Calls and texts | Missing | Nothing | All of it: in-app calls logged as activities (iOS outgoing only), caller matching, text hand-off | — | MOB-01, COM-12, ACT-01 | — | `Mobile.dc.html` ("Deal on the go") | none found |
| MOB-05 Offline mode | Missing | Nothing | All of it: offline edits of deals, notes, activities; sync on reconnect and manual; latest change wins with earlier value in changelog | — | MOB-01, CRM-02 changelog, SF-31 | — | `Mobile.dc.html` (offline toggle) | none found |
| MOB-06 Capture | Missing | Nothing; no storage buckets | All of it: audio notes with transcription, note scanner, photo/file upload, share-in, card scanner; scanned note saved on chosen record | Contact rule (via AIA-07) | MOB-01, AIA-07, CRM-05, transcription provider | — | `Mobile.dc.html` ("Capture") | none found |
| MOB-07 Push notifications | Missing | Nothing; no `device_token` | All of it: reminders, assignments, mentions, chat requests; per-type configuration; one push per assignment | — | MOB-01, ACT-04, AUT-11, CRM-06, LGN-02 | — | `Mobile.dc.html` ("Notifications") | none found |
| MOB-08 Mobile extras | Missing | Nothing | All of it: live chat takeover, project tasks, statistics dashboard; rep answers live chat from phone | Consent-gated loading of site widgets (via LGN-05) | MOB-01, LGN-02, PRJ-03, INS-03 | — | `Mobile.dc.html` ("Extras") | none found |
| ENT-01 Feature gating | Missing | No entitlement table, no feature flags | All of it: feature on/off per plan and add-on; checked in UI, API and workflow engine; gated feature unavailable everywhere; default all on | Plan gates and usage limits (default all on, unlimited) | SEC, billing, CUS-07, SF-16, UF-28 | — | `Settings.dc.html` ("Entitlements — features per plan and add-on"); `Platform.dc.html` tab "Feature flags" | none found |
| ENT-02 Usage limits | Missing | No counters. `app.usage_daily` `0001:111-118` holds Orgpuls customers' daily counts, not CRM limits | All of it: metered limits per company/seat (leads and deals … API tokens); unlimited until set; enforced at creation | Plan gates and usage limits; Count limits taken from the source | ENT-01, every counted module, SF-16 | — | `Settings.dc.html` section "Plans and usage" | none found |
| ENT-03 Plans, add-ons and top-ups | Missing | "Existing billing" here is only the mirror `app.subscriptions` (plan, trial, cancel fields) `0001:80-95` fed by `billing.changed` `0001:236-248`, plus Orgpuls `billing.*` commands `orgpuls.ts:14-17`; none of it models CRM plans | All of it: seat plans; add-ons per company/seat/volume; credit top-ups; free trial; buying an add-on enables at once. Whose plans these are in an internal back-office is unclear (Q-10) | Plan gates and usage limits | ENT-01, ENT-02, PRO-06 credits, billing | — | `Settings.dc.html` ("Add-on" column); `Feed.dc.html` (credit top-up) | none found |
| ENT-04 Usage screen and limit handling | Missing | Nothing | All of it: consumption against every limit; block new additions at a limit, delete nothing; overflow to waitlist/import skip file; warnings; matches actual counts | Plan gates and usage limits | ENT-02, PIP-16, CRM-09, SF-16 | — | `Settings.dc.html` ("Usage against every limit") | none found |

---

#### 2. Part F — Data model and API

#### 2.1 Conventions

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Product ID on every row | Partial | `product` column on `app.installations` `0001:48`, `account_products` `:67`, `subscriptions` `:81`, `members` `:99`, `usage_daily` `:112`, `events_in` `:124`, `audit` `:140` | Absent on `app.admins` `0001:18`, `app.accounts` `0001:58` (cross-product by design, README.md:3), `app.intake_nonces` `0002:9`. Column is named `product`, Appendix 2 says product ID (Q-11) |
| Access only through role checks, never bypassing RLS | Conflict | `app.is_admin()` `0001:32-36`; RLS on/no policy `0001:156-165` | The repository's rule is RLS-on-no-policy plus SECURITY DEFINER RPCs (`0001:4-7`, CLAUDE.md:17-20). Definer functions bypass RLS by construction, so "never by bypassing RLS" and A8's per-role RLS tests contradict the established pattern (Q-02) |
| No FK or grant from any CRM table to survey response tables | Partial | whole database | Holds structurally today: no survey table exists in this project; the product's event registry forbids respondent fields (Orgpuls `0205_platform_api.sql:76-99`); command allow-list excludes answer exports (`orgpuls.ts:8-44`, test `tests/signing.test.ts:43`). Not met: the database test A8/R6 demands (none) |
| Owner, visibility, created, updated, deleted on business records | Partial | `app.accounts` created/updated `0001:62-63`; `app.account_products` created/deleted_at `0001:73-74` | No owner, visibility or version on any table; `members`/`subscriptions` have only `updated_at` |
| Custom field values in JSON keyed by field ID, indexed; definitions in `custom_field` | Missing | none (`jsonb` columns `account_products.details/attribution` `0001:71-72` are product payloads, not field-keyed) | No `custom_field` table, no per-field index |
| Configuration as versioned rows | Missing | none | No pipelines, workflows, sequences, reports, templates, score models or permission sets |
| Soft delete 30 days, then permanent removal | Missing | `account_products.status`/`deleted_at` `0001:70,74` mark a product-side deletion only | No purge job, no cron, no restore |
| Row + changelog + event in one transaction; read audit row; version column | Missing | `public.ingest_events` `0001:173-266` writes event + projection in one function call (inbound only); `public.record_command` `0001:271-276` | No changelog, no outbox; the command audit is written after the remote call in a separate RPC and a failed audit is only logged (`PC:84-92`); reads (e.g. `platform_status`) are not audited; no version column |

#### 2.2 Entities

| Item | Status | Existing table/function to extend (path:line) or "none" | Notes |
| --- | --- | --- | --- |
| Identity: platform admin with role and MFA | Partial | `app.admins` `0001:18-23`; `app.admin_email()` `:25-30`; `app.is_admin()` `:32-36` | Role is owner/admin and unused; MFA is session-level (aal2), not a column. Baseline 4 roles absent (Q-01) |
| Identity: audit log | Partial | `app.audit` `0001:136-145`, trigger `:148-154` | Records product commands only (actor, product, command, arg names, ok, error). No reads, no target org/record, no reason column. `service_role` holds ALL incl. TRUNCATE `0001:163` and the trigger covers UPDATE/DELETE only, so TRUNCATE bypasses append-only (Q-12) |
| Identity relationship: staff identities separate from customer logins; admin role never derived from a customer role | Partial | `app.admins` matched to `auth.users` of this project `0001:28`; customers are `app.members` rows, not auth users `0001:98-109` | Holds structurally (separate project). No test |
| Identity: team | Missing | none | |
| Identity: team_member | Missing | none | |
| Identity: visibility_group | Missing | none | |
| Identity: permission_set | Missing | none (extend `app.admins.role` `0001:20`) | |
| Records: organization (org.nr, product ID) | Partial | `app.accounts` (name, `org_number` 9 digits unique) `0001:58-64`; product link via `app.account_products` `0001:66-77` | Org.nr present; product ID on the link table, not on the account. No notes, tags, owner, deleted, version. Created only by product events `0001:215-223` |
| Records: contact (type, role, source, consent basis) | Partial | `app.members` (product, tenant_id, user_id, role, email, name, active) `0001:98-109` | Customer users only (member.joined/left). No type, source, consent basis; keyed by product user id, not a person; no prospects. Part B says contacts exist with these fields — not here (Q-13) |
| Records: suppression list | Missing | none | Prior art: Orgpuls `crm_suppression` |
| Records: organization_relation | Missing | none | |
| Records: label | Missing | none | |
| Records: follower | Missing | none | |
| Sales: pipeline | Missing | none | Prior art: Orgpuls `crm_stages` (0056) |
| Sales: stage | Missing | none | Prior art: `crm_stages` |
| Sales: deal | Missing | none | Prior art: Orgpuls 0056/0119 deal tables |
| Sales: deal_participant | Missing | none | |
| Sales: deal_stage_history | Missing | none | Prior art: `crm_stage_changes` |
| Sales: lead | Missing | none | |
| Sales: lost_reason | Missing | none | |
| Sales: saved_filter | Missing | none | |
| Products: product | Conflict | `app.products` `0001:41-45` already means *installed software products* (key, name; seeded `orgpuls` `0001:329`) | Name collision with the CRM product catalog (Q-14) |
| Products: product_price | Missing | none | |
| Products: deal_product | Missing | none | |
| Products: revenue_schedule | Missing | none; recurring revenue source would be `app.subscriptions` `0001:80-95` (Part B: "comes from the billing mirror") | Mirror has plan/interval/trial/cancel dates, no amounts (Q-15) |
| Products: currency | Missing | none | |
| Products: exchange_rate | Missing | none | |
| Activities: activity | Missing | none | |
| Activities: activity_type | Missing | none | |
| Activities: activity_guest | Missing | none | |
| History: note | Missing | none | Prior art: `admin_org_notes` (0049) |
| History: comment | Missing | none | |
| History: file | Missing | none (no storage bucket) | |
| History: mention | Missing | none | Prior art: `ticket_mentions` |
| History: changelog | Missing | none | |
| Email: mail_account | Missing | none | |
| Email: mail_thread | Missing | none | |
| Email: mail_message | Missing | none | Prior art: `ticket_mail` |
| Email: mail_link | Missing | none | |
| Email: mail_event | Missing | none | Prior art: Orgpuls `0053_mail_events.sql` |
| Email: mail_template | Missing | none | Prior art: `mail_templates`, `crm_templates` |
| Email: signature | Missing | none | |
| Scheduling: availability | Missing | none | |
| Scheduling: booking_link | Missing | none | |
| Scheduling: booking | Missing | none | |
| Calls: call_log | Missing | none | |
| Messaging: message_thread | Missing | none | |
| Messaging: message | Missing | none | |
| Automation: workflow | Missing | none | The "lifecycle-messaging engine" to extend does not exist here (Q-16) |
| Automation: workflow_version | Missing | none | |
| Automation: workflow_run | Missing | none | |
| Automation: workflow_step_run | Missing | none | |
| Automation: assignment_rule | Missing | none | |
| Automation: assignment_log | Missing | none | |
| Automation: sequence | Missing | none | Prior art: Orgpuls journeys/sequences (crm_journeys, crm_sequences suites) |
| Automation: sequence_step | Missing | none | |
| Automation: enrollment | Missing | none | |
| Insights: report | Missing | none | |
| Insights: dashboard | Missing | none | |
| Insights: dashboard_item | Missing | none | |
| Insights: goal | Missing | none | |
| Insights: public_link | Missing | none | |
| Insights: rollup tables | Missing | `app.usage_daily` `0001:111-118` is a per-tenant daily product rollup, a possible source | No CRM rollups; "metrics as SQL views in git" (Part B) absent |
| Prospecting: score_model | Missing | none | |
| Prospecting: score_criterion | Missing | none | |
| Prospecting: deal_score | Missing | none | |
| Prospecting: feed_card | Missing | none | |
| Prospecting: enrichment_request | Missing | none | |
| Prospecting: credit_ledger | Missing | none | |
| Marketing: consent record (existing) | Missing | none | Part F calls it existing; it is not in this repo (Q-13). Prior art: `consent_records` (0141:697) |
| Marketing: suppression list (existing) | Missing | none | As above |
| Marketing: segment (existing) | Missing | none | Prior art: `crm_segments` |
| Marketing: campaign | Missing | none | Prior art: `crm_campaigns` |
| Marketing: campaign_recipient | Missing | none | Prior art: `crm_sends` |
| Marketing: campaign_event | Missing | none | Prior art: `crm_clicks` |
| Marketing: sender_domain | Missing | none | Prior art: `crm_senders`, `mail_auth_checks` |
| Projects: board | Missing | none | |
| Projects: phase | Missing | none | |
| Projects: project | Missing | none | |
| Projects: project_deal | Missing | none | |
| Projects: task | Missing | none | |
| Projects: milestone | Missing | none | |
| Projects: dependency | Missing | none | |
| Projects: project_template | Missing | none | |
| Lead generation: chatbot_playbook | Missing | none | |
| Lead generation: chat_conversation | Missing | none | |
| Lead generation: chat_message | Missing | none | |
| Lead generation: web_form | Missing | none | |
| Lead generation: form_submission | Missing | none; Orgpuls `contact.submitted` and `demo.requested` events land in `app.events_in` unprojected `0001:261-262` | Closest existing inbound path; contains a person's own words (CLAUDE.md:33-35) |
| Web visitors: tracked_site | Missing | none | Prior art: `web_events` |
| Web visitors: visitor_company | Missing | none | |
| Web visitors: visit | Missing | none | |
| Documents: document_template | Missing | none | |
| Documents: document | Missing | none | |
| Documents: document_link | Missing | none | |
| Documents: signature_request | Missing | none | |
| Documents: signer | Missing | none | |
| Documents: signature_event | Missing | none | |
| Meetings: meeting | Missing | none | |
| Meetings: recording | Missing | none | |
| Meetings: transcript | Missing | none | |
| Meetings: brief | Missing | none | |
| Meetings: recap | Missing | none | |
| Meetings: update_suggestion | Missing | none | |
| Platform: custom_field | Missing | none | |
| Platform: translation | Missing | none; UI strings are files `messages/no.json`, `messages/en.json` loaded by `lib/i18n/request.ts:9-10` | Orgpuls `translations.*` commands (`orgpuls.ts:18-25`) govern the product's texts, not the admin's |
| Platform: setting | Missing | none | No settings registry (A9) |
| Platform: import_job | Missing | none | |
| Platform: waitlist_item | Missing | none | |
| Platform: integration | Missing | `app.installations` `0001:47-54` (per product) is the nearest | |
| Platform: installed_app | Missing | as above | |
| Platform: device_token | Missing | none | |
| Platform: event | Partial | `app.events_in` `0001:122-133` | Inbound product events only: `product` NOT NULL FK and `source_id` NOT NULL (`0001:124-125`) do not fit platform-originated CRM events (Q-17) |
| Platform: notification | Missing | none | |
| Platform: webhook | Missing | none | |
| Platform: webhook_delivery | Missing | none | |
| Platform: api_token | Missing | none | |
| Platform: oauth_app | Missing | none | |
| Platform: oauth_grant | Missing | none | |
| Platform: entitlement | Missing | none | |
| Platform: usage_counter | Missing | none (`app.usage_daily` is customer product usage) | |
| Platform: login_log | Missing | none (Supabase's own `auth.audit_log_entries` is not read by any code) | |
| Platform: security_rule | Missing | none | |

#### 2.3 Event catalog

The "single typed events table" is `app.events_in` `0001:122-133`. Its kind check `^[a-z]+\.[a-z_]+$` (`0001:126`) is
object.action with a dot; Part F says "object_action naming" (Q-17). Consumers named in Part F (workflows, assignment,
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
| Product (existing): organization-level survey aggregates | Missing | none | Orgpuls `usage.daily` is "counts … nothing about any answer or any group" (Orgpuls `0205:91-93`); Part F/G allow aggregates of ≥5 (Q-18) |

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
| Data residency | Partial | Database eu-central-1 (README.md:11, CLAUDE.md:11) | Storage (none yet), logs, Vercel region, edge-function region, AI and sub-processors: not stated in repo. Design says Stockholm eu-north-1 (Q-20) |
| Sending | Missing | none | No email provider; no streams |
| Job runtime | Missing | none (no `pg_cron`, no queue, no worker). Orgpuls pushes events every five minutes (README.md:20-21) | Open decision (open point 3) |
| Recovery | Unknown | not in repo | RPO/RTO and restore tests not established (Q-31, open point 8) |
| Scale | Missing | Only an ingest batch cap of 500 (`0001:190`) | No sizing; source ceilings are reference only |
| Performance | Missing | Timeouts only: 5 s Supabase calls (`lib/supabase/env.ts:18-22`), 20 s product call (`PC:77`), 25 s app→function (`lib/platform/command.ts:28`) | No targets, no measurements (A8 asks Tor) |
| Monitoring | Missing | Status page shows last event time, counts by kind, last 10 commands with errors (`app/page.tsx:51-101`, `0001:302-325`) | No alerts on failed jobs, sync lag, send failures or error rates; no job monitor |
| AI governance | Missing | none | No AI features |
| Privacy | Missing | none | Erasure, recording consent, sub-processor list absent; personal data of customer users retained after `org.deleted` (`0001:231-232`) (Q-21) |
| Destructive actions | Missing | none in the platform UI. `orgs.delete_now` is in the command allow-list (`orgpuls.ts:12`), reachable through `runCommand` by any admin, not yet called from any screen | No preview, soft delete or approval setting in the platform; Orgpuls' `orgs.deletions` (read) could serve as preview (Q-22) |
| Interface language | Conflict | `no` is the source and default; English only by cookie (`lib/i18n/request.ts:9`; CLAUDE.md:12-13) | Spec: English is the default (CUS-05, Part G) (Q-03) |
| Test data | Missing | No seed, no demo tenant; no "Lumio AS"/"Kari Nordmann" outside `design-reference/` and `docs/` | R8 requires the seeded demo tenant; the only configured project is the production one (`.env.example`) (Q-23) |
| Provider independence | Missing | Product connection is per-product (`app.installations`, `orgpuls.ts`), not a third-party adapter layer | No adapters for mail, calendar, sending, telephony, transcription, LLM, data, e-signature |

#### 3.1 Part G architecture choices (verifiable claims about the existing admin)

| Design choice | Status | Evidence / note |
| --- | --- | --- |
| One API for every client | Missing | No public API (2.4) |
| Configuration as data | Missing | No registry |
| Outbox events | Missing | No outbox/dispatcher; inbound events only |
| One workflow engine on the admin's lifecycle-messaging engine | Conflict | No such engine exists in this repository (Q-16) |
| Adapters for providers | Missing | none |
| AI gateway | Missing | none |

#### 3.2 Open points and risks (Part G), as questions

Decided on 3 October (recorded, not questions): all 183 features are built; every restriction is a setting defaulting to
unrestricted; the existing CRM "is not assessed"; size not decided separately (≥169 person-weeks).

1. **One engine (OP-1).** Which engine should workflows, sequences and assignment extend? Part B/G assume an existing lifecycle-messaging engine; the platform has none (Q-16).
2. **Build or buy (OP-2).** Which provider per service — mail sync, meeting capture and transcription, company and contact data, e-signature evidence, telephony — and which accounting system for INT-08 first?
3. **Job runtime (OP-3).** Database queues and cron (pg_cron/pgmq in this project) or a separate worker service?
4. **Legal exposure of the defaults (OP-4).** Which settings must be switched on per market, and who performs the legal review of the unrestricted defaults before go-live?
5. **Recording consent and signature level (OP-5).** What consent policy applies to MTG, and what e-signature level is needed?
6. **Undefined source items (OP-6).** What is the LinkedIn connector in LEA-06? Should the build go beyond the source with recurring activities and activities linked to more than one deal?
7. **Three inventory rows outside the 183 (OP-7).** Add named migration sources, the Mailchimp migrator and partnership discounts, or leave them out?
8. **Targets and running costs (OP-8).** What are the performance, RPO and RTO targets, and what is the cost model for language models, transcription and enrichment before phase 7?
9. **Originality (OP-9).** Confirmed rule: neutral names, own design and text — any naming review needed beyond R12?
10. **Staff roles (OP-10).** Which roles or permission sets should SEC-07 add for sales rep, manager, marketer and project manager — and, given the code has only owner/admin, should the four baseline roles be built first (Q-01)?

---

#### 4. Questions and conflicts

| # | Question or conflict | IDs affected |
| --- | --- | --- |
| Q-01 | **Role model.** The SEC intro, Part B and Part F say the admin already has four staff roles (super-admin, support, finance, read-only analyst) and `is_platform_admin(role)`. The code has `app.admins.role in ('owner','admin')` (`0001:20`), read by nothing, and `app.is_admin()` (`0001:32-36`). Build the four roles (as Orgpuls 0049 did), or define a new role/permission-set model directly? | SEC-07, SEC-08, SEC-09, NFR Access, Part F Identity, OP-10 |
| Q-02 | **RLS vs definer functions.** SEC-08 says "enforced by row-level security", Part F says "never by bypassing RLS", A8 wants per-role RLS allow/deny tests. The repository's rule (CLAUDE.md:17-20, `0001:4-7`) is RLS-on-no-policy and SECURITY DEFINER RPCs, which bypass RLS. Keep the definer pattern with visibility checks inside functions (tested), or introduce policies and client grants? | SEC-07, SEC-08, Part F conventions, A8 |
| Q-03 | **Interface language.** Spec: English default. Code: Norwegian (`no`) source and default, English by cookie (`lib/i18n/request.ts:9`, CLAUDE.md:12-13). Which wins? | NFR Interface language, CUS-05 |
| Q-04 | **Auth settings outside the repo.** Password policy, leaked-password protection, session lifetime and whether sign-ups are off live in Supabase project settings (README.md:29 asks the owner to turn sign-ups off). Not visible in the repo; may Phase A read them, and should they be codified? | SEC-03, SEC-06, SEC-04 |
| Q-05 | **Restrictions missing from the register.** IP/time restrictions, password expiry/reuse (SEC-03), the ">3 failed logins" alert threshold (SEC-02), 60-day login history (SEC-04) and push-type configuration (MOB-07) are rules or numbers not in the CUS-07 register. Add them as settings (default off/unrestricted per R5/A9)? | SEC-02, SEC-03, SEC-04, MOB-07, CUS-07 |
| Q-06 | **MFA enforcement as a setting.** SEC-06 says "Admins can enforce it for everyone", implying it can be off; R7 and CLAUDE.md:21-22 make it mandatory. Confirm MFA stays always-on for staff and SEC-06's toggle is satisfied by "always enforced", or does it apply to some other user class? Also: is an email-code factor acceptable alongside TOTP, and how is account recovery done (recovery codes vs owner reset)? | SEC-06, R7 |
| Q-07 | **Who are the "users" of SEC-01/02/04/09 and INT-02?** All staff are `app.admins`. Is every CRM user a platform admin (with a role), or will non-admin staff accounts exist? | SEC-01, SEC-02, SEC-04, SEC-09, INT-02 |
| Q-08 | **SSO scope.** SEC-05 lists SAML (Entra, Okta) and Google. Which IdP does the company use, and does SAML (a Supabase paid feature) fit the plan? | SEC-05 |
| Q-09 | **Mobile app.** MOB-01..08 require native iOS/Android clients; R9 forbids a new stack without asking. Which technology (React Native/Expo, PWA), distribution (App Store/MDM) and who signs builds? | MOB-01..MOB-08 |
| Q-10 | **Meaning of ENT in an internal back-office.** ENT gates CRM features "per plan and add-on", "per company or per seat", with "free trial" and "top-ups". The admin is a single internal company. Are ENT plans (a) the CRM's own internal configuration, (b) a preparation for selling the CRM, or (c) Orgpuls customers' plans? The design's "Plans and usage" (`Settings.dc.html`) shows the CRM's own usage. | ENT-01..ENT-04, INT-03, SEC-07, SEC-08 |
| Q-11 | **Product ID convention.** Existing column is `product` (text key), not `product_id`; `app.accounts` and `app.admins` deliberately carry none (an account spans products). Keep that, or add product IDs to them? | Part F conventions, NFR Access |
| Q-12 | **Audit append-only gap.** `service_role` has ALL on `app.audit` (`0001:163`) and the trigger covers UPDATE/DELETE, not TRUNCATE (`0001:154`); Orgpuls' 0049 had a truncate guard. Fix in Phase B (adding a guard tightens, not weakens, R7)? Also the command audit is written after the action in a separate call and its failure is only logged (`PC:84-92`) — acceptable? | NFR Audit, Part F Identity audit, A7.11 |
| Q-13 | **"Existing" CRM records that do not exist.** Part B/F describe existing contacts (type, role, source, consent), consent records, suppression list, segments, tickets, typed events table feeding funnel/health score, health score, SQL metric views, job monitor, feature flags, coupon codes, Brønnøysund sync. In this repository only `app.accounts`, `app.members` and `app.events_in` exist; the rest was in Orgpuls and was deleted by 0206. Phase B must build them; port from Orgpuls `ced4af2` or redesign? | Part F Records/Marketing, SEC-11, ENT-03, INT-11 |
| Q-14 | **Name collision `products`.** `app.products` (`0001:41`) is the list of connected software products. The CRM product catalog (CRM-07, Part F "product") needs another name. | Part F Products, CRM-07, INT-08 |
| Q-15 | **Revenue from the billing mirror.** Part B says recurring revenue for Orgpuls customers comes from the mirror; `app.subscriptions` has no amounts or seat counts (`0001:80-95`) and Orgpuls' `billing.changed` registry has none (Orgpuls `0205:88-90`). Extend the product event, or read prices elsewhere? | Part F revenue_schedule, ENT-03, INT-08 |
| Q-16 | **Lifecycle-messaging engine.** Part G "one workflow engine" and OP-1 assume it exists; nothing in the platform does. Build it new in phase 0/3? | Part G architecture, OP-1, Part F Automation |
| Q-17 | **One events table for in and out.** `app.events_in` requires `product` (FK) and `source_id` (`0001:124-125`), fitting inbound product events only. Extend it (nullable source, a "platform" product, a direction column) or add an outbox table? Also naming: code uses `object.action` (dot), Part F says "object_action". | Part F event catalog, Platform: event, INT-04, SF-02 |
| Q-18 | **Survey aggregates as product events.** Part F/G allow organization-level survey aggregates (≥5). Orgpuls' registry sends none ("nothing about any answer or any group", Orgpuls `0205:91-93`). Should Orgpuls be asked to add aggregates, or is the stricter current contract the rule? | Part F Product events, NFR Anonymity firewall, PRO-03 |
| Q-19 | **Design shows events and actions that do not exist.** `Platform.dc.html` lists `orgpuls.org.signed_up`, `orgpuls.survey.sent`, `orgpuls.user.logged_in`, `orgpuls.payment.failed`, `orgpuls.trial.day_7` (three-segment names, which `0001:126` rejects) and remote actions `/orgs/{orgnr}/suspend`, `/export`, `/support-access/requests`, `PUT /flags/{key}` not in the command map (`orgpuls.ts:8-44`); it also shows product auth as "OAuth 2.0 client credentials" while the code uses HS256 shared-secret tokens and HMAC. Build to the code's contract and render only real data? | INT-11, ENT-01, Part F event catalog |
| Q-20 | **Hosting region and recovery figures in the design.** Design: "EU · Stockholm (eu-north-1)", Supabase "EU · Stockholm", "RPO 1 h · RTO 4 h". Code: eu-central-1 (Frankfurt). Spec source: RPO 1 h, RTO 2 h. Which are the real values to show? | SEC-10, NFR Data residency, NFR Recovery |
| Q-21 | **Retention of customer users' data.** `org.deleted` marks the tenant deleted but keeps `app.members` email and name; `member.left` keeps them too (`0001:231-232`, `0001:255-257`). What retention rule applies, and should erasure (SEC-11) purge them? | SEC-11, NFR Privacy |
| Q-22 | **Destructive product commands.** `orgs.delete_now` (and `billing.cancel`) are callable by any admin through `runCommand` (`orgpuls.ts:12,16`). Preview and soft delete are "always" in Part B; should the platform require a preview via `orgs.deletions` and the second-admin setting for these? | NFR Destructive actions, CRM-12, SEC-07 |
| Q-23 | **Development database and demo tenant.** R8 forbids production and requires the Lumio AS / Kari Nordmann demo tenant. The only project configured is `zuvqbaejoktpekfsiyyr` (`.env.example`), which is production; no seed exists. Create a development project/branch and a seed? | NFR Test data, CUS-08, all IDs (testing) |
| Q-24 | **Session timeout, IP allowlist, login alerts, access review, break-glass.** The SEC intro says the admin specification already has these; none exists in code (only the 5 s fetch bound and middleware aal2). Are they in scope as part of SEC-03/SEC-02/SEC-09, or separate baseline work from Appendix 2? Design shows "Session timeout 30 min idle · IP allowlist on". | SEC-02, SEC-03, SEC-09 |
| Q-25 | **Secrets for provider tokens.** A7.8 requires encryption of provider tokens with the existing mechanism; the repo has Vault for product secrets (`0002`). Is Vault (one secret per token) the mechanism for per-user OAuth tokens too, or pgsodium/column encryption? | INT-02, INT-05, INT-06, INT-08, A7.8 |
| Q-26 | **Webhook signature.** Design marks "Signature header: open decision (A4)". The repo already signs/verifies with HMAC-SHA256 (`signing.ts`). Use the same scheme for outbound webhooks? | INT-04 |
| Q-27 | **INT-05/06 sign-in vs staff identity.** "Sign-in" with Google/Microsoft overlaps SEC-05. Does a Workspace/365 connection also become a staff login path, given admins are matched by email (`0001:28`)? Matching by email is the nOAuth risk Orgpuls 0155 documents. | INT-05, INT-06, SEC-05 |
| Q-28 | **INT-03 plan multiplier and seats.** The budget formula needs plans and seats, which depend on Q-10. | INT-03, ENT-03 |
| Q-29 | **MOB-08 / MOB-07 chat requests.** Live chat (LGN-02) is a public widget; should its takeover from mobile follow the same consent-gated widget setting, and is LGN in scope before MOB? | MOB-07, MOB-08, LGN-02, LGN-05 |
| Q-30 | **Schema drift.** The live project was not introspected (A3.2 requires reconciling migrations with a database; CLAUDE.md "Operating" says the Management API token here returns 403). How should Phase A introspect it? | All Part F rows |
| Q-31 | **Encryption at rest and backups.** Provider-managed (Supabase plan/PITR) and not visible in the repo. What plan and backup mode does the project use? | SEC-10, NFR Recovery |

---

#### 5. Counts

Features (34 IDs: SEC 11, INT 11, MOB 8, ENT 4): Implemented 0 · Partial 3 (SEC-06, SEC-09, SEC-10) · Missing 31 · Conflict 0 · Unknown 0.

Part F (199 rows): conventions 8 — Partial 3, Missing 4, Conflict 1; entities 123 — Partial 6, Missing 116, Conflict 1;
events 60 — Partial 4, Missing 56; API surface 8 — Missing 8. Total: Implemented 0 · Partial 13 · Missing 184 · Conflict 2 · Unknown 0.

Part G non-functional requirements (17): Implemented 0 · Partial 4 · Missing 11 · Conflict 1 (Interface language) · Unknown 1 (Recovery).
Architecture choices (6, supplementary): Missing 5 · Conflict 1.

Questions: 31 (Q-01 to Q-31), plus the 10 Part G open points restated as questions in 3.2.

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

A10/A5 require each gate flow to pass end to end before a phase closes; the platform has no end-to-end tool (Q1).

### Table

Prior art in Orgpuls before 0206 is given in each flow-level row (table names from the removed list and the
`ced4af2` route tree `app/(admin)/admin/*`; not read in detail). None of it counts toward a status here.

| Flow / step | Status | Evidence | Missing or different | Feature IDs it needs | Design screen |
| --- | --- | --- | --- | --- | --- |
| **UF-01 Capture and qualify a lead** (gate, phase 1) | Missing | E0 | All of it: lead capture from every channel with source, rule assignment, lead work, archive, conversion to deal with history. Prior art (Orgpuls ≤0206): `crm_companies` (source brreg/import/manual/signup, 0056), `crm_contacts`, `brreg_entities`/`brreg_outreach` (0143); routes `/admin/crm/prospects`, `/admin/crm/contacts`. No separate lead object in the removed list | LEA-01..05, AUT-11, PRO-04, CRM-15, ACT-07 | Contacts.dc.html (Leads tab), Automation.dc.html, Feed.dc.html, Marketing.dc.html |
| UF-01 · 1 Lead arrives from form, chatbot, import, prospect search or manual entry, source recorded | Missing | E0. Note: Orgpuls' `contact.submitted` and `demo.requested` events are stored raw in `app.events_in` (`0001:201–204`) and fall into the no-op branch (`0001:261–262`); no lead is made | No lead entity, no channel, no source field (Q13) | LEA-04, CRM-15; channels LGN-01, LGN-03, LGN-04, CRM-09 (not in the flow's "Uses" list, Q14) · Settings: form_tracking, contact_rule | Contacts.dc.html (Leads); Marketing.dc.html (Web forms, Chatbot and live chat, Prospect search) |
| UF-01 · 2 Assignment rule sets owner; owner notified | Missing | E0 | No rules, no owner, no notifications, no email provider (Q17) | AUT-11, SF-06, SF-07 | Automation.dc.html (Assignment rules) |
| UF-01 · 3 Rep opens lead, reads enriched company data and chat/form answers | Missing | E0 | No lead view, no enrichment | LEA-01, PRO-04 | Contacts.dc.html (Leads); Feed.dc.html (Enrichment) |
| UF-01 · 4 Rep emails or calls; contact logged on the lead | Missing | E0 | No email, calling or activity log | LEA-05; COM-12 for calls (not in "Uses", Q14) | Contacts.dc.html; Inbox.dc.html |
| UF-01 · 5 Not relevant: label and archive; flow ends | Missing | E0 | No labels, no archive | LEA-02, LEA-01 | Contacts.dc.html (Leads) |
| UF-01 · 6 Qualified: convert to deal, pick pipeline and stage | Missing | E0 | No deals, pipelines or conversion | LEA-03 | Contacts.dc.html; Deals.dc.html |
| UF-01 · 7 Notes, emails, files, activities move to the deal; next-activity prompt | Missing | E0 | Nothing to move; no prompt | LEA-03, ACT-07 | Contacts.dc.html; Activities.dc.html |
| **UF-02 Work a deal to won or lost** (gate, phase 1) | Missing | E0 | All of it: pipeline board with activity warnings and rotting, deal detail, activities, stage move with required fields, products, won/lost, workflow on close. Prior art (Orgpuls ≤0206): `crm_stages`, `crm_stage_changes` (0093, 0137), `crm_companies.stage`, `crm_activities` (0056); routes `/admin/crm/pipeline`, `/admin/crm/stages` — a company pipeline, not deals | PIP-01..07, CUS-02, CRM-07, ACT-01, ACT-04, ACT-07 | Deals.dc.html |
| UF-02 · 1 Pipeline opens; no-activity warning; idle deals rotting | Missing | E0 | No pipeline, no rotting | PIP-01, PIP-05, ACT-01, SF-26 | Deals.dc.html (Pipeline; "rotting" present) |
| UF-02 · 2 Deal opens with Focus and History | Missing | E0 | No deal view, no changelog | PIP-04 | Deals.dc.html ("Focus", "History" present) |
| UF-02 · 3 Complete due activity, plan next when prompted | Missing | E0 | No activities | ACT-01, ACT-04, ACT-07 | Deals.dc.html; Activities.dc.html |
| UF-02 · 4 Drag to next stage; blocked while a required field is empty | Missing | E0 | No stage move, no field rules | PIP-01, CUS-02 | Deals.dc.html; Settings.dc.html (Data fields: "Required from Negotiation") |
| UF-02 · 5 Add products; value recalculates | Missing | E0 | No product catalog, no derived value | CRM-07, PIP-03, SF-32 | Deals.dc.html (Products) |
| UF-02 · 6 Mark won, or lost with reason | Missing | E0 | No status, no lost reasons | PIP-07 | Deals.dc.html |
| UF-02 · 7 Workflows listening for the change run (e.g. create project) | Missing | E0 | No workflow engine, no CRM events | AUT-02, AUT-07, PRJ-01 (not in "Uses", Q14) | Automation.dc.html |
| **UF-03 Daily routine in the feed** (gate, phase 4) | Missing | E0 | All of it: three-tab feed, card actions, scheduling next steps, score filter and counter. Prior art (Orgpuls ≤0206): `/admin/crm/tasks` over `crm_activities` open tasks (index `crm_activities_open`, 0056) | PRO-01, PRO-02, PRO-03, COM-06 | Feed.dc.html |
| UF-03 · 1 Feed on Follow-ups: replies, opened emails, today's activities, emails waiting to send | Missing | E0 | No feed, no email tracking | PRO-01, COM-06, SF-13 · Settings: tracking | Feed.dc.html ("Follow-ups" tab) |
| UF-03 · 2 Act from the card or the side panel | Missing | E0 | — | PRO-02 | Feed.dc.html |
| UF-03 · 3 Overlooked deals: no follow-up or overdue; schedule next step | Missing | E0 | — | PRO-01, PRO-02 | Feed.dc.html ("Overlooked deals") |
| UF-03 · 4 Opportunities: new deals without activity; plan first step | Missing | E0 | — | PRO-01 | Feed.dc.html |
| UF-03 · 5 Filter by score; counter shows what is done | Missing | E0 | No scoring | PRO-03, PRO-01 | Feed.dc.html |
| **UF-04 Email outreach with tracking** (gate, phase 2) | Missing | E0 (no mail provider, no mailbox connection) | All of it: composer, templates, AI draft, merge fields, schedule, outbox with retry, open/click notifications, reply linking, AI summary, 5-day follow-up card. Prior art (Orgpuls ≤0206): `crm_templates`, `crm_clicks` (0056), `crm_senders` (0093), `crm_sends` (0055); routes `/admin/crm/inbox`, `/admin/crm/templates` | COM-02, COM-05, COM-06, COM-08, AIA-03, AIA-04 | Inbox.dc.html |
| UF-04 · 1 Composer from a deal; template or AI draft | Missing | E0 | No composer, no AI gateway | COM-05, AIA-03, SF-24 | Inbox.dc.html |
| UF-04 · 2 Merge fields fill; missing value flagged | Missing | E0 | — | COM-05 | Inbox.dc.html ("missing" present) |
| UF-04 · 3 Send now or schedule | Missing | E0 | — | COM-08 | Inbox.dc.html ("Scheduled and failed") |
| UF-04 · 4 Failure shows reason in outbox; retry | Missing | E0 | — | COM-08 | Inbox.dc.html (outbox, "retry") |
| UF-04 · 5 Open or click notifies the rep | Missing | E0 | — | COM-06, SF-07 · Settings: tracking | Inbox.dc.html |
| UF-04 · 6 Reply links to deal; summary and suggested reply | Missing | E0 | — | COM-02, AIA-04, SF-03 | Inbox.dc.html ("summar…" present) |
| UF-04 · 7 No reply after 5 days: follow-up card in feed | Missing | E0 | "5 days" is a fixed number with no register setting (Q2) | PRO-01, SF-26 (not in "Uses", Q14) | Feed.dc.html |
| **UF-05 Nurture with a sequence** (gate, phase 3) | Missing | E0 (no scheduler, no job runtime) | All of it: sequence builder, enrollment (single, bulk, by workflow), auto and manual email steps, activity steps, exit on reply or stage change, completion and failure. Prior art (Orgpuls ≤0206): `crm_campaigns.follows_id/follow_days` (0093), routes `/admin/crm/journeys`, `/admin/crm/triggers` | AUT-12, COM-05, ACT-01 | Automation.dc.html (Sequences) |
| UF-05 · 1 Build a sequence of email and activity steps with delays | Missing | E0 | — | AUT-12, COM-05 | Automation.dc.html (Sequences) |
| UF-05 · 2 Enroll one, bulk, or by workflow | Missing | E0 | — | AUT-12; AUT-07 for workflow enrollment (not in "Uses", Q14) | Automation.dc.html (Sequences) |
| UF-05 · 3 Auto email steps send on time; manual ones wait for review | Missing | E0 | — | AUT-12, COM-05, SF-05 · Settings: sales_consent | Automation.dc.html; Feed.dc.html (sequence emails waiting) |
| UF-05 · 4 Activity steps create activities for the owner | Missing | E0 | — | AUT-12, ACT-01 | Automation.dc.html |
| UF-05 · 5 Reply or stage change ends enrollment | Missing | E0 | — | AUT-12 | Automation.dc.html |
| UF-05 · 6 Completes; failed step marks enrollment failed with reason | Missing | E0 | — | AUT-12 | Automation.dc.html |
| **UF-06 Book a meeting** (gate, phase 2) | Missing | E0 (no calendar provider, no public surface) | All of it: availability, public booking page in the invitee's time zone, confirmations, activity with video link, calendar sync, reschedule/cancel. Prior art (Orgpuls ≤0206): none found in the removed list | COM-10, COM-11, ACT-08, ACT-09 | Activities.dc.html (Meeting scheduler) |
| UF-06 · 1 Set availability; booking link in email, signature or automated message | Missing | E0 | — | COM-10; COM-05 signature | Activities.dc.html (Meeting scheduler; "booking" present) |
| UF-06 · 2 Contact opens booking page, sees free slots in own time zone, picks one | Missing | E0 | Public token surface (A7.9) needed | COM-10 | Activities.dc.html; time-zone display not found (Q22) |
| UF-06 · 3 Both confirmed; activity with video link on the deal | Missing | E0 | No outbound mail, no video provider | COM-10, COM-11, ACT-08, SF-40 | Activities.dc.html |
| UF-06 · 4 Slot disappears; event syncs to the rep's calendar | Missing | E0 | — | COM-10, ACT-09, SF-08 | Activities.dc.html (Reminders and sync) |
| UF-06 · 5 Reschedule/cancel updates activity and calendar event | Missing | E0 | — | COM-10, ACT-08, ACT-09 | Activities.dc.html ("reschedul/cancel" present) |
| **UF-07 Run a meeting with meeting intelligence** (gate, phase 7) | Missing | E0 (no AI gateway, no recording provider) | All of it: brief, recording notice, bot/desktop capture, objection path, recap and transcript on deal with chat notice, CRM update suggestions with approval, follow-up draft. Prior art (Orgpuls ≤0206): none found | MTG-01..08, AIA-03 | Meetings.dc.html |
| UF-07 · 1 Rep reads the brief | Missing | E0 | — | MTG-01 | Meetings.dc.html (Pre-call brief) |
| UF-07 · 2 Attendees notified of recording; bot joins or desktop app records | Missing | E0 | Desktop app is a new stack element (Q18) | MTG-02, MTG-03, MTG-08 · Settings: rec_notice | Meetings.dc.html (Ways to capture; "notice" present) |
| UF-07 · 3 Attendee objects: remove bot or stop recording | Missing | E0 | — | MTG-02, MTG-08 | Meetings.dc.html (Workspace and controls); objection path not found (Q22) |
| UF-07 · 4 Recap and transcript saved on deal; chat message announces it | Missing | E0 | Chat notice finishes in phase 8 (Part G:2547) | MTG-04, INT-07 | Meetings.dc.html (Transcript and recap) |
| UF-07 · 5 Review suggested CRM updates; approve the right ones | Missing | E0 | — | MTG-05 · Settings: contact_rule | Meetings.dc.html (CRM update suggestions) |
| UF-07 · 6 Follow-up drafted from recap; plan next activity | Missing | E0 | — | AIA-03; ACT-07 (not in "Uses", Q14) | Meetings.dc.html; Inbox.dc.html |
| **UF-08 Quote to signature** (gate, phase 5) | Missing | E0 (no document generation, no storage bucket, no public surface) | All of it: templates, generation with product table, share link, signature request, open notification, code-verified signing, signed PDF and audit trail, workflow to won. Prior art (Orgpuls ≤0206): none found | DOC-01..06, CRM-07, AUT-01 | Documents.dc.html; Deals.dc.html |
| UF-08 · 1 Documents tab on the deal; pick a template | Missing | E0 | — | DOC-01 | Documents.dc.html (Templates); Deals.dc.html |
| UF-08 · 2 Generated with deal data and product table; opens for editing | Missing | E0 | — | DOC-01, DOC-02, CRM-07 | Documents.dc.html |
| UF-08 · 3 Share by trackable link or request signatures | Missing | E0 | — | DOC-04, DOC-05 · Settings: count_limits (signers) | Documents.dc.html (E-signature) |
| UF-08 · 4 Customer opens; rep notified | Missing | E0 | — | DOC-04, SF-07 | Documents.dc.html |
| UF-08 · 5 Each signer enters emailed code and signs | Missing | E0 | — | DOC-05, DOC-06, SF-20 | Documents.dc.html ("code" present) |
| UF-08 · 6 Signed PDF and audit trail on the deal; workflow can move to won | Missing | E0 | — | DOC-05, DOC-03, AUT-01, AUT-07 | Documents.dc.html ("audit trail" present) |
| UF-08 · 7 Nobody opens or signs: rep sees status and follows up | Missing | E0 | — | DOC-04, DOC-05 | Documents.dc.html |
| **UF-09 Set up the sales process** (gate, phase 1) | Partial | Only step 4, partly: `app.admins` (`0001:18–23`) | Steps 1, 2, 3, 5 missing; step 4 partial. Prior art (Orgpuls ≤0206): `platform_admins` (0049), `crm_stages` (0093), `crm_settings` (0055); routes `/admin/admins`, `/admin/crm/stages`, `/admin/settings` | PIP-02, PIP-14, CUS-01..08, ACT-02, SEC-07..09 | Settings.dc.html |
| UF-09 · 1 Create pipelines and stages with probabilities and rotting thresholds | Missing | E0 | — | PIP-02 | Settings.dc.html (Pipelines and stages; "probabilit", "rotting" present) |
| UF-09 · 2 Add custom fields, group them, mark important and required | Missing | E0 | No field registry (SF-38) | CUS-01, CUS-02, CUS-03, PIP-14 · Settings: count_limits (options per field) | Settings.dc.html (Data fields) |
| UF-09 · 3 Set activity types, currencies, modules on/off | Missing | E0 | — | ACT-02, CUS-05, CUS-06, CUS-07 | Settings.dc.html (Activity types, Language and currencies, Modules) |
| UF-09 · 4 Invite users, place in teams and visibility groups, assign permission sets | Partial | Met: a staff user list with a role exists — `app.admins` (email pk, `role in ('owner','admin')`, `active`; `0001:18–23`), checked by `app.admin_email()`/`app.is_admin()` (`0001:25–36`) | Not met: invite (rows are added only by SQL; no route, no email provider), teams, visibility groups, permission sets, deactivate/replace/reassign; roles are owner/admin only, not Appendix 2's four or open point 10's (Q7) | SEC-09, SEC-08, SEC-07 | Settings.dc.html (Users and teams, Permission sets, Visibility groups; "invite" present) |
| UF-09 · 5 Test with a sample deal; in a sandbox nothing reaches the live company | Missing | E0; no seed (no `supabase/seed*`, R8) | Sandbox = seeded demo tenant (INSTRUCTIONS.md:680–682) does not exist; `product-command` can reach live Orgpuls (Q8) | CUS-08 | Settings.dc.html (Sandbox) |
| **UF-10 Import and clean data** (gate, phase 1) | Missing | E0 | All of it: upload, mapping (AI later), duplicate preview, skip file, re-import, duplicate merge, revert from history. Prior art (Orgpuls ≤0206): `crm_companies.source = 'import'` (0056); not read further | CRM-09, AIA-05, CRM-11, CRM-12, ENT-04 | Contacts.dc.html (Import, Duplicates, Restore) |
| UF-10 · 1 Upload spreadsheet; confirm or correct suggested mapping | Missing | E0 | AI mapping waits for the gateway; manual until phase 7 (Part G:2543) | CRM-09, AIA-05 · Settings: import_consent | Contacts.dc.html (Import) |
| UF-10 · 2 Duplicates previewed; merge or create | Missing | E0. Note: `app.accounts.org_number` is unique (`0001:61`) and ingest matches accounts by it (`0001:216`) — a dedupe key import could reuse | No preview | CRM-09, CRM-11 | Contacts.dc.html (Duplicates: "Same org.nr") |
| UF-10 · 3 Import runs; invalid or over-capacity rows to skip file | Missing | E0 | — | CRM-09, ENT-04, SF-09 · Settings: plan_gates | Contacts.dc.html ("skip" present) |
| UF-10 · 4 Download skip file, fix, re-import | Missing | E0 | — | CRM-09 | Contacts.dc.html |
| UF-10 · 5 Review suggested duplicates and merge | Missing | E0 | — | CRM-11, SF-10 · Settings: second_admin | Contacts.dc.html (Duplicates) |
| UF-10 · 6 Revert a wrong import from history | Missing | E0 | — | CRM-09, CRM-12 | Contacts.dc.html ("revert" present; Restore) |
| **UF-11 Build a workflow** (gate, phase 3) | Missing | E0 (no job runtime; open point 3) | All of it: templates/canvas, triggers, conditions, actions, delays, branches, draft/activate with sharing, run history, failure alerts, limit refusal. Prior art (Orgpuls ≤0206): routes `/admin/crm/triggers`, `/admin/growth/rules`, `brreg_triggers`; not read further | AUT-01..10 | Automation.dc.html |
| UF-11 · 1 Start from template or blank canvas | Missing | E0 | — | AUT-01, AUT-08 | Automation.dc.html (Builder, Templates) |
| UF-11 · 2 Event or date trigger plus conditions | Missing | E0 | No CRM events (SF-02) | AUT-02, AUT-03, AUT-04 | Automation.dc.html (Builder) |
| UF-11 · 3 Actions, delays, wait-for, branches | Missing | E0 | — | AUT-07, AUT-05, AUT-06 · Settings: count_limits | Automation.dc.html (Builder) |
| UF-11 · 4 Save draft; activate for self, selected users or team | Missing | E0 | — | AUT-01, AUT-10 | Automation.dc.html (Workflows) |
| UF-11 · 5 Matching events start runs; history shows each | Missing | E0 | — | AUT-09, SF-04 | Automation.dc.html (Monitoring) |
| UF-11 · 6 Failed step alerts owner; opens failing step from overview | Missing | E0 | — | AUT-09 | Automation.dc.html (Monitoring) |
| UF-11 · 7 A set limit is reached: activation refused with reason | Missing | E0 | — | AUT-09 · Settings: count_limits, safeguards, plan_gates | Automation.dc.html |
| **UF-12 Set up automatic assignment** (gate, phase 3) | Missing | E0 | All of it: rules per trigger, conditions and assignee types, priority order, first-match assignment with creator fallback, assignment history. Prior art (Orgpuls ≤0206): `account_owners` (0118) | AUT-11, SEC-09 | Automation.dc.html (Assignment rules) |
| UF-12 · 1 Rule for lead added, deal added or deal updated | Missing | E0 | — | AUT-11 | Automation.dc.html (Assignment rules) |
| UF-12 · 2 Conditions and assignee: user, team, org owner, person owner | Missing | E0 | No teams | AUT-11, SEC-09 | Automation.dc.html |
| UF-12 · 3 Order by priority; activate | Missing | E0 | — | AUT-11 | Automation.dc.html |
| UF-12 · 4 First matching rule assigns; no match leaves creator | Missing | E0 | — | AUT-11, SF-06 | Automation.dc.html |
| UF-12 · 5 Assignment history shows which rule fired | Missing | E0 | — | AUT-11 | Automation.dc.html |
| **UF-13 Reports, dashboards and goals** (gate, phase 4) | Missing | E0. `public.platform_status` (`0001:302–325`) returns counts only and is not a report | All of it: report builder (and AI generator), measures/dimensions/filters/charts, dashboards with sharing and public link, goals, export. Prior art (Orgpuls ≤0206): `kpi_daily`, `growth_*`; routes `/admin/growth/funnel`, `/admin/web/goals` | INS-01..10 | Insights.dc.html |
| UF-13 · 1 Create report by type or AI request | Missing | E0 | AI part waits for the gateway (Part G:2546) | INS-01, INS-09 | Insights.dc.html (Report builder, Ask for a report) |
| UF-13 · 2 Measure, dimensions, filters, chart type | Missing | E0 | — | INS-01, INS-02, INS-07, SF-14 | Insights.dc.html (Report builder) |
| UF-13 · 3 Add to dashboard, arrange, share with team or public link | Missing | E0 | Public link is a token surface (A7.9) | INS-03, INS-04 | Insights.dc.html (Dashboards; "Public" present) |
| UF-13 · 4 Goals for users or teams; track progress | Missing | E0 | — | INS-05 | Insights.dc.html (Goals) |
| UF-13 · 5 Export chart or rows | Missing | E0 | Formula neutralization (A7.6) | INS-08 · Settings: typed_reason | Insights.dc.html ("export" present) |
| **UF-14 Scoring and enrichment** (gate, phase 4) | Missing | E0 (no enrichment provider) | All of it: scoring models with preview and activation, scores on deals and feed, single and bulk enrichment, credits and top-up, score refresh. Prior art (Orgpuls ≤0206): route `/admin/crm/scoring`; `brreg_entities` (0143) as company data | PRO-03..06 | Feed.dc.html (Scoring models, Enrichment) |
| UF-14 · 1 Scoring model for a pipeline; criteria in three groups | Missing | E0 | — | PRO-03 · Settings: count_limits (score models) | Feed.dc.html (Scoring models) |
| UF-14 · 2 Preview on sample deals; activate | Missing | E0 | — | PRO-03 | Feed.dc.html ("preview" present) |
| UF-14 · 3 Scores on deals and in the feed filter | Missing | E0 | — | PRO-03, PRO-01, SF-12 | Feed.dc.html; Deals.dc.html (Deal score) |
| UF-14 · 4 Enrich one organization or up to 100 records in bulk | Missing | E0 | "up to 100" is a fixed number not in the register (Q3) | PRO-04, PRO-05, PRO-06, SF-11 · Settings: contact_rule (PRO-05) | Feed.dc.html (Enrichment; "100" present) |
| UF-14 · 5 Credit allowance set and short: refused; admin can buy top-up | Missing | E0 | Who buys in an internal admin (Q16) | PRO-06; ENT-03 (not in "Uses", Q14) · Settings: plan_gates | Feed.dc.html ("credit" present) |
| UF-14 · 6 Enriched fields update dependent scores | Missing | E0 | — | PRO-03, PRO-04, PRO-05 | Feed.dc.html |
| **UF-15 Security administration** (gate, phase 8) | Partial | Only step 2, partly: mandatory TOTP for every admin (`middleware.ts:43–45`, `0001:32–36`, `app/mfa/actions.ts:14–34`) | Steps 1, 3, 4, 5, 6 missing; step 2 partial. SEC-10 has no step. Prior art (Orgpuls ≤0206): `platform_admins` (0049), `admin_audit`; routes `/admin/audit`, `/admin/admins` | SEC-01..06, SEC-10, SEC-11 | Security.dc.html |
| UF-15 · 1 Security dashboard; work through the assessment | Missing | E0 | No login log, no dashboard | SEC-01, SF-27 | Security.dc.html (Security dashboard; "Assessment" present) |
| UF-15 · 2 Configure single sign-on; enforce two-factor | Partial | Met: a second factor is enforced for every admin, without exception: middleware sends any session below aal2 to `/mfa` (`middleware.ts:43–45`); `app.is_admin()` requires `aal = 'aal2'` (`0001:32–36`); TOTP enrol/verify (`app/mfa/actions.ts:14–34`); fails closed (`middleware.ts:22–26, 48–51`) | Not met: SSO (SAML, Google) and its admin fallback; email-code factor; account recovery; remembered login email; an admin-facing enforcement switch (enforcement is hard-wired on; a switch must not loosen it, R7 — Q6). No test of the aal2 gate | SEC-05, SEC-06 | Security.dc.html (SSO and two-factor; "Single sign-on", "enforce" present) |
| UF-15 · 3 Password, IP and time rules; preview affected; enforce | Missing | E0 | — | SEC-03 | Security.dc.html (Alerts and rules; "IP", "password" present); preview of affected users not found (Q22) |
| UF-15 · 4 Choose alerts and delivery | Missing | E0; no email provider | — | SEC-02 | Security.dc.html (Alerts and rules); digest not found (Q22) |
| UF-15 · 5 On alert: check login history, log the device out | Missing | E0. Only self sign-out exists: `signOut({ scope: 'local' })` (`app/login/actions.ts:22–25`) | No login history, no remote log-out | SEC-04 | Security.dc.html (Device and login history; "Log out of all devices") |
| UF-15 · 6 Privacy request: export or erase the person's data | Missing | E0 | No export/erasure across modules | SEC-11, SF-15 | Security.dc.html (Privacy compliance; "Erase from every module") |
| **UF-16 Connect systems** (gate, phase 8) | Missing | E0 for every CRM part. Present but different: signed inbound product events (`supabase/functions/orgpuls-events/index.ts`) and signed outbound product commands (`supabase/functions/product-command/index.ts`, `_shared/signing.ts`) — platform-to-product plumbing, not a public API, OAuth app, webhook subscription or catalog | All of it: Google/Microsoft connections, API tokens and OAuth apps with reference, webhook subscriptions with ban policy, integration catalog, AI connector switch. Prior art (Orgpuls ≤0206): `event_catalogue`, `product_events` (product side) | INT-01..11, MCP-01..03, AIA-06 | Platform.dc.html |
| UF-16 · 1 Connect Google or Microsoft for mail, calendar, contacts, files | Missing | E0 | Token storage at rest (A7.8; Q19) | INT-05, INT-06 (serving COM-02, ACT-09, CRM-04, DOC-03) | Platform.dc.html (Applications, Integration catalog) |
| UF-16 · 2 Create API token or register OAuth app; read API reference | Missing | E0. `product-command` signs 2-minute HS256 tokens for Orgpuls commands only (`_shared/signing.ts`; `_shared/orgpuls.ts:52`) | No developer API | INT-01, INT-02 | Platform.dc.html (REST API and tokens; "OAuth" present) |
| UF-16 · 3 Subscribe webhooks to events | Missing | E0 | Outbound webhooks absent; inbound product events only | INT-04, SF-23 · Settings: count_limits (webhooks per user) | Platform.dc.html (Webhooks) |
| UF-16 · 4 Failing endpoint banned then removed; visible in list | Missing | E0 | SSRF protection needed (A7.7) | INT-04 · Settings: safeguards | Platform.dc.html (Webhooks; "ban" present) |
| UF-16 · 5 Find integrations by search or recommendation; install; review access | Missing | E0 | — | INT-11, INT-10, AIA-06, SF-41 | Platform.dc.html (Integration catalog) |
| UF-16 · 6 Switch the AI connector on or off | Missing | E0 | Switch not in the register (Q14 note) | MCP-03 | Platform.dc.html (AI connector) |
| **UF-17 Send an email campaign** (gate, phase 6) | Missing | E0 (no sending provider, no marketing stream) | All of it: domain authentication, builder with previews, consent-filtered audience, send/schedule, bounce/unsubscribe/spam status, report and comparison. Prior art (Orgpuls ≤0206): `crm_campaigns`, `crm_sends`, `crm_segments`, `crm_suppression` (0055), `crm_senders` (0093), `mail_auth_checks`/`mail_auth_runs`, `mail_streams` (0144); routes `/admin/crm/campaigns`, `/admin/deliverability` | CMP-01..09 | Marketing.dc.html |
| UF-17 · 1 Authenticate sender domain; sending blocked until it passes | Missing | E0 | A hard block with no register setting (Q4) | CMP-08 | Marketing.dc.html (Deliverability; "domain" present) |
| UF-17 · 2 Build from template; preview desktop and mobile | Missing | E0 | HTML sanitization (A7.4) | CMP-01, CMP-02, SF-39 | Marketing.dc.html (Email builder) |
| UF-17 · 3 Audience by filter; only subscribed addresses counted | Missing | E0 | No consent/marketing status | CMP-03, CMP-04 | Marketing.dc.html (Audience and consent) |
| UF-17 · 4 Send now or schedule | Missing | E0 | — | CMP-05, SF-19 · Settings: plan_gates (subscriber allowance) | Marketing.dc.html (Campaigns) |
| UF-17 · 5 Bounces, unsubscribes, spam reports update status | Missing | E0 | — | CMP-04, CMP-08 | Marketing.dc.html ("unsubscrib" present) |
| UF-17 · 6 Campaign report; compare with earlier campaigns | Missing | E0 | — | CMP-06, CMP-09 | Marketing.dc.html ("compare" present) |
| **UF-18 Website visitor to lead** (gate, phase 5) | Missing | E0 (no public widget, no tracker) | All of it: widget with optional consent gating, chatbot per page, meeting/live-chat offer, rep claim within waiting time, lead with answers and tracking, web form alternative. Prior art (Orgpuls ≤0206): `web_events` (0050), `cms_*`, `consent_records` (0141); no chatbot found | LGN-01..05, LEA-01, AUT-11, COM-10 | Marketing.dc.html (Chatbot and live chat, Web forms) |
| UF-18 · 1 Widget loads; by consent if consent-gated loading is on | Missing | E0 | Must never load in the survey flow (R6; Q15) | LGN-05 · Settings: widget_consent | Marketing.dc.html (Chatbot and live chat) |
| UF-18 · 2 Chatbot asks its questions for that page | Missing | E0 | — | LGN-01 | Marketing.dc.html |
| UF-18 · 3 Qualified: bot offers a meeting slot or live chat | Missing | E0 | — | LGN-01, LGN-02, COM-10 | Marketing.dc.html; Activities.dc.html |
| UF-18 · 4 Rep online claims within waiting time, else bot continues | Missing | E0 | — | LGN-02, SF-30 | Marketing.dc.html ("live chat" present); waiting time/claim not found (Q5, Q22) |
| UF-18 · 5 Lead created with answers, source, tracking; assigned by rule | Missing | E0 | — | LGN-01, LGN-02, LEA-01, LEA-04, CRM-15, AUT-11, SF-17 · Settings: form_tracking | Marketing.dc.html; Contacts.dc.html (Leads) |
| UF-18 · 6 Or a web form creates the lead the same way | Missing | E0. Note: Orgpuls site forms already emit `contact.submitted`/`demo.requested`, stored raw only (`0001:201–204, 261–262`) | No form builder, no lead (Q13) | LGN-03, LEA-01, SF-17 · Settings: form_tracking | Marketing.dc.html (Web forms) |
| **UF-19 Identify web visitors** (gate, phase 5) | Missing | E0 | All of it: tracker, company identification, ranked visitor inbox with filters and history, existing-record match, convert and prospect search. Prior art (Orgpuls ≤0206): `web_events` (0050); routes `/admin/web`, `/admin/web/pages` | WEB-01..04, LGN-04 | Marketing.dc.html (Web visitors) |
| UF-19 · 1 Admin installs the tracker | Missing | E0 | Flow actor is "sales rep" but this step is the admin's (Q15) | WEB-01, SF-18 · Settings: web_ident | Marketing.dc.html (Web visitors) |
| UF-19 · 2 Visiting companies in the visitor inbox, ranked | Missing | E0 | — | WEB-02, WEB-03 | Marketing.dc.html (Web visitors) |
| UF-19 · 3 Filter by country, campaign, page; open visit history | Missing | E0 | — | WEB-03 | Marketing.dc.html |
| UF-19 · 4 Company already in CRM: existing record shown | Missing | E0 | — | WEB-04 | Marketing.dc.html |
| UF-19 · 5 Else convert to lead/organization; prospect search for contacts | Missing | E0 | — | WEB-04, LGN-04 · Settings: contact_rule | Marketing.dc.html (Web visitors, Prospect search) |
| **UF-20 Hand over a won deal to delivery** (gate, phase 6) | Missing | E0 | All of it: project from deal (template), drafted brief, timeline with dependencies, board with phase and health, AI summary, client status report, close. PRJ-08 has no step. Prior art (Orgpuls ≤0206): none found | PRJ-01..09, AUT-07 | Projects.dc.html |
| UF-20 · 1 Deal won; workflow or rep creates project, optionally from template | Missing | E0 | — | PRJ-02, PRJ-05, AUT-07; PIP-07 (not in "Uses", Q14) | Projects.dc.html (Templates); Deals.dc.html |
| UF-20 · 2 Brief drafted from the deal and reviewed | Missing | E0 | AI brief finishes in phase 7 (Part G:2546) | PRJ-02, SF-24 | Projects.dc.html |
| UF-20 · 3 Adjust tasks, owners, dates, dependencies on timeline | Missing | E0 | — | PRJ-03, PRJ-04 | Projects.dc.html (Timeline) |
| UF-20 · 4 Team works tasks; board shows phase and health | Missing | E0 | — | PRJ-01, PRJ-03, PRJ-06 | Projects.dc.html (Board; "health" present) |
| UF-20 · 5 Slipping: set health or request AI summary | Missing | E0 | — | PRJ-06 | Projects.dc.html |
| UF-20 · 6 Share status report with client; close project | Missing | E0 | External share is a token surface (A7.9) | PRJ-07, PRJ-09, SF-42 | Projects.dc.html (Reports) |
| **UF-21 Field visit on mobile** (gate, phase 8) | Missing | E0 (web app only; no mobile client) | All of it: focus view, nearby, offline, audio note, card scan, sync. MOB-04, MOB-07, MOB-08 have no step. Prior art (Orgpuls ≤0206): none | MOB-01..08, AIA-07 | Mobile.dc.html |
| UF-21 · 1 App opens on focus view; the day | Missing | E0 | Native or web app undecided (Q18) | MOB-02, SF-44 | Mobile.dc.html ("Focus") |
| UF-21 · 2 Nearby contacts around next meeting; navigate | Missing | E0 | — | MOB-03 | Mobile.dc.html ("Nearby") |
| UF-21 · 3 Offline: open deal, add notes | Missing | E0 | — | MOB-05 | Mobile.dc.html ("Offline") |
| UF-21 · 4 Audio note, business card scan, plan next activity | Missing | E0 | — | MOB-06, AIA-07; ACT-07 (not in "Uses", Q14) · Settings: contact_rule | Mobile.dc.html ("Audio note", "Scan") |
| UF-21 · 5 Changes sync when connection returns | Missing | E0 | — | MOB-05, SF-31 | Mobile.dc.html ("sync") |
| **UF-22 Work through an external AI assistant** (gate, phase 8) | Missing | E0 | All of it: MCP endpoint with OAuth, tool catalog, per-user permissions and API limits, company switch, changelog source. Prior art (Orgpuls ≤0206): none | MCP-01..03, INT-03 | Platform.dc.html (AI connector) |
| UF-22 · 1 Add connector in assistant; log in | Missing | E0 | — | MCP-01, INT-02 | Platform.dc.html (AI connector) |
| UF-22 · 2 Ask to find, create or update records | Missing | E0 | Tools must expose CRM data only (R6) | MCP-01, MCP-02 | Platform.dc.html |
| UF-22 · 3 Each call runs with user's permissions, counts against API limits | Missing | E0 | — | MCP-01, INT-03, SF-22 · Settings: api_rate | Platform.dc.html |
| UF-22 · 4 Connector switched off: connection refused | Missing | E0 | — | MCP-03 | Platform.dc.html |
| UF-22 · 5 Changes appear in changelog with connector as source | Missing | E0 | No changelog (SF-02) | MCP-01, PIP-04, SF-02 | Platform.dc.html ("source" present); Deals.dc.html (History) |
| **UF-23 Manage contacts and organizations** (gate, phase 1) | Partial | Only step 1, partly: organization and contact data exist (`app.accounts` `0001:58–64`, `app.account_products` `0001:66–77`, `app.members` `0001:97–109`), filled by `public.ingest_events` (`0001:214–257`) | Steps 2–7 missing; step 1 partial. Prior art (Orgpuls ≤0206): `crm_contacts` (0055), `crm_companies`, `crm_activities` (0056), `admin_org_notes` (0049), `tickets` (0051); routes `/admin/crm/contacts/[id]`, `/admin/orgs/[id]` | CRM-01..06, CRM-10, CRM-13, CRM-14 | Contacts.dc.html; Customers.dc.html |
| UF-23 · 1 Open an organization: its contacts, deals, tickets, activities, files | Partial | Met: an organization record (`app.accounts`: name, org_number) linked to product tenants (`app.account_products`) with the tenant's users as contacts (`app.members`: email, name, role; comment "contacts, never respondents" `0001:97`), created and updated from product events (`0001:214–257`) | Not met: nothing opens it — no route or RPC returns an account or its members (`public.platform_status` returns counts only, `0001:313–314`); no deals, tickets, activities or files; members exist only per product tenant (Q10); tickets have no Part C feature (Q9) | CRM-01; tickets (Appendix 2) | Contacts.dc.html (Organizations); Customers.dc.html (Overview, Users and roles, Tickets, Timeline) |
| UF-23 · 2 Add a contact; source and basis optional unless contact rule on | Missing | E0. `app.members` rows come only from `member.joined` events (`0001:249–254`) | No manual creation, no source/basis fields, no settings | CRM-01, CRM-15, SF-37 · Settings: contact_rule | Contacts.dc.html (People; contact rule present) |
| UF-23 · 3 Note, mention a colleague, attach a file | Missing | E0 (no storage bucket) | — | CRM-06, CRM-05, SF-33 | Contacts.dc.html |
| UF-23 · 4 Link parent organization; apply labels | Missing | E0 | — | CRM-13, CRM-14 | Contacts.dc.html ("parent" present) |
| UF-23 · 5 Timeline of no-contact in period; map of contacts near a place | Missing | E0 | — | CRM-02, CRM-03 | Contacts.dc.html (Timeline, Map) |
| UF-23 · 6 Contact sync with the address book | Missing | E0 | Provider connection lands in phase 2 (Part G:2544) | CRM-04, SF-29 · Settings: contact_rule | Contacts.dc.html ("sync" present) |
| UF-23 · 7 Export a filtered list; export is logged | Missing | E0. `app.audit` logs product commands only (`0001:136–145`, `public.record_command` `0001:271–276`) | No export, no read/export audit (Q20) | CRM-10 · Settings: typed_reason | Contacts.dc.html (Export; "logged" present) |
| **UF-24 Review and maintain the pipeline** (gate, phase 1) | Missing | E0 | All of it: search and saved filters, list view with inline edit, bulk edit, participants and followers, activity calendar with priorities, archive/closed/duplicate/restore, bulk-delete preview with optional approval. PIP-11 is in "Uses" but has no step here. Prior art (Orgpuls ≤0206): `crm_lists`, `crm_list_members` (0056), `crm_segments`; routes `/admin/crm/lists`, `/admin/crm/segments` | PIP-08..13, PIP-15, PIP-17, ACT-03, ACT-05, ACT-06 | Deals.dc.html; Activities.dc.html |
| UF-24 · 1 Search or apply a saved filter | Missing | E0 | — | PIP-12, SF-25 | Deals.dc.html |
| UF-24 · 2 List view: columns, sort, inline edit | Missing | E0 | — | PIP-10 | Deals.dc.html (List) |
| UF-24 · 3 Bulk edit owner or label; activity for all | Missing | E0 | — | PIP-10, ACT-06 | Deals.dc.html ("bulk" present); Activities.dc.html |
| UF-24 · 4 Add participants; follow a colleague's deal | Missing | E0 | — | PIP-08, PIP-09 | Deals.dc.html ("follow" present) |
| UF-24 · 5 Calendar: reschedule activities, set priorities | Missing | E0 | — | ACT-03, ACT-05 | Activities.dc.html (Calendar; "priority" present) |
| UF-24 · 6 Archive, show closed, duplicate, restore deleted | Missing | E0 | No soft delete (SF-15) | PIP-13, PIP-15, PIP-17, SF-35 | Deals.dc.html (Archive and restore) |
| UF-24 · 7 Bulk delete: preview; second-admin approval only if setting on | Missing | E0 | — | PIP-10, CRM-12 · Settings: second_admin | Deals.dc.html ("approv" present) |
| **UF-25 Calls, messages and shared inboxes** (gate, phase 2) | Missing | E0 (no telephony, messaging or mail provider) | All of it: click-to-call with logging, messaging inbox with notification, team inbox, mailbox choice/labels/archive, group email with optional consent filter, mail-client add-on and BCC. Prior art (Orgpuls ≤0206): `crm_suppression` (0055), `consent_records`/`consent_purposes` (0141), `crm_lists`; routes `/admin/crm/inbox`, `/admin/crm/consent` | COM-01, COM-03, COM-04, COM-07, COM-09, COM-12, COM-13, COM-14, LEA-06 | Inbox.dc.html |
| UF-25 · 1 Click a number; call via provider, logged with outcome and duration | Missing | E0 | — | COM-12, SF-28 | Inbox.dc.html ("call" present) |
| UF-25 · 2 Message arrives in messaging inbox; owner notified | Missing | E0. Orgpuls `support.requested` events are stored raw only (`0001:261–262`) | No messaging channel (Q13) | COM-13, LEA-06 | Inbox.dc.html ("messaging") |
| UF-25 · 3 Answer in a shared inbox; colleagues see the reply | Missing | E0 | — | COM-04 | Inbox.dc.html ("Shared") |
| UF-25 · 4 Pick sending mailbox; label and archive thread | Missing | E0 | — | COM-03, COM-09 | Inbox.dc.html |
| UF-25 · 5 One email to a list; all receive by default; consent setting filters and reports | Missing | E0 | No consent basis, no suppression list | COM-07 · Settings: sales_consent, count_limits (recipients) | Inbox.dc.html; suppression not found there (Q21) |
| UF-25 · 6 Add deal from mail-client side panel; else BCC address | Missing | E0 | — | COM-14, COM-01, SF-40 | Inbox.dc.html ("BCC drop-box", add-on) |
| **UF-26 Recurring revenue and forecast** (gate, phase 4) | Partial | Only step 5, partly: billing mirror `app.subscriptions` (`0001:80–95`) fed by `billing.changed` (`0001:236–248`) | Steps 1–4 missing; step 5 partial. Prior art (Orgpuls ≤0206): route `/admin/billing` over Orgpuls' own billing | CRM-08, PIP-11, INS-06 | Deals.dc.html; Insights.dc.html; Customers.dc.html (Billing) |
| UF-26 · 1 Add recurring product or installment plan to a deal | Missing | E0 | — | CRM-08, CRM-07 | Deals.dc.html ("installment" present; Products) |
| UF-26 · 2 Deal shows MRR, ARR, ACV, TCV | Missing | E0 | — | CRM-08, SF-32 | Deals.dc.html ("MRR" present) |
| UF-26 · 3 Forecast view; drag a deal to a later month | Missing | E0 | — | PIP-11 | Deals.dc.html (Forecast) |
| UF-26 · 4 Forecast reports by month from deals and recurring products | Missing | E0 | — | INS-06 | Insights.dc.html (Forecast) |
| UF-26 · 5 For existing Orgpuls customers recurring figures come from billing | Partial | Met: a per-tenant billing mirror exists — plan, billing_interval, trial/confirmed/free/cancel/deletion dates (`0001:80–95`), upserted newest-wins from `billing.changed` (`0001:236–248`) | Not met: no price, amount or currency column, so no MRR/ARR/ACV/TCV can be derived (Q11); no reader, no screen, no join to deals or forecast; no test | CRM-08 | Customers.dc.html (Billing; "MRR" present); Analytics.dc.html ("MRR") |
| **UF-27 Work with the AI assistant** (gate, phase 7) | Missing | E0 (no AI gateway, SF-24). Firewall precondition holds today: the platform stores no survey responses or respondents (`0001:9–10`; table list E0), but no firewall test exists (A8) | All of it: assistant with record citations, survey refusal, stalled-deal notifications with suggestions, accept-and-log, contact proposal for unknown sender. Prior art (Orgpuls ≤0206): none | AIA-01, AIA-02, PRO-07 | Sentral Admin.dc.html (Assistant, Notifications); Feed.dc.html |
| UF-27 · 1 Ask about deals or contacts; answer cites records | Missing | E0 | — | AIA-01, SF-24 | Sentral Admin.dc.html (Assistant) |
| UF-27 · 2 Survey-answer question refused; data outside reach | Missing | E0. Design text: "Survey responses and respondent identities are outside my reach…" (Sentral Admin.dc.html) | No assistant; firewall not test-proven (R6, A8; Q12) | AIA-01 · Settings: firewall (fixed) | Sentral Admin.dc.html |
| UF-27 · 3 Notifications panel: stalled deals with suggested next step | Missing | E0 | — | AIA-02 | Sentral Admin.dc.html (Notifications); "stalled" found only in Inbox/Feed/Platform.dc.html |
| UF-27 · 4 Accept a suggestion; action runs and is logged | Missing | E0 | AI output written only on approval (A7.10) | AIA-02, SF-02 | Sentral Admin.dc.html |
| UF-27 · 5 Unknown sender: assistant proposes a contact; accept to create | Missing | E0 | — | PRO-07 · Settings: contact_rule | Sentral Admin.dc.html ("propos…" present); Inbox.dc.html |
| **UF-28 Plans and limits** (gate, phase 8) | Missing | E0. `app.usage_daily` (`0001:111–118`) is a product's per-tenant usage, not CRM consumption against limits | All of it: usage page against limits, refusal and waitlist at a limit, upgrade/top-up, waitlist release. Default is unlimited (plan_gates). Prior art (Orgpuls ≤0206): none | ENT-01..03, PIP-16 | Settings.dc.html (Plans and usage); Deals.dc.html |
| UF-28 · 1 Usage page: consumption against each limit | Missing | E0 | — | ENT-04 (not in "Uses", Q14), SF-16 · Settings: plan_gates | Settings.dc.html ("Usage against every limit") |
| UF-28 · 2 At a limit manual creation refused; automated lead/deal creation to waitlist | Missing | E0 | — | ENT-01, ENT-02, PIP-16 · Settings: plan_gates | Settings.dc.html:146 ("overflow goes to the waitlist"); Deals.dc.html ("waitlist") |
| UF-28 · 3 Upgrade plan or buy top-up; available at once | Missing | E0 | Purchase in an internal admin (Q16) | ENT-03 | Settings.dc.html (Entitlements "plan and add-on"); upgrade/top-up action not found (Q22) |
| UF-28 · 4 Add waitlisted deals back | Missing | E0 | — | PIP-16 | Deals.dc.html ("waitlist") |
| **UF-29 Set rules and limits** (gate, phase 1) | Missing | E0 (no settings registry, SF-34). `app.audit` records commands to products only (`0001:136–145`) | All of it: settings screen with every rule and default, switch on with warn/block, limits and plan gates, immediate effect logged with who/when, user sees which setting stopped an action, switch off restores. Prior art (Orgpuls ≤0206): `crm_settings` (0055); route `/admin/settings` | CUS-07, ENT-01, ENT-02 | Settings.dc.html (Rules and limits) |
| UF-29 · 1 Settings shows every rule with current value; all unrestricted by default | Missing | E0 | — | CUS-07, SF-34 · Settings: all 15 | Settings.dc.html (Rules and limits; "Default — unrestricted") |
| UF-29 · 2 Switch on a rule; pick warn or block where offered | Missing | E0 | — | CUS-07 · Settings: contact_rule, sales_consent (Off; Warn; Block) | Settings.dc.html (Rules and limits) |
| UF-29 · 3 Set a limit or plan gate if wanted | Missing | E0 | — | ENT-01, ENT-02 · Settings: count_limits, plan_gates, api_rate | Settings.dc.html (Rules and limits, Plans and usage) |
| UF-29 · 4 Applies at once; logged with who and when | Missing | E0. The only log is `app.audit` (actor, product NOT NULL, command matching `^[a-z]+\.[a-z_]+$`; `0001:136–145`), written only by `public.record_command` for product commands (`0001:271–276`) | No settings-change log (Q20) | CUS-07 | Settings.dc.html:35, 185–188 (rule log: when, who, what) |
| UF-29 · 5 A user hitting a rule sees which setting stopped the action | Missing | E0 | — | SF-34 | Settings.dc.html; none found on feature screens |
| UF-29 · 6 Switching the rule off restores full function | Missing | E0 | — | CUS-07 | Settings.dc.html |

### Questions and conflicts

1. **No end-to-end tool for the gate flows.** A8 requires an end-to-end test for every UF-01..UF-29, and A10/Part G close
   each phase only when its gate flows pass. The platform has vitest only (`package.json:12, 27–37`), `supabase/tests/`
   is empty, and there are no database tests. Which end-to-end tool (and database-test setup) should be added (R9 asks
   first)? Affects all 29 flows.
2. **Fixed "5 days" with no setting.** UF-04 step 7 (also PRO-01 at INSTRUCTIONS.md:978, SF-13 at :2042) fixes "no reply
   after 5 days". A9 says a source number is a reference value for a setting, but the CUS-07 register has no such row.
   Is it a setting (which key, default 5?) or a fixed product behaviour? Affects UF-04, UF-03.
3. **Fixed "up to 100 records".** UF-14 step 4 (Appendix 1:3159) caps bulk enrichment at 100; the register's count-limit
   row does not list PRO-06. Setting (default unlimited, or 100 as a safeguard?) or fixed? Affects UF-14.
4. **Hard sending block.** UF-17 step 1: "sending stays blocked until it passes" is an unconditional gate. R5 forbids a
   hard-coded gate; the register's technical safeguards row names only loop protection and the webhook policy. Should
   domain authentication be a register setting (and with what default), or is it accepted as fixed? Affects UF-17.
5. **Live-chat waiting time.** UF-18 step 4 depends on a "waiting time" (per chatbot in Appendix 1:3322). Is this a
   per-chatbot configuration field rather than a register setting? The design shows no waiting time. Affects UF-18.
6. **Two-factor enforcement vs the platform.** UF-15 step 2 / SEC-06 say "Admins can enforce it for everyone". The
   platform already enforces aal2 for every session and every admin RPC (`middleware.ts:43–45`, `0001:32–36`), and R7
   forbids loosening MFA. Should the enforcement switch be shown fixed-on, or omitted? SEC-06 also wants an email-code
   factor and recovery (platform: TOTP only, `app/mfa/actions.ts:14–23`). SSO (SEC-05) must still reach aal2 to pass
   `app.is_admin()`; is SSO with a second factor expected, or should SSO count as aal2? Affects UF-15, UF-22 (OAuth login).
7. **Staff roles.** The platform has `owner|admin` (`0001:20`); Appendix 2 (INSTRUCTIONS.md:1357) names super-admin,
   support, finance, read-only analyst; open point 10 adds sales, marketing and project roles; SEC-07 adds permission
   sets. Users are added only by SQL (no invite path, no email provider). Which model, and does `app.admins` become the
   user table (A6 "extend")? Affects UF-09, UF-12, UF-15, UF-24 (second admin), every flow's permission checks.
8. **No demo tenant / sandbox.** CUS-08 makes the sandbox the seeded demo tenant (INSTRUCTIONS.md:680–682) and R8 names
   Lumio AS / Kari Nordmann; the platform has no seed at all. Also, "nothing reaches the live company" must cover
   `product-command`, which can send `orgs.delete_now`, `billing.cancel` etc. to live Orgpuls
   (`_shared/orgpuls.ts:9–43`). Where does the seed live (this repo or Orgpuls), and how is a sandbox kept away from
   product commands? Affects UF-09 and every flow's verification (R8).
9. **Tickets in UF-23.** UF-23 step 1 shows an organization's tickets, but Part C has no ticket feature; tickets are in
   Appendix 2 and the design (Customers.dc.html Tickets tab, Tickets.dc.html). The platform has none; Orgpuls'
   `support.requested` events are stored raw (`0001:261–262`). Is ticketing (Appendix 2) a prerequisite of the phase 1
   gate, or is the tickets list dropped from UF-23 until it exists? Affects UF-23.
10. **Which table is "organization" and "contact".** A6 says extend existing tables. `app.accounts` is the company;
    `app.members` holds customer users keyed by (product, tenant_id, user_id) with an FK to a product tenant
    (`0001:97–109`). A CRM contact or prospect without a product tenant cannot live in `app.members`. Extend `members`,
    add a contacts table linked to `accounts`, or both? Affects UF-01, UF-18, UF-19, UF-23, UF-25.
11. **Billing mirror has no money.** UF-26 step 5 / CRM-08 take Orgpuls' recurring figures from billing, but
    `app.subscriptions` holds plan, interval and dates only (`0001:80–95`). Does Orgpuls' `billing.changed` carry an
    amount, or where do prices come from? Affects UF-26 (and INS-06 forecasts).
12. **Survey aggregate threshold.** Part G's firewall row (INSTRUCTIONS.md:2557) allows survey data only "as organization-level aggregates of at
    least 5 answers"; Orgpuls' own invariant is a database floor of 3 with default 5, and an organisation may choose 3–4
    after a warning (Orgpuls CLAUDE.md, invariant 1). The design's Customers.dc.html has a Surveys tab. Which threshold
    governs any survey figure in the admin, and does the platform show any survey aggregate at all (today it receives
    none: `0001:9–10`)? Affects UF-27 step 2, UF-23 step 1 (customer view), the firewall tests.
13. **Orgpuls inbound events as lead/message sources.** `contact.submitted`, `demo.requested` and `support.requested`
    arrive and are stored raw in `app.events_in` with no projection (`0001:201–204, 261–262`). Should they create leads
    (LEA-04 "web forms" channel), inbox messages or tickets, or are LGN web forms a separate build? Their payloads are a
    person's own words (`orgpuls-events/index.ts:10–11`), so A7.4 sanitization and A7.13 log rules apply. Affects UF-01,
    UF-18, UF-25.
14. **Flow headers vs steps.** Several steps use features missing from the flow's "Uses" line: UF-01 s1 (LGN-01, LGN-03,
    LGN-04, CRM-09) and s4 (COM-12); UF-02 s7 (AUT-02/AUT-07); UF-04 s7 (PRO-01); UF-05 s2 (AUT-07); UF-07 s6 and UF-21 s4
    (ACT-07); UF-14 s5 (ENT-03); UF-20 s1 (PIP-07); UF-28 s1 (ENT-04). Conversely, header features with no step: UF-07
    MTG-06, MTG-07; UF-09 CUS-04; UF-15 SEC-10; UF-16 INT-07, INT-08, INT-09; UF-17 CMP-07; UF-20 PRJ-08; UF-21 MOB-04,
    MOB-07, MOB-08; UF-24 PIP-11. Also UF-16 s6 / UF-22 s4 / MCP-03 is a company switch that is not in the CUS-07
    register. Should each flow's end-to-end test cover its header features or only its steps, and is the MCP switch a
    register setting? Affects the listed flows.
15. **Tracker placement and actor.** UF-19's actor is the sales rep, but step 1 is the admin installing the tracker. R6
    says the tracker and widgets never load in the survey flow: which site(s) get the tracker and widget (Orgpuls'
    marketing site only?), and how is the survey path excluded? Affects UF-18, UF-19.
16. **Buying plans and top-ups in an internal admin.** A1 says the admin is internal, not a tenant product, yet UF-28 s3
    and UF-14 s5 have the admin "upgrade the plan or buy a top-up". Who sells the CRM's plans to whom, and are enrichment
    credits the provider's credits? Affects UF-14, UF-28.
17. **Notifications and outbound mail.** UF-01 s2, UF-04 s5, UF-06 s3, UF-08 s4, UF-09 s4 (invite), UF-15 s4 need a
    notification channel and an email provider; the platform has none (open point 2). Affects those flows.
18. **Mobile and desktop clients.** UF-21 needs a mobile app (offline, card scan, push, Nearby) and UF-07 s2 a desktop
    recorder; the platform is a Next.js web app only. Native, PWA, or out of scope until decided (R9)? Affects UF-21,
    UF-07.
19. **Provider tokens at rest.** UF-16 s1, UF-06, UF-23 s6, UF-25 need per-user OAuth tokens. The platform's only secret
    store is Vault for product secrets (`0002_product_secrets.sql`). Reuse Vault for user tokens (A7.8 asks to use the
    existing mechanism)? Affects UF-04, UF-06, UF-16, UF-23, UF-25.
20. **Audit log shape.** UF-29 s4 (settings change who/when), UF-23 s7 (export logged), A7.11 (every write and read of
    customer data) need audit rows, but `app.audit` requires a `product` and a dotted `command` and is written only by
    `record_command` (`0001:136–145, 271–276`). Extend `app.audit` (and how is a CRM write's "product" filled — A6's
    product key) or add a CRM changelog beside it? Affects UF-23, UF-24, UF-27 s4, UF-29.
21. **Design gap: suppression in group email.** UF-25 s5 leaves out suppressed recipients when the consent setting is on;
    Inbox.dc.html shows no suppression list (grep: 0). Affects UF-25.
22. **Design gaps in other steps.** Not found in the design: booking-page time zone (Activities.dc.html, UF-06 s2);
    objection / remove-bot path (Meetings.dc.html, UF-07 s3); preview of affected users and alert digest
    (Security.dc.html, UF-15 s3–s4); live-chat waiting time and claim (Marketing.dc.html, UF-18 s4); upgrade / top-up
    action (Settings.dc.html, UF-28 s3); a "which setting stopped you" message on feature screens (UF-29 s5). Will the
    design be extended, or are these built in the existing design language without a reference? Affects the listed flows.

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
`PAGE` = `app/page.tsx` · `ACT` = `app/actions.ts`. Orgpuls prior art: `O:<migration>:<line>` at commit
`ced4af2` unless marked HEAD. Design files are in `design-reference/sentral/project/`; every SF flow is also
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

| Flow / step | Status | Evidence | Missing or different | Feature IDs it needs | Existing platform mechanism it can build on (path:line) or "none" | Design screen | Prior art (Orgpuls ≤0206) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **SF-01 Permission and visibility check** | Conflict | MW:98-140; M1:25-36, 156-166, 302-307; PC:83-114; OC:8-44 | Steps 2, 4, 5 missing; step 3 contradicts the repo's access pattern; steps 1, 6 partial. Settings: Typed reason for CRM actions; Plan gates and usage limits; Anonymity firewall (fixed) | SEC-07, SEC-08, CUS-03, ENT-01 | `app.is_admin()` M1:32-36; deny-all RLS M1:156-166; definer RPC gate M1:306-307 | Settings.dc.html; Security.dc.html | O:0049:24 `platform_admins`, O:0049:74 `app.is_platform_admin(roles[])` with roles super_admin/support/finance (+marketing O:0055), O:0049:79 `admin_audit` with `reason` |
| SF-01.1 Request authenticated, tied to staff user, role and product | Partial | MW:129-134 (session + aal2); M1:25-36 (`admins` row, confirmed email, aal2); M1:20 (`role owner/admin`); PC:95 (product fixed to `orgpuls`) | Met: authenticated, tied to a staff user (`app.admins`). Not met: role is stored (M1:20) but never read by any function (`is_admin` ignores it); UI reads (`platform_status` M1:302) are not tied to a product | SEC-07 | M1:25-36; MW:100-140 | — | — |
| SF-01.2 Permission sets decide whether the action is allowed | Missing | none | All of it: no permission sets; `is_admin()` is all-or-nothing. OC scopes (OC:8-44) are product-side scopes for commands, not staff permissions | SEC-07 | none (OC:8-44 is a per-command scope map that a permission model could mirror) | — | O:0049:74 role arrays per function |
| SF-01.3 RLS decides rows by visibility: owner, group, group+sub-groups, everyone | Conflict | M1:4-7, 156-166; CLAUDE.md rule 1 | Spec: RLS policies select rows by visibility. Repo: every `app` table has RLS on with **no policy and no client grant**; clients read only via SECURITY DEFINER functions that check `app.is_admin()` (CLAUDE.md rule 1). Visibility would have to live in definer functions, or the repo rule changes. No owner/group columns exist | SEC-08 | definer-RPC pattern M1:302-325 | — | Orgpuls used the same no-policy + definer pattern (O:0055 header l.34-36) |
| SF-01.4 Field rules hide fields and reject writes to read-only ones | Missing | none | All of it: no field registry, no field rules | CUS-01, CUS-03 | none | — | — |
| SF-01.5 Entitlement check where in use | Missing | none | All of it: no entitlements/registry (default "all on" would mean no check, but the check point does not exist) | ENT-01, CUS-07 | none | — | O:0142:133 `growth_plan_gates` (product plans, not staff entitlements) |
| SF-01.6 Refusal returns clear error and is logged; read of customer data writes audit row; typed reason only if setting on; survey tables unreachable | Partial | M1:306-307 (`not_allowed`); PC:84, 114 (401/403); EV:37-40; PC:141-148 + M1:271-276 (audit of every command that reaches the product, e.g. `orgs.list` from ACT:119); M1:9-10, 136-145; CLAUDE.md rule 6 | Met: refusals return a clear error code; a read of customer data **through a product command** writes `app.audit` (actor, command, arg names). Not met: refusals are not logged to the audit (PC returns 401/403 before `record_command`; EV only `console.error`); direct reads (`platform_status`) write no audit row; `app.audit` has no reason column and no setting exists. Firewall: structurally true today (no response table in the platform DB, M1:9-10; no key to Orgpuls' DB) but no test proves it (R6/A8) and whether every allow-listed command (OC:8-44) is response-free is decided in Orgpuls, not verifiable here | SEC-07, SEC-11, CUS-07 | `app.audit` + `record_command` M1:136-154, 271-278; append-only trigger M1:148-154 | — | O:0049:79-122 audit with optional reason; O:0049:363 required a ≥5-char reason (a hard-coded gate, contrary to R5) |
| **SF-02 Record change and event publication** | Missing | none for CRM records | All of it: no CRM records, no changelog, no outbound event table, no dispatcher. Inbound product events exist (`app.events_in`) and are a different direction | PIP-04, AUT-01–AUT-10, INT-04, INS-10 | `app.events_in` M1:122-133 (typed events table Part F says to extend); one-transaction projection M1:173-266 | Automation.dc.html; Deals.dc.html; Insights.dc.html; Platform.dc.html | O:0049:142 `product_events`; O:0141:71 `event_catalogue`; O:0141:126 `growth_events`; Orgpuls' live `platform_emit` + `orgpuls-dispatch` (Orgpuls 0205) is the producer pattern |
| SF-02.1 Change, changelog entry and event in one transaction | Missing | none | All of it. `ingest_events` writes event + projection in one function call (M1:173-266) but for inbound product events only; no changelog table | PIP-04 | M1:173-266 (single-transaction pattern) | — | — |
| SF-02.2 Dispatcher delivers new events to subscribers | Missing | M1:262 (`else null; -- a later reader decides`) | All of it: no dispatcher, no subscribers, no job runtime | AUT, INT-04, INS-10, PRO-01, SEC (notifications) | none (no scheduler in repo) | — | Orgpuls `orgpuls-dispatch` cron */5 (O:0032:292) |
| SF-02.3 Each subscriber processes an event once by ID | Missing | M1:131, 203 | All of it. Only receipt is idempotent (unique `(product, source_id)`), not per-subscriber processing | AUT, INT-04 | idempotent receipt M1:131, 201-208 | — | — |
| SF-02.4 Failing subscriber retries without blocking others | Missing | none | All of it | AUT, INT-04 | none | — | — |
| **SF-03 Email sync** | Missing | none | All of it: no mailbox connection, no mail tables, no provider. Settings: Email open and click tracking; Consent and suppression checks on sales email | COM-01–COM-09 | Vault-held secrets M2:27-65, SC:69-78 (encryption at rest per A7.8) | Inbox.dc.html | O:0051:209 `ticket_mail` (support mail, not sync) |
| SF-03.1 Mailbox authorized; tokens stored encrypted | Missing | none | All of it. Vault exists but `product_secret` / `store_product_secrets` accept only names matching `^[a-z][a-z0-9_]{1,30}_(token\|webhook)_secret$` (M2:43, 62) — product secrets, not per-user OAuth tokens | COM-01 | Vault M2:46-50, 58-63 | — | — |
| SF-03.2 History loaded back to chosen start date | Missing | none | All of it | COM-01 | none | — | — |
| SF-03.3 New mail by notification or polling, stored | Missing | none | All of it | COM-01, COM-02 | signed inbound endpoint pattern EV:20-57, SG:119-136 | — | — |
| SF-03.4 Senders/recipients matched to people; thread linked to open deal/lead or waits | Missing | none | All of it; `app.members` (M1:98-109) holds customer users' emails but there are no deals/leads | COM-03, CRM-01 | `app.members.email` M1:103 | — | — |
| SF-03.5 Outgoing mail sent with tracking, stored | Missing | none | All of it | COM-04, COM-06 | none | — | — |
| SF-03.6 Opens/clicks return as events, notify sender | Missing | none | All of it | COM-06, SF-07 | none | — | O:0056:241 `crm_clicks` |
| SF-03.7 Expired token / failed send: reconnect prompt or outbox reason | Missing | none | All of it | COM-01 | none | — | — |
| **SF-04 Workflow execution** | Missing | none | All of it. Settings: Count limits (actions and delays per path); Technical safeguards: workflow loop protection | AUT-01–AUT-10 | none (no scheduler, no outbound events) | Automation.dc.html | none found by table name |
| SF-04.1 Engine finds active workflows whose trigger matches | Missing | none | All of it | AUT-01, AUT-02, AUT-03 | none | — | — |
| SF-04.2 Conditions evaluated; failure ends silently | Missing | none | All of it | AUT-04 | none | — | — |
| SF-04.3 Run created; steps execute in order with owner's permissions | Missing | none | All of it; no per-user permission model to run as (see SF-01.2) | AUT-05, SEC-07 | PC:101-114 shows actor resolution (admin or `platform`) | — | — |
| SF-04.4 Delay schedules next step; wait-for stops after 7 days | Missing | none | All of it (7 days is a reference value for a setting per A9) | AUT-06 | none | — | — |
| SF-04.5 Branch picks one path | Missing | none | All of it | AUT-06 | none | — | — |
| SF-04.6 Step result written to run history | Missing | none | All of it | AUT-08 | none | — | — |
| SF-04.7 Failed action marks run failed, alerts owner; run counters stop loops | Missing | none | All of it | AUT-09, SF-07 | none | — | — |
| **SF-05 Sequence scheduler** | Missing | none | All of it. Settings: Consent and suppression checks on sales email (default Off) | AUT-12 | none | Automation.dc.html; Contacts.dc.html; Feed.dc.html | O:0055:95 `crm_suppression` (hashed addresses); O:0141:697 `consent_records`; O:0055:141 `crm_sends` |
| SF-05.1 First step time computed on enrollment, skipping weekends if set | Missing | none | All of it | AUT-12 | none | — | — |
| SF-05.2 Consent/suppression checked if setting on; then auto email, queued manual email, or activity | Missing | none | All of it | AUT-12, COM-07, ACT-01, PRO-01, CUS-07 | none | — | O:0055 header l.13-25 (basis per contact, suppression hashes) |
| SF-05.3 Next step scheduled | Missing | none | All of it | AUT-12 | none | — | — |
| SF-05.4 Reply or stage change ends enrollment | Missing | none | All of it | AUT-12, SF-03, SF-35 | none | — | — |
| SF-05.5 After last step completed; failed send marks failed | Missing | none | All of it | AUT-12 | none | — | — |
| **SF-06 Assignment engine** | Missing | none | All of it | AUT-11 | none | Automation.dc.html | O:0143:837 `app.lead_route()` (cron */5, O:0143:887; routes hand-raises and score ≥60 to a founder task); O:0118:14 `account_owners` |
| SF-06.1 Active rules for the event loaded in priority order | Missing | none | All of it | AUT-11 | none | — | — |
| SF-06.2 First matching rule chosen | Missing | none | All of it | AUT-11 | none | — | — |
| SF-06.3 Assignee resolved: user, team rotation, org owner, person's owner | Missing | none | All of it; no teams, no owners on `app.accounts` (M1:58-64) | AUT-11, SEC-09 | none | — | O:0118:14 |
| SF-06.4 Owner set, evaluation logged, new owner notified | Missing | none | All of it | AUT-11, SF-07 | none | — | — |
| SF-06.5 No match keeps owner | Missing | none | All of it | AUT-11 | none | — | — |
| **SF-07 Notifications and reminders** | Missing | none | All of it: no notification table, no email provider, no push | ACT-04, CRM-06, MOB-07 | none | Activities.dc.html; Contacts.dc.html; Mobile.dc.html | O:0135:141 `ticket_mentions` |
| SF-07.1 Source emits notification request | Missing | none | All of it | ACT-04, CRM-06 | none | — | — |
| SF-07.2 User's channel preferences applied | Missing | none | All of it | ACT-04 | none | — | — |
| SF-07.3 Delivered in app, by email or by push | Missing | none | All of it | ACT-04, MOB-07 | none | — | — |
| SF-07.4 Duplicates in short window merged | Missing | none | All of it | ACT-04 | none | — | — |
| **SF-08 Calendar sync** | Missing | none | All of it | ACT-08, ACT-09, COM-10 | Vault M2 for tokens | Activities.dc.html; Meetings.dc.html | none found |
| SF-08.1 User connects calendar, picks direction and activity types | Missing | none | All of it | ACT-09 | none | — | — |
| SF-08.2 Activity changes pushed to calendar | Missing | none | All of it | ACT-09 | none | — | — |
| SF-08.3 Calendar changes arrive by notification, update activities | Missing | none | All of it | ACT-09 | EV:20-57 (signed inbound endpoint pattern) | — | — |
| SF-08.4 Private events stored as busy time | Missing | none | All of it | ACT-09 | none | — | — |
| SF-08.5 Conflicts resolve to latest change | Missing | none | All of it | ACT-09 | last-write-wins guard M1:248, 254, 257 | — | — |
| **SF-09 Import pipeline** | Missing | none | All of it. Settings: Consent source on import; Plan gates and usage limits (capacity) | CRM-09, AIA-05, ENT-04 | none (no storage bucket) | Contacts.dc.html; Settings.dc.html | O:0055 header l.9-12 (import naming consent source per row) |
| SF-09.1 File parsed, column mapping suggested | Missing | none | All of it | CRM-09, AIA-05 | none | — | — |
| SF-09.2 User confirms mapping and duplicate rule | Missing | none | All of it | CRM-09, CRM-11 | none | — | — |
| SF-09.3 Rows validated; capacity checked | Missing | none | All of it | CRM-09, ENT-04 | zod at boundaries (RD:150, LOGIN:132) | — | — |
| SF-09.4 Valid rows written in batches tagged with import ID | Missing | none | All of it | CRM-09 | batch-of-500 ingest pattern M1:190-193 | — | — |
| SF-09.5 Rejected rows to skip file with reasons | Missing | none | All of it | CRM-09 | none | — | — |
| SF-09.6 History records counts; revert by import ID | Missing | none | All of it | CRM-09, CRM-12 | none | — | — |
| **SF-10 Duplicate detection and merge** | Partial | M1:214-223 | Only step 1 partly met (organizations arriving from a product are matched by org number). Settings: Second-admin approval for bulk deletes and merges (default Off) | CRM-11 | M1:216 (match by `org_number`, unique M1:61) | Contacts.dc.html | none found |
| SF-10.1 New people/orgs compared by configured matching rules | Partial | M1:214-223 | Met: an organisation a product names for the first time is matched to an existing `app.accounts` row by `org_number` before a new one is made. Not met: people are not compared; the rule is hard-coded, not configured; staff-created records do not exist | CRM-11 | M1:216-221 | — | — |
| SF-10.2 Matches listed as suggestions | Missing | none | All of it (the org-number match links automatically, no suggestion) | CRM-11 | none | — | — |
| SF-10.3 On merge user picks surviving values | Missing | none | All of it | CRM-11 | none | — | — |
| SF-10.4 Linked deals/activities/emails/files move; other record soft-deleted | Missing | none | All of it; no soft delete on `app.accounts` | CRM-11, CRM-12 | FK cascade from accounts M1:69 | — | — |
| **SF-11 Enrichment** | Missing | none | All of it. Settings: Contact rule (PRO-05, PRO-07); Plan gates and usage limits (credits) | PRO-04–PRO-07 | none | Feed.dc.html; Contacts.dc.html | O:0143:98-195 `brreg_*` (Brønnøysund settings, polls, entities, triggers, DNC, purges, outreach) |
| SF-11.1 Credit balance checked where allowance set | Missing | none | All of it | PRO-04, ENT-02 | none | — | — |
| SF-11.2 Provider adapter called | Missing | none | All of it; provider not chosen (open point 2) | PRO-04 | outbound fetch with timeout PC:126-139 | — | O:0143 brreg polling |
| SF-11.3 Returned values mapped to fields | Missing | none | All of it | PRO-04, CUS-01 | none | — | — |
| SF-11.4 Only empty fields written, with source and date | Missing | none | All of it (cf. `coalesce(a.org_number, …)` fill-if-empty M1:229, product events only) | PRO-04, CRM-15 | fill-if-empty pattern M1:229 | — | — |
| SF-11.5 Credits deducted; scoring re-run | Missing | none | All of it | PRO-04, PRO-03, SF-12 | none | — | — |
| SF-11.6 Provider error leaves record unchanged, no credit | Missing | none | All of it | PRO-04 | none | — | — |
| **SF-12 Scoring** | Missing | none | All of it. Settings: Count limits (score models) | PRO-03 | none | Feed.dc.html; Deals.dc.html | O:0143:835-836 score ≥60 routing (growth lead score) |
| SF-12.1 Active model for the deal's pipeline loaded | Missing | none | All of it | PRO-03, PIP-02 | none | — | — |
| SF-12.2 Each criterion evaluated, group points added | Missing | none | All of it | PRO-03 | none | — | — |
| SF-12.3 Total normalized to 0–100 | Missing | none | All of it | PRO-03 | none | — | — |
| SF-12.4 Score and matched criteria stored; score-changed event published | Missing | none | All of it | PRO-03, SF-02 | none | — | — |
| **SF-13 Feed generation** | Missing | none | All of it | PRO-01, PRO-02 | none | Feed.dc.html | none found |
| SF-13.1 Events (reply, open, click, new deal) create cards for owner | Missing | none | All of it | PRO-01 | none | — | — |
| SF-13.2 Scheduled checks create no-reply-5-days, no-follow-up, overdue cards | Missing | none | All of it (5 days = reference value for a setting) | PRO-01, SF-26 | none | — | — |
| SF-13.3 Card resolved when condition no longer holds or user acts | Missing | none | All of it | PRO-01 | none | — | — |
| SF-13.4 Daily counter updated | Missing | none | All of it | PRO-02 | none | — | — |
| **SF-14 Report query** | Missing | none | All of it | INS-01–INS-10 | aggregate definer RPC M1:302-325; `app.usage_daily` M1:111-118 (product usage rollup) | Insights.dc.html; Analytics.dc.html | O:0062:16 `kpi_daily`; O:0062:31 `marketing_spend` |
| SF-14.1 Report definition turned into a query | Missing | none | All of it | INS-01, INS-02 | none | — | — |
| SF-14.2 Query runs under viewer's visibility on live tables or rollups | Missing | none | All of it; no visibility model (SF-01.3) | INS-01, SEC-08 | M1:302-325 runs under `is_admin()` only | — | — |
| SF-14.3 Results cached per definition and scope | Missing | none | All of it | INS-01 | none | — | — |
| SF-14.4 Related events invalidate cache | Missing | none | All of it | INS-01, SF-02 | none | — | — |
| SF-14.5 Public link runs with owner's scope only | Missing | MW:98 | All of it. Only `/login` and `/ingen-tilgang` are public (MW:98); CLAUDE.md rule 2 requires a written reason for any new public path | INS-08 | none | — | — |
| **SF-15 Delete, restore and erasure** | Partial | M1:70, 74, 231-232 | Step 1 partly met for product-reported deletions only; steps 2-5 missing | CRM-12, SEC-11 | `account_products.status/deleted_at` M1:70-74; FK cascades M1:69, 94, 108, 117; `orgs.delete_now` OC:12 | Contacts.dc.html; Deals.dc.html; Security.dc.html | O:0064 `deletion_log` + `deletion_run` (product org deletion, cron O:0064:311); O:0055 header: suppression hashes outlive erased contacts |
| SF-15.1 Delete marks the row and records who, when, from where | Partial | M1:231-232 | Met: `app.account_products` is marked `status='deleted'` with `deleted_at` when the product reports `org.deleted`. Not met: no staff delete action, no who/from-where, no `deleted_at` on any other table | CRM-12 | M1:70-75, 231-232 | — | — |
| SF-15.2 Listed for restore for 30 days | Missing | none | All of it (30 days = reference value) | CRM-12 | none | — | — |
| SF-15.3 Restore brings back row and links | Missing | none | All of it | CRM-12 | none | — | — |
| SF-15.4 After 30 days a job removes it permanently | Missing | none | All of it; no job runtime | CRM-12, SF-26 | none | — | O:0064:311 cron |
| SF-15.5 Erasure removes a person from every module at once, logged | Missing | M1:122-133, 98-109 | All of it. Personal data today sits in `app.members` (email, name) and in raw `app.events_in.payload` (e.g. `contact.submitted` name/email/message, `member.joined`), with no erasure function and no retention | SEC-11 | `orgs.delete_now` OC:12 erases an org in Orgpuls, not a person in the platform | — | — |
| **SF-16 Entitlements and metering** | Missing | none | All of it. Settings: Plan gates and usage limits (default all on, unlimited) | ENT-01–ENT-04, PIP-16 | none (`app.subscriptions` M1:80-95 mirrors customers' product plans, not CRM entitlements) | Settings.dc.html; Deals.dc.html | O:0142:133 `growth_plan_gates` (product-side) |
| SF-16.1 Counter compared with limit if set; none by default | Missing | none | All of it | ENT-01 | none | — | — |
| SF-16.2 Under limit creation proceeds, counter rises | Missing | none | All of it | ENT-01 | none | — | — |
| SF-16.3 At limit manual creation refused with reason | Missing | none | All of it | ENT-01, SF-34 | none | — | — |
| SF-16.4 Automated lead/deal creation goes to waitlist | Missing | none | All of it | PIP-16 | none | — | — |
| SF-16.5 Usage page reads same counters | Missing | none | All of it | ENT-03 | `app.usage_daily` M1:111 (product usage, not CRM counters) | — | — |
| **SF-17 Lead capture from forms and chat** | Missing | M1:261-262; EV:50 | All of it in the platform. Contact submissions from Orgpuls' site arrive as `contact.submitted` events and are stored raw in `app.events_in`; nothing reads them (M1:210-212 skips projection when there is no tenant). Settings: Consent-gated loading of site widgets; Form tracking fields; Contact rule | LGN-01–LGN-05, LEA-04 | `app.events_in` + `contact.submitted`/`demo.requested` kinds (README:12; EV) | Marketing.dc.html; Contacts.dc.html | O:0051:282 `public.submit_contact` → ticket; O:0141:697 `consent_records`; Orgpuls HEAD 0206:400-431 now emits `contact.submitted` instead |
| SF-17.1 Widget loads (consent-gated if on); never in survey flow | Missing | none | All of it: no widget. "Never in the survey flow" is unprovable until a widget exists (R6 test required) | LGN-01, LGN-05 | none | — | — |
| SF-17.2 Submission validated and checked for spam | Missing | none in platform | All of it in the platform; only the HMAC of the batch is checked (EV:30-40). Orgpuls validates its own form (honeypot, length, 3/hour per address, 60/hour total) before emitting (Orgpuls HEAD 0206:411-426) | LGN-01 | EV:30-40 | — | O:0051:282 |
| SF-17.3 Contact and org found or created; source and consent recorded; admin's contact-form path (opens a ticket) reused | Missing | M1:261-262 | All of it. There is no contact-form path and no ticket table in the platform to reuse; see Questions | LGN-01, LEA-04, CRM-01, CRM-15 | `contact.submitted` in `app.events_in` M1:201-204 | — | O:0051:94 `tickets` |
| SF-17.4 Lead or deal created with answers, source, tracking data | Missing | none | All of it | LEA-04, LGN-03 | none | — | — |
| SF-17.5 Assignment runs, owner notified, workflows fire | Missing | none | All of it | AUT-11, SF-06, SF-07, SF-04 | none | — | — |
| SF-17.6 Resubmission updates existing record, keeps owner | Missing | none | All of it | LEA-04 | upsert pattern M1:250-254 | — | — |
| **SF-18 Web visitor identification** | Missing | M1:233-235 | All of it. `org.attribution` events fill `account_products.attribution` (signup attribution), which is not visitor identification. Settings: Web visitor identification (default On); Contact rule (WEB-04) | WEB-01–WEB-04 | `account_products.attribution` M1:72, 233-235 | Marketing.dc.html | O:0050:35 `web_events`; O:0050:54 `org_attribution` |
| SF-18.1 Tracker sends page, referrer, network address | Missing | none | All of it | WEB-01 | none | — | O:0050:35 |
| SF-18.2 Address matched to company through data source | Missing | none | All of it; provider undecided (open point 2) | WEB-01 | none | — | — |
| SF-18.3 ISPs, crawlers, unmatched dropped | Missing | none | All of it | WEB-01 | none | — | — |
| SF-18.4 Visit stored; monthly unique count and ranking updated | Missing | none | All of it | WEB-02 | none | — | — |
| SF-18.5 Visitor inbox refreshes hourly | Missing | none | All of it; no scheduler | WEB-03, SF-26 | none | — | — |
| **SF-19 Campaign send** | Missing | none | All of it: no campaigns, segments, sending provider or domain authentication check | CMP-03–CMP-08 | none | Marketing.dc.html | O:0055:103-141 `crm_segments`, `crm_campaigns`, `crm_sends`, `crm_suppression`; O:0056:241 `crm_clicks`; O:0093:70 `crm_senders`; O:0144:166 `mail_streams`; O:0144:252-267 `mail_auth_runs/checks` |
| SF-19.1 Audience filter resolved, reduced to subscribed addresses | Missing | none | All of it | CMP-03, CMP-05 | none | — | O:0055 header l.20-25 (mailable definition) |
| SF-19.2 Each email rendered with recipient data | Missing | none | All of it | CMP-01, CMP-03 | none | — | — |
| SF-19.3 Sent to provider on marketing stream | Missing | none | All of it | CMP-04 | none | — | O:0144:166 |
| SF-19.4 Provider events return (delivered…complaint) | Missing | none | All of it | CMP-06 | signed inbound endpoint pattern EV, SG:119-136 | — | — |
| SF-19.5 Events update campaign figures and address status | Missing | none | All of it | CMP-06, CMP-09 | none | — | — |
| SF-19.6 Unauthenticated domain or suspended account blocks send | Missing | none | All of it | CMP-07 | none | — | O:0144:252-267 SPF/DKIM/DMARC checks |
| **SF-20 Document and signature** | Missing | none | All of it: no storage, no drive connection, no signature. Settings: Count limits (signers) | DOC-01–DOC-06 | none | Documents.dc.html; Deals.dc.html | none found |
| SF-20.1 Template filled from deal, saved to connected drive | Missing | none | All of it | DOC-01, DOC-02 | none | — | — |
| SF-20.2 Share link created; opens logged and notified | Missing | none | All of it (public surface: A7.9 token) | DOC-03 | none | — | — |
| SF-20.3 Signature request emails link and one-time code | Missing | none | All of it | DOC-05 | one-time hashed nonce pattern M2:9-24, 35 | — | — |
| SF-20.4 Each signature recorded with time and address | Missing | none | All of it | DOC-05 | none | — | — |
| SF-20.5 All signed: PDF sealed with audit trail, stored on deal | Missing | none | All of it | DOC-05, DOC-06 | none | — | — |
| SF-20.6 Event published for workflows | Missing | none | All of it | DOC-06, SF-02 | none | — | — |
| **SF-21 Meeting intelligence pipeline** | Missing | none | All of it. Settings: Recording consent notices to attendees; Contact rule (MTG-05) | MTG-01–MTG-08 | none | Meetings.dc.html | none found |
| SF-21.1 Upcoming meetings read from calendar, linked to deals | Missing | none | All of it | MTG-01, SF-08 | none | — | — |
| SF-21.2 Brief generated from deal history, stored before meeting | Missing | none | All of it | MTG-01, SF-24 | none | — | — |
| SF-21.3 Bot joins or desktop app captures audio | Missing | none | All of it | MTG-02 | none | — | — |
| SF-21.4 Audio transcribed with speakers and timestamps | Missing | none | All of it | MTG-03 | none | — | — |
| SF-21.5 AI gateway produces recap and proposed field changes | Missing | none | All of it | MTG-04, MTG-05, SF-24 | none | — | — |
| SF-21.6 Recap saved as note and announced | Missing | none | All of it | MTG-04, CRM-06 | none | — | — |
| SF-21.7 Only approved changes written; failed transcription keeps recording | Missing | none | All of it | MTG-05 | none | — | — |
| **SF-22 API request and rate limiting** | Partial | PC:83-114 | Steps 1 and 4 partly met by the platform's one internal endpoint; no public CRM API, no OAuth, no rate limiting. Settings: API rate limits (default Off) | INT-01–INT-03, MCP-01 | PC:83-114 (bearer check), MW, size caps EV:22-25, PC:89 | Platform.dc.html | none (Orgpuls 0205 `platform_command` is the product side of the same channel) |
| SF-22.1 Token or OAuth grant verified | Partial | PC:83-114 | Met: `product-command` verifies its bearer (admin session via `admin_whoami`, or the service role key compared in constant time, PC:103). Not met: no API tokens or OAuth grants for external clients or connectors | INT-01, INT-02, MCP-01 | PC:101-114; SG:110-115 | — | — |
| SF-22.2 If rate limits on, burst limiter checks 2-second window | Missing | none | All of it (default Off means no limiter; the setting does not exist) | INT-03, CUS-07 | none | — | — |
| SF-22.3 With limits on, token cost deducted from daily budget | Missing | none | All of it | INT-03 | none | — | — |
| SF-22.4 SF-01 permission check runs | Partial | PC:110-114; M1:32-36 | Met to the extent of SF-01.1 (admin + aal2). Not met: permission sets, visibility (SF-01.2/3) | SEC-07 | M1:32-36 | — | — |
| SF-22.5 Handler responds with limit headers | Missing | none | All of it | INT-03 | none | — | — |
| SF-22.6 Over limit HTTP 429; admins emailed at 75%/100% | Missing | none | All of it; no email provider | INT-03, SF-07 | none | — | — |
| **SF-23 Webhook delivery** | Missing | none | All of it: no outbound webhooks. Settings: Technical safeguards: webhook retry and ban policy (default source values); Count limits (webhooks per user) | INT-04, AUT-07 | HMAC signing SG:100-107 (for signed payloads, an A4 decision); timeout pattern PC:134 | Platform.dc.html; Automation.dc.html | none found |
| SF-23.1 Matching subscriptions found | Missing | none | All of it | INT-04 | none | — | — |
| SF-23.2 Payload posted with 10-second timeout | Missing | none | All of it; no private/link-local address blocking exists (A7.7) | INT-04 | `AbortSignal.timeout` PC:134 | — | — |
| SF-23.3 Retried after 3, 30, 150 seconds | Missing | none | All of it; no job runtime | INT-04 | none | — | — |
| SF-23.4 Ten first-attempt failures ban for 30 minutes | Missing | none | All of it | INT-04 | none | — | — |
| SF-23.5 Three days without success deletes it, notifies owner | Missing | none | All of it | INT-04, SF-07 | none | — | — |
| **SF-24 AI gateway call** | Missing | none | All of it: no model provider, no AI code | AIA-01–AIA-05, MTG-01–MTG-08, PRJ-06, INS-09 | audit row pattern M1:271-276 | Sentral Admin.dc.html (Assistant panel); Feed.dc.html; Inbox.dc.html; Meetings.dc.html; Insights.dc.html; Projects.dc.html; Contacts.dc.html | none found |
| SF-24.1 Feature sends request with user and records in scope | Missing | none | All of it | AIA-01 | none | — | — |
| SF-24.2 Context retrieved under user's permissions, never from survey tables | Missing | none | All of it; firewall test required (R6) | AIA-01, SEC-07 | none | — | — |
| SF-24.3 Prompt sent to provider under no-training agreement | Missing | none | All of it; provider undecided (open point 2) | AIA-01 | none | — | — |
| SF-24.4 Output validated against expected structure | Missing | none | All of it | AIA-01 | zod validation pattern CMD:192, RD:150-171 | — | — |
| SF-24.5 Call logged with feature, user, cost | Missing | none | All of it | AIA-01 | M1:136-145 (audit columns lack feature/cost) | — | — |
| SF-24.6 Invalid output retried once, then error | Missing | none | All of it | AIA-01 | none | — | — |
| **SF-25 Search** | Missing | none | All of it: no search index (no `tsvector`/`pg_trgm` in M1/M2) | PIP-12 | none | Deals.dc.html; Sentral Admin.dc.html (search) | none found |
| SF-25.1 Each write updates index (name, emails, phones, text) | Missing | none | All of it | PIP-12 | none | — | — |
| SF-25.2 Query matched against index | Missing | none | All of it | PIP-12 | none | — | — |
| SF-25.3 Results filtered by role and visibility | Missing | none | All of it | PIP-12, SEC-08 | none | — | — |
| SF-25.4 Ranked and grouped by record type | Missing | none | All of it | PIP-12 | none | — | — |
| SF-25.5 Survey data never indexed | Missing | M1:9-10 | No index exists to check; structurally no survey data is in the platform DB (M1:9-10), but no test (R6) | PIP-12 | none | — | — |
| **SF-26 Scheduled checks** | Missing | none | All of it: no scheduler in the repo. PC:5 names "scheduled work: a nightly sync" as a service-role use, but no such job exists | PIP-05, AUT-03, INS-05, PRO-01 | service-role actor `platform` in PC:103-104 | Deals.dc.html (rotting); Automation.dc.html (rotting alert, date triggers); Feed.dc.html; Insights.dc.html | Orgpuls pg_cron jobs (e.g. O:0143:750, O:0143:887, O:0062:74) |
| SF-26.1 Scheduler starts each check at its interval | Missing | none | All of it; job runtime undecided (open point 3) | SF-26 | none | — | — |
| SF-26.2 Rotting check flags idle deals, notifies owners | Missing | none | All of it | PIP-05 | none | — | — |
| SF-26.3 Date-trigger check starts workflows | Missing | none | All of it | AUT-03 | none | — | — |
| SF-26.4 Goal check recomputes progress | Missing | none | All of it | INS-05 | none | — | — |
| SF-26.5 Feed check creates no-reply/no-follow-up cards | Missing | none | All of it | PRO-01 | none | — | — |
| SF-26.6 Each check records its run; failure raises alert | Missing | none | All of it | SF-07 | none | — | — |
| **SF-27 Sign-in and security events** | Partial | LOGIN:132-142; MFA:162-182; MW:129-134; M1:32-36 | Steps 1-2 partly met in code (no tests, not seen on screen); steps 3-6 missing | SEC-01–SEC-06 | `app.is_admin()` aal2 M1:35; MW:131-134 | Security.dc.html (SSO, IP allowlist, login history, new device) | O:0049:24 `platform_admins` with aal2 |
| SF-27.1 Sign in with password or single sign-on | Partial | LOGIN:135-142 | Met: password sign-in (zod-validated). Not met: single sign-on | SEC-01 | LOGIN:135-142 | — | — |
| SF-27.2 Second factor checked; mandatory in admin | Partial | MW:131-134; M1:35; MFA:162-182 | Met in code: every page but `/login` and `/ingen-tilgang` requires aal2 and fails closed; `is_admin()` requires aal2 in the database; TOTP enrol/verify. Not met for Implemented: no test covers it and it has not been seen on screen in this phase | SEC-02 | MW:100-140; M1:32-36 | — | — |
| SF-27.3 Security rules applied: IP allowlist, time window, password age | Missing | none | All of it. These are restrictions but are not in the CUS-07 register (see Questions) | SEC-03, SEC-04 | none | — | — |
| SF-27.4 Login written to login log with device and location | Missing | LOGIN:139-140 | All of it; failures return `failed` without a record. Whether Supabase Auth's own audit log can serve is Unknown (not in repo) | SEC-05 | none | — | — |
| SF-27.5 New device/location or repeated failures sends alert | Missing | none | All of it | SEC-05, SF-07 | none | — | — |
| SF-27.6 Security dashboard reads the same log | Missing | none | All of it | SEC-06 | none | — | — |
| **SF-28 Calls and messages** | Missing | none | All of it: no telephony or messaging adapter | COM-12, COM-13, MOB-04 | none | Inbox.dc.html; Mobile.dc.html | none found |
| SF-28.1 Click-to-call goes to telephony adapter | Missing | none | All of it | COM-12 | none | — | — |
| SF-28.2 Provider reports result; activity written with outcome, duration, recording | Missing | none | All of it | COM-12, ACT-01 | none | — | — |
| SF-28.3 Incoming number matched to contact | Missing | none | All of it | COM-12 | none | — | — |
| SF-28.4 Incoming message stored on thread, linked to open deal, owner notified | Missing | none | All of it | COM-13, SF-07 | none | — | — |
| SF-28.5 Unmatched number/sender listed for manual linking | Missing | none | All of it | COM-12, COM-13 | none | — | — |
| **SF-29 Contact sync** | Missing | none | All of it. Settings: Contact rule (default No rule) | CRM-04 | none | Contacts.dc.html | Not prior art: Orgpuls' Entra sync (O:0165:334) imports employees (respondent side) and must not be ported (R6) |
| SF-29.1 User connects address book, chooses what syncs | Missing | none | All of it | CRM-04 | Vault M2 for tokens | — | — |
| SF-29.2 Records matched by email | Missing | none | All of it | CRM-04 | none | — | — |
| SF-29.3 Change on one side updates the other | Missing | none | All of it | CRM-04 | none | — | — |
| SF-29.4 New external contact imported; contact rule if on | Missing | none | All of it | CRM-04, CUS-07 | none | — | — |
| **SF-30 Live chat routing** | Missing | none | All of it: no chat, no realtime | LGN-02 | none | Marketing.dc.html; Inbox.dc.html | none found |
| SF-30.1 Chat enters unassigned queue; online reps notified | Missing | none | All of it | LGN-02 | none | — | — |
| SF-30.2 First rep to claim gets it, locked to that rep | Missing | none | All of it | LGN-02 | none | — | — |
| SF-30.3 Nobody claims within waiting time: bot continues | Missing | none | All of it | LGN-02 | none | — | — |
| SF-30.4 Real-time delivery both directions | Missing | none | All of it | LGN-02 | none | — | — |
| SF-30.5 Transcript saved on the lead | Missing | none | All of it | LGN-02, LEA-01 | none | — | — |
| **SF-31 Mobile offline sync** | Missing | none | All of it: no mobile client, no changelog | MOB-05 | last-write-wins guard M1:248, 254, 257 | Mobile.dc.html | none found |
| SF-31.1 Offline changes queued on device with time | Missing | none | All of it | MOB-05 | none | — | — |
| SF-31.2 Sent in order on reconnect | Missing | none | All of it | MOB-05 | none | — | — |
| SF-31.3 Applied if unchanged; else latest wins, earlier kept in changelog | Missing | none | All of it; no version column, no changelog | MOB-05, SF-02 | M1:248, 254 (`updated_at <=` guard) | — | — |
| SF-31.4 Device pulls changes made elsewhere | Missing | none | All of it | MOB-05 | none | — | — |
| **SF-32 Derived values** | Missing | none | All of it | CRM-07, CRM-08, CUS-04, CUS-06, PIP-15 | none | Deals.dc.html; Settings.dc.html | none found |
| SF-32.1 Product line change recalculates deal value | Missing | none | All of it | CRM-07 | none | — | — |
| SF-32.2 Schedule change recalculates MRR, ARR, ACV, TCV | Missing | none | All of it (`app.subscriptions` M1:80-95 holds plan/interval, no amounts) | CRM-08 | none | — | — |
| SF-32.3 Formula input change recalculates formula field | Missing | none | All of it | CUS-04 | none | — | — |
| SF-32.4 Reports convert with stored exchange rate | Missing | none | All of it | CUS-06 | none | — | — |
| SF-32.5 Stage change closes previous stage time, opens next | Missing | none | All of it | PIP-15 | none | — | O:0137:36 `crm_stage_changes` |
| **SF-33 Files** | Missing | none | All of it: no storage bucket, no file table | CRM-05, DOC-03, MOB-06 | none | Contacts.dc.html; Deals.dc.html; Documents.dc.html; Mobile.dc.html | O:0124:21 `cms_media` (CMS media, not record files) |
| SF-33.1 Uploaded to storage under record's access rules | Missing | none | All of it | CRM-05 | none | — | — |
| SF-33.2 File row links to record and history | Missing | none | All of it | CRM-05 | none | — | — |
| SF-33.3 Download only if user may see the record | Missing | none | All of it | CRM-05, SEC-08 | none | — | — |
| SF-33.4 Deleting record soft-deletes its files | Missing | none | All of it | CRM-05, CRM-12 | none | — | — |
| **SF-34 Rule settings** | Partial | M1:9-10; CLAUDE.md rule 6 | Only step 6 partly met (the firewall is structural and has no switch). No registry exists | CUS-07, ENT-01, ENT-02 | `app.audit` M1:136-154 for logging changes | Settings.dc.html | O:0055:54 `crm_settings`; O:0142:34 `growth_settings` |
| SF-34.1 Feature asks registry for applicable rules | Missing | none | All of it | CUS-07 | none | — | — |
| SF-34.2 Default: no rule applies, action proceeds | Missing | none | All of it | CUS-07 | none | — | — |
| SF-34.3 Rule on: evaluated, returns allow/warn/block | Missing | none | All of it | CUS-07 | none | — | — |
| SF-34.4 Block names the setting | Missing | none | All of it | CUS-07 | none | — | — |
| SF-34.5 Every setting change logged | Missing | none | All of it; `app.audit.command` must match `^[a-z]+\.[a-z_]+$` and has no product-less form (M1:140-141) | CUS-07 | M1:136-154 | — | — |
| SF-34.6 Firewall not in registry, cannot be switched off | Partial | M1:9-10; CLAUDE.md rule 6 | Met: the platform DB holds no response-level table and nothing can switch that on. Not met: no database test proves it (R6, A8), and there is no registry yet to be absent from | CUS-07 | M1:9-10 | — | — |
| **SF-35 Deal lifecycle** | Missing | none | All of it: no deals, pipelines, stages | PIP-01, PIP-02, PIP-03, PIP-06, PIP-07, PIP-11, PIP-13, PIP-14, PIP-17 | none | Deals.dc.html | O:0093:33 `crm_stages`; O:0137:36 `crm_stage_changes`; O:0056:37 `crm_companies` |
| SF-35.1 Deal created in pipeline/stage with owner; quality rules checked | Missing | none | All of it | PIP-03, CUS-02 | none | — | — |
| SF-35.2 Stage move or forecast date change saved optimistically, stage history, event | Missing | none | All of it | PIP-01, PIP-11, SF-02 | none | — | O:0137:36 |
| SF-35.3 Deleting a stage moves deals to target | Missing | none | All of it | PIP-02 | none | — | — |
| SF-35.4 Won/lost stores status and lost reason | Missing | none | All of it | PIP-07 | none | — | — |
| SF-35.5 Archive removes from active views; unarchive returns | Missing | none | All of it | PIP-13 | none | — | — |
| SF-35.6 Duplicate copies fields and products; restore returns to former stage | Missing | none | All of it | PIP-17 | none | — | — |
| **SF-36 Activity lifecycle** | Missing | none | All of it: no activities | ACT-01, ACT-02, ACT-03, ACT-05, ACT-06, ACT-07 | none | Activities.dc.html | O:0056:69 `crm_activities` |
| SF-36.1 Activity created with type, owner, time, record; bulk creates one per record | Missing | none | All of it | ACT-01, ACT-06 | none | — | — |
| SF-36.2 Custom types and fields from registry | Missing | none | All of it | ACT-02, SF-38 | none | — | — |
| SF-36.3 Calendar reschedule updates activity and synced event | Missing | none | All of it | ACT-03, SF-08 | none | — | — |
| SF-36.4 Completing stamps time and user, publishes event | Missing | none | All of it | ACT-01, SF-02 | none | — | — |
| SF-36.5 No open activity: next-step prompt and warning icon | Missing | none | All of it | ACT-07 | none | — | — |
| **SF-37 Records, links and list operations** | Partial | M1:58-64, 98-109, 214-230, 249-257 | Step 1 partly met by product-event projection; steps 2-6 missing. Settings: Contact rule; Second-admin approval for bulk deletes and merges | CRM-01, CRM-02, CRM-03, CRM-10, CRM-13, CRM-14, CRM-15, PIP-08, PIP-09, PIP-10 | `app.accounts` M1:58; `app.members` M1:98; `ingest_events` M1:173-266 | Contacts.dc.html; Customers.dc.html; Deals.dc.html | O:0055:64 `crm_contacts`; O:0056:37 `crm_companies`; O:0056:105-136 `crm_lists`, `crm_list_members`; O:0049:126 `admin_org_notes`; O:0118:14 `account_owners` |
| SF-37.1 Person/org created or updated on admin's records with source stored | Partial | M1:214-230, 249-257, 66-76 | Met: organisations (`app.accounts`) and customer users (`app.members`, email/name/role) are created and updated from product events; the product and tenant that reported them are kept (`account_products`), and signup attribution in `attribution` jsonb. Not met: no staff create/update path; no person record beyond product members (no prospects); no source field per CUS/CRM-15 | CRM-01, CRM-15 | M1:58-76, 98-109, 214-257 | — | — |
| SF-37.2 Labels, related orgs, participants, followers stored as links; followers notified | Missing | none | All of it | CRM-13, CRM-14, PIP-08, PIP-09, SF-07 | none | — | — |
| SF-37.3 New address geocoded once for map | Missing | none | All of it; no address columns | CRM-03 | none | — | — |
| SF-37.4 Timeline built from activities and messages | Missing | none | All of it | CRM-02 | none | — | — |
| SF-37.5 Bulk edit one changelog entry per record; bulk delete preview | Missing | none | All of it | PIP-10 | none | — | — |
| SF-37.6 Export writes visible rows/columns to file, logged | Missing | none | All of it (formula neutralization A7.6) | CRM-10 | audit M1:136 | — | — |
| **SF-38 Field and configuration registry** | Partial | I18N:9-12; messages/no.json, messages/en.json | Step 4 partly met (interface text from message catalogs); steps 1-3, 5 missing | CUS-01, CUS-02, CUS-05, CUS-08 | next-intl I18N:9-12; `scripts/verify-i18n.mjs` | Settings.dc.html (demo tenant, Lumio) | Orgpuls demo sandboxes O:0094:772 (product-side) |
| SF-38.1 Field, quality rule or translation saved as versioned row | Missing | none | All of it | CUS-01, CUS-02, CUS-05 | none | — | — |
| SF-38.2 Forms, filters, reports, import, API read registry; no deploy | Missing | none | All of it | CUS-01 | none | — | — |
| SF-38.3 Quality rules evaluated on save and stage move | Missing | none | All of it | CUS-02, SF-35 | none | — | — |
| SF-38.4 Interface text served from translation catalog in user's language | Partial | I18N:9-12 | Met: every UI string comes from `messages/<lang>.json` (no, en), chosen per request. Not met: the language comes from a `lang` cookie, not a user profile; the catalog is files in the repo, not saved rows (step 1) | CUS-05 | I18N:9-12 | — | — |
| SF-38.5 Demo tenant has own config and sample data apart from live | Missing | none | All of it: no seed, no demo tenant (R8 names Lumio AS / Kari Nordmann; the design shows Lumio) | CUS-08 | none | — | — |
| **SF-39 Campaign authoring and insights** | Missing | none | All of it | CMP-01, CMP-02, CMP-09 | none | Marketing.dc.html; Insights.dc.html | O:0056:157 `crm_templates`; O:0055:116 `crm_campaigns` |
| SF-39.1 Builder saves rows and blocks; footer added automatically | Missing | none | All of it | CMP-01 | none | — | — |
| SF-39.2 Design saved to/loaded from template store | Missing | none | All of it | CMP-02 | none | — | O:0056:157 |
| SF-39.3 Test send and previews render same output as final | Missing | none | All of it | CMP-01 | none | — | — |
| SF-39.4 Provider events rolled up per campaign | Missing | none | All of it | CMP-09, SF-19 | none | — | — |
| SF-39.5 Insights reads rollups | Missing | none | All of it | CMP-09, INS-01 | none | — | — |
| **SF-40 Video links and mail client add-ons** | Missing | none | All of it | COM-11, COM-14 | none | Activities.dc.html; Inbox.dc.html | none found |
| SF-40.1 Video provider link stored on activity and invite | Missing | none | All of it | COM-11 | none | — | — |
| SF-40.2 Provider failure: activity saved without link, user told | Missing | none | All of it | COM-11 | none | — | — |
| SF-40.3 Add-on signs in as user, calls same API | Missing | none | All of it; no public API (SF-22) | COM-14, INT-01 | none | — | — |
| SF-40.4 Add-on records carry add-on as source | Missing | none | All of it | COM-14, CRM-15 | none | — | — |
| **SF-41 Connectors, app platform and AI connector tools** | Partial | M1:47-54, 302-324; PAGE:39-50, 88-101 | Step 2 partly met by the product-installation status; the rest missing | INT-05–INT-11, AIA-06, MCP-02, MCP-03 | `app.installations` M1:47-54 (`enabled` gate M1:187, 285); `platform_status` M1:302-325 | Platform.dc.html; Settings.dc.html | none found |
| SF-41.1 Install connector from catalog, grant scopes via OAuth | Missing | none | All of it; installations are SQL rows plus `secret-intake` (M2, SI), no catalog or OAuth | INT-05 | M1:47-54; per-command scopes OC:8-44 | — | — |
| SF-41.2 Connector status and error rate reported to admin's integrations status | Partial | M1:310-312, 322-324; PAGE:39-50, 88-101 | Met: the status page shows each installed product (enabled, host) and the last ten commands with ok/error. Not met: no error rate; applies to installed products, not catalog connectors | INT-05, INT-11 | M1:302-325; PAGE | — | — |
| SF-41.3 Deal events to team chat; invoice request to accounting adapter, status back | Missing | none | All of it | INT-06, INT-07 | none | — | — |
| SF-41.4 Extension panels in sandbox with scoped data | Missing | none | All of it | INT-08, INT-09 | none | — | — |
| SF-41.5 AI connector tools generated from API definitions; company switch blocks all | Missing | none | All of it | MCP-02, MCP-03, AIA-06 | none | — | — |
| SF-41.6 Removing connector revokes grants | Missing | M1:187, 285 | All of it for connectors. (Setting `installations.enabled=false` stops commands and events for a product, M1:187, 285 — a kill switch, not grant revocation) | INT-05 | M1:52, 187, 285 | — | — |
| **SF-42 Project lifecycle** | Missing | none | All of it | PRJ-01–PRJ-05, PRJ-07, PRJ-08, PRJ-09 | none | Projects.dc.html | none found |
| SF-42.1 Project from won deal or scratch, optional template dated from start | Missing | none | All of it | PRJ-01, PRJ-02 | none | — | — |
| SF-42.2 Tasks, subtasks, milestones, activities added, pasted or imported | Missing | none | All of it | PRJ-03 | none | — | — |
| SF-42.3 Dependency saved unless it forms a cycle | Missing | none | All of it | PRJ-04 | none | — | — |
| SF-42.4 Dragging phase shifts items keeping spacing | Missing | none | All of it | PRJ-05 | none | — | — |
| SF-42.5 Phase change publishes event | Missing | none | All of it | PRJ-07, SF-02 | none | — | — |
| SF-42.6 Notes, files, mentions, emails attach; status report PDF | Missing | none | All of it | PRJ-08, PRJ-09, SF-33 | none | — | — |
| **SF-43 User administration and data protection** | Partial | M1:18-23, 29; LOGIN:144-148; README:27-29 | Step 2 partly met; step 4 Unknown; steps 1, 3, 5 missing | SEC-09, SEC-10 | `app.admins` M1:18-23 (`active` read by `admin_email` M1:29) | Security.dc.html (backup, restore test); Settings.dc.html | O:0049:24 `platform_admins` |
| SF-43.1 Admin invites user, assigns role, team, visibility group | Missing | README:27-29 | All of it: users are created by hand in the Supabase dashboard and rows added to `app.admins` by SQL; role is owner/admin only; no team or visibility group | SEC-09 | M1:18-23 | — | — |
| SF-43.2 Deactivating ends sessions, prompts workflow transfer, reassigns records | Partial | M1:21, 29, 35 | Met: `active=false` makes `admin_email()`/`is_admin()` false, so every RPC and command is refused immediately. Not met: sessions are not ended (sign-out is `scope: 'local'` only, LOGIN:146); no transfer or reassignment; no UI | SEC-09 | M1:29 | — | — |
| SF-43.3 Access settings copied from another user | Missing | none | All of it | SEC-09 | none | — | — |
| SF-43.4 Backups run on schedule; last success recorded | Unknown | none in repo | Whether Supabase backups run for project `zuvqbaejoktpekfsiyyr` depends on its plan and is not visible from the repository. Recording the last success: missing | SEC-10 | none | — | — |
| SF-43.5 Restore test run and recorded against recovery targets | Missing | none | All of it; recovery targets not defined (Part G open) | SEC-10 | none | — | — |
| **SF-44 Mobile client** | Missing | none | All of it: no mobile app, no public API | MOB-01, MOB-02, MOB-03, MOB-08, AIA-07 | none | Mobile.dc.html | none found |
| SF-44.1 App signs in, loads focus view from same API | Missing | none | All of it | MOB-01, INT-01 | none | — | — |
| SF-44.2 Real-time changes while open | Missing | none | All of it | MOB-02 | none | — | — |
| SF-44.3 Nearby asks for location, queries by distance | Missing | none | All of it | MOB-03, CRM-03 | none | — | — |
| SF-44.4 Business card read on device as contact draft | Missing | none | All of it | AIA-07 | none | — | — |
| SF-44.5 Chat takeover, project tasks, statistics use same endpoints | Missing | none | All of it | MOB-08, LGN-02, PRJ-03 | none | — | — |
| **SF-45 Lead lifecycle** | Missing | none | All of it: no leads. `demo.requested` / `contact.submitted` events arrive and are stored raw (M1:261-262) but become nothing | LEA-01, LEA-02, LEA-03, LEA-05, LEA-06 | `app.events_in` M1:122-133 | Contacts.dc.html; Inbox.dc.html | O:0142:307 `growth_lead_sources`; O:0143:837 `lead_route` |
| SF-45.1 Lead created with source, linked to person or org | Missing | none | All of it | LEA-01, LEA-04 | none | — | — |
| SF-45.2 Labels and owner set, by hand or assignment rule | Missing | none | All of it | LEA-02, SF-06 | none | — | — |
| SF-45.3 Emails/messages stored on lead; connected-channel message arrives in inbox | Missing | none | All of it | LEA-05, LEA-06, SF-03, SF-28 | none | — | — |
| SF-45.4 Convert to deal in chosen pipeline/stage, moving notes, activities, emails, files | Missing | none | All of it | LEA-03, SF-35 | none | — | — |
| SF-45.5 Convert back returns to inbox with history | Missing | none | All of it | LEA-03 | none | — | — |
| SF-45.6 Archiving removes from inbox without deleting | Missing | none | All of it | LEA-01 | none | — | — |

### Questions and conflicts

1. **RLS visibility vs the repository's deny-all rule (SF-01.3, SF-14.2, SF-25.3, SF-33.3; SEC-08).** Part E
   says row-level security decides which rows a user sees (owner, group, sub-groups, everyone), and A6/A8 ask for
   explicit policies and per-role allow/deny tests. The repository's rule (CLAUDE.md rule 1; M1:4-7, 156-166) is
   RLS on, **no policy, no client grant**, every read through SECURITY DEFINER functions gated by `app.is_admin()`.
   Does visibility live in definer functions (repo pattern kept, "RLS" in the spec read loosely), or does the
   platform adopt policies for CRM tables (changing a security rule, which needs Tor's approval under R7)?
2. **Staff role model (SF-01.1-2, SF-04.3, SF-43.1, SF-43.3; SEC-07, SEC-09).** `app.admins.role` (owner|admin,
   M1:20) exists but no function reads it. Part E presumes permission sets, teams and visibility groups. Which
   roles or permission sets do sales, marketing and project users get (open point 10), and is the existing `role`
   column extended or replaced?
3. **"The admin's contact-form path, which also opens a ticket, is reused" (SF-17.3).** No such path exists in the
   platform: there is no ticket table and `contact.submitted` events are stored raw in `app.events_in` and never
   projected (M1:210-212, 261-262). In Orgpuls the path that opened a ticket (O:0051:282) was replaced in 0206 by
   `platform_emit('contact.submitted')`. Is the ticket path to be built in the platform first (Appendix 2's
   tickets), and is it the reader of `contact.submitted`?
4. **Rate limits outside the register (SF-17.2, SF-22; R5).** Orgpuls' `submit_contact` hard-codes 3 per hour per
   address and 60 per hour overall (Orgpuls HEAD 0206:421-426); the platform's events function hard-codes 1 MB and
   500 events per batch (EV:22-25, 48; M1:190) and `product-command` 200 kB / 50 args (PC:89, 96). R5 says every
   limit is a setting, A7.9 calls public-surface abuse protection a setting. Are these existing integration
   safeguards exempt (R7 "never weaken what exists"), or should they be registered? (The Orgpuls one is outside
   this repository.)
5. **Security rules missing from the register (SF-27.3; SEC-03/SEC-04).** IP allowlist, sign-in time window and
   password age restrict access but are not in "Settings managed in CUS-07". Per R5/A9 every restriction is a
   setting with an off default: add them to the register (default off)?
6. **Mandatory second factor vs "no restrictions" (SF-27.2; R5/R7).** SF-27.2 makes the second factor mandatory
   and the code enforces it (MW:131-134; M1:35). Confirm this is not a setting (R7 forbids weakening MFA), so it is
   a second fixed rule beside the anonymity firewall, contrary to A9's "the firewall is the one fixed rule".
7. **Erasure reach (SF-15.5; SEC-11).** Personal data today sits in `app.members` and in raw
   `app.events_in.payload` (contact form name/email/message, member events). `events_in` has no retention, and
   SF-15.5 says erasure removes a person "from every module". Must erasure rewrite or delete `events_in` payloads
   (a data rewrite, R8 needs approval), and what retention applies to raw events?
8. **Audit shape vs Part E logging (SF-01.6, SF-24.5, SF-34.5, SF-37.6).** `app.audit` (M1:136-145) is
   per-product command audit: `product` is required, `command` must match `^[a-z]+\.[a-z_]+$`, there is no reason,
   target record, feature or cost column. Part E needs audit rows for reads, refusals, setting changes, exports and
   AI calls. Extend `app.audit` (new nullable columns, relaxed product requirement) or add a second audit table
   (which A4.1 forbids for things that already exist)?
9. **Refusals are not audited today (SF-01.6).** `product-command` returns 401/403 before writing the audit
   (PC:84, 114); `platform_status` refuses silently (M1:306-307). Should the existing endpoints start logging
   refusals (a behaviour change to an existing feature, R7)?
10. **Which events table is "the typed events table" (SF-02; Part F).** `app.events_in` is inbound-only (unique
    `(product, source_id)`, `source_id` not null, M1:122-133). CRM record events have no product source id. Extend
    `events_in` (make `source_id` nullable / add a direction) or add an outbound table?
11. **Entitlements target (SF-16, SF-01.5; ENT-01–ENT-04).** `app.subscriptions` mirrors each customer's plan in a
    product (M1:80-95). Are ENT plan gates about the CRM's own staff usage, or about customers' product plans? The
    two would build on different tables.
12. **Demo tenant (SF-38.5; CUS-08; R8).** No seed or demo tenant exists in the platform. Orgpuls has its own demo
    organisations (sandboxes, O:0094) and sends their help requests without a tenant (Orgpuls HEAD 0206:464).
    Is the CRM "demo tenant" (Lumio AS / Kari Nordmann) a platform-side seed only?
13. **Backups (SF-43.4-5; SEC-10).** Backup schedule and restore tests for project `zuvqbaejoktpekfsiyyr` are not
    visible in the repository; recovery targets are unset (Part G). What plan and targets apply, and where is the
    "last success" read from?
14. **Login log source (SF-27.4-6; SEC-05/06).** Use Supabase Auth's own audit log (not visible from the repo) or a
    platform table written by the sign-in action? Device and location need a data source decision (open point 2).
15. **Job runtime (SF-02.2, SF-04, SF-05, SF-15.4, SF-18.5, SF-23.3, SF-26).** No scheduler exists in the platform
    (M1/M2 have no `cron.schedule`; PC:5 mentions a "nightly sync" that does not exist). Open point 3 blocks these.
16. **Firewall proof (SF-01.6, SF-17.1, SF-24.2, SF-25.5, SF-34.6; R6/A8).** The firewall is structural today (no
    response table in the platform DB, M1:9-10) but there are no database tests at all, and whether every
    allow-listed command in OC:8-44 returns only response-free data is decided in Orgpuls. What should the platform
    test prove: absence of response-level tables/columns here, and a contract test of command replies?
17. **Outbound webhook signing and SSRF guard (SF-23; A4.2, A7.7).** `SG:100-107` can sign payloads with HMAC; no
    private-address blocking exists anywhere. Sign outbound webhooks or not?
18. **Language source (SF-38.4; CUS-05).** The interface language is a `lang` cookie (I18N:11), not a user setting,
    and the catalog is repo files, while SF-38.1 asks for translations as versioned rows. Keep next-intl files for
    interface text and use rows only for CRM field labels, or move interface text to rows?
19. **Public paths (SF-14.5, SF-17.1, SF-20.2-3, SF-30).** Public dashboard links, form widgets, share and
    signature pages and live chat each need a public path. CLAUDE.md rule 2 requires a written reason per path,
    and MW:98 lists only two. Confirm these are approved in principle.
20. **Do not port Entra sync (SF-29).** Orgpuls' Entra import (O:0165:334) syncs employees, who are respondents. It
    must not be used as prior art for contact sync (R6). Recorded for Phase B.

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

#### 5. Questions (A12 says stop and ask; A11 format to be applied when raised)

1. **PIP-17 (I1):** Deal duplication has no source in the Appendix 1 research. Should it stay in scope as a design addition? If it stays, should the line 2725 justification be corrected so it no longer cites the Restore data row, which maps to CRM-12?
2. **Marketplace categories (M1):** Is mapping the nine categories to INT-05..09, COM-11, COM-12 and DOC-06 enough, given that Chatbots, Email marketing, Lead generation, Resource management and Task management have no connector spec? Or should Part H cite the first-party modules (COM-13, LGN, CMP, PRO/WEB, CRM-10/11, AUT-07) as the equivalents?
3. **Named app integrations (M2):** Are the connectors Pipedrive names (Zendesk, monday, Facebook Lead Ads, Livestorm, Mailchimp, PandaDoc, Stripe and others) meant to be built? Or are catalog entries (INT-11) plus automation-platform connectors (INT-09) the intended coverage?
4. **Hard-coded campaign rules against R5 (M8):** Should the non-removable footer (CMP-01), "only subscribed receive" (CMP-03) and "unauthenticated domain cannot send" (CMP-08) become settings in the CUS-07 register? Or are they fixed rules like the anonymity firewall? If fixed, A2 or Part C should say so explicitly.
5. **Languages (M7):** Which interface languages are in scope for CUS-05? Is Norwegian or Bokmål required, given the research lists 22 or 24 languages including Norwegian?
6. **Tailored setup (M6):** Is the sign-up questionnaire (company size, industry) and tailored setup part of CUS-08, or deliberately left out?
7. **Small omissions (M3, M4, M5, M9, M10, M11):** Should Part C add or confirm these?
   - Google Tasks sync (INT-05)
   - email address as an input to person enrichment (PRO-05)
   - a lead-conversion-status tool (MCP-02)
   - team filters in reports (INS-05 or SEC-09)
   - job title in reverse lookup (PRO-07)
   - participants on activities
8. **Part H bookkeeping (I2, I3, I4):** Should Part H be corrected?
   - count ENT-01 among the specs that cite no feature row (six, not five)
   - record UF-29 and SF-34 in the gap history
   - reword "four gaps" to match the eight-row table

#### 6. Issue count

**15 issues**: 4 in Part H's internal consistency (I1–I4) and 11 research-to-spec mismatches (M1–M11). By severity:
- **Medium (4):** I1, M1, M2, M8
- **Low to medium (2):** M6, M7
- **Low (9):** I2, I3, I4, M3, M4, M5, M9, M10, M11

There are no unmapped rows, no dangling IDs and no number gaps or duplicates in the 183 features, 29 user flows or 45 system flows.
