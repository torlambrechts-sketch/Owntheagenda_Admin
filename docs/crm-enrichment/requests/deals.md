# Database requests — Deals

Changes the Deals screen needs and leaves out until they exist. Each names the function and the behaviour.

## R-DEALS-01 — `deal_list` sorts by organization, owner and labels
The list’s Organization, Owner and Labels headers cannot sort: `deal_list` accepts only registered columns
(sorting `organization_id` or `owner_id` would order by uuid; `owner_id` and `labels` are not registered and
raise `invalid`). Accept `{f: 'organization'}` → `(select o.name from app.organizations o where o.id =
t.organization_id)`, `{f: 'owner'}` → `(select a.name from app.admins a where a.id = t.owner_id)`, and
`{f: 'labels'}` → the first label’s name (or `cardinality(t.labels)`), all with `nulls last`. The screen then
maps those headers (`ListView.tsx`, `SORT_F`). Deviation V-DEALS-12.

## R-DEALS-02 — OR groups and idle days in `app.filter_sql`
The advanced filter draws «＋ OR group» and an «Idle days» field. `app.filter_sql` joins every condition with
AND, and idle time is derived (`coalesce(last_activity_at, stage_entered_at)`). Proposal: accept
`{or: [[cond, …], [cond, …]]}` as one filter entry (each inner list ANDed, the lists ORed), and for deals a
virtual field `idle_days` (`floor(extract(epoch from now() - coalesce(t.last_activity_at,
t.stage_entered_at)) / 86400)`) with eq/gt/lt. «Score» follows once phase 4 fills `deals.score`.
Deviation V-DEALS-10.

## R-DEALS-03 — `deal_to_lead(p_id)`
The drawer’s More menu offers «Convert back to lead». Nothing does this today (`lead_convert` goes the other
way). Proposal: `public.deal_to_lead(p_id uuid) returns jsonb` — requires `deals:edit_others` or ownership,
creates a lead from the deal’s title, person, organization, owner, source and value, links the deal’s notes
and activities to the lead, archives the deal, writes the changelog on both, emits `deal.converted_to_lead`,
returns `{lead_id}`. Deviation V-DEALS-11.
