'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Audience, ErrorRow, NearLimit, Reach } from '@/lib/data/platform-plus'
import { createErrorTicket } from '../../plus-actions'
import { audienceOf, errorTone, limitTone } from './logic'
import { Head, p, usePlusAct } from './kit'

/**
 * Rollouts and announcements (PlatformPlus.dc.html, v.ops), Sentral's half. Orgpuls has no flags that can be staged per
 * organisation yet, so the rollouts card says so instead of drawing invented ones. The announcement composer counts its real
 * reach (the product's active customer users × live subscriptions) and cannot publish until Orgpuls has an in-app announcement
 * command. Accounts near their plan's employee limit come from the usage Orgpuls reports; notifying or raising waits for
 * Orgpuls' flow. Errors per customer are what Sentral itself knows: its own mail to the customer that did not arrive.
 */
export function OpsTab({ product, name, reach, limits, errors, canTicket, nf }: {
  product: string
  name: string
  reach: Record<Audience, Reach>
  limits: { warn_pct: number; usage: boolean; rows: NearLimit[] }
  errors: { hours: number; rows: ErrorRow[]; clean: number }
  canTicket: boolean
  nf: NumberFormat
}) {
  const t = useTranslations('platformPlus.ops')
  return (
    <div className="flex flex-col gap-[14px]">
      <div className={p.card}>
        <Head title={t('rollouts.title')} />
        <div className="px-[18px] py-[14px] text-12.5 text-muted">
          {t('rollouts.empty', { name })}{' '}
          <Link href="/platform" className="font-semibold">{t('rollouts.applications')}</Link>
        </div>
      </div>
      <div className={p.grid2}>
        <Announcement name={name} reach={reach} nf={nf} />
        <Limits name={name} limits={limits} nf={nf} />
      </div>
      <Errors product={product} name={name} errors={errors} canTicket={canTicket} nf={nf} />
    </div>
  )
}

function Announcement({ name, reach, nf }: { name: string; reach: Record<Audience, Reach>; nf: NumberFormat }) {
  const t = useTranslations('platformPlus.ops.announce')
  const [text, setText] = useState('')
  const [admins, setAdmins] = useState(false)
  const [trial, setTrial] = useState(false)
  const r = reach[audienceOf(admins, trial)]
  const chip = (on: boolean) => `cursor-pointer whitespace-nowrap rounded-999 border px-[10px] py-1 text-11.5 disabled:cursor-default ${
    on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
  return (
    <div className={`${p.cardPad} gap-[10px]`}>
      <b className={p.title}>{t('title')}</b>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        maxLength={300}
        aria-label={t('label')}
        placeholder={t('placeholder')}
        className="min-h-[60px] rounded-11 border border-line bg-canvas px-[11px] py-[9px] text-13 text-ink"
      />
      <div className="flex flex-wrap items-center gap-[6px]">
        <span className="text-12 text-muted">{t('showTo')}</span>
        <button type="button" disabled aria-pressed title={t('onlyProduct', { name })} className={chip(true)}>{name}</button>
        <button type="button" aria-pressed={admins} title={t('adminsTitle')} onClick={() => setAdmins(!admins)} className={chip(admins)}>{t('admins')}</button>
        <button type="button" aria-pressed={trial} onClick={() => setTrial(!trial)} className={chip(trial)}>{t('trial')}</button>
      </div>
      <div className="rounded-12 bg-highlight px-3 py-[10px] text-12.5"><b>{t('preview')}</b> {text}</div>
      <button
        type="button"
        disabled
        title={t('noCommand', { name })}
        className="h-8 cursor-default self-start rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold opacity-60"
      >
        {r.known ? t('publish', { count: r.users, n: formatNumber(r.users, nf) }) : t('publishUnknown')}
      </button>
      <span className="text-11.5 text-muted">{t('noCommand', { name })}</span>
    </div>
  )
}

function Limits({ name, limits, nf }: { name: string; limits: { warn_pct: number; usage: boolean; rows: NearLimit[] }; nf: NumberFormat }) {
  const t = useTranslations('platformPlus.ops.limits')
  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('warn', { pct: limits.warn_pct })} />
      {!limits.usage ? <div className={p.empty}>{t('noUsage', { name })}</div>
        : limits.rows.length === 0 ? <div className={p.empty}>{t('empty', { pct: limits.warn_pct })}</div> : null}
      {limits.rows.map((l) => (
        <div key={l.organization.id} className={`${p.row} grid items-center gap-[10px] py-[10px] text-12.5 [grid-template-columns:minmax(0,1.2fr)_minmax(0,1fr)_110px]`}>
          <span className="flex min-w-0 flex-col">
            <b>{l.organization.name}</b>
            <span className="text-11.5 text-muted">{t('what', { employees: formatNumber(l.employees, nf), max: formatNumber(l.max, nf) })}</span>
          </span>
          <span className="flex flex-col gap-[3px]">
            <span className={p.bar}><span className={`block h-full ${limitTone(l.pct)}`} style={{ width: `${Math.min(l.pct, 100)}%` }} /></span>
            <span className="text-11 text-muted">{`${formatNumber(l.pct, nf)} %`}</span>
          </span>
          <button type="button" disabled title={t('noFlow', { name })} className={`${p.btnRow} bg-surface`}>{t('notify')}</button>
        </div>
      ))}
      {limits.rows.length ? <div className={p.foot}>{t('noFlow', { name })}</div> : null}
    </div>
  )
}

function Errors({ product, name, errors, canTicket, nf }: {
  product: string
  name: string
  errors: { hours: number; rows: ErrorRow[]; clean: number }
  canTicket: boolean
  nf: NumberFormat
}) {
  const t = useTranslations('platformPlus.ops.errors')
  const { run, pending, flash } = usePlusAct()
  const what = (e: ErrorRow) => [
    e.replies ? t('replies', { count: e.replies }) : null,
    e.bounces ? t('bounces', { count: e.bounces }) : null,
    e.failed ? t('failed', { count: e.failed }) : null,
  ].filter(Boolean).join(' · ')
  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('sub')} />
      {errors.rows.length === 0 ? <div className={p.empty}>{t('empty', { name })}</div> : null}
      {errors.rows.map((e) => (
        <div key={e.organization.id} className={`${p.row} ${p.stackRow} md:[grid-template-columns:minmax(0,1.1fr)_minmax(0,1.6fr)_70px_110px]`}>
          <b className="min-w-0 [overflow-wrap:anywhere]">{e.organization.name}</b>
          <span className="order-2 min-w-0 text-muted md:order-none">{what(e)}</span>
          <b className={`order-1 text-right md:order-none md:text-left ${errorTone(e.total)}`}>{formatNumber(e.total, nf)}</b>
          {e.ticket ? (
            <Link href={`/tickets?ticket=${e.ticket.id}`} className={`${p.btnRowSoft} order-3 flex items-center justify-center text-ink hover:text-ink hover:no-underline md:order-none`}>{t('open')}</Link>
          ) : (
            <button
              type="button"
              disabled={!canTicket || pending}
              title={canTicket ? undefined : t('noRight')}
              onClick={() => run(() => createErrorTicket({ org: e.organization.id, product }), (r) => flash(r.existing ? t('existing', { ref: r.ref }) : t('created', { ref: r.ref })))}
              className={`${p.btnRowSoft} order-3 md:order-none`}
            >
              {t('create')}
            </button>
          )}
        </div>
      ))}
      <div className={p.foot}>
        {errors.rows.length ? `${t('clean', { count: errors.clean })} · ` : ''}
        {t('productErrors', { name })}
      </div>
    </div>
  )
}
