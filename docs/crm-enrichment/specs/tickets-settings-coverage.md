# Data-requirements spec: Tickets, Settings and Coverage (Sentral prototype)

I read all three screens in full (markup and script), plus `admin-data.js`, `coverage-data.js`, Appendix 2 "Ticketing" in `docs/crm-enrichment/INSTRUCTIONS.md` (lines 4046–4092), the gap docs, DECISIONS.md and the existing migrations `0001`–`0008`.

The existing schema is richer than the brief suggests. Settings, modules, fields, staff, permission sets, groups, teams and sandbox already have public RPCs: `settings_get/setting_set/settings_log`, `modules_get/module_set`, `fields_get/field_save`, `staff_list/staff_save/staff_copy_access/staff_replace`, `access_model`, `permission_set_save`, `group_save`, `team_save`, `sandbox_set/sandbox_counts/sandbox_clear`, `profile_set`.

Labels used in the field tables below:
- **E** = existing
- **N** = new
- **D** = derived
- **P** = provider or product integration
- **F** = fabricated demo value with no real source

---

## 1. Tickets (`Tickets.dc.html`)

### 1.1 Views and states
- **Six tab pills:** Inbox · Problems and known errors · Help centre · Macros · Reports · SLA and routing. There is also a "＋ New ticket" button that opens a modal.
- **Inbox, queue chips with counts:** All open, My tickets, Unassigned, SLA at risk (the chip turns red when the count is above 0), Support, Billing, Sales, Personvern, Resolved and closed. The list has a filter input (matches subject, id and org name) and a sort control (SLA due / Priority / Newest). Selected row = yellow. A row in New status is bold.
  - Empty state: "Ingenting venter akkurat nå — no tickets in this view."
- **Detail panel:** header and controls, an impact × urgency block, SLA bars, the thread, a composer (Reply / Internal note mode, macro picker, Attach, @Mention, an after-send status select) and a side column. The side column shows Organization, Captured automatically and Links, plus three conditional panels:
  - Service request panel, when type = Service request.
  - Personvern panel, when category = Personvern request.
  - CSAT, when a score exists.
- **Modal:** New ticket, with a help-article suggestion box that appears once the subject is longer than 3 characters.
- **Toast:** 2.6 s.
- **Props:** `product` filters the whole list by the header product switcher. `focus.ticket` preselects a ticket. `focus.newFor` opens the modal (from the org detail).

### 1.2 Fields

