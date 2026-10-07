'use client'

import { useEffect, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { ui } from '@/components/ui/styles'
import { Switch } from '@/components/ui/Switch'
import type { Pref, PushState, SyncResult } from '@/lib/data/mobile-shared'
import type { OutboxItem, OutboxKind } from './outbox'
import { pushSupported, type SubscribeFail } from './push'

/**
 * The panels under the phones (spec §6 Q13, D-41): this device's offline sync, the staff member's push devices and their
 * notification types, in the design's card language (Settings and Platform cards).
 */
export type Logged = { key: string; kind: OutboxKind; title: string; result: SyncResult }

function Panel({ eyebrow, title, children }: { eyebrow: string; title: string; children: React.ReactNode }) {
  return (
    <section className={`${ui.cardPad} flex flex-col gap-3`}>
      <div className="flex flex-col gap-1">
        <span className={ui.eyebrow}>{eyebrow}</span>
        <h2 className="m-0 text-15 font-bold">{title}</h2>
      </div>
      {children}
    </section>
  )
}

const STATE_TONE = { applied: 'bg-ok', superseded: 'bg-warn', rejected: 'bg-alert' } as const

export function SyncPanel({ device, offline, outbox, log, syncing, lastPull, onSync }: {
  device: string | null; offline: boolean; outbox: OutboxItem[]; log: Logged[]; syncing: boolean; lastPull: { at: Date; count: number } | null; onSync: () => void
}) {
  const t = useTranslations('mobile.sync')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const outcome = (r: SyncResult) => {
    if (r.result === 'applied') return r.conflict ? t('result.appliedConflict') : r.replayed ? t('result.replayed') : t('result.applied')
    if (r.result === 'superseded') return t('result.superseded')
    if (r.detail === 'missing_fields') return t('result.missingFields')
    return t('result.rejected', { reason: r.error && te.has(r.error) ? te(r.error) : te('failed') })
  }
  return (
    <Panel eyebrow={t('eyebrow')} title={t('title')}>
      <p className="m-0 text-12.5 text-muted">{t('body')}</p>
      <div className="flex flex-wrap items-center justify-between gap-2 text-12.5">
        <span><b>{offline ? t('offline') : t('online')}</b>{device ? ` · ${t('device', { id: device.slice(0, 8) })}` : ''}</span>
        <button type="button" className={`${ui.btnSmall} disabled:cursor-default disabled:opacity-60`} onClick={onSync} disabled={syncing || outbox.length === 0}>{syncing ? t('syncing') : t('syncNow')}</button>
      </div>
      <div className="flex flex-col gap-[6px]">
        <span className={ui.colHead}>{t('waiting', { n: outbox.length })}</span>
        {outbox.length === 0 ? <span className="text-12.5 text-muted">{t('nothingWaiting')}</span> : null}
        {outbox.map((o) => (
          <div key={o.first.mutation_id} className="flex items-baseline justify-between gap-2 text-12.5">
            <span>{t(`kinds.${o.kind}`)} · {o.title}</span>
            <span className="whitespace-nowrap text-11.5 text-muted">{format.dateTime(new Date(o.first.client_at), { hour: '2-digit', minute: '2-digit' })}{o.created_id ? ` · ${t('halfway')}` : ''}</span>
          </div>
        ))}
      </div>
      {log.length ? (
        <div className="flex flex-col gap-[6px]">
          <span className={ui.colHead}>{t('lastSync')}</span>
          {log.map((l) => (
            <div key={l.key} className="flex items-start gap-2 text-12.5">
              <span className={`mt-[5px] h-2 w-2 flex-none rounded-999 ${STATE_TONE[l.result.result]}`} aria-hidden />
              <span className="flex flex-col">
                <span>{t(`kinds.${l.kind}`)} · {l.title}</span>
                <span className="text-12 text-muted">{outcome(l.result)}</span>
              </span>
            </div>
          ))}
        </div>
      ) : null}
      {lastPull ? <span className="text-12 text-muted">{t('pulled', { n: lastPull.count, time: format.dateTime(lastPull.at, { hour: '2-digit', minute: '2-digit' }) })}</span> : null}
    </Panel>
  )
}

/**
 * «Register this browser» works only when push is ready (module, setting, provider key in Vault), the database gives the
 * public key, and the browser can receive push; otherwise the line says which of these is missing (D-41).
 */
export function DevicesPanel({ push, onRevoke, onRegister, registering, problem }: {
  push: PushState | null; onRevoke: (id: string) => void; onRegister: () => void; registering: boolean; problem: SubscribeFail | null
}) {
  const t = useTranslations('mobile.devices')
  const format = useFormatter()
  // the browser's abilities are known only after hydration; the server renders «not yet known» as unsupported
  const [supported, setSupported] = useState(false)
  useEffect(() => setSupported(pushSupported()), [])
  if (!push) return <Panel eyebrow={t('eyebrow')} title={t('title')}><span className="text-12.5 text-danger">{t('failed')}</span></Panel>
  const state = !push.module ? 'moduleOff' : push.setting !== 'on' ? 'settingOff' : !push.push_ready ? 'notConnected' : 'ready'
  return (
    <Panel eyebrow={t('eyebrow')} title={t('title')}>
      <div className="flex items-start gap-2 rounded-14 border border-solid border-line bg-canvas px-3 py-[10px] text-12.5">
        <span className={`mt-[5px] h-2 w-2 flex-none rounded-999 ${state === 'ready' ? 'bg-ok' : 'bg-warn'}`} aria-hidden />
        <span className="flex flex-col gap-[2px]"><b>{t(`state.${state}.t`)}</b><span className="text-muted">{t(`state.${state}.s`)}</span></span>
      </div>
      {push.devices.length === 0 ? <span className="text-12.5 text-muted">{t('none')}</span> : null}
      {push.devices.map((d) => (
        <div key={d.id} className="flex items-center justify-between gap-2 text-12.5">
          <span className="flex flex-col">
            <b>{d.label ?? t('unnamed')}</b>
            <span className="text-12 text-muted">
              {t('added', { date: format.dateTime(new Date(d.created_at), { day: 'numeric', month: 'short', year: 'numeric' }) })}
              {d.last_used_at ? ` · ${t('lastUsed', { date: format.dateTime(new Date(d.last_used_at), { day: 'numeric', month: 'short' }) })}` : ''}
              {d.failures ? ` · ${t('failures', { n: d.failures })}` : ''}
            </span>
          </span>
          <button type="button" className={ui.btnSmall} onClick={() => onRevoke(d.id)}>{t('revoke')}</button>
        </div>
      ))}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={`text-12 ${problem ? 'font-semibold text-danger' : 'text-muted'}`}>
          {problem ? t(`registerProblem.${problem}`)
            : state !== 'ready' ? t('registerWaits')
            : !push.public_key ? t('registerNoKey')
            : !supported ? t('registerUnsupported')
            : t('registerHint')}
        </span>
        <button type="button" className={`${ui.btnSmall} disabled:cursor-default disabled:opacity-60`} onClick={onRegister}
          disabled={state !== 'ready' || !push.public_key || !supported || registering}>
          {registering ? t('registering') : t('register')}
        </button>
      </div>
    </Panel>
  )
}

export function PrefsPanel({ prefs, pushReady, onSet }: { prefs: Pref[] | null; pushReady: boolean; onSet: (kind: Pref['kind'], push: boolean) => void }) {
  const t = useTranslations('mobile.prefs')
  return (
    <Panel eyebrow={t('eyebrow')} title={t('title')}>
      <p className="m-0 text-12.5 text-muted">{pushReady ? t('body') : t('bodyNotConnected')}</p>
      {prefs === null ? <span className="text-12.5 text-danger">{t('failed')}</span> : null}
      <div className="flex flex-col">
        <div className="grid items-center gap-2 border-b border-solid border-line pb-[6px] [grid-template-columns:1fr_60px_60px]">
          <span className={ui.colHead}>{t('kind')}</span>
          <span className={`${ui.colHead} text-center`}>{t('inApp')}</span>
          <span className={`${ui.colHead} text-center`}>{t('push')}</span>
        </div>
        {prefs?.map((p) => (
          <div key={p.kind} className="grid items-center gap-2 border-b border-solid border-line py-2 text-12.5 [grid-template-columns:1fr_60px_60px]">
            <span>{t(`kinds.${p.kind}`)}</span>
            <span className="flex justify-center"><Switch on label={t('inAppLabel', { kind: t(`kinds.${p.kind}`) })} disabled onChange={() => {}} /></span>
            <span className="flex justify-center"><Switch on={p.channels.includes('push')} label={t('pushLabel', { kind: t(`kinds.${p.kind}`) })} onChange={(on) => onSet(p.kind, on)} /></span>
          </div>
        ))}
      </div>
      <span className="text-12 text-muted">{t('reminders')}</span>
    </Panel>
  )
}
