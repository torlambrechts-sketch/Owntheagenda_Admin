/**
 * An application's link address (0063): https://post.<its domain>, the same deployment as Sentral. On such a host the
 * app serves the unsubscribe page and nothing else, so a customer who follows a link from an Orgpuls email never meets
 * Sentral's sign-in. Pure, for the middleware (edge) and the tests.
 */
export const isLinkHost = (host: string | null | undefined) => /^post\.[a-z0-9.-]+(:\d+)?$/i.test(host ?? '')

/** may this path be served on this host? Anywhere but a link host: yes (the usual checks follow); on one: /u only */
export const servedOnHost = (host: string | null | undefined, path: string) => !isLinkHost(host) || path === '/u' || path.startsWith('/u/')
