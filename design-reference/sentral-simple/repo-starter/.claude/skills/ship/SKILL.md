---
name: ship
description: Prepare the current branch for review. Use when the work on a roadmap item is finished.
---
1. Run `pnpm lint`, `pnpm test` and `supabase test db`. Stop and report on any failure.
2. Run the code-reviewer and anonymity-guard subagents on the diff. Fix blocking findings.
3. Add an entry under "Unreleased" in CHANGELOG.md in plain language.
4. Tick finished tasks and set `status: review` in the feature file.
5. Mark the PR ready for review.
