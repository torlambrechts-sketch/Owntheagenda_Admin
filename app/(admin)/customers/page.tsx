import { getNow, getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { loadEmailProvider } from '@/lib/mail/provider'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import {
  PRIORITY_BAR, QUEUES, adminContact, ageOf, approvalBlock, initialsOf, parseActionNote, requestDays,
} from '@/lib/data/simple-customers-shared'
import {
  loadAccount, loadAccounts, loadConfig, loadMacros, loadQueue, loadSummary, loadTicket, type SimpleTicketDetail, type Summary,
} from '@/lib/data/simple-customers'
import type { TimelineItem } from '@/lib/data/customers'
import { orgNr } from './_components/fmt'
import { SimpleTabs } from './_components/SimpleTabs'
import { SimpleAccounts, type AccountPanel, type AccountRow, type ActionKey, type Kpi } from './_components/SimpleAccounts'
import { SimpleTickets, type CannedReply, type ThreadMsg, type TicketItem, type TicketView } from './_components/SimpleTickets'
import { SupportHub } from './_components/support/SupportHub'
import { SUBS } from './_components/support/logic'

const first = (v: unknown) => (Array.isArray(v) ? v[0] : v)
const Params = z.object({
  tab: z.preprocess(first, z.enum(['accounts', 'tickets', 'support']).optional()).catch(undefined),
  org: z.preprocess(first, z.string().uuid().optional()).catch(undefined),
  queue: z.preprocess(first, z.enum(QUEUES).default('open')).catch('open'),
  ticket: z.preprocess(first, z.string().uuid().optional()).catch(undefined),
  // Help centre and support (SupportHub.dc.html): its sub-tab and the article in the editor
  sub: z.preprocess(first, z.enum(SUBS).default('metrics')).catch('metrics'),
  article: z.preprocess(first, z.string().uuid().optional()).catch(undefined),
})

type T = Awaited<ReturnType<typeof getTranslations<'simpleCustomers'>>>

/**
 * Sentral Simple › Customers (design-reference/sentral-simple/SimpleCustomers.dc.html): «Accounts», «Tickets and
 * requests» and «Help centre and support» (SupportHub.dc.html, ?tab=support&sub=…) for the application chosen in the rail.
 * The selected account (?org=) and ticket (?ticket=) live in the address, so the links other screens already use
 * (/customers?org=…) open the same account here.
 */
export default async function CustomersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = Params.parse(await searchParams)
  const shell = await getShell()
  const product = await currentProduct(shell)
  const t = await getTranslations('simpleCustomers')
  const now = await getNow()
  const nf = shell.me.number_format
  const canAccounts = can(shell, 'deals', 'see')
  const canTickets = can(shell, 'tickets', 'see')
  const tab = p.tab === 'support' && canTickets ? 'support' : (p.tab === 'tickets' && canTickets) || !canAccounts ? 'tickets' : 'accounts'
  const age = (iso: string) => { const a = ageOf(iso, now); return t(`age.${a.unit}`, { n: a.n }) }
  const productName = shell.products.find((x) => x.key === product)?.name ?? product

  let body: React.ReactNode
  let counts: { accounts: number | null; tickets: number | null }

  if (tab === 'support') {
    // the other two pills keep their counts: the open tickets and the accounts, as on their own tabs
    const [summary, accounts] = await Promise.all([loadSummary(product), canAccounts ? loadAccounts(product) : Promise.resolve(null)])
    counts = { accounts: accounts ? accounts.rows.length : null, tickets: summary?.open_tickets ?? null }
    body = (
      <SupportHub
        product={product}
        productName={productName}
        sub={p.sub}
        article={p.article ?? null}
        org={p.org ?? null}
        ticket={p.ticket ?? null}
        nf={nf}
      />
    )
  } else if (tab === 'accounts') {
    const [summary, list] = await Promise.all([loadSummary(product), loadAccounts(product)])
    counts = { accounts: list.rows.length, tickets: summary?.open_tickets ?? null }
    const rows: AccountRow[] = list.rows.map((o) => ({
      id: o.id,
      name: o.name,
      orgnr: orgNr(o.org_number),
      digits: o.org_number ?? '',
      employees: o.employees,
      status: o.status,
      statusLabel: statusLabel(t, o.status),
      plan: o.plan ?? '—',
      mrr: o.mrr ? money(o.mrr, nf) : '—',
      href: `/customers?org=${o.id}`,
    }))
    const selectedId = p.org ?? rows[0]?.id ?? null
    const panel = selectedId ? await accountPanel(selectedId, { t, nf, product, age, writer: can(shell, 'global', 'edit_others') }) : null
    body = (
      <SimpleAccounts
        kpis={kpis(t, summary, nf)}
        rows={rows}
        selectedId={selectedId}
        panel={panel}
        emptyText={t('noAccounts', { product: productName })}
      />
    )
  } else {
    const [queue, config, macros, accounts, mail] = await Promise.all([
      loadQueue(product, p.queue),
      loadConfig(),
      loadMacros(),
      canAccounts ? loadAccounts(product) : Promise.resolve(null),
      loadEmailProvider(),
    ])
    const mailReady = mail.ok && mail.data.ready_products.includes(product)
    counts = { accounts: accounts ? accounts.rows.length : null, tickets: queue.counts.open }
    const selectedId = p.ticket ?? queue.rows[0]?.id ?? null
    const ticket = selectedId ? await loadTicket(selectedId) : null
    const base = `/customers?tab=tickets&queue=${p.queue}`
    const items: TicketItem[] = queue.rows.map((x) => ({
      id: x.id,
      ref: x.ref,
      kind: t(`tickets.types.${x.type}`),
      statusLabel: t(`tickets.statuses.${x.status}`),
      subject: x.subject,
      org: x.organization?.name ?? x.person?.name ?? '—',
      bar: PRIORITY_BAR[x.priority],
      bold: x.status === 'new',
      href: `${base}&ticket=${x.id}`,
      on: x.id === ticket?.id,
    }))
    const assignees = config.assignees.flatMap((a) => (a.name ? [{ id: a.id, name: a.name }] : []))
    const canned: CannedReply[] = macros.flatMap((m) => {
      // the newest published version, bokmål first (the customers write Norwegian)
      const v = m.versions.find((x) => x.locale === 'nb') ?? m.versions.find((x) => x.locale === 'nn') ?? m.versions[0]
      return v ? [{ id: m.id, name: m.name, body: v.body }] : []
    })
    const editOthers = can(shell, 'tickets', 'edit_others')
    body = (
      <SimpleTickets
        queues={QUEUES.map((k) => ({ key: k, label: t(`tickets.queues.${k}`), count: queue.counts[k], href: `/customers?tab=tickets&queue=${k}`, on: k === p.queue }))}
        items={items}
        ticket={ticket ? ticketView(ticket, {
          t, age,
          canEdit: editOthers || ticket.owner_id === shell.me.id,
          canWrite: editOthers || ticket.owner_id === shell.me.id || ticket.assignee_id === shell.me.id,
          canApprove: can(shell, 'global', 'edit_others'),
        }) : null}
        assignees={assignees}
        canned={canned}
        me={{ name: shell.me.name }}
        mailReady={mailReady}
      />
    )
  }

  const tabs = [
    ...(canAccounts ? [{ key: 'accounts', label: t('tabs.accounts'), count: counts.accounts, href: '/customers', on: tab === 'accounts' }] : []),
    ...(canTickets ? [{ key: 'tickets', label: t('tabs.tickets'), count: counts.tickets, href: '/customers?tab=tickets', on: tab === 'tickets' }] : []),
    // the third pill has no count (SimpleCustomers.dc.html passes null)
    ...(canTickets ? [{ key: 'support', label: t('tabs.support'), count: null, href: '/customers?tab=support', on: tab === 'support' }] : []),
  ]

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <SimpleTabs tabs={tabs} />
      {body}
    </div>
  )
}

