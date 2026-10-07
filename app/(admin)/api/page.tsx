import { PlatformPage } from '../applications/_components/PlatformPage'

/** Platform › API and integrations (Platform.dc.html, tab «api»); also Webhooks, Integration catalog and AI connector. */
export default function ApiPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return <PlatformPage route="api" searchParams={searchParams} />
}
