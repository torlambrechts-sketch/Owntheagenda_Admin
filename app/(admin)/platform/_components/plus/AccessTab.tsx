'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import type { AccessMatrix, AccountOption, Approval, Approvals, StaffAction } from '@/lib/data/platform-plus'
import { Dialog, useAgo, useNowMs } from '../../../applications/_components/kit'
import { decideApproval, requestApproval, setPolicy } from '../../plus-actions'
import { CELL_CLASS, SYMBOL, actionKey, isOpen, nextMode, type Mode } from './logic'
import { Head, p, usePlusAct } from './kit'

const ROLE_KEYS = ['admin', 'sales', 'support', 'marketing', 'analyst']
const COLS = '[grid-template-columns:minmax(0,1.7fr)_repeat(5,minmax(70px,1fr))]'

/**
 * Roles and approvals (PlatformPlus.dc.html, v.access): the five roles (X-V3-4) against the sensitive actions, and the queue of
 * requests a second person approves. A cell is the role's policy where Sentral enforces one (product-command asks
 * command_authorize; the matrix itself), the role's right where a right decides (changed in Settings), and «–» where nothing
 * can do the action yet. Approval («A») is offered only where the queue can execute the action; it is off until switched on
 * (D-30). Every change needs a fresh second factor and is audited.
 */
export function AccessTab({ matrix, approvals, accounts, productName }: {
  matrix: AccessMatrix
  approvals: Approvals
  accounts: AccountOption[]
  productName: string
}) {
  return (
    <div className="flex flex-col gap-[14px]">
      <Matrix matrix={matrix} productName={productName} />
      <Queue approvals={approvals} accounts={accounts} />
    </div>
  )
}

function useRoleName() {
  const t = useTranslations('platformPlus.access.roles')
  return (r: { key: string | null; name: string | null }) => (r.key && ROLE_KEYS.includes(r.key) ? t(`role.${r.key}`) : r.name ?? '—')
}

function Matrix({ matrix, productName }: { matrix: AccessMatrix; productName: string }) {
  const t = useTranslations('platformPlus.access.roles')
  const roleName = useRoleName()
  const { run, pending, flash, mfa } = usePlusAct()
  const [ask, setAsk] = useState<null | { set: string; action: string; mode: Mode; role: string; label: string }>(null)
  const [reason, setReason] = useState('')
  const canManage = matrix.manage !== 'deny'
  const label = (a: StaffAction) => t(`actions.${actionKey(a.key)}`)

  const click = (roleId: string, role: string, a: StaffAction, cur: Mode) => {
    const mode = nextMode(cur, a.approvable)
    if (matrix.manage === 'approve') {
      setReason('')
      setAsk({ set: roleId, action: a.key, mode, role, label: label(a) })
      return
    }
    run(() => setPolicy({ set: roleId, action: a.key, mode }), () => flash(t('changed', { action: label(a), role, mode: t(`mode.${mode}`) })))
  }
  const why = (a: StaffAction) =>
    a.enforced === 'none' ? t('why.none', { product: productName })
    : a.enforced === 'right' ? t('why.right', { right: a.basis_right && t.has(`rights.${a.basis_right.replace(':', '_')}`) ? t(`rights.${a.basis_right.replace(':', '_')}`) : a.basis_right ?? '' })
    : !canManage ? t('why.readOnly') : null

  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('legend')} />
      {mfa && !ask ? <div className="border-b border-line px-[18px] py-3">{mfa}</div> : null}
      <div className="overflow-x-auto">
        <div className="min-w-[760px]">
          <div className={`grid gap-[6px] border-b border-line px-[18px] py-[9px] text-10.5 font-bold uppercase tracking-[.08em] text-muted ${COLS}`}>
            <span>{t('action')}</span>
            {matrix.roles.map((r) => <span key={r.id} className="text-center">{roleName(r)}</span>)}
          </div>
          {matrix.actions.map((a) => {
            const editable = canManage && (a.enforced === 'command' || a.enforced === 'database')
            const title = why(a)
            return (
              <div key={a.key} className={`grid items-center gap-[6px] border-b border-tile px-[18px] py-[7px] text-12.5 ${COLS}`}>
                <span>
                  {label(a)}
                  {a.enforced === 'none' ? <span className="text-11 text-faint">{` · ${t('notYet')}`}</span> : null}
                </span>
                {matrix.roles.map((r) => {
                  const cur = matrix.cells[r.id]?.[a.key] ?? 'none'
                  const mode: Mode = cur === 'none' ? 'deny' : cur
                  return (
                    <button
                      key={r.id}
                      type="button"
                      disabled={!editable || pending}
                      title={title ?? undefined}
                      aria-label={t('cellLabel', { action: label(a), role: roleName(r), mode: cur === 'none' ? t('notYet') : t(`mode.${cur}`) })}
                      onClick={() => click(r.id, roleName(r), a, mode)}
                      className={`h-[26px] cursor-pointer rounded-7 border text-12 font-bold disabled:cursor-default ${CELL_CLASS[cur]}`}
                    >
                      {SYMBOL[cur]}
                    </button>
                  )
                })}
              </div>
            )
          })}
        </div>
      </div>
      <div className={p.foot}>{canManage ? t('footer') : t('footerRead')}</div>
      {ask ? (
        <Dialog title={t('reasonTitle')} onClose={() => setAsk(null)}>
          <span className="text-13 text-muted">{t('reasonBody', { action: ask.label, role: ask.role, mode: t(`mode.${ask.mode}`) })}</span>
          <label className={p.label}>
            {t('reasonLabel')}
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className={`${p.input} h-auto min-h-[70px] py-[9px]`} />
          </label>
          {mfa}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setAsk(null)} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
            <button
              type="button"
              disabled={pending || reason.trim().length < 3}
              onClick={() => run(() => setPolicy({ set: ask.set, action: ask.action, mode: ask.mode, reason: reason.trim() }), () => {
                setAsk(null)
                flash(t('requested', { action: ask.label, role: ask.role }))
              })}
              className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60"
            >
              {t('send')}
            </button>
          </div>
        </Dialog>
      ) : null}
    </div>
  )
}

