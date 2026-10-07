'use client'

/**
 * Web Push for this browser (MOB-07, R-MOBILE-03): the service worker under /m registers, the browser subscribes with the
 * provider's public key (push_vapid_public_key — never the private one), and the subscription's endpoint and keys go to
 * push_device_register. The endpoint is write-only: the server never returns it.
 */
export const SW_URL = '/m/sw.js'
export const SW_SCOPE = '/m/'

export type Subscribed = { endpoint: string; p256dh: string; auth: string }
export type SubscribeFail = 'unsupported' | 'denied' | 'failed'

export const pushSupported = () =>
  typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window && window.isSecureContext

/** «BNc…» (base64url, as VAPID keys are written) → the bytes PushManager.subscribe takes. */
function keyBytes(b64url: string): Uint8Array<ArrayBuffer> {
  const b64 = (b64url + '='.repeat((4 - (b64url.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  const out = new Uint8Array(new ArrayBuffer(raw.length))
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

const same = (a: ArrayBuffer | null | undefined, b: Uint8Array) => {
  if (!a || a.byteLength !== b.byteLength) return false
  const x = new Uint8Array(a)
  return x.every((v, i) => v === b[i])
}

/** The registration's worker once it is active: subscribe() refuses a registration without one. */
async function activated(reg: ServiceWorkerRegistration): Promise<void> {
  if (reg.active) return
  const w = reg.installing ?? reg.waiting
  if (!w) return
  await new Promise<void>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), 15000)
    w.addEventListener('statechange', () => {
      if (w.state === 'activated') { clearTimeout(t); resolve() }
      if (w.state === 'redundant') { clearTimeout(t); reject(new Error('redundant')) }
    })
  })
}

/** Asks for permission only on the person's click, registers the worker and subscribes (or reuses a subscription made with this key). */
export async function subscribeThisBrowser(publicKey: string): Promise<Subscribed | SubscribeFail> {
  if (!pushSupported()) return 'unsupported'
  try {
    const permission = await Notification.requestPermission()
    if (permission !== 'granted') return 'denied'
    const reg = await navigator.serviceWorker.register(SW_URL, { scope: SW_SCOPE })
    await activated(reg)
    const key = keyBytes(publicKey)
    let sub = await reg.pushManager.getSubscription()
    if (sub && !same(sub.options.applicationServerKey, key)) { await sub.unsubscribe(); sub = null }
    sub ??= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key })
    const j = sub.toJSON()
    if (!j.endpoint || !j.keys?.p256dh || !j.keys?.auth) return 'failed'
    return { endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth }
  } catch {
    return 'failed'
  }
}

/** A coarse device name for the list («Chrome · macOS»): the browser's and the system's own names, nothing finer. */
export function browserLabel(): string | null {
  if (typeof navigator === 'undefined') return null
  const ua = navigator.userAgent
  const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : null
  const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Mac OS X/.test(ua) ? 'macOS' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : null
  const parts = [browser, os].filter(Boolean)
  return parts.length ? parts.join(' · ') : null
}