const statusLabel = (t: T, s: string | null) => (s ? (t.has(`status.${s}`) ? t(`status.${s}`) : s) : '—')

/** The KPI row (simple_customers_summary): «—» where the database has no figure. */
function kpis(t: T, s: Summary | null, nf: NumberFormat): Kpi[] {
  const kr = (n: number | null | undefined) => (n === null || n === undefined ? '—' : money(n, nf))
  const pct = s?.trial_conversion
  const reply = s?.median_first_response_min
  return [
    { key: 'mrr', label: t('kpi.mrr'), value: kr(s?.mrr), sub: t('kpi.arr', { value: kr(s?.arr) }) },
    { key: 'paying', label: t('kpi.paying'), value: s ? String(s.paying) : '—', sub: t('kpi.payingSub') },
    {
      key: 'trials', label: t('kpi.trials'), value: s ? String(s.trials) : '—',
      sub: pct === null || pct === undefined ? t('kpi.conversionNone') : t('kpi.conversion', { pct: formatNumber(pct, nf, Number.isInteger(pct) ? 0 : 1) }),
    },
    {
      key: 'open', label: t('kpi.open'), value: s?.open_tickets === null || s?.open_tickets === undefined ? '—' : String(s.open_tickets),
      sub: reply === null || reply === undefined ? t('kpi.firstReplyNone') : t('kpi.firstReply', { value: duration(t, reply, nf) }),
    },
  ]
}

