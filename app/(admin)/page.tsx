import Link from 'next/link'
import { cookies } from 'next/headers'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import { loadOverview } from '@/lib/data/overview'
import { formatNumber, money, percent, thousands } from '@/lib/format'
import { ui } from '@/components/ui/styles'
import { OpenSearchButton } from '@/components/shell/OpenSearchButton'

const TONE = { alert: 'bg-alert', warn: 'bg-warn', ok: 'bg-ok' } as const
// the design's chart and stage palette (Sentral Admin.dc.html: pc, viz)
const VIZ = ['#F6D9C6', '#DCEBD3', '#CFE0F5', '#F3E2C9', '#E7DAF2']

/** Overview (Sentral Admin.dc.html, r.home): only what the database holds; a block without a source is left out. */
export default async function OverviewPage() {
  const shell = await getShell()
  const product = (await cookies()).get('product')?.value ?? 'all'
  const o = await loadOverview(product)
  const t = await getTranslations('overview')
  const format = await getFormatter()
  const now = await getNow()
  const nf = shell.me.number_format
  const cur = product === 'all' ? null : shell.products.find((p) => p.key === product)
  const scopeName = cur?.name ?? t('allApplications')
  const signed = (n: number) => `${n >= 0 ? '+' : '−'}${formatNumber(Math.abs(n), nf)}`
  const daysLeft = (iso: string) => Math.max(0, Math.ceil((new Date(iso).getTime() - now.getTime()) / 86_400_000))
  const conv = o.trials.ended_month > 0 ? (o.trials.converted_month / o.trials.ended_month) * 100 : null

  // the headline is a sentence of facts that exist
  const headline = [
    conv !== null ? t('headline.conversion', { pct: percent(conv, nf) }) : t('headline.trials', { count: o.trials.now, ending: o.trials.ending7 }),
    o.at_risk ? t('headline.atRisk', { count: o.at_risk.length }) : null,
    o.tickets && o.tickets.at_risk ? t('headline.sla', { count: o.tickets.at_risk }) : null,
  ].filter(Boolean).join(' ')

  const kpis: { label: string; value: string; delta?: string; dc?: string; sub: string; href: string }[] = [
    o.mrr.priced > 0
      ? {
          label: t('kpi.mrr'), value: money(o.mrr.now, nf),
          ...(o.mrr.prev !== null ? { delta: signed(o.mrr.now - o.mrr.prev), dc: o.mrr.now - o.mrr.prev >= 0 ? 'text-link' : 'text-danger' } : {}),
          sub: t('kpi.arr', { value: money(o.mrr.now * 12, nf) }), href: '/analytics',
        }
      : { label: t('kpi.mrr'), value: '—', sub: t('kpi.mrrUnpriced'), href: '/analytics' },
    {
      label: t('kpi.paying'), value: String(o.paying.now),
      // the snapshot counts paid subscriptions per product, so the change is measured the same way
      ...(o.paying.prev !== null ? { delta: signed(o.paying.subs_now - o.paying.prev), dc: o.paying.subs_now - o.paying.prev >= 0 ? 'text-link' : 'text-danger' } : {}),
      sub: t('kpi.payingSub'), href: '/customers',
    },
    {
      label: t('kpi.trials'), value: String(o.trials.now), delta: t('kpi.trialsEnding', { count: o.trials.ending7 }), dc: 'text-warn-ink',
      sub: conv !== null ? t('kpi.trialsConversion', { pct: percent(conv, nf) }) : t('kpi.trialsNoneEnded'), href: '/customers',
    },
    ...(o.tickets
      ? [{
          label: t('kpi.tickets'), value: String(o.tickets.open), delta: t('kpi.ticketsRisk', { count: o.tickets.at_risk }),
          dc: o.tickets.at_risk ? 'text-danger' : 'text-link',
          sub: o.tickets.median_first_response_min !== null ? t('kpi.ticketsMedian', { minutes: o.tickets.median_first_response_min }) : t('kpi.ticketsNoMedian'),
          href: '/tickets',
        }]
      : []),
    ...(o.pipeline
      ? [{
          label: t('kpi.pipeline'), value: money(o.pipeline.weighted, nf), delta: t('kpi.rotting', { count: o.pipeline.rotting }), dc: 'text-danger',
          sub: t('kpi.openDeals', { count: o.pipeline.open }), href: '/deals',
        }]
      : []),
  ]

  const series = o.mrr_series
  const prods = shell.products.filter((p) => product === 'all' || p.key === product)
  const total = (m: (typeof series)[number]) => prods.reduce((a, p) => a + (m.by_product[p.key] ?? 0), 0)
  const max = Math.max(1, ...series.map(total))
  const maxStage = o.pipeline ? Math.max(1, ...o.pipeline.stages.map((s) => s.value)) : 1

  return (
    <div className="flex max-w-[1480px] flex-col gap-[18px] px-4 pb-12 pt-[26px] md:px-7">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-[820px]">
          <div className={ui.eyebrow}>
            {format.dateTime(now, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })} · {scopeName}
          </div>
          <h1 className="m-0 mt-2 font-serif text-30 font-semibold leading-[1.12] [text-wrap:balance]">{headline}</h1>
        </div>
        <div className="flex gap-2">
          <Link href="/analytics" className={`${ui.btnGhost} inline-flex items-center ${ui.plainLink}`}>{t('openAnalytics')}</Link>
          <OpenSearchButton className={ui.btnPrimary}>{t('newRecord')}</OpenSearchButton>
        </div>
      </div>

      <div className="grid gap-[13px] [grid-template-columns:repeat(auto-fit,minmax(190px,1fr))]">
        {kpis.map((k) => (
          <Link key={k.label} href={k.href as never} className={`flex cursor-pointer flex-col gap-[6px] rounded-20 border border-line bg-surface px-5 py-[18px] text-left ${ui.plainLink}`}>
            <span className={ui.eyebrow}>{k.label}</span>
            <span className="flex items-baseline gap-[10px]">
              <span className="whitespace-nowrap font-serif text-26 font-semibold tabular-nums leading-none">{k.value}</span>
              {k.delta ? <span className={`text-12.5 font-bold ${k.dc}`}>{k.delta}</span> : null}
            </span>
            <span className="text-12 text-muted">{k.sub}</span>
          </Link>
        ))}
      </div>

      <div className="rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <div className="mb-3 flex items-baseline justify-between gap-3">
          <span className="text-15 font-bold">{t('apps.title')}</span>
          <Link href="/applications" className="text-12.5 font-semibold">{t('apps.manage')}</Link>
        </div>
        <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(230px,1fr))]">
          {o.apps.map((a) => {
            const status = !a.installed ? 'none' : a.enabled ? 'on' : 'off'
            return (
              <div key={a.key} className="flex flex-col gap-[10px] rounded-15 border border-line bg-canvas px-4 py-[14px]">
                <div className="flex items-center gap-[10px]">
                  <span className="flex h-8 w-8 items-center justify-center rounded-10 border border-[rgba(25,21,16,.1)] font-serif text-15 font-bold" style={{ background: a.color, color: a.ink }}>
                    {a.name[0]}
                  </span>
                  <span className="flex flex-1 flex-col">
                    <span className="text-13.5 font-bold">{a.name}</span>
                    <span className="text-11.5 text-muted">{a.host ?? t('apps.noHost')}</span>
                  </span>
                  <span className={`rounded-999 px-[9px] py-[3px] text-11 font-bold ${status === 'on' ? 'bg-ok-bg text-ok-ink' : 'bg-beige text-muted'}`}>{t(`apps.status.${status}`)}</span>
                </div>
                <div className="grid grid-cols-4 gap-[6px] text-11 text-muted">
                  <span className="flex flex-col"><b className="text-13 tabular-nums text-ink">{a.orgs}</b>{t('apps.orgs')}</span>
                  <span className="flex flex-col"><b className="text-13 tabular-nums text-ink">{a.mrr !== null ? thousands(a.mrr, nf) : '—'}</b>{t('apps.mrr')}</span>
                  <span className="flex flex-col"><b className="text-13 tabular-nums text-ink">—</b>{t('apps.p95')}</span>
                  <span className="flex flex-col"><b className="text-13 tabular-nums text-ink">—</b>{t('apps.errors')}</span>
                </div>
                <div className="text-11 text-faint">
                  {a.last_event_at ? t('apps.lastSync', { when: format.relativeTime(new Date(a.last_event_at), now) }) : t('apps.noEvents')}
                </div>
              </div>
            )
          })}
        </div>
      </div>

      <div className="grid gap-[18px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-5">
          <div className="mb-3 flex items-baseline justify-between">
            <span className="text-15 font-bold">{t('todo.title')}</span>
            <span className="text-12 text-muted">{t('todo.count', { count: o.todo.length })}</span>
          </div>
          <div className="flex flex-col gap-2">
            {o.todo.map((x, i) => (
              <div key={i} className="flex items-center gap-[14px] rounded-15 border border-line bg-surface py-3 pl-3 pr-[14px]">
                <span className={`w-[7px] self-stretch rounded-999 ${TONE[x.tone]}`} />
                <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
                  <span className="text-13.5 font-semibold">{t(`todo.items.${x.key}.title`, x.params)}</span>
                  <span className="text-12 text-muted">{t(`todo.items.${x.key}.sub`, x.params)}</span>
                </span>
                <Link href={x.href as never} className={`${ui.btnSmall} inline-flex items-center ${ui.plainLink}`}>{t(`todo.items.${x.key}.cta`)}</Link>
              </div>
            ))}
            {o.todo.length === 0 ? <div className="rounded-15 border border-dashed border-line-strong px-4 py-6 text-center text-13 text-muted">{t('todo.empty')}</div> : null}
          </div>
        </div>

        <div className="flex flex-col rounded-20 border border-line bg-surface px-[22px] py-5">
          <div className="mb-1 flex items-baseline justify-between">
            <span className="text-15 font-bold">{t('mrrChart.title')}</span>
            <span className="text-12 text-muted">{t('mrrChart.sub')}</span>
          </div>
          <div className="mb-[14px] flex flex-wrap gap-3">
            {prods.map((p) => (
              <span key={p.key} className="flex items-center gap-[6px] text-11.5 text-muted">
                <span className="h-[10px] w-[10px] rounded-3 border border-[rgba(25,21,16,.15)]" style={{ background: p.color }} />
                {p.name}
              </span>
            ))}
          </div>
          {series.length ? (
            <>
              <div className="flex min-h-[170px] flex-1 items-end gap-2 border-b border-line-strong pb-0">
                {series.map((m) => {
                  const tot = total(m)
                  return (
                    <div
                      key={m.month}
                      title={`${format.dateTime(new Date(`${m.month}-15`), { month: 'short' })}: ${money(tot, nf)}`}
                      className="flex flex-1 flex-col-reverse overflow-hidden rounded-t-6"
                      style={{ height: Math.round((tot / max) * 160) }}
                    >
                      {prods.filter((p) => (m.by_product[p.key] ?? 0) > 0).map((p) => (
                        <div key={p.key} className="border-t border-[rgba(25,21,16,.08)]" style={{ height: `${((m.by_product[p.key] ?? 0) / tot) * 100}%`, background: p.color }} />
                      ))}
                    </div>
                  )
                })}
              </div>
              <div className="mt-[6px] flex gap-2">
                {series.map((m) => (
                  <span key={m.month} className="flex-1 text-center text-10.5 text-faint">{format.dateTime(new Date(`${m.month}-15`), { month: 'short' })}</span>
                ))}
              </div>
            </>
          ) : (
            <div className="flex min-h-[170px] flex-1 items-center justify-center border-b border-line-strong text-center text-12.5 text-muted">{t('mrrChart.empty')}</div>
          )}
        </div>
      </div>

      <div className="grid gap-[18px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-5">
          <div className="mb-[10px] flex items-baseline justify-between">
            <span className="text-15 font-bold">{t('trials.title')}</span>
            <Link href="/customers" className="text-12.5 font-semibold">{t('trials.all')}</Link>
          </div>
          <div className={`grid gap-[10px] border-b border-line px-1 py-2 [grid-template-columns:minmax(0,2fr)_70px_minmax(0,1fr)_minmax(0,1fr)_90px] ${ui.colHead}`}>
            <span>{t('trials.cols.org')}</span><span>{t('trials.cols.days')}</span><span>{t('trials.cols.survey')}</span><span>{t('trials.cols.source')}</span><span>{t('trials.cols.owner')}</span>
          </div>
          {o.trials_list.map((r) => {
            const left = daysLeft(r.ends)
            return (
              <Link
                key={r.account_id}
                href={(r.organization_id ? `/customers?org=${r.organization_id}` : '/customers') as never}
                className={`grid w-full cursor-pointer items-center gap-[10px] border-b border-line bg-transparent px-1 py-[10px] text-left text-13 [grid-template-columns:minmax(0,2fr)_70px_minmax(0,1fr)_minmax(0,1fr)_90px] ${ui.plainLink}`}
              >
                <span className="flex flex-col">
                  <span className="font-semibold">{r.name}</span>
                  <span className="text-11.5 text-muted">
                    {[r.org_number ? r.org_number.replace(/(\d{3})(\d{3})(\d{3})/, '$1 $2 $3') : null, r.employees !== null ? t('trials.employees', { count: r.employees }) : null].filter(Boolean).join(' · ')}
                  </span>
                </span>
                <span className={`font-bold tabular-nums ${left <= 7 ? 'text-danger' : 'text-ink'}`}>{t('trials.days', { count: left })}</span>
                <span className="text-muted">—</span>
                <span className="text-muted">{r.source ?? '—'}</span>
                <span className="text-muted">{r.owner?.split(' ')[0] ?? '—'}</span>
              </Link>
            )
          })}
          {o.trials_list.length === 0 ? <div className="px-1 py-6 text-center text-13 text-muted">{t('trials.empty')}</div> : null}
        </div>

        {o.pipeline ? (
          <div className="rounded-20 border border-line bg-surface px-[22px] py-5">
            <div className="mb-3 flex items-baseline justify-between">
              <span className="text-15 font-bold">{t('pipeline.title')}</span>
              <Link href="/deals" className="text-12.5 font-semibold">{t('pipeline.open')}</Link>
            </div>
            <div className="flex flex-col gap-[10px]">
              {o.pipeline.stages.map((s, i) => (
                <div key={s.name} className="grid items-center gap-[10px] text-12.5 [grid-template-columns:120px_minmax(0,1fr)_92px]">
                  <span className="font-semibold">{s.name}</span>
                  <span className="h-[22px] overflow-hidden rounded-7 bg-tile">
                    <span className="block h-full border-r border-[rgba(25,21,16,.15)]" style={{ width: `${Math.round((s.value / maxStage) * 100)}%`, background: VIZ[i % VIZ.length] }} />
                  </span>
                  <span className="text-right tabular-nums"><b>{thousands(s.value, nf)}</b> <span className="text-faint">· {s.n}</span></span>
                </div>
              ))}
            </div>
            <div className="mt-4 flex justify-between border-t border-line pt-3 text-12.5 text-muted">
              <span>{t('pipeline.weighted')}</span>
              <b className="tabular-nums text-ink">{money(o.pipeline.weighted, nf)}</b>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  )
}
