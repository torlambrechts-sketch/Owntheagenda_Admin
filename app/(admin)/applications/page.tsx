import { PlatformPage } from './_components/PlatformPage'

/** Platform › Applications (Platform.dc.html, tab «apps»); also the Job monitor, Feature flags and Content tabs. */
export default function ApplicationsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return <PlatformPage route="applications" searchParams={searchParams} />
}
