// Phase 7 · Meetings (Meetings.dc.html): the design's four meetings in the workspace's three groups, with their
// attendees, a pre-call brief each, and the finished discovery call with its transcript, recap and CRM update
// suggestions. Called from generate.mjs after the nightly jobs, because a brief reads scores and health.
//
// Nothing is connected (no calendar adapter, meeting bot, transcription, AI or email provider), so no row may claim a
// provider did something. Where the design's literals cannot be backed they are left out and logged in
// docs/crm-enrichment/deviations/meetings.md (V-MEETINGS-*):
// - the meetings stand for what a calendar scan would have made (source «calendar», an external event id); none has
//   the notetaker, because capture «bot» is chosen only while the bot provider is connected (V-P7M-28). So there is no
//   «Bot joins», no «Notice due» and no recording notice sent: every meeting is «not required» and no bot is planned;
// - no video links: a join link is the calendar's, and none was synced (precedent V-ACTIVITIES-21);
// - the discovery call was not recorded by the desktop app (not available, D-38): its transcript is an upload, parsed
//   (the file is deleted after parsing), with the raw speaker labels of the file; «Tor» is mapped to the owner, the
//   guest's label is left for the owner to map;
// - its recap and suggestions are the design's fixture with no AI call in the log (none could have been made); the
//   suggestions pass the worker's register checks (worker_recap_ready) with the current values taken from the records
//   now. «Lead · Expected close» is left out: leads have no such column (V-P7M-16);
// - people the design names who are not in its data (Mona Hansen, Petter Aas, Ole Hansen, Marte Larsen, Silje Olsen)
//   are attendees unknown to the CRM; the discovery call's guest is Camilla Hansen of Kystlinje Transport AS (the
//   design's «Lars Olsen» belongs to Sandvik Elektro in its data); Bergheim's «4 others» are not invented;
// - «Demo: Avvikspunkt» has no recap (none could be made) and no link: «Solstrand Helse — HR suite» is not a deal in
//   the design's data and no guest is known to the CRM, so it carries the «Not linked» flag. Ola (read-only) is
//   invited, so the read-only view has a meeting to show.
//
// Every row passes the schema's checks and guards: check them with triggers on in a rolled-back session.

