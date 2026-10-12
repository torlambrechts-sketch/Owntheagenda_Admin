'use client'

import { useId, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useTranslations } from 'next-intl'
import type { Board, WorkItem } from '@/lib/data/dev-core'
import { archiveWorkItem, moveWorkItem, saveSprint, saveWorkItem } from '../../core-actions'
import { COLUMN_RULE, KINDS, STATUSES, initials, neighbour, sprintDates, type Kind, type Status } from './logic'
import { c, Modal, useRun, type ProductInfo } from './kit'

/** the board: the sprint line, the seven columns, the cards, and their dialogs */
export function BoardView({ data, products, locale }: { data: Board; products: ProductInfo[]; locale: string }) {
  const t = useTranslations('devCore.board')
  const ts = useTranslations('devCore.status')
  const { run, pending } = useRun()
  const hint = useId()
  const [editing, setEditing] = useState<string | 'new' | null>(null)
  const [sprintOpen, setSprintOpen] = useState(false)
  const s = data.sprint
  const move = (w: WorkItem, to: Status) => {
    if (w.status === to) return
    run(() => moveWorkItem({ id: w.id, status: to, version: w.version }), () => t('moved', { key: w.key, column: ts(to) }))
  }
  const item = editing && editing !== 'new' ? data.items.find((w) => w.id === editing) ?? null : null

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap items-center gap-x-[14px] gap-y-[6px] whitespace-nowrap text-12.5 text-muted">
        {s ? (
          <>
            <span><b className="text-ink">{s.name}</b> · {sprintDates(s.starts_on, s.ends_on, locale)} · {t('day', { day: s.day, days: s.days })}</span>
            <span>{t.rich('points', { committed: s.committed, done: s.done, b: (x) => <b className="text-ink">{x}</b> })}</span>
          </>
        ) : <span>{t('noSprint')}</span>}
        <span className="flex-1" />
        {data.can_add ? (
          <span className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setSprintOpen(true)} className={c.dashed}>{s ? t('editSprint') : t('newSprint')}</button>
            <button type="button" onClick={() => setEditing('new')} className={c.dashed}>{t('newItem')}</button>
          </span>
        ) : null}
      </div>
      <span id={hint} className="sr-only">{t('keyboardHint')}</span>
      <div className="flex items-start gap-2 overflow-x-auto pb-2">
        {STATUSES.map((col) => {
          const cards = data.items.filter((w) => w.status === col)
          return (
            <section key={col} aria-label={ts(col)}
              onDragOver={(e) => { if (data.can_add) e.preventDefault() }}
              onDrop={(e) => {
                e.preventDefault()
                const w = data.items.find((x) => x.id === e.dataTransfer.getData('text/plain'))
                if (w && data.can_add) move(w, col)
              }}
              className="flex min-h-[320px] flex-[0_0_210px] flex-col gap-[7px] rounded-16 bg-tile p-[7px]">
              <div className={`flex justify-between border-b-[3px] px-[6px] pb-[7px] pt-[5px] ${COLUMN_RULE[col]}`}>
                <b className="whitespace-nowrap text-12.5">{ts(col)}</b>
                <span className="text-11.5 text-muted">{cards.length}</span>
              </div>
              {cards.map((w) => (
                <Card key={w.id} w={w} canMove={data.can_add && !pending} hint={hint} onOpen={() => setEditing(w.id)}
                  onMove={(dir) => { const to = neighbour(w.status, dir); if (to) move(w, to) }} />
              ))}
            </section>
          )
        })}
      </div>
      {!data.items.length ? <span className="text-12.5 text-muted">{t('empty')}</span> : null}
      {editing ? <EditWork key={editing} w={item} data={data} products={products} onClose={() => setEditing(null)} /> : null}
      {sprintOpen ? <EditSprint sprint={s} onClose={() => setSprintOpen(false)} /> : null}
    </div>
  )
}

