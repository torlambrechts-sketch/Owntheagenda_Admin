# Campaigns schema (0037) — departures, message keys and the RPC contract

Migration `supabase/migrations/0037_campaigns.sql`, proved by `supabase/tests/phase6_campaigns_invariants.sql` (189 checks).
Spec: `docs/crm-enrichment/specs/marketing-documents.md` §1 (Campaigns, Email builder, Audience and consent, Deliverability),
§3–§11. Reused from earlier migrations: consent wording, `app.consent_write`, suppressions, the consent log and status summary
(0031), `app.email_hash`, `app.token_hash`, `app.connected`/`require_connected` (0031), the merge registry (0020/0032),
`app.filter_sql` (0023/0034), the engine (0021/0032), `app.doc_html_unsafe` and `app.doc_tokens` (0032).

## Departures from the spec

| ID | Where | Spec | Built | Reason |
|---|---|---|---|---|
| V-P6C-01 | `campaign_schedule` | `(p_id, p_at, p_version)` | `(p_id, p_at, p_version, p_html)` | The renderer is TypeScript (one renderer for preview, test and send, SF-39). Scheduling receives its output, checks it and freezes it with its links; SQL cannot render the design |
| V-P6C-02 | Scheduling without the provider | `campaign_schedule` refuses `not_connected` | Scheduling works without the provider; a due campaign stays `scheduled` with `hold_reason` (`not_connected:email`, `sender_domain`, `audience`) and its owner is notified once per reason. Test send and the send worker answer `not_connected` (email) | The lead's brief: the database must let you build, schedule and count honestly. CMP-05/CMP-08 are about leaving and sending; the hold is the honest state the screen shows |
| V-P6C-03 | Sender domain checks | One «verified» condition | *Authenticated* = SPF + DKIM + a DMARC record (DNS check, no key) is required to schedule; *verified* = authenticated + the provider's verification (`verified_at`, never set while the provider is not connected) is required to send, test and run a workflow step | Follows from V-P6C-02; «Verified is not_connected without the provider» (§1) |
| V-P6C-04 | `campaigns` check constraint | `status = 'draft' or type = 'automated' or segment_id is not null` | Dropped. The segment's name is frozen into `audience_name` at schedule; schedule and `campaign_due` require the segment | `segment_id` is `on delete set null` and saved views cascade from their owner: the check would block the database's own referential maintenance (CLAUDE.md rule on immutability triggers) |
| V-P6C-05 | New columns | — | `campaigns.html` («Code your own HTML»), `audience_name`, `hold_reason`, `canceled_at`; `campaign_recipients.claimed_at`, `failure_code`, `last_open_at`, `last_click_at`; `sender_domains.version`, `updated_at`; domain unique among non-deleted rows | Hand-written HTML campaigns, the report's audience line after a segment is gone, the honest hold state, batch claiming, failed sends, «days since last open» filters that survive event pruning, optimistic locking, re-adding a removed domain |
| V-P6C-06 | Unsubscribe token | `unsub_token text` (plaintext) | `unsub_token_sha256 bytea`; a fresh token is returned once per recipient in `worker_campaign_batch` | House rule: tokens are stored only as SHA-256 (0031, 0032) |
| V-P6C-07 | `v_campaign_stats` | A view | `app.campaign_stats(id)` (internal function) used by the list, the card, the recipients read and the comparison | One function makes CMP-09's «same figures» structural; no view in the closed schema |
| V-P6C-08 | Bounce rate | `count(state = 'bounced') ÷ sent`, hard and soft on hover | `bounce_rate` = (hard + soft) ÷ sent, with `bounced_hard` and `bounced_soft` | The state machine keeps soft bounces in their own state; the spec's formula would hide them |
| V-P6C-09 | `sent_at`, signups | Signups after `sent_at` | `started_at` = sending began, `sent_at` = the last recipient left; signups and MRR won count from `started_at` | Signups during a long send are not lost |
| V-P6C-10 | Cancel and pause | Cancel (scheduled only), Pause/Resume (automated) | Cancel is terminal (`canceled`); a canceled campaign is duplicated to change it. While paused, workflow steps still queue recipients; nobody is sent until resumed | The spec's states; the minimal consistent rule for queued recipients |
| V-P6C-11 | Automated campaigns | — | Activating (`campaign_schedule`, no time) freezes the content like a broadcast; no A/B (`subject_b` refused) | Sent content is immutable for the report; an A/B test needs a broadcast audience |
| V-P6C-12 | `campaign_test_send` | Merged with the caller as the person | `(p_id, p_html, p_person)`: to the caller's own address, merged with a person they choose (or none: tokens stay as listed missing); queued as job `campaign_test`; never a recipient | Staff are not people; a token has no value for them |
| V-P6C-13 | `campaign_preview` | `(p_id, p_person)` → `{html, missing, unknown}` | `(p_id, p_person, p_html)` → also subjects, preheader and `audience_missing: [{token, people}]` when no person is given | COM-05: missing values are listed before scheduling. Counts people (not addresses) |
| V-P6C-14 | Extra and widened RPCs | — | `worker_campaign_failed`, `sender_domain_delete`; `segment_save(..., p_shared)`; `campaigns_compare(p_ids, p_type)`; `campaign_export` returns `{filename, mime, rows, content}` (CSV only); `worker_unsubscribe(p_token, p_scope, p_method)` | A refused send needs a state; a domain needs removing; the compare default follows the type filter; SQL cannot write a file |
| V-P6C-15 | Workflow blockers | `not_connected:email`, `sender_domain_unverified` | Also `campaign_inactive` (draft or deleted campaign); at run time a draft campaign fails the step with `campaign_inactive`, an organization subject is skipped `no_email` | Same pattern as 0026's `sequence_inactive` |
| V-P6C-16 | Subscriber allowance | «Pending upgrade» row, skip `over_allowance` | Not derived; `over_allowance` stays a check value only | No allowance number exists in the register (`plan_gates` has none, `count_limits` does not apply to CMP-05); nothing sold (D-17); never fabricated |
| V-P6C-17 | Insights and Automation | Report entity `campaign` (INS-01); segment as a workflow condition | Not added | Out of the campaign schema's reach; CMP-09 is `campaigns_compare`. The report entity is added by 0040 (type, status, owner; sent, open rate, click rate); the segment as a workflow condition stays open |
| V-P6C-18 | Starting layouts | Seeded rows | Seeded in the migration (`Newsletter`, `Product announcement`, structure only, no product claims, Q18) | Configuration, not demo data; the demo «Saved: Webinar invite» belongs in the seed script |
| V-P6C-19 | Figures of others' campaigns | `campaigns:reports_others` | Own campaigns, or `reports_others`, or `edit_others` | The Marketing preset has `edit_others` but not `reports_others`; it would edit colleagues' campaigns without seeing their figures |
| V-P6C-20 | Audience resolution | — | Resolved as the campaign's owner sees people (D-09); the frozen `audience_count` equals the owner's `segment_count.receivable` | Visibility is enforced in the definer functions; a private person of another owner is never mailed through someone else's campaign |
| V-P6C-21 | Recipients | — | One row per person in the segment, skipped ones with their reason and **no address**; one queued row per address (`duplicate`) | The report shows who was left out and why without keeping addresses that cannot be mailed |
| V-P6C-22 | Events | Per provider event | `campaign.opened` on a recipient's first human open, `campaign.clicked` on the first human click per link, `campaign.delivered` once; `campaign.deleted` on a draft delete | Workflows trigger on engagement, not on every pixel load; `rec_delete`'s convention |
| V-P6C-23 | Footer check | `[Unsubscribe]` token in HTML | Campaign HTML must contain `[Unsubscribe]` **and** the sender domain's postal address (raw or HTML-escaped); templates need the token | D-27 sender identity, enforced structurally |
| V-P6C-24 | Generic saved views | — | `view_save` and `view_delete` only touch `kind = 'view'`; segments change through `segment_*` (a segment a scheduled campaign needs cannot be deleted) | The in-use rule would otherwise be bypassed |
| V-P6C-25 | `suppressions.campaign_id` | Foreign key | Foreign key `on delete set null` added | Resolves V-P5-10 |
| V-P6C-26 | Design model | Kinds title … menu | Also `header` and `footer` kinds; keys `alt` and `items`; footer: exactly one, last, `kind` and `bg` only | The design's header and fixed footer rows are rows of the model |
| V-P6C-27 | Mail tables | Reuse the outbox and link tracking | Campaigns do not go through `email_messages` (mailbox path); own `campaign_links`/`campaign_events`, same conventions (random tokens, client classes, no IP) | The marketing stream is the provider's, not a staff mailbox (D-07, «separate streams») |
| V-P6C-28 | `campaign_links.token` | — | Plaintext | The same in every copy of the campaign; it names a link, not a person |
| V-P6C-29 | Tracking rule | `off` forces no tracking | `on` forces tracking, `per_email` uses the campaign's choice, `off` none — frozen at schedule; untracked opens and clicks are not stored and their figures are null | Same reading as mail (0020) |
| V-P6C-30 | Hygiene | — | Candidates and archiving cover the people the caller may see | D-09 |

