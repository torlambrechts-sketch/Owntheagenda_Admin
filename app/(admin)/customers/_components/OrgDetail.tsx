import Link from 'next/link'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { can, type Shell } from '@/lib/shell'
import { money } from '@/lib/format'
import {
  loadAudit, loadCustomer, loadLabels, loadNotes, loadStaff, loadTickets, loadTimeline, settingValue, type CustomerDetail,
} from '@/lib/data/customers'
import { ui } from '@/components/ui/styles'
import { ActionsMenu } from './ActionsMenu'
import { TimelineList, type TimelineRow } from './TimelineList'
import { NotesTags } from './NotesTags'
import { PRIORITY_INK, TIMELINE_DOT, statusTone } from './tones'
import { dateRange, daysSince, daysUntil, initials, label, orgNr, when, type Fmt, type T } from './fmt'

export const DETAIL_TABS = ['overview', 'users', 'surveys', 'billing', 'timeline', 'tickets', 'notes', 'audit'] as const
export type DetailTab = (typeof DETAIL_TABS)[number]

type Ctx = { o: CustomerDetail; t: T; fmt: Fmt; now: Date; shell: Shell }

const card = 'rounded-20 border border-line bg-surface px-[22px] py-5'
const tableCard = 'overflow-hidden rounded-20 border border-line bg-surface'
const colHead = 'text-10.5 font-bold uppercase tracking-label text-muted'
const smallBtn = 'h-7 cursor-pointer rounded-9 border bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default disabled:opacity-55'
const MILESTONES = ['account_created', 'employees_uploaded', 'survey_scheduled', 'survey_sent', 'result_unlocked', 'results_viewed', 'first_tiltak', 'converted']

