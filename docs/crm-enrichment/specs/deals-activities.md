# Data-requirements spec: Deals and Activities screens (Sentral admin)

Sources read in full: `Deals.dc.html` (markup and logic), `Activities.dc.html`, `admin-data.js`, and the PIP-01..17, ACT-01..09, CRM-07/08/10/11/12, COM-10/11 and CUS-01 entries in `coverage-data.js`. I only got part of the CUS-02 text. I didn't read the rest of CUS, AIA, SEC or ENT-02, because the auto-mode classifier blocked me from re-reading a saved tool output.

**Ground rule.** `admin-data.js` builds every deal and activity from a seeded PRNG (`rnd`). Each value marked **FAB** below is invented and has no real source. The real app must compute it, read it from a provider, or leave it out.

---

## A. Deals screen

### A1. Views and states
- **Toolbar:**
  - View tabs: Pipeline, List, Forecast, Archive and restore, Products.
  - Pipeline `<select>`.
  - Quick filters: Owner, Label, Status (Open/Won/Lost/All).
  - "Filter" popover (advanced filter). Its count badge reads "Filter · N".
  - "Won and lost" toggle.
  - "View as" select: **demo-only**. It simulates permission sets (super-admin, sales, read-only). In the real app this comes from the session.
  - "＋ Deal" button.
- **Summary strip:**
  - `N deals · Σvalue · weighted Σ`.
  - "Capacity: unlimited (setting) · waitlist 0".
  - Legend: ◷ planned, ! overdue, ⚠ no next step.
  - Read-only banner: "View rights only — cards cannot be moved".
- **Pipeline (kanban):**
  - "Customize cards" popover: per-pipeline checkboxes for Organization, Value, Expected close date, Deal score.
  - Stage columns. While a drag is in progress, the columns tint and a sticky drop bar appears with Won, Lost, Archive and Delete.
- **List:**
  - Sort label, with "shift-click a header to add a sort".
  - Selection bar: N selected, Move to stage, Set owner, Delete.
  - Columns popover, Export CSV, XLSX.
- **Forecast:** month columns showing Open, Won and Projected. Cards can be dragged between months.
- **Archive and restore:** two cards.
  - Archived deals: Unarchive. Empty text "Nothing archived yet."
  - Deleted, restorable for 30 days: Restore. Empty text "No deleted deals in the last 30 days."
- **Products:** catalog table and a "＋ Product" button. The button has no handler in the prototype.
- **Deal drawer** (right side, 980 px):
  - Sticky header with owner select, Follow · N followers, Won, Lost, More… (Duplicate with products, Convert back to lead, Archive, Delete) and close.
  - Clickable stage progress bar.
  - Left column: AI panel, Summary with label toggles, Score-why, Details/custom fields, Person/organization/participants.
  - Right column: Products with MRR/ARR/ACV/TCV tiles; composer tabs (Note, Activity, Call, Email, Files, Documents, Invoice); Focus; History with 9 filter chips.
- **Modals:**
  - New deal (title only).
  - Lost: reason chips plus an optional comment.
  - Required field before stage ("«Decision maker» is required from the Negotiation stage", button "Save and move").
  - Next step ("Done — what is the next step?").
- **Toast:** shows for 2.6 s.

### A2. Field mapping
**Stage column header**

| Element | Source |
|---|---|
| name, prob % | NEW `stages.name`, `stages.probability smallint 0..100` |
| "rots N d" | NEW `stages.rot_days int NULL`. Optional (PIP-05). Hide when null. |
| Σvalue · count | DERIVED over the filtered deals in that stage |
| top border colour | Design constant: palette indexed by stage position, not data |

**Card**

