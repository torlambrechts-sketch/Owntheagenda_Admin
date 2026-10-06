'use client'

import type { Route } from 'next'
import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { NumberFormat } from '@/lib/format'
import type { Dashboard, DashboardRef, Tile } from '@/lib/data/insights'
import { Definition, SPAN, segmentOf, type ResultRow } from '@/lib/data/insights-shared'
import { duplicateDashboardAction, saveLayoutAction } from '../actions'
import { ReportChart } from './ReportChart'
import { SharePopover } from './SharePopover'
import { btnTool, useDashboardName, useTileSub, type Pickers, type Rights } from './shared'
import type { DrillTarget } from './DrillModal'

type Layout = { report_id: string; span: number }[]

/**
 * Dashboards (design: v.dash): the dashboard picker, arrange and resize (kept in dashboard_tiles, INS-03),
 * duplicate, share, and the tiles, each the report run for this staff member by dashboard_get.
 */
export function Dashboards({ list, current, currentKey, rights, pickers, nf, onAddReport, onDrill }: {
  list: DashboardRef[]
  current: Dashboard | null
  currentKey: string
  rights: Rights
  pickers: Pickers
  nf: NumberFormat
  onAddReport: () => void
  onDrill: (d: DrillTarget) => void
}) {
  const t = useTranslations('insights')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const nameOf = useDashboardName()
  const subOf = useTileSub(rights, pickers)
  const [editing, setEditing] = useState(false)
  const [shareOpen, setShareOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const tiles = current?.tiles ?? []
  const [layout, setLayout] = useState<Layout>(() => tiles.map((x) => ({ report_id: x.report_id, span: x.span })))
  const shareRef = useRef<HTMLDivElement>(null)

  // a new dashboard (or a refresh after saving) brings its own layout
  const sig = `${current?.id ?? currentKey}:${tiles.map((x) => `${x.report_id}/${x.span}`).join(',')}`
  useEffect(() => {
    setLayout(tiles.map((x) => ({ report_id: x.report_id, span: x.span })))
    // eslint-disable-next-line react-hooks/exhaustive-deps -- sig is the dashboard and its tiles
  }, [sig])
  useEffect(() => { setEditing(false); setShareOpen(false) }, [currentKey])
  useEffect(() => {
    if (!shareOpen) return
    const close = (e: MouseEvent) => { if (shareRef.current && !shareRef.current.contains(e.target as Node)) setShareOpen(false) }
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') setShareOpen(false) }
    document.addEventListener('mousedown', close)
    window.addEventListener('keydown', key)
    return () => { document.removeEventListener('mousedown', close); window.removeEventListener('keydown', key) }
  }, [shareOpen])

  const canArrange = current !== null && (current.role === 'owner' || current.role === 'editor')
  const isOwner = current?.role === 'owner'
  const readOnlyWhy = current?.template_role ? t('dash.templateReadOnly') : t('dash.viewerReadOnly')
  const hasOwn = list.some((d) => d.role === 'owner')
  const name = current ? nameOf(current) : t('dash.mine')

  const persist = async (next: Layout) => {
    if (!current) return
    const prev = layout
    setLayout(next)
    const r = await saveLayoutAction({ dashboard: current.id, tiles: next.map((x, i) => ({ report_id: x.report_id, position: i, span: x.span })) })
    if (!r.ok) { setLayout(prev); flash(te(r.code)) }
  }
  const move = (i: number, d: number) => {
    const j = i + d
    if (j < 0 || j >= layout.length) return
    const next = [...layout];
    [next[i], next[j]] = [next[j]!, next[i]!]
    void persist(next)
  }
  const resize = (i: number, d: number) => {
    const span = Math.max(3, Math.min(12, layout[i]!.span + d * 2))
    if (span === layout[i]!.span) return
    void persist(layout.map((x, j) => (j === i ? { ...x, span } : x)))
  }

  const duplicate = async () => {
    if (!current) return
    const copy = t('dash.copyName', { name })
    setBusy(true)
    const r = await duplicateDashboardAction({ dashboard: current.id, name: copy })
    setBusy(false)
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('dash.duplicated', { name: copy }))
    router.push(`/insights?dashboard=${r.id}` as Route)
  }

  const drill = (tile: Tile) => (row: ResultRow, label: string) => {
    const def = Definition.safeParse(tile.definition)
    if (!def.success || !tile.definition.group_by) return
    onDrill({ def: def.data, segment: segmentOf(row), title: t('drill.title', { report: tile.name, segment: label }) })
  }

  const ordered = layout.map((l) => ({ l, tile: tiles.find((x) => x.report_id === l.report_id) })).filter((x): x is { l: Layout[number]; tile: Tile } => !!x.tile)

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <select aria-label={t('dash.pick')} value={currentKey} onChange={(e) => router.push(`/insights?dashboard=${e.target.value}` as Route)}
          className="h-9 max-w-full rounded-10 border border-ink bg-surface px-[10px] text-13 font-bold">
          {list.map((d) => <option key={d.id} value={d.id}>{nameOf(d)}</option>)}
          {!hasOwn ? <option value="mine">{t('dash.mine')}</option> : null}
        </select>
        <button type="button" onClick={() => setEditing(!editing)} disabled={!canArrange} title={canArrange ? undefined : readOnlyWhy} aria-pressed={editing}
          className={`${btnTool} ${editing ? 'border-ink bg-highlight' : 'border-line'}`}>{editing ? t('dash.done') : t('dash.arrange')}</button>
        <button type="button" onClick={duplicate} disabled={!current || busy} className={`${btnTool} border-line`}>{t('dash.duplicate')}</button>
        <div ref={shareRef} className="relative">
          <button type="button" onClick={() => setShareOpen(!shareOpen)} disabled={!isOwner} title={isOwner ? undefined : readOnlyWhy} aria-expanded={shareOpen}
            className={`${btnTool} border-line`}>{t('dash.share')}</button>
          {shareOpen && current ? <SharePopover dashboard={current.id} shares={current.shares ?? []} pickers={pickers} meId={rights.meId} /> : null}
        </div>
        <span className="flex-1" />
        <button type="button" disabled title={t('dash.exportNotYet')} className={`${btnTool} border-line`}>{t('dash.export')}</button>
        <button type="button" onClick={onAddReport} disabled={!rights.see} title={rights.see ? undefined : t('noAccess')}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-55">{t('dash.addReport')}</button>
      </div>

      {ordered.length === 0 ? (
        <div className="rounded-20 border border-line bg-surface px-6 py-10 text-center">
          <b className="text-14">{t('dash.empty')}</b>
          <p className="m-0 mt-1 text-12.5 text-muted">{canArrange || !current ? t('dash.emptyHint') : t('dash.emptyHintRead')}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-12">
          {ordered.map(({ l, tile }, i) => (
            <div key={tile.report_id} className={`${SPAN[l.span] ?? 'md:col-span-6'} flex min-w-0 flex-col gap-[10px] rounded-20 border bg-surface px-4 py-[14px] ${editing ? 'border-line-strong' : 'border-line'}`}>
              <div className="flex items-start justify-between gap-2">
                <span className="flex min-w-0 flex-col">
                  <b className="text-13.5">{tile.name}</b>
                  <span className="text-11.5 text-muted">{subOf(tile.definition)}</span>
                </span>
                {editing ? (
                  <span className="flex flex-none gap-[3px]">
                    {([['←', () => move(i, -1), 'left', 'text-11'], ['→', () => move(i, 1), 'right', 'text-11'], ['−', () => resize(i, -1), 'narrower', 'text-12'], ['+', () => resize(i, 1), 'wider', 'text-12']] as const).map(([g, fn, k, size]) => (
                      <button key={k} type="button" onClick={fn} aria-label={t(`dash.${k}`, { name: tile.name })} className={`h-6 w-6 cursor-pointer rounded-7 border border-line bg-transparent p-0 ${size}`}>{g}</button>
                    ))}
                  </span>
                ) : null}
              </div>
              {'error' in tile.result ? (
                <div className="text-12.5 text-muted">{tile.result.error === 'forbidden' ? t('noAccess') : tile.result.error === 'module_off' ? te('module_off') : t('tile.failed')}</div>
              ) : (
                <>
                  <ReportChart def={tile.definition} result={tile.result} nf={nf} variant="tile" onDrill={tile.definition.group_by ? drill(tile) : undefined} />
                  {tile.result.excluded_currency ? <span className="text-11.5 text-muted">{t('tile.excluded', { count: tile.result.excluded_currency })}</span> : null}
                </>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
