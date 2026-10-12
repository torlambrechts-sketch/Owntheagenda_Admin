'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useFormatter, useTranslations } from 'next-intl'
import type { CurrentRelease, Releases } from '@/lib/data/dev-delivery'
import { signItem } from '../../delivery-actions'
import { GATE_ORDER, orderChecks, verdict, type CheckKey } from './logic'
import { releaseTitle, useCheckText, useProductName } from './checks'
import { useRun } from './kit'
import { d } from './styles'

/** the items «Ask Claude to fix» stands beside in the design; it needs GitHub, which Sentral does not reach */
const FIXABLE: CheckKey[] = ['deps', 'help']

/** Release gate (DevClaude.dc.html v.gate): the verdict, the items with where each comes from, sign-offs by a person. */
export function GateBoard({ data }: { data: Releases }) {
  const t = useTranslations('devDelivery.gate')
  const format = useFormatter()
  const pname = useProductName(data.products)
  const cur = data.current
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      {cur ? <GateCard data={data} cur={cur} /> : (
        <div className={`${d.cardInk} flex flex-col gap-2 px-5 py-4`}>
          <b className={d.serif20}>{t('none.title')}</b>
          <span className="text-12.5 text-muted">{t('none.body')}</span>
          <Link href={'/development?tab=releases' as Route} className="text-12.5 font-semibold">{t('none.link')}</Link>
        </div>
      )}
      <div className={`${d.card} min-w-0 overflow-hidden`}>
        <div className={d.head}><b className={d.headTitle}>{t('releases.title')}</b><span className={d.headNote}>{t('releases.note')}</span></div>
        {data.releases.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('releases.empty')}</div> : null}
        {data.releases.map((r) => {
          const on = cur?.id === r.id
          return (
            <Link key={r.id} href={`/development?tab=gate&release=${r.id}` as Route} aria-current={on ? 'true' : undefined}
              className={`flex items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 text-ink hover:text-ink hover:no-underline ${on ? 'bg-highlight' : ''}`}>
              <span className={`w-[7px] self-stretch rounded-999 ${r.state === 'recorded' ? 'bg-ok' : 'bg-warn'}`} aria-hidden />
              <span className="flex min-w-0 flex-1 flex-col">
                <b className="[overflow-wrap:anywhere]">{releaseTitle(pname(r.product), r.name)}</b>
                <span className="text-11.5 text-muted">
                  {r.state === 'recorded' && r.recorded_at
                    ? t('releases.recorded', { day: format.dateTime(new Date(r.recorded_at), { day: 'numeric', month: 'short' }) })
                    : t('releases.open')}
                </span>
              </span>
            </Link>
          )
        })}
      </div>
    </div>
  )
}

function GateCard({ data, cur }: { data: Releases; cur: CurrentRelease }) {
  const t = useTranslations('devDelivery.gate')
  const format = useFormatter()
  const pname = useProductName(data.products)
  const text = useCheckText('gate', cur.watching)
  const { run, pending, mfa } = useRun()
  const [rollback, setRollback] = useState<string | null>(null)
  const items = orderChecks(cur.checks, GATE_ORDER)
  const v = verdict(items)
  const recorded = cur.state === 'recorded'
  const canSign = data.can_add && !recorded
  const fixShown = !recorded && items.some((c) => FIXABLE.includes(c.key) && c.state !== 'pass')
  const sign = (key: CheckKey, note: string | null = null) =>
    run(() => signItem({ release: cur.id, item: key, on: true, note }), () => t('signedToast'), () => setRollback(null))
  const state = recorded ? { s: t('recorded'), c: 'text-link' } : v.ready ? { s: t('ready'), c: 'text-link' } : { s: t('blocking', { n: v.blocking }), c: 'text-danger' }

  return (
    <div className={`${d.cardInk} flex min-w-0 flex-col gap-2 px-5 py-4`}>
      <div className="flex items-baseline justify-between gap-[10px]">
        <b className="font-serif text-20 [overflow-wrap:anywhere]">{t('title', { release: releaseTitle(pname(cur.product), cur.name) })}</b>
        <span className={`whitespace-nowrap text-12 font-bold ${state.c}`}>{state.s}</span>
      </div>
      <span className="text-12 text-muted">{t('subtitle')}</span>
      {items.map((c) => {
        const x = text(c)
        const ok = c.state === 'pass'
        return (
          <div key={c.key} className="flex flex-col gap-2 border-b border-tile py-[7px]">
            <div className="grid items-center gap-[10px] text-12.5 [grid-template-columns:22px_minmax(0,1fr)_110px]">
              <span aria-label={ok ? t('ok') : t('notOk')}
                className={`flex h-5 w-5 items-center justify-center rounded-999 text-11 font-bold ${ok ? 'bg-ok-bg text-ok-ink' : 'bg-peach text-rust-ink'}`}>
                {ok ? '✓' : '!'}
              </span>
              <span className="flex min-w-0 flex-col">
                <span>{x.label}</span>
                <span className="text-11 text-faint [overflow-wrap:anywhere]">
                  {x.source}
                  {x.sub && x.href ? <> · <a href={x.href} target="_blank" rel="noreferrer" className="font-semibold">{x.sub}</a></> : x.sub ? ` · ${x.sub}` : null}
                </span>
              </span>
              <span className="flex justify-end">
                {c.kind === 'manual' && !ok && canSign ? (
                  <button type="button" disabled={pending} onClick={() => (c.key === 'rollback' ? setRollback(rollback === null ? '' : null) : sign(c.key))}
                    className={d.rowBtn}>{t('signOff')}</button>
                ) : FIXABLE.includes(c.key) && !ok && !recorded ? (
                  <button type="button" disabled title={t('fixReason')} className={d.rowBtnPrimary}>{t('fix')}</button>
                ) : null}
              </span>
            </div>
            {c.key === 'rollback' && rollback !== null ? (
              <div className="flex flex-col gap-2 rounded-12 bg-canvas p-3">
                <label className={d.field}>
                  {t('rollbackPlan')}
                  <textarea value={rollback} onChange={(e) => setRollback(e.target.value.slice(0, 500))} maxLength={500} rows={3} placeholder={t('rollbackHint')}
                    className="min-h-[70px] rounded-12 border border-line bg-surface px-3 py-[10px] text-13 leading-[1.55] text-ink" />
                </label>
                <div className="flex flex-wrap gap-2">
                  <button type="button" disabled={pending || !rollback.trim()} onClick={() => sign('rollback', rollback.trim())} className={d.smallPrimary}>{t('signOff')}</button>
                  <button type="button" onClick={() => setRollback(null)} className={d.small}>{t('cancel')}</button>
                </div>
              </div>
            ) : null}
          </div>
        )
      })}
      {recorded ? (
        <div className={`${d.bigBtn} mt-[6px] flex items-center justify-center bg-ok-bg`}>
          {t('recordedButton', { day: format.dateTime(new Date(cur.recorded_at ?? cur.created_at), { day: 'numeric', month: 'short' }) })}
        </div>
      ) : v.ready ? (
        <Link href={`/development?tab=releases&release=${cur.id}` as Route}
          className={`${d.bigBtn} mt-[6px] flex items-center justify-center bg-primary text-ink hover:text-ink hover:no-underline`}>
          {t('toRecord')}
        </Link>
      ) : (
        <div aria-disabled="true" className={`${d.bigBtn} mt-[6px] flex items-center justify-center bg-primary opacity-50`}>{t('blocked')}</div>
      )}
      {mfa}
      {fixShown ? <span className="text-11.5 text-faint">{t('fixReason')}</span> : null}
    </div>
  )
}
