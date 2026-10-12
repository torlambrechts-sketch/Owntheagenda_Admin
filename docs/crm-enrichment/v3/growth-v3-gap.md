# Growth v3: Marketing campaigns and Email and automation (gap analysis)

Evaluator: growth, 12 Oct 2026. Design: `design-reference/sentral-simple/GrowthMarketing.dc.html`, read in full (the markup and
the `<script>`, every literal, every computed value, every button and what it pretends to do), diffed against its previous
version (`git diff e8a5565~1 e8a5565`: the handoff was committed in `e8a5565`, so a working-tree diff is empty). The shell
`Sentral Simple.dc.html` was diffed the same way. SimpleGrowth, GrowthPlaybook and SeoSuite are unchanged in `e8a5565`.
Shared runtime: `design-reference/sentral/project/admin-data.js` (`kr`, `nb`, `pct`).

I rendered it with `scripts/visual/design-simple.mjs` and with a scratch variant that clicks by selector, at 1440 px and 390 px.
I clicked a day, applied a tip, opened each of the five campaigns, opened each sequence, applied the email tips and pressed «Send
all steps at the best time». Screenshots: `/tmp/claude-0/-home-user/ebb42717-a6b5-52e0-a1e8-4cdc6ef4f4f9/scratchpad/v3/growth/`
(`campaigns*.png`, `email*.png`).

I checked the design against these sources:
- the app: `app/(admin)/growth/_components/Campaigns.tsx`, `Email.tsx`, `ads/*`, `page.tsx`, `lib/data/simple-growth*.ts`,
  `lib/data/growth.ts`;
- the migrations: 0020, 0021 (engine: `if_else`, `wf_delay_until`, `wf_start`), 0025, 0037 (campaigns, recipients, events,
  `campaign_stats`), 0058, 0059, 0060, 0067, 0068, 0073, 0074, 0076 and 0077;
- the edge functions `_shared/ads.ts`, `ads-run`, `_shared/brevo-events.ts` and `_shared/web-collect.ts`;
- the docs `SIMPLE-PLAN.md`, `DECISIONS.md`, `growth-v2-gap.md`, `deviations/simple-growth.md` and `deviations/growth-v2.md`;
- the local database, SELECT only;
- read only, the Orgpuls repository: what `org.attribution` carries (0205, 0206).

## Legend

| Verdict | Meaning |
|---|---|
| **build** | Real on the existing backend, or with a new migration in this repo. An existing connection (the 0077 ad imports, Brevo, the tracker) counts as existing |
| **build+connector** | Real only once a connection we can build here exists. The connection is named |
| **needs-orgpuls** | Needs an Orgpuls command or event that does not exist. It is named |
| **needs-decision** | Needs a product decision only Tor can make. It is named (D-GR3-n below) |
| **cannot** | Cannot be real, because it is invented by nature or a rule forbids it. The honest rendering is named |
| *built* | Already in production and unchanged by this design. Listed so the tab is complete |

## Overview

**What changed.** Only `GrowthMarketing.dc.html` changed in Growth.
- **Marketing campaigns › Campaigns.** The campaign card gains three blocks between «Budget used» and «Tracking link»:
  - «Daily spend and signups · click a day»: 21 bars, each with a signups bar inside, and a day line under them.
  - «Ads and keywords in this campaign»: rows with clicks, signups and cost per signup.
  - One or two **tips** per channel, each with an apply button whose toast says «… · applied via <channel> API».
- **Email and automation › Email campaigns.** Two cards are added under the editor:
  - «Results per step · <name>, Last 30 days»: sent, open, click, unsubscribe and signups per email of the sequence, with three
    email tips: «Create A/B test», «Add condition» and «Use best time».
  - «Best time to send»: a weekday × hour open-rate heatmap, «Best: Tue 08:00 (54 %)», and «Send all steps at the best time».

The add-step buttons' padding changed (`4px 0` became `4px 0 14px`). That is layout only.

**The shell** (`Sentral Simple.dc.html`) changed in two places, both for the Development section: a fifth rail item
(«Development · Roadmap, bugs, releases», listed last, with a code icon) and `<dc-import name="DevHub">` with no `go`, `product`
or `tab` props. Nothing in it touches Growth.

**What the new blocks pretend.** Every new value is invented:
- **The daily bars are random.** Spend per day is `spent / 21 × (0.6 … 1.4)` from a seeded generator, and signups per day are
  the same.
  - The window ends «11 Oct», so it reaches back into September. The month label is hard-coded, so September's days read
    «Mon 21 Oct … Wed 30 Oct».
  - Bars are drawn before the campaign started (Lovkrav, 1 Oct) and while it was paused (Retargeting).
  - A one-day webinar has 21 days of spend.
- **The ads and keywords are literal lists per channel.** Each row's cost is the campaign's whole spend split by click share. A
  tip's text contradicts its own row: «1 300 kr per signup» against the row's 1 135 kr.
- **Applying a tip changes nothing.** The tip goes and a toast claims the platform API was called.
- **«Results per step» is invented.**
  - Sent is `enrolled × 3 − i × 30`. Open, click and unsubscribe rates are fixed arrays.
  - They are printed even for a draft with 0 sent (Webinar follow-up: «0 · 55 % · 18 % · 0,2 %»).
  - The same three tips appear for every sequence, whatever its figures. «Email 2 has a 9 % click rate» shows on a sequence that
    sent nothing.
- **The heatmap is a formula.** It is the same for every sequence. «Best: Tue 08:00 (54 %)» is literal markup.
- **The best-time button changes no step.**
- **At 390 px the heatmap collapses to zero width.** The prototype has no small layout (V-SGR-27).

