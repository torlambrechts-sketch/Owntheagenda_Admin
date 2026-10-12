'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { Spec, Specs } from '@/lib/data/dev-core'
import { saveSpec, setSpecStatus, signSpec } from '../../core-actions'
import { SPEC_ROLES, SPEC_SECTIONS, SPEC_STATUSES, type SpecSection } from './logic'
import { c, Modal, useRun, type ProductInfo } from './kit'

const STATUS_TONE: Record<Spec['status'], string> = { approved: 'text-link', in_review: 'text-warn-ink', draft: 'text-muted' }

/** the spec list and the open spec (DevHub.dc.html, v.specs) */
export function SpecsView({ data, products, selected }: { data: Specs; products: ProductInfo[]; selected: string | null }) {
  const t = useTranslations('devCore.specs')
  const [sel, setSel] = useState(selected)
  const [adding, setAdding] = useState(false)
  const spec = data.specs.find((s) => s.id === sel) ?? data.specs[0] ?? null
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        {data.specs.map((s) => (
          <button key={s.id} type="button" onClick={() => setSel(s.id)} aria-pressed={spec?.id === s.id}
            className={`flex w-full cursor-pointer flex-col gap-[3px] border-0 border-b border-line px-4 py-[11px] text-left text-ink ${spec?.id === s.id ? 'bg-highlight' : 'bg-transparent'}`}>
            <span className="flex justify-between gap-2">
              <b className="text-13">{s.title}</b>
              <span className={`whitespace-nowrap text-11 font-bold ${STATUS_TONE[s.status]}`}>{t(`status.${s.status}`)}</span>
            </span>
            <span className="text-11.5 text-muted">{[s.ref, s.author?.name].filter(Boolean).join(' · ')}</span>
          </button>
        ))}
        {!data.specs.length ? <div className="px-4 py-6 text-center text-13 text-muted">{t('empty')}</div> : null}
        {data.can_add ? <div className="px-[14px] py-[10px]"><button type="button" onClick={() => setAdding(true)} className={c.dashed}>{t('newSpec')}</button></div> : null}
      </div>
      {spec ? <Detail key={spec.id} s={spec} canEdit={data.can_add} /> : null}
      {adding ? <NewSpec data={data} products={products} onClose={() => setAdding(false)} onAdded={(id) => setSel(id)} /> : null}
    </div>
  )
}

