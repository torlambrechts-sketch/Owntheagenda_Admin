'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { FindResult, Incident, PreviewResult, PrivacyJob, PrivacyRequest, RetentionRule, Subprocessor } from '@/lib/data/security'
import { foundIn, intervalUnit } from '@/lib/data/security-shared'
import { incidentSave, privacyApprove, privacyErase, privacyExport, privacyFind, privacyPreview, subprocessorSave } from '../actions'
import { Modal, dialogCancel, dialogDanger, dialogInput, sx, useErrorText, useGuarded, useWhen } from './kit'

type Person = FindResult['people'][number]

/**
 * Privacy compliance (SEC-11; SF-15; D-24, D-27): find a person, see where they are (privacy_preview's counts), export
 * or erase with the approval step (typed confirmation, fresh second factor, a second admin when second_admin is on).
 * Only names, addresses and counts are shown — never message bodies, never respondent text. An export or an erasure may
 * name the open personvern request it answers (privacy_requests_get, R-SECURITY-05); the job closes it when done. Then
 * the retention rules (each with the job that enforces it), the sub-processor register, the incident register and the
 * privacy jobs.
 */
export function PrivacyView({ retention, subprocessors, incidents, jobs, requests, now, meName }: {
  retention: RetentionRule[] | null
  subprocessors: Subprocessor[] | null
  incidents: Incident[] | null
  jobs: PrivacyJob[] | null
  requests: PrivacyRequest[] | null
  now: string
  meName: string
}) {
  const t = useTranslations('security.privacy')
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="flex flex-col gap-[14px]">
        <Finder requests={requests} />
        {jobs && jobs.length ? <Jobs jobs={jobs} now={now} meName={meName} /> : null}
      </div>
      <section className={sx.card} aria-label={t('retention.title')}>
        <div className={sx.headTitle}>{t('retention.title')}</div>
        {retention ? retention.map((r) => <RetentionRow key={r.key} r={r} />) : <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('loadFailed')}</div>}
      </section>
      <Subprocessors rows={subprocessors} />
      <Incidents rows={incidents} now={now} />
    </div>
  )
}

