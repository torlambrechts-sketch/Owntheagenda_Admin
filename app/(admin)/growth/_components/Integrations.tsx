import Link from 'next/link'
import type { Route } from 'next'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { growthHref } from '@/lib/growth/scope'
import type { GrowthIntegrations } from '@/lib/growth/types'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { SearchConsoleCard } from './SearchConsole'
import { PageSpeedPanel } from './PageSpeedPanel'
import { CrawlNow } from './CrawlNow'
import { AdPlatformPanel } from './ads/AdPlatformPanel'
import { AD_PROVIDERS, connectionState, type GrowthAds } from '@/lib/growth/ads'

const DAY = 86_400_000
type Card = {
  key: string; ini: string; name: string; on: boolean; state: string; desc: string; feeds: string[]; sync: string | null
  action: { kind: 'link'; label: string; href: string } | { kind: 'crawl' } | null
}

/**
 * Growth › Integrations (SimpleGrowth.dc.html, v.integrations) on growth_integrations: only what Sentral really reads from,
 * each with its true state, what it feeds and when it last did; the design's other cards (GA4, Google Ads, GTM, BigQuery,
 * Trends, Business Profile, Looker Studio, Ahrefs, Bing, Clarity, Microsoft Ads, Stripe, Slack) have no connector here and
 * are not shown as if they had (V-GR2-20). Google Ads, LinkedIn Ads and Meta Ads are connected here (0077). Search
 * Console's, PageSpeed's and each ad platform's setup open below the cards.
 */
