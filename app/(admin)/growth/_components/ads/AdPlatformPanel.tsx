'use client'

import { useEffect, useState, useTransition } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { connectionState, missing, type AdProvider, type GrowthAds } from '@/lib/growth/ads'
import { useAgo, useSensitive, k } from '../../../applications/_components/kit'
import { checkAds, connectGoogleAds, connectMeta, disconnectAds, importAds, linkAdAccount, saveLinkedIn, startLinkedIn } from '../../ads-actions'

/**
 * An ad platform's setup and state under Growth › Integrations (0077). The owner gives the credentials (each goes straight
 * to the vault after a fresh second factor), checks them, links each ad account to an application, imports now or
 * disconnects; everybody else sees the state and the accounts. Every code from a platform is said in words.
 */
export function AdPlatformPanel({ provider, d, products }: { provider: AdProvider; d: GrowthAds; products: { key: string; name: string }[] }) {
  const t = useTranslations('simpleGrowth.ads')
  const flash = useToast()
  const ago = useAgo()
  const s = useSensitive()
  const params = useSearchParams()
  const p = d.providers.find((x) => x.provider === provider)!
  const state = connectionState(p)
  const accounts = d.accounts.filter((a) => a.provider === provider)
  const [editing, setEditing] = useState(state === 'none')
  const need = missing(p, !!d.search_console_email)

  // LinkedIn's sign-in comes back here with its outcome
  const oauth = provider === 'linkedin_ads' ? params.get('oauth') : null
  useEffect(() => {
    if (oauth) flash(t(`oauth.${['ok', 'denied', 'failed', 'no_access', 'not_configured'].includes(oauth) ? oauth : 'failed'}`))
  }, [oauth, flash, t])

  const codeText = (c: string | null | undefined) => {
    const code = c ?? 'failed'
    if (code === 'bad_key' || code === 'invalid' || code === 'no_key') return t('codes.bad_key')
    if (code === 'expired') return t('codes.expired')
    if (/^token_/.test(code)) return t('codes.token')
    if (code === 'token_expired' || code === 'not_signed_in') return t('codes.sign_in')
    if (code === 'http_401' || code === 'http_403') return t(`codes.forbidden_${provider}`)
    if (code === 'http_429') return t('codes.rate')
    if (code === 'not_deployed' || code === 'not_connected' || code === 'network') return t('codes.unreachable')
    return t('codes.other', { code })
  }
  type R = { ok: boolean; code?: string; detail?: string | null }
  const act = <T extends R>(fn: () => Promise<T>, okMsg: (r: T) => string, onOk?: () => void) => s.call(async () => {
    const r = await fn()
    if (r.ok) return { ok: true as const, msg: okMsg(r), done: true }
    if (r.code === 'forbidden' && r.detail === 'fresh_mfa') return { ok: false as const, code: r.code, detail: r.detail, msg: '', done: false }
    return { ok: true as const, msg: codeText(r.detail ?? r.code), done: false }
  }, (x) => { flash(x.msg); if (x.done) onOk?.() })

  const stateText = state === 'connected'
    ? (p.last_check_at ? t('state.connectedAgo', { ago: ago(p.last_check_at) }) : t('state.connected'))
    : state === 'error' ? codeText(p.last_error)
    : state === 'stored' ? t('state.stored') : t('state.none')

  return (
    <div className={`${k.cardPad} gap-3`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <b className="text-15">{t(`names.${provider}`)}</b>
        <span className={`text-12 font-bold ${state === 'connected' ? 'text-link' : state === 'error' ? 'text-danger' : 'text-muted'}`}>{stateText}</span>
      </div>
      <span className="text-12.5 leading-[1.5] text-muted">{t(`what.${provider}`)}</span>
      {provider === 'linkedin_ads' && p.token_expires_at ? (
        <span className={k.note}>
          {t('linkedin.tokenUntil', { date: new Date(p.token_expires_at).toISOString().slice(0, 10) })}
          {p.refresh_expires_at ? ` ${t('linkedin.refreshUntil', { date: new Date(p.refresh_expires_at).toISOString().slice(0, 10) })}` : ` ${t('linkedin.noRefresh')}`}
        </span>
      ) : null}

      {d.can_manage ? (
        editing ? (
          <SetupForm provider={provider} d={d} p={p} act={act} onDone={() => setEditing(false)} onCancel={state === 'none' ? null : () => setEditing(false)} />
        ) : (
          <>
            {need.length ? <span className="text-12 text-warn-ink">{t('needs', { what: need.map((x) => t(`missing.${x}`)).join(', ') })}</span> : null}
            <div className="flex flex-wrap gap-2">
              <button type="button" disabled={s.pending || need.length > 0} onClick={() => act(() => checkAds(provider), (r) => t('checked', { n: 'accounts' in r ? r.accounts : 0 }))} className={k.btn}>{t('check')}</button>
              <button type="button" disabled={s.pending || state !== 'connected' || !accounts.some((a) => a.product)} onClick={() => act(() => importAds(provider), (r) => t('imported', { rows: 'rows' in r ? r.rows : 0 }))} className={k.btn}>{t('importNow')}</button>
              <button type="button" onClick={() => setEditing(true)} className={k.btnSoft}>{t('change')}</button>
              <button type="button" disabled={s.pending || state === 'none'} onClick={() => act(() => disconnectAds(provider), () => t('disconnected'))} className={k.btnSoft}>{t('disconnect')}</button>
            </div>
          </>
        )
      ) : <span className={k.note}>{t('ownerOnly')}</span>}
      {provider === 'linkedin_ads' && d.can_manage && !editing ? <LinkedInGo disabled={s.pending || !p.client_id || !p.stored.includes('linkedin_ads_client_secret')} /> : null}
      {s.mfa}{s.alert}

      <div className="flex flex-col">
        <span className="text-11 font-bold uppercase tracking-[.1em] text-muted">{t('accounts')}</span>
        {!accounts.length ? <span className="py-2 text-12.5 text-muted">{state === 'connected' ? t('noAccounts') : t('accountsAfter')}</span> : null}
        {accounts.map((a) => (
          <div key={a.id} className="flex flex-wrap items-center gap-3 border-b border-line py-[9px] text-12.5 last:border-b-0">
            <span className="flex min-w-0 flex-1 flex-col">
              <b className="[overflow-wrap:anywhere]">{a.name}</b>
              <span className="text-11.5 text-muted">
                <span className={k.mono}>{a.external_id}</span>
                {a.currency ? ` · ${a.currency}` : ''}
                {a.manager ? ` · ${t('manager')}` : a.last_import_at ? ` · ${t('lastImport', { ago: ago(a.last_import_at), n: a.campaigns })}` : ''}
                {a.currency && a.currency !== 'NOK' ? ` · ${t('notNok')}` : ''}
              </span>
              {a.last_error ? <span className="text-11.5 font-semibold text-danger">{codeText(a.last_error)}</span> : null}
            </span>
            {a.manager ? null : d.can_manage ? (
              <AccountLink account={a.id} value={a.product} products={products} label={t('countsFor', { name: a.name })} none={t('noApplication')} />
            ) : <span className="text-12 text-muted">{products.find((x) => x.key === a.product)?.name ?? t('noApplication')}</span>}
          </div>
        ))}
      </div>
    </div>
  )
}

/** «Sign in with LinkedIn»: a one-time state from the database, then LinkedIn's own page */
function LinkedInGo({ disabled }: { disabled: boolean }) {
  const t = useTranslations('simpleGrowth.ads')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [pending, start] = useTransition()
  return (
    <div className="flex flex-col gap-1">
      <button type="button" disabled={disabled || pending} className={`${k.dlgConfirm} self-start`}
        onClick={() => start(async () => {
          const r = await startLinkedIn()
          if (r.ok) { window.location.assign(r.url); return }
          flash(r.code === 'forbidden' && r.detail === 'fresh_mfa' ? t('freshMfa') : te(r.code as 'invalid'))
        })}>
        {t('linkedin.signIn')}
      </button>
      <span className={k.note}>{t('linkedin.signInNote')}</span>
    </div>
  )
}

function AccountLink({ account, value, products, label, none }: { account: string; value: string | null; products: { key: string; name: string }[]; label: string; none: string }) {
  const te = useTranslations('common.errors')
  const t = useTranslations('simpleGrowth.ads')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <select value={value ?? ''} disabled={pending} aria-label={label}
      onChange={(e) => start(async () => {
        const r = await linkAdAccount({ account, product: e.target.value || null })
        if (!r.ok) { flash(te(r.code as 'invalid')); return }
        flash(t('linked'))
        router.refresh()
      })}
      className="h-[30px] max-w-[220px] rounded-9 border border-line bg-canvas px-2 text-12.5">
      <option value="">{none}</option>
      {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
    </select>
  )
}

type Act = <T extends { ok: boolean; code?: string; detail?: string | null }>(fn: () => Promise<T>, okMsg: (r: T) => string, onOk?: () => void) => void

/** the credentials a platform needs, with the steps that give Sentral access; a stored value is left as it is when its field is empty */
function SetupForm({ provider, d, p, act, onDone, onCancel }: {
  provider: AdProvider; d: GrowthAds; p: GrowthAds['providers'][number]; act: Act; onDone: () => void; onCancel: (() => void) | null
}) {
  const t = useTranslations('simpleGrowth.ads')
  const [a, setA] = useState('')
  const [b, setB] = useState(provider === 'google_ads' ? (p.login_customer_id ?? '') : provider === 'linkedin_ads' ? (p.client_id ?? '') : '')
  const [key, setKey] = useState('')
  const [source, setSource] = useState<'own' | 'search_console'>(p.key_source === 'search_console' || (!p.stored.includes('google_ads_key') && d.search_console_email) ? 'search_console' : 'own')
  const has = (n: string) => p.stored.includes(n)
  const stored = t('form.stored')
  const steps = (n: number, values: Record<string, string> = {}) => (
    <ol className="m-0 flex list-decimal flex-col gap-1 pl-5 text-12.5 text-muted [overflow-wrap:anywhere]">
      {Array.from({ length: n }, (_, i) => <li key={i}>{t(`steps.${provider}.${i + 1}`, values)}</li>)}
    </ol>
  )
  const field = `${k.input} ${k.mono} text-12.5`
  if (provider === 'google_ads') {
    const email = source === 'search_console' ? d.search_console_email : (p.client_email ?? null)
    const ready = (a.trim() || has('google_ads_developer_token')) && (source === 'search_console' ? !!d.search_console_email : (key.trim() || has('google_ads_key')))
    return (
      <div className="flex flex-col gap-2">
        {steps(4, { email: email ?? t('form.theServiceAccount') })}
        <label className={k.label}>{t('form.developerToken')}
          <input type="password" value={a} onChange={(e) => setA(e.target.value)} autoComplete="off" placeholder={has('google_ads_developer_token') ? stored : ''} className={field} />
        </label>
        <label className={k.label}>{t('form.managerId')}
          <input value={b} onChange={(e) => setB(e.target.value)} inputMode="numeric" placeholder="123-456-7890" className={`${field} max-w-[220px]`} />
        </label>
        <fieldset className="m-0 flex flex-col gap-1 border-none p-0">
          <legend className="mb-1 text-11.5 font-semibold text-muted">{t('form.serviceAccount')}</legend>
          <label className="flex items-center gap-2 text-12.5">
            <input type="radio" name="key_source" checked={source === 'search_console'} disabled={!d.search_console_email} onChange={() => setSource('search_console')} />
            {d.search_console_email ? t('form.useSearchConsole', { email: d.search_console_email }) : t('form.noSearchConsole')}
          </label>
          <label className="flex items-center gap-2 text-12.5">
            <input type="radio" name="key_source" checked={source === 'own'} onChange={() => setSource('own')} />{t('form.ownKey')}
          </label>
        </fieldset>
        {source === 'own' ? (
          <textarea value={key} onChange={(e) => setKey(e.target.value)} rows={4} spellCheck={false} autoComplete="off" aria-label={t('form.ownKey')}
            placeholder={has('google_ads_key') ? stored : '{"type": "service_account", …}'} className={`${k.input} h-auto py-2 ${k.mono} text-12`} />
        ) : null}
        <Buttons ready={!!ready} label={t('form.connect')} onCancel={onCancel}
          onGo={() => act(() => connectGoogleAds({ developerToken: a.trim() || null, loginCustomerId: b, keySource: source, key: source === 'own' && key.trim() ? key.trim() : null }),
            (r) => t('checked', { n: 'accounts' in r ? (r as { accounts: number }).accounts : 0 }), () => { setA(''); setKey(''); onDone() })} />
      </div>
    )
  }
  if (provider === 'linkedin_ads') {
    return (
      <div className="flex flex-col gap-2">
        {steps(4, { redirect: d.oauth_redirect ?? '—' })}
        {d.oauth_redirect ? <code className={`break-all rounded-10 border border-line bg-canvas px-3 py-2 text-11.5 ${k.mono}`}>{d.oauth_redirect}</code> : null}
        <label className={k.label}>{t('form.clientId')}
          <input value={b} onChange={(e) => setB(e.target.value)} autoComplete="off" className={`${field} max-w-[320px]`} />
        </label>
        <label className={k.label}>{t('form.clientSecret')}
          <input type="password" value={a} onChange={(e) => setA(e.target.value)} autoComplete="off" placeholder={has('linkedin_ads_client_secret') ? stored : ''} className={field} />
        </label>
        <Buttons ready={!!b.trim() && (!!a.trim() || has('linkedin_ads_client_secret'))} label={t('form.save')} onCancel={onCancel}
          onGo={() => act(() => saveLinkedIn({ clientId: b.trim(), clientSecret: a.trim() || null }), () => t('saved'), () => { setA(''); onDone() })} />
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-2">
      {steps(4)}
      <label className={k.label}>{t('form.systemToken')}
        <input type="password" value={a} onChange={(e) => setA(e.target.value)} autoComplete="off" placeholder={has('meta_ads_token') ? stored : ''} className={field} />
      </label>
      <label className={k.label}>{t('form.appSecret')}
        <input type="password" value={b} onChange={(e) => setB(e.target.value)} autoComplete="off" placeholder={has('meta_ads_app_secret') ? stored : t('form.optional')} className={field} />
      </label>
      <Buttons ready={!!a.trim() || has('meta_ads_token')} label={t('form.connect')} onCancel={onCancel}
        onGo={() => act(() => connectMeta({ token: a.trim() || null, appSecret: b.trim() || null }),
          (r) => t('checked', { n: 'accounts' in r ? (r as { accounts: number }).accounts : 0 }), () => { setA(''); setB(''); onDone() })} />
    </div>
  )
}

function Buttons({ ready, label, onGo, onCancel }: { ready: boolean; label: string; onGo: () => void; onCancel: (() => void) | null }) {
  const t = useTranslations('simpleGrowth.ads')
  return (
    <div className="flex flex-wrap gap-2">
      <button type="button" disabled={!ready} onClick={onGo} className={k.dlgConfirm}>{label}</button>
      {onCancel ? <button type="button" onClick={onCancel} className={k.dlgCancel}>{t('form.cancel')}</button> : null}
    </div>
  )
}
