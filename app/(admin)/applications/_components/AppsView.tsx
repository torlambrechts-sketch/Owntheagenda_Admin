'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { AppCard, AppDetail, HealthT } from '@/lib/data/platform'
import { PRODUCT_SCOPES } from '@/lib/data/platform-shared'
import { connectApplication, testConnection } from '../actions'
import { Dialog, OnceValue, k, useAct, useAgo, useNowMs, useSensitive } from './kit'

const PILL: Record<HealthT['status'], string> = {
  operational: 'bg-ok-bg text-ok-ink',
  degraded: 'bg-amber-bg text-amber-ink',
  unreachable: 'bg-salmon text-rust-ink',
  no_data: 'bg-beige text-muted',
  disabled: 'bg-beige text-muted',
  not_installed: 'bg-beige text-muted',
}

/** Requests per hour over 24 h as the design's polyline (viewBox 200×36); nothing is drawn over no calls. */
function Spark({ points, degraded, empty }: { points: number[]; degraded: boolean; empty: string }) {
  const max = Math.max(0, ...points)
  if (max === 0) return <div className="flex h-9 items-center text-11.5 text-faint">{empty}</div>
  const pts = points.map((v, i) => `${((i * 200) / Math.max(points.length - 1, 1)).toFixed(1)},${(32 - (v / max) * 26).toFixed(1)}`).join(' ')
  return (
    <svg viewBox="0 0 200 36" preserveAspectRatio="none" className="block h-9 w-full" aria-hidden="true">
      <polyline points={pts} fill="none" stroke={degraded ? '#E0A21F' : '#5C9A55'} strokeWidth={2} vectorEffect="non-scaling-stroke" />
    </svg>
  )
}

export function AppsView({ apps, current, detail, owner, nf }: { apps: AppCard[]; current: string | null; detail: AppDetail | null; owner: boolean; nf: NumberFormat }) {
  const t = useTranslations('platform.apps')
  const th = useTranslations('platform.health')
  const [connect, setConnect] = useState(false)

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="flex flex-wrap items-center gap-[10px]">
        <h1 className="m-0 flex-[1_1_360px] font-serif text-22 font-semibold">{t('title')}</h1>
        {owner ? (
          <button type="button" onClick={() => setConnect(true)} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-4 text-13 font-bold">{t('connect')}</button>
        ) : (
          <span className="text-12 text-muted">{t('connectOwner')}</span>
        )}
      </div>

      {apps.length === 0 ? (
        <div className={`${k.card} ${k.empty}`}>{t('none')}</div>
      ) : (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
          {apps.map((a) => {
            const h = a.health
            const inner = (
              <>
                <div className="flex items-center gap-[10px]">
                  <span
                    className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-12 border border-[rgba(25,21,16,.1)] font-serif text-17 font-bold"
                    style={{ background: a.color ?? '#F2EAD6', color: a.ink ?? '#191510' }}
                  >
                    {a.name.slice(0, 1)}
                  </span>
                  <span className="flex min-w-0 flex-1 flex-col">
                    <b className="text-14">{a.name}</b>
                    <span className="text-11.5 text-muted">{[a.description, a.region, a.stage === 'beta' ? t('beta') : null].filter(Boolean).join(' · ') || '—'}</span>
                  </span>
                  <span className={`rounded-999 px-[10px] py-[3px] text-11 font-bold ${PILL[h.status]}`}>{th(h.status)}</span>
                </div>
                <Spark points={a.spark} degraded={h.status === 'degraded'} empty={t('noCalls')} />
                <div className="grid grid-cols-4 gap-[6px] text-11 text-muted">
                  <span className="flex flex-col"><b className="text-13 text-ink">{formatNumber(h.calls_per_min, nf, h.calls_per_min % 1 ? 1 : 0)}</b>{t('rpm')}</span>
                  <span className="flex flex-col"><b className={`text-13 ${h.p95_ms !== null && h.p95_ms > 500 ? 'text-danger' : 'text-ink'}`}>{h.p95_ms !== null ? `${formatNumber(h.p95_ms, nf)} ms` : '—'}</b>p95</span>
                  <span className="flex flex-col"><b className={`text-13 ${h.error_rate !== null && h.error_rate > 0.015 ? 'text-danger' : 'text-ink'}`}>{h.error_rate !== null ? percent(h.error_rate * 100, nf) : '—'}</b>{t('errors')}</span>
                  <span className="flex flex-col"><b className="text-13 text-ink">{formatNumber(a.orgs, nf)}</b>{t('orgs')}</span>
                </div>
              </>
            )
            const cls = `flex flex-col gap-[10px] rounded-20 border bg-surface px-[18px] py-4 text-left text-ink ${a.key === current ? 'border-ink' : 'border-line'}`
            return a.installed ? (
              <Link key={a.key} href={`/applications?app=${a.key}` as Route} aria-current={a.key === current ? 'true' : undefined} className={`${cls} cursor-pointer hover:text-ink hover:no-underline`}>
                {inner}
              </Link>
            ) : (
              <div key={a.key} className={cls}>{inner}</div>
            )
          })}
        </div>
      )}

      {detail ? <Detail d={detail} nf={nf} /> : apps.length ? <div className={`${k.card} ${k.empty}`}>{t('noneInstalled')}</div> : null}
      {connect ? <ConnectDialog onClose={() => setConnect(false)} /> : null}
    </div>
  )
}

