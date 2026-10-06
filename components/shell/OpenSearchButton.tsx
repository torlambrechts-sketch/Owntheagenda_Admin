'use client'

/** A control on a screen that opens the shell's ⌘K search (the design's «＋ New record» does this). */
export function OpenSearchButton({ className, children }: { className: string; children: React.ReactNode }) {
  return (
    <button type="button" className={className} onClick={() => window.dispatchEvent(new Event('sentral:search'))}>
      {children}
    </button>
  )
}
