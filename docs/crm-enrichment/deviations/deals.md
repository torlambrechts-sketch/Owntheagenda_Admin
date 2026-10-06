# Deviations — Deals

Where the Deals screen departs from `design-reference/sentral/project/Deals.dc.html`, and why. Same columns as
`DEVIATIONS.md`; the lead builder folds these in.

| ID | Where | Design | Built | Reason |
|---|---|---|---|---|
| V-DEALS-01 | Toolbar | «View as» select (Tor · super-admin / Ingrid · sales / Ola · read-only) | Left out; rights come from the signed-in staff member (`can()`), the read-only pill and the drag refusal appear for a read-only account | A demo device; the database decides rights |
| V-DEALS-02 | Cards, list, «Customize cards», drawer | Deal score badge, Score column, «Deal score» card field, «Score N — why» panel | Left out | `deals.score` is null until the scoring model (phase 4) |
| V-DEALS-03 | Drawer, dark panel | «72 % chance to advance …» with a canned action | The assistant's unconnected state with a link to API and integrations | Phase 7 (AI gateway); nothing is guessed |
| V-DEALS-04 | Drawer, history | Fixed entries (email opened, proposal signers, file attached, web visit, «No invoice yet», automation value change, assignment rule) and chips Emails, Files, Documents, Invoices, Engagement | Entries from the changelog (`rec_history`), notes and completed activities; chips All, Notes, Activities, Changelog | No source for those channels yet |
| V-DEALS-05 | Drawer, composer | Call, Email, Files, Documents, Invoice usable | Tabs shown in faint ink; input and button disabled with a «not connected» message per provider | Providers not connected (D-07) |
| V-DEALS-06 | Drawer, composer Note | «@mention to notify, pin to keep on top» · «Rich text · pinned notes stay on top» | «Write a note — saved on the deal and in its history» · «Notes follow the deal’s visibility» | Mentions, pinning and rich text are not in the composer yet; the copy must not promise them |
| V-DEALS-07 | Products view | EUR and SEK computed from NOK, «EUR and SEK converted daily», variations text | Prices that exist in `catalog_prices` or «—»; «other currencies only where a price is set»; variations from the item’s description or «—»; billing as stored (Kursrom: Installments) | No FX source; only NOK prices exist |
| V-DEALS-08 | Summary line | «Capacity: unlimited (setting) · waitlist 0» | «Capacity: <setting>»; no waitlist | No waitlist exists |
| V-DEALS-09 | Drawer, Summary | «drag sections to reorder» | Left out | Sections cannot be reordered |
| V-DEALS-10 | Advanced filter | Fields Value, Score, Idle days, Source, Label; «＋ OR group» | Fields Value, Source, Label; AND conditions only | `app.filter_sql` ANDs; score is null; idle is derived and not filterable (R-DEALS-02) |
| V-DEALS-11 | Drawer, More | «Convert back to lead» | Left out | No function turns a deal back into a lead (R-DEALS-03) |
| V-DEALS-12 | List | Every header sorts | Organization, Owner and Labels headers do not sort | `deal_list` sorts by registered columns only (R-DEALS-01) |
| V-DEALS-13 | Drawer, details and people | Decision maker, Competitor «Planday», Board meeting, two invented participants, organization health | The deal’s real custom fields (`fields_get('deal')`; none in the seed), employees from the organization, weighted value; people from `deal_detail`; no health | Never fabricate; no health score yet |
| V-DEALS-14 | Drawer, Products view | No controls to add or remove lines, set person or organization, schedule an activity at a time, reopen; «＋ Product» without an action | «＋ Product …» select and × per line; «Calculate deal value from lines» when the value is set by hand; «＋ Person», «＋ Organization», «Change», «Remove»; activity type and date/time beside «Schedule»; More › Reopen / Unarchive; «＋ Product» opens a small dialog (name, NOK price) | D-41: gaps built in the design’s language |
| V-DEALS-15 | Toasts | «project created by workflow · invoice can be created», «owner set by assignment rule», «shared with Sales team», «preview shown», «suggested in scheduling and email» | Only what happened | Those workflows and rules do not run |
| V-DEALS-16 | 390 px | Drawer body in two columns (280–330 px and the rest); tables and the filter popover overflow the viewport | Drawer body in one column under 640 px; list and catalog scroll horizontally inside their card; the filter popover fits the viewport | The prototype squeezes the drawer’s right column to about 30 px |
| V-DEALS-17 | Lost dialog | Six fixed reasons | The configured lost reasons (`lost_reasons_get`) | Data, set in Settings |
| V-DEALS-18 | Required-field dialog | Demo rule «Decision maker» from Negotiation | Driven by `deal_move`’s `missing` list (any required-from-stage field, typed input) | No such field is configured in the seed; the dialog appears once one is |
| V-DEALS-19 | Stage bar, forecast, archive | Invented stage durations, Oct–Jan fixed, a seeded deleted deal | Days from `deal_stage_history` (blank where there is none), the current month and the three after, the real trash | Never fabricate |
| V-DEALS-20 | Board | Cards in the prototype’s array order | Value, largest first (`deal_board`) | Database order |
