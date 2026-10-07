'use client'

import { useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { acceptFor, putSigned, TRANSCRIPT_MAX_BYTES, TRANSCRIPT_TYPES, typeFor } from '@/lib/storage/mime'
import { transcriptUploadBegin, transcriptUploadDone } from '../actions'
import { Modal, btnCancel, btnConfirm, quiet, useFail } from './kit'

/**
 * Upload transcript (MTG-06): meeting_transcript_upload_begin (a new unlinked meeting and a pending upload in the private
 * «meeting-files» bucket) → storage-sign signs that path (0052) → the browser sends the file → meeting_transcript_upload_done,
 * and jobs-run reads it into the meeting at once (0054). The toast says whether it was read, could not be read, or waits
 * (the reader could not be reached; «Read now» on the transcript asks again). Without the signer nothing can be sent, and
 * starting anyway would leave an empty meeting
 * behind, so the dialog then only says what will be accepted and why it waits. The type sent is the extension's: browsers
 * leave it empty for .srt and .vtt.
 */
export function UploadModal({ storage, onClose, onUploaded }: { storage: boolean; onClose: () => void; onUploaded: (meetingId: string) => void }) {
  const t = useTranslations('meetings.upload')
  const ts = useTranslations('common.storage')
  const flash = useToast()
  const fail = useFail()
  const picker = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)

  const send = async (file: File) => {
    const mime = typeFor(file.name, TRANSCRIPT_TYPES)
    if (!mime) { flash(ts('type')); return }
    if (file.size > TRANSCRIPT_MAX_BYTES) { flash(ts('tooLarge', { mb: 5 })); return }
    setBusy(true)
    try {
      const begun = await transcriptUploadBegin({ filename: file.name, mime, size: file.size })
      if (!begun.ok) { if (begun.detail && ts.has(begun.detail)) flash(ts(begun.detail)); else fail(begun); return }
      if (!(await putSigned(begun.url, file, mime))) { flash(t('sendFailed')); onUploaded(begun.meetingId); return }
      const done = await transcriptUploadDone(begun.id)
      if (!done.ok) { fail(done); onUploaded(begun.meetingId); return }
      flash(done.job.state === 'ready' ? t('read') : done.job.state === 'failed' ? t('readFailed') : t('readPending'))
      onUploaded(begun.meetingId)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal eyebrow={t('eyebrow')} title={t('title')} onClose={onClose}>
      <p className="m-0 text-13 leading-[1.55] text-ink-2">{t('body')}</p>
      <div className="flex flex-col gap-1 rounded-13 border border-line px-[13px] py-[11px]">
        <b className="text-13">{t('formats')}</b>
        <span className="text-11.5 text-muted">{t('formatsHint')}</span>
      </div>
      <p className={`m-0 ${quiet}`}>{storage ? t('reader') : t('notConnected')}</p>
      <input ref={picker} type="file" hidden accept={acceptFor(TRANSCRIPT_TYPES)} onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void send(f) }} />
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={btnCancel}>{t('close')}</button>
        <button type="button" disabled={!storage || busy} onClick={() => picker.current?.click()} className={btnConfirm}>{busy ? t('sending') : t('choose')}</button>
      </div>
    </Modal>
  )
}
