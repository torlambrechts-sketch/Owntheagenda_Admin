/**
 * The permission matrix as the database names it (0003 app.right_ok, 0012 adds tickets): the design's
 * scope columns with tickets before Global, and its eleven rows in order. A right is `<scope>:<action>`.
 */
export const SCOPE_KEYS = ['deals', 'projects', 'campaigns', 'tickets', 'global', 'dev'] as const
export const ACTION_KEYS = ['see', 'add', 'edit_others', 'delete', 'bulk', 'export', 'configure', 'workflows', 'reports_others', 'ai', 'security'] as const
