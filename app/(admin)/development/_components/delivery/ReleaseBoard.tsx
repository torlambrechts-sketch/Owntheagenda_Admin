'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import type { CurrentRelease, Note, Releases } from '@/lib/data/dev-delivery'
import { addRelease, attachNote, deleteRelease, recordRelease, saveNote, setRelease, signItem } from '../../delivery-actions'
import { RELEASE_ORDER, orderChecks, shortSha, verdict, type CheckKey } from './logic'
import { releaseTitle, useCheckText, useProductName } from './checks'
import { useRun } from './kit'
import { d } from './styles'

const href = (tab: 'releases' | 'gate', id: string) => `/development?tab=${tab}&release=${id}` as Route
/** «Thu 15 Oct» in two parts: the server's and the browser's ICU join weekday and date differently («Thu, 15 Oct») */
const weekdayDay = (format: ReturnType<typeof useFormatter>, v: string) =>
  `${format.dateTime(new Date(v), { weekday: 'short' })} ${format.dateTime(new Date(v), { day: 'numeric', month: 'short' })}`

/** Releases (DevHub.dc.html v.releases): the release card with its checklist, the changelog, recent releases. */
export function ReleaseBoard({ data, railProduct }: { data: Releases; railProduct: string }) {
  const cur = data.current
  const [adding, setAdding] = useState(false)
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
      {cur ? <ReleaseCard data={data} cur={cur} /> : (
        <div className={`${d.cardInk} flex flex-col gap-[10px] px-5 py-4`}>
          <NoRelease data={data} railProduct={railProduct} />
        </div>
      )}
      <div className="flex min-w-0 flex-col gap-3">
        {cur ? <Changelog data={data} cur={cur} /> : null}
        <Recent data={data} adding={adding} setAdding={setAdding} railProduct={railProduct} />
      </div>
    </div>
  )
}

function NoRelease({ data, railProduct }: { data: Releases; railProduct: string }) {
  const t = useTranslations('devDelivery.releases')
  return (
    <>
      <b className={d.serif20}>{t('none.title')}</b>
      <span className="text-12.5 text-muted">{t('none.body')}</span>
      {data.can_add ? <NewRelease data={data} railProduct={railProduct} onDone={() => {}} /> : <span className="text-12 text-muted">{t('noRight')}</span>}
    </>
  )
}

