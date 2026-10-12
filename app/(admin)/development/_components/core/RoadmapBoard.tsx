'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Roadmap, RoadmapItem } from '@/lib/data/dev-core'
import { money, type NumberFormat } from '@/lib/format'
import { addRoadmapItem, archiveRoadmapItem, linkEvidence, moveRoadmapItem, promote, setRoadmapItem } from '../../core-actions'
import { LANES, LANE_RULE, STATUSES, type Lane } from './logic'
import { c, Modal, useRun, type ProductInfo } from './kit'

/** The three lanes, their cards and «Promote from» (DevHub.dc.html, v.roadmap). */
export function RoadmapBoard({ data, products, filter, nf }: { data: Roadmap; products: ProductInfo[]; filter: string | null; nf: NumberFormat }) {
  const t = useTranslations('devCore.roadmap')
  const { run, pending } = useRun()
  const [editing, setEditing] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [promoted, setPromoted] = useState<Record<string, string>>({})
  const product = (k: string) => products.find((p) => p.key === k) ?? { key: k, name: k, color: '#F2EAD6' }
  const item = editing ? data.items.find((i) => i.id === editing) ?? null : null

  const sources = (['feature_request', 'experiment', 'seo_plan'] as const).map((k) => ({ k, cand: data.candidates[k], done: promoted[k] ?? null }))
    .filter((s) => s.cand || s.done)

  return (
    <>
      <div className="grid items-start gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr))]">
        {LANES.map((lane) => {
          const items = data.items.filter((i) => i.lane === lane)
          return (
            <section key={lane} aria-label={t(`lanes.${lane}`)} className="flex min-h-[300px] flex-col gap-2 rounded-18 bg-tile p-2">
              <div className={`flex justify-between border-b-[3px] px-[6px] pb-2 pt-[6px] ${LANE_RULE[lane]}`}>
                <b className="text-13.5">{t(`lanes.${lane}`)}</b>
                <span className="text-12 text-muted">{items.length}</span>
              </div>
              {items.map((i) => (
                <Card key={i.id} i={i} lane={lane} product={product(i.product)} nf={nf} canMove={data.can_add} busy={pending}
                  onEdit={() => setEditing(i.id)}
                  onMove={(to) => run(() => moveRoadmapItem({ id: i.id, lane: to, version: i.version }), () => t('moved', { title: i.title, lane: t(`lanes.${to}`) }))} />
              ))}
            </section>
          )
        })}
      </div>

      {data.can_add ? (
        <div className="flex flex-wrap items-center gap-[10px] rounded-18 border border-line bg-surface px-4 py-3">
          <b className="text-13">{t('promoteFrom')}</b>
          {sources.map(({ k, cand, done }) => (
            <button key={k} type="button" disabled={pending || !!done}
              onClick={() => cand && run(() => promote({ kind: k, ref: cand.id }), (r) => ('title' in r ? t('promotedToast') : null),
                                         (r) => { if ('title' in r) setPromoted((p) => ({ ...p, [k]: r.title })) })}
              className={`h-[30px] cursor-pointer whitespace-nowrap rounded-9 border px-[11px] text-12 font-semibold text-ink disabled:cursor-default ${done ? 'border-link bg-ok-bg' : 'border-line-strong bg-transparent'}`}>
              {done ? `✓ ${done}` : t(`source.${k}`, { title: cand!.title })}
            </button>
          ))}
          {!sources.length ? <span className="text-12 text-muted">{t('nothingToPromote')}</span> : null}
          <span className="flex-1" />
          <button type="button" onClick={() => setAdding(true)} className={c.dashed}>{t('newItem')}</button>
        </div>
      ) : null}

      {item ? <EditItem key={item.id} i={item} data={data} products={products} onClose={() => setEditing(null)} /> : null}
      {adding ? <NewItem products={products} preset={filter} onClose={() => setAdding(false)} /> : null}
    </>
  )
}

