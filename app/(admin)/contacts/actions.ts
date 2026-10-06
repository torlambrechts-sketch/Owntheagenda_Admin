'use server'

import { z } from 'zod'
import { rpc, type RpcCode } from '@/lib/rpc'
import { Duplicate, Field, listAll, Organization, Person, peopleFilters, leadFilters, Staff } from '@/lib/data/contacts'
import { MAX_BYTES, MAX_ROWS, parseCsv, parseNumber, suggestMapping, targetsFor, type ImportEntity } from '@/lib/data/contacts-import'
import { EXPORT_COLUMNS, exportHeader, toCsv } from '@/lib/data/contacts-export'

/** Every action parses its input and answers { ok: true, … } or { ok: false, code }. */
type Fail = { ok: false; code: RpcCode | 'too_large' | 'empty_file' | 'too_many_rows' }
type Ok<T = object> = { ok: true } & T
const fail = (code: Fail['code']): Fail => ({ ok: false, code })
const bad = fail('invalid')

const id = z.string().min(1).max(64)
const ids = z.array(id).min(1).max(500)
const entity = z.enum(['person', 'organization', 'lead'])
const text = (max: number) => z.string().trim().max(max)

// ---------------------------------------------------------------------------
// create and edit (rec_save). Values are the registered columns a form writes, owner, labels and custom.
const common = { owner_id: id.nullable().optional(), labels: z.array(id).max(50).optional(), custom: z.record(z.string(), z.unknown()).optional() }
const opt = (max: number) => text(max).nullable().optional()
const VALUES = {
  person: z.object({
    name: text(200).min(1), email: opt(254), phone: opt(40), organization_id: id.nullable().optional(), title: opt(80),
    contact_type: z.enum(['prospect', 'trial_user', 'customer_user', 'former_customer', 'partner', 'other']).nullable().optional(),
    source: opt(60), city: opt(80), fylke: opt(60), linkedin: opt(200), ...common,
  }),
  organization: z.object({
    name: text(200).min(1), org_number: z.string().regex(/^\d{9}$/).nullable().optional(), address: opt(200), postal_code: opt(12),
    city: opt(80), fylke: opt(60), industry: opt(80), employees: z.number().int().min(0).nullable().optional(), website: opt(200),
    phone: opt(40), email: opt(254), source: opt(60), ...common,
  }),
  lead: z.object({
    title: text(200).min(1), person_id: id.nullable().optional(), organization_id: id.nullable().optional(),
    value: z.number().min(0).nullable().optional(), source: opt(60), ...common,
  }),
}
const Saved = z.object({ id: z.string(), version: z.number() })

export async function saveRecord(input: { entity: string; id: string | null; version: number | null; values: unknown }): Promise<Ok<{ id: string }> | Fail> {
  const e = entity.safeParse(input.entity)
  if (!e.success) return bad
  const v = VALUES[e.data].safeParse(input.values)
  const head = z.object({ id: id.nullable(), version: z.number().int().nullable() }).safeParse(input)
  if (!v.success || !head.success) return bad
  const values: Record<string, unknown> = { ...v.data }
  for (const k of Object.keys(values)) if (values[k] === '' ) values[k] = null
  const r = await rpc('rec_save', { p_entity: e.data, p_id: head.data.id, p_values: values, p_version: head.data.version }, Saved)
  return r.ok ? { ok: true, id: r.data.id } : fail(r.code)
}

