'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Workspace } from '@/lib/data/meetings'
import { setMySettings } from '../actions'
import type { Mine } from './MeetingsScreen'
import { Modal, btn32, btnCancel, useFail } from './kit'

type Props = { ws: Workspace; mine: Mine | null; onMineChanged: () => Promise<void>; onUpload: () => void }

/**
 * Ways to capture (Meetings.dc.html, v.capture; spec §2.5): the four cards, each with its honest state. The notetaker
 * and transcription wait for their providers, the desktop app is not available (D-38), and upload waits for the file
 * storage signer. The auto-join choice behind «Configure» is real and stored (meeting_my_settings_set).
 */
export function CaptureView({ ws, mine, onMineChanged, onUpload }: Props) {
  const t = useTranslations('meetings.capture')
  const [configure, setConfigure] = useState(false)
  const botOn = ws.capabilities.meeting_bot === 'connected'
  const auto = mine?.settings.bot_auto_join ?? null
  const cards = [
    { k: 'bot', g: '◉', bg: '#CFE7E4', s: auto ? t(`autoJoin.${auto}`) : t('dash'), status: botOn ? t('bot.connected') : t('bot.notConnected'), cta: t('bot.cta'), run: () => setConfigure(true), off: !mine },
    { k: 'desktop', g: '▣', bg: '#CFE0F5', s: t('desktop.s'), status: t('desktop.status'), cta: t('desktop.cta'), run: null, off: true },
    { k: 'adhoc', g: '●', bg: '#FBD5C4', s: t('adhoc.s'), status: t('adhoc.status'), cta: t('adhoc.cta'), run: null, off: true },
    { k: 'upload', g: '▤', bg: '#F3E2C9', s: t('upload.s'), status: t('upload.status'), cta: t('upload.cta'), run: onUpload, off: false },
  ]
  return (
    <div className="grid gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
      {cards.map((c) => (
        <div key={c.k} className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-5 py-[18px]">
          <span className="flex h-10 w-10 items-center justify-center rounded-12 text-18" style={{ background: c.bg }} aria-hidden="true">{c.g}</span>
          <b className="text-15">{t(`${c.k}.n`)}</b>
          <span className="text-12.5 leading-[1.55] text-ink-2">{t(`${c.k}.d`)}</span>
          <span className="text-12 text-muted">{c.s}</span>
          <span className="text-11.5 font-semibold leading-[1.5] text-amber-ink">{c.status}</span>
          <button type="button" disabled={c.off || !c.run} onClick={() => c.run?.()} className={btn32}>{c.cta}</button>
        </div>
      ))}
      {configure && mine ? <AutoJoinModal value={mine.settings.bot_auto_join} botOn={botOn} onClose={() => setConfigure(false)} onSaved={onMineChanged} /> : null}
    </div>
  )
}

/** The notetaker's auto-join choice (spec §2.5): external guests (the design's default), every meeting, or off. */
export function AutoJoinModal({ value, botOn, onClose, onSaved }: { value: 'external' | 'all' | 'off'; botOn: boolean; onClose: () => void; onSaved: () => Promise<void> }) {
  const t = useTranslations('meetings.capture')
  const fail = useFail()
  const flash = useToast()
  const [busy, setBusy] = useState(false)
  const pick = async (v: 'external' | 'all' | 'off') => {
    setBusy(true)
    const r = await setMySettings({ bot_auto_join: v })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(t('autoJoinSaved'))
    await onSaved()
    onClose()
  }
  return (
    <Modal eyebrow={t('bot.n')} title={t('autoJoinTitle')} onClose={onClose}>
      {(['external', 'all', 'off'] as const).map((k) => (
        <button key={k} type="button" disabled={busy} onClick={() => void pick(k)}
          className={`flex cursor-pointer flex-col gap-[2px] rounded-13 border px-[13px] py-[11px] text-left ${value === k ? 'border-ink bg-highlight' : 'border-line bg-transparent'}`}>
          <b className="text-13">{t(`autoJoin.${k}`)}</b>
          <span className="text-11.5 text-muted">{t(`autoJoinHint.${k}`)}</span>
        </button>
      ))}
      <p className="m-0 text-11.5 leading-[1.5] text-muted">{botOn ? t('autoJoinNote') : t('autoJoinNoteOff')}</p>
      <div className="flex justify-end"><button type="button" onClick={onClose} className={btnCancel}>{t('close')}</button></div>
    </Modal>
  )
}
