'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { EmailProvider } from '@/lib/mail/provider'
import { useAct, useAgo, useSensitive, k } from '../../applications/_components/kit'
import { checkBrevo, connectBrevo, disconnectBrevo, saveAppBase, saveMailSettings, saveSender, testBrevo } from '../mail-actions'

const PILL = { connected: 'bg-ok-bg text-ok-ink', not_connected: 'bg-beige text-muted', error: 'bg-peach text-rust-ink' } as const

/**
 * Email (Brevo, 0060): whether Sentral can send, from which address, and what waits. The owner connects with a Brevo API
 * key (handed straight to Vault through secret-intake; never shown again), checks again, sends a test to themselves, and
 * sets the public address links open and the optional reply domain for customers' answers. Sending addresses are the
 * sender domains Brevo has authenticated.
 */
export function EmailCard({ p, apps, current }: { p: EmailProvider; apps: { key: string; name: string }[]; current: string }) {
  const t = useTranslations('simplePlatform.email')
  const ago = useAgo()
  const router = useRouter()
  const { flash, errText } = useAct()
  const s = useSensitive()
  const [pending, start] = useTransition()
  const [key, setKey] = useState('')
  const [editing, setEditing] = useState(!p.key_stored)
  const [base, setBase] = useState(p.public_base ?? '')
  const [inbound, setInbound] = useState(p.inbound_domain ?? '')
  const [appBase, setAppBase] = useState(p.app_bases[current] ?? '')
  const appName = apps.find((a) => a.key === current)?.name ?? current
  // the two link addresses are web addresses of this deployment, never email addresses: said before the server refuses
  const baseOk = !base.trim() || /^https:\/\/[a-z0-9.-]+(:\d+)?\/?$/i.test(base.trim())
  const appBaseOk = !appBase.trim() || /^https:\/\/post\.[a-z0-9.-]+\.[a-z]{2,}\/?$/i.test(appBase.trim())
  const [adding, setAdding] = useState(false)

  const connect = () => s.call(() => connectBrevo({ key }), (r) => {
    setKey('')
    setEditing(false)
    if (r.ok) flash(t('connected', { verified: r.verified, domains: r.domains }))
  })
  const run = (fn: () => Promise<{ ok: boolean }>, ok: string) => start(async () => {
    const r = await fn()
    if (r.ok) { flash(ok); router.refresh() } else flash(failText(r as never))
  })
  const failText = (r: { code: string; detail?: string | null }) =>
    r.code === 'not_connected' && r.detail ? t(`codes.${codeKey(r.detail)}`, { code: r.detail }) : errText(r as never)

  const waiting = p.waiting.tickets + p.waiting.invites + p.waiting.alerts + p.waiting.jobs

  return (
    <div className={`${k.cardPad} gap-3`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <b className="text-14">{t('title')}</b>
        <span className={`rounded-999 px-[10px] py-[3px] text-11 font-bold ${PILL[p.status]}`}>{t(`status.${p.status}`)}</span>
      </div>

      <p className="m-0 text-12.5 text-muted">
        {!p.connected ? t('intro') : p.ready_products.includes(current)
          ? t('readyApp', { app: apps.find((a) => a.key === current)?.name ?? current, address: p.senders.find((d) => d.product === current && d.verified)?.address ?? '' })
          : t('noSenderApp', { app: apps.find((a) => a.key === current)?.name ?? current })}
      </p>

      <dl className="m-0 grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 gap-y-[6px] text-12.5">
        <dt className="text-muted">{t('key')}</dt><dd className="m-0 text-right font-semibold">{p.key_stored ? t('keyStored') : t('keyMissing')}</dd>
        <dt className="text-muted">{t('webhook')}</dt><dd className="m-0 text-right font-semibold">{p.connected ? (p.webhook_ok ? t('yes') : t('no')) : '—'}</dd>
        <dt className="text-muted">{t('lastCheck')}</dt><dd className="m-0 text-right">{ago(p.last_check_at)}{p.last_error ? ` · ${p.last_error}` : ''}</dd>
        <dt className="text-muted">{t('lastRun')}</dt><dd className="m-0 text-right">{ago(p.last_run_at)}</dd>
        <dt className="text-muted">{t('waiting')}</dt><dd className="m-0 text-right">{waiting}{p.failed_24h ? ` · ${t('failed24h', { n: p.failed_24h })}` : ''}</dd>
      </dl>

      {p.can_manage ? (
        <>
          {editing ? (
            <div className="flex flex-col gap-2">
              <label className={k.label}>
                {t('keyLabel')}
                <input
                  type="password"
                  autoComplete="off"
                  spellCheck={false}
                  value={key}
                  onChange={(e) => setKey(e.target.value.trim())}
                  placeholder="xkeysib-…"
                  className={`${k.input} ${k.mono}`}
                />
              </label>
              <span className={k.note}>{t('keyNote')}</span>
              {s.mfa}{s.alert}
              <div className="flex flex-wrap gap-2">
                <button type="button" disabled={key.length < 32 || s.pending || s.blocked} onClick={connect} className={k.dlgConfirm}>{p.key_stored ? t('replace') : t('connect')}</button>
                {p.key_stored ? <button type="button" onClick={() => { setEditing(false); setKey('') }} className={k.dlgCancel}>{t('cancel')}</button> : null}
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              <button type="button" disabled={pending} onClick={() => run(checkBrevo, t('checked'))} className={k.btn}>{t('check')}</button>
              <button type="button" disabled={pending || !p.ready} title={p.ready ? undefined : t('testNeedsSender')} onClick={() => run(testBrevo, t('testSent'))} className={k.btn}>{t('test')}</button>
              <button type="button" onClick={() => setEditing(true)} className={k.btnSoft}>{t('replaceKey')}</button>
              {p.connected ? <button type="button" disabled={pending} onClick={() => s.call(disconnectBrevo, () => flash(t('disconnected')))} className={k.btnSoft}>{t('disconnect')}</button> : null}
            </div>
          )}

          <div className="flex flex-col gap-2 border-t border-line pt-3">
            <label className={k.label}>
              {t('publicBase')}
              <input value={base} onChange={(e) => setBase(e.target.value)} placeholder={p.public_base ?? 'https://…'} aria-invalid={!baseOk} className={`${k.input} ${k.mono}`} />
            </label>
            <span className={baseOk ? k.note : `${k.note} font-semibold text-danger`}>{baseOk ? t('publicBaseNote') : t('publicBaseInvalid')}</span>
            <label className={k.label}>
              {t('inbound')}
              <input value={inbound} onChange={(e) => setInbound(e.target.value)} placeholder={t('inboundPh')} className={`${k.input} ${k.mono}`} />
            </label>
            <span className={k.note}>{p.inbound_domain ? (p.inbound_ok ? t('inboundOk', { domain: p.inbound_domain }) : t('inboundPending', { domain: p.inbound_domain })) : t('inboundNote')}</span>
            <div>
              <button type="button" disabled={pending || !base || !baseOk} onClick={() => run(() => saveMailSettings({ publicBase: base.trim(), inboundDomain: inbound || null }), t('saved'))} className={k.btn}>{t('save')}</button>
            </div>
          </div>

          <div className="flex flex-col gap-2 border-t border-line pt-3">
            <label className={k.label}>
              {t('appBase', { app: appName })}
              <input value={appBase} onChange={(e) => setAppBase(e.target.value)} placeholder="https://post.orgpuls.com" aria-invalid={!appBaseOk} className={`${k.input} ${k.mono}`} />
            </label>
            <span className={appBaseOk ? k.note : `${k.note} font-semibold text-danger`}>
              {appBaseOk ? <>{t('appBaseNote', { app: appName })}{p.app_bases[current] ? '' : ` ${t('appBaseNone', { app: appName })}`}</> : t('appBaseInvalid', { app: appName })}
            </span>
            <div>
              <button type="button" disabled={pending || !appBaseOk || appBase.trim() === (p.app_bases[current] ?? '')} onClick={() => run(() => saveAppBase({ product: current, base: appBase.trim() }), t('saved'))} className={k.btn}>{t('save')}</button>
            </div>
          </div>
        </>
      ) : (
        <span className={k.note}>{t('ownerOnly')}</span>
      )}

      <div className="flex flex-col gap-2 border-t border-line pt-3">
        <div className="flex items-center justify-between gap-2">
          <b className="text-13">{t('senders')}</b>
          {p.can_manage && !adding ? <button type="button" onClick={() => setAdding(true)} className={k.btnSoft}>{t('addSender')}</button> : null}
        </div>
        {p.senders.length === 0 ? <span className={k.note}>{t('noSenders')}</span> : (
          <ul className="m-0 flex list-none flex-col gap-[6px] p-0">
            {p.senders.map((d) => (
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 text-12.5">
                <span className="flex min-w-0 flex-col">
                  <b className={`${k.mono} text-12`}>{d.address}</b>
                  <span className="text-11.5 text-muted">{d.name ?? '—'} · {d.product ? apps.find((a) => a.key === d.product)?.name ?? d.product : t('staffMail')} · {t(`stream.${d.stream}`)}</span>
                </span>
                <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${d.verified ? PILL.connected : d.authenticated ? 'bg-amber-bg text-amber-ink' : PILL.not_connected}`}>
                  {d.verified ? t('verified') : d.authenticated ? t('authenticated') : t('notVerified')}
                </span>
              </li>
            ))}
          </ul>
        )}
        {adding ? <SenderForm apps={apps} current={current} onDone={() => setAdding(false)} /> : null}
        <span className={k.note}>{t('sendersNote')}</span>
      </div>
    </div>
  )
}

function SenderForm({ apps, current, onDone }: { apps: { key: string; name: string }[]; current: string; onDone: () => void }) {
  const t = useTranslations('simplePlatform.email')
  const router = useRouter()
  const { flash, errText } = useAct()
  const [pending, start] = useTransition()
  const [v, setV] = useState({ domain: '', fromLocal: 'support', fromName: apps.find((a) => a.key === current)?.name ?? '', replyTo: '',
    stream: 'transactional' as 'transactional' | 'marketing', postalAddress: '', product: current })
  const set = (key: keyof typeof v) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setV((x) => ({ ...x, [key]: e.target.value }))
  const save = () => start(async () => {
    const r = await saveSender({ ...v, replyTo: v.replyTo || null, postalAddress: v.postalAddress || null, product: v.product || null })
    if (r.ok) { flash(t('senderSaved')); onDone(); router.refresh() } else flash(errText(r as never))
  })
  return (
    <div className="grid gap-2 rounded-12 border border-line p-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,180px),1fr))]">
      <label className={k.label}>{t('f.app')}
        <select value={v.product} onChange={set('product')} className={k.input}>
          {apps.map((a) => <option key={a.key} value={a.key}>{a.name}</option>)}
          <option value="">{t('staffMail')}</option>
        </select>
      </label>
      <label className={k.label}>{t('f.domain')}<input value={v.domain} onChange={set('domain')} placeholder="orgpuls.no" className={k.input} /></label>
      <label className={k.label}>{t('f.fromLocal')}<input value={v.fromLocal} onChange={set('fromLocal')} className={k.input} /></label>
      <label className={k.label}>{t('f.fromName')}<input value={v.fromName} onChange={set('fromName')} placeholder="Orgpuls" className={k.input} /></label>
      <label className={k.label}>{t('f.replyTo')}<input value={v.replyTo} onChange={set('replyTo')} placeholder="support@orgpuls.no" className={k.input} /></label>
      <label className={k.label}>{t('f.stream')}
        <select value={v.stream} onChange={set('stream')} className={k.input}>
          <option value="transactional">{t('stream.transactional')}</option>
          <option value="marketing">{t('stream.marketing')}</option>
        </select>
      </label>
      <label className={k.label}>{t('f.postal')}<input value={v.postalAddress} onChange={set('postalAddress')} className={k.input} /></label>
      <div className="flex gap-2 [grid-column:1/-1]">
        <button type="button" disabled={pending || !v.domain || !v.fromName} onClick={save} className={k.dlgConfirm}>{t('saveSender')}</button>
        <button type="button" onClick={onDone} className={k.dlgCancel}>{t('cancel')}</button>
      </div>
    </div>
  )
}

/** the codes mail-run and secret-intake answer with, as message keys */
function codeKey(code: string): string {
  if (/^http_40[13]$/.test(code)) return 'key_refused'
  if (code === 'not_deployed' || code === 'not_connected') return 'unreachable'
  if (code === 'expired') return 'expired'
  if (code === 'no_sender') return 'no_sender'
  return 'other'
}
