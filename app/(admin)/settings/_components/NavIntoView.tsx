'use client'

import { useEffect } from 'react'

/** On a phone the section nav is a row that scrolls sideways: bring the current section into view. */
export function NavIntoView({ sec }: { sec: string }) {
  useEffect(() => {
    document.querySelector('nav[data-settings-nav] [aria-current="page"]')?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }, [sec])
  return null
}
