# Meetings and AI gateway schema (Phase 7): deviations, message keys, RPCs

Migration `supabase/migrations/0042_meetings_ai.sql` (runs after 0040 and 0041), proved by `supabase/tests/phase7_meetings_invariants.sql` (175 checks).
Spec: `docs/crm-enrichment/specs/projects-meetings.md` §2, §3.2 (it called the migration 0028), §4–§10. Design: `design-reference/sentral/project/Meetings.dc.html`.

Nothing is connected: no calendar adapter, meeting bot, transcription, AI provider or email provider. The database models the whole flow anyway. The `worker_*` functions stand in for the providers: a worker reports what the provider did, and the database decides what may happen next.

## Deviations from the spec

| ID | Where | Spec | Built | Reason |
|---|---|---|---|---|
| V-P7M-01 | Rights (§5, §9.6) | Brief: «scope `meetings`» | No new rights scope. The workspace is `deals:see` plus module `meetings` plus the per-user switch `meeting_user_settings.enabled` (no row means on). Refused with `forbidden`, detail `deals:see` or `meetings:disabled`. Workspace and controls need `global:configure`. Link, capture, remove the bot, delete a recording, map speakers, upload into an existing meeting and regenerate the recap need the owner or `deals:edit_others` | This is the spec's own recommendation (§9.6, MTG-08: «one permission covers all features»). A new scope would add a sixth matrix column that the design does not have. **The lead should confirm**, because the task brief said «scope meetings» |
| V-P7M-02 | AI provider (§3.2, Q16) | New row `llm`, detail `llm` | The existing `ai` row (0029). `not_connected` carries detail `ai` | Same as V-P6P-03 |
| V-P7M-03 | `mailboxes.kind` | Add `'meeting'` | Not added. `meeting_user_settings.mailbox_id` may point at any mailbox the staff member owns or is a member of | No writer can create a «meeting» mailbox yet (`worker_mailbox_connected` takes personal or team). A kind with no writer would fail the wiring rule |
| V-P7M-04 | Visibility (Q13) | `owner` plus staff attendees; fallback `visibility_default` | A new meeting is `owner` by default, as an explicit exception to D-16. An admin can override it with the existing `visibility_default` setting, scope `meeting` (tested). A staff attendee always sees the meeting | Uses the existing register; no new setting. Tor should confirm the exception |
| V-P7M-05 | Notices (§2.7) | Job → edge mailer → `worker_notice_result` | The job (`app.mtg_notices_due`, every 5 min) puts `{job: 'meeting_notices', meeting_id}` on the queue. The mailer then calls `worker_notice_claim(meeting)`, which returns each untold external guest with a fresh opt-out token. Only the SHA-256 of the token is stored, and no token ever goes on the queue. `meetings.notice_queued_at` prevents re-queuing within an hour. A notice is required only when the meeting is to be recorded (`capture = 'bot'`) and has external guests. It is blocked (fail closed, so the bot stays out) when the email provider is not connected **or** there is no verified transactional sender domain whose `from_name` can be named as the controller (art. 13) | Keeps plaintext tokens out of pgmq. A notice for a meeting nobody records would tell people something untrue |
| V-P7M-06 | In-call opt-out (§8.3 «the bot posts a chat line with the opt-out link») | — | `meetings.call_opt_out_sha256`. `worker_bot_state(m, 'in_call')` returns the token once. `meeting_opt_out` accepts either an attendee's token or the call's token. The call's token makes the bot leave and blocks it (`opted_out`). It carries no address, so «always» does not apply to it | The fixed rule needs a link that works for people who never got a notice |
| V-P7M-07 | Extra functions and shapes | — | `worker_notice_claim`, `worker_meeting_ai_context` (the AI context builder, CRM tables only, SF-24.2), `meeting_opt_out_staff` (an objection someone tells the owner; writes `via = 'staff'`), and `app.mtg_*` helpers. Signature changes: `worker_transcript_ready(..., p_speakers default null, p_error text default null)`; `p_segments` may be `{language, segments}`; `p_quotes` is an object `{state, ai_call_id, quotes}`; `p_recap` is `{state, ai_call_id, takeaways, next_steps}` | The spec's states and the AI log need these carriers |
| V-P7M-08 | Enums | `meeting_recaps.state` requested/ready/failed; `quotes_state` none/ready/not_connected/failed | Recap state adds `not_connected`; `quotes_state` adds `requested`; briefs add `since_at`; recordings add `participants_confirmed_at` (MTG-03, §8.3) and `created_at`; uploads have state `uploaded` and `transcript_id`; attendees have `external` | Honest states for «AI not connected» and for work in flight |
| V-P7M-09 | State label (§2.1) | blocked, notice due, bot joins, processing, n suggestions, recap saved, recap ready | Adds `cancelled`, `bot_in_call`, `transcription_failed` (with its code), and `transcript_ready` (a transcript whose recap is not ready, for example because the AI provider is not connected) | Each one is a state the database can actually be in. Never stored, always derived |
| V-P7M-10 | Consent gate on recordings | «Otherwise blocked» | `worker_recording_ready` returns `{ok: false, refused: <reason>}` and queues the file for deletion. It does not raise, because a raise would roll back the deletion job. Reasons: `disabled`, `opted_out`, `bot_not_admitted` or the bot's block reason, `notice_not_sent`, `no_link`, `internal_only`, `not_connected`, and `not_confirmed` (desktop without the participants' confirmation) | Fail closed, and the refused audio does not linger |
| V-P7M-11 | Retry (SF-21.7) | Retry a failed transcription | Retry replaces the failed provider transcript with a new one in processing; the recording is kept. An uploaded transcript cannot be retried (`invalid`, detail `source`) because its file is deleted after parsing. Upload it again | The upload file is gone by design (§2.5) |
| V-P7M-12 | Plan next activity | `deals:see` | Goes through `rec_save('activity', …, 'meeting')`, so it needs `deals:add` | The generic create decides as it does for every activity |
| V-P7M-13 | Upload into an existing meeting | «workspace» | Owner or `deals:edit_others`. Without a meeting, anyone with the workspace may upload (this creates an unlinked meeting they own) | Adding a transcript to someone else's meeting is an edit |
| V-P7M-14 | New contact and `contact_rule` (MTG-05 RU, SF-34.4) | Follows contact_rule | Under `opt_in_only`: state `failed`, error `forbidden`, detail `setting:contact_rule`. Under `source_and_basis`: the person is created with `source = 'Meeting'` and no consent status | The basis concerns marketing consent, which a meeting suggestion does not set |
| V-P7M-15 | Accept (§2.4) | `rec_save(…, base_version, …)` | The snapshot is compared per value: if the field's current value differs from `current_value`, the item is `stale` and nothing is written. `rec_save` is called without a version, so «Accept all remaining» on several fields of one record does not go stale against itself. `version_conflict` still becomes `stale`. A missing right leaves the item `pending`, with the error in the result. A rule (`invalid`, a setting) or a gone record makes it `failed` | Accepting one field bumps the version; the per-value check keeps the «never overwrite» rule |
| V-P7M-16 | Suggestion validation | «registry» | The target must be linked to the meeting: its deal, its lead, attendee people known to the CRM, and their organisations (A7.10). The field must be a writable plain column of kind text, int, numeric, boolean or date (never `owner_id` or `visibility`), the labels, or a live custom field (`check_custom`). The value type is checked. A new person (`*new`) needs a name and may carry only name, title, email, phone and one of the meeting's organisations. Anything else is dropped and counted. At most 50 suggestions per recap | The prototype's «Lead · Expected close» is a column that does not exist, so it is dropped |
| V-P7M-17 | Transcript retention (Q12) | Transcripts follow the linked record | When the purge (`app.purging`) empties a meeting's last link, the trigger `meeting_link_purged` soft-deletes the meeting. `app.mtg_purge` deletes soft-deleted meetings 30 days later, with their history and storage. Unlinking by hand deletes nothing. There is no meeting delete function | Q12 without a second clock |
| V-P7M-18 | Erasure (§8.3) | — | A trigger of its own, `person_erased_meetings` (`app.person_erased` from 0037 stays as it is). Only speakers mapped to the person, by id or address, are redacted. An unmapped raw label in an uploaded transcript cannot be identified as that person | Not redefining 0031/0037's function avoids a merge collision |
| V-P7M-19 | Opt-out after the call | — | An opt-out does not delete a recording already made. The owner has «Stop and delete recording» | The spec is silent. Flag it for the D-27 legal review |
| V-P7M-20 | Inbox insight (Q16) | Move the thread insight onto the connection | `thread_insight_request` (0020 body) now raises `not_connected` (`ai`) | Q16 |
| V-P7M-21 | Project summary call (V-P6P-04) | `ai_call_id` on `project_ai_summaries` | Column added (nullable FK). `worker_project_summary_ready` (0038 body) takes optional `p_result.ai_call_id`; when given, it must be a `project_summary` call in the log | Asked for |
| V-P7M-22 | `ai_calls` | Log | Append-only (`ai_call_fixed`): only a deleted admin's id may empty itself (FK), and rows are deleted only under `app.purging`. No retention rule. `worker_ai_call` refuses any state other than `not_connected` while `ai` is not connected, and refuses unknown keys (a `prompt` is refused by name) | Nothing may claim an AI call that could not have happened |
| V-P7M-23 | Events | Spec list | Adds `meeting.created` (a meeting made by an upload). Meeting events are not workflow trigger entities (§6) | Upload-made meetings are not «scheduled» |
| V-P7M-24 | Desktop capture (D-38, §9.1) | Not available | `meeting_capture_set(…, 'desktop')` raises `not_available` (`desktop`); capabilities report `desktop: 'not_available'`. Recordings already model desktop with the confirmation. No `meeting_capture_devices` | D-38 |
| V-P7M-25 | Brief facts (§2.2, §9.7) | — | Change kinds: `field_changed`, `email_engagement`, `ticket_resolved`, `participant_added`, `count_changed`. «Prefers phone mornings» is omitted; «uses Orgpuls weekly» becomes `last_signed_in`; document views are not included yet. Items whose source the reader may not see are filtered out when read. Facts: `deal` or `lead`, `score`, `health:<product>`, `applications`, `custom.<key>` (important or required deal fields) | No source, or not yet |
| V-P7M-26 | Slack announcement (MTG-04 RU) | — | When `slack` is connected, `worker_recap_ready` queues `meeting_recap_announce` and sets `announced_at`; otherwise in-app only | No Slack consumer exists yet (left open) |
| V-P7M-27 | Auto-link at calendar scan | Deal by attendee, or an existing activity | An activity of the same owner with the same join link wins (its links are taken). Otherwise: the first external attendee known to the CRM, their organisation, and the open deal of that person or else of the organisation | A person-linked meeting has a basis for its brief; truly unlinked meetings keep the flag |
| V-P7M-28 | Capture choice | From `bot_auto_join` | Set at creation only, and only while `meeting_bot` is connected. A later change of choice refreshes existing meetings' bot plans but does not change their capture | The owner's explicit choice for a meeting wins |
| V-P7M-29 | Quotes (§2.2) | The gateway checks substrings | Checked in the database (`worker_brief_quotes_ready`): exact substring of the cited segment or note, from a source on the same deal, lead, organisation or people, never redacted; speaker and date come from the source; at most 10 | Anti-fabrication cannot depend on the worker |
| V-P7M-30 | AI rights for meetings | — | None beyond the workspace and the connection. The spec names `projects:ai` only; no `meeting_ai` setting | Spec §5 and §7 |