| Shown | Source |
|---|---|
| Ticket id `T-2310` | N `tickets.number bigint identity`, shown as `'T-'‖number` |
| Type (Question, Service request, Incident, Problem) | N `tickets.type` |
| Category (9 values) | N `ticket_categories` (key, queue_key) |
| Status (New, Open, Waiting on customer, Waiting on us, Resolved, Closed) | N `tickets.status` |
| Queue (Support, Billing, Sales, Personvern) | N `tickets.queue_key`. Defaulted from the category routing; can be reassigned by hand. |
| Assignee | N `tickets.assignee_id → app.admins`. The picker lists staff whose role is Support, Super-admin, Finance or Sales. |
| Impact / Urgency | N `tickets.impact` (one_user, one_org, many_orgs) and `tickets.urgency` (not_blocking, blocking) |
| Priority pill | D `app.ticket_priority(impact, urgency)`: many_orgs + blocking → Urgent; many_orgs or blocking → High; one_org → Normal; otherwise Low. Store it as a generated column. Never set by hand. |
| Priority colour bar (list) | D from priority |
| List SLA text ("N h left", "Overdue N h", "Responded") | D `first_response_due_at − now()` in **business** time. The prototype uses wall-clock `frtTarget − ageH`. |
| SLA bar "First response · 4 h / 1 day / 2 days / 5 days" | D from `ticket_sla_policies` and `first_response_at` |
| "Met · 1 h 40 min" | **F**. The same string appears on every responded ticket. Real value: business time from `created_at` to `first_response_at`. |
| "Resolution · N business days", "N days left" | D. The prototype computes `resTarget − ceil(ageH/8)`, which mixes wall-clock hours with 8-hour days. Real value: `resolution_due_at` from the business calendar. |
| "opened N h/days ago" | D `created_at` |
| Channel (In-app help, Email, Contact form) | N `tickets.channel`. Staff-created tickets need a 4th value (`staff`), which the design does not show. |
| Product name | E `app.products`. N `tickets.product`. |
| Subject | N `tickets.subject` |
| Thread: who · kind · when · text · attachment | N `ticket_messages` (kind: customer, reply, note, system, admin_action), `ticket_attachments`. **F:** every thread except T-2310 is synthesised from the subject ("Hei, <subject>. … Vi er N ansatte …"), as are the canned replies and "skjermbilde.png · 182 kB". |
| System message "Auto-linked … E-mail log: 14 deferred, reason 451 greylisted" | **F** text. A real version needs (a) an auto-match rule, which the design does not specify, and (b) **P** the Orgpuls e-mail log, fetched by product command. |
| Organization: name, org.nr · band · employees, status pill, Health N, "Trial · N d left" / "Customer" | E `app.organizations` (name, org_number, employees). D status and trial days from `app.subscriptions` (trial_ends_at). D band from employees/plan. Health is D but not computed yet (D-21). |
| Person: name, role · email | E `app.people` (name, title, email). N `tickets.person_id`. |
| Captured automatically: Role, Page, Browser, App version, Channel | P from the `support.requested` payload, stored as N `tickets.context jsonb`. **F** in the demo: App version is the product's *current* version, not the version when the ticket was raised. Capture it at intake. |
| Links: Problem | N `tickets.problem_id` (self-FK) |
| Links: Survey "Baseline 2026 · metadata only" | **F** (hard-coded for every Survey delivery ticket). Real: N `ticket_links(kind='survey', ref)` holding metadata only (D-19). |
| Links: Invoice "INV-40171" | **F** (hard-coded for every Billing ticket). Real: N `ticket_links(kind='invoice')`. There is no invoice table yet (Stripe waits, D-22). |
| Links: Deal "New business · Qualified" | **F** (hard-coded for Sales tickets). Real: `ticket_links(kind='deal')` once deals exist. |
| Personvern panel "30-day clock — 24 days left" | "24" is **F**. D `privacy_requests.due_at − now()`. |
| CSAT "N / 5" | N `tickets.csat_score`, plus `csat_requested_at` and `csat_at` |

**Problems tab.** Both problem cards are hard-coded. They are tickets with type = Problem (T-2316, T-2329). Fields:
- Owner: N `tickets.owner_id` (the problem owner, as distinct from the assignee).
- Product.
- Root cause: N `root_cause text`.
- Status pill "Investigating / Resolved": N `problem_status` (investigating, known_error, resolved). This set does not exist in the ticket status list.
- Linked incidents: D, the tickets where `problem_id` = this problem.
- Known error and workaround: N `workaround text`.
- Toggles "Published to help centre" (N `help_articles.problem_id`) and "In-app status banner" (N `status_banner bool`, plus a **P** Orgpuls command that shows the banner).

**Help centre tab.**
- **Articles table** (title, category, views, deflected, updated, status): all six rows are **F**. Real: N `help_articles` and N `help_article_stats_daily`. Views and deflections are **P** count-only events from the Orgpuls help widget (to be added per D-40).
- **"Ticket-to-article rate 38 %"** and **"deflected 212 this month"**: **F**.
  - Rate: resolved tickets in the period linked to an article ÷ resolved tickets.
  - Deflected: sum of deflections.
- **"Close the loop"** (3 gaps, counts 6/5/4): **F**. Real: count tickets in the last 30 days per topic that has no published article. This needs a topic or tag on tickets (N `tickets.topic`), or clustering. The design names topics like "Two owners on one tiltak", which plain categories cannot produce.
- **Widget preview:** a naive 5-letter-prefix match over a hard-coded list. Real: full-text search (`to_tsvector('norwegian', …)`) over published articles.

