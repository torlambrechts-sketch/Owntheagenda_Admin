'use client'

import Link from 'next/link'
import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { RpcCode } from '@/lib/rpc'
import type { MeetingBundle, Row, Workspace } from '@/lib/data/meetings'
import { STATE_TONE } from '@/lib/data/meetings-shared'
import { fetchWorkspace } from '../actions'
import { MeetingPanel } from './MeetingPanel'
import { card20, useFail, useWhen, type Me } from './kit'
import { useMeetingText } from './text'

type Props = {
  ws: Workspace
  setWs: (w: Workspace) => void
  selId: string | null
  bundle: MeetingBundle | null
  bundleError: RpcCode | null
  loading: boolean
  onOpen: (id: string) => void
  onChanged: () => Promise<void>
  me: Me
  products: Record<string, string>
}

/** The workspace: the three grouped lists on the left, the chosen meeting on the right (Meetings.dc.html, v.workspace). */
export function WorkspaceView({ ws, setWs, selId, bundle, bundleError, loading, onOpen, onChanged, me, products }: Props) {
  const t = useTranslations('meetings')
  const when = useWhen(me)
  const text = useMeetingText()
  const fail = useFail()
  const [more, setMore] = useState(false)
  const empty = ws.upcoming.length + ws.review.length + ws.history.length === 0

  const older = async () => {
    if (!ws.history_next) return
    setMore(true)
    const r = await fetchWorkspace({ history_before: ws.history_next })
    setMore(false)
    if (!r.ok) { fail(r); return }
    setWs({ ...ws, history: [...ws.history, ...r.workspace.history], history_next: r.workspace.history_next })
  }

  const item = (m: Row) => {
    const tone = STATE_TONE[m.state?.key ?? 'none']
    const on = m.id === selId
    return (
      <button
        key={m.id}
        type="button"
        aria-current={on ? 'true' : undefined}
        onClick={() => onOpen(m.id)}
        className={`flex w-full cursor-pointer flex-col gap-[3px] border-0 border-b border-solid border-line px-[14px] py-[11px] text-left ${on ? 'bg-highlight' : 'bg-transparent'}`}
      >
        <span className="flex justify-between gap-2 text-12 text-muted">
          <span>{when(m.starts_at ?? m.at, { time: m.group !== 'history' && !!m.starts_at, day: m.group === 'history' ? 'plain' : 'weekday' })}</span>
          <span className="text-right font-bold" style={{ color: tone.c }}>{text.state(m.state, m.capture, true)}</span>
        </span>
        <b className="text-13">{m.title}</b>
        <span className="text-11.5 text-muted">{m.organization?.name ?? (m.linked ? t('dash') : t('list.notLinked'))} · {text.via(m.conference, m.capture)}</span>
      </button>
    )
  }

  const group = (key: 'upcoming' | 'review' | 'history', rows: Row[]) => (
    <div key={key} className={`${card20} overflow-hidden`}>
      <div className="border-0 border-b border-solid border-line px-[14px] py-[10px] text-11 font-bold uppercase tracking-eyebrow text-muted">{t(`groups.${key}`)}</div>
      {rows.map(item)}
      {rows.length === 0 ? <div className="px-[14px] py-[11px] text-12 text-faint">{t(`groups.empty.${key}`)}</div> : null}
      {key === 'history' && ws.history_next ? (
        <button type="button" disabled={more} onClick={() => void older()} className="w-full cursor-pointer border-none bg-transparent px-[14px] py-[10px] text-left text-12 font-semibold text-link disabled:opacity-60">
          {t('groups.older')}
        </button>
      ) : null}
    </div>
  )

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(260px,320px)_minmax(0,1fr)]">
      <div className="flex flex-col gap-3">
        {group('upcoming', ws.upcoming)}
        {group('review', ws.review)}
        {group('history', ws.history)}
      </div>
      <div className="flex min-w-0 flex-col gap-3">
        {empty ? (
          <div className={`${card20} flex flex-col gap-2 px-5 py-4`}>
            <b className="font-serif text-22 font-semibold">{t('empty.title')}</b>
            <span className="text-12.5 leading-[1.5] text-ink-2">{ws.capabilities.calendar === 'connected' ? t('empty.connected') : t('empty.noCalendar')}</span>
            {ws.capabilities.calendar !== 'connected' ? (
              <Link href="/activities?tab=reminders" className="self-start text-12.5 font-semibold">{t('empty.connect')}</Link>
            ) : null}
          </div>
        ) : bundle && bundle.detail.id === selId ? (
          <MeetingPanel key={bundle.detail.id} bundle={bundle} capabilities={ws.capabilities} loading={loading} onChanged={onChanged} me={me} products={products} />
        ) : (
          <div className={`${card20} px-5 py-4 text-13 text-muted`}>
            {loading ? t('loading') : bundleError ? t(`errors.open_${bundleError === 'not_found' ? 'not_found' : 'failed'}`) : t('empty.choose')}
          </div>
        )}
      </div>
    </div>
  )
}
