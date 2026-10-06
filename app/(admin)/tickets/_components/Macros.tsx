'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { publishMacro } from '../actions'
import { useLabel } from './lib'
import type { Macro } from '@/lib/data/tickets'

const MERGE = ['[fornavn]', '[organisasjon]', '[orgnr]', '[agent]', '[dato]', '[dager]', '[domene]', '[antall]']

/** Macros (Tickets.dc.html, v.macros): the list with use counts, and the published text per language, versioned. */
export function Macros({ macros, canConfigure }: { macros: Macro[]; canConfigure: boolean }) {
  const t = useTranslations('tickets.macros')
  if (!macros.length) {
    return <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{t('empty')}</div>
  }
  return <MacroEditor macros={macros} canConfigure={canConfigure} />
}

function MacroEditor({ macros, canConfigure }: { macros: Macro[]; canConfigure: boolean }) {
  const t = useTranslations('tickets.macros')
  const tc = useTranslations('common')
  const cat = useLabel('categories')
  const flash = useToast()
  const [sel, setSel] = useState(0)
  const [locale, setLocale] = useState<'nb' | 'nn'>('nb')
  const m = macros[Math.min(sel, macros.length - 1)]!
  const current = m.versions.filter((v) => v.locale === locale).sort((a, b) => b.version - a.version)[0] ?? null
  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const key = `${m.id}:${locale}`
  const body = drafts[key] ?? current?.body ?? ''
  const [busy, setBusy] = useState(false)
  const changed = body.trim() !== '' && body !== (current?.body ?? '')

  async function publish() {
    setBusy(true)
    const r = await publishMacro({ id: m.id, name: m.name, category: m.category_key, locale, body })
    setBusy(false)
    if (!r.ok) { flash(tc(`errors.${r.code}`)); return }
    setDrafts((d) => { const n = { ...d }; delete n[key]; return n })
    flash(t('published', { v: r.version }))
  }

  return (
    <div className="grid items-start gap-4 md:[grid-template-columns:minmax(240px,320px)_minmax(0,1fr)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        {macros.map((x, i) => (
          <button
            key={x.id}
            type="button"
            aria-current={i === sel ? 'true' : undefined}
            onClick={() => setSel(i)}
            className={`flex w-full cursor-pointer flex-col gap-[2px] border-0 border-b border-line px-4 py-[11px] text-left ${i === sel ? 'bg-highlight' : 'bg-transparent'}`}
          >
            <b className="text-13">{x.name}</b>
            <span className="text-11.5 text-muted">{t('used', { cat: x.category_key ? cat(x.category_key) : t('noCategory'), n: x.used })}</span>
          </button>
        ))}
      </div>
      <div className="flex min-w-0 flex-col gap-[10px] rounded-20 border border-line bg-surface px-[22px] py-5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="text-15 font-bold">{m.name}</span>
          <span className="text-12 text-muted">
            {current ? t('meta', { locale: t(`locales.${locale}`), v: current.version }) : t('metaNew', { locale: t(`locales.${locale}`) })}
          </span>
        </div>
        <textarea
          aria-label={t('bodyLabel')}
          value={body}
          readOnly={!canConfigure}
          onChange={(e) => setDrafts((d) => ({ ...d, [key]: e.target.value }))}
          className="min-h-[200px] rounded-12 border border-line bg-canvas px-[14px] py-3 text-13 leading-[1.6]"
        />
        <div className="flex flex-wrap gap-[6px]">
          {MERGE.map((f) => <span key={f} className="rounded-999 border border-line-strong px-[10px] py-1 font-[ui-monospace,Menlo,monospace] text-11.5">{f}</span>)}
        </div>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={() => setLocale(locale === 'nb' ? 'nn' : 'nb')} className="h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-[14px] text-12.5 font-semibold">
            {locale === 'nb' ? t('switchNn') : t('switchNb')}
          </button>
          <button
            type="button"
            disabled={!canConfigure || !changed || busy}
            onClick={() => void publish()}
            className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60"
          >
            {t('publish')}
          </button>
        </div>
      </div>
    </div>
  )
}
