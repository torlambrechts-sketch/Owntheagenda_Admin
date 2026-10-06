import { z } from 'zod'
import { getTranslations } from 'next-intl/server'
import { can, getShell } from '@/lib/shell'
import {
  loadCaptureSettings, loadChat, loadChatQueue, loadCustomFields, loadForm, loadForms, loadPipelines, loadPlaybookStats, loadPlaybooks,
  loadProspectFilters, loadProspectUsage, loadSequences, loadSites, loadSubmissions,
} from '@/lib/data/capture'
import { LEAD_TABS, type LeadTab } from '@/lib/data/capture-shared'
import { CaptureTabs, visiblePills } from './_components/CaptureTabs'
import { FormsView } from './_components/FormsView'
import { ChatView } from './_components/ChatView'
import { ProspectView } from './_components/ProspectView'

const Params = z.object({
  tab: z.enum(LEAD_TABS).nullable().catch(null),
  form: z.string().uuid().nullable().catch(null),
  pb: z.string().uuid().nullable().catch(null),
  chat: z.string().uuid().nullable().catch(null),
  kw: z.string().max(200).nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Lead capture (Marketing.dc.html, route leadgen): Web forms, Chatbot and live chat, Prospect search. The tab and
 * the chosen form or playbook live in the address; each tab loads only what it shows and only what the staff
 * member may see (forms and playbooks campaigns:see, chats and prospects deals:see; spec §6, Q21).
 */
export default async function LeadCapturePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab), form: one(sp.form), pb: one(sp.pb), chat: one(sp.chat), kw: one(sp.kw) })
  const shell = await getShell()
  const t = await getTranslations('capture')
  const nf = shell.me.number_format
  const rights = { campaigns: can(shell, 'campaigns', 'see'), deals: can(shell, 'deals', 'see') }
  const pills = visiblePills(shell.modules, rights)
  const tabs = LEAD_TABS.filter((k) => pills.includes(k))
  const tab: LeadTab | null = p.tab && tabs.includes(p.tab) ? p.tab : (tabs[0] ?? null)

  if (!tab) {
    return (
      <div className="px-4 pb-[60px] pt-5 md:px-7">
        <div className="rounded-20 border border-line bg-surface p-[26px]">
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t(shell.modules.leadgen === false ? 'noAccess.moduleOff' : 'noAccess.body')}</p>
        </div>
      </div>
    )
  }

  let body: React.ReactNode
  if (tab === 'forms') {
    const forms = await loadForms()
    const id = forms.find((f) => f.id === p.form)?.id ?? forms[0]?.id ?? null
    const [detail, subs, sequences, pipelines, customFields] = await Promise.all([
      id ? loadForm(id) : null,
      id && rights.deals ? loadSubmissions(id) : null,
      loadSequences(),
      loadPipelines(),
      loadCustomFields(),
    ])
    body = (
      <FormsView
        forms={forms}
        form={detail && detail.ok ? detail.data : null}
        submissions={subs && subs.ok ? subs.data : null}
        sequences={sequences}
        pipelines={pipelines}
        customFields={customFields}
        can={{
          add: can(shell, 'campaigns', 'add'), configure: can(shell, 'campaigns', 'configure'), del: can(shell, 'campaigns', 'delete'),
          editOthers: can(shell, 'campaigns', 'edit_others'), me: shell.me.id,
        }}
        nf={nf}
      />
    )
  } else if (tab === 'chat') {
    const [playbooks, queue, sites, settings] = await Promise.all([
      rights.campaigns ? loadPlaybooks() : null,
      rights.deals ? loadChatQueue() : null,
      rights.campaigns ? loadSites() : null,
      loadCaptureSettings(),
    ])
    const pb = playbooks ? (playbooks.find((x) => x.id === p.pb) ?? playbooks[0] ?? null) : null
    const chatId = queue ? (queue.rows.find((r) => r.id === p.chat)?.id ?? queue.rows[0]?.id ?? null) : null
    const [stats, chat] = await Promise.all([pb ? loadPlaybookStats(pb.id) : null, chatId ? loadChat(chatId) : null])
    body = (
      <ChatView
        playbooks={playbooks}
        playbook={pb}
        stats={stats && stats.ok ? stats.data : null}
        queue={queue}
        chat={chat && chat.ok ? chat.data : null}
        sites={sites}
        widgetConsent={settings.widget_consent}
        can={{
          add: can(shell, 'campaigns', 'add'), configure: can(shell, 'campaigns', 'configure'), editOthers: can(shell, 'campaigns', 'edit_others'),
          chat: can(shell, 'deals', 'add'), me: shell.me.id, meName: shell.me.name,
        }}
        nf={nf}
      />
    )
  } else {
    const [usage, saved] = await Promise.all([loadProspectUsage(), loadProspectFilters()])
    // «Find people here» (Web visitors) opens the search with the company's name or domain
    body = <ProspectView key={p.kw ?? ''} usage={usage} saved={saved} initial={p.kw ? { keyword: p.kw } : {}} nf={nf} />
  }

  return (
    <div className="flex flex-col gap-[14px] px-4 pb-[60px] pt-5 text-14 text-ink md:px-7">
      <CaptureTabs current={tab} pills={pills} />
      {body}
    </div>
  )
}