function ReleaseCard({ data, cur }: { data: Releases; cur: CurrentRelease }) {
  const t = useTranslations('devDelivery.releases')
  const format = useFormatter()
  const pname = useProductName(data.products)
  const text = useCheckText('release', cur.watching)
  const { run, pending, mfa } = useRun()
  const router = useRouter()
  const [rollback, setRollback] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const open = cur.state === 'open'
  const canAct = data.can_add && open
  const items = orderChecks(cur.checks, RELEASE_ORDER)
  const v = verdict(items)
  const title = releaseTitle(pname(cur.product), cur.name)
  const right = cur.state === 'recorded' && cur.recorded_at
    ? t('recordedOn', { day: format.dateTime(new Date(cur.recorded_at), { day: 'numeric', month: 'short' }) })
    : cur.planned_on ? t('planned', { day: weekdayDay(format, `${cur.planned_on}T12:00:00`) }) : t('notPlanned')

  const sign = (key: CheckKey, on: boolean, note: string | null = null) =>
    run(() => signItem({ release: cur.id, item: key, on, note }), () => (on ? t('signedToast') : t('unsignedToast')), () => setRollback(null))

  const label = cur.state === 'recorded' ? t('recordedButton', { day: format.dateTime(new Date(cur.recorded_at ?? cur.created_at), { day: 'numeric', month: 'short' }) })
    : v.ready ? t('record') : t('complete')

  return (
    <div className={`${d.cardInk} flex min-w-0 flex-col gap-[10px] px-5 py-4`}>
      <div className="flex items-baseline justify-between gap-[10px]">
        <b className="font-serif text-20 [overflow-wrap:anywhere]">{title}</b>
        <span className="whitespace-nowrap text-12 text-muted">{right}</span>
      </div>
      <span className={d.label}>{t('checklist', { done: v.done, total: v.total })}</span>
      {items.map((c) => {
        const x = text(c)
        const on = c.state === 'pass'
        const toggle = canAct && c.kind === 'manual'
        const body = (
          <>
            <span className={`flex h-[18px] w-[18px] flex-none items-center justify-center rounded-5 border-[1.5px] border-ink text-10 ${on ? 'bg-ok-bg' : 'bg-transparent'}`} aria-hidden>
              {on ? '✓' : ''}
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span>{x.label}</span>
              {x.sub ? <span className="text-11 text-faint [overflow-wrap:anywhere]">{x.sub}</span> : null}
            </span>
            <span className="whitespace-nowrap text-11 text-faint">{x.source}</span>
          </>
        )
        const row = 'flex items-center gap-[9px] border-0 border-b border-tile bg-transparent py-[6px] text-left text-12.5 text-ink'
        return (
          <div key={c.key} className="flex flex-col gap-2">
            {toggle ? (
              <button type="button" disabled={pending} aria-pressed={on}
                onClick={() => (c.key === 'rollback' && !on ? setRollback(rollback === null ? '' : null) : sign(c.key, !on))}
                className={`${row} w-full cursor-pointer px-0 disabled:cursor-wait`}>
                {body}
              </button>
            ) : <div className={row}>{body}</div>}
            {c.key === 'rollback' && rollback !== null ? (
              <div className="flex flex-col gap-2 rounded-12 bg-canvas p-3">
                <label className={d.field}>
                  {t('rollbackPlan')}
                  <textarea value={rollback} onChange={(e) => setRollback(e.target.value.slice(0, 500))} maxLength={500} rows={3}
                    placeholder={t('rollbackHint')} className="min-h-[70px] rounded-12 border border-line bg-surface px-3 py-[10px] text-13 leading-[1.55] text-ink" />
                </label>
                <div className="flex flex-wrap gap-2">
                  <button type="button" disabled={pending || !rollback.trim()} onClick={() => sign('rollback', true, rollback.trim())} className={d.smallPrimary}>{t('signOff')}</button>
                  <button type="button" onClick={() => setRollback(null)} className={d.small}>{t('cancel')}</button>
                </div>
              </div>
            ) : null}
          </div>
        )
      })}
      <button
        type="button"
        disabled={!open || !v.ready || !data.can_add || pending}
        title={!data.can_add ? t('noRight') : open && !v.ready ? t('completeTitle', { n: v.blocking }) : undefined}
        onClick={() => run(() => recordRelease({ id: cur.id, version: cur.version }), (r) => t('recordedToast', { n: r.published }))}
        className={`${d.bigBtn} ${cur.state === 'recorded' ? 'bg-ok-bg' : 'bg-primary'} ${open && !v.ready ? 'opacity-50' : 'opacity-100'} ${open && v.ready && data.can_add ? 'cursor-pointer' : 'cursor-default'}`}
      >
        {label}
      </button>
      {mfa}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-11.5 text-muted">
        <span>
          {cur.commit?.sha
            ? t(`commit.${cur.commit.source}`, { sha: shortSha(cur.commit.sha) ?? '' })
            : t('commit.none')}
        </span>
        {cur.ci?.run_url ? <a href={cur.ci.run_url} target="_blank" rel="noreferrer" className="font-semibold">{t('ciRun')}</a> : null}
        <Link href={href('gate', cur.id)} className="font-semibold">{t('toGate')}</Link>
        {canAct ? (
          <>
            <button type="button" onClick={() => setEditing(!editing)} className="cursor-pointer border-0 bg-transparent p-0 text-11.5 font-semibold text-link">{t('edit')}</button>
            <button type="button" disabled={pending}
              onClick={() => { if (window.confirm(t('deleteConfirm'))) run(() => deleteRelease(cur.id), () => t('deletedToast'), () => router.push('/development?tab=releases' as Route)) }}
              className="cursor-pointer border-0 bg-transparent p-0 text-11.5 font-semibold text-danger">{t('delete')}</button>
          </>
        ) : null}
      </div>
      {editing && canAct ? <EditRelease cur={cur} onDone={() => setEditing(false)} /> : null}
    </div>
  )
}

