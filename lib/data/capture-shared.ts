import { z } from 'zod'

/**
 * What Lead capture and Web visitors share between server and client (Marketing.dc.html, routes leadgen and
 * visitors; 0031): the tab keys, the shapes the capture functions return, and the pure helpers that edit a form's
 * draft or word a time. The database checks every draft again (app.form_check).
 */

// ---------------------------------------------------------------------------
// tabs: the design's eight pills. The first four are the Campaigns route's (phase 6); Web visitors is its own route.
export const LEAD_TABS = ['forms', 'chat', 'prospect'] as const
export type LeadTab = (typeof LEAD_TABS)[number]
export const PILLS = ['campaigns', 'builder', 'audience', 'deliver', 'forms', 'chat', 'prospect', 'visitors'] as const
export type Pill = (typeof PILLS)[number]

// ---------------------------------------------------------------------------
// forms
export const FORM_KINDS = ['contact', 'registration', 'gated_download', 'file_upload', 'blank'] as const
export type FormKind = (typeof FORM_KINDS)[number]
export const FORM_LANGS = ['nb', 'nn', 'en', 'sv'] as const
export type FormLang = (typeof FORM_LANGS)[number]
export const FIELD_KINDS = ['short_text', 'email', 'phone', 'marketing_status', 'custom_field', 'file_upload', 'message'] as const
export type FieldKind = (typeof FIELD_KINDS)[number]
/** Where a short text may save (app.form_check). */
export const TEXT_MAPS = ['person.name', 'person.title', 'organization.name', 'organization.org_number'] as const
export const HIDDEN = ['utm', 'referrer_host', 'landing_path', 'page_vars'] as const

export const Field = z.object({
  key: z.string(),
  kind: z.enum(FIELD_KINDS),
  label: z.string().optional(),
  map: z.string().optional(),
  required: z.boolean().optional(),
  placeholder: z.string().optional(),
})
export type Field = z.infer<typeof Field>

export const AfterSubmit = z.object({
  creates: z.enum(['lead', 'deal']).optional(),
  pipeline_id: z.string().uuid().optional(),
  stage_id: z.string().uuid().optional(),
  ticket: z.boolean().optional(),
  sequence_id: z.string().uuid().optional(),
  thank_you: z.string().optional(),
  redirect_url: z.string().optional(),
  asset_path: z.string().optional(),
})
export type AfterSubmit = z.infer<typeof AfterSubmit>

export const Draft = z.object({
  intro: z.object({ title: z.string(), body: z.string().optional() }),
  fields: z.array(Field),
  hidden: z.array(z.enum(HIDDEN)).optional(),
  consent: z.object({ text_key: z.string(), double_opt_in: z.boolean().optional() }).optional(),
  after_submit: AfterSubmit.optional(),
  notice: z.string().optional(),
})
export type Draft = z.infer<typeof Draft>

const num = z.coerce.number()
export const FormRow = z.object({
  id: z.string().uuid(),
  name: z.string(),
  kind: z.enum(FORM_KINDS),
  language: z.enum(FORM_LANGS),
  status: z.enum(['active', 'inactive']),
  current_version: num,
  public_id: z.string(),
  public_url: z.string(),
  version: num,
  updated_at: z.string(),
  owner: z.object({ id: z.string().uuid(), name: z.string() }).passthrough().nullable(),
  submissions_month: num,
  views_month: num,
  landing: z.string().nullable(),
})
export type FormRow = z.infer<typeof FormRow>

export const FormDetail = FormRow.extend({
  draft: Draft,
  published: Draft.nullable(),
  versions: z.array(z.object({ version: num, published_at: z.string(), by: z.string().nullable() })),
  consent_texts: z.array(z.object({ id: z.string().uuid(), key: z.string(), body: z.string(), version: num })),
  settings: z.object({ double_opt_in: z.string(), form_tracking: z.string(), email_connected: z.boolean() }),
})
export type FormDetail = z.infer<typeof FormDetail>

export const Submission = z.object({
  id: z.string().uuid(),
  state: z.enum(['accepted', 'spam', 'duplicate']),
  created_at: z.string(),
  person: z.object({ id: z.string().uuid(), name: z.string(), email: z.string().nullable() }).nullable(),
  lead_id: z.string().uuid().nullable(),
  deal_id: z.string().uuid().nullable(),
  ticket_id: z.string().uuid().nullable(),
  consent: z.object({ given: z.boolean().optional(), status: z.string().optional() }).passthrough(),
})
export type Submission = z.infer<typeof Submission>

// ---------------------------------------------------------------------------
// chat
export const TEMPLATES = ['leads', 'meetings', 'qualify_route', 'live_chat'] as const
export type Template = (typeof TEMPLATES)[number]
export const STEP_KINDS = ['message', 'question', 'handoff'] as const
export const STEP_MAPS = ['person.name', 'person.email', 'person.phone', 'organization.name', 'organization.org_number'] as const
export const PALETTES = ['cream', 'mint', 'card'] as const
export const BUTTONS = ['saffron', 'ink'] as const

