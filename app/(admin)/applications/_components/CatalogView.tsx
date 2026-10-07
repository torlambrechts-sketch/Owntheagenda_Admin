'use client'

import { useEffect, useRef, useState } from 'react'
import { useTranslations } from 'next-intl'
import type { Catalog } from '@/lib/data/platform'
import { CATALOG_COLLECTIONS } from '@/lib/data/platform-shared'
import {
  catalogSearch, integrationInstall, integrationRemove, integrationRemovePreview, integrationUserRevoke, integrationUsers,
  type IntegrationUser, type RemovePreview,
} from '../actions'
import { Dialog, k, useAct } from './kit'

type Item = Catalog['items'][number]

export function CatalogView({ initial, canConfigure }: { initial: Catalog; canConfigure: boolean }) {
  const t = useTranslations('platform.catalog')
  const { run, pending, flash } = useAct()
  const [q, setQ] = useState('')
  const [cat, setCat] = useState(initial)
  const [remove, setRemove] = useState<Item | null>(null)
  const [users, setUsers] = useState<Item | null>(null)
  const seq = useRef(0)
  useEffect(() => { setCat(initial) }, [initial])
  useEffect(() => {
    if (!q.trim()) { setCat(initial); return }
    const n = ++seq.current
    const h = setTimeout(() => { void catalogSearch(q).then((r) => { if (n === seq.current && r.ok) setCat(r.catalog) }) }, 250)
    return () => clearTimeout(h)
  }, [q, initial])

  const name = (key: string) => (t.has(`items.${key}.name`) ? t(`items.${key}.name`) : key)
  const stateOf = (i: Item): [string, string] => {
    if (!i.installed) return [t('available'), 'text-muted']
    if (i.connection === 'company' && i.company_connected === false) return [t('installedNotConnected'), 'text-warn-ink']
    return [t('installed'), 'text-link']
  }
  const install = (i: Item) => run(() => integrationInstall(i.key), (r) => {
    if (r.ok) flash(r.connect_required ? t('installedConnect', { name: name(i.key) }) : t('installedToast', { name: name(i.key) }))
  })

  return (
    <div className="flex flex-col gap-[14px]">
      <div className="flex items-center gap-[10px] rounded-16 border border-line bg-surface px-3 py-[10px]">
        {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's assistant portrait */}
        <img src="/brand/assistant.png" alt="" width={26} height={26} className="flex-none rounded-8" />
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t('placeholder')}
          aria-label={t('placeholder')}
          className="h-[34px] min-w-0 flex-1 border-none bg-transparent text-13 outline-none"
        />
        <span className="hidden text-12 text-muted sm:inline">{q.trim() ? t('hintMatches') : t('hintAssistant')}</span>
      </div>
      {!canConfigure ? <div className={`${k.card} text-12 text-muted`}><div className="px-[18px] py-[9px]">{t('readOnly')}</div></div> : null}
      {CATALOG_COLLECTIONS.map((c) => {
        const items = cat.items.filter((i) => i.collection === c)
        if (!items.length) return null
        return (
          <div key={c} className="flex flex-col gap-[10px]">
            <b className="text-14">{t(`collections.${c}`)}</b>
            <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),1fr))]">
              {items.map((i) => {
                const [st, sc] = stateOf(i)
                return (
                  <div key={i.key} className={`flex flex-col gap-[6px] rounded-18 border bg-surface px-4 py-[14px] ${q.trim() && i.match ? 'border-ink' : 'border-line'}`}>
                    <div className="flex justify-between gap-2">
                      <b className="text-13.5">{name(i.key)}</b>
                      <span className={`text-11 font-bold ${sc}`}>{st}</span>
                    </div>
                    <span className="text-12 leading-[1.45] text-muted">{t.has(`items.${i.key}.description`) ? t(`items.${i.key}.description`) : ''}</span>
                    <span className="text-11 text-faint">{t('access', { list: i.access.map((a) => (t.has(`accessLabels.${a}`) ? t(`accessLabels.${a}`) : a)).join(', ') })}</span>
                    {i.installed && i.users > 0 ? <span className="text-11 text-faint">{t('usersConnected', { count: i.users })}</span> : null}
                    <div className="flex flex-wrap gap-[6px]">
                      {i.installed ? (
                        <button type="button" disabled={!canConfigure || pending} onClick={() => setRemove(i)} className={k.btn}>{t('remove')}</button>
                      ) : (
                        <button type="button" disabled={!canConfigure || pending} onClick={() => install(i)} className={k.btnPrimary}>{t('install')}</button>
                      )}
                      {i.installed ? (
                        <button type="button" disabled={!canConfigure} onClick={() => setUsers(i)} className={k.btnSoft}>{t('settingsUsers')}</button>
                      ) : null}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}
      {cat.items.length === 0 ? <div className={`${k.card} ${k.empty}`}>{t('noMatch')}</div> : null}
      {remove ? <RemoveDialog item={remove} name={name(remove.key)} onClose={() => setRemove(null)} /> : null}
      {users ? <UsersDialog item={users} name={name(users.key)} onClose={() => setUsers(null)} /> : null}
    </div>
  )
}

/** Removing an integration revokes its access (INT-11): the preview names each effect, and the key is typed to confirm (D-30). */
function RemoveDialog({ item, name, onClose }: { item: Item; name: string; onClose: () => void }) {
  const t = useTranslations('platform.catalog.removeDlg')
  const { run, pending, flash } = useAct()
  const [preview, setPreview] = useState<RemovePreview | null>(null)
  const [typed, setTyped] = useState('')
  useEffect(() => { run(() => integrationRemovePreview(item.key), (r) => { if (r.ok) setPreview(r.preview) }, { refresh: false }) }, [item.key, run])
  const effects = preview
    ? ([
        ['users', preview.users], ['mailboxes', preview.mailboxes], ['calendars', preview.calendars], ['workflows', preview.workflows], ['grants', preview.grants],
      ] as const).filter(([, n]) => n > 0)
    : []
  return (
    <Dialog title={t('title', { name })} onClose={onClose} width={520}>
      {!preview ? <span className="text-12.5 text-muted">{t('loading')}</span> : (
        <>
          <span className="text-12.5 leading-[1.55]">{t('body')}</span>
          <ul className="m-0 flex flex-col gap-1 pl-[18px] text-12.5">
            {preview.company_connection ? <li>{t('companyConnection')}</li> : null}
            {effects.map(([key, n]) => <li key={key}>{t(`effects.${key}`, { count: n })}</li>)}
            {!preview.company_connection && effects.length === 0 ? <li>{t('nothing')}</li> : null}
          </ul>
          <label className="flex flex-col gap-1 text-11.5 font-semibold text-muted">
            {t('confirm', { key: item.key })}
            <input value={typed} onChange={(e) => setTyped(e.target.value)} className={`${k.input} ${k.mono}`} />
          </label>
        </>
      )}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className={k.dlgCancel}>{t('cancel')}</button>
        <button
          type="button"
          disabled={pending || !preview || typed !== item.key}
          onClick={() => run(() => integrationRemove({ key: item.key, confirm: typed }), () => { flash(t('done', { name })); onClose() })}
          className={k.dlgDanger}
        >
          {t('submit')}
        </button>
      </div>
    </Dialog>
  )
}

/** «Settings · users»: who is connected to the integration, with a per-person revoke. */
function UsersDialog({ item, name, onClose }: { item: Item; name: string; onClose: () => void }) {
  const t = useTranslations('platform.catalog.usersDlg')
  const { run, pending, flash } = useAct()
  const [list, setList] = useState<IntegrationUser[] | null>(null)
  const load = () => run(() => integrationUsers(item.key), (r) => { if (r.ok) setList(r.users) }, { refresh: false })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(load, [item.key])
  return (
    <Dialog title={t('title', { name })} onClose={onClose} width={520}>
      {item.connection === 'company' ? <span className="text-12.5 text-muted">{item.company_connected ? t('company') : t('companyNotConnected')}</span> : null}
      {list === null ? <span className="text-12.5 text-muted">{t('loading')}</span> : list.length === 0 ? <span className="text-12.5 text-muted">{t('none')}</span> : (
        <div className="flex flex-col">
          {list.map((u) => (
            <div key={`${u.staff_id}-${u.via}`} className="flex items-center justify-between gap-[10px] border-b border-line py-2 text-12.5">
              <span><b>{u.name ?? '—'}</b> · <span className="text-muted">{t(`via.${u.via}`)}</span></span>
              {u.via !== 'company' ? (
                <button type="button" disabled={pending} onClick={() => run(() => integrationUserRevoke({ key: item.key, staff: u.staff_id }), () => { flash(t('revoked', { name: u.name ?? '—' })); load() })} className={`${k.btnRevoke} px-[10px]`}>
                  {t('revoke')}
                </button>
              ) : null}
            </div>
          ))}
        </div>
      )}
      <div className="flex justify-end"><button type="button" onClick={onClose} className={k.dlgCancel}>{t('close')}</button></div>
    </Dialog>
  )
}
