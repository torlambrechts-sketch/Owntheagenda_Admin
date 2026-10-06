import { ContactsPage } from './_components/ContactsPage'

/** Contacts (route key «contacts»): the People tab unless the address asks for another. */
export default function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return <ContactsPage searchParams={searchParams} defaultTab="people" />
}
