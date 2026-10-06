'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { Hygiene, Recommendation, SenderDomain } from '@/lib/data/campaigns-shared'
import { archiveHygiene, deleteDomain, recheckDns, saveDomain } from '../actions'
import { card, danger, dark, ghost, label, primary, small } from './bits'
import { useErr } from './hooks'
import type { Can } from './CampaignsView'

type Product = { key: string; name: string }
export type DeliverabilityProps = {
  domains: SenderDomain[]
  providerConnected: boolean
  recommendations: Recommendation[]
  hygiene: Hygiene
  products: Product[]
  can: Can
  nf: NumberFormat
}

const okPill = 'bg-ok-bg text-ok-ink'
const badPill = 'bg-salmon text-rust-ink'
const warnPill = 'bg-amber-bg text-amber-ink'
const offPill = 'bg-tile text-muted'

/** Deliverability (Marketing.dc.html, v.deliver): sending domains with their checks, recommendations, separate streams. */
export function DeliverabilityView(p: DeliverabilityProps) {
  const t = useTranslations('campaigns.deliver')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [editing, setEditing] = useState<string | 'new' | null>(null)
  const [busy, start] = useTransition()
  const recheck = () => start(async () => {
    const r = await recheckDns({})
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('recheckQueued', { n: r.queued }))
    router.refresh()
  })
  const marketing = p.domains.filter((d) => d.stream === 'marketing' && d.sends_here).map((d) => d.domain)
  const transactional = p.domains.filter((d) => d.stream === 'transactional').map((d) => d.domain)
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={`overflow-hidden ${card}`}>
        <div className="flex flex-wrap items-center justify-between gap-2 border-0 border-b border-solid border-line px-[18px] py-3">
          <b className="text-14">{t('domainsTitle')}</b>
          {p.can.configure ? (
            <span className="flex gap-[6px]">
              <button type="button" onClick={() => setEditing(editing === 'new' ? null : 'new')} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('addDomain')}</button>
              {p.domains.length ? <button type="button" disabled={busy} onClick={recheck} className="h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold">{t('recheck')}</button> : null}
            </span>
          ) : null}
        </div>
        {editing === 'new' ? <DomainForm d={null} products={p.products} onDone={() => setEditing(null)} /> : null}
        {p.domains.map((d) => (
          <div key={d.id} className="border-0 border-b border-solid border-line">
            <DomainRow d={d} p={p} onEdit={p.can.configure ? () => setEditing(editing === d.id ? null : d.id) : null} />
            {editing === d.id ? <DomainForm d={d} products={p.products} onDone={() => setEditing(null)} /> : null}
          </div>
        ))}
        {p.domains.length === 0 ? <div className="px-[18px] py-3 text-12.5 text-muted">{t(p.can.configure ? 'noDomainsAdd' : 'noDomains')}</div> : null}
        <div className="px-[18px] py-[10px] text-11.5 text-faint">{t(p.providerConnected ? 'checksNote' : p.domains.some((d) => d.last_checked_at) ? 'checksNoteNoProviderChecked' : 'checksNoteNoProvider')}</div>
      </div>
      <div className="flex flex-col gap-3">
        <Recommendations {...p} />
        <div className="rounded-20 bg-ink px-[18px] py-4 text-12.5 leading-[1.55] text-canvas">
          <b>{t('streamsTitle')}</b>{' '}
          {t('streamsBody', {
            marketing: marketing.length ? marketing.join(', ') : t('aMarketingDomain'),
            transactional: transactional.length ? transactional.join(', ') : t('aTransactionalDomain'),
          })}
        </div>
      </div>
    </div>
  )
}

