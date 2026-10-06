'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import type { PersonHit } from '@/lib/data/deals'
import { searchPeople } from '../actions'

/** A person or organization search in the drawer (participants, primary person, organization). */
export function Picker({ entity, onPick, onCancel }: { entity: 'person' | 'organization'; onPick: (h: PersonHit) => void; onCancel: () => void }) {
  const t = useTranslations('deals.drawer.picker')
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<PersonHit[]>([])
  const ref = useRef<HTMLInputElement>(null)
  const seq = useRef(0)
  useEffect(() => { ref.current?.focus() }, [])
  useEffect(() => {
    const n = ++seq.current
    const h = setTimeout(() => {
      void searchPeople({ entity, q }).then((r) => { if (n === seq.current && r.ok) setHits(r.rows) })
    }, 200)
    return () => clearTimeout(h)
  }, [q, entity])
  return (
    <div className="flex flex-col gap-1">
      <div className="flex gap-[6px]">
        <input
          ref={ref}
          value={q}
          aria-label={t(entity)}
          placeholder={t(entity)}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); onCancel() } }}
          className="h-8 min-w-0 flex-1 rounded-9 border border-line bg-canvas px-2 text-12.5"
        />
        <button type="button" onClick={onCancel} aria-label={t('cancel')} className="h-8 w-8 cursor-pointer rounded-999 border border-line bg-transparent">×</button>
      </div>
      {hits.map((h) => (
        <button key={h.id} type="button" onClick={() => onPick(h)} className="flex cursor-pointer flex-col items-start rounded-9 border-none bg-transparent px-2 py-[5px] text-left text-12.5 hover:bg-canvas">
          <b>{h.name}</b>
          {h.title || h.city ? <span className="text-11.5 text-muted">{[h.title, h.city].filter(Boolean).join(' · ')}</span> : null}
        </button>
      ))}
      {q && hits.length === 0 ? <span className="px-2 text-11.5 text-faint">{t('none')}</span> : null}
    </div>
  )
}
