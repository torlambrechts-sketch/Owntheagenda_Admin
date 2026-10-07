'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Mfa, Review, Sso, StaffOpt } from '@/lib/data/security'
import { mfaReminder, mfaReset, reviewComplete, reviewDecide, reviewStart, ssoSet } from '../actions'
import { RecoveryCodes } from './RecoveryCodes'
import { Modal, Toggle, dialogCancel, dialogDanger, sx, useGuarded, useWhen } from './kit'

/**
 * SSO and two-factor (SEC-05, SEC-06; D-11, D-31). Google and Microsoft are the only providers (no SAML, no Okta) and
 * neither is configured in the Auth project, so both say «Not connected». Two-factor is the fixed `mfa` key: TOTP only,
 * no email code. Below the design's two cards: one's own recovery codes, the owner's reset, and the access review.
 */
export function SigninView({ sso, mfa, review, staff, now, isOwner, meId }: { sso: Sso | null; mfa: Mfa | null; review: Review | null; staff: StaffOpt[]; now: string; isOwner: boolean; meId: string }) {
  const t = useTranslations('security.signin')
  const when = useWhen(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()

  const reviewNote = !sso ? null
    : sso.access_review_open ? t('reviewOpen')
    : sso.access_review_due ? t('reviewDue', { date: when(sso.access_review_due, { time: false }) })
    : t('reviewNever')

  return (
    <div className="flex flex-col gap-[14px]">
      {dialog}
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
        <section className={sx.cardPad} aria-label={t('ssoTitle')}>
          <b className="text-14">{t('ssoTitle')}</b>
          {sso ? sso.providers.map((p) => {
            const on = p.state === 'on'
            const d = !p.configured ? t('notConfigured')
              : p.allowed_domains.length ? t('allowedFor', { domains: p.allowed_domains.map((x) => '@' + x).join(', ') }) : t('anyDomain')
            return (
              <div key={p.provider} className={`flex items-center justify-between gap-[10px] rounded-13 border border-solid px-3 py-[10px] ${on ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}>
                <span className="flex flex-col">
                  <b className="text-13">{t(`providers.${p.provider}`)}</b>
                  <span className="text-11.5 text-muted">{d}{p.configured ? ` · ${t('users', { n: p.users })}` : ''}</span>
                </span>
                <span className="flex items-center gap-2">
                  <span className={`text-11.5 font-bold ${on ? 'text-link' : 'text-muted'}`}>{t(`state.${p.state}`)}</span>
                  {p.configured ? (
                    <Toggle on={p.enabled} label={t(`providers.${p.provider}`)} disabled={busy}
                      onChange={async (v) => { const r = await run(() => ssoSet({ provider: p.provider, enabled: v })); if (r.ok) flash(t('saved')) }} />
                  ) : null}
                </span>
              </div>
            )
          }) : <span className="text-12.5 text-muted">{t('loadFailed')}</span>}
          <div className="text-11.5 text-muted">{[t('separate'), reviewNote].filter(Boolean).join(' · ')}</div>
        </section>

        <section className={sx.cardPad} aria-label={t('mfaTitle')}>
          <div className="flex items-center justify-between">
            <b className="text-14">{t('mfaTitle')}</b>
            {mfa?.enforced ? <span className="rounded-999 bg-ok-bg px-[10px] py-[3px] text-11 font-bold text-ok-ink">{t('enforced')}</span> : null}
          </div>
          {mfa ? (
            <>
              <MfaRow n={t('authenticator')} v={t('usersN', { n: mfa.authenticator })} />
              <MfaRow
                n={t('notEnrolled')}
                v={mfa.not_enrolled.length ? t('notEnrolledV', { n: mfa.not_enrolled.length, names: mfa.not_enrolled.map((x) => x.name).join(', ') }) : t('none')}
                tone={mfa.not_enrolled.length ? 'text-danger' : 'text-ink'}
                action={mfa.not_enrolled.length ? (
                  <button type="button" className={sx.btn} disabled={busy} onClick={async () => {
                    const r = await run(() => mfaReminder({ staff: mfa.not_enrolled.map((x) => x.id) }))
                    if (r.ok) flash(t(r.email === 'queued' ? 'reminderQueued' : 'reminderInApp'))
                  }}>{t('sendReminder')}</button>
                ) : null}
              />
              <MfaRow n={t('recovery')} v={t('ofN', { n: mfa.recovery_codes, total: mfa.active })} />
            </>
          ) : <span className="text-12.5 text-muted">{t('loadFailed')}</span>}
          <div className="text-11.5 text-muted">{t('footnote')}</div>
        </section>
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
        <RecoveryCodes />
        {isOwner ? <OwnerReset staff={staff.filter((s) => s.active && !s.is_sample && s.id !== meId)} /> : null}
      </div>

      <AccessReview review={review} now={now} />
    </div>
  )
}

function MfaRow({ n, v, tone = 'text-ink', action }: { n: string; v: string; tone?: string; action?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-[10px] border-0 border-b border-solid border-line py-[6px] text-12.5">
      <span>{n}</span>
      <span className="flex items-center gap-2 text-right"><b className={tone}>{v}</b>{action}</span>
    </div>
  )
}

/** The owner resets another person's second factor (D-11): factors, codes and sessions go; a fresh factor and a reason. */
function OwnerReset({ staff }: { staff: StaffOpt[] }) {
  const t = useTranslations('security.signin.reset')
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [who, setWho] = useState('')
  const [ask, setAsk] = useState(false)
  const person = staff.find((s) => s.id === who)
  return (
    <section className={sx.cardPad} aria-label={t('title')}>
      {dialog}
      <b className="text-14">{t('title')}</b>
      <span className="text-12 text-muted">{t('body')}</span>
      <div className="flex flex-wrap items-center gap-2">
        <select aria-label={t('staff')} className={`${sx.inputSm} min-w-[180px]`} value={who} onChange={(e) => setWho(e.target.value)}>
          <option value="">{t('pick')}</option>
          {staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
        <button type="button" className={sx.btnDanger30} disabled={busy || !person} onClick={() => setAsk(true)}>{t('reset')}</button>
      </div>
      {ask && person ? (
        <Modal eyebrow={t('eyebrow')} title={t('confirmTitle', { name: person.name })} onClose={() => setAsk(false)}>
          <p className="m-0 text-13 leading-[1.5] text-muted">{t('confirmBody', { name: person.name })}</p>
          <div className="flex justify-end gap-2">
            <button type="button" className={dialogCancel} onClick={() => setAsk(false)}>{t('cancel')}</button>
            <button type="button" className={dialogDanger} disabled={busy} onClick={async () => {
              setAsk(false)
              const r = await run((reason) => mfaReset({ staff: person.id, reason }))
              if (r.ok) { flash(t('done', { name: person.name, n: r.removed })); setWho('') }
            }}>{t('reset')}</button>
          </div>
        </Modal>
      ) : null}
    </section>
  )
}

/** The access review (Appendix 2): start it, decide keep / change / deactivate per person, complete it. */
function AccessReview({ review, now }: { review: Review | null; now: string }) {
  const t = useTranslations('security.signin.review')
  const when = useWhen(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const open = review?.review && !review.review.completed_at ? review.review : null
  const items = open ? review?.items ?? [] : []
  const undecided = items.filter((i) => !i.decision).length
  return (
    <section id="review" className={sx.card} aria-label={t('title')}>
      {dialog}
      <div className={`${sx.head} flex-wrap items-center`}>
        <b className="text-14">{t('title')}</b>
        <span className="flex items-center gap-2 text-12 text-muted">
          {review === null ? t('loadFailed')
            : open ? t('openSince', { date: when(open.started_at, { time: false }), n: undecided })
            : review.next_due ? t('nextDue', { date: when(review.next_due, { time: false }), interval: t(`interval.${review.interval}`) })
            : t('never', { interval: t(`interval.${review.interval}`) })}
          {review && !open ? (
            <button type="button" className={sx.btn} disabled={busy} onClick={async () => { const r = await run(() => reviewStart()); if (r.ok) flash(t('started')) }}>{t('start')}</button>
          ) : null}
          {open ? (
            <button type="button" className={sx.btn} disabled={busy || undecided > 0} onClick={async () => { const r = await run(() => reviewComplete({ review: open.id })); if (r.ok) flash(t('completed')) }}>{t('complete')}</button>
          ) : null}
        </span>
      </div>
      {open ? (
        <div className="overflow-x-auto">
          <div className={`${sx.row} grid min-w-[560px] gap-[10px] py-[9px] ${sx.colHead} [grid-template-columns:minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)_150px]`}>
            <span>{t('cols.name')}</span><span>{t('cols.set')}</span><span>{t('cols.group')}</span><span>{t('cols.decision')}</span>
          </div>
          {items.map((i) => (
            <div key={i.staff_id} className={`${sx.row} grid min-w-[560px] items-center gap-[10px] py-[8px] text-12.5 [grid-template-columns:minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)_150px]`}>
              <b>{i.name}</b>
              <span className="text-muted">{i.permission_set ?? '—'}</span>
              <span className="text-muted">{i.group ?? '—'}</span>
              <select aria-label={t('decisionFor', { name: i.name })} className={sx.select} value={i.decision ?? ''} disabled={busy}
                onChange={async (e) => { if (e.target.value) await run(() => reviewDecide({ review: open.id, staff: i.staff_id, decision: e.target.value })) }}>
                <option value="" disabled>{t('undecided')}</option>
                <option value="keep">{t('decision.keep')}</option>
                <option value="change">{t('decision.change')}</option>
                <option value="deactivate">{t('decision.deactivate')}</option>
              </select>
            </div>
          ))}
          <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('footnote')}</div>
        </div>
      ) : null}
    </section>
  )
}
