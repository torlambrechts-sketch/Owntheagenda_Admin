# Data-requirements spec: Customers and Contacts screens (Sentral admin)

Sources read in full: `Customers.dc.html` (521 lines), `Contacts.dc.html` (349 lines), `admin-data.js`, and `coverage-data.js` (CRM-01..15, LEA-01..05, CUS-01/07, SEC-*, ENT-*). Short labels used below: **EX** = existing column, **NEW** = new column or table, **DER** = derived, **PRV** = external provider, **FAB** = demo-only fabricated, with no real source.

Seeding facts that apply to everything: `admin-data.js` builds everything from a seeded PRNG. Its status, band, employees, health, MRR, lastSurvey, response, signup, labels, ehf and owner are all random. Nothing in it is real data.

---

## A. Customers screen

### A1. Views and states
- **Top tabs:** Organizations (count = number of orgs after the product filter), Users, Subscriptions and billing, Support access (count **2**, hard-coded, FAB), Personvern requests (count **4**, hard-coded, FAB). The shell's product switcher (`props.product`) narrows every tab to orgs that use that product.
- **Organizations, list view:** search, saved views, filters, a table with row checkboxes, and a bulk bar that shows when at least one row is selected. There is no header select-all and no sortable column. There is no empty state; a real build should use a "no organizations match" treatment.
- **Organizations, detail view:** back link, header card, Actions ▾ dropdown, and 8 sub-tabs (Overview, Users and roles, Surveys, Billing, Timeline, Tickets, Notes and tags, Audit trail). Tickets has an empty state: "No tickets from this organization."
- **Action modal:** reason textarea, an optional field, and a red warning on the delete action. Confirm is disabled until a reason is typed, and for delete until the typed org.nr matches.
- **Toast:** dark, auto-hides after 2.6 s, used for every action.
- **Users tab:** list plus a sticky detail panel. Billing, Support access and Personvern are single panels.

### A2. Organizations list: columns

| Column | Source |
|---|---|
| Name | EX `organizations.name` |
| Product chips | EX `account_products` via `organizations.account_id` |
| Label chips | EX `organizations.labels` → `labels` |
| Org.nr | EX `org_number` |
| Status (Trial / Active / Past due / Suspended / Cancelled) | DER from the subscription. Trial: `trial_end > now()` and `confirmed_at` is null. Past due: `payment_state = 'past_due'`. Cancelled: `cancelled_at` is set. Suspended needs **NEW** `account_products.suspended_at timestamptz`. The design shows one status per org (taken from Orgpuls), so a rollup rule is needed: either the primary product or the worst state. Log the choice. |
| Plan | DER `subscriptions.plan` → **NEW** `plan_versions.band_label` |
| Staff | Ambiguous. The design uses one number for Brreg-registered employees, "on the employee list" and band reconciliation. Keep two: EX `organizations.employees` (Brreg) and **NEW** `account_products.reported_headcount int` plus `reported_headcount_at` (a count sent by Orgpuls, which the hard rule allows). Show the product count here. |
| Last survey ("N d ago" / "Never"; red if over 90 days or never) | DER `now() − max(product_survey_rounds.sent_at)`. **NEW** table below. |
| Response ("—" if no survey) | DER `answered_count / delivered_count` of the latest closed round. The demo value is a random 54–93 (FAB). |
| Health (bar plus number; colour cut-offs ≥70 / ≥40) | **FAB.** Random by status (Past due 22–45, Suspended 10–25, Cancelled 5–20, otherwise 34–96; Lumio 82). Needs **NEW** `health_scores` and a defined formula (A3). |
| MRR ("—" if 0) | DER: sum of `subscriptions.price` normalised to a month (annual ÷ 12), excluding trial, cancelled and complimentary. The demo's other-product prices (×0.8, ×0.6, flat 190) are FAB. |
| Signup ("N d ago" / "N mo ago") | DER `min(account_products.created_at)`, or the trial start |