## Keys the app must add

**Notifications** (`app.notify`, kind `system`, route `/campaigns` unless noted):
- `campaign.held` — `{campaign, reason}`; reason ∈ `not_connected:email`, `sender_domain`, `audience`
- `campaign.sent` — `{campaign, sent, failed, bounce_rate}`
- `campaign.sent_with_problems` — same params (failed sends, or bounce rate above 3 %)
- `campaign.ab_decided` — `{campaign, winner, a, b}`
- `campaign.engaged` — `{campaign, person, kind}` (kind ∈ `opened`, `clicked`; route `/contacts`, entity person)

**Enumerations shown on screen**
- Campaign type: `newsletter`, `one_off`, `promotion`, `product_announcement`, `automated`
- Campaign status: `draft`, `scheduled`, `sending`, `sent`, `active`, `paused`, `canceled`; hold reason as above
- Recipient state: `queued`, `sent`, `delivered`, `soft_bounced`, `bounced`, `complained`, `failed`, `skipped`; skip reason: `not_subscribed`, `suppressed`, `no_email`, `duplicate`
- Recommendation kind: `dns_missing` (records: `spf`, `dkim`, `dmarc`), `dmarc_none`, `bounce_rate`, `hygiene`, `identity`
- Workflow blockers: `not_connected:email`, `campaign_inactive`, `sender_domain_unverified`; step skip reasons as recipient skip reasons
- Design row kinds: `header`, `title`, `paragraph`, `list`, `image`, `button`, `divider`, `social`, `html`, `video`, `icons`, `menu`, `footer`; backgrounds `card`, `soft_yellow`, `mint`, `cream`; padding 14/22/32; border `none`/`hairline`

