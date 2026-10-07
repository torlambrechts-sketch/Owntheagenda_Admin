'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { ApiOverview, OauthApp } from '@/lib/data/platform'
import { grantRevoke, oauthAppCreate, oauthAppDisable, tokenCreate, tokenRevoke, tokenRotate } from '../actions'
import { Dialog, OnceValue, k, useAct, useAgo, useSensitive } from './kit'

const METHOD: Record<string, string> = { GET: 'bg-teal-soft', POST: 'bg-highlight', DELETE: 'bg-peach', PATCH: 'bg-lilac' }

type Confirm = { kind: 'token' | 'grant' | 'app'; id: string; name: string }

export function ApiView({ api, oauth, scopes, canConfigure, canSecurity, nf }: { api: ApiOverview; oauth: OauthApp[]; scopes: string[]; canConfigure: boolean; canSecurity: boolean; nf: NumberFormat }) {
  const t = useTranslations('platform.api')
  const ago = useAgo()
  const [all, setAll] = useState(false)
  const [tokenDlg, setTokenDlg] = useState<null | 'create' | 'rotate'>(null)
  const [appDlg, setAppDlg] = useState(false)
  const [confirm, setConfirm] = useState<Confirm | null>(null)
  const rateOn = api.rate.mode !== 'off'
  const endpoints = all ? api.endpoints : api.endpoints.slice(0, 8)
  const total = api.usage.reduce((s, u) => s + u.requests, 0)
  const max = Math.max(0, ...api.usage.map((u) => u.requests))
  const scope = (s: string[]) => (s.includes('*') ? t('fullAsUser') : s.join(', '))
  const apps = oauth.filter((a) => a.kind !== 'mcp' && !a.disabled_at)

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={k.card}>
        <div className={`${k.head} flex-wrap`}>
          <b className="text-14">{t('restTitle')}</b>
          <a href="/api/openapi" download="sentral-openapi.json" className="text-12.5 font-semibold">{t('reference')}</a>
        </div>
        {endpoints.map((e) => (
          <div key={`${e.method} ${e.path}`} className={`${k.row} grid items-center gap-[10px] py-2 text-12 [grid-template-columns:62px_minmax(0,1fr)_70px]`}>
            <span className={`rounded-6 px-[7px] py-[2px] text-center text-10.5 font-bold ${METHOD[e.method] ?? 'bg-tile'}`}>{e.method}</span>
            <span className={`${k.mono} break-all`}>{e.path}</span>
            <span className="text-right text-muted">{rateOn && e.cost !== null ? t('cost', { count: e.cost }) : '—'}</span>
          </div>
        ))}
        {api.endpoints.length > 8 ? (
          <div className={`${k.row} py-2`}>
            <button type="button" onClick={() => setAll(!all)} className="cursor-pointer border-none bg-transparent p-0 text-12.5 font-semibold text-link">
              {all ? t('fewer') : t('allEndpoints', { count: api.endpoints.length })}
            </button>
          </div>
        ) : null}
        <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('footnote')}{rateOn ? '' : ` · ${t('costOff')}`}</div>
      </div>

      <div className="flex flex-col gap-3">
        <div className={k.card}>
          <div className={`${k.head} flex-wrap`}>
            <b className="text-14">{t('tokensTitle')}</b>
            <span className="flex flex-wrap gap-[6px]">
              {canConfigure ? <button type="button" onClick={() => setAppDlg(true)} className={k.btnSoft}>{t('registerApp')}</button> : null}
              <button type="button" onClick={() => setTokenDlg(api.has_token ? 'rotate' : 'create')} className={k.btn}>{api.has_token ? t('rotate') : t('create')}</button>
            </span>
          </div>
          {api.tokens.length + api.grants.length + apps.length === 0 ? <div className={k.empty}>{t('noTokens')}</div> : null}
          {api.tokens.map((x) => (
            <Row key={x.id} name={t('personal', { name: x.staff ?? '—' })} code={x.masked} scope={scope(x.scopes)} last={x.last_used_at ? ago(x.last_used_at) : t('neverUsed')}
              action={x.mine || canSecurity ? () => setConfirm({ kind: 'token', id: x.id, name: x.staff ?? x.name }) : null} label={t('revoke')} />
          ))}
          {api.grants.map((g) => (
            <Row key={g.id} name={t('grant', { app: g.app, name: g.staff ?? '—' })} code={g.client} scope={scope(g.scopes)} last={g.last_used_at ? ago(g.last_used_at) : t('neverUsed')}
              action={g.mine || canSecurity ? () => setConfirm({ kind: 'grant', id: g.id, name: g.app }) : null} label={t('revoke')} />
          ))}
          {apps.map((a) => (
            <Row key={a.id} name={t('app', { app: a.name })} code={`${a.client_id.slice(0, 10)}…`} scope={a.allowed_scopes.join(', ')} last={t('grants', { count: a.grants })}
              action={canConfigure ? () => setConfirm({ kind: 'app', id: a.id, name: a.name }) : null} label={t('disable')} />
          ))}
          <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('tokenNote')}</div>
        </div>

        <div className={`${k.cardPad} gap-2`}>
          <div className="flex justify-between gap-2">
            <b className="text-14">{t('rateTitle')}</b>
            <span className="rounded-999 bg-tile px-[10px] py-[3px] text-11 font-bold">{t(`rate.${api.rate.mode === 'source_values' || api.rate.mode === 'custom' ? api.rate.mode : 'off'}`)}</span>
          </div>
          <span className="text-12.5 leading-[1.55]">{t('rateText')}</span>
          {rateOn && api.rate.budget_day !== null ? (
            <span className="text-12.5 text-ink-2">
              {t('budget', { used: formatNumber(api.rate.used_today ?? 0, nf), budget: formatNumber(api.rate.budget_day, nf), burst: api.rate.burst_token ?? 0 })}
            </span>
          ) : null}
          {max > 0 ? (
            <div className="flex h-[70px] items-end gap-1" aria-hidden="true">
              {api.usage.map((u) => <span key={u.hour} className="flex-1 rounded-t-3 bg-blue-bg" style={{ height: `${Math.max(2, Math.round((u.requests / max) * 100))}%` }} />)}
            </div>
          ) : (
            <div className="flex h-[70px] items-center justify-center rounded-12 bg-canvas text-12 text-muted">{t('noUsage')}</div>
          )}
          <span className="text-11.5 text-muted">{t(api.usage_scope === 'company' ? 'usageCompany' : 'usageMine', { total: formatNumber(total, nf) })}</span>
        </div>
      </div>

      {tokenDlg ? <TokenDialog mode={tokenDlg} onClose={() => setTokenDlg(null)} /> : null}
      {appDlg ? <AppDialog scopes={scopes} onClose={() => setAppDlg(false)} /> : null}
      {confirm ? <ConfirmDialog c={confirm} onClose={() => setConfirm(null)} /> : null}
    </div>
  )
}

