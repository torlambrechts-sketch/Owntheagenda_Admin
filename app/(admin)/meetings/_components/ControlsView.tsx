'use client'

import { useCallback, useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Capabilities, Controls, UserRow } from '@/lib/data/meetings'
import { fetchControls, setMySettings, setRecordingSetting, setUser } from '../actions'
import type { Mine } from './MeetingsScreen'
import { btn32, card20, fieldInput, quiet, useFail } from './kit'

type Props = { canConfigure: boolean; capabilities: Capabilities; mine: Mine | null; onMineChanged: () => Promise<void> }

/** A mailbox that syncs (inbox.ts MAILBOX_STATUSES); «reauth» reads «(re-auth)», the rest «not connected». */
const live = (status: string) => ['synced', 'syncing', 'connecting'].includes(status)
const option = (on: boolean) => `flex cursor-pointer flex-col gap-[2px] rounded-13 border px-[13px] py-[11px] text-left disabled:cursor-default ${on ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`

/**
 * Workspace and controls (Meetings.dc.html, v.controls; MTG-08, spec §2.6). The per-user switch, the recording notice
 * and the audio's retention are global:configure's (meeting_controls); everyone keeps their own choices (my settings:
 * auto-join, brief instructions, the mailbox briefs read).
 */
export function ControlsView({ canConfigure, capabilities, mine, onMineChanged }: Props) {
  const t = useTranslations('meetings.controls')
  const fail = useFail()
  const [controls, setControls] = useState<Controls | null>(null)
  const load = useCallback(async () => {
    const r = await fetchControls()
    if (r.ok) setControls(r.controls); else fail(r)
  }, [fail])
  useEffect(() => { if (canConfigure) void load() }, [canConfigure, load])

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className="flex flex-col gap-[14px]">
        {canConfigure ? (
          controls ? <UsersCard users={controls.users} onChanged={load} /> : <div className={`${card20} px-[18px] py-4 text-13 text-muted`}>{t('loading')}</div>
        ) : (
          <div className={`${card20} flex flex-col gap-2 px-[18px] py-4`}>
            <b className="text-14">{t('adminOnly.title')}</b>
            <span className={quiet}>{t('adminOnly.body')}</span>
            <span className="text-12 leading-[1.5] text-muted">{t('firewall')}</span>
          </div>
        )}
        <MyCard mine={mine} onChanged={onMineChanged} />
      </div>
      {canConfigure && controls ? (
        <div className="flex flex-col gap-[14px]">
          <NoticeCard controls={controls} capabilities={capabilities} onChanged={load} />
          <RetentionCard controls={controls} onChanged={load} />
        </div>
      ) : null}
    </div>
  )
}

function UsersCard({ users, onChanged }: { users: UserRow[]; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.controls')
  const fail = useFail()
  const flash = useToast()
  const [busy, setBusy] = useState<string | null>(null)
  const toggle = async (u: UserRow) => {
    setBusy(u.id)
    const r = await setUser({ staff: u.id, values: { enabled: !u.enabled } })
    setBusy(null)
    if (!r.ok) { fail(r); return }
    flash(u.enabled ? t('userOff', { name: u.name }) : t('userOn', { name: u.name }))
    await onChanged()
  }
  const mailbox = (u: UserRow) => {
    if (!u.mailbox) return t('mailbox.none')
    const name = u.mailbox.own ? t('mailbox.own') : u.mailbox.address
    return u.mailbox.status === 'reauth' ? `${name} ${t('mailbox.reauth')}` : live(u.mailbox.status) ? name : `${name} ${t('mailbox.notConnected')}`
  }
  return (
    <div className={`${card20} overflow-hidden`}>
      <div className="flex flex-wrap justify-between gap-2 border-0 border-b border-solid border-line px-[18px] py-3">
        <b className="text-14">{t('users.title')}</b>
        <span className="text-12 text-muted">{t('users.hint')}</span>
      </div>
      {users.map((u) => (
        <div key={u.id} className="flex items-center justify-between gap-3 border-0 border-b border-solid border-line px-[18px] py-[10px] text-12.5">
          <span className="flex min-w-0 flex-col">
            <b>{u.name}</b>
            <span className="text-11.5 text-muted">{[u.title, t('mailbox.line', { mailbox: mailbox(u) })].filter(Boolean).join(' · ')}</span>
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={u.enabled}
            aria-label={t('users.switch', { name: u.name })}
            disabled={busy === u.id}
            onClick={() => void toggle(u)}
            className={`relative h-[22px] w-10 flex-none cursor-pointer rounded-999 border-none disabled:opacity-60 ${u.enabled ? 'bg-ink' : 'bg-line-strong'}`}
          >
            <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: u.enabled ? 21 : 3 }} />
          </button>
        </div>
      ))}
      {users.length === 0 ? <div className="px-[18px] py-[10px] text-12.5 text-muted">{t('users.none')}</div> : null}
    </div>
  )
}

