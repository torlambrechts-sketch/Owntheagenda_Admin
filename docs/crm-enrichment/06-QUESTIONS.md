# 06 — Questions and conflicts

Phase A, A3.6. These are all the Unknowns, Conflicts and differences between the code, Appendix 2 and the
brief. They were collected from 01–05 and the seven part-reviews in 05 (about 150 raw questions) and
merged here into 57 numbered questions. The part-review question lists in 05 keep their own wording
and carry the detail. Format per A11: what was found, the options, what each changes, what is blocked.

Answers go into `DECISIONS.md`, dated.

**Legend.** ⛔ blocks Phase B as a whole · 🧱 blocks the data model or security design · ◻ blocks one module or phase.

---

## A. The baseline the brief assumes no longer exists

**Q-01 ⛔ Port the old Orgpuls admin, or build fresh?**
- *Found:* Part B, Appendix 2 and many Part C rows say "the admin already has" contacts, segments,
  campaigns, sequences, consent, suppression, tickets, web analytics, the typed events table, the health
  score, SQL metric views, a job monitor, feature flags, coupons, the Brønnøysund sync and four staff roles.
  All of that was built in Orgpuls and **deleted with its data on 5 Oct** (Orgpuls 0206, X-105). The
  platform has none of it (`01`, `02`). The code still exists at Orgpuls commit `ced4af2`.
- *Options:*
  - (a) Port the Orgpuls prior art, adapted to the platform's schema and rules, then extend it as the brief says.
  - (b) Build each module fresh from Part C and use the old code only as reference.
  - (c) A mix: port where the old code matches Part C, build the rest.
- *Changes:* the size of phase 0. "Extend, don't rebuild" (A4.1) becomes "build" for most modules.
- *Blocks:* the Phase B data model and all work packages.

**Q-02 ⛔ Where do contacts and consent live?**
- *Found:* Appendix 2's recorded decision says "CRM: contacts and consent stay in Orgpuls". Since 5 Oct the
  CRM has left Orgpuls. Orgpuls now only sends `contact.submitted`, `demo.requested` and `support.requested`,
  plus customer users as `member.*`.
- *Options:*
  - (a) Contacts and consent live in the platform (the natural reading after X-104/X-105).
  - (b) Orgpuls keeps them and the platform reads them by command.
- *Changes:* (a) needs new platform tables. (b) needs new Orgpuls commands and keeps CRM data inside the product.
- *Blocks:* CRM, LEA, CMP, COM-07, AUT-07/12.

**Q-09 🧱 Who owns product content?**
- *Found:* Appendix 2's content management covers question sets, tiltak, legal references and templates.
  Today these live in Orgpuls. The platform can reach some of it by command (`modules.*`, `legal.*`,
  `translations.*`, `overrides.*`, `settings.*`) but has no screen.
- *Options:*
  - (a) Content stays in Orgpuls, and the platform gets screens that call the commands.
  - (b) Content moves to the platform.
- *Blocks:* Appendix 2 "Content management" and the design's Platform screen.

**Q-12 ◻ Which product events should Orgpuls add?**
- *Found:* Appendix 2's activation funnel and product-usage metrics need events Orgpuls does not emit:
  employee list uploaded, survey scheduled or sent, result unlocked, results viewed, tiltak created, comments.
  Orgpuls' registry (0205) sends only org, member, billing, usage and three inbound kinds.
- *Options:* add event kinds in Orgpuls (each a migration there with a field list free of respondent data),
  or read them on demand by command.
- *Blocks:* INS, PRO-03, Appendix 2 Analytics.

**Q-16 🧱 What should Orgpuls' inbound events become?**
- *Found:* `contact.submitted`, `demo.requested` and `support.requested` arrive and are stored raw in
  `app.events_in`; nothing projects them (`0001:261-262`). The brief reuses "the contact form path that also
  opens a ticket" (SF-17.3, LGN-03), which no longer exists.
- *Options:* tickets (Appendix 2 Ticketing first), leads (LEA-04), inbox messages, or all three.
- *Blocks:* Ticketing, LEA-04, LGN-03, UF-01, UF-18, UF-23.

**Q-17 ◻ Ticketing is in Appendix 2 and the design, but not in Part C.**
- *Found:* UF-23 shows an organisation's tickets, and the design has a Tickets screen and a Customers › Tickets
  tab. Part C has no ticket feature.
