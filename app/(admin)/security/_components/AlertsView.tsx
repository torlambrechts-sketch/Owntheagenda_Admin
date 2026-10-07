'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { Alerts, Preview, Rule, Rules } from '@/lib/data/security'
import { ALERT_KEYS, DIGEST_HOURS, ISO_DAYS, cidrOk, timeOk, type AlertKey } from '@/lib/data/security-shared'
import { deleteRule, previewRules, saveRule, setAlert, setSecuritySetting, type Result } from '../actions'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { Modal, Toggle, dialogBtn, dialogCancel, sx, useErrorText, useGuarded } from './kit'

type Change = Parameters<typeof previewRules>[0]

/**
 * Alerts and rules (SEC-02, SEC-03). The six alert switches are register keys written with setting_set; the rules card
 * reads security_rules_get. Below them the controls the design leaves out (D-41): session timeout, password expiry, the
 * IP allowlist and sign-in hours with their ranges and windows, each tightening previewed first, and the self-lockout
 * refusal said in place.
 */
export function AlertsView({ alerts, rules, nf }: { alerts: Alerts | null; rules: Rules | null; nf: NumberFormat }) {
  const t = useTranslations('security.alerts')
  const numberFormat = (n: number) => formatNumber(n, nf)
  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        {alerts ? <AlertCard a={alerts} numberFormat={numberFormat} /> : <Unavailable title={t('emailTitle')} />}
        {rules ? <RulesCard r={rules} /> : <Unavailable title={t('rulesTitle')} />}
      </div>
      {rules ? <RulesEditor r={rules} /> : null}
    </div>
  )
}

function Unavailable({ title }: { title: string }) {
  const t = useTranslations('security')
  return (
    <section className={sx.card}>
      <div className={sx.headTitle}>{title}</div>
      <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('loadFailed')}</div>
    </section>
  )
}

function AlertCard({ a, numberFormat }: { a: Alerts; numberFormat: (n: number) => string }) {
  const t = useTranslations('security.alerts')
  const flash = useToast()
  const { run, busy, dialog } = useGuarded()
  const [modes, setModes] = useState<Record<string, string>>(a.settings)
  const names = a.recipients.map((r) => r.name).join(', ')
  const header = [
    a.email === 'connected' ? t('to', { names: a.recipients.map((r) => r.email).join(', ') }) : t('inAppOnly'),
    a.slack === 'connected' && a.slack_channel ? t('andSlack', { channel: a.slack_channel }) : null,
  ].filter(Boolean).join(' · ')

  const write = async (key: string, mode: string) => {
    const before = modes[key]
    setModes((m) => ({ ...m, [key]: mode }))
    const r = await run(() => (key === 'alert_digest_time' ? setSecuritySetting({ key, value: mode }) : setAlert({ key, mode })))
    if (!r.ok) setModes((m) => ({ ...m, [key]: before ?? 'off' }))
    else flash(t('saved'))
  }

  const label = (k: AlertKey) => {
    switch (k) {
      case 'alert_failed_logins': return t('keys.alert_failed_logins', { n: a.failed_logins_count })
      case 'alert_large_export': return t('keys.alert_large_export', { rows: numberFormat(a.large_export_rows) })
      default: return t(`keys.${k}`)
    }
  }

  return (
    <section className={sx.card} aria-label={t('emailTitle')}>
      {dialog}
      <div className={`${sx.head} flex-wrap`}>
        <b className="text-14">{t('emailTitle')}</b>
        <span className="text-12 text-muted">{header}</span>
      </div>
      {a.email !== 'connected' ? <div className={`${sx.row} py-[9px]`}><div className={sx.band}>{t('notConnected', { names: names || t('nobody') })}</div></div> : null}
      {ALERT_KEYS.map((k) => {
        const mode = modes[k] ?? 'off'
        const on = mode !== 'off'
        return (
          <div key={k} className={`${sx.row} flex items-center justify-between gap-[10px] py-[10px] text-12.5`}>
            <span>
              {label(k)}
              {k === 'login_alerts' && a.slack !== 'connected' ? <span className="text-faint"> · {t('slackNotConnected')}</span> : null}
            </span>
            <span className="flex flex-none items-center gap-2">
              {on ? (
                <select aria-label={t('modeLabel', { alert: label(k) })} className="h-[22px] rounded-7 border border-solid border-line bg-canvas px-1 text-11.5 text-ink disabled:opacity-60" value={mode} disabled={busy} onChange={(e) => write(k, e.target.value)}>
                  <option value="immediate">{t('modes.immediate')}</option>
                  <option value="digest">{t('modes.digest')}</option>
                </select>
              ) : null}
              <Toggle on={on} label={label(k)} disabled={busy} onChange={(v) => write(k, v ? 'immediate' : 'off')} />
            </span>
          </div>
        )
      })}
      <div className="flex flex-wrap items-center gap-2 px-[18px] py-[10px] text-11.5 text-muted">
        <label className="flex items-center gap-2">
          {t('digestAt')}
          <select className={sx.select} value={modes.alert_digest_time ?? '08:00'} disabled={busy} onChange={(e) => write('alert_digest_time', e.target.value)}>
            {DIGEST_HOURS.map((h) => <option key={h} value={h}>{h}</option>)}
          </select>
        </label>
        <span>· {t(modes.security_alert_recipients === 'list' && a.listed.length ? 'recipientsList' : 'recipientsRole', { names: names || t('nobody') })}</span>
      </div>
    </section>
  )
}

