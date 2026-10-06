# Database requests — Lead capture and Web visitors

## Status

| Request | Status |
|---|---|
| R-CAPTURE-01 | Open: needs storage buckets and the upload edge function (with R-DOCUMENTS-03) |
| R-CAPTURE-02 | Open: same storage work as R-CAPTURE-01 |
| R-CAPTURE-03 | Done in 0036 (`chat_playbooks.hours`, `playbook_hours_set`, `app.chat_in_hours` in start, poll and fallback) · screen done |
| R-CAPTURE-04 | Done in 0036 (`tracking.landing_host`, tracked sites only; `form_row.landing` = host + path) · screen shows it |
| R-CAPTURE-05 | Done without a migration: `assignment_test({entity, source: 'Web form'})` · screen names the rule |

Changes the screens need and leave out until they exist. Each names the function and the behaviour.

## R-CAPTURE-01 — upload a gated download's file

A gated-download form cannot be published without `after_submit.asset_path` (app.form_check), and nothing can put a
file in the `form-assets` bucket. Add `form_asset_upload(p_form uuid, p_name text, p_size int)` → a signed upload
path in `form-assets/<form id>/…` (campaigns:add), and have `form_check` on publish confirm the object exists.
The seeded «Last ned: Lovkrav-sjekkliste» stays a draft until then. Deviation V-CAPTURE-04.

## R-CAPTURE-02 — the widget's avatar

The playbook profile shows «face» (Marketing.dc.html) but has no picture. Add an upload for `profile.avatar_path` in
the `email-assets` bucket (signed upload, campaigns:add) and return a signed read URL in `playbook_get`.
Deviation V-CAPTURE-16.

## R-CAPTURE-03 — business hours on a live-chat playbook

The design's «Snakk med oss · Chat live · business hours» needs opening hours: `chat_playbooks.hours jsonb`
(weekday → [from, to], Europe/Oslo), checked by `worker_chat_start`/`worker_chat_poll` (`online` false outside the
hours, so the offline message shows) and returned in `playbooks_get`. Deviation V-CAPTURE-14.

## R-CAPTURE-04 — the host a form is embedded on

`form_row.landing` is the landing path only; the design shows «orgpuls.com/kontakt». Store the landing host with the
tracking (`tracking.landing_host`, a hostname of a tracked site only) and return `host || path`. Deviation V-CAPTURE-02.

## R-CAPTURE-05 — which assignment rule a form's leads meet

The after-submit card names «Inbound — chatbot and forms». Add `assignment_preview(p_entity text, p_source text)` →
the first active assignment rule whose condition a record with that source would meet (name and assignee kind), so
the card can name it for source «Web form» (and the playbooks for «Chatbot»). Deviation V-CAPTURE-08.
