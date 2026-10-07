'use client'

import type { Route } from 'next'
import Link from 'next/link'
import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { recordHref } from '@/lib/records-href'
import type { Capabilities, Detail, LinkRef, MeetingBundle } from '@/lib/data/meetings'
import { STATE_TONE, attendeeLine, type MTab } from '@/lib/data/meetings-shared'
import { linkMeeting } from '../actions'
import { BriefTab } from './BriefTab'
import { TranscriptTab } from './TranscriptTab'
import { SuggestionsTab } from './SuggestionsTab'
import { ConsentCard } from './ConsentCard'
import { Modal, Picker, btnCancel, card20, field, useFail, useWhen, type Me } from './kit'
import { useMeetingText } from './text'

type Props = { bundle: MeetingBundle; capabilities: Capabilities; loading: boolean; onChanged: () => Promise<void>; me: Me; products: Record<string, string> }

/** The right-hand side: the header (Meetings.dc.html), the three tabs, and the meeting's recording and consent. */
export function MeetingPanel({ bundle, capabilities, loading, onChanged, me, products }: Props) {
  const t = useTranslations('meetings')
  const d = bundle.detail
  const [tab, setTab] = useState<MTab>(d.default_tab)
  const [linking, setLinking] = useState(false)
  const when = useWhen(me)
  const text = useMeetingText()
  const tone = STATE_TONE[d.state?.key ?? 'none']
  const names = d.attendee_list.filter((a) => a.staff_id !== d.owner?.id).map((a) => a.name ?? a.email)
  const head = [when(d.starts_at ?? d.at, { time: !!d.starts_at }), text.via(d.conference, d.capture), names.length ? attendeeLine(names, (n) => t('header.others', { n })) : null].filter(Boolean).join(' · ')

  return (
    <>
      <div className={`${card20} flex flex-wrap items-start justify-between gap-3 px-5 py-4 ${loading ? 'opacity-70' : ''}`}>
        <div className="[flex:1_1_300px]">
          <div className="text-12 text-muted">{head}</div>
          <h2 className="m-0 mt-[3px] font-serif text-22 font-semibold">{d.title}</h2>
          <div className="mt-[3px] text-12.5 text-ink-2">
            {d.links.primary ? (
              <>
                {t('header.linkedTo')} <Link href={recordHref(d.links.primary.entity, d.links.primary.id) as Route} className="font-bold text-ink">{text.link(d.links.primary)}</Link>
              </>
            ) : d.linked ? (
              <span className="text-muted">{t('header.linkedHidden')}</span>
            ) : (
              <span className="rounded-999 bg-peach px-[9px] py-[2px] text-11.5 font-bold text-danger">{t('header.notLinked')}</span>
            )}
            {d.can_edit ? (
              <button type="button" onClick={() => setLinking(true)} className="ml-2 cursor-pointer border-none bg-transparent p-0 text-12.5 font-semibold text-link hover:underline">
                {d.linked ? t('header.changeLink') : t('header.linkTo')}
              </button>
            ) : null}
          </div>
        </div>
        <div className="flex flex-col items-end gap-[6px]">
          <span className="rounded-999 px-[11px] py-1 text-11.5 font-bold" style={{ background: tone.bg, color: tone.c }}>{text.state(d.state, d.capture)}</span>
          <span className="text-right text-11.5 text-muted">{noticeLine(d, capabilities, t, when)}</span>
        </div>
      </div>

      <div className="flex gap-[2px] overflow-x-auto border-0 border-b border-solid border-line" role="tablist" aria-label={t('tabs.label')}>
        {(['brief', 'transcript', 'suggest'] as const).map((k) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={tab === k}
            onClick={() => setTab(k)}
            className={`cursor-pointer whitespace-nowrap border-0 border-b-2 border-solid bg-transparent px-[14px] py-[9px] text-13 ${tab === k ? 'border-ink font-bold text-ink' : 'border-transparent font-medium text-muted'}`}
          >
            {t(`tabs.${k}`)}{k === 'suggest' && d.suggestions_pending > 0 ? ` · ${d.suggestions_pending}` : ''}
          </button>
        ))}
      </div>

      {tab === 'brief' ? <BriefTab key={bundle.brief?.generated_at ?? 'none'} detail={d} brief={bundle.brief} onChanged={onChanged} me={me} products={products} /> : null}
      {tab === 'transcript' ? <TranscriptTab key={d.transcript?.id ?? 'none'} bundle={bundle} capabilities={capabilities} onChanged={onChanged} me={me} /> : null}
      {tab === 'suggest' ? <SuggestionsTab detail={d} rows={bundle.suggestions} labels={bundle.labels} onChanged={onChanged} me={me} /> : null}

      <ConsentCard detail={d} capabilities={capabilities} onChanged={onChanged} me={me} />

      {linking ? <LinkModal detail={d} onClose={() => setLinking(false)} onChanged={onChanged} /> : null}
    </>
  )
}

