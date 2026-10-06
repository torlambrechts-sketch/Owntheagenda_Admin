'use client'

import { useCallback, useState } from 'react'
import type { Route } from 'next'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTranslations } from 'next-intl'
import type { RpcCode } from '@/lib/rpc'
import type { ActivityDetail, ActivityRow, Counts, CustomField, DealOption, PersonOption, Scheduling } from '@/lib/data/activities'
import type { CalView, Ctx, ListTab, Sort, Status, Tab } from './shared'
import { CalendarTab } from './CalendarTab'
import { TodoTab } from './TodoTab'
import { SchedulerTab } from './SchedulerTab'
import { RemindersTab } from './RemindersTab'
import { ActivityModal } from './ActivityModal'
import { NextStepPrompt } from './NextStepPrompt'

export type ModalData = {
  detail: ActivityDetail | null
  deals: DealOption[]
  people: PersonOption[]
  fields: CustomField[]
  prefs: Scheduling['prefs']
  calendar: Scheduling['calendar']
}
export type ScreenState = { tab: Tab; view: CalView; date: string; status: Status; list: ListTab; sort: Sort; owner: string | null; type: string | null }
export type Go = (patch: Record<string, string | null>) => void

const DEFAULTS: Record<string, string> = { tab: 'calendar', view: 'week', status: 'open', list: 'all', sort: 'due' }
const TABS: Tab[] = ['calendar', 'todo', 'scheduler', 'reminders']

// the seeded system types carry these names (0010_activities.sql); while unchanged they are shown in the staff member's language
const SYSTEM_NAMES: Record<string, string> = { call: 'Call', meeting: 'Meeting', task: 'Task', deadline: 'Deadline', email: 'Email', lunch: 'Lunch', demo: 'Product demo' }

export function ActivitiesScreen({ ctx: raw, state, rows, counts, loadError, scheduling, modal }: {
  ctx: Ctx
  state: ScreenState
  rows: ActivityRow[]
  counts: Counts | null
  loadError: RpcCode | null
  scheduling: Scheduling | null
  modal: ModalData | null
}) {
  const t = useTranslations('activities')
  const tc = useTranslations('common')
  const ctx: Ctx = {
    ...raw,
    types: raw.types.map((x) => (x.is_system && SYSTEM_NAMES[x.key] === x.name ? { ...x, name: t(`typeNames.${x.key}` as 'typeNames.call') } : x)),
  }
  const router = useRouter()
  const params = useSearchParams()
  const [prompt, setPrompt] = useState<ActivityRow | null>(null)

  const go = useCallback<Go>((patch) => {
    const p = new URLSearchParams(params.toString())
    for (const [k, v] of Object.entries(patch)) {
      if (v === null || v === DEFAULTS[k]) p.delete(k)
      else p.set(k, v)
    }
    const qs = p.toString()
    router.push((qs ? `/activities?${qs}` : '/activities') as Route, { scroll: false })
  }, [params, router])
  const open = useCallback((id: string) => go({ activity: id }), [go])

  const filters = [
    { key: 'owner', label: t('filter.user'), value: state.owner ?? '', opts: [{ v: '', n: t('filter.everyone') }, ...ctx.staff.map((s) => ({ v: s.id, n: s.name }))] },
    { key: 'type', label: t('filter.type'), value: state.type ?? '', opts: [{ v: '', n: t('filter.allTypes') }, ...ctx.types.map((x) => ({ v: x.id, n: x.name }))] },
    { key: 'status', label: t('filter.status'), value: state.status === 'open' ? '' : state.status, opts: [{ v: '', n: t('filter.open') }, { v: 'done', n: t('filter.done') }, { v: 'all', n: t('filter.all') }] },
  ]

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-[6px]" role="tablist">
          {TABS.map((k) => {
            const on = state.tab === k
            return (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={on}
                onClick={() => go({ tab: k, activity: null })}
                className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 ${on ? 'border-ink bg-ink font-bold text-canvas' : 'border-line-strong bg-transparent font-medium text-ink'}`}
              >
                {t(`tabs.${k}`)}
              </button>
            )
          })}
        </div>
        <span className="flex-1" />
        {filters.map((f) => (
          <label key={f.key} className={`flex h-[34px] items-center gap-[5px] rounded-10 border bg-surface pl-[10px] pr-1 text-12 text-muted ${f.value ? 'border-ink' : 'border-line'}`}>
            {f.label}
            <select value={f.value} onChange={(e) => go({ [f.key]: e.target.value || null })} className="border-none bg-transparent text-12.5 font-semibold text-ink">
              {f.opts.map((o) => <option key={o.v} value={o.v}>{o.n}</option>)}
            </select>
          </label>
        ))}
        {ctx.rights.add ? (
          <button type="button" onClick={() => go({ activity: 'new' })} className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold">
            {t('newActivity')}
          </button>
        ) : null}
      </div>

      {loadError ? <div role="alert" className="rounded-14 border border-line bg-surface px-[18px] py-3 text-13 text-danger">{tc(`errors.${loadError}`)}</div> : null}

      {state.tab === 'calendar' ? <CalendarTab ctx={ctx} state={state} rows={rows} go={go} open={open} /> : null}
      {state.tab === 'todo' ? <TodoTab ctx={ctx} state={state} rows={rows} counts={counts} go={go} open={open} onDone={setPrompt} /> : null}
      {state.tab === 'scheduler' && scheduling ? <SchedulerTab ctx={ctx} scheduling={scheduling} /> : null}
      {state.tab === 'reminders' && scheduling ? <RemindersTab ctx={ctx} scheduling={scheduling} /> : null}

      {modal ? (
        <ActivityModal
          key={modal.detail ? `${modal.detail.id}:${modal.detail.version}` : 'new'}
          ctx={ctx}
          data={modal}
          onClose={() => go({ activity: null })}
        />
      ) : null}
      {prompt ? <NextStepPrompt ctx={ctx} row={prompt} onClose={() => setPrompt(null)} /> : null}
    </div>
  )
}
