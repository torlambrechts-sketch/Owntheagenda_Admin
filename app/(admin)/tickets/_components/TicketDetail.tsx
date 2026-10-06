'use client'

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { extendTrial, linkTicket, saveTicket, sendMessage } from '../actions'
import { DAY_MIN, PTONE, STATUS_TONE, initialsOf, orgNumber, priorityOf, useDur, useLabel, useTarget } from './lib'
import { fillMerge, placeholders } from './merge'
import { IMPACTS, LINK_KINDS, TICKET_STATUSES, TICKET_TYPES, URGENCIES } from '@/lib/data/tickets-shared'
import type { Macro, TicketConfig, TicketDetail } from '@/lib/data/tickets'

export type DetailProps = {
  ticket: TicketDetail
  config: TicketConfig
  macros: Macro[]
  me: { id: string; name: string }
  superAdmins: { id: string; name: string }[]
  products: Record<string, string>
  problems: { id: string; ref: string; subject: string }[]
  now: string
  /** may change the ticket's fields (rec_save: its owner, or tickets:edit_others) */
  canEdit: boolean
  /** may reply or note (ticket_message: its assignee or owner, or tickets:edit_others) */
  canWrite: boolean
  /** may run a product command and write the company's audit (global:see) */
  canAct: boolean
}

const eyebrow = 'text-11 font-bold uppercase tracking-eyebrow text-muted'
const sideCard = 'flex flex-col rounded-18 border border-line bg-surface px-4 py-[14px]'
const ctrlLabel = 'flex h-8 items-center gap-[6px] rounded-9 border border-line pl-[10px] pr-1 text-12 text-muted'
const ctrlSelect = 'border-0 bg-transparent text-12.5 font-bold text-ink'
const smallBtn = 'h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-11.5 font-semibold disabled:cursor-default disabled:opacity-60'
const mono = 'font-[ui-monospace,Menlo,monospace]'

/** A refusal as a message: the queue guard (forbidden, detail «queue») has its own words. */
function useRefusal() {
  const t = useTranslations('tickets.detail')
  const tc = useTranslations('common')
  return (r: { code: string; detail?: string | null }) => (r.code === 'forbidden' && r.detail === 'queue' ? t('queueForbidden') : tc(`errors.${r.code}`))
}

