// A local stand-in for the hosted project's /functions/v1: the local stack runs no edge runtime, so each function runs under
// Deno on its own port and this proxy sends /functions/v1/<name> there and everything else (Auth, PostgREST, Storage) to the
// local API. Point a dev server's NEXT_PUBLIC_SUPABASE_URL at it. Local development only.
//
//   PORT=54431 FUNCTIONS=jobs-run=8124,storage-sign=8125,session-report=8126 node scripts/dev/functions-proxy.mjs
import http from 'node:http'

const PORT = Number(process.env.PORT ?? 54431)
const API = Number(process.env.API_PORT ?? 54421)
const routes = Object.fromEntries((process.env.FUNCTIONS ?? 'jobs-run=8124,storage-sign=8125,session-report=8126').split(',').map((x) => {
  const [name, port] = x.split('=')
  return [name, Number(port)]
}))

http.createServer((req, res) => {
  const m = /^\/functions\/v1\/([a-z0-9-]+)(\/.*)?$/.exec(req.url ?? '')
  const fn = m ? routes[m[1]] : undefined
  if (m && !fn) {
    res.writeHead(404, { 'content-type': 'application/json' })
    res.end('{"error":"not_deployed"}')
    return
  }
  const up = http.request(
    { host: '127.0.0.1', port: fn ?? API, path: fn ? (m[2] ?? '/') : req.url, method: req.method, headers: { ...req.headers, host: `127.0.0.1:${fn ?? API}` } },
    (r) => { res.writeHead(r.statusCode ?? 502, r.headers); r.pipe(res) },
  )
  up.on('error', () => { if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' }); res.end('{"error":"unreachable"}') })
  req.pipe(up)
}).listen(PORT, '127.0.0.1', () => console.log(`functions proxy on http://127.0.0.1:${PORT} → ${JSON.stringify(routes)}, API :${API}`))
