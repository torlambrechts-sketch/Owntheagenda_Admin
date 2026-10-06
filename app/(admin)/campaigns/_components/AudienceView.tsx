'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import {
  OPS_BY_KIND, SEGMENT_FIELDS, condReady, fieldDef, fromQuery, toQuery,
  type Cond, type ConsentEntry, type Counts, type Op, type Segment, type StatusSummary, type Suppression,
} from '@/lib/data/campaigns-shared'
import { addSuppression, countSegment, deleteSegment, removeSuppression, saveSegment } from '../actions'
import { card, danger, dark, ghost, label, small } from './bits'
import { useErr, useGo } from './hooks'
import type { Can } from './CampaignsView'

export type AudienceProps = {
  segments: Segment[]
  selected: Segment | null
  summary: StatusSummary
  hygieneMonths: number | null
  log: { rows: ConsentEntry[]; next: number | null; before: number | null }
  suppressions: Suppression[] | null
  suppressionQuery: string | null
  can: Can
  nf: NumberFormat
}

/** Audience and consent (Marketing.dc.html, v.audience): the segment, saved segments, marketing status and the consent log. */
export function AudienceView(p: AudienceProps) {
  return (
    <div className="grid grid-cols-1 items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_minmax(280px,360px)]">
      <div className="flex min-w-0 flex-col gap-3">
        <SegmentEditor key={p.selected?.id ?? 'new'} {...p} />
        <SavedSegments {...p} />
      </div>
      <div className="flex min-w-0 flex-col gap-3">
        <StatusCard {...p} />
        <ConsentLogCard {...p} />
        <SuppressionsCard {...p} />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// the segment: the design's Where / AND / OR list, each condition a pill that opens its editor; counts are live
function useCondText() {
  const t = useTranslations('campaigns.segment')
  return (c: Cond) => {
    const def = fieldDef(c.f)
    if (!def) return c.f
    const group = t(`groups.${def.group}`)
    const field = t(`fields.${c.f.replace('.', '_')}`)
    const val = (v: string) => (def.kind === 'enum' || c.op === 'in' ? v.split(',').map((x) => x.trim()).filter(Boolean).map((x) => (def.kind === 'enum' && t.has(`values.${x}`) ? t(`values.${x}`) : x)).join(t('or')) : v)
    if (def.kind === 'days') return `${group} · ${t(c.f === 'engagement.opened_days' ? 'openedWithin' : 'clickedWithin', { n: c.v || '…' })}`
    if (c.op === 'between') return `${group} · ${t('ops.betweenText', { field, a: c.v || '…', b: c.v2 || '…' })}`
    return `${group} · ${t(`ops.${c.op}Text`, { field, v: val(c.v) || '…' })}`
  }
}

function SegmentEditor(p: AudienceProps) {
  const t = useTranslations('campaigns.segment')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const { go } = useGo()
  const text = useCondText()
  const parsed = p.selected ? fromQuery(p.selected.query) : []
  const [conds, setConds] = useState<Cond[]>(parsed ?? [])
  const [open, setOpen] = useState<number | null>(null)
  const [counts, setCounts] = useState<Counts | null>(p.selected ? { matches: p.selected.matches, receivable: p.selected.receivable } : null)
  const [countErr, setCountErr] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [name, setName] = useState(p.selected?.name ?? '')
  const [shared, setShared] = useState(p.selected?.shared ?? true)
  const [sure, setSure] = useState(false)
  const [busy, start] = useTransition()
  const mineOrOthers = p.selected ? (p.selected.mine ? p.can.add : p.can.editOthers) : p.can.add
  const editable = parsed !== null && mineOrOthers
  const query = JSON.stringify(toQuery(conds))
  const first = useRef(true)

  useEffect(() => {
    if (first.current && p.selected) { first.current = false; return }
    first.current = false
    const h = setTimeout(async () => {
      const r = await countSegment({ query: JSON.parse(query) })
      if (!r.ok) { setCountErr(err(r.code, r.detail)); return }
      setCountErr(null)
      setCounts(r.counts)
    }, 350)
    return () => clearTimeout(h)
  }, [query]) // eslint-disable-line react-hooks/exhaustive-deps

  const patch = (i: number, c: Partial<Cond>) => setConds((xs) => xs.map((x, k) => (k === i ? { ...x, ...c } : x)))
  const add = () => { setConds((xs) => [...xs, { join: 'and', f: 'title', op: 'eq', v: '' }]); setOpen(conds.length) }
  const save = (asNew: boolean) => start(async () => {
    const r = await saveSegment({ id: asNew ? null : p.selected?.id ?? null, name: name.trim(), query: JSON.parse(query), shared })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('saved'))
    setSaving(false)
    if (r.id !== p.selected?.id) go({ seg: r.id })
    else router.refresh()
  })
  const del = () => start(async () => {
    if (!p.selected) return
    const r = await deleteSegment({ id: p.selected.id })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('deleted'))
    go({ seg: null })
  })

  return (
    <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
      <div className="flex items-baseline justify-between gap-2">
        <b className="text-14">{p.selected ? t('title', { name: p.selected.name }) : t('titleNew')}</b>
        {p.selected ? <button type="button" onClick={() => go({ seg: null })} className="cursor-pointer border-none bg-transparent p-0 text-12 text-link underline">{t('new')}</button> : null}
      </div>
      {p.selected?.description ? <span className="text-12 text-muted">{p.selected.description}</span> : null}
      {parsed === null ? <span className="text-12 text-muted">{t('unsupported')}</span> : null}
      {conds.map((c, i) => {
        const def = fieldDef(c.f)
        return (
          <div key={i} className="flex flex-col gap-[6px]">
            <div className="flex items-center gap-2 text-12.5">
              {i === 0 ? <span className="w-11 text-10.5 font-bold text-muted">{t('where')}</span> : (
                <button type="button" disabled={!editable} onClick={() => patch(i, { join: c.join === 'and' ? 'or' : 'and' })} title={editable ? t('toggleJoin') : undefined}
                  className="w-11 cursor-pointer border-none bg-transparent p-0 text-left text-10.5 font-bold text-muted disabled:cursor-default">{c.join === 'and' ? t('and') : t('orJoin')}</button>
              )}
              <button type="button" disabled={!editable} onClick={() => setOpen(open === i ? null : i)} aria-expanded={open === i}
                className={`flex-1 cursor-pointer rounded-9 border border-line bg-canvas px-[10px] py-[6px] text-left text-12.5 text-ink disabled:cursor-default ${condReady(c) ? '' : 'text-faint'} ${open === i ? 'border-ink' : ''}`}>
                {text(c)}
              </button>
            </div>
            {open === i && editable && def ? (
              <div className="ml-[52px] flex flex-wrap items-end gap-[6px] text-12">
                <label className={label}>{t('field')}
                  <select value={c.f} onChange={(e) => { const d = fieldDef(e.target.value)!; patch(i, { f: d.f, op: OPS_BY_KIND[d.kind][0]!, v: '', v2: '' }) }} className={small}>
                    {SEGMENT_FIELDS.map((f) => <option key={f.f} value={f.f}>{t(`groups.${f.group}`)} · {t(`fields.${f.f.replace('.', '_')}`)}</option>)}
                  </select>
                </label>
                {OPS_BY_KIND[def.kind].length > 1 ? (
                  <label className={label}>{t('op')}
                    <select value={c.op} onChange={(e) => patch(i, { op: e.target.value as Op })} className={small}>
                      {OPS_BY_KIND[def.kind].map((o) => <option key={o} value={o}>{t(`ops.${o}`)}</option>)}
                    </select>
                  </label>
                ) : null}
                {def.kind === 'enum' && c.op !== 'in' ? (
                  <label className={label}>{t('value')}
                    <select value={c.v} onChange={(e) => patch(i, { v: e.target.value })} className={small}>
                      <option value="">…</option>
                      {def.options!.map((o) => <option key={o} value={o}>{t.has(`values.${o}`) ? t(`values.${o}`) : o}</option>)}
                    </select>
                  </label>
                ) : (
                  <label className={label}>{def.kind === 'days' ? t('days') : c.op === 'in' ? t('valueList') : c.op === 'between' ? t('from') : t('value')}
                    <input value={c.v} onChange={(e) => patch(i, { v: e.target.value })} inputMode={def.kind === 'text' || c.op === 'in' ? undefined : 'numeric'} className={`${small} w-[150px]`} />
                  </label>
                )}
                {c.op === 'between' ? (
                  <label className={label}>{t('to')}<input value={c.v2 ?? ''} onChange={(e) => patch(i, { v2: e.target.value })} inputMode="numeric" className={`${small} w-[80px]`} /></label>
                ) : null}
                <button type="button" onClick={() => setOpen(null)} className={dark}>{t('done')}</button>
                <button type="button" onClick={() => { setConds((xs) => xs.filter((_, k) => k !== i)); setOpen(null) }} className={danger}>{t('remove')}</button>
              </div>
            ) : null}
          </div>
        )
      })}
      {conds.length === 0 ? <span className="text-12 text-muted">{t('noConditions')}</span> : null}
      {editable ? (
        <button type="button" onClick={add} className="self-start cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] py-[5px] text-12">{t('add')}</button>
      ) : null}
      <div className="flex flex-wrap items-center justify-between gap-2 border-0 border-t border-solid border-line pt-2 text-12.5">
        <span>
          {countErr ? <span className="text-danger">{countErr}</span> : counts ? (
            t.rich('counts', { m: formatNumber(counts.matches, p.nf), r: formatNumber(counts.receivable, p.nf), b: (x) => <b>{x}</b> })
          ) : '…'}
        </span>
        {editable || (p.can.add && parsed !== null) ? (
          <button type="button" onClick={() => setSaving((x) => !x)} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold">{t('save')}</button>
        ) : null}
      </div>
      {counts && counts.matches > 0 && counts.receivable === 0 ? <span className="text-12 text-muted">{t('noneReceivable')}</span> : null}
      {saving ? (
        <div className="flex flex-wrap items-end gap-2 text-12">
          <label className={`${label} min-w-[200px] flex-1`}>{t('name')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className={small} autoFocus /></label>
          <label className="flex h-[30px] items-center gap-2"><input type="checkbox" checked={shared} onChange={(e) => setShared(e.target.checked)} style={{ accentColor: '#191510' }} />{t('shared')}</label>
          {p.selected && mineOrOthers ? <button type="button" disabled={busy || !name.trim()} onClick={() => save(false)} className={dark}>{t('saveChanges')}</button> : null}
          {p.can.add ? <button type="button" disabled={busy || !name.trim()} onClick={() => save(true)} className={dark}>{t(p.selected ? 'saveAsNew' : 'saveNew')}</button> : null}
          <button type="button" onClick={() => setSaving(false)} className={ghost}>{t('cancel')}</button>
        </div>
      ) : null}
      {p.selected && (p.selected.mine ? p.can.del : p.can.editOthers && p.can.del) ? (
        <div className="flex flex-wrap items-center gap-2 text-12">
          {sure ? <span className="text-muted">{t('deleteConfirm')}</span> : null}
          <button type="button" disabled={busy} onClick={() => (sure ? del() : setSure(true))} className={danger}>{t('delete')}</button>
          {sure ? <button type="button" onClick={() => setSure(false)} className={ghost}>{t('cancel')}</button> : null}
        </div>
      ) : null}
    </div>
  )
}

function SavedSegments(p: AudienceProps) {
  const t = useTranslations('campaigns.segment')
  const { go } = useGo()
  return (
    <div className={`overflow-hidden ${card}`}>
      <div className="border-0 border-b border-solid border-line px-[18px] py-3 text-14 font-bold">{t('savedTitle')}</div>
      {p.segments.map((s) => (
        <button key={s.id} type="button" onClick={() => go({ seg: s.id })} aria-current={p.selected?.id === s.id ? 'true' : undefined}
          className={`flex w-full cursor-pointer justify-between gap-3 border-0 border-b border-solid border-line px-[18px] py-[9px] text-left text-12.5 ${p.selected?.id === s.id ? 'bg-highlight' : 'bg-transparent'}`}>
          <b>{s.name}{!s.shared ? <span className="font-normal text-faint"> · {t('private')}</span> : null}</b>
          <span className="whitespace-nowrap text-muted">{t('people', { n: formatNumber(s.matches, p.nf), r: formatNumber(s.receivable, p.nf) })}</span>
        </button>
      ))}
      {p.segments.length === 0 ? <div className="px-[18px] py-3 text-12.5 text-muted">{t('noSaved')}</div> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
// marketing status of all addresses (0031 marketing_status_summary); bars against the largest group (spec §1)
const ORDER = ['subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived'] as const
const COLOR: Record<(typeof ORDER)[number], string> = {
  subscribed: 'bg-ok', no_consent: 'bg-line-strong', pending: 'bg-warn', unsubscribed: 'bg-alert', bounced: 'bg-danger', archived: 'bg-faint',
}
function StatusCard(p: AudienceProps) {
  const t = useTranslations('campaigns.consent')
  const n = (k: string) => p.summary.statuses.find((x) => x.status === k)?.n ?? 0
  const max = Math.max(1, ...ORDER.map(n))
  const footer = [
    p.summary.double_opt_in === 'off' ? t('doubleOptInOff') : t('doubleOptInOn'),
    t('oneList', { n: formatNumber(p.summary.suppressed, p.nf) }),
    t('logged'),
  ].join(' · ')
  return (
    <div className={`${card} flex flex-col gap-[7px] px-[18px] py-4`}>
      <b className="text-14">{t('statusTitle')}</b>
      {ORDER.map((k) => (
        <div key={k} className="grid items-center gap-2 text-12.5 [grid-template-columns:150px_minmax(0,1fr)_46px]">
          <span>{k === 'archived' && p.hygieneMonths ? t('archivedMonths', { m: p.hygieneMonths }) : t(`status.${k}`)}</span>
          <span className="h-2 overflow-hidden rounded-999 bg-tile"><span className={`block h-full ${COLOR[k]}`} style={{ width: `${(n(k) / max) * 100}%` }} /></span>
          <b className="text-right">{formatNumber(n(k), p.nf)}</b>
        </div>
      ))}
      <div className="border-0 border-t border-solid border-line pt-[7px] text-11.5 text-muted">{footer}</div>
    </div>
  )
}

function useConsentLine() {
  const t = useTranslations('campaigns.consent')
  const fmt = useFormatter()
  return (c: ConsentEntry) => {
    const when = fmt.dateTime(new Date(c.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
    const label = c.ref_label ? `«${c.ref_label}»` : null
    let what: string
    if (c.ref_type === 'campaign' && c.status === 'unsubscribed') what = t(c.detail === 'one_click' ? 'src.oneClick' : 'src.unsubscribe', { campaign: label ?? '' })
    else if (c.ref_type === 'campaign') what = t('src.campaign', { campaign: label ?? '' })
    else if (c.ref_type === 'provider') what = t('src.provider', { code: c.detail ?? '—', campaign: label ?? '' })
    else if (c.ref_type === 'form_submission') what = t('src.form', { form: label ?? '' })
    else if (c.ref_type === 'confirmation') what = t('src.confirmation')
    else if (c.ref_type === 'list_hygiene') what = t('src.hygiene')
    else if (c.ref_type === 'email_changed') what = t('src.emailChanged')
    else what = c.source
    return [what, c.actor ? t('src.by', { name: c.actor }) : null, c.text_version ? t('src.wording', { v: c.text_version }) : null, when].filter(Boolean).join(' · ')
  }
}

function ConsentLogCard(p: AudienceProps) {
  const t = useTranslations('campaigns.consent')
  const { go } = useGo()
  const line = useConsentLine()
  const st = (s: string) => (t.has(`status.${s}`) ? t(`status.${s}`) : s)
  return (
    <div className={`overflow-hidden ${card}`}>
      <div className="border-0 border-b border-solid border-line px-4 py-3 text-13.5 font-bold">{t('logTitle')}</div>
      {p.log.rows.map((c) => (
        <div key={c.id} className="border-0 border-b border-solid border-line px-4 py-2 text-12">
          <b>{c.email ?? c.name ?? '—'}</b> · {c.prev_status ? `${st(c.prev_status)} → ${st(c.status)}` : st(c.status)}
          <div className="text-muted">{line(c)}</div>
        </div>
      ))}
      {p.log.rows.length === 0 ? <div className="px-4 py-3 text-12 text-muted">{t('logEmpty')}</div> : null}
      {p.log.before || p.log.next ? (
        <div className="flex gap-3 px-4 py-2 text-12">
          {p.log.before ? <button type="button" onClick={() => go({ before: null })} className="cursor-pointer border-none bg-transparent p-0 text-12 text-link underline">{t('newest')}</button> : null}
          {p.log.next && p.log.rows.length >= 8 ? <button type="button" onClick={() => go({ before: String(p.log.next) })} className="cursor-pointer border-none bg-transparent p-0 text-12 text-link underline">{t('older')}</button> : null}
        </div>
      ) : null}
    </div>
  )
}

function SuppressionsCard(p: AudienceProps) {
  const t = useTranslations('campaigns.suppressions')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const { go } = useGo()
  const [q, setQ] = useState(p.suppressionQuery ?? '')
  const [email, setEmail] = useState('')
  const [scope, setScope] = useState<'marketing' | 'all'>('marketing')
  const [busy, start] = useTransition()
  const add = () => start(async () => {
    const r = await addSuppression({ email: email.trim(), scope })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t(r.added ? 'added' : 'already'))
    setEmail('')
    router.refresh()
  })
  const remove = (s: Suppression) => start(async () => {
    if (!s.email) return
    const r = await removeSuppression({ email: s.email, scope: s.scope })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('removed'))
    router.refresh()
  })
  return (
    <div className={`overflow-hidden ${card}`}>
      <div className="border-0 border-b border-solid border-line px-4 py-3 text-13.5 font-bold">{t('title')}</div>
      <form onSubmit={(e) => { e.preventDefault(); go({ sq: q.trim() || null }) }} className="flex gap-[6px] border-0 border-b border-solid border-line px-4 py-2">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('search')} aria-label={t('search')} className={`${small} min-w-0 flex-1`} />
        <button type="submit" className={ghost}>{t('find')}</button>
      </form>
      {p.suppressions === null ? <div className="px-4 py-2 text-12 text-danger">{t('badSearch')}</div> : p.suppressions.map((s) => (
        <div key={`${s.hash}:${s.scope}`} className="flex items-center justify-between gap-2 border-0 border-b border-solid border-line px-4 py-2 text-12">
          <span className="min-w-0">
            <b className="break-all">{s.email ?? t('hashOnly', { hash: s.hash })}</b>
            <div className="text-muted">{t(`scope.${s.scope}`)} · {t.has(`reason.${s.reason}`) ? t(`reason.${s.reason}`) : s.reason} · {fmt.dateTime(new Date(s.created_at), { day: 'numeric', month: 'short', year: 'numeric' })}</div>
          </span>
          {p.can.bulk && s.email && ['manual', 'hard_bounce', 'soft_bounces'].includes(s.reason) ? (
            <button type="button" disabled={busy} onClick={() => remove(s)} className={ghost}>{t('lift')}</button>
          ) : null}
        </div>
      ))}
      {p.suppressions && p.suppressions.length === 0 ? <div className="px-4 py-2 text-12 text-muted">{t(p.suppressionQuery ? 'notFound' : 'empty')}</div> : null}
      {p.can.bulk ? (
        <div className="flex flex-wrap gap-[6px] px-4 py-2">
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t('addPlaceholder')} aria-label={t('addPlaceholder')} className={`${small} min-w-[160px] flex-1`} />
          <select value={scope} onChange={(e) => setScope(e.target.value as 'marketing' | 'all')} aria-label={t('scopeLabel')} className={small}>
            <option value="marketing">{t('scope.marketing')}</option><option value="all">{t('scope.all')}</option>
          </select>
          <button type="button" disabled={busy || !email.trim()} onClick={add} className={dark}>{t('add')}</button>
        </div>
      ) : null}
      <div className="px-4 pb-2 text-11 text-faint">{t('note')}</div>
    </div>
  )
}
