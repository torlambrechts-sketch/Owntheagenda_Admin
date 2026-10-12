'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useFormatter, useTranslations } from 'next-intl'
import { setBug, setRoadmapItem } from '../../core-actions'
import { STATUSES, STATUS_PILL, fileStatus, type AiFeature, type Status } from './logic'
import { c, useRun, type ProductInfo } from './kit'
import { NewItem } from './RoadmapBoard'
import { AskClaude } from './AskClaude'

export type FileRow = { key: string; kind: 'feature' | 'bug'; id: string; path: string; title: string; status: Status }
export type FileDetail = {
  key: string; kind: 'feature' | 'bug'; id: string; path: string; title: string; status: Status; md: string; version: number; open: boolean
  owner: string | null; lastChange: { at: string; by: string | null } | null
  /** the server's «now», so a relative time reads the same in both renders */
  now: string
  tasks: { key: string; title: string; done: boolean }[]; links: string[]
  log: { at: string; action: string; by: string | null; title: string; detail: string }[]
  doneTasks: number
  ai: { connected: boolean; allowed: string[] } | null
  drafts: { id: string; feature: AiFeature; body: string; at: string; by: string | null }[]
}

/** the log's glyphs (baseLog): created, a change, the spec, a link, Claude */
const GLYPH: Record<string, [string, string]> = {
  added: ['＋', 'bg-ok-bg'], promoted: ['＋', 'bg-ok-bg'], moved: ['✎', 'bg-highlight'], changed: ['✎', 'bg-highlight'], status: ['✎', 'bg-highlight'],
  linked: ['⎇', 'bg-blue-bg'], merged: ['⎇', 'bg-blue-bg'], archived: ['▤', 'bg-lilac'], fixed: ['✓', 'bg-ok-bg'], signed: ['▤', 'bg-lilac'],
  unsigned: ['▤', 'bg-lilac'], planned: ['🤖', 'bg-tile'], used: ['🤖', 'bg-tile'],
}
const glyph = (action: string) => GLYPH[action.split('.')[1] ?? ''] ?? ['✎', 'bg-highlight']

