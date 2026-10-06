import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'

/** The Inbox's reads (0020 mail, 0022 calls). Every result is parsed; nothing is cast. */
const num = z.coerce.number()
const str = z.string()
const nstr = z.string().nullable()
const uuid = z.string().uuid()

export const MAILBOX_STATUSES = ['connecting', 'syncing', 'synced', 'reauth', 'error', 'disconnected'] as const
export const THREAD_STATUSES = ['new', 'waiting_on_you', 'replied', 'waiting_on_contact'] as const
export const MESSAGE_STATES = ['draft', 'awaiting_review', 'scheduled', 'queued', 'sending', 'sent', 'failed', 'canceled', 'received'] as const


export const Folders = z.object({
  connected: z.boolean(),
  inbox: num,
  teams: z.array(z.object({ mailbox_id: uuid, address: str, unread: num })),
  outbox: num,
  review: num,
  group: num,
  unlinked: num,
})
export type Folders = z.infer<typeof Folders>

const Link = z.object({ entity: str, id: uuid, title: str, linked_by: str })
export type ThreadLink = z.infer<typeof Link>

export const ThreadRow = z.object({
  id: uuid,
  subject: str,
  snippet: str,
  last_message_at: nstr,
  from_name: nstr,
  unread: z.boolean(),
  status: z.enum(THREAD_STATUSES),
  archived: z.boolean(),
  labels: z.array(uuid),
  links: z.array(Link),
  mailbox: z.object({ id: uuid, address: str, provider: z.enum(['google', 'microsoft']), kind: z.enum(['personal', 'team']) }).nullable(),
  opens: num,
})
export type ThreadRow = z.infer<typeof ThreadRow>

// an address in a message: a plain string or {address, name}, as providers and the composer store them
const Addr = z.union([str.transform((a) => ({ address: a, name: null as string | null })), z.object({ address: str, name: nstr.optional() }).transform((a) => ({ address: a.address, name: a.name ?? null }))])

const Message = z.object({
  id: uuid,
  direction: z.enum(['in', 'out']),
  from_addr: str,
  from_name: nstr,
  to: z.array(Addr),
  cc: z.array(Addr),
  subject: str,
  body_text: nstr,
  state: z.enum(MESSAGE_STATES),
  at: str,
  scheduled_at: nstr,
  failure_code: nstr,
  tracking: z.boolean(),
  attachments: z.array(z.object({ id: uuid, filename: str, mime: str, size: num })),
  track: z.object({
    opens: num, prefetch: num, last_open: nstr,
    clicks: z.array(z.object({ label: str, count: num, last: nstr })),
  }).nullable(),
})
export type Message = z.infer<typeof Message>

const Insight = z.object({
  state: z.enum(['requested', 'ready', 'failed']),
  summary: nstr,
  sentiment: z.enum(['positive', 'neutral', 'negative']).nullable(),
  readiness: num.nullable(),
  reason: nstr,
  action_items: z.array(z.unknown()).transform((xs) => xs.filter((x): x is string => typeof x === 'string')),
  suggested_replies: z.array(z.unknown()).transform((xs) => xs.filter((x): x is string => typeof x === 'string')),
  generated_at: nstr,
  stale: z.boolean(),
})

export const Thread = ThreadRow.extend({
  visibility: z.enum(['private', 'shared']),
  version: num,
  participants: z.array(z.object({ address: str, name: nstr, person_id: uuid.nullable() })),
  suggested: z.array(z.object({ person_id: uuid, name: str, email: str })),
  messages: z.array(Message),
  insight: Insight.nullable(),
})
export type Thread = z.infer<typeof Thread>

export const Mailbox = z.object({
  id: uuid,
  kind: z.enum(['personal', 'team']),
  provider: z.enum(['google', 'microsoft']),
  address: str,
  display_name: nstr,
  owner_id: uuid.nullable(),
  owner: nstr,
  status: z.enum(MAILBOX_STATUSES),
  last_synced_at: nstr,
  default_visibility: z.enum(['private', 'shared']),
  signature: nstr,
  mine: z.boolean().nullable(),
  can_reply: z.boolean(),
  members: z.array(z.object({ staff_id: uuid, name: str, can_reply: z.boolean() })),
})
export type Mailbox = z.infer<typeof Mailbox>

export const Mailboxes = z.object({
  mailboxes: z.array(Mailbox),
  aliases: z.array(z.object({ id: uuid, address: str, kind: z.enum(['send_as', 'bcc_accepted']), verified_at: nstr })),
  dropbox: nstr,
  tracking: z.enum(['on', 'off', 'per_email']),
})
export type Mailboxes = z.infer<typeof Mailboxes>

export const Template = z.object({
  id: uuid, name: str, scope: z.enum(['private', 'shared']), is_starter: z.boolean(), owner: nstr,
  subject: str, body: str, mine: z.boolean().nullable(),
})
export type Template = z.infer<typeof Template>

