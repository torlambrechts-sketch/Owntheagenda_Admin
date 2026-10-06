# Decisions

Tor's answers to the questions in `06-QUESTIONS.md`, recorded with the date (rule R3). Order of authority:
these decisions, then the rules in A2, then Parts C–G, then the appendices.

| Date | Question | Decision |
|---|---|---|
| 2026-10-06 | D-01 (replaces former Q-01, Q-02) | Everything is built new in the platform. Nothing from any earlier admin is reused or used as a reference. Where the brief says something «already exists in the admin», it is to be built. Contacts, consent, segments, tickets and the rest live in the platform. (Tor: «Ikke husk NOE AV DET GAMLE! … alt nytt.») |
| 2026-10-06 | D-02 (Q-02) | A separate Supabase development project or branch; a seed with the demo tenant (Lumio AS, Kari Nordmann) in this repository; product commands from development and sandbox go to a local stand-in, never to live Orgpuls. |
| 2026-10-06 | D-03 (Q-03) | Playwright for end-to-end, visual and accessibility tests; database tests as SQL files that raise on failure, run by psql against a database rebuilt from migrations in CI. |
| 2026-10-06 | D-04 (Q-04) | English is the default interface language, bokmål available; language and time zone per admin (default Europe/Oslo). |
| 2026-10-06 | D-05 (Q-05) | Job runtime: pg_cron and pgmq in this Supabase project, with edge functions as workers. |
| 2026-10-06 | D-06 (Q-06) | One workflow engine, built in phase 0, runs workflows, sequences, lifecycle messages and assignment. |
| 2026-10-06 | D-07 (Q-07) | Providers chosen per phase: one email provider with separate transactional and marketing streams; Gmail and Microsoft Graph directly for mailbox sync; Claude as the LLM; Brønnøysund's open API. Others chosen before their phase. |
| 2026-10-06 | D-08 (Q-08) | Staff roles as permission sets (SEC-07) with presets super-admin, support, finance, analyst (read-only), sales, marketing, project; app.admins is extended into the staff table. |
| 2026-10-06 | D-09 (Q-09) | Visibility is enforced inside security-definer functions (RLS on, no policy, no client grant stays), tested per role. |
| 2026-10-06 | D-10 (Q-10) | All CRM users are staff rows with a profile (name, phone, language, time zone) and a permission set. |
| 2026-10-06 | D-11 (Q-11) | MFA is always on, a fixed rule beside the anonymity firewall; TOTP only; recovery codes plus an owner reset. |
| 2026-10-06 | D-12 (Q-12) | app.audit is extended (action, target, organisation, reason, detail; product and command optional); every write and every read of customer data is audited; TRUNCATE guard; a typed reason is a setting, off by default. |
| 2026-10-06 | D-13 (Q-13) | New CRM tables (organisations, people, leads, deals …); an organisation links to app.accounts by org.nr, a person to app.members where they are a product user; product events never overwrite edited fields. |
| 2026-10-06 | D-14 (Q-14) | app.events_in stays for products; a new platform events table (outbox) carries CRM and outbound events; names stay object.action. |
| 2026-10-06 | D-15 (Q-15) | The settings register uses the design's keys; each setting has a scope (platform, user, pipeline); the anonymity firewall is shown read-only. |
| 2026-10-06 | D-16 (Q-16) | Every feature rule and source number becomes a setting defaulting to unrestricted; the source number is a reference only. |
| 2026-10-06 | D-17 (Q-17) | ENT means the platform's own module switches and usage counters, all on and unlimited by default; nothing is sold; credits count provider usage only. |
| 2026-10-06 | D-18 (Q-18) | Users' provider tokens live in Vault, one secret per token, read only through security-definer functions. |
| 2026-10-06 | D-19 (Q-19) | The platform shows no survey figures, only metadata Orgpuls sends (counts and dates). |
| 2026-10-06 | D-20 (Q-20) | support.requested → ticket; contact.submitted → ticket and lead; demo.requested → lead; ticketing (Appendix 2) is built in phase 0/1. |
| 2026-10-06 | D-21 (Q-21) | Orgpuls adds count-only events (survey scheduled/sent, result unlocked, results viewed, tiltak created, logins by role); health score and funnel are computed in the platform. |
| 2026-10-06 | D-22 (Q-22) | Orgpuls adds price, currency and seats to billing.changed; Stripe waits; Orgpuls' current terms apply. |
| 2026-10-06 | D-23 (Q-23) | Product content stays in Orgpuls; the platform gets screens that use the existing commands. |
| 2026-10-06 | D-24 (Q-24) | Raw product events are kept 13 months; erasing a person deletes their rows and blanks name and email in stored events. |
| 2026-10-06 | D-25 (Q-25) | Keep the column product (text); the CRM sales catalog is catalog_items. |
| 2026-10-06 | D-26 (Q-26) | The existing technical limits (500 events and 1 MB per batch, 200 kB and 50 arguments per command) stay as documented safeguards outside the register. |
| 2026-10-06 | D-27 (Q-27) | The brief's consent defaults stand; the unsubscribe link and sender identity, no campaign to unsubscribed people and no sending from an unauthenticated domain are fixed rules; a legal review precedes go-live. |
| 2026-10-06 | D-28 (Q-28) | Public pages are approved on a separate host (go.owntheagenda.com) with unguessable, revocable tokens. |
| 2026-10-06 | D-29 (Q-29) | Session idle timeout 30 minutes on; IP allowlist and login alerts are settings, off. |
| 2026-10-06 | D-30 (Q-30) | Destructive product commands: preview always, org.nr typed to delete, second-admin approval a setting (off). |
| 2026-10-06 | D-31 (Q-31) | SSO later (Google or Microsoft), still followed by TOTP. |
| 2026-10-06 | D-32 (Q-32) | Outbound webhooks are signed with HMAC-SHA256; private and internal addresses are blocked. |
| 2026-10-06 | D-33 (Q-33) | supabase/config.toml (TOTP on) and supabase/seed.sql in the repository; http://127.0.0.1 allowed as the Supabase URL in development only. |
| 2026-10-06 | D-34 (Q-34) | Tests prove that no response-level table or column exists here and that no product event kind carries respondent fields; command replies get a contract test. |
| 2026-10-06 | D-35 (Q-35) | Show the real region (eu-central-1); point-in-time recovery before CRM data is entered; targets RPO 1 h, RTO 4 h. |
| 2026-10-06 | D-36 (Q-36) | The design's components are recreated exactly in Tailwind from the bundle's tokens and fonts, without shadcn/ui. |
| 2026-10-06 | D-37 (Q-37) | The tracker runs on marketing sites only; the company is resolved from the IP at ingest and the IP is never stored. |
| 2026-10-06 | D-38 (Q-38) | Mobile and desktop wait until the web modules are done; then a PWA; the desktop recorder is decided with meeting intelligence. |
| 2026-10-06 | D-39 (Q-39) | LinkedIn connector left out until defined; the three inventory rows outside the 183 left out; recording notice 24 h ahead with opt-out; performance targets set from measurements; R12 suffices for naming. |
| 2026-10-06 | D-40 (Q-40) | Integration details the design shows are targets; Orgpuls commands and events are added when a feature needs them. |
| 2026-10-06 | D-41 (Q-41) | Gaps in the design are built in the design's language. |
| 2026-10-06 | D-42 (Q-42) | Keep PIP-17; marketplace categories via first-party modules; named apps through the catalog and automation platforms; add the small omissions; end-to-end tests follow flow steps. |

Tor, 2026-10-06: «Gå med dine anbefalinger og full implementasjon av design.» Every recommendation in `06-QUESTIONS.md` is accepted (D-02 to D-42), and the whole design in `design-reference/sentral/` is to be implemented.
