# Data requirements: Inbox, Feed and Automation (Sentral design)

Sources I read: `design-reference/sentral/project/{Inbox,Feed,Automation}.dc.html`, `admin-data.js`, `coverage-data.js` (COM-01..14, AUT-01..12, plus PRO-01..07, AIA-02/03/04, LEA-06, CUS-07, INT-04, ENT-02 and flows UF-03/04/05/11/12/14/25, SF-02..06/13/23/26/28), `docs/crm-enrichment/DECISIONS.md`, and the existing migrations 0001–0014. Staff is `app.admins(id)`. These already exist and are reused: `teams`/`team_members`, `labels(entity,…)`, `notes(entity,record_id)`, `booking_links`, `calendar_connections` (which already has the `vault_secret_id` pattern), `consent_events`, `changelog`, `events`, `notifications`, `setting_values`, and the `jobs` queue in pgmq (`pgmq.create('jobs')`).

**A rule for every screen:** each list, count, name and number in the three prototypes is a literal in the component script. The only exceptions are a few values derived from `admin-data.js`, which is itself seeded random data. None of them may appear in the build. Where this spec says **FAB**, the value is fabricated and must be replaced by the derivation given, or not rendered.

---

## 1. Inbox (`Inbox.dc.html`)

### Views and states
The left rail picks the view. Its folder groups:
- **Mail:** Inbox, Team inbox · salg@, Scheduled and failed, Group email, Archive
- **Channels:** WhatsApp and LinkedIn, Calls
- **Labels:** Proposal, Follow-up, Billing
- **Setup:** Mailboxes and templates

Views: `mail` (inbox, team, archive), `outbox`, `group`, `messaging`, `calls`, `settings`.

States the build needs:
- Empty folder ("Nothing here.").
- Thread selected (the prototype always selects one; with no threads it falls back to `T[0]`, which is a bug — show nothing).
- Composer: empty, drafted, scheduled.
- Missing-attachment warning.
- Toast.
- Mailbox status: Synced or Re-auth needed.
- Outbox row: Scheduled, Failed (with Retry), Sending n/m.

States missing from the design but required by the features:
- **No mailbox connected.** Every mail view has to show this, because without a Gmail or Graph token nothing can be listed or sent (D-07).
- AI not configured.
- Missing merge value (COM-05).
- Group email excluded recipients (Warn or Block mode).

**Gaps:**
- Labels in the rail (`l1`–`l3`) just reset the folder to Inbox; the build must filter by label.
- Archive is hard-coded empty (`folder==='archive' ? false`).
- **Compose** only clears the body. There is no To field for a new message, so a new-thread composer (To, Subject) has to be built in the design's language (D-41).

### Field mapping

