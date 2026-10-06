# Database requests — Analytics

Changes the Analytics screen needs that a screen builder may not make (no migrations in phase B). The
screen ships without them, as noted in `deviations/analytics.md`. The zod schemas in `lib/data/analytics.ts`
already accept the optional fields named here, so the screen picks them up when they arrive.

| Request | Status |
|---|---|
| R-1 NOK only | Done — 0034: `snapshot_mrr` sums NOK (so `mrr_daily`, `v_mrr_monthly`, `mrr`/`mrr_prev`); `v_net_new_mrr` and `v_revenue_churn` leave out tenants whose subscription is in another currency (metric definitions version 2); `bands.mrr`, `churn.mrr_lost`, attribution `mrr` and the forecast's subscriptions sum NOK; `analytics_business.excluded_currency` and `analytics_attribution.excluded_currency` count the paying subscriptions left out. `marketing_spend` already stores its currency and `analytics_set_spend` can only write NOK (it takes no currency), so nothing is refused: each `spend` row now returns `currency` and a channel's `spend` sums NOK only |
| R-2 first snapshot is a baseline | Done — 0033 (the baseline); 0034 returns `first_snapshot` (date, the earliest `mrr_tenant_daily` day in scope) from `analytics_business` and `analytics_retention` |
| R-3 activation medians | Done — 0034: `first_send_median_min` (survey_sent − account_created) and `paid_median_min` (converted − account_created) for the cohort. Open: the optional `p_days` variant — it changes the function's signature and the cards are answered by the cohort |
| R-4 retention and churn | Done — 0034: a logos cell with no snapshot for the cohort that month is null; `churn_by_month[].paying_start` (paying subscriptions in the last daily snapshot before the month, null without one) and `mrr_lost` (NOK); `analytics_business.churn.paying_start` (same day as `mrr_prev`); new read `analytics_churns(p_product, p_days)` → `{churns: [{product, tenant_id, organization_id, organization, churned_at, mrr_lost, currency, payment_failure, reason}], reasons: [code]}`, whose `churned_at` is what `analytics_set_churn_reason` takes |
| R-5 usage | Done — 0034: `counts_by_product`, `response_rate.all`, `counts_delta` ({metric: change over the range from `product_counts_daily`}; null for a metric while a tenant that existed before the range has no count from its start). Open: feature adoption per organization — there is no registry of feature-use keys and Orgpuls sends none |
| R-6 customers by size | Done — 0034: `analytics_business.by_size` ({key: band label, count}), the same customers as `by_industry`, banded by the price list's employee bands (the product's own, else another product's); `''` = employees unknown or outside every band |
| R-7 web | Done — 0034: `channels[].bounce` and `channels[].signups` (signups by the signup's attributed channel), `campaigns` [{campaign, sessions, signups, paid}] by `utm_campaign` (sessions null while nothing was tracked in the period), `daily[].signups`, `search[].position` (Search Console's position weighted by impressions; empty until Search Console is connected and reports). Open: signups per session or landing page (the daily salt leaves no key between a session and a signup, and the attribution carries no landing path); the funnel's second step (no page-path rules decided); `signup.lookup_failed` (no source); the bot filter (the tracker's edge function does not exist, and `worker_web_ingest` in 0031 has none) |
| R-8 attribution | Done — 0034: the channels of the period's spend appear even without signups. Open: the journey of a paying customer — not built here: consent is recorded by the capture work (0031, written in parallel), so the read belongs after it; touches, milestones and the paid date exist and would be combined there |
| R-9 who may read web analytics and attribution | Done — 0034: `analytics_web` and `analytics_attribution` accept `campaigns:reports_others` or `global:reports_others`. The Marketing preset itself does not hold `campaigns:reports_others` (jonas has `see, add, edit_others, export, ai` on campaigns), so an admin grants it in Settings › Permissions |

## R-1 NOK only, and say what was left out
`app.sub_mrr` ignores `subscriptions.currency`, so `analytics_business` (mrr, mrr_prev, bands, arpa),
`analytics_attribution` (mrr), `v_mrr_monthly` / `mrr_daily` and the movements sum amounts in any currency.
Today every subscription is NOK, so nothing is wrong yet. Restrict the sums to `currency = 'NOK'` and
return `excluded_currency` (count of subscriptions in scope left out) from `analytics_business` and
`analytics_attribution`, as `report_run` does in 0024. The screen renders the line
«N subscriptions in other currencies than NOK are left out of the sums» when the field is above zero.
`marketing_spend.currency` likewise: return it in `spend`, or refuse non-NOK in `analytics_set_spend`.

