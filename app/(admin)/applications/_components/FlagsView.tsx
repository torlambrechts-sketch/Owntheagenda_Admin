'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Flags, Notice } from '@/lib/data/platform'
import { moduleSet, noticeSet } from '../actions'
import { Dialog, Toggle, k, useAct, useAgo, useSensitive } from './kit'

/**
 * Feature flags and the status banner (ENT-01; Appendix 2 System operations). The platform's own module switches are
 * real and switchable (module_set). A product's flags live in the product (D-23) and are read through its commands;
 * the replies have no agreed shape yet, so they are named, not drawn (V-PLATFORM-07). Maintenance mode needs a product
 * command that does not exist (D-40): the database refuses it as not_available, and the switch says so.
 */
export function FlagsView({ flags, apps, current, notice, canConfigure, owner }: {
  flags: Flags; apps: { key: string; name: string }[]; current: string | null; notice: Notice | null; canConfigure: boolean; owner: boolean
}) {
  const t = useTranslations('platform.flags')
  const ago = useAgo()
  const { run, pending, flash } = useAct()
  const [text, setText] = useState(notice?.current?.text ?? '')
  const [maint, setMaint] = useState<boolean | null>(null)
  const app = apps.find((a) => a.key === current) ?? null
  const cur = notice?.current ?? null

  const save = (clear: boolean) => run(
    () => noticeSet({ product: current, text: clear ? null : text.trim(), problem: clear ? null : cur?.problem_ticket_id ?? null, maintenance: false, confirm: null }),
    () => { flash(t(clear ? 'cleared' : 'saved', { name: app?.name ?? '' })); if (clear) setText('') },
  )

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={k.card}>
        <div className={`${k.head} text-14 font-bold`}>{t('title')}</div>
        {!canConfigure ? <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly')}</div> : null}
        {flags.modules.map((m) => (
          <div key={m.key} className={`${k.row} grid items-center gap-[10px] py-[10px] [grid-template-columns:minmax(0,1.4fr)_110px_minmax(0,1fr)_46px]`}>
            <span className="flex min-w-0 flex-col"><b className={`${k.mono} truncate text-12`}>sentral.{m.key}</b><span className="text-11.5 text-muted">{t('moduleSwitch')}</span></span>
            <span className="text-muted">{t('global')}</span>
            <span className="flex items-center gap-[6px]">
              <span className="h-[6px] flex-1 overflow-hidden rounded-999 bg-tile"><span className="block h-full bg-ok" style={{ width: m.enabled ? '100%' : '0%' }} /></span>
              <b className="text-11.5">{m.enabled ? '100 %' : t('off')}</b>
            </span>
            <Toggle on={m.enabled} label={`sentral.${m.key}`} disabled={!canConfigure || pending} onChange={(v) => run(() => moduleSet({ key: m.key, enabled: v }), () => flash(t(v ? 'moduleOn' : 'moduleOff', { key: m.key })))} />
          </div>
        ))}
        {flags.products.map((p) => (
          <div key={p.key} className={`${k.row} grid items-center gap-[10px] py-[10px] [grid-template-columns:minmax(0,1.4fr)_minmax(0,1fr)]`}>
            <span className="flex min-w-0 flex-col"><b className={`${k.mono} truncate text-12`}>{p.key}.*</b><span className="text-11.5 text-muted">{p.name}</span></span>
            <span className="text-12 text-muted">{p.flags_command ? t('productFlags', { tenants: p.active_tenants }) : t('noFlagCommand')}</span>
          </div>
        ))}
      </div>

      <div className={`${k.cardPad} gap-[10px]`}>
        <b className="text-14">{t('maintTitle')}</b>
        {apps.length > 1 ? (
          <div className="flex flex-wrap gap-[6px]">
            {apps.map((a) => (
              <Link
                key={a.key}
                href={`/applications?tab=flags&app=${a.key}` as Route}
                aria-current={a.key === current ? 'true' : undefined}
                className={`rounded-999 border px-3 py-[5px] text-12 hover:no-underline ${a.key === current ? 'border-ink bg-highlight font-bold text-ink hover:text-ink' : 'border-line-strong font-medium text-ink hover:text-ink'}`}
              >
                {a.name}
              </Link>
            ))}
          </div>
        ) : null}
        {!app || !notice ? <span className="text-12.5 text-muted">{t('noApp')}</span> : (
          <>
            <div className="flex items-center justify-between gap-2 text-12.5">
              <span>{t('maintenance', { name: app.name })}</span>
              <Toggle
                on={cur?.maintenance ?? false}
                label={t('maintenance', { name: app.name })}
                disabled={!canConfigure || pending}
                onChange={(v) => (notice.maintenance_command ? setMaint(v) : run(() => noticeSet({ product: current, text: text.trim() || null, problem: null, maintenance: true, confirm: null }), () => {}))}
              />
            </div>
            {!notice.maintenance_command ? <span className="text-11.5 text-muted">{t('maintNotAvailable', { name: app.name })}</span> : !owner ? <span className="text-11.5 text-muted">{t('maintOwner')}</span> : null}
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              maxLength={500}
              disabled={!canConfigure || !notice.notice_command}
              aria-label={t('banner')}
              placeholder={t('bannerPlaceholder')}
              className="min-h-[60px] rounded-10 border border-line bg-canvas px-[11px] py-[9px] text-12.5 text-ink"
            />
            {text.trim() ? (
              <div className="rounded-12 bg-amber-bg px-3 py-[10px] text-12.5 text-amber-ink"><b>{t('preview')}</b> {text.trim()}</div>
            ) : null}
            {cur?.problem_number ? <div className="text-11.5 text-muted">{t('linked', { number: String(cur.problem_number), name: app.name })}</div> : null}
            {cur ? (
              <div className={`text-11.5 ${cur.push_error ? 'font-semibold text-danger' : 'text-muted'}`}>
                {cur.push_error ? t('pushFailed', { code: cur.push_error }) : cur.pushed_at ? t('pushed', { ago: ago(cur.pushed_at) }) : t('notPushed', { name: app.name })}
              </div>
            ) : null}
            {!notice.notice_command ? <span className="text-11.5 text-muted">{t('noNoticeCommand', { name: app.name })}</span> : null}
            <div className="flex flex-wrap gap-[6px]">
              <button type="button" disabled={!canConfigure || !notice.notice_command || pending || !text.trim() || text.trim() === (cur?.text ?? '')} onClick={() => save(false)} className={k.btn}>{t('save')}</button>
              {cur ? <button type="button" disabled={!canConfigure || pending} onClick={() => save(true)} className={k.btnSoft}>{t('clear')}</button> : null}
            </div>
            {notice.history.length ? (
              <div className="flex flex-col gap-1 border-t border-line pt-2">
                <span className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('history')}</span>
                {notice.history.slice(0, 5).map((h) => (
                  <span key={h.id} className="text-11.5 text-muted">
                    {ago(h.set_at)} · {h.set_by ?? '—'} · {h.text ? <span className="text-ink-2">{h.text.length > 70 ? `${h.text.slice(0, 70)} …` : h.text}</span> : t('clearedEntry')}
                  </span>
                ))}
              </div>
            ) : null}
          </>
        )}
      </div>
      {maint !== null && app ? <MaintDialog product={app.key} name={app.name} on={maint} text={text.trim() || null} onClose={() => setMaint(null)} /> : null}
    </div>
  )
}

