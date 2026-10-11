# Growth v2 — gap analysis (SimpleGrowth · SeoSuite · GrowthPlaybook, 11 Oct 2026)

The design grew from four tabs to seven, each with sub-views: about 25 screens. This maps every element to its source in
Sentral and says what is built, how, and what is left out because nothing real could fill it (CLAUDE.md: a value the
schema does not hold is not rendered as if it were real).

Legend
- **D** built on data Sentral already holds (tracker sessions, page views and presses; product events: accounts,
  milestones, subscriptions, MRR; Search Console; the crawler; campaigns, spend, email events, sender domains)
- **I** built with an integration added in this work: PageSpeed Insights (Core Web Vitals), Search Console URL Inspection
  (index coverage), the crawler's link graph and page facts
- **W** a workflow feature: records people create here (plans, changes, alert rules, experiments, budgets)
- **≈** built, but adapted: a measure differs from the prototype's and the deviation file says how
- **✖** left out: no source; what it would take is named

Facts the plan rests on: the tracker is cookieless (D-37), so a web session is never joined to an account; steps after
«account created» are counted from the product's own events, per account. Production has had the tracker since 8 Oct;
the screens show the real, small numbers and the design's empty treatments.

## Shell of the tab (SimpleGrowth)
| Element | Source | Plan |
|---|---|---|
| Seven tabs: Overview · Signup funnel and log · Pages and links · SEO · Marketing campaigns · Email and automation · Integrations | — | D. Links with addresses (V-SGR-01 stays) |
| Scope bar: Today / 7 / 30 / 90 days | sessions, accounts | D. «Today» is new (ranges 1/7/30/90) |
| Breadcrumbs: period › day › hour | sessions `started_at`, accounts `created_at` | D. Day and hour in the address |
| Source and Device filters | session channel, device | D. Account figures follow Source through first-touch attribution; Device cannot reach an account (cookieless) — account figures read «—» under a device filter, with the reason as a hint (≈) |
| «Updated 2 min ago» | latest session / import | D |

