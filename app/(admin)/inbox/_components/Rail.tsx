import Link from 'next/link'
import { getTranslations } from 'next-intl/server'
import type { Folders, Label } from '@/lib/data/inbox'
import type { Folder } from '@/lib/data/inbox-shared'

type Item = { key: string; href: string; glyph: string; name: string; count: number | null; on: boolean }

/**
 * The left rail (Inbox.dc.html, folders): Compose and the folder groups. The design's buttons navigate, so
 * they are links with the same look (V-01). Counts are the database's: unread threads per mailbox folder,
 * my messages waiting in the outbox, my group sends in progress; none where there is no source.
 */
export async function Rail({ folder, teamId, labelId, folders, labels }: {
  folder: Folder
  teamId: string | null
  labelId: string | null
  folders: Folders
  labels: Label[]
}) {
  const t = await getTranslations('inbox')
  const groups: { h: string; items: Item[] }[] = [
    {
      h: t('rail.mail'),
      items: [
        { key: 'inbox', href: '/inbox', glyph: '✉', name: t('folders.inbox'), count: folders.inbox, on: folder === 'inbox' },
        ...folders.teams.map((x) => ({
          key: `team-${x.mailbox_id}`, href: `/inbox?folder=team&mailbox=${x.mailbox_id}`, glyph: '◎',
          name: t('folders.team', { local: x.address.split('@')[0]! }), count: x.unread, on: folder === 'team' && teamId === x.mailbox_id,
        })),
        { key: 'outbox', href: '/inbox?folder=outbox', glyph: '◷', name: t('folders.outbox'), count: folders.outbox + folders.review, on: folder === 'outbox' },
        { key: 'group', href: '/inbox?folder=group', glyph: '⁂', name: t('folders.group'), count: folders.group, on: folder === 'group' },
        { key: 'archive', href: '/inbox?folder=archive', glyph: '▤', name: t('folders.archive'), count: null, on: folder === 'archive' },
      ],
    },
    {
      h: t('rail.channels'),
      items: [
        { key: 'messaging', href: '/inbox?folder=messaging', glyph: '◌', name: t('folders.messaging'), count: null, on: folder === 'messaging' },
        { key: 'calls', href: '/inbox?folder=calls', glyph: '☎', name: t('folders.calls'), count: null, on: folder === 'calls' },
      ],
    },
    // the labels that exist for email threads; Settings creates them, and with none the group is left out
    ...(labels.length
      ? [{
          h: t('rail.labels'),
          items: labels.map((l) => ({ key: `label-${l.id}`, href: `/inbox?folder=label&label=${l.id}`, glyph: '●', name: l.name, count: null, on: folder === 'label' && labelId === l.id })),
        }]
      : []),
    {
      h: t('rail.setup'),
      items: [{ key: 'settings', href: '/inbox?folder=settings', glyph: '⚙', name: t('folders.settings'), count: null, on: folder === 'settings' }],
    },
  ]

  return (
    <nav aria-label={t('rail.label')} className="flex flex-[0_0_200px] flex-col gap-3">
      <Link
        href="/inbox?compose=1"
        className="flex h-10 items-center justify-center rounded-11 border border-ink bg-primary text-13 font-bold text-ink hover:text-ink hover:no-underline"
      >
        {t('compose')}
      </Link>
      {groups.map((g) => (
        <div key={g.h} className="flex flex-col gap-px">
          <div className="px-2 pb-1 text-10.5 font-bold uppercase tracking-label text-faint">{g.h}</div>
          {g.items.map((f) => (
            <Link
              key={f.key}
              href={f.href as never}
              aria-current={f.on ? 'page' : undefined}
              className={`flex items-center gap-2 rounded-10 px-[9px] py-[7px] text-left text-13 text-ink hover:text-ink hover:no-underline ${f.on ? 'bg-highlight font-bold' : 'bg-transparent font-medium'}`}
            >
              <span className="w-4 text-center text-12">{f.glyph}</span>
              <span className="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap">{f.name}</span>
              {f.count ? <span className="text-11 font-bold text-muted">{f.count}</span> : null}
            </Link>
          ))}
        </div>
      ))}
    </nav>
  )
}
