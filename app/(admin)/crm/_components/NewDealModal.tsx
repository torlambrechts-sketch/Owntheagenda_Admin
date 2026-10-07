'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { OrgOption } from '@/lib/data/simple-crm'
import { createCrmDeal, fetchOrgOptions } from '../actions'
import { Modal, field } from './Modal'

/**
 * «New deal» (SimpleCRM.dc.html modal.isDeal): title, account, value in NOK and stage, in the board's pipeline
 * (deal_create). The accounts are the organizations the person may see; «—» leaves the deal without one.
 */
export function NewDealModal({ pipelineId, stages, onClose, onCreated }: {
  pipelineId: string
  stages: { id: string; name: string }[]
  onClose: () => void
  onCreated: () => void
}) {
  const t = useTranslations('simpleCrm.modal.deal')
  const tf = useTranslations('simpleCrm.flash')
  const te = useTranslations('common.errors')
  const tc = useTranslations('common')
  const flash = useToast()
  const [orgs, setOrgs] = useState<OrgOption[] | null>(null)
  const [title, setTitle] = useState('')
  const [org, setOrg] = useState('')
  const [value, setValue] = useState('')
  const [stage, setStage] = useState(stages[0]?.id ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    void fetchOrgOptions().then((r) => { if (r.ok) setOrgs(r.orgs); else setError(te(r.code)) })
  }, [te])

  const create = async () => {
    if (busy) return
    const digits = value.replace(/\D/g, '')
    setBusy(true)
    setError(null)
    const r = await createCrmDeal({
      title: title.trim() || t('fallback'),
      pipeline_id: pipelineId,
      stage_id: stage,
      organization_id: org || null,
      value: digits ? Number(digits) : null,
    })
    setBusy(false)
    if (!r.ok) { setError(te(r.code)); return }
    flash(tf('created'))
    onCreated()
  }

  return (
    <Modal title={t('title')} cta={t('cta')} busy={busy} error={error} onClose={onClose} onSubmit={() => void create()}>
      <div className="flex flex-col gap-[10px]">
        <label className={field.label}>
          {t('dealTitle')}
          <input value={title} maxLength={200} onChange={(e) => setTitle(e.target.value)} placeholder={t('titlePh')} className={field.input} />
        </label>
        <label className={field.label}>
          {t('account')}
          <select value={org} onChange={(e) => setOrg(e.target.value)} disabled={orgs === null} className={field.select}>
            <option value="">{tc('dash')}</option>
            {(orgs ?? []).map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
          </select>
        </label>
        <div className="grid grid-cols-2 gap-[10px]">
          <label className={field.label}>
            {t('value')}
            <input value={value} inputMode="numeric" maxLength={16} onChange={(e) => setValue(e.target.value)} className={field.input} />
          </label>
          <label className={field.label}>
            {t('stage')}
            <select value={stage} onChange={(e) => setStage(e.target.value)} className={field.select}>
              {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
        </div>
      </div>
    </Modal>
  )
}