function EditRelease({ cur, onDone }: { cur: CurrentRelease; onDone: () => void }) {
  const t = useTranslations('devDelivery.releases')
  const { run, pending, mfa } = useRun()
  const [name, setName] = useState(cur.name)
  const [planned, setPlanned] = useState(cur.planned_on ?? '')
  const [sha, setSha] = useState(cur.sha ?? '')
  const save = () => run(() => setRelease({ id: cur.id, version: cur.version, patch: { name: name.trim(), planned_on: planned || null, sha: sha.trim() || null } }),
    () => t('savedToast'), onDone)
  return (
    <div className="flex flex-col gap-2 rounded-12 bg-canvas p-3">
      <ReleaseFields name={name} setName={setName} planned={planned} setPlanned={setPlanned} sha={sha} setSha={setSha} />
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={pending || !name.trim()} onClick={save} className={d.smallPrimary}>{t('save')}</button>
        <button type="button" onClick={onDone} className={d.small}>{t('cancel')}</button>
      </div>
      {mfa}
    </div>
  )
}

function ReleaseFields({ name, setName, planned, setPlanned, sha, setSha }: {
  name: string; setName: (v: string) => void; planned: string; setPlanned: (v: string) => void; sha: string; setSha: (v: string) => void
}) {
  const t = useTranslations('devDelivery.releases.form')
  return (
    <div className="grid gap-2 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
      <label className={d.field}>{t('name')}<input value={name} maxLength={80} onChange={(e) => setName(e.target.value)} placeholder={t('namePlaceholder')} className={d.input} /></label>
      <label className={d.field}>{t('planned')}<input type="date" value={planned} onChange={(e) => setPlanned(e.target.value)} className={d.input} /></label>
      <label className={d.field}>{t('sha')}<input value={sha} maxLength={40} onChange={(e) => setSha(e.target.value.toLowerCase())} placeholder={t('shaPlaceholder')}
        className={`${d.input} ${d.mono} text-12`} /></label>
    </div>
  )
}

function NewRelease({ data, railProduct, onDone }: { data: Releases; railProduct: string; onDone: () => void }) {
  const t = useTranslations('devDelivery.releases')
  const pname = useProductName(data.products)
  const router = useRouter()
  const { run, pending, mfa } = useRun()
  const [product, setProduct] = useState(data.products.some((p) => p.key === railProduct) ? railProduct : data.products[0]?.key ?? 'sentral')
  const [name, setName] = useState('')
  const [planned, setPlanned] = useState('')
  const [sha, setSha] = useState('')
  const create = () => run(() => addRelease({ product, name: name.trim(), plannedOn: planned || null, sha: sha.trim() || null }), () => t('addedToast'),
    (r) => { onDone(); router.push(href('releases', r.id)) })
  return (
    <div className="flex flex-col gap-2">
      <label className={d.field}>
        {t('form.product')}
        <select value={product} onChange={(e) => setProduct(e.target.value)} className={d.select}>
          {data.products.map((p) => <option key={p.key} value={p.key}>{pname(p.key)}</option>)}
        </select>
      </label>
      <ReleaseFields name={name} setName={setName} planned={planned} setPlanned={setPlanned} sha={sha} setSha={setSha} />
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={pending || !name.trim()} onClick={create} className={d.smallPrimary}>{t('create')}</button>
      </div>
      {mfa}
    </div>
  )
}

