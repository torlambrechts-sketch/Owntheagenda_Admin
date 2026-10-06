# Database requests — Tickets

Changes the Tickets screen needs that a screen builder may not make (no migrations in phase B). The
screen ships without them, as noted in `deviations/tickets.md`.

## R-1 A thread message for executed actions
`ticket_message` accepts only `reply` and `note`. The design posts a system message «Extend trial 14 days
executed by … Reason: T-2312. Written to the audit trail of …» when a service-request action runs. Add
`public.ticket_action_note(p_id uuid, p_action text, p_ok boolean)` (or allow `admin_action` for the
platform itself) that writes a `ticket_messages` row of kind `admin_action` with the actor, the action key
and the outcome — no free text from the caller. The screen then shows it in the thread.

## R-2 Queue and edit checks on ticket writes (security)
- `rec_save('ticket', …)` checks visibility and `tickets:edit_others`, but not `app.queue_ok(queue_key)`.
  A staff member without the personvern queue (sales, finance) who knows a ticket id can change a
  personvern ticket's fields, and can move any ticket they own into a queue they cannot see. Suggested: a
  ticket-specific guard in `rec_save` (or a `ticket_save` function) that requires `queue_ok` of both the
  current and the new queue.
- `ticket_link` checks `queue_ok` but neither `app.visible(owner_id, visibility)` nor an edit right; it
  should match `ticket_message` (assignee, owner or `tickets:edit_others`).

## R-3 `ticket_reports` previous period ignores the product
`previous` counts every product while `created` is filtered by `p_product`, so «+x % vs previous» compares
unlike sets when a product is chosen. Apply the same product filter.

## R-4 Product commands the service-request panel and the banner need (D-40)
Orgpuls commands for: change plan, export organization data (logged), switch to EHF invoice, and an
in-app status banner that reads `tickets.status_banner` / the problem's workaround. Until then the three
actions and the banner toggle are disabled with a message.

## R-5 Ticket-to-article rate
`help_get` has no source for the design's «Ticket-to-article rate». Suggest: the share of tickets created
in the last 30 days that carry a `ticket_links` row of kind `article`, returned as `article_rate`.

## R-6 CSAT average and answers
`ticket_reports.csat_avg` averages `csat_score` regardless of `csat_at`; the seed has scores without
`csat_at`, so the CSAT card shows 4,0 / 5 with «No surveys answered». Either count only answered rows or
let the seed set `csat_at`/`csat_requested_at`.

## R-7 Smaller gaps
- `ticket_detail.messages` could carry the author's initials (staff) so the avatar need not derive them.
- Organization health score and band for the organization card (phase 2 health).
- `context.app_version` for in-app intake (the product's `support.requested` payload).
- Attachment storage for the composer's Attach button.
