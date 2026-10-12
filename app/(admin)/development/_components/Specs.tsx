import { getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import { loadSpecs } from '@/lib/data/dev-core'
import type { DevTabProps } from '@/lib/data/dev-tabs'
import { SENTRAL_COLOR } from './core/logic'
import type { ProductInfo } from './core/styles'
import { SpecsView as Specs } from './core/SpecsView'

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Development › Spec documents (DevHub.dc.html, v.specs): RFCs kept in Sentral, each with Problem, Options, Decision,
 * Privacy and anonymity, and Rollout, and four sign-offs (Product, Engineering, Security and privacy, Support) that hold
 * for the revision they were given on. The design's comment count has no source and is left out.
 */
export async function SpecsView({ searchParams }: DevTabProps) {
  const t = await getTranslations('devCore')
  const [shell, data] = await Promise.all([getShell(), loadSpecs()])
  const products: ProductInfo[] = [...shell.products.map((p) => ({ key: p.key, name: p.name, color: p.color })), { key: 'sentral', name: t('sentral'), color: SENTRAL_COLOR }]
  const asked = one(searchParams.spec)
  const selected = data.specs.find((s) => s.ref === asked || s.id === asked)?.id ?? data.specs[0]?.id ?? null
  return <Specs data={data} products={products} selected={selected} />
}