**Macros tab.**
- Five macros, each with name, category, "used N times", version and body. Name, category, version and body are **F** seed content. The usage count is **F** too; the real count is the number of `ticket_messages.macro_id` rows.
- "Bokmål · version N · edited in Content management" → N `ticket_macros` + `ticket_macro_versions(locale nb|nn)`.
- Merge fields:
  - `[fornavn]` (person first name), `[organisasjon]`, `[orgnr]` and `[agent]` are D.
  - `[dato]` and `[dager]` come from service-request parameters.
  - `[domene]` and `[antall]` come from the **P** e-mail log.
  - The prototype replaces only `[fornavn]` and `[agent]`. Real behaviour: block sending while any placeholder is unresolved.

**Reports tab: every number is F.**
- KPIs: 312, +8 %, 2 h 10 min, 1,6 days, 94 %, 19 breaches, 4,2 %, −0,8, 4,7 / 5, 68 % response.
- Category bars: trial vs customer counts that sum to 262, not 312. The scaling uses a fixed 52.
- FRT medians: 2.1 / 4.5 / 7 / 18 h.

Real formulas:
- Count created in 30 days, versus the previous 30 days.
- Median business-time first response and median business-time resolution (`percentile_cont(0.5)`).
- SLA compliance = tickets that met both due times ÷ tickets due in the period. Breaches = the complement.
- Reopen rate = resolved tickets later reopened ÷ resolved. This needs `ticket_events` status transitions.
- CSAT = average score. Response rate = answered ÷ requested.
- Volume by category × lifecycle stage. This needs N `tickets.org_stage_at_open` (trial or customer) as a snapshot taken at intake, because the org's stage changes later.

**SLA and routing tab.**
- Service levels: N `ticket_sla_policies`.
- Matrix: D from the priority function.
- Routing: N `ticket_categories.queue_key`.
- Channels: static copy (i18n).
- "Business hours Mon–Fri 08–16 Europe/Oslo": N `business_hours` + `holidays`.

**New ticket modal.**
- The organization select lists all orgs; it needs a search-select.
- Category, Subject and Description are present. The description is not bound in the prototype.
- **Missing from the design:** a requester person (needed to send replies by e-mail), type and channel.
- The toast "Ticket T-2334 created · routed to Support" is **F** (hard-coded id and queue).

### 1.3 Actions
Every write calls `app.log(...)` and `app.emit(...)`. Bodies are never put in audit `detail`, event payloads or notification params; only ids go there.
- **Change type / status / queue / assignee / impact / urgency:** `ticket_update`.
  - Priority recomputes and the SLA due times are recalculated.
  - Moving out of Resolved increments `reopened_count`.
  - Each change goes to `ticket_events` / changelog.
- **Send reply:**
  - Inserts a `ticket_messages(kind='reply')`.
  - Sends **P** through the transactional e-mail stream, threaded (Message-ID / In-Reply-To stored).
  - Sets `first_response_at` if it is null.
  - Applies the after-send option: Waiting on customer / keep / Resolved. Resolved sets `resolved_at` and schedules the CSAT request.
- **Internal note:**
  - Inserts kind = note. Visible only to staff with ticket rights.
  - @mentions write `app.notify(staff, 'mention', …)`.
  - The prototype's @Mention button always inserts "@Hanna". Real: a staff picker.
- **Insert macro:** fills the draft from the current version in the agent's locale and records `macro_id` when sent.
- **Attach:** no handler in the prototype. Real: a Storage bucket, staff-only, with size and type limits. Respect "Never attach survey answers": the platform holds no answers (D-19/D-34), so this is structural.
- **Escalate to super-admin:** the prototype hard-codes Tor. Real: assign to a chosen staff member whose permission set is `admin`, write event `escalated`, and notify.
- **Link to problem:** the prototype always links T-2316. Real: a picker over open problems; sets `problem_id`.
- **Link survey or invoice:** no handler. Real: `ticket_link`.
- **Service-request actions** (Extend trial 14 days, Change plan, Export organization data, Switch to EHF invoice):
  - **P** Orgpuls commands through the existing `product-command` edge function (D-23).
  - Set `app.reason` = the T-number, `account_id` = the org's account, and post a `system`/`admin_action` message.
  - Change plan and EHF need parameters and a preview (D-30). The design runs them with no dialog.
  - The design shows all four actions on every service request, whatever its category.
