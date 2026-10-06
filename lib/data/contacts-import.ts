/**
 * Import helpers for Contacts › Import: an RFC 4180 CSV parser and the plain column-name matching that
 * proposes a field for each column. Pure functions (no server or browser API), so the parser is tested
 * on its own and runs inside the server action. XLSX is not read here (not supported yet).
 */

export type ImportEntity = 'person' | 'organization' | 'lead'
export const IMPORT_ENTITIES: ImportEntity[] = ['person', 'organization', 'lead']

/** The most a file may hold, the same as import_run's limit. */
export const MAX_ROWS = 50_000
/** A server action's request body is limited to 1 MB by Next.js; the file travels inside it. */
export const MAX_BYTES = 950_000

export type ParsedCsv = { headers: string[]; rows: string[][] }

/** The delimiter of the first line outside quotes: «;» is what Excel writes with a Norwegian locale. */
export function detectDelimiter(text: string): ',' | ';' | '\t' {
  let inQ = false
  const n = { ',': 0, ';': 0, '\t': 0 }
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!
    if (c === '"') inQ = !inQ
    else if (!inQ && (c === '\n' || c === '\r')) break
    else if (!inQ && (c === ',' || c === ';' || c === '\t')) n[c]++
  }
  if (n[';'] > n[','] && n[';'] >= n['\t']) return ';'
  if (n['\t'] > n[','] && n['\t'] > n[';']) return '\t'
  return ','
}

/**
 * RFC 4180: fields separated by the delimiter, records by CRLF or LF; a field in double quotes may hold
 * the delimiter, line breaks and doubled quotes. A byte-order mark is dropped, blank records are skipped,
 * and every record is padded or cut to the header's width.
 */
export function parseCsv(input: string, delimiter?: string): ParsedCsv {
  const text = input.charCodeAt(0) === 0xfeff ? input.slice(1) : input
  const d = delimiter ?? detectDelimiter(text)
  const records: string[][] = []
  let field = ''
  let record: string[] = []
  let inQ = false
  let quotedField = false
  const endField = () => { record.push(quotedField ? field : field.trim()); field = ''; quotedField = false }
  const endRecord = () => {
    endField()
    if (record.some((f) => f !== '')) records.push(record)
    record = []
  }
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!
    if (inQ) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++ } else inQ = false
      } else field += c
      continue
    }
    if (c === '"' && field.trim() === '') { inQ = true; quotedField = true; field = ''; continue }
    if (c === d) { endField(); continue }
    if (c === '\r') { if (text[i + 1] === '\n') i++; endRecord(); continue }
    if (c === '\n') { endRecord(); continue }
    field += c
  }
  if (field !== '' || record.length) endRecord()
  const [head = [], ...body] = records
  const headers = head.map((h, i) => h.trim() || `#${i + 1}`)
  const rows = body.map((r) => headers.map((_, i) => (r[i] ?? '').trim()))
  return { headers, rows }
}

// ---------------------------------------------------------------------------
// targets: what a column can become. Lookups (organization by name or org.nr, person by email) are
// resolved by the server action to the record's id before import_run sees the row.
export type Target =
  | { key: string; col: string; kind: 'text' | 'int' | 'numeric' }
  | { key: 'org_name' | 'org_nr'; col: 'organization_id'; kind: 'lookup_org' }
  | { key: 'person_email'; col: 'person_id'; kind: 'lookup_person' }
  | { key: 'consent_source' | 'consent_basis'; col: '_consent_source' | '_consent_basis'; kind: 'text' }
  | { key: string; col: string; kind: 'custom_text' | 'custom_number' }

const T = (key: string, kind: 'text' | 'int' | 'numeric' = 'text', col = key): Target => ({ key, col, kind })

export const TARGETS: Record<ImportEntity, Target[]> = {
  person: [
    T('name'), T('email'), T('phone'), T('title'), T('source'), T('city'), T('fylke'), T('linkedin'),
    { key: 'org_name', col: 'organization_id', kind: 'lookup_org' }, { key: 'org_nr', col: 'organization_id', kind: 'lookup_org' },
    { key: 'consent_source', col: '_consent_source', kind: 'text' }, { key: 'consent_basis', col: '_consent_basis', kind: 'text' },
  ],
  organization: [
    T('name'), T('org_number'), T('address'), T('postal_code'), T('city'), T('fylke'), T('industry'), T('employees', 'int'),
    T('website'), T('phone'), T('email'), T('source'),
  ],
  lead: [
    T('title'), T('value', 'numeric'), T('source'),
    { key: 'org_name', col: 'organization_id', kind: 'lookup_org' }, { key: 'org_nr', col: 'organization_id', kind: 'lookup_org' },
    { key: 'person_email', col: 'person_id', kind: 'lookup_person' },
  ],
}

