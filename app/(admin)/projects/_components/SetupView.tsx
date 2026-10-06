'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardRow } from '@/lib/data/projects'
import type { RpcCode } from '@/lib/rpc'
import { deletePhase, reorderPhases, saveBoard, savePhase } from '../actions'

type R = { ok: true } | { ok: false; code: RpcCode }

/** The design's phase palette (Projects.dc.html, viz), offered first for a new phase. */
export const PHASE_COLORS = ['#F6D9C6', '#DCEBD3', '#CFE0F5', '#E7DAF2', '#F3E2C9', '#F2EAD6']

const GRID = '[grid-template-columns:50px_minmax(0,1.5fr)_120px_90px_150px]'

/**
 * Boards and phases («projects:configure», D-41 in the language of Settings › Pipelines and stages): create, rename and
 * archive a board; add, rename, recolour and reorder its phases; delete a phase after moving its projects to another.
 */
export function SetupView({ boards, onChanged }: { boards: BoardRow[]; onChanged: () => Promise<void> | void }) {
  const t = useTranslations('projects.setup')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [sel, setSel] = useState<string | null>(boards.find((b) => !b.archived_at)?.id ?? boards[0]?.id ?? null)
  const [adding, setAdding] = useState(false)
  const [deleting, setDeleting] = useState<string | null>(null)
  const [target, setTarget] = useState('')
  const [newPhase, setNewPhase] = useState('')
  const board = boards.find((b) => b.id === sel) ?? null

  const run = async (p: R | Promise<R>, msg?: string) => {
    const r = await p
    if (!r.ok) { flash(te(r.code)); return false }
    if (msg) flash(msg)
    await onChanged()
    return true
  }

  const move = async (i: number, dir: -1 | 1) => {
    if (!board) return
    const ids = board.phases.map((p) => p.id)
    const j = i + dir
    if (j < 0 || j >= ids.length) return
    ;[ids[i], ids[j]] = [ids[j]!, ids[i]!]
    await run(await reorderPhases({ board: board.id, ids }), t('reordered'))
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[6px]">
        {boards.map((b) => (
          <button
            key={b.id}
            type="button"
            aria-pressed={sel === b.id}
            onClick={() => { setSel(b.id); setDeleting(null) }}
            className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${sel === b.id ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'} ${b.archived_at ? 'text-muted' : ''}`}
          >
            {b.name}{b.archived_at ? ` · ${t('archived')}` : ''}
          </button>
        ))}
        <button type="button" onClick={() => setAdding(true)} className="cursor-pointer rounded-999 border border-dashed border-line-strong bg-transparent px-3 py-[6px] text-12">{t('newBoard')}</button>
      </div>

      {adding ? <NewBoardForm onCancel={() => setAdding(false)} onCreated={async (id) => { setAdding(false); setSel(id); await onChanged() }} /> : null}

      {board ? (
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-[10px]">
            <input
              key={`${board.id}-${board.name}`}
              aria-label={t('boardName')}
              defaultValue={board.name}
              maxLength={80}
              onBlur={(e) => { const v = e.target.value.trim(); if (v && v !== board.name) void run(saveBoard({ id: board.id, values: { name: v } }), t('saved')) }}
              onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
              className="h-8 min-w-[200px] flex-1 rounded-9 border border-line bg-canvas px-[9px] text-13 font-bold"
            />
            <button
              type="button"
              onClick={() => void run(saveBoard({ id: board.id, values: { archived: !board.archived_at } }), board.archived_at ? t('restored') : t('archivedDone'))}
              className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold"
            >
              {board.archived_at ? t('restore') : t('archive')}
            </button>
          </div>
          <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${GRID}`}>
            <span>{t('order')}</span><span>{t('phase')}</span><span>{t('color')}</span><span>{t('projects')}</span><span />
          </div>
          {board.phases.map((p, i) => (
            <div key={p.id} className="flex flex-col border-b border-line">
              <div className={`grid items-center gap-[10px] px-4 py-2 text-12.5 ${GRID}`}>
                <span className="flex gap-[2px]">
                  <button type="button" aria-label={t('up', { name: p.name })} disabled={i === 0} onClick={() => void move(i, -1)} className="h-[22px] w-[22px] cursor-pointer rounded-6 border border-line bg-transparent text-10 disabled:cursor-default disabled:opacity-40">▲</button>
                  <button type="button" aria-label={t('down', { name: p.name })} disabled={i === board.phases.length - 1} onClick={() => void move(i, 1)} className="h-[22px] w-[22px] cursor-pointer rounded-6 border border-line bg-transparent text-10 disabled:cursor-default disabled:opacity-40">▼</button>
                </span>
                <input
                  key={`${p.id}-${p.name}`}
                  aria-label={t('phaseName')}
                  defaultValue={p.name}
                  maxLength={60}
                  onBlur={(e) => { const v = e.target.value.trim(); if (v && v !== p.name) void run(savePhase({ id: p.id, board: board.id, values: { name: v } }), t('saved')) }}
                  onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
                  className="h-8 rounded-9 border border-line bg-canvas px-[9px] text-12.5 font-semibold"
                />
                <span className="flex items-center gap-[6px]">
                  <input
                    type="color"
                    aria-label={t('color')}
                    value={p.color.toLowerCase()}
                    onChange={(e) => void run(savePhase({ id: p.id, board: board.id, values: { color: e.target.value.toUpperCase() } }))}
                    className="h-8 w-10 cursor-pointer rounded-9 border border-line bg-canvas p-[2px]"
                  />
                  <span className="text-11 text-muted">{p.color}</span>
                </span>
                <span className="text-muted">{p.open_projects}</span>
                <span className="flex justify-end">
                  {board.phases.length > 1 ? (
                    <button type="button" onClick={() => { setDeleting(deleting === p.id ? null : p.id); setTarget(board.phases.find((x) => x.id !== p.id)?.id ?? '') }} className="h-7 cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">
                      {t('delete')}
                    </button>
                  ) : null}
                </span>
              </div>
              {deleting === p.id ? (
                <div className="flex flex-wrap items-center gap-2 bg-cream px-4 py-2 text-12 text-amber-ink">
                  {t('deleteMove', { count: p.open_projects })}
                  <select aria-label={t('target')} value={target} onChange={(e) => setTarget(e.target.value)} className="h-[30px] rounded-9 border border-line bg-surface px-2 text-12 text-ink">
                    {board.phases.filter((x) => x.id !== p.id).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
                  </select>
                  <button
                    type="button"
                    disabled={!target}
                    onClick={async () => {
                      const r = await deletePhase({ phase: p.id, target })
                      if (await run(r, r.ok ? t('deleted', { count: r.moved }) : undefined)) setDeleting(null)
                    }}
                    className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-bold text-rust"
                  >
                    {t('deleteConfirm')}
                  </button>
                  <button type="button" onClick={() => setDeleting(null)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold text-ink">{t('cancel')}</button>
                </div>
              ) : null}
            </div>
          ))}
          <div className="flex flex-wrap items-center gap-2 px-4 py-[10px]">
            <input
              aria-label={t('newPhase')}
              placeholder={t('newPhase')}
              value={newPhase}
              maxLength={60}
              onChange={(e) => setNewPhase(e.target.value)}
              onKeyDown={async (e) => {
                if (e.key !== 'Enter' || !newPhase.trim()) return
                const ok = await run(await savePhase({ id: null, board: board.id, values: { name: newPhase.trim(), color: PHASE_COLORS[board.phases.length % PHASE_COLORS.length] } }), t('added'))
                if (ok) setNewPhase('')
              }}
              className="h-[30px] w-[220px] rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12"
            />
            <button
              type="button"
              disabled={!newPhase.trim()}
              onClick={async () => {
                const ok = await run(await savePhase({ id: null, board: board.id, values: { name: newPhase.trim(), color: PHASE_COLORS[board.phases.length % PHASE_COLORS.length] } }), t('added'))
                if (ok) setNewPhase('')
              }}
              className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[11px] text-12 font-semibold disabled:cursor-default disabled:opacity-60"
            >
              {t('addPhase')}
            </button>
          </div>
        </div>
      ) : (
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[18px] py-8 text-center text-13 text-muted">{t('none')}</div>
      )}
    </div>
  )
}

/** A new board with its phases, one per line (the design's four as the starting suggestion). */
export function NewBoardForm({ onCancel, onCreated }: { onCancel?: () => void; onCreated: (id: string) => void | Promise<void> }) {
  const t = useTranslations('projects.setup')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [name, setName] = useState('')
  const [phases, setPhases] = useState(t('defaultPhases'))
  const [busy, setBusy] = useState(false)
  const create = async () => {
    const list = phases.split(/\r?\n/).map((x) => x.trim()).filter(Boolean).slice(0, 20)
    setBusy(true)
    const r = await saveBoard({ id: null, values: { name: name.trim(), phases: list.map((n, i) => ({ name: n.slice(0, 60), color: PHASE_COLORS[i % PHASE_COLORS.length]! })) } })
    setBusy(false)
    if (!r.ok) return flash(te(r.code))
    flash(t('boardCreated'))
    await onCreated(r.id)
  }
  return (
    <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
      <b className="text-14">{t('newBoardTitle')}</b>
      <label className="flex flex-col gap-[5px] text-12 font-semibold text-muted">
        {t('boardName')}
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className="h-9 rounded-10 border border-line bg-canvas px-3 text-13 font-medium text-ink" />
      </label>
      <label className="flex flex-col gap-[5px] text-12 font-semibold text-muted">
        {t('phasesOnePerLine')}
        <textarea value={phases} onChange={(e) => setPhases(e.target.value)} rows={4} className="rounded-10 border border-line bg-canvas px-3 py-2 text-13 font-medium text-ink" />
      </label>
      <span className="flex gap-2">
        <button type="button" disabled={busy || !name.trim()} onClick={() => void create()} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold disabled:cursor-default disabled:opacity-60">{t('create')}</button>
        {onCancel ? <button type="button" onClick={onCancel} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-4 text-12.5 font-semibold">{t('cancel')}</button> : null}
      </span>
    </div>
  )
}
