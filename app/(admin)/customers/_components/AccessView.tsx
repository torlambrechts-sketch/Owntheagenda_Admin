import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { can, type Shell } from '@/lib/shell'
import type { CustomerRow, Grant } from '@/lib/data/customers'
import { AccessForm } from './AccessForm'
import { grantTone } from './tones'
import { when } from './fmt'

/** Customers › Support access (instead of impersonation): the grants and the request form. */
export async function AccessView({ grants, orgs, shell, product }: { grants: Grant[] | null; orgs: CustomerRow[]; shell: Shell; product: string }) {
  const t = await getTranslations('customers')
  const fmt = await getFormatter()
  const now = await getNow()
  const hoursLeft = (iso: string) => Math.max(0, Math.ceil((new Date(iso).getTime() - now.getTime()) / 3_600_000))
  const prodName = (k: string) => shell.products.find((p) => p.key === k)?.name ?? k

  return (
    <div className="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface [grid-column:1/-1]">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 border-b border-line px-[18px] py-[14px]">
          <span className="text-15 font-bold">{t('access.title')}</span>
          <span className="text-12 text-muted">{t('access.sub')}</span>
        </div>
        <div className="overflow-x-auto">
          <div className="min-w-[760px]">
            {(grants ?? []).map((g) => {
              const by = g.state === 'active' || g.state === 'expired'
                ? g.approved_by ? t('access.approvedBy', { name: g.approved_by }) : t('access.granted')
                : t('access.requested', { when: when(g.requested_at, now, fmt, t) })
              const exp = g.state === 'active' && g.expires_at ? t('access.left', { n: hoursLeft(g.expires_at) })
                : g.state === 'pending' ? t('access.whenApproved', { n: g.hours })
                : g.expires_at ? t('access.ended', { when: when(g.expires_at, now, fmt, t, 'plain') }) : '—'
              return (
                <div key={g.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 [grid-template-columns:minmax(0,1.3fr)_120px_150px_120px_110px_120px]">
                  <span className="flex flex-col"><b>{g.organization ?? '—'}</b><span className="text-11.5 text-muted">{prodName(g.product)} · {g.reason}</span></span>
                  <span>{g.staff ?? '—'}</span>
                  <span className="text-muted">{by}</span>
                  <span><span className={`rounded-999 px-[10px] py-[3px] text-11.5 font-bold ${grantTone(g.state)}`}>{t(`access.state.${g.state}`)}</span></span>
                  <span className="text-muted">{exp}</span>
                  <span className="text-muted">{g.state === 'pending' ? '—' : t('access.views', { n: g.page_views })}</span>
                </div>
              )
            })}
            {grants && grants.length === 0 ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('access.empty')}</div> : null}
            {!grants ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('detail.tabForbidden')}</div> : null}
          </div>
        </div>
      </div>
      <AccessForm
        orgs={orgs.map((o) => ({ id: o.id, name: o.name, products: o.products.map((p) => ({ key: p.key, name: prodName(p.key) })) }))}
        product={product}
        allowed={can(shell, 'global', 'add')}
      />
    </div>
  )
}
