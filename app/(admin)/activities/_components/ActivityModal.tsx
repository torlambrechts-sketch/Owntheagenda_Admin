'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import type { Channel, Guest } from '@/lib/data/activities'
import { addDays, fromZoned, parseYmd, ymd, zoned } from '@/lib/data/activities-time'
import { useToast } from '@/components/ui/Toast'
import { saveActivity } from '../actions'
import type { ModalData } from './ActivitiesScreen'
import { PRIORITIES, canEdit, chip, type Ctx } from './shared'

const CHANNELS: Channel[] = ['app', 'email', 'desktop', 'push']
const DURATIONS = [15, 30, 45, 60, 90, 120]
const VIDEO = ['meet', 'teams', 'zoom'] as const
type Video = (typeof VIDEO)[number] | null
const RSVP = { accepted: 'text-link', tentative: 'text-warn-ink', declined: 'text-danger', needs_action: 'text-muted' } as const

const field = 'h-9 rounded-9 border border-line bg-canvas text-12.5'
const label = 'flex flex-col gap-1 text-11.5 text-muted'
const pad = (n: number) => String(n).padStart(2, '0')

/** The edit and new dialog (Activities.dc.html, edit). Guests and reminders are saved with the activity. */
export function ActivityModal({ ctx, data, onClose }: { ctx: Ctx; data: ModalData; onClose: () => void }) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const flash = useToast()
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const a = data.detail
  const editable = a ? canEdit(ctx, a) : ctx.rights.add
  const types = ctx.types.filter((x) => x.active || x.id === a?.type_id)

  const start = a?.starts_at ? zoned(new Date(a.starts_at), ctx.tz) : null
  const tomorrow = addDays(parseYmd(ctx.today)!, 1)
  const [typeId, setTypeId] = useState(a?.type_id ?? (types.find((x) => x.key === 'meeting') ?? types[0])?.id ?? '')
  const [subject, setSubject] = useState(a?.subject ?? '')
  const [date, setDate] = useState(a ? (start ? ymd(start) : '') : ymd(tomorrow))
  const [time, setTime] = useState(a ? (start && !a.all_day ? `${pad(start.h)}:${pad(start.min)}` : '') : '10:00')
  const [duration, setDuration] = useState(a?.duration_min ?? 30)
  const [priority, setPriority] = useState(a?.priority ?? 'medium')
  const [dealId, setDealId] = useState(a?.deal_id ?? '')
  const [ownerId, setOwnerId] = useState(a ? (a.owner_id ?? '') : ctx.me.id)
  const [guests, setGuests] = useState<Guest[]>(a?.guest_list ?? [])
  const [guestInput, setGuestInput] = useState('')
  const [video, setVideo] = useState<Video>(a?.video_provider ?? null)
  const [videoUrl, setVideoUrl] = useState(a?.video_url ?? '')
  const [remind, setRemind] = useState<Channel[]>(a ? [...new Set(a.reminders.map((r) => r.channel))] : data.prefs.channels)
  const [custom, setCustom] = useState<Record<string, string>>(
    Object.fromEntries(Object.entries(a?.custom ?? {}).filter(([, v]) => typeof v === 'string') as [string, string][]),
  )
  const [note, setNote] = useState(a?.note ?? '')

  const box = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  useEffect(() => {
    const back = document.activeElement as HTMLElement | null
    box.current?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close.current() }
    window.addEventListener('keydown', onKey)
    return () => { window.removeEventListener('keydown', onKey); back?.focus?.() }
  }, [])

  // deals on offer: the open ones, and the linked one even when it is closed
  const deals = a?.deal && !data.deals.some((d) => d.id === a.deal!.id)
    ? [{ id: a.deal.id, title: a.deal.title, organization_id: a.organization_id, person_id: a.person_id }, ...data.deals]
    : data.deals
  const owners = ownerId && !ctx.staff.some((s) => s.id === ownerId) && a?.owner ? [{ id: ownerId, name: a.owner.name ?? '—' }, ...ctx.staff] : ctx.staff
  const durations = DURATIONS.includes(duration) ? DURATIONS : [...DURATIONS, duration].sort((x, y) => x - y)
  const fields = data.fields.filter((f) => f.type !== 'formula' && (!f.activity_type_ids || f.activity_type_ids.includes(typeId)) &&
    ['single_option', 'text', 'large_text', 'phone'].includes(f.type))
  const providerName = (v: NonNullable<Video>) => t(`modal.video.${v}`)

  const addGuest = () => {
    const raw = guestInput.trim()
    if (!raw) return
    const person = data.people.find((p) => p.email && (p.email.toLowerCase() === raw.toLowerCase() || p.name.toLowerCase() === raw.toLowerCase()))
    const email = (person?.email ?? raw).toLowerCase()
    if (!/^[^@\s]+@[^@\s]+$/.test(email)) { setError(t('modal.guestInvalid')); return }
    if (!guests.some((g) => g.email === email)) setGuests([...guests, { email, name: person?.name ?? null, person_id: person?.id ?? null, response: 'needs_action' }])
    setGuestInput('')
    setError(null)
  }

  const save = () => {
    setError(null)
    if (!subject.trim()) { setError(t('modal.subjectRequired')); return }
    const day = parseYmd(date)
    const [hh, mm] = time.split(':').map(Number)
    const timed = day && time && Number.isFinite(hh) && Number.isFinite(mm)
    const startsAt = day ? fromZoned(day, timed ? hh! : 0, timed ? mm! : 0, ctx.tz).toISOString() : null
    const deal = deals.find((d) => d.id === dealId) ?? null
    const dealChanged = (a?.deal_id ?? '') !== dealId
    const offsetOf = (c: Channel) => a?.reminders.find((r) => r.channel === c)?.offset_min ?? data.prefs.default_offset
    const customOut: Record<string, string | null> = {}
    for (const f of fields) {
      if (f.readonly) continue
      const v = custom[f.key] ?? ''
      const before = typeof a?.custom[f.key] === 'string' ? (a.custom[f.key] as string) : ''
      if (v !== before) customOut[f.key] = v || null
    }
    startTransition(async () => {
      const r = await saveActivity({
        id: a?.id ?? null,
        version: a?.version ?? null,
        values: {
          type_id: typeId,
          subject: subject.trim(),
          starts_at: startsAt,
          all_day: !!day && !timed,
          duration_min: duration,
          priority,
          note: note.trim() ? note : null,
          deal_id: dealId || null,
          person_id: dealChanged && deal ? deal.person_id : (a?.person_id ?? null),
          organization_id: dealChanged && deal ? deal.organization_id : (a?.organization_id ?? null),
          video_provider: video,
          video_url: video && videoUrl.trim() ? videoUrl.trim() : null,
          owner_id: ownerId || null,
          custom: customOut,
        },
        guests: guests.map((g) => ({ email: g.email, name: g.name, person_id: g.person_id })),
        reminders: remind.map((c) => ({ channel: c, offset_min: offsetOf(c) })),
      })
      if (!r.ok && r.part) {
        // the activity is saved; its guests or reminders were refused (owner or deals:edit_others)
        flash(t(`toast.partRefused.${r.part}`, { reason: tc(`errors.${r.code}`) }))
        onClose()
        return
      }
      if (!r.ok) { setError(tc(`errors.${r.code}`)); return }
      flash(remind.length ? t('toast.savedReminders') : t('toast.saved'))
      onClose()
    })
  }

  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        ref={box}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-labelledby="activity-modal-title"
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[92vh] w-[620px] max-w-full flex-col gap-3 overflow-auto rounded-22 bg-surface px-6 py-[22px] shadow-modal outline-none"
      >
        <div className="flex justify-between">
          <b id="activity-modal-title" className="font-serif text-21">{a ? t('modal.edit') : t('modal.new')}</b>
          <button type="button" onClick={onClose} aria-label={tc('close')} className="h-[30px] w-[30px] cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
        </div>
        <fieldset disabled={!editable || pending} className="m-0 flex min-w-0 flex-col gap-3 border-none p-0">
          <div className="flex flex-wrap gap-[6px]">
            {types.map((x) => (
              <button key={x.id} type="button" aria-pressed={typeId === x.id} onClick={() => setTypeId(x.id)} className={`px-3 py-[6px] text-12.5 ${chip(typeId === x.id)}`}>
                {x.glyph} {x.name}
              </button>
            ))}
          </div>
          <input
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
            placeholder={t('modal.subject')}
            aria-label={t('modal.subject')}
            maxLength={200}
            className="h-[42px] rounded-10 border border-line bg-canvas px-3 text-14 font-semibold"
          />
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <label className={label}>{t('modal.date')}<input type="date" value={date} onChange={(e) => setDate(e.target.value)} className={`${field} px-2`} /></label>
            <label className={label}>{t('modal.time')}<input type="time" value={time} onChange={(e) => setTime(e.target.value)} className={`${field} px-2`} /></label>
            <label className={label}>{t('modal.duration')}
              <select value={duration} onChange={(e) => setDuration(Number(e.target.value))} className={field}>
                {durations.map((m) => <option key={m} value={m}>{t('calendar.minutes', { count: m })}</option>)}
              </select>
            </label>
            <label className={label}>{t('modal.priority')}
              <select value={priority} onChange={(e) => setPriority(e.target.value as typeof priority)} className={field}>
                {PRIORITIES.map((p) => <option key={p} value={p}>{t(`priority.${p}`)}</option>)}
              </select>
            </label>
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className={label}>{t('modal.deal')}
              <select value={dealId} onChange={(e) => setDealId(e.target.value)} className={field}>
                <option value="">—</option>
                {deals.map((d) => <option key={d.id} value={d.id}>{d.title}</option>)}
              </select>
            </label>
            <label className={label}>{t('modal.owner')}
              <select value={ownerId} onChange={(e) => setOwnerId(e.target.value)} className={field}>
                {ownerId === '' ? <option value="">—</option> : null}
                {owners.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </label>
          </div>
          <div className="flex flex-col gap-[6px] rounded-14 border border-line px-3 py-[10px]">
            <b className="text-12.5">{data.calendar?.status === 'connected' ? t('modal.guestsSynced') : t('modal.guestsNotSynced')}</b>
            {guests.length === 0 ? <span className="text-12.5 text-muted">{t('modal.noGuests')}</span> : null}
            {guests.map((g) => (
              <div key={g.email} className="flex items-center justify-between gap-2 text-12.5">
                <span className="min-w-0">{g.name ?? g.email}{g.name ? <span className="text-muted"> · {g.email}</span> : null}</span>
                <span className="flex items-center gap-2">
                  <span className={`font-bold ${RSVP[g.response]}`}>{t(`modal.rsvp.${g.response}`)}</span>
                  {editable ? (
                    <button type="button" aria-label={t('modal.removeGuest', { name: g.name ?? g.email })} onClick={() => setGuests(guests.filter((x) => x.email !== g.email))} className="cursor-pointer border-none bg-transparent p-0 text-13 text-muted">×</button>
                  ) : null}
                </span>
              </div>
            ))}
            {editable ? (
              <div className="flex gap-[6px]">
                <input
                  list="activity-guest-people"
                  value={guestInput}
                  onChange={(e) => setGuestInput(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addGuest() } }}
                  placeholder={t('modal.addGuest')}
                  aria-label={t('modal.addGuest')}
                  className="h-[30px] min-w-0 flex-1 rounded-9 border border-line bg-canvas px-[10px] text-12"
                />
                <datalist id="activity-guest-people">
                  {data.people.map((p) => <option key={p.id} value={p.email ?? ''}>{p.name}</option>)}
                </datalist>
                <button type="button" onClick={addGuest} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('modal.add')}</button>
              </div>
            ) : null}
          </div>
          <div className="flex flex-wrap items-center gap-2 rounded-14 border border-line px-3 py-[10px]">
            <b className="flex-1 text-12.5">{t('modal.videoLink')}</b>
            {VIDEO.map((v) => (
              <button key={v} type="button" aria-pressed={video === v} onClick={() => setVideo(v)} className={`px-[10px] py-[5px] text-12 ${chip(video === v)}`}>{providerName(v)}</button>
            ))}
            <button type="button" aria-pressed={video === null} onClick={() => setVideo(null)} className={`px-[10px] py-[5px] text-12 ${chip(video === null)}`}>{t('modal.video.none')}</button>
          </div>
          {video ? (
            <input
              value={videoUrl}
              onChange={(e) => setVideoUrl(e.target.value)}
              placeholder={t('modal.videoPaste', { provider: providerName(video) })}
              aria-label={t('modal.videoLink')}
              maxLength={500}
              className="h-6 border-none bg-transparent p-0 font-mono text-12 text-link"
            />
          ) : null}
          <div className="flex flex-wrap items-center gap-[6px]">
            <b className="mr-1 text-12.5">{t('modal.remindMe')}</b>
            {CHANNELS.map((c) => {
              const on = remind.includes(c)
              return (
                <button key={c} type="button" aria-pressed={on} onClick={() => setRemind(on ? remind.filter((x) => x !== c) : [...remind, c])} className={`px-[10px] py-[5px] text-12 ${chip(on)}`}>
                  {t(`modal.remind.${c}`)}
                </button>
              )
            })}
          </div>
          {fields.map((f) => (
            <label key={f.id} className={label}>
              {f.label}
              {f.type === 'single_option' ? (
                <select value={custom[f.key] ?? ''} disabled={f.readonly} onChange={(e) => setCustom({ ...custom, [f.key]: e.target.value })} className={field}>
                  <option value="">—</option>
                  {f.options.map((o) => <option key={o.key} value={o.key}>{o.label ?? o.name ?? o.key}</option>)}
                </select>
              ) : (
                <input value={custom[f.key] ?? ''} disabled={f.readonly} onChange={(e) => setCustom({ ...custom, [f.key]: e.target.value })} className={`${field} px-2`} />
              )}
            </label>
          ))}
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder={t('modal.note')}
            aria-label={t('modal.note')}
            maxLength={10000}
            className="min-h-[60px] rounded-11 border border-line bg-canvas px-[11px] py-[9px] text-13"
          />
        </fieldset>
        {error ? <div role="alert" className="text-12.5 font-semibold text-danger">{error}</div> : null}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{tc('cancel')}</button>
          {editable ? (
            <button type="button" disabled={pending} onClick={save} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">
              {t('modal.save')}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  )
}
