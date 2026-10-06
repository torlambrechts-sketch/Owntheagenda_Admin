'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { CHANNELS } from '@/lib/data/analytics-calc'
import { setSpend } from '../actions'

type Spend = { campaign: string; month: string; channel: string | null; amount: number }
const COLS = '[grid-template-columns:minmax(0,1.3fr)_96px_56px_56px_48px_88px]'

/**
 * «Campaigns — spend to paid customers» (Analytics.dc.html, web.campaigns): the spend people entered per
 * campaign and month (analytics_set_spend), editable in place by those who may. Visits, signups and paid per
 * campaign are not returned yet (requests/analytics.md R-7), so those columns read «—».
 */
export function Campaigns({ rows, canEdit, nf, thisMonth, monthLabel }: {
  rows: Spend[]; canEdit: boolean; nf: NumberFormat; thisMonth: string; monthLabel: Record<string, string>
}) {
  const t = useTranslations('analytics')
  const flash = useToast()
  const [pending, start] = useTransition()
  const [draft, setDraft] = useState<{ campaign: string; channel: string; month: string; amount: string }>({ campaign: '', channel: '', month: thisMonth, amount: '' })
  const channel = (c: string | null) => (c ? (t.has(`channels.${c}`) ? t(`channels.${c}`) : c) : t('web.campaigns.noChannel'))
  const te = useTranslations('common.errors')
  // an amount typed in the staff member's number format: group separators dropped, the decimal sign read
  const parse = (s: string) => {
    const [group, dec] = nf === 'comma_dot' ? [',', '.'] : nf === 'dot_comma' ? ['.', ','] : [' ', ',']
    const x = s.replace(/[\s\u00a0\u202f]/g, '').split(group).join('').replace(dec, '.')
    return x === '' ? null : /^\d+(\.\d{0,2})?$/.test(x) ? Number(x) : NaN
  }

  const save = (row: { campaign: string; month: string; channel: string | null }, raw: string, done?: () => void) => {
    const amount = parse(raw)
    if (amount !== null && Number.isNaN(amount)) { flash(te('invalid')); return }
    start(async () => {
      const r = await setSpend({ campaign: row.campaign, month: row.month, amount, channel: (CHANNELS as readonly string[]).includes(row.channel ?? '') ? row.channel as (typeof CHANNELS)[number] : null })
      if (!r.ok) { flash(te(r.code)); return }
      flash(amount === null ? t('web.campaigns.removed') : t('web.campaigns.saved'))
      done?.()
    })
  }

  return (
    <>
      <div className="overflow-x-auto"><div className="min-w-[480px]">
      <div className={`grid gap-2 border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-[.06em] text-muted ${COLS}`}>
        <span>{t('web.campaigns.cols.campaign')}</span><span>{t('web.campaigns.cols.spend')}</span><span>{t('web.campaigns.cols.visits')}</span>
        <span>{t('web.campaigns.cols.signups')}</span><span>{t('web.campaigns.cols.paid')}</span><span>{t('web.campaigns.cols.cpp')}</span>
      </div>
      {rows.map((c) => (
        <div key={`${c.campaign}-${c.month}`} className={`grid items-center gap-2 border-b border-line px-[18px] py-2 text-12.5 tabular-nums ${COLS}`}>
          <span className="flex min-w-0 flex-col">
            <b className="truncate">{c.campaign}</b>
            <span className="text-11 text-muted">{channel(c.channel)} · {monthLabel[c.month] ?? c.month}</span>
          </span>
          {canEdit ? (
            <input
              key={c.amount}
              defaultValue={formatNumber(c.amount, nf, Number.isInteger(c.amount) ? 0 : 2)}
              aria-label={t('web.campaigns.amountLabel', { campaign: c.campaign, month: monthLabel[c.month] ?? c.month })}
              disabled={pending}
              onBlur={(e) => { if (parse(e.currentTarget.value) !== c.amount) save(c, e.currentTarget.value) }}
              onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
              className="h-[30px] w-[90px] rounded-8 border border-line bg-canvas px-2 text-12.5"
            />
          ) : <span>{formatNumber(c.amount, nf, Number.isInteger(c.amount) ? 0 : 2)}</span>}
          <span>—</span><span>—</span><span>—</span><b>—</b>
        </div>
      ))}
      {rows.length === 0 ? (
        <div className="border-b border-line px-[18px] py-4 text-12.5 text-muted">
          {t('web.campaigns.empty')} {canEdit ? t('web.campaigns.prompt') : t('web.campaigns.promptNoRight')}
        </div>
      ) : null}
      </div></div>
      {canEdit ? (
        <form
          className="flex flex-wrap items-center gap-2 px-[18px] py-3"
          onSubmit={(e) => {
            e.preventDefault()
            if (!draft.campaign.trim() || parse(draft.amount) === null || Number.isNaN(parse(draft.amount))) { flash(te('invalid')); return }
            save({ campaign: draft.campaign.trim(), month: draft.month, channel: draft.channel || null }, draft.amount, () => setDraft({ campaign: '', channel: '', month: thisMonth, amount: '' }))
          }}
        >
          <input value={draft.campaign} onChange={(e) => setDraft({ ...draft, campaign: e.target.value })} placeholder={t('web.campaigns.add.campaign')} aria-label={t('web.campaigns.add.campaign')} maxLength={120} className="h-[30px] min-w-[140px] flex-1 rounded-8 border border-line bg-canvas px-2 text-12.5" />
          <select value={draft.channel} onChange={(e) => setDraft({ ...draft, channel: e.target.value })} aria-label={t('web.campaigns.add.channel')} className="h-[30px] rounded-8 border border-line bg-canvas px-1 text-12">
            <option value="">{t('web.campaigns.noChannel')}</option>
            {CHANNELS.map((ch) => <option key={ch} value={ch}>{t(`channels.${ch}`)}</option>)}
          </select>
          <input type="month" value={draft.month} onChange={(e) => setDraft({ ...draft, month: e.target.value })} aria-label={t('web.campaigns.add.month')} className="h-[30px] rounded-8 border border-line bg-canvas px-2 text-12" />
          <input value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} inputMode="decimal" placeholder={t('web.campaigns.add.amount')} aria-label={t('web.campaigns.add.amount')} className="h-[30px] w-[110px] rounded-8 border border-line bg-canvas px-2 text-12.5" />
          <button type="submit" disabled={pending} className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('web.campaigns.add.submit')}</button>
        </form>
      ) : null}
    </>
  )
}
