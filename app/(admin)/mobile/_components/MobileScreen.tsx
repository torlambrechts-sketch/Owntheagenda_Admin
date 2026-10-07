'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useFormatter, useNow, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { NumberFormat } from '@/lib/format'
import type { CallOutcome, Coords, Mutation, NearbyRow, Pref, Preview, SyncResult } from '@/lib/data/mobile-shared'
import { checkIn, fetchNearby, fetchPreview, logCall, moveStage, registerDevice, revokeDevice, saveCapture, saveCard, setPushPref, syncApply, syncChanges } from '../actions'
import { recordUploadAbandon, recordUploadBegin, recordUploadDone } from '@/lib/storage/actions'
import { putSigned, RECORD_MAX_BYTES, RECORD_TYPES, typeFor } from '@/lib/storage/mime'
import { Banner } from './kit'
import { CapturePhone, DealPhone, ExtrasPhone, FocusPhone, NearbyPhone, NotificationsPhone, type CaptureUpload, type CardValues, type Frame } from './phones'
import { DevicesPanel, PrefsPanel, SyncPanel, type Logged } from './panels'
import { deviceId, loadCursor, loadOutbox, newId, saveCursor, saveOutbox, secondStep, type OutboxItem } from './outbox'
import { browserLabel, subscribeThisBrowser, type SubscribeFail } from './push'

type Geo = 'idle' | 'asking' | 'denied' | 'blocked' | 'unavailable'

/**
 * Mobile (Mobile.dc.html): the six phones show the signed-in staff member's own data, live (spec §6 Q13, D-38: the phone app
 * is the same web app). «Simulate offline» and «Landscape» change only the preview: offline, the phones' changes go to this
 * device's outbox and are sent with sync_apply when it is back online; the browser's own offline state does the same.
 *
 * The device's position is asked for only when the user presses «Use my location» (or types one), is kept in memory for
 * this page only, and is sent only with the Focus and Nearby reads, which neither store nor log it.
 */
