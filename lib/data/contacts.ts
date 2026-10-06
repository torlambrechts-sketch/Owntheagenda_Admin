import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'

/**
 * Contacts and Leads (Contacts.dc.html): people, organizations, leads, the activity timeline, places,
 * duplicates, imports and the restore list. Every read is an RPC parsed with its schema.
 */

const num = z.coerce.number()
const str = z.string()
const nstr = z.string().nullable()
const ids = z.array(z.string())

import type { Tab } from './contacts-shared'
export { TABS, CONTACT_TYPES, MARKETING, type Tab } from './contacts-shared'

export const Staff = z.object({ id: str, name: str, initials: nstr, active: z.boolean() })
export type Staff = z.infer<typeof Staff>
export const Label = z.object({ id: str, name: str, bg: str, ink: str, entity: str })
export type Label = z.infer<typeof Label>

export const Person = z.object({
  id: str, name: str, email: nstr, phone: nstr, organization_id: nstr, organization_id__title: nstr.optional(), title: nstr,
  contact_type: nstr, source: nstr, city: nstr, fylke: nstr, linkedin: nstr, owner_id: nstr, owner_id__title: nstr.optional(),
  labels: ids, marketing_status: str, version: num, custom: z.record(z.string(), z.unknown()), created_at: str, updated_at: str,
})
export type Person = z.infer<typeof Person>

export const Organization = z.object({
  id: str, name: str, org_number: nstr, address: nstr, postal_code: nstr, city: nstr, fylke: nstr, country: str, industry: nstr,
  employees: num.nullable(), website: nstr, phone: nstr, email: nstr, source: nstr, parent_id: nstr, account_id: nstr,
  owner_id: nstr, owner_id__title: nstr.optional(), labels: ids, version: num, custom: z.record(z.string(), z.unknown()),
})
export type Organization = z.infer<typeof Organization>

const list = <T extends z.ZodTypeAny>(row: T) => z.object({ total: num, rows: z.array(row) })
const Groups = z.array(z.object({ key: nstr, n: num }))

export const Relations = z.object({
  parent: z.object({ id: str, name: str }).nullable(),
  daughters: z.array(z.object({ id: str, name: str })),
  related: z.array(z.object({ id: str, name: str, note: nstr })),
})
export type Relations = z.infer<typeof Relations>

export const Lead = z.object({
  id: str, seq: num.nullable().optional(), title: str, value: num.nullable(), currency: str, source: nstr, form_data: z.unknown().nullable(), archived_at: nstr,
  converted_deal_id: nstr, labels: ids, version: num, created_at: str, owner_id: nstr, person_id: nstr, organization_id: nstr,
  person: z.object({ id: str, name: str, title: nstr, email: nstr }).nullable(),
  organization: z.object({ id: str, name: str, org_number: nstr, industry: nstr, city: nstr, employees: num.nullable() }).nullable(),
  owner: z.object({ name: nstr, initials: nstr }).nullable(),
  next_activity: z.object({ id: str, subject: str, starts_at: nstr, overdue: z.boolean().nullable() }).nullable(),
})
export type Lead = z.infer<typeof Lead>

export const Pipeline = z.object({ id: str, name: str, stages: z.array(z.object({ id: str, name: str })) })
export type Pipeline = z.infer<typeof Pipeline>
export const ActivityType = z.object({ id: str, key: str, name: str, glyph: str, active: z.boolean() })
export type ActivityType = z.infer<typeof ActivityType>

export const Activity = z.object({
  id: str, subject: str, starts_at: nstr, done: z.boolean(), duration_min: num, person_id: nstr, person: nstr, organization: nstr,
  type: z.object({ key: str, name: str, glyph: str }).nullable(), overdue: z.boolean().nullable(),
})
export type Activity = z.infer<typeof Activity>
const Activities = z.object({ rows: z.array(Activity) })

