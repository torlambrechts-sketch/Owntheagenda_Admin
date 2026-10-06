'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { DocDetail, DocRow, DocView, MergeField, Rights, StorageState, Tab, TeamOption, Template } from '@/lib/data/documents-shared'
import { TABS } from '@/lib/data/documents-shared'
import { documentAction } from '../actions'
import { DocumentsTab } from './DocumentsTab'
import { NewDocumentModal } from './NewDocumentModal'
import { SignTab } from './SignTab'
import { StorageTab } from './StorageTab'
import { TemplatesTab } from './TemplatesTab'
import { useError, type Product } from './util'

export type Loaded = { doc: DocDetail; views: DocView[] }
type ListState = { ok: true; total: number; rows: DocRow[] } | { ok: false; code: string } | null

/** Documents (Documents.dc.html): four tabs, «＋ Document from template», and the toast. */
export function DocumentsScreen(p: {
  initialTab: Tab
  list: ListState
  templates: Template[]
  templatesError: string | null
  initial: Loaded | null
  initialSign: string | null
  storage: StorageState | null
  storageError: string | null
  merge: MergeField[]
  teams: TeamOption[]
  products: Product[]
  rights: Rights
}) {
  const t = useTranslations('documents')
  const router = useRouter()
  const flash = useToast()
  const err = useError()
  const [tab, setTab] = useState<Tab>(p.initialTab)
  const rows = useMemo(() => (p.list && p.list.ok ? p.list.rows : []), [p.list])
  const [selected, setSelected] = useState<string | null>(p.initial?.doc.id ?? rows[0]?.id ?? null)
  const [signDoc, setSignDoc] = useState<string | null>(p.initialSign)
  const [loaded, setLoaded] = useState<Record<string, Loaded>>(() => (p.initial ? { [p.initial.doc.id]: p.initial } : {}))
  const [creating, setCreating] = useState(false)

  const address = (k: Tab, doc: string | null) => {
    try {
      const u = new URL(window.location.href)
      u.searchParams.set('tab', k)
      if (doc) u.searchParams.set('doc', doc); else u.searchParams.delete('doc')
      window.history.replaceState(null, '', u)
    } catch { /* the address is a convenience */ }
  }
  const pick = (k: Tab) => { setTab(k); address(k, k === 'sign' ? signDoc : k === 'docs' ? selected : null) }

  /** Loads a document (and its views) into the cache; `fresh` reloads one already there. */
  const load = useCallback(async (id: string, fresh = false) => {
    if (!fresh && loaded[id]) return loaded[id]
    const r = await documentAction({ id })
    if (!r.ok) { flash(err(r)); return null }
    const v = { doc: r.doc, views: r.views }
    setLoaded((m) => ({ ...m, [id]: v }))
    return v
  }, [loaded, flash, err])

  // the list may have changed under the selection (a document deleted, the first load empty)
  useEffect(() => {
    if (selected && !rows.some((r) => r.id === selected)) setSelected(rows[0]?.id ?? null)
  }, [rows, selected])
  useEffect(() => { if (selected && !loaded[selected]) void load(selected) }, [selected, loaded, load])

  /** After a change: the document again, and the server's list. */
  const changed = useCallback(async (id: string | null) => {
    if (id) await load(id, true)
    router.refresh()
  }, [load, router])

  const choose = (id: string) => { setSelected(id); address('docs', id) }
  const requestSignature = (id: string) => { setSignDoc(id); setTab('sign'); address('sign', id) }
  const tabs = p.rights.see ? TABS : (['settings'] as const)

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-[6px]">
          {tabs.map((k) => (
            <button key={k} type="button" aria-pressed={tab === k} onClick={() => pick(k)}
              className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${tab === k ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}>
              {t(`tabs.${k}`)}
            </button>
          ))}
        </div>
        <span className="flex-1" />
        {p.rights.see ? (
          <button type="button" onClick={() => setCreating(true)} disabled={!p.rights.add} title={p.rights.add ? undefined : t('noRight')}
            className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60">
            {t('newDoc')}
          </button>
        ) : null}
      </div>

      {tab === 'docs' ? (
        <DocumentsTab
          list={p.list}
          selected={selected}
          loaded={selected ? loaded[selected] ?? null : null}
          templates={p.templates}
          products={p.products}
          rights={p.rights}
          onChoose={choose}
          onChanged={changed}
          onNew={() => setCreating(true)}
          onRequestSignature={requestSignature}
        />
      ) : null}
      {tab === 'templates' ? (
        <TemplatesTab templates={p.templates} error={p.templatesError} storage={p.storage} merge={p.merge} teams={p.teams} products={p.products} rights={p.rights}
          onChanged={() => router.refresh()} onGoStorage={() => pick('settings')} />
      ) : null}
      {tab === 'sign' ? (
        <SignTab
          docId={signDoc}
          rows={rows}
          loaded={signDoc ? loaded[signDoc] ?? null : null}
          load={load}
          storage={p.storage}
          rights={p.rights}
          onPick={(id) => { setSignDoc(id); address('sign', id) }}
          onChanged={changed}
        />
      ) : null}
      {tab === 'settings' ? <StorageTab storage={p.storage} error={p.storageError} onChanged={() => router.refresh()} /> : null}

      {creating ? (
        <NewDocumentModal
          templates={p.templates}
          storage={p.storage}
          onClose={() => setCreating(false)}
          onCreated={(id) => { setTab('docs'); choose(id); void changed(id) }}
        />
      ) : null}
    </div>
  )
}
