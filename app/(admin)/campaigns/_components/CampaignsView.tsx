'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import {
  CAMPAIGN_TYPES, HTML_STARTER, RECIPIENT_STATES, canEdit,
  type CampaignDetail, type CampaignRow, type CampaignType, type Compare, type Recipient, type RecipientState, type Stats, type Template,
} from '@/lib/data/campaigns-shared'
import { cancelCampaign, createCampaign, deleteCampaign, duplicateCampaign, exportRecipients, pauseCampaign } from '../actions'
import { StatusPill, card, danger, dark, ghost, label, primary, small } from './bits'
import { download, useErr, useGo } from './hooks'

export type Can = { add: boolean; editOthers: boolean; del: boolean; export: boolean; bulk: boolean; configure: boolean }
export type CampaignsProps = {
  rows: CampaignRow[]
  type: CampaignType | null
  selected: CampaignDetail | null
  compare: Compare | null
  cmp: string[] | null
  recipients: { rows: Recipient[]; state: RecipientState | null } | null
  templates: Template[]
  can: Can
  reasonRequired: boolean
  nf: NumberFormat
}

const COLS = '[grid-template-columns:minmax(200px,1.6fr)_120px_120px_80px_70px_70px_80px_90px_100px]'
const dash = '—'

/** Campaigns tab (Marketing.dc.html, v.campaigns): type filter, the list, the selected campaign's card, the comparison. */
export function CampaignsView(p: CampaignsProps) {
  const t = useTranslations('campaigns')
  const { go } = useGo()
  const [creating, setCreating] = useState(false)
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        {[null, ...CAMPAIGN_TYPES].map((k) => {
          const on = p.type === k
          return (
            <button
              key={k ?? 'all'}
              type="button"
              aria-pressed={on}
              onClick={() => go({ type: k, cmp: null })}
              className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
            >
              {k ? t(`types.${k}`) : t('list.all')}
            </button>
          )
        })}
        <span className="flex-1" />
        {p.can.add ? (
          <button type="button" onClick={() => setCreating((x) => !x)} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">
            {t('list.new')}
          </button>
        ) : null}
      </div>
      {creating ? <NewCampaign templates={p.templates} onClose={() => setCreating(false)} /> : null}
      <List {...p} />
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        {p.selected ? <CampaignCard key={`${p.selected.id}:${p.selected.version}`} c={p.selected} can={p.can} reasonRequired={p.reasonRequired} nf={p.nf} /> : (
          <div className={`${card} px-[18px] py-4`}>
            <b className="text-14">{t('card.noneTitle')}</b>
            <div className="mt-2 text-12 text-muted">{t(p.rows.length ? 'card.pick' : p.can.add ? 'card.emptyAdd' : 'card.empty')}</div>
          </div>
        )}
        <CompareCard compare={p.compare} cmp={p.cmp} rows={p.rows} nf={p.nf} />
      </div>
      {p.recipients && p.selected ? <RecipientsCard c={p.selected} data={p.recipients} can={p.can} /> : null}
    </div>
  )
}

/** The audience line under a campaign's name: the segment and its count, or the workflows that send it. */
export function useAudienceLine(nf: NumberFormat) {
  const t = useTranslations('campaigns.list')
  return (c: CampaignRow) => {
    if (c.audience.kind === 'workflow') {
      return c.audience.workflows.length ? t('viaWorkflow', { names: c.audience.workflows.map((w) => w.name).join(', ') }) : t('noWorkflow')
    }
    const a = c.audience
    if (!a.name) return t('noAudience')
    return a.count === null ? a.name : `${a.name} · ${formatNumber(a.count, nf)}`
  }
}

