import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { durationParts, funnelFix, type FixRule } from '@/lib/growth/calc'
import { growthHref, type LogFilter, type Scope } from '@/lib/growth/scope'
import type { GrowthFunnel } from '@/lib/growth/types'
import { Bar, card, channelColor, label11 } from './v2kit'
import { SignupLog } from './SignupLog'

const STEP_COLS = '[grid-template-columns:22px_minmax(0,1.4fr)_minmax(0,1.6fr)_60px_52px]'
const DEVICE_COLOR: Record<string, string> = { desktop: '#9DB8B3', mobile: '#E38258', tablet: '#B5DAD4' }

/**
 * Growth › Signup funnel and log (SimpleGrowth.dc.html, v.funnel) on growth_funnel. Steps 1–4 are the website's (visitors
 * who reached them), 5–8 the products' (accounts created in the scope and how far they got); the two are never joined
 * person by person (D-37). The step card explains one transition with real exits and form errors.
 */
export async function FunnelTab({ d, scope, scopeLabel, lf, nf }: { d: GrowthFunnel; scope: Scope; scopeLabel: string; lf: LogFilter; nf: NumberFormat }) {
  const t = await getTranslations('simpleGrowth.funnel')
  const tc = await getTranslations('simpleGrowth.channels')
  const ts = await getTranslations('simpleGrowth.scope')
  const s = d.step
  const steps = d.steps
  const top = Math.max(1, steps[0]?.count ?? 0)
  const name = (k: number) => t(`steps.${k}`)
  const cur = steps[s - 1]
  const next = steps[s]
  const continued = cur?.count && next?.count !== null && next?.count !== undefined ? Math.min(1, next.count / cur.count) : null
  const prevRate = cur?.prev && next?.prev !== null && next?.prev !== undefined ? Math.min(1, next.prev / cur.prev) : null
  const lost = cur?.count !== null && cur?.count !== undefined && next?.count !== null && next?.count !== undefined ? Math.max(0, cur.count - next.count) : null
  const segName = (kind: string, key: string) => (kind === 'device' ? ts(`devices.${key}`) : tc.has(key) ? tc(key) : key)
  const segRows = d.segments.filter((x) => x.entered > 0)
  const chan = segRows.filter((x) => x.kind === 'channel').slice(0, 5)
  const dev = segRows.filter((x) => x.kind === 'device')
  const overall = continued
  const stoppedBase = Math.max(1, d.stopped ?? 0)
  const fix = funnelFix(d.segments, d.reasons, d.stopped)
  const median = d.median_seconds === null ? '—' : (() => {
    const p = durationParts(d.median_seconds)
    return p.unit === 'min' && p.rest ? t('time.minSec', { m: p.value, s: p.rest }) : t(`time.${p.unit}`, { v: formatNumber(p.value, nf, p.unit === 'h' || p.unit === 'd' ? 1 : 0) })
  })()
  const pts = continued !== null && prevRate !== null ? Math.round((continued - prevRate) * 100) : null

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,560px),1fr))]">
        <div className={`${card} px-5 py-4`}>
          <div className="mb-3 flex items-baseline justify-between gap-3">
            <b className="text-15">{t('title', { scope: scopeLabel })}</b>
            <span className="text-12 text-muted">{t('hint')}</span>
          </div>
          <div className="flex flex-col gap-[6px]">
            {steps.map((f, i) => {
              const prev = i > 0 ? steps[i - 1]!.count : null
              const drop = i > 0 && f.count !== null && prev ? 1 - f.count / prev : null
              const on = i + 1 === s
              const color = i === 7 ? '#F5C64A' : i >= 4 ? '#CFE7E4' : '#CFE0F5'
              const w = f.count === null ? 0 : Math.max(1.5, (f.count / top) * 100)
              const pickable = i < 7
              const row = (
                <>
                  <span className="flex h-5 w-5 items-center justify-center rounded-999 bg-ink text-10.5 font-bold text-highlight">{i + 1}</span>
                  <span className="font-semibold leading-[1.25]">{name(i + 1)}</span>
                  <Bar w={w} color={color} h={20} round="rounded-6" />
                  <b className="text-right tabular-nums">{f.count === null ? '—' : formatNumber(f.count, nf)}</b>
                  <span className={`text-right text-11.5 font-bold ${drop !== null && drop > 0.5 && i > 2 ? 'text-danger' : 'text-warn-ink'}`}>
                    {drop !== null && i !== 4 ? `−${percent(Math.round(Math.max(0, drop) * 100), nf)}` : ''}
                  </span>
                </>
              )
              const cls = `grid items-center gap-[10px] rounded-11 border px-2 py-[7px] text-left text-12.5 text-ink ${STEP_COLS} ${on ? 'border-ink bg-highlight' : 'border-transparent bg-transparent'}`
              return pickable
                ? <Link key={i} href={growthHref('funnel', scope, { step: i + 1, lf }) as Route} aria-current={on ? 'true' : undefined} className={`${cls} cursor-pointer hover:text-ink hover:no-underline`}>{row}</Link>
                : <div key={i} className={cls}>{row}</div>
            })}
          </div>
          <div className="mt-3 text-11.5 text-faint">{t('note')}</div>
        </div>

        <div className="flex flex-col gap-3 rounded-20 border border-ink bg-surface px-5 py-4">
          <div className="flex items-start justify-between gap-[10px]">
            <div>
              <div className={label11}>{t('card.step', { from: s, to: s + 1 })}</div>
              <div className="mt-[3px] font-serif text-20 font-semibold leading-[1.2]">{name(s)} → {name(s + 1).toLocaleLowerCase()}</div>
            </div>
            <div className="text-right">
              <div className="font-serif text-26 font-semibold text-danger">{lost === null ? '—' : formatNumber(lost, nf)}</div>
              <div className="text-11.5 text-muted">{t('card.stopped')}</div>
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {[
              { k: t('card.continued'), v: continued === null ? '—' : percent(continued * 100, nf) },
              { k: t('card.median'), v: median },
              { k: t('card.vsLast'), v: pts === null ? '—' : t('card.pts', { n: (pts >= 0 ? '+' : '−') + Math.abs(pts) }) },
            ].map((f) => (
              <div key={f.k} className="rounded-12 border border-line bg-canvas px-[10px] py-2">
                <div className="text-10 font-bold uppercase tracking-[.08em] text-muted">{f.k}</div>
                <b className="text-13.5">{f.v}</b>
              </div>
            ))}
          </div>
          <div className={label11}>{t('card.why')}</div>
          {d.reasons.length ? d.reasons.map((r) => (
            <div key={`${r.kind}${r.value}`} className="grid items-center gap-2 text-12.5 [grid-template-columns:minmax(0,1fr)_100px_40px]">
              <span className="[overflow-wrap:anywhere]">{r.kind === 'exit' ? t('card.leftOn', { path: r.value }) : t('card.error', { code: r.value })}</span>
              <Bar w={(r.count / stoppedBase) * 100} color="#D4633A" />
              <b className="text-right">{formatNumber(r.count, nf)}</b>
            </div>
          )) : <span className="text-12.5 text-muted">{s >= 5 ? t('card.noReasonsProduct') : t('card.noReasons')}</span>}
          <div className={label11}>{t('card.segments')}</div>
          {[...chan, ...dev].length ? [...chan, ...dev].map((r) => {
            const rr = r.continued / r.entered
            return (
              <div key={`${r.kind}${r.key}`} className="grid items-center gap-2 text-12.5 [grid-template-columns:110px_minmax(0,1fr)_46px]">
                <span className="overflow-hidden text-ellipsis whitespace-nowrap">{segName(r.kind, r.key)}</span>
                <Bar w={rr * 100} color={r.kind === 'device' ? DEVICE_COLOR[r.key] ?? '#C4BCA8' : channelColor(r.key)} />
                <b className={`text-right ${overall !== null && rr < overall * 0.8 ? 'text-danger' : 'text-ink'}`}>{percent(rr * 100, nf)}</b>
              </div>
            )
          }) : <span className="text-12.5 text-muted">{t('card.noSegments')}</span>}
          {fix ? (
            <div className="rounded-13 bg-highlight px-3 py-[10px] text-12.5 leading-[1.5]"><b>{t('card.fix')}</b> {fixText(fix, t, ts, tc, nf)}</div>
          ) : null}
        </div>
      </div>

      <SignupLog rows={d.log} total={d.log_total} step={s} filter={lf} scope={scope} scopeLabel={scopeLabel} />
    </div>
  )
}

type T = Awaited<ReturnType<typeof getTranslations<'simpleGrowth.funnel'>>>
type TS = Awaited<ReturnType<typeof getTranslations<'simpleGrowth.scope'>>>
type TC = Awaited<ReturnType<typeof getTranslations<'simpleGrowth.channels'>>>
function fixText(f: FixRule, t: T, ts: TS, tc: TC, nf: NumberFormat): string {
  const pc = (x: number) => percent(x * 100, nf)
  switch (f.kind) {
    case 'device': return t('fixes.device', { device: ts(`devices.${f.key}`), rate: pc(f.rate), other: ts(`devices.${f.other}`).toLocaleLowerCase(), otherRate: pc(f.otherRate) })
    case 'error': return t('fixes.error', { code: f.value, count: f.count })
    case 'exit': return t('fixes.exit', { path: f.value, share: pc(f.share) })
    case 'channel': return t('fixes.channel', { channel: tc.has(f.key) ? tc(f.key) : f.key, rate: pc(f.rate), overall: pc(f.overall) })
  }
}
