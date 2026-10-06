'use client'

import { useTransition } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { type GroupPreview, type Mailboxes, type Pipelines, type Template } from '@/lib/data/inbox'
import { groupSend } from '../actions'
import { useFail, useGo } from './lib'

export type GroupSource = { kind: 'people'; ids: string[] } | { kind: 'deals'; ids: string[] } | { kind: 'view'; view_id: string }
type Src = 'view' | 'people' | 'deals'

const chip = (on: boolean) => `cursor-pointer rounded-999 border px-3 py-[6px] text-12 ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
const sel = 'h-[30px] rounded-9 border border-line bg-surface text-12'

/**
 * Group email (v.group, COM-07): recipients resolved from a saved view of people, a selection handed over
 * from Contacts, or the open deals of a stage (their person); sales_consent decides who is left out; one
 * message per person from my own mailbox, throttled. The count, the chips and the template are the
 * resolved ones, never a fixed list.
 */
export function GroupView({ canBulk, src, source, preview, previewCode, views, viewId, pipelines, stageId, peopleCount, templates, templateId, mailboxes }: {
  canBulk: boolean
  src: Src
  source: GroupSource | null
  preview: GroupPreview | null
  previewCode: string | null
  views: { id: string; name: string }[]
  viewId: string | null
  pipelines: Pipelines
  stageId: string | null
  peopleCount: number
  templates: Template[]
  templateId: string | null
  mailboxes: Mailboxes
}) {
  const t = useTranslations('inbox.group')
  const ti = useTranslations('inbox')
  const flash = useToast()
  const { fail, text } = useFail()
  const { go } = useGo()
  const [busy, start] = useTransition()

  if (!canBulk) {
    return (
      <div className="flex max-w-[860px] flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-[18px]">
        <b className="text-15">{t('title')}</b>
        <span className="text-13 text-muted">{t('noRight')}</span>
      </div>
    )
  }

  const mode = preview?.consent_mode ?? 'off'
  const sends = (r: GroupPreview['recipients'][number]) => r.excluded === null || (mode === 'warn' && r.excluded !== 'no_address')
  const recipients = preview?.recipients ?? []
  const count = recipients.filter(sends).length
  const excluded = recipients.filter((r) => r.excluded !== null)
  const tpl = templates.find((x) => x.id === templateId) ?? null
  const box = mailboxes.mailboxes.find((m) => m.can_reply && m.status === 'synced') ?? null
  const anyBox = mailboxes.mailboxes.find((m) => m.can_reply) ?? null
  const stageName = pipelines.flatMap((p) => p.stages).find((s) => s.id === stageId)?.name ?? null

  const send = () => {
    if (!source || !tpl || !box) return
    start(async () => {
      const r = await groupSend({ source, mailboxId: box.id, templateId: tpl.id, track: mailboxes.tracking === 'per_email' ? true : null })
      if (!r.ok) return fail(r.code, r.detail)
      flash(t('queued', { n: r.total }))
      go({ folder: 'outbox' }, { reset: true })
    })
  }

  return (
    <div className="flex max-w-[860px] flex-col gap-3 rounded-20 border border-line bg-surface px-[22px] py-[18px]">
      <b className="text-15">{t('title')}</b>
      <div className="flex flex-wrap items-center gap-[6px]">
        <span className="text-12 text-muted">{t('from')}</span>
        {(['view', 'people', 'deals'] as const).map((k) => (
          <button key={k} type="button" aria-pressed={src === k} onClick={() => go({ src: k })} className={chip(src === k)}>
            {k === 'deals' && stageName && src === 'deals' ? t('src.dealsStage', { stage: stageName }) : t(`src.${k}`)}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-[6px] text-12 text-muted">
        {src === 'view' ? (
          views.length ? (
            <select aria-label={t('src.view')} value={viewId ?? ''} onChange={(e) => go({ view: e.target.value || null })} className={sel}>
              <option value="">{t('pickView')}</option>
              {views.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
            </select>
          ) : <span>{t('noViews')}</span>
        ) : src === 'people' ? (
          <span>{peopleCount ? t('selected', { n: peopleCount }) : t('noSelection')}</span>
        ) : (
          <select aria-label={t('src.deals')} value={stageId ?? ''} onChange={(e) => go({ stage: e.target.value || null })} className={sel}>
            <option value="">{t('pickStage')}</option>
            {pipelines.map((p) => (
              <optgroup key={p.id} label={p.name}>
                {p.stages.map((s) => <option key={s.id} value={s.id}>{s.name} ({s.open_deals})</option>)}
              </optgroup>
            ))}
          </select>
        )}
        <select aria-label={ti('composer.template')} value={templateId ?? ''} onChange={(e) => go({ tpl: e.target.value || null })} className={sel}>
          <option value="">{ti('composer.template')}</option>
          {templates.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
        </select>
      </div>

      {previewCode ? <div className="text-12 text-danger">{text(previewCode)}</div> : null}

      {recipients.length ? (
        <div className="flex flex-wrap gap-[5px]">
          {recipients.map((r) => (
            <span
              key={r.person_id}
              title={r.excluded ? t(`excluded.${r.excluded}`) : r.email ?? undefined}
              className={`rounded-999 px-[10px] py-1 text-12 ${sends(r) ? 'bg-tile' : 'bg-transparent text-faint line-through'}`}
            >
              {r.name}
            </span>
          ))}
        </div>
      ) : source && !previewCode ? <div className="text-12 text-muted">{t('noRecipients')}</div> : null}

      <div className="text-12 text-muted">
        {[
          t('summary.count', { n: count }),
          tpl ? t('summary.template', { name: tpl.name }) : t('summary.noTemplate'),
          t('summary.merge'),
          t('summary.consent', { mode: t(`consent.${mode}`) }),
          t('summary.limit', { limit: preview?.limit ?? t('unlimited') }),
          ...(excluded.length ? [t('summary.excluded', { n: excluded.length, mode: t(`consentEffect.${mode}`) })] : []),
        ].join(' · ')}
      </div>

      <div className="whitespace-pre-wrap rounded-14 border border-line bg-canvas px-[14px] py-3 text-13 leading-[1.6]">
        {tpl ? tpl.body || t('emptyTemplate') : <span className="text-muted">{t('pickTemplate')}</span>}
      </div>

      {!box ? (
        <div className="rounded-10 bg-amber-bg px-3 py-2 text-12 leading-[1.5] text-amber-ink">
          <b>{anyBox ? ti(`mailboxState.${anyBox.status}`) : ti('composer.noMailbox')}</b> {t('notConnected')}{' '}
          <Link href="/inbox?folder=settings" className="whitespace-nowrap font-bold text-amber-ink underline">{ti('reconnectLink')}</Link>
        </div>
      ) : null}

      <div className="flex justify-end gap-2">
        <button
          type="button"
          disabled={busy || !box || !tpl || count === 0}
          onClick={send}
          className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-4 text-13 font-bold disabled:cursor-default disabled:opacity-60"
        >
          {t('send', { n: count })}
        </button>
      </div>
    </div>
  )
}
