'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { Board as BoardData, Card, DealBundle, DealsBase, Filter, SavedView } from '@/lib/data/deals'
import type { RpcCode } from '@/lib/rpc'
import { archiveDeals, deleteDeals, fetchBoard, fetchDeal, moveDeal, setPref, setStatus } from '../actions'
import { canEditDeal, VIEWS, type Cond, type Modal, type Rights, type View } from './shared'
import { Board } from './Board'
import { ListView } from './ListView'
import { ForecastView } from './ForecastView'
import { ArchiveView } from './ArchiveView'
import { ProductsView } from './ProductsView'
import { DealDrawer } from './DealDrawer'
import { DealModal } from './DealModal'
import { AdvancedFilter } from './AdvancedFilter'

type Props = {
  base: DealsBase
  rights: Rights
  nf: NumberFormat
  initialPipeline: string
  initialShowClosed: boolean
  initialBoard: BoardData | null
  initialDeal: DealBundle | null
  initialDealId: string | null
}

export type Status = 'open' | 'won' | 'lost' | 'all'

/** The advanced filter's rows as rec_list filters (app.filter_sql): rows that cannot be read yet are skipped. */
function condFilters(conds: Cond[], labels: DealsBase['labels']): Filter[] {
  const out: Filter[] = []
  for (const c of conds) {
    const val = c.val.trim()
    if (!val) continue
    if (c.field === 'label') {
      const ids = labels.filter((l) => (c.op === 'is' ? l.name.toLowerCase() === val.toLowerCase() : l.name.toLowerCase().includes(val.toLowerCase()))).map((l) => l.id)
      out.push({ f: 'labels', op: 'has', v: ids })
      continue
    }
    const op = { is: 'eq', gt: 'gt', lt: 'lt', contains: 'contains' }[c.op]
    if (c.field === 'value') {
      const n = Number(val.replace(/\s/g, '').replace(',', '.'))
      if (c.op !== 'contains' && !Number.isFinite(n)) continue
      out.push({ f: 'value', op, v: c.op === 'contains' ? val : n })
    } else {
      out.push({ f: 'source', op, v: val })
    }
  }
  return out
}

