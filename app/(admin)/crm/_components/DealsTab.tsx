'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { RpcCode } from '@/lib/rpc'
import type { Board, Card } from '@/lib/data/deals'
import type { CrmDeal, CrmDeals } from '@/lib/data/simple-crm'
import { canEditDeal, NEXT_STEP, STAGE_VIZ, summarise, type CrmRights } from '@/lib/data/simple-crm-shared'
import { fetchBoard, moveDeal, setStatus, type MissingField } from '../../deals/actions'
import { fetchCrmDeal } from '../actions'
import { DealDrawer } from './DealDrawer'
import { NewDealModal } from './NewDealModal'
import { LostModal } from './LostModal'
import { RequiredModal } from './RequiredModal'

type Movable = Pick<Card, 'id' | 'title' | 'version' | 'owner_id' | 'stage_id'>
type Prompt =
  | { kind: 'lost'; deal: Movable }
  | { kind: 'required'; deal: Movable; stage: string; stageName: string; missing: MissingField[] }

/**
 * The Deals tab (SimpleCRM.dc.html v.deals): the summary line, the first pipeline's stages as columns of open deals,
 * the Won and Lost drop zones, the deal drawer at ?deal=<id>, and the new-deal dialog. A card moves by HTML5
 * drag-drop (deal_move) or from the drawer's stage steps; Won and Lost go through deal_status.
 */
