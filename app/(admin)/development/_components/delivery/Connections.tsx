'use client'

import { useState } from 'react'
import { useFormatter, useTranslations } from 'next-intl'
import type { Connection, Deploys } from '@/lib/data/dev-delivery'
import { bindRepo, connectSource, disconnectSource, setProject } from '../../delivery-actions'
import { CI_EXAMPLE, CI_HEADERS } from './logic'
import { CopyButton, useRun } from './kit'
import { d } from './styles'

type Source = 'vercel' | 'ci'

/**
 * The two connections (0078 v3_intake / v3_disconnect: the owner, a fresh second factor): Vercel's deployment webhook and
 * the products' CI. Each card says what to paste where, and takes the signing secret into Vault through secret-intake; the
 * secret never comes back. Vercel's projects are mapped to the applications here (Development › Configure). One CI secret
 * signs every repository's posts (X-V3-1), so the owner binds each repository to its product (0080 dev_ci_repo_set); the
 * database refuses a post from a repository that is not bound, or that names another product.
 */
export function Connections({ url, now, vercel, ci, canManage, canConfigure, projects, products, repos }: {
  url: string | null; now: number; vercel: Connection; ci: Connection; canManage: boolean; canConfigure: boolean
  projects: { id: string; name: string; product: string | null }[]; products: { key: string; name: string }[]; repos: Deploys['ci_repos']
}) {
  const t = useTranslations('devDelivery.connect')
  const { run, pending, mfa } = useRun()
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <Card source="vercel" c={vercel} url={url} now={now} canManage={canManage}>
        <ol className="m-0 flex flex-col gap-1 pl-5 text-12.5">
          <li>{t('vercel.step1')}</li>
          <li>{t('vercel.step2')}</li>
          <li>{t('vercel.step3')}</li>
          <li>{t('vercel.step4')}</li>
        </ol>
        {projects.length ? (
          <div className="flex flex-col gap-[6px] border-t border-line pt-3">
            <b className="text-13">{t('vercel.projects')}</b>
            <span className="text-11.5 text-muted">{t('vercel.projectsNote')}</span>
            {projects.map((p) => (
              <div key={p.id} className="flex flex-wrap items-center justify-between gap-2 text-12.5">
                <span className={`${d.mono} text-12`}>{p.name}</span>
                {canConfigure ? (
                  <select aria-label={t('vercel.projectApp', { name: p.name })} value={p.product ?? ''} disabled={pending}
                    onChange={(e) => run(() => setProject({ id: p.id, product: e.target.value || null }), () => t('vercel.mappedToast'))}
                    className={`${d.select} h-8 w-[180px] text-12`}>
                    <option value="">{t('vercel.noApp')}</option>
                    {products.map((x) => <option key={x.key} value={x.key}>{x.name}</option>)}
                  </select>
                ) : <span className="text-muted">{products.find((x) => x.key === p.product)?.name ?? t('vercel.noApp')}</span>}
              </div>
            ))}
            {mfa}
          </div>
        ) : null}
      </Card>
      <Card source="ci" c={ci} url={url} now={now} canManage={canManage}>
        <ol className="m-0 flex flex-col gap-1 pl-5 text-12.5">
          <li>{t('ci.step1')} <code className={`${d.mono} rounded-5 bg-tile px-1 text-11.5`}>openssl rand -hex 32</code></li>
          <li>{t('ci.step2')}</li>
          <li>{t('ci.step3')}</li>
          <li>{t('ci.step4')}</li>
          <li>{t('ci.step5')}</li>
        </ol>
        <Repos repos={repos} products={products} now={now} canManage={canManage} />
        <details className="text-12.5">
          <summary className="cursor-pointer font-semibold">{t('ci.request')}</summary>
          <div className="mt-2 flex flex-col gap-2">
            <span className="text-11.5 text-muted">{t('ci.requestNote')}</span>
            <pre className={d.pre}>{`POST ${url ?? 'https://…/functions/v1/dev-events'}\n${CI_HEADERS}`}</pre>
            <pre className={d.pre}>{CI_EXAMPLE}</pre>
            <span className="text-11.5 text-muted">{t('ci.fields')}</span>
            <div><CopyButton text={CI_EXAMPLE} label={t('ci.copyExample')} /></div>
          </div>
        </details>
      </Card>
    </div>
  )
}