/** a card (cards[]): id, kind and points, title, epic and assignee; a bug card has its own border and a link to its triage row */
function Card({ w, canMove, hint, onOpen, onMove }: { w: WorkItem; canMove: boolean; hint: string; onOpen: () => void; onMove: (dir: 1 | -1) => void }) {
  const t = useTranslations('devCore.board')
  const tk = useTranslations('devCore.kind')
  return (
    <div draggable={canMove} onDragStart={(e) => e.dataTransfer.setData('text/plain', w.id)}
      className={`flex flex-col gap-[5px] rounded-12 border bg-surface px-[10px] py-[9px] ${canMove ? 'cursor-grab' : ''} ${w.kind === 'bug' ? 'border-coral' : 'border-line'}`}>
      <span className="flex justify-between text-10.5 text-muted">
        <b className={c.mono}>{w.key}</b>
        <span className="whitespace-nowrap">{w.points !== null ? t('kindPoints', { kind: tk(w.kind), pts: w.points }) : tk(w.kind)}</span>
      </span>
      <button type="button" onClick={onOpen} aria-describedby={hint}
        onKeyDown={(e) => {
          if (!canMove || !e.altKey) return
          if (e.key === 'ArrowRight') { e.preventDefault(); onMove(1) }
          if (e.key === 'ArrowLeft') { e.preventDefault(); onMove(-1) }
        }}
        className="cursor-pointer border-none bg-transparent p-0 text-left text-12.5 font-bold leading-[1.3] text-ink">{w.title}</button>
      <span className="flex items-center justify-between gap-2 text-11">
        <span className="min-w-0 truncate text-muted" title={w.roadmap?.title}>{w.roadmap?.title ?? ''}</span>
        {w.assignee ? (
          <span title={w.assignee.name} className="flex h-5 w-5 flex-none items-center justify-center rounded-999 bg-tile text-9.5 font-bold">
            {initials(w.assignee.name, w.assignee.initials)}
          </span>
        ) : null}
      </span>
      {w.bug ? (
        <Link href={`/development?tab=bugs&prod=${w.product}#bug-${w.bug.id}` as Route} className={`${c.mono} text-11`}>{t('bugLink', { n: w.bug.number })}</Link>
      ) : null}
    </div>
  )
}

