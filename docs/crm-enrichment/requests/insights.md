# Database requests — Insights

Changes the Insights screen needs and leaves out until they exist. Each names the function and the behaviour.
Nothing here blocks the screen: where a request is open, the screen shows the honest state named in
`docs/crm-enrichment/deviations/insights.md`.

## R-INSIGHTS-01 — «Stage conversion» on the role templates
The design's dashboard draws «Stage conversion · Last 90 days» as a table. `app.report_conversion` computes it,
but none of the sixteen template tiles in 0024 uses it, so no dashboard shows it (the builder offers it as the
Conversion report type). Proposal: add a template report
`{"entity":"deal","type":"conversion","pipeline_id":<New business>,"period":{"kind":"last_90"},"chart":"table"}`
named «Stage conversion» (span 4) to `default` and `sales_manager`, looking the pipeline up by name in the
migration. Deviation V-INSIGHTS-06.

## R-INSIGHTS-02 — template tiles carry a key, so their names can be translated
Template report names are stored English text («Won value · this quarter»), so a bokmål user reads English
tile titles on the four templates. Proposal: `reports.template_key text` (e.g. `won_quarter`), seeded for the
sixteen template reports, returned by `dashboard_get` per tile as `template_key` (null for a staff member's
own report). The screen then renders `insights.templateTiles.<key>` and falls back to the stored name.
Deviation V-INSIGHTS-30.

## R-INSIGHTS-03 — «Deals per stage» on one pipeline
The template «Deals per stage» groups open deals by stage over every pipeline, so one chart mixes the stages of
New business, Expansion and Public sector (thirteen columns, ordered by `stages.ord` across pipelines). The
design shows one pipeline («New business · progress»). Proposal: add the filter
`{"f":"pipeline_id","op":"eq","v":<New business>}` to that template report (and to «My open pipeline» on
`sales_rep`), or order the stage dimension by pipeline first (`(p.ord, s.ord)`). Deviation V-INSIGHTS-05.

## R-INSIGHTS-04 — lost reasons normalised
«Lost reasons» groups `deals.lost_reason`, which is free text: «Price» and «price» or a typed variant become
separate slices. Proposal: a report dimension `lost_reason` that maps the text to `lost_reasons.label`
(case-insensitive) and puts anything else under one «Other» key, as the spec (§1) describes.

## R-INSIGHTS-05 — Progress and Products report types
`app.report_check` accepts `progress` and `products`, but `app.report_run` computes them exactly as
`performance`, so the builder offers them disabled («not available yet») rather than show a performance report
under another name. Proposal: `progress` = deals that entered a later stage in the period
(`deal_stage_history`, grouped by the stage reached); `products` = `deal_items` of won deals grouped by
catalog item, measure count, quantity or line value (NOK). Deviation V-INSIGHTS-18.

## R-INSIGHTS-06 — «does not contain» in `app.filter_sql`
The spec's filter tree includes *does not contain*; `app.filter_sql` has `contains` but no negation. Proposal:
`op = 'ncontains'` → `coalesce(col::text, '') not ilike '%v%'`. The builder adds it to its operator list once it
exists. Deviation V-INSIGHTS-21.

## R-INSIGHTS-07 — the deal forecast says what it leaves out
`forecast_deals` sums NOK deals only (`best`, `weighted`) but counts every currency in `count`, and returns no
`excluded_currency`, so the screen cannot say that a deal in EUR is missing from the bars (Phase 4 brief: rows
in other currencies are reported, «so say so»). Its `undated` count also skips the sandbox filter the month
counts apply (`d.is_sample = (select sandbox …)`), so a staff member outside the sandbox sees sample deals
counted as undated. Proposal: return `excluded_currency` (open deals in the window with `currency <> 'NOK'`)
and apply the sandbox condition to `undated`.

## R-INSIGHTS-08 — a dashboard period
The prototype has no period control on a dashboard, and `dashboards.filters` is neither written by
`dashboard_save` nor read by `dashboard_get`, so every tile runs with its own definition's period (the screen
passes `p_period = null`). If a dashboard-wide period is wanted later: `dashboard_save(…, p_filters jsonb)`
stores `{period}` and `dashboard_get` applies it when `p_period` is null. No change is needed for the design as
drawn. Deviation V-INSIGHTS-04.

## R-INSIGHTS-09 — drill-down for a conversion row
`report_drill` re-runs a definition with the segment's `group_by` value; a conversion report has no
`group_by`, so a row of «Stage conversion» cannot open the deals that entered that stage. Proposal: for
`type = 'conversion'`, `app.report_rows` with `{key: <stage id>}` returns the deals whose
`deal_stage_history` entered that stage in the period. The screen makes those rows clickable once it exists.
