# Database requests — Automation

Changes the Automation screen would use that a screen builder may not make (no migrations in phase B). The
screen ships without them, as noted in `deviations/automation.md`.

The known gap (`wf_blockers` did not flag an enroll_sequence step pointing at a draft sequence) is closed by
`0026_engine_followups.sql` (`sequence_inactive`); the screen words it.

## R-AUTOMATION-01 Assignment rules in one read
`workflows_get({kind:'assignment'})` returns `app.wf_row`, which has no `options`, so a rule's condition and
assignee need one `workflow_get` per rule. Add `options` (and `priority`) to `app.wf_row`, or have
`workflows_get` add them for kind `assignment`.

## R-AUTOMATION-02 The record a run is about
`workflow_runs_get` returns `subject_type` and `subject_id` only; the screen names each record with one
`rec_list(entity, {ids})` per record type. Add `subject_title` (the entity's `title_col`, visibility applied).

## R-AUTOMATION-03 Who may skip or exit an enrolment
`sequence_skip_step` and `sequence_exit` allow the enroller or `deals:edit_others`, but `sequence_get.enrolled`
does not say who enrolled a record, so the screen offers both to anyone who may see deals and the database
refuses the rest. Add `enrolled_by` (or `mine`).

## R-AUTOMATION-04 Filterable fields and events as data
No function exposes `app.entity_columns` (column, kind, writable, ref), so the builder's condition editor, the
date trigger and the update step carry their own lists of fields, events and date columns per record type
(`_components/builder-text.ts`). Add `public.entity_columns_get(p_entity)` (filterable and writable columns with
their kinds) and the event kinds each record type emits.

## R-AUTOMATION-05 The custom safeguard number in the monitor
`workflow_monitor.loop_protection` is the mode only; the «Custom · n runs» figure comes from `settings_get`.
Add the number beside the mode.

## R-AUTOMATION-06 Asana and Trello steps (AUT-07)
`integration_connections` lists `asana` and `trello`, but `app.wf_kinds` has no step kind for them, so the
builder cannot offer them. Add `asana_task` / `trello_card` kinds (blocked as `not_connected:<provider>` like
Slack) when the design adds them to the palette.
