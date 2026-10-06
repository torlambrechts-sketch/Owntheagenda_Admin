# Database requests — Analytics

Changes the Analytics screen needs that a screen builder may not make (no migrations in phase B). The
screen ships without them, as noted in `deviations/analytics.md`. The zod schemas in `lib/data/analytics.ts`
already accept the optional fields named here, so the screen picks them up when they arrive.

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
