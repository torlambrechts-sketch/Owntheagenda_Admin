'use client'

import { useEffect, useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { CONTACT_TYPES } from '@/lib/data/contacts-shared'
import type { ContactsData, Field, Lead } from '@/lib/data/contacts'
import { deleteRecord, formOptions, saveRecord } from '../actions'
import { fieldInput, fieldLabel, overlay, useError, useNav, type Me, type Rights } from './util'

export type FormTarget = { entity: 'person' | 'organization' | 'lead'; id: string | null; lead?: Lead }
type Opts = { orgs: { id: string; name: string }[]; people: { id: string; name: string }[]; fields: Field[] }
type V = Record<string, unknown>

const TEXT: Record<FormTarget['entity'], [string, number, string?][]> = {
  person: [['name', 200], ['email', 254, 'email'], ['phone', 40, 'tel'], ['title', 80], ['source', 60], ['city', 80], ['fylke', 60], ['linkedin', 200]],
  organization: [['name', 200], ['org_number', 9], ['address', 200], ['postal_code', 12], ['city', 80], ['fylke', 60], ['industry', 80], ['website', 200], ['phone', 40, 'tel'], ['email', 254, 'email'], ['source', 60]],
  lead: [['title', 200], ['source', 60]],
}
const CUSTOM_OK = ['text', 'large_text', 'phone', 'autocomplete', 'numerical', 'single_option', 'multiple_options', 'date', 'user', 'organization']

/**
 * Create and edit a person, an organization or a lead (the design's «＋ Person» opens a form it does not
 * draw; built in the convert dialog's language, D-41). Owner, labels and custom fields from fields_get.
 */
export function RecordForm({ target, data, rights, me, onClose }: { target: FormTarget; data: ContactsData; rights: Rights; me: Me; onClose: () => void }) {
  const t = useTranslations('contacts')
  const flash = useToast()
  const err = useError()
  const { go, refresh } = useNav()
  const { entity, id } = target
  const current: V | null = !id ? null
    : entity === 'person' ? (data.detail?.person as V | undefined) ?? null
    : entity === 'organization' ? (data.org?.row as V | undefined) ?? null
    : (target.lead as V | undefined) ?? null
  const [v, setV] = useState<V>(() => (current ? { ...current, custom: { ...((current.custom as V) ?? {}) } } : { owner_id: me.id, labels: [], custom: {} }))
  const [opts, setOpts] = useState<Opts | null>(null)
  const [busy, setBusy] = useState(false)
  const [bad, setBad] = useState<string | null>(null)
  const labels = data.labels[entity]

  useEffect(() => {
    void formOptions({ entity }).then((r) => (r.ok ? setOpts(r) : flash(err(r.code))))
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', k)
    return () => window.removeEventListener('keydown', k)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const set = (k: string, x: unknown) => setV((o) => ({ ...o, [k]: x }))
  const setCustom = (k: string, x: unknown) => setV((o) => ({ ...o, custom: { ...(o.custom as V), [k]: x } }))
  const str = (k: string) => (typeof v[k] === 'string' || typeof v[k] === 'number' ? String(v[k]) : '')
  const fields = (opts?.fields ?? []).filter((f) => CUSTOM_OK.includes(f.type))

  async function save() {
    const values: V = {}
    for (const [k] of TEXT[entity]) values[k] = str(k).trim() || null
    if (entity === 'person') { values.organization_id = v.organization_id || null; values.contact_type = v.contact_type || null }
    if (entity === 'organization') { values.employees = str('employees') ? Number(str('employees')) : null; values.org_number = str('org_number').replace(/\s/g, '') || null }
    if (entity === 'lead') { values.person_id = v.person_id || null; values.organization_id = v.organization_id || null; values.value = str('value') ? Number(str('value').replace(/\s/g, '').replace(',', '.')) : null }
    values.owner_id = v.owner_id || null
    values.labels = v.labels ?? []
    const custom: V = {}
    for (const f of fields) {
      if (f.readonly) continue
      const x = (v.custom as V)[f.key]
      const before = (current?.custom as V | undefined)?.[f.key]
      if (x === undefined || (x === before)) continue
      custom[f.key] = x === '' ? null : f.type === 'numerical' && typeof x === 'string' ? Number(x.replace(',', '.')) : x
    }
    if (Object.keys(custom).length) values.custom = custom
    setBusy(true); setBad(null)
    const r = await saveRecord({ entity, id, version: id ? Number(current?.version ?? 0) || null : null, values })
    setBusy(false)
    if (!r.ok) { if (r.code === 'invalid') setBad('invalid'); return flash(err(r.code)) }
    flash(id ? t('form.saved') : t(`form.created.${entity}`))
    onClose()
    if (!id && entity === 'person') go({ person: r.id }, true)
    else if (!id && entity === 'lead') go({ lead: r.id })
    else if (!id && entity === 'organization') go({ org: r.id })
    else refresh()
  }
  async function remove() {
    if (!id || !window.confirm(t('form.confirmDelete'))) return
    const r = await deleteRecord({ entity, id })
    if (!r.ok) return flash(err(r.code))
    flash(t('form.deleted'))
    onClose()
    go(entity === 'person' ? { person: null } : entity === 'lead' ? { lead: null } : { org: null })
  }

  const required = entity === 'lead' ? 'title' : 'name'
  const ready = !!str(required).trim() && (entity !== 'lead' || !!v.person_id || !!v.organization_id) && (entity !== 'organization' || !str('org_number') || /^\d{9}$/.test(str('org_number').replace(/\s/g, '')))

  return (
    <div className={overlay} onClick={onClose}>
      <div role="dialog" aria-modal="true" aria-labelledby="form-title" onClick={(e) => e.stopPropagation()}
        className="flex max-h-[90vh] w-[560px] max-w-full flex-col gap-3 overflow-auto rounded-22 bg-surface px-6 py-[22px] shadow-modal">
        <div id="form-title" className="font-serif text-21 font-semibold">{t(`form.title.${id ? 'edit' : 'new'}.${entity}`)}</div>
        <div className="grid gap-3 md:grid-cols-2">
          {TEXT[entity].map(([k, max, type], i) => (
            <label key={k} className={`${fieldLabel} ${i === 0 ? 'md:col-span-2' : ''}`}>
              {t(`form.f.${entity}.${k}` as 'form.f.person.name')}{k === required ? ' *' : ''}
              <input autoFocus={i === 0} type={type ?? 'text'} value={str(k)} maxLength={max} onChange={(e) => set(k, e.target.value)} className={fieldInput} />
            </label>
          ))}
          {entity === 'organization' ? (
            <label className={fieldLabel}>{t('form.f.organization.employees')}<input type="number" min={0} value={str('employees')} onChange={(e) => set('employees', e.target.value)} className={fieldInput} /></label>
          ) : null}
          {entity === 'lead' ? (
            <label className={fieldLabel}>{t('form.f.lead.value')}<input inputMode="decimal" value={str('value')} onChange={(e) => set('value', e.target.value)} className={fieldInput} /></label>
          ) : null}
          {entity === 'person' ? (
            <label className={fieldLabel}>{t('form.f.person.contact_type')}
              <select value={str('contact_type')} onChange={(e) => set('contact_type', e.target.value)} className={fieldInput}>
                <option value="">—</option>
                {CONTACT_TYPES.map((c) => <option key={c} value={c}>{t(`contactType.${c}`)}</option>)}
              </select>
            </label>
          ) : null}
          {entity === 'lead' ? (
            <label className={fieldLabel}>{t('form.f.lead.person_id')}
              <select value={str('person_id')} onChange={(e) => set('person_id', e.target.value)} className={fieldInput}>
                <option value="">—</option>
                {(opts?.people ?? []).map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </label>
          ) : null}
          {entity !== 'organization' ? (
            <label className={fieldLabel}>{t('form.f.organization_id')}
              <select value={str('organization_id')} onChange={(e) => set('organization_id', e.target.value)} className={fieldInput}>
                <option value="">—</option>
                {(opts?.orgs ?? []).map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </label>
          ) : null}
          <label className={fieldLabel}>{t('form.f.owner')}
            <select value={str('owner_id')} onChange={(e) => set('owner_id', e.target.value)} className={fieldInput}>
              <option value="">—</option>
              {data.staff.filter((s) => s.active || s.id === v.owner_id).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          {fields.map((f) => (
            <CustomInput key={f.id} f={f} value={(v.custom as V)[f.key]} onChange={(x) => setCustom(f.key, x)} data={data} opts={opts} />
          ))}
        </div>
        {labels.length ? (
          <div className="flex flex-col gap-[5px]">
            <span className="text-12 font-semibold text-muted">{t('form.labels')}</span>
            <div className="flex flex-wrap gap-[5px]">
              {labels.map((l) => {
                const on = ((v.labels as string[]) ?? []).includes(l.id)
                return (
                  <button key={l.id} type="button" aria-pressed={on} onClick={() => set('labels', on ? (v.labels as string[]).filter((x) => x !== l.id) : [...((v.labels as string[]) ?? []), l.id])}
                    className={`cursor-pointer rounded-999 border px-[10px] py-1 text-11.5 font-bold ${on ? 'border-transparent' : 'border-line-strong bg-transparent text-muted'}`}
                    style={on ? { background: l.bg, color: l.ink } : undefined}>{l.name}</button>
                )
              })}
            </div>
          </div>
        ) : null}
        {entity === 'lead' ? <div className="text-11.5 text-faint">{t('form.leadNeeds')}</div> : null}
        {bad ? <div className="text-12 text-danger">{t('form.invalid')}</div> : null}
        <div className="flex flex-wrap items-center justify-end gap-2">
          {id && rights.del ? <button type="button" onClick={remove} className="mr-auto h-[38px] cursor-pointer rounded-11 border border-coral bg-transparent px-[15px] text-13 font-semibold text-rust">{t('form.delete')}</button> : null}
          <button type="button" onClick={onClose} className="h-[38px] cursor-pointer rounded-11 border border-line bg-transparent px-[15px] text-13 font-semibold">{t('cancel')}</button>
          <button type="button" disabled={busy || !ready} onClick={save} className="h-[38px] cursor-pointer rounded-11 border border-ink bg-primary px-[17px] text-13 font-bold disabled:cursor-default disabled:opacity-60">{t('form.save')}</button>
        </div>
      </div>
    </div>
  )
}

/** One custom field, by its type; read-only fields are shown and not sent. */
function CustomInput({ f, value, onChange, data, opts }: { f: Field; value: unknown; onChange: (v: unknown) => void; data: ContactsData; opts: Opts | null }) {
  const s = typeof value === 'string' || typeof value === 'number' ? String(value) : ''
  const label = `${f.label}${f.quality === 'required' ? ' *' : ''}`
  const optLabel = (o: Field['options'][number]) => o.label ?? o.key
  if (f.type === 'multiple_options') {
    const cur = Array.isArray(value) ? (value as string[]) : []
    return (
      <fieldset className="m-0 flex flex-col gap-[5px] border-none p-0 text-12 font-semibold text-muted md:col-span-2">
        <legend className="mb-[5px] p-0">{label}</legend>
        <div className="flex flex-wrap gap-[10px] font-normal text-ink">
          {f.options.map((o) => (
            <label key={o.key} className="flex items-center gap-[5px] text-12.5">
              <input type="checkbox" disabled={f.readonly} checked={cur.includes(o.key)} onChange={(e) => onChange(e.target.checked ? [...cur, o.key] : cur.filter((x) => x !== o.key))} className="accent-ink" />{optLabel(o)}
            </label>
          ))}
        </div>
      </fieldset>
    )
  }
  const common = { disabled: f.readonly, className: fieldInput }
  return (
    <label className={`${fieldLabel} ${f.type === 'large_text' ? 'md:col-span-2' : ''}`}>
      {label}
      {f.type === 'single_option' ? (
        <select value={s} onChange={(e) => onChange(e.target.value || null)} {...common}><option value="">—</option>{f.options.map((o) => <option key={o.key} value={o.key}>{optLabel(o)}</option>)}</select>
      ) : f.type === 'user' ? (
        <select value={s} onChange={(e) => onChange(e.target.value || null)} {...common}><option value="">—</option>{data.staff.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}</select>
      ) : f.type === 'organization' ? (
        <select value={s} onChange={(e) => onChange(e.target.value || null)} {...common}><option value="">—</option>{(opts?.orgs ?? []).map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}</select>
      ) : f.type === 'large_text' ? (
        <textarea value={s} onChange={(e) => onChange(e.target.value)} disabled={f.readonly} className="min-h-[60px] rounded-10 border border-line bg-canvas px-2 py-2 text-13 font-normal text-ink" />
      ) : (
        <input type={f.type === 'numerical' ? 'number' : f.type === 'date' ? 'date' : f.type === 'phone' ? 'tel' : 'text'} value={s} onChange={(e) => onChange(e.target.value)} {...common} />
      )}
    </label>
  )
}
