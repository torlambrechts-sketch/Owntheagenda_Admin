'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { PUBLIC_HOST, STATUS_PILL, type DocDetail, type DocRow, type Rights, type Template } from '@/lib/data/documents-shared'
import { createLinkAction, deleteDocumentAction, fileAction, revokeLinkAction, updateDocumentAction } from '../actions'
import type { Loaded } from './DocumentsScreen'
import { Modal, btnCancel, btnConfirm, btnDanger, field, fieldInput, note } from './Modal'
import { copyText, mono, publicUrl, useDate, useError, useWhen, type Product } from './util'

const cols = '[grid-template-columns:minmax(180px,1.6fr)_minmax(130px,1.2fr)_120px_80px_100px]'
const btnLink = 'h-[30px] cursor-pointer rounded-9 border px-[11px] text-12 disabled:cursor-default disabled:opacity-60'

/** A status pill in the design's colours. */
export function StatusPill({ status }: { status: DocRow['status'] }) {
  const t = useTranslations('documents.status')
  const [bg, c] = STATUS_PILL[status]
  return <span className="rounded-999 px-[9px] py-[2px] text-11 font-bold" style={{ background: bg, color: c }}>{t(status)}</span>
}

/** Documents tab: the list on the left; the selected document's preview and its trackable link on the right. */
export function DocumentsTab(p: {
  list: { ok: true; total: number; rows: DocRow[] } | { ok: false; code: string } | null
  selected: string | null
  loaded: Loaded | null
  templates: Template[]
  products: Product[]
  rights: Rights
  onChoose: (id: string) => void
  onChanged: (id: string | null) => Promise<void>
  onNew: () => void
  onRequestSignature: (id: string) => void
}) {
  const t = useTranslations('documents')
  const err = useError()
  if (!p.list || !p.list.ok) {
    return <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-13 text-muted">{p.list ? err({ code: p.list.code }) : t('noRight')}</div>
  }
  const { rows, total } = p.list
  if (!rows.length) {
    return (
      <div className="flex flex-col items-start gap-[10px] rounded-20 border border-line bg-surface px-[22px] py-5">
        <b className="text-14">{t('docs.emptyTitle')}</b>
        <span className="text-12.5 text-muted">{t('docs.emptyBody')}</span>
        {p.rights.add ? <button type="button" onClick={p.onNew} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">{t('newDoc')}</button> : null}
      </div>
    )
  }
  return (
    <div className="grid grid-cols-1 items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_minmax(320px,440px)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="overflow-x-auto">
          <div className="min-w-[650px]">
            <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${cols}`}>
              <span>{t('docs.col.document')}</span><span>{t('docs.col.deal')}</span><span>{t('docs.col.status')}</span><span>{t('docs.col.opens')}</span><span>{t('docs.col.stored')}</span>
            </div>
            {rows.map((d) => (
              <button key={d.id} type="button" onClick={() => p.onChoose(d.id)} aria-pressed={p.selected === d.id}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-b border-line px-4 py-[10px] text-left text-12.5 ${cols} ${p.selected === d.id ? 'bg-highlight' : 'bg-transparent'}`}>
                <span className="flex flex-col"><b>{d.name}</b><span className="text-11.5 text-muted">{d.source === 'upload' ? t('docs.uploaded') : d.template ?? '—'}</span></span>
                <span className="text-ink-2">{d.deal_title ?? d.organization_name ?? '—'}</span>
                <span><StatusPill status={d.status} /></span>
                <b>{d.opens}</b>
                <span className="text-muted">{t(`storage.${d.storage}`)}</span>
              </button>
            ))}
          </div>
        </div>
        {total > rows.length ? <div className="px-4 py-[9px] text-11.5 text-muted">{t('docs.more', { shown: rows.length, total })}</div> : null}
      </div>
      <div className="flex min-w-0 flex-col gap-3">
        {p.loaded ? (
          <>
            <Preview doc={p.loaded.doc} templates={p.templates} products={p.products} rights={p.rights} onChanged={p.onChanged} />
            <LinkCard loaded={p.loaded} rights={p.rights} onChanged={p.onChanged} onRequestSignature={p.onRequestSignature} />
          </>
        ) : (
          <div className="rounded-20 border border-line bg-surface p-[18px] text-12.5 text-muted">{t('loading')}</div>
        )}
      </div>
    </div>
  )
}

