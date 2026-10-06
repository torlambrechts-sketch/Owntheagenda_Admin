'use client'

import { useState, useTransition } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { type Mailbox, type Mailboxes, type Template } from '@/lib/data/inbox'
import { addAlias, deleteTemplate, disconnectMailbox, removeAlias, saveTemplate, setMailboxMembers, updateMailbox } from '../actions'
import { connected } from '@/lib/data/inbox-shared'
import { providerKey, useFail } from './lib'

const card = 'flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4'
const small = 'h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:cursor-default'
const field = 'h-[30px] rounded-9 border border-line bg-canvas px-2 text-12'
const STATUS_TONE: Record<string, string> = { synced: 'text-link', syncing: 'text-warn-ink', connecting: 'text-warn-ink', reauth: 'text-danger', error: 'text-danger', disconnected: 'text-danger' }

/**
 * Mailboxes and templates (v.settings): the mailboxes and their state, the BCC drop-box, alternative sender
 * addresses, templates, and the mail client add-on. Connecting needs the Gmail or Microsoft OAuth client,
 * which is not configured, so «add» and «reconnect» say so; IMAP is outside D-07 and not offered.
 */
export function SetupView({ mailboxes, templates, mergeFields, dropbox, staff, canConfigure }: {
  mailboxes: Mailboxes
  templates: Template[]
  mergeFields: string[]
  dropbox: string
  staff: { id: string; name: string }[]
  canConfigure: boolean
}) {
  const t = useTranslations('inbox.setup')
  const ti = useTranslations('inbox')
  const flash = useToast()
  const { fail } = useFail()
  const [busy, start] = useTransition()
  const [adding, setAdding] = useState(false)
  const [editBox, setEditBox] = useState<string | null>(null)
  const [alias, setAlias] = useState('')
  const [aliasKind, setAliasKind] = useState<'send_as' | 'bcc_accepted'>('send_as')
  const [editTpl, setEditTpl] = useState<string | 'new' | null>(null)

  const run = (fn: () => Promise<{ ok: true } | { ok: false; code: string; detail?: string | null }>, ok: string, after?: () => void) => start(async () => {
    const r = await fn()
    if (!r.ok) return fail(r.code, r.detail)
    flash(ok)
    after?.()
  })

  const sub = (m: Mailbox) => m.kind === 'team'
    ? t('teamSub', { n: m.members.filter((x) => x.can_reply).length })
    : [ti(`provider.${providerKey(m.provider)}`), t('twoWay'), ...(m.signature ? [t('signatureSub', { signature: m.signature.split('\n')[0]! })] : [])].join(' · ')

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className={card}>
        <b className="text-14">{t('mailboxes')}</b>
        {mailboxes.mailboxes.map((m) => {
          const editable = m.mine === true || canConfigure
          return (
            <div key={m.id} className="flex flex-col gap-2 border-b border-line py-2 text-12.5">
              <div className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 flex-col"><b className="break-all">{m.address}</b><span className="text-11.5 text-muted">{sub(m)}</span></span>
                <span className={`whitespace-nowrap font-bold ${STATUS_TONE[m.status]}`}>{ti(`mailboxState.${m.status}`)}</span>
              </div>
              {!connected(m.status) ? <span className="text-11.5 text-muted">{t('reconnectNote', { provider: ti(`provider.${providerKey(m.provider)}`) })}</span> : null}
              <div className="flex flex-wrap gap-[6px]">
                {!connected(m.status) ? (
                  <button type="button" disabled title={t('oauthMissing')} className={`${small} opacity-50`}>{t('reconnect')}</button>
                ) : editable ? (
                  <button type="button" disabled={busy} onClick={() => run(() => disconnectMailbox({ id: m.id }), t('disconnected'))} className={small}>{t('disconnect')}</button>
                ) : null}
                {editable ? (
                  <button type="button" aria-expanded={editBox === m.id} onClick={() => setEditBox(editBox === m.id ? null : m.id)} className={small}>{t('edit')}</button>
                ) : null}
              </div>
              {editBox === m.id ? (
                <MailboxForm m={m} staff={staff} canMembers={canConfigure && m.kind === 'team'} busy={busy}
                  onSave={(v, members) => run(async () => {
                    const r = await updateMailbox({ id: m.id, values: v })
                    if (!r.ok || !members) return r
                    return setMailboxMembers({ id: m.id, members })
                  }, t('saved'), () => setEditBox(null))}
                />
              ) : null}
            </div>
          )
        })}
        {mailboxes.mailboxes.length === 0 ? <span className="text-12.5 text-muted">{t('noMailboxes')}</span> : null}
        <button type="button" aria-expanded={adding} onClick={() => setAdding(!adding)} className="h-[30px] cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[11px] text-12 font-semibold">
          {t('add')}
        </button>
        {adding ? <div className="rounded-10 bg-amber-bg px-3 py-2 text-12 leading-[1.5] text-amber-ink"><b>{t('addTitle')}</b> {t('addBody')}</div> : null}
      </div>

      <div className={card}>
        <b className="text-14">{t('dropbox')}</b>
        <span className="rounded-9 border border-line bg-canvas px-[10px] py-2 font-mono text-12.5">
          {dropbox}@<span className="font-sans text-12 text-warn-ink"> · {t('domainMissing')}</span>
        </span>
        <span className="text-12 text-muted">{t('dropboxBody')}</span>
        <b className="mt-1 text-12.5">{t('aliases')}</b>
        {mailboxes.aliases.map((a) => (
          <span key={a.id} className="flex items-center gap-2 text-12.5">
            <span className="min-w-0 break-all">{a.address}</span>
            <span className="text-11.5 text-muted">{t(`aliasKind.${a.kind}`)}{a.verified_at ? '' : ` · ${t('unverified')}`}</span>
            <button type="button" aria-label={t('removeAlias', { address: a.address })} disabled={busy} onClick={() => run(() => removeAlias({ id: a.id }), t('aliasRemoved'))} className="cursor-pointer border-none bg-transparent text-14 text-muted">×</button>
          </span>
        ))}
        {mailboxes.aliases.length === 0 ? <span className="text-12.5 text-muted">{t('noAliases')}</span> : null}
        <div className="flex flex-wrap gap-[6px]">
          <input aria-label={t('aliasAddress')} placeholder={t('aliasAddress')} value={alias} onChange={(e) => setAlias(e.target.value)} className={`${field} min-w-0 flex-[1_1_160px]`} />
          <select aria-label={t('aliasKindLabel')} value={aliasKind} onChange={(e) => setAliasKind(e.target.value as 'send_as' | 'bcc_accepted')} className={field}>
            <option value="send_as">{t('aliasKind.send_as')}</option>
            <option value="bcc_accepted">{t('aliasKind.bcc_accepted')}</option>
          </select>
          <button type="button" disabled={busy || !alias.trim()} onClick={() => run(() => addAlias({ address: alias, kind: aliasKind }), t('aliasAdded'), () => setAlias(''))} className={small}>{t('addAlias')}</button>
        </div>
      </div>

      <div className="flex flex-col gap-[6px] rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('templates')}</b>
        {templates.map((x) => {
          const editable = x.mine === true || canConfigure
          return (
            <div key={x.id} className="flex flex-col border-b border-line py-[6px] text-12.5">
              <div className="flex justify-between gap-2">
                {editable ? (
                  <button type="button" aria-expanded={editTpl === x.id} onClick={() => setEditTpl(editTpl === x.id ? null : x.id)} className="cursor-pointer border-none bg-transparent p-0 text-left text-12.5 font-bold">{x.name}</button>
                ) : <b>{x.name}</b>}
                <span className="whitespace-nowrap text-muted">{t(x.scope === 'shared' ? (x.is_starter ? 'scope.starter' : 'scope.shared') : 'scope.private')}</span>
              </div>
              {editTpl === x.id ? (
                <TemplateForm tpl={x} mergeFields={mergeFields} busy={busy}
                  onSave={(v) => run(() => saveTemplate({ id: x.id, values: v }), t('templateSaved'), () => setEditTpl(null))}
                  onDelete={() => run(() => deleteTemplate({ id: x.id }), t('templateDeleted'), () => setEditTpl(null))}
                  onCancel={() => setEditTpl(null)}
                />
              ) : null}
            </div>
          )
        })}
        {editTpl === 'new' ? (
          <TemplateForm tpl={null} mergeFields={mergeFields} busy={busy}
            onSave={(v) => run(() => saveTemplate({ id: null, values: v }), t('templateSaved'), () => setEditTpl(null))}
            onCancel={() => setEditTpl(null)}
          />
        ) : (
          <button type="button" onClick={() => setEditTpl('new')} className="mt-1 h-[30px] cursor-pointer self-start rounded-9 border border-dashed border-line-strong bg-transparent px-[11px] text-12 font-semibold">{t('newTemplate')}</button>
        )}
      </div>

      <div className={card}>
        <b className="text-14">{t('addons')}</b>
        <div className="text-12.5 leading-[1.5]">{t('addonsBody')} <b>{t('addonsState')}</b></div>
        <span className="text-12 text-muted">
          {t.rich('tracking', { mode: ti(`setup.trackingMode.${mailboxes.tracking}`), b: (c) => <b>{c}</b> })}
        </span>
        <span className="text-11.5 text-faint">{ti('track.caveatLong')}</span>
      </div>
    </div>
  )
}

