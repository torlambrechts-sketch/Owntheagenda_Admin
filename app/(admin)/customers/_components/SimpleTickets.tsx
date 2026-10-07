'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { PRIORITIES, TICKET_STATUSES, type IMPACTS, type URGENCIES } from '@/lib/data/tickets-shared'
import { pairFor, type Queue } from '@/lib/data/simple-customers-shared'
import { saveTicket, sendMessage } from '../../tickets/actions'
import { fillMerge, placeholders } from '../../tickets/_components/merge'
import { approveRequest } from '../actions'
import { useErrorText } from './useErrorText'

type Status = (typeof TICKET_STATUSES)[number]
type Priority = (typeof PRIORITIES)[number]

export type QueueChip = { key: Queue; label: string; count: number; href: string; on: boolean }
export type TicketItem = { id: string; ref: string; kind: string; statusLabel: string; subject: string; org: string; bar: string; bold: boolean; href: string; on: boolean }
export type ThreadMsg = { id: string; who: string; kind: string; when: string; text: string; ini: string; cust: boolean; note: boolean }
export type CannedReply = { id: string; name: string; body: string }
export type TicketView = {
  id: string
  ref: string
  version: number
  meta: string[]
  subject: string
  status: Status
  priority: Priority
  impact: (typeof IMPACTS)[number]
  urgency: (typeof URGENCIES)[number]
  assigneeId: string | null
  request: { text: string; why: string | null } | null
  thread: ThreadMsg[]
  person: { name: string | null; first: string | null }
  merge: { organisasjon: string | null; orgnr: string | null }
  canEdit: boolean
  canWrite: boolean
}

const fieldLabel = 'flex h-8 items-center gap-[6px] rounded-9 border border-line pl-[10px] pr-1 text-12 text-muted'
const fieldSelect = 'border-0 bg-transparent text-12.5 font-bold disabled:opacity-100'