| UI element | Source |
|---|---|
| Folder counts (3, 1, 3, 2) | **FAB**. Derive: unread threads per folder for the viewer; outbox = scheduled + failed + sending messages I own; messaging = unread conversations |
| Thread list `from / when / subject / snippet` | NEW `email_threads` (`subject`, `snippet`, `last_message_at`) + latest `email_messages.from_name` |
| Bold (unread) | NEW `email_thread_reads(thread_id, staff_id, read_at)`. Read state is per user because team inboxes are shared |
| `status` (Waiting on you / New / Replied / Waiting on contact) | Derived: no outbound message ⇒ New; last direction `in` ⇒ Waiting on you; last direction `out` with an earlier inbound ⇒ Replied or Waiting on contact. The split rule is unspecified, so I propose "Waiting on contact" after an outbound reply to a thread the contact started, and log the choice |
| Chips `Deal` / `Lead` / `Team inbox` | Derived from `email_links.entity` and `mailboxes.kind` |
| Chip `Opened 2×` | Derived: count of `email_tracking_events(kind='open')` on the last outbound message |
| Chips `Signed`, `Cold` | Thread labels (`labels` with a new entity `email_thread`) or the linked deal's labels. Both are **FAB** content |
| `th.mailbox` "tor@orgpuls.no · Gmail" | `mailboxes.address` + `provider` |
| `◆ linked` | `email_links` → record title (deal, lead, person, organisation, project) |
| Button "Archive · syncs to Gmail" | The provider name must be interpolated. The prototype says Gmail even on a Microsoft 365 thread |
| Label toggles (Proposal, Follow-up, Billing, Urgent) | `labels where entity='email_thread'` + NEW `email_thread_labels` |
| AI panel: summary, readiness `/10`, sentiment, reason, action items, suggested replies | Claude (D-07), stored in NEW `email_thread_insights`. AIA-04 says on demand, so it needs a "Summarise" trigger or generation on open. Gate it on the `ai` permission action. Without an API key, show an unconfigured state, never canned text. The prototype's texts are **FAB** |
| Message `from → to`, `when`, `body` | `email_messages` |
| Track line "Opened 2× · clicked «Se prisene» · last open …" | Derived from `email_tracking_events` joined to `email_tracking_links.label`. COM-06 requires an "opens may be inflated by image prefetch" caveat, which the design lacks; log it as a deviation |
| From select (3 hard-coded addresses) | Mailboxes I may send from (personal + team via `mailbox_members.can_reply`) + verified `sender_aliases` |
| To | Thread counterpart; `replyTo` |
| "suggested:" participants (Mona Hansen, Petter Aas, Ingrid Solberg) | **FAB**. Derive: the linked deal's `deal_participants` and people at the linked organisation not already on the thread. Clicking adds them as CC |
| Template select | NEW `email_templates` (`name`, `scope` private/shared, `is_starter`) |
| Merge fields `[Person.fornavn]`, `[Organisasjon.navn]`, `[Organisasjon.ansatte]`, `[Avtale.verdi]`, `[Avtale.fase]`, `[Bruker.navn]`, `[Bruker.bookinglenke]` (plus `[Bruker.signatur]`, used in a template but missing from the list) | NEW seeded registry `merge_fields(token, source_path, format)` resolving to `people.first_name`, `organizations.name`, `organizations.employees`, `deals.value` (kr format), stage name, `admins.name`, `booking_links`, and `mailboxes.signature` |
| Tone (Professional / Formal / Friendly), length (Short / Standard / Long), prompt, Draft | Claude via `ai_draft_email`. The `draftFor()` string builder is **FAB** |
| Missing-attachment warning | Client-derived: regex `/vedlagt\|vedlegg\|attach/` **and** no attachments. The prototype skips the second check |
| Attach | NEW `email_attachments` + Storage. The button has no handler in the prototype |
| Track toggle default | Setting `tracking`: On ⇒ on; Off ⇒ hidden or disabled; "Chosen per email" ⇒ toggle shown |
| "Signature: Tor · Orgpuls" | `mailboxes.signature` of the selected sender |
| Send at (Send now / Tomorrow 08:00 / Monday 09:00) | `email_messages.scheduled_at`, computed in the user's time zone (D-04, Europe/Oslo by default) |
| Outbox rows (Tilbud — Kystlinje, 550 failure, group "31 / 38 · throttled") | **FAB**. Derive from `email_messages` where `state in (scheduled, queued, sending, failed)`; group progress from `group_sends` |
| Group sources (Segment «Webinar attendees» / Contacts timeline selection / Deals list — Proposal sent) | Segment = a saved segment (`saved_views` or the segments table when built); selection = ids passed in; deal list = a saved view query |
| Group recipient chips (`people.slice(2,14)`) and count 38 | **FAB**, and inconsistent with each other: 12 chips against a count of 38. Derive both from the resolved source |
| Group text "template «Oppfølging etter webinar»" | **FAB**: that template is not in the template list. Use the chosen template |
| Group text "consent checks …: off (setting)" | Setting `sales_consent` |
| Group text "recipient limit: unlimited" | Setting `count_limits` |
| WhatsApp chats, messages, ticks, reaction, image, the "1 560 kr" quick reply, approved templates | **FAB**. Needs a WhatsApp Business provider, which is not chosen (D-07: chosen before its phase). Show an unconnected state |
| LinkedIn card | D-39 leaves it out. Render the explanatory card with Connect disabled, or omit it, and log the choice |
| Call log, the "+47 912 34 567" input, "Matched: Kari Nordmann", the Incoming card for Ole Hansen | **FAB**. Needs a telephony provider (not chosen). "Call via default calling app" can work without a provider as a `tel:` link, followed by a manual outcome form that writes the activity |
| Connected mailboxes and their statuses | `mailboxes` |
| Add mailbox "Gmail · Microsoft 365 · Exchange · IMAP" | Exchange Online is covered by Graph. **IMAP is outside D-07**: log a deviation or hide it |
| BCC address `tor.k82h@inbox.sentral.orgpuls.no`, `deal-d101@inbox…` | NEW `dropbox_addresses` (random local part per staff member, and per deal). Needs inbound mail routing from the chosen email provider and an MX record on the inbox subdomain |
| Alternative sender addresses | NEW `sender_aliases(kind='bcc_accepted')` |
| "14 users installed" (add-ons) | **FAB**. No add-on exists. Render nothing until installs are recorded |
| "Open and click tracking: on (setting)" | Setting `tracking` |

