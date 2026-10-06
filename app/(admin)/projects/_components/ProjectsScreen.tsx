'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import type { BoardRow, BoardView, Card, ProjectBundle, ProjectsBase, TemplateRow } from '@/lib/data/projects'
import { canEditProject, type Rights, type Tab } from '@/lib/data/projects-shared'
import { fetchBoard, fetchBoards, fetchProject, moveProject, setPref } from '../actions'
import { Board } from './Board'
import { ExportMenu } from './ExportMenu'
import { TimelineView } from './TimelineView'
import { TemplatesView } from './TemplatesView'
import { ReportsView } from './ReportsView'
import { SetupView } from './SetupView'
import { ProjectDrawer } from './ProjectDrawer'
import { NewProjectModal } from './NewProjectModal'
import { NoBoards } from './NoBoards'

type Props = {
  base: ProjectsBase
  boardsError: RpcCode | null
  rights: Rights
  initialTab: Tab
  initialBoardId: string | null
  initialClosed: boolean
  initialBoard: BoardView | null
  initialProject: ProjectBundle | null
  initialProjectId: string | null
  initialFromDeal: { id: string; label: string } | null
}

export type NewProject = { template?: TemplateRow | null; deal?: { id: string; label: string } | null }

const VIEW_TABS: Tab[] = ['board', 'timeline', 'templates', 'reports']

