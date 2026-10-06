'use client'

import { useEffect, useState, useTransition } from 'react'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import type { Channel, Scheduling } from '@/lib/data/activities'
import { useToast } from '@/components/ui/Toast'
import { saveCalendar, setReminderPrefs } from '../actions'
import type { Ctx } from './shared'

const CHANNELS: Channel[] = ['app', 'email', 'desktop', 'push']
const TIMINGS = [15, 60, 1440]
type Permission = 'granted' | 'denied' | 'default' | 'unsupported' | null

export function RemindersTab({ ctx, scheduling }: { ctx: Ctx; scheduling: Scheduling }) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const format = useFormatter()
  const now = useNow()
  const flash = useToast()
  const [, startTransition] = useTransition()
  const [channels, setChannels] = useState<Channel[]>(scheduling.prefs.channels)
  const [offset, setOffset] = useState(scheduling.prefs.default_offset)
  const [permission, setPermission] = useState<Permission>(null)
  useEffect(() => setPermission(typeof Notification === 'undefined' ? 'unsupported' : Notification.permission), [])
  const stored = scheduling.calendar
  const connected = stored?.status === 'connected'
  // the choice is stored before any provider is connected (calendar_connection_save); the status stays not connected
  type Choice = { provider: 'google' | 'microsoft' | null; mode: 'one_way' | 'two_way'; calendar_id: string | null; sync_type_ids: string[] }
  const [cal, setCal] = useState<Choice>({
    provider: stored?.provider ?? null, mode: stored?.mode ?? 'two_way', calendar_id: stored?.calendar_id ?? null, sync_type_ids: stored?.sync_type_ids ?? [],
  })
  const chosen = cal.provider !== null
  const saveCal = (patch: Partial<Choice>) => {
    const before = cal
    setCal({ ...cal, ...patch })
    startTransition(async () => {
      const r = await saveCalendar({ ...patch, provider: patch.provider ?? cal.provider ?? undefined })
      if (!r.ok) { setCal(before); flash(tc(`errors.${r.code}`)) }
    })
  }
  const ownCalendar = scheduling.email ?? ctx.me.email

  const save = (patch: { channels?: Channel[]; default_offset?: number }, undo: () => void) => {
    startTransition(async () => {
      const r = await setReminderPrefs(patch)
      if (!r.ok) { undo(); flash(tc(`errors.${r.code}`)) }
    })
  }
  const toggle = (c: Channel) => {
    const before = channels
    const next = channels.includes(c) ? channels.filter((x) => x !== c) : [...channels, c]
    setChannels(next)
    save({ channels: next }, () => setChannels(before))
  }
  const sub: Record<Channel, string> = {
    app: t('reminders.sub.app'),
    email: t('reminders.sub.email', { email: scheduling.email ?? ctx.me.email }),
    desktop: permission ? t(`reminders.sub.desktop.${permission}`) : '',
    push: t('reminders.sub.push'),
  }
  const timings = TIMINGS.includes(offset) ? TIMINGS : [...TIMINGS, offset].sort((a, b) => a - b)
  const timingLabel = (m: number) => (m % 1440 === 0 ? t('reminders.daysBefore', { count: m / 1440 }) : m % 60 === 0 ? t('reminders.hoursBefore', { count: m / 60 }) : t('reminders.minutesBefore', { count: m }))

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-[18px]">
        <b className="text-15">{t('reminders.title')}</b>
        <span className="text-12 text-muted">{t('reminders.hint')}</span>
        {CHANNELS.map((c) => {
          const on = channels.includes(c)
          // no device is registered for push until the mobile app exists (D-38)
          const disabled = c === 'push' && !on
          return (
            <div key={c} className="flex items-center justify-between border-b border-line py-2">
              <span className="flex flex-col">
                <b className="text-13">{t(`reminders.channel.${c}`)}</b>
                <span className="text-11.5 text-muted">{sub[c]}</span>
              </span>
              <button
                type="button"
                role="switch"
                aria-checked={on}
                aria-label={t(`reminders.channel.${c}`)}
                disabled={disabled}
                onClick={() => toggle(c)}
                className={`relative h-[22px] w-10 cursor-pointer rounded-999 border-none disabled:cursor-default ${on ? 'bg-ink' : 'bg-line-strong'}`}
              >
                <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: on ? 21 : 3 }} />
              </button>
            </div>
          )
        })}
        <label className="flex items-center justify-between text-12.5">
          {t('reminders.defaultTiming')}
          <select
            value={offset}
            onChange={(e) => { const before = offset; const v = Number(e.target.value); setOffset(v); save({ default_offset: v }, () => setOffset(before)) }}
            className="h-8 rounded-9 border border-line bg-canvas text-12.5"
          >
            {timings.map((m) => <option key={m} value={m}>{timingLabel(m)}</option>)}
          </select>
        </label>
      </div>

      <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-5 py-[18px]">
        <b className="text-15">{t('sync.title')}</b>
        <div className="flex gap-2">
          {(['google', 'microsoft'] as const).map((p) => {
            const on = cal.provider === p
            return (
              <button
                key={p}
                type="button"
                aria-pressed={on}
                onClick={() => { if (!on) saveCal({ provider: p }) }}
                className={`h-10 flex-1 cursor-pointer rounded-11 border text-12.5 ${on ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-medium'}`}
              >
                {t(`sync.provider.${p}`)}
              </button>
            )
          })}
        </div>
        <div className="flex rounded-10 bg-tile p-[3px]" title={chosen ? undefined : t('sync.chooseProvider')}>
          {(['one_way', 'two_way'] as const).map((m) => {
            const on = chosen && cal.mode === m
            return (
              <button key={m} type="button" aria-pressed={on} disabled={!chosen} onClick={() => { if (!on) saveCal({ mode: m }) }} className={`flex-1 cursor-pointer rounded-7 border-none p-[7px] text-12.5 disabled:cursor-default ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
                {t(`sync.mode.${m}`)}
              </button>
            )
          })}
        </div>
        <label className="flex items-center justify-between text-12.5">
          {t('sync.calendar')}
          <select
            disabled={!chosen}
            value={cal.calendar_id ?? ''}
            onChange={(e) => saveCal({ calendar_id: e.target.value || null })}
            className="h-8 rounded-9 border border-line bg-canvas text-12.5"
          >
            <option value="">—</option>
            <option value={ownCalendar}>{ownCalendar}</option>
            {cal.calendar_id && cal.calendar_id !== ownCalendar ? <option value={cal.calendar_id}>{cal.calendar_id}</option> : null}
          </select>
        </label>
        <div className="text-12 font-bold text-muted">{t('sync.types')}</div>
        <div className="flex flex-wrap gap-[6px]">
          {ctx.types.filter((x) => x.active).map((x) => {
            const on = cal.sync_type_ids.includes(x.id)
            return (
              <button
                key={x.id}
                type="button"
                aria-pressed={on}
                disabled={!chosen}
                onClick={() => saveCal({ sync_type_ids: on ? cal.sync_type_ids.filter((y) => y !== x.id) : [...cal.sync_type_ids, x.id] })}
                className={`cursor-pointer rounded-999 border px-[11px] py-[5px] text-12 disabled:cursor-default ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
              >
                {x.glyph} {x.name}
              </button>
            )
          })}
        </div>
        <div className="border-t border-line pt-2 text-12 text-muted">
          {connected
            ? t('sync.connected', { when: stored?.last_synced_at ? format.relativeTime(new Date(stored.last_synced_at), now) : '—' })
            : t('sync.notConnected')}
        </div>
      </div>
    </div>
  )
}
