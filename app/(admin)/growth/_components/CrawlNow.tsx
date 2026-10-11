'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { checkSiteHealth } from '../actions'

/** The crawler card's one button: read the site now instead of tonight */
export function CrawlNow({ site }: { site: string }) {
  const t = useTranslations('simpleGrowth.seo.health')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <button type="button" disabled={pending} onClick={() => start(async () => {
      const r = await checkSiteHealth({ site })
      if (!r.ok) { flash(t.has(`codes.${r.code}`) ? t(`codes.${r.code}`) : t('codes.failed')); return }
      flash(r.error === 'unreachable' ? t('codes.unreachable') : t('checked', { pages: r.pages, issues: r.issues }))
      router.refresh()
    })} className="h-[30px] flex-none cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold">
      {pending ? t('checking') : t('check')}
    </button>
  )
}