function List(p: CampaignsProps) {
  const t = useTranslations('campaigns')
  const { go } = useGo()
  const aud = useAudienceLine(p.nf)
  const cell = (c: CampaignRow, f: (s: Stats) => string | null) => (c.stats ? f(c.stats) ?? dash : dash)
  const pct = (v: number | null) => (v === null ? null : percent(v, p.nf))
  return (
    <div className={`overflow-hidden ${card}`}>
      <div className="overflow-x-auto">
        <div className="min-w-[1040px]">
          <div className={`grid ${COLS} gap-[10px] border-0 border-b border-solid border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted`}>
            <span>{t('list.col.campaign')}</span><span>{t('list.col.type')}</span><span>{t('list.col.status')}</span><span>{t('list.col.sent')}</span>
            <span>{t('list.col.open')}</span><span>{t('list.col.click')}</span><span>{t('list.col.unsub')}</span>
            <span title={t('list.viaUtm')}>{t('list.col.signups')}</span><span>{t('list.col.mrr')}</span>
          </div>
          {p.rows.map((c) => {
            const on = p.selected?.id === c.id
            return (
              <button
                key={c.id}
                type="button"
                onClick={() => go({ campaign: c.id, view: null, state: null })}
                aria-current={on ? 'true' : undefined}
                className={`grid w-full ${COLS} cursor-pointer items-center gap-[10px] border-0 border-b border-solid border-line px-4 py-[10px] text-left text-12.5 tabular-nums ${on ? 'bg-highlight' : 'bg-transparent'}`}
              >
                <span className="flex min-w-0 flex-col"><b>{c.name}</b><span className="text-11.5 text-muted">{aud(c)}</span></span>
                <span>{t(`types.${c.type}`)}</span>
                <span><StatusPill c={c} /></span>
                <span>{cell(c, (s) => (s.sent ? formatNumber(s.sent, p.nf) : null))}</span>
                <b>{cell(c, (s) => pct(s.open_rate))}</b>
                <b>{cell(c, (s) => pct(s.click_rate))}</b>
                <span>{cell(c, (s) => pct(s.unsub_rate))}</span>
                <span>{cell(c, (s) => (s.signups ? formatNumber(s.signups, p.nf) : null))}</span>
                <b>{cell(c, (s) => (s.mrr_won ? money(s.mrr_won, p.nf) : null))}</b>
              </button>
            )
          })}
          {p.rows.length === 0 ? (
            <div className="px-4 py-[14px] text-12.5 text-muted">{t(p.type ? 'list.noneOfType' : 'list.none')}</div>
          ) : null}
        </div>
      </div>
    </div>
  )
}

function NewCampaign({ templates, onClose }: { templates: Template[]; onClose: () => void }) {
  const t = useTranslations('campaigns')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [name, setName] = useState('')
  const [type, setType] = useState<CampaignType>('newsletter')
  const [from, setFrom] = useState<string>(templates.find((x) => x.layout && x.category === 'newsletter')?.id ?? 'blank')
  const [busy, start] = useTransition()
  const create = () => start(async () => {
    const r = await createCampaign({
      name: name.trim(), type,
      template_id: from !== 'blank' && from !== 'html' ? from : null,
      html: from === 'html' ? HTML_STARTER : null,
    })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('list.created'))
    onClose()
    router.push(`/campaigns?tab=builder&campaign=${r.id}` as Route)
  })
  return (
    <div className={`${card} flex flex-wrap items-end gap-[10px] px-[18px] py-[14px]`}>
      <label className={`${label} min-w-[200px] flex-1`}>
        {t('new.name')}
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={small} autoFocus />
      </label>
      <label className={label}>
        {t('new.type')}
        <select value={type} onChange={(e) => setType(e.target.value as CampaignType)} className={small}>
          {CAMPAIGN_TYPES.map((k) => <option key={k} value={k}>{t(`types.${k}`)}</option>)}
        </select>
      </label>
      <label className={label}>
        {t('new.from')}
        <select value={from} onChange={(e) => setFrom(e.target.value)} className={small}>
          <option value="blank">{t('builder.blank')}</option>
          {templates.map((x) => <option key={x.id} value={x.id}>{x.layout ? x.name : t('builder.saved', { name: x.name })}</option>)}
          <option value="html">{t('builder.ownHtml')}</option>
        </select>
      </label>
      <div className="flex gap-[6px]">
        <button type="button" onClick={create} disabled={busy || !name.trim()} className={primary}>{t('new.create')}</button>
        <button type="button" onClick={onClose} className={ghost}>{t('common.cancel')}</button>
      </div>
    </div>
  )
}