- *Question:* is Appendix 2 Ticketing in scope as phase-0 baseline work before the CRM phases?

## B. Access and security model

**Q-10 🧱 Which staff roles? (Part G open point 10)**
- *Found:* `app.admins` has `role ∈ {owner, admin}`, keyed on email, and nothing reads the role (`0001:18-23`).
  Appendix 2 names four roles (super-admin, support, finance, read-only analyst). SEC-07 adds permission sets,
  and open point 10 adds sales, marketing and project roles. Appendix 2 also wants
  `platform_admins(user_id, role, mfa_enforced, created_by)`.
- *Options:*
  - (a) Build Appendix 2's four roles first (as Orgpuls 0049 did), then SEC-07 permission sets.
  - (b) Go straight to permission sets with these roles as presets.
  Either way: should `app.admins` be extended (user_id, created_by, roles) or replaced?
- *Blocks:* every module's permission and visibility sentences, and SEC-07/08/09.

**Q-11 🧱 Visibility via RLS policies or definer functions?**
- *Found:* The platform's rule is RLS on with **no policy and no client grant**. Every read goes through
  SECURITY DEFINER functions gated on `app.is_admin()` (`CLAUDE.md` rule 1; `0001:156-166`). The brief (SEC-08,
  SF-01.3, A6, A8) wants visibility enforced by RLS policies and tests per role on select, insert, update and delete.
- *Options:*
  - (a) Keep definer functions and implement owner/group/everyone visibility inside them, tested per role.
  - (b) Add policies and client grants on CRM tables. That changes a security rule, so it needs Tor's approval under R7.
- *Blocks:* every CRM table design and the A8 test style.

**Q-18 🧱 Is MFA a second fixed rule?**
- *Found:* aal2 is required for every session and every admin RPC (`middleware.ts`, `0001:32-36`). SEC-06 reads
  as if MFA could be switched off, while A9 says the firewall is the only fixed rule and R7 forbids weakening MFA.
  SEC-06 also wants an email-code factor and account recovery; there is no recovery path for a lost device today.
- *Question:* MFA always on for staff (a second fixed rule)? Is an email-code factor acceptable? Recovery by codes or by an owner reset?
- *Blocks:* SEC-06, UF-15.

**Q-19 ◻ Are CRM users the same as platform admins?**
- *Found:* PIP-09, ACT-04, CUS-05 and SEC-01..09 assume user profiles and per-user preferences. Only
  `app.admins (email, role, active)` exists.
- *Question:* is every CRM user an admin row with a role, or will staff accounts that are not admins exist?

**Q-20 ◻ Which public paths are approved?**
- *Found:* `middleware.ts` allows only `/login` and `/ingen-tilgang`, and `CLAUDE.md` rule 2 requires a written
  reason per public path. The brief needs public report links (INS-04), booking pages (COM-10), web forms,
  chatbot and live chat (LGN), share and signature pages (DOC) and the MCP OAuth endpoint.
- *Question:* approve them in principle, and decide the domain they live on. Abuse-protection defaults
  (A7.9) are proposed in Phase B.

**Q-21 ◻ Session timeout, IP allowlist, login alerts, access review, break-glass.**
- *Found:* Appendix 2 and the SEC intro say these exist; none does. The design shows "Session timeout
  30 min idle · IP allowlist on". The brief has no register rows for IP and time windows or password age
  (SF-27.3, SEC-03).
- *Question:* are they in scope, and are they settings (default off per R5)?

**Q-22 🧱 What should the audit log cover, and in what shape?**
- *Found:* `app.audit` fits product commands only: `product` required, `command` must match `a.b`, no reason,
  target or feature (`0001:136-145`). Reads, refusals, settings changes, exports and AI calls are not audited.
  `service_role` has all privileges, and the append-only trigger does not cover TRUNCATE (Orgpuls 0049 had a guard).
  The command audit is written after the call, and a failure to write it is only logged (`product-command`).
- *Options:*
  - (a) Extend `app.audit` with nullable columns, a reason and a target, plus a truncate guard.
  - (b) Add a CRM changelog beside it.
  A4.1 discourages a second table.
