import { getFormatter, getTranslations } from 'next-intl/server'
import { getShell, can } from '@/lib/shell'
import { loadDrafts, loadFiles } from '@/lib/data/dev-core'
import { loadAiStatus } from '@/lib/ai/run'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { SENTRAL_COLOR, bugMarkdown, bugPath, bugStatus, featureMarkdown, featurePath, linkToken, type LogEntry } from './core/logic'
import type { ProductInfo } from './core/styles'
import { MarkdownView as View, type FileRow, type FileDetail } from './core/MarkdownView'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Markdown roadmap (DevClaude.dc.html, v.md): the roadmap items and bugs written out as the repo starter
 * kit's feature and bug files — front matter, the tasks (their work items) and the log (Sentral's own audit of the
 * record). The files are generated, not read from a repository: they are edited by editing the records, and they can be
 * downloaded. Committing needs GitHub, which is not connected.
 */
export async function MarkdownView({ searchParams }: DevTabProps) {
  const t = await getTranslations('devCore')
  const format = await getFormatter()
  const shell = await getShell()
  const data = await loadFiles()
  const products: ProductInfo[] = [...shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color })), { key: 'sentral', name: t('sentral'), color: SENTRAL_COLOR }]

  const words = (e: LogEntry): { title: string; detail: string } => {
    const d = (e.detail ?? {}) as Record<string, unknown>
    const s = (k: string) => (typeof d[k] === 'string' ? (d[k] as string) : '')
    const key = e.action === 'dev_roadmap.changed' && s('status') ? 'log.dev_roadmap_status' : `log.${e.action.replace('.', '_')}`
    const vals = {
      lane: s('lane') ? t(`roadmap.lanes.${s('lane')}`) : '',
      status: s('status') && t.has(`status.${s('status')}`) ? t(`status.${s('status')}`) : '',
      kind: s('kind') && t.has(`roadmap.kind.${s('kind')}`) ? t(`roadmap.kind.${s('kind')}`) : '',
      feature: s('feature') && t.has(`ai.features.${s('feature')}`) ? t(`ai.features.${s('feature')}`) : '',
      role: s('role') && t.has(`specs.roles.${s('role')}`) ? t(`specs.roles.${s('role')}`) : '',
      severity: s('severity').toUpperCase(),
      n: Number(d.created ?? d.added ?? d.tickets ?? d.notified ?? d.into ?? d.revision ?? 0) || 0,
      on: d.on === false ? 'off' : 'on',
      fields: Array.isArray(d.fields) ? (d.fields as unknown[]).filter((f): f is string => typeof f === 'string')
        .map((f) => (t.has(`md.fieldNames.${f}`) ? t(`md.fieldNames.${f}`) : f)).join(', ') : '',
    }
    const title = t.has(`${key}.title`) ? t(`${key}.title`, vals) : e.action
    const detail = t.has(`${key}.detail`) ? t(`${key}.detail`, vals) : ''
    return { title, detail }
  }
  const line = (e: LogEntry) => { const w = words(e); return `${e.by ?? '—'}: ${w.title}${w.detail ? ` · ${w.detail}` : ''}` }

  const files: (FileRow & { md: () => string })[] = [
    ...data.items.map((i) => ({
      key: i.key, kind: 'feature' as const, id: i.id, path: featurePath(i), title: i.title, status: i.status,
      md: () => featureMarkdown({ key: i.key, product: i.product, title: i.title, goal: i.goal, status: i.status, owner: i.owner?.name ?? null,
                                  spec: i.spec?.ref ?? null, problem: i.problem, links: i.links, tasks: i.tasks, log: i.log }, line),
    })),
    ...data.bugs.map((b) => ({
      key: `BUG-${b.number}`, kind: 'bug' as const, id: b.id, path: bugPath(b), title: b.title, status: bugStatus({ state: b.state, workStatus: b.work?.status ?? null }),
      md: () => bugMarkdown({ number: b.number, product: b.product, title: b.title, severity: b.severity, state: b.state, owner: b.assignee?.name ?? null,
                              customers: b.customers, ticketNumbers: b.ticket_numbers ?? [], problemNumber: b.problem?.number ?? null,
                              workStatus: b.work?.status ?? null, tasks: b.tasks, log: b.log }, line),
    })),
  ]
  const asked = one(searchParams.file)
  const sel = files.find((f) => f.key === asked) ?? files[0] ?? null

  let detail: FileDetail | null = null
  if (sel) {
    const item = sel.kind === 'feature' ? data.items.find((i) => i.id === sel.id)! : null
    const bug = sel.kind === 'bug' ? data.bugs.find((b) => b.id === sel.id)! : null
    const log = (item?.log ?? bug?.log ?? []).map((e) => ({ at: e.at, action: e.action, by: e.by, ...words(e) }))
    const canAdd = can(shell, 'dev', 'add')
    const [ai, drafts] = item && canAdd ? await Promise.all([loadAiStatus(), loadDrafts(item.id)]) : [null, []]
    detail = {
      key: sel.key, kind: sel.kind, id: sel.id, path: `/${sel.path}`, title: sel.title, status: sel.status, md: sel.md(),
      version: item?.version ?? bug?.version ?? 1, open: bug ? bug.state === 'open' : true,
      owner: item?.owner?.id ?? bug?.assignee?.id ?? null,
      lastChange: log[0] ? { at: log[0].at, by: log[0].by } : null,
      now: new Date().toISOString(),
      tasks: item?.tasks ?? bug?.tasks ?? [],
      links: item ? item.links.map(linkToken) : bug ? [...(bug.ticket_numbers ?? []).map((n) => `T-${n}`), ...(bug.problem?.number ? [`T-${bug.problem.number}`] : [])] : [],
      log,
      doneTasks: (item?.tasks ?? []).filter((x) => x.done).length,
      ai: ai ? { connected: ai.connected, allowed: ai.features.filter((f) => f.allowed && f.enabled).map((f) => f.key) } : null,
      drafts: drafts.map((d) => ({ id: d.id, feature: d.feature, body: d.body, at: d.created_at, by: d.by })),
    }
  }
  const updated = format.dateTime(new Date(), { hour: '2-digit', minute: '2-digit' })
  return (
    <View files={files.map(({ md, ...f }) => { void md; return f })} detail={detail} staff={data.staff} canAdd={data.can_add} generatedAt={updated} products={products} />
  )
}
