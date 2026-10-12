'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import {
  AD_CHANNELS, AD_TONE, AD_UTM, parseAmount, slug, trackingUrl, type AdCampaign, type AdCampaigns, type AdChannel,
} from '@/lib/data/simple-growth-shared'
import type { CampaignDetail } from '@/lib/growth/v3'
import { createCampaign, setCampaignSpend, setCampaignState } from '../actions'
import { campaignDetail } from '../v3-actions'
import { colHead } from './kit'
import { CampaignInsights } from './v3/CampaignInsights'

const COLS = '[grid-template-columns:minmax(0,1.5fr)_80px_80px_60px_80px]'
const field = 'h-10 rounded-10 border border-line bg-canvas px-3 text-13 text-ink'
const label = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'

/**
 * Growth › Marketing campaigns (GrowthMarketing.dc.html, v.campaigns) on ad_campaigns_get. Spend is what people typed in
 * under the campaign's utm_campaign; signups and paying customers are first touches carrying it; visits wait for the
 * website tracker («—»). Launch, pause and resume change the record only — no ad platform is connected, and the card
 * says so (V-SGR-13).
 */
export function CampaignsTab({ d, nf, product, app, canAdd, editOthers, canSpend, initialDetail = null }: {
  d: AdCampaigns; nf: NumberFormat; product: string; app: string; canAdd: boolean; editOthers: boolean; canSpend: boolean
  /** the first campaign's days, ads and keywords (0083), read with the page */
  initialDetail?: CampaignDetail | null
}) {
  const t = useTranslations('simpleGrowth.campaigns')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [selId, setSelId] = useState<string | null>(d.rows[0]?.id ?? null)
  const [modal, setModal] = useState(false)
  const host = d.site?.hostname ?? null
  const dash = '—'
  const kr = (v: number | null | undefined) => (v === null || v === undefined ? dash : money(v, nf))

  const rows = d.rows
  const cur = rows.find((c) => c.id === selId) ?? rows[0] ?? null
  // each campaign's days, ads and keywords (ad_campaign_detail), read when it is first chosen and kept for this visit
  const [details, setDetails] = useState<Record<string, CampaignDetail | 'failed'>>(initialDetail ? { [initialDetail.id]: initialDetail } : {})
  const want = cur && cur.figures && !details[cur.id] ? cur.id : null
  useEffect(() => {
    if (!want) return
    let live = true
    campaignDetail({ id: want }).then((r) => { if (live) setDetails((m) => ({ ...m, [want]: r.ok ? r.data : 'failed' })) },
      () => { if (live) setDetails((m) => ({ ...m, [want]: 'failed' })) })
    return () => { live = false }
  }, [want])
  // a refresh (after a save) reads the days again
  useEffect(() => { setDetails(initialDetail ? { [initialDetail.id]: initialDetail } : {}) }, [d, initialDetail])
  const fig = (c: AdCampaign) => c.figures
  const cps = (c: AdCampaign) => (c.figures && c.figures.spent !== null && c.figures.signups > 0 ? c.figures.spent / c.figures.signups : null)

  // the line over the table: what the visible figures add up to
  const seen = rows.filter((c) => c.figures)
  const spent = seen.some((c) => c.figures!.spent !== null) ? seen.reduce((a, c) => a + (c.figures!.spent ?? 0), 0) : null
  const budget = rows.some((c) => c.budget !== null) ? rows.reduce((a, c) => a + (c.budget ?? 0), 0) : null
  const visits = seen.length && seen.every((c) => c.figures!.visits !== null) ? seen.reduce((a, c) => a + (c.figures!.visits ?? 0), 0) : null
  const signups = seen.reduce((a, c) => a + c.figures!.signups, 0)

  const dates = (c: AdCampaign) => {
    const f = (s: string) => format.dateTime(new Date(`${s}T12:00:00Z`), { day: 'numeric', month: 'short' })
    if (c.starts_on && c.ends_on) return c.starts_on === c.ends_on ? f(c.starts_on) : `${f(c.starts_on)} – ${f(c.ends_on)}`
    if (c.starts_on) return t('dates.from', { date: f(c.starts_on) })
    if (c.ends_on) return t('dates.until', { date: f(c.ends_on) })
    return t('dates.none')
  }
  const mayEdit = (c: AdCampaign) => canAdd && (!!c.mine || editOthers)

  const toggle = (c: AdCampaign) => {
    if (c.state === 'ended') {
      start(async () => {
        const r = await createCampaign({ product, name: t('copyName', { name: c.name }).slice(0, 120), channel: c.channel, landing_path: c.landing_path, budget: c.budget, starts_on: null, ends_on: null })
        if (!r.ok) { flash(te(r.code)); return }
        setSelId(r.id)
        flash(t('toast.duplicated'))
        router.refresh()
      })
      return
    }
    const next = c.state === 'live' ? 'paused' : 'live'
    start(async () => {
      const r = await setCampaignState({ id: c.id, state: next, version: c.version })
      if (!r.ok) { flash(te(r.code)); return }
      flash(next === 'paused' ? t('toast.paused', { channel: t(`channels.${c.channel}`) }) : t('toast.live', { channel: t(`channels.${c.channel}`) }))
      router.refresh()
    })
  }

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 whitespace-nowrap text-12.5 text-muted">
        <span>{t.rich('totals.spent', { spent: kr(spent), budget: kr(budget), b: (x) => <b className="whitespace-nowrap text-ink">{x}</b> })}</span>
        <span>{t.rich('totals.visits', { n: visits === null ? dash : formatNumber(visits, nf), b: (x) => <b className="whitespace-nowrap text-ink">{x}</b> })}</span>
        <span>{t.rich('totals.signups', { n: formatNumber(signups, nf), b: (x) => <b className="whitespace-nowrap text-ink">{x}</b> })}</span>
        <span>{t.rich('totals.cps', { v: spent !== null && signups > 0 ? money(spent / signups, nf) : dash, b: (x) => <b className="whitespace-nowrap text-ink">{x}</b> })}</span>
        <span className="flex-1" />
        {canAdd ? (
          <button type="button" onClick={() => setModal(true)} className="h-9 flex-none cursor-pointer whitespace-nowrap rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold text-ink">
            {t('new')}
          </button>
        ) : null}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="overflow-x-auto"><div className="min-w-[460px]">
          <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] ${colHead} ${COLS}`}>
            <span>{t('cols.campaign')}</span><span>{t('cols.status')}</span><span>{t('cols.spent')}</span><span>{t('cols.signups')}</span><span>{t('cols.cps')}</span>
          </div>
          {rows.map((c) => (
            <button
              key={c.id}
              type="button"
              onClick={() => setSelId(c.id)}
              aria-pressed={cur?.id === c.id}
              className={`grid w-full cursor-pointer items-center gap-[10px] border-0 border-b border-line px-4 py-[10px] text-left text-12.5 tabular-nums ${COLS} ${cur?.id === c.id ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="flex min-w-0 flex-col">
                <b className="overflow-hidden text-ellipsis whitespace-nowrap">{c.name}</b>
                <span className="text-11.5 text-muted">{t(`channels.${c.channel}`)}</span>
              </span>
              <span><span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${AD_TONE[c.state]}`}>{t(`states.${c.state}`)}</span></span>
              <span>{fig(c) ? kr(fig(c)!.spent) : dash}</span>
              <span>{fig(c) ? formatNumber(fig(c)!.signups, nf) : dash}</span>
              <b>{kr(cps(c))}</b>
            </button>
          ))}
          </div></div>
          {rows.length === 0 ? <div className="px-4 py-5 text-12.5 text-muted">{canAdd ? t('empty') : t('emptyNoRight')}</div> : null}
        </div>

        {cur ? (
          <Detail
            key={cur.id}
            c={cur}
            host={host}
            app={app}
            nf={nf}
            dates={dates(cur)}
            mayEdit={mayEdit(cur)}
            canSpend={canSpend}
            detail={details[cur.id] ?? null}
            pending={pending}
            onToggle={() => toggle(cur)}
            onSpend={(month, amount) => start(async () => {
              const r = await setCampaignSpend({ campaign: cur.utm.campaign, channel: cur.channel, month, amount })
              if (!r.ok) { flash(te(r.code)); return }
              flash(amount === null ? t('spend.removed') : t('spend.saved'))
              router.refresh()
            })}
          />
        ) : null}
      </div>

      {modal ? (
        <NewCampaign
          host={host}
          app={app}
          nf={nf}
          pending={pending}
          onClose={() => setModal(false)}
          onCreate={(v) => start(async () => {
            const r = await createCampaign({ product, ...v })
            if (!r.ok) { flash(te(r.code)); return }
            setModal(false)
            setSelId(r.id)
            flash(t('toast.created'))
            router.refresh()
          })}
        />
      ) : null}
    </div>
  )
}

function Detail({ c, host, app, nf, dates, mayEdit, canSpend, detail, pending, onToggle, onSpend }: {
  c: AdCampaign; host: string | null; app: string; nf: NumberFormat; dates: string; mayEdit: boolean; canSpend: boolean
  detail: CampaignDetail | 'failed' | null; pending: boolean
  onToggle: () => void; onSpend: (month: string, amount: number | null) => void
}) {
  const t = useTranslations('simpleGrowth.campaigns')
  const te = useTranslations('common.errors')
  const ta = useTranslations('simpleGrowth.ads')
  const format = useFormatter()
  const flash = useToast()
  const f = c.figures
  // an ad platform campaign's spend is imported (0077): its months are the platform's, and its state follows the platform
  const platform = c.platform ?? null
  const dash = '—'
  const url = trackingUrl(host, c.landing_path, c.utm)
  const used = f && f.spent !== null && c.budget ? Math.round((f.spent / c.budget) * 100) : f && c.budget ? 0 : null
  const thisMonth = new Date().toISOString().slice(0, 7)
  const [month, setMonth] = useState(thisMonth)
  const entered = f?.spend.find((s) => s.month === month)
  const imported = !!entered?.source && entered.source !== 'typed'
  const [amount, setAmount] = useState(entered ? formatNumber(entered.amount, nf, Number.isInteger(entered.amount) ? 0 : 2) : '')
  useEffect(() => { setAmount(entered ? formatNumber(entered.amount, nf, Number.isInteger(entered.amount) ? 0 : 2) : '') }, [entered, nf])
  const monthLabel = (m: string) => format.dateTime(new Date(`${m}-15T12:00:00Z`), { month: 'short', year: 'numeric' })
  const stats: [string, string][] = [
    [t('stats.visits'), f?.visits === null || f?.visits === undefined ? dash : formatNumber(f.visits, nf)],
    [t('stats.signups'), f ? formatNumber(f.signups, nf) : dash],
    [t('stats.conversion'), f && f.visits ? percent((f.signups / f.visits) * 100, nf) : dash],
    [t('stats.cps'), f && f.spent !== null && f.signups > 0 ? money(f.spent / f.signups, nf) : dash],
  ]
  const toggleLabel = c.state === 'live' ? t('toggle.pause') : c.state === 'paused' ? t('toggle.resume') : c.state === 'scheduled' ? t('toggle.launch') : t('toggle.duplicate')

  return (
    <div className="flex flex-col gap-3 rounded-20 border border-ink bg-surface px-5 py-[18px]">
      <div className="flex items-start justify-between gap-[10px]">
        <div>
          <div className="text-12 text-muted">{t(`channels.${c.channel}`)} · {dates}</div>
          <div className="mt-[3px] font-serif text-21 font-semibold leading-[1.2]">{c.name}</div>
        </div>
        <button
          type="button"
          onClick={onToggle}
          disabled={!mayEdit || pending || !!platform}
          title={platform ? ta('followsPlatform', { platform: ta(`names.${platform.provider}`) }) : mayEdit ? undefined : t('toggle.noRight')}
          className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-surface px-3 text-12 font-bold disabled:cursor-not-allowed disabled:opacity-50"
        >
          {toggleLabel}
        </button>
      </div>
      {platform ? (
        <div className="-mt-1 text-11.5 text-muted">{ta('fromPlatform', { platform: ta(`names.${platform.provider}`), name: platform.name, more: platform.count - 1 })}</div>
      ) : c.state !== 'ended' ? <div className="-mt-1 text-11.5 text-muted">{t('toggle.recordOnly', { channel: t(`channels.${c.channel}`) })}</div> : null}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {stats.map(([k, v]) => (
          <div key={k} className="rounded-13 border border-line bg-canvas px-[10px] py-[9px]">
            <div className="text-10 font-bold uppercase tracking-[.08em] text-muted">{k}</div>
            <b className="text-14">{v}</b>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-[5px]">
        <div className="flex justify-between text-12 text-muted"><span>{t('budgetUsed')}</span><b className="text-ink">{used === null ? dash : `${used} %`}</b></div>
        <div className="h-2 overflow-hidden rounded-999 bg-tile"><div className="h-full bg-warn" style={{ width: `${Math.min(100, used ?? 0)}%` }} /></div>
      </div>
      {f ? <CampaignInsights d={detail && detail !== 'failed' ? detail : null} state={detail === 'failed' ? 'failed' : detail ? 'ready' : 'loading'} nf={nf} /> : null}
      {canSpend && f ? (
        <div className="flex flex-col gap-[6px]">
          <div className="text-11 font-bold uppercase tracking-[.1em] text-muted">{t('spend.title')}</div>
          <div className="text-12 text-muted">
            {f.spend.length ? f.spend.map((s) => `${monthLabel(s.month)}: ${money(s.amount, nf, s.currency)}${s.source && s.source !== 'typed' ? ` (${ta(`names.${s.source}`)})` : ''}`).join(' · ') : t('spend.none')}
          </div>
          <form
            className="flex flex-wrap items-center gap-[6px]"
            onSubmit={(e) => {
              e.preventDefault()
              const a = parseAmount(amount, nf)
              if (a !== null && Number.isNaN(a)) { flash(te('invalid')); return }
              onSpend(month, a)
            }}
          >
            <input type="month" value={month} onChange={(e) => setMonth(e.target.value || thisMonth)} aria-label={t('spend.month')} className="h-[30px] rounded-9 border border-line bg-canvas px-2 text-12" />
            <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" placeholder={t('spend.amount')} aria-label={t('spend.amount')} disabled={imported} className="h-[30px] w-[110px] rounded-9 border border-line bg-canvas px-2 text-12.5" />
            <button type="submit" disabled={pending || imported} className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold disabled:cursor-default disabled:opacity-60">{t('spend.save')}</button>
          </form>
          {imported && entered?.source ? <div className="text-11.5 text-muted">{ta('spendImported', { platform: ta(`names.${entered.source}`) })}</div> : null}
        </div>
      ) : null}
      <div className="text-11 font-bold uppercase tracking-[.1em] text-muted">{t('link.title')}</div>
      <div className="break-all rounded-10 border border-line bg-canvas px-3 py-[10px] font-[ui-monospace,Menlo,monospace] text-11.5">{url ?? t('link.noSite', { app })}</div>
      <button
        type="button"
        disabled={!url}
        onClick={() => {
          if (!url) return
          navigator.clipboard.writeText(url).then(() => flash(t('link.copied')), () => flash(te('failed')))
        }}
        className="h-[30px] cursor-pointer self-start rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold disabled:cursor-not-allowed disabled:opacity-50"
      >
        {t('link.copy')}
      </button>
      <div className="text-12 text-muted">{t('link.note')}</div>
    </div>
  )
}

type Draft = { name: string; channel: AdChannel; budget: number | null; landing_path: string; starts_on: string | null; ends_on: string | null }

function NewCampaign({ host, app, nf, pending, onClose, onCreate }: {
  host: string | null; app: string; nf: NumberFormat; pending: boolean; onClose: () => void; onCreate: (v: Draft) => void
}) {
  const t = useTranslations('simpleGrowth.campaigns')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [f, setF] = useState({ name: '', channel: 'google_ads' as AdChannel, budget: formatNumber(10000, nf), path: '/', starts: '', ends: '' })
  const first = useRef<HTMLInputElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  useEffect(() => {
    first.current?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close.current() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])
  const path = f.path.trim().startsWith('/') ? f.path.trim() : `/${f.path.trim()}`
  const utm = { source: AD_UTM[f.channel].source, medium: AD_UTM[f.channel].medium, campaign: slug(f.name) || 'campaign' }
  const preview = trackingUrl(host, path, utm)

  const submit = () => {
    const budget = parseAmount(f.budget, nf)
    if (!f.name.trim() || (budget !== null && Number.isNaN(budget)) || !/^\/[A-Za-z0-9/_.~%-]*$/.test(path) || (f.starts && f.ends && f.ends < f.starts)) {
      flash(te('invalid'))
      return
    }
    onCreate({ name: f.name.trim(), channel: f.channel, budget, landing_path: path, starts_on: f.starts || null, ends_on: f.ends || null })
  }

  return (
    <div className="fixed inset-0 z-[90] flex items-center justify-center bg-[rgba(25,21,16,.42)] p-5" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-campaign-title"
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-full w-[480px] max-w-full flex-col gap-[11px] overflow-y-auto rounded-22 bg-surface px-6 py-[22px] shadow-modal"
      >
        <b id="new-campaign-title" className="font-serif text-21">{t('modal.title')}</b>
        <label className={label}>{t('modal.name')}
          <input ref={first} value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder={t('modal.namePlaceholder')} maxLength={120} className={field} />
        </label>
        <div className="grid grid-cols-2 gap-[10px]">
          <label className={label}>{t('modal.channel')}
            <select value={f.channel} onChange={(e) => setF({ ...f, channel: AD_CHANNELS.find((x) => x === e.target.value) ?? 'other' })} className={`${field} px-1`}>
              {AD_CHANNELS.map((ch) => <option key={ch} value={ch}>{t(`channels.${ch}`)}</option>)}
            </select>
          </label>
          <label className={label}>{t('modal.budget')}
            <input value={f.budget} onChange={(e) => setF({ ...f, budget: e.target.value })} inputMode="decimal" className={field} />
          </label>
        </div>
        <div className="grid grid-cols-2 gap-[10px]">
          <label className={label}>{t('modal.starts')}
            <input type="date" value={f.starts} onChange={(e) => setF({ ...f, starts: e.target.value })} className={field} />
          </label>
          <label className={label}>{t('modal.ends')}
            <input type="date" value={f.ends} min={f.starts || undefined} onChange={(e) => setF({ ...f, ends: e.target.value })} className={field} />
          </label>
        </div>
        <label className={label}>{t('modal.landing')}
          <input value={f.path} onChange={(e) => setF({ ...f, path: e.target.value })} placeholder="/" maxLength={300} className={field} />
        </label>
        <div className="break-all rounded-10 border border-dashed border-line-strong bg-canvas px-[11px] py-[9px] font-[ui-monospace,Menlo,monospace] text-11.5">
          {preview ?? t('link.noSite', { app })}
        </div>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-10 cursor-pointer rounded-11 border border-line bg-transparent px-4 text-13 font-semibold">{t('modal.cancel')}</button>
          <button type="button" onClick={submit} disabled={pending} className="h-10 cursor-pointer rounded-11 border border-ink bg-primary px-[18px] text-13 font-bold">{t('modal.create')}</button>
        </div>
      </div>
    </div>
  )
}
