import type { CommandClaims } from './signing.ts'

/**
 * Orgpuls' commands and the scope each needs (its app.platform_command_map, 0205/0206/0207). A token carries
 * only the scope of the one command it is for, so a leaked token can do one kind of thing for five
 * minutes, once. A command Orgpuls adds is added here too; one it removes, removed.
 */
export const ORGPULS_COMMANDS = {
  'orgs.list': 'orgs:read',
  'orgs.get': 'orgs:read',
  'orgs.deletions': 'orgs:read',
  'orgs.delete_now': 'orgs:write',
  'orgs.resync': 'orgs:read',
  'billing.cancellation': 'billing:read',
  'billing.extend_trial': 'billing:write',
  'billing.cancel': 'billing:write',
  'billing.cancel_withdraw': 'billing:write',
  'translations.list': 'translations:read',
  'translations.sources': 'translations:read',
  'translations.history': 'translations:read',
  'translations.auto_approve': 'translations:read',
  'translations.import': 'translations:write',
  'translations.update': 'translations:write',
  'translations.approve': 'translations:write',
  'translations.set_auto_approve': 'translations:write',
  'overrides.list': 'translations:read',
  'overrides.import': 'translations:write',
  'overrides.approve': 'translations:write',
  'modules.list': 'modules:read',
  'modules.set_status': 'modules:write',
  'modules.set_validation': 'modules:write',
  'modules.sync': 'modules:write',
  'modules.pilot': 'modules:write',
  'locales.pilots': 'modules:read',
  'locales.pilot': 'modules:write',
  'legal.reviews': 'legal:read',
  'legal.approvals': 'legal:read',
  'legal.review': 'legal:write',
  'legal.set': 'legal:write',
  'legal.auto_record': 'legal:write',
  'settings.notice': 'settings:read',
  'settings.set_notice': 'settings:write',
  'settings.set_indexing': 'settings:write',
} as const

export type OrgpulsCommand = keyof typeof ORGPULS_COMMANDS

export const isOrgpulsCommand = (c: string): c is OrgpulsCommand => Object.prototype.hasOwnProperty.call(ORGPULS_COMMANDS, c)

/** two minutes is ample for one call; Orgpuls accepts at most five */
export function commandClaims(actor: string, command: OrgpulsCommand, nowSec: number, jti: string): CommandClaims {
  return { aud: 'orgpuls', sub: actor.slice(0, 254), scope: ORGPULS_COMMANDS[command], jti, iat: nowSec, exp: nowSec + 120 }
}