/** One customer company (Customers.dc.html, v.detail): the header, its actions and the eight tabs. */
export async function OrgDetail({ id, tab, shell }: { id: string; tab: DetailTab; shell: Shell }) {
  const t = await getTranslations('customers')
  const fmt = await getFormatter()
  const now = await getNow()
  const r = await loadCustomer(id)
  if (!r.ok) {
    return (
      <div className="flex flex-col gap-4">
        <Link href="/customers" className="self-start text-13 font-semibold text-link">{t('detail.back')}</Link>
        <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{t(`detail.unavailable.${r.code === 'forbidden' ? 'forbidden' : 'not_found'}`)}</div>
      </div>
    )
  }
  const o = r.data
  const labels = await loadLabels()
  const labelName = new Map(labels.map((l) => [l.id, l.name]))
  const prodName = (k: string) => shell.products.find((p) => p.key === k)?.name ?? k
  const ctx: Ctx = { o, t, fmt, now, shell }

  const where = [o.address, [o.postal_code, o.city].filter(Boolean).join(' ')].filter(Boolean).join(', ')
  const facts = [
    o.org_number ? orgNr(o.org_number) : null,
    where || null,
    o.nace ? t('detail.nace', { nace: o.nace }) : null,
    o.registered_employees !== null ? t('detail.employeesRegistered', { n: o.registered_employees }) : null,
  ].filter(Boolean)
  const source = [
    o.brreg_synced_at ? t('detail.brreg', { when: fmt.relativeTime(new Date(o.brreg_synced_at), now) }) : null,
    o.owner ? t('detail.owner', { name: o.owner }) : null,
    o.csm ? t('detail.csm', { name: o.csm }) : null,
  ].filter(Boolean)

  // the actions menu: what reaches Orgpuls today, and the preview each one shows
  const orgpuls = o.subscriptions.find((s) => s.product === 'orgpuls')
  const trialDays = orgpuls?.status === 'trial' && orgpuls.trial_ends_at ? daysUntil(orgpuls.trial_ends_at, now) : null
  const secondAdmin = await settingValue('second_admin')
  const writer = can(shell, 'global', 'edit_others')

  const tabBody = await (async () => {
    switch (tab) {
      case 'overview': return overview(ctx, prodName)
      case 'users': return users(ctx)
      case 'surveys': return surveys(ctx)
      case 'billing': return billing(ctx, prodName)
      case 'timeline': return timeline(ctx, prodName)
      case 'tickets': return tickets(ctx)
      case 'notes': return notes(ctx, labels)
      case 'audit': return audit(ctx)
    }
  })()

  return (
    <div className="flex flex-col gap-4">
      <Link href="/customers" className="self-start text-13 font-semibold text-link">{t('detail.back')}</Link>
      <div className="flex flex-wrap items-start gap-[22px] rounded-20 border border-line bg-surface px-6 py-[22px]">
        <span className="flex h-14 w-14 flex-none items-center justify-center rounded-16 bg-ink font-serif text-22 font-bold text-canvas">{initials(o.name)}</span>
        <div className="flex min-w-0 flex-[1_1_360px] flex-col gap-2">
          <div className="flex flex-wrap items-center gap-[10px]">
            <h2 className="m-0 font-serif text-28 font-semibold leading-[1.1]">{o.name}</h2>
            {o.status ? <span className={`rounded-999 px-[11px] py-1 text-11.5 font-bold ${statusTone(o.status)}`}>{t(`status.${o.status}`)}</span> : null}
            {o.labels.map((l) => labelName.get(l)).filter(Boolean).map((l) => (
              <span key={l} className="rounded-999 border border-line-strong px-[9px] py-[3px] text-11 font-semibold text-muted">{l}</span>
            ))}
          </div>
          {facts.length ? <div className="text-13 text-ink-2">{facts.join(' · ')}</div> : null}
          {source.length ? <div className="text-12 text-muted">{source.join(' · ')}</div> : null}
          {o.subscriptions.length ? (
            <div className="mt-1 flex flex-wrap gap-[6px]">
              {o.subscriptions.slice().sort((a, b) => shell.products.findIndex((x) => x.key === a.product) - shell.products.findIndex((x) => x.key === b.product)).map((s) => {
                const p = shell.products.find((x) => x.key === s.product)
                return (
                  <span key={s.product} className="flex items-center gap-[6px] rounded-999 px-[11px] py-[5px] text-12 font-bold" style={{ background: p?.color ?? '#F2EAD6', color: p?.ink ?? '#191510' }}>
                    <span>{prodName(s.product)}</span><span>·</span><span>{t(`status.${s.status}`)}</span>
                  </span>
                )
              })}
            </div>
          ) : null}
        </div>
        <div className="flex items-center gap-[22px]">
          <div className="flex flex-col items-end">
            <span className={ui.eyebrow}>{t('detail.health')}</span>
            <span className="font-serif text-40 font-semibold leading-none">—</span>
          </div>
          <div className="flex flex-col items-end">
            <span className={ui.eyebrow}>{t('detail.mrr')}</span>
            <span className="font-serif text-26 font-semibold leading-[1.2]">{o.mrr ? money(o.mrr, shell.me.number_format) : '—'}</span>
            {o.plan ? <span className="text-12 text-muted">{t('detail.band', { plan: o.plan })}</span> : null}
          </div>
          <ActionsMenu
            org={{ id: o.id, name: o.name, orgnr: o.org_number ? orgNr(o.org_number).replace(/ /g, ' ') : '', suspended: o.status === 'suspended' }}
            hasOrgpuls={!!orgpuls}
            previews={{
              trial: t('actions.preview.trial', { left: trialDays !== null ? t('actions.preview.trialLeft', { n: Math.max(0, trialDays) }) : '—' }),
              delete: t('actions.preview.delete', {
                users: o.users.filter((u) => u.product === 'orgpuls').length,
                rounds: o.rounds.filter((x) => x.product === 'orgpuls').length,
                cancelled: orgpuls?.cancelled_at ? 'yes' : 'no',
              }),
            }}
            rights={{ trial: writer, resync: writer || can(shell, 'global', 'add'), delete: shell.me.permission_kind === 'admin' }}
            secondAdmin={secondAdmin === 'on'}
          />
        </div>
      </div>

      <nav className="flex flex-wrap gap-[2px] border-b border-line" aria-label={t('detail.tabsLabel')}>
        {DETAIL_TABS.map((k) => {
          const on = k === tab
          return (
            <Link
              key={k}
              href={(k === 'overview' ? `/customers?org=${o.id}` : `/customers?org=${o.id}&d=${k}`) as never}
              aria-current={on ? 'page' : undefined}
              className={`cursor-pointer border-b-2 bg-transparent px-[14px] py-[10px] text-13 hover:no-underline ${on ? 'border-ink font-bold text-ink hover:text-ink' : 'border-transparent font-medium text-muted hover:text-muted'}`}
            >
              {t(`detail.tabs.${k}`)}
            </Link>
          )
        })}
      </nav>

      {tabBody}
    </div>
  )
}

