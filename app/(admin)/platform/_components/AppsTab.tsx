'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useCallback, useEffect, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import type { Notice } from '@/lib/data/platform'
import type { Health } from '@/lib/data/platform-shared'
import type { SimpleApp } from '@/lib/data/simple-platform'
import { testConnection } from '../../applications/actions'
import { ConnectDialog } from '../../applications/_components/AppsView'
import { Dialog, useAct, useAgo, useErrorText } from '../../applications/_components/kit'
import { fetchProductFlags, publishNotice, setProductFlag, type ProductFlag } from '../actions'
import type { EmailProvider } from '@/lib/mail/provider'
import { EmailCard } from './EmailCard'

/** The design's status pill per health (Operational, Degraded, Beta, Maintenance colours of SimplePlatform.dc.html). */
const PILL: Record<Health, string> = {
  operational: 'bg-ok-bg text-ok-ink',
  degraded: 'bg-amber-bg text-amber-ink',
  unreachable: 'bg-peach text-rust-ink',
  no_data: 'bg-beige text-muted',
  disabled: 'bg-beige text-muted',
  not_installed: 'bg-beige text-muted',
}
const mono = 'font-[ui-monospace,Menlo,monospace]'

/**
 * Applications (SimplePlatform.dc.html, v.apps): a card per application with its accounts and health, Test connection and
 * Maintenance mode; «＋ Connect an application»; the chosen application's feature flags, its secrets and its status message.
 * Response and errors are «—» until calls are logged (V-SPL-02); maintenance has no product command (V-SPL-03).
 */
export function AppsTab({ apps, current, name, notice, flags, canConfigure, owner, nf, email }: {
  apps: SimpleApp[]
  current: string
  name: string
  notice: Notice | null
  flags: { flags_command: boolean; set_command: boolean } | null
  canConfigure: boolean
  owner: boolean
  nf: NumberFormat
  /** the mail provider (Brevo, 0060); null when it could not be read */
  email: EmailProvider | null
}) {
  const t = useTranslations('simplePlatform.apps')
  const [connect, setConnect] = useState(false)
  const cur = apps.find((a) => a.key === current) ?? null
  const installed = apps.filter((a) => a.installed)

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
        {apps.map((a) => <AppCard key={a.key} a={a} current={a.key === current} nf={nf} />)}
        <button
          type="button"
          disabled={!owner}
          onClick={() => setConnect(true)}
          className="flex min-h-[180px] cursor-pointer flex-col items-center justify-center gap-1 rounded-20 border-2 border-dashed border-line-strong bg-transparent text-13.5 font-bold disabled:cursor-default"
        >
          {t('connect')}
          {!owner ? <span className="max-w-[220px] text-11.5 font-normal text-muted">{t('connectOwner')}</span> : null}
        </button>
      </div>

      <div className="flex flex-col gap-1 text-12 text-muted">
        {installed.some((a) => a.p95_ms === null || a.error_rate === null) ? <span>{t('notes.latency')}</span> : null}
        {installed.some((a) => !a.maintenance) ? <span>{t('notes.maintenance')}</span> : null}
        {installed.some((a) => !a.testable) ? <span>{t('notes.test')}</span> : null}
      </div>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
        <FlagsCard key={current} product={current} name={name} flags={flags} canConfigure={canConfigure} />
        <KeyAndNotice key={`${current}:${notice?.current?.id ?? ''}`} app={cur} product={current} name={name} notice={notice} canConfigure={canConfigure} />
        {email ? <EmailCard p={email} apps={apps.map((a) => ({ key: a.key, name: a.name }))} current={current} /> : null}
      </div>
      {connect ? <ConnectDialog onClose={() => setConnect(false)} /> : null}
    </div>
  )
}

