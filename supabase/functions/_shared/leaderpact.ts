/**
 * LeaderPact's commands and the scope each needs (its public.platform_command, leaderpact 0025: the same contract as
 * Orgpuls 0205). A token carries only the scope of the one command it is for. LeaderPact bills per group, so its billing
 * commands take p_team; it refuses an argument a command does not take (invalid_args). A command LeaderPact adds is
 * added here too; one it removes, removed.
 */
export const LEADERPACT_COMMANDS = {
  'orgs.list': 'orgs:read',
  'orgs.get': 'orgs:read',
  'orgs.resync': 'orgs:read',
  'billing.cancel': 'billing:write',
  'billing.cancel_withdraw': 'billing:write',
  'billing.move_to_free': 'billing:write',
  'billing.set_status': 'billing:write',
  'users.deactivate': 'users:write',
  'users.resend_invite': 'users:write',
  'modules.list': 'modules:read',
  'modules.set_status': 'modules:write',
} as const

export type LeaderpactCommand = keyof typeof LEADERPACT_COMMANDS

export const isLeaderpactCommand = (c: string): c is LeaderpactCommand => Object.prototype.hasOwnProperty.call(LEADERPACT_COMMANDS, c)
