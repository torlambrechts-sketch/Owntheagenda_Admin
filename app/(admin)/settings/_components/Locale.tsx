'use client'

import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { setProfile } from '../actions'
import { k, useRun } from './kit'

const FORMATS: NumberFormat[] = ['space_comma', 'comma_dot', 'dot_comma']

/**
 * Language and currencies (Settings.dc.html, v.locale). Language, time zone and number format are the staff
 * member's own (profile_set, as the account menu). English and bokmål only (D-04). Currencies: the company
 * default only; others wait for stored exchange rates (requests/settings.md).
 */
export function Locale({ me, dateSample, zones }: { me: { locale: 'en' | 'no'; time_zone: string; number_format: NumberFormat }; dateSample: string; zones: string[] }) {
  const t = useTranslations('settings.locale')
  const { run, pending } = useRun()
  // a language switch needs no toast: the whole screen answers in the new language
  const save = (values: Parameters<typeof setProfile>[0]) => run(() => setProfile(values), () => (values.locale ? undefined : t('saved')))
  const rowCls = 'flex items-center justify-between gap-3 border-b border-line py-[6px] text-12.5'
  // the design shows the value in bold; the select keeps that look and only adds its arrow
  const sel = 'max-w-[60%] cursor-pointer border-none bg-transparent p-0 text-right text-12.5 font-bold text-ink [text-align-last:right] disabled:cursor-default'

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('title')}</b>
        <div className="flex rounded-10 bg-tile p-[3px]" role="group" aria-label={t('title')}>
          {(['en', 'no'] as const).map((l) => (
            <button
              key={l}
              type="button"
              aria-pressed={me.locale === l}
              disabled={pending}
              onClick={() => me.locale !== l && save({ locale: l })}
              className={`flex-1 cursor-pointer rounded-7 border-none p-[7px] text-12.5 text-ink ${me.locale === l ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
            >
              {t(`languages.${l}`)}
            </button>
          ))}
        </div>
        <div className={rowCls}>
          <span className="text-muted">{t('dateFormat')}</span>
          <b>{dateSample}</b>
        </div>
        <label className={rowCls}>
          <span className="text-muted">{t('numberFormat')}</span>
          <select value={me.number_format} disabled={pending} onChange={(e) => save({ number_format: e.target.value as NumberFormat })} className={sel}>
            {FORMATS.map((f) => (
              <option key={f} value={f}>{formatNumber(12345.67, f, 2)}</option>
            ))}
          </select>
        </label>
        <label className={rowCls}>
          <span className="text-muted">{t('timeZone')}</span>
          <select value={me.time_zone} disabled={pending} onChange={(e) => save({ time_zone: e.target.value })} className={sel}>
            {zones.map((z) => (
              <option key={z} value={z}>{z}</option>
            ))}
          </select>
        </label>
        <span className="text-11.5 text-faint">{t('note')}</span>
      </div>
      <div className={k.card}>
        <div className={k.cardHead}>
          <b className="text-14">{t('currencies')}</b>
          <span className="text-12 text-muted">{t('companyDefault')}</span>
        </div>
        <div className="grid gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:60px_minmax(0,1fr)_100px_80px]">
          <b>NOK</b>
          <span>{t('nok')}</span>
          <span className="text-muted">{formatNumber(1, me.number_format, 3)} NOK</span>
          <span className="font-bold text-link">{t('default')}</span>
        </div>
        <div className="flex flex-col items-start gap-[6px] px-[18px] py-[10px]">
          <button type="button" disabled aria-describedby="currency-pending" className={k.dashed}>{t('addCurrency')}</button>
          <span id="currency-pending" className="text-11.5 text-muted">{t('currencyPending')}</span>
        </div>
      </div>
    </div>
  )
}