export async function deleteRecord(input: { entity: string; id: string }): Promise<Ok | Fail> {
  const p = z.object({ entity, id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_delete', { p_entity: p.data.entity, p_ids: [p.data.id] }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

/** What a create or edit form chooses from: organizations, people, owners and the custom fields. */
export async function formOptions(input: { entity: string }): Promise<Ok<{ orgs: { id: string; name: string }[]; people: { id: string; name: string }[]; fields: z.infer<typeof Field>[] }> | Fail> {
  const e = entity.safeParse(input.entity)
  if (!e.success) return bad
  try {
    const [orgs, people, fields] = await Promise.all([
      listAll('organization', { sort: { f: 'name', dir: 'asc' } }, Organization),
      e.data === 'lead' ? listAll('person', { sort: { f: 'name', dir: 'asc' } }, Person) : Promise.resolve([]),
      rpc('fields_get', { p_entity: e.data }, z.array(Field)),
    ])
    return {
      ok: true,
      orgs: orgs.map((o) => ({ id: o.id, name: o.name })),
      people: people.map((p) => ({ id: p.id, name: p.name })),
      fields: fields.ok ? fields.data : [],
    }
  } catch {
    return fail('failed')
  }
}

// ---------------------------------------------------------------------------
// the person drawer
export async function setLabels(input: { entity: string; id: string; version: number; labels: string[] }): Promise<Ok | Fail> {
  const p = z.object({ entity, id, version: z.number().int(), labels: z.array(id).max(50) }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_save', { p_entity: p.data.entity, p_id: p.data.id, p_values: { labels: p.data.labels }, p_version: p.data.version }, Saved)
  return r.ok ? { ok: true } : fail(r.code)
}

export async function setConsent(input: { person: string; status: string; source: string; basis: string }): Promise<Ok | Fail> {
  const p = z.object({
    person: id, status: z.enum(['subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced']), source: text(60).min(1), basis: text(200),
  }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('consent_set', { p_person: p.data.person, p_status: p.data.status, p_source: p.data.source, p_basis: p.data.basis || null }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

/** A note; «@Ingrid» or «@Ingrid Solberg» mentions an active staff member, who is notified. */
export async function saveNote(input: { entity: string; id: string; body: string; parent?: string | null }): Promise<Ok<{ mentioned: number; undelivered: boolean }> | Fail> {
  const p = z.object({ entity, id, body: text(10000).min(1), parent: id.nullable().optional() }).safeParse(input)
  if (!p.success) return bad
  const staff = await rpc('staff_list', {}, z.array(Staff))
  const body = p.data.body.toLowerCase()
  const mentions = staff.ok
    ? staff.data.filter((s) => s.active && (body.includes(`@${s.name.toLowerCase()}`) || new RegExp(`@${s.name.split(' ')[0]!.toLowerCase()}(?![\\p{L}])`, 'u').test(body))).map((s) => s.id)
    : []
  const args = { p_entity: p.data.entity, p_id: p.data.id, p_note: null, p_body: p.data.body, p_pinned: false, p_parent: p.data.parent ?? null }
  const r = await rpc('note_save', { ...args, p_mentions: mentions }, z.unknown(), { quiet: mentions.length > 0 })
  if (r.ok) return { ok: true, mentioned: mentions.length, undelivered: false }
  // note_save's notification route («/contacts?person=…») fails app.notifications' route check, so a note
  // with a mention is refused as a whole (requests/contacts.md R-1); the note is kept without the mention
  if (r.code === 'failed' && mentions.length) {
    const again = await rpc('note_save', { ...args, p_mentions: [] }, z.unknown())
    return again.ok ? { ok: true, mentioned: 0, undelivered: true } : fail(again.code)
  }
  return fail(r.code)
}

export async function pinNote(input: { entity: string; id: string; note: string; pinned: boolean }): Promise<Ok | Fail> {
  const p = z.object({ entity, id, note: id, pinned: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('note_save', { p_entity: p.data.entity, p_id: p.data.id, p_note: p.data.note, p_body: '', p_pinned: p.data.pinned }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

// ---------------------------------------------------------------------------
// organizations
export async function setRelation(input: { a: string; b: string; kind: string }): Promise<Ok | Fail> {
  const p = z.object({ a: id, b: id, kind: z.enum(['parent', 'daughter', 'related', 'none']) }).safeParse(input)
  if (!p.success || p.data.a === p.data.b) return bad
  const r = await rpc('org_relation_set', { p_a: p.data.a, p_b: p.data.b, p_kind: p.data.kind, p_note: null }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

// ---------------------------------------------------------------------------
// leads
export async function archiveLeads(input: { ids: string[]; archived: boolean }): Promise<Ok<{ n: number }> | Fail> {
  const p = z.object({ ids, archived: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = p.data.ids.length === 1
    ? await rpc('rec_save', { p_entity: 'lead', p_id: p.data.ids[0], p_values: { archived_at: p.data.archived ? new Date().toISOString() : null } }, Saved)
    : await rpc('rec_bulk', { p_entity: 'lead', p_ids: p.data.ids, p_values: { archived_at: p.data.archived ? new Date().toISOString() : null } }, z.unknown())
  return r.ok ? { ok: true, n: p.data.ids.length } : fail(r.code)
}

/** Adds one label to each lead, keeping its others: leads with the same resulting set share one rec_bulk. */
export async function labelLeads(input: { ids: string[]; label: string }): Promise<Ok<{ n: number }> | Fail> {
  const p = z.object({ ids, label: id }).safeParse(input)
  if (!p.success) return bad
  const cur = await rpc('rec_list', { p_entity: 'lead', p_query: { ids: p.data.ids, limit: 500 } }, z.object({ rows: z.array(z.object({ id: z.string(), labels: z.array(z.string()) })) }))
  if (!cur.ok) return fail(cur.code)
  const groups = new Map<string, string[]>()
  for (const l of cur.data.rows) {
    if (l.labels.includes(p.data.label)) continue
    const next = JSON.stringify([...l.labels, p.data.label])
    groups.set(next, [...(groups.get(next) ?? []), l.id])
  }
  for (const [labels, members] of groups) {
    const r = await rpc('rec_bulk', { p_entity: 'lead', p_ids: members, p_values: { labels: JSON.parse(labels) } }, z.unknown())
    if (!r.ok) return fail(r.code)
  }
  return { ok: true, n: cur.data.rows.length }
}

export async function leadActivities(input: { ids: string[]; type_id: string; subject: string; starts_at: string }): Promise<Ok<{ n: number }> | Fail> {
  const p = z.object({ ids, type_id: id, subject: text(200).min(1), starts_at: z.string().datetime({ offset: true }) }).safeParse(input)
  if (!p.success) return bad
  const leads = await rpc('rec_list', { p_entity: 'lead', p_query: { ids: p.data.ids, limit: 500 } }, z.object({ rows: z.array(z.object({ id: z.string(), person_id: z.string().nullable(), organization_id: z.string().nullable() })) }))
  if (!leads.ok) return fail(leads.code)
  let n = 0
  for (const l of leads.data.rows) {
    const r = await rpc('rec_save', {
      p_entity: 'activity', p_id: null,
      p_values: { type_id: p.data.type_id, subject: p.data.subject, starts_at: p.data.starts_at, lead_id: l.id, person_id: l.person_id, organization_id: l.organization_id },
    }, Saved)
    if (!r.ok) return fail(r.code)
    n++
  }
  return { ok: true, n }
}

export async function convertLead(input: { lead: string; pipeline: string; stage: string }): Promise<Ok<{ deal: string }> | Fail> {
  const p = z.object({ lead: id, pipeline: id, stage: id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('lead_convert', { p_lead: p.data.lead, p_pipeline: p.data.pipeline, p_stage: p.data.stage }, z.object({ deal_id: z.string() }))
  return r.ok ? { ok: true, deal: r.data.deal_id } : fail(r.code)
}

// ---------------------------------------------------------------------------
// duplicates
export async function scanDuplicates(): Promise<Ok<{ n: number }> | Fail> {
  const r = await rpc('duplicates_get', { p_scan: true }, z.array(Duplicate))
  return r.ok ? { ok: true, n: r.data.length } : fail(r.code)
}

export async function dismissDuplicate(input: { id: string }): Promise<Ok | Fail> {
  const p = z.object({ id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('duplicate_dismiss', { p_id: p.data.id }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

export async function mergeRecords(input: { entity: string; keep: string; merge: string }): Promise<Ok | Fail> {
  const p = z.object({ entity: z.enum(['person', 'organization']), keep: id, merge: id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('records_merge', { p_entity: p.data.entity, p_keep: p.data.keep, p_merge: p.data.merge, p_values: {} }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

export async function setRule(input: { key: string; on: boolean }): Promise<Ok | Fail> {
  const p = z.object({ key: z.enum(['dedupe_name', 'dedupe_email', 'dedupe_orgnr', 'dedupe_phone']), on: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('setting_set', { p_key: p.data.key, p_value: p.data.on ? 'on' : 'off' }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

// ---------------------------------------------------------------------------
// import: the file's text travels with each step and is parsed here, never trusted from the browser
const ImportIn = z.object({ entity, text: z.string().max(MAX_BYTES * 2), mapping: z.array(z.string().nullable()).max(500) })

const parse = (t: string) => {
  if (new TextEncoder().encode(t).length > MAX_BYTES) return fail('too_large')
  const csv = parseCsv(t)
  if (!csv.headers.length || !csv.rows.length) return fail('empty_file')
  if (csv.rows.length > MAX_ROWS) return fail('too_many_rows')
  return csv
}

const customFields = async (e: ImportEntity) => {
  const f = await rpc('fields_get', { p_entity: e }, z.array(Field))
  return f.ok ? f.data.filter((x) => !x.readonly && !x.formula).map((x) => ({ key: x.key, label: x.label, type: x.type })) : []
}

export async function importPreview(input: { entity: string; text: string }): Promise<Ok<{ headers: string[]; rows: number; mapping: (string | null)[] }> | Fail> {
  const p = z.object({ entity, text: z.string().max(MAX_BYTES * 2) }).safeParse(input)
  if (!p.success) return bad
  const csv = parse(p.data.text)
  if ('ok' in csv) return csv
  return { ok: true, headers: csv.headers, rows: csv.rows.length, mapping: suggestMapping(p.data.entity, csv.headers, await customFields(p.data.entity)) }
}

/** The rows ready for import_run: lookups resolved to ids, numbers read, empty cells left out. */
async function buildRows(e: ImportEntity, rows: string[][], mapping: (string | null)[]) {
  const targets = targetsFor(e, await customFields(e))
  const cols = mapping.map((k) => (k ? targets.find((t) => t.key === k) ?? null : null))
  const needOrg = cols.some((c) => c?.kind === 'lookup_org')
  const needPerson = cols.some((c) => c?.kind === 'lookup_person')
  const orgs = needOrg ? await listAll('organization', {}, Organization) : []
  const people = needPerson ? await listAll('person', {}, Person) : []
  const orgByName = new Map(orgs.map((o) => [o.name.toLowerCase(), o.id]))
  const orgByNr = new Map(orgs.filter((o) => o.org_number).map((o) => [o.org_number!, o.id]))
  const personByEmail = new Map(people.filter((x) => x.email).map((x) => [x.email!.toLowerCase(), x.id]))
  return rows.map((r) => {
    const out: Record<string, unknown> = {}
    const custom: Record<string, unknown> = {}
    cols.forEach((t, i) => {
      const v = r[i] ?? ''
      if (!t || v === '') return
      if (t.kind === 'lookup_org') {
        const hit = t.key === 'org_nr' ? orgByNr.get(v.replace(/\D/g, '')) : orgByName.get(v.toLowerCase())
        if (hit) out.organization_id = hit
      } else if (t.kind === 'lookup_person') {
        const hit = personByEmail.get(v.toLowerCase())
        if (hit) out.person_id = hit
      } else if (t.kind === 'int' || t.kind === 'numeric') out[t.col] = parseNumber(v)
      else if (t.kind === 'custom_number') custom[t.col] = parseNumber(v)
      else if (t.kind === 'custom_text') custom[t.col] = v
      else out[t.col] = v
    })
    if (Object.keys(custom).length) out.custom = custom
    return out
  })
}

const Count = z.object({ total: z.coerce.number() })

/** How many rows match a record that exists (the same key import_run matches on: email, org.nr). */
export async function importCheck(input: { entity: string; text: string; mapping: (string | null)[] }): Promise<Ok<{ matches: number | null }> | Fail> {
  const p = ImportIn.safeParse(input)
  if (!p.success) return bad
  const csv = parse(p.data.text)
  if ('ok' in csv) return csv
  const key = p.data.entity === 'person' ? 'email' : p.data.entity === 'organization' ? 'org_number' : null
  const col = key ? p.data.mapping.indexOf(key) : -1
  if (!key || col < 0) return { ok: true, matches: key ? 0 : null }
  const values = csv.rows.map((r) => r[col] ?? '').filter(Boolean).map((v) => (key === 'org_number' ? v.replace(/\D/g, '') : v.trim()))
  const uniq = [...new Set([...values, ...values.map((v) => v.toLowerCase())])]
  let found = new Set<string>()
  for (let i = 0; i < uniq.length; i += 1000) {
    const r = await rpc('rec_list', { p_entity: p.data.entity, p_query: { filters: [{ f: key, op: 'in', v: uniq.slice(i, i + 1000) }], limit: 500 } }, z.object({ rows: z.array(z.record(z.string(), z.unknown())) }).and(Count))
    if (!r.ok) return fail(r.code)
    found = new Set([...found, ...r.data.rows.map((x) => String(x[key] ?? '').toLowerCase())])
  }
  return { ok: true, matches: values.filter((v) => found.has(v.toLowerCase())).length }
}

const Run = z.object({ id: z.string(), rows_read: z.number(), created: z.number(), merged: z.number(), skipped: z.number() })

export async function importRun(input: { entity: string; text: string; file: string; mapping: (string | null)[]; mode: string; consent: boolean }): Promise<Ok<z.infer<typeof Run>> | Fail> {
  const p = ImportIn.extend({ file: text(200), mode: z.enum(['merge', 'create', 'skip']), consent: z.boolean() }).safeParse(input)
  if (!p.success) return bad
  const csv = parse(p.data.text)
  if ('ok' in csv) return csv
  const rows = await buildRows(p.data.entity, csv.rows, p.data.mapping)
  const mapping = Object.fromEntries(csv.headers.map((h, i) => [h, p.data.mapping[i] ?? null]))
  const r = await rpc('import_run', { p_entity: p.data.entity, p_rows: rows, p_dup_mode: p.data.mode, p_file: p.data.file || null, p_mapping: mapping, p_require_consent: p.data.consent }, Run)
  return r.ok ? { ok: true, ...r.data } : fail(r.code)
}

export async function importSkips(input: { id: string }): Promise<Ok<{ rows: { row: number; reason: string | null }[] }> | Fail> {
  const p = z.object({ id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('import_skips', { p_import: p.data.id }, z.array(z.object({ row: z.number(), reason: z.string().nullable() })))
  return r.ok ? { ok: true, rows: r.data } : fail(r.code)
}

export async function importRevert(input: { id: string }): Promise<Ok | Fail> {
  const p = z.object({ id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('import_revert', { p_import: p.data.id }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}


// ---------------------------------------------------------------------------
// export: exactly the rows the staff member sees, written by the app and recorded with export_log
const ExportIn = z.object({
  entity: z.enum(['person', 'organization', 'lead', 'deal', 'activity', 'catalog_item']),
  scope: z.enum(['current', 'full']),
  query: z.object({ q: text(100), type: text(40), consent: text(40), label: text(64), archived: z.boolean(), leadLabel: text(64) }),
})

export async function exportCsv(input: unknown): Promise<Ok<{ csv: string; rows: number }> | Fail> {
  const p = ExportIn.safeParse(input)
  if (!p.success) return bad
  const { entity: e, scope, query } = p.data
  const current = scope === 'current'
  const q = current && e === 'person' ? { q: query.q, filters: peopleFilters(query) }
    : current && e === 'lead' ? { filters: [...leadFilters(query), { f: 'archived_at', op: query.archived ? 'notempty' : 'empty' }] }
    : {}
  try {
    const rows = await listAll(e, { ...q, sort: { f: e === 'activity' ? 'starts_at' : 'created_at', dir: 'asc' } }, z.record(z.string(), z.unknown()))
    const cols = EXPORT_COLUMNS[e]!
    const csv = toCsv(cols.map(exportHeader), rows.map((r) => cols.map((c) => r[c] ?? '')))
    const log = await rpc('export_log', { p_entity: e, p_rows: rows.length, p_format: 'csv', p_scope: scope }, z.unknown())
    if (!log.ok) return fail(log.code)
    return { ok: true, csv, rows: rows.length }
  } catch (err) {
    const code = (err as { code?: RpcCode }).code
    return fail(code ?? 'failed')
  }
}

// ---------------------------------------------------------------------------
export async function restoreRecord(input: { entity: string; id: string }): Promise<Ok | Fail> {
  const p = z.object({ entity: z.string().regex(/^[a-z_]{2,40}$/), id }).safeParse(input)
  if (!p.success) return bad
  const r = await rpc('rec_restore', { p_entity: p.data.entity, p_ids: [p.data.id] }, z.unknown())
  return r.ok ? { ok: true } : fail(r.code)
}