function Finder({ requests }: { requests: PrivacyRequest[] | null }) {
  const t = useTranslations('security.privacy.find')
  const err = useErrorText()
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [q, setQ] = useState('')
  const [found, setFound] = useState<FindResult | null>(null)
  const [picked, setPicked] = useState<{ person: Person; preview: PreviewResult } | null>(null)
  const [erase, setErase] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [request, setRequest] = useState<string | null>(null)

  const preview = async (person: Person) => {
    const r = await run(() => privacyPreview({ subject: { people: [person.id] } }))
    if (r.ok) setPicked({ person, preview: r.data })
  }
  const search = async (e: React.FormEvent) => {
    e.preventDefault()
    setPicked(null); setFound(null); setProblem(null); setRequest(null)
    if (q.trim().length < 3) return setProblem(t('tooShort'))
    const r = await run(() => privacyFind({ q: q.trim() }), { onError: (x) => { setProblem(err(x)); return true } })
    if (!r.ok) return
    setFound(r.data)
    // one person found: show where they are at once, as the design does
    if (r.data.people.length === 1) await preview(r.data.people[0]!)
  }

  const hits = found?.people ?? []
  const others = found ? [
    found.email_participants ? t('others.email_participants', { n: found.email_participants }) : null,
    found.tickets ? t('others.tickets', { n: found.tickets }) : null,
    found.consent_events ? t('others.consent_events', { n: found.consent_events }) : null,
    found.members.length ? t('others.members', { n: found.members.length }) : null,
  ].filter(Boolean) : []

  return (
    <section className={sx.cardPad} aria-label={t('title')}>
      {dialog}
      <b className="text-14">{t('title')}</b>
      <form onSubmit={search} role="search">
        <input
          className={`${sx.input} w-full`}
          placeholder={t('placeholder')}
          aria-label={t('placeholder')}
          value={q}
          onChange={(e) => { setQ(e.target.value); setProblem(null) }}
        />
        <button type="submit" className="sr-only" disabled={busy}>{t('search')}</button>
      </form>
      {problem ? <span role="alert" className="text-12 font-semibold text-danger">{problem}</span> : null}
      {found ? (
        <>
          {found.erased ? <div className={sx.band}>{t('erased')}</div> : null}
          {hits.length === 0 && !found.erased ? <span className="text-12.5 text-muted">{others.length ? t('noPersonButOthers', { list: others.join(', ') }) : t('noHit')}</span> : null}
          {hits.length > 1 && !picked ? (
            <div className="flex flex-col gap-[6px]">
              {hits.map((p) => (
                <button key={p.id} type="button" disabled={busy} onClick={() => preview(p)}
                  className="flex cursor-pointer flex-col items-start rounded-14 border border-solid border-line bg-canvas px-[13px] py-[9px] text-left text-12.5">
                  <b>{[p.name, p.email].filter(Boolean).join(' · ')}</b>
                  <span className="text-muted">{[p.organization, p.deleted ? t('deleted') : null].filter(Boolean).join(' · ') || '—'}</span>
                </button>
              ))}
            </div>
          ) : null}
          {picked ? (
            <PersonCard
              person={picked.person}
              preview={picked.preview}
              busy={busy}
              requests={requests}
              request={request}
              onRequest={setRequest}
              onExport={async () => {
                const r = await run((reason) => privacyExport({ subject: { people: [picked.person.id] }, request, reason }))
                if (r.ok) { flash(t('exported')); setRequest(null) }
              }}
              onErase={() => setErase(true)}
            />
          ) : null}
        </>
      ) : null}
      <div className="text-11.5 text-muted">{t('footnote')}</div>
      {erase && picked ? (
        <EraseDialog
          person={picked.person}
          preview={picked.preview}
          busy={busy}
          onClose={() => setErase(false)}
          onConfirm={async (confirm) => {
            const r = await run((reason) => privacyErase({ subject: { people: [picked.person.id] }, confirm, request, reason }))
            if (r.ok) {
              setErase(false); setPicked(null); setFound(null); setQ(''); setRequest(null)
              flash(r.state === 'done' ? t('erasedDone', { n: r.rows }) : t('erasedPending'))
            }
            return r
          }}
        />
      ) : null}
    </section>
  )
}

function PersonCard({ person, preview, busy, requests, request, onRequest, onExport, onErase }: {
  person: Person; preview: PreviewResult; busy: boolean; requests: PrivacyRequest[] | null; request: string | null; onRequest: (id: string | null) => void
  onExport: () => void; onErase: () => void
}) {
  const t = useTranslations('security.privacy.find')
  const c = useTranslations('security.privacy.counts')
  const list = foundIn(preview.counts).map((x) => c(x.key, { n: x.n }))
  return (
    <div className="flex flex-col gap-[6px] rounded-14 border border-solid border-line bg-canvas px-[13px] py-[11px] text-12.5">
      <b>{[person.name, person.email].filter(Boolean).join(' · ')}</b>
      <span className="text-muted">{list.length ? t('foundIn', { list: list.join(', ') }) : t('foundNothing')}</span>
      {preview.product_user ? <div className={sx.bandDanger}>{t('productUser')}</div> : null}
      <RequestPicker requests={requests} value={request} onChange={onRequest} disabled={busy} />
      <div className="flex flex-wrap gap-[6px]">
        <button type="button" className={sx.btn30} disabled={busy} onClick={onExport}>{t('export')}</button>
        <button type="button" className={sx.btnDanger30} disabled={busy || preview.product_user || preview.emails > 1} onClick={onErase}>{t('erase')}</button>
      </div>
      {preview.emails > 1 ? <span className="text-11.5 text-muted">{t('oneAddress')}</span> : null}
    </div>
  )
}

/**
 * Which open personvern request this export or erasure answers (SF-15): the ticket's number, the kind and the 30-day due
 * date privacy_requests_get returns. None is the default; with no open request the line says so.
 */
