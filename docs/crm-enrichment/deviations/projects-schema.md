# Projects schema (Phase 6): deviations, message keys, RPCs

Migration `supabase/migrations/0038_projects.sql`, proved by `supabase/tests/phase6_projects_invariants.sql` (203 checks). Spec:
`docs/crm-enrichment/specs/projects-meetings.md` §1, §3.1, §4–§10. Meetings and the AI gateway (§2, §3.2) are Phase 7 and are not here.

## Deviations from the spec

| ID | Where | Spec | Built | Reason |
|---|---|---|---|---|
| V-P6P-01 | Engine: `project_action` | `wf_validate` validates it, `wf_blockers` drops `not_available:projects`, `wf_step` executes it (§3.1, §6, §9.13) | The step is built as `app.wf_project_validate(key, config)`, `app.wf_project_blocker(config)` and `app.wf_project_action(run, workflow, config)`, and tested by calling them directly. `wf_validate`, `wf_blockers` and `wf_step` are **not** redefined, so activating a workflow with a project step still fails with `not_available:projects`, and the Reports tab's hooks say `actions_available: false` (`app.project_actions_wired()` looks for the call in `wf_step`) | 0037 (campaigns) is written in parallel and redefines exactly these three functions for `campaign_action`. Redefining them here would let whichever migration runs last erase the other's step. The merge adds three lines (below) |
| V-P6P-02 | INS-01: `report_run` entity `project` | `report_check` whitelist, dimensions board, phase, health, status, owner, and a duration measure (§1.4, §9.14) | Not wired. The Reports tab has its own RPC (`project_reports`) with the two measures the screen shows | 0037 adds `campaign` to the same whitelist (`app.report_check`, plus `report_dim`). The merge adds `project` together with it (below). **Resolved by 0040** (both entities) |
| V-P6P-03 | LLM connection | A new provider row `llm` (§3.2, Q16) | The existing `ai` row of `app.integration_connections` (0029, R-INBOX-03) | That row already is «the AI provider»; a second row for the same key would split one connection in two. `not_connected` carries detail `ai` |
| V-P6P-04 | `project_ai_summaries.ai_call_id` | References `ai_calls` | Left out | `ai_calls` is Phase 7 (§3.2). The column comes with it |
| V-P6P-05 | `record_files` | No pending state | `ready_at`: `file_upload_begin` makes a pending row, `file_upload_done` makes it ready; only ready rows are listed; `app.files_purge()` (nightly) drops pending rows after a day and removed ones after 30 days, queuing the storage deletes | An upload signed but never confirmed must not appear as a file |
| V-P6P-06 | Files on purge | «The purge job queues the storage delete» | An `after delete` trigger on `app.projects` (`app.record_files_forget('project')`) removes the project's file rows and queues `files_purge`. `app.purge()` is unchanged | A trigger reaches every path that removes a project (purge, sandbox clear) without redefining the generic purge. Other record types attach the same trigger when they get files |
| V-P6P-07 | `activities_get` / `activity_done` accept project rights (§5, §9.12) | Changed | Unchanged. A project's activities are listed in `project_detail` and completed through `project_item_done` with the project's rights (it stamps `done_at`/`done_by`, resets the deal's idle clock and emits `activity.completed`, as `activity_done` does). The calendar does not list them for a Projects-only user | Keeps the deals-scoped activity functions intact; the drawer covers UF-20 step 4 |
| V-P6P-08 | Import (PRJ-08) through `imports` with entities `project`, `project_item` | Built | Not built: `import_run` and `imports.entity` stay as they are. «Paste a list» (`project_items_add`) and export are built | A project row needs a board and a phase the import mapping has no place for yet |
| V-P6P-09 | DOC-01 `[project.start]` | The merge-field registry gains project fields | Not added | `phase5_documents_invariants.sql` asserts the token is unknown until Projects; adding it is a Documents change with its own test |
| V-P6P-10 | `project_template_items` | — | Adds `completes_with_subtasks` | A template must carry the PRJ-03 rule to its projects; «Save as template» would lose it otherwise |
| V-P6P-11 | `project_phase_history` | `board_id uuid`, free `source` | `board_id` not null; `source` in (ui, workflow, system, api, import); `left_at ≥ entered_at` | The duration report reads them |
| V-P6P-12 | Closing a project | — | Closing ends the open stay in its phase (`left_at`); reopening starts a new stay | Otherwise «median days per phase» would count a closed project's last phase until today |
| V-P6P-13 | Activity created from a project | — | Its visibility is the project's; `deal_id` is the primary deal; organisation and person are the project's | The activity belongs to the project's audience; on the deal it shows in the history (ACT-01) |
| V-P6P-14 | Own items | «Item owner or staff assignee may edit and complete their own items» | They may change name, description, dates, `completes_with_subtasks` and done; owner, assignees, group and parent need the project's edit right | Reassigning is the project owner's decision |
| V-P6P-15 | Extra RPCs | Not in §4 | `project_template_get` (the editor), `project_group_delete`, `project_brief_review` (draft → reviewed, PRJ-02), `project_boards_get(p_archived)`, `p_version` on `project_template_save` | States the spec names (template editing, reviewed brief) need a writer or reader |
| V-P6P-16 | Delete right | «projects:delete (own, or with edit_others)» | The generic `rec_delete`: `projects:delete` and visibility, as for every record type | The generic path decides the same way for all types; changing it is a platform decision |
| V-P6P-17 | Status-report filename | — | `status-report-P<seq>-<YYYY-MM-DD>.pdf`, written by `worker_status_report_ready` | The worker sends a path; the name is data, not prose |

### Redefined functions (merge order with 0037)

- `app.entity_route`: the full 0030 body plus `project → /projects` (asked for).
- `public.note_save`: §9.11 — a mention's route comes from the record's screen (`/projects?project=…`; other unlisted types `app.entity_route(e) || '?' || e || '='`, or no route), and only mentioned staff who have the scope's `see` and pass the record's visibility are notified (CRM-06 RU; this applies to deals and the rest too). If 0037 also redefines `note_save`, keep this body: it already routes campaigns generically (`/campaigns?campaign=…`).
- `public.workflow_save`: the 0021 body with `project` added to the trigger-entity whitelist (AUT-02). Nothing else changed.

### The merge snippet (after 0037 lands, in one new migration)

In `app.wf_validate`'s `case`:
```sql
when 'project_action' then perform app.wf_project_validate(k, c);
```
In `app.wf_blockers`, replace the `not_available:projects` line:
```sql
when n.v ->> 'kind' = 'project_action' then app.wf_project_blocker(n.v -> 'config')
```
In `app.wf_step`, split `'campaign_action', 'project_action'`:
```sql
when 'project_action' then
  r := app.wf_project_action(p_run, p_wf, c);
  update app.workflow_run_steps set output = r where id = p_step;
```
INS-01: add `'project'` to `app.report_check`'s entity list; in `app.report_dim` add `board` (`t.board_id`, label from `project_boards`) and `phase` (`t.phase_id`, label and order from `project_phases`); in `app.report_measure` a `duration_days` for project (`coalesce(t.closed_at, now()) − t.created_at` in days). `status`, `health` and `owner` already work through the generic dimension rules.

## Message keys the app must add

Notifications (`app.notify`, kind `system` unless noted; params are ids and staff-written names, never customer text):

| Key | Params | Route |
|---|---|---|
| `project.assigned` | `record`, `actor` | `/projects?project=<id>` — a project made for someone else |
| `project.item_assigned` | `record`, `item`, `actor` (a workflow's name when a workflow assigns) | same |
| `project.phase_changed` | `record`, `phase`, `actor` | same — to followers |
| `project.health_changed` | `record`, `health` (null = not set), `actor` | same — to followers |
| `project.closed` / `project.reopened` | `record`, `status`, `actor` | same — to followers |
| `project.ai_summary_ready` / `project.ai_summary_failed` | `record` | same — to the requester |
| `project.brief_ready` / `project.brief_failed` | `record` | same — to the owner |
| `project.status_report_ready` / `project.status_report_failed` | `record` | same — to the requester |
| `mention` (kind `mention`, existing) | `actor`, `record`, `excerpt` | now `/projects?project=<id>` for a project |

Other keys the screen needs from these RPCs: health `on_track | at_risk | off_track | on_hold` and «not set» (null); status `open | done | canceled`; `brief_state` `none | drafting | draft | reviewed | failed`; item `kind` `task | milestone | activity`; item `source` `paste` («Added from list»); `created_source` `ui | deal | workflow | import | api`; AI reasons `forbidden:projects:ai | forbidden:setting:project_ai | not_connected:ai`; hooks triggers `created, updated, deleted, phase_changed, health_changed, task_completed, milestone_reached, completed` and actions `create_from_template, move_phase, add_tasks_from_template, assign_task`; export column keys (board: `seq, name, phase, status, health, owner, organization, person, deal, starts_on, ends_on, done, total`; project: `kind, name, group, parent, owner, assignees, starts_on, due_on, done, done_at, depends_on`); status-report sections `summary, milestones, done_since, open_overdue, upcoming, note_ids`; workflow blockers `project_template_missing`, `project_phase_missing`; setting `project_ai` (group `ai`, options `on | off`); error details listed per RPC below.

Events (`app.events`, ids and counts only): `project.created {source, template, deal}`, `project.updated {fields, count?}`, `project.deleted`, `project.phase_changed {from, to, board}`, `project.health_changed {from, to, source}`, `project.task_completed {item, kind}`, `project.milestone_reached {item}`, `project.completed {status}`, `project.reopened {status}`, `project.template_applied {template, items}`, `project.status_report_created {file, report}`, `project_item.created|updated|reopened|deleted {project, fields?}`, `file.attached {file}` (subject: the record), `activity.created|completed {project, deal}`, `export.created`.

Jobs on `pgmq` queue `jobs` for the edge workers: `project_ai_summary {summary_id, project_id}` → `worker_project_summary_ready`; `project_brief {project_id, staff_id, deal_id?}` → `worker_project_brief_ready`; `project_status_report {report_id, project_id, ai_draft}` → `worker_status_report_ready`; `files_purge {bucket: 'record-files', paths}`. Storage bucket `record-files` (private) must exist; uploads and downloads are signed by an edge function from `{bucket, path, expires_in}`.

## RPCs for the screen builder

All `security definer`, `search_path = ''`, granted to `authenticated` (workers: `service_role`), each checks `module projects`. Errors: `forbidden` (detail `projects:<action>`, `deals:see`, `setting:project_ai`), `not_found` (also for records the caller may not see; detail `board`, `phase`, `deal`, `summary`, `item` where useful), `invalid` (detail = field: `name`, `starts_on`, `items[3].due_on`, `dependency.cycle`, `status` …), `version_conflict` (detail = current version), `not_connected` (detail `ai`), `module_off`.

### Reads
- `project_boards_get(p_archived boolean default false)` → `[{id, name, ord, archived_at, phases: [{id, name, ord, color, open_projects}]}]`. The chosen board persists with `pref_set('projects', 'board', …)`.
- `projects_board(p_board uuid, p_query jsonb default '{}')` — query `{filters (generic, PIP-12), q, mine, closed}` → `{board: {id, name, archived_at}, phases: [{id, name, ord, color, count}], cards: [card], workflow_hint: {id, name} | null}`. Card: `{id, seq, name, board_id, phase_id, phase_entered_at, status, closed_at, health, health_source, organization_id, organization, person_id, person, starts_on, ends_on, done, total, overdue, owner_id, owner: {name, initials}, deal: {id, title} | null, deals_more, labels, version, is_sample, updated_at}`. `total = 0` → the bar is empty and the label «—».
- `project_detail(p_id uuid)` → card fields plus `{description, brief_state, custom, visibility, created_source, health_set_at, health_set_by, created_at, can_edit, board: {id, name}, phase: {id, name, color}, template: {id, name} | null, deals: [{id, title, is_primary, value, currency, status, stage}] (value/currency/status/stage null without deals:see), groups: [{id, name, ord, phase_id}], items: [{id, kind, name, parent_id, group_id, description, owner_id, owner, assignees: [{staff_id, person_id, name}], starts_on, due_on, done, done_at, late_days, depends_on: [{id, name, kind, lag_days}], completes_with_subtasks, source, ord, version, activity: {id, subject, starts_at, duration_min, type: {key, glyph}} | null, can_edit}], timeline: [{kind: 'note', id, at, author, author_id, body, pinned} | {kind: 'email', id, thread_id, at, author, direction, subject, excerpt}], files: [{id, filename, mime, size_bytes, source, created_at}], sharing: {visibility, group, followers: [{id, name}], following}, ai: {enabled, reason, summary: {id, suggested_health, summary, recommendations, sources, generated_at, applied_at} | null, pending}, status_reports: [{id, state, requested_at, ready_at, file_id, ai_drafted}]}`. Audited, remembered as recent.
- `project_timeline(p_id uuid default null, p_from date default null, p_months int default null)` → `{project: {id, seq, name, starts_on, ends_on, status, organization, can_edit} | null, range: {from, to, days, months: ['YYYY-MM-01' …]} | null, today, today_pct | null, groups: [{id, name, ord, start, end, x, w}], rows: [{id, kind, name, parent_id, group_id, start, end, done, overdue, x, w}], dependencies: [{predecessor, successor, lag_days, violated}]}`. `x`, `w` in percent of the range (null when undated); `p_id` null opens the caller's last opened project.
- `project_templates_get()` → `[{id, name, description, organized_by, board_id, source_project_id, version, updated_at, created_by, creator, groups, tasks, milestones, activities, dependencies, preview: [{day, kind, name}] (first five), can_edit}]`.
- `project_template_get(p_id uuid)` → the same plus `group_list: [{key, name, ord, phase_id}]`, `items: [{key, group, parent, kind, name, start_offset_days, due_offset_days, activity_type, activity_time 'HH:MM', activity_duration_min, assignee, completes_with_subtasks, ord}]`, `dependency_list: [{pred, succ, lag_days}]` (keys are ids, ready to send back to `project_template_save`).
- `project_reports(p_board uuid default null, p_from date default null, p_to date default null)` → `{board_id, from, to, own_only, performance: [{health | null, n, w}] (on_track, at_risk, off_track, on_hold, not set), duration: [{phase_id, phase, board_id, board, n, median_days | null}], hooks: {triggers, actions, actions_available}}`. Default period: the last twelve months by the day a stay ended.
- History: `rec_history('project', id)` (item lines are `items.<item_id>.<column>`). Followers: `follow_set('project', …)`. Notes: `notes_list` / `note_save('project', …)`. Mail: `thread_link(thread, 'project', id)`.

### Projects
- `project_create(p_values jsonb)` — `{name, board_id?, phase_id?, owner_id?, visibility?, labels?, custom?, starts_on?, ends_on?, description?, person_id?, organization_id?, template_id?, deal_ids?}` → `{id, version, seq}`. Template needs `starts_on`.
- `project_create_from_deal(p_deal uuid, p_values jsonb default '{}')` — pre-fills name, person, organisation and the deal; `{draft_brief: true}` queues the AI brief → `{id, version, seq}`.
- `project_move(p_id uuid, p_phase uuid, p_version int default null)` → `{id, version, board_id, phase_id}` (any board's phase).
- `project_health_set(p_id uuid, p_health text, p_version int default null, p_from_summary uuid default null)` → `{id, version, health}`; null clears; with a summary id it is «Use suggestion».
- `project_close(p_id uuid, p_status text, p_version int default null)` — `open | done | canceled` → `{id, version, status}`.
- `project_deal_link(p_id uuid, p_deal uuid, p_on boolean, p_primary boolean default false)` → `{id, version, deals: [{id, title, is_primary}]}`.
- `project_brief_review(p_id uuid, p_version int default null)` → `{id, version, brief_state}`.
- Plain fields: `rec_save('project', id, {name, starts_on, ends_on, description, person_id, organization_id, owner_id, visibility, labels, custom}, version)`; `rec_delete` / `rec_restore('project', ids)`.

### Items, groups, dependencies
- `project_item_save(p_project uuid, p_id uuid, p_values jsonb, p_version int default null)` — `{kind (create: task | milestone), name, description, owner_id, starts_on, due_on, group_id, parent_id, completes_with_subtasks, assignees: [{staff_id} | {person_id}]}` → `{id, version}`.
- `project_item_done(p_id uuid, p_done boolean)` → `{id, done, parent_completed}`.
- `project_items_add(p_project uuid, p_group uuid, p_items jsonb)` — `[{name, due_on?, starts_on?, kind?, owner_id?}]`, 1..200, parsed by the app → `{ids, count}`.
- `project_items_bulk(p_project uuid, p_ids uuid[], p_values jsonb)` — `{owner_id?, shift_days?, group_id?, done?}` → `{updated}` (needs `projects:bulk`).
- `project_items_delete(p_ids uuid[])` → `{deleted}`. `project_items_reorder(p_project uuid, p_ids uuid[])` → `{ok}`.
- `project_activity_add(p_project uuid, p_group uuid, p_values jsonb)` — `{type (key), subject, starts_at (ISO with time), owner_id, duration_min?}` → `{id, activity_id}`.
- `project_dependency_set(p_pred uuid, p_succ uuid, p_on boolean, p_lag int default 0)` → `{ok, violated}`.
- `project_group_save(p_project uuid, p_id uuid, p_name text, p_ord int default null)` → `{id}`; `project_group_delete(p_id uuid)` → `{ok}`.
- `project_group_shift(p_project uuid, p_group uuid, p_days int)` → `{shifted, flagged: [{predecessor, successor}]}`.

### Templates and configuration
- `project_template_save(p_id uuid, p_values jsonb, p_version int default null)` — see `project_template_get` for the shape → `{id, version}`.
- `project_template_from_project(p_project uuid, p_name text)` → `{id, version}`. `project_template_delete(p_id uuid)` → `{ok}`.
- `project_board_save(p_id uuid, p_values jsonb)` — `{name, ord?, archived?, phases?: [{name, color?}] (create only)}` → `{id}`.
- `project_phase_save(p_id uuid, p_board uuid, p_values jsonb)` — `{name, color, ord}` → `{id}`. `project_phases_reorder(p_board uuid, p_ids uuid[])` → `{ok}`. `project_phase_delete(p_phase uuid, p_target uuid)` → `{moved}`.

### AI, reports, export
- `project_ai_summary_request(p_id uuid)` → `{id, state: 'requested'}` (one pending per project).
- `project_brief_request(p_id uuid)` → `{id, brief_state: 'drafting'}`.
- `project_status_report_request(p_id uuid, p_sections jsonb, p_summary text default null, p_ai_draft boolean default false)` → `{id, state: 'requested'}`.
- `project_export(p_board uuid, p_project uuid, p_format text)` — `csv | xlsx`; board or one project → `{format, scope, columns, rows}` (cells starting with `= + - @` are prefixed with `'`). Audited.

### Files (generic, CRM-05; any record type except mail threads and documents)
- `files_list(p_entity text, p_id uuid)` → `[{id, filename, mime, size_bytes, source, uploaded_by, created_at, can_delete}]`.
- `file_upload_begin(p_entity text, p_id uuid, p_filename text, p_mime text, p_size bigint)` → `{id, bucket: 'record-files', path, expires_in}`; PDF, PNG, JPEG, DOCX, XLSX, PPTX, CSV, TXT up to 25 MB, extension matching the type.
- `file_upload_done(p_id uuid)` → `{id}`. `file_download_url(p_id uuid)` → `{bucket, path, expires_in, filename, mime}`. `file_delete(p_id uuid)` → `{ok}`.

### Workers (service role)
- `worker_project_summary_ready(p_id uuid, p_result jsonb)` — `{state: 'ready' | 'failed', suggested_health, summary (≤ 4000), recommendations: [text ≤ 300] (≤ 5), sources: [{entity, id, kind}]}` → `{ok}`.
- `worker_project_brief_ready(p_project uuid, p_text text)` — null text = failed → `{ok}`.
- `worker_status_report_ready(p_report uuid, p_storage_path text, p_size bigint)` — path `project/<project_id>/….pdf`, null = failed → `{ok, file_id}`.

## Left open
- (The merge snippet: V-P6P-01 resolved by 0039, V-P6P-02 by 0040.)
- The edge functions: the upload/download signer for `record-files`, the PDF worker, the AI worker, the `files_purge` consumer.
- No seed: no boards, projects or templates are seeded; the screen starts in its «no boards yet» state until a seed module is added (`scripts/seed/…` is outside this task).

## Added by 0040 (Phase 6 requests)

- `project_templates_get` / `project_template_get`: `preview[].day` is a task's start offset when it has one, else its due offset; a milestone's or activity's due offset.
- Provider `pdf` in `app.integration_connections`; `project_pdf_status()` (see) → `{pdf_connected}`.
- `report_run` entity `project`: dimensions `board`, `phase`, plus `status`, `health`, `owner`; measure `{fn: 'duration_days'}` (unit `days`); type `duration` = the average duration. `report_fields('project').measures = ['duration_days']`.