## R-2 The first snapshot is a baseline, not new MRR
`snapshot_mrr_tenants` compares today with «the last snapshot before the month began»; on the first run
there is none, so every paying subscription becomes a `new` movement (today: 31 350 kr «new» in October
2026, the whole MRR). Suggested: skip movements for a tenant whose first `mrr_tenant_daily` row is in the
current month *and* was written by the first run (or seed one baseline snapshot dated the day before the
month from `mrr_daily`). Also return `first_snapshot` (date) from `analytics_business` and
`analytics_retention`, so the screen does not have to infer it from the earliest movement month.

## R-3 Activation medians the cards need
`analytics_activation` returns the median time between consecutive steps only. The design's hero
«Promise on the site — median time from signup to first survey sent» and «Signup → paid — median for
converted orgs» need medians from `account_created`:
`first_send_median_min` (survey_sent − account_created) and `paid_median_min` (converted − account_created),
for the cohort. Optionally `p_days` to compute the hero over the range instead of one cohort.

## R-4 Retention: no figure is not zero; logo churn as a rate
- In `analytics_retention`, logos mode returns `0` for a month with no `mrr_tenant_daily` row for the
  cohort (before the first snapshot); revenue mode returns null there. Return null in logos mode too.
- `churn_by_month` has logos only. Add `paying_start` per month (paying subscriptions at the start of the
  month) so logo churn can be shown as the design's percentage, and `mrr_lost` per month.
- `analytics_business.churn` counts logos in the range; add `paying_start` for the period so the Logo churn
  KPI can be a rate (today the screen shows the count).
- A list of churns (`product, tenant, organization name, churned_at, mrr_lost, reason code`) so staff can set
  the reason with `analytics_set_churn_reason` — today there is no read that names a churn, so the setter
  cannot be reached from the screen.

## R-5 Usage per application and over the period
- `analytics_usage.counts` merges every product's latest counts into one object. Return
  `counts_by_product` ({product: {metric: value}}) for «Usage across applications» under All applications.
- `counts` are latest totals, not the period's; tiltak created «· month» needs the delta over the range from
  `product_counts_daily`.
- `response_rate.all` (Σanswered ÷ Σinvited over both kinds) — the screen cannot weight main and pulse.
- Feature adoption per organization: no registry of feature-use keys exists (spec §2, `product_metric_defs`).

## R-6 Customers by size
`analytics_business` has `by_industry` and `by_fylke` over all active customers, but size only as `bands`
(paying subscriptions). Add `by_size` (customers by employee band, same population as the other two).

## R-7 Web: per-source and per-campaign figures
- `channels` returns sessions only; the design's Sources table also has bounce, signups and conversion.
  Signups per channel need the session→signup join (same day's hash) or the signup's attribution channel.
- `landing` has sessions and bounce; the design shows signups and conversion per page.
- Campaign visits, signups and paid per `utm_campaign` (web_sessions.utm × account_products.attribution ×
  confirmed_at), to fill the Campaigns table and cost per paid.
- `daily` signups, for the dashed «Signups (× 20)» line.
- The website funnel's second step (pricing or platform page) needs page-path rules; and
  `signup.lookup_failed` (failed Brønnøysund lookups) has no source.
- `search` lacks the average position.
- The tracker's edge function does not exist yet; `worker_web_ingest` has no bot filter, so the banner no
  longer says «bots filtered».

## R-8 Attribution
- Channels that have spend but no signups in the period do not appear (the spend is only joined to channels
  with signups), so wasted spend is invisible. Union the channels of `marketing_spend`.
- «Journey of a paying customer»: a read per organization of first touch, last touch, consent, activation
  milestones and paid date (spec §2 Attribution). Without it the card is left out.

## R-9 Who may read web analytics and attribution
Every analytics read requires `global:reports_others`, so Marketing (jonas) cannot open Web analytics or
Attribution, and cannot reach the spend input that `analytics_set_spend` allows them
(`campaigns:reports_others`). Suggested: `analytics_web` and `analytics_attribution` accept
`campaigns:reports_others` as well.
