'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { BoardRow, ProjectsBase, TemplateRow } from '@/lib/data/projects'
import type { Rights } from '@/lib/data/projects-shared'
import { fetchTemplates } from '../actions'
import { TemplateEditor } from './TemplateEditor'

type Props = { boards: BoardRow[]; base: ProjectsBase; rights: Rights; rev: number; onUse: (t: TemplateRow) => void }

/** Template cards (Projects.dc.html v.templates): counts computed from the template's rows, its first five items. */
export function TemplatesView({ boards, base, rights, rev, onUse }: Props) {
  const t = useTranslations('projects.templates')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [rows, setRows] = useState<TemplateRow[] | null>(null)
  const [editing, setEditing] = useState<string | 'new' | null>(null)
  const [mine, setMine] = useState(0)

  useEffect(() => {
    void fetchTemplates().then((r) => { if (r.ok) setRows(r.templates); else flash(te(r.code)) })
  }, [rev, mine, flash, te])

  const summary = (x: TemplateRow) => [
    t(x.organized_by === 'groups' ? 'count.groups' : 'count.phases', { count: x.groups }),
    t('count.tasks', { count: x.tasks }),
    t('count.milestones', { count: x.milestones }),
    ...(x.activities > 0 ? [t('count.activities', { count: x.activities })] : []),
    ...(x.dependencies > 0 ? [t('count.dependencies')] : []),
  ].join(' · ')

  return (
    <div className="flex flex-col gap-3">
      {rights.add ? (
        <div className="flex justify-end">
          <button type="button" onClick={() => setEditing('new')} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold">{t('new')}</button>
        </div>
      ) : null}
      {rows === null ? <div className="text-13 text-muted">{t('loading')}</div> : null}
      {rows && rows.length === 0 ? (
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[18px] py-8 text-center text-13 text-muted">{t('empty')}</div>
      ) : null}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        {(rows ?? []).map((x) => (
          <div key={x.id} className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
            <b className="text-14">{x.name}</b>
            <span className="text-12 text-muted">{summary(x)}</span>
            {x.description ? <span className="text-12 text-muted">{x.description}</span> : null}
            {x.preview.map((i, k) => (
              <span key={k} className="border-b border-tile py-1 text-12">
                {i.day === null ? '—' : t('day', { n: i.day })} {i.kind === 'milestone' ? '◆' : i.kind === 'activity' ? '◷' : '·'} {i.name}
              </span>
            ))}
            {x.preview.length === 0 ? <span className="py-1 text-12 text-faint">{t('noItems')}</span> : null}
            <span className="flex flex-wrap gap-[6px]">
              {rights.add ? (
                <button type="button" onClick={() => onUse(x)} className="h-[30px] cursor-pointer self-start rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold">{t('use')}</button>
              ) : null}
              {x.can_edit ? (
                <button type="button" onClick={() => setEditing(x.id)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold">{t('edit')}</button>
              ) : null}
            </span>
          </div>
        ))}
      </div>
      {editing ? (
        <TemplateEditor id={editing === 'new' ? null : editing} boards={boards} base={base} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); setMine((m) => m + 1) }} />
      ) : null}
    </div>
  )
}
