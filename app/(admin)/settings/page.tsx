import Link from 'next/link'
import { getFormatter, getNow, getTranslations } from 'next-intl/server'
import { getShell } from '@/lib/shell'
import {
  RULE_GROUPS, SECTIONS, allowed, countRecords, effective, loadAccessModel, loadActivityTypes, loadFields, loadModules, loadPipelines,
  loadSandboxCounts, loadSettings, loadSettingsLog, loadStaff, type Section,
} from '@/lib/data/settings'
import { Rules } from './_components/Rules'
import { Modules } from './_components/Modules'
import { Fields } from './_components/Fields'
import { Pipelines } from './_components/Pipelines'
import { ActTypes } from './_components/ActTypes'
import { Locale } from './_components/Locale'
import { Users } from './_components/Users'
import { Perms } from './_components/Perms'
import { Groups } from './_components/Groups'
import { Plans } from './_components/Plans'
import { Sandbox } from './_components/Sandbox'
import { NavIntoView } from './_components/NavIntoView'

/**
 * Settings (Settings.dc.html): a section nav and one section at a time, chosen by ?sec=. The design's
 * section buttons become links (control substitution, V-01), so a section has an address. Each section
 * reads only what it shows.
 */
export default async function SettingsPage({ searchParams }: { searchParams: Promise<{ sec?: string }> }) {
  const sp = await searchParams
  const sec: Section = (SECTIONS as readonly string[]).includes(sp.sec ?? '') ? (sp.sec as Section) : 'rules'
  const t = await getTranslations('settings.sections')

  return (
    <div className="grid items-start gap-4 px-4 pb-[60px] pt-5 text-14 text-ink md:px-7 md:[grid-template-columns:200px_minmax(0,1fr)]">
      <nav data-settings-nav aria-label={t('label')} className="flex gap-[2px] overflow-x-auto max-md:-mx-4 max-md:px-4 max-md:pb-1 md:sticky md:top-[76px] md:flex-col">
        {SECTIONS.map((k) => (
          <Link
            key={k}
            href={`/settings?sec=${k}`}
            aria-current={sec === k ? 'page' : undefined}
            className={`whitespace-nowrap rounded-10 px-[11px] py-2 text-left text-13 text-ink hover:text-ink hover:no-underline ${sec === k ? 'bg-highlight font-bold' : 'bg-transparent font-medium'}`}
          >
            {t(k)}
          </Link>
        ))}
        <NavIntoView sec={sec} />
      </nav>
      <div className="flex min-w-0 flex-col gap-[14px]">
        <SectionBody sec={sec} />
      </div>
    </div>
  )
}

