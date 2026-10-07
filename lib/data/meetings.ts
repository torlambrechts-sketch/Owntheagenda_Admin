import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import { BOT_REASONS, CAPTURES, CONFERENCES, STATE_KEYS } from './meetings-shared'

/**
 * Meetings (Meetings.dc.html) read through the 0042 functions (contract: docs/crm-enrichment/deviations/meetings-schema.md).
 * Every shape is parsed, never cast. The worker_* functions are the service role's and are never called from here.
 */
const num = z.coerce.number()
const id = z.guid()
const iso = z.string()
const str = z.string()
const nstr = z.string().nullable()

const LinkRef = z.object({ entity: z.enum(['deal', 'lead', 'person', 'organization']), id, title: nstr, seq: num.nullish() })
export type LinkRef = z.infer<typeof LinkRef>

export const State = z.object({ key: z.enum(STATE_KEYS), n: num.optional(), reason: nstr.optional(), at: nstr.optional() })
export type State = z.infer<typeof State>

export const Row = z.object({
  id,
  title: str,
  at: iso,
  starts_at: iso.nullable(),
  ends_at: iso.nullable(),
  source: z.enum(['calendar', 'adhoc', 'upload', 'desktop']),
  conference: z.enum(CONFERENCES).nullable(),
  capture: z.enum(CAPTURES),
  group: z.enum(['upcoming', 'review', 'history']),
  state: State.nullable(),
  organization: z.object({ id, name: str }).nullable(),
  attendees: z.object({ first: nstr, others: num, total: num, external: num }).nullable(),
  link: LinkRef.nullable(),
  linked: z.boolean(),
  owner: z.object({ id, name: str, initials: nstr }).nullable(),
  is_sample: z.boolean(),
  version: num,
})
export type Row = z.infer<typeof Row>

const Status = z.string()
export const Capabilities = z.object({
  calendar: Status, meeting_bot: Status.nullable(), transcription: Status.nullable(), ai: Status.nullable(), email: Status.nullable(), slack: Status.nullable(), desktop: Status,
})
export type Capabilities = z.infer<typeof Capabilities>

export const Workspace = z.object({
  upcoming: z.array(Row),
  review: z.array(Row),
  history: z.array(Row),
  history_next: iso.nullable(),
  capabilities: Capabilities,
  can_configure: z.boolean(),
})
export type Workspace = z.infer<typeof Workspace>

export const Attendee = z.object({
  email: str, name: nstr, person_id: id.nullable(), staff_id: id.nullable(), external: z.boolean(),
  response: z.enum(['needs_action', 'accepted', 'tentative', 'declined']), notice_sent_at: iso.nullable(), opted_out: z.boolean(),
})
export type Attendee = z.infer<typeof Attendee>

export const Detail = Row.extend({
  join_url: nstr,
  visibility: z.enum(['owner', 'group', 'group_sub', 'all']),
  cancelled_at: iso.nullable(),
  can_edit: z.boolean(),
  activity_id: id.nullable(),
  links: z.object({ deal: LinkRef.nullable(), lead: LinkRef.nullable(), person: LinkRef.nullable(), organization: LinkRef.nullable(), primary: LinkRef.nullable(), linked: z.boolean() }),
  attendee_list: z.array(Attendee),
  notice: z.object({ state: z.enum(['not_required', 'pending', 'sent', 'blocked']), due_at: iso.nullable(), sent_at: iso.nullable(), setting: str, hours: num.nullable() }),
  bot: z.object({ state: z.enum(['none', 'scheduled', 'joining', 'in_call', 'removed', 'left', 'failed', 'blocked']), reason: z.enum(BOT_REASONS).nullable() }),
  recording: z.object({ id, method: z.enum(['bot', 'desktop']), state: z.enum(['recording', 'processing', 'ready', 'failed', 'deleted']), duration_s: num.nullable(), purge_after: iso.nullable(), deleted_at: iso.nullable() }).nullable(),
  transcript: z.object({
    id, source: z.enum(['provider', 'upload']), state: z.enum(['processing', 'ready', 'failed']), error_code: nstr, duration_s: num.nullable(),
    speaker_count: num.nullable(), language: nstr, file_name: nstr, ready_at: iso.nullable(),
  }).nullable(),
  recap: z.object({ state: z.enum(['requested', 'ready', 'failed', 'not_connected']), saved_at: iso.nullable(), note_id: id.nullable() }).nullable(),
  suggestions_pending: num,
  brief: z.object({ state: str, generated_at: iso.nullable(), quotes_state: str }).nullable(),
  default_tab: z.enum(['brief', 'transcript']),
  history: z.array(z.object({ at: iso, field: str, old: z.unknown(), new: z.unknown(), source: str, actor: nstr })),
  created_at: iso,
  updated_at: iso,
})
export type Detail = z.infer<typeof Detail>

