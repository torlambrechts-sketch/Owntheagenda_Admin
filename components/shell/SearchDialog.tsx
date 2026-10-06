'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { search, type SearchResult } from '@/app/(admin)/shell-actions'
import { recordHref } from '@/lib/records-href'

/** ⌘K: records the staff member may see, by type; with nothing typed, the records they opened last. */
export function SearchDialog({ onClose }: { onClose: () => void }) {
  const t = useTranslations('shell.search')
  const router = useRouter()
  const [q, setQ] = useState('')
  const [results, setResults] = useState<SearchResult | null>(null)
  const [failed, setFailed] = useState(false)
  const seq = useRef(0)

  useEffect(() => {
    const n = ++seq.current
    const timer = setTimeout(() => {
      search(q).then((r) => {
        if (n !== seq.current) return
        setResults(r)
        setFailed(r === null)
      })
    }, q ? 160 : 0)
    return () => clearTimeout(timer)
  }, [q])

  const ini = (entity: string, title: string) =>
    entity === 'deal' ? '◆' : entity === 'ticket' ? '#' : entity === 'person'
      ? title.split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase()
      : title.slice(0, 2)

  return (
    <div onClick={onClose} className="fixed inset-0 z-[80] flex items-start justify-center bg-[rgba(25,21,16,.42)] pt-[90px]">
      <div
        role="dialog"
        aria-modal="true"
        aria-label={t('label')}
        onClick={(e) => e.stopPropagation()}
        className="w-[640px] max-w-[92vw] overflow-hidden rounded-22 border border-line bg-surface shadow-modal"
      >
        <div className="flex items-center gap-[10px] border-b border-line px-[18px] py-[14px]">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
            <path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-4-4" />
          </svg>
          <input
            autoFocus
            value={q}
            onChange={(e) => setQ(e.target.value)}
            aria-label={t('label')}
            placeholder={t('inputPlaceholder')}
            maxLength={100}
            className="h-9 flex-1 border-none bg-transparent text-15 outline-none"
          />
          <span className="text-11 text-faint">Esc</span>
        </div>
        <div className="max-h-[460px] overflow-auto p-2">
          {results?.map((g) => (
            <div key={g.group} className="py-[6px]">
              <div className="px-[10px] py-1 text-10.5 font-bold uppercase tracking-label text-muted">{t(`groups.${g.group}`)}</div>
              {g.items.map((it) => (
                <button
                  key={`${it.entity}:${it.id}`}
                  type="button"
                  onClick={() => { onClose(); router.push(recordHref(it.entity, it.id) as never) }}
                  className="flex w-full cursor-pointer items-center gap-[10px] rounded-11 border-none bg-transparent px-[10px] py-[9px] text-left hover:bg-canvas"
                >
                  <span className="flex h-7 w-7 flex-none items-center justify-center rounded-8 bg-tile text-11 font-bold">{ini(it.entity, it.title ?? '')}</span>
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="text-13.5 font-semibold">{it.title}</span>
                    <span className="text-12 text-muted">{[t(`types.${it.entity}`), it.sub].filter(Boolean).join(' · ')}</span>
                  </span>
                  <span className="text-11.5 text-faint">↵</span>
                </button>
              ))}
            </div>
          ))}
          {results && results.length === 0 && q.trim() ? (
            <div className="p-[26px] text-center text-13 text-muted">{t('none', { q: q.trim() })}</div>
          ) : null}
          {results && results.length === 0 && !q.trim() ? <div className="p-[26px] text-center text-13 text-muted">{t('noRecent')}</div> : null}
          {failed ? <div role="alert" className="p-[26px] text-center text-13 text-danger">{t('failed')}</div> : null}
        </div>
        <div className="border-t border-line px-[18px] py-[10px] text-11.5 text-faint">{t('footer')}</div>
      </div>
    </div>
  )
}
