import type { Route } from 'next'
import { redirect } from 'next/navigation'
import { getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import { loadBoard, loadDealsBase } from '@/lib/data/deals'
import { DealsScreen } from './_components/DealsScreen'
import type { Rights } from './_components/shared'

/** Deals (Deals.dc.html): pipeline, list, forecast, archive and catalog, with the deal drawer (opened in
 * place; a ?deal=<id> address now opens the deal in CRM). */
export default async function DealsPage({ searchParams }: { searchParams: Promise<{ deal?: string }> }) {
  const sp = await searchParams
  // Sentral Simple (S5): a link to one deal (notifications, search, saved addresses) opens it in CRM; the full deals
  // screen (other pipelines, forecast, archive, catalogue) stays at /deals
  const linked = z.string().uuid().safeParse(sp.deal)
  if (linked.success) redirect(`/crm?deal=${linked.data}` as Route)
  const shell = await getShell()
  const base = await loadDealsBase()
  const t = await getTranslations('deals')

  if (base.pipelines.length === 0) {
    return (
      <div className="px-4 pb-[60px] pt-[18px] md:px-7">
        <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{t('empty.noPipelines')}</div>
      </div>
    )
  }

  const prefs = base.views.prefs
  const prefPipeline = typeof prefs.pipeline === 'string' ? prefs.pipeline : null
  const pipeline = base.pipelines.find((p) => p.id === prefPipeline)?.id ?? base.pipelines[0]!.id
  const showClosed = prefs.show_closed === true
  const board = await loadBoard(pipeline, [], showClosed)

  const rights: Rights = {
    meId: shell.me.id,
    readOnly: !can(shell, 'deals', 'add') && !can(shell, 'deals', 'edit_others'),
    add: can(shell, 'deals', 'add'),
    editOthers: can(shell, 'deals', 'edit_others'),
    del: can(shell, 'deals', 'delete'),
    bulk: can(shell, 'deals', 'bulk'),
    exportRows: can(shell, 'deals', 'export'),
    configure: can(shell, 'deals', 'configure'),
  }

  return (
    <DealsScreen
      base={base}
      rights={rights}
      nf={shell.me.number_format}
      initialPipeline={pipeline}
      initialShowClosed={showClosed}
      initialBoard={board.ok ? board.data : null}
      initialDeal={null}
      initialDealId={null}
    />
  )
}