function AppCard({ a, current, nf }: { a: SimpleApp; current: boolean; nf: NumberFormat }) {
  const t = useTranslations('simplePlatform.apps')
  const { flash, errText } = useAct()
  const [pending, start] = useTransition()
  const slow = a.p95_ms !== null && a.p95_ms > 500
  const failing = a.error_rate !== null && a.error_rate > 0.015
  // the answer is shown, not stored: product-command does not record a ping yet (testConnection, V-SPL-02)
  const test = () => start(async () => {
    const r = await testConnection(a.key)
    if (r.ok) flash(t('testOk', { name: a.name, ms: formatNumber(r.ms, nf) }))
    else flash(r.code === 'not_connected' ? t('testFailed', { name: a.name, code: r.detail ?? 'failed' }) : errText(r))
  })

  return (
    <div className={`flex flex-col gap-[10px] rounded-20 border bg-surface px-[18px] py-4 ${current ? 'border-ink' : 'border-line'}`}>
      <div className="flex items-center gap-[10px]">
        <span
          className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-12 border border-[rgba(25,21,16,.1)] font-serif text-17 font-bold"
          style={{ background: a.color ?? '#F2EAD6', color: a.ink ?? '#191510' }}
        >
          {a.name.slice(0, 1)}
        </span>
        <span className="flex min-w-0 flex-1 flex-col">
          <b className="text-14">{a.name}</b>
          <span className="text-11.5 text-muted">{a.description ?? '—'}</span>
        </span>
        <span className={`flex-none rounded-999 px-[10px] py-[3px] text-11 font-bold ${PILL[a.status]}`}>{t(`status.${a.status}`)}</span>
      </div>
      <div className="grid grid-cols-3 gap-[6px] text-11 text-muted">
        <span className="flex flex-col"><b className="text-14 text-ink">{formatNumber(a.orgs, nf)}</b>{t('accounts')}</span>
        <span className="flex flex-col"><b className={`text-14 ${slow ? 'text-danger' : 'text-ink'}`}>{a.p95_ms !== null ? `${formatNumber(a.p95_ms, nf)} ms` : '—'}</b>{t('response')}</span>
        <span className="flex flex-col"><b className={`text-14 ${failing ? 'text-danger' : 'text-ink'}`}>{a.error_rate !== null ? percent(a.error_rate * 100, nf) : '—'}</b>{t('errors')}</span>
      </div>
      <div className={`${mono} text-11.5 text-muted`}>{a.host ?? '—'} · {a.version ?? '—'}</div>
      <div className="flex gap-[6px]">
        <button
          type="button"
          disabled={!a.testable || pending}
          title={a.testable ? undefined : t('notes.test')}
          onClick={test}
          className="h-8 flex-1 cursor-pointer rounded-9 border border-ink bg-surface text-12 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {t('test')}
        </button>
        {a.maintenance ? (
          // the confirmed flow (owner, fresh second factor, the key typed) lives with the banner on the Platform screen
          <Link
            href={`/applications?tab=flags&app=${a.key}` as Route}
            className="flex h-8 flex-1 items-center justify-center rounded-9 border border-line bg-transparent text-12 font-semibold text-ink hover:text-ink hover:no-underline"
          >
            {t('maintenance')}
          </Link>
        ) : (
          <button
            type="button"
            disabled
            title={t('notes.maintenance')}
            className="h-8 flex-1 cursor-default rounded-9 border border-line bg-transparent text-12 font-semibold opacity-60"
          >
            {t('maintenance')}
          </button>
        )}
      </div>
    </div>
  )
}

