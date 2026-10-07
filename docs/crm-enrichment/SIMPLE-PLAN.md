# Sentral Simple — plan (2026-10-07)

Source: Claude Design handoff «Sentral Simple» (`Sentral Simple.dc.html`, `SimpleCustomers`, `SimpleCRM`, `SimpleGrowth` +
`GrowthMarketing`, `SimplePlatform`). It replaces today's 24 routes with four sections. The backend (migrations 0001–0055)
stays; the simple interface is built on it. Rules unchanged: never fabricate data, zod at every boundary, en + no, the
design's rendering recreated exactly.

## Target

| Section | Route | Tabs |
|---|---|---|
| Customers | `/customers` | Accounts · Tickets and requests |
| CRM | `/crm` | Deals · Lists |
| Growth | `/growth` | Analytics · SEO · Marketing campaigns · Email and automation |
| Platform | `/platform` | Applications · Plans and prices · Team and roles |

Shell: 244 px rail (brand, application select, four sections with sub-labels, user footer), sticky header (product name and
description, page title, API status dot). `/` opens Customers.

## What is real today, and what is not

| Area | Works on today's backend | Has no writer or command yet → honest state |
|---|---|---|
| Accounts | list, search, status filter, MRR/ARR, paying, trials, trial→paid, open tickets, median first reply, plan, health, admin contact, log, **extend trial** | change plan, suspend/reactivate, send login link (no Orgpuls command) |
| Tickets | queues, status, assignee, priority (mapped to impact × urgency), thread, reply/note, canned replies (macros), approve «extend trial» | replies are stored, **not emailed** (no mail provider); approve for other request kinds |
| Deals | board, drag-drop, won/lost, drawer, notes, new deal | — |
| Lists | segments, counts, members, new list, CSV export | — |
| Analytics | signups, trial→paid, signups by source, funnel bottom (account, first survey, paying) | visitors, funnel top, landing pages (no web tracker); cost per customer only with spend typed in |
| SEO | — | everything (no Search Console connection); site health, content ideas and indexed pages are cut (no source) |
| Marketing campaigns | new table, UTM links, manual spend, signups by UTM | visits (tracker); pause cannot reach the ad platform |
| Email and automation | sequence editor on the workflow engine | nothing sends (no mail provider) |
| Applications | accounts per app, test connection, connect app, status message row, feature flags via `modules.*` | latency/errors (edge logging not wired), maintenance (no command), «rotate API key» in one click (breaks security rule 5 → show secret presence + owner intake flow) |
| Plans and prices | prices read from `plan_versions`, accounts per plan | saving prices, trial length, discount (Orgpuls owns checkout; no command) → read-only |
| Team and roles | list, role, remove/restore | invite creates the staff row but no login and no email |

## Phases

**S1 — Shell and Customers.** New nav (four sections, `?tab=`), rail and header from the design, app picker. Accounts and
Tickets from existing loaders/actions. Migration 0056: `tickets_get` view `requests`, `tickets.request` (structured service
request from `support.requested`), `simple_customers_summary`. Buttons without an Orgpuls command disabled with «Not
available in Orgpuls yet».

**S2 — CRM.** Deals board/drawer/modal and Lists from the existing deals and segment code, restyled to the design.

**S3 — Platform.** Applications (cards, test, connect, flags, status message, secret presence), Plans and prices
(read-only), Team and roles. Migration 0058 (roles part): the five roles Admin / Sales / Support / Marketing / Read-only
mapped onto today's permission sets with patched rights; Finance/Project folded in. Edge: `product-command` and
`orgpuls-events` log calls (latency/errors), status message pushed with `settings.set_notice`.

**S4 — Growth.** Migration 0057: `growth_overview` (7/30/90 d), `ad_campaigns` (+ spend and UTM joins), `seo_keywords` +
`seo_get`. Analytics and Marketing campaigns with honest empty states; SEO as «Connect Search Console» until connected.
Email and automation: the sequence editor compiled onto the workflow engine (0058 engine part), activation blocked until
email sends.

**S5 — Hide the old interface.** The 24 old routes leave the rail. Kept but reachable from the account menu as «Settings
and security»: privacy requests (30-day legal clock), MFA/sessions, profile and language, macro authoring, pipeline
setup, audit search, sandbox. Redirects for every old deep link (notifications link to `/tickets?ticket=`, `/deals?deal=`
…). Code for features with no place in Simple is removed in a later release, not now.

Each phase: gates (tsc, lint, i18n, vitest, SQL suites on a rebuilt DB, build), screenshots against the design at 1440 and
390 px, CI green, production verified.

## Needs outside the app (not code in this repo)

1. Orgpuls commands: `billing.change_plan`, `billing.suspend` / `reactivate`, `users.send_login_link`,
   `settings.set_maintenance`, later `billing.set_prices` (Orgpuls repo, D-40).
2. A mail provider and the mail worker (ticket replies, sequences, campaigns, invites).
3. The web tracker edge function (D-37) — most of Growth › Analytics depends on it.
4. Search Console connection (OAuth + daily ingest) for SEO.