**What exists today:**
- **Ad imports (0077).** Each linked account's campaigns, ads and days are imported read only: `ad_platform_campaigns`,
  `ad_platform_ads`, `ad_daily` (`level campaign|ad`: impressions, clicks, spend, conversions, reach).
  - A platform campaign counts as a Sentral campaign (`ad_platform_campaigns.ad_campaign_id`), so a campaign's daily spend is
    real when it is platform-linked.
  - **Keywords and Meta ad sets are not imported.**
  - Nothing is ever written to a platform. The setup asks for Google «Read only» users, Meta `ads_read`/`read_insights` and
    LinkedIn `r_ads r_ads_reporting`.
- **The tracker (0066/0068).** It records `web_sessions.utm` (utm_source, medium, campaign, term, content) and `web_events`
  (`signup_started`, `signup_completed`, `cta`, `signup_error`) per session, cookieless.
  - So visits and **completed signups per utm_campaign, utm_term and utm_content per day** can be counted now. Locally,
    `lovkrav-q4` has 3 802 sessions, 33 completed signups and 4 distinct terms.
- **Email (0037/0059/0060).** Each email step of a simple sequence is an automated `campaigns` row.
  - `campaign_recipients` holds per send `sent_at`, `delivered_at`, `first_open_at` (human opens only: Brevo's `proxy_open` is
    `prefetch` and is not counted), `first_click_at`, `unsubscribed_at`, `bounced_at` and `complained_at`.
  - `campaign_events` holds each event with `at` and `client_class`.
  - Every email campaign has its own `utm_campaign`, and mail-run puts it on the links.
  - So per-step results over 30 days and an open rate by send weekday × hour can be computed exactly.
  - Automated campaigns may **not** have an A/B subject (`check (subject_b is null or type <> 'automated')`, 0037).
- **The engine (0021).** It has `if_else` with branches that converge, so «skip the next email if …» is expressible. The simple
  model only compiles `condition`, which *ends* the run (V-SGR-20).
  - The delay has amount, unit and `skip_weekends`, but **no time-of-day window**.
  - `app.wf_start` starts a run for a person, so enrolment by hand is possible.
