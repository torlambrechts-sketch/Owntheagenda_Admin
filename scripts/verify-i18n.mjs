// Every message key in bokmål exists in English and the reverse: the UI never shows a raw key.
import { readFileSync } from 'node:fs'

const flat = (o, p = '', out = new Set()) => {
  for (const [k, v] of Object.entries(o)) {
    const key = p ? `${p}.${k}` : k
    if (v && typeof v === 'object') flat(v, key, out)
    else out.add(key)
  }
  return out
}
const no = flat(JSON.parse(readFileSync('messages/no.json', 'utf8')))
const en = flat(JSON.parse(readFileSync('messages/en.json', 'utf8')))
const missing = [...[...no].filter((k) => !en.has(k)).map((k) => `en lacks ${k}`), ...[...en].filter((k) => !no.has(k)).map((k) => `no lacks ${k}`)]
if (missing.length) {
  console.error(missing.join('\n'))
  process.exit(1)
}
console.log(`i18n: ${no.size} keys in both languages`)
