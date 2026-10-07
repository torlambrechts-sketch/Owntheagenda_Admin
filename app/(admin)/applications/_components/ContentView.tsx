'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useTranslations } from 'next-intl'
import type { Content } from '@/lib/data/platform'
import { k, useAgo } from './kit'

const PRODUCT_CARDS = ['question_set', 'pulse_templates', 'tiltak', 'legal', 'templates'] as const

/**
 * Content (Appendix 2 Content management; D-23). The product's question set, pulse templates, tiltak library, legal
 * references and templates stay in the product: each card names the command it is read through, or that none exists
 * yet, and shows no number it cannot have. Drafts and roll-back wait for product commands, so those buttons are off.
 * Help texts and macros are the platform's own and are real.
 */
export function ContentView({ apps, current, content }: { apps: { key: string; name: string }[]; current: string | null; content: Content | null }) {
  const t = useTranslations('platform.content')
  const ago = useAgo()
  const app = apps.find((a) => a.key === current) ?? null

  return (
    <div className="flex flex-col gap-3">
      {apps.length > 1 ? (
        <div className="flex flex-wrap gap-[6px]">
          {apps.map((a) => (
            <Link
              key={a.key}
              href={`/applications?tab=content&app=${a.key}` as Route}
              aria-current={a.key === current ? 'true' : undefined}
              className={`rounded-999 border px-3 py-[5px] text-12 hover:no-underline ${a.key === current ? 'border-ink bg-highlight font-bold text-ink hover:text-ink' : 'border-line-strong font-medium text-ink hover:text-ink'}`}
            >
              {a.name}
            </Link>
          ))}
        </div>
      ) : null}
      {!content || !app ? <div className={`${k.card} ${k.empty}`}>{t('noApp')}</div> : (
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr))]">
          {PRODUCT_CARDS.every((c) => !content.cards[c].command) ? (
            <div className={`${k.cardPad} gap-2`}>
              <b className="text-14">{t('productContent', { name: app.name })}</b>
              <span className="text-12.5 leading-[1.5] text-ink-2">{t('noCommands', { name: app.name })}</span>
            </div>
          ) : PRODUCT_CARDS.map((c) => {
            const command = content.cards[c].command
            return (
              <div key={c} className={`${k.cardPad} gap-2`}>
                <div className="flex justify-between gap-2">
                  <b className="text-14">{t(`cards.${c}.name`)}</b>
                  <span className="whitespace-nowrap rounded-999 bg-tile px-[9px] py-[2px] text-11 font-bold">{t('inProduct', { name: app.name })}</span>
                </div>
                <span className="text-12.5 leading-[1.5] text-ink-2">{t(`cards.${c}.description`)}</span>
                <span className="text-11.5 text-muted">{command ? t('readThrough', { command }) : t('noReadCommand', { name: app.name })}</span>
                <Buttons draft={content.draft_command} rollback={content.rollback_command} />
              </div>
            )
          })}
          <div className={`${k.cardPad} gap-2`}>
            <div className="flex justify-between gap-2">
              <b className="text-14">{t('cards.help.name')}</b>
              <span className="whitespace-nowrap rounded-999 bg-tile px-[9px] py-[2px] text-11 font-bold">{t('live', { count: content.help.published })}</span>
            </div>
            <span className="text-12.5 leading-[1.5] text-ink-2">{t('cards.help.description')}</span>
            <span className="text-11.5 text-muted">
              {content.help.last_change ? t('lastChange', { ago: ago(content.help.last_change), articles: content.help.articles, macros: content.help.macros }) : t('noArticles')}
            </span>
            <div className="flex gap-[6px]">
              <Link href={'/tickets?tab=help' as Route} className={`${k.btn} inline-flex items-center text-ink hover:text-ink hover:no-underline`}>{t('edit')}</Link>
              <button type="button" disabled title={t('noRollback')} className={k.btnSoft}>{t('rollback')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function Buttons({ draft, rollback }: { draft: boolean; rollback: boolean }) {
  const t = useTranslations('platform.content')
  return (
    <div className="flex flex-wrap items-center gap-[6px]">
      <button type="button" disabled={!draft} title={draft ? undefined : t('noDraft')} className={k.btn}>{t('editDraft')}</button>
      <button type="button" disabled={!rollback} title={rollback ? undefined : t('noRollback')} className={k.btnSoft}>{t('rollback')}</button>
      {!draft && !rollback ? <span className="text-11 text-faint">{t('waits')}</span> : null}
    </div>
  )
}
