/** Where a record opens: the screen of its type with the record in focus. */
const BASE: Record<string, string> = {
  organization: '/customers?org=',
  person: '/contacts?person=',
  lead: '/leads?lead=',
  deal: '/deals?deal=',
  activity: '/activities?activity=',
  ticket: '/tickets?ticket=',
  project: '/projects?project=',
  document: '/documents?document=',
  campaign: '/campaigns?campaign=',
}

export const recordHref = (entity: string, id: string) => `${BASE[entity] ?? '/?'}${encodeURIComponent(id)}`
