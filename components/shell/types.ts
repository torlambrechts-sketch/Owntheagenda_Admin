/** The shell's data as the client receives it (parsed on the server, lib/shell.ts). */
export type ShellData = {
  me: {
    id: string
    email: string
    name: string
    initials: string | null
    title: string | null
    locale: 'en' | 'no'
    time_zone: string
    number_format: 'space_comma' | 'comma_dot' | 'dot_comma'
    sandbox: boolean
    permission_set: string
    permission_kind: 'admin' | 'regular' | 'custom'
    rights: string[]
    owner: boolean
  }
  products: { key: string; name: string; description: string | null; color: string; ink: string; installed: boolean; enabled: boolean }[]
  modules: Record<string, boolean>
  settings: { session_idle: string; ip_allowlist: string }
  unread: number
  badges: Record<string, number>
}

export const canIn = (shell: ShellData, scope: 'deals' | 'projects' | 'campaigns' | 'global', action: string) =>
  shell.me.permission_kind === 'admin' || shell.me.rights.includes(`${scope}:${action}`)
