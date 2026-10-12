# Customers › Help centre and support — gap analysis (SupportHub, 12 Oct 2026)

Design: `design-reference/sentral-simple/SupportHub.dc.html` (read in full, markup and script) and the change in
`SimpleCustomers.dc.html` (a third pill «Help centre and support», no count, `<dc-import name="SupportHub">` with **no**
`product`, `go` or `tab` prop; `this.props.tab` may open it as `support`). Shared data: `design-reference/sentral/project/admin-data.js`
(`nb`, `orgs`, `tickets` with `csat`, `channel`, `page`, `browser`, `problem: 'T-2316'`). Cross-references read for overlap:
`PlatformPlus.dc.html` (roles matrix row «Request support access» = Super-admin and Support; «Announcement in the app»; NPS;
feature requests «Shipped → the changelog is updated»), `DevHub.dc.html` (release checklist «Help centre articles updated»,
«Generated changelog», roadmap card «Help widget and help centre · Self-service 75 %»).

Rendered with `scripts/visual/design-simple.mjs` (and a scratch copy that types into inputs) into the scratchpad
`v3/support/`: 01-results, 02-widget-app, 03-widget-web, 04-centre, 05-channels, 06-portal, 07-assist, 08-status,
09-status-resolved, 10-portal-approved, 11-centre-ai, 12-results-write, 13-results-390, 14-widget-390, 15-widget-answer
(«invitasjon» typed), 16-widget-web-answer («hva er prisen»), 17-contact-match (Privacy + «921456789»).

Verdicts: **build** (existing backend or a new migration here) · **build+connector** (real only after a connection built
here, credentials in Vault) · **needs-orgpuls** (an Orgpuls command, event or repo change that does not exist) ·
**needs-decision** (only Tor can decide) · **cannot** (fabricated by nature or forbidden; the honest rendering is named).
Each row carries one verdict, the one that gates it; the «Needs» column names any second dependency.

## Overview

### What the design is
A customer-support cockpit in seven sub-tabs: self-service results (sessions, deflection, AI acceptance, CSAT, effort), an
embeddable help widget for the app and the public site, a help-centre editor with languages and SEO, the public contact form
and support mailboxes, a customer portal with approvals (support access, deletions, band changes), an AI assistant for agents,
and a public status page with incidents and a changelog. **Every figure is a literal in the script**: the six KPIs and their
deltas (`kpis`), the session-end split 41/30/9/20 (`ends`), the four search gaps (`G`), the six articles with views, solved
and helpful (`AR`), the widget's captured context (`captured`), the channel shares (`chans`), the portal's tickets and
approvals (`portalTickets`, `AP`), the AI usage (`aiStats`), the six status components, the incident and the changelog.
Values that look computed are not: «% solved» is `def / views` of hard-coded numbers; the widget's AI answer is chosen by
substring (`invit`, `grupp`, `pris` …) from a fixed list `ANS`; the contact form «matches» any nine digits to
`D.orgs[digits.charCodeAt(4) % D.orgs.length]` (921456789 → «Elvebakken kommune», not the Lumio AS the design implies); «AI:
improve from tickets» appends a fixed paragraph; every button only sets local state and flashes a toast.

### What exists today

| Source | Where | Useful for |
|---|---|---|
| Tickets: type, category, queue, status, impact × urgency → priority, channel (`in_app`, `email`, `contact_form`, `staff`), product, organisation, person, requester email, context (`role`, `page`, `browser`, `app_version`), SLA in business time, CSAT columns (`csat_score`, `csat_requested_at`, `csat_at`, `csat_token_hash`), `topic`, `request` (0056) | 0012 `app.tickets`, 0056 | Tickets created, channel shares, portal list, AI assist subject |
| Thread: `customer`, `reply`, `note`, `system`, `admin_action`; replies emailed per product through Brevo (`delivery_status`), customer email answers threaded when the subject names `[T-n]` and the sender is the requester (`worker_ticket_inbound`) | 0012, 0060, 0061, `mail-events`, `mail-run` | Approve and send, email threading |
| Problems and known errors (`type = 'problem'`, `problem_status`, `root_cause`, `workaround`), incidents linked by `problem_id`; `problem_resolve(problem, body)` replies to every open incident (emailed), resolves them, emits `problem.resolved` | 0012, 0051 | Incident card, «Resolve and notify» |
| Status banner per product: `status_notice_set(product, text, problem, maintenance)` pushed to Orgpuls with `settings.set_notice`; `app.status_notices_due()` clears a notice when its problem is resolved | 0044, 0057 | «Banner in app», «Banner removed» |
| Help articles: `slug` (globally unique), `title`, `body`, `category_key`, `locale` nb/nn/en, `status` draft/published, `version`, `problem_id`; `help_get()` (articles + 30-day `views`/`deflected` from `help_article_stats_daily`, `gaps` from `tickets.topic`, `article_rate`), `help_article_save` (needs `tickets:configure`); ticket links of kind `article` | 0012, 0023 | Help centre list and editor, «linked from N tickets» |
| Macros with per-locale versions; `macros_get` | 0012 | Draft grounding, canned replies |
| Personvern queue (restricted to admin and support permission sets) and `privacy_requests` with the 30-day clock | 0012 | Contact form «Privacy» route |
| Reports: `ticket_reports(days, product)` → created, previous (product-scoped since 0023), medians, SLA met, reopened, CSAT average (answered only) | 0012, 0023 | Tickets created + delta, CSAT |
| Lead capture: consent ledger, double opt-in, contact `forms` with org-number mapping and ticket creation (`worker_form_submit` → `app.ticket_from_capture`), chat playbooks incl. `live_chat`, business hours; seeded «Kontakt oss» form and «Snakk med oss» live chat | 0031 | Contact form, newsletter consent, live chat |
| AI: the «ai» integration row (`not_connected`), the `tickets:ai` right (support role has it), `app.ai_calls` (append-only call log: feature, subject, tokens, cost, outcome, never prompt or output) | 0029, 0012, 0042 | AI assist, AI usage |
| Public pages pattern: `/u/[token]` (unsubscribe) is a public path; it calls an edge function (`mail-events`) that uses the service role; the Next app holds no service key | `middleware.ts`, `lib/mail/public.ts` | CSAT page, public status page |
| Public collector pattern: `web-collect` (CORS to registered sites, 204 always, day-salted hashes, no IP, cookieless D-37) | 0066, `web-collect` | Help-session beacons |
| Booking links table (0 rows) | 0010 `app.booking_links` | «Book a call» |
| Old interface: `/tickets?tab=help` (`HelpCentre.tsx`: articles table, gaps with «Draft», a naive widget preview), `Problems.tsx` (resolve with a typed message; banner toggle disabled) | `app/(admin)/tickets` | Reuse of loaders and actions |

Local database (read-only): 6 help articles (5 published, 1 draft, all `nb`, two linked to problem T-2316), **0 rows in
`help_article_stats_daily`**, 25 tickets (channels in_app/email/contact_form), 3 CSAT scores from the seed and **0 CSAT
requests**, 0 `ticket_links` of kind article, 0 `topic` values, 5 macros, 1 open status notice, 2 problem tickets
(T-2316 investigating with 3 incidents, T-2329 resolved), 0 `ai_calls`, `mail_settings.inbound_domain` empty.

### Facts the design's world does not match
- **Orgpuls already has a help centre, and owns its content.** `/hjelp` in Orgpuls renders 21 articles from a registry
  (`lib/help/articles.ts`, categories start, malinger, resultater, anonymitet, regelverk, oppsett) whose text lives in Orgpuls'
  `/messages` (`hjelp.article.*`) — product copy under D-23 «Product content stays in Orgpuls». Sentral's `help_articles`
  (6 rows) are a separate set nobody outside Sentral reads. The design moves authoring to Sentral. **Decision.**