export const Step = z.object({ key: z.string(), kind: z.enum(STEP_KINDS), text: z.string(), map: z.enum(STEP_MAPS).optional() })
export type Step = z.infer<typeof Step>

export const Playbook = z.object({
  id: z.string().uuid(),
  name: z.string(),
  template: z.enum(TEMPLATES),
  state: z.enum(['draft', 'live']),
  pages: z.array(z.string()),
  site_ids: z.array(z.string().uuid()),
  theme: z.object({ palette: z.string().optional(), button: z.string().optional() }).passthrough(),
  profile: z.object({ name: z.string().optional(), avatar: z.string().optional(), language: z.string().optional() }).passthrough(),
  steps: z.array(Step),
  creates: z.enum(['lead', 'deal']),
  pipeline_id: z.string().uuid().nullable(),
  stage_id: z.string().uuid().nullable(),
  queue_wait_seconds: num,
  offline_message: z.string().nullable(),
  current_version: num,
  version: num,
  owner: z.object({ id: z.string().uuid(), name: z.string() }).nullable(),
  conversations_30d: num,
  completed_30d: num,
})
export type Playbook = z.infer<typeof Playbook>

export const PlaybookStats = z.object({
  conversations: num,
  completed: num,
  live: num,
  drop_off: z.array(z.object({ step: z.string(), n: num })),
})
export type PlaybookStats = z.infer<typeof PlaybookStats>

const Staff = z.object({ id: z.string().uuid(), name: z.string(), initials: z.string().nullable() })
export const ChatRow = z.object({
  id: z.string().uuid(),
  state: z.enum(['bot', 'queued', 'live', 'closed']),
  page_path: z.string().nullable(),
  started_at: z.string(),
  completed: z.boolean(),
  lead_id: z.string().uuid().nullable(),
  deal_id: z.string().uuid().nullable(),
  playbook: z.object({ id: z.string().uuid(), name: z.string(), template: z.string() }).nullable(),
  site: z.string().nullable(),
  company: z.object({ org_number: z.string(), name: z.string().nullable(), visits_30d: num }).nullable(),
  claimed_by: Staff.nullable(),
  messages: num,
  last_message_at: z.string().nullable(),
})
export type ChatRow = z.infer<typeof ChatRow>
export const ChatQueue = z.object({ rows: z.array(ChatRow), online: z.boolean(), staff_online: num })
export type ChatQueue = z.infer<typeof ChatQueue>
export const ChatDetail = ChatRow.extend({
  read_only: z.boolean(),
  transcript: z.array(z.object({ id: num, sender: z.enum(['bot', 'visitor', 'staff', 'system']), body: z.string(), at: z.string(), staff: z.string().nullable() })),
})
export type ChatDetail = z.infer<typeof ChatDetail>

export const Site = z.object({
  id: z.string().uuid(),
  hostname: z.string(),
  key: z.string(),
  active: z.boolean(),
  chat_enabled: z.boolean(),
  last_seen_at: z.string().nullable(),
  sessions_7d: num,
  snippet: z.string(),
})
export type Site = z.infer<typeof Site>

// ---------------------------------------------------------------------------
// prospects
export const PROSPECT_FILTERS = { person: ['title', 'department', 'location'], organization: ['size', 'industry', 'revenue', 'keyword'] } as const
export type ProspectFilter = (typeof PROSPECT_FILTERS)['person'][number] | (typeof PROSPECT_FILTERS)['organization'][number]
export const ProspectUsage = z.object({
  connected: z.boolean(),
  contact_rule: z.string(),
  used_month: num,
  limit: num.nullable(),
  revealed_month: num,
})
export type ProspectUsage = z.infer<typeof ProspectUsage>
export const SavedFilter = z.object({ id: z.string().uuid(), name: z.string(), query: z.record(z.string(), z.unknown()), mine: z.boolean() })
export type SavedFilter = z.infer<typeof SavedFilter>

// ---------------------------------------------------------------------------
// web visitors
export const PERIODS = [30, 90, 365] as const
export const CHANNELS = ['direct', 'organic_search', 'paid_search', 'social', 'paid_social', 'email', 'referral', 'partner', 'other'] as const
export const VisitorRow = z.object({
  rank: num,
  org_number: z.string(),
  name: z.string().nullable(),
  industry: z.string().nullable(),
  city: z.string().nullable(),
  country: z.string().nullable(),
  source: z.string().nullable(),
  last_visit: z.string(),
  pages: num,
  sessions: num,
  in_crm: z.boolean(),
  organization_id: z.string().uuid().nullable(),
})
export type VisitorRow = z.infer<typeof VisitorRow>
export const Visitors = z.object({
  rows: z.array(VisitorRow),
  days: num,
  connected: z.boolean(),
  identification: z.string(),
  sites: z.array(z.object({ id: z.string().uuid(), hostname: z.string(), last_seen_at: z.string().nullable() })),
})
export type Visitors = z.infer<typeof Visitors>
export const Visitor = z.object({
  org_number: z.string(),
  name: z.string().nullable(),
  industry: z.string().nullable(),
  city: z.string().nullable(),
  country: z.string().nullable(),
  website: z.string().nullable(),
  in_crm: z.boolean(),
  organization_id: z.string().uuid().nullable(),
  visits_30d: num,
  pageviews: z.array(z.object({ at: z.string(), path: z.string(), channel: z.string().nullable(), seconds: num.nullable() })),
})
export type Visitor = z.infer<typeof Visitor>

