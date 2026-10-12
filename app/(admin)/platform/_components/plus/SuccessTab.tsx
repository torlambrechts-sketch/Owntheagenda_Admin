'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { formatNumber, money, type NumberFormat } from '@/lib/format'
import type { AccountOption, FeatureRequest, Onboarding, Signal } from '@/lib/data/platform-plus'
import { Dialog } from '../../../applications/_components/kit'
import { addRequest, createSuccessDeal, createSuccessTask, setRequestStatus, voteRequest } from '../../plus-actions'
import { REQUEST_STATUSES, STATUS_BG, pctOf } from './logic'
import { Head, p, usePlusAct } from './kit'

/**
 * Customer success (PlatformPlus.dc.html, v.success) on Sentral's own data. Onboarding completion by step for the accounts
 * created in the last 180 days, from the usage, members and milestones the product reports (a step it never reports is «—»);
 * no NPS source exists; feature requests (0078) with their votes, linked tickets and deals and — for people who may see deals —
 * the MRR of the accounts asking; renewal and expansion signals with «Create deal» and «CSM task», each made once while open.
 */
export function SuccessTab({ product, name, onboarding, requests, signals, accounts, canAddRequest, canDeal, nf }: {
  product: string
  name: string
  onboarding: Onboarding
  requests: { money: boolean; rows: FeatureRequest[] }
  signals: Signal[]
  accounts: AccountOption[]
  canAddRequest: boolean
  canDeal: boolean
  nf: NumberFormat
}) {
  return (
    <div className="flex flex-col gap-[14px]">
      <div className={p.grid2}>
        <OnboardingCard name={name} onboarding={onboarding} nf={nf} />
        <Nps name={name} />
      </div>
      <Requests product={product} name={name} requests={requests} accounts={accounts} canAdd={canAddRequest} nf={nf} />
      <Renewals product={product} name={name} signals={signals} canDeal={canDeal} nf={nf} />
    </div>
  )
}

function OnboardingCard({ name, onboarding, nf }: { name: string; onboarding: Onboarding; nf: NumberFormat }) {
  const t = useTranslations('platformPlus.success.onboarding')
  const waiting = onboarding.steps.some((s) => s.done === null)
  return (
    <div className={`${p.cardPad} gap-2`}>
      <div className="flex items-baseline justify-between gap-[10px]">
        <b className={p.title}>{t('title')}</b>
        <span className={p.sub}>{t('sub')}</span>
      </div>
      {onboarding.steps.map((s) => {
        const pct = pctOf(s.done, onboarding.cohort)
        return (
          <div key={s.key} className="grid min-h-[30px] items-center gap-[10px] py-[5px] text-12.5 [grid-template-columns:minmax(0,1fr)_110px_44px]">
            <span>{t(`steps.${s.key}`)}</span>
            <span className={p.bar}><span className="block h-full bg-ok" style={{ width: `${pct ?? 0}%` }} /></span>
            <b className="text-right">{pct === null ? '—' : `${formatNumber(pct, nf)} %`}</b>
          </div>
        )
      })}
      <span className="text-11.5 text-muted">
        {t('cohort', { days: onboarding.days, count: onboarding.cohort })}
        {waiting ? ` ${t('waiting', { name })}` : ''}
      </span>
    </div>
  )
}

function Nps({ name }: { name: string }) {
  const t = useTranslations('platformPlus.success.nps')
  return (
    <div className={`${p.cardPad} gap-[10px]`}>
      <b className={p.title}>{t('title')}</b>
      <div className="flex items-baseline gap-[10px]">
        {/* no score exists: the dash is muted, never the design's «good result» green */}
        <span className="font-serif text-40 font-semibold text-muted">—</span>
        <span className="text-12.5 text-muted">{t('noSource', { name })}</span>
      </div>
    </div>
  )
}

