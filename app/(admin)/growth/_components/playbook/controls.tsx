'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { addBlackout, removeBlackout } from '../../playbook-actions'
import { setSequenceState } from '../../actions'

/**
 * The playbook's small controls (GrowthPlaybook.dc.html): each calls one server action, says what happened in the toast and
 * refreshes the view from the database. Without the right, the database refuses and the toast says so.
 */

const field = 'h-[34px] rounded-9 border border-line bg-canvas text-12.5 text-ink'

/** a blackout period: its name and its first and last day */
export function BlackoutForm({ product, year }: { product: string; year: number }) {
  const t = useTranslations('simpleGrowth.playbook.calendar')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [name, setName] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [pending, start] = useTransition()
  const ready = name.trim() && from && to && to >= from
  return (
    <form className="flex flex-wrap items-center gap-2 px-[18px] py-3" onSubmit={(e) => {
      e.preventDefault()
      if (!ready) return
      start(async () => {
        const r = await addBlackout({ product, name, from, to })
        if (!r.ok) { flash(te(r.code)); return }
        setName(''); setFrom(''); setTo('')
        flash(t('added'))
        router.refresh()
      })
    }}>
      <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder={t('name')} aria-label={t('name')}
        className={`${field} min-w-0 flex-[1_1_160px] px-[10px]`} />
      <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} aria-label={t('from')} min={`${year - 1}-01-01`} max={`${year + 1}-12-31`}
        className={`${field} px-2`} />
      <input type="date" value={to} onChange={(e) => setTo(e.target.value)} aria-label={t('to')} min={from || `${year - 1}-01-01`} max={`${year + 1}-12-31`}
        className={`${field} px-2`} />
      <button type="submit" disabled={pending || !ready}
        className="h-[34px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold text-ink disabled:cursor-default">
        {t('add')}
      </button>
    </form>
  )
}

export function RemoveBlackout({ id, name }: { id: string; name: string }) {
  const t = useTranslations('simpleGrowth.playbook.calendar')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending} aria-label={t('remove', { name })} title={t('remove', { name })}
      onClick={() => start(async () => {
        const r = await removeBlackout({ id })
        if (!r.ok) { flash(te(r.code)); return }
        flash(t('removed'))
        router.refresh()
      })}
      className="h-6 w-6 flex-none cursor-pointer rounded-7 border border-line bg-transparent text-11 text-ink disabled:cursor-default disabled:opacity-40">×</button>
  )
}

/** «Activate» / «Pause» on a flow (height 28, radius 8): the engine's own switch, refused while a step blocks it */
export function FlowToggle({ id, name, live, blocked, canEdit }: { id: string; name: string; live: boolean; blocked: string | null; canEdit: boolean }) {
  const t = useTranslations('simpleGrowth.playbook.library')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending || !canEdit || (!live && !!blocked)} title={!live && blocked ? blocked : undefined}
      onClick={() => start(async () => {
        const r = await setSequenceState({ id, state: live ? 'draft' : 'active' })
        if (!r.ok) { flash(te(r.code)); return }
        flash(live ? t('paused', { name }) : t('activated', { name }))
        router.refresh()
      })}
      className={`h-7 flex-none cursor-pointer whitespace-nowrap rounded-8 border border-ink px-[10px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50 ${live ? 'bg-surface' : 'bg-primary'}`}>
      {live ? t('pause') : t('activate')}
    </button>
  )
}