/** the changelog: the release's notes; open, each line is edited in place, a new line written, a draft added */
function Changelog({ data, cur }: { data: Releases; cur: CurrentRelease }) {
  const t = useTranslations('devDelivery.releases.changelog')
  const tk = useTranslations('devDelivery.kinds')
  const { run, pending, mfa } = useRun()
  const [edit, setEdit] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const canEdit = data.can_add && cur.state === 'open'
  const lines = cur.changelog
  return (
    <div className={`${d.card} flex min-w-0 flex-col gap-[7px] px-[18px] py-4`}>
      <b className="text-15">{t('title')}</b>
      <span className="text-11.5 text-muted">
        {cur.state === 'recorded' ? t('published', { n: lines.length }) : t('from', { n: lines.length })}
      </span>
      {lines.length === 0 ? <span className="text-12.5 text-muted">{t('empty')}</span> : null}
      {lines.map((n) => (edit === n.id
        ? <NoteForm key={n.id} note={n} onClose={() => setEdit(null)}
            onSave={(kind, title) => run(() => saveNote({ release: cur.id, id: n.id, product: cur.product, kind, title, body: n.body, featureRequest: n.feature_request_id }),
              () => t('savedToast'), () => setEdit(null))}
            onRemove={() => run(() => attachNote({ release: cur.id, note: n.id, on: false }), () => t('removedToast'), () => setEdit(null))}
            pending={pending} />
        : (
          <div key={n.id} className="flex gap-2 text-12.5">
            <span className={`h-[18px] flex-none rounded-999 px-2 py-[1px] text-10.5 font-bold ${d.kind[n.kind]}`}>{tk(n.kind)}</span>
            {canEdit ? (
              <button type="button" onClick={() => setEdit(n.id)} title={t('editLine')}
                className="cursor-pointer border-0 bg-transparent p-0 text-left text-12.5 text-ink hover:underline">{n.title}</button>
            ) : <span>{n.title}</span>}
          </div>
        )))}
      {canEdit && edit === 'new' ? (
        <NoteForm note={null} onClose={() => setEdit(null)} pending={pending}
          onSave={(kind, title) => run(() => saveNote({ release: cur.id, id: null, product: cur.product, kind, title, body: null, featureRequest: null }), () => t('addedToast'), () => setEdit(null))} />
      ) : null}
      {canEdit ? (
        <div className="mt-1 flex flex-wrap items-center gap-2">
          {edit !== 'new' ? (
            <button type="button" onClick={() => setEdit('new')}
              className="h-8 cursor-pointer whitespace-nowrap rounded-9 border border-dashed border-ink bg-transparent px-3 text-12 font-semibold text-ink">{t('add')}</button>
          ) : null}
          {cur.drafts.length ? (
            <>
              <select aria-label={t('fromDrafts')} value={draft} onChange={(e) => setDraft(e.target.value)} className={`${d.select} h-8 max-w-[260px] text-12`}>
                <option value="">{t('fromDrafts')}</option>
                {cur.drafts.map((n) => <option key={n.id} value={n.id}>{`${tk(n.kind)} · ${n.title}`}</option>)}
              </select>
              <button type="button" disabled={!draft || pending} onClick={() => run(() => attachNote({ release: cur.id, note: draft, on: true }), () => t('addedToast'), () => setDraft(''))}
                className={`${d.small} h-8`}>{t('addDraft')}</button>
            </>
          ) : null}
        </div>
      ) : null}
      {mfa}
    </div>
  )
}

