'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { useTranslations } from 'next-intl'
import { FIXES, STARTER, STARTER_GROUPS, starterFile, type StarterFile } from './starter'
import { CopyButton } from './kit'
import { d } from './styles'

const fileHref = (id: string) => `/development?tab=repo&file=${id}` as Route
const STATUS_TONE: Record<StarterFile['status'], string> = { as_designed: 'text-faint', corrected: 'text-warn-ink', new: 'text-link', removed: 'text-danger' }

/** Repo rules (DevClaude.dc.html v.repo): the files by group on the left, the chosen one on the right. */
export function RepoKit({ selected }: { selected: string | null }) {
  const t = useTranslations('devDelivery.repo')
  const all = selected === 'corrections'
  const f = starterFile(selected)
  return (
    <div className="grid items-start gap-[14px] md:[grid-template-columns:minmax(220px,300px)_minmax(0,1fr)]">
      <nav aria-label={t('files')} className={`${d.card} min-w-0 overflow-hidden`}>
        <Link href={fileHref('corrections')} aria-current={all ? 'page' : undefined}
          className={`flex w-full justify-between gap-2 border-b border-line px-[14px] py-[10px] text-12 font-bold text-ink hover:text-ink hover:no-underline ${all ? 'bg-highlight' : ''}`}>
          <span>{t('allCorrections')}</span><span className="font-normal text-faint">{FIXES.length}</span>
        </Link>
        {STARTER_GROUPS.map((g) => (
          <div key={g}>
            <div className="px-[14px] pb-[5px] pt-[9px] text-10.5 font-bold uppercase tracking-label text-muted">{t(`groups.${g}`)}</div>
            {STARTER.filter((x) => x.group === g).map((x) => {
              const on = !all && x.id === f.id
              return (
                <Link key={x.id} href={fileHref(x.id)} aria-current={on ? 'page' : undefined}
                  className={`flex w-full justify-between gap-2 px-[14px] py-2 text-left text-12 text-ink hover:text-ink hover:no-underline ${on ? 'bg-highlight' : ''}`}>
                  <span title={x.path} className={`${d.mono} min-w-0 overflow-hidden text-ellipsis whitespace-nowrap ${x.status === 'removed' ? 'line-through' : ''}`}>{x.path}</span>
                  <span className={`whitespace-nowrap ${STATUS_TONE[x.status]}`}>{t(`status.${x.status}`)}</span>
                </Link>
              )
            })}
          </div>
        ))}
      </nav>
      {all ? <Corrections /> : <FileCard f={f} />}
    </div>
  )
}

function FileCard({ f }: { f: StarterFile }) {
  const t = useTranslations('devDelivery.repo')
  const download = () => {
    const url = URL.createObjectURL(new Blob([f.body], { type: 'text/plain;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = f.path.split('/').pop() ?? 'file'
    a.click()
    URL.revokeObjectURL(url)
  }
  return (
    <div className={`${d.cardInk} flex min-w-0 flex-col gap-[10px] px-[18px] py-4`}>
      <div className="flex items-baseline justify-between gap-[10px]">
        <b className={`${d.mono} text-13 [overflow-wrap:anywhere]`}>{f.path}</b>
        <span className={`whitespace-nowrap text-11.5 ${STATUS_TONE[f.status]}`}>{t(`status.${f.status}`)}</span>
      </div>
      <span className="text-12.5 text-ink-2">{t(`what.${f.id}`)}</span>
      {f.status === 'removed'
        ? <div className="rounded-12 bg-peach px-[14px] py-3 text-12.5 text-rust-ink">{t('removed')}</div>
        : <pre className={`${d.pre} max-h-[460px] overflow-auto`}>{f.body}</pre>}
      {f.fixes.length ? (
        <div className="flex flex-col gap-1">
          <span className={d.label}>{t('correctedHere')}</span>
          <ul className="m-0 flex flex-col gap-1 pl-5 text-12.5">
            {f.fixes.map((k) => <li key={k}>{t(`fix.${k}`)}</li>)}
          </ul>
        </div>
      ) : null}
      <div className="flex flex-wrap items-center gap-2">
        {f.status !== 'removed' ? (
          <>
            <CopyButton text={f.body} />
            <button type="button" onClick={download} className={d.small}>{t('download')}</button>
          </>
        ) : null}
        <span className="text-11.5 text-faint">{t('footer')}</span>
      </div>
    </div>
  )
}

function Corrections() {
  const t = useTranslations('devDelivery.repo')
  return (
    <div className={`${d.cardInk} flex min-w-0 flex-col gap-[10px] px-[18px] py-4`}>
      <b className="text-15">{t('allCorrections')}</b>
      <span className="text-12.5 text-ink-2">{t('allIntro')}</span>
      <ol className="m-0 flex flex-col gap-2 pl-5 text-12.5">
        {FIXES.map((k) => {
          const files = STARTER.filter((x) => x.fixes.includes(k))
          return (
            <li key={k}>
              <span>{t(`fix.${k}`)}</span>
              <span className="mt-[2px] flex flex-wrap gap-x-2 text-11.5">
                {files.map((x) => <Link key={x.id} href={fileHref(x.id)} className={`${d.mono}`}>{x.path}</Link>)}
              </span>
            </li>
          )
        })}
      </ol>
      <span className="text-11.5 text-faint">{t('footer')}</span>
    </div>
  )
}