/** The rendered body's styles: the design's preview (title, line, product table, totals) applied to the document's HTML. */
const body = [
  '[&_h1]:m-0 [&_h1]:mt-4 [&_h1]:font-serif [&_h1]:text-20 [&_h1]:font-semibold [&_h1]:leading-[1.3]',
  '[&_h2]:m-0 [&_h2]:mt-[14px] [&_h2]:font-serif [&_h2]:text-16 [&_h2]:font-semibold',
  '[&_p]:m-0 [&_p]:mt-1 [&_p]:text-12 [&_p]:leading-[1.55] [&_p]:text-ink-2',
  '[&_ul]:my-1 [&_ul]:pl-5 [&_ul]:text-12 [&_ul]:text-ink-2 [&_ol]:my-1 [&_ol]:pl-5 [&_ol]:text-12 [&_ol]:text-ink-2',
  '[&_table]:mt-[14px] [&_table]:w-full [&_table]:border-collapse',
  '[&_thead_th]:border-t [&_thead_th]:border-ink [&_thead_th]:py-[7px] [&_thead_th]:pr-[10px] [&_thead_th]:text-left [&_thead_th]:align-top [&_thead_th]:text-10 [&_thead_th]:font-bold [&_thead_th]:uppercase [&_thead_th]:tracking-[.06em] [&_thead_th]:text-muted',
  '[&_tbody_td]:border-t [&_tbody_td]:border-tile [&_tbody_td]:py-[6px] [&_tbody_td]:pr-[10px] [&_tbody_td]:align-top [&_tbody_td]:text-12',
  '[&_tbody_tr:last-child_td]:border-b [&_tbody_tr:last-child_td]:border-b-line',
  // numbers keep to one line; the description wraps (the design's minmax(0,1.6fr) column)
  '[&_.col-qty]:whitespace-nowrap [&_.col-price]:whitespace-nowrap [&_.col-discount]:whitespace-nowrap [&_.col-tax]:whitespace-nowrap [&_.col-period]:whitespace-nowrap [&_.col-total]:whitespace-nowrap',
  '[&_th.col-name]:w-full [&_.col-total]:pr-0 [&_.col-total]:text-right [&_td.col-total]:font-bold',
  '[&_tfoot_td]:py-1 [&_tfoot_td]:text-12 [&_tfoot_td:first-child]:text-muted [&_tfoot_td:last-child]:whitespace-nowrap [&_tfoot_td:last-child]:pl-3 [&_tfoot_td:last-child]:text-right [&_tfoot_td:last-child]:font-bold',
  '[&_tfoot_tr:first-child_td]:pt-[10px] [&_tfoot_tr.total_td:last-child]:text-15',
].join(' ')

/** The bodies the database accepts never carry script, frames, forms or event handlers; one that does is not shown. */
const unsafe = (html: string) => /<\s*\/?\s*(script|iframe|frame|object|embed|form|input|meta|link|base|style)\b|\son[a-z]+\s*=|javascript:|vbscript:|data:text\/html/i.test(html)

const LANG: Record<string, string> = { nb: 'nb', nn: 'nn', en: 'en-GB', sv: 'sv' }

