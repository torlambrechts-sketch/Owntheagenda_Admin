'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { formatNumber, percent, type NumberFormat } from '@/lib/format'
import { recordHref } from '@/lib/records-href'
import {
  FIELD_KINDS, FORM_KINDS, FORM_LANGS, TEXT_MAPS, addField, blockAllowed, doubleOptIn, moveField, patchField, removeField,
  type Draft, type FieldKind, type FormDetail, type FormKind, type FormLang, type FormRow, type Submission,
} from '@/lib/data/capture-shared'
import { createForm, deleteForm, publishForm, saveConsentText, saveForm, setFormStatus, type Result } from '../actions'
import { useErr, useGo } from './hooks'

type Sel = { k: 'intro' } | { k: 'field'; i: number } | null
export type FormsProps = {
  forms: FormRow[]
  form: FormDetail | null
  submissions: Submission[] | null
  sequences: { id: string; name: string; state: string }[]
  pipelines: { id: string; name: string; stages: { id: string; name: string }[] }[]
  customFields: { map: string; label: string }[]
  /** the assignment rule a web-form record meets: its name, '' when none matches, null when unknown */
  rules: { lead: string | null; deal: string | null }
  can: { add: boolean; configure: boolean; del: boolean; editOthers: boolean; me: string }
  nf: NumberFormat
}

const card = 'rounded-18 border border-line bg-surface'
const small = 'h-[30px] rounded-9 border border-line bg-canvas px-[9px] text-12 text-ink'
const btn = 'h-[30px] cursor-pointer whitespace-nowrap rounded-9 border px-3 text-12 font-bold disabled:cursor-default disabled:opacity-50'

/** Web forms (Marketing.dc.html, v.forms): the form list and templates, the canvas, blocks and after-submit. */
export function FormsView(p: FormsProps) {
  const t = useTranslations('capture.forms')
  const { go } = useGo()
  const sel = p.form?.id ?? null
  return (
    <div className="grid grid-cols-1 items-start gap-3 lg:[grid-template-columns:minmax(220px,260px)_minmax(0,1fr)_minmax(240px,300px)]">
      <FormList {...p} selected={sel} onPick={(id) => go({ form: id })} />
      {p.form ? (
        <Editor key={`${p.form.id}:${p.form.version}`} {...p} form={p.form} />
      ) : (
        <>
          <div className="flex justify-center rounded-18 border border-line bg-canvas p-[18px]">
            <div className="flex w-[420px] max-w-full flex-col gap-2 rounded-18 border border-dashed border-line-strong bg-surface p-5 text-center">
              <b className="text-14">{t('empty.title')}</b>
              <span className="text-12.5 text-muted">{t(p.can.add ? 'empty.body' : 'empty.bodyReadOnly')}</span>
            </div>
          </div>
          <div />
        </>
      )}
    </div>
  )
}