- *Also:* should existing endpoints start auditing refusals? That changes existing behaviour (R7).
- *Blocks:* SF-02, SEC-11, A7.11 and every write path.

**Q-23 ◻ Should destructive product commands get guards?**
- *Found:* any admin can send `orgs.delete_now` or `billing.cancel` to live Orgpuls from the platform
  (`_shared/orgpuls.ts`). Part B says "preview and soft delete always".
- *Question:* require a preview (`orgs.deletions`) and the second-admin setting before these run?

**Q-24 ◻ SSO.**
- *Found:* SEC-05 asks for SAML (Entra, Okta) and Google. Admins are matched by email (`0001:28`), which is the
  nOAuth risk documented in Orgpuls 0155.
- *Question:* which identity provider, is SAML on the plan, and how does SSO reach aal2?

## C. Data model

**Q-25 🧱 Organisations and people: projection or source of truth?**
- *Found:* `app.accounts` and `app.members` are projections that `ingest_events` overwrites from product events
  (`0001:226-257`). `members` is keyed by (product, tenant, user), so a prospect without a product tenant cannot
  live there and one person in two tenants is two rows.
- *Options:*
  - (a) The CRM edits these rows and the projection stops overwriting fields a person has edited.
  - (b) Add CRM `people` and `organizations` tables linked to accounts and members.
- *Blocks:* CRM-01..15, PIP-03, LEA, CMP.

**Q-07 ◻ Product key on every table.**
- *Found:* the column is `product` (text), not `product_id`. `accounts` and `admins` deliberately carry none,
  because a customer spans products. Appendix 2 says "every admin table carries a product ID".
- *Question:* keep the current convention?

**Q-26 ◻ Name clash: "products".**
- *Found:* `app.products` is the list of installed software products (`0001:41`). CRM-07's product catalog
  needs another name in schema and UI.

**Q-27 🧱 One events table for in and out.**
- *Found:* `app.events_in` is inbound only: `product` foreign key, `source_id` not null, unique (product, source_id).
  Its kinds are dotted (`a.b`), while Part F says `object_action`. `CLAUDE.md` rule 4 says events come in only
  through a product's events function.
- *Options:*
  - (a) Extend `events_in` (nullable source, a direction column).
  - (b) Add an outbox or CRM events table.
  Also: which naming convention?

**Q-28 ◻ The billing mirror has no money.**
- *Found:* `app.subscriptions` and Orgpuls' `billing.changed` carry plan, interval and dates, but no price,
  amount or seats. CRM-08, INS-06 and Appendix 2's MRR/ARR need amounts.
- *Options:* extend Orgpuls' event with price and seats, hold a price catalogue in the platform, or read Stripe (Q-13).

**Q-08 🧱 Which survey threshold, and any survey figures at all?**
- *Found:* Appendix 2 and Part G say n ≥ 5. Orgpuls' rule is a database floor of 3 and a default of 5; an
  organisation may choose 3–4 after a warning (Orgpuls D-198). The platform receives no survey figures today.
  The design has a Customers › Surveys tab.
- *Question:* may the platform show any survey aggregate? If so, under Orgpuls' own k for that round, or a
  stricter platform-wide 5? Orgpuls' registry currently sends "nothing about any answer or any group".

**Q-29 ◻ Retention and erasure of raw events.**
- *Found:* names, emails and contact messages sit in `app.events_in.payload` and `app.members` with no retention.
  `org.deleted` and `member.left` keep names and emails. SF-15.5 says erasure reaches "every module".
- *Question:* what retention applies to raw events, and may erasure rewrite payloads (a data rewrite under R8)?

**Q-30 ◻ Health score and the Brønnøysund sync.**
- *Found:* PRO-03 and PRO-04 build on an existing health score and register sync. Neither exists in the platform;
  Orgpuls had both.
- *Question:* port them? Should the health score be computed from `usage_daily` and `members`, which is what Orgpuls sends now?

## D. Settings and R5 ("no restrictions built in")

**Q-31 🧱 Register keys, types and scopes.**
- *Found:* A9 wants key, type, options, default, scope and IDs. Part C's register gives setting, options, default
  and applies-to. The design's `admin-data.js` gives keys and groups, but no scope.
- *Question:* adopt the design's keys? What is each setting's scope (company, user, pipeline)?
- *Also:* should the firewall be shown read-only in the register (Part C) or kept out of it (A9)?

