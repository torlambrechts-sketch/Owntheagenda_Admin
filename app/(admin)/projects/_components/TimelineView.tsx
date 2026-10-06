'use client'

import { useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Card, Timeline } from '@/lib/data/projects'
import { dateOnly, dragDays } from '@/lib/data/projects-shared'
import { fetchTimeline, shiftGroup } from '../actions'

type Props = { cards: Card[]; openId: string | null; rev: number; onChanged: () => void; onOpen: (id: string) => void }

type Row =
  | { kind: 'group'; id: string; name: string; x: number | null; w: number | null; start: string | null; end: string | null }
  | { kind: 'task' | 'milestone' | 'activity'; id: string; name: string; sub: boolean; x: number | null; w: number | null; done: boolean; overdue: boolean; start: string | null; end: string | null }

const ROW = 38

/**
 * The timeline (Projects.dc.html v.timeline) for one project: month columns over the computed range, a bar per group
 * (dragged to shift every dated item in it, PRJ-04), task and activity bars, milestones, dependency lines (red when
 * the successor starts before its predecessor ends) and the today line. Positions come from project_timeline.
 */
export function TimelineView({ cards, openId, rev, onChanged, onOpen }: Props) {
  const t = useTranslations('projects')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [chosen, setChosen] = useState<string | null>(openId)
  const [tl, setTl] = useState<Timeline | null>(null)
  const [loading, setLoading] = useState(true)
  const [drag, setDrag] = useState<{ id: string; dx: number } | null>(null)
  const track = useRef<HTMLDivElement>(null)
  const seq = useRef(0)

  useEffect(() => {
    const n = ++seq.current
    setLoading(true)
    void fetchTimeline(chosen).then((r) => {
      if (n !== seq.current) return
      setLoading(false)
      if (!r.ok) { flash(te(r.code)); return }
      // nothing opened yet: the first card on the board (spec §1.2)
      if (!r.timeline.project && !chosen && cards[0]) { setChosen(cards[0].id); return }
      setTl(r.timeline)
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- cards are read for the default only
  }, [chosen, rev])

  const p = tl?.project ?? null
  const range = tl?.range ?? null
  const rows: Row[] = []
  if (tl) {
    const items = tl.rows ?? []
    const row = (i: (typeof items)[number]): Row => ({ kind: i.kind, id: i.id, name: i.name ?? '', sub: i.parent_id !== null, x: i.x, w: i.w, done: i.done, overdue: !!i.overdue, start: i.start, end: i.end })
    for (const g of tl.groups ?? []) {
      rows.push({ kind: 'group', id: g.id, name: g.name, x: g.x, w: g.w, start: g.start, end: g.end })
      for (const i of items.filter((x) => x.group_id === g.id)) rows.push(row(i))
    }
    for (const i of items.filter((x) => x.group_id === null || !(tl.groups ?? []).some((g) => g.id === x.group_id))) rows.push(row(i))
  }
  const index = new Map(rows.map((r, i) => [r.id, i]))
  const deps = (tl?.dependencies ?? []).map((d) => {
    const a = rows[index.get(d.predecessor) ?? -1]
    const b = rows[index.get(d.successor) ?? -1]
    if (!a || !b || a.x === null || a.w === null || b.x === null) return null
    const ax = a.kind === 'milestone' ? a.x : a.x + a.w
    return { key: `${d.predecessor}-${d.successor}`, ya: index.get(d.predecessor)! * ROW + ROW / 2, yb: index.get(d.successor)! * ROW + ROW / 2, ax, bx: b.x, violated: !!d.violated, succ: d.successor }
  }).filter((x): x is NonNullable<typeof x> => x !== null)
  const flagged = new Set(deps.filter((d) => d.violated).map((d) => d.succ))

  const shift = async (group: string, days: number) => {
    if (!p || days === 0) return
    const r = await shiftGroup({ project: p.id, group, days })
    if (!r.ok) return flash(te(r.code))
    flash(r.flagged > 0 ? t('timeline.shiftedFlagged', { count: r.shifted, days, flagged: r.flagged }) : t('timeline.shifted', { count: r.shifted, days }))
    onChanged()
  }
  const startDrag = (e: React.PointerEvent, id: string) => {
    if (!p?.can_edit || !range) return
    e.preventDefault()
    const x0 = e.clientX
    const width = track.current?.getBoundingClientRect().width ?? 0
    setDrag({ id, dx: 0 })
    const moveH = (ev: PointerEvent) => setDrag({ id, dx: ev.clientX - x0 })
    const up = (ev: PointerEvent) => {
      window.removeEventListener('pointermove', moveH)
      window.removeEventListener('pointerup', up)
      setDrag(null)
      void shift(id, dragDays(ev.clientX - x0, width, range.days))
    }
    window.addEventListener('pointermove', moveH)
    window.addEventListener('pointerup', up)
  }

  const months = range?.months ?? []
  const short = (d: string | null) => (d ? format.dateTime(dateOnly(d), { day: 'numeric', month: 'short', timeZone: 'UTC' }) : '')
  const options = cards.some((c) => c.id === p?.id) || !p ? cards : [{ id: p.id, name: p.name } as Card, ...cards]

  return (
    <div className="flex flex-col gap-[10px]">
      <label className="flex flex-wrap items-center gap-2 text-12 text-muted">
        {t('timeline.project')}
        <select
          value={p?.id ?? chosen ?? ''}
          onChange={(e) => setChosen(e.target.value || null)}
          className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12.5 font-semibold text-ink"
        >
          {!p && !chosen ? <option value="">{t('timeline.pick')}</option> : null}
          {options.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        {p ? <button type="button" onClick={() => onOpen(p.id)} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('timeline.open')}</button> : null}
      </label>

      <div className="overflow-x-auto rounded-20 border border-line bg-surface px-[18px] py-4">
        {!p ? (
          <div className="py-6 text-center text-13 text-muted">{loading ? t('loading') : cards.length ? t('timeline.pick') : t('timeline.noProjects')}</div>
        ) : (
          <div className="relative min-w-[900px]">
            <div
              className="grid border-b border-line pb-2 text-10.5 font-bold uppercase tracking-label text-muted"
              style={{ gridTemplateColumns: `240px repeat(${Math.max(months.length, 1)},minmax(0,1fr))` }}
            >
              <span>{p.name}</span>
              {months.map((m) => <span key={m} className="border-l border-line pl-[6px]">{format.dateTime(dateOnly(m), { month: 'long', timeZone: 'UTC' })}</span>)}
            </div>
            {!range ? (
              <div className="py-6 text-center text-13 text-muted">{t('timeline.undated')}</div>
            ) : (
              <div className="relative">
                {rows.map((r) => {
                  const isGroup = r.kind === 'group'
                  const late = !isGroup && r.overdue
                  const glyph = isGroup ? '▸' : r.kind === 'milestone' ? '◆' : r.kind === 'activity' ? '◷' : '↳'
                  const dx = drag && drag.id === r.id ? drag.dx : 0
                  const tip = [r.name, r.start && r.end && r.start !== r.end ? `${short(r.start)} – ${short(r.end)}` : short(r.end ?? r.start)].filter(Boolean).join(' · ')
                  const bar =
                    isGroup ? 'top-3 h-[14px] rounded-5 border border-[rgba(25,21,16,.15)] bg-ink'
                      : r.kind === 'milestone' ? 'top-3 h-[14px] w-[14px] rounded-3 border border-ink bg-primary'
                        : r.kind === 'activity' ? 'top-[10px] h-[18px] rounded-7 border border-[rgba(25,21,16,.15)] bg-blue-bg'
                          : `top-[10px] h-[18px] rounded-7 border ${late ? 'border-danger bg-salmon' : 'border-[rgba(25,21,16,.15)] bg-ok-bg'}`
                  return (
                    <div key={r.id} className="grid h-[38px] items-center border-b border-tile [grid-template-columns:240px_minmax(0,1fr)]">
                      <span
                        className={`flex items-center gap-[6px] text-12.5 ${isGroup ? 'font-bold' : 'font-medium'} ${late ? 'text-danger' : ''} ${!isGroup && r.done ? 'text-muted line-through' : ''}`}
                        style={{ paddingLeft: isGroup ? 0 : r.sub ? 32 : 18 }}
                      >
                        <span className="text-faint">{glyph}</span>
                        <span className="min-w-0 truncate">{r.name}</span>
                        {!isGroup && flagged.has(r.id) ? <span title={t('timeline.violated')} className="text-danger">⚠</span> : null}
                      </span>
                      <div ref={rows[0]?.id === r.id ? track : undefined} className="relative h-full">
                        {r.x !== null && (r.w !== null || r.kind === 'milestone') ? (
                          isGroup && p.can_edit ? (
                            <button
                              type="button"
                              title={`${tip} · ${t('timeline.dragHint')}`}
                              aria-label={t('timeline.shiftGroup', { name: r.name })}
                              onPointerDown={(e) => startDrag(e, r.id)}
                              onKeyDown={(e) => { if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); void shift(r.id, e.key === 'ArrowLeft' ? -1 : 1) } }}
                              className={`absolute cursor-grab touch-none p-0 ${bar}`}
                              style={{ left: `${r.x}%`, width: `${r.w}%`, transform: dx ? `translateX(${dx}px)` : undefined }}
                            />
                          ) : (
                            <span
                              title={tip}
                              className={`absolute ${bar}`}
                              style={r.kind === 'milestone' ? { left: `${r.x}%`, transform: 'rotate(45deg) translateX(-7px)' } : { left: `${r.x}%`, width: `${r.w}%` }}
                            />
                          )
                        ) : null}
                      </div>
                    </div>
                  )
                })}
                {deps.length ? (
                  <svg
                    aria-hidden="true"
                    className="pointer-events-none absolute top-0"
                    style={{ left: 240, width: 'calc(100% - 240px)', height: rows.length * ROW }}
                    viewBox={`0 0 100 ${rows.length * ROW}`}
                    preserveAspectRatio="none"
                  >
                    {deps.map((d) => (
                      <path
                        key={d.key}
                        d={`M ${d.ax} ${d.ya} H ${d.ax + 0.5} V ${d.yb} H ${d.bx}`}
                        fill="none"
                        stroke={d.violated ? '#A33A16' : '#8A8272'}
                        strokeWidth={1.5}
                        strokeDasharray={d.violated ? '4 3' : undefined}
                        vectorEffect="non-scaling-stroke"
                      />
                    ))}
                  </svg>
                ) : null}
              </div>
            )}
            {range && tl?.today_pct != null ? (
              <div className="absolute bottom-0 top-[26px] w-[2px] bg-alert" style={{ left: `calc(240px + (100% - 240px) * ${tl.today_pct / 100})` }} />
            ) : null}
            <div className="mt-[10px] flex flex-wrap gap-[14px] text-11.5 text-muted">
              <span>{t('timeline.legend.task')}</span>
              <span>{t('timeline.legend.milestone')}</span>
              <span>{t('timeline.legend.depends')}</span>
              <span className="text-danger">{t('timeline.legend.today')}</span>
              {p.can_edit ? <span>{t('timeline.legend.drag')}</span> : null}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
