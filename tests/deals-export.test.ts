import { describe, expect, it } from 'vitest'
import { toCsv, toXlsx } from '@/app/(admin)/deals/_components/xlsx'

describe('deal list export', () => {
  it('neutralizes cells a spreadsheet would read as a formula and quotes separators', () => {
    const csv = toCsv([['Title', 'Value'], ['=HYPERLINK("x")', 64000], ['+47 22 00', 1], ['Lumio, AS', 2], ['@sum', 3], ['-1', 4]])
    const lines = csv.split('\r\n')
    expect(lines[0]).toBe('Title,Value')
    expect(lines[1]).toBe(`"'=HYPERLINK(""x"")",64000`)
    expect(lines[2]).toBe(`'+47 22 00,1`)
    expect(lines[3]).toBe('"Lumio, AS",2')
    expect(lines[4]).toBe(`'@sum,3`)
    expect(lines[5]).toBe(`'-1,4`)
  })

  it('writes a zip with the workbook parts and a valid central directory', async () => {
    const blob = toXlsx([['Title', 'Value'], ['Lumio <AS> & co', 64000]], 'Deals')
    const bytes = new Uint8Array(await blob.arrayBuffer())
    const view = new DataView(bytes.buffer)
    expect(view.getUint32(0, true)).toBe(0x04034b50)
    const end = bytes.length - 22
    expect(view.getUint32(end, true)).toBe(0x06054b50)
    expect(view.getUint16(end + 10, true)).toBe(5)
    const text = new TextDecoder().decode(bytes)
    expect(text).toContain('xl/worksheets/sheet1.xml')
    expect(text).toContain('Lumio &lt;AS&gt; &amp; co')
    expect(text).toContain('<v>64000</v>')
  })
})
