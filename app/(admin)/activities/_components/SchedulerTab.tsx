'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import type { BookingLink, Scheduling } from '@/lib/data/activities'
import { addDays, fromZoned, parseYmd, weekday, type Day } from '@/lib/data/activities-time'
import { useToast } from '@/components/ui/Toast'
import { createBookingLink, setAvailability } from '../actions'
import type { Ctx } from './shared'
import { useDates } from './dates'

const GRID_DAYS = [1, 2, 3, 4, 5]
const GRID_HOURS = [8, 9, 10, 11, 12, 13, 14, 15]
const PROVIDER = { meet: 'Google Meet', teams: 'Teams', zoom: 'Zoom' } as const
const key = (wd: number, h: number) => `${wd}:${h}`

/** Open slots for a link: only the hours marked available here, from now to the link's horizon. */
function slotsFor(link: BookingLink, avail: Set<string>, today: Day, now: Date, tz: string, max = 6): Date[] {
  const out: Date[] = []
  const step = 30
  for (let i = 0; i <= link.horizon_days && out.length < max; i++) {
    const day = addDays(today, i)
    const wd = weekday(day)
    for (let m = 0; m < 24 * 60 && out.length < max; m += step) {
      const end = m + link.duration_min
      if (end > 24 * 60) break
      let fits = true
      for (let h = Math.floor(m / 60); h * 60 < end; h++) if (!avail.has(key(wd, h))) { fits = false; break }
      if (!fits) continue
      const at = fromZoned(day, Math.floor(m / 60), m % 60, tz)
      if (at.getTime() > now.getTime()) out.push(at)
    }
  }
  return out
}

