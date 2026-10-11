'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Seo } from '@/lib/data/simple-growth-shared'
import { planIdea } from '../actions'
import { cardTable, emptyRow } from './kit'

/**
 * «Content ideas» (SimpleGrowth.dc.html, ideas[]) on Search Console (0072): searches Google already shows the site for,
 * outside its top ten, that nobody tracks. Search Console has no monthly search volume, so the line says impressions over
 * the days read and the page Google showed (V-SGR-30). «Plan article» puts the search in the content plan.
 */
export function ContentIdeas({ ideas, product, nf, canEdit }: {
  ideas: NonNullable<Seo['ideas']>; product: string; nf: NumberFormat; canEdit: boolean
}) {
  const t = useTranslations('simpleGrowth.seo.ideas')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()

  const plan = (query: string) => start(async () => {
    const r = await planIdea({ product, query })
    if (!r.ok) { flash(te(r.code)); return }
    flash(t('planned'))
    router.refresh()
  })

  return (
    <div className={cardTable}>
      <div className="flex justify-between gap-3 border-b border-line px-[18px] py-[14px]">
        <b className="text-15">{t('title')}</b>
        <span className="text-12 text-muted">{t('sub')}</span>
      </div>
      {ideas.map((i) => (
        <div key={i.query} className="flex items-center gap-3 border-b border-line px-[18px] py-[11px]">
          <span className="flex min-w-0 flex-1 flex-col gap-[2px]">
            <b className="text-13 [overflow-wrap:anywhere]">{i.query}</b>
            <span className="text-12 text-muted [overflow-wrap:anywhere]">
              {t('line', { impressions: formatNumber(i.impressions, nf), days: i.days, position: i.position === null ? '—' : formatNumber(i.position, nf, 1) })}
              {i.page ? ` · ${i.page}` : ''}
            </span>
          </span>
          {canEdit || i.planned ? (
            <button type="button" disabled={pending || i.planned || !canEdit} onClick={() => plan(i.query)}
              className={`h-[30px] flex-none whitespace-nowrap rounded-9 border px-[11px] text-12 font-bold ${i.planned ? 'cursor-default border-link bg-ok-bg' : 'cursor-pointer border-ink bg-primary'}`}>
              {i.planned ? t('done') : t('plan')}
            </button>
          ) : null}
        </div>
      ))}
      {ideas.length === 0 ? <div className={emptyRow}>{t('empty')}</div> : null}
    </div>
  )
}