export function ProjectsScreen({ base, boardsError, rights, initialTab, initialBoardId, initialClosed, initialBoard, initialProject, initialProjectId, initialFromDeal }: Props) {
  const t = useTranslations('projects')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const err = useCallback((code: RpcCode) => flash(te(code)), [flash, te])

  const [tab, setTab] = useState<Tab>(initialTab)
  const [boards, setBoards] = useState<BoardRow[]>(base.boards)
  const [boardId, setBoardId] = useState<string | null>(initialBoardId)
  const [closed, setClosed] = useState(initialClosed)
  const [board, setBoard] = useState<BoardView | null>(initialBoard)
  const [newProject, setNewProject] = useState<NewProject | null>(initialFromDeal ? { deal: initialFromDeal } : null)
  const [rev, setRev] = useState(0)
  const refresh = useCallback(() => setRev((r) => r + 1), [])
  const live = boards.filter((b) => !b.archived_at)

  // ---- the board (cards and counts); the timeline's picker and Reports read the same board
  const first = useRef(true)
  const seq = useRef(0)
  useEffect(() => {
    if (first.current) { first.current = false; if (initialBoard || !boardId) return }
    if (!boardId) { setBoard(null); return }
    const n = ++seq.current
    void fetchBoard({ board: boardId, closed }).then((r) => {
      if (n !== seq.current) return
      if (r.ok) setBoard(r.board)
      else err(r.code)
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the initial board is read once
  }, [boardId, closed, rev])

  const reloadBoards = useCallback(async () => {
    const r = await fetchBoards()
    if (!r.ok) return err(r.code)
    setBoards(r.boards)
    const still = r.boards.filter((b) => !b.archived_at)
    setBoardId((cur) => (cur && still.some((b) => b.id === cur) ? cur : still[0]?.id ?? null))
    refresh()
  }, [err, refresh])

  // ---- the drawer follows ?project=<id> (a mention, ⌘K and the board open it the same way)
  const params = useSearchParams()
  const projectId = params.get('project')
  const [bundle, setBundle] = useState<ProjectBundle | null>(initialProject)
  const pseq = useRef(0)
  const firstProject = useRef(true)
  useEffect(() => {
    if (!projectId) { setBundle(null); return }
    if (firstProject.current && initialProject && projectId === initialProjectId && rev === 0) { firstProject.current = false; return }
    firstProject.current = false
    const n = ++pseq.current
    void fetchProject(projectId).then((r) => {
      if (n !== pseq.current) return
      if (r.ok) setBundle(r.project)
      else { err(r.code); setBundle(null) }
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- initial values are read once
  }, [projectId, rev])

  const openProject = useCallback((id: string) => {
    const u = new URL(window.location.href)
    u.searchParams.set('project', id)
    window.history.pushState(null, '', u.pathname + u.search)
  }, [])
  const closeProject = useCallback(() => {
    const u = new URL(window.location.href)
    u.searchParams.delete('project')
    window.history.pushState(null, '', u.pathname + u.search)
  }, [])

  const dropFromDeal = () => {
    const u = new URL(window.location.href)
    if (!u.searchParams.has('from_deal')) return
    u.searchParams.delete('from_deal')
    window.history.replaceState(null, '', u.pathname + u.search)
  }
  const pickTab = (k: Tab) => {
    setTab(k)
    const u = new URL(window.location.href)
    if (k === 'board') u.searchParams.delete('tab')
    else u.searchParams.set('tab', k)
    window.history.replaceState(null, '', u.pathname + u.search)
  }
  const pickBoard = (id: string) => { setBoardId(id); void setPref({ key: 'board', value: id }) }
  const toggleClosed = () => { const v = !closed; setClosed(v); void setPref({ key: 'closed', value: v }) }

  // ---- moving a card (PRJ-01): optimistic, rolled back by a reload on refusal
  const move = useCallback(async (c: Card, phase: string) => {
    if (!canEditProject(rights, c)) { flash(t('flash.viewOnlyMove')); return }
    if (c.status !== 'open') { flash(t('flash.closedMove')); return }
    if (c.phase_id === phase) return
    const name = board?.phases.find((p) => p.id === phase)?.name ?? ''
    setBoard((b) => (b ? { ...b, cards: b.cards.map((x) => (x.id === c.id ? { ...x, phase_id: phase } : x)) } : b))
    const r = await moveProject({ id: c.id, phase, version: c.version })
    if (!r.ok) { err(r.code); refresh(); return }
    flash(t('flash.moved', { phase: name }))
    refresh()
  }, [rights, board, flash, t, err, refresh])

  if (boardsError) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface px-[22px] py-5 text-13 text-muted">{te(boardsError)}</div>
      </div>
    )
  }

  const tabs = rights.configure ? [...VIEW_TABS, 'setup' as const] : VIEW_TABS
  const hint = board?.workflow_hint ?? null

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div role="tablist" aria-label={t('tabs.label')} className="flex flex-wrap gap-[6px]">
          {tabs.map((k) => (
            <button
              key={k}
              type="button"
              role="tab"
              aria-selected={tab === k}
              onClick={() => pickTab(k)}
              className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${tab === k ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
            >
              {t(`tabs.${k}`)}
            </button>
          ))}
        </div>
        {live.length > 0 ? (
          <select
            aria-label={t('board.select')}
            value={boardId ?? ''}
            onChange={(e) => pickBoard(e.target.value)}
            className="h-9 rounded-10 border border-ink bg-surface px-[10px] text-13 font-bold text-ink"
          >
            {live.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        ) : null}
        <span className="flex-1" />
        {hint ? <span className="text-12 text-muted">{t('hint', { name: hint.name })}</span> : null}
        {live.length > 0 && tab === 'board' ? (
          <>
            <button
              type="button"
              role="switch"
              aria-checked={closed}
              onClick={toggleClosed}
              className="flex h-9 cursor-pointer items-center gap-[7px] rounded-10 border border-line bg-transparent px-[11px] text-12.5 font-semibold"
            >
              <span className={`relative h-4 w-[26px] rounded-999 ${closed ? 'bg-ink' : 'bg-line-strong'}`}>
                <span className="absolute top-[2px] h-3 w-3 rounded-999 bg-surface" style={{ left: closed ? 12 : 2 }} />
              </span>
              {t('board.closed')}
            </button>
            {rights.exportRows && board ? <ExportMenu board={board.board.id} project={null} name={board.board.name} tall /> : null}
          </>
        ) : null}
        {rights.add && live.length > 0 ? (
          <button type="button" onClick={() => setNewProject({})} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">
            {t('newProject')}
          </button>
        ) : null}
      </div>

      {live.length === 0 && tab !== 'setup' && tab !== 'templates' ? (
        <NoBoards rights={rights} onCreated={reloadBoards} />
      ) : null}

      {live.length > 0 && tab === 'board' ? (
        <Board board={board} rights={rights} onOpen={openProject} onMove={(c, p) => void move(c, p)} />
      ) : null}
      {live.length > 0 && tab === 'timeline' ? (
        <TimelineView cards={board?.cards ?? []} openId={projectId} rev={rev} onChanged={refresh} onOpen={openProject} />
      ) : null}
      {tab === 'templates' ? (
        <TemplatesView boards={live} base={base} rights={rights} rev={rev} onUse={(tpl) => setNewProject({ template: tpl })} />
      ) : null}
      {live.length > 0 && tab === 'reports' ? <ReportsView boards={live} boardId={boardId} rights={rights} rev={rev} /> : null}
      {tab === 'setup' && rights.configure ? <SetupView boards={boards} onChanged={reloadBoards} /> : null}

      {projectId && bundle && bundle.detail.id === projectId ? (
        <ProjectDrawer
          bundle={bundle}
          base={base}
          boards={live}
          rights={rights}
          onClose={closeProject}
          onChanged={refresh}
        />
      ) : null}

      {newProject ? (
        <NewProjectModal
          init={newProject}
          base={base}
          boards={live}
          boardId={boardId}
          rights={rights}
          onClose={() => { setNewProject(null); dropFromDeal() }}
          onCreated={(id) => { setNewProject(null); dropFromDeal(); refresh(); openProject(id) }}
        />
      ) : null}
    </div>
  )
}
