# Platform, new tabs — gap analysis (SimplePlatform › Rollouts and announcements · Billing portal · Customer success · Team · Roles and approvals)

Evaluator: platform, 12 Oct 2026. Design: `design-reference/sentral-simple/PlatformPlus.dc.html` (four views `ops`, `billing`,
`success`, `access`, mounted by SimplePlatform for those tabs) and the change in `SimplePlatform.dc.html` (the tab strip). Both
read in full, markup and `<script>` (every literal, every computed value, every button and what it pretends to do); the shell
`Sentral Simple.dc.html` and the shared `design-reference/sentral/project/admin-data.js` (bands, products, staff, `kr`, `pct`)
read for what the views use. Rendered at 1440 and 390 px, with interactions pressed (Widen → Roll back → Restart; Approve).
Screenshots: `/tmp/claude-0/-home-user/ebb42717-a6b5-52e0-a1e8-4cdc6ef4f4f9/scratchpad/v3/platform/*.png`.

Checked against: `app/(admin)/platform/` (page, AppsTab, PlansTab, TeamTab, actions, mail-actions), `lib/data/simple-platform.ts`,
`lib/platform/command.ts`, `supabase/functions/product-command`, `orgpuls-events`, `_shared/orgpuls.ts`, migrations 0001–0077
(0003, 0005, 0012, 0013, 0021, 0022, 0043, 0044, 0057, 0060, 0067 in detail), `docs/crm-enrichment/{SIMPLE-PLAN,DECISIONS}.md`,
`deviations/simple-platform.md`, `deviations/platform-schema.md`, the peer files `v3/dev-a-gap.md` and `v3/dev-b-gap.md`, the
local database (SELECT only), and — read only, to know what the product really has — the Orgpuls repository
(`/home/user/orgpuls`: migrations 0048, 0049, 0123, 0141, 0201, 0205–0208, 0227, 0228; `lib/flags.ts`, `lib/site/pricing.ts`,
`lib/shell/read.ts`).

Legend for the Verdict column

| Verdict | Meaning |
|---|---|
| **build** | Real on the existing backend or with a new migration in this repo (an existing connection such as Brevo counts as existing) |
| **build+connector** | Real once a connection we can build here exists (named) |
| **needs-orgpuls** | Needs an Orgpuls command or event, or Orgpuls repository work, that does not exist (named) |
| **needs-decision** | A product decision only Tor can make (named, D-PL-nn below) |
| **cannot** | Cannot be real (invented by nature, or forbidden by a rule). The honest rendering is named |

## Overview

**What changed in the design.** SimplePlatform's three tabs become seven: Applications · **Rollouts and announcements** · Plans
and prices · **Billing portal** · **Customer success** · Team · **Roles and approvals**. «Team and roles» is renamed «Team» (its
content is unchanged, role select included); the four new tabs are one new file, `PlatformPlus.dc.html`, picked by `view`.
Applications and Plans and prices are byte-for-byte unchanged (git diff of `e8a5565`).

**What the four new views pretend.** Everything in PlatformPlus is literal or local state: four rollouts of features in three
products with error and adoption percentages; an announcement whose «372 users» is `1240 × 0.3`; four accounts near a limit
whose «Raised · 58 %» is `p × 0.6`; four error rows; a billing portal for Lumio AS with card payment, three invoices and a
«38 % fewer billing tickets» claim; three refunds; a «68 %» failed-payment recovery with a card-retry dunning funnel; a seven-step
onboarding checklist with completion; an NPS of «+42» from «214 answers»; five feature requests with votes and «MRR asking»
(`mrr × 620`); four renewal signals; a 12 × 6 role matrix; four approval requests. No value has a source.

**What is true of the product (Orgpuls), and it shapes almost every verdict here.**
- **Feature flags** are code constants (`lib/flags.ts`, 22 names; on per deployment through `ORGPULS_FLAGS`, «each flag named on
  its own once someone has signed it off»). Several are gated by a DPIA, a badge sign-off or approved translations
  (`action_volunteers`, `measured_badge_public`, `locale_*`). There is **no runtime flag store, no per-organisation targeting and no
  percentage rollout**. What exists are *question modules* with one-organisation pilots (`modules.list`, `modules.pilot`,
  `modules.set_status`: draft → published → retired, one way) and language pilots (`locales.pilot`). Sentral's Applications
  «Feature flags» card already shows the modules (V-SPL-04).
- **The status message does not reach the app.** `settings.set_notice` sets Orgpuls' *site notice* (0123): «a notice on the public
  site's pages … It never replaces a page, never reaches the product or a survey». Sentral's Status message placeholder says
  «Shown at the top of the app for all users» (`messages/en/simple-platform.json` `notice.placeholder`) — a mislabel in today's
  build (finding F-1). Nothing reaches the signed-in product today, so «Announcement in the app» needs a new command.
- **Billing** (0048, 0201, 0227): plans `small` (Liten, ≤ 25, 265 kr), `usual` (Vanlig, ≤ 100, 565 kr), `group` (Flere selskaper,
  by agreement) and a free plan after the trial; a year costs 10 months (`app.annual_months()`); the trial is 15 days, fixed by
  an immutable function (`app.trial_days()`), extendable once; prices live in code (`lib/site/pricing.ts`, NOK and GBP) and «the
  database stores a plan and an interval, never an amount»; payment is **by invoice, e-mail or EHF — "nothing here holds a card
  or talks to a payment provider"**. No invoice, refund, credit note, discount or dunning concept exists. Invoices are made outside
  the product (op_org_get is «where the invoice is made»).
- **Events Orgpuls sends today** (its `app.platform_event_kinds`): `org.created`, `org.deleted`, `org.attribution`,
  `member.joined`, `member.left`, `billing.changed` (plan, interval, trial and cancellation dates, market — **no** price, seats,
  payment state or period end, although D-22 asked for price, currency and seats), `usage.daily` (employees, members,
  rounds_planned/open/closed, last_round_closed_at, last_sign_in_at), `support.requested`, `contact.submitted`,
  `demo.requested`, `template.requested`. Sentral's registry (0044) and projection trigger (0013) already *expect*
  `survey.round`, `counts.updated`, `milestone.reached`, `member.state` and `logins.daily` (D-21); **Orgpuls has not added them**.
- **Customer NPS has no source** (Orgpuls 0141: «Customer NPS has no source in the schema … says 'no_source'»). Orgpuls' eNPS
  (0035) is respondent data and must never come here.
- **Onboarding**: Orgpuls has a «Kom i gang» panel of four steps ticked from real rows (register, grupper, årshjul, måling;
  `lib/shell/read.ts`), not configurable, not reported to Sentral.
- **Mail**: Orgpuls' survey invitations go through the same Brevo account as Sentral's mail; Sentral's `mail-events` drops every
  event not tagged as Sentral's «before reading anything else» (0060, rule 6). Invitation delivery can only come from Orgpuls,
  as counts.
- **Other products**: Skiftly, Avvikspunkt and Kursrom are rows in `app.products` with no command path (`product-command`
  accepts `orgpuls` only), no event function and no repository (dev-a). Every design row about them is «cannot» until they exist.

**What Sentral has today that these tabs stand on.**

