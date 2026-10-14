import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { LEADERPACT_COMMANDS } from '@/supabase/functions/_shared/leaderpact.ts'
import { ORGPULS_COMMANDS } from '@/supabase/functions/_shared/orgpuls.ts'
import { PRODUCT_SCOPES } from '@/lib/data/platform-shared'

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

  const sql0091 = readFileSync(new URL('../supabase/migrations/0091_leaderpact_commands.sql', import.meta.url), 'utf8')
  const block = (from: string, to: string) => {
    const start = sql0091.indexOf(from)
    return sql0091.slice(start, sql0091.indexOf(to, start))
  }

  it('seeds exactly LEADERPACT_COMMANDS with their scopes (0091)', () => {
    const b = block("select 'leaderpact', c, s, u, d", ') as x(c, s, u, d)')
    const seeded = Object.fromEntries([...b.matchAll(/\('([a-z]+\.[a-z_]+)', '([a-z]+:(?:read|write))'/g)].map((m) => [m[1], m[2]]))
    expect(seeded).toEqual({ ...LEADERPACT_COMMANDS })
  })

  it('lets an installation hold every scope a registry uses, users:* included, and the database the same list', () => {
    const used = new Set([...Object.values(ORGPULS_COMMANDS), ...Object.values(LEADERPACT_COMMANDS)])
    for (const s of used) expect(PRODUCT_SCOPES).toContain(s)
    expect(PRODUCT_SCOPES).toEqual(expect.arrayContaining(['users:read', 'users:write']))
    const fn = block('create or replace function app.installation_scopes()', '$fn$;')
    const check = block('add constraint installations_scopes_check', ');')
    const list = (t: string) => [...t.matchAll(/'([a-z]+:(?:read|write))'/g)].map((m) => m[1]).sort()
    expect(list(fn)).toEqual([...PRODUCT_SCOPES].sort())
    expect(list(check)).toEqual([...PRODUCT_SCOPES].sort())
    // application_connect and application_update ask the one list, not a copy of it
    expect(block('create or replace function public.application_connect', 'end $fn$;')).toContain('v_scopes <@ app.installation_scopes()')
    expect(block('create or replace function public.application_update', 'end $fn$;')).toContain('v_scopes <@ app.installation_scopes()')
  })

  it('gives LeaderPact\'s installation exactly the scopes its commands need', () => {
    const b = block("update app.installations set scopes", ';')
    const given = [...b.matchAll(/'([a-z]+:(?:read|write))'/g)].map((m) => m[1]).sort()
    expect(given).toEqual([...new Set(Object.values(LEADERPACT_COMMANDS))].sort())
  })

  it('names what each of LeaderPact\'s events feeds, with a known use', () => {
    const b = block("select 'leaderpact', k, u", ') as x(k, u)')
    const kinds = [...b.matchAll(/\('([a-z_]+\.[a-z_]+)', array\[([^\]]*)\]\)/g)].map((m) => m[1])
    expect(kinds.sort()).toEqual(['billing.changed', 'member.invited', 'member.joined', 'member.left', 'org.created', 'org.deleted', 'usage.daily'])
    const known = ['crm', 'funnel', 'billing', 'health', 'activation', 'usage', 'tickets', 'leads', 'workflows', 'support_access', 'content']
    for (const m of b.matchAll(/array\[([^\]]*)\]/g)) for (const u of m[1]!.matchAll(/'([a-z_]+)'/g)) expect(known).toContain(u[1])
  })
})

// product-command takes the product from the request and uses it everywhere: authorize, installation, secret, audience, audit
describe('product-command per product', () => {
  const src = readFileSync(new URL('../supabase/functions/product-command/index.ts', import.meta.url), 'utf8')
  const code = src.slice(src.indexOf('*/'))
  it('names no product of its own', () => {
    expect(code).not.toMatch(/'orgpuls'|'leaderpact'/)
  })
  it('checks the product and the command against the registry before anything else', () => {
    expect(code).toMatch(/!isCommandProduct\(product\) \|\| !isProductCommand\(product, input\.command\)/)
    expect(code.indexOf('isCommandProduct(product)')).toBeLessThan(code.indexOf("rpc('admin_whoami')"))
  })
  it('reads the product\'s own secret and installation, signs for it and audits under it', () => {
    expect(code).toContain('productSecret(svc, `${product}_token_secret`)')
    expect(code).toContain("rpc('installation_of', { p_product: product })")
    expect(code).toContain('commandClaims(product, actor, command,')
    expect(code.match(/p_product: product/g)?.length).toBe(4)
    expect(code).toContain('p_arg_names: Object.keys(args).sort()')
  })
})