function Tile({ value, label: name, danger }: { value: string; label: string; danger?: boolean }) {
  return (
    <div className="rounded-15 border border-line bg-canvas px-[14px] py-3">
      <div className={`font-serif text-24 font-semibold ${danger ? 'text-danger' : ''}`}>{value}</div>
      <div className="text-12 text-muted">{name}</div>
    </div>
  )
}

function overview({ o, t, shell }: Ctx, prodName: (k: string) => string) {
  const nf = shell.me.number_format
  const start = o.milestones.account_created ?? o.signup_at
  const reported = Object.keys(o.milestones).length > 0
  const count = (k: string) => (o.counts[k] !== undefined ? String(o.counts[k]) : '—')
  return (
    <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,340px),1fr))]">
      <div className={card}>
        <div className="mb-[14px] text-15 font-bold">{t('overview.activation')}</div>
        <div className="flex flex-col gap-[7px]">
          {MILESTONES.map((k, i) => {
            const at = o.milestones[k]
            return (
              <div key={k} className="flex items-center gap-[10px] text-12.5">
                <span className={`flex h-5 w-5 flex-none items-center justify-center rounded-999 border-[1.5px] text-11 font-bold text-ok-ink ${at ? 'border-link bg-ok-bg' : 'border-line-strong bg-transparent'}`}>{at ? '✓' : i + 1}</span>
                <span className={`flex-1 ${at ? 'font-normal' : 'font-semibold'}`}>{t(`milestones.${k}`)}</span>
                <span className="text-11.5 text-muted">{at && start ? t('overview.day', { n: Math.max(0, daysSince(start, new Date(at))) }) : ''}</span>
              </div>
            )
          })}
        </div>
        {!reported ? <div className="mt-3 text-12 text-muted">{t('overview.noMilestones')}</div> : null}
      </div>

      <div className={`${card} flex flex-col gap-[14px]`}>
        <div className="text-15 font-bold">{t('overview.structure')}</div>
        <div className="grid grid-cols-2 gap-[10px]">
          <Tile value={count('departments')} label={t('overview.departments')} />
          <Tile value={count('teams')} label={t('overview.teams')} />
          <Tile value={count('employees')} label={t('overview.onList')} />
          <Tile value={count('groups_below_threshold')} label={t('overview.belowThreshold')} danger={(o.counts.groups_below_threshold ?? 0) > 2} />
        </div>
        <div className="rounded-12 border border-dashed border-line-strong px-3 py-[10px] text-12 leading-[1.5] text-muted">{t('overview.anonymity')}</div>
      </div>

      <div className={card}>
        <div className="mb-3 text-15 font-bold">{t('overview.crossProduct')}</div>
        <div className="flex flex-col gap-2">
          {shell.products.map((p) => {
            const s = o.subscriptions.find((x) => x.product === p.key)
            return (
              <div key={p.key} className={`flex items-center gap-[10px] rounded-15 border border-line px-3 py-[10px] ${s ? 'bg-surface' : 'bg-canvas'}`}>
                <span className="flex h-7 w-7 items-center justify-center rounded-9 font-serif font-bold" style={{ background: p.color, color: p.ink }}>{p.name[0]}</span>
                <span className="flex flex-1 flex-col">
                  <span className="text-13 font-bold">{prodName(p.key)}</span>
                  <span className="text-11.5 text-muted">
                    {s ? [t(`status.${s.status}`), s.seats !== null ? t('overview.seats', { n: s.seats }) : null].filter(Boolean).join(' · ') : t('overview.notUsed')}
                  </span>
                </span>
                <span className="text-12 font-bold">{s && s.mrr ? money(s.mrr, nf) : '—'}</span>
              </div>
            )
          })}
        </div>
        <div className="mt-[10px] text-11.5 text-faint">{t('overview.joined')}</div>
      </div>

      <div className={card}>
        <div className="mb-3 text-15 font-bold">{t('overview.tiltak')}</div>
        <div className="mb-[14px] grid grid-cols-3 gap-[10px]">
          <Tile value={count('tiltak_open')} label={t('overview.tiltakOpen')} />
          <Tile value={count('tiltak_closed')} label={t('overview.tiltakClosed')} />
          <Tile value={count('tiltak_overdue')} label={t('overview.tiltakOverdue')} danger={o.counts.tiltak_overdue !== undefined && o.counts.tiltak_overdue > 0} />
        </div>
        <div className="mb-2 text-12 text-muted">{t('overview.titlesOnly')}</div>
        <div className="flex justify-between border-t border-line py-[10px] text-13"><span>{t('overview.nps')}</span><b>—</b></div>
        <div className="flex justify-between border-t border-line py-[10px] text-13"><span>{t('overview.feedback')}</span><b>—</b></div>
      </div>

      <div className={card}>
        <div className="mb-3 flex items-baseline justify-between">
          <span className="text-15 font-bold">{t('overview.crm')}</span>
          <Link href="/deals" className="text-12.5 font-semibold">{t('overview.openDeals')}</Link>
        </div>
        {o.deals.map((d) => (
          <Link key={d.id} href={`/deals?deal=${d.id}` as never} className="flex justify-between gap-[10px] border-b border-line py-[9px] text-13 text-ink hover:text-ink hover:no-underline">
            <span className="flex flex-col"><span className="font-semibold">{d.title}</span><span className="text-11.5 text-muted">{d.stage} · {label(t, 'dealStatus', d.status)}</span></span>
            <b className="whitespace-nowrap">{d.value !== null ? money(d.value, nf) : '—'}</b>
          </Link>
        ))}
        {o.contacts.map((c) => (
          <Link key={c.id} href={`/contacts?person=${c.id}` as never} className="flex justify-between gap-[10px] border-b border-line py-[9px] text-13 text-ink hover:text-ink hover:no-underline">
            <span className="flex flex-col"><span className="font-semibold">{c.name}</span><span className="text-11.5 text-muted">{[c.title, c.email].filter(Boolean).join(' · ') || '—'}</span></span>
            <span className="whitespace-nowrap text-11.5 text-muted">{label(t, 'consent', c.marketing_status)}</span>
          </Link>
        ))}
        {o.deals.length + o.contacts.length === 0 ? <div className="py-[9px] text-13 text-muted">{t('overview.noCrm')}</div> : null}
      </div>
    </div>
  )
}

