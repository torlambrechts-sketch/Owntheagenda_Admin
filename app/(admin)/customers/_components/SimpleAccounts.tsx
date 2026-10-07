'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { ACCOUNT_FILTERS, type AccountFilter } from '@/lib/data/simple-customers-shared'
import { runCustomerAction } from '../actions'
import { statusTone } from './tones'
import { useErrorText } from './useErrorText'

export type Kpi = { key: string; label: string; value: string; sub: string }
export type AccountRow = {
  id: string
  name: string
  orgnr: string
  digits: string
  employees: number | null
  status: string | null
  statusLabel: string
  plan: string
  mrr: string
  href: string
}
export type ActionKey = 'trial' | 'plan' | 'login' | 'suspend' | 'reactivate'
export type AccountPanel =
  | { ok: false; code: string }
  | {
      ok: true
      id: string
      name: string
      sub: string
      status: string | null
      statusLabel: string
      facts: { key: 'plan' | 'mrr' | 'health'; value: string; tone: string }[]
      contact: { name: string; email: string | null } | null
      actions: { key: ActionKey; why: string | null }[]
      recent: { key: string; text: string; when: string }[]
    }

const eyebrow = 'text-11 font-bold uppercase tracking-[.1em] text-muted'
// the list's columns: the design's four from md; on a phone the plan column goes (the design draws no narrow layout)
const cols = '[grid-template-columns:minmax(0,1fr)_84px_72px] md:[grid-template-columns:minmax(0,1.6fr)_90px_90px_90px]'