export function seedMeetings({ sql, q, uid, D }) {
  const staff = (id) => q(uid('staff', id))
  const tor = staff('tor')
  const email = (id) => D.staffById[id].email
  // the design's dates are relative to its today (Monday 5 October 2026), in Oslo time
  const oslo = (days, hm) => `((((now() at time zone 'Europe/Oslo')::date + ${days}) + time '${hm}') at time zone 'Europe/Oslo')`
  const ago = (days) => `(now() - interval '${days} days')`
  const person = (name) => {
    const p = D.people.find((x) => x.name === name)
    return p ? { id: q(uid('person', p.id)), email: p.email, org: q(uid('org', p.org)) } : null
  }
  const kari = person('Kari Nordmann')
  const maria = person('Maria Karlsen')
  const camilla = person('Camilla Hansen')
  const mid = (k) => q(uid('meeting', k))
  // «Today 09:00»: in the past whenever the database is built (yesterday's 09:00 before nine), so the call sits under review
  const today9 = `(case when ${oslo(0, '09:00')} < now() then ${oslo(0, '09:00')} else ${oslo(-1, '09:00')} end)`

  const meetings = [
    // key, title, starts, minutes, conference, capture, links {deal, lead, person, org}, created days ago
    ['m1', 'Skiftly walkthrough with shift leads', oslo(3, '10:00'), 60, 'meet', 'none', { deal: q(uid('deal', 'd101')), person: kari?.id, org: q(uid('org', 'o1')) }, 6],
    ['m2', 'Group agreement — steering group', oslo(4, '13:30'), 60, 'teams', 'none', { person: maria?.id, org: q(uid('org', 'o3')) }, 9],
    ['m3', 'Discovery call', today9, 30, 'phone', 'upload', { lead: q(uid('lead', 'L-501')), person: camilla?.id, org: q(uid('org', 'o17')) }, 4],
    ['m4', 'Demo: Avvikspunkt', oslo(-3, '10:00'), 45, 'zoom', 'none', {}, 12],
  ]
  for (const [k, title, starts, min, conf, capture, l, created] of meetings) {
    sql(`insert into app.meetings (id, title, starts_at, ends_at, source, calendar_staff_id, external_event_id, conference, capture, bot_state, notice_state,
  deal_id, lead_id, person_id, organization_id, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${mid(k)}, ${q(title)}, ${starts}, ${starts} + interval '${min} minutes', 'calendar', ${tor}, ${q('seed-' + k)}, ${q(conf)}, ${q(capture)}, 'none', 'not_required',
  ${l.deal ?? 'null'}, ${l.lead ?? 'null'}, ${l.person ?? 'null'}, ${l.org ?? 'null'}, ${tor}, 'owner', ${tor}, ${tor}, ${ago(created)}, ${ago(Math.min(created, 1))});`)
  }

  // attendees as the calendar lists them: the owner, colleagues, guests (matched to people by address)
  const att = (k, addr, name, { personId = null, staffId = null, response = 'accepted' } = {}) =>
    sql(`insert into app.meeting_attendees (meeting_id, email, name, person_id, staff_id, external, response) values (${mid(k)}, ${q(addr.toLowerCase())}, ${q(name)},
  ${personId ?? 'null'}, ${staffId ?? 'null'}, ${staffId ? 'false' : 'true'}, ${q(response)});`)
  for (const k of ['m1', 'm2', 'm3', 'm4']) att(k, email('tor'), D.staffById.tor.name, { staffId: tor })
  if (kari) att('m1', kari.email, 'Kari Nordmann', { personId: kari.id })
  att('m1', 'mona.hansen@lumio.no', 'Mona Hansen')
  att('m1', 'petter.aas@lumio.no', 'Petter Aas', { response: 'needs_action' })
  att('m2', 'ole.hansen@bergheimbygg.no', 'Ole Hansen')
  if (maria) att('m2', maria.email, 'Maria Karlsen', { personId: maria.id, response: 'tentative' })
  if (camilla) att('m3', camilla.email, 'Camilla Hansen', { personId: camilla.id })
  att('m4', 'marte.larsen@solstrandhelse.no', 'Marte Larsen')
  att('m4', 'silje.olsen@solstrandhelse.no', 'Silje Olsen')
  att('m4', email('ola'), D.staffById.ola.name, { staffId: staff('ola') })

  // ---- the discovery call: an uploaded transcript (parsed, the file gone), its speakers, the recap, the suggestions
  const tr = q(uid('meeting-transcript', 'm3'))
  const up = q(uid('meeting-upload', 'm3'))
  const lines = [
    [12000, 'Tor', 'Takk for at dere tok dere tid. Skal vi starte med hvordan bytter fungerer i dag?'],
    [31000, 'Camilla', 'I dag går alt på telefon og en delt Excel. Vi er 220 sjåfører fordelt på tre depoter.'],
    [125000, 'Tor', 'Da passer Skiftly per depot. Hva skjer når noen blir syke på natta?'],
    [160000, 'Camilla', 'Vaktsjefen ringer rundt. Vi vil gjerne ha det på plass før jul — budsjettet er godkjent for fire hundre tusen.'],
    [318000, 'Camilla', 'HR-sjefen vår, Nora Berg, må være med på neste møte.'],
    [422000, 'Tor', 'Jeg sender et forslag innen fredag, og vi booker en demo med Nora.'],
  ]
  const readyAt = `(${today9} + interval '50 minutes')`
  sql(`insert into app.meeting_transcripts (id, meeting_id, source, language, duration_s, speaker_count, state, file_name, uploaded_by, created_at, ready_at)
  values (${tr}, ${mid('m3')}, 'upload', 'nb-NO', ${lines.at(-1)[0] / 1000}, 2, 'ready', 'Discovery call — Kystlinje.vtt', ${tor}, ${readyAt} - interval '1 minute', ${readyAt});`)
  sql(`insert into app.meeting_uploads (id, meeting_id, transcript_id, storage_path, filename, mime, size_bytes, state, uploaded_by, created_at, parsed_at)
  values (${up}, ${mid('m3')}, ${tr}, 'upload/' || ${mid('m3')} || '/' || ${up} || '.vtt', 'Discovery call — Kystlinje.vtt', 'text/vtt', 2318, 'parsed', ${tor}, ${readyAt} - interval '1 minute', ${readyAt});`)
  for (const [i, [ms, who, text]] of lines.entries()) {
    sql(`insert into app.transcript_segments (transcript_id, seq, start_ms, speaker_label, text) values (${tr}, ${i + 1}, ${ms}, ${q(who)}, ${q(text)});`)
  }
  sql(`insert into app.transcript_speakers (transcript_id, label, staff_id, email) values (${tr}, 'Tor', ${tor}, ${q(email('tor'))});`)
  sql(`insert into app.transcript_speakers (transcript_id, label) values (${tr}, 'Camilla');`)
  const items = (xs) => q(JSON.stringify(xs.map(([text, seq]) => ({ text, seq }))))
  sql(`insert into app.meeting_recaps (transcript_id, meeting_id, state, takeaways, next_steps, requested_at, generated_at)
  values (${tr}, ${mid('m3')}, 'ready', ${items([['220 drivers across three depots; swaps run on phone and a shared spreadsheet', 2],
    ['Budget approved — about 400 000 kr; wants go-live before Christmas', 4], ['HR lead Nora Berg must join the next meeting', 5]])}::jsonb,
  ${items([['Send proposal by Friday', 6], ['Book demo with Nora Berg', 6], ['Convert lead to deal in New business · Discovery call', null]])}::jsonb, ${readyAt}, ${readyAt} + interval '1 minute');`)

  // suggestions: targets linked to the meeting, writable fields, values of the right type; the current value and the
  // version are the record's own when the seed runs (as worker_recap_ready snapshots them)
  const lead = q(uid('lead', 'L-501'))
  const kyst = q(uid('org', 'o17'))
  const cur = (tbl, id, field) => `(select to_jsonb(t) -> ${q(field)} from app.${tbl} t where t.id = ${id})`
  const ver = (tbl, id) => `(select t.version from app.${tbl} t where t.id = ${id})`
  const sugg = [
    ['lead', lead, 'leads', 'value', '400000', [4]],
    ['lead', lead, 'leads', 'labels', JSON.stringify([uid('label-lead', 'Hot'), uid('label-lead', 'Multi-product')]), [2]],
    ...(camilla ? [['person', camilla.id, 'people', 'title', JSON.stringify('Driftssjef'), [2]]] : []),
    ['organization', kyst, 'organizations', 'employees', '220', [2]],
  ]
  for (const [i, [entity, id, tbl, field, value, ev]] of sugg.entries()) {
    sql(`insert into app.meeting_suggestions (id, meeting_id, transcript_id, ord, target_entity, target_id, field, current_value, base_version, proposed_value, evidence, created_at)
  values (${q(uid('meeting-suggestion', `m3/${field}`))}, ${mid('m3')}, ${tr}, ${i + 1}, ${q(entity)}, ${id}, ${q(field)}, ${cur(tbl, id, field)}, ${ver(tbl, id)}, ${q(value)}::jsonb,
  array[${ev.join(', ')}]::int[], ${readyAt} + interval '1 minute');`)
  }
  sql(`insert into app.meeting_suggestions (id, meeting_id, transcript_id, ord, target_entity, target_id, field, proposed_value, evidence, created_at)
  values (${q(uid('meeting-suggestion', 'm3/new'))}, ${mid('m3')}, ${tr}, ${sugg.length + 1}, 'person', null, '*new',
  jsonb_build_object('name', 'Nora Berg', 'title', 'HR-leder', 'organization_id', ${kyst}), array[5]::int[], ${readyAt} + interval '1 minute');`)

  // ---- the pre-call briefs, computed from the records as the brief job does (facts first; the quotes say «not connected»)
  for (const k of ['m1', 'm2', 'm3', 'm4']) sql(`select app.mtg_brief_build(${mid(k)});`)
}
