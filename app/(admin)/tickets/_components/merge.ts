/** A macro's merge field left in a text: [antall], [domene] … A reply is never sent with one still in it. */
export const placeholders = (text: string): string[] => Array.from(new Set(text.match(/\[[^\]\n]{1,40}\]/g) ?? []))

/** The merge fields a ticket can fill; the others stay for the agent to write. */
export function fillMerge(body: string, f: { fornavn: string | null; organisasjon: string | null; orgnr: string | null; agent: string }): string {
  let out = body
  if (f.fornavn) out = out.replaceAll('[fornavn]', f.fornavn)
  if (f.organisasjon) out = out.replaceAll('[organisasjon]', f.organisasjon)
  if (f.orgnr) out = out.replaceAll('[orgnr]', f.orgnr)
  return out.replaceAll('[agent]', f.agent)
}