function Row({ name, code, scope, last, action, label }: { name: string; code: string; scope: string; last: string; action: (() => void) | null; label: string }) {
  return (
    <div className={`${k.row} grid items-center gap-[10px] py-[9px] [grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)_90px_70px]`}>
      <span className="flex min-w-0 flex-col"><b>{name}</b><span className={`text-11.5 text-muted ${k.mono}`}>{code}</span></span>
      <span className="text-11.5 text-muted">{scope}</span>
      <span className="text-muted">{last}</span>
      {action ? <button type="button" onClick={action} className={k.btnRevoke}>{label}</button> : <span />}
    </div>
  )
}

/** Create or rotate the personal token. The plaintext lives in this dialog's state only and is gone when it closes. */
function TokenDialog({ mode, onClose }: { mode: 'create' | 'rotate'; onClose: () => void }) {
  const t = useTranslations('platform.token')
  const { call, pending, mfa, alert, blocked } = useSensitive()
  const [name, setName] = useState(t('defaultName'))
  const [days, setDays] = useState<'' | '30' | '90' | '365'>('')
  const [once, setOnce] = useState<{ token: string; masked: string } | null>(null)
  const submit = () => {
    if (mode === 'rotate') call(() => tokenRotate(), (r) => { if (r.ok) setOnce({ token: r.token, masked: r.masked }) })
    else call(() => tokenCreate({ name, days: days ? (Number(days) as 30 | 90 | 365) : null }), (r) => { if (r.ok) setOnce({ token: r.token, masked: r.masked }) })
  }
  if (once) {
    return (
      <Dialog title={t('readyTitle')} onClose={onClose}>
        <span className="text-12.5 leading-[1.55]">{t(mode === 'rotate' ? 'rotated' : 'created', { masked: once.masked })}</span>
        <OnceValue label={t('token')} value={once.token} warning={t('onceWarning')} />
        <div className="flex justify-end"><button type="button" onClick={onClose} className={k.dlgConfirm}>{t('done')}</button></div>
      </Dialog>
    )
  }
  return (
    <Dialog title={t(mode === 'rotate' ? 'rotateTitle' : 'createTitle')} onClose={onClose}>
      {mode === 'create' ? (
        <>
          <label className={k.label}>{t('name')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className={k.input} /></label>
          <label className={k.label}>
            {t('expires')}
            <select value={days} onChange={(e) => setDays(e.target.value as typeof days)} className={k.input}>
              <option value="">{t('never')}</option>
              <option value="30">{t('days', { count: 30 })}</option>
              <option value="90">{t('days', { count: 90 })}</option>
              <option value="365">{t('days', { count: 365 })}</option>
            </select>
          </label>
        </>
      ) : null}
      <span className="text-12.5 leading-[1.55]">{t(mode === 'rotate' ? 'rotateBody' : 'createBody')}</span>
      <span className="text-12 text-muted">{t('mfaNote')}</span>
      {mfa}
      {alert}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button type="button" disabled={pending || blocked || (mode === 'create' && !name.trim())} onClick={submit} className={k.dlgConfirm}>{t(mode === 'rotate' ? 'rotateSubmit' : 'createSubmit')}</button>
      </div>
    </Dialog>
  )
}

/** Register an OAuth app (UF-16 step 2): a confidential app's client secret is shown once. The scope chips are app.api_scopes (R-PLATFORM-02). */
function AppDialog({ scopes: offered, onClose }: { scopes: string[]; onClose: () => void }) {
  const t = useTranslations('platform.oauth')
  const { call, pending, mfa, alert, blocked } = useSensitive()
  const [name, setName] = useState('')
  const [kind, setKind] = useState<'integration' | 'extension'>('integration')
  const [uris, setUris] = useState('https://')
  const [scopes, setScopes] = useState<string[]>(offered.includes('deals:read') ? ['deals:read'] : [])
  const [confidential, setConfidential] = useState(true)
  const [done, setDone] = useState<{ client_id: string; client_secret: string | null } | null>(null)
  const submit = () => call(
    () => oauthAppCreate({ name, kind, redirect_uris: uris.split(/\s+/).map((u) => u.trim()).filter(Boolean), allowed_scopes: scopes, confidential }),
    (r) => { if (r.ok) setDone({ client_id: r.client_id, client_secret: r.client_secret }) },
  )
  if (done) {
    return (
      <Dialog title={t('doneTitle', { name })} onClose={onClose}>
        <label className={k.label}>{t('clientId')}<input readOnly value={done.client_id} className={`${k.input} ${k.mono} text-12`} /></label>
        {done.client_secret ? <OnceValue label={t('clientSecret')} value={done.client_secret} warning={t('onceWarning')} /> : <span className="text-12.5">{t('public')}</span>}
        <span className="text-12 text-muted">{t('notConnected')}</span>
        <div className="flex justify-end"><button type="button" onClick={onClose} className={k.dlgConfirm}>{t('done')}</button></div>
      </Dialog>
    )
  }
  return (
    <Dialog title={t('title')} onClose={onClose}>
      <label className={k.label}>{t('name')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className={k.input} /></label>
      <label className={k.label}>
        {t('kind')}
        <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} className={k.input}>
          <option value="integration">{t('kinds.integration')}</option>
          <option value="extension">{t('kinds.extension')}</option>
        </select>
      </label>
      <label className={k.label}>
        {t('redirects')}
        <textarea value={uris} onChange={(e) => setUris(e.target.value)} rows={2} className={`min-h-[60px] rounded-10 border border-line bg-canvas px-[11px] py-[9px] text-12.5 text-ink ${k.mono}`} />
      </label>
      <div className="text-11.5 font-semibold text-muted">{t('scopes')}</div>
      <div className="flex flex-wrap gap-[5px]">
        {offered.map((s) => {
          const on = scopes.includes(s)
          return <button key={s} type="button" aria-pressed={on} onClick={() => setScopes(on ? scopes.filter((x) => x !== s) : [...scopes, s])} className={k.chip(on)}>{s}</button>
        })}
      </div>
      <label className="flex items-center gap-2 text-12.5">
        <input type="checkbox" checked={confidential} onChange={(e) => setConfidential(e.target.checked)} />
        {t('confidential')}
      </label>
      <span className="text-12 text-muted">{t('mfaNote')}</span>
      {mfa}
      {alert}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button type="button" disabled={pending || blocked || !name.trim() || !scopes.length} onClick={submit} className={k.dlgConfirm}>{t('submit')}</button>
      </div>
    </Dialog>
  )
}

/** Revoke a token or a grant, or disable an app: effective at once (INT-02). A token's revocation takes the typed reason when the company asks for one. */
function ConfirmDialog({ c, onClose }: { c: Confirm; onClose: () => void }) {
  const t = useTranslations('platform.revoke')
  const { run, pending, flash } = useAct()
  const [reason, setReason] = useState('')
  const submit = () => {
    const fn = c.kind === 'token' ? () => tokenRevoke({ id: c.id, reason }) : c.kind === 'grant' ? () => grantRevoke(c.id) : () => oauthAppDisable(c.id)
    run(fn, () => { flash(t(`done.${c.kind}`, { name: c.name })); onClose() })
  }
  return (
    <Dialog title={t(`title.${c.kind}`, { name: c.name })} onClose={onClose} width={480}>
      <span className="text-12.5 leading-[1.55]">{t(`body.${c.kind}`)}</span>
      {c.kind === 'token' ? (
        <label className={k.label}>{t('reason')}<input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className={k.input} /></label>
      ) : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button type="button" disabled={pending} onClick={submit} className={k.dlgDanger}>{t(`submit.${c.kind}`)}</button>
      </div>
    </Dialog>
  )
}
