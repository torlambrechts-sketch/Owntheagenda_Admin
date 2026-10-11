import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { growthHref } from '@/lib/growth/scope'
import { cardTable, head } from '../v2kit'

/**
 * Marketing campaigns › Creative and landing pages (GrowthPlaybook.dc.html, v.creative). The message matrix, ad variants
 * with fatigue and landing page tests need impressions, click-through, frequency and test results from an ad platform or a
 * testing tool; none is connected, so the view says what it would need and where landing pages are measured today
 * (Pages and links) instead of drawing figures (V-GR2-37).
 */
export async function CreativeView() {
  const t = await getTranslations('simpleGrowth.playbook.creative')
  return (
    <section className={cardTable}>
      <div className={head}>
        <b className="text-15">{t('title')}</b>
        <span className="text-12 text-muted">{t('note')}</span>
      </div>
      <div className="flex flex-col gap-2 px-[18px] py-[14px] text-12.5 leading-[1.5] text-muted">
        <p className="m-0">{t('needs')}</p>
        <p className="m-0">{t.rich('today', { link: (x) => <Link href={growthHref('pages', {}) as Route}>{x}</Link> })}</p>
      </div>
    </section>
  )
}
