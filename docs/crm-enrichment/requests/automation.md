# Database requests — Automation

Changes the Automation screen would use that a screen builder may not make (no migrations in phase B). The
screen ships without the open ones, as noted in `DEVIATIONS.md` (Automation).

The known gap (`wf_blockers` did not flag an enroll_sequence step pointing at a draft sequence) is closed by
`0026_engine_followups.sql` (`sequence_inactive`); the screen words it.

| ID | Request | Status |
|---|---|---|
| R-AUTOMATION-01 | Assignment rules in one read | Done (0029): `app.wf_row` carries `options` and `priority` for kind assignment; the screen reads the rules with `workflows_get` alone |
| R-AUTOMATION-02 | The record a run is about | Done (0029): `workflow_runs_get` returns `subject_title`; the per-type `rec_list` lookups are gone |
| R-AUTOMATION-03 | Who may skip or exit an enrolment | Done (0029): `sequence_get.enrolled[]` has `enrolled_by` and `mine`; Skip and Exit show only when mine or the viewer may edit others' deals |
| R-AUTOMATION-04 | Filterable fields and events as data | Partly done (0029): `entity_columns_get` feeds the condition editor, the date trigger and the update step. Open: no database list of the event kinds each record type emits, so they stay in `_components/builder-text.ts` |
| R-AUTOMATION-05 | The custom safeguard number in the monitor | Done (0029): `workflow_monitor.loop_protection_runs` |
| R-AUTOMATION-06 | Asana and Trello steps (AUT-07) | Open |

## R-AUTOMATION-04 (open part) Event kinds per record type
The trigger's Event select lists, per record type, the events the platform emits today (`rec_save` created /
updated / deleted, `deal_status` won / lost / reopened, `deal.stage_changed`, `lead.converted`,
`activity.completed`, `ticket.replied`). A registry of event kinds (for example `app.event_kinds(entity, kind)`
read by an `event_kinds_get(p_entity)`) would let the screen take them from the database.

## R-AUTOMATION-06 Asana and Trello steps (AUT-07)
`integration_connections` lists `asana` and `trello`, but `app.wf_kinds` has no step kind for them, so the
builder cannot offer them. Add `asana_task` / `trello_card` kinds (blocked as `not_connected:<provider>` like
Slack) when the design adds them to the palette.
