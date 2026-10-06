'use client'

import { useTranslations } from 'next-intl'

/** A refusal code as words: the screen's own message (a product's reply), else the common one, else «failed». */
export function useErrorText() {
  const t = useTranslations('customers.errors')
  const c = useTranslations('common.errors')
  return (code: string) => (t.has(code) ? t(code) : c.has(code) ? c(code) : c('failed'))
}
