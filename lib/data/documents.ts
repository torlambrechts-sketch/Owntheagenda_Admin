import 'server-only'
import { z } from 'zod'
import { rpc } from '@/lib/rpc'
import {
  DocDetail, DocList, DocView, MergeField, SignRequest, StorageState, Template, TemplateDetail, type DealOption, type TeamOption,
} from '@/lib/data/documents-shared'

/**
 * Documents (Documents.dc.html) reads through the 0032 functions: the documents on deals the staff member can
 * see, one document with its links, its views, the templates, a signature request and the storage settings.
 * Every answer is parsed; a refusal comes back as its code for the screen to word.
 */
export const loadDocuments = () => rpc('documents_get', { p_query: { limit: 200 } }, DocList)
export const loadDocument = (id: string) => rpc('document_get', { p_id: id }, DocDetail)
export const loadViews = (id: string) => rpc('document_views', { p_id: id }, z.array(DocView))
export const loadTemplates = () => rpc('doc_templates_get', { p_category: null }, z.array(Template))
export const loadTemplate = (id: string) => rpc('doc_template_get', { p_id: id }, TemplateDetail)
export const loadSignRequest = (id: string) => rpc('signature_request_get', { p_id: id }, SignRequest)
export const loadStorage = () => rpc('doc_storage_get', {}, StorageState)

/** The document tokens of the merge registry (merge_fields_get('document')), for the template editor. */
export async function loadMergeFields(): Promise<MergeField[]> {
  const r = await rpc('merge_fields_get', { p_context: 'document' }, z.array(MergeField), { quiet: true })
  return r.ok ? r.data : []
}

/** Deals a document can be made on: every deal the staff member can see, by title. */
export async function loadDealOptions(): Promise<DealOption[]> {
  const r = await rpc('deal_list', { p_query: { limit: 500, sort: [{ f: 'title', dir: 'asc' }] } }, z.object({ rows: z.array(z.object({ id: z.string().uuid(), title: z.string() })) }))
  return r.ok ? r.data.rows : []
}

/** Teams a template can be shared with: the staff member's own, or every team with Deals › configure (doc_template_save). */
export async function loadTeams(meId: string, all: boolean): Promise<TeamOption[]> {
  const r = await rpc('access_model', {}, z.object({ teams: z.array(z.object({ id: z.string().uuid(), name: z.string(), members: z.array(z.object({ id: z.string().uuid() })) })) }), { quiet: true })
  if (!r.ok) return []
  return r.data.teams.filter((t) => all || t.members.some((m) => m.id === meId)).map((t) => ({ id: t.id, name: t.name }))
}
