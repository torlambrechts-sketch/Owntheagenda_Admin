# Database requests — Inbox

Changes the Inbox screen needs and leaves out until they exist. Each names the function and the behaviour.

| Request | Status |
|---|---|
| R-INBOX-01 send as an alias | Done — 0029 (`email_send` takes `from_alias_id`); the From select offers verified send-as addresses under my own mailboxes |
| R-INBOX-02 organisation in `call_log_get` | Done — 0029; call rows read «organisation · number» |
| R-INBOX-03 whether AI is configured | Done — 0029 (provider `ai` in `integrations_get`); «Summarise» appears when it is connected |
| R-INBOX-04 inbound domain | Open — needs the email provider's inbound route and an MX record on the inbox subdomain; the drop-box shows «not configured» (V-INBOX-30) |
| R-INBOX-05 attachments | Open — needs Storage and an upload function; Attach stays disabled (V-INBOX-14) |
| R-INBOX-06 connecting a mailbox | Open — needs the Gmail/Microsoft OAuth client and the edge worker; Add mailbox and Reconnect say so (V-INBOX-28, V-INBOX-29) |

## R-INBOX-01 — send as an alias in `email_send`
The From select offers mailboxes only: `email_send(draft)` takes `mailbox_id`, and `sender_aliases(kind='send_as')`
cannot be chosen. Accept `from_alias_id` in the draft (a verified `send_as` alias of the caller), store it as
`from_addr` and pass it to the worker. Done in 0029.

## R-INBOX-02 — the organisation in `call_log_get`
The design's call row says «organisation · number». `call_log_get` returns person and deal but not the organisation;
add `'organization', (select o.name from app.organizations o where o.id = a.organization_id)` as `phone_match` does.
Done in 0029.

## R-INBOX-03 — whether AI is configured
The AI panel and the AI writer cannot tell whether a Claude key exists, so they always show «not configured» and
never offer «Summarise» (`thread_insight_request`). Expose a flag — an `integration_connections` row for the AI
provider with its status, read through the shell or `inbox_folders` — so the trigger appears when configured.
Done in 0029; V-INBOX-09 and V-INBOX-13 now read the integration.

## R-INBOX-04 — the inbound domain of the drop-box
`dropbox_address_get` returns the local part; the domain is the email provider's inbound route, which nothing
stores. A setting (or a field in `mailboxes_get`) holding the configured inbound domain lets the screen render the
full address, and «not configured» until then. Deviation V-INBOX-30.

## R-INBOX-05 — attachments
`email_attachments` exists, but no function stores a file (Storage upload) and links it to a draft. The Attach
button stays disabled until one does. Deviation V-INBOX-14.

## R-INBOX-06 — connecting a mailbox
Spec §5 names `mailbox_connect_start(provider)` → OAuth URL and `mailbox_connect_finish`. Without them (and the
OAuth client) «Add mailbox» and «Reconnect» can only say they are not available. A flag telling whether the OAuth
client is configured would let the screen switch to the real flow. Deviations V-INBOX-28, V-INBOX-29.

## Notes for other screens (not database)
- Group email reads people saved views from `views_get('contacts')` and a selection from `/inbox?folder=group&src=people&people=<ids>`.
  The Contacts screen has neither a saved people view nor a «Group email» hand-over yet (V-INBOX-22).