## Overview
| Element | Source | Plan |
|---|---|---|
| KPIs: Visitors, Signups started, Visit → signup, Accounts, Paying, Cost per paying; a KPI picks the chart's metric | sessions; `signup_started`; accounts; subscriptions; spend | D. Cost per paying = spend typed in ÷ new paying (no change figure unless both periods have spend) |
| Bar chart per day / per hour, inner signup bar, click to drill, peak hour | sessions and accounts by day/hour | D |
| Biggest opportunities (+signups/month, effort, jump) | funnel, segments, keywords, pages, campaigns | D ≈. Each estimate is a stated rule on real figures (closing a segment gap, a page's gap to the site rate, a striking-distance keyword at the expected click rate, a budget move); shown only when its inputs exist |
| Channels (visits, signups, conv., paying), click filters | sessions; first-touch attribution | D |

## Signup funnel and log
| Element | Source | Plan |
|---|---|---|
| Eight steps | 1 visited, 2 pricing/product, 3 «Kom i gang» press, 4 org.nr sent (`signup_started`): sessions · 5 account created, 6 employee list, 7 first survey, 8 paying: accounts and milestones | D ≈. Steps 1–4 count sessions, 5–8 accounts; the join between them is the period, not a person (D-37) |
| Step card: stopped here, continued, median time, vs last period | same | D. Median time from timestamps (seconds within a session; days between milestones) |
| Why they stop | tracker: the last page before leaving, `signup_error` values; products: none | D ≈. Real exit pages and errors instead of the prototype's survey-style reasons; account steps say what the product reports |
| Continue rate by segment | channel, device | D (device only for session steps) |
| Fix | rules on the step's own figures | D ≈. A recommendation is chosen by rule from the figures shown, never a canned claim |
| Signup log, filters, trail, Export CSV | session journeys (0068 `attempts`) | D ≈. «Reached» stops at the website's steps; a session never carries an account's later events (D-37). CSV holds no personal data |

## Pages and links
| Element | Source | Plan |
|---|---|---|
| Landing pages: visits, bounce, signups, conv., LCP; sort; tags | sessions by entry page; PSI | D + I |
| Page card: title, visits sparkline, LCP/INP/CLS, sources, keywords ranking it, recommendation | crawler title; sessions; PSI; Search Console pages | D + I. INP only where Chrome field data exists, else «—» |
| Referring sites: domain, visits, signups, status | sessions' referrer | D ≈. «Links» and «DR» need a backlink index (Ahrefs/Semrush API) ✖; status New/Active/Lost from referral traffic |
| Links and buttons on our site: clicks, CTR, signups | tracker `cta` presses with the page they were on | D |

## SEO (SeoSuite + SimpleGrowth › Keywords)
| View / element | Source | Plan |
|---|---|---|
| Overview KPIs: organic clicks, organic signups, organic MRR won, traffic value, visibility, indexed pages | Search Console; first-touch organic accounts; MRR; URL Inspection | D + I. Traffic value needs CPC data ✖ (left out); visibility = our click share of tracked keywords against the expected-CTR curve (≈, defined beside it) |
| Top 5 actions (kr/mo) | opportunities below | D ≈. Value = impressions × click-rate gain × signup rate × paid rate × ARPA × chance — every input real; «—» while one is missing |
| Index coverage | URL Inspection API (2 000 inspections/day) on the sitemap's pages | I |
| Data confidence | facts about Sentral's own sources | D (true statements only) |
| Topic clusters | tracked keywords grouped by topic, main page, supporting pages; 12-week click share | W + D ≈. Topics are defined here (name, main page, keywords); competitor share of clicks ✖ |
| Opportunities (typed: striking distance, low CTR, content gap, cannibalization, decay; featured snippet ✖) | Search Console query × page × day | D. Difficulty (KD) needs an SEO tool ✖ (column left out) |
| Content plan (Idea → Writing → Published → Measuring), brief, measured result after 28 days | `seo_content_plan` extended; Search Console | W + D. Brief: target, intent (rule), related searches and questions from Search Console's own queries (≈ for «People also ask»); length vs top 3 ✖ |
| Internal links: suggestions, orphan pages, most linked pages | crawler link graph with anchors and term mentions | I. «Add link» records the decision and logs a change; Sentral does not edit the website |
| Search results and competitors | needs SERP/competitor data (Ahrefs/Semrush/DataForSEO) | ✖ The sub-tab shows the integration it waits for |
| Change log: log a change, clicks per day with markers, result after 28 days | W; Search Console page data before/after | W + D |
| Alerts: rules on/off, channels, history | hourly checker over Search Console, tracker, URL Inspection, PSI | W + D. Rules without a source (lost backlink, competitor jump, lost snippet) left out ✖; channels In app and Email (Slack when connected; Ticket creates a support ticket) |
| Keywords: KPIs, segment chips, table (volume, pos., Δ, CTR, clicks, potential), detail (intent, position line, CTR vs expected, ranking page, Do this) | Search Console | D ≈. «Volume» shows impressions (V-SGR-08); «Who ranks above us» needs SERP data ✖ |
| Technical SEO | crawler + PSI + cannibalization + schema | D + I |
| Content gaps | Search Console (0072 ideas) | D |

## Marketing campaigns (GrowthMarketing + GrowthPlaybook)
| View | Source | Plan |
|---|---|---|
| Campaigns | existing | D (unchanged) |
| Outcomes and attribution: spend, per signup, per account, paying, CAC, payback, MRR; models | spend; first-touch attribution; MRR | D ≈. First and last touch only — position-based and data-driven need multi-touch paths ✖. «Sent back to ad platforms as a conversion» needs ad APIs ✖ |
| Most common journeys to paying | first and last touch per account | D ≈ (two touches, not full paths) |
| Budget planner: budget per channel, pace, projection, suggested move, scenario | W budgets; monthly spend; observed cost per paying | W + D ≈. Marginal cost per next 10 000 kr needs bid-level data ✖ (uses observed cost per paying, labelled so) |
| Experiments: hypothesis, ICE, Backlog → Ready → Running → Done | W | W. Live lift/confidence needs an A/B tool ✖; result typed when called |
| Audiences | CRM lists | ≈ Lists and sizes; sync to Google/LinkedIn/Meta needs ad APIs ✖ |
| Results by persona | needs a role from signup | ✖ until the product reports one |
| Creative: message matrix, ad variants, landing page tests | needs ad platform data | ✖ |
| Calendar and offers | ad campaigns and email campaigns with dates; W blackouts | D + W. Search interest needs Google Trends (no API) ✖; offers and partners need an offer field on signups ✖ |

## Email and automation
| View | Source | Plan |
|---|---|---|
| Email campaigns | existing | D (unchanged) |
| Trial and abandoned signup: KPIs, branches, control group, recovery | trial conversion, milestones, tracker abandonments; workflows | D ≈. Branches are the live workflows whose triggers are trial events; recovery emails need the address captured on step 1 of the product's signup ✖ |
| Flow library | workflows/sequences with states and email events | D ≈. Lift needs a control group per flow ✖ |
| Deliverability and frequency | sender domains (SPF/DKIM/DMARC), bounces, complaints, unsubscribes | D ≈. Inbox placement (seed tests) and domain reputation (Postmaster) ✖; frequency cap and priority only when the engine enforces them |

## Integrations
| Element | Source | Plan |
|---|---|---|
| Cards with state, feeds, last sync, Connect | `integration_connections`, imports, crawls, tracker | D. Only integrations Sentral has: website tracker, Search Console, PageSpeed Insights, crawler, product events, email (Brevo). GA4, Google Ads, GTM, BigQuery, Trends, GBP, Looker, Ahrefs, Bing, Clarity, LinkedIn, Meta, Microsoft Ads, Stripe and Slack are not built and are not shown as connected ✖ |
| Sync log | job runs, imports, crawls, product events | D |

## Order of work
1. Database and screens for Overview, Signup funnel and log, Pages and links, SEO › Keywords, Integrations — **built (0073)**;
   the deviations are `deviations/growth-v2.md`.
2. PageSpeed Insights (0073), URL Inspection and the crawler's link graph (0074) — **built**.
3. The SEO suite: overview, opportunities, content plan, internal links, change log, alerts, clusters — **built (0074)**;
   deviations V-GR2-23 to 32.
4. The playbook: outcomes, budget, experiments, calendar, audiences; trial, flow library, deliverability.

Each step is released to production on its own, with its migration, tests and pixel check.
