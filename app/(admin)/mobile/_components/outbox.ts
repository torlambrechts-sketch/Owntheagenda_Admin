'use client'

import type { Mutation } from '@/lib/data/mobile-shared'

/**
 * The device's outbox (SF-31) for the preview: the changes made while offline, in order, with their mutation ids made once
 * at the moment of the change, so sending the same change again (a lost answer, a reload) returns the stored result and
 * changes nothing. Kept in this browser's storage; when storage is unavailable (a private window), it lives in memory for
 * the visit. It holds record ids, stage ids and record names, never coordinates.
 *
 * A check-in or a logged call offline is two steps the server applies in order: create the activity, then mark it done
 * with the id the first step returned. Both ids exist before the first is sent.
 */
export type OutboxKind = 'checkin' | 'call' | 'stage'
export type OutboxItem = {
  kind: OutboxKind
  title: string
  first: Mutation
  then: { mutation_id: string } | null
  created_id: string | null
}

const mem: Record<string, string> = {}
const read = (k: string): string | null => {
  try {
    const v = window.localStorage.getItem(k)
    if (v !== null) return v
  } catch {}
  return mem[k] ?? null
}
const write = (k: string, v: string) => {
  mem[k] = v
  try { window.localStorage.setItem(k, v) } catch {}
}

export const newId = () => crypto.randomUUID()

/** This browser's device id (sync_receipts are per device). */
export function deviceId(): string {
  const k = 'sentral.mobile.device'
  let v = read(k)
  if (!v || !/^[0-9a-f-]{36}$/.test(v)) { v = newId(); write(k, v) }
  return v
}

const outboxKey = (staff: string) => `sentral.mobile.outbox.${staff}`
export function loadOutbox(staff: string): OutboxItem[] {
  try {
    const v = JSON.parse(read(outboxKey(staff)) ?? '[]')
    return Array.isArray(v) ? (v as OutboxItem[]).filter((x) => x && x.first && typeof x.first.mutation_id === 'string') : []
  } catch {
    return []
  }
}
export const saveOutbox = (staff: string, items: OutboxItem[]) => write(outboxKey(staff), JSON.stringify(items))

const cursorKey = (staff: string) => `sentral.mobile.cursor.${staff}`
export const loadCursor = (staff: string) => { const n = Number(read(cursorKey(staff)) ?? 0); return Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0 }
export const saveCursor = (staff: string, n: number) => write(cursorKey(staff), String(n))

/** The mutation that finishes a two-step item, once the first step returned the activity's id. */
export const secondStep = (item: OutboxItem): Mutation | null =>
  item.then && item.created_id
    ? { mutation_id: item.then.mutation_id, op: 'activity_done', record_id: item.created_id, fields: { done: true }, client_at: item.first.client_at }
    : null