function Detail({ d, nf }: { d: AppDetail; nf: NumberFormat }) {
  const t = useTranslations('platform.apps')
  const tu = useTranslations('platform.eventUse')
  const ago = useAgo()
  const nowMs = useNowMs()
  const format = useFormatter()
  const { run, pending, flash } = useAct()
  const c = d.connection
  const yes = (b: boolean) => (b ? '✓' : '✗')
  const conn: [string, string, boolean][] = c
    ? [
        [t('conn.baseUrl'), c.api_url ?? '—', true],
        [t('conn.version'), c.api_version ?? '—', false],
        [t('conn.auth'), t('conn.authValue', { token: yes(c.token_secret), webhook: yes(c.webhook_secret) }), false],
        [t('conn.inbound'), t('conn.inboundValue', { count: c.event_kinds_30d }), false],
        [t('conn.key'), `product_id = ${d.key}`, true],
        [t('conn.region'), c.region ?? '—', false],
        [t('conn.lastSync'), ago(c.last_sync_at), false],
        [t('conn.since'), c.connected_since ? format.dateTime(new Date(c.connected_since), { day: 'numeric', month: 'short', year: 'numeric' }) : '—', false],
        [t('conn.state'), c.enabled ? t('conn.enabled') : t('conn.awaitingSecrets'), false],
      ]
    : [[t('conn.state'), t('conn.notInstalled'), false]]

  // Healthy while the family has spoken; the usage stream is lagging once it is older than the push interval plus 5 min
  const s = d.synced
  const state = (last: string | null, stream: boolean): [string, string] => {
    if (!last) return [t('sync.noData'), 'text-muted']
    const min = Math.floor((nowMs - new Date(last).getTime()) / 60_000)
    return stream && min > 10 ? [t('sync.lagging', { min }), 'text-danger'] : [t('sync.healthy'), 'text-link']
  }
  const synced: [string, string, string, string | null, boolean][] = [
    [t('sync.orgs'), t('sync.orgsDir'), formatNumber(s.organizations, nf), s.organizations_last, false],
    [t('sync.users'), t('sync.appToSentral'), formatNumber(s.users, nf), s.users_last, false],
    [t('sync.subs'), t('sync.subsDir'), formatNumber(s.subscriptions, nf), s.subscriptions_last, false],
    [t('sync.usage'), t('sync.appToSentral'), t('sync.perDay', { count: formatNumber(s.usage_events_24h, nf) }), s.usage_last, true],
  ]

  const test = () => run(() => testConnection(d.key), (r) => { if (r.ok) flash(t('testOk', { name: d.name, ms: formatNumber(r.ms, nf) })) }, { refresh: false })

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={k.card}>
        <div className={k.head}>
          <b className="text-14">{t('connTitle', { name: d.name })}</b>
          <button type="button" disabled={pending || !c} onClick={test} className={k.btn}>{t('test')}</button>
        </div>
        {conn.map(([label, value, mono]) => (
          <div key={label} className={`${k.row} flex justify-between gap-[10px] py-[9px]`}>
            <span className="text-muted">{label}</span>
            <b className={`text-right ${mono ? `${k.mono} text-12` : 'text-12.5'} break-all`}>{value}</b>
          </div>
        ))}
        {c && c.last_ping_at ? (
          <div className={`${k.row} py-[9px] ${c.last_ping_ok ? 'text-muted' : 'font-semibold text-danger'}`}>
            {c.last_ping_ok ? t('lastPingOk', { ago: ago(c.last_ping_at), ms: c.last_ping_ms ?? 0 }) : t('lastPingFailed', { ago: ago(c.last_ping_at) })}
          </div>
        ) : null}
      </div>

      <div className={k.card}>
        <div className={`${k.head} flex-wrap`}>
          <b className="text-14">{t('syncTitle', { name: d.name })}</b>
          <span className="text-12 text-muted">{t('syncKey')}</span>
        </div>
        {synced.map(([n, dir, count, last, stream]) => {
          const [st, sc] = state(last, stream)
          return (
            <div key={n} className={`${k.row} grid items-center gap-[10px] py-[9px] [grid-template-columns:minmax(0,1.3fr)_70px_90px_100px] max-sm:[grid-template-columns:minmax(0,1fr)_56px_84px]`}>
              <span className="flex flex-col"><b>{n}</b><span className="text-11.5 text-muted">{dir}</span></span>
              <span>{count}</span>
              <span className="text-muted max-sm:hidden">{ago(last)}</span>
              <span className={`font-bold ${sc}`}>{st}</span>
            </div>
          )
        })}
        <div className={`${k.row} grid items-center gap-[10px] py-[9px] [grid-template-columns:minmax(0,1.3fr)_70px_90px_100px] max-sm:[grid-template-columns:minmax(0,1fr)_56px_84px]`}>
          <span className="flex flex-col"><b>{t('sync.flags')}</b><span className="text-11.5 text-muted">{t('sync.flagsDir')}</span></span>
          <span>—</span>
          <span className="text-muted max-sm:hidden">—</span>
          <span className="font-bold text-muted">{t('sync.notRead')}</span>
        </div>
      </div>

      <div className={k.card}>
        <div className={`${k.head} text-14 font-bold`}>{t('eventsTitle')}</div>
        {d.events.length === 0 ? <div className={k.empty}>{t('noEvents')}</div> : null}
        {d.events.map((e) => (
          <div key={e.kind} className={`${k.row} grid gap-[10px] py-2 [grid-template-columns:minmax(0,1.2fr)_80px_minmax(0,1fr)]`}>
            <span className={`${k.mono} text-12`}>{e.kind}</span>
            <b>{formatNumber(e.count, nf)}</b>
            <span className="text-muted">{e.uses.map((u) => (tu.has(u) ? tu(u) : u)).join(' · ') || '—'}</span>
          </div>
        ))}
        <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('eventsWindow')}</div>
      </div>

      <div className={k.card}>
        <div className={`${k.head} text-14 font-bold`}>{t('actionsTitle')}</div>
        {d.commands.length === 0 ? <div className={k.empty}>{t('noCommands')}</div> : null}
        {d.commands.map((c2) => (
          <div key={c2.command} className={`${k.row} flex justify-between gap-[10px] py-[9px]`}>
            <span className={`${k.mono} text-12 ${c2.allowed ? '' : 'text-faint'}`}>
              {c2.command}{c2.destructive ? <span className="ml-[6px] font-sans text-11 font-bold text-danger">{t('destructive')}</span> : null}
            </span>
            <span className="text-right text-muted">{c2.allowed ? c2.used_by.map((u) => (tu.has(`area.${u}`) ? tu(`area.${u}`) : u)).join(' · ') : t('notInScopes', { scope: c2.scope })}</span>
          </div>
        ))}
        <div className="px-[18px] py-[10px] text-11.5 font-semibold text-danger">{t('firewall')}</div>
      </div>
    </div>
  )
}

