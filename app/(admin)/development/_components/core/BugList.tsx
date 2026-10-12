'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { Bug, Bugs } from '@/lib/data/dev-core'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { createBug, fixBug, linkBugTicket, mergeBug, saveWorkItem, setBug } from '../../core-actions'
import { SEVERITIES, SEVERITY_CHIP, dueState, durationParts, share, type Severity } from './logic'
import { c, Kpi, Modal, useRun, type ProductInfo } from './kit'

/** the KPIs, the triage card and its dialogs (DevHub.dc.html, v.bugs) */
export function BugList({ data, products, filter, nf, timeZone }: { data: Bugs; products: ProductInfo[]; filter: string | null; nf: NumberFormat; timeZone: string }) {
  const t = useTranslations('devCore.bugs')
  const [dialog, setDialog] = useState<{ kind: 'new' } | { kind: 'edit' | 'merge' | 'fix'; id: string } | null>(null)
  const k = data.kpi
  const within = share(k.within_30, k.fixed_30)
  const dur = (h: number | null) => {
    if (h === null) return t('dash')
    const d = durationParts(h)
    return t(d.unit === 'min' ? 'minutes' : d.unit === 'h' ? 'hours' : 'days', { n: formatNumber(d.value, nf, d.decimals) })
  }
  const target = data.targets
  const bug = dialog && dialog.kind !== 'new' ? data.bugs.find((b) => b.id === dialog.id) ?? null : null

  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Kpi label={t('kpi.open')} value={String(k.open)} tone={k.open > 3 ? 'text-danger' : 'text-ink'} sub={t('kpi.openSub', { s1: k.s1, s2: k.s2, s3: k.s3 })} />
        <Kpi label={t('kpi.within')} value={within === null ? t('dash') : `${within} %`} tone="text-link" sub={t('kpi.withinSub')}
          title={within === null ? t('kpi.withinNone') : t('kpi.withinTitle', { within: k.within_30, fixed: k.fixed_30 })} />
        <Kpi label={t('kpi.escaped')} value={String(k.escaped_30)} tone={k.escaped_30 >= target.escaped_goal ? 'text-warn-ink' : 'text-ink'}
          sub={t('kpi.escapedSub', { goal: target.escaped_goal })} title={t('kpi.escapedTitle')} />
        <Kpi label={t('kpi.median')} value={dur(k.median_h)} sub={t('kpi.medianSub', { s1: dur(k.median_s1_h), s2: dur(k.median_s2_h) })} title={t('kpi.medianTitle')} />
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-[18px] py-3">
          <b className="text-15">{t('title')}</b>
          <span className="flex flex-wrap items-center gap-[10px]">
            <span className="text-12 text-muted">
              {t('targets', { s1: target.s1 === 'same_day' ? t('sameDay') : t('hours', { n: target.s1 }), s2: target.s2, s3: target.s3 })}
            </span>
            {data.can_add ? <button type="button" onClick={() => setDialog({ kind: 'new' })} className={c.dashed}>{t('newBug')}</button> : null}
          </span>
        </div>
        {data.bugs.map((b) => (
          <Row key={b.id} b={b} now={data.now} timeZone={timeZone} canAct={data.can_add} product={products.find((p) => p.key === b.product)?.name ?? b.product}
            showProduct={filter === null} onOpen={(kind) => setDialog({ kind, id: b.id })} />
        ))}
        {!data.bugs.length ? <div className="p-6 text-center text-13 text-muted">{t('empty')}</div> : null}
      </div>
      {dialog?.kind === 'new' ? <NewBug data={data} products={products} preset={filter} onClose={() => setDialog(null)} /> : null}
      {bug && dialog?.kind === 'edit' ? <EditBug b={bug} data={data} onClose={() => setDialog(null)} /> : null}
      {bug && dialog?.kind === 'merge' ? <MergeBug b={bug} data={data} onClose={() => setDialog(null)} /> : null}
      {bug && dialog?.kind === 'fix' ? <FixBug b={bug} canResolve={data.can_resolve} onClose={() => setDialog(null)} /> : null}
    </div>
  )
}

