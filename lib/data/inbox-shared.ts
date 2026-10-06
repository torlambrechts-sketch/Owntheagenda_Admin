/**
 * What the Inbox's server and client code share: the folders the rail offers, the send-at choices and the
 * instant each names in the staff member's time zone, and the client checks the composer makes.
 */
import { fromZoned, zoned } from '@/lib/data/activities-time'

export const FOLDERS = ['inbox', 'team', 'archive', 'label', 'outbox', 'group', 'messaging', 'calls', 'settings'] as const
export type Folder = (typeof FOLDERS)[number]
export const MAIL_FOLDERS: readonly Folder[] = ['inbox', 'team', 'archive', 'label']

export const SEND_AT = ['now', 'tomorrow', 'monday'] as const
export type SendAt = (typeof SEND_AT)[number]

/**
 * The instant a send-at choice names, in the staff member's time zone (D-04): «Tomorrow 08:00» is the next
 * calendar day at 08:00; «Monday 09:00» is the next Monday after today at 09:00. «Send now» is null.
 */
export function sendAtInstant(choice: SendAt, now: Date, tz: string): Date | null {
  if (choice === 'now') return null
  const z = zoned(now, tz)
  const base = Date.UTC(z.y, z.m - 1, z.d)
  const isoDow = ((new Date(base).getUTCDay() + 6) % 7) + 1 // 1 = Monday
  const add = choice === 'tomorrow' ? 1 : 8 - isoDow
  const day = new Date(base + add * 86_400_000)
  return fromZoned({ y: day.getUTCFullYear(), m: day.getUTCMonth() + 1, d: day.getUTCDate() }, choice === 'tomorrow' ? 8 : 9, 0, tz)
}

/** The composer's missing-attachment check (COM): the text mentions an attachment and none is added. */
export const mentionsAttachment = (body: string) => /vedlagt|vedlegg|attach/i.test(body)

/** The [Token] merge fields a text uses. */
export const mergeTokens = (text: string) => [...new Set([...text.matchAll(/\[([A-Za-zÆØÅæøå]+\.[A-Za-zÆØÅæøå]+)\]/g)].map((m) => m[1]!))]

/** Addresses typed in the To field: separated by commas, semicolons or spaces. */
export const parseAddresses = (s: string) => s.split(/[,;\s]+/).map((x) => x.trim().toLowerCase()).filter(Boolean)
export const isAddress = (s: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s) && s.length <= 254

/** «Re: » once. */
export const replySubject = (s: string) => (/^(re|sv|aw):/i.test(s.trim()) ? s.trim() : `Re: ${s.trim()}`)

/** A mailbox may send while it is synced or syncing (app.mail_enqueue). */
export const connected = (status: string) => status === 'synced' || status === 'syncing'