export async function IntegrationsTab({ d, sc, ads, products, open, nf, app, canMeasure }: {
  d: GrowthIntegrations; sc: Seo | null; ads: GrowthAds | null; products: { key: string; name: string }[]; open: string | null; nf: NumberFormat; app: string
  canMeasure: boolean
}) {
  const t = await getTranslations('simpleGrowth.integrations')
  const format = await getFormatter()
  const now = (await getNow()).getTime()
  const ago = (iso: string | null) => (iso ? format.relativeTime(new Date(iso), now) : '—')
  const recent = (iso: string | null, days: number) => !!iso && now - new Date(iso).getTime() < days * DAY
  const hosts = d.tracker.sites.map((s) => s.hostname).join(', ')
  const site = sc?.site ?? null

  const tracker: Card = {
    key: 'tracker', ini: 'WT', name: t('cards.tracker.name'), on: recent(d.tracker.last_seen_at, 2),
    state: d.tracker.last_seen_at ? (recent(d.tracker.last_seen_at, 2) ? t('state.receiving') : t('state.quiet', { ago: ago(d.tracker.last_seen_at) })) : t('state.waiting'),
    desc: t('cards.tracker.desc', { hosts: hosts || app }), feeds: ['overview', 'funnel', 'pages'],
    sync: d.tracker.last_seen_at ? t('sync.tracker', { ago: ago(d.tracker.last_seen_at), n: formatNumber(d.tracker.sessions_24h, nf) }) : null,
    action: null,
  }
  const crawler: Card = {
    key: 'crawler', ini: 'CR', name: t('cards.crawler.name'), on: !!d.crawler && recent(d.crawler.last_at, 2) && d.crawler.error !== 'unreachable',
    state: d.crawler ? (d.crawler.error === 'unreachable' ? t('state.failed') : t('state.on')) : t('state.notRun'),
    desc: t('cards.crawler.desc'), feeds: ['tech', 'pages'],
    sync: d.crawler ? t('sync.crawler', { ago: ago(d.crawler.last_at), pages: d.crawler.pages }) : null,
    action: canMeasure && site ? { kind: 'crawl' } : null,
  }
  const gscOn = d.search_console?.status === 'connected'
  // each site's property (0089): the properties found, and the sites Search Console gives no access to
  const gscSites = d.search_console?.sites ?? []
  const props = [...new Set(gscSites.map((x) => x.property).filter((x): x is string => !!x))]
  const without = gscSites.filter((x) => !x.property).map((x) => x.hostname)
  const gscState = gscSites.length > 1
    ? [props.length ? t('state.connectedTo', { what: props.join(' · ') }) : t('state.noProperty'), ...(without.length ? [t('state.noPropertyFor', { sites: without.join(', ') })] : [])].join(' · ')
    : d.search_console?.property ? t('state.connectedTo', { what: d.search_console.property }) : t('state.noProperty')
  const gsc: Card = {
    key: 'gsc', ini: 'GSC', name: t('cards.gsc.name'), on: gscOn,
    state: gscOn ? gscState : d.search_console?.status === 'error' ? t('state.failed') : t('state.off'),
    desc: t('cards.gsc.desc'), feeds: ['seo', 'pages', 'tech'],
    sync: gscOn && d.search_console?.last_import_at ? t('sync.daily', { ago: ago(d.search_console.last_import_at) }) : null,
    action: { kind: 'link', label: gscOn ? t('manage') : t('connect'), href: growthHref('integrations', {}, { sub: open === 'gsc' ? null : 'gsc' }) },
  }
  const psiOn = d.pagespeed.status === 'connected'
  const psi: Card = {
    key: 'psi', ini: 'PSI', name: t('cards.psi.name'), on: psiOn,
    state: psiOn ? t('state.on') : d.pagespeed.status === 'error' ? t('state.keyRefused') : t('state.off'),
    desc: t('cards.psi.desc'), feeds: ['pages', 'tech'],
    sync: psiOn && d.pagespeed.last_at ? t('sync.psi', { ago: ago(d.pagespeed.last_at), pages: d.pagespeed.pages }) : null,
    action: { kind: 'link', label: psiOn ? t('manage') : t('connect'), href: growthHref('integrations', {}, { sub: open === 'psi' ? null : 'psi' }) },
  }
  const productCards: Card[] = d.products.map((p) => ({
    key: `p:${p.product}`, ini: p.name.slice(0, 2).toUpperCase(), name: t('cards.product.name', { name: p.name }), on: recent(p.last_event_at, 7),
    state: p.last_event_at ? (recent(p.last_event_at, 7) ? t('state.receiving') : t('state.quiet', { ago: ago(p.last_event_at) })) : t('state.waiting'),
    desc: t('cards.product.desc', { name: p.name }), feeds: ['funnel', 'accounts', 'paying'],
    sync: p.last_event_at ? t('sync.events', { ago: ago(p.last_event_at), n: p.events_24h }) : null, action: null,
  }))
  const emailOn = d.email?.status === 'connected'
  const email: Card = {
    key: 'email', ini: 'BR', name: t('cards.email.name'), on: emailOn, state: emailOn ? t('state.on') : t('state.off'),
    desc: t('cards.email.desc'), feeds: ['email'], sync: null, action: null,
  }
  // the ad platforms (0077): connected, refused, credentials waiting for a check, or nothing yet
  const adCards: Card[] = (ads?.providers ?? []).map((p) => {
    const st = connectionState(p)
    const accts = (ads?.accounts ?? []).filter((a) => a.provider === p.provider && !a.manager)
    const last = accts.map((a) => a.last_import_at).filter((x): x is string => !!x).sort().pop() ?? null
    return {
      key: p.provider, ini: { google_ads: 'GA', linkedin_ads: 'LI', meta_ads: 'ME' }[p.provider], name: t(`cards.${p.provider}.name`), on: st === 'connected',
      state: st === 'connected' ? t('state.accounts', { n: accts.filter((a) => a.product).length, total: accts.length })
        : st === 'error' ? t('state.failed') : st === 'stored' ? t('state.notChecked') : t('state.off'),
      desc: t(`cards.${p.provider}.desc`), feeds: ['campaigns', 'outcomes', 'creative'],
      sync: last ? t('sync.daily', { ago: ago(last) }) : null,
      action: { kind: 'link', label: st === 'connected' ? t('manage') : t('connect'), href: growthHref('integrations', {}, { sub: open === p.provider ? null : p.provider }) },
    }
  })
  const groups = [
    { h: t('groups.site'), items: [tracker, crawler] },
    { h: t('groups.google'), items: [gsc, psi] },
    ...(adCards.length ? [{ h: t('groups.ads'), items: adCards }] : []),
    { h: t('groups.products'), items: [...productCards, email] },
  ]
  const all = groups.flatMap((g) => g.items)

  const when = (iso: string) => {
    const d0 = new Date(iso)
    const days = Math.floor((new Date(now).setHours(0, 0, 0, 0) - new Date(d0).setHours(0, 0, 0, 0)) / DAY)
    const time = format.dateTime(d0, { hour: '2-digit', minute: '2-digit' })
    return days === 0 ? t('log.today', { time }) : days === 1 ? t('log.yesterday', { time }) : t('log.on', { day: format.dateTime(d0, { day: 'numeric', month: 'short' }), time })
  }
  const what = (l: GrowthIntegrations['log'][number]) => {
    const i = l.info as Record<string, unknown>
    const code = typeof i.code === 'string' ? ` · ${i.code}` : ''
    switch (l.source) {
      case 'tracker': return t('log.what.tracker', { n: l.rows ?? 0, views: Number(i.pageviews ?? 0) })
      case 'crawler': return t('log.what.crawler', { n: l.rows ?? 0, issues: Number(i.issues ?? 0) }) + code
      case 'search_console': return (typeof i.last_day === 'string' ? t('log.what.searchConsole', { day: i.last_day }) : t('log.what.searchConsoleNone')) + code
      case 'pagespeed': return t('log.what.pagespeed', { n: l.rows ?? 0 }) + code
      case 'product_events': return t('log.what.events', { n: l.rows ?? 0, kinds: Array.isArray(i.kinds) ? (i.kinds as string[]).join(', ') : '' })
      case 'url_inspection': return t('log.what.urlInspection', { n: l.rows ?? 0, indexed: Number(i.indexed ?? 0), pages: Number(i.pages ?? 0) })
      case 'google_ads': case 'linkedin_ads': case 'meta_ads':
        return (l.state === 'ok' ? t('log.what.ads', { n: l.rows ?? 0, months: Number(i.months ?? 0) }) : t('log.what.adsFailed')) + code
      default: return ''
    }
  }
  const STATE_TONE = { ok: 'text-link', warning: 'text-warn-ink', failed: 'text-danger' } as const

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="flex flex-wrap items-center gap-[14px] text-12.5 text-muted">
        <span>{t.rich('connected', { n: all.filter((c) => c.on).length, total: all.length, b: (x) => <b className="text-ink">{x}</b> })}</span>
        <span>{t('note')}</span>
      </div>
      {groups.map((g) => (
        <div key={g.h} className="flex flex-col gap-[10px]">
          <b className="text-14">{g.h}</b>
          <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr))]">
            {g.items.map((c) => (
              <div key={c.key} className={`flex flex-col gap-[7px] rounded-18 border bg-surface px-4 py-[14px] ${c.on ? 'border-line' : 'border-line-strong'}`}>
                <div className="flex items-center gap-[10px]">
                  <span className={`flex h-[34px] w-[34px] flex-none items-center justify-center rounded-10 text-12 font-bold ${c.on ? 'bg-ok-bg' : 'bg-tile'}`}>{c.ini}</span>
                  <span className="flex min-w-0 flex-1 flex-col">
                    <b className="text-13.5">{c.name}</b>
                    <span className={`text-11.5 font-bold [overflow-wrap:anywhere] ${c.on ? 'text-link' : 'text-faint'}`}>{c.state}</span>
                  </span>
                  {c.action?.kind === 'link' ? (
                    <Link href={c.action.href as Route}
                      className={`flex h-[30px] flex-none items-center whitespace-nowrap rounded-9 border border-ink px-[11px] text-12 font-bold text-ink hover:text-ink hover:no-underline ${c.on ? 'bg-surface' : 'bg-primary'}`}>
                      {c.action.label}
                    </Link>
                  ) : c.action?.kind === 'crawl' && site ? <CrawlNow site={site.id} /> : null}
                </div>
                <span className="text-12 leading-[1.45] text-ink-2">{c.desc}</span>
                <div className="flex flex-wrap gap-1">
                  {c.feeds.map((f) => <span key={f} className="rounded-999 bg-tile px-2 py-[2px] text-10.5 font-bold">→ {t(`feeds.${f}`)}</span>)}
                </div>
                {c.on && c.sync ? <span className="text-11 text-faint">{c.sync}</span> : null}
              </div>
            ))}
          </div>
          {g.items.some((c) => c.key === 'gsc') && open === 'gsc' && sc ? (
            <SearchConsoleCard sc={sc.search_console} site={sc.site?.hostname ?? null} app={app} connected={sc.connected} />
          ) : null}
          {ads && g.items.some((c) => c.key === open) && (AD_PROVIDERS as readonly string[]).includes(open ?? '') ? (
            <AdPlatformPanel provider={open as GrowthAds['providers'][number]['provider']} d={ads} products={products} />
          ) : null}
          {g.items.some((c) => c.key === 'psi') && open === 'psi' ? (
            <PageSpeedPanel status={d.pagespeed.status} lastError={d.pagespeed.last_error} lastAt={d.pagespeed.last_at} pages={d.pagespeed.pages}
              canManage={d.can_manage} canMeasure={canMeasure} site={site?.id ?? null} />
          ) : null}
        </div>
      ))}
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex justify-between gap-3 border-b border-line px-[18px] py-3"><b className="text-15">{t('log.title')}</b><span className="text-12 text-muted">{t('log.sub')}</span></div>
        <div className="overflow-x-auto"><div className="min-w-[540px]">
        {d.log.slice(0, 12).map((l, i) => (
          <div key={i} className="grid gap-[10px] border-b border-line px-[18px] py-2 text-12.5 [grid-template-columns:110px_minmax(0,1fr)_minmax(0,1.4fr)_90px]">
            <span className="whitespace-nowrap text-muted">{when(l.at)}</span>
            <b>{t(`log.sources.${l.source}`)}</b>
            <span className="text-muted [overflow-wrap:anywhere]">{what(l)}</span>
            <span className={`font-bold ${STATE_TONE[l.state]}`}>{t(`log.states.${l.state}`)}</span>
          </div>
        ))}
        </div></div>
        {d.log.length === 0 ? <div className="px-[18px] py-4 text-12.5 text-muted">{t('log.none')}</div> : null}
      </div>
    </div>
  )
}
