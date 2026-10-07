// Phase 8 · Platform (Platform.dc.html, tabs Applications … Content): the design's configuration fixtures that a staff member
// could have made through the screen, and nothing that only a connected service could have produced.
//
// Nothing external is connected (no API gateway, no OAuth or MCP endpoints, no webhook delivery worker, no product ping, no
// product command worker), so no row may claim one of them did something. Left out, and logged in
// docs/crm-enrichment/deviations/platform.md (V-PLATFORM-*):
// - integration calls, product events, API usage and job runs: measurements, not configuration (the sparklines, req/min, p95,
//   the usage bars and the job rows are read live; job runs come from the real cron);
// - OAuth grants and MCP assistants: a grant is issued only by the token endpoint, which is not deployed;
// - webhook deliveries and the «Retrying» and «Blocked» states: only the delivery worker produces them. The design's
//   «http://10.0.4.2/internal» subscription cannot be saved at all (app.url_public), so it is not seeded;
// - bulk changes (Contacts › Restore): a change log needs the records it changed at the versions it left them.
//
// Secrets: no token, client secret or webhook secret plaintext exists anywhere. A seeded token or client secret is a hash of
// random bytes drawn when the database is built, so nobody holds a value that matches it; the «last four» are the design's.
// A seeded webhook names a Vault secret that was never created: the worker would refuse its deliveries (no_secret), and the
// owner re-creates the webhook to get a signing secret.
//
// Every row passes the schema's checks: check them with triggers on in a rolled-back session.

export function seedPlatform({ sql, q, uid }) {
  const staff = (id) => q(uid('staff', id))
  const ago = (days) => `(now() - interval '${days} days')`
  const randomHash = `extensions.digest(extensions.gen_random_bytes(32), 'sha256')`

  // the design's installed set (installed: gw, m365, slack, acc). Slack and the accounting system stay «not connected»
  for (const [key, days] of [['gw', 120], ['m365', 120], ['slack', 60], ['acc', 30]]) {
    sql(`insert into app.installed_apps (key, installed_by, installed_at) values (${q(key)}, ${staff('tor')}, ${ago(days)});`)
  }

  // personal tokens (Tor, Ingrid): never used, because no gateway could have served a call
  for (const [who, last4, days] of [['tor', 'f3a9', 14], ['ingrid', '82bd', 40]]) {
    sql(`insert into app.api_tokens (id, staff_id, name, token_sha256, last4, created_at) values (${q(uid('api-token', who))}, ${staff(who)}, 'Personal token', ${randomHash}, ${q(last4)}, ${ago(days)});`)
  }

  // two registered OAuth apps (Zapier, the accounting system), confidential, with no grants
  const apps = [
    ['zapier', 'Zapier', ['https://zapier.com/dashboard/auth/oauth/return/App/'], ['deals:read', 'deals:write'], 21],
    ['accounting', 'Accounting', ['https://accounting.example.no/oauth/callback'], ['deals:read'], 18],
  ]
  for (const [k, name, uris, scopes, days] of apps) {
    const client = `client_${uid('oauth-client', k).replace(/-/g, '').slice(0, 24)}`
    sql(`insert into app.oauth_apps (id, client_id, name, kind, owner_id, redirect_uris, client_secret_sha256, allowed_scopes, created_at)
  values (${q(uid('oauth-app', k))}, ${q(client)}, ${q(name)}, 'integration', ${staff('tor')}, array[${uris.map(q).join(', ')}]::text[], ${randomHash}, array[${scopes.map(q).join(', ')}]::text[], ${ago(days)});`)
  }

  // three of the design's four subscriptions, under the kinds the platform emits («person.added» is person.created)
  const hooks = [
    ['h1', 'tor', 'deal.updated', 'https://hooks.zapier.com/hooks/catch/8823', 20],
    ['h2', 'ingrid', 'person.created', 'https://crm-sync.lumio.no/hook', 35],
    ['h3', 'tor', 'deal.won', 'https://api.skiftly.no/v1/provision', 9],
  ]
  for (const [k, who, kind, url, days] of hooks) {
    sql(`insert into app.webhooks (id, owner_id, event_kind, url, vault_secret_id, created_at, updated_at)
  values (${q(uid('webhook', k))}, ${staff(who)}, ${q(kind)}, ${q(url)}, ${q(uid('webhook-secret-none', k))}, ${ago(days)}, ${ago(days)});`)
  }

  // Orgpuls' status banner, linked to the known error T-2316; not yet sent, since no product command worker runs
  sql(`insert into app.status_notices (id, product, text, problem_ticket_id, set_by, set_at)
  values (${q(uid('status-notice', 'orgpuls'))}, 'orgpuls', 'Noen invitasjoner til kommunale e-postdomener kommer forsinket frem. Vi jobber med saken.',
  (select id from app.tickets where type = 'problem' and subject = 'Mail provider rejecting @kommune.no domains'), ${staff('tor')}, now() - interval '2 hours');`)
}
