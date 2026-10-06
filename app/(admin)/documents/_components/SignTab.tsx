'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import {
  FIELD_KINDS, INVITE_LANGUAGES, SIGNER_COLORS, firstName,
  type DocRow, type FieldKind, type Rights, type SignRequest, type StorageState,
} from '@/lib/data/documents-shared'
import { cancelSignatureAction, remindSignerAction, sendSignatureAction, signRequestAction } from '../actions'
import type { Loaded } from './DocumentsScreen'
import { note } from './Modal'
import { useDate, useError } from './util'

type SignerDraft = { key: string; name: string; email: string; color: string; person_id: string | null; status: SignRequest['signers'][number]['status']; id: string | null }
type FieldDraft = { key: string; signer: string; kind: FieldKind; page: number; x: number; y: number; w: number; h: number }

// the page skeleton's line widths (Documents.dc.html, lines) and a field's height: 38 px of the 520 px page
const LINES = [92, 88, 95, 70, 90, 84, 60, 93, 77, 40]
const FIELD_H = 7.3
const round = (n: number) => Math.round(n * 100) / 100
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))
let seq = 0
const key = () => `k${++seq}`

/**
 * E-signature (DOC-05): the document's page with the signers' fields, placed by dragging (D-41), the signers, the
 * message, the invite language and the one-time code. «Send for signature» saves the draft request and sends it;
 * without the document's PDF or the email provider the database refuses, and the screen says why.
 */
