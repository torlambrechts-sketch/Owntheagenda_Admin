/** The tickets screen's fixed value sets (0012_tickets.sql checks), safe to import in client components. */
export const TICKET_TYPES = ['question', 'service_request', 'incident', 'problem'] as const
export const TICKET_STATUSES = ['new', 'open', 'waiting_customer', 'waiting_us', 'resolved', 'closed'] as const
export const IMPACTS = ['one_user', 'one_org', 'many_orgs'] as const
export const URGENCIES = ['not_blocking', 'blocking'] as const
export const PRIORITIES = ['urgent', 'high', 'normal', 'low'] as const
export const VIEWS = ['open', 'mine', 'unassigned', 'sla', 'support', 'billing', 'sales', 'personvern', 'closed', 'problems'] as const
export const SORTS = ['sla', 'priority', 'newest'] as const
export const LINK_KINDS = ['survey', 'invoice', 'deal', 'lead', 'article'] as const
export const TABS = ['inbox', 'problems', 'help', 'macros', 'reports', 'sla'] as const
export type Tab = (typeof TABS)[number]
