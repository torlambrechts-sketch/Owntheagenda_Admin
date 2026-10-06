# Status of the screen requests

What the Phase 1 screen builders asked for, and what happened to each. «0023» is
`supabase/migrations/0023_screen_requests.sql`, proved by `supabase/tests/requests_invariants.sql`.
«Screen» means the database function exists and the screen still has to use it.

| Request | What | Status |
|---|---|---|
| Activities R-ACT-01 | `calendar_connection_save` | Done in 0023 · screen |
| Activities R-ACT-02 | Proposed times on booking links | Done in 0023 (`proposed_times`, `booking_link_save`) · screen |
| Activities R-ACT-03 | Reminders need the owner or edit-others (security) | Done in 0023 |
| Activities R-ACT-04 | Bookings name the organisation | Done in 0023 (`my_scheduling`) · screen |
| Activities R-ACT-05 | `activities_shift` | Done in 0023 · screen |
| Contacts R-1 | A note with an @mention was refused (bug) | Done in 0023 (route check accepts `?<entity>=<uuid>`) · screen: drop the workaround |
| Contacts R-2 | Import body above 1 MB | Done: `serverActions.bodySizeLimit` 8 MB, the screen's limit 7.9 MB |
| Contacts R-3 | XLSX import and export | Open: needs a library decision (exceljs) |
| Contacts R-4 | Lead numbers | Done in 0023 (`leads.seq` from 501) · screen |
| Contacts R-5 | Person label colours in the seed | Done (seed generator, the design's colours) |
| Contacts R-6 | Revertable bulk changes | Open: needs a bulk-change log; with the audit work in phase 8 |
| Customers R-01, R-02, R-06, R-07 | Orgpuls commands and events | Open: Orgpuls side (D-40) |
| Customers R-03 | Count keys in `counts.updated` | Open: Orgpuls side (D-21) |
| Customers R-04, R-05 | Invoice mirror, coupons | Open: with Stripe (D-22) |
| Customers R-08 | Health score | Phase 4 (health_scores) |
| Deals R-DEALS-01 | `deal_list` sorts by organisation, owner, labels | Done in 0023 · screen |
| Deals R-DEALS-02 | OR groups and idle days in filters | Done in 0023 (`app.filter_sql`) · screen |
| Deals R-DEALS-03 | `deal_to_lead` | Done in 0023 · screen |
| Settings R-SETTINGS-01 | Currencies with Norges Bank rates | Open: needs an edge worker; with the worker deployment once hosted access returns (Q-01) |
| Settings R-SETTINGS-02 | Invitation e-mail | Open: needs the transactional e-mail provider (D-07) |
| Settings R-SETTINGS-03 | `sandbox_reset` | Open: the production sandbox loader |
| Settings R-SETTINGS-04 | `entities_get` | Done in 0023; the screen uses it (Data fields chips, visibility defaults, plans, sandbox) |
| Settings R-SETTINGS-05 | Archived field keys | Done in 0023 (refused as `invalid`, detail `key`); the screen dropped the retry and says the key belongs to an archived field |
| Settings R-SETTINGS-06 | First day of the week | Left out (V-SETTINGS-16); Monday throughout |
| Tickets R-1 | A thread line for an executed action | Done in 0023 (`ticket_action_note`, needs the action in the audit) · screen |
| Tickets R-2 | Queue and edit checks on ticket writes (security) | Done in 0023 (update trigger, `ticket_link`) |
| Tickets R-3 | Previous period ignored the product | Done in 0023 |
| Tickets R-4 | Product commands, status banner | Open: Orgpuls side (D-40) |
| Tickets R-5 | Ticket-to-article rate | Done in 0023 (`help_get.article_rate`) · screen |
| Tickets R-6 | CSAT counted unanswered scores | Done in 0023 |
| Tickets R-7 | Initials, health, app version, attachments | Open: health in phase 4; attachments with storage |

Shared code the builders reported, fixed in the same change: the 2 px overflow at 390 px (V-15), `can()`
without the tickets scope, the toast's shadow, and the Overview failing for staff without Global › See.
