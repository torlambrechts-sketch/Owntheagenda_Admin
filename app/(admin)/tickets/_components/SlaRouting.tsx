'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { routeCategory, saveSla } from '../actions'
import { PTONE, priorityOf, useLabel, useTarget } from './lib'
import { IMPACTS } from '@/lib/data/tickets-shared'
import type { TicketConfig } from '@/lib/data/tickets'

const card = 'overflow-hidden rounded-20 border border-line bg-surface'
const head = 'flex items-center justify-between gap-2 border-b border-line px-[18px] py-[14px] text-15 font-bold'
const editBtn = 'h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-11.5 font-semibold'
const slaCols = '[grid-template-columns:90px_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.4fr)]'

/** SLA and routing (Tickets.dc.html, v.sla): service levels, the priority matrix, routing and the channels in. */
export function SlaRouting({ config, canConfigure }: { config: TicketConfig; canConfigure: boolean }) {
  const t = useTranslations('tickets')
  const tc = useTranslations('common')
  const format = useFormatter()
  const target = useTarget()
  const cat = useLabel('categories')
  const queue = useLabel('queues')
  const flash = useToast()
  const [editSla, setEditSla] = useState(false)
  const [editRoute, setEditRoute] = useState(false)

  // «Mon–Fri 08–16»: the open days as a range when they run together, and the opening hours
  const hours = [...config.hours].sort((a, b) => a.dow - b.dow)
  const day = (dow: number) => format.dateTime(new Date(Date.UTC(2024, 0, dow)), { weekday: 'short', timeZone: 'UTC' })
  const contiguous = hours.every((h, i) => i === 0 || h.dow === hours[i - 1]!.dow + 1)
  const days = !hours.length ? '—' : contiguous ? (hours.length > 1 ? `${day(hours[0]!.dow)}–${day(hours.at(-1)!.dow)}` : day(hours[0]!.dow)) : hours.map((h) => day(h.dow)).join(', ')
  const clock = (s: string | undefined) => (s ? (s.slice(3, 5) === '00' ? s.slice(0, 2) : s.slice(0, 5)) : '—')

  async function sla(priority: string, first: number, resolution: number) {
    if (!(first > 0) || !(resolution > 0)) return
    const r = await saveSla({ priority, firstResponseMin: Math.round(first * 60), resolutionMin: Math.round(resolution * 60) })
    flash(r.ok ? t('sla.saved') : tc(`errors.${r.code}`))
  }
  async function route(category: string, q: string) {
    const r = await routeCategory({ category, queue: q })
    flash(r.ok ? t('sla.saved') : tc(`errors.${r.code}`))
  }

  const routing = config.queues
    .map((q) => ({ q, cats: config.categories.filter((c) => c.queue_key === q.key) }))
    .filter((x) => x.cats.length)
  const channels = ['form', 'inapp', 'email', 'none'] as const

  return (
    <div className="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={card}>
        <div className={`${head}`}>
          {t('sla.title')}
          {canConfigure ? <button type="button" aria-pressed={editSla} onClick={() => setEditSla(!editSla)} className={editBtn}>{editSla ? t('sla.done') : t('sla.edit')}</button> : null}
        </div>
        <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${slaCols}`}>
          <span>{t('sla.cols.priority')}</span><span>{t('sla.cols.first')}</span><span>{t('sla.cols.resolution')}</span><span>{t('sla.cols.used')}</span>
        </div>
        {config.sla.map((s) => {
          const p = t(`priorities.${s.priority}`)
          return (
            <div key={s.priority} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 ${slaCols}`}>
              <span><span className={`rounded-999 px-[10px] py-[3px] text-11.5 font-bold ${PTONE[s.priority].bg} ${PTONE[s.priority].ink}`}>{p}</span></span>
              {editSla ? (
                <>
                  <HoursInput label={t('sla.firstLabel', { p })} min={s.first_response_min} onSave={(h) => void sla(s.priority, h, s.resolution_min / 60)} unit={t('sla.unit')} />
                  <HoursInput label={t('sla.resolutionLabel', { p })} min={s.resolution_min} onSave={(h) => void sla(s.priority, s.first_response_min / 60, h)} unit={t('sla.unit')} />
                </>
              ) : (
                <>
                  <b>{target(s.first_response_min, true)}</b>
                  <b>{target(s.resolution_min, true)}</b>
                </>
              )}
              <span className="text-12 text-muted">{t.has(`sla.usedFor.${s.priority}`) ? t(`sla.usedFor.${s.priority}`) : ''}</span>
            </div>
          )
        })}
        <div className="px-[18px] py-[10px] text-12 text-muted">
          {t('sla.hours', { days, from: clock(hours[0]?.opens), to: clock(hours[0]?.closes) })}
        </div>
      </div>

      <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="mb-1 text-15 font-bold">{t('sla.matrix')}</div>
        <div className="mb-3 text-12 text-muted">{t('sla.matrixSub')}</div>
        <div className="grid gap-[6px] text-12.5 [grid-template-columns:110px_repeat(2,minmax(0,1fr))]">
          <span />
          <b className="text-center">{t('urgencies.not_blocking')}</b>
          <b className="text-center">{t('sla.blockingSend')}</b>
          {IMPACTS.map((i) => (
            <MatrixRow key={i} label={t(`impacts.${i}`)} a={priorityOf(i, 'not_blocking')} b={priorityOf(i, 'blocking')} />
          ))}
        </div>
      </div>

      <div className={card}>
        <div className={head}>
          {t('sla.routing')}
          {canConfigure ? <button type="button" aria-pressed={editRoute} onClick={() => setEditRoute(!editRoute)} className={editBtn}>{editRoute ? t('sla.done') : t('sla.edit')}</button> : null}
        </div>
        {editRoute
          ? config.categories.map((c) => (
              <div key={c.key} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 [grid-template-columns:minmax(0,1fr)_20px_130px]">
                <span>{cat(c.key, c.name)}</span>
                <span className="text-faint">→</span>
                <select
                  aria-label={t('sla.routeLabel', { category: cat(c.key, c.name) })}
                  defaultValue={c.queue_key}
                  onChange={(e) => void route(c.key, e.target.value)}
                  className="h-[30px] rounded-8 border border-line bg-canvas text-12 font-bold"
                >
                  {config.queues.map((q) => <option key={q.key} value={q.key}>{queue(q.key, q.name)}</option>)}
                </select>
              </div>
            ))
          : routing.map((r) => (
              <div key={r.q.key} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 [grid-template-columns:minmax(0,1fr)_20px_110px]">
                <span>{r.cats.map((c) => cat(c.key, c.name)).join(' · ')}</span>
                <span className="text-faint">→</span>
                <b>{queue(r.q.key, r.q.name)}</b>
              </div>
            ))}
      </div>

      <div className={card}>
        <div className={head}>{t('sla.channels')}</div>
        {channels.map((c) => (
          <div key={c} className="flex flex-col gap-[3px] border-b border-line px-[18px] py-[11px]">
            <b className="text-13">{t(`sla.channel.${c}`)}</b>
            <span className="text-12 leading-[1.5] text-muted">{t(`sla.channel.${c}D`)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function MatrixRow({ label, a, b }: { label: string; a: keyof typeof PTONE; b: keyof typeof PTONE }) {
  const tp = useTranslations('tickets.priorities')
  const cell = (p: keyof typeof PTONE) => (
    <span className={`flex h-[46px] items-center justify-center rounded-12 font-bold ${PTONE[p].bg} ${PTONE[p].ink}`}>{tp(p)}</span>
  )
  return (
    <>
      <b className="flex items-center">{label}</b>
      {cell(a)}
      {cell(b)}
    </>
  )
}

/** One SLA target in business hours; saved when the value changes and the field is left. */
function HoursInput({ label, min, onSave, unit }: { label: string; min: number; onSave: (hours: number) => void; unit: string }) {
  const [v, setV] = useState(String(Math.round((min / 60) * 100) / 100))
  return (
    <span className="flex items-center gap-[6px]">
      <input
        type="number"
        min={0.25}
        step={0.25}
        aria-label={label}
        value={v}
        onChange={(e) => setV(e.target.value)}
        onBlur={() => { const h = Number(v); if (h > 0 && Math.round(h * 60) !== min) onSave(h) }}
        className="h-[30px] w-[72px] rounded-8 border border-line bg-canvas px-2 text-12 font-bold"
      />
      <span className="text-12 text-muted">{unit}</span>
    </span>
  )
}
