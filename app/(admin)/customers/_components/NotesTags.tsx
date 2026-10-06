'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { deleteNote, saveNote, setTags } from '../actions'
import { useErrorText } from './useErrorText'

type Props = {
  org: { id: string; version: number; labels: string[] }
  notes: { id: string; body: string; by: string; when: string; pinned: boolean; mine: boolean }[]
  labels: { id: string; name: string }[]
  staff: { id: string; name: string }[]
  canDeleteOthers: boolean
}

/** Internal notes with @mentions, and the company's tags (Customers.dc.html, d.notes). */
export function NotesTags({ org, notes, labels, staff, canDeleteOthers }: Props) {
  const t = useTranslations('customers.notes')
  const err = useErrorText()
  const flash = useToast()
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [tags, setTagState] = useState(org.labels)
  const [version, setVersion] = useState(org.version)

  // «@Ingrid» or «@Ingrid Solberg» mentions a colleague by first or full name
  const mentionsIn = (text: string) => {
    const lower = text.toLowerCase()
    return staff.filter((s) => lower.includes(`@${s.name.toLowerCase()}`) || lower.includes(`@${s.name.split(' ')[0]!.toLowerCase()}`)).map((s) => s.id)
  }

  const add = async () => {
    const body = draft.trim()
    if (!body || busy) return
    setBusy(true)
    const mentions = mentionsIn(body)
    const r = await saveNote({ org: org.id, body, mentions })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    setDraft('')
    flash(mentions.length ? t('savedMention') : t('saved'))
  }

  const remove = async (id: string) => {
    const r = await deleteNote({ note: id })
    flash(r.ok ? t('deleted') : err(r.code))
  }

  const toggle = async (id: string) => {
    const next = tags.includes(id) ? tags.filter((x) => x !== id) : [...tags, id]
    const prev = tags
    setTagState(next)
    const r = await setTags({ org: org.id, labels: next, version })
    if (!r.ok) {
      setTagState(prev)
      return flash(err(r.code))
    }
    setVersion(r.version)
  }

  return (
    <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr))]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[22px] py-5">
        <div className="text-15 font-bold">{t('title')}</div>
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={t('placeholder')}
          aria-label={t('title')}
          className="min-h-[84px] resize-y rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 text-ink"
        />
        <button type="button" onClick={add} disabled={busy} className="h-8 cursor-pointer self-end rounded-9 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default">
          {t('add')}
        </button>
        {notes.map((n) => (
          <div key={n.id} className={`rounded-16 border border-line px-[14px] py-3 ${n.pinned ? 'bg-highlight' : 'bg-surface'}`}>
            <div className="mb-[5px] flex justify-between gap-2 text-12 text-muted">
              <span><b className="text-ink">{n.by}</b> · {n.when}</span>
              <span className="flex items-center gap-2">
                {n.pinned ? <span>{t('pinned')}</span> : null}
                {n.mine || canDeleteOthers ? (
                  <button type="button" onClick={() => remove(n.id)} className="cursor-pointer border-none bg-transparent p-0 text-12 font-semibold text-link">{t('delete')}</button>
                ) : null}
              </span>
            </div>
            <div className="whitespace-pre-wrap text-13 leading-[1.55]">{n.body}</div>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[22px] py-5">
        <div className="text-15 font-bold">{t('tags')}</div>
        <div className="flex flex-wrap gap-[6px]">
          {labels.map((l) => {
            const on = tags.includes(l.id)
            return (
              <button
                key={l.id}
                type="button"
                aria-pressed={on}
                onClick={() => toggle(l.id)}
                className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
              >
                {l.name}
              </button>
            )
          })}
        </div>
        <div className="text-12 text-muted">{t('tagsHint')}</div>
      </div>
    </div>
  )
}
