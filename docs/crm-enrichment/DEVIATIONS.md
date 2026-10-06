# Deviations from the design

Where the build departs from `design-reference/sentral/`, and why. A deviation is a decision, not a
shortcut: each names the constraint.

| ID | Where | Design | Built | Reason |
|---|---|---|---|---|
| V-01 | Every screen | Buttons that navigate (`go(route)`) | Links with the same classes | Control substitution: the prototype has no router |
| V-02 | Shell, rail footer | «EU residency · Stockholm» | «EU residency · Frankfurt» | D-35: the real region is eu-central-1 |
| V-03 | Shell, nav badges (Tickets 7, Feed 9, Inbox 4) | Fixed numbers | Real counts when the source exists; nothing at zero | Never fabricate |
| V-04 | Shell, notifications footer | «In app · email · desktop · push» | «In app» | Only in-app notifications exist; the other channels arrive with their providers |
| V-05 | Shell, assistant | A conversation with canned answers | The unconnected state, prompts and input disabled | Phase 7 (AI gateway, a Claude key) |
| V-06 | Shell, product picker | Product state dots (operational/degraded) | Connected or not | Product health is measured in phase 8 |
| V-07 | Overview KPIs | Five cards always | Cards whose source exists (tickets and pipeline arrive with phase 1) | Never fabricate |
| V-08 | Overview, applications | p95, error rate, version | «—» | No source until phase 8 measures command latency and errors |
| V-09 | Overview, trials | «First survey: Sent 97 d ago / Not sent» | «—» | Needs Orgpuls' count-only survey events (D-21) |
| V-10 | Overview, headline | Fixed sentence | A sentence built from the facts that exist | Never fabricate |
| V-11 | Overview, delta on paying organizations | +6 | The change in paid subscriptions since the snapshot 30 days ago | The daily snapshot counts per product |
| V-12 | Settings › Visibility defaults | Deals and leads «Owner's group and sub-groups» | Everyone for every type | D-16: rules default to unrestricted |
| V-13 | Login, second factor, no access | Not in the design | Built in the design's language | D-41 |
| V-14 | Response headers | — | Referrer-Policy same-origin (was no-referrer) | A form posted before hydration must carry its Origin or the server action refuses it |
