'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Setting, LogEntry } from '@/lib/data/settings'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { setSetting } from '../actions'
import { k, useRun } from './kit'
import { numberBounds, numberOk } from './numbers'

// the design's groups in its order, then the register's later ones (AI, Analytics, Documents) before the constants (V-SETTINGS-03, -35)
const GROUPS = ['contacts_consent', 'tracking', 'approvals_audit', 'limits', 'safeguards', 'meetings', 'ai', 'analytics', 'documents', 'platform_constant']

// a platform setting's stored row, and its value or the default
const cur = (s: Setting) => s.values.find((v) => v.scope_id === '') ?? null
const valueOf = (s: Setting) => cur(s)?.value ?? s.default

/** Rules and limits (Settings.dc.html, v.rules): the register by group, the option pills, and the change log. */
export function Rules({ settings, registry, modules, log, nf, canEdit }: {
  settings: Setting[]
  registry: string[]
  modules: string[]
  log: (LogEntry & { when: string })[]
  nf: NumberFormat
  canEdit: boolean
}) {
  const t = useTranslations('settings')
  const { opt, name } = useRuleText()
  const changedCount = settings.filter((s) => !s.fixed && valueOf(s) !== s.default).length

  const logLine = (l: LogEntry) => {
    const key = l.key ?? ''
    if (registry.includes(key)) {
      const from = l.from ? opt(key, l.from) : '—'
      const to = l.to ? opt(key, l.to) : '—'
      if (l.scope_id) {
        const scope = t.has(`entities.${l.scope_id}`) ? t(`entities.${l.scope_id}`) : l.scope_id
        return t('rules.logScoped', { name: name(key), scope, from, to })
      }
      // the same option twice: the number it carries changed (the log keeps option keys, not the number)
      if (l.from && l.from === l.to) return t('rules.logNumber', { name: name(key), value: to })
      return t('rules.logLine', { name: name(key), from, to })
    }
    if (modules.includes(key)) {
      const onOff = (v: string | null) => (v === 'on' ? t('rules.on') : v === 'off' ? t('rules.off') : '—')
      return t('rules.logLine', { name: t(`modules.items.${key}.name`), from: onOff(l.from), to: onOff(l.to) })
    }
    return `${key}: ${l.from ?? '—'} → ${l.to ?? '—'}`
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-[14px] rounded-20 bg-ink px-5 py-4 text-canvas">
        <span className="flex-[1_1_360px] text-13 leading-[1.55]">
          <b className="text-primary">{t('rules.bannerLead')}</b> {t('rules.bannerBody')}
        </span>
        <span className="text-12 text-line-mid">{t('rules.changed', { count: changedCount })}</span>
      </div>
      {!canEdit ? <div className="px-1 text-12 text-muted">{t('readOnly', { right: t('rights.configure') })}</div> : null}

      {GROUPS.map((g) => {
        const items = settings.filter((s) => s.group === g)
        return items.length ? <RuleCard key={g} title={t(`rules.groups.${g}`)} items={items} nf={nf} canEdit={canEdit} /> : null
      })}

      <div className={k.card}>
        <div className="border-b border-line px-[18px] py-[11px] text-14 font-bold">{t('rules.log')}</div>
        {log.map((l, i) => (
          <div key={i} className="grid gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 [grid-template-columns:110px_130px_minmax(0,1fr)] max-md:[grid-template-columns:70px_minmax(0,1fr)]">
            <span className="text-muted">{l.when}</span>
            <b className="truncate">{l.actor ?? t('rules.system')}</b>
            <span className="max-md:col-span-2">{logLine(l)}</span>
          </div>
        ))}
        {log.length === 0 ? <div className="px-[18px] py-[9px] text-12.5 text-muted">{t('rules.logEmpty')}</div> : null}
      </div>
    </div>
  )
}

/** A setting's texts from messages (rules.items.<key>), falling back to the register's own key. */
function useRuleText() {
  const t = useTranslations('settings')
  const opt = (key: string, o: string) => (t.has(`rules.items.${key}.options.${o}`) ? t(`rules.items.${key}.options.${o}`) : o)
  const name = (key: string) => (t.has(`rules.items.${key}.name`) ? t(`rules.items.${key}.name`) : key)
  return { opt, name }
}

/**
 * One group of the register as the design draws it (v.rules): an eyebrow head, then a row per setting with
 * its name and «Applies to», the option pills, the default and the state. A fixed setting is read-only on
 * the canvas background; a numeric option carries its number (V-SETTINGS-04). Also used by Pipelines and
 * stages for the register's pipeline group (V-SETTINGS-38).
 */