function NoteForm({ note, onSave, onRemove, onClose, pending }: {
  note: Note | null; onSave: (kind: Note['kind'], title: string) => void; onRemove?: () => void; onClose: () => void; pending: boolean
}) {
  const t = useTranslations('devDelivery.releases.changelog')
  const tk = useTranslations('devDelivery.kinds')
  const [kind, setKind] = useState<Note['kind']>(note?.kind ?? 'new')
  const [title, setTitle] = useState(note?.title ?? '')
  return (
    <div className="flex flex-col gap-2 rounded-12 bg-canvas p-3">
      <div className="flex flex-wrap gap-2">
        <select aria-label={t('kind')} value={kind} onChange={(e) => setKind(e.target.value as Note['kind'])} className={`${d.select} w-[120px]`}>
          {(['new', 'improved', 'fixed'] as const).map((k) => <option key={k} value={k}>{tk(k)}</option>)}
        </select>
        <input aria-label={t('line')} value={title} maxLength={200} onChange={(e) => setTitle(e.target.value)} placeholder={t('linePlaceholder')}
          onKeyDown={(e) => { if (e.key === 'Enter' && title.trim().length >= 3) onSave(kind, title.trim()) }}
          className={`${d.input} min-w-[200px] flex-1`} />
      </div>
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={pending || title.trim().length < 3} onClick={() => onSave(kind, title.trim())} className={d.smallPrimary}>{t('save')}</button>
        {onRemove ? <button type="button" disabled={pending} onClick={onRemove} className={d.small}>{t('remove')}</button> : null}
        <button type="button" onClick={onClose} className={d.small}>{t('cancel')}</button>
      </div>
    </div>
  )
}

/** Recent releases: name, date, the changelog's lines, and what happened in production after it */
function Recent({ data, adding, setAdding, railProduct }: { data: Releases; adding: boolean; setAdding: (v: boolean) => void; railProduct: string }) {
  const t = useTranslations('devDelivery.releases.recent')
  const format = useFormatter()
  const pname = useProductName(data.products)
  return (
    <div className={`${d.card} min-w-0 overflow-hidden`}>
      <div className="flex items-center justify-between gap-2 border-b border-line px-[18px] py-3">
        <span className="text-15 font-bold">{t('title')}</span>
        {data.can_add && data.current ? (
          <button type="button" onClick={() => setAdding(!adding)} aria-expanded={adding}
            className="h-7 cursor-pointer whitespace-nowrap rounded-8 border border-line bg-transparent px-[10px] text-11.5 font-bold text-ink">{t('new')}</button>
        ) : null}
      </div>
      {adding ? <div className="border-b border-line px-[18px] py-3"><NewRelease data={data} railProduct={railProduct} onDone={() => setAdding(false)} /></div> : null}
      {data.releases.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('empty')}</div> : null}
      {data.releases.map((r) => {
        const when = r.recorded_at ?? (r.planned_on ? `${r.planned_on}T12:00:00` : r.created_at)
        const status = r.state === 'open' ? { s: t('open'), c: 'text-warn-ink' }
          : !r.watching || r.rollbacks === null ? { s: t('unknown'), c: 'text-muted' }
          : r.rollbacks === 0 ? { s: t('noRollback'), c: 'text-link' } : { s: t('rolledBack', { n: r.rollbacks }), c: 'text-warn-ink' }
        const on = data.current?.id === r.id
        return (
          <div key={r.id} className={`flex flex-wrap gap-x-[10px] gap-y-[2px] border-b border-line px-[18px] py-[9px] text-12.5 sm:grid sm:[grid-template-columns:minmax(0,1fr)_80px_90px_90px] ${on ? 'bg-highlight' : ''}`}>
            <b className="min-w-0 basis-full [overflow-wrap:anywhere] sm:basis-auto">
              <Link href={href('releases', r.id)} aria-current={on ? 'true' : undefined} className="text-ink hover:text-ink">{releaseTitle(pname(r.product), r.name)}</Link>
            </b>
            <span className="text-muted">{format.dateTime(new Date(when), { day: 'numeric', month: 'short' })}</span>
            <span>{t('notes', { n: r.notes })}</span>
            <span className={`font-bold ${status.c}`} title={!r.watching && r.state === 'recorded' ? t('unknownTitle') : undefined}>{status.s}</span>
          </div>
        )
      })}
    </div>
  )
}
