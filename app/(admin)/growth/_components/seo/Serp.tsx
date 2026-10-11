import { getTranslations } from 'next-intl/server'
import { card, label11 } from '../v2kit'

/**
 * SEO › Search results and competitors (SeoSuite.dc.html, v.serp). Competitors' visibility, result-page features and
 * keyword gaps need result-page data from an SEO tool (Ahrefs, Semrush, DataForSEO); Sentral has none, and Search Console
 * reports only the site's own results. The view says what it waits for rather than drawing figures (V-GR2-29).
 */
export async function SeoSerpView() {
  const t = await getTranslations('simpleGrowth.seoSuite.serp')
  return (
    <section className={`${card} flex flex-col gap-2 px-5 py-4`}>
      <span className={label11}>{t('needs')}</span>
      <b className="text-15">{t('title')}</b>
      <p className="m-0 max-w-[720px] text-13 leading-[1.5] text-muted">{t('body')}</p>
    </section>
  )
}
