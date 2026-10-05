import type { Config } from 'tailwindcss'

// Placeholder tokens: the platform's own design replaces these (README, «Design»).
export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: { extend: {} },
  plugins: [],
} satisfies Config
