'use client'

import { useEffect, useState, useTransition } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { useRouter } from 'next/navigation'
import { useFormatter, useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { Switch } from '@/components/ui/Switch'
import { formatNumber, type NumberFormat } from '@/lib/format'
import { footerProblems, renderEmail } from '@/lib/data/campaigns-render'
import {
  BACKGROUNDS, BLANK_DESIGN, CAMPAIGN_LANGUAGES, CAMPAIGN_TYPES, HTML_STARTER, PADDINGS, PALETTE, addRow, canEdit, isFixed, itemHref, itemLabel, moveRow, patchRow, removeRow, toLocalInput,
  type Background, type Border, type CampaignDetail, type CampaignLanguage, type CampaignRow, type CampaignType, type Design, type Item, type Preview, type Row, type Segment,
  type SenderDomain, type Template,
} from '@/lib/data/campaigns-shared'
import { createCampaign, deleteTemplate, previewCampaign, restoreTemplate, saveCampaign, saveTemplate, scheduleCampaign, testSendCampaign } from '../actions'
import { Canvas, type Brand } from './Canvas'
import { card, danger, dark, ghost, label, primary, small } from './bits'
import { useErr, useGo } from './hooks'
import type { Can } from './CampaignsView'

type Coupon = { code: string; description: string | null; percent: number | null; months: number | null }
type Product = { key: string; name: string; color: string }
type Person = { id: string; name: string; email: string | null }
type Version = { version: number; subject: string; created_at: string; by: string | null }

export type BuilderProps = {
  campaign: CampaignDetail | null
  template: Template | null
  templates: Template[]
  campaigns: CampaignRow[]
  segments: Segment[]
  domains: SenderDomain[]
  providerConnected: boolean
  coupons: Coupon[]
  /** the open template's saved versions, newest first (null when none is open or they could not be read) */
  versions: Version[] | null
  people: Person[]
  products: Product[]
  can: Can
  nf: NumberFormat
}

const box = 'rounded-18 border border-line bg-surface'
const eyebrow = 'text-10.5 font-bold uppercase tracking-label text-muted'
const field = 'h-[30px] rounded-8 border border-line bg-canvas px-2 text-12 text-ink'
const row = 'flex items-center justify-between gap-2 text-12'

/** Email builder (Marketing.dc.html, v.builder): palette and layouts, the canvas, row properties and the campaign's fields. */
export function BuilderView(p: BuilderProps) {
  if (p.template) return <Editor key={`t:${p.template.id}:${p.template.version}`} {...p} mode="template" />
  if (p.campaign) return <Editor key={`c:${p.campaign.id}:${p.campaign.version}`} {...p} mode="campaign" />
  return <Chooser {...p} />
}

// ---------------------------------------------------------------------------
// no campaign chosen: the drafts to open, and «Start from» begins a new campaign (CMP-02)
function Chooser(p: BuilderProps) {
  const t = useTranslations('campaigns')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [from, setFrom] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [type, setType] = useState<CampaignType>('newsletter')
  const [busy, start] = useTransition()
  const drafts = p.campaigns.filter((c) => c.status === 'draft')
  const create = () => start(async () => {
    if (!from) return
    const r = await createCampaign({ name: name.trim(), type, template_id: from !== 'blank' && from !== 'html' ? from : null, html: from === 'html' ? HTML_STARTER : null })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('list.created'))
    router.push(`/campaigns?tab=builder&campaign=${r.id}` as Route)
  })
  const fromName = from === 'blank' ? t('builder.blank') : from === 'html' ? t('builder.ownHtml') : p.templates.find((x) => x.id === from)?.name
  return (
    <div className="grid grid-cols-1 items-start gap-3 lg:[grid-template-columns:190px_minmax(0,1fr)_270px]">
      <StartFrom templates={p.templates} can={p.can} onPick={p.can.add ? setFrom : null} />
      <div className={`${box} flex flex-col gap-2 p-[18px]`}>
        <b className="text-14">{t('builder.chooseTitle')}</b>
        <span className="text-12.5 text-muted">{t(p.can.add ? 'builder.chooseBody' : 'builder.chooseBodyReadOnly')}</span>
        {drafts.map((c) => (
          <Link key={c.id} href={`/campaigns?tab=builder&campaign=${c.id}` as Route} className="flex items-center justify-between gap-2 rounded-10 border border-line bg-canvas px-3 py-2 text-12.5 text-ink hover:text-ink hover:no-underline">
            <b>{c.name}</b><span className="text-11.5 text-muted">{t(`types.${c.type}`)}{c.owner ? ` · ${c.owner}` : ''}</span>
          </Link>
        ))}
        {drafts.length === 0 ? <span className="text-12 text-faint">{t('builder.noDrafts')}</span> : null}
        {from ? (
          <div className="mt-2 flex flex-wrap items-end gap-2 border-0 border-t border-solid border-line pt-3">
            <span className="w-full text-12 text-muted">{t('builder.newFrom', { name: fromName ?? '' })}</span>
            <label className={`${label} min-w-[180px] flex-1`}>{t('new.name')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={small} autoFocus /></label>
            <label className={label}>{t('new.type')}
              <select value={type} onChange={(e) => setType(e.target.value as CampaignType)} className={small}>
                {CAMPAIGN_TYPES.map((k) => <option key={k} value={k}>{t(`types.${k}`)}</option>)}
              </select>
            </label>
            <button type="button" disabled={busy || !name.trim()} onClick={create} className={primary}>{t('new.create')}</button>
            <button type="button" onClick={() => setFrom(null)} className={ghost}>{t('common.cancel')}</button>
          </div>
        ) : null}
      </div>
      <div className={`${box} p-[14px] text-12 text-muted`}>{t('builder.noSelection')}</div>
    </div>
  )
}

function StartFrom({ templates, can, onPick, current }: { templates: Template[]; can: Can; onPick: ((id: string) => void) | null; current?: string | null }) {
  const t = useTranslations('campaigns')
  const items: { id: string; name: string; edit?: string; v?: number }[] = [
    { id: 'blank', name: t('builder.blank') },
    ...templates.map((x) => ({
      id: x.id, name: x.layout ? x.name : t('builder.saved', { name: x.name }), v: x.current_version,
      edit: (x.layout ? can.configure : x.mine ? can.add : can.editOthers) ? x.id : undefined,
    })),
    { id: 'html', name: t('builder.ownHtml') },
  ]
  return (
    <div className={`${box} flex flex-col gap-[6px] p-3`}>
      <span className={`${eyebrow} mt-[2px]`}>{t('builder.startFrom')}</span>
      {items.map((x) => (
        <div key={x.id} className="flex items-stretch gap-1">
          <button
            type="button"
            disabled={!onPick}
            onClick={() => onPick?.(x.id)}
            aria-current={current === x.id ? 'true' : undefined}
            className={`min-w-0 flex-1 rounded-10 border border-dashed px-[9px] py-[7px] text-left text-12 ${current === x.id ? 'border-ink bg-highlight' : 'border-line-strong bg-transparent'} ${onPick ? 'cursor-pointer' : 'cursor-default'}`}
          >
            {x.name}{x.v && x.v > 1 ? <span className="text-faint"> · v{x.v}</span> : null}
          </button>
          {x.edit ? (
            <Link href={`/campaigns?tab=builder&template=${x.edit}` as Route} title={t('builder.editTemplate')} aria-label={t('builder.editTemplate')}
              className="flex w-[26px] items-center justify-center rounded-10 border border-line text-12 text-muted hover:text-ink hover:no-underline">✎</Link>
          ) : null}
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
type Form = {
  name: string; type: CampaignType; segment_id: string | null; sender_domain_id: string | null; subject_a: string; subject_b: string; preheader: string
  ab_percent: number; ab_metric: 'opens' | 'clicks'; ab_wait_hours: number; coupon_code: string | null
  utm_source: string; utm_medium: string; utm_campaign: string; tracking: boolean; notify_owners: boolean
  scope: 'private' | 'shared'; category: string; language: CampaignLanguage
}

function initial(p: BuilderProps, mode: 'campaign' | 'template'): { form: Form; design: Design; html: string | null } {
  const c = p.campaign
  const tp = p.template
  if (mode === 'template' && tp) {
    return {
      form: {
        name: tp.name, type: 'newsletter', segment_id: null, sender_domain_id: null, subject_a: tp.subject ?? '', subject_b: '', preheader: '', ab_percent: 20, ab_metric: 'clicks',
        ab_wait_hours: 4, coupon_code: null, utm_source: '', utm_medium: '', utm_campaign: '', tracking: true, notify_owners: false,
        scope: tp.scope === 'shared' ? 'shared' : 'private', category: tp.category ?? '', language: 'nb',
      },
      design: tp.design ?? BLANK_DESIGN, html: tp.html,
    }
  }
  return {
    form: {
      name: c!.name, type: c!.type, segment_id: c!.segment?.id ?? null, sender_domain_id: c!.sender_domain_id, subject_a: c!.subject_a, subject_b: c!.subject_b ?? '',
      preheader: c!.preheader ?? '', ab_percent: c!.ab?.percent ?? 20, ab_metric: c!.ab?.metric === 'opens' ? 'opens' : 'clicks', ab_wait_hours: c!.ab?.wait_hours ?? 4,
      coupon_code: c!.coupon_code, utm_source: c!.utm.source, utm_medium: c!.utm.medium, utm_campaign: c!.utm.campaign, tracking: c!.tracking,
      notify_owners: c!.notify_owners, scope: 'private', category: '', language: c!.language,
    },
    design: c!.design.rows.length ? c!.design : BLANK_DESIGN, html: c!.html,
  }
}

function Editor(p: BuilderProps & { mode: 'campaign' | 'template' }) {
  const t = useTranslations('campaigns')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const { go } = useGo()
  const c = p.campaign
  const tp = p.template
  const [init] = useState(() => initial(p, p.mode))
  const [form, setForm] = useState<Form>(init.form)
  const [design, setDesign] = useState<Design>(init.design)
  const [html, setHtml] = useState<string | null>(init.html)
  const [templateId, setTemplateId] = useState<string | null>(null)
  const [sel, setSel] = useState(1)
  const [device, setDevice] = useState<'desktop' | 'mobile'>('desktop')
  const [panel, setPanel] = useState<'none' | 'preview' | 'schedule' | 'saveAs'>('none')
  const [busy, start] = useTransition()

  const editable = p.mode === 'template'
    ? (tp!.layout ? p.can.configure : tp!.mine ? p.can.add : p.can.editOthers)
    : c!.status === 'draft' && canEdit(c!, p.can)
  const dirty = JSON.stringify([form, design, html]) !== JSON.stringify([init.form, init.design, init.html]) || templateId !== null
  const width = device === 'mobile' ? 360 : 600
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }))

  const domain = p.domains.find((d) => d.id === form.sender_domain_id) ?? null
  const marketingDomains = p.domains.filter((d) => d.stream === 'marketing' && d.sends_here)
  const product = p.products.find((x) => x.key === c?.product) ?? null
  const brand: Brand = { name: product?.name ?? domain?.from_name ?? '', color: product?.color ?? null, mark: (product?.key ?? '') === 'orgpuls' || (!product && /orgpuls/i.test(domain?.from_name ?? '')) }
  const segment = p.segments.find((s) => s.id === form.segment_id) ?? null
  const automated = form.type === 'automated'

  // the one renderer, with what the builder holds now
  const renderNow = () => renderEmail({
    design: html !== null ? null : design, html, preheader: form.preheader,
    sender: { name: domain?.from_name ?? brand.name, postalAddress: domain?.postal_address ?? null }, brand: brand.name || (domain?.from_name ?? ''),
    utm: p.mode === 'campaign' ? { source: form.utm_source, medium: form.utm_medium, campaign: form.utm_campaign } : null,
    lang: form.language,
  })

  const values = () => {
    const v: Record<string, unknown> = {
      name: form.name.trim(), type: form.type, segment_id: form.segment_id, sender_domain_id: form.sender_domain_id, subject_a: form.subject_a,
      subject_b: automated ? null : form.subject_b.trim() || null, preheader: form.preheader.trim() || null,
      coupon_code: form.type === 'promotion' ? form.coupon_code : null, utm_source: form.utm_source, utm_medium: form.utm_medium, utm_campaign: form.utm_campaign,
      tracking: form.tracking, notify_owners: form.notify_owners, language: form.language,
    }
    if (!automated && form.subject_b.trim()) Object.assign(v, { ab_percent: form.ab_percent, ab_metric: form.ab_metric, ab_wait_hours: form.ab_wait_hours })
    if (html !== null) v.html = html
    else v.design = design
    if (templateId) v.template_id = templateId
    return v
  }

  /** Saves what is shown; answers the new version, or null after telling why it was refused. */
  const save = async (): Promise<number | null> => {
    if (p.mode === 'template') {
      const r = await saveTemplate({
        id: tp!.id, version: tp!.version,
        values: { name: form.name.trim(), scope: form.scope, category: form.category.trim() || null, subject: form.subject_a, ...(html !== null ? { html } : { design }) },
      })
      if (!r.ok) { flash(err(r.code, r.detail)); return null }
      flash(t('builder.templateSaved', { v: r.current }))
      router.refresh()
      return r.version
    }
    if (!dirty) return c!.version
    const r = await saveCampaign({ id: c!.id, version: c!.version, values: values() as never })
    if (!r.ok) { flash(err(r.code, r.detail)); return null }
    return r.version
  }

  const onSave = () => start(async () => {
    const v = await save()
    if (v !== null && p.mode === 'campaign') { flash(t('builder.draftSaved')); router.refresh() }
  })
  const onTest = () => start(async () => {
    if ((await save()) === null) return
    const r = await testSendCampaign({ id: c!.id, person: previewPerson })
    if (!r.ok) { flash(r.code === 'not_connected' ? t('builder.testNotConnected') : err(r.code, r.detail)); router.refresh(); return }
    flash(t('builder.testSent', { to: r.to }))
    router.refresh()
  })

  // preview: rendered here, merged by the database (a draft's unsaved rows included)
  const [previewPerson, setPreviewPerson] = useState<string | null>(null)
  const [preview, setPreview] = useState<Preview | null>(null)
  const [localPreview, setLocalPreview] = useState<string | null>(null)
  const loadPreview = (person: string | null) => start(async () => {
    if (p.mode === 'template') { setLocalPreview(renderNow()); return }
    const r = await previewCampaign({ id: c!.id, person, draft: c!.status === 'draft' ? { design: html !== null ? null : design, html, preheader: form.preheader || null, sender_domain_id: form.sender_domain_id, language: form.language } : null })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    setPreview(r.preview)
  })
  useEffect(() => {
    if (panel === 'preview' || panel === 'schedule') loadPreview(panel === 'preview' ? previewPerson : null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [panel, previewPerson])

  const applyStart = (id: string) => {
    if (!editable) return
    if (id === 'blank') { setDesign(BLANK_DESIGN); setHtml(null); setTemplateId(null); setSel(0); return }
    if (id === 'html') { setHtml(html ?? HTML_STARTER); setTemplateId(null); return }
    const x = p.templates.find((y) => y.id === id)
    if (!x) return
    if (x.html) { setHtml(x.html) } else { setHtml(null); setDesign(x.design ?? BLANK_DESIGN) }
    if (p.mode === 'campaign') { setTemplateId(x.id); if (!form.subject_a && x.subject) set('subject_a', x.subject) }
    setSel(1)
  }

  const r = design.rows[sel] ?? design.rows[0]
  const readOnlyFrozen = p.mode === 'campaign' && c!.status !== 'draft'

  return (
    <div className="grid grid-cols-1 items-start gap-3 lg:[grid-template-columns:190px_minmax(0,1fr)_270px]">
      <div className="flex flex-col gap-3">
        <div className={`${box} flex flex-col gap-[6px] p-3`}>
          <span className={eyebrow}>{t('builder.blocks')}</span>
          {PALETTE.map((b) => (
            <button
              key={b.kind}
              type="button"
              disabled={!editable || html !== null}
              onClick={() => { const a = addRow(design, b.kind); setDesign(a.design); setSel(a.index) }}
              className="flex cursor-pointer items-center gap-2 rounded-10 border border-line bg-canvas px-[9px] py-[7px] text-left text-12.5 text-ink disabled:cursor-default disabled:opacity-50"
            >
              <span className="w-[18px] text-center">{b.glyph}</span>{t(`kinds.${b.kind}`)}
            </button>
          ))}
        </div>
        <StartFrom templates={p.templates.filter((x) => x.id !== tp?.id)} can={p.can} onPick={editable ? applyStart : null} current={templateId} />
      </div>

      <div className="flex min-w-0 flex-col items-center gap-[10px]">
        <div className="flex w-full flex-wrap items-center gap-2">
          <div className="flex rounded-10 bg-tile p-[3px]">
            {(['desktop', 'mobile'] as const).map((d) => (
              <button key={d} type="button" aria-pressed={device === d} onClick={() => setDevice(d)}
                className={`cursor-pointer rounded-7 border-none px-3 py-[6px] text-12 ${device === d ? 'bg-surface font-bold' : 'bg-transparent font-medium'}`}>
                {t(`builder.device.${d}`)}
              </button>
            ))}
          </div>
          <span className="flex-1" />
          <button type="button" onClick={() => setPanel(panel === 'preview' ? 'none' : 'preview')} aria-pressed={panel === 'preview'} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold">
            {t(panel === 'preview' ? 'builder.closePreview' : 'builder.preview')}
          </button>
          {editable ? (
            <button type="button" disabled={busy || !dirty} onClick={onSave} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold disabled:cursor-default disabled:opacity-50">
              {t(p.mode === 'template' ? 'builder.saveTemplate' : 'builder.save')}
            </button>
          ) : null}
          {p.mode === 'campaign' ? (
            <>
              <button type="button" disabled={busy || !canEdit(c!, p.can)} onClick={onTest} className="h-8 cursor-pointer rounded-9 border border-line bg-transparent px-3 text-12 font-semibold disabled:cursor-default disabled:opacity-50">{t('builder.sendTest')}</button>
              {editable ? (
                <button type="button" disabled={busy} onClick={() => setPanel(panel === 'schedule' ? 'none' : 'schedule')} aria-pressed={panel === 'schedule'} className="h-8 cursor-pointer rounded-9 border border-ink bg-primary px-[13px] text-12 font-bold">
                  {t(automated ? 'builder.activate' : 'builder.schedule')}
                </button>
              ) : null}
            </>
          ) : null}
        </div>
        <StatusLine {...p} dirty={dirty} editable={editable} />
        {panel === 'schedule' && c ? (
          <SchedulePanel c={c} form={form} segment={segment} domain={domain} providerConnected={p.providerConnected} preview={preview} html={html !== null ? renderNow() : null}
            nf={p.nf} busy={busy} onClose={() => setPanel('none')}
            onConfirm={(at) => start(async () => {
              const v = await save()
              if (v === null) return
              const r = await scheduleCampaign({ id: c.id, version: v, at })
              if (!r.ok) { flash(err(r.code, r.detail)); router.refresh(); return }
              flash(t(r.status === 'active' ? 'builder.activated' : 'builder.scheduled'))
              go({ tab: null, campaign: c.id })
            })}
          />
        ) : null}
        {panel === 'preview' ? (
          <div className="flex w-full flex-col items-center gap-2">
            {p.mode === 'campaign' ? (
              <div className="flex w-full flex-wrap items-center gap-2 text-12">
                <label className="flex items-center gap-2 text-muted">{t('builder.mergeWith')}
                  <select value={previewPerson ?? ''} onChange={(e) => setPreviewPerson(e.target.value || null)} className={field}>
                    <option value="">{t('builder.nobody')}</option>
                    {p.people.map((x) => <option key={x.id} value={x.id}>{x.name}{x.email ? ` · ${x.email}` : ''}</option>)}
                  </select>
                </label>
                {preview ? <span className="text-muted">{t('builder.subjectLine', { subject: preview.subject_a || '—' })}{preview.subject_b ? ` · B: ${preview.subject_b}` : ''}</span> : null}
              </div>
            ) : null}
            {preview && (preview.missing.length || preview.unknown.length) ? (
              <div className="w-full text-12 text-muted">
                {preview.missing.length ? t('builder.missing', { list: preview.missing.map((x) => `[${x}]`).join(' ') }) : null}
                {preview.unknown.length ? <span className="text-danger"> {t('builder.unknown', { list: preview.unknown.map((x) => `[${x}]`).join(' ') })}</span> : null}
              </div>
            ) : null}
            <iframe
              title={t('builder.preview')}
              sandbox=""
              srcDoc={(p.mode === 'template' ? localPreview : preview?.html) ?? ''}
              className="max-w-full rounded-14 border border-line bg-surface"
              style={{ width, height: 720 }}
            />
          </div>
        ) : readOnlyFrozen ? (
          <iframe title={t('builder.frozen')} sandbox="" srcDoc={c!.rendered_html ?? ''} className="max-w-full rounded-14 border border-line bg-surface" style={{ width, height: 720 }} />
        ) : html !== null ? (
          <HtmlEditor html={html} onChange={setHtml} editable={editable} width={width} postal={domain?.postal_address ?? null} isTemplate={p.mode === 'template'} />
        ) : (
          <Canvas design={design} selected={sel} onPick={setSel} width={width} brand={brand} readOnly={!editable}
            footer={{ address: domain?.postal_address ?? null, sender: domain?.from_name ?? brand.name, stream: domain?.stream ?? (p.mode === 'campaign' ? null : 'marketing'), lang: form.language }} />
        )}
      </div>

      <div className="flex flex-col gap-3">
        {html === null && r && !readOnlyFrozen ? (
          <RowPanel r={r} index={sel} count={design.rows.length} editable={editable}
            onPatch={(patch) => setDesign((d) => patchRow(d, sel, patch))}
            onMove={(dir) => { const m = moveRow(design, sel, dir); setDesign(m.design); setSel(m.index) }}
            onRemove={() => { const m = removeRow(design, sel); setDesign(m.design); setSel(m.index) }}>
            {p.mode === 'campaign' ? (
              <CampaignFields {...p} form={form} set={set} editable={editable} segment={segment} domains={marketingDomains} domain={domain} />
            ) : <TemplateFields tp={tp!} form={form} set={set} editable={editable} fmt={fmt} />}
          </RowPanel>
        ) : (
          <div className="flex flex-col gap-[9px] rounded-18 border border-ink bg-surface p-[14px]">
            <span className={eyebrow}>{t(readOnlyFrozen ? 'builder.frozenTitle' : 'builder.htmlTitle')}</span>
            {readOnlyFrozen ? <span className="text-12 text-muted">{t('builder.frozenBody')}</span> : null}
            {p.mode === 'campaign' ? (
              <CampaignFields {...p} form={form} set={set} editable={editable} segment={segment} domains={marketingDomains} domain={domain} />
            ) : <TemplateFields tp={tp!} form={form} set={set} editable={editable} fmt={fmt} />}
          </div>
        )}
        {p.mode === 'campaign' && p.can.add ? (
          <SaveAs open={panel === 'saveAs'} onToggle={() => setPanel(panel === 'saveAs' ? 'none' : 'saveAs')} subject={form.subject_a} design={design} html={html} />
        ) : null}
        {p.mode === 'template' && p.versions ? <Versions tp={tp!} versions={p.versions} editable={editable} busy={busy} /> : null}
        {p.mode === 'template' && editable && p.can.del ? (
          <DeleteTemplate id={tp!.id} />
        ) : null}
      </div>
    </div>
  )
}

function StatusLine(p: BuilderProps & { dirty: boolean; editable: boolean }) {
  const t = useTranslations('campaigns')
  const fmt = useFormatter()
  const parts: string[] = []
  if (p.template) {
    parts.push(t('builder.editingTemplate', { name: p.template.name, v: p.template.current_version }))
    parts.push(t('builder.savedAt', { at: fmt.dateTime(new Date(p.template.updated_at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }))
  } else if (p.campaign) {
    parts.push(t('builder.editingCampaign', { name: p.campaign.name, status: t(`status.${p.campaign.status}`) }))
  }
  if (!p.editable) parts.push(t('builder.readOnly'))
  return (
    <div className="flex w-full flex-wrap items-center gap-2 text-11.5 text-muted">
      <span>{parts.join(' · ')}</span>
      {p.dirty ? <span className="rounded-999 bg-highlight px-2 py-[1px] font-bold text-amber-ink">{t('builder.unsaved')}</span> : null}
      {p.template ? <Link href={'/campaigns?tab=builder' as Route} className="ml-auto text-11.5">{t('builder.backToCampaigns')}</Link> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
// the selected row's properties (the design's right panel); the footer keeps only its background (D-27)
function RowPanel({ r, index, count, editable, onPatch, onMove, onRemove, children }: {
  r: Row; index: number; count: number; editable: boolean; onPatch: (p: Partial<Row>) => void; onMove: (d: -1 | 1) => void; onRemove: () => void; children: React.ReactNode
}) {
  const t = useTranslations('campaigns.builder')
  const tk = useTranslations('campaigns.kinds')
  const fixed = isFixed(r)
  const dis = !editable
  const itemsText = (xs: Item[] | undefined, links: boolean) => (xs ?? []).map((x) => (links && itemHref(x) ? `${itemLabel(x)} | ${itemHref(x)}` : itemLabel(x))).join('\n')
  const parseItems = (s: string, links: boolean): Item[] => s.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
    if (!links) return l
    const [lab, href] = l.split('|').map((x) => x.trim())
    return href ? { label: lab ?? '', href } : { label: lab ?? '' }
  })
  const [itemsDraft, setItemsDraft] = useState<string>(itemsText(r.items, r.kind !== 'list'))
  useEffect(() => { setItemsDraft(itemsText(r.items, r.kind !== 'list')) }, [index, r.kind]) // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className="flex flex-col gap-[9px] rounded-18 border border-ink bg-surface p-[14px]">
      <span className={eyebrow}>{t('rowProps', { kind: tk(r.kind) })}</span>
      {fixed ? <span className="text-12 text-muted">{t('footerFixed')}</span> : null}
      {['title', 'paragraph', 'header'].includes(r.kind) ? (
        <textarea value={r.text ?? ''} disabled={dis} onChange={(e) => onPatch({ text: e.target.value })} maxLength={5000} aria-label={t('text')}
          placeholder={r.kind === 'header' ? t('headerPlaceholder') : undefined}
          className="min-h-[80px] rounded-10 border border-line bg-canvas p-[9px] font-sans text-12.5 text-ink" />
      ) : null}
      {['button', 'video'].includes(r.kind) ? (
        <label className={label}>{t(r.kind === 'button' ? 'buttonText' : 'videoText')}<input value={r.text ?? ''} disabled={dis} onChange={(e) => onPatch({ text: e.target.value })} maxLength={200} className={field} /></label>
      ) : null}
      {r.kind === 'title' ? (
        <label className={row}>{t('size')}
          <select value={r.fs ?? 22} disabled={dis} onChange={(e) => onPatch({ fs: Number(e.target.value) })} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
            {[18, 22, 26, 32, 40].map((x) => <option key={x} value={x}>{x} px</option>)}
          </select>
        </label>
      ) : null}
      {['image', 'video'].includes(r.kind) ? (
        <label className={label}>{t(r.kind === 'image' ? 'src' : 'thumb')}<input value={r.src ?? ''} disabled={dis} onChange={(e) => onPatch({ src: e.target.value })} placeholder="https://" maxLength={2000} className={field} /></label>
      ) : null}
      {r.kind === 'image' ? (
        <>
          <label className={label}>{t('alt')}<input value={r.alt ?? ''} disabled={dis} onChange={(e) => onPatch({ alt: e.target.value })} maxLength={300} className={field} /></label>
          <span className="text-11 text-faint">{t('noUpload')}</span>
        </>
      ) : null}
      {['button', 'image', 'video'].includes(r.kind) ? (
        <label className={label}>{t('href')}<input value={r.href ?? ''} disabled={dis} onChange={(e) => onPatch({ href: e.target.value })} placeholder="https://" maxLength={2000} className={field} /></label>
      ) : null}
      {['list', 'social', 'menu', 'icons'].includes(r.kind) ? (
        <label className={label}>{t(r.kind === 'list' ? 'listItems' : 'linkItems')}
          <textarea value={itemsDraft} disabled={dis} onChange={(e) => { setItemsDraft(e.target.value); onPatch({ items: parseItems(e.target.value, r.kind !== 'list') }) }}
            className="min-h-[80px] rounded-10 border border-line bg-canvas p-[9px] font-sans text-12.5 text-ink" />
        </label>
      ) : null}
      {r.kind === 'html' ? (
        <label className={label}>{t('htmlBlock')}
          <textarea value={r.html ?? ''} disabled={dis} onChange={(e) => onPatch({ html: e.target.value })} maxLength={100000} spellCheck={false}
            className="min-h-[120px] rounded-10 border border-line bg-ink p-[9px] font-mono text-11.5 text-tile" />
          <span className="text-11 text-faint">{t('htmlSanitized')}</span>
        </label>
      ) : null}
      <label className={row}>{t('background')}
        <select value={r.bg ?? (fixed ? 'cream' : 'card')} disabled={dis} onChange={(e) => onPatch({ bg: e.target.value as Background })} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
          {BACKGROUNDS.map((b) => <option key={b} value={b}>{t(`bg.${b}`)}</option>)}
        </select>
      </label>
      <label className={row}>{t('padding')}
        <select value={r.padding ?? 22} disabled={dis || fixed} onChange={(e) => onPatch({ padding: Number(e.target.value) })} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
          {PADDINGS.map((x) => <option key={x} value={x}>{x} px</option>)}
        </select>
      </label>
      <label className={row}>{t('border')}
        <select value={r.border ?? 'none'} disabled={dis || fixed} onChange={(e) => onPatch({ border: e.target.value as Border })} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
          <option value="none">{t('borderNone')}</option><option value="hairline">{t('borderHairline')}</option>
        </select>
      </label>
      <div className="flex gap-[6px]">
        <button type="button" disabled={dis || fixed || index === 0} onClick={() => onMove(-1)} className="h-[30px] flex-1 cursor-pointer rounded-9 border border-line bg-transparent text-12 disabled:cursor-default disabled:opacity-50">↑ {t('move')}</button>
        <button type="button" disabled={dis || fixed || index >= count - 2} onClick={() => onMove(1)} className="h-[30px] flex-1 cursor-pointer rounded-9 border border-line bg-transparent text-12 disabled:cursor-default disabled:opacity-50">↓ {t('move')}</button>
        <button type="button" disabled={dis || fixed} onClick={onRemove} className="h-[30px] flex-1 cursor-pointer rounded-9 border border-coral bg-transparent text-12 text-rust disabled:cursor-default disabled:opacity-50">{t('remove')}</button>
      </div>
      <div className="flex flex-col gap-[7px] border-0 border-t border-solid border-line pt-[9px] text-12">{children}</div>
    </div>
  )
}

function HtmlEditor({ html, onChange, editable, width, postal, isTemplate }: { html: string; onChange: (s: string) => void; editable: boolean; width: number; postal: string | null; isTemplate: boolean }) {
  const t = useTranslations('campaigns.builder')
  const problems = footerProblems(html, postal).filter((x) => !(isTemplate && x === 'address'))
  return (
    <div className="flex max-w-full flex-col gap-2" style={{ width }}>
      <textarea value={html} disabled={!editable} onChange={(e) => onChange(e.target.value)} spellCheck={false} aria-label={t('ownHtmlLabel')}
        className="min-h-[420px] w-full rounded-14 border border-line bg-ink p-3 font-mono text-11.5 leading-[1.5] text-tile" />
      {problems.length ? (
        <div className="text-12 text-danger">{problems.map((x) => (x === 'unsubscribe' ? t('needsUnsubscribe') : postal ? t('needsAddress', { address: postal }) : t('needsDomainAddress'))).join(' · ')}</div>
      ) : <div className="text-12 text-muted">{t('htmlOk')}</div>}
    </div>
  )
}

// ---------------------------------------------------------------------------
function CampaignFields(p: BuilderProps & { form: Form; set: <K extends keyof Form>(k: K, v: Form[K]) => void; editable: boolean; segment: Segment | null; domains: SenderDomain[]; domain: SenderDomain | null }) {
  const t = useTranslations('campaigns')
  const { form, set, editable: ed } = p
  const c = p.campaign!
  const [utmOpen, setUtmOpen] = useState(false)
  const automated = form.type === 'automated'
  const trackingForced = c.tracking_rule === 'on' || c.tracking_rule === 'off'
  const coupon = p.coupons.find((x) => x.code === form.coupon_code) ?? null
  // a coupon's terms as the register holds them: only the parts it has
  const couponTerms = (x: Coupon) => [x.description, x.percent !== null ? t('fields.couponPercent', { n: formatNumber(x.percent, p.nf, Number.isInteger(x.percent) ? 0 : 2) }) : null,
    x.months !== null ? t('fields.couponMonths', { n: x.months }) : null].filter(Boolean).join(' · ')
  return (
    <>
      <label className={label}>{t('fields.name')}<input value={form.name} disabled={!ed} onChange={(e) => set('name', e.target.value)} maxLength={120} className={field} /></label>
      <label className={row}>{t('fields.type')}
        <select value={form.type} disabled={!ed} onChange={(e) => set('type', e.target.value as CampaignType)} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
          {CAMPAIGN_TYPES.map((k) => <option key={k} value={k}>{t(`types.${k}`)}</option>)}
        </select>
      </label>
      {automated ? (
        <span className="text-muted">{c.audience.kind === 'workflow' && c.audience.workflows.length ? t('list.viaWorkflow', { names: c.audience.workflows.map((w) => w.name).join(', ') }) : t('fields.automatedAudience')}</span>
      ) : (
        <label className={label}>{t('fields.audience')}
          <select value={form.segment_id ?? ''} disabled={!ed} onChange={(e) => set('segment_id', e.target.value || null)} className={field}>
            <option value="">{t('fields.noSegment')}</option>
            {p.segments.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          {p.segment ? <span className="text-11.5">{t('fields.receivable', { n: formatNumber(p.segment.receivable, p.nf), m: formatNumber(p.segment.matches, p.nf) })}</span> : null}
        </label>
      )}
      <label className={label}>{t('fields.sender')}
        <select value={form.sender_domain_id ?? ''} disabled={!ed} onChange={(e) => set('sender_domain_id', e.target.value || null)} className={field}>
          <option value="">{t('fields.noSender')}</option>
          {p.domains.map((d) => <option key={d.id} value={d.id}>{d.from_local}@{d.domain}</option>)}
        </select>
        {p.domain ? (
          <span className={`text-11.5 ${p.domain.authenticated ? 'text-muted' : 'text-danger'}`}>
            {p.domain.authenticated ? (p.domain.verified ? t('fields.domainVerified') : t('fields.domainAuthenticated')) : t('fields.domainUnchecked')}
            {!p.domain.postal_address ? ` · ${t('fields.noPostal')}` : ''}
          </span>
        ) : p.domains.length === 0 ? <span className="text-11.5">{t('fields.noDomains')}</span> : null}
      </label>
      <label className={row}>{t('fields.language')}
        <select value={form.language} disabled={!ed} onChange={(e) => set('language', e.target.value as CampaignLanguage)} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
          {CAMPAIGN_LANGUAGES.map((k) => <option key={k} value={k}>{t(`languages.${k}`)}</option>)}
        </select>
      </label>
      <label className={label}>{t('fields.subjectA')}<input value={form.subject_a} disabled={!ed} onChange={(e) => set('subject_a', e.target.value)} maxLength={200} className={field} /></label>
      {!automated ? (
        <label className={label}>{t('fields.subjectB')}<input value={form.subject_b} disabled={!ed} onChange={(e) => set('subject_b', e.target.value)} maxLength={200} className={field} /></label>
      ) : <span className="text-11.5 text-faint">{t('fields.noAbAutomated')}</span>}
      {!automated && form.subject_b.trim() ? (
        <div className="flex flex-wrap gap-2">
          <label className={label}>{t('fields.abPercent')}<input type="number" min={2} max={50} value={form.ab_percent} disabled={!ed} onChange={(e) => set('ab_percent', Number(e.target.value))} className={`${field} w-[64px]`} /></label>
          <label className={label}>{t('fields.abMetric')}
            <select value={form.ab_metric} disabled={!ed} onChange={(e) => set('ab_metric', e.target.value as 'opens' | 'clicks')} className={field}>
              <option value="clicks">{t('card.abMetric.clicks')}</option><option value="opens">{t('card.abMetric.opens')}</option>
            </select>
          </label>
          <label className={label}>{t('fields.abWait')}<input type="number" min={1} max={72} value={form.ab_wait_hours} disabled={!ed} onChange={(e) => set('ab_wait_hours', Number(e.target.value))} className={`${field} w-[64px]`} /></label>
        </div>
      ) : null}
      <label className={label}>{t('fields.preheader')}<input value={form.preheader} disabled={!ed} onChange={(e) => set('preheader', e.target.value)} maxLength={200} className={field} /></label>
      {form.type === 'promotion' ? (
        <label className={row}>{t('fields.coupon')}
          <select value={form.coupon_code ?? ''} disabled={!ed} onChange={(e) => set('coupon_code', e.target.value || null)} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
            <option value="">{t('fields.none')}</option>
            {form.coupon_code && !p.coupons.some((x) => x.code === form.coupon_code) ? <option value={form.coupon_code}>{form.coupon_code}</option> : null}
            {p.coupons.map((x) => <option key={x.code} value={x.code}>{x.code}</option>)}
          </select>
        </label>
      ) : null}
      {form.type === 'promotion' && coupon ? <span className="text-11.5 text-muted">{couponTerms(coupon)}</span> : null}
      {form.type === 'promotion' && p.coupons.length === 0 ? <span className="text-11.5 text-faint">{t('fields.noCoupons')}</span> : null}
      <span className="text-muted">
        UTM: utm_source={form.utm_source} · utm_campaign={form.utm_campaign}
        {ed ? <button type="button" onClick={() => setUtmOpen((x) => !x)} className="ml-1 cursor-pointer border-none bg-transparent p-0 text-12 text-link underline">{t('fields.edit')}</button> : null}
      </span>
      {utmOpen ? (
        <div className="flex flex-col gap-[6px]">
          {(['utm_source', 'utm_medium', 'utm_campaign'] as const).map((k) => (
            <label key={k} className={label}>{k}<input value={form[k]} onChange={(e) => set(k, e.target.value.toLowerCase())} maxLength={60} pattern="[a-z0-9_-]+" className={field} /></label>
          ))}
        </div>
      ) : null}
      <div className={row}>
        <span>{t('fields.tracking')}</span>
        <Switch on={trackingForced ? c.tracking_rule === 'on' : form.tracking} disabled={!ed || trackingForced} onChange={(v) => set('tracking', v)} label={t('fields.tracking')} />
      </div>
      {trackingForced ? <span className="text-11.5 text-faint">{t(`fields.trackingRule.${c.tracking_rule}`)}</span> : null}
      <label className="flex items-start gap-2 text-12">
        <input type="checkbox" checked={form.notify_owners} disabled={!ed} onChange={(e) => set('notify_owners', e.target.checked)} style={{ accentColor: '#191510', marginTop: 2 }} />
        {t('fields.notifyOwners')}
      </label>
    </>
  )
}

function TemplateFields({ tp, form, set, editable, fmt }: { tp: Template; form: Form; set: <K extends keyof Form>(k: K, v: Form[K]) => void; editable: boolean; fmt: ReturnType<typeof useFormatter> }) {
  const t = useTranslations('campaigns')
  return (
    <>
      <label className={label}>{t('fields.templateName')}<input value={form.name} disabled={!editable} onChange={(e) => set('name', e.target.value)} maxLength={120} className={field} /></label>
      {!tp.layout ? (
        <label className={row}>{t('fields.scope')}
          <select value={form.scope} disabled={!editable} onChange={(e) => set('scope', e.target.value as 'private' | 'shared')} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
            <option value="private">{t('fields.scopePrivate')}</option><option value="shared">{t('fields.scopeShared')}</option>
          </select>
        </label>
      ) : <span className="text-muted">{t('fields.layoutNote')}</span>}
      <label className={label}>{t('fields.category')}<input value={form.category} disabled={!editable} onChange={(e) => set('category', e.target.value)} maxLength={40} className={field} /></label>
      <label className={label}>{t('fields.subjectA')}<input value={form.subject_a} disabled={!editable} onChange={(e) => set('subject_a', e.target.value)} maxLength={500} className={field} /></label>
      <span className="text-muted">{t('fields.version', { v: tp.current_version, at: fmt.dateTime(new Date(tp.updated_at), { day: 'numeric', month: 'short', year: 'numeric' }), by: tp.owner ?? '—' })}</span>
    </>
  )
}

function SaveAs({ open, onToggle, subject, design, html }: { open: boolean; onToggle: () => void; subject: string; design: Design; html: string | null }) {
  const t = useTranslations('campaigns')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [name, setName] = useState('')
  const [scope, setScope] = useState<'private' | 'shared'>('shared')
  const [busy, start] = useTransition()
  const save = () => start(async () => {
    const r = await saveTemplate({ id: null, version: null, values: { name: name.trim(), scope, subject, ...(html !== null ? { html } : { design }) } })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('builder.savedAsTemplate', { name: name.trim() }))
    setName('')
    onToggle()
    router.refresh()
  })
  return (
    <div className={`${box} flex flex-col gap-2 p-[14px] text-12`}>
      <button type="button" onClick={onToggle} className="cursor-pointer border-none bg-transparent p-0 text-left text-12 font-bold text-ink">{t('builder.saveAsTemplate')}</button>
      {open ? (
        <>
          <label className={label}>{t('fields.templateName')}<input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} className={field} autoFocus /></label>
          <label className={row}>{t('fields.scope')}
            <select value={scope} onChange={(e) => setScope(e.target.value as 'private' | 'shared')} className="h-[30px] rounded-8 border border-line bg-canvas text-12">
              <option value="private">{t('fields.scopePrivate')}</option><option value="shared">{t('fields.scopeShared')}</option>
            </select>
          </label>
          <button type="button" disabled={busy || !name.trim()} onClick={save} className={dark}>{t('builder.saveTemplateNew')}</button>
        </>
      ) : null}
    </div>
  )
}

/** A template's saved versions (R-CAMPAIGNS-05): each save is one; restoring saves the chosen one as the next. */
function Versions({ tp, versions, editable, busy: outerBusy }: { tp: Template; versions: Version[]; editable: boolean; busy: boolean }) {
  const t = useTranslations('campaigns')
  const fmt = useFormatter()
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [busy, start] = useTransition()
  const restore = (v: number) => start(async () => {
    const r = await restoreTemplate({ id: tp.id, version: v })
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('builder.versionRestored', { from: v, v: r.current }))
    router.refresh()
  })
  return (
    <div className={`${box} flex flex-col gap-[6px] p-[14px] text-12`}>
      <span className={eyebrow}>{t('builder.versions')}</span>
      {versions.map((x) => (
        <div key={x.version} className="flex items-center justify-between gap-2 border-0 border-b border-solid border-tile py-[3px]">
          <span className="min-w-0">
            <b>v{x.version}</b>
            <span className="text-muted"> · {fmt.dateTime(new Date(x.created_at), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}{x.by ? ` · ${x.by}` : ''}</span>
            {x.subject ? <span className="block overflow-hidden text-ellipsis whitespace-nowrap text-faint">{x.subject}</span> : null}
          </span>
          {x.version === tp.current_version ? <span className="flex-none text-11.5 text-muted">{t('builder.currentVersion')}</span>
            : editable ? (
              <button type="button" disabled={busy || outerBusy} onClick={() => restore(x.version)} className="h-[26px] flex-none cursor-pointer rounded-8 border border-line bg-transparent px-2 text-11.5 font-semibold disabled:cursor-default disabled:opacity-50">
                {t('builder.restore')}
              </button>
            ) : null}
        </div>
      ))}
    </div>
  )
}

function DeleteTemplate({ id }: { id: string }) {
  const t = useTranslations('campaigns')
  const err = useErr()
  const flash = useToast()
  const router = useRouter()
  const [sure, setSure] = useState(false)
  const [busy, start] = useTransition()
  return (
    <div className={`${box} flex flex-wrap items-center gap-2 p-[14px] text-12`}>
      {sure ? <span className="text-muted">{t('builder.deleteTemplateConfirm')}</span> : null}
      <button type="button" disabled={busy} onClick={() => (sure ? start(async () => {
        const r = await deleteTemplate({ id })
        if (!r.ok) { flash(err(r.code, r.detail)); return }
        flash(t('builder.templateDeleted'))
        router.push('/campaigns?tab=builder' as Route)
      }) : setSure(true))} className={danger}>{t('builder.deleteTemplate')}</button>
      {sure ? <button type="button" onClick={() => setSure(false)} className={ghost}>{t('common.cancel')}</button> : null}
    </div>
  )
}

// ---------------------------------------------------------------------------
// schedule (CMP-05): what the database will check, said before it refuses; the provider's absence is a hold, not a refusal
function SchedulePanel({ c, form, segment, domain, providerConnected, preview, html, nf, busy, onClose, onConfirm }: {
  c: CampaignDetail; form: Form; segment: Segment | null; domain: SenderDomain | null; providerConnected: boolean; preview: Preview | null; html: string | null
  nf: NumberFormat; busy: boolean; onClose: () => void; onConfirm: (at: string | null) => void
}) {
  const t = useTranslations('campaigns.schedule')
  const automated = form.type === 'automated'
  const [now, setNow] = useState(true)
  const [at, setAt] = useState(() => { const d = new Date(Date.now() + 3600_000); d.setMinutes(0, 0, 0); return toLocalInput(d) })
  const checks: { ok: boolean; text: string; block: boolean }[] = [
    { ok: form.subject_a.trim() !== '', text: form.subject_a.trim() ? t('subjectOk') : t('subjectMissing'), block: true },
    ...(automated ? [] : [{
      ok: !!segment && segment.receivable > 0,
      text: !segment ? t('audienceMissing') : segment.receivable > 0 ? t('audienceOk', { n: formatNumber(segment.receivable, nf), name: segment.name }) : t('audienceEmpty', { name: segment.name }),
      block: true,
    }]),
    { ok: !!domain?.authenticated, text: !domain ? t('domainMissing') : domain.authenticated ? t('domainOk', { domain: domain.domain }) : t('domainUnchecked', { domain: domain.domain }), block: true },
    { ok: !!domain?.postal_address, text: domain?.postal_address ? t('addressOk') : t('addressMissing'), block: true },
    ...(html !== null ? [{ ok: footerProblems(html, domain?.postal_address ?? null).length === 0, text: footerProblems(html, domain?.postal_address ?? null).length ? t('footerProblem') : t('footerOk'), block: true }] : []),
    ...(!automated && form.subject_b.trim() && c.tracking_rule === 'off' ? [{ ok: false, text: t('abNeedsTracking'), block: true }] : []),
  ]
  const blocked = checks.some((x) => x.block && !x.ok)
  return (
    <div className={`${card} flex w-full flex-col gap-2 px-[18px] py-[14px] text-12.5`}>
      <b className="text-14">{t(automated ? 'titleActivate' : 'title')}</b>
      {checks.map((x, i) => (
        <div key={i} className="flex items-start gap-2"><span className={`w-4 font-bold ${x.ok ? 'text-ok' : 'text-danger'}`}>{x.ok ? '✓' : '!'}</span><span>{x.text}</span></div>
      ))}
      {preview?.audience_missing.map((m) => (
        <div key={m.token} className="flex items-start gap-2"><span className="w-4 font-bold text-warn-ink">!</span><span>{t('mergeMissing', { n: formatNumber(m.people, nf), token: `[${m.token}]` })}</span></div>
      ))}
      {!providerConnected ? <div className="rounded-12 bg-canvas px-[10px] py-2 text-12 text-muted">{t('noProvider')}</div> : null}
      {!automated ? (
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex items-center gap-2"><input type="radio" checked={now} onChange={() => setNow(true)} style={{ accentColor: '#191510' }} />{t('now')}</label>
          <label className="flex items-center gap-2"><input type="radio" checked={!now} onChange={() => setNow(false)} style={{ accentColor: '#191510' }} />{t('at')}</label>
          {!now ? <input type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} className={field} /> : null}
        </div>
      ) : <span className="text-muted">{t('activateNote')}</span>}
      <div className="flex gap-[6px]">
        <button type="button" disabled={busy || blocked || (!now && !at)} onClick={() => onConfirm(automated || now ? null : new Date(at).toISOString())} className={primary}>
          {t(automated ? 'confirmActivate' : 'confirm')}
        </button>
        <button type="button" onClick={onClose} className={ghost}>{t('cancel')}</button>
      </div>
      <span className="text-11.5 text-faint">{t('frozenNote')}</span>
    </div>
  )
}
