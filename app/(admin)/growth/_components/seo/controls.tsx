'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { ChangeKind, OppKind, Rule, Stage } from '@/lib/growth/seo'
import { CHANGE_KINDS } from '@/lib/growth/seo'
import { alertAck, alertRuleSet, changeAdd, linkDecide, planAdd, planMove } from '../../seo-actions'

/**
 * The SEO suite's buttons and forms (SeoSuite.dc.html): each calls one server action, says what happened in the toast,
 * and refreshes the view from the database. Without the right, the database refuses and the toast says so.
 */

/** «Do it» / «Plan» → «✓ In plan» (height 30 or 26, radius 9 or 8, yellow; teal once planned) */
export function PlanButton({ product, query, kind, path, planned, label, small = false, disabled = false }: {
  product: string; query: string; kind: OppKind; path: string | null; planned: boolean; label: string; small?: boolean; disabled?: boolean
}) {
  const t = useTranslations('simpleGrowth.seoSuite')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const size = small ? 'h-[26px] rounded-8 px-[9px] text-11.5' : 'h-[30px] rounded-9 px-[11px] text-12'
  return (
    <button type="button" disabled={pending || planned || disabled} aria-pressed={planned}
      onClick={() => start(async () => {
        const r = await planAdd({ product, query, kind, path })
        if (!r.ok) { flash(te(r.code)); return }
        flash(t('planned'))
        router.refresh()
      })}
      className={`flex-none cursor-pointer whitespace-nowrap border border-ink font-bold text-ink disabled:cursor-default ${size} ${planned ? 'bg-ok-bg' : 'bg-primary'}`}>
      {planned ? t('inPlan') : label}
    </button>
  )
}

/** ← and → on a plan card (24 × 24, radius 7) */
export function PlanMove({ id, back, fwd, backLabel, fwdLabel, backName, fwdName }: {
  id: string; back: Stage | null; fwd: Stage | null; backLabel: string; fwdLabel: string; backName: string; fwdName: string
}) {
  const t = useTranslations('simpleGrowth.seoSuite.plan')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const move = (stage: Stage, name: string) => start(async () => {
    const r = await planMove({ id, stage })
    if (!r.ok) { flash(te(r.code)); return }
    flash(r.logged ? t('movedLogged', { stage: name }) : t('moved', { stage: name }))
    router.refresh()
  })
  return (
    <span className="flex gap-[3px]">
      <button type="button" disabled={pending || !back} aria-label={backLabel} title={backLabel} onClick={() => back && move(back, backName)}
        className="h-6 w-6 cursor-pointer rounded-7 border border-line bg-transparent text-11 text-ink disabled:cursor-default disabled:opacity-40">←</button>
      <button type="button" disabled={pending || !fwd} aria-label={fwdLabel} title={fwdLabel} onClick={() => fwd && move(fwd, fwdName)}
        className="h-6 w-6 cursor-pointer rounded-7 border border-ink bg-surface text-11 text-ink disabled:cursor-default disabled:opacity-40">→</button>
    </span>
  )
}

/** «Skip» and «Add link» on a suggested internal link */
export function LinkDecide({ product, from, to, anchor }: { product: string; from: string; to: string; anchor: string }) {
  const t = useTranslations('simpleGrowth.seoSuite.links')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const decide = (decision: 'added' | 'skipped') => start(async () => {
    const r = await linkDecide({ product, from, to, anchor, decision })
    if (!r.ok) { flash(te(r.code)); return }
    flash(decision === 'added' ? t('addedToast') : t('skippedToast'))
    router.refresh()
  })
  return (
    <>
      <button type="button" disabled={pending} onClick={() => decide('skipped')}
        className="h-7 cursor-pointer rounded-8 border border-line bg-transparent px-[9px] text-11.5 text-ink">{t('skip')}</button>
      <button type="button" disabled={pending} onClick={() => decide('added')}
        className="h-7 cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-primary px-[10px] text-11.5 font-bold text-ink">{t('add')}</button>
    </>
  )
}