const Source = z.object({ entity: str, id }).nullable()
export const Brief = z.object({
  state: str,
  generated_at: iso.nullish(),
  since_at: iso.nullish(),
  last_contact_at: iso.nullish(),
  linked: z.boolean(),
  changes: z.array(z.object({ key: str, kind: str, at: iso.nullable(), params: z.record(z.string(), z.unknown()), source: Source, checked: z.boolean() })).default([]),
  people: z.array(z.object({ person_id: id.nullable(), name: str, title: nstr, labels: z.array(str), first_meeting: z.boolean(), last_signed_in: iso.nullable(), source: Source })).default([]),
  facts: z.array(z.object({ key: str, ord: z.coerce.string(), params: z.record(z.string(), z.unknown()), source: Source })).default([]),
  quotes: z.array(z.object({ text: str, kind: z.enum(['segment', 'note']), seq: num.nullish(), meeting_id: id.nullish(), speaker: nstr, at: iso.nullable(), record: Source.optional() })).default([]),
  quotes_state: str.default('none'),
  ai: z.boolean(),
  instructions_set: z.boolean().nullish(),
})
export type Brief = z.infer<typeof Brief>

/** email: the address the label is mapped to (0050, R-MEETINGS-05); null for a person the caller may not see */
export const Speaker = z.object({ label: str, staff_id: id.nullable(), person_id: id.nullable(), name: nstr, kind: z.enum(['staff', 'external', 'unknown']), email: nstr })
export type Speaker = z.infer<typeof Speaker>
export const Segment = z.object({ seq: num, start_ms: num, end_ms: num.nullable(), label: nstr, text: str, redacted: z.boolean() })
export type Segment = z.infer<typeof Segment>
export const Transcript = z.object({ transcript: z.unknown(), speakers: z.array(Speaker), segments: z.array(Segment), next: num.nullable() })
export type Transcript = z.infer<typeof Transcript>

const Step = z.object({ text: str, seq: num.nullable(), activity_id: id.nullish() })
export const Recap = z.object({
  transcript_id: id.nullable(),
  state: z.enum(['none', 'requested', 'ready', 'failed', 'not_connected']),
  takeaways: z.array(Step),
  next_steps: z.array(Step),
  generated_at: iso.nullable(),
  saved_at: iso.nullable(),
  announced_at: iso.nullable(),
  note: z.object({ id, entity: str, record_id: id }).nullable(),
  save_target: LinkRef.nullable(),
  ai: z.boolean(),
  can_edit: z.boolean(),
})
export type Recap = z.infer<typeof Recap>

export const Suggestion = z.object({
  id, ord: num, target_entity: z.enum(['deal', 'lead', 'person', 'organization']), target_id: id.nullable(), target_title: nstr, field: str, field_label: nstr,
  /** the record's currency when the field is its money «value» (0050, R-MEETINGS-04), else null */
  currency: nstr,
  current_value: z.unknown(), proposed_value: z.unknown(), evidence: z.array(num), state: z.enum(['pending', 'accepted', 'rejected', 'stale', 'failed']),
  error_code: nstr, decided_by: nstr, decided_at: iso.nullable(), written_record_id: id.nullable(), stale_now: z.boolean(),
})
export type Suggestion = z.infer<typeof Suggestion>
export const Suggestions = z.object({ transcript_id: id.nullable(), suggestions: z.array(Suggestion) })

