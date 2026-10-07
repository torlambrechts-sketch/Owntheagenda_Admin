'use client'

import Link from 'next/link'
import { useTranslations } from 'next-intl'
import { Icon } from '@/components/ui/Icon'
import { NAV, ROUTES, routeVisible, type RouteKey } from '@/lib/nav'
import type { ShellData } from './types'
import { ProductPicker } from './ProductPicker'

/** The left rail: brand, product picker, navigation, residency (Sentral Admin.dc.html, <aside>). */
export function Sidebar({ shell, route, product, open, onNavigate }: { shell: ShellData; route: RouteKey; product: string; open: boolean; onNavigate: () => void }) {
  const t = useTranslations('shell')
  return (
    <aside
      className={`${open ? 'flex' : 'hidden'} md:flex fixed md:sticky left-0 top-0 z-[75] md:z-auto h-screen w-[236px] flex-none flex-col overflow-hidden border-r border-line bg-surface`}
    >
      <div className="flex items-center gap-[10px] px-4 pb-[10px] pt-4">
        {/* eslint-disable-next-line @next/next/no-img-element -- the bundle's own mark, served as a static file */}
        <img src="/brand/orgpuls-mark.svg" alt="" width={30} height={30} className="block" />
        <div className="flex flex-col gap-px">
          <span className="font-serif text-19 font-semibold leading-none tracking-tightish">{t('brand')}</span>
          <span className="text-11 font-semibold text-muted">{t('brandSub')}</span>
        </div>
      </div>
      <ProductPicker shell={shell} product={product} />
      <nav aria-label={t('mainMenu')} className="flex-1 overflow-y-auto px-[10px] pb-[14px]">
        {NAV.map((g, gi) => {
          const who = { admin: shell.me.permission_kind === 'admin', rights: shell.me.rights, modules: shell.modules, meetingsWorkspace: shell.meetings_workspace }
          const items = g.items.filter((k) => routeVisible(k, who))
          if (!items.length) return null
          return (
            <div key={gi} className="mt-3 flex flex-col gap-px">
              {g.group ? (
                <div className="px-[10px] pb-[5px] pt-[2px] text-10.5 font-bold uppercase tracking-label text-faint">{t(`group.${g.group}`)}</div>
              ) : null}
              {items.map((k) => {
                const cur = k === route
                const badge = shell.badges[k]
                return (
                  <Link
                    key={k}
                    href={ROUTES[k].path as never}
                    onClick={onNavigate}
                    aria-current={cur ? 'page' : undefined}
                    className={`flex w-full cursor-pointer items-center gap-[10px] rounded-11 border-none px-2 py-[5px] text-left text-13.5 text-ink hover:text-ink hover:no-underline ${cur ? 'bg-highlight font-bold' : 'bg-transparent font-medium'}`}
                  >
                    <span className={`flex h-[26px] w-[26px] flex-none items-center justify-center rounded-8 ${cur ? 'bg-primary' : 'bg-tile'}`}>
                      <Icon name={ROUTES[k].icon} />
                    </span>
                    <span className="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap">{t(`nav.${k}`)}</span>
                    {badge ? (
                      <span className="flex h-[19px] min-w-[19px] items-center justify-center rounded-999 bg-alert px-[5px] text-10.5 font-bold text-surface">{badge}</span>
                    ) : null}
                  </Link>
                )
              })}
            </div>
          )
        })}
      </nav>
      <div className="flex items-center gap-2 border-t border-line px-[14px] py-[10px] text-11.5 text-muted">
        <span className="h-[7px] w-[7px] rounded-999 bg-ok" />
        <span>{t('residency')}</span>
      </div>
    </aside>
  )
}
