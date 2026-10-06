'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { saveArticle } from '../actions'
import { useLabel } from './lib'
import { matchArticles } from './NewTicketModal'
import { useNewTicket } from './TicketsFrame'
import type { Help } from '@/lib/data/tickets'

const cols = '[grid-template-columns:minmax(0,2fr)_130px_70px_80px_100px_90px]'

/** Help centre (Tickets.dc.html, v.help): articles with 30-day views and deflections, gaps, and the widget preview. */
export function HelpCentre({ help, now, nf, canConfigure, canAdd }: { help: Help; now: string; nf: NumberFormat; canConfigure: boolean; canAdd: boolean }) {
  const t = useTranslations('tickets.help')
  const tc = useTranslations('common')
  const format = useFormatter()
  const cat = useLabel('categories')
  const flash = useToast()
  const openNew = useNewTicket()
  const [q, setQ] = useState(t('widgetSample'))
  const [busy, setBusy] = useState(false)
  const deflected = help.articles.reduce((a, x) => a + x.deflected, 0)
  const titles = help.articles.filter((a) => a.status === 'published').map((a) => a.title)
  const suggest = matchArticles(q, titles)

  async function draft(topic: string, n: number) {
    setBusy(true)
    const r = await saveArticle({ id: null, values: { title: topic } })
    setBusy(false)
    flash(r.ok ? t('drafted', { n }) : tc(`errors.${r.code}`))
  }

  return (
    <div className="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="overflow-x-auto rounded-20 border border-line bg-surface [grid-column:1/-1]">
        <div className="flex min-w-[640px] items-baseline justify-between gap-3 border-b border-line px-[18px] py-[14px]">
          <span className="text-15 font-bold">{t('title')}</span>
          <span className="text-12 text-muted">
            {t.rich('stats', { rate: '—', n: formatNumber(deflected, nf), b: (c) => <b className="text-ink">{c}</b> })}
          </span>
        </div>
        <div className={`grid min-w-[640px] gap-[10px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${cols}`}>
          <span>{t('cols.article')}</span><span>{t('cols.category')}</span><span>{t('cols.views')}</span><span>{t('cols.deflected')}</span><span>{t('cols.updated')}</span><span>{t('cols.status')}</span>
        </div>
        {help.articles.map((a) => (
          <div key={a.id} className={`grid min-w-[640px] items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 ${cols}`}>
            <b>{a.title}</b>
            <span className="text-muted">{a.category_key ? cat(a.category_key) : '—'}</span>
            <span>{formatNumber(a.views, nf)}</span>
            <span>{formatNumber(a.deflected, nf)}</span>
            <span className="text-muted">{format.relativeTime(new Date(a.updated_at), new Date(now))}</span>
            <span className={`font-semibold ${a.status === 'draft' ? 'text-warn-ink' : 'text-link'}`}>{t(`status.${a.status}`)}</span>
          </div>
        ))}
        {!help.articles.length ? <div className="px-[18px] py-6 text-center text-13 text-muted">{t('noArticles')}</div> : null}
      </div>

      <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="mb-1 text-15 font-bold">{t('loopTitle')}</div>
        <div className="mb-3 text-12 text-muted">{t('loopSub')}</div>
        {help.gaps.map((g) => (
          <div key={g.topic} className="flex items-center justify-between gap-2 border-b border-line py-2 text-12.5">
            <span className="flex flex-col"><b>{g.topic}</b><span className="text-11.5 text-muted">{t('gapCount', { n: g.count })}</span></span>
            <button
              type="button"
              disabled={!canConfigure || busy}
              onClick={() => void draft(g.topic, g.count)}
              className="h-7 cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-11.5 font-bold disabled:cursor-default disabled:opacity-60"
            >
              {t('draft')}
            </button>
          </div>
        ))}
        {!help.gaps.length ? <div className="py-2 text-12.5 text-muted">{t('noGaps')}</div> : null}
      </div>

      <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="mb-[10px] text-15 font-bold">{t('widget')}</div>
        <div className="flex flex-col gap-2 rounded-16 border border-line bg-canvas p-3">
          <input aria-label={t('widgetLabel')} value={q} onChange={(e) => setQ(e.target.value)} className="h-9 rounded-10 border border-line bg-surface px-[10px] text-13" />
          <div className="text-11.5 text-muted">{t('suggested')}</div>
          {suggest.map((s) => <div key={s} className="rounded-10 border border-line bg-surface px-[10px] py-2 text-12.5 font-semibold">{s} →</div>)}
          {!suggest.length ? <div className="text-12.5 text-muted">{t('noSuggest')}</div> : null}
          <button
            type="button"
            disabled={!canAdd}
            onClick={() => openNew({ subject: q.trim() })}
            className="h-8 cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent text-12 font-semibold disabled:cursor-default disabled:opacity-60"
          >
            {t('stillNeed')}
          </button>
        </div>
      </div>
    </div>
  )
}
