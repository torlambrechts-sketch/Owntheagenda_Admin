'use client'

import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { clearSandbox, switchSandbox } from '../actions'
import { DesignSwitch, useRun } from './kit'

/**
 * Sandbox (Settings.dc.html, v.sandbox): the sample records per type (sandbox_counts), removing them in one
 * step (sandbox_clear) and my own sandbox switch (the header's, sandbox_set). «Reset from seed» has no
 * backend yet: disabled, with the reason (requests/settings.md).
 */
export function Sandbox({ rows, lastCleared, on, nf, canClear }: { rows: { key: string; n: number }[]; lastCleared: string | null; on: boolean; nf: NumberFormat; canClear: boolean }) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const total = rows.reduce((a, r) => a + r.n, 0)
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,380px),1fr))]">
      <div className="flex flex-col gap-[10px] rounded-20 border border-ink bg-highlight px-5 py-[18px]">
        <b className="font-serif text-20">{t('sandbox.title')}</b>
        <span className="text-12.5 leading-[1.55] text-amber-ink">{t('sandbox.body')}</span>
        {rows.map((r) => (
          <div key={r.key} className="flex justify-between border-b border-[rgba(25,21,16,.12)] py-[5px] text-12.5">
            <span>{t('sandbox.sample', { entity: t(`sandbox.entities.${r.key}`) })}</span>
            <b>{formatNumber(r.n, nf)}</b>
          </div>
        ))}
        <div className="flex justify-between border-b border-[rgba(25,21,16,.12)] py-[5px] text-12.5">
          <span>{t('sandbox.lastCleared')}</span>
          <b>{lastCleared ?? '—'}</b>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={!canClear || pending || total === 0}
            onClick={() => run(() => clearSandbox(), (r) => t('sandbox.removed', { count: r.removed }))}
            className="h-[34px] cursor-pointer rounded-10 border border-ink bg-surface px-[13px] text-12.5 font-bold text-ink disabled:cursor-default disabled:opacity-60"
          >
            {t('sandbox.remove')}
          </button>
          <button type="button" disabled aria-describedby="sandbox-reset" className="h-[34px] cursor-default rounded-10 border border-ink bg-transparent px-[13px] text-12.5 font-semibold text-ink opacity-60">
            {t('sandbox.reset')}
          </button>
        </div>
        <span id="sandbox-reset" className="text-11.5 text-amber-ink">{t('sandbox.resetPending')}</span>
        {!canClear ? <span className="text-11.5 text-amber-ink">{t('readOnly', { right: t('rights.configure') })}</span> : null}
      </div>
      <div className="flex flex-col gap-2 rounded-20 border border-line bg-surface px-[18px] py-4">
        <b className="text-14">{t('sandbox.useTitle')}</b>
        <span className="text-12.5 leading-[1.55]">{t('sandbox.useBody')}</span>
        <div className="flex items-center justify-between gap-3 border-t border-line pt-[10px] text-12.5">
          <b>{t('sandbox.switch')}</b>
          <DesignSwitch on={on} label={t('sandbox.switch')} disabled={pending} onChange={(v) => run(() => switchSandbox(v), () => t(v ? 'sandbox.switchedOn' : 'sandbox.switchedOff'))} />
        </div>
      </div>
    </div>
  )
}
