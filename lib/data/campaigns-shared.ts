import { z } from 'zod'

/**
 * What the Campaigns route shares between server and client (Marketing.dc.html, route campaigns; 0037): the tab
 * keys, the shapes the campaign functions return (deviations/campaigns-schema.md), the design model the builder
 * edits, and the pure helpers that edit a design or turn the segment editor's conditions into a people filter.
 * The database checks everything again (app.campaign_design_check, app.filter_sql).
 */

// ---------------------------------------------------------------------------
// tabs: the address keeps the values Lead capture links to (?tab=builder|audience|deliverability)
export const CAMPAIGN_TABS = ['campaigns', 'builder', 'audience', 'deliverability'] as const
export type CampaignTab = (typeof CAMPAIGN_TABS)[number]
/** The pill each tab lights in the shared Marketing pill row (CaptureTabs). */
export const TAB_PILL = { campaigns: 'campaigns', builder: 'builder', audience: 'audience', deliverability: 'deliver' } as const

// ---------------------------------------------------------------------------
// enumerations (contract «Enumerations shown on screen»)
export const CAMPAIGN_TYPES = ['newsletter', 'one_off', 'promotion', 'product_announcement', 'automated'] as const
export type CampaignType = (typeof CAMPAIGN_TYPES)[number]
export const CAMPAIGN_STATUSES = ['draft', 'scheduled', 'sending', 'sent', 'active', 'paused', 'canceled'] as const
export type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number]
/** The language an email is written in: its own words (the footer) follow it (campaigns.language, 0040). */
export const CAMPAIGN_LANGUAGES = ['nb', 'nn', 'en', 'sv'] as const
export type CampaignLanguage = (typeof CAMPAIGN_LANGUAGES)[number]
export const HOLD_REASONS = ['not_connected:email', 'sender_domain', 'audience'] as const
export const RECIPIENT_STATES = ['queued', 'sent', 'delivered', 'soft_bounced', 'bounced', 'complained', 'failed', 'skipped'] as const
export type RecipientState = (typeof RECIPIENT_STATES)[number]
export const SKIP_REASONS = ['not_subscribed', 'suppressed', 'no_email', 'duplicate', 'over_allowance'] as const
export const MARKETING_STATUSES = ['subscribed', 'no_consent', 'pending', 'unsubscribed', 'bounced', 'archived'] as const
export type MarketingStatus = (typeof MARKETING_STATUSES)[number]
export const ROW_KINDS = ['header', 'title', 'paragraph', 'list', 'image', 'button', 'divider', 'social', 'html', 'video', 'icons', 'menu', 'footer'] as const
export type RowKind = (typeof ROW_KINDS)[number]
export const BACKGROUNDS = ['card', 'soft_yellow', 'mint', 'cream'] as const
export type Background = (typeof BACKGROUNDS)[number]
export const PADDINGS = [22, 14, 32] as const
export type Padding = (typeof PADDINGS)[number]
export const BORDERS = ['none', 'hairline'] as const
export type Border = (typeof BORDERS)[number]
/** The builder's background swatches: the design's bgMap (Card, Soft yellow, Mint, Cream). */
export const BG_HEX: Record<Background, string> = { card: '#FFFDF6', soft_yellow: '#FBEBBE', mint: '#CFE7E4', cream: '#FCF6E9' }

// ---------------------------------------------------------------------------
// the design model (CMP-01, V-P6C-26): rows of blocks, the footer fixed as the last row
const Item = z.union([z.string(), z.object({ label: z.string(), href: z.string().optional() })])
export type Item = z.infer<typeof Item>
export const Row = z.object({
  kind: z.enum(ROW_KINDS),
  text: z.string().optional(),
  fs: z.number().optional(),
  bg: z.enum(BACKGROUNDS).optional(),
  padding: z.coerce.number().optional(),
  border: z.enum(BORDERS).optional(),
  src: z.string().optional(),
  href: z.string().optional(),
  alt: z.string().optional(),
  html: z.string().optional(),
  items: z.array(Item).optional(),
})
export type Row = z.infer<typeof Row>
export const Design = z.object({ rows: z.array(Row) })
export type Design = z.infer<typeof Design>

export const BLANK_DESIGN: Design = { rows: [{ kind: 'header', bg: 'card' }, { kind: 'footer', bg: 'cream' }] }

