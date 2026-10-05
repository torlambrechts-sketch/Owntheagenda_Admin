import { NextResponse, type NextRequest } from 'next/server'
import { boundedFetch, supabaseEnv } from '@/lib/supabase/env'

/**
 * Every page but the sign-in needs a session, and a session needs its second factor: an admin tool
 * is not reachable with a password alone. Whether the account is an admin's at all is the page's
 * question (public.admin_whoami); this only refreshes the session and sends the visitor to the step
 * they are missing. It fails closed: no settings, or a failed check, is the sign-in page.
 */
const PUBLIC = ['/login', '/ingen-tilgang']

export async function middleware(request: NextRequest) {
  const path = request.nextUrl.pathname
  if (PUBLIC.some((p) => path === p || path.startsWith(`${p}/`))) return NextResponse.next({ request })

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
