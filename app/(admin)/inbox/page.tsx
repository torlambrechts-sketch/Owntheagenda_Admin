import { getTranslations } from 'next-intl/server'
import { z } from 'zod'
import { can, getShell } from '@/lib/shell'
import {
  loadCalls, loadDropbox, loadFolders, loadGroupPreview, loadLabels, loadMailboxes, loadMergeFields, loadOutbox, loadPeopleViews, loadPipelines,
  loadStaff, loadStageDeals, loadTemplates, loadThread, loadThreads,
} from '@/lib/data/inbox'
import { FOLDERS, type Folder } from '@/lib/data/inbox-shared'
import { ui } from '@/components/ui/styles'
import { Rail } from './_components/Rail'
import { MailView } from './_components/MailView'
import { OutboxView } from './_components/OutboxView'
import { GroupView, type GroupSource } from './_components/GroupView'
import { MessagingView } from './_components/MessagingView'
import { CallsView } from './_components/CallsView'
import { SetupView } from './_components/SetupView'

const uuid = z.string().uuid()
const Params = z.object({
  folder: z.enum(FOLDERS).catch('inbox'),
  mailbox: uuid.nullable().catch(null),
  label: uuid.nullable().catch(null),
  thread: uuid.nullable().catch(null),
  compose: z.literal('1').nullable().catch(null),
  src: z.enum(['view', 'people', 'deals']).catch('people'),
  view: uuid.nullable().catch(null),
  stage: uuid.nullable().catch(null),
  people: z.string().max(200000).nullable().catch(null),
  tpl: uuid.nullable().catch(null),
})
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? null

/**
 * Inbox (Inbox.dc.html). The folder, label, open thread and composer live in the address, so a link from a
 * notification (/inbox?thread=<id>) opens the same state. Each view loads only what it shows. No mailbox is
 * connected until the Gmail or Microsoft OAuth client is configured: the synced history is shown, the
 * mailboxes say they are disconnected, and sending is refused with that reason.
 */
export default async function InboxPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams
  const p = Params.parse(Object.fromEntries(Object.keys(Params.shape).map((k) => [k, one(sp[k])])))
  const shell = await getShell()
  const t = await getTranslations('inbox')
  if (!can(shell, 'deals', 'see')) {
    return (
      <div className="px-4 pb-[60px] pt-[18px] md:px-7">
        <div className={`${ui.card} p-[26px]`}>
          <h1 className="m-0 font-serif text-22 font-semibold">{t('noAccess.title')}</h1>
          <p className="m-0 mt-2 text-13 text-muted">{t('noAccess.body')}</p>
        </div>
      </div>
    )
  }

  const [folders, labels] = await Promise.all([loadFolders(), loadLabels()])
  let folder: Folder = p.folder
  const team = folder === 'team' ? folders.teams.find((x) => x.mailbox_id === p.mailbox) ?? folders.teams[0] ?? null : null
  if (folder === 'team' && !team) folder = 'inbox'
  const label = folder === 'label' ? labels.find((l) => l.id === p.label) ?? null : null
  if (folder === 'label' && !label) folder = 'inbox'
  const now = new Date().toISOString()

  let body: React.ReactNode = null
  if (folder === 'inbox' || folder === 'team' || folder === 'archive' || folder === 'label') {
    const threads = await loadThreads(folder === 'label' ? 'all' : folder, {
      ...(team ? { mailbox: team.mailbox_id } : {}), ...(label ? { label: label.id } : {}),
    })
    const compose = p.compose === '1'
    // the prototype always selects a thread; with none in the folder nothing is selected
    const selectedId = compose ? null : p.thread ?? threads[0]?.id ?? null
    const [thread, boxes, templates, mergeFields] = await Promise.all([
      selectedId ? loadThread(selectedId) : Promise.resolve(null),
      loadMailboxes(), loadTemplates(), loadMergeFields(),
    ])
    const name = folder === 'team' ? t('folders.team', { local: team!.address.split('@')[0]! }) : folder === 'label' ? label!.name : t(`folders.${folder}`)
    body = (
      <MailView
        key={`${folder}-${team?.mailbox_id ?? ''}-${label?.id ?? ''}-${thread?.id ?? ''}-${compose}`}
        folderName={name}
        threads={threads}
        thread={thread}
        compose={compose}
        mailboxes={boxes}
        templates={templates}
        mergeFields={mergeFields.map((m) => m.token)}
        labels={labels}
        now={now}
        canLead={can(shell, 'deals', 'add')}
        canLabel={can(shell, 'deals', 'add') || can(shell, 'deals', 'edit_others')}
      />
    )
  } else if (folder === 'outbox') {
    body = <OutboxView outbox={await loadOutbox()} now={now} />
  } else if (folder === 'group') {
    const canBulk = can(shell, 'deals', 'bulk')
    const [templates, boxes, views, pipelines] = await Promise.all([loadTemplates(), loadMailboxes(), loadPeopleViews(), loadPipelines()])
    const people = (p.people ?? '').split(',').filter((x) => uuid.safeParse(x).success).slice(0, 5000)
    let source: GroupSource | null = null
    if (p.src === 'people' && people.length) source = { kind: 'people', ids: people }
    else if (p.src === 'view' && p.view && views.some((v) => v.id === p.view)) source = { kind: 'view', view_id: p.view }
    else if (p.src === 'deals' && p.stage) source = { kind: 'deals', ids: await loadStageDeals(p.stage) }
    const preview = canBulk && source ? await loadGroupPreview(source) : null
    body = (
      <GroupView
        canBulk={canBulk}
        src={p.src}
        source={source}
        preview={preview && preview.ok ? preview.data : null}
        previewCode={preview && !preview.ok ? preview.code : null}
        views={views}
        viewId={p.view}
        pipelines={pipelines}
        stageId={p.stage}
        peopleCount={people.length}
        templates={templates}
        templateId={templates.some((x) => x.id === p.tpl) ? p.tpl : null}
        mailboxes={boxes}
      />
    )
  } else if (folder === 'messaging') {
    body = <MessagingView />
  } else if (folder === 'calls') {
    body = <CallsView calls={await loadCalls()} now={now} />
  } else {
    const [boxes, templates, dropbox, staff, mergeFields] = await Promise.all([loadMailboxes(), loadTemplates(), loadDropbox(), loadStaff(), loadMergeFields()])
    body = (
      <SetupView
        mailboxes={boxes}
        templates={templates}
        mergeFields={mergeFields.map((m) => m.token)}
        dropbox={dropbox.local_part}
        staff={staff}
        canConfigure={can(shell, 'global', 'configure')}
      />
    )
  }

  return (
    <div className="flex flex-wrap items-start gap-[14px] px-4 pb-[60px] pt-[18px] text-14 text-ink md:px-7">
      <Rail folder={folder} teamId={team?.mailbox_id ?? null} labelId={label?.id ?? null} folders={folders} labels={labels} />
      <div className="min-w-0 flex-[1_1_440px]">{body}</div>
    </div>
  )
}