**Q-32 🧱 Rules and numbers with no register row.** Each should become a setting, defaulting to
unrestricted, or be declared fixed:
- **Rules:** PIP-07 mandatory reason; CUS-02 required fields; label, bulk-edit, export and settings permissions
  (PIP-06, PIP-10, ACT-06, CRM-10, LEA-02, INS-08, AUT-10); CRM-11 matching rules; AIA-02 hide AI scoring;
  PRJ-06 AI summary per account; MCP-03 access switch; MTG-08 per-user switch; CMP-06 engagement tracking;
  the LGN-02 queue wait.
- **Numbers:** the 30-day restore (PIP-17, CRM-12); 208 billing cycles (CRM-08); "5 days without a reply"
  (PRO-01, UF-04); 100-record bulk enrichment (PRO-06); AUT-05's 90-day path and 7-day wait-for; 10 signers
  (DOC-05); the ">3 failed logins" alert and 60-day login history (SEC-02/04).
- **Campaign rules:** non-removable footer (CMP-01); only subscribed receive (CMP-03); unsubscribed never
  mailed (CMP-04); triggered email obeys consent (CMP-07); unauthenticated domain cannot send (CMP-08,
  UF-17). CMP-08 is also imposed by the provider.

**Q-33 ◻ Safeguards that already exist.**
- *Found:* `ingest_events` refuses batches over 500 events, the events function refuses bodies over 1 MB, and
  `product-command` refuses bodies over 200 kB or more than 50 args (`0001:190`, function sources). Orgpuls
  rate-limits its contact form.
- *Question:* are these technical safeguards exempt from R5, or should they move into the register?
- *Also:* the register's "technical safeguards" default is "source values", which restricts by default — confirm.

**Q-34 ◻ Consent defaults.**
- *Found:* the brief defaults `import_consent` and `sales_consent` to Off. Orgpuls' earlier CRM required a
  consent source per imported row and treated the § 15 customer exception as a setting that was off by default
  (Orgpuls 0055). `rec_notice` defaults to On.
- *Question:* confirm the defaults, and who does the legal review (open point 4).

**Q-35 🧱 What do plans and entitlements mean in an internal admin? (ENT, credits)**
- *Found:* ENT gates features "per plan, per seat, trial, top-ups". The admin is one internal company.
  `app.subscriptions` mirrors customers' product plans.
- *Options:* ENT is (a) the CRM's own internal configuration, (b) preparation for selling the CRM, or
  (c) about Orgpuls customers' plans.
- *Also:* what are enrichment credits when the default is "unlimited"?

## E. Runtime, engines and providers

**Q-36 ⛔ Job runtime (Part G open point 3).**
- *Found:* there is no cron, queue or worker. Scheduled sends, sequences, syncs, enrichment, MCP sync, purges
  and meeting bots all need one.
- *Options:* pg_cron/pgmq in this project plus edge functions, Vercel cron, or a separate worker service.

**Q-37 ⛔ One workflow engine (Part G open point 1).**
- *Found:* AUT, CMP-07 and Part G "extend the admin's lifecycle-messaging engine". There is none in the
  platform; Orgpuls' engine was deleted (0060/0111/0120), and Orgpuls kept only its own trial service mail.
- *Question:* build the single engine fresh in phase 0, or port Orgpuls' journeys engine?

**Q-38 ⛔ Providers (Part G open point 2).** Each is a new dependency under R9:
- mail send and sync (Gmail, Microsoft 365, IMAP) with transactional and marketing streams
- calendar
- telephony
- LLM
- transcription and meeting bot
- IP-to-company
- prospect and person data (is Brønnøysund one source or the only one?)
- e-signature evidence
- maps and geocoding
- OCR
- Slack and Teams
- accounting system for INT-08

**Q-39 🧱 Where are per-user OAuth tokens stored?**
- *Found:* the only secret store is Vault for product secrets, restricted to `*_(token|webhook)_secret`
  (`0002:43, 62`). A7.8 says to use the existing mechanism.
- *Options:* Vault with one secret per token, or column encryption.

**Q-40 ◻ Outbound webhooks.**
- *Found:* `_shared/signing.ts` already signs with HMAC-SHA256. No guard against private addresses exists (A7.7).
- *Question:* sign outbound webhooks the same way?

