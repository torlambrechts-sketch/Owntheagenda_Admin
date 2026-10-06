'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useFormatter, useTranslations } from 'next-intl'
import { money } from '@/lib/format'
import { useToast } from '@/components/ui/Toast'
import type { Lead } from '@/lib/data/contacts'
import { archiveLeads, labelLeads } from '../actions'
import type { TabProps } from './ContactsScreen'
import { firstName, localDay, useError, useNav } from './util'
import { ConvertModal } from './ConvertModal'
import { ActivityModal } from './ActivityModal'

const COLS = '[grid-template-columns:26px_minmax(160px,1.6fr)_90px_110px_120px_minmax(110px,1fr)]'
const smallBtn = 'h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold'

/** Leads (Contacts.dc.html, v.leads): label filter, bulk actions, the list and the selected lead. */
export function LeadsTab({ data, rights, me, now, openForm }: TabProps) {
  const t = useTranslations('contacts')
  const format = useFormatter()
  const flash = useToast()
  const err = useError()
  const { go, refresh } = useNav()
  const [sel, setSel] = useState<Record<string, boolean>>({})
  const [convert, setConvert] = useState(false)
  const [activity, setActivity] = useState<string[] | null>(null)
  const leads = data.leads ?? []
  const lead = data.lead
  const labelById = Object.fromEntries(data.labels.lead.map((l) => [l.id, l]))
  const hot = data.labels.lead.find((l) => l.name.toLowerCase() === 'hot')
  const selected = leads.filter((l) => sel[l.id]).map((l) => l.id)
  const nowD = new Date(now)

  /** «today 14:00», «tomorrow 09:00», «Thu 10:00», «12 Oct»: when the next activity is, in the staff member's zone. */
  const when = (iso: string) => {
    const d = new Date(iso)
    const days = Math.round((new Date(localDay(d, me.tz)).getTime() - new Date(localDay(nowD, me.tz)).getTime()) / 86_400_000)
    const time = format.dateTime(d, { hour: '2-digit', minute: '2-digit' })
    if (days === 0) return t('leads.today', { time })
    if (days === 1) return t('leads.tomorrow', { time })
    if (days > 1 && days < 7) return `${format.dateTime(d, { weekday: 'short' })} ${time}`
    return format.dateTime(d, { day: 'numeric', month: 'short' })
  }
  const next = (l: Lead) => {
    const a = l.next_activity
    if (!a) return { text: t('leads.noActivity'), c: 'text-danger' }
    const at = a.starts_at ? when(a.starts_at) : ''
    // the time first: in a narrow column the subject is what gives way
    const text = [at, a.subject].filter(Boolean).join(' · ')
    if (a.overdue) return { text: t('leads.overdue', { what: text }), c: 'text-danger' }
    const today = a.starts_at && localDay(new Date(a.starts_at), me.tz) === localDay(nowD, me.tz)
    return { text, c: today ? 'text-link' : 'text-muted' }
  }
  const who = (l: Lead) => [l.person?.name, l.organization?.name].filter(Boolean).join(' · ')

  async function bulkLabel() {
    if (!hot) return
    const r = await labelLeads({ ids: selected, label: hot.id })
    if (!r.ok) return flash(err(r.code))
    flash(t('leads.labelAdded', { label: hot.name, count: selected.length }))
    setSel({}); refresh()
  }
  async function archive(ids: string[], archived: boolean) {
    const r = await archiveLeads({ ids, archived })
    if (!r.ok) return flash(err(r.code))
    flash(archived ? (ids.length === 1 ? t('leads.archivedOne') : t('leads.archived', { count: ids.length })) : t('leads.unarchived'))
    setSel({}); refresh()
  }

  const enriched = lead?.organization
    ? [lead.organization.industry, lead.organization.employees !== null ? t('leads.employees', { count: lead.organization.employees }) : null, lead.organization.city, lead.person?.email?.split('@')[1]].filter(Boolean).join(' · ')
    : null
  const answers = formAnswers(lead?.form_data)
  const chat = lead?.source && /chat/i.test(lead.source)
  const canEditLead = lead ? lead.owner_id === me.id || rights.editOthers : false

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap items-center gap-2">
        {[{ id: '', name: t('leads.all') }, ...data.labels.lead].map((f) => {
          const on = data.query.leadLabel === f.id
          return (
            <button key={f.id || 'all'} type="button" onClick={() => go({ ll: f.id || null, lead: null })} aria-pressed={on}
              className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {f.name}
            </button>
          )
        })}
        <span className="flex-1" />
        {selected.length ? (
          <span className="flex flex-wrap items-center gap-[6px] text-12.5">
            <b>{t('leads.selected', { count: selected.length })}</b>
            {rights.bulk && hot ? <button type="button" onClick={bulkLabel} className={smallBtn}>{t('leads.labelBulk', { label: hot.name })}</button> : null}
            {rights.bulk ? <button type="button" onClick={() => archive(selected, !data.query.archived)} className={smallBtn}>{data.query.archived ? t('leads.unarchive') : t('leads.archive')}</button> : null}
            {rights.add ? <button type="button" onClick={() => setActivity(selected)} className={smallBtn}>{t('leads.activityEach')}</button> : null}
          </span>
        ) : null}
        <button type="button" onClick={() => go({ archived: data.query.archived ? null : '1', lead: null })} aria-pressed={data.query.archived}
          className={`h-8 cursor-pointer rounded-9 border px-[11px] text-12 font-semibold ${data.query.archived ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}>
          {t('leads.archiveToggle')}{data.query.archived ? ' ✓' : ''}
        </button>
      </div>
      <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(0,1fr)_minmax(300px,380px)]">
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="overflow-x-auto">
            <div className="min-w-[680px] md:min-w-0">
              <div className={`grid gap-[10px] border-b border-line px-[14px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${COLS}`}>
                <span /><span>{t('leads.col.lead')}</span><span>{t('leads.col.value')}</span><span>{t('leads.col.labels')}</span><span>{t('leads.col.source')}</span><span>{t('leads.col.next')}</span>
              </div>
              {leads.map((l) => {
                const n = next(l)
                return (
                  <div key={l.id} className={`grid items-center gap-[10px] border-b border-line px-[14px] py-[9px] text-12.5 ${COLS} ${lead?.id === l.id ? 'bg-highlight' : 'bg-transparent'}`}>
                    <input type="checkbox" disabled={!rights.bulk && !rights.add} checked={!!sel[l.id]} onChange={() => setSel({ ...sel, [l.id]: !sel[l.id] })} aria-label={t('leads.select', { title: l.title })} className="accent-ink" />
                    <button type="button" onClick={() => go({ lead: l.id })} className="flex min-w-0 cursor-pointer flex-col border-none bg-transparent p-0 text-left">
                      <b>{l.title}</b>
                      <span className="text-11.5 text-muted">{[who(l), firstName(l.owner?.name)].filter(Boolean).join(' · ')}</span>
                    </button>
                    <b>{l.value !== null ? money(l.value, me.nf, l.currency) : '—'}</b>
                    <span className="flex flex-wrap gap-[3px]">
                      {l.labels.map((id) => labelById[id]).filter(Boolean).map((x) => (
                        <span key={x!.id} className="rounded-999 px-[7px] py-px text-10.5 font-bold" style={{ background: x!.bg, color: x!.ink }}>{x!.name}</span>
                      ))}
                    </span>
                    <span className="text-muted">{l.source ?? '—'}</span>
                    <span title={n.text} className={`truncate ${n.c}`}>{n.text}</span>
                  </div>
                )
              })}
              {leads.length === 0 ? <div className="px-4 py-[30px] text-center text-13 text-muted">{data.query.archived ? t('leads.emptyArchived') : t('leads.empty')}</div> : null}
            </div>
          </div>
        </div>
        {lead ? (
          <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-[18px] md:sticky md:top-20">
            <div className="flex justify-between gap-2 text-11.5 text-muted">
              <span>{[lead.source, format.relativeTime(new Date(lead.created_at), nowD)].filter(Boolean).join(' · ')}</span>
              {canEditLead ? <button type="button" onClick={() => openForm({ entity: 'lead', id: lead.id, lead })} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('edit')}</button> : null}
            </div>
            <b className="font-serif text-20 leading-[1.2]">{lead.title}</b>
            <span className="text-12.5 text-ink-2">{who(lead) || '—'}</span>
            {enriched ? (
              <div className="rounded-14 bg-teal-soft px-3 py-[10px] text-12 leading-[1.55]"><b>{t('leads.companyData')}</b><br />{enriched}</div>
            ) : null}
            {answers ? (
              <div className="rounded-14 border border-line bg-canvas px-3 py-[10px] text-12 leading-[1.55]"><b>{chat ? t('leads.chatAnswers') : t('leads.formAnswers')}</b><br />{answers}</div>
            ) : null}
            <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('leads.emailsHead')}</div>
            <div className="border-b border-line py-[6px] text-12 text-muted">{t('leads.noMailbox')}</div>
            <div className="flex flex-wrap gap-[6px]">
              {lead.converted_deal_id ? (
                <Link href={`/deals?deal=${lead.converted_deal_id}` as never} className="flex h-9 items-center rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink hover:text-ink hover:no-underline">{t('leads.openDeal')}</Link>
              ) : rights.add && data.pipelines?.length ? (
                <button type="button" onClick={() => setConvert(true)} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold">{t('leads.convert')}</button>
              ) : null}
              <Link href="/inbox" className="flex h-9 items-center rounded-10 border border-line bg-transparent px-3 text-12.5 font-semibold text-ink hover:text-ink hover:no-underline">{t('leads.email')}</Link>
              {canEditLead && !lead.converted_deal_id ? (
                <button type="button" onClick={() => archive([lead.id], !lead.archived_at)} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-3 text-12.5 font-semibold">
                  {lead.archived_at ? t('leads.unarchive') : t('leads.notRelevant')}
                </button>
              ) : null}
            </div>
            <div className="text-11.5 text-faint">{t('leads.moveNote')}</div>
          </div>
        ) : null}
      </div>
      {convert && lead && data.pipelines ? <ConvertModal lead={lead} pipelines={data.pipelines} onClose={() => setConvert(false)} /> : null}
      {activity ? <ActivityModal ids={activity} types={data.activityTypes} tz={me.tz} onClose={(done) => { setActivity(null); if (done) setSel({}) }} /> : null}
    </div>
  )
}

/** A form's or a chat's answers as the design writes them: «Question» answer · «Question» answer. */
function formAnswers(v: unknown): string | null {
  if (!v || typeof v !== 'object') return null
  const pairs = Array.isArray(v)
    ? v.map((x) => (x && typeof x === 'object' ? [String((x as Record<string, unknown>).q ?? (x as Record<string, unknown>).label ?? ''), String((x as Record<string, unknown>).a ?? (x as Record<string, unknown>).value ?? '')] : ['', String(x)]))
    : Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, typeof x === 'object' ? JSON.stringify(x) : String(x)])
  const out = pairs.filter(([, a]) => a !== '').map(([q, a]) => (q ? `«${q}» ${a}` : a)).join(' · ')
  return out || null
}
