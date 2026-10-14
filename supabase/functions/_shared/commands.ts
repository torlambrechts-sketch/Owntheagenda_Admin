import { LEADERPACT_COMMANDS } from './leaderpact.ts'
import { ORGPULS_COMMANDS } from './orgpuls.ts'
import type { CommandClaims } from './signing.ts'

/**
 * The products product-command may reach, each with its command registry (command → the one scope it needs). A product
 * is reached only when it is here, has an enabled installation and its token secret is in Vault (`<product>_token_secret`);
 * app.product_commands mirrors each list for command_authorize (tests/product-commands.test.ts asserts equality).
 */
export const PRODUCT_COMMANDS = {
  orgpuls: ORGPULS_COMMANDS,
  leaderpact: LEADERPACT_COMMANDS,
} as const

export type CommandProduct = keyof typeof PRODUCT_COMMANDS
export type ProductCommand<P extends CommandProduct> = keyof (typeof PRODUCT_COMMANDS)[P] & string

const own = (o: object, k: string) => Object.prototype.hasOwnProperty.call(o, k)

export const isCommandProduct = (p: unknown): p is CommandProduct => typeof p === 'string' && own(PRODUCT_COMMANDS, p)

export const isProductCommand = <P extends CommandProduct>(product: P, c: unknown): c is ProductCommand<P> =>
  typeof c === 'string' && own(PRODUCT_COMMANDS[product], c)

/** the scope a command needs at its product */
export const commandScope = <P extends CommandProduct>(product: P, command: ProductCommand<P>): string =>
  (PRODUCT_COMMANDS[product] as Record<ProductCommand<P>, string>)[command]

/** two minutes is ample for one call; a product accepts at most five. The audience is the product itself. */
export function commandClaims<P extends CommandProduct>(product: P, actor: string, command: ProductCommand<P>, nowSec: number, jti: string): CommandClaims {
  return { aud: product, sub: actor.slice(0, 254), scope: commandScope(product, command), jti, iat: nowSec, exp: nowSec + 120 }
}
