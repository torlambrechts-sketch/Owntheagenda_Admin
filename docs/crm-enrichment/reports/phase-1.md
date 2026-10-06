# Phase 1 report — the CRM core screens

Branch `build/sentral`. Built per D-01: everything new, on the Sentral design.

## What was built

| Screen | Design file | Route | Deviations |
|---|---|---|---|
| Customers: organisations, company detail, users, billing, support access, personvern | Customers.dc.html | `/customers` | 36 |
| Contacts and Leads: people, organisations, leads, lists, import and export | Contacts.dc.html | `/contacts`, `/leads` | 27 |
| Deals: pipeline, list, forecast, archive, catalogue, deal drawer and dialogs | Deals.dc.html | `/deals` | 17 |
| Activities: calendar, to-do, meeting scheduler, reminders and sync, edit dialog | Activities.dc.html | `/activities` | 25 |
| Tickets: inbox, problems, help centre, macros, reports, SLA and routing | Tickets.dc.html | `/tickets` | 23 |
| Settings, 11 sections | Settings.dc.html | `/settings` | 34 |
| Spec coverage | Coverage.dc.html | `/coverage` | 6 |

The deviations are in `docs/crm-enrichment/DEVIATIONS.md`, one section per screen, plus the shared V-01..V-24.
Most are figures the prototype invents. Each one is either computed from records or left out; no placeholder
looks like data.

## Database

- **Phase 1 schema** (`0009`–`0014`): deals, pipelines and stages; activities, reminders and booking links;
  leads, people and organisations; tickets, queues, SLA and help centre; customers and the overview.
- **0023** answers what the screen builders asked for. `requests/STATUS.md` lists every request with what
  happened to it: 19 done, 1 left out (first day of the week), and the rest open with a named cause.
- Two of the requests were security fixes:
  - Reminders can only be set by the owner or someone who may edit others' records.
  - Ticket writes are checked against the queues the staff member may see.
- Proved by the SQL suites: access 27, phase1 36, records 26, settings 15, structure 21, requests 18. All
  pass on a database rebuilt from migrations.

## Gates at the merge

- tsc, lint and verify:i18n pass. verify:i18n covered 2389 keys, en and no in agreement.
- vitest: 20 tests pass. `next build` passes.
- The visual comparison was run against the design at 1440 and 390 px.
- One shared defect was found and fixed: the header overflowed a 390 px screen by 2 px (V-15).

## Open

- **Hosted.** The Supabase MCP returns an authentication error, so the migrations are not applied to the
  hosted project and `main` waits (Q-01). Tor must reconnect the Supabase connector.
- **Orgpuls-side commands and events** (D-40, D-21), Stripe invoices and coupons (D-22), and XLSX
  (needs a library decision).
- **Waiting for later phases:**
  - The bulk-change revert log (phase 8).
  - Currency rates and invitation e-mail, which need edge workers and a mail provider once hosted access
    returns.
