import { getLocale, getTranslations } from 'next-intl/server'

/**
 * The PWA manifest (D-38, R-MOBILE-03): the phone app is this web app. Served under /m beside the service worker, in the
 * staff member's language. It holds no data: names, the start page, the colours and the icon. The page links it with
 * credentials (crossOrigin «use-credentials»), so the middleware's sign-in check applies as for any other path.
 */
export const dynamic = 'force-dynamic'

export async function GET() {
  const t = await getTranslations('mobile.pwa')
  const locale = await getLocale()
  const manifest = {
    name: t('name'),
    short_name: t('shortName'),
    description: t('description'),
    lang: locale,
    start_url: '/mobile',
    scope: '/',
    display: 'standalone',
    background_color: '#FCF6E9', // canvas
    theme_color: '#191510', // ink
    icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' }],
  }
  return new Response(JSON.stringify(manifest), {
    headers: { 'Content-Type': 'application/manifest+json; charset=utf-8', 'Cache-Control': 'private, no-cache' },
  })
}
