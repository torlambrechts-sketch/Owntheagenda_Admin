'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { ACTION_KEYS, SCOPE_KEYS } from '@/lib/data/settings-matrix'
import { savePermissionSet } from '../actions'
import { k, useRun } from './kit'

type Set = { id: string; key: string | null; name: string; kind: 'admin' | 'regular' | 'custom'; rights: string[]; members: number }
const COLS = '[grid-template-columns:minmax(0,1.8fr)_repeat(5,80px)]'

/**
 * Permission sets (Settings.dc.html, v.perms): action × scope. The design draws Deals, Projects, Campaigns and
 * Global; the database also has Tickets (0012), so it is a column too. A cell saves at once. Admin is locked.
 */
const PRESETS = ['admin', 'sales', 'marketing', 'project', 'support', 'finance', 'analyst']

export function Perms({ sets: raw, canEdit }: { sets: Set[]; canEdit: boolean }) {
  // the design's order: the presets as D-08 lists them, then custom sets by name
  const rank = (s: Set) => (s.key && PRESETS.includes(s.key) ? PRESETS.indexOf(s.key) : PRESETS.length)
  const sets = [...raw].sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name))
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const [sel, setSel] = useState(sets.find((s) => s.key === 'sales')?.id ?? sets[0]?.id ?? '')
  const [adding, setAdding] = useState(false)
  const [name, setName] = useState('')
  const cur = sets.find((s) => s.id === sel) ?? sets[0]
  if (!cur) return null
  const locked = cur.kind === 'admin'
  const has = (r: string) => locked || cur.rights.includes(r)
  const toggle = (r: string) => {
    const rights = has(r) ? cur.rights.filter((x) => x !== r) : [...cur.rights, r]
    run(() => savePermissionSet({ id: cur.id, name: cur.name, rights }), () => t('perms.saved', { name: cur.name }))
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[6px]">
        {sets.map((s) => (
          <button key={s.id} type="button" aria-pressed={cur.id === s.id} onClick={() => setSel(s.id)} className={k.chip(cur.id === s.id)}>
            {s.name}
          </button>
        ))}
        {canEdit && !adding ? (
          <button type="button" onClick={() => setAdding(true)} className={k.dashedChip}>{t('perms.add')}</button>
        ) : null}
        {adding ? (
          <form
            className="flex items-center gap-1"
            onSubmit={(e) => {
              e.preventDefault()
              const n = name.trim()
              if (!n) return
              run(() => savePermissionSet({ id: null, name: n, rights: [] }), (r) => {
                setSel(r.id)
                setAdding(false)
                setName('')
                return t('perms.created', { name: n })
              })
            }}
          >
            <input autoFocus aria-label={t('perms.addName')} placeholder={t('perms.addName')} value={name} maxLength={80} onChange={(e) => setName(e.target.value)} className="h-[30px] rounded-999 border border-line-strong bg-canvas px-3 text-12 text-ink" />
            <button type="submit" disabled={pending || !name.trim()} className={k.dashedChip}>{t('perms.addSubmit')}</button>
            <button type="button" onClick={() => setAdding(false)} className="cursor-pointer border-none bg-transparent px-2 text-12 text-muted">{t('perms.cancel')}</button>
          </form>
        ) : null}
      </div>
      <div className={`${k.card} overflow-x-auto`}>
        <div className={`grid min-w-[620px] gap-[10px] border-b border-line px-[18px] py-[9px] ${k.colHead} ${COLS}`}>
          <span>{t('perms.cols.action')}</span>
          {SCOPE_KEYS.map((s) => <span key={s}>{t(`perms.scopes.${s}`)}</span>)}
        </div>
        {ACTION_KEYS.map((a) => (
          <div key={a} className={`grid min-w-[620px] items-center gap-[10px] border-b border-line px-[18px] py-2 text-12.5 ${COLS}`}>
            <span>{t(`perms.actions.${a}`)}</span>
            {SCOPE_KEYS.map((s) => {
              const r = `${s}:${a}`
              const on = has(r)
              return (
                <button
                    key={s}
                    type="button"
                    role="checkbox"
                    aria-checked={on}
                    aria-label={t('perms.cell', { action: t(`perms.actions.${a}`), scope: t(`perms.scopes.${s}`) })}
                    disabled={locked || !canEdit || pending}
                    onClick={() => toggle(r)}
                    className={`h-[22px] w-[22px] cursor-pointer rounded-6 border-[1.5px] p-0 text-11 text-ok-ink disabled:cursor-default ${on ? 'border-link bg-ok-bg' : 'border-line-strong bg-transparent'}`}
                  >
                    {on ? '✓' : ''}
                  </button>
              )
            })}
          </div>
        ))}
        <div className="flex flex-col gap-1 px-[18px] py-[10px] text-11.5 text-muted">
          {locked ? <span>{t('perms.locked')}</span> : null}
          {!canEdit ? <span>{t('readOnly', { right: t('rights.security') })}</span> : null}
          <span>{t('perms.members', { count: cur.members })}</span>
          <span>{t('perms.foot')}</span>
        </div>
      </div>
    </div>
  )
}
