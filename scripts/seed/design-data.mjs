// Loads the design's own demo data (design-reference/sentral/project/admin-data.js) exactly as the
// prototype does: a deterministic generator that sets window.SA. The seed is built from it so the
// development database shows the scenario the design was drawn with (D-02).
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'

const file = fileURLToPath(new URL('../../design-reference/sentral/project/admin-data.js', import.meta.url))

export function designData() {
  const window = {}
  vm.runInNewContext(readFileSync(file, 'utf8'), { window })
  return window.SA
}