export function SignTab(p: {
  docId: string | null
  rows: DocRow[]
  loaded: Loaded | null
  load: (id: string, fresh?: boolean) => Promise<Loaded | null>
  storage: StorageState | null
  rights: Rights
  onPick: (id: string) => void
  onChanged: (id: string | null) => Promise<void>
}) {
  const t = useTranslations('documents.sign')
  const flash = useToast()
  const err = useError()
  const date = useDate()
  const { docId, loaded, load } = p
  const [request, setRequest] = useState<SignRequest | null>(null)
  const [requestFor, setRequestFor] = useState<string | null>(null)
  const [fresh, setFresh] = useState(false)
  const [signers, setSigners] = useState<SignerDraft[]>([])
  const [fields, setFields] = useState<FieldDraft[]>([])
  const [message, setMessage] = useState('')
  const [language, setLanguage] = useState<(typeof INVITE_LANGUAGES)[number]>('nb')
  const [otp, setOtp] = useState(true)
  const [sel, setSel] = useState<string | null>(null)
  const [adding, setAdding] = useState<{ name: string; email: string } | null>(null)
  const [newKind, setNewKind] = useState<FieldKind>('signature')
  const [newFor, setNewFor] = useState<string>('')
  const [busy, setBusy] = useState(false)
  const page = useRef<HTMLDivElement>(null)
  const drag = useRef<{ key: string; sx: number; sy: number; ox: number; oy: number } | null>(null)

  const doc = loaded?.doc ?? null
  const latest = doc?.signature_requests[doc.signature_requests.length - 1] ?? null

  useEffect(() => { if (docId && !loaded) void load(docId) }, [docId, loaded, load])

  /** Fills the editor from a request (or empties it for a new one). */
  function fill(r: SignRequest | null) {
    setRequest(r)
    const ss: SignerDraft[] = (r?.signers ?? []).map((s) => ({ key: s.id, id: s.id, name: s.name, email: s.email, color: s.color ?? SIGNER_COLORS[0], person_id: s.person_id, status: s.status }))
    setSigners(ss)
    setFields((r?.fields ?? []).map((f) => ({ key: f.id, signer: f.signer_id, kind: f.kind, page: f.page, x: f.x, y: f.y, w: f.w, h: f.h })))
    setMessage(r?.message ?? '')
    setLanguage(r?.language ?? 'nb')
    setOtp(r?.otp_required ?? true)
    setSel(null)
    setNewFor(ss[0]?.key ?? '')
  }

  // the document's latest request, loaded when the document (or its latest request) changes
  useEffect(() => {
    if (!doc) return
    const want = latest?.id ?? null
    if (requestFor === `${doc.id}:${want}`) return
    setRequestFor(`${doc.id}:${want}`)
    setFresh(false)
    if (!want) { fill(null); return }
    void signRequestAction({ id: want }).then((r) => { if (r.ok) fill(r.request); else { flash(err(r)); fill(null) } })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [doc?.id, latest?.id])

  if (!docId) return <Choose rows={p.rows} onPick={p.onPick} />
  if (!doc) return <div className="rounded-20 border border-line bg-surface p-[18px] text-12.5 text-muted">{t('loading')}</div>

  const open = request && ['draft', 'sent', 'in_progress'].includes(request.status)
  const editable = doc.can_edit && p.rights.add && !['signed', 'revoked'].includes(doc.status) && (fresh || !request || request.status === 'draft')
  const limit = request?.signer_limit ?? p.storage?.signer_limit ?? null
  const service = p.storage?.esign_service ?? 'builtin'
  const signerOf = (k: string) => signers.find((s) => s.key === k)
  const kindLabel = (k: FieldKind) => t(`kind.${k}`)
  const selected = fields.find((f) => f.key === sel) ?? null

  function move(k: string, x: number, y: number) {
    setFields((fs) => fs.map((f) => (f.key === k ? { ...f, x: round(clamp(x, 0, 100 - f.w)), y: round(clamp(y, 0, 100 - f.h)) } : f)))
  }
  function onDown(e: React.PointerEvent<HTMLButtonElement>, f: FieldDraft) {
    setSel(f.key)
    if (!editable) return
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { key: f.key, sx: e.clientX, sy: e.clientY, ox: f.x, oy: f.y }
  }
  function onMove(e: React.PointerEvent<HTMLButtonElement>) {
    const d = drag.current
    const box = page.current?.getBoundingClientRect()
    if (!d || !box) return
    move(d.key, d.ox + ((e.clientX - d.sx) / box.width) * 100, d.oy + ((e.clientY - d.sy) / box.height) * 100)
  }
  function onKey(e: React.KeyboardEvent<HTMLButtonElement>, f: FieldDraft) {
    if (!editable) return
    const step = e.shiftKey ? 5 : 1
    const by: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }
    if (by[e.key]) { e.preventDefault(); move(f.key, f.x + by[e.key]![0], f.y + by[e.key]![1]) }
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); setFields((fs) => fs.filter((x) => x.key !== f.key)); setSel(null) }
  }
  function addSigner() {
    if (!adding) return
    const name = adding.name.trim()
    const email = adding.email.trim()
    if (!name || !/^[^@\s]+@[^@\s]+$/.test(email)) return flash(t('signerInvalid'))
    const i = signers.length
    const k = key()
    const y = round(Math.min(70 + 12 * i, 100 - FIELD_H))
    setSigners((ss) => [...ss, { key: k, id: null, name, email, color: SIGNER_COLORS[i % SIGNER_COLORS.length]!, person_id: null, status: 'waiting' }])
    setFields((fs) => [...fs, { key: key(), signer: k, kind: 'signature', page: 1, x: 8, y, w: 40, h: FIELD_H }, { key: key(), signer: k, kind: 'date', page: 1, x: 52, y, w: 26, h: FIELD_H }])
    setNewFor((v) => v || k)
    setAdding(null)
  }
  function removeSigner(k: string) {
    setSigners((ss) => ss.filter((s) => s.key !== k))
    setFields((fs) => fs.filter((f) => f.signer !== k))
    if (newFor === k) setNewFor(signers.find((s) => s.key !== k)?.key ?? '')
  }
  function addField() {
    const s = signerOf(newFor) ?? signers[0]
    if (!s) return
    const k = key()
    setFields((fs) => [...fs, { key: k, signer: s.key, kind: newKind, page: 1, x: 8, y: 40, w: newKind === 'signature' ? 40 : 26, h: FIELD_H }])
    setSel(k)
  }

  async function send() {
    if (!doc) return
    setBusy(true)
    const order = signers.map((s) => s.key)
    const r = await sendSignatureAction({
      send: true,
      draft: {
        id: fresh ? null : request?.status === 'draft' ? request.id : null,
        document: doc.id,
        version: fresh || request?.status !== 'draft' ? null : request.version,
        signers: signers.map((s) => ({ name: s.name, email: s.email, color: s.color, person_id: s.person_id })),
        fields: fields.filter((f) => order.includes(f.signer)).map((f) => ({ signer: order.indexOf(f.signer) + 1, kind: f.kind, page: f.page, x: f.x, y: f.y, w: f.w, h: f.h })),
        message, language, otp,
      },
    })
    setBusy(false)
    if (r.ok) flash(t('sent'))
    else flash(r.id ? t('savedNot', { reason: err(r) }) : err(r))
    const saved = r.id
    if (saved) { await reload(saved); await p.onChanged(doc.id) }
  }
  /** The request again after a change (its version moves with every save). */
  async function reload(id: string) {
    if (!doc) return
    const g = await signRequestAction({ id })
    setRequestFor(`${doc.id}:${id}`)
    setFresh(false)
    if (g.ok) fill(g.request)
  }
  async function remind(signer: string) {
    if (!request) return
    const r = await remindSignerAction({ id: request.id, signer })
    flash(r.ok ? t('reminded') : err(r))
  }
  async function cancel() {
    if (!request || !doc) return
    setBusy(true)
    const r = await cancelSignatureAction({ id: request.id })
    setBusy(false)
    flash(r.ok ? t('canceled') : err(r))
    if (r.ok) { await reload(request.id); await p.onChanged(doc.id) }
  }

  const statusColor = (s: SignerDraft['status']) => (s === 'declined' ? '#8A3A16' : ['opened', 'code_verified', 'signed'].includes(s) ? '#2F5D2A' : '#8A6A00')
  const blockers = editable ? [
    ...(doc.merge_missing.length ? [t('blockers.merge', { tokens: doc.merge_missing.map((x) => `[${x}]`).join(' ') })] : []),
    ...(!doc.has_pdf ? [t('blockers.pdf')] : []),
    ...(service === 'builtin' && p.storage && !p.storage.email_connected ? [t('blockers.email')] : []),
    ...(service === 'external' && p.storage && !p.storage.esign_connected ? [t('blockers.esign')] : []),
  ] : []

  return (
    <div className="grid grid-cols-1 items-start gap-[14px] lg:[grid-template-columns:minmax(0,1fr)_minmax(300px,380px)]">
      <div className="flex flex-col items-center gap-3 rounded-20 border border-line bg-canvas p-[18px]">
        <div ref={page} className="relative h-[520px] w-[420px] max-w-full rounded-12 border border-line bg-surface p-[22px] shadow-soft">
          <div className="font-serif text-16 font-semibold">{doc.name}</div>
          <div className="mt-[10px] flex flex-col gap-[7px]">
            {LINES.map((w, i) => <span key={i} className="h-[7px] rounded-4 bg-tile" style={{ width: `${w}%` }} />)}
          </div>
          {fields.map((f) => {
            const s = signerOf(f.signer)
            const c = s?.color ?? '#5F5849'
            return (
              <button key={f.key} type="button" aria-pressed={sel === f.key}
                aria-label={`${kindLabel(f.kind)} · ${s ? s.name : ''}`}
                onPointerDown={(e) => onDown(e, f)} onPointerMove={onMove} onPointerUp={() => { drag.current = null }} onPointerCancel={() => { drag.current = null }}
                onKeyDown={(e) => onKey(e, f)}
                className={`absolute flex touch-none items-center justify-center overflow-hidden whitespace-nowrap rounded-8 border-[1.5px] border-dashed p-0 text-11 font-bold ${editable ? 'cursor-move' : 'cursor-pointer'}`}
                style={{ left: `${f.x}%`, top: `${f.y}%`, width: `${f.w}%`, height: `${f.h}%`, borderColor: c, color: c, background: sel === f.key ? '#FBEBBE' : 'rgba(255,253,246,.7)' }}>
                {kindLabel(f.kind)} · {s ? firstName(s.name) : ''}
              </button>
            )
          })}
        </div>
        {editable && signers.length ? (
          <div className="flex w-[420px] max-w-full flex-wrap items-center gap-[6px] text-12">
            <select aria-label={t('fieldFor')} value={newFor} onChange={(e) => setNewFor(e.target.value)} className="h-[30px] rounded-8 border border-line bg-surface text-12">
              {signers.map((s) => <option key={s.key} value={s.key}>{s.name}</option>)}
            </select>
            <select aria-label={t('fieldKind')} value={newKind} onChange={(e) => setNewKind(e.target.value as FieldKind)} className="h-[30px] rounded-8 border border-line bg-surface text-12">
              {FIELD_KINDS.map((k) => <option key={k} value={k}>{kindLabel(k)}</option>)}
            </select>
            <button type="button" onClick={addField} className="h-[30px] cursor-pointer rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold">{t('addField')}</button>
            {selected ? (
              <>
                <span className="flex-1" />
                <select aria-label={t('fieldKind')} value={selected.kind} onChange={(e) => setFields((fs) => fs.map((f) => (f.key === selected.key ? { ...f, kind: e.target.value as FieldKind } : f)))}
                  className="h-[30px] rounded-8 border border-line bg-surface text-12">
                  {FIELD_KINDS.map((k) => <option key={k} value={k}>{kindLabel(k)}</option>)}
                </select>
                <button type="button" onClick={() => { setFields((fs) => fs.filter((f) => f.key !== selected.key)); setSel(null) }}
                  className="h-[30px] cursor-pointer rounded-9 border border-coral bg-transparent px-[10px] text-12 font-semibold text-rust">{t('removeField')}</button>
              </>
            ) : null}
          </div>
        ) : null}
        <span className="w-[420px] max-w-full text-11.5 text-muted">{doc.has_pdf ? t('pageNote') : t('noPdfNote')}</span>
      </div>

      <div className="flex flex-col gap-3">
        <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
          <b className="text-14">{t('signers')}</b>
          {signers.length ? signers.map((s) => (
            <div key={s.key} className="flex items-center gap-[10px] border-b border-line py-[7px]">
              <span className="h-[10px] w-[10px] flex-none rounded-3" style={{ background: s.color }} />
              <span className="flex min-w-0 flex-1 flex-col text-12.5"><b>{s.name}</b><span className="break-all text-11.5 text-muted">{s.email}</span></span>
              <span className="text-11.5 font-bold" style={{ color: statusColor(s.status) }}>{t(`signer.${s.status}`)}</span>
              {editable ? (
                <button type="button" onClick={() => removeSigner(s.key)} aria-label={t('removeSigner', { name: s.name })}
                  className="h-6 w-6 flex-none cursor-pointer rounded-999 border border-line bg-transparent text-12 leading-none">×</button>
              ) : request && open && request.service === 'builtin' && s.id && ['sent', 'opened', 'code_verified'].includes(s.status) && doc.can_edit ? (
                <button type="button" onClick={() => remind(s.id!)} className="h-6 cursor-pointer rounded-9 border border-line bg-transparent px-2 text-11 font-semibold">{t('remind')}</button>
              ) : null}
            </div>
          )) : <span className="text-12 text-muted">{t('noSigners')}</span>}
          {editable ? (
            adding ? (
              <div className="flex flex-col gap-[6px]">
                <input aria-label={t('signerName')} placeholder={t('signerName')} value={adding.name} maxLength={200} onChange={(e) => setAdding({ ...adding, name: e.target.value })}
                  className="h-[30px] rounded-8 border border-line bg-canvas px-[10px] text-12.5" />
                <input aria-label={t('signerEmail')} placeholder={t('signerEmail')} type="email" value={adding.email} maxLength={254} onChange={(e) => setAdding({ ...adding, email: e.target.value })}
                  onKeyDown={(e) => { if (e.key === 'Enter') addSigner() }} className="h-[30px] rounded-8 border border-line bg-canvas px-[10px] text-12.5" />
                <div className="flex gap-[6px]">
                  <button type="button" onClick={addSigner} className="h-7 cursor-pointer rounded-9 border border-ink bg-primary px-[10px] text-12 font-bold">{t('addSigner')}</button>
                  <button type="button" onClick={() => setAdding(null)} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('cancel')}</button>
                </div>
              </div>
            ) : (
              <button type="button" onClick={() => setAdding({ name: '', email: '' })} disabled={limit !== null && signers.length >= limit}
                className="h-7 cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-60">{t('signer.add')}</button>
            )
          ) : null}
          <span className="text-11.5 text-muted">{t('limit', { limit: limit === null ? t('unlimited') : String(limit) })}</span>
        </div>

        <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
          {request && !editable ? (
            <div className="flex flex-col gap-1 text-12.5">
              <b>{t(`request.${request.status}`)}</b>
              <span className="text-11.5 text-muted">
                {request.sent_at ? t('sentOn', { date: date(request.sent_at) }) : null}
                {request.completed_at ? ` · ${t('completedOn', { date: date(request.completed_at) })}` : null}
              </span>
              <span className="text-11.5" style={{ color: request.chain_ok ? '#2F5D2A' : '#8A3A16' }}>{request.chain_ok ? t('chainOk', { n: request.events.length }) : t('chainBroken')}</span>
            </div>
          ) : null}
          <label className="flex flex-col gap-1 text-11.5 text-muted">{t('message')}
            <textarea value={message} maxLength={2000} disabled={!editable} onChange={(e) => setMessage(e.target.value)}
              className="min-h-[60px] rounded-10 border border-line bg-canvas px-[10px] py-2 text-12.5 text-ink disabled:opacity-70" />
          </label>
          <label className="flex items-center justify-between text-12.5">{t('language')}
            <select value={language} disabled={!editable} onChange={(e) => setLanguage(e.target.value as typeof language)} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
              {INVITE_LANGUAGES.map((l) => <option key={l} value={l}>{t(`lang.${l}`)}</option>)}
            </select>
          </label>
          <label className="flex items-center gap-2 text-12.5">
            <input type="checkbox" checked={otp} disabled={!editable} onChange={(e) => setOtp(e.target.checked)} style={{ accentColor: '#191510' }} />{t('otp')}
          </label>
          {blockers.length ? <div className={`${note} flex flex-col gap-1 text-11.5`}>{blockers.map((b) => <span key={b}>{b}</span>)}</div> : null}
          {editable ? (
            <button type="button" onClick={send} disabled={busy || !signers.length}
              className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary text-13 font-bold disabled:cursor-default disabled:opacity-60">{t('send')}</button>
          ) : request && open && doc.can_edit ? (
            <button type="button" onClick={cancel} disabled={busy}
              className="h-[38px] cursor-pointer rounded-11 border border-coral bg-transparent text-13 font-semibold text-rust disabled:opacity-60">{t('cancelRequest')}</button>
          ) : request && !open && doc.can_edit && p.rights.add && !['signed', 'revoked'].includes(doc.status) ? (
            <button type="button" onClick={() => { fill(null); setFresh(true) }}
              className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary text-13 font-bold">{t('newRequest')}</button>
          ) : null}
          <span className="text-11.5 text-faint">{t('evidence')}</span>
        </div>
      </div>
    </div>
  )
}

/** No document chosen yet (the tab opened directly, D-41): pick one to send for signature. */
function Choose({ rows, onPick }: { rows: DocRow[]; onPick: (id: string) => void }) {
  const t = useTranslations('documents.sign')
  const candidates = rows.filter((r) => !['signed', 'revoked'].includes(r.status))
  const [id, setId] = useState(candidates[0]?.id ?? '')
  return (
    <div className="flex flex-col items-start gap-[10px] rounded-20 border border-line bg-surface px-[22px] py-5">
      <b className="text-14">{t('chooseTitle')}</b>
      <span className="text-12.5 text-muted">{candidates.length ? t('chooseBody') : t('chooseNone')}</span>
      {candidates.length ? (
        <div className="flex flex-wrap items-center gap-2">
          <select aria-label={t('chooseTitle')} value={id} onChange={(e) => setId(e.target.value)} className="h-9 rounded-10 border border-line bg-canvas px-2 text-12.5">
            {candidates.map((r) => <option key={r.id} value={r.id}>{r.name}{r.deal_title ? ` · ${r.deal_title}` : ''}</option>)}
          </select>
          <button type="button" disabled={!id} onClick={() => onPick(id)} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">{t('choose')}</button>
        </div>
      ) : null}
    </div>
  )
}
