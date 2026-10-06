'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import type { ActivityRow, Counts } from '@/lib/data/activities'
import { addDays, dayDiff, fromZoned, parseYmd, sameDay, zoned } from '@/lib/data/activities-time'
import { useToast } from '@/components/ui/Toast'
import { bulkDone, bulkMove, bulkPriority, markDone, setPriority } from '../actions'
import type { Go, ScreenState } from './ActivitiesScreen'
import { PRIO_BG, PRIORITIES, canEdit, hm, type Ctx, type ListTab } from './shared'
import { useDates } from './dates'

const COLS = '[grid-template-columns:26px_28px_minmax(180px,1.6fr)_minmax(140px,1.2fr)_120px_70px_90px_100px_70px]'
const RANK = { high: 0, medium: 1, low: 2 } as const
const LIST_TABS: ListTab[] = ['all', 'overdue', 'today', 'week', 'done']

export function TodoTab({ ctx, state, rows, counts, go, open, onDone }: {
  ctx: Ctx; state: ScreenState; rows: ActivityRow[]; counts: Counts | null; go: Go; open: (id: string) => void; onDone: (row: ActivityRow) => void
}) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const dates = useDates(ctx.tz)
  const flash = useToast()
  const [pending, startTransition] = useTransition()
  const [sel, setSel] = useState<Record<string, boolean>>({})
  // optimistic edits until the refreshed rows arrive
  const [local, setLocal] = useState<Record<string, Partial<ActivityRow>>>({})
  useEffect(() => { setLocal({}); setSel((s) => Object.fromEntries(Object.entries(s).filter(([id, on]) => on && rows.some((r) => r.id === id)))) }, [rows])
  const today = parseYmd(ctx.today)!

  const list = useMemo(() => {
    const merged = rows.map((r) => ({ ...r, ...local[r.id] }))
    const due = (a: ActivityRow) => a.starts_at ?? '9999'
    return merged.sort((a, b) => (state.sort === 'prio' ? RANK[a.priority] - RANK[b.priority] || due(a).localeCompare(due(b)) : due(a).localeCompare(due(b))))
  }, [rows, local, state.sort])
  const selIds = list.filter((a) => sel[a.id]).map((a) => a.id)

  const fail = (code: string) => flash(tc(`errors.${code}`))

  const dueOf = (a: ActivityRow) => {
    if (!a.starts_at) return { text: '—', late: false }
    const z = zoned(new Date(a.starts_at), ctx.tz)
    const day = { y: z.y, m: z.m, d: z.d }
    const late = !a.done && !!a.overdue
    if (sameDay(day, today)) return { text: a.all_day ? t('todo.todayAllDay') : t('todo.today', { time: hm(z.h, z.min) }), late }
    const ago = dayDiff(today, day)
    if (ago > 0 && !a.done) return { text: t('todo.overdue', { count: ago }), late }
    return { text: dates.short(day), late }
  }

  const toggleDone = (a: ActivityRow) => {
    const next = !a.done
    setLocal((l) => ({ ...l, [a.id]: { ...l[a.id], done: next } }))
    startTransition(async () => {
      const r = await markDone({ id: a.id, done: next })
      if (!r.ok) { setLocal((l) => ({ ...l, [a.id]: { ...l[a.id], done: a.done } })); fail(r.code); return }
      if (next && r.prompt) onDone(a)
    })
  }
  const changePrio = (a: ActivityRow, p: (typeof PRIORITIES)[number]) => {
    setLocal((l) => ({ ...l, [a.id]: { ...l[a.id], priority: p } }))
    startTransition(async () => {
      const r = await setPriority({ id: a.id, version: a.version, priority: p })
      if (!r.ok) { setLocal((l) => ({ ...l, [a.id]: { ...l[a.id], priority: a.priority } })); fail(r.code) }
    })
  }
  const bulk = (run: () => Promise<{ ok: true; n: number } | { ok: false; code: string }>, msg: string) => {
    startTransition(async () => {
      const r = await run()
      if (!r.ok) { fail(r.code); return }
      setSel({})
      flash(t('toast.bulk', { what: msg, count: r.n }))
    })
  }
  const moveTomorrow = () => {
    // each activity keeps its time of day; one without a time becomes an all-day item tomorrow
    const tomorrow = addDays(today, 1)
    const groups = new Map<string, { ids: string[]; starts_at: string; all_day: boolean }>()
    for (const a of list.filter((x) => sel[x.id])) {
      const z = a.starts_at && !a.all_day ? zoned(new Date(a.starts_at), ctx.tz) : null
      const at = fromZoned(tomorrow, z?.h ?? 0, z?.min ?? 0, ctx.tz).toISOString()
      const key = `${at}|${!z}`
      const g = groups.get(key) ?? { ids: [], starts_at: at, all_day: !z }
      g.ids.push(a.id)
      groups.set(key, g)
    }
    bulk(() => bulkMove([...groups.values()]), t('toast.movedTomorrow'))
  }

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-[10px] text-12.5">
        {LIST_TABS.map((k) => {
          const on = state.list === k
          return (
            <button
              key={k}
              type="button"
              aria-pressed={on}
              onClick={() => go({ list: k })}
              className={`cursor-pointer rounded-999 border px-[11px] py-[5px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
            >
              {t(`todo.tabs.${k}`)} <span className="text-muted">{counts ? counts[k] : ''}</span>
            </button>
          )
        })}
        <span className="flex-1" />
        {selIds.length && ctx.rights.bulk ? (
          <span className="flex flex-wrap items-center gap-[6px]">
            <b>{t('todo.selected', { count: selIds.length })}</b>
            <select
              value=""
              disabled={pending}
              onChange={(e) => { const p = e.target.value as (typeof PRIORITIES)[number]; if (p) bulk(() => bulkPriority(selIds, p), t('toast.prioritySet')) }}
              className="h-[30px] rounded-9 border border-line bg-surface text-12"
            >
              <option value="">{t('todo.setPriority')}</option>
              {PRIORITIES.map((p) => <option key={p} value={p}>{t(`priority.${p}`)}</option>)}
            </select>
            <button type="button" disabled={pending} onClick={moveTomorrow} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">
              {t('todo.moveTomorrow')}
            </button>
            <button type="button" disabled={pending} onClick={() => bulk(() => bulkDone(selIds), t('toast.markedDone'))} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold">
              {t('todo.markDone')}
            </button>
          </span>
        ) : null}
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[904px]">
          <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
            <span />
            <span>{t('todo.col.done')}</span>
            <span>{t('todo.col.subject')}</span>
            <span>{t('todo.col.linked')}</span>
            <button type="button" aria-pressed={state.sort === 'due'} onClick={() => go({ sort: 'due' })} className="cursor-pointer border-none bg-transparent p-0 text-left [color:inherit] [font:inherit] [letter-spacing:inherit] [text-transform:inherit]">
              {t('todo.col.due')}
            </button>
            <span>{t('todo.col.dur')}</span>
            <span>{t('todo.col.owner')}</span>
            <button type="button" aria-pressed={state.sort === 'prio'} onClick={() => go({ sort: 'prio' })} className="cursor-pointer border-none bg-transparent p-0 text-left [color:inherit] [font:inherit] [letter-spacing:inherit] [text-transform:inherit]">
              {t('todo.col.priority')}
            </button>
            <span>{t('todo.col.guests')}</span>
          </div>
          {list.length === 0 ? <div className="px-4 py-[14px] text-12.5 text-muted">{t(`todo.empty.${state.list}`)}</div> : null}
          {list.map((a) => {
            const due = dueOf(a)
            const editable = canEdit(ctx, a)
            return (
              <div key={a.id} className={`grid items-center gap-[10px] border-b border-line px-4 py-2 text-12.5 ${COLS} ${sel[a.id] ? 'bg-highlight' : 'bg-transparent'}`}>
                <input
                  type="checkbox"
                  aria-label={t('todo.select', { subject: a.subject })}
                  checked={!!sel[a.id]}
                  disabled={!ctx.rights.bulk}
                  onChange={() => setSel((s) => ({ ...s, [a.id]: !s[a.id] }))}
                  className="accent-ink"
                />
                <button
                  type="button"
                  aria-label={a.done ? t('todo.reopen') : t('todo.markDone')}
                  aria-pressed={a.done}
                  disabled={!editable}
                  onClick={() => toggleDone(a)}
                  className={`h-5 w-5 cursor-pointer rounded-999 border-[1.5px] p-0 text-11 font-bold text-ok-ink disabled:cursor-default ${a.done ? 'border-link bg-ok-bg' : 'border-ink bg-transparent'}`}
                >
                  {a.done ? '✓' : ''}
                </button>
                <button type="button" onClick={() => open(a.id)} className={`cursor-pointer border-none bg-transparent p-0 text-left font-semibold ${a.done ? 'line-through' : ''}`}>
                  {a.type?.glyph} {a.subject}
                </button>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap text-muted">{a.deal?.title ?? a.organization ?? a.person ?? '—'}</span>
                <span className={due.late ? 'font-bold text-danger' : 'font-normal text-ink'}>{due.text}</span>
                <span>{t('calendar.minutes', { count: a.duration_min })}</span>
                <span>{a.owner?.name?.split(' ')[0] ?? '—'}</span>
                <select
                  aria-label={t('todo.col.priority')}
                  value={a.priority}
                  disabled={!editable}
                  onChange={(e) => changePrio(a, e.target.value as (typeof PRIORITIES)[number])}
                  className={`h-7 rounded-8 border border-line text-12 font-bold ${PRIO_BG[a.priority]}`}
                >
                  {PRIORITIES.map((p) => <option key={p} value={p}>{t(`priority.${p}`)}</option>)}
                </select>
                <span className="text-muted">{a.guests ? (a.declined ? t('todo.guestsDeclined', { count: a.guests, declined: a.declined }) : String(a.guests)) : '—'}</span>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