function DomainRow({ d, p, onEdit }: { d: SenderDomain; p: DeliverabilityProps; onEdit: (() => void) | null }) {
  const t = useTranslations('campaigns.deliver')
  const fmt = useFormatter()
  const checked = d.last_checked_at !== null
  const pill = (v: boolean | null, name: string): [string, string] =>
    v === true ? [`✓ ${name}`, okPill] : v === false ? [t('missing', { name }), badPill] : [t('unchecked', { name }), offPill]
  const checks: [string, string][] = [
    pill(d.spf_ok, 'SPF'),
    pill(d.dkim_ok, 'DKIM'),
    d.dmarc_policy === 'none' ? [t('dmarcNone'), warnPill] : d.dmarc_policy ? [`✓ DMARC p=${d.dmarc_policy}`, okPill] : checked ? [t('missing', { name: 'DMARC' }), badPill] : [t('unchecked', { name: 'DMARC' }), offPill],
    !p.providerConnected ? [t('verifiedOff'), offPill] : d.verified ? [`✓ ${t('verified')}`, okPill] : [t('notVerified'), warnPill],
  ]
  const product = p.products.find((x) => x.key === d.product)?.name
  const stream = [d.stream === 'marketing' ? t('streamMarketing') : t('streamTransactional'), !d.sends_here ? t('sentElsewhere') : null, product].filter(Boolean).join(' · ')
  const bounce = d.rates?.bounce_rate ?? null
  const warm = d.warmup ? (d.warmup.done ? t('warmDone') : t('warmDay', { day: d.warmup.day, days: d.warmup.days })) : '—'
  return (
    <div className="flex flex-col gap-[6px] px-[18px] py-3">
      <div className="flex flex-wrap justify-between gap-2 text-13">
        {onEdit ? (
          <button type="button" onClick={onEdit} title={t('edit')} className="cursor-pointer border-none bg-transparent p-0 text-left font-mono text-12.5 font-bold text-ink underline decoration-line-strong underline-offset-2">{d.domain}</button>
        ) : <b className="font-mono text-12.5">{d.domain}</b>}
        <span className="text-12 text-muted">{stream}</span>
      </div>
      <div className="flex flex-wrap gap-[6px]">
        {checks.map(([n, cls]) => <span key={n} className={`rounded-999 px-[9px] py-[3px] text-11 font-bold ${cls}`}>{n}</span>)}
      </div>
      <div className="flex flex-wrap gap-[14px] text-12 text-muted">
        <span>{t('bounce')} <b className={bounce !== null && bounce > 3 ? 'text-danger' : 'text-ink'}>{bounce !== null ? percent(bounce, p.nf) : '—'}</b></span>
        <span>{t('complaints')} <b className="text-ink">{d.rates?.complaint_rate != null ? percent(d.rates.complaint_rate, p.nf) : '—'}</b></span>
        <span>{t('warmup')} {warm}</span>
      </div>
      <div className="text-11.5 text-faint">
        {[
          `${d.from_name} <${d.from_local}@${d.domain}>`,
          d.postal_address ?? t('noAddress'),
          checked ? t('checkedAt', { at: fmt.dateTime(new Date(d.last_checked_at!), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }) : t('neverChecked'),
        ].join(' · ')}
      </div>
    </div>
  )
}

function DomainForm({ d, products, onDone }: { d: SenderDomain | null; products: Product[]; onDone: () => void }) {
  const t = useTranslations('campaigns.deliver')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [v, setV] = useState({
    domain: d?.domain ?? '', stream: d?.stream ?? 'marketing', sends_here: d?.sends_here ?? true, product: d?.product ?? '', from_name: d?.from_name ?? '',
    from_local: d?.from_local ?? 'news', reply_to: d?.reply_to ?? '', postal_address: d?.postal_address ?? '',
    warmup_started_at: '', warmup_days: d?.warmup?.days ?? 30,
  })
  const [sure, setSure] = useState(false)
  const [busy, start] = useTransition()
  const set = <K extends keyof typeof v>(k: K, x: (typeof v)[K]) => setV((o) => ({ ...o, [k]: x }))
  const save = () => start(async () => {
    const values: Record<string, unknown> = {
      stream: v.stream, sends_here: v.sends_here, product: v.product || null, from_name: v.from_name, from_local: v.from_local,
      reply_to: v.reply_to.trim() || null, postal_address: v.postal_address.trim() || null, warmup_days: v.warmup_days,
    }
    if (!d) values.domain = v.domain
    if (v.warmup_started_at) values.warmup_started_at = v.warmup_started_at
    const r = await saveDomain({ id: d?.id ?? null, version: d?.version ?? null, values: values as never })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t(d ? 'domainSaved' : 'domainAdded'))
    onDone()
    router.refresh()
  })
  const del = () => start(async () => {
    const r = await deleteDomain({ id: d!.id })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('domainDeleted'))
    onDone()
    router.refresh()
  })
  return (
    <div className="grid gap-2 border-0 border-t border-solid border-line bg-canvas px-[18px] py-3 text-12 sm:grid-cols-2">
      <label className={label}>{t('f.domain')}<input value={v.domain} disabled={!!d} onChange={(e) => set('domain', e.target.value.toLowerCase())} placeholder="news.example.no" className={small} /></label>
      <label className={label}>{t('f.stream')}
        <select value={v.stream} onChange={(e) => set('stream', e.target.value as 'marketing' | 'transactional')} className={small}>
          <option value="marketing">{t('streamMarketing')}</option><option value="transactional">{t('streamTransactional')}</option>
        </select>
      </label>
      <label className={label}>{t('f.fromName')}<input value={v.from_name} onChange={(e) => set('from_name', e.target.value)} maxLength={120} className={small} /></label>
      <label className={label}>{t('f.fromLocal')}<input value={v.from_local} onChange={(e) => set('from_local', e.target.value.toLowerCase())} maxLength={40} className={small} /></label>
      <label className={label}>{t('f.replyTo')}<input value={v.reply_to} onChange={(e) => set('reply_to', e.target.value)} maxLength={254} className={small} /></label>
      <label className={label}>{t('f.product')}
        <select value={v.product} onChange={(e) => set('product', e.target.value)} className={small}>
          <option value="">—</option>
          {products.map((x) => <option key={x.key} value={x.key}>{x.name}</option>)}
        </select>
      </label>
      <label className={`${label} sm:col-span-2`}>{t('f.postal')}<input value={v.postal_address} onChange={(e) => set('postal_address', e.target.value)} maxLength={300} placeholder={t('f.postalPlaceholder')} className={small} /></label>
      <label className={label}>{t('f.warmupStart')}<input type="date" value={v.warmup_started_at} onChange={(e) => set('warmup_started_at', e.target.value)} className={small} /></label>
      <label className={label}>{t('f.warmupDays')}<input type="number" min={0} max={120} value={v.warmup_days} onChange={(e) => set('warmup_days', Number(e.target.value))} className={small} /></label>
      <label className="flex items-center gap-2 sm:col-span-2">
        <input type="checkbox" checked={v.sends_here} onChange={(e) => set('sends_here', e.target.checked)} style={{ accentColor: '#191510' }} />{t('f.sendsHere')}
      </label>
      <div className="flex flex-wrap items-center gap-[6px] sm:col-span-2">
        <button type="button" disabled={busy || !v.from_name.trim() || (!d && !v.domain.trim())} onClick={save} className={primary}>{t(d ? 'save' : 'add')}</button>
        <button type="button" onClick={onDone} className={ghost}>{t('cancel')}</button>
        <span className="flex-1" />
        {d ? (
          <>
            {sure ? <span className="text-muted">{t('deleteConfirm')}</span> : null}
            <button type="button" disabled={busy} onClick={() => (sure ? del() : setSure(true))} className={danger}>{t('delete')}</button>
          </>
        ) : null}
      </div>
      {!d ? <span className="text-11.5 text-faint sm:col-span-2">{t('f.checkNote')}</span> : null}
    </div>
  )
}

