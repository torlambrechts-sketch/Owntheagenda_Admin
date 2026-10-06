import { ICON } from '@/lib/nav'

/** The design's stroke icons: a 24-unit path at the size the design gives it. */
export function Icon({ name, size = 15, width = 1.8, className, style }: { name: keyof typeof ICON; size?: number; width?: number; className?: string; style?: React.CSSProperties }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" className={className} style={style} aria-hidden="true">
      <path d={ICON[name]} />
    </svg>
  )
}