- **Summary line:** "N organizations · MRR X", DER over the filtered list.
- **Bulk bar:**
  - Add tag → `labels` array append.
  - Assign owner → `owner_id`.
  - Send broadcast → navigates to Campaigns, carrying the segment.

### A3. Detail view: header and Overview
- **Header line 1:** initials (DER), name, status, labels.
- **Header line 2:** "{orgnr} · {address} · NACE {nace} · {employees} employees registered". These map to EX `address`, `city`, `nace`, `employees`. In the demo, address, NACE and "synced N days ago" are FAB (computed from the row index modulo).
- **Header line 3:** "From Brønnøysundregistrene · synced {brreg_synced_at} · owner · CSM", from EX `brreg_synced_at`, `owner_id`, `csm_id`.
- **Product chips "name · state":** for products other than Orgpuls the state is hard-coded "Active" (FAB). Derive it per `account_products` row the same way as Status.
- **Health score breakdown** ("Feeds the org list and the CRM scoring model"). There are 5 parts, each value = health ± random 15 (FAB), and every subtitle is hard-coded (FAB):
  - "Daglig leder · 2 days ago" → needs **NEW** `members.last_login_at`.
  - "On plan · next pulse in 3 weeks" → **NEW** `product_survey_rounds.planned_at`.
  - "% · +4 since last" → DER from the last two rounds.
  - "6 open · 2 closed on time" → **NEW** `product_counts`.
  - "Paid on time / Failed 2 times" → `invoices`.
  - Proposed table: **NEW** `health_scores(organization_id, computed_at, score int, parts jsonb)`, computed nightly by a documented, deterministic formula over those five inputs. Until it exists, render nothing; do not render a number.
- **Activation:** 8 milestones. "Account created — Brønnøysund lookup ok", "Employee list uploaded", "First survey scheduled", "First survey sent", "Result unlocked (≥ 5 answers)", "Results viewed by daglig leder / HR", "First tiltak created", "Converted to paid". Which steps are done is FAB (8 for paid, otherwise 5 or 2), and so is "when" ("day 2i", "18 min after signup").
  - Proposed table: **NEW** `activation_milestones(account_product_id, key text, reached_at)`, filled from `events_in`.
  - Copy issue: "≥ 5 answers" should be the round's frozen k (3..10).
  - Copy issue: "HR" is not an Orgpuls role (the roles are daglig_leder, avdelingsleder, verneombud).
- **Structure:** Departments (3 + n%5) and Teams (6 + n%9) are FAB. "On employee list" maps to reported_headcount. "Groups below threshold" is random 1–3 (FAB).
  - Proposed table: **NEW** `product_counts(account_product_id, metric text, value int, as_of)`, holding departments, teams, groups_below_k, tiltak_open, tiltak_closed, tiltak_overdue. All are counts, which the hard rule allows.
  - Copy promise: "groups under 5 answers show as «—» here and in every export and support session". Change "5" to the organisation's k.
- **Cross-product view:** one row per product. The seat count (employees × 0.7) and the other-product MRR (price × 0.7) are FAB. Use `account_products.seats` and the per-subscription price. Promise: "Joined on org.nr — the shared customer key across applications", which requires `org_number` to be unique.
- **Tiltak and feedback:**
  - Open 6 / Closed 11 / Overdue 2 are constants (FAB); source them from `product_counts`.
  - "NPS (last 90 days)" (+20 + n%40) is FAB.
  - "In-app feedback" (n%6 + 2) is FAB.
  - Both need **NEW** `product_feedback(account_product_id, member_id, kind 'nps'|'feedback', score int null, created_at)`. This is customer admin users only, never respondents.
  - Promise: "Titles only with an active support-access grant".
- **CRM card:** deals for the org (title, "stage · status", value), linking to the Deals table (Deals screen). Contacts are `people` where `organization_id` matches, showing role (`title`), email and marketing status. "Open in Deals →" navigates there.

