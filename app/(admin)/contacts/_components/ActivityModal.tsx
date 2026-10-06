'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { ActivityType } from '@/lib/data/contacts'
import { leadActivities } from '../actions'
import { dialog, fieldInput, fieldLabel, overlay, useError, useNav } from './util'

/** «＋ Activity for each»: one activity per selected lead, in the convert dialog's language (D-41). */
export function ActivityModal({ ids, types, tz, onClose }: { ids: string[]; types: ActivityType[]; tz: string; onClose: (done: boolean) => void }) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const { refresh } = useNav()
  const [type, setType] = useState(types[0]?.id ?? '')
  const [subject, setSubject] = useState('')
  const [date, setDate] = useState(() => new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(new Date(Date.now() + 86_400_000)))
  const [time, setTime] = useState('09:00')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(false) }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, [onClose])

  async function run() {
    // the chosen wall-clock time in the staff member's zone, as an instant
    const guess = new Date(`${date}T${time}:00Z`)
    const shown = new Date(guess.toLocaleString('en-US', { timeZone: tz }))
    const utc = new Date(guess.toLocaleString('en-US', { timeZone: 'UTC' }))
    const at = new Date(guess.getTime() - (shown.getTime() - utc.getTime()))
    setBusy(true)
    const r = await leadActivities({ ids, type_id: type, subject: subject.trim(), starts_at: at.toISOString() })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    flash(t('activity.done', { count: r.n }))
    onClose(true)
    refresh()
  }

  return (
    <div className={overlay} onClick={() => onClose(false)}>
      <div role="dialog" aria-modal="true" aria-labelledby="activity-title" className={dialog} onClick={(e) => e.stopPropagation()}>
        <div id="activity-title" className="font-serif text-21 font-semibold">{t('activity.title', { count: ids.length })}</div>
        <label className={fieldLabel}>
          {t('activity.type')}
          <select autoFocus value={type} onChange={(e) => setType(e.target.value)} className={fieldInput}>
            {types.map((x) => <option key={x.id} value={x.id}>{x.glyph} {x.name}</option>)}
          </select>
        </label>
        <label className={fieldLabel}>
          {t('activity.subject')}
          <input value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={200} className={fieldInput} />
        </label>
        <div className="flex gap-2">
          <label className={`${fieldLabel} flex-1`}>{t('activity.date')}<input type="date" value={date} onChange={(e) => setDate(e.target.value)} className={fieldInput} /></label>
          <label className={`${fieldLabel} w-[120px]`}>{t('activity.time')}<input type="time" value={time} onChange={(e) => setTime(e.target.value)} className={fieldInput} /></label>
        </div>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={() => onClose(false)} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
          <button type="button" disabled={busy || !type || !subject.trim() || !date} onClick={run} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:opacity-60">{t('activity.go')}</button>
        </div>
      </div>
    </div>
  )
}
