import { redirect } from 'next/navigation'
import { getFormatter, getTranslations } from 'next-intl/server'
import { signOut } from '@/app/login/actions'
import { platformStatus, whoami } from '@/lib/platform/read'
import { TestButton } from './TestButton'

/**
 * The foundation's one screen: is a product installed, are its events arriving, does a command make the
 * round trip. Kinds, counts and times only — never an event's contents. The platform's design replaces
 * it with the real pages.
 */
export default async function StatusPage() {
  const me = await whoami()
  if (!me?.account) redirect('/ingen-tilgang')
  if (!me.admin) redirect('/mfa')
  const t = await getTranslations('status')
  const a = await getTranslations('app')
  const format = await getFormatter()
  const s = await platformStatus()
  const when = (iso: string) => format.dateTime(new Date(iso), { dateStyle: 'short', timeStyle: 'short' })

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10">
      <header className="mb-8 flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold">{t('title')}</h1>
        <form action={signOut} className="flex items-baseline gap-3 text-sm text-neutral-600">
          <span>{me.email}</span>
          <button type="submit" className="underline focus:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900">
            {a('signOut')}
          </button>
        </form>
      </header>
      {!s ? (
        <p role="alert" className="text-red-700">
          {t('unavailable')}
        </p>
      ) : (
        <div className="flex flex-col gap-8">
          <section>
            <h2 className="mb-2 font-semibold">{t('installations')}</h2>
            <ul className="mb-3">
              {s.installations.map((i) => (
                <li key={i.product}>
                  {i.name}: {i.enabled === null ? t('notInstalled') : i.enabled ? t('enabled') : t('disabled')}
                  {i.host ? <span className="text-neutral-500"> · {i.host}</span> : null}
                </li>
              ))}
            </ul>
            <TestButton />
          </section>
          <section>
            <h2 className="mb-2 font-semibold">{t('customers')}</h2>
            <p>
              {t('accounts', { count: s.accounts })} · {t('tenants', { count: s.tenants_active })}
            </p>
          </section>
          <section>
            <h2 className="mb-2 font-semibold">{t('events')}</h2>
            <p>
              {t('eventsTotal', { count: s.events })}
              {s.last_event_at ? ` · ${t('lastEvent', { when: when(s.last_event_at) })}` : ''}
            </p>
            {Object.keys(s.by_kind).length ? (
              <>
                <h3 className="mt-4 text-sm font-semibold text-neutral-600">{t('byKind')}</h3>
                <ul className="text-sm">
                  {Object.entries(s.by_kind).map(([kind, n]) => (
                    <li key={kind}>
                      <code>{kind}</code> {n}
                    </li>
                  ))}
                </ul>
              </>
            ) : null}
            {s.recent.length ? (
              <>
                <h3 className="mt-4 text-sm font-semibold text-neutral-600">{t('recent')}</h3>
                <ul className="text-sm">
                  {s.recent.map((e, i) => (
                    <li key={i}>
                      {when(e.received_at)} · <code>{e.kind}</code>
                    </li>
                  ))}
                </ul>
              </>
            ) : null}
          </section>
          <section>
            <h2 className="mb-2 font-semibold">{t('commands')}</h2>
            {s.commands.length ? (
              <ul className="text-sm">
                {s.commands.map((c, i) => (
                  <li key={i}>
                    {when(c.at)} · {c.actor} · <code>{c.command}</code> · {c.ok ? 'ok' : c.error}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-neutral-600">{t('noCommands')}</p>
            )}
          </section>
        </div>
      )}
    </main>
  )
}