/** The design's palette (Marketing.dc.html, palette), plus Icons (D-42: the small omission CMP-01 names). */
export const PALETTE: { kind: RowKind; glyph: string }[] = [
  { kind: 'title', glyph: 'T' }, { kind: 'paragraph', glyph: '¶' }, { kind: 'list', glyph: '☰' }, { kind: 'image', glyph: '▣' },
  { kind: 'button', glyph: '▭' }, { kind: 'divider', glyph: '—' }, { kind: 'social', glyph: '◎' }, { kind: 'html', glyph: '</>' },
  { kind: 'video', glyph: '▶' }, { kind: 'menu', glyph: '≡' }, { kind: 'icons', glyph: '✦' },
]

/** A new row of a kind; the words are left for the author (no invented copy). */
export function newRow(kind: RowKind): Row {
  switch (kind) {
    case 'title': return { kind, text: '', fs: 22 }
    case 'paragraph': return { kind, text: '' }
    case 'list': return { kind, items: [] }
    case 'button': return { kind, text: '', href: '' }
    case 'social': return { kind, items: [{ label: 'LinkedIn', href: '' }, { label: 'Facebook', href: '' }, { label: 'Instagram', href: '' }] }
    case 'menu': return { kind, items: [] }
    case 'icons': return { kind, items: [] }
    case 'html': return { kind, html: '' }
    default: return { kind }
  }
}

/** Rows a design may take: the footer is fixed (one, last), and only its background changes (D-27). */
export const isFixed = (r: Row) => r.kind === 'footer'

/** Inserts a row before the footer (the design's palette splice). */
export function addRow(d: Design, kind: RowKind): { design: Design; index: number } {
  const rows = [...d.rows]
  const at = rows.length > 0 && rows[rows.length - 1]!.kind === 'footer' ? rows.length - 1 : rows.length
  rows.splice(at, 0, newRow(kind))
  return { design: { rows }, index: at }
}

/** Moves a row one step; the footer never moves and nothing moves below it. */
export function moveRow(d: Design, i: number, dir: -1 | 1): { design: Design; index: number } {
  const j = i + dir
  const rows = [...d.rows]
  if (j < 0 || j >= rows.length || isFixed(rows[i]!) || isFixed(rows[j]!)) return { design: d, index: i }
  ;[rows[i], rows[j]] = [rows[j]!, rows[i]!]
  return { design: { rows }, index: j }
}

/** Removes a row; the footer cannot be removed (the prototype's Remove deleted it — a bug, spec §1). */
export function removeRow(d: Design, i: number): { design: Design; index: number } {
  const r = d.rows[i]
  if (!r || isFixed(r)) return { design: d, index: i }
  const rows = d.rows.filter((_, k) => k !== i)
  return { design: { rows }, index: Math.max(0, Math.min(i, rows.length - 1)) }
}

export function patchRow(d: Design, i: number, patch: Partial<Row>): Design {
  const r = d.rows[i]
  if (!r) return d
  const next: Row = isFixed(r) ? { kind: 'footer', bg: patch.bg ?? r.bg } : { ...r, ...patch }
  return { rows: d.rows.map((x, k) => (k === i ? next : x)) }
}

/** The design as the database stores it: empty optional strings left out, so the check sees only real values. */
export function cleanDesign(d: Design): Design {
  return {
    rows: d.rows.map((r) => {
      if (r.kind === 'footer') return r.bg ? { kind: 'footer', bg: r.bg } : { kind: 'footer' }
      const o: Row = { kind: r.kind }
      if (r.text !== undefined) o.text = r.text
      if (r.fs !== undefined) o.fs = r.fs
      if (r.bg) o.bg = r.bg
      if (r.padding !== undefined) o.padding = r.padding
      if (r.border) o.border = r.border
      if (r.src) o.src = r.src.trim()
      if (r.href) o.href = r.href.trim()
      if (r.alt) o.alt = r.alt
      if (r.html !== undefined && r.kind === 'html') o.html = r.html
      if (r.items) o.items = r.items.map((x) => (typeof x === 'string' ? x : x.href?.trim() ? { label: x.label, href: x.href.trim() } : { label: x.label }))
      return o
    }),
  }
}

