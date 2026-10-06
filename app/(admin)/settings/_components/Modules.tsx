'use client'

import { useTranslations } from 'next-intl'
import { setModule } from '../actions'
import { DesignSwitch, k, useRun } from './kit'

/** Modules (Settings.dc.html, v.modules): one switch per module; the shell's nav follows after the refresh. */
export function Modules({ modules, canEdit }: { modules: { key: string; enabled: boolean }[]; canEdit: boolean }) {
  const t = useTranslations('settings')
  const { run, pending } = useRun()
  const name = (key: string) => (t.has(`modules.items.${key}.name`) ? t(`modules.items.${key}.name`) : key)
  return (
    <div className={k.card}>
      <div className={`${k.cardHead} max-md:flex-col`}>
        <b className="text-14">{t('modules.title')}</b>
        <span className="text-12 text-muted">{t('modules.sub')}</span>
      </div>
      {!canEdit ? <div className="border-b border-line px-[18px] py-[9px] text-12 text-muted">{t('readOnly', { right: t('rights.configure') })}</div> : null}
      {modules.map((m) => (
        <div key={m.key} className="flex items-center justify-between gap-3 border-b border-line px-[18px] py-[11px]">
          <span className="flex flex-col">
            <b className="text-13">{name(m.key)}</b>
            <span className="text-11.5 text-muted">{t.has(`modules.items.${m.key}.desc`) ? t(`modules.items.${m.key}.desc`) : ''}</span>
          </span>
          <DesignSwitch
            on={m.enabled}
            label={name(m.key)}
            disabled={!canEdit || pending}
            onChange={(on) => run(() => setModule({ key: m.key, enabled: on }), () => t(on ? 'modules.toastOn' : 'modules.toastOff', { name: name(m.key) }))}
          />
        </div>
      ))}
    </div>
  )
}
