/** Where a record opens: the screen of its type with the record in focus (deals and tickets in Sentral Simple's sections). */
const BASE: Record<string, string> = {
  organization: '/customers?org=',
  person: '/contacts?person=',
  lead: '/leads?lead=',
  deal: '/crm?deal=',
  activity: '/activities?activity=',
  ticket: '/customers?tab=tickets&ticket=',
  project: '/projects?project=',
  document: '/documents?document=',
  campaign: '/campaigns?campaign=',
}

export const recordHref = (entity: string, id: string) => `${BASE[entity] ?? '/?'}${encodeURIComponent(id)}`
