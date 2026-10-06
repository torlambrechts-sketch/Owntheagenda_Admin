'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardView, Card } from '@/lib/data/projects'
import { canEditProject, dateOnly, firstName, HEALTH_TONE, type Rights } from '@/lib/data/projects-shared'

type Props = {
  board: BoardView | null
  rights: Rights
  onOpen: (id: string) => void
  onMove: (c: Card, phase: string) => void
}

/** «5 Oct – 18 Dec»: the project's start and end in the viewer's locale, one side left out when not set. */
export function useDates() {
  const format = useFormatter()
  return (a: string | null, b: string | null, year = false) => {
    const f = (d: string) => format.dateTime(dateOnly(d), { day: 'numeric', month: 'short', ...(year ? { year: 'numeric' } : {}), timeZone: 'UTC' })
    if (a && b) return `${f(a)} – ${f(b)}`
    if (a) return f(a)
    if (b) return `– ${f(b)}`
    return null
  }
}

/** The board (Projects.dc.html v.board): a column per phase with its count, cards with computed progress. */
export function Board({ board, rights, onOpen, onMove }: Props) {
  const t = useTranslations('projects')
  const flash = useToast()
  const dates = useDates()
  const [dragId, setDragId] = useState<string | null>(null)
  const cards = board?.cards ?? []

  const drop = (phase: string) => (e: React.DragEvent) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain') || dragId
    setDragId(null)
    const c = cards.find((x) => x.id === id)
    if (c && c.phase_id !== phase) onMove(c, phase)
  }

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex items-start gap-[10px] overflow-x-auto pb-2">
        {(board?.phases ?? []).map((ph) => {
          const cs = cards.filter((c) => c.phase_id === ph.id)
          return (
            <div
              key={ph.id}
              onDragOver={(e) => e.preventDefault()}
              onDrop={drop(ph.id)}
              className={`flex min-h-[360px] flex-[0_0_260px] flex-col gap-2 rounded-18 p-2 ${dragId ? 'bg-wheat' : 'bg-tile'}`}
            >
              <div className="flex justify-between px-[6px] pb-2 pt-[6px]" style={{ borderBottom: `3px solid ${ph.color}` }}>
                <b className="text-13">{ph.name}</b>
                <span className="text-12 text-muted">{ph.count}</span>
              </div>
              {cs.map((c) => {
                const pct = c.total > 0 ? (c.done / c.total) * 100 : 0
                const tone = c.health ? HEALTH_TONE[c.health] : null
                const line = [c.organization, dates(c.starts_on, c.ends_on)].filter(Boolean).join(' · ')
                return (
                  <div
                    key={c.id}
                    role="button"
                    tabIndex={0}
                    draggable
                    aria-label={c.name}
                    onDragStart={(e) => {
                      if (!canEditProject(rights, c) || c.status !== 'open') { e.preventDefault(); flash(t(c.status !== 'open' ? 'flash.closedMove' : 'flash.viewOnlyMove')); return }
                      e.dataTransfer.setData('text/plain', c.id)
                      e.dataTransfer.effectAllowed = 'move'
                      setDragId(c.id)
                    }}
                    onDragEnd={() => setDragId(null)}
                    onClick={() => onOpen(c.id)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onOpen(c.id) } }}
                    className={`flex cursor-pointer flex-col gap-[6px] rounded-14 border border-line px-3 py-[11px] ${c.status === 'open' ? 'bg-surface' : 'bg-beige'}`}
                  >
                    <div className="flex justify-between gap-[6px]">
                      <b className="text-12.5 leading-[1.3]">{c.name}</b>
                      {c.status !== 'open' ? (
                        <span className="flex-none rounded-999 bg-surface px-2 py-px text-10.5 font-bold text-muted">{t(`status.${c.status}`)}</span>
                      ) : tone ? (
                        <span className={`flex-none rounded-999 px-2 py-px text-10.5 font-bold ${tone.pill}`}>{t(`health.${c.health}`)}</span>
                      ) : null}
                    </div>
                    {line ? <span className="text-11.5 text-muted">{line}</span> : null}
                    <div className="flex items-center gap-2">
                      <span className="h-[6px] flex-1 overflow-hidden rounded-999 bg-tile">
                        <span className="block h-full bg-ok" style={{ width: `${pct}%` }} />
                      </span>
                      <span className="text-11 font-bold">{c.total > 0 ? `${c.done}/${c.total}` : '—'}</span>
                    </div>
                    <span className="flex justify-between gap-2 text-11 text-muted">
                      <span>{firstName(c.owner?.name) || t('card.noOwner')}</span>
                      {c.deal ? <span className="text-right">◆ {c.deal.title}{c.deals_more > 0 ? ` +${c.deals_more}` : ''}</span> : null}
                    </span>
                    {c.overdue > 0 && c.status === 'open' ? <span className="text-11 font-bold text-danger">{t('card.overdue', { count: c.overdue })}</span> : null}
                  </div>
                )
              })}
              {cs.length === 0 ? <span className="px-[6px] py-1 text-12 text-faint">{t('board.emptyPhase')}</span> : null}
            </div>
          )
        })}
      </div>
    </div>
  )
}
