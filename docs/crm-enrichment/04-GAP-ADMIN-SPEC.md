# 04 — Gap against the admin specification (Appendix 2)

Phase A, A3.4. Every bullet of Appendix 2 (`INSTRUCTIONS.md:3777-4141`) is given a status (A3.5),
judged against **this repository only** (`main` `8c01aec`).

- Per decision D-01, everything is built new. No earlier system is a source or a reference.
- **Via command** means the platform can already ask Orgpuls to do it through a signed command
  (`supabase/functions/_shared/orgpuls.ts`), but the platform has no screen for it.

Abbreviations: Impl = Implemented, Part = Partial, Miss = Missing, Confl = Conflict, Unk = Unknown.

## Summary

| Section | Rows | Impl | Part | Miss | Confl | Unk |
|---|---|---|---|---|---|---|
| Purpose and principles | 7 | 0 | 3 | 2 | 0 | 2 |
| Access model | 9 | 0 | 5 | 2 | 2 | 0 |
| Analytics | 19 | 0 | 0 | 19 | 0 | 0 |
| Organisations | 21 | 0 | 2 | 19 | 0 | 0 |
| Users and support access | 14 | 0 | 1 | 13 | 0 | 0 |
| Content management | 8 | 0 | 0 | 8 | 0 | 0 |
| Data, privacy and compliance | 9 | 0 | 1 | 8 | 0 | 0 |
| Billing and payments | 11 | 0 | 1 | 9 | 1 | 0 |
| Communication and support | 6 | 0 | 0 | 6 | 0 | 0 |
| System operations | 6 | 0 | 1 | 5 | 0 | 0 |
| Web analytics | 13 | 0 | 0 | 13 | 0 | 0 |
| Marketing CRM | 6 | 0 | 0 | 5 | 1 | 0 |
| Ticketing | 25 | 0 | 0 | 25 | 0 | 0 |
| Best practices | 12 | 0 | 3 | 8 | 1 | 0 |
| **Total** | **166** | **0** | **17** | **142** | **5** | **2** |

Counts are of the rows below. A row may group a sentence and its sub-clauses; the open point on
benchmarks (later phase) and the recorded decisions are not counted.

Nothing is Implemented. Implemented requires tests that pass (the repository has no database or end-to-end tests) and having seen it on screen.

## Purpose and principles

| Item | Status | Evidence / what is missing |
|---|---|---|
| Not the customer-facing admin | Part | Separate app and project (`01-ENVIRONMENT.md`). The rest of the admin is not built |
| Anonymity holds for staff; 5-answer threshold on every admin view, export and impersonation | Part | The platform holds no answer data and the event registry carries none (`02-DATABASE.md`). No firewall test, no impersonation yet. Note: Orgpuls' floor is now k = 3, default 5 (Orgpuls D-198/k_floor), not a fixed 5 → **Q-19** |
| Orgpuls as data processor; metadata only by default | Part | Only metadata arrives (`ingest_events`, `0001:173-268`). No consent-gated content access |
| Least privilege by role | Miss | Only `owner`/`admin`, and nothing reads the role (`0001:21`) |
| Everything audited (reads of customer data and writes, with a reason) | Miss | Only product commands are audited (`0001:136, 271`), with no reason field. Reads are not audited |
| Data, not code (plans, question sets, tiltak, templates, flags as rows) | Unk | In the platform: none. In Orgpuls: question sets, modules, legal, translations are data, reachable via command → **Q-23** (which system owns which content) |
| EU residency | Unk | Supabase project in eu-central-1 (`README.md`). The Vercel function region is not verified |

## Access model

| Item | Status | Evidence / what is missing |
|---|---|---|
| Separate surface, own middleware | Part | Separate app; `middleware.ts` gates every route. Domain `www.owntheagenda.com`, not admin.orgpuls.com |
| Own role model | Miss | Four roles (super-admin, support, finance, analyst) do not exist |
| Mandatory MFA | Part | aal2 required by middleware and `app.is_admin()` (`0001:32-36`). No `mfa_enforced` column; MFA is not optional per admin. Brief says MFA "mandatory", so this matches the principle |
| `platform_admins (user_id, role, mfa_enforced, created_by)` | Confl | The platform has `app.admins (email, role, active, created_at)`, keyed on email, not user_id, and has no `mfa_enforced` or `created_by` (`0001:18-23`) → **Q-08** |
| Admin role never derivable from a customer role | Part | `app.admins` is unrelated to `app.members` (`0001:18, 98`). No test |
| Admin reads through definer functions that check role **and write an audit row** | Part | Definer functions check `is_admin()` (`platform_status`, `0001:306`), but write no audit row on read |
| RLS stays on; admin access via named policy `is_platform_admin(role)` | Confl | RLS is on with **no** policy and no client grant (deny-all). Access is only through definer RPCs gated on `app.is_admin()`, not a policy path → **Q-09** |
| Response-level tables unreachable; aggregates n ≥ 5 | Part | None exist here. Orgpuls enforces k in its own RPCs. No platform test |
| Session timeout 30 min idle, optional IP allowlist, login alerts | Miss | None |

