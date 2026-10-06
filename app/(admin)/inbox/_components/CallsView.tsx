'use client'

import { useEffect, useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Calls, PhoneMatch } from '@/lib/data/inbox'
import { logCall, phoneMatch } from '../actions'
import { useFail, useWhen } from './lib'

const ROW = 'grid min-w-[600px] items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 [grid-template-columns:24px_minmax(0,1.4fr)_110px_70px_120px_110px]'
const OUTCOMES = ['connected', 'no_answer', 'missed', 'busy', 'voicemail'] as const
const field = 'h-[30px] rounded-9 border border-line bg-surface px-2 text-12'

/**
 * Calls (v.calls, COM-10). No telephony provider is chosen: the log is what was logged by hand
 * (call_log_get), the call itself goes through the device's calling app (a tel: link), and the outcome is
 * written afterwards as a done call activity (call_log_save). «Matched» comes from phone_match.
 */
export function CallsView({ calls, now }: { calls: Calls; now: string }) {
  const t = useTranslations('inbox.calls')
  const flash = useToast()
  const { fail } = useFail()
  const when = useWhen(now)
  const [busy, start] = useTransition()
  const [number, setNumber] = useState('')
  const [match, setMatch] = useState<PhoneMatch | null>(null)
  const [logging, setLogging] = useState(false)
  const [direction, setDirection] = useState<'outbound' | 'inbound'>('outbound')
  const [outcome, setOutcome] = useState<(typeof OUTCOMES)[number]>('connected')
  const [minutes, setMinutes] = useState('')
  const [note, setNote] = useState('')

  const digits = number.replace(/\D/g, '')
  useEffect(() => {
    if (digits.length < 6) { setMatch(null); return }
    const h = setTimeout(async () => {
      const r = await phoneMatch({ number })
      setMatch(r.ok ? r.matches : null)
    }, 300)
    return () => clearTimeout(h)
  }, [digits, number])
  const hit = match?.[0] ?? null
  const tel = number.replace(/[^\d+]/g, '')

  const save = () => start(async () => {
    const m = minutes.trim() === '' ? null : Number(minutes)
    if (m !== null && (!Number.isInteger(m) || m < 0)) return fail('invalid')
    const r = await logCall({ personId: hit?.person_id ?? null, dealId: hit?.deal_id ?? null, number: number.trim(), direction, outcome, minutes: m, note })
    if (!r.ok) return fail(r.code, r.detail)
    flash(t('logged'))
    setLogging(false); setMinutes(''); setNote(''); setNumber('')
  })

  const dur = (s: number | null) => (s === null || s === 0 ? '—' : t('minutes', { n: Math.max(1, Math.round(s / 60)) }))

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:minmax(0,1fr)] lg:[grid-template-columns:minmax(0,1fr)_300px]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('title')}</div>
        <div className="overflow-x-auto">
          {calls.calls.map((c) => (
            <div key={c.activity_id} className={ROW}>
              <span className={`font-bold ${c.direction === 'inbound' ? 'text-link' : 'text-muted'}`} aria-label={t(`dir.${c.direction}`)}>{c.direction === 'inbound' ? '↙' : '↗'}</span>
              <span className="flex min-w-0 flex-col"><b>{c.person ?? t('unknown')}</b><span className="text-11.5 text-muted">{[c.organization, c.number ?? '—'].filter(Boolean).join(' · ')}</span></span>
              <span>{t(`outcome.${c.outcome}`)}</span>
              <span>{dur(c.duration_s)}</span>
              <span className="text-muted">{when.long(c.at)}</span>
              <span />
            </div>
          ))}
        </div>
        {calls.calls.length === 0 ? <div className="p-[30px] text-center text-13 text-muted">{t('empty')}</div> : null}
      </div>
      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('clickToCall')}</b>
          <input
            value={number}
            onChange={(e) => setNumber(e.target.value)}
            inputMode="tel"
            placeholder={t('numberPlaceholder')}
            aria-label={t('number')}
            className="h-10 rounded-10 border border-line bg-canvas px-3 text-15 font-semibold tracking-[.02em]"
          />
          {match ? (
            <div className="text-12 text-muted">
              {hit
                ? <>{t('matched')} <b className="text-ink">{hit.name}</b>{hit.organization ? ` · ${hit.organization}` : ''}{hit.deal_id ? ` · ${t('openDeal')}` : ''}</>
                : t('noMatch')}
            </div>
          ) : null}
          {tel.replace('+', '').length >= 3 ? (
            <a
              href={`tel:${tel}`}
              onClick={() => { setDirection('outbound'); setLogging(true) }}
              className="flex h-10 items-center justify-center rounded-11 border border-ink bg-primary text-13 font-bold text-ink hover:text-ink hover:no-underline"
            >
              {t('call')}
            </a>
          ) : (
            <button type="button" disabled className="h-10 cursor-default rounded-11 border border-ink bg-primary text-13 font-bold opacity-50">{t('call')}</button>
          )}
          <div className="text-11.5 text-faint">{t('noProvider')}</div>
          {!logging ? (
            <button type="button" onClick={() => setLogging(true)} className="h-[30px] cursor-pointer self-start rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('logManually')}</button>
          ) : (
            <div className="flex flex-col gap-2 border-t border-line pt-[10px] text-12">
              <b className="text-12.5">{t('logTitle')}</b>
              <div className="flex flex-wrap gap-[6px]">
                <select aria-label={t('direction')} value={direction} onChange={(e) => setDirection(e.target.value as 'outbound' | 'inbound')} className={field}>
                  <option value="outbound">{t('dir.outbound')}</option>
                  <option value="inbound">{t('dir.inbound')}</option>
                </select>
                <select aria-label={t('outcomeLabel')} value={outcome} onChange={(e) => setOutcome(e.target.value as (typeof OUTCOMES)[number])} className={field}>
                  {OUTCOMES.map((o) => <option key={o} value={o}>{t(`outcome.${o}`)}</option>)}
                </select>
                <input aria-label={t('durationLabel')} placeholder={t('durationLabel')} inputMode="numeric" value={minutes} onChange={(e) => setMinutes(e.target.value)} className={`${field} w-[90px]`} />
              </div>
              <textarea aria-label={t('note')} placeholder={t('note')} value={note} onChange={(e) => setNote(e.target.value)} className="min-h-[60px] rounded-9 border border-line bg-canvas px-2 py-[6px] text-12" />
              <div className="flex gap-[6px]">
                <button type="button" disabled={busy} onClick={save} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold">{t('save')}</button>
                <button type="button" onClick={() => setLogging(false)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('cancel')}</button>
              </div>
              <span className="text-11.5 text-faint">{hit ? t('willLink', { name: hit.name }) : t('willLinkNone')}</span>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
