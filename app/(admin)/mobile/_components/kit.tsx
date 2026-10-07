'use client'

import Link from 'next/link'
import type { ReactNode } from 'react'

/**
 * The phone mock-up of Mobile.dc.html and its parts, transcribed: the 7 px ink frame with radius 38, the 30 px status
 * bar, the amber offline banner, the scrolling body (padding 10/14/14, gap 9), the cards (radius 14, padding 10/12,
 * gap 6) and the 56 px tab bar. Portrait 300 × 620, landscape 520 × 330 (border-box: the frame is inside).
 */
export type Tone = 'plain' | 'dark' | 'amber' | 'canvas'
const TONE: Record<Tone, string> = {
  plain: 'border-line bg-surface text-ink',
  dark: 'border-ink bg-ink text-canvas',
  amber: 'border-amber-bg bg-highlight text-ink',
  canvas: 'border-line bg-canvas text-ink',
}

export function Phone({ land, time, net, banner, title, label, ids, tabs, children }: {
  land: boolean; time: string; net: string; banner: ReactNode; title: string; label: string; ids: string; tabs: { g: string; n: string; on: boolean }[]; children: ReactNode
}) {
  const w = land ? 'w-[520px]' : 'w-[300px]'
  return (
    <div className="flex max-w-full flex-col items-center gap-2">
      <div className={`${w} ${land ? 'h-[330px]' : 'h-[620px]'} flex max-w-full flex-col overflow-hidden rounded-38 border-[7px] border-solid border-ink bg-canvas shadow-soft`}>
        <div className="flex h-[30px] flex-none items-center justify-between px-[18px] text-11 font-bold">
          <span>{time}</span>
          <span>{net}</span>
        </div>
        {banner}
        <div className="flex flex-1 flex-col gap-[9px] overflow-auto px-[14px] pb-[14px] pt-[10px]">
          <h2 className="m-0 font-serif text-20 font-semibold">{title}</h2>
          {children}
        </div>
        <div className="grid h-14 flex-none grid-cols-5 items-center border-t border-solid border-line bg-surface text-center text-9.5 font-bold" aria-hidden>
          {tabs.map((t) => (
            <span key={t.n} className={`flex flex-col items-center gap-[2px] ${t.on ? 'text-ink' : 'text-faint'}`}>
              <span className="text-14">{t.g}</span>
              {t.n}
            </span>
          ))}
        </div>
      </div>
      <span className="text-12 font-bold">{label}</span>
      <span className={`${land ? 'max-w-[520px]' : 'max-w-[300px]'} text-center text-11.5 text-muted`}>{ids}</span>
    </div>
  )
}

export function Banner({ text, action, onAction }: { text: string; action: string; onAction: () => void }) {
  return (
    <div className="flex justify-between gap-2 bg-amber-bg px-[14px] py-[6px] text-11 font-bold text-amber-ink">
      <span>{text}</span>
      <button type="button" onClick={onAction} className="cursor-pointer border-none bg-transparent p-0 text-11 font-bold text-amber-ink underline">{action}</button>
    </div>
  )
}

export function Card({ tone = 'plain', pad, eyebrow, big, t, s, children }: {
  tone?: Tone; pad?: string; eyebrow?: ReactNode; big?: ReactNode; t?: ReactNode; s?: ReactNode; children?: ReactNode
}) {
  return (
    <div className={`flex flex-col gap-[6px] rounded-14 border border-solid ${TONE[tone]} ${pad ?? 'px-3 py-[10px]'}`}>
      {eyebrow ? <span className="text-10 font-bold uppercase tracking-[.1em] opacity-75">{eyebrow}</span> : null}
      {big !== undefined && big !== null ? <span className="font-serif text-26 font-semibold leading-none">{big}</span> : null}
      {t ? <b className="text-12.5 leading-[1.3]">{t}</b> : null}
      {s ? <span className="text-11.5 leading-[1.4] opacity-80">{s}</span> : null}
      {children}
    </div>
  )
}

export const Btns = ({ children }: { children: ReactNode }) => <div className="flex flex-wrap gap-[6px]">{children}</div>

const btnCls = (primary?: boolean) =>
  `flex min-h-[44px] flex-1 cursor-pointer items-center justify-center rounded-12 border border-solid px-[10px] text-12 font-bold text-ink disabled:cursor-default disabled:opacity-60 ${primary ? 'border-ink bg-primary' : 'border-line bg-surface'}`

export function Btn({ primary, children, ...rest }: { primary?: boolean; children: ReactNode } & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type="button" {...rest} className={btnCls(primary)}>{children}</button>
}

/** A design button that hands off to another app (tel:, sms:, geo:) or opens a screen: a link styled as the button. */
export function BtnLink({ primary, href, children, onClick }: { primary?: boolean; href: string; children: ReactNode; onClick?: () => void }) {
  const cls = `${btnCls(primary)} hover:text-ink hover:no-underline`
  if (href.startsWith('/')) return <Link href={href as never} className={cls} onClick={onClick}>{children}</Link>
  return <a href={href} className={cls} onClick={onClick}>{children}</a>
}

/** Small inputs inside a phone card (the card scanner's review, the call prompt, a typed position). */
export const fieldCls = 'h-[34px] w-full rounded-10 border border-solid border-line bg-canvas px-[10px] text-12'
export const fieldLabel = 'flex flex-col gap-[3px] text-10.5 font-bold uppercase tracking-label text-muted'
