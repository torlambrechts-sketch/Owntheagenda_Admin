'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import type { Attendee, Capabilities, Detail } from '@/lib/data/meetings'
import { deleteRecording, recordObjection, removeBot, setCapture } from '../actions'
import { Modal, btn32, btnCancel, btnDanger, card18, quiet, useFail, useWhen, type Me } from './kit'

type Props = { detail: Detail; capabilities: Capabilities; onChanged: () => Promise<void>; me: Me }

/**
 * Recording and consent (§8.3, D-39; D-41 — the design draws no place for it): how this meeting is captured, what the
 * bot may do and why not, the recording notice, each guest's notice and objection, and the owner's controls (capture
 * choice, remove the bot, stop and delete the recording). Nothing here implies a recording can happen when it cannot.
 */
export function ConsentCard({ detail: d, capabilities, onChanged, me }: Props) {
  const t = useTranslations('meetings.consent')
  const f = useFormatter()
  const when = useWhen(me)
  const fail = useFail()
  const flash = useToast()
  const [busy, setBusy] = useState(false)
  const [objecting, setObjecting] = useState<Attendee | null>(null)
  const [deleting, setDeleting] = useState(false)
  const upcoming = !!d.starts_at && new Date(d.starts_at) > new Date() && !d.cancelled_at
  const botOn = capabilities.meeting_bot === 'connected'
  const rec = d.recording && d.recording.state !== 'deleted' ? d.recording : null

  const run = async (p: Promise<{ ok: true } | { ok: false; code: RpcCode; detail?: string | null }>, done: string) => {
    setBusy(true)
    const r = await p
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(done)
    await onChanged()
  }

  const botLine = () => {
    if (d.bot.state === 'blocked') return t('bot.blocked', { reason: t(`reason.${d.bot.reason ?? 'other'}`) })
    if (d.capture !== 'bot') return botOn ? t('bot.notChosen') : t('bot.notConnected')
    return t(`bot.${d.bot.state}`)
  }
  const noticeLine = () => {
    const setting = d.notice.setting === 'off' ? t('notice.settingOff') : d.notice.setting === 'custom' ? t('notice.settingCustom', { hours: d.notice.hours ?? 0 }) : t('notice.setting24')
    switch (d.notice.state) {
      case 'sent': return `${t('notice.sent', { at: when(d.notice.sent_at) })} · ${setting}`
      case 'pending': return `${t('notice.pending', { at: when(d.notice.due_at) })} · ${setting}`
      case 'blocked': return `${t('notice.blocked')} · ${setting}`
      default: return `${d.capture === 'bot' ? t('notice.notRequiredNoGuests') : t('notice.notRequired')} · ${setting}`
    }
  }

  const row = (k: string, v: React.ReactNode) => (
    <div className="grid gap-[10px] border-0 border-b border-solid border-line py-[7px] text-12.5 [grid-template-columns:130px_minmax(0,1fr)]">
      <span className="text-muted">{k}</span>
      <span className="leading-[1.5]">{v}</span>
    </div>
  )

  return (
    <div className={`${card18} flex flex-col gap-1 px-4 py-[14px]`}>
      <b className="text-13.5">{t('title')}</b>
      {row(t('capture'), (
        <span className="flex flex-col gap-[6px]">
          <span>{t(`captureValue.${d.capture}`)}</span>
          {upcoming && d.can_edit ? (
            <span className="flex flex-wrap items-center gap-[6px]">
              <button type="button" disabled={busy || d.capture === 'bot' || !botOn} onClick={() => void run(setCapture({ id: d.id, capture: 'bot' }), t('captureSet'))} className={btn32}>{t('useBot')}</button>
              <button type="button" disabled={busy || d.capture !== 'bot'} onClick={() => void run(setCapture({ id: d.id, capture: 'none' }), t('captureSet'))} className={btn32}>{t('noBot')}</button>
              {!botOn ? <span className="text-11.5 text-muted">{t('botNotConnected')}</span> : null}
            </span>
          ) : null}
        </span>
      ))}
      {row(t('botLabel'), (
        <span className="flex flex-wrap items-center gap-2">
          <span className={d.bot.state === 'blocked' ? 'text-danger' : ''}>{botLine()}</span>
          {d.can_edit && ['scheduled', 'joining', 'in_call'].includes(d.bot.state) ? (
            <button type="button" disabled={busy} onClick={() => void run(removeBot(d.id), t('botRemoved'))} className={btn32}>{t('removeBot')}</button>
          ) : null}
        </span>
      ))}
      {row(t('noticeLabel'), noticeLine())}
      {row(t('recordingLabel'), (
        <span className="flex flex-wrap items-center gap-2">
          <span>
            {rec ? t('recording.kept', { state: t(`recording.state.${rec.state}`), until: rec.purge_after ? f.dateTime(new Date(rec.purge_after), { day: 'numeric', month: 'short', year: 'numeric' }) : t('recording.forever') })
              : d.transcript?.source === 'upload' ? t('recording.upload') : t('recording.none')}
          </span>
          {d.can_edit && (rec || d.transcript) ? (
            <button type="button" disabled={busy} onClick={() => setDeleting(true)} className="h-8 cursor-pointer rounded-9 border border-coral bg-transparent px-[13px] text-12 font-semibold text-rust disabled:opacity-60">
              {rec ? t('deleteRecording') : t('deleteTranscript')}
            </button>
          ) : null}
        </span>
      ))}
      <div className="mt-2 text-11 font-bold uppercase tracking-eyebrow text-muted">{t('attendees')}</div>
      {d.attendee_list.map((a) => (
        <div key={a.email} className="flex flex-wrap items-center justify-between gap-2 border-0 border-b border-solid border-line py-[6px] text-12.5">
          <span className="flex min-w-0 flex-col">
            <b className="truncate">{a.name ?? a.email}</b>
            <span className="text-11.5 text-muted">
              {[a.external ? t('guest') : t('colleague'), t(`response.${a.response}`), a.external && a.notice_sent_at ? t('noticeSent', { at: when(a.notice_sent_at) }) : null].filter(Boolean).join(' · ')}
            </span>
          </span>
          {a.opted_out ? (
            <span className="rounded-999 bg-peach px-[9px] py-[2px] text-11 font-bold text-danger">{t('optedOut')}</span>
          ) : a.external && d.can_edit ? (
            <button type="button" onClick={() => setObjecting(a)} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[9px] text-11.5 font-semibold">{t('object')}</button>
          ) : null}
        </div>
      ))}
      {d.attendee_list.length === 0 ? <span className={quiet}>{t('noAttendees')}</span> : null}
      <span className="mt-1 text-11.5 leading-[1.5] text-muted">{t('rules')}</span>

      {objecting ? (
        <ObjectionModal attendee={objecting} onClose={() => setObjecting(null)} onSave={(always) => run(recordObjection({ id: d.id, email: objecting.email, always }), t('objectionSaved')).then(() => setObjecting(null))} busy={busy} />
      ) : null}
      {deleting ? (
        <DeleteModal hasRecording={!!rec} onClose={() => setDeleting(false)} busy={busy}
          onConfirm={(withTranscript) => run(deleteRecording({ id: d.id, withTranscript }), t('deleted')).then(() => setDeleting(false))} />
      ) : null}
    </div>
  )
}

