import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadMeeting, loadWorkspace } from '@/lib/data/meetings'
import { VIEWS, type View } from '@/lib/data/meetings-shared'
import { MeetingsScreen } from './_components/MeetingsScreen'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Meetings (Meetings.dc.html): the workspace (upcoming, needs your review, history; a meeting's brief, transcript and
 * recap, CRM suggestions), Ways to capture, and Workspace and controls. ?meeting=<id> opens a meeting (notifications
 * link here); ?tab=capture|controls opens a view. The workspace is deals:see, the module and the staff member's own
 * switch (MTG-08, V-P7M-01): without it there is no workspace, only the reason.
 */
export default async function MeetingsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const shell = await getShell()
  const sp = await searchParams
  const t = await getTranslations('meetings')

  const closed = (key: 'moduleOff' | 'body' | 'disabled') => (
    <div className="px-4 pb-[60px] pt-5 md:px-7">
      <div className="rounded-20 border border-line bg-surface p-[26px]">
        <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
        <p className="m-0 mt-2 text-13 text-muted">{t(`noAccess.${key}`)}</p>
      </div>
    </div>
  )
  if (shell.modules.meetings === false) return closed('moduleOff')
  if (!can(shell, 'deals', 'see')) return closed('body')

  const workspace = await loadWorkspace()
  if (!workspace.ok) {
    if (workspace.code === 'forbidden' && workspace.detail === 'meetings:disabled') return closed('disabled')
    if (workspace.code === 'module_off') return closed('moduleOff')
    if (workspace.code === 'forbidden') return closed('body')
    throw new Error(workspace.code)
  }

  const asked = one(sp.tab)
  const view: View = (VIEWS as readonly string[]).includes(asked ?? '') ? (asked as View) : 'workspace'
  const wanted = z.guid().safeParse(one(sp.meeting))
  const all = [...workspace.data.upcoming, ...workspace.data.review, ...workspace.data.history]
  // the design opens on the first meeting of the first group that has one
  const selected = wanted.success ? wanted.data : (all[0]?.id ?? null)
  const meeting = selected ? await loadMeeting(selected) : null

  return (
    <MeetingsScreen
      initialView={view}
      initialWorkspace={workspace.data}
      initialMeetingId={selected}
      initialMeeting={meeting && meeting.ok ? meeting.data : null}
      initialMeetingError={meeting && !meeting.ok ? meeting.code : null}
      me={{ id: shell.me.id, timeZone: shell.me.time_zone, numberFormat: shell.me.number_format, dealsAdd: can(shell, 'deals', 'add') }}
      products={Object.fromEntries(shell.products.map((p) => [p.key, p.name]))}
    />
  )
}