### What the actions must really do
- **Send:**
  1. Render the merge fields server-side and refuse if a value is missing (COM-05).
  2. Insert into `email_messages` with `state=queued` (or `scheduled`).
  3. A worker sends through Gmail `users.messages.send` (threaded with `threadId` and `In-Reply-To`) or Graph `/messages/{id}/reply` or `sendMail`.
  4. If tracking is on, inject a pixel and rewrite links to `email_tracking_links` tokens first.
  5. Store the provider ids.
  6. Write an activity of type `email` (COM-02: logged at send time).
  7. Emit `email.sent`.
- **Schedule:** the same path with `scheduled_at`. Editable or cancellable until it is picked up (COM-08).
- **Retry:** re-queue the failed message (attempt +1). The prototype's "Sent after retry · corrected address" is **FAB**; correcting an address is Edit.
- **Archive:** set `archived_at`, then push to the provider (Gmail removes the INBOX label; Graph moves to the Archive folder). A provider-side archive arrives through sync (COM-09, two-way).
- **Create lead / Turn into lead:** create a lead (and a person if the sender is unmatched), link the thread or conversation, emit `lead.created`.
- **Group send:**
  1. Requires the `bulk` permission and a synced mailbox (COM-07).
  2. Resolve recipients and apply `sales_consent`: Warn shows the excluded people; Block drops people with no basis or on the suppression list.
  3. Create `group_sends` plus N individual `email_messages`, throttled per mailbox.
  4. Each message links to its person.
  5. D-27's unsubscribe link and sender identity apply to campaigns, not to 1:1 sales email. Confirm this with legal review.
- **Tracking:** a public edge endpoint records opens and clicks (no IP stored, in the spirit of D-37), emits `email.opened` / `email.clicked`, and sends a realtime notification to the sender.
- **Auto-linking:** match participant addresses to `people.email` and then to their open deal or lead. Unmatched threads land in an unlinked list (derived: threads with no `email_links`).

---

## 2. Feed (`Feed.dc.html`): three tabs, Feed, Scoring models and Enrichment

### Feed view
Sub-tabs: Follow-ups, Overlooked deals, Suggestions (each with a count). Card list, empty state ("Ingenting venter akkurat nå — …"), side panel, progress panel.

Discrepancy: PRO-01's third tab is "Opportunities: new deals with no activity", but the design shows **Suggestions** with AIA-02 AI cards. The design wins visually; I propose Suggestions holds the AIA-02 cards plus new-deal-no-activity cards. Log it.

Not in the design but required by the features: card filters by stage, type and score, and the one-time scope setting (PRO-01/02).

| Card kind (tone, title, subtitle) | Real trigger | Fabricated parts |
|---|---|---|
| Email reply | `email.received` on a thread linked to my deal; resolved when I reply | "readiness 8/10" is real only if an insight exists |
| No reply after 5 days | Scheduled check: last outbound on a deal thread more than 5 days old with no inbound | — |
| Planned today | My activities due today on the deal | "14:00 · high priority" is **FAB** (hard-coded, not from `activities`) |
| Email opened | `email.opened` | "Last open 25 min ago from {org.city}" — the city comes from the organisation, not the open: **FAB**. Drop the location |
| Link clicked | `email.clicked` (+ sequence step) | — |
| Sequence email waiting | Messages with `state='awaiting_review'` from sequences | — |
| Overdue activity · idle N d / No follow-up activity | Derived from `activities` (undone and past due; no planned activity) and the idle days since the last activity, against the stage `rot` | Derivable |
| Likely to advance — 72 % | AI estimate (AIA-02, reason required) | 72 % is **FAB** |
| Slipping | Close date near or past + idle days | Derivable |
| Cross-sell signal | `account_products` count = 1 + employees | "120 shift workers" is **FAB** |
| Stalled "… close 40 % less often after 21 days" | Time in stage from `deal_stage_history` | The 40 % statistic is **FAB** unless computed from history; otherwise drop that clause |

Cards are stored in NEW `feed_cards`, with an i18n kind and `params jsonb` rather than prose, and a dedupe key. They are generated from events (SF-13) and resolved when their condition clears or the user acts. Per AIA-02, admins can hide AI scoring; that needs a NEW setting key `ai_scoring` (with its consumer and test, per the wiring audit).

| Action | What it does |
|---|---|
| Schedule task | Create a `task` activity due tomorrow, owned by me, on the deal; resolve the card (`resolved_by='task'`) |
| Email | Open the composer with the deal context; resolve the card |
| Open | Side panel: deal title, `kr(value)`, organisation, person; the deal's first 3 activities (subject · done/planned); person · role; "Open deal →" |

