import type { Card } from '@/lib/data/deals'
import type { MissingField } from '../actions'

/** What the signed-in staff member may do here (mirrors app.can; the database decides). */
export type Rights = {
  meId: string
  readOnly: boolean
  add: boolean
  editOthers: boolean
  del: boolean
  bulk: boolean
  exportRows: boolean
  configure: boolean
}

export const canEditDeal = (r: Rights, d: { owner_id: string | null }) => !r.readOnly && (r.editOthers || d.owner_id === r.meId)

export type View = 'pipeline' | 'list' | 'forecast' | 'archive' | 'products'
export const VIEWS: View[] = ['pipeline', 'list', 'forecast', 'archive', 'products']

// the design's stage palette (Deals.dc.html: viz)
export const VIZ = ['#F6D9C6', '#DCEBD3', '#CFE0F5', '#F3E2C9', '#E7DAF2']

/** A card's background and border (cardOf in the design): won, lost, rotting or plain. */
export const cardTone = (c: Pick<Card, 'status' | 'rotting'>) => ({
  bg: c.status === 'won' ? 'bg-ok-bg' : c.status === 'lost' ? 'bg-beige' : c.rotting ? 'bg-peach' : 'bg-surface',
  bc: c.rotting ? 'border-coral' : 'border-line',
})

/** The score badge's tone (the design's sbg): 70 and up good, 40 and up middling, below low. */
export const scoreTone = (s: number) => (s >= 70 ? 'bg-ok-bg' : s >= 40 ? 'bg-highlight' : 'bg-peach')

export const ACT = {
  overdue: { g: '!', c: 'text-danger' },
  none: { g: '⚠', c: 'text-warn-ink' },
  planned: { g: '◷', c: 'text-link' },
} as const

/** Advanced filter conditions (the design's Where/AND rows). */
export type CondField = 'value' | 'score' | 'idle' | 'source' | 'label'
export type CondOp = 'is' | 'gt' | 'lt' | 'contains'
/** join: how the row attaches to the one before it; «or» starts a new OR group. */
export type Cond = { field: CondField; op: CondOp; val: string; join?: 'and' | 'or' }

export type Modal =
  | { kind: 'new' }
  | { kind: 'lost'; id: string; version: number }
  | { kind: 'required'; id: string; stage: string; stageName: string; version: number; missing: MissingField[] }
  | { kind: 'next'; dealId: string; subject: string }
  | { kind: 'saveFilter' }
  | { kind: 'product' }
  | { kind: 'toLead'; id: string; title: string }

/** A date-only value (YYYY-MM-DD) as a Date at noon UTC, so every time zone shows the same day. */
export const dateOnly = (d: string) => new Date(`${d}T12:00:00Z`)

export const initials = (name: string | null | undefined) =>
  (name ?? '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('')
