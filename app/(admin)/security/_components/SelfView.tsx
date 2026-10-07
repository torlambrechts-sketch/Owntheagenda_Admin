'use client'

import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { MySession } from '@/lib/data/security'
import { revokeAll, revokeSession } from '../actions'
import { RecoveryCodes } from './RecoveryCodes'
import { place, sx, useGuarded, useWhen } from './kit'

/**
 * The screen without global:security (D-41): the no-permission state, and what every staff member may do for
 * themselves — their own open sessions (my_sessions; their own IP, which the function opens for them) and their
 * recovery codes. The spec places these on the profile; no profile screen exists yet (V-SECURITY-03).
 */
export function SelfView({ sessions, meId, now }: { sessions: MySession[] | null; meId: string; now: string }) {
  const t = useTranslations('security.self')
  const when = useWhen(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const others = (sessions ?? []).filter((s) => !s.current)
  return (
    <div className="flex flex-col gap-[14px]">
      {dialog}
      <div className="rounded-20 border border-solid border-line bg-surface p-[26px]">
        <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccessTitle')}</h1>
        <p className="m-0 mt-2 text-13 text-muted">{t('noAccessBody')}</p>
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <section className={sx.card} aria-label={t('sessionsTitle')}>
          <div className={`${sx.head} items-center`}>
            <b className="text-14">{t('sessionsTitle')}</b>
            {others.length ? (
              <button type="button" className={`${sx.logout} px-[10px]`} disabled={busy} onClick={async () => {
                const r = await run((reason) => revokeAll({ staff: meId, reason }))
                if (r.ok) flash(t('endedOthers', { n: r.ended }))
              }}>{t('logoutOthers')}</button>
            ) : null}
          </div>
          {sessions === null ? <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('failed')}</div>
            : sessions.length === 0 ? <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('none')}</div>
            : sessions.map((s) => (
              <div key={s.session_id} className={`${sx.row} grid items-center gap-[10px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)_90px]`}>
                <span className="flex min-w-0 flex-col">
                  <b>{s.device ?? t('unknownDevice')}</b>
                  <span className="text-11.5 text-muted">{[place(s.city, s.country), s.ip].filter(Boolean).join(' · ') || '—'}</span>
                </span>
                <span className="text-muted">{t('since', { when: when(s.created_at) })}</span>
                {s.current ? <span className="text-center text-11.5 font-semibold text-muted">{t('thisSession')}</span> : (
                  <button type="button" className={sx.logout} disabled={busy} onClick={async () => {
                    const r = await run((reason) => revokeSession({ session: s.session_id, reason }))
                    if (r.ok) flash(t('ended'))
                  }}>{t('logout')}</button>
                )}
              </div>
            ))}
        </section>
        <RecoveryCodes />
      </div>
    </div>
  )
}
