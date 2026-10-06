'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { AccessModel, Staff } from '@/lib/data/settings'
import { copyAccess, replaceStaff, saveStaff, saveTeam } from '../actions'
import { k, useRun } from './kit'

type Row = Staff & { seen: string | null }
type Open = { id: string; kind: 'copy' | 'replace' } | null
const COLS = '[grid-template-columns:minmax(0,1.4fr)_130px_130px_120px_90px_220px]'

/** Users and teams (Settings.dc.html, v.users): the staff list with invite, copy access, replace and deactivate; the team cards. */
export function Users({ me, staff, access, canEdit }: { me: string; staff: Row[]; access: AccessModel; canEdit: boolean }) {
  const t = useTranslations('settings.users')
  const ts = useTranslations('settings')
  const { run, pending } = useRun()
  const [open, setOpen] = useState<Open>(null)
  const [inviting, setInviting] = useState(false)
  const toggle = (id: string, kind: 'copy' | 'replace') => setOpen(open?.id === id && open.kind === kind ? null : { id, kind })

  return (
    <div className="flex flex-col gap-3">
      <div className={`${k.card} overflow-x-auto`}>
        <div className="flex min-w-[880px] items-center justify-between border-b border-line px-[18px] py-3">
          <b className="text-14">{t('title')}</b>
          {canEdit ? (
            <button type="button" aria-expanded={inviting} onClick={() => setInviting(!inviting)} className="h-[30px] cursor-pointer rounded-9 border border-ink bg-primary px-3 text-12 font-bold text-ink">
              {t('invite')}
            </button>
          ) : null}
        </div>
        {!canEdit ? <div className="min-w-[880px] border-b border-line px-[18px] py-[9px] text-12 text-muted">{ts('readOnly', { right: ts('rights.security') })}</div> : null}
        {inviting ? <Invite access={access} onDone={() => setInviting(false)} /> : null}
        {staff.map((u) => {
          const self = u.id === me
          return (
            <div key={u.id}>
              <div className={`grid min-w-[880px] items-center gap-[10px] border-b border-line px-[18px] py-[9px] text-12.5 ${COLS} ${u.active ? '' : 'opacity-50'}`}>
                <span className="flex min-w-0 flex-col">
                  <b className="truncate">{u.name}</b>
                  <span className="truncate text-11.5 text-muted">{u.email ?? '—'}</span>
                </span>
                <span>{u.title ?? '—'}</span>
                <span className="text-muted">{u.permission_set}</span>
                <span className="text-muted">{u.group}</span>
                <span className="text-muted">{u.seen === 'now' ? t('now') : u.seen ?? t('never')}</span>
                <span className="flex justify-end gap-[5px]">
                  <button type="button" disabled={!canEdit || pending} aria-expanded={open?.id === u.id && open.kind === 'copy'} onClick={() => toggle(u.id, 'copy')} className={k.small}>
                    {t('copy')}
                  </button>
                  <button type="button" disabled={!canEdit || pending || self || !u.active} title={self ? ts('users.self') : undefined} aria-expanded={open?.id === u.id && open.kind === 'replace'} onClick={() => toggle(u.id, 'replace')} className={k.small}>
                    {t('replace')}
                  </button>
                  <button
                    type="button"
                    disabled={!canEdit || pending || self}
                    title={self ? ts('users.self') : undefined}
                    onClick={() => run(() => saveStaff({ id: u.id, values: { active: !u.active } }), () => t(u.active ? 'deactivated' : 'reactivated', { name: u.name }))}
                    className={k.smallDanger}
                  >
                    {u.active ? t('deactivate') : t('reactivate')}
                  </button>
                </span>
              </div>
              {open?.id === u.id ? (
                <Picker
                  title={open.kind === 'copy' ? t('copyTitle', { name: u.name }) : t('replaceTitle', { name: u.name })}
                  people={staff.filter((x) => x.id !== u.id && (open.kind === 'copy' ? x.id !== me : x.active))}
                  submit={open.kind === 'copy' ? t('copy') : t('replace')}
                  onCancel={() => setOpen(null)}
                  onPick={(id) => {
                    const other = staff.find((x) => x.id === id)?.name ?? ''
                    if (open.kind === 'copy') run(() => copyAccess({ from: u.id, to: id }), () => (setOpen(null), t('copied', { name: u.name })))
                    else run(() => replaceStaff({ old: u.id, next: id }), (r) => (setOpen(null), t('replaced', { name: u.name, count: r.reassigned, next: other })))
                  }}
                />
              ) : null}
            </div>
          )
        })}
      </div>
      <Teams teams={access.teams} staff={staff} canEdit={canEdit} />
    </div>
  )
}