function FormList({ forms, selected, onPick, can, nf }: FormsProps & { selected: string | null; onPick: (id: string) => void }) {
  const t = useTranslations('capture.forms')
  const tk = useTranslations('capture.kinds')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [making, setMaking] = useState<FormKind | null>(null)
  const [name, setName] = useState('')
  const [lang, setLang] = useState<FormLang>('nb')
  const [busy, start] = useTransition()

  const create = () => start(async () => {
    if (!making) return
    const r = await createForm({ kind: making, name: name.trim() || tk(making), language: lang })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('created'))
    setMaking(null)
    setName('')
    router.push(`/lead-capture?form=${r.id}` as Route, { scroll: false })
  })

  const sub = (f: FormRow) => [
    tk(f.kind),
    f.landing,
    f.current_version === 0 ? t('notPublished') : f.status === 'inactive' ? t('inactive') : null,
    t('thisMonth', { n: formatNumber(f.submissions_month, nf) }),
  ].filter(Boolean).join(' · ')

  return (
    <div className={`overflow-hidden ${card}`}>
      {forms.map((f) => (
        <button
          key={f.id}
          type="button"
          onClick={() => onPick(f.id)}
          aria-current={f.id === selected ? 'true' : undefined}
          className={`flex w-full cursor-pointer flex-col gap-[2px] border-0 border-b border-line px-[13px] py-[11px] text-left ${f.id === selected ? 'bg-highlight' : 'bg-transparent'}`}
        >
          <b className="text-13">{f.name}</b>
          <span className="text-11.5 text-muted">{sub(f)}</span>
        </button>
      ))}
      {forms.length === 0 ? <div className="border-0 border-b border-line px-[13px] py-[11px] text-12 text-muted">{t('none')}</div> : null}
      <div className="flex flex-wrap gap-[5px] px-[13px] py-[10px]">
        {FORM_KINDS.map((k) => (
          <button
            key={k}
            type="button"
            disabled={!can.add}
            onClick={() => { setMaking(k); setName('') }}
            title={can.add ? t('newFrom', { kind: tk(k) }) : undefined}
            className={`rounded-999 border border-dashed px-[9px] py-[3px] text-11 ${making === k ? 'border-ink bg-highlight' : 'border-line-strong bg-transparent'} ${can.add ? 'cursor-pointer' : 'cursor-default'}`}
          >
            {tk(k)}
          </button>
        ))}
      </div>
      {making ? (
        <div className="flex flex-col gap-[6px] border-0 border-t border-line px-[13px] py-[10px]">
          <label className="flex flex-col gap-[3px] text-11.5 text-muted">
            {t('newName')}
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder={tk(making)} maxLength={120} className={`${small} text-ink`} />
          </label>
          <label className="flex flex-col gap-[3px] text-11.5 text-muted">
            {t('language')}
            <select value={lang} onChange={(e) => setLang(e.target.value as FormLang)} className={`${small} text-ink`}>
              {FORM_LANGS.map((l) => <option key={l} value={l}>{t(`langs.${l}`)}</option>)}
            </select>
          </label>
          <span className="text-11 text-faint">{t('languageFixed')}</span>
          <div className="flex gap-[6px]">
            <button type="button" onClick={create} disabled={busy} className={`${btn} border-ink bg-primary`}>{t('create')}</button>
            <button type="button" onClick={() => setMaking(null)} className={`${btn} border-line bg-transparent font-semibold`}>{t('cancel')}</button>
          </div>
        </div>
      ) : null}
    </div>
  )
}

