# Data-requirements spec: Marketing and Documents (Sentral)

Sources read in full: `design-reference/sentral/project/Marketing.dc.html` and `Documents.dc.html` (markup and logic), `admin-data.js`, `coverage-data.js` (CMP-01..09, LGN-01..05, WEB-01..04, DOC-01..06, plus the features that lean on them: CRM-05, CRM-07, CRM-15, LEA-04, COM-05, COM-06, AUT-07, PIP-04, PIP-12, PIP-16, INS-01, SEC-07, SEC-11, ENT-02; flows UF-01, UF-08, UF-17, UF-18, UF-19, SF-17, SF-18, SF-19, SF-20, SF-30, SF-33, SF-39), `docs/crm-enrichment/DECISIONS.md`, `05-GAP-FEATURES.md` (Part 3, Part F entities and events, Part G), `INSTRUCTIONS.md` (Marketing CRM, Web analytics, Ticketing and best practices) and migrations 0001–0026. 0026 exists beyond the 0025 the brief names. It changes only `wf_blockers` and `deal_detail`.

The Marketing component serves three shell routes: `campaigns` (opens on the Campaigns tab), `leadgen` (opens on Web forms) and `visitors` (opens on Web visitors). Each route shows all eight tabs. Documents is the `documents` route.

**Overall finding.** Every figure on both screens is a literal from the component. No figure is computed from a record, and the only shared data the two screens read is `admin-data.js`'s random deals, orgs and people, which Documents uses for deal titles and the quote preview. Almost every action is a toast or a local state change. The real build has three sources:
- the existing database: people, consent, leads, deals, deal items, coupons, the email templates and merge fields (0020), the engine (0021), credits (0022) and the cookieless web tables (0025);
- about 30 new tables;
- six providers, none of them connected today: the email provider, IP-to-company, the prospect database, Google and Microsoft drives, external e-signature, and PDF sealing.

Without its provider, each feature shows a `not_connected` state and never sample output. Three rules from D-27 are law or provider requirements and therefore fixed, not settings: an unsubscribe link and sender identity in every campaign, no campaign to unsubscribed people, and no send from an unauthenticated domain. The prototype breaks one of them (the footer block can be removed).

---

## 1. Marketing screen (routes `campaigns`, `leadgen`, `visitors`; CMP, LGN, WEB; UF-17, UF-18, UF-19)

### Views and states
- **Tabs (pill row).** Campaigns, Email builder, Audience and consent, Deliverability, Web forms, Chatbot and live chat, Prospect search, Web visitors.
- **Module gating.** The first four tabs belong to module `campaigns`, the next three to `leadgen`, and Web visitors to `visitors` (`app.modules`, 0005). A switched-off module hides its tabs, and its functions raise `module_off`.
- **Overlays.** A toast only.
- **Local selections in the prototype.** Campaign type filter, selected campaign, builder device (Desktop 600 px / Mobile 360 px), selected block, selected form, live-chat takeover, revealed prospects, selected visitor.

The design has no loading, empty, no-permission or unconnected states. Per D-41 they must be built in the design's language:
- **Campaigns:** no campaigns yet (CTA «＋ Campaign»); a campaign with no stats yet ("—", as the design already does for a scheduled one).
- **Email builder:** a new blank design (header and fixed footer only).
- **Audience:** no segments; a segment with 0 matches; an empty consent log.
- **Deliverability:** no sender domain yet; email provider `not_connected` (DNS checks still run, «Verified» shows not connected).
- **Web forms:** no forms.
- **Chat:** no playbooks; no chat in the queue; staff offline.
- **Prospect search:** provider `not_connected` (filters can be built and saved, Reveal is disabled); a search with no results.
- **Web visitors:** no tracked site; tracker installed but no visits; IP-to-company `not_connected` (sessions exist but no company is named); identification switched off (`web_ident` = off).
- **No permission:** the tab is not listed. A direct call returns `forbidden`.
- **Loading:** skeleton rows in each card.

### Campaigns tab (CMP-05, CMP-06, CMP-09)
The list columns are Campaign + audience line, Type, Status, Sent, Open, Click, Unsub., Signups and MRR won. All six rows are a literal array `C`.

| Element | Prototype | Real source / formula |
|---|---|---|
| Type filter (All, Newsletter, One-off campaign, Promotion, Product announcement, Automated) | Filters the literal list | `campaigns.type`. The five types come from the brief ("newsletter, one-off campaign, promotion, product announcement") plus `automated` (CMP-07). |
| Campaign name, audience line ("All subscribed · 4 120") | **Fabricated** | `campaigns.name`. The audience line is the segment name (`saved_views.name`) · `campaigns.audience_count`, frozen when sending starts. Before that, the live estimate from `segment_count`. For an automated campaign: "Workflow step · <workflow name>". |
| Status pill (Scheduled, Sent, Active) | **Fabricated** | `campaigns.status`. D-41 adds the missing states draft, sending, paused and canceled. Active is used for automated campaigns. |
| Sent | **Fabricated** | `count(*) from campaign_recipients where campaign_id = c and state <> 'queued' and state <> 'skipped'` |
| Open | **Fabricated** | open rate = unique opens ÷ delivered. Unique opens = recipients with `first_open_at` from an event whose `client_class <> 'prefetch'`. The report must say that opens are unreliable where clients prefetch images (COM-06). |
| Click | **Fabricated** | unique clicks ÷ delivered |
| Unsub. | **Fabricated** | `count(unsubscribed_at)` ÷ delivered |
| Signups | **Fabricated** | `count(*) from account_products ap where ap.created_at >= c.sent_at and lower(coalesce(ap.attribution->'last_touch'->>'utm_campaign', ap.attribution->>'utm_campaign')) = c.utm_campaign`. The attribution touch is open question Q14. |
| MRR won | **Fabricated** | `Σ app.sub_mrr(s)` over those signups' subscriptions with `confirmed_at is not null`. Tenant-level counts only (D-19). |

Selected-campaign card:

| Element | Prototype | Real |
|---|---|---|
| "Sends Thu 8 Oct 08:00 · marketing stream" / "Sent 22 Sep 08:00" | **Fabricated** (literal) | `scheduled_at` or `sent_at`, plus the sender domain's stream |
| Delivered | **Fabricated** (`sent × 0.986`) | `count(delivered_at)` |
| Bounced | **Fabricated** ("1,4 %") | `count(state = 'bounced')` ÷ sent. Show hard and soft separately on hover. |
| Unique opens / Total opens | unique = the list's literal; **total fabricated** (`sent × open × 1.6`) | unique as above; total = `Σ opens` (human and unknown opens) |
| Unique clicks / Click-through | literal / computed from literals | unique clicks ÷ delivered; click-through (CTOR) = unique clicks ÷ unique opens |
| Spam reports | **Fabricated** ("2") | `count(complained_at)` |
| Signups (UTM) | literal | as in the list |
| A/B line ("«Slik kartlegger…» 49 % vs «Lovkravet…» 44 % — winner sent to the rest") | **Fabricated** | per variant `a`/`b`: the metric in `campaigns.ab_metric` over that variant's recipients. "winner sent to the rest" holds only when `ab_winner` is set. Before then the line reads "test running · decides at <time>". Hidden when there is no subject B. |
| "Top locations: Oslo · Bergen · Trondheim · Stavanger" | **Fabricated** | top 4 `campaign_recipients.city` among human opens, from the provider's own geo field. **The platform never receives or stores an IP.** Omit the line when the provider sends no geo. |
| "owners notified on engagement" | literal | true only when `campaigns.notify_owners`. Then the first open or click by a person notifies the person's owner (`app.notify`, kind system). |

