// The session-report edge function against the local stack (R-SECURITY-04). Run the function first:
//   SUPABASE_URL=http://127.0.0.1:54421 SUPABASE_SERVICE_ROLE_KEY=<local service key> \
//     npx deno run --allow-net --allow-env --config supabase/functions/deno.json supabase/functions/session-report/index.ts
// then: NEXT_PUBLIC_SUPABASE_URL=… NEXT_PUBLIC_SUPABASE_ANON_KEY=… node scripts/dev/session-report-e2e.mjs
// It writes a local Vault secret for the keyed checks and removes it again; it cleans up its own rows.
import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { totp } from './totp.mjs'
import { DEV_PASSWORD, DEV_TOTP } from '../seed/dev-credentials.mjs'

const DB = 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const sql = (q) => execFileSync('psql', [DB, '-qtAc', q], { encoding: 'utf8' }).trim()
const FN = 'http://localhost:8000'
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
const url = process.env.NEXT_PUBLIC_SUPABASE_URL
let fails = 0
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) fails++ }
const post = async (body, h = {}) => {
  const r = await fetch(FN, { method: 'POST', headers: { 'content-type': 'application/json', ...h }, body: JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}

const sb = createClient(url, anon, { auth: { persistSession: false } })
const { error: e1 } = await sb.auth.signInWithPassword({ email: 'ola@orgpuls.no', password: DEV_PASSWORD })
if (e1) throw e1
const aal1 = (await sb.auth.getSession()).data.session.access_token
const { data: f } = await sb.auth.mfa.listFactors()
const factorId = f.totp[0].id
const sid = JSON.parse(Buffer.from(aal1.split('.')[1], 'base64url')).session_id

let r = await post({ kind: 'login', outcome: 'success' }, { authorization: `Bearer ${aal1}` })
check(r.status === 401, 'a success at aal1 is refused')
r = await post({ kind: 'login', outcome: 'failed_mfa', user_agent: 'Mozilla/5.0 Chrome/129.0' }, { authorization: `Bearer ${aal1}` })
check(r.status === 200 && r.body.ok === false, 'a failed second factor at aal1 is recorded')
check(sql(`select count(*) from app.login_log where email_sha256 = app.email_hash('ola@orgpuls.no') and outcome = 'failed_mfa' and at > now() - interval '1 minute'`) === '1', 'the failed second factor is in the login log')

const { error: e2 } = await sb.auth.mfa.challengeAndVerify({ factorId, code: totp(DEV_TOTP) })
if (e2) throw e2
const aal2 = (await sb.auth.getSession()).data.session.access_token
r = await post({ kind: 'login', outcome: 'success', ip: '203.0.113.9', city: 'Bergen', country: 'NO', device_id: 'dev-1', user_agent: 'Mozilla/5.0 (Macintosh) Chrome/129.0' }, { authorization: `Bearer ${aal2}` })
check(r.status === 200 && r.body.ok === true, 'a sign-in at aal2 is allowed')
check(sql(`select ip_sealed is null and city is null and country is null and method = 'password_totp' and ended_at is null from app.staff_sessions where session_id = '${sid}'`) === 't',
  'without the report key the session is entered and its origin is unknown, not what the body claimed')
r = await post({ kind: 'login', outcome: 'success' }, { authorization: `Bearer ${aal2}` })
check(r.status === 200 && r.body.ok === true && sql(`select count(*) from app.login_log where session_id = '${sid}' and outcome = 'success'`) === '1', 'a repeated sign-in report is not logged twice')
r = await post({ kind: 'seen' }, { authorization: `Bearer ${aal2}` })
check(r.status === 200 && r.body.ok === true, 'seen: the session is still good')
r = await post({ kind: 'login', outcome: 'failed_password', email: 'tor@orgpuls.no' })
check(r.status === 403, 'a failed password without the report key is refused (nobody fills the log)')
r = await post({ kind: 'seen' }, { authorization: `Bearer ${aal2}`, 'x-report-key': 'wrong' })
check(r.status === 403, 'a wrong report key is refused')
r = await post({ kind: 'seen' }, { authorization: `Bearer ${anon}` })
check(r.status === 401, 'the anon key is nobody')

// the keyed server: its origin is believed
const key = randomBytes(32).toString('hex')
sql(`select vault.create_secret('${key}', 'session_report_token_secret', 'local e2e')`)
try {
  r = await post({ kind: 'seen', ip: '203.0.113.9' }, { authorization: `Bearer ${aal2}`, 'x-report-key': key })
  check(r.status === 200 && r.body.ok === true && sql(`select host(app.ip_open(last_ip_sealed)) from app.staff_sessions where session_id = '${sid}'`) === '203.0.113.9', 'with the report key the IP is recorded')
  r = await post({ kind: 'login', outcome: 'failed_password', email: 'nobody-e2e@orgpuls.no', ip: '203.0.113.10' }, { 'x-report-key': key })
  check(r.status === 200 && r.body.ok === false && sql(`select count(*) from app.login_log where email_sha256 = app.email_hash('nobody-e2e@orgpuls.no')`) === '1', 'the keyed server reports a failed password')
} finally {
  sql(`delete from vault.secrets where name = 'session_report_token_secret'`)
}

// the register ends the session: the next report says so
sql(`select app.session_end('${sid}', 'forced', null)`)
r = await post({ kind: 'seen' }, { authorization: `Bearer ${aal2}` })
check((r.status === 200 && r.body.ok === false && r.body.reason === 'forced') || r.status === 401, `a revoked session is reported ended (status ${r.status}, ${JSON.stringify(r.body)})`)

// cleanup of this run's rows (local only)
sql(`set app.purging = on; delete from app.login_log where email_sha256 in (app.email_hash('ola@orgpuls.no'), app.email_hash('nobody-e2e@orgpuls.no')) and at > now() - interval '10 minutes'; delete from app.staff_sessions where session_id = '${sid}'; delete from app.staff_devices where label is not null and first_seen_at > now() - interval '10 minutes'`)
console.log(fails ? `${fails} failed` : 'all passed')
process.exit(fails ? 1 : 0)