Counters, all of which need derivation:

| Counter | Status | Derivation |
|---|---|---|
| "✓ N done today" | **FAB** (`4 + st.done.length`) | Cards I resolved today |
| Today: Tasks 5/8, Calls 3/6 | **FAB** | My activities due today of that type, done / total |
| Today: Activities n/14 | **FAB** | My activities due today, done / total |
| This month: New deals 14 | **FAB** | `deals.created_at` this month |
| This month: Won 6 · 312 000 kr | **FAB** | `won_at` this month (count and sum) |
| This month: Forecast (weighted) 726 100 kr | **FAB** | Σ value × stage probability for open deals closing this month |
| This month: Goal: won value 62 % of 500 000 kr | **FAB** | Needs a goals table (INS-05) that does not exist. Omit and log it |

### Scoring models view
- **Model list:** name and subtitle (entity · pipeline · state), e.g. "Lead fit · Leads · draft". PRO-03 says deals only, but the design includes a lead model, so the table needs an `entity` column.
- "Score models: unlimited (setting)" comes from `count_limits`.
- **Groups:** Highly positive +25, Slightly positive +10, Negative −10. Each criterion row has a join (IF / OR / AND) and a match mark. "+ Criterion" has no handler in the prototype.
- **Criteria in the demo, mapped to real data:**

| Criterion | Real source | How the prototype fakes it |
|---|---|---|
| Organisation health ≥ 70 | Health score (0013) | — |
| Proposal link opened in 7 days | Tracking events | `deal.score > 60` |
| Decision maker is a participant | `deal_participants` + person label "Decision maker" | `deal.score > 50` |
| Already uses another application | `account_products` | — |
| Source is web form or chatbot | `deals.source` | — |
| Employees 26–250 | `organizations.employees` | — |
| No reply to last email in 5 days | Email threads | `deal.idle > 5` |
| Payment past due | Organisation status | — |

- **Preview:** a deal select (the first 12 deals) and a score of `clamp(30 + Σ)`. The base of 30 is **FAB** and unspecified; propose base 0 and log it. The prototype also ignores the AND/OR joins and adds points per hit. The scoring rule has to be decided; I propose each criterion row adds its group's points, with AND/OR combining conditions inside the row, and logging that.
- **Rules:** one active model per pipeline (partial unique index). Scores are recomputed when a referenced field changes (PRO-03).

### Enrichment view

| Element | Status | Real source |
|---|---|---|
| Credits "618 left … of 1 000 · resets 1 Nov" and "Buy top-up →" | **FAB**. D-17 says nothing is sold and credits only count provider usage, so the top-up conflicts with D-17 | A usage counter from `credit_ledger`; show an allowance only if `count_limits`/ENT sets one. Omit the top-up and log it |
| Sources: Brønnøysundregistrene | Real | Open API, no credentials needed (D-07) |
| Sources: "Company and contact data provider (adapter)" | Provider not chosen | Show unconnected |
| "Enrich 24 organizations with gaps" | **FAB** (24) | Count of organisations with an org.nr and empty enrichable fields; at most 100 per request (PRO-06) |
| Company diff for Mjøsa Energi (address, NACE, employees, revenue, LinkedIn, website) | Values **FAB** | Brreg Enhetsregisteret gives address, NACE, employees and website (`hjemmeside`). Revenue needs Regnskapsregisteret. LinkedIn needs the provider |
| Apply | — | Write empty fields only; changelog source `enrichment`; 1 credit |
| Person finds with masked email or phone, "Reveal · 1" | Provider only | Store with source and date (PRO-05); apply `contact_rule` |
| Reverse lookup "sigrid.aas@fjordvekst.no …" | **FAB** | Produced from unmatched inbound senders: domain → Brreg name search or provider |
| Create linked records / Dismiss | — | Create the person and organisation and link the email; or dismiss the suggestion |

---

## 3. Automation (`Automation.dc.html`)

Tabs: Workflows, Builder, Templates, Monitoring, Assignment rules, Sequences. Header text: "One engine — extends lifecycle messaging · loop protection on (safeguard)". "On" comes from setting `safeguards` (Source values / Custom / Off).

### Workflows list
- **Columns:** Workflow (name, description), Trigger (human-readable summary from `trigger_config`), Owner, State (Active/Draft), Runs 7 d, Failed, **Active for** (activation scope: team or Everyone), Activate/Deactivate, Transfer.
- Runs and failures are **FAB**. Derive them as counts of `workflow_runs` over 7 days.
- **Transfer** always goes to Ingrid in the prototype. The build needs a staff picker, must notify both people and must audit the change (AUT-10).
- The "owned by me / by others" filter (AUT-10) is not in the design.
- **Trigger types the design uses:**

