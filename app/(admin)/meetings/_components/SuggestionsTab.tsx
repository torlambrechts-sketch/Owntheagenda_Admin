'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { money } from '@/lib/format'
import type { RpcCode } from '@/lib/rpc'
import type { Detail, Suggestion } from '@/lib/data/meetings'
import { valueText } from '@/lib/data/meetings-shared'
import { decideSuggestions } from '../actions'
import { btn28, btn28Ghost, card18, quiet, useFail, useNum, type Me } from './kit'

type Props = { detail: Detail; rows: Suggestion[]; labels: Record<string, string>; onChanged: () => Promise<void>; me: Me }

const cols = '[grid-template-columns:110px_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1fr)_150px]'

/**
 * CRM update suggestions (MTG-05, spec §2.4): nothing is written without approval; an approved item is written with the
 * meeting as its source; an item whose record moved since the proposal is stale and never overwritten (V-P7M-15).
 */
export function SuggestionsTab({ detail, rows, labels, onChanged, me }: Props) {
  const t = useTranslations('meetings.suggest')
  const fail = useFail()
  const flash = useToast()
  const num = useNum(me)
  const [busy, setBusy] = useState(false)
  const pending = rows.filter((s) => s.state === 'pending')
  const canDecide = detail.can_edit || me.dealsAdd

  const decide = async (ids: string[], decision: 'accept' | 'reject') => {
    setBusy(true)
    const r = await decideSuggestions({ ids, decision })
    setBusy(false)
    if (!r.ok) { fail(r); return }
    const left = r.results.find((x) => x.state === 'pending' && x.error)
    const stale = r.results.filter((x) => x.state === 'stale').length
    const failed = r.results.filter((x) => x.state === 'failed').length
    if (r.written > 0) flash(t('written', { n: r.written }))
    else if (stale) flash(t('staleToast', { n: stale }))
    else if (failed) flash(t('failedToast', { n: failed }))
    else if (left) fail({ code: (left.error ?? 'failed') as RpcCode, detail: left.detail ?? null })
    await onChanged()
  }

  const fieldName = (s: Suggestion) => s.field_label ?? (t.has(`field.${s.field}`) ? t(`field.${s.field}`) : s.field.replace(/_/g, ' '))
  // a money column reads with its record's currency («120 000 kr», R-MEETINGS-04); anything else as the value is
  const show = (v: unknown, currency: string | null = null) =>
    (currency && typeof v === 'number' ? money(v, me.numberFormat, currency) : valueText(v, num, (id) => labels[id] ?? null)) ?? t('dash')

  if (rows.length === 0) {
    const why = !detail.transcript ? t('empty.noTranscript') : detail.recap?.state === 'not_connected' ? t('empty.notConnected') : detail.recap?.state === 'ready' ? t('empty.none') : t('empty.waiting')
    return (
      <div className={`${card18} flex flex-col gap-2 px-4 py-[14px]`}>
        <b className="text-13.5">{t('title')}</b>
        <span className={quiet}>{why}</span>
      </div>
    )
  }

  return (
    <div className={`${card18} overflow-hidden`}>
      <div className="flex items-center justify-between gap-2 border-0 border-b border-solid border-line px-4 py-3">
        <b className="text-13.5">{t('title')}</b>
        {pending.length > 0 && canDecide ? (
          <button type="button" disabled={busy} onClick={() => void decide(pending.map((s) => s.id), 'accept')} className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold disabled:opacity-60">
            {t('acceptAll')}
          </button>
        ) : null}
      </div>
      <div className="overflow-x-auto">
        <div className="min-w-[640px]">
          <div className={`grid gap-[10px] border-0 border-b border-solid border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${cols}`}>
            <span>{t('col.record')}</span><span>{t('col.field')}</span><span>{t('col.current')}</span><span>{t('col.proposed')}</span><span />
          </div>
          {rows.map((s) => {
            const isNew = s.field === '*new'
            const p = (isNew && s.proposed_value && typeof s.proposed_value === 'object' ? s.proposed_value : {}) as Record<string, unknown>
            const org = typeof p.organization_id === 'string' && detail.links.organization?.id === p.organization_id ? detail.links.organization.title : null
            const field = isNew ? String(p.name ?? '') : s.target_entity === 'person' ? `${s.target_title ?? t('dash')} · ${fieldName(s)}` : fieldName(s)
            const proposed = isNew ? [p.title, org].filter((x) => typeof x === 'string' && x).join(' · ') || t('dash') : show(s.proposed_value, s.currency)
            const tone = s.state === 'accepted' ? 'text-link' : s.state === 'pending' ? '' : 'text-danger'
            return (
              <div key={s.id} className={`border-0 border-b border-solid border-line px-4 py-[10px] text-12.5 ${s.state === 'accepted' ? 'bg-mint' : 'bg-transparent'}`}>
                <div className={`grid items-center gap-[10px] ${cols}`}>
                  <span className="text-muted">{isNew ? t('entity.new') : t(`entity.${s.target_entity}`)}</span>
                  <b>{field}</b>
                  <span className="text-faint">{isNew ? t('dash') : show(s.current_value, s.currency)}</span>
                  <b className="text-ok-ink">{proposed}</b>
                  <span className="flex justify-end gap-[6px]">
                    {s.state === 'pending' && canDecide ? (
                      <>
                        <button type="button" disabled={busy} onClick={() => void decide([s.id], 'reject')} className={btn28Ghost}>{t('reject')}</button>
                        <button type="button" disabled={busy} onClick={() => void decide([s.id], 'accept')} className={btn28}>{t('accept')}</button>
                      </>
                    ) : (
                      <span className={`text-right text-12 font-bold ${tone}`}>{t(`state.${s.state}`)}</span>
                    )}
                  </span>
                </div>
                {s.state === 'pending' && s.stale_now ? <div className="mt-1 text-11.5 text-warn-ink">{t('staleNow')}</div> : null}
                {s.state === 'stale' ? <div className="mt-1 text-11.5 text-muted">{t('staleDone')}</div> : null}
                {s.state === 'failed' ? <div className="mt-1 text-11.5 text-muted">{s.error_code?.includes('setting:contact_rule') ? t('failedContactRule') : t('failedRule')}</div> : null}
              </div>
            )
          })}
        </div>
      </div>
      <div className="px-4 py-[10px] text-11.5 text-faint">{t('footer')}</div>
    </div>
  )
}