/** Customers › Tickets and requests (SimpleCustomers.dc.html, v.tickets): queues, the list, one ticket and the composer. */
export function SimpleTickets({ queues, items, ticket, assignees, canned, me }: {
  queues: QueueChip[]
  items: TicketItem[]
  ticket: TicketView | null
  assignees: { id: string; name: string }[]
  canned: CannedReply[]
  me: { name: string }
}) {
  const t = useTranslations('simpleCustomers')
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <nav className="flex flex-wrap gap-[5px] border-b border-line px-3 py-[10px]">
          {queues.map((q) => (
            <Link
              key={q.key}
              href={q.href as never}
              scroll={false}
              aria-current={q.on ? 'page' : undefined}
              className={`flex-none whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink hover:text-ink hover:no-underline ${q.on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
            >
              {q.label} {q.count}
            </Link>
          ))}
        </nav>
        <div className="max-h-[640px] overflow-auto">
          {items.map((x) => (
            <Link
              key={x.id}
              href={x.href as never}
              scroll={false}
              aria-current={x.on ? 'true' : undefined}
              className={`flex w-full gap-[10px] border-b border-line px-3 py-[11px] text-left text-ink hover:text-ink hover:no-underline ${x.on ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className={`w-[5px] flex-none self-stretch rounded-999 ${x.bar}`} />
              <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
                <span className="flex justify-between gap-2 text-11 text-muted">
                  <span><b className="text-ink">{x.ref}</b> · {x.kind}</span>
                  <span>{x.statusLabel}</span>
                </span>
                <span className={`text-13 leading-[1.3] ${x.bold ? 'font-bold' : 'font-semibold'}`}>{x.subject}</span>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11.5 text-muted">{x.org}</span>
              </span>
            </Link>
          ))}
          {items.length === 0 ? <div className="p-[30px] text-center text-13 text-muted">{t('tickets.emptyQueue')}</div> : null}
        </div>
      </div>
      {ticket ? <Detail key={ticket.id} ticket={ticket} assignees={assignees} canned={canned} me={me} /> : null}
    </div>
  )
}

function Detail({ ticket: tk, assignees, canned, me }: { ticket: TicketView; assignees: { id: string; name: string }[]; canned: CannedReply[]; me: { name: string } }) {
  const t = useTranslations('simpleCustomers')
  const err = useErrorText()
  const flash = useToast()
  const router = useRouter()
  const [busy, setBusy] = useState(false)
  // what the selects show: the saved ticket, with a change in flight on top until the saved version comes back
  const [pending, setPending] = useState<Partial<{ status: Status; priority: Priority; assignee: string }>>({})
  useEffect(() => { setPending({}) }, [tk.version])
  const shown = { status: tk.status, priority: tk.priority, assignee: tk.assigneeId ?? '', ...pending }
  const [mode, setMode] = useState<'reply' | 'note'>('reply')
  const [draft, setDraft] = useState('')
  const [macroId, setMacroId] = useState<string | null>(null)
  const [after, setAfter] = useState<'waiting_customer' | 'resolved' | 'keep'>('waiting_customer')
  const note = mode === 'note'

  async function save(values: Parameters<typeof saveTicket>[0]['values'], next: typeof pending) {
    setPending({ ...pending, ...next })
    setBusy(true)
    const r = await saveTicket({ id: tk.id, version: tk.version, values })
    setBusy(false)
    if (!r.ok) { setPending({}); flash(err(r.code)); return }
    router.refresh()
  }
  const setPriority = (p: Priority) => {
    const pair = pairFor(p, { impact: tk.impact, urgency: tk.urgency })
    if (pair) void save(pair, { priority: p })
  }

  async function approve() {
    if (busy) return
    setBusy(true)
    const r = await approveRequest({ ticketId: tk.id })
    setBusy(false)
    flash(r.ok ? t('tickets.request.done') : err(r.code.startsWith('http_') ? 'unreachable' : r.code))
    router.refresh()
  }
  function decline() {
    setMode('reply')
    setMacroId(null)
    setDraft(t('tickets.request.declineDraft', { first: tk.person.first ?? '', agent: me.name }).replace(/^(\S+) ,/, '$1,'))
  }
  function applyCanned(id: string) {
    const c = canned.find((x) => x.id === id)
    if (!c) return
    setMacroId(c.id)
    setDraft(fillMerge(c.body, { fornavn: tk.person.first, organisasjon: tk.merge.organisasjon, orgnr: tk.merge.orgnr, agent: me.name }))
  }
  async function send() {
    if (busy || !draft.trim() || !tk.canWrite) return
    const left = placeholders(draft)
    if (!note && left.length) { flash(t('tickets.composer.placeholders', { fields: left.join(', ') })); return }
    setBusy(true)
    const r = await sendMessage({ id: tk.id, kind: mode, body: draft, after: note || after === 'keep' ? null : after, macroId, mentions: [] })
    setBusy(false)
    if (!r.ok) { flash(err(r.code)); return }
    setDraft('')
    setMacroId(null)
    flash(t(note ? 'tickets.composer.saved' : 'tickets.composer.sent'))
    router.refresh()
  }

  const current = assignees.some((a) => a.id === shown.assignee) || !shown.assignee ? assignees : [...assignees, { id: shown.assignee, name: '—' }]

  return (
    <div className="flex min-w-0 flex-col gap-3 lg:col-span-2">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-4">
        <div className="text-12 text-muted"><b className="text-ink">{tk.ref}</b>{tk.meta.map((x) => ` · ${x}`).join('')}</div>
        <div className="font-serif text-21 font-semibold leading-[1.2]">{tk.subject}</div>
        <div className="flex flex-wrap items-center gap-2">
          <label className={`${fieldLabel} ${tk.canEdit ? '' : 'opacity-70'}`}>
            {t('tickets.fields.status')}
            <select value={shown.status} disabled={!tk.canEdit || busy} onChange={(e) => void save({ status: e.target.value as Status }, { status: e.target.value as Status })} className={fieldSelect}>
              {TICKET_STATUSES.map((s) => <option key={s} value={s}>{t(`tickets.statuses.${s}`)}</option>)}
            </select>
          </label>
          <label className={`${fieldLabel} ${tk.canEdit ? '' : 'opacity-70'}`}>
            {t('tickets.fields.priority')}
            <select value={shown.priority} disabled={!tk.canEdit || busy} onChange={(e) => setPriority(e.target.value as Priority)} className={fieldSelect}>
              {PRIORITIES.map((p) => <option key={p} value={p}>{t(`tickets.priorities.${p}`)}</option>)}
            </select>
          </label>
          <label className={`${fieldLabel} ${tk.canEdit ? '' : 'opacity-70'}`}>
            {t('tickets.fields.assignee')}
            <select value={shown.assignee} disabled={!tk.canEdit || busy} onChange={(e) => void save({ assignee_id: e.target.value || null }, { assignee: e.target.value })} className={fieldSelect}>
              <option value="">{t('tickets.fields.unassigned')}</option>
              {current.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </label>
        </div>
        {tk.request ? (
          <div className="flex flex-wrap items-center gap-[10px] rounded-14 border border-ink bg-highlight px-[13px] py-[11px]">
            <span className="flex-[1_1_220px] text-12.5 text-amber-ink"><b className="text-ink">{t('tickets.request.label')}</b> {tk.request.text}</span>
            <button
              type="button"
              disabled={!!tk.request.why || busy}
              title={tk.request.why ?? undefined}
              onClick={() => void approve()}
              className={`h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[13px] text-12.5 font-bold disabled:cursor-default ${tk.request.why ? 'opacity-55' : ''}`}
            >
              {t('tickets.request.approve')}
            </button>
            <button
              type="button"
              disabled={!tk.canWrite}
              onClick={decline}
              className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-surface px-3 text-12.5 font-semibold disabled:cursor-default disabled:opacity-55"
            >
              {t('tickets.request.decline')}
            </button>
          </div>
        ) : null}
      </div>
      {tk.thread.map((m) => (
        <div key={m.id} className="flex items-start gap-[10px]">
          <span className={`flex h-8 w-8 flex-none items-center justify-center rounded-10 text-11 font-bold ${m.cust ? 'bg-tile text-ink' : 'bg-ink text-highlight'}`}>{m.ini}</span>
          <div className={`min-w-0 flex-1 rounded-16 border px-[14px] py-3 ${m.note ? 'border-amber-bg bg-highlight' : 'border-line bg-surface'}`}>
            <div className="mb-[5px] flex justify-between gap-[10px] text-12 text-muted">
              <span><b className="text-ink">{m.who}</b> · {m.kind}</span>
              <span className="whitespace-nowrap">{m.when}</span>
            </div>
            <div className="whitespace-pre-wrap text-13 leading-[1.6]">{m.text}</div>
          </div>
        </div>
      ))}
      <div className={`overflow-hidden rounded-18 border bg-surface ${note ? 'border-amber-bg' : 'border-line'}`}>
        <div className={`flex flex-wrap items-center gap-1 border-b border-line p-[6px] ${note ? 'bg-highlight' : 'bg-canvas'}`}>
          {(['reply', 'note'] as const).map((k) => {
            const on = mode === k
            return (
              <button
                key={k}
                type="button"
                aria-pressed={on}
                onClick={() => setMode(k)}
                className={`cursor-pointer rounded-9 border-0 px-3 py-[6px] text-12.5 ${on ? (k === 'reply' ? 'bg-surface font-bold' : 'bg-amber-bg font-bold') : 'bg-transparent font-medium'}`}
              >
                {t(`tickets.composer.${k}`)}
              </button>
            )
          })}
          <span className="flex-1" />
          <select
            value=""
            aria-label={t('tickets.composer.canned')}
            onChange={(e) => applyCanned(e.target.value)}
            disabled={!tk.canWrite}
            className="h-[30px] min-w-0 max-w-[200px] rounded-9 border border-line bg-surface text-12"
          >
            <option value="">{t('tickets.composer.canned')}</option>
            {canned.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </div>
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          disabled={!tk.canWrite}
          aria-label={t(`tickets.composer.${mode}`)}
          placeholder={!tk.canWrite ? t('tickets.composer.locked') : note ? t('tickets.composer.phNote')
            : tk.person.name ? t('tickets.composer.phReply', { name: tk.person.name }) : t('tickets.composer.phReplyNoName')}
          className="block min-h-[110px] w-full resize-y border-0 bg-transparent px-[14px] py-3 text-13 leading-[1.55] outline-none"
        />
        <div className="flex flex-wrap items-center justify-end gap-2 border-t border-line px-[10px] py-2">
          <select
            value={after}
            aria-label={t('tickets.composer.afterLabel')}
            onChange={(e) => setAfter(e.target.value as typeof after)}
            className="h-8 rounded-9 border border-line bg-surface text-12"
          >
            {(['waiting_customer', 'resolved', 'keep'] as const).map((k) => <option key={k} value={k}>{t(`tickets.composer.after.${k}`)}</option>)}
          </select>
          <button
            type="button"
            onClick={() => void send()}
            disabled={busy || !tk.canWrite || !draft.trim()}
            className={`h-[34px] flex-none cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold disabled:cursor-default ${tk.canWrite ? '' : 'opacity-55'}`}
          >
            {t(note ? 'tickets.composer.save' : 'tickets.composer.send')}
          </button>
        </div>
      </div>
    </div>
  )
}