| Trigger type | Design example | Source |
|---|---|---|
| Entity event with a field-change requirement | Deal updated · status = won | `app.events` |
| Date offset | 2 days after the stage threshold; 60 days before renewal | Scheduled date check |
| Product event | trial day 7, payment_failed | `events_in` / D-21 count events |
| Campaign email clicked | — | Marketing stream |
| Organisation updated with a condition | health < 40 | `app.events` |

### Builder
- **Canvas:** one hard-coded workflow. Node kinds: Trigger, Condition, Delay, Wait for, If/else (two paths), Action, Webhook, joined by "＋" connectors.
- **Config panel per node:**
  - Trigger: Object / Event / Field changed.
  - Condition: Group 1, Group 2 (OR), Related record.
  - Webhook: Method, URL, raw JSON body with `{deal.org.orgnr}` merge syntax. This differs from email's `[Person.fornavn]`; unify it in one merge registry with two renderings.
  - Notes on the panel: "Email conditions can test opened/answered"; "Private and link-local addresses blocked · 10 s timeout · no redirects into blocked ranges" (D-32: also sign the request with HMAC-SHA256, secret in Vault); "Actions and delays per path: unlimited (setting)" (`count_limits`).
- The inputs are not wired in the prototype; in the build they are editable.
- **Palette:** Condition, If/else, Delay, Wait for, Create, Update and Delete record, Send email, Add note, Campaign action, Project action, Webhook, Slack, Teams. AUT-07's Asana and Trello are missing from the palette.
- "Create invoice in the accounting system" requires an accounting provider, which is not chosen. Show it as an unconnected step that fails at configuration time, not with fake success.
- Slack and Teams require OAuth connections; without them, show unconnected.
- **Step limits (AUT-05):** at most 10 delays and 90 days per path; at most 10 actions per path; a wait-for step gives up after 7 days.
- Activate/Deactivate. Activation is refused, with the reason, when an entitlement limit is set and reached (UF-11).
- **There is no "Test run" in the builder design.** Do not invent one; the only test in the design is the assignment "Test a record".

### Templates
Eight templates in four groups (Follow up and nurture, Pipeline hygiene, Handover and delivery, Customer health). "Use template →" creates a draft from the template graph and opens the builder. These are seeded rows (`workflow_templates`) with i18n keys.

### Monitoring
- **Health cards:** Runs today 214 · 99,1 %; 7 d 1 482 · 12 failed · 4 retried; 14 d 2 910 · "trend stable". All **FAB**, and inconsistent with the list, whose 7-day runs sum to 267 with 4 failed. Derive them from `workflow_runs`.
- **Overview:** Most failed, Most active, Never run. Derived.
- **Run history:** when, workflow, record, step chips (status, with the error as a tooltip, e.g. "Timeout after 10 s", "Template missing merge field"), Retry or Completed.
- The prototype's Retry turns every chip green: **FAB**. Real retry creates a new attempt that resumes from the failed step.
- AUT-09 says the webhook step stores the final request body and path, so `workflow_run_steps.request`. "Owners are alerted on failure" means a notification.
- **Loop protection:** a rolling 10-minute counter, with the source's values of 10 000 per company and 5 000 per workflow (`safeguards`). Each run also carries `depth` and `origin_run_id`, so changes a workflow makes that trigger other workflows are bounded.

### Assignment rules
- Each rule shows a priority number, name, "When {event} · if {condition}" and "→ {assignee}", with ▲▼ to reorder. Footer: "first match assigns the owner and notifies them".
- **Assignee kinds:** a user, a team in round-robin, the organisation's owner, the person's owner.
- **Test a record:** inputs are Source, Employees and Organisation exists; it shows the matched rule and the assignee. It must be a real read-only evaluation RPC.
- The prototype's matcher can never hit rule 1 (Municipality), because the test form has no label input. The build must evaluate every rule; the form needs an organisation-label input or a real record picker.
- "Round-robin → Eirik Moen is next" is derived from the rotation pointer.
- The assignment history (AUT-11) is not in the design. Its data is still required.

