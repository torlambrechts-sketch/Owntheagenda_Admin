'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { saveGroup, setSetting } from '../actions'
import { k, useRun } from './kit'

type Group = { id: string; name: string; parent_id: string | null; members: number }

/** The tree in depth-first order with its depth (root 0). */
function tree(groups: Group[]) {
  const out: (Group & { depth: number })[] = []
  const walk = (parent: string | null, depth: number) => {
    for (const g of groups.filter((x) => x.parent_id === parent)) {
      out.push({ ...g, depth })
      walk(g.id, depth + 1)
    }
  }
  walk(null, 0)
  // a group's count includes its sub-groups, as the design's tree counts («Everyone» holds every user)
  const below = (id: string): number => groups.filter((x) => x.parent_id === id).reduce((a, x) => a + x.members + below(x.id), 0)
  return out.map((g) => ({ ...g, total: g.members + below(g.id) }))
}

/**
 * Visibility groups (Settings.dc.html, v.groups): the group tree with its direct members, and the default
 * visibility per record type (setting visibility_default, scoped by the record type's key).
 */
export function Groups({ groups, entities, options, canEditGroups, canEditDefaults }: {
  groups: Group[]
  entities: { key: string; value: string }[]
  options: string[]
  canEditGroups: boolean
  canEditDefaults: boolean
}) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const [adding, setAdding] = useState(false)
  const [name, setName] = useState('')
  const rows = tree(groups)
  const [parent, setParent] = useState(rows[0]?.id ?? '')
  const ent = (e: string) => (t.has(`entities.${e}`) ? t(`entities.${e}`) : e)

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-1 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="mb-[6px] text-14">{t('groups.title')}</b>
        {rows.map((g) => (
          <div key={g.id} className="flex justify-between border-b border-line py-[7px] text-12.5" style={{ paddingLeft: Math.min(g.depth, 4) * 18 }}>
            <b className={g.depth === 0 ? 'font-bold' : g.depth === 1 ? 'font-semibold' : 'font-medium'}>{g.name}</b>
            <span className="text-muted">{t('groups.users', { count: g.total })}</span>
          </div>
        ))}
        {adding ? (
          <form
            className="flex flex-wrap items-end gap-2 pt-2"
            onSubmit={(e) => {
              e.preventDefault()
              const n = name.trim()
              if (!n) return
              run(() => saveGroup({ id: null, name: n, parent: parent || null }), () => {
                setAdding(false)
                setName('')
                return t('groups.created', { name: n })
              })
            }}
          >
            <label className={k.label}>
              {t('groups.name')}
              <input autoFocus value={name} maxLength={80} onChange={(e) => setName(e.target.value)} className={`${k.input} font-normal`} />
            </label>
            <label className={k.label}>
              {t('groups.parent')}
              <select value={parent} onChange={(e) => setParent(e.target.value)} className="h-8 rounded-8 border border-line bg-canvas text-12 font-normal text-ink">
                {rows.map((g) => <option key={g.id} value={g.id}>{'· '.repeat(g.depth)}{g.name}</option>)}
              </select>
            </label>
            <button type="submit" disabled={pending || !name.trim()} className={k.primary}>{t('groups.addSubmit')}</button>
            <button type="button" onClick={() => setAdding(false)} className={k.ghost}>{t('groups.cancel')}</button>
          </form>
        ) : canEditGroups ? (
          <div className="pt-2">
            <button type="button" onClick={() => setAdding(true)} className={k.dashed}>{t('groups.add')}</button>
          </div>
        ) : null}
      </div>
      <div className={k.card}>
        <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('groups.defaults')}</div>
        {entities.map((e) => (
          <label key={e.key} className="flex items-center justify-between gap-3 border-b border-line px-[18px] py-[9px] text-12.5">
            <b>{ent(e.key)}</b>
            <select
              aria-label={t('groups.defaultFor', { entity: ent(e.key) })}
              value={e.value}
              disabled={!canEditDefaults || pending}
              onChange={(ev) => run(() => setSetting({ key: 'visibility_default', value: ev.target.value, scopeId: e.key }), () => t('groups.saved'))}
              className="h-[30px] max-w-[62%] rounded-8 border border-line bg-canvas text-12 text-ink"
            >
              {options.map((o) => <option key={o} value={o}>{t(`rules.items.visibility_default.options.${o}`)}</option>)}
            </select>
          </label>
        ))}
        <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('groups.foot')}</div>
      </div>
    </div>
  )
}
