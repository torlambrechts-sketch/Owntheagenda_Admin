import type { Metadata } from 'next'
import { headers } from 'next/headers'
import { createTranslator } from 'next-intl'
import { AuthCard } from '@/components/auth/AuthCard'
import { authButton } from '@/components/auth/styles'
import { messagesFor } from '@/lib/i18n/messages'
import { answer } from './actions'
import { answerCsat, peekCsat } from './csat'
import { clicked, langOf, scoreOf, tokenOk, type CsatLang } from './logic'

type Search = Promise<{ s?: string | string[]; l?: string | string[]; r?: string | string[] }>

// the email's language, not the browser's cookie: the customer has no Sentral account and no lang cookie
const tFor = (lang: CsatLang) => createTranslator({ locale: lang === 'no' ? 'nb' : 'en-GB', messages: messagesFor(lang), namespace: 'supportHub.csatPage' })

export async function generateMetadata({ searchParams }: { searchParams: Search }): Promise<Metadata> {
  const t = tFor(langOf((await searchParams).l))
  return { title: t('title'), robots: { index: false, follow: false }, referrer: 'no-referrer' }
}

/**
 * «How satisfied are you with the help you got?» (0081): the five links in the email that resolves a ticket open this page.
 * Opening it changes nothing unless a person's click opened it (Sec-Fetch-User): then the score is recorded at once. A mail
 * scanner, an app's webview or a redirector gets the page with one button that sends the score, so nobody is told to
 * «open the link in a browser» they are already in. Public, no session, no index; the card names the application's sender,
 * never Sentral. The token is the only authority (only its hash is stored, single use, 30 days).
 */
export default async function CsatPage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Search }) {
  const { token } = await params
  const sp = await searchParams
  const lang = langOf(sp.l)
  const t = tFor(lang)
  const score = scoreOf(sp.s)
  const line = (text: string) => <p className="m-0 text-13 leading-[1.55]">{text}</p>
  if (!tokenOk(token) || score === null) return <AuthCard title={t('title')} sender={{ name: null }}>{line(t('invalid'))}</AuthCard>

  const peek = await peekCsat(token)
  if (!peek) return <AuthCard title={t('title')} sender={{ name: null }}>{line(t('unavailable'))}</AuthCard>
  const sender = { name: peek.from_name }
  const thanks = <AuthCard title={t('thanksTitle')} sender={sender}>{line(t('thanks', { score }))}</AuthCard>
  // after the button: thanks only when the token really is spent
  if (sp.r === 'thanks' && !peek.open) return thanks
  if (!peek.open) return <AuthCard title={t('title')} sender={sender}>{line(t('used'))}</AuthCard>

  let retry = sp.r === 'retry'
  if (!retry && clicked(await headers())) {
    const r = await answerCsat(token, score)
    if (r === 'recorded') return thanks
    if (r === 'closed') return <AuthCard title={t('title')} sender={sender}>{line(t('used'))}</AuthCard>
    retry = true
  }
  return (
    <AuthCard title={t('title')} sender={sender}>
      {line(t('chosen', { score }))}
      {retry ? <p role="alert" className="m-0 text-12.5 leading-[1.5] text-rust-ink">{t('retry')}</p> : null}
      <form action={answer}>
        <input type="hidden" name="token" value={token} />
        <input type="hidden" name="score" value={score} />
        <input type="hidden" name="lang" value={lang} />
        <button type="submit" className={authButton}>{t('send', { score })}</button>
      </form>
    </AuthCard>
  )
}