/** The canvas, the blocks, after-submit, publishing and submissions of one form. */
function Editor(p: FormsProps & { form: FormDetail }) {
  const { form } = p
  const t = useTranslations('capture.forms')
  const tb = useTranslations('capture.blocks')
  const tm = useTranslations('capture.maps')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [draft, setDraft] = useState<Draft>(form.draft)
  const [name, setName] = useState(form.name)
  const [dirty, setDirty] = useState(false)
  const [sel, setSel] = useState<Sel>(null)
  const [busy, start] = useTransition()
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [afterOpen, setAfterOpen] = useState(false)
  const lang = form.language
  const mine = form.owner?.id === p.can.me
  const edit = p.can.add && (mine || p.can.editOthers)
  const consent = form.consent_texts.find((c) => c.key === (draft.consent?.text_key ?? 'newsletter')) ?? null
  const doi = doubleOptIn(draft, form.settings.double_opt_in)
  const hasConsent = draft.fields.some((f) => f.kind === 'marketing_status')
  const a = draft.after_submit ?? {}

  const change = (d: Draft) => { setDraft(d); setDirty(true) }
  const run = (fn: () => Promise<Result<object>>, okMsg: string) => start(async () => {
    const r = await fn()
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(okMsg)
    setDirty(false)
    router.refresh()
  })
  const payload = () => ({ id: form.id, draft, version: form.version, ...(name.trim() && name.trim() !== form.name ? { name: name.trim() } : {}) })

  const sequence = p.sequences.find((s) => s.id === a.sequence_id) ?? null
  const pipeline = p.pipelines.find((x) => x.id === a.pipeline_id) ?? null
  const conv = form.views_month > 0 ? percent((form.submissions_month / form.views_month) * 100, p.nf) : null
  const hiddenNames = (draft.hidden ?? []).map((h) => t(`hidden.${h}`)).join(', ')

  return (
    <>
      {/* the canvas */}
      <div className="flex justify-center rounded-18 border border-line bg-canvas p-[18px]">
        <div className="flex w-[420px] max-w-full flex-col gap-[10px] rounded-18 border border-line bg-surface p-5">
          <Pickable on={sel?.k === 'intro'} onPick={() => setSel(sel?.k === 'intro' ? null : { k: 'intro' })} label={t('editIntro')}>
            <div className="rounded-12 border border-dashed border-line-strong px-3 py-[10px]">
              <span className="text-10 font-bold uppercase tracking-label text-muted">{t('intro')}</span>
              <div className="mt-1 font-serif text-19 font-semibold">{draft.intro.title}</div>
              {draft.intro.body ? <div className="mt-[3px] text-12.5 text-muted">{draft.intro.body}</div> : null}
            </div>
          </Pickable>
          {sel?.k === 'intro' && edit ? (
            <Panel>
              <Labelled label={t('introTitle')}>
                <input value={draft.intro.title} maxLength={200} onChange={(e) => change({ ...draft, intro: { ...draft.intro, title: e.target.value } })} className={small} />
              </Labelled>
              <Labelled label={t('introBody')}>
                <textarea value={draft.intro.body ?? ''} maxLength={2000} onChange={(e) => change({ ...draft, intro: { ...draft.intro, body: e.target.value } })} className="min-h-[60px] rounded-9 border border-line bg-canvas p-[9px] text-12 text-ink" />
              </Labelled>
              <span className="text-11 text-faint">{t('introMandatory')}</span>
            </Panel>
          ) : null}

          {draft.fields.map((f, i) => {
            const on = sel?.k === 'field' && sel.i === i
            const pick = () => setSel(on ? null : { k: 'field', i })
            return (
              <div key={f.key} className="flex flex-col gap-[10px]">
                {f.kind === 'marketing_status' ? (
                  <Pickable on={on} onPick={pick} label={t('editField', { label: t('consentBox') })}>
                    <div className="flex items-start gap-2 text-12 leading-[1.45]">
                      <input type="checkbox" tabIndex={-1} checked={false} readOnly aria-hidden className="mt-[2px] accent-ink" />
                      <span>
                        {consent ? consent.body : <span className="text-danger">{t('noWording', { lang: t(`langs.${lang}`) })}</span>}
                        {' '}{t(doi ? 'consentPending' : 'consentSubscribed')}
                      </span>
                    </div>
                  </Pickable>
                ) : (
                  <Pickable on={on} onPick={pick} label={t('editField', { label: f.label ?? '' })}>
                    <div className="flex flex-col gap-1 text-12 font-semibold">
                      {f.label}{' '}<span className="text-danger">{f.required ? '*' : ''}</span>
                      {f.kind === 'message' ? (
                        <textarea tabIndex={-1} readOnly aria-hidden placeholder={f.placeholder} className="min-h-[76px] rounded-10 border-[1.5px] border-ink bg-surface p-[10px] text-13" />
                      ) : f.kind === 'file_upload' ? (
                        <span className="flex h-[38px] items-center rounded-10 border-[1.5px] border-dashed border-ink bg-surface px-[10px] text-13 font-normal text-faint">{t('chooseFile')}</span>
                      ) : (
                        <input tabIndex={-1} readOnly aria-hidden placeholder={f.placeholder} className="h-[38px] rounded-10 border-[1.5px] border-ink bg-surface px-[10px] text-13" />
                      )}
                    </div>
                  </Pickable>
                )}
                {on && edit ? (
                  <Panel>
                    {f.kind === 'marketing_status' ? (
                      <ConsentEditor key={consent?.id ?? 'none'} lang={lang} textKey={draft.consent?.text_key ?? 'newsletter'} body={consent?.body ?? ''} version={consent?.version ?? 0} canSave={p.can.configure} />
                    ) : (
                      <>
                        <Labelled label={t('fieldLabel')}>
                          <input value={f.label ?? ''} maxLength={200} onChange={(e) => change(patchField(draft, i, { label: e.target.value }))} className={small} />
                        </Labelled>
                        {f.kind !== 'file_upload' ? (
                          <Labelled label={t('placeholder')}>
                            <input value={f.placeholder ?? ''} maxLength={200} onChange={(e) => change(patchField(draft, i, { placeholder: e.target.value }))} className={small} />
                          </Labelled>
                        ) : null}
                        {f.kind === 'short_text' ? (
                          <Labelled label={t('savesTo')}>
                            <select value={f.map ?? ''} onChange={(e) => change(patchField(draft, i, { map: e.target.value }))} className={small}>
                              <option value="">{t('savesToLead')}</option>
                              {TEXT_MAPS.map((m) => (
                                <option key={m} value={m} disabled={draft.fields.some((x, k) => k !== i && x.map === m)}>{tm(m)}</option>
                              ))}
                            </select>
                          </Labelled>
                        ) : null}
                        {f.kind === 'custom_field' ? (
                          <Labelled label={t('savesTo')}>
                            <select value={f.map ?? ''} onChange={(e) => change(patchField(draft, i, { map: e.target.value }))} className={small}>
                              {p.customFields.map((c) => <option key={c.map} value={c.map}>{c.label}</option>)}
                            </select>
                          </Labelled>
                        ) : null}
                        <label className="flex items-center gap-2 text-12">
                          <input type="checkbox" checked={f.required ?? false} onChange={(e) => change(patchField(draft, i, { required: e.target.checked }))} className="accent-ink" />
                          {t('required')}
                        </label>
                      </>
                    )}
                    <div className="flex flex-wrap gap-[6px]">
                      <button type="button" disabled={i === 0} onClick={() => { change(moveField(draft, i, -1)); setSel({ k: 'field', i: i - 1 }) }} className={`${btn} border-line bg-transparent font-semibold`} aria-label={t('moveUp')}>↑</button>
                      <button type="button" disabled={i === draft.fields.length - 1} onClick={() => { change(moveField(draft, i, 1)); setSel({ k: 'field', i: i + 1 }) }} className={`${btn} border-line bg-transparent font-semibold`} aria-label={t('moveDown')}>↓</button>
                      <button type="button" onClick={() => { change(removeField(draft, i)); setSel(null) }} className={`${btn} border-line bg-transparent font-semibold text-danger`}>{t('remove')}</button>
                    </div>
                  </Panel>
                ) : null}
              </div>
            )
          })}
          <button type="button" tabIndex={-1} className="h-[42px] rounded-12 border border-ink bg-primary text-14 font-bold">{t('send')}</button>
          {form.kind === 'file_upload' ? <div className="text-11.5 font-bold text-danger">{t('employeeListNotice')}</div> : null}
          <div className="text-11 text-faint">
            {(draft.hidden ?? []).length > 0
              ? t('hiddenLine', { fields: hiddenNames, setting: t(form.settings.form_tracking === 'on' ? 'settingOn' : 'settingOffNotStored') })
              : t('hiddenNone')}
            {' · '}
            {t('createsLine', { creates: a.creates ?? 'lead', ticket: String(a.ticket ?? form.kind === 'contact'), consent: String(hasConsent) })}
          </div>
        </div>
      </div>

      {/* blocks, after submit, publishing, submissions */}
      <div className="flex flex-col gap-[10px]">
        <div className={`flex flex-col gap-[6px] p-[14px] ${card}`}>
          <b className="text-13.5">{t('blocks')}</b>
          {FIELD_KINDS.map((b) => {
            const ok = edit && blockAllowed(draft, form.kind, b, p.customFields.length)
            return (
              <button
                key={b}
                type="button"
                disabled={!ok}
                title={!ok && edit ? t(`blockWhy.${b}`) : undefined}
                onClick={() => { change(addField(draft, b as FieldKind, lang, b === 'custom_field' ? p.customFields[0]?.map : undefined)); setSel({ k: 'field', i: draft.fields.length }) }}
                className={`rounded-9 border border-line bg-canvas px-[9px] py-[6px] text-left text-12 ${ok ? 'cursor-pointer' : 'cursor-default text-faint'}`}
              >
                ＋ {tb(b)}
              </button>
            )
          })}
        </div>

        <div className={`flex flex-col gap-[6px] p-[14px] ${card}`}>
          <b className="text-13.5">{t('afterSubmit')}</b>
          <span className="text-12 leading-[1.5] text-ink-2">
            {[
              t(a.creates === 'deal' ? 'after.deal' : 'after.lead', { pipeline: pipeline?.name ?? '' }),
              ((r) => (r == null ? t('after.owner') : r === '' ? t('after.ownerNone') : t('after.ownerRule', { name: r })))(p.rules[a.creates === 'deal' ? 'deal' : 'lead']),
              ...(a.ticket ?? form.kind === 'contact' ? [t('after.ticket')] : []),
              ...(sequence ? [t('after.sequence', { name: sequence.name })] : []),
              a.redirect_url ? t('after.redirect') : t('after.thanks'),
            ].join(' → ')}.
          </span>
          {sequence && sequence.state !== 'active' ? <span className="text-11.5 text-warn-ink">{t('after.sequenceDraft', { name: sequence.name })}</span> : null}
          <span className="text-12 text-muted">
            {t.rich('stats', {
              n: formatNumber(form.submissions_month, p.nf),
              conv: conv ?? '—',
              b: (c) => <b className="text-ink">{c}</b>,
            })}
          </span>
          {edit ? (
            <button type="button" onClick={() => setAfterOpen(!afterOpen)} aria-expanded={afterOpen} className="self-start cursor-pointer border-0 bg-transparent p-0 text-12 font-semibold text-link">
              {afterOpen ? t('after.hide') : t('after.edit')}
            </button>
          ) : null}
          {afterOpen && edit ? (
            <div className="mt-1 flex flex-col gap-2 border-0 border-t border-line pt-2">
              <Labelled label={t('after.creates')}>
                <select value={a.creates ?? 'lead'} onChange={(e) => {
                  const creates = e.target.value as 'lead' | 'deal'
                  const first = p.pipelines[0]
                  const next = { ...a, creates } as NonNullable<Draft['after_submit']>
                  if (creates === 'deal' && first && !next.pipeline_id) { next.pipeline_id = first.id; if (first.stages[0]) next.stage_id = first.stages[0].id }
                  if (creates === 'lead') { delete next.pipeline_id; delete next.stage_id }
                  change({ ...draft, after_submit: next })
                }} className={small}>
                  <option value="lead">{t('after.optLead')}</option>
                  <option value="deal" disabled={p.pipelines.length === 0}>{t('after.optDeal')}</option>
                </select>
              </Labelled>
              {a.creates === 'deal' ? (
                <Labelled label={t('after.pipeline')}>
                  <select value={`${a.pipeline_id ?? ''}|${a.stage_id ?? ''}`} onChange={(e) => {
                    const [pid, sid] = e.target.value.split('|')
                    change({ ...draft, after_submit: { ...a, pipeline_id: pid || undefined, stage_id: sid || undefined } })
                  }} className={small}>
                    {p.pipelines.flatMap((x) => x.stages.map((s) => <option key={s.id} value={`${x.id}|${s.id}`}>{x.name} · {s.name}</option>))}
                  </select>
                </Labelled>
              ) : null}
              <label className="flex items-center gap-2 text-12">
                <input type="checkbox" checked={a.ticket ?? form.kind === 'contact'} onChange={(e) => change({ ...draft, after_submit: { ...a, ticket: e.target.checked } })} className="accent-ink" />
                {t('after.ticketToggle')}
              </label>
              <Labelled label={t('after.sequenceLabel')}>
                <select value={a.sequence_id ?? ''} onChange={(e) => change({ ...draft, after_submit: { ...a, sequence_id: e.target.value || undefined } })} className={small}>
                  <option value="">{t('after.noSequence')}</option>
                  {p.sequences.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </Labelled>
              <Labelled label={t('after.thanksLabel')}>
                <textarea value={a.thank_you ?? ''} maxLength={500} onChange={(e) => change({ ...draft, after_submit: { ...a, thank_you: e.target.value || undefined } })} className="min-h-[52px] rounded-9 border border-line bg-canvas p-[9px] text-12 text-ink" />
              </Labelled>
              <Labelled label={t('after.redirectLabel')}>
                <input value={a.redirect_url ?? ''} placeholder="https://" maxLength={2000} onChange={(e) => change({ ...draft, after_submit: { ...a, redirect_url: e.target.value || undefined } })} className={small} />
              </Labelled>
              {form.kind === 'gated_download' ? (
                <span className="text-11.5 text-warn-ink">{t('after.assetMissing')}</span>
              ) : null}
            </div>
          ) : null}
        </div>

        <div className={`flex flex-col gap-2 p-[14px] ${card}`}>
          <div className="flex items-center justify-between gap-2">
            <b className="text-13.5">{t('publishing')}</b>
            <span className={`rounded-999 px-[9px] py-[2px] text-11 font-bold ${form.status === 'active' ? 'bg-ok-bg text-ok-ink' : 'bg-tile'}`}>
              {t(form.current_version === 0 ? 'stateDraft' : form.status === 'active' ? 'stateActive' : 'stateInactive')}
            </span>
          </div>
          {edit ? (
            <Labelled label={t('formName')}>
              <input value={name} maxLength={120} onChange={(e) => { setName(e.target.value); setDirty(true) }} className={small} />
            </Labelled>
          ) : null}
          <span className="text-12 text-muted">
            {form.versions[0]
              ? t('publishedLine', { v: form.versions[0].version, date: fmt.dateTime(new Date(form.versions[0].published_at), { day: 'numeric', month: 'short', year: 'numeric' }), by: form.versions[0].by ?? '—' })
              : t('neverPublished')}
            {' · '}{t(`langs.${lang}`)}
          </span>
          <div className="break-all rounded-9 bg-canvas px-[9px] py-[7px] font-mono text-11.5">{form.public_url}</div>
          <span className="text-11 text-faint">{t('hostNote')}</span>
          {hasConsent && doi && !form.settings.email_connected ? <span className="text-11.5 text-warn-ink">{t('doiNotSent')}</span> : null}
          {dirty ? <span className="text-11.5 font-semibold text-warn-ink">{t('unsaved')}</span> : null}
          <div className="flex flex-wrap gap-[6px]">
            {edit ? (
              <button type="button" disabled={busy || !dirty} onClick={() => run(() => saveForm(payload()), t('saved'))} className={`${btn} border-ink bg-primary`}>{t('save')}</button>
            ) : null}
            {p.can.configure ? (
              <button type="button" disabled={busy || !edit} onClick={() => run(() => publishForm(payload()), t('publishedToast'))} className={`${btn} border-ink bg-surface`}>{t('publish')}</button>
            ) : null}
            {p.can.configure && form.current_version > 0 ? (
              <button type="button" disabled={busy} onClick={() => run(() => setFormStatus({ id: form.id, status: form.status === 'active' ? 'inactive' : 'active' }), t(form.status === 'active' ? 'deactivated' : 'activated'))} className={`${btn} border-line bg-transparent font-semibold`}>
                {t(form.status === 'active' ? 'deactivate' : 'activate')}
              </button>
            ) : null}
            {p.can.del ? (
              confirmDelete ? (
                <button type="button" disabled={busy} onClick={() => start(async () => {
                  const r = await deleteForm({ id: form.id })
                  if (!r.ok) { flash(err(r.code, r.detail)); return }
                  flash(t('deleted'))
                  router.push('/lead-capture' as Route, { scroll: false })
                })} className={`${btn} border-danger bg-transparent text-danger`}>{t('confirmDelete')}</button>
              ) : (
                <button type="button" onClick={() => setConfirmDelete(true)} className={`${btn} border-line bg-transparent font-semibold text-danger`}>{t('delete')}</button>
              )
            ) : null}
          </div>
          {!p.can.configure ? <span className="text-11 text-faint">{t('publishRight')}</span> : null}
        </div>

        {p.submissions ? (
          <div className={`flex flex-col gap-[6px] p-[14px] ${card}`}>
            <b className="text-13.5">{t('submissions')}</b>
            {p.submissions.length === 0 ? <span className="text-12 text-muted">{t('noSubmissions')}</span> : null}
            {p.submissions.map((s) => {
              const href = s.lead_id ? recordHref('lead', s.lead_id) : s.deal_id ? recordHref('deal', s.deal_id) : null
              const who = s.person?.name ?? s.person?.email ?? '—'
              return (
                <div key={s.id} className="flex items-center justify-between gap-2 border-0 border-b border-line py-1 text-12">
                  <span className="min-w-0 truncate">
                    {href ? <Link href={href as Route}>{who}</Link> : who}
                    {s.state !== 'accepted' ? <span className="text-muted"> · {t(`subState.${s.state}`)}</span> : null}
                    {s.consent.status ? <span className="text-muted"> · {t(`consentState.${s.consent.status}`)}</span> : null}
                  </span>
                  <span className="shrink-0 text-muted">{fmt.dateTime(new Date(s.created_at), { day: 'numeric', month: 'short' })}</span>
                </div>
              )
            })}
          </div>
        ) : null}
      </div>
    </>
  )
}

/** A canvas block that can be picked for editing (the builder's selected outline). */
function Pickable({ on, onPick, label, children }: { on: boolean; onPick: () => void; label: string; children: React.ReactNode }) {
  return (
    <div
      role="button"
      tabIndex={0}
      aria-pressed={on}
      aria-label={label}
      onClick={onPick}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onPick() } }}
      className={`cursor-pointer rounded-12 ${on ? '[outline:2px_solid_#191510] [outline-offset:3px]' : ''}`}
    >
      {children}
    </div>
  )
}

