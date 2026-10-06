# 06 — Questions

Phase A, A3.6. Rewritten on 2026-10-06 after decision **D-01**: everything is built new in the platform,
and no earlier system is a source or a reference. Where the brief says something "already exists in the
admin", it is something to build. Contacts, consent, segments, tickets and so on live in the platform.

Each question gives what was found, a **recommendation** and what it blocks. Answer per number, or
"follow the recommendations" with exceptions. Answers go into `DECISIONS.md`.

**Legend.** ⛔ blocks Phase B as a whole · 🧱 blocks the data model or security design · ◻ blocks one module or phase.

---

## ⛔ Blocking

**Q-01 ⛔ Access to the hosted Supabase projects (action for Tor).**
- *Found:* since 2026-10-06 the Supabase tools and the Management API token are refused for every project
  ("FGA Authentication Error"), probably after the projects moved organisation. Both sites answer normally,
  but nothing can be applied to or read from the databases from here.
- *Action:* reconnect the Supabase connector to the new organisation, and put a new access token in the
  environment variable `SB_MCP_PAT`.

**Q-02 ⛔ Development project, demo tenant and sandbox (R8).**
- *Found:* the only project is production. There is no seed and no demo tenant (Lumio AS, Kari Nordmann).
  The platform can send commands to live Orgpuls, including `orgs.delete_now` and `billing.cancel`.
- *Recommendation:* a separate Supabase development project or branch, plus a seed with the demo tenant in
  this repository. In development and in the sandbox, product commands go to a local stand-in, never to live Orgpuls.

**Q-03 ⛔ Test tooling (A8).**
- *Found:* vitest only. No database tests and no end-to-end tool.
- *Recommendation:* Playwright for end-to-end, visual and accessibility tests. Database tests as SQL files
  that raise on failure, run by psql against a database rebuilt from migrations in CI.

**Q-04 ⛔ Interface language (conflict, CUS-05).**
- *Found:* your decision in Appendix 2 is "Admin UI language: English", and CUS-05 makes English the default with a
  per-user locale. The design is in English. Today the platform defaults to bokmål with English by cookie.
- *Recommendation:* English as default, bokmål available, language and time zone per admin (default Europe/Oslo).

**Q-05 ⛔ Job runtime (open point 3).**
- *Found:* no scheduler, queue or worker exists.
- *Recommendation:* pg_cron and pgmq in this Supabase project, with edge functions as workers. No extra service.

**Q-06 ⛔ One workflow engine (open point 1).**
- *Found:* AUT, CMP-07 and Part G "extend the lifecycle-messaging engine"; under D-01 that engine is built new.
- *Recommendation:* one engine built in phase 0 that runs workflows, sequences, lifecycle messages and assignment.

**Q-07 ⛔ Providers (open point 2).** Each is a new dependency under R9.
- *Recommendation:* decide per phase, and only what the next phase needs.
  - Email sending: one provider with separate transactional and marketing streams.
  - Mailbox sync: Gmail and Microsoft Graph directly.
  - LLM: Claude.
  - Brønnøysund: its open API.
- Transcription, e-signature, person data, telephony, maps and accounting are chosen before their phases.

## 🧱 Data model and security

**Q-08 🧱 Staff roles (open point 10).**
- *Found:* `app.admins` has `owner`/`admin`, and nothing reads the role.
- *Recommendation:* permission sets (SEC-07) with presets: super-admin, support, finance, analyst (read-only),
  sales, marketing and project. `app.admins` is extended into the staff table (user_id, role/permission set,
  created_by, active).

**Q-09 🧱 How visibility is enforced.**
- *Found:* the brief says RLS policies. The platform's rule is RLS on, no policy and no client grant, with all
  access through security-definer functions gated on `app.is_admin()`.
- *Recommendation:* keep the platform's rule. Owner, group and everyone visibility is checked inside the functions,
  with database tests per role. This keeps today's "no client can touch a table" guarantee.

**Q-10 🧱 Are all CRM users staff in `app.admins`?**
- *Recommendation:* yes. One kind of user, with a profile (name, phone, language, time zone) and a permission set.

**Q-11 🧱 Second factor.**
- *Found:* TOTP is required for everyone today. SEC-06 reads as a switch and wants an email code and recovery.
- *Recommendation:* MFA always on, as a fixed rule beside the anonymity firewall. TOTP only. Recovery codes,
  plus a reset by the owner.

**Q-12 🧱 Audit log.**
- *Found:* `app.audit` records only product commands. It has no reason, target or reads, and no TRUNCATE guard.
- *Recommendation:* extend `app.audit` with action, target, organisation, reason and detail. Make product and
  command optional. Audit every write and every read of customer data. Add a TRUNCATE guard. A typed reason
  stays a setting, off by default.

