import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadDocument, loadDocuments, loadMergeFields, loadStorage, loadTeams, loadTemplates, loadViews } from '@/lib/data/documents'
import { TABS, type Rights, type Tab } from '@/lib/data/documents-shared'
import { DocumentsScreen } from './_components/DocumentsScreen'

/**
 * Documents (Documents.dc.html): documents made from templates on deals, their trackable links and views, the
 * templates, e-signature and where documents are stored. ?tab=<tab> opens a tab, ?doc=<id> a document.
 */
export default async function DocumentsPage({ searchParams }: { searchParams: Promise<{ tab?: string; doc?: string }> }) {
  const shell = await getShell()
  const sp = await searchParams
  const t = await getTranslations('common')
  const rights: Rights = {
    meId: shell.me.id,
    see: can(shell, 'deals', 'see'),
    add: can(shell, 'deals', 'add'),
    editOthers: can(shell, 'deals', 'edit_others'),
    remove: can(shell, 'deals', 'delete'),
    configureDeals: can(shell, 'deals', 'configure'),
    configureGlobal: can(shell, 'global', 'configure'),
  }

  const [list, templates, storage, merge, teams] = await Promise.all([
    rights.see ? loadDocuments() : Promise.resolve(null),
    rights.see ? loadTemplates() : Promise.resolve(null),
    loadStorage(),
    rights.see ? loadMergeFields() : Promise.resolve([]),
    rights.see ? loadTeams(shell.me.id, rights.configureDeals) : Promise.resolve([]),
  ])

  if (!storage.ok && storage.code === 'module_off') {
    return (
      <div className="px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-13 text-muted">{t('errors.module_off')}</div>
      </div>
    )
  }

  const rows = list && list.ok ? list.data.rows : []
  const asked = z.string().uuid().safeParse(sp.doc)
  const selected = (asked.success ? rows.find((r) => r.id === asked.data) : undefined) ?? rows[0] ?? null
  const [detail, views] = selected ? await Promise.all([loadDocument(selected.id), loadViews(selected.id)]) : [null, null]
  const tab = (TABS as readonly string[]).includes(sp.tab ?? '') ? (sp.tab as Tab) : 'docs'

  return (
    <DocumentsScreen
      initialTab={rights.see ? tab : 'settings'}
      list={list ? (list.ok ? { ok: true, total: list.data.total, rows } : { ok: false, code: list.code }) : null}
      templates={templates && templates.ok ? templates.data : []}
      templatesError={templates && !templates.ok ? templates.code : null}
      initial={detail && detail.ok ? { doc: detail.data, views: views && views.ok ? views.data : [] } : null}
      initialSign={asked.success && tab === 'sign' && selected?.id === asked.data ? asked.data : null}
      storage={storage.ok ? storage.data : null}
      storageError={storage.ok ? null : storage.code}
      merge={merge}
      teams={teams}
      products={shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color }))}
      rights={rights}
    />
  )
}