/** The notice line under the pill (§2.1): what the recording notice did, or why there is none — never a send that did not happen. */
function noticeLine(d: Detail, caps: Capabilities, t: ReturnType<typeof useTranslations>, when: ReturnType<typeof useWhen>): string {
  if (d.cancelled_at) return t('notice.cancelled')
  if (d.recap?.saved_at) return t('notice.recapSaved')
  if (d.capture === 'bot') {
    switch (d.notice.state) {
      case 'sent': return d.notice.hours ? t('notice.sentHours', { hours: d.notice.hours }) : t('notice.sent', { at: when(d.notice.sent_at) })
      case 'pending': return t('notice.pending', { at: when(d.notice.due_at) })
      case 'blocked': return t('notice.blocked')
      default: return d.notice.setting === 'off' ? t('notice.off') : t('notice.noGuests')
    }
  }
  if (d.capture === 'desktop') return t('notice.desktop')
  if (d.capture === 'upload') return t('notice.upload')
  return caps.meeting_bot === 'connected' ? t('notice.none') : t('notice.noneNotConnected')
}

const ENTITIES = ['deal', 'lead', 'person', 'organization'] as const

/** «Link to deal…» (MTG-01 RU, MTG-07 A): one of the meeting's four links set or removed (meeting_link). */
function LinkModal({ detail, onClose, onChanged }: { detail: Detail; onClose: () => void; onChanged: () => Promise<void> }) {
  const t = useTranslations('meetings.link')
  const fail = useFail()
  const flash = useToast()
  const [entity, setEntity] = useState<(typeof ENTITIES)[number]>('deal')
  const [busy, setBusy] = useState(false)
  const save = async (k: (typeof ENTITIES)[number], value: string | null) => {
    setBusy(true)
    const r = await linkMeeting({ id: detail.id, values: { [`${k}_id`]: value }, version: detail.version })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    flash(value ? t('linked') : t('unlinked'))
    await onChanged()
    if (value) onClose()
  }
  const current = ENTITIES.map((k) => [k, detail.links[k]] as const).filter((x): x is readonly [(typeof ENTITIES)[number], LinkRef] => !!x[1])
  return (
    <Modal eyebrow={t('eyebrow')} title={detail.title} onClose={onClose} width={500}>
      {current.length ? (
        <div className="flex flex-col gap-1">
          {current.map(([k, l]) => (
            <div key={k} className="flex items-center justify-between gap-2 border-0 border-b border-solid border-line py-[6px] text-13">
              <span><span className="text-muted">{t(`entity.${k}`)}</span> · <b>{l.entity === 'lead' ? `L-${l.seq ?? ''} · ${l.title ?? ''}` : l.title}</b></span>
              <button type="button" disabled={busy} onClick={() => void save(k, null)} className="h-[30px] cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold disabled:opacity-60">{t('remove')}</button>
            </div>
          ))}
        </div>
      ) : <p className="m-0 text-13 text-muted">{t('none')}</p>}
      <div className={field}>
        {t('to')}
        <div className="flex flex-wrap gap-[6px]">
          {ENTITIES.map((k) => (
            <button key={k} type="button" onClick={() => setEntity(k)} className={`cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${entity === k ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}>
              {t(`entity.${k}`)}
            </button>
          ))}
        </div>
      </div>
      <Picker key={entity} entity={entity} onPick={(h) => void save(entity, h.id)} />
      <p className="m-0 text-11.5 leading-[1.5] text-muted">{t('hint')}</p>
      <div className="flex justify-end"><button type="button" onClick={onClose} className={btnCancel}>{t('close')}</button></div>
    </Modal>
  )
}
