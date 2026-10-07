'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import type { BoardRow, Field, ProjectBundle, ProjectsBase } from '@/lib/data/projects'
import { dateOnly, HEALTH_BG, HEALTHS, type Health, type Rights } from '@/lib/data/projects-shared'
import {
  closeProject, deleteFile, deleteProject, linkDeal, moveProject, requestBrief, requestSummary, reviewBrief, saveNote, saveProject,
  setFollow, setHealth, templateFromProject,
} from '../actions'
import { useDates } from './Board'
import { useExporter } from './ExportMenu'
import { WorkItems } from './WorkItems'
import { StatusReportModal } from './StatusReportModal'
import { recordDownload, recordUploadAbandon, recordUploadBegin, recordUploadDone } from '@/lib/storage/actions'
import { acceptFor, putSigned, RECORD_MAX_BYTES, RECORD_TYPES, typeFor } from '@/lib/storage/mime'
import { btnCancel, btnConfirm, card, field, fieldInput, inputSmall, Modal, Picker } from './kit'

type Props = { bundle: ProjectBundle; base: ProjectsBase; boards: BoardRow[]; rights: Rights; onClose: () => void; onChanged: () => void }
type R = { ok: true } | { ok: false; code: RpcCode; detail?: string | null }

const eyebrow = 'text-11 font-bold uppercase tracking-eyebrow text-muted'

/**
 * The project drawer (Projects.dc.html, proj): header with health and the status report, the AI summary, work items,
 * notes with mentions and linked mail, files and sharing; then the record's details (custom fields, labels), linked
 * deals and its history (D-41). A closed project is read-only with a Reopen action.
 */
