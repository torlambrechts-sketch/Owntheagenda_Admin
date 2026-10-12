'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { SearchHits, Widget } from '@/lib/data/support-hub'
import { askArticles, saveSupportSettings, searchHelp } from '../../support-actions'
import { orgNr } from '../fmt'
import { card, label, Toggle, useSupportError, Why } from './bits'
import { snippetRuns, suggestedFor, type ParsedAnswer } from './logic'

type Mode = 'app' | 'web'

/**
 * Help widget (SupportHub.dc.html, v.widget): an admin preview. The search is real (full text over the product's published
 * bokmål articles), and so is the answer from published articles when Claude is connected (X-V3-2: the staff member's own
 * question and published articles only). Nothing is counted: the widget is not embedded anywhere yet (V-V3S-07).
 */
export function WidgetView({ data, product, productName, aiConnected }: { data: Widget; product: string; productName: string; aiConnected: boolean }) {
  const t = useTranslations('supportHub.widget')
  const [mode, setMode] = useState<Mode>('app')
  const [page, setPage] = useState(data.pages[0] ?? '/')
  const inApp = mode === 'app'
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-[10px]">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex self-start rounded-10 bg-tile p-[3px]" role="group" aria-label={t('modesLabel')}>
            {(['app', 'web'] as const).map((m) => (
              <button
                key={m}
                type="button"
                aria-pressed={mode === m}
                onClick={() => setMode(m)}
                className={`cursor-pointer whitespace-nowrap rounded-7 border-none px-3 py-[6px] text-12.5 text-ink ${mode === m ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
              >
                {t(`modes.${m}`)}
              </button>
            ))}
          </div>
          {inApp && data.pages.length > 0 ? (
            <label className="flex items-center gap-[6px] text-12 text-muted">
              {t('page')}
              <select value={page} onChange={(e) => setPage(e.target.value)} className="h-[30px] rounded-8 border border-line bg-surface text-12 text-ink">
                {data.pages.map((p) => <option key={p} value={p}>{p}</option>)}
              </select>
            </label>
          ) : null}
        </div>
        <Preview data={data} product={product} productName={productName} inApp={inApp} page={page} aiConnected={aiConnected} />
      </div>
      <div className="flex flex-col gap-3">
        <Captured data={data} productName={productName} inApp={inApp} />
        <Settings data={data} product={product} productName={productName} />
      </div>
    </div>
  )
}

function Preview({ data, product, productName, inApp, page, aiConnected }: { data: Widget; product: string; productName: string; inApp: boolean; page: string; aiConnected: boolean }) {
  const t = useTranslations('supportHub.widget')
  const errorText = useSupportError()
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<SearchHits | null>(null)
  const [answer, setAnswer] = useState<ParsedAnswer | null>(null)
  const [askError, setAskError] = useState<string | null>(null)
  const [asking, startAsk] = useTransition()
  const seq = useRef(0)

  // the search runs as one types, a quarter of a second after the last key; the words are never stored
  useEffect(() => {
    const term = q.trim()
    if (term.length < 2) { setHits(null); return }
    const n = ++seq.current
    const timer = setTimeout(async () => {
      const r = await searchHelp({ product, locale: 'nb', q: term })
      if (n === seq.current) setHits(r.ok ? r.hits : [])
    }, 250)
    return () => clearTimeout(timer)
  }, [q, product])

  const askWhy = !data.can_ask ? t('ai.noRight') : !aiConnected ? t('ai.notConnected') : !data.ai_enabled ? t('ai.off', { product: productName }) : null
  const ask = () => {
    const question = q.trim()
    if (askWhy || question.length < 3) return
    setAskError(null)
    startAsk(async () => {
      const r = await askArticles({ product, locale: 'nb', question, titles: data.articles.map((a) => a.title) })
      if (r.ok) setAnswer(r.answer)
      else { setAnswer(null); setAskError(errorText(r.code)) }
    })
  }

  const list = q.trim().length >= 2 ? (hits ?? []).map((h) => ({ id: h.id, title: h.title, snippet: h.snippet }))
    : (inApp ? suggestedFor(page, data.articles) : data.articles.slice(0, 3)).map((a) => ({ id: a.id, title: a.title, snippet: null as string | null }))
  const head = q.trim().length >= 2 ? t('matches') : inApp ? t('sugApp') : t('sugWeb')
  const empty = q.trim().length >= 2 ? (hits === null ? null : t('noMatch')) : inApp ? t('sugEmpty', { page }) : t('noArticles')

  return (
    <div className="flex w-[380px] max-w-full flex-col overflow-hidden rounded-22 border border-ink bg-surface shadow-pop">
      <div className="flex flex-col gap-[3px] bg-ink px-4 py-[14px] text-canvas">
        <b className="text-15">{inApp ? t('greetApp') : t('greetWeb')}</b>
        <span className="text-12 text-line-mid">{inApp ? t('ctxApp', { page }) : t('ctxWeb', { product: productName })}</span>
      </div>
      <div className="flex flex-col gap-[9px] bg-canvas px-[14px] py-3">
        <input
          value={q}
          onChange={(e) => { setQ(e.target.value); setAnswer(null); setAskError(null) }}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); ask() } }}
          placeholder={t('search')}
          aria-label={t('search')}
          className="h-10 rounded-11 border border-line bg-surface px-3 text-13"
        />
        <Why>{askWhy ?? (asking ? t('ai.asking') : t('ai.hint'))}</Why>
        {askError ? <Why className="text-danger">{askError}</Why> : null}
        {answer ? (
          <div className="flex flex-col gap-[6px] rounded-13 border border-line bg-surface px-3 py-[10px]">
            <span className={label}>{t('answer.label')}</span>
            {answer.kind === 'answer' ? (
              <>
                <span className="whitespace-pre-wrap text-12.5 leading-[1.5]">{answer.text}</span>
                <span className="text-11.5 font-semibold text-link">{t('answer.source', { title: answer.source ?? t('answer.noSource') })}</span>
              </>
            ) : <span className="text-12.5 leading-[1.5]">{t('answer.none')}</span>}
            <span className="flex gap-[6px]">
              <button type="button" disabled title={t('answer.why')} className="h-7 cursor-not-allowed rounded-8 border border-ink bg-ok-bg px-[10px] text-11.5 font-bold text-ink opacity-60">{t('answer.yes')}</button>
              <button type="button" disabled title={t('answer.why')} className="h-7 cursor-not-allowed rounded-8 border border-line bg-surface px-[10px] text-11.5 font-semibold text-ink opacity-60">{t('answer.talk')}</button>
            </span>
            <Why>{t('answer.why')}</Why>
          </div>
        ) : null}
        <span className={label}>{head}</span>
        {list.map((a) => (
          <div key={a.id} className="rounded-10 border border-line bg-surface px-[11px] py-2 text-12.5 font-semibold">
            {a.title} →
            {a.snippet ? (
              <span className="mt-[3px] block text-11.5 font-normal text-muted">
                {snippetRuns(a.snippet).map((r, i) => (r.hit ? <b key={i} className="text-ink">{r.text}</b> : <span key={i}>{r.text}</span>))}
              </span>
            ) : null}
          </div>
        ))}
        {list.length === 0 && empty ? <Why>{empty}</Why> : null}
        <div className="grid grid-cols-2 gap-[6px]">
          {(inApp ? (['talk', 'book'] as const) : (['demo', 'sales'] as const)).map((k, i) => (
            <button
              key={k}
              type="button"
              disabled
              title={t('actions.why')}
              className={`h-[38px] cursor-not-allowed rounded-10 border text-12 font-bold text-ink opacity-60 ${i === 0 ? 'border-ink bg-primary' : 'border-line bg-surface'}`}
            >
              {t(`actions.${k}`)}
            </button>
          ))}
        </div>
        <Why>{t('actions.why')}</Why>
      </div>
    </div>
  )
}

function Captured({ data, productName, inApp }: { data: Widget; productName: string; inApp: boolean }) {
  const t = useTranslations('supportHub.widget.captured')
  const st = useTranslations('simpleCustomers.status')
  const dash = useTranslations('common')('dash')
  const r = data.last_request
  const notSent = t('notSent', { product: productName })
  const subs = r?.subscriptions.map((s) => `${s.product}: ${s.status && st.has(s.status) ? st(s.status) : s.status ?? dash}`).join(' · ')
  const rows: [string, string][] = inApp ? [
    [t('user'), r ? [r.person ?? dash, r.role ?? dash].join(' · ') : dash],
    [t('organization'), r?.organization ? [r.organization.name, r.organization.org_number ? orgNr(r.organization.org_number) : null].filter(Boolean).join(' · ') : dash],
    [t('plan'), subs || dash],
    [t('page'), r?.page ?? dash],
    [t('lastError'), `${dash} · ${notSent}`],
    [t('browser'), r?.browser ?? dash],
    [t('version'), r?.app_version ?? `${dash} · ${notSent}`],
  ] : [
    [t('visitor'), t('anonymous')],
    [t('page'), dash],
    [t('source'), dash],
    [t('company'), t('notConnected')],
  ]
  return (
    <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
      <b className="text-15">{t('title')}</b>
      <Why>{inApp ? (r ? t('from', { ref: r.ref }) : t('none')) : t('web')}</Why>
      {rows.map(([k, v]) => (
        <div key={k} className="flex justify-between gap-[10px] border-b border-tile py-1 text-12.5">
          <span className="text-muted">{k}</span><b className="text-right [overflow-wrap:anywhere]">{v}</b>
        </div>
      ))}
      <span className="text-11.5 font-semibold text-danger">{t('never')}</span>
    </div>
  )
}

function Settings({ data, product, productName }: { data: Widget; product: string; productName: string }) {
  const t = useTranslations('supportHub.widget.settings')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [ai, setAi] = useState(data.ai_enabled)
  const [pending, start] = useTransition()
  const setAiOn = (on: boolean) => start(async () => {
    const r = await saveSupportSettings({ product, aiEnabled: on })
    if (!r.ok) { flash(errorText(r.code)); return }
    setAi(on)
    flash(on ? t('aiOn', { product: productName }) : t('aiOff', { product: productName }))
    router.refresh()
  })
  const rows: { key: string; on: boolean; why: string | null; change?: (on: boolean) => void }[] = [
    { key: 'ai', on: ai, why: data.can_configure ? null : t('why.configure'), change: setAiOn },
    { key: 'tickets', on: false, why: t('why.tickets') },
    { key: 'chat', on: false, why: t('why.chat') },
    { key: 'consent', on: false, why: t('why.consent') },
  ]
  return (
    <div className={`${card} flex flex-col gap-[9px] px-[18px] py-4`}>
      <b className="text-15">{t('title')}</b>
      {rows.map((s) => (
        <div key={s.key} className="flex items-center justify-between gap-[10px]">
          <span className="flex flex-col">
            <b className="text-12.5">{t(`${s.key}.name`)}</b>
            <span className="text-11.5 text-muted">{t(`${s.key}.sub`)}</span>
            {s.why ? <Why className="text-faint">{s.why}</Why> : null}
          </span>
          <Toggle on={s.on} label={t(`${s.key}.name`)} disabled={!!s.why || !s.change || pending} why={s.why} onChange={s.change} />
        </div>
      ))}
      <div className="rounded-10 bg-ink px-[10px] py-[9px] text-11.5 text-tile [font-family:ui-monospace,Menlo,monospace]">{t('embed')}</div>
    </div>
  )
}
