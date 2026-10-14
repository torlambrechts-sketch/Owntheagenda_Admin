# LeaderPact, the second product, and the public site's content by API (0090)

The owner asked (13 October 2026) for LeaderPact's articles and SEO in Sentral by API. LeaderPact
(`torlambrechts-sketch/leaderpact`, Supabase `tgxjbshdjwoemsmrtkzw`) is the platform's second product; its owner
answered E1–E8 in LeaderPact's `docs/REUSE_EVALUATION.md` 2.0. Migration `supabase/migrations/0090_leaderpact.sql`,
proved by `supabase/tests/leaderpact_invariants.sql` (21 checks) and `tests/product-events.test.ts`. Edge function
`product-events` (new). LeaderPact's side: its D-33 to D-37.

| Id | Area | Before | Now | Why |
|---|---|---|---|---|
| V-LP-01 | A second product | Orgpuls only; its secrets, headers and events function are named after it | `leaderpact` is a product (beta) with its installation (its project's address and publishable key), off until it hands over `leaderpact_token_secret` and `leaderpact_webhook_secret` through secret-intake. leaderpact.com is its site, so the crawler, Search Console and PageSpeed pick it up | LeaderPact's E1, E6 |
| V-LP-02 | One door for every product | `orgpuls-events`, hard-coded to Orgpuls | `product-events` takes any product: `{"product", "events"}` with `x-platform-product`, `x-platform-timestamp` and `x-platform-signature` (HMAC-SHA256 of `<ts>.<body>` under `<key>_webhook_secret`), checked before the body is parsed; the body must name the header's product. Orgpuls keeps `orgpuls-events` unchanged | LeaderPact's E2: neutral names, a product field, one key per product |
| V-LP-03 | The lead guard | Orgpuls rate-limits template, demo and contact requests in its own database (its 0208) | `ingest_product_events` takes a lead request five times an hour from one address and two hundred from one product, then passes the rest to `ingest_events`; when every event is refused the door answers 429. A refused request is counted, never stored | LeaderPact sends a request at once and keeps nothing, so the limit sits here |
| V-LP-04 | Content as a use | `product_event_kinds.uses` had no content | `content` joins the uses; LeaderPact registers `template.requested` (tickets, leads) and `content.inventory` (content). Labels «Content» / «Innhold» | — |
| V-LP-05 | The content inventory | Growth › SEO's plan and keywords were written by staff only | A `content.inventory` event lists the product's public pages with the searches each answers. Each page's first search becomes a content-plan row (idea while planned; published with its path once live), every search a tracked keyword (at most 200 per site), and a page's first publication a change in the log. A stage a person set is never moved back, nothing is deleted, and an inventory naming another product's site writes nothing (`content.skipped` in the audit) | The owner asked for the articles and SEO in Sentral by API; titles, paths, dates and searches only, never a person or an answer (rule 6) |