function RequestPicker({ requests, value, onChange, disabled }: { requests: PrivacyRequest[] | null; value: string | null; onChange: (id: string | null) => void; disabled: boolean }) {
  const t = useTranslations('security.privacy.find')
  const format = useFormatter()
  if (requests === null) return <span className="text-11.5 text-muted">{t('requestsFailed')}</span>
  if (requests.length === 0) return <span className="text-11.5 text-muted">{t('requestsNone')}</span>
  const label = (r: PrivacyRequest) => {
    const v = {
      ref: r.ticket_number !== null ? `T-${r.ticket_number}` : t('requestNoTicket'),
      kind: t(`requestKind.${r.kind}`),
      date: format.dateTime(new Date(r.due_at), { day: 'numeric', month: 'short', year: 'numeric' }),
    }
    return [t(r.overdue ? 'requestOverdue' : 'requestOption', v), r.organization].filter(Boolean).join(' · ')
  }
  return (
    <label className={sx.label}>
      {t('request')}
      <select className={`${sx.inputSm} w-full`} value={value ?? ''} disabled={disabled} onChange={(e) => onChange(e.target.value || null)}>
        <option value="">{t('requestNone')}</option>
        {requests.map((r) => <option key={r.id} value={r.id}>{label(r)}</option>)}
      </select>
      {value ? <span className="font-normal">{t('requestHint')}</span> : null}
    </label>
  )
}

/** The approval step: what goes, the irreversible wording, the typed confirmation, and the second admin when it is on. */
function EraseDialog({ person, preview, busy, onClose, onConfirm }: {
  person: Person
  preview: PreviewResult
  busy: boolean
  onClose: () => void
  onConfirm: (confirm: string) => Promise<{ ok: boolean; code?: string; detail?: string | null }>
}) {
  const t = useTranslations('security.privacy.erase')
  const c = useTranslations('security.privacy.counts')
  const [typed, setTyped] = useState('')
  const expect = preview.confirm === 'email' ? person.email ?? '' : person.name
  const list = foundIn(preview.counts)
  return (
    <Modal eyebrow={t('eyebrow')} title={t('title', { name: person.name })} onClose={onClose} width={480}>
      <div className={sx.bandDanger}>{t('irreversible')}</div>
      {list.length ? (
        <ul className="m-0 flex list-disc flex-col gap-[2px] pl-5 text-13">
          {list.map((x) => <li key={x.key}>{c(x.key, { n: x.n })}</li>)}
        </ul>
      ) : <span className="text-13 text-muted">{t('nothing')}</span>}
      <span className="text-12.5 text-muted">{t('tombstone')}</span>
      {preview.second_admin ? <div className={sx.band}>{t('secondAdmin')}</div> : null}
      <label className="flex flex-col gap-1 text-12 font-semibold text-muted">
        {t(preview.confirm === 'email' ? 'typeEmail' : 'typeName', { value: expect })}
        <input className={dialogInput} value={typed} autoComplete="off" onChange={(e) => setTyped(e.target.value)} />
      </label>
      <span className="text-11.5 text-muted">{t('freshMfa')}</span>
      <div className="flex justify-end gap-2">
        <button type="button" className={dialogCancel} onClick={onClose}>{t('cancel')}</button>
        <button type="button" className={dialogDanger} disabled={busy || typed.trim().toLowerCase() !== expect.trim().toLowerCase()} onClick={() => onConfirm(typed.trim())}>
          {t(preview.second_admin ? 'request' : 'confirm')}
        </button>
      </div>
    </Modal>
  )
}