export function ProjectDrawer({ bundle, base, boards, rights, onClose, onChanged }: Props) {
  const t = useTranslations('projects.drawer')
  const tp = useTranslations('projects')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const dates = useDates()
  const d = bundle.detail
  const editable = d.can_edit
  const open = d.status === 'open'
  const [modal, setModal] = useState<null | 'report' | 'template' | 'delete'>(null)
  const exportItems = useExporter(null, d.id, d.name)
  const panel = useRef<HTMLDivElement>(null)
  useEffect(() => { panel.current?.focus() }, [d.id])
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && !modal) onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [modal, onClose])

  const after = async (p: R | Promise<R>, msg?: string) => {
    const r = await p
    if (!r.ok) { flash(te(r.code)); return false }
    if (msg) flash(msg)
    onChanged()
    return true
  }
  const save = (values: Record<string, unknown>, msg?: string) => after(saveProject({ id: d.id, version: d.version, values }), msg ?? t('saved'))

  const more = async (a: string) => {
    if (a === 'done' || a === 'canceled' || a === 'open') await after(closeProject({ id: d.id, status: a, version: d.version }), t(`closed.${a}`))
    if (a === 'csv' || a === 'xlsx') await exportItems(a)
    if (a === 'template') setModal('template')
    if (a === 'delete') setModal('delete')
    if (a === 'follow') await after(setFollow({ id: d.id, on: !d.sharing.following }), d.sharing.following ? t('unfollowed') : t('followed'))
  }

  const primary = d.deals.find((x) => x.is_primary) ?? d.deals[0] ?? null
  const sub = [d.organization, d.person, primary ? `◆ ${primary.title}${d.deals.length > 1 ? ` +${d.deals.length - 1}` : ''}` : null, dates(d.starts_on, d.ends_on, true)].filter(Boolean).join(' · ')
  const allPhases = boards.flatMap((b) => b.phases.map((p) => ({ ...p, board: b.name, boardId: b.id })))
  const healthBg = d.health ? HEALTH_BG[d.health] : 'bg-surface'

  return (
    <div onClick={onClose} className="fixed inset-0 z-[80] flex justify-end bg-[rgba(25,21,16,.42)]">
      <div
        ref={panel}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-labelledby="project-title"
        onClick={(e) => e.stopPropagation()}
        className="flex h-full w-[min(900px,100%)] flex-col gap-3 overflow-auto bg-canvas px-[22px] py-5 outline-none [&>*]:shrink-0"
      >
        <div className="flex flex-wrap items-start gap-[10px]">
          <div className="min-w-0 flex-[1_1_300px]">
            <div className="text-12 text-muted">{t('head', { board: d.board?.name ?? '—', phase: d.phase?.name ?? '—', owner: d.owner?.name ?? '—' })}</div>
            <div id="project-title" className="mt-[2px] font-serif text-23 font-semibold">{d.name}</div>
            {sub ? <div className="mt-[3px] text-12.5 text-ink-2">{sub}</div> : null}
          </div>
          <select
            aria-label={t('health')}
            value={d.health ?? ''}
            disabled={!editable || !open}
            onChange={(e) => void after(setHealth({ id: d.id, health: (e.target.value || null) as Health | null, version: d.version }), t('healthSet'))}
            className={`h-[34px] rounded-10 border border-ink text-12.5 font-bold text-ink ${healthBg}`}
          >
            {HEALTHS.map((h) => <option key={h} value={h}>{tp(`health.${h}`)}</option>)}
            <option value="">{tp('health.none')}</option>
          </select>
          <button type="button" onClick={() => setModal('report')} className="h-[34px] cursor-pointer rounded-10 border border-ink bg-surface px-3 text-12.5 font-bold">{t('statusReport')}</button>
          <select aria-label={t('more.label')} value="" onChange={(e) => void more(e.target.value)} className="h-[34px] rounded-10 border border-line bg-surface text-12.5 text-ink">
            <option value="">{t('more.label')}</option>
            <option value="follow">{d.sharing.following ? t('more.unfollow') : t('more.follow')}</option>
            {editable && open ? <option value="done">{t('more.done')}</option> : null}
            {editable && open ? <option value="canceled">{t('more.canceled')}</option> : null}
            {editable && !open ? <option value="open">{t('more.reopen')}</option> : null}
            {rights.add ? <option value="template">{t('more.template')}</option> : null}
            {rights.exportRows ? <option value="csv">{t('more.exportCsv')}</option> : null}
            {rights.exportRows ? <option value="xlsx">{t('more.exportXlsx')}</option> : null}
            {rights.del ? <option value="delete">{t('more.delete')}</option> : null}
          </select>
          <button type="button" aria-label={tp('close')} onClick={onClose} className="h-8 w-8 cursor-pointer rounded-999 border border-ink bg-transparent">×</button>
        </div>

        {!open ? (
          <div className="flex flex-wrap items-center gap-3 rounded-14 border border-line bg-beige px-4 py-[10px] text-12.5">
            <b>{t(`closedBanner.${d.status}`, { date: d.closed_at ? format.dateTime(new Date(d.closed_at), { day: 'numeric', month: 'short', year: 'numeric' }) : '' })}</b>
            <span className="text-muted">{t('readOnly')}</span>
            {editable ? <button type="button" onClick={() => void more('open')} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-surface px-[10px] text-12 font-bold">{t('more.reopen')}</button> : null}
          </div>
        ) : null}

        <AiBanner bundle={bundle} rights={rights} editable={editable && open} onAfter={after} />

        <WorkItems detail={d} base={base} rights={rights} editable={editable} onChanged={onChanged} />

        <div className="grid gap-3 [grid-template-columns:minmax(0,1fr)] sm:[grid-template-columns:1fr_1fr]">
          <Notes bundle={bundle} base={base} onAfter={after} />
          <Files bundle={bundle} onAfter={after} />
        </div>

        <div className="grid gap-3 [grid-template-columns:minmax(0,1fr)] sm:[grid-template-columns:1fr_1fr]">
          <Details bundle={bundle} base={base} editable={editable && open} allPhases={allPhases} onSave={save} onAfter={after} />
          <Deals bundle={bundle} rights={rights} editable={editable} onAfter={after} />
        </div>

        <History bundle={bundle} base={base} allPhases={allPhases} />
      </div>

      {modal === 'report' ? <StatusReportModal bundle={bundle} onClose={() => setModal(null)} onAfter={after} /> : null}
      {modal === 'template' ? <SaveTemplate projectId={d.id} name={d.name} onClose={() => setModal(null)} /> : null}
      {modal === 'delete' ? (
        <Modal eyebrow={t('deleteEyebrow')} title={t('deleteTitle', { name: d.name })} onClose={() => setModal(null)}>
          <p className="m-0 text-13 text-muted">{t('deleteBody')}</p>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setModal(null)} className={btnCancel}>{t('cancel')}</button>
            <button type="button" onClick={async () => { if (await after(deleteProject(d.id), t('deleted'))) { setModal(null); onClose() } }} className={btnConfirm}>{t('deleteConfirm')}</button>
          </div>
        </Modal>
      ) : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
function AiBanner({ bundle, rights, editable, onAfter }: { bundle: ProjectBundle; rights: Rights; editable: boolean; onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean> }) {
  const t = useTranslations('projects.ai')
  const tp = useTranslations('projects')
  const format = useFormatter()
  const d = bundle.detail
  const ai = d.ai
  const s = ai.summary
  const reason = ai.reason === 'forbidden:projects:ai' || !rights.ai ? 'forbidden' : ai.reason === 'forbidden:setting:project_ai' ? 'off' : 'notConnected'
  return (
    <div className="flex items-start gap-3 rounded-18 bg-ink px-4 py-[14px] text-canvas">
      {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
      <img src="/brand/assistant.png" alt="" width={26} height={26} className="rounded-8 bg-canvas" />
      <span className="flex flex-1 flex-col gap-2 text-12.5 leading-[1.55] text-tile">
        {!ai.enabled ? (
          <span><b className="text-primary">{t('title')}</b> {t(`reason.${reason}`)}</span>
        ) : s ? (
          <>
            <span>
              {s.suggested_health ? <b className="text-primary">{t('suggested', { health: tp(`health.${s.suggested_health}`) })}</b> : null} {s.summary}
            </span>
            {s.recommendations.length ? <span>{t('recommend', { list: s.recommendations.join(' · ') })}</span> : null}
            <span className="flex flex-wrap items-center gap-2 text-11.5 text-line-strong">
              {s.generated_at ? t('generated', { when: format.dateTime(new Date(s.generated_at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }) : null}
              {editable && s.suggested_health && s.suggested_health !== d.health ? (
                <button type="button" onClick={() => void onAfter(setHealth({ id: d.id, health: s.suggested_health, version: d.version, summary: s.id }), t('applied'))} className="h-[26px] cursor-pointer rounded-8 border border-primary bg-primary px-[9px] text-11.5 font-bold text-ink">{t('use')}</button>
              ) : null}
              <button type="button" disabled={ai.pending} onClick={() => void onAfter(requestSummary(d.id), t('requested'))} className="h-[26px] cursor-pointer rounded-8 border border-line-strong bg-transparent px-[9px] text-11.5 font-semibold text-canvas disabled:opacity-60">{ai.pending ? t('pending') : t('regenerate')}</button>
            </span>
          </>
        ) : (
          <span className="flex flex-wrap items-center gap-2">
            <span><b className="text-primary">{t('title')}</b> {ai.pending ? t('pendingBody') : t('none')}</span>
            {!ai.pending ? <button type="button" onClick={() => void onAfter(requestSummary(d.id), t('requested'))} className="h-[26px] cursor-pointer rounded-8 border border-primary bg-primary px-[9px] text-11.5 font-bold text-ink">{t('generate')}</button> : null}
          </span>
        )}
      </span>
    </div>
  )
}

// ---------------------------------------------------------------------------
function Notes({ bundle, base, onAfter }: { bundle: ProjectBundle; base: ProjectsBase; onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean> }) {
  const t = useTranslations('projects.notes')
  const format = useFormatter()
  const d = bundle.detail
  const [draft, setDraft] = useState('')
  const [mentioned, setMentioned] = useState<string[]>([])
  const when = (iso: string) => {
    const dt = new Date(iso)
    const day = (x: Date) => Math.floor((x.getTime() - x.getTimezoneOffset() * 60000) / 86_400_000)
    const diff = day(new Date()) - day(dt)
    if (diff === 0) return format.dateTime(dt, { hour: '2-digit', minute: '2-digit' })
    if (diff === 1) return t('yesterday')
    return format.dateTime(dt, { day: 'numeric', month: 'short' })
  }
  const first = (name: string) => name.split(/\s+/)[0] ?? name
  const mention = (id: string) => {
    const s = base.staff.find((x) => x.id === id)
    if (!s) return
    setDraft((v) => `${v}${v && !v.endsWith(' ') ? ' ' : ''}@${first(s.name)} `)
    setMentioned((m) => (m.includes(id) ? m : [...m, id]))
  }
  const submit = async () => {
    const body = draft.trim()
    if (!body) return
    // a mention counts while its @Name is still in the text
    const mentions = mentioned.filter((id) => { const s = base.staff.find((x) => x.id === id); return s && body.includes(`@${first(s.name)}`) })
    if (await onAfter(saveNote({ id: d.id, body, mentions }), mentions.length ? t('savedMentioned', { count: mentions.length }) : t('saved'))) { setDraft(''); setMentioned([]) }
  }
  return (
    <div className={`${card} flex flex-col gap-2 px-4 py-[14px]`}>
      <b className="text-13.5">{t('title')}</b>
      <textarea aria-label={t('placeholder')} value={draft} onChange={(e) => setDraft(e.target.value)} placeholder={t('placeholder')} maxLength={10000} className="min-h-[60px] rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5" />
      <span className="flex flex-wrap items-center gap-[6px]">
        <select aria-label={t('mention')} value="" onChange={(e) => { if (e.target.value) mention(e.target.value) }} className={inputSmall}>
          <option value="">{t('mention')}</option>
          {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
        <span className="flex-1" />
        <button type="button" disabled={!draft.trim()} onClick={() => void submit()} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:cursor-default disabled:opacity-60">{t('add')}</button>
      </span>
      {d.timeline.map((n) => (
        <div key={`${n.kind}-${n.id}`} className="border-b border-line py-[7px] text-12.5 leading-[1.5]">
          <b>{n.kind === 'email' ? t('fromEmail', { name: n.author ?? '—' }) : (n.author ?? '—')}</b> · <span className="text-muted">{when(n.at)}</span>
          <div className="whitespace-pre-wrap break-words" title={n.kind === 'email' ? (n.subject ?? undefined) : undefined}>{n.kind === 'note' ? n.body : (n.excerpt ?? n.subject ?? '')}</div>
        </div>
      ))}
      {d.timeline.length === 0 ? <div className="text-12.5 text-muted">{t('empty')}</div> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
function Files({ bundle, onAfter }: { bundle: ProjectBundle; onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean> }) {
  const t = useTranslations('projects.files')
  const te = useTranslations('common.errors')
  const ts = useTranslations('common.storage')
  const flash = useToast()
  const d = bundle.detail
  const ready = bundle.storageReady
  const canUpload = ready && d.can_edit
  const picker = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const size = (n: number) => (n >= 1_048_576 ? `${(n / 1_048_576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} kB`)
  const shared = d.sharing.visibility === 'all' ? t('everyone') : d.sharing.visibility === 'owner' ? t('ownerOnly') : d.sharing.visibility === 'group_sub' ? t('groupSub', { group: d.sharing.group ?? '—' }) : (d.sharing.group ?? '—')
  const why = (r: { code: RpcCode; detail?: string | null }) => (r.detail && ts.has(r.detail) ? ts(r.detail) : te(r.code))
  // storage-sign (0052): the database begins the upload, the signer signs its path, the browser sends the file, the database lists it
  const upload = async (file: File) => {
    const mime = typeFor(file.name, RECORD_TYPES)
    if (!mime) { flash(ts('type')); return }
    if (file.size > RECORD_MAX_BYTES) { flash(ts('tooLarge', { mb: 25 })); return }
    setBusy(true)
    try {
      const begun = await recordUploadBegin({ entity: 'project', id: d.id, filename: file.name, mime, size: file.size })
      if (!begun.ok) { flash(why(begun)); return }
      if (!(await putSigned(begun.url, file, mime))) { await recordUploadAbandon(begun.id); flash(ts('sendFailed')); return }
      await onAfter(recordUploadDone(begun.id), t('uploaded', { name: file.name }))
    } finally {
      setBusy(false)
    }
  }
  const open = async (id: string) => {
    if (!ready) { flash(t('downloadOff')); return }
    const r = await recordDownload(id)
    if (!r.ok) { flash(why(r)); return }
    window.location.assign(r.url)
  }
  return (
    <div className={`${card} flex flex-col gap-2 px-4 py-[14px]`}>
      <b className="text-13.5">{t('title')}</b>
      {bundle.files.map((f) => (
        <div key={f.id} className="flex items-center justify-between gap-2 border-b border-line py-[6px] text-12.5">
          <button type="button" onClick={() => void open(f.id)} title={ready ? t('download', { name: f.filename }) : t('downloadOff')} className="min-w-0 cursor-pointer truncate border-none bg-transparent p-0 text-left text-12.5">▦ {f.filename}</button>
          <span className="flex flex-none items-center gap-2 text-muted">
            {size(f.size_bytes)}
            {f.can_delete ? <button type="button" aria-label={t('remove', { name: f.filename })} onClick={() => void onAfter(deleteFile(f.id), t('removed'))} className="cursor-pointer border-none bg-transparent p-0 text-faint">×</button> : null}
          </span>
        </div>
      ))}
      {bundle.files.length === 0 ? <div className="text-12.5 text-muted">{t('empty')}</div> : null}
      <span className="flex flex-wrap items-center gap-2">
        <input ref={picker} type="file" hidden accept={acceptFor(RECORD_TYPES)} onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void upload(f) }} />
        <button type="button" disabled={!canUpload || busy} onClick={() => picker.current?.click()} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-60">{busy ? t('uploading') : t('upload')}</button>
        {!ready ? <span className="text-11.5 text-faint">{t('signerOff')}</span> : canUpload ? <span className="text-11.5 text-faint">{t('limits')}</span> : null}
      </span>
      <span className="text-11.5 text-muted">
        {d.sharing.followers.length ? t('sharedWith', { who: shared, followers: d.sharing.followers.map((f) => f.name).join(', ') }) : t('sharedWithOnly', { who: shared })}
      </span>
    </div>
  )
}

// ---------------------------------------------------------------------------
type DetailsProps = {
  bundle: ProjectBundle
  base: ProjectsBase
  editable: boolean
  allPhases: { id: string; name: string; board: string; boardId: string }[]
  onSave: (values: Record<string, unknown>, msg?: string) => Promise<boolean>
  onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean>
}

function Details({ bundle, base, editable, allPhases, onSave, onAfter }: DetailsProps) {
  const t = useTranslations('projects.details')
  const format = useFormatter()
  const d = bundle.detail
  const [picking, setPicking] = useState<'person' | 'organization' | null>(null)
  const row = 'flex items-center justify-between gap-[10px] text-12.5'
  const ownerKnown = base.staff.some((s) => s.id === d.owner_id)
  const fieldValue = (f: Field): string => {
    const v = d.custom[f.key]
    if (v === null || v === undefined || v === '') return '—'
    if (f.type === 'single_option' || f.type === 'multiple_options') {
      const opts = f.options.map((o) => (typeof o === 'string' ? { key: o, label: o } : { key: o.key, label: o.label ?? o.key }))
      const keys = Array.isArray(v) ? v.map(String) : [String(v)]
      return keys.map((k) => opts.find((o) => o.key === k)?.label ?? k).join(', ')
    }
    if (f.type === 'date' && typeof v === 'string') return format.dateTime(dateOnly(v), { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
    if (f.type === 'user') return base.staff.find((s) => s.id === v)?.name ?? '—'
    if (typeof v === 'string' || typeof v === 'number') return String(v)
    return '—'
  }
  const editableField = (f: Field) => editable && !f.readonly && ['text', 'large_text', 'numerical', 'date', 'single_option', 'phone'].includes(f.type)
  const saveField = (f: Field, raw: string) => {
    const v = raw.trim()
    const val = v === '' ? null : f.type === 'numerical' ? Number(v.replace(',', '.')) : v
    if (typeof val === 'number' && !Number.isFinite(val)) return
    if ((d.custom[f.key] ?? null) === val) return
    void onSave({ custom: { [f.key]: val } })
  }
  const small = 'h-7 rounded-7 border border-line bg-canvas px-[6px] text-12.5'

  return (
    <div className={`${card} flex flex-col gap-[7px] px-4 py-[14px]`}>
      <span className={eyebrow}>{t('title')}</span>
      <label className={row}>
        <span className="text-muted">{t('phase')}</span>
        <select
          value={d.phase_id}
          disabled={!editable}
          onChange={(e) => void onAfter(moveProject({ id: d.id, phase: e.target.value, version: d.version }), t('moved', { phase: allPhases.find((p) => p.id === e.target.value)?.name ?? '' }))}
          className={`${small} max-w-[200px] text-ink`}
        >
          {[...new Set(allPhases.map((p) => p.boardId))].map((b) => (
            <optgroup key={b} label={allPhases.find((p) => p.boardId === b)?.board}>
              {allPhases.filter((p) => p.boardId === b).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </optgroup>
          ))}
        </select>
      </label>
      <label className={row}>
        <span className="text-muted">{t('owner')}</span>
        <select value={d.owner_id ?? ''} disabled={!editable} onChange={(e) => void onSave({ owner_id: e.target.value }, t('ownerChanged'))} className={`${small} max-w-[200px] text-ink`}>
          {!ownerKnown ? <option value={d.owner_id ?? ''}>{d.owner?.name ?? '—'}</option> : null}
          {base.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
      </label>
      {(['starts_on', 'ends_on'] as const).map((k) => (
        <label key={k} className={row}>
          <span className="text-muted">{t(k)}</span>
          <input type="date" key={`${k}-${d.version}`} defaultValue={d[k] ?? ''} disabled={!editable} onBlur={(e) => { if ((e.target.value || null) !== d[k]) void onSave({ [k]: e.target.value || null }) }} className={small} />
        </label>
      ))}
      {(['person', 'organization'] as const).map((k) => (
        <div key={k} className={row}>
          <span className="text-muted">{t(k)}</span>
          {picking === k ? null : (
            <span className="flex items-center gap-2">
              <b className="text-right">{(k === 'person' ? d.person : d.organization) ?? '—'}</b>
              {editable ? <button type="button" onClick={() => setPicking(k)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('change')}</button> : null}
              {editable && (k === 'person' ? d.person_id : d.organization_id) ? <button type="button" onClick={() => void onSave({ [`${k}_id`]: null })} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('clear')}</button> : null}
            </span>
          )}
        </div>
      ))}
      {picking ? <Picker entity={picking} onCancel={() => setPicking(null)} onPick={(h) => { const k = picking; setPicking(null); void onSave({ [`${k}_id`]: h.id }) }} /> : null}
      <label className={row}>
        <span className="text-muted">{t('visibility')}</span>
        <select value={d.visibility} disabled={!editable} onChange={(e) => void onSave({ visibility: e.target.value })} className={`${small} text-ink`}>
          {(['all', 'group_sub', 'group', 'owner'] as const).map((v) => <option key={v} value={v}>{t(`vis.${v}`)}</option>)}
        </select>
      </label>
      {base.fields.map((f) => (
        <label key={f.id} className={row}>
          <span className="text-muted">{f.label}{f.quality === 'required' ? <span className="text-faint"> {t('required')}</span> : null}</span>
          {editableField(f) ? (
            f.type === 'single_option' ? (
              <select value={String(d.custom[f.key] ?? '')} onChange={(e) => saveField(f, e.target.value)} className={`${small} text-ink`}>
                <option value="">—</option>
                {f.options.map((o) => { const k = typeof o === 'string' ? o : o.key; return <option key={k} value={k}>{typeof o === 'string' ? o : o.label ?? o.key}</option> })}
              </select>
            ) : (
              <input key={`${f.key}-${d.version}`} type={f.type === 'date' ? 'date' : 'text'} defaultValue={typeof d.custom[f.key] === 'string' || typeof d.custom[f.key] === 'number' ? String(d.custom[f.key]) : ''} onBlur={(e) => saveField(f, e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }} className={`${small} w-[150px]`} />
            )
          ) : <b className="text-right">{fieldValue(f)}</b>}
        </label>
      ))}
      {base.labels.length ? (
        <div className="flex flex-wrap gap-1 pt-1">
          {base.labels.map((l) => {
            const on = d.labels.includes(l.id)
            return (
              <button key={l.id} type="button" aria-pressed={on} disabled={!editable} onClick={() => void onSave({ labels: on ? d.labels.filter((x) => x !== l.id) : [...d.labels, l.id] })}
                className={`cursor-pointer rounded-999 border px-[9px] py-[3px] text-11 font-bold disabled:cursor-default ${on ? 'border-transparent' : 'border-line-strong bg-transparent text-muted'}`}
                style={on ? { background: l.bg, color: l.ink } : undefined}>
                {l.name}
              </button>
            )
          })}
        </div>
      ) : null}
      <div className="flex flex-col gap-1 pt-1">
        <span className="flex items-center justify-between gap-2 text-12.5">
          <span className="text-muted">{t('description')}{d.brief_state !== 'none' ? <span className="text-faint"> · {t(`brief.${d.brief_state}`)}</span> : null}</span>
          <span className="flex gap-2">
            {editable && d.brief_state === 'draft' ? <button type="button" onClick={() => void onAfter(reviewBrief({ id: d.id, version: d.version }), t('reviewed'))} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('markReviewed')}</button> : null}
            {editable && d.brief_state !== 'drafting' ? (
              <button type="button" disabled={!d.ai.enabled} title={d.ai.enabled ? undefined : t('briefOff')} onClick={() => void onAfter(requestBrief(d.id), t('briefRequested'))} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link disabled:cursor-default disabled:text-faint">{t('draftBrief')}</button>
            ) : null}
          </span>
        </span>
        <textarea key={`desc-${d.version}`} aria-label={t('description')} defaultValue={d.description ?? ''} disabled={!editable} maxLength={20000} onBlur={(e) => { const v = e.target.value; if (v !== (d.description ?? '')) void onSave({ description: v.trim() ? v : null }) }} className="min-h-[60px] rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5 disabled:opacity-80" />
        {editable && !d.ai.enabled ? <span className="text-11.5 text-faint">{t('briefOff')}</span> : null}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
function Deals({ bundle, rights, editable, onAfter }: { bundle: ProjectBundle; rights: Rights; editable: boolean; onAfter: (p: R | Promise<R>, msg?: string) => Promise<boolean> }) {
  const t = useTranslations('projects.deals')
  const [picking, setPicking] = useState(false)
  const d = bundle.detail
  return (
    <div className={`${card} flex flex-col gap-[7px] px-4 py-[14px]`}>
      <span className={eyebrow}>{t('title')}</span>
      {d.deals.map((x) => (
        <div key={x.id} className="flex items-center justify-between gap-2 border-b border-line py-[6px] text-12.5">
          <span className="flex min-w-0 flex-col">
            <a href={`/deals?deal=${x.id}`} className="font-bold text-ink hover:text-ink">◆ {x.title}</a>
            <span className="text-11.5 text-muted">{[x.is_primary ? t('primary') : null, x.stage, x.status ? t(`status.${x.status}`) : null].filter(Boolean).join(' · ') || (rights.dealsSee ? '' : t('titleOnly'))}</span>
          </span>
          {editable && rights.dealsSee ? (
            <span className="flex flex-none gap-2 text-11.5">
              {!x.is_primary ? <button type="button" onClick={() => void onAfter(linkDeal({ id: d.id, deal: x.id, on: true, primary: true }), t('primarySet'))} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">{t('makePrimary')}</button> : null}
              <button type="button" onClick={() => void onAfter(linkDeal({ id: d.id, deal: x.id, on: false }), t('unlinked'))} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-rust">{t('unlink')}</button>
            </span>
          ) : null}
        </div>
      ))}
      {d.deals.length === 0 ? <div className="text-12.5 text-muted">{t('empty')}</div> : null}
      {editable && rights.dealsSee ? (
        picking ? <Picker entity="deal" onCancel={() => setPicking(false)} onPick={(h) => { setPicking(false); void onAfter(linkDeal({ id: d.id, deal: h.id, on: true }), t('linked')) }} />
          : <button type="button" onClick={() => setPicking(true)} className="h-7 cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('link')}</button>
      ) : null}
      {editable && !rights.dealsSee ? <span className="text-11.5 text-faint">{t('needsDeals')}</span> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
function History({ bundle, base, allPhases }: { bundle: ProjectBundle; base: ProjectsBase; allPhases: { id: string; name: string }[] }) {
  const t = useTranslations('projects.history')
  const tp = useTranslations('projects')
  const format = useFormatter()
  const items = new Map(bundle.detail.items.map((i) => [i.id, i.name ?? '']))
  const phase = (v: unknown) => allPhases.find((p) => p.id === v)?.name ?? '—'
  const val = (field: string, v: unknown): string => {
    if (v === null || v === undefined || v === '') return '—'
    if (field === 'phase_id') return phase(v)
    if (field === 'owner_id') return base.staff.find((x) => x.id === v)?.name ?? '—'
    if (field === 'group_id') return bundle.detail.groups.find((g) => g.id === v)?.name ?? '—'
    if (field === 'parent_id') return items.get(String(v)) || '—'
    if (field === 'done' || field === 'completes_with_subtasks') return tp(v === true ? 'export.yes' : 'export.no')
    if (field === 'health' && typeof v === 'string' && (HEALTHS as readonly string[]).includes(v)) return tp(`health.${v}`)
    if (field === 'status' && typeof v === 'string') return tp(`status.${v}`)
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return String(v)
    return ''
  }
  const rows = useMemo(() => bundle.history.map((h) => {
    const m = h.field.match(/^items\.([0-9a-f-]{36})\.(.+)$/)
    if (m) return { ...h, label: t('item', { name: items.get(m[1]!) || t('removedItem'), what: t.has(`col.${m[2]!.replace('*', '_')}`) ? t(`col.${m[2]!.replace('*', '_')}`) : m[2]! }), change: m[2]!.startsWith('*') || m[2] === 'assignees' || m[2] === 'depends_on' ? '' : `${val(m[2]!, h.old)} → ${val(m[2]!, h.new)}` }
    const label = t.has(`field.${h.field.replace('*', '_')}`) ? t(`field.${h.field.replace('*', '_')}`) : h.field
    const change = h.field.startsWith('*') || ['items', 'deals', 'files', 'person_id', 'organization_id', 'labels', 'custom', 'board_id'].includes(h.field) ? '' : `${val(h.field, h.old)} → ${val(h.field, h.new)}`
    return { ...h, label, change }
  }), [bundle.history]) // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className={`${card} px-4 py-[14px]`}>
      <div className={`${eyebrow} mb-2`}>{t('title')}</div>
      {rows.map((h, i) => (
        <div key={i} className="grid gap-[10px] border-b border-line py-[7px] text-12.5 [grid-template-columns:minmax(0,1fr)_auto]">
          <span className="flex min-w-0 flex-col gap-[2px]"><b>{h.label}</b>{h.change ? <span className="break-words text-muted">{h.change}</span> : null}</span>
          <span className="whitespace-nowrap text-11 text-faint">{[h.actor, format.dateTime(new Date(h.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })].filter(Boolean).join(' · ')}</span>
        </div>
      ))}
      {rows.length === 0 ? <div className="text-12.5 text-muted">{t('empty')}</div> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
function SaveTemplate({ projectId, name, onClose }: { projectId: string; name: string; onClose: () => void }) {
  const t = useTranslations('projects.saveTemplate')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const [value, setValue] = useState(name)
  const [busy, setBusy] = useState(false)
  const submit = async () => {
    setBusy(true)
    const r = await templateFromProject({ project: projectId, name: value.trim() })
    setBusy(false)
    if (!r.ok) return flash(r.detail === 'name' ? t('taken') : te(r.code))
    flash(t('saved', { name: value.trim() }))
    onClose()
  }
  return (
    <Modal eyebrow={t('eyebrow')} title={t('title')} onClose={onClose}>
      <label className={field}>{t('name')}<input value={value} maxLength={120} onChange={(e) => setValue(e.target.value)} className={fieldInput} /></label>
      <p className="m-0 text-12 text-muted">{t('body')}</p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('cancel')}</button>
        <button type="button" disabled={busy || !value.trim()} onClick={() => void submit()} className={btnConfirm}>{t('save')}</button>
      </div>
    </Modal>
  )
}
