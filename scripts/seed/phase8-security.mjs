// Phase 8 · Security (Security.dc.html): the design's sign-ins, live sessions, security events and incidents, as the
// running system would have recorded them. Called from generate.mjs. The migration (0043) already seeds the register,
// the platform facts (eu-central-1, D-35), the sub-processors, the retention rules and the two SSO providers.
//
// Every row is a seed fixture for the local scenario (D-02) and nothing else. They are written the way 0043 writes them:
// - IPs are sealed with app.ip_seal (pgp_sym_encrypt under the Vault key security_ip_key, created on first use); no IP
//   is stored in clear. A device is the SHA-256 of a device cookie; an address is app.email_hash. Device labels are what
//   app.device_label makes of a user agent («Edge on Windows»), not the design's «Windows 11 · Edge 128»;
// - times are relative to the build (the design's today is Monday 5 October 2026, about 09:44), so the sessions are live
//   right after a reset and go idle 30 minutes later, as session_idle (on_30) says. Nothing keeps them alive;
// - a person's first device and city are not «new» (V-P8S-09): each staff member with a sign-in has older devices and
//   places in staff_devices / staff_locations, which outlive the 60-day log;
// - alert states follow the register defaults (D-29): new devices and admin logins are off, so those events say «none»;
//   failed logins, password resets and large exports are immediate and were delivered in the app to the recipients
//   (security_recipients()), with the email delivery recorded as not_connected (no email provider).
// Left out (docs/crm-enrichment/deviations/security.md): «SSO · Entra ID» and «SSO + Face ID» methods (D-11, D-31: every
// sign-in is password + TOTP); «Blocked — IP rule» for Riga (no IP rule exists and the allowlist is off, D-29: it is a
// failed password); «Account locked 15 min» (no lockout, Q7); «Emma Lie invited Petter Aas» (Petter Aas is not staff);
// Ola «not enrolled» (Ola signs in for the read-only screenshots, so his factor stays); backups and the restore test
// (nothing recorded them); the audit rows of the design's audit log (the audit is what really happened).
//
// Every row passes the schema's checks and guards: check them with triggers on in a rolled-back session.

