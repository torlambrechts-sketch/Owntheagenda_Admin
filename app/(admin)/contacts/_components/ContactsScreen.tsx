'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useTranslations } from 'next-intl'
import type { ContactsData, Tab } from '@/lib/data/contacts'
import type { Me, Rights } from './util'
import { PeopleTab } from './PeopleTab'
import { OrgsTab } from './OrgsTab'
import { LeadsTab } from './LeadsTab'
import { TimelineTab } from './TimelineTab'
import { MapTab } from './MapTab'
import { DupesTab } from './DupesTab'
import { ImportTab } from './ImportTab'
import { ExportTab } from './ExportTab'
import { RestoreTab } from './RestoreTab'
import { PersonDrawer } from './PersonDrawer'
import { RecordForm, type FormTarget } from './RecordForm'

const TAB_KEYS: Tab[] = ['people', 'orgs', 'leads', 'timeline', 'map', 'dupes', 'import', 'export', 'restore']
// the leads tab is its own route; the others live on /contacts (the design's tab buttons become links, V-01)
const hrefOf = (k: Tab) => (k === 'leads' ? '/leads' : k === 'people' ? '/contacts' : `/contacts?tab=${k}`)

export type ScreenProps = { data: ContactsData; rights: Rights; me: Me; now: string }

export function ContactsScreen({ data, rights, me, now }: ScreenProps) {
  const t = useTranslations('contacts')
  const [form, setForm] = useState<FormTarget | null>(null)
  const [importKey, setImportKey] = useState(0)
  const tab = data.tab
  const addEntity = tab === 'leads' ? 'lead' : tab === 'orgs' ? 'organization' : tab === 'import' ? null : 'person'
  const addLabel = tab === 'leads' ? t('add.lead') : tab === 'orgs' ? t('add.organization') : tab === 'import' ? t('add.import') : t('add.person')
  const props = { data, rights, me, now, openForm: setForm }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <div className="flex flex-wrap items-center justify-between gap-[10px]">
        <nav aria-label={t('tabsLabel')} className="flex flex-wrap gap-[6px]">
          {TAB_KEYS.map((k) => {
            const on = k === tab
            return (
              <Link
                key={k}
                href={hrefOf(k) as never}
                aria-current={on ? 'page' : undefined}
                className={`cursor-pointer rounded-999 border px-[14px] py-2 text-12.5 hover:no-underline ${on ? 'border-ink bg-ink font-bold text-canvas hover:text-canvas' : 'border-line-strong bg-transparent font-medium text-ink hover:text-ink'}`}
              >
                {t(`tabs.${k}`)}
              </Link>
            )
          })}
        </nav>
        <div className="flex items-center gap-2">
          <span className="text-12 text-muted">{t('sync')}</span>
          {rights.add ? (
            <button
              type="button"
              onClick={() => (addEntity ? setForm({ entity: addEntity, id: null }) : setImportKey((n) => n + 1))}
              className="h-9 cursor-pointer rounded-10 border border-ink bg-primary px-[15px] text-12.5 font-bold"
            >
              {addLabel}
            </button>
          ) : null}
        </div>
      </div>

      {tab === 'people' ? <PeopleTab {...props} /> : null}
      {tab === 'orgs' ? <OrgsTab {...props} /> : null}
      {tab === 'leads' ? <LeadsTab {...props} /> : null}
      {tab === 'timeline' ? <TimelineTab {...props} /> : null}
      {tab === 'map' ? <MapTab {...props} /> : null}
      {tab === 'dupes' ? <DupesTab {...props} /> : null}
      {tab === 'import' ? <ImportTab key={importKey} {...props} /> : null}
      {tab === 'export' ? <ExportTab {...props} /> : null}
      {tab === 'restore' ? <RestoreTab {...props} /> : null}

      {data.detail ? <PersonDrawer {...props} detail={data.detail} /> : null}
      {form ? <RecordForm target={form} data={data} rights={rights} me={me} onClose={() => setForm(null)} /> : null}
    </div>
  )
}

export type TabProps = ScreenProps & { openForm: (f: FormTarget) => void }
