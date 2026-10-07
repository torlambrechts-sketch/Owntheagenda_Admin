'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Firewall, Protection } from '@/lib/data/security'
import { FIREWALL_CHECKS } from '@/lib/data/security-shared'
import { restoreTestRecord } from '../actions'
import { sx, useGuarded, useWhen } from './kit'

/**
 * Data protection (SEC-10): the firewall's six claims, each proved live by firewall_status(); the reviewed platform
 * facts (platform_facts, eu-central-1 per D-35); backups and restore tests from ops_checks — empty until the backup
 * worker reports or staff record a test, never a time nobody recorded. The anonymity guardrails panel is left out
 * (D-19, V-SECURITY-12).
 */
export function ProtectView({ firewall, protection, now }: { firewall: Firewall | null; protection: Protection | null; now: string }) {
  const t = useTranslations('security.protect')
  const when = useWhen(now)
  const minutes = (m: number) => (m % 60 === 0 ? t('hours', { n: m / 60 }) : t('minutes', { n: m }))
  const p = protection
  const fact = (k: string) => p?.facts[k]?.value ?? '—'
  const rows: { k: string; v: string }[] = p ? [
    { k: 'transit', v: fact('encryption_in_transit') },
    { k: 'rest', v: fact('encryption_at_rest') },
    { k: 'hosting', v: fact('hosting_region_label') },
    { k: 'isolation', v: fact('isolation') },
    { k: 'backup', v: p.last_backup ? when(p.last_backup.at) : t('noBackup') },
    {
      k: 'restore',
      v: p.last_restore_test
        ? [when(p.last_restore_test.at, { time: false }), t(p.last_restore_test.ok ? 'passed' : 'failedTest'), ...(p.last_restore_test.ok && p.last_restore_test.meets_objectives === false ? [t('missesObjectives')] : [])].join(' · ')
        : t('noRestore'),
    },
    { k: 'objectives', v: t('objectivesValue', { rpo: minutes(p.objectives.rpo_minutes), rto: minutes(p.objectives.rto_minutes) }) },
  ] : []

  return (
    <div className="flex flex-col gap-[14px]">
      <section className="flex flex-col gap-[10px] rounded-20 bg-ink px-[22px] py-[18px] text-canvas" aria-label={t('eyebrow')}>
        <span className="text-11 font-bold uppercase tracking-eyebrow text-amber-bg">{t('eyebrow')}</span>
        <span className="font-serif text-22 font-semibold leading-[1.25]">{t('headline')}</span>
        {firewall ? (
          <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))]">
            {FIREWALL_CHECKS.map((k) => {
              const ok = firewall.checks.find((c) => c.key === k)?.ok ?? false
              return (
                <div key={k} className="rounded-14 border border-solid border-[rgba(252,246,233,.2)] px-3 py-[10px] text-12 leading-[1.5]">
                  <b className={ok ? 'text-primary' : 'text-coral-light'}>{ok ? '✓' : '✗'} {t(`checks.${k}.n`)}</b>
                  <div className="text-line-mid">{ok ? t(`checks.${k}.d`) : t('checkFailed')}</div>
                </div>
              )
            })}
          </div>
        ) : <span className="text-12 text-line-mid">{t('firewallUnavailable')}</span>}
      </section>

      {/* auto-fill keeps the design's two-column track although the guardrails panel beside it is left out (V-SECURITY-12) */}
      <div className="grid gap-[14px] [grid-template-columns:repeat(auto-fill,minmax(min(100%,380px),1fr))]">
        <section className={sx.card} aria-label={t('title')}>
          <div className={sx.headTitle}>{t('title')}</div>
          {p ? (
            <>
              {p.pitr_warning ? <div className={`${sx.row} py-[9px]`}><div className={sx.band}>{t('pitrWarning')}</div></div> : null}
              {rows.map((r) => (
                <div key={r.k} className={`${sx.row} flex justify-between gap-[10px] py-[9px] text-12.5`}>
                  <span className="text-muted">{t(`rows.${r.k}`)}</span>
                  <b className="text-right">{r.v}</b>
                </div>
              ))}
              <RestoreTest />
            </>
          ) : <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('loadFailed')}</div>}
        </section>
      </div>
    </div>
  )
}

/** SF-43.5 / SEC-10 AC: staff record a restore test; it meets the objectives when RPO ≤ 60 and RTO ≤ 240 (D-35). */
function RestoreTest() {
  const t = useTranslations('security.protect.restoreForm')
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [open, setOpen] = useState(false)
  const [at, setAt] = useState('')
  const [ok, setOk] = useState(true)
  const [rpo, setRpo] = useState('')
  const [rto, setRto] = useState('')
  const [note, setNote] = useState('')
  const valid = at !== '' && /^\d+$/.test(rpo) && /^\d+$/.test(rto)
  if (!open) {
    return <div className="px-[18px] py-[10px]"><button type="button" className={sx.btn} onClick={() => setOpen(true)}>{t('open')}</button></div>
  }
  return (
    <form className="flex flex-col gap-2 px-[18px] py-[10px]" onSubmit={async (e) => {
      e.preventDefault()
      if (!valid) return
      const r = await run(() => restoreTestRecord({ at: new Date(at).toISOString(), ok, rpo: Number(rpo), rto: Number(rto), note: note.trim() || null }))
      if (r.ok) { flash(t(r.meets ? 'meets' : 'misses')); setOpen(false) }
    }}>
      {dialog}
      <div className="flex flex-wrap gap-2">
        <label className={sx.label}>{t('at')}<input className={sx.inputSm} type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} /></label>
        <label className={sx.label}>{t('rpo')}<input className={`${sx.inputSm} w-[90px]`} type="number" min={0} value={rpo} onChange={(e) => setRpo(e.target.value)} /></label>
        <label className={sx.label}>{t('rto')}<input className={`${sx.inputSm} w-[90px]`} type="number" min={0} value={rto} onChange={(e) => setRto(e.target.value)} /></label>
        <label className="flex items-end gap-1 pb-[6px] text-12"><input type="checkbox" checked={ok} onChange={(e) => setOk(e.target.checked)} />{t('passed')}</label>
      </div>
      <label className={sx.label}>{t('note')}<input className={sx.inputSm} maxLength={300} value={note} onChange={(e) => setNote(e.target.value)} /></label>
      <div className="flex justify-end gap-2">
        <button type="button" className={`${sx.btn30} border-line font-semibold`} onClick={() => setOpen(false)}>{t('cancel')}</button>
        <button type="submit" className={`${sx.btn30} bg-primary`} disabled={busy || !valid}>{t('save')}</button>
      </div>
    </form>
  )
}