/** a bug's row: severity, title and due label; its tickets, problem and customers; who has it; Merge duplicate and Mark fixed */
function Row({ b, now, timeZone, canAct, product, showProduct, onOpen }: {
  b: Bug; now: string; timeZone: string; canAct: boolean; product: string; showProduct: boolean; onOpen: (kind: 'edit' | 'merge' | 'fix') => void
}) {
  const t = useTranslations('devCore.bugs')
  const ts = useTranslations('devCore.status')
  const format = useFormatter()
  const open = b.state === 'open'
  const due = dueState(b.due_at, now, timeZone)
  const dueText = b.state === 'fixed' ? t('fixed') : b.state === 'duplicate' ? t('merged') : due.kind === 'today' ? t('dueToday', { time: due.time })
    : due.kind === 'overdue' ? t('overdue', { n: due.days }) : t('daysLeft', { n: due.days })
  const dueTone = b.state !== 'open' ? 'text-link' : due.kind === 'overdue' || b.severity === 's1' ? 'text-danger' : 'text-warn-ink'
  const links: string[] = []
  if (showProduct) links.push(product)
  if (b.tickets) links.push(t('tickets', { n: b.tickets }))
  if (b.problem) {
    const label = b.problem.status === 'known_error' ? 'knownProblem' : b.problem.status === 'resolved' ? 'problemResolved' : 'problem'
    links.push(t(label, { ref: b.problem.number ? `T-${b.problem.number}` : '' }).trim())
  }
  if (b.customers) links.push(t('customers', { n: b.customers }))
  if (b.source === 'internal') links.push(t('internal'))
  const state = b.state === 'fixed'
    ? [t('fixedOn', { date: format.dateTime(new Date(b.fixed_at!), { day: 'numeric', month: 'short' }) }), b.problem?.status === 'resolved' ? t('problemClosed') : null].filter(Boolean).join(' · ')
    : b.state === 'duplicate' ? t('mergedInto', { n: b.duplicate_of?.number ?? 0 })
    : [b.assignee ? t('assigned', { name: b.assignee.name ?? '—' }) : null, b.work ? t('onBoard', { key: b.work.key, column: ts(b.work.status) }) : null]
        .filter(Boolean).join(' · ') || t('notStarted')
  return (
    <div id={`bug-${b.id}`} className={`flex scroll-mt-4 flex-col gap-[7px] border-b border-line px-[18px] py-3 target:outline target:outline-2 target:outline-ink ${b.state === 'fixed' ? 'bg-mint' : 'bg-transparent'}`}>
      <div className="flex flex-wrap items-center gap-[10px]">
        <span className={`rounded-7 px-[9px] py-[3px] text-11 font-bold ${SEVERITY_CHIP[b.severity]}`}>{b.severity.toUpperCase()}</span>
        {open && canAct ? (
          <button type="button" onClick={() => onOpen('edit')} title={t('edit')}
            className="flex-[1_1_260px] cursor-pointer border-none bg-transparent p-0 text-left text-13 font-bold text-ink hover:underline">{b.title}</button>
        ) : <b className="flex-[1_1_260px] text-13">{b.title}</b>}
        <span className={`whitespace-nowrap text-12 font-bold ${dueTone}`}>{dueText}</span>
      </div>
      {links.length ? (
        <div className="flex flex-wrap gap-[6px] text-11.5">
          {links.map((l, i) => <span key={i} className="whitespace-nowrap rounded-999 bg-tile px-2 py-[2px]">{l}</span>)}
        </div>
      ) : null}
      <div className="flex flex-wrap items-center gap-[6px]">
        <span className="flex-1 text-12 text-muted"><span className={`${c.mono} mr-[6px]`}>BUG-{b.number}</span>{state}</span>
        {open && canAct ? (
          <>
            <button type="button" onClick={() => onOpen('merge')} className={c.rowBtn}>{t('merge')}</button>
            <button type="button" onClick={() => onOpen('fix')} className={c.rowBtnPrimary}>{t('markFixed')}</button>
          </>
        ) : null}
      </div>
    </div>
  )
}

const parseNumbers = (s: string) => s.split(/[\s,;]+/).map((x) => x.replace(/^t-?/i, '')).filter(Boolean).map(Number)

