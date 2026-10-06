'use client'

import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money } from '@/lib/format'
import { MARKETING } from '@/lib/data/contacts-shared'
import type { Note, PersonDetail } from '@/lib/data/contacts'
import { pinNote, saveNote, setConsent, setLabels } from '../actions'
import type { TabProps } from './ContactsScreen'
import { firstName, initialsOf, useError, useNav } from './util'

const FIELD_KEYS = ['name', 'email', 'phone', 'organization_id', 'title', 'contact_type', 'source', 'city', 'fylke', 'linkedin', 'labels', 'owner_id', 'marketing_status'] as const

/** The person drawer (Contacts.dc.html, person): labels, facts, marketing status, notes and history. */
export function PersonDrawer({ data, rights, me, now, openForm, detail }: TabProps & { detail: PersonDetail }) {
  const t = useTranslations('contacts')
  const format = useFormatter()
  const flash = useToast()
  const err = useError()
  const { go, refresh } = useNav()
  const p = detail.person
  const canEdit = p.owner_id === me.id || rights.editOthers
  const [draft, setDraft] = useState('')
  const [consentOpen, setConsentOpen] = useState(false)
  const [reply, setReply] = useState<{ id: string; text: string } | null>(null)
  const panel = useRef<HTMLDivElement>(null)
  const nowD = new Date(now)
  const close = () => go({ person: null })

  useEffect(() => {
    panel.current?.focus()
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') close() }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const owner = data.staff.find((s) => s.id === p.owner_id)
  const facts = [
    { k: t('drawer.type'), v: p.contact_type ? t(`contactType.${p.contact_type}` as 'contactType.prospect') : '—' },
    { k: t('drawer.marketing'), v: t(`marketing.${p.marketing_status}` as 'marketing.subscribed'), consent: true },
    { k: t('drawer.source'), v: p.source ?? '—' },
    { k: t('drawer.owner'), v: owner ? firstName(owner.name) : '—' },
  ]

  async function toggleLabel(id: string) {
    const on = p.labels.includes(id)
    const r = await setLabels({ entity: 'person', id: p.id, version: p.version, labels: on ? p.labels.filter((x) => x !== id) : [...p.labels, id] })
    if (!r.ok) return flash(err(r.code))
    refresh()
  }
  async function addNote(body: string, parent: string | null) {
    if (!body.trim()) return
    const r = await saveNote({ entity: 'person', id: p.id, body, parent })
    if (!r.ok) return flash(err(r.code))
    flash(r.undelivered ? t('drawer.noteUndelivered') : r.mentioned ? t('drawer.noteMentioned') : t('drawer.noteSaved'))
    if (parent) setReply(null); else setDraft('')
    refresh()
  }
  async function pin(n: Note) {
    const r = await pinNote({ entity: 'person', id: p.id, note: n.id, pinned: !n.pinned })
    if (!r.ok) return flash(err(r.code))
    refresh()
  }

  const top = detail.notes.filter((n) => !n.parent_id)
  const replies = (id: string) => detail.notes.filter((n) => n.parent_id === id).sort((a, b) => a.created_at.localeCompare(b.created_at))
  const fieldName = (f: string) => ((FIELD_KEYS as readonly string[]).includes(f) ? t(`drawer.field.${f as (typeof FIELD_KEYS)[number]}`) : f.replace(/^custom\./, ''))
  const change = (f: string) =>
    f === '*created' ? t('drawer.change.created') : f === '*deleted' ? t('drawer.change.deleted') : f === '*restored' ? t('drawer.change.restored')
      : f === '*merged' ? t('drawer.change.merged') : t('drawer.change.field', { field: fieldName(f) })
  const date = (iso: string) => format.dateTime(new Date(iso), { day: 'numeric', month: 'short' })
  const history = [
    ...detail.deals.map((d) => ({ key: `d${d.id}`, g: '◆', bg: '#F3E2C9', tt: d.title, s: `${money(d.value, me.nf, d.currency)} · ${t(`drawer.dealStatus.${d.status}` as 'drawer.dealStatus.open')}`, when: d.expected_close_date ? date(d.expected_close_date) : '', href: `/deals?deal=${d.id}` })),
    ...detail.activities.map((a) => ({ key: `a${a.id}`, g: a.type?.glyph ?? '•', bg: '#DCEBD3', tt: a.subject, s: `${a.done ? t('drawer.done') : t('drawer.planned')} · ${t('drawer.minutes', { n: a.duration_min })}`, when: a.starts_at ? format.relativeTime(new Date(a.starts_at), nowD) : '', href: `/activities?activity=${a.id}` })),
    ...detail.changes.map((c, i) => ({ key: `c${i}`, g: '✎', bg: '#F2EAD6', tt: change(c.field), s: [c.actor, c.source ? t(`restore.source.${c.source}` as 'restore.source.ui') : null].filter(Boolean).join(' · '), when: date(c.at), href: null })),
  ]

  return (
    <div onClick={close} className="fixed inset-0 z-[80] flex justify-end bg-[rgba(25,21,16,.42)]">
      <div ref={panel} tabIndex={-1} role="dialog" aria-modal="true" aria-labelledby="person-name" onClick={(e) => e.stopPropagation()}
        className="flex h-full w-[min(760px,100%)] flex-col gap-3 overflow-auto bg-canvas px-[22px] py-5 outline-none">
        <div className="flex items-start gap-3">
          <span className="flex h-[52px] w-[52px] flex-none items-center justify-center rounded-15 bg-ink font-serif text-19 font-bold text-canvas">{initialsOf(p.name)}</span>
          <div className="min-w-0 flex-1">
            <div id="person-name" className="font-serif text-24 font-semibold">{p.name}</div>
            <div className="text-12.5 text-ink-2">{[p.title, p.organization_id__title, p.email, p.phone].filter(Boolean).join(' · ') || '—'}</div>
            <div className="mt-[3px] text-11.5 text-muted">{t('drawer.sync')}</div>
          </div>
          {canEdit ? <button type="button" onClick={() => openForm({ entity: 'person', id: p.id })} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('edit')}</button> : null}
          <button type="button" onClick={close} aria-label={t('close')} className="h-8 w-8 flex-none cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
        </div>

        <div className="flex flex-wrap gap-[5px]">
          {data.labels.person.map((l) => {
            const on = p.labels.includes(l.id)
            return (
              <button key={l.id} type="button" disabled={!canEdit} onClick={() => toggleLabel(l.id)} aria-pressed={on}
                className={`cursor-pointer rounded-999 border px-[10px] py-1 text-11.5 font-bold disabled:cursor-default ${on ? 'border-transparent' : 'border-line-strong bg-transparent text-muted'}`}
                style={on ? { background: l.bg, color: l.ink } : undefined}>
                {l.name}
              </button>
            )
          })}
        </div>

        <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
          {facts.map((f) => {
            const body = (<><div className="text-10.5 font-bold uppercase tracking-label text-muted">{f.k}</div><b className="text-13">{f.v}</b></>)
            return f.consent ? (
              <button key={f.k} type="button" onClick={() => setConsentOpen(!consentOpen)} aria-expanded={consentOpen} className="cursor-pointer rounded-14 border border-line bg-surface px-3 py-[10px] text-left">{body}</button>
            ) : (
              <div key={f.k} className="rounded-14 border border-line bg-surface px-3 py-[10px]">{body}</div>
            )
          })}
        </div>

        {consentOpen ? <ConsentCard detail={detail} canEdit={canEdit} onDone={() => { setConsentOpen(false); refresh() }} /> : null}

        <div className="flex flex-col gap-2 rounded-18 border border-line bg-surface px-4 py-[14px]">
          <b className="text-13.5">{t('drawer.notes')}</b>
          <textarea value={draft} onChange={(e) => setDraft(e.target.value)} placeholder={t('drawer.notePlaceholder')} aria-label={t('drawer.notes')}
            className="min-h-[60px] rounded-11 border border-line bg-canvas px-[11px] py-[9px] text-13" />
          <button type="button" onClick={() => addNote(draft, null)} disabled={!draft.trim()} className="h-[30px] cursor-pointer self-end rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('drawer.addNote')}</button>
          {top.map((n) => (
            <div key={n.id} className={`rounded-14 border border-line px-3 py-[10px] ${n.pinned ? 'bg-highlight' : 'bg-surface'}`}>
              <div className="flex justify-between gap-2 text-11.5 text-muted">
                <span><b className="text-ink">{n.author ?? '—'}</b> · {date(n.created_at)}</span>
                <button type="button" onClick={() => pin(n)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 text-muted">{n.pinned ? t('drawer.pinned') : t('drawer.pin')}</button>
              </div>
              <div className="mt-1 whitespace-pre-wrap text-12.5 leading-[1.5]">{n.body}</div>
              {replies(n.id).map((c) => (
                <div key={c.id} className="ml-[14px] mt-[6px] border-l-2 border-line pl-[10px] text-12"><b>{firstName(c.author)}:</b> {c.body}</div>
              ))}
              {reply?.id === n.id ? (
                <div className="ml-[14px] mt-[6px] flex gap-[6px]">
                  <input autoFocus value={reply.text} onChange={(e) => setReply({ id: n.id, text: e.target.value })} onKeyDown={(e) => { if (e.key === 'Enter') void addNote(reply.text, n.id) }}
                    aria-label={t('drawer.reply')} className="h-[30px] min-w-0 flex-1 rounded-9 border border-line bg-canvas px-2 text-12" />
                  <button type="button" onClick={() => addNote(reply.text, n.id)} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('drawer.send')}</button>
                </div>
              ) : (
                <button type="button" onClick={() => setReply({ id: n.id, text: '' })} className="ml-[14px] mt-[6px] cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('drawer.reply')}</button>
              )}
            </div>
          ))}
        </div>

        <div className="flex flex-col gap-1 rounded-18 border border-line bg-surface px-4 py-[14px]">
          <b className="mb-[6px] text-13.5">{t('drawer.history')}</b>
          {history.map((h) => {
            const inner = (
              <>
                <span className="flex h-[22px] w-[22px] items-center justify-center rounded-7 text-10.5" style={{ background: h.bg }}>{h.g}</span>
                <span><b>{h.tt}</b> {h.s ? <span className="text-muted">· {h.s}</span> : null}</span>
                <span className="text-11 text-faint">{h.when}</span>
              </>
            )
            const cls = 'grid gap-[10px] border-b border-line py-[7px] text-12.5 [grid-template-columns:24px_minmax(0,1fr)_auto]'
            return h.href ? <Link key={h.key} href={h.href as never} className={`${cls} text-ink hover:text-ink hover:no-underline`}>{inner}</Link> : <div key={h.key} className={cls}>{inner}</div>
          })}
          {history.length === 0 ? <div className="py-[7px] text-12.5 text-muted">{t('drawer.noHistory')}</div> : null}
        </div>
        <div className="text-11.5 text-faint">{t('drawer.footer', { type: p.contact_type ? t(`contactType.${p.contact_type}` as 'contactType.prospect').toLowerCase() : t('drawer.contact') })}</div>
      </div>
    </div>
  )
}

/** Marketing status: changed only through consent_set, with a source and a basis; the ledger below. */
function ConsentCard({ detail, canEdit, onDone }: { detail: PersonDetail; canEdit: boolean; onDone: () => void }) {
  const t = useTranslations('contacts')
  const format = useFormatter()
  const flash = useToast()
  const err = useError()
  const [status, setStatus] = useState(detail.person.marketing_status)
  const [source, setSource] = useState('')
  const [basis, setBasis] = useState('')
  const [busy, setBusy] = useState(false)
  async function save() {
    setBusy(true)
    const r = await setConsent({ person: detail.person.id, status, source, basis })
    setBusy(false)
    if (!r.ok) return flash(r.code === 'invalid' ? t('consent.basisRequired') : err(r.code))
    flash(t('consent.saved'))
    onDone()
  }
  const input = 'h-8 rounded-9 border border-line bg-canvas px-2 text-12.5'
  return (
    <div className="flex flex-col gap-2 rounded-18 border border-line bg-surface px-4 py-[14px]">
      <b className="text-13.5">{t('consent.title')}</b>
      {canEdit ? (
        <div className="grid gap-2 md:[grid-template-columns:180px_minmax(0,1fr)_minmax(0,1fr)_auto]">
          <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('consent.status')} className={input}>
            {MARKETING.map((m) => <option key={m} value={m}>{t(`marketing.${m}`)}</option>)}
          </select>
          <input value={source} onChange={(e) => setSource(e.target.value)} maxLength={60} placeholder={t('consent.source')} aria-label={t('consent.source')} className={input} />
          <input value={basis} onChange={(e) => setBasis(e.target.value)} maxLength={200} placeholder={t('consent.basis')} aria-label={t('consent.basis')} className={input} />
          <button type="button" disabled={busy || !source.trim() || status === detail.person.marketing_status} onClick={save} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('consent.save')}</button>
        </div>
      ) : null}
      {detail.consent.map((c, i) => (
        <div key={i} className="flex flex-wrap justify-between gap-2 border-b border-line py-[6px] text-12">
          <span><b>{t(`marketing.${c.status}` as 'marketing.subscribed')}</b> <span className="text-muted">· {[c.source, c.basis, c.actor].filter(Boolean).join(' · ')}</span></span>
          <span className="text-11 text-faint">{format.dateTime(new Date(c.at), { day: 'numeric', month: 'short', year: 'numeric' })}</span>
        </div>
      ))}
      {detail.consent.length === 0 ? <div className="text-12 text-muted">{t('consent.none')}</div> : null}
    </div>
  )
}
