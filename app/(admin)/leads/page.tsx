import { ContactsPage } from '../contacts/_components/ContactsPage'

/** Leads (route key «leads»): the Contacts screen with its Leads tab. */
export default function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return <ContactsPage searchParams={searchParams} defaultTab="leads" />
}
