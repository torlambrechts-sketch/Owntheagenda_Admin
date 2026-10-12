'use client'

import { useEffect, useRef } from 'react'
import { useTranslations } from 'next-intl'

/**
 * «Add condition» opens the editor at the email it is about: this bar, right above that step, offers the condition the
 * tip names («If the employee list is not uploaded»). Nothing changes until the person adds it; the editor then saves it
 * like any other step (simple_sequence_save, the editor's rights). Escape or «Cancel» closes it.
 */
export function InsertCondition({ email, condition, onAdd, onCancel }: { email: number; condition: string; onAdd: () => void; onCancel: () => void }) {
  const t = useTranslations('simpleGrowth.v3.insert')
  const box = useRef<HTMLDivElement>(null)
  const add = useRef<HTMLButtonElement>(null)
  const cancel = useRef(onCancel)
  cancel.current = onCancel
  useEffect(() => {
    box.current?.scrollIntoView({ block: 'center', behavior: 'smooth' })
    add.current?.focus({ preventScroll: true })
  }, [])
  return (
    <div className="flex flex-col items-center">
      <div
        ref={box}
        role="group"
        aria-label={t('label', { n: email })}
        onKeyDown={(e) => { if (e.key === 'Escape') cancel.current() }}
        className="flex w-full flex-wrap items-center gap-[10px] rounded-16 border-[1.5px] border-dashed border-ink bg-highlight px-[14px] py-3 text-12.5"
      >
        <span className="min-w-0 flex-[1_1_220px]">{t('text', { n: email, condition })}</span>
        <button ref={add} type="button" onClick={onAdd} className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-999 border border-dashed border-ink bg-surface px-[13px] text-12 font-semibold">
          {t('add')}
        </button>
        <button type="button" onClick={onCancel} className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-[11px] text-12 font-semibold">
          {t('cancel')}
        </button>
      </div>
      <span className="h-[14px] w-[1.5px] bg-line-strong" />
    </div>
  )
}
