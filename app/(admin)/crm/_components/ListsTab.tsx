'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { download } from '@/lib/xlsx'
import type { CrmLists } from '@/lib/data/simple-crm'
import { CONSENT_TONE, MEMBERS_SHOWN, describeQuery, isMarketingStatus, ruleLine, type CrmRights } from '@/lib/data/simple-crm-shared'
import { exportList } from '../actions'
import { NewListModal } from './NewListModal'

const GRID = 'min-w-[520px] [grid-template-columns:minmax(0,1.3fr)_minmax(0,1.2fr)_110px_120px]'

/**
 * The Lists tab (SimpleCRM.dc.html v.lists): the saved lists — campaign segments (0037), each with its rule and the
 * number of people it matches — and the chosen list: its conditions, who can receive marketing email, the people in it
 * (rec_list with the list's own filter), «Use in email campaign» and «Export CSV».
 */
export function ListsTab({ rights, data, blocked, creating, setCreating }: {
  rights: CrmRights
  data: CrmLists | null
  blocked: 'moduleOff' | 'noRight' | 'failed' | null
  creating: boolean
  setCreating: (v: boolean) => void
}) {
  const t = useTranslations('simpleCrm')
  const tl = useTranslations('simpleCrm.lists')
  const te = useTranslations('common.errors')
  const tc = useTranslations('common')
  const flash = useToast()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [picked, setPicked] = useState<string | null>(null)
  const [exporting, setExporting] = useState(false)

  if (blocked || !data) return <Notice text={tl(blocked === 'moduleOff' ? 'moduleOff' : blocked === 'noRight' ? 'noRight' : 'failed')} />

  const words = (k: string, v?: Record<string, string | number>) => t(k, v)
  const selectedId = pending && picked ? picked : data.selectedId
  const list = data.segments.find((s) => s.id === data.selectedId) ?? null
  const pick = (id: string) => {
    if (id === data.selectedId) return
    setPicked(id)
    start(() => router.push(`/crm?tab=lists&list=${id}` as Route, { scroll: false }))
  }

  const doExport = async () => {
    if (!list || exporting) return
    setExporting(true)
    const r = await exportList(list.id)
    setExporting(false)
    if (!r.ok) { flash(te(r.code)); return }
    const name = r.name.toLowerCase().replace(/[^a-z0-9æøå]+/g, '-').replace(/^-|-$/g, '') || 'list'
    download(new Blob(['﻿' + r.csv], { type: 'text/csv;charset=utf-8' }), `${name}-${new Date().toISOString().slice(0, 10)}.csv`)
    flash(t('flash.exported', { count: r.rows }))
  }

  const conds = list ? describeQuery(list.query, words) : []
  const members = data.members

  return (
    <>
      <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr))]">
        <div className="overflow-hidden rounded-20 border border-line bg-surface">
          <div className="border-b border-line px-4 py-3 text-11 font-bold uppercase tracking-[.1em] text-muted">{tl('saved')}</div>
          {data.segments.map((s) => (
            <button
              key={s.id}
              type="button"
              aria-current={s.id === selectedId ? 'true' : undefined}
              onClick={() => pick(s.id)}
              className={`flex w-full cursor-pointer items-center justify-between gap-[10px] border-b border-line px-4 py-3 text-left ${s.id === selectedId ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="flex min-w-0 flex-col">
                <b className="text-13">{s.name}</b>
                <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11.5 text-muted">{ruleLine(describeQuery(s.query, words))}</span>
              </span>
              <b className="text-13">{s.matches}</b>
            </button>
          ))}
          {data.segments.length === 0 ? (
            <div className="px-4 py-6 text-center text-13 text-muted">{tl(rights.addList ? 'noneYetAdd' : 'noneYet')}</div>
          ) : null}
        </div>

        {list ? (
          <div className={`flex min-w-0 flex-col gap-3 min-[914px]:[grid-column:span_2] ${pending ? 'opacity-60 transition-opacity' : ''}`}>
            <div className="flex flex-col gap-[10px] rounded-20 border border-line bg-surface px-[18px] py-4">
              <div className="flex flex-wrap items-center justify-between gap-[10px]">
                <b className="font-serif text-20">{list.name}</b>
                <span className="flex gap-[6px]">
                  <Link
                    href={'/growth?tab=email' as Route}
                    className="flex h-8 flex-none items-center whitespace-nowrap rounded-9 border border-ink bg-primary px-3 text-12 font-bold text-ink hover:text-ink hover:no-underline"
                  >
                    {tl('useInCampaign')}
                  </Link>
                  <button
                    type="button"
                    disabled={!rights.exportRows || exporting}
                    onClick={() => void doExport()}
                    className="h-8 flex-none cursor-pointer whitespace-nowrap rounded-9 border border-line bg-transparent px-3 text-12 font-semibold disabled:cursor-default disabled:opacity-60"
                  >
                    {tl('export')}
                  </button>
                </span>
              </div>
              <div className="flex flex-wrap items-center gap-[6px]">
                <span className="text-12 text-muted">{tl('whoIsIn')}</span>
                {conds.map((c, i) => <span key={i} className="rounded-9 border border-line bg-canvas px-[10px] py-[5px] text-12">{c}</span>)}
              </div>
              <span className="text-12 text-muted">{tl('countLine', { count: list.matches, subs: list.receivable })}</span>
              {!rights.exportRows ? <span className="text-12 text-muted">{tl('exportNoRight')}</span> : null}
            </div>

            <div className="overflow-hidden rounded-20 border border-line bg-surface">
              {/* at phone width the four columns scroll inside the card rather than overlap */}
              <div className="overflow-x-auto">
              <div className={`grid gap-[10px] border-b border-line px-4 py-[9px] text-10.5 font-bold uppercase tracking-label text-muted ${GRID}`}>
                <span>{tl('cols.person')}</span><span>{tl('cols.account')}</span><span>{tl('cols.role')}</span><span>{tl('cols.status')}</span>
              </div>
              {(members?.rows ?? []).map((p) => (
                <div key={p.id} className={`grid items-center gap-[10px] border-b border-line px-4 py-[9px] text-12.5 ${GRID}`}>
                  <span className="flex min-w-0 flex-col">
                    <b>{p.name}</b>
                    <span className="overflow-hidden text-ellipsis whitespace-nowrap text-11.5 text-muted">{p.email ?? tc('dash')}</span>
                  </span>
                  <span className="overflow-hidden text-ellipsis whitespace-nowrap">{p.organization_id__title ?? tc('dash')}</span>
                  <span>{p.title ?? tc('dash')}</span>
                  <span>
                    {isMarketingStatus(p.marketing_status) ? (
                      <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${CONSENT_TONE[p.marketing_status]}`}>{t(`consent.${p.marketing_status}`)}</span>
                    ) : tc('dash')}
                  </span>
                </div>
              ))}
              </div>
              {data.membersFailed ? <div className="p-6 text-center text-13 text-muted">{tl('membersFailed')}</div> : null}
              {members && members.rows.length === 0 ? <div className="p-6 text-center text-13 text-muted">{tl('empty')}</div> : null}
              {members && members.total > members.rows.length ? (
                <div className="px-4 py-3 text-12 text-muted">{tl('more', { shown: Math.min(MEMBERS_SHOWN, members.rows.length), total: members.total })}</div>
              ) : null}
            </div>
          </div>
        ) : null}
      </div>

      {creating ? (
        <NewListModal
          roles={data.roles}
          onClose={() => setCreating(false)}
          onSaved={(id) => {
            setCreating(false)
            flash(t('flash.listSaved'))
            setPicked(id)
            start(() => router.push(`/crm?tab=lists&list=${id}` as Route, { scroll: false }))
          }}
        />
      ) : null}
    </>
  )
}

function Notice({ text }: { text: string }) {
  return <div className="rounded-20 border border-line bg-surface p-6 text-center text-13 text-muted">{text}</div>
}