/** a spec: title and RFC id, status, the five sections (edited in place), the four sign-offs */
function Detail({ s, canEdit }: { s: Spec; canEdit: boolean }) {
  const t = useTranslations('devCore.specs')
  const format = useFormatter()
  const { run, pending } = useRun()
  const [editing, setEditing] = useState(false)
  const [title, setTitle] = useState(s.title)
  const [text, setText] = useState<Record<SpecSection, string>>(() => Object.fromEntries(SPEC_SECTIONS.map((x) => [x, s.sections[x] ?? ''])) as Record<SpecSection, string>)
  const changed: Record<string, string> = {}
  if (title.trim() !== s.title) changed.title = title.trim()
  for (const x of SPEC_SECTIONS) if (text[x].trim() !== (s.sections[x] ?? '')) changed[x] = text[x]
  const signed = (role: (typeof SPEC_ROLES)[number]) => s.signoffs.find((g) => g.role === role) ?? null
  const date = (iso: string) => format.dateTime(new Date(iso), { day: 'numeric', month: 'short', year: 'numeric' })
  return (
    <div className="flex min-w-0 flex-col gap-[10px] rounded-20 border border-ink bg-surface px-5 py-4 lg:col-span-2">
      <div className="flex justify-between gap-[10px]">
        {editing ? <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} aria-label={t('fields.title')} className={`${c.input} flex-1 font-serif text-18`} />
          : <b className="font-serif text-20">{s.title}</b>}
        <span className="whitespace-nowrap text-12 text-muted">{s.ref}</span>
      </div>
      <div className="flex flex-wrap items-center gap-2 text-12 text-muted">
        {s.roadmap ? <span>{t('forItem', { key: s.roadmap.key, title: s.roadmap.title })}</span> : null}
        <span>{t('revision', { n: s.revision })}</span>
        <span className="flex-1" />
        {canEdit ? (
          <>
            <select value={s.status} disabled={pending} aria-label={t('fields.status')}
              onChange={(e) => run(() => setSpecStatus({ id: s.id, status: e.target.value, version: s.version }), () => t('statusSet'))}
              className="h-[30px] rounded-8 border border-line bg-canvas px-1 text-12 text-ink">
              {SPEC_STATUSES.map((x) => <option key={x} value={x}>{t(`status.${x}`)}</option>)}
            </select>
            {editing ? (
              <>
                <button type="button" onClick={() => setEditing(false)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold text-ink">{t('cancel')}</button>
                <button type="button" disabled={pending || !Object.keys(changed).length || title.trim().length < 3}
                  onClick={() => run(() => saveSpec({ id: s.id, version: s.version, values: changed }), () => t('saved'), () => setEditing(false))}
                  className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold text-ink disabled:cursor-default disabled:opacity-50">{t('save')}</button>
              </>
            ) : <button type="button" onClick={() => setEditing(true)} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-3 text-12 font-bold text-ink">{t('edit')}</button>}
          </>
        ) : null}
      </div>
      {editing ? <span className="text-11.5 text-warn-ink">{t('lapseNote')}</span> : null}
      {SPEC_SECTIONS.map((x) => (
        <div key={x} className="flex flex-col gap-1">
          <span className={`text-11 font-bold uppercase tracking-[.1em] ${x === 'privacy' ? 'text-danger' : 'text-muted'}`}>{t(`sections.${x}`)}</span>
          {editing ? (
            <textarea value={text[x]} onChange={(e) => setText({ ...text, [x]: e.target.value })} maxLength={8000} aria-label={t(`sections.${x}`)} className={`${c.textarea} min-h-[70px] text-12.5`} />
          ) : s.sections[x] ? <span className="whitespace-pre-wrap text-12.5 leading-[1.55] [overflow-wrap:anywhere]">{s.sections[x]}</span>
            : <span className="text-12.5 leading-[1.55] text-faint">{t('notWritten')}</span>}
        </div>
      ))}
      <span className="text-11 font-bold uppercase tracking-[.1em] text-muted">{t('signoff')}</span>
      <div className="flex flex-wrap gap-[6px]">
        {SPEC_ROLES.map((role) => {
          const g = signed(role)
          const on = !!g?.current
          const tip = g ? (g.current ? t('signedBy', { name: g.by ?? '—', date: date(g.at) }) : t('lapsed', { name: g.by ?? '—', n: g.revision })) : t('notSigned')
          return (
            <button key={role} type="button" disabled={!canEdit || pending} title={tip} aria-pressed={on}
              onClick={() => run(() => signSpec({ id: s.id, role, on: !on }), () => (on ? t('unsignedToast', { role: t(`roles.${role}`) }) : t('signedToast', { role: t(`roles.${role}`) })))}
              className={`cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink disabled:cursor-default ${on ? 'border-link bg-ok-bg font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {on ? '✓' : '○'} {t(`roles.${role}`)}
            </button>
          )
        })}
      </div>
      {!canEdit ? <span className="text-11.5 text-muted">{t('signNoRight')}</span> : null}
    </div>
  )
}

/** a new spec: for a roadmap item (its product) or on its own for a product */
function NewSpec({ data, products, onClose, onAdded }: { data: Specs; products: ProductInfo[]; onClose: () => void; onAdded: (id: string) => void }) {
  const t = useTranslations('devCore.specs')
  const { run, pending } = useRun()
  const [item, setItem] = useState('')
  const [product, setProduct] = useState(products[0]?.key ?? 'sentral')
  const [title, setTitle] = useState('')
  const picked = data.roadmap.find((r) => r.id === item) ?? null
  return (
    <Modal title={t('newTitle')} cta={t('add')} busy={pending || title.trim().length < 3} onClose={onClose}
      onSubmit={() => run(() => saveSpec({ id: null, version: null, values: picked ? { roadmap_item_id: picked.id, title } : { product, title } }),
                          () => t('added'), (r) => { if ('id' in r) onAdded(r.id); onClose() })}>
      <label className={c.field}>{t('fields.item')}
        <select value={item} onChange={(e) => { setItem(e.target.value); const r = data.roadmap.find((x) => x.id === e.target.value); if (r && !title) setTitle(r.title) }} className={c.select}>
          <option value="">{t('noItem')}</option>
          {data.roadmap.map((r) => <option key={r.id} value={r.id}>{r.key} {r.title}</option>)}
        </select>
      </label>
      {!picked ? (
        <label className={c.field}>{t('fields.product')}
          <select value={product} onChange={(e) => setProduct(e.target.value)} className={c.select}>
            {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
          </select>
        </label>
      ) : null}
      <label className={c.field}>{t('fields.title')}<input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={c.input} /></label>
    </Modal>
  )
}