function users({ o, t, fmt, now }: Ctx) {
  const notYet = t('notYet')
  const grid = '[grid-template-columns:minmax(180px,1.6fr)_120px_110px_90px_100px_120px_230px]'
  return (
    <div className={tableCard}>
      <div className="overflow-x-auto">
        <div className="min-w-[1080px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[10px] ${colHead} ${grid}`}>
            <span>{t('users.user')}</span><span>{t('users.role')}</span><span>{t('users.lastLogin')}</span><span>{t('users.mfa')}</span><span>{t('users.auth')}</span><span>{t('users.invitedBy')}</span><span />
          </div>
          {o.users.map((u) => {
            const pending = u.invite_state === 'pending'
            const stale = u.last_login_at ? daysSince(u.last_login_at, now) > 30 : false
            return (
              <div key={`${u.product}:${u.user_id}`} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 ${grid}`}>
                <span className="flex flex-col">
                  <span className="font-semibold">
                    {u.name ?? u.email ?? '—'}{' '}
                    {u.is_billing_contact ? <span className="rounded-999 bg-highlight px-[7px] py-px text-10.5 font-bold text-amber-ink">{t('users.billingContact')}</span> : null}
                    {!u.active ? <span className="rounded-999 bg-tile px-[7px] py-px text-10.5 font-bold text-muted">{t('users.deactivated')}</span> : null}
                  </span>
                  <span className="text-11.5 text-muted">{u.email ?? '—'}</span>
                </span>
                <span>{label(t, 'roles', u.role)}</span>
                <span className={pending ? 'text-warn-ink' : stale ? 'text-danger' : 'text-ink'}>{pending ? t('users.invitePending') : u.last_login_at ? when(u.last_login_at, now, fmt, t, 'plain') : '—'}</span>
                <span className={u.mfa_enabled === null ? 'text-muted' : u.mfa_enabled ? 'text-link' : 'text-danger'}>{u.mfa_enabled === null ? '—' : u.mfa_enabled ? t('users.on') : t('users.off')}</span>
                <span className="text-muted">{label(t, 'auth', u.auth_method)}</span>
                <span className="text-muted">{u.invited_by ?? '—'}</span>
                <span className="flex justify-end gap-[6px]">
                  <button type="button" disabled title={notYet} className={`${smallBtn} border-line`}>{pending ? t('users.resendInvite') : t('users.magicLink')}</button>
                  <button type="button" disabled title={notYet} className={`${smallBtn} border-line`}>{t('users.resetMfa')}</button>
                  <button type="button" disabled title={notYet} className={`${smallBtn} border-coral text-rust`}>{t('users.deactivate')}</button>
                </span>
              </div>
            )
          })}
          {o.users.length === 0 ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('users.empty')}</div> : null}
        </div>
      </div>
      <div className="px-[18px] py-3 text-12 text-muted">{t('users.footer')} {t('users.actionsNotYet')}</div>
    </div>
  )
}

function surveys({ o, t, fmt, now }: Ctx) {
  const grid = '[grid-template-columns:minmax(160px,1.4fr)_80px_120px_70px_70px_70px_70px_80px_120px]'
  const v = (x: number | null) => (x !== null ? String(x) : '—')
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-[10px] rounded-16 bg-highlight px-4 py-3 text-12.5 text-amber-ink">
        {t.rich('surveys.banner', { b: (c) => <b className="text-ink">{c}</b> })}
      </div>
      <div className={tableCard}>
        <div className="overflow-x-auto">
          <div className="min-w-[900px]">
            <div className={`grid gap-[10px] border-b border-line px-[18px] py-[10px] ${colHead} ${grid}`}>
              <span>{t('surveys.survey')}</span><span>{t('surveys.type')}</span><span>{t('surveys.dates')}</span><span>{t('surveys.invited')}</span><span>{t('surveys.delivered')}</span>
              <span>{t('surveys.bounced')}</span><span>{t('surveys.answered')}</span><span>{t('surveys.rate')}</span><span>{t('surveys.reminders')}</span>
            </div>
            {o.rounds.map((r) => {
              const dates = dateRange(r.opens_at ?? r.planned_at, r.closes_at, now, fmt)
              const rate = r.answered !== null && r.delivered ? `${Math.round((r.answered / r.delivered) * 100)} %` : '—'
              const rem = r.reminders_sent === null ? '—' : r.gained_after_reminders !== null ? t('surveys.remindersGained', { n: r.reminders_sent, gained: r.gained_after_reminders }) : String(r.reminders_sent)
              return (
                <div key={`${r.product}:${r.round_ref}`} className={`grid items-center gap-[10px] border-b border-line px-[18px] py-[11px] text-13 tabular-nums ${grid}`}>
                  <span className="font-semibold">{r.name ?? r.round_ref}</span>
                  <span>{r.kind ? <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${r.kind === 'pulse' ? 'bg-teal-soft' : 'bg-tile'}`}>{t(`surveys.kind.${r.kind}`)}</span> : '—'}</span>
                  <span className="text-muted">{dates}</span>
                  <span>{v(r.invited)}</span>
                  <span>{v(r.delivered)}</span>
                  <span className={(r.bounced ?? 0) > 2 ? 'text-danger' : 'text-ink'}>{v(r.bounced)}</span>
                  <span>{v(r.answered)}</span>
                  <b>{rate}</b>
                  <span className="text-muted">{rem}</span>
                </div>
              )
            })}
            {o.rounds.length === 0 ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('surveys.empty')}</div> : null}
          </div>
        </div>
      </div>
    </div>
  )
}