export function DealsTab({ rights, nf, tz, data, blocked, initialDeal, creating, setCreating }: {
  rights: CrmRights
  nf: NumberFormat
  tz: string
  data: CrmDeals | null
  blocked: 'moduleOff' | 'failed' | null
  initialDeal: CrmDeal | null
  creating: boolean
  setCreating: (v: boolean) => void
}) {
  const t = useTranslations('simpleCrm')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const err = useCallback((code: RpcCode) => flash(te(code)), [flash, te])
  const pipeline = data?.pipeline ?? null

  const [board, setBoard] = useState<Board | null>(data?.board ?? null)
  const [dragId, setDragId] = useState<string | null>(null)
  const [prompt, setPrompt] = useState<Prompt | null>(null)
  const seq = useRef(0)
  const refresh = useCallback(async () => {
    if (!pipeline) return
    const n = ++seq.current
    const r = await fetchBoard({ pipeline: pipeline.id, filters: [], closed: true })
    if (n !== seq.current) return
    if (r.ok) setBoard(r.board)
    else err(r.code)
  }, [pipeline, err])

  // ---- the drawer follows ?deal=<id> (the address a notification or a colleague's link carries)
  const params = useSearchParams()
  const dealId = params.get('deal')
  const [deal, setDeal] = useState<CrmDeal | null>(initialDeal)
  const dealSeq = useRef(0)
  const loadDeal = useCallback(async (id: string) => {
    const n = ++dealSeq.current
    const r = await fetchCrmDeal(id)
    if (n !== dealSeq.current) return
    if (r.ok) setDeal(r.deal)
    else { err(r.code); setDeal(null) }
  }, [err])
  useEffect(() => {
    if (!dealId) { setDeal(null); return }
    if (deal?.detail.id === dealId) return
    void loadDeal(dealId)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the deal in hand answers for its own id
  }, [dealId])
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

  const stages = useMemo(() => board?.stages ?? pipeline?.stages ?? [], [board, pipeline])
  // a deal opened by its address may sit in another pipeline: its own stages name the step
  const stageName = useCallback((id: string) => (stages.find((s) => s.id === id) ?? deal?.detail.stages?.find((s) => s.id === id))?.name ?? '', [stages, deal])
  // after a change: the board again, and the drawer when it shows that deal
  const after = useCallback(async (id: string) => {
    await refresh()
    if (new URL(window.location.href).searchParams.get('deal') === id) await loadDeal(id)
  }, [refresh, loadDeal])

  // ---- moving: the board, the drawer's steps and the required-fields dialog share this
  const move = useCallback(async (d: Movable, stage: string) => {
    if (!canEditDeal(rights, d)) { flash(t(rights.readOnly ? 'flash.viewOnly' : 'flash.notYours')); return }
    if (d.stage_id === stage) return
    setBoard((b) => (b ? { ...b, cards: b.cards.map((c) => (c.id === d.id ? { ...c, stage_id: stage } : c)) } : b))
    const r = await moveDeal({ id: d.id, stage, version: d.version })
    if (!r.ok) { err(r.code); void after(d.id); return }
    if (r.missing && r.missing.length) {
      setPrompt({ kind: 'required', deal: d, stage, stageName: stageName(stage), missing: r.missing })
      void after(d.id)
      return
    }
    flash(t('flash.moved', { stage: stageName(stage) }))
    void after(d.id)
  }, [rights, flash, t, err, after, stageName])

  // ---- won and lost: a reason first when Settings requires one (lost_reason_required)
  const close = useCallback(async (d: Movable, status: 'won' | 'lost', reason?: string) => {
    if (!canEditDeal(rights, d)) { flash(t(rights.readOnly ? 'flash.viewOnly' : 'flash.notYours')); return false }
    if (status === 'lost' && data?.lostRequired && !reason) { setPrompt({ kind: 'lost', deal: d }); return false }
    const r = await setStatus({ id: d.id, status, reason, version: d.version })
    if (!r.ok) {
      if (r.detail === 'lost_reason:required') { setPrompt({ kind: 'lost', deal: d }); return false }
      err(r.code)
      return false
    }
    flash(status === 'won' ? t('flash.won', { title: d.title }) : t('flash.lost'))
    void after(d.id)
    return true
  }, [rights, data?.lostRequired, flash, t, err, after])

  if (blocked || !data) return <Notice text={t(blocked === 'moduleOff' ? 'empty.moduleOff' : 'empty.failed')} />
  if (!pipeline || !board) return <Notice text={t('empty.noPipeline')} />

  const cards = board.cards
  const open = cards.filter((c) => c.status === 'open')
  const sum = summarise(cards, tz)
  const allow = (e: React.DragEvent) => e.preventDefault()
  const dropOn = (fn: (c: Card) => void) => (e: React.DragEvent) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain') || dragId
    setDragId(null)
    const c = cards.find((x) => x.id === id)
    if (c) fn(c)
  }
  const b = (c: React.ReactNode) => <b className="whitespace-nowrap text-ink">{c}</b>

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap gap-x-4 gap-y-2 whitespace-nowrap text-12.5 text-muted">
        <span>{t.rich('summary.open', { count: sum.count, b })}</span>
        <span>{t.rich('summary.value', { value: money(sum.value, nf), b })}</span>
        <span>{t.rich('summary.weighted', { value: money(sum.weighted, nf), b })}</span>
        <span>{t.rich('summary.won', { value: money(sum.wonValue, nf), b: (c) => <b className="whitespace-nowrap text-link">{c}</b> })}</span>
        <span className="text-faint">{t('summary.hint')}</span>
      </div>

      <div className="flex items-start gap-[10px] overflow-x-auto pb-[10px]">
        {stages.map((s, i) => {
          const cs = open.filter((c) => c.stage_id === s.id)
          return (
            <div
              key={s.id}
              onDragOver={allow}
              onDrop={dropOn((c) => void move(c, s.id))}
              className="flex min-h-[380px] flex-[0_0_240px] flex-col gap-2 rounded-18 bg-tile p-2"
            >
              <div className="px-[6px] pb-2 pt-[6px]" style={{ borderBottom: `3px solid ${STAGE_VIZ[i % STAGE_VIZ.length]}` }}>
                <div className="flex justify-between">
                  <b className="text-13">{s.name}</b>
                  <span className="whitespace-nowrap text-11 text-muted">{s.probability} %</span>
                </div>
                <div className="mt-[2px] text-12 text-muted"><b className="text-ink">{money(cs.reduce((a, c) => a + c.value, 0), nf)}</b> · {cs.length}</div>
              </div>
              {cs.map((c) => {
                const next = NEXT_STEP[c.act]
                return (
                  <div
                    key={c.id}
                    role="button"
                    tabIndex={0}
                    draggable
                    aria-label={c.title}
                    onDragStart={(e) => {
                      if (!canEditDeal(rights, c)) { e.preventDefault(); flash(t(rights.readOnly ? 'flash.viewOnly' : 'flash.notYours')); return }
                      e.dataTransfer.setData('text/plain', c.id)
                      e.dataTransfer.effectAllowed = 'move'
                      setDragId(c.id)
                    }}
                    onDragEnd={() => setDragId(null)}
                    onClick={() => openDeal(c.id)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openDeal(c.id) } }}
                    className={`flex cursor-pointer flex-col gap-[5px] rounded-14 border bg-surface px-[11px] py-[10px] ${next.border}`}
                  >
                    <b className="text-12.5 leading-[1.3]">{c.title}</b>
                    {c.organization ? <span className="text-11.5 text-muted">{c.organization}</span> : null}
                    <span className="flex items-center justify-between text-11.5">
                      <b className="whitespace-nowrap">{money(c.value, nf, c.currency)}</b>
                      <span className="flex items-center gap-[6px]">
                        <span className={next.ink}>{t(`next.${next.key}`)}</span>
                        <span title={c.owner?.name ?? undefined} className="flex h-5 w-5 items-center justify-center rounded-999 bg-tile text-9.5 font-bold">
                          {c.owner?.initials ?? ''}
                        </span>
                      </span>
                    </span>
                  </div>
                )
              })}
            </div>
          )
        })}
        <div className="flex flex-[0_0_200px] flex-col gap-2">
          <div onDragOver={allow} onDrop={dropOn((c) => void close(c, 'won'))} className="flex h-[120px] flex-col items-center justify-center gap-1 rounded-18 border-2 border-dashed border-link bg-ok-bg text-ok-ink">
            <b className="text-14">{t('zone.won')}</b>
            <span className="text-12">{t('zone.count', { count: sum.wonCount })}</span>
          </div>
          <div onDragOver={allow} onDrop={dropOn((c) => void close(c, 'lost'))} className="flex h-[120px] flex-col items-center justify-center gap-1 rounded-18 border-2 border-dashed border-coral bg-peach text-rust-ink">
            <b className="text-14">{t('zone.lost')}</b>
            <span className="text-12">{t('zone.count', { count: sum.lostCount })}</span>
          </div>
        </div>
      </div>

      {dealId && deal && deal.detail.id === dealId ? (
        <DealDrawer
          deal={deal}
          rights={rights}
          nf={nf}
          onClose={closeDeal}
          onMove={(stage) => void move(deal.detail, stage)}
          onStatus={async (status) => { if (await close(deal.detail, status)) closeDeal() }}
          onNoteSaved={() => void after(deal.detail.id)}
        />
      ) : null}

      {creating ? (
        <NewDealModal
          pipelineId={pipeline.id}
          stages={stages}
          onClose={() => setCreating(false)}
          onCreated={() => { setCreating(false); void refresh() }}
        />
      ) : null}

      {prompt?.kind === 'lost' ? (
        <LostModal
          reasons={data.lostReasons}
          onClose={() => setPrompt(null)}
          onSubmit={async (reason) => {
            const ok = await close(prompt.deal, 'lost', reason)
            if (ok) { setPrompt(null); if (dealId === prompt.deal.id) closeDeal() }
            return ok
          }}
        />
      ) : null}
      {prompt?.kind === 'required' ? (
        <RequiredModal
          deal={prompt.deal}
          stage={prompt.stage}
          stageName={prompt.stageName}
          missing={prompt.missing}
          onClose={() => setPrompt(null)}
          onMoved={(missing) => {
            if (missing) { setPrompt({ ...prompt, missing }); return }
            setPrompt(null)
            flash(t('flash.moved', { stage: prompt.stageName }))
            void after(prompt.deal.id)
          }}
        />
      ) : null}
    </div>
  )
}

/** The tab's honest empty or unavailable state, in the design's card. */
function Notice({ text }: { text: string }) {
  return <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{text}</div>
}
