'use client'

import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { Portal } from '@/lib/data/support-hub'
import { card, cardInk } from './bits'

const label = 'px-[18px] py-3 text-11 font-bold uppercase tracking-[.1em] text-muted'
const tone = { us: 'text-warn-ink', you: 'text-warn-ink', done: 'text-link' } as const

/**
 * Customer portal (SupportHub.dc.html, v.portal): a read-only admin preview of one organisation's real tickets in the words
 * its users would see. «Venter på deg» lists only what really waits: today the organisation's open privacy requests (the
 * organisation decides on its employees' data), counted for those who see the personvern queue. The approvals the design
 * draws (support access, deletion, band) are named in Portal access as what the portal will carry once Orgpuls has the
 * commands (V-V3S-24).
 */
export function PortalView({ data, productName }: { data: Portal; productName: string }) {
  const t = useTranslations('supportHub.portal')
  const router = useRouter()
  const org = data.organization
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
          {data.privacy_open ? (
            <div className="flex flex-col border-t border-tile px-[18px] py-[10px]">
              <b className="text-12.5">{t('privacyOpen')}</b>
              <span className="text-11.5 text-muted">{t('privacyOpenSub', { n: data.privacy_open })}</span>
            </div>
          ) : (
            <div className="border-t border-tile px-[18px] py-[9px] text-12.5 text-muted">{t('waitingNone')}</div>
          )}
        </div>
      </div>
      <div className={`${card} flex flex-col gap-2 px-[18px] py-4`}>
        <b className="text-15">{t('rules.title')}</b>
        {(['preview', 'roles', 'signin', 'approvals'] as const).map((k) => <span key={k} className="text-12.5 leading-[1.5]">· {t(`rules.${k}`, { product: productName })}</span>)}
      </div>
    </div>
  )
}
