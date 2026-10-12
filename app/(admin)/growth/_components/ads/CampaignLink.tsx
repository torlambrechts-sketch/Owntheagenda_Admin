'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { linkPlatformCampaign } from '../../ads-actions'

/** «Counts as»: the Sentral campaign a platform campaign's spend and figures go to (Campaigns › Edit others'; 0077) */
export function CampaignLink({ id, value, options, label, auto }: { id: string; value: string | null; options: { id: string; name: string }[]; label: string; auto: string }) {
  const t = useTranslations('simpleGrowth.ads')
  const te = useTranslations('common.errors')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  return (
    <select value={value ?? ''} disabled={pending} aria-label={label}
      onChange={(e) => start(async () => {
        const r = await linkPlatformCampaign({ campaign: id, adCampaign: e.target.value || null })
        if (!r.ok) { flash(te(r.code as 'invalid')); return }
        flash(t('campaignLinked'))
        router.refresh()
      })}
      className="h-[28px] max-w-[200px] rounded-8 border border-line bg-canvas px-2 text-12">
      <option value="">{auto}</option>
      {options.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
    </select>
  )
}