const Panel = ({ children }: { children: React.ReactNode }) => (
  <div className="flex flex-col gap-2 rounded-12 border border-line bg-canvas p-[10px] text-12">{children}</div>
)

const Labelled = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <label className="flex flex-col gap-[3px] text-11.5 text-muted">
    {label}
    {children}
  </label>
)

/** The consent box's wording in the form's language: a change is a new version (campaigns:configure). */
function ConsentEditor({ lang, textKey, body, version, canSave }: { lang: FormLang; textKey: string; body: string; version: number; canSave: boolean }) {
  const t = useTranslations('capture.forms')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [text, setText] = useState(body)
  const [busy, start] = useTransition()
  return (
    <>
      <Labelled label={t('wording', { v: version, lang: t(`langs.${lang}`) })}>
        <textarea value={text} disabled={!canSave} maxLength={2000} onChange={(e) => setText(e.target.value)} className="min-h-[52px] rounded-9 border border-line bg-surface p-[9px] text-12 text-ink" />
      </Labelled>
      <span className="text-11 text-faint">{t('wordingNote')}</span>
      {canSave ? (
        <button type="button" disabled={busy || !text.trim() || text.trim() === body} onClick={() => start(async () => {
          const r = await saveConsentText({ key: textKey, locale: lang, body: text })
          if (!r.ok) { flash(err(r.code, r.detail)); return }
          flash(t('wordingSaved', { v: r.version }))
          router.refresh()
        })} className={`${btn} self-start border-ink bg-surface`}>{t('wordingSave')}</button>
      ) : null}
    </>
  )
}