/** The open ticket: header with controls, impact × urgency, SLA bars, the thread and composer, and the side column. */
export function TicketDetailPanel(p: DetailProps) {
  const { ticket: tk, config, me } = p
  const t = useTranslations('tickets')
  const format = useFormatter()
  const flash = useToast()
  const dur = useDur()
  const target = useTarget()
  const cat = useLabel('categories')
  const queueName = useLabel('queues')
  const now = new Date(p.now)
  const version = useRef(tk.version)
  if (tk.version > version.current) version.current = tk.version
  const [vals, setVals] = useState({ type: tk.type, status: tk.status, queue_key: tk.queue_key, assignee_id: tk.assignee_id ?? '', impact: tk.impact, urgency: tk.urgency })

  const refusal = useRefusal()

  async function save(values: Parameters<typeof saveTicket>[0]['values'], ok?: string) {
    const r = await saveTicket({ id: tk.id, version: version.current, values })
    if (!r.ok) {
      setVals({ type: tk.type, status: tk.status, queue_key: tk.queue_key, assignee_id: tk.assignee_id ?? '', impact: tk.impact, urgency: tk.urgency })
      flash(refusal(r))
      return false
    }
    version.current = r.version
    if (ok) flash(ok)
    return true
  }
  const set = <K extends keyof typeof vals>(k: K, v: (typeof vals)[K]) => {
    setVals((x) => ({ ...x, [k]: v }))
    void save({ [k]: k === 'assignee_id' ? (v || null) : v } as never)
  }

  // the escalation goes to a super-admin other than the one who already holds it
  const escalateTo = p.superAdmins.find((a) => a.id !== vals.assignee_id && a.id !== me.id) ?? p.superAdmins.find((a) => a.id !== vals.assignee_id)
  const prio = priorityOf(vals.impact, vals.urgency)
  const policy = config.sla.find((s) => s.priority === tk.priority)
  const open = tk.status !== 'resolved' && tk.status !== 'closed'

  // first response
  const frT = policy?.first_response_min ?? 0
  const frLeft = tk.first_response_left_min
  const late = !!(tk.first_response_at && tk.first_response_due_at && tk.first_response_at > tk.first_response_due_at)
  const frBox = tk.responded
    ? { v: t(late ? 'detail.breached' : 'detail.met', { dur: dur(tk.first_response_used_min ?? 0) }), w: 100, c: late ? 'bg-alert' : 'bg-ok', tc: 'text-ink' }
    : frLeft === null
      ? { v: '—', w: 0, c: 'bg-warn', tc: 'text-ink' }
      : frLeft < 0
        ? { v: t('detail.overdueBy', { dur: dur(frLeft, true) }), w: 100, c: 'bg-alert', tc: 'text-danger' }
        : { v: t('detail.businessLeft', { dur: dur(frLeft, true) }), w: frT ? Math.min(100, Math.max(0, ((frT - frLeft) / frT) * 100)) : 0, c: 'bg-warn', tc: 'text-ink' }
  // resolution
  const resT = policy?.resolution_min ?? 0
  const resLeft = tk.resolution_left_min
  const resBox = resLeft === null
    ? { v: open ? '—' : t('detail.resolved'), w: open ? 0 : 100, c: 'bg-teal-mid', tc: 'text-ink' }
    : resLeft < 0
      ? { v: t('detail.overdueBy', { dur: dur(resLeft, true) }), w: 100, c: 'bg-alert', tc: 'text-danger' }
      : {
          v: resLeft >= DAY_MIN ? t('detail.daysLeft', { n: Math.floor(resLeft / DAY_MIN) }) : t('detail.businessLeft', { dur: dur(resLeft, true) }),
          w: resT ? Math.min(100, Math.max(0, ((resT - resLeft) / resT) * 100)) : 0, c: 'bg-teal-mid', tc: 'text-ink',
        }
  const slas = [
    { n: t('detail.firstResponse', { target: policy ? target(frT) : '—' }), ...frBox },
    { n: t('detail.resolution', { target: policy ? target(resT, true) : '—' }), ...resBox },
  ]

  const editable = p.canEdit
  const allowedQueues = config.queues.filter((q) => q.allowed || q.key === tk.queue_key)
  const productName = tk.product ? p.products[tk.product] ?? tk.product : null

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="flex flex-wrap items-center gap-2 text-12 text-muted">
          <b className="text-ink">{tk.ref}</b><span>·</span><span>{t(`channels.${tk.channel}`)}</span><span>·</span><span>{cat(tk.category_key)}</span>
          {productName ? <><span>·</span><span>{productName}</span></> : null}
          <span>·</span><span>{t('detail.opened', { when: format.relativeTime(new Date(tk.created_at), now) })}</span>
        </div>
        <h2 className="m-0 font-serif text-22 font-semibold leading-[1.2]">{tk.subject}</h2>
        <div className="flex flex-wrap items-center gap-2">
          <label className={ctrlLabel}>
            {t('detail.type')}
            <select disabled={!editable} value={vals.type} onChange={(e) => set('type', e.target.value as typeof vals.type)} className={ctrlSelect}>
              {TICKET_TYPES.map((x) => <option key={x} value={x}>{t(`types.${x}`)}</option>)}
            </select>
          </label>
          <label className={ctrlLabel}>
            {t('detail.status')}
            <select disabled={!editable} value={vals.status} onChange={(e) => set('status', e.target.value as typeof vals.status)} className={ctrlSelect}>
              {TICKET_STATUSES.map((x) => <option key={x} value={x}>{t(`statuses.${x}`)}</option>)}
            </select>
          </label>
          <label className={ctrlLabel}>
            {t('detail.queue')}
            <select disabled={!editable} value={vals.queue_key} onChange={(e) => set('queue_key', e.target.value)} className={ctrlSelect}>
              {allowedQueues.map((q) => <option key={q.key} value={q.key}>{queueName(q.key, q.name)}</option>)}
            </select>
          </label>
          <label className={ctrlLabel}>
            {t('detail.assignee')}
            <select disabled={!editable} value={vals.assignee_id} onChange={(e) => set('assignee_id', e.target.value)} className={ctrlSelect}>
              <option value="">{t('detail.unassigned')}</option>
              {config.assignees.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              {tk.assignee && !config.assignees.some((a) => a.id === tk.assignee!.id) ? <option value={tk.assignee.id}>{tk.assignee.name}</option> : null}
            </select>
          </label>
          <button
            type="button"
            disabled={!editable || !escalateTo}
            title={escalateTo ? undefined : t('detail.noEscalation')}
            onClick={() => {
              if (!escalateTo) return
              setVals((x) => ({ ...x, assignee_id: escalateTo.id }))
              void save({ assignee_id: escalateTo.id }, t('detail.escalated', { name: escalateTo.name }))
            }}
            className="h-8 cursor-pointer rounded-9 border border-coral bg-transparent px-3 text-12 font-semibold text-rust disabled:cursor-default disabled:opacity-60"
          >
            {t('detail.escalate')}
          </button>
        </div>
        <div className="flex flex-wrap items-stretch gap-[10px]">
          <div className="flex min-w-0 max-w-full flex-wrap items-center gap-[10px] rounded-14 border border-line bg-canvas px-3 py-[10px]">
            <label className="flex flex-col gap-1 text-11 text-muted">
              {t('detail.impact')}
              <select disabled={!editable} value={vals.impact} onChange={(e) => set('impact', e.target.value as typeof vals.impact)} className="h-7 rounded-8 border border-line bg-surface text-12 font-semibold text-ink">
                {IMPACTS.map((x) => <option key={x} value={x}>{t(`impacts.${x}`)}</option>)}
              </select>
            </label>
            <span className="text-16 text-faint">×</span>
            <label className="flex flex-col gap-1 text-11 text-muted">
              {t('detail.urgency')}
              <select disabled={!editable} value={vals.urgency} onChange={(e) => set('urgency', e.target.value as typeof vals.urgency)} className="h-7 rounded-8 border border-line bg-surface text-12 font-semibold text-ink">
                {URGENCIES.map((x) => <option key={x} value={x}>{t(`urgencies.${x}`)}</option>)}
              </select>
            </label>
            <span className="text-16 text-faint">=</span>
            <span className={`rounded-999 px-3 py-[6px] text-12 font-bold ${PTONE[prio].bg} ${PTONE[prio].ink}`}>{t(`priorities.${prio}`)}</span>
          </div>
          {slas.map((s) => (
            <div key={s.n} className="flex min-w-[150px] flex-col justify-center gap-1 rounded-14 border border-line px-3 py-[10px]">
              <span className="text-10.5 font-bold uppercase tracking-label text-muted">{s.n}</span>
              <span className="h-[6px] overflow-hidden rounded-999 bg-tile"><span className={`block h-full ${s.c}`} style={{ width: `${s.w}%` }} /></span>
              <b className={`text-12.5 ${s.tc}`}>{s.v}</b>
            </div>
          ))}
        </div>
      </div>

      <div className="grid items-start gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        <div className="col-[1/-1] flex min-w-0 flex-col gap-[10px]">
          <Thread ticket={tk} now={now} />
          <Composer {...p} />
        </div>
        <Side {...p} at={now} />
      </div>
    </div>
  )
}

