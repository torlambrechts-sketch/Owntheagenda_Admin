import 'server-only'
import { cache } from 'react'
import { z } from 'zod'
import { RpcError, rpcOrThrow } from '@/lib/rpc'

export const Shell = z.object({
  me: z.object({
    id: z.string().uuid(),
    email: z.string(),
    name: z.string(),
    initials: z.string().nullable(),
    title: z.string().nullable(),
    locale: z.enum(['en', 'no']),
    time_zone: z.string(),
    number_format: z.enum(['space_comma', 'comma_dot', 'dot_comma']),
    sandbox: z.boolean(),
    permission_set: z.string(),
    permission_kind: z.enum(['admin', 'regular', 'custom']),
    rights: z.array(z.string()),
    owner: z.boolean(),
  }),
  products: z.array(
    z.object({ key: z.string(), name: z.string(), description: z.string().nullable(), color: z.string(), ink: z.string(), installed: z.boolean(), enabled: z.boolean() }),
  ),
  modules: z.record(z.string(), z.boolean()),
  settings: z.object({ session_idle: z.string(), ip_allowlist: z.string() }),
  unread: z.number(),
  badges: z.record(z.string(), z.number()),
  /** whether the staff member has the meeting workspace (deals:see, the module, their own switch; 0050, R-MEETINGS-02) */
  meetings_workspace: z.boolean().optional(),
})
export type Shell = z.infer<typeof Shell>

/** The signed-in staff member's shell, once per request (the layout and the i18n config share it). */
export const getShell = cache(async (): Promise<Shell> => {
  const s = await getShellIfSignedIn()
  if (!s) throw new RpcError('not_signed_in', null)
  return s
})

/** The same where there may be no session (the i18n config on the sign-in pages): null, quietly. */
export const getShellIfSignedIn = cache(async (): Promise<Shell | null> => rpcOrThrow('shell', {}, Shell, { quiet: true }).catch(() => null))

/** May the staff member do this action in this scope? (Mirrors app.can; the database decides.) */
export const can = (shell: Shell, scope: 'deals' | 'projects' | 'campaigns' | 'tickets' | 'global' | 'dev', action: string) =>
  shell.me.permission_kind === 'admin' || shell.me.rights.includes(`${scope}:${action}`)
