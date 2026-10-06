'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'

const PROMPTS = ['winRate', 'dealSize', 'activities', 'campaigns'] as const

/**
 * Ask for a report (design: v.ai). The model call goes through the AI gateway, which is not configured
 * (phase 7, a Claude key), so the screen shows that state: the description can be written, nothing is
 * generated, and no canned answer or definition is shown.
 */
export function AskAi() {
  const t = useTranslations('insights.ai')
  const [q, setQ] = useState(() => t('example'))
  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(0,1fr)_minmax(0,1.2fr)]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-15">{t('describe')}</b>
        <textarea value={q} onChange={(e) => setQ(e.target.value)} aria-label={t('describe')}
          className="min-h-[90px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 leading-[1.5]" />
        <div className="flex flex-wrap gap-[6px]">
          {PROMPTS.map((p) => (
            <button key={p} type="button" onClick={() => setQ(t(`prompts.${p}`))} className="cursor-pointer rounded-999 border border-line-strong bg-transparent px-[11px] py-[6px] text-12">{t(`prompts.${p}`)}</button>
          ))}
        </div>
        <button type="button" disabled title={t('notConfiguredShort')} className="h-[38px] cursor-default rounded-11 border border-ink bg-ink text-13 font-bold text-canvas opacity-55">{t('generate')}</button>
        <div role="note" className="rounded-12 bg-canvas px-[11px] py-[9px] text-12.5 leading-[1.5]">{t('notConfigured')}</div>
        <input disabled placeholder={t('refine')} aria-label={t('refine')} className="h-9 rounded-10 border border-line bg-canvas px-[11px] text-12.5 disabled:opacity-55" />
      </div>
      <div className="flex flex-col gap-[10px] rounded-20 border border-ink bg-surface px-[18px] py-4">
        <span className="text-10.5 font-bold uppercase tracking-label text-muted">{t('generated')}</span>
        <div className="border-b border-line py-[7px] text-12.5 text-muted">{t('nothingYet')}</div>
        <div className="flex gap-2">
          <button type="button" disabled title={t('notConfiguredShort')} className="h-[34px] cursor-default rounded-10 border border-ink bg-primary px-[13px] text-12.5 font-bold opacity-55">{t('openInBuilder')}</button>
          <button type="button" disabled title={t('notConfiguredShort')} className="h-[34px] cursor-default rounded-10 border border-line bg-transparent px-[13px] text-12.5 font-semibold opacity-55">{t('saveAsIs')}</button>
        </div>
      </div>
    </div>
  )
}
