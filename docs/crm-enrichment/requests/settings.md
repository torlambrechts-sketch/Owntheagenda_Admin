# Database and backend requests — Settings

For the lead builder. Each is left out of the screen (disabled with a message) until it exists.

## R-SETTINGS-01 Currencies with Norges Bank exchange rates (CUS-06)
Settings › Language and currencies shows NOK as the company default only, and «＋ Custom currency» is
disabled. Needed:
- `app.currencies (code text primary key check (code ~ '^[A-Z]{3}$'), name text, active boolean, is_default boolean, custom boolean, ord int)`,
  one default (NOK), RLS on, no policy, no grant, a suite check.
- `app.exchange_rates (code, rate_date date, rate numeric, source text default 'norges_bank', primary key (code, rate_date))`.
- A daily job (pg_cron → edge function) fetching Norges Bank's EXR series (data.norges-bank.no SDMX, `EXR/B..NOK.SP`) and storing the rate per active currency.
- `currencies_get()` (code, name, latest rate and its date, active, default) and `currency_save(code, values)` requiring `global:configure`, audited.
- The screen then lists them in the design's rows (code, name, «x,xx NOK», Default/Active) with the rate date.

## R-SETTINGS-02 Invitation e-mail for a new staff member (SEC-09, SF-43)
`staff_save(null, …)` creates the staff row; the person can sign in with that e-mail and set up TOTP, but
nothing tells them. Needed: an edge function (transactional stream, D-07) sending the invitation with the
sign-in address, triggered after `staff.invited` (outbox or a direct call from the action), audited with
kind and status only. The screen's toast then becomes «Invite sent · MFA required at first login».

## R-SETTINGS-03 Reset the sandbox from the demo seed (CUS-08)
«Reset from seed» is disabled. Needed: `sandbox_reset()` requiring `global:configure` that clears the sample
records (as `sandbox_clear`) and re-creates the Lumio AS demo tenant as sample records (`is_sample`) from the
seed generator's data, logs `sandbox.reset` with counts, and returns them. `sandbox_counts` should then also
return `last_reset`.

## R-SETTINGS-04 A read of the record-type registry — done (0023, `entities_get`; the screen uses it)
The Data fields chips and the visibility defaults read the record types from the keys of `sandbox_counts()`,
the only function that lists every row of `app.entities`. A small `entities_get()` (key, scope, module,
owned, ord) would make the order and the scope (for the right to configure) come from the database.

## R-SETTINGS-05 Field keys of archived fields — done (0023: `invalid`, detail `key`; the retry is gone, the screen names the taken key)
`field_save` keeps an archived field's key, so adding a field with the same label again fails with a
unique violation (23505 → `failed`). The action retries once with a short suffix. A nicer fix: map 23505 to
`invalid` with detail `key`, or let `fields_get` return archived keys to the configuring staff member.

## R-SETTINGS-06 First day of the week
The design shows «First day of week: Monday» per user. No column holds it; it is left out. If wanted: a
`week_start` on `app.admins` (1 or 7) in `profile_set` and the shell.
