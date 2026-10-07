'use client'

import { useRef, useState, type ReactNode } from 'react'
import Link from 'next/link'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { formatNumber, money, percent, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import {
  CALL_OUTCOMES, CONTACT_RULES, type CallOutcome, type Captures, type Coords, type DealPreview, type Focus, type NearbyRow, type NotificationItem,
} from '@/lib/data/mobile-shared'
import { acceptFor, RECORD_TYPES } from '@/lib/storage/mime'
import { Btn, BtnLink, Btns, Card, Phone, fieldCls, fieldLabel, type Tone } from './kit'

/** What every phone frame shares: orientation, the status bar, the offline banner, the tab bar. */
export type Frame = { land: boolean; time: string; net: string; banner: ReactNode; tabs: { g: string; n: string; on: boolean }[] }

const short = (title: string, org: string | null) => (org && title.startsWith(`${org} — `) ? title.slice(org.length + 3) : title)
const km = (n: number, nf: NumberFormat) => `${formatNumber(n, nf, n < 10 ? 1 : 0)} km`

// ---------------------------------------------------------------------------
// Focus (MOB-02): the counts use the web lists' own filters (mobile_focus); the drive time needs a routing provider, so a
// straight-line distance is shown once the device's position was shared; the home-screen widget is not possible in a PWA
export function FocusPhone({ frame, focus, nf, located }: { frame: Frame; focus: Focus; nf: NumberFormat; located: boolean }) {
  const t = useTranslations('mobile')
  const format = useFormatter()
  const part = focus.hour >= 5 && focus.hour < 12 ? 'morning' : focus.hour >= 12 && focus.hour < 18 ? 'afternoon' : 'evening'
  const first = focus.name.split(/\s+/)[0] ?? focus.name
  const overdue = focus.overdue_activities + (focus.deals_past_close ?? 0)
  const hm = (iso: string | null) => (iso ? format.dateTime(new Date(iso), { hour: '2-digit', minute: '2-digit' }) : '')
  const week = focus.closing_this_week
  return (
    <Phone {...frame} title={t('focus.greeting.' + part, { name: first })} label={t('phones.focus.label')} ids={t('phones.focus.ids')}>
      <Card tone="dark" eyebrow={t('focus.overdue')} big={String(overdue)}
        s={overdue === 0 ? t('focus.nothingOverdue')
          : focus.deals_past_close === null ? t('focus.overdueActivities', { a: focus.overdue_activities })
          : t('focus.overdueBoth', { a: focus.overdue_activities, d: focus.deals_past_close })} />
      {focus.today.length === 0 ? <Card eyebrow={t('focus.today')} t={t('focus.nothingToday')} /> : null}
      {focus.today.map((a, i) => (
        <Card key={a.id} eyebrow={i === 0 ? t('focus.today') : undefined}
          t={`${hm(a.starts_at)} ${a.subject}`}
          s={[a.organization, a.deal ? short(a.deal, a.organization) : null, a.km !== null ? km(a.km, nf) : null].filter(Boolean).join(' · ') || undefined} />
      ))}
      <Card eyebrow={located ? t('focus.unreadNearbyEyebrow') : t('focus.unreadEyebrow')}
        t={located && focus.nearby_10km !== null ? t('focus.unreadNearby', { n: focus.unread_threads, near: focus.nearby_10km }) : t('focus.unread', { n: focus.unread_threads })}
        s={week ? [t('focus.closing', { count: week.count, value: money(week.value_nok, nf) }), week.excluded_currency ? t('focus.excluded', { n: week.excluded_currency }) : null].filter(Boolean).join(' · ') : undefined} />
    </Phone>
  )
}

// ---------------------------------------------------------------------------
// Nearby (MOB-03): organisations around a position the user sent (located or typed), from record_geo. The map has no tiles
// (no provider) and nearby() returns distances, not positions, so no pin is drawn where its place is not known
export function NearbyPhone({ frame, nf, coords, geo, rows, failed, offline, canCheckIn, onLocate, onManual, onForget, onCheckIn }: {
  frame: Frame; nf: NumberFormat; coords: Coords | null; geo: 'idle' | 'asking' | 'denied' | 'blocked' | 'unavailable'; rows: NearbyRow[] | null; failed: boolean; offline: boolean
  canCheckIn: boolean; onLocate: () => void; onManual: (c: Coords) => void; onForget: () => void; onCheckIn: (r: NearbyRow) => void
}) {
  const t = useTranslations('mobile')
  const format = useFormatter()
  const [typed, setTyped] = useState({ lat: '', lng: '' })
  const [typing, setTyping] = useState(false)
  const lat = Number(typed.lat.replace(',', '.'))
  const lng = Number(typed.lng.replace(',', '.'))
  const typedOk = typed.lat !== '' && typed.lng !== '' && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
  const sub = (r: NearbyRow) => r.deal
    ? t('nearby.deal', { deal: short(r.deal.title, r.title), stage: r.deal.stage ?? '—' })
    : [r.customer ? t('nearby.customer') : null, r.health !== null ? t('nearby.health', { n: r.health }) : null,
       r.last_visit_at ? t('nearby.lastVisit', { date: format.dateTime(new Date(r.last_visit_at), { day: 'numeric', month: 'short' }) }) : t('nearby.noVisit')].filter(Boolean).join(' · ')
  const shown = (rows ?? []).slice(0, 6)
  return (
    <Phone {...frame} title={t('nearby.title')} label={t('phones.nearby.label')} ids={t('phones.nearby.ids')}>
      <Card pad="p-[6px]">
        <div className="relative h-[190px] rounded-12 bg-[repeating-linear-gradient(135deg,#F2EAD6_0_8px,#FCF6E9_8px_16px)]">
          {coords ? (
            <>
              <span className="absolute left-[46%] top-[52%] h-[18px] w-[18px] rounded-999 border-[3px] border-solid border-surface bg-link" aria-hidden />
              <span className="absolute bottom-2 left-2 right-2 flex flex-wrap items-center justify-between gap-1 text-10.5 font-bold">
                <span className="rounded-999 bg-surface px-2 py-[3px]">{t('nearby.noTiles')}</span>
                <button type="button" onClick={onForget} className="cursor-pointer rounded-999 border border-solid border-line bg-surface px-2 py-[3px] text-10.5 font-bold">{t('nearby.forget')}</button>
              </span>
            </>
          ) : (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 p-4 text-center">
              {typing ? (
                <form className="flex w-full flex-col gap-[6px] rounded-12 bg-surface p-[10px] text-left" onSubmit={(e) => { e.preventDefault(); if (typedOk) onManual({ lat, lng }) }}>
                  <div className="flex gap-[6px]">
                    <label className={`${fieldLabel} flex-1`}>{t('nearby.lat')}<input className={fieldCls} inputMode="decimal" value={typed.lat} onChange={(e) => setTyped({ ...typed, lat: e.target.value })} /></label>
                    <label className={`${fieldLabel} flex-1`}>{t('nearby.lng')}<input className={fieldCls} inputMode="decimal" value={typed.lng} onChange={(e) => setTyped({ ...typed, lng: e.target.value })} /></label>
                  </div>
                  <Btns><Btn type="submit" primary disabled={!typedOk}>{t('nearby.search')}</Btn></Btns>
                </form>
              ) : (
                <>
                  <div className="flex"><Btn primary onClick={onLocate} disabled={geo === 'asking'}>{geo === 'asking' ? t('nearby.asking') : t('nearby.locate')}</Btn></div>
                  <span className="max-w-[230px] rounded-10 bg-surface px-2 py-1 text-11 leading-[1.4]">
                    {geo === 'denied' ? t('nearby.denied') : geo === 'blocked' ? t('nearby.blocked') : geo === 'unavailable' ? t('nearby.unavailable') : t('nearby.why')}
                  </span>
                  <button type="button" onClick={() => setTyping(true)} className="cursor-pointer border-none bg-transparent p-0 text-11 font-bold text-link underline">{t('nearby.type')}</button>
                </>
              )}
            </div>
          )}
        </div>
      </Card>
      {coords && failed ? <Card t={t('nearby.failed')} /> : null}
      {coords && rows && rows.length === 0 ? <Card t={t('nearby.none')} s={t('nearby.noneBody')} /> : null}
      {shown.map((r, i) => (
        <Card key={r.id}
          t={<Link href={recordHref(r.entity, r.id) as never} className="text-ink hover:text-ink">{`${r.title} · ${km(r.km, nf)}`}</Link>}
          s={sub(r)}>
          {i === 0 ? (
            <Btns>
              <BtnLink href={`geo:0,0?q=${encodeURIComponent([r.title, r.city].filter(Boolean).join(', '))}`}>{t('nearby.navigate')}</BtnLink>
              <Btn primary onClick={() => onCheckIn(r)} disabled={offline && !canCheckIn}>{t('nearby.checkIn')}</Btn>
            </Btns>
          ) : null}
        </Card>
      ))}
    </Phone>
  )
}

// ---------------------------------------------------------------------------
// Deal on the go (MOB-01, MOB-04, MOB-05): the deal, the person with tel:/sms: hand-offs and the call prompt, the next stage
// with what it requires, the latest note
export function DealPhone({ frame, deal, nf, offline, movePending, canCallOffline, missing, onMove, onCall }: {
  frame: Frame; deal: DealPreview | null; nf: NumberFormat; offline: boolean; movePending: boolean; canCallOffline: boolean; missing: string[] | null
  onMove: (stage: { id: string; name: string }) => void; onCall: (v: { outcome: CallOutcome; minutes: number }) => Promise<boolean>
}) {
  const t = useTranslations('mobile')
  const format = useFormatter()
  const [prompt, setPrompt] = useState(false)
  const [call, setCall] = useState<{ outcome: CallOutcome; minutes: string }>({ outcome: 'connected', minutes: '' })
  if (!deal) {
    return (
      <Phone {...frame} title={t('deal.empty.title')} label={t('phones.deal.label')} ids={t('phones.deal.ids')}>
        <Card t={t('deal.empty.t')} s={t('deal.empty.s')} />
      </Phone>
    )
  }
  const at = deal.stages.findIndex((s) => s.id === deal.stage_id)
  const current = deal.stages[at]
  const next = at >= 0 ? deal.stages[at + 1] : undefined
  const close = deal.expected_close_date ? format.dateTime(new Date(`${deal.expected_close_date}T12:00:00Z`), { day: 'numeric', month: 'short', timeZone: 'UTC' }) : null
  const minutes = Number(call.minutes)
  const minutesOk = call.minutes !== '' && Number.isInteger(minutes) && minutes >= 0 && minutes <= 600
  const tel = deal.person?.phone ? deal.person.phone.replace(/[^\d+]/g, '') : null
  return (
    <Phone {...frame} title={deal.organization ?? deal.title} label={t('phones.deal.label')} ids={t('phones.deal.ids')}>
      <Card eyebrow={<Link href={recordHref('deal', deal.id) as never} className="text-ink hover:text-ink">{short(deal.title, deal.organization)}</Link>} big={money(deal.value, nf, deal.currency)}
        s={[current?.name, deal.score !== null ? t('deal.score', { n: deal.score }) : null, close ? t('deal.close', { date: close }) : null].filter(Boolean).join(' · ')} />
      {deal.person ? (
        <Card t={deal.person.name} s={[deal.person.title, deal.person.phone].filter(Boolean).join(' · ') || undefined}>
          {tel ? (
            <Btns>
              <BtnLink primary href={`tel:${tel}`} onClick={() => setPrompt(true)}>{t('deal.call')}</BtnLink>
              <BtnLink href={`sms:${tel}`}>{t('deal.text')}</BtnLink>
            </Btns>
          ) : <span className="text-11.5 opacity-80">{t('deal.noPhone')}</span>}
          {prompt ? (
            <form className="flex flex-col gap-[6px] border-t border-solid border-line pt-2" onSubmit={async (e) => {
              e.preventDefault()
              if (!minutesOk) return
              if (await onCall({ outcome: call.outcome, minutes })) { setPrompt(false); setCall({ outcome: 'connected', minutes: '' }) }
            }}>
              <b className="text-12">{t('deal.prompt')}</b>
              <div className="flex gap-[6px]">
                <label className={`${fieldLabel} flex-[2]`}>{t('deal.outcome')}
                  <select className={fieldCls} value={call.outcome} onChange={(e) => setCall({ ...call, outcome: e.target.value as CallOutcome })}>
                    {CALL_OUTCOMES.map((o) => <option key={o} value={o}>{t(`deal.outcomes.${o}`)}</option>)}
                  </select>
                </label>
                <label className={`${fieldLabel} flex-1`}>{t('deal.minutes')}
                  <input className={fieldCls} inputMode="numeric" value={call.minutes} onChange={(e) => setCall({ ...call, minutes: e.target.value })} />
                </label>
              </div>
              {offline && !canCallOffline ? <span className="text-11.5 opacity-80">{t('needsConnection')}</span> : null}
              <Btns>
                <Btn type="submit" primary disabled={!minutesOk || (offline && !canCallOffline)}>{t('deal.logCall')}</Btn>
                <Btn onClick={() => setPrompt(false)}>{t('cancel')}</Btn>
              </Btns>
            </form>
          ) : null}
        </Card>
      ) : null}
      {next ? (
        <Card t={t('deal.moveTo', { stage: next.name })}
          s={movePending ? t('deal.movePending') : missing && missing.length ? t('deal.missing', { fields: missing.join(', ') })
            : deal.next_requires.length ? t('deal.requires', { fields: deal.next_requires.join(', '), count: deal.next_requires.length }) : undefined}>
          <Btns>
            {missing && missing.length
              ? <BtnLink href={recordHref('deal', deal.id)}>{t('deal.openDeal')}</BtnLink>
              : <Btn onClick={() => onMove(next)} disabled={movePending}>{t('deal.move')}</Btn>}
          </Btns>
        </Card>
      ) : null}
      <Card t={t('deal.notes')} s={deal.note ? `«${deal.note.body}»` : t('deal.noNotes')} />
    </Phone>
  )
}

// ---------------------------------------------------------------------------
// Capture (MOB-06, AIA-07, SF-44): audio notes, photos and scanned notes upload to the deal through the storage signer (0052)
// when it runs; transcription and reading handwriting need their providers, which are not connected. A card can be typed and
// reviewed, then saved under the contact rule (card_draft_save)
export type CardValues = { name: string; title: string; email: string; phone: string; organization_name: string; basis: string }
export type CaptureUpload = 'audio' | 'photo' | 'scan'

/** A design button that opens the device's recorder, camera or file picker (a file input: no camera or microphone permission). */
function PickBtn({ kind, primary, disabled, label, onFile }: { kind: CaptureUpload; primary?: boolean; disabled?: boolean; label: string; onFile: (f: File) => void }) {
  const input = useRef<HTMLInputElement>(null)
  const accept = kind === 'audio' ? acceptFor(RECORD_TYPES, (m) => m.startsWith('audio/'))
    : kind === 'photo' ? acceptFor(RECORD_TYPES, (m) => m.startsWith('image/'))
    : acceptFor(RECORD_TYPES, (m) => m.startsWith('image/') || m === 'application/pdf')
  return (
    <>
      <input ref={input} type="file" hidden accept={accept} capture={kind === 'audio' ? 'user' : 'environment'}
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) onFile(f) }} />
      <Btn primary={primary} disabled={disabled} onClick={() => input.current?.click()}>{label}</Btn>
    </>
  )
}

