import { useTranslations } from 'next-intl'

/**
 * WhatsApp and LinkedIn (v.messaging). No WhatsApp Business provider is chosen (D-07), so the conversation
 * pane shows its unconnected state, not sample chats; the LinkedIn connector is the design's explanatory
 * card with Connect disabled (D-39).
 */
export function MessagingView() {
  const t = useTranslations('inbox.messaging')
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:minmax(0,1fr)] md:[grid-template-columns:minmax(240px,300px)_minmax(0,1fr)]">
      <div className="flex flex-col gap-[10px]">
        <div className="flex flex-col gap-[6px] rounded-20 border border-dashed border-line-strong bg-surface px-4 py-[14px]">
          <b className="text-13">{t('linkedinTitle')}</b>
          <span className="text-12 leading-[1.5] text-muted">{t('linkedinBody')}</span>
          <button type="button" disabled title={t('linkedinOff')} className="h-[30px] cursor-default self-start rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold opacity-50">
            {t('connect')}
          </button>
          <span className="text-11.5 text-faint">{t('linkedinOff')}</span>
        </div>
      </div>
      <div className="flex min-h-[520px] flex-col rounded-20 border border-line bg-surface">
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <span className="flex flex-col"><b className="text-14">{t('waTitle')}</b><span className="text-11.5 text-muted">{t('waState')}</span></span>
          <button type="button" disabled title={t('waOff')} className="h-[30px] cursor-default rounded-9 border border-ink bg-surface px-[11px] text-12 font-bold opacity-50">
            {t('connect')}
          </button>
        </div>
        <div className="flex flex-1 flex-col items-center justify-center gap-2 rounded-b-20 bg-canvas px-4 py-[14px] text-center">
          <b className="text-13">{t('waEmptyTitle')}</b>
          <span className="max-w-[420px] text-12.5 leading-[1.5] text-muted">{t('waEmptyBody')}</span>
        </div>
      </div>
    </div>
  )
}
