// Phase 5 · Documents (Documents.dc.html): the design's document templates and documents on the seeded deals,
// called from generate.mjs. Every document is rendered by the database's own functions (app.doc_product_table,
// app.doc_render), as document_create renders it, so its body, missing values and totals are the real ones.
//
// What the design shows and the seed leaves out, because nothing could have produced it yet (D-41, never fabricate):
// no PDF exists (no PDF worker), so no document awaits a signature or is signed and no uploaded PDF is seeded; no
// drive is connected, so every document is stored on the platform; a view has no city and no «forwarded» guess.
// See docs/crm-enrichment/deviations/documents.md (V-DOCUMENTS-*). No template text makes a product claim (Q18).

/** Oslo wall-clock time `day` days from today (negative: in the past), as the generator writes activity times. */
const osloAt = (day, hour, min) =>
  `((date_trunc('day', now() at time zone 'Europe/Oslo') + interval '${day} days' + interval '${hour} hours' + interval '${min} minutes') at time zone 'Europe/Oslo')`

export function seedDocuments({ sql, q, uid, ago }) {
  const tor = q(uid('staff', 'tor'))

  // ---- templates (Documents.dc.html, TP). Platform templates are sanitised HTML with tokens; their placeholders
  // are the distinct tokens of the body, found by app.doc_tokens as doc_template_save finds them.
  const platform = [
    ['tilbud', 'Tilbud — standard', 'quotes', 'company', null, 14, 'T-', ['name', 'qty', 'price', 'discount', 'total'],
      '<h1>Tilbud til [organization.name]</h1><p>Til [person.name] · [organization.orgnr] · gyldig til [document.valid_until]</p><p>Gjelder: [deal.title]</p>[product.table]'],
    ['saas', 'Avtale — SaaS', 'contracts', 'company', null, null, null, null,
      '<h1>Avtale</h1><p>Mellom leverandøren og [organization.name], org.nr. [organization.orgnr].</p><p>Avtalen gjelder [deal.title], med en samlet verdi på [deal.value] eks. mva.</p><p>For kunden: [signer.1]</p>'],
    ['offentlig', 'Avtale — offentlig', 'contracts', 'team', 'Sales Norway', null, null, null,
      '<h1>Rammeavtale</h1><p>Oppdragsgiver: [organization.name]</p><p>Planlagt oppstart: [project.start]</p>'],
  ]
  for (const [key, name, category, share, team, validity, prefix, columns, body] of platform) {
    const id = q(uid('doc-template', key))
    const table = columns ? q(JSON.stringify({ columns })) + '::jsonb' : 'null'
    sql(`insert into app.document_templates (id, name, kind, category, share, team_id, language, source, body_html, product_table, validity_days, number_prefix,
  placeholders, owner_id, created_by, updated_by, created_at, updated_at)
  values (${id}, ${q(name)}, 'document', ${q(category)}, ${q(share)}, ${team ? q(uid('team', team)) : 'null'}, 'nb', 'platform', ${q(body)}, ${table}, ${validity ?? 'null'},
  ${q(prefix)}, app.doc_tokens(${q(body)}), ${tor}, ${tor}, ${tor}, ${ago(40)}, ${ago(12)});
insert into app.document_template_versions (template_id, version, body_html, product_table, created_by, created_at) values (${id}, 1, ${q(body)}, ${table}, ${tor}, ${ago(40)});`)
  }
  // a presentation and a spreadsheet live in a drive (the platform renders documents only); their placeholders are
  // the design's. Making a document from them needs the drive adapter and answers not_connected until it exists.
  const drive = [['presentasjon', 'Kundepresentasjon', 'presentation', 'presentations', 'company', 'google', ['organization.name', 'organization.employees']],
    ['prisberegning', 'Prisberegning', 'spreadsheet', 'spreadsheets', 'private', 'microsoft', ['product.table', 'deal.currency']]]
  for (const [key, name, kind, category, share, source, placeholders] of drive) {
    sql(`insert into app.document_templates (id, name, kind, category, share, language, source, placeholders, owner_id, created_by, updated_by, created_at, updated_at)
  values (${q(uid('doc-template', key))}, ${q(name)}, ${q(kind)}, ${q(category)}, ${q(share)}, 'nb', ${q(source)}, array[${placeholders.map(q).join(', ')}]::text[], ${tor}, ${tor}, ${tor}, ${ago(40)}, ${ago(20)});`)
  }

  // ---- documents (Documents.dc.html, DO) on the design's deals, owned by the deal's owner
  const docs = [
    ['lager', 'Tilbud — Skiftly for lageret', 'tilbud', 'd101', 'eirik', 'T-1', 6],
    ['avtale-skiftly', 'Avtale om bruk av Skiftly', 'saas', 'd101', 'eirik', null, 4],
    ['avvik-rollout', 'Tilbud — Avvikspunkt rollout', 'tilbud', 'd104', 'ingrid', 'T-2', 3],
    ['rammeavtale', 'Rammeavtale kommune', 'offentlig', 'd130', 'ingrid', null, 2],
    ['full-platform', 'Avtale — Full platform', 'saas', 'd201', 'eirik', null, 9],
  ]
  for (const [key, name, tpl, deal, owner, number, days] of docs) {
    const d = `(select * from app.deals where id = ${q(uid('deal', deal))})`
    sql(`insert into app.documents (id, number, name, template_id, template_version, kind, source, deal_id, organization_id, person_id, product, status, valid_until,
  storage, owner_id, visibility, created_by, updated_by, created_at, updated_at)
  select ${q(uid('document', key))}, ${q(number)}, ${q(name)}, t.id, 1, 'document', 'template', d.id, d.organization_id, d.person_id, d.product, 'draft',
  case when t.validity_days is not null then ((${ago(days)}) at time zone 'Europe/Oslo')::date + t.validity_days end,
  'platform', ${q(uid('staff', owner))}, 'all', ${q(uid('staff', owner))}, ${q(uid('staff', owner))}, ${ago(days)}, ${ago(days)}
  from ${d} d, app.document_templates t where t.id = ${q(uid('doc-template', tpl))};`)
  }
  sql(`insert into app.document_counters (prefix, next) values ('T-', 3);`)
  // rendered as document_create renders: merge values (escaped), the deal's product table, missing and unknown tokens
  sql(`update app.documents x set body_html = r.j ->> 'html',
  merge_missing = array(select jsonb_array_elements_text(r.j -> 'missing')) || array(select jsonb_array_elements_text(r.j -> 'unknown')), totals = r.tb -> 'totals'
  from (select d.id, l.tb, app.doc_render(t.body_html, app.merge_context('deal', d.deal_id, null, d.owner_id) || jsonb_build_object('document', d.id, 'language', t.language), l.tb ->> 'html') j
        from app.documents d join app.document_templates t on t.id = d.template_id
        cross join lateral (select app.doc_product_table(d.deal_id, case when t.product_table is not null then array(select jsonb_array_elements_text(t.product_table -> 'columns')) end, t.language) tb) l
        where d.id in (${docs.map(([key]) => q(uid('document', key))).join(', ')})) r
  where x.id = r.id;`)

  // ---- the quote for the warehouse was shared with Kari two days ago and opened three times (DOC-04). The token was
  // returned once when the link was made; only its hash is kept, so the seed stores the hash of a random token.
  const link = q(uid('document-link', 'lager-kari'))
  sql(`insert into app.document_links (id, document_id, token_sha256, recipient_person_id, created_by, created_at)
  values (${link}, ${q(uid('document', 'lager'))}, sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'UTF8')), ${q(uid('person', 'p1'))},
  ${q(uid('staff', 'eirik'))}, ${osloAt(-2, 8, 55)});
insert into app.document_views (link_id, document_id, started_at, duration_seconds, client_class) values
  (${link}, ${q(uid('document', 'lager'))}, ${osloAt(-2, 9, 12)}, 75, 'human'),
  (${link}, ${q(uid('document', 'lager'))}, ${osloAt(-1, 18, 31)}, 120, 'human'),
  (${link}, ${q(uid('document', 'lager'))}, ${osloAt(-1, 18, 40)}, 240, 'human');
update app.documents set status = 'opened', sent_at = ${osloAt(-2, 8, 55)}, first_opened_at = ${osloAt(-2, 9, 12)}, last_opened_at = ${osloAt(-1, 18, 40)}
  where id = ${q(uid('document', 'lager'))};`)

  // ---- the SaaS agreement has a draft signature request: Kari and Tor, a signature and a date field each, where
  // the design places them (x, y, w in % of the page; 38 px of the 520 px page is 7.3 %). Nothing is sent: sending
  // needs the document's PDF and the email provider. The evidence chain starts with «created»; the generator runs
  // with triggers off, so the hash is computed here with the chain's own function.
  const req = q(uid('signature-request', 'avtale-skiftly'))
  const created = osloAt(-1, 10, 5)
  sql(`insert into app.signature_requests (id, document_id, status, service, language, otp_required, created_by, created_at, updated_at)
  values (${req}, ${q(uid('document', 'avtale-skiftly'))}, 'draft', 'builtin', 'nb', true, ${q(uid('staff', 'eirik'))}, ${created}, ${created});
insert into app.signature_events (request_id, seq, kind, at, prev_hash, hash, detail)
  values (${req}, 1, 'created', ${created}, null, app.signature_event_hash(null, ${req}, 1, null, 'created', ${created}, null, '{}'::jsonb), '{}'::jsonb);`)
  const signers = [['kari', 1, 'p1', 'Kari Nordmann', 'kari.nordmann@lumio.no', '#2F5D2A'], ['tor', 2, null, 'Tor Lambrechts', 'tor@orgpuls.no', '#6E8FB8']]
  for (const [key, ord, person, name, email, color] of signers) {
    const sid = q(uid('signature-signer', `avtale-skiftly-${key}`))
    sql(`insert into app.signature_signers (id, request_id, ord, person_id, name, email, color) values (${sid}, ${req}, ${ord}, ${person ? q(uid('person', person)) : 'null'}, ${q(name)}, ${q(email)}, ${q(color)});
insert into app.signature_fields (request_id, signer_id, kind, page, x, y, w, h) values
  (${req}, ${sid}, 'signature', 1, 8, ${58 + ord * 12}, 40, 7.3), (${req}, ${sid}, 'date', 1, 52, ${58 + ord * 12}, 26, 7.3);`)
  }
}