/** a work item's dialog: new, or its fields, its column (the keyboard's way to move it) and Archive */
function EditWork({ w, data, products, onClose }: { w: WorkItem | null; data: Board; products: ProductInfo[]; onClose: () => void }) {
  const t = useTranslations('devCore.board')
  const ts = useTranslations('devCore.status')
  const tk = useTranslations('devCore.kind')
  const { run, pending } = useRun()
  const [product, setProduct] = useState(w?.product ?? products[0]?.key ?? 'sentral')
  const [kind, setKind] = useState<Kind>(w?.kind ?? 'story')
  const [title, setTitle] = useState(w?.title ?? '')
  const [points, setPoints] = useState(w?.points != null ? String(w.points) : '')
  const [status, setStatus] = useState<Status>(w?.status ?? 'backlog')
  const [epic, setEpic] = useState(w?.roadmap?.id ?? '')
  const [sprint, setSprint] = useState(w?.sprint_id ?? (w ? '' : data.sprint?.id ?? ''))
  const [assignee, setAssignee] = useState(w?.assignee?.id ?? '')
  const [bug, setBug] = useState(w?.bug?.id ?? '')
  const pts = points.trim() === '' ? null : Number(points)
  const ptsOk = pts === null || (Number.isInteger(pts) && pts >= 0 && pts <= 100)
  const all: Record<string, unknown> = {
    kind, title: title.trim(), points: pts, status, roadmap_item_id: epic || null, sprint_id: sprint || null, assignee_id: assignee || null, bug_id: bug || null,
  }
  const before: Record<string, unknown> = w ? {
    kind: w.kind, title: w.title, points: w.points, status: w.status, roadmap_item_id: w.roadmap?.id ?? null, sprint_id: w.sprint_id,
    assignee_id: w.assignee?.id ?? null, bug_id: w.bug?.id ?? null,
  } : {}
  // a new item sends everything; a change sends what changed
  const values: Record<string, unknown> = w ? Object.fromEntries(Object.entries(all).filter(([k, v]) => v !== before[k])) : { ...all, product }
  const epics = data.roadmap.filter((r) => r.product === product)
  const bugs = data.bugs.filter((b) => b.product === product || b.id === w?.bug?.id)
  return (
    <Modal title={w ? t('editTitle', { key: w.key }) : t('newTitle')} cta={data.can_add ? (w ? t('save') : t('add')) : null} width={560}
      busy={pending || title.trim().length < 3 || !ptsOk || !Object.keys(values).length} onClose={onClose}
      onSubmit={() => run(() => saveWorkItem({ id: w?.id ?? null, version: w?.version ?? null, values }), (r) => ('key' in r ? (w ? t('saved') : t('added', { key: r.key })) : null), onClose)}
      extra={w && data.can_add ? (
        <button type="button" disabled={pending} className={c.small} onClick={() => run(() => archiveWorkItem({ id: w.id, version: w.version }), () => t('archived'), onClose)}>
          {t('archive')}
        </button>
      ) : null}>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <label className={c.field}>{t('fields.product')}
          <select value={product} disabled={!!w || !data.can_add} onChange={(e) => { setProduct(e.target.value); setEpic(''); setBug('') }} className={c.select}>
            {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.kind')}
          <select value={kind} disabled={!data.can_add} onChange={(e) => setKind(e.target.value as Kind)} className={c.select}>
            {KINDS.map((k) => <option key={k} value={k}>{tk(k)}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.points')}
          <input value={points} disabled={!data.can_add} inputMode="numeric" onChange={(e) => setPoints(e.target.value.replace(/[^\d]/g, '').slice(0, 3))} className={c.input} />
        </label>
      </div>
      <label className={c.field}>{t('fields.title')}<input value={title} disabled={!data.can_add} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))]">
        <label className={c.field}>{t('fields.column')}
          <select value={status} disabled={!data.can_add} onChange={(e) => setStatus(e.target.value as Status)} className={c.select}>
            {STATUSES.map((s) => <option key={s} value={s}>{ts(s)}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.assignee')}
          <select value={assignee} disabled={!data.can_add} onChange={(e) => setAssignee(e.target.value)} className={c.select}>
            <option value="">{t('nobody')}</option>
            {data.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.epic')}
          <select value={epic} disabled={!data.can_add} onChange={(e) => setEpic(e.target.value)} className={c.select}>
            <option value="">{t('noEpic')}</option>
            {epics.map((r) => <option key={r.id} value={r.id}>{r.key} {r.title}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.sprint')}
          <select value={sprint} disabled={!data.can_add} onChange={(e) => setSprint(e.target.value)} className={c.select}>
            <option value="">{t('noSprintPick')}</option>
            {data.sprints.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        <label className={c.field}>{t('fields.bug')}
          <select value={bug} disabled={!data.can_add} onChange={(e) => setBug(e.target.value)} className={c.select}>
            <option value="">{t('noBug')}</option>
            {bugs.map((b) => <option key={b.id} value={b.id}>BUG-{b.number} {b.title}</option>)}
          </select>
        </label>
      </div>
      {!ptsOk ? <span role="alert" className="text-12 font-semibold text-danger">{t('pointsRange')}</span> : null}
    </Modal>
  )
}

/** a sprint: its name and its first and last day */
function EditSprint({ sprint, onClose }: { sprint: Board['sprint']; onClose: () => void }) {
  const t = useTranslations('devCore.board')
  const { run, pending } = useRun()
  const [name, setName] = useState(sprint?.name ?? '')
  const [starts, setStarts] = useState(sprint?.starts_on ?? '')
  const [ends, setEnds] = useState(sprint?.ends_on ?? '')
  const ok = name.trim() && starts && ends && ends >= starts
  return (
    <Modal title={sprint ? t('editSprint') : t('newSprint')} cta={t('save')} busy={pending || !ok} onClose={onClose}
      onSubmit={() => run(() => saveSprint({ id: sprint?.id ?? null, name, starts, ends }), () => t('sprintSaved'), onClose)}>
      <label className={c.field}>{t('fields.sprintName')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder={t('sprintHint')} className={c.input} /></label>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        <label className={c.field}>{t('fields.starts')}<input type="date" value={starts} onChange={(e) => setStarts(e.target.value)} className={c.input} /></label>
        <label className={c.field}>{t('fields.ends')}<input type="date" value={ends} min={starts || undefined} onChange={(e) => setEnds(e.target.value)} className={c.input} /></label>
      </div>
    </Modal>
  )
}
