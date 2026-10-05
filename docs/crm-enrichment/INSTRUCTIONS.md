# Orgpuls Admin — CRM Enrichment: Implementation Instructions for Claude Code

Version 1.0 · 3 October 2026 · Owner: Tor

This file is the complete brief for enriching the Orgpuls platform admin with the researched CRM feature set. It holds the working rules, the gap-analysis method, the implementation and verification standards, and the full specification: **183 features, 29 user flows, 45 system flows**, the settings register, the data model, and both source documents in full.

## Contents

| Part | What it holds |
| --- | --- |
| For Tor | How to start Claude Code with this file |
| Part A | Instructions: rules, gap analysis, implementation plan, implementation, standards, verification, reporting |
| Part B | Baseline: what the Orgpuls admin specification already defines, and how its rules are applied |
| Part C | Feature specifications: 183 features in 21 modules, plus the settings register |
| Part D | User flows: UF-01 to UF-29 |
| Part E | System flows: SF-01 to SF-45 |
| Part F | Data model and API |
| Part G | Feature map, architecture choices, phases, non-functional requirements, open points |
| Part H | Coverage: every researched feature mapped to a specification |
| Appendix 1 | Pipedrive feature inventory: the research, in full |
| Appendix 2 | Orgpuls platform admin specification, in full |

## For Tor: how to start

1. Put this file in the Orgpuls admin repository, for example at `docs/crm-enrichment/INSTRUCTIONS.md`, and commit it.
2. Start Claude Code in the repository root. To let it read and plan before it may change anything, start it in plan mode.
3. Give it this prompt:

```text
Read docs/crm-enrichment/INSTRUCTIONS.md from the first line to the last before doing anything else.
Confirm you have read every part and both appendices by stating how many features, user flows
and system flows it defines and by listing the twelve rules in section A2 in your own words.
Then start Phase A (section A3). Do not change application code or the database until I approve
the gap analysis.
```

4. The correct answer to the check is 183 features, 29 user flows and 45 system flows. Any other answer means the file was not read in full.

---

## Part A — Instructions

### A1. Mission

Enrich the Orgpuls platform admin with every feature in Part C, on top of what is implemented today. The work has three outcomes, in this order:

1. **Gap analysis.** A complete, evidenced comparison of what is implemented today with (a) the admin specification in Appendix 2 and (b) the 183 features, 29 user flows, 45 system flows and the settings in this file.
2. **Implementation plan matched to the real code.** Work packages that extend the existing tables, routes and components instead of duplicating them.
3. **Full implementation.** Every feature built, tested at the database level, verified visually and reviewed for security.

The admin is an internal back-office shared across products. It is not a tenant product. The baseline and its rules are in Part B.

### A2. Rules

These twelve rules override everything else in this file. When a rule and a specification seem to conflict, stop and ask (R3).

**R1. Read everything in full.** Read this file to its last line before acting. Read every repository file you rely on from start to end. When a file is too long for one read, read it in consecutive chunks until the end. Never infer the unread part of a file, a table or a document.

**R2. Make no assumptions.** Every statement about the code base must cite what you read: file path and line range, or the name of the table, policy, function or test. This file describes the target and a specification of the admin; it does not describe the code. Anything not found in the repository or in this file is unknown, and unknowns become questions.

**R3. Ask when unsure.** If two readings are possible, if a decision is not covered here, or if the code contradicts this file, stop that piece of work and ask Tor. Use the format in A11. Never choose silently, and never fill a gap with a guess. Record every answer in `docs/crm-enrichment/DECISIONS.md` with the date.

**R4. Skip nothing.** Every feature ID, every acceptance criterion, every user flow, every system flow, every setting and every entity is either implemented and verified, or listed in the gap report with its status, the reason and Tor's written decision. No stubs, no TODO markers, no mock data, no placeholder screens and no "coming soon" in delivered work.

**R5. Build no restrictions in.** Every limit, plan gate, quota, approval step and compliance rule is a setting, and each setting's default leaves the feature fully working and unrestricted. Never hard-code a cap, a gate or a check that blocks a feature. If you believe a restriction is needed, implement it as a setting that is off by default and tell Tor. The settings register is in Part C under Customization, and A9 explains how to build it.

**R6. The anonymity firewall is the one fixed rule.** It is not a setting, because the admin specification makes it a platform constant. No CRM code path may read survey responses or respondent identities. No foreign key, view, function, grant, search index, export, report, AI context or connector tool may reach response-level tables. The site tracker and widgets never load in the survey flow. Survey respondents never become CRM contacts through any path that reads product data. Database tests must prove this (A8).

**R7. Never weaken what exists.** Do not remove or loosen existing row-level-security policies, role checks, MFA, audit logging or tests. Do not change the behavior of existing admin features unless the gap analysis shows it is necessary and Tor approves the change.

**R8. Protect data and environments.** Never run against production. Never use real customer data. Work on a branch, against a local or development database, with the seeded demo tenant; the admin specification names Lumio AS and Kari Nordmann, so verify that seed exists and ask if it does not. No destructive migration (drop, rename, type change, data rewrite) without Tor's explicit approval. Secrets stay in environment configuration and never appear in code, logs, tests or screenshots. The service-role key never reaches the browser.

**R9. Match the code base.** Follow the repository's existing structure, naming, lint rules, formatting, component library, design tokens, migration tooling and test tooling. Do not add a library, service or pattern when an existing one does the job. If a new dependency or tool is needed, ask first and give the reason and the alternatives.

**R10. Pass every quality gate.** Nothing is done until type check, lint, unit tests, database tests, end-to-end tests, visual verification and the security checklist all pass. A failing gate is fixed. It is never skipped, disabled, loosened or marked as expected to fail.

**R11. Report honestly.** State what was not done, what was not verified and what failed. Never report a feature as complete without the evidence listed in A10.

**R12. Replicate functions only.** The feature set was researched from Pipedrive. Do not copy Pipedrive's names, text, icons or screen layouts. Use the neutral names in Part C and the admin's own design system.

Order of authority when sources differ: Tor's recorded decisions, then the rules in A2, then Part C to Part G, then the appendices. The repository is the only authority on what exists today. Report every difference you find between these sources; do not resolve it yourself.

### A3. Phase A — Discovery and gap analysis

No application code or database change in this phase. Write all outputs to `docs/crm-enrichment/`.

**A3.1 Environment.** Read the README, any `CLAUDE.md`, the `docs/` folder, every configuration file, the package manifest and lockfile, the CI workflows, the environment examples and the whole Supabase folder (configuration, migrations, seeds, functions, tests). Record, with a file reference for each fact:

- Package manager, scripts, framework and library versions.
- Where the admin lives and how it is separated from the customer product.
- How sign-in, admin roles, MFA and the audit log work, with the real names of the tables and functions involved.
- How migrations are created and applied, how types are generated, how seeds are loaded.
- Background jobs and scheduled work, the email provider integration, the billing mirror, feature flags.
- The component library, design tokens and layout shell of the admin.
- Which test tools exist for units, end-to-end and the database, and how CI runs them.

Output: `01-ENVIRONMENT.md`. List every fact you could not establish as a question.

**A3.2 Database inventory.** Read every migration file in order. If a local database can be started with the repository's own commands, introspect it as well and reconcile the two; report any drift. Record every schema, table, column, type, constraint, index, foreign key, view, function, trigger, policy, grant, extension, scheduled job and storage bucket. For each table state whether row-level security is on and list each policy with its roles and expressions. Classify each table as admin, product, response-level or CRM. The response-level list is the firewall list for R6.

Output: `02-DATABASE.md`. Do not connect to production. If no local database can be started, stop and ask.

**A3.3 What is implemented today.** Cover the whole admin, not only the CRM. Enumerate every route, page and layout; every server action, route handler and endpoint; every edge function and job; every email template and feature flag. For each, record what it does, what data it reads and writes, which role checks it applies and which tests cover it. Then run the admin locally with the repository's documented commands and the demo tenant, open every route, and capture baseline screenshots at desktop width (1440 px) and mobile width (390 px) into `screens/baseline/`. Note every runtime error. If the admin cannot be run locally, stop and ask.

Output: `03-IMPLEMENTED-TODAY.md`.

**A3.4 Gap against the admin specification.** Go through Appendix 2 section by section and bullet by bullet. Give each item a status with evidence.

Output: `04-GAP-ADMIN-SPEC.md`.

**A3.5 Gap against this specification.** Give a status to each of the 183 features, sentence by sentence against its description, rules and acceptance criteria. Do the same for each step of the 29 user flows and 45 system flows, each setting in the register, each entity and convention in Part F and each non-functional requirement in Part G.

Use exactly these statuses:

| Status | Meaning |
| --- | --- |
| Implemented | Every sentence of the specification is met, tests exist and pass, and you have seen it work on screen |
| Partial | Some of it exists. List exactly which sentences are met and which are not |
| Missing | Nothing of it exists |
| Conflict | Existing behavior contradicts the specification. Describe both sides |
| Unknown | You could not determine the status. This becomes a question |

Use this row format for every ID:

| Column | Content |
| --- | --- |
| ID and name | For example PIP-05 Deal rotting |
| Status | One of the five above |
| Evidence | File paths with line ranges, table and policy names, test names, screenshot file |
| Missing or different | The exact sentences of the specification that are not met, or the conflict |
| Settings | The settings from the register that apply |
| Depends on | Other IDs, existing admin features, providers |
| Work package | Filled in during Phase B |

Output: `05-GAP-FEATURES.md`, with a summary table of counts per module and status at the top.

**A3.6 Questions and conflicts.** Collect every Unknown, every Conflict and every difference between the code, Appendix 2 and this file. Add the open points from Part G. Output: `06-QUESTIONS.md`.

**A3.7 Stop.** Present the summary counts, the ten largest gaps and the question list. Wait for Tor's approval and answers before Phase B.

### A4. Phase B — Implementation plan matched to the code

Still no application code. Output: `07-IMPLEMENTATION-PLAN.md`.

1. **Data model mapping.** For every entity proposed in Part F, name the existing table to extend or the new table to create, with columns, types, constraints, indexes and policies. Extend existing tables; never create a second table for organizations, contacts, consent, segments, events, tickets or anything else the admin already has. The table names in Part F are proposals. Include a relationship diagram.
2. **Decisions to put to Tor, with options and consequences.** At least: which schema the CRM tables live in; which staff roles or permission sets sales, marketing and project users get (open point 10); the job runtime for long-running work (open point 3); the provider for each external service (open point 2); whether outbound webhook payloads are signed; the safe defaults for abuse protection on public endpoints (A7).
3. **Work packages.** Group the gaps into packages small enough to review. For each: the IDs it closes, the migrations, the server and interface changes, the settings it registers, the tests, the screens and states to verify, and what it depends on.
4. **Order.** Use the phases and gates in Part G, adjusted to the real code. Anything in Appendix 2 that this work depends on and that is not yet built comes first.
5. **Test plan.** For each package list the database tests, unit tests, end-to-end tests and the visual states.
6. **Stop.** Wait for Tor's approval before Phase C.

### A5. Phase C — Implementation

Work one package at a time, in this order:

1. Re-read in full the specification rows, flows, settings and data-model entries the package covers.
2. Write the migration and its database tests together. Run them on a fresh database and on a database with the demo seed.
3. Build the server layer: validation, role and permission checks, visibility, audit rows, changelog entries and events.
4. Build the interface with the admin's existing components. Cover every state: loading, empty, populated, error, permission denied, long content, and the mobile layout.
5. Register every setting the package introduces, with its default. Verify the feature with the setting off and with it on.
6. Write unit and end-to-end tests for the logic and the flows the package touches.
7. Run the visual verification in A8.
8. Run the security checklist in A7.
9. Update `05-GAP-FEATURES.md`: status, evidence and screenshot references for each ID.
10. Commit in small, described steps. Run every quality gate.

At the end of each phase in Part G, run the gate flows named there, write the phase report (A11) and stop for Tor's review.

### A6. Database standards

Verify each of these against the repository's existing conventions first. Where the repository already does it differently, follow the repository and report the difference.

- **Tooling.** Use the existing migration tooling and naming. Never edit a migration that has been applied; add a new one.
- **Row-level security.** Enable it on every new table and write explicit policies. No table is readable or writable by customer roles or by anonymous users. Access goes through the admin's role check; Appendix 2 names it `is_platform_admin(role)`, so verify the real name.
- **Product key.** Appendix 2 puts a product ID on every admin table. Verify how existing tables do this and do the same.
- **Standard columns.** Created and updated timestamps and actors, a deleted timestamp for soft delete, a version number for optimistic concurrency, and owner and visibility where the specification gives a record an owner.
- **Integrity in the database.** Not-null, check and unique constraints and foreign keys with an explicit delete behavior, not checks in application code alone.
- **Indexes.** Every foreign key and every column used to filter, sort or join. Custom field values in JSON get an index for each filterable field.
- **One transaction per change.** The row, its changelog entry, its audit row and its event are written together or not at all (SF-02).
- **Soft delete.** Thirty days, then a purge job (CRM-12, SF-15).
- **Configuration as data.** Pipelines, fields, workflows, sequences, reports, templates, scoring models, permission sets and settings are versioned rows.
- **Firewall.** CRM roles and functions hold no privilege on any table in the firewall list. No foreign key, view or function references them.
- **Seeds.** Extend the demo tenant seed with CRM demo data. Never copy real data.
- **Types.** Regenerate database types after every migration with the repository's own command.

### A7. Security standards

Record the result of this checklist per package in `docs/crm-enrichment/security/`.

1. Every server entry point checks session, admin role, permission and visibility before touching data, and denies by default. Hiding something in the interface is never the control.
2. No secret and no service-role key in client bundles. Verify the built output.
3. Validate every input at the boundary with the validation approach the repository already uses.
4. Sanitize all rich text and HTML that users or external systems supply: notes, comments, email bodies, the HTML block of the email builder, templates, form submissions, transcripts.
5. Validate file uploads by type and size, store them under the record's access rules, and never serve them from a public path.
6. Neutralize spreadsheet formulas in exports: cells beginning with `=`, `+`, `-` or `@`.
7. Outbound calls (webhooks, workflow webhook actions, provider adapters) must block private and link-local addresses and metadata endpoints, use timeouts, and never follow redirects into them.
8. Encrypt provider tokens and credentials at rest using the mechanism the repository already has. If there is none, ask.
9. Public surfaces (web forms, chatbot, live chat, tracker, booking pages, document share links, signature pages, public dashboard links) use unguessable, revocable tokens. Abuse protection on them is a technical safeguard, built as settings whose defaults never block legitimate use. Propose the defaults to Tor.
10. Treat all external content as untrusted in AI features: email bodies, transcripts, web pages and form text can carry instructions. The AI gateway never lets such content trigger a write. AI output is never written without the user's approval where the specification requires approval.
11. The audit log is append-only. Every write, and every read of customer-scoped data, writes an audit row. A typed reason is a setting, off by default.
12. API and connector calls run with the calling user's permissions. Tokens can be rotated and revoked at once.
13. Logs and error reports contain no message bodies, no tokens and no personal data beyond identifiers.
14. Run the repository's dependency audit. Add no dependency with known vulnerabilities.
15. If the repository uses the Supabase CLI, run `supabase db lint` and review Supabase's security and performance advisors after each migration. Fix each finding or explain why it does not apply. See https://supabase.com/docs/guides/local-development/cli/testing-and-linting and https://supabase.com/docs/guides/observability/advisors.
16. Prove the anonymity firewall with tests (A8) after every migration, not once.

### A8. Testing and verification

**Database tests are mandatory for every migration.** If the repository already has database tests, extend them in the same style. If it uses the Supabase CLI and has none, propose pgTAP tests run with `supabase test db` and ask before adding the setup. See https://supabase.com/docs/guides/database/testing and https://supabase.com/docs/guides/local-development/testing/pgtap-extended. Each package's database tests must cover:

- Structure: tables, columns, types, constraints, indexes and foreign keys exist as designed.
- Row-level security: enabled on every table, and an allow or deny result for every staff role, for customer users and for anonymous users, on select, insert, update and delete.
- Visibility: owner only, owner's group, group with sub-groups, everyone (SEC-08).
- Firewall: CRM roles have no privilege on response-level tables; no foreign key, view or function references them; a test that fails if one is added.
- Triggers and functions: changelog, audit rows, events, derived values, assignment, scoring, formulas, purge.
- Settings: every setting exists with its documented default, and the default leaves the feature unrestricted.
- Soft delete, restore and purge.
- Concurrency: a stale version is rejected.
- Every acceptance criterion in Part C that concerns data.

**Unit and integration tests** cover the pure logic with the repository's test runner: filters, scoring, assignment order, schedule and delay calculation, merge fields, formulas, derived revenue values, limit and setting evaluation.

**End-to-end tests** cover every user flow UF-01 to UF-29 and every system flow whose result is observable, with the repository's end-to-end tool. If there is none, propose one and ask.

**Visual verification is mandatory for every screen and every state.** Follow this protocol:

1. For each screen, list its states: loading, empty, populated, error, permission denied, long content, and each setting-dependent variant.
2. Capture each state at 1440 px and at 390 px, and in each theme the admin supports. Save the files as `screens/<phase>/<ID>-<state>-<width>.png`.
3. Open every image and inspect it yourself. Check layout, alignment, overflow, truncation, wrapping, contrast, focus styles, empty and error messages, and consistency with the baseline screenshots of the existing admin.
4. Fix what you find, capture again, and inspect again.
5. Add the screens to visual regression snapshots so later changes are detected.
6. Verify rendered output that is not a screen as well: campaign emails in their preview and test send, generated documents and PDFs, charts and exported files.
7. Record the result in a table in the phase report: screen, state, width, file, result, issues fixed.

Never state that an interface works without having looked at its screenshots.

**Accessibility.** Run an automated accessibility check on every new screen and do one keyboard-only pass: reachable, visible focus, logical order, labeled controls.

**Regression.** The existing test suite stays green, and the baseline screenshots of existing admin pages do not change unless the change is intended and listed.

**Performance.** Part G leaves the targets open. Measure pipeline load, search, report queries and list views with a realistic seeded volume, report the timings, and ask Tor for targets.

### A9. Settings: how "no restrictions" is built

- One settings registry holds every rule that can limit a feature. Each entry has a key, a type, its options, its default, its scope and the IDs it applies to. The register is the table "Settings managed in CUS-07" in Part C.
- Every default leaves the feature fully working. Limits default to unlimited. Plan gates default to all features on. Consent checks on sales email, second-admin approval, a typed reason for actions and consent-gated widget loading default to off. Tracking defaults to on.
- Workflow loop protection and the webhook retry and ban policy are technical safeguards. They are settings too, default to the source values in Part C, and can be changed or switched off.
- Feature code asks the registry (SF-34). It never hard-codes a rule.
- Every change to a setting is logged with who and when.
- The settings screen shows every setting, its current value and its default (UF-29).
- Each setting gets a test in both states.
- If a specification row states a number from the source product, treat it as a reference value for a setting, not as a built-in limit.
- The anonymity firewall is not in the registry and cannot be switched off (R6).

### A10. Definition of done

A feature is done only when all of these are true and recorded against its ID in `05-GAP-FEATURES.md`:

- Every sentence of its description, rules and acceptance criteria is implemented.
- Its settings are registered with their defaults and tested in both states.
- Its database tests, unit tests and end-to-end tests exist and pass.
- Its screens and states are captured, inspected and added to visual regression.
- Its security checklist is recorded.
- Its audit rows, changelog entries and events are written and tested.
- No stub, mock, TODO or placeholder remains.
- Type check and lint pass, and the whole existing suite is green.

A phase is done when every feature in it is done, the gate flows in Part G pass end to end, and Tor has reviewed the phase report.

The work is done when the gap report shows all 183 features, 29 user flows and 45 system flows as Implemented, or shows Tor's written decision for any that is not.

### A11. How to ask and how to report

**Asking.** One message. Numbered questions. For each: what you found (with file references), the options you see, what each option changes, and which work is blocked. Continue only with work the question does not affect. Record the answer in `DECISIONS.md`.

**Phase report.** Write `docs/crm-enrichment/reports/phase-<n>.md` with:

- IDs completed, with status changes.
- Migrations added.
- Test counts and results: database, unit, end-to-end, visual, accessibility.
- The visual verification table.
- The security checklist result.
- Settings added, with defaults.
- Deviations from this file, each with Tor's decision.
- What is not done or not verified, and why.
- Open questions.

### A12. Open points to raise with Tor

Part G lists ten open points. Raise each before the phase that needs it, and all of them in `06-QUESTIONS.md`. The ones that block design are: staff roles for sales, marketing and project users; the job runtime; the provider per external service; the definition of the LinkedIn connector in LEA-06; and the legal review of the unrestricted defaults.

If you find a researched feature in Appendix 1 with no specification in Part C, or a specification that differs from the research, stop and ask. Part H maps every research row to a specification so that this can be checked.

---

## Part B — Baseline: the Orgpuls admin

Source: the Build plan tab of "CRM Enrichment — Build Plan and Specifications", as of 3 October 2026. The full admin specification is in Appendix 2. This part describes a specification, not the code: Phase A establishes what is actually implemented. Where the text below names a tab, read it as a part of this file: Feature specifications is Part C, User flows is Part D, System flows is Part E, Data model and API is Part F, Coverage check is Part H.

### Goal and scope

The goal is to enrich the Marketing CRM of the Orgpuls platform admin with the full capability set inventoried from Pipedrive: 183 features in 21 modules, built as modules that read and write the CRM's own records instead of a second system beside it. Every feature has a specification with an ID, and the Coverage check tab maps each inventoried Pipedrive feature to one of those IDs.

| Item | Decision in this plan |
| --- | --- |
| What is built | Functional parity with the inventory: sales core, engagement, automation, intelligence, growth modules, platform services and channels |
| What is not copied | Pipedrive's names, branding, interface design and text. Modules carry neutral names (Feed, Meeting intelligence, Prospect search). The apps in Pipedrive's Marketplace, its partner discounts and its support tiers are not carried over; the platform to list apps is built (INT-11) |
| Build approach | Configuration is stored as data, not code: pipelines, fields, automations, sequences, report definitions, templates, scoring models and permission sets are rows that a registry and a workflow engine interpret |
| Target stack | Next.js, TypeScript, Tailwind, shadcn/ui, Supabase (Postgres with row-level security, Auth, Storage, Edge Functions), Vercel, EU data residency. This is the stack of the Orgpuls platform admin, which runs as a separate app shared across your products |
| Access model | An internal back-office, not a tenant product. Staff sign in through the admin's own role model with mandatory MFA; every table carries a product ID; every write and every read of customer-scoped data is audited; survey responses stay unreachable |
| Third-party services | Bought, not built: email and calendar providers, sending, telephony, transcription, language models, company and contact data, e-signature evidence. Each is behind an adapter so it can be swapped |
| Restrictions | Every limit, gate and compliance rule is a setting that defaults to unrestricted, so each feature works in full from the start. Only the anonymity firewall is fixed, because the admin specification makes it a platform constant |

The other tabs hold the detail: Feature specifications (one row per feature), User flows, System flows, Data model and API, Coverage check and Quality review.

