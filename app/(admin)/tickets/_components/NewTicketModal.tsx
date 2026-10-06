'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { createTicket, newTicketData } from '../actions'
import { useGo, useLabel } from './lib'
import type { OrgOption, PersonOption, TicketConfig } from '@/lib/data/tickets'

export type NewTicketSeed = { organizationId?: string; subject?: string }

/** Help articles whose title shares a word with the text (the design's match(): words over three letters, first five letters). */
export function matchArticles(text: string, titles: string[]) {
  const words = text.toLowerCase().split(/\s+/).filter((x) => x.length > 3)
  return titles.filter((a) => words.some((w) => a.toLowerCase().includes(w.slice(0, 5)))).slice(0, 3)
}

const label = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'
const field = 'h-[38px] rounded-10 border border-line bg-canvas text-13 font-normal text-ink'

/** The new-ticket dialog (Tickets.dc.html, newOpen): company, category, contact, subject with help suggestions, description. */
export function NewTicketModal({ seed, config, product, onClose }: { seed: NewTicketSeed; config: TicketConfig; product: string; onClose: () => void }) {
  const t = useTranslations('tickets.modal')
  const tc = useTranslations('common')
  const cat = useLabel('categories')
  const queue = useLabel('queues')
  const flash = useToast()
  const { go } = useGo()
  const [data, setData] = useState<{ orgs: OrgOption[]; people: PersonOption[]; articles: string[] } | null>(null)
  const [org, setOrg] = useState(seed.organizationId ?? '')
  const [person, setPerson] = useState('')
  const [category, setCategory] = useState(config.categories[0]?.key ?? '')
  const [subject, setSubject] = useState(seed.subject ?? '')
  const [description, setDescription] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const first = useRef<HTMLSelectElement>(null)
  const closeRef = useRef(onClose)
  closeRef.current = onClose

  useEffect(() => {
    let live = true
    void newTicketData().then((r) => { if (live) { if (r.ok) setData(r); else setError(tc(`errors.${r.code}`)) } })
    first.current?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') closeRef.current() }
    window.addEventListener('keydown', onKey)
    return () => { live = false; window.removeEventListener('keydown', onKey) }
  }, [tc])

  const people = useMemo(() => (data?.people ?? []).filter((p) => !org || p.organization_id === org), [data, org])
  const suggest = subject.length > 3 ? matchArticles(subject, data?.articles ?? []) : []

  async function create() {
    if (busy || !subject.trim() || !category) return
    setBusy(true)
    setError(null)
    const r = await createTicket({
      category_key: category, subject, description, organization_id: org || null, person_id: person || null, product: product === 'all' ? null : product,
    })
    setBusy(false)
    if (!r.ok) { setError(tc(`errors.${r.code}`)); return }
    flash(t('created', { ref: r.ref, queue: queue(r.queue_key, config.queues.find((q) => q.key === r.queue_key)?.name) }))
    onClose()
    if (config.queues.find((q) => q.key === r.queue_key)?.allowed !== false) go({ ticket: r.id, tab: null, view: null, q: null, new: null }, { reset: true, push: true })
  }

  return (
    <div onClick={onClose} className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-ticket-title"
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-full w-[600px] max-w-full flex-col gap-3 overflow-auto rounded-22 bg-surface px-[26px] py-6 shadow-modal"
      >
        <div className="flex justify-between">
          <span id="new-ticket-title" className="font-serif text-22 font-semibold">{t('title')}</span>
          <button type="button" aria-label={t('close')} onClick={onClose} className="h-[30px] w-[30px] cursor-pointer rounded-999 border border-ink bg-transparent p-0">×</button>
        </div>
        <div className="grid grid-cols-2 gap-[10px]">
          <label className={label}>
            {t('org')}
            <select ref={first} value={org} onChange={(e) => { setOrg(e.target.value); setPerson('') }} className={`${field} min-w-0`}>
              <option value="">{data ? t('orgNone') : tc('loading')}</option>
              {data?.orgs.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
              {!data && seed.organizationId ? <option value={seed.organizationId}>{tc('loading')}</option> : null}
            </select>
          </label>
          <label className={label}>
            {t('category')}
            <select value={category} onChange={(e) => setCategory(e.target.value)} className={`${field} min-w-0`}>
              {config.categories.map((c) => <option key={c.key} value={c.key}>{cat(c.key, c.name)}</option>)}
            </select>
          </label>
          <label className={`${label} col-span-2`}>
            {t('person')}
            <select value={person} onChange={(e) => setPerson(e.target.value)} className={`${field} min-w-0`}>
              <option value="">{t('personNone')}</option>
              {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
        </div>
        <label className={label}>
          {t('subject')}
          <input
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
            placeholder={t('subjectPh')}
            maxLength={200}
            className="h-10 rounded-10 border border-line bg-canvas px-3 text-13 font-normal text-ink"
          />
        </label>
        {suggest.length ? (
          <div className="flex flex-col gap-[5px] rounded-14 bg-highlight px-3 py-[10px] text-12.5">
            <b>{t('suggest')}</b>
            {suggest.map((s) => <span key={s}>{s} →</span>)}
          </div>
        ) : null}
        <textarea
          aria-label={t('description')}
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder={t('description')}
          className="min-h-[90px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13"
        />
        <div className="text-12 text-muted">{t('note')}</div>
        {error ? <div role="alert" className="text-12 font-semibold text-danger">{error}</div> : null}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold">{t('cancel')}</button>
          <button
            type="button"
            onClick={() => void create()}
            disabled={busy || !subject.trim()}
            className="h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold disabled:cursor-default disabled:opacity-60"
          >
            {t('create')}
          </button>
        </div>
      </div>
    </div>
  )
}
