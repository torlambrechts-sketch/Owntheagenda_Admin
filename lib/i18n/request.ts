import { cookies } from 'next/headers'
import { getRequestConfig } from 'next-intl/server'

/** Bokmål is the source; English by the visitor's own choice (a cookie). No locale in the address. */
export default getRequestConfig(async () => {
  const locale = (await cookies()).get('lang')?.value === 'en' ? 'en' : 'no'
  return { locale, messages: (await import(`../../messages/${locale}.json`)).default }
})
