import { getTranslations } from 'next-intl/server'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { expectedCtr } from '@/lib/growth/calc'
import type { SeoOpp } from '@/lib/growth/seo'

/** «#4,2»: a position the way the design writes it */
export const pos = (p: number | null, nf: NumberFormat) => (p === null ? '—' : formatNumber(Math.round(p * 10) / 10, nf, Number.isInteger(Math.round(p * 10) / 10) ? 0 : 1))

/** An opportunity's line and its note (SeoSuite.dc.html OPP[]: «Move … from #4,2 into top 3» / «18 400 searches · …»), its
 *  value per month or, without the economics, the clicks it would bring */
export async function oppTexts(opps: SeoOpp[], nf: NumberFormat) {
  const t = await getTranslations('simpleGrowth.seoSuite')
  return opps.map((o) => {
    const q = o.query
    const pct = (v: number | null) => (v === null ? '—' : percent(v * 100, nf))
    let line: string
    let note: string
    switch (o.kind) {
      case 'striking':
        line = t('opps.t.striking', { q, pos: pos(o.position, nf) })
        note = t('opps.s.striking', { impr: formatNumber(o.impressions, nf), ctr: pct(o.ctr) })
        break
      case 'low_ctr':
        line = t('opps.t.low_ctr', { q })
        note = t('opps.s.low_ctr', { pos: pos(o.position, nf), ctr: pct(o.ctr), expected: pct(o.position === null ? null : expectedCtr(o.position)) })
        break
      case 'gap':
        line = t('opps.t.gap', { q })
        note = t('opps.s.gap', { impr: formatNumber(o.impressions, nf), pos: pos(o.position, nf) })
        break
      case 'cannibal': {
        const [a, b] = o.pages ?? []
        line = t('opps.t.cannibal', { q })
        note = t('opps.s.cannibal', { a: a?.page ?? '—', b: b?.page ?? '—', sa: Math.round((a?.share ?? 0) * 100), sb: Math.round((b?.share ?? 0) * 100) })
        break
      }
      case 'decay': {
        const change = o.before ? Math.round(((o.now ?? 0) / o.before - 1) * 100) : null
        line = t('opps.t.decay', { path: o.path ?? '—' })
        note = t('opps.s.decay', { change: change === null ? '—' : `${change >= 0 ? '+' : '−'}${percent(Math.abs(change), nf)}`, q })
        break
      }
    }
    return {
      line,
      note,
      type: t(`kinds.${o.kind}`),
      effort: t(`effort.${o.effort}`),
      worth: o.value !== null ? t('perMonth', { value: money(o.value, nf) }) : t('clicksPerMonth', { n: formatNumber(o.clicks, nf) }),
      worthShort: o.value !== null ? money(o.value, nf) : t('clicksPerMonth', { n: formatNumber(o.clicks, nf) }),
    }
  })
}

/** The type pill's colour (TC in the design) */
export const KIND_BG: Record<SeoOpp['kind'], string> = {
  striking: 'bg-highlight', low_ctr: 'bg-apricot', gap: 'bg-blue-bg', cannibal: 'bg-lilac', decay: 'bg-peach',
}
