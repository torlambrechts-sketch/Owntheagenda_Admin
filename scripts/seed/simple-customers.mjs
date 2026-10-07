// Sentral Simple · Customers (SimpleCustomers.dc.html, 0056): the structured request on the design's service requests, as
// the product's support.requested payload carries it ({kind, args}) — Customers › Tickets and requests › Requests shows it
// and «Approve and apply» works for the trial extension. Personvern requests carry none (they follow the 30-day clock),
// and the kinds without a product command (a plan change, an invoice switch, an ownership transfer, a data export) show
// their request with approval disabled. Called from generate.mjs after the tickets.
const REQUESTS = [
  [2312, { kind: 'extend_trial', args: { days: 14 } }], // Extend trial by 14 days — board meeting moved
  [2321, { kind: 'change_plan', args: { plan: '26–100' } }], // Change plan to 26–100 band
  [2315, { kind: 'other', args: {} }], // Switch from card to EHF invoice
  [2324, { kind: 'other', args: {} }], // Data export for annual HSE report
  [2333, { kind: 'other', args: {} }], // Transfer ownership to new daglig leder
]

export function seedSimpleCustomers({ sql, q }) {
  for (const [n, request] of REQUESTS) {
    sql(`update app.tickets set request = ${q(JSON.stringify(request))}::jsonb where number = ${n} and type = 'service_request';`)
  }
}