/** Business minutes as the design writes a reply time: «40 min», «2 h», «2,5 h». */
function duration(t: T, min: number, nf: NumberFormat) {
  if (min < 60) return t('dur.min', { n: Math.round(min) })
  const h = Math.round((min / 60) * 10) / 10
  return t('dur.h', { n: formatNumber(h, nf, Number.isInteger(h) ? 0 : 1) })
}

const healthTone = (h: number | null) => (h === null ? '' : h < 40 ? 'text-danger' : h < 70 ? 'text-warn-ink' : 'text-link')

/** One account's card: the application's plan and MRR, health, admin contact, actions and the newest five events. */
async function accountPanel(id: string, ctx: { t: T; nf: NumberFormat; product: string; age: (iso: string) => string; writer: boolean }): Promise<AccountPanel> {
  const { t, nf, product, age, writer } = ctx
  const r = await loadAccount(id)
  if (!r.ok) return { ok: false, code: r.code }
  const o = r.data.detail
  const sub = o.subscriptions.find((s) => s.product === product) ?? null
  const status = sub?.status ?? o.status
  const hasOrgpuls = o.subscriptions.some((s) => s.product === 'orgpuls')
  const trialWhy = product !== 'orgpuls' ? t('actions.why.otherProduct') : !hasOrgpuls ? t('actions.why.noOrgpuls') : !writer ? t('actions.why.noRight') : null
  const notYet = t('actions.why.notYet')
  const actions: { key: ActionKey; why: string | null }[] = [
    { key: 'trial', why: trialWhy },
    { key: 'plan', why: notYet },
    { key: 'login', why: notYet },
    { key: status === 'suspended' ? 'reactivate' : 'suspend', why: notYet },
  ]
  return {
    ok: true,
    id: o.id,
    name: o.name,
    sub: [o.org_number ? orgNr(o.org_number) : null, o.city, o.industry].filter(Boolean).join(' · '),
    status,
    statusLabel: statusLabel(t, status),
    facts: [
      { key: 'plan', value: sub?.plan ?? '—', tone: '' },
      { key: 'mrr', value: sub?.mrr ? money(sub.mrr, nf) : '—', tone: '' },
      { key: 'health', value: o.health === null ? '—' : String(o.health), tone: healthTone(o.health) },
    ],
    contact: adminContact(o.users, o.contacts, product),
    actions,
    recent: r.data.timeline.slice(0, 5).map((e, i) => ({ key: `${i}`, text: recentText(t, e), when: age(e.at) })),
  }
}

/** A timeline row in words: product events and admin actions by their key, a ticket by its number. */
function recentText(t: T, e: TimelineItem) {
  if (e.kind === 'support') return t('recent.ticket', { ref: e.ref ?? '' })
  if (e.kind === 'admin') {
    const key = `recent.admin.${e.event ?? ''}`
    const failedKey = `recent.adminFailed.${e.event ?? ''}`
    const what = e.event && t.has(key) ? t(key) : t('recent.adminOther')
    const text = e.ok !== false ? what : e.event && t.has(failedKey) ? t(failedKey) : t('recent.failed', { what })
    return [text, e.actor].filter(Boolean).join(' · ')
  }
  const key = `recent.events.${e.event ?? ''}`
  return e.event && t.has(key) ? t(key) : t('recent.eventOther')
}

