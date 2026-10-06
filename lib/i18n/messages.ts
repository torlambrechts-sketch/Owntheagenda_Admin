/**
 * The message catalogue, one JSON file per namespace and language. A new namespace is a file in both
 * messages/en and messages/no and a line in each list below; scripts/verify-i18n.mjs checks they agree.
 */
import enAuth from '@/messages/en/auth.json'
import enShell from '@/messages/en/shell.json'
import enCommon from '@/messages/en/common.json'
import enOverview from '@/messages/en/overview.json'
import enCustomers from '@/messages/en/customers.json'
import enContacts from '@/messages/en/contacts.json'
import enDeals from '@/messages/en/deals.json'
import enActivities from '@/messages/en/activities.json'
import enTickets from '@/messages/en/tickets.json'
import enSettings from '@/messages/en/settings.json'
import enCoverage from '@/messages/en/coverage.json'
import enInbox from '@/messages/en/inbox.json'
import enFeed from '@/messages/en/feed.json'
import enAutomation from '@/messages/en/automation.json'
import noAuth from '@/messages/no/auth.json'
import noShell from '@/messages/no/shell.json'
import noCommon from '@/messages/no/common.json'
import noOverview from '@/messages/no/overview.json'
import noCustomers from '@/messages/no/customers.json'
import noContacts from '@/messages/no/contacts.json'
import noDeals from '@/messages/no/deals.json'
import noActivities from '@/messages/no/activities.json'
import noTickets from '@/messages/no/tickets.json'
import noSettings from '@/messages/no/settings.json'
import noCoverage from '@/messages/no/coverage.json'
import noInbox from '@/messages/no/inbox.json'
import noFeed from '@/messages/no/feed.json'
import noAutomation from '@/messages/no/automation.json'

export const locales = ['en', 'no'] as const
export type Locale = (typeof locales)[number]

const catalogue = {
  en: { ...enAuth, ...enShell, ...enCommon, ...enOverview, ...enCustomers, ...enContacts, ...enDeals, ...enActivities, ...enTickets, ...enSettings, ...enCoverage, ...enInbox, ...enFeed, ...enAutomation },
  no: { ...noAuth, ...noShell, ...noCommon, ...noOverview, ...noCustomers, ...noContacts, ...noDeals, ...noActivities, ...noTickets, ...noSettings, ...noCoverage, ...noInbox, ...noFeed, ...noAutomation },
}

export const messagesFor = (locale: Locale) => catalogue[locale]
