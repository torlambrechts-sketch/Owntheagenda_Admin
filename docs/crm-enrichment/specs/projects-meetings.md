# Data-requirements spec: Projects and Meetings (Sentral)

Sources read in full: `design-reference/sentral/project/Projects.dc.html` and `Meetings.dc.html` (markup and logic), `admin-data.js`, `coverage-data.js` (PRJ-01..09, MTG-01..08, and every feature that names projects, meetings, recordings, transcripts or calendars: ACT-01/03/09, COM-02/10/11, CRM-05/06, CUS-01/07, PIP-12, AUT-02/07/08, INS-01, SEC-07/08/11, AIA-03, INT-05/06/07, DOC-01, MOB-06/08, ENT-01; flows UF-07, UF-20, SF-02, SF-04, SF-07, SF-08, SF-15, SF-21, SF-24, SF-33, SF-34, SF-40, SF-42), `docs/crm-enrichment/DECISIONS.md`, `05-GAP-FEATURES.md` (Part 3 rows, Part F entities and events, Part G), `06-QUESTIONS.md` (Q-27, Q-38, Q-39, Q-41), `07-IMPLEMENTATION-PLAN.md`, `INSTRUCTIONS.md` (A7, Part F, Part G), and migrations 0001–0026. I also grepped the other screens for references to these two: Settings (module and permission matrix), Security (retention, sub-processors, erasure), Automation (the «Won deal → project» workflow) and Insights (the Projects report entity).

**Overall finding.** Neither screen computes anything from records.

*Projects.* Seven projects are hard-coded in `componentDidMount`: name, phase, health, done/total counts and a short deal label. Every card shows the same dates, "5 Oct – 18 Dec". The board selector changes only the text in the drawer header. It filters nothing, and every board has the same four phases. The Gantt is one fixed plan for one project. Templates, durations, the AI banner, the work items, notes and files are all literals. Two things are computed: the phase column counts and the "Project performance" counts. Both run over the seven literals.

*Meetings.* All four meetings are literals, and so are the brief, transcript, recap and six suggestions. Every meeting shows the same transcript, including upcoming meetings when that tab is opened. The per-user switches, notice choice, checklist ticks and suggestion decisions live only in component state. Nothing is written. Every toast on both screens is **fabricated**.

None of the providers meeting intelligence needs is connected: meeting bot, transcription, desktop app and the LLM key (D-07, D-38). The honest default for the real build is therefore:
- Projects works fully without any provider, except its three AI actions.
- Meetings works as a calendar-fed workspace with deterministic briefs and transcript upload. Everything that records, transcribes or generates shows `not_connected` and is never faked.

What exists today that these screens build on:
- the `projects` and `meetings` module switches (0005), the `rec_notice` setting (0005) and the `ai_scoring` precedent (0022);
- the `projects` rights scope with the «Regular — Projects» preset (0003);
- `activities`, `activity_guests`, `calendar_connections` and `booking_links` (0010);
- `notes` and `followers` (0009);
- `email_links`, which already accepts `project` (0020);
- the engine with a `project_action` step kind that today always blocks with `not_available:projects` (0021, 0026), plus the `won_project` workflow template;
- `integration_connections` with its `not_connected` status (0021, 0022).

Nothing for boards, projects, tasks, templates, meetings, recordings, transcripts, files or an AI call log exists yet (D-01: all of it is built new).

---

## 1. Projects screen (route `projects`, PRJ-01..09, UF-20, SF-42)

### Views and states
- **Toolbar:**
  - Tab pills: Board (default), Timeline, Templates, Reports.
  - Board `<select>`.
  - Hint "Workflow «Won deal → project» creates projects automatically".
  - "＋ Project" button.
- **Board:** phase columns (260 px) with a count and a coloured underline. Cards are draggable between columns.
- **Timeline:** a Gantt with month columns, a phase bar and task, milestone and today markers, and a legend ending "Drag a phase bar to shift everything in it". There are no handlers at all: the bars cannot be dragged and no dependency lines are drawn.
- **Templates:** template cards with "Use template".
- **Reports:** "Project performance" by health, "Duration by phase (median days)", and an "Automation hooks" text card.
- **Project drawer (overlay):**
  - Header: board · phase · owner, title, org · person · ◆ deal · dates.
  - Health select. "AI status report (PDF)". Close.
  - AI suggestion banner.
  - Work items list with "Paste a list" (textarea + "Add tasks") and "＋ Task".
  - "Notes, mentions and emails".
  - "Files and sharing".
- **Toast.**

States the design lacks, to build in the design's language (D-41):
- loading;
- no boards yet: an empty board with a "New board" card for `projects:configure`, and a plain empty message for others;
- an empty phase column;
- a project with no work items;
- an empty timeline (no dated items);
- no templates;
- reports with no projects;
- no permission: without `projects:see` the route and nav item are absent, and the module-off state follows CUS-07;
- AI not connected or switched off (§1.5);
- a closed project (done/cancelled, read-only header with a Reopen action);
- the timeline's project picker (the design shows one fixed project);
- a group picker for "Paste a list" (PRJ-08: "Pasted lines become tasks in the chosen phase");
- "Save as template" (PRJ-05) and template editing;
- "Regenerate" on the AI summary (PRJ-06);
- a note composer with @mention (PRJ-07);
- an upload control in "Files and sharing";
- an overdue highlight on the timeline (PRJ-04);
- a subtask control (Q-41 lists subtasks as missing).

### 1.1 Board: figures, source and formula

