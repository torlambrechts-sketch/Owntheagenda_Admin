'use client'

import { useEffect, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money, type NumberFormat } from '@/lib/format'
import type { CrmDeal } from '@/lib/data/simple-crm'
import { canEditDeal, type CrmRights } from '@/lib/data/simple-crm-shared'
import { saveNote } from '../../deals/actions'

/**
 * The deal drawer (SimpleCRM.dc.html deal): stage and status over the title, the stage steps (a click moves the deal),
 * the facts from deal_detail, a note (note_save — a note, not a next step) and the deal's notes, Mark won / Mark lost.
 */
export function DealDrawer({ deal, rights, nf, onClose, onMove, onStatus, onNoteSaved }: {
  deal: CrmDeal
  rights: CrmRights
  nf: NumberFormat
  onClose: () => void
  onMove: (stage: string) => void
  onStatus: (status: 'won' | 'lost') => void
  onNoteSaved: () => void
}) {
  const t = useTranslations('simpleCrm')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const d = deal.detail
  const editable = canEditDeal(rights, d)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const panel = useRef<HTMLDivElement>(null)
  const closeRef = useRef(onClose)
  closeRef.current = onClose

  // the drawer takes focus when it opens and closes on Escape (a dialog above it closes first)
  useEffect(() => { panel.current?.focus() }, [d.id])
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') closeRef.current() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const stages = d.stages ?? []
  const idx = stages.findIndex((s) => s.id === d.stage_id)
  const thisYear = new Date().getFullYear()
  const day = (iso: string, dateOnly: boolean) => {
    const at = dateOnly ? new Date(`${iso}T12:00:00Z`) : new Date(iso)
    return format.dateTime(at, { day: 'numeric', month: 'short', ...(at.getFullYear() !== thisYear ? { year: 'numeric' } : {}), ...(dateOnly ? { timeZone: 'UTC' } : {}) })
  }
  const dash = '—'
  const person = d.person_detail
  const facts: [string, string][] = [
    [t('drawer.facts.value'), money(d.value, nf, d.currency)],
    [t('drawer.facts.account'), d.organization ?? dash],
    [t('drawer.facts.contact'), person ? (person.title ? t('drawer.contact', { name: person.name, title: person.title }) : person.name) : dash],
    [t('drawer.facts.owner'), d.owner?.name ?? dash],
    [t('drawer.facts.close'), d.expected_close_date ? day(d.expected_close_date, true) : dash],
    [t('drawer.facts.source'), d.source ?? dash],
  ]
  // a note needs sight of the deal (note_save); a read-only person reads
  const canNote = !rights.readOnly

  const save = async () => {
    if (!note.trim() || busy) return
    setBusy(true)
    const r = await saveNote({ deal: d.id, body: note })
    setBusy(false)
    if (!r.ok) { flash(te(r.code)); return }
    setNote('')
    flash(t('flash.saved'))
    onNoteSaved()
  }

  return (
    <div onClick={onClose} className="fixed inset-0 z-[80] flex justify-end bg-[rgba(25,21,16,.42)]">
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby="crm-deal-title"
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className="flex h-full w-[min(460px,100%)] flex-col gap-[14px] overflow-auto bg-surface px-6 py-[22px] outline-none"
      >
        <div className="flex justify-between gap-[10px]">
          <div>
            <div className="text-12 text-muted">{t('drawer.head', { stage: stages[idx]?.name ?? dash, status: t(`drawer.status.${d.status}`) })}</div>
            <div id="crm-deal-title" className="mt-[3px] font-serif text-22 font-semibold leading-[1.2]">{d.title}</div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t('drawer.close')}
            className="h-8 w-8 flex-none cursor-pointer whitespace-nowrap rounded-999 border border-ink bg-transparent"
          >
            ×
          </button>
        </div>

        <div className="flex gap-[3px]">
          {stages.map((s, i) => (
            <button
              key={s.id}
              type="button"
              title={s.name}
              aria-current={i === idx ? 'step' : undefined}
              disabled={!editable}
              onClick={() => onMove(s.id)}
              className={`h-[30px] flex-1 cursor-pointer overflow-hidden text-ellipsis whitespace-nowrap rounded-8 border-none px-1 text-10.5 disabled:cursor-default ${i < idx ? 'bg-ok-bg' : i === idx ? 'bg-primary' : 'bg-tile'} ${i === idx ? 'font-bold' : 'font-medium'}`}
            >
              {s.name}
            </button>
          ))}
        </div>

        {facts.map(([k, v]) => (
          <div key={k} className="flex justify-between gap-[10px] border-b border-tile py-[7px] text-13">
            <span className="text-muted">{k}</span>
            <b className="text-right">{v}</b>
          </div>
        ))}

        {canNote ? (
          <div className="flex flex-col gap-2">
            <label htmlFor="crm-note" className="text-13 font-bold">{t('drawer.note.heading')}</label>
            <textarea
              id="crm-note"
              value={note}
              maxLength={10000}
              onChange={(e) => setNote(e.target.value)}
              placeholder={t('drawer.note.placeholder')}
              className="min-h-[70px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13"
            />
            <button
              type="button"
              disabled={busy || !note.trim()}
              onClick={() => void save()}
              className="h-8 cursor-pointer self-end rounded-9 border border-ink bg-surface px-[13px] text-12 font-bold disabled:cursor-default"
            >
              {t('drawer.note.save')}
            </button>
          </div>
        ) : null}

        {deal.notes.map((n) => (
          <div key={n.id} className="rounded-11 border border-line bg-canvas px-[10px] py-2 text-12.5">
            <b>{n.author ?? dash}</b> <span className="text-faint">· {day(n.created_at, false)}</span>
            <div className="mt-[3px] whitespace-pre-wrap">{n.body}</div>
          </div>
        ))}

        {/* why the steps and the buttons below do nothing for this person: the database would refuse */}
        {!editable ? <span className="mt-auto text-12 text-muted">{t(rights.readOnly ? 'flash.viewOnly' : 'flash.notYours')}</span> : null}
        <div className={`${editable ? 'mt-auto' : ''} flex gap-2`}>
          <button
            type="button"
            disabled={!editable || d.status === 'won'}
            onClick={() => onStatus('won')}
            className="h-[42px] flex-1 cursor-pointer rounded-11 border border-link bg-ok-bg text-13 font-bold text-ok-ink disabled:cursor-default disabled:opacity-60"
          >
            {t('drawer.markWon')}
          </button>
          <button
            type="button"
            disabled={!editable || d.status === 'lost'}
            onClick={() => onStatus('lost')}
            className="h-[42px] flex-1 cursor-pointer rounded-11 border border-coral bg-peach text-13 font-bold text-rust-ink disabled:cursor-default disabled:opacity-60"
          >
            {t('drawer.markLost')}
          </button>
        </div>
      </div>
    </div>
  )
}
