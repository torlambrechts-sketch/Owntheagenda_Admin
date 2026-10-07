// Phase 8 · Mobile (Mobile.dc.html): the design's fixtures for the phone previews of the signed-in staff member (Tor).
// Called from generate.mjs at the end, after the nightly jobs.
//
// Nothing is connected (no push provider, no geocoder, no transcription, no AI, no storage signer), so no row may
// claim a provider did something. What the design draws and this module leaves out is logged in
// docs/crm-enrichment/deviations/mobile.md (V-MOBILE-*):
// - Focus «Today»: the call with Kari Nordmann at 10:00 on «Lumio AS — Expansion to Skiftly» and the site visit to
//   Bergheim Bygg AS at 13:30 (activity type «visit», 0044), both Tor's, today in Oslo time. The call has an in-app
//   reminder 15 minutes before; the reminder job (app.dispatch_reminders) makes the design's «Call Kari Nordmann in
//   15 minutes» notification itself when the time comes, so no reminder notification is written here;
// - the mention «@Tor partner discount here?» is Ingrid's note on the Lumio deal with Tor mentioned, and the
//   notification note_save writes for it (key «mention», the deal's route);
// - places (record_geo): the design's organisations have a city and no street address, and the geocoder is not
//   connected, so each gets a hand-set place (source «manual») at the centre of its own city. Distances are therefore
//   city-level; organisations in one city share a point. No staff member's or device's position is stored;
// - not seeded: push devices (a device registers itself in a browser with the provider's key), push deliveries,
//   sync receipts (they come from a device's outbox), captures and transcripts (no storage signer, no transcription),
//   the business card «Nora Berg» (a card becomes a contact only when someone reviews and saves it), the assignment
//   «Lead L-503 · Rule «Inbound — large orgs»» (the assignment rules are configuration with no runs) and the chat
//   request «Visitor on /pris» (no visitor has asked).
//
// Every row passes the schema's checks and guards: check them with triggers on in a rolled-back session.

// the centres of the design's cities (WGS 84), for the hand-set places
const CITY = {
  Oslo: [59.913900, 10.752200], Trondheim: [63.430500, 10.395100], Kristiansand: [58.146700, 7.995600], Fredrikstad: [59.218100, 10.929800],
  'Lillestrøm': [59.956000, 11.049000], Stavanger: [58.970000, 5.733100], Hamar: [60.794500, 11.068000], 'Tønsberg': [59.267500, 10.407600],
  'Bodø': [67.280400, 14.404900], 'Ålesund': [62.472200, 6.149500], 'Tromsø': [69.649200, 18.955300], Bergen: [60.391300, 5.322100], Drammen: [59.743900, 10.204500],
}

export function seedMobile({ sql, q, uid, D }) {
  const tor = q(uid('staff', 'tor'))
  const ingrid = D.staffById.ingrid
  // today at the design's hour, in Oslo time
  const today = (hm) => `((((now() at time zone 'Europe/Oslo')::date) + time '${hm}') at time zone 'Europe/Oslo')`
  const type = (k) => `(select id from app.activity_types where key = ${q(k)})`
  const kari = D.people.find((p) => p.name === 'Kari Nordmann')
  const bergheim = D.orgs.find((o) => o.name === 'Bergheim Bygg AS')
  const lumioDeal = D.deals.find((d) => d.id === 'd101')
  const call = q(uid('activity', 'mobile-call-kari'))

  sql(`insert into app.activities (id, type_id, subject, starts_at, duration_min, priority, done, deal_id, person_id, organization_id, owner_id, created_at, updated_at)
  values (${call}, ${type('call')}, 'Call Kari Nordmann', ${today('10:00')}, 15, 'high', false, ${q(uid('deal', lumioDeal.id))}, ${q(uid('person', kari.id))}, ${q(uid('org', kari.org))},
  ${tor}, now() - interval '2 days', now() - interval '2 days'),
  (${q(uid('activity', 'mobile-visit-bergheim'))}, ${type('visit')}, 'Site visit Bergheim Bygg', ${today('13:30')}, 60, 'medium', false, null, null, ${q(uid('org', bergheim.id))},
  ${tor}, now() - interval '3 days', now() - interval '3 days');`)
  sql(`insert into app.activity_reminders (activity_id, channel, offset_min) values (${call}, 'app', 15);`)

  // Ingrid's question on the Lumio deal, with Tor mentioned, and what note_save tells him
  const dealId = q(uid('deal', lumioDeal.id))
  const body = '@Tor partner discount here?'
  sql(`insert into app.notes (id, entity, record_id, body, pinned, mentions, author_id, created_at)
  values (${q(uid('note', 'mobile-mention'))}, 'deal', ${dealId}, ${q(body)}, false, array[${tor}]::uuid[], ${q(uid('staff', 'ingrid'))}, now() - interval '2 hours');`)
  sql(`insert into app.notifications (staff_id, kind, key, params, route, entity, record_id, created_at)
  values (${tor}, 'mention', 'mention', jsonb_build_object('actor', ${q(ingrid.name)}, 'record', ${q(lumioDeal.title)}, 'excerpt', ${q(body)}),
  ${q('/deals?deal=' + uid('deal', lumioDeal.id))}, 'deal', ${dealId}, now() - interval '2 hours');`)

  // hand-set places at each organisation's city centre (the geocoder is not connected)
  for (const o of D.orgs) {
    const c = CITY[o.city]
    if (!c) continue
    sql(`insert into app.record_geo (entity, record_id, field_key, lat, lng, source, geocoded_at) values ('organization', ${q(uid('org', o.id))}, 'address', ${c[0].toFixed(6)}, ${c[1].toFixed(6)}, 'manual', now() - interval '1 day');`)
  }
}
