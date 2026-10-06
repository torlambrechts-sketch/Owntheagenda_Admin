/**
 * The message catalogue, one JSON file per namespace and language. A new namespace is a file in both
 * messages/en and messages/no and a line in each list below; scripts/verify-i18n.mjs checks they agree.
 */
import enAuth from '@/messages/en/auth.json'
import enShell from '@/messages/en/shell.json'
import enCommon from '@/messages/en/common.json'
import enOverview from '@/messages/en/overview.json'
import noAuth from '@/messages/no/auth.json'
import noShell from '@/messages/no/shell.json'
import noCommon from '@/messages/no/common.json'
import noOverview from '@/messages/no/overview.json'

export const locales = ['en', 'no'] as const
export type Locale = (typeof locales)[number]

const catalogue = {
  en: { ...enAuth, ...enShell, ...enCommon, ...enOverview },
  no: { ...noAuth, ...noShell, ...noCommon, ...noOverview },
}

export const messagesFor = (locale: Locale) => catalogue[locale]
