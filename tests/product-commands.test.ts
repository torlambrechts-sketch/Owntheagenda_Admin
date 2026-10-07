import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { ORGPULS_COMMANDS } from '@/supabase/functions/_shared/orgpuls.ts'

// app.product_commands (0044) mirrors the allow-list product-command signs from: same commands, same scopes.
// The TS list stays the authority; this test fails when one changes without the other.
describe('product_commands mirror', () => {
  it('seeds exactly ORGPULS_COMMANDS with their scopes', () => {
    const sql = readFileSync(new URL('../supabase/migrations/0044_platform.sql', import.meta.url), 'utf8')
    const start = sql.indexOf('insert into app.product_commands')
    const block = sql.slice(start, sql.indexOf(') as x(c, s, u, d);', start))
    const seeded = Object.fromEntries([...block.matchAll(/\('([a-z]+\.[a-z_]+)', '([a-z]+:(?:read|write))'/g)].map((m) => [m[1], m[2]]))
    expect(seeded).toEqual({ ...ORGPULS_COMMANDS })
  })
})
