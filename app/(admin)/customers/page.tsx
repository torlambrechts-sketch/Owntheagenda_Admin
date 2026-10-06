import { cookies } from 'next/headers'
import { getNow, getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import { money } from '@/lib/format'
import {
  FILTER_KEYS, loadCustomers, loadGrants, loadLabels, loadPrivacy, loadSavedViews, loadStaff, type FilterKey, type ListQuery, type ViewKey,
} from '@/lib/data/customers'
import { TopTabs, type TabKey } from './_components/TopTabs'
import { OrgList, type ListRow } from './_components/OrgList'
import { OrgDetail, DETAIL_TABS } from './_components/OrgDetail'
import { UsersView } from './_components/UsersView'
import { BillingView } from './_components/BillingView'
import { AccessView } from './_components/AccessView'
import { PrivacyView } from './_components/PrivacyView'
import { ago, daysSince, orgNr } from './_components/fmt'

// the saved views the list offers; «At risk before renewal» waits for the health score (phase 4, V-CUSTOMERS-01)
const VIEWS = ['all', 'trials_week_no_survey', 'past_due', 'multi_product', 'ehf'] as const satisfies readonly ViewKey[]
const STATUSES = ['trial', 'active', 'past_due', 'cancelled', 'suspended']

const first = (v: unknown) => (Array.isArray(v) ? v[0] : v)
const one = z.preprocess(first, z.string().max(200).optional()).catch(undefined)
const Params = z.object({
  tab: z.preprocess(first, z.enum(['orgs', 'users', 'billing', 'access', 'privacy']).default('orgs')).catch('orgs'),
  org: z.preprocess(first, z.string().uuid().optional()).catch(undefined),
  d: z.preprocess(first, z.enum(DETAIL_TABS).default('overview')).catch('overview'),
  view: z.preprocess(first, z.enum(VIEWS).default('all')).catch('all'),
  q: one, uq: one, status: one, plan: one, industry: one, fylke: one, source: one, uses: one,
})

/** Customers (Customers.dc.html): organizations, one company's detail, users, billing, support access, personvern. */
export default async function CustomersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = Params.parse(await searchParams)
  const shell = await getShell()
  const t = await getTranslations('customers')
  const now = await getNow()
  const nf = shell.me.number_format
  const cookie = (await cookies()).get('product')?.value ?? 'all'
  const product = cookie === 'all' || shell.products.some((x) => x.key === cookie) ? cookie : 'all'
  const tab: TabKey = p.tab

  // the list's query: filters by their database values («uses» is a product key)
  const fromParam: Record<FilterKey, string | undefined> = { status: p.status, plan: p.plan, industry: p.industry, fylke: p.fylke, source: p.source, product: p.uses }
  const f: Partial<Record<FilterKey, string>> = {}
  for (const k of FILTER_KEYS) if (fromParam[k]) f[k] = fromParam[k]
  const listing = tab === 'orgs' && !p.org
  const query: ListQuery = listing ? { product, view: p.view, ...(p.q ? { q: p.q } : {}), ...(Object.keys(f).length ? { f } : {}) } : { product }

  const [list, grants, privacy] = await Promise.all([loadCustomers(query), loadGrants(), loadPrivacy()])
  const counts = {
    orgs: list.views.all,
    access: grants.ok ? grants.data.filter((g) => g.state === 'pending' || g.state === 'active').length : null,
    privacy: privacy.ok ? privacy.data.length : null,
  }

  let body: React.ReactNode
  if (tab === 'orgs' && p.org) {
    body = <OrgDetail id={p.org} tab={p.d} shell={shell} />
  } else if (tab === 'orgs') {
    const [labels, staff, saved] = await Promise.all([loadLabels(), loadStaff(), loadSavedViews()])
    const labelName = new Map(labels.map((l) => [l.id, l.name]))
    const prod = new Map(shell.products.map((x) => [x.key, x]))
    const order = (k: string) => { const i = shell.products.findIndex((x) => x.key === k); return i < 0 ? 99 : i }
    const rows: ListRow[] = list.rows.map((o) => {
      const ls = o.last_survey_at ? daysSince(o.last_survey_at, now) : null
      const status = o.status ? t(`status.${o.status}`) : '—'
      return {
        id: o.id,
        name: o.name,
        orgnr: orgNr(o.org_number),
        status: o.status,
        statusLabel: status,
        plan: o.plan ?? '—',
        employees: o.employees !== null ? String(o.employees) : '—',
        ls: ls !== null ? t('fmt.daysAgo', { n: ls }) : t('list.never'),
        lsDanger: ls === null || ls > 90,
        resp: o.last_survey_at && o.response !== null ? `${o.response} %` : '—',
        mrr: o.mrr ? money(o.mrr, nf) : '—',
        mrrValue: o.mrr,
        signup: o.signup_at ? ago(o.signup_at, now, t) : '—',
        prods: o.products.slice().sort((a, b) => order(a.key) - order(b.key)).map((x) => ({ key: x.key, name: prod.get(x.key)?.name ?? x.key, color: prod.get(x.key)?.color ?? '#F2EAD6', ink: prod.get(x.key)?.ink ?? '#191510' })),
        labelIds: o.labels,
        labels: o.labels.map((l) => labelName.get(l)).filter((x): x is string => !!x),
        csv: [
          o.name, o.org_number ?? '', o.status ? status : '', o.plan ?? '', o.employees ?? '', o.last_survey_at?.slice(0, 10) ?? '', o.response ?? '', o.mrr,
          o.signup_at?.slice(0, 10) ?? '', o.products.map((x) => prod.get(x.key)?.name ?? x.key).join(' + '),
          o.labels.map((l) => labelName.get(l) ?? '').filter(Boolean).join(' + '),
        ],
      }
    })
    const sorted = (values: string[]) => values.slice().sort((a, b) => a.localeCompare(b, 'nb')).map((v) => ({ value: v, label: v }))
    const filters = [
      { key: 'status', label: t('filters.status'), value: p.status, options: STATUSES.map((s) => ({ value: s, label: t(`status.${s}`) })) },
      { key: 'plan', label: t('filters.plan'), value: p.plan, options: list.facets.plans.slice().sort((a, b) => parseInt(a, 10) - parseInt(b, 10)).map((v) => ({ value: v, label: v })) },
      { key: 'industry', label: t('filters.industry'), value: p.industry, options: sorted(list.facets.industries) },
      { key: 'fylke', label: t('filters.fylke'), value: p.fylke, options: sorted(list.facets.fylker) },
      { key: 'source', label: t('filters.source'), value: p.source, options: sorted(list.facets.sources) },
      { key: 'uses', label: t('filters.uses'), value: p.uses, options: shell.products.map((x) => ({ value: x.key, label: x.name })) },
    ].map((x) => ({ ...x, value: x.value ?? '' }))
    body = (
      <OrgList
        rows={rows}
        q={p.q ?? ''}
        view={p.view}
        views={VIEWS.map((k) => ({ key: k, label: t(`views.${k}`), count: list.views[k] }))}
        saved={saved.ok ? saved.data.views.map((v) => ({ id: v.id, name: v.name, query: Object.fromEntries(Object.entries(v.query).filter((e): e is [string, string] => typeof e[1] === 'string')) })) : []}
        filters={filters}
        listMrr={money(list.rows.reduce((a, o) => a + o.mrr, 0), nf)}
        labels={labels.map((l) => ({ id: l.id, name: l.name }))}
        staff={staff.filter((s) => s.active).map((s) => ({ id: s.id, name: s.name }))}
        rights={{ bulk: can(shell, 'deals', 'bulk'), export: can(shell, 'deals', 'export') }}
      />
    )
  } else if (tab === 'users') {
    body = <UsersView q={p.uq ?? ''} product={product} />
  } else if (tab === 'billing') {
    body = <BillingView product={product} shell={shell} />
  } else if (tab === 'access') {
    body = <AccessView grants={grants.ok ? grants.data : null} orgs={list.rows} shell={shell} product={product} />
  } else {
    body = <PrivacyView rows={privacy.ok ? privacy.data : null} />
  }

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-[22px] text-14 text-ink md:px-7">
      <TopTabs current={tab} counts={counts} />
      {body}
    </div>
  )
}
