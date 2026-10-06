/**
 * Numbers the way the design writes them (admin-data.js: nb, kr, pct) in the staff member's number format:
 * space_comma «12 345,67» (the design's own, with a no-break space), comma_dot «12,345.67», dot_comma
 * «12.345,67».
 */
export type NumberFormat = 'space_comma' | 'comma_dot' | 'dot_comma'

const SEP: Record<NumberFormat, [string, string]> = { space_comma: [' ', ','], comma_dot: [',', '.'], dot_comma: ['.', ','] }

export function formatNumber(n: number, f: NumberFormat = 'space_comma', decimals = 0): string {
  const [group, dec] = SEP[f]
  const neg = n < 0
  const fixed = Math.abs(n).toFixed(decimals)
  const [int, frac] = fixed.split('.')
  const grouped = int!.replace(/\B(?=(\d{3})+(?!\d))/g, group)
  return (neg ? '−' : '') + grouped + (frac ? dec + frac : '')
}

/** «64 000 kr» — whole kroner. Another currency is written with its code after the amount. */
export const money = (n: number, f: NumberFormat = 'space_comma', currency = 'NOK') =>
  `${formatNumber(Math.round(n), f)} ${currency === 'NOK' ? 'kr' : currency}`

/** «0,2 %» — one decimal, the decimal sign of the format. */
export const percent = (n: number, f: NumberFormat = 'space_comma') => {
  const r = Math.round(n * 10) / 10
  return `${formatNumber(r, f, Number.isInteger(r) ? 0 : 1)} %`
}

/** «98,4k» style abbreviation the overview uses for thousands. */
export const thousands = (n: number, f: NumberFormat = 'space_comma') => `${formatNumber(Math.round(n / 1000), f)}k`