export function CapturePhone({ frame, rule, deal, offline, storage, captures, onSaveCard, onCapture }: {
  frame: Frame; rule: string; deal: DealPreview | null; offline: boolean; storage: boolean; captures: Captures | null
  onSaveCard: (v: CardValues) => Promise<string | null>; onCapture: (kind: CaptureUpload, file: File) => Promise<boolean>
}) {
  const t = useTranslations('mobile')
  const format = useFormatter()
  const empty: CardValues = { name: '', title: '', email: '', phone: '', organization_name: '', basis: '' }
  const [open, setOpen] = useState(false)
  const [v, setV] = useState<CardValues>(empty)
  const [bad, setBad] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [sending, setSending] = useState<CaptureUpload | null>(null)
  const known = (CONTACT_RULES as readonly string[]).includes(rule) ? rule : 'no_rule'
  const refused = known === 'opt_in_only'
  const needsBasis = known === 'source_and_basis'
  const field = (k: keyof CardValues, type = 'text') => (
    <label className={fieldLabel}>{t(`capture.card.${k}`)}
      <input className={`${fieldCls} ${bad === k ? 'border-danger' : ''}`} type={type} value={v[k]} onChange={(e) => setV({ ...v, [k]: e.target.value })} aria-invalid={bad === k} />
    </label>
  )
  const canSend = storage && !!deal && !offline && sending === null
  const send = async (kind: CaptureUpload, f: File) => {
    setSending(kind)
    try { await onCapture(kind, f) } finally { setSending(null) }
  }
  const day = (iso: string) => format.dateTime(new Date(iso), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
  const audio = captures?.items.find((c) => c.kind === 'audio') ?? null
  const scans = captures?.items.filter((c) => c.kind === 'photo' || c.kind === 'scan') ?? []
  const transcribing = captures?.transcription === 'connected'
  return (
    <Phone {...frame} title={t('capture.title')} label={t('phones.capture.label')} ids={t('phones.capture.ids')}>
      {!storage ? (
        <Card eyebrow={t('capture.audio.eyebrow')} t={t('capture.audio.t')} s={deal ? t('capture.audio.sOn', { record: deal.title }) : t('capture.audio.s')} />
      ) : (
        <Card eyebrow={transcribing ? t('capture.audio.eyebrowReady') : t('capture.audio.eyebrow')}
          t={audio ? (audio.transcript ? `«${audio.transcript}»` : audio.filename) : t('capture.audio.tReady')}
          s={!deal ? t('capture.audio.noDeal')
            : audio ? [t('capture.audio.attached', { when: day(audio.created_at), record: deal.title }),
                audio.transcript ? null : transcribing ? t('capture.audio.pending') : t('capture.audio.untranscribed')].filter(Boolean).join(' · ')
            : t('capture.audio.sReady', { record: deal.title })}>
          {deal ? <Btns><PickBtn kind="audio" primary disabled={!canSend} label={sending === 'audio' ? t('capture.sending') : t('capture.audio.record')} onFile={(f) => void send('audio', f)} /></Btns> : null}
          {deal && offline ? <span className="text-11.5 opacity-80">{t('needsConnection')}</span> : null}
        </Card>
      )}
      <Card eyebrow={t('capture.card.eyebrow')} t={open ? t('capture.card.review') : t('capture.card.t')} s={refused ? t('capture.card.refused') : open ? undefined : t('capture.card.s')}>
        {open ? (
          <form className="flex flex-col gap-[6px]" onSubmit={async (e) => {
            e.preventDefault()
            setBusy(true)
            const err = await onSaveCard(v)
            setBusy(false)
            if (err === null) { setOpen(false); setV(empty); setBad(null) } else setBad(err)
          }}>
            {field('name')}{field('title')}{field('email', 'email')}{field('phone', 'tel')}{field('organization_name')}
            {needsBasis ? field('basis') : null}
            <Btns>
              <Btn type="submit" primary disabled={busy || !v.name.trim() || (needsBasis && !v.basis.trim())}>{t('capture.card.save')}</Btn>
              <Btn onClick={() => { setOpen(false); setBad(null) }}>{t('cancel')}</Btn>
            </Btns>
          </form>
        ) : (
          <Btns><Btn primary disabled={refused || offline} onClick={() => setOpen(true)}>{t('capture.card.create')}</Btn></Btns>
        )}
        {!open && offline && !refused ? <span className="text-11.5 opacity-80">{t('needsConnection')}</span> : null}
      </Card>
      {!storage ? <Card eyebrow={t('capture.scan.eyebrow')} t={t('capture.scan.t')} s={t('capture.scan.s')} /> : (
        <Card eyebrow={t('capture.scan.eyebrow')} t={t('capture.scan.t')}
          s={deal ? (scans.length ? t('capture.scan.kept', { n: scans.length, record: deal.title }) : t('capture.scan.sReady', { record: deal.title })) : t('capture.scan.noDeal')}>
          {deal ? (
            <Btns>
              <PickBtn kind="photo" disabled={!canSend} label={sending === 'photo' ? t('capture.sending') : t('capture.scan.photo')} onFile={(f) => void send('photo', f)} />
              <PickBtn kind="scan" disabled={!canSend} label={sending === 'scan' ? t('capture.sending') : t('capture.scan.scan')} onFile={(f) => void send('scan', f)} />
            </Btns>
          ) : null}
        </Card>
      )}
      <Card tone="canvas" s={t('capture.rule', { rule: t(`capture.rules.${known}`), effect: t(`capture.effects.${known}`) })} />
    </Phone>
  )
}

// ---------------------------------------------------------------------------
// Notifications (MOB-07): the staff member's latest notifications, as the bell writes them (shell messages); push is not
// connected, so they stay in the app
const KIND_TONE: Record<string, Tone> = { reminder: 'dark', chat_request: 'amber' }
export function NotificationsPhone({ frame, data, pushReady }: { frame: Frame; data: { unread: number; items: NotificationItem[] } | null; pushReady: boolean }) {
  const t = useTranslations('mobile')
  const tn = useTranslations('shell.notifications.messages')
  const format = useFormatter()
  const now = useNow({ updateInterval: 60_000 })
  const text = (n: NotificationItem, part: 'title' | 'body') => (tn.has(`${n.key}.${part}`) ? tn(`${n.key}.${part}`, n.params) : part === 'title' ? t('notifications.unknown') : '')
  return (
    <Phone {...frame} title={t('notifications.title')} label={t('phones.notifications.label')} ids={t('phones.notifications.ids')}>
      {data === null ? <Card t={t('notifications.failed')} /> : null}
      {data && data.items.length === 0 ? <Card t={t('notifications.none')} s={t('notifications.noneBody')} /> : null}
      {data?.items.map((n) => (
        <Card key={n.id} tone={KIND_TONE[n.kind] ?? 'plain'}
          eyebrow={`${t.has(`kinds.${n.kind}`) ? t(`kinds.${n.kind}`) : n.kind} · ${format.relativeTime(new Date(n.created_at), now)}`}
          t={n.route ? <Link href={n.route as never} className="text-inherit hover:text-inherit">{text(n, 'title')}</Link> : text(n, 'title')}
          s={text(n, 'body') || undefined} />
      ))}
      {!pushReady ? <Card tone="canvas" s={t('notifications.inAppOnly')} /> : null}
    </Phone>
  )
}

// ---------------------------------------------------------------------------
// Extras (MOB-08): this month's won value and goal (the Insights formula), live chat waiting (leadgen), project tasks due
export function ExtrasPhone({ frame, focus, nf }: { frame: Frame; focus: Focus; nf: NumberFormat }) {
  const t = useTranslations('mobile')
  const m = focus.month
  const goal = m?.goal ?? null
  const target = goal ? (goal.target_value ?? goal.target_count) : null
  const pct = goal && target && goal.progress !== null ? (goal.progress / target) * 100 : null
  return (
    <Phone {...frame} title={t('extras.title')} label={t('phones.extras.label')} ids={t('phones.extras.ids')}>
      {m ? (
        <Card eyebrow={t('extras.month')} big={money(m.won_value_nok, nf)}
          s={[t('extras.won'), pct !== null ? t('extras.goal', { pct: percent(pct, nf) }) : null, t('extras.newDeals', { n: m.new_deals })].filter(Boolean).join(' · ')} />
      ) : null}
      {focus.chats_waiting !== null ? (
        <Card eyebrow={t('extras.chat')} t={focus.chats_waiting > 0 ? t('extras.chatWaiting', { n: focus.chats_waiting }) : t('extras.chatNone')} s={t('extras.chatS')}>
          <Btns><BtnLink primary={focus.chats_waiting > 0} href="/lead-capture?tab=chat">{t('extras.openChat')}</BtnLink></Btns>
        </Card>
      ) : null}
      {focus.tasks_due_today !== null ? (
        <Card eyebrow={t('extras.tasks')} t={t('extras.tasksDue', { n: focus.tasks_due_today })} s={t('extras.tasksS')}>
          <Btns><BtnLink href="/projects">{t('extras.openProjects')}</BtnLink></Btns>
        </Card>
      ) : null}
    </Phone>
  )
}
