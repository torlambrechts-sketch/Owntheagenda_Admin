'use client'

import { useState } from 'react'
import { useLocale, useTranslations } from 'next-intl'
import type { TabProps } from './ContactsScreen'

/**
 * Map (Contacts.dc.html, v.map). There is no geocoding yet, so nothing is plotted: the map keeps the
 * design's placeholder tiles, and the panel counts the records per place from their own city and fylke.
 */
export function MapTab({ data }: TabProps) {
  const t = useTranslations('contacts')
  const locale = useLocale()
  const [mode, setMode] = useState<'orgs' | 'people'>('orgs')
  const [country, setCountry] = useState('')
  const [region, setRegion] = useState('')
  const orgs = data.orgs ?? []
  const people = data.people ?? []
  const orgCountry = Object.fromEntries(orgs.map((o) => [o.id, o.country]))
  const records = (mode === 'orgs'
    ? orgs.map((o) => ({ city: o.city, fylke: o.fylke, country: o.country }))
    : people.map((p) => ({ city: p.city, fylke: p.fylke, country: p.organization_id ? orgCountry[p.organization_id] ?? null : null })))
  const countries = [...new Set(records.map((r) => r.country).filter(Boolean))] as string[]
  const names = new Intl.DisplayNames([locale], { type: 'region' })
  const inCountry = records.filter((r) => !country || r.country === country)
  const regions = [...new Set(inCountry.map((r) => r.fylke).filter(Boolean))].sort() as string[]
  const shown = inCountry.filter((r) => !region || r.fylke === region)
  const byCity = new Map<string, number>()
  for (const r of shown) if (r.city) byCity.set(r.city, (byCity.get(r.city) ?? 0) + 1)
  const places = [...byCity.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  const placed = places.reduce((a, [, n]) => a + n, 0)
  const select = 'h-[34px] rounded-9 border border-line bg-canvas text-12.5 text-ink'

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(0,1fr)_260px]">
      <div className="relative h-[560px] overflow-hidden rounded-20 border border-line [background:repeating-linear-gradient(135deg,#F7EDD2_0_10px,#FCF6E9_10px_20px)]">
        <span className="absolute left-1/2 top-1/2 max-w-[80%] -translate-x-1/2 -translate-y-1/2 rounded-10 border border-line bg-surface px-3 py-2 text-center text-12 text-muted">{t('map.noProvider')}</span>
        <span className="absolute bottom-3 left-[14px] rounded-6 border border-line bg-surface px-2 py-1 font-mono text-11 text-muted">{t('map.tiles')}</span>
      </div>
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('map.filter')}</b>
        <label className="flex flex-col gap-1 text-12 text-muted">
          {t('map.country')}
          <select value={country} onChange={(e) => { setCountry(e.target.value); setRegion('') }} className={select}>
            <option value="">{t('map.allCountries')}</option>
            {countries.map((c) => <option key={c} value={c}>{names.of(c) ?? c}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-12 text-muted">
          {t('map.region')}
          <select value={region} onChange={(e) => setRegion(e.target.value)} className={select}>
            <option value="">{t('map.allRegions')}</option>
            {regions.map((r) => <option key={r} value={r}>{r}</option>)}
          </select>
        </label>
        <div className="flex rounded-10 bg-tile p-[3px]">
          {(['orgs', 'people'] as const).map((m) => (
            <button key={m} type="button" onClick={() => setMode(m)} aria-pressed={mode === m}
              className={`flex-1 cursor-pointer rounded-7 border-none p-[6px] text-12 ${mode === m ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
              {t(`map.mode.${m}`)}
            </button>
          ))}
        </div>
        <span className="text-12 text-muted">{t('map.count', { count: placed, total: shown.length })}</span>
        {places.length ? (
          <div className="flex flex-col">
            {places.map(([city, n]) => (
              <div key={city} className="flex justify-between border-b border-line py-[6px] text-12.5"><b>{city}</b><span className="text-muted">{n}</span></div>
            ))}
          </div>
        ) : null}
      </div>
    </div>
  )
}
