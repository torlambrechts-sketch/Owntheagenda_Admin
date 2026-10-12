'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Status } from '@/lib/data/support-hub'
import { addComponent, openIncident, postIncidentUpdate, removeComponent, resolveIncident, setComponent } from '../../support-actions'
import { card, cardInk, useSupportError, Why } from './bits'
import { COMPONENT_STATES, componentTone, kindTone } from './logic'

type Incident = Status['incidents'][number]
const btn = 'h-8 cursor-pointer whitespace-nowrap rounded-9 border px-[13px] text-12 font-bold text-ink disabled:cursor-not-allowed disabled:opacity-60'
const field = 'rounded-10 border border-line bg-canvas px-[11px] text-12.5 text-ink'

/**
 * Status and changelog (SupportHub.dc.html, v.proactive): the product's components and incidents as Sentral's own records,
 * «Resolve and notify» through problem_resolve, the site notice the problem holds, and the changelog from release_notes
 * (0078). Nothing is public yet: a status page waits for a host decision (V-V3S-17).
 */
export function StatusView({ data, product, dates, times }: { data: Status; product: string; dates: Record<string, string>; times: Record<string, string> }) {
  const t = useTranslations('supportHub.status')
  const open = data.incidents.filter((i) => i.state !== 'resolved')
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <Components data={data} product={product} />
      <div className="flex flex-col gap-3">
        {data.can_edit ? <NewIncident data={data} product={product} /> : null}
        {open.length === 0 ? <div className={`${card} px-[18px] py-4 text-12.5 text-muted`}>{t('noIncidents')}</div> : null}
        {data.incidents.map((i) => <IncidentCard key={i.id} i={i} canEdit={data.can_edit} times={times} />)}
        <div className={`${card} overflow-hidden`}>
          <div className="border-b border-line px-[18px] py-[13px] text-15 font-bold">{t('changelog')}</div>
          {data.changelog.length === 0 ? <div className="px-[18px] py-[10px] text-12.5 text-muted">{t('changelogEmpty')}</div> : null}
          {data.changelog.map((c) => (
            <div key={c.id} className="flex gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5">
              <span className="w-[60px] flex-none text-muted">{dates[c.id]}</span>
              <span className={`h-[18px] flex-none rounded-999 px-2 py-[1px] text-10.5 font-bold ${kindTone(c.kind)}`}>{t(`kinds.${c.kind}`)}</span>
              <span>{c.title}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function Components({ data, product }: { data: Status; product: string }) {
  const t = useTranslations('supportHub.status')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [name, setName] = useState('')
  const [pending, start] = useTransition()
  const run = (f: () => Promise<{ ok: boolean; code?: string }>, done?: string) => start(async () => {
    const r = await f()
    if (!r.ok) { flash(errorText(r.code ?? 'failed')); return }
    if (done) flash(done)
    router.refresh()
  })
  return (
    <div className={`${card} overflow-hidden`}>
      <div className="flex justify-between gap-[10px] border-b border-line px-[18px] py-[13px]">
        <b className="text-15">{t('pageTitle')}</b>
        <span className="text-12 text-muted" title={t('notPublicWhy')}>{t('notPublic')}</span>
      </div>
      {data.components.length === 0 ? <div className="border-b border-line px-[18px] py-[10px] text-12.5 text-muted">{t('componentsEmpty')}</div> : null}
      {data.components.map((c) => (
        <div key={c.id} className="flex items-center justify-between gap-2 border-b border-line px-[18px] py-[10px] text-12.5">
          <b className="min-w-0 flex-1 [overflow-wrap:anywhere]">{c.name}</b>
          {data.can_edit ? (
            <button type="button" aria-label={t('remove', { name: c.name })} title={t('remove', { name: c.name })} disabled={pending}
              onClick={() => run(() => removeComponent({ id: c.id }))}
              className="h-[30px] w-[30px] flex-none cursor-pointer rounded-8 border border-line bg-transparent text-13 text-muted">×</button>
          ) : null}
          <select
            value={c.state}
            disabled={!data.can_edit || pending}
            aria-label={t('stateOf', { name: c.name })}
            onChange={(e) => run(() => setComponent({ id: c.id, state: e.target.value }), t('stateSet', { name: c.name, state: t(`states.${e.target.value}`) }))}
            className={`h-[30px] rounded-8 border border-line text-12 font-bold text-ink ${componentTone(c.state)}`}
          >
            {COMPONENT_STATES.map((s) => <option key={s} value={s}>{t(`states.${s}`)}</option>)}
          </select>
        </div>
      ))}
      {data.can_edit ? (
        <form className="flex flex-wrap gap-2 border-b border-line px-[18px] py-[10px]"
          onSubmit={(e) => { e.preventDefault(); if (name.trim().length >= 2) run(async () => { const r = await addComponent({ product, name }); if (r.ok) setName(''); return r }, t('componentAdded', { name: name.trim() })) }}>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} placeholder={t('componentName')} aria-label={t('componentName')} className={`h-8 min-w-0 flex-1 ${field}`} />
          <button type="submit" disabled={pending || name.trim().length < 2} className={`${btn} border-ink bg-primary`}>{t('addComponent')}</button>
        </form>
      ) : null}
      <div className="px-[18px] py-[9px]"><Why>{data.can_edit ? t('notPublicWhy') : t('editWhy')}</Why></div>
    </div>
  )
}

function NewIncident({ data, product }: { data: Status; product: string }) {
  const t = useTranslations('supportHub.status.new')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [show, setShow] = useState(false)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [problem, setProblem] = useState('')
  const [comps, setComps] = useState<string[]>([])
  const [pending, start] = useTransition()
  if (!show) return <button type="button" onClick={() => setShow(true)} className={`${btn} self-start border-ink bg-primary`}>{t('open')}</button>
  const submit = () => start(async () => {
    const r = await openIncident({ product, title, body, problem: problem || null, components: comps })
    if (!r.ok) { flash(errorText(r.code)); return }
    flash(t('opened'))
    setShow(false)
    router.refresh()
  })
  return (
    <div className={`${cardInk} flex flex-col gap-2 px-[18px] py-4`}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} placeholder={t('title')} aria-label={t('title')} className={`h-9 ${field}`} />
      <textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={4000} placeholder={t('body')} aria-label={t('body')} className={`min-h-[70px] py-[9px] ${field}`} />
      <label className="flex flex-col gap-1 text-11.5 text-muted">
        {t('problem')}
        <select value={problem} onChange={(e) => setProblem(e.target.value)} className={`h-8 ${field}`}>
          <option value="">{t('problemNone')}</option>
          {data.problems.map((p) => <option key={p.id} value={p.id}>{`${p.ref} · ${p.subject}`}</option>)}
        </select>
      </label>
      {data.components.length > 0 ? (
        <fieldset className="m-0 flex flex-wrap gap-x-3 gap-y-1 border-none p-0 text-12">
          <legend className="mb-1 p-0 text-11.5 text-muted">{t('components')}</legend>
          {data.components.map((c) => (
            <label key={c.id} className="flex items-center gap-[6px]">
              <input type="checkbox" checked={comps.includes(c.id)} onChange={(e) => setComps((x) => (e.target.checked ? [...x, c.id] : x.filter((y) => y !== c.id)))} className="accent-ink" />
              {c.name}
            </label>
          ))}
        </fieldset>
      ) : null}
      <Why>{t('note')}</Why>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={() => setShow(false)} className={`${btn} border-line bg-transparent font-semibold`}>{t('cancel')}</button>
        <button type="button" onClick={submit} disabled={pending || title.trim().length < 3 || !body.trim()} className={`${btn} border-ink bg-primary`}>{t('submit')}</button>
      </div>
    </div>
  )
}

function IncidentCard({ i, canEdit, times }: { i: Incident; canEdit: boolean; times: Record<string, string> }) {
  const t = useTranslations('supportHub.status')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [form, setForm] = useState<'none' | 'update' | 'resolve'>('none')
  const [text, setText] = useState('')
  const [state, setState] = useState<'investigating' | 'identified' | 'monitoring'>(i.state === 'resolved' ? 'monitoring' : i.state)
  const [pending, start] = useTransition()
  const open = i.state !== 'resolved'
  // a ✓ only for what is true; a notice Orgpuls has not taken (or not yet removed) says so instead
  const notice = i.notice
  const noticeChip = (): { text: string; ok: boolean } | null => {
    if (!notice) return null
    if (notice.state === 'shown') return open ? { text: t('chips.notice'), ok: true } : null
    if (notice.state === 'removed') return open ? null : { text: t('chips.noticeCleared'), ok: true }
    const key = notice.state === 'not_delivered' ? 'noticeNotDelivered' : 'removalNotDelivered'
    return { text: notice.error ? t(`chips.${key}Why`, { error: notice.error }) : t(`chips.${key}`), ok: false }
  }
  const chips = (open
    ? [noticeChip(), i.linked > 0 ? { text: t('chips.linked', { n: i.linked }), ok: true } : null]
    : [noticeChip(), (i.notified ?? 0) > 0 ? { text: t('chips.resolved', { n: i.notified ?? 0 }), ok: true } : null,
       (i.emailed ?? 0) > 0 ? { text: t('chips.emailed', { n: i.emailed ?? 0 }), ok: true } : null]
  ).filter((c): c is { text: string; ok: boolean } => c !== null)
  const submit = () => start(async () => {
    if (form === 'resolve') {
      const r = await resolveIncident({ id: i.id, message: text })
      if (!r.ok) { flash(errorText(r.code)); return }
      // what happened: tickets resolved with the reply, and whether any of it can be emailed
      flash(r.notified > 0 && !r.mailReady ? t('resolvedToastNoMail', { n: r.notified }) : t('resolvedToast', { n: r.notified }))
    } else {
      const r = await postIncidentUpdate({ id: i.id, state, body: text })
      if (!r.ok) { flash(errorText(r.code)); return }
      flash(t('updatedToast'))
    }
    setForm('none')
    setText('')
    router.refresh()
  })
  return (
    <div className={`${open ? cardInk : card} flex flex-col gap-2 px-[18px] py-4`}>
      <div className="flex justify-between gap-[10px]">
        <b className="text-14">{i.title}</b>
        <span className={`whitespace-nowrap text-11.5 font-bold ${open ? 'text-warn-ink' : 'text-link'}`}>{t(`incidentStates.${i.state}`)}</span>
      </div>
      {i.body ? <span className="text-12.5 text-ink-2">{i.body}</span> : null}
      {i.problem ? <span className="text-12 text-muted">{t('affected', { n: i.customers, ref: i.problem.ref })}</span> : null}
      {chips.length > 0 ? (
        <div className="flex flex-wrap gap-[6px]">
          {chips.map((c) => <span key={c.text} className={`rounded-999 px-[9px] py-[3px] text-11 font-bold ${c.ok ? 'bg-ok-bg' : 'bg-amber-bg'}`}>{c.ok ? `✓ ${c.text}` : c.text}</span>)}
        </div>
      ) : null}
      {/* the opening update repeats the description: it is shown once */}
      {i.updates.filter((u, n) => !(n === i.updates.length - 1 && u.body === i.body)).slice(0, 3).map((u) => (
        <div key={u.at} className="text-11.5 text-muted"><b className="text-ink-2">{times[`${i.id}:${u.at}`]} · {t(`incidentStates.${u.state}`)}</b> · {u.body}</div>
      ))}
      {open && canEdit && form === 'none' ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => setForm('resolve')} className={`${btn} self-start border-ink bg-primary`}>{i.problem ? t('resolve') : t('resolveOnly')}</button>
          <button type="button" onClick={() => setForm('update')} className={`${btn} border-line bg-transparent font-semibold`}>{t('update')}</button>
        </div>
      ) : null}
      {open && !canEdit ? <Why>{t('editWhy')}</Why> : null}
      {form !== 'none' ? (
        <div className="flex flex-col gap-2">
          {form === 'update' ? (
            <select value={state} onChange={(e) => setState(e.target.value as typeof state)} aria-label={t('updateState')} className={`h-8 self-start ${field}`}>
              {(['investigating', 'identified', 'monitoring'] as const).map((s) => <option key={s} value={s}>{t(`incidentStates.${s}`)}</option>)}
            </select>
          ) : null}
          <textarea value={text} onChange={(e) => setText(e.target.value)} maxLength={4000}
            placeholder={form === 'resolve' ? (i.problem ? t('resolveMessage') : t('resolveNote')) : t('updatePlaceholder')}
            aria-label={form === 'resolve' ? t('resolveMessage') : t('updatePlaceholder')} className={`min-h-[70px] py-[9px] ${field}`} />
          {form === 'resolve' && i.problem ? <Why>{t('resolveWhat', { ref: i.problem.ref })}</Why> : null}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setForm('none')} className={`${btn} border-line bg-transparent font-semibold`}>{t('cancel')}</button>
            <button type="button" onClick={submit} disabled={pending || !text.trim()} className={`${btn} border-ink bg-primary`}>{form === 'resolve' ? t('send') : t('post')}</button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
