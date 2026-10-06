import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadEnrichment, loadFeed, loadPreviewRecords, loadScoring, previewScore } from '@/lib/data/feed'
import { FEED_TABS, KINDS, SCREEN_TABS } from '@/lib/data/feed-shared'
import { ScreenTabs } from './_components/ScreenTabs'
import { FeedView } from './_components/FeedView'
import { ScoringView } from './_components/ScoringView'
import { EnrichView } from './_components/EnrichView'

const Params = z.object({
  tab: z.enum(SCREEN_TABS).catch('feed'),
  ft: z.enum(FEED_TABS).catch('follow_ups'),
  kind: z.string().regex(/^[a-z_]{2,40}$/).nullable().catch(null),
  stage: z.string().uuid().nullable().catch(null),
  model: z.string().uuid().nullable().catch(null),
  record: z.string().uuid().nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

/**
 * Feed (Feed.dc.html): Feed, Scoring models and Enrichment. The tab, the feed's sub-tab and filters, the
 * chosen model and the preview record live in the address; each tab loads only what it shows.
 */
export default async function FeedPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({
    tab: one(sp.tab) ?? 'feed', ft: one(sp.ft) ?? 'follow_ups', kind: one(sp.kind) ?? null, stage: one(sp.stage) ?? null,
    model: one(sp.model) ?? null, record: one(sp.record) ?? null,
  })
  const shell = await getShell()
  const t = await getTranslations('feed')
  const nf = shell.me.number_format

  // every feed, scoring and enrichment function asks for «See» on deals
  if (!can(shell, 'deals', 'see')) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
        </div>
      </div>
    )
  }

  let body: React.ReactNode
  if (p.tab === 'feed') {
    const kind = p.kind && KINDS[p.ft].includes(p.kind) ? p.kind : null
    const b = await loadFeed(p.ft, { ...(kind ? { kinds: [kind] } : {}), ...(p.stage ? { stage_ids: [p.stage] } : {}) })
    body = (
      <FeedView
        ft={p.ft}
        kind={kind}
        stage={p.stage}
        feed={b.feed}
        progress={b.progress}
        pipelines={b.pipelines.map((x) => ({ id: x.id, name: x.name, stages: x.stages.map((s) => ({ id: s.id, name: s.name })) }))}
        canSend={b.canSend}
        nf={nf}
        owner={shell.me.name.split(' ')[0] ?? shell.me.name}
        products={Object.fromEntries(shell.products.map((x) => [x.key, x.name]))}
      />
    )
  } else if (p.tab === 'scoring') {
    const s = await loadScoring()
    const model = s.models.find((m) => m.id === p.model) ?? s.models[0] ?? null
    const records = model ? await loadPreviewRecords(model) : []
    const record = records.find((r) => r.id === p.record)?.id ?? records[0]?.id ?? null
    const preview = model && record ? await previewScore(model.id, record) : null
    body = (
      <ScoringView
        key={model?.id ?? 'none'}
        models={s.models}
        limit={s.limit}
        model={model}
        records={records}
        record={record}
        preview={preview && preview.ok ? preview.data : null}
        pipelines={s.pipelines.map((x) => ({ id: x.id, name: x.name }))}
        labels={s.labels.map((x) => ({ id: x.id, name: x.name }))}
        canConfigure={can(shell, 'deals', 'configure')}
        nf={nf}
      />
    )
  } else {
    const e = await loadEnrichment()
    body = <EnrichView data={e} canBulk={can(shell, 'deals', 'bulk')} canAdd={can(shell, 'deals', 'add')} nf={nf} now={new Date().toISOString()} />
  }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <ScreenTabs tab={p.tab} />
      {body}
    </div>
  )
}
