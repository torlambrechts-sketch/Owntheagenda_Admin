# Requests: Projects (Phase 6 screen build)

What the Projects screen needs beyond `0038_projects.sql` and `0039_phase6_engine_wiring.sql`. None of it blocks the screen:
each item is left out or shown in its honest state until the change exists (`deviations/projects.md`).

| ID | What | Why | Until then |
|---|---|---|---|
| R-PROJECTS-01 | The edge function that signs uploads and downloads for bucket `record-files` from `file_upload_begin` / `file_download_url` (`{bucket, path, expires_in}`), and the bucket itself | Uploading a file to a project and opening one (CRM-05, SF-33). The same signer serves every record type | «＋ Upload file» is disabled and a file name says the signer is not connected; listing and removing work (V-PROJECTS-19). Same dependency as R-DOCUMENTS-03 |
| R-PROJECTS-02 | The PDF worker for `project_status_report` (→ `worker_status_report_ready`), and a way for the screen to know it runs — an `integration_connections` row (e.g. provider `pdf`) or a field in `project_detail` | Without a running worker, `project_status_report_request` leaves a report «requested» for ever; the screen cannot tell whether to offer «Create PDF» | «Create PDF» disabled with «The PDF renderer is not connected yet» (V-PROJECTS-16) |
| R-PROJECTS-03 | The AI worker for `project_ai_summary`, `project_brief` and the status report draft (with the `ai` connection, V-P6P-03) | AI summary, brief and report draft (PRJ-02, PRJ-06, PRJ-07) | The banner and the brief controls show the reason from `project_detail.ai.reason` (V-PROJECTS-15) |
| R-PROJECTS-04 | `project_templates_get.preview[].day`: the start offset for a task that has one (the due offset for milestones and activities) | The design's template lines read «Day 0 · Kickoff meeting», «Day 3 · Upload employee list»: the day an item starts. With the due offset first a three-day task reads «Day 2» | Shown as the function returns it (V-PROJECTS-12) |
