'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { StorageState } from '@/lib/data/documents-shared'
import { connectDriveAction, documentSettingAction, storageDefaultAction } from '../actions'
import { useError } from './util'

type Row = { key: 'platform' | 'google' | 'onedrive' | 'sharepoint'; drive: 'google' | 'microsoft' | null }
const ROWS: Row[] = [{ key: 'platform', drive: null }, { key: 'google', drive: 'google' }, { key: 'onedrive', drive: 'microsoft' }, { key: 'sharepoint', drive: 'microsoft' }]

/**
 * Storage and branding (DOC-03, DOC-06): where new documents are stored (the platform until a drive is connected),
 * the platform's branding on documents and signing pages, and the e-signature service. The company default,
 * branding and the service need Global › configure; connecting one's own drive is anyone's.
 */
export function StorageTab({ storage, error, onChanged }: { storage: StorageState | null; error: string | null; onChanged: () => void }) {
  const t = useTranslations('documents.settings')
  const ts = useTranslations('documents.storage')
  const flash = useToast()
  const err = useError()
  const [busy, setBusy] = useState(false)
  if (!storage) return <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-13 text-muted">{err({ code: error ?? 'failed' })}</div>

  const may = storage.can_configure
  const conn = (d: Row['drive']) => storage.connections.find((c) => c.provider === d && c.status === 'connected') ?? null
  const isDefault = (k: Row['key']) => storage.default.provider === k
  const label = typeof storage.default.location.label === 'string' ? storage.default.location.label : ''

  async function pick(r: Row) {
    if (isDefault(r.key)) return
    setBusy(true)
    const c = r.drive ? conn(r.drive) : null
    const res = r.drive && !c
      ? await connectDriveAction(r.drive)
      : may ? await storageDefaultAction({ provider: r.key, location: r.drive ? { kind: 'personal', label: '' } : null }) : { ok: false as const, code: 'forbidden' }
    setBusy(false)
    if (!res.ok) return flash(err(res))
    flash(t('defaultSet', { where: ts(r.key === 'platform' ? 'platformLong' : r.key) }))
    onChanged()
  }
  async function setting(key: 'doc_branding' | 'esign_service', value: string) {
    setBusy(true)
    const r = await documentSettingAction({ key, value })
    setBusy(false)
    if (!r.ok) return flash(err(r))
    onChanged()
  }

  const describe = (r: Row) => {
    if (!r.drive) return t('platformDesc')
    const c = conn(r.drive)
    if (!c) return t('notConnected')
    return r.key === 'google' ? t('connectedAs', { email: c.account_email ?? '' }) : r.key === 'onedrive' ? t('connectedMs', { email: c.account_email ?? '' }) : t('sharepointDesc')
  }
  const state = (r: Row) => (isDefault(r.key) ? t('default') : r.drive && !conn(r.drive) ? t('connect') : t('available'))
  const branded = storage.branding === 'hidden'

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('cloud')}</b>
        {ROWS.map((r) => (
          <button key={r.key} type="button" aria-pressed={isDefault(r.key)} onClick={() => pick(r)} disabled={busy || (!r.drive && !may) || (!!r.drive && !!conn(r.drive) && !may)}
            className={`flex cursor-pointer items-center justify-between gap-3 rounded-13 border px-[13px] py-[11px] text-left disabled:cursor-default ${isDefault(r.key) ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}>
            <span className="flex flex-col"><b className="text-13">{ts(r.key === 'platform' ? 'platformLong' : r.key)}</b><span className="text-11.5 text-muted">{describe(r)}</span></span>
            <span className={`text-11.5 font-bold ${isDefault(r.key) ? 'text-link' : 'text-muted'}`}>{state(r)}</span>
          </button>
        ))}
        <label className="flex items-center justify-between gap-3 text-12.5">{t('location')}
          {/* a drive's folders come from its adapter (DOC-03); until one is connected the location is the platform */}
          <select disabled value="current" className="h-[30px] rounded-8 border border-line bg-canvas text-12 disabled:opacity-100">
            <option value="current">{storage.default.provider === 'platform' ? ts('platformLong') : label || t('personal')}</option>
          </select>
        </label>
        {!may ? <span className="text-11.5 text-muted">{t('needConfigure')}</span> : null}
      </div>

      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('branding')}</b>
        <div className="flex items-center justify-between gap-3">
          <span className="flex flex-col text-12.5"><b>{t('removeBranding')}</b><span className="text-11.5 text-muted">{t('removeBrandingDesc')}</span></span>
          <button type="button" role="switch" aria-checked={branded} aria-label={t('removeBranding')} disabled={busy || !may}
            onClick={() => setting('doc_branding', branded ? 'shown' : 'hidden')}
            className={`relative h-[22px] w-10 flex-none cursor-pointer rounded-999 border-none disabled:cursor-default disabled:opacity-60 ${branded ? 'bg-ink' : 'bg-line-strong'}`}>
            <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: branded ? 21 : 3 }} />
          </button>
        </div>
        <div className="flex rounded-10 bg-tile p-[3px]">
          {(['builtin', 'external'] as const).map((k) => (
            <button key={k} type="button" aria-pressed={storage.esign_service === k} disabled={busy || !may} onClick={() => storage.esign_service !== k && setting('esign_service', k)}
              className={`flex-1 cursor-pointer rounded-7 border-none p-[7px] text-12 disabled:cursor-default ${storage.esign_service === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
              {t(`svc.${k}`)}
            </button>
          ))}
        </div>
        <span className="text-11.5 text-muted">{t('svcNote')}</span>
        {storage.esign_service === 'external' && !storage.esign_connected ? <span className="text-11.5 text-rust">{t('esignOff')}</span> : null}
        {storage.esign_service === 'builtin' && !storage.email_connected ? <span className="text-11.5 text-rust">{t('emailOff')}</span> : null}
      </div>
    </div>
  )
}
