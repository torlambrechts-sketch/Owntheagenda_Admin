import { getLocale, getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import { loadBoard } from '@/lib/data/dev-core'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { SENTRAL_COLOR } from './core/logic'
import type { ProductInfo } from './core/styles'
import { BoardView as Board } from './core/BoardView'

/**
 * Development › Work board (DevHub.dc.html, v.board): Sentral's own work items in seven columns, with the running
 * sprint's line computed from its rows. Cards move by drag and drop or, from the keyboard, Alt+← and Alt+→ (and in the
 * card's dialog). Nothing is synced to a tracker: the board is the tracker.
 */
export async function BoardView(props: DevTabProps) {
  void props
  const t = await getTranslations('devCore')
  const [shell, data, locale] = await Promise.all([getShell(), loadBoard(), getLocale()])
  const products: ProductInfo[] = [...shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color })), { key: 'sentral', name: t('sentral'), color: SENTRAL_COLOR }]
  return <Board data={data} products={products} locale={locale} />
}
