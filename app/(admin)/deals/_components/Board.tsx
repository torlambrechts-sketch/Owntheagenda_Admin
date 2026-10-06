'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { Board as BoardData, Card, Label, Pipeline } from '@/lib/data/deals'
import { setPref } from '../actions'
import { ACT, canEditDeal, cardTone, dateOnly, initials, scoreTone, VIZ, type Rights } from './shared'

const CARD_FIELDS = ['organization', 'value', 'close', 'score'] as const
type CardField = (typeof CARD_FIELDS)[number]

type Props = {
  pipeline: Pipeline
  board: BoardData | null
  labels: Label[]
  rights: Rights
  nf: NumberFormat
  prefs: Record<string, unknown>
  dragId: string | null
  setDragId: (id: string | null) => void
  onOpen: (id: string) => void
  onMove: (c: Card, stage: string) => void
  drops: { won: (c: Card) => void; lost: (c: Card) => void; archive: (c: Card) => void; del: ((c: Card) => void) | null }
  dragged: () => Card | null
}

const readCardPrefs = (prefs: Record<string, unknown>) =>
  prefs.card_fields && typeof prefs.card_fields === 'object' ? (prefs.card_fields as Record<string, unknown>) : {}

/** The pipeline board (Deals.dc.html v.pipeline): stage columns, cards, the drop bar while dragging. */
export function Board({ pipeline, board, labels, rights, nf, prefs, dragId, setDragId, onOpen, onMove, drops, dragged }: Props) {
  const t = useTranslations('deals')
  const format = useFormatter()
  const flash = useToast()
  const [customOpen, setCustomOpen] = useState(false)
  const [cardPrefs, setCardPrefs] = useState<Record<string, unknown>>(() => readCardPrefs(prefs))
  const stored = cardPrefs[pipeline.id]
  const fields: string[] = Array.isArray(stored) ? stored.filter((x): x is string => typeof x === 'string') : pipeline.card_fields
  const on = (f: CardField) => fields.includes(f)
  const toggle = (f: CardField) => {
    const next = on(f) ? fields.filter((x) => x !== f) : [...fields, f]
    const all = { ...cardPrefs, [pipeline.id]: next }
    setCardPrefs(all)
    void setPref({ key: 'card_fields', value: all })
  }
  const labelBy = new Map(labels.map((l) => [l.id, l]))
  const cards = board?.cards ?? []
  const dragging = dragId !== null

  const dropOn = (fn: (c: Card) => void) => (e: React.DragEvent) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain') || dragId
    const c = cards.find((x) => x.id === id) ?? dragged()
    setDragId(null)
    if (c && canEditDeal(rights, c)) fn(c)
  }
  const allow = (e: React.DragEvent) => e.preventDefault()

  const zones = [
    { k: 'won', cls: 'border-link bg-ok-bg text-ok-ink', fn: drops.won },
    { k: 'lost', cls: 'border-coral bg-peach text-rust-ink', fn: drops.lost },
    { k: 'archive', cls: 'border-line-strong bg-surface text-muted', fn: drops.archive },
    ...(drops.del ? [{ k: 'delete', cls: 'border-danger bg-surface text-danger', fn: drops.del }] : []),
  ]

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="relative flex justify-end">
        <button type="button" aria-expanded={customOpen} onClick={() => setCustomOpen(!customOpen)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold">
          {t('board.customize')}
        </button>
        {customOpen ? (
          <div className="absolute right-0 top-9 z-30 w-[240px] rounded-16 border border-line bg-surface p-[10px] shadow-pop">
            <div className="px-[6px] pb-2 pt-[2px] text-11 text-muted">{t('board.fieldsOn', { pipeline: pipeline.name })}</div>
            {CARD_FIELDS.map((f) => (
              <label key={f} className="flex cursor-pointer items-center gap-2 p-[6px] text-12.5">
                <input type="checkbox" checked={on(f)} onChange={() => toggle(f)} className="accent-ink" />
                {t(`board.field.${f}`)}
              </label>
            ))}
          </div>
        ) : null}
      </div>

      <div className="flex items-start gap-[10px] overflow-x-auto pb-[10px]">
        {pipeline.stages.map((s, i) => {
          const cs = cards.filter((c) => c.stage_id === s.id)
          return (
            <div
              key={s.id}
              onDragOver={allow}
              onDrop={dropOn((c) => { if (c.stage_id !== s.id) onMove(c, s.id) })}
              className={`flex min-h-[420px] flex-[0_0_250px] flex-col gap-2 rounded-18 border p-2 ${dragging ? 'border-line-strong bg-wheat' : 'border-transparent bg-tile'}`}
            >
              <div className="px-[6px] pb-2 pt-[6px]" style={{ borderBottom: `3px solid ${VIZ[i % 5]}` }}>
                <div className="flex justify-between gap-[6px]">
                  <b className="text-13">{s.name}</b>
                  <span className="text-11 text-muted">{s.probability} %</span>
                </div>
                <div className="mt-[3px] flex justify-between gap-[6px] whitespace-nowrap text-12 text-muted">
                  <span><b className="text-ink">{money(cs.reduce((a, c) => a + c.value, 0), nf)}</b> · {cs.length}</span>
                  {s.rot_days !== null ? <span>{t('board.rots', { days: s.rot_days })}</span> : null}
                </div>
              </div>
              {cs.map((c) => {
                const tone = cardTone(c)
                const act = ACT[c.act]
                return (
                  <div
                    key={c.id}
                    role="button"
                    tabIndex={0}
                    draggable
                    onDragStart={(e) => {
                      if (!canEditDeal(rights, c)) { e.preventDefault(); flash(t('flash.viewOnlyMove')); return }
                      e.dataTransfer.setData('text/plain', c.id)
                      e.dataTransfer.effectAllowed = 'move'
                      setDragId(c.id)
                    }}
                    onDragEnd={() => setDragId(null)}
                    onClick={() => onOpen(c.id)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onOpen(c.id) } }}
                    className={`flex cursor-pointer flex-col gap-[6px] rounded-14 border px-[11px] py-[10px] ${tone.bg} ${tone.bc}`}
                  >
                    <div className="flex justify-between gap-[6px]">
                      <b className="text-12.5 leading-[1.3]">{c.title}</b>
                      <span title={t(`act.${c.act}`)} className={`flex-none text-12 font-bold ${act.c}`}>{act.g}</span>
                    </div>
                    {on('organization') && c.organization ? <span className="text-11.5 text-muted">{c.organization}</span> : null}
                    {c.labels.length ? (
                      <span className="flex flex-wrap gap-1">
                        {c.labels.map((id) => {
                          const l = labelBy.get(id)
                          return l ? <span key={id} className="rounded-999 px-[7px] py-px text-10.5 font-bold" style={{ background: l.bg, color: l.ink }}>{l.name}</span> : null
                        })}
                      </span>
                    ) : null}
                    <div className="flex items-center justify-between gap-[6px] text-11.5">
                      <span className="flex items-center gap-[6px]">
                        <span className="flex h-5 w-5 items-center justify-center rounded-999 bg-tile text-9.5 font-bold">{c.owner?.initials ?? initials(c.owner?.name)}</span>
                        {on('value') ? <b className="tabular-nums">{money(c.value, nf)}</b> : null}
                      </span>
                      <span className="flex items-center gap-1">
                        {on('close') && c.expected_close_date ? (
                          <span className="text-muted">{format.dateTime(dateOnly(c.expected_close_date), { day: 'numeric', month: 'short', timeZone: 'UTC' })}</span>
                        ) : null}
                        {on('score') && c.score !== null ? <span className={`rounded-6 px-[6px] py-px font-bold ${scoreTone(c.score)}`}>{c.score}</span> : null}
                      </span>
                    </div>
                    {c.rotting ? <span className="text-11 font-bold text-danger">{t('board.rotting', { days: c.idle_days })}</span> : null}
                  </div>
                )
              })}
            </div>
          )
        })}
      </div>

      {dragging ? (
        <div className="sticky bottom-3 z-20 grid gap-[10px]" style={{ gridTemplateColumns: `repeat(${zones.length},1fr)` }}>
          {zones.map((z) => (
            <div key={z.k} onDragOver={allow} onDrop={dropOn(z.fn)} className={`flex h-[60px] items-center justify-center rounded-16 border-2 border-dashed text-13 font-bold ${z.cls}`}>
              {t(`drop.${z.k}`)}
            </div>
          ))}
        </div>
      ) : null}
    </div>
  )
}
