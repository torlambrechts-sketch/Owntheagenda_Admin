import { NextResponse, type NextRequest } from 'next/server'
import { boundedFetch, supabaseEnv } from '@/lib/supabase/env'
import { DEVICE_COOKIE, SEEN_COOKIE, originOf, report, sessionOf } from '@/lib/supabase/report'
import { servedOnHost } from '@/lib/mail/link-host'

/**
 * Every page but the sign-in needs a session, and a session needs its second factor: an admin tool
 * is not reachable with a password alone. Whether the account is an admin's at all is the page's
 * question (public.admin_whoami); this only refreshes the session and sends the visitor to the step
 * they are missing. It fails closed: no settings, or a failed check, is the sign-in page.
 *
 * At most once a minute per session it also tells the session register the session is still in use, and from
 * where (session-report, R-SECURITY-04). A session the register has ended (revoked, idle, outside the IP rules
 * or the sign-in hours, a deactivated account) is signed out here. A report that cannot be delivered does not
 * stop the request: the database checks every session itself on every call (app.session_ok).
 */
const SEEN_EVERY_S = 60
// /u: the unsubscribe page every campaign email links to (its token is the authority, noindex); /velkommen: an invitation's
// password step (the one-time token from the email signs the person in; /mfa follows). Neither shows anything without a token.
const PUBLIC = ['/login', '/ingen-tilgang', '/u', '/velkommen']

export async function middleware(request: NextRequest) {
  const path = request.nextUrl.pathname
  // an application's link address (post.<domain>, 0063) answers the unsubscribe page only; everything else there is absent
  if (!servedOnHost(request.headers.get('host'), path)) return new NextResponse(null, { status: 404 })
  if (PUBLIC.some((p) => path === p || path.startsWith(`${p}/`))) return NextResponse.next({ request })

  // the admin layout decides access by route (lib/nav.ts routeVisible); this is the only writer, so a client's own header is overwritten
  request.headers.set('x-sentral-path', path)

  const to = (pathname: string) => {
    const url = request.nextUrl.clone()
    url.pathname = pathname
    url.search = ''
    return NextResponse.redirect(url)
  }
  const env = supabaseEnv()
  if ('problem' in env) {
    console.error(`[middleware] ${env.problem}`)
    return to('/login')
  }
  try {
    const { createServerClient } = await import('@supabase/ssr')
    let response = NextResponse.next({ request })
    const supabase = createServerClient(env.url, env.key, {
      global: { fetch: boundedFetch },
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (toSet) => {
          toSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          toSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
        },
      },
    })
    const { data } = await supabase.auth.getUser()
    if (!data.user) return to('/login')
    if (path !== '/mfa') {
      const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
      if (aal?.currentLevel !== 'aal2') return to('/mfa')
      const token = (await supabase.auth.getSession()).data.session?.access_token
      const session = token ? sessionOf(token) : null
      const now = Math.floor(Date.now() / 1000)
      const [seenFor, seenAt] = (request.cookies.get(SEEN_COOKIE)?.value ?? '').split('.')
      if (token && session && !(seenFor === session && now - Number(seenAt) < SEEN_EVERY_S)) {
        const reply = await report({ kind: 'seen', token, origin: originOf(request.headers), device: request.cookies.get(DEVICE_COOKIE)?.value ?? null })
        if (reply && !reply.ok) {
          await supabase.auth.signOut({ scope: 'local' })
          const url = request.nextUrl.clone()
          url.pathname = '/login'
          url.search = `?ended=${encodeURIComponent(reply.reason ?? 'ended')}`
          const out = NextResponse.redirect(url)
          response.cookies.getAll().forEach((c) => out.cookies.set(c))
          out.cookies.delete(SEEN_COOKIE)
          return out
        }
        if (reply) response.cookies.set(SEEN_COOKIE, `${session}.${now}`, { httpOnly: true, secure: true, sameSite: 'lax', path: '/' })
      }
    }
    return response
  } catch (error) {
    console.error('[middleware] refusing the request: the session check failed', error)
    return to('/login')
  }
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|woff2?)$).*)'],
}
