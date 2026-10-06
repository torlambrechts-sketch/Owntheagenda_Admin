'use client'

import { useCallback, useEffect, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { Switch } from '@/components/ui/Switch'
import { formatNumber, type NumberFormat } from '@/lib/format'
import {
  BUTTONS, DAYS, FORM_LANGS, PALETTES, STEP_KINDS, STEP_MAPS, TEMPLATES,
  type ChatDetail, type ChatQueue, type Day, type Hours, type Playbook, type PlaybookStats, type Site, type Step, type Template,
} from '@/lib/data/capture-shared'
import { claimChat, closeChat, pollChats, publishPlaybook, savePlaybook, saveSite, sendChat, setPlaybookHours, setPlaybookState, setPresence, type Result } from '../actions'
import { useErr, useGo } from './hooks'

export type ChatProps = {
  playbooks: Playbook[] | null // null: no campaigns:see
  playbook: Playbook | null
  stats: PlaybookStats | null
  queue: ChatQueue | null // null: no deals:see
  chat: ChatDetail | null
  sites: Site[] | null
  widgetConsent: string
  can: { add: boolean; configure: boolean; editOthers: boolean; chat: boolean; me: string; meName: string }
  nf: NumberFormat
}

const card = 'rounded-20 border border-line bg-surface'
const small = 'h-[30px] rounded-9 border border-line bg-canvas px-[9px] text-12 text-ink'
const btn = 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50'

/** Chatbot and live chat (Marketing.dc.html, v.chat): playbooks, the live chat and the embed. */
export function ChatView(p: ChatProps) {
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      {p.playbooks ? <Playbooks {...p} playbooks={p.playbooks} /> : null}
      {p.queue ? <LiveChat {...p} queue={p.queue} /> : null}
      {p.sites ? <Embed sites={p.sites} widgetConsent={p.widgetConsent} canConfigure={p.can.configure} nf={p.nf} /> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
// playbooks
type StepTab = 'theme' | 'profile' | 'template'

function Playbooks(p: ChatProps & { playbooks: Playbook[] }) {
  const t = useTranslations('capture.chat')
  const tt = useTranslations('capture.templates')
  const { go } = useGo()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [tab, setTab] = useState<StepTab>('template')
  const [making, setMaking] = useState(false)
  const [newName, setNewName] = useState('')
  const [newTpl, setNewTpl] = useState<Template>('leads')
  const [busy, start] = useTransition()
  const pb = p.playbook
  // «Chat live · business hours» (Marketing.dc.html): a playbook with opening hours names them in place of «all pages»
  const sub = (x: Playbook) => [tt(x.template), x.pages.length ? x.pages.join(', ') : x.hours ? null : t('allPages'), x.hours ? t('businessHours') : null]
    .filter(Boolean).join(' · ')

  const create = () => start(async () => {
    const r = await savePlaybook({ id: null, values: { name: newName.trim(), template: newTpl }, version: null })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    setMaking(false)
    setNewName('')
    flash(t('created'))
    router.push(`/lead-capture?tab=chat&pb=${r.id}` as never, { scroll: false })
  })

  const steps: [StepTab, string][] = pb
    ? [
        ['theme', [t(`palette.${pb.theme.palette ?? 'cream'}`), t(`button.${pb.theme.button ?? 'saffron'}`)].join(', ')],
        ['profile', [t('profileName', { name: pb.profile.name || '—' }), pb.profile.avatar ? t(`avatar.${pb.profile.avatar === 'face' ? 'face' : 'none'}`) : null, t(`langs.${pb.profile.language ?? 'nb'}`)].filter(Boolean).join(', ')],
        ['template', tt(pb.template)],
      ]
    : []

  return (
    <div className={`flex flex-col gap-[10px] px-[18px] py-4 ${card}`}>
      <div className="flex items-center justify-between gap-2">
        <b className="text-14">{t('playbooks')}</b>
        {p.can.add ? (
          <button type="button" onClick={() => setMaking(!making)} aria-expanded={making} className="cursor-pointer border-0 bg-transparent p-0 text-12 font-semibold text-link">{t('newPlaybook')}</button>
        ) : null}
      </div>
      {making ? (
        <div className="flex flex-wrap items-end gap-[6px] rounded-12 border border-line bg-canvas p-[10px]">
          <label className="flex min-w-[160px] flex-1 flex-col gap-[3px] text-11.5 text-muted">
            {t('name')}
            <input value={newName} maxLength={120} onChange={(e) => setNewName(e.target.value)} className={small} />
          </label>
          <label className="flex flex-col gap-[3px] text-11.5 text-muted">
            {t('template')}
            <select value={newTpl} onChange={(e) => setNewTpl(e.target.value as Template)} className={small}>
              {TEMPLATES.map((k) => <option key={k} value={k}>{tt(k)}</option>)}
            </select>
          </label>
          <button type="button" disabled={busy || !newName.trim()} onClick={create} className={`${btn} border-ink bg-primary`}>{t('create')}</button>
        </div>
      ) : null}
      {p.playbooks.map((x) => (
        <button
          key={x.id}
          type="button"
          onClick={() => go({ pb: x.id })}
          aria-current={x.id === pb?.id ? 'true' : undefined}
          className={`flex w-full cursor-pointer items-center justify-between border-0 border-b border-line py-[9px] text-left text-12.5 ${x.id === pb?.id ? '-mx-2 rounded-8 bg-highlight px-2 [width:calc(100%+16px)]' : 'bg-transparent px-0'}`}
        >
          <span className="flex flex-col"><b>{x.name}</b><span className="text-11.5 text-muted">{sub(x)}</span></span>
          <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${x.state === 'live' ? 'bg-ok-bg' : 'bg-tile'}`}>{t(`state.${x.state}`)}</span>
        </button>
      ))}
      {p.playbooks.length === 0 ? <span className="text-12.5 text-muted">{t('noPlaybooks')}</span> : null}
      {pb ? (
        <div className="flex gap-[6px]">
          {steps.map(([k, d], j) => (
            <button
              key={k}
              type="button"
              onClick={() => setTab(k)}
              aria-pressed={tab === k}
              className={`flex flex-1 cursor-pointer flex-col items-start justify-start rounded-12 border px-[10px] py-[9px] text-left text-12 ${tab === k ? 'border-ink bg-highlight' : 'border-line bg-canvas'}`}
            >
              <b>{j + 1} · {t(`steps.${k}`)}</b>
              <div className="text-11 text-muted">{d}</div>
            </button>
          ))}
        </div>
      ) : null}
      <div className="text-12 text-muted">{t('templatesLine')}</div>
      {pb ? <PlaybookEditor key={`${pb.id}:${pb.version}`} pb={pb} tab={tab} stats={p.stats} can={p.can} nf={p.nf} /> : null}
    </div>
  )
}

function PlaybookEditor({ pb, tab, stats, can, nf }: { pb: Playbook; tab: StepTab; stats: PlaybookStats | null; can: ChatProps['can']; nf: NumberFormat }) {
  const t = useTranslations('capture.chat')
  const tt = useTranslations('capture.templates')
  const tm = useTranslations('capture.maps')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [busy, start] = useTransition()
  const edit = can.add && (pb.owner?.id === can.me || can.editOthers)
  const [name, setName] = useState(pb.name)
  const [palette, setPalette] = useState(pb.theme.palette ?? 'cream')
  const [button, setButton] = useState(pb.theme.button ?? 'saffron')
  const [profName, setProfName] = useState(pb.profile.name ?? '')
  const [profLang, setProfLang] = useState(pb.profile.language ?? 'nb')
  const [template, setTemplate] = useState<Template>(pb.template)
  const [pages, setPages] = useState(pb.pages.join(', '))
  const [steps, setSteps] = useState<Step[]>(pb.steps)
  const [wait, setWait] = useState(pb.queue_wait_seconds)
  const [offline, setOffline] = useState(pb.offline_message ?? '')
  const [dirty, setDirty] = useState(false)
  const d = <T,>(set: (v: T) => void) => (v: T) => { set(v); setDirty(true) }

  const act = (fn: () => Promise<Result>, msg: string) => start(async () => {
    const r = await fn()
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(msg)
    setDirty(false)
    router.refresh()
  })
  const save = () => act(() => {
    const pageList = pages.split(',').map((s) => s.trim()).filter(Boolean)
    return savePlaybook({
      id: pb.id, version: pb.version,
      values: {
        name: name.trim(), template, pages: pageList,
        theme: { palette: palette as (typeof PALETTES)[number], button: button as (typeof BUTTONS)[number] },
        profile: { ...(pb.profile.avatar ? { avatar: pb.profile.avatar } : {}), name: profName.trim(), language: profLang as (typeof FORM_LANGS)[number] },
        steps: steps.map((s) => ({ key: s.key, kind: s.kind, text: s.text, ...(s.kind === 'question' && s.map ? { map: s.map } : {}) })),
        queue_wait_seconds: wait, offline_message: offline,
      },
    })
  }, t('saved'))

  const addStep = (kind: Step['kind']) => {
    const keys = new Set(steps.map((s) => s.key))
    let key = kind === 'question' ? 'q' : kind === 'handoff' ? 'handoff' : 'msg'
    for (let i = 2; keys.has(key); i++) key = `${kind === 'question' ? 'q' : kind === 'handoff' ? 'handoff' : 'msg'}_${i}`
    setSteps([...steps, { key, kind, text: '' }])
    setDirty(true)
  }

  return (
    <div className="flex flex-col gap-2 border-0 border-t border-line pt-[10px] text-12">
      {edit ? (
        <>
          {tab === 'theme' ? (
            <div className="flex flex-wrap gap-2">
              <Lab label={t('paletteLabel')}>
                <select value={palette} onChange={(e) => d(setPalette)(e.target.value)} className={small}>{PALETTES.map((k) => <option key={k} value={k}>{t(`palette.${k}`)}</option>)}</select>
              </Lab>
              <Lab label={t('buttonLabel')}>
                <select value={button} onChange={(e) => d(setButton)(e.target.value)} className={small}>{BUTTONS.map((k) => <option key={k} value={k}>{t(`button.${k}`)}</option>)}</select>
              </Lab>
            </div>
          ) : null}
          {tab === 'profile' ? (
            <div className="flex flex-wrap gap-2">
              <Lab label={t('profileNameLabel')}><input value={profName} maxLength={60} onChange={(e) => d(setProfName)(e.target.value)} className={small} /></Lab>
              <Lab label={t('languageLabel')}>
                <select value={profLang} onChange={(e) => d(setProfLang)(e.target.value)} className={small}>{FORM_LANGS.map((k) => <option key={k} value={k}>{t(`langs.${k}`)}</option>)}</select>
              </Lab>
              <span className="basis-full text-11 text-faint">{t('avatarNote')}</span>
            </div>
          ) : null}
          {tab === 'template' ? (
            <>
              <div className="flex flex-wrap gap-2">
                <Lab label={t('name')}><input value={name} maxLength={120} onChange={(e) => d(setName)(e.target.value)} className={small} /></Lab>
                <Lab label={t('template')}>
                  <select value={template} onChange={(e) => d(setTemplate)(e.target.value as Template)} className={small}>{TEMPLATES.map((k) => <option key={k} value={k}>{tt(k)}</option>)}</select>
                </Lab>
                <Lab label={t('pagesLabel')}><input value={pages} placeholder="/pris, /artikler/*" onChange={(e) => d(setPages)(e.target.value)} className={small} /></Lab>
              </div>
              <span className="text-11.5 font-semibold text-muted">{t('stepsLabel')}</span>
              {steps.map((s, i) => (
                <div key={s.key} className="flex flex-wrap items-center gap-[6px]">
                  <select aria-label={t('stepKind')} value={s.kind} onChange={(e) => { const n = [...steps]; n[i] = { ...s, kind: e.target.value as Step['kind'] }; d(setSteps)(n) }} className={small}>
                    {STEP_KINDS.map((k) => <option key={k} value={k}>{t(`stepKinds.${k}`)}</option>)}
                  </select>
                  <input aria-label={t('stepText')} value={s.text} maxLength={1000} onChange={(e) => { const n = [...steps]; n[i] = { ...s, text: e.target.value }; d(setSteps)(n) }} className={`${small} min-w-[140px] flex-1`} />
                  {s.kind === 'question' ? (
                    <select aria-label={t('stepMap')} value={s.map ?? ''} onChange={(e) => { const n = [...steps]; n[i] = { ...s, map: (e.target.value || undefined) as Step['map'] }; d(setSteps)(n) }} className={small}>
                      <option value="">{t('mapNone')}</option>
                      {STEP_MAPS.map((m) => <option key={m} value={m}>{tm(m)}</option>)}
                    </select>
                  ) : null}
                  <button type="button" onClick={() => d(setSteps)(steps.filter((_, k) => k !== i))} className={`${btn} border-line bg-transparent font-semibold`} aria-label={t('removeStep')}>✕</button>
                </div>
              ))}
              {steps.length === 0 ? <span className="text-11.5 text-muted">{t(template === 'live_chat' ? 'noStepsLive' : 'noSteps')}</span> : null}
              <div className="flex flex-wrap gap-[6px]">
                {STEP_KINDS.map((k) => <button key={k} type="button" onClick={() => addStep(k)} className={`${btn} border-line bg-canvas font-semibold`}>＋ {t(`stepKinds.${k}`)}</button>)}
              </div>
              <div className="flex flex-wrap gap-2">
                <Lab label={t('waitLabel')}><input type="number" min={10} max={900} value={wait} onChange={(e) => d(setWait)(Number(e.target.value))} className={`${small} w-[90px]`} /></Lab>
                <Lab label={t('offlineLabel')}><input value={offline} maxLength={500} onChange={(e) => d(setOffline)(e.target.value)} className={`${small} min-w-[200px]`} /></Lab>
              </div>
            </>
          ) : null}
          {dirty ? <span className="text-11.5 font-semibold text-warn-ink">{t('unsaved')}</span> : null}
        </>
      ) : null}
      {tab === 'template' && (pb.template === 'live_chat' || pb.steps.some((s) => s.kind === 'handoff')) ? (
        <OpeningHours pb={pb} canConfigure={can.configure} />
      ) : null}
      <span className="text-11.5 text-muted">
        {pb.current_version > 0 ? t('publishedV', { v: pb.current_version }) : t('neverPublished')}
        {stats ? ` · ${t('stats', { n: formatNumber(stats.conversations, nf), done: formatNumber(stats.completed, nf), live: formatNumber(stats.live, nf) })}` : ''}
      </span>
      {stats && stats.drop_off.length > 0 ? (
        <div className="flex flex-col">
          <span className="text-11.5 font-semibold text-muted">{t('dropOff')}</span>
          {stats.drop_off.map((x) => (
            <div key={x.step} className="flex justify-between border-0 border-b border-line py-1 text-11.5">
              <span>{pb.steps.find((s) => s.key === x.step)?.text ?? x.step}</span><b>{formatNumber(x.n, nf)}</b>
            </div>
          ))}
        </div>
      ) : null}
      <div className="flex flex-wrap gap-[6px]">
        {edit ? <button type="button" disabled={busy || !dirty} onClick={save} className={`${btn} border-ink bg-primary`}>{t('save')}</button> : null}
        {can.configure ? (
          <button type="button" disabled={busy || dirty} onClick={() => act(() => publishPlaybook({ id: pb.id }), t('publishedToast'))} className={`${btn} border-ink bg-surface`}>{t('publish')}</button>
        ) : null}
        {can.configure && pb.current_version > 0 ? (
          <button type="button" disabled={busy} onClick={() => act(() => setPlaybookState({ id: pb.id, state: pb.state === 'live' ? 'draft' : 'live' }), t(pb.state === 'live' ? 'toDraftToast' : 'liveToast'))} className={`${btn} border-line bg-transparent font-semibold`}>
            {t(pb.state === 'live' ? 'toDraft' : 'goLive')}
          </button>
        ) : null}
      </div>
      {!can.configure ? <span className="text-11 text-faint">{t('publishRight')}</span> : null}
    </div>
  )
}

/** Opening hours (0036): outside them the widget is offline and a live chat gets the offline message at once. */
function OpeningHours({ pb, canConfigure }: { pb: Playbook; canConfigure: boolean }) {
  const t = useTranslations('capture.chat')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [busy, start] = useTransition()
  const [on, setOn] = useState(pb.hours != null)
  const [hours, setHours] = useState<Hours>(pb.hours ?? { mon: ['08:00', '16:00'], tue: ['08:00', '16:00'], wed: ['08:00', '16:00'], thu: ['08:00', '16:00'], fri: ['08:00', '16:00'] })
  const [dirty, setDirty] = useState(false)
  const put = (day: Day, v: [string, string] | null) => {
    const n = { ...hours }
    if (v) n[day] = v
    else delete n[day]
    setHours(n)
    setDirty(true)
  }
  const valid = !on || DAYS.every((d) => !hours[d] || hours[d][0] < hours[d][1])
  const save = () => start(async () => {
    const r = await setPlaybookHours({ id: pb.id, hours: on ? hours : null, version: pb.version })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('hoursSaved'))
    setDirty(false)
    router.refresh()
  })
  return (
    <div className="flex flex-col gap-[6px] border-0 border-t border-line pt-[10px]">
      <span className="text-11.5 font-semibold text-muted">{t('hoursLabel')}</span>
      <label className="flex items-center gap-2 text-12">
        <input type="checkbox" checked={on} disabled={!canConfigure} onChange={(e) => { setOn(e.target.checked); setDirty(true) }} className="accent-ink" />
        {t('hoursOn')}
      </label>
      {on ? DAYS.map((d) => (
        <div key={d} className="flex flex-wrap items-center gap-[6px] text-12">
          <label className="flex w-[110px] items-center gap-2">
            <input type="checkbox" checked={!!hours[d]} disabled={!canConfigure} onChange={(e) => put(d, e.target.checked ? ['08:00', '16:00'] : null)} className="accent-ink" />
            {t(`days.${d}`)}
          </label>
          {hours[d] ? (
            <>
              <input type="time" aria-label={t('hoursFrom', { day: t(`days.${d}`) })} value={hours[d][0]} disabled={!canConfigure} onChange={(e) => put(d, [e.target.value, hours[d]![1]])} className={small} />
              <span className="text-muted">–</span>
              <input type="time" aria-label={t('hoursTo', { day: t(`days.${d}`) })} value={hours[d][1] === '24:00' ? '23:59' : hours[d][1]} disabled={!canConfigure} onChange={(e) => put(d, [hours[d]![0], e.target.value])} className={small} />
            </>
          ) : <span className="text-11.5 text-muted">{t('closed')}</span>}
        </div>
      )) : null}
      <span className="text-11 text-faint">{t(on ? 'hoursNote' : 'hoursOffNote')}</span>
      {canConfigure ? (
        <div>
          <button type="button" disabled={busy || !dirty || !valid} onClick={save} className={`${btn} border-ink bg-surface`}>{t('saveHours')}</button>
          {!valid ? <span className="ml-2 text-11.5 font-semibold text-warn-ink">{t('hoursInvalid')}</span> : null}
        </div>
      ) : null}
    </div>
  )
}

const Lab = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <label className="flex flex-col gap-[3px] text-11.5 text-muted">{label}{children}</label>
)

// ---------------------------------------------------------------------------
// live chat: polled every 3 s while the tab is visible (Q10); presence renewed every minute while online
function LiveChat(p: ChatProps & { queue: ChatQueue }) {
  const t = useTranslations('capture.live')
  const err = useErr()
  const flash = useToast()
  const [queue, setQueue] = useState(p.queue)
  const [chat, setChat] = useState<ChatDetail | null>(p.chat)
  const [online, setOnline] = useState(p.queue.online)
  const [text, setText] = useState('')
  const [busy, start] = useTransition()
  const sel = useRef<string | null>(p.chat?.id ?? null)
  const beat = useRef(0)

  const poll = useCallback(async () => {
    const r = await pollChats({ id: sel.current })
    if (!r.ok) return
    setQueue(r.queue)
    setChat(r.chat)
    sel.current = r.chat?.id ?? null
  }, [])

  useEffect(() => {
    const tick = () => {
      if (document.visibilityState !== 'visible') return
      void poll()
      if (online && Date.now() - beat.current > 60_000) { beat.current = Date.now(); void setPresence({ online: true }) }
    }
    const id = setInterval(tick, 3000)
    return () => clearInterval(id)
  }, [poll, online])

  const pick = (id: string) => { sel.current = id; void poll() }
  const presence = (on: boolean) => start(async () => {
    const r = await setPresence({ online: on })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    beat.current = Date.now()
    setOnline(on)
  })
  const claim = () => start(async () => {
    if (!chat) return
    const r = await claimChat({ id: chat.id })
    if (!r.ok) flash(err(r.code, r.detail))
    await poll()
  })
  const send = () => start(async () => {
    if (!chat || !text.trim()) return
    const r = await sendChat({ id: chat.id, body: text })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    setText('')
    await poll()
  })
  const close = () => start(async () => {
    if (!chat) return
    const r = await closeChat({ id: chat.id })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(r.leadId ? t('closedLead') : t('closed'))
    sel.current = null
    await poll()
  })

  const mine = chat?.claimed_by?.id === p.can.me && chat.state === 'live'
  const other = chat?.claimed_by && chat.claimed_by.id !== p.can.me ? chat.claimed_by.name : null
  const first = p.can.meName.split(' ')[0] ?? p.can.meName
  const who = (m: ChatDetail['transcript'][number]) => m.sender === 'bot' ? t('bot') : m.sender === 'visitor' ? t('visitor') : m.sender === 'system' ? t('system') : (m.staff?.split(' ')[0] ?? t('staff'))

  return (
    <div className={`flex min-h-[440px] flex-col ${card}`}>
      <div className="flex items-center justify-between gap-2 border-0 border-b border-line px-4 py-3">
        <span className="flex min-w-0 flex-col">
          <b className="text-14">{chat ? t('title', { page: chat.page_path ?? '/' }) : t('titleEmpty')}</b>
          <span className="text-11.5 text-muted">
            {chat
              ? chat.company
                ? t('company', { name: chat.company.name ?? chat.company.org_number, n: chat.company.visits_30d })
                : t('noCompany', { site: chat.site ?? '—' })
              : t('subEmpty')}
          </span>
        </span>
        {chat && chat.state !== 'closed' ? (
          mine ? (
            <span className="flex shrink-0 gap-[6px]">
              <span className="flex h-8 items-center rounded-9 border border-ink bg-ok-bg px-[13px] text-12 font-bold">{t('youAreChatting')}</span>
              <button type="button" disabled={busy} onClick={close} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">{t('close')}</button>
            </span>
          ) : other ? (
            <span className="flex h-8 shrink-0 items-center rounded-9 border border-line bg-tile px-[13px] text-12 font-bold">{t('otherChatting', { name: other.split(' ')[0] ?? other })}</span>
          ) : (
            <button type="button" disabled={busy || !p.can.chat} onClick={claim} className="h-8 shrink-0 cursor-pointer rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold disabled:cursor-default disabled:opacity-50">{t('takeOver')}</button>
          )
        ) : null}
      </div>
      <div className="flex flex-wrap items-center gap-[6px] border-0 border-b border-line px-4 py-2 text-11.5 text-muted">
        {queue.rows.map((r) => (
          <button
            key={r.id}
            type="button"
            onClick={() => pick(r.id)}
            aria-pressed={r.id === chat?.id}
            className={`cursor-pointer rounded-999 border px-[9px] py-[3px] text-11 ${r.id === chat?.id ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent'}`}
          >
            {r.page_path ?? '/'} · {t(`state.${r.state}`)}
          </button>
        ))}
        {queue.rows.length === 0 ? <span>{t('queueEmpty')}</span> : null}
        <span className="flex-1" />
        <span>{t('staffOnline', { n: queue.staff_online })}</span>
        <Switch on={online} onChange={presence} label={t('online')} disabled={busy} />
        <span className="font-semibold text-ink">{t(online ? 'online' : 'offline')}</span>
      </div>
      <div className="flex flex-1 flex-col gap-2 bg-canvas px-4 py-3" aria-live="polite">
        {chat?.transcript.map((m) => {
          const right = m.sender === 'bot' || m.sender === 'staff'
          return (
            <div key={m.id} className={`flex ${right ? 'justify-end' : m.sender === 'system' ? 'justify-center' : 'justify-start'}`}>
              <div className={`max-w-[75%] rounded-13 border border-line px-[11px] py-2 text-12.5 leading-[1.45] ${m.sender === 'bot' ? 'bg-teal-soft' : m.sender === 'staff' ? 'bg-highlight' : m.sender === 'system' ? 'bg-tile' : 'bg-surface'}`}>
                <span className="block text-10.5 font-bold text-muted">{who(m)}</span>{m.body}
              </div>
            </div>
          )
        })}
        {!chat ? <div className="m-auto max-w-[320px] text-center text-12.5 text-muted">{t('empty')}</div> : null}
      </div>
      <div className="flex gap-2 border-0 border-t border-line px-3 py-[10px]">
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && mine) { e.preventDefault(); send() } }}
          disabled={!mine}
          maxLength={4000}
          aria-label={t('reply')}
          placeholder={mine ? t('replyAs', { name: first }) : t('takeOverToReply')}
          className="h-9 min-w-0 flex-1 rounded-10 border border-line bg-canvas px-[11px] text-12.5"
        />
        <button type="button" onClick={send} disabled={!mine || busy || !text.trim()} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold disabled:cursor-default">{t('send')}</button>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// the embed: one script per tracked site (go.owntheagenda.com, D-28)
function Embed({ sites, widgetConsent, canConfigure, nf }: { sites: Site[]; widgetConsent: string; canConfigure: boolean; nf: NumberFormat }) {
  const t = useTranslations('capture.embed')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [busy, start] = useTransition()
  const [host, setHost] = useState('')
  const save = (id: string | null, values: { hostname?: string; active?: boolean; chat_enabled?: boolean }, msg: string) => start(async () => {
    const r = await saveSite({ id, values })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(msg)
    if (!id) setHost('')
    router.refresh()
  })
  return (
    <div className={`col-span-full flex flex-col gap-2 px-[18px] py-4 ${card}`}>
      <b className="text-14">{t('title')}</b>
      {sites.map((s) => (
        <div key={s.id} className="flex flex-col gap-[6px]">
          <div className="break-all rounded-12 bg-ink p-3 font-mono text-12 text-tile">{s.snippet}</div>
          <div className="flex flex-wrap items-center gap-[10px] text-12 text-muted">
            <b className="text-ink">{s.hostname}</b>
            <span className="flex items-center gap-[6px]">
              {canConfigure ? <Switch on={s.active} onChange={(on) => save(s.id, { active: on }, t(on ? 'trackingOn' : 'trackingOff', { host: s.hostname }))} label={t('tracking', { host: s.hostname })} disabled={busy} /> : null}
              {t(s.active ? 'trackingIs' : 'trackingIsOff')}
            </span>
            <span className="flex items-center gap-[6px]">
              {canConfigure ? <Switch on={s.chat_enabled} onChange={(on) => save(s.id, { chat_enabled: on }, t(on ? 'chatOn' : 'chatOff', { host: s.hostname }))} label={t('chat', { host: s.hostname })} disabled={busy} /> : null}
              {t(s.chat_enabled ? 'chatIs' : 'chatIsOff')}
            </span>
            <span>{s.last_seen_at ? t('sessions', { n: formatNumber(s.sessions_7d, nf) }) : t('neverSeen')}</span>
          </div>
        </div>
      ))}
      {sites.length === 0 ? <span className="text-12 text-muted">{t('noSites')}</span> : null}
      {canConfigure ? (
        <div className="flex flex-wrap items-center gap-[6px]">
          <input value={host} onChange={(e) => setHost(e.target.value)} placeholder={t('hostPlaceholder')} aria-label={t('addSite')} className={`${small} min-w-[200px]`} />
          <button type="button" disabled={busy || !host.trim()} onClick={() => save(null, { hostname: host.trim() }, t('siteAdded'))} className={`${btn} border-ink bg-surface`}>{t('addSite')}</button>
        </div>
      ) : null}
      <span className="text-11.5 text-faint">{t('hostNote')}</span>
      <div className="flex flex-wrap gap-[14px] text-12 text-muted">
        <span>{t.rich('consentGated', { value: t(widgetConsent === 'on' ? 'on' : 'off'), b: (c) => <b className="text-ink">{c}</b> })}</span>
        <span>{t('wording')}</span>
        <span className="font-bold text-danger">{t('surveyBlock')}</span>
      </div>
    </div>
  )
}