function Thread({ ticket: tk, now }: { ticket: TicketDetail; now: Date }) {
  const t = useTranslations('tickets')
  const format = useFormatter()
  const when = (iso: string) => {
    const d = new Date(iso)
    const min = Math.floor((now.getTime() - d.getTime()) / 60000)
    if (min < 1) return t('thread.justNow')
    if (min < 60) return t('thread.minutesAgo', { m: min })
    if (min < 60 * 24 * 7) return t('thread.hoursAgo', { h: Math.floor(min / 60) })
    return format.dateTime(d, { day: 'numeric', month: 'short', year: 'numeric' })
  }
  // an executed action is stored as «<action>:<ok|failed>» (ticket_action_note); its sentence comes from messages
  const actionLine = (body: string, author: string | null) => {
    const a = /^([a-z_]+)\.([a-z_]+):(ok|failed)$/.exec(body)
    if (!a) return body
    const key = `thread.actions.${a[1]}_${a[2]}`
    const params = { action: t.has(key) ? t(key) : `${a[1]}.${a[2]}`, name: author ?? '—', ref: tk.ref, org: tk.organization?.name ?? '' }
    const ok = a[3] === 'ok'
    return tk.organization ? t(ok ? 'thread.actionOk' : 'thread.actionFailed', params) : t(ok ? 'thread.actionOkNoOrg' : 'thread.actionFailedNoOrg', params)
  }
  return (
    <>
      {tk.messages.map((m) => {
        const cust = m.kind === 'customer'
        const sys = m.kind === 'system' || m.kind === 'admin_action'
        const note = m.kind === 'note'
        const who = sys ? t('thread.system') : m.author ?? t('thread.requester')
        return (
          <div key={m.id} className="flex items-start gap-[10px]">
            <span className={`flex h-8 w-8 flex-none items-center justify-center rounded-10 text-11 font-bold ${cust ? 'bg-tile text-ink' : sys ? 'bg-teal-soft text-ink' : 'bg-ink text-highlight'}`}>
              {sys ? '⚙' : initialsOf(m.author)}
            </span>
            <div className={`min-w-0 flex-1 rounded-16 border px-[14px] py-3 ${note ? 'border-amber-bg bg-highlight' : sys ? 'border-line bg-canvas' : 'border-line bg-surface'}`}>
              <div className="mb-[6px] flex justify-between gap-[10px] text-12 text-muted">
                <span><b className="text-ink">{who}</b> · {cust ? t('thread.customer', { channel: t(`channels.${tk.channel}`).toLowerCase() }) : t(`thread.${m.kind}`)}</span>
                <span className="whitespace-nowrap">{when(m.created_at)}</span>
              </div>
              <div className="whitespace-pre-wrap text-13 leading-[1.6]">{m.kind === 'admin_action' ? actionLine(m.body, m.author) : m.body}</div>
              {m.kind === 'reply' && m.delivery_status && m.delivery_status !== 'sent' ? (
                <div className={`mt-2 text-11.5 ${m.delivery_status === 'failed' ? 'text-danger' : 'text-faint'}`}>
                  {t(m.delivery_status === 'not_configured' ? 'thread.notConfigured' : m.delivery_status === 'queued' ? 'thread.queued' : 'thread.failed')}
                </div>
              ) : null}
            </div>
          </div>
        )
      })}
    </>
  )
}

