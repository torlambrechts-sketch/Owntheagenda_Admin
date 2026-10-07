'use client'

import type { Route } from 'next'
import Link from 'next/link'
import { useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { recordHref } from '@/lib/records-href'
import type { Capabilities, MeetingBundle, Segment, Speaker } from '@/lib/data/meetings'
import { clock, minutes } from '@/lib/data/meetings-shared'
import { fetchTranscriptPage, mapSpeaker, planNextStep, regenerateRecap, retryTranscript, saveRecapNote } from '../actions'
import { Modal, btn32, btnCancel, btnConfirm, card18, eyebrowAmber, field, fieldInput, quiet, useFail, type Me } from './kit'

type Props = { bundle: MeetingBundle; capabilities: Capabilities; onChanged: () => Promise<void>; me: Me }

/** Transcript and recap (MTG-04, MTG-06; spec §2.3): the words as spoken (escaped as untrusted), the recap beside them. */
export function TranscriptTab({ bundle, capabilities, onChanged, me }: Props) {
  const t = useTranslations('meetings.transcript')
  const fail = useFail()
  const d = bundle.detail
  const tr = d.transcript
  const [segments, setSegments] = useState<Segment[]>(bundle.transcript?.segments ?? [])
  const [next, setNext] = useState<number | null>(bundle.transcript?.next ?? null)
  const [busy, setBusy] = useState(false)
  const box = useRef<HTMLDivElement>(null)
  const speakers = new Map((bundle.transcript?.speakers ?? []).map((s) => [s.label, s]))

  const more = async () => {
    if (next === null) return
    setBusy(true)
    const r = await fetchTranscriptPage({ id: d.id, cursor: next })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    setSegments((s) => [...s, ...r.page.segments])
    setNext(r.page.next)
  }
  const retry = async () => {
    if (!tr) return
    setBusy(true)
    const r = await retryTranscript(tr.id)
    setBusy(false)
    if (!r.ok) { fail(r); return }
    await onChanged()
  }
  const jump = (seq: number | null) => {
    if (seq === null) return
    const el = box.current?.querySelector<HTMLElement>(`[data-seq="${seq}"]`)
    if (!el || !box.current) return
    box.current.scrollTo({ top: el.offsetTop - box.current.offsetTop - 40, behavior: 'smooth' })
    el.classList.add('bg-highlight')
    setTimeout(() => el.classList.remove('bg-highlight'), 1600)
  }

  // ---- the left card: the transcript, or why there is none
  let left: React.ReactNode
  if (!tr) {
    const upcoming = !!d.starts_at && new Date(d.starts_at) > new Date() && !d.cancelled_at
    const why = d.bot.state === 'blocked'
      ? t('none.blocked', { reason: t(`reason.${d.bot.reason ?? 'other'}`) })
      : upcoming ? t('none.upcoming') : capabilities.meeting_bot === 'connected' ? t('none.notRecorded') : t('none.notConnected')
    left = (
      <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
        <b className="text-13.5">{d.bot.state === 'blocked' ? t('none.blockedTitle') : t('none.title')}</b>
        <span className={quiet}>{why}</span>
        {d.recording && d.recording.state !== 'deleted' ? <span className={quiet}>{t(`recording.${d.recording.state}`)}</span> : null}
        <span className={quiet}>{t('none.upload')}</span>
      </div>
    )
  } else {
    const facts = [tr.duration_s ? t('minutes', { n: minutes(tr.duration_s) }) : null, tr.speaker_count !== null ? t('speakers', { n: tr.speaker_count }) : null, tr.language].filter(Boolean).join(' · ')
    left = (
      <div ref={box} className={`${card18} relative flex max-h-[620px] flex-col gap-[10px] overflow-auto px-4 py-[14px]`}>
        <div className="flex items-center justify-between gap-2">
          <b className="text-13.5">{t('title')}</b>
          <span className="text-11.5 text-muted">{facts}</span>
        </div>
        {tr.source === 'upload' && tr.file_name ? <span className="text-11.5 text-faint">{t('uploaded', { file: tr.file_name })}</span> : null}
        {tr.state === 'processing' ? <span className={quiet}>{tr.source === 'upload' ? t('processingUpload') : t('processing')}</span> : null}
        {tr.state === 'failed' ? (
          <div className="flex flex-col gap-2">
            <span className="text-12.5 leading-[1.5] text-danger">{t('failed', { code: tr.error_code ?? '—' })}</span>
            {tr.source === 'upload' ? <span className={quiet}>{t('failedUpload')}</span> : (
              <>
                <button type="button" disabled={busy || !d.can_edit || capabilities.transcription !== 'connected'} onClick={() => void retry()} className={btn32}>{t('retry')}</button>
                {capabilities.transcription !== 'connected' ? <span className={quiet}>{t('retryNotConnected')}</span> : null}
              </>
            )}
          </div>
        ) : null}
        {segments.map((s) => {
          const sp = s.label ? speakers.get(s.label) : undefined
          const who = sp?.name ?? (sp?.email ? d.attendee_list.find((a) => a.email.toLowerCase() === sp.email)?.name : null) ?? s.label ?? t('unknownSpeaker')
          return (
            <div key={s.seq} data-seq={s.seq} className="grid gap-[10px] rounded-6 text-12.5 transition-colors [grid-template-columns:48px_minmax(0,1fr)]">
              <span className="pt-[2px] font-mono text-11 text-faint">{clock(s.start_ms)}</span>
              <span className="leading-[1.55]">
                <b style={{ color: sp?.kind === 'staff' ? '#191510' : '#2F5D2A' }}>{who}:</b>{' '}
                {s.redacted ? <i className="text-faint">{t('redacted')}</i> : s.text}
              </span>
            </div>
          )
        })}
        {next !== null ? <button type="button" disabled={busy} onClick={() => void more()} className={btn32}>{t('more')}</button> : null}
      </div>
    )
  }

  return (
    <div className="grid items-start gap-3 md:[grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)]">
      {left}
      <div className="flex flex-col gap-3">
        {tr ? <RecapCard bundle={bundle} capabilities={capabilities} onChanged={onChanged} onJump={jump} me={me} /> : null}
        {tr && tr.state === 'ready' && bundle.transcript?.speakers.length ? <SpeakersCard bundle={bundle} speakers={bundle.transcript.speakers} onChanged={onChanged} /> : null}
      </div>
    </div>
  )
}

function RecapCard({ bundle, capabilities, onChanged, onJump, me }: { bundle: MeetingBundle; capabilities: Capabilities; onChanged: () => Promise<void>; onJump: (seq: number | null) => void; me: Me }) {
  const t = useTranslations('meetings.recap')
  const fail = useFail()
  const flash = useToast()
  const d = bundle.detail
  const r = bundle.recap
  const [busy, setBusy] = useState(false)
  const [planning, setPlanning] = useState<number | null>(null)
  const aiOn = capabilities.ai === 'connected'
  const state = r?.state ?? 'none'

  const save = async () => {
    setBusy(true)
    const res = await saveRecapNote(d.id)
    setBusy(false)
    if (!res.ok) { fail(res); return }
    flash(t('savedToast', { entity: t(`entity.${res.entity}`) }))
    await onChanged()
  }
  const regenerate = async () => {
    if (!d.transcript) return
    setBusy(true)
    const res = await regenerateRecap(d.transcript.id)
    setBusy(false)
    if (!res.ok) { fail(res); return }
    flash(t('requestedToast'))
    await onChanged()
  }

  // the AI's actions: regenerate (owner, before the recap is saved) and draft a follow-up (AI and a mailbox); while the
  // provider is not connected both are shown disabled with one line that says why
  const canRegen = d.can_edit && !!r && !r.saved_at && d.transcript?.state === 'ready' && state !== 'requested'
  const regen = state === 'ready' || canRegen ? (
    <>
      <span className="flex flex-wrap gap-[6px]">
        {state === 'ready' ? <button type="button" disabled className={btn32}>{t('draft')}</button> : null}
        {canRegen ? <button type="button" disabled={busy || !aiOn} onClick={() => void regenerate()} className={btn32}>{t('regenerate')}</button> : null}
      </span>
      <span className="text-11.5 leading-[1.5] text-amber-ink">{aiOn ? t('draftNotConnected') : t('aiNotConnected')}</span>
    </>
  ) : null

  return (
    <div className="flex flex-col gap-2 rounded-18 border border-ink bg-highlight px-4 py-[14px]">
      <b className="text-13.5">{t('title')}</b>
      {state === 'none' ? <span className="text-12.5 leading-[1.5]">{t('waiting')}</span> : null}
      {state === 'not_connected' ? <span className="text-12.5 leading-[1.5]">{t('notConnected')}</span> : null}
      {state === 'requested' ? <span className="text-12.5 leading-[1.5]">{t('requested')}</span> : null}
      {state === 'failed' ? <span className="text-12.5 leading-[1.5] text-danger">{t('failed')}</span> : null}
      {state === 'ready' && r ? (
        <>
          <span className={eyebrowAmber}>{t('takeaways')}</span>
          {r.takeaways.map((x, i) => (
            <button key={i} type="button" onClick={() => onJump(x.seq)} disabled={x.seq === null} className="cursor-pointer border-none bg-transparent p-0 text-left text-12.5 leading-[1.5] text-ink disabled:cursor-default">· {x.text}</button>
          ))}
          {r.takeaways.length === 0 ? <span className="text-12.5 text-muted">{t('dash')}</span> : null}
          <span className={`${eyebrowAmber} mt-1`}>{t('nextSteps')}</span>
          {r.next_steps.map((x, i) => (
            <div key={i} className="flex items-start justify-between gap-2">
              <button type="button" onClick={() => onJump(x.seq)} disabled={x.seq === null} className="cursor-pointer border-none bg-transparent p-0 text-left text-12.5 leading-[1.5] text-ink disabled:cursor-default">○ {x.text}</button>
              {x.activity_id ? (
                <Link href={recordHref('activity', x.activity_id) as Route} className="whitespace-nowrap text-11.5 font-semibold">{t('planned')}</Link>
              ) : me.dealsAdd ? (
                <button type="button" onClick={() => setPlanning(i)} className="h-6 flex-none cursor-pointer whitespace-nowrap rounded-8 border border-line bg-surface px-2 text-11 font-semibold">{t('plan')}</button>
              ) : null}
            </div>
          ))}
          {r.saved_at && r.note ? (
            <Link href={recordHref(r.note.entity, r.note.record_id) as Route} className="text-12 font-bold">{t('saved', { entity: t(`entity.${r.note.entity}`) })}</Link>
          ) : r.save_target ? (
            <button type="button" disabled={busy} onClick={() => void save()} className={btn32}>{t('save')}</button>
          ) : (
            <span className="text-11.5 leading-[1.5] text-amber-ink">{t('saveNeedsLink')}</span>
          )}
        </>
      ) : null}
      {regen}
      {planning !== null && r ? <PlanModal meetingId={d.id} step={planning} text={r.next_steps[planning]?.text ?? ''} onClose={() => setPlanning(null)} onChanged={onChanged} /> : null}
    </div>
  )
}

/** Plan next activity (UF-07 step 6): an activity from a next step, linked like the meeting (meeting_next_step_activity). */
function PlanModal({ meetingId, step, text, onClose, onChanged }: { meetingId: string; step: number; text: string; onClose: () => void; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.plan')
  const fail = useFail()
  const flash = useToast()
  const tomorrow = new Date(Date.now() + 86400000)
  const [type, setType] = useState<'task' | 'call' | 'email' | 'meeting'>('task')
  const [date, setDate] = useState(`${tomorrow.getFullYear()}-${String(tomorrow.getMonth() + 1).padStart(2, '0')}-${String(tomorrow.getDate()).padStart(2, '0')}`)
  const [time, setTime] = useState('10:00')
  const [busy, setBusy] = useState(false)
  const save = async () => {
    const at = new Date(`${date}T${time}`)
    if (Number.isNaN(at.getTime())) return
    setBusy(true)
    const r = await planNextStep({ id: meetingId, step, type, startsAt: at.toISOString(), durationMin: 30 })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('done'))
    await onChanged()
    onClose()
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={text} onClose={onClose}>
      <label className={field}>
        {t('type')}
        <select value={type} onChange={(e) => setType(e.target.value as typeof type)} className={fieldInput}>
          {(['task', 'call', 'email', 'meeting'] as const).map((k) => <option key={k} value={k}>{t(`types.${k}`)}</option>)}
        </select>
      </label>
      <div className="grid grid-cols-2 gap-[10px]">
        <label className={field}>{t('date')}<input type="date" value={date} onChange={(e) => setDate(e.target.value)} className={fieldInput} /></label>
        <label className={field}>{t('time')}<input type="time" value={time} onChange={(e) => setTime(e.target.value)} className={fieldInput} /></label>
      </div>
      <p className="m-0 text-11.5 leading-[1.5] text-muted">{t('hint')}</p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={busy} onClick={() => void save()} className={btnConfirm}>{t('save')}</button>
      </div>
    </Modal>
  )
}

/** Speaker mapping (D-41): an uploaded file's raw labels tied to a colleague, a guest or an address (meeting_speaker_map). */
function SpeakersCard({ bundle, speakers, onChanged }: { bundle: MeetingBundle; speakers: Speaker[]; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.speakers')
  const fail = useFail()
  const d = bundle.detail
  const [busy, setBusy] = useState(false)
  const options: { value: string; label: string }[] = []
  for (const a of d.attendee_list) {
    if (a.staff_id) options.push({ value: `s:${a.staff_id}`, label: `${a.name ?? a.email} · ${t('colleague')}` })
    else if (a.person_id) options.push({ value: `p:${a.person_id}`, label: a.name ?? a.email })
    else options.push({ value: `e:${a.email}`, label: `${a.name ?? a.email} · ${t('notInCrm')}` })
  }
  if (d.owner && !options.some((o) => o.value === `s:${d.owner!.id}`)) options.unshift({ value: `s:${d.owner.id}`, label: `${d.owner.name} · ${t('colleague')}` })
  // a label mapped to an address only (a guest unknown to the CRM) reads back by its address (0050, R-MEETINGS-05)
  const current = (s: Speaker) => (s.staff_id ? `s:${s.staff_id}` : s.person_id ? `p:${s.person_id}` : s.email ? `e:${s.email}` : '')
  for (const s of speakers) {
    if (!s.staff_id && !s.person_id && s.email && !options.some((o) => o.value === `e:${s.email}`)) options.push({ value: `e:${s.email}`, label: `${s.email} · ${t('notInCrm')}` })
  }
  const shown = (s: Speaker) => {
    if (s.kind !== 'unknown') return s.name ?? t('hidden')
    if (!s.email) return t('unmapped')
    const a = d.attendee_list.find((x) => x.email.toLowerCase() === s.email)
    return `${a?.name ?? s.email} · ${t('notInCrm')}`
  }
  const change = async (s: Speaker, v: string) => {
    if (!d.transcript) return
    const [k, id] = [v.slice(0, 1), v.slice(2)]
    const values = k === 's' ? { staff_id: id } : k === 'p' ? { person_id: id } : k === 'e' ? { email: id } : {}
    setBusy(true)
    const r = await mapSpeaker({ transcript: d.transcript.id, label: s.label, values })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    await onChanged()
  }
  return (
    <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
      <b className="text-13.5">{t('title')}</b>
      {speakers.map((s) => (
        <div key={s.label} className="flex flex-wrap items-center justify-between gap-2 border-0 border-b border-solid border-line py-[5px] text-12.5">
          <span className="flex flex-col">
            <b style={{ color: s.kind === 'staff' ? '#191510' : '#2F5D2A' }}>{s.label}</b>
            <span className="text-11.5 text-muted">{shown(s)}</span>
          </span>
          {d.can_edit ? (
            <select aria-label={t('mapLabel', { label: s.label })} disabled={busy} value={current(s)} onChange={(e) => void change(s, e.target.value)} className="h-[30px] max-w-[220px] rounded-8 border border-line bg-canvas text-12">
              <option value="">{t('none')}</option>
              {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          ) : null}
        </div>
      ))}
      <span className="text-11.5 leading-[1.5] text-muted">{t('hint')}</span>
    </div>
  )
}