export function DealsScreen({ base, rights, nf, initialPipeline, initialShowClosed, initialBoard, initialDeal, initialDealId }: Props) {
  const t = useTranslations('deals')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const err = useCallback((code: RpcCode) => flash(te(code)), [flash, te])

  const [view, setView] = useState<View>('pipeline')
  const [pipelineId, setPipelineId] = useState(initialPipeline)
  const [owner, setOwner] = useState('')
  const [label, setLabel] = useState('')
  const [status, setStatusFilter] = useState<Status>('open')
  const [showClosed, setShowClosed] = useState(initialShowClosed)
  const [conds, setConds] = useState<Cond[]>([])
  const [advOpen, setAdvOpen] = useState(false)
  const [saved, setSaved] = useState<SavedView[]>(base.views.views)
  const [board, setBoard] = useState<BoardData | null>(initialBoard)
  const [dragId, setDragId] = useState<string | null>(null)
  const [modal, setModal] = useState<Modal | null>(null)
  const [rev, setRev] = useState(0)
  const refresh = useCallback(() => setRev((r) => r + 1), [])

  const pipeline = base.pipelines.find((p) => p.id === pipelineId) ?? base.pipelines[0]!
  const stageName = useMemo(() => new Map(base.pipelines.flatMap((p) => p.stages.map((s) => [s.id, s.name] as const))), [base.pipelines])

  // ---- filters: one set for the board, the list and the forecast («Same result in pipeline, list and forecast»)
  const [debounced, setDebounced] = useState<Cond[]>([])
  useEffect(() => { const h = setTimeout(() => setDebounced(conds), 300); return () => clearTimeout(h) }, [conds])
  const filters = useMemo<Filter[]>(() => [
    ...(owner ? [{ f: 'owner_id', op: 'eq', v: owner }] : []),
    ...(label ? [{ f: 'labels', op: 'has', v: [label] }] : []),
    ...condFilters(debounced, base.labels),
  ], [owner, label, debounced, base.labels])
  const statusFilters = useMemo<Filter[]>(() => (!showClosed && (status === 'won' || status === 'lost') ? [{ f: 'status', op: 'eq', v: status }] : []), [showClosed, status])
  const boardFilters = useMemo(() => [...filters, ...statusFilters], [filters, statusFilters])
  // the forecast leaves lost deals out itself; open and won follow the status filter as everywhere else
  const forecastFilters = useMemo<Filter[]>(() => [...filters, ...(!showClosed && status !== 'all' ? [{ f: 'status', op: 'eq', v: status }] : [])], [filters, showClosed, status])
  const closed = showClosed || status !== 'open'
  const listStatus: Status = showClosed ? 'all' : status
  const key = JSON.stringify([pipelineId, boardFilters, closed])

  // ---- the board (also the summary line in every view)
  const firstBoard = useRef(true)
  const boardSeq = useRef(0)
  useEffect(() => {
    if (firstBoard.current && initialBoard && rev === 0 && key === JSON.stringify([initialPipeline, [], initialShowClosed])) { firstBoard.current = false; return }
    firstBoard.current = false
    const n = ++boardSeq.current
    void fetchBoard({ pipeline: pipelineId, filters: boardFilters, closed }).then((r) => {
      if (n !== boardSeq.current) return
      if (r.ok) setBoard(r.board)
      else err(r.code)
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- key covers pipeline, filters and closed
  }, [key, rev])

  // ---- the drawer follows ?deal=<id>
  const params = useSearchParams()
  const dealId = params.get('deal') ?? null
  const [bundle, setBundle] = useState<DealBundle | null>(initialDeal)
  const dealSeq = useRef(0)
  const firstDeal = useRef(true)
  useEffect(() => {
    if (!dealId) { setBundle(null); return }
    if (firstDeal.current && initialDeal && dealId === initialDealId && rev === 0) { firstDeal.current = false; return }
    firstDeal.current = false
    const n = ++dealSeq.current
    void fetchDeal(dealId).then((r) => {
      if (n !== dealSeq.current) return
      if (r.ok) setBundle(r.deal)
      else { err(r.code); setBundle(null) }
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- initial values are read once
  }, [dealId, rev])

  const openDeal = useCallback((id: string) => {
    const u = new URL(window.location.href)
    u.searchParams.set('deal', id)
    window.history.pushState(null, '', u.pathname + u.search)
  }, [])
  const closeDeal = useCallback(() => {
    const u = new URL(window.location.href)
    u.searchParams.delete('deal')
    window.history.pushState(null, '', u.pathname + u.search)
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (modal) setModal(null)
      else if (dealId) closeDeal()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [modal, dealId, closeDeal])

  // ---- moving a deal: the board, the drawer's stage bar and the required-field modal share this
  const move = useCallback(async (d: Pick<Card, 'id' | 'version' | 'owner_id' | 'stage_id'>, stage: string, followers = 0) => {
    if (!canEditDeal(rights, d)) { flash(t('flash.viewOnlyMove')); return }
    if (d.stage_id === stage) return
    setBoard((b) => (b ? { ...b, cards: b.cards.map((c) => (c.id === d.id ? { ...c, stage_id: stage } : c)) } : b))
    const r = await moveDeal({ id: d.id, stage, version: d.version })
    if (!r.ok) { err(r.code); refresh(); return }
    if (r.missing && r.missing.length) {
      setModal({ kind: 'required', id: d.id, stage, stageName: stageName.get(stage) ?? '', version: d.version, missing: r.missing })
      refresh()
      return
    }
    flash(followers > 0 ? t('flash.movedNotified', { stage: stageName.get(stage) ?? '' }) : t('flash.moved', { stage: stageName.get(stage) ?? '' }))
    refresh()
  }, [rights, flash, t, err, refresh, stageName])

  // ---- the drop bar (Won, Lost, Archive, Delete)
  const dragged = () => board?.cards.find((c) => c.id === dragId) ?? null
  const dropWon = async (c: Card) => {
    const r = await setStatus({ id: c.id, status: 'won', version: c.version })
    if (!r.ok) return err(r.code)
    flash(t('flash.won', { title: c.title }))
    refresh()
  }
  const dropLost = (c: Card) => { openDeal(c.id); setModal({ kind: 'lost', id: c.id, version: c.version }) }
  const dropArchive = async (c: Card) => {
    const r = await archiveDeals({ ids: [c.id], archived: true })
    if (!r.ok) return err(r.code)
    flash(t('flash.archived'))
    refresh()
  }
  const dropDelete = async (c: Card) => {
    const r = await deleteDeals({ ids: [c.id] })
    if (!r.ok) return err(r.code)
    flash(t('flash.deleted'))
    refresh()
  }

  const pickPipeline = (id: string) => { setPipelineId(id); void setPref({ key: 'pipeline', value: id }) }
  const toggleClosed = () => { const v = !showClosed; setShowClosed(v); void setPref({ key: 'show_closed', value: v }) }

  // ---- summary (the selected pipeline's cards, as the design's inPl)
  const cards = board?.cards ?? []
  const sum = cards.reduce((a, c) => a + c.value, 0)
  const weighted = cards.reduce((a, c) => a + (c.value * c.probability) / 100, 0)
  const capacity = board?.capacity === 'unlimited' || !board?.capacity ? t('summary.unlimited') : board.capacity

  const quick: { key: string; label: string; value: string; set: (v: string) => void; opts: { v: string; n: string }[]; changed: boolean }[] = [
    { key: 'owner', label: t('quick.owner'), value: owner, set: setOwner, changed: owner !== '', opts: [{ v: '', n: t('quick.everyone') }, ...base.staff.map((s) => ({ v: s.id, n: s.name }))] },
    { key: 'label', label: t('quick.label'), value: label, set: setLabel, changed: label !== '', opts: [{ v: '', n: t('quick.anyLabel') }, ...base.labels.map((l) => ({ v: l.id, n: l.name }))] },
    { key: 'status', label: t('quick.status'), value: status, set: (v) => setStatusFilter(v as Status), changed: status !== 'open', opts: (['open', 'won', 'lost', 'all'] as const).map((s) => ({ v: s, n: t(`status.${s}`) })) },
  ]

  return (
    <div className="flex flex-col gap-3 px-4 pb-[60px] pt-[18px] text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div role="tablist" aria-label={t('views.label')} className="flex rounded-11 bg-tile p-[3px]">
          {VIEWS.map((v) => (
            <button
              key={v}
              type="button"
              role="tab"
              aria-selected={view === v}
              onClick={() => setView(v)}
              className={`cursor-pointer rounded-8 border-none px-[13px] py-[7px] text-12.5 ${view === v ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
            >
              {t(`views.${v}`)}
            </button>
          ))}
        </div>
        <select
          aria-label={t('quick.pipeline')}
          value={pipelineId}
          onChange={(e) => pickPipeline(e.target.value)}
          className="h-9 rounded-10 border border-ink bg-surface px-[10px] text-13 font-bold text-ink"
        >
          {base.pipelines.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        {quick.map((f) => (
          <label key={f.key} className={`flex h-[34px] items-center gap-[5px] rounded-10 border bg-surface pl-[10px] pr-1 text-12 text-muted ${f.changed ? 'border-ink' : 'border-line'}`}>
            {f.label}
            <select value={f.value} onChange={(e) => f.set(e.target.value)} className="border-none bg-transparent text-12.5 font-semibold text-ink">
              {f.opts.map((o) => <option key={o.v} value={o.v}>{o.n}</option>)}
            </select>
          </label>
        ))}
        <AdvancedFilter
          open={advOpen}
          setOpen={setAdvOpen}
          conds={conds}
          setConds={setConds}
          saved={saved}
          onSave={() => setModal({ kind: 'saveFilter' })}
        />
        <button
          type="button"
          role="switch"
          aria-checked={showClosed}
          onClick={toggleClosed}
          className="flex h-[34px] cursor-pointer items-center gap-[7px] rounded-10 border border-line bg-transparent px-[11px] text-12.5 font-semibold"
        >
          <span className={`relative h-4 w-[26px] rounded-999 ${showClosed ? 'bg-ink' : 'bg-line-strong'}`}>
            <span className="absolute top-[2px] h-3 w-3 rounded-999 bg-surface" style={{ left: showClosed ? 12 : 2 }} />
          </span>
          {t('quick.wonLost')}
        </button>
        <span className="flex-1" />
        {rights.add ? (
          <button type="button" onClick={() => setModal({ kind: 'new' })} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">
            {t('newDeal')}
          </button>
        ) : null}
      </div>

      <div className="flex flex-wrap items-center gap-[14px] text-12 text-muted">
        <span>
          {t.rich('summary.line', {
            count: cards.length,
            value: money(sum, nf),
            weighted: money(weighted, nf),
            b: (c) => <b className="text-ink">{c}</b>,
          })}
        </span>
        <span>{t.rich('summary.capacity', { capacity, b: (c) => <b className="text-ink">{c}</b> })}</span>
        <span className="flex gap-[10px]">
          <span>◷ {t('legend.planned')}</span>
          <span className="text-danger">! {t('legend.overdue')}</span>
          <span className="text-warn-ink">⚠ {t('legend.noNext')}</span>
        </span>
        {rights.readOnly ? <span className="rounded-999 bg-peach px-[10px] py-[3px] font-bold text-rust-ink">{t('readOnly')}</span> : null}
      </div>

      {view === 'pipeline' ? (
        <Board
          pipeline={pipeline}
          board={board}
          labels={base.labels}
          rights={rights}
          nf={nf}
          prefs={base.views.prefs}
          dragId={dragId}
          setDragId={setDragId}
          onOpen={openDeal}
          onMove={(c, stage) => void move(c, stage)}
          drops={{ won: dropWon, lost: dropLost, archive: dropArchive, del: rights.del ? dropDelete : null }}
          dragged={dragged}
        />
      ) : null}
      {view === 'list' ? (
        <ListView
          base={base}
          pipeline={pipeline}
          filters={filters}
          status={listStatus}
          rights={rights}
          nf={nf}
          rev={rev}
          refresh={refresh}
          onOpen={openDeal}
          stageName={stageName}
        />
      ) : null}
      {view === 'forecast' ? (
        <ForecastView pipelineId={pipelineId} filters={forecastFilters} rights={rights} nf={nf} rev={rev} refresh={refresh} onOpen={openDeal} stageName={stageName} />
      ) : null}
      {view === 'archive' ? <ArchiveView rights={rights} nf={nf} rev={rev} refresh={refresh} stageName={stageName} /> : null}
      {view === 'products' ? <ProductsView rights={rights} nf={nf} rev={rev} onAdd={() => setModal({ kind: 'product' })} /> : null}

      {dealId && bundle && bundle.detail.id === dealId ? (
        <DealDrawer
          bundle={bundle}
          base={base}
          rights={rights}
          nf={nf}
          onClose={closeDeal}
          onChanged={refresh}
          onMove={(stage) => void move(bundle.detail, stage, bundle.detail.followers.length)}
          onLost={() => setModal({ kind: 'lost', id: bundle.detail.id, version: bundle.detail.version })}
          onNextStep={(subject) => setModal({ kind: 'next', dealId: bundle.detail.id, subject })}
        />
      ) : null}

      {modal ? (
        <DealModal
          modal={modal}
          setModal={setModal}
          base={base}
          pipeline={pipeline}
          conds={conds}
          onCreated={(id) => { refresh(); openDeal(id) }}
          onSaved={(v) => setSaved((s) => [...s, v])}
          onChanged={refresh}
        />
      ) : null}
    </div>
  )
}
