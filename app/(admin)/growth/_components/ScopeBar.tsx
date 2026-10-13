'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { RANGES, growthHref, type Device, type Scope, type Tab } from '@/lib/growth/scope'
import { useAgo } from '../../applications/_components/kit'

/**
 * The scope bar (SimpleGrowth.dc.html, showScope): the period, the drill-down path (period › day › hour), the source and
 * device filters and when the figures were last fed. Every choice is an address, so the server renders the scoped figures.
 */
export function ScopeBar({ tab, scope, channels, dayLabel, updatedAt, extra = {}, hideFilters = false, ranges = RANGES, sites = [] }: {
  tab: Tab
  scope: Scope
  channels: string[]
  /** the application's sites by hostname (0089: a site per market); the picker shows when there is more than one */
  sites?: string[]
  dayLabel: string | null
  updatedAt: string | null
  extra?: Record<string, string | number | null>
  hideFilters?: boolean
  ranges?: readonly (typeof RANGES)[number][]
}) {
  const t = useTranslations('simpleGrowth.scope')
  const tc = useTranslations('simpleGrowth.channels')
  const router = useRouter()
  const ago = useAgo()
  const go = (s: Partial<Scope>) => router.push(growthHref(tab, { ...scope, ...s }, extra) as Route)

  const crumbs: { label: string; href: string | null }[] = []
  if (scope.range === 'today') {
    crumbs.push({ label: dayLabel ?? t('ranges.today'), href: scope.hour !== null ? growthHref(tab, { ...scope, hour: null }, extra) : null })
  } else {
    crumbs.push({ label: t('last', { days: scope.range === '7d' ? 7 : scope.range === '90d' ? 90 : 30 }), href: scope.day ? growthHref(tab, { ...scope, day: null, hour: null }, extra) : null })
    if (scope.day) crumbs.push({ label: dayLabel ?? scope.day, href: scope.hour !== null ? growthHref(tab, { ...scope, hour: null }, extra) : null })
  }
  if (scope.hour !== null) crumbs.push({ label: `${String(scope.hour).padStart(2, '0')}:00`, href: null })

  const label = (on: boolean) =>
    `flex h-8 items-center gap-[5px] rounded-9 border pl-[10px] pr-1 text-12 text-muted ${on ? 'border-ink' : 'border-line'}`
  const channelName = (c: string) => (tc.has(c) ? tc(c) : c)

  return (
    <div className="flex flex-wrap items-center gap-2 rounded-16 border border-line bg-surface px-[10px] py-2">
      <div className="flex rounded-10 bg-tile p-[3px]" role="group" aria-label={t('rangeLabel')}>
        {ranges.map((r) => {
          const on = r === scope.range
          return (
            <Link key={r} href={growthHref(tab, { ...scope, range: r, day: null, hour: null }, extra) as Route} aria-current={on ? 'true' : undefined}
              className={`cursor-pointer whitespace-nowrap rounded-7 px-[11px] py-[6px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
              {t(`ranges.${r}`)}
            </Link>
          )
        })}
      </div>
      <nav className="flex items-center gap-1 text-12.5" aria-label={t('crumbs')}>
        {crumbs.map((c, i) => {
          const last = i === crumbs.length - 1
          return (
            <span key={i} className="flex items-center gap-1">
              {c.href && !last ? (
                <Link href={c.href as Route} className="whitespace-nowrap rounded-7 px-[6px] py-1 text-12.5 font-medium text-link">{c.label}</Link>
              ) : (
                <span className={`whitespace-nowrap rounded-7 px-[6px] py-1 text-12.5 ${last ? 'font-bold text-ink' : 'font-medium text-link'}`} aria-current={last ? 'true' : undefined}>{c.label}</span>
              )}
              <span className="text-faint">{last ? '' : '›'}</span>
            </span>
          )
        })}
      </nav>
      <span className="flex-1" />
      <SiteSelect tab={tab} scope={scope} sites={sites} extra={extra} />
      {hideFilters ? null : (
        <>
          <label className={label(!!scope.src)}>
            {t('source')}
            <select value={scope.src ?? ''} onChange={(e) => go({ src: e.target.value || null })}
              className="border-none bg-transparent text-12.5 font-semibold text-ink">
              <option value="">{t('allSources')}</option>
              {channels.map((c) => <option key={c} value={c}>{channelName(c)}</option>)}
            </select>
          </label>
          <label className={label(!!scope.dev)}>
            {t('device')}
            <select value={scope.dev ?? ''} onChange={(e) => go({ dev: (e.target.value || null) as Device | null })}
              className="border-none bg-transparent text-12.5 font-semibold text-ink">
              <option value="">{t('allDevices')}</option>
              <option value="desktop">{t('devices.desktop')}</option>
              <option value="mobile">{t('devices.mobile')}</option>
              <option value="tablet">{t('devices.tablet')}</option>
            </select>
          </label>
        </>
      )}
      <span className="whitespace-nowrap text-11.5 text-faint">{updatedAt ? t('updated', { ago: ago(updatedAt) }) : t('noData')}</span>
    </div>
  )
}

/**
 * Which of the application's sites the figures are for (0089: orgpuls.com, se.orgpuls.com, empvibe.com): all of them, or
 * one. SEO reads one site's Search Console and pages, so there it is one, the first unless another is chosen. Like every
 * scope choice it is an address. Nothing shows for an application with one site.
 */
function SiteSelect({ tab, scope, sites, extra }: { tab: Tab; scope: Scope; sites: string[]; extra: Record<string, string | number | null> }) {
  const t = useTranslations('simpleGrowth.scope')
  const router = useRouter()
  if (sites.length < 2) return null
  const all = tab !== 'seo'
  const value = scope.site ?? (all ? '' : sites[0]!)
  return (
    <label className={`flex h-8 items-center gap-[5px] rounded-9 border pl-[10px] pr-1 text-12 text-muted ${scope.site ? 'border-ink' : 'border-line'}`}>
      {t('site')}
      <select value={value} onChange={(e) => router.push(growthHref(tab, { ...scope, site: e.target.value || null }, extra) as Route)}
        className="border-none bg-transparent text-12.5 font-semibold text-ink">
        {all ? <option value="">{t('allSites')}</option> : null}
        {sites.map((h) => <option key={h} value={h}>{h}</option>)}
      </select>
    </label>
  )
}

/** SEO's views without the scope bar still say which site they read, and let it be changed (0089) */
export function SiteBar({ tab, scope, sites, extra = {} }: { tab: Tab; scope: Scope; sites: string[]; extra?: Record<string, string | number | null> }) {
  if (sites.length < 2) return null
  return (
    <div className="flex flex-wrap items-center justify-end gap-2 rounded-16 border border-line bg-surface px-[10px] py-2">
      <SiteSelect tab={tab} scope={scope} sites={sites} extra={extra} />
    </div>
  )
}
