import Link from 'next/link'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import type { PrivacyRequest } from '@/lib/data/customers'
import { daysSince, daysUntil, label, when } from './fmt'

const tableCard = 'overflow-hidden rounded-20 border border-line bg-surface'
const empty = 'px-[18px] py-[26px] text-center text-13 text-muted'

/**
 * Customers › Personvern requests (privacy_get, the 30-day clock). Only staff who work the personvern queue
 * read them; anyone else sees the panel with the reason instead of rows.
 */
export async function PrivacyView({ rows }: { rows: PrivacyRequest[] | null }) {
  const t = await getTranslations('customers')
  const fmt = await getFormatter()
  const now = await getNow()
  return (
    <div className="flex flex-col gap-4">
      <div className={tableCard}>
        <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 border-b border-line px-[18px] py-[14px]">
          <span className="text-15 font-bold">{t('privacy.title')}</span>
          <span className="text-12 text-muted">{t('privacy.sub')}</span>
        </div>
        {rows ? (
          <div className="overflow-x-auto">
            <div className="min-w-[860px]">
              {rows.map((p) => {
                const days = daysSince(p.received_at, now)
                const left = daysUntil(p.due_at, now)
                const tone = days > 22 ? '#D4633A' : days > 14 ? '#E0A21F' : '#5C9A55'
                return (
                  <div key={p.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 [grid-template-columns:90px_110px_minmax(0,1.4fr)_120px_150px_110px_120px]">
                    <b>{p.ticket_ref ?? '—'}</b>
                    <span>{label(t, 'privacy.kind', p.kind)}</span>
                    <span className="flex flex-col">
                      <span className="font-semibold">{p.requester_category ?? t('privacy.unknownRequester')}</span>
                      <span className="text-11.5 text-muted">
                        {p.organization_id && p.organization ? <Link href={`/customers?org=${p.organization_id}` as never} className="text-muted hover:text-muted">{p.organization}</Link> : (p.organization ?? '—')}
                      </span>
                    </span>
                    <span className="text-muted">{t('privacy.received', { when: when(p.received_at, now, fmt, t, 'plain') })}</span>
                    <span className="flex items-center gap-2">
                      <span className="h-[6px] flex-1 overflow-hidden rounded-999 bg-tile">
                        <span className="block h-full" style={{ width: `${Math.min(100, (days / 30) * 100)}%`, background: tone }} />
                      </span>
                      <b className={`text-12 ${days > 22 ? 'text-danger' : 'text-ink'}`}>{left >= 0 ? t('privacy.left', { n: left }) : t('privacy.overdue', { n: -left })}</b>
                    </span>
                    <span>{label(t, 'privacy.status', p.status)}</span>
                    <span className="text-muted">{p.owner ?? t('privacy.unassigned')}</span>
                  </div>
                )
              })}
              {rows.length === 0 ? <div className={empty}>{t('privacy.empty')}</div> : null}
            </div>
          </div>
        ) : (
          <div className={empty}>{t('privacy.forbidden')}</div>
        )}
      </div>
      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={tableCard}>
          <div className="border-b border-line px-[18px] py-[14px] text-15 font-bold">{t('privacy.deletions')}</div>
          <div className={empty}>{t('privacy.noDeletions')}</div>
        </div>
        <div className={tableCard}>
          <div className="flex justify-between border-b border-line px-[18px] py-[14px]"><span className="text-15 font-bold">{t('privacy.dpas')}</span></div>
          <div className={empty}>{t('privacy.noDpas')}</div>
        </div>
      </div>
    </div>
  )
}
