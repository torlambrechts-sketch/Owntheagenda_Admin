'use client'

import { useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { Card, DealsBase, Filter, Pipeline } from '@/lib/data/deals'
import { bulkOwner, deleteDeals, fetchList, logExport, moveDeals, saveDeal, setPref } from '../actions'
import { canEditDeal, dateOnly, type Rights } from './shared'
import { download, toCsv, toXlsx, type Cell } from '@/lib/xlsx'
import type { Status } from './DealsScreen'

type Col = 'id' | 'title' | 'org' | 'value' | 'stage' | 'owner' | 'close' | 'score' | 'source' | 'labels'
const COLS: [Col, string][] = [['id', '80px'], ['title', 'minmax(200px,2fr)'], ['org', 'minmax(140px,1.2fr)'], ['value', '110px'], ['stage', '120px'], ['owner', '110px'], ['close', '70px'], ['score', '60px'], ['source', '120px'], ['labels', '110px']]
// what deal_list sorts each column by (organization, owner and labels by name, nulls last — 0023)
const SORT_F: Record<Col, 'seq' | 'title' | 'organization' | 'value' | 'stage' | 'owner' | 'expected_close_date' | 'score' | 'source' | 'labels'> = {
  id: 'seq', title: 'title', org: 'organization', value: 'value', stage: 'stage', owner: 'owner', close: 'expected_close_date', score: 'score', source: 'source', labels: 'labels',
}
type Sort = { k: Col; dir: 'asc' | 'desc' }
const DEFAULT_COLS: Record<Col, boolean> = { id: false, title: true, org: true, value: true, stage: true, owner: true, close: true, score: true, source: true, labels: true }

const readCols = (v: unknown): Record<Col, boolean> =>
  v && typeof v === 'object' ? { ...DEFAULT_COLS, ...Object.fromEntries(Object.entries(v).filter(([k, x]) => k in DEFAULT_COLS && typeof x === 'boolean')), title: true } : DEFAULT_COLS
const readSort = (v: unknown): Sort[] =>
  Array.isArray(v) && v.length && v.every((s) => s && typeof s === 'object' && SORT_F[(s as Sort).k] && ((s as Sort).dir === 'asc' || (s as Sort).dir === 'desc'))
    ? (v as Sort[]) : [{ k: 'value', dir: 'desc' }]

/** The list (Deals.dc.html v.list): sortable, multi-sort with shift, selection bar, columns, export. */
export function ListView({ base, pipeline, filters, status, rights, nf, rev, refresh, onOpen, stageName }: {
  base: DealsBase
  pipeline: Pipeline
  filters: Filter[]
  status: Status
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
  const [rows, setRows] = useState<Card[] | null>(null)
  const [sort, setSort] = useState<Sort[]>(() => readSort(base.views.prefs.list_sort))
  const [cols, setCols] = useState<Record<Col, boolean>>(() => readCols(base.views.prefs.list_cols))
  const [colsOpen, setColsOpen] = useState(false)
  const [sel, setSel] = useState<Set<string>>(new Set())
  const seq = useRef(0)

  const key = JSON.stringify([filters, status, sort])
  useEffect(() => {
    const n = ++seq.current
    void fetchList({ status, filters, sort: sort.map((s) => ({ f: SORT_F[s.k], dir: s.dir })) }).then((r) => {
      if (n !== seq.current) return
      if (r.ok) setRows(r.list.rows)
      else flash(te(r.code))
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- key covers filters, status and sort
  }, [key, rev])

  const staffBy = new Map(base.staff.map((s) => [s.id, s.name]))
  const labelBy = new Map(base.labels.map((l) => [l.id, l.name]))
  const shown = COLS.filter(([k]) => cols[k])
  const gridCols = '26px ' + shown.map((c) => c[1]).join(' ')
  const list = rows ?? []

  const clickSort = (k: Col, shift: boolean) => {
    const cur = sort.find((s) => s.k === k)
    const dir: Sort['dir'] = cur ? (cur.dir === 'asc' ? 'desc' : 'asc') : 'asc'
    const next = shift ? [...sort.filter((s) => s.k !== k), { k, dir }] : [{ k, dir }]
    setSort(next)
    void setPref({ key: 'list_sort', value: next })
  }
  const toggleCol = (k: Col) => {
    const next = { ...cols, [k]: !cols[k] }
    setCols(next)
    void setPref({ key: 'list_cols', value: next })
  }

  const text = (d: Card, k: Col): string => {
    switch (k) {
      case 'id': return String(d.seq)
      case 'title': return d.title
      case 'org': return d.organization ?? '—'
      case 'value': return money(d.value, nf)
      case 'stage': return (stageName.get(d.stage_id) ?? '') + (d.status !== 'open' ? ' · ' + t(`status.${d.status}`).toLowerCase() : '')
      case 'owner': return (d.owner_id && staffBy.get(d.owner_id)) || d.owner?.name || '—'
      case 'close': return d.expected_close_date ? format.dateTime(dateOnly(d.expected_close_date), { day: 'numeric', month: 'short', timeZone: 'UTC' }) : '—'
      case 'score': return d.score !== null ? String(d.score) : '—'
      case 'source': return d.source ?? '—'
      case 'labels': return d.labels.map((id) => labelBy.get(id)).filter(Boolean).join(', ') || '—'
    }
  }

  const ids = [...sel].filter((id) => list.some((d) => d.id === id))
  const bulkStage = async (stage: string) => {
    if (!stage) return
    const r = await moveDeals({ ids, stage })
    if (!r.ok) return flash(te(r.code))
    setSel(new Set())
    flash(r.held ? t('flash.bulkMovedHeld', { moved: r.moved, held: r.held }) : t('flash.bulk', { count: r.moved }))
    refresh()
  }
  const bulkSetOwner = async (owner: string) => {
    if (!owner) return
    const r = await bulkOwner({ ids, owner_id: owner })
    if (!r.ok) return flash(te(r.code))
    setSel(new Set())
    flash(t('flash.bulk', { count: r.updated }))
    refresh()
  }
  const bulkDelete = async () => {
    const r = await deleteDeals({ ids })
    if (!r.ok) return flash(te(r.code))
    setSel(new Set())
    flash(t('flash.bulkDeleted', { count: r.deleted }))
    refresh()
  }
  const editValue = async (d: Card, raw: string) => {
    const n = parseInt(raw.replace(/\D/g, ''), 10) || 0
    if (n === d.value) return
    const r = await saveDeal({ id: d.id, values: { value: n }, version: d.version })
    if (!r.ok) return flash(te(r.code))
    refresh()
  }

  const table = (): Cell[][] => [
    shown.map(([k]) => t(`list.cols.${k}`)),
    ...list.map((d) => shown.map(([k]) => (k === 'value' ? d.value : k === 'id' ? d.seq : k === 'score' && d.score !== null ? d.score : text(d, k)))),
  ]
  const exportAs = async (fmt: 'csv' | 'xlsx') => {
    const data = table()
    const name = `deals-${new Date().toISOString().slice(0, 10)}.${fmt}`
    const r = await logExport({ rows: list.length, format: fmt })
    if (!r.ok) return flash(te(r.code))
    download(fmt === 'csv' ? new Blob(['﻿' + toCsv(data)], { type: 'text/csv;charset=utf-8' }) : toXlsx(data, t('views.list')), name)
    flash(fmt === 'csv' ? t('flash.csv', { rows: list.length, cols: shown.length }) : t('flash.xlsx'))
  }

  const sortLabel = sort.map((s) => `${t(`list.cols.${s.k}`).toLowerCase()} ${s.dir === 'asc' ? '↑' : '↓'}`).join(t('list.then'))
  const smallSelect = 'h-[30px] rounded-9 border border-line bg-surface text-12 text-ink'

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-[10px] text-12.5">
        <span className="text-muted">{t.rich('list.sort', { sort: sortLabel, b: (c) => <b className="text-ink">{c}</b> })}</span>
        <span className="flex-1" />
        {ids.length ? (
          <span className="flex items-center gap-[6px]">
            <b>{t('list.selected', { count: ids.length })}</b>
            {!rights.readOnly ? (
              <select aria-label={t('list.moveTo')} value="" onChange={(e) => void bulkStage(e.target.value)} className={smallSelect}>
                <option value="">{t('list.moveTo')}</option>
                {pipeline.stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            ) : null}
            {rights.bulk ? (
              <select aria-label={t('list.setOwner')} value="" onChange={(e) => void bulkSetOwner(e.target.value)} className={smallSelect}>
                <option value="">{t('list.setOwner')}</option>
                {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            ) : null}
            {rights.del && (ids.length === 1 || rights.bulk) ? (
              <button type="button" onClick={() => void bulkDelete()} className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">
                {t('list.delete')}
              </button>
            ) : null}
          </span>
        ) : null}
        <div className="relative">
          <button type="button" aria-expanded={colsOpen} onClick={() => setColsOpen(!colsOpen)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">
            {t('list.columns')}
          </button>
          {colsOpen ? (
            <div className="absolute right-0 top-9 z-30 w-[200px] rounded-16 border border-line bg-surface p-2 shadow-pop">
              {COLS.filter(([k]) => k !== 'title').map(([k]) => (
                <label key={k} className="flex items-center gap-2 px-[6px] py-[5px] text-12.5">
                  <input type="checkbox" checked={cols[k]} onChange={() => toggleCol(k)} className="accent-ink" />
                  {t(`list.cols.${k}`)}
                </label>
              ))}
            </div>
          ) : null}
        </div>
        {rights.exportRows ? (
          <>
            <button type="button" onClick={() => void exportAs('csv')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('list.exportCsv')}</button>
            <button type="button" onClick={() => void exportAs('xlsx')} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('list.xlsx')}</button>
          </>
        ) : null}
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[980px]">
          <div className="grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted" style={{ gridTemplateColumns: gridCols }}>
            <span />
            {shown.map(([k]) => {
              const i = sort.findIndex((s) => s.k === k)
              const arrow = i >= 0 ? (sort[i]!.dir === 'asc' ? '↑' : '↓') + (sort.length > 1 ? String(i + 1) : '') : ''
              return (
                <button
                  key={k}
                  type="button"
                  onClick={(e) => clickSort(k, e.shiftKey)}
                  className="cursor-pointer border-none bg-transparent p-0 text-left [color:inherit] [font:inherit] [letter-spacing:inherit] [text-transform:inherit]"
                >
                  {t(`list.cols.${k}`)} {arrow}
                </button>
              )
            })}
          </div>
          {list.map((d) => {
            const on = sel.has(d.id)
            const editable = canEditDeal(rights, d)
            return (
              <div key={d.id} className={`grid items-center gap-[10px] border-b border-line px-4 py-2 text-12.5 ${on ? 'bg-highlight' : 'bg-transparent'}`} style={{ gridTemplateColumns: gridCols }}>
                <input
                  type="checkbox"
                  aria-label={d.title}
                  checked={on}
                  onChange={() => setSel((s) => { const n = new Set(s); if (n.has(d.id)) n.delete(d.id); else n.add(d.id); return n })}
                  className="accent-ink"
                />
                {shown.map(([k]) => (
                  <span key={k} className={`min-w-0 overflow-hidden text-ellipsis whitespace-nowrap ${k === 'title' || k === 'value' ? 'font-semibold' : 'font-normal'} ${k === 'id' ? 'text-faint' : 'text-ink'}`}>
                    {k === 'value' && editable ? (
                      <input
                        key={`${d.id}-${d.version}`}
                        aria-label={t('list.cols.value')}
                        defaultValue={String(d.value)}
                        onBlur={(e) => void editValue(d, e.target.value)}
                        onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
                        className="h-7 w-full rounded-7 border border-line bg-canvas px-[6px] text-12.5 font-semibold"
                      />
                    ) : k === 'title' ? (
                      <a href={`/deals?deal=${d.id}`} onClick={(e) => { e.preventDefault(); onOpen(d.id) }}>{d.title}</a>
                    ) : (
                      text(d, k)
                    )}
                  </span>
                ))}
              </div>
            )
          })}
          {rows && list.length === 0 ? <div className="p-6 text-center text-13 text-muted">{t('list.empty')}</div> : null}
        </div>
      </div>
    </div>
  )
}
