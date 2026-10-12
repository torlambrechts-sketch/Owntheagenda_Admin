import Link from 'next/link'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { loadAiStatus } from '@/lib/ai/run'
import {
  loadArticle, loadAssist, loadChannels, loadHelpCentre, loadPortal, loadResults, loadStatus, loadWidget,
} from '@/lib/data/support-hub'
import type { NumberFormat } from '@/lib/format'
import { SUBS, type Sub } from './logic'
import { Refused } from './bits'
import { ResultsView } from './Results'
import { WidgetView } from './Widget'
import { CentreView } from './Centre'
import { ChannelsView } from './Channels'
import { PortalView } from './Portal'
import { AssistView } from './Assist'
import { StatusView } from './Status'

/**
 * Customers › Help centre and support (SupportHub.dc.html): the seven sub-tabs. The design's buttons switch a state; here
 * they are links to `?tab=support&sub=` so each view has an address (control substitution, D-06). Only the open view's
 * data is read.
 */
export async function SupportHub({ product, productName, sub, article, org, ticket, nf }: {
  product: string
  productName: string
  sub: Sub
  article: string | null
  org: string | null
  ticket: string | null
  nf: NumberFormat
}) {
  const t = await getTranslations('supportHub')
  return (
    <div className="flex flex-col gap-[14px] text-14 text-ink">
      <nav className="flex flex-wrap gap-1 self-start rounded-13 bg-tile p-1" aria-label={t('subsLabel')}>
        {SUBS.map((k) => (
          <Link
            key={k}
            href={`/customers?tab=support&sub=${k}` as never}
            aria-current={k === sub ? 'page' : undefined}
            className={`whitespace-nowrap rounded-9 px-3 py-[7px] text-12.5 text-ink hover:text-ink hover:no-underline ${k === sub ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
          >
            {t(`subs.${k}`)}
          </Link>
        ))}
      </nav>
      <SubView product={product} productName={productName} sub={sub} article={article} org={org} ticket={ticket} nf={nf} />
    </div>
  )
}

async function SubView({ product, productName, sub, article, org, ticket, nf }: Parameters<typeof SupportHub>[0]) {
  const now = await getNow()
  const format = await getFormatter()
  switch (sub) {
    case 'metrics': {
      const r = await loadResults(product)
      return r.ok ? <ResultsView data={r.data} product={product} nf={nf} /> : <Refused code={r.code} />
    }
    case 'widget': {
      const [r, ai] = await Promise.all([loadWidget(product), loadAiStatus()])
      return r.ok ? <WidgetView data={r.data} product={product} productName={productName} aiConnected={ai?.connected ?? false} /> : <Refused code={r.code} />
    }
    case 'center': {
      const r = await loadHelpCentre(product)
      if (!r.ok) return <Refused code={r.code} />
      const chosen = article ?? r.data.articles[0]?.id ?? null
      const a = chosen ? await loadArticle(chosen) : null
      const editing = a && a.product === product ? a : null
      return (
        <CentreView
          data={r.data}
          article={editing}
          product={product}
          productName={productName}
          reviewed={editing?.reviewed_at ? format.relativeTime(new Date(editing.reviewed_at), now) : null}
          nf={nf}
        />
      )
    }
    case 'channels': {
      const r = await loadChannels(product)
      return r.ok ? <ChannelsView data={r.data} productName={productName} nf={nf} /> : <Refused code={r.code} />
    }
    case 'portal': {
      const r = await loadPortal(product, org)
      return r.ok ? <PortalView data={r.data} productName={productName} /> : <Refused code={r.code} />
    }
    case 'assist': {
      const [r, ai] = await Promise.all([loadAssist(product, ticket), loadAiStatus()])
      return r.ok ? <AssistView data={r.data} product={product} productName={productName} aiConnected={ai?.connected ?? false} nf={nf} /> : <Refused code={r.code} />
    }
    case 'proactive': {
      const r = await loadStatus(product)
      if (!r.ok) return <Refused code={r.code} />
      const dates = Object.fromEntries(r.data.changelog.map((c) => [c.id, format.dateTime(new Date(c.published_at), { day: 'numeric', month: 'short' })]))
      const times = Object.fromEntries(r.data.incidents.flatMap((i) => i.updates.map((u) => [`${i.id}:${u.at}`, format.dateTime(new Date(u.at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })])))
      return <StatusView data={r.data} product={product} dates={dates} times={times} />
    }
  }
}