**Compare campaigns («Same figures as each campaign's report»).** The prototype lists every campaign whose literal open rate is above zero. Its click bar is drawn as `click × 4`, which **distorts the comparison**. Real (CMP-09):
- the user selects two or more sent campaigns, defaulting to the last 6 sent of the current type filter;
- both bars use the same 0–100 % axis, with the values printed;
- the figures come from `v_campaign_stats`, so they equal each campaign's card.

The source puts comparison in a higher tier. Per D-17 it is on.

**Actions**
- **＋ Campaign.** The prototype only switches tab. Real: `campaign_save(null, {type, name})` creates a draft, then opens the builder on it.
- **Row click.** Selects the campaign. Real: `campaign_get(id)`.
- **Missing per D-41:** row actions Duplicate, Cancel (scheduled only), Pause and Resume (automated), and Delete (drafts only; a sent campaign is kept for its report).

### Email builder (CMP-01, CMP-02, SF-39)
The prototype's content:
- **Palette:** Title, Paragraph, List, Image, Button, Divider, Social, HTML, Video and Menu. Video renders as an image placeholder. Menu inserts a second header.
- **Starting layouts:** «Start from» Blank / Newsletter — Orgpuls / Product announcement / Saved: Webinar invite / Code your own HTML. **Every option except Blank loads the same default design**, so these are fabricated.
- **Row properties:** Background has a handler (Card, Soft yellow, Mint, Cream). **Padding and Border have no handler.** Also Move up/down and Remove.
- **Campaign fields:** Subject A and Subject B are uncontrolled inputs with literal values. The promotion coupon select has no handler. The UTM line is a literal.

The real build:
- **Design model.** `{rows: [{kind, text?, fs?, bg: 'card'|'soft_yellow'|'mint'|'cream', padding: 14|22|32, border: 'none'|'hairline', src?, href?, html?}]}`, Zod-validated. The kind list is CMP-01's: title, paragraph, list, image, button, divider, social, html, video, icons, menu. Icons is missing from the design's palette (D-42: add the small omission).
- **The footer is fixed (D-27, CMP-01 RU).** It is always the last row and cannot be removed or edited, apart from its background. It carries the sender's legal name and full postal address from `sender_domains.postal_address`, plus the one-click unsubscribe link. **The prototype's Remove deletes the footer and header**, which is a bug: Remove refuses on the footer.
- **HTML block.** Sanitised against an allowlist (tables, inline styles, links, images); no scripts, forms or iframes. "Code your own HTML" stores `email_templates.html` and must contain the footer token `[Unsubscribe]`. Saving without it is refused with `invalid` (detail `html.footer`).
- **One renderer.** A single TypeScript renderer, design → email HTML, is used by the preview, the test send and the send worker (SF-39 step 3: "render the same output as the final send"). At schedule time the HTML is frozen into `campaigns.rendered_html`, so the report shows what was sent.
- **Device switch.** Desktop renders at 600 px and Mobile at 360 px, from the same HTML.
- **Images.** Uploaded to the `email-assets` bucket and served from the public host (D-28), because email clients fetch them unauthenticated.
- **Merge fields.** `[Person.fornavn]` and the other tokens resolve through `app.merge_render` (0020). Missing values are listed before scheduling (COM-05 rule).
- **Layouts and saved templates (CMP-02).** Layouts are seeded rows in `email_templates` with `kind='marketing', layout=true`. «Saved: …» rows are the user's templates. Every save writes `email_template_versions`. "A template can start a new campaign" copies its design into `campaigns.design`.
- **Subject A / B.** `campaigns.subject_a` and `subject_b`. A non-empty B turns on the A/B test, which needs `ab_percent` (the toast says 20 %), `ab_metric` and `ab_wait`.
- **Promotion coupon.** A select over `app.coupons where active` (0013), plus None. Saved as `campaigns.coupon_code` and available as merge token `[Kampanje.kode]`. Allowed only for type promotion.
- **UTM.** `utm_source` defaults to `newsletter`, `utm_medium` to `email`, and `utm_campaign` to a slug of the name plus the month, editable and unique. The renderer appends the UTM to every tracked link.
- **Send test.** The toast is literal: "Test sent to tor@orgpuls.no". Real: `campaign_test_send(id)` sends to the caller's own address through the marketing stream, merged with the caller as the person. Not counted in stats. `not_connected` without the email provider.
- **Schedule.** The toast is literal: "Thu 8 Oct 08:00 · A/B on 20 %". Real: `campaign_schedule(id, at, version)`. It refuses with `invalid`:
  - detail `sender_domain` when the domain is not verified (CMP-08, D-27);
  - detail `audience` when 0 recipients can receive;
  - detail `subject` when the subject is empty;
  - detail `merge:<token>` when a merge field is unknown.

  It refuses with `not_connected` when there is no provider. Otherwise it freezes the HTML and sets status scheduled.

**Copy correction (seeded layout).** The default content says «Fem er gulvet — og det er produktets.» and «Resultat for grupper med minst 5 svar». Orgpuls's k is a floor of 3 and a default of 5, set per organisation and frozen per round. The seeded "Newsletter — Orgpuls" layout must not repeat either claim. See Q18.

### Audience and consent (CMP-03, CMP-04)

| Element | Prototype | Real source / formula |
|---|---|---|
| Segment title and the five conditions (Where/AND/AND/AND/OR) | **Fabricated**, not editable | A segment is a `saved_views` row with `kind='segment'`, `screen='people'` and `shared=true` ("shared by sales and marketing"). Its `query` is the people filter syntax, including `or` groups (0023). The conditions need new computed filter fields in `app.filter_sql` for entity person, built the way `idle_days` is: `organization.<column>` (join), `organization.status` (trial/active/past_due/cancelled from the linked account's subscriptions), `member.role` (the product user's role), `engagement.opened_days` / `engagement.clicked_days` (days since the last human open or click of any campaign) and `marketing_status`. «Person · role is HR» needs `people.title`, or a custom field, because there is no role column. |
| "**214** people match · **178** can receive marketing" | **Fabricated** | `segment_count(query)` → `matches = count(*)` of the filter. `receivable = count(*) where marketing_status = 'subscribed' and email is not null and not exists (suppression for sha256(lower(email)))`. CMP-03's acceptance test: "the recipient count equals subscribed matches". |
| Saved segments with counts | **Fabricated** | `saved_views where kind='segment' and (shared or owner_id = me)`, count = `segment_count`. Computed on open, not cached. |
| "Segment saved · available in Campaigns and Automation" | toast | `segment_save`. Usable as a campaign audience and as a condition in workflows. |
| Marketing status of all addresses (7 bars) | **Fabricated** counts; bar width = value ÷ 4 120 | `marketing_status_summary()`: `count(*) group by marketing_status` over people with an email, not deleted and not sample. Bars are proportional to the largest group. **Only five statuses are stored today** (`subscribed, no_consent, pending, unsubscribed, bounced`, 0011). This build adds `archived`. "Pending upgrade" is not a consent state: it is the subscribed people above the subscriber allowance (CMP-05, ENT-02). Unlimited by default (D-17), so the row shows only when an allowance is set (Q2). |
| Footer promise "Double opt-in for newsletter signups · one suppression list across all sends · every change logged with time and source" | literal | True only with `double_opt_in` = on (new setting, Q3), `app.suppressions` and the append-only `consent_events`. |
| Consent log (4 rows) | **Fabricated** | `consent_log(limit, before)`: newest `consent_events` joined to `people.email`. Shows `prev_status → status` and the source line (source + ref: the form's name, the campaign's name "honoured immediately", or a provider code such as `550`). Needs the new columns `prev_status`, `ref_type`, `ref_id`, `detail`. |

**Rules**
- **CMP-04: the consent record is the source of truth.** `people.marketing_status` is set only by `consent_set` and the workers, each of which writes `consent_events`. `rec_save` cannot set it (0011).
- **Bounces.** A hard bounce, or five soft bounces since the last delivery, sets `bounced` (CMP-06 RU) and adds a suppression with scope `all`.
- **Complaints.** A complaint sets `unsubscribed` and suppresses with scope `marketing`.
- **Unsubscribe.** One-click unsubscribe (RFC 8058 `List-Unsubscribe-Post` plus the footer link) writes `unsubscribed` and the suppression in the same transaction. It is honoured immediately.
- **Address-level consent.** CMP-04 says "each email address has a status". A change of `people.email` writes a `no_consent` event with source `email_changed`, unless the new address already has its own consent.
- **List hygiene (Archived, no engagement in 12 months).** Candidates are subscribed people with no human open or click in `list_hygiene` months who received at least one campaign in that window. Archiving is a staff action (`hygiene_archive`, `campaigns:bulk`), never automatic. It writes `archived` with source `list_hygiene`.

### Deliverability (CMP-08)

| Element | Prototype | Real |
|---|---|---|
| Domain rows (news.orgpuls.no, varsler.orgpuls.no, news.skiftly.no) with stream | **Fabricated** | `sender_domains` (domain, stream, product, from name) |
| Check pills SPF / DKIM / DMARC p=… / Verified | **Fabricated** | `spf_ok`, `dkim_ok`, `dmarc_policy`, `verified_at`, written by the DNS-check worker (DNS-over-HTTPS, no key needed) and by the provider's domain verification. Verified is `not_connected` without the provider. |
| Bounce % / Complaints % | **Fabricated** | last 30 days, per domain: bounced ÷ sent and complaints ÷ delivered from `campaign_recipients` joined to `campaigns.sender_domain_id`. **Only for domains this platform sends through** (`sends_here`). For varsler.orgpuls.no (Orgpuls's survey invitations) the platform has no source: show "—" (Q6). |
| Warm-up "done" / "day 9 of 30" | **Fabricated** | `current_date − warmup_started_at + 1` of `warmup_days`; "done" when past |
| Re-check DNS → "DKIM still missing on news.skiftly.no" | toast with a literal result | `sender_domain_recheck(id?)` queues `dns_check` jobs. The toast says "Re-check queued". The rows refresh when `worker_sender_domain_status` reports. |
| Recommendations (3) | **Fabricated** | computed by `deliverability_recommendations()`: (a) per domain, a missing SPF/DKIM/DMARC record, or a bounce rate above 3 % over the last 30 days; (b) the hygiene candidate count, when above 0; (c) "Unsubscribe link and sender identity are present in all marketing templates", true by construction because the footer is fixed. Shown only when the check passes; otherwise it names the templates without a postal address. |
| "Separate streams" box | literal | Copy stays. The domain names come from `sender_domains` per stream. "Mail from staff mailboxes is a third path" is true (0020). |

### Web forms (LGN-03, SF-17, D-20)

| Element | Prototype | Real |
|---|---|---|
| Form list (Kontakt oss 128, Lovkrav-sjekkliste 342, Webinar 96, Ansattlisten 14) | **Fabricated** | `forms`. Subtitle: kind · embedding page (the most frequent `tracking.landing_path` host and path of the last 30 days, or the form's public link) · submissions this month (`form_stats_daily`). **Selecting a form does not change the preview in the prototype**: the canvas always shows Kontakt oss. |
| Template chips (Contact, Registration, Gated download, File upload, Blank) | not clickable | `form_create(kind)` seeds the definition for that kind |
| Canvas: Introduction (mandatory), fields, consent checkbox, Send | literal; «＋ block» always adds "Ny felt" whatever the block type | the form's draft definition. The block palette is Short text, Email, Phone, Marketing status, Custom field, File upload and Message block, each mapped to its kind. Fields map to `person.name|email|phone`, `organization.org_number|name` or `custom.<key>` of person, organization or lead (`app.fields`), and each has a required flag. The intro block cannot be removed (LGN-03). |
| Consent checkbox "Ja, send meg nyhetsbrev (marketing status: pending double opt-in)" | literal | Unticked by default. The public form shows only the consent text (`consent_texts`, in the form's language). The bracketed note is an admin annotation on the canvas, not public copy. |
| "Hidden tracking fields: UTM, referrer, cookie ID (setting on)" | literal | UTM, referrer host, landing path and declared page variables, captured only while `form_tracking` = on. **"Cookie ID" conflicts with D-37's cookieless tracker** (Q7). The line shows the real setting value. |
| "creates a lead, a ticket in Sales and a consented prospect" | literal | from the form's `after_submit`: create a lead (or a deal, with pipeline and stage), optionally a ticket in the Sales category (on by default for kind `contact`), and a person of `contact_type='prospect'` with a consent event only when the box was ticked |
| After submit: "Create lead → owner by assignment rule «Inbound — chatbot and forms» → enroll in «Trial nurture» → thank-you message" | literal | Rendered from `after_submit`: the assignment runs through the existing `sub_assignment` (the lead's changelog source is `capture`, so V-20 applies), then the selected sequence (`seq_enroll`, lead), then a thank-you text or a redirect URL. Gated download: a signed URL to `form-assets`, valid 24 h. |
| "Submissions this month 128 · conversion 7,4 %" | **Fabricated** | `Σ submissions` this month from `form_stats_daily`. Conversion = Σ submissions ÷ Σ views (LGN-03: views, interactions, submissions and conversion are counted). Views and starts are posted by the public form, as counters with no visitor id. |

The submit path (SF-17), as one transaction in `worker_form_submit`, called by the public edge function on the public host (D-28):
1. Validate the answers against the published version (Zod at the edge, then again in SQL).
2. Check spam: a honeypot field, a minimum fill time, and a per-day-hash rate limit held in edge memory. No IP is stored.
3. Find the person by `lower(email)` or create one. Find the organization by `org_number` or create it, then queue Brønnøysund enrichment (0022).
4. Write the consent: when the box was ticked, `pending` plus a `consent_confirmations` token (double opt-in on) or `subscribed` (off), with `basis='consent'`, `text_id`, and `ref` set to the submission.
5. Create the lead, with `leads.form_data` = answers and `source = 'Web form'`. On resubmission, an open lead from the same form for the same person is updated, and the owner is kept (SF-17 step 6).
6. Create the ticket through a refactored `app.ticket_from_capture(...)`, so `app.ticket_intake` (Orgpuls's `contact.submitted`) and forms share one path.
7. Emit `form.submitted`.

The same refactor gives D-20's `contact.submitted → ticket and lead` its missing lead. 0012 notes "a lead, added with phase 5's capture".

**Firewall flag.** The seeded example «Send oss ansattlisten» (send us the employee list) is a file-upload form for employee lists. An employee list names future survey respondents. **Respondents are never contacts in the CRM** (brief's hard rule, D-34), so the platform must not collect it. Do not seed this form, and add the fixed rule in Q8.

### Chatbot and live chat (LGN-01, LGN-02, LGN-05, SF-30)

| Element | Prototype | Real |
|---|---|---|
| Playbooks (4) with Live/Draft | **Fabricated** | `chat_playbooks` (name, template, pages, state) |
| Steps 1 Theme · 2 Profile · 3 Template | literal | the playbook editor in three steps (LGN-01). Theme: palette key and button. Profile: name, avatar in the `email-assets` bucket, and language. Template: leads / meetings / qualify_route / live_chat, then a question list per page pattern. |
| Live chat header "visitor on /pris · Bergheim Bygg AS (identified) · 3rd visit" | **Fabricated** | `chat_conversations.page_path`. Company: `company_org_number`, resolved from the IP in memory at chat start, joined to `web_companies.name`. "Nth visit" = sessions with that org number in the last 30 days, which counts **the company's** visits. Cross-day visitor identity is impossible with the daily salt (D-37). |
| Messages, take over, send | local state | `chat_claim(id)`: the first claim wins (`update … where claimed_by is null`) and locks the chat to one rep (LGN-02). `chat_send(id, body)`. The visitor side polls `worker_chat_poll`. Until claimed, «Take over from bot» stays active. Once claimed by someone else, the panel is read-only, naming the rep. |
| Queue fallback | none | A conversation in `queued` for longer than the playbook's `queue_wait_seconds` returns to `bot` (`app.chat_fallback`, every minute). The online message shows when `chat_presence.online_until > now()`. |
| Transcript saved on the lead | none | A completed bot flow creates a lead (or a deal) with `answers`. Messages stay in `chat_messages`, shown on the lead's history (LGN-01 acceptance). |
| Per-step drop-off (LGN-01 RU) | absent | `playbook_stats(id, days)`: conversations per `last_step_key` where not completed. D-41: a small table under Playbooks. |
| Embed `<script async src="https://sentral.orgpuls.no/w.js" data-site="orgpuls-com">` | literal | `https://go.owntheagenda.com/w.js` with `data-site=<web_sites.key>` (**D-28 conflict**, Q1) |
| "Consent-gated loading: off (setting)" | literal | `app.setting('widget_consent')` |
| "Never loaded on survey pages (svar.orgpuls.no) — fixed" | literal | Enforced three ways: `w.js` exits when the host matches the survey-host denylist; `web_sites` refuses such hostnames by a check constraint; `worker_web_ingest` drops them. A fixed register row and a test (Q8). |

Real-time delivery under D-09 (no client grant on any table) is open question Q10.

### Prospect search (LGN-04)

| Element | Prototype | Real |
|---|---|---|
| Person filters (Job title, Department, Location) and organization filters (Size, Industry, Revenue, Keyword or domain) | uncontrolled inputs with literal values | the query sent to the prospect-data adapter (provider `contact_data`, 0022). LGN-04 also lists name, type and location for organizations. Saved with `view_save(screen='prospect_search')` (0009). |
| "1 284 prospects" | **Fabricated** | the provider's total for the query, or `not_connected` |
| "Credits 618" | **Fabricated**, decremented locally | used this month = `−Σ credit_ledger.delta` this month. The limit is `app.count_limit()`: unlimited by default (D-17), in which case it shows "used N". |
| Result rows with name, title, company, meta and masked contact | **Fabricated** (fictional people with real-looking emails and phones) | provider results. **Never stored** until revealed. |
| Reveal · 1 credit → "Added as lead" | local state | `prospect_reveal(provider_ref)`:<br>1. With `contact_rule` = `opt_in_only`, refused (`invalid`, detail `contact_rule`).<br>2. Calls the provider (edge worker).<br>3. Creates the person (`source='Prospect search'`, `contact_type='prospect'`, `marketing_status='no_consent'`) and organization, and a lead.<br>4. Writes `prospect_reveals` and one `credit_ledger` row (−1).<br>5. A repeat reveal of the same `provider_ref` costs nothing. |
| Save filter | toast | `view_save` |

### Web visitors (WEB-01..04, SF-18, D-37)

| Element | Prototype | Real |
|---|---|---|
| "Tracker on 2 sites · orgpuls.com · skiftly.no" | **Fabricated** | `web_sites where active and last_seen_at > now() − 7 days`. Seeded rows today are `www.owntheagenda.com` and `orgpuls.com` (0025). |
| "ISPs, crawlers and irrelevant traffic filtered" | literal | true only while the IP-to-company adapter is connected. It drops ISPs and unresolved traffic, and bots are dropped by user agent. |
| "identification on (setting)" | literal | `app.setting('web_ident')`. When off, the edge function skips company resolution and the tab shows the off state. |
| Rank, company, industry | **Fabricated** | `visitors_list(days, filters)`: `web_sessions where company_org_number is not null and day > current_date − days group by company_org_number`. Rank orders by Σ pageviews desc, then by last visit desc (WEB-03 acceptance: "most active first"). Name and industry come from `web_companies` (a Brønnøysund cache), overridden by the CRM organization's name when one exists. |
| Location "Lillestrøm, NO" | **Fabricated** | `web_companies.city`, `country`: **the company's registered address, not the visitor's location**. Label it so. |
| Source | **Fabricated** | the channel of the company's latest session (`web_sessions.channel` via `channel_rules`), shown through message keys |
| Last visit, Pages | **Fabricated** | `max(started_at)`, `Σ pageviews` in the period |
| Detail: "existing organization in CRM / not in CRM yet" | literal flag | `exists (organizations where org_number = … and deleted_at is null and not is_sample)` |
| Visit history (same 5 rows for every company) | **Fabricated** | `visitor_get(org_number, days)`: pageviews of the company's sessions, newest first. Time on page = the next pageview's `at` − `at` within the session; "—" for the last page of a session. |
| Filters (WEB-03 RU: period, country, campaign, page, already in CRM) | absent | period 30/90/365 days; campaign = `utm->>'utm_campaign'`; page = an `exists` on `web_pageviews.path like`; in CRM yes/no. Country is always NO, because `company_org_number` is Norwegian only (Q15). D-41: a filter row in the design's pill style. |
| Create lead / Create deal / Create organization | toasts | `visitor_convert(org_number, kind, pipeline?, stage?)`: find or create the organization by org number (fields from `web_companies`, changelog source `capture`), then a lead or deal with `source = 'Web visitors'`. The visit history links through `organizations.org_number`, so no link table is needed (WEB-04 acceptance). Emits `lead.created` / `deal.created`. |
| Find people here | switches tab | opens Prospect search prefilled with the company's name and domain (`web_companies.website`). Reveals use credits (WEB-04). |

`visitor.identified` is emitted once per CRM organization per day, when its first session is ingested. It drives the owner's feed and workflows.

WEB-02 "A company counts once per month for billing" is the usage count `count(distinct company_org_number)` per month. It counts the IP-to-company provider's usage (D-17) and stores no new row.

**Personal-data flag.** An org number of form ENK (enkeltpersonforetak) identifies a natural person. `web_companies.excluded = true` for ENK. Such sessions keep `company_org_number = null` at ingest (Q16).

### Conflicts with decisions (Marketing)
1. **D-28.** The embed host is `sentral.orgpuls.no/w.js`. Public scripts, forms, chat, unsubscribe and confirmation pages belong on `go.owntheagenda.com`, with unguessable revocable tokens.
2. **D-37.** "cookie ID" in the form's hidden tracking fields conflicts with the cookieless tracker.
3. **D-27.** The prototype lets the footer (unsubscribe and sender identity) be removed. This must be fixed.
4. **D-16 versus the design.** "Double opt-in for newsletter signups" is a restricting rule, so D-16 would default it to off. The design and the brief's best practice say on (Q3).
5. **D-19 / D-34.** The transactional stream row shows bounce and complaint rates for survey invitations, and «Send oss ansattlisten» would collect employee lists. Per-recipient invitation events and employee lists must never enter the platform.
6. **D-17.** "Pending upgrade" and credit balances assume a sold allowance. With nothing sold, both are usage counts against an optional limit.

---

## 2. Documents screen (route `documents`, DOC-01..06, UF-08, SF-20, SF-33)

### Views and states
- **Tabs:** Documents (default), Templates, E-signature, Storage and branding.
- **Global button:** «＋ Document from template».
- **Overlays:** a toast only.
- **Module:** `documents`.

The design has no states beyond the filled ones. D-41 adds:
- **Documents:** no documents (CTA); a document with no deal (uploaded); a link never opened (the design already has "Not opened yet"); a revoked link.
- **Templates:** no templates; drive import `not_connected`.
- **E-signature:** no document selected (opened from the tab rather than from «Request signature»); the email provider `not_connected` (OTP and invitations cannot be sent); external service `not_connected`; a request in each status (sent, in progress, completed, declined, expired, canceled).
- **Storage and branding:** no drive connected (the default location is "Platform storage").
- **No permission:** the tab is hidden; calls return `forbidden`.
- **Loading:** skeletons.

### Documents tab

| Element | Prototype | Real source / formula |
|---|---|---|
| Rows: Document + template, Deal, Status, Opens, Stored in | **Fabricated** (literal `DO`; deal titles from random demo deals) | `documents_list({status, deal_id, q})`: `documents` joined to `deals.title`. Opens = `count(*) from document_views where client_class <> 'prefetch'`. Stored in = `documents.storage` (Platform / Google Drive / OneDrive / SharePoint). |
| Status pills Draft, Sent, Opened, Awaiting signature, Signed | **Fabricated** | `documents.status`, moved by events: draft → sent (first link created or emailed) → opened (first human view) → awaiting_signature (request sent) → signed (all signers). D-41 adds declined, expired and revoked. |
| Preview header "Tilbud T-101 · 5. oktober 2026" | **number derived from the deal id; date literal** | `documents.number` = the template's `number_prefix` + a per-prefix sequence (`document_counters`); date = `documents.created_at`, in the template's language |
| "Tilbud til <org> · Til <person> · <orgnr> · gyldig til 19. oktober" | org, person and orgnr from demo data; **validity literal** | merge values from the deal's organization and person, with `org_number` formatted as `### ### ###`. `valid_until = created_at::date + template.validity_days`. |
| Product table rows | **Fabricated**: d101 has two hard-coded lines; every other deal gets `value/12` as one line | `deal_items` (0009) of the deal: name, quantity, unit price, discount, tax and line total, using the template's `product_table.columns` (DOC-02: configurable columns) |
| Totals: Sum eks. mva, Mva 25 %, Totalt | computed from fabricated lines; **VAT hard-coded at 25 %** | per line `qty × price × (1 − discount)`; VAT grouped by `deal_items.tax_rate`. **DOC-02's acceptance test ("table totals equal the deal value") only holds for one-off lines.** `deals.value` is TCV when `value_source='items'` (`app.deal_revenue`). The table adds rows "Per month" (MRR), "One-off" and "Total contract value ex. VAT" = `deals.value` (Q13). |
| "Product table filled from the deal · placeholders: [deal.title] [person.name] [organization.orgnr] [product.table]" | literal | the template's tokens. **This token syntax differs from the existing registry** (`[Person.navn]`, `[Avtale.tittel]`, 0020), and `[signer.1]` does not even match `app.merge_render`'s regex (Q5). |
| Trackable link `docs.orgpuls.no/s/k7Qd101xZ2` | **token derived from the deal id (guessable)** | `document_link_create(doc, recipient?)` returns a random token **once**. Only `token_sha256` is stored. Host `go.owntheagenda.com/d/<token>` (**D-28 conflict**). |
| Views: "Kari Nordmann · Bergen — Yesterday 18:40 · 4 min", "Unknown viewer · forwarded" | **Fabricated** (sliced to the literal opens count) | `document_views` of the document's links. Who = the link's recipient, when the link was made per recipient, else "Anyone with the link". When = `started_at`. Duration = `duration_seconds` from the viewer page's heartbeat. **No city** (it would need the IP; D-37 spirit) and **no "forwarded"** (cannot be known without cookies or fingerprinting). |
| Copy link → "each open is recorded" | toast | copies the link returned at creation. A lost token is replaced by a new link. Every open notifies the owner (DOC-04) and writes a deal history entry. |
| Revoke | toast | `document_link_revoke(link)` sets `revoked_at`. The viewer answers 410 at once. |
| Request signature | switches tab | opens E-signature for this document |
| «＋ Document from template» → "Document created from «Tilbud — standard» in Google Drive" | toast | a dialog picks the template and the deal, then `document_create(template, deal)`:<br>1. Renders merge fields and the product table into `body_html`, storing `merge_missing`.<br>2. Status draft. Missing values are flagged in the dialog and block sending (DOC-01 RU), not creation.<br>3. Stores in the default location: a Google Doc or Word copy through the drive adapter, or platform storage without a drive.<br>4. Renders a PDF into the `documents` bucket. Generated PDFs are always stored in the platform (DOC-03 RU). |
| Uploaded PDF row ("Uploaded: Kundens innkjøpsvilkår.pdf") | literal | `document_upload(deal, file)`: the file goes into the bucket under the deal's visibility (SF-33). Status draft. Shareable by link and signable. |

### Templates (DOC-01)

| Element | Prototype | Real |
|---|---|---|
| Category pills All, Quotes, Contracts, Presentations, Spreadsheets | filter a literal list | `document_templates.category` |
| Cards: kind placeholder, name, "category · share", placeholder chips | **Fabricated** | name, kind (document / presentation / spreadsheet), category, share (Company-wide / <team name> / Private, from `share` + `team_id`), and `placeholders` = the distinct tokens found in the body when saved |
| Import from drive | toast | `doc_template_import(provider, file_ref)`: `not_connected` without the caller's drive connection. A presentation or spreadsheet template is only possible through a drive (Google Slides or Sheets, PowerPoint or Excel). The platform renders documents natively. |
| Missing per D-41 | — | create, edit, duplicate and archive a template; the product-table column picker (not for spreadsheets, DOC-02 RU); validity days and number prefix for quotes; the brand (product) |

Placeholders the design uses: `[deal.title] [deal.value] [deal.currency] [person.name] [organization.name] [organization.orgnr] [organization.employees] [product.table] [signer.1] [project.start]`. Each needs a source:
- `[project.start]` waits for Projects (phase 6). Until then it is flagged as unknown, never filled.
- `[signer.N]` is not text: it marks a signature-field anchor for the E-signature tab.
- Address parts (DOC-01 RU: "address fields can be split") need `organization.address`, `organization.postal_code` and `organization.city` as separate tokens.

### E-signature (DOC-05)

| Element | Prototype | Real |
|---|---|---|
| Page preview "Avtale om bruk av Skiftly" with grey lines | decorative skeleton | page images of the document's PDF (rendered by the worker), paged |
| Signer fields (Signature · Kari, Date · Kari …) at fixed x/y % | **Fabricated** positions; click-select only, **no drag** | `signature_fields` (signer, kind, page, x, y, w, h in % of the page). Drag-and-drop placement must be built (DOC-05; D-41). Initial positions come from `[signer.N]` anchors when the template has them. |
| Signers list with status ("Opened · code verified", "Waiting") | **Fabricated** names and emails | `signature_signers` (name, email, order, colour, status from events) |
| ＋ Signer (capped at 4 by the colour array) | local; **cap 4** | no cap by default. With `count_limits` = a number, that number (DOC-05 names 10 as the source value, D-16). The copy "Signers: unlimited (setting · source reference 10)" stays and follows the real setting. |
| Message (literal Norwegian default), Invite language (Norsk bokmål / English / Svenska), One-time code by email (checked) | uncontrolled | `signature_requests.message` (≤ 2 000 chars), `language` (nb/en/sv), `otp_required` (default true) |
| Send for signature → "Signature request sent · status shows on the deal" | toast | `signature_request_send(id)`:<br>1. Refuses with `invalid` (detail `merge`) when the document has missing merge values, and with `invalid` (detail `fields`) when a signer has no signature field.<br>2. Refuses with `not_connected` without the email provider (built-in), or without the external adapter.<br>3. Freezes `original_sha256` and sets the document to awaiting_signature.<br>4. Emails each signer a link (`go.owntheagenda.com/s/<token>`) and, when they open it, an OTP. |
| "evidence package (audit trail, hashes) stored with the document" | literal | `signature_events` is an append-only hash chain. On completion the worker produces the sealed PDF (`sealed_pdf_path`, `sealed_sha256`) plus an audit-trail page, stored in the platform and on the deal (DOC-05 acceptance). Emits `document.completed`. |

The signing flow is SF-20 steps 3–6 via the `worker_sign_*` functions: view → OTP sent → OTP verified (at most 5 attempts; a new code after 10 min) → fields filled → signed. A decline records a reason (≤ 500 chars). **SF-20 step 4 says "recorded with time and address"**: this spec reads "address" as the signer's verified email address. No IP is stored (Q9).

### Storage and branding (DOC-03, DOC-06)

| Element | Prototype | Real |
|---|---|---|
| Cloud storage: Google Drive "Connected · tor@orgpuls.no · Default", OneDrive "Connected via Microsoft 365", SharePoint "Site «Salg»" | **Fabricated** | `drive_connections` per staff member (provider, account email, status; token in Vault per D-18). The company default is `document_storage_default` (provider and location). "Default" marks that row. Choosing a row calls `doc_storage_set_default` (requires `global:configure`). A not-connected provider shows «Connect», which returns the adapter's OAuth URL, or `not_connected` when no OAuth client is configured. |
| Location: "Shared drive · Salg/Tilbud" / "Personal drive" | literal options | `document_storage_default.location` (`{kind: 'shared'|'personal', drive_id, folder_id, label}`), picked from the provider's folder list. DOC-03: personal or shared location, with a company default. |
| Remove platform branding (toggle, on) — "Documents and signing pages show only Orgpuls" | local state | setting `doc_branding` (`hidden` / `shown`, default `hidden` as designed). **"only Orgpuls" is wrong for a multi-product platform**: documents carry the brand of `deals.product` (Skiftly quotes show Skiftly). The preview's hard-coded Orgpuls mark becomes the product's mark (Q12). |
| Built-in e-signature / External service | local state | setting `esign_service` (`builtin` / `external`). External needs `integration_connections` provider `esign` and its adapter, which reports status through `worker_esign_status` back to the deal (DOC-06 acceptance). |

### Conflicts with decisions (Documents)
1. **D-28.** `docs.orgpuls.no/s/…` must become `go.owntheagenda.com/d/<token>` for viewing and `/s/<token>` for signing. Tokens are unguessable, only their SHA-256 is stored, and they are revocable. The prototype's token is built from the deal id.
2. **D-37 spirit / no IP.** The views list's city and SF-20's "address" both imply an IP.
3. **D-16.** The prototype caps signers at 4. The rule is unlimited by default.
4. **DOC-02 versus `deal_revenue`.** Table totals cannot equal a TCV deal value with recurring lines unless the TCV row is added.

---

## 3. IDs these screens implement (with acceptance tests)

| ID | Name | Acceptance test (coverage-data.js) | Where |
|---|---|---|---|
| CMP-01 | Email builder | A built email renders in the preview as it is delivered | Builder |
| CMP-02 | Templates | A template can start a new campaign | Builder «Start from» |
| CMP-03 | Audience | The recipient count equals subscribed matches of the filter | Audience |
| CMP-04 | Marketing status and consent | An unsubscribed address cannot be mailed by any campaign | Audience, consent log |
| CMP-05 | Scheduling and sending | A scheduled campaign leaves at the set time | Builder › Schedule |
| CMP-06 | Campaign analytics | Figures match provider events for the campaign | Campaigns card |
| CMP-07 | Automated campaigns | A triggered email obeys consent status | Campaigns (Automated), Automation step `campaign_action` |
| CMP-08 | Deliverability | An unauthenticated domain cannot send | Deliverability |
| CMP-09 | Campaign insights | The comparison shows the same figures as each campaign's own report | Compare; Insights entity `campaign` |
| LGN-01 | Chatbot | A completed conversation creates a lead with the answers stored | Chat |
| LGN-02 | Live chat | A claimed chat is locked to one rep and saved on the lead | Chat |
| LGN-03 | Web forms | A submission creates a lead with source and tracking data; views, interactions, submissions and conversion are counted | Web forms |
| LGN-04 | Prospect search | Revealing a prospect uses one credit and creates a lead | Prospect search |
| LGN-05 | Embedding and consent | With the consent setting on and consent declined, no tracking cookie is set. No widget ever appears on a survey page | Chat › Embed |
| WEB-01 | Tracker | Visits from each site appear under that site | Visitors |
| WEB-02 | Organization identification | A known company IP produces a named visitor | Visitors |
| WEB-03 | Visitor inbox and ranking | Sorting by quality puts the most active companies first | Visitors |
| WEB-04 | Convert and reveal | The created record links to the visit history | Visitors detail |
| DOC-01 | Templates and merge fields | A document generated from a template contains the deal's data | Templates, ＋ Document |
| DOC-02 | Product tables | Table totals equal the deal value (see Q13) | Preview |
| DOC-03 | Cloud storage | A new document appears in the connected drive | Storage |
| DOC-04 | Trackable links | An open is logged with time on the deal | Trackable link |
| DOC-05 | E-signatures | A completed request stores the signed PDF and audit trail on the deal | E-signature |
| DOC-06 | Branding and external signing | A document sent through the external service shows its status on the deal | Storage and branding |
| CRM-15 / LEA-04 | Source fields / lead creation | Every channel produces a lead with the right source | Forms («Web form»), chat («Chatbot», «Live chat»), reveal («Prospect search»), visitors («Web visitors»), campaigns («Campaign») |
| CRM-05 / SF-33 | File attachments | A user who cannot see the record cannot fetch the file | Documents bucket, form uploads |
| PIP-04 | Deal detail | (Documents tab and the history's documents/engagement filters) | Deal panel reads `documents`, `document_views`, `signature_events` |
| PIP-16 | Capacity and waitlist | No payload is lost when the limit is hit | Form and chat leads go to the waitlist only when a capacity limit is set (none by default) |
| COM-05 | Merge fields | A missing merge value is flagged before sending | Shared registry for emails, campaigns and documents |
| AUT-07 | Actions: campaign actions | Every action type completes or reports an error in the run history | `campaign_action` replaces `not_available:campaigns` |
| SEC-11 | Privacy compliance | An erasure request removes the person from every module | §10 |
| ENT-02 | Usage limits | A limit is enforced at the moment of creation | signers, subscriber allowance, credits |

Flows (end-to-end tests follow their steps, D-42):
- **UF-08 Quote to signature:** DOC-01..06, CRM-07, AUT-01.
- **UF-17 Send an email campaign:** CMP-01..09.
- **UF-18 Website visitor to lead:** LGN-01..05, LEA-01, AUT-11, COM-10.
- **UF-19 Identify web visitors:** WEB-01..04, LGN-04.
- **UF-01 Capture and qualify a lead:** steps 1–3.
- **System flows:**
  - SF-17 (lead capture from forms and chat);
  - SF-18 (web visitor identification);
  - SF-19 (campaign send);
  - SF-20 (document and signature);
  - SF-30 (live-chat routing);
  - SF-39 (campaign authoring and insights);
  - SF-33 (files);
  - SF-05 (sequence enrollment from a form);
  - SF-11 step 1 (credit check for reveal).
- **Phase gates (07-IMPLEMENTATION-PLAN):** phase 5 gates on UF-08, 18, 19 and SF-17, 18, 20, 30; phase 6 on UF-17 and SF-19, 39.

Settings register rows that apply:
- `contact_rule` (LGN-04, WEB-04);
- `tracking` (COM-06; extend `applies_to` to CMP-06);
- `form_tracking` (LGN-03);
- `web_ident` (WEB-01..04);
- `widget_consent` (LGN-05);
- `count_limits` (DOC-05 signers);
- `plan_gates` (CMP-05 allowance, CMP-09 tier);
- `typed_reason` and `firewall` (all).

Part F entities:
- **Marketing:** consent record and suppression list ("existing" in the brief, built here per D-01), segment, campaign, campaign_recipient, campaign_event, sender_domain.
- **Lead generation:** chatbot_playbook, chat_conversation, chat_message, web_form, form_submission.
- **Web visitors:** tracked_site, visitor_company, visit.
- **Documents:** document_template, document, document_link, signature_request, signer, signature_event.
- **Prospecting:** credit_ledger.

Part F events:
- **Capture:** form_submitted, chat_completed, visitor_identified.
- **Campaign:** sent, delivered, bounced, unsubscribed, complained.
- **Document:** generated, opened, signed, completed.

Part G areas, which have no numbered IDs:
- **Anonymity firewall:** never in the survey flow; no respondent contacts.
- **Rule settings.**
- **Access.**
- **Audit:** every write and read audited (D-12).
- **Data residency:** EU-hosted providers.
- **Sending:** separate streams.
- **Job runtime.**
- **Monitoring:** send failures and bounces alert the owner.
- **Privacy.**
- **Provider independence:** adapters for email, IP-to-company, prospect data, drive and e-sign.
- **Test data:** the seed carries only demo tenant rows.

---

## 4. Data model (schema `app`, RLS on, no policy, no client grant; access through security-definer RPCs; tests per D-03/D-09)

Standard columns on business records, as in 0006: `id`, `version`, `created_at/by`, `updated_at/by`, `deleted_at`, `is_sample`, plus `owner_id`, `visibility`, `labels` and `custom` where owned. Every append-only trigger is written as "nobody may change this content; a delete is allowed only when the parent is already gone", as `app.consent_fixed` is (0011).

### EXISTING tables, altered
```
people                 marketing_status check += 'archived'   -- 'pending' keeps meaning «pending double opt-in»
consent_events         status check += 'archived';
                       + prev_status text, + email_sha256 bytea,           -- the address the consent is for (CMP-04)
                       + ref_type text check (ref_type in ('form_submission','campaign','chat','import','prospect','staff','provider','confirmation','list_hygiene','email_changed')),
                       + ref_id uuid, + detail text check (char_length(detail) <= 120),   -- a code ('550', 'one_click'), never free text
                       + text_id uuid references consent_texts(id)
                       trigger on people: update of email → consent event 'no_consent' source 'email_changed' unless the new address is consented
saved_views            + kind text not null default 'view' check (kind in ('view','segment')), + description text (≤300), + updated_at timestamptz
email_templates        + kind text not null default 'sales' check (kind in ('sales','marketing')), + layout boolean not null default false,
                       + design jsonb check (design is null or jsonb_typeof(design)='object'), + html text check (char_length(html) <= 500000),
                       + category text (≤40), + current_version int not null default 1, + version int not null default 1
                       templates_get() keeps returning kind='sales' only, so the Inbox is unchanged
merge_fields           + contexts text[] not null default '{email}' check (contexts <@ '{email,campaign,document}'),
                       format check += 'block' (product.table), 'orgnr', 'date';
                       new rows for the document tokens (Q5); merge_value extended to address parts, deal.currency, org_number
web_sites              + key text unique check (key ~ '^[a-z0-9-]{2,40}$'),       -- data-site in the embed
                       + last_seen_at timestamptz, + chat_enabled boolean not null default false,
                       + check (hostname !~ '(^|\.)svar\.')                       -- survey hosts can never be tracked (LGN-05, fixed)
web_sessions           index (company_org_number, day) where company_org_number is not null
credit_ledger          + reveal_id uuid references prospect_reveals(id) on delete set null
integration_connections provider check += 'email', 'ip_company', 'esign'
changelog              source check += 'capture'                                  -- forms, chat, reveal, visitor conversion
entities               + ('campaign','campaigns','campaigns','campaigns', owned), ('form','forms','campaigns','leadgen', owned),
                       ('document','documents','deals','documents', owned), ('document_template','document_templates','deals','documents', owned)
app.entity_route       + campaign → /campaigns, form → /leadgen, document → /documents
app.wf_kinds / wf_blockers / wf_step   campaign_action implemented (see §7); blockers 'not_connected:email', 'sender_domain_unverified'
app.ticket_intake      refactored onto app.ticket_from_capture(category, subject, email, organization, message, channel, source_ref)
reports (0024)         report entity 'campaign' added to the builder whitelist (INS-01, CMP-09)
```

### NEW: consent and suppression
```
consent_texts(id uuid pk, key text check (key ~ '^[a-z_]{2,40}$'), locale text check (locale in ('nb','nn','en','sv')),
              body text check (char_length(body) between 1 and 2000), version int not null, created_by uuid, created_at,
              unique (key, locale, version))                                     -- the wording shown (art. 7(1) proof); append-only
consent_confirmations(token_sha256 bytea pk, person_id uuid not null references people on delete cascade, email_sha256 bytea not null,
              submission_id uuid references form_submissions on delete set null, expires_at timestamptz not null, confirmed_at timestamptz,
              created_at)                                                       -- double opt-in links, valid 7 days
suppressions(email_sha256 bytea not null, scope text not null check (scope in ('marketing','all')),
              reason text not null check (reason in ('unsubscribed','complaint','hard_bounce','soft_bounces','manual','erasure')),
              campaign_id uuid references campaigns on delete set null, created_by uuid, created_at,
              primary key (email_sha256, scope))                                -- keyed by hash, so it survives erasure
```

### NEW: campaigns
```
sender_domains(id uuid pk, domain text unique check (domain = lower(domain) and domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
              stream text not null check (stream in ('marketing','transactional')), sends_here boolean not null default true,
              product text references products(key), from_name text not null (1..120), from_local text not null default 'news' check (from_local ~ '^[a-z0-9._-]{1,40}$'),
              reply_to text (≤254), postal_address text (≤300),          -- sender identity; required before a marketing send (D-27)
              provider_domain_id text, spf_ok boolean, dkim_ok boolean, dmarc_policy text check (dmarc_policy in ('none','quarantine','reject')),
              verified_at timestamptz, check_detail jsonb not null default '{}', last_checked_at timestamptz,
              warmup_started_at date, warmup_days int not null default 30 check (warmup_days between 0 and 120),
              created_by uuid, created_at, deleted_at)
campaigns(id uuid pk, seq bigint identity unique, name text (1..120),
              type text not null check (type in ('newsletter','one_off','promotion','product_announcement','automated')),
              status text not null default 'draft' check (status in ('draft','scheduled','sending','sent','active','paused','canceled')),
              segment_id uuid references saved_views on delete set null, template_id uuid references email_templates on delete set null,
              design jsonb not null default '{"rows":[]}' check (jsonb_typeof(design)='object'), rendered_html text,
              subject_a text not null default '' (≤200), subject_b text (≤200), preheader text (≤200),
              ab_percent smallint check (ab_percent between 2 and 50), ab_metric text check (ab_metric in ('opens','clicks')),
              ab_wait interval check (ab_wait between '1 hour' and '72 hours'), ab_winner text check (ab_winner in ('a','b')), ab_decided_at timestamptz,
              sender_domain_id uuid references sender_domains, product text references products(key),
              coupon_code text references coupons(code), utm_source text not null default 'newsletter', utm_medium text not null default 'email',
              utm_campaign text not null check (utm_campaign ~ '^[a-z0-9_-]{1,60}$'), tracking boolean not null default true,
              notify_owners boolean not null default false, scheduled_at timestamptz, started_at timestamptz, sent_at timestamptz, audience_count int,
              + standard owned columns,
              check (subject_b is null or (ab_percent is not null and ab_metric is not null and ab_wait is not null)),
              check (coupon_code is null or type = 'promotion'),
              check (status = 'draft' or type = 'automated' or segment_id is not null))
              unique index (utm_campaign) where deleted_at is null and not is_sample
campaign_links(id uuid pk, campaign_id uuid not null references campaigns on delete cascade, url text check (url ~ '^https?://' and char_length(url) <= 2000),
              label text (≤200), token text unique check (token ~ '^[A-Za-z0-9_-]{22,64}$'))
campaign_recipients(id uuid pk, campaign_id uuid not null references campaigns on delete cascade,
              person_id uuid references people on delete set null, email text,              -- blanked on erasure
              send_key text not null default 'once',                                         -- automated: the workflow run step
              variant text check (variant in ('a','b','w')),
              state text not null default 'queued' check (state in ('queued','sent','delivered','soft_bounced','bounced','complained','failed','skipped')),
              skip_reason text check (skip_reason in ('not_subscribed','suppressed','no_email','duplicate','over_allowance')),
              provider_message_id text unique, unsub_token text unique check (unsub_token ~ '^[A-Za-z0-9_-]{22,64}$'),
              sent_at, delivered_at, first_open_at, opens int not null default 0, first_click_at, clicks int not null default 0,
              unsubscribed_at, complained_at, bounced_at, bounce_kind text check (bounce_kind in ('hard','soft')),
              city text (≤80), country char(2),                                              -- provider geo; never an IP
              is_sample boolean, unique (campaign_id, person_id, send_key))
              index (campaign_id, state)
campaign_events(id bigint identity pk, recipient_id uuid not null references campaign_recipients on delete cascade, campaign_id uuid not null,
              kind text not null check (kind in ('sent','delivered','bounced','opened','clicked','unsubscribed','complained')),
              bounce_kind text, smtp_code text check (smtp_code ~ '^[245]\d\d$'), link_id uuid references campaign_links on delete set null,
              client_class text not null default 'unknown' check (client_class in ('human','prefetch','unknown')),
              provider_event_id text unique,                                                 -- idempotent webhook ingest
              at timestamptz not null)                                                       -- pruned after 13 months (D-24)
v_campaign_stats (view over campaign_recipients + attribution): recipients, sent, delivered, bounced, unique_opens, total_opens,
              unique_clicks, total_clicks, unsubscribed, complaints, open_rate, click_rate, ctor, unsub_rate, a_metric, b_metric, signups, mrr_won
email_template_versions(template_id uuid references email_templates on delete cascade, version int, subject text, body text, design jsonb, html text,
              created_by uuid, created_at, primary key (template_id, version))
```

### NEW: lead capture
```
forms(id uuid pk, public_id text unique not null default app.token(), name text (1..120),
              kind text not null check (kind in ('contact','registration','gated_download','file_upload','blank')),
              language text not null check (language in ('nb','nn','en','sv')),        -- fixed at creation: trigger refuses a change
              status text not null default 'inactive' check (status in ('active','inactive')),
              draft jsonb not null check (jsonb_typeof(draft)='object'),            -- {intro{title,body}, fields[], hidden[], consent{text_key, double_opt_in}, after_submit{}}
              current_version int not null default 0, site_id uuid references web_sites on delete set null,
              + standard owned columns)
form_versions(form_id uuid references forms on delete cascade, version int, definition jsonb not null, published_by uuid, published_at,
              primary key (form_id, version))
form_submissions(id uuid pk, form_id uuid not null references forms on delete cascade, form_version int not null,
              state text not null check (state in ('accepted','spam','duplicate')),
              answers jsonb not null check (jsonb_typeof(answers)='object'), tracking jsonb not null default '{}',   -- {} when form_tracking is off
              consent jsonb not null default '{}', person_id uuid references people on delete set null,
              organization_id uuid references organizations on delete set null, lead_id uuid references leads on delete set null,
              deal_id uuid references deals on delete set null, ticket_id uuid references tickets on delete set null,
              files jsonb not null default '[]' check (jsonb_typeof(files)='array'), is_sample boolean, created_at)
form_stats_daily(form_id uuid references forms on delete cascade, day date, views int default 0, starts int default 0, submissions int default 0,
              primary key (form_id, day))
chat_playbooks(id uuid pk, name text (1..120), template text not null check (template in ('leads','meetings','qualify_route','live_chat')),
              state text not null default 'draft' check (state in ('draft','live')), site_ids uuid[] not null default '{}',
              pages text[] not null default '{}' check (cardinality(pages) <= 50),        -- path patterns, '*' suffix allowed
              theme jsonb not null default '{}', profile jsonb not null default '{}', steps jsonb not null default '[]',
              creates text not null default 'lead' check (creates in ('lead','deal')), pipeline_id uuid references pipelines, stage_id uuid references stages,
              booking_link_id uuid references booking_links on delete set null,
              queue_wait_seconds int not null default 60 check (queue_wait_seconds between 10 and 900),
              offline_message text (≤500), current_version int not null default 0, + standard owned columns)
chat_playbook_versions(playbook_id, version, definition jsonb, published_by, published_at, primary key (playbook_id, version))
chat_conversations(id uuid pk, playbook_id uuid references chat_playbooks on delete set null, playbook_version int, site_id uuid references web_sites,
              page_path text (≤500), company_org_number text check (company_org_number ~ '^\d{9}$'),
              visitor_token_sha256 bytea unique not null, language text,
              state text not null default 'bot' check (state in ('bot','queued','live','closed')),
              queued_at, claimed_by uuid references admins on delete set null, claimed_at, closed_at,
              last_step_key text, completed boolean not null default false, answers jsonb not null default '{}',
              person_id uuid references people on delete set null, lead_id uuid references leads on delete set null,
              deal_id uuid references deals on delete set null, is_sample boolean, started_at timestamptz not null default now(),
              check ((state = 'live') = (claimed_by is not null and closed_at is null)))
chat_messages(id bigint identity pk, conversation_id uuid not null references chat_conversations on delete cascade,
              sender text not null check (sender in ('bot','visitor','staff','system')), staff_id uuid references admins on delete set null,
              body text not null check (char_length(body) between 1 and 4000), at timestamptz not null default now())
chat_presence(staff_id uuid pk references admins on delete cascade, online_until timestamptz not null)
prospect_reveals(id uuid pk, provider text not null default 'contact_data', provider_ref text not null (≤200),
              person_id uuid references people on delete set null, organization_id uuid references organizations on delete set null,
              lead_id uuid references leads on delete set null, credits int not null default 1, revealed_by uuid references admins, revealed_at,
              unique (provider, provider_ref))
web_companies(org_number text pk check (org_number ~ '^\d{9}$'), name text not null (≤200), org_form text (≤10), nace text, industry text,
              city text, fylke text, country char(2) not null default 'NO', employees int, website text,
              excluded boolean not null default false,                                   -- ENK: a natural person (Q16)
              source text not null default 'brreg', fetched_at timestamptz not null)
```

### NEW: documents and e-signature
```
document_templates(id uuid pk, name text (1..120), kind text not null check (kind in ('document','presentation','spreadsheet')),
              category text not null check (category in ('quotes','contracts','presentations','spreadsheets','other')),
              share text not null default 'private' check (share in ('company','team','private')), team_id uuid references teams on delete set null,
              product text references products(key), language text not null default 'nb' check (language in ('nb','nn','en','sv')),
              source text not null default 'platform' check (source in ('platform','google','microsoft')), external_file_id text,
              body_html text check (char_length(body_html) <= 500000), product_table jsonb,  -- {columns:[name,qty,price,discount,tax,total,period]}
              validity_days int check (validity_days between 1 and 365), number_prefix text check (number_prefix ~ '^[A-Z]{1,4}-$'),
              placeholders text[] not null default '{}', current_version int not null default 1, + standard owned columns,
              check ((share = 'team') = (team_id is not null)), check (kind = 'document' or source <> 'platform'),
              check (kind <> 'spreadsheet' or product_table is null))
document_template_versions(template_id, version, body_html, product_table, created_by, created_at, primary key (template_id, version))
document_counters(prefix text pk, next int not null default 1)
documents(id uuid pk, number text unique, name text (1..200), template_id uuid references document_templates on delete set null, template_version int,
              kind text not null, source text not null check (source in ('template','upload')),
              deal_id uuid references deals on delete set null, organization_id uuid references organizations on delete set null,
              person_id uuid references people on delete set null, product text references products(key),
              status text not null default 'draft' check (status in ('draft','sent','opened','awaiting_signature','signed','declined','expired','revoked')),
              body_html text, merge_missing text[] not null default '{}', totals jsonb, valid_until date,
              storage text not null default 'platform' check (storage in ('platform','google','onedrive','sharepoint')),
              external_file_id text, external_url text, pdf_path text, pdf_sha256 bytea, size_bytes bigint check (size_bytes <= 26214400),
              sent_at, first_opened_at, last_opened_at, signed_at, + standard owned columns,
              check (deal_id is not null or organization_id is not null))
document_links(id uuid pk, document_id uuid not null references documents on delete cascade, token_sha256 bytea unique not null,
              recipient_person_id uuid references people on delete set null, label text (≤120), notify_owner boolean not null default true,
              expires_at timestamptz, revoked_at timestamptz, created_by uuid, created_at)
document_views(id bigint identity pk, link_id uuid not null references document_links on delete cascade, document_id uuid not null,
              started_at timestamptz not null, duration_seconds int not null default 0 check (duration_seconds between 0 and 86400),
              client_class text not null default 'unknown' check (client_class in ('human','prefetch','unknown')))   -- no IP, no city
signature_requests(id uuid pk, document_id uuid not null references documents on delete cascade,
              status text not null default 'draft' check (status in ('draft','sent','in_progress','completed','declined','canceled','expired')),
              service text not null check (service in ('builtin','external')), external_id text, message text (≤2000),
              language text not null default 'nb' check (language in ('nb','en','sv')), otp_required boolean not null default true,
              signing_order text not null default 'parallel' check (signing_order in ('parallel','sequential')),
              expires_at timestamptz, original_sha256 bytea, sealed_pdf_path text, sealed_sha256 bytea, evidence_path text,
              sent_at, completed_at, created_by uuid, version int, is_sample boolean, created_at)
signature_signers(id uuid pk, request_id uuid not null references signature_requests on delete cascade, ord int not null,
              person_id uuid references people on delete set null, name text not null (1..200), email text not null (≤254), color text check (color ~ '^#[0-9A-F]{6}$'),
              status text not null default 'waiting' check (status in ('waiting','sent','opened','code_verified','signed','declined')),
              token_sha256 bytea unique, otp_hash bytea, otp_expires_at, otp_attempts smallint not null default 0 check (otp_attempts <= 5),
              opened_at, verified_at, signed_at, declined_at, decline_reason text (≤500), unique (request_id, ord))
signature_fields(id uuid pk, request_id uuid references signature_requests on delete cascade, signer_id uuid references signature_signers on delete cascade,
              kind text not null check (kind in ('signature','date','initials','text','checkbox')), page int not null check (page >= 1),
              x numeric(5,2), y numeric(5,2), w numeric(5,2), h numeric(5,2) check (all between 0 and 100), required boolean not null default true,
              value text (≤500), filled_at timestamptz)
signature_events(id bigint identity pk, request_id uuid not null references signature_requests on delete cascade, signer_id uuid,
              kind text not null check (kind in ('created','sent','opened','otp_sent','otp_verified','otp_failed','field_filled','signed','declined','reminded','canceled','completed','sealed')),
              at timestamptz not null default now(), document_sha256 bytea, prev_hash bytea, hash bytea not null,   -- sha256(prev_hash || canonical row)
              detail jsonb not null default '{}')                                       -- append-only; no IP
drive_connections(id uuid pk, staff_id uuid not null references admins on delete cascade, provider text not null check (provider in ('google','microsoft')),
              account_email text, vault_secret_id uuid, status text not null default 'not_connected' check (status in ('not_connected','connected','error')),
              connected_at timestamptz, unique (staff_id, provider))
document_storage_default(id boolean pk default true check (id), provider text not null default 'platform' check (provider in ('platform','google','onedrive','sharepoint')),
              location jsonb not null default '{}', set_by uuid, set_at timestamptz)
```

Storage buckets (private, accessed only by edge workers with the service role, downloads through short-lived signed URLs issued by an RPC that checks the record's visibility, per CRM-05):
- `documents`
- `form-uploads`
- `form-assets`
- `email-assets` (public read through the public host, images only)

---

## 5. Public RPCs (`public.*`, security definer, `set search_path = ''`, Zod at the edge, PostgREST rows parsed)

Error contract:
- **`forbidden`:** errcode `insufficient_privilege`, detail `scope:action`.
- **`not_found`:** errcode `no_data_found`. Also returned for records the caller may not see.
- **`invalid`:** errcode `invalid_parameter_value`, detail = the field, e.g. `subject`, `sender_domain`, `merge:Person.navn`, `fields`, `contact_rule`.
- **`version_conflict`:** errcode `serialization_failure`, detail = the current version.
- **`not_connected`:** errcode `invalid_parameter_value`, detail = the provider (`email`, `ip_company`, `contact_data`, `google`, `microsoft`, `esign`).
- **Existing codes kept:** `module_off`, `reason_required`.

Every list and read writes `app.log('record.listed' | 'record.read', …)` (D-12). Every write writes the audit, the changelog where the record has a history, and its event.

- **Campaigns:**
  - `campaigns_get(p_query jsonb)`, `campaign_get(p_id)`;
  - `campaign_save(p_id, p_values jsonb, p_version)`, `campaign_duplicate(p_id)`, `campaign_delete(p_ids uuid[], p_reason)` (drafts only);
  - `campaign_preview(p_id, p_person uuid default null)` → `{html, missing, unknown}`;
  - `campaign_test_send(p_id)`, `campaign_schedule(p_id, p_at, p_version)`, `campaign_cancel(p_id)`, `campaign_pause(p_id, p_paused boolean)`;
  - `campaigns_compare(p_ids uuid[])`;
  - `campaign_recipients(p_id, p_state text, p_limit)`, `campaign_export(p_id, p_format)`.
- **Marketing templates:** `marketing_templates_get()`, `marketing_template_save(p_id, p_values, p_version)`, `marketing_template_delete(p_id)`.
- **Segments and audience:**
  - `segments_get()`, `segment_save(p_id, p_name, p_query, p_description)`, `segment_count(p_query)` → `{matches, receivable}`, `segment_delete(p_id)`;
  - `marketing_status_summary()`, `consent_log(p_limit, p_before bigint)`;
  - `consent_set` (existing, widened to `archived`, with ref fields);
  - `suppressions_get(p_q)`, `suppression_add(p_email, p_reason)`, `suppression_remove(p_email, p_scope, p_reason)` (only for `manual` and bounce reasons);
  - `hygiene_candidates()`, `hygiene_archive(p_expected int)`. The function refuses when the count has changed since it was shown.
- **Deliverability:** `sender_domains_get()`, `sender_domain_save(p_id, p_values, p_version)`, `sender_domain_recheck(p_id default null)`, `deliverability_recommendations()`.
- **Forms:** `forms_get()`, `form_get(p_id)`, `form_create(p_kind, p_name, p_language)`, `form_save(p_id, p_draft, p_version)`, `form_publish(p_id)`, `form_set_status(p_id, p_status)`, `form_delete(p_id)`, `form_stats(p_id, p_days)`, `form_submissions(p_id, p_limit)`.
- **Chat:** `playbooks_get()`, `playbook_get(p_id)`, `playbook_save(p_id, p_values, p_version)`, `playbook_publish(p_id)`, `playbook_set_state(p_id, p_state)`, `playbook_stats(p_id, p_days)`, `chats_queue()`, `chat_get(p_id)`, `chat_claim(p_id)`, `chat_send(p_id, p_body)`, `chat_close(p_id)`, `chat_presence_set(p_online boolean)`.
- **Prospects:** `prospect_search(p_filters, p_page)` (edge-backed; `not_connected`), `prospect_reveal(p_provider_ref)`, `prospect_usage()`.
- **Web visitors and sites:** `visitors_get(p_days, p_filters)`, `visitor_get(p_org_number, p_days)`, `visitor_convert(p_org_number, p_kind, p_pipeline, p_stage)`, `web_sites_get()`, `web_site_save(p_id, p_values)` (returns the embed snippet).
- **Documents:**
  - `documents_get(p_query)`, `document_get(p_id)`;
  - `document_create(p_template, p_deal, p_name)`, `document_upload(p_deal, p_path, p_name, p_size)`, `document_update(p_id, p_values, p_version)` (draft only), `document_delete(p_ids, p_reason)`;
  - `document_link_create(p_id, p_recipient uuid default null)` → `{url}` once, `document_link_revoke(p_link)`, `document_views(p_id)`;
  - `document_file_url(p_id)` (a signed URL, visibility-checked).
- **Document templates:** `doc_templates_get(p_category)`, `doc_template_get(p_id)`, `doc_template_save(p_id, p_values, p_version)`, `doc_template_import(p_provider, p_file_ref)`, `doc_template_delete(p_id)`.
- **E-signature:** `signature_request_save(p_id, p_document, p_signers jsonb, p_fields jsonb, p_message, p_language, p_otp, p_version)`, `signature_request_send(p_id)`, `signature_request_remind(p_id, p_signer)`, `signature_request_cancel(p_id)`, `signature_request_get(p_id)`.
- **Storage:** `doc_storage_get()`, `doc_storage_connect(p_provider)` → OAuth URL, `doc_storage_set_default(p_provider, p_location)`. Branding and the e-sign service go through the existing `setting_set`.
- **Workers** (granted to `service_role` only; called by edge functions on the public host or by queue workers):
  - campaigns and email: `worker_campaign_batch(p_campaign, p_limit)`, `worker_campaign_sent(p_recipient, p_provider_message_id)`, `worker_email_events(p_batch jsonb)` (provider webhooks; idempotent on `provider_event_id`; updates recipients, consent and suppressions), `worker_unsubscribe(p_token, p_scope)`, `worker_consent_confirm(p_token)`, `worker_sender_domain_status(p_id, p_checks)`;
  - forms: `worker_form_definition(p_public_id)`, `worker_form_event(p_public_id, p_kind)`, `worker_form_submit(p_public_id, p_answers, p_meta)`;
  - chat: `worker_chat_start(p_site_key, p_page, p_org_number, p_language)` → token, `worker_chat_message(p_token, p_body)`, `worker_chat_poll(p_token, p_since)`;
  - web: `worker_company_upsert(p_rows)`; the existing `worker_web_ingest` extended to drop survey hosts and emit `visitor.identified`;
  - documents and signing: `worker_doc_view(p_token)`, `worker_doc_heartbeat(p_view, p_seconds)`, `worker_sign_view(p_token)`, `worker_sign_otp_send(p_token)`, `worker_sign_otp_verify(p_token, p_code)`, `worker_sign_submit(p_token, p_values)`, `worker_sign_decline(p_token, p_reason)`, `worker_sign_sealed(p_request, p_path, p_sha256, p_evidence_path)`, `worker_esign_status(p_external_id, p_status)`, `worker_document_stored(p_id, p_storage, p_external_id, p_url, p_pdf_path, p_sha256)`, `worker_drive_connected(p_staff, p_provider, p_email, p_token)`;
  - prospects: `worker_prospect_revealed(p_reveal, p_contact jsonb)`.

---

## 6. Rights (`app.require(scope, action)`; scopes deals/projects/campaigns/tickets/global; visibility via `app.visible`)

| Area | See | Create / own | Others' records | Other |
|---|---|---|---|---|
| Campaigns, marketing templates, segments | `campaigns:see` | `campaigns:add` (save, test, schedule own) | `campaigns:edit_others` | delete `campaigns:delete`; recipients export `campaigns:export`; reports on others' campaigns `campaigns:reports_others`; compare `campaigns:see` |
| Consent and suppressions | `campaigns:see` (log), `deals:see` (per person, existing) | `consent_set` as in 0011 (owner, or `deals:edit_others` / `campaigns:edit_others`) | — | suppression add/remove and hygiene archive `campaigns:bulk`; sender domains, sites, embed `campaigns:configure` |
| Forms, chat playbooks | `campaigns:see` | `campaigns:add` | `campaigns:edit_others` | publish and activate `campaigns:configure` |
| Live chat queue and claim | `deals:see` | claim/send `deals:add` | — | — |
| Form submissions, chat transcripts | through the lead's visibility (`deals:see` + `app.visible`) | — | — | export `deals:export` |
| Prospect search | `deals:see` | reveal `deals:add` | — | — |
| Web visitors | `deals:see` (company-level data) | convert `deals:add` | — | export `deals:export` |
| Documents, links, signatures | `deals:see` + the deal's visibility | `deals:add` | `deals:edit_others` | delete `deals:delete` |
| Document templates | `deals:see` (company, own team, own private) | private and team `deals:add` | `deals:edit_others` | company-wide `deals:configure` |
| Storage default, branding, e-sign service | `global:configure` | — | — | own drive connection: any staff member (`app.require_staff`) |
| Workflows with `campaign_action` | — | `campaigns:workflows` | — | — |

Presets (0003):
- **Marketing** (campaigns + deals: see, add, edit_others, export, ai) runs campaigns, forms and chat, but cannot configure domains or bulk-archive. An admin, or a custom set with `campaigns:configure` and `campaigns:bulk`, can.
- **Sales** handles visitors, chats, reveals and documents.
- **Read-only analyst** sees campaign reports.

---

## 7. Events (`app.emit`, object.action) and workflow triggers

| Kind | Subject | Payload (ids and counts only, never free text) | Emitted by |
|---|---|---|---|
| `campaign.scheduled` / `campaign.sent` / `campaign.canceled` | campaign | `{type, audience_count}` | schedule, send finished, cancel |
| `campaign.delivered` / `campaign.opened` / `campaign.clicked` / `campaign.bounced` / `campaign.unsubscribed` / `campaign.complained` | person | `{campaign, link?, bounce_kind?}` | `worker_email_events`. Open and click skip `prefetch`. |
| `consent.changed` | person | `{status, ref_type}` (existing kind, payload widened) | `consent_set`, workers |
| `form.submitted` | lead (or deal) | `{form, submission, person, organization, ticket?}` | `worker_form_submit` |
| `chat.started` / `chat.claimed` / `chat.completed` | lead, when one exists; else nothing | `{conversation, playbook}` | chat functions |
| `visitor.identified` | organization (CRM only) | `{org_number, pages, high_intent: bool}` once per org per day | `worker_web_ingest` |
| `prospect.revealed` | lead | `{reveal, provider}` | `prospect_reveal` |
| `lead.created` / `deal.created` / `organization.created` | the record | existing payload, changelog source `capture` | conversions |
| `document.generated` / `document.sent` / `document.opened` / `document.revoked` | deal | `{document, link?}` | document functions, `worker_doc_view` (first view per link per day) |
| `document.signed` / `document.declined` / `document.completed` | deal | `{document, request, signer?}` | signing workers |

Engine changes (0021):
- **Full-kind matching.** `sub_workflows` matches `trigger_config.event` against either the suffix or the **full kind**. A workflow on entity `deal` with event `document.completed` then fires (UF-08 step 6: "a workflow can move the deal to won"), and so do one on entity `lead` with `form.submitted` and one on entity `person` with `campaign.clicked`.
- **Data conditions.** `trigger_config.data` (today honoured only for product events) applies to platform events too, which gives conditions such as "form is X", "campaign is X" and "template category is quotes".
- **`campaign_action`.** The step's config is `{campaign_id}`, which must be an automated, active campaign. The step resolves the subject's person. It skips with `not_subscribed` / `suppressed` / `no_email` (CMP-07 acceptance; D-27 fixed: never to unsubscribed people), and otherwise creates a `campaign_recipients` row with `send_key = run step id` and queues it. Blockers: `not_connected:email`, `sender_domain_unverified`. The existing `not_available:campaigns` goes.
- **Assignment** of capture leads works as is (V-20: the changelog source is not `ui`).

---

## 8. Settings (register `app.settings_registry`, D-15/D-16)

| Key | Group | Options (default first) | Applies to | Note |
|---|---|---|---|---|
| `tracking` (existing) | tracking | on, off, per_email | COM-06, **CMP-06** (extend `applies_to`) | `per_email` means per campaign here; `off` forces `campaigns.tracking = false` and hides open and click figures |
| `form_tracking` (existing) | tracking | on, off | LGN-03 | off → `form_submissions.tracking = {}` |
| `web_ident` (existing) | tracking | on, off | WEB-01..04 | off → no company resolution at ingest |
| `widget_consent` (existing) | tracking | off, on | LGN-05 | on → `w.js` loads chat and tracking only after the site's consent signal |
| `contact_rule` (existing) | contacts_consent | no_rule, … | LGN-04, WEB-04 | `opt_in_only` refuses reveals; `source_and_basis` requires a basis on reveal |
| `count_limits` (existing) | limits | unlimited, number | DOC-05 (signers), credits | |
| `plan_gates` (existing) | limits | all_on, per_plan | CMP-05 allowance, CMP-09 | |
| `double_opt_in` **NEW** | contacts_consent | on, off | CMP-04, LGN-03 | **default on, against D-16** (Q3); per-form override only towards on |
| `list_hygiene` **NEW** | contacts_consent | source_values (12 months), custom, off | CMP-04, CMP-08 | `numeric_option` custom = months (6–24); drives the recommendation only |
| `doc_branding` **NEW** | documents | hidden, shown | DOC-06 | design default: hidden |
| `esign_service` **NEW** | documents | builtin, external | DOC-06 | |
| `campaign_rules` **NEW, fixed** | platform_constant | fixed | CMP-01, CMP-03, CMP-04, CMP-08 | D-27: footer with unsubscribe and sender identity; never to unsubscribed people; never from an unauthenticated domain. Shown read-only like `firewall`. |
| `survey_flow_block` **NEW, fixed** | platform_constant | fixed | LGN-05, WEB-01 | tracker and widgets never on a survey host |

Values that are not options live in their tables, because the register holds option keys only:
- the postal address and from name (`sender_domains`);
- the storage location (`document_storage_default`);
- the queue wait (`chat_playbooks`).

---

## 9. External dependencies and jobs

| Dependency | Needed for | Without it |
|---|---|---|
| Email provider, two streams (D-07; EU-hosted; webhook signing secret in Vault) | campaign send and test, DOI confirmation, signer invitations and OTP, provider events, domain verification | `not_connected` on test, schedule and send; DNS checks still run; DOI submissions stay `pending` and the form shows the confirmation-not-sent notice to staff |
| DNS-over-HTTPS (no key) | SPF/DKIM/DMARC checks | — |
| IP-to-company provider (`ip_company`) | WEB-02, chat company | sessions without company; Visitors shows `not_connected` |
| Brønnøysund open API (D-07, no key) | `web_companies`, org lookup on forms | — |
| Prospect database (`contact_data`, 0022) | LGN-04 | search and reveal `not_connected` |
| Google Drive / Microsoft Graph (OneDrive, SharePoint) OAuth clients (D-18) | DOC-03, template import | storage is the platform only; import `not_connected` |
| External e-sign provider (`esign`) | DOC-06 | the External option shows `not_connected`; built-in remains |
| PDF render and seal worker (headless render + platform seal key in Vault; optional RFC 3161 timestamp provider) | document PDFs, sealing (07-PLAN lists "e-signature evidence" as provider-dependent) | documents stay HTML drafts; signing `not_connected` (Q11) |
| Public host `go.owntheagenda.com` (D-28) | `w.js`, forms, chat, document view, signing, unsubscribe, DOI confirm, email images, click redirect and open pixel | no public feature works |

Jobs (pg_cron + pgmq, D-05):
- **Campaign sending:**
  - `campaign_due` every minute: scheduled → sending; resolves the audience into `campaign_recipients`; queues `campaign_send` batches.
  - `campaign_ab_decide` every 10 minutes.
- **Checks:**
  - `dns_check`: nightly and on demand.
  - `chat_fallback`: every minute.
  - `signature_expire_remind`: daily.
- **Pruning and refresh:**
  - `document_link_expire`: daily.
  - `campaign_events_prune`: daily, 13 months.
  - `web_companies_refresh`: monthly.
- **Edge workers:**
  - provider webhooks (campaign events);
  - the public host functions;
  - drive, prospect, e-sign and IP-to-company adapters;
  - the PDF worker.

---

## 10. Privacy (GDPR)

**Consent and email**
- **Consent records.** Every marketing status change is a `consent_events` row recording who, what, when, the source, the basis, the wording shown (`text_id`) and the reference (form submission, campaign, import). The table is append-only; the only deletion is the cascade from an erased person. The form's consent checkbox is unticked by default and separate from the contact purpose. Double opt-in confirms through a single-use, expiring link.
- **Marketing email.** Only `subscribed` people who are not suppressed receive campaigns (fixed). The basis is stored per person: consent, or the existing-customer exception with opt-out, per the brief's reading of Norwegian marketing law. The footer wording must follow the basis (Q19).
- **Unsubscribe.** A one-click header plus the footer link, honoured in the same transaction. The suppression is kept as a SHA-256 of the address, so it survives erasure (the right to object outlasts the record).

**Tracking and identification**
- **No IP stored.** Applies to the tracker (0025), chat start, campaign opens and clicks (provider geo city only), document views and signing evidence. IPs are used only in memory at the edge for hashing and company resolution.
- **Bots and prefetch** are classified and excluded from engagement.
- **Cookies (LGN-05).** The tracker is cookieless. Chat keeps its conversation token in the visitor's storage only after the visitor opens the chat, which is strictly necessary for a service the visitor requested. Consent-gated loading is a setting.
- **No tracking on survey hosts (fixed).** Neither the tracker nor any widget ever loads on a survey host.
- **Web visitors.** Company-level only; ENK org numbers are excluded. The legal check that a cookieless IP+UA hash needs no banner is still open (brief, Web analytics).
- **Prospect search.** Results are not stored until revealed. A revealed person triggers the GDPR art. 14 information duty within one month. With `contact_rule = no_rule` that duty is the user's, and D-27's legal review must cover it (Q20).

**Retention**

| Data | Retention |
|---|---|
| Raw web rows | 13 months (exists) |
| Campaign events | 13 months, then the per-recipient rollup only |
| Form submissions | 13 months for tracking metadata; answers stay with the lead's lifecycle |
| Chat transcripts | follow the lead |
| Document views | follow the document |
| Sealed contracts and their evidence | kept as long as the contract and the bookkeeping law require (Bokføringsloven: 5 years for sales documents) |

**Erasure (SEC-11).** Erasing a person:
- deletes their consent events (by the existing cascade);
- blanks `campaign_recipients.email` and sets `person_id` to null;
- deletes form submissions' answers and chat messages linked to them;
- keeps the suppression hash, adding reason `erasure` when none exists.

Signed contract evidence is retained under the legal-obligation exception, recorded on the `privacy_requests` row.

**Anonymity firewall (D-19, D-34)**
- No form, chat or import may collect employee lists or respondent data (Q8).
- Per-recipient events of Orgpuls's survey-invitation stream are never ingested.
- Segments on product data use tenant-level counts and dates only, e.g. "no pulse in 90 days" from `product_survey_rounds`.
- `member.role` is a product user's role, not a respondent's.

**Logs.** No form answers, chat text, document bodies or decline reasons appear in audit detail, event payloads or edge logs. Payloads carry ids and counts.

---

## 11. Open questions, each with a recommendation

1. **Public hosts (D-28).** The design uses `sentral.orgpuls.no/w.js` and `docs.orgpuls.no/s/`. *Recommendation:* `go.owntheagenda.com` for everything public (`/w.js`, `/f/<public_id>`, `/d/<token>`, `/s/<token>`, `/u/<token>`, `/c/<token>`). Brand-specific custom domains later. Log as a deviation.
2. **Seven statuses against five stored.** *Recommendation:* add `archived`, and keep `pending` as "pending double opt-in" (no data migration). "Pending upgrade" is derived from an optional subscriber allowance and shown only when one is set (D-17).
3. **Double opt-in default.** D-16 says unrestricted (off); the design and the brief say on. *Recommendation:* register key `double_opt_in` default **on**, as a logged exception under D-27 (the brief's consent defaults stand). Tor to confirm.
4. **One template store.** *Recommendation:* extend `app.email_templates` with `kind='marketing'`, design and HTML plus versions, rather than a second template table. This follows the brief's "never a second table" and the shared store for COM-05 and CMP-02.
5. **Merge-field syntax.** Documents use `[deal.title]` while the registry uses `[Avtale.tittel]`. *Recommendation:* one registry. Add lowercase English tokens as rows with `contexts` (email, campaign, document); keep the Norwegian ones as aliases; widen the regex to allow digits for `[signer.N]`. `[product.table]` is a block token, and `[project.*]` stays unknown until Projects.
6. **The transactional stream in Deliverability.** varsler.orgpuls.no is Orgpuls's sending. *Recommendation:* such a domain is a `sends_here = false` row with DNS checks only. Bounce and complaint figures for it are "—". Per-recipient invitation events never enter the platform.
7. **"Cookie ID" in form tracking.** *Recommendation:* drop it. Capture UTM, referrer host, landing path and declared page variables, under `form_tracking`.
8. **Employee-list upload form.** *Recommendation:* do not seed «Send oss ansattlisten». Add the fixed rule `survey_flow_block` plus a fixed notice on file-upload forms that employee lists belong in the product. The employee import lives in Orgpuls.
9. **Signature evidence "time and address" (SF-20).** *Recommendation:* "address" means the verified email address. Store no IP. The built-in level is a simple electronic signature (email + OTP). BankID (an advanced signature) comes through the external adapter when a contract needs it. Tor confirms the level per contract type (open point 5).
10. **Live chat in real time without client grants (D-09).** *Recommendation:* start with polling. Staff call `chats_queue`/`chat_get` every 3 s and the visitor's edge function polls `worker_chat_poll`. Move to Realtime Broadcast on private channels later, which needs a policy on Supabase's `realtime.messages`, not on an `app` table. Decide before MOB-08.
11. **Document editing and sealing.** *Recommendation:* platform-native templates are sanitised HTML with tokens, rendered to PDF by the worker. While a document is a draft its body can be edited in a rich-text panel (D-41). Drive documents are edited in the drive. The built-in seal uses a platform key in Vault plus the hash chain, with a qualified timestamp optional later.
12. **Branding per product.** *Recommendation:* a document's brand is `deals.product` (or the template's product). "Remove platform branding" hides Sentral/owntheagenda marks only. Fix the copy "show only Orgpuls".
13. **Product-table total against deal value.** *Recommendation:* the table prints "Per month", "One-off" and "Total contract value ex. VAT" = `deals.value` (TCV), so DOC-02's acceptance test holds. VAT follows each line's `tax_rate`.
14. **Campaign "Signups" and "MRR won" attribution.** *Recommendation:* last touch with `utm_campaign` equal to the campaign's, signup after `sent_at`, and no window cap. Show "via UTM" in the header tooltip. Revisit when Orgpuls sends both touches (D-40).
15. **Foreign visiting companies.** `company_org_number` is Norwegian only. *Recommendation:* Norway only in phase 5; the Country filter shows "Norway" only. Add a `company_key` later if a foreign source is bought.
16. **ENK visitors.** *Recommendation:* exclude them at ingest (`web_companies.excluded`) because they identify natural persons.
17. **A/B winner metric.** *Recommendation:* default `clicks`, because opens are inflated by prefetch. `opens` is offered, counting human opens only. The wait defaults to 4 h.
18. **Copy claiming k = 5** («Fem er gulvet», «grupper med minst 5 svar») in the seeded newsletter layout. *Recommendation:* seed layouts without product claims. Tor writes the content, which must say "at least 3, 5 by default".
19. **Footer wording «fordi du har samtykket».** It is wrong for existing-customer recipients. *Recommendation:* footer text keyed by basis (consent / existing customer), with the postal address from the sender domain.
20. **Prospect data and the art. 14 duty.** *Recommendation:* keep `contact_rule` default (D-16), but on each reveal show the notice "you must inform this person within a month". Put it in D-27's legal review.
21. **Who configures capture.** *Recommendation:* forms and playbooks under `campaigns` (Marketing preset); handling chats, leads and visitors under `deals` (Sales preset), as in §6.
22. **One OAuth table or several.** Calendar (0010), mailboxes (0020) and drives each keep their own. *Recommendation:* keep `drive_connections` separate now, and unify into one per-staff connection in phase 8 (INT-05/06).
23. **"Nth visit" and "3 h ago".** *Recommendation:* label them as the company's visits. A visitor-level count is impossible with the daily salt (D-37).
24. **Signer cap.** *Recommendation:* no cap unless `count_limits` is set. The prototype's cap of 4 is a bug.
