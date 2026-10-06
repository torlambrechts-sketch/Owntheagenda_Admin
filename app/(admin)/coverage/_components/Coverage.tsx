'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { COVERAGE, GAP_STATUS, type CoverageFeature, type GapStatus } from '@/lib/data/coverage-data'
import { ROUTES, type RouteKey } from '@/lib/nav'

type Tab = 'features' | 'flows' | 'baseline'

// where a feature lives (the design's routeOf)
const routeOf = (f: CoverageFeature): string =>
  f.m === 'LGN' ? 'leadgen' : f.m === 'WEB' ? 'visitors' : f.m === 'CMP' ? 'campaigns' : f.m === 'LEA' && f.id !== 'LEA-06' ? 'leads' : f.r === 'assistant' ? 'home' : f.r === 'marketing' ? 'campaigns' : f.r
const hrefOf = (r: string) => (r in ROUTES ? ROUTES[r as RouteKey].path : '/')

const BASELINE: [key: string, route: RouteKey][] = [
  ['orgs', 'customers'], ['users', 'customers'], ['billing', 'customers'], ['analytics', 'analytics'], ['web', 'analytics'], ['tickets', 'tickets'], ['platform', 'apps'],
]

const STATUS_TONE: Record<GapStatus, string> = {
  implemented: 'bg-ok-bg text-ok-ink',
  partial: 'bg-amber-bg text-amber-ink',
  conflict: 'bg-peach text-rust-ink',
  missing: 'bg-beige text-muted',
  unknown: 'bg-beige text-muted',
}

