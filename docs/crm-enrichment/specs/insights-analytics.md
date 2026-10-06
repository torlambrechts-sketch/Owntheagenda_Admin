# Data-requirements spec: Insights and Analytics (Sentral)

Sources read in full: `design-reference/sentral/project/Insights.dc.html` and `Analytics.dc.html` (markup and logic), `admin-data.js`, `coverage-data.js` (INS-01..10, PRO-01..07, plus PIP-11, CRM-08, SEC-09, ENT-01..04, WEB-01..04, CMP-06/09, LGN-03, flows UF-13, UF-26, SF-02, SF-14, SF-24, SF-26, SF-32), `docs/crm-enrichment/DECISIONS.md`, and migrations 0001–0014. Only PRO-03 touches these screens: the health score can be a scoring criterion. The rest of PRO is the Feed.

**Overall finding.** Almost every figure on both screens is fabricated in the prototype. Some are literals, some come from a seeded PRNG (`s=31` in Analytics), some from `admin-data.js`'s random orgs and deals. The only figures computed from records are these Insights tiles: open pipeline total, open value by owner, deals per stage, deals by source, and the deal-revenue forecast. Even those run on random demo deals. In Analytics the **range selector (30 d / 90 d / 12 m) is stored in state but no computation uses it.** The real build must pass a period into every query.

---

## 1. Insights screen (route `insights`, INS-01..10, UF-13)

### Views and states
Five tabs: Dashboards (default), Report builder, Goals, Forecast, Ask for a report. Overlays are a drill-down modal and a toast. The dashboard has an edit mode ("Arrange and resize" / "Done arranging") and a share popover with a public-link on/off state. The design has no loading, empty or no-permission states. Per D-41 they need building: an empty dashboard, a report with no rows, a goal with no matching records, and a forecast with no open deals.

Header promise: *"Live data · same visibility rules · reports per user: unlimited (entitlement)"*. This means three things: reports query live tables or event-refreshed rollups (INS-10, SF-14); the viewer's visibility scope applies (D-09); and the report count is an ENT-02 limit, defaulting to unlimited (D-17).

### Dashboard tiles: source and formula

| Tile | Prototype | Real source / formula |
|---|---|---|
| Won value · this quarter | **Fabricated** (312 000 literal, "+18 %" literal) | `sum(value_nok) from deals where status='won' and won_at in quarter and deleted_at is null`, visibility-filtered. Delta = against the previous quarter. Needs FX conversion (NEW `fx_rates`, SF-32). |
| Open pipeline | Sum of demo open deals; **"+6 %" fabricated** | `sum(value) where status='open' and archived_at is null`. The delta needs the open value at the end of the previous period. Deal values are not kept as history, so this needs NEW `pipeline_snapshots_daily`. |
| Average sales cycle | **Fabricated** ("34 d", "−4 d") | `avg(won_at - created_at)` in days for deals won in the period, compared with the previous period. |
| Open value by owner | Demo deals, three hard-coded owners | `deals` open, `group by owner_id`, joined to `admins.name`. All owners, not a fixed list. |
| Deals per stage (New business) | Demo deals | `count(*) from deals where status='open' group by stage_id`, ordered by `stages.ord`, with a pipeline filter. |
| Stage conversion · 90 d | **Fabricated** (72/58/49/61/68 %) | From `deal_stage_history`: of the deals that entered stage *i* in the window, the share later in stage *i+1*. For the last stage, the share with `status='won'`. |
| Lost reasons (pie) | **Fabricated** (Price 9 …). Demo data has only one lost deal | `count(*) from deals where status='lost' group by lost_reason`. This is a text column; normalise it against `lost_reasons.label`. |
| Deals by source | Demo deals | `group by deals.source`. |
| Activities completed · month by type | **Fabricated** (Calls 64, Emails 142 …) | `activities where done and done_at in month group by type_id` (→ `activity_types`). The "Emails" bucket needs logged emails from mailbox sync (COM, not built yet). Until then it is empty or omitted. |

Dashboard selector options are Default, Sales manager, Sales rep, Marketing and My dashboard. These are role templates (INS-03) and become seeded `dashboards` rows with `is_template`.