function Picker({ title, people, submit, onPick, onCancel }: { title: string; people: Row[]; submit: string; onPick: (id: string) => void; onCancel: () => void }) {
  const t = useTranslations('settings.users')
  const [id, setId] = useState('')
  return (
    <form
      className="flex min-w-[880px] flex-wrap items-center gap-2 border-b border-line bg-canvas px-[18px] py-[10px] text-12.5"
      onSubmit={(e) => {
        e.preventDefault()
        if (id) onPick(id)
      }}
    >
      <label className="flex flex-wrap items-center gap-2">
        {title}
        <select value={id} onChange={(e) => setId(e.target.value)} className="h-[30px] rounded-8 border border-line bg-surface text-12 text-ink">
          <option value="">{t('pick')}</option>
          {people.map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
      </label>
      <button type="submit" disabled={!id} className={k.small}>{submit}</button>
      <button type="button" onClick={onCancel} className="cursor-pointer border-none bg-transparent px-2 text-12 text-muted">{t('cancel')}</button>
    </form>
  )
}

/** Invite = the staff row (staff_save); the person signs in with this e-mail and sets up their authenticator. */
function Invite({ access, onDone }: { access: AccessModel; onDone: () => void }) {
  const t = useTranslations('settings.users')
  const { run, pending } = useRun()
  const analyst = access.permission_sets.find((p) => p.key === 'analyst')?.id ?? access.permission_sets[0]?.id ?? ''
  const root = access.groups.find((g) => g.parent_id === null)?.id ?? ''
  const [v, setV] = useState({ name: '', email: '', title: '', permission_set_id: analyst, group_id: root, team_id: '' })
  const up = (p: Partial<typeof v>) => setV((x) => ({ ...x, ...p }))
  const ok = v.name.trim() && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.email.trim())
  const field = 'flex flex-col gap-1 text-11.5 font-semibold text-muted'
  const input = 'h-8 rounded-9 border border-line bg-surface px-[9px] text-12.5 font-normal text-ink'
  return (
    <form
      className="flex min-w-[880px] flex-col gap-[10px] border-b border-line bg-canvas px-[18px] py-3"
      onSubmit={(e) => {
        e.preventDefault()
        if (!ok) return
        const name = v.name.trim()
        run(
          () => saveStaff({ id: null, values: { name, email: v.email.trim(), title: v.title.trim() || undefined, permission_set_id: v.permission_set_id, group_id: v.group_id, team_id: v.team_id || null } }),
          () => (onDone(), t('invited', { name })),
        )
      }}
    >
      <b className="text-13">{t('inviteTitle')}</b>
      <div className="grid gap-[10px] [grid-template-columns:repeat(6,minmax(0,1fr))]">
        <label className={field}>{t('name')}<input required value={v.name} maxLength={120} onChange={(e) => up({ name: e.target.value })} className={input} /></label>
        <label className={field}>{t('email')}<input required type="email" value={v.email} maxLength={200} onChange={(e) => up({ email: e.target.value })} className={input} /></label>
        <label className={field}>{t('role')}<input value={v.title} maxLength={60} onChange={(e) => up({ title: e.target.value })} className={input} /></label>
        <label className={field}>
          {t('permissionSet')}
          <select value={v.permission_set_id} onChange={(e) => up({ permission_set_id: e.target.value })} className={input}>
            {access.permission_sets.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('group')}
          <select value={v.group_id} onChange={(e) => up({ group_id: e.target.value })} className={input}>
            {access.groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
        </label>
        <label className={field}>
          {t('team')}
          <select value={v.team_id} onChange={(e) => up({ team_id: e.target.value })} className={input}>
            <option value="">{t('noTeam')}</option>
            {access.teams.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
        </label>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <button type="submit" disabled={!ok || pending} className={k.primary}>{t('inviteSubmit')}</button>
        <button type="button" onClick={onDone} className={k.ghost}>{t('cancel')}</button>
        <span className="text-11.5 text-muted">{t('inviteNote')}</span>
      </div>
    </form>
  )
}

function Teams({ teams, staff, canEdit }: { teams: AccessModel['teams']; staff: Row[]; canEdit: boolean }) {
  const t = useTranslations('settings.users')
  const [edit, setEdit] = useState<string | 'new' | null>(null)
  return (
    <div className="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
      {teams.map((x) =>
        edit === x.id ? (
          <TeamForm key={x.id} team={x} staff={staff} onDone={() => setEdit(null)} />
        ) : (
          <div key={x.id} className="flex flex-col gap-[6px] rounded-18 border border-line bg-surface px-4 py-[14px]">
            <span className="flex items-start justify-between gap-2">
              <b className="text-13.5">{x.name}</b>
              {canEdit ? (
                <button type="button" onClick={() => setEdit(x.id)} className="cursor-pointer border-none bg-transparent p-0 text-11.5 font-semibold text-link">
                  {t('teamEdit')}
                </button>
              ) : null}
            </span>
            <span className="text-12 text-muted">{t('teamManager', { name: x.manager ?? '—' })}</span>
            <span className="text-12">{x.members.filter((m) => m.id !== x.manager_id).map((m) => m.name).join(' · ') || '—'}</span>
            <span className="text-11 text-faint">{t('teamFoot')}</span>
          </div>
        ),
      )}
      {edit === 'new' ? <TeamForm team={null} staff={staff} onDone={() => setEdit(null)} /> : null}
      {canEdit && edit !== 'new' ? (
        <button type="button" onClick={() => setEdit('new')} className="min-h-[120px] cursor-pointer rounded-18 border border-dashed border-line-strong bg-transparent text-12 font-semibold text-ink">
          {t('teamAdd')}
        </button>
      ) : null}
    </div>
  )
}

function TeamForm({ team, staff, onDone }: { team: AccessModel['teams'][number] | null; staff: Row[]; onDone: () => void }) {
  const t = useTranslations('settings.users')
  const { run, pending } = useRun()
  const [name, setName] = useState(team?.name ?? '')
  const [manager, setManager] = useState(team?.manager_id ?? '')
  const [members, setMembers] = useState<string[]>(team?.members.map((m) => m.id) ?? [])
  const active = staff.filter((s) => s.active)
  return (
    <form
      className="flex flex-col gap-[6px] rounded-18 border border-ink bg-surface px-4 py-[14px] text-12"
      onSubmit={(e) => {
        e.preventDefault()
        const n = name.trim()
        if (!n) return
        const ids = manager && !members.includes(manager) ? [...members, manager] : members
        run(() => saveTeam({ id: team?.id ?? null, name: n, manager: manager || null, members: ids }), () => (onDone(), t('teamSaved', { name: n })))
      }}
    >
      <label className={k.label}>
        {t('teamName')}
        <input value={name} maxLength={80} onChange={(e) => setName(e.target.value)} className={`${k.input} font-normal`} />
      </label>
      <label className={k.label}>
        {t('manager')}
        <select value={manager} onChange={(e) => setManager(e.target.value)} className="h-8 rounded-8 border border-line bg-canvas text-12 font-normal text-ink">
          <option value="">{t('noManager')}</option>
          {active.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
      </label>
      <fieldset className="m-0 flex flex-col gap-1 border-0 p-0">
        <legend className="mb-1 p-0 text-11.5 font-semibold text-muted">{t('members')}</legend>
        <div className="flex max-h-[140px] flex-col gap-1 overflow-y-auto">
          {active.map((s) => (
            <label key={s.id} className="flex items-center gap-2">
              <input type="checkbox" checked={members.includes(s.id)} onChange={(e) => setMembers(e.target.checked ? [...members, s.id] : members.filter((m) => m !== s.id))} />
              {s.name}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="flex gap-2 pt-1">
        <button type="submit" disabled={pending || !name.trim()} className={k.primary}>{t('teamSave')}</button>
        <button type="button" onClick={onDone} className={k.ghost}>{t('cancel')}</button>
      </div>
    </form>
  )
}