- **Personvern:** creating a ticket with that category inserts a `privacy_requests` row with `due_at = received + 30 d`.
- **Resolve problem and notify N tickets:**
  - Sets problem_status = resolved.
  - For each linked open ticket: posts a templated reply and sets it to Resolved, so CSAT follows.
  - Emits `problem.resolved`.
- **Toggle help / banner:** publishes or unpublishes the linked article, and sends the banner command to Orgpuls (**P**).
- **Draft article:** the prototype only shows a toast. Real: creates a `help_articles` draft prefilled from the ticket cluster.
- **Publish new version / Nynorsk version (macros):** no handlers in the prototype. Real: insert a `ticket_macro_versions` row.
- **Create ticket:** `ticket_create`. Intake workers create tickets from events:
  - `support.requested` → ticket.
  - `contact.submitted` → ticket and lead (D-20; the design says "prospect", and D-20 wins).
  - Inbound support@ / kontakt@ e-mail → ticket, or a message on an existing thread.
- **CSAT:** there is no rating action in the admin. A one-click link in the resolution e-mail calls `csat_submit(token, score)`, an anon RPC with a SHA-256 token hash and single use.
- **Merge tickets:** **not in the design**. There is no control for it. Build it only if wanted (D-41), using `rec_bulk`-style merge with changelog source `merge`.
- **SLA warnings:** a pg_cron job notifies the assignee before a breach (cf. the admin-data notification "T-2310 is close to breaching first response · 38 min left") and records `sla_breached`.

**Rights.** The current right scopes are deals, projects, campaigns and global; there is no tickets scope. Proposal: add a `tickets` scope to `app.right_ok` in a new migration, with actions see, add, edit_others, configure, reports_others and export.
- **Conflict to decide:** the brief says ticket content is restricted to support and super-admin, but the design lists Finance and Sales staff as assignees and has Billing and Sales queues.
- Proposal: per-queue access through `ticket_queues.permission_set_ids`, with Personvern limited to support + admin, matching the panel text "visible to support and super-admin only".
- `ticket_get` writes a `ticket.read` audit row (D-12: reads of customer data are audited).

### 1.4 Promises in the text
- "Reply sent · threaded by e-mail"
- "Internal note — visible to support and super-admin only"
- "Executed actions are written to the org's audit trail with this ticket as the reason"
- "Mirrored to the request queue with its 30-day clock"
- "Never attach survey answers"
- "overdue tickets are highlighted in every list"
- "Priority … never picked freely"
- "Contact-form tickets also create a CRM prospect if consented"
- "Captures user, org, role, current page and browser automatically; suggests help articles first"
- "No respondent channel"
- "Problem resolved · N linked tickets notified"

**Conflicts in the text:**
- The SLA row says Urgent = "Survey send failing, data concern, security", but the matrix only reaches Urgent from many_orgs × blocking. A data concern for one org cannot become Urgent.
- The data's `frtTarget` values (4/9/18/45 h) disagree with the brief and the Reports tab (4/8/16/40 business hours). Use 8-hour business days.
- The prototype's "My tickets" is hard-coded to Magnus while the signed-in user is Tor. Real: `assignee_id = app.me()`.
- The macro "Hvorfor vises gruppen som «—»?" claims "færre enn fem svar … Fem er gulvet". Orgpuls' floor is 3 and its default 5, and an organisation can set 3–10. The copy is wrong.
- Whether SLA clocks pause in "Waiting on customer" is unspecified. Decide and log it.

---

## 2. Settings (`Settings.dc.html`)

### 2.1 Sections
There are 11 sections in a left nav: Rules and limits, Modules, Data fields, Pipelines and stages, Activity types, Language and currencies, Users and teams, Permission sets, Visibility groups, Plans and usage, Sandbox. Feedback is by toast only; there are no modals.

### 2.2 Section by section

**Rules and limits**
- Settings: E `settings_registry` + `setting_values` through `settings_get/setting_set`.
  - Each row shows name, "Applies to …", option pills, the default, and a state: "Default — unrestricted" / "Changed · X" / "Fixed — cannot be switched off".
  - Options are stored as keys (`no_rule`, …). The labels come from i18n.
