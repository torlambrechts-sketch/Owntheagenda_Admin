/** The notification kinds the bell reads; the same list as the newest `notifications_kind_check` (0044). */
export const NOTIFICATION_KINDS = ['mention', 'reminder', 'security', 'system', 'assignment', 'chat_request'] as const
export type NotificationKind = (typeof NOTIFICATION_KINDS)[number]