| Element | Prototype | Real source / formula |
|---|---|---|
| Board options | **Fabricated** (three literal names). Selecting one filters nothing | `project_boards where archived_at is null order by ord`. The selection persists per user in `view_prefs (screen 'projects', key 'board')` |
| Phase names, order, colour | **Fabricated**: the same four phases (Kickoff, Setup, First survey, Handover) and four colours on every board | `project_phases where board_id = :board order by ord`; colour from `project_phases.color` |
| Column count | Real logic over the seven literals | `count(*) from projects where board_id = :b and phase_id = :p and status = 'open' and deleted_at is null` and visible (`app.visible(owner_id, visibility)`), plus sandbox filtering as everywhere else |
| Card title | Literal | `projects.name` |
| Health pill | Literal per project | `projects.health`, coloured by the design's map: on_track `#CFE7E4/#20431C`, at_risk `#F5DC96/#5C4600`, off_track `#F0B9A0/#6B240C`, on_hold `#EFE6D2/#5F5849`. When null, no pill (see open question 1) |
| Org name | demo org from a literal id (`o1` …) | `organizations.name` via `projects.organization_id`; omitted when null |
| Dates "5 Oct – 18 Dec" | **Fabricated** (same on every card) | `starts_on – ends_on` in the viewer's locale; one side omitted when null |
| Progress bar, "5/14" | **Fabricated** (literal `done`/`total`) | `done = count(*) filter (where done)`, `total = count(*)` over `project_items where project_id = :id and kind in ('task','milestone') and deleted_at is null` (subtasks count; activities don't). With total = 0 the bar is empty and the label is "—" |
| Owner first name | staff name from `admin-data` | `admins.name` of `projects.owner_id` (first word, as the design shows) |
| "◆ Lumio — Skiftly" | **Fabricated** (short labels that match no deal) | Title of the primary deal (`project_deals.is_primary`). The "◆" segment is omitted when no deal is linked |
| Hint "Workflow «Won deal → project» creates projects automatically" | Literal | Shown only if an **active** workflow has a `project_action` step with `action = 'create_from_template'`; its name is shown. Otherwise hidden (precedent V-DEALS-15) |

### 1.2 Timeline

| Element | Prototype | Real source / formula |
|---|---|---|
| Title "Lumio AS — Skiftly onboarding" | **Fabricated** (always the same project) | The project chosen in a picker (D-41). Defaults to the most recently opened project (`recents`), then the first card on the board |
| Months October–January | **Fabricated** | Range R = [month start of min(`projects.starts_on`, item starts/dues), month end of max(`ends_on`, item dues)], with at least 3 months shown |
| Group ("phase") rows and bars | **Fabricated** offsets (`G` array) | One row per `project_groups` row. Bar = [min(`starts_on`, `due_on`), max(`due_on`)] of the group's items. x% = (start − R.start) ÷ R.days × 100; w% = (end − start + 1) ÷ R.days × 100 |
| Task rows | **Fabricated** | `project_items` kind task (subtasks indented). Bar from `starts_on` to `due_on`; a one-day bar when only `due_on` is set; listed without a bar when undated |
| Milestone ◆ | **Fabricated** | kind milestone, placed at `due_on` |
| Activity rows | not shown | kind activity at `activities.starts_at` (◷), as in the drawer |
| "↳ depends on the row above" | Legend only; ↳ actually marks indentation | Dependency lines drawn from `project_item_dependencies` (predecessor end → successor start). The legend should read "→ depends on" (log in DEVIATIONS) |
| Today line at 3.5 % | **Fabricated** | (today in the viewer's time zone − R.start) ÷ R.days × 100; hidden outside R |
| Overdue | not shown | `not done and due_on < today` → the design's red ink `#A33A16` (PRJ-04 RU) |

### 1.3 Templates

| Element | Prototype | Real source / formula |
|---|---|---|
| Three templates | **Fabricated** | `project_templates where deleted_at is null order by name` |
| Summary "4 phases · 14 tasks · 3 milestones · due dates relative to start" | **Fabricated**, and inconsistent with the four items listed under it | Computed: `count(groups)` (called phases or groups by `organized_by`), count of task items, count of milestone items, plus "dependencies" when any exist |
| Item lines "Day 3 · Upload employee list", "Day 11 ◆ …" | **Fabricated** | The first five `project_template_items` by (`due_offset_days`, `ord`). "Day N" = `due_offset_days`, falling back to `start_offset_days`; ◆ for milestones |

### 1.4 Reports

| Element | Prototype | Real source / formula |
|---|---|---|
| Project performance (counts per health) | Real logic over the seven literals. Bar width `v × 22 %` is an arbitrary scale that overflows at five | `count(*) group by health` over open, visible projects on the selected board (or all boards), including a "Not set" bucket. Width = v ÷ max(v) × 100. Without `projects:reports_others`, own projects only (the Insights rule, 0024) |
| Duration by phase (median days) | **Fabricated** (9/16/21/6) | Per phase: `percentile_cont(0.5) within group (order by left_at − entered_at)` in days over `project_phase_history` rows with `left_at is not null`, in a period (default 12 months). Show n; a phase with n = 0 shows "—" |
| Automation hooks text | Static promise | It must be true at ship: triggers project created, phase changed, task completed, milestone reached; actions create project, move phase, add tasks from template, assign task (§6). Render it from the engine's registry, not as prose |

PRJ-09/INS-01: the same two measures become Insights report types. `app.report_run` must add `project` to its entity whitelist (0024 l.204), with dimensions board, phase, health, status and owner, and a duration measure (`ends_on`/`closed_at − created_at`).

### 1.5 Project drawer

| Element | Prototype | Real source / formula |
|---|---|---|
| "Customer onboarding · Kickoff · owner Emma Lie" | Uses the **toolbar's** board, not the project's (bug) | `project_boards.name` · `project_phases.name` · owner name |
| Org · person · ◆ deal · "5 Oct – 18 Dec 2026" | Names from demo data; deal label and dates **fabricated** | `organization_id`, `person_id`, primary deal title (more deals: "+N"), `starts_on – ends_on`. A project-only user sees titles only (open question 6) |
| Health select | Four options; the choice is kept in state only | `projects.health`, written by `project_health_set` |
| AI banner "Suggested: At risk. The employee import is 4 days late …" | **Fabricated**, identical for every project | Latest `project_ai_summaries` row with `state = 'ready'`: suggested health, summary, up to five recommendations, `generated_at`, cited sources. Rendered only if setting `project_ai = on`, the caller has `projects:ai`, and the `llm` connection is connected. Otherwise the banner is absent; clicking an AI action then shows the `not_connected` message. D-41 adds "Regenerate" and "Use suggestion" (sets health with `health_source = 'ai_suggestion'`) |
| Work items: names, glyphs | **Fabricated** (six fixed rows + pasted extras) | `project_items` ordered by group, `ord`; subtasks under their parent (40 px indent); ◆ milestone, ◷ activity (`activities.subject`) |
| "Kari Nordmann · Mona Hansen" (who) | **Fabricated** | `project_item_assignees`: staff and, per open question 2, customer-side people. Falls back to `owner_id`, else "Unassigned" |
| Due "Done", "4 days late", "16 Oct", "Thu 10:00" | **Fabricated** (the lateness is a literal string) | done → "Done"; `due_on < today` and not done → "N days late" (N = today − `due_on`, red); a date otherwise; an activity shows `starts_at` as weekday + time |
| Dependency column "Depends on «Upload employee list»", "Depends on milestone", "Activity", "Added from list" | **Fabricated** | The first predecessor's name ("Depends on «X»", "+N" for more). "Activity" for kind activity. "Added from list" is `source = 'paste'` (real provenance, kept) |
| Done toggles | Kept in state; not cascaded | `project_item_done`. A parent is not auto-completed unless its `completes_with_subtasks` is true (PRJ-03 A) |
| Notes, mentions and emails | **Fabricated** (one is Kari's email in Norwegian) | Merged, newest first: `notes where entity = 'project' and record_id = :id`, plus messages of threads in `email_links (entity 'project')` that the caller may see (`app.thread_visible`: private threads stay private, COM-02). An email shows the sender's name with "(email)" |
| Files | **Fabricated** (two files with sizes) | NEW `record_files where entity = 'project'`: filename and size. Status-report PDFs land here too |
| "Shared with Delivery team · Emma Lie, Magnus Berg" | **Fabricated** | The project's visibility, rendered as the owner's visibility group name for `group`/`group_sub`, "Everyone" for `all`, "Only the owner" for `owner`, plus the project's followers by name (`followers where entity = 'project'`). No separate sharing table, so every generic path (notes, files, mail links, search) applies the same rule |

### 1.6 Actions: what each does for real

| Action | Behaviour | Right | Event / history |
|---|---|---|---|
| ＋ Project | A dialog in the design's language (D-41): name (required), board, phase (default: first), owner (default: me), start and end, deal(s), person, organization, template (optional), description. The prototype only toasts "Project created · link a deal …" and creates nothing | `projects:add`; linking a deal needs it visible (`deals:see`) | `project.created`; changelog `*created` |
| Create from a won deal (deal drawer, D-41) | Pre-fills person, organization and the deal; optional template. With "Draft brief", queues an AI brief from the deal's notes, linked emails and files into `description` with `brief_state = 'draft'`. The user reviews it, then `brief_state = 'reviewed'` (PRJ-02) | `projects:add` + `deals:see`; the brief needs `projects:ai` and an LLM | `project.created` (payload `source: 'deal'`) |
| Use template | Opens ＋ Project with the template chosen; then `project_create` instantiates it (below). The prototype toasts "Project created from «…»" and creates nothing | `projects:add` | `project.created`, `project.template_applied` |
| Template instantiation | One transaction: create groups; create items with `starts_on = project.starts_on + start_offset_days` and `due_on = starts_on + due_offset_days` (calendar days, open question 4); create activities (type, start date + offset at `activity_time`, `duration_min`, owner = project owner) with their `project_items` rows; copy dependencies. Without a start date: refuse with `invalid` (detail `starts_on`), since PRJ-05 A says "gets dated items from its start date" | | |
| Drag a card to another phase | `project_move(id, phase_id, version)`: sets `phase_id`, `phase_entered_at`, closes and opens `project_phase_history`, writes changelog `phase_id`. Optimistic, rolled back on error. A cross-board move happens only in the drawer, by choosing a phase from another board | owner or `projects:edit_others` | `project.phase_changed` (`from`, `to`) |
| Health select | `project_health_set(id, health, version)`; `health_source = 'manual'` | owner/edit_others | `project.health_changed`; changelog |
| AI status report (PDF) | D-41 dialog: tick the sections to include (summary, milestones, done since date, open and overdue, upcoming, selected notes) and edit the summary. "Draft with AI" fills the summary (needs the LLM). Render the PDF server-side, store it as a `record_files` row (source `status_report`), and show it in Files. PRJ-07: "the PDF contains only what the sender chooses". Sending it to the client is a separate mail action (COM, needs a mailbox). Without the LLM the report still works with a hand-written summary | `projects:see` on the project; AI draft needs `projects:ai` | `project.status_report_created` |
| Paste a list → Add tasks | Each non-empty line becomes a task in the chosen group. A trailing or leading date (`16.10`, `16.10.2026`, `16 Oct`, `16. okt`, `2026-10-16`) becomes `due_on` and is stripped from the name (PRJ-08 RU). Parsing is done by a pure TypeScript function with a preview; the RPC takes the structured list (≤ 200). `source = 'paste'` | owner/edit_others | one `project.updated` (fields `items`); changelog per item |
| ＋ Task | Inline row: type a name, Enter creates it. No "New task" placeholder row is written | same | `project_item.created` |
| Toggle done | `project_item_done(id, done)`. A milestone also emits `project.milestone_reached`. An activity item calls the activity path (stamps `done_at`/`done_by`, touches the deal's idle clock, ACT-01) | item owner or assignee, project owner, or edit_others | `project.task_completed` / `project_item.reopened` |
| Dependencies (D-41, item menu and timeline) | `project_dependency_set(pred, succ, on, lag_days)`. Refused with `invalid` (detail `dependency.cycle`) when it would close a cycle (PRJ-04 RU); only tasks and milestones of the same project | owner/edit_others | changelog |
| Drag a group bar (timeline) | `project_group_shift(project, group, days)`: shifts `starts_on` and `due_on` of every dated item in the group by the same number of days. Spacing is kept (PRJ-04 A). Successors are not moved automatically (open question 3); a successor that now starts before its predecessor ends is flagged | owner/edit_others | one changelog entry per item |
| Bulk edit (D-41: select rows) | owner, assignee, due-date shift, group, done | `projects:bulk` | changelog per row |
| Note with @mention | `note_save('project', …)`; mentioned staff are notified only if they may see the project (CRM-06 RU). Needs a fix to `note_save` (§9.11) | `projects:see` | `note.created` |
| Upload file | `record_files` via a signed upload URL; type and size checked (A7.5). Download only through `file_download_url`, which checks the project's visibility (CRM-05 A) | owner/edit_others to upload; see to download | `file.attached` |
| Save as template (D-41) | Copies groups, items (offsets = item date − project `starts_on`), activities (offset + time of day) and dependencies into a new template with `source_project_id` | `projects:add` (own template); editing others' needs `projects:configure` | audit `template.saved` |
| Close / reopen (UF-20 step 6) | `project_close(id, 'done' | 'canceled' | 'open')` | owner/edit_others | `project.completed` / `project.reopened` |
| Export / import (PRJ-08) | Export of the board, or of one project's items, to CSV/XLSX with formulas neutralised (A7.6), audited. Import goes through the existing `imports` pipeline with entities `project` and `project_item`. Other tools (Asana, Trello) are handled first as CSV mappings; their APIs later | `projects:export`; import `projects:add` | `export.created` |

### 1.7 Feature and flow IDs on this screen, with their acceptance tests

| ID | Acceptance test (coverage-data.js) | Where it is met |
|---|---|---|
| PRJ-01 Boards and phases | Dragging a project changes its phase and logs it | `project_move`, `project_phase_history`, changelog |
| PRJ-02 Project record | A project created from a deal shows the deal and its contacts | `project_create_from_deal`, `project_deals`, person/org links |
| PRJ-03 Work items | Completing all subtasks does not auto-complete the parent unless set | `project_items.completes_with_subtasks` |
| PRJ-04 Dependencies and timeline | Shifting a phase keeps the spacing between its items | `project_group_shift`; cycle trigger |
| PRJ-05 Project templates | A project from a template gets dated items from its start date | template instantiation |
| PRJ-06 Project health | The status shows on the board and in reports | `projects.health`, the board pill, the Reports tab, Insights |
| PRJ-07 Collaboration and sharing | A mention on a project notifies the user | `note_save` route fix + visibility check |
| PRJ-08 Bulk work and import | Pasted lines become tasks in the chosen phase | `project_items_add` with `group_id` |
| PRJ-09 Automation and reports | A workflow can create a project when a deal is won | `project_action create_from_template`; `won_project` template |
| ACT-01 Activities (link to project) | A completed activity shows in the linked record's history | `activities.project_id`; project history |
| ACT-03 Calendar (project tasks beside activities) | Rescheduling in the calendar updates the activity and any synced calendar event | `activities_get` accepts `project_id`; the calendar may also list dated `project_items` (read-only) |
| CRM-05 File attachments (projects) | A user who cannot see the record cannot fetch the file | `record_files` + `file_download_url` |
| CRM-06 Notes, mentions | A mentioned user gets a notification that opens the record | route `/projects?project=<uuid>` |
| CUS-01 Custom fields (projects) | A new field appears in forms, filters, reports, import and the API without a deploy | entity `project` in `app.entities`; `custom` jsonb |
| PIP-12 Filters (projects) | A saved filter returns the same set in pipeline, list and forecast views | `saved_views (screen 'projects')`; board and timeline share one predicate |
| COM-02 Email (projects) | Mail sent from either the CRM or the mail client appears in both | `email_links entity 'project'` (exists) |
| AUT-02 Event triggers (project added/updated/deleted) | Each of the 18 entity-event pairs can start a workflow | `project` added to the trigger whitelist (0021 l.1181) |
| AUT-07 Actions (project actions) | Every action type completes or reports an error in the run history | `project_action` executor |
| AUT-08 Workflow templates (Won → project) | A template becomes an editable workflow | `won_project` (exists) once the step is unblocked |
| INS-01 Report types (projects performance, duration) | Each of the 17 report types returns figures that match the underlying list view | `report_run` whitelist + project dimensions |
| SEC-07 / SEC-08 | An action missing from the set is refused in the UI and the API; a user outside the group cannot read the row | `app.require('projects', …)`, `app.visible` |
| DOC-01 placeholder `[project.start]` | A generated document contains the deal's data | the merge field registry gains project fields (Documents spec) |
| MOB-08 Project tasks on mobile | A rep can answer a live chat from the phone (the test does not cover tasks) | later; the same RPCs |
| UF-20 Hand over a won deal | steps 1–6 | §1.6; step 2 needs the LLM |
| SF-42 Project lifecycle | steps 1–6 | §1.6; step 4 (drag a phase) maps to `project_group_shift` |

---

## 2. Meetings screen (route `meetings`, MTG-01..08, UF-07, SF-21)

### Views and states
- **Toolbar:**
  - Tab pills: Workspace (default), Ways to capture, Workspace and controls.
  - "● Record unscheduled call" and "Upload transcript".
- **Workspace:**
  - Left: three grouped lists, Upcoming, Needs your review and History. Each item shows when, a state label, title, and org · via.
  - Right:
    - Header: when · via · attendees, title, "Linked to …", state pill, notice line.
    - Three tabs: Pre-call brief (default for Upcoming), Transcript and recap (default otherwise), CRM update suggestions.
- **Ways to capture:** four cards (Notetaker bot, Desktop capture, Unscheduled calls, Transcript upload), each with a CTA.
- **Workspace and controls:**
  - Per-user switches with "mailbox own" or "meetings@ (re-auth)".
  - The three recording-notice options.
  - A firewall note.
- **Toast.**

States the design lacks (D-41):
- loading;
- no meetings (no calendar connected → a "Connect calendar" link to Activities › Reminders and sync);
- an empty group;
- no meeting selected;
- workspace switched off for this user (MTG-08 A: "a user without the permission sees no meeting workspace", so the nav item and route are absent);
- module off;
- a meeting with no transcript ("No recording" / "Recording blocked: <reason>");
- a transcript still processing; transcription failed with "Retry" (SF-21.7);
- a recap or brief quotes not available because the LLM is not connected;
- no suggestions;
- a stale suggestion (the record changed since the proposal);
- an unlinked meeting flag with a "Link to deal…" picker (MTG-01 RU, MTG-07 A);
- "Remove bot" (MTG-02 RU; Q-41 lists it);
- "Stop and delete recording" (UF-07 step 3);
- an attendee opted out;
- speaker mapping for uploaded transcripts;
- "Brief instructions" per user (MTG-01 RU);
- "Draft follow-up" and "Plan next activity" from the recap (UF-07 step 6, AIA-03, ACT-07);
- the bot auto-join choice behind "Configure".

### 2.1 List and header: figures

| Element | Prototype | Real source / formula |
|---|---|---|
| Four meetings (when, title, org, via, attendees, linked record) | **Fabricated** (array `M`) | `meetings` visible to the caller (owner, visibility, or staff attendee), not deleted, sandbox-filtered |
| Group | literal `g` | Upcoming: `starts_at > now()` and not cancelled. Needs your review: a ready transcript and (pending suggestions > 0 or a recap not yet saved). History: the rest, newest first, paged |
| "via" ("Google Meet · notetaker", "Desktop capture · phone") | **Fabricated** | `meetings.conference` (meet/teams/zoom/phone/in_person) · `capture` (bot → "notetaker", desktop, upload, none) |
| State label and pill ("Bot joins", "Notice due tomorrow", "6 suggestions", "Recap saved") | **Fabricated** | Derived in this order: `bot_state='blocked'` → "Recording blocked"; upcoming and `notice_state='pending'` → "Notice due <relative day of notice_due_at>"; upcoming and bot scheduled → "Bot joins"; transcript processing → "Processing"; pending suggestions n > 0 → "n suggestions"; recap saved → "Recap saved"; transcript ready → "Recap ready"; else none |
| Notice line ("Recording notice sent 24 h before", "Notice goes out Thu 13:30", "Recorded without a bot", "Recap saved as note") | **Fabricated** | `notice_sent_at` and the setting's hours; `notice_due_at`; `capture='desktop'`; `meeting_recaps.saved_at` |
| Attendees "Ole Hansen, 4 others" | **Fabricated** | `meeting_attendees` (external first): the first name, then "N others" |
| "Linked to <b>Lead L-501 · Kystlinje Transport</b>" | **Fabricated** | The deal title, else the lead number + title, else person, else organization; none → "Not linked" flag + picker |

### 2.2 Pre-call brief (MTG-01)

The brief is built **from records first, AI second**. Facts are computed deterministically and stored with their source (MTG-01 A: "cites its sources"). The LLM is used only for the "From earlier conversations" quotes and an optional one-line framing. So a brief exists before every linked meeting even with no LLM connected.

| Element | Prototype | Real source / formula |
|---|---|---|
| "Since the last contact" (5 items) | **Fabricated** | Last contact = max(done activity, email message, meeting) touching the linked deal/lead or any external attendee, before now. Items since then, each `{kind, params, source}` rendered from message keys (never prose): changelog entries on the deal/lead/org/people (field, old → new: "Board meeting fixed for 14 October" is a custom-field change); `email_tracking_events` opens and clicks on linked threads ("opened the proposal twice … clicked pricing"); tickets of the org resolved with CSAT; `deal_participants` added; product seat count change from `product_counts_daily` (D-19: counts only, so "Employee list grew from 44 to 48 — still the 26–100 band" is allowed). Document views come once Documents exists |
| Checkboxes | unbound | NEW `meeting_brief_checks (meeting, item_key, staff)`; ticking persists per user (open question 18) |
| "Who you meet" (name, role · decision maker · prefers phone mornings) | **Fabricated** | Attendees joined to `people`: `title`, labels (e.g. "Decision maker"), "first meeting" when no earlier meeting or activity with that person exists. "Prefers phone mornings" has no source and is omitted (a custom field could hold it). "Uses Orgpuls weekly" is **not derivable**: `members.last_login_at` holds only the latest login. Show "Last signed in <date>" for product users, or nothing |
| Deal and organization facts (Deal "64 000 kr · Proposal sent", Score 86, Health 82, Applications, Competitor) | **Fabricated** (they happen to match demo values) | `deals.value`, `currency`, stage name; `record_scores`; `v_health_latest` (0025); the organization's installed `account_products`; deal custom fields with quality important/required (that is where "Competitor" lives). Each line is omitted when its value is null or the caller lacks the right |
| "From earlier conversations" quotes | **Fabricated** | AI-selected **verbatim** excerpts from earlier `transcript_segments` and `notes` on the same deal, org or people, each with its speaker and date and a link to the segment or note. The gateway rejects any quote that is not an exact substring of its cited source (an anti-fabrication check; one retry, then dropped). Without an LLM the card reads "Not available — AI not connected" |
| Brief instructions | absent | NEW `meeting_user_settings.brief_instructions` (≤ 2000), passed to the AI step only |

### 2.3 Transcript and recap (MTG-04, MTG-06)

| Element | Prototype | Real source / formula |
|---|---|---|
| "28 min · 3 speakers · nb-NO" | **Fabricated**, and wrong: the transcript has two speakers | `meeting_transcripts.duration_s`, `count(distinct speaker_label)` over segments, `language` |
| Lines (time, speaker, text) | **Fabricated**, the same for every meeting | `transcript_segments` ordered by `seq`: `start_ms` as mm:ss; speaker from `transcript_speakers` (staff or person name, else the raw label); staff in ink `#191510`, external speakers in `#2F5D2A`. Paged (cursor). Text is escaped as untrusted (A7.4) |
| Recap: key takeaways, next steps | **Fabricated** | `meeting_recaps.takeaways`, `.next_steps` (each `{text, seq}`). Clicking an item scrolls to segment `seq` (MTG-04 RU, D-41). With no LLM: `state = 'not_connected'` and the card says so; the transcript stays readable |
| "Save recap as note" → "✓ Saved as note on the lead" | label swap only | `meeting_recap_save_note`: inserts a `notes` row on the primary linked record (deal → lead → organization → person) whose body is the takeaways and next steps plus a link to the meeting; stores `note_id`; refuses an unlinked meeting with `invalid` (detail `link`). The label names the real entity |
| Slack message when the recap is ready (MTG-04 RU) | absent | Posted by the notification subscriber when `integration_connections('slack')` is connected; otherwise an in-app notification only |

### 2.4 CRM update suggestions (MTG-05)

| Element | Prototype | Real source / formula |
|---|---|---|
| Six rows (Record, Field, Current, Proposed) | **Fabricated** | `meeting_suggestions`. The LLM proposes `{target, field, value, evidence seq[]}`. The gateway validates each one against the registry (`entity_columns` writable + `fields` by type + labels by entity). Proposals for fields that do not exist are **dropped**: e.g. the prototype's "Lead · Expected close" — `leads` has no such column. `current_value` and `base_version` are snapshotted when the suggestion is made |
| Accept / Reject / "Accept all remaining" | state only | `meeting_suggestion_decide(ids, 'accept' | 'reject')`. Accept calls `rec_save(entity, id, {field: value}, base_version, null, 'meeting')`. On `version_conflict`, or when the current value differs from the snapshot, the row becomes `stale` and is shown as such, never overwritten. A "New contact" goes through `rec_save('person', null, …)` and follows `contact_rule` (MTG-05 RU), so with `opt_in_only` it is refused with the setting named (SF-34.4). Each item is decided independently; the result lists per-id states |
| Footer "changelog source: meeting intelligence" | promise | changelog `source = 'meeting'`. **Not allowed today**: `changelog_source_check` (0022) and `rec_save`'s source whitelist (0006) both need `meeting` (§9.10) |
| Toast "Updates written …" | **Fabricated** | shown only after at least one write succeeded, with the count |

### 2.5 Ways to capture

| Card | Prototype | Real |
|---|---|---|
| Notetaker bot, "Auto-join: meetings with external guests", Configure | literal; "Configure" toasts "· ready" | Needs `integration_connections('meeting_bot')` connected plus the owner's `calendar_connections` connected. "Configure" opens the per-user choice `bot_auto_join` (external / all / off; default external, the design's text). Not connected → the card shows the `not_connected` state with no CTA (admin: a link to connect) |
| Desktop capture, "macOS and Windows app · 6 users", Download app | **"6 users" fabricated** | D-38: the desktop recorder is decided with meeting intelligence and is not built. The card shows "Not available yet" and no count. When it exists: a count of `meeting_capture_devices` that are not revoked |
| Unscheduled calls, Start recording | toast "Recording started in the desktop app" (**fabricated**) | needs the desktop app → not available (same as the toolbar button) |
| Transcript upload (.vtt · .srt · .txt · .docx), Upload | toast | Real without any provider except the LLM: upload ≤ 5 MB to the private bucket; an edge worker parses it (VTT `<v>` speaker tags, SRT timings without speakers, TXT `Name: text` lines, DOCX paragraphs); segments are stored; the original file is deleted after parsing. The recap and suggestions follow only if the LLM is connected. The toast "recap ready in about a minute" is **fabricated** and may only say "Transcript uploaded" |

### 2.6 Workspace and controls (MTG-08)

| Element | Prototype | Real |
|---|---|---|
| User list | `staff.slice(0, 7)` | All active staff with `deals:see`, with `meeting_user_settings.enabled` (default true when no row exists). Visible to `global:configure` only; others see only their own settings (D-41) |
| "Super-admin · mailbox meetings@ (re-auth)" / "own" | **Fabricated** | `meeting_user_settings.mailbox_id → mailboxes`: its address and status (`reauth` → "(re-auth)"). Null → "own" = the user's personal mailbox from `mailboxes`. With no mailbox at all → "no mailbox" (email items then drop out of briefs) |
| Toggle | state only | `meeting_user_set(staff, {enabled})`, audited |
| Recording notice options | state only, not bound to the register | `setting_set('rec_notice', 'on_24h' | 'custom' | 'off', '', hours)`; custom = hours before start (open question 8) |
| Note "The notetaker joins as a visible participant. Transcripts are CRM data only — survey content is never part of a brief, recap or AI context." | promise | Structural. The bot's display name always contains "(recording)" (fixed). The AI context builder reads a whitelist of CRM tables and none of the product mirrors beyond count tables (D-19, SF-24.2); this is proven by the firewall test suite (D-34) |

### 2.7 Actions: what each does for real

| Action | Behaviour | Right | Event |
|---|---|---|---|
| Calendar scan (job) | From each connected `calendar_connections` row, upsert meetings for events in the next 14 days that have a join link or an external attendee. Attendees are matched to `people`/`admins` by email; the meeting is linked to a deal by attendee email (open deal of that person or org) or to an existing activity (SF-21.1). An unlinked meeting gets the flag | system (worker) | `meeting.scheduled` / `meeting.updated` |
| Notice dispatch (job) | At `notice_due_at` (= `starts_at − hours`), email each external attendee through the transactional stream: who records, why, retention, the controller's identity, and an opt-out link (D-28 host, unguessable token stored as SHA-256). If the email provider is not connected or the send fails, `notice_state = 'blocked'` and **the bot does not join** (fail closed) | system | `meeting.notice_sent` |
| Opt-out (public page) | `meeting_opt_out(token, always)`: sets `opted_out_at`, cancels the bot for that meeting, and with "always" stores `recording_opt_outs(sha256(lower(email)))`, which blocks the bot in every future meeting with that address | anon via edge, token only | `meeting.opted_out` |
| Bot scheduling (job) | Joins about two minutes before start (MTG-02 RU) when all hold: module on; owner's workspace enabled; `capture = 'bot'` (from `bot_auto_join`); join URL present; notice sent (or setting off); no attendee opted out; provider connected. Otherwise `bot_state = 'blocked'` with the reason | system | |
| Remove bot (D-41) | Provider call to leave; `bot_state = 'removed'` (MTG-02 A "leaves when removed") | meeting owner, or `deals:edit_others` | `meeting.bot_removed` |
| Stop and delete recording (D-41) | Deletes the audio from storage, plus the transcript and derived recap/suggestions if chosen | owner | `meeting.recording_deleted` |
| Recording ready → transcription (worker) | Store the audio in the private bucket with `purge_after` = now + retention; request transcription; on failure keep the recording and allow "Retry" (SF-21.7) | system | `meeting.recorded`, `meeting.transcribed` |
| Recap + suggestions (worker) | One AI gateway call over the transcript, the linked records' current values and the field registry. Output schema validated (Zod, one retry, SF-24.6). Transcript content is treated as untrusted: it can never trigger a write (A7.10) | system | `meeting.recap_ready` |
| Link meeting | `meeting_link(id, {deal_id | lead_id | person_id | organization_id}, version)`. Ensures a `meeting`-type activity exists for the link (done for past meetings) so the meeting appears in the record's history (ACT-01 A, MTG-07 A) | owner or `deals:edit_others`; the target must be visible | `meeting.linked`; changelog entity `meeting` |
| Upload transcript | `meeting_transcript_upload_begin(meeting_id?, filename, size, mime)` → signed upload; then `…_done(upload)` queues parsing. No meeting id → a meeting with `source = 'upload'` is created, unlinked | workspace | `meeting.transcribed` |
| Speaker mapping (D-41) | `meeting_speaker_map(transcript, label, staff_id | person_id | email)` | owner | |
| Save recap as note | §2.3 | the target note's scope `see` | `note.created`, `meeting.recap_saved` |
| Plan next activity / Draft follow-up (D-41, UF-07 step 6) | Creates an activity from a next step (subject = step text, linked like the meeting). "Draft follow-up" opens the composer with an AIA-03 draft (needs mailbox + LLM) | `deals:see` | `activity.created` |
| Accept / reject suggestions | §2.4 | target scope edit rights (as `rec_save`) | `meeting.updates_approved` (counts only) |
| Brief regenerate | Rebuilds facts now and re-queues quotes | workspace | |
| Per-user switch / notice setting | §2.6 | `global:configure` | audit `meeting_user.changed`, `setting.changed` |

### 2.8 Feature and flow IDs on this screen, with their acceptance tests

| ID | Acceptance test | Where it is met / honest state now |
|---|---|---|
| MTG-01 Pre-call brief | A brief exists before the meeting starts and cites its sources | `meeting_briefs` built at T−24 h and refreshed at T−1 h; facts carry `source`. Works without an LLM, except the quotes |
| MTG-02 Notetaker bot | The bot joins scheduled meetings that have a link and leaves when removed | bot job + `meeting_bot_remove`. **`not_connected`** until a bot provider is chosen (D-07) |
| MTG-03 Desktop capture | A recording made in the desktop app appears in the same workspace | **Not available** (D-38). Schema-ready (`capture = 'desktop'`, devices table later) |
| MTG-04 Transcript and recap | Recap and transcript are attached to the right record | meeting links + note on the record. Transcription **`not_connected`** (provider); recap needs the LLM |
| MTG-05 CRM update suggestions | Approved items are written and logged with the meeting as source | `meeting_suggestion_decide` → `rec_save(…, 'meeting')`; needs the source fix |
| MTG-06 Transcript upload | An uploaded transcript produces a recap | upload + parse (real now), recap (LLM) |
| MTG-07 Unscheduled calls | The recording can be linked to a deal afterward | `meeting_link` (real now for uploads); recording needs the desktop app |
| MTG-08 Workspace and controls | A user without the permission sees no meeting workspace | `app.require_meetings()`; the shell hides the nav item |
| ACT-09 / SF-08 Calendar sync (feeds meetings) | An event changed on either side is updated on the other in two-way mode | `calendar_connections` (exists, adapter pending) |
| COM-11 / SF-40 Video links | The invite contains a working link | `activities.video_url` → `meetings.join_url` |
| INT-05 / INT-06 Google, Microsoft | Each connection can be made and revoked by the user | calendar + mailbox connections |
| INT-07 Team chat | A won deal posts to the configured channel | recap announcement uses the same connection |
| AIA-03 Email writer (follow-up) | The draft uses the linked deal and person context | D-41 "Draft follow-up" |
| SEC-11 Privacy (recordings, transcripts) | An erasure request removes the person from every module | §8.3 erasure rules |
| CUS-07 / SF-34 `rec_notice`, module `meetings` | Turning a module off hides it for every user | existing register + module switch |
| UF-07 Run a meeting | steps 1–6 | step 2 bot/desktop: not connected / not available; steps 1, 4 (upload path), 5, 6 buildable |
| SF-21 Meeting intelligence pipeline | steps 1–7 | §2.7 |
| SF-24 AI gateway call | steps 1–6 | NEW `ai_calls` log, validation, retry |
| SF-15 Erasure | step 5 | §8.3 |
| Part F entities: meeting, recording, transcript, brief, recap, update_suggestion | — | §3.2 |
| Part F events: meeting scheduled, recorded, recap_ready, updates_approved | — | §6 |
| Part G: AI governance, Privacy, Data residency, Provider independence, Job runtime, Audit | — | §8 |

---

## 3. Data model (DDL sketch; schema `app`, RLS on, no policy, no client grant, access only through security-definer RPCs, tests per D-03/D-09)

Standard columns, abbreviated `STD` below: `owner_id uuid → admins on delete set null, visibility text not null check in ('owner','group','group_sub','all'), labels uuid[] not null default '{}', custom jsonb not null default '{}', is_sample bool not null default false, version int not null default 1, created_at, created_by, updated_at, updated_by, deleted_at`. This is the Part F convention, as on `deals` and `activities`.

### 3.1 Projects (proposed migration `0027_projects.sql`)

**NEW**
```
project_boards(id uuid pk, name text not null check (char_length(btrim(name)) between 1 and 80), ord int not null default 0,
        archived_at timestamptz, is_sample bool not null default false, created_at, created_by)
        unique index (lower(name)) where archived_at is null
project_phases(id uuid pk, board_id uuid not null → project_boards on delete cascade, name text 1..60, ord int,
        color text not null default '#F2EAD6' check (color ~ '^#[0-9A-F]{6}$'), created_at, unique (board_id, name))
        -- deleted only by project_phase_delete(phase, target), which first moves its projects (as stage_delete)
projects(id uuid pk, seq bigint generated always as identity unique,            -- "P-8" in the Security audit sample
        name text not null check (char_length(btrim(name)) between 1 and 200),
        board_id uuid not null → project_boards, phase_id uuid not null → project_phases, phase_entered_at timestamptz not null default now(),
        status text not null default 'open' check (status in ('open','done','canceled')), closed_at timestamptz, closed_by uuid,
        health text check (health in ('on_track','at_risk','off_track','on_hold')), health_set_at, health_set_by uuid,
        health_source text check (health_source in ('manual','ai_suggestion')),
        starts_on date, ends_on date, check (ends_on is null or starts_on is null or ends_on >= starts_on),
        description text check (char_length(description) <= 20000),                -- the brief
        brief_state text not null default 'none' check (brief_state in ('none','drafting','draft','reviewed','failed')),
        person_id uuid → people on delete set null, organization_id uuid → organizations on delete set null,
        template_id uuid → project_templates on delete set null,
        created_source text not null default 'ui' check (created_source in ('ui','deal','workflow','import','api')),
        check ((status = 'open') = (closed_at is null)), STD)
        trigger project_phase_ok: phase_id belongs to board_id (insert/update)
project_deals(project_id → projects on delete cascade, deal_id → deals on delete cascade, is_primary bool not null default false,
        linked_by uuid, linked_at timestamptz default now(), primary key (project_id, deal_id))
        unique index one_primary (project_id) where is_primary
project_phase_history(id bigint identity pk, project_id → projects on delete cascade, board_id uuid, phase_id → project_phases on delete set null,
        entered_at timestamptz not null, left_at timestamptz, moved_by uuid, source text not null default 'ui')
        trigger: content is fixed; allowed are UPDATE of left_at from null only, and DELETE when the project is gone
        (FK-safe append-only, as consent_fixed in 0011)
project_groups(id uuid pk, project_id → projects on delete cascade, name text 1..80, ord int, phase_id → project_phases on delete set null, created_at)
project_items(id uuid pk, project_id → projects on delete cascade,
        kind text not null check (kind in ('task','milestone','activity')),
        parent_id uuid → project_items on delete cascade, group_id uuid → project_groups on delete set null,
        name text check (name is null or char_length(btrim(name)) between 1 and 300), description text check (<= 10000),
        owner_id uuid → admins on delete set null, starts_on date, due_on date, check (due_on is null or starts_on is null or due_on >= starts_on),
        done bool not null default false, done_at, done_by uuid, check (done = (done_at is not null)),
        completes_with_subtasks bool not null default false,
        activity_id uuid unique → activities on delete cascade, ord int not null default 0,
        source text not null default 'ui' check (source in ('ui','template','paste','import','workflow','api')),
        template_item_id uuid, is_sample, version, created_at, created_by, updated_at, updated_by, deleted_at,
        check ((kind = 'activity') = (activity_id is not null)), check (kind = 'activity' or name is not null),
        check (kind <> 'milestone' or starts_on is null), check (parent_id is null or kind = 'task'), check (parent_id is distinct from id))
        trigger project_item_ok: the parent is a top-level task of the same project (one level, PRJ-03 "subtasks always have a parent");
        an activity item's activities.project_id = project_id
project_item_assignees(item_id → project_items on delete cascade, staff_id → admins on delete cascade, person_id → people on delete cascade,
        check ((staff_id is null) <> (person_id is null)))
        unique index (item_id, coalesce(staff_id, person_id))
project_item_dependencies(predecessor_id → project_items on delete cascade, successor_id → project_items on delete cascade,
        lag_days int not null default 0 check (lag_days between -365 and 365), created_by uuid, created_at,
        primary key (predecessor_id, successor_id), check (predecessor_id <> successor_id))
        trigger: same project; kinds in (task, milestone); no cycle (recursive CTE) → invalid, detail 'dependency.cycle'
project_templates(id uuid pk, name text 1..120, description text check (<= 500),
        organized_by text not null default 'phases' check (organized_by in ('phases','groups')),
        board_id → project_boards on delete set null, source_project_id → projects on delete set null,
        is_sample, version, created_at, created_by, updated_at, deleted_at)
        unique index (lower(name)) where deleted_at is null
project_template_groups(id uuid pk, template_id → project_templates on delete cascade, name text 1..80, ord int, phase_id → project_phases on delete set null)
project_template_items(id uuid pk, template_id → project_templates on delete cascade, group_id → project_template_groups on delete set null,
        parent_id → project_template_items on delete cascade, kind text check in ('task','milestone','activity'), name text 1..300,
        start_offset_days int check (between 0 and 3650), due_offset_days int check (between 0 and 3650),
        check (due_offset_days is null or start_offset_days is null or due_offset_days >= start_offset_days),
        activity_type_id → activity_types, activity_time time, activity_duration_min int check (between 0 and 1440),
        check ((kind = 'activity') = (activity_type_id is not null and activity_time is not null)),
        assignee text not null default 'unassigned' check (assignee in ('owner','unassigned')), ord int)
project_template_dependencies(template_id → project_templates on delete cascade, predecessor_id → project_template_items on delete cascade,
        successor_id → project_template_items on delete cascade, lag_days int not null default 0, primary key (predecessor_id, successor_id))
project_ai_summaries(id uuid pk, project_id → projects on delete cascade,
        state text not null check (state in ('requested','ready','failed')), suggested_health text check (in the four values),
        summary text check (<= 4000), recommendations jsonb not null default '[]' check (jsonb_typeof = 'array' and length <= 5),
        sources jsonb not null default '[]',          -- [{entity, id, kind}]
        ai_call_id bigint → ai_calls, requested_by uuid, requested_at, generated_at, applied_at, applied_by uuid)
project_status_reports(id uuid pk, project_id → projects on delete cascade, sections jsonb not null, summary text check (<= 4000),
        ai_drafted bool not null default false, state text check in ('requested','ready','failed'), file_id → record_files on delete set null,
        requested_by uuid, requested_at, ready_at)
record_files(id uuid pk, entity text not null → entities(key) on delete cascade, record_id uuid not null,
        storage_path text not null unique check (char_length(storage_path) <= 500), filename text 1..255,
        mime text not null check (mime in (<allow-list: pdf, png, jpeg, docx, xlsx, pptx, csv, txt>)),
        size_bytes bigint not null check (size_bytes between 1 and 26214400),
        source text not null default 'upload' check (source in ('upload','status_report','email','generated')),
        uploaded_by uuid, is_sample bool, created_at, deleted_at)       -- generic CRM-05/SF-33; bucket 'record-files', private
        index (entity, record_id) where deleted_at is null
```

**EXISTING, changed**
- `app.activities`: `add column project_id uuid references app.projects (id) on delete set null`, plus an index. `entity_columns ('activity','project_id','uuid', writable, ref 'project')`.
- `app.entities`: insert `('project','projects','projects','projects', owned true, title_col 'name', sub_cols ['status'], search ['name'], ord 60)`. `entity_columns` for project:
  - writable: `name` (required), `starts_on`, `ends_on`, `description`, `person_id` (ref person), `organization_id` (ref organization);
  - not writable: `board_id`, `phase_id`, `status`, `health`, `seq`.

  `rec_save` then handles the plain fields, custom fields, labels, owner and visibility. Phase, health and status move only through their own RPCs, as `deal_move`/`deal_status` do (0009).
- `app.labels`, `app.fields`, `app.notes`, `app.followers`, `app.email_links`, `saved_views` and `view_prefs` take entity/screen `project` with no schema change. The `visibility_default` setting works per entity (`scope_id 'project'`).
- `app.changelog`: item changes are written under the **project** (`entity 'project'`, field `items.<item_id>.<column>`). The project's history then shows task work, and `app.purge()` removes it with the project. `project_items` are **not** registered in `app.entities`: `app.vis_sql` returns `true` for an unowned entity, so generic `rec_get` would leak items of invisible projects.
- `app.purge()`: needs no change. Projects are purged through the registry and children cascade. `record_files` rows of purged records need a storage delete, which the purge job queues to the worker.
- `public.note_save`: the mention route `case` lacks `project`, so a mention on a project produces `/?<uuid>`, which **fails `notifications_route_check` (0023)**. Add `when 'project' then 'projects?project='`. Also notify only mentioned staff who pass `app.can(e.scope,'see')` and the record's visibility (CRM-06 RU; today every active staff member is notified).
- `app.report_run` (0024 l.204): add `project` to the entity whitelist, with the dimensions and duration measure above.
- Engine (0021/0026):
  - `wf_save` trigger whitelist (l.1181) adds `project`.
  - `wf_validate` validates `project_action` configs.
  - `wf_blockers` drops `not_available:projects`.
  - The executor implements `project_action` (§6).
  - `wf_scope` already derives `projects` from the entity.

### 3.2 Meetings and the AI gateway (proposed migration `0028_meetings_ai.sql`)

**NEW**
```
ai_calls(id bigint identity pk, feature text not null check (feature ~ '^[a-z_]{2,40}$'),   -- meeting_brief, meeting_recap, project_health, project_brief, status_report …
        staff_id uuid, subject_type text, subject_id uuid, provider text, model text,
        input_tokens int, output_tokens int, cost_micros bigint, latency_ms int,
        state text not null check (state in ('ok','retried_ok','invalid','error','not_connected')), at timestamptz default now())
        -- never the prompt or the output (A7.13); shared by every AI feature (plan §AI and meetings)
meetings(id uuid pk, title text not null check (1..300), starts_at timestamptz, ends_at timestamptz, check (ends_at is null or ends_at >= starts_at),
        source text not null check (source in ('calendar','adhoc','upload','desktop')),
        calendar_staff_id uuid → admins on delete set null, external_event_id text check (<= 500), unique (calendar_staff_id, external_event_id),
        conference text check (conference in ('meet','teams','zoom','phone','in_person','other')), join_url text check (<= 1000),
        capture text not null default 'none' check (capture in ('bot','desktop','upload','none')),
        bot_state text not null default 'none' check (bot_state in ('none','scheduled','joining','in_call','removed','left','failed','blocked')),
        bot_block_reason text check (bot_block_reason in ('notice_not_sent','opted_out','not_connected','no_link','disabled','internal_only')),
        notice_due_at timestamptz, notice_sent_at timestamptz,
        notice_state text not null default 'pending' check (notice_state in ('not_required','pending','sent','blocked')),
        activity_id uuid unique → activities on delete set null, deal_id → deals on delete set null, lead_id → leads on delete set null,
        person_id → people on delete set null, organization_id → organizations on delete set null,
        cancelled_at timestamptz, STD without labels/custom)
meeting_attendees(meeting_id → meetings on delete cascade, email text not null check (email = lower(email) and char_length(email) <= 254),
        name text check (<= 200), person_id → people on delete set null, staff_id → admins on delete set null,
        response text not null default 'needs_action' check in ('needs_action','accepted','tentative','declined'),
        notice_sent_at timestamptz, opt_out_token_sha256 bytea unique, opted_out_at timestamptz, primary key (meeting_id, email))
recording_opt_outs(email_sha256 bytea primary key, via text not null check (via in ('notice_link','staff')), created_at)
meeting_recordings(id uuid pk, meeting_id → meetings on delete cascade, method text check in ('bot','desktop'), provider text, provider_ref text check (<= 500),
        storage_path text check (<= 500), duration_s int check (>= 0), started_at, ended_at,
        state text not null check in ('scheduled','recording','processing','ready','failed','deleted'), error_code text check (<= 80),
        purge_after timestamptz, deleted_at)
meeting_transcripts(id uuid pk, meeting_id → meetings on delete cascade, recording_id → meeting_recordings on delete set null,
        source text not null check in ('provider','upload'), language text check (char_length(language) <= 20), duration_s int, speaker_count smallint,
        state text not null check in ('processing','ready','failed'), error_code text check (<= 80), file_name text check (<= 255),
        uploaded_by uuid, provider text, created_at, ready_at)
transcript_speakers(transcript_id → meeting_transcripts on delete cascade, label text check (1..120), staff_id → admins on delete set null,
        person_id → people on delete set null, email text, primary key (transcript_id, label))
transcript_segments(transcript_id → meeting_transcripts on delete cascade, seq int not null, start_ms int not null check (>= 0),
        end_ms int check (end_ms >= start_ms), speaker_label text check (<= 120), text text not null check (char_length(text) between 1 and 4000),
        redacted_at timestamptz, primary key (transcript_id, seq))
meeting_briefs(meeting_id uuid pk → meetings on delete cascade, state text check in ('pending','ready','failed'), generated_at, last_contact_at,
        changes jsonb not null default '[]', people jsonb not null default '[]', facts jsonb not null default '[]',   -- [{key, kind, params, source:{entity,id}}]
        quotes jsonb not null default '[]', quotes_state text check in ('none','ready','not_connected','failed'), ai_call_id bigint → ai_calls)
meeting_brief_checks(meeting_id → meetings on delete cascade, item_key text check (<= 80), staff_id → admins on delete cascade, checked_at,
        primary key (meeting_id, item_key, staff_id))
meeting_recaps(transcript_id uuid pk → meeting_transcripts on delete cascade, meeting_id → meetings on delete cascade,
        state text check in ('requested','ready','failed'), takeaways jsonb not null default '[]', next_steps jsonb not null default '[]',  -- [{text, seq, activity_id?}]
        ai_call_id bigint → ai_calls, generated_at, note_id → notes on delete set null, saved_by uuid, saved_at, announced_at)
meeting_suggestions(id uuid pk, meeting_id → meetings on delete cascade, transcript_id → meeting_transcripts on delete cascade, ord int,
        target_entity text not null check in ('deal','lead','person','organization'), target_id uuid,           -- null + field '*new' = a new person
        field text not null check (field ~ '^(custom\.[a-z][a-z0-9_]{1,40}|labels|\*new|[a-z_][a-z0-9_]{0,40})$'),
        current_value jsonb, base_version int, proposed_value jsonb not null, evidence int[] not null default '{}',
        state text not null default 'pending' check in ('pending','accepted','rejected','stale','failed'), error_code text check (<= 80),
        decided_by uuid, decided_at, written_record_id uuid, created_at)
meeting_user_settings(staff_id uuid pk → admins on delete cascade, enabled bool not null default true,
        bot_auto_join text not null default 'external' check (bot_auto_join in ('external','all','off')),
        brief_instructions text check (char_length(brief_instructions) <= 2000), mailbox_id → mailboxes on delete set null, updated_by uuid, updated_at)
meeting_uploads(id uuid pk, meeting_id → meetings on delete cascade, storage_path text, filename text, mime text check in (vtt, srt, txt, docx types),
        size_bytes int check (between 1 and 5242880), state text check in ('pending','parsed','failed'), uploaded_by uuid, created_at)  -- the file is deleted after parsing
-- later, with the desktop app (D-38): meeting_capture_devices(id, staff_id, platform check in ('macos','windows'), app_version, token_sha256, registered_at, last_seen_at, revoked_at)
```

**EXISTING, changed**
- `app.integration_connections`: provider check adds `'llm','meeting_bot','transcription'` (and `'email'` if the transactional stream has no status row elsewhere), with one row each, `not_connected`. This is the 0022 precedent. Every AI and provider RPC raises `not_connected` (detail = provider) from this row instead of checking an env var (open question 16).
- `app.mailboxes.kind`: add `'meeting'` (MTG-08: "its own mailbox connection reads email for briefs"; Security screen: "Meeting mailbox token expires …").
- `app.changelog`: `changelog_source_check` adds `'meeting'`. `public.rec_save`: its `v_source` whitelist adds `'meeting'` (`create or replace`, nothing else changed).
- `app.settings_registry`: see §7. `rec_notice.applies_to` becomes `'MTG-02, MTG-03, MTG-07, MTG-08'`.
- Meetings are **not** registered in `app.entities`. They are read only through the meetings RPCs, so the per-user switch can't be bypassed through `rec_get`, search or exports. Their soft-delete purge and the recording retention run in a job of their own (§8.2).

---

## 4. Public RPCs

All are `security definer`, `set search_path = ''`, revoked from `public, anon` and granted to `authenticated` (worker functions: `service_role` only; the opt-out: called by the edge function on the public host with the service role). The return value is `jsonb`, parsed with Zod in the app. Errors use the house codes:
- `forbidden`: `insufficient_privilege`, detail `scope:action`, `setting:<key>` or `meetings:disabled`;
- `not_found`: `no_data_found`, also for records the caller may not see;
- `invalid`: `invalid_parameter_value`, detail = the field (`starts_on`, `dependency.cycle`, `items[3].name`, `link` …);
- `version_conflict`: `serialization_failure`, detail = the current version;
- `not_connected`: `invalid_parameter_value`, detail = `llm | meeting_bot | transcription | calendar | email | desktop`;
- `module_off`: the existing code.

Every read of customer-scoped data writes `app.log('record.read' …)` (D-12).

**Projects** (each first does `app.require_module('projects')`):
- *Read:*
  - `project_boards_get()`;
  - `projects_board(p_board uuid, p_query jsonb)` → phases with count and cards, plus `workflow_hint`;
  - `project_detail(p_id)` → header, health, AI summary (when allowed), items tree, timeline of notes and mail, files, sharing, deals;
  - `project_timeline(p_id, p_from date default null, p_months int default null)`;
  - `project_templates_get()`;
  - `project_reports(p_board uuid default null, p_from date, p_to date)`;
  - history through `rec_history('project', id)`.
- *Projects:*
  - `project_create(p_values jsonb)` (template optional);
  - `project_create_from_deal(p_deal uuid, p_values jsonb)`;
  - `project_move(p_id, p_phase uuid, p_version int)`;
  - `project_health_set(p_id, p_health text, p_version int, p_from_summary uuid default null)`;
  - `project_close(p_id, p_status text, p_version int)`;
  - `project_deal_link(p_id, p_deal uuid, p_on boolean, p_primary boolean default false)`;
  - plain fields through `rec_save('project', …)`, delete and restore through `rec_delete`/`rec_restore`.
- *Items:*
  - `project_item_save(p_project uuid, p_id uuid, p_values jsonb, p_version int default null)` (assignees included);
  - `project_item_done(p_id, p_done boolean)` → `{id, parent_completed}`;
  - `project_items_add(p_project, p_group uuid, p_items jsonb)` (paste; ≤ 200);
  - `project_items_bulk(p_project, p_ids uuid[], p_values jsonb)`;
  - `project_items_delete(p_ids uuid[])`;
  - `project_items_reorder(p_project, p_ids uuid[])`;
  - `project_activity_add(p_project, p_group uuid, p_values jsonb)` (date, time and owner required, PRJ-03 RU);
  - `project_dependency_set(p_pred uuid, p_succ uuid, p_on boolean, p_lag int default 0)`;
  - `project_group_save(p_project, p_id, p_name, p_ord)`;
  - `project_group_shift(p_project, p_group uuid, p_days int)`.
- *Templates and configuration:*
  - `project_template_save(p_id, p_values jsonb)` (with groups, items and dependencies as a set);
  - `project_template_from_project(p_project, p_name)`;
  - `project_template_delete(p_id)`;
  - `project_board_save(p_id, p_values)`;
  - `project_phase_save(p_id, p_board, p_values)`;
  - `project_phases_reorder(p_board, p_ids uuid[])`;
  - `project_phase_delete(p_phase, p_target)`.
- *AI and output:*
  - `project_ai_summary_request(p_id)`;
  - `project_brief_request(p_id)`;
  - `project_status_report_request(p_id, p_sections jsonb, p_summary text default null, p_ai_draft boolean default false)`;
  - `project_export(p_board uuid, p_project uuid, p_format text)`.
- *Files (generic, CRM-05):*
  - `files_list(p_entity, p_id)`;
  - `file_upload_begin(p_entity, p_id, p_filename, p_mime, p_size)` → the edge function signs the upload;
  - `file_upload_done(p_id)`;
  - `file_download_url(p_id)`;
  - `file_delete(p_id)`.
- *Worker:*
  - `worker_project_summary_ready(p_id, p_result jsonb)`;
  - `worker_project_brief_ready(p_project, p_text)`;
  - `worker_status_report_ready(p_report, p_storage_path, p_size)`.

**Meetings** (each first calls `app.require_meetings()` = `require('deals','see')` + `require_module('meetings')` + `coalesce(meeting_user_settings.enabled, true)`, else `forbidden`, detail `meetings:disabled`):
- *Read:*
  - `meetings_workspace(p_query jsonb)` → groups, plus `capabilities {calendar, meeting_bot, transcription, llm, email, desktop}` with each status;
  - `meeting_detail(p_id)`;
  - `meeting_brief(p_id)`;
  - `meeting_transcript(p_id, p_cursor int default 0, p_limit int default 200)`;
  - `meeting_recap(p_id)`;
  - `meeting_suggestions(p_id)`;
  - `meeting_controls()` (`global:configure`);
  - `meeting_my_settings()`.
- *Write:*
  - `meeting_link(p_id, p_values jsonb, p_version int)`;
  - `meeting_capture_set(p_id, p_capture text)`;
  - `meeting_bot_remove(p_id)`;
  - `meeting_recording_delete(p_id, p_with_transcript boolean)`;
  - `meeting_brief_check(p_id, p_item_key, p_checked boolean)`;
  - `meeting_brief_regenerate(p_id)`;
  - `meeting_transcript_upload_begin(p_meeting uuid, p_filename, p_mime, p_size)` and `meeting_transcript_upload_done(p_upload uuid)`;
  - `meeting_transcript_retry(p_transcript uuid)`;
  - `meeting_speaker_map(p_transcript, p_label, p_values jsonb)`;
  - `meeting_recap_regenerate(p_transcript)`;
  - `meeting_recap_save_note(p_id, p_entity text default null, p_record uuid default null)`;
  - `meeting_next_step_activity(p_id, p_step int, p_values jsonb)`;
  - `meeting_suggestion_decide(p_ids uuid[], p_decision text)` → `[{id, state, error}]`;
  - `meeting_user_set(p_staff uuid, p_values jsonb)` (`global:configure`);
  - `meeting_my_settings_set(p_values jsonb)`.
- *Public:* `meeting_opt_out(p_token text, p_always boolean)` → `{date, organiser_company}`. It returns nothing else: no attendee list, no title.
- *Worker:*
  - `worker_meeting_upsert(p_staff, p_event jsonb)`;
  - `worker_notice_result(p_meeting, p_email, p_ok)`;
  - `worker_bot_state(p_meeting, p_state, p_reason)`;
  - `worker_recording_ready(p_meeting, p_values)`;
  - `worker_transcript_ready(p_transcript, p_segments jsonb, p_speakers jsonb)`;
  - `worker_upload_parsed(p_upload, p_segments jsonb)`;
  - `worker_brief_quotes_ready(p_meeting, p_quotes jsonb)`;
  - `worker_recap_ready(p_transcript, p_recap jsonb, p_suggestions jsonb)`;
  - `worker_ai_call(p_values jsonb)`.

## 5. Rights (`app.can` / `app.require`)

| Operation | Scope:action | Notes |
|---|---|---|
| See boards, projects, timeline, templates, reports | `projects:see` + visibility | Without `projects:reports_others` the Reports tab and Insights count own projects only |
| Create a project (also from a template or a deal) | `projects:add` | Linking a deal needs it visible (`deals:see`). A workflow acts as its owner (0021) |
| Edit a project, its items and groups; move phase; set health; close | owner, or `projects:edit_others` | An item's owner or staff assignee may edit and complete **their own items** without `edit_others` (UF-20 step 4: "the team works the tasks") |
| Delete or restore | `projects:delete` (own, or with `edit_others`) | soft delete, 30 days (SF-15) |
| Bulk edit items | `projects:bulk` | |
| Export | `projects:export` | audited, formulas neutralised |
| Boards, phases; edit or delete others' templates | `projects:configure` | Saving one's own template needs `projects:add` (open question 7) |
| AI summary, AI brief, AI report draft | `projects:ai` + setting `project_ai = on` + `llm` connected | refusals name the cause: `forbidden` (`projects:ai` or `setting:project_ai`), `not_connected` (`llm`) |
| Workflows triggered by projects | `projects:workflows` | via `app.wf_scope` |
| Project-linked activities | `deals:see` **or** (`projects:see` and the activity's `project_id` is visible) | needs a change in `activities_get`/`activity_done` (§9.12) |
| Meetings workspace | `deals:see` + per-user switch `meeting_user_settings.enabled` (default on) + module `meetings` | MTG-08 "one permission covers all features". There is no meetings scope in `app.right_ok` (§9.6) |
| Workspace and controls (others' switches, notice setting) | `global:configure` | |
| Link a meeting, remove the bot, delete a recording, map speakers | meeting owner, or `deals:edit_others` | |
| Accept a suggestion | the target's scope `see` + owner or `edit_others` (as `rec_save`) | a new person also follows `contact_rule` |
| Meeting visibility | `app.visible(owner_id, visibility)` **or** the caller is a staff attendee | default visibility: open question 13 |

## 6. Events (`app.emit`, kind `object.action`) and workflow triggers

| Event | Subject | Payload (ids and counts only, never text) | Consumers |
|---|---|---|---|
| `project.created` | project | `source` (ui, deal, workflow, template), `template`, `deal` | workflows (AUT-02 "added"), feed, webhooks |
| `project.updated` | project | `fields` (from `rec_save`; `items` for item changes) | workflows ("updated"), report cache |
| `project.deleted` | project | — | workflows ("deleted") |
| `project.phase_changed` | project | `from`, `to`, `board` | workflows, reports (Part F "phase_changed") |
| `project.health_changed` | project | `from`, `to`, `source` | workflows, feed |
| `project.task_completed` | project | `item`, `kind` | workflows (hook "task completed"; Part F "completed") |
| `project.milestone_reached` | project | `item` | workflows (hook "milestone reached") |
| `project.completed` / `project.reopened` | project | `status` | workflows, reports |
| `project.template_applied`, `project.status_report_created` | project | `template` / `file` | history |
| `project_item.created`, `.updated`, `.reopened`, `.deleted` | project_item | `project` | webhooks (INT-04), MCP sync |
| `meeting.scheduled`, `meeting.updated`, `meeting.linked` | meeting | `deal`/`lead`/`person`/`organization` ids | notifications, workflows (Part F "scheduled") |
| `meeting.notice_sent`, `meeting.opted_out`, `meeting.bot_removed`, `meeting.recording_deleted` | meeting | counts | audit trail, notifications |
| `meeting.recorded`, `meeting.transcribed` | meeting | `duration_s` | Part F "recorded" |
| `meeting.recap_ready`, `meeting.recap_saved` | meeting | `note` | notifications (Slack via INT-07), Part F "recap_ready" |
| `meeting.updates_approved` | meeting | `accepted`, `rejected`, `stale` counts | Part F "updates_approved" |
| `note.created`, `activity.created`, `<entity>.updated` | as today | | |

Workflow triggers:
- `trigger_config.entity = 'project'` with event `created | updated | deleted | phase_changed | health_changed | task_completed | milestone_reached | completed`.
- Update triggers can require fields (`trigger_config.fields`, as today).
- Date triggers on `starts_on` and `ends_on` (AUT-03) come free once `project` is registered.

`project_action` configs, validated in `wf_validate`, executed in SQL as the workflow owner:
- `{action: 'create_from_template', template_id, board_id, phase_id?, owner: '@record_owner' | staff id, start: 'today' | 'won_at'}`, on a deal subject: links the deal, its person and its organization;
- `{action: 'move_phase', phase_id}`, on a project subject;
- `{action: 'add_tasks_from_template', template_id, group?}`;
- `{action: 'assign_task', item_name | template_item_id, assignee}`.

The Automation screen's sample uses "«Onboarding — Skiftly» · board Delivery · owner Emma Lie". The seeded `won_project` template (0021) gets a template picker in its setup, since `create_from_template` without a `template_id` is `invalid`. Meeting events are not added as trigger entities in this phase (AUT-02 does not list them).

## 7. Settings (register, D-15/D-16) and preferences

| Key | Group | Options (default) | Applies to | Effect |
|---|---|---|---|---|
| `project_ai` **NEW** | `ai` | `on`, `off` (**on**, D-16) | PRJ-02, PRJ-06, PRJ-07 | AI brief, health summary and report draft. PRJ-06 RU says "must be enabled per account"; D-16 makes the default unrestricted (§9.4) |
| `rec_notice` existing | `meetings` | `on_24h`, `custom` (number = hours, 0..168), `off` (**on_24h**) | MTG-02, MTG-03, MTG-07, MTG-08 | notice timing; with `off`, no email, but the fixed in-call disclosure and opt-out still apply (§8.3) |
| `rec_retention` **NEW** | `meetings` | `12_months`, `custom` (number = months), `keep` (**12_months**, from the Security screen "Meeting recordings · 12 months · transcripts kept") | SEC-11, MTG-02/03 | the audio purge job. Transcripts follow the linked record (open question 12) |
| `visibility_default` (scope `project`) existing | `visibility` | `all` | CRM-03 | new projects' visibility |
| Module switches `projects`, `meetings` existing | | on | CUS-07 | `module_off` everywhere |
| Per user (not in the register): `meeting_user_settings` | | enabled on, auto-join external, instructions empty, mailbox own | MTG-01, MTG-02, MTG-08 | |
| Per user: `view_prefs (screen 'projects')` | | board, tab, timeline project | | |
| ENT-02 limits | | none specific; ENT-01 gating = the module switches (D-17) | | Credits count provider usage only: transcription minutes and LLM tokens go into `ai_calls`/a credit ledger, never sold |

## 8. Jobs, external dependencies, consent

### 8.1 Providers (all behind adapters; Part G "Provider independence")

| Need | Provider status | Honest state until connected |
|---|---|---|
| Calendar events (Google Calendar, Microsoft Graph) | adapter pending (0010 «not connected») | no Upcoming list; a "Connect calendar" empty state |
| Mailbox for briefs | Gmail/Graph adapters (0020) | brief without email items |
| Transactional email (notices) | one provider (D-07), not connected | `notice_state = 'blocked'` → no bot |
| Meeting bot (Meet, Teams, Zoom) | **not chosen** (D-07: "others chosen before their phase") | the bot card shows `not_connected`; `capture = 'none'` |
| Transcription (speakers, timestamps, nb-NO) | **not chosen**; the Security screen lists "Transcription service · EU" | recordings stay unprocessed; uploads still work |
| LLM (Claude, D-07) | chosen, key not present | AI blocks render `not_connected`; nothing is generated or approximated |
| Desktop recorder (macOS/Windows) | **deferred** (D-38) | "Not available yet" |
| PDF rendering (status report) | edge function | none needed |
| Slack (recap announcement) | `integration_connections('slack')` | in-app notification only |

All of them must process in the EU (Part G "Data residency", D-35) under a data processing agreement and a no-training clause (SF-24.3), and be listed as sub-processors on the Security screen. Running costs (per transcription minute, per token) need a cost model before phase 7 (Part G open point 8).

### 8.2 Jobs (pg_cron + pgmq, D-05)
- `meeting-calendar-scan` (every 10 min) → `worker_meeting_upsert`.
- `meeting-notices` (every 5 min): notices due → edge mailer → `worker_notice_result`.
- `meeting-bot-schedule` (every minute): meetings starting in ≤ 5 min that pass the join rules → provider.
- `meeting-briefs`: build facts at T−24 h and refresh at T−1 h; quotes are queued to the AI worker.
- `meeting-recordings-purge` (nightly): delete audio where `purge_after < now()` (`rec_retention`), plus soft-deleted meetings after 30 days.
- `ai-worker` queue consumers: briefs, recaps and suggestions, project summary, project brief, status report draft.
- `files-purge`: storage objects of purged `record_files`.
- No project job is needed: lateness and progress are derived when read.

### 8.3 Recording consent, Norwegian law and GDPR (requirements for the build; the legal review in D-27 precedes go-live)
- **Criminal law.** Straffeloven § 205 forbids secretly recording a conversation one is not part of. A participant's own recording, or a bot acting for a participant, is not covered. It is still personal-data processing, and that is what governs.
- **GDPR / personopplysningsloven:**
  - a documented lawful basis, normally legitimate interests (art. 6(1)(f)) with a balancing test;
  - information before or at collection (art. 13): the notice email with controller, purpose, retention and the opt-out, plus the bot's visible name;
  - a right to object (art. 21): the opt-out link and in-call removal;
  - storage limitation (art. 5(1)(e)): `rec_retention`;
  - erasure (art. 17);
  - processor agreements (art. 28);
  - transfers (chapter V): EU region.
- **A DPIA (art. 35) should be done before go-live.** The processing is systematic recording plus AI analysis, and conversations may touch special categories (health customers, sick leave).
- **Own staff.** Recording staff in internal meetings can be a control measure under arbeidsmiljøloven chapter 9 (objective reason, proportionality, discussion with employee representatives, information beforehand). The default `bot_auto_join = 'external'` (the design's own text) keeps internal-only meetings out. `internal_only` is a block reason.
- **D-39 made concrete:** a notice 24 hours ahead, and a person can opt out. The opt-out works per meeting and as "never record me" (`recording_opt_outs`, keyed by a hash of the email). The bot does not join if any attendee has opted out, or if the notice could not be sent while the setting requires it.
- **Fixed rules, not settings:**
  - the bot's display name says it records;
  - on joining, the bot posts a chat line with the opt-out link;
  - the owner can remove it at once.
- **Desktop capture (MTG-03 "the user controls participant notices").** When it exists, the app requires the user to confirm that participants were told before recording starts. The confirmation is stored on `meeting_recordings`.
- **Erasure (SEC-11, SF-15).** Erasing a person:
  - deletes their `meeting_attendees` rows and `transcript_speakers` mapping;
  - redacts their segments (`text` → "[removed]", `redacted_at`);
  - deletes the audio of every meeting they attended (audio cannot be partly redacted);
  - removes them from brief quotes;
  - keeps the opt-out hash (that is the point of it).

  The Security screen's erasure toast already promises "across CRM, campaigns, tickets, meetings and files".
- **Anonymity firewall (D-19, D-34).** Briefs, recaps, suggestions and AI context read CRM tables and product **count** mirrors only. No survey response table exists here, and the firewall test asserts that no meeting or AI function references a product table other than the count mirrors. What a customer says about their survey in a call is their own speech, stored as CRM data, and never joined to product data.
- **Logs.** `ai_calls`, `app.audit` and worker logs carry ids, counts and status codes. They never carry transcript text, prompts or outputs (A7.13).

## 9. Conflicts with decisions and with existing code (named)

1. **D-38 vs MTG-03, MTG-07 and the "● Record unscheduled call" button.** The desktop recorder is deferred. The button and the two cards show "Not available yet" instead of the prototype's toasts. Log in DEVIATIONS.
2. **D-07 vs MTG-02/04.** The meeting-bot and transcription providers are not chosen, and the LLM key is absent. Those features ship as real `not_connected` states.
3. **D-39 vs the `rec_notice = off` option.** D-39 requires notice and opt-out; the design and the register (0005) offer "Off". Recommendation: keep "Off" (it removes only the advance email) and make the in-call disclosure and opt-out fixed rules. Tor should confirm in the D-27 legal review.
4. **D-16 vs PRJ-06 RU ("the AI summary must be enabled per account").** A new setting `project_ai`, defaulting to **on**.
5. **D-16 vs privacy of transcripts.** The unrestricted default would make every transcript visible to every staff member with `deals:see` (open question 13).
6. **D-08 / SEC-07 vs MTG-08 "one permission covers all features".** `app.right_ok` has no meetings scope. Recommendation: the per-user switch the design shows is the permission, on top of `deals:see`, with no new scope. That avoids a sixth matrix column the design does not have (V-SETTINGS-22 already added Tickets).
7. **D-19 vs the brief's "uses Orgpuls weekly".** There is no per-member login frequency (only `members.last_login_at`). Omit it, or show the last sign-in date. Seat-count changes are allowed (counts).
8. **D-28.** The opt-out page and any status-report share link live on `go.owntheagenda.com` with hashed, revocable tokens.
9. **D-01.** There is no generic file table yet (CRM-05). `record_files` is built here as the shared table, not a projects-only one.
10. **Existing code:** `changelog_source_check` (0022) and `rec_save`'s source whitelist (0006) lack `meeting` (MTG-05 A: "logged with the meeting as source").
11. **Existing code:** `note_save` (0009) builds `/?<uuid>` for any entity outside its `case`, which violates `notifications_route_check` (0023). A mention on a project would raise. It also notifies mentioned staff without checking that they can see the record (CRM-06 RU).
12. **Existing code: activities are in the `deals` scope.** «Regular — Projects» (0003) has no deals rights, so Emma could not see or complete her project's activities through `activities_get`/`activity_done`. Accept `projects:see` for activities whose project is visible.
13. **Existing code:** the engine refuses `project` as a trigger entity (0021 l.1181) and blocks every `project_action` (`not_available:projects`, 0026). The `won_project` template and the Automation screen's «Won deal → project» depend on lifting both.
14. **Existing code:** `report_run` whitelists five entities (0024 l.204). INS-01's project reports need `project`.
15. **Part F vs the design.** Part F says "a meeting links to one activity and optionally one deal"; the design links a lead (L-501). Allow deal, lead, person or organization, with one primary for "Linked to".
16. **Design vs D-41 / never fabricate.**
    - Every toast that announces work that did not happen goes, as in V-DEALS-15.
    - The "Workflow «Won deal → project»" hint shows only when such a workflow is active.
    - The legend "↳ depends on the row above" describes indentation, not dependencies.

## 10. Open questions, with a recommendation each

1. **Health of a new project.** *Recommend* null ("Not set": no pill, the select shows a placeholder) rather than a default "On track", which would be a status nobody set.
2. **Assignees outside the company.** The design assigns "Upload employee list" to Kari Nordmann and Mona Hansen, both customer contacts. *Recommend* allowing people as customer-side assignees (no notifications, no access), beside staff.
3. **Do dependencies move successors?** *Recommend* no automatic rescheduling. Shifting keeps spacing inside the group, and a successor that now starts before its predecessor ends is flagged.
4. **Template days: calendar or business days?** *Recommend* calendar days, matching "Day 11"; business days can come later as a template option.
5. **Closed projects on the board.** *Recommend* hidden, with a "Closed" filter (D-41). Reports count them by period.
6. **What a project-only user sees of a linked deal.** *Recommend* the deal title and person/org names only; value and stage only with `deals:see`.
7. **Who may create templates.** *Recommend* `projects:add` for saving one's own project as a template; `projects:configure` to edit or delete others'.
8. **`rec_notice = custom` encoding, and "at invite time".** *Recommend* `value_number` = hours before start (1–168), with 0 meaning "as soon as the meeting is known" (the design's "at invite time"). The copy stays as designed.
9. **Notice "Off".** *Recommend* keeping it, with the fixed in-call disclosure and opt-out (§9.3). Tor decides after the legal review.
10. **Language of notice emails.** *Recommend* bokmål and English in one email for Norwegian organisations, English otherwise; the meeting owner's locale picks the order.
11. **Erasure inside transcripts.** *Recommend* §8.3: redact the person's segments, delete audio of meetings they attended, keep everything else.
12. **Transcript retention.** The Security screen says "transcripts kept". *Recommend* transcripts live as long as the linked record (purged with it) plus erasure, with audio on `rec_retention`. Confirm in the DPIA.
13. **Default visibility of meetings and transcripts.** *Recommend* `owner` plus staff attendees for meetings (transcripts are richer than notes), as an explicit exception to D-16 that Tor confirms. The fallback is the register's `visibility_default`.
14. **Where pasted lines are parsed.** *Recommend* a pure TypeScript parser (unit-tested, locale-aware dates) with a preview. The RPC takes the structured list, so the database sees validated data only.
15. **Bot and transcription vendor.** *Recommend* one EU-hosted vendor that offers both the bot and Norwegian transcription with speaker labels, to keep the sub-processor list short. Choose before phase 7 with a DPA.
16. **How "LLM connected" is known.** 0020 checks an env key in the app («AI not configured»). *Recommend* `integration_connections('llm')` as the single source, so SQL can raise `not_connected`; move the thread insight onto it.
17. **Brief facts: deterministic or AI?** *Recommend* deterministic facts rendered from message keys, with AI limited to verbatim quotes validated against their source. The brief then exists and is truthful without the LLM.
18. **Persisting the checklist ticks.** *Recommend* yes, per user (`meeting_brief_checks`): cheap, and it makes "reviewed" visible.
19. **Meetings in ⌘K search and the generic record API.** *Recommend* not in this phase. Meetings are reached from the workspace and from linked records, so the per-user switch cannot be bypassed.
20. **Cross-board moves.** *Recommend* allowed from the drawer's phase picker (all boards grouped), not by drag, with `project_phase_history` recording the board.
21. **Project numbers.** *Recommend* `projects.seq` shown as "P-<n>" where a reference is needed (audit lines, workflow runs), as lead numbers do (0023).
22. **Desktop app scope.** *Recommend* keeping D-38 (decide with meeting intelligence). Ship the upload path first, since it gives MTG-04/05/06 value with no capture provider.
