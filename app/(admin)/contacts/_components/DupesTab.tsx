'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber } from '@/lib/format'
import type { Duplicate } from '@/lib/data/contacts'
import { dismissDuplicate, mergeRecords, scanDuplicates, setRule } from '../actions'
import type { TabProps } from './ContactsScreen'
import { orgNr, useError, useNav } from './util'

const RULES = ['dedupe_name', 'dedupe_email', 'dedupe_orgnr', 'dedupe_phone'] as const

/** Duplicates (Contacts.dc.html, v.dupes): the matching rules (settings) and the candidates to merge or dismiss. */
export function DupesTab({ data, rights, me }: TabProps) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const { refresh } = useNav()
  const [busy, setBusy] = useState<string | null>(null)
  const dupes = data.duplicates ?? []

  async function toggle(key: (typeof RULES)[number], on: boolean) {
    const r = await setRule({ key, on })
    if (!r.ok) return flash(err(r.code))
    refresh()
  }
  async function scan() {
    setBusy('scan')
    const r = await scanDuplicates()
    setBusy(null)
    if (!r.ok) return flash(err(r.code))
    flash(t('dupes.scanned', { count: r.n }))
    refresh()
  }
  async function merge(d: Duplicate) {
    if (!d.keep || !d.merge) return
    setBusy(d.id)
    const r = await mergeRecords({ entity: d.entity, keep: d.keep.id, merge: d.merge.id })
    setBusy(null)
    if (!r.ok) return flash(err(r.code))
    flash(t('dupes.merged'))
    refresh()
  }
  async function skip(d: Duplicate) {
    setBusy(d.id)
    const r = await dismissDuplicate({ id: d.id })
    setBusy(null)
    if (!r.ok) return flash(err(r.code))
    refresh()
  }

  const fields = (d: Duplicate) => {
    const k = d.keep!, m = d.merge!
    const rows: [string, string, string][] = d.entity === 'person'
      ? [[t('dupes.f.name'), k.name, m.name], [t('dupes.f.email'), k.email ?? '—', m.email ?? '—'], [t('dupes.f.phone'), k.phone ?? '—', m.phone ?? '—'], [t('dupes.f.organization'), k.organization ?? '—', m.organization ?? '—']]
      : [[t('dupes.f.name'), k.name, m.name], [t('dupes.f.orgnr'), orgNr(k.org_number) || '—', orgNr(m.org_number) || '—'], [t('dupes.f.city'), k.city ?? '—', m.city ?? '—']]
    return rows
  }

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(260px,320px)_minmax(0,1fr)]">
      <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('dupes.rules')}</b>
        {RULES.map((k) => (
          <label key={k} className="flex items-center gap-2 py-1 text-12.5">
            <input type="checkbox" checked={data.settings[k] === 'on'} disabled={!rights.configure} onChange={(e) => toggle(k, e.target.checked)} className="accent-ink" />
            {t(`dupes.rule.${k}`)}
          </label>
        ))}
        {!rights.configure ? <div className="text-11.5 text-faint">{t('dupes.rulesLocked')}</div> : null}
        <div className="border-t border-line pt-2 text-11.5 text-muted">
          {t.rich('dupes.approval', { b: (c) => <b>{c}</b>, state: data.settings.second_admin === 'on' ? t('on') : t('off') })}
        </div>
        <button type="button" onClick={scan} disabled={busy === 'scan'} className="h-[30px] cursor-pointer self-start rounded-9 border border-line bg-transparent px-3 text-12 font-semibold disabled:opacity-60">{t('dupes.scan')}</button>
      </div>
      <div className="flex flex-col gap-3">
        {dupes.filter((d) => d.keep && d.merge).map((d) => (
          <div key={d.id} className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
            <div className="flex items-baseline justify-between gap-2">
              <b className="text-13.5">{t(`dupes.kind.${d.entity}`)} · {t(`dupes.why.${d.rule}` as 'dupes.why.email')}</b>
              {d.score !== null ? <span className="text-12 text-muted">{t('dupes.score', { pct: formatNumber(Math.round(d.score * 100), me.nf) })}</span> : null}
            </div>
            <div className="grid gap-[6px] text-12.5 [grid-template-columns:120px_1fr_1fr]">
              <span /><b>{t('dupes.keep')}</b><b>{t('dupes.mergeInto')}</b>
              {fields(d).map(([k, a, b]) => (
                <div key={k} className="contents">
                  <span className="text-muted">{k}</span>
                  <span className="rounded-8 bg-ok-bg px-2 py-[5px]">{a}</span>
                  <span className={`rounded-8 px-2 py-[5px] ${a === b ? 'bg-ok-bg' : 'bg-tile'}`}>{b}</span>
                </div>
              ))}
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" disabled={busy === d.id} onClick={() => skip(d)} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold disabled:opacity-60">{t('dupes.notDuplicate')}</button>
              {rights.bulk ? <button type="button" disabled={busy === d.id} onClick={() => merge(d)} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-[14px] text-12 font-bold disabled:opacity-60">{t('dupes.merge')}</button> : null}
            </div>
          </div>
        ))}
        {dupes.length === 0 ? <div className="rounded-20 border border-dashed border-line-strong p-[30px] text-center text-13 text-muted">{t('dupes.empty')}</div> : null}
      </div>
    </div>
  )
}