function NoticeCard({ controls, capabilities, onChanged }: { controls: Controls; capabilities: Capabilities; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.controls')
  const fail = useFail()
  const flash = useToast()
  const [hours, setHours] = useState(String(controls.rec_notice.value === 'custom' ? (controls.rec_notice.hours ?? 48) : 48))
  const [busy, setBusy] = useState(false)
  const save = async (value: 'on_24h' | 'custom' | 'off') => {
    const n = value === 'custom' ? Number.parseInt(hours, 10) : null
    if (value === 'custom' && (n === null || Number.isNaN(n) || n < 0 || n > 168)) { fail({ code: 'invalid' }); return }
    setBusy(true)
    const r = await setRecordingSetting({ key: 'rec_notice', value, number: n })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('saved'))
    await onChanged()
  }
  const v = controls.rec_notice.value
  const retention = controls.rec_retention.value === 'keep' ? t('preview.keep') : t('preview.months', { n: controls.rec_retention.months ?? 12 })
  const timing = v === 'off' ? null : v === 'custom' ? ((controls.rec_notice.hours ?? 0) === 0 ? t('preview.whenKnown') : t('preview.hoursBefore', { n: controls.rec_notice.hours ?? 0 })) : t('preview.hoursBefore', { n: 24 })
  return (
    <div className={`${card20} flex flex-col gap-[10px] px-[18px] py-4`}>
      <b className="text-14">{t('notice.title')}</b>
      {(['on_24h', 'custom', 'off'] as const).map((k) => (
        <button key={k} type="button" disabled={busy} onClick={() => void save(k)} aria-pressed={v === k} className={option(v === k)}>
          <b className="text-13">{t(`notice.${k}.n`)}</b>
          <span className="text-11.5 text-muted">{k === 'custom' && v === 'custom' ? t('notice.custom.current', { n: controls.rec_notice.hours ?? 0 }) : t(`notice.${k}.s`)}</span>
        </button>
      ))}
      <label className="flex flex-wrap items-center gap-2 text-12 text-muted">
        {t('notice.hours')}
        <input type="number" min={0} max={168} value={hours} onChange={(e) => setHours(e.target.value)} className={`${fieldInput} h-8 w-20`} />
        <button type="button" disabled={busy} onClick={() => void save('custom')} className={btn32}>{t('notice.useCustom')}</button>
      </label>
      <div className="text-12 leading-[1.5] text-muted">{t('firewall')}</div>

      <div className="flex flex-col gap-[6px] rounded-13 border border-line bg-canvas px-[13px] py-[11px]">
        <span className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('preview.title')}</span>
        {v === 'off' ? (
          <span className="text-12.5 leading-[1.55]">{t('preview.off')}</span>
        ) : (
          <>
            <b className="text-12.5">{t('preview.subject')}</b>
            <span className="text-12.5 leading-[1.55]">{t('preview.body', { timing: timing ?? '', retention })}</span>
          </>
        )}
        <span className="text-11.5 leading-[1.5] text-amber-ink">
          {capabilities.email === 'connected' ? t('preview.emailConnected') : t('preview.emailNotConnected')}
        </span>
      </div>
    </div>
  )
}

