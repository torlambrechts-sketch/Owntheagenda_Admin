'use client'

import { useFormatter, useTranslations } from 'next-intl'
import { asNoon, zoned, type Day } from '@/lib/data/activities-time'

const pad = (n: number) => String(n).padStart(2, '0')

/**
 * Dates as the design writes them («Tue 6 Oct», «Monday 5 October 2026», «Tue 09:00»), assembled from
 * single fields: Node and the browser join multi-field formats differently, which breaks hydration.
 */
export function useDates(tz: string) {
  const format = useFormatter()
  const t = useTranslations('activities.date')
  const wd = (x: Day, weekday: 'short' | 'long') => format.dateTime(asNoon(x), { weekday, timeZone: 'UTC' })
  const mon = (x: Day, month: 'short' | 'long') => format.dateTime(asNoon(x), { month, timeZone: 'UTC' })
  const dayOf = (at: Date) => { const z = zoned(at, tz); return { day: { y: z.y, m: z.m, d: z.d }, time: `${pad(z.h)}:${pad(z.min)}` } }
  return {
    weekdayShort: (x: Day) => wd(x, 'short'),
    monthLong: (x: Day) => mon(x, 'long'),
    short: (x: Day) => t('short', { weekday: wd(x, 'short'), day: x.d, month: mon(x, 'short') }),
    long: (x: Day) => t('long', { weekday: wd(x, 'long'), day: x.d, month: mon(x, 'long'), year: x.y }),
    monthTitle: (x: Day) => t('month', { month: mon(x, 'long'), year: x.y }),
    /** «Tue 09:00» for an instant in the staff member's zone; with the date when it is further off. */
    slot: (at: Date, withDate: boolean) => {
      const { day, time } = dayOf(at)
      return withDate ? t('shortTime', { date: t('short', { weekday: wd(day, 'short'), day: day.d, month: mon(day, 'short') }), time }) : t('weekdayTime', { weekday: wd(day, 'short'), time })
    },
    dayOf,
  }
}