- "N changed from default": D.
- Change log: E `settings_log` (audit). The two seeded rows ("1 Oct … kept at default", "3 Oct System … register created") are **F**.
- Gaps and conflicts:
  - **Numeric input missing:** the "A number" (count_limits) and "Custom" (api_rate, safeguards, rec_notice) options need a number. `numeric_option` and `value_number` exist in the DB, but the design has no input.
  - **Conflict:** the banner says "Only the anonymity firewall is fixed", but D-11 and the registry also fix `mfa`. The registry also holds `session_idle`, `ip_allowlist` and `login_alerts`, which this screen does not show (they belong on the Security screen). The design's list has 15 rows; the registry has 19.

**Modules**
- Nine switches: E `app.modules` via `modules_get/module_set`. The prototype gets them from shell props.
- "API returns «module disabled»" is E `app.require_module` raising `module_off`. Map it to the message.
- Right: global:configure. Audit `module.switched`.

**Data fields**
- Entity chips (7): E `app.entities`. Deals, leads, products, projects and activities may not exist yet.
- Field rows:
  - Label, key (the design shows `field_<key>`), type, quality rule, access: E `app.fields`.
  - The quality-rule text is D from `quality` + `from_stage_id`, or "Formula · read-only".
  - The access text is D from `hidden_for`, `readonly_for` and `pipeline_ids`.
  - **F:** the prototype shows the same seven deal fields for every entity.
- Editor:
  - Type chips are display only.
  - Formula, Quality, From stage, Pipelines, Read-only for and Description (≤300) map to E columns. `from_stage_id` and `pipeline_ids` need N pipelines/stages.
- **Conflict:** the design models "Weighted value" as type **Monetary** with a formula, and "16 available" excludes Formula. The DB has `type='formula'` if and only if `formula` is set. Add N `fields.formula_result_type`.
- **Missing from the design:** a save button, Add field, an options editor, and a Hidden-for control (the access text shows "Hidden from Sales" but nothing edits it).
- Promise: "Appears in forms, filters, reports, import and the API without a deploy · options per field: unlimited". The limit is governed by `count_limits`.
- Right: deals:configure or global:configure.

**Pipelines and stages**
- N `pipelines` (name, ord, `visibility_group_ids` for "Visible to: …").
- N `pipeline_stages` (ord, name, probability 0–100, which the prototype clamps; `rot_days`, nullable).
- Actions: reorder (▲▼), rename, change probability, change rotting days, "＋ Stage", "＋ Pipeline".
  - "＋ Pipeline" only shows a toast in the prototype: "pipelines: unlimited".
- **Delete stage:**
  - The prototype silently moves open deals to the previous stage (or the next one, if the first stage is deleted).
  - PIP-02 says "Deleting a stage requires a target stage". Real: `stage_delete(stage, target)`. Deals move with changelog source `system` and event `deal.stage_changed`. The toast reports the real count.
  - There is no deals table yet.
- "Reorder shows for every user": realtime or refetch.

**Activity types**
- N `activity_types` (key, name, glyph, active, ord, is_system). The toggle sets `active`.
- "Custom fields: Outcome, duration …" is **F**: assigned by row index with `i % 8`. Real: fields on entity `activities` scoped by N `fields.activity_type_ids`.
- "＋ Activity type" always adds "Site visit ⌂" (**F**). Real: a name and icon form, which the design does not show.
- Promise: "New types are selectable and reportable at once".

**Language and currencies**
- Language toggle: English / Norsk bokmål / **Svenska**. E `admins.locale`, which only allows `en` or `no`. Svenska conflicts with D-04 and the check constraint; drop it or decide.
- Date format: D from locale.
- Number format "12 345,67": E `admins.number_format`. The design has no control for it.
- Time zone: E `admins.time_zone`. No control in the design.
- First day of week "Monday": no column. D from locale, or N `admins.week_start`.
- Currencies: N `currencies` (code, name, rate_nok, rate_date, rate_source, active, is_default, is_custom).
  - The rates (11,62, 0,98, 1,56, 10,74) are **F**. Real: **P** Norges Bank daily rates through a cron job.
  - "Company default NOK": `is_default`.
  - "＋ Custom currency" has no handler.
- Promise: "switching language does not reload data".