/** The design's switch: 42×24 track, an 18 px knob at 3 or 21. */
function Toggle({ on, label, disabled, onClick }: { on: boolean; label: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className={`relative h-6 w-[42px] flex-none cursor-pointer whitespace-nowrap rounded-999 border-none disabled:cursor-default disabled:opacity-60 ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span className="absolute top-[3px] h-[18px] w-[18px] rounded-999 bg-surface" style={{ left: on ? 21 : 3 }} />
    </button>
  )
}

type FlagsState = { kind: 'loading' } | { kind: 'error'; code: string } | { kind: 'ready'; flags: ProductFlag[] }

/**
 * Feature flags · <application> (v.apps, «flags»): the product's own modules, read through its modules.list when the card
 * opens (not on every page render), switched through modules.set_status — one way, with a reason (V-SPL-04).
 */
function FlagsCard({ product, name, flags, canConfigure }: {
  product: string; name: string; flags: { flags_command: boolean; set_command: boolean } | null; canConfigure: boolean
}) {
  const t = useTranslations('simplePlatform.flags')
  const [state, setState] = useState<FlagsState>({ kind: 'loading' })
  const [ask, setAsk] = useState<ProductFlag | null>(null)
  const readable = !!flags?.flags_command

  const load = useCallback(async () => {
    setState({ kind: 'loading' })
    const r = await fetchProductFlags(product)
    setState(r.ok ? { kind: 'ready', flags: r.flags } : { kind: 'error', code: r.detail ?? r.code })
  }, [product])
  useEffect(() => { if (readable) void load() }, [readable, load])

  const row = 'flex items-center justify-between gap-[10px] border-b border-line px-[18px] py-[11px]'
  const note = 'border-b border-line px-[18px] py-[11px] text-12.5 text-muted'
  return (
    <div className="overflow-hidden rounded-20 border border-line bg-surface">
      <div className="flex items-center justify-between gap-[10px] border-b border-line px-[18px] py-[14px]">
        <b className="text-15">{t('title', { name })}</b>
        <span className="text-12 text-muted">{t('everyAccount')}</span>
      </div>
      {!readable ? <div className={note}>{t('noCommand', { name })}</div>
        : state.kind === 'loading' ? <div className={note}>{t('loading', { name })}</div>
        : state.kind === 'error' ? (
          <div className={`${note} flex flex-wrap items-center justify-between gap-2`}>
            <span>{t('unreachable', { name, code: state.code })}</span>
            <button type="button" onClick={() => void load()} className="h-7 cursor-pointer rounded-9 border border-line bg-transparent px-[10px] text-12 font-semibold">{t('retry')}</button>
          </div>
        )
        : state.flags.length === 0 ? <div className={note}>{t('none', { name })}</div>
        : state.flags.map((f) => {
          const on = f.status === 'published'
          const can = canConfigure && !!flags?.set_command && f.status !== 'retired'
          return (
            <div key={`${f.key}@${f.version}`} className={row}>
              <span className="flex min-w-0 flex-col">
                <b className="text-13">{f.name}</b>
                <span className="text-11.5 text-muted">
                  {[`${f.key} · v${f.version}`, t(`status.${f.status}`), f.items !== null ? t('items', { count: f.items }) : null, f.pilots ? t('pilots', { count: f.pilots }) : null]
                    .filter(Boolean).join(' · ')}
                </span>
              </span>
              <Toggle on={on} label={`${f.name} ${f.version}`} disabled={!can} onClick={() => setAsk(f)} />
            </div>
          )
        })}
      {readable && !canConfigure ? <div className={note}>{t('readOnly')}</div> : null}
      {readable && canConfigure && !flags?.set_command ? <div className={note}>{t('noSetCommand', { name })}</div> : null}
      {ask ? <FlagDialog product={product} flag={ask} onClose={() => setAsk(null)} onDone={() => { setAsk(null); void load() }} /> : null}
    </div>
  )
}

function FlagDialog({ product, flag, onClose, onDone }: { product: string; flag: ProductFlag; onClose: () => void; onDone: () => void }) {
  const t = useTranslations('simplePlatform.flags.dialog')
  const { flash } = useAct()
  const errText = useErrorText()
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, start] = useTransition()
  const publish = flag.status === 'draft'
  const label = `${flag.name} ${flag.version}`
  const submit = () => start(async () => {
    setError(null)
    const r = await setProductFlag({ product, key: flag.key, version: flag.version, status: publish ? 'published' : 'retired', reason: reason.trim() })
    if (!r.ok) { setError(r.code === 'not_connected' ? t('failed', { code: r.detail ?? 'failed' }) : errText(r)); return }
    flash(t(publish ? 'published' : 'retired', { name: label }))
    onDone()
  })
  return (
    <Dialog title={t(publish ? 'publishTitle' : 'retireTitle', { name: label })} onClose={onClose} width={480}>
      <span className="text-12.5 leading-[1.55]">{t(publish ? 'publishBody' : 'retireBody')}</span>
      <label className="flex flex-col gap-1 text-11.5 font-semibold text-muted">
        {t('reason')}
        <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className="h-[38px] rounded-10 border border-line bg-canvas px-[11px] text-13 text-ink" />
      </label>
      {error ? <div role="alert" className="text-12.5 font-semibold text-danger">{error}</div> : null}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
        <button
          type="button"
          disabled={pending || reason.trim().length < 5}
          onClick={submit}
          className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {t(publish ? 'publish' : 'retire')}
        </button>
      </div>
    </Dialog>
  )
}

/**
 * «API key» and «Status message» (v.apps, right card). A product's secrets live in Vault and are never shown or rotated in one
 * click (CLAUDE.md rule 5): the card says whether they are there and how they are replaced (V-SPL-05). The message is stored
 * in Sentral and delivered with Orgpuls' settings.set_notice (V-SPL-06).
 */
function KeyAndNotice({ app, product, name, notice, canConfigure }: { app: SimpleApp | null; product: string; name: string; notice: Notice | null; canConfigure: boolean }) {
  const t = useTranslations('simplePlatform.key')
  const tn = useTranslations('simplePlatform.notice')
  const ago = useAgo()
  const router = useRouter()
  const { flash, errText } = useAct()
  const [pending, start] = useTransition()
  const cur = notice?.current ?? null
  const [text, setText] = useState(cur?.text ?? '')
  const yes = (b: boolean | null) => (b ? '✓' : '✗')
  const command = !!notice?.notice_command
  const canPublish = canConfigure && command

  const send = (value: string | null) => start(async () => {
    const r = await publishNotice({ product, text: value })
    if (!r.ok) { flash(errText(r)); return }
    if (value === null) setText('')
    flash(r.delivered ? tn(value === null ? 'clearedLive' : 'live', { name }) : tn(value === null ? 'clearedSaved' : 'saved', { name, code: r.code ?? 'failed' }))
    router.refresh()
  })
  const publish = () => {
    if (!text.trim()) { flash(tn('empty')); return }
    send(text.trim())
  }

  return (
    <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
      <b className="text-15">{t('title')}</b>
      <div className="flex items-center gap-2">
        <span className={`flex-1 rounded-10 border border-line bg-canvas px-3 py-[10px] ${mono} text-12`}>
          {app?.token_secret === null || !app ? t('notConnected') : t('presence', { token: yes(app.token_secret), webhook: yes(app.webhook_secret) })}
        </span>
        <button
          type="button"
          disabled
          title={t('rotation')}
          className="h-9 flex-none cursor-default whitespace-nowrap rounded-10 border border-ink bg-surface px-3 text-12 font-bold opacity-60"
        >
          {t('rotate')}
        </button>
      </div>
      <span className="text-12 text-muted">{t('body')}</span>
      <span className="text-12 text-muted">{t('rotation')}</span>

      <b className="mt-[6px] text-15">{tn('title')}</b>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        maxLength={300}
        disabled={!canPublish || pending}
        aria-label={tn('title')}
        placeholder={tn('placeholder')}
        className="min-h-[70px] rounded-12 border border-line bg-canvas px-3 py-[10px] text-13 text-ink"
      />
      {notice === null ? <span className="text-12 text-danger">{tn('readFailed')}</span> : null}
      {cur ? (
        <span className="text-12 text-muted">
          {tn('since', { ago: ago(cur.set_at) })}
          {' · '}
          {cur.pushed_at ? tn('delivered', { name, ago: ago(cur.pushed_at) })
            : cur.push_error ? <span className="font-semibold text-danger">{tn('notDelivered', { name, code: cur.push_error })}</span>
            : tn('notDeliveredYet', { name })}
        </span>
      ) : null}
      {cur?.problem_number ? <span className="text-12 text-muted">{tn('problem', { number: String(cur.problem_number) })}</span> : null}
      {notice && !command ? <span className="text-12 text-muted">{tn('noCommand', { name })}</span> : null}
      {notice && command && !canConfigure ? <span className="text-12 text-muted">{tn('readOnly')}</span> : null}
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled={!canPublish || pending}
          onClick={publish}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[13px] text-12.5 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {tn('publish', { name })}
        </button>
        {cur && canPublish ? (
          <button
            type="button"
            disabled={pending}
            onClick={() => send(null)}
            className="h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-[13px] text-12.5 font-semibold disabled:cursor-default disabled:opacity-60"
          >
            {tn('clear')}
          </button>
        ) : null}
      </div>
    </div>
  )
}
