'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { CatalogItem, DealBundle, DealsBase, Field, Item } from '@/lib/data/deals'
import type { RpcCode } from '@/lib/rpc'
import {
  archiveDeals, completeActivity, deleteDeals, duplicateDeal, deleteItem, fetchCatalog, saveActivity, saveDeal, saveItem, saveNote,
  setFollow, setParticipant, setStatus,
} from '../actions'
import { canEditDeal, dateOnly, initials, type Rights } from './shared'
import { buildHistory, HIST_FILTERS } from './history'
import { Picker } from './Picker'

const TABS = ['note', 'activity', 'call', 'email', 'files', 'documents', 'invoice'] as const
type Tab = (typeof TABS)[number]
const OFF: Tab[] = ['call', 'email', 'files', 'documents', 'invoice']
const card = 'rounded-18 border border-line bg-surface px-4 py-[14px]'
const eyebrow = 'text-11 font-bold uppercase tracking-eyebrow text-muted'
const LINE_GRID = '[grid-template-columns:minmax(0,1.6fr)_60px_90px_70px_100px_100px]'
const lineTotal = (l: Item) => l.quantity * l.unit_price * (1 - l.discount_pct / 100)

type Props = {
  bundle: DealBundle
  base: DealsBase
  rights: Rights
  nf: NumberFormat
  onClose: () => void
  onChanged: () => void
  onMove: (stage: string) => void
  onLost: () => void
  onNextStep: (subject: string) => void
  onToLead: () => void
}

