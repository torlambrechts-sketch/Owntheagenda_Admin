import { describe, expect, it } from 'vitest'
import {
  bugMarkdown, bugPath, bugStatus, dueState, durationParts, featureMarkdown, featurePath, fileStatus, initials, linkToken, neighbour,
  parseReleaseNotes, parseSpecDraft, parseTaskPlan, share, slug, sprintDates, yaml, type FeatureRecord,
} from '../app/(admin)/development/_components/core/logic'

describe('Development: due labels (Bug triage)', () => {
  it('due later today reads «Due today» with the Oslo time', () => {
    expect(dueState('2026-10-12T14:00:00Z', '2026-10-12T08:00:00Z')).toEqual({ kind: 'today', time: '16:00' })
  })
  it('counts calendar days left in Oslo', () => {
    expect(dueState('2026-10-15T08:00:00Z', '2026-10-12T20:00:00Z')).toEqual({ kind: 'left', days: 3 })
    // 23:30 in Oslo on the 12th is already the 13th in UTC terms of the due date's day
    expect(dueState('2026-10-13T10:00:00Z', '2026-10-12T21:30:00Z')).toEqual({ kind: 'left', days: 1 })
  })
  it('a passed due time is overdue by whole days', () => {
    expect(dueState('2026-10-10T14:00:00Z', '2026-10-12T08:00:00Z')).toEqual({ kind: 'overdue', days: 2 })
    expect(dueState('2026-10-12T07:00:00Z', '2026-10-12T08:00:00Z')).toEqual({ kind: 'overdue', days: 0 })
  })
})

describe('Development: figures', () => {
  it('a duration in minutes, hours or days', () => {
    expect(durationParts(0.2)).toEqual({ unit: 'min', value: 12, decimals: 0 })
    expect(durationParts(4.4)).toEqual({ unit: 'h', value: 4, decimals: 0 })
    expect(durationParts(45.6)).toEqual({ unit: 'd', value: 1.9, decimals: 1 })
    expect(durationParts(48)).toEqual({ unit: 'd', value: 2, decimals: 0 })
  })
  it('a share has no value without a whole', () => {
    expect(share(3, 4)).toBe(75)
    expect(share(0, 0)).toBeNull()
  })
  it('initials from the stored ones or the name', () => {
    expect(initials('Magnus Berg', null)).toBe('MB')
    expect(initials('Tor', null)).toBe('TO')
    expect(initials('Eirik Lund', 'el')).toBe('EL')
    expect(initials(null)).toBe('—')
  })
  it('a sprint in one month and across two', () => {
    expect(sprintDates('2026-10-05', '2026-10-16', 'en-GB')).toBe('5–16 Oct')
    expect(sprintDates('2026-10-26', '2026-11-06', 'en-GB')).toBe('26 Oct–6 Nov')
  })
  it('the keyboard moves a card one column, not past the ends', () => {
    expect(neighbour('backlog', 1)).toBe('spec')
    expect(neighbour('review', -1)).toBe('in_progress')
    expect(neighbour('backlog', -1)).toBeNull()
    expect(neighbour('done', 1)).toBeNull()
  })
})

describe('Development: Claude drafts read into records', () => {
  it('a spec draft by its five headings', () => {
    const s = parseSpecDraft('## Problem\nToo many stop.\n\n## Options\nA or B\n## Decision\nB\n## Privacy and anonymity\nNo survey data.\n## Rollout\nInternal first.')
    expect(s).toEqual({ problem: 'Too many stop.', options: 'A or B', decision: 'B', privacy: 'No survey data.', rollout: 'Internal first.' })
  })
  it('Norwegian headings are read too', () => {
    const s = parseSpecDraft('## Problem\nP\n## Alternativer\nA\n## Beslutning\nB\n## Personvern og anonymitet\nV\n## Utrulling\nU')
    expect(s.options).toBe('A')
    expect(s.privacy).toBe('V')
    expect(s.rollout).toBe('U')
  })
  it('a draft without the headings goes into Problem whole', () => {
    expect(parseSpecDraft('Just one paragraph.').problem).toBe('Just one paragraph.')
  })
  it('a task plan: one work item per line, its kind, at most 20', () => {
    expect(parseTaskPlan('Intro line\n- Story: Email first step\n- Task: Move org.nr\n* Spike – SAML or OIDC\n1. Write the tests\n- ab')).toEqual([
      { kind: 'story', title: 'Email first step' },
      { kind: 'task', title: 'Move org.nr' },
      { kind: 'spike', title: 'SAML or OIDC' },
      { kind: 'task', title: 'Write the tests' },
    ])
    expect(parseTaskPlan(Array.from({ length: 30 }, (_, i) => `- Task: Item ${i}`).join('\n'))).toHaveLength(20)
  })
  it('release notes: New, Improved, Fixed; other lines are left', () => {
    expect(parseReleaseNotes('Here you go:\n- New: Pulse surveys\n- **Improved**: Faster lookup\n- Fixed: Reminder sent twice\n- Other: no')).toEqual([
      { kind: 'new', title: 'Pulse surveys' },
      { kind: 'improved', title: 'Faster lookup' },
      { kind: 'fixed', title: 'Reminder sent twice' },
    ])
    expect(parseReleaseNotes('- Rettet: Påminnelse sendt to ganger')).toEqual([{ kind: 'fixed', title: 'Påminnelse sendt to ganger' }])
  })
})

