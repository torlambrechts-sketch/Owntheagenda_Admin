'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { requestAccess } from '../actions'
import { useErrorText } from './useErrorText'

type Org = { id: string; name: string; products: { key: string; name: string }[] }
const select = 'h-[38px] rounded-10 border border-line bg-canvas px-[10px] text-13 text-ink'
const lbl = 'flex flex-col gap-[5px] text-12 font-semibold text-muted'

/** «Request access»: the company, the application, 24 or 72 hours and the reason the customer sees. */
export function AccessForm({ orgs, product, allowed }: { orgs: Org[]; product: string; allowed: boolean }) {
  const t = useTranslations('customers.access')
  const err = useErrorText()
  const flash = useToast()
  const [org, setOrg] = useState(orgs[0]?.id ?? '')
  const [app, setApp] = useState('')
  const [hours, setHours] = useState<24 | 72>(24)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  const current = orgs.find((o) => o.id === org)
  const apps = current?.products ?? []
  // the shell's product when the company uses it, else the first application it has
  const chosen = apps.find((a) => a.key === app)?.key ?? apps.find((a) => a.key === product)?.key ?? apps[0]?.key ?? ''

  const send = async () => {
    if (!allowed || busy || !org || !chosen) return
    if (!reason.trim()) return flash(err('reason_required'))
    setBusy(true)
    const r = await requestAccess({ org, product: chosen, hours, reason: reason.trim() })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    setReason('')
    flash(t('sent'))
  }

  return (
    <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-5">
      <div className="text-15 font-bold">{t('request')}</div>
      <label className={lbl}>
        {t('organization')}
        <select value={org} onChange={(e) => { setOrg(e.target.value); setApp('') }} className={select}>
          {orgs.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
      </label>
      {apps.length > 1 ? (
        <label className={lbl}>
          {t('application')}
          <select value={chosen} onChange={(e) => setApp(e.target.value)} className={select}>
            {apps.map((a) => <option key={a.key} value={a.key}>{a.name}</option>)}
          </select>
        </label>
      ) : null}
      <div className="flex gap-[6px]" role="group" aria-label={t('duration')}>
        {([24, 72] as const).map((h) => (
          <button
            key={h}
            type="button"
            aria-pressed={hours === h}
            onClick={() => setHours(h)}
            className={`h-9 flex-1 cursor-pointer rounded-10 border text-12.5 ${hours === h ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-medium'}`}
          >
            {t('hours', { n: h })}
          </button>
        ))}
      </div>
      <label className={lbl}>
        {t('reason')}
        <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} placeholder={t('reasonPlaceholder')} className="min-h-[70px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 text-ink" />
      </label>
      <button
        type="button"
        onClick={send}
        disabled={!allowed || busy || !chosen}
        title={allowed ? undefined : t('noRight')}
        className="h-10 cursor-pointer rounded-11 border border-ink bg-primary text-13 font-bold disabled:cursor-default disabled:opacity-55"
      >
        {t('send')}
      </button>
      <div className="text-12 leading-[1.5] text-muted">{t('note')}</div>
    </div>
  )
}
