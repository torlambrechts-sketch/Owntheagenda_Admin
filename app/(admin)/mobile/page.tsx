import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import { loadPreview } from '@/lib/data/mobile'
import { MobileScreen } from './_components/MobileScreen'

/**
 * Mobile (Mobile.dc.html; spec §7, MOB-01..08, AIA-07, UF-21, SF-31, SF-44, D-38): six phone previews of the signed-in
 * staff member's own data (Focus, Nearby, Deal on the go, Capture, Notifications, Extras), with offline sync, push devices
 * and notification types under them. Deals:see and the mobile module (app.mobile_require); without them only the reason.
 * The device's position is never asked for on load: the first render has none.
 */
export default async function MobilePage() {
  const shell = await getShell()
  const t = await getTranslations('mobile')

  const closed = (key: 'moduleOff' | 'body') => (
    <div className="px-4 pb-[60px] pt-5 md:px-7">
      <div className="rounded-20 border border-line bg-surface p-[26px]">
        <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
        <p className="m-0 mt-2 text-13 text-muted">{t(`noAccess.${key}`)}</p>
      </div>
    </div>
  )
  if (shell.modules.mobile === false) return closed('moduleOff')
  if (!can(shell, 'deals', 'see')) return closed('body')

  const preview = await loadPreview(shell.me.id, null)
  if (!preview.ok) {
    if (preview.code === 'module_off') return closed('moduleOff')
    if (preview.code === 'forbidden') return closed('body')
    throw new Error(preview.code)
  }
  return (
    <>
      {/* the PWA's manifest (R-MOBILE-03), fetched with the session's cookies like every signed-in path; React places it in <head> */}
      <link rel="manifest" href="/m/manifest.webmanifest" crossOrigin="use-credentials" />
      <MobileScreen staffId={shell.me.id} numberFormat={shell.me.number_format} initial={preview.data} />
    </>
  )
}
