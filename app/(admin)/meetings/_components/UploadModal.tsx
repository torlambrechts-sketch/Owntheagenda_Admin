'use client'

import { useTranslations } from 'next-intl'
import { Modal, btnCancel, btnConfirm, quiet } from './kit'

/**
 * Upload transcript (MTG-06). The database takes the upload (meeting_transcript_upload_begin → a signed path in the
 * private «meeting-files» bucket → meeting_transcript_upload_done), but the edge function that signs the path is not
 * deployed, so nothing can be sent yet. Starting anyway would leave an empty meeting behind, so the dialog only says
 * what will be accepted and why it waits.
 */
export function UploadModal({ onClose }: { onClose: () => void }) {
  const t = useTranslations('meetings.upload')
  return (
    <Modal eyebrow={t('eyebrow')} title={t('title')} onClose={onClose}>
      <p className="m-0 text-13 leading-[1.55] text-ink-2">{t('body')}</p>
      <div className="flex flex-col gap-1 rounded-13 border border-line px-[13px] py-[11px]">
        <b className="text-13">{t('formats')}</b>
        <span className="text-11.5 text-muted">{t('formatsHint')}</span>
      </div>
      <p className={`m-0 ${quiet}`}>{t('notConnected')}</p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('close')}</button>
        <button type="button" disabled className={btnConfirm}>{t('choose')}</button>
      </div>
    </Modal>
  )
}