### A4. Users and roles
- **Columns:** User (name, email, "Billing contact" badge), Role, Last login, MFA, Auth, Invited by, then the action buttons.
- **All FAB.** The rows are CRM `people` plus invented names (Mona Lunde, Petter Aas…). Last login, MFA, auth and invited-by come from the row index; the invite state is pending only when `i === 3`. The roles include "HR" and "Tillitsvalgt".
- **Real source is `members`.** Needs **NEW** columns: `last_login_at`, `mfa_enabled bool`, `auth_method text`, `invited_by_member_id`, `invited_at`, `invite_state ('pending'|'accepted')`, `is_billing_contact bool`. All are reported by the product.
- **Actions** (product API commands, audited):
  - "Resend invite" / "Magic link" (the label depends on the invite state).
  - "Reset MFA" (toast: "they enrol again at next login").
  - "Deactivate".
- **Footer promise:** "Respondents are never listed — only counts and delivery status per survey."

### A5. Surveys
- **Banner promise:** "Metadata only. Answers and respondent identities are unreachable from the admin. Bounced addresses are fixed by the customer, not here."
- **Columns:** Survey, Type (Main / Pulse), Dates, Invited, Deliv., Bounced, Answered, Rate, Reminders ("count · +N answers").
- **All 4 rows FAB:** the names, the dates, invited = employees × 0.95, and the rest.
- **Proposed table:** **NEW** `product_survey_rounds(id, account_product_id, external_round_id text, name text, kind 'main'|'pulse', planned_at, opens_at, closes_at, invited_count, delivered_count, bounced_count, answered_count, reminders_sent int, answers_after_reminders int, updated_at)`. Whole-round counts only; never per department or group. Rate is DER.

### A6. Billing (per org)
- **Subscription rows:**
  - Plan ("band · price/month") and Applications are DER.
  - Next invoice: the trial wording "After trial · N days" is DER from `trial_end`. The paid wording uses a hard-coded "1 Nov 2026" plus MRR × 1.25 (FAB); use `next_invoice_at`.
  - Payment method: "Visa •••• 4242" is FAB. Use "EHF via PEPPOL" (from `organizations.ehf`) or **NEW** `subscriptions.pm_brand`, `pm_last4`.
  - Dunning: "Step 2 of 3 · retry 8 Oct" is FAB. Use **NEW** `subscriptions.dunning_step int`, `next_retry_at`.
  - Discount: needs **NEW** `subscriptions.discount_label`, `discount_ends_at`.
- **"Band crossed" flag:** triggers when employees > band max − 6, and the "shows {max+3}" figure is FAB. Use **NEW** `band_reconciliations` with the reported headcount. Copy promise: "The customer confirms before the price changes." The "Notify customer →" link sends an email and writes `notified_at`.
- **Invoices** ("Mirrored from Stripe · EHF via the accounting system"): number, date, description, amount (incl. MVA 25 %), status Paid / Sent / Failed. All 6 are FAB.
  - Proposed table: **NEW** `invoices(id, account_id, stripe_invoice_id, number, issued_at, description, amount_ex_vat numeric, vat numeric, total numeric, currency, channel 'card'|'ehf', status, attempt_count, next_attempt_at, pdf_url)`, filled by a **PRV** Stripe webhook.
  - Buttons: PDF (no handler in the design) opens `pdf_url`. Resend sends the invoice to the billing contact. Retry (only on failed invoices) is a Stripe retry.

### A7. Timeline, Tickets, Notes and tags, Audit trail
- **Timeline:** filter chips All / Activation / Billing / Support / Logins / CRM. The 6 events are hard-coded (FAB); admin actions are prepended. Real source: a union view over `events_in` (logins, activation), `audit`, tickets, `invoices` and plan changes, and CRM changelog / email tracking. Each event needs a `kind`.
- **Tickets:** id, subject, "type · category · channel", queue, priority, status. Click → Tickets screen. "＋ New ticket for {org}" → Tickets with `newFor`. Uses the tickets table from the Tickets screen.
- **Notes:**
  - Textarea promise: "@mention a colleague to notify them". Pinned notes. The 2 seed notes are FAB.
  - Proposed tables: **NEW** `notes(id, entity_type, entity_id, author_id, body, pinned bool, parent_id, created_at, deleted_at)` and `note_mentions(note_id, staff_id)` → `notifications`.