function RulesCard({ r }: { r: Rules }) {
  const t = useTranslations('security.alerts.rules')
  const ranges = r.rules.filter((x) => x.kind === 'ip_range').length
  const windows = r.rules.filter((x) => x.kind === 'time_window').length
  const rows: { k: string; v: string; tone: string }[] = [
    { k: 'strength', v: t('strengthValue'), tone: 'text-muted' },
    { k: 'expiry', v: r.password_expiry === 'days' ? t('expiryDays', { n: r.password_expiry_days ?? 90 }) : t('expiryNever'), tone: 'text-ink' },
    { k: 'reuse', v: r.password_reuse_available ? t('reuseOff') : t('reuseUnavailable'), tone: 'text-muted' },
    { k: 'ip', v: r.ip_allowlist === 'on' ? t('ipOn', { n: ranges }) : t('off'), tone: r.ip_allowlist === 'on' ? 'text-link' : 'text-muted' },
    { k: 'time', v: r.signin_hours === 'on' ? t('timeOn', { n: windows }) : t('off'), tone: r.signin_hours === 'on' ? 'text-link' : 'text-muted' },
    { k: 'timeout', v: r.session_idle === 'on_30' ? t('timeout30') : t('off'), tone: 'text-ink' },
  ]
  return (
    <section className={sx.card} aria-label={t('title')}>
      <div className={sx.headTitle}>{t('title')}</div>
      {rows.map((x) => (
        <div key={x.k} className={`${sx.row} flex justify-between gap-[10px] py-[10px] text-12.5`}>
          <span className="flex flex-col">
            <b>{t(`${x.k}.n`)}</b>
            <span className="text-11.5 text-muted">{t(`${x.k}.d`)}</span>
          </span>
          <b className={`text-right ${x.tone}`}>{x.v}</b>
        </div>
      ))}
    </section>
  )
}

