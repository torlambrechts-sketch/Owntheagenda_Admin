import type { Config } from 'tailwindcss'

/**
 * Tokens transcribed from the design bundle (design-reference/sentral/project, inline styles). Every hex
 * appears verbatim there; the names say where the design uses it. The radius and type scales are scales:
 * which step a component uses is part of its identity (a nav button is 11, a card 20, a chip round).
 */
const px = (xs: number[]) => Object.fromEntries(xs.map((x) => [String(x), `${x}px`]))

export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        canvas: '#FCF6E9', // page background, inputs
        surface: '#FFFDF6', // cards, sidebar, header, popovers
        ink: '#191510', // text, strong borders
        'ink-2': '#3A342A', // secondary strong text
        line: '#E8DFC9', // hairlines, card borders
        'line-mid': '#D9CFB8',
        'line-strong': '#C4BCA8', // chip outlines, chart axis
        muted: '#5F5849', // secondary text
        faint: '#8A8272', // tertiary text, placeholders
        tile: '#F2EAD6', // icon tiles, tracks
        beige: '#EFE6D2',
        wheat: '#F7EDD2',
        cream: '#FFFBEF', // changed-setting row
        highlight: '#FBEBBE', // selection, current nav item
        primary: '#F5C64A', // primary action, current nav tile
        link: '#2F5D2A',
        'link-hover': '#1E3D1A',
        ok: '#5C9A55', // status dot: fine
        'ok-ink': '#20431C',
        'ok-bg': '#CFE7E4',
        'teal-soft': '#E4EEEC',
        'teal-mid': '#9DB8B3',
        'teal-light': '#B5DAD4',
        aqua: '#A8D5D2',
        mint: '#F2F7EF',
        sage: '#DCEBD3',
        warn: '#E0A21F', // status dot: watch
        'warn-ink': '#8A6A00',
        'amber-bg': '#F5DC96',
        'amber-ink': '#5C4600',
        sand: '#F3E2C9',
        alert: '#D4633A', // badges, urgent
        danger: '#A33A16', // negative text
        rust: '#8A3A16',
        'rust-ink': '#6B240C',
        'rust-dark': '#5E1F09',
        'rust-darker': '#4A1706',
        salmon: '#F0B9A0',
        peach: '#FBD5C4',
        apricot: '#F6D9C6',
        coral: '#E38258',
        'coral-light': '#EC9B77',
        'blue-bg': '#CFE0F5',
        'blue-mid': '#6E8FB8',
        'blue-ink': '#1F3A5C',
        lilac: '#E7DAF2',
        'lilac-mid': '#8F74B3',
        'lilac-ink': '#3E2A5C',
      },
      fontFamily: {
        sans: ["'DM Sans'", 'Arial', 'sans-serif'],
        serif: ["'Playfair Display'", 'serif'],
      },
      fontSize: px([9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26, 28, 30, 32, 34, 40, 48, 56]),
      borderRadius: px([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 38, 999]),
      boxShadow: {
        pop: '0 18px 40px -24px rgba(25,21,16,.45)', // menus and popovers
        soft: '0 18px 40px -28px rgba(25,21,16,.35)',
        modal: '0 34px 80px rgba(25,21,16,.3)', // dialogs, drawers, the assistant
      },
      letterSpacing: {
        eyebrow: '.11em',
        label: '.09em',
        tightish: '-0.01em',
      },
    },
  },
  // no preflight: the prototype has no reset beyond box-sizing, and the baselines carry browser defaults
  corePlugins: { preflight: false },
  plugins: [],
} satisfies Config