function Queue({ approvals, accounts }: { approvals: Approvals; accounts: AccountOption[] }) {
  const t = useTranslations('platformPlus.access.queue')
  const tr = useTranslations('platformPlus.access.roles')
  const roleName = useRoleName()
  const ago = useAgo()
  const nowMs = useNowMs()
  const { run, pending, flash, mfa } = usePlusAct()
  const [confirm, setConfirm] = useState<Approval | null>(null)
  const [typed, setTyped] = useState('')
  const [asking, setAsking] = useState(false)

  const title = (a: Approval) => {
    const org = a.organization?.name ?? '—'
    if (a.action === 'trial.extend') return t('titleTrial', { org, days: a.days ?? 0 })
    if (a.action === 'account.delete') return t('titleDelete', { org })
    if (a.policy) {
      return t('titlePolicy', {
        action: tr.has(`actions.${actionKey(a.policy.action)}`) ? tr(`actions.${actionKey(a.policy.action)}`) : a.policy.action,
        role: roleName({ key: a.policy.set_key, name: a.policy.set_name }),
        from: tr(`mode.${a.policy.from}`),
        to: tr(`mode.${a.policy.mode}`),
      })
    }
    return a.action
  }
  const decide = (a: Approval, yes: boolean, confirmText?: string) => run(
    () => decideApproval({ id: a.id, yes, confirm: confirmText }),
    (r) => {
      setConfirm(null)
      flash(!yes ? t('rejectedToast') : r.state === 'executed' ? t('approvedToast') : t('failedToast', { code: r.code ?? r.state }))
    },
  )
  const done = (a: Approval): { text: string; tone: string } => {
    if (a.state === 'executed') return { text: t('state.executed', { name: a.decided_by ?? '—' }), tone: 'text-link' }
    if (a.state === 'approved' || a.state === 'executing') return { text: t('state.approved', { name: a.decided_by ?? '—' }), tone: 'text-link' }
    if (a.state === 'rejected') return { text: t('state.rejected'), tone: 'text-danger' }
    if (a.state === 'failed') return { text: t('state.failed', { code: a.result_code ?? 'failed' }), tone: 'text-danger' }
    return { text: t('state.expired'), tone: 'text-muted' }
  }

  return (
    <div className={p.card}>
      <Head title={t('title')} sub={t('sub', { count: approvals.open })}>
        {approvals.requestable.length ? (
          <button type="button" onClick={() => setAsking(true)} className={`${p.btnRow} bg-primary px-[10px]`}>{t('request')}</button>
        ) : null}
      </Head>
      {mfa && !confirm ? <div className="border-b border-line px-[18px] py-3">{mfa}</div> : null}
      {approvals.rows.length === 0 ? <div className={p.empty}>{t('empty')}</div> : null}
      {approvals.rows.map((a) => {
        const open = isOpen(a, nowMs)
        const d = open ? null : done(a)
        return (
          <div key={a.id} className="flex flex-wrap items-center gap-[10px] border-b border-line px-[18px] py-[11px]">
            <span className="flex flex-[1_1_300px] flex-col gap-[2px]">
              <b className="text-13">{title(a)}</b>
              <span className="text-11.5 text-muted">{t('by', { name: a.requested_by ?? '—', when: ago(a.requested_at), reason: a.reason })}</span>
            </span>
            <b className="whitespace-nowrap text-13">{a.days ? t('amountDays', { days: a.days }) : '—'}</b>
            {open && a.can_decide ? (
              <span className="flex gap-[6px]">
                <button type="button" disabled={pending} onClick={() => decide(a, false)} className={p.btnReject}>{t('reject')}</button>
                <button
                  type="button"
                  disabled={pending}
                  onClick={() => { if (a.confirm) { setTyped(''); setConfirm(a) } else decide(a, true) }}
                  className={p.btnApprove}
                >
                  {t('approve')}
                </button>
              </span>
            ) : open ? (
              <b className="text-12 text-muted">{t('waiting')}</b>
            ) : d ? (
              <b className={`text-12 ${d.tone}`}>{d.text}</b>
            ) : null}
          </div>
        )
      })}
      {confirm ? (
        <Dialog title={t('confirmTitle', { org: confirm.organization?.name ?? '—' })} onClose={() => setConfirm(null)}>
          <span className="text-13 text-muted">{t('confirmBody')}</span>
          <label className={p.label}>
            {t('confirmLabel')}
            <input value={typed} onChange={(e) => setTyped(e.target.value)} inputMode="numeric" maxLength={20} className={p.input} />
          </label>
          {mfa}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setConfirm(null)} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('dialog.cancel')}</button>
            <button
              type="button"
              disabled={pending || typed.replace(/\s/g, '').length < 9}
              onClick={() => decide(confirm, true, typed)}
              className="h-[38px] cursor-pointer rounded-11 border border-coral bg-transparent px-[15px] text-13 font-semibold text-rust disabled:cursor-default disabled:opacity-60"
            >
              {t('approve')}
            </button>
          </div>
        </Dialog>
      ) : null}
      {asking ? <RequestDialog requestable={approvals.requestable} accounts={accounts} onClose={() => setAsking(false)} /> : null}
    </div>
  )
}