| Exists | Where | Use here |
|---|---|---|
| Permission sets of `scope:action` rights (deals, projects, campaigns, tickets, global × 11 actions), the five Simple roles (admin, sales, support, marketing, analyst = Read-only) offered, finance and project kept but not offered | 0003, 0012, 0057; `lib/data/settings-matrix.ts` | Roles matrix, Team role select |
| `app.require(scope, action)`, `app.can`, `app.require_fresh_mfa`, `app.log`, `app.notify`, `app.audit` (actor, product, command, arg_names, action, target, account, staff, reason, detail) | 0003, 0004, 0043 | Every new RPC; approvals |
| Setting `second_admin` (off) and the one two-person pattern: `privacy_jobs.approved_by <> created_by`, `privacy_approve` | 0005, 0043 | Approvals queue; today `runCustomerAction('delete')` with `second_admin = on` returns `approval_required` and nothing can approve it (a dead end) |
| `product-command`: signs a 2-minute token for one command; actor = the admin's address or `platform` (service role); audit by argument names | `supabase/functions/product-command` | Every product action. **It authorises any admin for any command** (`admin_whoami().admin`), see R-PL-1 |
| Orgpuls commands mirrored in `_shared/orgpuls.ts` / `app.product_commands` (orgs.*, billing.extend_trial/cancel*, translations.*, overrides.*, modules.*, locales.*, legal.*, settings.notice/set_notice/set_indexing) | 0044 | Rollouts (modules pilots only), trial extension, deletion |
| Events in: `ingest_events` (0067) → accounts, account_products, subscriptions, members, usage_daily; trigger `project_product_event` (0013) → product_survey_rounds, product_counts, activation_milestones (keys account_created, employees_uploaded, survey_scheduled, survey_sent, result_unlocked, results_viewed, first_tiltak, converted), members' login/MFA state | 0013, 0067 | Onboarding completion, band crossing, reach of an announcement |
| `plan_versions` (band_label, min/max employees, monthly/annual price), `plan_accounts` (subscriptions.plan = band_label) | 0013, 0057 | Billing portal plans, plan limits. Local seed matches the design's four bands; Orgpuls sends `small`/`usual`/`group` (finding F-2) |
| `subscriptions.payment_state` (ok, past_due, suspended), `current_period_end`, `price`, `seats` | 0008, 0067 | Not fed by Orgpuls (fields not in its registry) |
| `health_scores` (nightly), `mrr_tenant_daily`, `organizations.csm_id`, `deals`, `activities` (tasks), the workflow engine with product-event triggers | 0021, 0022, 0028, 0033 | Renewal signals, MRR asking, CSM tasks, «detractor → task» |
| Tickets with categories `billing`, `bug`, `feature_request`; `ticket_links`; problems | 0012, 0056 | Create ticket, feature-request evidence, billing-ticket counts |
| Brevo (transactional + marketing streams), mail worker, ticket-reply delivery status, campaign bounces | 0060, 0061 | «Notify about band», voters' e-mail, Sentral's own delivery errors per customer |
| `status_notices`, `status_notice_set`, `status_notice_push_result` | 0044, 0057 | The pattern for announcements (store, deliver, record outcome) |

**Headline.** Of the four new views, **Roles and approvals** is the one that can be made fully real in this repository (an
action registry with three-state policies per role, a two-person approval queue that executes the approved action, and —
required, not optional — authorisation inside `product-command`). **Customer success** is mostly buildable on Sentral's own data
(onboarding steps from usage/members, feature requests, renewal signals, deals and CSM tasks), with NPS and two milestones waiting
for Orgpuls. **Rollouts and announcements** is mostly Orgpuls work (a runtime flag store with staged targeting, flag metrics, an
in-app announcement command, error counts per organisation); Sentral can build the announcement composer with a real reach, the
employees-vs-band limit with «Notify», and the email half of «Errors per customer» now. **Billing portal** is mostly not real:
Orgpuls has no card, no invoices, no refunds and no dunning; what is real is the current plan, a credit-note register with
approvals, and — with an accounting connector Tor chooses — invoices.

## Tab strip (SimplePlatform change)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| TAB-01 Seven pills: Applications, Rollouts and announcements, Plans and prices, Billing portal, Customer success, Team, Roles and approvals | `setState({tab})`; `plusView` mounts PlatformPlus for ops/billing/success/access | — | Three links (`SIMPLE_PLATFORM_TABS = ['apps','plans','team']`, V-SPL-01) | build | Extend the enum and `HREF` (`?tab=ops|billing|success|access`), i18n `simplePlatform.tabs.*` en + no; at 390 px seven pills wrap to four lines (the design's own wrap) |
| TAB-02 «Team and roles» → «Team» | Label only; content unchanged | — | `tabs.team = "Team and roles"` | build | Rename the string (en + no) |
| TAB-03 Toast | `flash()` 2.4 s, one per view | — | `useAct().flash` | build | Reuse |

## Applications (unchanged in this handoff)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| APP-01 Application cards: initial, name, description, status pill, accounts | Seed | Products, accounts per product, health | Built (`loadAppsTab`, V-SPL-15) | build | — |
| APP-02 Response and errors | Seed `182 ms`, `0,2 %` | `integration_calls` | «—» (V-SPL-02): product-command and orgpuls-events do not log calls | build | `product-command`/`orgpuls-events` → `worker_integration_call` (platform-schema «Edge workers still needed») |
| APP-03 Test connection | Toast with seeded latency | A real call | Built (orgs.list, Orgpuls only) | build | — |
| APP-04 Maintenance mode | Toggle | `settings.set_maintenance` | Disabled (V-SPL-03) | needs-orgpuls | `settings.set_maintenance` |
| APP-05 ＋ Connect an application | Toast | `application_connect` | Built (owner, fresh MFA, intake) | build | — |
| APP-06 Feature flags · Orgpuls | Five invented flags | The product's flags | Built on question modules (V-SPL-04) | build | When `flags.list` exists (OPS-03) this card should show runtime flags at 100 % and the Rollouts card the rest (D-PL-04) |
| APP-07 API key + Rotate | `sk_live_…`, new key in one click | — | Secret presence; Rotate disabled (V-SPL-05) | cannot | Rule 5; keep as built |
| APP-08 Status message | «Shown at the top of the app for all users» | Delivery into the app | Built on `settings.set_notice`, **which reaches only Orgpuls' public site** | build | **F-1:** relabel now («Shown on Orgpuls' public website», en + no); the in-app message is OPS-21's command |

## Plans and prices (unchanged in this handoff)

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| PLN-01 Plan cards: band, accounts, price | Seed bands | Catalogue, accounts per plan | Read-only (V-SPL-07/09) | build | **F-2:** `plan_accounts` matches `subscriptions.plan = band_label`; Orgpuls sends `small`/`usual`/`group`, so on real data every count is 0. Add `plan_versions.plan_key` (D-PL-08) |
| PLN-02 Editable prices, «Save prices» | Toast | `billing.set_prices` | Disabled | needs-orgpuls | Prices are code in Orgpuls (`PLAN_PRICES`, NOK and GBP): a command, or Sentral reads `billing.plans` |
| PLN-03 Trial length 14 / 30 / 45 | Select | — | «—» | needs-decision | Orgpuls fixes 15 days in an immutable function («so no row can change the length»): changing it is an Orgpuls X-entry; Sentral shows «15» once `billing.plans` reports it |
| PLN-04 Annual discount | Select | `annual_months` | Derived from the catalogue | build | Changing it is Orgpuls (`app.annual_months()` immutable, 10) |
| PLN-05 Names Small/Medium/Large/Enterprise, included lines | Literal | Plan names, entitlements | Band as title (V-SPL-08) | needs-decision | Orgpuls' names are Liten / Vanlig / Flere selskaper (+ free); no entitlements exist (D-PL-08) |

## Rollouts and announcements (`view = ops`)

Screens: `rollouts-and-announcements.png`, `rollouts-after-clicks.png` (Widen → Roll back → «Restart», grey stages),
`rollouts-and-announcements-390.png`.

### Gradual rollouts

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| OPS-01 Card «Gradual rollouts» | Static | — | — | build | — |
| OPS-02 «Rolls back automatically if the error rate doubles» | Static claim | A guard: per-flag error rate with and without the flag, a threshold, a job that rolls back | Nothing | needs-decision | D-PL-05 (may a machine roll back production, where the guard lives, ×2 of what baseline, minimum volume). Until a guard runs, the line is not shown |
| OPS-03 Rollout rows: feature name, application | `RO` literal: New results dashboard, Pulse surveys (Orgpuls), Shift swap marketplace (Skiftly), Photo upload on mobile (Avvikspunkt) | The product's runtime flags with their stage | Orgpuls flags are code constants; question modules have pilots | needs-orgpuls | `flags.list` (flags:read) returning `{key, name, stage, pilot_orgs, eligible, changed_at}`; Orgpuls must move rollable flags to a runtime store (D-PL-04). Interim (decision): question modules can show Internal (draft) → pilots (`modules.pilot`) → 100 % (published), without % stages |
| OPS-04 Rows for Skiftly, Avvikspunkt | Literal | Their flags | No connection, no repo | cannot | Only connected products are listed; the application select scopes the card |
| OPS-05 «errors 0,3 %» | Literal | Error rate of requests touched by the flag | Nothing | needs-orgpuls | Event `flags.daily` (better `flags.hourly` for a guard): per flag `{flag, stage, orgs_on, orgs_using, requests, errors}`, product-wide counts only |
| OPS-06 «adoption 61 %» / «adoption —» | Literal | Organisations using the feature ÷ organisations that have it | Nothing | needs-orgpuls | Same event (`orgs_using / orgs_on`); «—» when `orgs_on = 0`. Counts of organisations, never of respondents or groups (R-PL-5) |
| OPS-07 Stage bar: Internal · 1 pilot org · 5 % · 25 % · 50 % · 100 % (done teal, current yellow, future beige, all beige after a roll back) | From `stage` | Stage | — | needs-orgpuls | Rendering is build; the stage comes from `flags.list`. At 390 px the six 26 px segments truncate their labels: show the current stage's name above a label-less bar (deviation) |
| OPS-08 «Widen to <next stage>» | `stage + 1`, toast «X now at Y» | A command | Nothing | needs-orgpuls | `flags.set_stage(p_flag, p_stage, p_reason)` (flags:write); stages as data (`internal`, `pilot`, `pct_5`, `pct_25`, `pct_50`, `all`); % = a deterministic bucket of the organisation id in Orgpuls. Right «Change feature flags and rollouts» (ACC-11; Ops = approval) |
| OPS-09 Which «1 pilot org» | Implied | An organisation | `modules.pilot` exists for modules only | needs-orgpuls | `flags.pilot(p_flag, p_org, p_on, p_reason)`; gap in the design: an organisation picker when widening to «1 pilot org» (D-41) |
| OPS-10 «Roll back» | Greys all stages, toast «rolled back for everyone» | A command | Nothing (module retire is one way) | needs-orgpuls | `flags.set_stage(…, 'off')`; asks a reason; never «for everyone» unless the reply says so |
| OPS-11 «Fully rolled out» (teal, inert) | `s >= 5` | Stage | — | build | From the stage |
| OPS-12 «Restart» after a roll back | Back to Internal | A command | — | needs-orgpuls | `flags.set_stage(…, 'internal')` |
| OPS-13 Toasts | Local | Command reply | `useAct` | build | Toast the product's answer (or its error code), as Applications does |
| OPS-14 Automatic roll back (behaviour behind OPS-02) | Not modelled | Hourly flag metrics, guard settings, a job calling the command as `platform` | product-command's service-role actor exists | needs-decision | D-PL-05; if Sentral-side: `app.rollout_guards` + job `rollout_guard` (every 15 min) that may only move a flag *down* (R-PL-7) |

