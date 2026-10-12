import 'server-only'

/**
 * The count on the «Bug triage» pill: open bugs for the application, or null when there is none to show. dev-core
 * replaces this with the real count (0079); until then the pill carries no badge rather than an invented one.
 */
export async function openBugCount(product: string): Promise<number | null> {
  void product
  return null
}