/** The coverage screen: stats, the three views, module chips, search, expandable features. */
export function Coverage({ settingsCount }: { settingsCount: number }) {
  const t = useTranslations('coverage')
  const [tab, setTab] = useState<Tab>('features')
  const [mod, setMod] = useState('All')
  const [q, setQ] = useState('')
  const [open, setOpen] = useState<Record<string, boolean>>({})
  const C = COVERAGE
  const where = (r: string) => (t.has(`where.${r}`) ? t(`where.${r}`) : r)

  const uf = C.flows.filter((f) => f.id.startsWith('UF')).length
  const sf = C.flows.filter((f) => f.id.startsWith('SF')).length
  const stats: [string, number, string][] = [
    [t('stats.features'), C.feats.length, t('stats.featuresSub')],
    [t('stats.modules'), Object.keys(C.mods).length, t('stats.modulesSub')],
    [t('stats.userFlows'), uf, t('stats.range', { prefix: 'UF', last: String(uf).padStart(2, '0') })],
    [t('stats.systemFlows'), sf, t('stats.range', { prefix: 'SF', last: String(sf).padStart(2, '0') })],
    [t('stats.settings'), settingsCount, t('stats.settingsSub')],
  ]
  const counts = useMemo(() => {
    const c: Record<string, number> = {}
    for (const f of C.feats) c[f.m] = (c[f.m] ?? 0) + 1
    return c
  }, [C.feats])
  const needle = q.toLowerCase()
  const feats = C.feats.filter((f) => (mod === 'All' || f.m === mod) && (!needle || `${f.id} ${f.n} ${f.d ?? ''}`.toLowerCase().includes(needle)))
  const flows = C.flows.filter((f) => !needle || `${f.id} ${f.n} ${f.h ?? ''}`.toLowerCase().includes(needle))
  const chip = (on: boolean) => `cursor-pointer rounded-999 border px-[10px] py-[5px] text-11.5 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
  const openBtn = 'inline-flex h-[30px] items-center whitespace-nowrap rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold text-ink hover:text-ink hover:no-underline'

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="max-w-[860px]">
        <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('eyebrow')}</div>
        <h1 className="m-0 mt-[6px] font-serif text-24 font-semibold leading-[1.2]">{t('title')}</h1>
        <div className="mt-[6px] text-12 text-muted">{t('statusNote')}</div>
      </div>
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(160px,1fr))]">
        {stats.map(([n, v, s]) => (
          <div key={n} className="rounded-18 border border-line bg-surface px-4 py-[14px]">
            <div className="text-10.5 font-bold uppercase tracking-label text-muted">{n}</div>
            <div className="mt-[6px] font-serif text-28 font-semibold">{v}</div>
            <div className="text-11.5 text-muted">{s}</div>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex rounded-11 bg-tile p-[3px]" role="tablist" aria-label={t('tabs.label')}>
          {(['features', 'flows', 'baseline'] as const).map((k) => (
            <button
              key={k}
              type="button"
              role="tab"
              aria-selected={tab === k}
              onClick={() => setTab(k)}
              className={`cursor-pointer rounded-8 border-none px-[13px] py-[7px] text-12.5 text-ink ${tab === k ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}
            >
              {t(`tabs.${k}`)}
            </button>
          ))}
        </div>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('search')}
          aria-label={t('search')}
          className="h-9 min-w-0 flex-[1_1_240px] rounded-10 border border-line bg-surface px-3 text-13 text-ink"
        />
      </div>

      {tab === 'features' ? (
        <div className="flex flex-col gap-[10px]">
          <div className="flex flex-wrap gap-[5px]">
            {[['All', t('allModules'), C.feats.length] as const, ...Object.entries(C.mods).map(([k, n]) => [k, n, counts[k] ?? 0] as const)].map(([k, n, c]) => (
              <button key={k} type="button" aria-pressed={mod === k} onClick={() => setMod(k)} className={chip(mod === k)}>
                {n} <span className="text-muted">{c}</span>
              </button>
            ))}
          </div>
          <div className="overflow-hidden rounded-20 border border-line bg-surface">
            {feats.map((f) => {
              const r = routeOf(f)
              const ex = !!open[f.id]
              const status = GAP_STATUS[f.id]
              const toggle = () => setOpen({ ...open, [f.id]: !ex })
              return (
                <div key={f.id} className="border-b border-line">
                  <div className="grid items-start gap-3 px-4 py-[11px] [grid-template-columns:82px_minmax(0,1fr)] md:[grid-template-columns:82px_minmax(0,1fr)_150px]">
                    <button
                      type="button"
                      aria-expanded={ex}
                      aria-label={t('expand', { id: f.id })}
                      onClick={toggle}
                      className="cursor-pointer rounded-6 border-none bg-ink px-2 py-[3px] text-11 font-bold text-highlight [font-family:ui-monospace,Menlo,monospace]"
                    >
                      {f.id}
                    </button>
                    <button type="button" aria-expanded={ex} onClick={toggle} className="flex min-w-0 cursor-pointer flex-col gap-[3px] border-none bg-transparent p-0 text-left text-ink">
                      <span className="flex flex-wrap items-center gap-[6px]">
                        <b className="text-13">{f.n}</b>
                        {status ? <span className={`rounded-999 px-[7px] text-10.5 font-bold leading-[16px] ${STATUS_TONE[status]}`}>{t(`status.${status}`)}</span> : null}
                      </span>
                      <span className={`w-full overflow-hidden text-ellipsis text-12 leading-[1.45] text-muted ${ex ? 'whitespace-normal' : 'whitespace-nowrap'}`}>{f.d ?? ''}</span>
                    </button>
                    <Link href={hrefOf(r) as never} className={`${openBtn} justify-self-start max-md:col-start-2 md:justify-self-end`}>
                      {t('open', { where: where(r) })}
                    </Link>
                  </div>
                  {ex ? (
                    <div className="grid gap-[10px] px-4 pb-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))] md:pl-[110px]">
                      <div className="rounded-12 border border-line bg-canvas px-3 py-[10px] text-12 leading-[1.5]">
                        <b className="text-10.5 uppercase tracking-label text-muted">{t('rules')}</b>
                        <div>{f.ru || '—'}</div>
                      </div>
                      <div className="rounded-12 bg-ok-bg px-3 py-[10px] text-12 leading-[1.5] text-ok-ink">
                        <b className="text-10.5 uppercase tracking-label">{t('acceptance')}</b>
                        <div>{f.a || '—'}</div>
                      </div>
                    </div>
                  ) : null}
                </div>
              )
            })}
            {feats.length === 0 ? <div className="px-4 py-6 text-center text-13 text-muted">{t('empty', { q })}</div> : null}
          </div>
        </div>
      ) : null}

      {tab === 'flows' ? (
        <div className="grid items-start gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
          {flows.map((f) => {
            const user = f.id.startsWith('UF')
            return (
              <div key={f.id} className="flex flex-col gap-[7px] rounded-18 border border-line bg-surface px-4 py-[14px]">
                <div className="flex items-center gap-2">
                  <span className={`rounded-6 px-2 py-[3px] text-11 font-bold [font-family:ui-monospace,Menlo,monospace] ${user ? 'bg-highlight text-amber-ink' : 'bg-teal-soft text-ok-ink'}`}>{f.id}</span>
                  <b className="text-13.5">{f.n}</b>
                </div>
                <span className="text-11.5 leading-[1.45] text-muted">{f.h ?? ''}</span>
                {f.s.map((s, i) => (
                  <div key={i} className="grid gap-[6px] text-12 leading-[1.45] [grid-template-columns:18px_minmax(0,1fr)]">
                    <b className="text-faint">{i + 1}</b>
                    <span>{s}</span>
                  </div>
                ))}
              </div>
            )
          })}
          {flows.length === 0 ? <div className="px-4 py-6 text-center text-13 text-muted">{t('empty', { q })}</div> : null}
        </div>
      ) : null}

      {tab === 'baseline' ? (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr))]">
          {BASELINE.map(([key, r]) => (
            <div key={key} className="flex flex-col gap-[7px] rounded-18 border border-line bg-surface px-4 py-[14px]">
              <b className="text-14">{t(`baseline.${key}.n`)}</b>
              {(t.raw(`baseline.${key}.items`) as string[]).map((i) => (
                <span key={i} className="text-12 leading-[1.45]">✓ {i}</span>
              ))}
              <Link href={ROUTES[r].path as never} className={`${openBtn} self-start`}>
                {t('open', { where: where(r) })}
              </Link>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  )
}