function MailboxForm({ m, staff, canMembers, busy, onSave }: {
  m: Mailbox
  staff: { id: string; name: string }[]
  canMembers: boolean
  busy: boolean
  onSave: (v: { display_name: string; signature: string; default_visibility: 'private' | 'shared' }, members: { staff_id: string; can_reply: boolean }[] | null) => void
}) {
  const t = useTranslations('inbox.setup')
  const [name, setName] = useState(m.display_name ?? '')
  const [signature, setSignature] = useState(m.signature ?? '')
  const [vis, setVis] = useState(m.default_visibility)
  const [members, setMembers] = useState(() => new Map(m.members.map((x) => [x.staff_id, x.can_reply])))
  return (
    <div className="flex flex-col gap-2 rounded-12 border border-line bg-canvas p-3 text-12">
      <label className="flex flex-col gap-1 text-muted">{t('displayName')}<input value={name} onChange={(e) => setName(e.target.value)} className={`${field} bg-surface text-ink`} /></label>
      <label className="flex flex-col gap-1 text-muted">{t('signature')}<textarea value={signature} onChange={(e) => setSignature(e.target.value)} className="min-h-[60px] rounded-9 border border-line bg-surface px-2 py-[6px] text-12 text-ink" /></label>
      <label className="flex flex-col gap-1 text-muted">
        {t('visibility')}
        <select value={vis} onChange={(e) => setVis(e.target.value as 'private' | 'shared')} className={`${field} bg-surface text-ink`}>
          <option value="private">{t('vis.private')}</option>
          <option value="shared">{t('vis.shared')}</option>
        </select>
      </label>
      {canMembers ? (
        <fieldset className="m-0 flex flex-col gap-1 border-none p-0">
          <legend className="mb-1 p-0 text-muted">{t('members')}</legend>
          {staff.map((s) => {
            const on = members.has(s.id)
            return (
              <span key={s.id} className="flex items-center gap-2">
                <label className="flex flex-1 items-center gap-[6px]">
                  <input type="checkbox" checked={on} onChange={() => { const n = new Map(members); if (on) n.delete(s.id); else n.set(s.id, true); setMembers(n) }} />
                  {s.name}
                </label>
                {on ? (
                  <label className="flex items-center gap-1 text-muted">
                    <input type="checkbox" checked={members.get(s.id) ?? true} onChange={(e) => { const n = new Map(members); n.set(s.id, e.target.checked); setMembers(n) }} />
                    {t('canReply')}
                  </label>
                ) : null}
              </span>
            )
          })}
        </fieldset>
      ) : null}
      <button type="button" disabled={busy} onClick={() => onSave({ display_name: name, signature, default_visibility: vis }, canMembers ? [...members].map(([staff_id, can_reply]) => ({ staff_id, can_reply })) : null)} className="h-[30px] cursor-pointer self-start rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold">{t('save')}</button>
    </div>
  )
}

