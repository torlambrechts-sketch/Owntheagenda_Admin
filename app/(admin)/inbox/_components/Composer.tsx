'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { type Mailboxes, type Template, type Thread } from '@/lib/data/inbox'
import { SEND_AT, connected, isAddress, mentionsAttachment, mergeTokens, parseAddresses, replySubject, type SendAt } from '@/lib/data/inbox-shared'
import { mergeCheck, sendEmail } from '../actions'
import { providerKey, useFail, useGo } from './lib'
import { primaryLink } from './ThreadPane'

const sel = 'h-[30px] rounded-9 border border-line bg-surface text-12'

/**
 * The composer (Inbox.dc.html, the reply card), and the same card for a new email with To and Subject
 * (D-41: the design only has the reply). Sending goes through email_send; a mailbox that is not connected
 * cannot send, so the card says so and Send waits. The AI writer needs a Claude key, which is not
 * configured: its controls are shown disabled with that reason.
 */
export function Composer({ mode, thread, mailboxes, templates, mergeFields, body: outerBody, setBody: setOuterBody, ai }: {
  mode: 'reply' | 'new'
  thread: Thread | null
  mailboxes: Mailboxes
  templates: Template[]
  mergeFields: string[]
  body?: string
  setBody?: (s: string) => void
  ai: boolean
}) {
  const t = useTranslations('inbox')
  const flash = useToast()
  const { fail } = useFail()
  const { go } = useGo()
  const [busy, start] = useTransition()
  const [innerBody, setInnerBody] = useState('')
  const body = outerBody ?? innerBody
  const setBody = setOuterBody ?? setInnerBody

  const senders = mailboxes.mailboxes.filter((m) => m.can_reply)
  // my verified send-as addresses, offered under each of my own mailboxes (email_send from_alias_id)
  const aliases = mailboxes.aliases.filter((a) => a.kind === 'send_as' && a.verified_at)
  const [from, setFrom] = useState<string>(() => (thread?.mailbox && senders.some((m) => m.id === thread.mailbox!.id) ? thread.mailbox.id : senders[0]?.id ?? ''))
  const [fromMailbox, fromAlias] = from.split(':') as [string, string | undefined]
  const box = senders.find((m) => m.id === fromMailbox) ?? null
  const [toText, setToText] = useState('')
  const [subject, setSubject] = useState('')
  const [cc, setCc] = useState<string[]>([])
  const [templateId, setTemplateId] = useState<string | null>(null)
  const [track, setTrack] = useState(true)
  const [sendAt, setSendAt] = useState<SendAt>('now')
  const [missing, setMissing] = useState<{ missing: string[]; unknown: string[] }>({ missing: [], unknown: [] })

  // a reply goes to the contact who wrote last, or to whom we wrote when they have not answered yet
  const replyTo = useMemo(() => {
    if (!thread) return null
    const lastIn = [...thread.messages].reverse().find((m) => m.direction === 'in')
    if (lastIn) return { address: lastIn.from_addr, name: lastIn.from_name }
    const first = thread.messages.find((m) => m.direction === 'out')?.to[0]
    if (first) return first
    const p = thread.participants[0]
    return p ? { address: p.address, name: p.name } : null
  }, [thread])
  const link = thread ? primaryLink(thread) : null
  const ctxEntity = link && ['deal', 'lead', 'person', 'organization'].includes(link.entity) ? (link.entity as 'deal' | 'lead' | 'person' | 'organization') : null
  const recipientPerson = thread?.participants.find((p) => p.address === replyTo?.address.toLowerCase())?.person_id ?? null
  const finalSubject = mode === 'reply' ? replySubject(thread?.subject ?? '') : subject

  // merge fields without a value for this recipient are named before sending (COM-05); the database refuses them anyway
  useEffect(() => {
    if (!mergeTokens(`${finalSubject} ${body}`).length) { setMissing({ missing: [], unknown: [] }); return }
    const h = setTimeout(async () => {
      const r = await mergeCheck({ subject: finalSubject, body, entity: ctxEntity, recordId: link?.id ?? null, personId: recipientPerson, mailboxId: box?.id ?? null })
      if (r.ok) setMissing({ missing: r.missing, unknown: r.unknown })
    }, 400)
    return () => clearTimeout(h)
  }, [body, finalSubject, ctxEntity, link?.id, recipientPerson, box?.id])

  const applyTemplate = (id: string) => {
    const tpl = templates.find((x) => x.id === id)
    if (!tpl) return
    setTemplateId(tpl.id)
    setBody(tpl.body)
    if (mode === 'new' && !subject.trim()) setSubject(tpl.subject)
  }
  const tracking = mailboxes.tracking
  const canSend = !!box && connected(box.status)
  const typed = parseAddresses(toText)
  const badTo = typed.filter((a) => !isAddress(a))

  const send = () => {
    if (!body.trim() || !box) return
    const to = mode === 'reply' ? (replyTo ? [{ address: replyTo.address, name: replyTo.name ?? null }] : []) : typed.map((a) => ({ address: a, name: null }))
    if (mode === 'new' && (badTo.length || !to.length)) return fail('no_recipient')
    const ccs = (thread?.suggested ?? []).filter((s) => cc.includes(s.person_id)).map((s) => ({ address: s.email, name: s.name }))
    start(async () => {
      const r = await sendEmail({
        threadId: thread?.id ?? null, mailboxId: box.id, fromAliasId: fromAlias ?? null, to, cc: ccs, subject: finalSubject, body, templateId,
        track: tracking === 'per_email' ? track : null, sendAt, entity: ctxEntity, recordId: link?.id ?? null,
      })
      if (!r.ok) return fail(r.code, r.detail)
      setBody('')
      flash(r.state === 'scheduled' ? t('toast.scheduled', { when: t(`sendAt.${sendAt}`).toLowerCase() }) : link ? t('toast.queuedLinked', { title: link.title }) : t('toast.queued'))
      if (mode === 'new') go({ compose: null, thread: r.threadId })
    })
  }

  const notConnected = box && !connected(box.status)
  return (
    <div className="overflow-hidden rounded-18 border border-line bg-surface">
      <div className="flex flex-wrap items-center gap-2 border-b border-line bg-canvas px-3 py-[9px] text-12">
        <label className="flex items-center gap-[5px] text-muted">
          {t('composer.from')}
          <select value={from} onChange={(e) => setFrom(e.target.value)} className="h-7 rounded-8 border border-line bg-surface text-12 font-semibold text-ink">
            {senders.map((m) => [
              <option key={m.id} value={m.id}>{m.address} ({m.kind === 'team' ? t('composer.team') : t(`provider.${providerKey(m.provider)}`)})</option>,
              ...(m.mine ? aliases.map((a) => <option key={`${m.id}:${a.id}`} value={`${m.id}:${a.id}`}>{t('composer.alias', { address: a.address, via: m.address })}</option>) : []),
            ])}
            {senders.length === 0 ? <option value="">{t('composer.noMailbox')}</option> : null}
          </select>
        </label>
        {mode === 'reply' ? (
          <>
            <span className="text-muted">{t('composer.to')}</span>
            <b>{replyTo ? replyTo.name || replyTo.address : '—'}</b>
            {thread && thread.suggested.length ? (
              <>
                <span className="text-muted">{t('composer.suggested')}</span>
                {thread.suggested.map((s) => {
                  const on = cc.includes(s.person_id)
                  return (
                    <button
                      key={s.person_id}
                      type="button"
                      aria-pressed={on}
                      title={s.email}
                      onClick={() => setCc(on ? cc.filter((x) => x !== s.person_id) : [...cc, s.person_id])}
                      className={`cursor-pointer rounded-999 border border-dashed border-line-strong px-2 py-[2px] text-11.5 ${on ? 'bg-highlight' : 'bg-transparent'}`}
                    >
                      {on ? '✓' : '＋'} {s.name}
                    </button>
                  )
                })}
              </>
            ) : null}
          </>
        ) : (
          <label className="flex min-w-[200px] flex-1 items-center gap-[5px] text-muted">
            {t('composer.to')}
            <input
              value={toText}
              onChange={(e) => setToText(e.target.value)}
              placeholder={t('composer.toPlaceholder')}
              aria-invalid={badTo.length > 0}
              className={`h-7 min-w-0 flex-1 rounded-8 border bg-surface px-2 text-12 font-semibold text-ink ${badTo.length ? 'border-danger' : 'border-line'}`}
            />
          </label>
        )}
      </div>
      {mode === 'new' ? (
        <input
          value={subject}
          onChange={(e) => setSubject(e.target.value)}
          placeholder={t('composer.subject')}
          aria-label={t('composer.subject')}
          className="block w-full border-0 border-b border-line bg-transparent px-[14px] py-[10px] text-13 font-semibold outline-none"
        />
      ) : null}
      <div className="flex flex-wrap items-center gap-[6px] border-b border-line px-3 py-2">
        <select aria-label={t('composer.template')} value="" onChange={(e) => applyTemplate(e.target.value)} className={sel}>
          <option value="">{t('composer.template')}</option>
          {templates.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
        </select>
        <select aria-label={t('composer.merge')} value="" onChange={(e) => e.target.value && setBody(body + `[${e.target.value}]`)} className={sel}>
          <option value="">{t('composer.merge')}</option>
          {mergeFields.map((m) => <option key={m} value={m}>[{m}]</option>)}
        </select>
        <span className="flex-1" />
        <input
          disabled
          placeholder={ai ? t('composer.aiNoDraft') : t('composer.aiOff')}
          aria-label={ai ? t('composer.aiNoDraft') : t('composer.aiOff')}
          className="h-[30px] flex-[1_1_220px] rounded-9 border border-line bg-canvas px-[9px] text-12"
        />
        <select disabled aria-label={t('composer.tone')} className={sel} defaultValue="friendly">
          {['professional', 'formal', 'friendly'].map((k) => <option key={k} value={k}>{t(`composer.tones.${k}`)}</option>)}
        </select>
        <select disabled aria-label={t('composer.length')} className={sel} defaultValue="short">
          {['short', 'standard', 'long'].map((k) => <option key={k} value={k}>{t(`composer.lengths.${k}`)}</option>)}
        </select>
        <button type="button" disabled title={ai ? t('composer.aiNoDraft') : t('composer.aiOff')} className="h-[30px] cursor-default rounded-9 border border-ink bg-ink px-[11px] text-12 font-bold text-canvas opacity-50">
          {t('composer.draft')}
        </button>
      </div>
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder={mode === 'reply' ? t('composer.placeholder') : t('composer.placeholderNew')}
        aria-label={mode === 'reply' ? t('composer.placeholder') : t('composer.placeholderNew')}
        className="block min-h-[140px] w-full resize-y border-none bg-transparent px-[14px] py-3 text-13 leading-[1.6] outline-none"
      />
      {mentionsAttachment(body) ? (
        <div className="mx-3 mb-2 rounded-10 bg-amber-bg px-3 py-2 text-12 text-amber-ink"><b>{t('composer.attachTitle')}</b> {t('composer.attachBody')}</div>
      ) : null}
      {missing.missing.length || missing.unknown.length ? (
        <div className="mx-3 mb-2 rounded-10 bg-amber-bg px-3 py-2 text-12 text-amber-ink">
          <b>{t('composer.mergeTitle')}</b>{' '}
          {missing.missing.length ? t('composer.mergeMissing', { tokens: missing.missing.map((x) => `[${x}]`).join(', ') }) : null}{' '}
          {missing.unknown.length ? t('composer.mergeUnknown', { tokens: missing.unknown.map((x) => `[${x}]`).join(', ') }) : null}
        </div>
      ) : null}
      {notConnected ? (
        <div className="mx-3 mb-2 rounded-10 bg-amber-bg px-3 py-2 text-12 leading-[1.5] text-amber-ink">
          <b>{t(`mailboxState.${box.status}`)}</b> {t('composer.notConnected', { address: box.address })}{' '}
          <Link href="/inbox?folder=settings" className="whitespace-nowrap font-bold text-amber-ink underline">{t('reconnectLink')}</Link>
        </div>
      ) : null}
      {senders.length === 0 ? (
        <div className="mx-3 mb-2 rounded-10 bg-amber-bg px-3 py-2 text-12 text-amber-ink"><b>{t('composer.noMailbox')}</b> {t('composer.noMailboxBody')}</div>
      ) : null}
      <div className="flex flex-wrap items-center gap-2 border-t border-line px-3 py-2 text-12">
        <button type="button" disabled title={t('composer.attachOff')} className="h-[30px] cursor-default rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">
          {t('composer.attach')}
        </button>
        {tracking !== 'off' ? (
          <button
            type="button"
            aria-pressed={tracking === 'on' || track}
            disabled={tracking === 'on'}
            title={tracking === 'on' ? t('composer.trackFixed') : undefined}
            onClick={() => setTrack(!track)}
            className="flex h-[30px] cursor-pointer items-center gap-[6px] rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default"
          >
            <span className={`h-2 w-2 rounded-999 ${tracking === 'on' || track ? 'bg-ok' : 'bg-line-strong'}`} />
            {t('composer.track')}
          </button>
        ) : null}
        <span className="text-faint">{box?.signature ? t('composer.signature', { signature: box.signature }) : t('composer.noSignature')}</span>
        <span className="flex-1" />
        <select aria-label={t('composer.sendAtLabel')} value={sendAt} onChange={(e) => setSendAt(e.target.value as SendAt)} className="h-8 rounded-9 border border-line bg-surface text-12">
          {SEND_AT.map((k) => <option key={k} value={k}>{t(`sendAt.${k}`)}</option>)}
        </select>
        <button
          type="button"
          disabled={busy || !canSend || !body.trim()}
          title={canSend ? undefined : t('composer.sendOff')}
          onClick={send}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {sendAt === 'now' ? t('composer.send') : t('composer.schedule')}
        </button>
      </div>
    </div>
  )
}