const DupSide = z.object({ id: str, name: str, email: nstr.optional(), phone: nstr.optional(), organization: nstr.optional(), org_number: nstr.optional(), city: nstr.optional() })
export const Duplicate = z.object({ id: str, entity: z.enum(['person', 'organization']), rule: str, score: num.nullable(), keep: DupSide.nullable(), merge: DupSide.nullable() })
export type Duplicate = z.infer<typeof Duplicate>

export const ImportRow = z.object({
  id: str, entity: str, file_name: nstr, rows_read: num, created: num, merged: num, skipped: num, status: str, created_at: str, by: nstr,
})
export type ImportRow = z.infer<typeof ImportRow>

export const Deleted = z.object({ entity: str, id: str, title: nstr, deleted_at: str, by: nstr, source: nstr })
export type Deleted = z.infer<typeof Deleted>

const Settings = z.array(z.object({ key: str, default: str, values: z.array(z.object({ scope_id: str, value: str })) }))
export const Field = z.object({
  id: str, entity: str, key: str, label: str, type: str, quality: str, readonly: z.boolean(), formula: nstr,
  options: z.array(z.object({ key: str, label: z.string().optional() }).passthrough()),
})
export type Field = z.infer<typeof Field>

export const Note = z.object({ id: str, body: str, pinned: z.boolean(), parent_id: nstr, created_at: str, author: nstr, author_id: nstr })
export type Note = z.infer<typeof Note>
const DealCard = z.object({ id: str, title: str, value: num, currency: str, status: str, expected_close_date: nstr, created_at: str })
const History = z.array(z.object({ at: str, field: str, source: nstr, actor: nstr }))
const Consent = z.array(z.object({ status: str, source: str, basis: nstr, at: str, actor: nstr }))

export type PersonDetail = {
  person: Person
  notes: Note[]
  deals: z.infer<typeof DealCard>[]
  activities: Activity[]
  changes: z.infer<typeof History>
  consent: z.infer<typeof Consent>
}

export type Week = { n: number; start: string }
export type Query = { q: string; type: string; consent: string; label: string; archived: boolean; leadLabel: string }

export type ContactsData = {
  tab: Tab
  query: Query
  staff: Staff[]
  labels: { person: Label[]; organization: Label[]; lead: Label[] }
  people: Person[] | null
  orgs: Organization[] | null
  orgCounts: { people: Record<string, number>; deals: Record<string, number> | null } | null
  org: { row: Organization; relations: Relations; people: Person[] } | null
  leads: Lead[] | null
  lead: Lead | null
  pipelines: Pipeline[] | null
  activityTypes: ActivityType[]
  timeline: { weeks: Week[]; today: number; activities: Activity[] } | null
  duplicates: Duplicate[] | null
  settings: Record<string, string>
  imports: ImportRow[] | null
  fields: Field[]
  deleted: Deleted[] | null
  detail: PersonDetail | null
}

// ---------------------------------------------------------------------------
const pageAll = async <T extends z.ZodTypeAny>(entity: string, query: Record<string, unknown>, row: T): Promise<z.infer<T>[]> => {
  const out: z.infer<T>[] = []
  for (let offset = 0; offset < 5000; offset += 500) {
    const r = await rpcOrThrow('rec_list', { p_entity: entity, p_query: { ...query, limit: 500, offset } }, list(row))
    out.push(...r.rows)
    if (out.length >= r.total || r.rows.length < 500) break
  }
  return out
}

export const peopleFilters = (q: Query) => [
  ...(q.type ? [{ f: 'contact_type', op: 'eq', v: q.type }] : []),
  ...(q.consent ? [{ f: 'marketing_status', op: 'eq', v: q.consent }] : []),
  ...(q.label ? [{ f: 'labels', op: 'has', v: [q.label] }] : []),
]
export const leadFilters = (q: Query) => (q.leadLabel ? [{ f: 'labels', op: 'has', v: [q.leadLabel] }] : [])