/** a new bug: a customer's tickets or a problem behind it, or found internally */
function NewBug({ data, products, preset, onClose }: { data: Bugs; products: ProductInfo[]; preset: string | null; onClose: () => void }) {
  const t = useTranslations('devCore.bugs')
  const { run, pending } = useRun()
  const [product, setProduct] = useState(preset ?? products[0]?.key ?? 'sentral')
  const [title, setTitle] = useState('')
  const [severity, setSeverity] = useState<Severity>('s2')
  const [source, setSource] = useState<'ticket' | 'internal'>('ticket')
  const [problem, setProblem] = useState('')
  const [tickets, setTickets] = useState('')
  const numbers = parseNumbers(tickets)
  const numbersOk = numbers.every((n) => Number.isInteger(n) && n > 0) && numbers.length <= 50
  const ready = title.trim().length >= 3 && numbersOk && (source === 'internal' || numbers.length > 0 || !!problem)
  return (
    <Modal title={t('newTitle')} cta={t('add')} busy={pending || !ready} onClose={onClose}
      onSubmit={() => run(() => createBug({ product, title, severity, source, problem: problem || null, tickets: numbers }), () => t('added'), onClose)}>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(140px,1fr))]">
        <label className={c.field}>{t('fields.product')}
          <select value={product} onChange={(e) => setProduct(e.target.value)} className={c.select}>
            {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.severity')}
          <select value={severity} onChange={(e) => setSeverity(e.target.value as Severity)} className={c.select}>
            {SEVERITIES.map((s) => <option key={s} value={s}>{t(`severity.${s}`)}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.source')}
          <select value={source} onChange={(e) => setSource(e.target.value as 'ticket' | 'internal')} className={c.select}>
            <option value="ticket">{t('sourceTicket')}</option>
            <option value="internal">{t('sourceInternal')}</option>
          </select>
        </label>
      </div>
      <label className={c.field}>{t('fields.title')}<input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
      {data.problems ? (
        <label className={c.field}>{t('fields.problem')}
          <select value={problem} onChange={(e) => setProblem(e.target.value)} className={c.select}>
            <option value="">{t('noProblem')}</option>
            {data.problems.map((p) => <option key={p.id} value={p.id}>T-{p.number} {p.subject}</option>)}
          </select>
        </label>
      ) : null}
      <label className={c.field}>{t('fields.tickets')}
        <input value={tickets} onChange={(e) => setTickets(e.target.value)} placeholder="T-2316, T-2317" className={c.input} />
      </label>
      <span className="text-11.5 text-muted">{t('dueNote')}</span>
    </Modal>
  )
}

/** an open bug: title, severity (the due time follows), assignee, problem, its tickets, and a card on the work board */
function EditBug({ b, data, onClose }: { b: Bug; data: Bugs; onClose: () => void }) {
  const t = useTranslations('devCore.bugs')
  const { run, pending } = useRun()
  const [title, setTitle] = useState(b.title)
  const [severity, setSeverity] = useState<Severity>(b.severity)
  const [assignee, setAssignee] = useState(b.assignee?.id ?? '')
  const [problem, setProblem] = useState(b.problem?.id ?? '')
  const [ticket, setTicket] = useState('')
  const n = Number(ticket.replace(/^t-?/i, '').trim())
  const patch: Record<string, unknown> = {}
  if (title.trim() !== b.title) patch.title = title.trim()
  if (severity !== b.severity) patch.severity = severity
  if (assignee !== (b.assignee?.id ?? '')) patch.assignee_id = assignee || null
  if (problem !== (b.problem?.id ?? '')) patch.problem_id = problem || null
  const problems = [...(data.problems ?? [])]
  return (
    <Modal title={`BUG-${b.number}`} cta={t('save')} busy={pending || !Object.keys(patch).length || title.trim().length < 3} onClose={onClose} width={560}
      onSubmit={() => run(() => setBug({ id: b.id, version: b.version, patch }), () => t('saved'), onClose)}
      extra={!b.work ? (
        <button type="button" disabled={pending} className={c.small}
          onClick={() => run(() => saveWorkItem({ id: null, version: null, values: { product: b.product, kind: 'bug', title: b.title, bug_id: b.id } }),
                             (r) => ('key' in r ? t('onBoardToast', { key: r.key }) : null), onClose)}>{t('toBoard')}</button>
      ) : null}>
      <label className={c.field}>{t('fields.title')}<input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        <label className={c.field}>{t('fields.severity')}
          <select value={severity} onChange={(e) => setSeverity(e.target.value as Severity)} className={c.select}>
            {SEVERITIES.map((s) => <option key={s} value={s}>{t(`severity.${s}`)}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.assignee')}
          <select value={assignee} onChange={(e) => setAssignee(e.target.value)} className={c.select}>
            <option value="">{t('nobody')}</option>
            {data.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
      </div>
      {data.problems ? (
        <label className={c.field}>{t('fields.problem')}
          <select value={problem} onChange={(e) => setProblem(e.target.value)} className={c.select}>
            <option value="">{t('noProblem')}</option>
            {b.problem && !problems.some((p) => p.id === b.problem!.id) ? <option value={b.problem.id}>{b.problem.number ? `T-${b.problem.number}` : t('problem', { ref: '' })}</option> : null}
            {problems.map((p) => <option key={p.id} value={p.id}>T-{p.number} {p.subject}</option>)}
          </select>
        </label>
      ) : null}
      {b.ticket_numbers ? (
        <div className="flex flex-col gap-2 border-t border-line pt-3">
          <span className={c.label}>{t('linkedTickets')}</span>
          <span className="text-12.5">{b.ticket_numbers.length ? b.ticket_numbers.map((x) => `T-${x}`).join(', ') : t('noTickets')}</span>
          <div className="flex flex-wrap gap-2">
            <input value={ticket} onChange={(e) => setTicket(e.target.value)} placeholder="T-2316" aria-label={t('ticketNumber')} className={`${c.input} h-[34px] flex-[1_1_160px] text-12.5`} />
            <button type="button" disabled={pending || !Number.isInteger(n) || n <= 0} className={c.small}
              onClick={() => run(() => linkBugTicket({ id: b.id, number: n, on: true }), () => t('ticketLinked'), () => setTicket(''))}>{t('link')}</button>
            <button type="button" disabled={pending || !Number.isInteger(n) || n <= 0} className={c.small}
              onClick={() => run(() => linkBugTicket({ id: b.id, number: n, on: false }), () => t('ticketUnlinked'), () => setTicket(''))}>{t('unlink')}</button>
          </div>
          <span className="text-11.5 text-muted">{t('incidentsNote')}</span>
        </div>
      ) : null}
    </Modal>
  )
}

/** «Merge duplicate»: the bug this one duplicates keeps the tickets and the problem; this one closes */
function MergeBug({ b, data, onClose }: { b: Bug; data: Bugs; onClose: () => void }) {
  const t = useTranslations('devCore.bugs')
  const { run, pending } = useRun()
  const others = data.bugs.filter((x) => x.id !== b.id && x.state !== 'duplicate' && x.product === b.product)
  const [into, setInto] = useState(others[0]?.id ?? '')
  return (
    <Modal title={t('mergeTitle', { n: b.number })} cta={t('merge')} busy={pending || !into} onClose={onClose}
      onSubmit={() => run(() => mergeBug({ id: b.id, into, version: b.version }), () => t('mergedToast', { n: others.find((x) => x.id === into)?.number ?? 0 }), onClose)}>
      <span className="text-13 leading-[1.55]">{t('mergeBody')}</span>
      {others.length ? (
        <label className={c.field}>{t('fields.duplicates')}
          <select value={into} onChange={(e) => setInto(e.target.value)} className={c.select}>
            {others.map((x) => <option key={x.id} value={x.id}>BUG-{x.number} {x.title}</option>)}
          </select>
        </label>
      ) : <span className="text-12.5 text-muted">{t('noOthers')}</span>}
    </Modal>
  )
}

/** «Mark fixed»: says who is told before anyone is; a linked problem is resolved with the person's message */
function FixBug({ b, canResolve, onClose }: { b: Bug; canResolve: boolean; onClose: () => void }) {
  const t = useTranslations('devCore.bugs')
  const { run, pending } = useRun()
  const [body, setBody] = useState('')
  const p = b.problem && b.problem.status !== 'resolved' ? b.problem : null
  const needsBody = !!p && p.open_incidents > 0
  const blocked = !!p && !canResolve
  return (
    <Modal title={t('fixTitle', { n: b.number })} cta={t('markFixed')} busy={pending || blocked || (needsBody && !body.trim())} onClose={onClose}
      onSubmit={() => run(() => fixBug({ id: b.id, version: b.version, body }),
                          (r) => ('notified' in r ? (r.resolved ? t('fixedToastProblem', { n: r.notified }) : t('fixedToast')) : null), onClose)}>
      <span className="text-13 leading-[1.55]">
        {!p ? t('fixPlain') : needsBody ? t('fixTells', { n: p.open_incidents, ref: p.number ? `T-${p.number}` : '' }) : t('fixProblem', { ref: p.number ? `T-${p.number}` : '' })}
      </span>
      {blocked ? <span role="alert" className="text-12.5 font-semibold text-danger">{t('fixNeedsRight')}</span> : null}
      {needsBody && !blocked ? (
        <textarea value={body} onChange={(e) => setBody(e.target.value)} aria-label={t('fixMessage')} placeholder={t('fixMessage')} maxLength={20000} className={c.textarea} />
      ) : null}
    </Modal>
  )
}
