'use client'

import { useCallback } from 'react'
import { useTranslations } from 'next-intl'
import type { Base, Pickers } from '@/lib/data/automation'
import { NOT_AVAILABLE, type Step } from '@/lib/data/automation-graph'
import { useWords } from './shared'

/** Fields a condition can test, per record type (app.entity_columns that filter, and the engine's extra tests). */
export const FILTER_FIELDS: Record<string, string[]> = {
  deal: ['title', 'value', 'status', 'source', 'product', 'currency', 'expected_close_date', 'score', 'idle_days', 'labels', 'email.opened', 'email.replied', 'email.no_reply', 'org_products', 'org_payment'],
  lead: ['title', 'value', 'source', 'currency', 'labels', 'email.opened', 'email.replied', 'email.no_reply', 'org_payment'],
  person: ['name', 'email', 'title', 'contact_type', 'source', 'city', 'labels', 'email.opened', 'email.replied', 'email.no_reply'],
  organization: ['name', 'org_number', 'city', 'fylke', 'industry', 'employees', 'source', 'country', 'labels', 'org_products', 'org_payment'],
  activity: ['subject', 'priority', 'done'],
  ticket: ['queue_key', 'urgency', 'product', 'topic'],
}
export const NUMERIC = new Set(['value', 'score', 'employees', 'idle_days', 'org_products', 'email.opened', 'email.replied', 'email.no_reply'])

/** Events a trigger can start on, per record type (what the platform emits: rec_save, deal_status, …). */
export const EVENTS: Record<string, string[]> = {
  deal: ['created', 'updated', 'deleted', 'stage_changed', 'won', 'lost', 'reopened'],
  lead: ['created', 'updated', 'deleted', 'converted'],
  person: ['created', 'updated', 'deleted'],
  organization: ['created', 'updated', 'deleted'],
  activity: ['created', 'updated', 'deleted', 'completed'],
  ticket: ['created', 'updated', 'deleted', 'replied'],
}
/** Dates a date trigger can count from (app.wf_dates: date columns, a deal's rotting date, a renewal). */
export const DATES: Record<string, string[]> = {
  deal: ['rots_at', 'expected_close_date', 'won_at', 'lost_at', 'created_at'],
  lead: ['created_at'],
  person: ['last_touch_at', 'created_at'],
  organization: ['renewal_at', 'created_at'],
  activity: ['starts_at', 'done_at'],
  ticket: ['resolution_due_at', 'resolved_at'],
}
export const WAIT_EVENTS = ['email.replied', 'email.opened', 'email.clicked', 'deal.stage_changed', 'deal.won', 'deal.lost', 'activity.completed']

/** What a node says: its family label, title, detail line and a warning when it cannot run here. */
export function useNodeText(entity: string, base: Base, pickers: Pickers, labels: Map<string, string>) {
  const t = useTranslations('automation.builder.nodes')
  const w = useWords()
  return useCallback((s: Step) => {
    const c = s.config
    const ent = w.pick('entityLower', entity)
    const owner = (v: unknown) => (v === '@workflow_owner' ? t('owner.workflow') : t('owner.record', { entity: ent }))
    const name = (list: { id: string; name: string }[], id: unknown) => list.find((x) => x.id === id)?.name ?? t('notChosen')
    const values = (v: unknown) => (v && typeof v === 'object' ? Object.keys(v).map((k) => w.pick('fields', k)).join(', ') : '')
    let title = ''
    let sub = ''
    switch (s.kind) {
      case 'condition': {
        const g = w.groups(c.groups, labels).filter(Boolean)
        title = g[0] || t('condition.empty')
        sub = g.slice(1).map((x) => `${w.t('or').toUpperCase()} ${x}`).join(' · ')
        break
      }
      case 'if_else': title = t('if_else.t'); break
      case 'delay': {
        const n = Number(c.amount ?? 0)
        const unit = String(c.unit ?? 'days')
        title = unit === 'days' && c.skip_weekends ? t('delay.business', { n }) : t(`delay.${unit === 'minutes' ? 'minutes' : unit === 'hours' ? 'hours' : 'days'}`, { n })
        sub = c.skip_weekends ? t('delay.skips') : ''
        break
      }
      case 'wait_for':
        title = t('wait_for.t', { event: w.pick('waitEvent', String(c.event ?? '')) })
        sub = t(`wait_for.${c.then === 'stop' ? 'stop' : 'continue'}`, { n: Number(c.timeout_days ?? 7) })
        break
      case 'create_record': title = t('create_record.t', { entity: w.pick('entityLower', String(c.entity ?? 'deal')) }); sub = values(c.values); break
      case 'update_record': title = t('update_record.t', { entity: ent }); sub = values(c.values) || t('noFields'); break
      case 'delete_record': title = t('delete_record.t', { entity: ent }); break
      case 'create_activity': title = t('create_activity.t'); sub = [String(c.subject ?? ''), t('assigned', { who: owner(c.owner) })].filter(Boolean).join(' · '); break
      case 'add_note': title = t('add_note.t', { entity: ent }); sub = c.body ? `«${String(c.body)}»` : ''; break
      case 'notify': title = t('notify.t', { who: owner(c.to) }); sub = String(c.message ?? ''); break
      case 'send_email': title = t('send_email.t'); sub = t('send_email.s', { template: name(pickers.emailTemplates, c.template_id), who: owner(c.from) }); break
      case 'enroll_sequence': title = t('enroll_sequence.t'); sub = name(pickers.sequences, c.sequence_id); break
      case 'assign_owner': {
        const a = (c.assignee ?? {}) as Record<string, string>
        title = t('assign_owner.t')
        sub = a.kind === 'user' ? name(base.people, a.staff_id) : a.kind === 'team_rr' ? t('assign_owner.team', { team: name(base.teams, a.team_id) }) : t(`assign_owner.${a.kind === 'person_owner' ? 'person' : 'org'}`)
        break
      }
      case 'create_ticket': title = t('create_ticket.t'); sub = [name(pickers.ticketCategories, c.category_key), String(c.subject ?? '')].filter(Boolean).join(' · '); break
      case 'webhook': {
        let target = String(c.url ?? '')
        try { const u = new URL(target); target = u.host + u.pathname } catch { /* shown as typed */ }
        title = t('webhook.t'); sub = target ? `${String(c.method ?? 'POST')} ${target}` : t('webhook.noUrl'); break
      }
      case 'slack': case 'teams': title = t(`${s.kind}.t`); sub = [String(c.channel ?? ''), String(c.message ?? '')].filter(Boolean).join(' · '); break
      case 'accounting_invoice': title = t('accounting_invoice.t'); sub = t('accounting_invoice.s'); break
      case 'campaign_action': case 'project_action': title = t(`${s.kind}.t`); break
      default: title = s.kind
    }
    let warn: string | null = null
    if (NOT_AVAILABLE.has(s.kind)) warn = t('notAvailable')
    const provider = s.kind === 'accounting_invoice' ? 'accounting' : s.kind
    if (['slack', 'teams', 'accounting'].includes(provider) && !base.connected.includes(provider)) warn = t('notConnected')
    return { title, sub, warn }
  }, [t, w, entity, base, pickers, labels])
}