- **No widget exists anywhere.** Orgpuls' Hjelp has a help panel and a form (D-92, D-174): «there is no widget». Nothing serves
  `help.orgpuls.no/w.js`; no host `help.orgpuls.no` or `status.orgpuls.no` exists. Orgpuls' public site is `orgpuls.com`
  (and `se.orgpuls.com`, X-109); whether `orgpuls.no` is owned is unknown. D-28 puts Sentral's public pages on
  `go.owntheagenda.com`, which is not deployed either: the 0031 form and chat workers have **no public edge function**.
- **The Hjelp request loses the customer's words today.** Orgpuls' `submit_help_request` emits `support.requested` with the
  text in **`body`** (its registry, 0206: category, subject, body, page, browser, role, user_id, email, name). Sentral's
  `app.ticket_intake` (0056) reads **`payload ->> 'message'`**, so the ticket gets a subject and no customer message. Bug.
- **The contact form's topic is ignored.** Orgpuls' `submit_contact` sends `topic` (product, pricing, first_send, privacy),
  `name`, `email`, `organisation` (free text, not an org number), `message`, and no `subject` or `category`. Sentral therefore
  files every contact under category `sales` with subject «contact.submitted», **including privacy requests**, which land in
  the Sales queue (visible to sales) with no `privacy_requests` row and no 30-day clock. Bug.
- **Auto-replies reopen tickets.** `worker_ticket_inbound` threads any message from the requester whose subject names
  `[T-n]`; an out-of-office answer from the requester sets a resolved ticket back to `waiting_us`. No `In-Reply-To` /
  `References` matching, no `Auto-Submitted` / `Precedence` check. A first email to support@ (no `[T-n]`) is dropped, not
  made into a ticket.
- **Nothing writes the help statistics.** `help_article_stats_daily` has no writer; `tickets.topic` has no writer in any
  screen, so `help_get().gaps` is always empty. CSAT is never requested: no worker sets `csat_requested_at` or the token, and
  no public path takes an answer (the 0012 spec planned `csat_submit(token, score)`).
- **`help_articles` has no product.** One slug space for all products, one row per locale with no link between a bokmål
  article and its nynorsk or English version.
- **AI is not connected.** No edge function calls an AI provider; no Claude key exists in Vault; `ai_calls` is empty.
- **Account facts in AI answers contradict «articles only».** The design's AI answers say «Lumio AS har 14 forsinkede
  invitasjoner» and «Dere er i båndet 26–100 ansatte: 565 kr/mnd»; the AI summary cites «Mail log shows 451 greylisting on
  lumio.no». None of that is in an article, and Sentral cannot read Orgpuls' mail log (mail-events drops every Orgpuls event
  by rule 6).
- **Orgpuls has no «HR» role** (daglig_leder, avdelingsleder, verneombud) and **no support-access concept** (no command, no
  table, no decision entry). Skiftly, Avvikspunkt and Kursrom are product rows in Sentral with no repository or live
  application (dev-a), yet the Orgpuls status page lists Skiftly and Avvikspunkt as components.
- **The web tracker is cookieless (D-37).** A visitor id («anonymous · v_8f3a») and «3rd visit» for one visitor cannot exist;
  0031 counts a *company's* sessions only, and the IP-to-company provider is `not_connected`.

