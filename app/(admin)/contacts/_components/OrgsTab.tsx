'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { setRelation } from '../actions'
import type { TabProps } from './ContactsScreen'
import { firstName, orgNr, useError, useNav } from './util'

const COLS = '[grid-template-columns:minmax(160px,1.5fr)_minmax(140px,1.3fr)_90px_60px_60px_110px]'

/** Organizations (Contacts.dc.html, v.orgs): the list and the selected organization's relations and people. */
export function OrgsTab({ data, rights, me, openForm }: TabProps) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const { go, refresh } = useNav()
  const [kind, setKind] = useState<'' | 'parent' | 'daughter' | 'related'>('')
  const [other, setOther] = useState('')
  const orgs = data.orgs ?? []
  const byId = Object.fromEntries(orgs.map((o) => [o.id, o]))
  const parents = new Set(orgs.map((o) => o.parent_id).filter(Boolean))
  const sel = data.org
  const canEdit = sel ? sel.row.owner_id === me.id || rights.editOthers : false

  const relation = (o: (typeof orgs)[number]) =>
    o.parent_id && byId[o.parent_id] ? t('orgs.daughterOf', { name: firstName(byId[o.parent_id]!.name) }) : parents.has(o.id) ? t('orgs.parent') : '—'

  async function add() {
    if (!sel || !kind || !other) return
    // «Add as parent …»: the chosen organization becomes this one's parent (and the reverse for daughter)
    const r = await setRelation(kind === 'parent' ? { a: sel.row.id, b: other, kind: 'parent' } : kind === 'daughter' ? { a: sel.row.id, b: other, kind: 'daughter' } : { a: sel.row.id, b: other, kind: 'related' })
    if (!r.ok) return flash(err(r.code))
    flash(t('orgs.relationAdded'))
    setKind(''); setOther('')
    refresh()
  }
  async function removeRelated(b: string) {
    if (!sel) return
    const r = await setRelation({ a: sel.row.id, b, kind: 'none' })
    if (!r.ok) return flash(err(r.code))
    refresh()
  }

  const related = sel
    ? [
        ...(sel.relations.parent ? [{ id: sel.relations.parent.id, n: sel.relations.parent.name, k: t('orgs.parent'), rel: false }] : []),
        ...sel.relations.daughters.map((d) => ({ id: d.id, n: d.name, k: t('orgs.daughter'), rel: false })),
        ...sel.relations.related.map((r) => ({ id: r.id, n: r.name, k: r.note ? t('orgs.relatedNote', { note: r.note }) : t('orgs.related'), rel: true })),
      ]
    : []

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(0,1fr)_340px]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="overflow-x-auto">
          <div className="min-w-[680px]">
            <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
              <span>{t('orgs.col.organization')}</span><span>{t('orgs.col.address')}</span><span>{t('orgs.col.owner')}</span>
              <span>{t('orgs.col.people')}</span><span>{t('orgs.col.deals')}</span><span>{t('orgs.col.relation')}</span>
            </div>
            {orgs.map((o) => (
              <button
                key={o.id}
                type="button"
                onClick={() => go({ org: o.id })}
                aria-pressed={sel?.row.id === o.id}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-b border-line px-4 py-[9px] text-left text-12.5 ${COLS} ${sel?.row.id === o.id ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <b>{o.name}</b>
                <span className="text-muted">{[o.city, o.fylke].filter(Boolean).join(', ') || '—'}</span>
                <span>{firstName(o.owner_id__title) || '—'}</span>
                <span>{data.orgCounts?.people[o.id] ?? 0}</span>
                <span>{data.orgCounts?.deals ? (data.orgCounts.deals[o.id] ?? 0) : '—'}</span>
                <span className="text-muted">{relation(o)}</span>
              </button>
            ))}
            {orgs.length === 0 ? <div className="px-4 py-[30px] text-center text-13 text-muted">{t('orgs.empty')}</div> : null}
          </div>
        </div>
      </div>
      {sel ? (
        <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-[18px] md:sticky md:top-20">
          <div className="flex items-start justify-between gap-2">
            <b className="font-serif text-20">{sel.row.name}</b>
            {canEdit ? <button type="button" onClick={() => openForm({ entity: 'organization', id: sel.row.id })} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('edit')}</button> : null}
          </div>
          <span className="text-12 text-muted">{[orgNr(sel.row.org_number), sel.row.industry, sel.row.city].filter(Boolean).join(' · ') || '—'}</span>
          <div className="mt-1 text-11 font-bold uppercase tracking-eyebrow text-muted">{t('orgs.relatedHead')}</div>
          {related.length ? related.map((r) => (
            <div key={`${r.k}-${r.id}`} className="flex justify-between gap-2 border-b border-line py-[6px] text-12.5">
              <b>{r.n}</b>
              <span className="flex items-center gap-2 text-muted">
                {r.k}
                {r.rel && canEdit ? <button type="button" onClick={() => removeRelated(r.id)} aria-label={t('orgs.removeRelation', { name: r.n })} className="cursor-pointer border-none bg-transparent p-0 text-12 text-muted">×</button> : null}
              </span>
            </div>
          )) : <div className="flex justify-between border-b border-line py-[6px] text-12.5"><b>{t('orgs.noRelated')}</b><span /></div>}
          {canEdit ? (
            <div className="flex flex-col gap-[6px]">
              <div className="flex gap-[6px]">
                <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} aria-label={t('orgs.addRelation')} className="h-8 flex-1 rounded-9 border border-line bg-canvas text-12">
                  <option value="">{t('orgs.addRelation')}</option>
                  <option value="parent">{t('orgs.addParent')}</option>
                  <option value="daughter">{t('orgs.addDaughter')}</option>
                  <option value="related">{t('orgs.addRelated')}</option>
                </select>
              </div>
              {kind ? (
                <div className="flex gap-[6px]">
                  <select value={other} onChange={(e) => setOther(e.target.value)} aria-label={t('orgs.chooseOrg')} className="h-8 min-w-0 flex-1 rounded-9 border border-line bg-canvas text-12">
                    <option value="">{t('orgs.chooseOrg')}</option>
                    {orgs.filter((o) => o.id !== sel.row.id).map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
                  </select>
                  <button type="button" disabled={!other} onClick={add} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('orgs.add')}</button>
                </div>
              ) : null}
            </div>
          ) : null}
          <div className="mt-1 text-11 font-bold uppercase tracking-eyebrow text-muted">{t('orgs.peopleHead')}</div>
          {sel.people.length ? sel.people.map((p) => (
            <button key={p.id} type="button" onClick={() => go({ person: p.id }, true)} className="flex cursor-pointer justify-between border-none bg-transparent p-0 text-left text-12.5">
              <b>{p.name}</b><span className="text-muted">{p.title ?? ''}</span>
            </button>
          )) : <div className="text-12.5 text-muted">{t('orgs.noPeople')}</div>}
          <Link href={`/customers?org=${sel.row.id}` as never} className="flex h-[34px] items-center justify-center rounded-10 border border-ink bg-surface text-12.5 font-bold text-ink hover:text-ink hover:no-underline">
            {t('orgs.openCustomer')}
          </Link>
        </div>
      ) : null}
    </div>
  )
}
