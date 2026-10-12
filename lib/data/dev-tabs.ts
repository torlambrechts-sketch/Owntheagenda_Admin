/**
 * Development (DevHub.dc.html): its thirteen views, in the design's order. The last five are the design's DevClaude
 * views. dev-core builds Roadmap, Work board, Bug triage, Integrations register and Spec documents; dev-delivery the rest
 * (docs/crm-enrichment/v3/PLAN.md).
 */
export const DEV_TABS = ['roadmap', 'board', 'bugs', 'releases', 'integrations', 'code', 'metrics', 'specs', 'md', 'jobs', 'env', 'gate', 'repo'] as const
export type DevTab = (typeof DEV_TABS)[number]

/** the props every view gets: the application chosen in the rail, its number format, and the raw query string */
export type DevTabProps = { product: string; nf: import('@/lib/format').NumberFormat; searchParams: Record<string, string | string[] | undefined> }