export const itemLabel = (x: Item) => (typeof x === 'string' ? x : x.label)
export const itemHref = (x: Item) => (typeof x === 'string' ? undefined : x.href || undefined)

// ---------------------------------------------------------------------------
// shapes the functions return (parsed, never cast)
const n = z.coerce.number()
const nn = z.number().nullable()
const ts = z.string().nullable()
const uuid = z.string().uuid()

export const Stats = z.object({
  recipients: n, sent: n, queued: n, skipped: n, failed: n, delivered: n, bounced: n, bounced_hard: n, bounced_soft: n,
  bounce_rate: nn, tracking: z.boolean(),
  unique_opens: nn, total_opens: nn, unique_clicks: nn, total_clicks: nn, open_rate: nn, click_rate: nn, ctor: nn,
  unsubscribed: n, unsub_rate: nn, complaints: n, complaint_rate: nn, a_metric: nn, b_metric: nn,
  signups: nn, mrr_won: nn, mrr_excluded_currency: nn,
})
export type Stats = z.infer<typeof Stats>

const Audience = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('segment'), segment_id: uuid.nullable(), name: z.string().nullable(), count: nn, matches: nn, live: z.boolean() }),
  z.object({ kind: z.literal('workflow'), workflows: z.array(z.object({ id: uuid, name: z.string(), state: z.string() })) }),
])

export const CampaignRow = z.object({
  id: uuid,
  seq: n,
  name: z.string(),
  type: z.enum(CAMPAIGN_TYPES),
  status: z.enum(CAMPAIGN_STATUSES),
  hold_reason: z.string().nullable(),
  owner_id: uuid.nullable(),
  owner: z.string().nullable(),
  mine: z.boolean().nullable(),
  audience: Audience,
  scheduled_at: ts, started_at: ts, sent_at: ts, canceled_at: ts,
  stream: z.string().nullable(),
  sender_domain: z.string().nullable(),
  subject_a: z.string(),
  subject_b: z.string().nullable(),
  ab: z.object({ percent: nn, metric: z.string().nullable(), wait_hours: nn, winner: z.string().nullable(), decided_at: ts, decides_at: ts }).nullable(),
  notify_owners: z.boolean(),
  version: n,
  updated_at: z.string(),
  stats: Stats.nullable(),
  reports: z.boolean(),
})
export type CampaignRow = z.infer<typeof CampaignRow>

export const CampaignDetail = CampaignRow.extend({
  segment: z.object({ id: uuid, name: z.string(), query: z.record(z.string(), z.unknown()) }).nullable(),
  template_id: uuid.nullable(),
  design: Design,
  html: z.string().nullable(),
  rendered_html: z.string().nullable(),
  preheader: z.string().nullable(),
  sender_domain_id: uuid.nullable(),
  from_name: z.string().nullable(),
  from: z.string().nullable(),
  postal_address: z.string().nullable(),
  product: z.string().nullable(),
  coupon_code: z.string().nullable(),
  language: z.enum(CAMPAIGN_LANGUAGES),
  utm: z.object({ source: z.string(), medium: z.string(), campaign: z.string() }),
  tracking: z.boolean(),
  tracking_rule: z.string().nullable(),
  visibility: z.string(),
  links: z.array(z.object({ id: uuid, url: z.string(), label: z.string().nullable(), clicks: nn })),
  top_locations: z.array(z.string()).nullable(),
  provider_connected: z.boolean(),
  domain: z.object({ authenticated: z.boolean(), verified: z.boolean() }).nullable(),
})
export type CampaignDetail = z.infer<typeof CampaignDetail>

export const CampaignList = z.object({ rows: z.array(CampaignRow), provider_connected: z.boolean() })

export const Compare = z.object({
  rows: z.array(z.object({ id: uuid, name: z.string(), type: z.enum(CAMPAIGN_TYPES), status: z.enum(CAMPAIGN_STATUSES), sent_at: ts, stats: Stats.nullable() })),
  axis_max: n,
})
export type Compare = z.infer<typeof Compare>

export const Recipient = z.object({
  id: uuid, person_id: uuid.nullable(), name: z.string().nullable(), email: z.string().nullable(), state: z.enum(RECIPIENT_STATES),
  skip_reason: z.string().nullable(), variant: z.string().nullable(), sent_at: ts, delivered_at: ts, opened_at: ts, clicked_at: ts,
  unsubscribed_at: ts, complained_at: ts, bounce_kind: z.string().nullable(),
})
export type Recipient = z.infer<typeof Recipient>
export const Recipients = z.object({ rows: z.array(Recipient), stats: Stats.nullable() })

