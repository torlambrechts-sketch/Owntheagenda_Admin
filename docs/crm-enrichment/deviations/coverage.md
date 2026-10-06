# Deviations — Spec coverage (`app/(admin)/coverage`, Coverage.dc.html)

| ID | Where | Design | Built | Reason |
|---|---|---|---|---|
| V-COVERAGE-01 | Data | `coverage-data.js` loaded by a script tag | The same data copied verbatim into `lib/data/coverage-data.ts` | No design file is loaded at run time; regenerate the module when the design data changes |
| V-COVERAGE-02 | Feature rows | ID, name, description, where | A status chip beside the name from the gap analysis (`05-GAP-FEATURES.md`, Status column: 178 Missing, 4 Partial, 1 Conflict), and a line under the heading saying it is the analysis of 6 October, before phase B | The heading's claim is about the prototype; the status says what the analysis found. It is not live progress |
| V-COVERAGE-03 | Settings tile | «15» | The number of settings in the register (`settings_get`) | Never fabricate |
| V-COVERAGE-04 | «Where →» buttons | Buttons calling `go(route)` | Links to the route's address | Control substitution (V-01) |
| V-COVERAGE-05 | Bokmål | — | Screen chrome, tabs, labels, baseline cards translated; the features' and flows' own text stays in English | The text is the specification's inventory, written in English |
| V-COVERAGE-06 | 390 px | The prototype's layout at phone width (shell rail squeezes the page) | The «Where →» link moves under the description; the expanded boxes lose the 110 px indent | The design has no phone layout; built in its language (D-41) |
