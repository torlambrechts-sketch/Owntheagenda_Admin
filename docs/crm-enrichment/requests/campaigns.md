# Campaigns screen — database requests

What the Campaigns screen (`/campaigns`) needs from the database that 0037 does not give. Each is left out of the
screen, or shown in its unavailable state, until the lead builder adds it.

| ID | Need | Why | Today |
|---|---|---|---|
| R-CAMPAIGNS-01 | Image upload for the email builder: an `email-assets` bucket served unauthenticated from the public host, and a signer (edge function) that returns an upload URL for staff with `campaigns:add` | Spec §1 «Images»: email clients fetch images unauthenticated | Image and video rows take an https address typed in; the panel says uploading waits for the public host (V-CAMPAIGNS-08) |
| R-CAMPAIGNS-02 | `campaign_coupons()` under `campaigns:see`: `[{code, description, percent, months}]` of active coupons | The only read of coupons is `billing_overview` (global:see); the Marketing preset lacks it, so a promotion cannot pick a coupon | The coupon select offers «None» and the campaign's own code, with a note (V-CAMPAIGNS-10) |
| R-CAMPAIGNS-03 | A segment field for product activity, e.g. `product.last_round_days` (days since the person's tenant last ran a survey round, from `product_survey_rounds`, tenant-level counts only, D-19) | The design's segment «Customers without a pulse in 90 days» | Not seeded, not offered in the editor (V-CAMPAIGNS-12) |
| R-CAMPAIGNS-04 | `campaigns.language` (nb, nn, en, sv), set in `campaign_save` and returned in the detail | The renderer's own words (the footer's reason line and unsubscribe link) should follow the email's language; Q19 also wants the footer wording by basis | The renderer prints bokmål (V-CAMPAIGNS-07); it already takes `lang` |
| R-CAMPAIGNS-05 | `marketing_template_versions(p_id)` → `[{version, subject, created_at, by}]`, and optionally a restore (save a chosen version as the next) | «marketing templates and versions»: the versions are written on every save but cannot be read | The builder shows the current version number and when it was saved (V-CAMPAIGNS-22) |