/** Customers › Accounts (SimpleCustomers.dc.html, v.accounts): KPI row, search and status filter, the list and one account. */
export function SimpleAccounts({ kpis, rows, selectedId, panel, emptyText }: {
  kpis: Kpi[]
  rows: AccountRow[]
  selectedId: string | null
  panel: AccountPanel | null
  emptyText: string
}) {
  const t = useTranslations('simpleCustomers')
  const [q, setQ] = useState('')
  const [filter, setFilter] = useState<AccountFilter>('all')
  const [clicked, setClicked] = useState<string | null>(null)
  useEffect(() => { setClicked(null) }, [selectedId])
  const sel = clicked ?? selectedId

  // the design filters as one types: the name without spaces, or the org.nr's digits
  const norm = q.toLowerCase().replace(/\s/g, '')
  const shown = rows.filter((r) => (filter === 'all' || r.status === filter)
    && (!norm || r.name.toLowerCase().replace(/\s/g, '').includes(norm) || (/\d/.test(norm) && r.digits.includes(norm.replace(/\D/g, '')))))

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(170px,1fr))]">
        {kpis.map((k) => (
          <div key={k.key} className="rounded-18 border border-line bg-surface px-[18px] py-4">
            <div className={eyebrow}>{k.label}</div>
            <div className="mt-[6px] whitespace-nowrap font-serif text-26 font-semibold">{k.value}</div>
            <div className="text-12 text-muted">{k.sub}</div>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap gap-2">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('search')}
          aria-label={t('search')}
          className="h-[38px] min-w-0 flex-[1_1_260px] rounded-10 border border-line bg-surface px-3 text-13"
        />
        {ACCOUNT_FILTERS.map((f) => {
          const on = filter === f
          return (
            <button
              key={f}
              type="button"
              aria-pressed={on}
              onClick={() => setFilter(f)}
              className={`h-[38px] flex-none cursor-pointer whitespace-nowrap rounded-10 border px-[14px] text-12.5 ${on ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-medium'}`}
            >
              {t(`filters.${f}`)}
            </button>
          )
        })}
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className={`grid gap-[10px] border-b border-line px-4 py-[10px] text-10.5 font-bold uppercase tracking-label text-muted ${cols}`}>
            <span>{t('cols.account')}</span><span>{t('cols.status')}</span><span className="hidden md:inline">{t('cols.plan')}</span><span>{t('cols.mrr')}</span>
          </div>
          {shown.map((o) => (
            <Link
              key={o.id}
              href={o.href as never}
              scroll={false}
              onClick={() => setClicked(o.id)}
              aria-current={sel === o.id ? 'true' : undefined}
              className={`grid w-full items-center gap-[10px] border-b border-line px-4 py-[10px] text-left text-13 text-ink hover:text-ink hover:no-underline ${cols} ${sel === o.id ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="flex min-w-0 flex-col">
                <b className="overflow-hidden text-ellipsis whitespace-nowrap">{o.name}</b>
                <span className="text-11.5 text-muted">{o.employees !== null ? t('row.sub', { orgnr: o.orgnr, n: o.employees }) : o.orgnr}</span>
              </span>
              <span>{o.status ? <span className={`rounded-999 px-[9px] py-[3px] text-11 font-bold ${statusTone(o.status)}`}>{o.statusLabel}</span> : '—'}</span>
              <span className="hidden text-ink-2 md:inline">{o.plan}</span>
              <b className="tabular-nums">{o.mrr}</b>
            </Link>
          ))}
          {shown.length === 0 ? <div className="p-[30px] text-center text-13 text-muted">{rows.length ? t('noMatch') : emptyText}</div> : null}
        </div>
        {panel ? <Panel panel={panel} /> : null}
      </div>
    </div>
  )
}

const ACTION_STYLE: Record<ActionKey, string> = {
  trial: 'border-ink bg-primary text-ink',
  plan: 'border-ink bg-surface text-ink',
  login: 'border-ink bg-surface text-ink',
  suspend: 'border-coral bg-peach text-rust-ink',
  reactivate: 'border-ink bg-surface text-ink',
}

function Panel({ panel }: { panel: AccountPanel }) {
  const t = useTranslations('simpleCustomers')
  const err = useErrorText()
  const flash = useToast()
  const router = useRouter()
  const [busy, setBusy] = useState(false)

  if (!panel.ok) {
    return (
      <div className="sticky top-20 rounded-20 border border-ink bg-surface px-[22px] py-5 text-13 text-muted">
        {t(panel.code === 'forbidden' ? 'detail.forbidden' : 'detail.unavailable')}
      </div>
    )
  }

  const run = async (key: ActionKey) => {
    if (key !== 'trial' || busy) return
    setBusy(true)
    const r = await runCustomerAction({ org: panel.id, action: 'trial', days: 14, reason: t('actions.reason') })
    setBusy(false)
    // a product that does not answer comes back as its HTTP status (runCommand); that is «could not be reached»
    flash(r.ok ? t('actions.done') : err(r.code.startsWith('http_') ? 'unreachable' : r.code))
    // a failed command is in the account log too
    router.refresh()
  }

  // the disabled actions and why, one line per reason
  const reasons = new Map<string, string[]>()
  for (const a of panel.actions) if (a.why) reasons.set(a.why, [...(reasons.get(a.why) ?? []), t(`actions.${a.key}`)])

  return (
    <div className="sticky top-20 flex flex-col gap-3 rounded-20 border border-ink bg-surface px-[22px] py-5">
      <div className="flex items-start justify-between gap-[10px]">
        <div className="min-w-0">
          <div className="font-serif text-22 font-semibold leading-[1.15]">{panel.name}</div>
          <div className="mt-[3px] text-12 text-muted">{panel.sub}</div>
        </div>
        {panel.status ? <span className={`flex-none rounded-999 px-[11px] py-1 text-11.5 font-bold ${statusTone(panel.status)}`}>{panel.statusLabel}</span> : null}
      </div>
      <div className="grid grid-cols-3 gap-2">
        {panel.facts.map((f) => (
          <div key={f.key} className="min-w-0 rounded-13 border border-line bg-canvas px-[11px] py-[9px]">
            <div className="text-10.5 font-bold uppercase tracking-[.08em] text-muted">{t(`detail.${f.key}`)}</div>
            <b className={`text-14 ${f.tone}`}>{f.value}</b>
          </div>
        ))}
      </div>
      <div className={eyebrow}>{t('detail.contact')}</div>
      <div className="text-13">
        {panel.contact ? (
          <>
            <b>{panel.contact.name}</b>
            {panel.contact.email ? <div className="text-12 text-muted">{panel.contact.email}</div> : null}
          </>
        ) : <span className="text-muted">—</span>}
      </div>
      <div className={eyebrow}>{t('detail.actions')}</div>
      <div className="grid grid-cols-2 gap-2">
        {panel.actions.map((a) => (
          <button
            key={a.key}
            type="button"
            disabled={!!a.why || (a.key === 'trial' && busy)}
            title={a.why ?? undefined}
            onClick={() => void run(a.key)}
            className={`h-[38px] flex-none cursor-pointer whitespace-nowrap rounded-10 border px-[10px] text-12.5 font-bold disabled:cursor-default ${ACTION_STYLE[a.key]} ${a.why ? 'opacity-55' : ''}`}
          >
            {t(`actions.${a.key}`)}
          </button>
        ))}
      </div>
      {[...reasons].map(([why, names]) => (
        <div key={why} className="-mt-1 text-11.5 text-faint">{t('actions.whyLine', { names: names.join(' · '), reason: why })}</div>
      ))}
      <div className={eyebrow}>{t('detail.recent')}</div>
      {panel.recent.map((l) => (
        <div key={l.key} className="flex justify-between gap-2 border-b border-tile py-[5px] text-12.5">
          <span>{l.text}</span>
          <span className="whitespace-nowrap text-faint">{l.when}</span>
        </div>
      ))}
      {panel.recent.length === 0 ? <div className="text-12.5 text-muted">{t('detail.recentEmpty')}</div> : null}
    </div>
  )
}
