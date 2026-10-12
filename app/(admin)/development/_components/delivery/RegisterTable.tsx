'use client'

import { Fragment, useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useFormatter, useTranslations } from 'next-intl'
import { percent, type NumberFormat } from '@/lib/format'
import type { Register, RegisterRow } from '@/lib/data/dev-delivery'
import { planDone, planUpgrade, setIntegration } from '../../delivery-actions'
import { API_VERSIONS, RENEW_HREF, daysUntil, errorRate } from './logic'
import { useRun } from './kit'
import { d } from './styles'

/** the action column fits the longest action in either language (no: «Planlegg oppgradering») */
const GRID = '[grid-template-columns:minmax(0,1.3fr)_90px_90px_70px_100px_minmax(0,1.5fr)_150px]'
const firstName = (s: string | null | undefined) => (s ? s.split(/\s+/)[0] ?? s : null)

/** Integrations register (DevHub.dc.html v.integrations): one row per integration Sentral itself depends on. */
export function RegisterTable({ data, nf, now }: { data: Register; nf: NumberFormat; now: number }) {
  const t = useTranslations('devDelivery.register')
  const format = useFormatter()
  const { run, pending, mfa } = useRun()
  const [edit, setEdit] = useState<string | null>(null)
  const [plan, setPlan] = useState<string | null>(null)
  const day = (v: string) => format.dateTime(new Date(`${v.slice(0, 10)}T12:00:00`), { day: 'numeric', month: 'short', year: 'numeric' })

  return (
    <div className={`${d.card} overflow-hidden`}>
      <div className={d.head}><b className={d.headTitle}>{t('title')}</b><span className={d.headNote}>{t('note')}</span></div>
      {mfa ? <div className="px-[18px] py-3">{mfa}</div> : null}
      <div className="overflow-x-auto">
        <div className="min-w-[860px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${d.colHead} ${GRID}`}>
            <span>{t('cols.integration')}</span><span>{t('cols.owner')}</span><span>{t('cols.version')}</span>
            <span title={t('cols.errorsTitle')}>{t('cols.errors')}</span><span>{t('cols.token')}</span><span>{t('cols.change')}</span><span />
          </div>
          {data.rows.map((r) => {
            const rate = errorRate(r.runs)
            const days = daysUntil(r.token_expires_at, now)
            const urgent = days !== null && days < 10
            const version = API_VERSIONS[r.key] ?? r.api_version
            const renew = urgent ? RENEW_HREF[r.key] : undefined
            const hasChange = !!r.change.text
            const planned = !!r.plan
            const status = r.direction === 'in' ? null : r.status && r.status !== 'connected' ? t(`status.${r.status === 'error' ? 'error' : 'off'}`) : null
            const editable = data.can_configure
            const cell = (children: React.ReactNode, cls = '') => editable ? (
              <button type="button" onClick={() => setEdit(edit === r.key ? null : r.key)} aria-expanded={edit === r.key} title={t('editTitle')}
                className={`cursor-pointer border-0 bg-transparent p-0 text-left text-12.5 hover:underline ${cls}`}>{children}</button>
            ) : <span className={cls}>{children}</span>
            return (
              <Fragment key={r.key}>
                <div className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 ${GRID}`}>
                  <span className="flex min-w-0 flex-col">
                    <b>{t(`rows.${r.key}.name`)}</b>
                    <span className="text-11 text-muted">{status ? `${t(`rows.${r.key}.use`)} · ${status}` : t(`rows.${r.key}.use`)}</span>
                  </span>
                  {cell(firstName(r.owner?.name) ?? '—', 'text-ink')}
                  <span className={`${d.mono} text-11.5`}>{version ?? '—'}</span>
                  <b className={rate !== null && rate > 1 ? 'text-danger' : 'text-ink'}
                    title={r.direction === 'in' ? t('inbound', { n: r.deliveries_30d ?? 0 }) : r.runs ? t('runs', { failed: r.runs.failed, total: r.runs.total }) : undefined}>
                    {rate === null ? '—' : percent(rate, nf)}
                  </b>
                  <span className={`font-bold ${urgent ? 'text-danger' : 'text-ink'}`}>
                    {days === null ? '—' : days < 0 ? t('expired') : t('inDays', { n: days })}
                  </span>
                  {cell(hasChange ? (r.change.due_on ? t('changeDue', { text: r.change.text ?? '', day: day(r.change.due_on) }) : r.change.text)
                    : r.change.none ? t('noneAnnounced') : '—', hasChange ? 'text-warn-ink' : 'text-faint')}
                  <span className="flex justify-end">
                    {renew ? (
                      <Link href={renew as Route} className="flex h-7 min-w-[100px] items-center justify-center whitespace-nowrap rounded-8 border border-ink bg-primary px-[10px] text-11.5 font-bold text-ink hover:text-ink hover:no-underline">
                        {t('renew')}
                      </Link>
                    ) : planned ? (
                      <button type="button" onClick={() => setPlan(plan === r.key ? null : r.key)} aria-expanded={plan === r.key}
                        className="h-7 min-w-[100px] cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-ok-bg px-[10px] text-11.5 font-bold text-ink">{t('planned')}</button>
                    ) : hasChange ? (
                      <button type="button" disabled={!data.can_add || pending} title={!data.can_add ? t('noRight') : undefined}
                        onClick={() => run(() => planUpgrade(r.key), () => t('plannedToast', { owner: r.owner?.name ?? t('noOwner') }))}
                        className="h-7 min-w-[100px] cursor-pointer whitespace-nowrap rounded-8 border border-ink bg-primary px-[10px] text-11.5 font-bold text-ink disabled:cursor-default disabled:opacity-50">
                        {t('plan')}
                      </button>
                    ) : null}
                  </span>
                </div>
                {plan === r.key && r.plan ? <PlanRow row={r} canAct={data.can_add} pending={pending} day={day}
                  onDone={() => run(() => planDone(r.plan!.id), () => t('doneToast'), () => setPlan(null))} /> : null}
                {edit === r.key ? <EditRow row={r} data={data} onClose={() => setEdit(null)} /> : null}
              </Fragment>
            )
          })}
        </div>
      </div>
      {!data.can_add && data.rows.some((r) => !!r.change.text && !r.plan) ? <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('noRight')}</div> : null}
    </div>
  )
}

function PlanRow({ row, canAct, pending, day, onDone }: { row: RegisterRow; canAct: boolean; pending: boolean; day: (v: string) => string; onDone: () => void }) {
  const t = useTranslations('devDelivery.register')
  const p = row.plan!
  return (
    <div className="flex flex-wrap items-center gap-3 border-b border-line bg-mint px-[18px] py-[10px] text-12.5">
      <span className="min-w-0 flex-1">
        {t('planLine', { by: p.planned_by ?? '—', day: day(p.planned_at), owner: p.owner ?? t('noOwner'), change: p.change_text })}
        {p.due_on ? ` · ${t('planDue', { day: day(p.due_on) })}` : ''}
      </span>
      {canAct ? <button type="button" disabled={pending} onClick={onDone} className={d.small}>{t('markDone')}</button> : null}
    </div>
  )
}

function EditRow({ row, data, onClose }: { row: RegisterRow; data: Register; onClose: () => void }) {
  const t = useTranslations('devDelivery.register.edit')
  const tr = useTranslations('devDelivery.register')
  const { run, pending, mfa } = useRun()
  const [owner, setOwner] = useState(row.owner?.id ?? '')
  const [text, setText] = useState(row.change.text ?? '')
  const [due, setDue] = useState(row.change.due_on ?? '')
  const [url, setUrl] = useState(row.change.url ?? '')
  const [none, setNone] = useState(row.change.none)
  const save = () => run(() => setIntegration({ key: row.key, owner: owner || null, changeText: text.trim(), dueOn: due || null, url: url.trim(), none: !text.trim() && none }),
    () => t('savedToast'), onClose)
  return (
    <div className="flex flex-col gap-2 border-b border-line bg-canvas px-[18px] py-3">
      <b className="text-13">{t('title', { name: tr(`rows.${row.key}.name`) })}</b>
      <div className="grid gap-2 [grid-template-columns:minmax(160px,220px)_minmax(220px,1fr)_160px]">
        <label className={d.field}>{t('owner')}
          <select value={owner} onChange={(e) => setOwner(e.target.value)} className={d.select}>
            <option value="">—</option>
            {data.staff.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
        <label className={d.field}>{t('change')}
          <input value={text} maxLength={200} onChange={(e) => setText(e.target.value)} placeholder={t('changePlaceholder')} className={d.input} />
        </label>
        <label className={d.field}>{t('due')}
          <input type="date" value={due} disabled={!text.trim()} onChange={(e) => setDue(e.target.value)} className={d.input} />
        </label>
      </div>
      <div className="grid gap-2 [grid-template-columns:minmax(220px,1fr)_auto]">
        <label className={d.field}>{t('url')}
          <input value={url} disabled={!text.trim()} maxLength={250} onChange={(e) => setUrl(e.target.value)} placeholder="https://" className={d.input} />
        </label>
        <label className="flex items-end gap-2 pb-[10px] text-12.5 text-ink">
          <input type="checkbox" checked={!text.trim() && none} disabled={!!text.trim()} onChange={(e) => setNone(e.target.checked)} />
          {t('none')}
        </label>
      </div>
      <div className="flex flex-wrap gap-2">
        <button type="button" disabled={pending} onClick={save} className={d.smallPrimary}>{t('save')}</button>
        <button type="button" onClick={onClose} className={d.small}>{t('cancel')}</button>
      </div>
      {mfa}
    </div>
  )
}