/** rec_retention (0042): how long audio is kept; transcripts live with the meeting (D-41: the design has no place for it). */
function RetentionCard({ controls, onChanged }: { controls: Controls; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.controls.retention')
  const fail = useFail()
  const flash = useToast()
  const [months, setMonths] = useState(String(controls.rec_retention.value === 'custom' ? (controls.rec_retention.months ?? 6) : 6))
  const [busy, setBusy] = useState(false)
  const v = controls.rec_retention.value
  const save = async (value: '12_months' | 'custom' | 'keep') => {
    const n = value === 'custom' ? Number.parseInt(months, 10) : null
    if (value === 'custom' && (n === null || Number.isNaN(n) || n < 1 || n > 120)) { fail({ code: 'invalid' }); return }
    setBusy(true)
    const r = await setRecordingSetting({ key: 'rec_retention', value, number: n })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('saved'))
    await onChanged()
  }
  return (
    <div className={`${card20} flex flex-col gap-[10px] px-[18px] py-4`}>
      <b className="text-14">{t('title')}</b>
      {(['12_months', 'custom', 'keep'] as const).map((k) => (
        <button key={k} type="button" disabled={busy} onClick={() => void save(k)} aria-pressed={v === k} className={option(v === k)}>
          <b className="text-13">{t(`${k}.n`)}</b>
          <span className="text-11.5 text-muted">{k === 'custom' && v === 'custom' ? t('custom.current', { n: controls.rec_retention.months ?? 0 }) : t(`${k}.s`)}</span>
        </button>
      ))}
      <label className="flex flex-wrap items-center gap-2 text-12 text-muted">
        {t('months')}
        <input type="number" min={1} max={120} value={months} onChange={(e) => setMonths(e.target.value)} className={`${fieldInput} h-8 w-20`} />
        <button type="button" disabled={busy} onClick={() => void save('custom')} className={btn32}>{t('useCustom')}</button>
      </label>
      <span className="text-12 leading-[1.5] text-muted">{t('note')}</span>
    </div>
  )
}

/** My settings (D-41, spec §2.6 «others see only their own»): auto-join, brief instructions, the mailbox briefs read. */
function MyCard({ mine, onChanged }: { mine: Mine | null; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.controls.mine')
  const fail = useFail()
  const flash = useToast()
  const [instructions, setInstructions] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  if (!mine) return <div className={`${card20} px-[18px] py-4 text-13 text-muted`}>{t('loading')}</div>
  const s = mine.settings
  const text = instructions ?? s.brief_instructions ?? ''
  const save = async (values: Parameters<typeof setMySettings>[0]) => {
    setBusy(true)
    const r = await setMySettings(values)
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('saved'))
    setInstructions(null)
    await onChanged()
  }
  return (
    <div className={`${card20} flex flex-col gap-[10px] px-[18px] py-4`}>
      <b className="text-14">{t('title')}</b>
      <span className="text-12 text-muted">{t('autoJoin')}</span>
      {(['external', 'all', 'off'] as const).map((k) => (
        <button key={k} type="button" disabled={busy} onClick={() => void save({ bot_auto_join: k })} aria-pressed={s.bot_auto_join === k} className={option(s.bot_auto_join === k)}>
          <b className="text-13">{t(`autoJoinOption.${k}.n`)}</b>
          <span className="text-11.5 text-muted">{t(`autoJoinOption.${k}.s`)}</span>
        </button>
      ))}
      <label className="flex flex-col gap-[5px] text-12 text-muted">
        {t('mailbox')}
        <select
          disabled={busy}
          value={s.mailbox && !s.mailbox.own ? s.mailbox.id : ''}
          onChange={(e) => void save({ mailbox_id: e.target.value || null })}
          className={fieldInput}
        >
          <option value="">{t('mailboxOwn')}</option>
          {mine.mailboxes.map((m) => (
            <option key={m.id} value={m.id}>{m.address}{live(m.status) ? '' : ` · ${t.has(`status.${m.status}`) ? t(`status.${m.status}`) : m.status}`}</option>
          ))}
        </select>
      </label>
      <span className="text-11.5 leading-[1.5] text-muted">{s.mailbox ? (live(s.mailbox.status) ? t('mailboxConnected', { address: s.mailbox.address }) : t('mailboxNotConnected', { address: s.mailbox.address })) : t('mailboxNone')}</span>
      <label className="flex flex-col gap-[5px] text-12 text-muted">
        {t('instructions')}
        <textarea value={text} maxLength={2000} rows={4} onChange={(e) => setInstructions(e.target.value)} placeholder={t('instructionsPlaceholder')}
          className="rounded-10 border border-line bg-canvas px-3 py-2 font-sans text-13 text-ink" />
      </label>
      <span className="text-11.5 leading-[1.5] text-muted">{t('instructionsNote')}</span>
      <button type="button" disabled={busy || instructions === null} onClick={() => void save({ brief_instructions: text })} className={btn32}>{t('saveInstructions')}</button>
    </div>
  )
}
