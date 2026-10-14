import { describe, expect, it } from 'vitest'
import { countryName } from '@/lib/growth/countries'

describe('a Search Console country by name (0091)', () => {
  it('names Google\'s three letters in the reader\'s language', () => {
    expect(countryName('nor', 'no')).toBe('Norge')
    expect(countryName('swe', 'no')).toBe('Sverige')
    expect(countryName('gbr', 'en')).toBe('United Kingdom')
    expect(countryName('USA', 'en')).toBe('United States')
    expect(countryName('xkk', 'en')).toBe('Kosovo')
  })
  it('has no name for «could not tell» or a code that is not a country', () => {
    expect(countryName('zzz', 'en')).toBeNull()
    expect(countryName('abc', 'no')).toBeNull()
  })
})
