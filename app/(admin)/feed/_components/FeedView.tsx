'use client'

import Link from 'next/link'
import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { ui } from '@/components/ui/styles'
import { money, formatNumber, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import { AI_KINDS, FEED_TABS, KINDS, KIND_TONE, type FeedTab } from '@/lib/data/feed-shared'
import type { FeedCard, FeedData, Progress } from '@/lib/data/feed'
import { openDeal, openOrg, resolveCard, setScope, type PanelData } from '../actions'
import { useErr, useGo } from './go'

export type PipelineLite = { id: string; name: string; stages: { id: string; name: string }[] }

type Panel =
  | { kind: 'deal'; data: PanelData }
  | { kind: 'org'; id: string; name: string; city: string | null; acts: PanelData['acts'] }

/** Feed › Feed (Feed.dc.html, v.feed): the cards of a sub-tab, the progress panel and the side panel. */
export function FeedView({ ft, kind, stage, smin, smax, feed, progress, pipelines, canSend, nf, products }: {
  ft: FeedTab
  kind: string | null
  stage: string | null
  smin: number | null
  smax: number | null
  feed: FeedData
  progress: Progress
  pipelines: PipelineLite[]
  canSend: boolean
  nf: NumberFormat
  products: Record<string, string>
}) {
  const t = useTranslations('feed')
  const flash = useToast()
  const err = useErr()
  const router = useRouter()
  const { go } = useGo()
  const text = useCardText(nf, products)
  const [panel, setPanel] = useState<Panel | null>(null)
  const [busy, start] = useTransition()
  const sideRef = useRef<HTMLDivElement>(null)

  const act = (c: FeedCard, how: 'task' | 'email') => start(async () => {
    if (how === 'email' && !canSend) { flash(t('toast.noMailbox')); return }
    const r = await resolveCard({ id: c.id, how })
    if (!r.ok) { flash(err(r.code)); return }
    flash(t(how === 'task' ? 'toast.task' : 'toast.email'))
    if (how === 'email') router.push('/inbox')
  })

  const open = (c: FeedCard) => start(async () => {
    if (c.deal) {
      const r = await openDeal({ id: c.deal.id })
      if (!r.ok) { flash(err(r.code)); return }
      setPanel({ kind: 'deal', data: r.panel })
    } else if (c.organization) {
      const r = await openOrg({ id: c.organization.id })
      if (!r.ok) { flash(err(r.code)); return }
      setPanel({ kind: 'org', id: c.organization.id, name: c.organization.name, city: c.organization.city, acts: r.acts })
    }
  })
  // on a narrow screen the side column sits under the cards: bring the opened panel into view
  useEffect(() => { if (panel && window.matchMedia('(max-width: 1023px)').matches) sideRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }) }, [panel])

  const kinds = KINDS[ft].filter((k) => feed.ai_scoring || !AI_KINDS.includes(k))
  const scoped = feed.scope.pipeline_ids.length ? pipelines.filter((p) => feed.scope.pipeline_ids.includes(p.id)) : pipelines
  const today = [
    { n: t('progress.tasks'), d: progress.today.task.done, of: progress.today.task.total },
    { n: t('progress.calls'), d: progress.today.call.done, of: progress.today.call.total },
    { n: t('progress.activities'), d: progress.today.all.done, of: progress.today.all.total },
  ]
  const month = [
    { n: t('progress.newDeals'), v: formatNumber(progress.month.new_deals, nf) },
    { n: t('progress.wonDeals'), v: `${formatNumber(progress.month.won_count, nf)} · ${money(progress.month.won_value, nf)}` },
    { n: t('progress.forecast'), v: money(progress.month.forecast, nf) },
  ]

  return (
    <div className="grid items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_300px]">
      <div className="flex min-w-0 flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex max-w-full overflow-x-auto rounded-11 bg-tile p-[3px]" role="tablist">
            {FEED_TABS.map((k) => (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={ft === k}
                onClick={() => { setPanel(null); go({ ft: k === 'follow_ups' ? null : k, kind: null }) }}
                className={`cursor-pointer whitespace-nowrap rounded-8 border-none px-[13px] py-[7px] text-12.5 ${ft === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
              >
                {t(`subTabs.${k}`)} <span className="text-muted">{feed.counts[k] ?? 0}</span>
              </button>
            ))}
          </div>
          <FilterButton kinds={kinds} kind={kind} stage={stage} smin={feed.ai_scoring ? smin : null} smax={feed.ai_scoring ? smax : null} scores={feed.ai_scoring} scoped={scoped} pipelines={pipelines} chosen={feed.scope.pipeline_ids} />
          <span className="flex-1" />
          <span className="rounded-999 bg-ok-bg px-3 py-[6px] text-12.5 font-bold text-ok-ink">{t('doneToday', { n: progress.done_today })}</span>
        </div>

        {feed.cards.map((c) => {
          const x = text(c)
          return (
            <div key={c.id} className="flex items-start gap-[14px] rounded-18 border border-line bg-surface px-4 py-[14px] max-sm:flex-wrap">
              <span className={`w-[7px] self-stretch rounded-999 ${KIND_TONE[c.kind] ?? 'bg-warn'}`} />
              <div className="flex min-w-0 flex-1 flex-col gap-1">
                <span className="text-11 font-bold uppercase tracking-label text-muted">{x.kind}</span>
                <b className="text-13.5 leading-[1.35]">{x.title}</b>
                <span className="text-12.5 text-muted">{x.sub}</span>
              </div>
              <div className="flex flex-wrap justify-end gap-[6px] max-sm:w-full max-sm:pl-[21px] max-sm:justify-start">
                <button
                  type="button"
                  disabled={busy || !c.deal}
                  title={c.deal ? undefined : t('noDealTask')}
                  onClick={() => act(c, 'task')}
                  className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-50"
                >
                  {t('actions.task')}
                </button>
                <button type="button" disabled={busy} onClick={() => act(c, 'email')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">
                  {t('actions.email')}
                </button>
                <button type="button" disabled={busy} onClick={() => open(c)} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold">
                  {t('actions.open')}
                </button>
              </div>
            </div>
          )
        })}
        {feed.cards.length === 0 ? (
          <div className="rounded-20 border border-dashed border-line-strong p-[34px] text-center text-13 text-muted">{t('allDone')}</div>
        ) : null}
      </div>

      <div ref={sideRef} className="flex flex-col gap-3 lg:sticky lg:top-[76px]">
        <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('progress.today')}</b>
          {today.map((p) => (
            <div key={p.n} className="grid items-center gap-2 text-12.5 [grid-template-columns:90px_minmax(0,1fr)_44px]">
              <span>{p.n}</span>
              <span className="h-2 overflow-hidden rounded-999 bg-tile">
                <span className="block h-full bg-ok" style={{ width: `${p.of ? (p.d / p.of) * 100 : 0}%` }} />
              </span>
              <b className="text-right">{p.d}/{p.of}</b>
            </div>
          ))}
          <b className="mt-[6px] text-14">{t('progress.month')}</b>
          {month.map((p) => (
            <div key={p.n} className="flex justify-between border-b border-line py-1 text-12.5">
              <span className="text-muted">{p.n}</span>
              <b>{p.v}</b>
            </div>
          ))}
        </div>
        {panel ? <SidePanel panel={panel} nf={nf} onClose={() => setPanel(null)} /> : null}
      </div>
    </div>
  )
}

function SidePanel({ panel, nf, onClose }: { panel: Panel; nf: NumberFormat; onClose: () => void }) {
  const t = useTranslations('feed.panel')
  const title = panel.kind === 'deal' ? panel.data.title : panel.name
  const line = panel.kind === 'deal'
    ? [money(panel.data.value, nf, panel.data.currency), panel.data.organization, panel.data.person].filter(Boolean).join(' · ')
    : panel.city ?? ''
  const acts = panel.kind === 'deal' ? panel.data.acts : panel.acts
  const person = panel.kind === 'deal' && panel.data.person ? [panel.data.person, panel.data.role].filter(Boolean).join(' · ') : null
  return (
    <div className="flex flex-col gap-2 rounded-20 border border-ink bg-surface px-[18px] py-4" aria-live="polite">
      <div className="flex justify-between gap-2">
        <b className="text-14">{title}</b>
        <button type="button" onClick={onClose} aria-label={t('close')} className="cursor-pointer border-none bg-transparent">×</button>
      </div>
      {line ? <span className="text-12.5 text-muted">{line}</span> : null}
      {acts.map((a) => <div key={a.id} className="border-b border-line py-[5px] text-12.5">{a.subject} · {t(a.done ? 'done' : 'planned')}</div>)}
      {person ? <div className="border-b border-line py-[5px] text-12.5">{person}</div> : null}
      <Link
        href={(panel.kind === 'deal' ? recordHref('deal', panel.data.id) : recordHref('organization', panel.id)) as never}
        className="flex h-8 items-center justify-center rounded-9 border border-ink bg-primary text-12 font-bold text-ink hover:text-ink hover:no-underline"
      >
        {t(panel.kind === 'deal' ? 'openDeal' : 'openOrganization')}
      </Link>
    </div>
  )
}

/**
 * Card filters by type and stage, and the feed's one-time scope (PRO-01/02). Not in the design; built in its
 * language (D-41) behind one button so the design's tab row keeps its shape.
 */
function FilterButton({ kinds, kind, stage, smin, smax, scores, scoped, pipelines, chosen }: {
  kinds: string[]; kind: string | null; stage: string | null; smin: number | null; smax: number | null; scores: boolean; scoped: PipelineLite[]; pipelines: PipelineLite[]; chosen: string[]
}) {
  const t = useTranslations('feed')
  const flash = useToast()
  const err = useErr()
  const { go } = useGo()
  const [open, setOpen] = useState(false)
  const all = pipelines.map((x) => x.id)
  const [sel, setSel] = useState<string[]>(chosen.length ? chosen : all)
  const [busy, start] = useTransition()
  const active = (kind ? 1 : 0) + (stage ? 1 : 0) + (smin !== null || smax !== null ? 1 : 0) + (chosen.length ? 1 : 0)
  const save = () => start(async () => {
    const r = await setScope({ pipelineIds: sel.length === pipelines.length ? [] : sel })
    if (!r.ok) { flash(err(r.code)); return }
    setOpen(false)
    flash(t('scope.saved'))
  })
  const sel2 = `${ui.select} w-full px-1`
  return (
    <span className="relative">
      <button type="button" aria-expanded={open} onClick={() => { setSel(chosen.length ? chosen : all); setOpen(!open) }} className={`${ui.btnSmall} ${active ? 'border-ink' : ''}`}>
        {active ? t('filter.buttonActive', { n: active }) : t('filter.button')}
      </button>
      {open ? (
        <div onKeyDown={(e) => { if (e.key === 'Escape') setOpen(false) }} className="absolute left-0 top-[36px] z-30 flex w-[280px] flex-col gap-2 rounded-14 border border-line bg-surface p-[14px] shadow-pop">
          <label className="flex flex-col gap-1 text-12">
            <span className={ui.eyebrow}>{t('filter.kind')}</span>
            <select value={kind ?? ''} onChange={(e) => go({ kind: e.target.value || null })} className={sel2}>
              <option value="">{t('filter.allKinds')}</option>
              {kinds.map((k) => <option key={k} value={k}>{t(`cards.${k}.name`)}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-12">
            <span className={ui.eyebrow}>{t('filter.stage')}</span>
            <select value={stage ?? ''} onChange={(e) => go({ stage: e.target.value || null })} className={sel2}>
              <option value="">{t('filter.allStages')}</option>
              {scoped.map((p) => (
                <optgroup key={p.id} label={p.name}>
                  {p.stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </optgroup>
              ))}
            </select>
          </label>
          {scores ? (
            <div className="flex flex-col gap-1 text-12">
              <span className={ui.eyebrow}>{t('filter.score')}</span>
              <span className="flex items-center gap-2">
                <ScoreInput label={t('filter.scoreMin')} value={smin} onSet={(v) => go({ smin: v })} />
                <span>–</span>
                <ScoreInput label={t('filter.scoreMax')} value={smax} onSet={(v) => go({ smax: v })} />
              </span>
            </div>
          ) : null}
          <span className={`${ui.eyebrow} mt-1`}>{t('scope.title')}</span>
          <span className="text-12 text-muted">{t('scope.hint')}</span>
          {pipelines.map((p) => (
            <label key={p.id} className="flex cursor-pointer items-center gap-2 text-12.5">
              <input
                type="checkbox"
                className="accent-ink"
                checked={sel.includes(p.id)}
                onChange={(e) => setSel(e.target.checked ? [...sel, p.id] : sel.filter((x) => x !== p.id))}
              />
              {p.name}
            </label>
          ))}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setOpen(false)} className={ui.btnSmall}>{t('scope.cancel')}</button>
            <button type="button" disabled={busy || sel.length === 0} onClick={save} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50">{t('scope.save')}</button>
          </div>
        </div>
      ) : null}
    </span>
  )
}

/** One end of the score range (0–100): applied on Enter or when the field is left. */
function ScoreInput({ label, value, onSet }: { label: string; value: number | null; onSet: (v: string | null) => void }) {
  const [v, setV] = useState(value === null ? '' : String(value))
  const commit = () => {
    const n = v.trim() === '' ? null : Math.round(Number(v))
    if (n !== null && (Number.isNaN(n) || n < 0 || n > 100)) { setV(value === null ? '' : String(value)); return }
    if (n !== value) onSet(n === null ? null : String(n))
  }
  return (
    <input
      type="number"
      min={0}
      max={100}
      aria-label={label}
      placeholder={label}
      value={v}
      onChange={(e) => setV(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => { if (e.key === 'Enter') commit() }}
      className={`${ui.select} w-[90px] px-2`}
    />
  )
}

// ---------------------------------------------------------------------------
const str = (v: unknown) => (typeof v === 'string' ? v : null)
const int = (v: unknown) => (typeof v === 'number' ? v : typeof v === 'string' && v !== '' && !Number.isNaN(Number(v)) ? Number(v) : null)

/** A card worded from its kind and parameters (0022 feed_get: never prose). */
function useCardText(nf: NumberFormat, products: Record<string, string>) {
  const t = useTranslations('feed.cards')
  const format = useFormatter()
  const now = useNow()
  const typeT = useTranslations('feed.typeNames')
  const prioT = useTranslations('feed.priority')
  return (c: FeedCard): { kind: string; title: string; sub: string } => {
    const p = c.params
    const deal = c.deal?.title ?? '—'
    const org = c.organization?.name ?? '—'
    const person = c.deal?.person ?? t('someone')
    const day = (iso: string | null) => (iso ? format.dateTime(new Date(iso), { day: 'numeric', month: 'short' }) : '—')
    // the deal's owner as feed_get names it (0027), by first name as the design writes it
    const owner = c.deal?.owner ? c.deal.owner.split(' ')[0] : null
    const value = c.deal ? money(c.deal.value ?? 0, nf, c.deal.currency ?? 'NOK') : ''
    const dealSub = c.deal ? (owner ? t('dealSub', { value, org, owner }) : t('dealSubNoOwner', { value, org })) : org
    const subject = str(p.subject) ?? '—'
    switch (c.kind) {
      case 'email_reply': {
        const r = int(p.readiness)
        return { kind: t('email_reply.label'), title: t('email_reply.title', { from: str(p.from) ?? person, deal }), sub: r !== null ? t('email_reply.subReady', { subject, r }) : t('email_reply.sub', { subject }) }
      }
      case 'no_reply':
        return { kind: t('no_reply.label'), title: deal, sub: t('no_reply.sub', { person, subject, date: day(str(p.since)) }) }
      case 'planned_today': {
        const at = str(p.starts_at)
        const type = str(p.type)
        const prio = str(p.priority)
        return {
          kind: t('planned_today.label'), title: t('planned_today.title', { subject, org }),
          sub: [at ? format.dateTime(new Date(at), { hour: '2-digit', minute: '2-digit' }) : null,
            type ? (typeT.has(type) ? typeT(type) : type) : null,
            prio && prioT.has(prio) ? prioT(prio) : null].filter(Boolean).join(' · '),
        }
      }
      case 'email_opened': {
        const last = str(p.last_at)
        return { kind: t('email_opened.label'), title: t('email_opened.title', { person, subject, count: int(p.count) ?? 1 }), sub: last ? t('email_opened.sub', { ago: format.relativeTime(new Date(last), now) }) : '' }
      }
      case 'link_clicked':
      {
        const seq = str(p.sequence)
        const step = int(p.step)
        const sub = seq ? (step !== null ? t('link_clicked.subStep', { sequence: seq, step }) : t('link_clicked.subSequence', { sequence: seq })) : t('link_clicked.sub', { subject })
        return { kind: t('link_clicked.label'), title: t('link_clicked.title', { person, label: str(p.label) ?? '—' }), sub }
      }
      case 'sequence_review':
        return { kind: t('sequence_review.label'), title: t('sequence_review.title', { subject }), sub: t('sequence_review.sub', { sequence: str(p.sequence) ?? '—', org }) }
      case 'overdue_activity':
        return { kind: t('overdue_activity.label', { days: int(p.idle_days) ?? 0 }), title: deal, sub: dealSub }
      case 'no_followup':
        return { kind: t('no_followup.label'), title: deal, sub: dealSub }
      case 'slipping':
        return { kind: t('slipping.label'), title: deal, sub: t('slipping.sub', { date: day(str(p.close_date)), days: int(p.idle_days) ?? 0 }) }
      case 'stalled':
        return { kind: t('stalled.label'), title: deal, sub: t('stalled.sub', { stage: str(p.stage) ?? c.deal?.stage ?? '—', days: int(p.days_in_stage) ?? 0 }) }
      case 'new_no_activity':
        return { kind: t('new_no_activity.label'), title: deal, sub: c.deal ? t('new_no_activity.sub', { value: money(c.deal.value ?? 0, nf, c.deal.currency ?? 'NOK'), org }) : org }
      case 'cross_sell': {
        const key = str(p.product)
        const emp = int(p.employees)
        return {
          kind: t('cross_sell.label'), title: t('cross_sell.title', { org, product: key ? products[key] ?? key : '—' }),
          sub: emp !== null ? t('cross_sell.sub', { employees: formatNumber(emp, nf) }) : t('cross_sell.subNoEmployees'),
        }
      }
      case 'likely_to_advance': {
        const pct = int(p.probability)
        return { kind: pct !== null ? t('likely_to_advance.labelPct', { pct }) : t('likely_to_advance.label'), title: deal, sub: str(p.reason) ?? '' }
      }
      default:
        return { kind: c.kind, title: c.deal?.title ?? org, sub: '' }
    }
  }
}