export const Preview = z.object({
  subject_a: z.string().nullable(), subject_b: z.string().nullable(), preheader: z.string().nullable(), html: z.string().nullable(),
  missing: z.array(z.string()), unknown: z.array(z.string()), audience_missing: z.array(z.object({ token: z.string(), people: n })),
})
export type Preview = z.infer<typeof Preview>

export const Template = z.object({
  id: uuid, name: z.string(), layout: z.boolean(), category: z.string().nullable(), scope: z.string(), subject: z.string().nullable(),
  design: Design.nullable(), html: z.string().nullable(), current_version: n, version: n, updated_at: z.string(), owner: z.string().nullable(),
  mine: z.boolean().nullable(),
})
export type Template = z.infer<typeof Template>

export const Segment = z.object({
  id: uuid, name: z.string(), description: z.string().nullable(), query: z.record(z.string(), z.unknown()), shared: z.boolean(),
  mine: z.boolean().nullable(), owner: z.string().nullable(), updated_at: z.string(), matches: n, receivable: n,
})
export type Segment = z.infer<typeof Segment>
export const Counts = z.object({ matches: n, receivable: n })
export type Counts = z.infer<typeof Counts>

export const SenderDomain = z.object({
  id: uuid, domain: z.string(), stream: z.enum(['marketing', 'transactional']), sends_here: z.boolean(), product: z.string().nullable(),
  from_name: z.string(), from_local: z.string(), reply_to: z.string().nullable(), postal_address: z.string().nullable(),
  spf_ok: z.boolean().nullable(), dkim_ok: z.boolean().nullable(), dmarc_policy: z.string().nullable(), verified_at: ts,
  authenticated: z.boolean(), verified: z.boolean(), last_checked_at: ts, check_detail: z.record(z.string(), z.unknown()).nullable(), version: n,
  warmup: z.object({ day: n, days: n, done: z.boolean() }).nullable(),
  rates: z.object({ sent: n, delivered: n, bounce_rate: nn, complaint_rate: nn }).nullable(),
})
export type SenderDomain = z.infer<typeof SenderDomain>
export const SenderDomains = z.object({ rows: z.array(SenderDomain), provider_connected: z.boolean() })

export const Recommendation = z.object({
  kind: z.enum(['dns_missing', 'dmarc_none', 'bounce_rate', 'hygiene', 'identity']),
  level: z.string(),
  domain: z.string().optional(),
  records: z.array(z.string()).optional(),
  rate: z.number().optional(),
  count: z.number().optional(),
  months: z.number().optional(),
  ok: z.boolean().optional(),
  domains_missing_address: z.array(z.string()).optional(),
})
export type Recommendation = z.infer<typeof Recommendation>

export const Hygiene = z.object({
  enabled: z.boolean(), months: nn, count: nn, people: z.array(z.object({ id: uuid, name: z.string(), email: z.string().nullable() })),
})
export type Hygiene = z.infer<typeof Hygiene>

export const StatusSummary = z.object({
  statuses: z.array(z.object({ status: z.enum(MARKETING_STATUSES), n })),
  suppressed: n,
  double_opt_in: z.string().nullable(),
})
export type StatusSummary = z.infer<typeof StatusSummary>

export const ConsentEntry = z.object({
  id: n, at: z.string(), person_id: uuid.nullable(), name: z.string().nullable(), email: z.string().nullable(),
  prev_status: z.string().nullable(), status: z.string(), source: z.string(), basis: z.string().nullable(), ref_type: z.string().nullable(),
  ref_id: z.string().nullable(), detail: z.string().nullable(), ref_label: z.string().nullable(), text_version: nn, actor: z.string().nullable(),
})
export type ConsentEntry = z.infer<typeof ConsentEntry>
export const ConsentLog = z.object({ rows: z.array(ConsentEntry), next: nn })

export const Suppression = z.object({
  hash: z.string(), scope: z.string(), reason: z.string(), campaign_id: z.string().nullable(), created_at: z.string(), by: z.string().nullable(),
  email: z.string().nullable(),
})
export type Suppression = z.infer<typeof Suppression>

