# Deviations — Contacts and Leads (Contacts.dc.html)

Same columns as `DEVIATIONS.md`. The lead builder folds these into it.

| ID | Where | Design | Built | Reason |
|---|---|---|---|---|
| V-CONTACTS-01 | Header, every tab | «Two-way sync · Google Contacts · Microsoft 365» | «Google Contacts · Microsoft 365 · not connected» | No contact-sync provider is connected (D-07); never fabricate a sync state |
| V-CONTACTS-02 | Person drawer, header | «Synced with Google Contacts · two-way · last sync 4 min ago» | «Not synced · Google Contacts and Microsoft 365 are not connected» | Same: no provider, no sync time to show |
| V-CONTACTS-03 | Person drawer, history | Emails («Re: Forslag · opened 2×») and files («Kontrakt-utkast.pdf») | Deals, activities and the record's changelog | No mailbox sync and no file store yet; the changelog (rec_history) is real |
| V-CONTACTS-04 | Person drawer, notes | One hard-coded pinned note with a comment | The person's notes from notes_list; pin/unpin, replies as comments, @mentions | Never fabricate. Replies and pinning are built in the design's language (D-41) |
| V-CONTACTS-05 | Person drawer, Edit and Marketing | Not drawn | An Edit button opens the record form; the Marketing fact opens a status card (consent_set with source and basis, and the consent ledger) | D-41: create/edit and consent changes are required, the design draws no control for them |
| V-CONTACTS-06 | People list, labels | The design's label colours (Decision maker lilac, Champion green …) | The colours stored on each label (labels_get) | The seed stores person and organization labels as #F2EAD6/#5F5849; the colour is data, not chosen by the screen |
| V-CONTACTS-07 | Leads, label filter | «All · Hot · Warm · Cold» | «All» and every lead label (labels_get('lead')) | The hard-coded list is replaced by the labels that exist |
| V-CONTACTS-08 | Lead panel, first line | «L-501 · Web form · 2 days ago» | «Web form · 1 day ago» | Leads have no number column; the created time is real |
| V-CONTACTS-09 | Lead panel, «Enriched company data» | Industry · employees · city · «annual revenue ~91 MNOK» · domain | «Company data»: industry · employees · city · email domain from the records | No enrichment provider; revenue does not exist in the schema |
| V-CONTACTS-10 | Lead panel, form answers | Always shown, invented answers | Shown only when the lead holds form_data | Never fabricate |
| V-CONTACTS-11 | Lead panel, «Emails on this lead» | Two emails with opens | The heading and «No mailbox is connected yet …» | No mailbox sync (D-07) |
| V-CONTACTS-12 | Leads, «Next activity» | Short phrases («Call today 14:00», «Email reply waiting») | The next open activity's time and subject; «No activity» in red; «Overdue · …» in red | Derived from activities (leads_get); «reply waiting» states have no source |
| V-CONTACTS-13 | Leads, «Label Hot» bulk action | Always «Hot» | Shown when a lead label named Hot exists; adds it to each lead keeping its other labels | rec_bulk writes one value set, so leads are grouped by their resulting label set |
| V-CONTACTS-14 | Leads, «＋ Activity for each» | A toast only | A dialog (type, subject, date, time) that creates one activity per lead with rec_save('activity') | D-41 |
| V-CONTACTS-15 | Timeline | First ten people, dots from a formula | Every person with an activity in the twelve weeks; up to two dots per week, then «+n» | Never fabricate; activities_get with a from/to range, grouped by ISO week in the staff member's time zone |
| V-CONTACTS-16 | Map | Pins at hard-coded city coordinates; «46 records plotted by address» | Placeholder tiles with «map tiles · provider adapter» and a note; the panel lists counts per city, filtered by country and fylke from the records | No geocoding or map provider yet; nothing is plotted |
| V-CONTACTS-17 | Map, country list | «Norway · Sweden · Denmark» | «All countries» and the countries the records hold | Hard-coded list replaced by data |
| V-CONTACTS-18 | Duplicates | Two hard-coded pairs with scores | duplicates_get candidates; rule checkboxes are the dedupe_* settings (disabled without global:configure); approval line reads second_admin; a «Scan now» button | The nightly scan is the only other trigger; D-41 for the button |
| V-CONTACTS-19 | Import, step 1 | «Upload spreadsheets — all entities in one session», two example files | One file per import with a record-type choice (People, Organizations, Leads) | import_run takes one record type; the example files are not shown |
| V-CONTACTS-20 | Import, file types and size | «Drop .xlsx or .csv · up to 50 000 rows» | CSV only, up to 50 000 rows and 1 MB; an .xlsx file gets «XLSX is not supported yet» | No XLSX reader; the file travels in a server action body, which Next.js limits to 1 MB (requests R-2, R-3) |
| V-CONTACTS-21 | Import, step 2 | «Suggested by the assistant — check and adjust» with confidence per column | «Matched by column name — check and adjust», no percentage | The assistant is not connected (V-05); plain column-name matching claims no confidence |
| V-CONTACTS-22 | Import, step 3 heading | «37 rows match existing records» | The real count of rows whose email (people) or org.nr (organizations) matches; leads are always created | The same keys import_run matches on |
| V-CONTACTS-23 | Import, result and history | Fixed numbers and three example imports | import_run's counts, the skip file from import_skips, revert with import_revert, history from imports_get | Never fabricate |
| V-CONTACTS-24 | Export | «Export XLSX» exports | «Export XLSX» says XLSX is not supported yet | No XLSX writer (request R-3) |
| V-CONTACTS-25 | Export, scope for Deals, Activities, Products | «Current list view» | Disabled; the full set the staff member may see | Those lists are not on this screen, so there is no current view to export |
| V-CONTACTS-26 | Restore, «Bulk changes — revertable» | Three bulk changes with Revert | Left out | No log of bulk changes that can be reverted exists (imports are reverted on the Import tab) |
| V-CONTACTS-27 | ＋ Person / ＋ Organization / ＋ Lead | A toast «form opened» | A record form (fields, owner, labels, custom fields from fields_get; delete in edit mode) | D-41 |
| V-CONTACTS-28 | Organizations, «Add as parent …» | One select | A select of the kind, then a select of the organization and «Add»; related organizations can be removed (×) | The design's select cannot say which organization; org_relation_set needs both |
| V-CONTACTS-29 | 390 px | The prototype's side panels keep their desktop columns (the lead list collapses to nothing) | Side panels stack under their lists below 768 px; wide tables scroll inside their card | The prototype is not laid out for a phone |
| V-CONTACTS-30 | Notes with an @mention | «Note saved · mentioned user notified» | The note is saved without the mention and the toast says the mention could not be delivered | note_save's notification route fails the notifications route check (request R-1) |