- **Tags:** 6 fixed toggles (Champion, Renewal Q4, Expansion, Pilot, Reference customer, Needs onboarding). Read them from `labels` filtered by scope `organization`; do not hard-code the list. Promise: "Tags work as segment filters in Campaigns and saved views."
- **Audit trail:** columns When / Who / Action / Reason. The 4 rows are FAB.
  - Needs `audit.reason text`, `audit.organization_id`, and `audit.kind 'write'|'read'`.
  - Footer promise: "Append-only · reads of customer-scoped data are logged too · retained longer than product data". That requires an immutability trigger, read logging in every customer-scoped read RPC, and a retention policy longer than product data.

### A8. Actions menu (every one needs a reason; writes `audit` and a timeline row; toast "· written to the audit log")

| Action | What it does in a real system | Rights |
|---|---|---|
| Extend or reset trial (days) | Product command to set `trial_end`; customer gets the "trial extended" email | Support, Sales, Super-admin |
| Change plan (band) | Stripe subscription schedule at the next period; "existing price version is kept until migrated" → `subscriptions.plan_version_id` | Finance, Super-admin |
| Apply discount | Stripe coupon on the subscription; shown on the next invoice | Finance, Super-admin |
| Mark as complimentary | **NEW** `subscriptions.complimentary bool`; excluded from MRR; adds the label "Complimentary" | Finance, Super-admin |
| Suspend / Reactivate | Product command; "Users keep read-only access to results. Scheduled sends pause." → `suspended_at` | Super-admin |
| Re-sync from Brønnøysund | **PRV** Brreg Enhetsregisteret API; "Differences are shown before saving" (needs a diff step); sets `brreg_synced_at` | Any staff with write access |
| Transfer ownership (e-mail) | Product command; "current owner becomes HR. Both receive an email." Use Orgpuls roles, not HR. | Support, Super-admin |
| Merge duplicate | "Same org.nr — preview first"; users, surveys and tickets move; the duplicate is soft-deleted for 30 days | Super-admin, plus second admin if that setting is on |
| Export organization data | "A ZIP with aggregates (n ≥ 5), tiltak and comments without identity". **Conflicts with the hard rule:** the platform holds no answers and no comments (they are respondent free text). It must be an Orgpuls-side export delivered to the customer, with the platform only logging that it was requested. Replace "n ≥ 5" with k. | Super-admin |
| Delete organization | "Super-admin only · scheduled with a 30-day grace period · soft-deleted until then"; confirm by typing the org.nr; confirmation is sent to the customer | Super-admin; second-admin approval if the setting is on |

### A9. Users tab (cross-org)
- **Search:** "Search users by e-mail or name across all organizations". The demo searches CRM `people` with type ≠ Prospect and truncates to 18 rows. The real source is `members`, grouped by `lower(email)`, across products.
- **Columns:** name / email, org, role, MFA, last login. MFA and last login are FAB (row index).
- **Detail panel:**
  - Memberships ("{role} · invited by {x} · {when}"): "Signup / Mar 2024" and the Bergheim "Board observer" row are FAB.
  - Facts: Last login "Today 09:12", MFA "Authenticator app", Auth "Magic link", Pending invites "None". All hard-coded (FAB).
- **Actions** (product commands, audited): Resend magic link, Reset MFA, Change e-mail, Mark as billing contact, Remove from org, Deactivate.

### A10. Subscriptions and billing (global)
- **KPIs:**
  - MRR: DER; copy says "Stripe is the source of truth".
  - Past due: DER as MRR × 1.25; better DER from the sum of open failed invoices.
  - Invoice (EHF): DER count, "organizations via PEPPOL".
  - **Refunds this month "1 590 kr / 2 refunds · 1 credit note" is FAB.** Source it from **NEW** `credit_notes` / `refunds` mirrored from Stripe.
