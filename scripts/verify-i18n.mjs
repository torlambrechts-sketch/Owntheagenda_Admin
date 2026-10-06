// Every message key in English exists in bokmål and the reverse, file by file: the UI never shows a raw
// key. Every namespace file is listed in lib/i18n/messages.ts.
import { readFileSync, readdirSync } from 'node:fs'

const flat = (o, p = '', out = new Set()) => {
  for (const [k, v] of Object.entries(o)) {
    const key = p ? `${p}.${k}` : k
    if (v && typeof v === 'object') flat(v, key, out)
    else out.add(key)
  }
  return out
}
const problems = []
const files = new Set([...readdirSync('messages/en'), ...readdirSync('messages/no')].filter((f) => f.endsWith('.json')))
const index = readFileSync('lib/i18n/messages.ts', 'utf8')
let total = 0
const seen = new Map()
for (const f of files) {
  let en, no
  try { en = flat(JSON.parse(readFileSync(`messages/en/${f}`, 'utf8'))) } catch { problems.push(`messages/en/${f} is missing or not JSON`); continue }
  try { no = flat(JSON.parse(readFileSync(`messages/no/${f}`, 'utf8'))) } catch { problems.push(`messages/no/${f} is missing or not JSON`); continue }
  for (const k of en) if (!no.has(k)) problems.push(`no/${f} lacks ${k}`)
  for (const k of no) if (!en.has(k)) problems.push(`en/${f} lacks ${k}`)
  for (const k of en) {
    const top = k.split('.')[0]
    if (seen.has(top) && seen.get(top) !== f) problems.push(`namespace ${top} is in both ${seen.get(top)} and ${f}`)
    seen.set(top, f)
  }
  for (const l of ['en', 'no']) if (!index.includes(`@/messages/${l}/${f}`)) problems.push(`lib/i18n/messages.ts does not load messages/${l}/${f}`)
  total += en.size
}
if (problems.length) {
  console.error(problems.join('\n'))
  process.exit(1)
}
console.log(`i18n: ${total} keys in both languages across ${files.size} files`)
