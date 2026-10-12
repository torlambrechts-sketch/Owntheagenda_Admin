'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useFormatter, useTranslations } from 'next-intl'
import type { Jobs } from '@/lib/data/dev-core'
import type { AiStatus } from '@/lib/ai/run'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { useSensitive } from '../../../applications/_components/kit'
import { connectClaude, disconnectClaude, setClaudeSettings } from '../../core-actions'
import { share } from './logic'
import { c, Kpi, useRun } from './kit'

/** the models the gateway's request shape (refusal fallback, effort) serves; the stored one is always offered */
const MODELS = ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-fable-5-1'] as const
const KIND: Record<Jobs['rows'][number]['feature'], string> = { spec_draft: '/spec', task_plan: '/plan', release_note_draft: '/notes' }
const STATE_PILL: Record<'ready' | 'used' | 'discarded' | 'failed', string> = {
  ready: 'bg-highlight text-amber-ink', used: 'bg-ok-bg text-ok-ink', discarded: 'bg-tile text-muted', failed: 'bg-salmon text-rust-ink',
}

export function JobsView({ data, ai, nf, now }: { data: Jobs; ai: AiStatus | null; nf: NumberFormat; now: string }) {
  const t = useTranslations('devCore.jobs')
  const ta = useTranslations('devCore.ai')
  const format = useFormatter()
  const k = data.kpi
  const accepted = share(k.used, k.drafts)
  const waiting = Math.max(k.drafts - k.used - k.discarded, 0)
  const ms = k.median_ms
  const median = ms === null ? t('dash') : ms < 60_000 ? t('seconds', { n: formatNumber(Math.round(ms / 1000), nf) }) : t('minutes', { n: formatNumber(Math.round(ms / 6000) / 10, nf, 1) })
  const quality: { name: string; n: number; tone: string }[] = [
    { name: t('quality.used'), n: k.used, tone: 'bg-ok' },
    { name: t('quality.discarded'), n: k.discarded, tone: 'bg-alert' },
    { name: t('quality.waiting'), n: waiting, tone: 'bg-warn' },
  ]
  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        <Kpi label={t('kpi.drafts')} value={formatNumber(k.drafts, nf)} sub={t('kpi.draftsSub', { calls: k.calls, failed: k.failed })} />
        <Kpi label={t('kpi.accepted')} value={accepted === null ? t('dash') : `${accepted} %`} tone={accepted === null ? 'text-ink' : 'text-link'} sub={t('kpi.acceptedSub')} />
        <Kpi label={t('kpi.median')} value={median} sub={t('kpi.medianSub')} />
        <Kpi label={t('kpi.spend')} value={formatNumber(k.tokens_month, nf)} sub={t('kpi.spendSub')} title={t('kpi.spendTitle')} />
      </div>
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-3">
          <b className="text-15">{t('title')}</b>
          <span className="text-12 text-muted">{t('note')}</span>
        </div>
        <div className="overflow-x-auto">
          <div className="min-w-[640px]">
            {data.rows.map((r) => {
              const failed = r.state !== 'ok' && r.state !== 'retried_ok'
              const state = failed ? 'failed' : r.output?.state ?? 'ready'
              const tokens = (r.input_tokens ?? 0) + (r.output_tokens ?? 0)
              const out = failed ? ta.has(`codes.${r.error ?? 'error'}`) ? ta(`codes.${r.error ?? 'error'}`) : t('failedCode', { code: r.error ?? 'error' })
                : t('out', { tokens: formatNumber(tokens, nf), s: formatNumber(Math.round((r.latency_ms ?? 0) / 1000), nf) })
              return (
                <div key={r.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 [grid-template-columns:minmax(0,2fr)_90px_100px_minmax(0,1.2fr)_80px]">
                  <span className="flex min-w-0 flex-col">
                    <b>{ta(`asks.${r.feature === 'spec_draft' ? 'spec' : r.feature === 'task_plan' ? 'plan' : 'notes'}`)}{r.item ? ` · ${r.item.title}` : ''}</b>
                    <span className="text-11 text-muted">
                      {r.item ? <Link href={`/development?tab=md&file=${r.item.key}` as Route}>{r.item.key}</Link> : t('dash')} · {r.by ?? t('dash')}
                    </span>
                  </span>
                  <span className={`${c.mono} whitespace-nowrap text-11.5 text-muted`}>{KIND[r.feature]}</span>
                  <span><span className={`whitespace-nowrap rounded-999 px-[9px] py-[2px] text-11 font-bold ${STATE_PILL[state]}`}>{t(`state.${state}`)}</span></span>
                  <span title={out} className={`${c.mono} min-w-0 truncate text-11.5 text-muted`}>{out}</span>
                  <span className="whitespace-nowrap text-11.5 text-faint">{format.relativeTime(new Date(r.at), new Date(now))}</span>
                </div>
              )
            })}
          </div>
        </div>
        {!data.rows.length ? <div className="p-6 text-center text-13 text-muted">{ai && !ai.connected ? t('emptyNotConnected') : t('empty')}</div> : null}
      </div>
      <div className="flex flex-col gap-[6px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-15">{t('quality.title')}</b>
        {quality.map((q) => {
          const pct = share(q.n, k.drafts)
          return (
            <div key={q.name} className="grid items-center gap-[10px] py-1 text-12.5 [grid-template-columns:minmax(0,1fr)_minmax(0,1.4fr)_70px]">
              <span>{q.name}</span>
              <span className="h-2 overflow-hidden rounded-999 bg-tile"><span className={`block h-full ${q.tone}`} style={{ width: `${pct ?? 0}%` }} /></span>
              <b className="whitespace-nowrap text-right">{pct === null ? t('dash') : `${pct} %`}</b>
            </div>
          )
        })}
        <span className="text-11.5 text-muted">{t('quality.note')}</span>
      </div>
      <ClaudeCard ai={ai} />
    </div>
  )
}

