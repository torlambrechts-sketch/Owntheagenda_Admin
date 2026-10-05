/**
 * Type-checks and deploys the edge functions in supabase/functions to the platform's project.
 *
 *   node scripts/functions.mjs --check   type-check only (deno check)
 *   node scripts/functions.mjs           type-check and deploy
 *
 * Deploys through the Management API with SB_MCP_PAT (or SUPABASE_ACCESS_TOKEN) from the environment.
 * `verify_jwt` is off for all three: orgpuls-events checks Orgpuls' HMAC signature, product-command checks
 * the caller itself (an aal2 admin through admin_whoami, or the service role), and secret-intake needs a
 * live one-time number.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const REF = process.env.PLATFORM_PROJECT_REF ?? 'zuvqbaejoktpekfsiyyr'
const TOKEN = process.env.SB_MCP_PAT ?? process.env.SUPABASE_ACCESS_TOKEN
const FUNCTIONS = ['orgpuls-events', 'product-command', 'secret-intake']
const SHARED = ['_shared/signing.ts', '_shared/orgpuls.ts', '_shared/secrets.ts']
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
