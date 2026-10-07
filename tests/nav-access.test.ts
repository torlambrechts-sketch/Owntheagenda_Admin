import { describe, expect, it } from 'vitest'
import { NAV, routeVisible, type RouteKey } from '@/lib/nav'

const all = NAV.flatMap((g) => g.items)
const menu = (rights: string[], extra: Partial<Parameters<typeof routeVisible>[1]> = {}) =>
  all.filter((k) => routeVisible(k, { admin: false, rights, modules: {}, ...extra }))

// The menu offers only what the person can open (the seeded permission sets)
describe('menu by rights', () => {
  it('an admin sees every route the modules allow', () => {
    expect(all.filter((k) => routeVisible(k, { admin: true, rights: [], modules: {} }))).toEqual(all)
    expect(routeVisible('projects', { admin: true, rights: [], modules: { projects: false } })).toBe(false)
  })

  it('a projects-only person sees projects and the views everyone has, no CRM or customers', () => {
    const m = menu(['projects:see', 'projects:add', 'projects:edit_others', 'projects:ai'])
    expect(m).toEqual(['home', 'projects', 'automation', 'insights', 'api', 'settings', 'security', 'coverage'] satisfies RouteKey[])
  })

  it('sales sees the CRM and customers but not campaigns or analytics', () => {
    const m = menu(['deals:see', 'deals:add', 'global:see', 'tickets:see'])
    expect(m).toContain('deals')
    expect(m).toContain('customers')
    expect(m).toContain('tickets')
    expect(m).toContain('leadgen')
    expect(m).not.toContain('campaigns')
    expect(m).not.toContain('analytics')
    expect(m).not.toContain('projects')
  })

  it('analytics opens with either reports right; the meeting workspace switch hides meetings', () => {
    expect(menu(['campaigns:reports_others'])).toContain('analytics')
    expect(menu(['deals:see'], { meetingsWorkspace: false })).not.toContain('meetings')
    expect(menu(['deals:see'])).toContain('meetings')
  })
})

// Sentral Simple's rail: the four sections by role
import { SECTIONS } from '@/lib/nav'
describe('simple rail by rights', () => {
  const rail = (rights: string[], admin = false) => SECTIONS.map((s) => s.key).filter((k) => routeVisible(k, { admin, rights, modules: {} }))
  it('an admin sees all four sections', () => expect(rail([], true)).toEqual(['customers', 'crm', 'growth', 'platform']))
  it('support sees customers (tickets) and platform', () => expect(rail(['tickets:see', 'global:see'])).toEqual(['customers', 'platform']))
  it('sales sees customers and CRM', () => expect(rail(['deals:see', 'global:see'])).toEqual(['customers', 'crm', 'platform']))
  it('marketing sees growth through the campaigns right', () => expect(rail(['campaigns:see'])).toEqual(['growth', 'platform']))
})
