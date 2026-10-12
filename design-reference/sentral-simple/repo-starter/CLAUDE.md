# Orgpuls monorepo

## Stack
- Next.js 15 on Vercel (apps/web, apps/sentral)
- Supabase: Postgres, Auth, Storage, Edge Functions (supabase/)
- TypeScript strict, pnpm workspaces

## Hard rules
- NEVER read, join or export survey response tables. Aggregates go through views that enforce n >= 5.
- Every new feature ships behind the flag named in its feature file.
- Migrations are reversible and include RLS policies and pgTAP tests.
- No secrets in code. Use env vars from Vercel and Supabase.

## Workflow
1. Read the feature or bug file in /roadmap before writing code.
2. Branch: `<id>-<slug>`. PR title: `<id>: <title>`. PR body links the file.
3. Tick tasks in the file as you finish them. Do not change `status` past `review` — humans do that.
4. Before opening a PR: `pnpm lint && pnpm test && supabase test db`.
5. Ask the `anonymity-guard` subagent to check any change touching supabase/ or exports.

## Commands
- `pnpm dev` · `pnpm test` · `supabase start` · `supabase db diff -f <name>`
