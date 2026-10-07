'use client'

import type { NotificationKind } from '@/lib/notification-kinds'
import { useEffect, useState, useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { markRead, notifications, type Notifications } from '@/app/(admin)/shell-actions'
import type { ShellData } from './types'

const TABS = [null, 'mention', 'reminder', 'security'] as const
const DOT: Record<NotificationKind, string> = { security: 'bg-alert', mention: 'bg-warn', reminder: 'bg-ok', system: 'bg-ok', assignment: 'bg-ok', chat_request: 'bg-warn' }

/** The bell and its panel: notifications in the reader's language, filtered by kind. */
export function NotificationsMenu({ shell, open, toggle, close }: { shell: ShellData; open: boolean; toggle: () => void; close: () => void }) {
  const t = useTranslations('shell.notifications')
  const format = useFormatter()
  const now = useNow({ updateInterval: 60_000 })
  const router = useRouter()
  const [tab, setTab] = useState<(typeof TABS)[number]>(null)
  const [data, setData] = useState<Notifications | null>(null)
  const [failed, setFailed] = useState(false)
  const [, start] = useTransition()

  useEffect(() => {
    if (!open) return
    let live = true
    notifications(tab).then((d) => { if (live) { setData(d); setFailed(d === null) } })
    return () => { live = false }
  }, [open, tab])

  return (
    <div className="relative">
      <button
        type="button"
        onClick={toggle}
        aria-label={t('label')}
        aria-expanded={open}
        className="relative flex h-9 w-9 cursor-pointer items-center justify-center rounded-10 border border-line bg-transparent"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20a2 2 0 0 0 4 0" />
        </svg>
        {shell.unread > 0 ? (
          <span className="absolute -right-[5px] -top-[5px] flex h-[18px] min-w-[18px] items-center justify-center rounded-999 bg-alert text-10 font-bold text-surface">
            {shell.unread}
          </span>
        ) : null}
      </button>
      {open ? (
        <div className="absolute right-0 top-11 z-[60] w-[380px] max-w-[calc(100vw-32px)] rounded-18 border border-line bg-surface p-2 shadow-pop">
          <div className="flex gap-[6px] border-b border-line px-[6px] pb-[10px] pt-[6px]">
            {TABS.map((k) => {
              const sel = k === tab
              return (
                <button
                  key={k ?? 'all'}
                  type="button"
                  onClick={() => setTab(k)}
                  className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${sel ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium'}`}
                >
                  {t(`tabs.${k ?? 'all'}`)}
                </button>
              )
            })}
          </div>
          <div className="flex max-h-[420px] flex-col overflow-auto pt-1">
            {data?.items.map((n) => (
              <button
                key={n.id}
                type="button"
                onClick={() => {
                  close()
                  start(async () => { await markRead([n.id]); if (n.route) router.push(n.route as never); else router.refresh() })
                }}
                className="flex cursor-pointer items-start gap-[10px] rounded-12 border-none bg-transparent p-[10px] text-left"
              >
                <span className={`mt-[5px] h-[7px] w-[7px] flex-none rounded-999 ${DOT[n.kind]}`} />
                <span className="flex flex-1 flex-col gap-[2px]">
                  <span className={`text-13 leading-[1.35] ${n.read ? 'font-medium' : 'font-semibold'}`}>{t(`messages.${n.key}.title`, n.params)}</span>
                  <span className="text-12 text-muted">{t(`messages.${n.key}.body`, n.params)}</span>
                </span>
                <span className="whitespace-nowrap text-11 text-faint">{format.relativeTime(new Date(n.created_at), now)}</span>
              </button>
            ))}
            {data && data.items.length === 0 ? <div className="p-[26px] text-center text-13 text-muted">{t('empty')}</div> : null}
            {failed ? <div role="alert" className="p-[26px] text-center text-13 text-danger">{t('failed')}</div> : null}
          </div>
          <div className="flex justify-between border-t border-line px-[10px] pb-1 pt-2 text-12">
            <span className="text-muted">{t('channels')}</span>
            <Link href={'/activities?tab=reminders' as never} onClick={close}>{t('channelsLink')}</Link>
          </div>
        </div>
      ) : null}
    </div>
  )
}
