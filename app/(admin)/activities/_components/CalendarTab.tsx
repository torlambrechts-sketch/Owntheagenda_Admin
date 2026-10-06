'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { ActivityRow } from '@/lib/data/activities'
import { addDays, asNoon, fromZoned, isoWeek, mondayOf, monthGrid, parseYmd, sameDay, ymd, zoned, type Day } from '@/lib/data/activities-time'
import { useToast } from '@/components/ui/Toast'
import { reschedule } from '../actions'
import type { Go, ScreenState } from './ActivitiesScreen'
import { bar, canEdit, hm, tone, typeName, type CalView, type Ctx } from './shared'
import { useDates } from './dates'

const ROW = 54 // px per hour (the design's slot height)

type Placed = ActivityRow & { at: { day: Day; h: number; min: number } | null }

export function CalendarTab({ ctx, state, rows, go, open }: { ctx: Ctx; state: ScreenState; rows: ActivityRow[]; go: Go; open: (id: string) => void }) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const dates = useDates(ctx.tz)
  const flash = useToast()
  const [, startTransition] = useTransition()
  const today = parseYmd(ctx.today)!
  const date = parseYmd(state.date) ?? today

  // a drop moves the card at once; the server's answer replaces it
  const [moved, setMoved] = useState<Record<string, string>>({})
  useEffect(() => setMoved({}), [rows])

  const placed: Placed[] = useMemo(() => rows.map((a) => {
    const iso = moved[a.id] ?? a.starts_at
    if (!iso) return { ...a, at: null }
    const z = zoned(new Date(iso), ctx.tz)
    return { ...a, starts_at: iso, at: { day: { y: z.y, m: z.m, d: z.d }, h: z.h, min: z.min } }
  }), [rows, moved, ctx.tz])

  const modes: CalView[] = ['day', 'week', 'month']
  const monday = mondayOf(date)
  const title = state.view === 'month'
    ? dates.monthTitle(date)
    : state.view === 'day'
      ? dates.long(date)
      : t('calendar.weekTitle', {
          week: isoWeek(date),
          range: (() => {
            // written out, not dateTimeRange: Node and the browser format ranges differently (hydration)
            const sunday = addDays(monday, 6)
            const month = dates.monthLong
            return monday.m === sunday.m
              ? t('calendar.rangeSameMonth', { from: monday.d, to: sunday.d, month: month(sunday) })
              : t('calendar.rangeTwoMonths', { from: monday.d, fromMonth: month(monday), to: sunday.d, toMonth: month(sunday) })
          })(),
        })

  const drop = (a: Placed, day: Day, hour: number) => {
    if (!canEdit(ctx, a)) return
    const at = fromZoned(day, hour, 0, ctx.tz).toISOString()
    setMoved((m) => ({ ...m, [a.id]: at }))
    const when = `${dates.weekdayShort(day)} ${hm(hour, 0)}`
    startTransition(async () => {
      const r = await reschedule({ id: a.id, version: a.version, starts_at: at })
      if (r.ok) flash(t('toast.rescheduled', { when }))
      else {
        setMoved((m) => { const n = { ...m }; delete n[a.id]; return n })
        flash(tc(`errors.${r.code}`))
      }
    })
  }

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex rounded-10 bg-tile p-[3px]">
          {modes.map((m) => (
            <button
              key={m}
              type="button"
              aria-pressed={state.view === m}
              onClick={() => go({ view: m })}
              className={`cursor-pointer rounded-7 border-none px-3 py-[6px] text-12.5 ${state.view === m ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
            >
              {t(`calendar.${m}`)}
            </button>
          ))}
        </div>
        <b className="font-serif text-18">{title}</b>
        <span className="text-12 text-muted">{t('calendar.hint')}</span>
      </div>
      {state.view === 'week' ? <Week ctx={ctx} monday={monday} today={today} items={placed} onDrop={drop} open={open} /> : null}
      {state.view === 'month' ? <Month ctx={ctx} date={date} today={today} items={placed} open={open} /> : null}
      {state.view === 'day' ? <DayList ctx={ctx} date={date} items={placed} open={open} /> : null}
    </div>
  )
}

function Week({ ctx, monday, today, items, onDrop, open }: {
  ctx: Ctx; monday: Day; today: Day; items: Placed[]; onDrop: (a: Placed, day: Day, hour: number) => void; open: (id: string) => void
}) {
  const t = useTranslations('activities')
  const format = useFormatter()
  const [dragging, setDragging] = useState<string | null>(null)
  const days = Array.from({ length: 7 }, (_, i) => addDays(monday, i))
  const timed = items.filter((a) => a.at && !a.all_day)
  const allDay = items.filter((a) => a.at && a.all_day)

  // the hours that hold activities: the design's 08–17, widened when an activity starts earlier or ends later
  let first = 8
  let last = 18
  for (const a of timed) {
    first = Math.min(first, a.at!.h)
    last = Math.max(last, Math.min(24, Math.ceil(a.at!.h + (a.at!.min + a.duration_min) / 60)))
  }
  const hours = Array.from({ length: last - first }, (_, i) => first + i)
  const colBg = (d: Day, i: number) => (sameDay(d, today) ? 'bg-cream' : i > 4 ? 'bg-canvas' : 'bg-surface')
  const byId = new Map(items.map((a) => [a.id, a]))

  return (
    <div className="overflow-auto rounded-20 border border-line bg-surface">
      <div className="min-w-[900px]">
        <div className="grid border-b border-line [grid-template-columns:54px_repeat(7,minmax(0,1fr))]">
          <span />
          {days.map((d, i) => (
            <div key={i} className={`border-l border-line p-[10px] ${colBg(d, i)}`}>
              <div className="text-11 font-bold uppercase tracking-label text-muted">{format.dateTime(asNoon(d), { weekday: 'short', timeZone: 'UTC' })}</div>
              <b className="font-serif text-18">{d.d}</b>
            </div>
          ))}
        </div>
        {allDay.length ? (
          <div className="grid border-b border-line [grid-template-columns:54px_repeat(7,minmax(0,1fr))]">
            <div className="pr-2 pt-[3px] text-right text-11 text-faint">{t('calendar.allDay')}</div>
            {days.map((d, i) => (
              <div key={i} className={`flex flex-col gap-1 border-l border-line p-1 ${colBg(d, i)}`}>
                {allDay.filter((a) => sameDay(a.at!.day, d)).map((a) => (
                  <button
                    key={a.id}
                    type="button"
                    onClick={() => open(a.id)}
                    title={`${typeName(ctx, a)} · ${a.subject}`}
                    className={`cursor-pointer overflow-hidden text-ellipsis whitespace-nowrap rounded-6 border-none px-[6px] py-[2px] text-left text-10.5 ${a.done ? 'bg-beige line-through' : tone(a.type?.key)[0]}`}
                  >
                    {a.type?.glyph} {a.subject}
                  </button>
                ))}
              </div>
            ))}
          </div>
        ) : null}
        <div className="grid [grid-template-columns:54px_repeat(7,minmax(0,1fr))]">
          <div className="flex flex-col">
            {hours.map((h) => (
              <div key={h} className="h-[54px] border-b border-tile pr-2 pt-[3px] text-right text-11 text-faint">{hm(h, 0)}</div>
            ))}
          </div>
          {days.map((d, i) => (
            <div key={i} className={`relative border-l border-line ${colBg(d, i)}`}>
              {hours.map((h) => (
                <div
                  key={h}
                  className="h-[54px] border-b border-tile"
                  onDragOver={(e) => { if (dragging) e.preventDefault() }}
                  onDrop={(e) => {
                    e.preventDefault()
                    const a = byId.get(e.dataTransfer.getData('text/plain'))
                    setDragging(null)
                    if (a) onDrop(a, d, h)
                  }}
                />
              ))}
              {timed.filter((a) => sameDay(a.at!.day, d)).map((a) => {
                const [bg, bc] = tone(a.type?.key)
                const top = (a.at!.h - first) * ROW + (a.at!.min / 60) * ROW + 2
                const height = Math.max(26, (a.duration_min / 60) * ROW - 4)
                const movable = canEdit(ctx, a)
                return (
                  <div
                    key={a.id}
                    role="button"
                    tabIndex={0}
                    draggable={movable}
                    onDragStart={(e) => { e.dataTransfer.setData('text/plain', a.id); e.dataTransfer.effectAllowed = 'move'; setDragging(a.id) }}
                    onDragEnd={() => setDragging(null)}
                    onClick={() => open(a.id)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(a.id) } }}
                    title={`${typeName(ctx, a)} · ${a.subject}`}
                    className={`absolute left-1 right-1 overflow-hidden rounded-10 border px-[7px] py-[5px] text-11.5 leading-[1.25] ${movable ? 'cursor-grab' : 'cursor-pointer'} ${a.done ? 'bg-beige' : bg} ${bc}`}
                    style={{ top, height }}
                  >
                    <b className={a.done ? 'line-through' : ''}>{a.type?.glyph} {a.subject}</b>
                    <div className="text-muted">{hm(a.at!.h, a.at!.min)}{a.organization ? ` · ${a.organization.split(' ')[0]}` : ''}</div>
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function Month({ ctx, date, today, items, open }: { ctx: Ctx; date: Day; today: Day; items: Placed[]; open: (id: string) => void }) {
  const t = useTranslations('activities')
  const cells = monthGrid(date.y, date.m)
  return (
    <div className="grid grid-cols-7 overflow-hidden rounded-20 border border-line bg-surface">
      {cells.map((c, i) => {
        const isToday = c !== null && sameDay(c, today)
        const its = c ? items.filter((a) => a.at && sameDay(a.at.day, c)) : []
        return (
          <div key={c ? ymd(c) : `x${i}`} className={`flex min-h-[96px] min-w-0 flex-col gap-1 border-b border-r border-line p-2 ${isToday ? 'bg-highlight' : c ? 'bg-surface' : 'bg-canvas'}`}>
            <b className={`text-12 ${isToday ? 'text-danger' : 'text-ink'}`}>{c ? c.d : ''}</b>
            {its.slice(0, 3).map((a) => (
              <button
                key={a.id}
                type="button"
                onClick={() => open(a.id)}
                title={`${typeName(ctx, a)} · ${a.subject}`}
                className={`cursor-pointer overflow-hidden text-ellipsis whitespace-nowrap rounded-6 border-none px-[6px] py-[2px] text-left text-10.5 ${a.done ? 'bg-beige line-through' : tone(a.type?.key)[0]}`}
              >
                {a.type?.glyph} {a.subject}
              </button>
            ))}
            {its.length > 3 ? <span className="whitespace-nowrap text-10.5 text-muted">{t('calendar.more', { count: its.length - 3 })}</span> : null}
          </div>
        )
      })}
    </div>
  )
}

function DayList({ date, items, open }: { ctx: Ctx; date: Day; items: Placed[]; open: (id: string) => void }) {
  const t = useTranslations('activities')
  const list = items
    .filter((a) => a.at && sameDay(a.at.day, date))
    .sort((a, b) => (a.all_day === b.all_day ? (a.starts_at ?? '').localeCompare(b.starts_at ?? '') : a.all_day ? -1 : 1))
  return (
    <div className="flex flex-col rounded-20 border border-line bg-surface px-[18px] py-3">
      {list.length === 0 ? <div className="py-[10px] text-13 text-muted">{t('calendar.emptyDay')}</div> : null}
      {list.map((a) => {
        const extra = [a.video_url ? t('calendar.videoLink') : null, a.guests ? t('calendar.guests', { count: a.guests }) : null].filter(Boolean).join(' · ')
        return (
          <div key={a.id} className="grid items-center gap-3 border-b border-line py-[10px] text-13 [grid-template-columns:70px_8px_minmax(0,1fr)_140px]">
            <b>{a.all_day ? t('calendar.allDay') : hm(a.at!.h, a.at!.min)}</b>
            <span className={`h-9 w-2 rounded-999 ${bar(a.type?.key)}`} />
            <span className="flex flex-col">
              <button type="button" onClick={() => open(a.id)} className={`cursor-pointer border-none bg-transparent p-0 text-left text-13 font-bold ${a.done ? 'line-through' : ''}`}>
                {a.type?.glyph} {a.subject}
              </button>
              <span className="text-12 text-muted">
                {[a.organization ?? a.deal?.title ?? null, t('calendar.minutes', { count: a.duration_min }), a.owner?.name ?? null].filter(Boolean).join(' · ')}
              </span>
            </span>
            <span className="text-12 text-muted">{extra}</span>
          </div>
        )
      })}
    </div>
  )
}