async function SectionBody({ sec }: { sec: Section }) {
  const shell = await getShell()
  const nf = shell.me.number_format
  const format = await getFormatter()
  const now = await getNow()

  switch (sec) {
    case 'rules': {
      const [settings, log, modules] = await Promise.all([loadSettings(), loadSettingsLog(), loadModules()])
      return (
        <Rules
          settings={settings.filter((s) => (RULE_GROUPS as readonly string[]).includes(s.group))}
          registry={settings.map((s) => s.key)}
          modules={modules.map((m) => m.key)}
          log={log.map((l) => ({ ...l, when: format.dateTime(new Date(l.at), { day: 'numeric', month: 'short' }) }))}
          nf={nf}
          canEdit={allowed(shell, 'global', 'configure')}
        />
      )
    }
    case 'modules':
      return <Modules modules={await loadModules()} canEdit={allowed(shell, 'global', 'configure')} />
    case 'fields': {
      const [fields, sandbox, pipelines, access, settings] = await Promise.all([loadFields(null), loadSandboxCounts(), loadPipelines(), loadAccessModel(), loadSettings()])
      const limit = settings.find((s) => s.key === 'count_limits')
      const lim = limit ? effective(limit) : null
      return (
        <Fields
          entities={sandbox.entities}
          fields={fields}
          pipelines={pipelines ?? []}
          sets={access.permission_sets.map((p) => ({ id: p.id, name: p.name }))}
          optionLimit={lim && lim.value === 'number' && lim.number !== null ? lim.number : null}
          canEdit={Object.fromEntries(sandbox.entities.map((e) => [e, allowed(shell, e === 'ticket' ? 'tickets' : 'deals', 'configure')]))}
        />
      )
    }
    case 'pipelines': {
      const [pipelines, access] = await Promise.all([loadPipelines(), loadAccessModel()])
      return <Pipelines pipelines={pipelines} groups={access.groups.map((g) => ({ id: g.id, name: g.name }))} canEdit={allowed(shell, 'deals', 'configure')} />
    }
    case 'acttypes': {
      const [types, fields] = await Promise.all([loadActivityTypes(), loadFields('activity')])
      return <ActTypes types={types} fields={fields.map((f) => ({ label: f.label, types: f.activity_type_ids ?? null }))} canEdit={allowed(shell, 'deals', 'configure')} />
    }
    case 'locale': {
      const zones = Intl.supportedValuesOf('timeZone')
      return (
        <Locale
          me={{ locale: shell.me.locale, time_zone: shell.me.time_zone, number_format: shell.me.number_format }}
          dateSample={format.dateTime(now, { day: 'numeric', month: 'short', year: 'numeric' })}
          zones={zones.includes(shell.me.time_zone) ? zones : [shell.me.time_zone, ...zones]}
        />
      )
    }
    case 'users': {
      const [staff, access] = await Promise.all([loadStaff(), loadAccessModel()])
      const seen = (iso: string | null) => {
        if (!iso) return null
        const d = new Date(iso)
        return now.getTime() - d.getTime() < 120_000 ? 'now' : format.relativeTime(d, now)
      }
      return (
        <Users
          me={shell.me.id}
          staff={staff.map((s) => ({ ...s, seen: seen(s.last_seen_at) }))}
          access={access}
          canEdit={allowed(shell, 'global', 'security')}
        />
      )
    }
    case 'perms':
      return <Perms sets={(await loadAccessModel()).permission_sets} canEdit={allowed(shell, 'global', 'security')} />
    case 'groups': {
      const [access, settings, sandbox] = await Promise.all([loadAccessModel(), loadSettings(), loadSandboxCounts()])
      const vis = settings.find((s) => s.key === 'visibility_default')
      return (
        <Groups
          groups={access.groups}
          entities={sandbox.entities.map((e) => ({ key: e, value: vis ? effective(vis, e).value : 'all' }))}
          options={vis?.options ?? ['owner', 'group', 'group_sub', 'all']}
          canEditGroups={allowed(shell, 'global', 'security')}
          canEditDefaults={allowed(shell, 'global', 'configure')}
        />
      )
    }
    case 'plans': {
      const [settings, sandbox, fields, staff, access, pipelines, types] = await Promise.all([
        loadSettings(), loadSandboxCounts(), loadFields(null), loadStaff(), loadAccessModel(), loadPipelines(), loadActivityTypes(),
      ])
      const records = await Promise.all(sandbox.entities.map(async (e) => ({ key: e, n: await countRecords(e) })))
      const gates = settings.find((s) => s.key === 'plan_gates')
      return (
        <Plans
          nf={nf}
          perPlan={gates ? effective(gates).value === 'per_plan' : false}
          records={records.filter((r): r is { key: string; n: number } => r.n !== null)}
          counts={{
            fields: fields.length,
            formula: fields.filter((f) => f.type === 'formula').length,
            pipelines: pipelines?.length ?? null,
            staff: staff.filter((s) => s.active && !s.is_sample).length,
            teams: access.teams.length,
            groups: access.groups.length,
            sets: access.permission_sets.length,
            acttypes: types.filter((x) => x.active).length,
          }}
        />
      )
    }
    case 'sandbox': {
      const sandbox = await loadSandboxCounts()
      return (
        <Sandbox
          rows={sandbox.entities.map((e) => ({ key: e, n: sandbox.counts[e] ?? 0 }))}
          lastCleared={sandbox.lastCleared ? format.dateTime(new Date(sandbox.lastCleared), { day: 'numeric', month: 'short', year: 'numeric' }) : null}
          on={shell.me.sandbox}
          nf={nf}
          canClear={allowed(shell, 'global', 'configure')}
        />
      )
    }
  }
}