const LEVEL: Record<string, string> = { high: 'bg-alert', medium: 'bg-warn', ok: 'bg-ok' }
function Recommendations(p: DeliverabilityProps) {
  const t = useTranslations('campaigns.deliver')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [sure, setSure] = useState(false)
  const [busy, start] = useTransition()
  const archive = (n: number) => start(async () => {
    const r = await archiveHygiene({ expected: n })
    if (!r.ok) { flash(err(r.code, r.detail)); router.refresh(); return }
    flash(t('archived', { n: r.archived }))
    setSure(false)
    router.refresh()
  })
  const text = (r: Recommendation) => {
    switch (r.kind) {
      case 'dns_missing': return t('rec.dnsMissing', { records: (r.records ?? []).map((x) => x.toUpperCase()).join(', '), domain: r.domain ?? '' })
      case 'dmarc_none': return t('rec.dmarcNone', { domain: r.domain ?? '' })
      case 'bounce_rate': return t('rec.bounce', { domain: r.domain ?? '', rate: percent(r.rate ?? 0, p.nf) })
      case 'hygiene': return t('rec.hygiene', { n: formatNumber(r.count ?? 0, p.nf), months: r.months ?? 12 })
      case 'identity': return r.ok ? t('rec.identityOk') : t('rec.identityMissing', { domains: (r.domains_missing_address ?? []).join(', ') })
    }
  }
  return (
    <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
      <b className="text-14">{t('recTitle')}</b>
      {p.recommendations.map((r, i) => (
        <div key={i} className="flex items-start gap-[10px] text-12.5 leading-[1.5]">
          <span className={`w-[7px] flex-none self-stretch rounded-999 ${LEVEL[r.level] ?? 'bg-line-strong'}`} />
          <span className="flex flex-col gap-1">
            <span>{text(r)}</span>
            {r.kind === 'hygiene' && p.can.bulk && r.count ? (
              <span className="flex flex-wrap items-center gap-[6px]">
                {sure ? <span className="text-12 text-muted">{t('archiveConfirm', { n: formatNumber(r.count, p.nf) })}</span> : null}
                <button type="button" disabled={busy} onClick={() => (sure ? archive(r.count!) : setSure(true))} className={dark}>{t('archive', { n: formatNumber(r.count, p.nf) })}</button>
                {sure ? <button type="button" onClick={() => setSure(false)} className={ghost}>{t('cancel')}</button> : null}
              </span>
            ) : null}
          </span>
        </div>
      ))}
      {!p.hygiene.enabled ? <div className="text-11.5 text-faint">{t('hygieneOff')}</div> : null}
    </div>
  )
}