/** Ask for an action you may take only with approval: the account, the days or the typed org.nr, and why. */
function RequestDialog({ requestable, accounts, onClose }: { requestable: string[]; accounts: AccountOption[]; onClose: () => void }) {
  const t = useTranslations('platformPlus.access.queue.dialog')
  const tq = useTranslations('platformPlus.access.queue')
  const tr = useTranslations('platformPlus.access.roles')
  const { run, pending, flash, mfa } = usePlusAct()
  const [action, setAction] = useState(requestable[0] ?? '')
  const [org, setOrg] = useState('')
  const [days, setDays] = useState('14')
  const [orgnr, setOrgnr] = useState('')
  const [reason, setReason] = useState('')
  const n = Number(days)
  const ready = !!org && reason.trim().length >= 3
    && (action === 'trial.extend' ? Number.isInteger(n) && n >= 1 && n <= 60 : orgnr.replace(/\s/g, '').length >= 9)
  const send = () => run(
    () => requestApproval(action === 'trial.extend'
      ? { action, organization: org, days: n, reason: reason.trim() }
      : { action, organization: org, confirm: orgnr, reason: reason.trim() }),
    (r) => { onClose(); flash(tq('requestedToast', { ref: String(r.ref) })) },
  )
  return (
    <Dialog title={t('title')} onClose={onClose}>
      <label className={p.label}>
        {t('action')}
        <select value={action} onChange={(e) => setAction(e.target.value)} className={p.input}>
          {requestable.map((k) => <option key={k} value={k}>{tr(`actions.${actionKey(k)}`)}</option>)}
        </select>
      </label>
      <label className={p.label}>
        {t('account')}
        <select value={org} onChange={(e) => setOrg(e.target.value)} className={p.input}>
          <option value="">{t('choose')}</option>
          {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
      </label>
      {action === 'trial.extend' ? (
        <label className={p.label}>
          {t('days')}
          <input type="number" min={1} max={60} value={days} onChange={(e) => setDays(e.target.value)} className={`${p.input} w-[120px]`} />
        </label>
      ) : (
        <label className={p.label}>
          {t('orgnr')}
          <input value={orgnr} onChange={(e) => setOrgnr(e.target.value)} inputMode="numeric" maxLength={20} className={p.input} />
        </label>
      )}
      <label className={p.label}>
        {t('reason')}
        <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className={`${p.input} h-auto min-h-[70px] py-[9px]`} />
      </label>
      {mfa}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
        <button type="button" disabled={pending || !ready} onClick={send} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">
          {t('send')}
        </button>
      </div>
    </Dialog>
  )
}
