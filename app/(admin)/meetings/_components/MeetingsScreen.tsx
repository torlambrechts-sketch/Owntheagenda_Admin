'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { RpcCode } from '@/lib/rpc'
import type { MailboxOption, MeetingBundle, MySettings, Workspace } from '@/lib/data/meetings'
import type { View } from '@/lib/data/meetings-shared'
import { fetchMeeting, fetchMySettings, fetchWorkspace } from '../actions'
import { WorkspaceView } from './WorkspaceView'
import { CaptureView } from './CaptureView'
import { ControlsView } from './ControlsView'
import { UploadModal } from './UploadModal'
import { useFail, type Me } from './kit'

type Props = {
  initialView: View
  initialWorkspace: Workspace
  initialMeetingId: string | null
  initialMeeting: MeetingBundle | null
  initialMeetingError: RpcCode | null
  me: Me
  products: Record<string, string>
  /** whether the storage signer runs (storage-sign, 0052): transcript upload follows it */
  storage: boolean
}

export type Mine = { settings: MySettings; mailboxes: MailboxOption[] }

/** The design's pill (tabs): ink when chosen, outlined otherwise. */
const pill = (on: boolean) =>
  `cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`

export function MeetingsScreen({ initialView, initialWorkspace, initialMeetingId, initialMeeting, initialMeetingError, me, products, storage }: Props) {
  const t = useTranslations('meetings')
  const flash = useToast()
  const fail = useFail()
  const [view, setView] = useState<View>(initialView)
  const [ws, setWs] = useState<Workspace>(initialWorkspace)
  const [selId, setSelId] = useState<string | null>(initialMeetingId)
  const [bundle, setBundle] = useState<MeetingBundle | null>(initialMeeting)
  const [bundleError, setBundleError] = useState<RpcCode | null>(initialMeetingError)
  const [loading, setLoading] = useState(false)
  const [mine, setMine] = useState<Mine | null>(null)
  const [upload, setUpload] = useState(false)
  const seq = useRef(0)

  // the address keeps the view and the meeting, so a reload or a shared link opens the same place
  useEffect(() => {
    const u = new URL(window.location.href)
    if (view === 'workspace') u.searchParams.delete('tab'); else u.searchParams.set('tab', view)
    if (selId && view === 'workspace') u.searchParams.set('meeting', selId); else u.searchParams.delete('meeting')
    window.history.replaceState(null, '', u.toString())
  }, [view, selId])

  const reloadWorkspace = useCallback(async () => {
    const r = await fetchWorkspace({})
    if (r.ok) setWs(r.workspace); else fail(r)
  }, [fail])

  const open = useCallback(async (id: string, quiet = false) => {
    const n = ++seq.current
    setSelId(id)
    if (!quiet) setLoading(true)
    const r = await fetchMeeting(id)
    if (n !== seq.current) return
    setLoading(false)
    if (r.ok) { setBundle(r.meeting); setBundleError(null) } else { setBundle(null); setBundleError(r.code) }
  }, [])

  /** After a write: the meeting and its list row both change (state label, group). */
  const refresh = useCallback(async () => {
    await Promise.all([selId ? open(selId, true) : Promise.resolve(), reloadWorkspace()])
  }, [open, reloadWorkspace, selId])

  const loadMine = useCallback(async () => {
    const r = await fetchMySettings()
    if (r.ok) setMine({ settings: r.settings, mailboxes: r.mailboxes }); else fail(r)
  }, [fail])
  useEffect(() => { if (view !== 'workspace' && !mine) void loadMine() }, [view, mine, loadMine])

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-[6px]" role="tablist" aria-label={t('views.label')}>
          {(['workspace', 'capture', 'controls'] as const).map((k) => (
            <button key={k} type="button" role="tab" aria-selected={view === k} onClick={() => setView(k)} className={pill(view === k)}>
              {t(`views.${k}`)}
            </button>
          ))}
        </div>
        <span className="flex-1" />
        <button type="button" onClick={() => flash(t('toolbar.adhocUnavailable'))} className="h-9 cursor-pointer rounded-10 border border-line bg-transparent px-[14px] text-12.5 font-semibold">
          {t('toolbar.adhoc')}
        </button>
        <button type="button" onClick={() => setUpload(true)} className="h-9 cursor-pointer rounded-10 border border-ink bg-surface px-[14px] text-12.5 font-bold">
          {t('toolbar.upload')}
        </button>
      </div>

      {view === 'workspace' ? (
        <WorkspaceView
          ws={ws}
          setWs={setWs}
          selId={selId}
          bundle={bundle}
          bundleError={bundleError}
          loading={loading}
          onOpen={(id) => void open(id)}
          onChanged={refresh}
          me={me}
          products={products}
        />
      ) : null}
      {view === 'capture' ? <CaptureView ws={ws} mine={mine} storage={storage} onMineChanged={loadMine} onUpload={() => setUpload(true)} /> : null}
      {view === 'controls' ? <ControlsView canConfigure={ws.can_configure} capabilities={ws.capabilities} mine={mine} onMineChanged={loadMine} /> : null}
      {upload ? (
        <UploadModal storage={storage} onClose={() => setUpload(false)} onUploaded={(id) => {
          setUpload(false)
          setView('workspace')
          void reloadWorkspace()
          void open(id)
        }} />
      ) : null}
    </div>
  )
}
