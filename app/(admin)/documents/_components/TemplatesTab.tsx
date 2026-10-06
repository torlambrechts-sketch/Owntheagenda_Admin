'use client'

import { useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import {
  CATEGORIES, SHARES, TABLE_COLUMNS, TEMPLATE_LANGUAGES,
  type Category, type MergeField, type Rights, type StorageState, type TeamOption, type Template, type TemplateDetail,
} from '@/lib/data/documents-shared'
import { deleteTemplateAction, importTemplateAction, saveTemplateAction, templateAction } from '../actions'
import { Modal, btnCancel, btnConfirm, btnDanger, field, fieldInput, note } from './Modal'
import { mono, useError, type Product } from './util'

// the design's category pills; «Other» joins them only when a template is filed there
const PILLS: Category[] = ['quotes', 'contracts', 'presentations', 'spreadsheets']
const COPY = '00000000-0000-4000-8000-000000000000'
const stripes = '[background:repeating-linear-gradient(135deg,#F2EAD6_0_8px,#FCF6E9_8px_16px)]'

/** Templates (DOC-01): category pills, a card per template, import from a drive, and the editor (D-41). */
export function TemplatesTab(p: {
  templates: Template[]
  error: string | null
  storage: StorageState | null
  merge: MergeField[]
  teams: TeamOption[]
  products: Product[]
  rights: Rights
  onChanged: () => void
  onGoStorage: () => void
}) {
  const t = useTranslations('documents.templates')
  const err = useError()
  const flash = useToast()
  const [cat, setCat] = useState<Category | 'all'>('all')
  const [editing, setEditing] = useState<TemplateDetail | 'new' | null>(null)
  const [importing, setImporting] = useState(false)
  const pills: (Category | 'all')[] = ['all', ...PILLS, ...(p.templates.some((x) => x.category === 'other') ? (['other'] as const) : [])]
  const shown = p.templates.filter((x) => cat === 'all' || x.category === cat)
  const share = (x: Template) => (x.share === 'team' ? x.team_name ?? t('share.team') : t(`share.${x.share}`))

  async function open(id: string) {
    const r = await templateAction({ id })
    if (!r.ok) return flash(err(r))
    setEditing(r.template)
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        {pills.map((c) => (
          <button key={c} type="button" aria-pressed={cat === c} onClick={() => setCat(c)}
            className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${cat === c ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
            {c === 'all' ? t('all') : t(`cat.${c}`)}
          </button>
        ))}
        <span className="flex-1" />
        {p.rights.add ? (
          <button type="button" onClick={() => setEditing('new')} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('new')}</button>
        ) : null}
        <button type="button" onClick={() => setImporting(true)} disabled={!p.rights.add}
          className="h-8 cursor-pointer rounded-9 border border-ink bg-surface px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('import')}</button>
      </div>
      {p.error ? <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-13 text-muted">{err({ code: p.error })}</div> : null}
      {!p.error && !shown.length ? (
        <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-12.5 text-muted">{p.templates.length ? t('emptyCategory') : t('empty')}</div>
      ) : null}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
        {shown.map((x) => (
          <button key={x.id} type="button" onClick={() => open(x.id)}
            className="flex cursor-pointer flex-col gap-2 rounded-20 border border-line bg-surface px-4 py-[14px] text-left">
            <span className={`flex h-[90px] w-full items-center justify-center rounded-12 text-10.5 text-muted ${stripes} ${mono}`}>{t(`kind.${x.kind}`)}</span>
            <b className="text-13.5">{x.name}</b>
            <span className="text-11.5 text-muted">{t(`cat.${x.category}`)} · {share(x)}</span>
            {x.placeholders.length ? (
              <span className="flex flex-wrap gap-1">
                {x.placeholders.map((ph) => <span key={ph} className={`rounded-6 bg-tile px-[7px] py-[2px] text-10.5 ${mono}`}>[{ph}]</span>)}
              </span>
            ) : null}
          </button>
        ))}
      </div>

      {editing ? (
        <TemplateEditor
          key={editing === 'new' ? 'new' : editing.id}
          template={editing === 'new' ? null : editing}
          merge={p.merge}
          teams={p.teams}
          products={p.products}
          rights={p.rights}
          onClose={() => setEditing(null)}
          onDone={(message) => { setEditing(null); flash(message); p.onChanged() }}
          onDuplicate={(copy) => setEditing(copy)}
        />
      ) : null}
      {importing ? <ImportModal storage={p.storage} onClose={() => setImporting(false)} onGoStorage={() => { setImporting(false); p.onGoStorage() }} onDone={() => { setImporting(false); flash(t('importQueued')); p.onChanged() }} /> : null}
    </div>
  )
}

type Draft = {
  name: string
  category: Category
  share: (typeof SHARES)[number]
  team_id: string | null
  product: string | null
  language: (typeof TEMPLATE_LANGUAGES)[number]
  body_html: string
  table: boolean
  columns: (typeof TABLE_COLUMNS)[number][]
  validity_days: string
  number_prefix: string
}

const fromTemplate = (x: TemplateDetail | null): Draft => ({
  name: x?.name ?? '',
  category: x?.category ?? 'quotes',
  share: x?.share ?? 'private',
  team_id: x?.team_id ?? null,
  product: x?.product ?? null,
  language: x?.language ?? 'nb',
  body_html: x?.body_html ?? '',
  table: x ? x.product_table !== null : true,
  columns: x?.product_table?.columns ?? ['name', 'qty', 'price', 'discount', 'total'],
  validity_days: x?.validity_days ? String(x.validity_days) : '',
  number_prefix: x?.number_prefix ?? '',
})

/**
 * Create, edit, duplicate and delete a platform template (D-41): the body with its tokens, the product-table
 * columns (DOC-02), validity days and number prefix for quotes, the brand (product). A drive template's content
 * lives in the drive; only its name and filing change here.
 */
function TemplateEditor(p: {
  template: TemplateDetail | null
  merge: MergeField[]
  teams: TeamOption[]
  products: Product[]
  rights: Rights
  onClose: () => void
  onDone: (message: string) => void
  onDuplicate: (copy: TemplateDetail) => void
}) {
  const t = useTranslations('documents.editor')
  const tt = useTranslations('documents.templates')
  const tc = useTranslations('common')
  const err = useError()
  const x = p.template
  const [d, setD] = useState<Draft>(() => fromTemplate(x))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [unknown, setUnknown] = useState<string[]>(x?.unknown ?? [])
  const body = useRef<HTMLTextAreaElement>(null)
  const platform = !x || x.source === 'platform'
  const editable = !x || x.can_edit
  // a duplicate is a new template: it carries the content and is saved with no id
  const isCopy = x?.id === COPY
  const asNew = !x || isCopy
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setD((o) => ({ ...o, [k]: v }))

  function insert(token: string) {
    const el = body.current
    const text = `[${token}]`
    if (!el) return set('body_html', d.body_html + text)
    const [a, b] = [el.selectionStart ?? d.body_html.length, el.selectionEnd ?? d.body_html.length]
    const next = d.body_html.slice(0, a) + text + d.body_html.slice(b)
    set('body_html', next)
    requestAnimationFrame(() => { el.focus(); el.setSelectionRange(a + text.length, a + text.length) })
  }

  async function save() {
    setBusy(true); setError(null)
    const values = {
      name: d.name.trim(), category: d.category, share: d.share, team_id: d.share === 'team' ? d.team_id : null, product: d.product, language: d.language,
      validity_days: d.validity_days ? Number(d.validity_days) : null, number_prefix: d.number_prefix.trim() || null,
      ...(platform ? { body_html: d.body_html, product_table: d.table && d.columns.length ? { columns: TABLE_COLUMNS.filter((c) => d.columns.includes(c)) } : null } : {}),
    }
    const r = await saveTemplateAction({ id: asNew ? null : x!.id, version: asNew ? null : x!.version, values })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    if (r.unknown.length) { setUnknown(r.unknown); p.onDone(t('savedUnknown', { tokens: r.unknown.map((u) => `[${u}]`).join(' ') })); return }
    p.onDone(asNew ? t('created') : t('saved'))
  }
  async function remove() {
    if (!x) return
    setBusy(true); setError(null)
    const r = await deleteTemplateAction({ id: x.id })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    p.onDone(t('deleted'))
  }
  function duplicate() {
    if (!x) return
    p.onDuplicate({ ...x, id: COPY, name: t('copyOf', { name: x.name }), share: 'private', team_id: null, team_name: null, can_edit: true, versions: [], source: 'platform', kind: 'document' })
  }

  const tokens = p.merge.filter((m) => m.token.includes('.') && m.token[0] === m.token[0]!.toLowerCase())

  return (
    <Modal eyebrow={t('eyebrow')} title={asNew ? (isCopy ? d.name || t('newTitle') : t('newTitle')) : x!.name} onClose={p.onClose} width={760}>
      {!editable ? <div className={note}>{t('readOnly')}</div> : null}
      {!platform ? <div className={note}>{t('drive', { provider: x!.source === 'google' ? 'Google Drive' : 'OneDrive' })}</div> : null}
      <div className="grid gap-3 md:grid-cols-2">
        <label className={field}>{t('name')}<input value={d.name} maxLength={120} disabled={!editable} onChange={(e) => set('name', e.target.value)} className={fieldInput} /></label>
        <label className={field}>{t('category')}
          <select value={d.category} disabled={!editable} onChange={(e) => set('category', e.target.value as Category)} className={fieldInput}>
            {CATEGORIES.map((c) => <option key={c} value={c}>{tt(`cat.${c}`)}</option>)}
          </select>
        </label>
        <label className={field}>{t('share')}
          <select value={d.share} disabled={!editable} onChange={(e) => set('share', e.target.value as Draft['share'])} className={fieldInput}>
            {SHARES.map((s) => <option key={s} value={s} disabled={(s === 'company' && !p.rights.configureDeals) || (s === 'team' && !p.teams.length)}>{tt(`share.${s}`)}</option>)}
          </select>
        </label>
        {d.share === 'team' ? (
          <label className={field}>{t('team')}
            <select value={d.team_id ?? ''} disabled={!editable} onChange={(e) => set('team_id', e.target.value || null)} className={fieldInput}>
              <option value="">—</option>
              {p.teams.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
          </label>
        ) : (
          <label className={field}>{t('language')}
            <select value={d.language} disabled={!editable} onChange={(e) => set('language', e.target.value as Draft['language'])} className={fieldInput}>
              {TEMPLATE_LANGUAGES.map((l) => <option key={l} value={l}>{t(`lang.${l}`)}</option>)}
            </select>
          </label>
        )}
        {d.share === 'team' ? (
          <label className={field}>{t('language')}
            <select value={d.language} disabled={!editable} onChange={(e) => set('language', e.target.value as Draft['language'])} className={fieldInput}>
              {TEMPLATE_LANGUAGES.map((l) => <option key={l} value={l}>{t(`lang.${l}`)}</option>)}
            </select>
          </label>
        ) : null}
        <label className={field}>{t('product')}
          <select value={d.product ?? ''} disabled={!editable} onChange={(e) => set('product', e.target.value || null)} className={fieldInput}>
            <option value="">{t('productDeal')}</option>
            {p.products.map((m) => <option key={m.key} value={m.key}>{m.name}</option>)}
          </select>
        </label>
        <label className={field}>{t('validity')}<input type="number" min={1} max={365} value={d.validity_days} disabled={!editable} onChange={(e) => set('validity_days', e.target.value)} className={fieldInput} /></label>
        <label className={field}>{t('prefix')}<input value={d.number_prefix} maxLength={5} placeholder="T-" disabled={!editable} onChange={(e) => set('number_prefix', e.target.value.toUpperCase())} className={fieldInput} /></label>
      </div>

      {platform ? (
        <>
          <fieldset className="m-0 flex flex-col gap-2 border-0 p-0">
            <legend className="mb-[6px] p-0 text-12 font-semibold text-muted">{t('table')}</legend>
            <label className="flex items-center gap-2 text-12.5"><input type="checkbox" checked={d.table} disabled={!editable} onChange={(e) => set('table', e.target.checked)} style={{ accentColor: '#191510' }} />{t('tableOn')}</label>
            {d.table ? (
              <div className="flex flex-wrap gap-x-[14px] gap-y-[6px]">
                {TABLE_COLUMNS.map((c) => (
                  <label key={c} className="flex items-center gap-[6px] text-12.5">
                    <input type="checkbox" checked={d.columns.includes(c)} disabled={!editable}
                      onChange={(e) => set('columns', e.target.checked ? [...d.columns, c] : d.columns.filter((y) => y !== c))} style={{ accentColor: '#191510' }} />
                    {t(`col.${c}`)}
                  </label>
                ))}
              </div>
            ) : null}
          </fieldset>
          <label className={field}>{t('body')}
            <textarea ref={body} value={d.body_html} disabled={!editable} spellCheck={false} onChange={(e) => set('body_html', e.target.value)}
              className={`min-h-[200px] rounded-10 border border-line bg-canvas px-3 py-[10px] text-12 font-normal leading-[1.5] text-ink ${mono}`} />
          </label>
          {editable ? (
            <div className="flex flex-col gap-[6px]">
              <span className="text-11.5 text-muted">{t('tokens')}</span>
              <div className="flex flex-wrap gap-1">
                {tokens.map((m) => (
                  <button key={m.token} type="button" onClick={() => insert(m.token)} className={`cursor-pointer rounded-6 border-0 bg-tile px-[7px] py-[2px] text-10.5 ${mono}`}>[{m.token}]</button>
                ))}
                <button type="button" onClick={() => insert('signer.1')} className={`cursor-pointer rounded-6 border-0 bg-tile px-[7px] py-[2px] text-10.5 ${mono}`}>[signer.1]</button>
              </div>
              <span className="text-11 text-muted">{t('tokensHint')}</span>
            </div>
          ) : null}
        </>
      ) : null}
      {unknown.length ? <div className={note}>{t('unknown', { tokens: unknown.map((u) => `[${u}]`).join(' ') })}</div> : null}
      {x && !isCopy && x.versions.length ? <span className="text-11 text-muted">{t('versions', { n: x.versions.length })}</span> : null}
      {error ? <div className={note}>{error}</div> : null}

      <div className="flex flex-wrap justify-end gap-2">
        {x && !isCopy && editable ? <button type="button" disabled={busy} onClick={remove} className={btnDanger}>{t('delete')}</button> : null}
        {x && !isCopy && platform && p.rights.add ? <button type="button" disabled={busy} onClick={duplicate} className={btnCancel}>{t('duplicate')}</button> : null}
        <span className="flex-1" />
        <button type="button" onClick={p.onClose} className={btnCancel}>{tc('cancel')}</button>
        {editable ? <button type="button" disabled={busy || !d.name.trim()} onClick={save} className={btnConfirm}>{tc('save')}</button> : null}
      </div>
    </Modal>
  )
}

/**
 * Import from drive: a presentation, spreadsheet or document from the staff member's own Google Drive or
 * OneDrive. No drive can be connected yet (no OAuth client), so the database answers not_connected and the
 * dialog says so before and after.
 */
function ImportModal({ storage, onClose, onGoStorage, onDone }: { storage: StorageState | null; onClose: () => void; onGoStorage: () => void; onDone: () => void }) {
  const t = useTranslations('documents.import')
  const tc = useTranslations('common')
  const err = useError()
  const [provider, setProvider] = useState<'google' | 'microsoft'>('google')
  const [file, setFile] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const connected = storage?.connections.find((c) => c.provider === provider && c.status === 'connected') ?? null

  async function run() {
    setBusy(true); setError(null)
    const r = await importTemplateAction({ provider, file })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    onDone()
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={t('title')} onClose={onClose}>
      <div className="flex rounded-10 bg-tile p-[3px]">
        {(['google', 'microsoft'] as const).map((k) => (
          <button key={k} type="button" aria-pressed={provider === k} onClick={() => setProvider(k)}
            className={`flex-1 cursor-pointer rounded-7 border-0 p-[7px] text-12 ${provider === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>{t(k)}</button>
        ))}
      </div>
      <span className="text-12 text-muted">{connected ? t('connected', { email: connected.account_email ?? '' }) : t('notConnected')}</span>
      <label className={field}>{t('file')}<input value={file} maxLength={300} onChange={(e) => setFile(e.target.value)} className={fieldInput} /></label>
      <span className="text-11.5 text-muted">{t('kinds')}</span>
      {error ? <div className={note}>{error}</div> : null}
      <div className="flex flex-wrap justify-end gap-2">
        {!connected ? <button type="button" onClick={onGoStorage} className={btnCancel}>{t('goStorage')}</button> : null}
        <span className="flex-1" />
        <button type="button" onClick={onClose} className={btnCancel}>{tc('cancel')}</button>
        <button type="button" disabled={busy || !file.trim()} onClick={run} className={btnConfirm}>{t('go')}</button>
      </div>
    </Modal>
  )
}
