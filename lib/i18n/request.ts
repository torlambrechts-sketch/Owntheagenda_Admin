import { cookies } from 'next/headers'
import { getRequestConfig } from 'next-intl/server'

/**
 * Bokmål is the source; English by the visitor's own choice (a cookie). No locale in the address. Times are
 * Norwegian time: the server runs in UTC, and a time shown without a zone is read as local.
 */
export default getRequestConfig(async () => {
  const locale = (await cookies()).get('lang')?.value === 'en' ? 'en' : 'no'
  return { locale, timeZone: 'Europe/Oslo', messages: (await import(`../../messages/${locale}.json`)).default }
})