/** Custom field types a spreadsheet cell can fill as it is. */
export const CUSTOM_TEXT = ['text', 'large_text', 'phone', 'autocomplete']
export const CUSTOM_NUMBER = ['numerical']

export type CustomField = { key: string; label: string; type: string }

export function targetsFor(entity: ImportEntity, custom: CustomField[]): Target[] {
  return [
    ...TARGETS[entity],
    ...custom
      .filter((f) => CUSTOM_TEXT.includes(f.type) || CUSTOM_NUMBER.includes(f.type))
      .map((f): Target => ({ key: `custom.${f.key}`, col: f.key, kind: CUSTOM_NUMBER.includes(f.type) ? 'custom_number' : 'custom_text' })),
  ]
}

// ---------------------------------------------------------------------------
// plain column-name matching: a normalised header compared with the names a column usually has, in
// bokmål and English. No confidence is claimed: a column either matches a name or it does not.
const SYN: Record<string, string[]> = {
  name: ['navn', 'name', 'fulltnavn', 'fullname', 'kontaktperson', 'contact', 'contactname'],
  email: ['epost', 'email', 'mail', 'emailaddress', 'epostadresse'],
  phone: ['mobil', 'telefon', 'phone', 'tlf', 'mobile', 'mobilnummer', 'telefonnummer', 'phonenumber'],
  title: ['stilling', 'tittel', 'title', 'role', 'rolle', 'jobtitle'],
  source: ['kilde', 'source', 'leadsource'],
  city: ['by', 'poststed', 'city', 'sted', 'town'],
  fylke: ['fylke', 'county', 'region'],
  linkedin: ['linkedin', 'linkedinurl'],
  org_name: ['firma', 'company', 'organisasjon', 'organization', 'organisation', 'bedrift', 'selskap', 'virksomhet', 'companyname'],
  org_nr: ['orgnr', 'organisasjonsnummer', 'orgnumber', 'organizationnumber', 'orgno'],
  address: ['adresse', 'address', 'gateadresse', 'street', 'streetaddress'],
  postal_code: ['postnummer', 'postnr', 'zip', 'zipcode', 'postalcode', 'postcode'],
  industry: ['bransje', 'industry', 'sector'],
  employees: ['ansatte', 'antallansatte', 'employees', 'numberofemployees', 'headcount'],
  website: ['nettside', 'website', 'web', 'url', 'hjemmeside'],
  value: ['verdi', 'value', 'belop', 'amount'],
  consent_source: ['samtykkekilde', 'consentsource'],
  consent_basis: ['samtykkegrunnlag', 'consentbasis', 'grunnlag'],
}

export const normaliseHeader = (h: string) =>
  h.toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9æøå]/g, '')

/** The suggested target key for each column (null: skip). A target is suggested once, to the first column. */
export function suggestMapping(entity: ImportEntity, headers: string[], custom: CustomField[]): (string | null)[] {
  const targets = targetsFor(entity, custom)
  const syn: Record<string, string[]> = { ...SYN }
  if (entity === 'organization') { syn.name = [...SYN.name!, ...SYN.org_name!]; syn.org_number = SYN.org_nr! }
  if (entity === 'lead') { syn.title = ['tittel', 'title', 'lead', 'leadtitle', 'emne', 'subject']; syn.person_email = SYN.email! }
  for (const f of custom) syn[`custom.${f.key}`] = [normaliseHeader(f.label), normaliseHeader(f.key)]
  const used = new Set<string>()
  return headers.map((h) => {
    const n = normaliseHeader(h)
    const hit = targets.find((t) => !used.has(t.key) && (syn[t.key] ?? [normaliseHeader(t.key)]).includes(n))
    if (!hit) return null
    used.add(hit.key)
    return hit.key
  })
}

/** «12 345,50» or «12345.5» → 12345.5; anything else stays text so the row is refused with a reason. */
export function parseNumber(s: string): number | string {
  const t = s.replace(/[\s ]/g, '').replace(/kr$/i, '')
  if (/^-?\d+([.,]\d+)?$/.test(t)) return Number(t.replace(',', '.'))
  return s
}

/** The skip file's reason as a message key under contacts.import.reasons (unknown reasons stay as they are). */
export const KNOWN_REASONS = ['duplicate', 'consent_source_missing', 'invalid', 'forbidden', 'not_found'] as const
