import { getLocale, getTranslations } from 'next-intl/server'
import { AD_CHANNELS } from '@/lib/data/simple-growth-shared'
import { yearSpan, type Calendar } from '@/lib/growth/playbook'
import { card, cardTable, head } from '../v2kit'
import { BlackoutForm, RemoveBlackout } from './controls'

/** the rows' bar colours (calRows: paid search amber, LinkedIn blue, email apricot, events lilac, blackout the hairline) */
const AD_BG: Record<string, string> = {
  google_ads: '#F5DC96', linkedin: '#CFE0F5', facebook: '#B5DAD4', newsletter: '#F6D9C6', webinar: '#E7DAF2', other: '#F2EAD6',
}
const EMAIL_BG = '#F6D9C6'
const BLACKOUT_BG = '#E8DFC9'
const GRID = '[grid-template-columns:150px_repeat(12,minmax(0,1fr))]'

type Bar = { id: string; t: string; from: string; to: string; bg: string }

/**
 * Marketing campaigns › Calendar and offers (GrowthPlaybook.dc.html, v.calendar) on growth_calendar (0076): the year's ad
 * campaigns by channel, the email campaigns sent or planned, and blackout periods people mark. The search-interest row needs
 * Google Trends; offers, referral and partners have no record in Sentral (V-GR2-38). Adding a blackout needs Campaigns › Add.
 */
export async function CalendarView({ d, product, canAdd }: { d: Calendar; product: string; canAdd: boolean }) {
  const t = await getTranslations('simpleGrowth.playbook.calendar')
  const tc = await getTranslations('simpleGrowth.campaigns.channels')
  const locale = await getLocale()
  const loc = locale === 'no' ? 'nb-NO' : locale
  const thisYear = Number(d.today.slice(0, 4)) === d.year
  const nowMonth = Number(d.today.slice(5, 7)) - 1
  const months = Array.from({ length: 12 }, (_, i) => new Intl.DateTimeFormat(loc, { month: 'short', timeZone: 'UTC' }).format(new Date(Date.UTC(d.year, i, 15))))
  const day = (iso: string) => new Intl.DateTimeFormat(loc, { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso}T12:00:00Z`))
  const span = (from: string, to: string) => (from === to ? day(from) : `${day(from)} – ${day(to)}`)

  const rows: { key: string; n: string; items: Bar[] }[] = [
    ...AD_CHANNELS.filter((c) => d.ads.some((a) => a.channel === c)).map((c) => ({
      key: c, n: tc(c), items: d.ads.filter((a) => a.channel === c).map((a) => ({ id: a.id, t: a.name, from: a.from, to: a.to, bg: AD_BG[c] ?? '#F2EAD6' })),
    })),
    ...(d.emails.length ? [{ key: 'email', n: t('rows.email'), items: d.emails.map((e) => ({ id: e.id, t: e.name, from: e.on, to: e.on, bg: EMAIL_BG })) }] : []),
    { key: 'blackout', n: t('rows.blackout'), items: d.blackouts.map((b) => ({ id: b.id, t: b.name, from: b.from, to: b.to, bg: BLACKOUT_BG })) },
  ]
  const nothing = !d.ads.length && !d.emails.length && !d.blackouts.length

  return (
    <div className="flex flex-col gap-[14px]">
      <section className={`${card} overflow-x-auto px-[18px] py-4`}>
        <div className="flex min-w-[820px] flex-col gap-[6px]">
          <div className={`grid ${GRID} gap-[3px] text-10.5 font-bold text-muted`}>
            <span>{d.year}</span>
            {months.map((m, i) => <span key={i} className={`text-center ${thisYear && i === nowMonth ? 'text-ink' : ''}`}>{m}</span>)}
          </div>
          {rows.map((r) => (
            <div key={r.key} className="relative grid h-[30px] items-center [grid-template-columns:150px_minmax(0,1fr)]">
              <b className="truncate text-12">{r.n}</b>
              <span className="relative h-full">
                {r.items.map((i) => {
                  const s = yearSpan(i.from, i.to, d.year)
                  if (!s) return null
                  const tip = `${i.t} · ${span(i.from, i.to)}`
                  return (
                    <span key={i.id} title={tip}
                      className="absolute bottom-1 top-1 flex items-center overflow-hidden whitespace-nowrap rounded-7 border border-[rgba(25,21,16,.15)] px-[6px] text-10.5 font-bold"
                      style={{ left: `${s.x}%`, width: `${s.w}%`, minWidth: 28, background: i.bg }}>
                      {i.t}
                    </span>
                  )
                })}
              </span>
            </div>
          ))}
          {nothing ? <div className="text-12 text-muted">{t('empty', { year: d.year })}</div> : null}
          <div className="text-11.5 text-muted">{t('footnote')}</div>
        </div>
      </section>

      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr))]">
        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('blackouts')}</b>
            <span className="text-12 text-muted">{t('blackoutsNote')}</span>
          </div>
          {!d.blackouts.length ? <p className="m-0 border-b border-line px-[18px] py-[12px] text-12.5 text-muted">{t('noBlackouts', { year: d.year })}</p> : null}
          {d.blackouts.map((b) => (
            <div key={b.id} className="flex items-center gap-3 border-b border-line px-[18px] py-[9px] text-12.5">
              <b className="min-w-0 flex-1 [overflow-wrap:anywhere]">{b.name}</b>
              <span className="whitespace-nowrap text-muted">{span(b.from, b.to)}</span>
              {canAdd ? <RemoveBlackout id={b.id} name={b.name} /> : null}
            </div>
          ))}
          {canAdd ? <BlackoutForm product={product} year={d.year} /> : null}
        </section>
        <section className={cardTable}>
          <div className={head}>
            <b className="text-15">{t('offers')}</b>
          </div>
          <p className="m-0 px-[18px] py-[14px] text-12.5 leading-[1.5] text-muted">{t('offersNone')}</p>
        </section>
      </div>
    </div>
  )
}