**Q-13 🧱 Organisations and people.**
- *Found:* `app.accounts` and `app.members` are mirrors that product events overwrite. A member always belongs to
  one product tenant, so a prospect cannot be one.
- *Recommendation:* new CRM tables (organisations, people, leads, deals and so on). An organisation links to
  `accounts` by org.nr; a person links to `members` where they are a product user. Product events never
  overwrite fields a person has edited.

**Q-14 🧱 Events table.**
- *Found:* `app.events_in` is for product events only (product source id required).
- *Recommendation:* keep `events_in` for products, and add one platform events table for CRM and outbound
  events. Event names stay `object.action` (dotted), as today.

**Q-15 🧱 Settings register.**
- *Found:* A9 wants key, type, options, default, scope and IDs. Part C lacks keys and scope; the design has keys.
- *Recommendation:* use the design's keys. Each setting has a scope (platform, user or pipeline). The anonymity
  firewall is shown read-only and cannot be changed.

**Q-16 🧱 Rules and numbers that have no register row.**
- *Found:* several feature rules and source numbers restrict without a setting:
  - permissions for labels, bulk edit, export and settings
  - required fields and a mandatory lost reason
  - the 30-day restore window and "5 days without reply"
  - the 100-record bulk limit, a 90-day path and 7-day wait in automations, and 10 signers
  - a ">3 failed logins" alert and 60-day login history
- *Recommendation:* each becomes a setting that defaults to unrestricted (R5). The source number is only a
  reference. Exception, see Q-27: the marketing-law and provider rules.

**Q-17 🧱 Plans and entitlements (ENT) in an internal admin.**
- *Recommendation:* ENT means the platform's own module switches and usage counters for its own staff, all on
  and unlimited by default. Nothing is sold. "Credits" only count provider usage.

**Q-18 🧱 Storing users' provider tokens (OAuth for mail and calendar).**
- *Recommendation:* Vault, one secret per token, read only through security-definer functions.

**Q-19 🧱 Survey figures in the platform.**
- *Found:* the platform receives no survey data. The design has a Customers › Surveys tab.
- *Recommendation:* the platform shows no survey figures at all, only the metadata Orgpuls already sends.
  The tab shows survey counts and dates (Q-21), never answers.

## ◻ Modules and phases

**Q-20 ◻ Orgpuls' inbound events and ticketing.**
- *Found:* `support.requested`, `contact.submitted` and `demo.requested` are stored raw and become nothing.
  Ticketing is in Appendix 2 and the design, but not in Part C.
- *Recommendation:*
  - `support.requested` becomes a ticket.
  - `contact.submitted` becomes a ticket and a lead.
  - `demo.requested` becomes a lead.
  - Ticketing (Appendix 2) is built in phase 0/1.

**Q-21 ◻ More events from Orgpuls (funnel and health score).**
- *Recommendation:* Orgpuls adds count-only events, each with a field list that carries no respondent data:
  - survey scheduled and sent
  - result unlocked
  - results viewed
  - tiltak created
  - logins by role
- The platform computes the health score and the funnel from them.

**Q-22 ◻ Money in the billing mirror, payments and trial.**
- *Found:* `billing.changed` has no price or seats. Appendix 2 says Stripe and a 30-day trial; Orgpuls today has a
  15-day trial and no Stripe.
- *Recommendation:* Orgpuls adds price, currency and seats to `billing.changed`, and the platform mirrors them.
  Stripe waits until Orgpuls takes payments. Use Orgpuls' current terms.

**Q-23 ◻ Product content (question sets, tiltak, legal texts, translations).**
- *Recommendation:* the content stays in Orgpuls, and the platform gets screens that use the existing commands.

**Q-24 ◻ Retention and erasure.**
- *Recommendation:* raw product events are kept 13 months and then purged. Erasing a person deletes the person's
  rows and blanks their name and email in stored events.

**Q-25 ◻ Product key and the name «products».**
- *Recommendation:* keep the column `product` (text) on product-scoped tables. Call the CRM's sales catalog
  `catalog_items`, so it does not collide with `app.products`.

**Q-26 ◻ Existing technical limits.**
- *Found:* events are capped at 500 per batch and 1 MB, and commands at 200 kB and 50 arguments.
- *Recommendation:* keep them as technical safeguards, documented, outside the register.

**Q-27 ◻ Consent defaults and the law (open point 4).**
- *Recommendation:*
  - Keep the brief's defaults: consent checks on sales mail and import off; recording notice on.
  - Make these campaign rules fixed rather than settings, since they are law or provider requirements: the
    unsubscribe link and sender identity in every campaign; no campaign to unsubscribed people; no sending from
    an unauthenticated domain.
  - A legal review of the unrestricted defaults happens before go-live. Who does it?

