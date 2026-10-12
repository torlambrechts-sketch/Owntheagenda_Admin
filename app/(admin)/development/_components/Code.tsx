import Link from 'next/link'
import type { Route } from 'next'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { loadDeploys, type CiRun } from '@/lib/data/dev-delivery'
import { deployTone, deployedAt, environments, envRows, shortSha } from './delivery/logic'
import { d } from './delivery/styles'

type Row = { tone: 'ok' | 'warn' | 'alert'; title: string; sub: string }

/**
 * Development › Code and environments (DevHub.dc.html, tab «code») on dev_deploys (0080): the newest deployment per Vercel
 * project and environment (Preview and Production; another column only when Vercel reports a custom environment such as
 * Staging), the previews per branch from Vercel's Git metadata, and the security, dependency and migration rows from each
 * product's newest CI run on its main line. Without GitHub there are no pull requests, reviews or secret scans (V-V3E-20, V-V3E-21).
 */
export async function CodeView(props: DevTabProps) {
  void props
  const [data, t, format, now] = await Promise.all([loadDeploys(), getTranslations('devDelivery'), getFormatter(), getNow()])
  const ago = (v: string) => format.relativeTime(new Date(v), now)
  const pname = (key: string | null) => (key === 'sentral' ? t('sentral') : data.products.find((p) => p.key === key)?.name ?? key)
  const envs = environments(data.latest)
  const rows = envRows(data.projects, data.latest)
  const perProduct = new Map<string, number>()
  for (const p of data.projects) if (p.product) perProduct.set(p.product, (perProduct.get(p.product) ?? 0) + 1)
  const appName = (p: { name: string; product: string | null }) =>
    p.product ? ((perProduct.get(p.product) ?? 0) > 1 ? `${pname(p.product)} · ${p.name}` : pname(p.product) ?? p.name) : p.name
  const sources = [data.projects.length || data.vercel.key_stored ? t('code.sourceVercel') : null, data.ci_runs.length || data.ci.key_stored ? t('code.sourceCi') : null].filter(Boolean)
  const grid = { gridTemplateColumns: `minmax(0,1fr) repeat(${envs.length},minmax(130px,1fr))` }
  const security = securityRows(data.ci_runs, data.ci_runs.length > 1, pname, ago, t)

  return (
    <div className="flex flex-col gap-[14px]">
      <div className={`${d.card} overflow-hidden`}>
        <div className={d.head}><b className={d.headTitle}>{t('code.deploys')}</b><span className={d.headNote}>{sources.length ? sources.join(' · ') : t('code.noSource')}</span></div>
        <div className="overflow-x-auto">
          <div style={{ minWidth: 160 + envs.length * 140 }}>
            <div className={`grid gap-[10px] border-b border-line px-[18px] py-[9px] ${d.colHead}`} style={grid}>
              <span>{t('code.app')}</span>
              {envs.map((e) => <span key={e}>{e === 'preview' || e === 'production' || e === 'staging' ? t(`env.${e}`) : e}</span>)}
            </div>
            {rows.length === 0 ? (
              <div className="px-[18px] py-[14px] text-12.5 text-muted">
                {t('code.noDeploys')} <Link href={'/development?tab=env' as Route} className="font-semibold">{t('code.connect')}</Link>
              </div>
            ) : rows.map(({ project, cells }) => (
              <div key={project.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5" style={grid}>
                <b className="min-w-0 [overflow-wrap:anywhere]">{appName(project)}</b>
                {envs.map((e) => {
                  const c = cells[e]
                  if (!c) return <span key={e} className="text-muted">—</span>
                  return (
                    <span key={e} className="flex flex-col" title={t(`state.${c.rolled_back_at ? 'rolled_back' : c.state}`)}>
                      <span className={`${d.mono} text-11.5`}><span className={d.dot[deployTone(c)]}>●</span> {shortSha(c.sha) ?? '—'}</span>
                      <span className="text-11 text-muted">{ago(deployedAt(c))}</span>
                    </span>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className={`${d.card} min-w-0 overflow-hidden`}>
          <div className={d.head}><b className={d.headTitle}>{t('code.previews')}</b><span className={d.headNote}>{t('code.previewsNote')}</span></div>
          {data.previews.length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('code.noPreviews')}</div> : null}
          {data.previews.map((p) => {
            const project = data.projects.find((x) => x.id === p.project_id)
            const title = p.pr ? t('code.prTitle', { n: p.pr, title: p.commit_title ?? p.ref ?? '' }).trim() : p.commit_title ?? p.ref ?? shortSha(p.sha) ?? p.id
            const meta = [project ? appName(project) : null, p.ref, t(`state.${p.state}`), ago(deployedAt(p))].filter(Boolean).join(' · ')
            return (
              <div key={p.id} className="flex items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5">
                <span className={d.dot[deployTone(p)]} aria-hidden>●</span>
                <span className="flex min-w-0 flex-1 flex-col">
                  <b className="[overflow-wrap:anywhere]">{title}</b>
                  <span className="text-11 text-muted [overflow-wrap:anywhere]">{meta}</span>
                </span>
                {p.host && p.state === 'ready' ? (
                  <a href={`https://${p.host}`} target="_blank" rel="noreferrer" className="whitespace-nowrap text-12 font-semibold">{t('code.preview')}</a>
                ) : null}
              </div>
            )
          })}
        </div>
        <div className={`${d.card} min-w-0 overflow-hidden`}>
          <div className={d.head}><b className={d.headTitle}>{t('code.security')}</b></div>
          {security.length === 0 ? (
            <div className="px-[18px] py-[14px] text-12.5 text-muted">
              {t('code.noCi')} <Link href={'/development?tab=env' as Route} className="font-semibold">{t('code.connectCi')}</Link>
            </div>
          ) : security.map((s, i) => (
            <div key={i} className="flex items-center gap-[10px] border-b border-line px-[18px] py-[9px]">
              <span className={`w-[7px] self-stretch rounded-999 ${d.rule[s.tone]}`} aria-hidden />
              <span className="flex min-w-0 flex-1 flex-col">
                <b className="text-12.5">{s.title}</b>
                <span className="text-11.5 text-muted [overflow-wrap:anywhere]">{s.sub}</span>
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

type T = Awaited<ReturnType<typeof getTranslations>>
function securityRows(runs: CiRun[], many: boolean, pname: (k: string | null) => string | null, ago: (v: string) => string, t: T): Row[] {
  const out: Row[] = []
  for (const r of runs) {
    const pre = many ? `${pname(r.product)} · ` : ''
    const at = t('code.at', { ref: r.ref ?? '—', sha: shortSha(r.sha) ?? '', ago: ago(r.finished_at) })
    if (r.deps) {
      const high = r.deps.high + r.deps.critical
      out.push(high > 0
        ? { tone: 'alert', title: pre + t('code.depsHigh', { n: high }), sub: `${t('code.depsCounts', r.deps)} · ${at}` }
        : r.deps.moderate > 0
          ? { tone: 'warn', title: pre + t('code.depsModerate', { n: r.deps.moderate }), sub: `${t('code.depsNoHigh')} · ${at}` }
          : { tone: 'ok', title: pre + t('code.depsNone'), sub: at })
    }
    out.push(r.migrations_pending.length
      ? { tone: 'warn', title: pre + t('code.migrations', { n: r.migrations_pending.length }), sub: r.migrations_pending.join(' · ') }
      : { tone: 'ok', title: pre + t('code.noMigrations'), sub: at })
    const rls = r.suites.filter((s) => s.kind === 'security' || s.kind === 'anonymity')
    if (rls.length) {
      const failed = rls.reduce((a, s) => a + s.failed, 0)
      const passed = rls.reduce((a, s) => a + s.passed, 0)
      out.push(failed
        ? { tone: 'alert', title: pre + t('code.rlsFail'), sub: `${t('code.failing', { n: failed })} · ${at}` }
        : { tone: 'ok', title: pre + t('code.rlsPass'), sub: rls.some((s) => s.kind === 'anonymity') ? t('code.rlsAnonymity', { n: passed }) : t('code.checks', { n: passed }) })
    }
  }
  return out
}
