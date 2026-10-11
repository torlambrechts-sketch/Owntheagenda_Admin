import { getFormatter, getTranslations } from 'next-intl/server'
import type { Spend, Web as WebData, WebAttempt } from '@/lib/data/analytics'
import { RANGE_DAYS, share, type RangeKey } from '@/lib/data/analytics-calc'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { Campaigns } from './Campaigns'
import { Empty, Kpi, cardChart, cardTable, colHead, deltaTone, signedPct, sub, title } from './kit'

const SRC_COLS = '[grid-template-columns:minmax(0,1.3fr)_70px_70px_60px_60px]'
const REF_COLS = '[grid-template-columns:minmax(0,1.6fr)_60px_60px_60px_70px]'
const PAGE_COLS = '[grid-template-columns:minmax(0,1.6fr)_60px_60px_60px_70px]'
const VIEW_COLS = '[grid-template-columns:minmax(0,1.6fr)_80px_60px]'
const EXIT_COLS = '[grid-template-columns:minmax(0,1.6fr)_80px_60px]'
const DEV_COLS = '[grid-template-columns:minmax(0,1.2fr)_60px_60px_80px_60px]'
const SC_COLS = '[grid-template-columns:minmax(0,1.6fr)_64px_54px_54px_54px]'
const row = 'grid gap-[10px] border-b border-line px-[18px] py-[9px] text-13 tabular-nums'
const head = `grid gap-[10px] border-b border-line px-[18px] py-[9px] ${colHead}`
const path = 'truncate font-[ui-monospace,Menlo,monospace] text-12'
const OUTCOME_TONE: Record<WebAttempt['outcome'], string> = {
  opened: 'bg-tile text-muted', started: 'bg-highlight text-amber-ink', completed: 'bg-ok-bg text-ok-ink',
}

/**
 * Web analytics (Analytics.dc.html, v.web) on analytics_web: the in-house cookieless tracker (D-37). The
 * database keeps a daily-salted hash, never an address or a cookie, so «visitors» over a period is a sum of
 * daily uniques. Before the tracker sends anything the tab shows its empty state; Search Console shows its
 * connection state; campaign spend is what people entered. 0068 adds where visits come from (referrers and utm),
 * what they searched for (Search Console's queries, the ads' utm_term), where they end, and the signup form's own
 * funnel down to the last attempts as anonymous journeys (V-WEB-03).
 */
