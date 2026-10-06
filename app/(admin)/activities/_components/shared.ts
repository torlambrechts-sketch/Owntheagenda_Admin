import type { ActivityRow, ActivityType, StaffOption } from '@/lib/data/activities'

export type Tab = 'calendar' | 'todo' | 'scheduler' | 'reminders'
export type CalView = 'day' | 'week' | 'month'
export type Status = 'open' | 'done' | 'all'
export type ListTab = 'all' | 'overdue' | 'today' | 'week' | 'done'
export type Sort = 'due' | 'prio'

export type Rights = { add: boolean; editOthers: boolean; bulk: boolean }
export type Me = { id: string; name: string; initials: string | null; email: string }

export type Ctx = {
  tz: string
  today: string // YYYY-MM-DD in the staff member's zone
  me: Me
  rights: Rights
  types: ActivityType[]
  staff: StaffOption[]
}

/** The design's activity-type palette (Activities.dc.html, tc): fill and edge per type key. */
const TONE: Record<string, [string, string]> = {
  call: ['bg-sage', 'border-ok'],
  meeting: ['bg-blue-bg', 'border-blue-mid'],
  task: ['bg-sand', 'border-warn'],
  deadline: ['bg-apricot', 'border-alert'],
  email: ['bg-lilac', 'border-lilac-mid'],
  lunch: ['bg-tile', 'border-line-strong'],
  demo: ['bg-blue-bg', 'border-blue-mid'],
}
const BAR: Record<string, string> = {
  call: 'bg-ok', meeting: 'bg-blue-mid', task: 'bg-warn', deadline: 'bg-alert', email: 'bg-lilac-mid', lunch: 'bg-line-strong', demo: 'bg-blue-mid',
}
export const tone = (key: string | undefined) => TONE[key ?? ''] ?? TONE.lunch!
export const bar = (key: string | undefined) => BAR[key ?? ''] ?? BAR.lunch!

/** «8:30»: the design writes hours without a leading zero. */
export const hm = (h: number, min: number) => `${h}:${String(min).padStart(2, '0')}`

export const canEdit = (ctx: Ctx, a: Pick<ActivityRow, 'owner_id'>) => a.owner_id === ctx.me.id || ctx.rights.editOthers

/** The design's soft pill (type chips, list tabs, reminder chips). */
export const chip = (on: boolean) =>
  `cursor-pointer rounded-999 border ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`

export const PRIORITIES = ['high', 'medium', 'low'] as const
export const PRIO_BG = { high: 'bg-peach', medium: 'bg-highlight', low: 'bg-surface' } as const

/** The type's name as the screen shows it (system types in the staff member's language). */
export const typeName = (ctx: Ctx, a: Pick<ActivityRow, 'type_id' | 'type'>) => ctx.types.find((x) => x.id === a.type_id)?.name ?? a.type?.name ?? ''
