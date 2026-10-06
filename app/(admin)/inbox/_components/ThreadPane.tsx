'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { recordHref } from '@/lib/records-href'
import { type Label, type Mailboxes, type Message, type Template, type Thread } from '@/lib/data/inbox'
import { archiveThread, setThreadLabels, threadToLead } from '../actions'
import { connected } from '@/lib/data/inbox-shared'
import { providerKey, useFail, useGo, useWhen } from './lib'
import { Composer } from './Composer'

// which linked record the thread is «about»: a deal before a lead, an organisation, then a person
const RANK: Record<string, number> = { deal: 0, lead: 1, project: 2, organization: 3, person: 4 }
export const primaryLink = (th: Thread) => [...th.links].sort((a, b) => (RANK[a.entity] ?? 9) - (RANK[b.entity] ?? 9))[0] ?? null

/** The open thread (v.mail, right column): header with link, archive, create lead and labels; the AI panel; the messages; the reply composer. */
export function ThreadPane({ thread: th, mailboxes, templates, mergeFields, labels, now, canLead, canLabel }: {
  thread: Thread
  mailboxes: Mailboxes
  templates: Template[]
  mergeFields: string[]
  labels: Label[]
  now: string
  canLead: boolean
  canLabel: boolean
}) {
  const t = useTranslations('inbox')
  const flash = useToast()
  const { fail } = useFail()
  const { go } = useGo()
  const router = useRouter()
  const when = useWhen(now)
  const [busy, start] = useTransition()
  const [body, setBody] = useState('')
  const [labelIds, setLabelIds] = useState(th.labels)
  const [version, setVersion] = useState(th.version)

  const box = th.mailbox ? mailboxes.mailboxes.find((m) => m.id === th.mailbox!.id) ?? null : null
  const provider = th.mailbox ? t(`provider.${providerKey(th.mailbox.provider)}`) : null
  const link = primaryLink(th)
  const insight = th.insight?.state === 'ready' ? th.insight : null

  const archive = () => start(async () => {
    const r = await archiveThread({ id: th.id, archived: !th.archived })
    if (!r.ok) return fail(r.code, r.detail)
    const synced = box && connected(box.status)
    flash(th.archived ? t('toast.unarchived') : synced ? t('toast.archived', { provider: provider ?? '' }) : t('toast.archivedLocal', { provider: provider ?? '' }))
    go({ thread: null })
  })
  const toLead = () => start(async () => {
    const r = await threadToLead({ id: th.id })
    if (!r.ok) return fail(r.code, r.detail)
    flash(t('toast.lead'))
    router.push(recordHref('lead', r.leadId) as never)
  })
  const toggleLabel = (id: string) => start(async () => {
    const next = labelIds.includes(id) ? labelIds.filter((x) => x !== id) : [...labelIds, id]
    const r = await setThreadLabels({ id: th.id, version, labels: next })
    if (!r.ok) return fail(r.code, r.detail)
    setLabelIds(next)
    setVersion(version + 1)
  })

  const sub = [th.mailbox?.address, th.mailbox?.kind === 'team' ? t('teamInbox') : provider, t(`status.${th.status}`)].filter(Boolean).join(' · ')

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="min-w-0 flex-[1_1_300px]">
            <h2 className="m-0 font-serif text-20 font-semibold leading-[1.2]">{th.subject || t('noSubject')}</h2>
            <div className="mt-[3px] text-12 text-muted">{sub}</div>
          </div>
          <div className="flex flex-wrap gap-[6px]">
            {link ? (
              <Link
                href={recordHref(link.entity, link.id) as never}
                className="flex h-[30px] items-center gap-[6px] rounded-9 bg-highlight px-[10px] text-12 font-bold text-ink hover:text-ink hover:no-underline"
              >
                ◆ {link.title}
              </Link>
            ) : null}
            <button type="button" disabled={busy} onClick={archive} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default">
              {th.archived ? t('unarchive') : box && connected(box.status) ? t('archiveSync', { provider: provider ?? '' }) : t('archive')}
            </button>
            {canLead ? (
              <button type="button" disabled={busy} onClick={toLead} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default">
                {t('createLead')}
              </button>
            ) : null}
          </div>
        </div>
        {box && !connected(box.status) ? (
          <div className="rounded-10 bg-amber-bg px-3 py-2 text-12 leading-[1.5] text-amber-ink">
            <b>{t(`mailboxState.${box.status}`)}</b> {t('threadDisconnected', { address: box.address })}{' '}
            <Link href="/inbox?folder=settings" className="whitespace-nowrap font-bold text-amber-ink underline">{t('reconnectLink')}</Link>
          </div>
        ) : null}
        {labels.length ? (
          <div className="flex flex-wrap gap-[5px]">
            {labels.map((l) => {
              const on = labelIds.includes(l.id)
              return (
                <button
                  key={l.id}
                  type="button"
                  aria-pressed={on}
                  disabled={!canLabel || busy}
                  onClick={() => toggleLabel(l.id)}
                  className={`cursor-pointer rounded-999 border px-[9px] py-[3px] text-11 font-bold disabled:cursor-default ${on ? 'border-ink bg-highlight' : 'border-line-strong bg-transparent'}`}
                >
                  {l.name}
                </button>
              )
            })}
          </div>
        ) : null}
      </div>

      {insight ? (
        <div className="grid gap-[14px] rounded-20 bg-ink px-5 py-4 text-canvas [grid-template-columns:repeat(auto-fit,minmax(min(100%,200px),1fr))]">
          <div className="flex flex-col gap-[6px]">
            <AiTitle text={t('ai.summary')} />
            <span className="text-12.5 leading-[1.5] text-tile">{insight.summary}</span>
          </div>
          <div className="flex flex-col gap-[6px]">
            <b className="text-12.5">{t('ai.readiness')}</b>
            {insight.readiness !== null ? (
              <span className="flex items-baseline gap-[6px]">
                <span className="font-serif text-32 font-semibold text-primary">{insight.readiness}</span>
                <span className="text-12 text-tile">{t('ai.outOf', { sentiment: insight.sentiment ? t(`ai.sentiment.${insight.sentiment}`) : '—' })}</span>
              </span>
            ) : null}
            <span className="text-12 leading-[1.45] text-tile">{insight.reason}</span>
          </div>
          <div className="flex flex-col gap-[6px]">
            <b className="text-12.5">{t('ai.actions')}</b>
            {insight.action_items.map((a) => <span key={a} className="text-12 text-tile">○ {a}</span>)}
          </div>
        </div>
      ) : (
        // no Claude key is configured: the panel says so instead of showing a summary nobody generated
        <div className="flex flex-col gap-[6px] rounded-20 bg-ink px-5 py-4 text-canvas">
          <AiTitle text={t('ai.summary')} />
          <span className="text-12.5 leading-[1.5] text-tile"><b className="text-canvas">{t('ai.offTitle')}</b> {t('ai.offBody')}</span>
        </div>
      )}

      {th.messages.map((m) => <MessageCard key={m.id} m={m} when={when.long} />)}

      {insight && insight.suggested_replies.length ? (
        <div className="flex flex-wrap gap-[6px]">
          <span className="self-center text-12 text-muted">{t('ai.replies')}</span>
          {insight.suggested_replies.map((r) => (
            <button key={r} type="button" onClick={() => setBody(r)} className="cursor-pointer rounded-999 border border-line-strong bg-surface px-3 py-[6px] text-12">{r}</button>
          ))}
        </div>
      ) : null}

      <Composer mode="reply" thread={th} mailboxes={mailboxes} templates={templates} mergeFields={mergeFields} body={body} setBody={setBody} />
    </div>
  )
}