## Analytics

| Item | Status | Evidence / what is missing |
|---|---|---|
| Activation funnel per cohort, 8 steps, drop-off and median time | Miss | Events today: org.created, member.joined, billing.changed, usage.daily (`0001:226-260`). No events for employee list, survey scheduled/sent, result unlocked, results viewed or tiltak; Orgpuls does not emit them (its event registry, 0205) → **Q-21** |
| "20 minutes to first send" metric | Miss | Needs a "first survey sent" event |
| MRR, ARR, net new MRR | Miss | `subscriptions` holds plan and dates but no price (`0001:80-96`) |
| Paying orgs, trials active, trials expiring in 7 days | Miss | Derivable from `subscriptions`, but nothing computes it |
| Trial → paid conversion by cohort and source | Miss | Attribution arrives as `org.attribution` (`0001:233-235`). No report |
| Logo and revenue churn, cohort retention | Miss | — |
| ARPA and tier distribution | Miss | — |
| Customers by industry (NACE), size, fylke | Miss | `org.created` carries industry and employee_count, no fylke |
| Surveys per month, response rate, reminder effectiveness | Miss | Not in Orgpuls' event registry |
| Share of groups hidden by threshold | Miss | Same |
| Tiltak created, closed on time | Miss | Same |
| Logins by role | Miss | `usage.daily.last_sign_in_at` only, not by role |
| Comments posted, share answered | Miss | Not emitted |
| Feature adoption per org | Miss | Not emitted |
| Marketing attribution: UTM + referrer; signups/activation/paid per channel | Miss | Raw attribution stored on `account_products.attribution`. No report |
| Health score per org | Miss | — |
| Health inputs (last login, cadence vs årshjul, response trend, tiltak, payment) | Miss | Most inputs are not emitted |
| Flag at-risk orgs before renewal | Miss | — |
| Dashboard answers "trials → orgs that run surveys and act" first | Miss | Status page only. |

## Organisations

| Item | Status | Evidence / what is missing |
|---|---|---|
| Organisation is the primary object | Part | `app.accounts` + `app.account_products` exist (`0001:58-77`). No screen |
| List: search by name, org.nr, admin e-mail | Miss | — |
| List filters (status, tier, band, industry, fylke, source, trial days, health) | Miss | — |
| List columns (name, org.nr, status, plan, employees, last survey, response rate, health, MRR, signup) | Miss | Some data exists (`accounts`, `subscriptions`, `usage_daily`) |
| Saved views | Miss | — |
| Detail header: Brreg data, status, plan, health | Miss | Via command: `orgs.get` returns registry facts |
| Users and roles in the org | Part | `app.members` mirrored (`0001:98`), and `orgs.get` returns members. No screen |
| Structure: departments count, employees, groups below threshold | Miss | `usage_daily.employees` only |
| Surveys metadata | Miss | Via command: `orgs.get` returns rounds (status, dates) |
| Tiltak counts | Miss | — |
| Billing: subscription, invoices, payment method | Miss | Subscription mirror only. No invoices or payment method |
| Timeline | Miss | `events_in` holds the raw events. No timeline |
| Internal notes and tags | Miss |. |
| Audit trail for this org | Miss | `app.audit` is not keyed by org |
| Action: extend or reset trial | Miss | Via command: `billing.extend_trial` |
| Action: change plan, discount, complimentary | Miss | Via command: `billing.*` (cancel, withdraw). No plan change or discount |
| Action: suspend / reactivate | Miss | No command |
| Action: re-sync from Brønnøysund | Miss | No command |
| Action: transfer ownership | Miss | No command |
| Action: merge duplicate orgs (same org.nr) | Miss | `accounts.org_number` is unique, so duplicates cannot occur at account level. No merge |
| Action: export org data; delete org (grace, type org.nr, super-admin) | Miss | Via command: `orgs.deletions`, `orgs.delete_now`. No reason capture, no super-admin role |

