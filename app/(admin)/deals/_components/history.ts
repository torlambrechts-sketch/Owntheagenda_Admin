import { money, type NumberFormat } from '@/lib/format'
import type { Activity, DealBundle, DealsBase, HistoryRow, Note } from '@/lib/data/deals'

export type HistKind = 'Notes' | 'Activities' | 'Changelog'
export const HIST_FILTERS = ['All', 'Notes', 'Activities', 'Changelog'] as const
export type HistEntry = { k: HistKind; t: string; s: string; g: string; bg: string; at: string }

type T = ((key: string, values?: Record<string, string | number>) => string) & { has: (key: string) => boolean }

/**
 * The drawer's history: the record's changelog, its notes and its completed activities, newest first.
 * Every entry comes from a row; nothing is drawn for channels that have no source yet.
 */
export function buildHistory(bundle: DealBundle, base: DealsBase, t: T, nf: NumberFormat, fmtDate: (iso: string) => string): HistEntry[] {
  const stageName = new Map(base.pipelines.flatMap((p) => p.stages.map((s) => [s.id, s.name] as const)))
  const staffName = new Map(base.staff.map((s) => [s.id, s.name]))
  const labelName = new Map(base.labels.map((l) => [l.id, l.name]))
  const fieldLabel = new Map(base.fields.map((f) => [f.key, f.label]))
  const str = (v: unknown): string => {
    if (v === null || v === undefined || v === '') return '—'
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return String(v)
    if (Array.isArray(v)) return v.map(str).join(', ')
    if (typeof v === 'object' && 'amount' in (v as object)) return money(Number((v as { amount: unknown }).amount), nf, String((v as { currency?: unknown }).currency ?? 'NOK'))
    return '—'
  }
  const src = (s: string) => t(`history.source.${['ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system'].includes(s) ? s : 'system'}`)

  const change = (h: HistoryRow): Omit<HistEntry, 'k' | 'bg' | 'at'> => {
    const tail = ` · ${t('history.sourceLabel', { source: src(h.source) })}${h.actor ? ` · ${h.actor}` : ''}`
    const arrow = (name: string, a: string, b: string) => ({ s: `${name}: ${a} → ${b}${tail}` })
    switch (h.field) {
      case '*created': {
        const dup = h.new && typeof h.new === 'object' && 'duplicate_of' in (h.new as object)
        return { t: dup ? t('history.duplicated') : t('history.created'), s: tail.slice(3), g: '＋' }
      }
      case 'archived_at': return { t: h.new ? t('history.archived') : t('history.unarchived'), s: tail.slice(3), g: '▤' }
      case '*archived': return { t: h.new === true ? t('history.archived') : t('history.unarchived'), s: tail.slice(3), g: '▤' }
      case '*deleted': return { t: t('history.deleted'), s: tail.slice(3), g: '×' }
      case '*restored': return { t: t('history.restored'), s: tail.slice(3), g: '↺' }
      case 'stage_id': return { t: t('history.stage'), g: '↔', ...arrow(t('history.f.stage'), stageName.get(String(h.old)) ?? '—', stageName.get(String(h.new)) ?? '—') }
      case 'status': {
        const v = String(h.new)
        return { t: v === 'won' ? t('history.won') : v === 'lost' ? t('history.lost') : t('history.reopened'), g: v === 'won' ? '✓' : v === 'lost' ? '×' : '↺', ...arrow(t('history.f.status'), t(`status.${String(h.old)}`).toLowerCase(), t(`status.${v}`).toLowerCase()) }
      }
      case 'value': return { t: t('history.value'), g: '✎', ...arrow(t('history.f.value'), h.old == null ? '—' : money(Number(h.old), nf), h.new == null ? '—' : money(Number(h.new), nf)) }
      case 'owner_id': return { t: t('history.owner'), g: '✎', ...arrow(t('history.f.owner'), staffName.get(String(h.old)) ?? '—', staffName.get(String(h.new)) ?? '—') }
      case 'expected_close_date': return { t: t('history.close'), g: '↔', ...arrow(t('history.f.close'), typeof h.old === 'string' ? fmtDate(h.old) : '—', typeof h.new === 'string' ? fmtDate(h.new) : '—') }
      case 'labels': {
        const names = (v: unknown) => (Array.isArray(v) ? v.map((x) => labelName.get(String(x)) ?? '').filter(Boolean).join(', ') || '—' : '—')
        return { t: t('history.labels'), g: '✎', ...arrow(t('history.f.labels'), names(h.old), names(h.new)) }
      }
      case 'items': return { t: h.new ? t('history.itemChanged') : t('history.itemRemoved'), s: tail.slice(3), g: '▦' }
      case 'participants': {
        const on = !!(h.new && typeof h.new === 'object' && (h.new as { on?: unknown }).on)
        return { t: on ? t('history.participantAdded') : t('history.participantRemoved'), s: tail.slice(3), g: '◉' }
      }
      case 'person_id': return { t: t('history.person'), s: tail.slice(3), g: '✎' }
      case 'organization_id': return { t: t('history.organization'), s: tail.slice(3), g: '✎' }
      case 'value_source': return { t: t('history.valueSource'), g: '✎', ...arrow(t('history.f.valueSource'), t(`valueSource.${h.old === 'items' ? 'items' : 'manual'}`), t(`valueSource.${h.new === 'items' ? 'items' : 'manual'}`)) }
      default:
        if (h.field.startsWith('custom.')) {
          const name = fieldLabel.get(h.field.slice(7)) ?? h.field.slice(7)
          return { t: t('history.custom', { field: name }), g: '✎', ...arrow(name, str(h.old), str(h.new)) }
        }
        return { t: t('history.other', { field: h.field }), g: '✎', ...arrow(h.field, str(h.old), str(h.new)) }
    }
  }

  const fromLog: HistEntry[] = bundle.history.map((h) => ({ k: 'Changelog', bg: '#F2EAD6', at: h.at, ...change(h) }))
  // a record imported without a creation row still has its creation time and source
  if (!bundle.history.some((h) => h.field === '*created')) {
    const d = bundle.detail
    fromLog.push({ k: 'Changelog', bg: '#F2EAD6', at: d.created_at, t: t('history.created'), s: d.source ? `${t('history.f.source')}: ${d.source}` : '', g: '＋' })
  }
  const fromNotes: HistEntry[] = bundle.notes.map((n: Note) => ({
    k: 'Notes', t: n.pinned ? t('history.notePinned', { author: n.author ?? '—' }) : t('history.note', { author: n.author ?? '—' }), s: n.body, g: '✎', bg: '#FBEBBE', at: n.created_at,
  }))
  const fromActs: HistEntry[] = bundle.activities.filter((a: Activity) => a.done && a.done_at).map((a) => ({
    k: 'Activities', t: t('history.activityDone', { subject: a.subject }), s: a.type ? (t.has(`activityTypes.${a.type.key}`) ? t(`activityTypes.${a.type.key}`) : a.type.name) : '', g: a.type?.glyph ?? '✓', bg: '#DCEBD3', at: a.done_at!,
  }))
  return [...fromLog, ...fromNotes, ...fromActs].sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
}