Source of the feature set: [Pipedrive — Complete Feature Inventory](https://claude.ai/code/artifact/3530e663-e99c-4095-aa30-bc0ac2d83f22), reviewed on 3 October 2026.

Baseline: [Orgpuls — Platform Admin Specification](https://claude.ai/code/artifact/299692f9-4524-4966-8286-d79980fc2dbb) of 25 September 2026.

### Baseline and gap

The baseline is the Marketing CRM in the Orgpuls platform admin, an internal back-office shared across your products. Its specification already covers parts of 15 of the 21 modules, mostly on the marketing side, and sets rules on contacts, consent and anonymity. As decided on 3 October, those rules are built as settings that default to unrestricted; only the anonymity firewall stays fixed. Deals and pipelines, mail sync, documents, projects, meeting intelligence, the AI features and mobile are new. The admin's CRM is partly built; this plan does not assess what exists and specifies the full implementation.

#### What the admin specification already has

| Admin specification | Plan features it overlaps | What this plan does |
| --- | --- | --- |
| Organizations as the primary object: org.nr, list and detail views, internal notes and tags | CRM-01, CRM-13, CRM-14 | Extends the organization record; adds no second company table |
| Contacts: prospect, trial user, customer user, former customer; role, source, consent status, tags; activity timeline; CSV import with a consent source per row | CRM-01, CRM-02, CRM-09, CRM-15, LEA | Extends contacts. Leads are built as their own object, linked to contacts and organizations |
| Segments as saved filters | PIP-12, CMP-03 | Reuses the segment definition for filters and audiences |
| Campaign editor, campaign types, scheduling, subject-line test, reporting with UTM attribution | CMP-01 to CMP-06, CMP-09 | Specified in full; what the admin already has is extended, not rebuilt |
| Automated sequences on the lifecycle-messaging engine, triggered by events | AUT-01 to AUT-12, CMP-07 | Extends that one engine with record triggers, branches and CRM actions; no second engine |
| Consent basis per contact, unsubscribe, suppression list across all sends, separate marketing and transactional streams | CMP-04, CMP-08, COM-07, AUT-07, AUT-12 | Reuses the consent and suppression model; checks on sales email are a setting, off by default |
| One typed events table feeding the funnel, web analytics, CRM triggers and the health score | AUT-02, PRO-01, PRO-03, INT-04 | Registers CRM events in that table; uses product events as triggers and scoring signals |
| Health score per organization | PRO-03 | Uses it as a scoring criterion instead of building a parallel score |
| Ticketing with a Sales queue; the contact form creates a ticket and a consented prospect | LGN-03, LEA-04, ACT-01 | Web forms and leads reuse this inbound path |
| Cookieless web analytics with its dashboard in the admin | WEB-01 to WEB-04 | Adds company identification on top; tracking is a setting, on by default |
| Access model: platform admins table, four staff roles (super-admin, support, finance, read-only analyst), mandatory MFA, audit log, session timeout, optional IP allowlist, login alerts | SEC-01 to SEC-07, SEC-09 | Builds on it. SEC adds screens and rules, and SEC-07 adds the sales, marketing and project roles the admin does not define |
| Billing with Stripe as source of truth, EHF invoices through the accounting system | CRM-08, INT-08, ENT-03 | Recurring revenue for Orgpuls customers comes from the billing mirror, not from manual product lines |
| Metrics defined once as SQL views kept in git | INS-01 to INS-10 | Reports on business figures read those views |
| Seeded demo tenant; destructive actions with preview, second-admin approval and soft delete | CUS-08, CRM-12, PIP-10 | The sandbox is the demo tenant; second-admin approval is a setting, off by default |
| Organization list filters, saved views and a merge of duplicate organizations with the same org.nr | PIP-12, CRM-11 | Reuses the saved views; extends the merge to contacts |
| Privacy operations: request queue with a 30-day clock, deletion queue, retention, DPA tracking, subprocessor and incident registers | SEC-10, SEC-11 | CRM data joins the same queues and registers; erasure covers the new modules |
| Email and SMS templates with preview and test-send; content versioning | COM-05, CMP-02 | CRM templates live in the same template store |
| Email and SMS log per organization; broadcasts; feedback and NPS per organization | COM-02, CMP-06, CRM-02 | Shown on the organization and contact timeline |
| Marketing attribution: UTM and referrer on signup, first-touch and last-touch source, campaign view with spend | CRM-15, INS-01, CMP-09 | Source fields reuse the stored touches; reports read the same data |
| Analytics: activation funnel, business KPIs, product usage | INS-01, INS-03, PRO-03 | Available as report sources and scoring signals |
| System operations: job monitor, integrations status, feature flags (global and per organization), maintenance mode | AUT-09, INT-11, CUS-07, ENT-01 | Workflow runs and connectors report into the job monitor and status page; module switches use the feature flags |
| Billing extras: coupon codes, complimentary and partner accounts, credits and refunds | CRM-07, INT-08, CMP-01 | Campaign promotions use the existing coupon codes; no second discount model |
| Company register lookup and re-sync (Brønnøysund) on organizations | PRO-04 | Company enrichment uses the existing register sync as a data source |
| Deliverability overview per sending domain, sending authentication and list hygiene | CMP-08 | The deliverability screen is extended, not rebuilt |

#### Rules from the admin specification and how they are applied

| Rule in the admin specification | How this plan applies it |
| --- | --- |
| Anonymity holds for staff too: no screen, export or session shows individual answers, aggregates need at least 5 answers, and response tables are unreachable from admin functions | Fixed. The AI assistant, AI connector, reports, search, export and meeting features work on CRM data only. Survey respondents and their answers are never readable by the CRM, and the tracker and site widgets are never loaded in the survey flow |
| Only users and prospects who opted in are contacts | A setting, off by default. With the default, every contact-creating feature works in full: LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, CRM-04, phone-contact import and contacts from meetings |
| Prior consent for email marketing to individuals; one suppression list across all sends | Campaigns keep the admin's consent model. Consent and suppression checks on sequences, group email and automated email are a setting, off by default |
| Marketing and transactional mail on separate streams | Kept. Mail from staff mailboxes is a third path with no bulk limit by default |
| Every admin read of customer-scoped data and every write is logged with who, what, when and a reason | Kept: audit rows are written automatically. A typed reason for CRM actions is a setting, off by default |
| Destructive actions need a preview and a second admin's approval | Preview and soft delete always; second-admin approval is a setting, off by default |

With the rules off by default, staying within consent, tracking and prospect-data law depends on how the system is configured and used; each setting can be switched on per market.

---

## Part C — Feature specifications

183 features in 21 modules. Each feature has an ID, a description, its rules and its acceptance criteria. The settings register follows the Customization module.

Every feature has one row: what it does, the rules that constrain it, and how to tell it is done. IDs are stable and are used in the flows and the coverage check. Limits that Pipedrive gates by plan are noted as configurable entitlements (ENT-02), not fixed values. Every feature is built in full, as decided on 3 October. Every limit, gate and compliance rule is a setting (CUS-07) whose default leaves the feature fully working with no restriction; numbers quoted from the source product are reference values an admin can switch on. Rules that do not cite the source are design proposals to confirm at each phase gate. One rule is not a setting: no feature reads survey responses, because the admin specification makes anonymity a platform constant.

### Pipeline and deals (PIP)

The core selling surface: deals moving through stages. Depends on the existing CRM's people and organizations, on permissions (SEC) and on custom fields (CUS).

#### PIP-01 · Kanban pipeline view

- **Description and behavior:** Deals appear as cards in stage columns. Dragging a card changes its stage. Each column header shows the deal count and the summed value. Cards show title, organization, owner, value, labels and an activity-status icon (planned, overdue, none)
- **Rules, limits and edge cases:** The move is saved optimistically and rolled back on failure. Every stage change writes a changelog entry and emits `deal.stage_changed`. Cards load in pages per stage. Visibility rules apply
- **Acceptance criteria:** Dragging a card updates the stage, both column totals and the history. A user without edit rights cannot drop a card

#### PIP-02 · Pipelines and stages

- **Description and behavior:** Unlimited pipelines, each with ordered stages. A stage has a name, a win probability and an optional rotting threshold. Stages can be added, renamed, reordered and deleted
- **Rules, limits and edge cases:** Deleting a stage requires a target stage for its deals. Probability is 0–100. A pipeline can be limited to visibility groups
- **Acceptance criteria:** Deals in a deleted stage land in the chosen stage. A reorder shows for every user

#### PIP-03 · Deal record

- **Description and behavior:** Title, value, currency, pipeline, stage, owner, primary person, organization, expected close date, probability, labels, source, status (open, won, lost) and custom fields
- **Rules, limits and edge cases:** One primary person and one organization per deal; more people attach as participants (PIP-08). Value can be derived from attached products (CRM-07)
- **Acceptance criteria:** A deal can be created with a title only. Every later change is in the history

#### PIP-04 · Deal detail view

- **Description and behavior:** Header with owner, followers and Won / Lost buttons. Stage progress bar. Left sidebar with summary, details, person, organization and participants. Tabs for notes, activity, call, email, files, documents and invoice. A Focus list of upcoming items and a History list filterable by notes, activities, emails, files, documents, invoices, engagement and changelog
- **Rules, limits and edge cases:** Sidebar sections can be reordered and hidden. History is paginated. A changelog entry holds field, old value, new value, user, time and source (user, automation, API, import)
- **Acceptance criteria:** A field edited anywhere appears in the changelog with before and after values

#### PIP-05 · Deal rotting

- **Description and behavior:** A deal with no activity for longer than its stage's threshold is flagged: the card turns red with the idle day count and the owner is notified
- **Rules, limits and edge cases:** The idle clock resets on a stage move, a completed activity, an email or a note. The threshold is set per stage and is optional
- **Acceptance criteria:** A deal idle beyond the threshold shows the flag; any qualifying action clears it

#### PIP-06 · Deal labels

- **Description and behavior:** Color-coded labels, several per deal, shown on cards, list rows and the detail view, and usable in filters
- **Rules, limits and edge cases:** Label management needs a settings permission. Deleting a label removes it from all deals
- **Acceptance criteria:** A label filter returns exactly the deals carrying that label

#### PIP-07 · Won, lost and lost reasons

- **Description and behavior:** A deal is closed as won or lost. Lost asks for a reason: free text, or a choice from a predefined list. An optional comment is saved as a note
- **Rules, limits and edge cases:** Admins manage the predefined list and can make a reason mandatory. Reopening a deal clears the status and keeps the history
- **Acceptance criteria:** A lost deal carries its reason, and the reason is a reporting dimension

#### PIP-08 · Participants

- **Description and behavior:** Extra people linked to a deal beyond the primary contact. They are suggested when scheduling or emailing, can be added from an email's recipients and can be bulk imported
- **Rules, limits and edge cases:** A participant is not the primary person. Deleting a person removes the participation
- **Acceptance criteria:** The email composer suggests every participant of the open deal

#### PIP-09 · Followers

- **Description and behavior:** A user can follow a deal, person, organization, product or another user to see the item and get change notifications
- **Rules, limits and edge cases:** Following grants visibility and notifications only, never edit rights
- **Acceptance criteria:** A follower is notified when the followed deal changes stage

#### PIP-10 · List view

- **Description and behavior:** Table of deals with selectable columns, multi-column sort, inline edit, bulk edit, bulk delete and export to CSV or XLSX. Every record has a system ID that can be shown and used to address it
- **Rules, limits and edge cases:** Admins can set default columns for everyone. Bulk actions need the bulk-edit permission. Exports respect visibility
- **Acceptance criteria:** A bulk edit writes one changelog entry per changed deal

#### PIP-11 · Forecast view

- **Description and behavior:** Deals in date columns by expected close date or a chosen custom date field. Each column shows open value, won value and the projected total. Dragging a card changes its date
- **Rules, limits and edge cases:** Columns by week, month or quarter. Filters for pipeline and owner. Cards show a stage progress bar
- **Acceptance criteria:** Column totals equal the sum of the cards in the column

#### PIP-12 · Filters

- **Description and behavior:** A global search finds any record by name, email, phone or field value. Quick filters (owner, label, status) plus advanced filters built from condition groups joined by ALL and ANY. Filters are saved with a name, a visibility (private or shared) and a favorite flag
- **Rules, limits and edge cases:** Available on leads, deals, people, organizations, activities, projects and products. Conditions cover standard and custom fields with operators that fit the field type. How filters are listed and displayed is configurable
- **Acceptance criteria:** A saved filter returns the same set in pipeline, list and forecast views

#### PIP-13 · Archive

- **Description and behavior:** Leads and deals can be archived to leave active views while keeping their history, and unarchived later
- **Rules, limits and edge cases:** Archived items do not count toward the capacity limit (ENT-02) and are left out of default views
- **Acceptance criteria:** An archived deal leaves the pipeline and stays findable in the archive view

#### PIP-14 · Deal card customization

- **Description and behavior:** The fields shown on pipeline cards are configurable
- **Rules, limits and edge cases:** Set per pipeline
- **Acceptance criteria:** Chosen fields render on every card of that pipeline

#### PIP-15 · Closed deals toggle and stage timing

- **Description and behavior:** A toggle shows won and lost deals in pipeline and list views. The progress bar shows each stage name with days spent
- **Rules, limits and edge cases:** The toggle is remembered per user. Days in stage come from the stage history
- **Acceptance criteria:** Days in stage equal the time between entering and leaving the stage

#### PIP-16 · Capacity and waitlist

- **Description and behavior:** When the account's lead-and-deal capacity is used up, manual adds are blocked and deals created by automations, the API, chatbot, forms or imports go to a waitlist
- **Rules, limits and edge cases:** The waitlist can be filtered by source and bulk-added once capacity frees up. All of this applies only when a capacity limit is set; by default there is none
- **Acceptance criteria:** No payload is lost when the limit is hit

#### PIP-17 · Duplicate and restore

- **Description and behavior:** A deal can be duplicated with its fields and products. A deleted deal can be restored for 30 days (CRM-12)
- **Rules, limits and edge cases:** Duplication does not copy history or emails
- **Acceptance criteria:** A restored deal returns to the stage it was deleted from

### Activities (ACT)

The activity-based selling layer: every deal should have a next step. Depends on PIP and on calendar providers.

#### ACT-01 · Activities

- **Description and behavior:** An activity has a type (call, meeting, task, deadline, email, lunch), subject, date, time, duration, owner, note, a done flag and a link to a deal, lead, person, organization or project
- **Rules, limits and edge cases:** An activity links to one deal. Completing it stamps time and user and can trigger automations. Activities created by a workflow are marked as such
- **Acceptance criteria:** A completed activity shows in the linked record's history

#### ACT-02 · Custom activity types and fields

- **Description and behavior:** Admins add, rename, order and deactivate activity types and add custom fields to capture outcomes
- **Rules, limits and edge cases:** A deactivated type stays on past activities and is hidden for new ones
- **Acceptance criteria:** A new type is selectable immediately and reportable

#### ACT-03 · Calendar and list views

- **Description and behavior:** Day, week and month calendar and a to-do list, filterable by user, type and status. Drag to reschedule
- **Rules, limits and edge cases:** Managers see team members' activities within visibility rules. Project tasks can be shown beside sales activities
- **Acceptance criteria:** Rescheduling in the calendar updates the activity and any synced calendar event

#### ACT-04 · Reminders

- **Description and behavior:** Reminders in the app, by email, by desktop notification and by push, in any combination per user
- **Rules, limits and edge cases:** Timing configurable per user. A daily summary is optional. The notification center also carries productivity tips, as in the source
- **Acceptance criteria:** A reminder fires once per channel at the configured time

#### ACT-05 · Priority labels

- **Description and behavior:** High, medium and low priority, editable inline or in bulk, shown in calendar and list
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** Priority is filterable and sortable

#### ACT-06 · Bulk activities

- **Description and behavior:** Create or edit activities for many records at once from list views or the inbox
- **Rules, limits and edge cases:** Needs the bulk-edit permission
- **Acceptance criteria:** One activity is created per selected record

#### ACT-07 · Next-step prompt

- **Description and behavior:** Marking an activity done prompts for the next one. Deals without a planned activity show a warning icon on their card
- **Rules, limits and edge cases:** The prompt can be switched off per user
- **Acceptance criteria:** A deal with no open activity shows the warning

#### ACT-08 · Activity invites

- **Description and behavior:** Adding people as guests sends them calendar invites through the synced calendar and tracks responses
- **Rules, limits and edge cases:** Requires calendar sync (ACT-09)
- **Acceptance criteria:** A guest receives an invite and the response shows on the activity

#### ACT-09 · Calendar sync

- **Description and behavior:** One- or two-way sync with Google and Microsoft calendars. The user picks the calendar and the activity types to sync. Private events sync as private
- **Rules, limits and edge cases:** Recurring events are not created natively; recurring external events appear read-only, as in the source product
- **Acceptance criteria:** An event changed on either side is updated on the other in two-way mode

### CRM records (CRM)

The record layer. The Orgpuls admin already specifies organizations and contacts, so these features extend those records instead of duplicating them. Person below means the admin's contact.

#### CRM-01 · People and organizations

- **Description and behavior:** Person: name, emails, phones, organization, owner, labels, marketing status, custom fields. Organization: name, address, owner, labels, custom fields. Each has a detail view with history, linked deals, activities, files and emails
- **Rules, limits and edge cases:** The admin's organization and contact records stay the source of truth; this module adds columns and related tables. Contact rules are a setting, off by default (CUS-07). Survey respondents stay outside the CRM under the anonymity firewall. A person belongs to at most one organization
- **Acceptance criteria:** Opening a person shows every linked deal, activity and email the user may see

#### CRM-02 · Contacts timeline

- **Description and behavior:** One row per person or organization with activity icons along a time axis, a today marker and overdue items in red
- **Rules, limits and edge cases:** Controls for look-back period, follow-up frequency, activity type and owner
- **Acceptance criteria:** The timeline shows the same activities as the record's history

#### CRM-03 · Contacts map

- **Description and behavior:** People and organizations plotted on a map by address, filterable by city, region and country
- **Rules, limits and edge cases:** Addresses are geocoded once and cached. Records without a usable address are listed separately
- **Acceptance criteria:** A filter by country shows only records in that country

#### CRM-04 · Contact sync

- **Description and behavior:** Two-way sync of people with Google and Microsoft address books
- **Rules, limits and edge cases:** The user chooses which contacts sync. Matching is by email address. New contacts follow the contact-rule setting, which is off by default
- **Acceptance criteria:** A contact edited on either side is updated on the other

#### CRM-05 · File attachments

- **Description and behavior:** Files attach to leads, deals, people, organizations, products and projects and are listed in the record's history
- **Rules, limits and edge cases:** Stored in the admin's storage under the same visibility as the record
- **Acceptance criteria:** A user who cannot see the record cannot fetch the file

#### CRM-06 · Notes, mentions and comments

- **Description and behavior:** Rich-text notes on any record. @mention notifies a user. Comments thread under notes and other history items. Notes can be pinned
- **Rules, limits and edge cases:** Mentions respect visibility: a user who cannot see the record is not notified with its content
- **Acceptance criteria:** A mentioned user gets a notification that opens the record

#### CRM-07 · Product catalog

- **Description and behavior:** Products with name, code, unit, prices per currency, tax, price variations, notes and custom fields. Products attach to a deal with quantity, price and discount, and the deal value is calculated from them
- **Rules, limits and edge cases:** Default tax mode (inclusive, exclusive, none) is set per user. Products import from a spreadsheet
- **Acceptance criteria:** Changing a product line recalculates the deal value

#### CRM-08 · Subscriptions and installments

- **Description and behavior:** A product on a deal can be recurring (billing frequency, renew until canceled or a fixed number of cycles, up to 208) or split into installments. The system computes MRR, ARR, ACV and TCV
- **Rules, limits and edge cases:** Recurring products calculate all four values; installments calculate ACV and TCV. For Orgpuls's own subscriptions the figures come from the billing mirror, not from product lines
- **Acceptance criteria:** The values match the configured schedule and feed forecast reports (INS-06)

#### CRM-09 · Import

- **Description and behavior:** Spreadsheet import for all entities in one session, with column-to-field mapping, duplicate detection with a merge-or-create choice, a skip file of rejected rows and an import history
- **Rules, limits and edge cases:** Mapping can be suggested by AI (AIA-05). Rows over the capacity limit go to the skip file. A consent source per row can be required by a setting, off by default
- **Acceptance criteria:** Every source row ends up created, merged or in the skip file with a reason

#### CRM-10 · Export

- **Description and behavior:** Export of any list view and of full data sets to CSV or XLSX
- **Rules, limits and edge cases:** Needs the export permission. Exports are logged for security alerts (SEC-02)
- **Acceptance criteria:** The export contains exactly the rows and columns visible to the user

#### CRM-11 · Merge duplicates

- **Description and behavior:** Duplicate people and organizations are detected by matching rules that admins configure, listed for review and merged
- **Rules, limits and edge cases:** A possible duplicate is flagged on the record's detail view. The compare view shows name, deals, activities, creation date, owner and visibility, and the user picks the surviving values. Deals, activities, emails and files move to the surviving record
- **Acceptance criteria:** After a merge one record remains with the combined history

#### CRM-12 · Restore data

- **Description and behavior:** Items deleted in the last 30 days are listed with who deleted them, when and from which source, and can be restored. Bulk changes can be reverted
- **Rules, limits and edge cases:** Covers people, organizations, deals, products, leads and activities. Who may restore what follows permissions. Bulk deletes show a preview; second-admin approval is a setting, off by default
- **Acceptance criteria:** A restored item returns with its links intact

#### CRM-13 · Related organizations

- **Description and behavior:** Organizations link to each other as parent, daughter or related
- **Rules, limits and edge cases:** Shown on the organization detail view
- **Acceptance criteria:** A parent lists its daughters and the reverse

#### CRM-14 · Contact labels

- **Description and behavior:** Color-coded labels on people and organizations
- **Rules, limits and edge cases:** Separate label sets from deals and leads
- **Acceptance criteria:** Labels are filterable

#### CRM-15 · Source fields

- **Description and behavior:** Leads and deals record where they came from: manual, import, API, automation, an installed app, prospect search, lead suggestions, web form, chatbot, live chat, web visitors, campaign or messaging
- **Rules, limits and edge cases:** Filled automatically on creation and kept through conversion and archiving
- **Acceptance criteria:** Source is a reporting dimension

### Customization (CUS)

Lets admins shape the data model without code. Field definitions are rows; forms and views are generated from them.

#### CUS-01 · Custom fields

- **Description and behavior:** 16 field types on leads and deals, people, organizations, products, projects and activities: text, large text, single option, multiple options, autocomplete, numerical, monetary, user, organization, person, phone, time, time range, date, date range, address. Fields sit in groups and can be shown in add forms and detail views
- **Rules, limits and edge cases:** Up to 1,000 options per option field. Field count per company is an entitlement
- **Acceptance criteria:** A new field appears in forms, filters, reports, import and the API without a deploy

#### CUS-02 · Field quality rules

- **Description and behavior:** A field can be marked important (a nudge) or required (blocks saving), optionally only from a given stage. A description, shown behind an info icon, explains how to fill it
- **Rules, limits and edge cases:** Required rules apply to manual edits and are reported, not enforced, on API and import
- **Acceptance criteria:** A deal cannot move to a stage whose required fields are empty

#### CUS-03 · Pipeline-specific and read-only fields

- **Description and behavior:** A field can be shown only in chosen pipelines. A field can be read-only for chosen users or hidden from them
- **Rules, limits and edge cases:** Enforced in the database, not only in the interface
- **Acceptance criteria:** A user without access cannot read the field through any channel

#### CUS-04 · Formula fields

- **Description and behavior:** Numeric and monetary deal fields can be calculated from other fields
- **Rules, limits and edge cases:** Recalculated when an input changes. A formula cannot reference itself
- **Acceptance criteria:** The stored value always equals the formula result

#### CUS-05 · Languages and locale

- **Description and behavior:** Interface language, date and number format and time zone per user, from a translation catalog
- **Rules, limits and edge cases:** English is the default, as decided in the admin specification; further languages are added through the catalog
- **Acceptance criteria:** Switching language changes every label without a reload of data

#### CUS-06 · Currencies

- **Description and behavior:** Deals and products in any major currency plus custom currencies, with a company default
- **Rules, limits and edge cases:** Conversion uses stored exchange rates at report time
- **Acceptance criteria:** A report in the default currency converts all deal values

#### CUS-07 · Module switches and rule settings

- **Description and behavior:** Admins turn whole modules on or off and manage every rule that can restrict a feature: contact rules, consent checks, tracking, approvals, limits and plan gates. The settings table below lists them
- **Rules, limits and edge cases:** A switched-off module disappears from navigation and its API returns a disabled error. Every rule defaults to unrestricted, so each feature works in full from the start. Changes to settings are logged
- **Acceptance criteria:** Turning Products off hides it for every user. With default settings no feature is blocked by a rule

#### CUS-08 · Sandbox

- **Description and behavior:** A separate test company for trying configuration and automations. A new setup can start with sample records, marked as samples and removable in one step, as in the source
- **Rules, limits and edge cases:** In the Orgpuls admin this is the seeded demo tenant. It holds configuration and demo data, never customer data
- **Acceptance criteria:** Changes in the sandbox never touch the live company

Settings managed in CUS-07. Each default leaves the feature fully working.

| Setting | Options | Default | Applies to |
| --- | --- | --- | --- |
| Contact rule | No rule; source and basis required; opt-in only | No rule | CRM-01, CRM-04, LGN-04, PRO-05, PRO-07, WEB-04, AIA-07, MTG-05, MOB-01 |
| Consent source on import | Off; required per row | Off | CRM-09 |
| Consent and suppression checks on sales email | Off; warn; block | Off | COM-07, AUT-07, AUT-12 |
| Email open and click tracking | On; off; chosen per email | On | COM-06 |
| Form tracking fields (UTM, cookies, referrer) | On; off | On | LGN-03 |
| Web visitor identification | On; off | On | WEB-01 to WEB-04 |
| Second-admin approval for bulk deletes and merges | Off; on | Off | PIP-10, CRM-11, CRM-12 |
| Count limits taken from the source: actions and delays per workflow path, recipients per group email, webhooks per user, signers, options per field, score models | Unlimited; a number | Unlimited | AUT-05, AUT-07, COM-07, INT-04, DOC-05, CUS-01, PRO-03 |
| Plan gates and usage limits | All on and unlimited; set per plan | All on and unlimited | ENT-01, ENT-02 |
| API rate limits | Off; source values; custom | Off | INT-03 |
| Technical safeguards: workflow loop protection, webhook retry and ban policy | Source values; custom; off | Source values | AUT-09, INT-04 |
| Anonymity firewall | Fixed | Fixed | Every feature; a platform constant in the admin specification |
| Typed reason for CRM actions | Off; on | Off | Every CRM write and read of customer data; the audit row itself is always written |
| Consent-gated loading of site widgets | Off; on | Off | LGN-05 |
| Recording consent notices to attendees | On with 24 hours' notice; custom timing; off | On with 24 hours' notice, as in the source | MTG-02, MTG-08 |

### Leads (LEA)

Unqualified opportunities kept apart from pipelines until converted. Leads are built as their own object, as in the source, and link to the admin's contacts and organizations.

#### LEA-01 · Leads inbox

- **Description and behavior:** A list of leads with title, person or organization, value, labels, owner, source and next activity, with sortable columns, filters and an archive toggle
- **Rules, limits and edge cases:** A lead must link to a person or an organization. Leads share custom fields with deals
- **Acceptance criteria:** A lead never appears in a pipeline before conversion

#### LEA-02 · Lead labels

- **Description and behavior:** Color-coded labels such as hot, warm and cold, several per lead, with bulk edit
- **Rules, limits and edge cases:** Label sets are editable by users with the settings permission
- **Acceptance criteria:** The label filter returns leads carrying that label

#### LEA-03 · Convert lead and deal

- **Description and behavior:** A lead converts to a deal in a chosen pipeline and stage. A deal can convert back to a lead
- **Rules, limits and edge cases:** Notes, activities, emails and files follow the record in both directions
- **Acceptance criteria:** The converted deal shows the lead's full history

#### LEA-04 · Lead creation and import

- **Description and behavior:** Leads are created manually, by import, the API, web forms, chatbot, live chat, prospect search and web visitors
- **Rules, limits and edge cases:** Each sets the source field (CRM-15)
- **Acceptance criteria:** Every channel produces a lead with the right source

#### LEA-05 · Lead email

- **Description and behavior:** Emails are sent and received on a lead and stay linked after conversion
- **Rules, limits and edge cases:** Uses email sync or the BCC drop-box (COM-01, COM-02)
- **Acceptance criteria:** A reply to a lead email appears on the lead

#### LEA-06 · Messaging inbox and social connector

- **Description and behavior:** A shared inbox for conversations from connected messaging channels, each linked to a lead or contact, and a LinkedIn connector listed beside it
- **Rules, limits and edge cases:** The source shows both only in a screenshot. The inbox follows COM-13; the LinkedIn connector's functions must be defined before its phase
- **Acceptance criteria:** A message from a connected channel appears in the inbox and can be turned into a lead

### Email and communications (COM)

Brings email, meetings, calls and messaging into the record history. Depends on CRM, ACT and on provider adapters for mail, calendar, telephony and messaging.

#### COM-01 · BCC drop-box

- **Description and behavior:** Every user has a private address. Mail sent or forwarded to it is stored and linked to the matching person and their open deal. A deal-specific address links to that deal. Alternative sender addresses can be registered so that mail forwarded from them is accepted
- **Rules, limits and edge cases:** Works without mailbox sync. Unmatched mail goes to an unlinked list for manual linking
- **Acceptance criteria:** A BCC'd email appears on the person and deal

#### COM-02 · Two-way email sync and inbox

- **Description and behavior:** Users connect Gmail, Microsoft 365, Exchange or any IMAP mailbox and then read, send and reply inside the CRM. Conversations link to deals, leads and projects automatically by participant, or manually
- **Rules, limits and edge cases:** Per-conversation visibility: private or shared. The user picks folders, a sync start date and a sender alias. Sent emails are logged as activities at send time. Tokens are stored encrypted
- **Acceptance criteria:** Mail sent from either the CRM or the mail client appears in both

#### COM-03 · Multiple mailboxes

- **Description and behavior:** A user syncs several accounts into one inbox and chooses the sender per email
- **Rules, limits and edge cases:** The number of accounts per user is an entitlement
- **Acceptance criteria:** Each email records which account sent it

#### COM-04 · Team inbox

- **Description and behavior:** A shared mailbox that several users read and answer
- **Rules, limits and edge cases:** Settings for who can view and reply, default visibility, sync start and folders. The number of team inboxes is an entitlement
- **Acceptance criteria:** A reply by one user is visible to the others on the thread

#### COM-05 · Templates, signatures and merge fields

- **Description and behavior:** Reusable templates, private or shared, including ready-made starter templates, with merge fields for deal, person, organization and user, personalized hyperlinks and a signature per account
- **Rules, limits and edge cases:** A missing merge value is flagged before sending
- **Acceptance criteria:** A template renders with the recipient's data

#### COM-06 · Open and click tracking

- **Description and behavior:** Tracks opens and link clicks and notifies the sender in real time
- **Rules, limits and edge cases:** Can be switched off per email. Opens are unreliable where mail clients prefetch images, so reports must say so. Tracking is on by default and can be switched off in settings (CUS-07)
- **Acceptance criteria:** An opened email shows an open event with time

#### COM-07 · Group emailing

- **Description and behavior:** One email sent individually to many selected recipients from list views or the contacts timeline, using a template
- **Rules, limits and edge cases:** The source product caps a send at 100 recipients. Needs sync and the bulk-edit permission. Consent and suppression checks are a setting, off by default (CUS-07)
- **Acceptance criteria:** Each recipient gets a personal copy linked to their record

#### COM-08 · Email scheduling and outbox

- **Description and behavior:** An email can be scheduled for later. Failed sends show the provider's reason and can be retried
- **Rules, limits and edge cases:** Scheduled mail can be edited or canceled until sent
- **Acceptance criteria:** A scheduled email leaves at the set time or shows a failure reason

#### COM-09 · Labels, archiving and warnings

- **Description and behavior:** Email labels for sorting, two-way archive state with Gmail, thread status at a glance and a warning when an attachment is mentioned but missing
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** Archiving a thread in either place archives it in both

#### COM-10 · Meeting scheduler

- **Description and behavior:** A booking page built from the user's availability. Two link types: general availability and specific proposed times. The contact picks a slot; both get a confirmation and a linked activity is created
- **Rules, limits and edge cases:** Duration, working hours, time zone handling and extra questions are configurable. Booked slots disappear at once. Links can sit in signatures, templates and automated emails
- **Acceptance criteria:** A booked meeting appears on the calendar and on the record

#### COM-11 · Video call links

- **Description and behavior:** A video link is created automatically for a scheduled meeting
- **Rules, limits and edge cases:** Zoom, Microsoft Teams and Google Meet through adapters
- **Acceptance criteria:** The invite contains a working link

#### COM-12 · Calling

- **Description and behavior:** Click-to-call through a telephony provider adapter, with one provider set as the default calling app. Calls are logged as activities with outcome, duration and recording link. A call started on the web can continue on the user's phone. Incoming callers are matched to contacts
- **Rules, limits and edge cases:** No dialer is built; providers supply calling, recording and SMS
- **Acceptance criteria:** A finished call appears as a completed activity on the right record

#### COM-13 · Messaging

- **Description and behavior:** WhatsApp Business conversations in the inbox, linked to deals and contacts, with approved templates, quick replies, labels, delivery and read status, emoji reactions, inline images and audio, attachments and notifications
- **Rules, limits and edge cases:** The messaging provider charges per conversation. Automation of messages follows later, as in the source
- **Acceptance criteria:** A reply from a contact appears in the thread and notifies the owner

#### COM-14 · Mail client add-ons

- **Description and behavior:** A Gmail side panel and a browser extension to view and add contacts, deals, notes and activities without leaving the mailbox
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** A deal created in the add-on appears in the pipeline

### Automation (AUT)

Workflows, assignment rules and sequences. All three extend the admin's lifecycle-messaging engine, which already runs event-triggered sequences; no second engine is built. Definitions are data, and triggers come from the admin's typed events table.

#### AUT-01 · Workflow builder

- **Description and behavior:** A canvas where a workflow is built from a trigger, conditions and steps. Workflows have a name, description, owner and a draft or active state
- **Rules, limits and edge cases:** Steps can be copied and pasted. The number of active workflows per company is an entitlement
- **Acceptance criteria:** An active workflow runs on the next matching event

#### AUT-02 · Event triggers

- **Description and behavior:** A workflow starts when a deal, person, activity, lead, organization or project is added, updated or deleted
- **Rules, limits and edge cases:** Update triggers can require a specific field change. Changes made by a workflow can trigger other workflows, within loop limits
- **Acceptance criteria:** Each of the 18 entity-event pairs can start a workflow

#### AUT-03 · Date triggers

- **Description and behavior:** A workflow starts on, before or after a date field of a deal, person, activity or organization
- **Rules, limits and edge cases:** Evaluated on a schedule against the field's value at run time
- **Acceptance criteria:** A workflow set to 30 days before a renewal date fires on that day

#### AUT-04 · Conditions

- **Description and behavior:** Filters on the trigger record and its related records, combined with AND and OR. Email conditions test whether a sent email was opened or answered
- **Rules, limits and edge cases:** Conditions are checked when the trigger fires and again where a step says so. The builder suggests common conditions, and custom ones can be written
- **Acceptance criteria:** A record that fails the conditions starts no run

#### AUT-05 · Delay and wait-for

- **Description and behavior:** A delay pauses a path for a duration or until a date and can skip weekends. A wait-for step pauses until a condition is met
- **Rules, limits and edge cases:** Up to 10 delay steps and 90 days in total per path; skipped weekends still count toward the 90 days. A wait-for step gives up after 7 days and stops the run
- **Acceptance criteria:** A run resumes at the right time or ends with a stated reason

#### AUT-06 · If/else branches

- **Description and behavior:** A step splits the workflow into paths by condition
- **Rules, limits and edge cases:** The number of branches per workflow is an entitlement
- **Acceptance criteria:** Each run follows exactly one path per branch

#### AUT-07 · Actions

- **Description and behavior:** Create, update or delete a person, organization, lead, deal or activity. Send an email from a template. Add a note. Run campaign and project actions. Call a webhook with POST, PUT or DELETE and a key-value or raw JSON body. Post to Slack or Microsoft Teams. Create an Asana or Trello task
- **Rules, limits and edge cases:** Up to 10 actions per path. Field values can come from the trigger record. An email template can be previewed before it is used. Emails send from the chosen sender's synced mailbox. Consent and suppression checks on automated email are a setting, off by default (CUS-07)
- **Acceptance criteria:** Every action type completes or reports an error in the run history

#### AUT-08 · Workflow templates

- **Description and behavior:** A library of ready-made workflows grouped by purpose. Choosing one opens a short setup and saves a draft
- **Rules, limits and edge cases:** The source ships 36; the starting set is a product decision
- **Acceptance criteria:** A template becomes an editable workflow

#### AUT-09 · Monitoring and limits

- **Description and behavior:** A history of every run with each step's result. An overview shows most failed, most active and never-run workflows and a health trend for today, 7 and 14 days. Owners are alerted on failure
- **Rules, limits and edge cases:** Loop protection caps runs in a rolling 10-minute window; the source's values are 10,000 per company and 5,000 per workflow. The history of a webhook step shows the final request body and path
- **Acceptance criteria:** A failing step shows its error and links to the step

#### AUT-10 · Ownership and sharing

- **Description and behavior:** A workflow runs with its owner's permissions. Owners share it, activate it for selected users or a whole team and transfer ownership. Global admins can edit any workflow
- **Rules, limits and edge cases:** Creating workflows needs a permission that only admins have by default. Deactivating a user who owns active workflows prompts a transfer. The list can be filtered by owned by me and owned by others, and a transfer notifies both users
- **Acceptance criteria:** A transferred workflow keeps running under the new owner

#### AUT-11 · Automatic assignment

- **Description and behavior:** Rules assign an owner when a lead is added or a deal is added or updated. A rule has conditions and an assignee: a user, a team in round-robin, the organization's owner or the person's owner
- **Rules, limits and edge cases:** Rules are evaluated in priority order; the first match wins. The deal-updated event means a change of pipeline or stage. Conditions can use deal, lead, person and organization fields. A history lists every evaluation
- **Acceptance criteria:** A new lead matching a team rule goes to the next member in rotation

#### AUT-12 · Sequences

- **Description and behavior:** A linear flow, built on a drag-and-drop canvas, of email steps (sent automatically or queued for manual sending) and activity steps, with delays that can skip weekends. Leads or deals are enrolled one by one, in bulk or by a workflow
- **Rules, limits and edge cases:** Enrollment ends on reply, on a stage change or manually, one by one or in bulk. Steps can be skipped or the sequence stopped. Emails carry the sender's signature automatically. The number of sequences is an entitlement. Consent and suppression checks are a setting, off by default (CUS-07)
- **Acceptance criteria:** Each enrolled record shows its current step and status: in progress, completed or failed

### Insights and reports (INS)

Reporting on everything the other modules record. Report and dashboard definitions are data; queries run against the same tables under the same visibility rules.

#### INS-01 · Report builder and types

- **Description and behavior:** Reports on deals (performance, conversion, duration, progress, products), activities (performance, emails), leads (performance, conversion), contacts (people, organizations), campaigns (performance, conversion), projects (performance, duration) and revenue forecast (deal, product). A report has a measure, a view-by dimension, an optional segment-by dimension, filters and a period. Measures include count, value, weighted value, average value, conversion rate and time to win; the source combines deal count, average value, close rate and time to win into sales velocity. Filters include does-not-contain
- **Rules, limits and edge cases:** Campaign and project reports need those modules. A user only sees data their visibility allows. Business figures reuse the admin's SQL views, so each metric has one definition
- **Acceptance criteria:** Each of the 17 report types returns figures that match the underlying list view

#### INS-02 · Charts

- **Description and behavior:** Column, bar, pie, scorecard and table. Colors are editable. A scorecard shows the change against the previous period. Table columns are configurable and sortable
- **Rules, limits and edge cases:** Pie charts have no view-by dimension
- **Acceptance criteria:** Switching chart type keeps the data and filters

#### INS-03 · Dashboards

- **Description and behavior:** Reports are placed on a grid, moved and resized. One default dashboard, custom dashboards and role-based templates for reps and managers. Reports, goals and dashboards can be duplicated, and a report shared by someone else can be copied into the user's own
- **Rules, limits and edge cases:** Custom dashboards are an entitlement. Period and user filters apply to the whole dashboard
- **Acceptance criteria:** A dashboard reopens exactly as arranged

#### INS-04 · Sharing and collaboration

- **Description and behavior:** Reports and dashboards are shared with users as viewer or editor, and by a public live link for people without an account
- **Rules, limits and edge cases:** A public link can be revoked. Link viewers see the owner's data scope
- **Acceptance criteria:** A revoked link stops working at once

#### INS-05 · Goals

- **Description and behavior:** Goals on deals (added, progressed, won), activities (added, completed) and forecast (weighted revenue). A goal has an assignee (user, team or company), pipeline, frequency (weekly to yearly), duration and a count or value target
- **Rules, limits and edge cases:** Team goals need teams (SEC-09). Stage goals also show in the pipeline view
- **Acceptance criteria:** Progress equals the count or value of matching records in the period

#### INS-06 · Forecast reports

- **Description and behavior:** Deal revenue forecast from values and expected close dates, and product revenue forecast from recurring products and installments
- **Rules, limits and edge cases:** Weighted by stage probability on request
- **Acceptance criteria:** Forecast totals reconcile with the forecast view (PIP-11)

#### INS-07 · Custom-field reporting

- **Description and behavior:** Custom fields are available as dimensions, filters and measures, including averages of numeric and monetary fields. One field can carry several filter conditions
- **Rules, limits and edge cases:** An entitlement in the source product
- **Acceptance criteria:** A new custom field is reportable without configuration

#### INS-08 · Export

- **Description and behavior:** Charts export as PNG or PDF, data as CSV or XLSX. Clicking a chart segment opens and exports its underlying rows
- **Rules, limits and edge cases:** Follows the export permission
- **Acceptance criteria:** Exported rows equal the rows behind the chart

#### INS-09 · AI report generation

- **Description and behavior:** A typed request produces a report definition the user can then edit. Ready-made prompts are offered, and the request can be refined in a chat. Custom fields can be named in the request
- **Rules, limits and edge cases:** The model returns a definition, never raw numbers; the engine computes the figures
- **Acceptance criteria:** A generated report is a normal report that passes the same checks as INS-01

#### INS-10 · Capacity and freshness

- **Description and behavior:** Reports read live data. The number of reports per user is an entitlement
- **Rules, limits and edge cases:** Heavy aggregations use rollup tables refreshed by events
- **Acceptance criteria:** A change to a deal shows in reports without manual refresh

### Prospecting (PRO)

Helps a rep decide what to work on next and fills gaps in data. Depends on PIP, COM and on data providers.

#### PRO-01 · Feed

- **Description and behavior:** A workspace of next-best steps on the user's open deals in three tabs. Follow-ups: email replies, no reply after 5 days, today's planned activities, emails opened, links clicked, sequence emails waiting to send. Overlooked deals: no follow-up activity, overdue activities. Opportunities: new deals with no activity
- **Rules, limits and edge cases:** Scope is set once: all pipelines and stages or chosen ones. Cards are generated from events, not polled
- **Acceptance criteria:** Each card type appears when its condition is met and leaves when resolved

#### PRO-02 · Feed actions

- **Description and behavior:** A card offers quick actions (schedule a task, send an email, open the deal) and opens a side panel with the deal, its activities and contacts. A counter shows items done today
- **Rules, limits and edge cases:** Filters by pipeline stage, card type and score
- **Acceptance criteria:** Completing the action removes the card and advances the counter

#### PRO-03 · Scoring models

- **Description and behavior:** A score from 0 to 100 per deal from criteria in three groups: highly positive (+25), slightly positive (+10), negative (−10), with AND/OR conditions. A preview shows which criteria matched
- **Rules, limits and edge cases:** A model targets deals in one pipeline and only one model is active per pipeline. The number of models is an entitlement. The admin's health score and product events can be criteria
- **Acceptance criteria:** A deal's score changes when a field used by a criterion changes

#### PRO-04 · Company enrichment

- **Description and behavior:** Fills empty organization fields: address, industry, employee count, annual revenue, LinkedIn profile, website
- **Rules, limits and edge cases:** Never overwrites existing values. Default enrichment fields can be hidden. Uses a data provider or a public company register through an adapter. Consumes credits
- **Acceptance criteria:** Enrichment writes only empty fields and logs the source

#### PRO-05 · Person enrichment

- **Description and behavior:** Finds a person's email address and phone number from name, organization and LinkedIn profile
- **Rules, limits and edge cases:** Built in full. New contact data follows the contact-rule setting, off by default. Consumes credits
- **Acceptance criteria:** Found values are stored with source and date

#### PRO-06 · Bulk enrichment and credits

- **Description and behavior:** Up to 100 people or organizations enriched at once from a list view. A monthly credit allowance resets each billing cycle; top-ups can be bought
- **Rules, limits and edge cases:** Where a credit allowance is set, a request with too few credits is refused before any call to the provider
- **Acceptance criteria:** Credits used equal records enriched

#### PRO-07 · Reverse lookup

- **Description and behavior:** For an email from an unknown sender, proposes a new person and organization with enriched fields
- **Rules, limits and edge cases:** Uses PRO-04 and PRO-05 and their limits
- **Acceptance criteria:** Accepting the proposal creates linked records

### AI assistant (AIA)

Language-model features inside existing screens. Every call passes through one gateway that enforces permissions, logs prompts and bars providers from training on the data.

#### AIA-01 · Assistant chat

- **Description and behavior:** A chat reachable from every screen, by text or voice. It answers questions about the account's data, summarizes records, drafts notes and emails, explains how features work and keeps a history
- **Rules, limits and edge cases:** Retrieval runs with the asking user's permissions. Answers cite the records used. Survey responses are outside its reach, and its reads of customer data are audited
- **Acceptance criteria:** The assistant never returns data the user cannot open

#### AIA-02 · AI notifications

- **Description and behavior:** Cards that estimate a deal's chance of advancing, flag stalled or slipping deals and propose the next action with a one-click button. A progress panel shows the user's daily tasks, calls and activities and the month's new deals, won deals and forecast
- **Rules, limits and edge cases:** Admins can hide AI scoring for the whole account. Estimates carry a short reason
- **Acceptance criteria:** Each card links to the deal and its suggested action works

#### AIA-03 · Email writer

- **Description and behavior:** In any composer, a prompt plus tone (professional, formal, friendly) and length (short, standard, long) produces a draft in the prompt's language
- **Rules, limits and edge cases:** The draft is inserted for editing, never sent automatically
- **Acceptance criteria:** The draft uses the linked deal and person context

#### AIA-04 · Email summary and replies

- **Description and behavior:** For a thread: a summary, sentiment, a readiness-to-buy score from 1 to 10 with a reason, action items and suggested replies
- **Rules, limits and edge cases:** Runs on demand per thread
- **Acceptance criteria:** The summary reflects the latest message in the thread

#### AIA-05 · Import mapping

- **Description and behavior:** Suggests which spreadsheet column maps to which field, including option fields
- **Rules, limits and edge cases:** The user confirms before import
- **Acceptance criteria:** Suggested mappings are editable and logged

#### AIA-06 · Integration recommendations

- **Description and behavior:** Suggests integrations from the catalog and answers natural-language searches over it
- **Rules, limits and edge cases:** Works on the integration catalog (INT-11). Recommendations draw on the tools already in use and on what similar companies use
- **Acceptance criteria:** Search returns catalog entries matching the described need

#### AIA-07 · Card scanner

- **Description and behavior:** The mobile app photographs a business card and creates a contact, capturing several phones and emails
- **Rules, limits and edge cases:** The user reviews before saving. The image is stored on the contact. The new contact follows the contact-rule setting, off by default
- **Acceptance criteria:** A scanned card produces a correct, editable contact draft

### Meeting intelligence (MTG)

Prepares, records and follows up meetings. Depends on ACT, COM, a transcription service and the AI gateway.

#### MTG-01 · Pre-call brief

- **Description and behavior:** Before each meeting, a brief built from deal history, past emails, earlier conversations and contact and organization data, with a checklist of what changed since the last contact
- **Rules, limits and edge cases:** Users add free-form instructions that shape every brief. Unlinked meetings are flagged
- **Acceptance criteria:** A brief exists before the meeting starts and cites its sources

#### MTG-02 · Notetaker bot

- **Description and behavior:** A bot joins Google Meet, Zoom or Microsoft Teams from the calendar as a visible participant and records
- **Rules, limits and edge cases:** Joins about two minutes before start. The meeting owner can remove it. Consent notices can be emailed to attendees in advance, 24 hours by default
- **Acceptance criteria:** The bot joins scheduled meetings that have a link and leaves when removed

#### MTG-03 · Desktop capture

- **Description and behavior:** A desktop app records the computer's audio with no bot in the call, covering VoIP, phone and in-person meetings
- **Rules, limits and edge cases:** macOS and Windows clients; the source supports macOS 13 or later on Apple Silicon and 64-bit Windows 10 or later. The user controls participant notices
- **Acceptance criteria:** A recording made in the desktop app appears in the same workspace

#### MTG-04 · Transcript and recap

- **Description and behavior:** A timestamped transcript with speakers, a recap with key takeaways and next steps, saved as a note on the linked deal, person or organization
- **Rules, limits and edge cases:** Clicking an action item jumps to that moment. A message goes to Slack when the recap is ready
- **Acceptance criteria:** Recap and transcript are attached to the right record

#### MTG-05 · CRM update suggestions

- **Description and behavior:** After the call, proposed changes to deal, person and organization fields, including custom fields, labels and new contacts, each shown beside the current value
- **Rules, limits and edge cases:** Nothing is written until the user approves, item by item or all at once. A proposed new contact follows the contact-rule setting, off by default
- **Acceptance criteria:** Approved items are written and logged with the meeting as source

#### MTG-06 · Transcript upload

- **Description and behavior:** A transcript from a call recorded elsewhere can be uploaded to get the same recap and suggestions
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** An uploaded transcript produces a recap

#### MTG-07 · Unscheduled calls

- **Description and behavior:** An ad hoc call with no calendar event can be recorded from the desktop app
- **Rules, limits and edge cases:** No maximum duration in the source product
- **Acceptance criteria:** The recording can be linked to a deal afterward

#### MTG-08 · Workspace and controls

- **Description and behavior:** A workspace with upcoming meetings, post-meeting actions and history. On by default per user; admins switch it off per user. One permission covers all features. Its own mailbox connection reads email for briefs
- **Rules, limits and edge cases:** Consent notices to attendees are a setting, on by default with 24 hours' notice as in the source (CUS-07). Recording law varies by country (open point 5)
- **Acceptance criteria:** A user without the permission sees no meeting workspace

### AI connector (MCP)

Lets external AI assistants work with live CRM data through the Model Context Protocol. Depends on INT and SEC.

#### MCP-01 · MCP server

- **Description and behavior:** An MCP endpoint that assistants connect to with an OAuth login. A sync mode, as in the source's ChatGPT app, indexes records every 30 minutes so an assistant can search deals, leads, contacts, pipelines, activities, email conversations, products, users, custom fields, automations and reports
- **Rules, limits and edge cases:** Every call runs as the connected user with that user's permissions and counts against API limits. Tools expose CRM data only, never survey data
- **Acceptance criteria:** An assistant can only see and change what the user can

#### MCP-02 · Tool catalog

- **Description and behavior:** Tools to get, list, add, update and search activities, deals, people, organizations, leads, products, pipeline stages and notes, plus convert lead to deal
- **Rules, limits and edge cases:** The source documents 37 tools. Tool names and schemas are generated from the API definitions
- **Acceptance criteria:** Every tool has a schema and returns structured results

#### MCP-03 · Admin controls

- **Description and behavior:** A company-level switch for MCP access. Switching it off blocks new connections and removes existing ones
- **Rules, limits and edge cases:** Does not affect API tokens or other integrations
- **Acceptance criteria:** After switch-off no assistant call succeeds

### Email marketing (CMP)

One-to-many email to consenting contacts. The Orgpuls admin already specifies contacts with consent, segments, a campaign editor, scheduling, subject-line tests, event-triggered sequences and campaign reporting; this module is specified in full, and what the admin already has is extended, not rebuilt.

#### CMP-01 · Email builder

- **Description and behavior:** A drag-and-drop editor with rows for layout and content blocks: title, paragraph, list, image, button, divider, social, HTML, video, icons, menu. Row properties cover border, background color or image and padding. A design starts blank or from a layout. Desktop and mobile preview
- **Rules, limits and edge cases:** The footer always carries the sender's postal address and an unsubscribe link and cannot be removed
- **Acceptance criteria:** A built email renders in the preview as it is delivered

#### CMP-02 · Templates

- **Description and behavior:** Ready-made layouts, a library of saved templates and code-your-own HTML templates
- **Rules, limits and edge cases:** Templates are stored as data and versioned
- **Acceptance criteria:** A template can start a new campaign

#### CMP-03 · Audience

- **Description and behavior:** Recipients are chosen with CRM filters over people, including engagement and location. Sales and marketing share one contact list
- **Rules, limits and edge cases:** Only addresses with the subscribed status receive mail
- **Acceptance criteria:** The recipient count equals subscribed matches of the filter

#### CMP-04 · Marketing status and consent

- **Description and behavior:** Each email address has a status: no consent, subscribed, unsubscribed, bounced, pending double opt-in, pending upgrade, archived. Single or double opt-in. Every change is logged with time and source
- **Rules, limits and edge cases:** The admin's consent record, with its basis and date, is the source of truth, and the statuses here are derived from it. The suppression list applies to every campaign send; sales email follows the consent setting (CUS-07)
- **Acceptance criteria:** An unsubscribed address cannot be mailed by any campaign

#### CMP-05 · Scheduling and sending

- **Description and behavior:** Send now or at a set time through a sending provider on a marketing stream that is separate from transactional mail
- **Rules, limits and edge cases:** The subscriber allowance is an entitlement; addresses over it wait as pending
- **Acceptance criteria:** A scheduled campaign leaves at the set time

#### CMP-06 · Campaign analytics

- **Description and behavior:** Per campaign: delivered, bounced, unsubscribed, spam reports, total and unique opens and clicks, open rate, click rate, click-through rate and top locations. Owners can be notified of engagement
- **Rules, limits and edge cases:** Needs engagement tracking switched on. A hard bounce or five soft bounces set the address to bounced
- **Acceptance criteria:** Figures match provider events for the campaign

#### CMP-07 · Automated campaigns

- **Description and behavior:** A campaign email can be a step in a workflow, so CRM changes trigger marketing mail with delays
- **Rules, limits and edge cases:** The audience comes from the workflow, not a filter
- **Acceptance criteria:** A triggered email obeys consent status

#### CMP-08 · Deliverability

- **Description and behavior:** Sender domain authentication with DNS checks, account verification before first send, compliance recommendations and list hygiene warnings
- **Rules, limits and edge cases:** The sending provider requires an authenticated domain before the first send
- **Acceptance criteria:** An unauthenticated domain cannot send

#### CMP-09 · Campaign insights

- **Description and behavior:** Campaign performance and conversion reports in Insights, a filter by campaign type, and a comparison of two or more campaigns in one chart
- **Rules, limits and edge cases:** The comparison is a higher tier in the source product
- **Acceptance criteria:** The comparison shows the same figures as each campaign's own report

### Projects (PRJ)

Delivery work after a deal is won. Depends on PIP, ACT and AUT.

#### PRJ-01 · Boards and phases

- **Description and behavior:** Projects sit on kanban boards and move through phases. Several boards can exist for different processes
- **Rules, limits and edge cases:** Phases are added, renamed, reordered and deleted like pipeline stages
- **Acceptance criteria:** Dragging a project changes its phase and logs it

#### PRJ-02 · Project record

- **Description and behavior:** Title, board, phase, owner, start and end dates, labels, description, custom fields and links to deals, one person and one organization
- **Rules, limits and edge cases:** A project can be created from a won deal, with an AI-drafted brief from the deal's emails, notes and files that the user reviews
- **Acceptance criteria:** A project created from a deal shows the deal and its contacts

#### PRJ-03 · Work items

- **Description and behavior:** Tasks (optional owner, start and due date, several assignees), subtasks under a task, milestones for key progress points and activities for scheduled events
- **Rules, limits and edge cases:** Subtasks always have a parent. Activities need date, time and owner and can sync to a calendar
- **Acceptance criteria:** Completing all subtasks does not auto-complete the parent unless set

#### PRJ-04 · Dependencies and timeline

- **Description and behavior:** Tasks and milestones can depend on others. A Gantt timeline shows items by month with dependency lines, and a whole phase or group can be dragged to shift it
- **Rules, limits and edge cases:** A dependency cannot form a cycle. Overdue items are highlighted
- **Acceptance criteria:** Shifting a phase keeps the spacing between its items

#### PRJ-05 · Project templates

- **Description and behavior:** A reusable plan of tasks, activities, milestones and dependencies with due dates relative to the start date, organized by phases or groups
- **Rules, limits and edge cases:** An existing project can be saved as a template
- **Acceptance criteria:** A project from a template gets dated items from its start date

#### PRJ-06 · Project health

- **Description and behavior:** A status of on track, at risk, off track or on hold, set manually or suggested by an AI summary of the project's emails, notes, tasks and activities with recommendations
- **Rules, limits and edge cases:** The AI summary must be enabled per account and can be regenerated
- **Acceptance criteria:** The status shows on the board and in reports

#### PRJ-07 · Collaboration and sharing

- **Description and behavior:** Notes, files, @mentions and emails on a project, and a one-click AI-written status report as a PDF for clients
- **Rules, limits and edge cases:** The PDF contains only what the sender chooses to include
- **Acceptance criteria:** A mention on a project notifies the user

#### PRJ-08 · Bulk work and import

- **Description and behavior:** Paste a list to add many tasks; bulk edit items; import and export project data, including from other project tools
- **Rules, limits and edge cases:** A date in a pasted line becomes the due date
- **Acceptance criteria:** Pasted lines become tasks in the chosen phase

#### PRJ-09 · Automation and reports

- **Description and behavior:** Projects and their tasks are triggers and actions in workflows, and Insights has project performance and duration reports
- **Rules, limits and edge cases:** Uses AUT and INS
- **Acceptance criteria:** A workflow can create a project when a deal is won

### Lead generation (LGN)

Captures inbound leads on the company's website and finds outbound ones. Depends on LEA, AUT and COM.

#### LGN-01 · Chatbot

- **Description and behavior:** A scripted website bot built as playbooks in three steps: theme, profile (name, picture, language) and template. Templates: get more leads, book meetings, qualify and route, chat live. Questions can differ per page. Answers create a lead or deal, assign an owner and can book a meeting
- **Rules, limits and edge cases:** Qualified leads are highlighted at the top of the owner's leads inbox. Per-step drop-off statistics show where visitors leave
- **Acceptance criteria:** A completed conversation creates a lead with the answers stored

#### LGN-02 · Live chat

- **Description and behavior:** A rep takes over a chat in real time from the web or mobile app
- **Rules, limits and edge cases:** Chats wait in an unassigned queue for a set time, then fall back to the bot. An online message shows when a rep is available
- **Acceptance criteria:** A claimed chat is locked to one rep and saved on the lead

#### LGN-03 · Web forms

- **Description and behavior:** A form builder with input and message blocks and templates for contact, registration, gated download, file upload and blank. An introduction block is mandatory. Fields include name, phone, email, marketing status and custom fields, each optionally required. Forms are embedded, linked or shared to social channels, and each has an ID and an active or inactive status
- **Rules, limits and edge cases:** Submissions become leads or deals, and the owner is notified by email. The current owner is kept on resubmission. Forms capture UTM parameters, cookie values, referral URL and landing page and accept page variables in hidden fields. The form language is fixed at creation. The admin's contact form already creates a ticket and a consented prospect, and forms reuse that path. Tracking fields are on by default and can be switched off (CUS-07)
- **Acceptance criteria:** A submission creates a lead with source and tracking data; views, interactions, submissions and conversion are counted

#### LGN-04 · Prospect search

- **Description and behavior:** Search of an external business database by person filters (job title, department, location, name) and organization filters (size, industry, type, revenue, location, name, domain, keyword). Saved filters. Credits reveal contact details and add the prospect to the leads inbox
- **Rules, limits and edge cases:** The database is licensed from a provider, not built. The search itself is built in full. Revealed contacts follow the contact-rule setting, off by default
- **Acceptance criteria:** Revealing a prospect uses one credit and creates a lead

#### LGN-05 · Embedding and consent

- **Description and behavior:** One script loads chatbot, live chat and tracking on a site. Forms and widgets can carry consent wording and a cookie notice
- **Rules, limits and edge cases:** Consent-gated loading of widgets is a setting, off by default (CUS-07). One rule is fixed by the admin specification: the tracker and widgets are never loaded in the survey flow
- **Acceptance criteria:** With the consent setting on and consent declined, no tracking cookie is set. No widget ever appears on a survey page

### Web visitors (WEB)

Shows which organizations visit the website. Depends on LEA, CRM and an IP-to-company data source. The admin already has cookieless web analytics; this module adds company identification on top of it. Identification is on by default and can be switched off (CUS-07).

#### WEB-01 · Tracker

- **Description and behavior:** A script on one or more websites records visits and pages
- **Rules, limits and edge cases:** Sites are told apart by hostname. The tracker is never loaded in the survey flow, a fixed rule of the admin specification
- **Acceptance criteria:** Visits from each site appear under that site

#### WEB-02 · Organization identification

- **Description and behavior:** Visits are matched to companies. Internet providers, crawlers and irrelevant traffic are filtered out
- **Rules, limits and edge cases:** A company counts once per month for billing however often it visits. Data refreshes hourly
- **Acceptance criteria:** A known company IP produces a named visitor

#### WEB-03 · Visitor inbox and ranking

- **Description and behavior:** A list of visiting companies with location, industry, last visit, source, pages viewed and a ranking by activity
- **Rules, limits and edge cases:** Filters for period, country, campaign, page and whether the company is already in the CRM
- **Acceptance criteria:** Sorting by quality puts the most active companies first

#### WEB-04 · Convert and reveal

- **Description and behavior:** A visitor becomes a lead, deal or organization. Prospect search finds people at that company
- **Rules, limits and edge cases:** Revealing people uses prospect credits (LGN-04)
- **Acceptance criteria:** The created record links to the visit history

### Documents and e-sign (DOC)

Quotes, proposals and contracts from a deal. Depends on PIP, the product catalog and cloud storage.

#### DOC-01 · Templates and merge fields

- **Description and behavior:** Document, spreadsheet and presentation templates with placeholders for deal, person, organization, product and project fields. Templates are named, categorized and shared company-wide, and can be imported from the connected drive
- **Rules, limits and edge cases:** Address fields can be split into parts. A missing value is flagged before sending
- **Acceptance criteria:** A document generated from a template contains the deal's data

#### DOC-02 · Product tables

- **Description and behavior:** A table in a template fills with the deal's products, prices, discounts, tax and totals
- **Rules, limits and edge cases:** Columns are configurable. Not available in spreadsheet templates in the source
- **Acceptance criteria:** Table totals equal the deal value

#### DOC-03 · Cloud storage

- **Description and behavior:** Documents are created and stored in the user's Google Drive, OneDrive or SharePoint, in a personal or shared location
- **Rules, limits and edge cases:** A default shared location can be set per company. Generated PDFs are always stored in the platform
- **Acceptance criteria:** A new document appears in the connected drive

#### DOC-04 · Trackable links

- **Description and behavior:** A document or uploaded PDF is shared through a link that records each open and notifies the owner
- **Rules, limits and edge cases:** Links can be disabled
- **Acceptance criteria:** An open is logged with time on the deal

#### DOC-05 · E-signatures

- **Description and behavior:** Signature requests to up to 10 signers with a one-time email code, a custom message, an invite language and signer fields placed by drag and drop
- **Rules, limits and edge cases:** A signed document is sealed with an audit trail. The legal weight of the signature level must be confirmed for your contracts
- **Acceptance criteria:** A completed request stores the signed PDF and audit trail on the deal

#### DOC-06 · Branding and external signing

- **Description and behavior:** Platform branding can be removed from documents. An external e-signature service can be used instead of the built-in one
- **Rules, limits and edge cases:** Through an adapter
- **Acceptance criteria:** A document sent through the external service shows its status on the deal

### Security and permissions (SEC)

Who can do and see what, and how the admin is protected. The admin specification already defines four staff roles (super-admin, support, finance, read-only analyst), mandatory MFA, an audit log, session timeout, an optional IP allowlist, login alerts, a quarterly access review and break-glass access; these features add screens and rules on top. It defines no sales, marketing or project role, so those are added as roles or permission sets in SEC-07.

#### SEC-01 · Security dashboard

- **Description and behavior:** Right now: users logged in and their locations. Last 7 days: new devices, new locations, security events, forced logouts. An assessment lists high- and low-risk issues with fixes
- **Rules, limits and edge cases:** Admin only. Each figure opens its list
- **Acceptance criteria:** The figures match the login log

#### SEC-02 · Security alerts

- **Description and behavior:** Email alerts when a user logs in from a new device or location, a user is invited, a user has more than 3 failed logins in a row, a password reset is requested, or unusually large exports or deletions happen
- **Rules, limits and edge cases:** Sent at once or as a digest at a set time
- **Acceptance criteria:** Each trigger produces one alert to admins

#### SEC-03 · Security rules

- **Description and behavior:** Company-wide password strength, expiry and reuse rules and access restrictions by IP address and by time
- **Rules, limits and edge cases:** A preview shows who is affected before enforcing
- **Acceptance criteria:** A login from a blocked IP is refused

#### SEC-04 · Device and login history

- **Description and behavior:** Per user: devices, locations, IP addresses, login time and method, session end, for the last 60 days, with remote log-out
- **Rules, limits and edge cases:** This is a login log. Record changes are audited separately in each record's changelog
- **Acceptance criteria:** Logging out a device ends its session at once

#### SEC-05 · Single sign-on

- **Description and behavior:** SAML sign-on with identity providers such as Entra ID and Okta, and sign-in with Google
- **Rules, limits and edge cases:** A fallback login for admins stays available
- **Acceptance criteria:** A user provisioned at the identity provider can log in without a local password

#### SEC-06 · Two-factor authentication

- **Description and behavior:** A second factor at login by email code or authenticator app. Admins can enforce it for everyone. Account recovery and a remembered login email are supported
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** With enforcement on, no user can log in without the second factor

#### SEC-07 · Permission sets

- **Description and behavior:** Named sets of allowed actions, separate for the deals, projects and campaigns apps and for global features. Admin (full), regular (editable) and custom sets
- **Rules, limits and edge cases:** Actions include create, edit, delete, import, export, bulk edit, change visibility and view reports. The number of custom sets is an entitlement
- **Acceptance criteria:** A user cannot perform an action missing from their set, in the interface or the API

#### SEC-08 · Visibility groups

- **Description and behavior:** Users sit in groups and sub-groups. Each item is visible to its owner only, the owner's group, the owner's group and sub-groups, or everyone. Defaults are set per record type; pipelines can be limited to groups. A setting decides whether hidden activities and notes show as placeholders
- **Rules, limits and edge cases:** Enforced by row-level security. The number of custom groups is an entitlement
- **Acceptance criteria:** A user outside the group cannot read the row by any route

#### SEC-09 · Users and teams

- **Description and behavior:** Invite, deactivate and replace users and reassign their records. Teams with a manager and members are used by assignment, reports and goals. Access settings can be copied from another user. A user overview page lists followed items and last login. Users edit their own profile and phone number
- **Rules, limits and edge cases:** Deactivating a user who owns workflows prompts a transfer (AUT-10)
- **Acceptance criteria:** A deactivated user cannot log in and their records keep an owner

#### SEC-10 · Data protection

- **Description and behavior:** Encryption in transit and at rest, isolation of CRM data from survey data, EU hosting and backups with stated recovery objectives
- **Rules, limits and edge cases:** The source states a one-hour recovery point and two-hour recovery time; your targets are an open decision
- **Acceptance criteria:** A restore test meets the agreed objectives

#### SEC-11 · Privacy compliance

- **Description and behavior:** Export and erasure of a person's data on request, consent logs, retention rules and a list of sub-processors
- **Rules, limits and edge cases:** Erasure covers emails, recordings, transcripts and enrichment data
- **Acceptance criteria:** An erasure request removes the person from every module

### Integrations and API (INT)

How other systems read, write and react. Depends on SEC, ENT and the event catalog.

#### INT-01 · REST API

- **Description and behavior:** Versioned endpoints to list, get, create, update, delete and search every entity, including custom fields, with filtering and pagination, a published API reference, client libraries and request collections
- **Rules, limits and edge cases:** The API definition is generated from the same registry as the interface, so new fields appear automatically
- **Acceptance criteria:** Every interface action on records is possible through the API

#### INT-02 · Authentication

- **Description and behavior:** A personal API token per user, sent in a header, with one active token at a time, and OAuth 2.0 with scopes for apps
- **Rules, limits and edge cases:** Rotating a token invalidates the old one at once
- **Acceptance criteria:** A revoked token or grant is refused

#### INT-03 · Rate limits

- **Description and behavior:** A daily token budget per company (base × plan multiplier × seats), a token cost per endpoint type and a burst limit per token in a rolling 2-second window
- **Rules, limits and edge cases:** Rate limits are off by default (CUS-07). When they are on, calls over budget return HTTP 429. Admins are emailed at 75% and 100%. A usage dashboard shows consumption
- **Acceptance criteria:** A client over the burst limit gets 429 with limit headers

#### INT-04 · Webhooks

- **Description and behavior:** Subscriptions by action (create, change, delete) and object. Each event is an HTTP POST with a JSON body holding current and previous state
- **Rules, limits and edge cases:** Source limits: 40 webhooks per user, 10-second timeout, retries after 3, 30 and 150 seconds, a 30-minute ban after 10 first-attempt failures, deletion after 3 days without success
- **Acceptance criteria:** A failing endpoint is retried on schedule and then banned

#### INT-05 · Google Workspace

- **Description and behavior:** Contacts, calendar, tasks, Drive files, Gmail, Meet links and sign-in
- **Rules, limits and edge cases:** Uses COM-02, ACT-09, CRM-04 and DOC-03
- **Acceptance criteria:** Each connection can be made and revoked by the user

#### INT-06 · Microsoft 365

- **Description and behavior:** Outlook and Exchange mail, calendar, contacts, Teams links and notifications, OneDrive and SharePoint
- **Rules, limits and edge cases:** Same features as INT-05
- **Acceptance criteria:** Same as INT-05

#### INT-07 · Team chat

- **Description and behavior:** Deal events posted to Slack or Microsoft Teams channels or direct messages, and search of deals, people and organizations from chat
- **Rules, limits and edge cases:** Also a workflow action (AUT-07)
- **Acceptance criteria:** A won deal posts to the configured channel

#### INT-08 · Invoicing

- **Description and behavior:** An invoice is created in the accounting system from a deal with its person, organization and products, and its status shows on the deal
- **Rules, limits and edge cases:** Through an adapter; which accounting system to support first is part of open point 2
- **Acceptance criteria:** An invoice created from a deal carries the deal's lines

#### INT-09 · Automation platforms

- **Description and behavior:** Connectors for no-code automation platforms, built on the API and webhooks
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** A new deal can trigger an external automation

#### INT-10 · App extensions

- **Description and behavior:** Integrations can show panels inside deal and contact detail views and offer actions that open a link, a dialog or embedded interface
- **Rules, limits and edge cases:** Panels are sandboxed and get only the data their scopes allow
- **Acceptance criteria:** An installed extension shows its panel on the detail view

#### INT-11 · Integration catalog

- **Description and behavior:** A list of available integrations, grouped in collections by sales stage and tagged by function, with what each can access, an install step, settings, per-user management and removal
- **Rules, limits and edge cases:** Third-party apps built on the app platform (INT-02, INT-10) can be listed beside the first-party connectors
- **Acceptance criteria:** Removing an integration revokes its access

### Mobile app (MOB)

iOS and Android clients on the same API.

#### MOB-01 · Core app

- **Description and behavior:** Pipeline, deals, leads, contacts, activities (list and calendar), detail views, filters and search, synced in real time with the web app, in portrait and landscape, with import of phone contacts
- **Rules, limits and edge cases:** Same permissions as the web app
- **Acceptance criteria:** A change on mobile appears on the web without refresh

#### MOB-02 · Focus view

- **Description and behavior:** The opening screen: overdue activities and deals, unread email count, nearby count, and activities and expected closes for today and the coming week, plus an agenda widget for the phone's home screen
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** Counts match the same filters on the web

#### MOB-03 · Nearby

- **Description and behavior:** A map of deals, organizations and people near the user's location, with filters, including address custom fields, and a hand-off to a navigation app
- **Rules, limits and edge cases:** Needs location permission
- **Acceptance criteria:** Tapping a pin opens the record

#### MOB-04 · Calls and texts

- **Description and behavior:** Calls from the app are logged as activities. Incoming callers are matched to contacts. A text opens the phone's messaging app with the number filled
- **Rules, limits and edge cases:** As in the source, iOS logs only outgoing calls made in the app, while Android logs calls in full
- **Acceptance criteria:** A call from the app creates an activity

#### MOB-05 · Offline mode

- **Description and behavior:** Deals, notes and activities can be changed offline and sync when the connection returns; a sync can also be forced manually
- **Rules, limits and edge cases:** Conflicts are resolved by the latest change, with the earlier value kept in the changelog
- **Acceptance criteria:** Offline changes appear after reconnecting

#### MOB-06 · Capture

- **Description and behavior:** Audio notes with transcription, a scanner that turns handwritten or printed notes into text, photo and file upload, sharing content from other apps into the CRM, and the card scanner (AIA-07)
- **Rules, limits and edge cases:** None stated.
- **Acceptance criteria:** A scanned note is saved on the chosen record

#### MOB-07 · Push notifications

- **Description and behavior:** Reminders, assignments, mentions and chat requests
- **Rules, limits and edge cases:** Configurable per type
- **Acceptance criteria:** A new assignment sends one push

#### MOB-08 · Mobile extras

- **Description and behavior:** Live chat takeover, project tasks and a statistics dashboard
- **Rules, limits and edge cases:** Project support may follow the web release, as in the source
- **Acceptance criteria:** A rep can answer a live chat from the phone

### Plans and entitlements (ENT)

Turns every plan gate and usage limit into configuration. It is built in full, as decided; by default every feature is on and every limit is unlimited.

#### ENT-01 · Feature gating

- **Description and behavior:** Each feature is switched on per plan and add-on from an entitlement table
- **Rules, limits and edge cases:** Checked in the interface, the API and the workflow engine
- **Acceptance criteria:** A gated feature is unavailable through every channel

#### ENT-02 · Usage limits

- **Description and behavior:** Metered limits per company or per seat: leads and deals, custom fields, reports, active workflows, branches per workflow, sequences, mailboxes, team inboxes, teams, visibility groups, permission sets, scoring models, enrichment credits, formula fields, API tokens
- **Rules, limits and edge cases:** The source's values per plan are in the inventory's usage-limits table. Every limit is unlimited until an admin sets a value
- **Acceptance criteria:** A limit is enforced at the moment of creation

#### ENT-03 · Plans, add-ons and top-ups

- **Description and behavior:** Seat-based plans, add-ons priced per company, per seat or by volume, credit top-ups and a free trial
- **Rules, limits and edge cases:** Uses the existing billing
- **Acceptance criteria:** Buying an add-on enables its features at once

#### ENT-04 · Usage screen and limit handling

- **Description and behavior:** A page showing consumption against every limit. At a limit, new additions are blocked and nothing is deleted; overflow goes to the waitlist or the import skip file
- **Rules, limits and edge cases:** Warnings before the limit is reached
- **Acceptance criteria:** The usage page matches actual counts

---

## Part D — User flows

The 29 flows below reference all 183 specifications. Each lists the actor, the features it uses by ID, the steps in order and where the path branches.

### Sales rep flows

#### UF-01 · Capture and qualify a lead

Actor: sales rep. Uses LEA-01 to LEA-05, AUT-11, PRO-04, CRM-15, ACT-07.

1. A lead arrives from a form, chatbot, import, prospect search or manual entry, with its source recorded.
2. An assignment rule sets the owner; the owner is notified.
3. The rep opens the lead, reads the enriched company data and any chat or form answers.
4. The rep emails or calls; the contact is logged on the lead.
5. If the lead is not relevant, the rep labels and archives it. The flow ends.
6. If qualified, the rep converts it to a deal and picks pipeline and stage.
7. Notes, emails, files and activities move to the deal, and the rep is prompted to plan the next activity.

#### UF-02 · Work a deal to won or lost

Actor: sales rep. Uses PIP-01 to PIP-07, CUS-02, CRM-07, ACT-01, ACT-04, ACT-07.

1. The rep opens the pipeline; cards without a planned activity show a warning and idle deals show as rotting.
2. The rep opens a deal and reads Focus and History.
3. The rep completes the due activity and plans the next one when prompted.
4. The rep drags the deal to the next stage. If a required field is empty, the move is blocked until it is filled.
5. The rep adds products; the deal value recalculates.
6. The rep marks the deal won, or marks it lost and gives a reason.
7. Workflows listening for that change run (for example, creating a project).

#### UF-03 · Daily routine in the feed

Actor: sales rep. Uses PRO-01, PRO-02, PRO-03, COM-06.

1. The rep opens the feed on the Follow-ups tab and sees replies, opened emails, today's activities and emails waiting to send.
2. For each card the rep acts from the card or opens the side panel.
3. The Overlooked deals tab lists deals with no follow-up or overdue activities; the rep schedules a next step for each.
4. The Opportunities tab lists new deals with no activity; the rep plans a first step.
5. The rep filters by score to take the best deals first. The counter shows what is done.

#### UF-04 · Email outreach with tracking

Actor: sales rep. Uses COM-02, COM-05, COM-06, COM-08, AIA-03, AIA-04.

1. From a deal, the rep opens the composer and picks a template or asks the AI writer for a draft.
2. Merge fields fill; a missing value is flagged.
3. The rep sends now or schedules.
4. If sending fails, the outbox shows the reason and the rep retries.
5. When the contact opens or clicks, the rep is notified.
6. If the contact replies, the thread links to the deal and the rep can ask for a summary and suggested reply.
7. If there is no reply after 5 days, a follow-up card appears in the feed.

#### UF-05 · Nurture with a sequence

Actor: sales rep or manager. Uses AUT-12, COM-05, ACT-01.

1. The user builds a sequence of email and activity steps with delays.
2. The user enrolls leads or deals one by one or in bulk, or a workflow enrolls them.
3. Automatic email steps send at the planned time; manual ones wait for the rep to review and send.
4. Activity steps create activities for the owner.
5. If the contact replies or the deal changes stage, enrollment ends.
6. Otherwise the record completes the sequence. A failed step marks the enrollment failed with the reason.

#### UF-06 · Book a meeting

Actors: sales rep and contact. Uses COM-10, COM-11, ACT-08, ACT-09.

1. The rep sets availability once and puts a booking link in an email, signature or automated message.
2. The contact opens the booking page, sees free slots in their own time zone and picks one.
3. Both receive a confirmation; an activity with a video link is created on the deal.
4. The slot disappears for other invitees and the event syncs to the rep's calendar.
5. If the contact reschedules or cancels, the activity and calendar event are updated.

#### UF-07 · Run a meeting with meeting intelligence

Actor: sales rep. Uses MTG-01 to MTG-08, AIA-03.

1. Before the meeting the rep reads the brief.
2. Attendees are notified of recording. The bot joins the call, or the rep records with the desktop app.
3. If an attendee objects, the rep removes the bot or stops recording.
4. After the call the recap and transcript are saved on the deal and a chat message announces it.
5. The rep reviews the suggested CRM updates and approves the ones that are right.
6. The rep sends a follow-up drafted from the recap and plans the next activity.

#### UF-08 · Quote to signature

Actors: sales rep and customer. Uses DOC-01 to DOC-06, CRM-07, AUT-01.

1. From the deal's Documents tab the rep picks a template.
2. The document is generated with deal data and a product table and opens for editing.
3. The rep shares it by trackable link or requests signatures, adding signers and a message.
4. The customer opens the document; the rep is notified.
5. Each signer enters the emailed code and signs.
6. The signed PDF and audit trail are stored on the deal, and a workflow can move the deal to won.
7. If nobody opens or signs, the rep sees the status and follows up.

### Manager and admin flows

#### UF-09 · Set up the sales process

Actor: admin. Uses PIP-02, PIP-14, CUS-01 to CUS-08, ACT-02, SEC-07 to SEC-09.

1. The admin creates pipelines and stages with probabilities and rotting thresholds.
2. The admin adds custom fields, groups them and marks important and required ones.
3. The admin sets activity types, currencies and which modules are on.
4. The admin invites users, places them in teams and visibility groups and assigns permission sets.
5. The admin tests with a sample deal. In a sandbox, nothing reaches the live company.

#### UF-10 · Import and clean data

Actor: admin. Uses CRM-09, AIA-05, CRM-11, CRM-12, ENT-04.

1. The admin uploads a spreadsheet and confirms or corrects the suggested column mapping.
2. The system previews duplicates; the admin chooses merge or create.
3. The import runs. Rows that fail validation or exceed capacity go to the skip file.
4. The admin downloads the skip file, fixes it and imports again.
5. The admin reviews suggested duplicates and merges them.
6. If the import was wrong, the admin reverts it from the import history.

#### UF-11 · Build a workflow

Actor: admin or permitted user. Uses AUT-01 to AUT-10.

1. The user starts from a template or a blank canvas.
2. The user picks an event or date trigger and adds conditions.
3. The user adds actions, delays, wait-for steps and branches.
4. The user saves a draft, then activates it for themselves, selected users or a team.
5. Matching events start runs. The history shows each run.
6. If a step fails, the owner is alerted and opens the failing step from the overview.
7. If a limit has been set and is reached, activation is refused with the reason.

#### UF-12 · Set up automatic assignment

Actor: admin. Uses AUT-11, SEC-09.

1. The admin creates a rule for lead added, deal added or deal updated.
2. The admin sets conditions and the assignee: user, team, organization owner or person owner.
3. The admin orders the rules by priority and activates them.
4. New records are assigned by the first matching rule; with no match the creator stays owner.
5. The admin checks the assignment history to see which rule fired.

#### UF-13 · Reports, dashboards and goals

Actor: manager. Uses INS-01 to INS-10.

1. The manager creates a report by choosing a type or typing a request for the AI generator.
2. The manager sets measure, dimensions, filters and chart type.
3. The manager adds reports to a dashboard, arranges them and shares the dashboard with the team or by public link.
4. The manager creates goals for users or teams and tracks progress.
5. The manager exports a chart or the underlying rows when needed.

#### UF-14 · Scoring and enrichment

Actor: admin and sales rep. Uses PRO-03 to PRO-06.

1. The admin creates a scoring model for a pipeline and adds criteria to the three groups.
2. The preview shows how sample deals score; the admin activates the model.
3. Scores appear on deals and in the feed filter.
4. A rep enriches an organization or selects up to 100 records for bulk enrichment.
5. If a credit allowance is set and credits are short, the request is refused and the admin can buy a top-up.
6. Enriched fields update scores that depend on them.

#### UF-15 · Security administration

Actor: admin. Uses SEC-01 to SEC-06, SEC-10, SEC-11.

1. The admin opens the security dashboard and works through the assessment.
2. The admin configures single sign-on and enforces two-factor authentication.
3. The admin sets password, IP and time rules, previews who is affected and enforces them.
4. The admin chooses alerts and how they are delivered.
5. On an alert the admin checks the login history and logs the device out.
6. On a privacy request the admin exports or erases the person's data.

#### UF-16 · Connect systems

Actor: admin or developer. Uses INT-01 to INT-11, MCP-01 to MCP-03, AIA-06.

1. The user connects Google or Microsoft for mail, calendar, contacts and files.
2. A developer creates an API token or registers an OAuth app and reads the API reference.
3. The developer subscribes webhooks to events.
4. If an endpoint keeps failing, the webhook is banned and later removed; the developer sees this in the webhook list.
5. The admin finds integrations in the catalog by search or recommendation, installs them and reviews their access.
6. The admin switches the AI connector on or off for the company.

### Marketing, project, visitor and mobile flows

#### UF-17 · Send an email campaign

Actor: marketer. Uses CMP-01 to CMP-09.

1. The marketer authenticates the sender domain; sending stays blocked until it passes.
2. The marketer builds the email from a template in the editor and previews desktop and mobile.
3. The marketer picks the audience with a filter; only subscribed addresses are counted.
4. The marketer sends now or schedules.
5. Bounces, unsubscribes and spam reports update each address's status.
6. The marketer reads the campaign report and compares it with earlier campaigns.

#### UF-18 · Website visitor to lead

Actors: visitor and sales rep. Uses LGN-01 to LGN-05, LEA-01, AUT-11, COM-10.

1. A visitor opens a page and the widget loads; if consent-gated loading is switched on, it loads according to consent.
2. The chatbot asks its questions for that page.
3. If the visitor qualifies, the bot offers a meeting slot or a live chat.
4. If a rep is online and claims the chat within the waiting time, the rep takes over; otherwise the bot continues and collects contact details.
5. A lead is created with the answers, source and tracking data and assigned by rule.
6. Alternatively the visitor submits a web form, which creates the lead the same way.

#### UF-19 · Identify web visitors

Actor: sales rep. Uses WEB-01 to WEB-04, LGN-04.

1. The admin installs the tracker on the website.
2. Visiting companies appear in the visitor inbox, ranked by activity.
3. The rep filters by country, campaign or page and opens a company's visit history.
4. If the company is already in the CRM, the rep sees the existing record.
5. Otherwise the rep converts it to a lead or organization and uses prospect search to find contacts.

#### UF-20 · Hand over a won deal to delivery

Actors: sales rep and project manager. Uses PRJ-01 to PRJ-09, AUT-07.

1. A deal is marked won; a workflow or the rep creates a project from it, optionally from a template.
2. The project brief is drafted from the deal and reviewed.
3. The project manager adjusts tasks, owners, dates and dependencies on the timeline.
4. The team works the tasks; the board shows phase and health.
5. If the project slips, the manager sets the health status or requests an AI summary with recommendations.
6. The manager shares a status report with the client and closes the project when done.

#### UF-21 · Field visit on mobile

Actor: sales rep. Uses MOB-01 to MOB-08, AIA-07.

1. The rep opens the app on the focus view and sees the day.
2. The rep checks Nearby for contacts around the next meeting and navigates there.
3. Without a connection the rep still opens the deal and adds notes.
4. After the meeting the rep records an audio note, scans a business card and plans the next activity.
5. Changes sync when the connection returns.

#### UF-22 · Work through an external AI assistant

Actor: any user. Uses MCP-01 to MCP-03, INT-03.

1. The user adds the connector in their AI assistant and logs in.
2. The user asks the assistant to find, create or update records in plain language.
3. The assistant calls tools; each call runs with the user's permissions and counts against API limits.
4. If the admin has switched the connector off, the connection is refused.
5. Changes made through the assistant appear in the changelog with the connector as source.

### Flows added in the quality review

#### UF-23 · Manage contacts and organizations

Actor: sales rep or admin. Uses CRM-01 to CRM-06, CRM-10, CRM-13, CRM-14.

1. The user opens an organization and sees its contacts, deals, tickets, activities and files.
2. The user adds a contact. Source and basis are optional by default and required only if the contact-rule setting is on.
3. The user adds a note, mentions a colleague and attaches a file.
4. The user links a parent organization and applies labels.
5. The contacts timeline shows who has had no contact in the chosen period; the map shows contacts near a place.
6. With contact sync connected, changes flow to and from the user's address book.
7. The user exports a filtered list; the export is logged.

#### UF-24 · Review and maintain the pipeline

Actor: sales rep or manager. Uses PIP-08 to PIP-13, PIP-15, PIP-17, ACT-03, ACT-05, ACT-06.

1. The user searches for a record or applies a saved filter.
2. In the list view the user picks columns, sorts and edits cells inline.
3. The user selects several deals and bulk edits an owner or label, or adds an activity to all of them.
4. The user adds participants to a deal and follows a colleague's deal.
5. In the calendar the user reschedules activities and sets priorities.
6. The user archives dead deals, shows closed deals to review them, duplicates a deal and restores one deleted by mistake.
7. If a bulk delete is requested, a preview is shown. A second admin must approve it only if that setting is on.

#### UF-25 · Calls, messages and shared inboxes

Actor: sales rep. Uses COM-01, COM-03, COM-04, COM-07, COM-09, COM-12, COM-13, COM-14, LEA-06.

1. The rep clicks a phone number; the call runs through the telephony provider and is logged with outcome and duration.
2. A message from a contact arrives in the messaging inbox and notifies the owner.
3. The rep answers an email in a shared inbox; colleagues see the reply on the thread.
4. The rep picks the sending mailbox, labels the thread and archives it.
5. The rep sends one email to a selected list. By default every recipient gets the email. If the consent setting is on, recipients without a consent basis or on the suppression list are left out and reported.
6. Working in the mail client, the rep adds a deal from the side panel. Without mail sync, the rep copies in the BCC address instead.

#### UF-26 · Recurring revenue and forecast

Actors: sales rep and manager. Uses CRM-08, PIP-11, INS-06.

1. The rep adds a recurring product or an installment plan to a deal.
2. The deal shows MRR, ARR, ACV and TCV.
3. The manager opens the forecast view and drags a deal to a later month.
4. The forecast reports show expected revenue by month from deals and from recurring products.
5. For existing Orgpuls customers the recurring figures come from billing, not from deals.

#### UF-27 · Work with the AI assistant

Actor: any staff user. Uses AIA-01, AIA-02, PRO-07.

1. The user asks the assistant about deals or contacts; the answer cites the records used.
2. A question about survey answers is refused, because that data is outside the assistant's reach.
3. The user opens the notifications panel and sees deals flagged as stalled, each with a suggested next step.
4. The user accepts a suggestion; the action runs and is logged.
5. For an email from an unknown sender the assistant proposes a contact, and the user accepts it to create the record.

#### UF-28 · Plans and limits

Actor: admin. Uses ENT-01 to ENT-03, PIP-16. By default nothing is limited; this flow applies once an admin sets plans or limits.

1. The admin opens the usage page and sees consumption against each limit.
2. At a limit a manual creation is refused, and automated lead and deal creation goes to the waitlist.
3. The admin upgrades the plan or buys a top-up; the feature or allowance is available at once.
4. The admin adds the waitlisted deals back.

#### UF-29 · Set rules and limits

Actor: admin. Uses CUS-07, ENT-01, ENT-02.

1. The admin opens Settings and sees every rule with its current value; by default all are unrestricted.
2. The admin switches on a rule, for example the contact rule or consent checks on sales email, and picks warn or block where offered.
3. The admin sets a limit or a plan gate if one is wanted.
4. The change applies at once and is logged with who and when.
5. A user who then hits a rule sees which setting stopped the action.
6. Switching the rule off restores full function.

---

## Part E — System flows

The 45 flows below describe what the system does behind the user flows. Every specification is served by at least one of them. Each names its trigger, the features it serves and the failure path.

### Core engines

#### SF-01 · Permission and visibility check

Runs on every read and write. Serves SEC-07, SEC-08, CUS-03, ENT-01.

1. The request is authenticated and tied to a staff user, a role and a product.
2. The user's permission sets decide whether the action is allowed at all.
3. Row-level security decides which rows match: owner, the owner's group, the group and its sub-groups, or everyone.
4. Field rules remove hidden fields and reject writes to read-only ones.
5. Where entitlements are in use, the check confirms the feature is switched on.
6. A refusal returns a clear error and is logged. A read of customer-scoped data writes an audit row; a typed reason is asked for only if that setting is on. Survey response tables are unreachable from every CRM function.

#### SF-02 · Record change and event publication

Triggered by any create, update or delete. Serves PIP-04, AUT, INT-04, INS-10.

1. The change, its changelog entry and an event are written in one transaction.
2. A dispatcher reads new events and delivers them to subscribers: workflows, assignment, scoring, feed, report rollups, webhooks, notifications.
3. Each subscriber processes an event once, identified by its ID.
4. A subscriber that fails retries without blocking the others.

#### SF-03 · Email sync

Triggered by a mailbox connection and by new mail. Serves COM-01 to COM-09.

1. The user authorizes the mailbox; tokens are stored encrypted.
2. History is loaded back to the chosen start date.
3. New mail arrives by provider notification or polling and is stored.
4. Senders and recipients are matched to people; the thread links to their open deal or lead, or waits for manual linking.
5. Outgoing mail is sent through the provider with tracking added, then stored.
6. Opens and clicks come back as events and notify the sender.
7. If a token expires or a send fails, the user is asked to reconnect or sees the failure reason in the outbox.

#### SF-04 · Workflow execution

Triggered by an event or a date. Serves AUT-01 to AUT-10.

1. The engine finds active workflows whose trigger matches.
2. Conditions are evaluated; a failed condition ends silently.
3. A run is created and steps execute in order with the owner's permissions.
4. A delay schedules the next step; a wait-for step listens for its condition and stops the run after 7 days.
5. A branch picks one path.
6. Each step's result is written to the run history.
7. A failed action marks the run failed and alerts the owner. Run counters stop loops when the rolling limit is passed.

#### SF-05 · Sequence scheduler

Triggered by enrollment. Serves AUT-12.

1. On enrollment the first step's time is computed, skipping weekends if set.
2. If the consent setting is on, consent basis and the suppression list are checked first. Then an automatic email is sent, a manual email is queued in the feed, or an activity is created.
3. The next step is scheduled.
4. A reply or a stage change ends the enrollment.
5. After the last step the enrollment is completed; a failed send marks it failed.

#### SF-06 · Assignment engine

Triggered when a lead is added or a deal is added or updated. Serves AUT-11.

1. Active rules for that event are loaded in priority order.
2. The first rule whose conditions match is chosen.
3. The assignee is resolved: a user, the next member of a team in rotation, the organization's owner or the person's owner.
4. The owner is set, the evaluation is logged and the new owner is notified.
5. With no match the record keeps its owner.

#### SF-07 · Notifications and reminders

Triggered by due activities, mentions, assignments, email events and AI cards. Serves ACT-04, CRM-06, MOB-07.

1. The source emits a notification request.
2. The service applies the user's channel preferences.
3. It delivers in the app, by email or by push.
4. Duplicates within a short window are merged.

#### SF-08 · Calendar sync

Triggered by changes on either side. Serves ACT-08, ACT-09, COM-10.

1. The user connects a calendar and picks the direction and activity types.
2. Activity changes are pushed to the calendar.
3. Calendar changes arrive by notification and update activities.
4. Private events are stored as busy time without details.
5. Conflicting edits resolve to the latest change.

### Data flows

#### SF-09 · Import pipeline

Triggered by an upload. Serves CRM-09, AIA-05, ENT-04.

1. The file is parsed and a column mapping is suggested.
2. The user confirms the mapping and the duplicate rule.
3. Rows are validated; capacity is checked.
4. Valid rows are written in batches, tagged with the import ID.
5. Rejected rows go to a skip file with reasons.
6. The import history records counts; a revert deletes or restores by import ID.

#### SF-10 · Duplicate detection and merge

Triggered by record creation and on demand. Serves CRM-11.

1. New people and organizations are compared with existing ones by the configured matching rules.
2. Matches are listed as suggestions.
3. On merge, the user picks surviving values.
4. Linked deals, activities, emails and files move to the survivor and the other record is soft-deleted.

#### SF-11 · Enrichment

Triggered by a user request, single or bulk. Serves PRO-04 to PRO-07.

1. Where a credit allowance is set, the balance is checked and a short balance refuses the request.
2. The provider adapter is called with name, domain or profile.
3. Returned values are mapped to fields.
4. Only empty fields are written, with source and date.
5. Credits are deducted and scoring is re-run for affected deals.
6. A provider error leaves the record unchanged and uses no credit.

#### SF-12 · Scoring

Triggered by a deal change or a model change. Serves PRO-03.

1. The active model for the deal's pipeline is loaded.
2. Each criterion is evaluated and its group's points are added.
3. The total is normalized to 0–100.
4. The score and the matched criteria are stored and a score-changed event is published.

#### SF-13 · Feed generation

Triggered by events and scheduled checks. Serves PRO-01, PRO-02.

1. Events such as a reply, an open, a click or a new deal create cards for the deal's owner.
2. Scheduled checks create cards for no reply after 5 days, no follow-up and overdue activities.
3. A card is resolved when its condition no longer holds or the user acts.
4. The daily counter is updated.

#### SF-14 · Report query

Triggered when a report or dashboard opens. Serves INS-01 to INS-10.

1. The report definition is turned into a query.
2. The query runs under the viewer's visibility, on live tables or rollups.
3. Results are cached per definition and data scope.
4. Related events invalidate the cache.
5. A public link runs with the owner's scope and nothing else.

#### SF-15 · Delete, restore and erasure

Triggered by a delete, a restore or a privacy request. Serves CRM-12, SEC-11.

1. A delete marks the row and records who, when and from where.
2. The item is listed for restore for 30 days.
3. A restore brings back the row and its links.
4. After 30 days a job removes it permanently.
5. An erasure request removes a person from every module at once and is logged.

#### SF-16 · Entitlements and metering

Triggered by any creation of a limited item. Serves ENT-01 to ENT-04, PIP-16.

1. If a limit is set, the counter for the item is compared with it; by default there is none.
2. Under the limit the creation proceeds and the counter rises.
3. At the limit a manual creation is refused with the reason.
4. An automated creation of a lead or deal goes to the waitlist instead.
5. The usage page reads the same counters.

### Channel flows

#### SF-17 · Lead capture from forms and chat

Triggered by a form submission or a finished chat. Serves LGN-01 to LGN-05, LEA-04.

1. The widget loads. If consent-gated loading is switched on, it loads only what consent allows. It never loads in the survey flow.
2. The submission is validated and checked for spam.
3. A contact and organization are found or created; source and any consent given are recorded. The admin's contact-form path, which also opens a ticket, is reused.
4. A lead or deal is created with answers, source and tracking data.
5. Assignment runs, the owner is notified and workflows fire.
6. A resubmission updates the existing record and keeps its owner.

#### SF-18 · Web visitor identification

Triggered by a page view on a tracked site. Serves WEB-01 to WEB-04.

1. The tracker sends page, referrer and network address.
2. The address is matched to a company through the data source.
3. Internet providers, crawlers and unmatched traffic are dropped.
4. The company's visit is stored and its monthly unique count and ranking are updated.
5. The visitor inbox refreshes hourly.

#### SF-19 · Campaign send

Triggered at the scheduled time. Serves CMP-03 to CMP-08.

1. The audience filter is resolved and reduced to subscribed addresses.
2. Each email is rendered with the recipient's data.
3. Messages go to the sending provider on the marketing stream.
4. Provider events return: delivered, bounced, opened, clicked, unsubscribed, complaint.
5. Events update the campaign figures and each address's status.
6. An unauthenticated domain or a suspended account blocks the send before step 3.

#### SF-20 · Document and signature

Triggered from a deal. Serves DOC-01 to DOC-06.

1. The template's placeholders are filled from the deal and the file is saved to the connected drive.
2. A share link is created; each open is logged and notified.
3. A signature request emails each signer a link and a one-time code.
4. Each signature is recorded with time and address.
5. When all have signed, the PDF is sealed with its audit trail and stored on the deal.
6. An event is published so workflows can react.

#### SF-21 · Meeting intelligence pipeline

Triggered by a calendar event or a manual recording. Serves MTG-01 to MTG-08.

1. Upcoming meetings are read from the calendar and linked to deals.
2. A brief is generated from the deal's history and stored before the meeting.
3. The bot joins or the desktop app captures audio.
4. Audio is transcribed with speakers and timestamps.
5. The AI gateway produces the recap and the proposed field changes.
6. The recap is saved as a note and announced.
7. Only approved changes are written. A failed transcription leaves the recording available for retry.

#### SF-22 · API request and rate limiting

Triggered by every API and connector call. Serves INT-01 to INT-03, MCP-01.

1. The token or OAuth grant is verified.
2. If rate limits are switched on, the burst limiter checks the rolling 2-second window for that token.
3. With rate limits on, the endpoint's token cost is deducted from the daily budget.
4. The permission check of SF-01 runs.
5. The handler responds with limit headers.
6. Over either limit the response is HTTP 429. Admins are emailed at 75% and 100% of the daily budget.

#### SF-23 · Webhook delivery

Triggered by an event with subscribers. Serves INT-04, AUT-07.

1. Subscriptions matching the action and object are found.
2. The payload is posted with a 10-second timeout.
3. On failure it is retried after 3, 30 and 150 seconds.
4. Ten first-attempt failures ban the webhook for 30 minutes.
5. Three days without a success delete it and notify its owner.

#### SF-24 · AI gateway call

Triggered by any AI feature. Serves AIA-01 to AIA-05, MTG, PRJ-06, INS-09.

1. The feature sends a request with the user and the records in scope.
2. Context is retrieved under the user's permissions, and never from survey response tables.
3. The prompt is assembled and sent to the model provider under a no-training agreement.
4. The output is validated against the expected structure.
5. The call is logged with feature, user and cost.
6. An invalid output is retried once, then returned as an error.

### Flows added in the quality review

#### SF-25 · Search

Triggered by a query. Serves PIP-12.

1. Each write updates a search index with the record's name, emails, phones and text fields.
2. A query is matched against the index.
3. Results are filtered by the user's role and visibility.
4. Results are ranked and grouped by record type.
5. Survey data is never indexed.

#### SF-26 · Scheduled checks

Triggered on a schedule. Serves PIP-05, AUT-03, INS-05, PRO-01.

1. A scheduler starts each check at its interval.
2. The rotting check flags deals idle past their stage threshold and notifies owners.
3. The date-trigger check starts workflows whose date condition is met.
4. The goal check recomputes progress.
5. The feed check creates no-reply and no-follow-up cards.
6. Each check records its run; a failed run raises an alert.

#### SF-27 · Sign-in and security events

Triggered by a login. Serves SEC-01 to SEC-06.

1. The user signs in with a password or single sign-on.
2. The second factor is checked; it is mandatory in the admin.
3. Security rules are applied: IP allowlist, time window, password age.
4. The login is written to the login log with device and location.
5. A new device or location, or repeated failures, sends an alert.
6. The security dashboard reads the same log.

#### SF-28 · Calls and messages

Triggered by a call or an incoming message. Serves COM-12, COM-13, MOB-04.

1. A click-to-call request goes to the telephony adapter.
2. The provider reports the result, and an activity is written with outcome, duration and recording link.
3. An incoming number is matched to a contact.
4. An incoming message is stored on its thread, linked to the contact's open deal and notified to the owner.
5. An unmatched number or sender is listed for manual linking.

#### SF-29 · Contact sync

Triggered by a change on either side. Serves CRM-04.

1. The user connects an address book and chooses what syncs.
2. Records are matched by email address.
3. A change on one side updates the other.
4. A new external contact is imported. If the contact-rule setting is on, it must pass that rule first.

#### SF-30 · Live chat routing

Triggered when a visitor asks for a person. Serves LGN-02.

1. The chat enters the unassigned queue and online reps are notified.
2. The first rep to claim it gets the conversation, which is then locked to that rep.
3. If nobody claims it within the waiting time, the bot continues.
4. Messages are delivered in real time in both directions.
5. The transcript is saved on the lead.

#### SF-31 · Mobile offline sync

Triggered when a device reconnects. Serves MOB-05.

1. Offline changes are queued on the device with their time.
2. On reconnecting they are sent in order.
3. Each is applied if the record has not changed since; otherwise the latest change wins and the earlier value stays in the changelog.
4. The device then pulls changes made elsewhere.

#### SF-32 · Derived values

Triggered by a change to an input. Serves CRM-07, CRM-08, CUS-04, CUS-06, PIP-15.

1. A product line change recalculates the deal value.
2. A schedule change recalculates MRR, ARR, ACV and TCV.
3. A change to a formula input recalculates the formula field.
4. Reports convert amounts with the stored exchange rate.
5. A stage change closes the time in the previous stage and opens the next.

#### SF-33 · Files

Triggered by an upload. Serves CRM-05, DOC-03, MOB-06.

1. The file is uploaded to storage under the record's access rules.
2. A file row links it to the record and its history.
3. A download is allowed only if the user may see the record.
4. Deleting the record soft-deletes its files with it.

#### SF-34 · Rule settings

Triggered whenever a feature with an optional rule runs. Serves CUS-07, ENT-01, ENT-02.

1. The feature asks the settings registry for the rules that apply to it.
2. With default settings no rule applies and the action proceeds.
3. If a rule is on, it is evaluated and returns allow, warn or block.
4. A block names the setting that caused it.
5. Every change to a setting is logged.
6. The anonymity firewall is not in the registry and cannot be switched off.

### Flows added in the team review

#### SF-35 · Deal lifecycle

Triggered when a deal is created, moved, closed, archived, duplicated or restored. Serves PIP-01, PIP-02, PIP-03, PIP-06, PIP-07, PIP-11, PIP-13, PIP-14, PIP-17.

1. A deal is created in a pipeline and stage with its owner; field quality rules are checked.
2. A stage move, or a date change in the forecast view, is saved optimistically, written to the stage history and published as an event.
3. Deleting a stage moves its deals to the chosen target stage.
4. Closing as won or lost stores the status and the lost reason.
5. Archiving removes the deal from active views; unarchiving returns it.
6. A duplicate copies fields and products; a restore returns a deleted deal to its former stage.

#### SF-36 · Activity lifecycle

Triggered when an activity is created, changed or completed. Serves ACT-01, ACT-02, ACT-03, ACT-05, ACT-06, ACT-07.

1. An activity is created with its type, owner, time and linked record; a bulk request creates one per selected record.
2. Custom activity types and fields come from the registry.
3. A reschedule in the calendar updates the activity and any synced event.
4. Completing it stamps time and user and publishes an event.
5. If the deal then has no open activity, the next-step prompt is shown and the card gets the warning icon.

#### SF-37 · Records, links and list operations

Triggered by changes to people, organizations and their links, and by list actions. Serves CRM-01, CRM-02, CRM-03, CRM-10, CRM-13, CRM-14, CRM-15, PIP-08, PIP-09, PIP-10.

1. A person or organization is created or updated on the admin's contact and organization records, with its source stored.
2. Labels, related organizations, participants and followers are stored as links; a follower is notified of changes.
3. A new address is geocoded once for the map.
4. The timeline is built from the record's activities and messages.
5. A bulk edit writes one changelog entry per record; a bulk delete shows a preview first.
6. An export writes the visible rows and columns to a file and is logged.

#### SF-38 · Field and configuration registry

Triggered when an admin changes configuration, and read by every screen. Serves CUS-01, CUS-02, CUS-05, CUS-08.

1. A field, quality rule or translation is saved as a versioned row.
2. Forms, filters, reports, import and the API read the registry, so the change appears without a deploy.
3. Quality rules are evaluated on save and on stage moves.
4. Interface text is served from the translation catalog in the user's language.
5. The demo tenant has its own configuration and sample data, kept apart from live data.

#### SF-39 · Campaign authoring and insights

Triggered when a marketer builds a campaign or opens its reports. Serves CMP-01, CMP-02, CMP-09.

1. The builder saves the design as rows and blocks; the footer is added automatically.
2. A design is saved to or loaded from the template store.
3. A test send and the desktop and mobile previews render the same output as the final send.
4. Provider events are rolled up per campaign.
5. Insights reads the rollups for performance, conversion and comparison reports.

#### SF-40 · Video links and mail client add-ons

Triggered when a meeting is scheduled or an add-on calls the API. Serves COM-11, COM-14.

1. Scheduling a meeting asks the connected video provider for a link and stores it on the activity and the invite.
2. If the provider fails, the activity is saved without a link and the user is told.
3. The mail client add-on signs in as the user and calls the same API as the web app.
4. Records created in the add-on carry the add-on as their source.

#### SF-41 · Connectors, app platform and AI connector tools

Triggered when a connector or app is installed, used or removed. Serves INT-05 to INT-11, AIA-06, MCP-02, MCP-03.

1. The user or admin installs a connector from the catalog and grants its scopes through OAuth.
2. The connector's status and error rate are reported to the admin's integrations status.
3. Deal events are posted to team chat; an invoice request goes to the accounting adapter and its status comes back.
4. Extension panels load in a sandbox with only the data their scopes allow.
5. AI connector tools are generated from the API definitions; the company switch blocks all of them at once.
6. Removing a connector revokes its grants.

#### SF-42 · Project lifecycle

Triggered when a project is created, planned or progressed. Serves PRJ-01 to PRJ-05, PRJ-07, PRJ-08, PRJ-09.

1. A project is created from a won deal or from scratch, optionally from a template whose dates are set from the start date.
2. Tasks, subtasks, milestones and activities are added one by one, pasted in bulk or imported.
3. A dependency is saved unless it would form a cycle.
4. Dragging a phase on the timeline shifts its items and keeps their spacing.
5. A phase change publishes an event for workflows and reports.
6. Notes, files, mentions and emails attach to the project; a status report is produced as a PDF.

#### SF-43 · User administration and data protection

Triggered by user changes and on a backup schedule. Serves SEC-09, SEC-10.

1. An admin invites a user and assigns role, team and visibility group.
2. Deactivating a user ends their sessions, prompts a transfer of owned workflows and reassigns records if chosen.
3. Access settings can be copied from another user.
4. Backups run on schedule and the last success is recorded.
5. A restore test is run and its result recorded against the recovery targets.

#### SF-44 · Mobile client

Triggered when the mobile app opens. Serves MOB-01, MOB-02, MOB-03, MOB-08, AIA-07.

1. The app signs in and loads the focus view from the same API as the web app.
2. Changes arrive in real time while the app is open.
3. Nearby asks for location permission and queries records by distance.
4. A scanned business card is read on the device and shown as a contact draft for review.
5. Live chat takeover, project tasks and the statistics dashboard use the same endpoints as the web app.

#### SF-45 · Lead lifecycle

Triggered when a lead is created, worked or converted. Serves LEA-01, LEA-02, LEA-03, LEA-05, LEA-06.

1. A lead is created with its source and linked to a person or organization.
2. Labels and owner are set, by hand or by assignment rule.
3. Emails and messages on the lead are stored on it; a message from a connected channel arrives in the messaging inbox.
4. Converting to a deal creates the deal in the chosen pipeline and stage and moves notes, activities, emails and files.
5. Converting back returns the record to the leads inbox with its history.
6. Archiving removes the lead from the inbox without deleting it.

---

## Part F — Data model and API

### Entities and relationships

The model adds tables around the Orgpuls admin's organization and contact records, its staff roles and its typed events table; those are extended, never duplicated. Table names are proposals and must be aligned with the admin's schema. Person means the admin's contact.

Conventions for every table:

- A product ID on every row. Access only through the admin's role checks, never by bypassing row-level security. No foreign key or grant from any CRM table to survey response tables.
- Owner, visibility, created, updated and deleted columns on every business record.
- Custom field values in a JSON column keyed by field ID, with an index for each filterable field; definitions in `custom_field`.
- Configuration as versioned rows: pipelines, workflows, sequences, reports, templates, scoring models, permission sets.
- Soft delete for 30 days, then permanent removal.
- Each change writes the row, a changelog entry and an event in one transaction. A read of customer-scoped data writes an audit row. A version column on each record guards against lost updates.

| Domain | Entities | Key relationships |
| --- | --- | --- |
| Identity (existing) | platform admin with role and MFA, audit log, team, team_member, visibility_group, permission_set | Staff identities are separate from customer logins; an admin role is never derived from a customer role |
| Records (existing, extended) | organization (org.nr, product ID), contact (type, role, source, consent basis), suppression list, organization_relation, label, follower | A person belongs to at most one organization; organizations relate as parent, daughter or related |
| Sales | pipeline, stage, deal, deal_participant, deal_stage_history, lead, lost_reason, saved_filter | A deal sits in one stage of one pipeline and links one person and one organization; a lead converts to a deal and back |
| Products | product, product_price, deal_product, revenue_schedule, currency, exchange_rate | A deal has many product lines; a line can carry a recurring or installment schedule |
| Activities | activity, activity_type, activity_guest | An activity links to one deal, lead, person, organization or project |
| History | note, comment, file, mention, changelog | Each attaches to exactly one record |
| Email | mail_account, mail_thread, mail_message, mail_link, mail_event, mail_template, signature | A thread links to any number of records through mail_link; events record opens and clicks |
| Scheduling, calls, messaging | availability, booking_link, booking, call_log, message_thread, message | A booking creates an activity; a call log is an activity with call fields |
| Automation | workflow, workflow_version, workflow_run, workflow_step_run, assignment_rule, assignment_log, sequence, sequence_step, enrollment | A run belongs to one workflow version and one trigger record; an enrollment links one lead or deal to one sequence |
| Insights | report, dashboard, dashboard_item, goal, public_link, rollup tables | A dashboard holds many reports; a goal targets a user, team or company |
| Prospecting | score_model, score_criterion, deal_score, feed_card, enrichment_request, credit_ledger | One active score model per pipeline; a feed card belongs to one user and one deal |
| Marketing | consent record and suppression list (existing), segment (existing), campaign, campaign_recipient, campaign_event, sender_domain | Sending status is derived from the consent record and the suppression list |
| Projects | board, phase, project, project_deal, task, milestone, dependency, project_template | A project sits in one phase of one board and links to deals; a task may have a parent task |
| Lead generation | chatbot_playbook, chat_conversation, chat_message, web_form, form_submission | A conversation or submission creates one lead or deal |
| Web visitors | tracked_site, visitor_company, visit | A visitor company may match one organization |
| Documents | document_template, document, document_link, signature_request, signer, signature_event | A document belongs to one deal or contact; a request has up to 10 signers |
| Meetings | meeting, recording, transcript, brief, recap, update_suggestion | A meeting links to one activity and optionally one deal |
| Platform | custom_field, translation, setting, import_job, waitlist_item, integration, installed_app, device_token, event, notification, webhook, webhook_delivery, api_token, oauth_app, oauth_grant, entitlement, usage_counter, login_log, security_rule | Events feed workflows, webhooks, rollups and notifications |

### Event catalog

The admin's single typed events table is the catalog. CRM events are added to it with the same object_action naming, and its product events become workflow triggers and scoring signals.

| Family | Events | Main consumers |
| --- | --- | --- |
| Deal | added, updated, stage_changed, won, lost, archived, deleted, restored | Workflows, assignment, scoring, feed, rollups, webhooks |
| Lead | added, updated, converted, archived, deleted | Workflows, assignment, feed, webhooks |
| Person, organization | added, updated, merged, deleted | Workflows, enrichment, webhooks |
| Activity | added, updated, completed, deleted | Workflows, feed, rollups, notifications |
| Email | received, sent, opened, link_clicked, replied, send_failed | Feed, sequences, workflows, notifications |
| Project, task | added, updated, phase_changed, completed | Workflows, rollups |
| Capture | form_submitted, chat_completed, visitor_identified | Lead creation, assignment |
| Campaign | sent, delivered, bounced, unsubscribed, complained | Marketing status, rollups |
| Document | generated, opened, signed, completed | Workflows, notifications |
| Meeting | scheduled, recorded, recap_ready, updates_approved | Notifications, workflows |
| Security | login, login_failed, user_invited, password_reset_requested, export_run | Security alerts, dashboard |
| Usage | limit_warning, limit_reached | Notifications, usage page |
| Product (existing) | signup, trial day, conversion, churn, payment status, organization-level survey aggregates | Workflows, scoring, feed, health score |

### API surface

The public API mirrors the interface: anything a user can do to a record, an integration can do with the same permissions.

| Area | Specification |
| --- | --- |
| Resources | deals, leads, persons, organizations, activities, products, pipelines, stages, notes, files, projects, tasks, users, fields, filters, webhooks, search, plus labels, activity types, currencies, organization relations, participants, followers, product lines and revenue schedules, mail threads, call logs, goals, permission sets and settings |
| Operations | list, get, create, update, delete, search; convert lead to deal; merge |
| Conventions | Versioned paths, cursor pagination, field selection, custom fields addressed by key, idempotency keys on create |
| Authentication | Personal token in a header, one active per user; OAuth 2.0 with scopes per resource for apps |
| Rate limits | Daily token budget per company and a burst limit per token in a rolling 2-second window; off by default (CUS-07) |
| Reference values from the source | Budget: 30,000 base tokens × plan multiplier (1, 2, 5, 7) × seats. Costs: get one 2, list 20, update 10, delete 6, delete list 10, search 40. Burst per 2 seconds: 20 to 120 for tokens, 80 to 480 for OAuth apps, 10 for search |
| Webhooks | Actions create, change, delete on any object; JSON body with current and previous state; retry and ban policy as in INT-04 |
| AI connector | Tools generated from the same API definitions (MCP-02) |

Your own values for the limits are an open decision; the source's are listed only as a starting point.

---

## Part G — Feature map, architecture, phases, non-functional requirements and open points

This part was written without access to the code. Where it says the existing implementation is not assessed, Phase A (section A3) replaces that with the measured gap, and Phase B (section A4) re-derives the phase contents, order and sizes from it. The exit gates stay as written: each phase closes only when the flows it names pass.

### Feature map

_Diagram in the source document: feature map · 21 modules in 6 layers. The table that follows carries the same content._

Each layer uses the ones below it: the sales core extends the admin's organizations and contacts, and every other module attaches to deals, leads or activities.

| Module | ID prefix | Features | Layer | Depends on |
| --- | --- | --- | --- | --- |
| Pipeline and deals | PIP | 17 | Sales core | Existing CRM, SEC, CUS |
| Activities | ACT | 9 | Sales core | PIP, calendar providers |
| CRM records | CRM | 15 | Sales core | Existing CRM |
| Customization | CUS | 8 | Sales core | Existing CRM, SEC |
| Leads | LEA | 6 | Sales core | CRM, PIP |
| Email and communications | COM | 14 | Engagement | CRM, ACT, email and calendar providers |
| Automation | AUT | 12 | Engagement | Event catalog, COM, PIP |
| Insights and reports | INS | 10 | Intelligence | PIP, ACT, LEA |
| Prospecting | PRO | 7 | Intelligence | PIP, COM, data providers |
| AI assistant | AIA | 7 | Intelligence | INS, COM, language model |
| Lead generation | LGN | 5 | Growth modules | LEA, AUT, COM |
| Web visitors | WEB | 4 | Growth modules | LEA, CRM, IP-to-company data |
| Email marketing | CMP | 9 | Growth modules | Consent, sending provider, AUT |
| Documents and e-sign | DOC | 6 | Growth modules | PIP, product catalog, cloud storage |
| Projects | PRJ | 9 | Growth modules | PIP, ACT, AUT |
| Meeting intelligence | MTG | 8 | Growth modules | ACT, COM, transcription, language model |
| Security and permissions | SEC | 11 | Platform services | Existing CRM identity |
| Plans and entitlements | ENT | 4 | Platform services | SEC, billing |
| Integrations and API | INT | 11 | Channels | SEC, ENT, event catalog |
| AI connector (MCP) | MCP | 3 | Channels | INT, SEC |
| Mobile app | MOB | 8 | Channels | INT, PIP, ACT, CRM |

The 183 features are specified one per row in the Feature specifications tab.

### Architecture

_Diagram in the source document: architecture · 4 layers, one API entry point. The table that follows carries the same content._

Read top to bottom: every client calls the same API, which checks permissions and limits before touching data; background workers react to events and call external services through adapters.

| Design choice | What it means | Why |
| --- | --- | --- |
| One API for every client | Web, mobile, widgets, integrations and AI assistants use the same endpoints and checks | A rule enforced once holds everywhere (SF-01, SF-22) |
| Configuration as data | Fields, pipelines, workflows, sequences, reports, templates, scoring models and permission sets are rows read by a registry | New fields and workflows need no deploy; the API and AI tools are generated from the same definitions |
| Outbox events | Each change writes its event in the same transaction; a dispatcher delivers it | Workflows, webhooks, feed, rollups and notifications never miss or double-handle a change (SF-02) |
| One workflow engine | Workflows, sequences, assignment rules and date triggers run on the admin's lifecycle-messaging engine, extended, not on a new one | One place for delays, retries, history and loop protection (SF-04 to SF-06) |
| Adapters for providers | Each external service sits behind an interface | Providers can be swapped per market or cost (open point 2) |
| AI gateway | All model calls pass one service | Permission-scoped context, logging and approval rules in one place (SF-24) |

### Delivery plan

The build runs in nine phases ordered by dependency, each closed by a gate that names the user flows that must pass. Sizes are relative engineering estimates for a new build on the stated stack and cover the full implementation. What is already built in the admin is not assessed and will shorten the work. The plan depends on the admin's sign-in, roles, audit log, CRM basics and sequences; anything not yet built there is part of this plan.

| Phase | Modules | Relative size | Exit gate |
| --- | --- | --- | --- |
| 0 · Foundations | Alignment with the admin: organization and contact extensions, registry for fields and configuration, CRM events in the typed events table, changelog and read audit, role checks, soft delete, job runtime | L | A custom field works end to end on existing organizations and contacts; SF-01, SF-02, SF-34, SF-38 |
| 1 · Sales core | PIP, ACT, CRM, CUS, LEA | PIP L, ACT M, CRM L, CUS M, LEA S | UF-01, UF-02, UF-09, UF-10, UF-23, UF-24, UF-29; SF-07, SF-09, SF-10, SF-15, SF-25, SF-26, SF-32, SF-33, SF-35, SF-36, SF-37, SF-45 |
| 2 · Engagement | COM, plus the provider connections for ACT-08, ACT-09 and CRM-04 | XL | UF-04, UF-06, UF-25; SF-03, SF-08, SF-28, SF-29, SF-40 |
| 3 · Automation | AUT, as an extension of the lifecycle-messaging engine | XL | UF-05, UF-11, UF-12; SF-04, SF-05, SF-06 |
| 4 · Insight | INS, PRO | INS L, PRO L | UF-03, UF-13, UF-14, UF-26; SF-11, SF-12, SF-13, SF-14 |
| 5 · Capture and close | LGN, WEB, DOC | LGN L, WEB M, DOC L | UF-08, UF-18, UF-19; SF-17, SF-18, SF-20, SF-30 |
| 6 · Market and deliver | CMP, PRJ | CMP L, PRJ L | UF-17, UF-20; SF-19, SF-39, SF-42 |
| 7 · AI | AIA, MTG | AIA M, MTG XL | UF-07, UF-27; SF-21, SF-24 |
| 8 · Platform and channels | INT, MCP, SEC, MOB, ENT | INT L, MCP S, SEC L, MOB XL, ENT M | UF-15, UF-16, UF-21, UF-22, UF-28; SF-16, SF-22, SF-23, SF-27, SF-31, SF-41, SF-43, SF-44 |

Size scale: S up to 3 person-weeks, M 3 to 8, L 8 to 16, XL more than 16. Counting S as 1 week, M as 3, L as 8 and XL as 16, the low end of each size, the plan adds up to at least 169 person-weeks, more than three person-years, and the four XL modules (COM, AUT, MTG, MOB) have no upper bound. These are sizes for a conventional team; with AI-assisted development, measure the real pace in phase 0 and re-size from that.

How the team works:

- An internal API and the event catalog exist from phase 0, so every later module is built API-first; phase 8 only hardens and publishes it.
- Each specification's acceptance criterion becomes an automated test, and each user and system flow an end-to-end test. A phase closes only when its gate flows pass.
- Quality gates on every merge: type check, lint, unit tests, and security tests proving that no CRM function can read survey responses and that each staff role sees only what it may.
- Each phase ends with a stop for your review before the next starts.
- Roles needed: product owner, tech lead, full-stack engineers, an integrations engineer for mail, calendar and telephony, a data engineer for reporting, an AI engineer, mobile engineers, a designer, QA, and security and privacy review.

Phases 5 to 7 are independent of each other after phase 4 and can be reordered by business priority.

Some features are started in one phase and finished in a later one, because a part of them needs something built later:

| Feature | Started in phase | Finished in phase | What it waits for |
| --- | --- | --- | --- |
| CRM-09 import with AI mapping (AIA-05) | 1 | 7 | The AI gateway; mapping is manual until then |
| ACT-08 and ACT-09 calendar sync and invites, CRM-04 contact sync | 1 | 2 | Provider connections |
| AUT-07 actions for team chat, task tools, campaigns and projects | 3 | 6 and 8 | Each action arrives with its module or connector |
| INS-09 AI report generation; PRJ-02, PRJ-06, PRJ-07 AI brief, summary and report | 4 and 6 | 7 | The AI gateway |
| COM-12 caller ID and web-to-mobile, AIA-07 card scanner, MTG-04 chat notice | 2 and 7 | 8 | The mobile app or the chat connector |

The AI connector (MCP) is built in phase 8, not with the other AI features, because it needs OAuth and rate limits from INT.

### Non-functional requirements

These apply to every module. Where the source product publishes a figure it is given as a reference; your own targets are open decisions.

| Area | Requirement | Reference or status |
| --- | --- | --- |
| Anonymity firewall | No CRM function, report, search, export, AI call or connector can reach survey responses; survey data appears only as organization-level aggregates of at least 5 answers | Hard rule of the admin specification; proven by automated tests |
| Rule settings | Contact rules, consent checks on sales email, tracking, approvals and limits are settings, each unrestricted by default | Your decision of 3 October; CUS-07 |
| Access | Staff roles from the admin's role model, mandatory MFA, least privilege per role, a product ID on every table | Admin specification, Access model |
| Audit | Every write, and every read of customer-scoped data, logged with who, what and when; a typed reason is a setting, off by default; run histories for workflows, imports, webhooks and AI calls | Admin specification; PIP-04, AUT-09 |
| Data residency | Database, storage, logs, AI processing and sub-processors in the EU | Admin specification |
| Sending | Marketing and transactional streams stay separate; consent and suppression checks on sales email are a setting, off by default | Admin specification; CMP-04 |
| Job runtime | Long-running work (mail sync, delays, meeting capture, imports) runs on durable queues and scheduled jobs, not in request handlers; edge functions have a wall-clock limit | To decide: database queues and cron, or a separate worker |
| Recovery | Stated recovery point and recovery time, proven by restore tests | Source: 1 hour and 2 hours. Your targets: to decide |
| Scale | Size for an internal back-office first; the source's ceilings are a reference only | Source: 300,000 active leads and deals per company; 10,000 workflow runs per 10 minutes |
| Performance | Response targets for pipeline load, search, report queries and mail sync delay | To decide |
| Monitoring | Alerts on failed jobs, sync lag, send failures and error rates, shown in the admin's job monitor | The admin specification lists a job monitor |
| AI governance | No training on customer data, context limited by role and by the anonymity firewall, human approval before any write, every call logged | SF-24 |
| Privacy | Erasure across all modules, recording consent, sub-processor list | SEC-11, MTG-08 |
| Destructive actions | Preview and soft delete for bulk deletes and merges; second-admin approval is a setting, off by default | Admin specification, Best practices |
| Interface language | English | Default decided in the admin specification; more languages through the catalog |
| Test data | Development and tests run against the seeded demo tenant, never customer data | Admin specification |
| Provider independence | Every third-party service behind an adapter | Mail, calendar, sending, telephony, transcription, language model, data providers, e-signature |

### Risks and open decisions

Four decisions were settled on 3 October. Ten points remain open or carry risk.

| Decided on 3 October | Your answer |
| --- | --- |
| Scope | All 183 features are built |
| Rules and limits | Every restriction is a setting that defaults to fully working and unrestricted; contact rules are part of settings |
| Existing code | The admin's CRM is partly built. It is not assessed, and the plan specifies the full implementation |
| Size | Not decided separately. You chose the full scope, which the plan sizes at 169 person-weeks or more |

| # | Open point or risk | Why it matters | What is needed |
| --- | --- | --- | --- |
| 1 | One engine | Workflows, sequences and assignment must extend the lifecycle-messaging engine, not sit beside it | That engine's design confirmed before phase 3 |
| 2 | Build or buy for providers | Mail sync, meeting capture and transcription, company and contact data, e-signature evidence and telephony are costly to build. Which accounting system INT-08 supports first belongs to the same choice | A choice per service; the plan assumes buy behind adapters |
| 3 | Job runtime | Mail sync and meeting capture do not fit short-lived functions | Database queues and cron, or a separate worker service |
| 4 | Legal exposure of the defaults | With every rule off by default, compliance with consent, tracking, prospect-data and recording law depends on how the system is configured and used in each market | The settings each market needs switched on, and a legal review of the defaults before go-live |
| 5 | Recording consent and signature level | Recording law and contract needs vary | A consent policy for MTG and the signature level you need |
| 6 | Items the source leaves undefined | The LinkedIn connector in LEA-06 is visible only in a screenshot. The source has no native recurring activities, and an activity links to one deal only | A definition of the connector, and whether to go beyond the source on the other two |
| 7 | Three inventory rows outside the 183 | Named migration sources, the Mailchimp migrator and partnership discounts were not carried over | Say if they should be added |
| 8 | Targets and running costs | Performance and recovery targets are not set. Language models, transcription and enrichment are usage-priced | Your targets, and a cost model before phase 7 |
| 9 | Originality | Only functions are replicated; names, interface design and text must be your own | Neutral names throughout |
| 10 | Staff roles | The admin specification defines four roles: super-admin, support, finance and read-only analyst. The plan's actors (sales rep, manager, marketer, project manager) have no role there | The roles or permission sets SEC-07 should add |

---

## Part H — Coverage: every researched feature mapped to a specification

### Result

All 276 feature rows of the Pipedrive inventory are accounted for: 273 map to a specification ID and 3 are deliberately not carried over. The check found four gaps in the first draft of the specifications, and all four are now closed. The team review counted all 21 inventory tables from the full text (274 rows) and then added two rows found by scanning every Knowledge Base article, which makes 276.

| Check | Result |
| --- | --- |
| Inventory rows mapped to a specification | 273 of 276 |
| Inventory rows not carried over | 3: named migration sources, the Mailchimp migrator, partnership discounts |
| Specifications written | 183 in 21 modules; module counts match the feature map |
| Modules covered by at least one user flow | 21 of 21, across 29 user flows. All 183 specifications are referenced |
| Modules covered by at least one system flow | 21 of 21, across 45 system flows. All 183 specifications are served |
| Specifications marked optional until scoped | None. All 183 are in scope, as decided on 3 October; the LinkedIn connector in LEA-06 still needs its functions defined |

### Gaps found and closed in this check

| Gap | Fix |
| --- | --- |
| Global search was in no specification | Added to PIP-12 |
| Mobile landscape layout, phone contact import and manual sync were missing | Added to MOB-01 and MOB-05 |
| The progress panel shown with AI notifications was missing | Added to AIA-02 |
| INS-01 counted 16 report types; the inventory has 17 | Corrected, with both forecast reports named |
| 42 specifications were in no user flow and 26 of them in no flow at all (found in the quality review) | Six user flows (UF-23 to UF-28) and nine system flows (SF-25 to SF-33) added |
| INS-01 did not name the pipeline metrics; two inventory rows were mapped too narrowly (found in the quality review) | Measures added to INS-01; the Notifications and ChatGPT app mappings corrected |
| 64 specifications were served by no system flow, and the delivery plan cited eleven system flows that did not exist (found in the team review) | SF-35 to SF-45 written; every specification is now served by a system flow |
| Two features were found only by scanning all 562 Knowledge Base articles: duplicating reports, goals and dashboards, and sample data (found in the team review) | Added to the inventory, to INS-03 and to CUS-08 |

### Mapping by inventory section

Each inventory row is followed by the specification that covers it.

**Automation**

- **Rows:** 17
- **Inventory row → specification:** Automations → AUT-01, AUT-02 · Date triggers → AUT-03 · Conditions → AUT-04 · Delay and wait-for → AUT-05 · If/else → AUT-06 · Automated emails → AUT-07 · Templates → AUT-08 · Slack and Teams notifications → AUT-07, INT-07 · Webhook action → AUT-07 · Dashboard → AUT-09 · History, sharing, ownership → AUT-09, AUT-10 · Frequency limits → AUT-09 · Automatic assignment → AUT-11 · Sequences → AUT-12 · Webhooks → INT-04 · API access → INT-01 to INT-03 · Bulk activity → ACT-06

**CRM**

- **Rows:** 16
- **Inventory row → specification:** People and organizations → CRM-01 · Contacts timeline → CRM-02 · Contacts map → CRM-03 · Contact sync → CRM-04 · File attachments → CRM-05 · Mentions and comments → CRM-06 · Products catalog → CRM-07 · Subscriptions and installments → CRM-08 · Data import → CRM-09 · Named migration sources → not carried · Data export → CRM-10 · Merge duplicates → CRM-11 · Capacity → ENT-02, PIP-16 · Data enrichment → PRO-04, PRO-05 · Restore data → CRM-12 · Related organizations → CRM-13

**Customization**

- **Rows:** 16
- **Inventory row → specification:** Pipelines → PIP-02 · Deal cards → PIP-14 · Custom fields → CUS-01 · Field descriptions, important, required → CUS-02 · Formula fields → CUS-04 · Pipeline-specific fields → CUS-03 · Custom activity types → ACT-02 · Languages → CUS-05 · Multi-currency → CUS-06 · Feature switches → CUS-07 · Custom reports and dashboards → INS-03, INS-07 · Permission sets and visibility groups → SEC-07, SEC-08 · Sandbox → CUS-08 · Sample data and tailored setup → CUS-08

**Email and communications**

- **Rows:** 19
- **Inventory row → specification:** Smart Bcc inbox → COM-01 · Two-way sync → COM-02 · Multiple accounts → COM-03 · Team inbox → COM-04 · Templates and signatures, merge fields → COM-05 · Tracking → COM-06 · Group emailing → COM-07 · Scheduling → COM-08 · Meeting scheduler, availability links → COM-10 · Video call scheduling → COM-11 · Calendar view → ACT-03, ACT-09 · Reminder alerts → ACT-04 · Calling, web-to-mobile, logging, caller ID → COM-12, MOB-04 · WhatsApp → COM-13 · Gmail extension → COM-14 · Email labels → COM-09

**Insights and reports**

- **Rows:** 20
- **Inventory row → specification:** Deal, activity, lead, contact, campaign and project reports → INS-01 · Revenue forecast reports → INS-06 · Forecast view → PIP-11 · Custom field reports → INS-07 · Chart types → INS-02 · AI report creation → INS-09 · Dashboards → INS-03 · Shareable links, report and dashboard collaboration → INS-04 · Company and user goals, team goals → INS-05 · Export → INS-08 · Report capacity → INS-10 · Duplicating reports, goals and dashboards → INS-03

**Integrations**

- **Rows:** 17
- **Inventory row → specification:** Google Workspace → INT-05 · Gmail add-on and extension → COM-14 · Microsoft → INT-06 · Slack → INT-07 · Named app integrations → INT-09, INT-11 · Invoicing → INT-08 · App panels → INT-10 · AI search and recommendations → AIA-06 · REST API, token costs, burst limits → INT-01 to INT-03 · Developer platform → INT-02, INT-10 · Webhooks → INT-04 · ChatGPT app → MCP-01 · MCP → MCP-01 to MCP-03 · Sandbox → CUS-08 · Partnership discounts → not carried

**Leads**

- **Rows:** 13
- **Inventory row → specification:** Leads Inbox → LEA-01 · Conversion → LEA-03 · Labels → LEA-02 · Import → LEA-04 · Lead email → LEA-05 · Lead reports → INS-01 · Lead capture → LGN-01 to LGN-03 · Outbound search → LGN-04 · Routing → AUT-11 · Scoring and enrichment → PRO-03 to PRO-05 · Leads on mobile → MOB-01 · Messaging inbox and LinkedIn → LEA-06 · Lead source fields → CRM-15

**Prospecting**

- **Rows:** 10
- **Inventory row → specification:** Feed → PRO-01 · Feed cards and side panel → PRO-02 · Custom scoring → PRO-03 · Firmographic enrichment → PRO-04 · Email and phone enrichment → PRO-05 · Bulk enrichment, credits → PRO-06 · Sequences → AUT-12 · Prospector → LGN-04 · Reverse email lookup → PRO-07

**Processes, pipeline and activities**

- **Rows:** 18
- **Inventory row → specification:** Visual pipeline → PIP-01 · Deal management → PIP-03, PIP-04 · Rotting → PIP-05 · Labels → PIP-06 · Lost reasons → PIP-07 · Participants → PIP-08 · Followers → PIP-09 · Views → PIP-10, PIP-11, PIP-13 · Filters → PIP-12 · Archive → PIP-13 · Waitlist → PIP-16 · Activities → ACT-01, ACT-02 · Priority labels → ACT-05 · Reminders → ACT-04, ACT-07 · Recurring activities (gap) → ACT-09 · Manager view → ACT-03, SEC-09 · Pipeline metrics → INS-01 · Activity invites → ACT-08

**AI CRM features**

- **Rows:** 20
- **Inventory row → specification:** Sales Assistant → AIA-01 · AI notifications → AIA-02 · Notifications → ACT-04, ACT-07, COM-06, CRM-06 · AI email creation → AIA-03 · Summarization, suggested replies → AIA-04 · AI report creation → INS-09 · Import assistant → AIA-05 · AI search and recommendations → AIA-06 · Card scanner → AIA-07 · Pre-call briefs → MTG-01 · Notetaker → MTG-02 · Companion app → MTG-03, MTG-07 · Recording, summary, transcript → MTG-04 · CRM data sync → MTG-05 · Transcript upload → MTG-06 · Controls, connections → MTG-08 · MCP server → MCP-01, MCP-03 · MCP tools → MCP-02

**Email marketing**

- **Rows:** 15
- **Inventory row → specification:** Builder → CMP-01 · Templates → CMP-02 · Segmentation → CMP-03 · Marketing status, double opt-in → CMP-04 · Scheduling → CMP-05 · Analytics, engagement notifications → CMP-06 · Insights, comparison, campaign-type filter → CMP-09 · Marketing automation → CMP-07 · Deliverability → CMP-08 · Security and permissions → SEC-06, SEC-07 · Mailchimp migration → not carried

**Projects**

- **Rows:** 19
- **Inventory row → specification:** Boards and phases → PRJ-01 · Links, AI brief → PRJ-02 · Tasks, subtasks, milestones, activities → PRJ-03 · Dependencies, Gantt → PRJ-04 · Bulk entry, import and export → PRJ-08 · Templates → PRJ-05 · Health, AI summary → PRJ-06 · Collaboration, external sharing → PRJ-07 · Customization → CUS-01, PIP-12 · Automation, reports → PRJ-09 · Mobile → MOB-08

**Lead generation**

- **Rows:** 9
- **Inventory row → specification:** Chatbot, routing, booking, analytics → LGN-01 · Live chat → LGN-02 · Web forms, routing, performance → LGN-03 · Prospector → LGN-04

**Web visitors**

- **Rows:** 8
- **Inventory row → specification:** Tracker → WEB-01 · Identification → WEB-02 · Inbox, ranking, source and history → WEB-03 · Convert, contact reveal → WEB-04 · Pricing tiers → ENT-03

**Documents**

- **Rows:** 9
- **Inventory row → specification:** Templates, auto-fill, Sheets and Slides → DOC-01 · Product tables → DOC-02 · Cloud storage → DOC-03 · Trackable links → DOC-04 · E-signatures → DOC-05 · Logo removal, external signing → DOC-06

**Privacy and security**

- **Rows:** 14
- **Inventory row → specification:** Dashboard → SEC-01 · Alerts → SEC-02 · Rules → SEC-03 · Device history → SEC-04 · SSO → SEC-05 · 2FA and enforcement → SEC-06 · Permission sets → SEC-07 · Visibility groups and options → SEC-08 · Encryption, hosting, backups → SEC-10 · Compliance → SEC-11

**Marketplace**

- **Rows:** 16
- **Inventory row → specification:** Nine app categories → first-party connectors INT-05 to INT-09, COM-11, COM-12, DOC-06 · Collections, tags, installed-app page → INT-11 · Recommendations and search → AIA-06 · In-product surfaces, build your own → INT-10, INT-02

**Mobile app**

- **Rows:** 20
- **Inventory row → specification:** Focus view, email widget → MOB-02 · Nearby → MOB-03 · Calls, caller ID, texting → MOB-04 · Web-to-mobile → COM-12 · Views, detail, contact import, landscape, real-time sync, leads → MOB-01 · Statistics, live chat, projects → MOB-08 · Offline, manual sync → MOB-05 · Audio notes, note scanner, uploads → MOB-06 · Card scanner → AIA-07 · Push → MOB-07

Plans and pricing in the inventory are not features to build: the 15 usage limits map to ENT-02, plan gating to ENT-01 and add-ons to ENT-03. Pipedrive's prices and support tiers are not carried over.

Five specifications cite no feature row because their source sits elsewhere in the inventory: PIP-15 (August 2026 release: closed deals toggle and stage day counts), PIP-17 (deal duplication and the restore data row), CRM-14 (contact labels, named in the deal labels row), LGN-05 (how the chatbot, forms and tracker are embedded) and ENT-04 (the note on what happens when a limit is reached).

---

## Appendix 1 — Pipedrive feature inventory (the research, in full)

Source: "Pipedrive — Complete Feature Inventory", as of 3 October 2026. It documents what Pipedrive publishes; nothing in it was tested in a live account. Plan and price information is included because it shows which limits exist; in this project every such limit is a setting that defaults to unlimited (rule R5).

### Scope and method

This inventory documents every feature Pipedrive presents on pipedrive.com as of 3 October 2026, grouped under Pipedrive's own category names, with limits and the plan each feature starts on. Features are described as documented by Pipedrive; nothing was tested in a live account.

| Material | What was covered | What was not |
| --- | --- | --- |
| pipedrive.com (English) | 157 pages downloaded: all 51 feature pages, all 58 product pages, the 25 CRM-hub pages, pricing, product updates, Nova, MCP and the reviews pages. 133 are unique after redirects; 75 were read in full and the other 58 were scanned for feature descriptions, which added no features beyond those listed | 816 blog posts, 111 case studies, 54 industry pages, 30 competitor-comparison pages, legal pages and the 23 non-English editions |
| Plan comparison table | All 128 rows of the official table on the pricing page, including the description behind each row | Prices for usage-limit top-ups, which the Knowledge Base mentions but the pricing page does not list |
| Knowledge Base | All 562 articles listed on the Knowledge Base category pages were downloaded: 159 were read for exact limits, settings and plan availability, and the other 403 were scanned by title, 323 of them also by their headings, plus five developer-documentation pages on API versions, rate limits, authentication and webhooks | The full API reference, Pipedrive Academy, the community forum and the video tutorials category |
| Screenshots | 39 images, described in their own section | Videos and animated demos |
| Reviews and articles | G2, Capterra, TechRadar and Fit Small Business, plus Pipedrive's own reviews and awards pages | Trustpilot, Software Advice, GetApp and individual Marketplace app listings |

Reading the tables: "Growth+" means Growth, Premium and Ultimate. Prices are US dollars per seat per month on annual billing unless stated. Figures Pipedrive gives about customer results are marked as vendor claims. Plan availability comes from the pricing table or an explicit Knowledge Base statement; where a feature appears in neither with a plan, "All plans" means no restriction is documented, and "Not stated per plan" marks cases where Pipedrive says availability varies without saying how.

Pipedrive's own material disagrees with itself in twelve places, each noted where it occurs:

- Custom visibility groups and permission sets: 15 and 25 on the pricing page, 3 and 2 (Premium) and unlimited (Ultimate) in two Knowledge Base articles, while the Knowledge Base usage-limits table matches the pricing page.
- Interface languages: 24 on the pricing page, 22 on the customization page.
- AI report prompts: 14 on the product page, 15+ on the features page.
- Business card scanner: on iOS and Android in its own article, Android only in the mobile comparison table.
- The Smart Docs page and the sales order management page still use the old plan names (Essential, Advanced, Professional, Power, Enterprise).

- AI next-step suggestions: "across all plans" on the forecasting page, but AI notifications start on Premium in the pricing table.
- Backups: hourly on the pricing page, nightly full backups in the Knowledge Base.
- Nova and the WhatsApp integration: listed as current beta features on the beta program page, presented as released on the pricing page and in product updates.
- Web Visitors: "from $41" and a lowest tier of $49 on the same page, without saying which is annual billing.
- Marketplace size: 500+ apps on most pages, 350+ and 400+ on two other pages.

- Device history and audit log: Ultimate only on the pricing page, every plan in the Knowledge Base's features-by-plan table.
- Live chat support: 24/7 on every plan on the pricing page, from Growth in the Knowledge Base's features-by-plan table.

Third-party sites also quote plan prices that differ from pipedrive.com (Capterra lists $19, $34, $64 and $89); this document uses pipedrive.com.

### Product map: how Pipedrive groups its features

Pipedrive organizes its [features page](https://www.pipedrive.com/en/features) into one core product (Sales software, nine feature groups), an AI layer, three workspace add-ons, two lead add-ons, a security group, the Marketplace and the mobile app. This document follows that structure and those category names.

| Pipedrive category | Sub-groups Pipedrive lists | How it is sold |
| --- | --- | --- |
| [Sales software](https://www.pipedrive.com/en/products/sales) | Automation · CRM · Customization · Email and communications · Insights and reports · Integrations · Leads · Prospecting software · Processes, pipeline and activities | Core CRM, all plans; depth varies by plan |
| [AI CRM features](https://www.pipedrive.com/en/products/ai-crm) | AI Sales Assistant · AI email writer and summarizer · AI reporting · [Nova meeting intelligence](https://www.pipedrive.com/en/nova) (new) · [Pipedrive MCP](https://www.pipedrive.com/en/features/mcp-server) | Nova, MCP and AI reports on all plans; AI email tools and AI notifications from Premium |
| [Email marketing software](https://www.pipedrive.com/en/products/email-marketing-software) | Email builder · Email analytics · Email segmentation · Email marketing automation | Campaigns add-on, paid on every plan |
| [Project management software](https://www.pipedrive.com/en/features/projects) | Project management automation · Email project management | Projects add-on; included in Premium and Ultimate |
| [Lead generation software](https://www.pipedrive.com/en/features/lead-generation-software) | Chatbot · Live Chat · Web Forms · Prospector | LeadBooster add-on; included in Premium and Ultimate |
| [Web visitor tracking](https://www.pipedrive.com/en/features/web-visitors-add-on) | Company identification, visit source, engagement ranking | Web Visitors add-on, paid on every plan |
| [Documents and templates](https://www.pipedrive.com/en/features/smart-docs) | Templates, auto-fill, tracking, e-signatures | Smart Docs add-on; included in Premium and Ultimate |
| [Privacy and security](https://www.pipedrive.com/en/features/privacy-security) | Security center · Permissions and visibility · Data encryption | Baseline on all plans; rules, alerts and audit log on Ultimate |
| [Marketplace integrations](https://www.pipedrive.com/en/marketplace) | Accounting and invoicing · Chatbots · Email marketing · Lead generation · Phone solutions · Proposal contracts · Remote work · Resource management · Task management | 500+ apps, all plans |
| Mobile app | iOS and Android | All plans |

Nova and Pipedrive MCP are taken from the site's product menu; the features page's own AI list has only the first three entries.

The [pricing page](https://www.pipedrive.com/en/pricing) regroups the same features under eleven comparison headings: Feature usage limits; Manage deals; Generate, qualify and nurture leads; Track communications; Automate and grow; Pipedrive Nova meeting intelligence; Other AI-powered features; Insights and reports; Privacy and security; Mobile apps and integrations; Get more from Pipedrive. The plan section near the end of this document uses those headings.

Plans are Lite, Growth, Premium and Ultimate. Older reviews use the previous plan names (Essential, Advanced, Professional, Power, Enterprise). In the tables below, "Growth+" means Growth, Premium and Ultimate.

### Sales software · Automation

Automation in Pipedrive is four things: trigger-based workflows (Automations), rule-based owner assignment (Automatic assignment), linear outreach flows (Sequences) and developer hooks (webhooks, API). Workflows and Sequences start on Growth; assignment starts on Premium; Lite has none of the three.

**Automations (workflow builder)**

- **What it does:** Runs actions when a trigger and optional conditions are met
- **Details and limits:** Event triggers on 6 entities (deal, person, activity, lead, organization, project) × added, updated, deleted. Actions on person, organization, lead, deal, activity, email, notes, campaigns, projects, webhooks, plus Slack, Microsoft Teams, Asana and Trello. Up to 10 actions per path. Created by global admins by default; regular users need the "Add automations and configure automated email senders" permission. Active automations per company: 50 / 150 / 250
- **Plan:** Growth+

**Date triggers**

- **What it does:** Starts an automation from a date field
- **Details and limits:** Entities: deal, person, activity, organization. Parameters: exact date, before date, after date (e.g. contract renewal)
- **Plan:** Growth+

**Conditions**

- **What it does:** Filters when an automation runs
- **Details and limits:** Suggested or custom conditions on the trigger; email conditions also exist
- **Plan:** Growth+

**Delay and wait-for steps**

- **What it does:** Adds timing to a workflow
- **Details and limits:** Delay: up to 10 delay steps per path (3 on Growth) and 90 days in total per path; weekends can be skipped but still count toward the 90 days. Wait for condition: up to 7 days per step, then the automation stops
- **Plan:** Growth+

**If/else steps**

- **What it does:** Branches a workflow into paths
- **Details and limits:** 3 / 10 / 20 if/else steps per automation (Growth / Premium / Ultimate)
- **Plan:** Growth+

**Automated emails**

- **What it does:** Sends a personalized email when a deal is created or reaches a stage
- **Details and limits:** Sent from the user's synced email address; uses templates and merge fields
- **Plan:** Growth+

**Automation templates**

- **What it does:** Ready-made workflows
- **Details and limits:** 36 templates grouped in collections, e.g. add products to deals, re-engage inactive deals, follow up on new or progressing deals, avoid rotting deals
- **Plan:** Growth+

**Slack and Microsoft Teams notifications**

- **What it does:** Posts to a channel or a private message when a deal, contact or activity is created, updated or deleted
- **Details and limits:** Two Slack workflow templates
- **Plan:** Growth+

**Webhook action in Automations**

- **What it does:** Sends data to an external endpoint as a workflow step
- **Details and limits:** Methods POST, PUT, DELETE; key-value or raw JSON body; execution history shows the final body and path
- **Plan:** Growth+

**Automation dashboard (Overview)**

- **What it does:** Monitors automation health
- **Details and limits:** Periods: today, last 7 days, last 14 days. Sections: most failed, most active, no executions, automation health. Click-through to the failing step
- **Plan:** Growth+

**Automation history, sharing and ownership transfer**

- **What it does:** Audit and hand over workflows
- **Details and limits:** Filters "Owned by me" / "Owned by others"
- **Plan:** Growth+

**Frequency limits**

- **What it does:** Protects against loops
- **Details and limits:** 10,000 executions per 10 minutes per company; 5,000 per single automation
- **Plan:** Growth+

**Automatic assignment**

- **What it does:** Routes new or updated leads and deals to an owner
- **Details and limits:** Events: deal added, deal updated (pipeline or stage change), lead added. Conditions on deal, lead, person or organization fields. Assignee types: user, team (round-robin), organization owner, person owner. Rule priority order and an assignment history log
- **Plan:** Premium+

**Sequences (part of Pulse)**

- **What it does:** Linear email-and-task flows for nurturing
- **Details and limits:** Drag-and-drop Sequence Canvas; steps are emails (manual or automatic) and activities; delays between steps with skip-weekends; enroll deals or leads one by one or in bulk, or automatically through Automations; statuses In progress, Completed, Failed. 5 / 25 / 50 sequences per company
- **Plan:** Growth+

**Webhooks**

- **What it does:** Pushes an HTTP POST with a JSON body to an endpoint when an event fires
- **Details and limits:** Webhooks v2, separate from the automation webhook action. Up to 40 webhooks per user. A delivery times out after 10 seconds and is retried after 3, 30 and 150 seconds. Ten first-attempt failures ban the webhook for 30 minutes; it is deleted after 3 consecutive days without a successful delivery
- **Plan:** All plans

**API access**

- **What it does:** REST API for custom features and integrations
- **Details and limits:** Token-based rate limit with a daily budget per company. Versions, authentication, token costs and burst limits are listed under Integrations
- **Plan:** All plans

**Bulk activity**

- **What it does:** Adds activities to many contacts, leads or deals at once
- **Plan:** All plans

Pipedrive describes Sequences as manual-enrollment, top-to-mid-funnel flows and Automations as event-triggered workflows for every funnel stage. Related automation that sits in other groups: AI next-step suggestions and the MCP server (AI CRM features), document auto-fill (Smart Docs), chatbot qualification (LeadBooster).

Sources: [Sales automation](https://www.pipedrive.com/en/products/sales/automations) · [Workflow automation](https://www.pipedrive.com/en/features/workflow-automation) · [Lead distribution](https://www.pipedrive.com/en/products/sales/lead-distribution-software) · [Sales sequences](https://www.pipedrive.com/en/products/sales/sales-sequences) · [Pricing comparison](https://www.pipedrive.com/en/pricing) · KB: [Automations: first steps](https://support.pipedrive.com/en/article/workflow-automation), [Automation limits](https://support.pipedrive.com/en/article/automation-limits), [Automation overview](https://support.pipedrive.com/en/article/automation-overview), [Templates](https://support.pipedrive.com/en/article/workflow-automation-templates), [Webhook requests](https://support.pipedrive.com/en/article/automations-webhook-requests), [Automatic assignment](https://support.pipedrive.com/en/article/automatic-assignment), [Sequences](https://support.pipedrive.com/en/article/sequences)

### Sales software · CRM

The CRM group is the record layer: people, organizations, products and the tools that load, clean and enrich that data. Almost all of it is on every plan; recurring revenue and the contacts timeline start on Growth.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| People and organization management | Unlimited contact database, split into people and organizations | Each record shows history, linked deals, activities and communications | All plans |
| Contacts timeline | Chronological visual of emails, calls and meetings per contact | Used to check the last conversation before a follow-up | Growth+ |
| Contacts map | Plots contacts on Google Maps | Filter by city, state and country | All plans |
| Contact sync | Syncs external address books | Google, Outlook, Office 365, Exchange and EWS | All plans |
| File attachments | Attach files to leads, deals, contacts and products |   | All plans |
| Mentions and comments | @mention colleagues in notes or post comments on a lead, deal or contact |   | All plans |
| Products catalog | Catalog of goods or services with price, tax, notes and custom fields | Linking a product to a deal calculates deal value automatically. Default tax setting per user (inclusive, exclusive, none). Price variations per product. Spreadsheet import | All plans |
| Product subscriptions and installments | Recurring products and scheduled payments on a deal | Recurring products calculate MRR, ARR, ACV and TCV; installments calculate ACV and TCV. Billing frequency plus renew-until-canceled or a fixed number of cycles (up to 208) | Growth+ |
| Data import | Loads spreadsheets or migrates from another CRM | Drag-and-drop field mapping; one combined session for all data objects; duplicate check with merge-or-create choice; skip file listing rows that failed; import history | All plans |
| Named migration sources | 36 tools listed | Includes Salesforce, HubSpot, Zoho CRM, MS Dynamics CRM, Copper, Close, Freshsales, Insightly, Zendesk Sell, Attio, GoHighLevel, Keap, Nimble, Nutshell, Streak, Sugar CRM, ActiveCampaign, Mailchimp, Klaviyo | All plans |
| Data export | Export data whenever needed |   | All plans |
| Merge duplicates | Detects and merges duplicate people and organizations | List under Tools and apps, plus a flag on the record's detail view. Admins can configure which fields count as a match (since September 2026). Shows name, deals, activities, creation date, owner and visibility before merging | All plans |
| Leads and deals capacity | Active (not archived or deleted) leads plus deals per company | 2,500 / 5,000 / 15,000 / 20,000 × seats, capped at 300,000 | All plans |
| Data enrichment | Fills company, email and phone data on records | See Prospecting software | Premium+ |
| Restore data | Recovers items deleted in the last 30 days | People, organizations, deals, products, leads and activities. Shows who deleted an item, when and from which source. Lite and Growth: users restore any item they can see. Premium and Ultimate: users restore their own items, or other users' items if they hold the permission to edit them | All plans |
| Related organizations | Records relationships between organizations | Relationship types: parent, daughter, related. Set in the organization detail view | All plans |

Sources: [Email and communications](https://www.pipedrive.com/en/products/sales/email-and-communications) · [Data import and export](https://www.pipedrive.com/en/features/data-import-export) · [Account management](https://www.pipedrive.com/en/products/account-management-software) · [Pricing comparison](https://www.pipedrive.com/en/pricing) · KB: [Products](https://support.pipedrive.com/en/article/products), [Recurring products and installments](https://support.pipedrive.com/en/article/recurring-products), [Merge duplicates](https://support.pipedrive.com/en/article/merge-duplicates)

Further KB sources: [Restore data](https://support.pipedrive.com/en/article/restore-data), [Related organizations](https://support.pipedrive.com/en/article/related-organizations)

### Sales software · Customization

Customization covers pipelines, data fields, languages, currencies and switching modules off. Basic fields and pipelines are on every plan; field governance (required, formula, pipeline-specific) starts on Premium.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Customizable pipelines | Unlimited pipelines in kanban view | Rename, create, delete and reorder stages; edit stage attributes; team pipelines | All plans |
| Deal card customization | Chooses which fields show on pipeline cards |   | All plans |
| Custom fields | Extra fields on lead/deal, person, organization, product and project | 16 field types: text, large text, single option, multiple options (up to 1,000 options per field), autocomplete, numerical, monetary, user, organization, person, phone, time, time range, date, date range and address. Field groups and choice of where the field is shown. Read-only fields, which restrict who can view and edit, need Premium. 30 / 100 / 300 / 500 fields per company | All plans |
| Field descriptions | Tells the team why and how to fill a lead or deal field | Shown behind an info icon | Growth+ |
| Important fields | Marks fields the team should fill |   | Growth+ |
| Required fields | Blocks progress until a field is filled |   | Premium+ |
| Formula fields | Auto-calculates deal numeric and monetary fields | 10 formula fields per company | Premium+ |
| Pipeline-specific fields | Hides fields from specific pipelines | Declutters the deal detail view | Premium+ |
| Custom activity types | Adds to the defaults (call, meeting, task, deadline, email, lunch) |   | All plans |
| Languages | App interface language per user | Pricing page states 24 languages; the customization page states 22. Includes Norwegian, Swedish, Finnish, Estonian, German, French, Dutch, Polish | All plans |
| Multi-currency | Deals and products in all major currencies | Custom currencies can be created, e.g. for trading services or goods instead of money | All plans |
| Feature switches | Turns whole modules on or off in one click | Example given: hide Products if not used | All plans |
| Custom reports and dashboards | Reports built on custom fields | See Insights and reports | Premium+ |
| Custom permission sets and visibility groups | Shapes what each user can do and see | See Privacy and security | Premium+ |
| Sandbox account | Tests setups and workflows without touching live data | Non-developer sandbox | Ultimate |
| Sample data and tailored setup | Fills a new account with example records and a setup fitted to the company | A sign-up questionnaire asks company size and industry. Sample deals, people, organizations and activities carry the prefix [Sample] and can be removed from Quick help, the import page or Insights | Not stated per plan |

Sources: [Customizable CRM](https://www.pipedrive.com/en/products/sales/customizable-crm) · [Pricing comparison](https://www.pipedrive.com/en/pricing) · KB: [Custom fields](https://support.pipedrive.com/en/article/custom-fields)

Further KB source: [Sample data](https://support.pipedrive.com/en/article/sample-data)

### Sales software · Email and communications

This group covers email inside the CRM, meeting booking, calling and messaging. Lite only gets a BCC drop-box; full sync, tracking, templates and the scheduler start on Growth, and shared inboxes on Premium. Pipedrive has no built-in dialer: calling runs through Marketplace apps.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Email inbox with Smart Bcc | BCC or forward an email to Pipedrive and it links to the right deal and contact | One email at a time, no full sync; alternative sender addresses can be registered under Email sync | All plans |
| Two-way email sync (Sales Inbox) | Send, receive and reply to email inside Pipedrive | Providers: Gmail / Google Apps, Office 365 / Outlook, Microsoft Exchange (EWS), any IMAP account. Links conversations to deals, leads or projects automatically or manually; conversations private or shared; send from a Gmail alias | Growth+ |
| Multiple email accounts sync | Several inboxes per user in the Sales Inbox | Email syncs per seat: 1 / 3 / 5 (Growth / Premium / Ultimate) | Premium+ |
| Team inbox | Shared address that several users read and answer | Settings for visibility and sharing, default email visibility, past sync start date and synced folders. 1 team inbox on Premium, 5 on Ultimate | Premium+ |
| Email templates and signatures | Reusable, shareable templates | Ready-made or built from scratch | Growth+ |
| Merge fields | Auto-fills deal names, contacts and organizations into templates |   | Growth+ |
| Email open and click tracking | Real-time notification when a prospect opens an email or clicks a link |   | Growth+ |
| Group emailing | One email to many selected contacts | Launched from list views of leads, deals, people and activities, or the contacts timeline. Up to 100 contacts per send. Needs email sync and the "Bulk edit items" permission | Growth+ |
| Email scheduling | Sends later, e.g. for other time zones |   | Growth+ |
| Meeting scheduler | Booking page where the contact picks a slot | Two link types: general availability and specific times. Duration, working hours, notes, links and extra fields; confirmation emails to both sides; booked slots disappear in real time; link can go in a signature, document or automated email | Growth+ |
| General availability scheduling links | Flexible or recurring availability links | Default link only on Growth; full on Premium and Ultimate | Growth+ |
| Video call scheduling | Creates the video link for a booked meeting | Zoom, Microsoft Teams, Google Meet | Growth+ |
| Calendar view and activity management | Activities as a calendar or to-do list, linked to deals or leads | Calendar sync, one- or two-way, with Google, Office 365, Outlook and Exchange; private calendar events can be synced as private | All plans |
| Activity reminder alerts | In-app, email and mobile reminders in any combination |   | All plans |
| Calling | Click-to-call from records through a calling app | Named apps: Aircall, Kixie, JustCall, CloudTalk, CallHippo, Ring.io, Toky, CircleLoop. Recording, routing and SMS come from the app | All plans |
| Web-to-mobile calls, automatic call logging, caller ID | Start a call in the web app and finish it on the phone; calls logged as activities; caller ID tied to deals |   | All plans |
| WhatsApp integration | WhatsApp Business chats in the Sales Inbox, linked to deals and contacts | Pre-approved message templates, quick replies, chat labels, sent/delivered/read status, emoji reactions, inline images and audio, file sending, in-app notifications. Meta charges apply. WhatsApp automation is marked "available soon" | Growth+ |
| Chrome extension for Gmail | Adds deals, contacts, notes and activities from Gmail |   | All plans |
| Email labels | Labels to sort and filter emails in the Pipedrive inbox | Created from the label dropdown in the inbox | All plans |

Related features documented elsewhere: AI email writer and summarizer (AI CRM features), Smart Docs quotes and e-signatures (Documents and templates), Nova call recording (AI CRM features), Campaigns bulk email marketing (Email marketing software).

Sources: [Email and communications](https://www.pipedrive.com/en/products/sales/email-and-communications) · [CRM email integration](https://www.pipedrive.com/en/features/crm-email-integration) · [Scheduler](https://www.pipedrive.com/en/products/sales/scheduling-tool) · [Activity calendar](https://www.pipedrive.com/en/features/activity-calendar) · [Call tracking](https://www.pipedrive.com/en/features/call-tracking-insights) · [CRM for WhatsApp](https://www.pipedrive.com/en/features/crm-for-whatsapp) · KB: [Email sync](https://support.pipedrive.com/en/article/email-sync), [Team Inbox](https://support.pipedrive.com/en/article/team-inbox), [Group emailing](https://support.pipedrive.com/en/article/group-emailing), [Meeting scheduler](https://support.pipedrive.com/en/article/scheduler), [Making calls](https://support.pipedrive.com/en/article/how-can-i-make-calls-in-pipedrive), [WhatsApp integration](https://support.pipedrive.com/en/article/whatsapp-integration)

Further KB sources: [Email labels](https://support.pipedrive.com/en/article/email-labels), [Private synced events](https://support.pipedrive.com/en/article/private-activities)

### Sales software · Insights and reports

Insights is Pipedrive's reporting area: reports, dashboards, goals and a forecast view. Deal and activity reports, goals and AI report creation are on every plan; forecasting starts on Growth; custom dashboards, custom-field reports and team goals start on Premium.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Deal reports | Performance, conversion, duration, progress and products | Performance covers won, lost and open deals; duration shows time per stage; products shows revenue contribution | All plans |
| Activity reports | Activities performance and emails performance | Emails performance counts mail sent and received through email sync or Smart Bcc | All plans |
| Lead reports | Lead performance and lead conversion | By status, source, owner and custom fields; lead-to-deal conversion rate | Not stated per plan |
| Contact reports | People and organizations | Analyzes contact details, ownership and custom fields | Not stated per plan |
| Campaign reports | Campaign performance and campaign conversion | Comparative insights put two or more campaigns in one chart. Needs the Campaigns add-on | Add-on |
| Project reports | Project performance and project duration | Needs Projects | Premium+ or add-on |
| Revenue forecast reports | Product revenue forecast and deal revenue forecast | Based on deal values, linked products and expected close dates | Growth+ |
| Forecast view | Kanban of deals in date columns | Uses expected close date or a custom date field. Each column totals open value, won value and the combined projection. Dragging a deal changes its close date. A green bar shows stage progress | Growth+ |
| Custom field reports | Reports built on custom fields |   | Premium+ |
| Chart types | Column, bar, pie, scorecard, table | Fields: measure-by, view-by, segment-by. Custom chart colors. Scorecard shows change versus the previous interval | Not stated per plan |
| AI-powered report creation | Builds a report from a typed request | 14 pre-written prompts on the product page (the features page says 15+). Refine by chat. Custom fields can be named in the prompt | All plans |
| Visual dashboards | Collection of reports, dragged in, resized and arranged | Default dashboard only on Lite and Growth; custom dashboards on Premium and Ultimate; role-based templates for reps and managers since September 2026 | All plans |
| Shareable dashboard links | Live dashboard link for people inside or outside Pipedrive |   | All plans |
| Report collaboration | Team edits reports together |   | All plans |
| Dashboard collaboration | Team edits dashboards together |   | Premium+ |
| Company and user goals | Tracks progress against targets | Deal goals (added, progressed, won), activity goals (added, completed), forecast goals (weighted revenue). Fields: assignee, pipeline, frequency (weekly to yearly), duration, value or count | All plans |
| Team filters and goals | Groups reps into teams for reports and goals |   | Premium+ |
| Export | Takes charts and data out | Reports, dashboards (PDF or PNG) and goals as charts; table data as XLSX or CSV | Not stated per plan |
| Report capacity | Reports per seat | 15 / 50 / 250 / 500 | All plans |
| Duplicate reports, goals and dashboards | Copies an existing item instead of rebuilding it | Title, folder and dashboard can be changed on the copy. A report shared by someone else can be duplicated into the user's own reports | Not stated per plan |

Pipedrive names four pipeline metrics its reports are built around: number of deals, average deal size, close ratio and sales velocity.

Sources: [Insights and reports](https://www.pipedrive.com/en/features/insights-and-reports) · [Sales dashboard](https://www.pipedrive.com/en/features/sales-dashboard) · [Sales forecasting](https://www.pipedrive.com/en/features/sales-forecasting-software) · [Activities and goals](https://www.pipedrive.com/en/features/activities-goals) · [AI report generator](https://www.pipedrive.com/en/products/ai-crm/ai-report-generator) · KB: [Report types](https://support.pipedrive.com/en/article/insights-report-types), [Chart types](https://support.pipedrive.com/en/article/insights-reports-chart-types), [Goals](https://support.pipedrive.com/en/article/insights-goals), [Forecast view](https://support.pipedrive.com/en/article/the-forecast-view-revenue-projection), [Dashboards](https://support.pipedrive.com/en/article/insights-dashboards), [Exporting from Insights](https://support.pipedrive.com/en/article/exporting-data-from-insights)

Further KB source: [Insights: duplication](https://support.pipedrive.com/en/article/insights-duplication)

### Sales software · Integrations

Integrations come in three layers: built-in sync with Google and Microsoft, Marketplace apps (500+), and an open REST API with webhooks. All three are on every plan; only the daily API budget and partner discounts vary.

**Google Workspace integration**

- **What it does:** Keeps Pipedrive and Google in sync
- **Details and limits:** 2-way sync with Google Contacts and Google Calendar; Google Drive files (Docs, Sheets, Slides) attached to or created from deals and contacts; Gmail; Google Meet links (automatic on scheduled meetings from Growth); Google Tasks; sign-in with Google; Google Ads via Make; Google Sheets via Zapier
- **Plan:** All plans

**Gmail add-on and Chrome extension**

- **What it does:** Works with the CRM from the Gmail side panel or browser
- **Details and limits:** Add contacts, deals, notes and activities without leaving Gmail
- **Plan:** All plans

**Microsoft integration**

- **What it does:** Contact and calendar sync, Teams
- **Details and limits:** Outlook, Office 365, Exchange and EWS; Microsoft Teams video links (automatic on scheduled meetings from Growth) and notifications
- **Plan:** All plans

**Slack integration (Dealbot)**

- **What it does:** Posts deal updates to Slack
- **Details and limits:** Automatic updates on deals added, won or lost, and personal deal updates; slash commands to search deals, people and organizations
- **Plan:** All plans

**Named app integrations**

- **What it does:** Pipedrive-documented connectors
- **Details and limits:** Zoom, Google Meet, Asana, Trello, monday, Zendesk, DocuSign, Mailchimp, PandaDoc, Aircall, CloudTalk, Facebook Lead Ads, Livestorm, Zapier. Other pages also name Stripe, Make, Dear Lucy, Dedupely and Textline. Automatic video links on scheduled meetings need Growth
- **Plan:** All plans

**Invoicing**

- **What it does:** Create, view and send invoices from the deal detail view
- **Details and limits:** QuickBooks; invoices carry deal, person and organization details and their status updates on the deal
- **Plan:** Not stated per plan

**App panels and extensions**

- **What it does:** Shows an app's data inside deal and contact detail views
- **Details and limits:** Three kinds: link actions, app actions (pop-ups) and custom UI actions. Sidebar order is configurable
- **Plan:** All plans

**AI Marketplace search and smart-app recommendations**

- **What it does:** Natural-language app search and suggested apps
- **Plan:** All plans

**REST API**

- **What it does:** Free API token on every plan
- **Details and limits:** API v1 with a gradual move to v2: v2 is live for activities, deals, persons, organizations, products, pipelines and stages, fields, followers and search, and a replaced v1 endpoint gets at least one year's notice. Authentication is OAuth 2.0 for apps or a personal API token in the x-api-token header, one active token per user. Client libraries, SDKs, Postman and Insomnia are supported. Daily budget 30,000 / 60,000 / 150,000 / 210,000 tokens × seats, capped at 100 million, shared by the whole company and reset at midnight server time. Calls are rejected with HTTP 429 once it is spent; admins are emailed at 75% and 100%; usage is shown in an API usage dashboard
- **Plan:** All plans

**Developer Platform**

- **What it does:** Build public or private apps
- **Details and limits:** API reference, developer documentation, developer community, API clients on GitHub; app panels and app actions as extension points
- **Plan:** All plans

**Webhooks**

- **What it does:** Event push to any endpoint
- **Details and limits:** HTTP POST with JSON body. Webhooks v2 add events for lead, deal product, deal installment, project, board, phase and task. Limits are listed under Automation
- **Plan:** All plans

**Pipedrive app for ChatGPT**

- **What it does:** Lets ChatGPT read account data
- **Details and limits:** Sync mode indexes data every 30 minutes. Sees deals, leads, contacts, pipelines, activities, email conversations, products, users, custom fields, automations and reports
- **Plan:** Not stated per plan

**Pipedrive MCP**

- **What it does:** Connects AI assistants to live CRM data
- **Details and limits:** See AI CRM features
- **Plan:** All plans

**Non-developer sandbox account**

- **What it does:** Test environment without publishing an app
- **Plan:** Ultimate

**Partnership discounts**

- **What it does:** 20% off PandaDoc and CloudTalk, 15% off Surfe
- **Plan:** Ultimate

**API token costs**

- **What it does:** What each call deducts from the daily budget
- **Details and limits:** Get one entity 2 tokens, get a list 20, update one 10, delete one 6, delete a list 10, search 40. v2 endpoints cost less than v1
- **Plan:** All plans

**API burst limits**

- **What it does:** Requests allowed per rolling 2-second window, per token
- **Details and limits:** API token: 20 / 40 / 100 / 120 (Lite / Growth / Premium / Ultimate). OAuth apps: 80 / 160 / 400 / 480. Search API: 10 on every plan
- **Plan:** All plans

Sources: [CRM integrations](https://www.pipedrive.com/en/products/sales/integrations) · [CRM API](https://www.pipedrive.com/en/features/crm-api) · [Slack integration](https://www.pipedrive.com/en/features/slack-crm-integration) · [Google Workspace integration](https://www.pipedrive.com/en/crm/integrations/google-apps-integration) · [Connect tools you use](https://www.pipedrive.com/en/connect-tools-you-use) · KB: [Invoicing](https://support.pipedrive.com/en/article/invoicing-feature-in-pipedrive), [App panels](https://support.pipedrive.com/en/article/app-panels), [ChatGPT app](https://support.pipedrive.com/en/article/chatgpt-pipedrive-app), [Gmail add-on](https://support.pipedrive.com/en/article/pipedrive-gmail-add-on)

### Sales software · Leads

Leads live in a separate Leads Inbox until they are qualified and converted to deals. The inbox, labels and lead reports are on every plan; capture tools come from LeadBooster and routing from Automatic assignment.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Leads Inbox | Holds unqualified leads outside the pipeline | Add with "+ Lead" or import a spreadsheet. A lead must link to a person or organization; other fields are optional. Sortable, filterable, customizable columns | All plans |
| Lead-to-deal conversion | Moves a qualified lead into a pipeline | Deals can also be converted back to leads; leads and deals can be archived | All plans |
| Lead labels | Color-coded categories | Several labels per lead, filter by label, bulk edit | All plans |
| Lead import | Bulk-imports leads and deals from spreadsheets |   | All plans |
| Lead email | Send from the Leads Inbox through Smart Bcc or email sync | Full sync needs Growth | All plans |
| Lead reports | Lead performance and lead conversion in Insights | By source, owner, status and custom fields | Not stated per plan |
| Lead capture | Web Forms, Chatbot, Live Chat | See Lead generation software (LeadBooster) | Premium+ or add-on |
| Outbound lead search | Prospector database | See Lead generation software (LeadBooster) | Premium+ or add-on |
| Lead routing | Automatic assignment rules, including round-robin by team | See Automation | Premium+ |
| Lead scoring and enrichment | Pulse scores and data enrichment | See Prospecting software | Premium+ |
| Leads on mobile | Leads Inbox in the iOS and Android apps |   | All plans |
| Messaging inbox and LinkedIn integration | Entries in the Leads menu, marked beta and new | Seen in a Knowledge Base screenshot only; not described on the pages read | Not stated per plan |
| Lead source fields | Records where a lead or deal originated | Entered manually or filled automatically; kept through conversion and archiving. Origins: manually created, import, API, automation, Marketplace, Prospector, lead suggestions, Web Forms, Chatbot, Live Chat, Web Visitors, Campaigns, Messaging inbox | All plans |

Pipedrive's own claim on the Leads page: customers increase deals in pipeline by 93% on average, raise average closed-deal value by 21% and cut time to close by 46%. These are vendor figures, not independently verified.

Sources: [Lead management](https://www.pipedrive.com/en/products/sales/leads) · [Lead capture](https://www.pipedrive.com/en/products/sales/lead-capture) · [Lead routing](https://www.pipedrive.com/en/products/sales/lead-routing-software) · KB: [Leads Inbox](https://support.pipedrive.com/en/article/leads-inbox), [Lead labels](https://support.pipedrive.com/en/article/lead-labels)

Further KB source: [Lead source in deals](https://support.pipedrive.com/en/article/lead-source-deals)

### Sales software · Prospecting software

Pipedrive's prospecting product is Pulse, a toolkit of four features: feed, data enrichment, custom scoring and Sequences. The toolkit and feed are on every plan; Sequences start on Growth, scoring and company enrichment on Premium, and email and phone enrichment on Ultimate.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Pulse feed (Sales feed) | One real-time workspace of next-best steps on open deals | Three tabs. Follow-ups: email replies, no reply after 5 days, today's planned activities, emails opened, links clicked, email drafts queued by Sequences. Overlooked deals: no follow-up activity, overdue activities. Opportunities: new deals with no activity | All plans |
| Feed cards and side panel | Act without leaving the feed | Quick actions to schedule a task, send an email or open the deal. Filters: pipeline stage, card type, score | All plans |
| Custom scoring (Scores) | Ranks deals by fit on a 0–100 scale | Target entity is deals, per pipeline. Criteria groups: highly positive +25, slightly positive +10, negative −10, with AND/OR conditions. Preview shows which criteria matched. Only one score can be active per pipeline. 5 scores per company on Premium, 10 on Ultimate | Premium+ |
| Firmographic data enrichment | Fills company fields | Address, industry, employee count, annual revenue, LinkedIn profile, website. Powered by Surfe. Only fills empty fields | Premium+ |
| Email and phone data enrichment | Finds a person's email and phone number | The article names these inputs: the person's name, LinkedIn profile, linked organization and email address | Ultimate |
| Bulk enrichment | Enriches up to 100 people or organizations at once from the list view |   | Premium+ |
| Enrichment credits | Monthly allowance, reset each billing cycle | 100 credits per company on Premium, 500 on Ultimate; top-up credits can be bought | Premium+ |
| Sequences | Email-and-task nurturing flows | See Automation | Growth+ |
| Prospector | Outbound search across 400 million profiles and 10 million companies | Powered by Cognism. Person filters: job title, department, location, name. Organization filters: size, industry, type, revenue, location, name, domain, keyword. Saved filters. Credits reveal phone, email and LinkedIn link; results go to the Leads Inbox. Up to 800,000 profiles verified per day | Premium+ or LeadBooster add-on |
| Reverse email lookup | Builds a contact profile from an inbound email address | The marketing page promises contact details, job titles and company information from an email address; the Knowledge Base enrichment fields include no job title | Follows the enrichment plans |

Sources: [Sales prospecting software (Pulse)](https://www.pipedrive.com/en/products/sales-prospecting-software) · [Prospector](https://www.pipedrive.com/en/features/prospector) · [Reverse email lookup](https://www.pipedrive.com/en/features/reverse-email-lookup) · KB: [Pulse](https://support.pipedrive.com/en/article/pulse), [Pulse feed](https://support.pipedrive.com/en/article/pulse-feed), [Scores](https://support.pipedrive.com/en/article/scores), [Score calculation](https://support.pipedrive.com/en/article/scores-calculation), [Data enrichment](https://support.pipedrive.com/en/article/data-enrichment), [Enrichment credits](https://support.pipedrive.com/en/article/data-enrichment-credits-and-top-ups), [Prospector](https://support.pipedrive.com/en/article/prospector)

### Sales software · Processes, pipeline and activities

This is the core of the product: a drag-and-drop kanban pipeline, deals with activities attached, and views and filters around them. Everything here is on every plan except teams, which start on Premium.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Visual pipeline | Kanban board of deals by stage | Drag and drop between stages; unlimited pipelines; color cues mark deals needing attention and overdue activities; stage totals | All plans |
| Deal management | One record per opportunity | Value, win probability, expected close date, owner, linked person and organization, communications and activity history | All plans |
| Deal rotting | Flags deals idle longer than a set period | Rotting period set per stage | All plans |
| Deal labels | Color-coded labels on deals | Visible in pipeline, detail and list views; separate contact labels exist | All plans |
| Lost reasons | Records why a deal was lost | Freeform, or a predefined list set by a user with Deals admin permission; comments saved as a note | All plans |
| Participants | Adds extra people to a deal beyond the one linked person | Suggested when creating activities or emails; added from linked conversations or by bulk import | All plans |
| Followers | Lets other users watch a deal, product, person, organization or another user's items | Followers get notifications; followed users and items are listed on each user's User overview page | All plans |
| Views | Pipeline, list, forecast and archive views of deals | List view has custom columns, multi-column sort, bulk edit and export. Every lead, deal, activity, person, organization and product has a system ID, shown in the item's URL. Forecast view needs Growth | All plans |
| Filters | Quick filters and advanced filters | Advanced filters use ALL and ANY condition groups, can be named, shared and favorited; available on leads, deals, contacts, activities, projects and products | All plans |
| Archive deals and leads | Removes inactive items from active views without losing history | Archived items do not count toward the leads-and-deals limit | All plans |
| Deals waitlist | Holds deals created by automations, API, Chatbot or Web Forms once the open-deal limit is hit | Filter by source; bulk add back to the pipeline | All plans |
| Activities | Calls, meetings, tasks, deadlines, emails, lunches and custom types | Linked to deals, leads, people or organizations; calendar or list view; scheduled from pipeline, calendar or contact timeline | All plans |
| Activity priority labels | High, medium, low | Set in contextual view, list view or bulk edit; shown in calendar view | All plans |
| Activity reminders | In-app, email and mobile | Follow-up prompt after an activity is marked done | All plans |
| Recurring activities | No native feature | Recurring events only arrive through calendar sync and appear grayed out | Gap |
| Manager view of team activities | Managers see each rep's planned and overdue activities | Teams (15 on Premium, 25 on Ultimate) group users for assignment, reports and pipelines | Premium+ for teams |
| Pipeline metrics | Deals in pipeline, average deal value, close rate, time to win | Reported in Insights | All plans |
| Activity invites | Sends calendar invites to contacts added as guests on an activity | Needs calendar sync to be active | All plans |

Sources: [Pipeline management](https://www.pipedrive.com/en/features/pipeline-management) · [Deal management](https://www.pipedrive.com/en/products/sales/deal-management) · [Sales funnel software](https://www.pipedrive.com/en/features/sales-funnel-management) · [Activities and goals](https://www.pipedrive.com/en/features/activities-goals) · [Sales team management](https://www.pipedrive.com/en/features/sales-team-management) · KB: [Deal labels](https://support.pipedrive.com/en/article/deal-labels), [Lost reasons](https://support.pipedrive.com/en/article/lost-reasons), [Participants](https://support.pipedrive.com/en/article/participants), [Followers](https://support.pipedrive.com/en/article/followers), [Advanced filtering](https://support.pipedrive.com/en/article/filtering), [Archive deals and leads](https://support.pipedrive.com/en/article/archive-deals-leads), [Deals waitlist](https://support.pipedrive.com/en/article/deals-waitlist), [Activity priority labels](https://support.pipedrive.com/en/article/activity-priority-labels), [Recurring activities](https://support.pipedrive.com/en/article/recurring-activities)

Further KB sources: [Activity invites](https://support.pipedrive.com/en/article/activity-invites), [User overview](https://support.pipedrive.com/en/article/user-overview)

Further KB source: [System IDs](https://support.pipedrive.com/en/article/pipedrive-system-ids)

### AI CRM features

Pipedrive AI is a set of assistants embedded across the CRM rather than a separate product, plus two newer pieces: Nova (meeting intelligence) and the MCP server. Nova, MCP, the Sales Assistant chat and AI reports are on every plan; AI email tools and AI notifications start on Premium.

#### Pipedrive AI

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Sales Assistant (beta) | Chat assistant next to the search bar | Powered by OpenAI. Voice or text questions; context-aware answers from account data and usage; summarizes content (up to 300 characters); drafts notes and emails; step-by-step help from the Knowledge Base; saved chat history. Example uses: deal summaries, team performance comparison, revenue forecast, stage-duration bottlenecks | All plans |
| AI-powered notifications | Predicts deal win probability and recommends next-best actions | Flags deals that stall, slip or show momentum | Premium+ |
| Notifications | Non-AI alerts and tips | Activity reminders, productivity tips, email opens, discussion updates, deals without a scheduled activity | All plans |
| AI email creation ("Write my email") | Drafts an email from a prompt | Fields: content description, tone (professional, formal, friendly), length (short, standard, long). Detects the prompt's language. Available in any email composer | Premium+ |
| AI email summarization (beta) | Condenses an email thread | Returns summary, sentiment, readiness to buy (1–10) and action items | Premium+ |
| AI email suggested replies (beta) | Proposes replies |   | Premium+ |
| AI-assisted report creation | Builds an Insights report from a prompt | See Insights and reports | All plans |
| AI import assistant | Maps spreadsheet columns to Pipedrive fields during import | Also handles multiple-option fields | All plans |
| AI Marketplace search and smart-app recommendations | Natural-language app search and a "Recommended apps for you" list | Based on tools in use and apps used by similar companies | All plans |
| Business card scanner on mobile | Digitizes a card into a contact |   | All plans |

#### Nova meeting intelligence

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Pre-call briefs | Brief before every call | Built from deal history, past emails, previous conversations and contact and organization info; checklist of recent activity; free-form custom instructions | All plans |
| AI Notetaker (bot) | Joins Google Meet, Zoom or Microsoft Teams as a visible participant | Auto-join from the calendar about two minutes before start; meeting owners can remove the bot; consent emails can be sent automatically, 24 hours before by default | All plans |
| Nova Companion desktop app | Records from the computer's audio with no bot in the call | Covers VoIP, phone calls, in-person meetings and any conferencing tool. macOS 13+ (Apple Silicon only) and Windows 10+ (64-bit). Ad hoc calls with no calendar event can be recorded, with no maximum duration | All plans |
| Recording, summary and transcript | Recap with key takeaways and recommended next steps | Timestamped transcript; clicking an action item jumps to that moment; saved as a note on the linked deal, person or organization; Slack notification when the recap is ready | All plans |
| CRM data sync | Drafts field updates when the call ends | Covers deal, person and organization fields, including custom fields, labels and contact details. Suggestion shown beside the current value; nothing changes until approved, in one click | All plans |
| Transcript upload | Processes calls Nova did not record | Produces the same recap and suggested updates | All plans |
| Controls | Nova is on by default for every user | Admins can turn it off per user under Manage users. AI providers are barred from training on client data | All plans |
| Connections | What Nova links to during setup | Its own Gmail connection, separate from email sync, which reads email in real time to build briefs (optional but recommended); a Google or Outlook calendar; Slack (optional). One permission set covers all Nova features | All plans |

#### Pipedrive MCP

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| MCP server | Official connection between AI assistants (ChatGPT, Claude) and live CRM data | OAuth login, no code. The assistant only sees and edits what the user's Pipedrive permissions allow. Admins can switch MCP access off for the whole company in Company settings | All plans |
| MCP tools | 37 documented tools following get, add, update and search patterns | Entities: activities, deals, persons, organizations, leads, products, pipeline stages and notes. Includes convertLeadToDeal and getLeadConversionStatus | All plans |

Pipedrive states it is ISO 27001 and ISO 27701 certified and GDPR-compliant, that its AI providers are contractually barred from training on client data, and that Pipedrive does not train its own models on it without permission.

Sources: [AI CRM](https://www.pipedrive.com/en/products/ai-crm) · [AI Sales Assistant](https://www.pipedrive.com/en/features/ai-sales-assistant) · [AI email writer](https://www.pipedrive.com/en/products/ai-crm/ai-email-writer) · [Nova](https://www.pipedrive.com/en/nova) · [MCP server](https://www.pipedrive.com/en/features/mcp-server) · [AI for everyone](https://www.pipedrive.com/en/ai-for-everyone) · KB: [Pipedrive AI availability](https://support.pipedrive.com/en/article/pipedrive-ai), [Sales Assistant](https://support.pipedrive.com/en/article/sales-assistant), [AI email creation](https://support.pipedrive.com/en/article/ai-email-creation), [AI email summarization](https://support.pipedrive.com/en/article/ai-email-summarization), [Nova Companion](https://support.pipedrive.com/en/article/nova-companion), [Nova FAQ](https://support.pipedrive.com/en/article/nova-faq), [MCP tools](https://support.pipedrive.com/en/article/mcp-tools)

Further KB source: [Nova: record unscheduled calls](https://support.pipedrive.com/en/article/nova-unscheduled)

### Email marketing software (Campaigns)

Campaigns is Pipedrive's email marketing add-on, sold separately on every plan and priced by subscriber count, starting from $13.33 per month. It has two tiers, Standard and Premium; only comparative insights and the campaign-type filter are Premium-only.

| Feature | What it does | Details and limits | Tier |
| --- | --- | --- | --- |
| Email builder | Drag-and-drop editor for campaigns, newsletters and templates | Three tabs: Content, Rows, Settings. Rows set the layout; content blocks drop into rows; row properties cover border, background color or image and padding. Start blank or from a layout | Standard and Premium |
| Email templates | Ready-made and custom templates saved to a library | Code-your-own (HTML) templates also supported | Standard and Premium |
| Email segmentation | Targets recipients with CRM filters | Filter by engagement, location and any contact data; one unified sales and marketing contact list | Standard and Premium |
| Marketing status and consent | Tracks opt-in per email address | Statuses: no consent (default), subscribed, unsubscribed, bounced (hard bounce or five soft bounces), pending upgrade, pending double opt-in, archived. Only subscribed contacts receive campaigns. Not applicable to leads or deals | Standard and Premium |
| Double opt-in | Confirms subscription by email | Single and double opt-in are both supported, but Pipedrive may require double opt-in on an account for compliance | Standard and Premium |
| Scheduling | Sends a campaign later |   | Standard and Premium |
| Email analytics | Real-time engagement and delivery reporting per campaign | Total and unique opens, open rate, total and unique clicks, click rate, click-through rate, delivered, bounced, unsubscribed, spam reports, top locations. Needs engagement tracking switched on | Standard and Premium |
| Campaign engagement notifications | Alerts on recipient engagement |   | Standard and Premium |
| Campaign insights | Campaign performance and conversion reports inside Insights |   | Standard and Premium |
| Comparative insights | Compares two or more campaigns in one chart | Used to compare subject lines and layouts | Premium |
| "Campaign type" insights filter | Filters insights by campaign type |   | Premium |
| Email marketing automation | Triggers campaign emails from CRM changes | Built into the Automations builder; automated campaigns take their audience from the automation; delay steps; templates | Standard and Premium |
| Deliverability tools | Sender domain authentication, DMARC guidance, email compliance recommendations | Account verification before sending | Standard and Premium |
| Security and permissions | Two-factor authentication and Campaigns permissions |   | Standard and Premium |
| Mailchimp migration | Moves lists from Mailchimp |   | Standard and Premium |

Sources: [Email marketing software](https://www.pipedrive.com/en/products/email-marketing-software) · [Email builder](https://www.pipedrive.com/en/products/email-marketing-software/email-builder) · [Email analytics](https://www.pipedrive.com/en/products/email-marketing-software/email-analytics) · [Marketing automation](https://www.pipedrive.com/en/features/email-workflow-automation) · [Campaign management](https://www.pipedrive.com/en/products/email-marketing-software/crm-campaign-management) · KB: [Campaigns by Pipedrive](https://support.pipedrive.com/en/article/campaigns-by-pipedrive), [Add-on tiers](https://support.pipedrive.com/en/article/campaigns-add-on-tiers), [Marketing contacts](https://support.pipedrive.com/en/article/campaigns-marketing-contacts), [Reporting](https://support.pipedrive.com/en/article/campaigns-reporting), [Drag-and-drop editor](https://support.pipedrive.com/en/article/drag-drop-editor), [Automated campaigns](https://support.pipedrive.com/en/article/automated-campaigns)

### Project management software (Projects)

Projects handles the work after a deal is won: boards with phases, tasks, timelines and health tracking, linked back to the deal. It is included for all users on Premium and Ultimate and is a per-seat paid add-on on Lite and Growth, from $16 per month. In the Status column, "Released" means Pipedrive's pages carry no beta label for that feature.

| Feature | What it does | Details and limits | Status |
| --- | --- | --- | --- |
| Boards and phases | Kanban boards where projects move through phases | Multiple boards per process, team or use case; add, edit, delete and reorder phases | Released |
| Deal, contact and organization links | Keeps sales context on the project | A project links to deals, one contact and one organization | Released |
| AI-assisted project brief | Drafts the brief when a deal closes | Built from the deal's emails, notes and files; needs review | Released |
| Tasks and subtasks | To-do items and their steps | Multiple assignees; owner, start and due date optional; subtasks always sit under a parent task | Released |
| Milestones | Marks key progress points | Tracks progress, not work | Released |
| Activities | Calls and meetings on the project | Need date, time and owner; can sync to an external calendar | Released |
| Task dependencies | Orders work and exposes blockers | Set on tasks and milestones | Released |
| Gantt timeline | Timeline view inside a project | Drag a whole phase or group to shift it while keeping spacing | Beta |
| Bulk task entry | Paste a list of tasks in one step | A date in a line becomes the due date | Released |
| Project templates | Reusable project structure | Tasks, activities, milestones and dependencies with due dates relative to the start date; organized by phases or groups; an existing project can be converted into a template | Released |
| Project health | Status in the project sidebar | On track, At risk, Off track, On hold; set manually | Released |
| AI health summary | Suggests a health status with overview and recommendations | Reads emails, notes, tasks and activities; can be regenerated; must be enabled for the account | Beta |
| AI-generated external sharing | One-click project report PDF for clients |   | Beta |
| Collaboration | Notes, file sharing and @mentions on the project | Emails can be sent and linked from a project | Released |
| Customization | Custom fields, labels and filters for projects |   | Released |
| Project automation | Projects as a trigger and an action in Automations | Project added, updated or deleted can start a workflow | Released |
| Project reports | Project performance and project duration in Insights |   | Released |
| Projects on mobile | Tasks and updates in the app | Android available; iOS "coming soon" | Partial |
| Import and export | Moves project data in and out | Project import and export since March 2026; import from Asana, Monday, Basecamp and others through Import2 since September 2026 | Released |

Sources: [Projects](https://www.pipedrive.com/en/features/projects) · [CRM task management](https://www.pipedrive.com/en/products/project-management-software/crm-task-management) · KB: [Projects by Pipedrive](https://support.pipedrive.com/en/article/projects-by-pipedrive), [Plan your project](https://support.pipedrive.com/en/article/projects-tasks-and-subtasks), [Templates](https://support.pipedrive.com/en/article/projects-templates), [Project health](https://support.pipedrive.com/en/article/projects-manage-project-health), [Manage work items](https://support.pipedrive.com/en/article/projects-manage-work-items-efficiently), [Billing and subscription](https://support.pipedrive.com/en/article/projects-billing-and-subscription)

### Lead generation software (LeadBooster)

LeadBooster bundles four lead tools: Chatbot, Live Chat, Web Forms and Prospector. It is included in Premium and Ultimate; on Lite and Growth it costs from $32.50 per company per month billed annually, or $39 billed monthly.

**Chatbot**

- **What it does:** Scripted website bot that qualifies visitors 24/7
- **Details and limits:** Built as playbooks. Setup covers color palette, bot name, profile picture and language. Four starting templates: Get more leads, Book more meetings, Qualify and route leads, Chat with your leads. Questions can differ per web page

**Chatbot routing**

- **What it does:** Saves qualified visitors as leads or deals and assigns an owner
- **Details and limits:** Qualified leads appear in bold with a blue dot at the top of the rep's Leads Inbox

**Chatbot meeting booking**

- **What it does:** Lets a qualified visitor book a meeting through Scheduler
- **Details and limits:** Meetings sync to the rep's calendar

**Chatbot analytics**

- **What it does:** Performance, status and drop-off analysis per step of the flow
- **Details and limits:** Shows where visitors leave and which steps create leads

**Live Chat**

- **What it does:** Rep takes over the chat in real time
- **Details and limits:** A card inside a Chatbot playbook. Settings include online message and waiting time; chats land in an unassigned folder to be claimed. Works from web or mobile app; the bot steps back in when nobody is free

**Web Forms**

- **What it does:** Embeddable or shareable forms and surveys
- **Details and limits:** Templates or blank start. Block types: input field and message; introduction block is mandatory. Fields: name, phone, email, marketing status and custom fields (text, large text, single option and more), each optionally required. Share by link, embed or post to social. Templates include file upload and gated download. Since August 2026 forms capture UTM parameters, cookie values, referral URL and landing page, and accept JavaScript variables in hidden fields

**Web Forms routing**

- **What it does:** Submissions become leads or deals
- **Details and limits:** Email notification on submission; can trigger workflows

**Web Forms performance**

- **What it does:** Viewed, interacted, submitted, conversion and active/inactive status

**Prospector**

- **What it does:** Outbound database of 400 million profiles and 10 million companies
- **Details and limits:** 10 credits per month included; one credit reveals one lead. More credits by slider, cheaper per credit at volume; Premium and Ultimate buy them as top-ups. See Prospecting software

Sources: [LeadBooster](https://www.pipedrive.com/en/features/lead-generation-software) · [Chatbot](https://www.pipedrive.com/en/features/web-chat) · [Web Forms](https://www.pipedrive.com/en/features/web-forms) · KB: [LeadBooster add-on](https://support.pipedrive.com/en/article/leadbooster-add-on), [Chatbot](https://support.pipedrive.com/en/article/chatbot), [Live Chat](https://support.pipedrive.com/en/article/live-chat), [Web Forms](https://support.pipedrive.com/en/article/web-forms), [Web Forms performance](https://support.pipedrive.com/en/article/web-forms-reporting-and-performance), [LeadBooster and Prospector billing](https://support.pipedrive.com/en/article/prospector-leadbooster-billing)

### Web visitor tracking (Web Visitors)

Web Visitors identifies which organizations browse a website, how they arrived and what they viewed. It is a paid add-on on every plan, including Ultimate, priced by identified organizations per month.

| Feature | What it does | Details and limits |
| --- | --- | --- |
| Tracker script | Collects visits on one or many websites | Sites separated with a hostname filter |
| Organization identification | Names the companies visiting | ISPs, crawlers and irrelevant traffic filtered out. A company counts once per month however often it visits. Data syncs hourly |
| Web Visitors inbox | Lists companies, visit times and whether they match an existing organization | Sorted by quality |
| Lead ranking | Ranks visitors by web activity | Filters: country, Google AdWords campaign, pages visited, existing contact or not |
| Visit source and browsing history | Shows how a company found the site and every page it viewed |   |
| Convert to CRM records | Adds a visitor as a lead, deal or organization |   |
| Contact reveal | Uses Prospector credits to find people at an identified company | Credits bought separately |
| Pricing tiers | Fixed price by average unique identified organizations | Up to 200: $49 per month. 201–500: $99. 501–2,000: $299. This page and the pricing page also say "from $41", without stating which billing period that figure applies to. 14-day free trial |

Sources: [Web Visitors add-on](https://www.pipedrive.com/en/features/web-visitors-add-on) · KB: [Web Visitors](https://support.pipedrive.com/en/article/web-visitors-feature), [Web Visitors pricing](https://support.pipedrive.com/en/article/how-does-web-visitors-pricing-work)

### Documents and templates (Smart Docs)

Smart Docs creates quotes, proposals and contracts from a deal or contact, fills them with CRM data, tracks opens and collects e-signatures. It is included in Premium and Ultimate; on Lite and Growth it is an add-on from $32.50 per company per month.

| Feature | What it does | Details and limits |
| --- | --- | --- |
| Templates | Reusable documents, spreadsheets and presentations | Created in the Documents tab of a deal or contact, or imported from cloud storage; named and categorized; shareable company-wide |
| Auto-fill fields | Inserts deal, contact, product and project data | Default and custom fields pasted into the template in square brackets; address fields can be split into sub-fields |
| Product tables | Quote tables filled from products on the deal | In Google Slides a three-row table (header, content, summary). Not available in Google Sheets templates, but can be added to a Sheets document |
| Cloud storage | Stores documents in the user's drive | Google Drive, Microsoft OneDrive and SharePoint; personal or shared drive; default shared drive per company |
| Trackable sharing links | Notifies when a recipient opens a document | Also works for uploaded PDFs |
| eSignatures | Requests signatures without another tool | Basic digital signing. Up to 10 signers per document; one-time authentication code by email; custom subject and message; invite language; drag-and-drop signer fields |
| Google Sheets and Slides support | Smart Docs functions inside Sheets and Slides |   |
| Logo removal | Removes the Pipedrive logo from documents |   |
| DocuSign integration | Creates DocuSign envelopes from Pipedrive |   |

Sources: [Smart Docs](https://www.pipedrive.com/en/features/smart-docs) · [Email and communications](https://www.pipedrive.com/en/products/sales/email-and-communications) · KB: [Smart Docs](https://support.pipedrive.com/en/article/smart-docs), [eSignatures](https://support.pipedrive.com/en/article/sales-documents-esignatures-beta), [Fields and templates](https://support.pipedrive.com/en/article/smart-docs-fields-and-templates), [Product tables](https://support.pipedrive.com/en/article/smart-docs-product-tables-in-slides-and-spreadsheets)

### Privacy and security

Pipedrive groups security into three parts: the Security center, permissions and visibility, and data encryption. Sign-in protection, encryption and the dashboard are on every plan; custom permissions and visibility start on Premium; rules, alerts and the audit log are Ultimate only.

| Feature | What it does | Details and limits | Plan |
| --- | --- | --- | --- |
| Security dashboard | Overview of who is accessing the account | "Right now": users logged in and their locations, unique locations. "Last 7 days": new devices and related login activity. Click-through to full lists | All plans |
| Security alerts | Email alerts on risky events | Login from a new device or location, new user invited, more than 3 failed logins in a row, password reset request; also suspected data leaks and data loss. Sent instantly or as a digest at a set time | Ultimate |
| Security rules | Enforced access policy | Password strength (upper and lower case, number, special character, minimum length of at least 8), password expiry (30 to 365 days or never), reuse limits, IP- and time-based access restrictions. The same screen holds the 2FA enforcement switch, which is available on every plan | Ultimate |
| Device history and audit log | Login times and locations for the last 60 days; remote log-out of other devices; a login and device log, not a record-change audit trail |   | Ultimate |
| SAML single sign-on | Central login through an identity provider | Guides for Entra ID and Okta; Google sign-in also supported | All plans |
| Two-factor authentication | Email verification at login |   | All plans |
| 2FA enforcement | Makes 2FA mandatory for all users | Authenticator app or verification link | All plans |
| Permission sets | Controls what users can do | Separate sets for the Deals, Projects and Campaigns apps and for global features. Types: Admin (full, not editable), Regular (editable), Custom. Covers creating, editing and deleting items, import and export, changing visibility, viewing reports | All plans; custom sets Premium+ |
| Visibility groups | Controls what users can see | Lite and Growth: one default group, visibility set to owner or all users. Premium and Ultimate: custom groups and sub-groups with four options (owner, owner's group, owner's group plus sub-groups, all users) | All plans; custom groups Premium+ |
| Visibility options | Item-level visibility for pipelines, leads, deals, contacts and products |   | All plans |
| Data encryption | AES-256 encryption of data and credentials | Each company's data sits in a separate database; HTTPS-only connections | All plans |
| Data hosting | AWS regions | Sydney, Montreal, Frankfurt, Dublin, London, US East, US West; region assigned by sign-up origin. The pricing page also names Rackspace | All plans |
| Backups | Hourly data backups | Pricing page: data loss limited to one hour and full service restored within two, in effect a 1-hour RPO and a 2-hour RTO. KB: real-time replicas, nightly full backups, encrypted off-site copies | All plans |
| Compliance | SOC 2 (annual third-party audits), ISO/IEC 27001, ISO 27701, GDPR | Data can be exported, transferred through the API or deleted | All plans |

Two inconsistencies in Pipedrive's own material. First, the pricing page lists 15 custom visibility groups and 15 custom permission sets on Premium and 25 of each on Ultimate, while two Knowledge Base articles say 3 groups and 2 custom sets on Premium and unlimited on Ultimate; the Knowledge Base usage-limits table agrees with the pricing page. Second, the pricing page puts device history and the audit log on Ultimate only, while the Knowledge Base's features-by-plan table lists them on every plan and a per-user device history sits under Personal preferences.

Sources: [Privacy and security](https://www.pipedrive.com/en/features/privacy-security) · [Permissions and visibility](https://www.pipedrive.com/en/features/permissions-visibility) · [Pricing comparison](https://www.pipedrive.com/en/pricing) · KB: [Security features](https://support.pipedrive.com/en/article/security-features-in-pipedrive), [Security dashboard](https://support.pipedrive.com/en/article/security-dashboard), [Security rules](https://support.pipedrive.com/en/article/security-rules), [Security alerts](https://support.pipedrive.com/en/article/security-alerts), [Single sign-on](https://support.pipedrive.com/en/article/single-sign-on), [Visibility and permissions](https://support.pipedrive.com/en/article/visibility-and-permissions-overview), [Data security](https://support.pipedrive.com/en/article/how-secure-is-my-data-in-pipedrive), [Backups](https://support.pipedrive.com/en/article/how-is-data-backed-up-in-pipedrive)

### Marketplace integrations

The Marketplace holds 500+ third-party and Pipedrive-built apps, installable in one click on any plan. The features page sorts them into nine categories; the Marketplace itself is browsed by revenue-cycle stage. In the first table, example apps are placed under the nearest category by this review, not by Pipedrive.

| Features-page category | What Pipedrive says it covers | Apps named on Pipedrive's pages |
| --- | --- | --- |
| Accounting and invoicing | Automates finance processes and pipeline management | QuickBooks, sevdesk |
| Chatbots | Automates conversations with visitors, leads and customers | Intercom, LiveChat, Crisp, WhatsApp Business |
| Email marketing | Manages opt-in lists and sends targeted bulk email | Mailchimp, Outfunnel, SendPulse, Klenty, Autopilot |
| Lead generation | Fills the pipeline from websites, social media and events | Surfe, Jotform, LinkPort, Leadfeeder, Facebook Lead Ads, Outgrow, Livestorm, Apollo.io |
| Phone solutions | Places, records, tracks and analyzes calls | Aircall, JustCall, CloudTalk, Kixie, CallHippo, Ring.io |
| Proposal contracts | Creates and tracks proposals and contracts | PandaDoc, DocuSign |
| Remote work | Video calls and meetings | Zoom, Microsoft Teams, Google Meet |
| Resource management | Backs up and exports data, merges or removes duplicates |   |
| Task management | Tracks goals, projects and tasks | Asana, Trello, monday |

| Marketplace mechanic | Details |
| --- | --- |
| Collections by revenue-cycle stage | Attract new leads · Qualify my leads · Nurture my leads · Communicate with leads · Manage contracts · Enable payments and tracking · Manage my projects · Automate my pipeline and data · Manage my accounts · Support my customers · Other use cases |
| Functional tags on apps | Accounting & invoicing, Analytics, Bots & messaging, Customer support, Integration platforms, Lead generation, Marketing automation, Phone solutions, Proposals & contracts, Task management, Video calls & solutions |
| Recommended apps for you | AI suggestions from tools in use and similar companies |
| Natural-language search | AI-powered Marketplace search |
| Installed-app page | Marketplace information, granted permissions, onboarding guides, support details, app settings, user management, uninstall |
| In-product surfaces | App panels in deal and contact detail views; app actions |
| Build your own | Public or private apps through the API and Developer Platform |

Sources: [Features page](https://www.pipedrive.com/en/features) · [Marketplace](https://www.pipedrive.com/en/marketplace) · KB: [Marketplace popular categories](https://support.pipedrive.com/en/article/pipedrive-marketplace-popular-categories), [Marketplace apps and integrations](https://support.pipedrive.com/en/article/pipedrive-marketplace-apps-integrations)

### Mobile app

The iOS and Android apps are included on every plan and mirror the web CRM, with a few phone-only features: Focus view, Nearby, caller ID, scanners, audio notes and offline mode.

| Feature | What it does | iOS | Android |
| --- | --- | --- | --- |
| Focus view | Opening screen with the day's most pressing items: overdue activities and deals, unread email count, nearby count, activities and expected closes for today and the coming week | Yes | Yes |
| Nearby view | Map of deals, organizations and people near the current location; filters, including address custom fields; opens the address in a navigation app | Yes | Yes |
| Calling and call logging | Calls from the app, logged as activities | Only in-app outgoing calls logged | Yes |
| Caller ID | Identifies incoming callers that match contacts and links the call to deals and activities | Yes | Yes |
| Web-to-mobile calling | Click a number in the web app and complete the call on the phone | Yes | Yes |
| Texting from the app | Opens the phone's messaging app with the contact's number pre-filled | Yes | Yes |
| Pipeline, activities, calendar and contacts views | Core list and board views with filtering | Yes | Yes |
| Detail view of deals and contacts | Full record with notes, files and history | Yes | Yes |
| Statistics dashboard | Sales statistics on the phone | Yes | Yes |
| Email sync widget | Unread synced mail from the Focus view | Yes | Yes |
| Offline mode | Move deals, add notes and activities offline; changes sync when the connection returns | Yes | Yes |
| Audio notes | Record a voice note on an activity, deal or contact, with optional transcription | Yes | Yes |
| Note scanner | Photographs handwritten or typed notes and transcribes them onto a deal, lead, project, person or organization | Yes | Yes |
| Business card scanner | Scans a card into a contact, including multiple phones and emails; card image saved to the contact timeline | Yes per the scanner article; the KB comparison table lists Android only | Yes |
| Photo and file upload | Attach a picture or file to a deal or contact | Yes | Yes |
| Phone contact importing | Brings phone contacts into Pipedrive | Yes | Yes |
| Push notifications | Activity reminders and updates | Yes | Yes |
| Manual data sync and landscape view | Force a sync; rotate the app | Yes | Yes |
| Leads Inbox, Live Chat and Projects on mobile | Leads on both platforms; Live Chat takeover from the app; Projects on Android with iOS "coming soon" | Partial | Yes |
| Real-time sync across devices | Mobile changes appear in the web app automatically | Yes | Yes |

Sources: [Features page](https://www.pipedrive.com/en/features) · [Mobile CRM](https://www.pipedrive.com/en/crm/features/mobile-crm) · [Sales app](https://www.pipedrive.com/en/products/sales/sales-app) · KB: [Mobile app features](https://support.pipedrive.com/en/article/what-features-do-the-mobile-apps-have), [Focus view](https://support.pipedrive.com/en/article/focus-view-in-the-mobile-app), [Nearby](https://support.pipedrive.com/en/article/the-nearby-feature), [Offline mode](https://support.pipedrive.com/en/article/do-the-mobile-apps-work-offline), [Business card scanner](https://support.pipedrive.com/en/article/card-scanner-mobile), [Note scanner](https://support.pipedrive.com/en/article/note-scanner-in-the-mobile-app), [Audio notes](https://support.pipedrive.com/en/article/audio-notes-in-the-mobile-apps)

### Recent releases

Pipedrive's [product updates](https://www.pipedrive.com/en/product-updates) page logs releases monthly; the last eleven months show the heaviest investment in Projects, Automations, AI (Nova, MCP) and email. Pipedrive notes that "coming soon" items are planned but not guaranteed.

| Month | Area | Released |
| --- | --- | --- |
| Sep 2026 | Nova | Nova meeting intelligence: pre-call briefs, recording and transcription, ready-to-approve CRM updates |
| Sep 2026 | Projects | Project import through Import2 from Asana, Monday, Basecamp and others |
| Sep 2026 | Automations | Global admins edit any automation; activate an automation for a whole team; ownership transfer with notifications; safeguards when deactivating a user who owns automations |
| Sep 2026 | MCP | Manage products and leads from an AI assistant; company-level switch for MCP access in Company settings |
| Sep 2026 | Email | Send from verified Gmail aliases; send-failure reasons with instant retry; two-way email archiving with Gmail |
| Sep 2026 | Insights | Average aggregation for custom numeric and monetary fields; multiple filters on one field; role-based dashboard templates for reps and managers |
| Sep 2026 | Web Forms, Contacts, Settings | Owner preserved on form resubmission; admin-configurable duplicate matching rules; phone number editable in profile |
| Aug 2026 | Deals | Stage names with day counts on the deal progress bar; toggle to show closed deals in pipeline and list views; admin toggle for AI scoring visibility |
| Aug 2026 | Web Forms | JavaScript variables into hidden fields; form ID, referral URL and landing page capture; UTM parameter and cookie value capture |
| Aug 2026 | Email | Failed-send visibility with live retry; auto-populated deal participants; personalized hyperlinks in templates |
| Aug 2026 | Activities, Sequences | Activities added by automations are marked; higher Sequence enrollment limits |
| Jul 2026 | Automations | Email sender control; copy and paste steps in the canvas; preview email templates |
| Jul 2026 | Integrations, Activities | WhatsApp chat inside Pipedrive; customizable activity fields that capture sales outcomes |
| Jun 2026 | Projects, Integrations, Settings | Project tasks beside sales activities; query and update CRM data from an AI assistant; copy access settings from another user; choose whether hidden activities and notes show in detail views |
| May 2026 | Projects, Automations | Advanced field settings for projects; proactive failure alerts and automation health tracking |
| Apr 2026 | Projects, Automations, Mobile | Post-sale performance in Insights; Projects for Android; better project–deal linking; bulk actions; automatic failure alerts; consistent secure login across devices |
| Mar 2026 | Projects, Activities | Task automation inside Projects; project import and export; emails logged as activities at send time; bulk activity creation from Sales Inbox and list views |
| Mar 2026 | Data enrichment, Data restoration | Hide enrichment default fields; move to a new enrichment provider; revert bulk changes |
| Feb 2026 | Insights, Deals, Login, Filters | "Does not contain" report filter; link contacts to deals; add email recipients and past-email contacts as deal participants; participants on activities; remembered login email; filter display options in pipeline view |
| Jan 2026 | Deals, Mobile | Add deal participants to emails; refreshed iOS design; business card scanner |
| Dec 2025 | Mobile, Data enrichment, Import | Pinned notes, agenda widget, share function; enrichment credit top-ups and bulk enrichment; improved contact import |
| Dec 2025 | Deals, Leads, Login, Integrations | Contact info at a glance; participant management; files on leads; account recovery; Zendesk and Mailchimp integration updates |
| Nov 2025 | Mobile, Email, Filters, Sequences | Activity priority labels; assignment push notifications; missing-attachment warning; thread status; quick filters; Sequences item limits, automatic signatures, auto-unenrollment, stop or skip, bulk unenrollment |

### Plans and pricing

Pipedrive sells four plans from $14 to $79 per seat per month on annual billing ($24 to $99 on monthly billing), with a 14-day free trial and no free plan. The same numbers apply in USD, EUR and GBP; prices exclude VAT. In 2025 Essential became Lite, Advanced became Growth, Professional and Power became Premium, and Enterprise became Ultimate.

| Plan | Annual billing, per seat per month | Monthly billing, per seat | Pipedrive's positioning | Headline features |
| --- | --- | --- | --- | --- |
| Lite | $14 | $24 | Organize your sales in one simple workspace | Lead, calendar and pipeline management; AI report creation; 500+ integrations; Nova meeting intelligence |
| Growth | $39 | $49 | Automate emails and follow-ups | Full email sync with tracking; automations and Sequences; subscriptions and forecast reports; meeting scheduler and contacts timeline |
| Premium ("most popular") | $59 | $79 | Full-cycle sales tools | LeadBooster and automatic assignment; custom scoring and company enrichment; AI email tools, team inbox, multi-account sync; Smart Docs with e-signatures; required, formula and pipeline-specific fields; custom permissions |
| Ultimate | $79 | $99 | Complete suite | Security rules and alerts; phone and email enrichment; sandbox account; extended phone support; partnership discounts |

#### Usage limits

| Limit | Lite | Growth | Premium | Ultimate |
| --- | --- | --- | --- | --- |
| Leads and deals per company (cap 300,000) | 2,500 × seats | 5,000 × seats | 15,000 × seats | 20,000 × seats |
| Custom fields per company | 30 | 100 | 300 | 500 |
| Reports per seat | 15 | 50 | 250 | 500 |
| Active automations per company | — | 50 | 150 | 250 |
| If/else steps per automation | — | 3 | 10 | 20 |
| Sequences per company | — | 5 | 25 | 50 |
| Email syncs per seat | — | 1 | 3 | 5 |
| Team inboxes per company | — | — | 1 | 5 |
| Teams per company | — | — | 15 | 25 |
| Custom visibility groups per company | — | — | 15 | 25 |
| Custom permission sets per company | — | — | 15 | 25 |
| Custom scores per company | — | — | 5 | 10 |
| Data enrichment credits per company | — | — | 100 | 500 |
| Formula fields per company | — | — | 10 | 10 |
| API tokens per 24 hours (cap 100 million) | 30,000 × seats | 60,000 × seats | 150,000 × seats | 210,000 × seats |

When a limit is reached Pipedrive blocks new additions but deletes nothing. The options are to archive or delete items, buy a top-up, or upgrade. Excess deals created by automations, LeadBooster, the API or an import go to the deals waitlist or the import skip file.

#### What each plan adds

| Pricing-page heading | On every plan (Lite) | Added in Growth | Added in Premium | Added in Ultimate |
| --- | --- | --- | --- | --- |
| Manage deals | Deal management, customizable pipelines, deal card customization, deal rotting, import and export, merge duplicates, products catalog, custom fields | Product subscriptions and installments; important fields | Required fields; formula fields; pipeline-specific fields; Projects included | — |
| Generate, qualify and nurture leads | Leads Inbox, Pulse toolkit, Sales feed | Sequences | Custom scoring; firmographic enrichment; LeadBooster included | Email and phone enrichment |
| Track communications | People and organizations, mentions and comments, file attachments, contacts map, calendar and activity management, reminder alerts, email inbox (Smart Bcc) | Two-way email sync, templates and signatures, merge fields, open and click tracking, group emailing, email scheduling, video call scheduling, meeting scheduler, contacts timeline | Multiple email accounts, team inbox, full general-availability scheduling links, Smart Docs with e-signatures included | — |
| Automate and grow | Notifications, API access, webhooks, bulk activity | Automations, delay and wait-for steps, if/else steps, automation dashboard | Automatic assignment | — |
| Pipedrive Nova meeting intelligence | Pre-call briefs, call recording with summaries and transcripts, CRM data sync | — | — | — |
| Other AI-powered features | AI report creation, smart-app recommendations, Marketplace search | — | Email creation, email summarization, AI notifications | — |
| Insights and reports | Default dashboard, shareable dashboard links, report collaboration, deal reports, activity reports, company and user goals | Product and deal revenue forecast reports, forecast view | Custom dashboards, dashboard collaboration, custom field reports, team filters and goals | — |
| Privacy and security | SAML SSO, 2FA and 2FA enforcement, SOC 2, AES-256, visibility options, security dashboard, hourly backups, default visibility group and permission sets | — | Custom visibility groups, custom permission sets | Security alerts, security rules, device history and audit log |
| Mobile apps and integrations | iOS and Android apps, Marketplace, contact and calendar sync, Chrome extension for Gmail, real-time sync, nearby contacts, caller ID, call logging, web-to-mobile calls, business card scanner, Pipedrive MCP | WhatsApp integration | — | Partnership discounts |
| Get more from Pipedrive | 24 languages, help center, chatbot support, 24/7 live chat support, personalized onboarding, Developer Center access | Eligible for a dedicated customer success manager | Phone support | Extended phone support (Mon–Fri 07:00–23:00 CET/CEST), non-developer sandbox |

#### Add-ons

| Add-on | Starting price per month | Pricing basis | Lite and Growth | Premium and Ultimate |
| --- | --- | --- | --- | --- |
| LeadBooster | $32.50 (annual) or $39 (monthly) | Per company; includes 10 Prospector credits a month | Paid add-on | Included |
| Smart Docs | $32.50 | Per company | Paid add-on | Included |
| Projects | $16 | Per seat | Paid add-on | Included |
| Campaigns | $13.33 | By subscriber count; Standard and Premium tiers | Paid add-on | Paid add-on |
| Web Visitors | $41 | By identified organizations per month | Paid add-on | Paid add-on |

Other commercial terms on the pricing page: annual billing saves up to 42%; payment by credit card, debit card or PayPal depending on country; unlimited colleagues can join a trial; implementation is free on plans above $400 a year; a dedicated customer success manager is for qualifying customers only, and the onboarding page cites spend above $1,000 a month; the Knowledge Base's features-by-plan table lists live chat support from Growth, not from Lite as the pricing page does.

Sources: [Pricing](https://www.pipedrive.com/en/pricing) · KB: [What's new in Pipedrive plans](https://support.pipedrive.com/en/article/new-pipedrive-plans), [Usage limits](https://support.pipedrive.com/en/article/usage-limits-in-pipedrive), [Features by plan](https://support.pipedrive.com/en/article/what-features-do-the-pipedrive-plans-have)

### What the screenshots show

This section covers 39 images: 19 from pipedrive.com marketing and product-update pages and 20 real-interface screenshots from Knowledge Base articles. They confirm the feature claims above and add interface detail the text leaves out. Several marketing pages (Smart Docs, Web Visitors, LeadBooster, WhatsApp) carry illustrations only, so those rows rely on Knowledge Base screenshots.

**Deals pipeline**

- **Where it appears:** [Pipeline management](https://www.pipedrive.com/en/features/pipeline-management), homepage
- **What it shows:** Dark left rail with icons for Pulse, Deals, Activities, Campaigns, Mail (unread badge), Contacts, Insights, Products. Three view toggles (pipeline, list, forecast) and a green "+ Deal" button. Each stage column shows total value and deal count. Cards show title, organization, owner avatar, value, a colored label bar and an activity-status icon: green arrow for a planned activity, red for overdue, yellow triangle for none. A rotting deal turns red with a "3d" badge

**Deal detail view**

- **Where it appears:** KB [Deal detail view](https://support.pipedrive.com/en/article/deal-detail-view)
- **What it shows:** Header with owner, follower count and Won / Lost buttons. Stage progress bar showing days in each stage. Left sidebar: Summary (score, "Add deal to sequence", value, product count, ACV / ARR / MRR, organization, person, expected close date, probability, labels), Details, Person. Main tabs: Notes, Activity, Call, Email, Files, Documents, Invoice. "Focus" lists upcoming activities; "History" filters by notes, activities, emails, files, documents, invoices, engagement and changelog, with before-and-after values per change

**Notifications panel**

- **Where it appears:** Homepage hero, [AI notifications](https://www.pipedrive.com/en/products/ai-crm)
- **What it shows:** "Next best action" card with deal, value, owner, stage progress and an Opportunity Meter rated High, plus a suggested action button ("Schedule call"). "Better opportunity" card. "Your progress": daily rings for tasks, calls and activities; monthly new deals, won deals and revenue forecast with change arrows

**Pulse feed**

- **Where it appears:** [Lead management](https://www.pipedrive.com/en/products/sales/leads)
- **What it shows:** Three tabs (Follow-ups, Overlooked deals, Opportunities), a "Today 1/3" completion counter, and cards typed by icon (reply, calendar, email) with a done checkbox, deal value and stage bar. Setup asks for all pipelines and stages or specific ones

**Sequence canvas**

- **Where it appears:** [Sales sequences](https://www.pipedrive.com/en/products/sales/sales-sequences)
- **What it shows:** Dotted canvas starting at "Deal added to sequence". Steps labeled by day ("Day 1: Email task, Intro email template"). The "+" menu offers two step types: Add activity, and Email task ("create an email to be sent manually")

**Scores setup**

- **Where it appears:** KB [Scores](https://support.pipedrive.com/en/article/scores)
- **What it shows:** Name, description, target item (Deals), target pipeline. Note on screen: only one score can be active per pipeline

**Data enrichment card**

- **Where it appears:** [Pulse](https://www.pipedrive.com/en/products/sales-prospecting-software)
- **What it shows:** Person card filling title, company, email, location and social media

**Leads Inbox**

- **Where it appears:** KB [Leads Inbox](https://support.pipedrive.com/en/article/leads-inbox)
- **What it shows:** Table with title, contact person, organization and labels (Warm, Hot lead, Cold, Website leads). Inbox / archive toggle, "+ Lead", label and owner filters. Side menu groups LeadBooster (Live Chat, Chatbot, Web Forms, Prospector), Add-ons (Web Visitors) and Integrations (Messaging, marked beta; LinkedIn, marked new)

**Automatic assignment**

- **Where it appears:** KB [Automatic assignment](https://support.pipedrive.com/en/article/automatic-assignment)
- **What it shows:** "+ Rule" button, Rules and History tabs, and one rule list per event: Deal added, Deal updated, Lead added

**Automation action picker**

- **Where it appears:** KB [Automations](https://support.pipedrive.com/en/article/workflow-automation)
- **What it shows:** Searchable action list: Activity, Asana, Campaign, Deal, Email, Lead, Microsoft Teams, Note, Organization, Person, Project, Slack, Trello, Webhook

**Automations list**

- **Where it appears:** [Product updates](https://www.pipedrive.com/en/product-updates)
- **What it shows:** Per-automation Active toggle, a "7/7" badge for users it is active for, and an Edit entry tagged new

**Nova web app**

- **Where it appears:** KB [Nova](https://support.pipedrive.com/en/article/nova)
- **What it shows:** Own workspace with Meetings and History. Tabs for upcoming meetings and post-meeting actions. Meeting card with time, linked company, attendees, a three-bullet "Quick Prep" and a "Get fully briefed" button; a "Deal not linked" badge on unlinked meetings

**Nova update approval**

- **Where it appears:** [Nova](https://www.pipedrive.com/en/nova)
- **What it shows:** "Review captured updates" with per-item ticks: deal value $1500 → $2000, add new person, deal stage Discovery → Demo; then "Update to Pipedrive". Transcript shows timestamps and speaker roles

**MCP**

- **Where it appears:** [Product updates](https://www.pipedrive.com/en/product-updates)
- **What it shows:** External AI chat window beside the Products list with a "Pipedrive MCP" toggle

**AI report generation**

- **Where it appears:** [AI report generator](https://www.pipedrive.com/en/products/ai-crm/ai-report-generator)
- **What it shows:** "Generate report" sits at the top of the Insights "+ Create" menu, above report, goal and dashboard

**AI email writer**

- **Where it appears:** [AI email writer](https://www.pipedrive.com/en/products/ai-crm/ai-email-writer)
- **What it shows:** "Write my email" dialog: prompt box, tone and length dropdowns, "Copy to email"

**AI email summary**

- **Where it appears:** [AI CRM](https://www.pipedrive.com/en/products/ai-crm)
- **What it shows:** "Conversation summary" under the thread: summary, sentiment icon, readiness to buy (7 of 10 with a reason), action items

**Insights dashboard**

- **Where it appears:** KB [Dashboards](https://support.pipedrive.com/en/article/insights-dashboards)
- **What it shows:** Left tree of dashboards (shared with me, my dashboards) and goals. Top controls: viewer role, period, user, export. Stacked column chart of deals per month segmented by stage

**Forecast view**

- **Where it appears:** KB [Forecast view](https://support.pipedrive.com/en/article/the-forecast-view-revenue-projection)
- **What it shows:** Month columns with open, won and projected totals; date navigation, pipeline and owner filters; cards carry warning icons and a green stage bar

**Goal creation**

- **Where it appears:** KB [Goals](https://support.pipedrive.com/en/article/insights-goals)
- **What it shows:** Two-step dialog: entity (Deal, Activity, Forecast), then goal type (Added, Progressed, Won)

**Contacts timeline**

- **Where it appears:** KB contacts timeline
- **What it shows:** One row per organization or person with activity icons along a monthly axis and a "today" line; overdue items in red; controls for follow-up frequency and look-back period

**Products settings**

- **Where it appears:** KB [Products](https://support.pipedrive.com/en/article/products)
- **What it shows:** Enable toggle and default tax setting. The Tools and apps menu also lists Automations, Automatic assignment, Pipedrive AI, Phone calls, Webhooks, Documents, Import data, Export data, Merge duplicates and Restore data

**Projects**

- **Where it appears:** [Projects](https://www.pipedrive.com/en/features/projects)
- **What it shows:** Project page with phase bar, labels (On hold, Delivery), dates and the linked won deal. Plan table with a Done column, tasks and subtasks. Gantt by month with dependency arrows, a milestone diamond and an overdue bar in red. Project health card ("On track", "Create AI health summary"). Performance report as monthly columns with a user filter

**Campaigns editor**

- **Where it appears:** KB [Drag-and-drop editor](https://support.pipedrive.com/en/article/drag-drop-editor)
- **What it shows:** Content blocks: Title, Paragraph, List, Image, Button, Divider, Social, HTML, Video, Icons, Menu. Desktop and mobile preview toggle. Footer pre-filled with sender address merge tags and an unsubscribe link

**Smart Docs settings**

- **Where it appears:** KB [Smart Docs](https://support.pipedrive.com/en/article/smart-docs)
- **What it shows:** Tabs: My accounts, Company settings, Customization. Connected Google Drive account with storage location; note that PDFs are always stored in Pipedrive

**Web Visitors inbox**

- **Where it appears:** KB [Web Visitors](https://support.pipedrive.com/en/article/web-visitors-feature)
- **What it shows:** Company logo, name, city and country, industry and last visit; sort by quality; period and visitor filters; a count of 2,294 visitors

**Chatbot builder**

- **Where it appears:** KB [Chatbot](https://support.pipedrive.com/en/article/chatbot)
- **What it shows:** Three-step wizard (Theme, Profile, Template) with preset or custom colors and a live widget preview that books a 45-minute meeting in chat. Widget carries "by Pipedrive" branding

**Web Form builder**

- **Where it appears:** KB [Web Forms](https://support.pipedrive.com/en/article/web-forms)
- **What it shows:** Language picker (fixed after creation) and five templates: Contact us, Registration, Download material, Collect information with file upload, Blank. Preview form carries "by Pipedrive" branding

**Security dashboard**

- **Where it appears:** KB [Security dashboard](https://support.pipedrive.com/en/article/security-dashboard)
- **What it shows:** "Right now": users logged in, unique locations. "Last 7 days": new devices, new locations, security events, forced logouts. "Security assessment": counts of high- and low-risk issues with a link to improvements

**Security rules**

- **Where it appears:** KB [Security rules](https://support.pipedrive.com/en/article/security-rules)
- **What it shows:** Enforce 2FA by email, password strength checkboxes, minimum length, password expiry and reuse dropdowns, advanced rules, "Preview and enforce"

**Manage users**

- **Where it appears:** KB permission sets
- **What it shows:** Tabs: Users and access, Permission sets, Visibility groups, Team filters. A "0/2 custom permission sets in use" counter. Permission sets are grouped per app (for example "Deals admin")

**Mobile deal screen**

- **Where it appears:** [Mobile CRM](https://www.pipedrive.com/en/crm/features/mobile-crm), homepage
- **What it shows:** Deal with person and organization, stage stepper, value, Won / Lost buttons, Timeline and Details tabs, planned and past items with @mentions. Bottom navigation: Focus, Deals, Activities, Contacts, More

Two details surfaced only in screenshots: a LinkedIn integration marked "new" and a Messaging inbox marked "beta" in the Leads menu. The Restore data tool under Tools and apps is visible there too; it is documented in the Knowledge Base and listed in the CRM table.

### What reviews and articles say

Users rate Pipedrive 4.3 out of 5 on G2 (5,048 reviews) and 4.5 on Capterra (3,062 reviews), and the pattern is consistent: the visual pipeline and ease of use win praise, while reporting depth, automation logic, email limits on lower plans and add-on cost draw the criticism. Editorial reviewers reach the same verdict and add that marketing automation is thin.

| Source | Rating | Basis | Notes |
| --- | --- | --- | --- |
| [G2](https://www.g2.com/products/pipedrive/reviews) | 4.3 / 5 | 5,048 reviews, updated 2 Oct 2026 | Pipedrive's own [G2 page](https://www.pipedrive.com/en/g2) cites rank 3 of 1,097 in the CRM category. Many G2 reviews are in-app or invited and carry a small incentive |
| [Capterra](https://www.capterra.com/p/132666/Pipedrive/) | 4.5 / 5 | 3,062 reviews, updated 29 Sep 2026 | Ease of use 4.5, value for money 4.4, customer service 4.4, features 4.3. Sentiment 93% positive. 86% of reviewers are small businesses |
| [Fit Small Business](https://fitsmallbusiness.com/pipedrive-review/) | 4.38 / 5 | Editorial, updated 21 Jul 2025 | General features 4.8, ease of use 4.7, support 4.4, pricing 4.0, niche and advanced features 4.0 |
| [TechRadar](https://www.techradar.com/reviews/pipedrive) | Positive verdict | Editorial hands-on review | Strong core sales functionality judged to justify the price despite weak marketing automation |

| Feature area | What reviewers praise | What reviewers criticize | Where |
| --- | --- | --- | --- |
| Pipeline and deals | Kanban pipeline with drag-and-drop is the most praised feature; it forces every deal to have a next step and shortens pipeline reviews | An activity links to one deal only; an email links to one deal only; no filter by activity type inside a deal; any user can delete another user's activity | G2, Capterra |
| Ease of use and setup | Top theme on G2 (527 mentions) and Capterra (93% positive of 601); teams adopt it without a CRM admin | Advanced features have a learning curve (108 G2 mentions); custom fields, automations and reports take time to structure; too many pop-ups | G2, Capterra |
| Reporting and Insights | Quick standard reports and dashboards; goals hold reps accountable | Most common weakness: limited customization and segmentation, flexibility gated to higher plans, data exported to spreadsheets for deeper analysis; no report of when won revenue actually lands | Capterra (40% negative of 184), G2 |
| Automations and assignment | Saves substantial time; round-robin assignment plus automated first email cuts lead response to minutes | One trigger per automation forces duplicate workflows; no way to remove a record from another running automation; branching limits; advanced workflows complex to configure | G2 |
| Sequences | Valued for follow-up consistency | Enroll deals rather than contacts; multi-sequence email campaigns still need another tool | G2 |
| Email | Gmail and Outlook sync, templates, tracking and bulk personalized email | Sync not in the base plan; a second mailbox needs an upgrade; email editor lacks proper HTML and modular blocks; occasional sync failures; Google Calendar events miss meeting details | G2 |
| AI | Sales Assistant, email summarizer and enrichment save admin time | Recommendations are hit-or-miss and need review; not always clear what is AI and what is rules | G2 |
| Leads | Lead management is a top-six praise theme (190 mentions) | Leads lack the changelog and formula fields that deals have | G2 |
| Campaigns and marketing | Sales and marketing contacts in one place | Marketing automation is thin; one reviewer had double opt-in enforced across the whole account, stricter than local law required | TechRadar, Fit Small Business, Capterra |
| Integrations | Fifth most praised theme (194 mentions); PandaDoc, Zoom, Slack, calling apps | Some connections need Zapier or paid third parties; no native LinkedIn Ads link; occasional reconnects | G2, Capterra |
| Pricing | Seen as fair for small teams | Add-ons (LeadBooster, Campaigns) and tier gating raise the real cost (97 G2 mentions) | G2, TechRadar, Fit Small Business |
| Scale and data model | Fits small and mid-sized sales teams | Hits a ceiling for larger organizations: no custom objects, shallow native reporting, weak territory, quota and commission tools | G2, Fit Small Business |
| Support | Praised on G2 (169 mentions); 4.4 on Capterra | Inconsistent quality; some disputes over feature access after plan changes | TechRadar, Capterra |
| Mobile | Call logging and business card scanner singled out | Smart Docs cannot be created or opened on phone or tablet | Fit Small Business, G2 |
| Search, filters and API | Global search finds any record | Filter setup is unintuitive (36% negative of 84 on Capterra); API mixes v1 and v2 endpoints | Capterra, G2 |

Numbers in brackets are theme counts published by G2 and Capterra. Points without a number come from individual reviews and are single reports, not confirmed defects. G2 and Capterra totals may overlap through syndicated reviews, so they are not added together. Not read: Trustpilot blocked automated access, and Software Advice and GetApp were seen only as search snippets, so none of the three is used above.

Sources: [G2 reviews](https://www.g2.com/products/pipedrive/reviews) · [Capterra](https://www.capterra.com/p/132666/Pipedrive/) · [TechRadar review](https://www.techradar.com/reviews/pipedrive) · [Fit Small Business review](https://fitsmallbusiness.com/pipedrive-review/) · [Pipedrive on G2](https://www.pipedrive.com/en/g2) · [Pipedrive reviews page](https://www.pipedrive.com/en/pipedrive-reviews) · [Awards page](https://www.pipedrive.com/en/saas-awards-crm-reviews)

### Sources

Every section above lists the pages it draws on. The entry points are below; all were opened on 3 October 2026.

| Source | Used for | Link |
| --- | --- | --- |
| Pipedrive features hub | Category structure and names | [pipedrive.com/en/features](https://www.pipedrive.com/en/features) |
| Pipedrive pricing | Plan prices, 128-row comparison table, add-on prices | [pipedrive.com/en/pricing](https://www.pipedrive.com/en/pricing) |
| Pipedrive feature and product pages | Feature descriptions (75 pages, cited per section) | [pipedrive.com/en/products](https://www.pipedrive.com/en/products) |
| Pipedrive product updates | Releases November 2025 to September 2026 | [pipedrive.com/en/product-updates](https://www.pipedrive.com/en/product-updates) |
| Pipedrive Nova | Meeting intelligence | [pipedrive.com/en/nova](https://www.pipedrive.com/en/nova) |
| Pipedrive MCP server | AI assistant connection | [pipedrive.com/en/features/mcp-server](https://www.pipedrive.com/en/features/mcp-server) |
| Pipedrive Marketplace | App collections and categories | [pipedrive.com/en/marketplace](https://www.pipedrive.com/en/marketplace) |
| Pipedrive Knowledge Base | Limits, settings, plan availability, interface screenshots (159 articles read and 403 more scanned by title, cited per section) | [support.pipedrive.com](https://support.pipedrive.com/en) |
| Pipedrive plan change notice | Mapping of old to new plan names | [What's new in Pipedrive plans](https://support.pipedrive.com/en/article/new-pipedrive-plans) |
| G2 | 5,048 user reviews, pros and cons themes | [g2.com/products/pipedrive/reviews](https://www.g2.com/products/pipedrive/reviews) |
| Capterra | 3,062 user reviews, sub-ratings, pros and cons | [capterra.com/p/132666/Pipedrive](https://www.capterra.com/p/132666/Pipedrive/) |
| TechRadar | Editorial review and verdict | [techradar.com/reviews/pipedrive](https://www.techradar.com/reviews/pipedrive) |
| Fit Small Business | Editorial review and scores | [fitsmallbusiness.com/pipedrive-review](https://fitsmallbusiness.com/pipedrive-review/) |

Developer documentation opened for API facts: [Rate limiting](https://pipedrive.readme.io/docs/core-api-concepts-rate-limiting) · [API v2 overview](https://pipedrive.readme.io/docs/pipedrive-api-v2) · [Authentication](https://pipedrive.readme.io/docs/core-api-concepts-authentication) · [Webhooks v2](https://pipedrive.readme.io/docs/guide-for-webhooks-v2) · [About the API](https://pipedrive.readme.io/docs/core-api-concepts-about-pipedrive-api)

---

## Appendix 2 — Orgpuls platform admin specification (in full)

Source: "Orgpuls — Platform Admin Specification" of 25 September 2026. It is the specification of the admin, not a description of the code. Where it and the code differ, the code is the truth about today; report the difference (rule R2).

### Purpose and principles

The platform admin is Orgpuls' internal back-office for running the business: seeing growth, supporting customers, managing billing and keeping data handling defensible. It is not the customer-facing admin (daglig leder / HR settings) — that stays in the product.

Because Orgpuls holds psychosocial work-environment data and promises anonymity, the admin's design constraints matter more than its features:

- **Anonymity holds for staff too.** No admin screen ever shows individual answers or links a respondent to an answer. The 5-answer threshold applies to every admin view, export and impersonation session. It is a platform constant, not a setting.
- **Orgpuls is the data processor (databehandler).** Customer survey data is the customer's. Admin sees metadata (counts, dates, response rates, status) by default; content access requires customer consent.
- **Least privilege by role.** Support, finance and super-admin see different things.
- **Everything is audited.** Every admin read of customer-scoped data and every write is logged with who, what, when and a reason.
- **Data, not code.** Plans, question sets, tiltak library, email templates and feature flags are rows managed in the admin, not constants in the codebase.
- **EU residency** for the admin and its logs, same as the product.

### Access model

The admin runs as a separate surface (e.g. admin.orgpuls.com or a separate Next.js route group behind its own middleware), with its own role model and mandatory MFA.

| Role | Can see | Can do |
| --- | --- | --- |
| Super-admin | Everything below, admin user list, system config | Manage admin users, plans, feature flags, content, deletions |
| Support | Orgs, users, survey metadata, email logs, audit trail for an org | Resend invites, extend trial, reset MFA, request support access |
| Finance | Orgs, subscriptions, invoices, revenue reports | Change plan, credits, refunds, discounts |
| Read-only / analyst | Dashboards and aggregated analytics | Nothing |

Implementation notes for the stack:

- `platform_admins` table (user_id, role, mfa_enforced, created_by) separate from customer memberships; admin role is never derivable from a customer role.
- Admin reads go through server-side route handlers or security-definer functions that check admin role and write an audit row; never ship the service-role key to the browser.
- RLS stays on for all customer tables; admin access is a named policy path (`is_platform_admin(role)`), not a bypass.
- Response-level tables are unreachable from admin functions; admins query only aggregate views that enforce n ≥ 5.
- Session timeout (e.g. 30 min idle), optional IP allowlist, and admin logins alerted to a Slack/e-mail channel.

### Analytics

The dashboard should answer one question first: are trials turning into organisations that run surveys and act on them? Everything else supports that.

**Activation funnel** (per signup cohort, with drop-off between steps and median time per step):

1. Account created (org.nr entered, Brønnøysund lookup succeeded)
2. Employee list uploaded
3. First survey scheduled
4. First survey sent
5. Result unlocked (≥ 5 answers in at least one group)
6. Results viewed by daglig leder / HR
7. First tiltak created
8. Converted to paid

The "20 minutes to first send" promise on the site becomes a tracked metric: median time from signup to first survey sent.

**Business KPIs**

- MRR, ARR, net new MRR (new, expansion, contraction, churn)
- Paying orgs, trials active, trials expiring in next 7 days
- Trial → paid conversion rate, by cohort and by signup source
- Logo churn and revenue churn per month; cohort retention curves
- ARPA and distribution across price tiers (employee-count bands)
- Customers by industry (NACE from Brreg), size and fylke

**Product usage**

- Surveys sent per month (main vs. pulse), average response rate, reminder effectiveness
- Share of groups hidden by the threshold (signals orgs structured too finely)
- Tiltak created, with owner and deadline, and share closed on time
- Logins by role: daglig leder, HR, avdelingsleder, verneombud/tillitsvalgt
- Comments posted and share answered by leaders
- Feature adoption per org (årshjul, AMU report, risk assessment export)

**Marketing attribution** — store UTM source/medium/campaign and referrer on signup, and report signups, activation and paid conversion per channel, so the monthly marketing spend can be judged by paid customers, not clicks.

**Health score per org** (feeds the org list): last admin login, survey cadence vs. årshjul, response rate trend, tiltak activity, payment status. Flag at-risk orgs before renewal.

### Organisations

The organisation (customer company) is the primary object in the admin; almost every support and billing task starts here.

**List view**

- Search by name, org.nr, admin e-mail
- Filters: status (trial, active, past due, cancelled, suspended), price tier, employee band, industry, fylke, signup source, trial days left, health score
- Columns: name, org.nr, status, plan, employees, last survey sent, response rate, health, MRR, signup date
- Saved views, e.g. "trials expiring this week without a survey sent"

**Detail view**

- Header: Brreg data (name, address, NACE, employees registered), status, plan, health
- Users and roles in the org (link to user detail)
- Structure: departments/teams count, employee list size, groups below threshold
- Surveys: metadata only — type, dates, invited, answered, response rate, reminder count, delivery status
- Tiltak: count open/closed/overdue (titles only with support access)
- Billing: subscription, invoices, payment method status
- Timeline: signup, key activation events, plan changes, support actions, logins
- Internal notes and tags (lightweight CRM)
- Audit trail for this org

**Actions** (each requires a reason, all audited)

- Extend or reset trial
- Change plan, apply discount, mark as complimentary (e.g. pilots, partners)
- Suspend / reactivate (e.g. unpaid, abuse)
- Re-sync from Brønnøysund
- Transfer ownership to another user
- Merge duplicate orgs (same org.nr)
- Export org data (for the customer, on request)
- Delete org — scheduled with a grace period, confirmed by typing org.nr, super-admin only

### Users and support access

Keep two kinds of people strictly apart: **users** (people who log in — daglig leder, HR, avdelingsleder, verneombud) and **respondents** (employees who receive surveys). The admin manages users; respondents are visible only as counts and delivery status.

**User search and detail**

- Search by e-mail or name across orgs
- Memberships: which orgs, which role, invited by whom, when
- Last login, MFA status, auth method, pending invites
- Actions: resend invite / magic link, reset MFA, change e-mail, deactivate, remove from org, mark as admin contact for billing

**Respondents**

- Per survey: invited, delivered, bounced, answered (count only)
- Fix bounced addresses only via the customer, not by admin edit
- No lookup from respondent to answer, ever

**Support access (instead of free impersonation)**

- Customer grants access from their own settings, or approves a request sent from the admin
- Time-boxed (e.g. 24 or 72 hours), read-only by default
- Visible banner in the customer's app while active, and listed in their own audit log
- Inherits the 5-answer threshold and role scope of the user being viewed
- Every page view during the session is logged

**Personvern requests** — a queue for access, correction and deletion requests from users or respondents, with due dates (30 days) and status.

### Content management

Orgpuls' value sits in its content (the fixed question set, the tiltak suggestions, the legal references), so it needs versioned editing without deploys.

- **Question set** — versioned; a published version is immutable so year-over-year comparisons stay valid. Each question maps to a factor. New versions need a mapping from old questions to keep trends.
- **Pulse templates** — short sets drawn from the main question bank.
- **Tiltak library** — suggestions per factor and score band, with the "three suggestions" ranking logic configurable.
- **Legal references** — hjemmel per factor for the risk assessment and the Arbeidstilsynet report; flag each with a "last reviewed" date so law changes are caught.
- **E-mail and SMS templates** — invitation, reminder, verneombud notice, results ready, trial expiring, payment failed; Norwegian (bokmål first, nynorsk/English if offered), with preview and test-send.
- **Årshjul defaults** — suggested annual cadence per org size.
- **Help texts and in-app announcements.**

Every content change records author, date and version, and published content can be rolled back.

### Data, privacy and compliance

This section is what lets Orgpuls answer a customer's DPO or an Arbeidstilsynet-adjacent question with evidence rather than assurances.

- **Databehandleravtale (DPA)** — per org: version accepted, date, by whom; prompt re-acceptance when the DPA changes.
- **Retention** — each customer chooses how long raw responses are kept before reduction to aggregates, default 2 years; a job report showing what was purged and when.
- **Deletion queue** — org and user deletions with grace period, execution log and confirmation sent to the customer.
- **Exports** — customer data export on request (aggregates, tiltak, comments without identity), logged.
- **Audit log** — append-only, searchable by admin, org, action and date; covers admin actions, support-access sessions, role changes and exports. Retain longer than product data.
- **Anonymity guardrails** — monitoring that no query path returns n < 5; alert if an org's structure makes groups re-identifiable (e.g. a department of 5 with 5 answers split by segment).
- **Subprocessor register** — Supabase, Vercel, e-mail provider, payment provider, with region; source for the public list.
- **Incident register** — log of security incidents and personal data breaches with the 72-hour notification clock.
- **Backups** — last successful backup, last restore test.

Open point: cross-customer benchmarks (e.g. "your industry average") are valuable but need an explicit legal basis in the terms and a minimum of several orgs per segment. Treat as a later phase.

### Billing and payments

Pricing is per employee band (from 265 kr/month; 565 kr for 26–100 employees), no binding, verneombud and tillitsvalgte free, 30-day trial without card. The admin should model exactly that as data.

**Plan catalogue** — bands (min/max employees), monthly and optional annual price, MVA 25 %, included features, active/archived. Price changes create a new price version; existing customers keep theirs until migrated.

**Subscription lifecycle**

1. Trial (30 days, no payment method)
2. Active
3. Past due (payment failed, dunning running)
4. Suspended (read-only access to results)
5. Cancelled (runs to end of paid period)
6. Deleted (after retention period)

**Band reconciliation** — the employee list size decides the band. When an org crosses a band, flag it in the admin and notify the customer; decide whether upgrades apply automatically or at next period.

**Admin features**

- Subscription view per org: plan, band, next invoice, payment method status
- Invoice list, status, PDF, resend
- Failed payments and dunning status; manual retry
- Credits, refunds, one-off discounts, coupon codes (useful for marketing campaigns)
- Complimentary / partner accounts
- Revenue reports and export to the accounting system

**Norwegian B2B reality** — many customers will want invoice (EHF via PEPPOL) rather than card, especially municipalities and larger firms. Support both: card for self-serve, invoice on request or above a band.

### Communication and support

- **E-mail/SMS log per org** — every invitation, reminder and notice: sent, delivered, opened (if tracked), bounced, spam-complained. Most survey support tickets are "people didn't get it".
- **Deliverability overview** — bounce and complaint rates per sending domain; alert on spikes.
- **Lifecycle messaging** — trial onboarding and nudges (e.g. day 2 "upload your employee list", day 7 "no survey sent yet"), driven by funnel events, editable in the admin.
- **Broadcasts** — send an in-app banner or e-mail to a segment (all daglig ledere, all trials, one industry).
- **Support inbox link** — from the org detail to the ticket thread in whatever tool is used, and vice versa.
- **Feedback capture** — in-app feedback and NPS stored per org, visible in the admin.

### System operations

- **Job monitor** — scheduled sends, reminders, verneombud notices, result unlocks, retention jobs: queued, running, failed, with manual retry.
- **Integrations status** — Brønnøysund API, e-mail provider, payment provider, SMS; last success and error rate.
- **Feature flags** — global and per org, for staged rollouts and pilots.
- **Errors** — link to error tracking, filtered by org.
- **Maintenance mode and status banner.**
- **Admin user management** — invite, role, MFA status, deactivate (super-admin only).

### Web analytics

Web analytics covers orgpuls.com (the marketing site) and joins up with the product funnel in Analytics, so one view runs from first visit to paying customer.

**Traffic and sources**

- Visitors, sessions, pages per visit, bounce, by day/week/month
- Sources: organic search, paid, social, referral, direct, e-mail campaigns (UTM)
- Campaign view: spend (entered manually per channel), visits, signups, activated orgs, paid orgs, cost per paid customer
- Top landing pages and content performance (e.g. /lovkrav, /artikler, /bruksomrader) — which articles lead to signups
- Search Console data: queries, impressions, position for key terms (medarbeiderundersøkelse, arbeidsmiljøkartlegging)

**Conversion**

- Website funnel: visit → pricing or platform page → "Kom i gang" click → org.nr entered → account created
- Drop-off on the signup form, including failed Brønnøysund lookups
- Persona entry points: clicks on the four "Hvem er du?" cards (daglig leder, HR, avdelingsleder, verneombud) as a signal of who is arriving
- First-touch and last-touch source stored on the org at signup, so revenue can be attributed back

**Consent and tooling**

- Norwegian cookie rules require active consent for non-essential cookies. Build in-house and cookieless: page views go to a web_events table in Supabase, unique visitors via an IP + user-agent hash with a daily rotating salt, bot filtering by user-agent list and rate limits, Search Console imported nightly via API. Confirm legally that this needs no consent banner.
- Keep marketing-site analytics separate from in-product analytics; never track respondents in the survey flow.
- Dashboard lives in the admin (embedded or via API), not only in the vendor's UI.

### Marketing CRM

A simple CRM for campaigns, newsletters and promotions, built on the org and user data already in the admin. It extends the lifecycle messaging and broadcasts in Communication and support to prospects and marketing sends.

**Hard rule:** respondents (employees who answer surveys) are never contacts in the CRM. Only users (people who log in) and prospects who opted in.

**Contacts**

- Types: prospect (newsletter signup, contact form, event), trial user, customer user, former customer
- Fields: name, e-mail, company, org.nr, role (daglig leder, HR, leder, verneombud), source, consent status and date, tags
- Auto-linked to org and user records; activity timeline (e-mails received, opened, clicked, site visits after click)
- Import from CSV (with consent source required per row)

**Segments** — saved filters on contact and org data, e.g. "HR in orgs with 26–100 employees on trial", "customers who have not sent a pulse survey in 90 days", "verneombud users", "industry = helse".

**Campaigns and newsletters**

- Editor with Orgpuls templates (header, article blocks, CTA button), preview on mobile, test-send
- Types: newsletter, one-off campaign, promotion (with coupon code from Billing), product announcement
- Scheduling, A/B test on subject line
- Automated sequences triggered by events (signup, trial day X, conversion, churn) — the same engine as lifecycle messaging
- Reporting: delivered, opened, clicked, unsubscribed, bounced, and signups/conversions attributed via UTM

**Consent and compliance**

- Norwegian marketing law requires prior consent for e-mail marketing to individuals, with an exception for existing customers about similar products as long as opt-out is offered. Store consent basis per contact.
- Unsubscribe link and sender identity in every marketing e-mail; one-click unsubscribe honoured immediately
- Separate marketing and transactional sending (different subdomain/stream) so a campaign can never hurt survey invitation deliverability
- Suppression list across all sends

**Build vs. buy** — the contact store, segments and consent belong in Orgpuls' own database; the sending and editor can be a provider (e.g. an EU-hosted e-mail platform via API) to avoid building deliverability infrastructure.

### Ticketing

Ticketing is built in-house as a simple ITSM module in the admin, on the same stack and data model, so every request lands in one queue linked to the org and user it concerns. The site promises you talk to the people who build the product, so the tool should make fast, personal replies easy.

**ITSM model (kept simple)**

| Ticket type | Used for | Example |
| --- | --- | --- |
| Question | How-to and sales questions | "How do we add verneombud?" |
| Service request | Something we do for the customer | Extend trial, change plan, data export |
| Incident | Something is broken for a customer | Survey invitations not delivered |
| Problem | Root cause behind one or more incidents | E-mail provider rejecting a domain |

- Priority is set from impact (one user / one org / many orgs) × urgency (blocking a scheduled send or not), not picked freely
- Incidents can be linked to a problem; resolving the problem notifies all linked tickets
- Known errors with a workaround are published to the help centre and an in-app status banner
- Service requests map to admin actions (extend trial, export, plan change) that can be executed from the ticket and are logged in the audit trail
- Queues: Support, Billing, Sales, Personvern; routing by category, manual reassignment, escalation to super-admin
- Data model: `tickets`, `ticket_messages`, `ticket_links` (org, user, survey, invoice, problem), `ticket_events` for the timeline; RLS with support/super-admin roles only

**Channels in**

- Contact form on orgpuls.com (sales, general questions) — creates a ticket and a CRM prospect if consented
- In-app help button — captures user, org, role, current page and browser automatically
- E-mail to support@ / kontakt@ — converted to tickets, replies threaded
- No separate channel for respondents: anonymity questions go via their employer (daglig leder, HR or verneombud), who can raise a ticket

**Ticket fields and workflow**

- Status: new, open, waiting on customer, waiting on us, resolved, closed
- Priority: low, normal, high, urgent (urgent = survey send failing, data concern, security)
- Category: getting started, survey delivery, results and anonymity, tiltak, billing, bug, feature request, sales, personvern request
- Assignee, internal notes, @mentions, attachments
- Linked org, user, survey or invoice; ticket history shown on the org detail page
- Canned replies (macros) in Norwegian, editable in Content management
- Personvern-category tickets flow into the personvern request queue with its 30-day clock

**Service levels and reporting**

- First-response targets (business hours): urgent 4 h, high 1 day, normal 2 days, low 5 days; resolution targets (business days): urgent 2, high 5, normal 10, low 20; overdue highlighting
- Volume by category and by lifecycle stage (trial vs. customer), time to first response, time to resolve, reopen rate
- CSAT (one-click rating) after resolution
- Top categories feed back into help articles and onboarding fixes

**Self-service** — a help centre with articles managed in the admin; the help widget suggests articles before a ticket is created.

**Privacy** — tickets can contain sensitive work-environment details. Restrict ticket content to support and super-admin roles, apply the same retention and deletion rules as other customer data, and never attach survey answers to a ticket.

### Best practices

These practices from comparable survey and SaaS back-offices apply across the spec; each row names the section it affects.

| Practice | Applies to | What to do |
| --- | --- | --- |
| Block differencing attacks | [Data, privacy and compliance](#mmv9k7zhz3k.8515) | Enforce n ≥ 5 on the difference between overlapping filters (e.g. department vs. department minus one team), not only per view; suppress the smaller complement |
| Screen free-text comments | [Data, privacy and compliance](#mmv9k7zhz3k.8515) | Flag names and identifying details before leaders see comments; the admin is never a route to un-hide them |
| One event catalogue | [Analytics](#mmv9k7zhz3k.2700), [Web analytics](#mmv9k7zhz3k.14023), [Marketing CRM](#mmv9k7zhz3k.15567) | A single typed events table with consistent object_action names feeds the funnel, web analytics, CRM triggers and health score |
| Metric definitions in code | [Analytics](#mmv9k7zhz3k.2700) | MRR, activated, churned etc. defined once as SQL views versioned in git |
| Stripe as billing source of truth | [Billing and payments](#mmv9k7zhz3k.9982) | Mirror Stripe into the database via webhooks; EHF customers get a Stripe subscription with invoice collection, so there is one ledger |
| Multi-product keys | [Access model](#mmv9k7zhz3k.1353), [Organisations](#mmv9k7zhz3k.4564) | product_id on every admin table; org.nr as the shared customer key, enabling a cross-product customer view and cross-sell segments |
| Safe destructive actions | [Organisations](#mmv9k7zhz3k.4564), [System operations](#mmv9k7zhz3k.12162) | Preview the effect of deletes and bulk actions, require a second admin to approve, soft delete during the grace period |
| Separate admin identities | [Access model](#mmv9k7zhz3k.1353) | Admin accounts separate from customer logins, quarterly access review, logged break-glass access for emergencies |
| Seeded demo tenant | [System operations](#mmv9k7zhz3k.12162) | Develop and test admin features against Lumio AS / Kari Nordmann, never real customer data |
| Sending authentication | [Marketing CRM](#mmv9k7zhz3k.15567) | SPF, DKIM and DMARC on both sending subdomains; warm up the marketing stream gradually |
| List hygiene | [Marketing CRM](#mmv9k7zhz3k.15567) | Double opt-in for newsletter signups; stop mailing contacts with no engagement for 6–12 months to protect survey-invitation deliverability |
| Close the loop on tickets | [Ticketing](#mmv9k7zhz3k.17785) | Every resolved incident or repeated question becomes a help article or product fix; track ticket-to-article rate |

### Phasing

| Phase | Scope | Why now |
| --- | --- | --- |
| 1 — Run the business | Admin auth + roles + MFA, audit log, org list/detail, user lookup, trial extension, activation funnel, UTM attribution, e-mail log, job monitor. Web analytics (cookieless tool, sources, landing pages, website → signup funnel). Ticketing core: contact form, in-app help, e-mail-in, ticket types, statuses, queues, linking to org/user, canned replies | Needed to support first customers and judge marketing spend |
| 2 — Get paid properly | Plan catalogue, subscription lifecycle, invoices, dunning, band reconciliation, support-access flow, DPA tracking, deletion queue. CRM basics: contacts, consent, segments, newsletter and one-off campaigns, coupon codes. Ticketing: priority matrix, SLA targets, service requests executed from tickets, reporting, CSAT | Needed once conversions start and marketing moves beyond paid ads |
| 3 — Scale | Content versioning UI, health score, cohort retention, lifecycle messaging, broadcasts, feature flags. CRM automated sequences and A/B tests; campaign-to-revenue reporting. Ticketing: problem management, known errors, help centre with article suggestions | Needed when volume outgrows manual follow-up |
| 4 — Leverage the data | Benchmarks, industry reports, anonymity-risk alerts | Needs legal basis and enough orgs per segment |

### Open decisions for Tor

- [x] Payment provider: Stripe + EHF invoice via the accounting system (decided)
- [x] Band upgrades: notify the customer, who confirms before the price changes (decided)
- [x] Support access: admin requests, customer approves (decided)
- [x] Retention of raw responses: customer chooses the period before reduction to aggregates, default 2 years (decided)
- [x] Benchmarks: add to terms now, use later (decided)
- [x] Admin runs as a separate subdomain/app (decided)
- [x] Admin UI language: English (decided)
- [x] Admin is shared across products on the same stack, not Orgpuls-only (decided)
- [x] Web analytics: build in-house, cookieless, in Supabase (decided)
- [x] E-mail provider: one provider with separate transactional and marketing streams (decided)
- [x] CRM: build the campaign editor in-house; contacts and consent stay in Orgpuls (decided)
- [x] Ticketing: respondents' anonymity questions are routed via their employer, no anonymous channel (decided)
- [x] Ticketing first-response targets (business hours): urgent 4 h, high 1 day, normal 2 days, low 5 days; resolution targets (business days): urgent 2, high 5, normal 10, low 20 (decided)
- [x] Ticketing: build in-house as a simple ITSM module (decided)

---

End of file. A reader who has reached this line has read all of it: 183 features, 29 user flows, 45 system flows, the settings register, the data model, the phases, the coverage mapping and both appendices.
