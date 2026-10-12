'use client'

import Link from 'next/link'
import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Article, HelpCentre } from '@/lib/data/support-hub'
import { LOCALES, type Locale } from './logic'
import { createArticle, publishArticle, reviewArticle, saveArticle } from '../../support-actions'
import { card, cardInk, useSupportError, Why } from './bits'

const href = (id: string) => `/customers?tab=support&sub=center&article=${id}`
// the list's columns: the design's four from md; on a phone the views column goes
const cols = '[grid-template-columns:minmax(0,1fr)_56px_70px] md:[grid-template-columns:minmax(0,1.6fr)_80px_70px_80px]'
const chip = (on: boolean) => `cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[5px] text-12 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
const field = 'rounded-9 border border-line bg-canvas text-12.5 text-ink'

/**
 * Help centre (SupportHub.dc.html, v.center): the product's articles by translation group, and the editor. Drafting needs
 * tickets:edit_others; publishing stays with tickets:configure (0012), and «published» is Sentral's own state until a public
 * host is chosen (V-V3S-09). Views and «helpful» are not measured yet (V-V3S-05).
 */
export function CentreView({ data, article, product, productName, reviewed, nf }: {
  data: HelpCentre
  article: Article | null
  product: string
  productName: string
  reviewed: string | null
  nf: NumberFormat
}) {
  const t = useTranslations('supportHub.center')
  const dash = useTranslations('common')('dash')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [cat, setCat] = useState<string>('all')
  const [pending, start] = useTransition()
  const catName = (k: string | null) => data.categories.find((c) => c.key === k)?.name ?? k ?? t('noCategory')
  const shown = data.articles.filter((a) => cat === 'all' || (cat === 'known' ? a.problem : a.category_key === cat))
  const add = () => start(async () => {
    const r = await createArticle({ product, title: t('newTitle', { n: data.articles.length + 1 }), category_key: cat === 'all' || cat === 'known' ? null : cat })
    if (!r.ok) { flash(errorText(r.code)); return }
    flash(t('created'))
    router.push(href(r.id) as never)
  })
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={`${card} overflow-hidden`}>
        <div className="flex flex-wrap items-center gap-[6px] border-b border-line px-4 py-3">
          {[{ key: 'all', name: t('all') }, ...data.categories.filter((c) => data.articles.some((a) => a.category_key === c.key)), { key: 'known', name: t('known') }].map((c) => (
            <button key={c.key} type="button" aria-pressed={cat === c.key} onClick={() => setCat(c.key)} className={chip(cat === c.key)}>{c.name}</button>
          ))}
          <span className="flex-1" />
          <button
            type="button"
            onClick={add}
            disabled={!data.can_edit || pending}
            title={data.can_edit ? undefined : t('editWhy')}
            className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold text-ink disabled:cursor-not-allowed disabled:opacity-60"
          >
            {t('add')}
          </button>
        </div>
        {!data.measured ? <div className="border-b border-line px-4 py-2"><Why>{t('notMeasured')}</Why></div> : null}
        {shown.length === 0 ? <div className="px-4 py-[14px] text-12.5 text-muted">{t('empty')}</div> : null}
        {shown.map((a) => {
          const on = article?.group_id === a.group_id
          return (
            <Link
              key={a.group_id}
              href={href(a.id) as never}
              aria-current={on ? 'true' : undefined}
              className={`grid w-full items-center gap-[10px] border-b border-line px-4 py-[10px] text-left text-12.5 text-ink hover:text-ink hover:no-underline ${cols} ${on ? 'bg-highlight' : 'bg-transparent'}`}
            >
              <span className="flex min-w-0 flex-col">
                <b className="[overflow-wrap:anywhere]">{a.title}</b>
                <span className="text-11 text-muted">{[catName(a.category_key), ...a.locales.map((l) => t(`langs.${l}`))].join(' · ')}</span>
              </span>
              <span className="hidden text-muted md:inline">{t('views', { n: a.views === null ? dash : formatNumber(a.views, nf) })}</span>
              <span className="font-bold text-muted" title={t('helpfulWhy')}>{dash}</span>
              <span className={`text-11.5 font-bold ${a.status === 'published' ? 'text-link' : 'text-warn-ink'}`}>{t(`state.${a.status}`)}</span>
            </Link>
          )
        })}
      </div>
      {article ? (
        <Editor key={`${article.id}:${article.version}`} data={data} article={article} productName={productName} reviewed={reviewed} />
      ) : (
        <div className={`${cardInk} px-5 py-4 text-12.5 text-muted`}>{t('none')}</div>
      )}
    </div>
  )
}

function Editor({ data, article, productName, reviewed }: { data: HelpCentre; article: Article; productName: string; reviewed: string | null }) {
  const t = useTranslations('supportHub.center')
  const flash = useToast()
  const errorText = useSupportError()
  const router = useRouter()
  const [title, setTitle] = useState(article.title)
  const [body, setBody] = useState(article.body)
  const [seo, setSeo] = useState(article.seo_title ?? '')
  const [page, setPage] = useState(article.app_pages[0] ?? '')
  const [category, setCategory] = useState(article.category_key ?? '')
  const [missing, setMissing] = useState<Locale | null>(null)
  const [pending, start] = useTransition()
  const values = { title: title.trim(), body, seo_title: seo.trim(), app_pages: page ? [page] : [], category_key: category || null }
  const dirty = values.title !== article.title || body !== article.body || values.seo_title !== (article.seo_title ?? '')
    || page !== (article.app_pages[0] ?? '') || (category || null) !== article.category_key
  const pages = page && !data.pages.includes(page) ? [page, ...data.pages] : data.pages
  const published = article.status === 'published'

  const save = async () => {
    const r = await saveArticle({ id: article.id, version: article.version, values })
    if (!r.ok) { flash(errorText(r.code)); return false }
    return true
  }
  const onSave = () => start(async () => {
    if (await save()) { flash(t('saved')); router.refresh() }
  })
  const onPublish = () => start(async () => {
    if (dirty && !(await save())) return
    const r = await publishArticle({ id: article.id, on: !published })
    if (!r.ok) { flash(errorText(r.code)); router.refresh(); return }
    flash(published ? t('unpublished') : t('published'))
    router.refresh()
  })
  const onReview = () => start(async () => {
    const r = await reviewArticle({ id: article.id })
    if (!r.ok) { flash(errorText(r.code)); return }
    flash(t('reviewedToast'))
    router.refresh()
  })
  const pickLang = (l: Locale) => {
    const s = article.siblings.find((x) => x.locale === l)
    if (s) { setMissing(null); if (s.id !== article.id) router.push(href(s.id) as never) }
    else setMissing(l)
  }
  const createLang = (l: Locale) => start(async () => {
    const r = await createArticle({ product: article.product, locale: l, group_id: article.group_id, title: article.title })
    if (!r.ok) { flash(errorText(r.code)); return }
    flash(t('created'))
    router.push(href(r.id) as never)
  })

  const canEdit = data.can_edit
  return (
    <div className={`${cardInk} flex flex-col gap-[10px] px-5 py-4`}>
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        readOnly={!canEdit}
        aria-label={t('titleLabel')}
        className="h-10 rounded-10 border border-line bg-canvas px-[11px] font-serif text-18 font-semibold"
      />
      <div className="flex flex-wrap items-center gap-[6px]">
        <div className="flex rounded-9 bg-tile p-[3px]" role="group" aria-label={t('langsLabel')}>
          {LOCALES.map((l) => {
            const on = (missing ?? article.locale) === l
            return (
              <button key={l} type="button" aria-pressed={on} onClick={() => pickLang(l)}
                className={`cursor-pointer rounded-7 border-none px-[10px] py-[5px] text-12 text-ink ${on ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
                {t(`langs.${l}`)}
              </button>
            )
          })}
        </div>
        <span className="text-11.5 text-muted">{t('slug', { slug: article.slug })}</span>
      </div>
      {missing ? (
        <div className="flex flex-wrap items-center gap-2 rounded-12 border border-line bg-canvas px-3 py-[10px] text-12.5">
          <span className="flex-1">{t('missing', { lang: t(`langs.${missing}`) })}</span>
          <button type="button" disabled={!canEdit || pending} onClick={() => createLang(missing)} title={canEdit ? undefined : t('editWhy')}
            className="h-[30px] cursor-pointer whitespace-nowrap rounded-9 border border-ink bg-primary px-[11px] text-12 font-bold text-ink disabled:cursor-not-allowed disabled:opacity-60">
            {t('createLang', { lang: t(`langs.${missing}`) })}
          </button>
        </div>
      ) : null}
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        readOnly={!canEdit}
        aria-label={t('bodyLabel')}
        className="min-h-[160px] rounded-12 border border-line bg-canvas px-3 py-[11px] text-13 leading-[1.6]"
      />
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="flex flex-col gap-1 text-11.5 text-muted">
          {t('seo')}
          <input value={seo} onChange={(e) => setSeo(e.target.value)} readOnly={!canEdit} placeholder={t('seoPlaceholder', { title: title.trim(), product: productName })}
            className={`h-8 px-[9px] ${field}`} />
        </label>
        <label className="flex flex-col gap-1 text-11.5 text-muted">
          {t('page')}
          <select value={page} onChange={(e) => setPage(e.target.value)} disabled={!canEdit} className={`h-8 ${field}`}>
            <option value="">{t('pageNone')}</option>
            {pages.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-11.5 text-muted">
          {t('category')}
          <select value={category} onChange={(e) => setCategory(e.target.value)} disabled={!canEdit} className={`h-8 ${field}`}>
            <option value="">{t('noCategory')}</option>
            {data.categories.map((c) => <option key={c.key} value={c.key}>{c.name}</option>)}
          </select>
        </label>
      </div>
      <div className="flex flex-wrap items-center gap-[6px] text-11.5 text-muted">
        <span>{t('linked', { n: article.linked_tickets })}</span>
        {article.problem_number ? <span>· {t('problem', { ref: `T-${article.problem_number}` })}</span> : null}
        <span>· {reviewed ? t('reviewed', { when: reviewed, by: article.reviewed_by ?? '' }) : t('notReviewed')}</span>
        {canEdit ? (
          <button type="button" onClick={onReview} disabled={pending} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link underline-offset-2 hover:underline">
            {t('markReviewed')}
          </button>
        ) : null}
      </div>
      <div className="flex flex-wrap justify-end gap-2">
        <button type="button" disabled title={t('aiWhy')} className="h-[34px] cursor-not-allowed rounded-10 border border-ink bg-ink px-[13px] text-12.5 font-bold text-canvas opacity-60">{t('ai')}</button>
        {canEdit ? (
          <button type="button" onClick={onSave} disabled={!dirty || pending || !values.title}
            className="h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-[13px] text-12.5 font-semibold text-ink disabled:cursor-default disabled:opacity-60">
            {t('save')}
          </button>
        ) : null}
        <button type="button" onClick={onPublish} disabled={!data.can_publish || pending || !values.title}
          title={data.can_publish ? undefined : t('publishWhy')}
          className="h-[34px] cursor-pointer rounded-10 border border-ink bg-primary px-[14px] text-12.5 font-bold text-ink disabled:cursor-not-allowed disabled:opacity-60">
          {published ? t('unpublish') : t('publish')}
        </button>
      </div>
      <div className="flex flex-col items-end gap-[2px] text-right">
        <Why>{t('aiWhy')}</Why>
        {!data.can_publish ? <Why>{t('publishWhy')}</Why> : null}
        {!canEdit ? <Why>{t('editWhy')}</Why> : null}
      </div>
    </div>
  )
}
