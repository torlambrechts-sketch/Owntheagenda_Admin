import 'server-only'
import { z } from 'zod'
import { rpc, rpcOrThrow } from '@/lib/rpc'

/**
 * Activities (Activities.dc.html): the calendar and to-do rows, one activity's detail, the activity types,
 * the staff member's scheduling (reminder channels, calendar connection, booking links, availability,
 * bookings) and the pickers the edit dialog uses. Every result is parsed here.
 */
const num = z.coerce.number()
const uuid = z.string().uuid()

export const ActivityRow = z.object({
  id: uuid,
  type_id: uuid,
  subject: z.string(),
  starts_at: z.string().nullable(),
  all_day: z.boolean(),
  duration_min: num,
  priority: z.enum(['high', 'medium', 'low']),
  note: z.string().nullable(),
  done: z.boolean(),
  deal_id: uuid.nullable(),
  person_id: uuid.nullable(),
  organization_id: uuid.nullable(),
  video_provider: z.enum(['meet', 'teams', 'zoom']).nullable(),
  video_url: z.string().nullable(),
  owner_id: uuid.nullable(),
  version: num,
  type: z.object({ key: z.string(), name: z.string(), glyph: z.string() }).nullable(),
  owner: z.object({ name: z.string().nullable(), initials: z.string().nullable() }).nullable(),
  deal: z.object({ id: uuid, title: z.string() }).nullable(),
  organization: z.string().nullable(),
  person: z.string().nullable(),
  guests: num,
  declined: num,
  overdue: z.boolean().nullable(),
  custom: z.record(z.string(), z.unknown()),
})
export type ActivityRow = z.infer<typeof ActivityRow>

const Counts = z.object({ all: num, overdue: num, today: num, week: num, done: num })
export type Counts = z.infer<typeof Counts>
const ActivitiesResult = z.object({ rows: z.array(ActivityRow), counts: Counts })

export type ActivitiesQuery = {
  from?: string
  to?: string
  owner_ids?: string[]
  type_ids?: string[]
  status?: 'open' | 'done' | 'all'
  tab?: 'all' | 'overdue' | 'today' | 'week' | 'done'
  deal_id?: string
}
export const loadActivities = (q: ActivitiesQuery) => rpc('activities_get', { p_query: q }, ActivitiesResult)

const Guest = z.object({
  email: z.string(),
  name: z.string().nullable(),
  person_id: uuid.nullable(),
  response: z.enum(['needs_action', 'accepted', 'tentative', 'declined']),
})
export type Guest = z.infer<typeof Guest>
const Channel = z.enum(['app', 'email', 'desktop', 'push'])
export type Channel = z.infer<typeof Channel>
export const ActivityDetail = ActivityRow.extend({
  guest_list: z.array(Guest),
  reminders: z.array(z.object({ channel: Channel, offset_min: num })),
})
export type ActivityDetail = z.infer<typeof ActivityDetail>
export const loadActivityDetail = (id: string) => rpc('activity_detail', { p_id: id }, ActivityDetail)

export const ActivityType = z.object({ id: uuid, key: z.string(), name: z.string(), glyph: z.string(), ord: num, active: z.boolean(), is_system: z.boolean() })
export type ActivityType = z.infer<typeof ActivityType>
export const loadActivityTypes = () => rpcOrThrow('activity_types_get', {}, z.array(ActivityType))

const Staff = z.object({ id: uuid, name: z.string(), initials: z.string().nullable(), active: z.boolean() })
export type StaffOption = z.infer<typeof Staff>
export const loadStaff = () => rpcOrThrow('staff_list', {}, z.array(Staff))

const BookingLink = z.object({
  id: uuid,
  slug: z.string(),
  kind: z.enum(['general', 'proposed']),
  title: z.string(),
  description: z.string().nullable(),
  duration_min: num,
  buffer_min: num,
  horizon_days: num,
  video_provider: z.enum(['meet', 'teams', 'zoom']).nullable(),
  expires_at: z.string().nullable(),
})
export type BookingLink = z.infer<typeof BookingLink>
export const Scheduling = z.object({
  prefs: z.object({ channels: z.array(Channel), default_offset: num, next_step_prompt: z.boolean() }),
  email: z.string().nullable(),
  calendar: z
    .object({
      provider: z.enum(['google', 'microsoft']),
      account_email: z.string().nullable(),
      calendar_id: z.string().nullable(),
      mode: z.enum(['one_way', 'two_way']),
      sync_type_ids: z.array(uuid),
      status: z.enum(['not_connected', 'connected', 'error']),
      last_synced_at: z.string().nullable(),
    })
    .nullable(),
  links: z.array(BookingLink),
  availability: z.array(z.object({ weekday: num, hour: num })),
  bookings: z.array(z.object({ name: z.string().nullable(), starts_at: z.string(), link: z.string(), created_at: z.string() })),
})
export type Scheduling = z.infer<typeof Scheduling>
export const loadScheduling = () => rpcOrThrow('my_scheduling', {}, Scheduling)

const DealOption = z.object({ id: uuid, title: z.string(), organization_id: uuid.nullable(), person_id: uuid.nullable() })
export type DealOption = z.infer<typeof DealOption>
export const loadDealOptions = async () => {
  const r = await rpc('deal_list', { p_query: { status: 'open', limit: 500, sort: [{ f: 'title', dir: 'asc' }] } }, z.object({ rows: z.array(DealOption) }))
  return r.ok ? r.data.rows : []
}

const PersonOption = z.object({ id: uuid, name: z.string(), email: z.string().nullable() })
export type PersonOption = z.infer<typeof PersonOption>
export const loadPeopleOptions = async () => {
  const r = await rpc('rec_list', { p_entity: 'person', p_query: { limit: 500, sort: { f: 'name', dir: 'asc' }, filters: [{ f: 'email', op: 'notempty' }] } }, z.object({ rows: z.array(PersonOption) }))
  return r.ok ? r.data.rows : []
}

const Field = z.object({
  id: uuid,
  key: z.string(),
  label: z.string(),
  type: z.string(),
  options: z.array(z.object({ key: z.string(), label: z.string().optional(), name: z.string().optional() })),
  activity_type_ids: z.array(uuid).nullable().optional(),
  readonly: z.boolean(),
})
export type CustomField = z.infer<typeof Field>
export const loadActivityFields = async () => {
  const r = await rpc('fields_get', { p_entity: 'activity' }, z.array(Field))
  return r.ok ? r.data : []
}
