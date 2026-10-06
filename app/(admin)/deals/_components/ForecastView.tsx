'use client'

import { useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { Card, Filter } from '@/lib/data/deals'
import { fetchForecast, saveDeal } from '../actions'
import { canEditDeal, cardTone, type Rights } from './shared'

const MONTHS = 4

/** The forecast (Deals.dc.html v.forecast): four months of expected close; a card dragged to a month moves its date. */
export function ForecastView({ pipelineId, filters, rights, nf, rev, refresh, onOpen, stageName }: {
  pipelineId: string
  filters: Filter[]
  rights: Rights
  nf: NumberFormat
  rev: number
  refresh: () => void
  onOpen: (id: string) => void
  stageName: Map<string, string>
}) {
  const t = useTranslations('deals')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const [cards, setCards] = useState<Card[] | null>(null)
  const [drag, setDrag] = useState<string | null>(null)
  const seq = useRef(0)

  const now = new Date()
  const months = Array.from({ length: MONTHS }, (_, i) => {
    const d = new Date(Date.UTC(now.getFullYear(), now.getMonth() + i, 1, 12))
    return { ym: d.toISOString().slice(0, 7), date: d }
  })
  const from = `${months[0]!.ym}-01`

  const key = JSON.stringify([pipelineId, filters, from])
  useEffect(() => {
    const n = ++seq.current
    void fetchForecast({ pipeline: pipelineId, from, months: MONTHS, filters }).then((r) => {
      if (n !== seq.current) return
      if (r.ok) setCards(r.forecast.cards)
      else flash(te(r.code))
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- key covers pipeline, filters and the first month
  }, [key, rev])

  const drop = (ym: string, label: string) => async (e: React.DragEvent) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain') || drag
    setDrag(null)
    const c = (cards ?? []).find((x) => x.id === id)
    if (!c || !canEditDeal(rights, c) || c.expected_close_date?.slice(0, 7) === ym) return
    const date = `${ym}-15`
    setCards((cs) => (cs ?? []).map((x) => (x.id === c.id ? { ...x, expected_close_date: date } : x)))
    const r = await saveDeal({ id: c.id, values: { expected_close_date: date }, version: c.version })
    if (!r.ok) { flash(te(r.code)); refresh(); return }
    flash(t('flash.closeMoved', { month: label }))
    refresh()
  }

  return (
    <div className="flex items-start gap-3 overflow-x-auto pb-[10px]">
      {months.map((m) => {
        const label = format.dateTime(m.date, { month: 'short', year: 'numeric', timeZone: 'UTC' })
        const cs = (cards ?? []).filter((c) => c.expected_close_date?.slice(0, 7) === m.ym)
        const open = cs.filter((c) => c.status === 'open')
        const won = cs.filter((c) => c.status === 'won')
        const wonSum = won.reduce((a, c) => a + c.value, 0)
        return (
          <div key={m.ym} onDragOver={(e) => e.preventDefault()} onDrop={drop(m.ym, label)} className="flex min-h-[380px] flex-[0_0_270px] flex-col gap-2 rounded-18 bg-tile p-[10px]">
            <div className="border-b border-line px-1 pb-[10px] pt-1">
              <b className="text-14">{label}</b>
              <div className="mt-2 grid grid-cols-3 gap-[6px] text-11 text-muted">
                <span className="flex flex-col">{t('forecast.open')}<b className="text-12.5 text-ink">{money(open.reduce((a, c) => a + c.value, 0), nf)}</b></span>
                <span className="flex flex-col">{t('forecast.won')}<b className="text-12.5 text-link">{money(wonSum, nf)}</b></span>
                <span className="flex flex-col">{t('forecast.projected')}<b className="text-12.5 text-ink">{money(wonSum + open.reduce((a, c) => a + (c.value * c.probability) / 100, 0), nf)}</b></span>
              </div>
            </div>
            {cs.map((c) => (
              <div
                key={c.id}
                role="button"
                tabIndex={0}
                draggable
                onDragStart={(e) => {
                  if (!canEditDeal(rights, c)) { e.preventDefault(); flash(t('flash.viewOnlyMove')); return }
                  e.dataTransfer.setData('text/plain', c.id)
                  setDrag(c.id)
                }}
                onDragEnd={() => setDrag(null)}
                onClick={() => onOpen(c.id)}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onOpen(c.id) } }}
                className={`flex cursor-pointer flex-col gap-1 rounded-13 border border-line px-[11px] py-[9px] ${cardTone(c).bg}`}
              >
                <b className="text-12.5">{c.title}</b>
                <span className="flex justify-between text-11.5 text-muted">
                  <span>{stageName.get(c.stage_id)} · {c.probability} %</span>
                  <b className="text-ink">{money(c.value, nf)}</b>
                </span>
              </div>
            ))}
          </div>
        )
      })}
    </div>
  )
}
