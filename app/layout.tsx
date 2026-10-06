import type { Metadata } from 'next'
import { NextIntlClientProvider } from 'next-intl'
import { getLocale, getMessages, getTranslations } from 'next-intl/server'
import './globals.css'

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations('app')
  return { title: t('name'), robots: { index: false, follow: false } }
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getLocale()
  return (
    <html lang={locale}>
      <body>
        <NextIntlClientProvider messages={await getMessages()}>{children}</NextIntlClientProvider>
      </body>
    </html>
  )
}
