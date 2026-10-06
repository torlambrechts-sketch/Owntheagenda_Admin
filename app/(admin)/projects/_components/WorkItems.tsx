'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import type { Detail, Item, ProjectsBase } from '@/lib/data/projects'
import { dateOnly, isoDay, parsePasteList, type Rights } from '@/lib/data/projects-shared'
import {
  addActivity, addItems, bulkItems, deleteGroup, deleteItems, itemDone, reorderItems, saveGroup, saveItem, setDependency,
} from '../actions'
import { btnSmallGhost, btnSmallStrong, inputSmall, Picker } from './kit'

type Props = { detail: Detail; base: ProjectsBase; rights: Rights; editable: boolean; onChanged: () => void }
type R = { ok: true } | { ok: false; code: RpcCode; detail?: string | null }

const GRID = '[grid-template-columns:22px_minmax(0,1.6fr)_120px_110px_minmax(0,1fr)]'
const GRID_SEL = '[grid-template-columns:18px_22px_minmax(0,1.6fr)_120px_110px_minmax(0,1fr)]'

/** The local calendar day (the lateness the database computes uses the staff member's time zone, set to the same). */
const today = () => { const d = new Date(); return isoDay(new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 12))) }

/**
 * Work items (Projects.dc.html, proj.items): groups, tasks with one level of subtasks, milestones and project
 * activities, with assignees, done, dependencies, «Paste a list» (PRJ-08), ＋ Task, bulk edit and reorder. Lateness and
 * who/when/depends are computed from the rows (project_detail); writes go through the project_item functions.
 */
