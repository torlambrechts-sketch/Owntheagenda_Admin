import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import {
  loadBase, loadEmailTemplates, loadHistory, loadMonitor, loadOrgLabels, loadPickers, loadRuns, loadSequence, loadTemplates, loadViews,
  loadWorkflow, loadWorkflows,
} from '@/lib/data/automation'
import { TABS } from '@/lib/data/automation-shared'
import { AutomationFrame } from './_components/AutomationFrame'
import { WorkflowsTab } from './_components/WorkflowsTab'
import { BuilderTab } from './_components/BuilderTab'
import { TemplatesTab } from './_components/TemplatesTab'
import { MonitorTab } from './_components/MonitorTab'
import { AssignTab } from './_components/AssignTab'
import { SequencesTab } from './_components/SequencesTab'

const Params = z.object({
  tab: z.enum(TABS).catch('list'),
  wf: z.string().uuid().nullable().catch(null),
  seq: z.string().uuid().nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

/**
 * Automation (Automation.dc.html): Workflows, Builder, Templates, Monitoring, Assignment rules and
 * Sequences on the one engine (0021_engine.sql). The tab, the workflow in the builder and the selected
 * sequence live in the address; each tab loads only what it shows.
 */
export default async function AutomationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab) ?? 'list', wf: one(sp.wf) ?? null, seq: one(sp.seq) ?? null })
  const shell = await getShell()
  const base = await loadBase()
  const me = shell.me.id
  // «Manage workflows» in a scope; a workflow is changed by its owner or by someone who may configure (0021)
  const rights = {
    deals: can(shell, 'deals', 'workflows'),
    tickets: can(shell, 'tickets', 'workflows'),
    configure: can(shell, 'global', 'configure'),
    seeDeals: can(shell, 'deals', 'see'),
    bulk: can(shell, 'deals', 'bulk'),
    editOthers: can(shell, 'deals', 'edit_others'),
  }

  let body: React.ReactNode = null
  if (p.tab === 'list') {
    body = <WorkflowsTab rows={await loadWorkflows('workflow')} people={base.people} me={me} rights={rights} />
  } else if (p.tab === 'builder') {
    const rows = await loadWorkflows('workflow')
    const wfId = p.wf && rows.some((r) => r.id === p.wf) ? p.wf : rows[0]?.id ?? null
    const [detail, pickers] = await Promise.all([wfId ? loadWorkflow(wfId) : Promise.resolve(null), loadPickers()])
    const wf = detail?.ok ? detail.data : null
    body = <BuilderTab key={wf ? `${wf.id}:${wf.version}` : 'none'} wf={wf} base={base} pickers={pickers} me={me} rights={rights} />
  } else if (p.tab === 'templates') {
    body = <TemplatesTab templates={await loadTemplates()} canCreate={rights.deals || rights.tickets} />
  } else if (p.tab === 'monitor') {
    const [monitor, runs] = await Promise.all([loadMonitor(), loadRuns()])
    body = <MonitorTab monitor={monitor} runs={runs} canRetry={rights.deals || rights.tickets} nf={shell.me.number_format} />
  } else if (p.tab === 'assign') {
    // each rule's condition, assignee and priority come with the list (0029)
    const [rules, labels, history] = await Promise.all([loadWorkflows('assignment'), loadOrgLabels(), loadHistory()])
    body = <AssignTab rules={rules} labels={labels} history={history.ok ? history.data : []} people={base.people} teams={base.teams} canEdit={rights.deals} />
  } else {
    const seqs = await loadWorkflows('sequence')
    const details = await Promise.all(seqs.map((s) => loadSequence(s.id)))
    const list = details.flatMap((d) => (d.ok ? [d.data] : []))
    const selected = list.find((s) => s.id === p.seq) ?? list[0] ?? null
    const entity = (selected?.trigger_config.entities as unknown[] | undefined)?.[0] === 'lead' ? 'lead' : 'deal'
    const [templates, views] = await Promise.all([loadEmailTemplates(), selected ? loadViews(entity) : Promise.resolve([])])
    body = <SequencesTab key={selected ? `${selected.id}:${selected.version}` : 'none'} list={list} selected={selected} entity={entity} templates={templates} views={views} me={me} rights={rights} />
  }

  return <AutomationFrame tab={p.tab} loopOn={base.safeguards.value !== 'off'}>{body}</AutomationFrame>
}
