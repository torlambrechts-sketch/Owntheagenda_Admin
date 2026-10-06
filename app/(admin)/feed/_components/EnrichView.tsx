'use client'

import { useState, useTransition } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { ui } from '@/components/ui/styles'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { ENRICH_FIELDS } from '@/lib/data/feed-shared'
import type { EnrichRequest, Enrichment, Lookup } from '@/lib/data/feed'
import { applyEnrich, decideLookup, dismissEnrich, requestBulkEnrich } from '../actions'
import { useErr } from './go'

const BULK_MAX = 100
const tile = 'rounded-18 border border-line bg-surface px-4 py-[14px]'
const tileHead = 'text-10.5 font-bold uppercase tracking-label text-muted'

/** Feed › Enrichment (Feed.dc.html, v.enrich): usage, sources, bulk, the register's diffs and sender lookups. */
export function EnrichView({ data, canBulk, canAdd, nf, now }: { data: Enrichment; canBulk: boolean; canAdd: boolean; nf: NumberFormat; now: string }) {
  const t = useTranslations('feed.enrich')
  const format = useFormatter()
  const flash = useToast()
  const err = useErr()
  const [busy, start] = useTransition()

  // used_month counts from the first of the month (UTC, as enrichment_get does); the next cycle starts on the next first
  const d = new Date(now)
  const resets = format.dateTime(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)), { day: 'numeric', month: 'short', timeZone: 'UTC' })
  const { used_month: used, limit } = data.credits
  const n = Math.min(data.candidates, BULK_MAX)
  const connected = data.contact_data === 'connected'

  const bulk = () => start(async () => {
    const r = await requestBulkEnrich()
    if (!r.ok) { flash(err(r.code)); return }
    flash(r.requested ? t('toast.requested', { n: r.requested }) : t('toast.nothingNew'))
  })

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(180px,1fr))]">
        <div className={tile}>
          <div className={tileHead}>{t('credits.title')}</div>
          <div className="mt-[6px] font-serif text-24 font-semibold">
            {limit !== null ? t('credits.left', { n: formatNumber(Math.max(0, limit - used), nf) }) : t('credits.used', { n: formatNumber(used, nf) })}
          </div>
          {limit !== null ? (
            <div className="mt-2 h-[6px] overflow-hidden rounded-999 bg-tile">
              <div className="h-full bg-warn" style={{ width: `${limit > 0 ? Math.min(100, (used / limit) * 100) : 100}%` }} />
            </div>
          ) : null}
          <div className="mt-[6px] text-11.5 text-muted">
            {limit !== null ? t('credits.of', { limit: formatNumber(limit, nf), date: resets }) : t('credits.unlimited', { date: resets })}
          </div>
        </div>
        <div className={tile}>
          <div className={tileHead}>{t('sources.title')}</div>
          <div className="mt-2 text-13 leading-[1.6]">
            {t('sources.brreg')}<br /><br />
            {t('sources.provider')}{connected ? null : <span className="text-muted"> · {t('sources.notConnected')}</span>}
          </div>
        </div>
        <div className={tile}>
          <div className={tileHead}>{t('bulk.title')}</div>
          <div className="mt-2 text-13">{t('bulk.body')}</div>
          <button
            type="button"
            disabled={busy || n === 0 || (n > 1 && !canBulk)}
            title={n > 1 && !canBulk ? t('bulk.noRight') : undefined}
            onClick={bulk}
            className="mt-2 h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold disabled:cursor-default disabled:opacity-50"
          >
            {data.candidates > BULK_MAX ? t('bulk.buttonMax', { n: BULK_MAX, total: formatNumber(data.candidates, nf) }) : t('bulk.button', { n })}
          </button>
        </div>
      </div>

      <div className="grid gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <CompanyCard requests={data.requests} nf={nf} />
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-3">
            <b className="text-14">{t('person.title')}</b>
            <span className="text-12 text-muted">{t('person.sub')}</span>
          </div>
          <div className="px-[18px] py-[14px] text-12.5 text-muted">{connected ? t('person.connected') : t('person.notConnected')}</div>
        </div>
      </div>

      {data.lookups.length ? data.lookups.map((l) => <LookupCard key={l.id} lookup={l} canAdd={canAdd} />) : (
        <div className="flex flex-col gap-1 rounded-20 border border-ink bg-surface px-5 py-4">
          <span className={ui.eyebrow}>{t('lookup.eyebrow')}</span>
          <span className="text-12.5 text-muted">{t('lookup.none')}</span>
        </div>
      )}
    </div>
  )
}

