'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useState, useTransition } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { Delivery, DeliveryRow, Webhooks } from '@/lib/data/platform'
import { fetchDelivery, webhookDelete, webhookRedeliver, webhookSave, webhookSetState, webhookTest } from '../actions'
import { Dialog, OnceValue, k, useAct, useErrorText, type Fail } from './kit'

type Hook = Webhooks['webhooks'][number]
type Line = { id: string; at: string; event: string; host: string | null; status: number | null; state: DeliveryRow['state']; attempt: number; attempts: number; error: string | null; webhookId: string }

const host = (url: string) => url.replace(/^https:\/\/(?:[^@/]*@)?/, '').split(/[/:?#]/)[0] ?? url

export function HooksView({ hooks, selected, rows }: { hooks: Webhooks; selected: string | null; rows: DeliveryRow[] | null }) {
  const t = useTranslations('platform.hooks')
  const format = useFormatter()
  const errText = useErrorText()
  const { run, pending, flash } = useAct()
  const [dlg, setDlg] = useState<null | { hook: Hook | null }>(null)
  const [del, setDel] = useState<Hook | null>(null)
  const [picked, setPicked] = useState<string | null>(null)
  const [delivery, setDelivery] = useState<Delivery | null>(null)
  const [loading, start] = useTransition()
  const sel = hooks.webhooks.find((w) => w.id === selected) ?? null

  const lines: Line[] = sel && rows
    ? rows.map((r) => ({ id: r.id, at: r.sent_at ?? r.scheduled_at, event: r.event, host: host(sel.url), status: r.status, state: r.state, attempt: r.attempt, attempts: r.attempts, error: r.error, webhookId: sel.id }))
    : hooks.deliveries.map((d) => ({ ...d, webhookId: d.webhook_id }))

  const stateOf = (w: Hook): [string, string] => {
    if (w.state === 'banned') return [t('state.banned', { until: w.banned_until ? format.dateTime(new Date(w.banned_until), { hour: '2-digit', minute: '2-digit' }) : '—' }), 'text-danger']
    if (w.state === 'blocked') return [t('state.blocked'), 'text-danger']
    if (w.state === 'paused') return [t('state.paused'), 'text-muted']
    if (w.retrying) return [t('state.retrying'), 'text-warn-ink']
    return [t('state.active'), 'text-link']
  }
  const policy = String(hooks.policy.mode ?? 'source_values')
  const pick = (id: string) => {
    setPicked(id)
    setDelivery(null)
    start(async () => {
      const r = await fetchDelivery(id)
      if (r.ok) setDelivery(r.delivery)
      else flash(errText(r as Fail))
    })
  }
  const code = (l: Line) => (l.status !== null ? String(l.status) : t(`delivery.${l.state}`))

  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(0,1fr)_minmax(300px,400px)]">
      <div className="flex min-w-0 flex-col gap-3">
        <div className={k.card}>
          <div className={`${k.head} flex-wrap`}>
            <b className="text-14">{t('subscriptions')}</b>
            <span className="flex flex-wrap items-center gap-[10px]">
              <span className="text-12 text-muted">{t('perUser', { limit: hooks.limit === null ? t('unlimited') : String(hooks.limit) })}</span>
              <button type="button" onClick={() => setDlg({ hook: null })} className={k.btn}>{t('new')}</button>
            </span>
          </div>
          {hooks.webhooks.length === 0 ? <div className={k.empty}>{t('none')}</div> : null}
          {hooks.webhooks.map((w) => {
            const [st, sc] = stateOf(w)
            const on = w.id === selected
            return (
              <Link
                key={w.id}
                href={(on ? '/api?tab=hooks' : `/api?tab=hooks&webhook=${w.id}`) as Route}
                aria-current={on ? 'true' : undefined}
                className={`${k.row} grid items-center gap-[10px] py-[9px] text-ink [grid-template-columns:150px_minmax(0,1.4fr)_90px] max-sm:[grid-template-columns:minmax(0,1fr)_90px] hover:text-ink hover:no-underline ${on ? 'bg-highlight' : ''}`}
              >
                <b className={`${k.mono} truncate text-12`}>{w.event_kind}</b>
                <span className={`${k.mono} truncate whitespace-nowrap text-11.5 text-muted max-sm:order-3 max-sm:col-span-2`}>{w.url}</span>
                <span className={`font-bold ${sc}`}>{st}</span>
              </Link>
            )
          })}
          {sel ? (
            <div className="flex flex-wrap items-center gap-[6px] border-b border-line bg-canvas px-[18px] py-[10px] text-12">
              <span className="mr-auto text-muted">{t('owner', { name: sel.owner ?? '—' })}</span>
              <button type="button" disabled={pending || sel.state !== 'active'} onClick={() => run(() => webhookTest(sel.id), () => flash(t('testQueued')))} className={k.btn}>{t('test')}</button>
              {sel.state === 'active' || sel.state === 'paused' || sel.state === 'blocked' ? (
                <button type="button" disabled={pending} onClick={() => run(() => webhookSetState({ id: sel.id, state: sel.state === 'active' ? 'paused' : 'active' }), () => flash(t(sel.state === 'active' ? 'paused' : 'resumed')))} className={k.btnSoft}>
                  {sel.state === 'active' ? t('pause') : t('resume')}
                </button>
              ) : null}
              <button type="button" onClick={() => setDlg({ hook: sel })} className={k.btnSoft}>{t('edit')}</button>
              <button type="button" onClick={() => setDel(sel)} className={`${k.btnSoft} border-coral text-rust`}>{t('delete')}</button>
            </div>
          ) : null}
        </div>

        <div className={k.card}>
          <div className={`${k.head} flex-wrap`}>
            <b className="text-14">{sel ? t('deliveriesFor', { event: sel.event_kind }) : t('deliveries')}</b>
            <span className="text-12 text-muted">{t(`policy.${policy === 'custom' || policy === 'off' ? policy : 'source_values'}`)}</span>
          </div>
          {lines.length === 0 ? <div className={k.empty}>{t('noDeliveries')}</div> : null}
          <div className="overflow-x-auto"><div className="min-w-[560px]">
          {lines.map((l) => (
            <button
              key={l.id}
              type="button"
              onClick={() => pick(l.id)}
              aria-pressed={picked === l.id}
              className={`grid w-full cursor-pointer items-center gap-[10px] border-0 border-b border-solid border-line px-[18px] py-[9px] text-left text-12.5 text-ink [grid-template-columns:90px_150px_minmax(0,1fr)_70px_70px] ${picked === l.id ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="text-muted">{format.dateTime(new Date(l.at), { hour: '2-digit', minute: '2-digit' })}</span>
              <b className={`${k.mono} truncate text-12`}>{l.event}</b>
              <span className="truncate whitespace-nowrap text-muted">{l.host ?? '—'}</span>
              <b className={l.state === 'failed' || (l.status !== null && l.status >= 400) ? 'text-danger' : l.state === 'sent' ? 'text-link' : 'text-muted'}>{code(l)}</b>
              <span className="text-muted">{t('attempt', { n: l.attempt, of: l.attempts })}</span>
            </button>
          ))}
          </div></div>
          <div className="px-[18px] py-[10px] text-11.5 text-muted">{t('workerNote')}</div>
        </div>
      </div>

      <div className="flex flex-col gap-2 rounded-20 bg-ink px-[18px] py-4 text-tile">
        <b className="text-13.5 text-canvas">{t('payloadTitle')}</b>
        {delivery ? (
          <>
            <pre className={`m-0 whitespace-pre-wrap break-all text-11.5 leading-[1.55] ${k.mono}`}>{JSON.stringify(delivery.envelope ?? { event: delivery.event, state: delivery.state }, null, 2)}</pre>
            <span className="text-11.5 text-line-mid">
              {delivery.body_sha256 ? t('bodyHash', { bytes: delivery.bytes ?? 0, hash: delivery.body_sha256.slice(0, 16) }) : t('notBuilt')}
            </span>
            {delivery.error ? <span className="text-11.5 font-semibold text-coral-light">{t('error', { code: delivery.error })}</span> : null}
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => webhookRedeliver(delivery.id), () => flash(t('redelivered')))}
              className="h-7 w-fit cursor-pointer rounded-9 border border-tile bg-transparent px-[10px] text-12 font-bold text-canvas disabled:cursor-default disabled:opacity-60"
            >
              {t('redeliver')}
            </button>
          </>
        ) : (
          <span className="text-12 leading-[1.55] text-line-mid">{loading ? t('loading') : t('pickDelivery')}</span>
        )}
        <span className="text-11.5 text-line-mid">{t('signature')}</span>
      </div>

      {dlg ? <HookDialog hook={dlg.hook} kinds={hooks.kinds} onClose={() => setDlg(null)} /> : null}
      {del ? (
        <Dialog title={t('deleteTitle', { event: del.event_kind })} onClose={() => setDel(null)} width={480}>
          <span className="text-12.5 leading-[1.55]">{t('deleteBody', { host: host(del.url) })}</span>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setDel(null)} className={k.dlgCancel}>{t('cancel')}</button>
            <button type="button" disabled={pending} onClick={() => run(() => webhookDelete(del.id), () => { flash(t('deleted')); setDel(null) })} className={k.dlgDanger}>{t('delete')}</button>
          </div>
        </Dialog>
      ) : null}
    </div>
  )
}

/** Create or edit a webhook: a webhookable event and a public https address (D-32). The signing secret is shown once, on create. */
function HookDialog({ hook, kinds, onClose }: { hook: Hook | null; kinds: string[]; onClose: () => void }) {
  const t = useTranslations('platform.hooks')
  const { run, pending } = useAct()
  const [kind, setKind] = useState(hook?.event_kind ?? kinds[0] ?? '')
  const [url, setUrl] = useState(hook?.url ?? 'https://')
  const [secret, setSecret] = useState<string | null>(null)
  const submit = () => run(() => webhookSave({ id: hook?.id ?? null, event_kind: kind, url, version: hook?.version ?? null }), (r) => {
    if (r.ok && r.secret) setSecret(r.secret)
    else onClose()
  })
  if (secret) {
    return (
      <Dialog title={t('createdTitle')} onClose={onClose}>
        <span className="text-12.5 leading-[1.55]">{t('createdBody')}</span>
        <OnceValue label={t('secret')} value={secret} warning={t('onceWarning')} />
        <div className="flex justify-end"><button type="button" onClick={onClose} className={k.dlgConfirm}>{t('done')}</button></div>
      </Dialog>
    )
  }
  return (
    <Dialog title={hook ? t('editTitle') : t('newTitle')} onClose={onClose}>
      <label className={k.label}>
        {t('event')}
        <select value={kind} onChange={(e) => setKind(e.target.value)} className={`${k.input} ${k.mono}`}>
          {kinds.map((x) => <option key={x} value={x}>{x}</option>)}
        </select>
      </label>
      <label className={k.label}>{t('url')}<input value={url} onChange={(e) => setUrl(e.target.value)} className={`${k.input} ${k.mono}`} /></label>
      <span className="text-12 text-muted">{t('urlNote')}</span>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button type="button" disabled={pending || !kind || url.length < 9} onClick={submit} className={k.dlgConfirm}>{hook ? t('save') : t('create')}</button>
      </div>
    </Dialog>
  )
}
