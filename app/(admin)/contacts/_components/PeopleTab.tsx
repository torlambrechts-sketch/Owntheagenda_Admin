'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { CONTACT_TYPES, MARKETING } from '@/lib/data/contacts-shared'
import type { TabProps } from './ContactsScreen'
import { MARKETING_TONE, initialsOf, useNav } from './util'

const COLS = '[grid-template-columns:minmax(170px,1.4fr)_minmax(140px,1.2fr)_110px_minmax(160px,1.3fr)_130px_140px_110px_80px]'

/** People (Contacts.dc.html, v.people): search, three filters and the list; a row opens the drawer. */
export function PeopleTab({ data }: TabProps) {
  const t = useTranslations('contacts')
  const { go } = useNav()
  const [q, setQ] = useState(data.query.q)
  const first = useRef(true)
  useEffect(() => {
    if (first.current) { first.current = false; return }
    const h = setTimeout(() => go({ q: q.trim() || null }), 300)
    return () => clearTimeout(h)
  }, [q]) // eslint-disable-line react-hooks/exhaustive-deps

  const staffIni = Object.fromEntries(data.staff.map((s) => [s.id, s.initials ?? initialsOf(s.name)]))
  const labelById = Object.fromEntries(data.labels.person.map((l) => [l.id, l]))
  const filters: { key: 'type' | 'consent' | 'label'; name: string; value: string; opts: [string, string][] }[] = [
    { key: 'type', name: t('people.filter.type'), value: data.query.type, opts: CONTACT_TYPES.map((k) => [k, t(`contactType.${k}`)]) },
    { key: 'consent', name: t('people.filter.consent'), value: data.query.consent, opts: MARKETING.map((k) => [k, t(`marketing.${k}`)]) },
    { key: 'label', name: t('people.filter.label'), value: data.query.label, opts: data.labels.person.map((l) => [l.id, l.name]) },
  ]
  const people = data.people ?? []

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap gap-2">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('people.search')}
          aria-label={t('people.search')}
          className="h-9 min-w-0 flex-[1_1_240px] rounded-10 border border-line bg-surface px-3 text-13"
        />
        {filters.map((f) => (
          <label key={f.key} className={`flex h-9 items-center gap-[5px] rounded-10 border bg-surface pl-[10px] pr-1 text-12 text-muted ${f.value ? 'border-ink' : 'border-line'}`}>
            {f.name}
            <select value={f.value} onChange={(e) => go({ [f.key]: e.target.value || null })} className="border-none bg-transparent text-12.5 font-semibold text-ink">
              <option value="">{t('any')}</option>
              {f.opts.map(([v, n]) => <option key={v} value={v}>{n}</option>)}
            </select>
          </label>
        ))}
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="overflow-x-auto">
          <div className="min-w-[1000px]">
            <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
              <span>{t('people.col.person')}</span><span>{t('people.col.organization')}</span><span>{t('people.col.role')}</span><span>{t('people.col.email')}</span>
              <span>{t('people.col.type')}</span><span>{t('people.col.marketing')}</span><span>{t('people.col.source')}</span><span>{t('people.col.owner')}</span>
            </div>
            {people.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => go({ person: p.id }, true)}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-0 border-b border-solid border-line bg-transparent px-4 py-[9px] text-left text-12.5 ${COLS}`}
              >
                <span className="flex min-w-0 items-center gap-2">
                  <span className="flex h-7 w-7 flex-none items-center justify-center rounded-9 bg-tile text-10.5 font-bold">{initialsOf(p.name)}</span>
                  <span className="flex min-w-0 flex-col">
                    <b className="overflow-hidden text-ellipsis whitespace-nowrap">{p.name}</b>
                    <span className="flex gap-[3px]">
                      {p.labels.map((id) => labelById[id]).filter(Boolean).map((l) => (
                        <span key={l!.id} className="rounded-999 px-[6px] text-10 font-bold" style={{ background: l!.bg, color: l!.ink }}>{l!.name}</span>
                      ))}
                    </span>
                  </span>
                </span>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap">{p.organization_id__title ?? '—'}</span>
                <span>{p.title ?? '—'}</span>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap text-ink-2">{p.email ?? '—'}</span>
                <span>{p.contact_type ? t(`contactType.${p.contact_type}` as 'contactType.prospect') : '—'}</span>
                <span><span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${MARKETING_TONE[p.marketing_status] ?? ''}`}>{t(`marketing.${p.marketing_status}` as 'marketing.subscribed')}</span></span>
                <span className="text-muted">{p.source ?? '—'}</span>
                <span className="text-muted">{p.owner_id ? staffIni[p.owner_id] ?? '—' : '—'}</span>
              </button>
            ))}
            {people.length === 0 ? <div className="px-4 py-[30px] text-center text-13 text-muted">{t('people.empty')}</div> : null}
          </div>
        </div>
      </div>
    </div>
  )
}