Every action "requires a reason": no reason field exists anywhere (`app.audit` has none).

## Users and support access

| Item | Status | Evidence / what is missing |
|---|---|---|
| Users and respondents kept apart; admin manages users only | Part | Only users (`app.members`) are mirrored; respondents never arrive |
| User search across orgs | Miss | — |
| Memberships (org, role, invited by, when) | Miss | `members` has no inviter or date |
| Last login, MFA status, auth method, pending invites | Miss | — |
| Actions: resend invite, reset MFA, change e-mail, deactivate, remove, billing contact | Miss | No commands for these |
| Respondents per survey: invited, delivered, bounced, answered (counts) | Miss | — |
| Fix bounced addresses only via the customer | Miss | (Rule; nothing to violate yet) |
| No lookup from respondent to answer, ever | Miss | Structurally true, but untested; a firewall test is required (R6) |
| Support access: customer grants or approves | Miss | — |
| Time-boxed, read-only by default | Miss | — |
| Banner in customer app, listed in their audit log | Miss | Needs Orgpuls changes |
| Inherits threshold and role scope | Miss | — |
| Every page view logged | Miss | — |
| Personvern request queue with 30-day clock | Miss | — |

## Content management

| Item | Status | Evidence / what is missing |
|---|---|---|
| Question set versioned, published immutable, factor mapping | Miss | Lives in Orgpuls (modules registry). Via command: `modules.*` (status, validation, sync, pilot) |
| Pulse templates | Miss | — |
| Tiltak library per factor and band, ranking configurable | Miss | — |
| Legal references with last-reviewed date | Miss | Via command: `legal.*` |
| E-mail and SMS templates with preview and test-send | Miss | Orgpuls mail texts are messages files. Via command: `translations.*`, `overrides.*` |
| Årshjul defaults | Miss | — |
| Help texts and announcements | Miss | Via command: `settings.notice`/`set_notice` (site notice) |
| Author, date, version, rollback for every change | Miss | — |

## Data, privacy and compliance

| Item | Status | Evidence / what is missing |
|---|---|---|
| DPA per org: version, date, by whom, re-acceptance | Miss | Orgpuls has DPA signatures (0047). Not emitted to the platform |
| Retention per customer, purge report | Miss | — |
| Deletion queue with grace period, log, confirmation | Miss | Via command: `orgs.deletions` (read) |
| Exports, logged | Miss | — |
| Audit log append-only, searchable by admin, org, action, date; retained longer | Part | Append-only (`0001:148-154`). Not searchable, not keyed by org, covers commands only |
| Anonymity guardrails (no n < 5 path; re-identification alert) | Miss | — |
| Subprocessor register | Miss | — |
| Incident register with 72-hour clock | Miss | — |
| Backups: last backup, last restore test | Miss | — |
| Benchmarks later | — | Open point, later phase |

## Billing and payments

| Item | Status | Evidence / what is missing |
|---|---|---|
| Pricing model (band pricing, free roles, **30-day trial**) | Confl | Orgpuls' current terms: **15-day** trial and a free access level (Orgpuls migrations 0048, 0199; D-217). Appendix 2 (25 Sep) is out of date → **Q-22** |
| Plan catalogue as versioned data | Miss | Plans live in Orgpuls |
| Subscription lifecycle (trial, active, past due, suspended, cancelled, deleted) | Part | Mirror holds trial, confirmed, free_from, cancelled, cancel_effective, deletion_due (`0001:80-96`). No past-due or suspended state |
| Band reconciliation | Miss | — |
| Subscription view per org | Miss | — |
| Invoice list, PDF, resend | Miss | No invoices anywhere |
| Failed payments, dunning, manual retry | Miss | — |
| Credits, refunds, discounts, coupon codes | Miss | — |
| Complimentary / partner accounts | Miss |. |
| Revenue reports, accounting export | Miss | — |
| EHF via PEPPOL and card | Miss | — |

## Communication and support

| Item | Status | Evidence / what is missing |
|---|---|---|
| E-mail/SMS log per org | Miss | Orgpuls has mail_events (dispatch). Not emitted |
| Deliverability overview | Miss |. |
| Lifecycle messaging, editable | Miss | Orgpuls kept its trial service mail (lifecycle_*). Not editable from the platform |
| Broadcasts | Miss | — |
| Support inbox link | Miss | `support.requested` events arrive in `events_in` but are not projected |
| Feedback and NPS per org | Miss | — |

