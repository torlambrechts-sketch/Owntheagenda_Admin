'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Share } from '@/lib/data/insights'
import { shareDashboardAction } from '../actions'
import type { Pickers } from './shared'

const sel = 'h-7 rounded-8 border border-line bg-canvas text-12'

/**
 * Share (design: shareOpen): who sees the dashboard and with which role, kept in dashboard_shares (staff,
 * team or visibility group; viewer or editor). The public live link waits for go.owntheagenda.com (D-28),
 * so its control is shown unavailable with the reason.
 */
export function SharePopover({ dashboard, shares, pickers, meId }: { dashboard: string; shares: Share[]; pickers: Pickers; meId: string }) {
  const t = useTranslations('insights.share')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pick, setPick] = useState('')
  const [role, setRole] = useState<'viewer' | 'editor'>('viewer')
  const [busy, setBusy] = useState(false)

  const apply = async (kind: Share['kind'], grantee: string, r: Share['role'] | null) => {
    setBusy(true)
    const res = await shareDashboardAction({ dashboard, kind, grantee, role: r })
    setBusy(false)
    if (!res.ok) { flash(te(res.code)); return false }
    router.refresh()
    return true
  }
  const taken = new Set(shares.map((s) => `${s.kind}:${s.id}`))
  const add = async () => {
    const [kind, id] = pick.split(':') as [Share['kind'], string]
    if (!kind || !id) return
    if (await apply(kind, id, role)) setPick('')
  }

  return (
    <div className="absolute left-0 top-10 z-30 flex w-[330px] max-w-[calc(100vw-32px)] flex-col gap-2 rounded-18 border border-line bg-surface p-[14px] shadow-pop">
      {shares.length === 0 ? <span className="text-12.5 text-muted">{t('none')}</span> : null}
      {shares.map((s) => (
        <div key={`${s.kind}:${s.id}`} className="flex items-center justify-between gap-2 text-12.5">
          <b className="min-w-0 truncate">{s.name ?? '—'}</b>
          <select aria-label={t('roleOf', { name: s.name ?? '' })} value={s.role} disabled={busy}
            onChange={(e) => void apply(s.kind, s.id, e.target.value === 'remove' ? null : (e.target.value as Share['role']))} className={sel}>
            <option value="viewer">{t('viewer')}</option>
            <option value="editor">{t('editor')}</option>
            <option value="remove">{t('remove')}</option>
          </select>
        </div>
      ))}
      <div className="flex items-center gap-[6px]">
        <select aria-label={t('pick')} value={pick} onChange={(e) => setPick(e.target.value)} className={`${sel} min-w-0 flex-1`}>
          <option value="">{t('pick')}</option>
          <optgroup label={t('people')}>
            {pickers.staff.filter((x) => x.id !== meId && !taken.has(`staff:${x.id}`)).map((x) => <option key={x.id} value={`staff:${x.id}`}>{x.name}</option>)}
          </optgroup>
          <optgroup label={t('teams')}>
            {pickers.teams.filter((x) => !taken.has(`team:${x.id}`)).map((x) => <option key={x.id} value={`team:${x.id}`}>{x.name}</option>)}
          </optgroup>
          <optgroup label={t('groups')}>
            {pickers.groups.filter((x) => !taken.has(`group:${x.id}`)).map((x) => <option key={x.id} value={`group:${x.id}`}>{x.name}</option>)}
          </optgroup>
        </select>
        <select aria-label={t('role')} value={role} onChange={(e) => setRole(e.target.value as 'viewer' | 'editor')} className={sel}>
          <option value="viewer">{t('viewer')}</option>
          <option value="editor">{t('editor')}</option>
        </select>
        <button type="button" onClick={add} disabled={!pick || busy} className="h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold disabled:cursor-default disabled:opacity-55">{t('add')}</button>
      </div>
      <div className="flex flex-col gap-[6px] border-t border-line pt-2">
        <b className="text-12.5">{t('publicLink')}</b>
        <span className="text-11.5 text-muted">{t('publicWaits')}</span>
        <span className="flex gap-[6px]">
          <button type="button" disabled title={t('publicWaits')} className="h-7 cursor-default rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold opacity-55">{t('createLink')}</button>
        </span>
      </div>
    </div>
  )
}