function Composer({ ticket: tk, macros, me, config, canWrite }: DetailProps) {
  const t = useTranslations('tickets.composer')
  const flash = useToast()
  const refusal = useRefusal()
  const [mode, setMode] = useState<'reply' | 'note'>('reply')
  const [draft, setDraft] = useState('')
  const [macroId, setMacroId] = useState<string | null>(null)
  const [mentions, setMentions] = useState<{ id: string; name: string }[]>([])
  const [after, setAfter] = useState<'waiting_customer' | 'keep' | 'resolved'>('waiting_customer')
  const [picker, setPicker] = useState(false)
  const [busy, setBusy] = useState(false)
  const note = mode === 'note'
  const first = tk.person?.name.split(' ')[0] ?? null
  const left = useMemo(() => placeholders(draft), [draft])
  const blocked = !note && left.length > 0

  function applyMacro(id: string) {
    const m = macros.find((x) => x.id === id)
    const v = m && (m.versions.find((x) => x.locale === 'nb') ?? m.versions[0])
    if (!m || !v) return
    setMacroId(m.id)
    setDraft(fillMerge(v.body, { fornavn: first, organisasjon: tk.organization?.name ?? null, orgnr: orgNumber(tk.organization?.org_number), agent: me.name }))
  }

  async function send() {
    if (busy || !draft.trim() || blocked) return
    setBusy(true)
    // a mention counts only while its name is still in the note
    const ids = note ? mentions.filter((m) => draft.includes(`@${m.name}`)).map((m) => m.id) : []
    const r = await sendMessage({ id: tk.id, kind: mode, body: draft, after: after === 'keep' ? null : after, macroId, mentions: ids })
    setBusy(false)
    if (!r.ok) { flash(refusal(r)); return }
    setDraft('')
    setMacroId(null)
    setMentions([])
    flash(note ? t(ids.length ? 'savedNoteMention' : 'savedNote') : t('sentReply'))
  }

  return (
    <div className={`overflow-hidden rounded-18 border bg-surface ${note ? 'border-amber-bg' : 'border-line'}`}>
      <div className={`flex gap-[2px] border-b border-line p-[6px] ${note ? 'bg-highlight' : 'bg-canvas'}`}>
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
              {t(k)}
            </button>
          )
        })}
        <span className="flex-1" />
        <select
          value=""
          aria-label={t('macro')}
          onChange={(e) => applyMacro(e.target.value)}
          className="h-[30px] min-w-0 max-w-[180px] rounded-9 border border-line bg-surface text-12"
        >
          <option value="">{t('macro')}</option>
          {macros.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
        </select>
      </div>
      <textarea
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        aria-label={note ? t('note') : t('reply')}
        placeholder={note ? t('phNote') : first ? t('phReply', { name: first }) : t('phReplyNoName')}
        className="block min-h-[110px] w-full resize-y border-0 bg-transparent px-[14px] py-3 text-13 leading-[1.55] outline-none"
      />
      <div className="flex flex-wrap items-center gap-2 border-t border-line px-[10px] py-2">
        {blocked ? <div role="alert" className="basis-full text-11.5 font-semibold text-danger">{t('placeholders', { fields: left.join(', ') })}</div> : null}
        <button type="button" disabled title={t('attachOff')} className="h-[30px] cursor-default rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold opacity-60">{t('attach')}</button>
        <span className="relative">
          <button
            type="button"
            aria-expanded={picker}
            onClick={() => setPicker(!picker)}
            className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold"
          >
            {t('mention')}
          </button>
          {picker ? (
            <span role="listbox" aria-label={t('mentionPick')} className="absolute bottom-[36px] left-0 z-20 flex max-h-[240px] w-[220px] flex-col overflow-auto rounded-14 border border-line bg-surface p-1 shadow-pop">
              {config.assignees.filter((a) => a.id !== me.id && a.name).map((a) => (
                <button
                  key={a.id}
                  type="button"
                  role="option"
                  aria-selected={false}
                  onClick={() => {
                    setMentions((x) => (x.some((y) => y.id === a.id) ? x : [...x, { id: a.id, name: a.name! }]))
                    setDraft((d) => `${d}${d && !d.endsWith(' ') && !d.endsWith('\n') ? ' ' : ''}@${a.name} `)
                    setMode('note')
                    setPicker(false)
                  }}
                  className="cursor-pointer rounded-9 border-0 bg-transparent px-[10px] py-[7px] text-left text-12.5 hover:bg-canvas"
                >
                  {a.name}
                </button>
              ))}
            </span>
          ) : null}
        </span>
        <span className="text-11.5 text-faint">{t('never')}</span>
        <span className="flex-1" />
        <select value={after} disabled={note} aria-label={t('afterLabel')} onChange={(e) => setAfter(e.target.value as typeof after)} className="h-8 rounded-9 border border-line bg-surface text-12">
          {(['waiting_customer', 'keep', 'resolved'] as const).map((k) => <option key={k} value={k}>{t(`after.${k}`)}</option>)}
        </select>
        <button
          type="button"
          onClick={() => void send()}
          disabled={busy || blocked || !canWrite}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {note ? t('saveNote') : t('sendReply')}
        </button>
      </div>
    </div>
  )
}