function CompanyCard({ requests, nf }: { requests: EnrichRequest[]; nf: NumberFormat }) {
  const t = useTranslations('feed.enrich.company')
  const format = useFormatter()
  const flash = useToast()
  const err = useErr()
  const [busy, start] = useTransition()
  const first = requests.find((r) => r.state === 'ready') ?? requests[0] ?? null
  const [chosen, setChosen] = useState<string | null>(first?.id ?? null)
  const req = requests.find((r) => r.id === chosen) ?? first
  const writable = req ? req.fields.filter((f) => f.writable).map((f) => f.field) : []
  const [off, setOff] = useState<Record<string, boolean>>({})
  const on = writable.filter((f) => !off[`${req?.id}:${f}`])

  const show = (field: string, v: unknown) => {
    if (v === null || v === undefined || v === '') return '—'
    if (field === 'employees' && typeof v === 'number') return formatNumber(v, nf)
    return typeof v === 'string' || typeof v === 'number' ? String(v) : '—'
  }
  const apply = () => req && start(async () => {
    const r = await applyEnrich({ request: req.id, fields: on.filter((f): f is (typeof ENRICH_FIELDS)[number] => (ENRICH_FIELDS as readonly string[]).includes(f)) })
    flash(r.ok ? t('applied', { n: r.applied }) : err(r.code))
  })
  const dismiss = () => req && start(async () => {
    const r = await dismissEnrich({ request: req.id })
    flash(r.ok ? t('dismissed') : err(r.code))
  })
  const ghost = 'h-8 cursor-pointer rounded-9 border border-line bg-transparent px-[13px] text-12 font-semibold'

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-3">
        <b className="text-14">{req ? t('title', { org: req.organization }) : t('titleNone')}</b>
        <span className="text-12 text-muted">{t('sub')}</span>
      </div>
      {requests.length > 1 ? (
        <div className="border-b border-line px-[18px] py-2">
          <select aria-label={t('choose')} value={req?.id ?? ''} onChange={(e) => setChosen(e.target.value)} className={`${ui.select} max-w-full px-1`}>
            {requests.map((r) => <option key={r.id} value={r.id}>{r.organization} · {t(`state.${r.state}`)}</option>)}
          </select>
        </div>
      ) : null}
      {!req ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('none')}</div> : null}
      {req?.state === 'requested' ? (
        <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('requested', { date: format.dateTime(new Date(req.created_at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) })}</div>
      ) : null}
      {req?.state === 'failed' ? <div className="px-[18px] py-[14px] text-12.5 text-danger">{t('failed', { error: req.error ?? '—' })}</div> : null}
      {req?.state === 'ready' && req.fields.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('nothingNew')}</div> : null}
      {req?.state === 'ready' ? req.fields.map((f) => {
        const k = `${req.id}:${f.field}`
        return (
          <div key={f.field} className="grid items-center gap-2 border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:120px_minmax(0,1fr)_minmax(0,1fr)_40px]">
            <span className="text-muted">{t(`fields.${f.field}`)}</span>
            <span className="break-words text-faint">{show(f.field, f.current)}</span>
            <b className="break-words text-ok-ink">{f.writable ? show(f.field, f.proposed) : t('kept', { value: show(f.field, f.proposed) })}</b>
            <input
              type="checkbox"
              aria-label={t(`fields.${f.field}`)}
              checked={f.writable && !off[k]}
              disabled={!f.writable}
              onChange={() => setOff({ ...off, [k]: !off[k] })}
              className="accent-ink"
            />
          </div>
        )
      }) : null}
      {req ? (
        <div className="flex justify-end gap-2 px-[18px] py-[10px]">
          <button type="button" disabled={busy} onClick={dismiss} className={ghost}>{t('dismiss')}</button>
          {req.state === 'ready' && req.fields.length ? (
            <button type="button" disabled={busy || on.length === 0} onClick={apply} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold disabled:cursor-default disabled:opacity-50">
              {t('apply', { n: on.length })}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

function LookupCard({ lookup, canAdd }: { lookup: Lookup; canAdd: boolean }) {
  const t = useTranslations('feed.enrich.lookup')
  const flash = useToast()
  const err = useErr()
  const [busy, start] = useTransition()
  const name = lookup.name ?? lookup.from.split('@')[0]!
  const decide = (accept: boolean) => start(async () => {
    const r = await decideLookup({ id: lookup.id, accept, organizationId: accept ? lookup.organization?.id ?? null : null })
    flash(r.ok ? t(accept ? 'created' : 'dismissed') : err(r.code))
  })
  return (
    <div className="flex flex-wrap items-center gap-[14px] rounded-20 border border-ink bg-surface px-5 py-4">
      <div className="flex flex-[1_1_360px] flex-col gap-1">
        <span className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('eyebrow')}</span>
        <b className="text-14">{t('title', { from: lookup.from })}</b>
        <span className="text-12.5 text-muted">
          {lookup.organization ? t('proposedOrg', { name, org: lookup.organization.name }) : t('proposedNoOrg', { name, domain: lookup.domain })}
        </span>
      </div>
      <div className="flex gap-2">
        <button type="button" disabled={busy} onClick={() => decide(false)} className="h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-[13px] text-12.5 font-semibold">{t('dismiss')}</button>
        <button
          type="button"
          disabled={busy || !canAdd}
          title={canAdd ? undefined : t('noRight')}
          onClick={() => decide(true)}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-50"
        >
          {t('create')}
        </button>
      </div>
    </div>
  )
}
