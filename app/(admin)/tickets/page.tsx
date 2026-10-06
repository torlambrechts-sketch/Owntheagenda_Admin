import { cookies } from 'next/headers'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import {
  SORTS, VIEWS, loadConfig, loadHelp, loadMacros, loadReports, loadSuperAdmins, loadTicketDetail, loadTickets, type TicketQuery,
} from '@/lib/data/tickets'
import { TABS, type Tab } from '@/lib/data/tickets-shared'
import { TicketsFrame } from './_components/TicketsFrame'
import { Inbox } from './_components/Inbox'
import { Problems } from './_components/Problems'
import { HelpCentre } from './_components/HelpCentre'
import { Macros } from './_components/Macros'
import { Reports } from './_components/Reports'
import { SlaRouting } from './_components/SlaRouting'

const REPORT_DAYS = 30

const Params = z.object({
  tab: z.enum(TABS).catch('inbox'),
  view: z.enum(VIEWS).catch('open'),
  sort: z.enum(SORTS).catch('sla'),
  q: z.string().max(100).catch(''),
  ticket: z.string().uuid().nullable().catch(null),
  new: z.string().uuid().nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

/**
 * Tickets (Tickets.dc.html). The tab, queue view, filter, sort and the open ticket live in the address, so
 * a link opens the same state (?ticket=<id> from search and notifications, ?new=<organization> from a
 * customer). Each tab loads only what it shows.
 */
export default async function TicketsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({
    tab: one(sp.tab) ?? 'inbox', view: one(sp.view) ?? 'open', sort: one(sp.sort) ?? 'sla', q: one(sp.q) ?? '',
    ticket: one(sp.ticket) ?? null, new: one(sp.new) ?? null,
  })
  const shell = await getShell()
  const product = (await cookies()).get('product')?.value ?? 'all'
  const config = await loadConfig()
  const canReports = can(shell, 'tickets', 'reports_others')
  const tabs = TABS.filter((k) => k !== 'reports' || canReports)
  const tab: Tab = tabs.includes(p.tab) ? p.tab : 'inbox'
  const products = Object.fromEntries(shell.products.map((x) => [x.key, x.name]))
  const me = { id: shell.me.id, name: shell.me.name }
  const canConfigure = can(shell, 'tickets', 'configure')
  const now = new Date().toISOString()

  let body: React.ReactNode = null
  if (tab === 'inbox') {
    // a queue the staff member may not work in is not offered (the database hides its tickets anyway)
    const view = config.queues.some((q) => q.key === p.view && !q.allowed) ? 'open' : p.view
    const query: TicketQuery = { view, q: p.q, sort: p.sort, product }
    const list = await loadTickets(query)
    const selectedId = p.ticket ?? list.rows[0]?.id ?? null
    const [ticket, macros, superAdmins, problems] = await Promise.all([
      selectedId ? loadTicketDetail(selectedId) : Promise.resolve(null),
      loadMacros(),
      loadSuperAdmins(),
      loadTickets({ view: 'problems', q: '', sort: 'newest', product: 'all' }),
    ])
    const editOthers = can(shell, 'tickets', 'edit_others')
    body = (
      <Inbox
        list={list}
        query={query}
        selectedId={ticket?.id ?? null}
        config={config}
        detail={ticket ? {
          ticket, config, macros, me, superAdmins, products, now,
          problems: problems.rows.map((x) => ({ id: x.id, ref: x.ref, subject: x.subject })),
          canEdit: editOthers || ticket.owner_id === me.id,
          canWrite: editOthers || ticket.owner_id === me.id || ticket.assignee_id === me.id,
          canAct: can(shell, 'global', 'see'),
        } : null}
      />
    )
  } else if (tab === 'problems') {
    const [problems, open, closed, help] = await Promise.all([
      loadTickets({ view: 'problems', q: '', sort: 'newest', product }),
      loadTickets({ view: 'open', q: '', sort: 'newest', product: 'all' }),
      loadTickets({ view: 'closed', q: '', sort: 'newest', product: 'all' }),
      loadHelp(),
    ])
    body = (
      <Problems
        problems={problems.rows}
        incidents={[...open.rows, ...closed.rows].filter((x) => x.problem_id)}
        articles={help.articles}
        config={config}
        products={products}
        canResolve={can(shell, 'tickets', 'edit_others')}
        canConfigure={canConfigure}
      />
    )
  } else if (tab === 'help') {
    body = <HelpCentre help={await loadHelp()} now={now} nf={shell.me.number_format} canConfigure={canConfigure} canAdd={can(shell, 'tickets', 'add')} />
  } else if (tab === 'macros') {
    body = <Macros macros={await loadMacros()} canConfigure={canConfigure} />
  } else if (tab === 'reports') {
    body = <Reports rep={await loadReports(REPORT_DAYS, product)} days={REPORT_DAYS} config={config} nf={shell.me.number_format} />
  } else {
    body = <SlaRouting config={config} canConfigure={canConfigure} />
  }

  return (
    <TicketsFrame tab={tab} tabs={tabs} config={config} product={product} canAdd={can(shell, 'tickets', 'add')} seed={p.new ? { organizationId: p.new } : null}>
      {body}
    </TicketsFrame>
  )
}
