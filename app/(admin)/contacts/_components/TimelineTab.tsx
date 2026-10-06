'use client'

import { useTranslations } from 'next-intl'
import type { Activity } from '@/lib/data/contacts'
import type { TabProps } from './ContactsScreen'
import { ACT_BG, localDay, useNav } from './util'

const COLS = '[grid-template-columns:200px_repeat(12,minmax(0,1fr))]'

/**
 * Timeline (Contacts.dc.html, v.timeline): each person's activities by ISO week, twelve weeks with this
 * week fifth. A dot is red when the activity is not done and its time has passed.
 */
export function TimelineTab({ data, me }: TabProps) {
  const t = useTranslations('contacts')
  const { go } = useNav()
  const tl = data.timeline!
  const first = new Date(`${tl.weeks[0]!.start}T00:00:00Z`).getTime()
  const weekOf = (a: Activity) => (a.starts_at ? Math.floor((new Date(`${localDay(new Date(a.starts_at), me.tz)}T00:00:00Z`).getTime() - first) / (7 * 86_400_000)) : -1)

  const rows = new Map<string, { id: string; name: string; org: string | null; cells: Activity[][] }>()
  for (const a of tl.activities) {
    if (!a.person_id || !a.person) continue
    const w = weekOf(a)
    if (w < 0 || w > 11) continue
    const r = rows.get(a.person_id) ?? { id: a.person_id, name: a.person, org: a.organization, cells: Array.from({ length: 12 }, () => []) }
    r.cells[w]!.push(a)
    rows.set(a.person_id, r)
  }
  const list = [...rows.values()].sort((a, b) => a.name.localeCompare(b.name))

  return (
    <div className="overflow-x-auto rounded-20 border border-line bg-surface px-[18px] py-4">
      <div className="min-w-[900px]">
        <div className={`grid border-b border-line pb-2 text-10.5 font-bold uppercase tracking-[.06em] text-muted ${COLS}`}>
          <span>{t('timeline.person')}</span>
          {tl.weeks.map((w, i) => <span key={w.start} className={`text-center ${i === tl.today ? 'text-ink' : 'text-muted'}`}>{t('timeline.week', { n: w.n })}</span>)}
        </div>
        {list.map((r) => (
          <div key={r.id} className={`relative grid h-[42px] items-center border-b border-line ${COLS}`}>
            <button type="button" onClick={() => go({ person: r.id }, true)} className="flex cursor-pointer flex-col border-none bg-transparent p-0 text-left text-12">
              <b>{r.name}</b><span className="text-11 text-muted">{r.org ?? ''}</span>
            </button>
            {r.cells.map((c, wi) => (
              <span key={wi} className={`flex h-full items-center justify-center gap-[3px] ${wi === tl.today ? 'bg-highlight' : 'bg-transparent'}`}>
                {c.slice(0, c.length > 2 ? 1 : 2).map((a) => {
                  const overdue = !a.done && !!a.overdue
                  return (
                    <span key={a.id} title={`${a.type?.name ?? ''} · ${a.subject}${overdue ? ` · ${t('timeline.overdueShort')}` : ''}`}
                      className={`flex h-[18px] w-[18px] items-center justify-center rounded-6 text-10 ${overdue ? 'text-rust-ink' : 'text-ink'}`}
                      style={{ background: overdue ? '#F0B9A0' : ACT_BG[a.type?.key ?? ''] ?? '#F2EAD6' }}>
                      {a.type?.glyph ?? '•'}
                    </span>
                  )
                })}
                {c.length > 2 ? <span title={c.slice(1).map((a) => a.subject).join(' · ')} className="flex h-[18px] min-w-[18px] items-center justify-center rounded-6 bg-tile px-[3px] text-10">+{c.length - 1}</span> : null}
              </span>
            ))}
          </div>
        ))}
        {list.length === 0 ? <div className="py-[30px] text-center text-13 text-muted">{t('timeline.empty')}</div> : null}
        <div className="mt-[10px] flex flex-wrap gap-[14px] text-11.5 text-muted">
          <span>{t('timeline.legendToday')}</span><span className="text-danger">{t('timeline.legendOverdue')}</span><span>{t('timeline.legendSame')}</span>
        </div>
      </div>
    </div>
  )
}
