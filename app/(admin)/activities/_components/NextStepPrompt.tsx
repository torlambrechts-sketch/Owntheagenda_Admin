'use client'

import { useTransition } from 'react'
import { useTranslations } from 'next-intl'
import type { ActivityRow } from '@/lib/data/activities'
import { addDays, fromZoned, parseYmd } from '@/lib/data/activities-time'
import { useToast } from '@/components/ui/Toast'
import { planNext } from '../actions'
import type { Ctx } from './shared'

// the design's four next steps: the activity type, and how many days ahead (at 10:00, the dialog's default time)
const OPTIONS = [
  { key: 'call', type: 'call', days: 2 },
  { key: 'email', type: 'email', days: 1 },
  { key: 'meeting', type: 'meeting', days: 7 },
  { key: 'proposal', type: 'task', days: 1 },
] as const

/** «Done. What is the next step?» — shown when a completed activity leaves its deal with nothing planned. */
export function NextStepPrompt({ ctx, row, onClose }: { ctx: Ctx; row: ActivityRow; onClose: () => void }) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const flash = useToast()
  const [pending, startTransition] = useTransition()
  const options = OPTIONS.map((o) => ({ ...o, typeId: ctx.types.find((x) => x.key === o.type && x.active)?.id })).filter((o) => o.typeId)

  const plan = (o: (typeof options)[number]) => {
    const at = fromZoned(addDays(parseYmd(ctx.today)!, o.days), 10, 0, ctx.tz).toISOString()
    startTransition(async () => {
      const r = await planNext({
        type_id: o.typeId!, subject: t(`next.subject.${o.key}`), starts_at: at,
        deal_id: row.deal_id, person_id: row.person_id, organization_id: row.organization_id,
      })
      if (!r.ok) { flash(tc(`errors.${r.code}`)); return }
      onClose()
      flash(t('toast.nextPlanned', { what: t(`next.option.${o.key}`) }))
    })
  }

  return (
    <div role="dialog" aria-labelledby="next-step-title" className="fixed bottom-[26px] right-[26px] z-[95] flex w-[360px] max-w-[calc(100vw-32px)] flex-col gap-2 rounded-18 border border-ink bg-surface px-[18px] py-4 shadow-pop">
      <b id="next-step-title" className="text-14">{t('next.title')}</b>
      <span className="text-12.5 text-muted">{t('next.on', { subject: row.subject, deal: row.deal?.title ?? '—' })}</span>
      <div className="flex flex-wrap gap-[6px]">
        {options.map((o) => (
          <button key={o.key} type="button" disabled={pending} onClick={() => plan(o)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">
            {t(`next.option.${o.key}`)}
          </button>
        ))}
      </div>
      <button type="button" onClick={onClose} className="cursor-pointer self-start border-none bg-transparent p-0 text-12 text-muted">{t('next.skip')}</button>
    </div>
  )
}
