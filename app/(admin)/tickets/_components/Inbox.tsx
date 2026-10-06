'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import { PTONE, useDur, useGo } from './lib'
import { TicketDetailPanel, type DetailProps } from './TicketDetail'
import type { TicketConfig, TicketList, TicketQuery } from '@/lib/data/tickets'

type Props = {
  list: TicketList
  query: TicketQuery
  selectedId: string | null
  config: TicketConfig
  detail: DetailProps | null
}

/** Inbox (Tickets.dc.html, v.inbox): queue chips with counts, filter and sort, the list, and the open ticket. */
export function Inbox({ list, query, selectedId, config, detail }: Props) {
  const t = useTranslations('tickets')
  const dur = useDur()
  const { go } = useGo()
  const [q, setQ] = useState(query.q)
  const typed = useRef(false)

  // the filter follows typing after a short pause; the server filters (tickets_get q)
  useEffect(() => {
    if (!typed.current) return
    const h = setTimeout(() => go({ q: q.trim() || null, ticket: null }), 300)
    return () => clearTimeout(h)
  }, [q, go])

  const queues = config.queues.filter((x) => x.allowed)
  const chips: { key: string; label: string; count: number }[] = [
    { key: 'open', label: t('views.open'), count: list.counts.open },
    { key: 'mine', label: t('views.mine'), count: list.counts.mine },
    { key: 'unassigned', label: t('views.unassigned'), count: list.counts.unassigned },
    { key: 'sla', label: t('views.sla'), count: list.counts.sla },
    ...queues.map((x) => ({ key: x.key, label: t.has(`queues.${x.key}`) ? t(`queues.${x.key}`) : x.name, count: list.counts.queues[x.key] ?? 0 })),
    { key: 'closed', label: t('views.closed'), count: list.counts.closed },
  ]
  const target = (p: string) => config.sla.find((s) => s.priority === p)?.first_response_min ?? 0

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap gap-[6px]">
        {chips.map((c) => {
          const on = c.key === query.view
          const hot = c.key === 'sla' && c.count > 0
          return (
            <button
              key={c.key}
              type="button"
              aria-pressed={on}
              onClick={() => go({ view: c.key === 'open' ? null : c.key, ticket: null })}
              className={`flex cursor-pointer items-center gap-[7px] rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}
            >
              {c.label}
              <span className={`flex h-[18px] min-w-[18px] items-center justify-center rounded-999 px-[5px] text-10.5 font-bold ${hot ? 'bg-alert text-surface' : 'bg-[rgba(25,21,16,.08)] text-ink'}`}>
                {c.count}
              </span>
            </button>
          )
        })}
      </div>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="flex gap-[6px] border-b border-line px-3 py-[10px]">
            <input
              value={q}
              onChange={(e) => { typed.current = true; setQ(e.target.value) }}
              placeholder={t('list.filter')}
              aria-label={t('list.filter')}
              className="h-8 min-w-0 flex-1 rounded-9 border border-line bg-canvas px-[10px] text-12.5"
            />
            <select
              value={query.sort}
              onChange={(e) => go({ sort: e.target.value === 'sla' ? null : e.target.value })}
              aria-label={t('list.sortLabel')}
              className="h-8 rounded-9 border border-line bg-surface text-12"
            >
              {(['sla', 'priority', 'newest'] as const).map((s) => <option key={s} value={s}>{t(`list.sort.${s}`)}</option>)}
            </select>
          </div>
          <div className="max-h-[720px] overflow-auto">
            {list.rows.map((r) => {
              const open = r.status !== 'resolved' && r.status !== 'closed'
              const left = r.first_response_left_min
              const sla = !open ? '' : r.responded ? t('list.responded') : left === null ? '' : left < 0 ? t('list.overdue', { dur: dur(left, true) }) : t('list.left', { dur: dur(left, true) })
              const slaC = !r.responded && open && left !== null && left < 0 ? 'text-danger' : !r.responded && open && left !== null && left < target(r.priority) * 0.3 ? 'text-warn-ink' : 'text-muted'
              const on = r.id === selectedId
              return (
                <button
                  key={r.id}
                  type="button"
                  aria-current={on ? 'true' : undefined}
                  onClick={() => go({ ticket: r.id })}
                  className={`flex w-full cursor-pointer gap-[10px] border-0 border-b border-line py-[11px] pl-[10px] pr-3 text-left ${on ? 'bg-highlight' : 'bg-transparent'}`}
                >
                  <span className={`w-[5px] self-stretch rounded-999 ${PTONE[r.priority].bar}`} />
                  <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
                    <span className="flex justify-between gap-2 whitespace-nowrap text-11 text-muted">
                      <span className="min-w-0 overflow-hidden text-ellipsis"><b className="text-ink">{r.ref}</b> · {t(`types.${r.type}`)}</span>
                      <span className={`flex-none font-bold ${slaC}`}>{sla}</span>
                    </span>
                    <span className={`text-13 leading-[1.3] ${r.status === 'new' ? 'font-bold' : 'font-semibold'}`}>{r.subject}</span>
                    <span className="flex justify-between gap-2 text-11.5 text-muted">
                      <span className="overflow-hidden text-ellipsis whitespace-nowrap">{r.organization?.name ?? t('list.noOrg')}</span>
                      <span className="whitespace-nowrap">{t(`statuses.${r.status}`)}</span>
                    </span>
                  </span>
                </button>
              )
            })}
            {list.rows.length === 0 ? <div className="p-[30px] text-center text-13 text-muted">{t('list.empty')}</div> : null}
          </div>
        </div>
        {detail ? (
          <TicketDetailPanel key={detail.ticket.id} {...detail} />
        ) : (
          <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-10 text-center text-13 text-muted">{t('detail.none')}</div>
        )}
      </div>
    </div>
  )
}
