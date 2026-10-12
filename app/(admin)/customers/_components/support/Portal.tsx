'use client'

import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { Portal } from '@/lib/data/support-hub'
import { card, cardInk, Why } from './bits'

const label = 'px-[18px] py-3 text-11 font-bold uppercase tracking-[.1em] text-muted'
const tone = { us: 'text-warn-ink', you: 'text-danger', done: 'text-link' } as const

/**
 * Customer portal (SupportHub.dc.html, v.portal): a read-only admin preview of one organisation's real tickets in the words
 * its users would see. The portal itself, its sign-in, and the approvals in it wait for Orgpuls (V-V3S-12, V-V3S-13).
 */
export function PortalView({ data, productName }: { data: Portal; productName: string }) {
  const t = useTranslations('supportHub.portal')
  const router = useRouter()
  const org = data.organization
  const approvals = [
    { key: 'access', sub: t('approvals.accessSub') },
    { key: 'deletion', sub: data.privacy_open ? t('approvals.deletionOpen', { n: data.privacy_open }) : t('approvals.deletionSub') },
    { key: 'band', sub: t('approvals.bandSub') },
  ]
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="flex flex-col gap-[10px]">
        {data.organizations.length > 0 ? (
          <label className="flex items-center gap-[6px] self-start text-12 text-muted">
            {t('org')}
            <select
              value={org?.id ?? ''}
              onChange={(e) => router.push(`/customers?tab=support&sub=portal&org=${e.target.value}` as never)}
              className="h-[30px] max-w-[260px] rounded-8 border border-line bg-surface text-12 text-ink"
            >
              {data.organizations.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
          </label>
        ) : null}
        <div className={`${cardInk} overflow-hidden`}>
          <div className="flex items-center justify-between gap-[10px] border-b border-line bg-canvas px-[18px] py-[14px]">
            <span className="flex flex-col">
              <b className="text-15">{t('title', { org: org?.name ?? productName })}</b>
              <span className="text-12 text-muted">{t('sub')}</span>
            </span>
            <span className="whitespace-nowrap rounded-999 bg-highlight px-[10px] py-[3px] text-11 font-bold">{t('badge')}</span>
          </div>
          <div className={label}>{t('cases')}</div>
          {data.tickets.length === 0 ? <div className="border-t border-tile px-[18px] py-[9px] text-12.5 text-muted">{org ? t('noTickets') : t('empty', { product: productName })}</div> : null}
          {data.tickets.map((x) => (
            <div key={x.id} className="flex justify-between gap-[10px] border-t border-tile px-[18px] py-[9px] text-12.5">
              <span className="flex flex-col"><b>{x.subject}</b><span className="text-11.5 text-muted">{[x.ref, x.requester].filter(Boolean).join(' · ')}</span></span>
              <b className={`whitespace-nowrap ${tone[x.state]}`}>{t(`state.${x.state}`)}</b>
            </div>
          ))}
          <div className={`${label} border-t border-line`}>{t('waiting')}</div>
          {approvals.map((a) => (
            <div key={a.key} className="flex flex-wrap items-center gap-[10px] border-t border-tile px-[18px] py-[10px]">
              <span className="flex flex-[1_1_200px] flex-col"><b className="text-12.5">{t(`approvals.${a.key}`)}</b><span className="text-11.5 text-muted">{a.sub}</span></span>
              <span className="flex gap-[6px]">
                <button type="button" disabled title={t('approvals.why')} className="h-[30px] cursor-not-allowed rounded-9 border border-line bg-transparent px-[10px] text-12 text-ink opacity-60">{t('approvals.decline')}</button>
                <button type="button" disabled title={t('approvals.why')} className="h-[30px] cursor-not-allowed rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold text-ink opacity-60">{t('approvals.approve')}</button>
              </span>
            </div>
          ))}
          <div className="border-t border-tile px-[18px] py-[9px]"><Why>{t('approvals.why')}</Why></div>
        </div>
      </div>
      <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
        <b className="text-15">{t('rules.title')}</b>
        {(['preview', 'roles', 'signin', 'access'] as const).map((k) => <span key={k} className="text-12.5 leading-[1.5]">· {t(`rules.${k}`, { product: productName })}</span>)}
      </div>
    </div>
  )
}