- **Lifecycle bar:** DER counts per status, plus "Deleted (retention)" = **3, FAB**. Source that from `deletion_jobs`.
- **Failed payments and dunning** ("Retries day 1 · 3 · 7"): org, reason, amount, step, Retry. Reason and step cycle with the index (FAB). Use `invoices.failure_reason` (NEW) and `dunning_step`.
- **Band reconciliation** ("Employee list decides the band"): the −6 threshold, the "max+2+i" headcount and the states are FAB.
  - Proposed table: **NEW** `band_reconciliations(account_product_id, headcount, from_band, to_band, state 'not_notified'|'notified'|'awaiting'|'confirmed', notified_at, confirmed_at)`.
- **Plan catalogue** ("MVA 25 % · price changes create a new version"): annual = monthly × 10. "Includes N admins" and "v3/v2 · active" are FAB.
  - Proposed table: **NEW** `plan_versions(id, product_id, band_label, min_emp, max_emp, monthly_price, annual_price, includes jsonb, version int, active bool, valid_from)`, append-only.
- **Footer promise:** "No binding · verneombud and tillitsvalgte free · 30-day trial without card". The headcount used for the band must therefore exclude those roles.
- **Coupons:** the 4 rows (HMS2026 41 used, …) are FAB. Use **NEW** `coupons(code, description, kind, percent, months, stripe_coupon_id)` with redemptions counted.
- **Buttons:** "Export to accounting" → **PRV** accounting adapter, audited. "＋ New coupon" has no handler.

### A11. Support access
- **Header promise:** "Support access — instead of impersonation. Customer approves · time-boxed · read-only by default · every page view logged".
- **Rows** (org, reason, staff, approved by / requested at, state, expiry, page views): the 3 rows are FAB.
- **Request form:** organization, duration 24 h / 72 h, reason "(shown to the customer)", "Send request to customer".
- **Promise:** "The session inherits the role scope of the user being viewed and the 5-answer threshold. A banner shows in the customer's app while it is active." Replace "5" with k.
- **Proposed table:** **NEW** `support_access_grants(id, organization_id, account_product_id, staff_id, reason, duration interval, state 'pending'|'active'|'expired'|'revoked'|'denied', requested_at, approved_by_member_id, approved_at, expires_at, page_views int)`. The product approves the request and reports page views.

### A12. Personvern requests
- **Header promise:** "30-day clock · personvern tickets flow in here".
- **Rows** (PV-id, type, who, org, received, progress / days left, status, owner): the 4 rows are FAB.
- **Proposed table:** **NEW** `privacy_requests(id, ticket_id, type 'access'|'deletion'|'correction', requester_category text, organization_id null, received_at, due_at = received_at + 30 days, status, owner_id)`.
- **Hard rule:** requests about survey data (for example "Former employee (via employer)") go to Orgpuls. The platform stores a category, not the respondent's identity.
- **Deletion queue:** 3 rows FAB. "Raw responses 2023 · reduced to aggregates · 12 orgs" is a product-side job; the platform may only show the product's reported status.
  - Proposed table: **NEW** `deletion_jobs(id, target_type, target_ref, reason, scheduled_for, executed_at, state)`.
- **DPAs** ("Current version 3.1"): version and state follow the i%3 pattern (FAB).
  - Proposed tables: **NEW** `dpa_versions(version, published_at, current bool)` and `dpa_acceptances(organization_id, version, accepted_by_member_id, accepted_at, prompted_at)`.

### A13. Filters, saved views, search (list)
- **Search:** name substring, org.nr ignoring whitespace, and "admin e-mail". The demo matches `people.email`; the real match should be `members.email`.
- **Saved views and their rules:**

| Saved view | Rule | Note |
|---|---|---|
| All | — | |
| Trials expiring this week without a survey sent | Trial, ≤7 days left, no survey | |
| At risk before renewal | health < 40 and not cancelled | Ignores the renewal date. Needs `subscriptions.current_period_end` within N days. |
| Past due | status = Past due | |
| Multi-product | more than one product | |
| Invoice (EHF) customers | `ehf` | |

  Counts are per view. "Save view" only shows a toast in the design. Needs **NEW** `saved_views(id, staff_id null, screen, name, query jsonb, shared bool, position)`.