function Requests({ product, name, requests, accounts, canAdd, nf }: {
  product: string
  name: string
  requests: { money: boolean; rows: FeatureRequest[] }
  accounts: AccountOption[]
  canAdd: boolean
  nf: NumberFormat
}) {
  const t = useTranslations('platformPlus.success.requests')
  const { run, pending, flash } = usePlusAct()
  const [voting, setVoting] = useState<FeatureRequest | null>(null)
  const [adding, setAdding] = useState(false)
  const line = (r: FeatureRequest) => {
    const parts = [t('tickets', { count: r.ticket_count }), r.deal_count ? t('deals', { count: r.deal_count }) : '—']
    if (requests.money) parts.push(t('mrr', { amount: r.asking?.mrr == null ? '—' : money(r.asking.mrr, nf) }))
    return parts.join(' · ')
  }
  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('sub')} />
      {requests.rows.length === 0 ? <div className={p.empty}>{t('empty', { name })}</div> : null}
      {requests.rows.map((r) => (
        <div key={r.id} className={`${p.row} flex flex-wrap items-center gap-3 py-[11px]`}>
          <button
            type="button"
            disabled={!canAdd}
            title={canAdd ? t('voteOf', { title: r.title }) : t('readOnly')}
            aria-label={t('voteOf', { title: r.title })}
            onClick={() => setVoting(r)}
            className="flex h-[46px] w-[52px] flex-none cursor-pointer flex-col items-center justify-center rounded-11 border border-ink bg-surface disabled:cursor-default"
          >
            <span className="text-11">▲</span>
            <b className="text-13">{formatNumber(r.votes, nf)}</b>
          </button>
          <span className="flex min-w-0 flex-[1_1_260px] flex-col gap-[2px]">
            <b className="text-13">{r.title}</b>
            <span className="text-11.5 text-muted">{line(r)}</span>
          </span>
          <select
            value={r.status}
            disabled={!canAdd || pending}
            aria-label={t('statusOf', { title: r.title })}
            onChange={(e) => {
              const status = e.target.value as FeatureRequest['status']
              run(() => setRequestStatus({ id: r.id, status }), () => flash(t('statusSet', { title: r.title, status: t(`status.${status}`) })))
            }}
            className={`h-[30px] rounded-8 border border-line text-12 font-bold text-ink ${STATUS_BG[r.status] ?? 'bg-tile'}`}
          >
            {REQUEST_STATUSES.map((s) => <option key={s} value={s}>{t(`status.${s}`)}</option>)}
          </select>
        </div>
      ))}
      <div className={`${p.foot} flex flex-wrap items-center justify-between gap-2`}>
        <span>{t('footer')}</span>
        {canAdd ? <button type="button" onClick={() => setAdding(true)} className={`${p.btnRow} bg-surface px-[10px]`}>{t('add')}</button> : null}
      </div>
      {voting ? (
        <VoteDialog request={voting} accounts={accounts} onClose={() => setVoting(null)} onVote={(org, orgName) => run(
          () => voteRequest({ id: voting.id, organization: org, on: true }),
          () => { setVoting(null); flash(t('voted', { name: orgName })) },
        )} pending={pending} />
      ) : null}
      {adding ? (
        <AddDialog accounts={accounts} pending={pending} onClose={() => setAdding(false)} onAdd={(title, org) => run(
          () => addRequest({ product, title, organization: org }),
          () => { setAdding(false); flash(t('added')) },
        )} />
      ) : null}
    </div>
  )
}