- **Signups by product attribution do not exist in production.**
  - Orgpuls's `org.attribution` carries only `heard` since its 0206 (5 Oct). That migration also dropped Orgpuls's own
    `org_attribution` and `web_events`.
  - Its original 0205 names (`campaign`, `term` …) never matched what Sentral reads (`utm_campaign`, `first_touch`).
  - 0074 already notes «Orgpuls reports only how a person heard of it».
  - The campaign card's existing «Signups» (0058/0077 `ad_campaigns_get`) counts `account_products.attribution ->>
    'utm_campaign'`, so it shows **0 as if real** (see Risks, R-1). Locally the figure comes from the visual sample
    (`scripts/visual/growth-sample.sql`).

---

## Tab: Marketing campaigns › Campaigns (view `campaigns`)

Today's screen: `CampaignsTab` / `Detail` in `Campaigns.tsx` on `ad_campaigns_get` (0077). In the card, the design's order is
stats, budget, **daily**, **ads and keywords**, **tips**, tracking link. Sentral's added «Spend» entry row (V-SGR-14) stays
after the tips, before the tracking link.

### New elements

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Label «Daily spend and signups · click a day» | Static caps label | — | — | **build** | i18n key (en, no) |
| Spend bar per day, platform-linked campaign | 21 bars, height = day spend ÷ max × 96 % + 2 %. Random spend, including days before the start and while paused | Spend per day for the platform campaigns that count as this one, in the account's currency | `ad_daily` (level `campaign`), joined through `ad_platform_campaigns.ad_campaign_id`, is imported nightly but not read per day for a campaign | **build** | New read `ad_campaign_detail` (below). Window = the 21 days to yesterday (Europe/Oslo; the platform's day is in the account's time zone, said in a hint when it is not Oslo). A day without a row is an empty slot. No bar before `starts_on`. Spend in a non-NOK account is shown in its currency, never converted (V-GR2-43) |
| Spend bar per day, typed-spend or no-spend campaign (Webinar, Newsletter, Other, an unlinked ad campaign) | Same random bars (the 2 Oct webinar has 21 days of spend) | Spend per day | Spend is typed **per month** (`marketing_spend`) | **cannot** | Spend is never pro-rated (V-SGR-09). Draw no spend bars; the signups bars alone, with one line: «Spend is entered per month; daily spend comes from a connected ad platform». With no signups either, use the design's empty treatment: 2 % stubs, which the prototype draws for Newsletter |
| Signups bar inside each day | Height = day signups ÷ max; random | Signups per day attributable to this campaign | Tracker: `web_sessions.utm ->> 'utm_campaign'` = the campaign's utm, with a `signup_completed` event that day. Product attribution: none in production | **needs-decision** (D-GR3-2) | Recommended: the tracker's completed signups (cookieless, live since 8 Oct). Alternative: the platform's conversions (`ad_daily.conversions`, platform-linked only). Product-confirmed signups need Orgpuls (see Orgpuls). Whichever is chosen, the card's «Signups» stat and the totals line must use the same definition (R-1) |
| Bar tooltip (`title`) «Sun 11 Oct · 419 kr · 2 signups» | Weekday and date, but the month is hard-coded «Oct» | Day, spend, signups | — | **build** | Dates through `next-intl` (`format.dateTime`), so 21 Sep is «Mon 21 Sep». Plural rules («1 signup»). Spend «—» where spend cannot be drawn. The `<button title>` gets an `aria-label` with the same text |
| Click a day: bar turns `#F5C64A` | Local state `cday` | — | — | **build** | `aria-pressed` on the day button; keyboard focus style |
| Day line «Sat 10 Oct: spent 423 kr, 3 signups, 141 kr per signup» | Shown after a click. Per signup only when signups > 0 | The day's spend and signups | — | **build** | «spent —» for typed spend; «per signup» only when both are real |
| Label «Ads and keywords in this campaign» | Static | — | — | **build** | Hidden when the campaign has no platform link (no rows can exist) |
| Ad rows (Google responsive search ads, LinkedIn creatives, Meta ads): name, clicks | Literal lists per channel («Video: 18 minutes to first survey» 310 clicks …) | Each ad of the platform campaigns that count as this one: name or first headline, clicks in the window | `ad_platform_ads` (name, headline, status) and `ad_daily` level `ad` (clicks, spend, conversions): imported, read only by Creative › Ad variants (`growth_ads`) | **build** | In `ad_campaign_detail`: ads joined on `campaign_external_id`, with 30 days of clicks (the design says no window; 30 days matches the Creative view). Column headers are missing in the design: add visually hidden headers or `aria-label`s, logged as a deviation |
| Keyword rows («lovkrav arbeidsmiljø» …): text, clicks | Literal Google list | Google Ads keywords per ad group with daily clicks, cost and conversions | **Not imported** (0077 queries campaign, ad_group_ad only) | **build+connector** | Google Ads keyword import: extend `ads-run` with a `keyword_view` query (criterion id, keyword text, match type, status, ad group, `effective_cpc_bid_micros`, daily metrics), using the same read-only credentials. New tables `ad_platform_keywords` and `ad_keyword_daily`. **Never `search_term_view`**: what people typed can carry a name (R-5). Keyword text is the advertiser's own |
| Meta ad set / audience rows («Retargeting /pris visitors», «Lookalike paying customers») | Literal | Meta ad sets with daily metrics | Ad sets **not imported**; Meta ads are | **build+connector** | Meta ad set import (`act_<id>/adsets`, insights `level=adset`), table `ad_platform_adsets` and `ad_daily` level `adset`. Until then, Meta rows are its ads |
| Row «Registrations 140 · 22» (Webinar) | Literal | Webinar registrations | No webinar source in Sentral | **cannot** | No rows for a channel with no platform. The block is omitted (an empty block would look like «no ads») |
| Row «Main CTA 0 · 0» (Newsletter) | Literal | The newsletter's link clicks | `campaign_links` and `campaign_recipients.clicks` exist for **email campaigns**, but an `ad_campaigns` row of channel newsletter has no link to its email campaign (both `utm_campaign` columns are unique and kept apart by 0077) | **needs-decision** (D-GR3-8) | With a link `ad_campaigns.email_campaign_id`: the email's links with their unique clicks. Without it, omitted |
| Signups per ad / keyword row | Literal | Signups attributable to the ad or keyword | Tracker sessions carry `utm_content` and `utm_term`, but only if the platform's tracking template puts the ad id and keyword there. Platform conversions per ad exist (`ad_daily.conversions`), per keyword once imported | **needs-decision** (D-GR3-2, D-GR3-3) | Tracker: `utm_term` = keyword (Google `{keyword}`), `utm_content` = ad id (Google `{creative}`, Meta `{{ad.id}}`, LinkedIn's creative id). That is a convention set in each platform; Sentral can show whether sessions carry it. Or platform conversions, labelled «conversions as <platform> counts them». «—» when neither exists |
| Cost per signup per row | Campaign spend × the row's click share ÷ signups (an invented allocation); «—» without signups | The row's own spend ÷ its signups | Spend per ad is imported (`ad_daily` level `ad`), and per keyword once keywords are | **build** | Real per-row spend, never an allocation. «—» without spend, without signups, or in a non-NOK account where kroner are shown |
| Red cost per signup (`#A33A16` when > 900 kr) | Fixed threshold | — | — | **build** | The design's 900 kr as drawn. A threshold relative to the campaign (for example ≥ 2× its own cost per signup) is offered as D-GR3-9 |
| Tip text (Google) «hms system costs 4× more per signup than the rest — pause it and add it as a negative keyword.» | Literal | Per-keyword cost per signup against the others' | Keywords not imported; signups per keyword per D-GR3-2/3 | **build+connector** | A stated rule on real figures, for example: a keyword with ≥ N clicks whose cost per signup is ≥ 3× the campaign's other keywords (the ratio printed, not «4×»). Shown only when every input exists |
| Button «Pause keyword» (and the negative keyword) | Removes the tip; toast «Pause keyword · applied via Google Ads API» | A write to Google Ads: the ad group criterion's status PAUSED, plus a campaign negative keyword | Nothing writes to a platform (0077, V-GR2-42/44). The credentials are Read only by setup | **needs-decision** (D-GR3-1) | Write path below. Until it is decided, the honest rendering is a disabled button with the one-line reason «Sentral reads Google Ads; pause it in Google Ads» |
| Tip text (Google) «… converts best — raise its bid 20 %.» | Literal | Per-keyword cost per signup, and the campaign's bidding strategy | Neither imported | **build+connector** | Rule: the keyword with the lowest cost per signup and ≥ N signups. Only under manual or enhanced CPC: with smart bidding (Maximise conversions, target CPA …) keyword bids are ignored, so the tip is not shown. Needs `campaign.bidding_strategy_type` in the import |
| Button «Raise bid» | Removes the tip; toast | A write: `cpc_bid_micros` × 1.2 on the criterion | — | **needs-decision** (D-GR3-1) | Write path. Under smart bidding it is a **cannot**, disabled with «This campaign's bids are set by Google» |
| Tip text (LinkedIn) «Daglig leder, construction costs 1 300 kr per signup — move budget to the video ad.» | Literal and inconsistent (the row says 1 135 kr) | Per-creative cost per signup | Creatives and their spend imported | **build** | Rule on real per-ad figures, with the printed figure being the row's own |
| Button «Move budget» | Removes the tip; toast | LinkedIn budgets are **per campaign**, not per creative | — | **needs-decision** (D-GR3-1) | As worded (to «the video ad» inside the same campaign) it is a **cannot**. Possible only between two campaigns: two writes (`rw_ads`, `dailyBudget`) that are not atomic. Otherwise, a disabled button with the reason |
| Tip «Use the CRM list «HR in trial accounts» as an exclusion …» + «Add exclusion» | Literal | Uploading the list's addresses, hashed, to LinkedIn Matched Audiences, then excluding it | Not built on purpose (V-GR2-45) | **needs-decision** (D-GR3-4, then D-GR3-1) | A decision about customer users' personal data (they are customer contacts from `member.joined`, never respondents). Until then: not shown |
| Tip text (Meta) «Lookalike audience is underperforming — limit to retargeting only.» | Literal | Per-ad-set cost per signup | Ad sets not imported | **build+connector** | Meta ad set import; rule as for keywords |
| Button «Limit audience» | Removes the tip; toast | A write: pause the lookalike ad set (`ads_management`) | — | **needs-decision** (D-GR3-1) | Write path; a lookalike built from a customer list also falls under D-GR3-4 |
| Tip (Webinar) «Invite non-converting webinar attendees into the «Webinar follow-up» email campaign.» + «Enroll» | Literal | Who attended (people), who did not convert, and a sequence to start for them | No attendee source. The engine's «Added to a list» trigger is unavailable (V-SGR-17), but `app.wf_start` can start a person's run | **needs-decision** (D-GR3-7) | Once attendees are a CRM list: a new `simple_sequence_enroll(sequence, segment)` that starts a run per person on the list who is not paying and is not unsubscribed (D-27), with Deals/Campaigns › Manage workflows rights. Not shown before then |
| Tip (Newsletter) «Send Tuesday 08:00 — your best open-rate slot.» + «Set time» | Literal | The best send slot (heatmap below) and the newsletter's email campaign | Best slot: computable. Link to the email campaign: none | **needs-decision** (D-GR3-8) | Then **build**: `campaign_schedule` on the linked, still scheduled email campaign at the next best slot. Hidden while the best time is «—» |
| Tip removed after «apply» | Local state `applied` | — | — | **build** | Only after a real, accepted change. A dismissed tip is remembered per staff member and tip key (small table, or `localStorage` for per-viewer convenience) |
| Toast «<cta> · applied via <channel> API» | Always claims success | The platform's answer | — | **cannot** | While Sentral is read only, a toast claiming a platform change would be fabricated. With a write path: the platform's real outcome («Paused in Google Ads», or the refusal as a code in words) |