/** «Log a change»: page, kind, note, «Log change» (selects and input 34 high, radius 9, on the canvas colour) */
export function ChangeForm({ product, pages }: { product: string; pages: string[] }) {
  const t = useTranslations('simpleGrowth.seoSuite.changes')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [page, setPage] = useState(pages[0] ?? '/')
  const [kind, setKind] = useState<ChangeKind>('title_meta')
  const [note, setNote] = useState('')
  const [pending, start] = useTransition()
  const field = 'h-[34px] rounded-9 border border-line bg-canvas text-12.5 text-ink'
  return (
    <form className="contents" onSubmit={(e) => {
      e.preventDefault()
      start(async () => {
        const r = await changeAdd({ product, path: page, kind, note })
        if (!r.ok) { flash(te(r.code)); return }
        setNote('')
        flash(t('logged'))
        router.refresh()
      })
    }}>
      <select value={page} onChange={(e) => setPage(e.target.value)} aria-label={t('pagePick')} className={`${field} max-w-full`} disabled={!pages.length}>
        {pages.map((p) => <option key={p} value={p}>{p}</option>)}
      </select>
      <select value={kind} onChange={(e) => setKind(e.target.value as ChangeKind)} aria-label={t('kindPick')} className={field}>
        {CHANGE_KINDS.map((k) => <option key={k} value={k}>{t(`kinds.${k}`)}</option>)}
      </select>
      <input value={note} onChange={(e) => setNote(e.target.value)} placeholder={t('note')} aria-label={t('note')} maxLength={200}
        className={`${field} min-w-0 flex-[1_1_200px] px-[10px]`} />
      <button type="submit" disabled={pending || !pages.length}
        className="h-[34px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold text-ink">{t('submit')}</button>
    </form>
  )
}

/** An alert rule's row (rules[]: padding 11×18; the name 13 bold and the switch 40 × 22 with a 16 px knob; the condition
 *  12 px muted and the channel pills); off, the row is at half opacity */
export function RuleRow({ product, rule, name, cond, enabled, channels, mailReady, canEdit }: {
  product: string; rule: Rule; name: string; cond: string; enabled: boolean; channels: string[]; mailReady: boolean; canEdit: boolean
}) {
  const t = useTranslations('simpleGrowth.seoSuite.alerts')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const save = (on: boolean, ch: string[]) => start(async () => {
    const r = await alertRuleSet({ product, rule, enabled: on, channels: ch })
    if (!r.ok) { flash(te(r.code)); return }
    router.refresh()
  })
  const op = enabled ? '' : 'opacity-50'
  return (
    <div className="flex flex-col gap-[7px] border-b border-line px-[18px] py-[11px]">
      <div className="flex items-center justify-between gap-[10px]">
        <b className={`text-13 ${op}`}>{name}</b>
        <button type="button" role="switch" aria-checked={enabled} aria-label={t('toggle', { rule: name })} disabled={pending || !canEdit}
          onClick={() => save(!enabled, channels)}
          className={`relative h-[22px] w-10 flex-none cursor-pointer rounded-999 border-none disabled:cursor-default ${enabled ? 'bg-ink' : 'bg-line-strong'}`}>
          <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: enabled ? 21 : 3 }} />
        </button>
      </div>
      <div className={`flex flex-wrap items-center gap-[6px] text-12 text-muted ${op}`}>
        <span>{cond}</span>
        {(['app', 'email'] as const).map((c) => {
          const sel = channels.includes(c)
          return (
            <button key={c} type="button" aria-pressed={sel} disabled={pending || !canEdit}
              title={c === 'email' && !mailReady ? t('mailOff') : undefined}
              onClick={() => save(enabled, sel ? channels.filter((x) => x !== c) : [...channels, c])}
              className={`cursor-pointer whitespace-nowrap rounded-999 border px-[9px] py-[3px] text-11 text-ink disabled:cursor-default ${sel ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {t(`channels.${c}`)}
            </button>
          )
        })}
      </div>
    </div>
  )
}

/** «Acknowledge» / «Reopen» (height 28, radius 8) */
export function AckButton({ id, acked, canAck }: { id: string; acked: boolean; canAck: boolean }) {
  const t = useTranslations('simpleGrowth.seoSuite.alerts')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending || !canAck}
      onClick={() => start(async () => {
        const r = await alertAck({ id, ack: !acked })
        if (!r.ok) { flash(te(r.code)); return }
        router.refresh()
      })}
      className="h-7 flex-none cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-surface px-[10px] text-11.5 font-bold text-ink disabled:cursor-default">
      {acked ? t('reopen') : t('ack')}
    </button>
  )
}