function ObjectionModal({ attendee, onClose, onSave, busy }: { attendee: Attendee; onClose: () => void; onSave: (always: boolean) => void; busy: boolean }) {
  const t = useTranslations('meetings.consent.objection')
  const [always, setAlways] = useState(false)
  return (
    <Modal eyebrow={t('eyebrow')} title={attendee.name ?? attendee.email} onClose={onClose}>
      <p className="m-0 text-13 leading-[1.55] text-ink-2">{t('body')}</p>
      <label className="flex items-start gap-2 text-13">
        <input type="checkbox" checked={always} onChange={(e) => setAlways(e.target.checked)} className="mt-[2px] accent-ink" />
        <span>{t('always')}</span>
      </label>
      <p className="m-0 text-11.5 leading-[1.5] text-muted">{t('note')}</p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={busy} onClick={() => onSave(always)} className={btnDanger}>{t('save')}</button>
      </div>
    </Modal>
  )
}

function DeleteModal({ hasRecording, onClose, onConfirm, busy }: { hasRecording: boolean; onClose: () => void; onConfirm: (withTranscript: boolean) => void; busy: boolean }) {
  const t = useTranslations('meetings.consent.delete')
  const [withTranscript, setWithTranscript] = useState(!hasRecording)
  return (
    <Modal eyebrow={t('eyebrow')} title={hasRecording ? t('titleRecording') : t('titleTranscript')} onClose={onClose}>
      <p className="m-0 text-13 leading-[1.55] text-ink-2">{hasRecording ? t('bodyRecording') : t('bodyTranscript')}</p>
      {hasRecording ? (
        <label className="flex items-start gap-2 text-13">
          <input type="checkbox" checked={withTranscript} onChange={(e) => setWithTranscript(e.target.checked)} className="mt-[2px] accent-ink" />
          <span>{t('withTranscript')}</span>
        </label>
      ) : null}
      <p className="m-0 text-11.5 leading-[1.5] text-muted">{t('note')}</p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={busy} onClick={() => onConfirm(withTranscript)} className={btnDanger}>{t('confirm')}</button>
      </div>
    </Modal>
  )
}
