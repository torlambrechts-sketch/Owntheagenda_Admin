'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { useToast } from '@/components/ui/Toast'
import type { WorkflowTemplate } from '@/lib/data/automation'
import { createFromTemplate } from '../actions'
import { useErrorText, useGo } from './shared'

/** Templates (Automation.dc.html, v.templates): the engine's seeded templates in their groups. «Use template →»
 *  creates a draft from the template's graph and opens it in the builder. */
export function TemplatesTab({ templates, canCreate }: { templates: WorkflowTemplate[]; canCreate: boolean }) {
  const t = useTranslations('automation.templates')
  const flash = useToast()
  const err = useErrorText()
  const { go } = useGo()
  const [busy, setBusy] = useState<string | null>(null)
  const groups = [...new Set(templates.map((x) => x.group))]
  const name = (k: string) => (t.has(`items.${k}.n`) ? t(`items.${k}.n`) : k)

  const use = async (k: string) => {
    if (!canCreate) { flash(err('forbidden')); return }
    setBusy(k)
    const r = await createFromTemplate({ key: k, name: name(k) })
    setBusy(null)
    if (!r.ok) { flash(err(r.code, r.detail)); return }
    flash(t('created', { name: name(k) }))
    go({ tab: 'builder', wf: r.id }, { reset: true })
  }

  return (
    <div className="flex flex-col gap-4">
      {groups.map((g) => (
        <div key={g} className="flex flex-col gap-[10px]">
          <b className="text-14">{t.has(`groups.${g}`) ? t(`groups.${g}`) : g}</b>
          <div className="grid gap-[10px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr))]">
            {templates.filter((x) => x.group === g).map((x) => (
              <button
                key={x.key}
                type="button"
                disabled={busy !== null}
                onClick={() => use(x.key)}
                className="flex cursor-pointer flex-col gap-[6px] rounded-18 border border-line bg-surface px-4 py-[14px] text-left"
              >
                <b className="text-13">{name(x.key)}</b>
                <span className="text-12 leading-[1.45] text-muted">{t.has(`items.${x.key}.d`) ? t(`items.${x.key}.d`) : ''}</span>
                <span className="text-11.5 font-bold text-link">{t('use')}</span>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