function ConnectDialog({ onClose }: { onClose: () => void }) {
  const t = useTranslations('platform.connect')
  const { call, pending, mfa, alert, blocked } = useSensitive()
  const [v, setV] = useState({ name: '', api_url: 'https://', key: '', public_key: '', region: '', description: '', stage: 'ga' as 'ga' | 'beta' })
  const [scopes, setScopes] = useState<string[]>(['orgs:read'])
  const [done, setDone] = useState<{ product: string; code: string; minutes: number } | null>(null)
  const set = (f: keyof typeof v) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setV({ ...v, [f]: e.target.value })
  const submit = () => call(() => connectApplication({ ...v, scopes }), (r) => {
    if (r.ok) setDone({ product: r.product, code: r.intake_code, minutes: Math.round(r.expires_in / 60) })
  })

  if (done) {
    return (
      <Dialog title={t('doneTitle', { product: done.product })} onClose={onClose}>
        <span className="text-12.5 leading-[1.55]">{t('doneBody', { minutes: done.minutes })}</span>
        <OnceValue label={t('intakeCode')} value={done.code} warning={t('onceWarning')} />
        <div className="flex justify-end"><button type="button" onClick={onClose} className={k.dlgConfirm}>{t('done')}</button></div>
      </Dialog>
    )
  }

  const fields: [keyof typeof v, string, string][] = [
    ['name', t('name'), 'Vaktbok'],
    ['api_url', t('baseUrl'), 'https://api.vaktbok.no'],
    ['key', t('key'), 'vaktbok'],
    ['public_key', t('publicKey'), ''],
    ['region', t('region'), ''],
    ['description', t('description'), ''],
  ]
  return (
    <Dialog title={t('title')} onClose={onClose}>
      {fields.map(([f, label, ph]) => (
        <label key={f} className={k.label}>
          {label}
          <input value={v[f]} onChange={set(f)} placeholder={ph} className={`${k.input} ${f === 'api_url' || f === 'key' || f === 'public_key' ? k.mono : ''}`} />
        </label>
      ))}
      <label className={k.label}>
        {t('stage')}
        <select value={v.stage} onChange={set('stage')} className={k.input}>
          <option value="ga">{t('stageGa')}</option>
          <option value="beta">{t('stageBeta')}</option>
        </select>
      </label>
      <div className="text-11.5 font-semibold text-muted">{t('scopes')}</div>
      <div className="flex flex-wrap gap-[5px]">
        {PRODUCT_SCOPES.map((s) => {
          const on = scopes.includes(s)
          return (
            <button key={s} type="button" aria-pressed={on} onClick={() => setScopes(on ? scopes.filter((x) => x !== s) : [...scopes, s])} className={k.chip(on)}>{s}</button>
          )
        })}
      </div>
      <div className="text-12 text-muted">{t('secretsNote')}</div>
      {mfa}
      {alert}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button type="button" disabled={pending || blocked} onClick={submit} className={k.dlgConfirm}>{t('submit')}</button>
      </div>
    </Dialog>
  )
}