export function seedSecurity({ sql, q, uid }) {
  const staff = (id) => q(uid('staff', id))
  const email = (id) => q(`${id}@orgpuls.no`)
  const mins = (m) => `(now() - interval '${m} minutes')`
  // a time of day N days ago, Oslo time
  const oslo = (days, hm) => `((((now() at time zone 'Europe/Oslo')::date - ${days}) + time '${hm}') at time zone 'Europe/Oslo')`
  const dev = (key) => `extensions.digest('device:seed-${key}', 'sha256')`
  const ip = (addr) => `app.ip_seal(${q(addr)}::inet)`
  const sid = (key) => q(uid('session', key))

  // ---- devices and places known before the 60-day log (no IP is kept here)
  const devices = [
    ['tor', 'tor-mac', 'Chrome on macOS', 210], ['tor', 'tor-ipad', 'Safari on iPad', 200],
    ['magnus', 'magnus-win', 'Edge on Windows', 180],
    ['hanna', 'hanna-mac', 'Chrome on macOS', 120], ['hanna', 'hanna-iphone', 'Safari on iPhone', 100],
    ['ingrid', 'ingrid-iphone', 'Safari on iPhone', 160],
    ['jonas', 'jonas-win', 'Chrome on Windows', 150],
    ['ola', 'ola-win', 'Chrome on Windows', 90],
  ]
  for (const [s, key, label, days] of devices) {
    sql(`insert into app.staff_devices (staff_id, device_hash, label, first_seen_at, last_seen_at) values (${staff(s)}, ${dev(key)}, ${q(label)}, now() - interval '${days} days', now() - interval '3 days');`)
  }
  const places = [['tor', 'Oslo', 210], ['magnus', 'Oslo', 180], ['hanna', 'Oslo', 120], ['hanna', 'Bergen', 90], ['ingrid', 'Oslo', 160], ['jonas', 'Oslo', 150], ['ola', 'Oslo', 90]]
  for (const [s, city, days] of places) {
    sql(`insert into app.staff_locations (staff_id, country, city, first_seen_at) values (${staff(s)}, 'NO', ${q(city)}, now() - interval '${days} days');`)
  }

  // ---- sign-ins (login_log) and their sessions
  // key, staff, at, outcome, device key, label, city, country, ip, new device, new place, session end: null = live, else [at, reason, by]
  const signins = [
    ['tor-today', 'tor', mins(102), 'success', 'tor-mac', 'Chrome on macOS', 'Oslo', 'NO', '193.69.41.7', false, false, null],
    ['magnus-today', 'magnus', mins(109), 'success', 'magnus-win', 'Edge on Windows', 'Oslo', 'NO', '193.69.41.7', false, false, null],
    ['hanna-today', 'hanna', mins(23), 'success', 'hanna-win', 'Edge on Windows', 'Bergen', 'NO', '84.208.12.40', true, false, null],
    ['ingrid-today', 'ingrid', mins(64), 'success', 'ingrid-iphone', 'Safari on iPhone', 'Oslo', 'NO', '77.16.45.130', false, false, null],
    ['jonas-today', 'jonas', mins(39), 'success', 'jonas-mac', 'Safari on macOS', 'Stockholm', 'SE', '81.170.128.15', true, true, null],
    ['hanna-yesterday', 'hanna', oslo(1, '16:02'), 'success', 'hanna-mac', 'Chrome on macOS', 'Oslo', 'NO', '193.69.41.7', false, false, [oslo(1, '17:30'), 'signed_out', null]],
    ['hanna-2oct', 'hanna', oslo(3, '08:11'), 'success', 'hanna-iphone', 'Safari on iPhone', 'Oslo', 'NO', '46.9.101.220', false, false, [oslo(3, '08:49'), 'idle_timeout', null]],
    ['jonas-1oct', 'jonas', oslo(4, '08:20'), 'success', 'jonas-win', 'Chrome on Windows', 'Oslo', 'NO', '193.69.41.7', false, false, [oslo(4, '16:45'), 'signed_out', null]],
    ['hanna-30sep', 'hanna', oslo(5, '07:58'), 'success', 'hanna-mac', 'Chrome on macOS', 'Oslo', 'NO', '193.69.41.7', false, false, [oslo(5, '16:10'), 'signed_out', null]],
    ['tor-ipad', 'tor', oslo(6, '07:31'), 'success', 'tor-ipad', 'Safari on iPad', 'Oslo', 'NO', '46.9.101.88', false, false, [oslo(6, '07:52'), 'forced', 'tor']],
    ['hanna-riga', 'hanna', oslo(14, '22:40'), 'failed_password', null, 'Firefox', 'Riga', 'LV', '185.12.4.77', false, false, null],
    ...['07:12', '07:13', '07:13', '07:14'].map((hm, i) => [`ola-failed-${i}`, 'ola', oslo(3, hm), 'failed_password', 'ola-win', 'Chrome on Windows', 'Oslo', 'NO', '193.69.41.7', false, false, null]),
  ]
  for (const [key, s, at, outcome, dkey, label, city, country, addr, newDev, newLoc, end] of signins) {
    const ok = outcome === 'success'
    sql(`insert into app.login_log (at, staff_id, email_sha256, session_id, outcome, method, ip_sealed, device_label, device_hash, city, country, new_device, new_location)
  values (${at}, ${staff(s)}, app.email_hash(${email(s)}), ${ok ? sid(key) : 'null'}, ${q(outcome)}, ${ok ? "'password_totp'" : 'null'}, ${ip(addr)}, ${q(label)}, ${dkey ? dev(dkey) : 'null'}, ${q(city)}, ${q(country)}, ${newDev}, ${newLoc});`)
    if (!ok) continue
    const [endAt, reason, by] = end ?? [null, null, null]
    const seen = end ? endAt : mins(key.startsWith('hanna') ? 1 : 4)
    sql(`insert into app.staff_sessions (session_id, staff_id, created_at, last_seen_at, ip_sealed, last_ip_sealed, device_label, device_hash, city, country, method, ended_at, end_reason, ended_by)
  values (${sid(key)}, ${staff(s)}, ${at}, ${reason === 'idle_timeout' ? `${endAt} - interval '30 minutes'` : seen}, ${ip(addr)}, ${ip(addr)}, ${q(label)}, ${dev(dkey)}, ${q(city)}, ${q(country)}, 'password_totp',
  ${endAt ?? 'null'}, ${reason ? q(reason) : 'null'}, ${by ? staff(by) : 'null'});`)
  }
  // the two new devices of the week and Jonas' first sign-in from Stockholm
  sql(`insert into app.staff_devices (staff_id, device_hash, label, first_seen_at, last_seen_at) values (${staff('hanna')}, ${dev('hanna-win')}, 'Edge on Windows', ${mins(23)}, ${mins(1)}), (${staff('jonas')}, ${dev('jonas-mac')}, 'Safari on macOS', ${mins(39)}, ${mins(4)});`)
  sql(`insert into app.staff_locations (staff_id, country, city, first_seen_at) values (${staff('jonas')}, 'SE', 'Stockholm', ${mins(39)});`)
  // Sara's completed password change after her reset request (dates only, Q4)
  sql(`insert into app.password_changes (staff_id, changed_at) values (${staff('sara')}, ${oslo(5, '10:12')});`)

  // ---- security events (ids and counts only) and, for those alerted at once, their deliveries
  const incident2 = q(uid('incident', 'webhook-exposed'))
  // key, kind, severity, subject, actor, at, detail, alert state
  const events = [
    ['ev-hanna-device', 'new_device', 'low', 'hanna', null, mins(23), { device: 'Edge on Windows', city: 'Bergen', country: 'NO' }, 'none'],
    ['ev-jonas-device', 'new_device', 'low', 'jonas', null, mins(39), { device: 'Safari on macOS', city: 'Stockholm', country: 'SE' }, 'none'],
    ['ev-jonas-place', 'new_location', 'low', 'jonas', null, mins(39), { city: 'Stockholm', country: 'SE' }, 'none'],
    ['ev-jonas-export', 'large_export', 'low', null, 'jonas', oslo(1, '14:30'), { rows: 4120, entity: 'person', threshold: 1000 }, 'sent'],
    ['ev-ola-failed', 'failed_logins', 'high', 'ola', null, oslo(3, '07:13'), { count: 3 }, 'sent'],
    ['ev-sara-reset', 'password_reset', 'low', 'sara', null, oslo(5, '10:05'), {}, 'sent'],
    ['ev-tor-ipad', 'session_revoked', 'info', 'tor', 'tor', oslo(6, '07:52'), { count: 1 }, 'none'],
  ]
  for (const [, kind, sev, subject, actor, at, detail, state] of events) {
    sql(`insert into app.security_events (at, kind, severity, subject_staff_id, actor_id, detail, alert_state) values (${at}, ${q(kind)}, ${q(sev)}, ${subject ? staff(subject) : 'null'}, ${actor ? staff(actor) : 'null'}, ${q(JSON.stringify(detail))}::jsonb, ${q(state)});`)
    if (state !== 'sent') continue
    const ev = `(select id from app.security_events where kind = ${q(kind)} and at = ${at} order by id desc limit 1)`
    sql(`insert into app.security_alert_deliveries (event_id, channel, recipient_id, sent_at, status) select ${ev}, 'in_app', r, ${at} + interval '1 minute', 'sent' from app.security_recipients() r;`)
    sql(`insert into app.security_alert_deliveries (event_id, channel, recipient_id, sent_at, status) select ${ev}, 'email', r, null, 'not_connected' from app.security_recipients() r;`)
  }

  // ---- the incident register (the 72-hour clock runs from detection)
  sql(`insert into app.security_incidents (id, title, summary, detected_at, logged_at, logged_by, personal_data, state, closed_at) values
  (${q(uid('incident', 'misdirected-invoice'))}, 'Misdirected invoice email', 'One invoice PDF sent to an old billing contact at Kvamme Regnskap AS. Contained name and org.nr only.',
   ${oslo(23, '09:40')}, ${oslo(23, '09:52')}, ${staff('tor')}, true, 'assessed_not_notifiable', ${oslo(22, '11:05')}),
  (${incident2}, 'Webhook endpoint exposed', 'A test webhook pointed at a private address — blocked by the outbound filter, no data left.',
   now() - interval '27 hours', now() - interval '26 hours 40 minutes', ${staff('tor')}, false, 'investigating', null);`)
  sql(`insert into app.security_events (at, kind, severity, subject_staff_id, actor_id, detail, alert_state) values (now() - interval '26 hours 40 minutes', 'incident_logged', 'high', null, ${staff('tor')}, jsonb_build_object('incident', ${incident2}), 'none');`)

  // ---- recovery codes: generated by eight of the nine (not Ola); random, so nobody knows them — hashes only
  for (const s of ['tor', 'ingrid', 'eirik', 'magnus', 'hanna', 'sara', 'jonas', 'emma']) {
    sql(`insert into app.recovery_codes (staff_id, hash, created_at) select ${staff(s)}, extensions.digest(extensions.gen_random_bytes(16), 'sha256'), now() - interval '40 days' from generate_series(1, 10);`)
  }

  // ---- the audit rows the actions above would have written (names, ids and counts; never an IP or an address)
  const audit = [
    [oslo(6, '07:52'), 'tor', 'session.revoked', 'staff', uid('staff', 'tor'), { session: uid('session', 'tor-ipad') }],
    [oslo(23, '09:52'), 'tor', 'incident.saved', 'security_incident', uid('incident', 'misdirected-invoice'), { created: true, state: 'investigating', personal_data: true, fields: ['detected_at', 'personal_data', 'summary', 'title'] }],
    [oslo(22, '11:05'), 'tor', 'incident.saved', 'security_incident', uid('incident', 'misdirected-invoice'), { created: false, state: 'assessed_not_notifiable', personal_data: true, fields: ['state'] }],
    ['now() - interval \'26 hours 40 minutes\'', 'tor', 'incident.saved', 'security_incident', uid('incident', 'webhook-exposed'), { created: true, state: 'investigating', personal_data: false, fields: ['detected_at', 'summary', 'title'] }],
  ]
  for (const [at, s, action, type, id, detail] of audit) {
    sql(`insert into app.audit (at, actor, ok, action, target_type, target_id, staff_id, detail, source, principal_kind, principal_id)
  values (${at}, ${email(s)}, true, ${q(action)}, ${q(type)}, ${q(id)}, ${staff(s)}, ${q(JSON.stringify(detail))}::jsonb, 'web', 'staff', ${staff(s)});`)
  }
}