### Sequences
- **List:** name and "Deals and leads · 38 enrolled". Counts are **FAB**; derive them from enrolments.
- **Steps:** Email · auto, Email · manual (amber border, "Queued for review"), Delay ("skips weekends"), Activity.
- **Enrolled table:** record, current step, "Enrolled · workflow / bulk / one by one", status (In progress, Failed, Completed).
- **"＋ Enroll a deal"** adds "Granli Eiendom — Pilot n" in the prototype: **FAB**. The build needs a record picker.
- **"Enroll in bulk"** reports "12 deals from «Proposal sent»": **FAB**. The build needs a saved-view or selection source.
- **Exit rules (AUT-12, SF-05):** reply on a linked thread, stage change, manual (one or bulk); a failed send sets status Failed with the reason.
- If `sales_consent` is not Off, consent and suppression are checked before each email step.
- Emails carry the sender's signature.
- Skipping a step or stopping the sequence is not in the design, but the data must support it.

---

## 4. Proposed tables (schema `app`, RLS on, no policy, access through security-definer functions, D-09)

**Mail**
- `mailboxes(id uuid pk, kind text check in (personal,team,meeting), provider text check in (google,microsoft), address citext unique, display_name text, owner_id uuid→admins null, status text check in (connecting,syncing,synced,reauth,error,disconnected), status_detail text, vault_secret_id uuid /*D-18*/, sync_from date, folders text[], default_visibility text check in (private,shared), signature text, sync_cursor text /*historyId|deltaLink*/, watch_expires_at timestamptz, last_synced_at timestamptz, created_at, deleted_at)`
- `mailbox_members(mailbox_id, staff_id, can_reply bool, pk(mailbox_id, staff_id))`
- `sender_aliases(id, staff_id, address citext, kind text check in (send_as,bcc_accepted), verified_at)`
- `dropbox_addresses(local_part text pk, staff_id uuid, entity text null, record_id uuid null, created_at)`
- `email_threads(id, mailbox_id null, provider_thread_id text, subject text, snippet text, last_message_at, last_direction text, visibility text, archived_at, is_sample bool, unique(mailbox_id, provider_thread_id))`
- `email_thread_reads(thread_id, staff_id, read_at)`
- `email_thread_participants(thread_id, address citext, person_id uuid null)`
- `email_messages(id, thread_id, mailbox_id, provider_message_id text, rfc_message_id text, in_reply_to text, direction text check in (in,out), from_addr, from_name, to_addrs jsonb, cc jsonb, bcc jsonb, subject, body_text, body_html, source text check in (sync,crm,dropbox,group,sequence,workflow), state text check in (draft,awaiting_review,scheduled,queued,sending,sent,failed,canceled,received), scheduled_at, sent_at, sent_by uuid, template_id uuid, tracking bool, attempt int, failure_code text, failure_reason text, group_send_id uuid, enrollment_id uuid, run_step_id uuid, activity_id uuid, created_at)`
- `email_attachments(id, message_id, storage_path, filename, mime, size_bytes, provider_attachment_id)`
- `email_links(thread_id, entity text→entities, record_id uuid, linked_by text check in (auto,manual,dropbox), staff_id, created_at, pk(thread_id, entity, record_id))`
- `email_thread_labels(thread_id, label_id→labels)`, with a new `entities` row `email_thread`
- `email_tracking_links(id, message_id, url text, label text, token text unique)`
- `email_tracking_events(id bigint identity, message_id, link_id null, kind text check in (open,click), client_class text check in (human,prefetch,unknown), at)`. No IP is stored.
- `email_templates(id, name, scope text check in (private,shared), is_starter bool, owner_id, subject, body, created_at, updated_at, deleted_at)`
- `merge_fields(token text pk, source_path text, format text)`, seeded
- `email_thread_insights(thread_id pk, upto_message_id, summary, sentiment text, readiness smallint check 1..10, reason, action_items jsonb, suggested_replies jsonb, model text, generated_at, generated_by)`
- `group_sends(id, mailbox_id, template_id, source_kind text, source_ref jsonb, total int, excluded jsonb, consent_mode text, state text, created_by, created_at)`

**Channels**
- `messaging_channels(id, provider text, display_number, status, vault_secret_id)`
- `chat_conversations(id, channel_id, handle text, person_id, lead_id, last_message_at, window_expires_at)`
- `chat_messages(id, conversation_id, direction, body, media_path, template_name, provider_message_id, status text check in (sent,delivered,read,failed), reaction, sent_by, at)`
- `chat_templates(name, language, status, body)`
- `quick_replies(id, label, body, scope, owner_id)`
- `telephony_connections(staff_id pk, provider, status, is_default, vault_secret_id)`
- `call_logs(activity_id pk→activities, direction, outcome text check in (connected,no_answer,missed,busy,voicemail), duration_s int, number text, recording_url, provider_call_id)`

