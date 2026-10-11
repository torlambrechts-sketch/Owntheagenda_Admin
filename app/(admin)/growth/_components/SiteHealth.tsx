'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo, SeoIssue } from '@/lib/data/simple-growth-shared'
import { checkSiteHealth, fixIssue } from '../actions'

/** the design's two tones (IS[][0]): high #D4633A, medium #E0A21F */
const TONE: Record<SeoIssue['severity'], string> = { high: 'bg-alert', medium: 'bg-warn' }

/**
 * «Technical SEO» (SimpleGrowth.dc.html, issues[]) on seo-crawl (0072) and what Search Console and PageSpeed Insights see
 * that a crawl cannot (0073): a search two pages split, a page slow for real users. «Mark fixed» hides a crawl's issue until
 * the next crawl agrees or brings it back (V-SGR-31); the other two clear themselves when the figures do. Below the list, an
 * addition: a failed or partial crawl, issues awaiting the next check, and «Check now».
 */
export function SiteHealth({ health, cannibal, slow, site, product, nf, canEdit }: {
  health: NonNullable<Seo['health']>; cannibal: NonNullable<Seo['cannibal']>; slow: NonNullable<Seo['slow']>
  site: string; product: string; nf: NumberFormat; canEdit: boolean
}) {
  const t = useTranslations('simpleGrowth.seo.health')
  const te = useTranslations('common.errors')
  const format = useFormatter()
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()

  const fix = (kind: SeoIssue['kind']) => start(async () => {
    const r = await fixIssue({ product, kind })
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('fixed'))
    router.refresh()
  })
  const check = () => start(async () => {
    const r = await checkSiteHealth({ site })
    if (!r.ok) { flash(t.has(`codes.${r.code}`) ? t(`codes.${r.code}`) : t('codes.failed')); return }
    flash(r.error === 'unreachable' ? t('codes.unreachable') : t('checked', { pages: r.pages, issues: r.issues }))
    router.refresh()
  })

  const issues = health.issues
  const seconds = (ms: number | null) => formatNumber((ms ?? 0) / 1000, nf, 1)
  const listed = (paths: string[], count: number) => paths.join(' · ') + (count > paths.length ? ` ${t('more', { n: count - paths.length })}` : '')
  const line = (i: SeoIssue) => {
    const title = t(`kinds.${i.kind}.title`, { count: i.count, path: i.paths[0] ?? '', seconds: seconds(i.ms) })
    const sub = i.kind === 'duplicate_title' || i.kind === 'duplicate_description'
      ? t(`kinds.${i.kind}.sub`, { value: i.value ?? '' })
      : i.kind === 'broken_link'
        ? t('kinds.broken_link.sub', { from: i.value ?? '—', to: listed(i.paths, i.count) })
        : i.kind === 'slow_page' || i.kind === 'sitemap_missing'
          ? t(`kinds.${i.kind}.sub`)
          : listed(i.paths, i.count)
    return { title, sub }
  }
  const derived = [
    ...slow.map((s) => ({
      key: `slow${s.path}`, tone: 'bg-alert',
      title: s.lcp_ms !== null && s.lcp_ms > 2500 ? t('derived.lcp', { lcp: seconds(s.lcp_ms), path: s.path }) : t('derived.inp', { inp: formatNumber(s.inp_ms ?? 0, nf), path: s.path }),
      sub: s.field ? t('derived.fieldSub') : t('derived.labSub'),
    })),
    ...cannibal.map((c) => ({
      key: `can${c.query}`, tone: 'bg-warn',
      title: t('derived.cannibal', { q: c.query, n: c.pages.length }),
      sub: c.pages.map((p) => p.page).join(' · '),
    })),
  ]
  const open = issues.length + derived.length
  const crawled = health.last_crawl_at
    ? (() => {
        const d = new Date(health.last_crawl_at)
        const sameDay = new Date().toDateString() === d.toDateString()
        const time = format.dateTime(d, { hour: '2-digit', minute: '2-digit' })
        return sameDay ? t('crawledToday', { time }) : t('crawledOn', { day: format.dateTime(d, { day: 'numeric', month: 'short' }), time })
      })()
    : t('never')

  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex justify-between gap-3 border-b border-line px-[18px] py-3">
        <b className="text-15">{t('title')}</b>
        <span className="text-12 text-muted">{t('open', { count: open })} · {crawled}</span>
      </div>
      {issues.map((i) => {
        const { title, sub } = line(i)
        return (
          <div key={i.kind} className="flex items-center gap-3 border-b border-line px-[18px] py-[10px]">
            <span className={`w-[7px] self-stretch rounded-999 ${TONE[i.severity]}`} />
            <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
              <b className="text-13">{title}</b>
              <span className="text-12 text-muted [overflow-wrap:anywhere]">{sub}</span>
              {i.reopened ? <span className="text-11.5 font-bold text-danger">{t('reopened')}</span> : null}
            </span>
            {canEdit ? (
              <button type="button" disabled={pending} onClick={() => fix(i.kind)}
                className="h-[30px] flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold">
                {t('fix')}
              </button>
            ) : null}
          </div>
        )
      })}
      {derived.map((x) => (
        <div key={x.key} className="flex items-center gap-3 border-b border-line px-[18px] py-[10px]">
          <span className={`w-[7px] self-stretch rounded-999 ${x.tone}`} />
          <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
            <b className="text-13">{x.title}</b>
            <span className="text-12 text-muted [overflow-wrap:anywhere]">{x.sub}</span>
          </span>
        </div>
      ))}
      {open === 0 && health.last_crawl_at ? <div className="p-[22px] text-center text-13 font-semibold text-link">{t('none')}</div> : null}
      {health.last_error || health.awaiting_check || canEdit ? (
        <div className="flex flex-wrap items-center justify-between gap-2 px-[18px] py-[10px] text-12 text-muted">
          <span>
            {health.last_error && t.has(`codes.${health.last_error}`) ? t(`codes.${health.last_error}`) : ''}
            {health.last_error && health.awaiting_check ? ' · ' : ''}
            {health.awaiting_check ? t('awaiting', { count: health.awaiting_check }) : ''}
            {!health.last_error && !health.awaiting_check && health.last_crawl_at ? t('pages', { pages: health.pages ?? 0 }) : ''}
          </span>
          {canEdit ? (
            <button type="button" disabled={pending} onClick={check}
              className="h-[30px] flex-none cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold text-ink">
              {pending ? t('checking') : t('check')}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
