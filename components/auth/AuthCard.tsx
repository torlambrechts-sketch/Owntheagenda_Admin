import { getTranslations } from 'next-intl/server'

/**
 * Sign-in, second factor and no-access pages. The design has no screen for them (D-41): they are built in
 * its language — the canvas, a surface card, the brand mark and the serif title. A page a customer reaches from an
 * application's email (the unsubscribe page) passes `sender`: the card then names that sender only, never Sentral.
 */
export async function AuthCard({ title, children, sender }: { title: string; children: React.ReactNode; sender?: { name: string | null } }) {
  const t = await getTranslations('shell')
  return (
    <main className="flex min-h-screen items-start justify-center bg-canvas px-4 pt-[12vh] font-sans text-14 text-ink">
      <div className="flex w-full max-w-[400px] flex-col gap-[18px] rounded-20 border border-line bg-surface px-[26px] py-6">
        {sender ? (
          sender.name ? <span className="font-serif text-19 font-semibold leading-none tracking-tightish">{sender.name}</span> : null
        ) : (
          <div className="flex items-center gap-[10px]">
            {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's own mark */}
            <img src="/brand/orgpuls-mark.svg" alt="" width={30} height={30} className="block" />
            <div className="flex flex-col gap-px">
              <span className="font-serif text-19 font-semibold leading-none tracking-tightish">{t('brand')}</span>
              <span className="text-11 font-semibold text-muted">{t('brandSub')}</span>
            </div>
          </div>
        )}
        <h1 className="m-0 font-serif text-24 font-semibold leading-[1.12]">{title}</h1>
        {children}
      </div>
    </main>
  )
}