| Element | Source |
|---|---|
| title | NEW `deals.title text NOT NULL` |
| activity glyph ◷ / ! / ⚠ | DERIVED from activities: `overdue` if any open linked activity has `starts_at < now()`; `planned` if any open activity exists; otherwise `none`. **FAB in demo:** `act` is random and tied to idle > rot. |
| org name | `deals.organization_id` → organizations.name |
| labels | `deals.labels uuid[]` → existing `labels` (record_type = 'deal'). The six demo labels are seed data. |
| owner initials | `owner_id` → staff.initials |
| value | NEW `deals.value numeric(14,2)`, `currency char(3)` |
| close | NEW `deals.expected_close_date date`. **FAB:** the demo's `close` and `closeMonth` are independent random values, so a card can sit in the wrong forecast month. |
| score badge (≥70 green, ≥40 amber, else red) | NEW `deals.score smallint NULL`, computed (see A2c). **FAB:** random 18–94. |
| "Rotting · idle N days" and red card | DERIVED: `status='open' AND stage.rot_days IS NOT NULL AND idle_days > rot_days`. `idle_days = now() − deals.last_activity_at` (NEW `timestamptz`). **FAB:** idle is random. |
| won/lost background | `deals.status` |

**Summary strip**
- count, value and weighted value: DERIVED. Weighted = Σ value × stage.probability / 100.
- "Capacity: unlimited (setting)": comes from the capacity setting (PIP-16/ENT-02).
- "waitlist 0": hard-coded. Needs a waitlist table, or leave it out until one exists.

**Drawer**

