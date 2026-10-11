'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { useAgo, useSensitive, k } from '../../applications/_components/kit'
import { connectPagespeed, disconnectPagespeed, measurePagespeed } from '../integration-actions'

/**
 * PageSpeed Insights on Growth › Integrations (0073). Not connected: the owner creates a Google API key restricted to the
 * PageSpeed Insights API and pastes it (after a fresh second factor; it goes straight to the vault); the first measurement
 * follows. Connected: when it last measured and how many pages, «Measure now», «Replace key», «Disconnect».
 */
export function PageSpeedPanel({ status, lastError, lastAt, pages, canManage, canMeasure, site }: {
  status: string | null; lastError: string | null; lastAt: string | null; pages: number; canManage: boolean; canMeasure: boolean; site: string | null
}) {
  const t = useTranslations('simpleGrowth.integrations.pagespeed')
  const ago = useAgo()
  const flash = useToast()
  const s = useSensitive()
  const [key, setKey] = useState('')
  const [editing, setEditing] = useState(false)
  const connected = status === 'connected' || status === 'error'
  const code = (c: string | null | undefined) => (c && t.has(`codes.${c}`) ? t(`codes.${c}`) : t('codes.other', { code: c ?? 'failed' }))
  type R = { ok: boolean; code?: string; detail?: string | null }
  const act = <T extends R>(fn: () => Promise<T>, okMsg: (r: T) => string, onOk?: () => void) => s.call(async () => {
    const r = await fn()
    if (r.ok) return { ok: true as const, msg: okMsg(r), done: true }
    if (r.code === 'forbidden' && r.detail === 'fresh_mfa') return { ok: false as const, code: r.code, detail: r.detail, msg: '', done: false }
    return { ok: true as const, msg: code(r.detail ?? r.code), done: false }
  }, (x) => { flash(x.msg); if (x.done) onOk?.() })
  const keyOk = /^[A-Za-z0-9_-]{30,80}$/.test(key.trim())

  const form = (
    <div className="flex flex-col gap-2">
      <ol className="m-0 flex list-decimal flex-col gap-1 pl-5 text-12.5 text-muted">
        <li>{t('step1')}</li>
        <li>{t('step2')}</li>
      </ol>
      <label className="flex flex-col gap-1 text-12 font-semibold text-muted">
        {t('keyLabel')}
        <input type="password" autoComplete="off" value={key} onChange={(e) => setKey(e.target.value)} className={`${k.input} ${k.mono} text-12`} />
      </label>
      <span className="text-11.5 text-muted">{t('keyNote')}</span>
      <div className="flex gap-2">
        <button type="button" disabled={!keyOk || s.pending || s.blocked} onClick={() => act(() => connectPagespeed({ key }), (r) => (r.ok ? t('connected', { pages: r.pages }) : ''), () => { setKey(''); setEditing(false) })}
          className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold">{t('save')}</button>
        {editing ? <button type="button" onClick={() => setEditing(false)} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('cancel')}</button> : null}
      </div>
    </div>
  )

  return (
    <div className="flex flex-col gap-3 rounded-18 border border-line bg-surface px-4 py-[14px]">
      <b className="text-14">{t('title')}</b>
      {connected && !editing ? (
        <>
          <span className="text-12.5 text-muted">
            {lastAt ? t('measured', { ago: ago(lastAt), pages }) : t('notYet')}
            {lastError ? ` · ${code(lastError)}` : ''}
          </span>
          <div className="flex flex-wrap gap-2">
            {canMeasure ? (
              <button type="button" disabled={s.pending} onClick={() => act(() => measurePagespeed({ site }), (r) => (r.ok ? t('measuredNow', { pages: r.pages }) : ''))}
                className="h-8 cursor-pointer rounded-9 border border-ink bg-surface px-3 text-12 font-bold">{s.pending ? t('measuring') : t('measure')}</button>
            ) : null}
            {canManage ? (
              <>
                <button type="button" onClick={() => setEditing(true)} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('replace')}</button>
                <button type="button" disabled={s.pending} onClick={() => act(() => disconnectPagespeed(), () => t('disconnected'))}
                  className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('disconnect')}</button>
              </>
            ) : null}
          </div>
        </>
      ) : canManage ? form : <span className="text-12.5 text-muted">{t('ownerOnly')}</span>}
      {s.mfa}
      {s.alert}
    </div>
  )
}