## System operations

| Item | Status | Evidence / what is missing |
|---|---|---|
| Job monitor | Miss | No jobs |
| Integrations status | Part | Status page shows installation on/off and last event (`app/page.tsx`, `platform_status`). No Brreg, e-mail, payment or SMS |
| Feature flags global and per org | Miss | — |
| Errors link | Miss | — |
| Maintenance mode and status banner | Miss | Via command: `settings.set_notice` (Orgpuls site notice) |
| Admin user management | Miss | Rows are inserted by SQL. No screen |

## Web analytics

All 13 items (traffic, sources, campaign view with spend, landing pages, Search Console, website funnel,
signup drop-off, persona clicks, first/last touch, cookieless `web_events` with daily salt, bot filtering,
separation from product analytics, dashboard in the admin): **Miss**. Orgpuls' public site exists. Where tracking would now run and send data is open → **Q-37**.

## Marketing CRM

| Item | Status | Evidence / what is missing |
|---|---|---|
| Hard rule: respondents never contacts | Miss | Structurally true (no respondent data). Needs a test |
| Contact types, fields, auto-link, timeline, CSV import with consent source | Miss |. |
| Segments | Miss |. |
| Campaign editor, types, scheduling, A/B, sequences, reporting | Miss |. |
| Consent basis, unsubscribe, separate streams, suppression list | Miss |. |
| Build vs buy: contacts and consent "stay in Orgpuls" | Confl | Overtaken by D-01: contacts and consent live in the platform |

## Ticketing

All 25 items (types, priority matrix, problem linking, known errors, service requests as actions,
queues, data model, contact-form, in-app help and e-mail channels, no respondent channel, statuses,
priorities, categories, assignee/notes/mentions/attachments, links, canned replies, personvern flow,
SLA targets, reporting, CSAT, self-service help centre, privacy restriction): **Miss**. The inbound
events exist: Orgpuls sends `support.requested` (Hjelp) and `contact.submitted` (site contact form),
and they are stored raw in `app.events_in` (`0001:198-204`) but turned into nothing.

## Best practices

| Practice | Status | Evidence |
|---|---|---|
| Block differencing attacks | Part | Applies to Orgpuls' result readers (complementary suppression, Orgpuls D1/0059). Nothing in the platform reads answers |
| Screen free-text comments | Miss | Product-side. Platform never receives comments |
| One event catalogue (`object_action`) | Part | `events_in.kind` must match `^[a-z]+\.[a-z_]+$` (`0001:126`). No catalogue table, no CRM events |
| Metric definitions as SQL views in git | Miss | No views |
| Stripe as billing source of truth | Confl | See Billing |
| Multi-product keys; org.nr as shared customer key | Part | `product` key on product-scoped tables; `accounts.org_number` unique and used for matching on first event (`0001:216-222`) |
| Safe destructive actions (preview, second admin, soft delete) | Miss | — |
| Separate admin identities, quarterly review, break-glass | Miss | Admin accounts are ordinary Auth users listed by email |
| Seeded demo tenant (Lumio AS / Kari Nordmann) | Miss | → Q-02 |
| SPF, DKIM, DMARC; warm-up | Miss | No sending |
| List hygiene | Miss | — |
| Close the loop on tickets | Miss | — |

## Phasing

Appendix 2's phase 1 ("Run the business": roles, audit, org list/detail, user lookup, trial extension,
funnel, attribution, e-mail log, job monitor, web analytics, ticketing core) is the part the CRM brief
depends on (A4.4: "Anything in Appendix 2 that this work depends on and that is not yet built comes
first"). In the platform, all of it is missing except the access gate and the audit table.

## Recorded decisions that conflict with today's code

| Decision (Appendix 2) | Today | Question |
|---|---|---|
| Admin UI language: English | The platform is bokmål-first with English (`lib/i18n/request.ts`), as are its message files; the Sentral design is in Norwegian | **Q-04** |
| CRM: contacts and consent stay in Orgpuls | Overtaken by D-01: contacts and consent are built in the platform | decided |
| Stripe + EHF via the accounting system | No Stripe anywhere; Orgpuls billing is internal | **Q-22** |
| Admin runs as a separate subdomain/app | Done: separate app on owntheagenda.com | — |
| Admin shared across products | Done in structure (`app.products`, `installations`) | — |
