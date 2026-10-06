# Database and platform requests — Contacts and Leads

Changes the Contacts screen needs that a screen builder may not make. The screen works without them and
says so where a feature is missing (see `deviations/contacts.md`).

## R-1 — note_save: a note with an @mention is refused (bug)
`public.note_save` (0009) notifies mentioned staff with the route
`'/' || 'contacts?person=' || p_id` (and `deals?deal=`, `customers?org=`, `leads?lead=`). `app.notifications.route`
(0007) is checked against `^/[a-z0-9/_-]*$`, which refuses `?` and `=`, so the insert raises 23514 and the whole
note is rolled back. Every screen's notes are affected. Fix in a new migration: either widen the check to allow a
query string (`^/[a-z0-9/_-]*(\?[a-z_]+=[0-9a-f-]{36})?$`) or store the route without the query and use
`entity`/`record_id` to build the link. Until then the Contacts drawer saves the note without the mention and says so.

## R-2 — Server action body size for imports
The import sends the CSV text through server actions, which Next.js limits to 1 MB, so the screen refuses
files over 1 MB although import_run accepts 50 000 rows. Raise `experimental.serverActions.bodySizeLimit`
in `next.config.ts` (e.g. `'8mb'`), or add an upload route that stores the file and passes a reference. Then
raise `MAX_BYTES` in `lib/data/contacts-import.ts`.

## R-3 — XLSX import and export
The design accepts and offers .xlsx. Reading and writing XLSX needs a library (e.g. SheetJS `xlsx` or `exceljs`)
added to package.json. Until then the screen says «XLSX is not supported yet» on both tabs.

## R-4 — Lead numbers
The design shows «L-501» on a lead. `app.leads` has no number; deals have `seq`. Add
`seq bigint generated always as identity unique` to leads and return it from leads_get if the number is wanted.

## R-5 — Seed: person and organization label colours
`scripts/seed/generate.mjs` gives every person and organization label `#F2EAD6/#5F5849`. The design colours
them (Decision maker `#E7DAF2/#3E2A5C`, Champion `#CFE7E4/#20431C`, Billing contact `#FBEBBE/#5C4600`,
Newsletter `#CFE0F5/#1F3A5C`, VIP `#F0B9A0/#6B240C`, Contacts.dc.html `lab`). The screen draws the stored colours.

## R-6 — Revertable bulk changes (Restore tab)
The Restore tab's «Bulk changes — revertable» needs a record of each rec_bulk call (who, when, the record ids
and the values before) and a function to revert one. Neither exists; the section is left out.
