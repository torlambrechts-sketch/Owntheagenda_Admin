import { z } from 'zod'

/**
 * Documents (Documents.dc.html) — the shapes the 0032 functions return, shared by the loaders, the server actions
 * and the client components. Every RPC answer is parsed with these, never cast.
 */
const id = z.string().uuid()
const num = z.coerce.number()
const str = z.string()
const ts = z.string()

export const TABS = ['docs', 'templates', 'sign', 'settings'] as const
export type Tab = (typeof TABS)[number]

export const DOC_STATUSES = ['draft', 'sent', 'opened', 'awaiting_signature', 'signed', 'declined', 'expired', 'revoked'] as const
export type DocStatus = (typeof DOC_STATUSES)[number]
export const STORAGES = ['platform', 'google', 'onedrive', 'sharepoint'] as const
export type Storage = (typeof STORAGES)[number]
export const CATEGORIES = ['quotes', 'contracts', 'presentations', 'spreadsheets', 'other'] as const
export type Category = (typeof CATEGORIES)[number]
export const KINDS = ['document', 'presentation', 'spreadsheet'] as const
export const SHARES = ['company', 'team', 'private'] as const
export const TEMPLATE_LANGUAGES = ['nb', 'nn', 'en', 'sv'] as const
export const INVITE_LANGUAGES = ['nb', 'en', 'sv'] as const
export const TABLE_COLUMNS = ['name', 'qty', 'price', 'discount', 'tax', 'total', 'period'] as const
export const FIELD_KINDS = ['signature', 'date', 'initials', 'text', 'checkbox'] as const
export type FieldKind = (typeof FIELD_KINDS)[number]
export const REQUEST_STATUSES = ['draft', 'sent', 'in_progress', 'completed', 'declined', 'canceled', 'expired'] as const
export const SIGNER_STATUSES = ['waiting', 'sent', 'opened', 'code_verified', 'signed', 'declined'] as const

/** The status pills (Documents.dc.html, S); the three D-41 adds use the design's own warning and neutral pairs. */
export const STATUS_PILL: Record<DocStatus, [string, string]> = {
  draft: ['#F2EAD6', '#5F5849'],
  sent: ['#FBEBBE', '#5C4600'],
  opened: ['#E4EEEC', '#20431C'],
  awaiting_signature: ['#F5DC96', '#5C4600'],
  signed: ['#CFE7E4', '#20431C'],
  declined: ['#FBD5C4', '#6B240C'],
  expired: ['#F2EAD6', '#5F5849'],
  revoked: ['#FBD5C4', '#6B240C'],
}

/** The signer colours (Documents.dc.html, colors); with no cap on signers (Q24) the list repeats. */
export const SIGNER_COLORS = ['#2F5D2A', '#6E8FB8', '#8F74B3', '#D4633A'] as const

/** The public host for document and signing links (D-28). It does not serve them yet. */
export const PUBLIC_HOST = 'go.owntheagenda.com'

export const DocRow = z.object({
  id,
  number: str.nullable(),
  name: str,
  status: z.enum(DOC_STATUSES),
  kind: z.enum(KINDS),
  source: z.enum(['template', 'upload']),
  template_id: id.nullable(),
  template: str.nullable(),
  deal_id: id.nullable(),
  deal_title: str.nullable(),
  organization_id: id.nullable(),
  organization_name: str.nullable(),
  opens: num,
  storage: z.enum(STORAGES),
  merge_missing: z.array(str),
  valid_until: str.nullable(),
  created_at: ts,
  has_pdf: z.boolean(),
  owner_id: id.nullable(),
  owner_name: str.nullable(),
  signature_status: z.enum(REQUEST_STATUSES).nullable(),
})
export type DocRow = z.infer<typeof DocRow>
export const DocList = z.object({ total: num, rows: z.array(DocRow) })
export type DocList = z.infer<typeof DocList>

export const Totals = z.object({
  currency: str,
  lines: num,
  mrr: num,
  one_off: num,
  tcv: num,
  vat: z.array(z.object({ rate: num, base: num, vat: num })),
  total_incl_vat: num,
  deal_value: num.nullable(),
  value_source: str.nullable(),
})
export type Totals = z.infer<typeof Totals>

export const DocLink = z.object({
  id,
  label: str.nullable(),
  recipient_name: str.nullable(),
  created_at: ts,
  expires_at: ts.nullable(),
  revoked_at: ts.nullable(),
  active: z.boolean(),
  opens: num,
})
export type DocLink = z.infer<typeof DocLink>

