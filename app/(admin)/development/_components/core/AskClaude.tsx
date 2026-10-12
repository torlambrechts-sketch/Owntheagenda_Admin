'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { applyDraft, askClaude, discardDraft } from '../../core-actions'
import type { AiFeature } from './logic'
import { c, useRun } from './kit'
import type { FileDetail } from './MarkdownView'

type Ask = { label: string; feature: AiFeature | null; primary?: boolean }

/**
 * «Ask Claude» on a roadmap item (DevClaude.dc.html, asks[]): Write spec, Plan tasks and Write release note go through
 * ai-run; the draft comes back here, and only «Use» makes it a spec, work items or draft release notes. Implement and
 * Review PR need a repository and stay disabled: GitHub is not connected.
 */
export function AskClaude({ d, canAdd }: { d: FileDetail; canAdd: boolean }) {
  const t = useTranslations('devCore.ai')
  const format = useFormatter()
  const { run, pending } = useRun()
  const [asking, setAsking] = useState<AiFeature | null>(null)
  const asks: Ask[] = [
    { label: t('asks.spec'), feature: 'spec_draft' },
    { label: t('asks.plan'), feature: 'task_plan' },
    { label: t('asks.implement'), feature: null, primary: true },
    { label: t('asks.review'), feature: null },
    { label: t('asks.notes'), feature: 'release_note_draft' },
  ]
  const why = (a: Ask): string | null => {
    if (!a.feature) return t('needsGithub')
    if (!canAdd || !d.ai) return t('needsRight')
    if (!d.ai.connected) return t('notConnected')
    if (!d.ai.allowed.includes(a.feature)) return t('needsRight')
    if (a.feature === 'release_note_draft' && d.doneTasks === 0) return t('noDoneWork')
    return null
  }
  const reasons = Array.from(new Set(asks.map(why).filter((x): x is string => !!x)))
  const ask = (feature: AiFeature) => {
    setAsking(feature)
    run(() => askClaude({ feature, item: d.id }), (r) => ('truncated' in r && r.truncated ? t('readyTruncated') : t('ready')), () => setAsking(null))
  }
  return (
    <div className="flex flex-col gap-3 border-t border-line pt-3">
      <div className="flex flex-wrap items-center gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/assistant.png" alt="" width={26} height={26} className="rounded-8 bg-canvas" />
        <b className="mr-1 text-13">{t('ask')}</b>
        {asks.map((a) => {
          const reason = why(a)
          return (
            <button key={a.label} type="button" disabled={!!reason || pending} title={reason ?? undefined} onClick={() => a.feature && ask(a.feature)}
              className={`h-8 cursor-pointer whitespace-nowrap rounded-9 border border-ink px-3 text-12 font-bold text-ink disabled:cursor-default disabled:opacity-50 ${a.primary ? 'bg-primary' : 'bg-surface'}`}>
              {asking === a.feature && pending ? t('asking') : a.label}
            </button>
          )
        })}
      </div>
      {reasons.length ? <span className="text-11.5 text-muted">{reasons.join(' ')}</span> : null}
      {d.drafts.map((x) => (
        <div key={x.id} className="flex flex-col gap-2 rounded-12 border border-line bg-canvas px-3 py-[10px]">
          <span className="text-12 text-muted"><b className="text-ink">{t('draftOf', { what: t(`features.${x.feature}`) })}</b> · {format.relativeTime(new Date(x.at), new Date(d.now))}{x.by ? ` · ${x.by}` : ''}</span>
          <pre className="m-0 max-h-[240px] overflow-auto whitespace-pre-wrap font-sans text-12.5 leading-[1.55] [overflow-wrap:anywhere]">{x.body}</pre>
          <span className="text-11.5 text-muted">{t(`useNote.${x.feature}`)}</span>
          <div className="flex flex-wrap justify-end gap-2">
            <button type="button" disabled={pending} className={c.rowBtn} onClick={() => run(() => discardDraft({ id: x.id }), () => t('discarded'))}>{t('discard')}</button>
            <button type="button" disabled={pending} className={c.rowBtnPrimary}
              onClick={() => run(() => applyDraft({ id: x.id, feature: x.feature, item: d.id }), (r) => ('created' in r ? t(`used.${x.feature}`, { n: r.created }) : null))}>
              {t('use')}
            </button>
          </div>
        </div>
      ))}
    </div>
  )
}
