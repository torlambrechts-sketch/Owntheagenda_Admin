import { getNow } from 'next-intl/server'
import { getShell, can } from '@/lib/shell'
import { loadContacts, TABS, type Tab } from '@/lib/data/contacts'
import { ContactsScreen } from './ContactsScreen'

type SP = Record<string, string | string[] | undefined>
const one = (v: string | string[] | undefined, max = 100) => (typeof v === 'string' ? v.slice(0, max) : '')

/**
 * Contacts and Leads are one screen (Contacts.dc.html, imported with tab="people" by the contacts route
 * and tab="leads" by the leads route). The tab, the open record and the filters come from the address.
 */
export async function ContactsPage({ searchParams, defaultTab }: { searchParams: Promise<SP>; defaultTab: Tab }) {
  const sp = await searchParams
  const shell = await getShell()
  const now = await getNow()
  const asked = one(sp.tab) as Tab
  const tab: Tab = defaultTab === 'leads' ? 'leads' : TABS.includes(asked) && asked !== 'leads' ? asked : 'people'
  const query = {
    q: one(sp.q), type: one(sp.type, 40), consent: one(sp.consent, 40), label: one(sp.label, 64),
    archived: one(sp.archived) === '1', leadLabel: one(sp.ll, 64),
  }
  const data = await loadContacts(tab, query, { person: one(sp.person, 64) || undefined, lead: one(sp.lead, 64) || undefined, org: one(sp.org, 64) || undefined }, shell.me.time_zone, now)
  const rights = {
    add: can(shell, 'deals', 'add'), del: can(shell, 'deals', 'delete'), bulk: can(shell, 'deals', 'bulk'),
    editOthers: can(shell, 'deals', 'edit_others'), exp: can(shell, 'deals', 'export'), configure: can(shell, 'global', 'configure'),
  }
  return <ContactsScreen data={data} rights={rights} me={{ id: shell.me.id, nf: shell.me.number_format, tz: shell.me.time_zone }} now={now.toISOString()} />
}
