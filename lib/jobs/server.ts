import 'server-only'
import { accessToken } from '@/lib/storage/server'
import { runJob, type JobRequest, type JobRun } from './run'

/** Run one job (a transcript parse, a privacy package) for the signed-in staff member (see lib/jobs/run.ts). */
export async function runJobForMe(request: JobRequest): Promise<JobRun> {
  return runJob(await accessToken(), request)
}