## F. Environment, testing and data

**Q-03 ⛔ Access to the hosted projects.**
- *Found:* since 2026-10-06 the Supabase MCP and the Management API token are refused for every project
  ("FGA Authentication Error"), probably after the projects moved to a new organisation. Both sites still
  answer normally. Hosted drift could not be checked, and the platform's hosted database cannot be changed from here.
- *Action for Tor:* reconnect the Supabase MCP to the new organisation and provide a new access token for it
  (environment variable `SB_MCP_PAT` or `SUPABASE_ACCESS_TOKEN`).

**Q-06 ◻ Local database by the repository's own commands.**
- *Found:* there is no `supabase/config.toml`. Phase A used a scratch copy outside the repository.
- *Question:* add `config.toml`, with TOTP enabled, and a `seed.sql`?
- *Also:* `lib/supabase/env.ts` accepts only an `https://` origin, so the app cannot point at a local http API
  without a proxy. Allow `http://127.0.0.1` in development?

**Q-04 ⛔ Demo tenant and development project (R8).**
- *Found:* no seed and no Lumio AS / Kari Nordmann tenant in the platform. The only configured project is
  production. Some hosted rows were created outside migrations: the installation, the owner admin and a
  deactivated test user. The sandbox (CUS-08) must also keep product commands away from live Orgpuls.
- *Question:* a development Supabase project or branch, plus a platform seed with the demo tenant? Should
  product commands from a sandbox go to a fake Orgpuls or be refused?

**Q-41 ⛔ Test tooling (A8).**
- *Found:* vitest only. No database tests and no end-to-end tool.
- *Question:* add Playwright (end-to-end and visual), plus database tests in the same style as Orgpuls'
  SQL invariant suites or pgTAP via `supabase test db`? Both are new tooling under R9.

**Q-42 ◻ Firewall proof.**
- *Found:* the firewall is structural today: no response table here, and Orgpuls' event registry has no
  respondent field. There are no tests. Whether each allow-listed command returns only response-free data
  is decided in Orgpuls.
- *Question:* should the platform prove the absence of response-level tables and columns here, plus a contract
  test of command replies? Note: Orgpuls' Entra import syncs respondents and must not be ported as contact sync (SF-29).

**Q-43 ◻ Backups, encryption at rest, recovery targets.**
- *Found:* none of these is visible in the repository. The design shows "RPO 1 h · RTO 4 h"; the spec source
  says RTO 2 h. The design shows region "EU · Stockholm (eu-north-1)"; the project is in eu-central-1.
- *Question:* which Supabase plan and backup mode, and which targets to show (open point 8)?

## G. Product scope and the design

**Q-15 🧱 Interface language (Conflict, CUS-05).**
- *Found:* Appendix 2 decided "Admin UI language: English", and CUS-05 makes English the default with a
  per-user locale. The design is written in English. The platform defaults to bokmål with an English option by
  cookie, with Europe/Oslo time (`lib/i18n/request.ts`). The latest commit made Norwegian time explicit.
- *Options:*
  - (a) English default, Norwegian available, locale and time zone per user.
  - (b) Bokmål default as today.
- *Blocks:* every string in Phase C.

**Q-05 ◻ Component library.**
- *Found:* Part B names shadcn/ui. The repository has none, and the design bundle has its own components and fonts.
- *Question:* recreate the design's components (pixel-faithful) or base them on shadcn/ui primitives styled to the design?

**Q-13 🧱 Billing source of truth, and the trial length.**
- *Found:* Appendix 2: "Stripe + EHF via the accounting system (decided)", "30-day trial". Orgpuls has no Stripe
  integration; its billing is its own table, with a **15-day trial** and a free access level (Orgpuls 0048,
  0199, D-217).
- *Question:* is Stripe still the plan? Appendix 2's pricing is out of date — confirm the current model.

**Q-14 ◻ Web analytics and tracker placement.**
- *Found:* the cookieless web analytics was removed from Orgpuls. WEB-02 needs the visitor IP to identify
  companies, while the old design never stored an IP. LGN and WEB scripts must never load in the survey flow,
  which lives in Orgpuls.
