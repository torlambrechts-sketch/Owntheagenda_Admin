import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { NOTIFICATION_KINDS } from '@/lib/notification-kinds'

// The bell parses every notification with these kinds; a kind the database allows but the app does not know would
// make the whole list fail to load. The newest migration that defines the check is the database's list.
describe('notification kinds', () => {
  it('match the newest notifications_kind_check', () => {
    const dir = join(process.cwd(), 'supabase/migrations')
    const defs = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
      .flatMap((f) => [...readFileSync(join(dir, f), 'utf8').matchAll(/notifications_kind_check\s+check\s*\(\s*kind\s+in\s*\(([^)]*)\)/gi)].map((m) => m[1]!))
    const last = defs.at(-1)
    expect(last).toBeDefined()
    const kinds = [...last!.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort()
    expect([...NOTIFICATION_KINDS].sort()).toEqual(kinds)
  })
})
