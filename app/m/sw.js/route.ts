import { getTranslations } from 'next-intl/server'

/**
 * The minimal service worker (R-MOBILE-03), scope /m/. It exists so a browser can hold a push subscription made with the
 * provider's public key (push_vapid_public_key → push_device_register). It caches nothing and reads no data. A push
 * carries the notification's kind, message key, parameters and route (worker_push_claim); the worker shows the kind's
 * name in the staff member's language, never a record value, and a click opens the route on this origin.
 * The texts are written into the script when it is served, from the messages (no hard-coded copy).
 */
export const dynamic = 'force-dynamic'

const KINDS = ['assignment', 'mention', 'chat_request', 'security', 'system'] as const

export async function GET() {
  const t = await getTranslations('mobile')
  const texts = {
    title: t('pwa.push.title'),
    body: t('pwa.push.body'),
    kinds: Object.fromEntries(KINDS.map((k) => [k, t(`prefs.kinds.${k}`)])),
  }
  const script = `'use strict';
const T = ${JSON.stringify(texts)};
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = {}; }
  const p = d && typeof d === 'object' && d.payload && typeof d.payload === 'object' ? d.payload : d;
  const kind = typeof p.kind === 'string' && Object.prototype.hasOwnProperty.call(T.kinds, p.kind) ? T.kinds[p.kind] : null;
  const route = typeof p.route === 'string' && p.route.startsWith('/') && !p.route.startsWith('//') ? p.route : '/mobile';
  e.waitUntil(self.registration.showNotification(kind ? T.title + ' · ' + kind : T.title, { body: T.body, data: { route } }));
});
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const route = e.notification.data && e.notification.data.route ? e.notification.data.route : '/mobile';
  e.waitUntil(self.clients.openWindow(new URL(route, self.location.origin).href));
});
`
  return new Response(script, {
    headers: { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-cache', 'Service-Worker-Allowed': '/m/' },
  })
}
