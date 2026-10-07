# Requests: Mobile (Phase 8 screen build)

## Status

| Request | Status |
|---|---|
| R-MOBILE-01 | Done in 0046 (`nearby` volatile); structure_invariants now refuses any non-volatile public function that writes |
| R-MOBILE-02 | Done: `Permissions-Policy` allows `geolocation=(self)`; camera and microphone wait for capture uploads (R-MOBILE-04) |
| R-MOBILE-03..06 | Open: push (VAPID reader, service worker, manifest), the record-files signer, coordinates and ids in the reads |

Database and shared-code changes the Mobile screen needs. Each names the deviation it would close.

| ID | Request | Why | Closes |
|---|---|---|---|
| R-MOBILE-01 | New migration: redefine `public.nearby(numeric, numeric, numeric, text[], jsonb)` as `volatile` (same body) | It is declared `stable` but calls `app.log` (an insert). PostgREST runs stable functions in a read-only transaction, so every call from the app fails with 25006 «cannot execute INSERT in a read-only transaction». The SQL suite does not see it because it runs read-write. Worth a structure check: no `stable` public function may call `app.log` | V-MOBILE-11 |
| R-MOBILE-02 | Shared file `next.config.ts`: `Permissions-Policy` `geolocation=(self)` (and later `camera=(self), microphone=(self)` for capture) | `geolocation=()` switches location off for every page, so «Use my location» cannot ask. The screen asks only on the user's click and never stores the position | V-MOBILE-10 |
| R-MOBILE-03 | `push_vapid_public_key()` for staff (the public key only, or null), a service worker, and the PWA manifest under `/m/*` | `push_device_register` needs a browser subscription made with the provider's public key; `worker_vapid_key` is the service role's and returns the private key too | V-MOBILE-24 |
| R-MOBILE-04 | Not a migration: the signing edge function for the `record-files` bucket (`file_upload_begin`'s path), as R-MEETINGS-06/R-PROJECTS | Audio notes, photos and scans (`capture_save`) cannot land without an upload | V-MOBILE-16 |
| R-MOBILE-05 | `nearby()` rows carry `lat`/`lng` of the organisation's place (not the device's) | Pins can be drawn only where the place is known; today the result has distances only | V-MOBILE-09 |
| R-MOBILE-06 | `mobile_focus().today[]` carries `deal_id` and `organization_id` | «Deal on the go» picks the deal of the next activity; today it needs a second call (`activities_get`) to find the id | — |
