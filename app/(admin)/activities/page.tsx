import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import {
  loadActivities, loadActivityDetail, loadActivityFields, loadActivityTypes, loadDealOptions, loadPeopleOptions, loadScheduling, loadStaff,
  type ActivitiesQuery,
} from '@/lib/data/activities'
import { addDays, daysInMonth, fromZoned, mondayOf, parseYmd, ymd, zoned, type Day } from '@/lib/data/activities-time'
import { ActivitiesScreen, type ModalData } from './_components/ActivitiesScreen'
import type { CalView, ListTab, Sort, Status, Tab } from './_components/shared'

type SP = Record<string, string | string[] | undefined>
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)
const pick = <T extends string>(v: string | undefined, allowed: readonly T[], d: T): T => (allowed.includes(v as T) ? (v as T) : d)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Activities (Activities.dc.html, route key «activities»): calendar, to-do list, meeting scheduler, and
 * reminders and sync, with the edit dialog. The state lives in the address: ?tab, ?view, ?date, the
 * filters (?owner, ?type, ?status), the list's ?list and ?sort, and ?activity=<id>|new for the dialog.
 */
export default async function ActivitiesPage({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams
  const shell = await getShell()
  const t = await getTranslations('activities')
  if (!can(shell, 'deals', 'see')) {
    return (
      <div className="px-4 pb-12 pt-[26px] md:px-7">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-10 text-center text-13 text-muted">{t('noAccess')}</div>
      </div>
    )
  }

  const tz = shell.me.time_zone
  const now = zoned(new Date(), tz)
  const today: Day = { y: now.y, m: now.m, d: now.d }
  const tab = pick(one(sp.tab), ['calendar', 'todo', 'scheduler', 'reminders'] as const satisfies readonly Tab[], 'calendar')
  const view = pick(one(sp.view), ['day', 'week', 'month'] as const satisfies readonly CalView[], 'week')
  const date = parseYmd(one(sp.date)) ?? today
  const status = pick(one(sp.status), ['open', 'done', 'all'] as const satisfies readonly Status[], 'open')
  const list = pick(one(sp.list), ['all', 'overdue', 'today', 'week', 'done'] as const satisfies readonly ListTab[], 'all')
  const sort = pick(one(sp.sort), ['due', 'prio'] as const satisfies readonly Sort[], 'due')
  const owner = UUID.test(one(sp.owner) ?? '') ? one(sp.owner)! : null
  const type = UUID.test(one(sp.type) ?? '') ? one(sp.type)! : null
  const act = one(sp.activity)
  const modalId = act === 'new' ? 'new' : UUID.test(act ?? '') ? act! : null

  const [types, staff] = await Promise.all([loadActivityTypes(), loadStaff()])
  const filter: ActivitiesQuery = { ...(owner ? { owner_ids: [owner] } : {}), ...(type ? { type_ids: [type] } : {}) }

  // the calendar reads its range; the to-do list reads by tab (the counts follow the user and type filters)
  let range: { from: Day; to: Day } | null = null
  if (tab === 'calendar') {
    const from = view === 'day' ? date : view === 'week' ? mondayOf(date) : { y: date.y, m: date.m, d: 1 }
    const to = view === 'day' ? addDays(from, 1) : view === 'week' ? addDays(from, 7) : addDays(from, daysInMonth(date.y, date.m))
    range = { from, to }
  }
  const needsScheduling = tab === 'scheduler' || tab === 'reminders' || modalId !== null
  const [acts, scheduling, detail, deals, people, fields] = await Promise.all([
    range
      ? loadActivities({ ...filter, status, from: fromZoned(range.from, 0, 0, tz).toISOString(), to: fromZoned(range.to, 0, 0, tz).toISOString() })
      : tab === 'todo'
        ? loadActivities({ ...filter, tab: list, status: list === 'done' ? 'done' : 'open' })
        : null,
    needsScheduling ? loadScheduling() : null,
    modalId && modalId !== 'new' ? loadActivityDetail(modalId) : null,
    modalId ? loadDealOptions() : null,
    modalId ? loadPeopleOptions() : null,
    modalId ? loadActivityFields() : null,
  ])

  const modal: ModalData | null =
    modalId && deals && people && fields && scheduling && (modalId === 'new' || detail?.ok)
      ? { detail: modalId === 'new' || !detail?.ok ? null : detail.data, deals, people, fields, prefs: scheduling.prefs, calendar: scheduling.calendar }
      : null

  return (
    <ActivitiesScreen
      ctx={{
        tz,
        today: ymd(today),
        me: { id: shell.me.id, name: shell.me.name, initials: shell.me.initials, email: shell.me.email },
        rights: { add: can(shell, 'deals', 'add'), editOthers: can(shell, 'deals', 'edit_others'), bulk: can(shell, 'deals', 'bulk') },
        types,
        staff: staff.filter((s) => s.active),
      }}
      state={{ tab, view, date: ymd(date), status, list, sort, owner, type }}
      rows={acts?.ok ? acts.data.rows : []}
      counts={acts?.ok ? acts.data.counts : null}
      loadError={acts && !acts.ok ? acts.code : detail && !detail.ok ? detail.code : null}
      scheduling={scheduling}
      modal={modal}
    />
  )
}
