# Database requests — Activities

Changes the Activities screen needs and could not make (builders do not write migrations). Until they land
the screen shows the honest state named in `deviations/activities.md`.

## R-ACT-01 — save the calendar connection choice (needed)
There is no function that writes `app.calendar_connections`, so the Reminders and sync tab cannot store the
provider choice, sync mode, calendar or activity types to sync, even in the «not connected» state.
Proposed: `public.calendar_connection_save(p_values jsonb) returns jsonb` — `app.require_staff()`, upsert the
caller's row with `provider` (google|microsoft), `mode`, `calendar_id`, `sync_type_ids` (checked against
`app.activity_types`), leaving `status = 'not_connected'` and `vault_secret_id` untouched; audit with the field
names. Grant to authenticated, test in a suite. The screen then enables the provider, mode and type controls.

## R-ACT-02 — proposed times on booking links
A «Proposed times» link (kind = 'proposed') has nowhere to keep its times. Proposed: `app.booking_links.proposed_times
timestamptz[] not null default '{}'` (max 10, in the future), accepted by `booking_link_save` on create and update.

## R-ACT-03 — `activity_reminders_set` does not check the owner (security)
`activity_guests_set` and `activity_done` refuse a caller who neither owns the activity nor has
`deals:edit_others`; `activity_reminders_set` only checks visibility, so anyone who can see an activity can
replace its reminders. Proposed: add the same owner / `edit_others` check. (The screen already hides the
controls when the staff member may not edit.)

## R-ACT-04 — bookings without the organization
The design's recent bookings show «name · organization»; `my_scheduling().bookings` returns name, link title
and times only. Proposed: add `organization` (the booked person's organization name) to each booking.

## R-ACT-05 — move many activities by a relative amount (optional)
«Move to tomorrow» keeps each activity's time of day. `rec_bulk` writes one value to every id, so the screen
groups the selection by time of day and calls `rec_bulk` once per group (not atomic across groups). An
`activities_shift(p_ids uuid[], p_days int)` would make it one transaction.