// ---------------------------------------------------------------------------
// the segment editor: conditions in the design's Where / AND / OR list, stored as the people filter (0023, 0037)
export type FieldKind = 'text' | 'number' | 'enum' | 'days' | 'since'
export type FieldDef = { f: string; group: 'person' | 'location' | 'organization' | 'product' | 'activity' | 'engagement'; kind: FieldKind; options?: readonly string[] }
export const ORG_STATUSES = ['trial', 'active', 'past_due', 'suspended', 'free', 'cancelled', 'expired'] as const
export const MEMBER_ROLES = ['daglig_leder', 'avdelingsleder', 'verneombud'] as const
export const SEGMENT_FIELDS: FieldDef[] = [
  { f: 'title', group: 'person', kind: 'text' },
  { f: 'marketing_status', group: 'person', kind: 'enum', options: MARKETING_STATUSES },
  { f: 'source', group: 'person', kind: 'text' },
  { f: 'city', group: 'location', kind: 'text' },
  { f: 'fylke', group: 'location', kind: 'text' },
  { f: 'organization.name', group: 'organization', kind: 'text' },
  { f: 'organization.employees', group: 'organization', kind: 'number' },
  { f: 'organization.industry', group: 'organization', kind: 'text' },
  { f: 'organization.nace', group: 'organization', kind: 'text' },
  { f: 'organization.status', group: 'organization', kind: 'enum', options: ORG_STATUSES },
  { f: 'organization.city', group: 'organization', kind: 'text' },
  { f: 'organization.fylke', group: 'organization', kind: 'text' },
  { f: 'organization.postal_code', group: 'organization', kind: 'text' },
  { f: 'member.role', group: 'product', kind: 'enum', options: MEMBER_ROLES },
  // days since a survey round last opened in the person's tenants: tenant-level dates only (D-19; 0040, R-CAMPAIGNS-03)
  { f: 'product.last_round_days', group: 'activity', kind: 'since' },
  { f: 'engagement.opened_days', group: 'engagement', kind: 'days' },
  { f: 'engagement.clicked_days', group: 'engagement', kind: 'days' },
]
export const fieldDef = (f: string) => SEGMENT_FIELDS.find((x) => x.f === f)

export const OPS_BY_KIND: Record<FieldKind, readonly Op[]> = {
  text: ['eq', 'neq', 'contains', 'in'],
  number: ['between', 'gte', 'lte', 'eq'],
  enum: ['eq', 'neq', 'in'],
  days: ['lte'],
  since: ['gte', 'lte', 'empty'],
}
export type Op = 'eq' | 'neq' | 'contains' | 'in' | 'gte' | 'lte' | 'between' | 'empty'
export type Cond = { join: 'and' | 'or'; f: string; op: Op; v: string; v2?: string }
type Filter = { f: string; op: string; v?: unknown }

const listOf = (s: string) => s.split(',').map((x) => x.trim()).filter(Boolean)

function condFilters(c: Cond): Filter[] {
  const def = fieldDef(c.f)
  const num = def?.kind === 'number' || def?.kind === 'days' || def?.kind === 'since'
  const val = (s: string) => (num ? Number(s) : s.trim())
  if (c.op === 'empty') return [{ f: c.f, op: 'empty' }]
  if (c.op === 'between') return [{ f: c.f, op: 'gte', v: Number(c.v) }, { f: c.f, op: 'lte', v: Number(c.v2 ?? '') }]
  if (c.op === 'in') return [{ f: c.f, op: 'in', v: listOf(c.v).map((x) => (num ? Number(x) : x)) }]
  return [{ f: c.f, op: c.op, v: val(c.v) }]
}

/** Is a condition complete enough to send? (A half-typed one is left out of the live count.) */
export function condReady(c: Cond): boolean {
  const def = fieldDef(c.f)
  if (!def || !OPS_BY_KIND[def.kind].includes(c.op)) return false
  if (c.op === 'empty') return true
  const num = def.kind === 'number' || def.kind === 'days' || def.kind === 'since'
  const okNum = (s: string | undefined) => s !== undefined && s.trim() !== '' && Number.isFinite(Number(s))
  if (c.op === 'between') return okNum(c.v) && okNum(c.v2)
  if (c.op === 'in') return listOf(c.v).length > 0 && (!num || listOf(c.v).every((x) => Number.isFinite(Number(x))))
  return num ? okNum(c.v) : c.v.trim() !== ''
}