### The architecture the rules allow
The design assumes one Sentral-hosted widget that knows who is signed in to Orgpuls. Under rules 3 and 4 the platform reaches
a product only through `product-command`, and a product reaches the platform only through its events function (async,
batched by Orgpuls' dispatcher). A synchronous, identity-bearing call from the Orgpuls app into Sentral does not exist, and
adding one (an Orgpuls-signed identity token) is a new inbound trust path that needs Tor's rule change. The split that fits
the rules:

1. **Anonymous and content-only → Sentral public edge function** (`help-public`, like `web-collect`): article search and
   reading (published only), the AI answer (published articles only, cited), and session/outcome/helpful beacons. No identity,
   no IP, no cookie; CORS to registered origins; never loaded on Orgpuls survey routes (`/s/…`).
2. **Anything that needs the signed-in customer → Orgpuls renders it**, fed by `product-command` pushes (their open tickets,
   pending approvals) and answering through events (`support.requested` with a session/answer reference, an approval
   decision). The «Your open requests» block, the portal and the approvals live in Orgpuls' Hjelp.
3. **Public operational pages (status, changelog) → Sentral public route or edge**, on a host Tor chooses.

## Tab bar — SimpleCustomers third pill and SupportHub sub-tabs

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Pill «Help centre and support» (no count) | Third pill; opens SupportHub | Right to see it | `/customers` accepts `tab` accounts/tickets only (zod enum); pills are links (V-SCU-19) | build | `?tab=support`; gate on `tickets:see`; no count (design passes null) |
| Sub-tab bar (7 buttons) | Switches local state `sub` | — | — | build | Links `?tab=support&sub=` metrics, widget, center, channels, portal, assist, proactive (control substitution, D-06) |

## Support results

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| KPI «Help sessions» 3 410, «widget + help centre» | Literal | Count of help sessions (widget opens + help-centre visits) in 30 days, per product | Nothing records a session | build+connector | `help-public` beacons into a new `app.help_sessions`; in-app sessions only once Orgpuls embeds the widget (needs-orgpuls); «—» until the first day is collected |
| KPI «Self-service rate» 71 %, «solved without a ticket» | Literal | Sessions ended without a ticket within 24 h ÷ sessions | No sessions; no link session → ticket | needs-orgpuls | Sessions (above) + `help_session_id` in `support.requested` so a ticket can be tied to its session; definition of «solved» (decision 7) |
| KPI «Tickets created» 312, «fewer than last month» | Literal | Tickets created in 30 days for the product, previous 30 days | `ticket_reports(30, product).created` / `.previous` (product-scoped since 0023) | build | Needs `tickets:reports_others` (or a summary RPC like 0056's for `tickets:see`); sub-line from the sign of the delta |
| KPI «AI answers accepted» 64 %, «"Yes, solved"» | Literal | AI answers shown, «Yes, solved» clicks | No AI answers exist | build+connector | Claude via `help-public`; `app.help_ai_answers.accepted`; «—» while AI is off or not connected |
| KPI «CSAT» 4,7 / 5, «after resolution» | Literal | Average of answered CSAT in 30 days | `ticket_reports.csat_avg` (answered only) — but nothing ever asks: 0 requests | build+connector | CSAT request mail on resolve (mail-run, Brevo — built) + public answer page + token (column exists); wording (decision 6); «—» with «No surveys answered» until then |
| KPI «Customer effort» 1,8 / 5, «lower is better» | Literal | An effort score per resolved ticket | No column, no question | needs-decision | Tor decides whether to ask a CES question beside CSAT and its wording/scale; then `tickets.ces_score` (build) |
| KPI deltas (+12 %, +6 pts, −9 %, +8 pts, +0,1, −0,3) and their green colour | Literals, all green (even −9 % and −0,3, where lower is better) | The same figure for the previous 30 days; the direction that counts as good per KPI | Only tickets have a previous period | build | Delta only when the previous period was fully collected, else no delta; colour by «good direction» per KPI (tickets and effort: down is good) |
| «Where help sessions end» stacked bar | Four literal shares | Session outcome: solved by article, solved by AI answer, ticket created, left without answer | Nothing | needs-orgpuls | Session outcomes from `help-public` beacons; «Ticket created» needs `help_session_id` in `support.requested`; «Solved» needs the 24-h rule (decision 7) |
| Legend rows (4) with % | Literal | Same | Nothing | needs-orgpuls | As above; honest empty «No help sessions recorded yet» |
| «Top questions without a good article» header «30 days» | Static | — | — | build | — |
| Gap rows: question, «N searches · N tickets» | Four literals (`G`) | Search queries that found no or a weak article, counted; tickets on the same subject | `help_get().gaps` from `tickets.topic` — never written, always empty | needs-decision | Whether search text may be stored at all (decision 4). Without it: gaps from ticket categories/subjects with no published article in that category (build), showing tickets only, no «searches» |
| «Write article» → «✓ Draft created», toast «Draft created from N tickets» | Adds the question to a local list | Create a draft article from the gap; with AI, a body drafted from the tickets | `help_article_save(null, {title})` makes an empty draft (old screen does this) | build | Plain draft with the title = build; «from N tickets» body = build+connector (Claude, see AI assist); toast says what really happened |
| «Articles by results» header, «Solved = no ticket within 24 h» | Static | — | — | build | Text must match the definition actually computed (decision 7) |
| Article rows: title | Literal | Published articles of the product | `help_articles` (no product column) | build | `help_articles.product` |
| Article rows: views | Literal | Views in 30 days | `help_article_stats_daily.views` — no writer | build+connector | `help-public` view beacons (public help centre and widget); in-app Hjelp views need Orgpuls (embed or a `help.daily` count event) |
| Article rows: «N % solved» | `def / views` of literals | Views not followed by a ticket within 24 h ÷ views | `deflections` column, no writer | needs-orgpuls | Session id on the view and on `support.requested` (Orgpuls field) to know «no ticket followed» |
| Article rows: «N % helpful» | Literal | Helpful yes / (yes + no) | No column, no button exists | build+connector | `helpful_yes`/`helpful_no` in stats; a «Was this helpful?» control in the widget/help centre pages (Sentral-hosted) |
| Article rows: flag Rewrite / Review / Good (<65 % / <75 % / else) | Thresholds on helpful | Helpful % | — | build | Design thresholds kept as constants (decision 7 if Tor wants others); no flag when helpful has fewer than a minimum number of votes |
| Mobile (390) | Fixed 70/80/70/90 px columns crush the title to one letter per line (13-results-390) | — | V-SCU-20 pattern | build | Drop «views» and «helpful» columns under md or scroll horizontally |

## Help widget

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Mode toggle «In the app» / «On the website» | Switches the preview | — | — | build | A preview control only |
| Widget header: «Hei Kari» + «Lumio AS · Daglig leder · /malinger/ny»; website «Hei! Hvordan kan vi hjelpe?» + «orgpuls.com/pris · visitor» | Fixed person and page | In a preview: placeholders, or the seeded demo tenant (D-02 Lumio AS, Kari Nordmann) marked «Preview» | — | build | Preview badge; placeholders («[Fornavn] · [Organisasjon] · [Rolle] · [side]») so no real customer is shown as if signed in |
| Search input «Hva lurer du på?» | Local substring match | Full-text search over published articles of the product and locale | Nothing (old screen: 5-letter prefix match) | build | `search_vector` on `help_articles` (Norwegian/English config); `help_search` RPC for the admin preview, `help-public` for the live widget |
| AI answer card «AI answer from our articles» + text + «Source: …» | Picks one of six fixed answers by keyword; answers contain account data | Answer generated only from the retrieved published articles, citing the article used | No AI | build+connector | Claude with the articles as `document` blocks and `citations: {enabled: true}`; no answer when nothing is cited (show «Talk to us»); **never account data** («14 forsinkede invitasjoner», «båndet 26–100») — that would break «articles only» and rule 6 |
| «Yes, solved» → toast «Marked solved · counted as self-service» | Clears the input | Answer accepted → session outcome | — | build+connector | Beacon `accepted` on `help_ai_answers`; in the admin preview the button does not count (preview) |
| «Talk to us» (in the answer card) → «Ticket created · the AI answer is attached» | Toast | A ticket that carries the AI answer given | `support.requested` exists, without an answer reference | needs-orgpuls | `help_answer_id` (and `help_session_id`) added to Orgpuls' `support.requested` fields; Sentral attaches the answer text (generated from articles, not personal) as a system line |
| «Suggested for this page» (3 items) | Fixed titles | Published articles mapped to the current app path | No mapping column | build | `help_articles.app_pages text[]` (paths checked like Orgpuls' `HELP_PAGE_PATTERN`, never `/s/…`) |
| «Popular questions» (website, 3 items) | Fixed titles | Most-viewed published articles on the website surface | No views | build+connector | Views from `help-public`; until then, newest published articles or omit the block |
| «Your open requests» «T-2312 · Utvide prøveperioden · Waiting on us» (only with «Show open requests») | Fixed row | The signed-in user's organisation's open tickets | Tickets per organisation exist in Sentral; the widget has no identity | needs-orgpuls | Orgpuls renders it from a pushed list (`support.tickets_sync` command); preview shows the demo tenant's real tickets |
| Action buttons, app: «Talk to us» (toast «Ticket created with page, role and browser attached»), «Book a call» | Toasts | Ticket with context; a booking link | `support.requested` carries page, browser, role ✓; `booking_links` table, 0 rows | needs-orgpuls | Talk to us = Orgpuls' existing Hjelp request (with the session field); Book a call = a booking link (decision 17) |
| Action buttons, website: «Book a demo» («→ Sales queue + CRM lead»), «Contact sales» («lead created with consent») | Toasts | `demo.requested` → lead (D-20 ✓); `contact.submitted` → ticket + lead ✓ | Both event paths exist | needs-orgpuls | Orgpuls' website must open its demo/contact flow from the widget; «with consent» needs `consent` in `contact.submitted` |
| «Sent with every ticket from the widget» — User «Kari Nordmann · Daglig leder» | Literal | Name and role | `support.requested` has `name`, `role` ✓ → ticket person/context | build | Rendered from a real ticket or as field names in the preview |
| — Organization «Lumio AS · 921 456 789 · 26–100» | Literal | Tenant → organisation, org number, band | Tenant → organisation ✓ (`account_products`), org number ✓, band from the subscription ✓ | build | Joined at display time from Sentral, not «sent» |
| — Plan and status «Active · Orgpuls + trial Skiftly» | Literal | Subscriptions per product | ✓ (`customer_detail.subscriptions`) | build | — |
| — Page «/malinger/ny» | Literal | Path without query | ✓ `page` | build | — |
| — Last error «none in 24 h» | Literal | Last client/server error for this user or org | Nothing | needs-orgpuls | An error code in `support.requested` (code only) or Sentry (build+connector, dev-a); «—» until then |
| — Browser «Chrome 129 · macOS» | Literal | User agent class | ✓ `browser` | build | — |
| — App version «v2.14.0» | Literal (also `D.products[0].version`) | The build the user ran | Orgpuls has no version (package.json 0.1.0, no tags) | needs-orgpuls | Orgpuls adds its deploy SHA (e.g. `VERCEL_GIT_COMMIT_SHA`) as `app_version`; Sentral already maps `app_version` |
| — Website: Visitor «anonymous · v_8f3a» | Literal | A persistent visitor id | Cookieless tracker (D-37), day-salted hash | cannot | Show «anonymous visitor»; no id |
| — Website: Page «/pris» | Literal | Page of the widget | `help-public` beacon page | build+connector | — |
| — Website: Source «Google Ads «lovkrav»» | Literal | UTM / referrer of the session | `web_sessions` UTM (0066) but no join from a widget ticket to a session | build+connector | The widget passes the day's session reference to the ticket; «—» when absent |
| — Website: Visits «3rd visit» | Literal | Visit count of this visitor | Cookieless; 0031 counts a company's sessions | cannot | «Nth visit» only for a resolved company (below), labelled as the company's |
| — Website: Company (IP lookup) «Bergheim Bygg AS» | Literal | IP → company at ingest (D-37), ENK excluded | `ip_company` provider `not_connected` | build+connector | IP-to-company provider (chosen per D-07), Brønnøysund cache (`web_companies`) |
| «Never sent: survey answers, comments or respondent identities.» | Static | — | True by contract (Orgpuls' registry refuses unlisted fields; D-34 tests) | build | Keep; the widget must never load on `/s/…` |
| Toggle «AI answers» — «Answer from published articles only» | Local toggle | A per-product setting the `help-public` answer path reads | — | build | `app.support_settings.ai_answers`; disabled with a reason while AI is not connected (wiring audit: the setting must have an effect) |
| Toggle «Show open requests» — «Logged-in users see their organization's tickets» | Local toggle | Setting read by the ticket push | — | needs-orgpuls | Effect only once Orgpuls renders the list; until then disabled with the reason |
| Toggle «Live chat in business hours» — «Mon–Fri 08–16, otherwise ticket» | Local toggle | Live chat, staff presence, business hours | 0031 chat (`live_chat` playbook seeded, presence, claim) and 0012 `business_hours` — no public chat edge | needs-decision | Tor decides whether to staff live chat (decision 12); then the chat edge (build) |
| Toggle «Load only after cookie consent» — «On the website; always on in the app» | Local toggle | A setting the website embed honours | — | needs-decision | The widget sets no cookie (cookieless like D-37); whether to gate it on the site's consent banner is Tor's call; the embed then reads the setting |
| Embed snippet `<script src="https://help.orgpuls.no/w.js" data-product="orgpuls">` | Static | A served script on a real host | No script, no host | needs-decision | Host and domain (decision 2); the script itself is build; Orgpuls must embed it and allow it in its CSP (needs-orgpuls) |
| Mobile (390) | Card is `width:380px; max-width:100%` | — | — | build | Fits; settings rows wrap |

## Help centre

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Category chips: All, Getting started, Survey delivery, Results and anonymity, Billing, Known problems | Filter | Categories with articles; «Known problems» = articles tied to a problem | `ticket_categories` (getting_started, survey_delivery, results_anonymity, billing …); `help_articles.problem_id` ✓ | build | «Known problems» filters `problem_id is not null`; Orgpuls' own six categories differ (decision 1) |
| «＋ Article» | Adds «Ny artikkel N» locally and selects it | Create a draft | `help_article_save(null, …)` needs `tickets:configure` (admin only) | build | Product, locale; right for support staff (decision 15) |
| Article row: title | Literal | Title per article group | ✓ | build | — |
| Article row: «category · Bokmål · Nynorsk» | Every third row claims Nynorsk (`i % 3`) | Locales that exist for this article | One row per locale, no link between them | build | `help_articles.group_id` (translation group) |
| Article row: «N views» | Literal | 30-day views | No writer | build+connector | As in Support results |
| Article row: helpful % (red under 65 %) | Literal | Helpful share | No data | build+connector | As in Support results |
| Article row: state Published / Draft | Derived from views (`a[2] ? 'Published'`) | `status` | ✓ `status` | build | — |
| Editor: title input | Edits local override | Title | ✓ | build | `help_article_save` with `version` for conflicts |
| Editor: language switch Bokmål / Nynorsk / English | Changes a highlight only (body does not change) | The article's version in that locale; create a missing one | Locale per row, no group | build | `group_id`; switching loads that locale's row or offers «Create nynorsk version» |
| Editor: «URL help.orgpuls.no/<slug>» | Slug from the title | Slug per product, public base URL | `slug` (globally unique, random md5 for new rows) | needs-decision | Host (decision 2); slug from title, unique per product and locale (migration) |
| Editor: body textarea | Local | Body (format) | ✓ `body` (plain text) | build | Markdown, sanitised when rendered publicly |
| Editor: «SEO title» input | Defaults to «title \| Orgpuls hjelp»; not editable in the prototype (no onChange) | Column | None | build | `help_articles.seo_title`; only meaningful once a public page renders it (decision 2) |
| Editor: «Show in app on page» select (/malinger/utsending, /resultater, /oppsett/ansatte) | Static options | App paths per article | None | build | `app_pages text[]`, validated path pattern; the list of Orgpuls pages could come from Orgpuls (optional) |
| Editor: «FAQ schema ✓» | Static claim | Structured data on the public page | No public page | cannot | Show only when a public page actually emits FAQPage JSON-LD for this article; otherwise omit |
| Editor: «· linked from 3 tickets» | Literal | Ticket links of kind `article` | ✓ `ticket_links` (0 rows locally) | build | Count; «Make article from answer» and «Write article» should create the link |
| Editor: «· last reviewed 3 weeks ago» | Literal | Review date | None (`updated_at` is not a review) | build | `reviewed_at`, `reviewed_by`, a «Mark reviewed» action |
| «AI: improve from tickets» → toast «Added a step based on 6 recent tickets» | Appends a fixed paragraph | The article + the staff replies of tickets linked to it → suggested edit | No AI; no links | build+connector | Claude; output is a suggestion shown as a diff the staff accepts, never published by itself; input limited to the article and staff replies (decision 5) |
| «Publish» → «Published to help.orgpuls.no and the in-app widget» | Toast | Status published | ✓ `help_article_save {status: 'published'}` | build | Toast names only where it really appears: Sentral's help-public now; Orgpuls' /hjelp only if decision 1 says Orgpuls renders Sentral's articles (then needs-orgpuls `help.articles_sync`) |
| Mobile (390) | Grid 80/70/80 px columns | — | — | build | Drop views/helpful columns under md |

## Contact form and email

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Card title «Contact form · orgpuls.com/kontakt» | Static | Which form is live where | Orgpuls' own form on orgpuls.com/kontakt (topics product, pricing, first_send, privacy; name, email, organisation, message) → `contact.submitted`; Sentral's 0031 «Kontakt oss» form exists but no public edge serves it | needs-decision | Which form is canonical (decision 11); the panel describes that one |
| Topic chips Support / Sales / Billing / Privacy | Local | The form's topics | Orgpuls' topics differ; Sentral ignores `topic` (bug) | build | Map Orgpuls' topics now (product → getting_started, pricing → sales, first_send → survey_delivery, privacy → personvern); the design's four topics need the Orgpuls form changed (needs-orgpuls) |
| «Organisasjonsnummer» input | Typed | Org number field on the public form | Orgpuls' form has free-text «organisation»; 0031 forms map `organization.org_number` | needs-orgpuls | `org_number` field in Orgpuls' form and `contact.submitted` registry (or the 0031 form, decision 11) |
| Match banner «Lumio AS · existing customer · ticket gets the account attached» | Any 9 digits «match» a random org | Server-side match of org number to a customer, after submit | `app.organizations.org_number` (46 orgs, all with numbers) | cannot | On the public form this tells any visitor whether a company is a customer (enumeration). Match server-side at intake and attach the account; in the admin preview show «Attaches the account when the number belongs to a customer», or a preview lookup against real organisations clearly labelled as staff-only |
| «E-post» input, «Hva gjelder det?» textarea | Static | email, message | ✓ in Orgpuls' form | build | — |
| «Ja, send meg nyhetsbrev» checkbox | Static | Consent with the wording version → consent ledger (double opt-in) | 0031 `consent_write`, double opt-in ✓; Orgpuls' contact form has no box, `contact.submitted` has no `consent` | needs-orgpuls | `consent` (and text version/lang) in `contact.submitted`, as `demo.requested` already has |
| Route line, Support: «ticket in Support with the account attached. Suggested articles are shown before sending.» | Static | Routing; article suggestions on the form | Account attach ✓ (when matched); suggestions: none | needs-orgpuls | Suggestions on the form = Orgpuls' form calling `help-public` search |
| Route line, Sales: «ticket in Sales and a CRM lead; adds the contact with consent if ticked» | Static | Ticket + lead + consent | Ticket + lead ✓ (0031 `ticket_intake`); consent ✗ | needs-orgpuls | `consent` field (above) |
| Route line, Billing: «ticket in Billing with the latest invoices attached» | Static | Invoices of the account | Sentral has no invoices (Orgpuls' billing is not built: Fiken/Stripe pending, D-93/94) | cannot | Say «ticket in Billing with the account's plan and status attached»; invoices only when a billing source exists |
| Route line, Privacy: «privacy-request ticket with a 30-day deadline; visible to support and super-admin only» | Static | Personvern queue + `privacy_requests` row | Queue restriction ✓, 30-day clock ✓ — but Orgpuls' privacy contacts land in **Sales** today | build | Intake fix: topic privacy → category personvern, queue personvern, `privacy_requests` row (kind unknown → `access` with a check, or a new `unspecified` kind) |
| «Channels into tickets» rows: Help widget in the app 41 %, Website widget 14 %, Contact form 18 %, support@ 19 %, kontakt@ 6 %, Customer portal 2 % | Literals | Tickets by channel (and by inbound address) in 30 days | `tickets.channel` in_app / email / contact_form / staff ✓; no website-widget, portal or per-address split | build | Shares over 30 days from `tickets.channel`; extend the channel check (`website_widget`, `portal`, `chat`) and store the inbound address; a channel with no tickets shows 0 % or is listed only once it exists |
| Channel row descriptions and «→ queue» | Static | The routing rule per channel | Categories → queues ✓ (`ticket_categories.queue_key`) | build | Descriptions as message keys; «by topic» for the form |
| «Email threading»: ticket ID in the subject | Static claim | `[T-n]` in reply subjects, matched on inbound | ✓ (0060) | build | — |
| — «and a hidden reference header» | Static claim | `In-Reply-To` / `References` matched to the sent message id | Not done; `ticket_messages.email_message_id` exists | build | Pass Brevo's inbound headers to `worker_ticket_inbound`; match the header before the subject |
| — «Auto-replies and bounces are detected and never reopen a ticket» | Static claim | Auto-reply detection; bounce handling | Bounces ✓ (delivery events mark the reply, never reopen); auto-replies ✗ — they reopen today | build | `Auto-Submitted`, `X-Autoreply`, `Precedence: auto_reply/bulk`, `X-Auto-Response-Suppress` → stored as a system line or dropped, never reopen |
| support@ / kontakt@ as ticket channels (new mail, not a reply) | Implied by the table | Inbound mail without `[T-n]` → new ticket, routed by address | Dropped today; `inbound_domain` unset | needs-decision | Which domain's MX goes to Brevo inbound (orgpuls.com is Orgpuls' sending domain too), and whether first emails create tickets (decision 16); then build |

## Customer portal

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Header «Kundeportal · Lumio AS — What Kari Nordmann sees at help.orgpuls.no/portal», «Preview» badge | Static | Where the portal lives; an organisation to preview | No portal | needs-decision | Portal inside Orgpuls' Hjelp («Mine saker») or a separate site (decision 9); the admin preview is build (pick an account) |
| «Saker for organisasjonen» rows: subject, «T-n · requester», status (Venter på oss / Løst) | Three literals | The organisation's tickets with requester and a customer-facing status | ✓ tickets by `organization_id`, person, status | build | Preview from real tickets of the chosen account; status mapped to customer words (new/open/waiting_us → «Venter på oss», waiting_customer → «Venter på deg», resolved/closed → «Løst») |
| The same list shown to the customer | — | Customer identity in Orgpuls | No path | needs-orgpuls | `support.tickets_sync` push per organisation; Orgpuls renders it with its own role rules |
| «Venter på deg»: «Støttetilgang i 24 timer — Magnus Berg (Orgpuls) ber om lesetilgang for sak T-2312» | Literal | A support-access request and its decision | Nothing in Sentral or Orgpuls | needs-decision | What «read access» to a customer's Orgpuls organisation would mean, and that it can never reach respondent data (decision 8, an Orgpuls X-entry); then Orgpuls commands/events (`support_access.request`, `support_access.changed`) and Sentral's grant table |
| «Sletting av tidligere ansatt — Forespørsel PV-121 · krever bekreftelse fra daglig leder» | Literal | A privacy request whose subject is an employee | `privacy_requests` ✓ (kind deletion, 30-day clock) | cannot | An employee is a respondent; their identity must not travel through Sentral (rule 6). Sentral tracks the request and its clock; the customer deletes the person in Orgpuls. The portal row can say «Personvernforespørsel PV-n · behandles i Orgpuls», with no name |
| «Nytt prisbånd 101–250 — Ansattlisten viser 103 ansatte · ny pris fra 1. nov» | Literal | Employee count, band thresholds, the change command | `usage.daily.employees` ✓, bands in `plan_versions` ✓; no `billing.change_plan` | needs-orgpuls | `billing.change_plan` (already on SIMPLE-PLAN's list) and an approval flow in Orgpuls |
| «Godkjenn» / «Avslå» → «✓ Godkjent» / «Avslått», toast «Approved · the ticket and audit log are updated» | Local state | The customer's decision, by an allowed role, audited | Nothing | needs-orgpuls | Decisions are the customer's: made in Orgpuls, sent back as an event (`support.approval`). In the admin preview the buttons are disabled: «Customers approve in the portal» |
| «Portal access» bullet 1: daglig leder and HR see all tickets; others their own | Static | Role rule | Orgpuls has no HR role | needs-decision | Which Orgpuls roles see the whole organisation's tickets (decision 9) |
| Bullet 2: approvals need daglig leder or HR | Static | Role rule | — | needs-decision | Same decision |
| Bullet 3: «Login with the same account as the app — single sign-on» | Static | Customer identity | Only true if the portal is in Orgpuls (or a new signed-identity path, rule change) | needs-decision | Decision 3/9 |
| Bullet 4: «Every view and approval is in the audit log» | Static | Audit of portal views and approvals | Sentral audits staff; customer views happen in Orgpuls | needs-orgpuls | Orgpuls audits views; approvals arrive as events and are written to Sentral's `app.audit` (names, never values) |

## AI assist

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Ticket line «T-2310 · Survey invitations not delivered to 14 employees · Lumio AS» | Fixed ticket | Which ticket the assistant works on | Tickets ✓ (T-2310 is seeded locally) | build | A ticket picker (open tickets of the product) or `?ticket=` shared with the Tickets tab; empty state when none is selected |
| Summary box «14 warehouse employees … Mail log shows 451 greylisting on lumio.no. Matches known problem T-2316.» | Literal | Summary of the thread, linked problem and its workaround | Thread ✓, problem link ✓; no AI; no mail log | build+connector | Claude over this ticket's thread + linked problem. «Mail log …» cannot come from Sentral (Orgpuls' mail is not Sentral's, rule 6); only an Orgpuls count-only `delivery.summary` command could add «N invitations deferred» (needs-orgpuls, decision) |
| Chip «Suggested category: Survey delivery» | Literal | Classification into `ticket_categories` | — | build+connector | Claude with `strict` tool output limited to the category keys; applying = existing ticket update |
| Chip «Priority: Urgent» | Literal | Impact × urgency suggestion (priority is generated, V-SCU-09) | — | build+connector | Suggest impact and urgency, not priority |
| Chip «Link: T-2316» | Literal | Candidate open problems with similar subject | Problems ✓ | build | Deterministic candidate list (open problems, FTS on subject) — no AI needed; AI may rank |
| Label «Draft reply · from article «Invitasjoner kommer ikke frem»» | Literal | The article the draft cites | Articles ✓ | build+connector | The cited article from Claude's citations; when none, «Draft reply · no article matched» |
| Draft textarea (pre-filled Norwegian reply signed «Tor») | Fixed text | Draft generated from published articles, macros and this thread; signed with the agent's name | Composer and macros ✓ | build+connector | `ticket_ai_drafts`; merge fields as in V-SCU-12; signed with the staff member's name |
| «Shorter» | Swaps in a fixed shorter text | Redraft | — | build+connector | Same draft row, kind `shorter` |
| «Make article from answer» → «Article draft created in the help centre» | Toast | Draft article from the reply, linked to the ticket | `help_article_save` ✓, `ticket_links` ✓ | build | Plain copy into a draft = build; generalising it (removing the customer's specifics) = connector |
| «Approve and send» → «Reply sent · ticket set to Waiting on customer» | Toast | Send the reply, set status | `ticket_message(id, 'reply', body, 'waiting_customer')` ✓, emailed per product when mail is ready (else «not emailed», V-SCU-11) | build | Records the draft outcome (sent unedited / edited) |
| Footer «AI never sends on its own · uses help articles and resolved tickets only · no survey data» | Static | — | — | needs-decision | «Never sends on its own» is by construction (build). «Resolved tickets» means other customers' words in this customer's draft — Tor decides (decision 5); recommended: articles, macros and this ticket only |
| «AI usage · 30 days» — Drafts created 248 | Literal | Count | `ai_calls` (no writer yet) | build+connector | `ticket_ai_drafts` count |
| — Drafts sent with no edits 41 % | Literal | Sent body equal to the draft | — | build+connector | Hash of draft vs sent body |
| — Drafts edited, then sent 52 % | Literal | Sent body differs | — | build+connector | As above |
| — Drafts discarded 7 % | Literal | Draft never sent (superseded, ticket closed) | — | build+connector | Outcome set when the ticket is answered otherwise or closed |
| — Median time saved per ticket 4 min | Literal | A counterfactual nobody measures | — | cannot | Omit the row (or «—» with «not measured»); a median draft-to-send time is a different figure and must not be labelled «time saved» |
| — Articles created from answers 12 | Literal | Articles whose source is a ticket reply | — | build | `help_articles.source = 'ticket_reply'`, `source_ticket_id` |

## Status and changelog

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Header «Status page · status.orgpuls.no», «Public» | Static | A published status page on a host | Nothing public; only the in-app banner | needs-decision | Host/domain (decision 2); the page itself is build (public route or edge) |
| Component rows (Orgpuls app, Survey sending (email), Survey sending (SMS), Skiftly, Avvikspunkt, API) | Fixed names | Components per product | None | needs-decision | Which components each product's page lists; Skiftly/Avvikspunkt are not live products (decision 13); then `status_components` (build) |
| Component state select (Operational / Degraded / Partial outage / Maintenance) | Local | State per component, audited | — | build | `status_component_set`; «Maintenance» may also push the banner with `maintenance = true` (exists in `status_notice_set`) |
| Incident card title «Delayed invitations to municipal email domains», state «Investigating» | Literal | Incident with public title and state, linked to a problem | Problem T-2316 ✓ (title is internal, not public copy) | build | `status_incidents` (public title separate from the problem's subject) |
| Incident description «… Linked to problem T-2316.» | Literal | Public text | — | build | Public body; the problem link is internal and not printed on the public page |
| «3 customers · 41 employees affected» | Literal | Organisations with incidents linked to the problem; employees affected | Customers ✓ (`incidents` count, distinct organisations); employees ✗ | needs-orgpuls | Employees affected is a count about respondents: only as an Orgpuls aggregate (`delivery.summary`), else show customers only |
| Chips «Banner in app», «Status page», «Linked to 3 tickets» | Literal | Notice open for the problem; incident published; linked incidents | Banner ✓ (`status_notices.problem_ticket_id`), linked ✓; status page ✗ | build | Each chip only when true |
| «Resolve and notify affected customers» → toast «Resolved · affected customers notified, tickets closed» | Local | Resolve problem, reply to each incident ticket, clear banner, update incident and components | `problem_resolve(problem, body)` ✓ (needs a message), banner cleared by `status_notices_due()` ✓ | build | A message field or a macro (the design has none; `problem_resolve` requires a body); «tickets closed» → «resolved» (the RPC resolves) |
| Resolved chips «Banner removed», «Status page updated», «3 customers emailed», «3 tickets resolved» | Literal | Outcomes | Notified count ✓ (`notified`), emailed = reply `delivery_status` ✓, banner cleared ✓ | build | Each from its outcome; «emailed» counts delivered/sent replies only |
| Changelog rows (date, New / Improved / Fixed, text) | Four literals | Release notes per product | `app.changelog` is the record audit log, not release notes | build | `release_notes` table shared with DevHub releases and PlatformPlus «Shipped» (decision 14) |
| Public changelog | Implied | Public page | — | needs-decision | Host and whether it is public or in-app only (decision 14) |
| Toast host (all tabs) | Fixed bottom-centre toast | — | `useToast` ✓ | build | Every toast states the real outcome (errors too) |

## Proposed database objects (one migration, number assigned at planning; RLS on, no policy, no grant on every table)

| Object | Kind | Columns / behaviour | Rights |
|---|---|---|---|
| `app.help_articles` (expand) | alter | `product text not null default 'orgpuls' references app.products`, `group_id uuid not null default gen_random_uuid()` (one per article across locales), unique (`product`, `locale`, `slug`) replacing the global unique slug (old `help_get` keeps working), `seo_title`, `app_pages text[]` (checked path pattern, never `/s/`), `reviewed_at`, `reviewed_by`, `source` (`staff`/`gap`/`ticket_reply`/`ai`), `source_ticket_id`, `search_vector tsvector` (generated: `norwegian` for nb/nn, `english` for en) + GIN index | — |
| `app.help_article_stats_daily` (expand) | alter | add `helpful_yes`, `helpful_no`, `ai_cited`, `solved` (replaces the meaning of `deflections`, kept for old reads) | — |
| `app.help_sessions` | table | `id uuid` (random per widget open, issued by `help-public`), `product`, `surface` (`in_app`/`website`/`help_centre`), `page_path` (no query), `started_hour timestamptz` (hour-truncated), `searches int`, `ai_answers int`, `outcome` (`article`/`ai_answer`/`ticket`/`none`), `outcome_at`, `ticket_id` (set at intake from `help_session_id`). No user, no IP, no visitor id. Kept 13 months | worker only |
| `app.help_ai_answers` | table | `id`, `product`, `session_id`, `article_ids uuid[]`, `answer text` (generated from articles), `ai_call_id → ai_calls`, `accepted boolean`, `created_at`. **No question text** unless decision 4 allows it | worker only |
| `app.help_queries` (only if decision 4 allows) | table | `product`, `day`, `normalised text` (≤ 80 chars), `searches`, `no_result`, shown in the UI only at ≥ 3 sessions; kept 90 days | worker only |
| `app.support_settings` | table | per product: `ai_answers`, `show_open_requests`, `live_chat`, `consent_gate`, `updated_by`, `updated_at` | read `tickets:see`, write `tickets:configure` |
| `app.ticket_ai_drafts` | table | `id`, `ticket_id`, `kind` (`summary`/`triage`/`reply`/`shorter`/`article_improve`), `state` (`queued`/`ready`/`failed`), `body`, `suggestion jsonb` (category key, impact, urgency, problem id), `article_ids`, `body_sha256`, `ai_call_id`, `outcome` (`pending`/`sent_unedited`/`sent_edited`/`discarded`/`superseded`), `message_id`, `created_by`, `created_at`, `decided_at` | via RPCs, `tickets:ai` + ticket visibility |
| `app.tickets` (expand) | alter | `channel` check adds `website_widget`, `portal`, `chat`; `inbound_address`; `ces_score smallint 1..5`, `ces_at` (after decision 6); `help_session_id`, `help_answer_id` | — |
| `app.status_components` | table | `id`, `product`, `key`, `name`, `ord`, `state` (`operational`/`degraded`/`partial_outage`/`maintenance`), `updated_by`, `updated_at` | read `tickets:see`, write `tickets:configure` (or `global:edit_others`) |
| `app.status_incidents`, `app.status_incident_updates`, `app.status_incident_components` | tables | public title/body, state (`investigating`/`identified`/`monitoring`/`resolved`), `problem_ticket_id`, `started_at`, `resolved_at`, `published`; updates append-only (immutability written as «nobody may change this content», FK maintenance allowed) | as above |
| `app.release_notes` | table | `id`, `product`, `kind` (`new`/`improved`/`fixed`), `title`, `body`, `published_at`, `source` (`manual`/`release`/`feature_request`), `source_ref`, `created_by` | read `global:see`, write `global:edit_others` |
| `app.portal_approvals`, `app.support_access_grants` (after decisions 8/9) | tables | approval kind, ticket, requested by, state from Orgpuls events, `expires_at`; grants with `granted_until`, revocation | read `tickets:see`; request: Super-admin and Support (PlatformPlus matrix) |
| `app.ticket_intake` (replace) | function | message = `coalesce(payload->>'message', payload->>'body')`; contact topic → category (product → getting_started, pricing → sales, first_send → survey_delivery, privacy → personvern + `privacy_requests` row); subject from the topic label when none; `help_session_id`/`help_answer_id` read when present | trigger |
| `public.worker_ticket_inbound` (replace) + `worker_ticket_inbound_new` | function | headers in; `In-Reply-To`/`References` match before `[T-n]`; auto-reply detection never reopens; new-ticket path behind a setting (decision 16) | service_role |
| `public.support_results(product, days)` | RPC | KPI row with previous period, session ends, gaps, articles by results | `tickets:reports_others` (or `tickets:see`, like 0056's summary) |
| `public.help_centre_get(product)`, `help_article_get(id)`, `help_article_save` v2, `help_article_review(id)`, `help_search(product, locale, q)` | RPCs | list with stats and link counts; one article group; save with version check | read `tickets:see`; write `tickets:configure` or a new `tickets:help` right (decision 15) |
| `public.support_channels(product, days)` | RPC | shares by channel and inbound address | `tickets:reports_others` |
| `public.portal_preview(product, organization)` | RPC | the organisation's tickets in customer words + pending approvals | `tickets:see` |
| `public.support_settings_get/save` | RPC | widget settings | see table |
| `public.ticket_ai_request(ticket, kind)`, `ticket_ai_drafts_get(ticket)`, `ticket_ai_outcome(draft, outcome)`, `ai_usage(product, days)` | RPCs | queue a job on pgmq for `ai-run`; read drafts; usage counts | `tickets:ai` + ticket visibility; usage `tickets:reports_others` |
| `public.status_get(product)`, `status_component_set`, `status_incident_save`, `status_incident_resolve` (wraps `problem_resolve`, clears the notice, appends an update, resets components) | RPCs | — | `tickets:see` / `tickets:configure` |
| `public.release_notes_get/save` | RPCs | — | see table |
| `public.worker_help_*` (`search`, `article`, `session`, `beacon`, `answer_context`, `answer_record`), `worker_status_public(product)`, `worker_csat_peek/submit(token, score, effort)` | worker RPCs | the public edge's only doors; published content only | service_role only |

## Proposed edge functions and connectors

| Function | Public? | Does | Secrets |
|---|---|---|---|
| `help-public` (new, `verify_jwt: false`) | Yes, CORS to the product's registered origins (`web_sites`) | Article search (FTS) and reading, published only; session start/end, view, helpful and outcome beacons (always 204, day-salted rate limit, no IP, logs counts only); the AI answer: retrieve top articles, call Claude with `document` blocks and citations, refuse when `ai_answers` is off or AI is not connected, record `help_ai_answers` + `ai_calls` (no prompt, no output in the log). Never answers from account data | `anthropic_api_key` via `public.product_secret` (allow-list extended in a migration) |
| `ai-run` (new, cron + pgmq, service role) | No | The AI gateway: claims `ticket_ai_drafts` jobs (summary, triage with a strict tool schema, reply, shorter, article improve), calls Claude, writes the draft and `ai_calls`; proves the key once and marks `integration_connections('ai')` connected | `anthropic_api_key`, a generated `ai_worker_secret` for the cron knock |
| `secret-intake` (existing) | — | Receives the Claude API key with a one-time number (rule 5) | — |
| `mail-run` (extend) | No | CSAT request email on resolve (token link), per product sender (0061) | existing |
| `mail-events` (extend) | Brevo webhook | Inbound: pass headers; CSAT peek/submit for the public page (as unsubscribe does) | existing |
| Public Next routes | Yes, each with a reason beside it in `middleware.ts` | `/r/[token]` CSAT (and effort) page; optionally the public status page and changelog if Tor hosts them on Sentral (decision 2) | none in the app |
| Widget script `w.js` | Yes | Static script served from the chosen host; renders search, answers, beacons; in-app shows identity blocks only when Orgpuls passes them in the page (no token) | none |
| Claude API (connector) | — | Model default `claude-opus-5-5` at low effort for the widget and medium for drafts (cost and model are Tor's call, decision 5); citations on article documents (incompatible with structured outputs, so triage uses a strict tool instead); prompt caching on the article set; refusal handling | Vault |
| IP-to-company provider (connector, existing plan D-37) | — | Company on website-widget tickets | Vault |

## Orgpuls commands and events needed

| Need | Kind | Fields / behaviour | For |
|---|---|---|---|
| `support.requested` + `help_session_id`, `help_answer_id`, `app_version` (deploy SHA), `last_error` (code only) | event fields (registry update in Orgpuls) | Optional fields; Sentral ignores unknown | Self-service rate, «Ticket created» ends, «AI answer attached», App version, Last error |
| `contact.submitted` + `org_number` (9 digits), `consent` (+ text version, lang), topics aligned with the design or a fixed mapping | event fields + form change | — | Org attach, newsletter consent, routing |
| Embed the widget (or a Hjelp panel calling `help-public`) in the app, never on `/s/…`; CSP `script-src`/`connect-src`; on orgpuls.com behind the consent setting | repo change | — | Every in-app number in Support results |
| `support.tickets_sync` (or `support.ticket_state` on each change) | command `support:write` | org, list of {ref, subject, status (customer words), requester name, updated_at} | «Your open requests», portal list |
| `support.approval_request` / event `support.approval` | command + event | kind, ticket ref, text key, expires; decision, deciding role | Portal approvals |
| `support_access.request`, `support_access.revoke`, event `support_access.changed` | commands + event | org, ticket ref, hours; granted_until, granting role — **after an Orgpuls X-entry defines what access exposes** | «Støttetilgang i 24 timer» |
| `billing.change_plan` | command (already listed in SIMPLE-PLAN) | org, band | «Nytt prisbånd» approval |
| `delivery.summary` (optional) | command `orgs:read` | count-only: invitations sent/delivered/deferred/bounced for a round, by recipient domain, never addresses | AI summary facts, «employees affected» |
| `help.articles_sync` (only if decision 1 keeps Orgpuls rendering /hjelp) | command | published Sentral articles per locale | One help centre for both surfaces |
| `help.daily` (only if Orgpuls renders the help centre itself) | count-only event | per article: views, helpful yes/no, solved | Articles by results |
| `settings.set_notice` | exists | — | Banner in app |

## Product decisions for Tor

1. **Who owns help-article content.** Sentral authoring for every product (Orgpuls renders synced copies or the Sentral
   widget) versus Orgpuls' registry under D-23. Today: 21 articles in Orgpuls' messages, 6 different ones in Sentral.
2. **Hosts and domains** for the public help centre, `w.js`, status page and changelog: `help.orgpuls.no` /
   `status.orgpuls.no` (design; is orgpuls.no owned?), `orgpuls.com` subdomains, or `go.owntheagenda.com` (D-28).
3. **In-app identity.** Orgpuls renders the identity blocks (recommended, fits rules 3–4) or a Sentral widget accepts an
   Orgpuls-signed identity token (a new inbound trust path: a rule change).
4. **Search text.** May the questions people type be stored (normalised, ≥ 3 sessions before shown, 90 days)? Without it,
   «Top questions without a good article» is built from tickets only and shows no «searches».
5. **AI.** Anthropic as a subprocessor for ticket text and widget questions; model and monthly budget; whether AI answers
   are on in the widget at launch; whether other customers' resolved tickets may ground a draft (recommended: no — articles,
   macros and this ticket only).
6. **CSAT and effort.** Wording, when to ask (on resolve, once), reminder or not, and whether to add the effort question
   (1–5, lower is better).
7. **Definitions and thresholds.** «Solved = no ticket within 24 h» (per session) and the Rewrite/Review/Good thresholds
   (65 % / 75 % helpful, minimum votes).
8. **Support access.** Whether it exists, what a 24-hour grant exposes in Orgpuls (never anything respondent-level), who
   grants it (daglig leder), and an Orgpuls X-entry before any command.
9. **Customer portal.** Inside Orgpuls' Hjelp or separate; which Orgpuls roles see all of the organisation's tickets and may
   approve (the design's «HR» does not exist).
10. **Deletion requests about employees.** Confirm they are fulfilled by the customer in Orgpuls, with Sentral tracking only
    the request and the 30-day clock, never the person.
11. **Contact form.** Keep Orgpuls' form (topics product/pricing/first_send/privacy) or adopt the design's
    (Support/Sales/Billing/Privacy + org nr + newsletter); confirm the visitor is never told whether a company is a customer.
12. **Live chat** in business hours: staffing, and deploying the 0031 chat edge.
13. **Status components** per product (Skiftly and Avvikspunkt are not live), one page per product or one for the company,
    language of public incident texts.
14. **Changelog** source (manual, DevHub releases, PlatformPlus «Shipped») and whether it is public.
15. **Publishing right.** `help_article_save` needs `tickets:configure` (admins only); should the Support role publish?
16. **Inbound email.** Which domain's MX goes to Brevo inbound for support@ and kontakt@, and whether a first email creates
    a ticket.
17. **Booking.** Which booking link «Book a call» opens.

## Risks against the security rules

- **Rule 1 (no client reads a table).** The 0012 spec planned «an anon published-only variant» of the help search; an anon
  RPC would skip `app.is_admin()`. Public reads must go through `help-public` and service-role `worker_*` functions only.
- **Rule 2 (aal2 everywhere).** Every new public route (`/r/[token]`, a status page, help pages) needs its written reason in
  `middleware.ts`, follows the `/u/[token]` pattern (the app calls an edge function; it holds no service key), and must not
  widen to any admin path.
- **Rule 3 (product-command only).** Ticket sync, approvals and support access go out only as signed commands with one
  scope each; the widget never carries an Orgpuls token or a Sentral key.
- **Rule 4 (events only).** A signed identity token from Orgpuls to a Sentral widget or portal is a second inbound path;
  avoid it (decision 3) or make it an explicit rule change.
- **Rule 5 (Vault).** The Claude key arrives through `secret-intake`; `product_secret`'s allow-list grows by name in a
  migration; never an environment variable in a tracked file, never printed.
- **Rule 6 (no respondent data).** The widget must never load on survey routes (`/s/…`). AI answers are grounded on
  published articles only and must not carry account facts. Ticket text sent to Claude can contain a customer's pasted
  survey comment: AI runs only on a staff click, never automatically, and a ticket can be marked «no AI». `ai_calls`, logs and
  beacons carry kinds, counts and codes, never the question, prompt or answer. «41 employees affected» and «Mail log shows …»
  are respondent-adjacent: only as Orgpuls count-only aggregates, if at all. The «Sletting av tidligere ansatt» approval must
  carry no employee identity. The public org-number match would disclose the customer list.
- **Rule 7 (migrations).** Expand `help_articles` and `tickets` without breaking `help_get`, `/tickets?tab=help` and the
  intake (expand → migrate → contract); the intake fix replaces the function in a new migration, never edits 0056.
- **Never fabricate.** Every literal listed above (KPIs and deltas, session split, searches, views, helpful, «FAQ schema ✓»,
  «linked from 3 tickets», «last reviewed», «Last error none», «v2.14.0», channel shares, portal rows, approvals, AI usage,
  «4 min saved», components, incident, changelog) is rendered from its source or as «—» / the empty state.
- **Prompt injection and XSS.** Article bodies and ticket text go to the model as documents; outputs are drafts a person
  sends, and widget answers are short and cited. Article Markdown is sanitised before any public render.

## Suggested build order (S ≈ ½–1 day, M ≈ 2–3 days, L ≈ 4–6 days, XL > 1 week)

1. **Intake and threading fixes (S, no decision needed).** `body`/`message`, contact topics → categories (privacy into the
   personvern queue with a `privacy_requests` row), auto-reply detection and `In-Reply-To` matching. Independent of the new
   tab and wrong in production today.
2. **Tab, help-centre editor and status (M).** Third pill and sub-tab links; Help centre on the expanded `help_articles`
   (product, translation group, SEO title, app pages, reviewed, link counts, ＋ Article, Publish); Support results with what
   exists (Tickets created + delta, CSAT «—»/answered, gaps from tickets) and honest empties; Channels from `tickets.channel`;
   the truthful Email threading card; Status components, incidents and release notes in the admin with «Resolve and
   notify» on `problem_resolve`; the portal preview read-only from tickets.
3. **CSAT and effort (M, after decision 6).** Request mail, `/r/[token]` page, answers, KPI.
4. **AI gateway and AI assist (L, after decision 5 and the key).** `ai-run`, Vault key, summary, triage, draft, shorter,
   make-article, outcomes, AI usage (without «time saved»), «AI: improve from tickets».
5. **Public help surface (L, after decisions 2 and 4).** `help-public` (search, article, beacons, cited AI answer), `w.js`,
   widget settings with real effects, sessions and outcomes, Articles by results, Top questions, public status page and
   changelog.
6. **Orgpuls side (XL, Orgpuls repo, after decisions 1, 3, 8–11).** Embed, event fields, contact form fields, ticket sync,
   portal and approvals, support access (with its X-entry), `billing.change_plan`.