function Jobs({ jobs, now, meName }: { jobs: PrivacyJob[]; now: string; meName: string }) {
  const t = useTranslations('security.privacy.jobs')
  const c = useTranslations('security.privacy.counts')
  const when = useWhen(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  return (
    <section className={sx.card} aria-label={t('title')}>
      {dialog}
      <div className={sx.headTitle}>{t('title')}</div>
      {jobs.slice(0, 20).map((j) => {
        const total = Object.values(j.preview).reduce((a, b) => a + b, 0)
        const mayApprove = j.kind === 'erasure' && j.state === 'previewed' && j.created_by !== meName
        return (
          <div key={j.id} className={`${sx.row} flex flex-col gap-1 py-[9px] text-12.5`}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <b>{t(`kind.${j.kind}`)} · {t(`state.${j.kind}.${j.state}`)}</b>
              <span className="text-11.5 text-muted">{when(j.created_at)}{j.created_by ? ` · ${j.created_by}` : ''}</span>
            </div>
            <span className="text-12 text-muted">
              {t('rows', { n: total })}
              {j.kind === 'export' && j.state === 'done' ? ` · ${t('downloadUnavailable')}` : ''}
              {j.kind === 'export' && (j.state === 'approved' || j.state === 'running') ? ` · ${t('waitingWorker')}` : ''}
              {j.approved_by ? ` · ${t('approvedBy', { name: j.approved_by })}` : ''}
              {j.error ? ` · ${t('failedJob')}` : ''}
            </span>
            {j.kind === 'erasure' && j.state === 'previewed' ? (
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-11.5 text-muted">{foundIn(j.preview).slice(0, 4).map((x) => c(x.key, { n: x.n })).join(', ')}</span>
                {mayApprove ? (
                  <button type="button" className={sx.btnDanger30} disabled={busy} onClick={async () => {
                    const r = await run(() => privacyApprove({ job: j.id }))
                    if (r.ok) flash(t('approved', { n: r.rows }))
                  }}>{t('approve')}</button>
                ) : <span className="text-11.5 text-muted">{t('waitingSecond')}</span>}
              </div>
            ) : null}
          </div>
        )
      })}
    </section>
  )
}

function RetentionRow({ r }: { r: RetentionRule }) {
  const t = useTranslations('security.privacy.retention')
  const u = intervalUnit(r.keep)
  // a rule tied to a setting reads the setting's period (R-SECURITY-07); no period there means kept until deleted
  const keep = u ? t(`unit.${u.unit}`, { n: u.n }) : r.keep === null && r.setting ? t('kept') : '—'
  const v = r.basis === 'product' ? t('product')
    : !r.in_force ? t('notEnforced', { keep })
    : t(`v.${r.key}`, { keep })
  return (
    <div className={`${sx.row} flex justify-between gap-[10px] py-[9px] text-12.5`}>
      <span>{t(`k.${r.key}`)}</span>
      <b className="text-right">{v}</b>
    </div>
  )
}

function Subprocessors({ rows }: { rows: Subprocessor[] | null }) {
  const t = useTranslations('security.privacy.subs')
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [editing, setEditing] = useState<Subprocessor | 'new' | null>(null)
  return (
    <section className={sx.card} aria-label={t('title')}>
      {dialog}
      <div className={sx.head}>
        <b className="text-14">{t('title')}</b>
        <span className="text-12 text-muted">{t('source')}</span>
      </div>
      {rows === null ? <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('loadFailed')}</div> : null}
      {(rows ?? []).filter((s) => !s.removed_at).map((s) => editing !== 'new' && editing?.id === s.id ? (
        <SubForm key={s.id} row={s} busy={busy} onCancel={() => setEditing(null)} onSave={async (v) => {
          const r = await run(() => subprocessorSave({ id: s.id, values: v, version: s.version }))
          if (r.ok) { setEditing(null); flash(t('saved')) }
        }} />
      ) : (
        <button key={s.id} type="button" onClick={() => setEditing(s)}
          className={`${sx.row} grid w-full cursor-pointer gap-[10px] bg-transparent py-[9px] text-left text-12.5 [grid-template-columns:minmax(0,1fr)_minmax(0,1.2fr)_120px]`}>
          <b>{s.name}</b>
          <span className="text-muted">{s.purpose}</span>
          <span className={s.region ? '' : 'text-muted'}>{s.region ?? t('noRegion')}{s.public ? '' : ` · ${t('notPublic')}`}</span>
        </button>
      ))}
      {editing === 'new' ? (
        <SubForm row={null} busy={busy} onCancel={() => setEditing(null)} onSave={async (v) => {
          const r = await run(() => subprocessorSave({ id: null, values: v }))
          if (r.ok) { setEditing(null); flash(t('saved')) }
        }} />
      ) : (
        <div className="px-[18px] py-[10px]"><button type="button" className={sx.btn} onClick={() => setEditing('new')}>{t('add')}</button></div>
      )}
    </section>
  )
}

