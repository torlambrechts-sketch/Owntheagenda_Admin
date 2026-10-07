# Status of the screen requests

What the Phase 1 screen builders asked for, and what happened to each. «0023» is
`supabase/migrations/0023_screen_requests.sql`, proved by `supabase/tests/requests_invariants.sql`.
«Screen» means the database function exists and the screen still has to use it.

| Request | What | Status |
|---|---|---|
| Activities R-ACT-01 | `calendar_connection_save` | Done in 0023 · screen done |
| Activities R-ACT-02 | Proposed times on booking links | Done in 0023 (`proposed_times`, `booking_link_save`) · screen done |
| Activities R-ACT-03 | Reminders need the owner or edit-others (security) | Done in 0023 · screen done (a refusal after the save is reported) |
| Activities R-ACT-04 | Bookings name the organisation | Done in 0023 (`my_scheduling`) · screen done |
| Activities R-ACT-05 | `activities_shift` | Done in 0023 · screen done |
| Contacts R-1 | A note with an @mention was refused (bug) | Done in 0023 (route check accepts `?<entity>=<uuid>`); the screen sends mentions again (V-CONTACTS-30 removed) |
| Contacts R-2 | Import body above 1 MB | Done: `serverActions.bodySizeLimit` 8 MB, the screen's limit 7.9 MB; a 1.5 MB import verified |
| Contacts R-3 | XLSX import and export | Open: needs a library decision (exceljs) |
| Contacts R-4 | Lead numbers | Done in 0023 (`leads.seq` from 501); the lead panel shows «L-<seq>» (V-CONTACTS-08 removed) |
| Contacts R-5 | Person label colours in the seed | Done (seed generator, the design's colours); shown by the screen (V-CONTACTS-06 removed) |
| Contacts R-6 | Revertable bulk changes | Done in 0044 (`rec_bulk` logs before-values; `bulk_changes_get`, `bulk_change_revert` refuses rows changed since) · screen: Phase 8 |
| Customers R-01, R-02, R-06, R-07 | Orgpuls commands and events | Open: Orgpuls side (D-40) |
| Customers R-03 | Count keys in `counts.updated` | Open: Orgpuls side (D-21) |
| Customers R-04, R-05 | Invoice mirror, coupons | Open: with Stripe (D-22) |
| Customers R-08 | Health score | Phase 4 (health_scores) |
| Deals R-DEALS-01 | `deal_list` sorts by organisation, owner, labels | Done in 0023 · screen done |
| Deals R-DEALS-02 | OR groups and idle days in filters | Done in 0023 (`app.filter_sql`) · screen done |
| Deals R-DEALS-03 | `deal_to_lead` | Done in 0023 · screen done |
| Settings R-SETTINGS-01 | Currencies with Norges Bank rates | Open: needs an edge worker; with the worker deployment once hosted access returns (Q-01) |
| Settings R-SETTINGS-02 | Invitation e-mail | Open: needs the transactional e-mail provider (D-07) |
| Settings R-SETTINGS-03 | `sandbox_reset` | Done in 0044 (sample rows only, proved by phase8_platform_invariants) · screen: Settings › sandbox |
| Settings R-SETTINGS-04 | `entities_get` | Done in 0023; the screen uses it (Data fields chips, visibility defaults, plans, sandbox) |
| Settings R-SETTINGS-05 | Archived field keys | Done in 0023 (refused as `invalid`, detail `key`); the screen dropped the retry and says the key belongs to an archived field |
| Settings R-SETTINGS-06 | First day of the week | Left out (V-SETTINGS-16); Monday throughout |
| Tickets R-1 | A thread line for an executed action | Done in 0023 (`ticket_action_note`, needs the action in the audit); the screen writes and renders it |
| Tickets R-2 | Queue and edit checks on ticket writes (security) | Done in 0023 (update trigger, `ticket_link`); the screen words the queue refusal (`forbidden`/`queue`) |
| Tickets R-3 | Previous period ignored the product | Done in 0023 |
| Tickets R-4 | Product commands, status banner | Open: Orgpuls side (D-40) |
| Tickets R-5 | Ticket-to-article rate | Done in 0023 (`help_get.article_rate`); shown on the screen |
| Tickets R-6 | CSAT counted unanswered scores | Done in 0023 |
| Tickets R-7 | Initials, health, app version, attachments | Open: health in phase 4; attachments with storage |

Shared code the builders reported, fixed in the same change: the 2 px overflow at 390 px (V-15), `can()`
without the tickets scope, the toast's shadow, and the Overview failing for staff without Global › See.

## Phase 6 (0040)

«0040» is `supabase/migrations/0040_phase6_requests.sql`, proved by `supabase/tests/phase6_requests_invariants.sql`.

| Request | What | Status |
|---|---|---|
| Campaigns R-CAMPAIGNS-01 | Image upload (bucket + signer) | Open: storage and an edge function |
| Campaigns R-CAMPAIGNS-02..05 | Coupons, product-activity segment field, campaign language, template versions and restore | Done in 0040 · screen done |
| Projects R-PROJECTS-01, 03 | record-files signer, AI worker | Open: edge functions |
| Projects R-PROJECTS-02 | Whether the PDF worker runs | State done in 0040 (`pdf` provider, `project_pdf_status`) · screen done; the worker is open |
| Projects R-PROJECTS-04 | Template line day = start offset | Done in 0040 · screen unchanged (reads `preview[].day`) |
| Insights INS-01 / V-P6P-02 | Report entities project and campaign | Done in 0040 · screen done |