export const DocDetail = z.object({
  id,
  number: str.nullable(),
  name: str,
  status: z.enum(DOC_STATUSES),
  kind: z.enum(KINDS),
  source: z.enum(['template', 'upload']),
  product: str.nullable(),
  body_html: str.nullable(),
  merge_missing: z.array(str),
  totals: Totals.nullable(),
  valid_until: str.nullable(),
  storage: z.enum(STORAGES),
  has_pdf: z.boolean(),
  size_bytes: num.nullable(),
  created_at: ts,
  version: num,
  can_edit: z.boolean(),
  owner_name: str.nullable(),
  template: z.object({ id, name: str, category: z.enum(CATEGORIES), language: z.enum(TEMPLATE_LANGUAGES) }).nullable(),
  deal: z.object({ id, title: str, value: num.nullable(), currency: str }).nullable(),
  organization: z.object({ id, name: str, org_number: str.nullable() }).nullable(),
  person: z.object({ id, name: str }).nullable(),
  links: z.array(DocLink),
  opens: num,
  signature_requests: z.array(z.object({ id, status: z.enum(REQUEST_STATUSES), service: z.enum(['builtin', 'external']), created_at: ts, sent_at: ts.nullable(), completed_at: ts.nullable(), sealed: z.boolean() })),
})
export type DocDetail = z.infer<typeof DocDetail>

export const DocView = z.object({
  id: num,
  link_id: id,
  label: str.nullable(),
  recipient_name: str.nullable(),
  started_at: ts,
  duration_seconds: num,
  client_class: z.enum(['human', 'prefetch', 'unknown']),
})
export type DocView = z.infer<typeof DocView>

export const Template = z.object({
  id,
  name: str,
  kind: z.enum(KINDS),
  category: z.enum(CATEGORIES),
  share: z.enum(SHARES),
  team_id: id.nullable(),
  team_name: str.nullable(),
  product: str.nullable(),
  language: z.enum(TEMPLATE_LANGUAGES),
  source: z.enum(['platform', 'google', 'microsoft']),
  placeholders: z.array(str),
  validity_days: num.nullable(),
  number_prefix: str.nullable(),
  version: num,
  owner_id: id.nullable(),
  owner_name: str.nullable(),
  can_edit: z.boolean(),
})
export type Template = z.infer<typeof Template>

export const TemplateDetail = Template.extend({
  body_html: str.nullable(),
  product_table: z.object({ columns: z.array(z.enum(TABLE_COLUMNS)) }).nullable(),
  unknown: z.array(str),
  versions: z.array(z.object({ version: num, created_at: ts, created_by: str.nullable() })),
})
export type TemplateDetail = z.infer<typeof TemplateDetail>

export const Signer = z.object({
  id,
  ord: num,
  name: str,
  email: str,
  color: str.nullable(),
  person_id: id.nullable(),
  status: z.enum(SIGNER_STATUSES),
  signed_at: ts.nullable(),
  declined_at: ts.nullable(),
})
export type Signer = z.infer<typeof Signer>

export const SignField = z.object({ id, signer_id: id, kind: z.enum(FIELD_KINDS), page: num, x: num, y: num, w: num, h: num, required: z.boolean(), filled: z.boolean() })
export type SignField = z.infer<typeof SignField>

export const SignRequest = z.object({
  id,
  status: z.enum(REQUEST_STATUSES),
  service: z.enum(['builtin', 'external']),
  message: str.nullable(),
  language: z.enum(INVITE_LANGUAGES),
  otp_required: z.boolean(),
  signing_order: z.enum(['parallel', 'sequential']),
  version: num,
  sent_at: ts.nullable(),
  completed_at: ts.nullable(),
  expires_at: ts.nullable(),
  original_sha256: str.nullable(),
  sealed_sha256: str.nullable(),
  document: z.object({ id, name: str, number: str.nullable(), status: z.enum(DOC_STATUSES) }),
  signer_limit: num.nullable(),
  signers: z.array(Signer),
  fields: z.array(SignField),
  events: z.array(z.object({ seq: num, kind: str, at: ts, signer_name: str.nullable() })),
  chain_ok: z.boolean(),
})
export type SignRequest = z.infer<typeof SignRequest>

export const StorageState = z.object({
  default: z.object({ provider: z.enum(STORAGES), location: z.record(z.string(), z.unknown()), set_at: ts.nullable(), set_by: str.nullable() }),
  connections: z.array(z.object({ provider: z.enum(['google', 'microsoft']), account_email: str.nullable(), status: z.enum(['not_connected', 'connected', 'error']), connected_at: ts.nullable() })),
  branding: z.enum(['hidden', 'shown']),
  esign_service: z.enum(['builtin', 'external']),
  esign_connected: z.boolean(),
  email_connected: z.boolean(),
  signer_limit: num.nullable(),
  can_configure: z.boolean(),
})
export type StorageState = z.infer<typeof StorageState>

export const MergeField = z.object({ token: str, format: str })
export type MergeField = z.infer<typeof MergeField>

export type DealOption = { id: string; title: string }
export type TeamOption = { id: string; name: string }

/** What the screen may do (lib/shell can(); the database decides again). */
export type Rights = {
  meId: string
  see: boolean
  add: boolean
  editOthers: boolean
  remove: boolean
  configureDeals: boolean
  configureGlobal: boolean
}

/** A signature field's label on the page: «Signature · Kari» (the signer's first name). */
export const firstName = (name: string) => name.trim().split(/\s+/)[0] ?? name