describe('Development: the Markdown roadmap', () => {
  const item: FeatureRecord = {
    key: 'OP-12', product: 'orgpuls', title: 'Email-first signup', goal: 'visit→account +25 %', status: 'in_progress', owner: 'Tor Lambrechts',
    spec: 'RFC-014', problem: 'Too many stop at org.nr.',
    links: [{ kind: 'feature_request', label: 'FR-3', title: 'Email first' }, { kind: 'ticket', label: 'T-2316', title: null }, { kind: 'experiment', label: null, title: 'Price calculator, v2' }],
    tasks: [{ key: 'OP-13', title: 'Email step', done: true }, { key: 'OP-14', title: 'E2E test', done: false }],
    log: [{ at: '2026-10-12T10:00:00Z', by: 'Tor', action: 'dev_roadmap.moved', detail: { lane: 'now' } }, { at: '2026-10-11T09:00:00Z', by: 'Tor', action: 'dev_roadmap.added', detail: null }],
  }
  it('file names follow the starter kit', () => {
    expect(featurePath(item)).toBe('roadmap/features/OP-12-email-first-signup.md')
    expect(bugPath({ number: 118, title: 'Invitations not delivered to kommune.no' })).toBe('roadmap/bugs/BUG-118-invitations-not-delivered-to-kommune-no.md')
    expect(slug('Tiltak: to eiere på én åpen sak')).toBe('tiltak-to-eiere-pa-en-apen-sak')
    expect(fileStatus('in_progress')).toBe('in-progress')
  })
  it('a feature file: front matter, problem, tasks and the log oldest first', () => {
    const md = featureMarkdown(item, (e) => `${e.by}: ${e.action}`)
    expect(md).toContain('id: OP-12\ntitle: Email-first signup\nstatus: in-progress\nowner: Tor Lambrechts\nproduct: orgpuls\npriority: —')
    expect(md).toContain('metric: "visit→account +25 %"')
    expect(md).toContain('links: [FR-3, T-2316, experiment: Price calculator v2]')
    expect(md).toContain('## Tasks\n- [x] OP-13 Email step\n- [ ] OP-14 E2E test')
    expect(md.indexOf('dev_roadmap.added')).toBeLessThan(md.indexOf('dev_roadmap.moved'))
    expect(md).toContain('- 2026-10-11 Tor: dev_roadmap.added')
  })
  it('a title YAML would misread is quoted', () => {
    expect(yaml('Plain title')).toBe('Plain title')
    expect(yaml('Signup v2: email first')).toBe('"Signup v2: email first"')
    expect(yaml('- dash first')).toBe('"- dash first"')
    expect(yaml(null)).toBe('—')
    expect(linkToken({ kind: 'seo_plan', label: null, title: 'hvordan måle arbeidsmiljø' })).toBe('seo: hvordan måle arbeidsmiljø')
  })
  it('a bug file: severity as priority, customers, tickets and the problem', () => {
    const md = bugMarkdown({ number: 3, product: 'orgpuls', title: 'Invitations bounce', severity: 's1', state: 'open', owner: null, customers: 3,
                             ticketNumbers: [2311, 2312], problemNumber: 2316, workStatus: 'review', tasks: [], log: [] }, () => '')
    expect(md).toContain('id: BUG-3')
    expect(md).toContain('status: review')
    expect(md).toContain('priority: S1\ncustomers: 3\nlinks: [T-2311, T-2312, problem T-2316]')
  })
  it('a bug without a card is backlog while open and done once closed', () => {
    expect(bugStatus({ state: 'open', workStatus: null })).toBe('backlog')
    expect(bugStatus({ state: 'fixed', workStatus: null })).toBe('done')
    expect(bugStatus({ state: 'open', workStatus: 'staging' })).toBe('staging')
  })
})
