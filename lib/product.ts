import 'server-only'
import { cookies } from 'next/headers'
import type { Shell } from '@/lib/shell'

/**
 * The application the simple interface is scoped to: the `product` cookie when it names a product, else the first
 * installed and enabled one, else the first known. Sentral Simple has no «all applications» (its picker lists products
 * only); the full interface's screens still read the cookie themselves and accept «all».
 */
export async function currentProduct(shell: Shell): Promise<string> {
  const chosen = (await cookies()).get('product')?.value
  if (chosen && shell.products.some((p) => p.key === chosen)) return chosen
  return (shell.products.find((p) => p.installed && p.enabled) ?? shell.products[0])?.key ?? 'orgpuls'
}
