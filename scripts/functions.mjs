/**
 * Type-checks and deploys the edge functions in supabase/functions to the platform's project.
 *
 *   node scripts/functions.mjs --check   type-check only (deno check)
 *   node scripts/functions.mjs           type-check and deploy
 *
 * Deploys through the Management API with SB_MCP_PAT (or SUPABASE_ACCESS_TOKEN) from the environment.
 * `verify_jwt` is off for all six: orgpuls-events checks Orgpuls' HMAC signature, product-command checks
 * the caller itself (an aal2 admin through admin_whoami, or the service role), secret-intake needs a
 * live one-time number, session-report checks the caller's own token with Auth (and the report key), and
 * storage-sign checks the caller's own aal2 token with Auth and asks worker_storage_check before it signs, and jobs-run
 * checks it likewise and asks worker_jobs_claim before it runs a transcript parse or a privacy package. mail-run takes the
 * cron's worker key or the owner's own token (email_provider_check_ready); mail-events takes Brevo's events key, a
 * one-click unsubscribe token, or the app's unsubscribe page's token. search-console-run takes the cron's worker key or the
 * owner's own token (search_console_check_ready). web-collect is the public site's beacon: it reads only an origin that
 * belongs to a registered site and answers 204 to everything. seo-crawl takes the nightly job's worker key or the
 * person's own token (seo_crawl_check_ready); pagespeed-run likewise (pagespeed_check_ready). ads-run takes the nightly job's
 * worker key or the owner's own token (ads_check_ready); ads-oauth is LinkedIn's redirect and needs the owner's one-time state.
 * ai-run takes the person's own token and asks ai_prepare (their right for the feature, the key, the hourly cap) before it
 * calls Claude. csat is public on purpose (0081): a customer answering «How satisfied are you?» from a resolution email has
 * no account here; the single-use token in the link (only its hash is stored, 30 days) is the authority, it accepts a score
 * 1–5 and nothing else, and only a person's click (Sec-Fetch-User) spends it.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const REF = process.env.PLATFORM_PROJECT_REF ?? 'zuvqbaejoktpekfsiyyr'
const TOKEN = process.env.SB_MCP_PAT ?? process.env.SUPABASE_ACCESS_TOKEN
const FUNCTIONS = ['orgpuls-events', 'product-command', 'secret-intake', 'session-report', 'storage-sign', 'jobs-run', 'mail-run', 'mail-events', 'search-console-run', 'web-collect', 'seo-crawl', 'pagespeed-run', 'ads-run', 'ads-oauth', 'ai-run', 'csat']
const SHARED = ['_shared/signing.ts', '_shared/orgpuls.ts', '_shared/secrets.ts', '_shared/zip.ts', '_shared/transcript.ts', '_shared/privacy-package.ts', '_shared/brevo.ts', '_shared/brevo-events.ts', '_shared/mail-render.ts', '_shared/mail-texts.gen.ts', '_shared/google.ts', '_shared/web-collect.ts', '_shared/seo-crawl.ts', '_shared/pagespeed.ts', '_shared/ads.ts', '_shared/csat.ts']
const ROOT = 'supabase/functions'

execFileSync('npx', ['-y', 'deno', 'check', '--config', `${ROOT}/deno.json`, ...FUNCTIONS.map((f) => `${ROOT}/${f}/index.ts`)], { stdio: 'inherit' })
if (process.argv.includes('--check')) process.exit(0)

if (!TOKEN) {
  console.error('SB_MCP_PAT (or SUPABASE_ACCESS_TOKEN) is not set; nothing deployed')
  process.exit(2)
}

for (const fn of FUNCTIONS) {
  const form = new FormData()
  form.append('metadata', new Blob([JSON.stringify({ name: fn, entrypoint_path: `${fn}/index.ts`, verify_jwt: false })], { type: 'application/json' }))
  for (const path of [`${fn}/index.ts`, ...SHARED]) {
    form.append('file', new Blob([readFileSync(`${ROOT}/${path}`)], { type: 'application/typescript' }), path)
  }
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=${fn}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}` },
    body: form,
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    console.error(`${fn}: deploy failed, HTTP ${res.status}: ${JSON.stringify(body).slice(0, 400)}`)
    process.exit(1)
  }
  console.log(`${fn}: version ${body.version}, ${body.status}, verify_jwt ${body.verify_jwt}`)
}