/** a roadmap card: title and product, goal, evidence chips, progress in Now, ← and → */
function Card({ i, lane, product, nf, canMove, busy, onEdit, onMove }: {
  i: RoadmapItem; lane: Lane; product: ProductInfo; nf: NumberFormat; canMove: boolean; busy: boolean; onEdit: () => void; onMove: (to: Lane) => void
}) {
  const t = useTranslations('devCore.roadmap')
  const e = i.evidence
  const chips: string[] = []
  if (e.requests) chips.push(t('ev.votes', { n: e.votes ?? 0 }))
  if (e.tickets) chips.push(t('ev.tickets', { n: e.tickets }))
  if (e.deals) chips.push(e.deals.mrr !== null ? t('ev.dealsMrr', { n: e.deals.n, mrr: money(e.deals.mrr, nf, e.deals.currency ?? 'NOK') }) : t('ev.deals', { n: e.deals.n }))
  for (const x of e.experiments ?? []) chips.push(t('ev.experiment', { state: t(`expState.${x.outcome ?? x.stage}`) }))
  for (const x of e.seo ?? []) chips.push(t('ev.seo', { stage: t(`seoStage.${x.stage}`) }))
  if (i.source) chips.push(t(`from.${i.source}`))
  const idx = LANES.indexOf(lane)
  const back = idx > 0 ? LANES[idx - 1]! : null
  const fwd = idx < LANES.length - 1 ? LANES[idx + 1]! : null
  const pct = lane === 'now' && i.work.total > 0 ? Math.round((i.work.done / i.work.total) * 100) : null
  return (
    <div className="flex flex-col gap-[6px] rounded-14 border border-line bg-surface px-3 py-[11px]">
      <div className="flex justify-between gap-2">
        <button type="button" onClick={onEdit} title={t('edit', { title: i.title })}
          className="cursor-pointer border-none bg-transparent p-0 text-left text-13 font-bold leading-[1.3] text-ink hover:underline">{i.title}</button>
        <span className="h-[18px] whitespace-nowrap rounded-999 px-2 py-px text-10.5 font-bold" style={{ background: product.color }}>{product.name}</span>
      </div>
      <span className="text-11.5 text-muted">{t('goal', { goal: i.goal ?? t('noGoal') })}</span>
      {chips.length ? (
        <span className="flex flex-wrap gap-1">
          {chips.map((x, n) => <span key={n} className="rounded-6 bg-tile px-[7px] py-[2px] text-10.5 font-bold">{x}</span>)}
        </span>
      ) : null}
      {pct !== null ? (
        <span className="flex items-center gap-[6px] text-11" title={t('progressTitle', { done: i.work.done, total: i.work.total })}>
          <span className="h-[6px] flex-1 overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-ok" style={{ width: `${pct}%` }} /></span>
          {pct} %
        </span>
      ) : null}
      {canMove ? (
        <div className="flex justify-end gap-1">
          <button type="button" disabled={!back || busy} onClick={() => back && onMove(back)} aria-label={back ? t('moveTo', { lane: t(`lanes.${back}`) }) : undefined}
            className="h-6 w-[26px] cursor-pointer rounded-7 border border-line bg-transparent text-11 text-ink disabled:cursor-default">←</button>
          <button type="button" disabled={!fwd || busy} onClick={() => fwd && onMove(fwd)} aria-label={fwd ? t('moveTo', { lane: t(`lanes.${fwd}`) }) : undefined}
            className="h-6 w-[26px] cursor-pointer rounded-7 border border-ink bg-surface text-11 text-ink disabled:cursor-default">→</button>
        </div>
      ) : null}
    </div>
  )
}

