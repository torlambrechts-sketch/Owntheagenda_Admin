import { cookies } from 'next/headers'
import { getRequestConfig } from 'next-intl/server'
import { messagesFor, type Locale } from './messages'
import { getShellIfSignedIn } from '@/lib/shell'

/**
 * English is the default; bokmål is available. The language and time zone are the staff member's own
 * (D-04): read from their profile when signed in, else the `lang` cookie the profile keeps in step, else
 * English. No locale in the address.
 */
export default getRequestConfig(async () => {
  const shell = await getShellIfSignedIn()
  const cookie = (await cookies()).get('lang')?.value
  const locale: Locale = shell?.me.locale ?? (cookie === 'no' ? 'no' : 'en')
  // British English writes dates the way the design does («Monday 5 October 2026»)
  return { locale: locale === 'no' ? 'nb' : 'en-GB', timeZone: shell?.me.time_zone ?? 'Europe/Oslo', messages: messagesFor(locale) }
})
