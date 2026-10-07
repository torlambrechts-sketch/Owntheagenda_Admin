'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Mcp } from '@/lib/data/platform'
import { grantRevoke, mcpSet } from '../actions'
import { Dialog, Toggle, k, useAct, useAgo } from './kit'

/**
 * The AI connector (MCP-01..03). The switch is the company setting mcp_access: off revokes every assistant's grant and
 * refuses new ones. The connector endpoint itself (the mcp edge function and its OAuth endpoints) is not deployed, so
 * no assistant can connect yet and the address says so instead of naming a host.
 */
export function McpView({ mcp }: { mcp: Mcp }) {
  const t = useTranslations('platform.mcp')
  const te = useTranslations('platform.entities')
  const ago = useAgo()
  const { run, pending, flash } = useAct()
  const [confirmOff, setConfirmOff] = useState(false)
  const on = mcp.access === 'on'
  const set = (v: boolean) => run(() => mcpSet(v), () => { flash(t(v ? 'switchedOn' : 'switchedOff')); setConfirmOff(false) })

  // the tool catalog, one row per record type as the design groups it (names from api_definition)
  const groups = new Map<string, string[]>()
  for (const tool of mcp.tools) {
    const g = tool.entity ?? 'search'
    groups.set(g, [...(groups.get(g) ?? []), tool.name])
  }

  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={`${k.cardPad} gap-[10px]`}>
        <div className="flex items-center justify-between">
          <b className="text-15">{t('title')}</b>
          <Toggle big on={on} label={t('switch')} disabled={!mcp.can_configure || pending} onChange={(v) => (v || mcp.connected === 0 ? set(v) : setConfirmOff(true))} />
        </div>
        <span className="text-12.5 text-ink-2">{on ? t('stateOn', { count: mcp.connected }) : t('stateOff')}</span>
        {!mcp.can_configure ? <span className="text-12 text-muted">{t('readOnly')}</span> : null}
        <div className={`rounded-10 border border-line bg-canvas p-[10px] text-12 ${k.mono}`}>{t('endpoint')}</div>
        <div className="flex justify-between gap-2 text-12.5">
          <span className="text-muted">{t('sync')}</span>
          <b className="text-right">{mcp.sync === 'on' ? t('syncOn', { ago: ago(mcp.last_index_at) }) : t('syncOff')}</b>
        </div>
        <div className="mt-1 text-11 font-bold uppercase tracking-eyebrow text-muted">{t('assistants')}</div>
        {mcp.assistants.length === 0 ? <span className="py-[6px] text-12.5 text-muted">{t('noAssistants')}</span> : null}
        {mcp.assistants.map((a) => (
          <div key={a.id} className="flex items-center justify-between gap-2 border-b border-line py-[6px] text-12.5">
            <span><b>{a.app}</b> · {a.staff ?? '—'}</span>
            <span className="flex items-center gap-2 text-muted">
              {a.last_used_at ? ago(a.last_used_at) : t('neverUsed')}
              {a.mine ? <button type="button" disabled={pending} onClick={() => run(() => grantRevoke(a.id), () => flash(t('revoked', { app: a.app })))} className={`${k.btnRevoke} px-2`}>{t('revoke')}</button> : null}
            </span>
          </div>
        ))}
        <span className="text-11.5 text-faint">{t('footnote')}</span>
      </div>

      <div className={k.card}>
        <div className={`${k.head} text-14 font-bold`}>{t('tools', { count: mcp.tools.length })}</div>
        {[...groups.entries()].map(([g, names]) => (
          <div key={g} className={`${k.row} flex justify-between gap-[10px] py-2 text-12`}>
            <span className={`${k.mono} min-w-0 break-words`}>{names.join(' / ')}</span>
            <span className="flex-none text-muted">{te.has(g) ? te(g) : g}</span>
          </div>
        ))}
      </div>

      {confirmOff ? (
        <Dialog title={t('offTitle')} onClose={() => setConfirmOff(false)} width={480}>
          <span className="text-12.5 leading-[1.55]">{t('offBody', { count: mcp.connected })}</span>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setConfirmOff(false)} className={k.dlgCancel}>{t('cancel')}</button>
            <button type="button" disabled={pending} onClick={() => set(false)} className={k.dlgDanger}>{t('offSubmit')}</button>
          </div>
        </Dialog>
      ) : null}
    </div>
  )
}
