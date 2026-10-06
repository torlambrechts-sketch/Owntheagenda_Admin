// Campaigns fixtures (Phase 6): the design's sending domains, saved segments, the saved «Webinar invite» template and
// the two campaigns that look forward (Marketing.dc.html: domains, segments, layouts, C), called from generate.mjs.
//
// Configuration only. Nothing is sent and nothing is counted: the design's sent campaigns (Lovkrav 2026, Skiftly for
// helse, Verneombud-webinar, Nyhetsbrev september) and every figure they carry are invented, so they are left out, as
// are DNS results (no DNS check has run) and provider verification (no provider is connected). An audience is a
// segment of app.people, which holds no respondent (D-34). No copy claims k = 5 (Q18): the design's title «Fem er
// gulvet» and list line «Resultat for grupper med minst 5 svar» are not seeded.
//
// The rows are written as campaign_save / segment_save / sender_domain_save would write them (the seed runs with
// triggers off); they pass app.campaign_design_check and the tables' constraints.
export function seedCampaigns({ sql, q, uid }) {
  const jonas = uid('staff', 'jonas') // Marketing runs campaigns (spec §6)
  const tor = uid('staff', 'tor') // the Admin configures sender domains (campaigns:configure)
  const json = (v) => `${q(JSON.stringify(v))}::jsonb`

  // ---- sending domains (CMP-08): identity and warm-up as the design gives them; no check results
  const domains = [
    { key: 'news.orgpuls.no', stream: 'marketing', sendsHere: true, product: 'orgpuls', fromName: 'Orgpuls', local: 'news', address: 'Orgpuls AS, Oslo', warm: 60 },
    // Orgpuls's survey invitations: another system sends them, so the platform has no rates for it (Q6)
    { key: 'varsler.orgpuls.no', stream: 'transactional', sendsHere: false, product: 'orgpuls', fromName: 'Orgpuls', local: 'varsler', address: null, warm: 120 },
    // the design gives no postal address for Skiftly: the identity recommendation names the domain until one is entered
    { key: 'news.skiftly.no', stream: 'marketing', sendsHere: true, product: 'skiftly', fromName: 'Skiftly', local: 'news', address: null, warm: 8 },
  ]
  for (const d of domains) {
    sql(`insert into app.sender_domains (id, domain, stream, sends_here, product, from_name, from_local, postal_address, warmup_started_at, warmup_days, created_by, created_at, updated_at)
  values (${q(uid('sender-domain', d.key))}, ${q(d.key)}, ${q(d.stream)}, ${d.sendsHere}, ${q(d.product)}, ${q(d.fromName)}, ${q(d.local)}, ${q(d.address)},
  current_date - ${d.warm}, 30, ${q(tor)}, now() - interval '${d.warm} days', now() - interval '${d.warm} days');`)
  }

  // ---- saved segments (CMP-03), shared by sales and marketing, in the design's order. «Customers without a pulse in
  // 90 days» needs a product-activity filter the people filter does not have (R-CAMPAIGNS-03), so it is left out.
  const segments = [
    ['hr-trial', 'HR in organizations with 26–100 employees on trial', null, [
      { f: 'title', op: 'eq', v: 'HR' },
      { f: 'organization.employees', op: 'gte', v: 26 },
      { f: 'organization.employees', op: 'lte', v: 100 },
      { f: 'organization.status', op: 'eq', v: 'trial' },
      { or: [[{ f: 'engagement.opened_days', op: 'lte', v: 90 }], [{ f: 'fylke', op: 'in', v: ['Vestland', 'Rogaland'] }]] },
    ]],
    ['all-subscribed', 'All subscribed', null, [{ f: 'marketing_status', op: 'eq', v: 'subscribed' }]],
    ['daglig-ledere', 'All daglig ledere', null, [{ f: 'title', op: 'eq', v: 'Daglig leder' }]],
    ['verneombud', 'Verneombud users', 'People who are verneombud users of a product', [{ f: 'member.role', op: 'eq', v: 'verneombud' }]],
    ['health', 'Industry = Health and care', null, [{ f: 'organization.industry', op: 'eq', v: 'Health and care' }]],
    ['win-back', 'Former customers (win-back)', null, [{ f: 'organization.status', op: 'eq', v: 'cancelled' }]],
  ]
  for (const [i, [key, name, description, filters]] of segments.entries()) {
    sql(`insert into app.saved_views (id, screen, kind, name, description, query, owner_id, shared, ord, created_at, updated_at)
  values (${q(uid('segment', key))}, 'people', 'segment', ${q(name)}, ${q(description)}, ${json({ filters })}, ${q(jonas)}, true, ${i + 1}, now() - interval '${20 - i} days', now() - interval '${20 - i} days');`)
  }

  // ---- the saved template «Webinar invite» (CMP-02): structure only, Tor writes the words
  const webinar = { rows: [{ kind: 'header', bg: 'card' }, { kind: 'title', text: '', fs: 26 }, { kind: 'paragraph', text: '' }, { kind: 'button', text: '' }, { kind: 'footer', bg: 'cream' }] }
  const tpl = uid('marketing-template', 'webinar-invite')
  sql(`insert into app.email_templates (id, name, scope, owner_id, subject, kind, layout, design, category, current_version, version, created_at, updated_at)
  values (${q(tpl)}, 'Webinar invite', 'shared', ${q(jonas)}, '', 'marketing', false, ${json(webinar)}, 'webinar', 1, 1, now() - interval '12 days', now() - interval '12 days');`)
  sql(`insert into app.email_template_versions (template_id, version, subject, design, created_by, created_at) values (${q(tpl)}, 1, '', ${json(webinar)}, ${q(jonas)}, now() - interval '12 days');`)

  // ---- campaigns: drafts. «Nyhetsbrev oktober» is scheduled in the design, but scheduling needs a sender domain whose
  // DNS records were found, and no DNS check has run; «Trial nurture — day 2» is Active, which needs the same.
  const newsletter = {
    rows: [
      { kind: 'header', bg: 'card', text: 'Nyhetsbrev · oktober' },
      { kind: 'title', text: '', fs: 26 },
      { kind: 'paragraph', text: 'Fra 1. januar må flere virksomheter dokumentere kartleggingen av det psykososiale arbeidsmiljøet. Her er sjekklisten vi bruker med kundene våre.' },
      { kind: 'image', alt: 'product shot · resultater' },
      { kind: 'list', items: ['Kartlegg alle 11 faktorer på 10 minutter', 'Tiltak med eier og frist'] },
      { kind: 'button', text: 'Les sjekklisten →' },
      { kind: 'divider' },
      { kind: 'social', items: [{ label: 'LinkedIn' }, { label: 'Facebook' }, { label: 'Instagram' }] },
      { kind: 'footer', bg: 'cream' },
    ],
  }
  const nurture = { rows: [{ kind: 'header', bg: 'card' }, { kind: 'paragraph', text: '' }, { kind: 'button', text: '' }, { kind: 'footer', bg: 'cream' }] }
  const layout = `(select id from app.email_templates where kind = 'marketing' and layout and name = 'Newsletter' and deleted_at is null limit 1)`
  sql(`insert into app.campaigns (id, name, type, status, segment_id, template_id, design, subject_a, subject_b, ab_percent, ab_metric, ab_wait, sender_domain_id, product,
  utm_source, utm_medium, utm_campaign, tracking, notify_owners, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${q(uid('campaign', 'nyhetsbrev-oktober'))}, 'Nyhetsbrev oktober', 'newsletter', 'draft', ${q(uid('segment', 'all-subscribed'))}, ${layout}, ${json(newsletter)},
  'Slik kartlegger dere arbeidsmiljøet før nyttår', 'Lovkravet dere må dokumentere i 2026', 20, 'clicks', interval '4 hours', ${q(uid('sender-domain', 'news.orgpuls.no'))}, 'orgpuls',
  'newsletter', 'email', 'okt-2026', true, true, ${q(jonas)}, 'all', ${q(jonas)}, ${q(jonas)}, now() - interval '6 days', now() - interval '2 days');`)
  sql(`insert into app.campaigns (id, name, type, status, design, subject_a, sender_domain_id, product, utm_source, utm_medium, utm_campaign, tracking, notify_owners,
  owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${q(uid('campaign', 'trial-nurture-day-2'))}, 'Trial nurture — day 2', 'automated', 'draft', ${json(nurture)}, '', ${q(uid('sender-domain', 'news.orgpuls.no'))}, 'orgpuls',
  'newsletter', 'email', 'trial-nurture-day-2', true, false, ${q(jonas)}, 'all', ${q(jonas)}, ${q(jonas)}, now() - interval '9 days', now() - interval '9 days');`)
  for (const k of ['nyhetsbrev-oktober', 'trial-nurture-day-2']) {
    sql(`insert into app.changelog (entity, record_id, field, actor_id, source) values ('campaign', ${q(uid('campaign', k))}, '*created', ${q(jonas)}, 'ui');`)
  }
}
