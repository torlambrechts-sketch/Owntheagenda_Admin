/**
 * Brevo's webhook payloads, read the way Sentral may read them (0060). Brevo posts every transactional event of the
 * account here, Orgpuls's survey invitations included, so an event is first sorted by its tag: anything without one of
 * Sentral's tags is dropped before any other field is touched (security rule 6: no respondent data, ever). Nothing here
 * returns an address.
 */
import { SENTRAL_TAGS, type SentralTag } from './brevo.ts'

export type CampaignEvent = {
  event_id: string; kind: 'delivered' | 'bounced' | 'opened' | 'clicked' | 'unsubscribed' | 'complained'
  message_id: string; at: string | null; bounce_kind?: 'hard' | 'soft'; url?: string; client_class?: 'human' | 'prefetch' | 'unknown'
}
export type TicketEvent = { message_id: string; kind: 'delivered' | 'bounced' | 'failed' }
export type Sorted = { campaign: CampaignEvent[]; ticket: TicketEvent[]; dropped: number }

type Raw = Record<string, unknown>
const str = (v: unknown, max = 500) => (typeof v === 'string' && v.length > 0 && v.length <= max ? v : null)

export function tagOf(e: Raw): SentralTag | null {
  const tags = [...(Array.isArray(e.tags) ? e.tags : []), e.tag].filter((t): t is string => typeof t === 'string')
  return (tags.find((t) => (SENTRAL_TAGS as readonly string[]).includes(t)) as SentralTag | undefined) ?? null
}

/** Brevo's event name → what Sentral records (null: nothing to record) */
export function kindOf(event: string): { kind: CampaignEvent['kind']; bounce?: 'hard' | 'soft'; prefetch?: boolean } | null {
  switch (event) {
    case 'delivered': return { kind: 'delivered' }
    case 'hard_bounce': case 'hardBounce': case 'invalid_email': case 'invalid': case 'blocked': case 'error': return { kind: 'bounced', bounce: 'hard' }
    case 'soft_bounce': case 'softBounce': return { kind: 'bounced', bounce: 'soft' }
    case 'spam': case 'complaint': return { kind: 'complained' }
    case 'unsubscribed': case 'unsubscribe': return { kind: 'unsubscribed' }
    case 'opened': case 'unique_opened': case 'uniqueOpened': return { kind: 'opened' }
    case 'proxy_open': return { kind: 'opened', prefetch: true }
    case 'click': return { kind: 'clicked' }
    default: return null
  }
}

export function sortEvents(payload: unknown): Sorted {
  const list: unknown[] = Array.isArray(payload) ? payload : [payload]
  const out: Sorted = { campaign: [], ticket: [], dropped: 0 }
  for (const item of list.slice(0, 1000)) {
    if (!item || typeof item !== 'object') { out.dropped++; continue }
    const e = item as Raw
    const tag = tagOf(e)
    if (tag !== 'sentral-campaign' && tag !== 'sentral-ticket') { out.dropped++; continue }
    const event = str(e.event, 40)
    const id = str(e['message-id'], 200) ?? str(e.messageId, 200)
    const k = event ? kindOf(event) : null
    if (!k || !id) { out.dropped++; continue }
    if (tag === 'sentral-ticket') {
      if (k.kind === 'delivered') out.ticket.push({ message_id: id, kind: 'delivered' })
      else if (k.kind === 'bounced') out.ticket.push({ message_id: id, kind: 'bounced' })
      else out.dropped++
      continue
    }
    const ts = typeof e.ts_event === 'number' ? e.ts_event : typeof e.ts === 'number' ? e.ts : null
    const at = ts ? new Date(ts * 1000).toISOString() : str(e.date, 40)
    const link = k.kind === 'clicked' ? str(e.link, 2000) : null
    out.campaign.push({
      event_id: `${id}:${event}:${ts ?? at ?? ''}${link ? `:${link.length}` : ''}`.slice(0, 200),
      kind: k.kind, message_id: id, at,
      ...(k.bounce ? { bounce_kind: k.bounce } : {}),
      ...(link ? { url: link } : {}),
      ...(k.kind === 'opened' || k.kind === 'clicked' ? { client_class: k.prefetch ? 'prefetch' as const : 'unknown' as const } : {}),
    })
  }
  return out
}

/** Brevo's inbound parsing: the items Sentral may thread (sender address, subject, the new text, Brevo's id) */
export type Inbound = { id: string; from: string; subject: string; body: string }
export function inboundItems(payload: unknown): Inbound[] {
  const items = payload && typeof payload === 'object' && Array.isArray((payload as Raw).items) ? ((payload as Raw).items as unknown[]) : []
  const out: Inbound[] = []
  for (const it of items.slice(0, 50)) {
    if (!it || typeof it !== 'object') continue
    const e = it as Raw
    const uuid = Array.isArray(e.Uuid) ? str(e.Uuid[0], 200) : str(e.Uuid, 200)
    const id = uuid ?? str(e.MessageId, 200)
    const from = e.From && typeof e.From === 'object' ? str((e.From as Raw).Address, 254) : null
    const subject = str(e.Subject, 500) ?? ''
    const body = str(e.ExtractedMarkdownMessage, 20000) ?? str(e.RawTextBody, 20000)
    if (id && from && body) out.push({ id, from, subject, body })
  }
  return out
}