### Actions: what each does for real
- **Arrange and resize.** Swaps a tile left or right; the width runs 3–12 columns in steps of 2. Persists `dashboard_tiles.position, span`. INS-03's acceptance test: "reopens exactly as arranged".
- **Duplicate.** Toast only in the prototype. Real: copies the dashboard and its tiles, and the reports they point to, to the current user as "<name> (copy)".
- **Share.** The prototype's list is a literal (Sales team / Ingrid / Ola) and its role selects have no handler. Real: `dashboard_shares` keyed by staff, team or visibility group, with role viewer or editor.
- **Public live link.** The prototype shows a literal token at `sentral.orgpuls.no/d/pub_7Gx2kQ9…`. **This conflicts with D-28.** Public pages live on `go.owntheagenda.com`, with unguessable, revocable tokens. Store a SHA-256 of the token. The link runs with the owner's scope (SF-14), and revoking it takes effect at once (INS-04).
- **PNG · PDF.** Toast only. Real: render server-side (headless print of the dashboard) and download. This is the INS-08 export permission.
- **＋ Report.** Opens the builder.
- **Drill-down (clicking any segment).** The prototype shows `D.deals.filter((x,j)=>(j+i)%4===0)`, which is **fabricated** and not the segment's rows. Real: re-run the report definition with the segment's dimension value as an extra filter and return rows (title, owner, value). INS-08: "exported rows equal the rows behind the chart".
- **Export rows.** Toast only. Real: XLSX or CSV of the drill rows, permission-checked and audited (D-12).