**Q-28 ◻ Public pages.**
- *Found:* report links, booking pages, forms, chat, document share and signature pages, and the AI connector's
  OAuth all need public paths.
- *Recommendation:* approve in principle, on a separate host (for example `go.owntheagenda.com`), with
  unguessable, revocable tokens.

**Q-29 ◻ Session timeout, IP allowlist, login alerts.**
- *Recommendation:* all three are settings. The 30-minute idle timeout is on; the IP allowlist and login
  alerts are off.

**Q-30 ◻ Destructive product commands.**
- *Recommendation:*
  - Always show a preview.
  - Deleting an organisation needs its org.nr typed in.
  - A second admin's approval is a setting, off by default.

**Q-31 ◻ SSO.**
- *Recommendation:* later. Google or Microsoft sign-in, still followed by TOTP.

**Q-32 ◻ Outbound webhooks.**
- *Recommendation:* sign them with HMAC-SHA256, the scheme the platform already uses, and block private and
  internal addresses.

**Q-33 ◻ Local database by the repository's own commands.**
- *Recommendation:*
  - Add `supabase/config.toml` (with TOTP on) and `supabase/seed.sql`.
  - Allow `http://127.0.0.1` as the Supabase URL in development only.

**Q-34 ◻ Proving the anonymity firewall.**
- *Recommendation:* the platform's tests prove that no response-level table or column exists here and that
  no product event kind carries respondent fields. The command replies get a contract test.

**Q-35 ◻ Backups, recovery and region.**
- *Found:* the design shows Stockholm and RPO 1 h / RTO 4 h. The project is in eu-central-1 (Frankfurt).
- *Recommendation:* show the real region. Move to a plan with point-in-time recovery before CRM data is
  entered. Targets: RPO 1 h, RTO 4 h.

**Q-36 ◻ Components.**
- *Recommendation:* recreate the design's components exactly in Tailwind (pixel-faithful, from the bundle's
  tokens and fonts), without shadcn/ui.

**Q-37 ◻ Web tracker.**
- *Recommendation:* the tracker runs on the marketing sites only, never in a product. A visitor's company is
  resolved from the IP at ingest, and the IP is never stored.

**Q-38 ◻ Mobile and desktop.**
- *Recommendation:* out of scope until the web modules are done. Then a PWA. The desktop recorder is decided with
  meeting intelligence.

**Q-39 ◻ The brief's open points 5–9.**
- *Recommendation:*
  - LinkedIn connector (LEA-06): left out until it is defined.
  - The three inventory rows outside the 183: left out.
  - Recording: a notice 24 hours ahead, and a person can opt out.
  - Performance targets: set in Phase B from measurements.
  - Naming: R12 is enough.

**Q-40 ◻ Integration details the design shows that do not exist.**
- *Found:* events such as `orgpuls.survey.sent` and remote actions such as suspend, export, support access and flags.
- *Recommendation:* treat them as targets. Add Orgpuls commands and events when a feature needs them.

**Q-41 ◻ Gaps in the design.** Not found in the design:
- suppression in group email
- the booking time zone
- removing the meeting bot
- the affected-users preview
- the chat waiting time
- the top-up action
- a "which setting stopped you" message
- Asana and Trello actions
- subtasks

*Recommendation:* build them in the design's language.

**Q-42 ◻ The brief's own consistency.**
- *Found:* the counts are confirmed (183 features, 29 user flows, 45 system flows), and all 276 research rows are
  accounted for. Open items:
  - PIP-17 (deal duplication) has no research source.
  - Five marketplace categories have no connector spec.
  - Named apps (Zendesk, Mailchimp, Stripe and others).
  - Small omissions: Google Tasks, email as an enrichment input, a lead-conversion tool for the AI connector,
    team filters in reports, job title in reverse lookup, activity participants.
  - Flow headers that do not match their steps.
- *Recommendation:*
  - Keep PIP-17.
  - Cover the categories with the first-party modules, and named apps through the catalog and automation platforms.
  - Add the small omissions.
  - End-to-end tests follow the flow steps.

---

## Findings in today's code (no question, fixed in Phase B)

| # | Finding | Evidence |
|---|---|---|
| F-1 | A failed TOTP enrolment shows no message | `03` R-1 |
| F-2 | The connection test shows a raw code («http_503») | `03` R-2 |
| F-3 | At 390 px the header's «Logg ut» touches the right edge | `03` R-3 |
| F-4 | No favicon (a 404 in the console) | `03` R-4 |
| F-5 | A non-admin account can enrol TOTP before learning it has no access | `03` R-5 |
| F-6 | `app.audit` has no TRUNCATE guard | Q-12 |