// ---------------------------------------------------------------------------
// draft helpers (pure)

/** The label a new field starts with, in the form's own language (the design's «Ny felt», corrected). */
const NEW_LABEL: Record<Exclude<FieldKind, 'marketing_status'>, Record<FormLang, string>> = {
  short_text: { nb: 'Nytt felt', nn: 'Nytt felt', en: 'New field', sv: 'Nytt fält' },
  email: { nb: 'E-post', nn: 'E-post', en: 'Email', sv: 'E-post' },
  phone: { nb: 'Telefon', nn: 'Telefon', en: 'Phone', sv: 'Telefon' },
  custom_field: { nb: 'Nytt felt', nn: 'Nytt felt', en: 'New field', sv: 'Nytt fält' },
  file_upload: { nb: 'Fil', nn: 'Fil', en: 'File', sv: 'Fil' },
  message: { nb: 'Melding', nn: 'Melding', en: 'Message', sv: 'Meddelande' },
}

/** May this block be added to this draft? (one consent box; files only on a file-upload form; one email field) */
export function blockAllowed(d: Draft, kind: FormKind, block: FieldKind, customFields: number): boolean {
  if (block === 'marketing_status') return !d.fields.some((f) => f.kind === 'marketing_status')
  if (block === 'file_upload') return kind === 'file_upload'
  if (block === 'email') return !d.fields.some((f) => f.kind === 'email')
  if (block === 'phone') return !d.fields.some((f) => f.kind === 'phone')
  if (block === 'custom_field') return customFields > 0
  return true
}

/** A new field of this kind at the end (before nothing: the consent box stays where it is). */
export function addField(d: Draft, kind: FieldKind, lang: FormLang, map?: string): Draft {
  const keys = new Set(d.fields.map((f) => f.key))
  const base = kind === 'marketing_status' ? 'consent' : kind
  let key = base
  for (let i = 2; keys.has(key); i++) key = `${base}_${i}`
  const f: Field = kind === 'marketing_status'
    ? { key, kind, required: false }
    : { key, kind, label: NEW_LABEL[kind][lang], required: false, ...(map ? { map } : {}) }
  return { ...d, fields: [...d.fields, f] }
}

export function moveField(d: Draft, i: number, by: -1 | 1): Draft {
  const j = i + by
  if (j < 0 || j >= d.fields.length) return d
  const fields = [...d.fields]
  const a = fields[i]!
  fields[i] = fields[j]!
  fields[j] = a
  return { ...d, fields }
}

export const removeField = (d: Draft, i: number): Draft => ({ ...d, fields: d.fields.filter((_, k) => k !== i) })

export const patchField = (d: Draft, i: number, patch: Partial<Field>): Draft => ({
  ...d,
  fields: d.fields.map((f, k) => {
    if (k !== i) return f
    const next: Field = { ...f, ...patch }
    // an empty map or placeholder is no map or placeholder
    if (!next.map) delete next.map
    if (!next.placeholder) delete next.placeholder
    return next
  }),
})

/** Is the double opt-in in force for this form? (the setting, or the form turning it on, Q3) */
export const doubleOptIn = (d: Draft, setting: string) => setting === 'on' || d.consent?.double_opt_in === true

// ---------------------------------------------------------------------------
// words for times

/** «12 min ago», «1 h ago», «Yesterday», or a date: the key and its number (messages capture.time.*). */
export function lastVisit(iso: string, now: Date): { key: 'justNow' | 'minutes' | 'hours' | 'yesterday' | 'date'; n: number } {
  const ms = now.getTime() - new Date(iso).getTime()
  const min = Math.floor(ms / 60_000)
  if (min < 1) return { key: 'justNow', n: 0 }
  if (min < 60) return { key: 'minutes', n: min }
  const h = Math.floor(min / 60)
  if (h < 24) return { key: 'hours', n: h }
  if (h < 48) return { key: 'yesterday', n: 1 }
  return { key: 'date', n: 0 }
}

/** Time on a page: «4 min», «under 1 min», or none for the last page of a session. */
export function onPage(seconds: number | null): { key: 'minutes' | 'underMinute' | 'none'; n: number } {
  if (seconds === null || seconds < 0) return { key: 'none', n: 0 }
  if (seconds < 60) return { key: 'underMinute', n: 0 }
  return { key: 'minutes', n: Math.round(seconds / 60) }
}

/** The effective value of a platform setting from settings_get (the platform row, else the default). */
export const settingValue = (rows: { key: string; default: string; values: { scope_id: string; value: string }[] }[], key: string): string | null => {
  const r = rows.find((x) => x.key === key)
  if (!r) return null
  return r.values.find((v) => v.scope_id === '')?.value ?? r.default
}