function SubForm({ row, busy, onCancel, onSave }: { row: Subprocessor | null; busy: boolean; onCancel: () => void; onSave: (v: Record<string, unknown>) => void }) {
  const t = useTranslations('security.privacy.subs')
  const [name, setName] = useState(row?.name ?? '')
  const [purpose, setPurpose] = useState(row?.purpose ?? '')
  const [region, setRegion] = useState(row?.region ?? '')
  const [pub, setPub] = useState(row?.public ?? false)
  const [since, setSince] = useState(row?.in_use_since ?? new Date().toISOString().slice(0, 10))
  const valid = name.trim() && purpose.trim() && (!pub || region.trim())
  return (
    <form className={`${sx.row} flex flex-col gap-2 bg-canvas py-[10px]`} onSubmit={(e) => { e.preventDefault(); if (valid) onSave({ name, purpose, region: region.trim() || null, public: pub, in_use_since: since }) }}>
      <div className="flex flex-wrap gap-2">
        <label className={`${sx.label} min-w-[140px] flex-1`}>{t('name')}<input className={sx.inputSm} maxLength={80} value={name} onChange={(e) => setName(e.target.value)} /></label>
        <label className={`${sx.label} min-w-[160px] flex-1`}>{t('purpose')}<input className={sx.inputSm} maxLength={200} value={purpose} onChange={(e) => setPurpose(e.target.value)} /></label>
      </div>
      <div className="flex flex-wrap items-end gap-2">
        <label className={`${sx.label} min-w-[140px] flex-1`}>{t('region')}<input className={sx.inputSm} maxLength={60} value={region} placeholder={t('regionHint')} onChange={(e) => setRegion(e.target.value)} /></label>
        <label className={sx.label}>{t('since')}<input className={sx.inputSm} type="date" value={since} onChange={(e) => setSince(e.target.value)} /></label>
        <label className="flex items-center gap-1 pb-[6px] text-12"><input type="checkbox" checked={pub} onChange={(e) => setPub(e.target.checked)} />{t('public')}</label>
      </div>
      {pub && !region.trim() ? <span className="text-11.5 font-semibold text-danger">{t('publicNeedsRegion')}</span> : null}
      <div className="flex justify-end gap-2">
        <button type="button" className={`${sx.btn30} border-line font-semibold`} onClick={onCancel}>{t('cancel')}</button>
        <button type="submit" className={`${sx.btn30} bg-primary`} disabled={busy || !valid}>{t('save')}</button>
      </div>
    </form>
  )
}

const STATE_INK: Record<string, string> = { investigating: 'text-warn-ink', assessed_not_notifiable: 'text-link', notified: 'text-link', closed: 'text-link' }