/** the Claude connection: its state for everyone; the owner gives the key (fresh second factor), picks the model and effort, or disconnects */
function ClaudeCard({ ai }: { ai: AiStatus | null }) {
  const t = useTranslations('devCore.jobs.claude')
  const format = useFormatter()
  const s = useSensitive()
  const { run, pending } = useRun()
  const [key, setKey] = useState('')
  const [model, setModel] = useState(ai?.model ?? MODELS[0])
  const [effort, setEffort] = useState<'low' | 'medium' | 'high'>(ai?.effort ?? 'medium')
  if (!ai) return null
  const models = Array.from(new Set([...MODELS, ai.model]))
  const keyOk = /^sk-ant-[A-Za-z0-9_-]+$/.test(key.trim()) && key.trim().length >= 30
  const sel = 'h-[34px] rounded-9 border border-line bg-canvas px-1 text-12.5 text-ink'
  return (
    <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[18px] py-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <b className="text-15">{t('title')}</b>
        <span className={`text-12 font-bold ${ai.connected ? 'text-link' : 'text-muted'}`}>
          {ai.connected ? (ai.key_stored_at ? t('connectedSince', { date: format.dateTime(new Date(ai.key_stored_at), { day: 'numeric', month: 'short', year: 'numeric' }) }) : t('connected')) : t('notConnected')}
        </span>
      </div>
      <span className="text-12.5 leading-[1.5] text-muted">{t('what')}</span>
      {ai.can_manage ? (
        <>
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1 text-11.5 font-semibold text-muted">{t('model')}
              <select value={model} onChange={(e) => setModel(e.target.value)} className={sel}>{models.map((m) => <option key={m} value={m}>{m}</option>)}</select>
            </label>
            <label className="flex flex-col gap-1 text-11.5 font-semibold text-muted">{t('effort')}
              <select value={effort} onChange={(e) => setEffort(e.target.value as 'low' | 'medium' | 'high')} className={sel}>
                {(['low', 'medium', 'high'] as const).map((x) => <option key={x} value={x}>{t(`efforts.${x}`)}</option>)}
              </select>
            </label>
            <button type="button" disabled={pending || (model === ai.model && effort === ai.effort)} className={c.small}
              onClick={() => run(() => setClaudeSettings({ model, effort }), () => t('settingsSaved'))}>{t('saveSettings')}</button>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex min-w-0 flex-[1_1_260px] flex-col gap-1 text-11.5 font-semibold text-muted">{ai.connected ? t('replaceKey') : t('key')}
              <input type="password" value={key} onChange={(e) => setKey(e.target.value)} autoComplete="off" placeholder="sk-ant-…" className={`${c.input} h-[34px] ${c.mono} text-12.5`} />
            </label>
            <button type="button" disabled={s.pending || !keyOk} className={c.smallPrimary}
              onClick={() => s.call(() => connectClaude({ key }), () => setKey(''))}>{ai.connected ? t('replace') : t('connect')}</button>
            {ai.connected ? (
              <button type="button" disabled={s.pending} className={c.small} onClick={() => s.call(() => disconnectClaude(), () => undefined)}>{t('disconnect')}</button>
            ) : null}
          </div>
          <span className="text-11.5 text-muted">{t('keyNote')}</span>
          {s.mfa}{s.alert}
        </>
      ) : <span className="text-12 text-muted">{t('ownerOnly')}</span>}
    </div>
  )
}
