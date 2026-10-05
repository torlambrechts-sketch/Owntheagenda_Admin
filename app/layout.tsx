import type { Metadata } from 'next'
import { NextIntlClientProvider } from 'next-intl'
import { getLocale, getMessages, getTranslations } from 'next-intl/server'
import './globals.css'

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations('app')
  return { title: t('name'), robots: { index: false, follow: false } }
}

/**
 * A plain shell until the platform's design arrives (README, «Design»): it carries the pages that prove
 * the foundation — sign-in, second factor, the connection's status — and nothing pretending to be more.
 */
export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getLocale()
  return (
    <html lang={locale === 'en' ? 'en' : 'nb'}>
      <body className="min-h-screen bg-white text-[15px] text-neutral-900 antialiased">
        <NextIntlClientProvider messages={await getMessages()}>{children}</NextIntlClientProvider>
      </body>
    </html>
  )
}