export const MergeField = z.object({ token: str, source: str, format: str })

export const Label = z.object({ id: uuid, name: str, bg: str, ink: str, entity: str })
export type Label = z.infer<typeof Label>

export const Outbox = z.object({
  messages: z.array(z.object({
    id: uuid, thread_id: uuid, subject: str, to: z.array(Addr), state: z.enum(MESSAGE_STATES), scheduled_at: nstr,
    failure_code: nstr, failure_reason: nstr, attempt: num, source: str, created_at: str,
  })),
  groups: z.array(z.object({ id: uuid, subject: str, total: num, state: str, created_at: str, sent: num, failed: num })),
})
export type Outbox = z.infer<typeof Outbox>

export const GroupPreview = z.object({
  consent_mode: z.enum(['off', 'warn', 'block']),
  limit: num.nullable(),
  recipients: z.array(z.object({ person_id: uuid, name: str, email: nstr, excluded: nstr })),
})
export type GroupPreview = z.infer<typeof GroupPreview>

export const Calls = z.object({
  telephony: nstr,
  calls: z.array(z.object({
    activity_id: uuid, at: str, direction: z.enum(['outbound', 'inbound']), outcome: z.enum(['connected', 'no_answer', 'missed', 'busy', 'voicemail']),
    duration_s: num.nullable(), number: nstr, person_id: uuid.nullable(), person: nstr, deal_id: uuid.nullable(), note: nstr, source: str,
  })),
})
export type Calls = z.infer<typeof Calls>

export const PhoneMatch = z.array(z.object({ person_id: uuid, name: str, organization: nstr, deal_id: uuid.nullable() }))
export type PhoneMatch = z.infer<typeof PhoneMatch>

const Pipelines = z.array(z.object({ id: uuid, name: str, stages: z.array(z.object({ id: uuid, name: str, open_deals: num })) }))
export type Pipelines = z.infer<typeof Pipelines>
const Views = z.object({ views: z.array(z.object({ id: uuid, name: str })) })

export const loadFolders = () => rpcOrThrow('inbox_folders', {}, Folders)
export const loadThreads = (folder: 'inbox' | 'team' | 'archive' | 'all', query: { label?: string; mailbox?: string }) =>
  rpcOrThrow('threads_get', { p_folder: folder, p_query: { ...query, limit: 100 } }, z.array(ThreadRow))
/** Opening a thread marks it read for the caller (thread_get). A thread that went away gives null. */
export const loadThread = async (id: string) => {
  const r = await rpc('thread_get', { p_id: id }, Thread)
  return r.ok ? r.data : null
}
export const loadMailboxes = () => rpcOrThrow('mailboxes_get', {}, Mailboxes)
export const loadTemplates = () => rpcOrThrow('templates_get', {}, z.array(Template))
export const loadMergeFields = () => rpcOrThrow('merge_fields_get', {}, z.array(MergeField))
export const loadLabels = () => rpcOrThrow('labels_get', { p_entity: 'email_thread' }, z.array(Label))
export const loadOutbox = () => rpcOrThrow('outbox_get', {}, Outbox)
export const loadCalls = () => rpcOrThrow('call_log_get', { p_limit: 100 }, Calls)
/** The drop-box local part; created on first use. */
export const loadDropbox = () => rpcOrThrow('dropbox_address_get', { p_entity: null, p_record: null }, z.object({ local_part: str }))
export const loadPipelines = async () => {
  const r = await rpc('pipelines_get', {}, Pipelines, { quiet: true })
  return r.ok ? r.data : []
}
/** Saved views of people (the Contacts screen's), the group email's «saved view» source. */
export const loadPeopleViews = async () => {
  const r = await rpc('views_get', { p_screen: 'contacts' }, Views, { quiet: true })
  return r.ok ? r.data.views : []
}
/** The open deals of a stage, the group email's «deals list» source. */
export const loadStageDeals = async (stage: string) => {
  const r = await rpc('rec_list', {
    p_entity: 'deal',
    p_query: { filters: [{ f: 'stage_id', op: 'eq', v: stage }, { f: 'status', op: 'eq', v: 'open' }], limit: 500 },
  }, z.object({ rows: z.array(z.object({ id: uuid })) }))
  return r.ok ? r.data.rows.map((x) => x.id) : []
}
export const loadGroupPreview = (source: { kind: 'people'; ids: string[] } | { kind: 'deals'; ids: string[] } | { kind: 'view'; view_id: string }) =>
  rpc('group_send_preview', { p_source: source }, GroupPreview)
/** Active staff, for a team mailbox's members. */
export const loadStaff = async () => {
  const r = await rpc('staff_list', {}, z.array(z.object({ id: uuid, name: str, active: z.boolean() })), { quiet: true })
  return r.ok ? r.data.filter((s) => s.active).map(({ id, name }) => ({ id, name })) : []
}
