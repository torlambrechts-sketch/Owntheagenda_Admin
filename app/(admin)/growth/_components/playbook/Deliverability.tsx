import { getTranslations } from 'next-intl/server'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { SenderDomain } from '@/lib/data/campaigns-shared'
import type { Deliverability } from '@/lib/growth/playbook'
import { Tile, card, cardTable, head } from '../v2kit'

const REASONS = ['unsubscribed', 'hard_bounce', 'complaint', 'soft_bounces', 'manual', 'erasure'] as const
const SIGNALS = ['engaged', 'replied', 'unsubscribed', 'hard_bounce', 'complaint'] as const
/** a mailbox provider's complaint limit (Google's and Yahoo's bulk-sender rule, the design's «Limit 0,3 %») */
const COMPLAINT_LIMIT = 0.003

/**
 * Email and automation › Deliverability and frequency (GrowthPlaybook.dc.html, v.deliver) on growth_deliverability (0076)
 * and sender_domains_get (0037): 30 days of sends, bounces, complaints and unsubscribes, each sender domain's SPF, DKIM and
 * DMARC, the suppression list, and what the engine does with email engagement this month. Inbox placement and domain
 * reputation need seed tests or Google Postmaster; the engine has no frequency cap, quiet hours or priority between flows,
 * and the view says so instead of offering settings that would change nothing (V-GR2-41).
 */
export async function DeliverabilityView({ d, domains, nf }: { d: Deliverability; domains: SenderDomain[] | null; nf: NumberFormat }) {
  const t = await getTranslations('simpleGrowth.playbook.deliver')
  const tr = await getTranslations('campaigns.suppressions.reason')
  const dash = '—'
  const s = d.sends
  const share = (n: number) => (s.sent ? n / s.sent : null)
  const pc = (v: number | null) => (v === null ? dash : percent(v * 100, nf))
  const complaints = share(s.complained)
  const auth = domains ? domains.filter((x) => x.authenticated).length : null
  const missing = domains?.find((x) => !x.authenticated) ?? null
  const gaps = (x: SenderDomain) => [x.spf_ok ? null : 'SPF', x.dkim_ok ? null : 'DKIM', x.dmarc_policy ? null : 'DMARC'].filter(Boolean).join(', ')
  const check = (ok: boolean | null, name: string) => (
    <span className={`whitespace-nowrap ${ok ? 'text-link' : ok === false ? 'text-danger' : 'text-muted'}`}>{ok ? '✓' : ok === false ? '✕' : '?'} {name}</span>
  )

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(150px,1fr))]">
        <Tile size={23} label={t('kpi.sent')} value={formatNumber(s.sent, nf)} note={s.sent ? t('kpi.sentNote', { n: formatNumber(s.delivered, nf) }) : t('kpi.none')} />
        <Tile size={23} label={t('kpi.bounce')} value={pc(share(s.bounced))} note={s.sent ? t('kpi.bounceNote', { n: formatNumber(s.hard, nf) }) : t('kpi.none')} />
        <Tile size={23} label={t('kpi.complaints')} value={pc(complaints)} tone={complaints === null ? 'text-ink' : complaints < COMPLAINT_LIMIT ? 'text-link' : 'text-danger'}
          note={t('kpi.complaintsNote', { limit: percent(COMPLAINT_LIMIT * 100, nf) })} />
        <Tile size={23} label={t('kpi.unsub')} value={pc(share(s.unsubscribed))} note={s.sent ? t('kpi.unsubNote', { n: formatNumber(s.unsubscribed, nf) }) : t('kpi.none')} />
        <Tile size={23} label={t('kpi.auth')} value={domains && domains.length ? `${auth} / ${domains.length}` : dash}
          tone={domains && domains.length && auth === domains.length ? 'text-link' : 'text-ink'}
          note={!domains ? t('kpi.authUnknown') : !domains.length ? t('kpi.authNone') : missing ? (missing.last_checked_at ? t('kpi.authMissing', { domain: missing.domain, what: gaps(missing) || 'DNS' }) : t('kpi.authUnchecked', { domain: missing.domain })) : t('kpi.authAll')} />
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('domains')}</b>
            <span className="text-12 text-muted">{t('domainsNote')}</span>
          </div>
          {!domains || !domains.length ? <p className="m-0 border-b border-line px-[18px] py-[12px] text-12.5 text-muted">{domains ? t('noDomains') : t('domainsUnknown')}</p> : null}
          {(domains ?? []).map((x) => (
            <div key={x.id} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1fr)_auto_60px]">
              <span className="flex min-w-0 flex-col">
                <b className="truncate">{x.domain}</b>
                <span className="text-11 text-muted">{t(`streams.${x.stream}`)}{x.warmup && !x.warmup.done ? ` · ${t('warmup', { day: x.warmup.day, days: x.warmup.days })}` : ''}</span>
              </span>
              <span className="flex gap-2 text-11.5 font-bold">{check(x.spf_ok, 'SPF')}{check(x.dkim_ok, 'DKIM')}{check(x.dmarc_policy ? true : x.last_checked_at ? false : null, 'DMARC')}</span>
              <b className="text-right" title={t('bounceTitle')}>{x.rates?.bounce_rate != null ? percent(x.rates.bounce_rate, nf) : dash}</b>
            </div>
          ))}
          <p className="m-0 px-[18px] py-[10px] text-11.5 text-muted">{t('placementNone')}</p>
        </section>

        <section className={`${card} flex flex-col gap-[10px] px-[18px] py-4`}>
          <b className="text-15">{t('suppression')}</b>
          <span className="text-11 font-bold uppercase tracking-[.1em] text-muted">{t('suppressionNote')}</span>
          {REASONS.map((r) => (
            <div key={r} className="flex items-center gap-2 rounded-10 border border-line bg-canvas px-[10px] py-[7px] text-12.5">
              <span className="flex-1">{tr(r)}</span>
              <b>{formatNumber(d.suppressions[r] ?? 0, nf)}</b>
            </div>
          ))}
          <span className="text-12 leading-[1.5] text-muted">{t('noCap')}</span>
        </section>
      </div>

      <section className={cardTable}>
        <div className={head}>
          <b className="text-15">{t('signals')}</b>
          <span className="text-12 text-muted">{t('signalsNote')}</span>
        </div>
        {SIGNALS.map((k) => (
          <div key={k} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 last:border-b-0 [grid-template-columns:minmax(0,1.4fr)_minmax(0,1.2fr)_120px]">
            <b>{t(`signal.${k}.n`)}</b>
            <span className="text-muted">{t(`signal.${k}.then`)}</span>
            <span className="font-bold text-link">{t('thisMonth', { n: d.signals[k] })}</span>
          </div>
        ))}
      </section>
    </div>
  )
}
