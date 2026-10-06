'use client'

import { useTranslations } from 'next-intl'
import type { CampaignRow, CampaignStatus } from '@/lib/data/campaigns-shared'

/** Status pill colours: the design's Scheduled, Sent and Active; the states it lacks in its own palette (D-41). */
const PILL: Record<CampaignStatus | 'held', string> = {
  scheduled: 'bg-highlight text-amber-ink',
  sent: 'bg-ok-bg text-ok-ink',
  active: 'bg-teal-soft text-ok-ink',
  draft: 'bg-tile text-muted',
  sending: 'bg-blue-bg text-blue-ink',
  paused: 'bg-amber-bg text-amber-ink',
  canceled: 'bg-apricot text-rust-ink',
  held: 'bg-salmon text-rust-ink',
}

export function StatusPill({ c }: { c: Pick<CampaignRow, 'status' | 'hold_reason'> }) {
  const t = useTranslations('campaigns')
  const held = c.status === 'scheduled' && !!c.hold_reason
  const k = held ? 'held' : c.status
  return (
    <span title={held ? t(`hold.${c.hold_reason!.replace(':', '_')}`) : undefined} className={`whitespace-nowrap rounded-999 px-[9px] py-[2px] text-11 font-bold ${PILL[k]}`}>
      {t(`status.${k}`)}
    </span>
  )
}

export const card = 'rounded-20 border border-line bg-surface'
export const small = 'h-[30px] rounded-8 border border-line bg-canvas px-2 text-12 text-ink'
export const btn = 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border px-[11px] text-12 font-bold disabled:cursor-default disabled:opacity-50'
export const ghost = `${btn} border-line bg-transparent font-semibold`
export const dark = `${btn} border-ink bg-surface`
export const primary = `${btn} border-ink bg-primary`
export const danger = `${btn} border-coral bg-transparent font-normal text-rust`
export const label = 'flex flex-col gap-[3px] text-12 text-muted'
