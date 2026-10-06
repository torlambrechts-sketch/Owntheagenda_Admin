'use client'

import { Fragment, useState, useTransition } from 'react'
import { useTimeZone, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { fromZoned } from '@/lib/data/activities-time'
import type { Outbox } from '@/lib/data/inbox'
import { changeEmail } from '../actions'
import { useFail, useWhen } from './lib'

const ROW = 'grid min-w-[560px] items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-12.5 [grid-template-columns:minmax(0,1.5fr)_150px_minmax(0,1.2fr)_180px]'
const TONE: Record<string, string> = { failed: 'text-danger', scheduled: 'text-warn-ink', queued: 'text-warn-ink', sending: 'text-warn-ink', awaiting_review: 'text-warn-ink' }

/**
 * Scheduled and failed (v.outbox): my messages that are not sent yet and my group sends in progress
 * (outbox_get). Retry re-queues a failed message; Edit reschedules, sends now or cancels one that has not
 * been picked up (COM-08). Nothing is retried or corrected unless the database says so.
 */
export function OutboxView({ outbox, now }: { outbox: Outbox; now: string }) {
  const t = useTranslations('inbox')
  const flash = useToast()
  const { fail } = useFail()
  const when = useWhen(now)
  const tz = useTimeZone() ?? 'Europe/Oslo'
  const [busy, start] = useTransition()
  const [edit, setEdit] = useState<string | null>(null)
  const [at, setAt] = useState('')
  const names = (xs: { address: string; name: string | null }[]) => xs.map((x) => x.name || x.address).join(', ')

  const act = (id: string, action: 'cancel' | 'reschedule' | 'send_now' | 'retry') => start(async () => {
    let iso: string | null = null
    if (action === 'reschedule') {
      const m = at.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/)
      if (!m) return fail('invalid')
      iso = fromZoned({ y: +m[1]!, m: +m[2]!, d: +m[3]! }, +m[4]!, +m[5]!, tz).toISOString()
    }
    const r = await changeEmail({ id, action, at: iso })
    if (!r.ok) return fail(r.code, r.detail)
    setEdit(null)
    flash(t(`outbox.done.${action}`))
  })

  const empty = outbox.messages.length === 0 && outbox.groups.length === 0
  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('folders.outbox')}</div>
      <div className="overflow-x-auto">
        {outbox.messages.map((o) => (
          <Fragment key={o.id}>
            <div className={ROW}>
              <span className="flex min-w-0 flex-col"><b>{o.subject || t('noSubject')}</b><span className="text-11.5 text-muted">{t('outbox.to', { to: names(o.to) })}</span></span>
              <span className={`font-bold ${TONE[o.state] ?? 'text-muted'}`}>
                {o.state === 'scheduled' ? t('outbox.state.scheduledAt', { when: when.long(o.scheduled_at) }) : t(`outbox.state.${o.state}`)}
              </span>
              <span className="text-muted">{o.failure_reason ?? o.failure_code ?? (o.attempt > 0 ? t('outbox.attempt', { n: o.attempt + 1 }) : '')}</span>
              <span className="flex justify-end gap-[6px]">
                {o.state === 'failed' ? (
                  <button type="button" disabled={busy} onClick={() => act(o.id, 'retry')} className="h-7 cursor-pointer rounded-9 border border-ink bg-primary px-[10px] text-12 font-bold">{t('outbox.retry')}</button>
                ) : null}
                {o.state !== 'sending' ? (
                  <button type="button" aria-expanded={edit === o.id} onClick={() => { setEdit(edit === o.id ? null : o.id); setAt('') }} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('outbox.edit')}</button>
                ) : null}
              </span>
            </div>
            {edit === o.id ? (
              <div className="flex min-w-[560px] flex-wrap items-center gap-2 border-b border-line bg-canvas px-[18px] py-[10px] text-12">
                {o.state === 'scheduled' || o.state === 'awaiting_review' ? (
                  <>
                    <label className="flex items-center gap-[6px] text-muted">
                      {t('outbox.newTime')}
                      <input type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12 text-ink" />
                    </label>
                    <button type="button" disabled={busy || !at} onClick={() => act(o.id, 'reschedule')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default">{t('outbox.reschedule')}</button>
                    <button type="button" disabled={busy} onClick={() => act(o.id, 'send_now')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('outbox.sendNow')}</button>
                  </>
                ) : null}
                <span className="flex-1" />
                <button type="button" disabled={busy} onClick={() => act(o.id, 'cancel')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold text-danger">{t('outbox.cancel')}</button>
              </div>
            ) : null}
          </Fragment>
        ))}
        {outbox.groups.map((g) => (
          <div key={g.id} className={ROW}>
            <span className="flex min-w-0 flex-col"><b>{t('outbox.groupSubject', { subject: g.subject, n: g.total })}</b><span className="text-11.5 text-muted">{t('outbox.groupTo')}</span></span>
            <span className="font-bold text-warn-ink">{t('outbox.state.groupSending', { sent: g.sent, total: g.total })}</span>
            <span className="text-muted">{g.failed ? t('outbox.groupFailed', { n: g.failed }) : ''}</span>
            <span />
          </div>
        ))}
      </div>
      {empty ? <div className="p-[30px] text-center text-13 text-muted">{t('empty')}</div> : null}
    </div>
  )
}
