'use client'

import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import { download, toCsv, toXlsx } from '@/lib/xlsx'
import { exportSheet, HEALTHS, type ExportCell } from '@/lib/data/projects-shared'
import { exportProjects } from '../actions'

const TRANSLATED = new Set(['status', 'health', 'kind'])

/**
 * Export (PRJ-08): a board's projects or one project's items through project_export, which checks
 * «projects:export», neutralises formula cells and audits the export; the file is written here (lib/xlsx).
 */
export function useExporter(board: string | null, project: string | null, name: string) {
  const t = useTranslations('projects')
  const te = useTranslations('common.errors')
  const flash = useToast()
  return async (format: 'csv' | 'xlsx') => {
    const r = await exportProjects({ board, project, format })
    if (!r.ok) return flash(te(r.code))
    const head = (k: string) => (t.has(`export.cols.${k}`) ? t(`export.cols.${k}`) : k)
    const cell = (k: string, v: ExportCell): string | number => {
      if (v === null) return ''
      if (typeof v === 'boolean') return t(v ? 'export.yes' : 'export.no')
      if (typeof v === 'number') return v
      if (k === 'health' && (HEALTHS as readonly string[]).includes(v)) return t(`health.${v}`)
      if (TRANSLATED.has(k) && t.has(`export.values.${v}`)) return t(`export.values.${v}`)
      return v
    }
    const rows = exportSheet(r.data.columns, r.data.rows, head, cell)
    const file = `${name.replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '').toLowerCase() || 'projects'}-${new Date().toISOString().slice(0, 10)}`
    if (format === 'csv') download(new Blob(['﻿' + toCsv(rows)], { type: 'text/csv;charset=utf-8' }), `${file}.csv`)
    else download(toXlsx(rows, name || 'Projects'), `${file}.xlsx`)
    flash(t('export.done', { count: r.data.rows.length }))
  }
}

export function ExportMenu({ board, project, name, tall = false }: { board: string | null; project: string | null; name: string; tall?: boolean }) {
  const t = useTranslations('projects')
  const run = useExporter(board, project, name)
  return (
    <select
      aria-label={t('export.label')}
      value=""
      onChange={(e) => { const v = e.target.value; if (v === 'csv' || v === 'xlsx') void run(v) }}
      className={tall ? 'h-9 cursor-pointer rounded-10 border border-line bg-transparent px-2 text-12.5 font-semibold text-ink' : 'h-[34px] cursor-pointer rounded-10 border border-line bg-transparent px-2 text-12.5 font-semibold text-ink'}
    >
      <option value="">{t('export.label')}</option>
      <option value="csv">{t('export.csv')}</option>
      <option value="xlsx">{t('export.xlsx')}</option>
    </select>
  )
}
