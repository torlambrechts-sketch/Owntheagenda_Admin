import { describe, expect, it } from 'vitest'
import { addField, blockAllowed, doubleOptIn, lastVisit, moveField, onPage, patchField, removeField, settingValue, type Draft } from '@/lib/data/capture-shared'

const draft: Draft = {
  intro: { title: 'Kontakt oss', body: '' },
  fields: [
    { key: 'name', kind: 'short_text', label: 'Navn', map: 'person.name', required: true },
    { key: 'email', kind: 'email', label: 'E-post', map: 'person.email', required: true },
    { key: 'consent', kind: 'marketing_status', required: false },
  ],
  consent: { text_key: 'newsletter' },
}

describe('form draft helpers', () => {
  it('adds a field with a unique key and a label in the form language', () => {
    const d = addField(addField(draft, 'short_text', 'nb'), 'short_text', 'en')
    expect(d.fields.slice(-2).map((f) => [f.key, f.label])).toEqual([['short_text', 'Nytt felt'], ['short_text_2', 'New field']])
  })
  it('allows one consent box, one email, files only on a file-upload form, custom fields only when some exist', () => {
    expect(blockAllowed(draft, 'contact', 'marketing_status', 0)).toBe(false)
    expect(blockAllowed(draft, 'contact', 'email', 0)).toBe(false)
    expect(blockAllowed(draft, 'contact', 'phone', 0)).toBe(true)
    expect(blockAllowed(draft, 'contact', 'file_upload', 0)).toBe(false)
    expect(blockAllowed(draft, 'file_upload', 'file_upload', 0)).toBe(true)
    expect(blockAllowed(draft, 'contact', 'custom_field', 0)).toBe(false)
    expect(blockAllowed(draft, 'contact', 'custom_field', 2)).toBe(true)
  })
  it('moves, removes and patches fields; an empty map or placeholder is dropped', () => {
    expect(moveField(draft, 0, 1).fields.map((f) => f.key)).toEqual(['email', 'name', 'consent'])
    expect(moveField(draft, 0, -1)).toBe(draft)
    expect(removeField(draft, 1).fields.map((f) => f.key)).toEqual(['name', 'consent'])
    const p = patchField(draft, 0, { map: '', placeholder: '' }).fields[0]!
    expect('map' in p || 'placeholder' in p).toBe(false)
  })
  it('double opt-in follows the setting, and a form may only turn it on', () => {
    expect(doubleOptIn(draft, 'on')).toBe(true)
    expect(doubleOptIn(draft, 'off')).toBe(false)
    expect(doubleOptIn({ ...draft, consent: { text_key: 'newsletter', double_opt_in: true } }, 'off')).toBe(true)
  })
})

describe('times and settings', () => {
  const now = new Date('2026-10-06T12:00:00Z')
  it('words the last visit as the design does', () => {
    expect(lastVisit('2026-10-06T11:48:00Z', now)).toEqual({ key: 'minutes', n: 12 })
    expect(lastVisit('2026-10-06T11:00:00Z', now)).toEqual({ key: 'hours', n: 1 })
    expect(lastVisit('2026-10-05T09:00:00Z', now).key).toBe('yesterday')
    expect(lastVisit('2026-10-01T09:00:00Z', now).key).toBe('date')
  })
  it('time on page is minutes, under a minute, or none for the last page', () => {
    expect(onPage(240)).toEqual({ key: 'minutes', n: 4 })
    expect(onPage(20).key).toBe('underMinute')
    expect(onPage(null).key).toBe('none')
  })
  it('a setting is the platform row, else its default', () => {
    const rows = [{ key: 'web_ident', default: 'on', values: [{ scope_id: '', value: 'off' }] }, { key: 'widget_consent', default: 'off', values: [] }]
    expect(settingValue(rows, 'web_ident')).toBe('off')
    expect(settingValue(rows, 'widget_consent')).toBe('off')
    expect(settingValue(rows, 'missing')).toBeNull()
  })
})