function Side({ ticket: tk, problems, canEdit, canAct, at: now }: DetailProps & { at: Date }) {
  const t = useTranslations('tickets')
  const tc = useTranslations('common')
  const flash = useToast()
  const refusal = useRefusal()
  const [problemPick, setProblemPick] = useState(false)
  const [linkForm, setLinkForm] = useState(false)
  const [kind, setKind] = useState<(typeof LINK_KINDS)[number]>('survey')
  const [ref, setRef] = useState('')
  const [lbl, setLbl] = useState('')
  const [busy, setBusy] = useState(false)

  const org = tk.organization
  const sub = tk.subscription
  const st = sub?.status ?? null
  const days = (iso: string) => Math.ceil((new Date(iso).getTime() - now.getTime()) / 86_400_000)
  const stage = st === 'trial' && sub?.trial_ends_at ? t('side.trialLeft', { n: Math.max(0, days(sub.trial_ends_at)) }) : st === 'active' ? t('side.customer') : null
  const ctx = (k: string) => {
    const v = tk.context[k]
    return typeof v === 'string' && v ? v : '—'
  }

  const linkRows: { k: string; v: string; refs: { kind: (typeof LINK_KINDS)[number]; ref: string }[] }[] = [
    { k: t('side.linkKinds.problem'), v: tk.problem_ref ?? '—', refs: [] },
    ...(['survey', 'invoice', 'deal', 'lead', 'article'] as const)
      .filter((k) => ['survey', 'invoice', 'deal'].includes(k) || tk.links.some((l) => l.kind === k))
      .map((k) => {
        const ls = tk.links.filter((l) => l.kind === k)
        return { k: t(`side.linkKinds.${k}`), v: ls.length ? ls.map((l) => l.label || l.ref).join(', ') : '—', refs: ls.map((l) => ({ kind: k, ref: l.ref })) }
      }),
  ]

  async function setProblem(id: string) {
    setProblemPick(false)
    const r = await saveTicket({ id: tk.id, version: tk.version, values: { problem_id: id || null } })
    if (!r.ok) { flash(refusal(r)); return }
    flash(id ? t('side.linked', { ref: problems.find((x) => x.id === id)?.ref ?? '' }) : t('side.unlinked'))
  }
  async function link(on: boolean, k: (typeof LINK_KINDS)[number], r: string, label: string | null) {
    setBusy(true)
    const res = await linkTicket({ id: tk.id, kind: k, ref: r, label, on })
    setBusy(false)
    if (!res.ok) { flash(refusal(res)); return }
    if (on) { setRef(''); setLbl(''); setLinkForm(false) }
    flash(t(on ? 'side.linkAdded' : 'side.linkRemoved'))
  }
  async function extend() {
    setBusy(true)
    const r = await extendTrial({ ticketId: tk.id })
    setBusy(false)
    if (!r.ok) { flash(refusal(r)); return }
    flash(r.error ? t('side.sr.extendFailed', { error: r.error }) : t('side.sr.extended'))
  }

  const extendOff = !canAct ? tc('errors.forbidden') : tk.product && tk.product !== 'orgpuls' ? t('side.sr.notOrgpuls') : st !== 'trial' ? t('side.sr.notTrial') : null
  const srActions = [
    { k: 'extend', n: t('side.sr.extend'), s: extendOff ?? t('side.sr.extendSub'), off: !!extendOff || !org, run: extend },
    { k: 'plan', n: t('side.sr.plan'), s: t('side.sr.notYet'), off: true },
    { k: 'export', n: t('side.sr.export'), s: t('side.sr.notYet'), off: true },
    { k: 'ehf', n: t('side.sr.ehf'), s: t('side.sr.notYet'), off: true },
  ]
  const privacyDays = tk.privacy ? days(tk.privacy.due_at) : null

  return (
    <div className="flex flex-col gap-[10px]">
      <div className={`${sideCard} gap-2`}>
        <div className={eyebrow}>{t('side.organization')}</div>
        {org ? (
          <Link href={`/customers?org=${org.id}` as never} className="flex flex-col gap-[2px] text-left text-ink hover:text-ink hover:no-underline">
            <b className="text-14">{org.name} →</b>
            <span className="text-12 text-muted">{[orgNumber(org.org_number), org.employees !== null ? t('side.employees', { n: org.employees }) : null].filter(Boolean).join(' · ')}</span>
          </Link>
        ) : <span className="text-12 text-muted">{t('side.noOrg')}</span>}
        {org ? (
          <div className="flex flex-wrap gap-[6px]">
            {st ? <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${STATUS_TONE[st] ?? STATUS_TONE.cancelled}`}>{t.has(`side.subStatus.${st}`) ? t(`side.subStatus.${st}`) : st}</span> : null}
            <span className="rounded-999 bg-tile px-[9px] py-[2px] text-11 font-bold">{t('side.health', { v: '—' })}</span>
            {stage ? <span className="rounded-999 bg-tile px-[9px] py-[2px] text-11 font-bold">{stage}</span> : null}
          </div>
        ) : null}
        {tk.person ? (
          <div className="flex flex-col gap-[2px] border-t border-line pt-2">
            <b className="text-13">{tk.person.name}</b>
            <span className="text-12 text-muted">{[tk.person.title, tk.person.email].filter(Boolean).join(' · ')}</span>
          </div>
        ) : null}
      </div>

      <div className={`${sideCard} gap-[7px]`}>
        <div className={eyebrow}>{t('side.captured')}</div>
        {[
          { k: t('side.ctx.role'), v: ctx('role') },
          { k: t('side.ctx.page'), v: ctx('page'), mono: true },
          { k: t('side.ctx.browser'), v: ctx('browser') },
          { k: t('side.ctx.appVersion'), v: ctx('app_version') },
          { k: t('side.ctx.channel'), v: t(`channels.${tk.channel}`) },
        ].map((c) => (
          <div key={c.k} className="flex justify-between gap-[10px] text-12">
            <span className="text-muted">{c.k}</span>
            <span className={`text-right font-semibold ${c.mono && c.v !== '—' ? mono : ''}`}>{c.v}</span>
          </div>
        ))}
      </div>

      <div className={`${sideCard} gap-2`}>
        <div className={eyebrow}>{t('side.links')}</div>
        {linkRows.map((l) => (
          <div key={l.k} className="flex justify-between gap-2 border-b border-line py-[6px] text-12.5">
            <span className="text-muted">{l.k}</span>
            <span className="flex items-center gap-[6px]">
              <b className="text-right">{l.v}</b>
              {canEdit ? l.refs.map((r) => (
                <button key={r.ref} type="button" disabled={busy} aria-label={t('side.linkRemove', { ref: r.ref })} onClick={() => void link(false, r.kind, r.ref, null)} className="cursor-pointer border-0 bg-transparent p-0 text-12 text-faint">×</button>
              )) : null}
            </span>
          </div>
        ))}
        <div className="flex flex-wrap gap-[6px]">
          {tk.type !== 'problem' ? (
            <button type="button" disabled={!canEdit} aria-expanded={problemPick} onClick={() => setProblemPick(!problemPick)} className={smallBtn}>{t('side.linkProblem')}</button>
          ) : null}
          <button type="button" disabled={!canEdit} aria-expanded={linkForm} onClick={() => setLinkForm(!linkForm)} className={smallBtn}>{t('side.linkOther')}</button>
        </div>
        {problemPick ? (
          <select autoFocus aria-label={t('side.linkProblem')} value={tk.problem_id ?? ''} onChange={(e) => void setProblem(e.target.value)} className="h-[30px] min-w-0 rounded-8 border border-line bg-canvas text-12">
            <option value="">{t('side.noProblem')}</option>
            {problems.filter((x) => x.id !== tk.id).map((x) => <option key={x.id} value={x.id}>{x.ref} · {x.subject}</option>)}
          </select>
        ) : null}
        {linkForm ? (
          <form
            onSubmit={(e) => { e.preventDefault(); if (ref.trim()) void link(true, kind, ref, lbl || null) }}
            className="flex flex-wrap gap-[6px]"
          >
            <select aria-label={t('side.linkKind')} value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
              {LINK_KINDS.map((k) => <option key={k} value={k}>{t(`side.linkKinds.${k}`)}</option>)}
            </select>
            <input aria-label={t('side.linkRef')} placeholder={t('side.linkRef')} value={ref} maxLength={100} onChange={(e) => setRef(e.target.value)} className="h-[30px] min-w-0 flex-1 rounded-8 border border-line bg-canvas px-2 text-12" />
            <input aria-label={t('side.linkLabel')} placeholder={t('side.linkLabel')} value={lbl} maxLength={200} onChange={(e) => setLbl(e.target.value)} className="h-[30px] min-w-0 flex-1 rounded-8 border border-line bg-canvas px-2 text-12" />
            <button type="submit" disabled={busy || !ref.trim()} className={smallBtn}>{t('side.linkAdd')}</button>
          </form>
        ) : null}
      </div>

      {tk.type === 'service_request' ? (
        <div className="flex flex-col gap-2 rounded-18 border border-ink bg-highlight px-4 py-[14px]">
          <div className="text-11 font-bold uppercase tracking-eyebrow text-amber-ink">{t('side.sr.title')}</div>
          {srActions.map((a, i) => (
            <button
              key={a.k}
              type="button"
              disabled={a.off || busy}
              onClick={() => void a.run?.()}
              className={`flex h-[34px] cursor-pointer items-center justify-between gap-2 rounded-10 border bg-surface px-3 text-left text-12.5 font-bold disabled:cursor-default ${i === 0 ? 'border-ink' : 'border-line'} ${a.off ? 'opacity-70' : ''}`}
            >
              {a.n}
              <span className="text-right text-11 font-medium text-muted">{a.s}</span>
            </button>
          ))}
          <div className="text-11.5 text-amber-ink">{t('side.sr.footer')}</div>
        </div>
      ) : null}

      {tk.category_key === 'personvern' ? (
        <div className="rounded-18 bg-peach px-4 py-[14px] text-12.5 leading-[1.5] text-rust-ink">
          <b>{t('side.privacyLead')}</b>{' '}
          {privacyDays === null ? t('side.privacyNoClock') : privacyDays >= 0 ? t('side.privacyClock', { n: privacyDays }) : t('side.privacyOverdue', { n: -privacyDays })}{' '}
          {t('side.privacyVisible')}
        </div>
      ) : null}

      {tk.csat_score !== null ? (
        <div className="flex items-center justify-between rounded-18 border border-line bg-surface px-4 py-[14px]">
          <span className="text-12.5 text-muted">{t('side.csat')}</span>
          <b className="font-serif text-20">{t('side.csatValue', { v: tk.csat_score })}</b>
        </div>
      ) : null}
    </div>
  )
}
