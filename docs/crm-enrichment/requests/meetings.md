# Requests: Meetings (Phase 7 screen build)

Database and shared-code changes the Meetings screen needs. Each names the deviation it would close.

## Status

«0050» is `supabase/migrations/0050_crm_requests.sql`, proved by `supabase/tests/phase7_meetings_invariants.sql`.

| ID | Status |
|---|---|
| R-MEETINGS-01 | **Done in 0050.** `meeting_controls().controller` (`app.mtg_controller()`, null without a verified transactional sender). «What guests receive» names it; without one it keeps «[company]» and says no notice can go out (V-MEETINGS-19) |
| R-MEETINGS-02 | **Done in 0050.** `shell().meetings_workspace` (`deals:see`, module `meetings`, the staff member's switch — the same gate as `app.mtg_require()`); `lib/shell.ts` parses it and `components/shell/Sidebar.tsx` leaves «Meetings» out when it is false (V-MEETINGS-21) |
| R-MEETINGS-03 | **Done in 0050.** `app.mtg_brief_build`: `health:<product>` params carry `organization`; `applications` is one line per organisation with `organization`, cited to it. The brief adds the name only when two lines would read the same. Briefs built before 0050 show it after their next build (V-MEETINGS-10) |
| R-MEETINGS-04 | **Done in 0050.** `meeting_suggestions[].currency`: the deal's or lead's currency when the field is `value`, else null; the table writes «120 000 kr» (V-MEETINGS-15) |
| R-MEETINGS-05 | **Done in 0050.** `meeting_transcript.speakers[].email` (left out for a person the caller may not see); the Speakers card keeps an address mapping selected and names the guest (V-MEETINGS-13) |
| R-MEETINGS-06 | **Open.** Storage bucket and signer, not a migration (V-MEETINGS-07) |

| ID | Request | Why | Closes |
|---|---|---|---|
| R-MEETINGS-01 | `meeting_controls()` returns `controller` (`app.mtg_controller()`, null when no verified transactional sender exists) | The notice preview («What guests receive») must name the controller (art. 13); today it shows a placeholder | V-MEETINGS-19 |
| R-MEETINGS-02 | The shell hides «Meetings» for a staff member without the workspace: `public.shell()` adds e.g. `meetings_workspace boolean` (module, `deals:see`, `meeting_user_settings.enabled`) and `components/shell` reads it | MTG-08 A «a user without the permission sees no meeting workspace»; the nav item is a shared file this build may not edit | V-MEETINGS-21 |
| R-MEETINGS-03 | Brief facts `health:<product>` (and `applications`) carry the organisation's name in `params` | Two organisations with the same product give two identical «Health · Orgpuls» lines | V-MEETINGS-10 |
| R-MEETINGS-04 | `meeting_suggestions` rows carry the target's `currency` when the field is a money column (`value` on deals and leads) | The design writes «120 000 kr»; the screen cannot know the currency | V-MEETINGS-15 |
| R-MEETINGS-05 | `meeting_transcript.speakers[]` includes `email` | A label mapped to an address only (a guest unknown to the CRM) reads «Not mapped» again after the save, because the speaker row has no field that shows the mapping | V-MEETINGS-13 |
| R-MEETINGS-06 | Not a migration: the `meeting-files` bucket and the signing edge function for `meeting_transcript_upload_begin`'s path | Transcript upload cannot land without them | V-MEETINGS-07 |
