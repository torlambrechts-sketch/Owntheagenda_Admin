'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Assist } from '@/lib/data/support-hub'
import { LOCALES, type Locale } from './logic'
import { askArticles } from '../../support-actions'
import { card, label, sectionLabel, useSupportError, Why } from './bits'
import type { ParsedAnswer } from './logic'

const pill = 'rounded-999 bg-tile px-[10px] py-[3px] text-11.5'

/**
 * AI assist (SupportHub.dc.html, v.assist). Ticket text is never sent to Claude (X-V3-2): summary, triage, the draft reply,
 * «Shorter» and «Make article from answer» are disabled with that reason. What is allowed is the answer from published
 * articles, on a question the staff member types; usage comes from ai_calls (V-V3S-14, V-V3S-15).
 */
export function AssistView({ data, product, productName, aiConnected, nf }: { data: Assist; product: string; productName: string; aiConnected: boolean; nf: NumberFormat }) {
  const t = useTranslations('supportHub.assist')
  const dash = useTranslations('common')('dash')
  const router = useRouter()
  const off = t('off')
  const tk = data.ticket
  const usage: [string, string][] = [
    [t('usage.drafts'), `${dash} · ${t('usage.draftsWhy')}`],
    [t('usage.previews'), formatNumber(data.usage.previews, nf)],
    [t('usage.calls'), formatNumber(data.usage.calls, nf)],
    [t('usage.failed'), formatNumber(data.usage.failed, nf)],
  ]
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={`${card} flex flex-col gap-[10px] px-[18px] py-4`}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="min-w-0 text-12 text-muted">
            {tk ? <><b className="text-ink">{tk.ref}</b> · {[tk.subject, tk.organization].filter(Boolean).join(' · ')}</> : t('noTicket')}
          </div>
          {data.tickets.length > 1 ? (
            <select
              value={tk?.id ?? ''}
              aria-label={t('pick')}
              onChange={(e) => router.push(`/customers?tab=support&sub=assist&ticket=${e.target.value}` as never)}
              className="h-[30px] max-w-[220px] rounded-8 border border-line bg-surface text-12 text-ink"
            >
              {data.tickets.map((x) => <option key={x.id} value={x.id}>{`${x.ref} · ${x.subject}`}</option>)}
            </select>
          ) : null}
        </div>
        <div className="rounded-14 bg-ink px-[13px] py-[11px] text-12.5 leading-[1.5] text-canvas"><b className="text-primary">{t('summary')}</b> {t('summaryOff')}</div>
        <div className="flex flex-wrap gap-[6px]">
          <span className={pill} title={off}>{t('category')} <b>{dash}</b></span>
          <span className={pill} title={off}>{t('priority')} <b>{dash}</b></span>
          <span className={pill}>{t('link')} <b>{tk?.problem ?? dash}</b></span>
        </div>
        <span className={sectionLabel}>{t('draftLabel')}</span>
        <textarea disabled placeholder={off} aria-label={t('draftLabel')}
          className="min-h-[150px] cursor-not-allowed rounded-12 border border-line bg-canvas px-3 py-[11px] text-13 leading-[1.55] opacity-70" />
        <div className="flex flex-wrap justify-end gap-2">
          <button type="button" disabled title={off} className="h-[34px] cursor-not-allowed rounded-10 border border-line bg-transparent px-3 text-12.5 font-semibold text-ink opacity-60">{t('shorter')}</button>
          <button type="button" disabled title={off} className="h-[34px] cursor-not-allowed rounded-10 border border-ink bg-surface px-3 text-12.5 font-bold text-ink opacity-60">{t('toArticle')}</button>
          <button type="button" disabled title={off} className="h-[34px] cursor-not-allowed rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink opacity-60">{t('approve')}</button>
        </div>
        <Why className="text-right">{off}</Why>
        <span className="text-11.5 text-faint">{t('footer')}</span>
      </div>
      <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
        <b className="text-15">{t('usage.title')}</b>
        {usage.map(([k, v]) => (
          <div key={k} className="flex justify-between gap-[10px] border-b border-tile py-[5px] text-12.5"><span className="text-muted">{k}</span><b className="text-right">{v}</b></div>
        ))}
      </div>
      <AnswerPreview data={data} product={product} productName={productName} aiConnected={aiConnected} />
    </div>
  )
}

/** the one thing Claude may do here: answer a typed test question from the product's published articles */
function AnswerPreview({ data, product, productName, aiConnected }: { data: Assist; product: string; productName: string; aiConnected: boolean }) {
  const t = useTranslations('supportHub.assist.preview')
  const lt = useTranslations('supportHub.center.langs')
  const errorText = useSupportError()
  const [q, setQ] = useState('')
  const [locale, setLocale] = useState<Locale>('nb')
  const [answer, setAnswer] = useState<ParsedAnswer | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, start] = useTransition()
  const why = !data.can_ask ? t('noRight') : !aiConnected ? t('notConnected') : !data.ai_enabled ? t('off', { product: productName }) : null
  const ask = () => start(async () => {
    setError(null)
    const r = await askArticles({ product, locale, question: q.trim(), titles: data.titles })
    if (r.ok) setAnswer(r.answer)
    else { setAnswer(null); setError(errorText(r.code)) }
  })
  return (
    <div className={`${card} flex flex-col gap-[10px] px-[18px] py-4`}>
      <b className="text-15">{t('title')}</b>
      <span className="text-12 leading-[1.5] text-muted">{t('sub', { product: productName })}</span>
      <div className="flex flex-wrap gap-2">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !why && q.trim().length >= 3) { e.preventDefault(); ask() } }}
          placeholder={t('placeholder')}
          aria-label={t('placeholder')}
          maxLength={500}
          className="h-[38px] min-w-0 flex-[1_1_220px] rounded-10 border border-line bg-canvas px-3 text-13"
        />
        <select value={locale} onChange={(e) => setLocale(e.target.value as Locale)} aria-label={t('lang')} className="h-[38px] rounded-10 border border-line bg-canvas text-12.5 text-ink">
          {LOCALES.map((l) => <option key={l} value={l}>{lt(l)}</option>)}
        </select>
        <button type="button" onClick={ask} disabled={!!why || pending || q.trim().length < 3} title={why ?? undefined}
          className="h-[38px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink disabled:cursor-not-allowed disabled:opacity-60">
          {pending ? t('asking') : t('ask')}
        </button>
      </div>
      {why ? <Why>{why}</Why> : null}
      {error ? <Why className="text-danger">{error}</Why> : null}
      {answer ? (
        <div className="flex flex-col gap-[6px] rounded-13 border border-line bg-canvas px-3 py-[10px]">
          <span className={label}>{t('label')}</span>
          {answer.kind === 'answer' ? (
            <>
              <span className="whitespace-pre-wrap text-12.5 leading-[1.5]">{answer.text}</span>
              <span className="text-11.5 font-semibold text-link">{t('source', { title: answer.source ?? t('noSource') })}</span>
            </>
          ) : <span className="text-12.5">{t('none')}</span>}
        </div>
      ) : null}
    </div>
  )
}