### Elements already built (unchanged by this design)

| Element | Today | Verdict | Note |
|---|---|---|---|
| Totals line: Spent of budget, Visits, Signups, Cost per signup | `ad_campaigns_get` | *built* | **Signups reads product attribution Orgpuls does not send (R-1)**; follow D-GR3-2 |
| «＋ New campaign» and its modal: name, channel, budget, starts, ends, landing path, preview link, Cancel, Create | `ad_campaign_save` | *built* | V-SGR-10, V-SGR-11 |
| Campaign table: name, channel, status pill, spent, signups, per signup, row selection | `ad_campaigns_get` | *built* | Signups as above |
| Card header: channel · dates, name | — | *built* | — |
| Pause / Resume / Launch now / Duplicate | Changes the record only; disabled for a platform-linked campaign, which follows the platform (V-SGR-13, V-GR2-43) | *built* | With the write path (D-GR3-1) a platform-linked campaign's Pause/Resume could become real (`campaign.status` on the platform) |
| Stats: Visits, Signups, Conversion, Per signup | Tracker visits; product signups | *built* | Signups as above |
| Budget used | Spent ÷ budget | *built* | — |
| Tracking link, «Copy link», the note | `trackingUrl` | *built* | — |

---

## Tab: Email and automation › Email campaigns (view `email`)

Today's screen: `EmailTab` in `Email.tsx` on `simple_sequences_get` (0059). The two new cards go in a grid under the editor
(`repeat(auto-fit, minmax(min(100%,420px),1fr))`), for the selected sequence.

### New elements

