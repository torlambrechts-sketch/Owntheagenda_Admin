'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { resolveProblem, saveArticle } from '../actions'
import { placeholders } from './merge'
import type { Help, TicketConfig, TicketRow } from '@/lib/data/tickets'

const box = 'rounded-15 border border-line bg-canvas px-[14px] py-3'
const eyebrow = 'text-11 font-bold uppercase tracking-eyebrow text-muted'
const toggle = (on: boolean) =>
  `flex h-[30px] cursor-pointer items-center gap-2 rounded-9 border px-[10px] text-12 font-semibold disabled:cursor-default ${on ? 'border-ink bg-ok-bg' : 'border-line bg-transparent'}`

/** Problems and known errors (Tickets.dc.html, v.problems): one card per problem ticket with its incidents. */
export function Problems({ problems, incidents, articles, config, products, canResolve, canConfigure }: {
  problems: TicketRow[]
  incidents: TicketRow[]
  articles: Help['articles']
  config: TicketConfig
  products: Record<string, string>
  canResolve: boolean
  canConfigure: boolean
}) {
  const t = useTranslations('tickets')
  if (!problems.length) {
    return <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{t('problems.empty')}</div>
  }
  return (
    <div className="flex flex-col gap-[14px]">
      {problems.map((p) => (
        <ProblemCard
          key={p.id}
          p={p}
          linked={incidents.filter((i) => i.problem_id === p.id)}
          articles={articles.filter((a) => a.problem_id === p.id)}
          owner={config.assignees.find((a) => a.id === p.owner_id)?.name ?? '—'}
          product={p.product ? products[p.product] ?? p.product : null}
          canResolve={canResolve}
          canConfigure={canConfigure}
        />
      ))}
    </div>
  )
}

function ProblemCard({ p, linked, articles, owner, product, canResolve, canConfigure }: {
  p: TicketRow; linked: TicketRow[]; articles: Help['articles']; owner: string; product: string | null; canResolve: boolean; canConfigure: boolean
}) {
  const t = useTranslations('tickets')
  const tc = useTranslations('common')
  const flash = useToast()
  const [composing, setComposing] = useState(false)
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState(false)
  const status = p.problem_status ?? 'investigating'
  const openLinked = linked.filter((i) => i.status !== 'resolved' && i.status !== 'closed')
  const published = articles.some((a) => a.status === 'published')
  const left = placeholders(body)

  async function resolve() {
    if (!body.trim() || left.length) return
    setBusy(true)
    const r = await resolveProblem({ id: p.id, body })
    setBusy(false)
    if (!r.ok) { flash(tc(`errors.${r.code}`)); return }
    setComposing(false)
    setBody('')
    flash(t('problems.resolved', { n: r.notified }))
  }

  async function toggleHelp() {
    setBusy(true)
    let ok = true
    let code = 'failed'
    if (published) {
      for (const a of articles.filter((x) => x.status === 'published')) {
        const r = await saveArticle({ id: a.id, values: { status: 'draft' } })
        if (!r.ok) { ok = false; code = r.code; break }
      }
    } else {
      const draft = articles[0]
      const r = draft
        ? await saveArticle({ id: draft.id, values: { status: 'published' } })
        : await saveArticle({ id: null, values: { title: p.subject, body: p.workaround ?? '', status: 'published', problem_id: p.id, category_key: linked[0]?.category_key ?? null } })
      if (!r.ok) { ok = false; code = r.code }
    }
    setBusy(false)
    flash(ok ? t(published ? 'problems.publishedOff' : 'problems.publishedOn') : tc(`errors.${code}`))
  }

  return (
    <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-[18px]">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex min-w-0 flex-[1_1_360px] flex-col gap-1">
          <span className="text-12 text-muted"><b className="text-ink">{p.ref}</b> · {t('problems.problem')} · {owner}{product ? ` · ${product}` : ''}</span>
          <span className="font-serif text-20 font-semibold">{p.subject}</span>
          <span className="text-13 leading-[1.55] text-ink-2">{t('problems.rootCause', { text: p.root_cause ?? '—' })}</span>
        </div>
        <div className="flex items-center gap-2">
          <span className={`rounded-999 px-[11px] py-1 text-11.5 font-bold ${status === 'resolved' ? 'bg-ok-bg text-ok-ink' : 'bg-amber-bg text-amber-ink'}`}>{t(`problemStatus.${status}`)}</span>
          <button
            type="button"
            disabled={!canResolve || status === 'resolved'}
            aria-expanded={composing}
            onClick={() => setComposing(!composing)}
            className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60"
          >
            {t('problems.resolveNotify', { n: openLinked.length })}
          </button>
        </div>
      </div>
      {composing ? (
        <div className="flex flex-col gap-2">
          <textarea
            autoFocus
            aria-label={t('problems.resolveBody')}
            placeholder={t('problems.resolveBody')}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            className="min-h-[90px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 leading-[1.55]"
          />
          <div className="flex flex-wrap items-center justify-end gap-2">
            {left.length ? <span role="alert" className="mr-auto text-11.5 font-semibold text-danger">{t('composer.placeholders', { fields: left.join(', ') })}</span> : null}
            <button type="button" onClick={() => setComposing(false)} className="h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-[14px] text-12.5 font-semibold">{tc('cancel')}</button>
            <button type="button" disabled={busy || !body.trim() || left.length > 0} onClick={() => void resolve()} className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60">
              {t('problems.resolveConfirm')}
            </button>
          </div>
        </div>
      ) : null}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        <div className={box}>
          <div className={`${eyebrow} mb-2`}>{t('problems.linked')}</div>
          {linked.map((l) => (
            <div key={l.id} className="flex justify-between gap-2 py-[5px] text-12.5">
              <span><b>{l.ref}</b> {l.subject}</span>
              <span className="whitespace-nowrap text-muted">{l.organization?.name ?? '—'}</span>
            </div>
          ))}
          {!linked.length ? <div className="py-[5px] text-12.5 text-muted">{t('problems.noIncidents')}</div> : null}
        </div>
        <div className={`${box} flex flex-col gap-2`}>
          <div className={eyebrow}>{t('problems.known')}</div>
          <div className="text-12.5 leading-[1.55]">{p.workaround ?? '—'}</div>
          <div className="flex flex-wrap gap-2">
            <button type="button" aria-pressed={published} disabled={!canConfigure || busy} onClick={() => void toggleHelp()} className={`${toggle(published)} ${!canConfigure ? 'opacity-60' : ''}`}>
              {published ? '✓' : '○'} {t('problems.published')}
            </button>
            <button type="button" aria-pressed={p.status_banner} disabled title={t('problems.bannerOff')} className={`${toggle(p.status_banner)} opacity-60`}>
              {p.status_banner ? '✓' : '○'} {t('problems.banner')}
            </button>
          </div>
          <div className="text-11.5 text-faint">{t('problems.bannerOff')}</div>
        </div>
      </div>
    </div>
  )
}