| Element | Source |
|---|---|
| "ID d101" | NEW `deals.seq bigint` (system ID, PIP-10) |
| pipeline name | `stages.pipeline_id` → pipelines.name |
| "source X" | NEW `deals.source text` (Web form, Chatbot, Prospect search, Manual, Campaign, Web visitors, Import, API) plus `created_source` |
| person name / role · phone · "primary" | NEW `deals.person_id` → people |
| org line `orgnr · city · health N` | organizations. `health` is a provider/derived value from the product side. If organizations has no health column, leave it out. |
| Followers count | NEW `followers` table (generic, PIP-09) |
| Progress-bar days per stage | DERIVED from NEW `deal_stage_history`. Past stages: `left_at − entered_at`. Current: `now() − entered_at`. **FAB:** `days[]` is random and current = idle + 2. |
| AI panel ("Slipping — 41 % chance…", "72 % chance…", "advance twice as often") | **FAB, all of it.** No model exists, so leave the panel out. The CTA would create an activity once the user approves it. |
| Summary: Value, "Probability N % (stage)", Status, Source, Lost reason | columns; probability comes from the stage |
| "Expected close: `close + ' 2026'`" | **FAB year.** Use the full date. |
| Labels toggles | `deals.labels` |
| "drag sections to reorder" | per-user sidebar order → NEW view prefs |
| Details: Decision maker | a custom field (`fields`, quality required, from_stage_id = Negotiation). **FAB:** the demo derives it from score > 50. |
| Details: Employees in scope | organizations.employees |
| Details: Weighted value | formula: value × probability |
| Details: Competitor "Planday" | **FAB:** d101 only |
| Details: Board meeting "14 Oct 2026" | **FAB:** the same on every deal |
| Details, generally | Render from `fields` (record_type = 'deal') and `deals.custom`. The tag shows the type and quality. |
| Participants Mona Hansen / Petter Aas | **FAB, hard-coded.** NEW `deal_participants`. |
| Product lines | NEW `deal_products`. **FAB:** only d101 has real lines; every other deal gets one invented line at value/12. |
| Focus | open activities WHERE deal_id; when = today hh:mm / "in N d" / "N d overdue"; priority |
| History | union of changelog (existing), notes, completed activities, and later emails, files, documents, invoices and engagement from their modules. **FAB:** all 9 base entries are identical on every deal (an email opened "Forslag: Skiftly for lageret", a proposal with 2 signers, Ingrid's pinned note, a Planday-era file, a web visit, a "Round-robin sales" assignment rule, and "52 000 → 64 000" from an automation). |

**List columns:** System ID, Title (link), Organization, Value (inline edit unless read-only), Stage (plus "· won/lost"), Owner, Close, Score, Source, Labels.

**Catalog**
- name, code, unit, tax, billing, colour, variations: NEW `products`.
- NOK: NEW `product_prices`.
- EUR and SEK: shown as "converted daily". **FAB:** fixed `/11.6` and `×1.02`. Real values need an FX provider, or manual prices per currency.
- Tax is shown as "25 %" on every row.

**A2c. Formulas.** The promises below need fixing, not copying.
- **Deal value from lines.** Line total = qty × price × (1 − disc/100). The demo multiplies recurring lines by 12 to get the deal value. Define deal value = TCV, and add `deals.value_source manual|products`: a deal with no lines keeps its typed value.
- **Revenue tiles.** MRR = Σ recurring monthly-normalised totals, ARR = 12 × MRR, ACV = ARR + one-off, TCV = MRR × cycles (or 12 when the line runs "until canceled") + one-off. The demo sets TCV = ACV, which is wrong for multi-year deals. Installments count only toward ACV and TCV (CRM-08).
- **Score** = Σ points of the matching rules, clamped to 0..100, and stored with its breakdown. The six demo rules:

| Rule | Points | What the demo actually tests |
|---|---|---|
| org health ≥ 70 | +25 | org health |
| proposal link opened | +25 | `score > 60`. Circular, and needs document tracking (provider). |
| decision maker is a participant | +10 | — |
| uses another app | +10 | `org.products > 1` |
| no reply in 5 days | −10 | idle > 5 |
| value > 100 000 | +10 | — |

  In the demo the shown score is random and does not equal the sum of the rules.
- **Projected** (forecast) = Σ won + Σ open × prob/100.

### A3. Actions
Every write goes through optimistic-concurrency `version`, writes changelog (field, old, new, user, time, source user|automation|api|import), and emits an outbox event.

| Action | Real behaviour | Right | Event / history |
|---|---|---|---|
| Drag card to stage, click progress bar, bulk "Move to stage" | Optimistic, rolled back on failure. Checks required fields with `from_stage_id` ≤ target; if any are missing, return a `missing_required` list (opens the modal). Updates `stage_id` and `stage_entered_at`, closes and opens `deal_stage_history`, resets `last_activity_at`. Notifies followers. Bulk is limited to stages of the same pipeline: the demo offers the current pipeline's stages to a list that spans all pipelines. | deals.edit (bulk_edit for bulk) | `deal.stage_changed`, one changelog row per deal |
| Demo side effect on stage move: an overdue activity becomes "planned" | **Do not copy.** Activity status is derived. | | |
| Won (button or drop zone) | status=won, `won_at`, `closed_by`. The "workflow «Won → create project» queued / invoice can be created" text is a promise from the automation module; show it only if such a workflow exists. | deals.edit | `deal.won` |
| Lost | status=lost, `lost_reason_id` or free text, `lost_at`. The comment becomes a note. Admin list plus a "reason mandatory" setting. Demo bug: with no chip picked, the typed comment is saved as the reason while the log says "Other". | deals.edit | `deal.lost`, plus note |
| Reopen (PIP-07; no button in the design) | clears status, keeps history | | `deal.reopened` |
| Archive / unarchive | `archived_at`/`archived_by`. Leaves default views and capacity. The demo's "archived today" is FAB. | deals.edit | `deal.archived` / `deal.unarchived` |
| Delete (drop, More, bulk) / restore | soft delete: `deleted_at`, `deleted_by`, source; purge after 30 days. Restore keeps `stage_id` and links. Bulk shows a preview; second-admin approval is a setting (off). Seeded "d130 · Eirik · 22 days left" is FAB. | deals.delete | `deal.deleted` / `deal.restored` |
| Duplicate with products | copies fields, custom and lines; no history, emails or followers | deals.create | `deal.created` (source duplicate) |
| Convert back to lead | belongs to the leads module | | |
| Inline value edit, owner change, labels, bulk owner | update_deal | deals.edit | `deal.updated`, changelog |
| Edit product qty or discount | upsert line, then recalc value in the same transaction | deals.edit | changelog for the line and the value |
| Follow | insert/delete `followers`. Gives visibility and notifications only, never edit rights. | deals.view | `record.followed` |
| ＋ Participant | insert `deal_participants` (person picker; the prototype only toasts) | deals.edit | changelog |
| Forecast drag | sets `expected_close_date`. The demo uses the 15th of the target month; keep the day of month, clamped. | deals.edit | `deal.updated` |
| New deal | title only; first stage of the current pipeline; value 0; source Manual; owner = creator or assignment rule. Demo bug: it copies `deals[2]`'s org and person. | deals.create | `deal.created` |
| Composer: Note | NEW `notes` (record_type, record_id, body, pinned, mentions). Resets the idle clock. | | `note.created`, mention notification |
| Composer: Activity | create_activity linked to the deal | | |
| Composer: Call, Email, Files, Documents, Invoice | provider modules (calling app, mail, storage, e-sign, accounting). Out of scope until those exist; hide or disable. | | |
| Focus "done" | complete_activity, then the next-step modal | | |
| Export CSV/XLSX | the visible rows and columns, formulas neutralised, logged | deals.export | `export.created` (SEC audit) |
| Save as filter | toast says "shared with Sales team" → visibility private / shared plus favourite | | |
| Customize cards | per pipeline, not per user (PIP-14) | settings.pipelines | |

### A4. Filters, sorts, totals
- **Quick filters:** owner (sales staff; the demo hard-codes 3 names), label, status.
- **Advanced filter:** conditions combined as OR of AND-groups. Fields: Value, Score, Idle days, Source, Label. Operators: is, >, <, contains. The real version must cover every standard and custom field, with operators by type.
- **Saved filters:** the demo's "Big and stuck", "Hot or high score" and "From prospect search" are seed examples.
- **"Same result in pipeline, list and forecast".** The filter is a single server-side predicate. Note the demo's inconsistency: List ignores the pipeline selector, while Board and Forecast honour it. Decide one rule.
- **"Won and lost" toggle:** a per-user preference (PIP-15).
- **Sort:** multi-column; default value desc. Stage sorts by probability.
- **Columns:** per-user, with an admin default.
- **Totals:** per column and per summary, always computed over the same filtered set.

### A5. Promises in the text
- Rot threshold per stage, optional. The idle clock resets on a stage move, a completed activity, an email or a note. Scheduling an activity does not reset it, though the demo resets it on "next step" and on the AI scheduling.
- The owner is notified when a deal starts rotting.
- A stage reorder shows for every user.
- Deleting a stage requires a target stage.
- One changelog entry per deal on bulk edits.
- Restorable for 30 days, returning to the stage it left, with links intact.
- Archived deals stay out of capacity.
- "No payload lost" when capacity is hit.
- "Deal value is calculated from lines".
- Duplicating does not copy history.
- Followers are notified on a stage change.
- Read-only users cannot drag.
- Exports respect visibility.

---

## B. Activities screen

### B1. Views and states
- **Toolbar:**
  - Tab pills: Calendar, To-do list, Meeting scheduler, Reminders and sync.
  - Filters: User, Type, Status (Open/Done/All).
  - "＋ Activity" button.
- **Calendar:**
  - Day, Week and Month modes.
  - Week: an 8:00–17:00 grid at 54 px per hour, with items placed by start and height by duration (minimum 26 px). Items are draggable onto hour slots ("Drag to reschedule · synced calendar events update too"). Done items are struck through.
  - Month: 35 cells, at most 3 items each, with no "+N more".
  - Day: a list showing time, colour bar, subject, org · duration · owner, and "Video link · N guests".
  - **FAB/hard-coded:** the titles ("Week 41 · 5–11 October", "October 2026", "Monday 5 October 2026"), a fixed today, and the month grid offset. The offset is wrong: 1 Oct 2026 is a Thursday. Items outside 8–18 vanish; the real grid needs scrolling and an all-day row.
  - Bug: Status = Open still shows done items in the calendar (`calMode !== 'List'`).
- **To-do list:**
  - Tabs All, Overdue, Today, This week, Done, with counts. The counts ignore the User and Type filters; fix that.
  - Columns: select, done toggle, subject, linked to, due, duration, owner, priority (inline select), guests.
  - Sort by due or priority.
  - Bulk: Set priority, Move to tomorrow, Mark done.
- **Next-step prompt** (bottom-right panel after marking done):
  - "«subject» on deal".
  - Quick picks: "Call in 2 days", "Email tomorrow", "Meeting next week", "Task: send proposal". The demo only toasts on these; the real picks create the activity.
  - "Skip — deal will show a warning icon".
- **Meeting scheduler:**
  - Booking-link cards: name, kind, URL, description.
  - Availability grid: Mon–Fri, 08–15, toggle cells.
  - "What the contact sees" preview: slots and Confirm booking.
  - Recent bookings.
- **Reminders and sync:**
  - Channel toggles: In app, Email, Desktop, Push.
  - Default timing select.
  - Calendar sync: provider (Google / Microsoft 365), One-way / Two-way, calendar select, activity types to sync, status footer.
- **Edit/New modal:**
  - Type chips. They include "Site visit", which is not in `actTypes` and shows that custom types exist.
  - Subject, Date, Time, Duration, Priority, Linked deal, Owner.
  - Guests with RSVP.
  - Video link: Meet, Teams, Zoom, None.
  - Remind me chips.
  - Outcome (custom field).
  - Note.
  - Save → "Activity saved · invites sent · reminders set".
  - In the demo, Date, Time, Duration, Priority, Owner, Outcome and Note are **unbound**, and Linked deal has a single option. All must be real fields.

### B2. Field mapping

| Element | Source |
|---|---|
| type, glyph, colour pair | NEW `activity_types(key, name, glyph, bg, border, position, active)`. The demo hard-codes the colours. |
| subject, note | NEW columns on `activities` |
| day/hour/min | NEW `starts_at timestamptz` (plus `all_day`). The demo uses a day offset from a fixed today. |
| duration | `duration_min int`. The demo also uses 15 and 90, which the modal select (30/45/60) cannot express. |
| owner | `owner_id` → staff |
| priority | `priority text check (high, medium, low)` |
| done | `done bool`, `done_at`, `done_by` (ACT-01 stamps) |
| linked to | `deal_id`, `person_id`, `organization_id`, plus nullable `lead_id` and `project_id`. "Linked to" shows the deal title, falling back to the org. |
| due label, overdue | DERIVED: overdue = not done and `starts_at < now()`. In the demo, earlier today doesn't count as overdue. |
| guests count, "N · 1 declined" | `activity_guests` with `response`. **FAB:** "1 declined" appears on every row. |
| Guest list (Kari, Mona, Petter, with Accepted / Tentative / Declined) | **FAB:** the same three on every activity. RSVP comes from the calendar provider (ACT-08). |
| video link | `video_provider`, `video_url`, created through provider adapters (COM-11). **FAB URLs.** |
| Remind me (per activity) | NEW `activity_reminders(channel, offset_min, fire_at, fired_at)` |
| Outcome | custom field (`fields`, record_type = 'activity'). The options are seed data. |
| "created by workflow" | `created_by_workflow_id` (ACT-01) |

**Scheduler**
- Booking links: NEW `booking_links`, `booking_link_times`. The two links, the `book.orgpuls.no/tor/...` URLs, "next 3 weeks", "sent to Kari Nordmann · expires Fri", the preview header "TL · Tor Lambrechts · 30 min · Google Meet" and all slot times are **FAB**.
- Free slots = availability rules − provider busy (free/busy) − existing activities − buffer (15 min, promised).
- Availability: NEW `availability_rules`. The demo default (lunch at 12 off, Friday after 13 off) is a seed.
- Recent bookings: Kari, Ole and Marte are **FAB**; read from `bookings`.

**Reminders**
- Channels: NEW `reminder_prefs`.
- "To tor@orgpuls.no" should be `staff.email`.
- "Browser permission granted" is runtime browser state; do not store it.
- "iPhone · Sentral mobile" needs `push_devices`; otherwise **FAB**.
- Default timing is unbound in the demo.

**Sync**
- Provider, mode, calendar and types: NEW `calendar_connections`.
- The calendar options "tor@orgpuls.no / Sales team" are **FAB**; they come from the provider's calendar list.
- The footer's "last sync 2 min ago · 0 conflicts" is **FAB**; read `last_synced_at` and the conflict count.
- "Private events sync as private" is a rule.

### B3. Actions

| Action | Behaviour | Right | Event / history |
|---|---|---|---|
| Create/edit (modal, composer, next-step pick, AI CTA) | insert/update; guests get invites through the synced calendar; reminders scheduled per channel | activities.edit (own) / team visibility | `activity.created` / `activity.updated`, changelog |
| Drag to reschedule (calendar), bulk "Move to tomorrow" | update `starts_at` (keep the time of day for bulk); push to the external event in sync mode; reschedule pending reminders | activities.edit | `activity.rescheduled` |
| Mark done / undo | done, `done_at`, `done_by`. Touch the deal's `last_activity_at`. Show the deal history entry. May trigger automations. Prompt for the next step (per-user switch, ACT-07). Bulk done gives no prompt. | activities.edit | `activity.completed` / `activity.reopened` |
| Skip next step | nothing is stored; the deal card shows ⚠ because it is derived | | |
| Priority inline / bulk | update | edit / bulk_edit | changelog per row |
| Toggle availability, create booking link | write rules and links | own | |
| Confirm booking (public page; in admin this is a preview) | atomic: re-check the slot is free, insert the booking and an activity linked to the person and their open deal, send confirmations to both, remove the slot | public token | `booking.created`, `activity.created` |
| Channel toggles, default timing | `reminder_prefs` | own | |
| Connect provider / change mode / types | OAuth tokens in Vault; sync job; webhooks; two-way = latest change wins; recurring external events read-only | own | `calendar.connected`, `calendar.sync_completed` |
| Reminder dispatch (job) | fires once per (activity, channel, offset); sets `fired_at` | system | notification rows |

### B4. Filters and sorts
- User (team visibility applies), Type, Status.
- List tabs: All, Overdue, Today, This week (Mon–Sun relative to now), Done.
- Sort: due (`starts_at`) or priority (High < Medium < Low).
- No saved filters in the design, though PIP-12 says activities have them.

### B5. Promises
- "Synced calendar events update too".
- "Invites go out through the synced calendar".
- "Each reminder fires once per chosen channel".
- "Busy times are read from the synced calendar · 15 min buffer · video link added automatically".
- "Both get a confirmation · an activity is created and linked to the person and open deal".
- "Private events sync as private".
- "Latest change wins".
- A deactivated type stays on past activities.

---

## C. Proposed schema (all org-scoped, RLS)

```
pipelines(id uuid pk, org_id, name text, position int, card_fields text[] default '{org,value,close,score}', visibility_group_ids uuid[] null, archived_at)
stages(id, pipeline_id fk, name, position int, probability smallint check 0..100, rot_days int null check >0, deleted_at)
deals(id, org_id, seq bigint identity, title text not null, value numeric(14,2) default 0, currency char(3) default 'NOK',
      value_source text check(manual|products) default 'manual', pipeline_id, stage_id, stage_entered_at timestamptz,
      status text check(open|won|lost) default 'open', won_at, lost_at, closed_by uuid, lost_reason_id null, lost_reason_text null,
      person_id null, organization_id null, expected_close_date date null, source text, created_source text,
      last_activity_at timestamptz, score smallint null, score_breakdown jsonb null, score_computed_at,
      archived_at, archived_by, owner_id, visibility, labels uuid[], custom jsonb, version int, created_at, created_by,
      deleted_at, deleted_by, deleted_source)
deal_stage_history(id, deal_id, stage_id, entered_at, left_at null, moved_by, source)
deal_participants(deal_id, person_id, added_by, added_at, pk(deal_id, person_id))
followers(record_type, record_id, staff_id, created_at, pk(...))
lost_reasons(id, label, position, active)                      -- plus setting lost_reason_required
notes(id, record_type, record_id, body, pinned bool, mentions uuid[], author_id, created_at, deleted_at)
products(id, name, code unique, unit, tax_rate numeric(5,2), billing_kind check(one_off|recurring|installments),
         billing_frequency text null, color, notes, custom, labels, owner_id, visibility, version, deleted_at)
product_prices(product_id, currency, unit_price numeric(14,2), origin check(manual|converted), as_of, pk(product_id, currency))
product_variations(id, product_id, name, currency, unit_price null, discount_pct null)
fx_rates(base, quote, rate numeric, as_of date)                 -- provider feed
deal_products(id, deal_id, product_id null, variation_id null, name_snapshot, quantity numeric, unit_price numeric, currency,
              discount_pct numeric(5,2), tax_rate, billing_kind, billing_frequency, cycles int null check <=208,
              installments int null, position)
score_rules(id, record_type, name, points int, predicate jsonb, active)
saved_filters(id, record_type, name, conditions jsonb, visibility check(private|shared), team text null, owner_id)
saved_filter_favorites(filter_id, staff_id)
view_prefs(staff_id null /* null = admin default */, record_type, key text, value jsonb)   -- columns, sort, show_closed, sidebar order, cal mode
activity_types(id, key, name, glyph, bg, border, position, active, is_system)
activities(id, org_id, type_id, subject, starts_at timestamptz null, all_day bool, duration_min int, priority check(high|medium|low),
           note text, done bool, done_at, done_by, deal_id null, lead_id null, person_id null, organization_id null, project_id null,
           video_provider null, video_url null, created_by_workflow_id null, owner_id, visibility, labels, custom, version, deleted_at)
activity_guests(activity_id, person_id null, email, name, response check(needs_action|accepted|tentative|declined), responded_at)
activity_reminders(id, activity_id, channel check(app|email|desktop|push), offset_min int, fire_at, fired_at, unique(activity_id, channel, offset_min))
reminder_prefs(staff_id pk, channels text[], default_offset_min int, daily_summary bool, next_step_prompt bool default true)
push_devices(id, staff_id, platform, token, label, created_at)
calendar_connections(id, staff_id, provider check(google|microsoft), account_email, calendar_id, calendar_name,
                     mode check(one_way|two_way), sync_type_ids uuid[], status, last_synced_at, sync_cursor, vault_secret_id)
calendar_event_links(activity_id, connection_id, external_id, etag, read_only bool, last_pushed_at, last_pulled_at)
calendar_sync_conflicts(id, connection_id, activity_id, detected_at, resolution)
booking_links(id, staff_id, slug unique, kind check(general|proposed), title, duration_min, buffer_min default 15, horizon_days,
              video_provider, person_id null, deal_id null, expires_at null, active)
booking_link_times(link_id, starts_at)
availability_rules(staff_id, weekday smallint, start_time time, end_time time)
bookings(id, link_id, person_id, starts_at, activity_id, created_at, cancelled_at)
deal_waitlist(id, payload jsonb, source, created_at, admitted_at)   -- only if a capacity limit is set (PIP-16)
```

**Triggers**
- Stage change maintains `stage_entered_at`, `deal_stage_history` and `last_activity_at`.
- Activity completion, note insert and email log bump `deals.last_activity_at`.
- Product line changes recompute `deals.value` when `value_source = 'products'`.
- Delete-stage reassigns deals to the target stage.
- Append-only history must permit FK cascades.

## D. RPCs (snake_case)

**Read:**
- `list_pipelines()`
- `get_pipeline_board(pipeline_id, filter jsonb, include_closed bool, per_stage_limit, cursors jsonb)` → stages with count, sum and card page; summary count, value and weighted value; capacity/waitlist.
- `list_deals(filter, sort jsonb[], columns text[], page)`
- `get_forecast(pipeline_id, bucket week|month|quarter, from, to, date_field, filter)`
- `list_archived_deals(page)`
- `list_deleted_deals(page)`
- `get_deal(id)` → summary, stage timeline, participants, followers, custom fields with quality, lines, revenue, score breakdown, focus.
- `list_deal_history(id, kind, cursor)`
- `list_products(filter)`
- `list_lost_reasons()`
- `list_saved_filters(record_type)`
- `get_view_prefs(record_type)`
- `list_activity_types()`
- `list_activities(from, to, owner_ids, type_ids, status, filter, sort, page)`
- `activity_tab_counts(owner_ids, type_ids)`
- `get_activity(id)`
- `list_booking_links()`
- `get_availability()`
- `get_free_slots(slug, from, to)` (public)
- `list_recent_bookings()`
- `get_reminder_prefs()`
- `get_calendar_connection()`
- `list_provider_calendars(connection_id)`

**Write:**
- *Pipelines and stages:* `upsert_pipeline`, `set_pipeline_card_fields`, `upsert_stage`, `reorder_stages(pipeline_id, ids[])`, `delete_stage(id, target_stage_id)`
- *Deals:* `create_deal(title, pipeline_id, …)`, `update_deal(id, patch, version)`, `move_deal_stage(id, stage_id, version, field_values jsonb)` → ok or `missing_required[]`, `set_deal_status(id, status, lost_reason_id, lost_reason_text, comment)`, `set_deal_labels`, `archive_deal`, `unarchive_deal`, `delete_deal`, `restore_deal`, `duplicate_deal(id)`, `bulk_update_deals(ids, patch)`, `bulk_delete_deals(ids, preview bool)`, `export_deals(filter, columns, format)`
- *Followers and participants:* `follow_record(record_type, id)`, `unfollow_record`, `add_deal_participant`, `remove_deal_participant`
- *Product lines and catalog:* `upsert_deal_product_line`, `delete_deal_product_line`, `upsert_product`, `set_product_price`
- *Admin lists and preferences:* `upsert_lost_reason`, `save_filter`, `delete_filter`, `toggle_filter_favorite`, `set_view_pref`
- *Notes and activities:* `create_note`, `create_activity`, `update_activity`, `reschedule_activity(id, starts_at, duration_min)`, `complete_activity(id, done bool)` → `{prompt_next: bool}`, `bulk_update_activities(ids, patch)`, `set_activity_guests`
- *Activity types:* `upsert_activity_type`, `deactivate_activity_type`
- *Scheduler:* `upsert_booking_link`, `set_availability_rules`, `book_slot(slug, starts_at, contact)` (public, atomic)
- *Reminders and sync:* `set_reminder_prefs`, `register_push_device`, `connect_calendar_start` / `connect_calendar_callback`, `update_calendar_connection`, `disconnect_calendar`, plus the jobs `run_calendar_sync` and `dispatch_reminders`

**Events (outbox):**
- Deals: `deal.created`, `.updated`, `.stage_changed`, `.won`, `.lost`, `.reopened`, `.archived`, `.unarchived`, `.deleted`, `.restored`, `.rotting`
- Records: `record.followed`
- Notes: `note.created`
- Activities: `activity.created`, `.updated`, `.rescheduled`, `.completed`, `.reopened`, `.deleted`
- Bookings and sync: `booking.created`, `calendar.sync_completed`
- Exports: `export.created`

**Notifications:**
- Followers on a stage change.
- The owner when a deal starts rotting.
- @mentions in notes.
- Reminders per channel.

**Rights the design implies:** deals.view, edit, create, delete, bulk_edit, export; settings.pipelines, labels, products, lost_reasons; activities.view_team, edit, bulk_edit.