/** The rules' own controls. A change that can only narrow who may sign in is previewed before it is written. */
function RulesEditor({ r }: { r: Rules }) {
  const t = useTranslations('security.alerts.edit')
  const flash = useToast()
  const err = useErrorText()
  const { run, busy, dialog } = useGuarded()
  const [lockout, setLockout] = useState<string | null>(null)
  const [confirm, setConfirm] = useState<{ title: string; preview: Preview; go: () => Promise<Result>; only: boolean } | null>(null)
  const [expiryDays, setExpiryDays] = useState(String(r.password_expiry_days ?? 90))

  const onError = (res: { code: string; detail: string | null }) => {
    if (res.detail === 'self_lockout') { setLockout(err(res)); return true }
    return false
  }
  const write = async (fn: () => Promise<Result>, ok: string) => {
    setLockout(null)
    const res = await run(fn, { onError })
    if (res.ok) flash(ok)
    return res
  }
  // preview first; the confirmation names who would have been refused and whether the change would lock the caller out
  const previewThen = async (change: Change, title: string, go: () => Promise<Result>, only = false) => {
    setLockout(null)
    const p = await run(() => previewRules(change), { onError })
    if (p.ok) setConfirm({ title, preview: p.data, go, only })
  }

  const ranges = r.rules.filter((x) => x.kind === 'ip_range')
  const windows = r.rules.filter((x) => x.kind === 'time_window')
  const ipOn = r.ip_allowlist === 'on'
  const hoursOn = r.signin_hours === 'on'

  return (
    <section className={sx.card} aria-label={t('title')}>
      {dialog}
      {confirm ? (
        <PreviewDialog
          title={confirm.title}
          preview={confirm.preview}
          previewOnly={confirm.only}
          busy={busy}
          onCancel={() => setConfirm(null)}
          onConfirm={async () => { const go = confirm.go; setConfirm(null); await write(go, t('saved')) }}
        />
      ) : null}
      <div className={sx.head}>
        <b className="text-14">{t('title')}</b>
        <span className="text-12 text-muted">{t('sub')}</span>
      </div>
      {lockout ? <div className={`${sx.row} py-[10px]`}><div role="alert" className={sx.bandDanger}><b>{t('lockoutTitle')}</b> {lockout}</div></div> : null}

      <div className={`${sx.row} flex flex-wrap items-center justify-between gap-[10px] py-[10px] text-12.5`}>
        <span className="flex flex-col"><b>{t('timeout')}</b><span className={sx.muted}>{t('timeoutHint')}</span></span>
        <select className={sx.select} aria-label={t('timeout')} value={r.session_idle} disabled={busy}
          onChange={(e) => write(() => setSecuritySetting({ key: 'session_idle', value: e.target.value }), t('saved'))}>
          <option value="on_30">{t('timeout30')}</option>
          <option value="off">{t('timeoutOff')}</option>
        </select>
      </div>

      <div className={`${sx.row} flex flex-wrap items-center justify-between gap-[10px] py-[10px] text-12.5`}>
        <span className="flex flex-col"><b>{t('expiry')}</b><span className={sx.muted}>{t('expiryHint')}</span></span>
        <span className="flex flex-wrap items-center gap-2">
          <select className={sx.select} aria-label={t('expiry')} value={r.password_expiry} disabled={busy}
            onChange={(e) => write(() => setSecuritySetting({ key: 'password_expiry', value: e.target.value, number: e.target.value === 'days' ? Number(expiryDays) || 90 : null }), t('saved'))}>
            <option value="never">{t('expiryNever')}</option>
            <option value="days">{t('expiryDaysOption')}</option>
          </select>
          {r.password_expiry === 'days' ? (
            <>
              <input className={`${sx.inputSm} w-[70px]`} type="number" min={1} max={3650} aria-label={t('expiryDaysLabel')} value={expiryDays} onChange={(e) => setExpiryDays(e.target.value)} />
              <button type="button" className={sx.btn30} disabled={busy || !(Number(expiryDays) >= 1)}
                onClick={() => write(() => setSecuritySetting({ key: 'password_expiry', value: 'days', number: Number(expiryDays) }), t('saved'))}>{t('save')}</button>
            </>
          ) : null}
        </span>
      </div>

      <RuleGroup
        kind="ip_range"
        on={ipOn}
        rules={ranges}
        busy={busy}
        onSwitch={(v) => v
          ? previewThen({ ip_allowlist: 'on' }, t('confirmAllowlist'), () => setSecuritySetting({ key: 'ip_allowlist', value: 'on' }))
          : write(() => setSecuritySetting({ key: 'ip_allowlist', value: 'off' }), t('saved'))}
        onDelete={(rule) => ipOn
          ? previewThen({ remove: rule.id }, t('confirmDelete', { label: rule.label }), () => deleteRule({ id: rule.id }))
          : write(() => deleteRule({ id: rule.id }), t('deleted'))}
        onSave={(rule, values) => {
          const go = () => saveRule({ id: rule?.id ?? null, values, version: rule?.version ?? null })
          // adding a range only widens who may sign in; editing one in force can narrow it
          return rule && ipOn ? previewThen({ rule: { id: rule.id, kind: 'ip_range', cidr: values.cidr as string } }, t('confirmEdit', { label: rule.label }), go) : write(go, t('saved'))
        }}
        onPreview={(values) => previewThen({ ip_allowlist: 'on', rule: { kind: 'ip_range', cidr: values.cidr as string } }, t('previewOnly'), async () => ({ ok: true }), true)}
      />
      <RuleGroup
        kind="time_window"
        on={hoursOn}
        rules={windows}
        busy={busy}
        onSwitch={(v) => v
          ? previewThen({ signin_hours: 'on' }, t('confirmHours'), () => setSecuritySetting({ key: 'signin_hours', value: 'on' }))
          : write(() => setSecuritySetting({ key: 'signin_hours', value: 'off' }), t('saved'))}
        onDelete={(rule) => hoursOn
          ? previewThen({ remove: rule.id }, t('confirmDelete', { label: rule.label }), () => deleteRule({ id: rule.id }))
          : write(() => deleteRule({ id: rule.id }), t('deleted'))}
        onSave={(rule, values) => {
          const go = () => saveRule({ id: rule?.id ?? null, values, version: rule?.version ?? null })
          const w = { kind: 'time_window' as const, days: values.days as number[], starts: values.starts as string, ends: values.ends as string }
          return rule && hoursOn ? previewThen({ rule: { id: rule.id, ...w } }, t('confirmEdit', { label: rule.label }), go) : write(go, t('saved'))
        }}
        onPreview={(values) => previewThen({ signin_hours: 'on', rule: { kind: 'time_window', days: values.days as number[], starts: values.starts as string, ends: values.ends as string } }, t('previewOnly'), async () => ({ ok: true }), true)}
      />
      <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('footnote')}</div>
    </section>
  )
}