### Redefined functions (merge order)

- `public.rec_save`: 0006 body; the source whitelist adds `'meeting'`. Nothing else.
- `app.entity_route`: 0038 body plus `meeting → /meetings`.
- `app.integration_connections` provider check: 0040's list (with `pdf`) plus `meeting_bot`, `transcription`.
- `app.changelog` `changelog_source_check`: 0030's list plus `meeting`.
- `public.worker_project_summary_ready`: 0038 body plus `ai_call_id`.
- `public.thread_insight_request`: 0020 body plus `app.require_connected('ai')`.
- Not touched: the engine (`wf_*`), `app.person_erased`, `note_save`, `app.filter_sql`, the report functions, `prj_template_row`, `campaign_*`.

## AI call log: every place that should log

| Feature | Exists? | Wired |
|---|---|---|
| `meeting_recap` (recap and suggestions) | yes | `meeting_recaps.ai_call_id` through `p_recap.ai_call_id` (must be a successful `meeting_recap` call) |
| `meeting_brief` (quotes) | yes | `meeting_briefs.ai_call_id` through `p_quotes.ai_call_id` |
| `project_summary` (PRJ-06) | yes | `project_ai_summaries.ai_call_id` (new column) through `p_result.ai_call_id` |
| `project_brief` (PRJ-02), `status_report_draft` (PRJ-07) | yes | `worker_ai_call` with subject `project` or `project_status_report` (no column; the log's subject names the record) |
| `thread_insight` (AIA-04, inbox) | yes | `worker_ai_call` with subject `email_thread`; the request now needs the connection |
| Assistant (AIA-01, V-05), email writer / inbox drafting (AIA-03), import mapping (AIA-05), integration recommendations (AIA-06), AI report suggestions (INS-09, `reports.source = 'ai'`) | no | Log with `worker_ai_call` when built |

## Message keys the app must add

Notifications (kind `system`; params are the meeting title and counts, never what was said). Route `/meetings?meeting=<id>`, entity `meeting`:

| Key | Params | To |
|---|---|---|
| `meeting.transcript_ready` / `meeting.transcript_failed` | `record` | owner |
| `meeting.recap_ready` / `meeting.recap_failed` | `record`, `suggestions` | owner |
| `meeting.notice_blocked` | `record` | owner (the notice could not go out; the bot stays out) |
| `meeting.recording_blocked` | `record`, `reason` | owner (the bot was blocked at join time) |
| `meeting.opted_out` | `record` | owner (no address) |

Other keys:
- **State label `state.key`:** `cancelled | recording_blocked (reason) | notice_due (at) | bot_joins | bot_in_call | processing | transcription_failed (reason) | suggestions (n) | recap_saved | recap_ready | transcript_ready`, or null.
- **Groups:** `upcoming | review | history`.
- **`bot_state`:** `none | scheduled | joining | in_call | removed | left | failed | blocked`.
- **`bot_block_reason`:** `notice_not_sent | opted_out | not_connected | no_link | disabled | internal_only`.
- **`notice_state`:** `not_required | pending | sent | blocked`.
- **`capture`:** `bot | desktop | upload | none`.
- **`conference`:** `meet | teams | zoom | phone | in_person | other`.
- **`source`:** `calendar | adhoc | upload | desktop`.
- **Recap state:** `none | requested | ready | failed | not_connected`.
- **`quotes_state`:** `none | requested | ready | not_connected | failed`.
- **Transcript state:** `processing | ready | failed`, with codes such as `parse_failed`, `provider_failed`, or the provider's own.
- **Suggestion state:** `pending | accepted | rejected | stale | failed`.
- **Recording refusals:** see V-P7M-10.
- **Brief change kinds and fact keys:** see V-P7M-25.
- **Capabilities:** `calendar | meeting_bot | transcription | ai | email | slack` take `not_connected | connected | error`; `desktop` is `not_available`.
- **Settings:** `rec_retention` (group `meetings`; options `12_months | custom (months) | keep`); `rec_notice` (existing; custom = hours, 0 = as soon as known).
- **Error details:** `deals:see`, `meetings:disabled`, `deals:edit_others`, `global:configure`, `deals:add`, `not_connected: ai | meeting_bot | transcription | calendar | email`, `not_available: desktop`, and `invalid` with `link | capture | starts_at | bot_state | item_key | filename | mime | size | state | source | recording | saved | recap | step | type | values | email | decision | ids | enabled | bot_auto_join | mailbox_id | history_before`, among others.

Events (`app.events`, ids and counts only):
- `meeting.scheduled | meeting.updated {deal, lead, person, organization}`
- `meeting.created {source}`
- `meeting.linked {deal, lead, person, organization}`
- `meeting.notice_sent {count}`
- `meeting.opted_out {count}`
- `meeting.bot_removed {from}`
- `meeting.recording_deleted {recordings, transcripts}`
- `meeting.recorded {duration_s, method}`
- `meeting.transcribed {transcript, duration_s}`
- `meeting.recap_ready {transcript, suggestions}`
- `meeting.recap_saved {note, entity, record}`
- `meeting.updates_approved {accepted, rejected, stale, failed}`
- `activity.created {meeting, deal}`

Jobs on the pgmq queue `jobs`:
- `meeting_calendar_scan {staff_id, days}` → `worker_meeting_upsert`
- `meeting_notices {meeting_id}` → `worker_notice_claim` / `worker_notice_result`
- `meeting_bot_join {meeting_id, join_url, conference, starts_at, display_name_suffix: '(recording)'}` → `worker_bot_state`
- `meeting_bot_leave {meeting_id}`
- `meeting_transcribe {transcript_id, recording_id, meeting_id}` → `worker_transcript_ready`
- `meeting_upload_parse {upload_id, transcript_id, meeting_id, bucket, path, mime}` → `worker_upload_parsed`
- `meeting_brief_quotes {meeting_id, staff_id}` → `worker_meeting_ai_context` + `worker_ai_call` + `worker_brief_quotes_ready`
- `meeting_recap {transcript_id, meeting_id}` → the same with `worker_recap_ready`
- `meeting_recap_announce {meeting_id, transcript_id}`
- `files_purge {bucket: 'meeting-files', paths}`

Cron jobs:
- `platform-meeting-calendar-scan`: every 10 min
- `platform-meeting-notices`: every 5 min
- `platform-meeting-bots`: every minute
- `platform-meeting-briefs`: every 10 min
- `platform-meeting-purge`: 03:23

Storage: a private bucket `meeting-files`, with paths `recording/<meeting>/…` and `upload/<meeting>/<upload>.<ext>`.

## RPCs for the screen builder

All are `security definer`, `search_path = ''`, and granted to `authenticated`. Every one checks the workspace gate (module, `deals:see`, the switch) except `meeting_controls` and `meeting_user_set`, which check `global:configure` and the module.

Errors:
- `forbidden`
- `not_found` (also for meetings the caller may not see)
- `invalid` (detail = field)
- `version_conflict` (detail = current version)
- `not_connected` (detail = provider)
- `not_available` (`desktop`)
- `module_off`

### Reads
- `meetings_workspace(p_query jsonb default '{}')`. Query: `{history_before: ISO time, history_limit: 1..100 (30), mine: boolean}`. Returns `{upcoming: [row], review: [row], history: [row], history_next: time | null, capabilities, can_configure}`.
  - Row: `{id, title, at, starts_at, ends_at, source, conference, capture, group, state: {key, n?, reason?, at?} | null, organization: {id, name} | null, attendees: {first, others, total, external}, link: {entity, id, title, seq?} | null, linked, owner: {id, name, initials}, is_sample, version}`.
  - `linked = false` means «Not linked», which needs the link picker.
  - `attendees.first` / `others` gives «Ole Hansen, 4 others».
- `meeting_detail(p_id uuid)` returns the row plus:
  - `{join_url, visibility, cancelled_at, can_edit, activity_id, links: {deal, lead, person, organization, primary, linked}}`
  - `attendee_list: [{email, name, person_id, staff_id, external, response, notice_sent_at, opted_out}]`
  - `notice: {state, due_at, sent_at, setting, hours}`
  - `bot: {state, reason}`
  - `recording: {id, method, state, duration_s, purge_after, deleted_at} | null`
  - `transcript: {id, source, state, error_code, duration_s, speaker_count, language, file_name, ready_at} | null`
  - `recap: {state, saved_at, note_id} | null`
  - `suggestions_pending`
  - `brief: {state, generated_at, quotes_state} | null`
  - `default_tab: 'brief' | 'transcript'`
  - `history: [{at, field, old, new, source, actor}]`
  - `created_at, updated_at`

  The read is audited.
- `meeting_brief(p_id uuid)` returns `{state: 'none' | 'ready' | …, generated_at, since_at, last_contact_at, linked, changes: [{key, kind, at, params, source: {entity, id}, checked}], people: [{person_id, name, title, labels, first_meeting, last_signed_in, source}], facts: [{key, ord, params, source}], quotes: [{text, kind: 'segment' | 'note', transcript_id?, seq?, note_id?, meeting_id?, speaker, person_id, at, record}], quotes_state, ai, instructions_set}`.
- `meeting_transcript(p_id uuid, p_cursor int default 0, p_limit int default 200)` returns `{transcript | null, speakers: [{label, staff_id, person_id, name, kind: 'staff' | 'external' | 'unknown'}], segments: [{seq, start_ms, end_ms, label, text, redacted}], next: seq | null}`.
  - Staff ink is `#191510`; external is `#2F5D2A`.
  - Text is untrusted (escape it).
- `meeting_recap(p_id uuid)` returns `{transcript_id, state, takeaways: [{text, seq}], next_steps: [{text, seq, activity_id?}], generated_at, saved_at, announced_at, note: {id, entity, record_id} | null, save_target, ai, can_edit}`. Clicking an item scrolls to `seq`.
- `meeting_suggestions(p_id uuid)` returns `{transcript_id, suggestions: [{id, ord, target_entity, target_id, target_title, field, field_label, current_value, proposed_value, evidence, state, error_code, decided_by, decided_at, written_record_id, stale_now}]}`. For a new contact, `field = '*new'` and the proposed value is `{name, title, …}`.
- `meeting_controls()` returns `{users: [{id, name, title, initials, enabled, bot_auto_join, mailbox: {id, address, status, kind, own} | null, calendar}], rec_notice: {value, hours}, rec_retention: {value, months}, visibility_default, capabilities}`.
  - The mailbox `status` value `reauth` gives «(re-auth)»; `own` means «own»; null means «no mailbox».
  - Write the notice choice with `setting_set('rec_notice', 'on_24h' | 'custom' | 'off', '', hours)`.
- `meeting_my_settings()` returns the caller's user row plus `brief_instructions`.

### Writes
- `meeting_link(p_id uuid, p_values jsonb, p_version int default null)`. Values: any of `{deal_id, lead_id, person_id, organization_id}` (null unlinks). Returns `{id, version, activity_id, links}`.
- `meeting_capture_set(p_id uuid, p_capture text)`: `bot | none` (future meetings). Returns `{id, version, capture, bot, notice}`.
- `meeting_bot_remove(p_id uuid)` returns `{id, bot_state: 'removed'}`.
- `meeting_recording_delete(p_id uuid, p_with_transcript boolean default false)` returns `{id, recordings, transcripts}`.
- `meeting_brief_check(p_id uuid, p_item_key text, p_checked boolean)` returns `{key, checked}`.
- `meeting_brief_regenerate(p_id uuid)` returns `{id, state, generated_at, quotes_state}`.
- `meeting_transcript_upload_begin(p_meeting uuid, p_filename text, p_mime text, p_size bigint)`. Accepts `text/vtt | application/x-subrip | text/plain | …wordprocessingml.document`, up to 5 MB, with the extension matching the type. Returns `{id, meeting_id, bucket, path, expires_in}`.
- `meeting_transcript_upload_done(p_upload uuid)` returns `{id, transcript_id, state: 'processing'}`. The toast may only say «Transcript uploaded».
- `meeting_transcript_retry(p_transcript uuid)` returns `{id, state: 'processing'}`.
- `meeting_speaker_map(p_transcript uuid, p_label text, p_values jsonb)`. Values: `{staff_id} | {person_id} | {email} | {}`. Returns `{label, staff_id, person_id, email}`.
- `meeting_recap_regenerate(p_transcript uuid)` returns `{transcript_id, state: 'requested'}`.
- `meeting_recap_save_note(p_id uuid, p_entity text default null, p_record uuid default null)` returns `{note_id, entity, record_id, already}`. Label: «✓ Saved as note on the <entity>».
- `meeting_next_step_activity(p_id uuid, p_step int, p_values jsonb default '{}')`. Values: `{type, starts_at, duration_min, owner_id}`. Returns `{activity_id, step}`.
- `meeting_suggestion_decide(p_ids uuid[], p_decision text)`: `accept | reject`, 1..100 ids. Returns `{results: [{id, state, error?, detail?, record_id?}], written}`. Show the «Updates written» toast only when `written > 0`, with the count.
- `meeting_user_set(p_staff uuid, p_values jsonb)`. Values: `{enabled, bot_auto_join, mailbox_id}`. Returns the user row.
- `meeting_my_settings_set(p_values jsonb)`. Values: `{bot_auto_join, brief_instructions, mailbox_id}`. Returns my settings.
- `meeting_opt_out_staff(p_id uuid, p_email text, p_always boolean default false)` returns `{id, opted_out}`.

### Service role (edge functions and workers)
- `meeting_opt_out(p_token text, p_always boolean default false)` returns `{date, organiser_company}`. Called by the public page on go.owntheagenda.com.
- `worker_meeting_upsert(p_staff uuid, p_event jsonb)` returns `{id, created, skipped}`.
- `worker_notice_claim(p_meeting uuid)` returns `{meeting_id, starts_at, ends_at, owner: {name, email, locale}, controller, retention_months, bot_name_suffix, attendees: [{email, name, token}]}`.
- `worker_notice_result(p_meeting uuid, p_email text, p_ok boolean)` returns `{ok, notice_state, bot_state}`.
- `worker_bot_state(p_meeting uuid, p_state text, p_reason text default null)`: `in_call | left | failed | removed`. Returns `{ok, leave, bot_state, opt_out_token?}`.
- `worker_recording_ready(p_meeting uuid, p_values jsonb)` returns `{ok, recording_id, transcript_id} | {ok: false, refused}`.
- `worker_transcript_ready(p_transcript uuid, p_segments jsonb, p_speakers jsonb default null, p_error text default null)` and `worker_upload_parsed(p_upload uuid, p_segments jsonb)` return `{ok, segments}`.
- `worker_meeting_ai_context(p_job jsonb)` returns the context for `meeting_recap` or `meeting_brief`.
- `worker_ai_call(p_values jsonb)` returns `{id}`.
- `worker_brief_quotes_ready(p_meeting uuid, p_quotes jsonb)` returns `{ok, kept, dropped}`.
- `worker_recap_ready(p_transcript uuid, p_recap jsonb, p_suggestions jsonb default '[]')` returns `{ok, suggestions, dropped}`.
- `worker_project_summary_ready(p_id uuid, p_result jsonb)`: 0038 contract plus `ai_call_id`.

## Left open
- **Rights scope (V-P7M-01).** The lead decides between the spec (no scope) and a `meetings` scope.
- **Edge functions and workers:** calendar adapters (Google, Graph), the notice mailer, the bot vendor, transcription, the upload parser (VTT, SRT, TXT, DOCX), the AI gateway (context → Claude → `worker_ai_call` → `worker_*_ready`, one retry), the Slack announcement, and the `files_purge` consumer for `meeting-files`.
- **Storage:** the bucket `meeting-files` must exist (private).
- **Legal:** the D-27 legal review and a DPIA before go-live (§8.3); `rec_notice = off` (Q9); V-P7M-19.
- **Old projects suite in this worktree:** `phase6_projects_invariants.sql` here predates 0040 and fails at line 417 with or without 0042. The lead's updated copy (and `phase6_requests_invariants.sql`) passes after 0042.
- **No seed** for meetings.
