import { getTranslations } from 'next-intl/server'

/**
 * A screen whose build has not landed yet on this branch: it says so in the design's empty treatment,
 * with nothing that looks like data. Replaced screen by screen as the phases land.
 */
export async function Pending({ phase }: { phase: number }) {
  const t = await getTranslations('common.pending')
  return (
    <div className="px-4 pb-12 pt-[26px] md:px-7">
      <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center">
        <div className="text-15 font-bold">{t('title')}</div>
        <div className="mt-2 text-13 text-muted">{t('body', { phase })}</div>
      </div>
    </div>
  )
}
