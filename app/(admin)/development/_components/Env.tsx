import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { eventsUrl, loadDeploys, type Deployment } from '@/lib/data/dev-delivery'
import { deployedAt, shortSha } from './delivery/logic'
import { Connections } from './delivery/Connections'
import { d } from './delivery/styles'

/** the steps a change takes today (Orgpuls' and Sentral's CLAUDE.md playbooks), not the design's PR flow (V-V3E-25) */
const FLOW = ['push', 'preview', 'ci', 'merge', 'production', 'record'] as const
const STATE_TONE: Record<string, string> = { ready: 'text-link', building: 'text-warn-ink', error: 'text-danger', canceled: 'text-muted', rolled_back: 'text-danger' }

/**
 * Development › Vercel and Supabase (DevClaude.dc.html, view «env») on dev_deploys (0080). The flow strip says how a change
 * really reaches production. The Vercel card lists what Vercel's deployment webhooks reported; «Roll back» stays in Vercel,
 * so a production row links there (X-V3-1). The Supabase card holds only what the products' CI posts: migrations not yet in
 * production and the RLS and anonymity suites — Sentral holds no Supabase token for a product. Below, the two connections
 * (owner, fresh second factor) with the address to paste into Vercel and the CI's exact request.
 */
export async function EnvView(props: DevTabProps) {
  void props
  const [data, t, format, now] = await Promise.all([loadDeploys(), getTranslations('devDelivery'), getFormatter(), getNow()])
  const ago = (v: string) => format.relativeTime(new Date(v), now)
  const pname = (key: string | null) => (key === 'sentral' ? t('sentral') : data.products.find((p) => p.key === key)?.name ?? key ?? '')
  const project = (id: string) => data.projects.find((p) => p.id === id)

  // per project: its production and custom environments' newest, then its newest previews
  const vercel: Deployment[] = []
  for (const p of data.projects) {
    vercel.push(...data.latest.filter((x) => x.project_id === p.id && x.environment !== 'preview')
      .sort((a, b) => (a.environment === 'production' ? 1 : 0) - (b.environment === 'production' ? 1 : 0)))
    vercel.push(...data.previews.filter((x) => x.project_id === p.id).slice(0, 3))
  }
  const pending = data.ci_runs.filter((r) => r.migrations_pending.length > 0)

  return (
    <div className="flex flex-col gap-[14px]">
      <div className={`${d.card} flex flex-wrap items-center gap-[6px] px-[18px] py-[14px]`}>
        <b className="mr-[6px] text-13">{t('env.flow')}</b>
        {FLOW.map((k, i) => (
          <span key={k} className="flex items-center gap-[6px]">
            <span className={`whitespace-nowrap rounded-11 border px-[11px] py-[6px] text-12 font-semibold ${i === FLOW.length - 1 ? 'border-ink bg-primary' : 'border-line bg-canvas'}`}>
              {t(`env.steps.${k}`)}
            </span>
            {i < FLOW.length - 1 ? <span className="text-faint" aria-hidden>→</span> : null}
          </span>
        ))}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={`${d.card} min-w-0 overflow-hidden`}>
          <div className={d.head}>
            <b className={d.headTitle}>{t('env.vercel')}</b>
            <span className={d.headNote}>{data.projects.length ? t('env.projects', { n: data.projects.length }) : t('env.notConnected')}</span>
          </div>
          {vercel.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('code.noDeploys')}</div> : null}
          {vercel.map((x) => {
            const p = project(x.project_id)
            const prod = x.environment === 'production'
            const name = prod ? p?.name ?? '' : x.pr ? t('env.pr', { name: p?.name ?? '', n: x.pr }) : `${p?.name ?? ''} · ${x.ref ?? shortSha(x.sha) ?? ''}`
            const state = x.rolled_back_at ? 'rolled_back' : x.state
            return (
              <div key={x.id} className="grid items-center gap-x-[10px] gap-y-1 border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:auto_auto_minmax(0,1fr)] sm:[grid-template-columns:minmax(0,1.3fr)_90px_80px_90px]">
                <span className="col-span-3 flex min-w-0 flex-col sm:col-span-1">
                  <b className="[overflow-wrap:anywhere]">{name}</b>
                  <span className={`${d.mono} text-11 text-muted [overflow-wrap:anywhere]`}>{x.host ?? '—'}</span>
                </span>
                <span className="text-muted">{x.environment === 'preview' || x.environment === 'production' || x.environment === 'staging' ? t(`env.${x.environment}`) : x.environment}</span>
                <b className={STATE_TONE[state]} title={ago(deployedAt(x))}>{t(`state.${state}`)}</b>
                <span className="flex justify-end">
                  {prod && x.inspector_url ? (
                    <a href={x.inspector_url} target="_blank" rel="noreferrer" title={t('env.openInVercelTitle')}
                      className="flex h-[26px] items-center whitespace-nowrap rounded-8 border border-coral bg-transparent px-[9px] text-11.5 font-semibold text-rust hover:text-rust hover:no-underline">
                      {t('env.openInVercel')}
                    </a>
                  ) : null}
                </span>
              </div>
            )
          })}
        </div>

        <div className={`${d.card} min-w-0 overflow-hidden`}>
          <div className={d.head}>
            <b className={d.headTitle}>{t('env.supabase')}</b>
            <span className={d.headNote}>{data.ci_runs.length ? t('env.fromCi') : t('env.noCi')}</span>
          </div>
          {data.ci_runs.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('code.noCi')}</div> : null}
          {data.ci_runs.flatMap((r) => r.migrations_pending.map((f) => (
            <div key={`${r.product}-${f}`} className="grid items-center gap-x-[10px] gap-y-1 border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:auto_minmax(0,1fr)] sm:[grid-template-columns:minmax(0,1.4fr)_90px_120px]">
              <span className="col-span-2 flex min-w-0 flex-col sm:col-span-1">
                <b className={`${d.mono} text-12 [overflow-wrap:anywhere]`}>{f}</b>
                <span className="text-11 text-muted">{t('env.waiting', { app: pname(r.product) })}</span>
              </span>
              <b className="text-warn-ink">{t('env.pendingProd')}</b>
              <span className="flex justify-end">
                <button type="button" disabled title={t('env.approveReason')} className={`${d.rowBtnPrimary} h-7 px-[10px]`}>{t('env.approve')}</button>
              </span>
            </div>
          )))}
          {data.ci_runs.filter((r) => r.migrations_pending.length === 0).map((r) => (
            <div key={`${r.product}-none`} className="grid items-center gap-x-[10px] gap-y-1 border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:auto_minmax(0,1fr)] sm:[grid-template-columns:minmax(0,1.4fr)_90px_120px]">
              <span className="col-span-2 flex min-w-0 flex-col sm:col-span-1">
                <b>{t('env.noneWaiting')}</b>
                <span className="text-11 text-muted">{t('env.ciAt', { app: pname(r.product), ago: ago(r.finished_at) })}</span>
              </span>
              <b className="text-link">{t('env.upToDate')}</b>
              <span />
            </div>
          ))}
          {data.ci_runs.map((r) => {
            const rls = r.suites.filter((s) => s.kind === 'security' || s.kind === 'anonymity')
            const failed = rls.reduce((a, s) => a + s.failed, 0)
            const passed = rls.reduce((a, s) => a + s.passed, 0)
            return (
              <div key={`${r.product}-rls`} className="flex justify-between gap-[10px] border-b border-line px-[18px] py-2 text-12.5">
                <span className="text-muted">{data.ci_runs.length > 1 ? t('env.rlsFor', { app: pname(r.product) }) : t('env.rls')}</span>
                <b className={`text-right ${!rls.length ? 'text-ink' : failed ? 'text-danger' : 'text-link'}`}>
                  {!rls.length ? '—' : failed ? t('env.failing', { n: failed }) : t('env.passing', { n: passed })}
                </b>
              </div>
            )
          })}
          {pending.length ? <div className="px-[18px] py-[9px] text-11.5 text-faint">{t('env.approveReason')}</div> : null}
        </div>
      </div>

      <Connections
        url={eventsUrl()}
        now={now.getTime()}
        vercel={data.vercel}
        ci={data.ci}
        canManage={data.can_manage}
        canConfigure={data.can_configure}
        projects={data.projects.map((p) => ({ id: p.id, name: p.name, product: p.product }))}
        products={data.products.map((p) => ({ key: p.key, name: pname(p.key) }))}
      />
    </div>
  )
}
