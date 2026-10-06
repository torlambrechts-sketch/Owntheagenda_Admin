'use client'

import Link from 'next/link'
import { useEffect, useRef, useState, useTransition } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { bulkAddLabel, bulkOwner, logExport, saveView } from '../actions'
import { statusTone } from './tones'
import { Modal, btnCancel, btnConfirm, field, fieldInput } from './Modal'
import { useErrorText } from './useErrorText'

export type ListRow = {
  id: string
  name: string
  orgnr: string
  status: string | null
  statusLabel: string
  plan: string
  employees: string
  ls: string
  lsDanger: boolean
  resp: string
  mrr: string
  mrrValue: number
  signup: string
  prods: { key: string; name: string; color: string; ink: string }[]
  labelIds: string[]
  labels: string[]
  csv: (string | number)[]
}
type Filter = { key: string; label: string; value: string; options: { value: string; label: string }[] }
type Props = {
  rows: ListRow[]
  q: string
  view: string
  views: { key: string; label: string; count: number }[]
  saved: { id: string; name: string; query: Record<string, string> }[]
  filters: Filter[]
  listMrr: string
  labels: { id: string; name: string }[]
  staff: { id: string; name: string }[]
  rights: { bulk: boolean; export: boolean }
}

const GRID = '[grid-template-columns:34px_minmax(220px,2.2fr)_110px_96px_80px_80px_96px_80px_120px_96px_84px]'
const QUERY_KEYS = ['q', 'view', 'status', 'plan', 'industry', 'fylke', 'source', 'uses'] as const
const bulkBtn = 'h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-55'
const menu = 'absolute right-0 top-[34px] z-30 max-h-[320px] w-[240px] overflow-y-auto rounded-18 border border-line bg-surface p-[6px] shadow-pop'
const menuItem = 'flex w-full cursor-pointer rounded-10 border-none bg-transparent px-[11px] py-2 text-left text-13 font-semibold text-ink'

