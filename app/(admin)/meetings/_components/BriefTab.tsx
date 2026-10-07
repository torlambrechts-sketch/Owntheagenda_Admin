'use client'

import type { Route } from 'next'
import Link from 'next/link'
import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import type { Brief, Detail } from '@/lib/data/meetings'
import { checkBriefItem, regenerateBrief } from '../actions'
import { btn32, card18, quiet, useFail, useNum, type Me } from './kit'

type Props = { detail: Detail; brief: Brief | null; onChanged: () => Promise<void>; me: Me; products: Record<string, string> }

const str = (v: unknown) => (v === null || v === undefined ? null : typeof v === 'string' ? v : typeof v === 'number' || typeof v === 'boolean' ? String(v) : Array.isArray(v) ? v.map(String).join(', ') : null)

/**
 * The pre-call brief (MTG-01, spec §2.2): facts computed from the records with their source, ticked per staff member;
 * «From earlier conversations» only as verbatim quotes the AI provider found, and so «not connected» until it is.
 */
export function BriefTab({ detail, brief, onChanged, me, products }: Props) {
  const t = useTranslations('meetings.brief')
  const f = useFormatter()
  const num = useNum(me)
  const fail = useFail()
  const flash = useToast()
  const [checked, setChecked] = useState<Record<string, boolean>>(() => Object.fromEntries((brief?.changes ?? []).map((c) => [c.key, c.checked])))
  const [busy, setBusy] = useState(false)
  const date = (iso: string | null | undefined) => (iso ? f.dateTime(new Date(iso), { day: 'numeric', month: 'short' }) : '')

  const regenerate = async () => {
    setBusy(true)
    const r = await regenerateBrief(detail.id)
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('regenerated'))
    await onChanged()
  }
  const tick = async (key: string, on: boolean) => {
    setChecked((c) => ({ ...c, [key]: on }))
    const r = await checkBriefItem({ id: detail.id, key, checked: on })
    if (!r.ok) { setChecked((c) => ({ ...c, [key]: !on })); fail(r) }
  }

  const change = (c: Brief['changes'][number]) => {
    const p = c.params
    switch (c.kind) {
      case 'field_changed':
        return t('change.field_changed', { entity: t(`entity.${str(p.entity) ?? 'deal'}`), field: str(p.field) ?? '', old: str(p.old) ?? '—', new: str(p.new) ?? '—' })
      case 'email_engagement':
        return t('change.email_engagement', { person: str(p.person) ?? '', opens: Number(p.opens ?? 0), clicks: Number(p.clicks ?? 0) })
      case 'ticket_resolved':
        return p.csat !== null && p.csat !== undefined
          ? t('change.ticket_resolved_csat', { number: str(p.number) ?? '', date: date(c.at), csat: str(p.csat) ?? '' })
          : t('change.ticket_resolved', { number: str(p.number) ?? '', date: date(c.at) })
      case 'participant_added':
        return t('change.participant_added', { person: str(p.person) ?? '' })
      case 'count_changed':
        return t('change.count_changed', { product: products[str(p.product) ?? ''] ?? str(p.product) ?? '', metric: str(p.metric) ?? '', from: num(Number(p.from ?? 0)), to: num(Number(p.to ?? 0)) })
      default:
        return t('change.other')
    }
  }

  const twice = new Set((brief?.facts ?? []).map((x) => x.key).filter((k, i, all) => all.indexOf(k) !== i))
  const fact = (x: Brief['facts'][number]): [string, string] => {
    const p = x.params
    if (x.key === 'deal') {
      const v = typeof p.value === 'number' ? money(p.value, me.numberFormat, str(p.currency) ?? 'NOK') : null
      return [t('fact.deal'), [v, str(p.stage)].filter(Boolean).join(' · ') || (str(p.title) ?? '—')]
    }
    if (x.key === 'lead') {
      const v = typeof p.value === 'number' ? money(p.value, me.numberFormat, str(p.currency) ?? 'NOK') : null
      return [t('fact.lead'), [`L-${str(p.seq) ?? ''}`, v].filter(Boolean).join(' · ')]
    }
    if (x.key === 'score') return [t('fact.score'), str(p.score) ?? '—']
    // two organisations with the same line (two «Health · Orgpuls») are told apart by the organisation's name (R-MEETINGS-03)
    const org = twice.has(x.key) ? str(p.organization) : null
    if (x.key.startsWith('health:')) {
      const product = products[str(p.product) ?? ''] ?? str(p.product) ?? ''
      return [org ? t('fact.healthOrg', { product, organization: org }) : t('fact.health', { product }), str(p.score) ?? '—']
    }
    if (x.key === 'applications') return [org ? t('fact.applicationsOrg', { organization: org }) : t('fact.applications'), (Array.isArray(p.products) ? p.products : []).map((k) => products[String(k)] ?? String(k)).join(', ')]
    if (x.key.startsWith('custom.')) return [str(p.label) ?? x.key.slice(7), str(p.value) ?? '—']
    return [x.key, '—']
  }

  const src = (s: { entity: string; id: string } | null) =>
    s && ['deal', 'lead', 'person', 'organization', 'ticket'].includes(s.entity) ? (
      <Link href={recordHref(s.entity, s.id) as Route} aria-label={t('source')} title={t('source')} className="ml-1 text-11.5 text-link">↗</Link>
    ) : null

  const quotes = () => {
    if (!brief) return null
    if (brief.quotes_state === 'not_connected' || (!brief.ai && brief.quotes.length === 0)) return <span className="text-12.5 leading-[1.5] text-[#F2EAD6]">{t('quotes.not_connected')}</span>
    if (brief.quotes_state === 'requested') return <span className="text-12.5 leading-[1.5] text-[#F2EAD6]">{t('quotes.requested')}</span>
    if (brief.quotes_state === 'failed') return <span className="text-12.5 leading-[1.5] text-[#F2EAD6]">{t('quotes.failed')}</span>
    if (brief.quotes.length === 0) return <span className="text-12.5 leading-[1.5] text-[#F2EAD6]">{t('quotes.none')}</span>
    return brief.quotes.map((q, i) => (
      <span key={i} className="text-12.5 leading-[1.5] text-[#F2EAD6]">❝ «{q.text}» — {[q.speaker, date(q.at)].filter(Boolean).join(', ')}</span>
    ))
  }

  if (!brief || brief.state === 'none') {
    return (
      <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
        <b className="text-13.5">{t('none.title')}</b>
        <span className={quiet}>{detail.linked || detail.attendees?.external ? t('none.body') : t('none.unlinked')}</span>
        <button type="button" disabled={busy} onClick={() => void regenerate()} className={btn32}>{t('prepare')}</button>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
          <b className="text-13.5">{t('since')}</b>
          {brief.changes.map((c) => (
            <label key={c.key} className="flex items-start gap-2 text-12.5 leading-[1.45]">
              <input type="checkbox" checked={!!checked[c.key]} onChange={(e) => void tick(c.key, e.target.checked)} className="mt-[2px] accent-ink" />
              <span>{change(c)}{src(c.source)}</span>
            </label>
          ))}
          {brief.changes.length === 0 ? <span className={quiet}>{brief.last_contact_at ? t('noChangesSince', { date: date(brief.last_contact_at) }) : t('noChanges')}</span> : null}
        </div>
        <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
          <b className="text-13.5">{t('who')}</b>
          {brief.people.map((p, i) => {
            const sub = [p.title, ...p.labels, p.first_meeting ? t('firstMeeting') : null, p.last_signed_in ? t('lastSignedIn', { date: date(p.last_signed_in) }) : null, p.person_id ? null : t('notInCrm')].filter(Boolean)
            return (
              <div key={`${p.person_id ?? p.name}-${i}`} className="flex flex-col border-0 border-b border-solid border-line py-[5px] text-12.5">
                <b>{p.person_id ? <Link href={recordHref('person', p.person_id) as Route} className="text-ink">{p.name}</Link> : p.name}</b>
                {sub.length ? <span className="text-muted">{sub.join(' · ')}</span> : null}
              </div>
            )
          })}
          {brief.people.length === 0 ? <span className={quiet}>{t('noPeople')}</span> : null}
        </div>
        <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
          <b className="text-13.5">{t('facts')}</b>
          {brief.facts.map((x) => {
            const [k, v] = fact(x)
            return (
              <div key={x.key + x.source?.id} className="flex justify-between gap-3 text-12.5">
                <span className="text-muted">{k}{src(x.source)}</span>
                <b className="text-right">{v}</b>
              </div>
            )
          })}
          {brief.facts.length === 0 ? <span className={quiet}>{detail.linked ? t('noFacts') : t('noFactsUnlinked')}</span> : null}
        </div>
        <div className="flex flex-col gap-[6px] rounded-18 bg-ink px-4 py-[14px] text-canvas">
          <b className="text-13.5">{t('earlier')}</b>
          {quotes()}
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-11.5 text-faint">
          {t('generated', { at: brief.generated_at ? `${f.dateTime(new Date(brief.generated_at), { day: 'numeric', month: 'short' })} ${f.dateTime(new Date(brief.generated_at), { hour: '2-digit', minute: '2-digit' })}` : '—' })}
          {brief.since_at ? ` · ${t('sinceAt', { date: date(brief.since_at) })}` : ''}
        </span>
        <span className="flex-1" />
        <button type="button" disabled={busy} onClick={() => void regenerate()} className={btn32}>{t('regenerate')}</button>
      </div>
    </div>
  )
}