export async function Web({ d, spend, canSpend, range, nf, now }: {
  d: WebData; spend: Spend[]; canSpend: boolean; range: RangeKey; nf: NumberFormat; now: Date
}) {
  const t = await getTranslations('analytics')
  const format = await getFormatter()
  const sites = d.sites.map((s) => s.hostname).join(', ')
  const has = d.sessions > 0
  const pct = (n: number | null) => (n === null ? '—' : percent(n, nf))
  const num = (n: number | null | undefined) => (n == null ? '—' : formatNumber(n, nf))
  const channel = (c: string) => (t.has(`channels.${c}`) ? t(`channels.${c}`) : c)
  const device = (v: string) => (t.has(`web.devices.names.${v}`) ? t(`web.devices.names.${v}`) : v)
  const dur = (s: number | null | undefined) =>
    s == null ? t('web.dur.none') : s < 60 ? t('web.dur.s', { s }) : t('web.dur.ms', { m: Math.floor(s / 60), s: s % 60 })
  const delta = (cur: number, prev: number | null | undefined) => {
    if (prev == null || prev === 0) return { delta: null, tone: undefined }
    const p = Math.round(((cur - prev) / prev) * 100)
    return { delta: signedPct(p, nf), tone: deltaTone(p) }
  }

  // the daily series over the range, a day without sessions drawn at zero
  const days = RANGE_DAYS[range]
  const daily = new Map(d.daily.map((x) => [x.day.slice(0, 10), x]))
  const dayKeys = Array.from({ length: days }, (_, i) => new Date(now.getTime() - (days - 1 - i) * 86_400_000).toISOString().slice(0, 10))
  const series = dayKeys.map((k) => daily.get(k)?.visitors ?? 0)
  const vmax = Math.max(1, ...series)
  const xy = (i: number, v: number) => `${((i * 600) / (days - 1)).toFixed(1)},${(156 - Math.min(1, v / vmax) * 146).toFixed(1)}`
  const pts = series.map((v, i) => xy(i, v)).join(' ')
  // signups × 20, drawn only on the days the read returns (a day with sessions)
  const hasSignups = d.daily.some((x) => typeof x.signups === 'number')
  const sign = dayKeys.flatMap((k, i) => { const x = daily.get(k); return typeof x?.signups === 'number' ? [xy(i, x.signups * 20)] : [] }).join(' ')
  const posTone = (p: number) => (p <= 3 ? 'text-link' : p <= 6 ? 'text-warn-ink' : 'text-danger')

  // the website funnel: sessions down to the site's own «done»; the account count is the products' (not a session)
  const su = d.signup
  const funnel = [
    { key: 'visit', v: d.sessions },
    { key: 'cta', v: su?.cta ?? 0 },
    { key: 'opened', v: su?.opened ?? 0 },
    { key: 'orgnr_entered', v: su?.started ?? 0 },
    { key: 'completed', v: su?.completed ?? 0 },
    { key: 'account_created', v: d.signups },
  ]
  const personas = d.events.filter((e) => e.name === 'persona_click' && e.value)
  const persona = (v: string) => (t.has(`web.personas.names.${v}`) ? t(`web.personas.names.${v}`) : v)
  const monthLabel = Object.fromEntries(spend.map((s) => [s.month, format.dateTime(new Date(`${s.month}-15T12:00:00Z`), { month: 'short', year: 'numeric' })]))
  const thisMonth = now.toISOString().slice(0, 7)
  const connected = d.search_console === 'connected'
  const event = (name: string, value: string | null) =>
    t.has(`web.attempts.events.${name}`) ? t(`web.attempts.events.${name}`, { value: value ?? '', name }) : t('web.attempts.events.other', { name })
  const vis = delta(d.visitors, d.visitors_prev)
  const ses = delta(d.sessions, d.sessions_prev)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-[10px] rounded-14 border border-dashed border-line-strong px-[14px] py-[10px] text-12 text-muted">{t('web.banner')}</div>

      {has ? (
        <>
          <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
            <Kpi size={24} label={t('web.kpi.visitors')} value={formatNumber(d.visitors, nf)} delta={vis.delta} tone={vis.tone} tip={vis.delta ? t('web.kpi.prevTip') : undefined} />
            <Kpi size={24} label={t('web.kpi.sessions')} value={formatNumber(d.sessions, nf)} delta={ses.delta} tone={ses.tone} tip={ses.delta ? t('web.kpi.prevTip') : undefined} />
            <Kpi size={24} label={t('web.kpi.pages')} value={formatNumber(d.pageviews / d.sessions, nf, 1)} />
            <Kpi size={24} label={t('web.kpi.bounce')} value={pct(share(d.bounces, d.sessions))} />
            <Kpi size={24} label={t('web.kpi.time')} value={d.avg_seconds == null ? '—' : dur(d.avg_seconds)} tip={t('web.kpi.timeTip')} />
            <Kpi size={24} label={t('web.kpi.signups')} value={formatNumber(d.signups, nf)} />
          </div>

          <div className={cardChart}>
            <div className="mb-[10px] flex items-baseline justify-between gap-3">
              <span className={title}>{hasSignups ? t('web.chart.titleSignups', { sites }) : t('web.chart.title', { sites })}</span>
              <span className={sub}>{t(`usage.rangeLong.${range}`)}</span>
            </div>
            <svg viewBox="0 0 600 160" preserveAspectRatio="none" className="block h-[160px] w-full" role="img" aria-label={t('web.chart.visitors')}>
              <polygon points={`0,156 ${pts} 600,156`} fill="#E4EEEC" />
              <polyline points={pts} fill="none" stroke="#9DB8B3" strokeWidth="2" vectorEffect="non-scaling-stroke" />
              {hasSignups ? <polyline points={sign} fill="none" stroke="#2F5D2A" strokeWidth="2" strokeDasharray="5 4" vectorEffect="non-scaling-stroke" /> : null}
            </svg>
            <div className="mt-2 flex gap-[14px] text-11.5 text-muted">
              <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-teal-mid" />{t('web.chart.visitors')}</span>
              {hasSignups ? <span className="flex items-center gap-[6px]"><span className="h-[3px] w-[14px] bg-link" />{t('web.chart.signups')}</span> : null}
            </div>
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={cardChart}>
              <div className={`${title} mb-3`}>{t('web.funnel.title')}</div>
              {funnel.map((f, i) => {
                const prev = i ? funnel[i - 1]!.v : f.v
                return (
                  <div key={f.key} className="grid items-center gap-[10px] py-[6px] text-12.5 [grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)_54px_54px]">
                    <span className="font-semibold">{t(`web.funnel.${f.key}`)}</span>
                    <span className="block h-5 overflow-hidden rounded-7 bg-tile"><span className="block h-full bg-blue-bg" style={{ width: `${Math.min(100, (f.v / Math.max(1, d.sessions)) * 100 + 2)}%` }} /></span>
                    <b className="text-right">{formatNumber(f.v, nf)}</b>
                    <span className="text-right text-12 font-bold text-danger">{i && prev && f.v < prev ? `−${percent(Math.round((1 - f.v / prev) * 100), nf)}` : ''}</span>
                  </div>
                )
              })}
              <div className="mt-2 text-11.5 text-muted">{t('web.funnel.note')}</div>
            </div>

            <div className={cardChart}>
              <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
                <span className={title}>{t('web.signup.title')}</span><span className={sub}>{t('web.signup.sub')}</span>
              </div>
              {su && su.opened + su.started + su.completed > 0 ? (
                <div className="flex flex-col gap-[10px] text-12.5">
                  <div className="grid gap-2 [grid-template-columns:repeat(auto-fit,minmax(130px,1fr))]">
                    <div className="rounded-15 border border-line bg-canvas px-[14px] py-3">
                      <div className="font-serif text-24 font-semibold tabular-nums">{formatNumber(Math.max(0, su.opened - su.started), nf)}</div>
                      <div className="text-11.5 text-muted">{t('web.signup.leftBefore')}</div>
                    </div>
                    <div className="rounded-15 border border-line bg-canvas px-[14px] py-3">
                      <div className="font-serif text-24 font-semibold tabular-nums">{formatNumber(Math.max(0, su.started - su.completed), nf)}</div>
                      <div className="text-11.5 text-muted">{t('web.signup.leftAfter')}</div>
                    </div>
                    <div className="rounded-15 border border-line bg-canvas px-[14px] py-3">
                      <div className="font-serif text-24 font-semibold tabular-nums">{formatNumber(su.completed, nf)}</div>
                      <div className="text-11.5 text-muted">{t('web.funnel.completed')}</div>
                    </div>
                  </div>
                  {su.steps.length ? (
                    <div>
                      <div className={`${colHead} mb-1`}>{t('web.signup.steps')}</div>
                      {su.steps.map((s) => <div key={s.value} className="flex justify-between border-b border-line py-[6px]"><span className={path}>{s.value}</span><b>{formatNumber(s.sessions, nf)}</b></div>)}
                    </div>
                  ) : null}
                  {su.errors.length ? (
                    <div>
                      <div className={`${colHead} mb-1`}>{t('web.signup.errors')}</div>
                      {su.errors.map((s) => (
                        <div key={s.value} className="flex justify-between gap-3 border-b border-line py-[6px]">
                          <span className={`${path} text-danger`}>{s.value}</span>
                          <span className="text-muted">{t('web.signup.errorsCount', { count: formatNumber(s.count, nf), sessions: formatNumber(s.sessions, nf) })}</span>
                        </div>
                      ))}
                    </div>
                  ) : null}
                  {su.steps.length === 0 && su.errors.length === 0 ? <div className="text-11.5 text-muted">{t('web.signup.noDetail')}</div> : null}
                  {su.ctas.length ? (
                    <div>
                      <div className={`${colHead} mb-1`}>{t('web.signup.ctas')}</div>
                      {su.ctas.map((s) => <div key={s.value} className="flex justify-between border-b border-line py-[6px]"><span className={path}>{s.value}</span><b>{formatNumber(s.sessions, nf)}</b></div>)}
                    </div>
                  ) : null}
                </div>
              ) : <Empty>{t('web.signup.none')}</Empty>}
            </div>
          </div>

          <div className={cardTable}>
            <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
              <span className={title}>{t('web.attempts.title')}</span><span className={sub}>{t('web.attempts.sub')}</span>
            </div>
            {d.attempts.map((a) => (
              <div key={a.at} className="flex flex-col gap-[6px] border-b border-line px-[18px] py-[10px] text-12.5">
                <div className="flex flex-wrap items-center gap-x-[10px] gap-y-1">
                  <b className="tabular-nums">{format.dateTime(new Date(a.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</b>
                  <span className={`rounded-999 px-[9px] py-[2px] text-11.5 font-bold ${OUTCOME_TONE[a.outcome]}`}>{t(`web.attempts.outcome.${a.outcome}`)}</span>
                  <span className="text-muted">{channel(a.channel)}{a.source ? ` · ${t('web.attempts.via', { source: a.source })}` : ''}</span>
                  <span className="text-muted">· {device(a.device)}</span>
                  <span className="text-muted">· {dur(a.seconds)}</span>
                </div>
                <div className="flex flex-wrap items-center gap-[6px]">
                  {a.steps.map((s, i) => (
                    <span key={i} className="flex items-center gap-[6px]">
                      {i ? <span className="text-muted">→</span> : null}
                      <span className={`rounded-7 border px-[7px] py-[2px] ${s.kind === 'view' ? 'border-line bg-canvas' : s.name === 'signup_error' ? 'border-danger text-danger' : 'border-line-strong bg-highlight'}`}>
                        <span className={s.kind === 'view' ? path : 'text-12'}>{s.kind === 'view' ? s.path : event(s.name, s.value)}</span>
                        <span className="ml-[6px] text-11 text-muted">+{s.seconds} s</span>
                      </span>
                    </span>
                  ))}
                </div>
              </div>
            ))}
            {d.attempts.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('web.attempts.empty')}</div> : null}
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={`${cardTable} overflow-x-auto`}>
              <div className={`border-b border-line px-[18px] py-[14px] ${title}`}>{t('web.sources.title')}</div>
              <div className={`${head} min-w-[420px] ${SRC_COLS}`}>
                <span>{t('web.sources.cols.source')}</span><span>{t('web.sources.cols.visits')}</span><span>{t('web.sources.cols.bounce')}</span>
                <span>{t('web.sources.cols.signups')}</span><span>{t('web.sources.cols.conv')}</span>
              </div>
              {d.channels.map((s) => (
                <div key={s.channel} className={`${row} min-w-[420px] ${SRC_COLS}`}>
                  <b>{channel(s.channel)}</b><span>{formatNumber(s.sessions, nf)}</span>
                  <span className="text-muted">{s.bounce != null ? percent(s.bounce, nf) : '—'}</span>
                  <span>{s.signups != null ? formatNumber(s.signups, nf) : '—'}</span>
                  <b>{s.signups != null ? pct(share(s.signups, s.sessions)) : '—'}</b>
                </div>
              ))}
            </div>
            <div className={`${cardTable} overflow-x-auto`}>
              <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
                <span className={title}>{t('web.referrers.title')}</span><span className={sub}>{t('web.referrers.sub')}</span>
              </div>
              <div className={`${head} min-w-[440px] ${REF_COLS}`}>
                <span>{t('web.referrers.cols.source')}</span><span>{t('web.referrers.cols.visits')}</span><span>{t('web.referrers.cols.bounce')}</span>
                <span>{t('web.referrers.cols.started')}</span><span>{t('web.referrers.cols.completed')}</span>
              </div>
              {d.sources.map((s) => (
                <div key={`${s.source}|${s.medium}|${s.campaign}`} className={`${row} min-w-[440px] ${REF_COLS}`}>
                  <span className="flex min-w-0 flex-col">
                    {s.source ? <b className="truncate">{s.source}</b> : <b className="truncate text-muted" title={t('web.referrers.directTip')}>{t('web.referrers.direct')}</b>}
                    {s.medium || s.campaign ? <span className="truncate text-11 text-muted">{[s.medium, s.campaign].filter(Boolean).join(' · ')}</span> : null}
                  </span>
                  <span>{formatNumber(s.sessions, nf)}</span><span className="text-muted">{pct(s.bounce)}</span>
                  <span>{formatNumber(s.started, nf)}</span><b>{formatNumber(s.completed, nf)}</b>
                </div>
              ))}
            </div>
          </div>

          <div className={`${cardTable} overflow-x-auto`}>
            <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
              <span className={title}>{t('web.pages.title')}</span><span className={sub}>{t('web.landing.sub')}</span>
            </div>
            <div className={`${head} min-w-[440px] ${PAGE_COLS}`}>
              <span>{t('web.landing.cols.path')}</span><span>{t('web.landing.cols.visits')}</span><span>{t('web.landing.cols.bounce')}</span>
              <span>{t('web.landing.cols.started')}</span><span>{t('web.landing.cols.completed')}</span>
            </div>
            {d.landing.map((s) => (
              <div key={s.path ?? ''} className={`${row} min-w-[440px] ${PAGE_COLS}`}>
                <span className={path}>{s.path ?? '—'}</span><span>{formatNumber(s.sessions, nf)}</span>
                <span className="text-muted">{pct(s.bounce)}</span><span>{num(s.started)}</span><b className="text-link">{num(s.completed)}</b>
              </div>
            ))}
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={cardTable}>
              <div className={`border-b border-line px-[18px] py-[14px] ${title}`}>{t('web.topPages.title')}</div>
              <div className={`${head} ${VIEW_COLS}`}>
                <span>{t('web.topPages.cols.path')}</span><span>{t('web.topPages.cols.views')}</span><span>{t('web.topPages.cols.sessions')}</span>
              </div>
              {d.top_pages.map((s) => (
                <div key={s.path} className={`${row} ${VIEW_COLS}`}><span className={path}>{s.path}</span><span>{formatNumber(s.views, nf)}</span><span>{formatNumber(s.sessions, nf)}</span></div>
              ))}
            </div>
            <div className={cardTable}>
              <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
                <span className={title}>{t('web.exits.title')}</span><span className={sub}>{t('web.exits.sub')}</span>
              </div>
              <div className={`${head} ${EXIT_COLS}`}>
                <span>{t('web.exits.cols.path')}</span><span>{t('web.exits.cols.exits')}</span><span>{t('web.exits.cols.rate')}</span>
              </div>
              {d.exits.map((s) => (
                <div key={s.path} className={`${row} ${EXIT_COLS}`}><span className={path}>{s.path}</span><span>{formatNumber(s.exits, nf)}</span><b className={s.rate >= 80 ? 'text-danger' : ''}>{percent(s.rate, nf)}</b></div>
              ))}
            </div>
          </div>

          <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
            <div className={`${cardTable} overflow-x-auto`}>
              <div className={`border-b border-line px-[18px] py-[14px] ${title}`}>{t('web.devices.title')}</div>
              <div className={`${head} min-w-[400px] ${DEV_COLS}`}>
                <span>{t('web.devices.cols.device')}</span><span>{t('web.devices.cols.visits')}</span><span>{t('web.devices.cols.bounce')}</span>
                <span>{t('web.devices.cols.opened')}</span><span>{t('web.devices.cols.started')}</span>
              </div>
              {d.devices.map((s) => (
                <div key={s.device} className={`${row} min-w-[400px] ${DEV_COLS}`}>
                  <b>{device(s.device)}</b><span>{formatNumber(s.sessions, nf)}</span><span className="text-muted">{pct(s.bounce)}</span>
                  <span>{formatNumber(s.opened, nf)}</span><b>{formatNumber(s.started, nf)}</b>
                </div>
              ))}
              {d.devices.some((s) => s.device === 'unknown') ? <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('web.devices.unknownNote')}</div> : null}
            </div>
            <div className={cardChart}>
              <div className={`${title} mb-3`}>{t('web.personas.title')}</div>
              {personas.length ? (
                <div className="grid grid-cols-2 gap-[10px]">
                  {personas.map((p) => (
                    <div key={p.value} className="rounded-15 border border-line bg-canvas px-[14px] py-3">
                      <b className="text-13">{persona(p.value!)}</b>
                      <div className="mt-1 font-serif text-24 font-semibold">{formatNumber(p.count, nf)}</div>
                      <div className="text-11.5 text-muted">{t('web.personas.sub')}</div>
                    </div>
                  ))}
                </div>
              ) : <Empty>{t('web.personas.empty')}</Empty>}
            </div>
          </div>
        </>
      ) : (
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center">
          <div className="text-15 font-bold">{t('web.empty.title')}</div>
          <div className="mt-2 text-13 text-muted">{t('web.empty.body', { sites })}</div>
        </div>
      )}

      <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr))]">
        <div className={`${cardTable} overflow-x-auto`}>
          <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
            <span className={title}>{t('web.search.title')}</span>
            <span className={sub}>{connected ? t('web.search.sub') : t('web.search.notConnected.tag')}</span>
          </div>
          {connected ? (
            <>
              <div className={`${head} min-w-[420px] ${SC_COLS}`}>
                <span>{t('web.search.cols.query')}</span><span>{t('web.search.cols.impr')}</span><span>{t('web.search.cols.clicks')}</span>
                <span>{t('web.search.cols.ctr')}</span><span>{t('web.search.cols.pos')}</span>
              </div>
              {d.search.map((s) => (
                <div key={s.query} className={`${row} min-w-[420px] ${SC_COLS}`}>
                  <span className="truncate">{s.query}</span><span>{formatNumber(s.impressions, nf)}</span><span>{formatNumber(s.clicks, nf)}</span>
                  <span className="text-muted">{s.ctr != null ? percent(s.ctr, nf) : '—'}</span>
                  {s.position != null ? <b className={posTone(s.position)}>{formatNumber(s.position, nf, 1)}</b> : <b>—</b>}
                </div>
              ))}
              {d.search.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('web.search.empty')}</div> : null}
            </>
          ) : (
            <div className="px-[18px] py-5">
              <div className="text-13.5 font-bold">{t('web.search.notConnected.title')}</div>
              <div className="mt-1 text-12.5 text-muted">{t('web.search.notConnected.body')}</div>
            </div>
          )}
        </div>
        <div className={`${cardTable} overflow-x-auto`}>
          <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
            <span className={title}>{t('web.paid.title')}</span><span className={sub}>{t('web.paid.sub')}</span>
          </div>
          {d.paid_terms.length ? (
            <>
              <div className={`${head} min-w-[420px] ${REF_COLS}`}>
                <span>{t('web.paid.cols.term')}</span><span>{t('web.paid.cols.visits')}</span><span>{t('web.paid.cols.bounce')}</span>
                <span>{t('web.paid.cols.started')}</span><span>{t('web.paid.cols.completed')}</span>
              </div>
              {d.paid_terms.map((s) => (
                <div key={s.term} className={`${row} min-w-[420px] ${REF_COLS}`}>
                  <span className="truncate">{s.term}</span><span>{formatNumber(s.sessions, nf)}</span><span className="text-muted">{pct(s.bounce)}</span>
                  <span>{formatNumber(s.started, nf)}</span><b>{formatNumber(s.completed, nf)}</b>
                </div>
              ))}
            </>
          ) : <div className="px-[18px] py-4 text-12.5 text-muted">{t('web.paid.empty')}</div>}
        </div>
      </div>

      <div className={cardTable}>
        <div className="flex flex-wrap justify-between gap-2 border-b border-line px-[18px] py-[14px]">
          <span className={title}>{t('web.campaigns.title')}</span><span className={sub}>{t('web.campaigns.sub')}</span>
        </div>
        <Campaigns rows={spend} figures={d.campaigns ?? []} canEdit={canSpend} nf={nf} thisMonth={thisMonth} monthLabel={monthLabel} />
      </div>
    </div>
  )
}