function VoteDialog({ request, accounts, onClose, onVote, pending }: {
  request: FeatureRequest
  accounts: AccountOption[]
  onClose: () => void
  onVote: (org: string, name: string) => void
  pending: boolean
}) {
  const t = useTranslations('platformPlus.success.requests')
  const voted = new Set(request.organizations.map((o) => o.id))
  const [org, setOrg] = useState('')
  const choice = accounts.find((a) => a.id === org)
  return (
    <Dialog title={t('voteTitle')} onClose={onClose}>
      <b className="text-13">{request.title}</b>
      <span className="text-12.5 text-muted">
        {request.organizations.length ? t('voteBody', { names: request.organizations.map((o) => o.name).join(', ') }) : t('voteNone')}
      </span>
      <label className={p.label}>
        {t('orgLabel')}
        <select value={org} onChange={(e) => setOrg(e.target.value)} className={p.input}>
          <option value="">{t('choose')}</option>
          {accounts.filter((a) => !voted.has(a.id)).map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
      </label>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
        <button type="button" disabled={!choice || pending} onClick={() => choice && onVote(choice.id, choice.name)}
          className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">
          {t('vote')}
        </button>
      </div>
    </Dialog>
  )
}

function AddDialog({ accounts, onClose, onAdd, pending }: {
  accounts: AccountOption[]
  onClose: () => void
  onAdd: (title: string, org: string | null) => void
  pending: boolean
}) {
  const t = useTranslations('platformPlus.success.requests')
  const [title, setTitle] = useState('')
  const [org, setOrg] = useState('')
  return (
    <Dialog title={t('addTitle')} onClose={onClose}>
      <label className={p.label}>
        {t('titleLabel')}
        <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} className={p.input} />
      </label>
      <label className={p.label}>
        {t('askedBy')}
        <select value={org} onChange={(e) => setOrg(e.target.value)} className={p.input}>
          <option value="">{t('none')}</option>
          {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
      </label>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
        <button type="button" disabled={title.trim().length < 3 || pending} onClick={() => onAdd(title.trim(), org || null)}
          className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">
          {t('save')}
        </button>
      </div>
    </Dialog>
  )
}

function Renewals({ product, name, signals, canDeal, nf }: { product: string; name: string; signals: Signal[]; canDeal: boolean; nf: NumberFormat }) {
  const t = useTranslations('platformPlus.success.renewal')
  const { run, pending, flash } = usePlusAct()
  const signal = (s: Signal) => {
    if (s.kind === 'expansion') {
      const n = formatNumber(s.employees, nf)
      return s.next ? t('next', { employees: n, max: formatNumber(s.max, nf), next: s.next }) : t('employees', { employees: n, max: formatNumber(s.max, nf) })
    }
    return [
      s.health_from !== null && s.health_to !== null ? t('health', { from: s.health_from, to: s.health_to }) : null,
      s.days_since_sign_in !== null ? t('signIn', { days: s.days_since_sign_in }) : null,
    ].filter(Boolean).join(' · ')
  }
  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('sub')} />
      {signals.length === 0 ? <div className={p.empty}>{t('empty', { name })}</div> : null}
      {signals.map((s) => {
        const created = !!s.open
        const risk = s.kind === 'at_risk'
        return (
          <div key={`${s.kind}:${s.organization.id}`} className={`${p.row} ${p.stackRow} md:[grid-template-columns:minmax(0,1.2fr)_minmax(0,1.6fr)_90px_110px]`}>
            <b className="min-w-0 [overflow-wrap:anywhere]">{s.organization.name}</b>
            <span className="order-2 min-w-0 text-muted md:order-none">{signal(s)}</span>
            <b className={`order-1 text-right md:order-none md:text-left ${risk ? 'text-danger' : 'text-link'}`}>{t(`kind.${s.kind}`)}</b>
            <button
              type="button"
              disabled={created || !canDeal || pending}
              title={created ? t('exists') : canDeal ? undefined : t('noRight')}
              onClick={() => run(
                () => (risk ? createSuccessTask : createSuccessDeal)({ org: s.organization.id, product, name: s.organization.name }),
                (r) => flash(r.existing ? t('exists') : risk ? t('taskDone') : t('dealDone')),
              )}
              className={`${p.btnRow} order-3 md:order-none ${created ? 'bg-ok-bg' : 'bg-primary'}`}
            >
              {created ? t('created') : risk ? t('task') : t('deal')}
            </button>
          </div>
        )
      })}
    </div>
  )
}
