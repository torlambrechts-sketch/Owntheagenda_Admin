/**
 * Mobile (Mobile.dc.html): the types the phone previews and the outbox share between server and client.
 * Nothing here is server-only; the loaders are in lib/data/mobile.ts.
 */

export type Coords = { lat: number; lng: number }

export type TodayItem = {
  id: string; subject: string; starts_at: string | null; done: boolean; type: string | null
  organization: string | null; organization_id: string | null; deal: string | null; deal_id: string | null; km: number | null
}

export type Focus = {
  hour: number
  name: string
  overdue_activities: number
  deals_past_close: number | null
  today: TodayItem[]
  unread_threads: number
  nearby_10km: number | null
  closing_this_week: { count: number; value_nok: number; excluded_currency: number } | null
  month: { won_value_nok: number; new_deals: number; goal: { id: string; name: string; progress: number | null; target_value: number | null; target_count: number | null } | null } | null
  tasks_due_today: number | null
  chats_waiting: number | null
  contact_rule: string
}

export type NearbyRow = {
  entity: 'organization' | 'person'
  id: string
  title: string
  city: string | null
  km: number
  /** the organisation's place (R-MOBILE-05), not the device's; null where unknown */
  lat: number | null
  lng: number | null
  deal: { id: string; title: string; stage: string | null } | null
  health: number | null
  customer: boolean
  last_visit_at: string | null
}

export type DealPreview = {
  id: string
  title: string
  value: number
  currency: string
  version: number
  stage_id: string
  expected_close_date: string | null
  score: number | null
  organization: string | null
  organization_id: string | null
  person: { id: string; name: string; title: string | null; phone: string | null } | null
  stages: { id: string; name: string }[]
  /** labels of the fields the next stage requires and the deal does not have yet (CUS-02) */
  next_requires: string[]
  note: { body: string; author: string | null } | null
}

export type NotificationItem = { id: string; kind: string; key: string; params: Record<string, string | number>; route: string | null; created_at: string; read: boolean }

export type PushState = {
  push_ready: boolean; setting: string; module: boolean
  devices: { id: string; platform: string; label: string | null; created_at: string; last_used_at: string | null; failures: number }[]
  /** the Web Push (VAPID) public key to subscribe with, or null while push is not configured (R-MOBILE-03) */
  public_key: string | null
}

export const PREF_KINDS = ['assignment', 'mention', 'chat_request', 'security', 'system'] as const
export type PrefKind = (typeof PREF_KINDS)[number]
export type Pref = { kind: PrefKind; channels: string[] }

export const CONTACT_RULES = ['no_rule', 'source_and_basis', 'opt_in_only'] as const

export const CALL_OUTCOMES = ['connected', 'no_answer', 'busy', 'voicemail', 'missed'] as const
export type CallOutcome = (typeof CALL_OUTCOMES)[number]

export type Preview = {
  focus: Focus
  deal: DealPreview | null
  notifications: { unread: number; items: NotificationItem[] } | null
  push: PushState | null
  prefs: Pref[] | null
  /** ids the client needs for offline mutations: the activity types it creates */
  types: { call: string | null; visit: string | null }
  /** whether the storage signer runs (storage-sign, 0052): audio notes, photos and scans can be uploaded */
  storage: boolean
  /** what was captured on the deal (captures_get), newest first */
  captures: Captures | null
}

export const CAPTURE_KINDS = ['photo', 'audio', 'scan', 'card'] as const
export type CaptureKind = (typeof CAPTURE_KINDS)[number]
export type Captures = {
  transcription: string
  items: { id: string; kind: CaptureKind; filename: string; mime: string; created_at: string; transcript: string | null }[]
}

// ---------------------------------------------------------------------------
// offline sync (SF-31): one mutation per user action, its id made once, so a retry is idempotent (sync_receipts)
export const SYNC_OPS = ['create', 'update', 'note', 'activity_done', 'stage_move'] as const
export type SyncOp = (typeof SYNC_OPS)[number]

export type Mutation = {
  mutation_id: string
  op: SyncOp
  entity?: 'deal' | 'activity'
  record_id?: string
  base_version?: number
  fields: Record<string, unknown>
  client_at: string
}

export type SyncResult = {
  mutation_id: string
  result: 'applied' | 'superseded' | 'rejected'
  id: string | null
  version: number | null
  conflict: boolean
  error: string | null
  detail: string | null
  replayed: boolean
}
