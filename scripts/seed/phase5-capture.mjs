// Lead capture fixtures (Phase 5): the design's web forms and chat playbooks (Marketing.dc.html, F and playbooks)
// as configuration, called from generate.mjs. No submissions, conversations, reveals or visits are seeded: those
// figures in the design are invented, and the real ones arrive through the public host (D-28) and the providers.
// Never an employee-list form (spec Q8, D-34): «Send oss ansattlisten» is left out. No copy claims k = 5 (Q18).
//
// The rows are written as form_check / playbook_publish would write them (the seed runs with triggers off).
export function seedCapture({ sql, q, uid }) {
  const owner = uid('staff', 'jonas') // Marketing runs forms and chat (spec §6)
  const json = (v) => `${q(JSON.stringify(v))}::jsonb`
  const hidden = ['utm', 'referrer_host', 'landing_path']

  // ---- web forms: «Kontakt oss» and «Webinar-påmelding» are published and active; the gated download stays a
  // draft because no file has been uploaded for it (a gated download cannot be published without one)
  const forms = [
    {
      key: 'kontakt', name: 'Kontakt oss', kind: 'contact', active: true,
      intro: { title: 'Snakk med oss om arbeidsmiljøet', body: 'Vi svarer innen én arbeidsdag.' },
      fields: [
        { key: 'name', kind: 'short_text', label: 'Navn', map: 'person.name', required: true, placeholder: 'Kari Nordmann' },
        { key: 'email', kind: 'email', label: 'E-post', map: 'person.email', required: true, placeholder: 'kari@firma.no' },
        { key: 'phone', kind: 'phone', label: 'Telefon', map: 'person.phone', required: false, placeholder: '+47' },
        { key: 'org_number', kind: 'short_text', label: 'Organisasjonsnummer', map: 'organization.org_number', required: true, placeholder: '923 456 789' },
        // the design's «(custom)» field: no custom field exists, so the value is kept with the lead's form data
        { key: 'employees', kind: 'short_text', label: 'Antall ansatte', required: false, placeholder: 'f.eks. 48' },
        { key: 'consent', kind: 'marketing_status', required: false },
      ],
      after: { creates: 'lead', ticket: true, sequence_id: uid('workflow', 'trial_nurture'), thank_you: 'Takk! Vi svarer innen én arbeidsdag.' },
    },
    {
      key: 'lovkrav', name: 'Last ned: Lovkrav-sjekkliste', kind: 'gated_download', active: false,
      intro: { title: 'Last ned: Lovkrav-sjekkliste', body: '' },
      fields: [
        { key: 'name', kind: 'short_text', label: 'Navn', map: 'person.name', required: true },
        { key: 'email', kind: 'email', label: 'E-post', map: 'person.email', required: true },
        { key: 'company', kind: 'short_text', label: 'Bedrift', map: 'organization.name', required: false },
        { key: 'consent', kind: 'marketing_status', required: false },
      ],
      after: { creates: 'lead', ticket: false },
    },
    {
      key: 'webinar', name: 'Webinar-påmelding', kind: 'registration', active: true,
      intro: { title: 'Webinar-påmelding', body: '' },
      fields: [
        { key: 'name', kind: 'short_text', label: 'Navn', map: 'person.name', required: true },
        { key: 'email', kind: 'email', label: 'E-post', map: 'person.email', required: true },
        { key: 'company', kind: 'short_text', label: 'Bedrift', map: 'organization.name', required: false },
        { key: 'consent', kind: 'marketing_status', required: false },
      ],
      after: { creates: 'lead', ticket: false },
    },
  ]
  for (const [i, f] of forms.entries()) {
    const id = uid('form', f.key)
    const def = { intro: f.intro, fields: f.fields, hidden, consent: { text_key: 'newsletter' }, after_submit: f.after }
    sql(`insert into app.forms (id, public_id, name, kind, language, status, draft, current_version, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${q(id)}, ${q(uid('form-public', f.key).replace(/-/g, ''))}, ${q(f.name)}, ${q(f.kind)}, 'nb', ${q(f.active ? 'active' : 'inactive')}, ${json(def)}, ${f.active ? 1 : 0},
  ${q(owner)}, 'all', ${q(owner)}, ${q(owner)}, now() - interval '${40 - i} days', now() - interval '${10 + i} days');`)
    if (f.active) {
      sql(`insert into app.form_versions (form_id, version, definition, published_by, published_at) values (${q(id)}, 1, ${json(def)}, ${q(owner)}, now() - interval '${10 + i} days');`)
    }
  }

  // ---- chat playbooks (LGN-01): three live, «Flere leads fra artikler» a draft
  const theme = { palette: 'cream', button: 'saffron' }
  const profile = { name: 'Orgpuls', avatar: 'face', language: 'nb' }
  const askName = { key: 'name', kind: 'question', text: 'Hei! Hva heter du?', map: 'person.name' }
  const askEmail = { key: 'email', kind: 'question', text: 'Hvilken e-postadresse kan vi nå deg på?', map: 'person.email' }
  const playbooks = [
    { key: 'pris', name: 'Pris-siden: kvalifiser og rut', template: 'qualify_route', pages: ['/pris'], live: true,
      steps: [{ key: 'employees', kind: 'question', text: 'Hei! Hvor mange ansatte er dere?' },
              { key: 'handoff', kind: 'handoff', text: 'Takk! Vil du snakke med en av oss nå?' }] },
    { key: 'demo', name: 'Book en demo', template: 'meetings', pages: ['/plattform'], live: true,
      steps: [askName, askEmail, { key: 'thanks', kind: 'message', text: 'Takk! Vi tar kontakt for å finne et tidspunkt.' }] },
    { key: 'artikler', name: 'Flere leads fra artikler', template: 'leads', pages: ['/artikler/*'], live: false,
      steps: [askName, askEmail, { key: 'thanks', kind: 'message', text: 'Takk! Vi tar kontakt.' }] },
    // «Chat live · business hours»: weekdays 08–16 (0036)
    { key: 'snakk', name: 'Snakk med oss', template: 'live_chat', pages: [], live: true, steps: [],
      hours: Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri'].map((d) => [d, ['08:00', '16:00']])) },
  ]
  for (const [i, p] of playbooks.entries()) {
    const id = uid('playbook', p.key)
    sql(`insert into app.chat_playbooks (id, name, template, state, pages, theme, profile, steps, hours, creates, current_version, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  values (${q(id)}, ${q(p.name)}, ${q(p.template)}, ${q(p.live ? 'live' : 'draft')}, array[${p.pages.map(q).join(', ')}]::text[], ${json(theme)}, ${json(profile)}, ${json(p.steps)}, ${p.hours ? json(p.hours) : 'null'}, 'lead',
  ${p.live ? 1 : 0}, ${q(owner)}, 'all', ${q(owner)}, ${q(owner)}, now() - interval '${30 - i} days', now() - interval '${8 + i} days');`)
    if (p.live) {
      const def = { template: p.template, steps: p.steps, creates: 'lead', pipeline_id: null, stage_id: null, booking_link_id: null, queue_wait_seconds: 60,
        offline_message: null, theme, profile, pages: p.pages, site_ids: [] }
      sql(`insert into app.chat_playbook_versions (playbook_id, version, definition, published_by, published_at) values (${q(id)}, 1, ${json(def)}, ${q(owner)}, now() - interval '${8 + i} days');`)
    }
  }
  // the design's embed is on orgpuls.com: chat is switched on for that site
  sql(`update app.web_sites set chat_enabled = true where key = 'orgpuls-com';`)
}
