'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { useAgo, useSensitive, k } from '../../applications/_components/kit'
import { checkSearchConsole, connectSearchConsole, disconnectSearchConsole, importSearchConsole } from '../search-console-actions'

type Sc = Seo['search_console']

/**
 * Search Console on Growth › SEO (0064). Not connected: the owner pastes a service account's JSON key (after a fresh second
 * factor; it goes straight to the vault) and the three steps that give the account access; others read who may. Connected:
 * the site's property and the last import, or why there is none, and for the owner Check again, Fetch now, Replace key and
 * Disconnect. Every code from Google is said in words, never shown as Google wrote it.
 */
export function SearchConsoleCard({ sc, site, app, connected }: { sc: Sc; site: string | null; app: string; connected: boolean }) {
  const t = useTranslations('simpleGrowth.seo')
  const ago = useAgo()
  const flash = useToast()
  const s = useSensitive()
  const [key, setKey] = useState('')
  const [editing, setEditing] = useState(false)
  const codeText = (c: string | null | undefined) => {
    const code = c ?? 'failed'
    if (code === 'bad_key' || code === 'invalid') return t('searchConsole.codes.bad_key')
    if (/^token_/.test(code)) return t('searchConsole.codes.token')
    if (code === 'http_403' || code === 'http_401') return t('searchConsole.codes.http_403')
    if (code === 'expired') return t('searchConsole.codes.expired')
    if (code === 'not_deployed' || code === 'not_connected' || code === 'network') return t('searchConsole.codes.unreachable')
    return t('searchConsole.codes.other', { code })
  }
  const keyOk = (() => {
    try {
      const j = JSON.parse(key) as Record<string, unknown>
      return j.type === 'service_account' && typeof j.client_email === 'string' && typeof j.private_key === 'string'
    } catch {
      return false
    }
  })()
  // every refusal but the fresh second factor is said here in words; the second factor goes to useSensitive's own step
  type R = { ok: boolean; code?: string; detail?: string | null }
  const act = <T extends R>(fn: () => Promise<T>, okMsg: (r: T) => string, onOk?: () => void) => s.call(async () => {
    const r = await fn()
    if (r.ok) return { ok: true as const, msg: okMsg(r), done: true }
    if (r.code === 'forbidden' && r.detail === 'fresh_mfa') return { ok: false as const, code: r.code, detail: r.detail, msg: '', done: false }
    return { ok: true as const, msg: codeText(r.detail ?? r.code), done: false }
  }, (x) => { flash(x.msg); if (x.done) onOk?.() })

  const connect = () => act(() => connectSearchConsole({ key }), (r) => (r.ok ? t('connect.connected', { mapped: r.mapped, sites: r.sites, rows: r.rows }) : ''),
    () => { setKey(''); setEditing(false) })

  const form = (
    <div className="flex flex-col gap-2">
      <ol className="m-0 flex list-decimal flex-col gap-1 pl-5 text-12.5 text-muted">
        <li>{t('connect.step1')}</li>
        <li>{t('connect.step2')}</li>
        <li>{t('connect.step3', { site: site ?? app })}{sc.client_email ? <> <b className={`${k.mono} text-ink`}>{sc.client_email}</b></> : null}</li>
      </ol>
      <label className={k.label}>
        {t('connect.keyLabel')}
        <textarea value={key} onChange={(e) => setKey(e.target.value)} rows={5} spellCheck={false} autoComplete="off"
          placeholder='{"type": "service_account", …}' className={`${k.input} h-auto py-2 ${k.mono} text-12`} />
      </label>
      <span className={k.note}>{key && !keyOk ? t('connect.badKey') : t('connect.keyNote')}</span>
      {s.mfa}{s.alert}
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={!keyOk || s.pending || s.blocked} onClick={connect} className={k.dlgConfirm}>{t('connect.button')}</button>
        {editing ? <button type="button" onClick={() => { setEditing(false); setKey('') }} className={k.dlgCancel}>{t('connect.cancel')}</button> : null}
      </div>
    </div>
  )

  if (!connected) {
    return (
      <div className="flex flex-col gap-3 rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-[18px]">
        <div>
          <b className="text-15">{t('connect.title')}</b>
          <div className="mt-1 text-12.5 text-muted">{site ? t('connect.body', { site }) : t('connect.noSite', { app })}</div>
          {sc.status === 'error' && sc.last_error ? <div role="alert" className="mt-1 text-12.5 font-semibold text-danger">{codeText(sc.last_error)}</div> : null}
        </div>
        {!site ? null : sc.can_manage ? form : <div className="text-11.5 text-muted">{t('connect.ownerOnly')}</div>}
      </div>
    )
  }

  return (
    <div className={`${k.cardPad} gap-2`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <b className="text-14">{t('searchConsole.title')}</b>
        {sc.property ? <span className={`${k.mono} text-12 text-muted`}>{t('searchConsole.property', { property: sc.property })}</span> : null}
      </div>
      <div className="text-12.5 text-muted">
        {!sc.property
          ? t('searchConsole.noProperty', { email: sc.client_email ?? '—', site: site ?? app })
          : sc.site_error ? codeText(sc.site_error)
          : sc.last_import_at ? t('searchConsole.lastImport', { ago: ago(sc.last_import_at) }) : t('searchConsole.neverImported')}
      </div>
      {sc.can_manage ? (
        editing ? form : (
          <>
            {s.mfa}{s.alert}
            <div className="flex flex-wrap gap-2">
              <button type="button" disabled={s.pending} onClick={() => act(checkSearchConsole, (r) => (r.ok ? t('searchConsole.checked', { mapped: r.mapped, rows: r.rows }) : ''))} className={k.btn}>{t('searchConsole.check')}</button>
              <button type="button" disabled={s.pending || !sc.property} onClick={() => act(importSearchConsole, (r) => (r.ok ? t('searchConsole.imported', { rows: r.rows }) : ''))} className={k.btn}>{t('searchConsole.importNow')}</button>
              <button type="button" onClick={() => setEditing(true)} className={k.btnSoft}>{t('searchConsole.replaceKey')}</button>
              <button type="button" disabled={s.pending} onClick={() => act(disconnectSearchConsole, () => t('searchConsole.disconnected'))} className={k.btnSoft}>{t('searchConsole.disconnect')}</button>
            </div>
          </>
        )
      ) : null}
    </div>
  )
}