**Users and teams**
- Staff rows: E `staff_list` (name, email, title as "role", permission set, group, `last_seen_at`).
- Actions:
  - **Invite:** `staff_save` insert, plus a **P** Supabase Auth invite e-mail (edge function, service role). The prototype only shows a toast. "MFA required at first login" holds because `is_admin` demands aal2.
  - **Copy access:** E `staff_copy_access(from, to)`. The per-row button has no target picker, and the direction is unclear (the toast says "copied from <row>").
  - **Replace:** E `staff_replace(old, new)`. Needs a picker for the new user.
  - **Deactivate / Reactivate:** `staff_save(active)`. SF-43 also requires ending sessions and prompting to transfer owned workflows. Add a `staff_deactivate` that revokes auth sessions.
- Team cards: E `access_model.teams`. The prototype's four cards are hard-coded, and their names (Sales Norway …) do not match `staff.team` (Sales, Leadership …).
- Right: global:security.

**Permission sets**
- Seven sets × 11 actions × 4 scopes: E `permission_sets.rights`, saved with `permission_set_save`.
- The prototype's default ticks come from an ad-hoc formula (**F**) that does not match the presets seeded in 0003. The DB is authoritative. Lock the Admin set.
- The footer says "sales, marketing and project roles are an open point (G-10)". D-08 settled this, so the copy is stale.
- Audit `permission_set.saved`.

**Visibility groups**
- Tree: E `visibility_groups` via `access_model`. Member counts are D; the prototype's counts are **F**.
- Default visibility per record type (7 rows, 4 options): N `entities.default_visibility`, using the existing values owner, group, group_sub, all. Prototype defaults: Deals and Leads = group_sub, everything else = all.
- The text says "Enforced by row-level security". In fact D-09 uses closed RLS plus security-definer `vis_sql`. The copy is imprecise.

**Plans and usage**
- Fourteen usage counters: all values are **F**. Real: D counts per table; most of those tables do not exist yet. "Enrichment credits (cycle)" is **P** provider usage (N `usage_counters`, D-17).
- Limits "unlimited": D from the `plan_gates` / `count_limits` settings.
- "waitlist (0)": **F**.
- Entitlements Base / Growth / Add-on, all "On": the plan names are **F**. D-17 says nothing is sold. Add N `entitlements` only if `plan_gates = per_plan`.

**Sandbox**
- Rows:
  - Sample organizations, people and deals: E `sandbox_counts`. The values 46 / 32 / 36 equal the demo array lengths.
  - "Workflows under test 3": **F**.
  - "Last reset 1 Oct 2026": **F**. D from the latest `sandbox.reset` audit row.
- Remove sample records: E `sandbox_clear` (global:configure).
- Reset from seed: N `sandbox_reset` = clear, then re-insert the repo's demo seed (D-02) as `is_sample`.
- Header switch: E `sandbox_set`. "Yellow band … «Sample» label" is shell UI.
- Promise: "never customer data … never touch the live company". Product commands from the sandbox go to the local stand-in (D-02).

---

## 3. Coverage (`Coverage.dc.html`)

### 3.1 What it shows
- **Header:** "CRM enrichment brief · 3 October 2026" (static) and the claim "Every feature and flow in the brief has a home in this prototype."
- **Stat tiles, all from `window.SA_COVERAGE` except Settings:**
  - Features: `feats.length` = 183, captioned "all mapped to a screen".
  - Modules: 21.
  - User flows: 29, "UF-01 to UF-29".
  - System flows: 45.
  - Settings: **15, hard-coded**, captioned "every default unrestricted". That is false for the firewall, and the registry holds 19.
- **Tabs and search:**
  - Search covers id, name and text.
  - **Features:** module chips with counts. Rows show id, name and description, expand to "Rules and edge cases" (`ru`) and "Acceptance" (`a`), and have a "where →" route button. The route comes from `r`, overridden for LGN→leadgen, WEB→visitors, CMP→campaigns, LEA (except LEA-06)→leads, assistant→home, marketing→campaigns.
  - **User and system flows:** 74 cards, each with trigger `h` and steps `s`.
  - **Admin baseline, extended:** seven cards hard-coded in the component, including "Ticketing (ITSM)".