**Feed, scoring and enrichment**
- `feed_card_kinds(kind pk, tab, tone)`, seeded
- `feed_cards(id, staff_id, kind, deal_id, source_type, source_id, params jsonb, dedupe_key unique, created_at, resolved_at, resolved_by text)`
- `feed_scope(staff_id pk, pipeline_ids uuid[], stage_ids uuid[])`
- `score_models(id, name, entity text check in (deal,lead), pipeline_id null, state text, base smallint default 0, created_by, …)`, with a partial unique index on `(pipeline_id) where state='active'`
- `score_criteria(id, model_id, grp text check in (high,slight,negative), ord, join_op text null, condition jsonb)`
- `record_scores(entity, record_id, model_id, score smallint, hits jsonb, computed_at, pk(entity, record_id))`
- `enrichment_requests(id, entity, record_id, kind text check in (company,person,reverse,bulk), provider text, state, proposed jsonb, applied_fields text[], credits int, requested_by, created_at, applied_at)`
- `credit_ledger(id, delta int, provider, request_id, staff_id, at)`
- `lookup_suggestions(id, thread_id, from_addr, proposed jsonb, state text check in (open,accepted,dismissed))`

**One engine (D-06)**
- `workflows(id, kind text check in (workflow,sequence,lifecycle,assignment), name, description, owner_id, state text check in (draft,active), trigger_type text check in (event,date,product_event,enrollment), trigger_config jsonb, conditions jsonb, priority int /*assignment*/, activation_scope text check in (owner,users,team,everyone), template_key text, current_version int, activated_at, created_at, updated_at, deleted_at, is_sample bool)`
- `workflow_versions(workflow_id, version, graph jsonb, published_at, pk(workflow_id, version))`. Runs pin a version, so editing an active workflow never breaks in-flight runs.
- `workflow_activation(workflow_id, staff_id null, team_id null)`
- `workflow_shares(workflow_id, staff_id null, team_id null, can_edit bool)`
- `workflow_runs(id, workflow_id, version, event_id bigint→events null, subject_type, subject_id, state text check in (running,waiting,completed,failed,stopped,loop_blocked), resume_at, wait_deadline, depth int, origin_run_id, retry_of uuid, error, started_at, finished_at)`
- `workflow_run_steps(id, run_id, step_key text, state, started_at, finished_at, error, request jsonb, response_status int, output jsonb)`
- `workflow_templates(key pk, group_key, graph jsonb)`, seeded
- `sequence_enrollments(id, workflow_id, entity text check in (deal,lead), record_id, enrolled_via text check in (one,bulk,workflow), enrolled_by uuid, run_id null, state text check in (in_progress,completed,failed,exited), current_ord int, next_at, exit_reason text, error, created_at, ended_at)`, with a partial unique index on `(workflow_id, entity, record_id) where state='in_progress'`
- `assignment_rotation(team_id pk, last_staff_id, updated_at)`
- `assignment_evaluations(id, workflow_id null, entity, record_id, assignee_id, at)`
- `integration_connections(id, provider text check in (slack,teams,accounting,…), status, vault_secret_id, config jsonb)`
- `event_cursors(subscriber text pk, last_event_id bigint)`. `app.events.processed_at` is a single flag, but SF-02 has several subscribers, each processing an event once, so each subscriber needs its own cursor.

**New setting keys:** `ai_scoring` (AIA-02). The tracking, consent, contact-rule, safeguard and limit keys already exist.

---

## 5. RPCs (security definer, Zod at the edge, audited per D-12)

