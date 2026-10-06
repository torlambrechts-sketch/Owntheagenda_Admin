# Deviations — Automation

Where the Automation screen (`app/(admin)/automation`) departs from `design-reference/sentral/project/Automation.dc.html`,
and why. Every value the spec (`specs/inbox-feed-automation.md` §3) marks FAB is replaced from the engine
(`0021_engine.sql`, `0026_engine_followups.sql`) or not rendered. The seed holds configuration and no runs, so
every run figure is zero and every run list shows its empty line.

| ID | Where | Design | Built | Reason |
|---|---|---|---|---|
| V-AUTOMATION-01 | Header line | «loop protection on (safeguard)» fixed | «on»/«off» from the `safeguards` setting | Never fabricate |
| V-AUTOMATION-02 | Workflows › Runs 7 d, Failed | 42, 61, 18 … and 3, 1 failed | `runs_7d` / `failed_7d` from `workflow_runs` (0 in the seed) | FAB (spec §3) |
| V-AUTOMATION-03 | Workflows › State | Seven of eight active | The stored state; a draft lists its blockers (`wf_blockers`) in red under its description | A workflow whose step cannot run is refused activation (UF-11); the screen says why |
| V-AUTOMATION-04 | Workflows › Transfer | Always to Ingrid, toast only | A staff picker of active people with Manage workflows in the workflow's scope; `workflow_transfer` notifies both and audits | AUT-10; FAB |
| V-AUTOMATION-05 | Workflows | — | No «owned by me / by others» filter | Not in the design (AUT-10); `workflows_get({mine})` supports it when a design arrives |
| V-AUTOMATION-06 | Workflows › Activate | Toggles locally | `workflow_set_state`; a refusal is a toast with the reason (Slack not connected, project actions not available, no mailbox, the enrolled sequence is a draft, the limit) | UF-11 |
| V-AUTOMATION-07 | Builder › canvas | One hard-coded workflow | The selected workflow's stored graph (the first in the list when none is chosen); the trigger node from `trigger_type`/`trigger_config`; If/else paths labelled «If {condition}» and «Else» | FAB; the graph has no path labels |
| V-AUTOMATION-08 | Builder › saving | Every «＋» flashes «Step added · draft saved» | Edits are a draft; Save (publishes a version through `workflow_save`) and Discard replace Activate in the header while there are changes; a refusal highlights the step and field it names | A new step must be configured before the graph validates; publishing on every keystroke would fill `workflow_versions` |
| V-AUTOMATION-09 | Builder › «＋» connectors | Each adds a step | Each selects where the next palette step goes (the palette otherwise adds after the selected step); no connector after the last step, as drawn | The design's connectors had no target |
| V-AUTOMATION-10 | Builder › config panel | Read-only inputs holding prose | Editable fields per step kind (`app.wf_validate`): a condition editor (groups of field · operator · value, OR between groups), selects for templates, sequences, categories, activity types and owners, raw JSON for record values and the webhook body | The inputs were not wired in the prototype (spec §3) |
| V-AUTOMATION-11 | Builder › config panel | — | «Remove step» | A real editor must be able to remove a step (D-41) |
| V-AUTOMATION-12 | Builder › palette | 14 items | The design's 14, then the engine's other actions (Create activity, Notify, Enroll in sequence, Assign owner, Create ticket, Invoice in accounting); Campaign action and Project action are shown disabled («Not available yet», phases 5–6) | The canvas itself shows activity and invoice steps; D-41 |
| V-AUTOMATION-13 | Builder › palette | — | No Asana or Trello step | AUT-07 names them, but they are not in the design's palette and `app.wf_kinds` has no such step kind (R-AUTOMATION-06) |
| V-AUTOMATION-14 | Builder › Slack, Teams, accounting steps | Look configured | «Not connected» on the node and in the panel note; activation is refused with the reason | No OAuth connection exists (spec §7) |
| V-AUTOMATION-15 | Builder › note | «Actions and delays per path: unlimited (setting)» | From `count_limits`: «unlimited», or the number set | D-16 |
| V-AUTOMATION-16 | Builder | — | No «Test run» | None in the design (brief) |
| V-AUTOMATION-17 | Templates | Names and descriptions in the script | The engine's seeded templates by key, with names and descriptions in messages; «Use template →» creates a draft (`workflow_from_template`) and opens it in the builder | Configuration as data |
| V-AUTOMATION-18 | Monitoring › health cards | 214 · 99,1 %; 1 482 · 12 failed · 4 retried; 2 910 · trend stable | `workflow_monitor` (today, d7, d14). With no runs: «0», «No runs today», «No runs in 14 days» — no percentage over zero runs. Trend: last 7 days against the 7 before, ±10 % reads rising/falling | FAB (spec §3); the ±10 % band is the screen's own reading of «stable» |
| V-AUTOMATION-19 | Monitoring › Loop protection | «On · Source values» | From `safeguards`: On/Off, «Source values», «Custom · n runs per 10 minutes», «Switched off»; adds «n blocked in 7 days» when any | Setting-driven (A9) |
| V-AUTOMATION-20 | Monitoring › overview | Fixed names and counts | `most_failed`, `most_active`, `never_run`; an empty list says so | FAB |
| V-AUTOMATION-21 | Monitoring › run history | Four fixed runs; Retry turns every chip green | `workflow_runs_get` (50 newest) with each record's title; a «Trigger» chip first (a run exists only when its trigger fired), then one chip per recorded step, its error as the tooltip; Retry calls `workflow_run_retry` (a new attempt from the failed step) and reports the resulting state | FAB (spec §3) |
| V-AUTOMATION-22 | Assignment › Test a record | Source, Employees, Organization exists; could never reach rule 1 | Adds Record type (rule 3 applies to deals only) and Organization label, so every rule can match; the result is `assignment_test` (read-only, the rotation does not move). Typed facts carry no owner, so an owner rule reads «Assigned to the organization’s owner» | Spec §3 |
| V-AUTOMATION-23 | Assignment › rules | Fixed list, local reorder | Assignment workflows; ▲▼ call `assignment_rules_reorder`; a draft rule carries a Draft chip | FAB |
| V-AUTOMATION-24 | Assignment | — | A rule dialog (name, record types, sources, employees, organization exists, organization labels, assignee, active, delete) opened from a rule's name, and «＋ Add a rule» | Rules must be configurable (AUT-11); D-41 |
| V-AUTOMATION-25 | Assignment | — | «Recent assignments» card under the test (`assignment_history`) | AUT-11: the history is required though not designed |
| V-AUTOMATION-26 | Sequences › list | «38 / 12 / 61 enrolled» | `counts.in_progress` from `sequence_get` (0); the subtitle is the stored description | FAB |
| V-AUTOMATION-27 | Sequences › steps | Literal titles and «Day 0 / Day 2 / Same day» | From the graph: the template's name, the delay and its weekend rule, the activity; «Day n» summed from the delays before the step | FAB |
| V-AUTOMATION-28 | Sequences › Enrolled | Four fixed rows | `sequence_get.enrolled` with step, how enrolled and state; an empty line when nobody is enrolled | FAB |
| V-AUTOMATION-29 | Sequences › «＋ Enroll a deal», «Enroll in bulk» | Adds «Granli Eiendom — Pilot n»; «12 deals from «Proposal sent» enrolled» | A record picker (search) for one; a saved view of the Deals or Leads screen, or several picked records, for bulk (`sequence_enroll`). Both are disabled while the sequence is a draft | FAB |
| V-AUTOMATION-30 | Sequences | — | A draft notice under «Enrolled» with the blockers and «Activate» | The seeded sequences are drafts (no mailbox, V-25); without this they could never be switched on |
| V-AUTOMATION-31 | Sequences › Enrolled | — | «Skip step» and «Exit» on rows in progress (a fifth column, only when such rows exist) | The spec requires skipping and stopping to be supported |
| V-AUTOMATION-32 | Sequences | — | No step editor for sequences | The design has none; sequences keep their seeded steps |
| V-AUTOMATION-33 | 390 px | The prototype does not reflow | Tables scroll inside their cards; the builder, assignment and sequence columns stack | The design has no mobile layout for this screen |