- **Data shape:**
  - `mods {code: name}`.
  - `feats [{id, n, m, r, d, ru, a}]`.
  - `flows [{id, n, s[], h}]`.
- **There is no status field.** "Has a home" means a prototype route, not that anything is built. Ticketing features are not among the 183; ticketing appears only in the baseline list.

### 3.2 How to compute it for real
Keep coverage in the **repository**, not the database. It describes the codebase and changes with commits.
- **Source:** `docs/coverage/coverage.json`, generated by a script from `INSTRUCTIONS.md` (the 183 features, 74 flows and Appendix 2 items, ticketing included).
- **Per item:**
  - `status` (missing / partial / built / verified), seeded from the statuses in `05-GAP-FEATURES.md`.
  - `route`.
  - `phase`.
  - `evidence[]`: migration, RPC, test or Playwright spec ids.
  - `decisions[]`.
- **CI checks:**
  - Every spec id appears exactly once.
  - Every route exists.
  - `verified` requires an evidence test that exists and passes.
- **Stats:** computed from the file. Add counts per status.
- **Settings tile:** count `settings_registry` live, split into fixed and unrestricted.
- **Page:** a static build-time import. If staff need to edit it in the admin instead, use `app.coverage_items(id pk, kind, module, name, status, route, evidence jsonb, updated_at)` with global:configure. The repo file is preferable.

---

## 4. Proposed DDL (new only; all in `app`, RLS on, no policy, no client grant, access through security-definer RPCs)

```
ticket_queues(key text pk, name text, ord int, permission_set_ids uuid[] null)
ticket_categories(key text pk, name text, queue_key text fk, ord int, active bool)
ticket_sla_policies(priority text pk check in(urgent,high,normal,low), first_response_min int, resolution_min int, ord int)
business_hours(dow smallint pk, opens time, closes time)   -- tz = setting, default Europe/Oslo
holidays(day date pk, name text)
tickets(id uuid pk, number bigint identity unique, type text check(question,service_request,incident,problem),
  category_key fk, queue_key fk, status text check(new,open,waiting_customer,waiting_us,resolved,closed),
  impact text check(one_user,one_org,many_orgs), urgency text check(not_blocking,blocking),
  priority text generated always as (app.ticket_priority(impact,urgency)) stored,
  subject text ≤200, organization_id fk null, person_id fk null, product text fk null,
  channel text check(in_app,email,contact_form,staff), assignee_id fk admins null, owner_id fk admins null,
  problem_id uuid fk tickets null, problem_status text null check(investigating,known_error,resolved),
  root_cause text, workaround text, status_banner bool default false, topic text null,
  context jsonb default '{}', org_stage_at_open text check(trial,customer,none),
  first_response_due_at, resolution_due_at, first_response_at, resolved_at, closed_at timestamptz,
  reopened_count int default 0, csat_score smallint check 1..5, csat_requested_at, csat_at, csat_token_hash bytea,
  source_event_id bigint fk events_in null, email_thread_key text, is_sample bool, deleted_at, version int,
  created_at, updated_at;
  check (problem_id is null or type <> 'problem'), check ((type='problem') = (problem_status is not null)))
ticket_messages(id uuid pk, ticket_id fk cascade, kind text check(customer,reply,note,system,admin_action),
  author_staff_id null, author_person_id null, body text, macro_id null, mentions uuid[],
  email_message_id text, in_reply_to text, delivery_status text, created_at)
ticket_attachments(id, message_id fk cascade, storage_path, filename, bytes int, mime)
ticket_links(ticket_id fk, kind text check(survey,invoice,deal,lead,article), ref text, label text, created_by, pk(ticket_id,kind,ref))
ticket_events(id bigint, ticket_id, kind text, from_value, to_value, actor_id, at)  -- or reuse app.changelog entity='tickets'; one, not both.
  Append-only trigger must allow cascade deletes when the parent is gone.
privacy_requests(id, ticket_id fk, organization_id, kind check(access,correction,deletion), received_at, due_at generated (received_at+30 d), status, closed_at)
help_articles(id, slug unique, title, body, category_key, locale check(nb,nn,en), status check(draft,published), version int, problem_id null, published_at, updated_at)
help_article_stats_daily(article_id, day, views int, deflections int, pk(article_id,day))
ticket_macros(id, name, category_key, active) ; ticket_macro_versions(macro_id, locale check(nb,nn), version int, body, published_at, published_by, pk(macro_id,locale,version))
pipelines(id, name, ord, visibility_group_ids uuid[] null, archived_at)
pipeline_stages(id, pipeline_id fk, name, ord, probability smallint check 0..100, rot_days int null, archived_at)
activity_types(id, key unique, name, glyph, active bool, ord, is_system bool)
currencies(code char(3) pk, name, rate_nok numeric(14,6), rate_date date, rate_source check(norges_bank,manual), active, is_default (partial unique), is_custom)
usage_counters(key, cycle_start date, value bigint, pk(key,cycle_start))
entitlements(feature, plan, enabled, pk(feature,plan))   -- only for plan_gates=per_plan
ALTER fields ADD formula_result_type text, ADD activity_type_ids uuid[]; FK fields.from_stage_id → pipeline_stages
ALTER entities ADD default_visibility text check(owner,group,group_sub,all) default 'all'
ALTER admins ADD week_start smallint null  (and decide on 'sv')
REPLACE app.right_ok to accept scope 'tickets'
```