/** the file list with its status filter, and the open file (DevClaude.dc.html, v.md) */
export function MarkdownView({ files, detail, staff, canAdd, generatedAt, products }: {
  files: FileRow[]; detail: FileDetail | null; staff: { id: string; name: string }[]; canAdd: boolean; generatedAt: string; products: ProductInfo[]
}) {
  const t = useTranslations('devCore.md')
  const [filter, setFilter] = useState<Status | 'all'>('all')
  const [adding, setAdding] = useState(false)
  const shown = files.filter((f) => filter === 'all' || f.status === filter)
  return (
    <div className="grid grid-cols-1 items-start gap-[14px] md:[grid-template-columns:minmax(220px,300px)_minmax(0,1fr)]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex items-center justify-between gap-2 border-b border-line px-4 py-3">
          <b className={`${c.mono} text-13.5`}>/roadmap</b>
          <span className="whitespace-nowrap text-11.5 text-muted">{t('generated', { time: generatedAt })}</span>
        </div>
        <div className="flex flex-wrap gap-[5px] border-b border-line px-3 py-[10px]">
          {(['all', ...STATUSES] as const).map((s) => {
            const n = s === 'all' ? files.length : files.filter((f) => f.status === s).length
            return (
              <button key={s} type="button" aria-pressed={filter === s} onClick={() => setFilter(s)}
                className={`cursor-pointer whitespace-nowrap rounded-999 border px-[10px] py-1 text-11.5 text-ink ${filter === s ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
                {s === 'all' ? t('all') : fileStatus(s)} {n}
              </button>
            )
          })}
        </div>
        {shown.map((f) => (
          <Link key={f.key} href={`/development?tab=md&file=${f.key}` as Route} aria-current={detail?.key === f.key ? 'true' : undefined}
            className={`flex w-full items-center gap-[10px] border-b border-line px-[14px] py-[10px] text-left text-ink hover:text-ink hover:no-underline ${detail?.key === f.key ? 'bg-highlight' : 'bg-transparent'}`}>
            <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
              <span className={`${c.mono} truncate text-11.5 text-muted`}>{f.path.replace(/^roadmap\/features\//, '').replace(/^roadmap\//, '')}</span>
              <b className="text-12.5">{f.title}</b>
            </span>
            <span className={`whitespace-nowrap rounded-999 px-2 py-[2px] text-10.5 font-bold ${STATUS_PILL[f.status]}`}>{fileStatus(f.status)}</span>
          </Link>
        ))}
        {!shown.length ? <div className="px-4 py-5 text-center text-12.5 text-muted">{files.length ? t('noneWithStatus') : t('empty')}</div> : null}
        {canAdd ? <div className="px-[14px] py-[10px]"><button type="button" onClick={() => setAdding(true)} className={c.dashed}>{t('newFile')}</button></div> : null}
      </div>
      {detail ? <Detail key={detail.key} d={detail} staff={staff} canAdd={canAdd} /> : null}
      {adding ? <NewItem products={products} preset={null} onClose={() => setAdding(false)} /> : null}
    </div>
  )
}

function Detail({ d, staff, canAdd }: { d: FileDetail; staff: { id: string; name: string }[]; canAdd: boolean }) {
  const t = useTranslations('devCore.md')
  const format = useFormatter()
  const { run, pending } = useRun()
  const editable = canAdd && d.open
  const download = () => {
    const url = URL.createObjectURL(new Blob([d.md], { type: 'text/markdown;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = d.path.split('/').pop() ?? `${d.key}.md`
    a.click()
    URL.revokeObjectURL(url)
  }
  const sel = 'h-[34px] rounded-9 border border-line bg-canvas px-1 text-12.5 font-bold normal-case tracking-normal text-ink disabled:opacity-70'
  /** a disabled control's reason, visible under it (not only in its title) */
  const note = 'text-11 font-normal normal-case tracking-normal text-muted'
  const ago = (iso: string) => format.relativeTime(new Date(iso), new Date(d.now))
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex flex-col gap-3 rounded-20 border border-ink bg-surface px-[18px] py-4">
        <div className="flex flex-wrap items-start justify-between gap-[10px]">
          <div className="min-w-0">
            <div className={`${c.mono} text-11.5 text-muted [overflow-wrap:anywhere]`}>{d.path}</div>
            <div className="mt-[3px] font-serif text-21 font-semibold leading-[1.2]">{d.title}</div>
          </div>
          <span className="flex flex-col items-end gap-[6px]">
            <span className="whitespace-nowrap text-12 text-muted">{d.lastChange ? t('lastChange', { ago: ago(d.lastChange.at), by: d.lastChange.by ?? '—' }) : ''}</span>
            <button type="button" onClick={download} className="h-7 cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-surface px-[10px] text-11.5 font-bold text-ink">{t('download')}</button>
          </span>
        </div>
        <div className="grid gap-2 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
          <label className="flex flex-col gap-1 text-11 font-bold uppercase tracking-[.06em] text-muted">{t('status')}
            <select value={d.status} disabled={!editable || d.kind === 'bug' || pending} title={d.kind === 'bug' ? t('bugStatusNote') : undefined}
              onChange={(e) => run(() => setRoadmapItem({ id: d.id, version: d.version, patch: { status: e.target.value } }), () => t('saved'))} className={sel}>
              {STATUSES.map((s) => <option key={s} value={s}>{fileStatus(s)}</option>)}
            </select>
            {d.kind === 'bug' ? <span className={note}>{t('bugStatusNote')}</span> : null}
          </label>
          <label className="flex flex-col gap-1 text-11 font-bold uppercase tracking-[.06em] text-muted">{t('owner')}
            <select value={d.owner ?? ''} disabled={!editable || pending}
              onChange={(e) => run(() => (d.kind === 'bug'
                ? setBug({ id: d.id, version: d.version, patch: { assignee_id: e.target.value || null } })
                : setRoadmapItem({ id: d.id, version: d.version, patch: { owner_id: e.target.value || null } })), () => t('saved'))} className={sel}>
              <option value="">—</option>
              {staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-11 font-bold uppercase tracking-[.06em] text-muted">{t('rollout')}
            <select value="" disabled title={t('rolloutNote')} className={sel}><option value="">—</option></select>
            <span className={note}>{t('rolloutNote')}</span>
          </label>
        </div>
        {!canAdd ? <span className="text-11.5 text-muted">{t('readOnlyNote')}</span> : null}
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr))]">
          <pre className={`m-0 whitespace-pre-wrap rounded-12 bg-ink px-[14px] py-3 ${c.mono} text-11.5 leading-[1.6] text-tile [overflow-wrap:anywhere]`}>{d.md}</pre>
          <div className="flex flex-col gap-2">
            <span className={c.label}>{t('tasks', { done: d.tasks.filter((x) => x.done).length, total: d.tasks.length })}</span>
            {d.tasks.map((x) => (
              <div key={x.key} className="flex items-start gap-[9px] border-b border-tile py-[5px] text-12.5">
                <span aria-hidden className={`mt-px flex h-[17px] w-[17px] flex-none items-center justify-center rounded-5 border-[1.5px] border-ink text-10 ${x.done ? 'bg-ok-bg' : 'bg-transparent'}`}>{x.done ? '✓' : ''}</span>
                <span className={x.done ? 'line-through' : ''}><span className="sr-only">{x.done ? t('done') : t('open')} </span><span className={`${c.mono} text-11`}>{x.key}</span> {x.title}</span>
              </div>
            ))}
            {!d.tasks.length ? <span className="text-12 text-muted">{d.kind === 'feature' ? t('noTasks') : t('noBugTasks')}</span> : null}
            <span className={`${c.label} mt-1`}>{t('linked')}</span>
            <div className="flex flex-wrap gap-[5px]">
              {d.links.map((l, i) => <span key={i} className="whitespace-nowrap rounded-999 bg-tile px-2 py-[2px] text-11">{l}</span>)}
              {!d.links.length ? <span className="text-12 text-muted">{t('noLinks')}</span> : null}
            </div>
          </div>
        </div>
        {d.kind === 'feature' ? <AskClaude d={d} canAdd={canAdd} /> : null}
        <div className="flex flex-wrap items-center gap-[10px] rounded-12 bg-highlight px-3 py-[10px] text-12.5">
          <span className="flex-[1_1_240px]">{t('commitNote')}</span>
          <button type="button" disabled title={t('commitDisabled')}
            className="h-8 cursor-default whitespace-nowrap rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold text-ink opacity-50">{t('commit')}</button>
        </div>
      </div>
      <div className="flex flex-col gap-1 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="mb-[6px] text-14">{t('workLog')}</b>
        {d.log.map((l, i) => {
          const [g, bg] = glyph(l.action)
          return (
            <div key={i} className="grid items-start gap-[10px] border-b border-tile py-[7px] text-12.5 [grid-template-columns:96px_26px_minmax(0,1fr)]">
              <span className="text-11.5 text-faint">{ago(l.at)}</span>
              <span aria-hidden className={`flex h-6 w-6 items-center justify-center rounded-7 text-11 ${bg}`}>{g}</span>
              <span className="min-w-0"><b>{l.title}</b> <span className="text-muted [overflow-wrap:anywhere]">· {[l.by, l.detail].filter(Boolean).join(' · ')}</span></span>
            </div>
          )
        })}
        {!d.log.length ? <span className="text-12.5 text-muted">{t('noLog')}</span> : null}
      </div>
    </div>
  )
}