function AiTitle({ text }: { text: string }) {
  return (
    <span className="flex items-center gap-2">
      {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
      <img src="/brand/assistant.png" alt="" width={22} height={22} className="rounded-7 bg-canvas" />
      <b className="text-12.5">{text}</b>
    </span>
  )
}

/** One message: who to whom and when, the text, and — for a tracked email — what tracking recorded (COM-06). */
function MessageCard({ m, when }: { m: Message; when: (iso: string | null) => string }) {
  const t = useTranslations('inbox')
  const names = (xs: Message['to']) => xs.map((x) => x.name || x.address).join(', ')
  const tr = m.track
  const track = tr
    ? [
        tr.opens ? t('track.opened', { n: tr.opens }) : t('track.notOpened'),
        ...tr.clicks.map((c) => t('track.clicked', { label: c.label })),
        ...(tr.last_open ? [t('track.lastOpen', { when: when(tr.last_open).toLowerCase() })] : []),
      ].join(' · ')
    : null
  const state = m.direction === 'out' && m.state !== 'sent'
    ? m.state === 'scheduled' ? t('msgState.scheduled', { when: when(m.scheduled_at) }) : t(`msgState.${m.state === 'received' ? 'queued' : m.state}`)
    : null
  return (
    <div className="flex flex-col gap-2 rounded-18 border border-line bg-surface px-[18px] py-[14px]">
      <div className="flex justify-between gap-[10px] text-12 text-muted">
        <span><b className="text-ink">{m.from_name || m.from_addr}</b> → {names(m.to)}{m.cc.length ? ` · ${t('cc')} ${names(m.cc)}` : ''}</span>
        <span className="whitespace-nowrap">{when(m.at)}</span>
      </div>
      <div className="whitespace-pre-wrap text-13 leading-[1.6]">{m.body_text ?? ''}</div>
      {m.attachments.length ? (
        <div className="flex flex-wrap gap-[6px]">
          {m.attachments.map((a) => <span key={a.id} className="rounded-999 bg-tile px-[10px] py-1 text-12">▤ {a.filename}</span>)}
        </div>
      ) : null}
      {state ? <div className={`text-11.5 font-semibold ${m.state === 'failed' ? 'text-danger' : 'text-warn-ink'}`}>{state}{m.failure_code ? ` · ${m.failure_code}` : ''}</div> : null}
      {track ? (
        <div className="flex flex-wrap gap-x-[10px] text-11.5 font-semibold text-link">
          <span>{track}</span>
          <span className="font-normal text-faint">{t('track.caveat')}</span>
        </div>
      ) : null}
    </div>
  )
}