/** a new roadmap item: its product, title, goal and lane */
export function NewItem({ products, preset, onClose }: { products: ProductInfo[]; preset: string | null; onClose: () => void }) {
  const t = useTranslations('devCore.roadmap')
  const { run, pending } = useRun()
  const [product, setProduct] = useState(preset ?? products[0]?.key ?? 'sentral')
  const [title, setTitle] = useState('')
  const [goal, setGoal] = useState('')
  const [lane, setLane] = useState<Lane>('later')
  return (
    <Modal title={t('newTitle')} cta={t('add')} busy={pending || title.trim().length < 3} onClose={onClose}
      onSubmit={() => run(() => addRoadmapItem({ product, title, goal, lane }), () => t('added'), onClose)}>
      <label className={c.field}>{t('fields.product')}
        <select value={product} onChange={(e) => setProduct(e.target.value)} className={c.select}>
          {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
        </select>
      </label>
      <label className={c.field}>{t('fields.title')}<input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
      <label className={c.field}>{t('fields.goal')}<input value={goal} onChange={(e) => setGoal(e.target.value)} maxLength={200} placeholder={t('goalHint')} className={c.input} /></label>
      <label className={c.field}>{t('fields.lane')}
        <select value={lane} onChange={(e) => setLane(e.target.value as Lane)} className={c.select}>
          {LANES.map((l) => <option key={l} value={l}>{t(`lanes.${l}`)}</option>)}
        </select>
      </label>
    </Modal>
  )
}

/** a roadmap item's fields and its evidence: what links it, and what can be linked */
function EditItem({ i, data, products, onClose }: { i: RoadmapItem; data: Roadmap; products: ProductInfo[]; onClose: () => void }) {
  const t = useTranslations('devCore.roadmap')
  const ts = useTranslations('devCore.status')
  const { run, pending } = useRun()
  const [title, setTitle] = useState(i.title)
  const [goal, setGoal] = useState(i.goal ?? '')
  const [status, setStatus] = useState(i.status)
  const [owner, setOwner] = useState(i.owner?.id ?? '')
  const [request, setRequest] = useState('')
  const [ticket, setTicket] = useState('')
  const [deal, setDeal] = useState('')
  const name = products.find((p) => p.key === i.product)?.name ?? i.product
  const linkedIds = new Set(i.links.map((l) => l.ref))
  const requests = data.requests.filter((r) => r.product === i.product && !linkedIds.has(r.id))
  const deals = (data.deals ?? []).filter((d) => !linkedIds.has(d.id))
  const ticketNo = Number(ticket.replace(/^t-?/i, '').trim())
  const changed: Record<string, unknown> = {}
  if (title.trim() !== i.title) changed.title = title.trim()
  if (goal.trim() !== (i.goal ?? '')) changed.goal = goal.trim()
  if (status !== i.status) changed.status = status
  if (owner !== (i.owner?.id ?? '')) changed.owner_id = owner || null
  const link = (kind: 'feature_request' | 'ticket' | 'deal', ref: string | null, number: number | null, after: () => void) =>
    run(() => linkEvidence({ id: i.id, kind, ref, number, on: true }), () => t('linked'), after)

  return (
    <Modal title={t('editTitle', { key: i.key })} cta={data.can_add ? t('save') : null} width={560}
      busy={pending || !Object.keys(changed).length || title.trim().length < 3} onClose={onClose}
      onSubmit={() => run(() => setRoadmapItem({ id: i.id, version: i.version, patch: changed }), () => t('saved'), onClose)}
      extra={data.can_add ? (
        <button type="button" disabled={pending} className={c.small}
          onClick={() => run(() => archiveRoadmapItem({ id: i.id, version: i.version }), () => t('archived'), onClose)}>{t('archive')}</button>
      ) : null}>
      <span className="text-12 text-muted">{name}{i.spec ? ` · ${i.spec.ref}` : ''}</span>
      <label className={c.field}>{t('fields.title')}<input value={title} disabled={!data.can_add} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
      <label className={c.field}>{t('fields.goal')}<input value={goal} disabled={!data.can_add} onChange={(e) => setGoal(e.target.value)} maxLength={200} placeholder={t('goalHint')} className={c.input} /></label>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(180px,1fr))]">
        <label className={c.field}>{t('fields.status')}
          <select value={status} disabled={!data.can_add} onChange={(e) => setStatus(e.target.value as RoadmapItem['status'])} className={c.select}>
            {STATUSES.map((s) => <option key={s} value={s}>{ts(s)}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.owner')}
          <select value={owner} disabled={!data.can_add} onChange={(e) => setOwner(e.target.value)} className={c.select}>
            <option value="">{t('noOwner')}</option>
            {data.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
      </div>

      <div className="flex flex-col gap-2 border-t border-line pt-3">
        <span className={c.label}>{t('evidence')}</span>
        {i.links.length ? (
          <div className="flex flex-wrap gap-[6px]">
            {i.links.map((l) => (
              <span key={`${l.kind}-${l.ref}`} className="flex items-center gap-1 rounded-999 bg-tile py-[2px] pl-2 pr-1 text-11.5">
                {t(`kind.${l.kind}`)} {[l.label, l.title].filter(Boolean).join(' ')}
                {data.can_add ? (
                  <button type="button" aria-label={t('unlink')} title={t('unlink')} disabled={pending}
                    onClick={() => run(() => linkEvidence({ id: i.id, kind: l.kind, ref: l.ref, number: null, on: false }), () => t('unlinked'))}
                    className="h-[18px] w-[18px] cursor-pointer rounded-999 border-none bg-transparent text-11 text-ink">×</button>
                ) : null}
              </span>
            ))}
          </div>
        ) : <span className="text-12 text-muted">{t('noEvidence')}</span>}
        {data.can_add ? (
          <div className="flex flex-col gap-2">
            <div className="flex flex-wrap gap-2">
              <select value={request} onChange={(e) => setRequest(e.target.value)} aria-label={t('linkRequest')} className={`${c.select} h-[34px] flex-[1_1_220px] text-12.5`}>
                <option value="">{requests.length ? t('pickRequest') : t('noRequests')}</option>
                {requests.map((r) => <option key={r.id} value={r.id}>{r.label} {r.title}</option>)}
              </select>
              <button type="button" disabled={pending || !request} className={c.small} onClick={() => link('feature_request', request, null, () => setRequest(''))}>{t('link')}</button>
            </div>
            <div className="flex flex-wrap gap-2">
              <input value={ticket} onChange={(e) => setTicket(e.target.value)} placeholder={t('ticketHint')} aria-label={t('linkTicket')}
                className={`${c.input} h-[34px] flex-[1_1_220px] text-12.5`} />
              <button type="button" disabled={pending || !Number.isInteger(ticketNo) || ticketNo <= 0} className={c.small}
                onClick={() => link('ticket', null, ticketNo, () => setTicket(''))}>{t('link')}</button>
            </div>
            {data.deals ? (
              <div className="flex flex-wrap gap-2">
                <select value={deal} onChange={(e) => setDeal(e.target.value)} aria-label={t('linkDeal')} className={`${c.select} h-[34px] flex-[1_1_220px] text-12.5`}>
                  <option value="">{deals.length ? t('pickDeal') : t('noDeals')}</option>
                  {deals.map((d) => <option key={d.id} value={d.id}>{d.label} {d.title}</option>)}
                </select>
                <button type="button" disabled={pending || !deal} className={c.small} onClick={() => link('deal', deal, null, () => setDeal(''))}>{t('link')}</button>
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </Modal>
  )
}
