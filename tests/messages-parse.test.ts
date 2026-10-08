import { readdirSync, readFileSync } from 'node:fs'
import { IntlMessageFormat } from 'intl-messageformat'
import { describe, expect, it } from 'vitest'

/**
 * Every UI text must parse as ICU MessageFormat, as next-intl parses it at runtime: a stray «<word>» is read as an
 * unclosed tag and the screen shows the raw key instead (simplePlatform.email.appBaseNote, 2026-10-08).
 */
function strings(o: unknown, path: string, out: Array<[string, string]>) {
  if (typeof o === 'string') out.push([path, o])
  else if (o && typeof o === 'object') for (const [k, v] of Object.entries(o)) strings(v, path ? `${path}.${k}` : k, out)
}

describe('UI texts', () => {
  for (const lang of ['no', 'en']) {
    it(`every ${lang} text parses as ICU MessageFormat`, () => {
      const bad: string[] = []
      for (const f of readdirSync(new URL(`../messages/${lang}/`, import.meta.url)).filter((x) => x.endsWith('.json'))) {
        const all: Array<[string, string]> = []
        strings(JSON.parse(readFileSync(new URL(`../messages/${lang}/${f}`, import.meta.url), 'utf8')), '', all)
        for (const [key, text] of all) {
          try {
            new IntlMessageFormat(text, lang === 'no' ? 'nb' : 'en')
          } catch (e) {
            bad.push(`${f} ${key}: ${(e as Error).message.slice(0, 40)}`)
          }
        }
      }
      expect(bad).toEqual([])
    })
  }
})
