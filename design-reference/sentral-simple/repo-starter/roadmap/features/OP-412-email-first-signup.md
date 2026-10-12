---
id: OP-412
title: Email-first signup
status: in-progress
owner: tor
product: orgpuls
priority: P1
metric: "visit→account +25 %"
flag: signup_email_first
rollout: internal
spec: RFC-014
links: [PR #881, RFC-014, funnel step 4]
---

## Problem
38 % of signup drop-offs happen at the org.nr step. Sole proprietorships fail the Brønnøysund lookup.

## Acceptance criteria
- Completion from step 1 to account created rises at least 15 % at 50 % rollout
- No rise in duplicate accounts
- No new read path to survey responses

## Tasks
- [x] Email + password step
- [x] Org.nr moved to step 2
- [x] Recovery email after 1 h
- [ ] Migration 0043_signup_email_first
- [ ] E2E test for both paths
- [ ] Help article updated

## Log
- 2026-10-12 claude: opened PR #881, 14 files, tests green
- 2026-10-11 tor: status → in-progress