### Announcement in the app

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| OPS-15 Card «Announcement in the app» | Static | — | — | build | — |
| OPS-16 Textarea, prefilled «Nytt: pulsundersøkelser med fem spørsmål. Prøv dem under Målinger.» | `setState(ann)` | Text (no and en: Orgpuls' notice takes both) | `status_notices` pattern | build | `app.announcements` draft; empty by default (the prefill is example copy); length and languages per D-PL-06 |
| OPS-17 Chip «All products» | Toggle; reach × 2 400 | Every product's users | Only Orgpuls is reachable | cannot | Not rendered while only one product has a command path; chips list connected products |
| OPS-18 Chips «Orgpuls», «Admins», «Trial» | Toggles | Audience: product, customer-user role, subscription state | `app.members` (role daglig_leder / avdelingsleder / verneombud, active), `subscriptions` (trial dates, confirmed_at, free_from) | build | Audience as data `{roles[], access[]}`; «Admins» must be defined (daglig leder only? every customer user is an admin of their organisation) — D-PL-06 |
| OPS-19 «Preview:» box | Echoes the text | — | — | build | Ideally Orgpuls' banner style; text only |
| OPS-20 «Publish · 372 users» (reach) | `(1240 or 2400 or 600) × 0.3 × 0.25` | Count of active customer users matching the audience | `members ⨝ account_products ⨝ subscriptions` | build | `announcement_reach(p_product, p_audience)` → count; «≈» because the mirror can lag; or Orgpuls' own count via `announcements.reach` |
| OPS-21 Publish into the product | Toast only | A command that shows a message to signed-in customer users | `settings.set_notice` reaches the public site only (F-1) | needs-orgpuls | `announcements.publish(p_id, p_no, p_en, p_roles[], p_access[], p_starts_at, p_ends_at)` and `announcements.withdraw(p_id)` (new scope `announcements:write`); never shown in the survey/respondent flow. Outcome recorded like `status_notice_push_result` |
| OPS-22 Toast «Announcement live for N users» | Local | Reply | — | build | After OPS-21; N = the reach at publish |

### Accounts near a plan limit

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| OPS-23 Card header, «Warn at 80 %» | Static | Threshold | — | build | Setting `plan_limit_warn_pct` (80) — value per D-PL-07 |
| OPS-24 «Bergheim Bygg AS · Employees 96 of 100 in band», bar 96 %, «96 %» | Literal | Latest employees per tenant ÷ plan maximum | `usage_daily.data.employees` (Orgpuls sends it daily); plan maximum from `plan_versions.max_employees` | build | Needs `plan_versions.plan_key` (F-2) so `small` → 25 and `usual` → 100; `group` has no maximum (never listed) |
| OPS-25 «Fjellheim skole · Admins 3 of 3» | Literal | A limit on admins per plan | No such limit exists in Orgpuls; the design's «1 admin / 3 admins / 10 admins» are invented (V-SPL-08) | needs-decision | D-PL-07 (do limits other than headcount exist?); then counts are build (members by role) and the limit is Orgpuls' |
| OPS-26 «Lumio AS · SMS invitations 410 of 500 / month» | Literal | SMS sent this month, a monthly cap | Orgpuls sends SMS invitations (0033) with no cap; no count is reported | needs-orgpuls | `usage.daily` + `sms_sent_month` (a count; recipients are respondents, so a count only) and a cap (D-PL-07) |
| OPS-27 «Tveit Omsorg AS · Storage 4,3 of 5 GB» | Literal | Storage used, a cap | No quota in Orgpuls | needs-orgpuls | `usage.daily` + `storage_bytes` and a cap (D-PL-07) |
| OPS-28 Bar colour (≥ 95 % red, else amber) | `p >= 95` | — | — | build | Same rule |
| OPS-29 «Notify about band» | Toast «… · logged on the account» | The customer's billing contact or daglig leder; a mail | Brevo transactional stream (0060); `members` (`is_billing_contact` needs `member.state`, else role daglig_leder) | build | `limit_notify(p_org, p_metric)` queues a templated mail (en/no) and an audit row (`customer.limit_notified`); wording by Tor |
| OPS-30 «Raise to 5 / 1 000 / 10 GB» | Toast, row turns «✓ Done» | A command that changes a limit | None | needs-orgpuls | `limits.set(p_org, p_metric, p_value, p_reason)` (billing:write), only if D-PL-07 creates limits |
| OPS-31 After raising: bar 60 %, «Raised · 58 %» | `p × 0.6` | — | — | cannot | Invented arithmetic; honest: re-read usage ÷ new limit from the reply, or «Raised to N» |
| OPS-32 Toast «<cta> · logged on the account» | Local | Audit | `customer_action_log` | build | — |

### Errors per customer · last 24 h

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| OPS-33 Header and «From the application error logs and email delivery» | Static | — | — | build | Names the real sources only («From Orgpuls' error counts and Sentral's mail») |
| OPS-34 «Mørkved IT AS · PDF export timed out twice · 2» | Literal | Application errors per organisation as codes and counts | Nothing (no Sentry, no error event) | needs-orgpuls | Event `errors.hourly` per organisation `{code, count}` from a code registry Orgpuls owns (`pdf_export_timeout`, …); the line text from a message key per code. Never messages, stack traces or payloads (R-PL-2) |
| OPS-35 «Lumio AS · 14 invitations held by mail server (451) · 14» | Literal | Invitation deliveries deferred/bounced per organisation | Orgpuls' invitations share Brevo; Sentral drops those events by design | needs-orgpuls | Counts from Orgpuls (`errors.hourly` code `mail_deferred_451`, or `survey.round` delivered/bounced). Never read from Brevo (R-PL-3) |
| OPS-36 Sentral's own mail to a customer failing (ticket replies, campaigns) | Implied by «email delivery» | Delivery failures by organisation, 24 h | `ticket_messages.delivery_status / mail_error`, `campaign_recipients.bounced_at / bounce_kind / failure_code` (→ person → organisation) | build | `customer_errors(p_product, p_hours)` merges these rows with OPS-34/35 |
| OPS-37 «Skiftly · Hamnvik Fiskeri · Calendar sync 504 from provider · 38» | Literal | — | Skiftly not connected | cannot | No row |
| OPS-38 Count with colour (> 10 rust, > 0 amber, 0 green) | Literal thresholds | — | — | build | Same thresholds |
| OPS-39 «Solstrand Helse AS · No errors · 0 · —» | Literal | — | — | build | List accounts with errors only, plus «No errors in 24 h for N other accounts» (a 0-row per account is noise) |
| OPS-40 «Create ticket» → «✓ Ticket open» | Local | A ticket on the organisation | `rec_save('ticket')`, category `bug`, queue support | build | `error_ticket_create(p_org, p_product)`: body generated from codes, counts and the window; «✓ Ticket open» when an open ticket from this source exists (dedupe) |
| OPS-41 Toast «Ticket created with the error log attached» | Local | — | — | cannot | No log is attached (rule 6/7: a log can carry a respondent's words); honest toast «Ticket created with the error counts» |

## Billing portal (`view = billing`)

Screen: `billing-portal.png`, `billing-portal-390.png`.

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| BIL-01 Card «Self-service billing · Lumio AS», «What the customer sees in Innstillinger → Abonnement», «Preview» chip | Fixed account, literal | An account, the product's own billing page | Orgpuls' page is «Oppsett › Betaling» (save_billing: plan, interval, invoice e-mail, reference, EHF, VAT) | needs-decision | D-PL-09: what this tab is for. If a preview: an account picker (gap, D-41), the page's real name, and only what Orgpuls offers |
| BIL-02 «Abonnement · 26–100 ansatte · 565 kr/mnd» | Literal | The account's plan, interval, price in its market's currency | `subscriptions.plan`, `billing_interval`; Orgpuls sends no price | build | With `plan_key` (F-2) and the catalogue; GBP for UK accounts (`market` in billing.changed, 0228 — Sentral does not store it yet) |
| BIL-03 Plan buttons «1–25 265 kr», «26–100 565 kr», «101–250 1 190 kr», «251–500 2 290 kr» | `D.bands` | The product's catalogue | `plan_versions` (local seed = the design's four bands) | needs-decision | Orgpuls sells Liten/Vanlig/Flere selskaper (+ free); 101–250 and 251–500 do not exist there (D-PL-08); best: Orgpuls `billing.plans` (billing:read) so Sentral never keeps a second price list |
| BIL-04 Picking a plan | Local highlight | — | — | build | Preview only, labelled; a real change is `billing.change_plan` (needs-orgpuls, also ACC-07) |
| BIL-05 Payment «Card» | Segmented toggle | Card payments | Orgpuls has none (0048: «nothing here holds a card»); Stripe waits (D-22) | cannot | Not rendered |
| BIL-06 Payment «EHF invoice» (and e-mail invoice) | Toggle | The account's invoice channel | `app.billing.ehf` in Orgpuls, not sent | needs-orgpuls | `billing.changed` + `ehf` (or `invoice_channel`); shown read-only («Invoiced by EHF» / «by e-mail») |
| BIL-07 Invoices «INV-40161 · 1 Oct · 706 kr» ×3 | Literal | Invoice number, date, amount | No invoice exists in Orgpuls or Sentral | build+connector | Accounting system API (Fiken / Tripletex / PowerOffice Go / Visma eAccounting — D-PL-10), read-only mirror `app.invoices`; credentials by `secret-intake` purpose `accounting` |
| BIL-08 «PDF» link | `href="#"` | The invoice PDF | — | build+connector | Same connector; a short-lived signed URL through an edge function, never stored |
| BIL-09 «Billing tickets dropped 38 % after the portal launched» | Literal | — | Tickets with category `billing` exist | cannot | A causal claim with no launch; honest: «Billing tickets, last 30 days: N (previous 30: M)» — build from `tickets` |
| BIL-10 «Refunds and credit notes», «Over 2 000 kr needs approval» | Static | Threshold | — | build | Setting `credit_note_approval_over` (2 000 kr) — value per D-PL-10 |
| BIL-11 Rows: organisation, reason, amount | Literal ×3 | A credit-note register | Nothing | build | `app.credit_notes` (requested → approved → issued / rejected) and `credit_note_request`; gap: «Request credit note» on the account (D-41) |
| BIL-12 Status «Waiting for approval» (tied to approval a1) | `st.apr.a1` | The approval's state | — | build | `credit_notes.approval_id` → ACC queue |
| BIL-13 Status «Refunded» / «Credit on next invoice» | Literal | Whether the accounting system issued it | No payment or invoicing in Sentral or Orgpuls | needs-decision | D-PL-10: issued by hand in the accounting system and marked here (`credit_note_mark_issued(p_id, p_ref)`), or through the connector. Never «Refunded» on Sentral's word alone |
| BIL-14 «Failed payments recovered · 30 days · 68 % · 17 of 25 failed payments · 12 002 kr saved» | Literal (`17 × 706`) | Card payment failures and retries | No card payments | cannot | Not rendered; if D-PL-10 adds a connector: «Overdue invoices» (count, amount) from it |
| BIL-15 Dunning rows: retry day 1 (9), e-mail with card link (6), switched to EHF (2), not recovered → suspended (8) | Literal | A dunning process | None; `subscriptions.payment_state` exists but Orgpuls never sends it | cannot | Not rendered |

## Customer success (`view = success`)

Screen: `customer-success.png`, `customer-success-390.png`.

### Onboarding checklist

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| SUC-01 Header, «Shown in the app · completion by step» | Static | — | — | build | Subtitle «completion by step» only, until SUC-10 is real |
| SUC-02 «Create account 100 %» | Literal | Accounts in the cohort | `account_products` (org.created) | build | 100 % by definition; kept as the base row |
| SUC-03 «Upload employee list 88 %» | Literal | Accounts whose employees > 0 ever | `usage_daily.data.employees`; milestone `employees_uploaded` when sent | build | `onboarding_completion` |
| SUC-04 «Invite HR and leaders 64 %» | Literal | Accounts with a second customer user | `members` (`member.joined`, roles avdelingsleder / verneombud) | build | Definition per D-PL-13 |
| SUC-05 «Schedule first survey 74 %» | Literal | Accounts that ever planned a round | `usage_daily.data.rounds_planned` (or open/closed) > 0; milestone `survey_scheduled` | build | — |
| SUC-06 «Send first survey 69 %» | Literal | Accounts that ever opened a round | `usage_daily` rounds_open + rounds_closed > 0; milestone `survey_sent` | build | — |
| SUC-07 «View results 57 %» | Literal | Results viewed | Milestone `results_viewed` expected (0013), not sent | needs-orgpuls | Event `milestone.reached` (D-21) with `results_viewed` |
| SUC-08 «Create first tiltak 44 %» | Literal | First tiltak | Milestone `first_tiltak` expected, not sent | needs-orgpuls | Same event, `first_tiltak` |
| SUC-09 Completion bars and percentages | Literal | Numerator ÷ cohort | — | build | Cohort per D-PL-13 (recommended: accounts created in the last 180 days, product = the picker's) |
| SUC-10 Checkbox per step, struck through when off; «Untick a step to hide it from the in-app checklist» | Local toggle | The product's in-app checklist and a command | Orgpuls «Kom i gang» has four fixed steps (register, grupper, årshjul, måling) | needs-orgpuls | `onboarding.steps` (settings:read) and `onboarding.set_visible(p_step, p_on)` (settings:write), after D-PL-13 decides the steps. Until then no checkbox, no footnote |

### NPS

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| SUC-11 «+42» | Literal | Customer users' 0–10 answers, 90 days | Orgpuls: «Customer NPS has no source» (0141) | needs-orgpuls | An in-app prompt to customer users and event `nps.answered {score, role}` per organisation; `app.nps_responses`. Never eNPS (R-PL-4) |
| SUC-12 «214 answers · +5 vs last quarter» | Literal | Count; previous 90 days | — | needs-orgpuls | Same; «—» for the comparison until two windows exist |
| SUC-13 Bar and legend «Promoters 56 % · Passives 30 % · Detractors 14 %» | Literal widths | Shares | — | needs-orgpuls | Same |
| SUC-14 «Asked in the app every 90 days» | Static | The product's cadence | — | needs-decision | D-PL-12 (ask at all, who: daglig leder only?, cadence, a free-text «why» or not) |
| SUC-15 «Detractors automatically create a task for the customer success manager» | Static claim | Workflow on the event | Workflow engine with product-event triggers; `organizations.csm_id`; activities | build | Template `nps_detractor`: `nps.answered` score ≤ 6 → task for the CSM (owner fallback per D-PL-15); shown only when the workflow is active |

### Feature requests

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| SUC-16 Header, «Votes from customers · linked tickets and deals» | Static | — | — | build | — |
| SUC-17 Request rows (title) | `RQ` literal ×5 | A request store | Tickets of category `feature_request` only | build | `app.feature_requests` — **shared with dev-a** (one definition, built once); gap: «Create request» from a feature-request ticket (D-41) |
| SUC-18 Vote button ▲ N (toggles one vote) | Local +1 | Votes | — | needs-decision | D-DEV-05 / D-PL-14: staff record a vote on behalf of an organisation (recommended: one per organisation) — then build `feature_request_votes` |
| SUC-19 «6 tickets» | Literal | Linked tickets | `ticket_links`, tickets | build | `feature_request_links (kind ticket)` |
| SUC-20 «2 deals» / «—» | Literal | Linked deals | `deals` | build | `feature_request_links (kind deal)` |
| SUC-21 «8 680 kr MRR asking» | `mrr × 620` | MRR of distinct accounts behind votes, tickets and deals | `mrr_tenant_daily`, `subscriptions` | build | Computed in the definer read under the MRR's own right (R-PL-10) |
| SUC-22 Status select: Under review · Planned · In progress · Shipped · Not planned, coloured | Local | Status | — | build | `feature_request_set_status`, audited |
| SUC-23 Shipped → «N voters emailed · added to the changelog», footnote | Toast | Voters' addresses; a changelog | Brevo exists; no changelog (dev-a D-DEV-13) | needs-decision | D-PL-14: mail as a service message to the people who asked (consent basis), and where the changelog lives; then build via Brevo |

### Renewal and expansion

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| SUC-24 Header «Renewal and expansion · Next 60 days» | Static | Window | — | build | Definition per D-PL-15 |
| SUC-25 «Bergheim Bygg AS · 96 employees · will cross into 101–250 · Expansion» | Literal | Employees vs plan maximum | `usage_daily`, plan maximum | build | `renewal_signals`; the next plan is Orgpuls' (after `usual` comes `group`, by agreement — not «101–250»), F-2 |
| SUC-26 «Lumio AS · Trial of Skiftly · 48 shift workers · Cross-sell» | Literal | Skiftly's trials and staff | Skiftly not connected | cannot | No row |
| SUC-27 «Kvamme Regnskap AS · Logins −60 % · renews in 34 days · At risk» | Literal | Logins trend; renewal date | `logins.daily` expected (0044), not sent; `current_period_end` not sent | needs-orgpuls | `logins.daily` and `billing.changed + current_period_end`. Interim build: health-score drop (`health_scores`) and «No sign-in for N days» (`usage_daily.last_sign_in_at`) |
| SUC-28 «Strandby Hotell AS · Uses Orgpuls only · 80 shift staff · Cross-sell» | Literal | Shift staff | No source | cannot | «80 shift staff» invented; «Uses Orgpuls only» is real but meaningless until another product is sold — no row |
| SUC-29 Kind label (At risk rust, others green) | Literal | — | — | build | — |
| SUC-30 «Create deal» → «✓ Created», toast «Expansion deal created in CRM» | Local | A deal | `rec_save('deal')` | build | Prefilled organisation and title; pipeline per D-PL-15; «✓ Created» when an open deal from this signal exists |
| SUC-31 «CSM task» → «✓ Created», toast | Local | A task to the CSM | `activities`, `organizations.csm_id` | build | Owner fallback when no CSM (D-PL-15) |
| SUC-32 Toasts | Local | — | — | build | — |

## Team (`tab = team`, unchanged content)

Screen: `team.png`, `team-390.png`.

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| TEAM-01 Tab label «Team» | Renamed | — | «Team and roles» | build | TAB-02 |
| TEAM-02 Invite field and «Invite» | Adds «Invited» row | Staff row + invitation | Built (`inviteStaff`, Brevo invitation, V-SPL-12) | build | — |
| TEAM-03 Person, Role, Last active columns | Seed | `staff_list` | Built (V-SPL-13, V-SPL-17) | build | — |
| TEAM-04 Role select: Admin · Sales · Support · Marketing · Read-only | Local | Permission sets | Built (0057, V-SPL-11) | needs-decision | **The design contradicts itself:** Roles and approvals has Super-admin · Support · Billing · Ops · Sales · Read-only (no Marketing). D-PL-01 |
| TEAM-05 Last active | Seed | `last_seen_at` | Built | build | — |
| TEAM-06 Remove / Restore | Local dim | `saveStaff({active})` | Built (V-SPL-14) | build | — |
| TEAM-07 Legend «Admin: everything · Sales: CRM · …» | Static | — | Built | build | Follows D-PL-01 |

## Roles and approvals (`view = access`)

Screens: `roles-and-approvals.png`, `roles-approved.png` (Approve → «✓ Approved by Tor», «3 open»), `roles-and-approvals-390.png`.

### Admin roles

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| ACC-01 Header «Admin roles», legend «✓ allowed · A needs approval · – not allowed» | Static | — | — | build | — |
| ACC-02 Six columns: Super-admin, Support, Billing, Ops, Sales, Read-only | `roleHead` | Permission sets | Admin, Sales, Support, Marketing, Read-only offered; Finance, Project not offered | needs-decision | D-PL-01: Billing = re-offered Finance? Ops = a new set? Where is Marketing? |
| ACC-03 «View accounts and users» | `YYYYYY` | Right | `global:see` | build | Action `accounts.view` mapped to `global:see` |
| ACC-04 «Reply to tickets» | `YYY-Y-` | Right | `tickets:see` (own/assigned), `tickets:edit_others` | build | Action `tickets.reply` |
| ACC-05 «Extend trial» | `YYA-Y-` | Right per role, approval for Billing | Any admin can run it (product-command checks only «is admin»; `customer_action_log` needs `global:see`) | build | Action `trial.extend` (command `billing.extend_trial`), enforced in product-command (R-PL-1) |
| ACC-06 «Request support access» | `YY----` | Right | `access_request` needs `global:add`; the product half (customer approves) is not live (D-40) | build | Action `support_access.request` |
| ACC-07 «Change plan or price» | `YAY-A-` | A command | None | needs-orgpuls | `billing.change_plan(p_org, p_plan, p_interval, p_reason)` (SIMPLE-PLAN «Needs»); prices: `billing.set_prices` or none (PLN-02) |
| ACC-08 «Refund or credit note» | `Y-A---` | A credit-note register | None | needs-decision | D-PL-10, then BIL-11 |
| ACC-09 «Discount over 20 %» | `Y-A-A-` | A discount on a subscription | `coupons` table (0013), unused; Orgpuls has no discount | needs-orgpuls | `billing.set_discount(p_org, p_percent, p_months, p_reason)` if D-PL-11 says discounts exist; threshold 20 % a setting |
| ACC-10 «Delete account or user data» | `A-----` | Policy | `orgs.delete_now` (server action: permission kind admin, typed org.nr, `second_admin` refuses); privacy erasure (`privacy_jobs`, `privacy_approve`) | build | Action `account.delete` covers both; the queue replaces `second_admin`'s dead end (R-PL-13) |
| ACC-11 «Change feature flags and rollouts» | `Y--A--` | Right | `global:configure` (modules.set_status) | build | Action `flags.change` |
| ACC-12 «Publish announcements» | `YY-Y--` | Right | `global:configure` (status notice) | build | Action `announcements.publish` (status message and announcements) |
| ACC-13 «Export customer lists» | `YAY-A-` | Right, approval | `<scope>:export` + `export_log` (CSV built in the server action) | build | Action `customers.export`; an approved export runs as a job into storage (0052) and is downloadable once by the requester |
| ACC-14 «Manage admin roles» | `A-----` | Right, approval even for Super-admin | `global:security` (`staff_save`, permission sets) | build | Action `roles.manage`; with one person holding it, «A» deadlocks (D-PL-02) |
| ACC-15 Cell click cycles ✓ → A → – | Local | A policy per action × role | — | build | `app.action_policies`; a change is itself `roles.manage` (approval), fresh MFA, audited before/after |
| ACC-16 «Super-admin and Billing require two-factor login with a security key» | Static | WebAuthn factor; per-role check of the session's method | TOTP only (D-11); `config.toml` has WebAuthn MFA commented out | needs-decision | D-PL-03 (amend D-11). Then: enable WebAuthn, check `amr` method in `app.is_admin` path for those roles |
| ACC-17 «all actions are logged · click a cell to change it» | Static | — | `app.audit` | build | True once ACC-15 exists |

### Waiting for approval

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| ACC-18 Header, «A second person must approve · N open» | `pendingN` | Open requests | — | build | `approvals_list` |
| ACC-19 Row: title, «Requested by …», relative time, «reason: …», amount | Literal ×4 | Request store | — | build | `app.approval_requests`; title from a message key per action with ids/counts/amounts, the reason typed by the requester |
| ACC-20 «Refund 3 390 kr to Kvamme Regnskap AS» | Literal | Credit note | — | needs-decision | D-PL-10 |
| ACC-21 «Delete organization Rimfrost Bakeri AS» · «—» | Literal | Deletion request | `orgs.delete_now` | build | The requester types the org.nr (D-30); the approver confirms it again |
| ACC-22 «Discount 35 % for 12 months — Elvebakken kommune» · «−2 380 kr/mo» | Literal | Discount | None | needs-orgpuls | ACC-09 |
| ACC-23 «Export all customer contacts (4 120)» · «4 120 rows» | Literal | Export request with its count | `export_log`, contacts export | build | Count at request time |
| ACC-24 «Reject» → «Rejected» | Local | Decision | — | build | `approval_decide(p_id, false, p_reason)`; requester notified |
| ACC-25 «Approve» → «✓ Approved by Tor» | Local | Decision and execution | — | build | `approval_decide(p_id, true)`: fresh MFA, approver ≠ requester, approver holds ✓ for the action; the server action then runs the action as the approver and records `executed` / `failed` with the product's code |
| ACC-26 Toast «Approved · action executed and logged» | Local | Execution result | — | build | Says «failed (code)» when the command fails |
| ACC-27 (not drawn) Enforcement at the product | — | Per-command authorisation | product-command accepts any admin for any command | build | `public.command_authorize(p_product, p_command, p_approval)` called by product-command with the caller's JWT; approval ids consumed once (R-PL-1) |

## Proposed database objects

Number assigned by the lead (next free is 0078). Every table in `app`, RLS on, no policy, no grant; reads and writes through
SECURITY DEFINER functions in `public` that call `app.require(...)` (which calls `app.is_admin()`: active, confirmed, aal2).
Each migration ships with its invariants suite in `supabase/tests/`.

| Object | Shape | Rights | For |
|---|---|---|---|
| `app.staff_actions` (registry, data) | `key` pk (`accounts.view`, `tickets.reply`, `trial.extend`, `support_access.request`, `plan.change`, `credit_note.issue`, `discount.over_threshold`, `account.delete`, `flags.change`, `announcements.publish`, `customers.export`, `roles.manage`), `label_key`, `ord`, `mapped_right` (e.g. `global:see`) null, `product_command` null, `available` bool (false until its command or store exists) | read: `access_matrix()` with `global:see` | ACC-03…14 |
| `app.action_policies` | `(permission_set_id → permission_sets on delete cascade, action → staff_actions)` pk, `mode in ('allow','approve','deny')`, `updated_by`, `updated_at`; seeded from today's rights (no one gains anything by the migration) | write: `action_policy_set(p_set, p_action, p_mode)` = action `roles.manage` (approval when the caller's mode is `approve`), fresh MFA | ACC-15 |
| `app.action_mode(p_action) → text` | the caller's mode; `deny` when unknown | internal | every gated RPC, `command_authorize` |
| `app.approval_requests` | `id`, `action`, `product` null, `target_type`, `target_id`, `account_id`, `params` jsonb (ids, counts, amounts — no free text), `args` jsonb (the command's argument *values*, nulled on execution, rejection or expiry), `amount` numeric, `unit` (`nok`, `nok_month`, `rows`), `reason` (1–300), `state` (`pending`, `approved`, `rejected`, `executing`, `executed`, `failed`, `expired`, `withdrawn`), `requested_by`, `requested_at`, `decided_by` (check ≠ `requested_by`), `decided_at`, `executed_at`, `result_code`, `expires_at` (7 days), `version`; immutable content trigger (state moves only forward) | `approval_request(...)` by anyone whose mode is `approve`; `approvals_list(p_state)` (requester sees own; holders of `allow` see all); `approval_decide(p_id, p_yes, p_reason)` fresh MFA; `approval_take(p_id)` → args once, state `executing`; `approval_done(p_id, p_ok, p_code)`; notifications `approval.requested` / `approval.decided` | ACC-18…26, BIL-12 |
| `public.command_authorize(p_product, p_command, p_approval uuid default null)` | maps the command to its action; `allow` → ok; `approve` → only with a matching approved, unconsumed request whose decider is the caller; `deny` → forbidden; commands with no action (reads such as `orgs.list`) need `global:see` | authenticated (JWT of the caller); called by product-command | R-PL-1 |
| `app.announcements` | `id`, `product`, `text_no`, `text_en` (≤ 300 each, per D-PL-06), `audience` jsonb `{roles[], access[]}` checked against a registry, `starts_at`, `ends_at`, `state` (`draft`, `published`, `withdrawn`), `reach` (at publish), `published_by/at`, `push_ok`, `push_error` (code), `version` | `announcements_list`, `announcement_save` (global:see to read, action `announcements.publish` to save/publish), `announcement_reach(p_product, p_audience)`, `announcement_push_result` (as 0057's notice) | OPS-15…22 |
| `app.product_flags` (cache) + `app.rollout_log` | cache: `product`, `key`, `name`, `stage`, `pilot_orgs` int, `eligible`, `changed_at`, `synced_at` (from `flags.list` and event `flag.changed`); log: `id`, `product`, `flag`, `from_stage`, `to_stage`, `staff_id` null (null = guard), `auto`, `reason`, `ok`, `error_code`, `at` | `rollouts_get(p_product)` global:see; `rollout_logged(...)` by the server action after the command | OPS-03…13 |
| `app.flag_metrics` | `product`, `flag`, `bucket` (hour or day), `orgs_on`, `orgs_using`, `requests`, `errors` | from `ingest_events` (`flags.daily` / `flags.hourly`) | OPS-05, OPS-06, guard |
| `app.rollout_guards` + job `rollout_guard` | `product`, `flag`, `enabled`, `factor` (2.0), `min_requests`, `window`; the job may only call `flags.set_stage` downwards, as `platform` | global:configure; only if D-PL-05 puts the guard in Sentral | OPS-02, OPS-14 |
| `alter table app.plan_versions add column plan_key text` | `small` / `usual` / `group` / `free`; `plan_accounts` and every band lookup by `plan_key` | — | F-2, OPS-24, BIL-02, SUC-25, PLN-01 |
| `app.plan_limits` (if D-PL-07) | `product`, `plan_key`, `metric` (`employees`, `admins`, `sms_month`, `storage_bytes`), `limit` | global:see read, global:configure write (or mirrored from Orgpuls) | OPS-25…27 |
| `public.limits_near(p_product, p_warn_pct)` | latest `usage_daily` per tenant against the plan's maximum (and `plan_limits`) | global:see | OPS-23…28 |
| `public.limit_notify(p_org, p_metric)` | queues a Brevo transactional mail and audits `customer.limit_notified` | global:add | OPS-29 |
| `app.product_error_codes` + `app.product_errors_hourly` | codes: `product`, `code` (`^[a-z0-9_]{1,40}$`), `label_key`, `severity`; counts: `product`, `tenant_id`, `hour`, `code`, `count` (90-day retention) | from `ingest_events` (`errors.hourly`) | OPS-34, OPS-35 |
| `public.customer_errors(p_product, p_hours)` | merges product error counts with Sentral's own failed deliveries (ticket replies, campaign bounces) per organisation | global:see | OPS-33…39 |
| `public.error_ticket_create(p_org, p_product)` | ticket, category `bug`, body generated from codes and counts, dedupe on an open ticket from this source | tickets:add | OPS-40 |
| `public.onboarding_completion(p_product, p_cohort_days)` + `app.onboarding_steps` (registry: `product`, `key`, `ord`, `label_key`, `source` (`accounts`, `usage`, `members`, `milestone`), `visible_in_app` mirror) | completion per step from `account_products`, `usage_daily`, `members`, `activation_milestones` | global:see | SUC-01…10 |
| `app.nps_responses` + `public.nps_summary(p_product, p_days)` (if D-PL-12) | `product`, `tenant_id`, `source_id`, `score` 0–10, `role`, `answered_at`; no user name, no text | global:see | SUC-11…15 |
| `app.feature_requests`, `app.feature_request_votes`, `app.feature_request_links` | **as dev-a defines them** (one definition): request (product, title, status, roadmap_item_id), vote (request, organization_id, person_id null, source, voted_by, at, unique per D-DEV-05), link (tickets, deals) | `feature_requests_list(p_product)` (votes, tickets, deals, MRR asking under the MRR right), `feature_request_vote`, `feature_request_set_status` (→ mail queue on Shipped per D-PL-14) | SUC-16…23 |
| `public.renewal_signals(p_product, p_days)` | band crossing (employees within N of the plan maximum), health drop (`health_scores`), no sign-in for N days, later logins trend and period end | global:see | SUC-24…29 |
| `public.success_deal_create(p_org, p_kind)`, `public.success_task_create(p_org, p_kind)` | thin wrappers over `rec_save('deal')` / activity create with dedupe | deals:add / global:add | SUC-30, SUC-31 |
| `app.credit_notes` (if D-PL-10) | `id`, `organization_id`, `product`, `tenant_id`, `amount`, `currency`, `kind` (`refund`, `credit_next_invoice`), `reason`, `state` (`requested`, `approved`, `issued`, `rejected`), `approval_id`, `issued_ref`, `requested_by`, `issued_by`, timestamps | `credit_notes_list`, `credit_note_request`, `credit_note_mark_issued` | BIL-10…13, ACC-08, ACC-20 |
| `app.invoices` (mirror, if D-PL-10 picks a connector) | `provider`, `number`, `organization_id`, `issued_on`, `due_on`, `amount`, `currency`, `state` (`paid`, `unpaid`, `overdue`, `credited`), `synced_at` | `invoices_for(p_org)` global:see | BIL-07, BIL-08 |
| Settings (registry rows) | `plan_limit_warn_pct` (80), `credit_note_approval_over` (2 000), `discount_approval_over_pct` (20) | global:configure | OPS-23, BIL-10, ACC-09 |
| `ingest_events` / `project_product_event` | project the new kinds: `flags.daily|hourly`, `flag.changed`, `errors.hourly`, `nps.answered`, `milestone.reached` (exists), `logins.daily` (registry exists), `usage.daily` new fields; `billing.changed` + `price`, `ehf`, `current_period_end`, `market` | — | above |
| `app.product_event_kinds`, `app.product_commands` rows | the new kinds and commands (mirror of `_shared/orgpuls.ts`, test-asserted) | — | — |

## Proposed edge functions and connectors

| Function / connector | Change | For | Rules |
|---|---|---|---|
| `product-command` | (1) before signing: call `command_authorize(product, command, approval)` as the caller (the service role path stays for scheduled work); (2) accept `approval` in the body and pass it; (3) register the new Orgpuls commands; (4) log each call to `integration_calls` (APP-02) | R-PL-1, every action here | Rule 3: still one scope per token, two minutes, names-only audit |
| `orgpuls-events` | No code change (ingest is SQL); the registry rows and projections grow | OPS-05/06/34/35, SUC-07/08/11/27 | Rule 4 unchanged |
| `mail-run` | New mail kinds: limit notice (OPS-29), «your request shipped» (SUC-23), approval notifications by e-mail (optional) | — | Templates en/no; no body logged |
| Accounting connector (`accounting-sync`, if D-PL-10) | Read invoices and credit notes from Fiken / Tripletex / PowerOffice Go / Visma eAccounting; PDF through a short-lived signed URL; credentials via `secret-intake` purpose `accounting`, read only by the worker through `product_secret` | BIL-07, BIL-08, BIL-13, BIL-14 (overdue) | Rule 5 |
| WebAuthn MFA (Supabase Auth, if D-PL-03) | Enable `[auth.mfa.web_authn]`; enrolment in the MFA page; per-role check of the session's method | ACC-16 | Rule 2 unchanged (aal2 always) |
| No Sentry connector here | dev-a covers Sentry (D-DEV-11); «Errors per customer» should use Orgpuls' counts, not Sentry payloads | — | R-PL-2 |

## Orgpuls commands and events needed

Commands (all through product-command, one scope each; actor = the admin or `platform`):

| Command | Scope | Arguments | For |
|---|---|---|---|
| `flags.list` | `flags:read` | — → `{key, name, stage, pilot_orgs, eligible, changed_at}[]` | OPS-03, APP-06 (dev-a names the same command) |
| `flags.set_stage` | `flags:write` | `p_flag`, `p_stage` (`off`, `internal`, `pilot`, `pct_5`, `pct_25`, `pct_50`, `all`), `p_reason` | OPS-08, OPS-10, OPS-12, guard (dev-a calls it `flags.set_rollout`; one name to be chosen) |
| `flags.pilot` | `flags:write` | `p_flag`, `p_org`, `p_on`, `p_reason` | OPS-09 |
| `announcements.publish` / `announcements.withdraw` (/ `announcements.reach`) | `announcements:write` (`:read`) | `p_id`, `p_no`, `p_en`, `p_roles[]`, `p_access[]`, `p_starts_at`, `p_ends_at` / `p_id` | OPS-20, OPS-21 |
| `limits.set` | `billing:write` | `p_org`, `p_metric`, `p_value`, `p_reason` | OPS-30 (only with D-PL-07) |
| `billing.change_plan` | `billing:write` | `p_org`, `p_plan`, `p_interval`, `p_reason` | ACC-07, BIL-04 (already in SIMPLE-PLAN) |
| `billing.set_discount` | `billing:write` | `p_org`, `p_percent`, `p_months`, `p_reason` | ACC-09, ACC-22 (only with D-PL-11) |
| `billing.plans` | `billing:read` | `p_market` → plans, prices, trial days, annual months | BIL-03, PLN-01…04 |
| `onboarding.steps` / `onboarding.set_visible` | `settings:read` / `settings:write` | `p_step`, `p_on` | SUC-10 (only with D-PL-13) |
| `settings.set_maintenance` | `settings:write` | (exists in the backlog, V-SPL-03) | APP-04 |

Events (count-only; each registered in Orgpuls' `app.platform_event_kinds` first, so `platform_emit` refuses any other field):

| Event | Fields | For |
|---|---|---|
| `flags.daily` (or `flags.hourly`) | `flag`, `stage`, `orgs_on`, `orgs_using`, `requests`, `errors` (product-wide) | OPS-05, OPS-06, guard |
| `flag.changed` | `flag`, `stage`, `by` (`platform` / `orgpuls`) | Cache kept true when Orgpuls changes a flag itself |
| `errors.hourly` | per organisation: `code`, `count` (codes from Orgpuls' registry, incl. mail deferrals/bounces of invitations as counts) | OPS-34, OPS-35 |
| `milestone.reached` | `key` (`results_viewed`, `first_tiltak`, and the others in 0013's list) | SUC-07, SUC-08 (D-21, never sent so far) |
| `logins.daily` | `role`, `logins` | SUC-27 (D-21) |
| `usage.daily` + `sms_sent_month`, `storage_bytes`, `admins` | counts | OPS-25…27 (only with D-PL-07) |
| `nps.answered` | `score`, `role` | SUC-11…13 (only with D-PL-12) |
| `billing.changed` + `price`, `ehf`, `current_period_end` (and `payment_state` if ever relevant) | — | BIL-02, BIL-06, SUC-27; D-22 promised price, currency, seats |

Orgpuls repository work that is not a command: a runtime flag store with per-organisation targeting and a deterministic bucket,
an «internal» cohort (its QA/demo tenants), `eligible` per flag (never the DPIA/translation-gated ones); an in-app announcement
banner for signed-in customer users (never the respondent flow); an in-app NPS prompt (if decided); a code registry for errors.
Each needs an X-entry by Tor in Orgpuls (flags move from «signed off in code review» to «staged from Sentral»).

## Product decisions for Tor

| ID | Decision | Elements | Recommendation |
|---|---|---|---|
| D-PL-01 | The staff role set: Team's five (Admin, Sales, Support, Marketing, Read-only) or the matrix's six (Super-admin, Support, Billing, Ops, Sales, Read-only)? | ACC-02, TEAM-04, TEAM-07 | Seven offered sets: Admin (= Super-admin), Sales, Support, Marketing, Billing (re-offer Finance), Ops (new), Read-only; the matrix shows them all |
| D-PL-02 | Approvals: the design's ✓/A/– as the starting policy? Who may approve (anyone holding ✓ for that action, never the requester)? Expiry? What if only one person holds ✓ (Manage admin roles is «A» even for Super-admin, so Tor alone could never change a role)? | ACC-14, ACC-15, ACC-18…26 | Design's matrix; approver = another holder of ✓ with fresh MFA; 7 days; the owner may act alone with a typed reason and an alert when no second holder exists |
| D-PL-03 | Security keys (WebAuthn) for Super-admin and Billing — D-11 says TOTP only | ACC-16 | Yes for Admin/Billing once the owner has enrolled a key; until then the line is not shown |
| D-PL-04 | Percentage rollouts in Orgpuls: move rollable flags from code to a runtime store; which flags are eligible; the «internal» cohort; stage set 1 pilot / 5 / 25 / 50 / 100 % | OPS-03…13, APP-06 | Yes for product features only; never `locale_*`, `action_volunteers`, `measured_badge_public` or anything gated by a DPIA or translation review |
| D-PL-05 | Automatic roll back: allowed on production? In Orgpuls or in Sentral? Threshold ×2 of what baseline, minimum volume, window | OPS-02, OPS-14 | In Orgpuls (it has the data), reported by `flag.changed`; Sentral shows it. If Sentral: down only, ≥ 200 requests, 1 h window |
| D-PL-06 | Announcements: the in-app channel (status message stays the public site's), audience model (what «Admins» and «Trial» mean), languages (no + en; sv and gb markets), schedule, dismissible | OPS-15…22, APP-08 | Separate command; roles + access; no + en (gb text for UK accounts); start/end dates; dismissible |
| D-PL-07 | Plan limits: do limits other than headcount exist (admins, SMS per month, storage)? Values per plan? Warn at 80 %? | OPS-23…30 | Headcount only for now (it is real); others only if Orgpuls will enforce them |
| D-PL-08 | The plan catalogue: Orgpuls' Liten/Vanlig/Flere selskaper (+ free, NOK/GBP) vs Sentral's four bands and the design's Small/Medium/Large/Enterprise | PLN-01, PLN-05, BIL-02, BIL-03, SUC-25, OPS-24 | Orgpuls is the truth: `billing.plans`, `plan_key` in Sentral; Orgpuls' names |
| D-PL-09 | What the Billing portal tab is: a preview of Orgpuls' «Oppsett › Betaling» for one account, or an operations view (plans, credit notes, invoices) | BIL-01 | An operations view with an account picker; no customer-page mock |
| D-PL-10 | Invoices and credit notes: which accounting system makes Orgpuls' invoices; should Sentral read it; may Sentral record credit notes; threshold 2 000 kr | BIL-07, BIL-08, BIL-10…15, ACC-08, ACC-20 | Read-only connector to the accounting system; credit-note register with approval over 2 000 kr, marked issued with the accounting reference |
| D-PL-11 | Discounts: does Orgpuls give them (the design: 35 % for 12 months for a kommune tender)? | ACC-09, ACC-22 | Only if Orgpuls invoices can carry one; otherwise remove the row |
| D-PL-12 | Customer NPS: ask customer users in Orgpuls at all, who (daglig leder?), every 90 days, a free-text «why»? | SUC-11…15 | Yes, daglig leder only, 90 days, score only at first |
| D-PL-13 | Onboarding: the design's seven steps vs Orgpuls' four «Kom i gang» steps; may Sentral hide steps in the product; the cohort for completion | SUC-02…10 | Completion in Sentral now (five steps real, two after `milestone.reached`); the in-app list stays Orgpuls' |
| D-PL-14 | Feature requests (with dev-a D-DEV-05/13): who votes; e-mail to voters on Shipped (transactional?); where the changelog is | SUC-18, SUC-23 | Staff on behalf of an organisation; a service mail to the people who asked; changelog with announcements |
| D-PL-15 | Renewal signals: definitions (band crossing within N employees, at-risk rule), «next 60 days» for monthly invoices, the pipeline for a created deal, the owner when no CSM | SUC-24…31 | Within 5 employees of the maximum; at risk = health drop ≥ 20 or no sign-in 30 days; default pipeline; owner = account owner |
| D-PL-16 | Who sees the new tabs: Billing and Customer success for Sales/Support? The matrix for everyone (read) or `global:security` only? | all | Read with `global:see`; acting per the matrix |
| D-PL-17 | Products without a connection (Skiftly, Avvikspunkt, Kursrom) in rollouts, errors and cross-sell | OPS-04, OPS-17, OPS-37, SUC-26, SUC-28 | Not rendered until connected |

## Risks against the security rules

| ID | Rule | Risk | Mitigation |
|---|---|---|---|
| R-PL-1 | 3 (product-command) and every role rule | `product-command` signs any command for any admin (`admin_whoami().admin`). A Read-only staff member with an aal2 session can POST `orgs.delete_now` or `billing.extend_trial` to the function directly; the matrix and approvals would be cosmetic | `command_authorize` inside product-command before signing; approval ids consumed once; a test per role and command |
| R-PL-2 | 6 (no respondent data), Orgpuls invariant 7 | «Application error logs» can carry respondent free text; «error log attached» would copy it into a ticket | Codes and counts only, from Orgpuls' code registry; the ticket carries the counts table; no Sentry payloads |
| R-PL-3 | 6 | Invitation delivery is visible in the shared Brevo account (respondents' addresses) | Never read Orgpuls-tagged Brevo events (0060 already drops them); counts come from Orgpuls |
| R-PL-4 | 6, D-34 | «NPS» confused with Orgpuls' eNPS (respondent data) | `nps.answered` comes only from customer users' own prompt; registry test that the kind has no respondent field; label «Customer NPS» |
| R-PL-5 | 6, D-19 | «Adoption» of survey features computed from responses or groups | Organisation counts only (`orgs_using`), never responses, groups or comments |
| R-PL-6 | 3 (audit holds names, never values) | An approval must keep the command's argument values until it runs | Values in `approval_requests.args` (RLS, no grant), nulled on execution, rejection or expiry; never in `audit`, logs or notifications |
| R-PL-7 | 3 | An automatic guard acting as `platform` could widen or flap a flag | Guard may only call `flags.set_stage` downwards, at most once per flag per hour, audited with `auto = true` |
| R-PL-8 | 2 (second factor) | Approving deletions, exports and role changes on a stale session | `app.require_fresh_mfa` on decide and on policy changes; security keys only after D-PL-03 |
| R-PL-9 | Never fabricate | Literals: rollout %, «372 users», «Raised · 58 %», invoices, «38 %», «68 %», dunning, «+42», «214 answers», onboarding %, «MRR asking», «48 shift workers», «Approved by Tor» | Each from its source or not shown (deviations V-SPL-19 onward when built) |
| R-PL-10 | 1 and visibility | Reach, MRR asking and renewal lists aggregate account data | Definer reads under each source's own right (MRR needs the right that shows MRR today), tested per role |
| R-PL-11 | Never fabricate (existing build) | F-1: the Status message claims «Shown at the top of the app» but reaches the public site | Relabel now (en + no) |
| R-PL-12 | Orgpuls X-089 / D-133 | A percentage rollout of `locale_*` would show unreviewed or partial translations to respondents | `eligible = false` for those flags in Orgpuls; Sentral never offers stages for them |
| R-PL-13 | D-30 | Deleting through an approval could skip the typed org.nr | The requester types it, the approver types it again; `orgs.delete_now` keeps `p_confirm` |

## Suggested build order

| Wave | Content | Depends on | Size |
|---|---|---|---|
| 0 | F-1 relabel of the Status message; F-2 `plan_versions.plan_key` and `plan_accounts` by key (fixes real-data counts) | — | S (½ day) |
| 1 | Tab strip (seven links, «Team»), the four new tabs' shells with honest states; **Roles and approvals**: `staff_actions`, `action_policies` (seeded from today's rights), `approval_requests`, `command_authorize` + product-command change, the matrix UI with cycling cells, the queue with Approve/Reject executing trial extension, deletion (replacing `second_admin`'s dead end), exports (as a storage job) and policy changes; notifications | D-PL-01, D-PL-02, D-PL-16 | L (≈ 4–5 days, migration ≈ 700 lines + suite) |
| 2 | **Customer success** on Sentral data: onboarding completion (five steps), feature requests (shared tables with dev-a), renewal signals (band crossing, health drop, no sign-in), Create deal, CSM task | D-PL-13, D-PL-14, D-PL-15; dev-a's feature-request definition | M (≈ 2–3 days) |
| 3 | **Rollouts and announcements**, Sentral half: announcement composer + reach (Publish disabled with «Orgpuls has no announcement command yet»), accounts near the employee limit + Notify (Brevo), errors per customer from Sentral's own mail + Create ticket | D-PL-06, D-PL-07 | M (≈ 2–3 days) |
| 4 | **Billing portal**: current plan per account (picker), billing-ticket counts, credit-note register with approvals; then the accounting connector and invoices | D-PL-09, D-PL-10, D-PL-11 | M, + M for the connector |
| 5 | **Orgpuls repository**: runtime flags (`flags.list`, `flags.set_stage`, `flags.pilot`, `flags.daily`, `flag.changed`), `announcements.*`, `errors.hourly`, `milestone.reached`, `logins.daily`, `billing.changed` fields, `billing.plans`; NPS prompt and limits if decided | D-PL-04, D-PL-05, D-PL-06, D-PL-07, D-PL-12; X-entries in Orgpuls | L (Orgpuls) |
| 6 | Sentral wiring for wave 5: Rollouts card (stages, widen, roll back, restart, pilot picker, metrics), guard if D-PL-05 puts it here, Publish announcement, the two milestones, NPS card and detractor workflow, at-risk on logins and period end, «Raise» | Wave 5 deployed (database first) | M (≈ 3 days) |
| 7 | Security keys for Admin and Billing | D-PL-03 | S–M |

Deviations to log when built (`deviations/simple-platform.md`, V-SPL-19 onward): tabs as links (four more); only connected
products in rollouts, announcement chips and errors; no «Card», no failed-payment card, no invoice rows without a connector;
«Ticket created with the error counts»; «Raised to N» instead of a computed percentage; onboarding without in-app checkboxes;
the stage bar at 390 px; an account picker on Billing; «Create request» from a ticket; the matrix's unavailable rows
(change plan, credit note, discount) shown with «Not available yet» until their command or store exists.