/** Calendar date (YYYY-MM-DD) of an instant in a time zone. */
export const localDate = (d: Date, tz: string) => new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
const tzOffset = (d: Date, tz: string) => {
  const p = new Intl.DateTimeFormat('en-US', { timeZone: tz, timeZoneName: 'longOffset' }).formatToParts(d).find((x) => x.type === 'timeZoneName')?.value ?? 'GMT'
  const m = p.match(/GMT([+-]\d{2}):?(\d{2})?/)
  return m ? `${m[1]}:${m[2] ?? '00'}` : '+00:00'
}
const addDays = (iso: string, n: number) => { const d = new Date(`${iso}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10) }
const isoWeek = (iso: string) => {
  const d = new Date(`${iso}T00:00:00Z`)
  const day = (d.getUTCDay() + 6) % 7
  d.setUTCDate(d.getUTCDate() - day + 3)
  const firstThu = new Date(Date.UTC(d.getUTCFullYear(), 0, 4))
  return 1 + Math.round(((d.getTime() - firstThu.getTime()) / 86_400_000 - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7)
}

/** Twelve ISO weeks with this week fifth, as the design draws them. */
export function timelineWeeks(now: Date, tz: string) {
  const today = localDate(now, tz)
  const dow = (new Date(`${today}T00:00:00Z`).getUTCDay() + 6) % 7
  const first = addDays(today, -dow - 28)
  const weeks = Array.from({ length: 12 }, (_, i) => { const start = addDays(first, i * 7); return { n: isoWeek(start), start } })
  const off = tzOffset(now, tz)
  return { weeks, today: 4, from: `${first}T00:00:00${off}`, to: `${addDays(first, 84)}T00:00:00${off}` }
}

const settingValue = (s: z.infer<typeof Settings>, key: string) => {
  const r = s.find((x) => x.key === key)
  return r ? (r.values.find((v) => v.scope_id === '')?.value ?? r.default) : ''
}

export async function loadPersonDetail(id: string): Promise<PersonDetail | null> {
  const p = await rpc('rec_get', { p_entity: 'person', p_id: id }, Person)
  if (!p.ok) return null
  const [notes, deals, acts, changes, consent] = await Promise.all([
    rpc('notes_list', { p_entity: 'person', p_id: id }, z.array(Note)),
    rpc('deal_list', { p_query: { filters: [{ f: 'person_id', op: 'eq', v: id }], limit: 50 } }, list(DealCard), { quiet: true }),
    rpc('activities_get', { p_query: { person_id: id } }, Activities),
    rpc('rec_history', { p_entity: 'person', p_id: id, p_limit: 30 }, History),
    rpc('consent_history', { p_person: id }, Consent),
  ])
  return {
    person: p.data,
    notes: notes.ok ? notes.data : [],
    deals: deals.ok ? deals.data.rows : [],
    activities: acts.ok ? acts.data.rows : [],
    changes: changes.ok ? changes.data : [],
    consent: consent.ok ? consent.data : [],
  }
}

export async function loadContacts(tab: Tab, query: Query, sel: { person?: string; lead?: string; org?: string }, tz: string, now: Date): Promise<ContactsData> {
  const [staff, labels, types] = await Promise.all([
    rpcOrThrow('staff_list', {}, z.array(Staff)),
    rpcOrThrow('labels_get', { p_entity: null }, z.array(Label)),
    rpc('activity_types_get', {}, z.array(ActivityType)),
  ])
  const data: ContactsData = {
    tab, query, staff,
    labels: { person: labels.filter((l) => l.entity === 'person'), organization: labels.filter((l) => l.entity === 'organization'), lead: labels.filter((l) => l.entity === 'lead') },
    people: null, orgs: null, orgCounts: null, org: null, leads: null, lead: null, pipelines: null,
    activityTypes: types.ok ? types.data.filter((t) => t.active) : [],
    timeline: null, duplicates: null, settings: {}, imports: null, fields: [], deleted: null, detail: null,
  }
  const jobs: Promise<unknown>[] = []

  if (tab === 'people' || tab === 'map') {
    jobs.push(pageAll('person', tab === 'people' ? { q: query.q, filters: peopleFilters(query), sort: { f: 'name', dir: 'asc' } } : { sort: { f: 'name', dir: 'asc' } }, Person).then((r) => { data.people = r }))
  }
  if (tab === 'orgs' || tab === 'map') {
    jobs.push(pageAll('organization', { sort: { f: 'name', dir: 'asc' } }, Organization).then((r) => { data.orgs = r }))
  }
  if (tab === 'orgs') {
    jobs.push(Promise.all([
      rpcOrThrow('rec_group', { p_entity: 'person', p_by: 'organization_id', p_query: {} }, Groups),
      rpc('rec_group', { p_entity: 'deal', p_by: 'organization_id', p_query: {} }, Groups, { quiet: true }),
    ]).then(([p, d]) => {
      const m = (g: z.infer<typeof Groups>) => Object.fromEntries(g.filter((x) => x.key).map((x) => [x.key!, x.n]))
      data.orgCounts = { people: m(p), deals: d.ok ? m(d.data) : null }
    }))
  }
  if (tab === 'leads') {
    jobs.push(rpcOrThrow('leads_get', { p_query: { archived: query.archived, filters: leadFilters(query) } }, z.array(Lead)).then((r) => {
      data.leads = r
      data.lead = r.find((l) => l.id === sel.lead) ?? r[0] ?? null
    }))
    jobs.push(rpc('pipelines_get', {}, z.array(Pipeline), { quiet: true }).then((r) => { data.pipelines = r.ok ? r.data : null }))
  }
  if (tab === 'timeline') {
    const w = timelineWeeks(now, tz)
    jobs.push(rpcOrThrow('activities_get', { p_query: { from: w.from, to: w.to } }, Activities).then((r) => {
      data.timeline = { weeks: w.weeks, today: w.today, activities: r.rows }
    }))
  }
  if (tab === 'dupes' || tab === 'import') {
    jobs.push(rpcOrThrow('settings_get', {}, Settings).then((s) => {
      for (const k of ['dedupe_name', 'dedupe_email', 'dedupe_orgnr', 'dedupe_phone', 'second_admin', 'import_consent']) data.settings[k] = settingValue(s, k)
    }))
  }
  if (tab === 'dupes') jobs.push(rpcOrThrow('duplicates_get', { p_scan: false }, z.array(Duplicate)).then((r) => { data.duplicates = r }))
  if (tab === 'import') {
    jobs.push(rpcOrThrow('imports_get', {}, z.array(ImportRow)).then((r) => { data.imports = r }))
    jobs.push(rpcOrThrow('fields_get', { p_entity: null }, z.array(Field)).then((r) => { data.fields = r }))
  }
  if (tab === 'restore') jobs.push(rpcOrThrow('deleted_get', {}, z.array(Deleted)).then((r) => { data.deleted = r }))
  if (sel.person) jobs.push(loadPersonDetail(sel.person).then((r) => { data.detail = r }))
  await Promise.all(jobs)

  if (tab === 'orgs' && data.orgs) {
    const row = data.orgs.find((o) => o.id === sel.org) ?? data.orgs[0]
    if (row) {
      const [relations, people] = await Promise.all([
        rpcOrThrow('org_relations', { p_org: row.id }, Relations),
        rpcOrThrow('rec_list', { p_entity: 'person', p_query: { filters: [{ f: 'organization_id', op: 'eq', v: row.id }], limit: 50, sort: { f: 'name', dir: 'asc' } } }, list(Person)),
      ])
      data.org = { row, relations, people: people.rows }
    }
  }
  return data
}

// ---------------------------------------------------------------------------
// reads the server actions share
export const listAll = pageAll
export { Settings as SettingsSchema, list as listSchema, DealCard }