| Element | Design behaviour | Data needed | Today | Verdict | Needs |
|---|---|---|---|---|---|
| Card title «Results per step · <name>» | The selected sequence's name | — | — | **build** | — |
| «Last 30 days» | Literal | Sends in the last 30 days | — | **build** | The window filters on `campaign_recipients.sent_at` |
| Column header: Email, Sent, Open, Click, Unsub., Signups | Static | — | — | **build** | i18n keys |
| Row per email step: subject | The step text | The email step's subject | `simple.steps[].text` and `campaign_id` | **build** | One row per email step in order; the step card's own figures stay all-time, so the two figures will differ by design (both labelled) |
| Sent | `enrolled × 3 − i × 30` | Sends in 30 days | `campaign_recipients` (state not queued or skipped, `sent_at` in the window) | **build** | New read `simple_sequence_results(p_id, p_days)` with `app.campaign_reports_ok` per email (another person's campaign needs Campaigns › See reports of others, as today) |
| Open % (red under 45 %) | A fixed array, minus 6 when the subject is long | Unique human opens ÷ delivered, in the window | `first_open_at` (prefetch excluded) and `delivered_at` | **build** | «—» when tracking is off (`campaign_stats`' rule) or nothing was delivered. Red under 45 % as drawn. A hint says Apple's proxy opens are not counted, so the rate is lower than the provider's |
| Click % (red under 10 %) | A fixed array | Unique clicks ÷ delivered | `first_click_at` | **build** | As for Open |
| Unsub. % | A fixed array | Unsubscribes ÷ delivered | `unsubscribed_at` | **build** | — |
| Signups (green) | `sent × click × 0.3` | Signups this email brought | Tracker sessions carrying the email's `utm_campaign` that completed signup. `campaign_stats.signups` (product last touch) is empty in production (R-1) | **needs-decision** (D-GR3-2) | Recommended: the tracker's completed signups from the email's links in the window. For a sequence whose people are already customers, «Signups» means little; Tor may prefer «Became an account»: the recipient's organisation got an `account_products` row after the send, a CRM join with no respondent data |
| An email that sent nothing | Rates printed over 0 sent | — | — | **build** | Sent «0», rates «—», signups «—». The design prints rates, which would be fabricated |
| Tip text «Email 2 has a 9 % click rate — test a shorter subject with the employee count, e.g. «Last opp 48 ansatte på 2 minutter».» | The same literal on every sequence | The email's click rate and delivered count | Computable from the read above | **build** | Rule: click rate under 10 % with ≥ N delivered in 30 days; the email's number and rate are real. **No example subject**: «Last opp 48 ansatte …» is invented copy. A proposed subject is either typed by the person or drafted by Claude (**build+connector**: the `ai` integration exists, `not_connected`; the subject alone goes to the model, no personal data) |
| Button «Create A/B test» | Removes the tip; toast «Create A/B test · done» | An A/B subject on an automated email | **Refused by the schema**: `campaigns` checks `subject_b is null or type <> 'automated'`. The broadcast A/B (a test share, wait, winner) does not fit a stream of sends | **needs-decision** (D-GR3-5) | Then **build**: relax the check for `automated`; assign variants alternately at enqueue until each has N delivered, pick the winner by `ab_metric`, then send only the winner (`ab_winner`, `ab_decided_at` exist); mail-run already chooses the subject by variant; the editor gets a field for subject B and shows A and B in Results per step |
| Tip text «Add a condition after email 1: if the account already uploaded employees, skip email 2.» | Literal | Whether the email after the first goes to organisations whose `employees_uploaded` milestone is already reached | `org_milestone(org, 'employees_uploaded')` exists (0059); the share of recipients already past it is computable from `activation_milestones` | **build** | Rule: shown when a sequence has an email after the first, no milestone condition before it, and ≥ N % of its recipients in 30 days were already past the milestone when it was sent (the share printed). Applies to records with an organisation (deals, leads) |
| Button «Add condition» | Removes the tip | Insert «skip the next email if the employee list is uploaded» after email 1 | The simple model's conditions **end** the run (V-SGR-20). The engine has `if_else` with converging branches, which can express «skip» | **build** | A new simple step kind `skip` {cond} compiled by `simple_sequence_save` into `if_else` (then: [], else: [next email]); the editor shows it as «If … skip the next email». The button writes through `simple_sequence_save` (same rights) |
| Tip text «Wait steps send at signup time; switch to «send at best time» (Tue–Thu 08:00).» | Literal | Whether the sequence's sends cluster outside the best window, and the best window itself | The send hours are in `sent_at`; the best window comes from the heatmap read | **build** | Shown only when the best time is known (not «—») and the sequence has no send window yet; the window printed is the computed one |
| Button «Use best time» | Removes the tip; toast «… · done» | A send window on the sequence's emails | **The engine's delay has no time of day** (`wf_delay_until`: amount, unit, skip_weekends) | **build** | Engine change: delay config `window {days: [1..7], hour: 0..23}` (Europe/Oslo); `wf_delay_until` waits to the next slot inside the window after the amount; `simple_sequence_save` takes `send_window` and adds the window to every wait before an email (and a zero-day wait before a first email only per D-GR3-6). The same state as «Send all steps at the best time» (one switch, not two) |
| Toast «<cta> · done» | Always | What really changed | — | **build** | Says what was saved («Email 2 is skipped when the employee list is uploaded»), or the refusal |
| Card title «Best time to send», «Open rate by weekday and hour» | Static | — | — | **build** | — |
| Heatmap, 7 weekdays × 12 hours (06–16, 20) with four fills (`#F2EAD6`, `#CFE7E4`, `#9DB8B3`, `#2F5D2A`) | A formula, the same for every sequence | Open rate by **send** weekday × hour (Europe/Oslo): human opens ÷ delivered, over the product's email campaigns the viewer may see reports for | `campaign_recipients.delivered_at`, `first_open_at`, `campaigns.product`. Locally 640 sends, all in one hour (one broadcast) | **build** | New read `email_send_times(p_product, p_days)`. Fills are bands relative to the best cell. A cell under the minimum (for example 20 delivered) gets an **empty treatment**, not «low» (a low fill would be fabricated): a deviation. Sends outside the 12 columns are counted in a line under the grid. Window, scope and minimum per D-GR3-6. Scrolls inside the card under 640 px (V-SGR-27) |
| Best cell's yellow border (`2px solid #F5C64A`) | Tue 08 always | The best cell with enough sends | — | **build** | No border while no cell qualifies |
| Cell tooltip «Tue 08:00 · 54 % open» | Formula | The cell's rate and sends | — | **build** | «Tue 08:00 · 54 % open · 212 delivered»; «too few sends» under the minimum. `aria-label` per cell; the grid is a `table` for screen readers |
| Legend low / medium / high | Three swatches for four fills | — | — | **build** | As drawn (the design's inconsistency is kept and logged) |
| «Best: Tue 08:00 (54 %)» | Literal in the markup | The best qualifying cell | — | **build** | Computed; «Best: —» until a cell has enough sends |
| Button «Send all steps at the best time» → «✓ Sending Tue–Thu 08:00», toast «Steps now send Tue–Thu at 08:00» | Local state; no step changes | The window the steps will use, then the same engine switch as «Use best time» | Engine has no window | **build** | The label states the computed window. The window rule (the best hour, and the weekdays whose rate at that hour is within x points of the best) and whether the first email waits for it are D-GR3-6. Disabled with a reason while the best time is «—», while the sequence cannot be edited (V-SGR-25), or for a draft with no email |

### Elements already built (unchanged by this design)

| Element | Today | Verdict | Note |
|---|---|---|---|
| «＋ New email campaign» | `simple_sequence_save` | *built* | V-SGR-16 |
| Sequence list: name, state, steps, enrolled, opens | `simple_sequences_get` | *built* | V-SGR-22, 23 |
| Name field, Pause / Activate | — | *built* | Activation blocked with a reason |
| Starts when, Send to list, Stop when | — | *built* | V-SGR-17, 18, 19: the design's sequences use the trial triggers that are unavailable |
| Step cards with «Sent · opened · clicked» per email | `campaign_stats` per email, all-time | *built* | — |
| ▲ ▼ × and «＋ Email / Wait / Condition / Task for sales» | — | *built* | Only the padding changed (`4px 0 14px`) |

---

## Shell: `Sentral Simple.dc.html` diff

| Element | Design | Verdict | Note |
|---|---|---|---|
| Rail item «Development · Roadmap, bugs, releases» (code icon), fifth and last | New | (dev evaluators) | Not Growth |
| `<dc-import name="DevHub">` between Growth and Platform, with no go, product or tab | New | (dev evaluators) | Not Growth |
| Anything for Growth | — | — | No change: Growth's rail item, tabs and imports are as before |

---

## Proposed database objects

All are in schema `app` or `public`, `security definer`, `search_path = ''`, zod-parsed in the app. New tables have RLS enabled,
no policy, and `revoke all from public, anon, authenticated` in the same migration (rule 1), plus a test in
`supabase/tests/simple_growth_invariants.sql`.

| Object | Kind | Rights | Purpose |
|---|---|---|---|
| `public.ad_campaign_detail(p_campaign uuid, p_days int default 21)` | read | `app.require('campaigns','see')`; figures as `ad_campaigns_get` (own, or Reports on others' / Edit others'); grant `authenticated` | The days (spend by currency from `ad_daily` for platform-linked campaigns; visits and signups per D-GR3-2), `spend_source` (`platform`, `typed`, null), ads (name, headline, status, clicks, spend, conversions, signups), keywords and ad sets once imported, bidding strategy, and the figures each tip rule needs. The tips themselves are a pure TypeScript function over this answer (vitest), so their texts live in `messages/` |
| `app.ad_platform_keywords` | table | none (RLS, no policy) | account_id, campaign_external_id, ad_group_external_id, criterion_id, text (≤ 80), match_type, status, cpc_bid_micros, updated_at; unique (account_id, ad_group_external_id, criterion_id) |
| `app.ad_keyword_daily` | table | none | account_id, ad_group_external_id, criterion_id, day, impressions, clicks, spend, conversions. A separate key, because a criterion id is unique only within its ad group and `ad_daily.external_id` is one number |
| `app.ad_platform_adsets` (+ `ad_daily.level` gains `adset`) | table, check change | none | Meta ad sets: id, campaign, name, status |
| `ad_platform_campaigns.bidding` | column | — | Google `bidding_strategy_type` (gates «Raise bid») |
| `public.worker_ads_import(…, p_keywords jsonb default null, p_adsets jsonb default null)` | worker, `service_role` | — | Extended with optional parameters (expand → migrate → contract; the old signature is retired, never dropped) |
| `public.simple_sequence_results(p_id uuid, p_days int default 30)` | read | `require_staff` plus `campaign_reports_ok` per email; `authenticated` | Per email step: sent, delivered, opens, clicks, unsubscribes, signups (D-GR3-2), and the inputs of the three email tips (milestone share, send-hour spread). It could instead be a `results` key on `simple_sequences_get`, but a separate read keeps the list fast |
| `public.email_send_times(p_product text, p_days int default 90)` | read | Campaigns › See; only campaigns whose reports the caller may see | 7 × 24 cells {dow, hour, delivered, opened} in Europe/Oslo, the minimum per cell, the best cell and the derived window |
| `app.wf_delay_until(…, p_window jsonb)` (new overload) and the delay config `window` | engine | — | The next slot inside {days, hour} after the delay. The old function stays for existing delays |
| `simple_sequence_save`: `send_window`, the step kind `skip` | engine and editor | as today | Compiles the window into every wait before an email; `skip` into `if_else` |
| `campaigns` check change, plus `ab_target int` | schema | — | Allows `subject_b` on `automated` (D-GR3-5); `ab_target` = delivered per variant before a winner |
| `public.simple_sequence_enroll(p_id uuid, p_segment uuid)` (after D-GR3-7) | write | Deals and Campaigns › Manage workflows | `app.wf_start` for each person on the list who is not paying and not suppressed; returns the count started; `app.log` with counts only |
| `ad_campaigns.email_campaign_id uuid references app.campaigns` (after D-GR3-8) | column | via `ad_campaign_save` | The newsletter's email campaign, for «Main CTA» rows and «Set time» |
| **Only after D-GR3-1:** `app.ad_changes` | table | none | id, provider, account_id, level (keyword, ad, adset, campaign, budget), external_id, action (`pause`, `enable`, `negative_keyword`, `set_bid`, `set_budget`), `before`/`after` jsonb (bids and budgets, not personal), requested_by, state (`requested`, `applied`, `failed`), code, platform request id, created_at, applied_at |
| **Only after D-GR3-1:** `public.ad_change_preview(p_kind, p_target, p_args)` and `public.ad_change_request(…)` | write | The owner, or a new right Campaigns › Change ad platforms; `app.require_fresh_mfa(10)`; limits (for example a bid change of ±25 % at most, a budget move ≤ the amount on the platform) | Records the change and calls `ads-command`; the answer is the platform's |
| **Only after D-GR3-1:** `worker_ad_change_result(p_id, p_ok, p_code, p_request_id)` | worker | `service_role` | The outcome, then a re-import of the account so the figures show the platform's state |

## Proposed edge functions and connectors

| Function / connector | Change | Credentials | Verdict |
|---|---|---|---|
| `ads-run` (Google Ads) | Add a `keyword_view` query (criterion id, text, match type, status, ad group, `effective_cpc_bid_micros`, daily impressions, clicks, cost_micros, conversions) and `campaign.bidding_strategy_type`. **Never `search_term_view`** | Existing read-only service account and developer token | build+connector |
| `ads-run` (Meta) | Add `act_<id>/adsets` (id, name, campaign_id, effective_status) and insights `level=adset` | Existing `ads_read` token | build+connector |
| `ads-run` (LinkedIn) | Nothing new: campaigns and creatives are imported | — | — |
| `mail-run` / the campaign dispatcher | Assign A/B variants for automated sends until `ab_target`, then the winner (after D-GR3-5) | Brevo (built) | build |
| Claude API (optional) | Draft a B subject from the A subject only, with no recipient data (after D-GR3-5) | The `ai` integration through secret-intake (D-07 names Claude) | build+connector |
| **`ads-command` (new, only after D-GR3-1)** | The only writer to ad platforms: reads `ad_changes`; a `validate_only` dry run first (Google); then the mutation; logs codes and counts, never a body | **Separate write credentials in Vault**, so read and write can be revoked apart. Google: a service-account user with *Standard* access, and a developer token whose access level permits production mutates. Meta: a system-user token with `ads_management` (app advanced access where the ad account is not the app's business), with `appsecret_proof`. LinkedIn: a new sign-in through `ads-oauth` with `rw_ads` (Advertising API write access must be approved for the app; `rw_dmp_segments` for D-GR3-4) | needs-decision |

**What a write path needs, per tip:**
- **«Pause keyword».** Google `AdGroupCriterionService.MutateAdGroupCriteria` (status PAUSED). The negative keyword is a
  `CampaignCriterionService` create (negative=true). That is two operations; the second failing leaves the first applied,
  reported as such.
- **«Raise bid».** The same service with `cpc_bid_micros`, only where `bidding` is MANUAL_CPC or ENHANCED_CPC. Otherwise it is
  refused before the call.
- **«Move budget» (LinkedIn).** `adCampaigns` partial update of `dailyBudget` on two campaigns. It is not atomic: lower the source
  first, then raise the target, and restore the source if the second fails.
- **«Limit audience» (Meta).** `POST /<adset_id>` status=PAUSED.
- **«Add exclusion» (LinkedIn).** A DMP segment from hashed addresses: D-GR3-4 first.
- **Pause / Resume of a platform-linked campaign.** It becomes real by the same path (campaign status).

Every write has a confirmation that shows the exact before and after values, and a fresh second factor. It goes into
`app.audit` through `app.log` (kinds and ids; bids and budgets are not personal). Nothing is ever applied automatically. The
toast says what the platform answered.

## Orgpuls commands and events needed

- **None are required** if signups come from Sentral's own tracker (D-GR3-2, recommended).
- **Optional, if Tor wants product-confirmed signups** per campaign, ad, keyword or email (accounts, and later paying): this
  is **needs-orgpuls**, and it is more than a registry line.
  - Orgpuls's `platform_event_kinds` lets `org.attribution` carry only `heard` (Orgpuls 0206).
  - The same migration **dropped Orgpuls's own `org_attribution` and `web_events`** (site analytics left Orgpuls for the
    platform's tracker), so Orgpuls no longer has the touch to send.
  - A route would be for the signup to carry the platform tracker's session reference (for example a short-lived, signed token
    the tracker hands the page). Orgpuls would pass it on in `org.attribution`, and Sentral would resolve it to the session's
    utm. The tracker is cookieless (D-37) and stores nothing on the device, so this needs a privacy review (ekomlov § 3-15)
    before it is designed.
  - It would also fix R-1 for the existing Signups figure.
- The «employees uploaded» condition uses `activation_milestones`, which the product already reports. Nothing new is needed.

## Product decisions for Tor

| ID | Decision |
|---|---|
| D-GR3-1 | **May Sentral change ad platforms?** 0077 was built read only on purpose (V-GR2-42/44). If yes: which actions (pause or enable a keyword, ad, ad set or campaign; add a negative keyword; change a keyword bid; change a campaign budget), who may (the owner only, or a new Campaigns › Change ad platforms right; always with a fresh second factor), what limits (the largest bid change, the largest budget move per day), and the platform access to grant again (Google user *Standard*, Meta `ads_management`, LinkedIn `rw_ads`, which needs LinkedIn's approval and can take weeks). If no: the tips stay as advice with a disabled button and a one-line reason, and Pause/Resume of platform-linked campaigns stays off |
| D-GR3-2 | **What «signups» means** on a campaign's day bars, an ad or keyword row, an email row, and (R-1) the existing campaign Signups. Options: (a) the tracker's completed signups carrying the utm (recommended: live now, cookieless, the same source as SEO's organic signups V-GR2-24); (b) the platform's conversions (ad channels only, as each platform counts them); (c) product-confirmed accounts (needs Orgpuls and a privacy review, above; not soon). For email, also (d) «became an account»: the recipient's organisation created an account after the send |
| D-GR3-3 | **The tracking-template convention on the ad platforms**, so signups can be credited to a keyword or ad: Google `utm_term={keyword}&utm_content={creative}`, Meta `utm_content={{ad.id}}`, LinkedIn's creative-id dynamic UTM. Someone sets these in each platform; Sentral can show whether sessions carry them |
| D-GR3-4 | **Uploading CRM lists to ad platforms** (exclusions, lookalikes): the addresses of customer users, hashed. V-GR2-45 stands until Tor decides (GDPR purpose and basis; never respondents) |
| D-GR3-5 | **A/B tests on automated emails:** how a test ends (N delivered per variant, the metric, then the winner for everyone), and whether Claude may draft subject B |
| D-GR3-6 | **Best time to send:** the window (90 days suggested), the scope (all of the product's email, or this sequence once it has enough), the minimum sends per cell (20 suggested), how «Tue–Thu 08:00» is derived from the cells, and whether the first email (sent when the trigger fires, for example a welcome) also waits for the window |
| D-GR3-7 | **Where webinar attendees come from** (a CRM list imported by hand, a form, or a webinar tool connector) before «Enroll» is built |
| D-GR3-8 | **Link a Newsletter marketing campaign to its email campaign** (one to one), for «Main CTA» and «Set time» |
| D-GR3-9 | **The tips' thresholds** (a keyword ≥ 3× dearer per signup, a minimum of clicks and signups, red cost per signup at the design's 900 kr or relative to the campaign), or accept the builder's stated rules logged in the deviations, as Growth v2 did (V-GR2-34) |

## Risks against the rules

| ID | Risk | Rule | Mitigation |
|---|---|---|---|
| R-1 | **An existing figure is not real.** The campaign «Signups» (totals line, table, stat; `ad_campaigns_get`) counts `account_products.attribution` utm_campaign, which Orgpuls does not send (only `heard`), so production shows **0 as if real**. `campaign_stats.signups` for email has the same source | Never fabricate | Decide D-GR3-2 first. Until then, «—» when no account of the product has a source (`app.has_source`, 0074), not 0. To be verified on the hosted project with a SELECT |
| R-2 | Fabricated daily spend: pro-rating typed monthly spend to days, or drawing bars before the start or while paused | Never fabricate | Daily spend only from `ad_daily`; otherwise no spend bars and the line says why |
| R-3 | A per-row cost from allocating campaign spend by clicks (as the design does) | Never fabricate | Each row's own imported spend |
| R-4 | A toast or a vanished tip claiming a platform change that did not happen | Never fabricate | No apply without the write path; with it, the platform's answer decides |
| R-5 | Importing search terms (what people typed) | Rule 6 spirit; logs carry no payload | Keywords only (advertiser text); `ads-run` logs counts and codes |
| R-6 | Uploading customer users' addresses to LinkedIn or Meta (exclusion, lookalike) | Personal data (rule 6 covers respondents; these are customer contacts, but a decision is needed) | Not built before D-GR3-4 |
| R-7 | A write path is Sentral spending money: a stolen session could pause campaigns or raise bids | Rules 2 and 5 | aal2 plus a fresh second factor per change, a narrow right, limits, preview and confirm, audit; separate write credentials in Vault through secret-intake / ads-oauth, never through a person; `ads-command` is the only writer |
| R-8 | Rates over tiny samples (0 or a few sends) shown as findings: the heatmap cells, the email tips | Never fabricate | «—» under a minimum; tips need N delivered; the empty treatment for thin cells |
| R-9 | Open rates confounded: automated emails go at trigger time, broadcasts in one hour, so a cell's rate partly reflects who is mailed when | Honesty | A one-line note under the heatmap; best time only from cells with enough sends |
| R-10 | Time zone and currency mismatches: platform days in the account's time zone, the tracker in Europe/Oslo; non-NOK accounts | Never fabricate | Say the account's time zone when it is not Oslo; never convert currency (V-GR2-43) |
| R-11 | The engine change (send window) touches every workflow's delays | Rule 7 (migrations); engine correctness | A new overload and an opt-in `window` key; existing delays unchanged; SQL tests for a window across weekends and the DST change |
| R-12 | 390 px: the heatmap collapses, and the ads grid squeezes the name to nothing | Definition of done (phone-usable) | Scroll inside the card; a minimum width for the grid (V-SGR-27 pattern) |

Product rule 3 (`product-command`) and rule 4 (events) are not touched: ad platforms and Brevo are external connectors of this
project, not products.

## Suggested build order

| Wave | Content | Depends on | Size |
|---|---|---|---|
| 0 | R-1: decide D-GR3-2; switch the campaign Signups (and email signups) to the chosen source, or «—» without a source | D-GR3-2 | S (½ day) |
| 1 | `ad_campaign_detail`. Daily bars (platform spend, tracker visits and signups), the click-a-day line, honest states for typed spend and no platform, ad rows with their own spend and cost per signup, the LinkedIn creative tip text (advice only, button disabled with the reason) | 0 | M (1–1½ days) |
| 2 | `simple_sequence_results` and `email_send_times`: Results per step (30 days), the heatmap with empty cells, Best label, the three email tip texts by rule | 0 | M (1 day) |
| 3 | Engine send window and the `skip` step: «Use best time», «Send all steps at the best time», «Add condition» | 2, D-GR3-6 | M (1–1½ days, mostly SQL tests) |
| 4 | Google keywords and Meta ad sets import (`ads-run`, tables, `worker_ads_import` optional parameters); keyword and ad-set rows and their tip texts | 1, D-GR3-3 for keyword signups | M (1 day) |
| 5 | A/B on automated emails (check change, dispatcher, subject B field, Results per step A/B), and optionally a Claude-drafted subject | D-GR3-5 | M–L (1½–2 days) |
| 6 | `simple_sequence_enroll` and «Enroll»; the newsletter link and «Set time» | D-GR3-7, D-GR3-8 | S–M (1 day) |
| 7 | The write path: `ad_changes`, preview and confirm with a fresh second factor, `ads-command` for Google (pause, negative, bid), Meta (pause ad set) and LinkedIn (budget), re-import after each change, the tips' buttons and Pause/Resume of platform-linked campaigns | D-GR3-1 (and platform approvals) | L (3–5 days, plus external approval time) |

Each wave ships the usual way: the migration first, then the functions, then the UI; en and no messages; deviations logged
(the empty heatmap cell, the hidden ads block, hidden column headers, no example subject, disabled apply buttons); the pixel
check at 1440 and 390 px against the screens listed above.
