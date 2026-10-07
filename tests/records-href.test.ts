import { describe, expect, it } from 'vitest'
import { recordHref } from '@/lib/records-href'

// Sentral Simple (S5): a deal and a ticket open in their sections; the old addresses redirect there too
describe('record links', () => {
  const id = '4b2d1c7e-0f3a-4c55-9a1e-2f6d8b9c0a11'
  it('a deal opens in CRM', () => expect(recordHref('deal', id)).toBe(`/crm?deal=${id}`))
  it('a ticket opens in Customers › Tickets and requests', () => expect(recordHref('ticket', id)).toBe(`/customers?tab=tickets&ticket=${id}`))
  it('an organization opens in Customers', () => expect(recordHref('organization', id)).toBe(`/customers?org=${id}`))
})
