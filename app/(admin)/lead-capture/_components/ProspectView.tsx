'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { PROSPECT_FILTERS, type ProspectFilter, type ProspectUsage, type SavedFilter } from '@/lib/data/capture-shared'
import { saveProspectFilter } from '../actions'
import { useErr } from './hooks'

const input = 'h-8 rounded-9 border border-line bg-canvas px-[9px] text-12.5 text-ink'
const eyebrow = 'text-10.5 font-bold uppercase tracking-label text-muted'

/**
 * Prospect search (Marketing.dc.html, v.prospect). The prospect database (contact_data) is not connected: the
 * filters can be built and saved, the results and Reveal wait for the provider (D-41), and nothing a provider
 * would return is shown (results are never stored until revealed).
 */
export function ProspectView({ usage, saved, initial, nf }: { usage: ProspectUsage; saved: SavedFilter[]; initial: Partial<Record<ProspectFilter, string>>; nf: NumberFormat }) {
  const t = useTranslations('capture.prospect')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [values, setValues] = useState<Partial<Record<ProspectFilter, string>>>(initial)
  const [naming, setNaming] = useState(false)
  const [name, setName] = useState('')
  const [busy, start] = useTransition()

  const query = () => Object.fromEntries(Object.entries(values).filter(([, v]) => v && v.trim()).map(([k, v]) => [k, v!.trim()]))
  const save = () => start(async () => {
    const r = await saveProspectFilter({ name: name.trim(), query: query() })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('saved'))
    setNaming(false)
    setName('')
    router.refresh()
  })
  const load = (f: SavedFilter) => setValues(Object.fromEntries(Object.entries(f.query).filter(([k, v]) => typeof v === 'string' && k in labels).map(([k, v]) => [k, v as string])))
  const labels: Record<ProspectFilter, string> = {
    title: t('f.title'), department: t('f.department'), location: t('f.location'),
    size: t('f.size'), industry: t('f.industry'), revenue: t('f.revenue'), keyword: t('f.keyword'),
  }
  const field = (k: ProspectFilter) => (
    <label key={k} className="flex flex-col gap-[3px] text-11.5 text-muted">
      {labels[k]}
      <input value={values[k] ?? ''} onChange={(e) => setValues({ ...values, [k]: e.target.value })} placeholder={k === 'keyword' ? undefined : t(`ph.${k}`)} maxLength={200} className={input} />
    </label>
  )
  const credits = usage.limit !== null
    ? t('creditsLeft', { left: formatNumber(Math.max(0, usage.limit - usage.used_month), nf), limit: formatNumber(usage.limit, nf) })
    : t('creditsUsed', { n: formatNumber(usage.used_month, nf) })

  return (
    <div className="grid grid-cols-1 items-start gap-[14px] md:[grid-template-columns:minmax(240px,280px)_minmax(0,1fr)]">
      <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-4 py-[14px]">
        <span className={eyebrow}>{t('person')}</span>
        {PROSPECT_FILTERS.person.map(field)}
        <span className={`${eyebrow} mt-[6px]`}>{t('organization')}</span>
        {PROSPECT_FILTERS.organization.map(field)}
        {naming ? (
          <div className="flex gap-[6px]">
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder={t('filterName')} aria-label={t('filterName')} maxLength={80} className={`${input} min-w-0 flex-1`} />
            <button type="button" disabled={busy || !name.trim()} onClick={save} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50">{t('save')}</button>
          </div>
        ) : (
          <button type="button" onClick={() => setNaming(true)} className="h-8 cursor-pointer rounded-9 border border-ink bg-surface text-12 font-bold">{t('saveFilter')}</button>
        )}
        {saved.length > 0 ? (
          <>
            <span className={`${eyebrow} mt-[6px]`}>{t('savedFilters')}</span>
            <div className="flex flex-wrap gap-[5px]">
              {saved.map((f) => (
                <button key={f.id} type="button" onClick={() => load(f)} className="cursor-pointer rounded-999 border border-line-strong bg-transparent px-[9px] py-[3px] text-11">{f.name}</button>
              ))}
            </div>
          </>
        ) : null}
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap justify-between gap-2 border-0 border-b border-line px-[18px] py-3 text-12.5">
          <b className="text-14">{usage.connected ? t('prospects') : t('notConnectedTitle')}</b>
          <span className="text-muted">{credits} · {t('revealAdds')}</span>
        </div>
        <div className="flex flex-col gap-2 px-[18px] py-6 text-12.5">
          {usage.connected ? (
            <span className="text-muted">{t('adapterPending')}</span>
          ) : (
            <>
              <span className="text-muted">{t('notConnected')}</span>
              <span className="text-faint">{t('revealWaits')}</span>
            </>
          )}
          {usage.contact_rule === 'opt_in_only' ? <span className="font-semibold text-danger">{t('optInOnly')}</span> : null}
          {usage.contact_rule === 'source_and_basis' ? <span className="text-warn-ink">{t('basisRequired')}</span> : null}
          <span className="text-11.5 text-faint">{t('art14')}</span>
        </div>
      </div>
    </div>
  )
}