**Error details** (`common.errors.invalid` + detail): `subject`, `subject_a`, `subject_b`, `preheader`, `sender_domain`, `sender_domain.postal_address`, `sender_domain_id`, `html`, `html.footer`, `merge:<token>`, `audience`, `scheduled_at`, `coupon_code`, `utm_campaign`, `utm_source`, `utm_medium`, `segment_id`, `template_id`, `design`, `design.rows`, `design.footer`, `design.<row>.<field>`, `status`, `type`, `name`, `ab_percent`, `ab_metric`, `ab_wait_hours`, `in_use`, `expected`, `list_hygiene`, `domain`, `stream`, `from_name`, `from_local`, `reply_to`, `postal_address`, `layout`, `scope`, `filter.<field>`, `query`; `not_connected` detail `email`; `version_conflict` detail = current version.

**Jobs** (pgmq `jobs`, for the edge workers): `campaign_send {campaign_id}`, `campaign_test {campaign_id, to, stream, from, from_name, reply_to, subjects, html}`, `dns_check {sender_domain_id}`.
Cron: `platform-campaign-due` (every minute), `platform-campaign-ab` (every 10 minutes), `platform-dns-check` (nightly), `platform-campaign-prune` (daily, 13 months).

## RPCs for the screen builder

All `public.*`, security definer, `search_path = ''`, module `campaigns`. Rights in brackets. Campaign row (`campaign_row`):
`{id, seq, name, type, status, hold_reason, owner_id, owner, mine, audience: {kind:'segment', segment_id, name, count, matches, live} | {kind:'workflow', workflows:[{id,name,state}]}, scheduled_at, started_at, sent_at, canceled_at, stream, sender_domain, subject_a, subject_b, ab: {percent, metric, wait_hours, winner, decided_at, decides_at} | null, notify_owners, version, updated_at, stats | null, reports}`.
Detail adds `{segment:{id,name,query}, template_id, design, html, rendered_html, preheader, sender_domain_id, from_name, from, postal_address, product, coupon_code, utm:{source,medium,campaign}, tracking, tracking_rule, visibility, labels, links:[{id,url,label,clicks}], top_locations:[city…], provider_connected, domain:{authenticated, verified}}`.
Stats (`null` until there are recipients; open/click fields `null` while untracked; rates `null` over 0):
`{recipients, sent, queued, skipped, failed, delivered, bounced, bounced_hard, bounced_soft, bounce_rate, tracking, unique_opens, total_opens, unique_clicks, total_clicks, open_rate, click_rate, ctor, unsubscribed, unsub_rate, complaints, complaint_rate, a_metric, b_metric, signups, mrr_won, mrr_excluded_currency}`.

