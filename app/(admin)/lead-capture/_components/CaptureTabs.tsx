import Link from 'next/link'
import type { Route } from 'next'
import { getTranslations } from 'next-intl/server'
import type { Pill } from '@/lib/data/capture-shared'

/** Where each of the design's eight pills leads: the first four are the Campaigns route's tabs (phase 6). */
const HREF: Record<Pill, string> = {
  campaigns: '/campaigns',
  builder: '/campaigns?tab=builder',
  audience: '/campaigns?tab=audience',
  deliver: '/campaigns?tab=deliverability',
  forms: '/lead-capture',
  chat: '/lead-capture?tab=chat',
  prospect: '/lead-capture?tab=prospect',
  visitors: '/web-visitors',
}

/**
 * The Marketing screen's pill row (Marketing.dc.html, tabs). The design's buttons become links (V-01); a pill
 * whose module is off or whose rights the staff member lacks is not listed (spec §1, module gating).
 */
export async function CaptureTabs({ current, pills }: { current: Pill; pills: Pill[] }) {
  const t = await getTranslations('capture.tabs')
  return (
    <nav className="flex flex-wrap gap-[6px]" aria-label={t('label')}>
      {pills.map((k) => {
        const on = k === current
        return (
          <Link
            key={k}
            href={HREF[k] as Route}
            aria-current={on ? 'page' : undefined}
            className={`cursor-pointer rounded-999 border px-[13px] py-[7px] text-12.5 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
          >
            {t(k)}
          </Link>
        )
      })}
    </nav>
  )
}

/** Which pills the staff member sees: modules on (shell.modules) and the right to see each area (spec §6). */
export function visiblePills(modules: Record<string, boolean>, rights: { campaigns: boolean; deals: boolean }): Pill[] {
  const on = (m: string) => modules[m] !== false
  const out: Pill[] = []
  if (on('campaigns') && rights.campaigns) out.push('campaigns', 'builder', 'audience', 'deliver')
  if (on('leadgen') && rights.campaigns) out.push('forms')
  if (on('leadgen') && (rights.campaigns || rights.deals)) out.push('chat')
  if (on('leadgen') && rights.deals) out.push('prospect')
  if (on('visitors') && rights.deals) out.push('visitors')
  return out
}