/**
 * The list as the people filter: an OR joins a condition to the one above it into an either-or group, and the
 * groups are all required (V-CAMPAIGNS-11). «between» is a pair of gte and lte on the field.
 */
export function toQuery(conds: Cond[]): { filters: unknown[] } {
  const groups: Cond[][] = []
  for (const c of conds.filter(condReady)) {
    if (c.join === 'or' && groups.length > 0) groups[groups.length - 1]!.push(c)
    else groups.push([c])
  }
  const filters: unknown[] = []
  for (const g of groups) {
    if (g.length === 1) filters.push(...condFilters(g[0]!))
    else filters.push({ or: g.map(condFilters) })
  }
  return { filters }
}

function filterToCond(fs: Filter[], join: 'and' | 'or'): Cond | null {
  const strOf = (v: unknown) => (Array.isArray(v) ? v.join(', ') : v === null || v === undefined ? '' : String(v))
  if (fs.length === 2 && fs[0]!.f === fs[1]!.f && fs[0]!.op === 'gte' && fs[1]!.op === 'lte') {
    return { join, f: fs[0]!.f, op: 'between', v: strOf(fs[0]!.v), v2: strOf(fs[1]!.v) }
  }
  if (fs.length !== 1) return null
  const x = fs[0]!
  const def = fieldDef(x.f)
  if (!def || !OPS_BY_KIND[def.kind].includes(x.op as Op)) return null
  return { join, f: x.f, op: x.op as Op, v: strOf(x.v) }
}

const isFilter = (x: unknown): x is Filter => !!x && typeof x === 'object' && typeof (x as Filter).f === 'string'

/** The stored filter back as the editor's list, or null when it holds something the editor cannot show. */
export function fromQuery(q: unknown): Cond[] | null {
  const filters = (q as { filters?: unknown })?.filters
  if (filters === undefined) return []
  if (!Array.isArray(filters)) return null
  const out: Cond[] = []
  for (let i = 0; i < filters.length; i++) {
    const x = filters[i]
    if (x && typeof x === 'object' && Array.isArray((x as { or?: unknown }).or)) {
      const parts = (x as { or: unknown[] }).or
      for (const [k, g] of parts.entries()) {
        if (!Array.isArray(g) || !g.every(isFilter)) return null
        const c = filterToCond(g, k === 0 ? 'and' : 'or')
        if (!c) return null
        out.push(c)
      }
      continue
    }
    if (!isFilter(x)) return null
    const next = filters[i + 1]
    const between = OPS_BY_KIND[fieldDef(x.f)?.kind ?? 'text'].includes('between')
    if (between && x.op === 'gte' && isFilter(next) && next.f === x.f && next.op === 'lte') {
      const c = filterToCond([x, next], 'and')
      if (!c) return null
      out.push(c)
      i++
      continue
    }
    const c = filterToCond([x], 'and')
    if (!c) return null
    out.push(c)
  }
  return out
}

// ---------------------------------------------------------------------------
// small helpers
/** A datetime-local value (the staff member's wall clock) for an instant, and back. */
export const toLocalInput = (d: Date) => {
  const p = (x: number) => String(x).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

/** May this staff member change this campaign? A draft of their own (add) or anyone's (edit_others). */
export const canEdit = (c: Pick<CampaignRow, 'mine'>, can: { add: boolean; editOthers: boolean }) => (c.mine ? can.add : can.editOthers)

/**
 * «Code your own HTML» starts from this: a table with the unsubscribe link. The sender's postal address is the
 * author's to add; scheduling refuses HTML without it (V-P6C-23), and the builder says so before.
 */
export const HTML_STARTER = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">\n'
  + '  <tr><td style="padding:16px 22px;font-family:Arial,sans-serif;font-size:14px;color:#191510;"></td></tr>\n'
  + '  <tr><td style="padding:16px 22px;font-family:Arial,sans-serif;font-size:11px;color:#5F5849;text-align:center;">\n'
  + '    <a href="[Unsubscribe]" style="color:#5F5849;">Meld deg av</a>\n'
  + '  </td></tr>\n</table>'
