'use client'

import { useTranslations } from 'next-intl'
import type { Label, Mailboxes, Template, Thread, ThreadRow } from '@/lib/data/inbox'
import { useGo, useWhen } from './lib'
import { ThreadPane } from './ThreadPane'
import { Composer } from './Composer'

export type Chip = { key: string; n: string; cls: string; style?: React.CSSProperties }

/** The chips a thread carries in the list (Inbox.dc.html, t.chips), each derived from what is stored. */
export function useChips(labels: Label[]) {
  const t = useTranslations('inbox.chips')
  return (x: ThreadRow): Chip[] => [
    ...(x.mailbox?.kind === 'team' ? [{ key: 'team', n: t('team'), cls: 'bg-teal-soft text-ok-ink' }] : []),
    ...(x.links.some((l) => l.entity === 'deal') ? [{ key: 'deal', n: t('deal'), cls: 'bg-highlight text-amber-ink' }] : []),
    ...(x.links.some((l) => l.entity === 'lead') ? [{ key: 'lead', n: t('lead'), cls: 'bg-lilac text-lilac-ink' }] : []),
    ...(x.opens > 0 ? [{ key: 'opens', n: t('opened', { n: x.opens }), cls: 'bg-ok-bg text-ok-ink' }] : []),
    ...labels.filter((l) => x.labels.includes(l.id)).map((l) => ({ key: l.id, n: l.name, cls: '', style: { background: l.bg, color: l.ink } })),
  ]
}

/** Inbox, team inbox, archive and a label (v.mail): the thread list and the open thread, or the new-email composer. */
export function MailView({ folderName, threads, thread, compose, mailboxes, templates, mergeFields, labels, now, ai, canAi, canLead, canLabel }: {
  folderName: string
  threads: ThreadRow[]
  thread: Thread | null
  compose: boolean
  mailboxes: Mailboxes
  templates: Template[]
  mergeFields: string[]
  labels: Label[]
  now: string
  ai: boolean
  canAi: boolean
  canLead: boolean
  canLabel: boolean
}) {
  const t = useTranslations('inbox')
  const { go } = useGo()
  const when = useWhen(now)
  const chips = useChips(labels)

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="flex items-center gap-[6px] border-b border-line px-3 py-[10px]">
          <b className="flex-1 text-13.5">{folderName}</b>
          <span className="text-11.5 text-muted">{threads.length}</span>
        </div>
        {threads.map((x) => {
          const on = x.id === thread?.id
          const fw = x.unread ? 'font-bold' : 'font-medium'
          return (
            <button
              key={x.id}
              type="button"
              aria-current={on ? 'true' : undefined}
              onClick={() => go({ thread: x.id, compose: null })}
              className={`flex w-full cursor-pointer flex-col gap-[3px] border-b border-line px-[13px] py-[11px] text-left ${on ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="flex justify-between gap-2 text-12">
                <b className={fw}>{x.from_name ?? t('noSender')}</b>
                <span className="text-faint">{when.short(x.last_message_at)}</span>
              </span>
              <span className={`text-13 leading-[1.3] ${fw}`}>{x.subject || t('noSubject')}</span>
              <span className="overflow-hidden text-ellipsis whitespace-nowrap text-12 text-muted">{x.snippet}</span>
              <span className="mt-[2px] flex flex-wrap gap-1">
                {chips(x).map((c) => (
                  <span key={c.key} className={`rounded-999 px-[7px] py-px text-10.5 font-bold ${c.cls}`} style={c.style}>{c.n}</span>
                ))}
              </span>
            </button>
          )
        })}
        {threads.length === 0 ? <div className="p-[30px] text-center text-13 text-muted">{t('empty')}</div> : null}
      </div>
      {compose ? (
        <div className="flex min-w-0 flex-col gap-3">
          <div className="rounded-20 border border-line bg-surface px-5 py-4">
            <h2 className="m-0 font-serif text-20 font-semibold leading-[1.2]">{t('newEmail')}</h2>
          </div>
          <Composer mode="new" thread={null} mailboxes={mailboxes} templates={templates} mergeFields={mergeFields} ai={ai} />
        </div>
      ) : thread ? (
        <ThreadPane
          thread={thread}
          mailboxes={mailboxes}
          templates={templates}
          mergeFields={mergeFields}
          labels={labels}
          now={now}
          ai={ai}
          canAi={canAi}
          canLead={canLead}
          canLabel={canLabel}
        />
      ) : null}
    </div>
  )
}