export function WorkItems({ detail, base, rights, editable, onChanged }: Props) {
  const t = useTranslations('projects.items')
  const tp = useTranslations('projects')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const d = detail
  const [pasteOpen, setPasteOpen] = useState(false)
  const [paste, setPaste] = useState('')
  const [pasteGroup, setPasteGroup] = useState<string>(d.groups[0]?.id ?? '')
  const [adding, setAdding] = useState<null | { kind: 'task' | 'milestone' | 'activity'; name: string; group: string; due: string; type: string; at: string; owner: string; parent: string | null }>(null)
  const [open, setOpen] = useState<string | null>(null)
  const [selecting, setSelecting] = useState(false)
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [newGroup, setNewGroup] = useState<string | null>(null)
  const [renaming, setRenaming] = useState<string | null>(null)
  const [shift, setShift] = useState('')

  const after = async (p: R | Promise<R>, msg?: string) => {
    const r = await p
    if (!r.ok) { flash(r.detail === 'dependency.cycle' ? t('cycle') : te(r.code)); return false }
    if (msg) flash(msg)
    onChanged()
    return true
  }

  const preview = useMemo(() => (pasteOpen ? parsePasteList(paste, today()) : []), [paste, pasteOpen])
  const byId = new Map(d.items.map((i) => [i.id, i]))
  const fmtDay = (iso: string) => format.dateTime(dateOnly(iso), { day: 'numeric', month: 'short', timeZone: 'UTC' })

  // ---- rows in the database's order, with a heading per group (items without a group last)
  const sections: { id: string | null; name: string | null; items: Item[] }[] = d.groups.map((g) => ({ id: g.id, name: g.name, items: d.items.filter((i) => i.group_id === g.id) }))
  const loose = d.items.filter((i) => !i.group_id || !d.groups.some((g) => g.id === i.group_id))
  if (loose.length || d.groups.length === 0) sections.push({ id: null, name: d.groups.length ? t('noGroup') : null, items: loose })

  const who = (i: Item) => {
    const names = i.assignees.map((a) => a.name).filter(Boolean)
    if (names.length) return names.join(' · ')
    return i.owner ?? t('unassigned')
  }
  const due = (i: Item): { text: string; late: boolean } => {
    if (i.done) return { text: t('done'), late: false }
    if (i.late_days && i.late_days > 0) return { text: t('late', { count: i.late_days }), late: true }
    if (i.kind === 'activity' && i.activity?.starts_at) return { text: format.dateTime(new Date(i.activity.starts_at), { weekday: 'short', hour: '2-digit', minute: '2-digit' }), late: false }
    if (i.due_on) return { text: fmtDay(i.due_on), late: false }
    return { text: '—', late: false }
  }
  const dep = (i: Item) => {
    if (i.depends_on.length) return t('dependsOn', { name: i.depends_on[0]!.name ?? '—' }) + (i.depends_on.length > 1 ? ` +${i.depends_on.length - 1}` : '')
    if (i.kind === 'activity') return t('activity')
    if (i.source === 'paste') return t('fromList')
    return ''
  }

  const toggle = async (i: Item) => {
    if (!i.can_edit || d.status !== 'open') { flash(tp('flash.viewOnly')); return }
    const r = await itemDone({ id: i.id, done: !i.done })
    if (!r.ok) return flash(te(r.code))
    flash(!i.done ? (r.parentCompleted ? t('parentCompleted') : i.kind === 'milestone' ? t('milestoneReached') : t('marked')) : t('reopened'))
    onChanged()
  }

  const addPasted = async () => {
    if (!preview.length) return
    const ok = await after(addItems({ project: d.id, group: pasteGroup || null, items: preview.map((x) => ({ name: x.name, ...(x.due_on ? { due_on: x.due_on } : {}) })) }), t('added', { count: preview.length }))
    if (ok) { setPaste(''); setPasteOpen(false) }
  }

  const create = async () => {
    if (!adding || !adding.name.trim()) return
    const group = adding.group || null
    let ok: boolean
    if (adding.kind === 'activity') {
      if (!adding.at) { flash(t('activityNeedsTime')); return }
      ok = await after(addActivity({ project: d.id, group, values: { type: adding.type, subject: adding.name.trim(), starts_at: new Date(adding.at).toISOString(), owner_id: adding.owner } }), t('activityAdded'))
    } else {
      ok = await after(saveItem({ project: d.id, id: null, values: { kind: adding.kind, name: adding.name.trim(), group_id: group, ...(adding.due ? { due_on: adding.due } : {}), ...(adding.parent ? { parent_id: adding.parent } : {}) } }), adding.parent ? t('subtaskAdded') : t('taskAdded'))
    }
    if (ok) setAdding({ ...adding, name: '', due: '', at: '' })
  }
  const startAdd = (parent: string | null = null, group?: string | null) =>
    setAdding({ kind: 'task', name: '', group: group ?? d.groups[0]?.id ?? '', due: '', type: base.activityTypes[0]?.key ?? 'call', at: '', owner: d.owner_id ?? rights.meId, parent })

  // ---- reorder: the item swaps place with its neighbour among its siblings (same group, same parent)
  const reorder = async (i: Item, dir: -1 | 1) => {
    const sibs = d.items.filter((x) => x.group_id === i.group_id && x.parent_id === i.parent_id)
    const k = sibs.findIndex((x) => x.id === i.id)
    const other = sibs[k + dir]
    if (!other) return
    const ids = d.items.map((x) => x.id)
    const a = ids.indexOf(i.id), b = ids.indexOf(other.id)
    ;[ids[a], ids[b]] = [ids[b]!, ids[a]!]
    await after(reorderItems({ project: d.id, ids }), t('reordered'))
  }

  const bulk = async (values: { owner_id?: string | null; shift_days?: number; group_id?: string | null; done?: boolean }) => {
    if (!sel.size) return
    const r = await bulkItems({ project: d.id, ids: [...sel], values })
    if (!r.ok) return flash(te(r.code))
    flash(t('bulkDone', { count: r.updated }))
    onChanged()
  }
  const bulkDelete = async () => {
    if (!sel.size) return
    const r = await deleteItems([...sel])
    if (!r.ok) return flash(te(r.code))
    flash(t('deleted', { count: r.deleted }))
    setSel(new Set())
    onChanged()
  }

  const canBulk = editable && rights.bulk && d.status === 'open'
  const writable = editable && d.status === 'open'
  const grid = selecting ? GRID_SEL : GRID

  return (
    <div className="overflow-hidden rounded-18 border border-line bg-surface">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-4 py-3">
        <b className="text-14">{t('title')}</b>
        <span className="flex flex-wrap gap-[6px]">
          {canBulk && d.items.length ? (
            <button type="button" aria-pressed={selecting} onClick={() => { setSelecting(!selecting); setSel(new Set()) }} className={btnSmallGhost}>{selecting ? t('selectDone') : t('select')}</button>
          ) : null}
          {writable ? <button type="button" onClick={() => setNewGroup('')} className={btnSmallGhost}>{t('addGroup')}</button> : null}
          {writable ? <button type="button" aria-expanded={pasteOpen} onClick={() => setPasteOpen(!pasteOpen)} className={btnSmallGhost}>{t('paste')}</button> : null}
          {writable ? <button type="button" onClick={() => startAdd()} className={btnSmallStrong}>{t('addTask')}</button> : null}
        </span>
      </div>

      {newGroup !== null ? (
        <div className="flex gap-2 border-b border-line px-4 py-[10px]">
          <input
            autoFocus
            aria-label={t('groupName')}
            placeholder={t('groupName')}
            value={newGroup}
            maxLength={80}
            onChange={(e) => setNewGroup(e.target.value)}
            onKeyDown={async (e) => {
              if (e.key === 'Escape') { e.stopPropagation(); setNewGroup(null) }
              if (e.key === 'Enter' && newGroup.trim()) { if (await after(saveGroup({ project: d.id, id: null, name: newGroup.trim() }), t('groupAdded'))) setNewGroup(null) }
            }}
            className={`${inputSmall} min-w-0 flex-1`}
          />
          <button type="button" disabled={!newGroup.trim()} onClick={async () => { if (await after(saveGroup({ project: d.id, id: null, name: newGroup.trim() }), t('groupAdded'))) setNewGroup(null) }} className={btnSmallStrong}>{t('add')}</button>
          <button type="button" onClick={() => setNewGroup(null)} className={btnSmallGhost}>{t('cancel')}</button>
        </div>
      ) : null}

      {pasteOpen ? (
        <div className="flex flex-col gap-2 border-b border-line px-4 py-[10px]">
          <div className="flex gap-2">
            <textarea
              autoFocus
              aria-label={t('pastePlaceholder')}
              value={paste}
              onChange={(e) => setPaste(e.target.value)}
              placeholder={t('pastePlaceholder')}
              className="min-h-[70px] flex-1 rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5"
            />
            <button type="button" disabled={!preview.length} onClick={() => void addPasted()} className="h-8 cursor-pointer self-end rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('addTasks')}</button>
          </div>
          <div className="flex flex-wrap items-center gap-2 text-12 text-muted">
            {d.groups.length ? (
              <label className="flex items-center gap-[6px]">
                {t('intoGroup')}
                <select value={pasteGroup} onChange={(e) => setPasteGroup(e.target.value)} className={inputSmall}>
                  {d.groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
                  <option value="">{t('noGroup')}</option>
                </select>
              </label>
            ) : null}
            <span>{preview.length ? t('pastePreview', { count: preview.length, dated: preview.filter((x) => x.due_on).length }) : t('pasteHint')}</span>
          </div>
          {preview.length ? (
            <div className="flex flex-col text-12">
              {preview.slice(0, 8).map((x, k) => (
                <span key={k} className="flex justify-between gap-2 border-b border-tile py-[3px]"><span>{x.name}</span><span className="text-muted">{x.due_on ? fmtDay(x.due_on) : '—'}</span></span>
              ))}
              {preview.length > 8 ? <span className="py-[3px] text-faint">{t('more', { count: preview.length - 8 })}</span> : null}
            </div>
          ) : null}
        </div>
      ) : null}

      {selecting && sel.size ? (
        <div className="flex flex-wrap items-center gap-2 border-b border-line bg-cream px-4 py-2 text-12">
          <b>{t('selected', { count: sel.size })}</b>
          <select aria-label={t('bulkOwner')} value="" onChange={(e) => { const v = e.target.value; if (v) void bulk({ owner_id: v === '-' ? null : v }) }} className={inputSmall}>
            <option value="">{t('bulkOwner')}</option>
            <option value="-">{t('unassigned')}</option>
            {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          {d.groups.length ? (
            <select aria-label={t('bulkGroup')} value="" onChange={(e) => { const v = e.target.value; if (v) void bulk({ group_id: v === '-' ? null : v }) }} className={inputSmall}>
              <option value="">{t('bulkGroup')}</option>
              {d.groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              <option value="-">{t('noGroup')}</option>
            </select>
          ) : null}
          <label className="flex items-center gap-1">
            {t('shiftBy')}
            <input aria-label={t('shiftBy')} inputMode="numeric" value={shift} onChange={(e) => setShift(e.target.value.replace(/[^\d-]/g, ''))} className={`${inputSmall} w-14`} />
            <button type="button" disabled={!Number(shift)} onClick={() => { void bulk({ shift_days: Math.trunc(Number(shift)) }); setShift('') }} className={btnSmallGhost}>{t('shift')}</button>
          </label>
          <button type="button" onClick={() => void bulk({ done: true })} className={btnSmallGhost}>{t('markDone')}</button>
          <button type="button" onClick={() => void bulk({ done: false })} className={btnSmallGhost}>{t('markOpen')}</button>
          <button type="button" onClick={() => void bulkDelete()} className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">{t('delete')}</button>
        </div>
      ) : null}

      {/* below 660 px the rows scroll sideways inside the card, as the design's fixed columns need the room */}
      <div className="overflow-x-auto"><div className="min-w-[620px]">
      {sections.map((s) => (
        <div key={s.id ?? 'none'}>
          {s.name !== null ? (
            <div className="flex items-center justify-between gap-2 border-b border-line bg-canvas px-4 py-[6px]">
              {renaming === s.id && s.id ? (
                <input
                  autoFocus
                  aria-label={t('groupName')}
                  defaultValue={s.name}
                  maxLength={80}
                  onBlur={async (e) => { const v = e.target.value.trim(); setRenaming(null); if (v && v !== s.name) await after(saveGroup({ project: d.id, id: s.id!, name: v }), t('groupRenamed')) }}
                  onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur(); if (e.key === 'Escape') { e.stopPropagation(); setRenaming(null) } }}
                  className={inputSmall}
                />
              ) : (
                <span className="text-10.5 font-bold uppercase tracking-label text-muted">{s.name} · {s.items.length}</span>
              )}
              {writable && s.id ? (
                <span className="flex gap-[6px] text-11.5">
                  <button type="button" onClick={() => startAdd(null, s.id)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('addHere')}</button>
                  <button type="button" onClick={() => setRenaming(s.id)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('rename')}</button>
                  <button type="button" onClick={() => void after(deleteGroup(s.id!), t('groupDeleted'))} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-rust">{t('deleteGroup')}</button>
                </span>
              ) : null}
            </div>
          ) : null}
          {s.items.map((i) => {
            const dd = due(i)
            const glyph = i.kind === 'milestone' ? '◆' : i.kind === 'activity' ? '◷' : ''
            return (
              <div key={i.id}>
                <div className={`grid items-center gap-[10px] border-b border-line py-[9px] pr-4 text-12.5 ${grid}`} style={{ paddingLeft: i.parent_id ? 40 : 16 }}>
                  {selecting ? (
                    <input type="checkbox" aria-label={t('selectItem', { name: i.name ?? '' })} checked={sel.has(i.id)} onChange={(e) => setSel((x) => { const n = new Set(x); if (e.target.checked) n.add(i.id); else n.delete(i.id); return n })} className="accent-ink" />
                  ) : null}
                  <button
                    type="button"
                    aria-pressed={i.done}
                    aria-label={t(i.done ? 'markOpenOne' : 'markDoneOne', { name: i.name ?? '' })}
                    onClick={() => void toggle(i)}
                    className={`h-[18px] w-[18px] cursor-pointer border-[1.5px] border-ink p-0 text-10 text-ok-ink ${i.kind === 'milestone' ? 'rounded-4' : 'rounded-999'} ${i.done ? 'bg-ok-bg' : 'bg-transparent'}`}
                  >
                    {i.done ? '✓' : ''}
                  </button>
                  <button
                    type="button"
                    aria-expanded={open === i.id}
                    onClick={() => setOpen(open === i.id ? null : i.id)}
                    className={`min-w-0 cursor-pointer border-none bg-transparent p-0 text-left text-12.5 ${i.kind === 'milestone' ? 'font-bold' : 'font-medium'} ${i.done ? 'line-through' : ''}`}
                  >
                    {glyph ? `${glyph} ` : ''}{i.name}
                  </button>
                  <span className="truncate text-muted">{who(i)}</span>
                  <span className={dd.late ? 'text-danger' : 'text-muted'}>{dd.text}</span>
                  <span className="truncate text-11.5 text-faint">{dep(i)}</span>
                </div>
                {open === i.id ? (
                  <ItemEditor
                    item={i}
                    detail={d}
                    base={base}
                    projectEditable={writable}
                    onAfter={after}
                    onReorder={(dir) => void reorder(i, dir)}
                    onSubtask={() => { startAdd(i.id, i.group_id); setOpen(null) }}
                    onClose={() => setOpen(null)}
                    byId={byId}
                  />
                ) : null}
              </div>
            )
          })}
        </div>
      ))}
      </div></div>

      {adding ? (
        <div className="flex flex-wrap items-center gap-2 border-b border-line bg-canvas px-4 py-[10px]">
          {adding.parent ? <span className="text-12 text-muted">{t('subtaskOf', { name: byId.get(adding.parent)?.name ?? '' })}</span> : (
            <select aria-label={t('kind')} value={adding.kind} onChange={(e) => setAdding({ ...adding, kind: e.target.value as 'task' | 'milestone' | 'activity' })} className={inputSmall}>
              <option value="task">{tp('kind.task')}</option>
              <option value="milestone">{tp('kind.milestone')}</option>
              {base.activityTypes.length ? <option value="activity">{tp('kind.activity')}</option> : null}
            </select>
          )}
          <input
            autoFocus
            aria-label={t('newName')}
            placeholder={adding.kind === 'activity' ? t('newActivity') : t('newName')}
            value={adding.name}
            maxLength={adding.kind === 'activity' ? 200 : 300}
            onChange={(e) => setAdding({ ...adding, name: e.target.value })}
            onKeyDown={(e) => { if (e.key === 'Enter') void create(); if (e.key === 'Escape') { e.stopPropagation(); setAdding(null) } }}
            className={`${inputSmall} min-w-[180px] flex-1`}
          />
          {!adding.parent && d.groups.length ? (
            <select aria-label={t('group')} value={adding.group} onChange={(e) => setAdding({ ...adding, group: e.target.value })} className={inputSmall}>
              {d.groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              <option value="">{t('noGroup')}</option>
            </select>
          ) : null}
          {adding.kind === 'activity' ? (
            <>
              <select aria-label={t('activityType')} value={adding.type} onChange={(e) => setAdding({ ...adding, type: e.target.value })} className={inputSmall}>
                {base.activityTypes.map((a) => <option key={a.key} value={a.key}>{a.name}</option>)}
              </select>
              <input type="datetime-local" aria-label={t('when')} value={adding.at} onChange={(e) => setAdding({ ...adding, at: e.target.value })} className={inputSmall} />
              <select aria-label={t('owner')} value={adding.owner} onChange={(e) => setAdding({ ...adding, owner: e.target.value })} className={inputSmall}>
                {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </>
          ) : (
            <input type="date" aria-label={t('due')} value={adding.due} onChange={(e) => setAdding({ ...adding, due: e.target.value })} className={inputSmall} />
          )}
          <button type="button" disabled={!adding.name.trim()} onClick={() => void create()} className={btnSmallStrong}>{t('add')}</button>
          <button type="button" onClick={() => setAdding(null)} className={btnSmallGhost}>{t('cancel')}</button>
          <span className="w-full text-11.5 text-faint">{t('enterHint')}</span>
        </div>
      ) : null}

      {d.items.length === 0 && !adding ? <div className="px-4 py-4 text-12.5 text-muted">{writable ? t('emptyEdit') : t('empty')}</div> : null}
    </div>
  )
}

type EditorProps = {
  item: Item
  detail: Detail
  base: ProjectsBase
  projectEditable: boolean
  byId: Map<string, Item>
  onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean>
  onReorder: (dir: -1 | 1) => void
  onSubtask: () => void
  onClose: () => void
}

/** One item opened under its row: content and dates (the item's owner or assignee), who and where (the project's editors). */
function ItemEditor({ item: i, detail: d, base, projectEditable, byId, onAfter, onReorder, onSubtask, onClose }: EditorProps) {
  const t = useTranslations('projects.items')
  const [picking, setPicking] = useState(false)
  const own = i.can_edit && d.status === 'open'
  const save = (values: Record<string, unknown>, msg?: string) => onAfter(saveItem({ project: d.id, id: i.id, version: i.version, values }), msg ?? t('saved'))
  const hasChildren = d.items.some((x) => x.parent_id === i.id)
  const parents = d.items.filter((x) => x.kind === 'task' && !x.parent_id && x.id !== i.id)
  const deppable = d.items.filter((x) => (x.kind === 'task' || x.kind === 'milestone') && x.id !== i.id && !i.depends_on.some((p) => p.id === x.id))
  const staffAssignees = i.assignees.filter((a) => a.staff_id)
  const setAssignees = (list: { staff_id?: string; person_id?: string }[]) =>
    save({ assignees: list.map((a) => (a.staff_id ? { staff_id: a.staff_id } : { person_id: a.person_id! })) }, t('assigneesSaved'))
  const current = i.assignees.map((a) => (a.staff_id ? { staff_id: a.staff_id } : { person_id: a.person_id ?? undefined }))
  const lbl = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'

  if (i.kind === 'activity') {
    return (
      <div className="flex flex-wrap items-center gap-3 border-b border-line bg-canvas px-4 py-3 text-12.5">
        <span>{t('activityOwner', { name: i.owner ?? '—' })}</span>
        {i.activity ? <Link href={`/activities?activity=${i.activity.id}`} className="font-semibold">{t('openActivity')}</Link> : null}
        <span className="flex-1" />
        {projectEditable ? <button type="button" onClick={() => void onAfter(deleteItems([i.id]), t('deleted', { count: 1 }))} className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">{t('unlink')}</button> : null}
        <button type="button" onClick={onClose} className={btnSmallGhost}>{t('close')}</button>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3 border-b border-line bg-canvas px-4 py-3">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <label className={`${lbl} [grid-column:span_2]`}>
          {t('name')}
          <input key={`n-${i.version}`} defaultValue={i.name ?? ''} disabled={!own} maxLength={300} onBlur={(e) => { const v = e.target.value.trim(); if (v && v !== i.name) void save({ name: v }) }} onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }} className={inputSmall} />
        </label>
        {i.kind === 'task' ? (
          <label className={lbl}>
            {t('start')}
            <input type="date" key={`s-${i.version}`} defaultValue={i.starts_on ?? ''} disabled={!own} onBlur={(e) => { if ((e.target.value || null) !== i.starts_on) void save({ starts_on: e.target.value || null }) }} className={inputSmall} />
          </label>
        ) : null}
        <label className={lbl}>
          {t('due')}
          <input type="date" key={`d-${i.version}`} defaultValue={i.due_on ?? ''} disabled={!own} onBlur={(e) => { if ((e.target.value || null) !== i.due_on) void save({ due_on: e.target.value || null }) }} className={inputSmall} />
        </label>
        <label className={lbl}>
          {t('owner')}
          <select value={i.owner_id ?? ''} disabled={!projectEditable} onChange={(e) => void save({ owner_id: e.target.value || null })} className={inputSmall}>
            <option value="">{t('unassigned')}</option>
            {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        {d.groups.length ? (
          <label className={lbl}>
            {t('group')}
            <select value={i.group_id ?? ''} disabled={!projectEditable} onChange={(e) => void save({ group_id: e.target.value || null })} className={inputSmall}>
              {d.groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              <option value="">{t('noGroup')}</option>
            </select>
          </label>
        ) : null}
        {i.kind === 'task' && !hasChildren ? (
          <label className={lbl}>
            {t('parent')}
            <select value={i.parent_id ?? ''} disabled={!projectEditable} onChange={(e) => void save({ parent_id: e.target.value || null })} className={inputSmall}>
              <option value="">{t('topLevel')}</option>
              {parents.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
        ) : null}
      </div>

      {i.kind === 'task' && !i.parent_id ? (
        <label className="flex items-center gap-[6px] text-12 text-muted">
          <input type="checkbox" checked={i.completes_with_subtasks} disabled={!own} onChange={(e) => void save({ completes_with_subtasks: e.target.checked })} className="accent-ink" />
          {t('completesWithSubtasks')}
        </label>
      ) : null}

      <div className="flex flex-wrap items-center gap-[6px] text-12">
        <span className="font-semibold text-muted">{t('assignees')}</span>
        {i.assignees.map((a) => (
          <span key={a.staff_id ?? a.person_id} className="flex items-center gap-1 rounded-999 border border-line bg-surface px-[9px] py-[2px]">
            {a.name}{a.person_id ? <span className="text-faint"> · {t('customerSide')}</span> : null}
            {projectEditable ? (
              <button type="button" aria-label={t('removeAssignee', { name: a.name ?? '' })} onClick={() => void setAssignees(current.filter((x) => (x.staff_id ?? x.person_id) !== (a.staff_id ?? a.person_id)))} className="cursor-pointer border-none bg-transparent p-0 text-faint">×</button>
            ) : null}
          </span>
        ))}
        {i.assignees.length === 0 ? <span className="text-faint">{t('none')}</span> : null}
        {projectEditable ? (
          <>
            <select aria-label={t('addStaff')} value="" onChange={(e) => { if (e.target.value) void setAssignees([...current, { staff_id: e.target.value }]) }} className={inputSmall}>
              <option value="">{t('addStaff')}</option>
              {base.staff.filter((s) => !staffAssignees.some((a) => a.staff_id === s.id)).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
            {picking ? null : <button type="button" onClick={() => setPicking(true)} className={btnSmallGhost}>{t('addPerson')}</button>}
          </>
        ) : null}
      </div>
      {picking ? <div className="max-w-[360px]"><Picker entity="person" onCancel={() => setPicking(false)} onPick={(h) => { setPicking(false); void setAssignees([...current, { person_id: h.id }]) }} /></div> : null}

      {i.kind === 'task' || i.kind === 'milestone' ? (
        <div className="flex flex-wrap items-center gap-[6px] text-12">
          <span className="font-semibold text-muted">{t('dependencies')}</span>
          {i.depends_on.map((p) => (
            <span key={p.id} className="flex items-center gap-1 rounded-999 border border-line bg-surface px-[9px] py-[2px]">
              {t('dependsOn', { name: p.name ?? '—' })}{p.lag_days ? ` · ${t('lag', { days: p.lag_days })}` : ''}
              {projectEditable ? <button type="button" aria-label={t('removeDependency', { name: p.name ?? '' })} onClick={() => void onAfter(setDependency({ pred: p.id, succ: i.id, on: false }), t('dependencyRemoved'))} className="cursor-pointer border-none bg-transparent p-0 text-faint">×</button> : null}
            </span>
          ))}
          {i.depends_on.length === 0 ? <span className="text-faint">{t('none')}</span> : null}
          {projectEditable && deppable.length ? (
            <select
              aria-label={t('addDependency')}
              value=""
              onChange={async (e) => {
                const v = e.target.value
                if (!v) return
                const r = await setDependency({ pred: v, succ: i.id, on: true })
                await onAfter(r, r.ok ? (r.violated ? t('dependencyViolated', { name: byId.get(v)?.name ?? '' }) : t('dependencyAdded')) : undefined)
              }}
              className={inputSmall}
            >
              <option value="">{t('addDependency')}</option>
              {deppable.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
            </select>
          ) : null}
        </div>
      ) : null}

      <div className="flex flex-wrap gap-[6px]">
        {projectEditable && i.kind === 'task' && !i.parent_id ? <button type="button" onClick={onSubtask} className={btnSmallGhost}>{t('addSubtask')}</button> : null}
        {projectEditable ? <button type="button" aria-label={t('moveUp')} onClick={() => onReorder(-1)} className={btnSmallGhost}>↑</button> : null}
        {projectEditable ? <button type="button" aria-label={t('moveDown')} onClick={() => onReorder(1)} className={btnSmallGhost}>↓</button> : null}
        <span className="flex-1" />
        {projectEditable ? <button type="button" onClick={() => void onAfter(deleteItems([i.id]), t('deleted', { count: 1 }))} className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">{t('delete')}</button> : null}
        <button type="button" onClick={onClose} className={btnSmallGhost}>{t('close')}</button>
      </div>
    </div>
  )
}
