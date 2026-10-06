// Runs every supabase/tests/*.sql against a database rebuilt from the migrations and the seed (D-03).
// Each file raises on the first failed assertion; the exit code is the number of failed files.
// Usage: node scripts/db/run-tests.mjs [--db postgresql://…] [file …]
import { readdirSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const args = process.argv.slice(2)
const i = args.indexOf('--db')
const db = i >= 0 ? args.splice(i, 2)[1] : process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54422/postgres'
const files = args.length ? args : readdirSync('supabase/tests').filter((f) => f.endsWith('.sql')).sort().map((f) => `supabase/tests/${f}`)
let failed = 0
for (const f of files) {
  const r = spawnSync('psql', [db, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-f', f], { encoding: 'utf8' })
  const notices = (r.stderr ?? '').split('\n').filter((l) => /NOTICE:\s+ok/.test(l)).length
  if (r.status === 0) console.log(`ok   ${f} (${notices} checks)`)
  else {
    failed++
    console.log(`FAIL ${f}\n${(r.stderr ?? '').split('\n').filter((l) => !/NOTICE:\s+ok/.test(l)).join('\n')}`)
  }
}
process.exit(failed)