/** A spreadsheet cell that cannot run as a formula (CSV injection) and survives commas and quotes. */
const cell = (v: string | number) => {
  let s = String(v)
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`
  return /[",;\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function OrgList({ rows, q, view, views, saved, filters, listMrr, labels, staff, rights }: Props) {
  const t = useTranslations('customers')
  const err = useErrorText()
  const flash = useToast()
  const router = useRouter()
  const pathname = usePathname()
  const params = useSearchParams()
  const [, start] = useTransition()
  const [text, setText] = useState(q)
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [pop, setPop] = useState<'tag' | 'owner' | null>(null)
  const [naming, setNaming] = useState(false)
  const [viewName, setViewName] = useState('')
  const [busy, setBusy] = useState(false)
  const popRef = useRef<HTMLSpanElement>(null)

  const go = (next: Record<string, string | null>) => {
    const sp = new URLSearchParams(params.toString())
    for (const [k, v] of Object.entries(next)) {
      if (v) sp.set(k, v)
      else sp.delete(k)
    }
    if (sp.get('view') === 'all') sp.delete('view')
    const s = sp.toString()
    start(() => router.replace((s ? `${pathname}?${s}` : pathname) as never, { scroll: false }))
  }

  // the search follows typing after a short pause
  useEffect(() => {
    if (text === q) return
    const h = setTimeout(() => go({ q: text.trim() || null }), 300)
    return () => clearTimeout(h)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text])

  useEffect(() => {
    if (!pop) return
    const close = (e: MouseEvent) => { if (!popRef.current?.contains(e.target as Node)) setPop(null) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setPop(null) }
    document.addEventListener('mousedown', close)
    document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', esc) }
  }, [pop])

  // selection holds only rows still in the list
  const visible = new Set(rows.map((r) => r.id))
  const selected = [...sel].filter((id) => visible.has(id))
  const anyFilter = filters.some((f) => f.value)
  const currentQuery = Object.fromEntries(QUERY_KEYS.map((k) => [k, params.get(k) ?? '']).filter(([, v]) => v))

  const exportCsv = async () => {
    const r = await logExport({ rows: rows.length })
    if (!r.ok) return flash(err(r.code))
    const head = ['name', 'orgnr', 'status', 'plan', 'staff', 'lastSurvey', 'response', 'mrr', 'signup', 'applications', 'tags'].map((k) => t(`csv.${k}`))
    const csv = [head, ...rows.map((x) => x.csv)].map((line) => line.map(cell).join(',')).join('\r\n')
    const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `organizations-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
    flash(t('toast.exported', { n: rows.length }))
  }

  const addTag = async (label: string) => {
    setPop(null)
    setBusy(true)
    const items = rows.filter((r) => selected.includes(r.id)).map((r) => ({ id: r.id, labels: r.labelIds }))
    const r = await bulkAddLabel({ items, label })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    setSel(new Set())
    flash(t('toast.tagAdded', { n: r.updated }))
  }

  const assignOwner = async (owner: string) => {
    setPop(null)
    setBusy(true)
    const r = await bulkOwner({ ids: selected, owner })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    setSel(new Set())
    flash(t('toast.ownerAssigned', { n: r.updated }))
  }

  const storeView = async () => {
    const r = await saveView({ name: viewName, query: currentQuery })
    if (!r.ok) return flash(err(r.code))
    setNaming(false)
    setViewName('')
    flash(t('toast.viewSaved'))
  }

  const toggle = (id: string) => setSel((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n })

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex h-[38px] min-w-0 flex-[1_1_280px] items-center gap-2 rounded-10 border border-line bg-surface px-3">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#5F5849" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true"><path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14M20 20l-4-4" /></svg>
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={t('list.search')}
            aria-label={t('list.search')}
            className="min-w-0 flex-1 border-none bg-transparent text-13 outline-none"
          />
        </div>
        <button type="button" onClick={exportCsv} disabled={!rights.export} title={rights.export ? undefined : t('rights.export')} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-[14px] text-12.5 font-semibold disabled:cursor-default disabled:opacity-55">
          {t('list.export')}
        </button>
        <button type="button" onClick={() => setNaming(true)} className="h-9 cursor-pointer rounded-10 border border-ink bg-surface px-[14px] text-12.5 font-bold">
          {t('list.saveView')}
        </button>
      </div>

      <div className="flex flex-wrap items-center gap-[6px]">
        <span className="mr-1 text-11 font-bold uppercase tracking-eyebrow text-muted">{t('list.savedViews')}</span>
        {views.map((v) => (
          <button key={v.key} type="button" aria-pressed={view === v.key} onClick={() => go({ view: v.key })} className={pillSoft(view === v.key)}>
            {v.label} <span className="text-muted">{v.count}</span>
          </button>
        ))}
        {saved.map((v) => {
          const on = Object.keys(v.query).length > 0 && QUERY_KEYS.every((k) => (v.query[k] ?? '') === (currentQuery[k] ?? ''))
          return (
            <button key={v.id} type="button" aria-pressed={on} onClick={() => start(() => router.replace(`${pathname}?${new URLSearchParams(v.query)}` as never, { scroll: false }))} className={pillSoft(on)}>
              {v.name}
            </button>
          )
        })}
      </div>

      <div className="flex flex-wrap gap-2">
        {filters.map((f) => (
          <label key={f.key} className={`flex h-[34px] items-center gap-[6px] rounded-10 border bg-surface pl-[11px] pr-1 text-12 text-muted ${f.value ? 'border-ink' : 'border-line'}`}>
            {f.label}
            <select value={f.value} onChange={(e) => go({ [f.key]: e.target.value || null })} className="border-none bg-transparent p-1 text-12.5 font-semibold text-ink outline-none">
              <option value="">{t('filters.any')}</option>
              {f.options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </label>
        ))}
        {anyFilter ? (
          <button type="button" onClick={() => go(Object.fromEntries(filters.map((f) => [f.key, null])))} className="h-[34px] cursor-pointer rounded-10 border-none bg-transparent px-3 text-12.5 font-semibold text-link">
            {t('list.clear')}
          </button>
        ) : null}
      </div>

      <div className="rounded-20 border border-line bg-surface">
        <div className="flex flex-wrap items-center gap-3 border-b border-line px-[18px] py-3 text-12.5 text-muted">
          <span>{t.rich('list.summary', { n: rows.length, mrr: listMrr, b: (c) => <b className="text-ink">{c}</b> })}</span>
          <span className="flex-1" />
          {selected.length ? (
            <span ref={popRef} className="relative flex items-center gap-[6px]">
              <b className="text-ink">{t('list.selected', { n: selected.length })}</b>
              <button type="button" disabled={!rights.bulk || busy} title={rights.bulk ? undefined : t('rights.bulk')} aria-expanded={pop === 'tag'} onClick={() => setPop(pop === 'tag' ? null : 'tag')} className={bulkBtn}>{t('list.addTag')}</button>
              <button type="button" disabled={!rights.bulk || busy} title={rights.bulk ? undefined : t('rights.bulk')} aria-expanded={pop === 'owner'} onClick={() => setPop(pop === 'owner' ? null : 'owner')} className={bulkBtn}>{t('list.assignOwner')}</button>
              <Link href="/campaigns" className={`${bulkBtn} inline-flex items-center text-ink hover:text-ink hover:no-underline`}>{t('list.broadcast')}</Link>
              {pop === 'tag' ? (
                <div className={menu} role="menu">
                  {labels.map((l) => <button key={l.id} type="button" role="menuitem" onClick={() => addTag(l.id)} className={menuItem}>{l.name}</button>)}
                  {labels.length === 0 ? <div className="px-[11px] py-2 text-12 text-muted">{t('list.noTags')}</div> : null}
                </div>
              ) : null}
              {pop === 'owner' ? (
                <div className={menu} role="menu">
                  {staff.map((s) => <button key={s.id} type="button" role="menuitem" onClick={() => assignOwner(s.id)} className={menuItem}>{s.name}</button>)}
                </div>
              ) : null}
            </span>
          ) : null}
        </div>
        <div className="overflow-x-auto rounded-b-20">
          <div className="min-w-[1120px]">
            <div className={`grid gap-[10px] border-b border-line px-[18px] py-[10px] text-10.5 font-bold uppercase tracking-label text-muted ${GRID}`}>
              <span />
              <span>{t('cols.name')}</span><span>{t('cols.orgnr')}</span><span>{t('cols.status')}</span><span>{t('cols.plan')}</span><span>{t('cols.staff')}</span>
              <span>{t('cols.lastSurvey')}</span><span>{t('cols.response')}</span><span>{t('cols.health')}</span><span>{t('cols.mrr')}</span><span>{t('cols.signup')}</span>
            </div>
            {rows.map((o) => {
              const on = sel.has(o.id)
              return (
                <div key={o.id} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-13 ${GRID} ${on ? 'bg-highlight' : 'bg-transparent'}`}>
                  <input type="checkbox" checked={on} onChange={() => toggle(o.id)} aria-label={t('list.select', { name: o.name })} className="h-4 w-4 [accent-color:#191510]" />
                  <Link href={`/customers?org=${o.id}` as never} className="flex min-w-0 cursor-pointer flex-col gap-[3px] text-left text-[13.333px] text-ink hover:text-ink hover:no-underline">
                    <span className="overflow-hidden text-ellipsis whitespace-nowrap font-bold">{o.name}</span>
                    <span className="flex flex-wrap gap-1">
                      {o.prods.map((p) => <span key={p.key} className="rounded-999 px-[7px] py-px text-10.5 font-bold" style={{ background: p.color, color: p.ink }}>{p.name}</span>)}
                      {o.labels.map((l) => <span key={l} className="rounded-999 border border-line-strong px-[7px] py-px text-10.5 font-semibold text-muted">{l}</span>)}
                    </span>
                  </Link>
                  <span className="tabular-nums text-ink-2">{o.orgnr}</span>
                  <span><span className={`inline-block rounded-999 px-[10px] py-[3px] text-11.5 font-bold ${statusTone(o.status)}`}>{o.statusLabel}</span></span>
                  <span className="text-ink-2">{o.plan}</span>
                  <span className="tabular-nums">{o.employees}</span>
                  <span className={o.lsDanger ? 'text-danger' : 'text-ink-2'}>{o.ls}</span>
                  <span className="tabular-nums">{o.resp}</span>
                  <span className="text-muted">—</span>
                  <span className="font-semibold tabular-nums">{o.mrr}</span>
                  <span className="text-muted">{o.signup}</span>
                </div>
              )
            })}
            {rows.length === 0 ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('list.empty')}</div> : null}
          </div>
        </div>
      </div>

      {naming ? (
        <Modal eyebrow={t('views.modalEyebrow')} title={t('list.saveView')} onClose={() => setNaming(false)}>
          <div className="text-13 leading-[1.55] text-ink-2">{t('views.modalPreview')}</div>
          <label className={field}>
            {t('views.name')}
            <input value={viewName} onChange={(e) => setViewName(e.target.value)} maxLength={80} placeholder={t('views.namePlaceholder')} className={fieldInput} />
          </label>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setNaming(false)} className={btnCancel}>{t('modal.cancel')}</button>
            <button type="button" onClick={storeView} disabled={!viewName.trim()} className={`${btnConfirm} bg-primary ${viewName.trim() ? '' : 'opacity-55'}`}>{t('views.save')}</button>
          </div>
        </Modal>
      ) : null}
    </div>
  )
}

const pillSoft = (on: boolean) => `cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
