'use client'

import Link from 'next/link'
import { useTranslations } from 'next-intl'

/**
 * The assistant drawer. Until the AI gateway is connected (phase 7, a Claude key under API and
 * integrations) it shows that state, not a conversation: the prompts and the input are disabled.
 */
export function AssistantPanel({ onClose }: { onClose: () => void }) {
  const t = useTranslations('shell.assistant')
  const prompts = ['trials', 'summarize', 'draft', 'tickets', 'pipeline'] as const
  return (
    <aside
      aria-label={t('button')}
      className="fixed bottom-0 right-0 top-0 z-[70] flex w-[420px] max-w-[100vw] flex-col border-l border-line bg-surface shadow-modal"
    >
      <div className="flex items-center gap-3 border-b border-line px-[18px] py-[14px]">
        {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
        <img src="/brand/assistant.png" alt="" width={38} height={38} className="block rounded-11 bg-canvas" />
        <div className="flex flex-1 flex-col">
          <span className="text-15 font-bold">{t('button')}</span>
          <span className="text-12 text-muted">{t('sub')}</span>
        </div>
        <button type="button" onClick={onClose} aria-label={t('close')} className="h-[30px] w-[30px] cursor-pointer rounded-999 border border-ink bg-transparent text-15">
          ×
        </button>
      </div>
      <div className="flex flex-1 flex-col gap-3 overflow-auto px-[18px] py-4">
        <div className="flex justify-start">
          <div className="flex max-w-[88%] flex-col gap-2 whitespace-pre-wrap rounded-16 border border-line bg-canvas px-[14px] py-[11px] text-13 leading-[1.55]">
            <span>{t('notConnected')}</span>
            <Link href="/api" onClick={onClose} className="text-12.5 font-semibold">{t('connect')}</Link>
          </div>
        </div>
      </div>
      <div className="flex flex-col gap-[10px] border-t border-line px-[18px] pb-4 pt-3">
        <div className="flex flex-wrap gap-[6px]">
          {prompts.map((p) => (
            <button key={p} type="button" disabled className="cursor-not-allowed rounded-999 border border-line-strong bg-transparent px-[11px] py-[6px] text-12 opacity-60">
              {t(`prompts.${p}`)}
            </button>
          ))}
        </div>
        <div className="flex gap-2">
          <input disabled aria-label={t('placeholder')} placeholder={t('placeholder')} className="h-10 flex-1 rounded-10 border border-line bg-canvas px-3 text-13" />
          <button type="button" disabled aria-label={t('voice')} className="flex h-10 w-10 cursor-not-allowed items-center justify-center rounded-10 border border-line bg-transparent opacity-60">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true">
              <path d="M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3M5 11a7 7 0 0 0 14 0M12 18v3" />
            </svg>
          </button>
          <button type="button" disabled className="h-10 cursor-not-allowed rounded-10 border border-ink bg-primary px-[15px] text-13 font-bold opacity-60">
            {t('send')}
          </button>
        </div>
        <div className="text-11 text-faint">{t('footer')}</div>
      </div>
    </aside>
  )
}