function billing({ o, t, now, shell }: Ctx, prodName: (k: string) => string) {
  const nf = shell.me.number_format
  const main = o.subscriptions.find((s) => s.product === 'orgpuls') ?? o.subscriptions[0]
  const per = main?.billing_interval === 'year' ? t('billing.perYear') : t('billing.perMonth')
  const pay = o.subscriptions.find((s) => s.payment_state !== 'ok')?.payment_state ?? (o.subscriptions.length ? 'ok' : null)
  const trial = o.subscriptions.find((s) => s.status === 'trial' && s.trial_ends_at)
  const rows: { k: string; v: string; danger?: boolean }[] = main
    ? [
        { k: t('billing.plan'), v: [main.plan ? t('billing.planBand', { plan: main.plan }) : null, main.price !== null ? `${money(main.price, nf, main.currency)}${per}` : null].filter(Boolean).join(' · ') || '—' },
        { k: t('billing.applications'), v: o.subscriptions.map((s) => prodName(s.product)).join(', ') },
        { k: t('billing.nextInvoice'), v: trial?.trial_ends_at ? t('billing.afterTrial', { n: Math.max(0, daysUntil(trial.trial_ends_at, now)) }) : '—' },
        { k: t('billing.payment'), v: pay ? t(`billing.paymentState.${pay}`) : '—', danger: !!pay && pay !== 'ok' },
      ]
    : []
  return (
    <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,340px),1fr))]">
      <div className={`${card} flex flex-col gap-[10px]`}>
        <div className="text-15 font-bold">{t('billing.subscription')}</div>
        {rows.map((r) => (
          <div key={r.k} className="flex justify-between gap-[10px] border-b border-line py-2 text-13">
            <span className="text-muted">{r.k}</span>
            <b className={`text-right ${r.danger ? 'text-danger' : 'text-ink'}`}>{r.v}</b>
          </div>
        ))}
        {rows.length === 0 ? <div className="text-13 text-muted">{t('billing.none')}</div> : null}
      </div>
      <div className={`${tableCard} [grid-column:span_2] max-[760px]:[grid-column:auto]`}>
        <div className="flex items-center justify-between gap-3 border-b border-line px-[18px] py-[14px]">
          <span className="text-15 font-bold">{t('billing.invoices')}</span>
        </div>
        <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('billing.noInvoices')}</div>
      </div>
    </div>
  )
}