export function SchedulerTab({ ctx, scheduling }: { ctx: Ctx; scheduling: Scheduling }) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const format = useFormatter()
  const now = useNow()
  const dates = useDates(ctx.tz)
  const flash = useToast()
  const [pending, startTransition] = useTransition()
  const today = parseYmd(ctx.today)!
  const links = scheduling.links
  const [selected, setSelected] = useState(0)
  const [slot, setSlot] = useState<number | null>(null)
  const stored = useMemo(() => new Set(scheduling.availability.map((c) => key(c.weekday, c.hour))), [scheduling.availability])
  const [avail, setAvail] = useState(stored)
  useEffect(() => setAvail(stored), [stored])
  const [title, setTitle] = useState('')
  const [duration, setDuration] = useState(30)
  const [kind, setKind] = useState<'general' | 'proposed'>('general')
  const [proposed, setProposed] = useState<string[]>([])
  const [pDate, setPDate] = useState('')
  const [pTime, setPTime] = useState('10:00')
  const link = links[selected] ?? links[0] ?? null

  const toggle = (wd: number, h: number) => {
    const next = new Set(avail)
    if (next.has(key(wd, h))) next.delete(key(wd, h))
    else next.add(key(wd, h))
    setAvail(next)
    startTransition(async () => {
      const r = await setAvailability([...next].map((k) => { const [w, hh] = k.split(':').map(Number); return { weekday: w!, hour: hh! } }))
      if (!r.ok) { setAvail(avail); flash(tc(`errors.${r.code}`)) }
    })
  }
  const create = () => {
    startTransition(async () => {
      const r = await createBookingLink({ title, duration_min: duration, kind, proposed_times: kind === 'proposed' ? proposed : [] })
      if (!r.ok) { flash(r.detail === 'proposed_times' ? t('scheduler.proposedInvalid') : tc(`errors.${r.code}`)); return }
      setTitle('')
      setProposed([])
      flash(t('toast.linkCreated'))
    })
  }

  // a proposed-times link offers its stored times that are still ahead; a general one, the marked hours
  const addTime = () => {
    const day = parseYmd(pDate)
    const [h, m] = pTime.split(':').map(Number)
    if (!day || !Number.isFinite(h) || !Number.isFinite(m)) return
    const at = fromZoned(day, h!, m!, ctx.tz)
    if (at.getTime() <= now.getTime()) { flash(t('scheduler.proposedPast')); return }
    const iso = at.toISOString()
    if (!proposed.includes(iso)) setProposed([...proposed, iso].sort())
  }
  const slots = !link ? [] : link.kind === 'general'
    ? slotsFor(link, avail, today, now, ctx.tz)
    : link.proposed_times.map((x) => new Date(x)).filter((d) => d.getTime() > now.getTime())
  const slotLabel = (at: Date) => dates.slot(at, link?.kind === 'proposed' || at.getTime() - now.getTime() > 6 * 86_400_000)
  const describe = (l: BookingLink) =>
    l.description ??
    [
      l.kind === 'general' ? t('scheduler.anySlot', { weeks: Math.max(1, Math.round(l.horizon_days / 7)) }) : t('scheduler.specificTimes', { count: l.proposed_times.length }),
      l.video_provider ? PROVIDER[l.video_provider] : null,
      l.expires_at ? t('scheduler.expires', { date: dates.short(dates.dayOf(new Date(l.expires_at)).day) }) : null,
    ].filter(Boolean).join(' · ')

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-3">
        {links.map((l, i) => (
          <button
            key={l.id}
            type="button"
            aria-pressed={i === selected}
            onClick={() => { setSelected(i); setSlot(null) }}
            className={`flex cursor-pointer flex-col gap-2 rounded-20 border bg-surface px-[18px] py-4 text-left text-14 ${i === selected ? 'border-ink' : 'border-line'}`}
          >
            <span className="flex w-full justify-between gap-[10px]">
              <b className="text-14">{l.title}</b>
              <span className="whitespace-nowrap rounded-999 bg-tile px-[9px] py-[2px] text-11 font-bold">{t(`scheduler.kind.${l.kind}`)}</span>
            </span>
            <span className="font-mono text-12 text-link">{l.slug}</span>
            <span className="text-12 text-muted">{describe(l)}</span>
          </button>
        ))}
        <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{links.length ? t('scheduler.newLink') : t('scheduler.noLinks')}</b>
          <span className="text-12 text-muted">{kind === 'general' ? t('scheduler.newLinkHint') : t('scheduler.newProposedHint')}</span>
          <div className="flex rounded-10 bg-tile p-[3px]">
            {(['general', 'proposed'] as const).map((k) => (
              <button key={k} type="button" aria-pressed={kind === k} onClick={() => setKind(k)} className={`flex-1 cursor-pointer rounded-7 border-none p-[7px] text-12.5 ${kind === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
                {t(`scheduler.kind.${k}`)}
              </button>
            ))}
          </div>
          {kind === 'proposed' ? (
            <>
              {proposed.length ? (
                <div className="grid grid-cols-2 gap-[6px] sm:grid-cols-3">
                  {proposed.map((x) => (
                    <span key={x} className="flex h-[38px] items-center justify-between gap-1 rounded-10 border border-line bg-surface pl-[10px] pr-[6px] text-12.5 font-medium">
                      {dates.slot(new Date(x), true)}
                      <button type="button" aria-label={t('scheduler.removeTime', { time: dates.slot(new Date(x), true) })} onClick={() => setProposed(proposed.filter((y) => y !== x))} className="cursor-pointer border-none bg-transparent p-0 text-13 text-muted">×</button>
                    </span>
                  ))}
                </div>
              ) : null}
              <div className="flex flex-wrap gap-2">
                <input type="date" value={pDate} min={ctx.today} onChange={(e) => setPDate(e.target.value)} aria-label={t('modal.date')} className="h-9 rounded-9 border border-line bg-canvas px-2 text-12.5" />
                <input type="time" value={pTime} onChange={(e) => setPTime(e.target.value)} aria-label={t('modal.time')} className="h-9 rounded-9 border border-line bg-canvas px-2 text-12.5" />
                <button type="button" disabled={!pDate || proposed.length >= 10} onClick={addTime} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-[15px] text-12.5 font-semibold disabled:cursor-default disabled:opacity-60">
                  {t('scheduler.addTime')}
                </button>
                <span className="self-center text-11.5 text-muted">{t('scheduler.timesCount', { count: proposed.length })}</span>
              </div>
            </>
          ) : null}
          <div className="flex flex-wrap gap-2">
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t('scheduler.titlePlaceholder')}
              aria-label={t('scheduler.titlePlaceholder')}
              maxLength={120}
              className="h-9 min-w-0 flex-1 rounded-9 border border-line bg-canvas px-[10px] text-12.5"
            />
            <select value={duration} onChange={(e) => setDuration(Number(e.target.value))} aria-label={t('modal.duration')} className="h-9 rounded-9 border border-line bg-canvas text-12.5">
              {[15, 30, 45, 60].map((m) => <option key={m} value={m}>{t('calendar.minutes', { count: m })}</option>)}
            </select>
            <button type="button" disabled={pending || !title.trim() || (kind === 'proposed' && proposed.length === 0)} onClick={create} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60">
              {t('scheduler.createLink')}
            </button>
          </div>
        </div>
        <div className="rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('scheduler.availability')}</b>
          <div className="mt-[10px] grid gap-1 text-11 [grid-template-columns:50px_repeat(5,minmax(0,1fr))]">
            <span />
            {GRID_DAYS.map((wd) => (
              <b key={wd} className="text-center">{format.dateTime(new Date(Date.UTC(2026, 9, 4 + wd, 12)), { weekday: 'short', timeZone: 'UTC' })}</b>
            ))}
            {GRID_HOURS.map((h) => (
              <div key={h} className="contents">
                <span className="pt-[5px] text-muted">{`${String(h).padStart(2, '0')}:00`}</span>
                {GRID_DAYS.map((wd) => {
                  const on = avail.has(key(wd, h))
                  return (
                    <button
                      key={wd}
                      type="button"
                      aria-pressed={on}
                      aria-label={t('scheduler.cell', { day: format.dateTime(new Date(Date.UTC(2026, 9, 4 + wd, 12)), { weekday: 'long', timeZone: 'UTC' }), hour: `${String(h).padStart(2, '0')}:00` })}
                      onClick={() => toggle(wd, h)}
                      className={`h-6 cursor-pointer rounded-6 border border-line ${on ? 'bg-ok-bg' : 'bg-canvas'}`}
                    />
                  )
                })}
              </div>
            ))}
          </div>
          <div className="mt-2 text-11.5 text-muted">
            {scheduling.calendar?.status === 'connected' ? t('scheduler.availConnected') : t('scheduler.availNotConnected')}
          </div>
        </div>
      </div>

      <div className="flex flex-col gap-3 rounded-20 border border-line bg-canvas px-5 py-[18px]">
        <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('scheduler.contactSees')}</div>
        <div className="flex flex-col gap-3 rounded-18 border border-line bg-surface p-[18px]">
          {link ? (
            <>
              <div className="flex items-center gap-[10px]">
                <span className="flex h-10 w-10 items-center justify-center rounded-12 bg-ink font-serif font-bold text-canvas">{ctx.me.initials ?? ''}</span>
                <span className="flex flex-col">
                  <b>{link.title}</b>
                  <span className="text-12 text-muted">
                    {[ctx.me.name, t('calendar.minutes', { count: link.duration_min }), link.video_provider ? PROVIDER[link.video_provider] : null].filter(Boolean).join(' · ')}
                  </span>
                </span>
              </div>
              {slots.length ? (
                <div className="grid grid-cols-3 gap-[6px]">
                  {slots.map((s, i) => (
                    <button
                      key={s.toISOString()}
                      type="button"
                      aria-pressed={slot === i}
                      onClick={() => setSlot(i)}
                      className={`h-[38px] cursor-pointer rounded-10 border text-12.5 ${slot === i ? 'border-ink bg-highlight font-bold' : 'border-line bg-surface font-medium'}`}
                    >
                      {slotLabel(s)}
                    </button>
                  ))}
                </div>
              ) : (
                <div className="text-12.5 text-muted">{link.kind === 'proposed' ? t('scheduler.noProposed') : t('scheduler.noSlots')}</div>
              )}
              <button type="button" disabled className="h-10 cursor-default rounded-11 border border-ink bg-primary text-13 font-bold opacity-60">
                {t('scheduler.confirm')}
              </button>
              <div className="text-11.5 text-muted">{t('scheduler.previewOnly')}</div>
            </>
          ) : (
            <div className="text-12.5 text-muted">{t('scheduler.previewEmpty')}</div>
          )}
        </div>
        <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('scheduler.recent')}</div>
        {scheduling.bookings.length === 0 ? <div className="py-[6px] text-12.5 text-muted">{t('scheduler.noBookings')}</div> : null}
        {scheduling.bookings.slice(0, 10).map((b, i) => (
          <div key={i} className="flex justify-between gap-3 border-b border-line py-[6px] text-12.5">
            <span><b>{b.name ?? '—'}</b> · {b.organization ?? b.link}</span>
            <span className="whitespace-nowrap text-muted">{dates.slot(new Date(b.starts_at), true)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
