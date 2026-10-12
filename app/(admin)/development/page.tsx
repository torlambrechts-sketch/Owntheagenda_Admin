import Link from 'next/link'
import type { Route } from 'next'
import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { currentProduct } from '@/lib/product'
import { DEV_TABS, type DevTab, type DevTabProps } from '@/lib/data/dev-tabs'
import { openBugCount } from '@/lib/data/dev-badge'
import { RoadmapView } from './_components/Roadmap'
import { BoardView } from './_components/Board'
import { BugsView } from './_components/Bugs'
import { ReleasesView } from './_components/Releases'
import { IntegrationsView } from './_components/Integrations'
import { CodeView } from './_components/Code'
import { MetricsView } from './_components/Metrics'
import { SpecsView } from './_components/Specs'
import { MarkdownView } from './_components/Markdown'
import { JobsView } from './_components/Jobs'
import { EnvView } from './_components/Env'
import { GateView } from './_components/Gate'
import { RepoView } from './_components/Repo'

const VIEW: Record<DevTab, (p: DevTabProps) => Promise<React.ReactNode>> = {
  roadmap: RoadmapView, board: BoardView, bugs: BugsView, releases: ReleasesView, integrations: IntegrationsView, code: CodeView,
  metrics: MetricsView, specs: SpecsView, md: MarkdownView, jobs: JobsView, env: EnvView, gate: GateView, repo: RepoView,
}
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development (DevHub.dc.html, the fifth section of Sentral Simple.dc.html): thirteen views under one pill bar. The
 * design's pill buttons become links, so a view has an address (control substitution, D-06). Opened by Development › See
 * (0078); every view reads the application chosen in the rail.
 */
export default async function DevelopmentPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const tab = z.enum(DEV_TABS).catch('roadmap').parse(one(sp.tab) ?? 'roadmap')
  const shell = await getShell()
  const t = await getTranslations('simpleDev')

  if (!can(shell, 'dev', 'see')) {
    return (
      <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <b className="font-serif text-20 font-semibold">{t('noAccess.title')}</b>
          <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
        </div>
      </div>
    )
  }

  const product = await currentProduct(shell)
  const [bugs, body] = await Promise.all([openBugCount(product), VIEW[tab]({ product, nf: shell.me.number_format, searchParams: sp })])

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <nav aria-label={t('tabsLabel')} className="flex flex-wrap gap-[6px]">
        {DEV_TABS.map((k) => {
          const on = k === tab
          const badge = k === 'bugs' && bugs ? bugs : null
          return (
            <Link
              key={k}
              href={(k === 'roadmap' ? '/development' : `/development?tab=${k}`) as Route}
              aria-current={on ? 'page' : undefined}
              className={`flex flex-none cursor-pointer items-center gap-[6px] whitespace-nowrap rounded-999 border px-[14px] py-2 text-13 hover:no-underline ${
                on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'
              }`}
            >
              {t(`tabs.${k}`)}
              {badge ? (
                <span aria-label={t('openBugs', { n: badge })}
                  className="flex h-[18px] min-w-[18px] items-center justify-center rounded-999 bg-alert px-[5px] text-10.5 font-bold text-surface">
                  {badge}
                </span>
              ) : null}
            </Link>
          )
        })}
      </nav>
      {body}
    </div>
  )
}
