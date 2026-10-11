'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo, SeoIssue } from '@/lib/data/simple-growth-shared'
import { useAgo } from '../../applications/_components/kit'
import { checkSiteHealth, fixIssue } from '../actions'
import { cardTable } from './kit'

/** the design's two tones (IS[][0]): high #D4633A, medium #E0A21F */
const TONE: Record<SeoIssue['severity'], string> = { high: 'bg-alert', medium: 'bg-warn' }

/**
 * «Site health» (SimpleGrowth.dc.html, issues[]) on seo-crawl (0072): the issues the last crawl of the application's site
 * found, most serious first. «Mark fixed» hides one until the next crawl agrees or brings it back (V-SGR-29). Below the
 * list, an addition: when the site was last read and «Check now».
 */
export function SiteHealth({ health, site, product, nf, canEdit }: {
  health: NonNullable<Seo['health']>; site: string; product: string; nf: NumberFormat; canEdit: boolean
}) {
  const t = useTranslations('simpleGrowth.seo.health')
  const te = useTranslations('common.errors')
  const ago = useAgo()
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

  return (
    <div className={cardTable}>
      <div className="flex justify-between gap-3 border-b border-line px-[18px] py-[14px]">
        <b className="text-15">{t('title')}</b>
        <span className="text-12 text-muted">{t('open', { count: issues.length })}</span>
      </div>
      {issues.map((i) => {
        const { title, sub } = line(i)
        return (
          <div key={i.kind} className="flex items-center gap-3 border-b border-line px-[18px] py-[11px]">
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
      {issues.length === 0 && health.last_crawl_at ? <div className="p-6 text-center text-13 font-semibold text-link">{t('none')}</div> : null}
      <div className="flex flex-wrap items-center justify-between gap-2 px-[18px] py-[10px] text-12 text-muted">
        <span>
          {health.last_crawl_at
            ? t('lastCrawl', { ago: ago(health.last_crawl_at), pages: health.pages ?? 0 })
            : t('never')}
          {health.last_error && t.has(`codes.${health.last_error}`) ? ` · ${t(`codes.${health.last_error}`)}` : ''}
          {health.awaiting_check ? ` · ${t('awaiting', { count: health.awaiting_check })}` : ''}
        </span>
        {canEdit ? (
          <button type="button" disabled={pending} onClick={check}
            className="h-[30px] flex-none cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold text-ink">
            {pending ? t('checking') : t('check')}
          </button>
        ) : null}
      </div>
    </div>
  )
}