/** The deal drawer (Deals.dc.html deal): header with stage bar, summary, details, people, products, composer, focus, history. */
export function DealDrawer({ bundle, base, rights, nf, onClose, onChanged, onMove, onLost, onNextStep, onToLead }: Props) {
  const t = useTranslations('deals')
  const td = useTranslations('deals.drawer')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const d = bundle.detail
  const editable = canEditDeal(rights, d)
  const err = (code: RpcCode) => flash(te(code))
  const after = (r: { ok: true } | { ok: false; code: RpcCode }, msg?: string) => {
    if (!r.ok) { err(r.code); return false }
    if (msg) flash(msg)
    onChanged()
    return true
  }
  const save = async (values: Record<string, unknown>, msg?: string) =>
    after(await saveDeal({ id: d.id, values, version: d.version }), msg)

  const fmtDay = (iso: string) => format.dateTime(dateOnly(iso), { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
  const [hist, setHist] = useState<(typeof HIST_FILTERS)[number]>('All')
  const [tab, setTab] = useState<Tab>('note')
  const [draft, setDraft] = useState('')
  const [actType, setActType] = useState(base.activityTypes[0]?.id ?? '')
  const [actWhen, setActWhen] = useState('')
  const [picking, setPicking] = useState<'participant' | 'person' | 'organization' | null>(null)
  const [editField, setEditField] = useState<string | null>(null)
  const [catalog, setCatalog] = useState<CatalogItem[]>([])
  // the dialog takes focus when it opens, so the keyboard continues inside it
  const panel = useRef<HTMLDivElement>(null)
  useEffect(() => { panel.current?.focus() }, [d.id])
  useEffect(() => { if (editable) void fetchCatalog().then((r) => { if (r.ok) setCatalog(r.catalog) }) }, [editable])

  const history = useMemo(() => buildHistory(bundle, base, t, nf, fmtDay), [bundle, base, t, nf]) // eslint-disable-line react-hooks/exhaustive-deps
  // the «why» panel: the active model's criteria for this pipeline, hits from the stored breakdown
  const why = useMemo(() => {
    const hits = bundle.scoreHits ?? []
    const model = base.scoreModels.find((m) => m.pipeline_id === d.pipeline_id) ?? base.scoreModels.find((m) => m.pipeline_id === null)
    const rows = model
      ? model.criteria.map((c) => {
          const hit = hits.find((h) => h.criterion === c.id)
          return { id: c.id, label: c.label, points: hit?.points ?? model.points[c.group] ?? 0, hit: !!hit }
        })
      : hits.map((h) => ({ id: h.criterion, label: h.label, points: h.points, hit: true }))
    return rows.map((r) => ({ ...r, c: r.hit ? (r.points > 0 ? 'text-ok-ink' : 'text-danger') : 'text-faint' }))
  }, [bundle.scoreHits, base.scoreModels, d.pipeline_id])
  const shownHistory = history.filter((h) => hist === 'All' || h.k === hist)
  const stages = d.stages ?? []
  const idx = stages.findIndex((s) => s.id === d.stage_id)
  const prob = stages[idx]?.probability ?? d.probability
  const open = bundle.activities.filter((a) => !a.done)
  const labelBy = base.labels
  const ownerKnown = base.staff.some((s) => s.id === d.owner_id)

  // ---- header actions
  const more = async (a: string) => {
    if (a === 'lead') { onToLead(); return }
    if (a === 'dup') { const r = await duplicateDeal(d.id); after(r, t('flash.duplicated')) }
    if (a === 'archive') { const r = await archiveDeals({ ids: [d.id], archived: true }); if (after(r, t('flash.archived'))) onClose() }
    if (a === 'unarchive') { const r = await archiveDeals({ ids: [d.id], archived: false }); after(r, t('flash.unarchived')) }
    if (a === 'reopen') { const r = await setStatus({ id: d.id, status: 'open', version: d.version }); after(r, t('flash.reopened')) }
    if (a === 'delete') { const r = await deleteDeals({ ids: [d.id] }); if (after(r, t('flash.deleted'))) onClose() }
  }
  const won = async () => after(await setStatus({ id: d.id, status: 'won', version: d.version }), t('flash.won', { title: d.title }))
  const follow = async () => after(await setFollow({ id: d.id, on: !d.following }))

  // ---- products
  const addLine = async (itemId: string) => {
    if (!itemId) return
    if (d.value_source === 'manual' && d.items.length === 0) {
      const s = await saveDeal({ id: d.id, values: { value_source: 'items' }, version: d.version })
      if (!s.ok) return err(s.code)
    }
    after(await saveItem({ deal: d.id, id: null, values: { item_id: itemId } }), t('flash.lineChanged'))
  }
  const setLine = async (l: Item, k: 'quantity' | 'discount_pct', raw: string) => {
    const n = Number(raw.replace(',', '.'))
    if (!Number.isFinite(n) || n === l[k]) return
    if (k === 'quantity' && n <= 0) { after(await deleteItem({ deal: d.id, id: l.id }), t('flash.lineChanged')); return }
    after(await saveItem({ deal: d.id, id: l.id, values: { [k]: Math.min(k === 'discount_pct' ? 100 : 1e7, Math.max(0, n)) } }), t('flash.lineChanged'))
  }
  const fromLines = async () => {
    const s = await saveDeal({ id: d.id, values: { value_source: 'items' }, version: d.version })
    if (!s.ok) return err(s.code)
    // a line save recalculates the value from the lines (app.deal_recalc)
    const first = d.items[0]
    if (first) after(await saveItem({ deal: d.id, id: first.id, values: {} }), t('flash.lineChanged'))
    else onChanged()
  }
  const billing = (l: Pick<Item, 'billing' | 'billing_frequency' | 'cycles'>) =>
    l.billing === 'recurring'
      ? `${t(`billing.${l.billing_frequency ?? 'monthly'}`)} · ${l.cycles ? td('products.cycles', { count: l.cycles }) : td('products.untilCancelled')}`
      : l.billing === 'installments' ? `${t('billing.installments')}${l.cycles ? ` · ${td('products.cycles', { count: l.cycles })}` : ''}` : t('billing.one_off')

  // ---- composer
  const off = OFF.includes(tab)
  // a note needs only sight of the deal (note_save); an activity is a new record (deals:add)
  const canWrite = tab === 'note' ? !rights.readOnly : tab === 'activity' ? rights.add : false
  const submit = async () => {
    if (off || !draft.trim()) return
    if (tab === 'note') {
      if (after(await saveNote({ deal: d.id, body: draft }), td('composer.saved.note'))) setDraft('')
    } else if (tab === 'activity') {
      const starts = actWhen ? new Date(actWhen).toISOString() : null
      if (after(await saveActivity({ deal: d.id, type_id: actType, subject: draft, starts_at: starts }), td('composer.saved.activity'))) { setDraft(''); setActWhen('') }
    }
  }
  const done = async (id: string, subject: string) => {
    const r = await completeActivity(id)
    if (!r.ok) return err(r.code)
    onChanged()
    if (r.prompt) onNextStep(subject)
    else flash(td('focus.done'))
  }
  const when = (iso: string | null) => {
    if (!iso) return null
    const dt = new Date(iso)
    const day = (x: Date) => Math.floor((x.getTime() - x.getTimezoneOffset() * 60000) / 86_400_000)
    const diff = day(dt) - day(new Date())
    if (diff === 0) return td('focus.today', { time: format.dateTime(dt, { hour: '2-digit', minute: '2-digit' }) })
    return diff > 0 ? td('focus.inDays', { count: diff }) : td('focus.overdue', { count: -diff })
  }

  // ---- details
  const fieldValue = (f: Field): string => {
    const v = d.custom[f.key]
    if (v === null || v === undefined || v === '') return '—'
    if (f.type === 'single_option' || f.type === 'multiple_options') {
      const opts = f.options.map((o) => (typeof o === 'string' ? { key: o, label: o } : { key: o.key, label: o.label ?? o.key }))
      const keys = Array.isArray(v) ? v.map(String) : [String(v)]
      return keys.map((k) => opts.find((o) => o.key === k)?.label ?? k).join(', ')
    }
    if (f.type === 'date' && typeof v === 'string') return fmtDay(v)
    if (f.type === 'user') return base.staff.find((s) => s.id === v)?.name ?? '—'
    if (f.type === 'monetary' && typeof v === 'object' && v && 'amount' in v) return money(Number((v as { amount: unknown }).amount), nf, String((v as { currency?: unknown }).currency ?? 'NOK'))
    if (typeof v === 'string' || typeof v === 'number') return String(v)
    return '—'
  }
  const fieldTag = (f: Field) =>
    f.type === 'formula' ? td('details.formula')
      : f.quality === 'required' ? (f.from_stage_id ? td('details.requiredFrom', { stage: base.pipelines.flatMap((p) => p.stages).find((s) => s.id === f.from_stage_id)?.name ?? '' }) : td('details.required'))
        : f.quality === 'important' ? td('details.important') : ''
  const editableField = (f: Field) => editable && !f.readonly && ['text', 'large_text', 'numerical', 'date', 'single_option', 'phone'].includes(f.type)
  const saveField = async (f: Field, raw: string) => {
    setEditField(null)
    const v = raw.trim()
    const val = v === '' ? null : f.type === 'numerical' ? Number(v.replace(',', '.')) : v
    if (typeof val === 'number' && !Number.isFinite(val)) return
    if ((d.custom[f.key] ?? null) === val) return
    await save({ custom: { [f.key]: val } }, td('details.saved'))
  }

  // ---- people
  const pick = async (id: string) => {
    const which = picking
    setPicking(null)
    if (which === 'participant') after(await setParticipant({ deal: d.id, person: id, on: true }), td('people.added'))
    if (which === 'person') await save({ person_id: id })
    if (which === 'organization') await save({ organization_id: id })
  }

  const statusColor = d.status === 'won' ? 'text-link' : d.status === 'lost' ? 'text-danger' : 'text-ink'
  const bigInput = 'h-7 rounded-7 border border-line bg-canvas px-[6px] text-12.5'

  return (
    <div onClick={onClose} className="fixed inset-0 z-[80] flex justify-end bg-[rgba(25,21,16,.42)]">
      <div ref={panel} tabIndex={-1} role="dialog" aria-modal="true" aria-labelledby="deal-title" onClick={(e) => e.stopPropagation()} className="flex h-full outline-none w-[min(980px,100%)] flex-col overflow-auto bg-canvas shadow-modal">
        <div className="sticky top-0 z-[5] flex flex-col gap-3 border-b border-line bg-surface px-[22px] py-4">
          <div className="flex flex-wrap items-start gap-[10px]">
            <div className="min-w-0 flex-[1_1_320px]">
              <div className="text-12 text-muted">
                {[td('idLabel', { id: d.seq }), d.pipeline, d.source ? td('source', { source: d.source }) : null].filter(Boolean).join(' · ')}
              </div>
              <div id="deal-title" className="mt-[3px] font-serif text-23 font-semibold leading-[1.2]">{d.title}</div>
              <div className="mt-[3px] text-13 text-ink-2">
                <b>{money(d.value, nf)}</b>
                {[d.organization, d.person].filter(Boolean).map((x) => ` · ${x}`).join('')}
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-[6px]">
              <select
                aria-label={td('owner')}
                value={d.owner_id ?? ''}
                disabled={!editable}
                onChange={(e) => void save({ owner_id: e.target.value }, td('ownerChanged'))}
                className="h-[34px] rounded-10 border border-line bg-surface text-12.5 font-semibold text-ink"
              >
                {!ownerKnown ? <option value={d.owner_id ?? ''}>{d.owner?.name ?? '—'}</option> : null}
                {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
              <button
                type="button"
                aria-pressed={d.following}
                onClick={() => void follow()}
                className={`h-[34px] cursor-pointer rounded-10 border px-[11px] text-12.5 font-semibold ${d.following ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}
              >
                {d.following ? td('following') : td('follow')} · {td('followers', { count: d.followers.length })}
              </button>
              {editable ? (
                <>
                  <button type="button" onClick={() => void won()} className="h-[34px] cursor-pointer rounded-10 border border-link bg-ok-bg px-[14px] text-12.5 font-bold text-ok-ink">{td('won')}</button>
                  <button type="button" onClick={onLost} className="h-[34px] cursor-pointer rounded-10 border border-coral bg-peach px-[14px] text-12.5 font-bold text-rust-ink">{td('lost')}</button>
                  <select aria-label={td('more.label')} value="" onChange={(e) => void more(e.target.value)} className="h-[34px] rounded-10 border border-line bg-surface text-12.5 text-ink">
                    <option value="">{td('more.label')}</option>
                    {rights.add ? <option value="dup">{td('more.dup')}</option> : null}
                    {rights.add && !d.archived_at ? <option value="lead">{td('more.lead')}</option> : null}
                    {d.status !== 'open' ? <option value="reopen">{td('more.reopen')}</option> : null}
                    {d.archived_at ? <option value="unarchive">{td('more.unarchive')}</option> : <option value="archive">{td('more.archive')}</option>}
                    {rights.del ? <option value="delete">{td('more.delete')}</option> : null}
                  </select>
                </>
              ) : null}
              <button type="button" aria-label={t('close')} onClick={onClose} className="h-8 w-8 cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
            </div>
          </div>
          <div className="flex gap-[3px]" role="group" aria-label={td('stages')}>
            {stages.map((s, i) => (
              <button
                key={s.id}
                type="button"
                title={`${s.name} · ${s.probability} %`}
                aria-current={i === idx ? 'step' : undefined}
                onClick={() => (editable ? onMove(s.id) : flash(t('flash.viewOnly')))}
                className={`flex min-w-0 flex-1 cursor-pointer flex-col items-start gap-[2px] rounded-9 border-none px-[10px] py-[7px] text-left ${i < idx ? 'bg-ok-bg' : i === idx ? 'bg-primary' : 'bg-tile'}`}
              >
                <span className={`max-w-full overflow-hidden text-ellipsis whitespace-nowrap text-11.5 ${i === idx ? 'font-bold' : 'font-medium'}`}>{s.name}</span>
                <span className="text-10.5 text-muted">
                  {i < idx && s.days !== null ? td('days', { count: s.days }) : i === idx ? td('daysNow', { count: s.days ?? 0 }) : ' '}
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="grid gap-4 px-[22px] py-[18px] [grid-template-columns:minmax(0,1fr)] sm:[grid-template-columns:minmax(280px,330px)_minmax(0,1fr)]">
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-2 rounded-18 bg-ink px-4 py-[14px] text-canvas">
              <div className="flex items-center gap-2">
                {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
                <img src="/brand/assistant.png" alt="" width={24} height={24} className="rounded-7 bg-canvas" />
                <b className="text-12.5">{td('ai.head')}</b>
              </div>
              <div className="text-12.5 leading-[1.5] text-tile">{td('ai.text')}</div>
              <Link href="/api" className="inline-flex h-[30px] items-center self-start rounded-9 border border-primary bg-primary px-3 text-12 font-bold text-ink hover:text-ink hover:no-underline">{td('ai.cta')}</Link>
            </div>

            <div className={`${card} flex flex-col gap-2`}>
              <span className={eyebrow}>{td('summary.title')}</span>
              {[
                { k: td('summary.value'), v: money(d.value, nf) },
                { k: td('summary.probability'), v: td('summary.probabilityValue', { pct: prob }) },
              ].map((r) => (
                <div key={r.k} className="flex justify-between gap-[10px] text-12.5"><span className="text-muted">{r.k}</span><b className="text-right">{r.v}</b></div>
              ))}
              <div className="flex items-center justify-between gap-[10px] text-12.5">
                <span className="text-muted">{td('summary.close')}</span>
                {editable && editField === '__close' ? (
                  <input
                    type="date"
                    autoFocus
                    aria-label={td('summary.close')}
                    defaultValue={d.expected_close_date ?? ''}
                    onBlur={(e) => { setEditField(null); if (e.target.value !== (d.expected_close_date ?? '')) void save({ expected_close_date: e.target.value || null }, td('summary.closeSaved')) }}
                    onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
                    className={bigInput}
                  />
                ) : editable ? (
                  <button type="button" onClick={() => setEditField('__close')} className="cursor-pointer border-none bg-transparent p-0 text-right text-12.5 font-bold">
                    {d.expected_close_date ? fmtDay(d.expected_close_date) : '—'}
                  </button>
                ) : (
                  <b className="text-right">{d.expected_close_date ? fmtDay(d.expected_close_date) : '—'}</b>
                )}
              </div>
              {[
                { k: td('summary.status'), v: t(`status.${d.status}`).toLowerCase(), c: statusColor },
                { k: td('summary.source'), v: d.source ?? '—' },
                { k: td('summary.lostReason'), v: d.lost_reason ?? '—' },
              ].map((r) => (
                <div key={r.k} className="flex justify-between gap-[10px] text-12.5"><span className="text-muted">{r.k}</span><b className={`text-right ${r.c ?? ''}`}>{r.v}</b></div>
              ))}
              <div className="flex flex-wrap gap-1 pt-1">
                {labelBy.map((l) => {
                  const on = d.labels.includes(l.id)
                  return (
                    <button
                      key={l.id}
                      type="button"
                      aria-pressed={on}
                      disabled={!editable}
                      onClick={() => void save({ labels: on ? d.labels.filter((x) => x !== l.id) : [...d.labels, l.id] })}
                      className={`cursor-pointer rounded-999 border px-[9px] py-[3px] text-11 font-bold disabled:cursor-default ${on ? 'border-transparent' : 'border-line-strong bg-transparent text-muted'}`}
                      style={on ? { background: l.bg, color: l.ink } : undefined}
                    >
                      {l.name}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className={`${card} flex flex-col gap-[7px]`}>
              <span className={eyebrow}>{td('score.title', { score: d.score ?? '—' })}</span>
              {why.map((w) => (
                <div key={w.id} className="flex justify-between gap-2 text-12">
                  <span className={w.c}>{w.hit ? '✓' : '○'} {w.label}</span>
                  <b className={w.c}>{w.points > 0 ? `+${w.points}` : `−${Math.abs(w.points)}`}</b>
                </div>
              ))}
              {why.length === 0 ? <div className="text-12 text-muted">{td('score.noModel')}</div> : null}
            </div>

            <div className={`${card} flex flex-col gap-[7px]`}>
              <span className={eyebrow}>{td('details.title')}</span>
              {base.fields.map((f) => (
                <div key={f.id} className="flex items-center justify-between gap-[10px] text-12.5">
                  <span className="text-muted">{f.label} <span className="text-faint">{fieldTag(f)}</span></span>
                  {editField === f.key ? (
                    f.type === 'single_option' ? (
                      <select autoFocus aria-label={f.label} defaultValue={String(d.custom[f.key] ?? '')} onChange={(e) => void saveField(f, e.target.value)} onBlur={() => setEditField(null)} className={`${bigInput} text-ink`}>
                        <option value="">—</option>
                        {f.options.map((o) => { const k = typeof o === 'string' ? o : o.key; return <option key={k} value={k}>{typeof o === 'string' ? o : o.label ?? o.key}</option> })}
                      </select>
                    ) : (
                      <input
                        autoFocus
                        aria-label={f.label}
                        type={f.type === 'date' ? 'date' : 'text'}
                        defaultValue={typeof d.custom[f.key] === 'string' || typeof d.custom[f.key] === 'number' ? String(d.custom[f.key]) : ''}
                        onBlur={(e) => void saveField(f, e.target.value)}
                        onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
                        className={`${bigInput} w-[150px]`}
                      />
                    )
                  ) : editableField(f) ? (
                    <button type="button" onClick={() => setEditField(f.key)} className="cursor-pointer border-none bg-transparent p-0 text-right text-12.5 font-bold">{fieldValue(f)}</button>
                  ) : (
                    <b className="text-right">{fieldValue(f)}</b>
                  )}
                </div>
              ))}
              {d.organization_detail?.employees != null ? (
                <div className="flex justify-between gap-[10px] text-12.5"><span className="text-muted">{td('details.employees')}</span><b className="text-right">{d.organization_detail.employees}</b></div>
              ) : null}
              <div className="flex justify-between gap-[10px] text-12.5">
                <span className="text-muted">{td('details.weighted')} <span className="text-faint">{td('details.weightedTag')}</span></span>
                <b className="text-right">{money((d.value * prob) / 100, nf)}</b>
              </div>
            </div>

            <div className={`${card} flex flex-col gap-[7px]`}>
              <span className={eyebrow}>{td('people.title')}</span>
              {d.person_detail ? (
                <Person ini={initials(d.person_detail.name)} name={d.person_detail.name} line={[d.person_detail.title, d.person_detail.phone, td('people.primary')].filter(Boolean).join(' · ')}
                  action={editable ? { label: td('people.change'), run: () => setPicking('person') } : null} />
              ) : null}
              {d.organization_detail ? (
                <Person ini={d.organization_detail.name.slice(0, 2)} name={d.organization_detail.name} line={[d.organization_detail.org_number, d.organization_detail.city].filter(Boolean).join(' · ')}
                  action={editable ? { label: td('people.change'), run: () => setPicking('organization') } : null} />
              ) : null}
              {d.participants.map((p) => (
                <Person key={p.id} ini={initials(p.name)} name={p.name} line={[p.title, td('people.participant')].filter(Boolean).join(' · ')}
                  action={editable ? { label: td('people.remove'), run: async () => { after(await setParticipant({ deal: d.id, person: p.id, on: false }), td('people.removed')) } } : null} />
              ))}
              {picking ? (
                <Picker entity={picking === 'organization' ? 'organization' : 'person'} onCancel={() => setPicking(null)} onPick={(h) => void pick(h.id)} />
              ) : editable ? (
                <div className="flex flex-wrap gap-[6px]">
                  <button type="button" onClick={() => setPicking('participant')} className="h-7 cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{td('people.addParticipant')}</button>
                  {!d.person_detail ? <button type="button" onClick={() => setPicking('person')} className="h-7 cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{td('people.addPerson')}</button> : null}
                  {!d.organization_detail ? <button type="button" onClick={() => setPicking('organization')} className="h-7 cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{td('people.addOrganization')}</button> : null}
                </div>
              ) : null}
            </div>
          </div>

          <div className="flex min-w-0 flex-col gap-3">
            <div className={card}>
              <div className="mb-[10px] flex items-baseline justify-between gap-2">
                <b className="text-14">{td('products.title')}</b>
                {d.value_source === 'items' ? (
                  <span className="text-12 text-muted">{td('products.fromLines')}</span>
                ) : editable && d.items.length ? (
                  <button type="button" onClick={() => void fromLines()} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{td('products.useLines')}</button>
                ) : (
                  <span className="text-12 text-muted">{td('products.manual')}</span>
                )}
              </div>
              <div className="overflow-x-auto">
                <div className={`grid gap-2 border-b border-line pb-[6px] text-10.5 font-bold uppercase tracking-[.06em] text-muted ${LINE_GRID}`}>
                  <span>{td('products.cols.product')}</span><span>{td('products.cols.qty')}</span><span>{td('products.cols.price')}</span><span>{td('products.cols.disc')}</span><span>{td('products.cols.billing')}</span><span className="text-right">{td('products.cols.total')}</span>
                </div>
                {d.items.map((l) => (
                  <div key={`${l.id}-${d.version}`} className={`grid items-center gap-2 border-b border-line py-[6px] text-12.5 ${LINE_GRID}`}>
                    <b>{l.name}</b>
                    {editable ? (
                      <input aria-label={td('products.cols.qty')} defaultValue={String(l.quantity)} onBlur={(e) => void setLine(l, 'quantity', e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }} className="h-7 w-[52px] rounded-7 border border-line bg-canvas px-[6px]" />
                    ) : <span>{l.quantity}</span>}
                    <span>{money(l.unit_price, nf)}</span>
                    {editable ? (
                      <input aria-label={td('products.cols.disc')} defaultValue={String(l.discount_pct)} onBlur={(e) => void setLine(l, 'discount_pct', e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }} className="h-7 w-[52px] rounded-7 border border-line bg-canvas px-[6px]" />
                    ) : <span>{l.discount_pct}</span>}
                    <span className="text-muted">{billing(l)}</span>
                    <span className="flex items-center justify-end gap-1">
                      <b className="text-right">{money(lineTotal(l), nf)}{l.billing === 'recurring' ? td(`products.per.${l.billing_frequency ?? 'monthly'}`) : ''}</b>
                      {editable ? (
                        <button type="button" aria-label={td('products.removeLine', { name: l.name })} onClick={async () => after(await deleteItem({ deal: d.id, id: l.id }), t('flash.lineChanged'))} className="h-5 w-5 cursor-pointer rounded-999 border-none bg-transparent text-12 text-faint">×</button>
                      ) : null}
                    </span>
                  </div>
                ))}
              </div>
              {d.items.length === 0 ? <div className="py-2 text-12.5 text-muted">{td('products.none')}</div> : null}
              {editable && catalog.length ? (
                <select aria-label={td('products.add')} value="" onChange={(e) => void addLine(e.target.value)} className="mt-2 h-7 rounded-9 border border-dashed border-line-strong bg-transparent px-[6px] text-12 font-semibold text-ink">
                  <option value="">{td('products.add')}</option>
                  {catalog.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              ) : null}
              <div className="mt-[10px] grid grid-cols-4 gap-2">
                {(['mrr', 'arr', 'acv', 'tcv'] as const).map((k) => (
                  <div key={k} className="rounded-12 border border-line bg-canvas px-[10px] py-2">
                    <div className="text-10.5 font-bold tracking-label text-muted">{td(`products.rev.${k}`)}</div>
                    <b className="text-14">{money(d.revenue[k], nf)}</b>
                  </div>
                ))}
              </div>
            </div>

            <div className="overflow-hidden rounded-18 border border-line bg-surface">
              <div role="tablist" aria-label={td('composer.label')} className="flex flex-wrap gap-[2px] border-b border-line bg-canvas p-[6px]">
                {TABS.map((c) => (
                  <button key={c} type="button" role="tab" aria-selected={tab === c} onClick={() => setTab(c)} className={`cursor-pointer rounded-9 border-none px-[11px] py-[6px] text-12.5 ${tab === c ? 'bg-surface font-bold' : 'bg-transparent font-medium'} ${OFF.includes(c) ? 'text-faint' : ''}`}>
                    {td(`composer.tabs.${c}`)}
                  </button>
                ))}
              </div>
              <textarea
                aria-label={td(`composer.ph.${tab}`)}
                value={off ? '' : draft}
                disabled={off || !canWrite}
                onChange={(e) => setDraft(e.target.value)}
                placeholder={off ? td(`composer.off.${tab}`) : td(`composer.ph.${tab}`, { person: d.person ?? '' })}
                className="block min-h-[80px] w-full resize-y border-none bg-transparent px-[14px] py-3 text-13 outline-none disabled:cursor-not-allowed"
              />
              <div className="flex flex-wrap items-center justify-between gap-2 border-t border-line px-[10px] py-2">
                <span className="text-11.5 text-faint">{off ? td('composer.notConnected') : td(`composer.hint.${tab}`)}</span>
                <span className="flex items-center gap-[6px]">
                  {tab === 'activity' && canWrite ? (
                    <>
                      <select aria-label={td('composer.type')} value={actType} onChange={(e) => setActType(e.target.value)} className="h-8 rounded-9 border border-line bg-surface text-12 text-ink">
                        {base.activityTypes.map((a) => <option key={a.id} value={a.id}>{t.has(`activityTypes.${a.key}`) ? t(`activityTypes.${a.key}`) : a.name}</option>)}
                      </select>
                      <input type="datetime-local" aria-label={td('composer.when')} value={actWhen} onChange={(e) => setActWhen(e.target.value)} className="h-8 rounded-9 border border-line bg-surface px-[6px] text-12" />
                    </>
                  ) : null}
                  <button type="button" disabled={off || !canWrite} onClick={() => void submit()} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60">
                    {td(`composer.cta.${tab}`)}
                  </button>
                </span>
              </div>
            </div>

            <div className={card}>
              <div className={`${eyebrow} mb-2`}>{td('focus.title')}</div>
              {open.map((a) => (
                <div key={a.id} className="flex items-center gap-[10px] border-b border-line py-[7px] text-12.5">
                  <button type="button" aria-label={td('focus.markDone', { subject: a.subject })} disabled={!editable} onClick={() => void done(a.id, a.subject)} className="h-5 w-5 flex-none cursor-pointer rounded-999 border-[1.5px] border-ink bg-transparent disabled:cursor-default" />
                  <span className="flex-1"><b>{a.subject}</b>{when(a.starts_at) ? <span className="text-muted"> · {when(a.starts_at)}</span> : null}</span>
                  <span className={`text-11.5 font-bold ${a.priority === 'high' ? 'text-danger' : 'text-muted'}`}>{td(`focus.prio.${a.priority}`)}</span>
                </div>
              ))}
              {open.length === 0 ? <div className="py-[6px] text-12.5 text-warn-ink">{td('focus.none')}</div> : null}
            </div>

            <div className={card}>
              <div className="mb-[10px] flex flex-wrap gap-[5px]">
                {HIST_FILTERS.map((h) => (
                  <button key={h} type="button" aria-pressed={hist === h} onClick={() => setHist(h)} className={`cursor-pointer rounded-999 border px-[10px] py-1 text-11.5 ${hist === h ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}>
                    {td(`history.filters.${h}`)}
                  </button>
                ))}
              </div>
              {shownHistory.map((h, i) => (
                <div key={i} className="grid gap-[10px] border-b border-line py-[9px] text-12.5 [grid-template-columns:26px_minmax(0,1fr)_auto]">
                  <span className="flex h-6 w-6 items-center justify-center rounded-7 text-11" style={{ background: h.bg }}>{h.g}</span>
                  <span className="flex min-w-0 flex-col gap-[2px]"><b>{h.t}</b><span className="whitespace-pre-wrap break-words leading-[1.45] text-muted">{h.s}</span></span>
                  <span className="whitespace-nowrap text-11 text-faint">{format.dateTime(new Date(h.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</span>
                </div>
              ))}
              {shownHistory.length === 0 ? <div className="py-[6px] text-12.5 text-muted">{td('history.empty')}</div> : null}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function Person({ ini, name, line, action }: { ini: string; name: string; line: string; action: { label: string; run: () => void } | null }) {
  return (
    <div className="flex items-center gap-2 text-12.5">
      <span className="flex h-[26px] w-[26px] flex-none items-center justify-center rounded-8 bg-tile text-10 font-bold">{ini}</span>
      <span className="flex min-w-0 flex-1 flex-col"><b>{name}</b><span className="text-11.5 text-muted">{line}</span></span>
      {action ? <button type="button" onClick={action.run} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{action.label}</button> : null}
    </div>
  )
}