export function MobileScreen({ staffId, numberFormat, initial }: { staffId: string; numberFormat: NumberFormat; initial: Preview }) {
  const t = useTranslations('mobile')
  const te = useTranslations('common.errors')
  const ts = useTranslations('common.storage')
  const format = useFormatter()
  const now = useNow({ updateInterval: 30_000 })
  const flash = useToast()
  const nf = numberFormat

  const [preview, setPreview] = useState(initial)
  const [simOffline, setSimOffline] = useState(false)
  const [netOnline, setNetOnline] = useState(true)
  const [land, setLand] = useState(false)
  const [coords, setCoords] = useState<Coords | null>(null)
  const [geo, setGeo] = useState<Geo>('idle')
  const [nearby, setNearby] = useState<NearbyRow[] | null>(null)
  const [nearbyFailed, setNearbyFailed] = useState(false)
  const [device, setDevice] = useState<string | null>(null)
  const [outbox, setOutbox] = useState<OutboxItem[]>([])
  const [log, setLog] = useState<Logged[]>([])
  const [syncing, setSyncing] = useState(false)
  const [lastPull, setLastPull] = useState<{ at: Date; count: number } | null>(null)
  const [missing, setMissing] = useState<string[] | null>(null)
  const offline = simOffline || !netOnline
  const outboxRef = useRef<OutboxItem[]>([])

  const setBox = useCallback((items: OutboxItem[]) => { outboxRef.current = items; setOutbox(items); saveOutbox(staffId, items) }, [staffId])

  // the device and its outbox live in this browser
  useEffect(() => {
    setDevice(deviceId())
    const items = loadOutbox(staffId)
    outboxRef.current = items
    setOutbox(items)
    setNetOnline(navigator.onLine)
  }, [staffId])

  const reload = useCallback(async (c: Coords | null) => {
    const r = await fetchPreview({ coords: c })
    if (r.ok) setPreview(r.preview)
    if (c) {
      const n = await fetchNearby(c)
      setNearby(n.ok ? n.rows : null)
      setNearbyFailed(!n.ok)
    } else {
      setNearby(null)
      setNearbyFailed(false)
    }
  }, [])

  const errorText = useCallback((code: string) => (te.has(code) ? te(code) : te('failed')), [te])

  // ---- sync: the outbox in order; a two-step item finishes with its second mutation once the first returned the id
  const syncingRef = useRef(false)
  const sync = useCallback(async (quietIfEmpty = false) => {
    if (syncingRef.current) return
    const items = outboxRef.current
    if (items.length === 0) { if (!quietIfEmpty) flash(t('sync.none')); return }
    const dev = deviceId()
    syncingRef.current = true
    setSyncing(true)
    const done: Logged[] = []
    let remaining = [...items]
    try {
      const firstBatch = remaining.filter((i) => !i.created_id).map((i) => i.first)
      if (firstBatch.length) {
        const r = await syncApply({ device: dev, mutations: firstBatch })
        if (!r.ok) { flash(t('sync.failed', { reason: errorText(r.code) })); return }
        const byId = new Map(r.results.map((x) => [x.mutation_id, x]))
        remaining = remaining.flatMap((i) => {
          if (i.created_id) return [i]
          const res = byId.get(i.first.mutation_id)
          if (!res) return [i]
          if (res.result === 'applied' && i.then && res.id) return [{ ...i, created_id: res.id }]
          done.push({ key: i.first.mutation_id, kind: i.kind, title: i.title, result: res })
          return []
        })
        setBox(remaining)
      }
      const second = remaining.map((i) => [i, secondStep(i)] as const).filter((x): x is readonly [OutboxItem, Mutation] => x[1] !== null)
      if (second.length) {
        const r = await syncApply({ device: dev, mutations: second.map((x) => x[1]) })
        if (!r.ok) { flash(t('sync.failed', { reason: errorText(r.code) })); return }
        const byId = new Map(r.results.map((x) => [x.mutation_id, x]))
        remaining = remaining.filter((i) => {
          const m = secondStep(i)
          const res = m ? byId.get(m.mutation_id) : undefined
          if (!res) return true
          // the activity exists from the first step; the second's outcome is the item's
          const combined: SyncResult = { ...res, id: i.created_id }
          done.push({ key: i.first.mutation_id, kind: i.kind, title: i.title, result: combined })
          return false
        })
        setBox(remaining)
      }
      const applied = done.filter((d) => d.result.result === 'applied').length
      const superseded = done.filter((d) => d.result.result === 'superseded').length
      const rejected = done.filter((d) => d.result.result === 'rejected').length
      const conflicts = done.filter((d) => d.result.conflict).length
      setLog(done)
      flash(superseded || rejected || conflicts ? t('sync.mixed', { applied, superseded, rejected }) : t('sync.done', { count: applied }))
      // then pull what changed since this device's cursor, and read the phones again
      const pulled = await syncChanges({ since: loadCursor(staffId) })
      if (pulled.ok) { saveCursor(staffId, pulled.cursor); setLastPull({ at: new Date(), count: pulled.count }) }
      await reload(coords)
    } finally {
      syncingRef.current = false
      setSyncing(false)
    }
  }, [coords, errorText, flash, reload, setBox, staffId, t])

  // the browser's own connection: offline queues, back online sends
  useEffect(() => {
    const on = () => { setNetOnline(true); if (!simOffline) void sync(true) }
    const off = () => setNetOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off) }
  }, [simOffline, sync])

  const toggleOffline = () => {
    if (!simOffline) { setSimOffline(true); return }
    setSimOffline(false)
    if (netOnline) void sync()
  }

  const queue = (item: OutboxItem) => {
    setBox([...outboxRef.current, item])
    flash(t('savedOffline'))
  }

  // ---- position: only on the user's action
  const locate = () => {
    if (!('geolocation' in navigator)) { setGeo('unavailable'); return }
    // the site's permissions policy may switch location off for every page; then the browser is not asked at all
    const policy = (document as Document & { featurePolicy?: { allowsFeature: (f: string) => boolean } }).featurePolicy
    if (policy && !policy.allowsFeature('geolocation')) { setGeo('blocked'); return }
    setGeo('asking')
    navigator.geolocation.getCurrentPosition(
      (p) => {
        const c = { lat: Math.round(p.coords.latitude * 1e6) / 1e6, lng: Math.round(p.coords.longitude * 1e6) / 1e6 }
        setGeo('idle')
        setCoords(c)
        void reload(c)
      },
      (e) => setGeo(e.code === e.PERMISSION_DENIED ? 'denied' : 'unavailable'),
      { enableHighAccuracy: false, timeout: 10_000, maximumAge: 60_000 },
    )
  }
  const typed = (c: Coords) => { setGeo('idle'); setCoords(c); void reload(c) }
  const forget = () => { setCoords(null); setGeo('idle'); void reload(null) }

  // ---- the phones' actions
  const onCheckIn = async (r: NearbyRow) => {
    if (offline) {
      if (!preview.types.visit) return
      queue({
        kind: 'checkin', title: r.title, then: { mutation_id: newId() }, created_id: null,
        first: { mutation_id: newId(), op: 'create', entity: 'activity', client_at: new Date().toISOString(),
          fields: { type_id: preview.types.visit, subject: r.title.slice(0, 200), starts_at: new Date().toISOString(), duration_min: 0, organization_id: r.id } },
      })
      return
    }
    const res = await checkIn({ entity: r.entity, id: r.id })
    if (!res.ok) { flash(errorText(res.code)); return }
    flash(t('checkedIn'))
    void reload(coords)
  }

  const deal = preview.deal
  const movePending = !!deal && outbox.some((o) => o.kind === 'stage' && o.first.record_id === deal.id)
  const onMove = async (stage: { id: string; name: string }) => {
    if (!deal) return
    setMissing(null)
    if (offline) {
      queue({
        kind: 'stage', title: `${deal.title} → ${stage.name}`, then: null, created_id: null,
        first: { mutation_id: newId(), op: 'stage_move', record_id: deal.id, base_version: deal.version, fields: { stage_id: stage.id }, client_at: new Date().toISOString() },
      })
      return
    }
    const res = await moveStage({ id: deal.id, stage: stage.id, version: deal.version })
    if (!res.ok) { flash(errorText(res.code)); if (res.code === 'version_conflict') void reload(coords); return }
    if (res.missing && res.missing.length) { setMissing(res.missing); return }
    flash(t('deal.moved', { stage: stage.name }))
    void reload(coords)
  }

  const onCall = async (v: { outcome: CallOutcome; minutes: number }): Promise<boolean> => {
    if (!deal?.person) return false
    const subject = t('deal.callSubject', { name: deal.person.name }).slice(0, 200)
    if (offline) {
      if (!preview.types.call) return false
      const at = new Date(Date.now() - v.minutes * 60_000).toISOString()
      queue({
        kind: 'call', title: deal.person.name, then: { mutation_id: newId() }, created_id: null,
        first: { mutation_id: newId(), op: 'create', entity: 'activity', client_at: new Date().toISOString(),
          fields: { type_id: preview.types.call, subject, starts_at: at, duration_min: v.minutes, person_id: deal.person.id, deal_id: deal.id, ...(deal.organization_id ? { organization_id: deal.organization_id } : {}) } },
      })
      return true
    }
    const res = await logCall({ person_id: deal.person.id, deal_id: deal.id, outcome: v.outcome, minutes: v.minutes, subject, number: deal.person.phone })
    if (!res.ok) { flash(errorText(res.code)); return false }
    flash(t('deal.callLogged', { n: v.minutes }))
    void reload(coords)
    return true
  }

  const onSaveCard = async (v: CardValues): Promise<string | null> => {
    const res = await saveCard(v)
    if (!res.ok) {
      const d = res.detail ?? ''
      flash(d === 'contact_rule' ? t('capture.card.refused') : d === 'basis' ? t('capture.card.basisNeeded') : errorText(res.code))
      return d || 'name'
    }
    flash(t('capture.card.saved'))
    return null
  }

  // Capture (MOB-06): the file goes to the deal through the storage signer (0052), then capture_save marks what it is
  const onCapture = async (kind: CaptureUpload, file: File): Promise<boolean> => {
    if (!deal) return false
    const mime = typeFor(file.name, RECORD_TYPES)
    if (!mime || (kind === 'audio') !== mime.startsWith('audio/') || (kind === 'photo' && !mime.startsWith('image/'))
        || (kind === 'scan' && !mime.startsWith('image/') && mime !== 'application/pdf')) { flash(ts('type')); return false }
    if (file.size > RECORD_MAX_BYTES) { flash(ts('tooLarge', { mb: 25 })); return false }
    const why = (r: { code: string; detail?: string | null }) => (r.detail && ts.has(r.detail) ? ts(r.detail) : errorText(r.code))
    const begun = await recordUploadBegin({ entity: 'deal', id: deal.id, filename: file.name, mime, size: file.size })
    if (!begun.ok) { flash(why(begun)); return false }
    if (!(await putSigned(begun.url, file, mime))) { await recordUploadAbandon(begun.id); flash(ts('sendFailed')); return false }
    const done = await recordUploadDone(begun.id)
    if (!done.ok) { flash(why(done)); return false }
    const saved = await saveCapture({ entity: 'deal', id: deal.id, file: begun.id, kind })
    if (!saved.ok) { flash(why(saved)); void reload(coords); return false }
    flash(kind === 'audio'
      ? t(saved.transcription === 'queued' ? 'capture.audio.savedQueued' : 'capture.audio.saved', { record: deal.title })
      : t('capture.scan.saved', { record: deal.title }))
    void reload(coords)
    return true
  }

  const onPref = async (kind: Pref['kind'], push: boolean) => {
    const before = preview.prefs
    setPreview({ ...preview, prefs: before?.map((p) => (p.kind === kind ? { ...p, channels: push ? ['in_app', 'push'] : ['in_app'] } : p)) ?? null })
    const r = await setPushPref({ kind, push })
    if (!r.ok) { setPreview((p) => ({ ...p, prefs: before })); flash(errorText(r.code)) }
  }
  // register this browser for push (R-MOBILE-03): only on the person's click, only with the provider's public key
  const [registering, setRegistering] = useState(false)
  const [pushProblem, setPushProblem] = useState<SubscribeFail | null>(null)
  const onRegister = async () => {
    const key = preview.push?.public_key
    if (!key) return
    setRegistering(true)
    setPushProblem(null)
    try {
      const sub = await subscribeThisBrowser(key)
      if (typeof sub === 'string') { setPushProblem(sub); return }
      const r = await registerDevice({ ...sub, label: browserLabel() })
      if (!r.ok) { flash(errorText(r.code)); return }
      flash(t('devices.registered'))
      void reload(coords)
    } finally {
      setRegistering(false)
    }
  }
  const onRevoke = async (id: string) => {
    const r = await revokeDevice(id)
    if (!r.ok) { flash(errorText(r.code)); return }
    void reload(coords)
  }

  // ---- the frame every phone shares
  const banner = offline || outbox.length > 0
    ? <Banner text={offline ? t('banner.offline', { n: outbox.length }) : t('banner.waiting', { n: outbox.length })} action={t('banner.sync')}
        onAction={() => (offline ? flash(t('sync.noNetwork')) : void sync())} />
    : null
  const tabs = (['focus', 'deals', 'activities', 'nearby', 'more'] as const).map((k, i) => ({ g: ['◉', '▥', '◷', '◎', '☰'][i]!, n: t(`tabbar.${k}`), on: k === 'focus' }))
  const frame: Frame = {
    land,
    time: format.dateTime(now, { hour: '2-digit', minute: '2-digit' }),
    net: offline ? t('net.offline') : t('net.online'),
    banner,
    tabs,
  }
  const pushReady = preview.push?.push_ready === true && preview.push.setting === 'on' && preview.push.module

  return (
    <div className="flex flex-col gap-4 px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="max-w-[720px]">
          <div className="text-11 font-bold uppercase tracking-eyebrow text-muted">{t('eyebrow')}</div>
          <h1 className="m-0 mt-[6px] font-serif text-24 font-semibold leading-[1.2]">{t('headline')}</h1>
          <p className="m-0 mt-[6px] text-12.5 text-muted">{t('previewNote')}</p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={toggleOffline} aria-pressed={simOffline}
            className={`h-[34px] cursor-pointer rounded-10 border border-solid px-3 text-12.5 font-semibold ${simOffline ? 'border-ink bg-amber-bg' : 'border-line bg-transparent'}`}>
            {simOffline ? t('goOnline') : t('simulateOffline')}
          </button>
          <button type="button" onClick={() => setLand(!land)} aria-pressed={land}
            className="h-[34px] cursor-pointer rounded-10 border border-solid border-line bg-transparent px-3 text-12.5 font-semibold">
            {land ? t('portrait') : t('landscape')}
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-start justify-center gap-[26px] md:justify-start">
        <FocusPhone frame={frame} focus={preview.focus} nf={nf} located={coords !== null} />
        <NearbyPhone frame={frame} nf={nf} coords={coords} geo={geo} rows={nearby} failed={nearbyFailed} offline={offline} canCheckIn={!!preview.types.visit}
          onLocate={locate} onManual={typed} onForget={forget} onCheckIn={onCheckIn} />
        <DealPhone frame={frame} deal={deal} nf={nf} offline={offline} movePending={movePending} canCallOffline={!!preview.types.call} missing={missing} onMove={onMove} onCall={onCall} />
        <CapturePhone frame={frame} rule={preview.focus.contact_rule} deal={deal} offline={offline} storage={preview.storage} captures={preview.captures} onSaveCard={onSaveCard} onCapture={onCapture} />
        <NotificationsPhone frame={frame} data={preview.notifications} pushReady={pushReady} />
        <ExtrasPhone frame={frame} focus={preview.focus} nf={nf} />
      </div>

      <div className="grid gap-[13px] [grid-template-columns:repeat(auto-fit,minmax(300px,1fr))]">
        <SyncPanel device={device} offline={offline} outbox={outbox} log={log} syncing={syncing} lastPull={lastPull} onSync={() => (offline ? flash(t('sync.noNetwork')) : void sync())} />
        <DevicesPanel push={preview.push} onRevoke={onRevoke} onRegister={onRegister} registering={registering} problem={pushProblem} />
        <PrefsPanel prefs={preview.prefs} pushReady={pushReady} onSet={onPref} />
      </div>
    </div>
  )
}
