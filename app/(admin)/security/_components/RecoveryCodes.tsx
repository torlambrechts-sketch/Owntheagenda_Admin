'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { recoveryCodesGenerate } from '../actions'
import { Modal, dialogBtn, sx, useGuarded } from './kit'

/**
 * One's own recovery codes (D-11): ten new codes replace the old ones, need a fresh second factor, and are shown once.
 * They live only in this component's state until the dialog closes; nothing stores or logs them here.
 */
export function RecoveryCodes() {
  const t = useTranslations('security.recovery')
  const { run, busy, dialog } = useGuarded()
  const [codes, setCodes] = useState<string[] | null>(null)
  const [copied, setCopied] = useState(false)
  return (
    <section className={sx.cardPad} aria-label={t('title')}>
      {dialog}
      <b className="text-14">{t('title')}</b>
      <span className="text-12 text-muted">{t('body')}</span>
      <div>
        <button type="button" className={sx.btn30} disabled={busy} onClick={async () => {
          const r = await run(() => recoveryCodesGenerate())
          if (r.ok) { setCodes(r.codes); setCopied(false) }
        }}>{t('generate')}</button>
      </div>
      {codes ? (
        <Modal eyebrow={t('eyebrow')} title={t('shownOnce')} onClose={() => setCodes(null)}>
          <p className="m-0 text-13 leading-[1.5] text-muted">{t('saveThem')}</p>
          <ol className="m-0 grid grid-cols-2 gap-x-6 gap-y-1 pl-5 text-14 [font-family:ui-monospace,Menlo,monospace]">
            {codes.map((c) => <li key={c}>{c}</li>)}
          </ol>
          <div className="flex justify-end gap-2">
            <button type="button" className={`${sx.btn30} h-10 px-4`} onClick={async () => {
              try { await navigator.clipboard.writeText(codes.join('\n')); setCopied(true) } catch { setCopied(false) }
            }}>{copied ? t('copied') : t('copy')}</button>
            <button type="button" className={dialogBtn} onClick={() => setCodes(null)}>{t('done')}</button>
          </div>
        </Modal>
      ) : null}
    </section>
  )
}