type Values = Record<string, unknown>

function RuleGroup({ kind, on, rules, busy, onSwitch, onDelete, onSave, onPreview }: {
  kind: 'ip_range' | 'time_window'
  on: boolean
  rules: Rule[]
  busy: boolean
  onSwitch: (on: boolean) => unknown
  onDelete: (r: Rule) => unknown
  onSave: (r: Rule | null, values: Values) => unknown
  onPreview: (values: Values) => unknown
}) {
  const t = useTranslations('security.alerts.edit')
  const d = useTranslations('security.days')
  const [editing, setEditing] = useState<Rule | 'new' | null>(null)
  const ip = kind === 'ip_range'
  const days = (xs: number[] | null) => (xs ?? []).map((x) => d(String(x))).join(', ')
  return (
    <div className={`${sx.row} flex flex-col gap-2 py-[10px] text-12.5`}>
      <div className="flex items-center justify-between gap-[10px]">
        <span className="flex flex-col">
          <b>{t(ip ? 'allowlist' : 'hours')}</b>
          <span className={sx.muted}>{t(ip ? 'allowlistHint' : 'hoursHint')}</span>
        </span>
        <Toggle on={on} label={t(ip ? 'allowlist' : 'hours')} disabled={busy} onChange={onSwitch} />
      </div>
      {rules.length === 0 ? <span className={sx.muted}>{t(ip ? 'noRanges' : 'noWindows')}</span> : null}
      {rules.map((r) => editing !== 'new' && editing?.id === r.id ? (
        <RuleForm key={r.id} kind={kind} rule={r} busy={busy} onCancel={() => setEditing(null)} onSave={(v) => { setEditing(null); onSave(r, v) }} onPreview={onPreview} />
      ) : (
        <div key={r.id} className="flex flex-wrap items-center gap-2 rounded-10 border border-solid border-line px-[10px] py-[6px]">
          <b className="min-w-0 flex-1">{r.label}</b>
          <span className={ip ? '[font-family:ui-monospace,Menlo,monospace] text-11.5' : 'text-muted'}>{ip ? r.cidr : t('window', { days: days(r.days), starts: (r.starts ?? '').slice(0, 5), ends: (r.ends ?? '').slice(0, 5) })}</span>
          <button type="button" className={sx.btn} disabled={busy} onClick={() => setEditing(r)}>{t('edit')}</button>
          <button type="button" className={`${sx.logout} px-[10px]`} disabled={busy} onClick={() => onDelete(r)}>{t('delete')}</button>
        </div>
      ))}
      {editing === 'new' ? (
        <RuleForm kind={kind} rule={null} busy={busy} onCancel={() => setEditing(null)} onSave={(v) => { setEditing(null); onSave(null, v) }} onPreview={onPreview} />
      ) : (
        <div><button type="button" className={sx.btn} disabled={busy} onClick={() => setEditing('new')}>{t(ip ? 'addRange' : 'addWindow')}</button></div>
      )}
    </div>
  )
}

