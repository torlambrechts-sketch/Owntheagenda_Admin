# Database, backend and product requests — Customers

For the lead builder. Each is left out of the screen (disabled with a message, or the design's empty
treatment) until it exists. Orgpuls commands are added to Orgpuls' `app.platform_command_map` and then to
`supabase/functions/_shared/orgpuls.ts` (D-40).

## R-CUSTOMERS-01 Orgpuls commands for the company actions
The Actions menu shows these disabled with «The product does not offer this yet». Each needs an Orgpuls
operation (super_admin/support as fits), a row in `platform_command_map`, the entry in `ORGPULS_COMMANDS`,
and then one branch in `runCustomerAction` (`app/(admin)/customers/actions.ts`), audited with
`customer_action_log` like the three that exist:
- `billing.change_plan (p_org uuid, p_plan text, p_reason text)` — band and price version.
- `billing.discount (p_org uuid, p_percent numeric, p_months int, p_reason text)`.
- `billing.complimentary (p_org uuid, p_on boolean, p_reason text)` — sets `free_from`.
- `orgs.suspend (p_org uuid, p_on boolean, p_reason text)` — read-only access to results, scheduled sends paused.
- `orgs.transfer_owner (p_org uuid, p_email text, p_reason text)`.
- `orgs.merge (p_keep uuid, p_merge uuid, p_reason text)` with a preview command first.
- `orgs.export (p_org uuid, p_reason text)` — aggregates at n ≥ the org's k, tiltak, comments without identity; returns a signed URL.

## R-CUSTOMERS-02 Orgpuls commands for product users
Users and roles and Customers › Users show these disabled: `members.resend_invite`, `members.magic_link`,
`members.reset_mfa`, `members.change_email`, `members.set_billing_contact`, `members.remove`,
`members.deactivate` (each `(p_org uuid, p_user uuid, p_reason text)`, plus the new e-mail for
change_email). The screen then calls them through `runCommand` with the member's `tenant_id` / `user_id`.
Also: Orgpuls should send `member.state` (0013's projection) so last login, MFA, auth method, invite
state and inviter are filled — today every member has them null.

## R-CUSTOMERS-03 Count-only metrics in `counts.updated` (D-21)
The Overview tiles read `customer_detail.counts` by these keys; please have Orgpuls send them:
`departments`, `teams`, `employees` (on the employee list), `groups_below_threshold` (groups under the
org's k), `tiltak_open`, `tiltak_closed`, `tiltak_overdue`. With `employees` per tenant, the Billing tab's
«Band crossed» notice and Subscriptions › Band reconciliation can be computed against `plan_versions`.
Optional: `k_threshold` so the copy can name the organization's own threshold.

## R-CUSTOMERS-04 Invoice and payment mirror (when Stripe arrives, D-22)
Invoices card, payment method, dunning step, «Retry», refunds KPI and the failed-payment reasons need an
invoice/payment mirror (number, date, amount, status, method, dunning step, reason code) and commands for
resend/retry. Until then the screen shows the empty treatment and disabled buttons.

## R-CUSTOMERS-05 Coupons
`coupon_save(code, values)` (global:configure, audited) and a usage count per coupon (redemptions from the
product or the payment provider) for «＋ New coupon» and the «used» column. «Export to accounting» needs
the accounting integration.

## R-CUSTOMERS-06 Support access reaches the customer
`access_request` records a pending grant, but nothing delivers it. Needed: an Orgpuls command
`access.request (p_org uuid, p_grant uuid, p_staff text, p_hours int, p_reason text)` that shows the
request in the customer's settings, and Orgpuls events `access.approved` / `access.denied` /
`access.page_view` projected onto `app.support_access_grants` (state, approved_by, approved_at,
expires_at, page_views). Also an expiry job (active → expired at `expires_at`).

## R-CUSTOMERS-07 Personvern: deletion queue and data processing agreements
Orgpuls has `orgs.deletions` (admin_deletions); the platform needs either a read RPC over a projected
table (organization, due date, state) fed by an Orgpuls event, or a server-side call of that command that
the screen may show. DPAs need an Orgpuls event (`dpa.accepted`: version, accepted_at, accepted by role)
and a table + `dpas_get()`.

## R-CUSTOMERS-08 Health score (phase 4)
`org_customer.health` is null. When the scoring model exists, return the score and its parts
(`health_parts`: last admin login, survey cadence, response trend, tiltak activity, payment status) so the
list column, the header, the breakdown card, the Health filter and the «At risk before renewal» view can
come back (V-CUSTOMERS-01).
