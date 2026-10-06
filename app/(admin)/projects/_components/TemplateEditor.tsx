'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardRow, ProjectsBase, TemplateDetail } from '@/lib/data/projects'
import { deleteTemplate, fetchTemplate, saveTemplate } from '../actions'
import { btnCancel, btnConfirm, btnDanger, field, fieldInput, inputSmall, Modal } from './kit'

type G = { key: string; name: string; phase_id: string | null }
type I = TemplateDetail['items'][number]
type D = { pred: string; succ: string; lag_days: number }

let counter = 0
const newKey = () => `n${Date.now().toString(36)}${(counter++).toString(36)}`
const intOrNull = (v: string) => (v.trim() === '' ? null : Math.max(0, Math.min(3650, Math.trunc(Number(v)) || 0)))

/**
 * The template editor (D-41, PRJ-05): groups tied to a board's phases, items with day offsets from the project's
 * start (activities at a time of day), subtasks one level deep and dependencies. Saved as one set
 * (project_template_save); the database refuses a cycle or a bad offset with the field named.
 */
export function TemplateEditor({ id, boards, base, onClose, onSaved }: { id: string | null; boards: BoardRow[]; base: ProjectsBase; onClose: () => void; onSaved: () => void }) {
  const t = useTranslations('projects.editor')
  const tp = useTranslations('projects')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [loaded, setLoaded] = useState(id === null)
  const [version, setVersion] = useState<number | undefined>(undefined)
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [organized, setOrganized] = useState<'phases' | 'groups'>('phases')
  const [boardId, setBoardId] = useState<string | null>(boards[0]?.id ?? null)
  const [groups, setGroups] = useState<G[]>([])
  const [items, setItems] = useState<I[]>([])
  const [deps, setDeps] = useState<D[]>([])
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [canDelete, setCanDelete] = useState(false)

  useEffect(() => {
    if (!id) return
    void fetchTemplate(id).then((r) => {
      if (!r.ok) { flash(te(r.code)); onClose(); return }
      const x = r.template
      setVersion(x.version); setName(x.name); setDescription(x.description ?? ''); setOrganized(x.organized_by); setBoardId(x.board_id)
      setGroups(x.group_list.map((g) => ({ key: g.key, name: g.name, phase_id: g.phase_id })))
      setItems(x.items)
      setDeps(x.dependency_list)
      setCanDelete(x.can_edit)
      setLoaded(true)
    })
  }, [id, flash, te, onClose])

  const phases = boards.find((b) => b.id === boardId)?.phases ?? []
  const setItem = (k: string, patch: Partial<I>) => setItems((xs) => xs.map((i) => (i.key === k ? { ...i, ...patch } : i)))
  const addItem = (kind: I['kind']) => setItems((xs) => [...xs, {
    key: newKey(), group: groups[0]?.key ?? null, parent: null, kind, name: '', start_offset_days: null, due_offset_days: 0,
    activity_type: kind === 'activity' ? (base.activityTypes[0]?.key ?? 'call') : null, activity_time: kind === 'activity' ? '10:00' : null,
    activity_duration_min: kind === 'activity' ? 30 : null, assignee: 'unassigned', completes_with_subtasks: false, ord: (xs.length + 1) * 10,
  }])
  const removeItem = (k: string) => {
    setItems((xs) => xs.filter((i) => i.key !== k && i.parent !== k))
    setDeps((ds) => ds.filter((d) => d.pred !== k && d.succ !== k))
  }

  const save = async () => {
    setBusy(true); setProblem(null)
    const r = await saveTemplate({
      id, version,
      values: {
        name, description: description.trim() || null, organized_by: organized, board_id: boardId,
        groups: groups.map((g, i) => ({ key: g.key, name: g.name, ord: (i + 1) * 10, phase_id: g.phase_id })),
        items: items.map((i, k) => ({ ...i, ord: (k + 1) * 10, start_offset_days: i.kind === 'milestone' ? null : i.start_offset_days })),
        dependencies: deps.filter((d) => d.pred && d.succ && d.pred !== d.succ),
      },
    })
    setBusy(false)
    if (!r.ok) { setProblem(r.detail ?? null); return flash(r.detail === 'dependency.cycle' ? t('cycle') : te(r.code)) }
    flash(tp('flash.templateSaved'))
    onSaved()
  }
  const remove = async () => {
    if (!id) return
    const r = await deleteTemplate(id)
    if (!r.ok) return flash(te(r.code))
    flash(tp('flash.templateDeleted'))
    onSaved()
  }

  const tasks = items.filter((i) => i.kind === 'task' && !i.parent)
  const deppable = items.filter((i) => i.kind === 'task' || i.kind === 'milestone')

  return (
    <Modal eyebrow={t('eyebrow')} title={id ? t('titleEdit') : t('titleNew')} onClose={onClose} width={900}>
      {!loaded ? <div className="text-13 text-muted">{tp('loading')}</div> : (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className={field}>{t('name')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={fieldInput} /></label>
            <label className={field}>{t('board')}
              <select value={boardId ?? ''} onChange={(e) => setBoardId(e.target.value || null)} className={fieldInput}>
                <option value="">{t('noBoard')}</option>
                {boards.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </label>
            <label className={`${field} sm:col-span-2`}>{t('description')}<input value={description} onChange={(e) => setDescription(e.target.value)} maxLength={500} className={fieldInput} /></label>
            <label className={field}>{t('organizedBy')}
              <select value={organized} onChange={(e) => setOrganized(e.target.value === 'groups' ? 'groups' : 'phases')} className={fieldInput}>
                <option value="phases">{t('byPhases')}</option>
                <option value="groups">{t('byGroups')}</option>
              </select>
            </label>
          </div>

          <div className="flex flex-col gap-[6px]">
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{organized === 'groups' ? t('groups') : t('phases')}</div>
            {groups.map((g, i) => (
              <div key={g.key} className="flex flex-wrap items-center gap-2">
                <input aria-label={t('groupName')} value={g.name} onChange={(e) => setGroups((gs) => gs.map((x) => (x.key === g.key ? { ...x, name: e.target.value } : x)))} maxLength={80} className={`${inputSmall} min-w-0 flex-1`} />
                <select aria-label={t('groupPhase')} value={g.phase_id ?? ''} onChange={(e) => setGroups((gs) => gs.map((x) => (x.key === g.key ? { ...x, phase_id: e.target.value || null } : x)))} className={inputSmall}>
                  <option value="">{t('noPhase')}</option>
                  {phases.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
                <button type="button" aria-label={t('up')} disabled={i === 0} onClick={() => setGroups((gs) => { const a = [...gs]; [a[i - 1], a[i]] = [a[i]!, a[i - 1]!]; return a })} className="h-[30px] w-[30px] cursor-pointer rounded-9 border border-line bg-transparent disabled:opacity-40">↑</button>
                <button type="button" aria-label={t('remove')} onClick={() => { setGroups((gs) => gs.filter((x) => x.key !== g.key)); setItems((xs) => xs.map((x) => (x.group === g.key ? { ...x, group: null } : x))) }} className="h-[30px] w-[30px] cursor-pointer rounded-9 border border-line bg-transparent">×</button>
              </div>
            ))}
            <button type="button" onClick={() => setGroups((gs) => [...gs, { key: newKey(), name: '', phase_id: null }])} className="h-[30px] cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addGroup')}</button>
          </div>

          <div className="flex flex-col gap-[6px]">
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('items')}</div>
            <div className="overflow-x-auto">
              <div className="min-w-[780px]">
                <div className="grid gap-2 border-b border-line pb-[6px] text-10.5 font-bold uppercase tracking-[.06em] text-muted [grid-template-columns:96px_minmax(0,1.4fr)_120px_120px_64px_64px_110px_30px]">
                  <span>{t('kind')}</span><span>{t('itemName')}</span><span>{t('group')}</span><span>{t('parent')}</span><span>{t('start')}</span><span>{t('due')}</span><span>{t('assignee')}</span><span />
                </div>
                {items.map((i) => (
                  <div key={i.key} className="flex flex-col gap-1 border-b border-tile py-[6px]">
                    <div className="grid items-center gap-2 [grid-template-columns:96px_minmax(0,1.4fr)_120px_120px_64px_64px_110px_30px]">
                      <span className="text-12 text-muted">{tp(`kind.${i.kind}`)}</span>
                      <input aria-label={t('itemName')} value={i.name} onChange={(e) => setItem(i.key, { name: e.target.value })} maxLength={300} className={`${inputSmall} min-w-0`} />
                      <select aria-label={t('group')} value={i.group ?? ''} onChange={(e) => setItem(i.key, { group: e.target.value || null })} className={inputSmall}>
                        <option value="">—</option>
                        {groups.map((g) => <option key={g.key} value={g.key}>{g.name || '—'}</option>)}
                      </select>
                      {i.kind === 'task' ? (
                        <select aria-label={t('parent')} value={i.parent ?? ''} onChange={(e) => setItem(i.key, { parent: e.target.value || null })} className={inputSmall}>
                          <option value="">—</option>
                          {tasks.filter((x) => x.key !== i.key && !items.some((c) => c.parent === i.key)).map((x) => <option key={x.key} value={x.key}>{x.name || '—'}</option>)}
                        </select>
                      ) : <span />}
                      {i.kind === 'task' ? (
                        <input aria-label={t('start')} inputMode="numeric" value={i.start_offset_days ?? ''} onChange={(e) => setItem(i.key, { start_offset_days: intOrNull(e.target.value) })} className={inputSmall} />
                      ) : <span />}
                      <input aria-label={t('due')} inputMode="numeric" value={i.due_offset_days ?? ''} onChange={(e) => setItem(i.key, { due_offset_days: intOrNull(e.target.value) })} className={inputSmall} />
                      <select aria-label={t('assignee')} value={i.assignee} onChange={(e) => setItem(i.key, { assignee: e.target.value === 'owner' ? 'owner' : 'unassigned' })} className={inputSmall}>
                        <option value="unassigned">{t('unassigned')}</option>
                        <option value="owner">{t('owner')}</option>
                      </select>
                      <button type="button" aria-label={t('remove')} onClick={() => removeItem(i.key)} className="h-[30px] w-[30px] cursor-pointer rounded-9 border border-line bg-transparent">×</button>
                    </div>
                    {i.kind === 'activity' ? (
                      <div className="flex flex-wrap items-center gap-2 pl-[104px] text-12 text-muted">
                        <select aria-label={t('activityType')} value={i.activity_type ?? ''} onChange={(e) => setItem(i.key, { activity_type: e.target.value })} className={inputSmall}>
                          {base.activityTypes.map((a) => <option key={a.key} value={a.key}>{a.name}</option>)}
                        </select>
                        <input type="time" aria-label={t('activityTime')} value={i.activity_time ?? ''} onChange={(e) => setItem(i.key, { activity_time: e.target.value || null })} className={inputSmall} />
                        <label className="flex items-center gap-1">{t('minutes')}<input inputMode="numeric" value={i.activity_duration_min ?? ''} onChange={(e) => setItem(i.key, { activity_duration_min: intOrNull(e.target.value) })} className={`${inputSmall} w-16`} /></label>
                      </div>
                    ) : i.kind === 'task' && !i.parent ? (
                      <label className="flex items-center gap-[6px] pl-[104px] text-12 text-muted">
                        <input type="checkbox" checked={i.completes_with_subtasks} onChange={(e) => setItem(i.key, { completes_with_subtasks: e.target.checked })} className="accent-ink" />
                        {t('completesWithSubtasks')}
                      </label>
                    ) : null}
                  </div>
                ))}
              </div>
            </div>
            {items.length === 0 ? <div className="text-12 text-faint">{t('noItems')}</div> : null}
            <span className="flex flex-wrap gap-[6px]">
              <button type="button" onClick={() => addItem('task')} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addTask')}</button>
              <button type="button" onClick={() => addItem('milestone')} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addMilestone')}</button>
              {base.activityTypes.length ? <button type="button" onClick={() => addItem('activity')} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addActivity')}</button> : null}
            </span>
            <span className="text-11.5 text-faint">{t('offsetsHint')}</span>
          </div>

          <div className="flex flex-col gap-[6px]">
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('dependencies')}</div>
            {deps.map((d, k) => (
              <div key={k} className="flex flex-wrap items-center gap-2 text-12 text-muted">
                <select aria-label={t('successor')} value={d.succ} onChange={(e) => setDeps((ds) => ds.map((x, j) => (j === k ? { ...x, succ: e.target.value } : x)))} className={inputSmall}>
                  {deppable.map((x) => <option key={x.key} value={x.key}>{x.name || '—'}</option>)}
                </select>
                {t('dependsOn')}
                <select aria-label={t('predecessor')} value={d.pred} onChange={(e) => setDeps((ds) => ds.map((x, j) => (j === k ? { ...x, pred: e.target.value } : x)))} className={inputSmall}>
                  {deppable.map((x) => <option key={x.key} value={x.key}>{x.name || '—'}</option>)}
                </select>
                <label className="flex items-center gap-1">{t('lag')}<input inputMode="numeric" value={d.lag_days} onChange={(e) => setDeps((ds) => ds.map((x, j) => (j === k ? { ...x, lag_days: Math.max(-365, Math.min(365, Math.trunc(Number(e.target.value)) || 0)) } : x)))} className={`${inputSmall} w-14`} /></label>
                <button type="button" aria-label={t('remove')} onClick={() => setDeps((ds) => ds.filter((_, j) => j !== k))} className="h-[30px] w-[30px] cursor-pointer rounded-9 border border-line bg-transparent">×</button>
              </div>
            ))}
            {deppable.length >= 2 ? (
              <button type="button" onClick={() => setDeps((ds) => [...ds, { pred: deppable[0]!.key, succ: deppable[1]!.key, lag_days: 0 }])} className="h-[30px] cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addDependency')}</button>
            ) : null}
          </div>

          {problem ? <div className="rounded-12 bg-peach px-3 py-[9px] text-12 text-rust-ink">{t('problem', { field: problem })}</div> : null}
          <div className="flex flex-wrap justify-between gap-2">
            <span>{id && canDelete ? <button type="button" onClick={() => void remove()} className={btnDanger}>{t('delete')}</button> : null}</span>
            <span className="flex gap-2">
              <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
              <button type="button" disabled={busy || !name.trim()} onClick={() => void save()} className={btnConfirm}>{t('save')}</button>
            </span>
          </div>
        </>
      )}
    </Modal>
  )
}