| RPC | Right | Returns |
|---|---|---|
| `campaigns_get(p_query jsonb default '{}')` — `{type?, status?, q?, owner?:'me', limit?}` | see | `{rows: [campaign_row], provider_connected}` |
| `campaign_get(p_id uuid)` | see | campaign_row detail |
| `campaign_save(p_id uuid, p_values jsonb, p_version int default null)` — keys `type, name, segment_id, template_id, design, html, subject_a, subject_b, preheader, ab_percent, ab_metric, ab_wait_hours, sender_domain_id, product, coupon_code, utm_source, utm_medium, utm_campaign, tracking, notify_owners, visibility` | add (others': edit_others) | campaign_row detail |
| `campaign_duplicate(p_id uuid)` | see + add | campaign_row detail (new draft) |
| `campaign_delete(p_ids uuid[], p_reason text default null)` | delete (+ bulk for several) | `{deleted}` |
| `campaign_preview(p_id uuid, p_person uuid default null, p_html text default null)` | see | `{subject_a, subject_b, preheader, html, missing, unknown, audience_missing:[{token, people}]}` |
| `campaign_test_send(p_id uuid, p_html text default null, p_person uuid default null)` | add/edit_others | `{queued:true, to}` |
| `campaign_schedule(p_id uuid, p_at timestamptz, p_version int, p_html text)` | add/edit_others | campaign_row detail |
| `campaign_cancel(p_id uuid)` | add/edit_others | campaign_row detail |
| `campaign_pause(p_id uuid, p_paused boolean)` | add/edit_others | campaign_row detail |
| `campaigns_compare(p_ids uuid[] default null, p_type text default null)` | see (+ reports for others') | `{rows:[{id, name, type, status, sent_at, stats}], axis_max:100}` |
| `campaign_recipients(p_id uuid, p_state text default null, p_limit int default 100)` | see + reports | `{rows:[{id, person_id, name, email, state, skip_reason, variant, sent_at, delivered_at, opened_at, clicked_at, unsubscribed_at, complained_at, bounce_kind}], stats}` (name/email null for people the caller may not see) |
| `campaign_export(p_id uuid, p_format text default 'csv')` | export + reports | `{filename, mime, rows, content}` |
| `marketing_templates_get()` | see | `[{id, name, layout, category, scope, subject, design, html, current_version, version, updated_at, owner, mine}]` |
| `marketing_template_save(p_id uuid, p_values jsonb, p_version int default null)` — `name, scope, category, subject, design, html, layout` | add (others': edit_others; layouts: configure) | `{id, version, current_version}` |
| `marketing_template_delete(p_id uuid)` | delete (others': edit_others; layouts: configure) | `{id}` |
| `segment_count(p_query jsonb)` — `{filters:[…]}` with person fields plus `organization.<name|employees|industry|nace|city|fylke|country|postal_code>`, `organization.status`, `member.role`, `engagement.opened_days`, `engagement.clicked_days`, OR groups | see | `{matches, receivable}` |
| `segments_get()` | see | `[{id, name, description, query, shared, mine, owner, updated_at, matches, receivable}]` |
| `segment_save(p_id uuid, p_name text, p_query jsonb, p_description text default null, p_shared boolean default true)` | add (others': edit_others) | `{id, matches, receivable}` |
| `segment_delete(p_id uuid)` | delete (others': edit_others) | `{id}` |
| `marketing_status_summary()`, `consent_log(p_limit, p_before)` (0031; the log now names the campaign in `ref_label`) | see | as 0031 |
| `suppressions_get/suppression_add/suppression_remove` (0031) | see / bulk | as 0031 |
| `hygiene_candidates()` | see | `{enabled, months, count, people:[{id, name, email}] (≤50)}` |
| `hygiene_archive(p_expected int)` | bulk | `{archived}` |
| `sender_domains_get()` | see | `{rows:[{id, domain, stream, sends_here, product, from_name, from_local, reply_to, postal_address, spf_ok, dkim_ok, dmarc_policy, verified_at, authenticated, verified, last_checked_at, check_detail, version, warmup:{day, days, done}|null, rates:{sent, delivered, bounce_rate, complaint_rate}|null}], provider_connected}` |
| `sender_domain_save(p_id uuid, p_values jsonb, p_version int default null)` | configure | sender domain row |
| `sender_domain_delete(p_id uuid)` | configure | `{id}` |
| `sender_domain_recheck(p_id uuid default null)` | configure | `{queued}` |
| `deliverability_recommendations()` | see | `[{kind, level, domain?, records?, rate?, count?, months?, ok?, domains_missing_address?}]` |
| Workers (service role): `worker_campaign_batch(p_campaign, p_limit)`, `worker_campaign_sent(p_recipient, p_provider_message_id)`, `worker_campaign_failed(p_recipient, p_code)`, `worker_email_events(p_batch)`, `worker_unsubscribe(p_token, p_scope, p_method)`, `worker_sender_domain_status(p_id, p_checks)` | — | see the migration's comments |

## Left open

- The segment as a workflow condition (the Insights report entity `campaign` came with 0040) (§1 «usable as a condition in workflows»).
- The edge workers themselves (send, provider webhooks, DNS-over-HTTPS check, unsubscribe page on go.owntheagenda.com) and the TypeScript renderer.
- Seed: the design's campaigns, segments and domains for the demo belong in a seed module; none is in the migration except the two layouts.
- The subscriber allowance («Pending upgrade») waits for a number in the register (Q2).

## Added by 0040 (Phase 6 requests)

- `campaign_coupons()` (see) → `[{code, description, percent, months}]`, active coupons only.
- `campaign_save` key `language` (`nb | nn | en | sv`, default `nb`; error detail `language`); the detail returns `language`; frozen with the content; copied by `campaign_duplicate`.
- People filter field `product.last_round_days` (numeric days; null when no tenant of the person ever opened a round).
- `marketing_template_versions(p_id)` (see) → `[{version, subject, created_at, by}]`, newest first; `marketing_template_restore(p_id, p_version)` (add; others' edit_others; layouts configure) → `{id, version, current_version}`; errors `not_found` (detail `version`), `invalid` (detail `version` for the current one).