function RuleForm({ kind, rule, busy, onCancel, onSave, onPreview }: { kind: 'ip_range' | 'time_window'; rule: Rule | null; busy: boolean; onCancel: () => void; onSave: (v: Values) => void; onPreview: (v: Values) => void }) {
  const t = useTranslations('security.alerts.edit')
  const d = useTranslations('security.days')
  const [label, setLabel] = useState(rule?.label ?? '')
  const [cidr, setCidr] = useState(rule?.cidr ?? '')
  const [days, setDays] = useState<number[]>(rule?.days ?? [1, 2, 3, 4, 5])
  const [starts, setStarts] = useState((rule?.starts ?? '07:00').slice(0, 5))
  const [ends, setEnds] = useState((rule?.ends ?? '18:00').slice(0, 5))
  const ip = kind === 'ip_range'
  const valid = label.trim().length > 0 && label.trim().length <= 80 && (ip ? cidrOk(cidr) : days.length > 0 && timeOk(starts) && timeOk(ends) && starts !== ends)
  const values: Values = ip ? { kind, label: label.trim(), cidr: cidr.trim() } : { kind, label: label.trim(), days, starts, ends }
  return (
    <form className="flex flex-col gap-2 rounded-12 border border-solid border-line bg-canvas p-[10px]" onSubmit={(e) => { e.preventDefault(); if (valid) onSave(values) }}>
      <div className="flex flex-wrap gap-2">
        <label className={`${sx.label} min-w-[160px] flex-1`}>{t('label')}<input className={sx.inputSm} value={label} maxLength={80} onChange={(e) => setLabel(e.target.value)} /></label>
        {ip ? (
          <label className={`${sx.label} min-w-[160px] flex-1`}>{t('cidr')}
            <input className={`${sx.inputSm} [font-family:ui-monospace,Menlo,monospace]`} value={cidr} placeholder="193.69.41.0/24" aria-invalid={cidr !== '' && !cidrOk(cidr)} onChange={(e) => setCidr(e.target.value)} />
          </label>
        ) : (
          <>
            <label className={sx.label}>{t('starts')}<input className={sx.inputSm} type="time" value={starts} onChange={(e) => setStarts(e.target.value)} /></label>
            <label className={sx.label}>{t('ends')}<input className={sx.inputSm} type="time" value={ends} onChange={(e) => setEnds(e.target.value)} /></label>
          </>
        )}
      </div>
      {!ip ? (
        <fieldset className="m-0 flex flex-wrap gap-2 border-0 p-0">
          <legend className="mb-1 p-0 text-11.5 font-semibold text-muted">{t('daysLabel')}</legend>
          {ISO_DAYS.map((x) => (
            <label key={x} className="flex items-center gap-1 text-12">
              <input type="checkbox" checked={days.includes(x)} onChange={(e) => setDays((ds) => (e.target.checked ? [...ds, x].sort() : ds.filter((y) => y !== x)))} />
              {d(String(x))}
            </label>
          ))}
        </fieldset>
      ) : null}
      {ip && cidr !== '' && !cidrOk(cidr) ? <span className="text-11.5 font-semibold text-danger">{t('cidrHint')}</span> : null}
      <div className="flex flex-wrap justify-end gap-2">
        <button type="button" className={sx.btn30} disabled={busy || !valid} onClick={() => onPreview(values)}>{t('preview')}</button>
        <button type="button" className={`${sx.btn30} border-line font-semibold`} onClick={onCancel}>{t('cancel')}</button>
        <button type="submit" className={`${sx.btn30} bg-primary`} disabled={busy || !valid}>{t(rule ? 'save' : 'add')}</button>
      </div>
    </form>
  )
}

function PreviewDialog({ title, preview, previewOnly, busy, onCancel, onConfirm }: { title: string; preview: Preview; previewOnly: boolean; busy: boolean; onCancel: () => void; onConfirm: () => void }) {
  const t = useTranslations('security.alerts.preview')
  return (
    <Modal eyebrow={t('eyebrow')} title={title} onClose={onCancel}>
      <p className="m-0 text-13 leading-[1.5] text-muted">{t('body')}</p>
      {preview.self_lockout ? <div role="alert" className={sx.bandDanger}><b>{t('lockoutTitle')}</b> {t('lockout')}</div> : null}
      {preview.staff.length === 0 ? (
        <div className="text-13">{t('nobody')}</div>
      ) : (
        <ul className="m-0 flex list-none flex-col gap-1 p-0 text-13">
          {preview.staff.map((s) => <li key={s.staff_id}><b>{s.name ?? '—'}</b> · {t('refused', { refused: s.refused, total: s.sign_ins })}</li>)}
        </ul>
      )}
      <div className="flex justify-end gap-2">
        <button type="button" className={dialogCancel} onClick={onCancel}>{t(previewOnly ? 'close' : 'cancel')}</button>
        {previewOnly ? null : <button type="button" className={dialogBtn} disabled={busy || !!preview.self_lockout} onClick={onConfirm}>{t('confirm')}</button>}
      </div>
    </Modal>
  )
}