### Report builder
Fields:
- **Entity:** Deals, Activities, Leads, People, Organizations, **Campaigns, Projects** (those modules don't exist yet), Revenue.
- **Report type:** Performance, Conversion, Duration, Progress, Products.
- **Group by:** Owner, Stage, Source, Lost reason, Label, plus custom fields such as "Competitor (custom)" and "Board meeting month (custom)".
- **Measure:** Count, Sum, Average, average of a custom numeric field ("Employees in scope"), Weighted value.
- **Period:** month, quarter, year, custom.
- **Chart:** Column, Bar, Pie, Scorecard, Table.
- **Filters:** a static list of three strings, not editable.
- **Series colour:** an input with no handler.

The preview reuses dashboard data. The "Competitor" data (Planday 6 …), the scorecard's 312 000 and its "+12 %" are **fabricated**.

Real build:
- A report definition as validated JSON: entity, type, measure, view-by, segment-by, filters as an AND/OR tree that includes *does-not-contain* and several conditions on one field, period, chart, colours and sort.
- A compiler from that definition to SQL over a **whitelist** of entity columns, plus `app.fields`. Custom fields are read from `custom->>key` with the type the registry gives (INS-07: "reportable without configuration").
- Visibility is applied inside a security-definer function.
- **Save to dashboard** inserts into `reports` and `dashboard_tiles`. The prototype only shows a toast.
- Footnote promise: *"click any segment to see and export its rows"*. Builder preview segments are not clickable in the prototype, so this needs implementing.
- INS-01 also names sales velocity, conversion rate and time to win as measures, and 17 report types in all. The design shows a subset.

### Goals
The five goals are **fabricated**: names, assignees, current values and targets are literals. "Pace" in the prototype is `w>=60`, which is not a pace. Real:
- A `goals` table with kind (deals_added / deals_progressed / deals_won / activities_added / activities_completed / forecast_weighted), assignee (staff, team per SEC-09, or company), pipeline, frequency (weekly to yearly), duration, and a count or value target.
- Progress = the count or sum of matching records in the current interval (INS-05).
- Pace = progress% ≥ elapsed% of the interval.
- Recomputed by the scheduled goal check (SF-26) and on events.

The design has **no "create goal" control**. Per D-41 it must be built in the design's language.

### Forecast
- **Deal revenue forecast.** Real logic on demo deals: group open deals by close month; best case = Σ value, weighted = Σ value × `stages.probability`/100. The months Oct–Jan are hard-coded and must become the next N months. Source: `deals.expected_close_date` and `stages.probability`. Reconciles with PIP-11.
- **Product revenue forecast.** **Fabricated** (`rec = 30 + 4.5i`, stepped installments). Real (UF-26, CRM-08):
  - Recurring = current subscription MRR (`app.sub_mrr`), carried forward and dropped from `cancel_effective_at`, plus won deals' `deal_items` where `billing='recurring'`, normalised to monthly by `billing_frequency` until `cycles` runs out.
  - Installments = `deal_items` where `billing='installments'`, spread over `cycles`.
  - Gap: `deal_items` has no start date. Add **`deal_items.starts_on date`**, or define the start as `deals.won_at`.

### Ask for a report (INS-09, SF-24)
- The prototype's chat reply and generated definition (Entity: Deals … Chart: Stacked column) are canned literals.
- Real: a Claude call through the AI gateway with the field registry as context. It returns a definition JSON, Zod-validated against the same schema as the builder, and **never numbers**. One retry, then an error. Logged with feature, user and cost.
- "Refine" appends a turn and returns a revised definition.
- "Open in builder" loads the definition; "Save as is" inserts it into `reports`.
- "Stacked column" is not among the five chart types. Add it, or have the model map to Column with segment-by.

### D-19 check (Insights)
No survey figures appear. The entities are CRM records only. The AI gateway must keep "never from survey response tables" (SF-24). If product metadata is ever added as a report entity, it must be limited to count and date metadata at tenant level, as in §2.

---

## 2. Analytics screen (route `analytics`, product-scoped by the shell's product switcher `props.product`)

### Views and states
Eight tabs: Business KPIs (default), Activation funnel, Retention and churn, Product usage, Web analytics, Attribution, Health score, Metric definitions. Global controls: scope label (product name or "All applications") and range (30 d / 90 d / 12 m, **currently unused**). Local toggles: Customers by Industry / Fylke / Size; cohort Jul–Oct; retention Logos / Revenue; attribution First / Last touch; an editable campaign spend input. Empty states (no product events yet, which 0013 says is the case until Orgpuls ships D-21) must use the design's empty treatment, never zeros.

### Business KPIs
Headline: *"Yes — trials are turning into organizations that run surveys and act on them: 31 % convert, and 78 % of paying customers created a tiltak within 30 days of their first result."* The prototype hard-codes the sentence. Real: a template filled from `v_trial_conversion`, plus the share of paying accounts where `activation_milestones.first_tiltak.reached_at − result_unlocked.reached_at ≤ 30 d`. The "Yes/No" wording must follow the figures.

| KPI | Prototype | Real |
|---|---|---|
| MRR | random `mrrSeries`, delta computed from it | latest `mrr_daily.mrr` (Σ over products in scope). Delta = against the same day last month. |
| ARR | MRR×12 | same |
| Net new MRR | MRR − previous | Σ(new+expansion−contraction−churn) from NEW `mrr_movements` |
| Paying orgs | demo orgs; **"+6" fabricated** | `count(distinct account_id)` with `sub_mrr>0`. `mrr_daily.paying` is per product and **double-counts multi-product accounts** under "All", so add NEW `mrr_daily_accounts` or compute live. |
| Trials active, "N ≤ 7 d" | demo | `sub_status='trial'`; expiring = `trial_ends_at < now()+7d` |
| Trial → paid | **fabricated** (31 %, +4) | `v_trial_conversion`: share of the signup cohort with `confirmed_at ≤ trial_started_at + 45 d` |
| Logo churn / Revenue churn / net of expansion | **fabricated** | from `mrr_movements` (definitions in §2 Metric definitions) |
| ARPA | demo orgs; **"+3 %" fabricated** | MRR ÷ paying accounts |
| Customers | demo | `count(distinct account_id) from account_products` (incl. trial and cancelled, excluding deleted) |

Charts:
- **Net new MRR (stacked ±).** **Fabricated** (PRNG). Real: monthly Σ per movement type from `mrr_movements`.
- **MRR by application, 12 months.** Fabricated series. Real: `mrr_daily` at month end per product (exists).
- **Trial → paid by signup source.** **Fabricated** (both the % and the count column `n2`). Real: group trial cohorts by `organizations.source` or `account_products.attribution->>'utm_source'` mapped through NEW `channel_rules`. Shows the conversion % and the trial count.
- **ARPA and price tiers.** Real on demo orgs: paying accounts per band. Source: `subscriptions.plan` or `seats` matched to `plan_versions (min_employees, max_employees)`.
- **Customers by Industry / Fylke / Size.** Real on demo orgs. Source: `organizations.industry` (NACE from Brønnøysund), `fylke`, and `subscriptions.seats` bucketed by `plan_versions`. The footnote *"size from the employee list"* means seats, not `organizations.employees`.

### Activation funnel
- **"Promise on the site 18 min · target 20 min".** 18 is **fabricated**. Real: median(`survey_sent − account_created`) for the cohort, from `activation_milestones`. The target is NEW setting `activation.first_send_target_min`.
- **Cards.** All three (biggest drop-off, Activated %, Signup → paid) are **fabricated** text. Real: argmax step drop; share reaching `result_unlocked`, with the delta against the cohort three months earlier; median `converted − account_created`.
- **Funnel.** Cohort sizes `{Jul:58…}`, rates and median times are **fabricated**. Real:
  - Cohort = the month of `account_created`.
  - Step *k* = count of tenants with `activation_milestones.key = k`. The eight steps map 1:1 to the existing check list.
  - Drop = 1 − step *k* ÷ step *k*−1. Median time = median(`reached_at_k − reached_at_{k−1}`).
  - Cohort pills = the last four months, computed.
- **Text corrections.**
  - "Result unlocked (≥ 5 answers)" and the `v_activated_orgs` definition hard-code k=5. Orgpuls's k is 3..10 per organisation, frozen per round. Use "Result unlocked" with no number.
  - "Results viewed by daglig leder / HR": Orgpuls has no HR role (roles are daglig_leder, avdelingsleder, verneombud).

### Retention and churn
- **Cohort heatmap.** **Fabricated** (PRNG); the cohort-year label logic is also wrong. Real: cohort = month of first `confirmed_at`, size = accounts. Logos M*k* = % still paying at month *k*. Revenue M*k* = MRR_k ÷ MRR_0, which may exceed 100 (net revenue retention). Source: NEW `mrr_tenant_monthly` (or `cohort_retention_monthly` snapshots).
- **Logo and revenue churn per month.** **Fabricated**. Real: from `mrr_movements`.
- **Churn reasons, last 6 months.** **Fabricated**. Needs NEW `churn_reasons` (lookup) and `account_churns.reason_id`. The reason is set by staff, or arrives as a coded reason on `billing.changed` (a code, never free text). "Payment failure, not recovered" is derivable from `payment_state` at churn time.

### Product usage
All KPIs are **fabricated literals**.

| Element | Source |
|---|---|
| Surveys sent · month (main / pulse) | exists: `count(*) from product_survey_rounds where opens_at in month group by kind` |
| Avg response rate (main / pulse) | exists: Σanswered ÷ Σinvited over closed rounds. Cross-tenant aggregate of counts. |
| Reminder effectiveness | exists: Σ`gained_after_reminders` ÷ Σ(`answered − gained_after_reminders`) |
| Groups hidden by threshold 11 % | **NEW count** from Orgpuls (`groups_total`, `groups_below_k` per round). **D-19 flag**, see below. |
| Tiltak created · month, "92 % with owner and deadline" | D-21 `tiltak created` count, plus NEW counts `tiltak_with_owner_deadline` |
| Tiltak closed on time 64 % | **NEW counts** `tiltak_closed`, `tiltak_closed_on_time` |
| Comments posted 1 920, "58 % answered by leaders" | **NEW counts**. **D-19 flag**. |
| Surveys sent per month chart | exists (`product_survey_rounds`). Prototype values are random. |
| Logins by role (30 d) | D-21 "logins by role" → NEW `product_logins_daily`. `members.last_login_at` holds only the latest login and cannot count. Labels must be Orgpuls's three roles. The prototype shows "HR" and "Verneombud / tillitsvalgt", which are wrong. |
| Feature adoption per org (Årshjul, AMU report …) | NEW counts per feature in `usage_daily.data`, or `product_feature_usage_daily`. % = tenants using the feature in the period ÷ paying tenants. |
| Usage across applications (Skiftly shifts, Avvik incidents, Kurs completions …) | `usage_daily.data` jsonb, rendered from NEW registry `product_metric_defs` (data, not code). All values in the design are literals. |

Today `product_counts` keeps only the latest value. Monthly trends need history: NEW `product_counts_daily`, or the counts sent through `usage.daily`.

### Web analytics (WEB-01/02, D-37)
Banner promise: *"In-house and cookieless · unique visitors from an IP + user-agent hash with a daily rotating salt · bots filtered · never loaded in the survey flow."* This is compatible with D-37 if the IP is used only in memory at ingest (hash + company lookup), the salt lives in Vault and is destroyed daily, and only the hash is stored.

Every number on the tab is **fabricated**: KPIs, the 30-day series, funnel, personas, sources, pages, campaigns, queries, and the "38 failed Brønnøysund lookups" banner.

Real sources:
- **Visitors, sessions, pages per visit, bounce:** NEW `web_sessions` and `web_pageviews`, rolled up into `web_daily`. Bounce = single-page sessions ÷ sessions. Promise correction: with a daily salt, "Visitors" over 30 days is a **sum of daily uniques**, not deduplicated uniques. Label it accordingly.
- **Signups:** `account_products.created_at`, or `org.created` events.
- **Website funnel** (Visit → pricing/platform page → «Kom i gang» click → Org.nr entered → Account created): page-path rules plus tracker custom events in NEW `web_events (name)`.
- **Failed Brønnøysund lookups:** a NEW Orgpuls count event `signup.lookup_failed` carrying an org-form code (e.g. ENK) and no org.nr. Or a tracker event.
- **Personas «Hvem er du?»:** `web_events` with name `persona_click` and a persona value. The signup rate needs the session's persona joined to a signup, which is possible only within the same day's hash.
- **Sources:** referrer and UTM classified by `channel_rules`.
- **Top landing pages:** `web_pageviews` where the page is the session's entry page.
- **Campaigns — spend to paid.** The spend input sets prototype state only. Real: NEW `marketing_spend` (campaign, channel, month, amount). Visits, signups and paid come from UTM campaign × `account_products.attribution` × `confirmed_at`. Cost per paid = spend ÷ paid.
- **Search Console, "imported nightly":** provider integration (Google Search Console API, OAuth token in Vault per D-18) → NEW `search_console_daily`.

### Attribution
- The channel table is **fabricated**. Last touch is produced by multiplying first-touch numbers by invented factors.
- Real: `account_products.attribution` (the `org.attribution` event already merges into it). Orgpuls must send **both first_touch and last_touch** UTM source, medium, campaign and referrer (a D-40 addition).
- Per channel (via `channel_rules`): signups; activated (`result_unlocked` milestone); paid (`confirmed_at`); MRR won (Σ`sub_mrr`); spend (`marketing_spend`); CAC = spend ÷ paid.
- **"Journey of a paying customer — Lumio AS".** **Fabricated**, including the Feb 2024 ad, 3 visits and 12 Mar 2024. **Not achievable as drawn.** A cross-day, person-level click path contradicts the daily-rotating cookieless hash and D-37. A real journey can show only: first touch and last touch (from attribution), the newsletter consent (`consent_events`), the activation milestones with their gaps ("first survey sent 18 min later"), and the paid date and band. Redesign as that or omit it, and log the change in DEVIATIONS.

### Health score (D-21: computed in the platform)
- **Distribution histogram.** **Fabricated** (random `org.health`). Real: NEW `health_scores` buckets.
- **"How the score is built."** Literal weights:

| Signal | Weight | Source |
|---|---|---|
| Last admin login | 25 % | `members.last_login_at` |
| Survey cadence vs årshjul | 25 % | `product_survey_rounds` against the planned cadence. Needs `planned_at` rounds or a NEW count `årshjul_planned`. |
| Response rate trend | 20 % | answered ÷ invited, last round against the previous one, counts only |
| Tiltak activity | 15 % | tiltak counts |
| Payment status | 15 % | `payment_state` |

  The weights go in NEW `health_models` (versioned, editable). Recompute nightly and on payment events (as the definitions tab promises).
- **At risk before renewal (score < 40 · paying).**
  - The "why" strings are template-fabricated. Real: the top negative contributors stored in `health_scores.factors`.
  - "Renews in N d" is **fabricated** from the record id, and **no renewal date exists**. Add NEW `subscriptions.current_period_end timestamptz` to `billing.changed`.
  - Clicking a row opens the customer.
- PRO-03: the health score must be available as a deal-scoring criterion.

### Metric definitions
Seven rows: view name, description, git path and version. The version strings ("metrics/mrr.sql · v4") are **fabricated**.

The text promises *"Defined once as SQL views, versioned in git · reports and CRM read the same views"*. Real: these SQL views ship in migrations, and NEW `metric_definitions (key, view_name, description, migration, version)` is seeded by the same migration, so the screen shows real versions.

Text corrections:
- `v_mrr_monthly` says "from the Stripe mirror". D-22 says Stripe waits; the source is the Orgpuls `billing.changed` mirror (`app.sub_mrr`).
- `v_activated_orgs` says "≥ 5 answers". k is per organisation (see Activation funnel).

### D-19 / anonymity flags (Analytics)
1. **Groups hidden by threshold.** Reveals k-suppression structure. Acceptable only as a cross-tenant aggregate of tenant-level counts (Σ groups_below_k ÷ Σ groups_total). Never per group, never named groups, never per round with group labels. Needs Orgpuls's agreement before it is added (Orgpuls invariant 1). Recommend omitting it until decided.
2. **Comments posted / answered by leaders.** Derived from Orgpuls's `response_comments` (X-103). Allowed only as tenant-level monthly counts. No text, no per-group split. Not in the D-21 list, so it is a new event that needs a decision.
3. **Response rate (aggregate, health signal) and reminder effectiveness.** Participation counts already in `product_survey_rounds`. Allowed at round or tenant level. Must never be split by group or department.
4. Nothing else on either screen shows survey results: no index, factor or answer distribution. Keep it that way. No report entity may be built on product survey data beyond these counts.

---

## 3. Proposed tables (DDL sketch; RLS on, no policy, access via security-definer RPCs, tests per D-03/D-09)

```
reports(id uuid pk, owner_id uuid→admins, name text, definition jsonb /*Zod-validated*/, chart text,
        colors jsonb, is_template bool, source text check in ('builder','ai'), created_at, updated_at, deleted_at)
dashboards(id uuid pk, owner_id uuid, name text, is_default bool, template_role text null,
        filters jsonb /*period,user*/, created_at, updated_at, deleted_at)
dashboard_tiles(dashboard_id uuid, report_id uuid, position int, span smallint check (span between 3 and 12), pk(dashboard_id,report_id))
dashboard_shares(dashboard_id uuid, report_id uuid null, grantee_kind text check in('staff','team','group'), grantee_id uuid, role text check in('viewer','editor'))
public_links(id uuid pk, object_kind text check in('dashboard','report'), object_id uuid, owner_id uuid,
        token_sha256 bytea unique, created_at, revoked_at)      -- served on go.owntheagenda.com (D-28)
report_cache(definition_hash bytea, scope_hash bytea, result jsonb, computed_at, pk(definition_hash,scope_hash))
goals(id uuid pk, kind text, assignee_kind text check in('staff','team','company'), assignee_id uuid null,
        pipeline_id uuid null, frequency text check in('weekly','monthly','quarterly','yearly'), starts_on date, ends_on date null,
        target_count int null, target_value numeric null, created_by uuid)
goal_progress(goal_id uuid, period_start date, current numeric, computed_at, pk(goal_id,period_start))
fx_rates(day date, currency char(3), nok_per_unit numeric, pk(day,currency))
pipeline_snapshots_daily(day date, pipeline_id uuid, stage_id uuid, owner_id uuid, open_count int, open_value_nok numeric)
mrr_tenant_daily(day date, product text, tenant_id text, mrr numeric, status text, pk(day,product,tenant_id))
mrr_movements(month date, product text, tenant_id text, kind text check in('new','expansion','contraction','churn','reactivation'), delta numeric)
mrr_daily_accounts(day date, product_scope text /*'all' or key*/, paying_accounts int, trial_accounts int)
churn_reasons(id uuid pk, label text, code text unique, ord int)
account_churns(product text, tenant_id text, churned_at timestamptz, mrr_lost numeric, reason_id uuid null, payment_failure bool)
subscriptions + current_period_end timestamptz                         -- from billing.changed
deal_items + starts_on date
product_logins_daily(product, tenant_id, day date, role text check in('daglig_leder','avdelingsleder','verneombud'), logins int)
product_counts_daily(product, tenant_id, day date, metric text, value int)  -- history of counts.updated
product_metric_defs(product text, key text, label_key text, agg text, format text, ord int)
health_models(id uuid pk, version int, weights jsonb, active bool, created_at)
health_scores(product text, tenant_id text, day date, score smallint 0..100, factors jsonb, model_id uuid, pk(product,tenant_id,day))
metric_definitions(key text pk, view_name text, description_key text, migration text, version int)
channel_rules(id uuid pk, ord int, match jsonb /*utm_source/medium/referrer patterns*/, channel text)
marketing_spend(campaign text, channel text, month date, amount numeric, currency char(3), entered_by uuid)
web_sites(id uuid pk, hostname text unique, active bool)
web_sessions(id uuid pk, site_id uuid, day date, visitor_hash bytea /*daily salt; IP never stored*/, started_at, entry_path text,
        referrer_host text, utm jsonb, company_org_number text null, is_bot bool, pageviews int)
web_pageviews(session_id uuid, at timestamptz, path text)
web_events(session_id uuid, at timestamptz, name text, value text)   -- persona_click, kom_i_gang, orgnr_entered
web_daily(day, site_id, path null, channel null, visitors int, sessions int, bounces int, pageviews int, signups int)
search_console_daily(day date, site_id uuid, query text, impressions int, clicks int, position numeric)
cohort_retention_monthly(cohort month, product_scope text, mode text check in('logos','revenue'), k int, value numeric, size int)
```
New settings: `activation.first_send_target_min` (20), `health.renewal_window_days`, ENT counter `reports_per_user` (unlimited).

## 4. RPCs (security definer, Zod-parsed rows, audited reads)
- **Insights, reports:** `insights_run_report(definition, period, scope)`, `insights_drill(report_id|definition, segment)`, `insights_export_rows(...)` (CSV/XLSX), `insights_save_report`, `insights_delete_report`, `insights_copy_report`.
- **Insights, dashboards:** `insights_dashboard(dashboard_id)`, `insights_list_dashboards`, `insights_save_layout(dashboard_id, tiles[])`, `insights_duplicate_dashboard`, `insights_share(object, grantee, role)`, `insights_unshare`, `insights_create_public_link` / `insights_revoke_public_link`, `public_dashboard(token)` (anon, owner scope).
- **Insights, goals, forecast, AI:** `insights_goals`, `insights_save_goal`, `insights_delete_goal`, `insights_deal_forecast(months, pipeline, owner)`, `insights_product_forecast(months)`, `insights_ai_generate(prompt, history)` (edge function → Claude → validated definition).
- **Analytics:** `analytics_business(product, range)`, `analytics_activation(product, cohort_month)`, `analytics_retention(product, mode)`, `analytics_churn(product, range)`, `analytics_usage(product, range)`, `analytics_web(site, range)`, `analytics_attribution(touch, range)`, `analytics_set_spend(campaign, month, amount)`, `analytics_health(product)`, `analytics_metric_definitions()`, `analytics_set_churn_reason(product, tenant, reason_id)`, `analytics_set_health_model(weights)`.
- **Tracker ingest (edge function, public):** `web_ingest(batch)`. Resolves the company from the IP, hashes with the daily salt, drops the IP, filters bots.

## 5. Jobs (pg_cron + pgmq, D-05)
- `snapshot_mrr_tenants` (nightly, after the existing `platform-mrr-snapshot`) → `mrr_tenant_daily`, `mrr_daily_accounts`
- `compute_mrr_movements` (nightly, month close) → `mrr_movements`, `account_churns`, `cohort_retention_monthly`
- `snapshot_pipeline` (nightly) → `pipeline_snapshots_daily`
- `compute_health_scores` (nightly, plus queued on `billing.changed` / payment events)
- `goal_check` (SF-26, hourly, plus on deal and activity events)
- `report_cache_invalidate` (outbox subscriber, SF-02/SF-14)
- `fx_rates_import` (daily, Norges Bank)
- `web_rollup` (hourly) and `web_salt_rotate` (daily; destroys the old salt)
- `search_console_import` (nightly; provider)
- Retention: raw `web_*` rows pruned to aggregates (no longer than the D-24 13-month horizon)

## 6. New Orgpuls events/fields needed (D-21/D-40)
- `billing.changed`: `current_period_end` and a coded `cancel_reason`
- `org.attribution`: both first-touch and last-touch blocks
- `logins.daily`: count per role
- `counts.updated` keys: `tiltak_created`, `tiltak_with_owner_deadline`, `tiltak_closed`, `tiltak_closed_on_time`, feature-use keys (årshjul, amu_report, risk_export, pulse)
- Pending decision: `groups_below_k` and `groups_total`; `comments_posted` and `comments_answered`
- `signup.lookup_failed` with an org-form code