async function timeline({ o, t, fmt, now }: Ctx, prodName: (k: string) => string) {
  const r = await loadTimeline(o.id)
  if (!r.ok) return <Refused t={t} code={r.code} />
  const rows: TimelineRow[] = r.data.map((e, i) => {
    const filter = e.kind === 'admin' ? 'support' : e.kind
    let title: string
    let sub: string
    if (e.kind === 'admin') {
      title = label(t, 'auditActions', e.event)
      sub = [t('timeline.adminAction'), e.actor, e.reason].filter(Boolean).join(' · ')
    } else if (e.kind === 'support') {
      title = t('timeline.ticket', { ref: e.ref ?? '' })
      sub = [t('timeline.support'), e.status ? label(t, 'ticketStatus', e.status) : null].filter(Boolean).join(' · ')
    } else {
      title = label(t, 'events', e.event)
      sub = [t('timeline.product'), e.product ? prodName(e.product) : null].filter(Boolean).join(' · ')
    }
    return { key: `${i}`, when: when(e.at, now, fmt, t), title, sub, filter, dot: TIMELINE_DOT[e.kind] ?? '#F2EAD6' }
  })
  return <TimelineList rows={rows} />
}

async function tickets({ o, t }: Ctx) {
  const r = await loadTickets(o.id)
  if (!r.ok) return <Refused t={t} code={r.code} />
  return (
    <div className={tableCard}>
      {r.data.map((x) => (
        <Link
          key={x.id}
          href={`/tickets?ticket=${x.id}` as never}
          className="grid w-full cursor-pointer items-center gap-[10px] border-b border-line bg-transparent px-[18px] py-3 text-left text-13 text-ink [grid-template-columns:80px_minmax(0,1fr)_120px_90px_140px] hover:text-ink hover:no-underline"
        >
          <b>{x.ref}</b>
          <span className="flex min-w-0 flex-col">
            <span className="font-semibold">{x.subject}</span>
            <span className="text-11.5 text-muted">{[label(t, 'ticketType', x.type), label(t, 'ticketCategory', x.category_key), label(t, 'ticketChannel', x.channel)].join(' · ')}</span>
          </span>
          <span className="text-muted">{label(t, 'ticketQueue', x.queue_key)}</span>
          <span className={`font-bold ${PRIORITY_INK[x.priority] ?? 'text-muted'}`}>{label(t, 'ticketPriority', x.priority)}</span>
          <span className="text-muted">{label(t, 'ticketStatus', x.status)}</span>
        </Link>
      ))}
      {r.data.length === 0 ? <div className="p-[26px] text-center text-13 text-muted">{t('tickets.empty')}</div> : null}
      <div className="px-[18px] py-3">
        <Link href={`/tickets?newFor=${o.id}` as never} className="inline-flex h-8 cursor-pointer items-center rounded-9 border border-ink bg-surface px-[13px] text-12.5 font-bold text-ink hover:text-ink hover:no-underline">
          {t('tickets.new', { name: o.name })}
        </Link>
      </div>
    </div>
  )
}