/** One ticket as the detail column draws it: header, request, thread, and what the staff member may do. */
function ticketView(tk: SimpleTicketDetail, ctx: { t: T; age: (iso: string) => string; canEdit: boolean; canWrite: boolean; canApprove: boolean }): TicketView {
  const { t, age } = ctx
  const open = tk.status !== 'resolved' && tk.status !== 'closed'
  const person = tk.person?.name ?? null
  let request: TicketView['request'] = null
  if (tk.type === 'service_request' && open) {
    const why = approvalBlock({ request: tk.request, product: tk.product, organizationId: tk.organization_id, subscriptionStatus: tk.subscription?.status ?? null }, ctx.canApprove)
    const k = tk.request?.kind
    const what = !k || k === 'other' ? tk.subject
      : k === 'extend_trial' ? t('tickets.request.kinds.extend_trial', { days: requestDays(tk.request) })
        : k === 'change_plan' ? (tk.request?.args.plan ? t('tickets.request.kinds.change_plan', { plan: tk.request.args.plan }) : t('tickets.request.kinds.change_plan_any'))
          : t(`tickets.request.kinds.${k}`)
    const whyText = why ? t(`tickets.request.why.${why}`) : null
    request = { text: t('tickets.request.line', { what, why: whyText ?? t('tickets.request.applies') }), why: whyText }
  }
  const thread: ThreadMsg[] = tk.messages.map((m) => {
    const who = m.author ?? (m.kind === 'customer' ? tk.person?.email ?? null : null) ?? '—'
    if (m.kind === 'admin_action' || m.kind === 'system') {
      const a = m.kind === 'admin_action' ? parseActionNote(m.body) : null
      const key = a ? `tickets.thread.actions.${a.action.replace('.', '_')}.${a.ok ? 'ok' : 'failed'}` : ''
      const text = a ? (t.has(key) ? t(key) : t('tickets.thread.actionOther', { action: a.action, outcome: t(`tickets.thread.outcome.${a.ok ? 'ok' : 'failed'}`) })) : m.body
      return {
        id: m.id, who: m.kind === 'system' ? t('tickets.thread.system') : who, kind: t(m.kind === 'system' ? 'tickets.thread.system' : 'tickets.thread.action'),
        when: age(m.created_at), text, ini: '✓', cust: false, note: true,
      }
    }
    const kind = m.kind === 'customer' ? t('tickets.thread.customer', { channel: t(`tickets.thread.channels.${tk.channel}`) })
      : m.kind === 'note' ? t('tickets.thread.note')
        : m.delivery_status === 'sent' || m.delivery_status === 'delivered' ? t(m.delivery_status === 'delivered' ? 'tickets.thread.replyState.delivered' : 'tickets.thread.reply')
          : t(`tickets.thread.replyState.${m.delivery_status ?? 'not_configured'}`)
    return { id: m.id, who, kind, when: age(m.created_at), text: m.body, ini: initialsOf(who === '—' ? null : who), cust: m.kind === 'customer', note: m.kind === 'note' }
  })
  return {
    id: tk.id,
    ref: tk.ref,
    version: tk.version,
    meta: [t(`tickets.types.${tk.type}`), tk.organization?.name, person].filter((x): x is string => !!x),
    subject: tk.subject,
    status: tk.status,
    priority: tk.priority,
    impact: tk.impact,
    urgency: tk.urgency,
    assigneeId: tk.assignee_id,
    request,
    thread,
    person: { name: person, first: person ? person.split(' ')[0]! : null },
    merge: { organisasjon: tk.organization?.name ?? null, orgnr: tk.organization?.org_number ? orgNr(tk.organization.org_number) : null },
    canEdit: ctx.canEdit,
    canWrite: ctx.canWrite,
  }
}
