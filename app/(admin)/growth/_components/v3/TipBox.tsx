import type { ReactNode } from 'react'

/**
 * A tip (GrowthMarketing.dc.html, cur.tips[] and emailTips[]): radius 12 on the highlight yellow, the text, and one
 * button at 28 px. The action is a link to an ad platform (`href`, X-V3-3: the change is made there), a button that does
 * something in Sentral (`onClick`), or a button that is off with its reason in sight (`reason`).
 */
export function TipBox({ text, cta, href, title, onClick, disabled, reason }: {
  text: ReactNode
  cta: string
  href?: string
  title?: string
  onClick?: () => void
  disabled?: boolean
  reason?: string | null
}) {
  const btn = 'flex h-7 flex-none cursor-pointer items-center whitespace-nowrap rounded-8 border border-ink bg-surface px-[10px] text-11.5 font-bold text-ink'
  return (
    <div className="flex flex-wrap items-start gap-[10px] rounded-12 bg-highlight px-[11px] py-[9px] text-12.5 leading-[1.45]">
      {/* the button wraps under the text only when the text would be squeezed below 200 px (a phone) */}
      <span className="flex min-w-0 flex-[1_1_200px] flex-col gap-[2px]">
        <span>{text}</span>
        {reason ? <span className="text-11.5 text-muted">{reason}</span> : null}
      </span>
      {href ? (
        <a href={href} target="_blank" rel="noopener noreferrer" title={title} className={`${btn} hover:text-ink hover:no-underline`}>{cta}</a>
      ) : (
        <button type="button" onClick={onClick} disabled={disabled} title={reason ?? title} className={`${btn} disabled:cursor-not-allowed disabled:opacity-50`}>{cta}</button>
      )}
    </div>
  )
}