function Incidents({ rows, now }: { rows: Incident[] | null; now: string }) {
  const t = useTranslations('security.privacy.incidents')
  const when = useWhen(now)
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [adding, setAdding] = useState(false)
  return (
    <section className={sx.card} aria-label={t('title')}>
      {dialog}
      <div className={`${sx.head} items-center`}>
        <b className="text-14">{t('title')}</b>
        <button type="button" className={sx.btn} onClick={() => setAdding(true)}>{t('log')}</button>
      </div>
      {adding ? (
        <IncidentForm busy={busy} onCancel={() => setAdding(false)} onSave={async (v) => {
          const r = await run(() => incidentSave({ id: null, values: v }))
          if (r.ok) { setAdding(false); flash(t('logged')) }
        }} />
      ) : null}
      {rows === null ? <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('loadFailed')}</div>
        : rows.length === 0 ? <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('empty')}</div>
        : rows.map((i) => {
          const open = i.state === 'investigating'
          const clock = open ? t('clock', { h: i.hours_left ?? 0 })
            : i.closed_at ? t('closedClock', { logged: when(i.logged_at, { time: false }), closed: when(i.closed_at, { time: false }) })
            : i.notified_at ? t('notifiedClock', { logged: when(i.logged_at, { time: false }), notified: when(i.notified_at, { time: false }) })
            : t('loggedClock', { logged: when(i.logged_at, { time: false }) })
          return (
            <div key={i.id} className={`${sx.row} flex flex-col gap-[5px] py-[11px] text-12.5`}>
              <div className="flex flex-wrap justify-between gap-2">
                <b>{i.title}</b>
                <select aria-label={t('stateFor', { title: i.title })} value={i.state} disabled={busy}
                  className={`cursor-pointer border-0 bg-transparent p-0 text-right text-12.5 font-bold ${STATE_INK[i.state]}`}
                  onChange={async (e) => { const r = await run(() => incidentSave({ id: i.id, values: { state: e.target.value }, version: i.version })); if (r.ok) flash(t('saved')) }}>
                  {(['investigating', 'assessed_not_notifiable', 'notified', 'closed'] as const).map((s) => <option key={s} value={s}>{t(`state.${s}`)}</option>)}
                </select>
              </div>
              {i.summary ? <span className="text-muted">{i.summary}</span> : null}
              <span className="h-[6px] overflow-hidden rounded-999 bg-tile">
                <span className={`block h-full ${open ? 'bg-warn' : 'bg-ok'}`} style={{ width: `${i.elapsed_pct}%` }} />
              </span>
              <span className="text-11.5 text-muted">{clock}</span>
            </div>
          )
        })}
    </section>
  )
}

function IncidentForm({ busy, onCancel, onSave }: { busy: boolean; onCancel: () => void; onSave: (v: Record<string, unknown>) => void }) {
  const t = useTranslations('security.privacy.incidents.form')
  const [title, setTitle] = useState('')
  const [summary, setSummary] = useState('')
  const [detected, setDetected] = useState('')
  const [personal, setPersonal] = useState(false)
  return (
    <form className={`${sx.row} flex flex-col gap-2 bg-canvas py-[10px]`} onSubmit={(e) => {
      e.preventDefault()
      if (!title.trim()) return
      onSave({ title: title.trim(), summary, personal_data: personal, ...(detected ? { detected_at: new Date(detected).toISOString() } : {}) })
    }}>
      <label className={sx.label}>{t('title')}<input className={sx.inputSm} maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} /></label>
      <label className={sx.label}>{t('summary')}
        <textarea className="min-h-[70px] rounded-9 border border-solid border-line bg-canvas p-2 text-12.5 text-ink" maxLength={2000} value={summary} onChange={(e) => setSummary(e.target.value)} />
      </label>
      <span className="text-11.5 text-muted">{t('summaryHint')}</span>
      <div className="flex flex-wrap items-end gap-2">
        <label className={sx.label}>{t('detected')}<input className={sx.inputSm} type="datetime-local" value={detected} onChange={(e) => setDetected(e.target.value)} /></label>
        <label className="flex items-center gap-1 pb-[6px] text-12"><input type="checkbox" checked={personal} onChange={(e) => setPersonal(e.target.checked)} />{t('personal')}</label>
      </div>
      <span className="text-11.5 text-muted">{t('detectedHint')}</span>
      <div className="flex justify-end gap-2">
        <button type="button" className={`${sx.btn30} border-line font-semibold`} onClick={onCancel}>{t('cancel')}</button>
        <button type="submit" className={`${sx.btn30} bg-primary`} disabled={busy || !title.trim()}>{t('save')}</button>
      </div>
    </form>
  )
}
