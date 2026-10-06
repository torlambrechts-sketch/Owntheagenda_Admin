/**
 * What the Feed screen shares between server and client: tab keys, the card kinds per tab (0022
 * feed_card_kinds), the design's tone per kind, and the tests a scoring criterion can make (app.wf_match).
 */
export const SCREEN_TABS = ['feed', 'scoring', 'enrich'] as const
export type ScreenTab = (typeof SCREEN_TABS)[number]

export const FEED_TABS = ['follow_ups', 'overlooked', 'suggestions'] as const
export type FeedTab = (typeof FEED_TABS)[number]

export const KINDS: Record<FeedTab, string[]> = {
  follow_ups: ['email_reply', 'no_reply', 'planned_today', 'email_opened', 'link_clicked', 'sequence_review'],
  overlooked: ['overdue_activity', 'no_followup', 'slipping', 'stalled'],
  suggestions: ['new_no_activity', 'cross_sell', 'likely_to_advance'],
}
export const AI_KINDS = ['likely_to_advance']

/** The design's bar colour per card (Feed.dc.html, all[…][0]): ok #5C9A55, warn #E0A21F, alert #D4633A, ink. */
export const KIND_TONE: Record<string, string> = {
  email_reply: 'bg-ok', no_reply: 'bg-warn', planned_today: 'bg-ok', email_opened: 'bg-ok', link_clicked: 'bg-ok', sequence_review: 'bg-warn',
  overdue_activity: 'bg-alert', no_followup: 'bg-warn', slipping: 'bg-alert', stalled: 'bg-warn',
  new_no_activity: 'bg-warn', cross_sell: 'bg-ink', likely_to_advance: 'bg-ink',
}

export const GROUPS = ['high', 'slight', 'negative'] as const
export type Group = (typeof GROUPS)[number]

/**
 * The tests «＋ Criterion» offers. Each is one wf_match filter (or two ANDed, for a range), written to the
 * criterion's condition as one AND group. `entities` says which model kinds may use it.
 */
export type CritField =
  | { key: 'email.opened' | 'email.replied' | 'email.no_reply'; input: 'days'; entities: ('deal' | 'lead')[] }
  | { key: 'participant_label'; input: 'label'; entities: ('deal' | 'lead')[] }
  | { key: 'org_products'; input: 'count'; entities: ('deal' | 'lead')[] }
  | { key: 'org_payment'; input: 'payment'; entities: ('deal' | 'lead')[] }
  | { key: 'source'; input: 'list'; entities: ('deal' | 'lead')[] }
  | { key: 'value'; input: 'range'; entities: ('deal' | 'lead')[] }
  | { key: 'org.employees'; input: 'range'; entities: ('deal' | 'lead')[] }
  | { key: 'org.city' | 'org.fylke' | 'org.industry'; input: 'text'; entities: ('deal' | 'lead')[] }

export const CRIT_FIELDS: CritField[] = [
  { key: 'email.opened', input: 'days', entities: ['deal', 'lead'] },
  { key: 'email.replied', input: 'days', entities: ['deal', 'lead'] },
  { key: 'email.no_reply', input: 'days', entities: ['deal', 'lead'] },
  { key: 'participant_label', input: 'label', entities: ['deal'] },
  { key: 'org_products', input: 'count', entities: ['deal', 'lead'] },
  { key: 'org_payment', input: 'payment', entities: ['deal', 'lead'] },
  { key: 'source', input: 'list', entities: ['deal', 'lead'] },
  { key: 'value', input: 'range', entities: ['deal', 'lead'] },
  { key: 'org.employees', input: 'range', entities: ['deal', 'lead'] },
  { key: 'org.city', input: 'text', entities: ['deal', 'lead'] },
  { key: 'org.fylke', input: 'text', entities: ['deal', 'lead'] },
  { key: 'org.industry', input: 'text', entities: ['deal', 'lead'] },
]
export const PAYMENT_STATES = ['past_due', 'suspended', 'ok'] as const
export const COUNT_OPS = ['gte', 'eq', 'lte'] as const

/** The fields Brønnøysund can fill (app.enrich_fields, 0022). */
export const ENRICH_FIELDS = ['address', 'postal_code', 'city', 'nace', 'industry', 'employees', 'website'] as const
