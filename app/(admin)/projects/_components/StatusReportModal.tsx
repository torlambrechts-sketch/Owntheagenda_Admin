'use client'

import { useState, useTransition } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { RpcCode } from '@/lib/rpc'
import type { ProjectBundle } from '@/lib/data/projects'
import { requestStatusReport } from '../actions'
import { btnCancel, btnConfirm, field, fieldInput, Modal, note } from './kit'

type R = { ok: true } | { ok: false; code: RpcCode; detail?: string | null }

const SECTIONS = ['summary', 'milestones', 'open_overdue', 'upcoming'] as const

/**
 * «AI status report (PDF)» (PRJ-07, D-41): the sender chooses what goes in — sections, a «done since» date, notes —
 * and writes or (with the AI) drafts the summary. The PDF is rendered by a worker; «Create PDF» follows whether it is
 * connected (project_pdf_status, 0040), so a report is never requested that nothing will produce. While it is not, the
 * dialog says so (D-41). The AI draft is offered only while both the worker and the AI are available.
 */
export function StatusReportModal({ bundle, onClose, onAfter }: {
  bundle: ProjectBundle
  onClose: () => void
  onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean>
}) {
  const t = useTranslations('projects.report')
  const format = useFormatter()
  const d = bundle.detail
  const [on, setOn] = useState<Record<string, boolean>>({ summary: true, milestones: true, open_overdue: true, upcoming: true })
  const [since, setSince] = useState('')
  const [notes, setNotes] = useState<string[]>([])
  const [summary, setSummary] = useState('')
  const noteRows = d.timeline.filter((x) => x.kind === 'note')
  const ai = d.ai
  const pdf = bundle.pdfConnected
  const [busy, start] = useTransition()
  // the database refuses a report that includes nothing
  const something = Object.values(on).some(Boolean) || since !== '' || notes.length > 0
  const create = (aiDraft: boolean) => start(async () => {
    const ok = await onAfter(requestStatusReport({
      id: d.id, aiDraft, summary,
      sections: { summary: !!on.summary, milestones: !!on.milestones, open_overdue: !!on.open_overdue, upcoming: !!on.upcoming,
        ...(since ? { done_since: since } : {}), ...(notes.length ? { note_ids: notes } : {}) },
    }), t('requested'))
    if (ok) onClose()
  })

  return (
    <Modal eyebrow={t('eyebrow')} title={t('title', { name: d.name })} onClose={onClose} width={560}>
      <div className="flex flex-col gap-[6px]">
        <span className="text-12 font-semibold text-muted">{t('sections')}</span>
        {SECTIONS.map((k) => (
          <label key={k} className="flex items-center gap-2 text-12.5">
            <input type="checkbox" checked={!!on[k]} onChange={(e) => setOn({ ...on, [k]: e.target.checked })} className="accent-ink" />
            {t(`section.${k}`)}
          </label>
        ))}
        <label className="flex items-center gap-2 text-12.5">
          {t('doneSince')}
          <input type="date" value={since} onChange={(e) => setSince(e.target.value)} className="h-[30px] rounded-9 border border-line bg-canvas px-2 text-12.5" />
        </label>
        {noteRows.length ? (
          <div className="flex flex-col gap-1">
            <span className="text-12 font-semibold text-muted">{t('notes')}</span>
            {noteRows.map((n) => (
              <label key={n.id} className="flex items-start gap-2 text-12.5">
                <input type="checkbox" checked={notes.includes(n.id)} onChange={(e) => setNotes((xs) => (e.target.checked ? [...xs, n.id] : xs.filter((x) => x !== n.id)))} className="mt-[3px] accent-ink" />
                <span className="line-clamp-2">{n.kind === 'note' ? n.body : ''}</span>
              </label>
            ))}
          </div>
        ) : null}
      </div>
      <label className={field}>
        {t('summary')}
        <textarea value={summary} onChange={(e) => setSummary(e.target.value)} maxLength={4000} rows={4} className={`${fieldInput} h-auto py-2`} />
      </label>
      <span className="text-11.5 text-faint">{ai.enabled ? t('aiReady') : t(ai.reason === 'forbidden:projects:ai' ? 'aiForbidden' : ai.reason === 'forbidden:setting:project_ai' ? 'aiOff' : 'aiNotConnected')}</span>
      {pdf ? null : <div className={note}>{t('pdfOff')}</div>}
      {d.status_reports.length ? (
        <div className="flex flex-col gap-1 text-12">
          <span className="font-semibold text-muted">{t('earlier')}</span>
          {d.status_reports.map((r) => (
            <span key={r.id} className="flex justify-between gap-2 border-b border-tile py-[3px]">
              <span>{format.dateTime(new Date(r.requested_at), { day: 'numeric', month: 'short', year: 'numeric' })}{r.ai_drafted ? ` · ${t('aiDrafted')}` : ''}</span>
              <span className="text-muted">{t(`state.${r.state}`)}</span>
            </span>
          ))}
        </div>
      ) : null}
      <div className="flex flex-wrap justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={!pdf || !ai.enabled || !something || busy} onClick={() => create(true)} title={!pdf ? t('pdfOff') : ai.enabled ? undefined : t('aiNotConnected')}
          className={btnCancel + ' disabled:cursor-default disabled:opacity-60'}>{t('draftAi')}</button>
        <button type="button" disabled={!pdf || !something || busy} onClick={() => create(false)} title={pdf ? undefined : t('pdfOff')} className={btnConfirm}>{t('create')}</button>
      </div>
    </Modal>
  )
}
