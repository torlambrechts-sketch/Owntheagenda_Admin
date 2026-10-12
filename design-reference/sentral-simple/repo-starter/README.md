# Repo starter — Claude Code + GitHub + Vercel + Supabase

Copy these files into the root of the monorepo. Sentral's Development section reads them through the GitHub API.

| Path | Purpose |
|---|---|
| CLAUDE.md | Project memory and hard rules for every Claude session |
| roadmap/ROADMAP.md | Now / Next / Later overview |
| roadmap/features/_TEMPLATE.md | Template — front matter is what Sentral reads |
| roadmap/features/OP-412-email-first-signup.md | Example feature file |
| roadmap/bugs/_TEMPLATE.md | Bug template |
| .claude/skills/{start,ship,triage,plan-feature}/SKILL.md | Slash-command workflows |
| .claude/agents/{code-reviewer,anonymity-guard}.md | Subagents with limited tools |
| .claude/settings.json + .claude/hooks/*.sh | Hooks: protect files, lint, log to Sentral |
| .mcp.json | GitHub, Supabase, Vercel and Sentry MCP servers |
| .github/workflows/claude.yml | @claude mentions and jobs sent from Sentral |
| .github/workflows/roadmap-sync.yml | Front matter ⇄ GitHub Issues, nightly rules check |

## Secrets to add in GitHub
- ANTHROPIC_API_KEY
- SENTRAL_WEBHOOK_TOKEN (the Stop hook and the audit script post to Sentral)
- SUPABASE_ACCESS_TOKEN, VERCEL_TOKEN (read-only for CI)

## Status flow
backlog → spec → in-progress → review → staging → rollout → done