/** the repositories bound to a product: who bound each, its newest post; the owner binds and unbinds */
function Repos({ repos, products, now, canManage }: { repos: Deploys['ci_repos']; products: { key: string; name: string }[]; now: number; canManage: boolean }) {
  const t = useTranslations('devDelivery.connect.ci')
  const format = useFormatter()
  const { run, pending, mfa } = useRun()
  const [repo, setRepo] = useState('')
  const [product, setProduct] = useState(products[0]?.key ?? 'sentral')
  const name = (key: string) => products.find((p) => p.key === key)?.name ?? key
  const shapeOk = /^[A-Za-z0-9][A-Za-z0-9_-]{0,38}\/(?!\.\.?$)[A-Za-z0-9_.-]{1,100}$/.test(repo.trim())
  return (
    <div className="flex flex-col gap-[6px] border-t border-line pt-3">
      <b className="text-13">{t('repos')}</b>
      <span className="text-11.5 text-muted">{t('reposNote')}</span>
      {repos.length === 0 ? <span className="text-12.5 font-semibold text-warn-ink">{t('noRepos')}</span> : null}
      {repos.map((r) => (
        <div key={r.repository} className="flex flex-wrap items-center justify-between gap-2 text-12.5">
          <span className="flex min-w-0 flex-col">
            <span className={`${d.mono} text-12 [overflow-wrap:anywhere]`}>{r.repository}</span>
            <span className="text-11 text-muted">
              {[name(r.product), r.last_run_at ? t('lastPost', { ago: format.relativeTime(new Date(r.last_run_at), now) }) : t('noPost'),
                t('boundBy', { by: r.bound_by ?? '—' })].join(' · ')}
            </span>
          </span>
          {canManage ? (
            <button type="button" disabled={pending}
              onClick={() => { if (window.confirm(t('unbindConfirm', { repo: r.repository }))) run(() => bindRepo({ repository: r.repository, product: null }), () => t('unboundToast')) }}
              className={d.small}>{t('unbind')}</button>
          ) : null}
        </div>
      ))}
      {canManage ? (
        <div className="flex flex-wrap items-end gap-2">
          <label className={`${d.field} min-w-[180px] flex-[1_1_200px]`}>
            {t('repo')}
            <input value={repo} maxLength={140} spellCheck={false} autoComplete="off" onChange={(e) => setRepo(e.target.value)} placeholder={t('repoPlaceholder')}
              className={`${d.input} ${d.mono} text-12`} />
          </label>
          <label className={`${d.field} w-[160px]`}>
            {t('repoProduct')}
            <select value={product} onChange={(e) => setProduct(e.target.value)} className={`${d.select} text-12`}>
              {products.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}
            </select>
          </label>
          <button type="button" disabled={pending || !shapeOk} onClick={() => run(() => bindRepo({ repository: repo.trim(), product }), () => t('boundToast'), () => setRepo(''))}
            className={`${d.smallPrimary} mb-[1px]`}>{t('bind')}</button>
          {repo.trim() && !shapeOk ? <span className="basis-full text-11.5 text-muted">{t('repoShape')}</span> : null}
        </div>
      ) : <span className="text-11.5 text-muted">{t('reposOwner')}</span>}
      {mfa}
    </div>
  )
}

function Card({ source, c, url, now, canManage, children }: { source: Source; c: Connection; url: string | null; now: number; canManage: boolean; children: React.ReactNode }) {
  const t = useTranslations('devDelivery.connect')
  const format = useFormatter()
  const { run, pending, mfa } = useRun()
  const [secret, setSecret] = useState('')
  const state = c.key_stored ? (c.last_delivery_at ? 'connected' : 'waiting') : 'off'
  const pill = { connected: 'bg-ok-bg text-ok-ink', waiting: 'bg-amber-bg text-amber-ink', off: 'bg-tile text-muted' }[state]
  const min = source === 'vercel' ? 16 : 32
  const shapeOk = new RegExp(`^[A-Za-z0-9_-]{${min},256}$`).test(secret.trim())
  return (
    <div className={`${d.card} flex min-w-0 flex-col gap-3 px-[18px] py-4`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <b className="text-15">{t(`${source}.title`)}</b>
        <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${pill}`}>{t(`state.${state}`)}</span>
      </div>
      <span className="text-12.5 text-muted">{t(`${source}.body`)}</span>
      <div className="flex flex-wrap gap-x-4 gap-y-1 text-12 text-muted">
        <span>{c.last_delivery_at ? t('last', { ago: format.relativeTime(new Date(c.last_delivery_at), now) }) : t('noDelivery')}</span>
        <span>{t('count', { n: c.applied_30d, ignored: c.ignored_30d })}</span>
      </div>
      <div className="flex flex-col gap-[5px]">
        <span className="text-12 font-semibold text-muted">{t('url')}</span>
        <div className="flex gap-2">
          <input readOnly value={url ?? '—'} onFocus={(e) => e.currentTarget.select()} aria-label={t('url')} className={`${d.input} ${d.mono} min-w-0 flex-1 text-12`} />
          {url ? <CopyButton text={url} /> : null}
        </div>
      </div>
      {children}
      {canManage ? (
        <div className="flex flex-col gap-2 border-t border-line pt-3">
          <label className={d.field}>
            {t(`${source}.secret`)}
            <input type="password" autoComplete="off" spellCheck={false} value={secret} onChange={(e) => setSecret(e.target.value)}
              placeholder={c.key_stored ? t('replace') : t(`${source}.secretPlaceholder`)} className={`${d.input} ${d.mono} text-12`} />
          </label>
          <span className="text-11.5 text-muted">{t('secretNote')}</span>
          <div className="flex flex-wrap gap-2">
            <button type="button" disabled={pending || !shapeOk} title={secret && !shapeOk ? t(`${source}.shape`) : undefined}
              onClick={() => run(() => connectSource({ purpose: source, secret: secret.trim() }), () => t('savedToast'), () => setSecret(''))}
              className={d.smallPrimary}>{c.key_stored ? t('saveNew') : t('save')}</button>
            {c.key_stored ? (
              <button type="button" disabled={pending}
                onClick={() => { if (window.confirm(t(`${source}.disconnectConfirm`))) run(() => disconnectSource(source), () => t('disconnectedToast')) }}
                className={d.small}>{t('disconnect')}</button>
            ) : null}
          </div>
          {mfa}
        </div>
      ) : <span className="border-t border-line pt-3 text-12 text-muted">{t('ownerOnly')}</span>}
    </div>
  )
}
