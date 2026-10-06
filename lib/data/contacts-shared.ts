/** Contacts' constants that both the server loaders and the browser components read. */
export const TABS = ['people', 'orgs', 'leads', 'timeline', 'map', 'dupes', 'import', 'export', 'restore'] as const
export type Tab = (typeof TABS)[number]
export const CONTACT_TYPES = ['prospect', 'trial_user', 'customer_user', 'former_customer', 'partner', 'other'] as const
export const MARKETING = ['subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced'] as const