const UserMailbox = z.object({ id, address: str, status: str, kind: str, own: z.boolean() }).nullable()
export const UserRow = z.object({ id, name: str, title: nstr, initials: nstr, enabled: z.boolean(), bot_auto_join: z.enum(['external', 'all', 'off']), mailbox: UserMailbox, calendar: str })
export type UserRow = z.infer<typeof UserRow>
export const Controls = z.object({
  users: z.array(UserRow),
  rec_notice: z.object({ value: str, hours: num.nullable() }),
  rec_retention: z.object({ value: str, months: num.nullable() }),
  visibility_default: str,
  /** the controller a notice names: the verified transactional sender, null while there is none (0050, R-MEETINGS-01) */
  controller: nstr,
  capabilities: Capabilities,
})
export type Controls = z.infer<typeof Controls>
export const MySettings = UserRow.extend({ brief_instructions: nstr })
export type MySettings = z.infer<typeof MySettings>

const Label = z.object({ id, name: str })
export type MailboxOption = { id: string; address: string; status: string; kind: string }

export type MeetingBundle = {
  detail: Detail
  brief: Brief | null
  transcript: Transcript | null
  recap: Recap | null
  suggestions: Suggestion[]
  labels: Record<string, string>
}

// ---------------------------------------------------------------------------
export const loadWorkspace = (query: { history_before?: string; history_limit?: number; mine?: boolean } = {}) =>
  rpc('meetings_workspace', { p_query: query }, Workspace)

export const loadTranscript = (meeting: string, cursor = 0) =>
  rpc('meeting_transcript', { p_id: meeting, p_cursor: cursor, p_limit: 200 }, Transcript)

/** One meeting with everything its three tabs show; the parts read in parallel, a part that fails is left empty. */
export async function loadMeeting(meeting: string) {
  const [detail, brief, transcript, recap, suggestions] = await Promise.all([
    rpc('meeting_detail', { p_id: meeting }, Detail),
    rpc('meeting_brief', { p_id: meeting }, Brief),
    loadTranscript(meeting),
    rpc('meeting_recap', { p_id: meeting }, Recap),
    rpc('meeting_suggestions', { p_id: meeting }, Suggestions),
  ])
  if (!detail.ok) return detail
  const rows = suggestions.ok ? suggestions.data.suggestions : []
  let labels: Record<string, string> = {}
  if (rows.some((s) => s.field === 'labels')) {
    const l = await rpc('labels_get', { p_entity: null }, z.array(Label.passthrough()), { quiet: true })
    if (l.ok) labels = Object.fromEntries(l.data.map((x) => [x.id, x.name]))
  }
  const bundle: MeetingBundle = {
    detail: detail.data,
    brief: brief.ok ? brief.data : null,
    transcript: transcript.ok ? transcript.data : null,
    recap: recap.ok ? recap.data : null,
    suggestions: rows,
    labels,
  }
  return { ok: true as const, data: bundle }
}

export const loadControls = () => rpc('meeting_controls', {}, Controls)
export const loadMySettings = () => rpc('meeting_my_settings', {}, MySettings)

/** The mailboxes a staff member may point their briefs at: their own and the team boxes they belong to. */
export async function loadMailboxOptions(me: string) {
  const r = await rpc('mailboxes_get', {}, z.object({
    mailboxes: z.array(z.object({ id, kind: str, address: str, status: str, owner_id: id.nullable(), members: z.array(z.object({ staff_id: id }).passthrough()) }).passthrough()),
  }).passthrough(), { quiet: true })
  if (!r.ok) return r
  const options: MailboxOption[] = r.data.mailboxes
    .filter((m) => m.owner_id === me || m.members.some((x) => x.staff_id === me))
    .map((m) => ({ id: m.id, address: m.address, status: m.status, kind: m.kind }))
  return { ok: true as const, data: options }
}

const LINKABLE = { deal: 'title', lead: 'title', person: 'name', organization: 'name' } as const
export type Linkable = keyof typeof LINKABLE
export const searchLinkable = (entity: Linkable, q: string) =>
  rpc('rec_list', { p_entity: entity, p_query: { q, limit: 6, sort: { f: LINKABLE[entity], dir: 'asc' } } },
    z.object({ rows: z.array(z.object({ id, name: z.string().optional(), title: z.string().nullable().optional(), seq: num.nullish() }).passthrough()) }))
