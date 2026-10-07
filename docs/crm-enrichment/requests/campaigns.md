# Campaigns screen — database requests

## Status

«0040» is `supabase/migrations/0040_phase6_requests.sql`, proved by `supabase/tests/phase6_requests_invariants.sql`.

| ID | Status |
|---|---|
| R-CAMPAIGNS-01 | **Open.** Needs the public `email-assets` bucket on go.owntheagenda.com (D-28) and an upload-signing edge function; neither is a migration. V-CAMPAIGNS-08 stands |
| R-CAMPAIGNS-02 | **Done in 0040.** `campaign_coupons()` (campaigns:see, active coupons only, `[{code, description, percent, months}]`). The builder's coupon select reads it and shows the chosen coupon's terms (V-CAMPAIGNS-10) |
| R-CAMPAIGNS-03 | **Done in 0040.** Segment field `product.last_round_days` in `app.filter_sql`: days since a survey round last opened (`product_survey_rounds.opens_at ≤ now()`) in a tenant of the person's organisation's account or of their own product membership; null (test with «empty») when none ever did. Dates only, tenant level (D-19). Offered in the segment editor under «Product activity» (at least / at most N days, never); the design's «Customers without a pulse in 90 days» is seeded (active customers, ≥ 90 days or never) (V-CAMPAIGNS-12) |
| R-CAMPAIGNS-04 | **Done in 0040.** `campaigns.language` (nb, nn, en, sv; default nb), set by `campaign_save`, returned in the detail, copied by `campaign_duplicate`, frozen by `app.campaign_guard`. The builder has a language select; the renderer, the canvas footer and the preview follow it, with the footer words in nn, en and sv (V-CAMPAIGNS-07) |
| R-CAMPAIGNS-05 | **Done in 0040.** `marketing_template_versions(p_id)` → `[{version, subject, created_at, by}]` and `marketing_template_restore(p_id, p_version)` (saves the version as the next one through `marketing_template_save`, same rights; audited `template.restored`). The template editor lists the versions with «Restore» (V-CAMPAIGNS-22) |


What the Campaigns screen (`/campaigns`) needs from the database that 0037 does not give. Each is left out of the
screen, or shown in its unavailable state, until the lead builder adds it.

| ID | Need | Why | Today |
|---|---|---|---|
| R-CAMPAIGNS-01 | Image upload for the email builder: an `email-assets` bucket served unauthenticated from the public host, and a signer (edge function) that returns an upload URL for staff with `campaigns:add` | Spec §1 «Images»: email clients fetch images unauthenticated | Image and video rows take an https address typed in; the panel says uploading waits for the public host (V-CAMPAIGNS-08) |
| R-CAMPAIGNS-02 | `campaign_coupons()` under `campaigns:see`: `[{code, description, percent, months}]` of active coupons | The only read of coupons is `billing_overview` (global:see); the Marketing preset lacks it, so a promotion cannot pick a coupon | The coupon select offers «None» and the campaign's own code, with a note (V-CAMPAIGNS-10) |
| R-CAMPAIGNS-03 | A segment field for product activity, e.g. `product.last_round_days` (days since the person's tenant last ran a survey round, from `product_survey_rounds`, tenant-level counts only, D-19) | The design's segment «Customers without a pulse in 90 days» | Not seeded, not offered in the editor (V-CAMPAIGNS-12) |
| R-CAMPAIGNS-04 | `campaigns.language` (nb, nn, en, sv), set in `campaign_save` and returned in the detail | The renderer's own words (the footer's reason line and unsubscribe link) should follow the email's language; Q19 also wants the footer wording by basis | The renderer prints bokmål (V-CAMPAIGNS-07); it already takes `lang` |
| R-CAMPAIGNS-05 | `marketing_template_versions(p_id)` → `[{version, subject, created_at, by}]`, and optionally a restore (save a chosen version as the next) | «marketing templates and versions»: the versions are written on every save but cannot be read | The builder shows the current version number and when it was saved (V-CAMPAIGNS-22) |
