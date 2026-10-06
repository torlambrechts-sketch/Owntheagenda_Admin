/**
 * CSV writing for Contacts › Export and the import skip file: RFC 4180 quoting, and formula neutralising
 * (a cell that starts with = + - − @, a tab or a carriage return gets a leading apostrophe so a spreadsheet
 * shows it as text and never runs it).
 */

const FORMULA = /^[=+\-−@\t\r]/

export function neutralise(v: string): string {
  return FORMULA.test(v) ? `'${v}` : v
}

export function csvCell(v: unknown): string {
  if (v === null || v === undefined) return ''
  const s = neutralise(typeof v === 'object' ? JSON.stringify(v) : String(v))
  return /[",\r\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function toCsv(headers: string[], rows: unknown[][]): string {
  return [headers, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n'
}

/** The columns an export carries per record type: registered columns, references written as their titles. */
export const EXPORT_COLUMNS: Record<string, string[]> = {
  person: ['name', 'email', 'phone', 'organization_id__title', 'title', 'contact_type', 'marketing_status', 'source', 'city', 'fylke', 'owner_id__title', 'created_at'],
  organization: ['name', 'org_number', 'address', 'postal_code', 'city', 'fylke', 'country', 'industry', 'employees', 'website', 'phone', 'email', 'source', 'owner_id__title', 'created_at'],
  lead: ['title', 'person_id__title', 'organization_id__title', 'value', 'currency', 'source', 'archived_at', 'converted_at', 'owner_id__title', 'created_at'],
  deal: ['title', 'value', 'currency', 'status', 'organization_id__title', 'person_id__title', 'expected_close_date', 'source', 'product', 'owner_id__title', 'created_at'],
  activity: ['subject', 'starts_at', 'duration_min', 'priority', 'done', 'deal_id__title', 'person_id__title', 'organization_id__title', 'owner_id__title'],
  catalog_item: ['name', 'code', 'unit', 'billing', 'billing_frequency', 'tax_rate', 'product', 'owner_id__title'],
}

export const exportHeader = (col: string) => col.replace(/__title$/, '').replace(/_id$/, '')