- **Mail:** `mailbox_list`, `mailbox_connect_start(provider)` → OAuth URL, `mailbox_connect_finish(code)`, `mailbox_update`, `mailbox_disconnect`, `mailbox_members_set`, `sender_alias_add` / `sender_alias_remove`, `dropbox_address_get(deal_id?)`.
- **Threads:** `inbox_folders` (counts), `thread_list(folder, label?, cursor)`, `thread_get(id)` (marks read), `thread_archive(id, archived)`, `thread_label_set`, `thread_link(entity, record_id)` / `thread_unlink`, `thread_to_lead`, `unlinked_threads`.
- **Compose and outbox:** `email_compose(draft)` → render + validate, `email_send(draft, send_at?, track?)`, `email_cancel`, `email_reschedule`, `email_retry`, `outbox_list`.
- **Templates:** `template_list`, `template_save`, `template_delete`, `merge_preview(template_id|body, entity, record_id)` → missing tokens.
- **AI:** `ai_thread_insight(thread_id, refresh)`, `ai_draft_email(thread_id?, prompt, tone, length)`.
- **Group:** `group_send_preview(source)` → recipients and exclusions, `group_send_start`.
- **Channels:** `chat_list`, `chat_get`, `chat_send`, `chat_to_lead`, `call_log_list`, `call_start(number)`, `call_log_manual(activity…)`, `phone_match(number)`.
- **Feed:** `feed_list(tab, filters)`, `feed_resolve(card_id, how)`, `feed_progress()`, `feed_scope_set`.
- **Scoring:** `score_model_list`, `score_model_save`, `score_model_activate`, `score_preview(model_id, record_id)`.
- **Enrichment:** `enrich_company_preview(org_id)`, `enrich_apply(request_id, fields)`, `enrich_person(person_id)`, `enrich_bulk(entity, ids≤100)`, `credits_summary`, `lookup_accept` / `lookup_dismiss`.
- **Workflows:** `workflow_list(filter)`, `workflow_get`, `workflow_save(graph)` (validates limits and node configs, and blocks webhook URLs in private ranges at save time), `workflow_set_state`, `workflow_transfer(id, to_staff)`, `workflow_from_template(key)`, `workflow_monitor()`, `workflow_runs(filter)`, `workflow_run_retry(run_id)`.
- **Assignment:** `assignment_rules_list`, `assignment_rule_save`, `assignment_rules_reorder(ids[])`, `assignment_test(input)` (read-only), `assignment_history`.
- **Sequences:** `sequence_list`, `sequence_save`, `sequence_enroll(entity, ids[])`, `sequence_exit(ids[], reason)`, `sequence_skip_step(enrollment_id)`, `sequence_send_manual(message_id)`.

## 6. Background jobs (pg_cron + pgmq + edge workers, D-05)

| Job | Kind | Purpose |
|---|---|---|
| `mail-notify` | Edge HTTP: Gmail Pub/Sub push and Graph change notifications | Enqueue `mail_sync` |
| `mail_sync` | Queue worker | History or delta fetch, store, match participants, auto-link, emit `email.received` |
| `mail-watch-renew` | Cron, every 6 h | Renew Gmail watch (7-day expiry) and Graph subscriptions (about 3 days); on token failure set `status=reauth` |
| `mail-poll-fallback` | Cron, every 5 min | Catch-up for mailboxes whose watch lapsed |
| `mail-scheduled` | Cron, every minute | Move due `scheduled` messages to `mail_send` |
| `mail_send` | Queue worker | Provider send with per-mailbox throttle; failures store the provider reason |
| `mail-inbound` | Edge HTTP (email provider inbound, signature verified) | BCC drop-box; unmatched mail to the unlinked list and lookup suggestions |
| `t` | Edge HTTP, public host | Open pixel and click redirect (no IP stored) |
| `ai` | Queue | Thread insights and drafts through Claude |
| `events-dispatch` | Cron, every minute + queue | Read `events` past each `event_cursors` entry and fan out to workflows, assignment, scoring, feed, sequences, webhooks and notifications |
| `workflow` | Queue | Execute steps; enforce the 10-minute loop windows; alert owners on failure |
| `workflow-resume` | Cron, every minute | Resume delays; time out wait-for steps after 7 days |
| `workflow-dates` | Cron, hourly | Date triggers (AUT-03, SF-26) |
| `sequence-tick` | Cron, every minute | Due steps, consent check, send or queue for review, create activities |
| `feed-checks` | Cron, hourly | No reply in 5 days, no follow-up, overdue, slipping |
| `scores` | Queue (on field events) + nightly cron | Recompute scores |
| `enrich` | Queue | Brreg / provider calls; debit the credit ledger |
| `telephony-hook`, `messaging-hook` | Edge HTTP | Provider callbacks |

## 7. What cannot work without credentials
Each item below must render an **unconnected** state, never sample output:

- **Gmail and Microsoft Graph OAuth client:** every mail view, sending, archive sync, tracking on CRM-sent mail, group email, sequence emails and the workflow "Send email" step.
- **Email provider inbound route and MX record:** the BCC drop-box.
- **Claude API key:** the AI panel, suggested replies, the Draft button and the "Likely to advance" cards.
- **WhatsApp Business provider:** the messaging view.
- **Telephony provider:** the call log, incoming calls and recordings. The `tel:` fallback works without one.
- **Contact data provider:** person enrichment, LinkedIn and revenue fields, and reverse lookup. Brreg works without credentials.
- **Slack, Teams or accounting OAuth:** the corresponding workflow steps.
- **Gmail add-on:** not built.

## 8. Other points to log
- Erasing a person (D-24) must also delete their `email_messages`, insights, chat messages and call logs.
- IMAP in the "Add mailbox" button is outside D-07.
- LinkedIn is left out by D-39.
- The credit top-up conflicts with D-17.
