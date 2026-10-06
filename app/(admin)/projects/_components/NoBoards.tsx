'use client'

import { useTranslations } from 'next-intl'
import type { Rights } from '@/lib/data/projects-shared'
import { NewBoardForm } from './SetupView'

/** No boards yet (D-41): a «New board» card for «projects:configure», a plain message for everybody else. */
export function NoBoards({ rights, onCreated }: { rights: Rights; onCreated: () => void | Promise<void> }) {
  const t = useTranslations('projects.empty')
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-20 border border-dashed border-line-strong bg-surface px-[22px] py-8 text-center">
        <div className="text-15 font-bold">{t('title')}</div>
        <div className="mt-2 text-13 text-muted">{t(rights.configure ? 'bodyConfigure' : 'body')}</div>
      </div>
      {rights.configure ? <div className="max-w-[520px]"><NewBoardForm onCreated={() => onCreated()} /></div> : null}
    </div>
  )
}
