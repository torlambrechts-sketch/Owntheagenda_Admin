/** The Automation screen's tabs (Automation.dc.html, `tabs`), shared by the page and its client components. */
export const TABS = ['list', 'builder', 'templates', 'monitor', 'assign', 'sequences'] as const
export type Tab = (typeof TABS)[number]
