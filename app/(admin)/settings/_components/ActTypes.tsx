'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { ActivityType } from '@/lib/data/settings'
import { saveActivityType } from '../actions'
import { DesignSwitch, k, useRun } from './kit'

/** Activity types (Settings.dc.html, v.acttypes): glyph, name, the custom fields that apply, the active switch, and a new type. */
export function ActTypes({ types, fields, canEdit }: { types: ActivityType[]; fields: { label: string; types: string[] | null }[]; canEdit: boolean }) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const [adding, setAdding] = useState(false)
  const [glyph, setGlyph] = useState('')
  const [name, setName] = useState('')
  // a seeded type is shown in the reader's language; a type an admin added keeps the name it was given
  const nameOf = (x: ActivityType) => (x.is_system && t.has(`acttypes.names.${x.key}`) ? t(`acttypes.names.${x.key}`) : x.name)
  const cfOf = (x: ActivityType) => fields.filter((f) => f.types === null || f.types.includes(x.id)).map((f) => f.label).join(', ') || '—'
  const row = 'grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 [grid-template-columns:30px_minmax(0,1fr)_minmax(0,1.2fr)_46px]'

  return (
    <div className={k.card}>
      <div className={`${k.cardHead} max-md:flex-col`}>
        <b className="text-14">{t('acttypes.title')}</b>
        <span className="text-12 text-muted">{t('acttypes.sub')}</span>
      </div>
      {!canEdit ? <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly', { right: t('rights.configure') })}</div> : null}
      {types.map((x) => (
        <div key={x.id} className={row}>
          <span className="flex h-[26px] w-[26px] items-center justify-center rounded-8 bg-tile" aria-hidden="true">{x.glyph}</span>
          <b className={x.active ? 'text-ink' : 'text-faint'}>{nameOf(x)}</b>
          <span className="text-muted">{t('acttypes.customFields', { list: cfOf(x) })}</span>
          <DesignSwitch
            size="sm"
            on={x.active}
            label={t('acttypes.switchLabel', { name: nameOf(x) })}
            disabled={!canEdit || pending}
            onChange={(on) => run(() => saveActivityType({ id: x.id, values: { active: on } }), () => t(on ? 'acttypes.on' : 'acttypes.off', { name: nameOf(x) }))}
          />
        </div>
      ))}
      {adding ? (
        <form
          className={row}
          onSubmit={(e) => {
            e.preventDefault()
            const n = name.trim()
            if (!n) return
            run(() => saveActivityType({ id: null, values: { name: n, ...(glyph.trim() ? { glyph: glyph.trim() } : {}) } }), () => {
              setAdding(false)
              setName('')
              setGlyph('')
              return t('acttypes.created', { name: n })
            })
          }}
        >
          <input aria-label={t('acttypes.glyph')} placeholder="⌂" value={glyph} maxLength={3} onChange={(e) => setGlyph(e.target.value)} className="h-[26px] w-[26px] rounded-8 border border-line bg-canvas p-0 text-center text-12.5 text-ink" />
          <input autoFocus aria-label={t('acttypes.name')} placeholder={t('acttypes.namePlaceholder')} value={name} maxLength={40} onChange={(e) => setName(e.target.value)} className={`${k.input} min-w-0 font-semibold`} />
          <span className="flex flex-wrap gap-2 [grid-column:3/5]">
            <button type="submit" disabled={pending || !name.trim()} className={k.primary}>{t('acttypes.create')}</button>
            <button type="button" onClick={() => setAdding(false)} className={k.ghost}>{t('acttypes.cancel')}</button>
          </span>
        </form>
      ) : null}
      {canEdit && !adding ? (
        <div className="px-[18px] py-[10px]">
          <button type="button" onClick={() => setAdding(true)} className={k.dashed}>{t('acttypes.add')}</button>
        </div>
      ) : null}
    </div>
  )
}
