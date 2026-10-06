import { loadSettings } from '@/lib/data/settings'
import { Coverage } from './_components/Coverage'

/**
 * Spec coverage (Coverage.dc.html): the brief's features, flows and the extended admin baseline, from the
 * design's own coverage data (lib/data/coverage-data.ts). The Settings tile counts the real register.
 */
export default async function CoveragePage() {
  const settings = await loadSettings()
  return <Coverage settingsCount={settings.length} />
}
