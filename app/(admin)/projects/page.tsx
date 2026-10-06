import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadBoard, loadDealTitle, loadProject, loadProjectsBase } from '@/lib/data/projects'
import { TABS, type Rights, type Tab } from '@/lib/data/projects-shared'
import { ProjectsScreen } from './_components/ProjectsScreen'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Projects (Projects.dc.html): Board, Timeline, Templates, Reports and the boards' setup, with the project drawer at
 * ?project=<id> (where a mention or ⌘K opens it). ?tab=<tab> opens a tab; ?from_deal=<id> opens ＋ Project from that deal.
 */
export default async function ProjectsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const shell = await getShell()
  const sp = await searchParams
  const t = await getTranslations('projects')

  if (shell.modules.projects === false || !can(shell, 'projects', 'see')) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t(shell.modules.projects === false ? 'noAccess.moduleOff' : 'noAccess.body')}</p>
        </div>
      </div>
    )
  }

  const rights: Rights = {
    meId: shell.me.id,
    add: can(shell, 'projects', 'add'),
    editOthers: can(shell, 'projects', 'edit_others'),
    del: can(shell, 'projects', 'delete'),
    bulk: can(shell, 'projects', 'bulk'),
    exportRows: can(shell, 'projects', 'export'),
    configure: can(shell, 'projects', 'configure'),
    ai: can(shell, 'projects', 'ai'),
    reportsOthers: can(shell, 'projects', 'reports_others'),
    dealsSee: can(shell, 'deals', 'see'),
  }

  const base = await loadProjectsBase()
  const boards = base.boards.ok ? base.boards.data : []
  const live = boards.filter((b) => !b.archived_at)
  const pref = typeof base.prefs.board === 'string' ? base.prefs.board : null
  const boardId = live.find((b) => b.id === pref)?.id ?? live[0]?.id ?? null
  const closed = base.prefs.closed === true
  const asked = one(sp.tab)
  const tab: Tab = (TABS as readonly string[]).includes(asked ?? '') ? (asked as Tab) : 'board'
  const projectId = z.guid().safeParse(one(sp.project))

  // ?from_deal=<id>: «Create project from deal» opened from elsewhere (the deal drawer links here)
  const fromDeal = z.guid().safeParse(one(sp.from_deal))
  const [board, project, deal] = await Promise.all([
    boardId ? loadBoard(boardId, { closed }) : Promise.resolve(null),
    projectId.success ? loadProject(projectId.data) : Promise.resolve(null),
    fromDeal.success && rights.add && rights.dealsSee ? loadDealTitle(fromDeal.data) : Promise.resolve(null),
  ])

  return (
    <ProjectsScreen
      base={{ ...base, boards }}
      boardsError={base.boards.ok ? null : base.boards.code}
      rights={rights}
      initialTab={tab === 'setup' && !rights.configure ? 'board' : tab}
      initialBoardId={boardId}
      initialClosed={closed}
      initialBoard={board && board.ok ? board.data : null}
      initialProject={project && project.ok ? project.data : null}
      initialProjectId={projectId.success ? projectId.data : null}
      initialFromDeal={deal && deal.ok && boardId ? { id: deal.data.id, label: deal.data.title } : null}
    />
  )
}
