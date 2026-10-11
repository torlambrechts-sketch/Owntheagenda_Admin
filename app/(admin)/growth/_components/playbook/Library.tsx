import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { Flows } from '@/lib/growth/playbook'
import { emptyLine, card } from '../v2kit'
import { FlowToggle } from './controls'

type State = 'live' | 'paused' | 'draft'
/** the state pill (library[].state: Live teal, Draft yellow, off the tile) */
const PILL: Record<State, string> = { live: 'bg-ok-bg text-ok-ink', draft: 'bg-highlight text-amber-ink', paused: 'bg-tile text-muted' }
const BLOCKER_KEYS = ['not_connected:email', 'campaign_inactive', 'sender_domain_unverified', 'limit']

/**
 * Email and automation › Flow library (GrowthPlaybook.dc.html, v.library) on growth_flows (0076): every sequence,
 * lifecycle flow and workflow that writes to people, with its state, its steps and 90 days of what it sent. Lift, MRR and a
 * health grade need a control group and revenue per flow the engine does not keep (V-GR2-40). Activate and Pause are the
 * engine's own switch (workflow_set_state): its rights and blockers decide.
 */
export async function LibraryView({ d, nf, canEdit }: { d: Flows; nf: NumberFormat; canEdit: boolean }) {
  const t = await getTranslations('simpleGrowth.playbook.library')
  const tb = await getTranslations('simpleGrowth.email.blockers')
  if (!d.length) return <div className={`${card} ${emptyLine}`}>{t('empty')}</div>
  const rate = (n: number, of: number) => (of ? percent((n / of) * 100, nf) : '—')
  const blocker = (b: string | undefined) => (b ? tb(BLOCKER_KEYS.includes(b) ? b : 'other') : null)
  return (
    <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
      {d.map((f) => {
        const state: State = f.state === 'active' ? 'live' : f.activated ? 'paused' : 'draft'
        const live = state === 'live'
        const what = f.description || (t.has(`types.${f.trigger_type}`) ? t(`types.${f.trigger_type}`) : '')
        const unsub = f.mail.sent ? f.mail.unsubscribed / f.mail.sent : 0
        return (
          <article key={f.id} className={`flex flex-col gap-[7px] rounded-18 border bg-surface px-4 py-[14px] ${live ? 'border-line' : 'border-line-strong'}`}>
            <div className="flex items-start justify-between gap-2">
              <b className="text-13.5 leading-[1.3] [overflow-wrap:anywhere]">{f.name}</b>
              <span className={`whitespace-nowrap rounded-999 px-[9px] py-[2px] text-11 font-bold ${PILL[state]}`}>{t(`states.${state}`)}</span>
            </div>
            <span className="text-12 leading-[1.45] text-muted [overflow-wrap:anywhere]">{what}</span>
            {f.mail.sent ? (
              <div className="grid grid-cols-3 gap-[6px]">
                {[
                  { k: t('stats.sent'), v: formatNumber(f.mail.sent, nf), c: '' },
                  { k: t('stats.opened'), v: rate(f.mail.opened, f.mail.sent), c: '' },
                  { k: t('stats.unsub'), v: rate(f.mail.unsubscribed, f.mail.sent), c: unsub > 0.01 ? 'text-danger' : '' },
                ].map((s) => (
                  <div key={s.k} className="rounded-10 bg-canvas px-2 py-[6px]">
                    <div className="text-9.5 font-bold uppercase tracking-[.08em] text-muted">{s.k}</div>
                    <b className={`text-12.5 ${s.c}`}>{s.v}</b>
                  </div>
                ))}
              </div>
            ) : null}
            <div className="mt-auto flex items-center justify-between gap-2">
              <span className="text-11.5 text-muted">
                {t('steps', { n: f.steps })} · {t.has(`kinds.${f.kind}`) ? t(`kinds.${f.kind}`) : f.kind}
                {f.in_flow ? ` · ${t('inFlow', { n: formatNumber(f.in_flow, nf) })}` : ''}
              </span>
              <FlowToggle id={f.id} name={f.name} live={live} blocked={blocker(f.blockers[0])} canEdit={canEdit} />
            </div>
          </article>
        )
      })}
    </div>
  )
}
