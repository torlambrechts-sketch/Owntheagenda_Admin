'use client'

import Link from 'next/link'
import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { setProduct } from '@/app/(admin)/shell-actions'
import type { ShellData } from './types'

/** «All applications» or one product: the scope the overview and lists are filtered to. */
export function ProductPicker({ shell, product }: { shell: ShellData; product: string }) {
  const t = useTranslations('shell.products')
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [, start] = useTransition()
  const ref = useRef<HTMLDivElement>(null)
  const connected = shell.products.filter((p) => p.installed && p.enabled).length
  const all = { key: 'all', name: t('all'), description: t('connected', { count: connected }), color: '#F5C64A', installed: true, enabled: true }
  const options = [all, ...shell.products.map((p) => ({ ...p, description: p.description ?? '' }))]
  const cur = options.find((p) => p.key === product) ?? all

  useEffect(() => {
    if (!open) return
    const onDoc = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false) }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDoc)
    window.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('mousedown', onDoc); window.removeEventListener('keydown', onKey) }
  }, [open])

  return (
    <div ref={ref} className="relative px-3 pb-[6px] pt-1">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className="flex h-10 w-full cursor-pointer items-center gap-[9px] rounded-10 border border-line bg-canvas px-[10px] text-left"
      >
        <span className="h-[18px] w-[18px] flex-none rounded-6 border border-[rgba(25,21,16,.15)]" style={{ background: cur.color }} />
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="overflow-hidden text-ellipsis whitespace-nowrap text-13 font-bold">{cur.name}</span>
          <span className="text-11 text-muted">{cur.description}</span>
        </span>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>
      {open ? (
        <div className="absolute left-3 right-3 top-12 z-[60] rounded-18 border border-line bg-surface p-[6px] shadow-pop">
          <div className="px-[10px] pb-[6px] pt-2 text-10.5 font-bold uppercase tracking-label text-muted">{t('heading')}</div>
          {options.map((p) => {
            const sel = p.key === cur.key
            return (
              <button
                key={p.key}
                type="button"
                onClick={() => {
                  setOpen(false)
                  start(async () => { await setProduct(p.key); router.refresh() })
                }}
                className={`flex w-full cursor-pointer items-center gap-[9px] rounded-10 border-none px-[10px] py-2 text-left ${sel ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <span className="h-4 w-4 flex-none rounded-5 border border-[rgba(25,21,16,.15)]" style={{ background: p.color }} />
                <span className="flex flex-1 flex-col">
                  <span className={`text-13 ${sel ? 'font-bold' : 'font-semibold'}`}>{p.name}</span>
                  <span className="text-11 text-muted">{p.description}</span>
                </span>
                <span className={`h-[7px] w-[7px] rounded-999 ${p.installed && p.enabled ? 'bg-ok' : 'bg-line-strong'}`} />
              </button>
            )
          })}
          <Link
            href="/applications"
            onClick={() => setOpen(false)}
            className="mt-1 flex w-full cursor-pointer items-center gap-2 rounded-10 border border-dashed border-line-strong bg-transparent px-[10px] py-[9px] text-12.5 font-semibold text-ink hover:text-ink hover:no-underline"
          >
            {t('connect')}
          </Link>
        </div>
      ) : null}
    </div>
  )
}
