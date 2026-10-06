// Phase 6 · Projects (Projects.dc.html): the design's boards, phases, seven projects with their work items, the
// phase history behind «Duration by phase», and the three templates. Called from generate.mjs.
//
// Dates are relative to the seed's today (the design's 6 October 2026), so lateness and the timeline's today line
// stay true whenever the database is rebuilt. Progress, lateness, counts per health and median days are never
// stored: the screen computes them from these rows. Where the design's literals cannot be backed by rows they are
// left out and logged in docs/crm-enrichment/deviations/projects.md (V-PROJECTS-*):
// - no file rows: «Oppstartsplan.pdf» and «Ansattliste-mal.xlsx» would be listed with no object behind them;
// - no AI summary: no AI provider is connected, so nothing could have suggested «At risk»;
// - «Mona Hansen» is not a person in the design's data, so Kari Nordmann is the one customer-side assignee;
// - a project's person is a person of its own organisation (the design picks people of other organisations);
// - only the projects whose deal exists in the design's data are linked to it (Lumio, Fjellheim).
//
// Every row passes the schema's guards (a phase on its own board, one level of subtasks, no dependency cycle, an
// append-only phase history): check them with triggers on in a rolled-back session (begin; … rollback;).

export function seedProjects({ sql, q, uid, D }) {
  const staff = (id) => q(uid('staff', id))
  const day = (n) => `((now() at time zone 'Europe/Oslo')::date + ${n})`
  const at = (n) => `(now() - interval '${n} days')`
  const tor = staff('tor')

  // ---- boards and phases: the design's three boards and its four phases with their colours (viz)
  const PHASES = [['Kickoff', '#F6D9C6'], ['Setup', '#DCEBD3'], ['First survey', '#CFE0F5'], ['Handover', '#E7DAF2']]
  const boards = ['Customer onboarding', 'Implementation — public sector', 'Training delivery']
  const phaseId = (board, phase) => q(uid('project-phase', `${board}/${phase}`))
  for (const [i, b] of boards.entries()) {
    sql(`insert into app.project_boards (id, name, ord, created_by, created_at) values (${q(uid('project-board', b))}, ${q(b)}, ${(i + 1) * 10}, ${tor}, ${at(60)});`)
    for (const [j, [p, color]] of PHASES.entries()) {
      sql(`insert into app.project_phases (id, board_id, name, ord, color, created_at) values (${phaseId(b, p)}, ${q(uid('project-board', b))}, ${q(p)}, ${(j + 1) * 10}, ${q(color)}, ${at(60)});`)
    }
  }
  const board = boards[0]

  // ---- templates (Projects.dc.html, templates; the plan its Gantt draws for the onboarding template)
  // plan rows: [key, kind, name, group, start offset, length in days (task) | null (milestone)]
  const PLAN = [
    ['kickoff', 'task', 'Kickoff meeting', 'Kickoff', 0, 3],
    ['upload', 'task', 'Upload employee list', 'Kickoff', 3, 8],
    ['ready', 'milestone', 'Employee list ready', 'Kickoff', 11, null],
    ['configure', 'task', 'Configure departments', 'Setup', 12, 10],
    ['invite', 'task', 'Invite HR and leaders', 'Setup', 20, 8],
    ['schedule', 'task', 'Schedule baseline', 'First survey', 30, 6],
    ['sent', 'milestone', 'Baseline sent', 'First survey', 37, null],
    ['review', 'task', 'Result review with HR', 'First survey', 52, 8],
    ['handover', 'milestone', 'Handover to CSM', 'Handover', 72, null],
  ]
  const PLAN_DEPS = [['upload', 'ready'], ['ready', 'configure'], ['schedule', 'sent']]
  const templates = [
    ['onboarding', 'Customer onboarding — Orgpuls', 'phases', board, PHASES.map(([p]) => p), PLAN, PLAN_DEPS],
    ['skiftly', 'Skiftly rollout', 'phases', board, [], [['import', 'task', 'Import shifts', null, 0, 1], ['train', 'task', 'Train shift leads', null, 5, 1], ['live', 'milestone', 'First live week', null, 14, null]],
      [['import', 'train'], ['train', 'live']]],
    ['municipality', 'Municipality pilot', 'groups', boards[1], [], [['scope', 'task', 'Agree scope with HR', null, 0, 1], ['briefing', 'task', 'Verneombud briefing', null, 10, 1], ['report', 'milestone', 'Pilot report', null, 45, null]], []],
  ]
  for (const [key, name, org, b, groups, items, deps] of templates) {
    const tid = q(uid('project-template', key))
    sql(`insert into app.project_templates (id, name, organized_by, board_id, created_by, updated_by, created_at, updated_at) values (${tid}, ${q(name)}, ${q(org)}, ${q(uid('project-board', b))}, ${tor}, ${tor}, ${at(45)}, ${at(12)});`)
    for (const [i, g] of groups.entries()) {
      sql(`insert into app.project_template_groups (id, template_id, name, ord, phase_id) values (${q(uid('project-template-group', `${key}/${g}`))}, ${tid}, ${q(g)}, ${(i + 1) * 10}, ${phaseId(b, g)});`)
    }
    for (const [i, [k, kind, n, g, x, w]] of items.entries()) {
      sql(`insert into app.project_template_items (id, template_id, group_id, kind, name, start_offset_days, due_offset_days, assignee, ord) values (${q(uid('project-template-item', `${key}/${k}`))}, ${tid},
  ${g ? q(uid('project-template-group', `${key}/${g}`)) : 'null'}, ${q(kind)}, ${q(n)}, ${kind === 'milestone' ? 'null' : x}, ${kind === 'milestone' ? x : x + w - 1}, ${q(k === 'kickoff' ? 'owner' : 'unassigned')}, ${(i + 1) * 10});`)
    }
    for (const [a, b2] of deps) {
      sql(`insert into app.project_template_dependencies (template_id, predecessor_id, successor_id) values (${tid}, ${q(uid('project-template-item', `${key}/${a}`))}, ${q(uid('project-template-item', `${key}/${b2}`))});`)
    }
  }

  // ---- projects (Projects.dc.html, projs): [key, name, org, phase, health, owner, design done, design total, deal,
  // finished stays in earlier phases (days, in board order), days in the current phase]
  const projects = [
    ['p1', 'Lumio AS — Skiftly onboarding', 'o1', 'Kickoff', 'at_risk', 'emma', 5, 14, 'd101', [], 6],
    ['p2', 'Fjellheim skole — full platform', 'o15', 'Setup', 'on_track', 'emma', 9, 16, 'd201', [9], 5],
    ['p3', 'Solstrand Helse — Avvikspunkt', 'o4', 'Setup', 'on_track', 'magnus', 11, 18, null, [8], 3],
    ['p4', 'Elvebakken kommune — pilot', 'o8', 'First survey', 'off_track', 'emma', 7, 20, null, [10, 16], 4],
    ['p5', 'Bergheim Bygg — group rollout', 'o3', 'Kickoff', 'on_hold', 'magnus', 1, 22, null, [], 20],
    ['p6', 'Mørkved IT — upgrade', 'o12', 'Handover', 'on_track', 'emma', 15, 16, null, [9, 17, 21], 2],
    ['p7', 'Tveit Omsorg — verneombud training', 'o21', 'First survey', 'at_risk', 'emma', 6, 10, null, [11, 15], 6],
  ]
  const groupId = (pk, g) => q(uid('project-group', `${pk}/${g}`))
  const itemId = (pk, k) => q(uid('project-item', `${pk}/${k}`))
  for (const [pk, name, org, phase, health, owner, done, total, deal, stays, current] of projects) {
    const id = q(uid('project', pk))
    const person = D.people.find((p) => p.org === org)
    const started = stays.reduce((a, b) => a + b, 0) + current
    const visibility = pk === 'p1' ? 'group' : 'all'
    sql(`insert into app.projects (id, name, board_id, phase_id, phase_entered_at, health, health_set_at, health_set_by, health_source, starts_on, ends_on, person_id, organization_id,
  template_id, created_source, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${id}, ${q(name)}, ${q(uid('project-board', board))}, ${phaseId(board, phase)}, ${at(current)}, ${q(health)}, ${at(Math.min(current, 2))}, ${staff(owner)}, 'manual',
  ${day(-started)}, ${day(74 - started)}, ${person ? q(uid('person', person.id)) : 'null'}, ${q(uid('org', org))}, ${q(uid('project-template', 'onboarding'))}, ${q(deal ? 'deal' : 'ui')},
  ${staff(owner)}, ${q(visibility)}, ${staff(owner)}, ${staff(owner)}, ${at(started)}, ${at(Math.min(current, 2))});`)
    if (deal) sql(`insert into app.project_deals (project_id, deal_id, is_primary, linked_by, linked_at) values (${id}, ${q(uid('deal', deal))}, true, ${staff(owner)}, ${at(started)});`)
    // the phase history: a finished stay per earlier phase, then the open stay in the current one
    let back = started
    for (const [i, len] of stays.entries()) {
      sql(`insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, left_at, moved_by, source) values (${id}, ${q(uid('project-board', board))}, ${phaseId(board, PHASES[i][0])}, ${at(back)}, ${at(back - len)}, ${staff(owner)}, 'ui');`)
      back -= len
    }
    sql(`insert into app.project_phase_history (project_id, board_id, phase_id, entered_at, moved_by, source) values (${id}, ${q(uid('project-board', board))}, ${phaseId(board, phase)}, ${at(current)}, ${staff(owner)}, 'ui');`)
    // groups: the template's phases, each tied to its phase of the board
    for (const [i, [g]] of PHASES.entries()) {
      sql(`insert into app.project_groups (id, project_id, name, ord, phase_id, created_at) values (${groupId(pk, g)}, ${id}, ${q(g)}, ${(i + 1) * 10}, ${phaseId(board, g)}, ${at(started)});`)
    }

    if (pk === 'p1') continue // the drawer's own plan, below
    // the template's plan dated from the project's start; the earliest items are done in the design's proportion
    const doneCount = Math.round((done / total) * PLAN.length)
    for (const [i, [k, kind, n, g, x, w]] of PLAN.entries()) {
      const due = x + (w ?? 1) - 1 - started
      const isDone = i < doneCount
      sql(`insert into app.project_items (id, project_id, kind, group_id, name, owner_id, starts_on, due_on, done, done_at, done_by, ord, source, template_item_id, created_at, updated_at)
  values (${itemId(pk, k)}, ${id}, ${q(kind)}, ${groupId(pk, g)}, ${q(n)}, ${k === 'kickoff' ? staff(owner) : 'null'}, ${kind === 'milestone' ? 'null' : day(x - started)}, ${day(due)},
  ${isDone}, ${isDone ? `(${day(Math.min(due, 0))})::timestamptz + interval '15 hours'` : 'null'}, ${isDone ? staff(owner) : 'null'}, ${(i + 1) * 10}, 'template',
  ${q(uid('project-template-item', `onboarding/${k}`))}, ${at(started)}, ${at(started)});`)
    }
    for (const [a, b] of PLAN_DEPS) sql(`insert into app.project_item_dependencies (predecessor_id, successor_id, created_by, created_at) values (${itemId(pk, a)}, ${itemId(pk, b)}, ${staff(owner)}, ${at(started)});`)
  }

  // ---- Lumio's plan as the drawer and the timeline draw it (Projects.dc.html, I and G): kickoff done with its
  // subtask, the employee list four days late (Kari Nordmann on the customer side), the milestone it blocks on
  // 16 October, the departments on 22 October, Magnus's training call on Thursday at 10:00
  const p1 = q(uid('project', 'p1'))
  const S = -6
  const item = (k, kind, n, g, start, due, extra = {}) => {
    const isDone = !!extra.done
    sql(`insert into app.project_items (id, project_id, kind, parent_id, group_id, name, owner_id, starts_on, due_on, done, done_at, done_by, ord, source, template_item_id, created_at, updated_at)
  values (${itemId('p1', k)}, ${p1}, ${q(kind)}, ${extra.parent ? itemId('p1', extra.parent) : 'null'}, ${groupId('p1', g)}, ${q(n)}, ${extra.owner ? staff(extra.owner) : 'null'},
  ${start === null ? 'null' : day(start)}, ${day(due)}, ${isDone}, ${isDone ? `(${day(due)})::timestamptz + interval '15 hours'` : 'null'}, ${isDone ? staff('emma') : 'null'}, ${extra.ord},
  ${q(extra.parent ? 'ui' : 'template')}, ${extra.parent ? 'null' : q(uid('project-template-item', `onboarding/${k}`))}, ${at(-S)}, ${at(-S)});`)
  }
  item('kickoff', 'task', 'Kickoff meeting', 'Kickoff', S, S + 1, { done: true, owner: 'emma', ord: 10 })
  item('agree', 'task', 'Agree survey dates', 'Kickoff', null, S + 1, { done: true, owner: 'emma', parent: 'kickoff', ord: 15 })
  item('upload', 'task', 'Upload employee list', 'Kickoff', S + 1, -4, { ord: 20 })
  item('ready', 'milestone', 'Employee list ready', 'Kickoff', null, 10, { ord: 30 })
  item('configure', 'task', 'Configure departments', 'Setup', 11, 16, { owner: 'emma', ord: 40 })
  item('invite', 'task', 'Invite HR and leaders', 'Setup', S + 20, S + 27, { ord: 50 })
  item('schedule', 'task', 'Schedule baseline', 'First survey', S + 30, S + 35, { ord: 70 })
  item('sent', 'milestone', 'Baseline sent', 'First survey', null, S + 37, { ord: 80 })
  item('review', 'task', 'Result review with HR', 'First survey', S + 52, S + 59, { ord: 90 })
  item('handover', 'milestone', 'Handover to CSM', 'Handover', null, S + 72, { ord: 100 })
  const kari = D.people.find((p) => p.name === 'Kari Nordmann')
  if (kari) sql(`insert into app.project_item_assignees (item_id, person_id) values (${itemId('p1', 'upload')}, ${q(uid('person', kari.id))});`)
  for (const [a, b] of [...PLAN_DEPS]) sql(`insert into app.project_item_dependencies (predecessor_id, successor_id, created_by, created_at) values (${itemId('p1', a)}, ${itemId('p1', b)}, ${staff('emma')}, ${at(-S)});`)
  // the training call is a real activity in Magnus's calendar, on the project's deal, next Thursday at 10:00
  const act = q(uid('activity', 'project-p1-training'))
  sql(`insert into app.activities (id, type_id, subject, starts_at, duration_min, owner_id, visibility, project_id, deal_id, organization_id, person_id, created_by, updated_by, created_at, updated_at)
  values (${act}, (select id from app.activity_types where key = 'call'), 'Training call with shift leads',
  (((now() at time zone 'Europe/Oslo')::date + ((11 - extract(isodow from now() at time zone 'Europe/Oslo')::int) % 7)) + time '10:00') at time zone 'Europe/Oslo',
  60, ${staff('magnus')}, 'group', ${p1}, ${q(uid('deal', 'd101'))}, ${q(uid('org', 'o1'))}, ${kari ? q(uid('person', kari.id)) : 'null'}, ${staff('emma')}, ${staff('emma')}, ${at(4)}, ${at(4)});`)
  sql(`insert into app.project_items (id, project_id, kind, group_id, activity_id, ord, source, created_at, updated_at) values (${itemId('p1', 'training')}, ${p1}, 'activity', ${groupId('p1', 'Setup')}, ${act}, 60, 'ui', ${at(4)}, ${at(4)});`)

  // sharing (the design's «Shared with Delivery team · Emma Lie, Magnus Berg»): the owner's group and two followers
  for (const f of ['emma', 'magnus']) sql(`insert into app.followers (entity, record_id, staff_id, created_at) values ('project', ${p1}, ${staff(f)}, ${at(5)});`)
  // «Notes, mentions and emails»: Emma's note with its mention, and Kari's thread about Skiftly linked to the project
  sql(`insert into app.notes (id, entity, record_id, body, mentions, author_id, created_at, updated_at) values (${q(uid('note', 'project-p1-training'))}, 'project', ${p1},
  '@Magnus kan du ta opplæringen av skiftlederne torsdag?', array[${staff('magnus')}]::uuid[], ${staff('emma')}, ${at(4)}, ${at(4)});`)
  sql(`insert into app.email_links (thread_id, entity, record_id, linked_by, staff_id) select t.id, 'project', ${p1}, 'manual', ${staff('emma')}
  from app.email_threads t where t.subject = 'Re: Forslag — Skiftly for lageret';`)
}
