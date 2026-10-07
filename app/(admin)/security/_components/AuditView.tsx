'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { AuditPage, AuditRow } from '@/lib/data/security'
import { sx, useIsToday, useWhen } from './kit'

const COLS = '[grid-template-columns:120px_130px_90px_minmax(0,1.6fr)_minmax(0,1fr)_100px]'
const KIND_BG: Record<string, string> = { read: 'bg-teal-soft', write: 'bg-highlight', export: 'bg-peach', role: 'bg-lilac', security: 'bg-ok-bg' }
const CHIPS = ['all', 'read', 'write', 'export', 'role', 'security'] as const

/**
 * Audit log (SEC-11; D-12): audit_search with its kind chips, the search box and a cursor. The audit holds names, ids and
 * counts, never values: «What» is the action's wording plus the target's current title, read now ((removed) when it is
 * gone). Every search is itself audited by the function, with the filter's keys only.
 */
export function AuditView({ page, q, kind, cursor, now }: { page: AuditPage | null; q: string; kind: string; cursor: number | null; now: string }) {
  const t = useTranslations('security.audit')
  const router = useRouter()
  const when = useWhen(now)
  const isToday = useIsToday(now)
  const [text, setText] = useState(q)
  const href = (p: { q?: string; kind?: string; cursor?: number | null }) => {
    const sp = new URLSearchParams({ tab: 'audit' })
    const qq = p.q ?? q
    const kk = p.kind ?? kind
    if (qq) sp.set('q', qq)
    if (kk && kk !== 'all') sp.set('kind', kk)
    if (p.cursor) sp.set('cursor', String(p.cursor))
    return `/security?${sp.toString()}` as Route
  }

  return (
    <div className="flex flex-col gap-[10px]">
      <div className="flex flex-wrap gap-2">
        <form role="search" className="flex flex-[1_1_260px]" onSubmit={(e) => { e.preventDefault(); router.push(href({ q: text.trim(), cursor: null })) }}>
          <input
            className="h-9 w-full rounded-10 border border-solid border-line bg-surface px-[11px] text-13 text-ink"
            placeholder={t('placeholder')}
            aria-label={t('placeholder')}
            maxLength={100}
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
        </form>
        {CHIPS.map((k) => {
          const on = (kind || 'all') === k
          return (
            <Link key={k} href={href({ kind: k, cursor: null })} aria-current={on ? 'true' : undefined}
              className={`inline-flex cursor-pointer items-center rounded-999 border border-solid px-3 py-[6px] text-12 text-ink hover:text-ink hover:no-underline ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`}>
              {t(`kinds.${k}`)}
            </Link>
          )
        })}
      </div>
      <section className={sx.card} aria-label={t('title')}>
        <div className="overflow-x-auto">
          <div className={`${sx.row} grid min-w-[760px] gap-[10px] py-[9px] ${sx.colHead} ${COLS}`}>
            <span>{t('cols.when')}</span><span>{t('cols.who')}</span><span>{t('cols.kind')}</span><span>{t('cols.what')}</span><span>{t('cols.org')}</span><span>{t('cols.source')}</span>
          </div>
          {page === null ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('failed')}</div>
          ) : page.rows.length === 0 ? (
            <div className={`${sx.row} py-[14px] text-12.5 text-muted`}>{t('empty')}</div>
          ) : (
            page.rows.map((a) => (
              <div key={a.id} className={`${sx.row} grid min-w-[760px] gap-[10px] py-[9px] text-12.5 ${COLS}`}>
                <span className="text-muted">{when(a.at, { time: isToday(a.at) })}</span>
                <b className="min-w-0 break-words"><Who a={a} /></b>
                <span><span className={`rounded-999 px-2 py-[2px] text-10.5 font-bold ${KIND_BG[a.kind]}`}>{t(`kinds.${a.kind}`)}</span></span>
                <span className="min-w-0 break-words"><What a={a} /></span>
                <span className="text-muted">{a.organization ?? '—'}</span>
                <span className="text-muted">{a.source ? t(`sources.${a.source}`) : '—'}</span>
              </div>
            ))
          )}
          <div className="flex flex-wrap items-center justify-between gap-2 px-[18px] py-[10px] text-11.5 text-muted">
            <span>{t('footnote', { reason: t(page?.typed_reason === 'on' ? 'reasonOn' : 'reasonOff') })}</span>
            <span className="flex gap-3">
              {cursor ? <Link href={href({ cursor: null })}>{t('newest')}</Link> : null}
              {page?.next ? <Link href={href({ cursor: page.next })}>{t('older')}</Link> : null}
            </span>
          </div>
        </div>
      </section>
    </div>
  )
}

function Who({ a }: { a: AuditRow }) {
  const t = useTranslations('security.audit.who')
  if (a.who) return <>{a.principal_kind && a.principal_kind !== 'staff' ? t(`via.${a.principal_kind}`, { name: a.who }) : a.who}</>
  if (a.principal_kind === 'workflow') return <>{t('workflow', { name: a.workflow ?? '—' })}</>
  if (a.principal_kind) return <>{t(`kind.${a.principal_kind}`)}</>
  return <>—</>
}

function What({ a }: { a: AuditRow }) {
  const t = useTranslations('security.audit')
  const key = a.action ?? ''
  const action = a.command ? t('command', { command: key }) : t.has(`actions.${key}`) ? t(`actions.${key}`) : null
  const target = !a.target ? null
    : a.target.state === 'ok' ? a.target.title ?? null
    : a.target.state === 'removed' ? t('removed')
    : a.target.state === 'hidden' ? t('hidden')
    : null
  return (
    <>
      {action ?? <span className="[font-family:ui-monospace,Menlo,monospace] text-11.5">{key || '—'}</span>}
      {target ? <> · {target}</> : null}
      {a.ok === false ? <span className="text-danger"> · {t('refused')}</span> : null}
      {a.reason ? <span className="text-muted"> · {t('withReason')}</span> : null}
    </>
  )
}
