'use client'

/** The design's switch (Settings › Modules, activity types): 42×24 track, 16 px knob at 3 or 21. */
export function Switch({ on, onChange, label, disabled }: { on: boolean; onChange: (on: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative h-6 w-[42px] cursor-pointer rounded-999 border-none disabled:cursor-default disabled:opacity-60 ${on ? 'bg-ink' : 'bg-line-strong'}`}
    >
      <span className="absolute top-[3px] h-4 w-4 rounded-999 bg-surface" style={{ left: on ? 21 : 3 }} />
    </button>
  )
}
