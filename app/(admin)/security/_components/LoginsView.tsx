'use client'

import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Login, StaffOpt } from '@/lib/data/security'
import { revokeAll } from '../actions'
import { place, sx, useClock, useGuarded, useWhen } from './kit'

const COLS = '[grid-template-columns:130px_minmax(0,1.2fr)_minmax(0,1fr)_120px_110px_110px]'

/**
 * Device and login history (SEC-04): one staff member's sign-ins over the last 60 days from login_history, which opens
 * the sealed IP for this purpose (global:security, or oneself) and audits the read. Session end comes from the session
 * row; a refused sign-in says why.
 */
export function LoginsView({ staff, selected, logins, now, meId }: { staff: StaffOpt[]; selected: string; logins: Login[] | null; now: string; meId: string }) {
  const t = useTranslations('security.logins')
  const router = useRouter()
  const flash = useToast()
  const when = useWhen(now)
  const clock = useClock()
  const { run, busy, dialog } = useGuarded()
  const person = staff.find((s) => s.id === selected)

  const endText = (l: Login): { text: string; tone: string } => {
    if (l.outcome !== 'success') return { text: t(`outcome.${l.outcome}`), tone: 'text-danger' }
    if (l.active) return { text: t('active'), tone: 'text-link' }
    if (!l.end_reason) return { text: '—', tone: 'text-muted' }
    const at = l.ended_at ? clock(l.ended_at) : ''
    return { text: t(`end.${l.end_reason}`, { time: at }), tone: 'text-muted' }
  }

  const logoutAll = async () => {
    const r = await run((reason) => revokeAll({ staff: selected, reason }))
    if (r.ok) flash(selected === meId ? t('loggedOutSelf', { n: r.ended }) : t('loggedOutAll', { name: person?.name ?? '', n: r.ended }))
  }

  return (
    <div className="flex flex-col gap-[10px]">
      {dialog}
      <div className="flex flex-wrap items-center gap-2">
        <select
          aria-label={t('staffLabel')}
          value={selected}
          onChange={(e) => router.push(`/security?tab=logins&staff=${e.target.value}` as Route)}
          className="h-9 rounded-10 border border-solid border-ink bg-surface px-[10px] text-13 font-bold text-ink"
        >
          {staff.map((s) => <option key={s.id} value={s.id}>{s.name}{s.active ? '' : ` · ${t('inactive')}`}</option>)}
        </select>
        <span className="text-12 text-muted">{t('sub')}</span>
        <span className="flex-1" />
        <button type="button" disabled={busy} onClick={logoutAll}
          className="h-[34px] cursor-pointer rounded-10 border border-solid border-coral bg-transparent px-[13px] text-12.5 font-semibold text-rust disabled:cursor-default disabled:opacity-60">
          {t('logoutAll')}
        </button>
      </div>
      <section className={sx.card} aria-label={t('title', { name: person?.name ?? '' })}>
        <div className="overflow-x-auto">
          <div className={`${sx.row} grid min-w-[720px] gap-[10px] py-[9px] ${sx.colHead} ${COLS}`}>
            <span>{t('cols.login')}</span><span>{t('cols.device')}</span><span>{t('cols.location')}</span><span>{t('cols.ip')}</span><span>{t('cols.method')}</span><span>{t('cols.end')}</span>
          </div>
          {logins === null ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('failed')}</div>
          ) : logins.length === 0 ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('empty', { name: person?.name ?? '' })}</div>
          ) : (
            logins.map((l, i) => {
              const end = endText(l)
              return (
                <div key={`${l.at}-${i}`} className={`${sx.row} grid min-w-[720px] gap-[10px] py-[9px] text-12.5 ${COLS} ${l.new_device ? 'bg-cream' : ''}`}>
                  <span>{when(l.at)}</span>
                  <b>{(l.device ?? t('unknownDevice')) + (l.new_device ? ` · ${t('new')}` : '')}</b>
                  <span>{(place(l.city, l.country) || '—') + (l.new_location ? ` · ${t('new')}` : '')}</span>
                  <span className="[font-family:ui-monospace,Menlo,monospace] text-11.5">{l.ip ?? '—'}</span>
                  <span className="text-muted">{l.method ? t(`method.${l.method}`) : '—'}</span>
                  <span className={end.tone}>{end.text}</span>
                </div>
              )
            })
          )}
        </div>
      </section>
    </div>
  )
}