export function RuleCard({ title, items, nf, canEdit }: { title: string; items: Setting[]; nf: NumberFormat; canEdit: boolean }) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const { opt, name } = useRuleText()

  const pick = (s: Setting, o: string) => {
    if (s.fixed || !canEdit || o === valueOf(s)) return
    run(() => setSetting({ key: s.key, value: o }), () => t('rules.toast'))
  }
  // a number in its unit where the setting names one («18 months»), else the bare number
  const numberText = (key: string, n: number) =>
    t.has(`rules.items.${key}.unit`) ? t(`rules.items.${key}.unit`, { count: n, n: formatNumber(n, nf) }) : formatNumber(n, nf)
  const appliesText = (s: Setting) =>
    t.has(`rules.items.${s.key}.applies`)
      ? t(`rules.items.${s.key}.applies`)
      : s.applies_to === '*'
        ? t(`rules.items.${s.key}.everywhere`)
        : s.applies_to.replace(/ – /g, ` ${t('rules.range')} `)

  return (
    <div className={k.card}>
      <div className="border-b border-line px-[18px] py-[11px] text-11 font-bold uppercase tracking-eyebrow text-muted">{title}</div>
      {items.map((s) => {
        const value = valueOf(s)
        const number = cur(s)?.number ?? null
        const changed = !s.fixed && value !== s.default
        const label = opt(s.key, value) + (s.numeric_option === value && number !== null ? ` (${numberText(s.key, number)})` : '')
        // a default that is itself a rule (double opt-in, D-27) does not read «unrestricted»
        const stateDefault = t.has(`rules.items.${s.key}.stateDefault`) ? t(`rules.items.${s.key}.stateDefault`) : t('rules.stateDefault')
        return (
          <div
            key={s.key}
            className={`flex flex-col gap-[10px] border-b border-line px-[18px] py-3 md:grid md:items-center md:gap-[14px] md:[grid-template-columns:minmax(0,1.5fr)_minmax(220px,1.3fr)_150px] ${s.fixed ? 'bg-canvas' : changed ? 'bg-cream' : 'bg-transparent'}`}
          >
            <span className="flex flex-col gap-[3px]">
              <b className="text-13">{name(s.key)}</b>
              <span className="text-11.5 text-muted">{t('rules.appliesTo', { what: appliesText(s) })}</span>
            </span>
            <span className="flex flex-wrap items-center gap-1" role="group" aria-label={name(s.key)}>
              {s.options.map((o) => {
                const on = value === o
                return (
                  <button
                    key={o}
                    type="button"
                    aria-pressed={on}
                    disabled={s.fixed || !canEdit || pending}
                    onClick={() => pick(s, o)}
                    className={`cursor-pointer rounded-999 border px-[10px] py-[5px] text-11.5 disabled:cursor-default ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
                  >
                    {opt(s.key, o)}
                  </button>
                )
              })}
              {s.numeric_option && value === s.numeric_option && !s.fixed ? (
                <NumberInput
                  key={`${s.key}-${number ?? ''}`}
                  settingKey={s.key}
                  initial={number}
                  label={t('rules.numberLabel', { name: name(s.key) })}
                  save={t('rules.numberSave')}
                  disabled={!canEdit || pending}
                  onSave={(n) => run(() => setSetting({ key: s.key, value: s.numeric_option!, number: n }), () => t('rules.toast'))}
                />
              ) : null}
            </span>
            <span className="flex flex-col gap-[2px] text-11.5 md:text-right">
              <span className="text-muted">
                {t('rules.default')} <b className="text-ink">{opt(s.key, s.default)}</b>
              </span>
              <span className={`font-bold ${s.fixed ? 'text-danger' : changed ? 'text-warn-ink' : 'text-link'}`}>
                {s.fixed ? t('rules.stateFixed') : changed ? t('rules.stateChanged', { value: label }) : stateDefault}
              </span>
            </span>
          </div>
        )
      })}
    </div>
  )
}

/** The number the design's «A number» / «Custom» options take (a gap in the design, built in its language: D-41). */
function NumberInput({ settingKey, initial, label, save, disabled, onSave }: { settingKey: string; initial: number | null; label: string; save: string; disabled: boolean; onSave: (n: number) => void }) {
  const [v, setV] = useState(initial === null ? '' : String(initial))
  const n = Number(v)
  const b = numberBounds(settingKey)
  const ok = v.trim() !== '' && numberOk(settingKey, n) && n !== initial
  return (
    <form
      className="flex items-center gap-1"
      onSubmit={(e) => {
        e.preventDefault()
        if (ok) onSave(n)
      }}
    >
      <input
        type="number"
        min={b.min}
        max={b.max}
        step={b.int ? 1 : 'any'}
        inputMode="numeric"
        aria-label={label}
        value={v}
        disabled={disabled}
        onChange={(e) => setV(e.target.value)}
        className="h-[27px] w-[76px] rounded-999 border border-line-strong bg-canvas px-[10px] text-11.5 text-ink"
      />
      <button type="submit" disabled={disabled || !ok} className="cursor-pointer rounded-999 border border-line-strong bg-transparent px-[10px] py-[5px] text-11.5 font-medium text-ink disabled:cursor-default disabled:opacity-50">
        {save}
      </button>
    </form>
  )
}