- **Filters:** Status, Price tier, Industry, Fylke, Signup source (EX `source`), Health bucket (<40 / 40–69 / 70+), Uses (product). "Clear filters".
- **Sort:** none is designed. Pick a minimal default (name) and log it.
- **Export CSV:** "formulas neutralized · logged" → audit, with the SEC-02 large-export alert.

---

## B. Contacts screen

### B1. Views and states
- **Tabs:** People, Organizations, Leads, Timeline, Map, Duplicates, Import, Export, Restore.
- **Header:**
  - Copy promise: "Two-way sync · Google Contacts · Microsoft 365" (**PRV**, CRM-04).
  - Add button whose label depends on the tab (＋ Person / Organization / Lead / New import). It only shows a toast, "form opened · contact rule: no rule (setting)". No form is designed, so log that.
- **Person drawer:** right side, 760 px.
- **Convert modal.**
- **Duplicates empty state:** "No duplicates waiting for review."
- **Toast.**

### B2. People
- **Search:** name, email, phone (whitespace-insensitive).
- **Filters:** Type, Marketing status, Label (Decision maker, Champion, Billing contact, Newsletter, VIP).
- **No sort and no pagination.**
- **Columns:**
  - Person: initials DER, name EX, labels EX.
  - Organization: EX `organization_id` → name.
  - Role: EX `title`.
  - Email: EX.
  - Type: EX `contact_type`. Should be kept in sync with the member link and subscription status (DER: Trial user / Customer user / Former customer).
  - Marketing status: Subscribed / No consent / Pending double opt-in / Unsubscribed / Bounced → **NEW** `people.marketing_status` enum plus `consent_events(person_id, status, source, basis, at, actor)`.
  - Source: EX.
  - Owner initials: EX `owner_id`.
- **Person drawer:**
  - Header: role · org · email · phone. "Synced with Google Contacts · two-way · last sync 4 min ago" is FAB. Needs **NEW** `contact_sync_links(person_id, provider, external_id, last_synced_at)`.
  - Label toggles, and facts (Type, Marketing, Source, Owner).
  - Notes with threaded comments and pins: the seed note is FAB; uses `notes`.
  - History: deals and activities are real joins. The email "Re: Forslag · opened 2× · clicked pricing" and the file "Kontrakt-utkast.pdf 212 kB" are FAB.
  - Footer promise: "Survey respondents never become contacts… marketing status changes are logged with time and source."

### B3. Organizations
- **List:** truncated to 30 rows in the demo.
- **Columns:** name, address (city, fylke), owner first name, People (DER count), Deals (DER count), Relation ("Daughter of X" / "Parent" / "—", DER from `parent_id`).
- **Side panel:**
  - "orgnr · industry · city".
  - Related organizations: the "Mørkved IT AS · Related · IT partner" row is FAB. Needs **NEW** `organization_relations(a_id, b_id, kind 'related', note)`; `parent_id` covers parent and daughter.
  - "Add as parent / daughter / related…" select (no handler).
  - People list.
  - "Open customer record →" → Customers detail.

### B4. Leads
- **The 10 seed leads are entirely FAB:** titles, values, labels, sources, the next-activity text and its colour.
- **Proposed tables:**
  - **NEW** `leads(id, title, person_id, organization_id, value numeric, currency, owner_id, source text, labels uuid[], archived_at, converted_deal_id, form_answers jsonb, created_at, deleted_at)`. A lead must have a person or an organization (CRM rule).
- **Next activity:** DER, the earliest open activity with the lead's id (`activities.lead_id`, NEW).
- **Filters:** label chips All / Hot / Warm / Cold, plus an Archive toggle.
- **Bulk actions:** Label Hot, Archive, "＋ Activity for each".
- **Detail panel:**
  - "id · source · created": "2 days ago" is FAB.
  - **Enriched company data:** "annual revenue ~employees × 1.4 MNOK" is a FAB formula. Use **PRV** Brreg / Proff enrichment, stored in **NEW** `organizations.enrichment jsonb`, `enriched_at`.
  - **Form / Chat answers:** the text is FAB. Use `leads.form_answers`.
  - **Emails on this lead:** 2 rows FAB. Use email-sync messages linked to the lead.