## 5. RPCs (snake_case, `public.*`, security definer)

**Tickets:**
- `tickets_list(p_queue, p_q, p_sort, p_product)` returns rows and queue counts
- `ticket_get(p_id)`, which audits the read
- `ticket_create(p_values)`
- `ticket_update(p_id, p_values, p_version)`
- `ticket_reply(p_id, p_body, p_after, p_macro_id, p_attachment_ids)`
- `ticket_note(p_id, p_body, p_mentions)`
- `ticket_escalate(p_id, p_to)`
- `ticket_link(p_id, p_kind, p_ref)` / `ticket_unlink`
- `ticket_link_problem(p_id, p_problem_id)`
- `ticket_run_action(p_id, p_action, p_args)`, which goes to product-command with reason = T-number
- `tickets_for_org(p_org)`
- `problems_list()`, `problem_update(p_id, p_values)`, `problem_resolve(p_id, p_macro_id)`
- `help_articles_list`, `help_article_save`, `help_article_publish`, `help_gaps(p_days)`, `help_suggest(p_q)` (plus an anon published-only variant for the widget)
- `macros_list`, `macro_publish_version(p_id, p_locale, p_body)`
- `ticket_reports(p_from, p_to, p_product)`
- `sla_config_get`, `sla_policy_save`, `routing_save`
- `csat_submit(p_token, p_score)` (anon)

**Internal (not public):**
- `app.ticket_priority`
- `app.business_add(ts, minutes)`
- `app.ticket_from_event(p_event_id)`
- `app.ticket_from_email(...)`
- `app.tickets_sla_scan()` (pg_cron)

**Settings:**
- Existing RPCs listed at the top.
- New:
  - `pipelines_get`, `pipeline_save`, `stage_save`, `stages_reorder(p_pipeline, p_ids)`, `stage_delete(p_stage, p_target)`
  - `activity_types_get`, `activity_type_save`
  - `currencies_get`, `currency_save`, `currency_rates_refresh` (job)
  - `visibility_default_set(p_entity, p_value)`
  - `usage_get`, `entitlements_get`
  - `sandbox_reset`
  - `staff_invite` (edge function wrapping `staff_save` plus the Auth invite)
  - `staff_deactivate` (also revokes sessions)

**Audit actions:**
- Tickets: `ticket.created|updated|replied|noted|escalated|linked|read|action_run`, `problem.resolved`, `article.published`, `macro.published`, `csat.received`.
- Settings: `setting.changed`, `module.switched`, `field.saved`, `pipeline.saved`, `stage.deleted` (moved count and target), `activity_type.saved`, `currency.saved`, `staff.invited|updated|access_copied|replaced|deactivated`, `permission_set.saved`, `visibility_default.changed`, `sandbox.cleared|reset`.

**Events:** `ticket.created`, `ticket.status_changed`, `ticket.assigned`, `ticket.resolved`, `ticket.sla_breached`, `problem.resolved`, `deal.stage_changed`.