/**
 * Maintenance mode stops the product for every customer (D-30): the owner, a fresh second factor and the product key typed
 * to confirm. Reached only once the product offers the command (status_notice_get.maintenance_command).
 */
function MaintDialog({ product, name, on, text, onClose }: { product: string; name: string; on: boolean; text: string | null; onClose: () => void }) {
  const t = useTranslations('platform.flags.maintDlg')
  const { call, pending, mfa, alert, blocked } = useSensitive()
  const [typed, setTyped] = useState('')
  return (
    <Dialog title={t(on ? 'titleOn' : 'titleOff', { name })} onClose={onClose} width={480}>
      <span className="text-12.5 leading-[1.55]">{t(on ? 'bodyOn' : 'bodyOff', { name })}</span>
      <label className={k.label}>{t('confirm', { key: product })}<input value={typed} onChange={(e) => setTyped(e.target.value)} className={`${k.input} ${k.mono}`} /></label>
      {mfa}
      {alert}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button
          type="button"
          disabled={pending || blocked || typed !== product}
          onClick={() => call(() => noticeSet({ product, text, problem: null, maintenance: on, confirm: typed }), () => onClose())}
          className={k.dlgDanger}
        >
          {t(on ? 'submitOn' : 'submitOff')}
        </button>
      </div>
    </Dialog>
  )
}