- **Actions:**
  - Convert to deal: modal with pipeline and stage. Promise: "Notes, emails, files and activities move to the deal. You will be asked to plan the next activity."
  - Email → Inbox.
  - "Not relevant → archive" → `archived_at`.

### B5. Timeline
- **Grid:** W37–W48 with a fixed "this week" column, first 10 people. Dot placement uses a modulo filter and "overdue" is a formula (FAB).
- **Real logic:** activities grouped by ISO week per person; overdue = `not done and due_at < now()`.
- **Promise:** "Same activities as each record's history".
- **Missing controls:** CRM-02 calls for look-back, frequency, type and owner controls; none are designed.

### B6. Map
- **Design:** placeholder tiles labelled "map tiles · provider adapter" (**PRV**, for example Kartverket/Geonorge or Mapbox). City coordinates are hard-coded and pins aggregate per city.
- **Real logic:** geocode once and cache. Needs **NEW** `organizations.lat`, `lon`, `geocoded_at`, and the same on `people`.
- **Controls:** Country (no handler), Region (fylke), mode Organizations / People. Copy: "N records plotted by address".
- **Missing:** the list of records without a usable address (CRM-03).

### B7. Duplicates
- **Rules:** Name similarity ≥ 90 %, Same email, Same org.nr, Same phone (off). Store in **NEW** `dedupe_rules(entity, rule, enabled)` or settings.
- **Copy:** "Second-admin approval for merges: off (setting)".
- **Pairs:** 2 FAB.
- **Proposed table:** **NEW** `duplicate_candidates(id, entity, keep_id, merge_id, rule, score, status 'open'|'merged'|'dismissed', decided_by, decided_at)`.
- **Buttons:** "Not a duplicate" and "Merge — keep combined history". CRM-11 also wants the user to pick the surviving values per field; the design does not show that.

### B8. Import (steps: Upload / Map fields / Duplicates / Result)
- **Upload:** "Drop .xlsx or .csv · up to 50 000 rows". The listed files are FAB. Checkbox: "Require a consent source per row (setting … is off)".
- **Map fields:** confidence % "Suggested by the assistant" (AIA-05). Mapping and confidence are FAB.
- **Duplicates:** "37 rows match existing records" is FAB. Modes: merge / create / skip.
- **Result:** Created 460, Merged 37, Skipped 11, Rows read 508. All FAB, and inconsistent in create mode (460 + 0 + 11 ≠ 508). Promise: "every row accounted for".
- **Result buttons:** "Download skip file" (no handler) and "Revert this import".
- **History:** 3 rows FAB.
- **Proposed tables:** **NEW** `imports(id, staff_id, files jsonb, mapping jsonb, dup_mode, require_consent bool, rows_read, created, merged, skipped, status, reverted_at)` and `import_rows(import_id, row_no, outcome, reason, entity, entity_id, before jsonb)`.

### B9. Export
- **Entities:** People, Organizations, Leads, Deals, Activities, Products.
- **Scope:** "Current list view" or "Full data set". Formats CSV and XLSX.
- **Promise:** "Contains exactly the rows and columns visible to you. Cells starting with = + − @ are neutralized. The export is written to the audit log." Needs the export permission (CRM-10) and the SEC-02 alert.

### B10. Restore
- **Deleted in the last 30 days:** "Purged automatically after 30 days". Columns: name, type, by (user / workflow / API token), when, source (Web app / Automation / Merge / API), Restore. Promise: "restored with links intact". 5 rows FAB.
- **Bulk changes — revertable:** 3 rows FAB.
- **Needs:**
  - **NEW** `deleted_at`, `deleted_by`, `deleted_via` on people, organizations, leads, deals, activities, files, products.
  - A purge job.
  - **NEW** `bulk_operations(id, actor, actor_kind, description, entity, count, created_at, reverted_at)`, with `changelog.bulk_op_id`.