function TemplateForm({ tpl, mergeFields, busy, onSave, onDelete, onCancel }: {
  tpl: Template | null
  mergeFields: string[]
  busy: boolean
  onSave: (v: { name: string; scope: 'private' | 'shared'; subject: string; body: string }) => void
  onDelete?: () => void
  onCancel: () => void
}) {
  const t = useTranslations('inbox.setup')
  const ti = useTranslations('inbox')
  const [name, setName] = useState(tpl?.name ?? '')
  const [scope, setScope] = useState<'private' | 'shared'>(tpl?.scope ?? 'private')
  const [subject, setSubject] = useState(tpl?.subject ?? '')
  const [body, setBody] = useState(tpl?.body ?? '')
  return (
    <div className="mt-[6px] flex flex-col gap-2 rounded-12 border border-line bg-canvas p-3 text-12">
      <div className="flex flex-wrap gap-[6px]">
        <input aria-label={t('templateName')} placeholder={t('templateName')} value={name} onChange={(e) => setName(e.target.value)} className={`${field} min-w-0 flex-[1_1_160px] bg-surface`} />
        <select aria-label={t('scopeLabel')} value={scope} onChange={(e) => setScope(e.target.value as 'private' | 'shared')} className={`${field} bg-surface`}>
          <option value="private">{t('scope.private')}</option>
          <option value="shared">{t('scope.shared')}</option>
        </select>
      </div>
      <input aria-label={ti('composer.subject')} placeholder={ti('composer.subject')} value={subject} onChange={(e) => setSubject(e.target.value)} className={`${field} bg-surface`} />
      <select aria-label={ti('composer.merge')} value="" onChange={(e) => e.target.value && setBody(body + `[${e.target.value}]`)} className={`${field} self-start bg-surface`}>
        <option value="">{ti('composer.merge')}</option>
        {mergeFields.map((m) => <option key={m} value={m}>[{m}]</option>)}
      </select>
      <textarea aria-label={t('templateBody')} placeholder={t('templateBody')} value={body} onChange={(e) => setBody(e.target.value)} className="min-h-[110px] rounded-9 border border-line bg-surface px-2 py-[6px] text-12 leading-[1.5]" />
      <div className="flex flex-wrap gap-[6px]">
        <button type="button" disabled={busy || !name.trim()} onClick={() => onSave({ name, scope, subject, body })} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold disabled:cursor-default">{t('save')}</button>
        <button type="button" onClick={onCancel} className={small}>{t('cancel')}</button>
        <span className="flex-1" />
        {onDelete ? <button type="button" disabled={busy} onClick={onDelete} className={`${small} text-danger`}>{t('delete')}</button> : null}
      </div>
    </div>
  )
}