/** The preview card: the document's brand (its deal's product, Q12), number and date, then its rendered body. */
function Preview({ doc, templates, products, rights, onChanged }: { doc: DocDetail; templates: Template[]; products: Product[]; rights: Rights; onChanged: (id: string | null) => Promise<void> }) {
  const t = useTranslations('documents')
  const flash = useToast()
  const err = useError()
  const date = useDate()
  const [editing, setEditing] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const product = products.find((x) => x.key === doc.product)
  const lang = doc.template?.language ?? 'nb'
  // the date is document content, written in the template's language (spec §2: «in the template's language»)
  const written = new Intl.DateTimeFormat(LANG[lang] ?? 'nb', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Oslo' }).format(new Date(doc.created_at))
  const placeholders = templates.find((x) => x.id === doc.template?.id)?.placeholders ?? []
  const draft = doc.status === 'draft'

  async function openFile() {
    const r = await fileAction({ id: doc.id })
    if (!r.ok) flash(err(r))
  }

  return (
    <div className="rounded-20 border border-line bg-surface p-[18px] shadow-soft">
      <div className="flex items-start justify-between gap-3">
        <span className="flex items-center gap-2">
          {product ? (
            product.key === 'orgpuls'
              // eslint-disable-next-line @next/next/no-img-element -- the bundle's own mark, served as a static file
              ? <img src="/brand/orgpuls-mark.svg" alt="" width={26} height={26} />
              : <span aria-hidden className="h-[26px] w-[26px] flex-none rounded-8" style={{ background: product.color }} />
          ) : null}
          <b className="font-serif text-16">{product?.name ?? doc.deal?.title ?? doc.organization?.name ?? ''}</b>
        </span>
        <span className="text-right text-11 text-muted">{doc.number ?? doc.name}<br />{written}</span>
      </div>

      {doc.source === 'upload' ? (
        <div className="mt-4 flex flex-col gap-2">
          <div className="font-serif text-20 font-semibold">{doc.name}</div>
          <div className="text-12 leading-[1.55] text-ink-2">{t('preview.uploaded', { size: doc.size_bytes ? Math.max(1, Math.round(doc.size_bytes / 1024)) : 0 })}</div>
          <div><button type="button" onClick={openFile} className={`${btnLink} border-line bg-transparent font-semibold`}>{t('preview.openPdf')}</button></div>
        </div>
      ) : doc.body_html && !unsafe(doc.body_html) ? (
        <div className={`overflow-x-auto ${body}`} dangerouslySetInnerHTML={{ __html: doc.body_html }} />
      ) : (
        <div className="mt-4 text-12 text-muted">{t('preview.noBody')}</div>
      )}

      {doc.merge_missing.length ? (
        <div className={`${note} mt-3`}>{t('preview.missing', { tokens: doc.merge_missing.map((x) => `[${x}]`).join(' ') })}</div>
      ) : null}

      <div className="mt-[10px] text-10.5 text-faint">
        {doc.source === 'template'
          ? (doc.totals ? t('preview.filled', { tokens: placeholders.map((x) => `[${x}]`).join(' ') }) : t('preview.placeholders', { tokens: placeholders.map((x) => `[${x}]`).join(' ') }))
          : null}
        {doc.source === 'template' ? ' · ' : null}
        {doc.has_pdf ? t('preview.pdf') : t('preview.noPdf')}
      </div>

      {doc.can_edit && (draft || (rights.remove && doc.status !== 'signed')) ? (
        <div className="mt-3 flex flex-wrap gap-[6px]">
          {draft && doc.source === 'template' ? <button type="button" onClick={() => setEditing(true)} className={`${btnLink} border-line bg-transparent font-semibold`}>{t('preview.edit')}</button> : null}
          {rights.remove && doc.status !== 'signed' ? <button type="button" onClick={() => setDeleting(true)} className={`${btnLink} border-coral bg-transparent font-semibold text-rust`}>{t('preview.delete')}</button> : null}
          <span className="self-center text-11 text-muted">{t('preview.madeBy', { name: doc.owner_name ?? '—', date: date(doc.created_at) })}</span>
        </div>
      ) : null}

      {editing ? <EditDraft doc={doc} onClose={() => setEditing(false)} onSaved={async (missing) => { setEditing(false); flash(missing.length ? t('edit.savedMissing', { n: missing.length }) : t('edit.saved')); await onChanged(doc.id) }} /> : null}
      {deleting ? <DeleteDoc doc={doc} onClose={() => setDeleting(false)} onDeleted={async () => { setDeleting(false); flash(t('delete.done')); await onChanged(null) }} /> : null}
    </div>
  )
}

/** A draft's name, validity and body (Q11: the body is edited while the document is a draft; tokens left in it merge again). */
function EditDraft({ doc, onClose, onSaved }: { doc: DocDetail; onClose: () => void; onSaved: (missing: string[]) => Promise<void> }) {
  const t = useTranslations('documents.edit')
  const tc = useTranslations('common')
  const err = useError()
  const [name, setName] = useState(doc.name)
  const [valid, setValid] = useState(doc.valid_until ?? '')
  const [html, setHtml] = useState(doc.body_html ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function save() {
    setBusy(true); setError(null)
    const r = await updateDocumentAction({ id: doc.id, version: doc.version, values: { name, body_html: html, valid_until: valid || null } })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    await onSaved(r.missing)
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={doc.name} onClose={onClose} width={680}>
      <label className={field}>{t('name')}<input value={name} maxLength={200} onChange={(e) => setName(e.target.value)} className={fieldInput} /></label>
      <label className={field}>{t('validUntil')}<input type="date" value={valid} onChange={(e) => setValid(e.target.value)} className={fieldInput} /></label>
      <label className={field}>{t('body')}
        <textarea value={html} onChange={(e) => setHtml(e.target.value)} spellCheck={false}
          className={`min-h-[240px] rounded-10 border border-line bg-canvas px-3 py-[10px] text-12 font-normal leading-[1.5] text-ink ${mono}`} />
      </label>
      <span className="text-11.5 text-muted">{t('hint')}</span>
      {error ? <div className={note}>{error}</div> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{tc('cancel')}</button>
        <button type="button" disabled={busy || !name.trim()} onClick={save} className={btnConfirm}>{tc('save')}</button>
      </div>
    </Modal>
  )
}

function DeleteDoc({ doc, onClose, onDeleted }: { doc: DocDetail; onClose: () => void; onDeleted: () => Promise<void> }) {
  const t = useTranslations('documents.delete')
  const tc = useTranslations('common')
  const err = useError()
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function run() {
    setBusy(true); setError(null)
    const r = await deleteDocumentAction({ id: doc.id, reason: reason || undefined })
    setBusy(false)
    if (!r.ok) return setError(err(r))
    await onDeleted()
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={doc.name} onClose={onClose}>
      <span className="text-12.5 text-ink-2">{t('body')}</span>
      <label className={field}>{t('reason')}<input value={reason} maxLength={300} onChange={(e) => setReason(e.target.value)} className={fieldInput} /></label>
      {error ? <div className={note}>{error}</div> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{tc('cancel')}</button>
        <button type="button" disabled={busy} onClick={run} className={btnDanger}>{t('go')}</button>
      </div>
    </Modal>
  )
}

/**
 * The trackable link (DOC-04). A link's address exists only in the answer that made it (Q1): it is shown here
 * once, for this session, and «Copy link» makes a new one when it is no longer known. The public host does not
 * serve links yet (D-28), which the card says.
 */
function LinkCard({ loaded, rights, onChanged, onRequestSignature }: { loaded: Loaded; rights: Rights; onChanged: (id: string | null) => Promise<void>; onRequestSignature: (id: string) => void }) {
  const t = useTranslations('documents.link')
  const flash = useToast()
  const err = useError()
  const when = useWhen()
  const date = useDate()
  const f = useFormatter()
  const { doc, views } = loaded
  const [fresh, setFresh] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const known = fresh[doc.id] ?? null
  const active = [...doc.links].reverse().find((l) => l.active) ?? null
  const latest = doc.links[doc.links.length - 1] ?? null
  const seen = views.filter((v) => v.client_class !== 'prefetch')
  const minutes = (s: number) => (s < 60 ? t('seconds', { n: s }) : t('minutes', { n: Math.round(s / 60) }))

  async function copy() {
    let url = known
    if (!url) {
      setBusy(true)
      const r = await createLinkAction({ id: doc.id, recipient: doc.person?.id ?? null })
      setBusy(false)
      if (!r.ok) return flash(err(r))
      url = publicUrl(PUBLIC_HOST, r.path)
      setFresh((m) => ({ ...m, [doc.id]: url as string }))
      void onChanged(doc.id)
    }
    flash((await copyText(`https://${url}`)) ? t('copied') : t('shown'))
  }
  async function revoke() {
    if (!active) return
    setBusy(true)
    const r = await revokeLinkAction({ link: active.id })
    setBusy(false)
    if (!r.ok) return flash(err(r))
    setFresh((m) => { const n = { ...m }; delete n[doc.id]; return n })
    flash(t('revoked'))
    await onChanged(doc.id)
  }

  return (
    <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-4 py-[14px]">
      <b className="text-13.5">{t('title')}</b>
      {known ? (
        <>
          <span className={`break-all text-12 text-link ${mono}`}>{known}</span>
          <span className="text-11.5 text-muted">{t('once', { host: PUBLIC_HOST })}</span>
        </>
      ) : active ? (
        <>
          <span className={`text-12 text-link ${mono}`}>{PUBLIC_HOST}/d/…</span>
          <span className="text-11.5 text-muted">{t('made', { date: date(active.created_at), who: active.recipient_name ?? active.label ?? t('anyone') })}</span>
        </>
      ) : latest ? (
        <span className="text-11.5 text-muted">{t('revokedOn', { date: date(latest.revoked_at ?? latest.expires_at ?? latest.created_at) })}</span>
      ) : (
        <span className="text-11.5 text-muted">{t('none')}</span>
      )}
      {seen.length ? seen.map((v) => (
        <div key={v.id} className="flex justify-between gap-3 border-b border-tile py-1 text-12">
          <span>{v.recipient_name ?? v.label ?? t('anyone')}</span>
          <span className="text-right text-muted">{when(v.started_at)}{v.duration_seconds > 0 ? ` · ${minutes(v.duration_seconds)}` : ''}</span>
        </div>
      )) : (
        <div className="flex justify-between border-b border-tile py-1 text-12"><span>{t('notOpened')}</span><span className="text-muted">—</span></div>
      )}
      <div className="flex flex-wrap gap-[6px]">
        <button type="button" onClick={copy} disabled={busy || (!known && (!doc.can_edit || !rights.add))} className={`${btnLink} border-line bg-transparent font-semibold`}>{t('copy')}</button>
        <button type="button" onClick={revoke} disabled={busy || !active || !doc.can_edit} className={`${btnLink} border-coral bg-transparent font-semibold text-rust`}>{t('revoke')}</button>
        <button type="button" onClick={() => onRequestSignature(doc.id)} className={`${btnLink} border-ink bg-primary font-bold`}>{t('sign')}</button>
      </div>
      {doc.links.length > 1 ? <span className="text-11 text-muted">{t('count', { active: doc.links.filter((l) => l.active).length, all: doc.links.length, opens: f.number(doc.opens) })}</span> : null}
    </div>
  )
}