---

## C. Rights (staff roles from the seed: Super-admin, Sales, Support, Finance, Marketing, Project, Read-only analyst)

| Role | Proposed rights |
|---|---|
| Read-only analyst | Read only |
| Sales | CRM writes |
| Support | User and product commands, support access |
| Finance | Plan, discount, complimentary, retry, coupons, accounting export |
| Super-admin | Suspend, delete, merge, org export |

- Imports, exports, merges and restores need the matching SEC-07 permission.
- The CRM "Typed reason" setting (default off) governs CRM writes. The Customers action modal requires a reason always.

## D. RPCs

**Reads:**
- `list_organizations(q, view, filters, product, sort, page)`
- `count_saved_views(product)`
- `get_organization(id)` (logs a read audit)
- `get_org_health(id)`, `get_org_activation(id)`, `get_org_counts(id)`
- `list_org_members(id)`, `list_org_survey_rounds(id)`, `get_org_billing(id)`, `list_org_invoices(id)`
- `list_org_timeline(id, kind)`, `list_org_tickets(id)`, `list_notes(entity, id)`, `list_org_audit(id)`
- `search_members(q)`, `get_member_identity(email)`
- `get_billing_overview(product)`, `list_failed_payments()`, `list_band_reconciliations()`, `list_plan_versions()`, `list_coupons()`
- `list_support_grants()`
- `list_privacy_requests()`, `list_deletion_jobs()`, `list_dpa_status()`
- `list_people(q, filters, page)`, `get_person(id)`, `list_crm_organizations(page)`, `get_crm_organization(id)`
- `list_leads(label, archived)`, `get_lead(id)`
- `contacts_timeline(from, weeks, filters)`, `map_points(mode, country, fylke)`
- `list_duplicate_candidates()`, `list_imports()`, `list_deleted_items()`, `list_bulk_operations()`

**Writes** (each takes `reason` where audited):
- `extend_trial`, `change_plan`, `apply_discount`, `set_complimentary`, `set_suspended`, `resync_brreg` (with preview and commit), `transfer_product_ownership`, `merge_organizations`, `request_org_export`, `schedule_org_deletion`
- `member_resend_invite`, `member_send_magic_link`, `member_reset_mfa`, `member_deactivate`, `member_change_email`, `member_set_billing_contact`, `member_remove_from_org`
- `notify_band_change`, `retry_invoice_payment`, `resend_invoice`, `export_to_accounting`, `create_coupon`
- `request_support_access`, `assign_privacy_request`
- `bulk_label_organizations`, `bulk_assign_owner`
- `add_note`, `toggle_label`, `save_view`, `log_export`
- `upsert_person`, `upsert_crm_organization`, `link_organizations`
- `upsert_lead`, `bulk_label_leads`, `archive_leads`, `bulk_create_activities`, `convert_lead_to_deal`
- `set_dedupe_rule`, `merge_records`, `dismiss_duplicate`
- `create_import`, `run_import`, `revert_import`
- `restore_item`, `revert_bulk_operation`

**Ingest** (service role): `ingest_product_counts`, `ingest_survey_round`, `ingest_member_state`, `ingest_milestone`, `stripe_webhook_sync`.

## E. Copy in the design that conflicts with the rules (fix before building)
1. **"Export organization data … comments without identity".** The platform must never hold respondent comments. Make it an Orgpuls-side export.
2. **"≥ 5 answers", "groups under 5", "the 5-answer threshold".** Use the organisation's k (3..10, frozen per round).
3. **"HR", "Tillitsvalgt", "Board observer" as product roles.** Orgpuls roles are daglig_leder, avdelingsleder, verneombud.
4. **Users tab built from CRM `people`.** It must read `members`; CRM contacts and product users are separate.
5. **"Raw responses 2023 reduced to aggregates"** is a product job. The platform shows only the status the product reports.
