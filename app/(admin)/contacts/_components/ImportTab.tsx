'use client'

import { useRef, useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber } from '@/lib/format'
import { IMPORT_ENTITIES, KNOWN_REASONS, MAX_BYTES, targetsFor, type ImportEntity } from '@/lib/data/contacts-import'
import { toCsv } from '@/lib/data/contacts-export'
import { importCheck, importPreview, importRevert, importRun, importSkips } from '../actions'
import type { TabProps } from './ContactsScreen'
import { download, useError, useNav } from './util'

type FileState = { name: string; text: string; rows: number; headers: string[] }
type Result = { id: string; rows_read: number; created: number; merged: number; skipped: number }
const btnGhost = 'h-9 cursor-pointer rounded-10 border border-line bg-transparent px-[14px] text-12.5 font-semibold disabled:cursor-default disabled:opacity-50'
const btnPrimary = 'h-9 cursor-pointer rounded-10 border border-ink bg-primary px-4 text-12.5 font-bold disabled:cursor-default disabled:opacity-50'

/** Import (Contacts.dc.html, v.import): upload, map fields, duplicates, result; and the history. */
export function ImportTab({ data, rights, me }: TabProps) {
  const t = useTranslations('contacts')
  const format = useFormatter()
  const flash = useToast()
  const err = useError()
  const { refresh } = useNav()
  const input = useRef<HTMLInputElement>(null)
  const [step, setStep] = useState(1)
  const [entity, setEntity] = useState<ImportEntity>('person')
  const [file, setFile] = useState<FileState | null>(null)
  const [mapping, setMapping] = useState<(string | null)[]>([])
  const [mode, setMode] = useState<'merge' | 'create' | 'skip'>('merge')
  const settingConsent = data.settings.import_consent === 'required_per_row'
  const [consent, setConsent] = useState(false)
  const [matches, setMatches] = useState<number | null>(null)
  const [result, setResult] = useState<Result | null>(null)
  const [reverted, setReverted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [drag, setDrag] = useState(false)
  const custom = data.fields.filter((f) => f.entity === entity && !f.readonly && !f.formula).map((f) => ({ key: f.key, label: f.label, type: f.type }))
  const targets = targetsFor(entity, custom).filter((x) => entity !== 'person' || !x.key.startsWith('consent_') || consent || settingConsent)
  const nf = me.nf

  const targetLabel = (key: string) => {
    if (key.startsWith('custom.')) return t('import.field.custom', { label: custom.find((c) => `custom.${c.key}` === key)?.label ?? key })
    return t(`import.field.${entity}.${key}` as 'import.field.person.name')
  }

  async function take(f: File) {
    if (/\.xlsx?$/i.test(f.name)) return flash(err('xlsx'))
    if (f.size > MAX_BYTES) return flash(err('too_large'))
    const text = await f.text()
    setBusy(true)
    const r = await importPreview({ entity, text })
    setBusy(false)
    if (!r.ok) return flash(err(r.code))
    setFile({ name: f.name, text, rows: r.rows, headers: r.headers })
    setMapping(r.mapping)
  }
  async function chooseEntity(e: ImportEntity) {
    setEntity(e)
    if (!file) return
    const r = await importPreview({ entity: e, text: file.text })
    if (r.ok) setMapping(r.mapping)
  }

  async function nextStep() {
    if (step === 1) return setStep(2)
    if (step === 2 && file) {
      setBusy(true)
      const r = await importCheck({ entity, text: file.text, mapping })
      setBusy(false)
      if (!r.ok) return flash(err(r.code))
      setMatches(r.matches)
      return setStep(3)
    }
    if (step === 3 && file) {
      setBusy(true)
      const r = await importRun({ entity, text: file.text, file: file.name, mapping, mode: entity === 'lead' ? 'create' : mode, consent: entity === 'person' && (consent || settingConsent) })
      setBusy(false)
      if (!r.ok) return flash(err(r.code))
      setResult(r); setReverted(false); setStep(4)
      return refresh()
    }
    // «Start a new import»
    setStep(1); setFile(null); setMapping([]); setResult(null); setMatches(null)
  }

  async function skipFile() {
    if (!result) return
    const r = await importSkips({ id: result.id })
    if (!r.ok) return flash(err(r.code))
    const reason = (x: string | null) => (x && (KNOWN_REASONS as readonly string[]).includes(x) ? t(`import.reasons.${x}` as 'import.reasons.duplicate') : (x ?? ''))
    download(`${(file?.name ?? 'import').replace(/\.[^.]+$/, '')}-skipped.csv`, toCsv([t('import.skipRow'), t('import.skipReason')], r.rows.map((x) => [x.row, reason(x.reason)])))
  }
  async function revert() {
    if (!result) return
    const r = await importRevert({ id: result.id })
    if (!r.ok) return flash(err(r.code))
    setReverted(true)
    flash(t('import.reverted', { created: result.created, merged: result.merged }))
    refresh()
  }

  const steps = ['upload', 'map', 'dupes', 'result'] as const
  const canNext = step === 1 ? !!file && mapping.some(Boolean) && rights.add : step === 2 ? mapping.some(Boolean) : true
  const nextLabel = [t('import.continue'), t('import.continue'), t('import.run'), t('import.again')][step - 1]

  return (
    <div className="flex flex-col gap-[14px]">
      <ol className="m-0 flex list-none gap-[6px] p-0">
        {steps.map((s, i) => {
          const n = i + 1
          return (
            <li key={s} aria-current={n === step ? 'step' : undefined} className={`flex min-w-0 flex-1 items-center gap-2 rounded-14 border px-3 py-[10px] ${n === step ? 'border-ink bg-highlight' : 'border-line bg-surface'}`}>
              <span className={`flex h-[22px] w-[22px] flex-none items-center justify-center rounded-999 text-11 font-bold ${n <= step ? 'bg-ink text-highlight' : 'bg-tile text-muted'}`}>{n < step ? '✓' : n}</span>
              <b className="truncate text-12.5">{t(`import.steps.${s}`)}</b>
            </li>
          )
        })}
      </ol>
      <div className="flex flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        {step === 1 ? (
          <div className="flex flex-col gap-3">
            <b className="text-15">{t('import.uploadTitle')}</b>
            <div className="flex flex-wrap gap-[6px]">
              {IMPORT_ENTITIES.map((e) => (
                <button key={e} type="button" onClick={() => chooseEntity(e)} aria-pressed={entity === e}
                  className={`cursor-pointer rounded-999 border px-[13px] py-[7px] text-12.5 ${entity === e ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
                  {t(`import.entity.${e}`)}
                </button>
              ))}
            </div>
            <label
              onDragOver={(e) => { e.preventDefault(); setDrag(true) }}
              onDragLeave={() => setDrag(false)}
              onDrop={(e) => { e.preventDefault(); setDrag(false); const f = e.dataTransfer.files[0]; if (f) void take(f) }}
              className={`flex h-[120px] cursor-pointer flex-col has-[:focus-visible]:outline has-[:focus-visible]:outline-[3px] has-[:focus-visible]:outline-ink items-center justify-center gap-1 rounded-16 border border-dashed border-line-strong text-center text-13 text-muted ${drag ? 'bg-highlight' : 'bg-canvas'}`}
            >
              <input ref={input} type="file" accept=".csv,text/csv,.xlsx" className="sr-only" disabled={!rights.add} onChange={(e) => { const f = e.target.files?.[0]; if (f) void take(f); e.target.value = '' }} />
              <span>{busy ? t('import.reading') : t('import.drop')}</span>
              <span className="text-11.5 text-faint">{t('import.noXlsx')}</span>
            </label>
            {file ? (
              <div className="flex flex-wrap gap-2">
                <span className="rounded-12 border border-line px-3 py-[7px] text-12.5">▦ {file.name} · {t('import.rows', { count: file.rows, n: formatNumber(file.rows, nf) })}</span>
              </div>
            ) : null}
            {entity === 'person' ? (
              <label className="flex items-center gap-2 text-12.5">
                <input type="checkbox" checked={consent || settingConsent} disabled={settingConsent} onChange={(e) => setConsent(e.target.checked)} className="accent-ink" />
                {settingConsent ? t('import.consentOn') : t('import.consentOff')}
              </label>
            ) : null}
          </div>
        ) : null}

        {step === 2 && file ? (
          <div className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <b className="text-15">{t('import.mapTitle')}</b>
              <span className="text-12 text-muted">{t('import.mapHint')}</span>
            </div>
            {file.headers.map((h, i) => (
              <div key={`${h}-${i}`} className="grid items-center gap-[10px] border-b border-line py-[7px] text-12.5 [grid-template-columns:minmax(0,1fr)_24px_minmax(0,1fr)] md:[grid-template-columns:minmax(0,1fr)_24px_minmax(0,1fr)_90px]">
                <span className="truncate font-mono text-12">{h}</span>
                <span className="text-faint">→</span>
                <select value={mapping[i] ?? ''} aria-label={t('import.mapFor', { column: h })} onChange={(e) => setMapping(mapping.map((m, j) => (j === i ? e.target.value || null : m === e.target.value && e.target.value ? null : m)))}
                  className="h-8 min-w-0 rounded-9 border border-line bg-canvas text-12.5 text-ink">
                  <option value="">{t('import.skipColumn')}</option>
                  {targets.map((x) => <option key={x.key} value={x.key}>{targetLabel(x.key)}</option>)}
                </select>
                <span className="hidden md:block" />
              </div>
            ))}
          </div>
        ) : null}

        {step === 3 ? (
          <div className="flex flex-col gap-[10px]">
            <b className="text-15">{matches === null ? t('import.leadsAlwaysNew') : matches ? t('import.matches', { count: matches, n: formatNumber(matches, nf) }) : t('import.noMatches')}</b>
            {matches !== null ? (
              <div className="flex flex-col gap-2 md:flex-row">
                {(['merge', 'create', 'skip'] as const).map((m) => (
                  <button key={m} type="button" onClick={() => setMode(m)} aria-pressed={mode === m}
                    className={`flex-1 cursor-pointer rounded-14 border p-3 text-left text-12.5 ${mode === m ? 'border-ink bg-highlight font-bold' : 'border-line bg-transparent font-semibold'}`}>
                    {t(`import.mode.${m}`)}
                    <div className="mt-[3px] text-11.5 font-normal text-muted">{t(`import.modeSub.${m}`)}</div>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}

        {step === 4 && result ? (
          <div className="flex flex-col gap-3">
            <b className="text-15">{t('import.doneTitle')}</b>
            <div className="grid grid-cols-2 gap-[10px] md:grid-cols-4">
              {([['created', result.created, 'bg-ok-bg'], ['merged', result.merged, 'bg-teal-soft'], ['skipped', result.skipped, 'bg-highlight'], ['read', result.rows_read, 'bg-tile']] as const).map(([k, v, bg]) => (
                <div key={k} className={`rounded-15 px-[14px] py-3 ${bg}`}>
                  <div className="font-serif text-26 font-semibold">{formatNumber(v, nf)}</div>
                  <div className="text-12">{t(`import.result.${k}`)}</div>
                </div>
              ))}
            </div>
            <div className="flex flex-wrap gap-2">
              <button type="button" disabled={!result.skipped} onClick={skipFile} className="h-[34px] cursor-pointer rounded-10 border border-ink bg-surface px-[13px] text-12.5 font-bold disabled:cursor-default disabled:opacity-50">{t('import.skipFile', { count: result.skipped, n: formatNumber(result.skipped, nf) })}</button>
              {rights.del ? (
                <button type="button" disabled={reverted} onClick={revert} className="h-[34px] cursor-pointer rounded-10 border border-coral bg-transparent px-[13px] text-12.5 font-semibold text-rust disabled:cursor-default disabled:opacity-50">{reverted ? t('import.revertedState') : t('import.revert')}</button>
              ) : null}
            </div>
          </div>
        ) : null}

        <div className="flex justify-between border-t border-line pt-3">
          <button type="button" disabled={step === 1 || step === 4 || busy} onClick={() => setStep(Math.max(1, step - 1))} className={btnGhost}>{t('import.back')}</button>
          <button type="button" disabled={!canNext || busy} onClick={nextStep} className={btnPrimary}>{nextLabel}</button>
        </div>
      </div>

      <div className="overflow-hidden rounded-20 border border-line bg-surface">
        <div className="border-b border-line px-[18px] py-3 text-14 font-bold">{t('import.history')}</div>
        <div className="overflow-x-auto">
          <div className="min-w-[640px]">
            {(data.imports ?? []).map((h) => (
              <div key={h.id} className="grid gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:minmax(0,1.4fr)_120px_90px_90px_90px_110px]">
                <b className="truncate">{h.file_name ?? t(`import.entity.${h.entity as ImportEntity}`)}</b>
                <span className="text-muted">{format.dateTime(new Date(h.created_at), { day: 'numeric', month: 'short' })}{h.status === 'reverted' ? ` · ${t('import.revertedShort')}` : ''}</span>
                <span>{t('import.hCreated', { n: formatNumber(h.created, nf) })}</span>
                <span>{t('import.hMerged', { n: formatNumber(h.merged, nf) })}</span>
                <span>{t('import.hSkipped', { n: formatNumber(h.skipped, nf) })}</span>
                <span className="truncate text-muted">{h.by ?? '—'}</span>
              </div>
            ))}
            {(data.imports ?? []).length === 0 ? <div className="px-[18px] py-[14px] text-12.5 text-muted">{t('import.noHistory')}</div> : null}
          </div>
        </div>
      </div>
    </div>
  )
}
