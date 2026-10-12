---
name: triage
description: Turn a Sentry issue and linked support tickets into a bug file. Use with a Sentry issue id.
---
1. Read the issue with the Sentry MCP: events, users, first and last seen, release.
2. Severity: S1 if survey invitations, signup or payments fail; S2 if one product area is blocked; else S3.
3. Create /roadmap/bugs/BUG-<next>-<slug>.md from _TEMPLATE.md with links and reproduction steps.
4. If a bug file already covers it, add the new links there instead.