- *Question:* which sites carry the tracker? Should the IP be resolved at ingest and dropped? Who proves the
  survey-flow exclusion (an Orgpuls test, a platform test, or both)?

**Q-44 ◻ Mobile and desktop clients.**
- *Found:* MOB-01..08 need iOS and Android apps, and MTG-03/07 need a macOS and Windows recorder. The
  repository is a web app.
- *Question:* React Native/Expo, a PWA, or out of scope until decided? Which repository?

**Q-45 ◻ LinkedIn connector (LEA-06, open point 6).** The spec says to define it before its phase. What should it do?

**Q-46 ◻ Three inventory rows outside the 183 (open point 7).** Named migration sources, the Mailchimp
migrator and partnership discounts: build them or leave them out?

**Q-47 ◻ Recording consent and signature level (open point 5).**

**Q-48 ◻ Targets and running costs (open point 8).** Performance targets, plus the cost model for LLM,
transcription and enrichment.

**Q-49 ◻ Naming review beyond R12 (open point 9).**

**Q-50 ◻ The design shows integration details that do not exist.**
- *Found:* `Platform.dc.html` shows events such as `orgpuls.survey.sent` and `orgpuls.payment.failed` with
  three-segment names, which `0001:126` rejects. It also shows remote actions (suspend, export, support access,
  flags) that are not in the command map, OAuth client auth for products, and an MCP host at `sentral.orgpuls.no`.
- *Question:* are these targets to build (new Orgpuls commands and events), or illustrations?

**Q-51 ◻ Design gaps.** Not found in the design:
- suppression in group email (UF-25)
- the booking-page time zone (UF-06)
- the remove-bot path (UF-07)
- the affected-users preview and alert digest (UF-15)
- the live-chat waiting time (UF-18)
- the upgrade or top-up action (UF-28)
- a "which setting stopped you" message (UF-29)
- Asana and Trello actions (AUT-07)
- subtasks (PRJ-03)

Will the design be extended, or should these be built in its language without a reference?

## H. The brief's own consistency (Part H check)

Counts verified: **183 features, 29 user flows, 45 system flows**. All 276 research rows are accounted for:
273 are mapped and 3 are "not carried". No dangling IDs.

**Q-52 ◻ PIP-17 deal duplication** has no source in the research. Part H cites "restore data", which maps to CRM-12. Keep it as a design addition?

**Q-53 ◻ Marketplace categories.** Five of the nine (Chatbots, Email marketing, Lead generation, Resource
management, Task management) have no connector spec. Are the first-party modules the intended equivalents?

**Q-54 ◻ Named app integrations.** Zendesk, monday, Facebook Lead Ads, Livestorm, Mailchimp, PandaDoc,
Stripe: build connectors, or rely on INT-11 (catalog) plus INT-09 (automation platforms)?

**Q-55 ◻ Small omissions in Part C:**
- Google Tasks (INT-05)
- email as an enrichment input (PRO-05)
- a lead-conversion-status tool (MCP-02)
- team filters in reports (INS-05)
- job title in reverse lookup (PRO-07)
- activity participants
- the tailored sign-up questionnaire (CUS-08)
- which interface languages beyond en and no (CUS-05)

**Q-56 ◻ Flow headers against steps.** Several flows use features not in their "Uses" line, and the reverse
(list in 05, Part 5, question 14). Should end-to-end tests cover the header features or only the steps?

**Q-57 ◻ Part H bookkeeping.**
- Six specs cite no research row, not five.
- UF-29 and SF-34 are missing from the gap history.
- Part H says "four gaps", but its table has eight rows.

---

## Findings in today's code (no question, carried into Phase B)

| # | Finding | Evidence |
|---|---|---|
| F-1 | A failed TOTP enrolment shows no message | `03` R-1; `app/mfa/MfaForms.tsx:66-69` |
| F-2 | The connection test shows a raw code («http_503») | `03` R-2; `lib/platform/command.ts:31` |
| F-3 | At 390 px the header's «Logg ut» touches the right edge | `03` R-3; `screens/baseline/status-390.png` |
| F-4 | No favicon (a 404 in the console) | `03` R-4 |
| F-5 | A non-admin account can enrol a TOTP factor before learning it has no access | `03` R-5 |
| F-6 | `app.audit` has no TRUNCATE guard | Q-22 |
