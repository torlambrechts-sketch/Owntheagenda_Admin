import { describe, expect, it } from 'vitest'
import { addDays, daysBetween, dragDays, exportSheet, parsePasteList } from '@/lib/data/projects-shared'

const TODAY = '2026-10-06'

describe('parsePasteList («Paste a list», PRJ-08)', () => {
  it('makes a task of every non-empty line and strips list markup', () => {
    expect(parsePasteList('Kickoff meeting\n\n  - Upload employee list\n• Configure departments\n1. Invite HR\n[ ] Review', TODAY).map((x) => x.name))
      .toEqual(['Kickoff meeting', 'Upload employee list', 'Configure departments', 'Invite HR', 'Review'])
  })

  it('takes a leading or trailing date as the due date and out of the name', () => {
    expect(parsePasteList('Upload employee list 16.10', TODAY)).toEqual([{ name: 'Upload employee list', due_on: '2026-10-16' }])
    expect(parsePasteList('16.10.2026 Upload employee list', TODAY)).toEqual([{ name: 'Upload employee list', due_on: '2026-10-16' }])
    expect(parsePasteList('Baseline sent — 22 Oct', TODAY)).toEqual([{ name: 'Baseline sent', due_on: '2026-10-22' }])
    expect(parsePasteList('Verneombud briefing 16. okt', TODAY)).toEqual([{ name: 'Verneombud briefing', due_on: '2026-10-16' }])
    expect(parsePasteList('2026-11-02: Result review', TODAY)).toEqual([{ name: 'Result review', due_on: '2026-11-02' }])
    expect(parsePasteList('Handover 3 desember 2026', TODAY)).toEqual([{ name: 'Handover', due_on: '2026-12-03' }])
  })

  it('puts a date without a year in the next year when it would lie more than half a year back', () => {
    expect(parsePasteList('Pilot report 15.01', '2026-12-10')).toEqual([{ name: 'Pilot report', due_on: '2027-01-15' }])
    expect(parsePasteList('Kickoff 01.10', TODAY)).toEqual([{ name: 'Kickoff', due_on: '2026-10-01' }])
  })

  it('leaves impossible dates and lines that are only a date alone', () => {
    expect(parsePasteList('Configure 31.02', TODAY)).toEqual([{ name: 'Configure 31.02', due_on: null }])
    expect(parsePasteList('16.10', TODAY)).toEqual([{ name: '16.10', due_on: null }])
  })

  it('stops at the limit the database takes', () => {
    expect(parsePasteList(Array.from({ length: 250 }, (_, i) => `Task ${i}`).join('\n'), TODAY)).toHaveLength(200)
  })
})

describe('timeline and export helpers', () => {
  it('turns a dragged distance into whole days on the range', () => {
    expect(dragDays(66, 660, 122)).toBe(12)
    expect(dragDays(-30, 660, 122)).toBe(-6)
    expect(dragDays(10, 0, 122)).toBe(0)
  })

  it('counts and adds calendar days', () => {
    expect(daysBetween('2026-09-30', '2026-10-06')).toBe(6)
    expect(addDays('2026-10-06', 10)).toBe('2026-10-16')
  })

  it('puts translated headers over the database rows', () => {
    expect(exportSheet(['seq', 'done'], [['P-1', true], ['P-2', null]], (k) => k.toUpperCase(), (_k, v) => (v === null ? '' : typeof v === 'boolean' ? (v ? 'Yes' : 'No') : v)))
      .toEqual([['SEQ', 'DONE'], ['P-1', 'Yes'], ['P-2', '']])
  })
})
