import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import { routeVisible } from '@/lib/nav'
import { loadCrmDeal, loadCrmDeals, loadCrmLists } from '@/lib/data/simple-crm'
import { CRM_TABS, type CrmRights } from '@/lib/data/simple-crm-shared'
import { CrmScreen } from './_components/CrmScreen'

const uuid = z.string().uuid().nullable().catch(null)
const Params = z.object({ tab: z.enum(CRM_TABS).nullable().catch(null), deal: uuid, list: uuid })
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Sentral Simple › CRM (SimpleCRM.dc.html): «Deals» (default) — the first pipeline as a board with the deal drawer at
 * ?deal=<id> — and «Lists» (?tab=lists, the chosen list at &list=<id>) — saved campaign segments and their people.
 * Each tab loads only what it shows.
 */
export default async function CrmPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse({ tab: one(sp.tab), deal: one(sp.deal), list: one(sp.list) })
  const shell = await getShell()
  const tab = p.tab ?? 'deals'
  const rights: CrmRights = {
    meId: shell.me.id,
    add: can(shell, 'deals', 'add'),
    editOthers: can(shell, 'deals', 'edit_others'),
    readOnly: !can(shell, 'deals', 'add') && !can(shell, 'deals', 'edit_others'),
    exportRows: can(shell, 'deals', 'export'),
    lists: shell.modules.campaigns !== false && can(shell, 'campaigns', 'see'),
    addList: shell.modules.campaigns !== false && can(shell, 'campaigns', 'add'),
    growth: routeVisible('growth', {
      admin: shell.me.permission_kind === 'admin', rights: shell.me.rights, modules: shell.modules, meetingsWorkspace: shell.meetings_workspace,
    }),
  }
  const common = { rights, nf: shell.me.number_format, tz: shell.me.time_zone }

  if (tab === 'lists') {
    const lists = rights.lists ? await loadCrmLists(p.list) : null
    return (
      <CrmScreen
        {...common}
        tab="lists"
        lists={lists && lists.ok ? lists.data : null}
        listsBlocked={!rights.lists ? (shell.modules.campaigns === false ? 'moduleOff' : 'noRight') : lists && !lists.ok ? 'failed' : null}
      />
    )
  }

  const [deals, deal] = await Promise.all([loadCrmDeals(), p.deal ? loadCrmDeal(p.deal) : null])
  return (
    <CrmScreen
      {...common}
      tab="deals"
      deals={deals.ok ? deals.data : null}
      dealsBlocked={deals.ok ? null : deals.code === 'module_off' ? 'moduleOff' : 'failed'}
      initialDeal={deal && deal.ok ? deal.data : null}
    />
  )
}
