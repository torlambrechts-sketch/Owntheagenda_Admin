'use client'

import { useCallback } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { Check, DeliveryProduct } from '@/lib/data/dev-delivery'

const n = (v: unknown) => (typeof v === 'number' ? v : Number(v ?? 0))

/** an application's name as Development shows it (Sentral's own from the messages) */
export function useProductName(products: DeliveryProduct[]) {
  const t = useTranslations('devDelivery')
  return useCallback((key: string) => (key === 'sentral' ? t('sentral') : products.find((p) => p.key === key)?.name ?? key), [products, t])
}

/** a release's title as the design writes it: «Orgpuls v2.15.0» (the product's name unless the name already says it) */
export function releaseTitle(productName: string, name: string) {
  return name.toLowerCase().startsWith(productName.toLowerCase()) ? name : `${productName} ${name}`
}

/**
 * The words of a checklist item: its label (the design's own, per view), where it comes from, and a line saying why it is
 * not ticked or who ticked it. Only what the row holds is said.
 */
export function useCheckText(view: 'release' | 'gate', watching: boolean) {
  const t = useTranslations('devDelivery.checks')
  const format = useFormatter()
  const day = useCallback((v: string) => format.dateTime(new Date(v), { day: 'numeric', month: 'short' }), [format])
  return useCallback((c: Check): { label: string; source: string; sub: string | null; href: string | null } => {
    const det = c.detail ?? {}
    const label = t(`${c.key}.${view}`)
    const source = view === 'gate' ? t(`from.${c.source ?? 'person'}`) : c.kind === 'manual' ? t('manual') : t(`auto.${c.source ?? 'ci'}`)
    let sub: string | null = null
    let href: string | null = null
    if (c.kind === 'manual') {
      if (c.signed) sub = c.signed.note ? t('signedNote', { by: c.signed.by ?? '—', day: day(c.signed.at), note: c.signed.note }) : t('signed', { by: c.signed.by ?? '—', day: day(c.signed.at) })
      else if (c.key === 'anonymity' && c.detail) sub = n(det.failed) > 0 ? t('evidence.anonymityFail', { n: n(det.failed) }) : t('evidence.anonymityPass', { n: n(det.passed) })
      else if (c.key === 'help' && c.detail) sub = t('evidence.help', { n: n(det.changed), day: day(String(det.since)) })
      else if (c.key === 'preview' && c.detail && typeof det.host === 'string') {
        sub = t(det.same_commit ? 'evidence.previewSame' : 'evidence.preview', { host: det.host })
        href = `https://${det.host}`
      }
      return { label, source, sub, href }
    }
    if (c.state === 'pass') return { label, source, sub, href }
    if (c.state === 'unknown') {
      sub = c.key === 'deploy' ? (watching ? (c.detail ? t('unknown.building') : t('unknown.notDeployed')) : t('unknown.noProject'))
        : c.key === 'rls' ? (det.anonymity === false ? t('unknown.noAnonymity') : t('unknown.rls')) : c.key === 'deps' ? t('unknown.deps')
        : c.key === 'tests' && c.detail ? t('unknown.noTests') : t('unknown.noCi')
      return { label, source, sub, href }
    }
    if (c.key === 'tests' || c.key === 'rls') sub = t('fail.failing', { failed: n(det.failed), total: n(det.passed) + n(det.failed) })
    else if (c.key === 'migrations') sub = t('fail.migrations', { names: Array.isArray(det.pending) ? det.pending.join(' · ') : '' })
    else if (c.key === 'deps') sub = t('fail.deps', { critical: n(det.critical), high: n(det.high) })
    else if (c.key === 'deploy') sub = det.rolled_back ? t('fail.rolledBack') : t('fail.deploy')
    else if (c.key === 'notes') sub = t('fail.notes')
    return { label, source, sub, href }
  }, [t, view, watching, day])
}