async function notes({ o, t, fmt, now, shell }: Ctx, labels: { id: string; name: string }[]) {
  const [r, staff] = await Promise.all([loadNotes(o.id), loadStaff()])
  if (!r.ok) return <Refused t={t} code={r.code} />
  return (
    <NotesTags
      org={{ id: o.id, version: o.version, labels: o.labels }}
      notes={r.data.filter((n) => !n.parent_id).map((n) => ({
        id: n.id, body: n.body, by: n.author ?? '—', when: when(n.created_at, now, fmt, t, 'plain'), pinned: n.pinned, mine: n.author_id === shell.me.id,
      }))}
      labels={labels}
      staff={staff.filter((s) => s.active && s.id !== shell.me.id).map((s) => ({ id: s.id, name: s.name }))}
      canDeleteOthers={can(shell, 'deals', 'edit_others')}
    />
  )
}

async function audit({ o, t, fmt, now }: Ctx) {
  const r = await loadAudit(o.id)
  if (!r.ok) return <Refused t={t} code={r.code} />
  const grid = '[grid-template-columns:130px_140px_minmax(0,1fr)_minmax(0,1fr)]'
  return (
    <div className={tableCard}>
      <div className="overflow-x-auto">
        <div className="min-w-[640px]">
          <div className={`grid gap-[10px] border-b border-line px-[18px] py-[10px] ${colHead} ${grid}`}>
            <span>{t('audit.when')}</span><span>{t('audit.who')}</span><span>{t('audit.action')}</span><span>{t('audit.reason')}</span>
          </div>
          {r.data.map((a, i) => (
            <div key={i} className={`grid gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 ${grid}`}>
              <span className="text-muted">{when(a.at, now, fmt, t, 'full')}</span>
              <b>{a.who ?? '—'}</b>
              <span>{label(t, 'auditActions', a.action)}{a.ok ? '' : ` · ${t('audit.failed')}`}</span>
              <span className="text-muted">{a.reason ?? '—'}</span>
            </div>
          ))}
          {r.data.length === 0 ? <div className="px-[18px] py-[26px] text-center text-13 text-muted">{t('audit.empty')}</div> : null}
        </div>
      </div>
      <div className="px-[18px] py-3 text-12 text-muted">{t('audit.footer')}</div>
    </div>
  )
}

function Refused({ t, code }: { t: T; code: string }) {
  return (
    <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">
      {code === 'forbidden' ? t('detail.tabForbidden') : t('detail.tabFailed')}
    </div>
  )
}