export function useWhen() {
  const t = useTranslations('campaigns.card')
  const ts = useTranslations('campaigns.streams')
  const fmt = useFormatter()
  const dt = (s: string) => fmt.dateTime(new Date(s), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
  return (c: CampaignRow) => {
    switch (c.status) {
      case 'draft': return t('when.draft')
      case 'scheduled': return c.scheduled_at ? t('when.scheduled', { at: dt(c.scheduled_at), stream: c.stream ? ts(c.stream) : '—' }) : t('when.scheduledNoTime')
      case 'sending': return c.started_at ? t('when.sending', { at: dt(c.started_at) }) : t('when.sendingNoTime')
      case 'sent': return c.sent_at ? t('when.sent', { at: dt(c.sent_at) }) : t('when.sentNoTime')
      case 'active': return t('when.active')
      case 'paused': return t('when.paused')
      case 'canceled': return c.canceled_at ? t('when.canceled', { at: dt(c.canceled_at) }) : t('when.canceledNoTime')
    }
  }
}

function CampaignCard({ c, can, reasonRequired, nf }: { c: CampaignDetail; can: Can; reasonRequired: boolean; nf: NumberFormat }) {
  const t = useTranslations('campaigns')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const { go } = useGo()
  const when = useWhen()
  const [busy, start] = useTransition()
  const [confirming, setConfirming] = useState(false)
  const [why, setWhy] = useState('')
  const s = c.reports ? c.stats : null
  const nb = (v: number | null | undefined) => (s && v !== null && v !== undefined ? formatNumber(v, nf) : dash)
  const pc = (v: number | null | undefined) => (s && v !== null && v !== undefined ? percent(v, nf) : dash)
  const tiles: [string, string, string?][] = [
    [t('card.stat.delivered'), nb(s?.delivered)],
    [t('card.stat.bounced'), pc(s?.bounce_rate), s ? t('card.bounceSplit', { hard: s.bounced_hard, soft: s.bounced_soft }) : undefined],
    [t('card.stat.uniqueOpens'), pc(s?.open_rate), s?.unique_opens != null ? t('card.ofDelivered', { n: formatNumber(s.unique_opens, nf) }) : undefined],
    [t('card.stat.totalOpens'), nb(s?.total_opens)],
    [t('card.stat.uniqueClicks'), pc(s?.click_rate), s?.unique_clicks != null ? t('card.ofDelivered', { n: formatNumber(s.unique_clicks, nf) }) : undefined],
    [t('card.stat.ctor'), pc(s?.ctor)],
    [t('card.stat.spam'), nb(s?.complaints)],
    [t('card.stat.signups'), s?.signups ? formatNumber(s.signups, nf) : dash],
  ]
  const editable = canEdit(c, can)
  const run = (f: () => Promise<{ ok: boolean; code?: string; detail?: string | null } & object>, msg: string, after?: (r: never) => void) => start(async () => {
    const r = await f()
    if (!r.ok) { flash(err((r as { code: never }).code, (r as { detail?: string | null }).detail)); return }
    flash(msg)
    after?.(r as never)
    router.refresh()
  })
  const ab = c.subject_b ? (() => {
    const a = c.ab
    const metric = a?.metric === 'opens' ? t('card.abMetric.opens') : t('card.abMetric.clicks')
    if (a?.winner && s) {
      const A = <b className={a.winner === 'a' ? 'text-ink' : 'font-normal'}>«{c.subject_a}»</b>
      const B = <b className={a.winner === 'b' ? 'text-ink' : 'font-normal'}>«{c.subject_b}»</b>
      return <>{t('card.abLabel')} {A} {s.a_metric !== null ? percent(s.a_metric, nf) : dash} {t('card.vs')} {B} {s.b_metric !== null ? percent(s.b_metric, nf) : dash} — {t('card.abWinner')}</>
    }
    if (a?.decides_at) return <>{t('card.abLabel')} «{c.subject_a}» {t('card.vs')} «{c.subject_b}» — {t('card.abRunning', { at: fmt.dateTime(new Date(a.decides_at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }), metric })}</>
    return <>{t('card.abLabel')} «{c.subject_a}» {t('card.vs')} «{c.subject_b}» — {t('card.abPlanned', { percent: a?.percent ?? 20, metric, hours: a?.wait_hours ?? 4 })}</>
  })() : null
  const locations = c.top_locations && c.top_locations.length ? t('card.locations', { list: c.top_locations.join(' · ') }) : null
  return (
    <div className={`${card} px-[18px] py-4`}>
      <div className="mb-[10px] flex items-baseline justify-between gap-3">
        <b className="text-14">{c.name}</b>
        <span className="text-right text-12 text-muted">{when(c)}</span>
      </div>
      {c.status === 'scheduled' && c.hold_reason ? (
        <div className="mb-[10px] rounded-12 border border-salmon bg-peach px-[10px] py-2 text-12 text-rust-ink">{t('card.held', { reason: t(`hold.${c.hold_reason.replace(':', '_')}`) })}</div>
      ) : null}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {tiles.map(([k, v, title]) => (
          <div key={k} title={title} className="rounded-13 border border-line bg-canvas px-[10px] py-[9px]">
            <div className="text-10 font-bold uppercase tracking-label text-muted">{k}</div>
            <b className="text-15">{v}</b>
          </div>
        ))}
      </div>
      {!c.reports ? <div className="mt-3 text-12 text-muted">{t('card.noReports')}</div> : null}
      {c.reports && !s ? <div className="mt-3 text-12 text-muted">{t('card.noFigures')}</div> : null}
      {s && !s.tracking ? <div className="mt-3 text-12 text-muted">{t('card.untracked')}</div> : null}
      {s && s.tracking && s.unique_opens ? <div className="mt-2 text-11.5 text-faint">{t('card.opensNote')}</div> : null}
      {s && s.mrr_won ? <div className="mt-2 text-12 text-muted">{t('card.mrr', { mrr: money(s.mrr_won, nf) })}{s.mrr_excluded_currency ? ` · ${t('card.excludedCurrency', { n: s.mrr_excluded_currency })}` : ''}</div> : null}
      {ab ? <div className="mt-3 text-12 text-muted">{ab}</div> : null}
      {locations || c.notify_owners ? (
        <div className="mt-2 text-12 text-muted">{[locations, c.notify_owners ? (locations ? t('card.ownersNotified') : t('card.ownersNotifiedFirst')) : null].filter(Boolean).join(' · ')}</div>
      ) : null}
      <div className="mt-3 flex flex-wrap gap-[6px] border-0 border-t border-solid border-line pt-3">
        <Link href={`/campaigns?tab=builder&campaign=${c.id}` as Route} className={`${dark} inline-flex items-center text-ink hover:text-ink hover:no-underline`}>
          {c.status === 'draft' && editable ? t('card.edit') : t('card.open')}
        </Link>
        {can.add ? <button type="button" disabled={busy} onClick={() => run(() => duplicateCampaign({ id: c.id }), t('card.duplicated'), (r: { id: string }) => go({ campaign: r.id }))} className={ghost}>{t('card.duplicate')}</button> : null}
        {c.status === 'scheduled' && editable ? <button type="button" disabled={busy} onClick={() => run(() => cancelCampaign({ id: c.id }), t('card.canceled'))} className={ghost}>{t('card.cancel')}</button> : null}
        {(c.status === 'active' || c.status === 'paused') && editable ? (
          <button type="button" disabled={busy} onClick={() => run(() => pauseCampaign({ id: c.id, paused: c.status === 'active' }), t(c.status === 'active' ? 'card.paused' : 'card.resumed'))} className={ghost}>
            {t(c.status === 'active' ? 'card.pause' : 'card.resume')}
          </button>
        ) : null}
        {c.reports && c.stats ? <button type="button" onClick={() => go({ view: 'recipients', state: null })} className={ghost}>{t('card.recipients')}</button> : null}
        {c.status === 'draft' && can.del ? <button type="button" disabled={busy} onClick={() => setConfirming(true)} className={danger}>{t('card.delete')}</button> : null}
      </div>
      {confirming ? (
        <div className="mt-2 flex flex-wrap items-center gap-[6px] text-12">
          <span className="text-muted">{t('card.deleteConfirm')}</span>
          {reasonRequired ? <input value={why} onChange={(e) => setWhy(e.target.value)} placeholder={t('common.reason')} maxLength={300} className={`${small} min-w-[180px] flex-1`} /> : null}
          <button type="button" disabled={busy || (reasonRequired && !why.trim())} onClick={() => run(() => deleteCampaign({ id: c.id, reason: why }), t('card.deleted'), () => go({ campaign: null }))} className={danger}>{t('card.delete')}</button>
          <button type="button" onClick={() => setConfirming(false)} className={ghost}>{t('common.cancel')}</button>
        </div>
      ) : null}
    </div>
  )
}

function CompareCard({ compare, cmp, rows, nf }: { compare: Compare | null; cmp: string[] | null; rows: CampaignRow[]; nf: NumberFormat }) {
  const t = useTranslations('campaigns.compare')
  const { go } = useGo()
  const [choosing, setChoosing] = useState(false)
  const [picked, setPicked] = useState<string[]>(cmp ?? compare?.rows.map((r) => r.id) ?? [])
  const choosable = rows.filter((r) => ['sent', 'sending', 'active', 'paused'].includes(r.status) && r.reports && r.stats)
  const axis = compare?.axis_max ?? 100
  const w = (v: number | null) => `${Math.max(0, Math.min(100, ((v ?? 0) / axis) * 100))}%`
  return (
    <div className={`${card} px-[18px] py-4`}>
      <div className="mb-[10px] flex items-baseline justify-between gap-3">
        <b className="text-14">{t('title')}</b>
        <span className="text-right text-12 text-muted">{t('same')}</span>
      </div>
      {compare && compare.rows.length ? compare.rows.map((r) => (
        <div key={r.id} className="grid items-center gap-2 py-1 text-12 [grid-template-columns:150px_minmax(0,1fr)_54px]">
          <span className="overflow-hidden text-ellipsis whitespace-nowrap" title={r.name}>{r.name}</span>
          <span className="flex flex-col gap-[2px]">
            <span className="h-2 overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-teal-mid" style={{ width: w(r.stats?.open_rate ?? null) }} /></span>
            <span className="h-2 overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-warn" style={{ width: w(r.stats?.click_rate ?? null) }} /></span>
          </span>
          <span className="flex flex-col text-right leading-[1.15]">
            <b>{r.stats?.open_rate != null ? percent(r.stats.open_rate, nf) : '—'}</b>
            <span className="text-10.5 text-warn-ink">{r.stats?.click_rate != null ? percent(r.stats.click_rate, nf) : '—'}</span>
          </span>
        </div>
      )) : <div className="py-1 text-12 text-muted">{t('none')}</div>}
      <div className="mt-2 flex flex-wrap gap-3 text-11.5 text-muted">
        <span>▬ {t('open')}</span><span className="text-warn-ink">▬ {t('click')}</span>
        <span className="flex-1" />
        {choosable.length >= 2 ? (
          <button type="button" onClick={() => setChoosing((x) => !x)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 text-link underline">{t('choose')}</button>
        ) : null}
        {cmp ? <button type="button" onClick={() => go({ cmp: null })} className="cursor-pointer border-none bg-transparent p-0 text-11.5 text-link underline">{t('latest')}</button> : null}
      </div>
      <div className="mt-1 text-11 text-faint">{cmp ? t('chosen') : t('defaultNote')}</div>
      {choosing ? (
        <div className="mt-2 flex flex-col gap-1 border-0 border-t border-solid border-line pt-2 text-12">
          {choosable.map((r) => (
            <label key={r.id} className="flex cursor-pointer items-center gap-2">
              <input type="checkbox" checked={picked.includes(r.id)} onChange={(e) => setPicked((xs) => (e.target.checked ? [...xs, r.id] : xs.filter((x) => x !== r.id)))} style={{ accentColor: '#191510' }} />
              {r.name}
            </label>
          ))}
          <div className="mt-1 flex gap-[6px]">
            <button type="button" disabled={picked.length < 2} onClick={() => { setChoosing(false); go({ cmp: picked.slice(0, 20).join(',') }) }} className={primary}>{t('apply')}</button>
            <button type="button" onClick={() => setChoosing(false)} className={ghost}>{t('cancel')}</button>
          </div>
        </div>
      ) : null}
    </div>
  )
}

const RCOLS = '[grid-template-columns:minmax(180px,1.4fr)_150px_50px_110px_110px_110px]'
function RecipientsCard({ c, data, can }: { c: CampaignDetail; data: { rows: Recipient[]; state: RecipientState | null }; can: Can }) {
  const t = useTranslations('campaigns')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const { go } = useGo()
  const [busy, start] = useTransition()
  const dt = (s: string | null) => (s ? fmt.dateTime(new Date(s), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—')
  const exp = () => start(async () => {
    const r = await exportRecipients({ id: c.id })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    download(r.filename, r.mime, r.content)
    flash(t('recipients.exported', { n: r.rows }))
  })
  return (
    <div className={`overflow-hidden ${card}`}>
      <div className="flex flex-wrap items-center gap-2 border-0 border-b border-solid border-line px-[18px] py-3">
        <b className="text-14">{t('recipients.title', { name: c.name })}</b>
        <span className="flex-1" />
        {can.export ? <button type="button" disabled={busy} onClick={exp} className={dark}>{t('recipients.export')}</button> : null}
        <button type="button" onClick={() => go({ view: null, state: null })} className={ghost}>{t('recipients.close')}</button>
      </div>
      <div className="flex flex-wrap gap-[6px] border-0 border-b border-solid border-line px-[18px] py-[10px]">
        {[null, ...RECIPIENT_STATES].map((k) => {
          const on = data.state === k
          return (
            <button key={k ?? 'all'} type="button" aria-pressed={on} onClick={() => go({ state: k })}
              className={`cursor-pointer rounded-999 border px-[10px] py-[4px] text-11.5 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {k ? t(`recipientState.${k}`) : t('list.all')}
            </button>
          )
        })}
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[760px]">
          <div className={`grid ${RCOLS} gap-[10px] border-0 border-b border-solid border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted`}>
            <span>{t('recipients.col.person')}</span><span>{t('recipients.col.state')}</span><span>{t('recipients.col.variant')}</span>
            <span>{t('recipients.col.sent')}</span><span>{t('recipients.col.opened')}</span><span>{t('recipients.col.clicked')}</span>
          </div>
          {data.rows.map((r) => (
            <div key={r.id} className={`grid ${RCOLS} items-center gap-[10px] border-0 border-b border-solid border-line px-[18px] py-[8px] text-12`}>
              <span className="flex min-w-0 flex-col">
                {r.person_id && r.name ? <Link href={recordHref('person', r.person_id) as Route} className="font-bold text-ink hover:text-ink">{r.name}</Link> : <b className="text-muted">{t('recipients.hidden')}</b>}
                <span className="overflow-hidden text-ellipsis text-11.5 text-muted">{r.email ?? (r.state === 'skipped' ? t('recipients.noAddressKept') : '—')}</span>
              </span>
              <span>{t(`recipientState.${r.state}`)}{r.skip_reason ? <span className="block text-11 text-muted">{t(`skip.${r.skip_reason}`)}</span> : null}{r.bounce_kind ? <span className="block text-11 text-muted">{t(`bounce.${r.bounce_kind}`)}</span> : null}</span>
              <span>{r.variant ? t(`variant.${r.variant}`) : '—'}</span>
              <span>{dt(r.sent_at)}</span>
              <span>{dt(r.opened_at)}</span>
              <span>{dt(r.clicked_at)}</span>
            </div>
          ))}
          {data.rows.length === 0 ? <div className="px-[18px] py-3 text-12 text-muted">{t('recipients.none')}</div> : null}
          {data.rows.length >= 200 ? <div className="px-[18px] py-2 text-11.5 text-faint">{t('recipients.capped')}</div> : null}
        </div>
      </div>
    </div>
  )
}
