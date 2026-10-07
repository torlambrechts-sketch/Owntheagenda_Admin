import { z } from 'zod'
import { rpc } from '@/lib/rpc'

/**
 * «API reference»: the OpenAPI 3.1 document the database generates from the record registry (INT-01, api_definition),
 * for the signed-in staff member (the middleware requires aal2 here as on every admin path). It describes the API; it
 * holds no record and no secret.
 */
export async function GET() {
  const r = await rpc('api_definition', {}, z.object({ openapi: z.string() }).passthrough())
  if (!r.ok) return new Response(JSON.stringify({ error: r.code }), { status: r.code === 'not_signed_in' ? 401 : 403, headers: { 'content-type': 'application/json' } })
  return new Response(JSON.stringify(r.data, null, 2), {
    headers: { 'content-type': 'application/json; charset=utf-8', 'content-disposition': 'attachment; filename="sentral-openapi.json"', 'cache-control': 'no-store' },
  })
}
