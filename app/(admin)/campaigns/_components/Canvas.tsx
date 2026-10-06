'use client'

import { useTranslations } from 'next-intl'
import { EMAIL_WORDS } from '@/lib/data/campaigns-render'
import { BG_HEX, itemHref, itemLabel, type Design, type Row } from '@/lib/data/campaigns-shared'

export type Brand = { name: string; color: string | null; mark: boolean }

const stripes = 'repeating-linear-gradient(135deg,#F2EAD6 0 10px,#FCF6E9 10px 20px)'
const padOf = (r: Row) => (r.kind === 'divider' ? `6px ${r.padding ?? 22}px` : `${Math.max(0, (r.padding ?? 22) - 6)}px ${r.padding ?? 22}px`)

/**
 * The builder's canvas (Marketing.dc.html, blocks): each row drawn as the design draws it, picked by click or
 * keyboard. It shows the author what they edit; the email itself is the renderer's output (Preview).
 */
export function Canvas({ design, selected, onPick, width, brand, footer, readOnly }: {
  design: Design
  selected: number
  onPick: (i: number) => void
  width: number
  brand: Brand
  footer: { address: string | null; sender: string; stream: string | null }
  readOnly?: boolean
}) {
  return (
    <div className="max-w-full overflow-hidden rounded-14 border border-line bg-surface shadow-soft" style={{ width }}>
      {design.rows.map((r, i) => (
        <div
          key={i}
          role="button"
          tabIndex={0}
          aria-pressed={selected === i}
          aria-label={r.kind}
          onClick={() => onPick(i)}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onPick(i) } }}
          className={`relative ${readOnly ? 'cursor-default' : 'cursor-pointer'}`}
          style={{
            padding: r.kind === 'footer' ? '16px 22px' : padOf(r),
            background: BG_HEX[r.bg ?? (r.kind === 'footer' ? 'cream' : 'card')],
            outline: selected === i && !readOnly ? '2px solid #191510' : 'none',
            outlineOffset: -2,
            borderTop: r.border === 'hairline' ? '1px solid #E8DFC9' : undefined,
            borderBottom: r.border === 'hairline' ? '1px solid #E8DFC9' : undefined,
          }}
        >
          <Block r={r} brand={brand} footer={footer} />
        </div>
      ))}
    </div>
  )
}

function Empty({ children }: { children: React.ReactNode }) {
  return <span className="text-faint">{children}</span>
}

function Block({ r, brand, footer }: { r: Row; brand: Brand; footer: { address: string | null; sender: string; stream: string | null } }) {
  const t = useTranslations('campaigns.builder.canvas')
  const items = (r.items ?? []).filter((x) => itemLabel(x).trim())
  switch (r.kind) {
    case 'header':
      return (
        <div className="flex items-center justify-between gap-3">
          <span className="flex items-center gap-2">
            {brand.mark ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src="/brand/orgpuls-mark.svg" alt="" width={24} height={24} />
            ) : brand.color ? <span className="inline-block h-6 w-6 rounded-6" style={{ background: brand.color }} /> : null}
            <b className="font-serif text-17">{brand.name || '—'}</b>
          </span>
          <span className="text-11 text-muted">{r.text}</span>
        </div>
      )
    case 'title':
      return <div className="whitespace-pre-line font-serif font-semibold leading-[1.15]" style={{ fontSize: r.fs ?? 22 }}>{r.text?.trim() ? r.text : <Empty>{t('emptyTitle')}</Empty>}</div>
    case 'paragraph':
      return <div className="whitespace-pre-line text-13.5 leading-[1.65] text-ink-2">{r.text?.trim() ? r.text : <Empty>{t('emptyText')}</Empty>}</div>
    case 'image':
      return r.src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={r.src} alt={r.alt ?? ''} className="block max-w-full rounded-10" />
      ) : (
        <div className="flex h-[150px] items-center justify-center rounded-10 font-mono text-11 text-muted" style={{ background: stripes }}>{r.alt?.trim() || t('noImage')}</div>
      )
    case 'video':
      return (
        <div className="flex h-[150px] items-center justify-center rounded-10 font-mono text-11 text-muted" style={{ background: stripes }}>
          ▶ {r.href ? r.href : t('noVideo')}
        </div>
      )
    case 'button':
      return (
        <div className="flex justify-center">
          <span className="inline-flex h-[42px] items-center rounded-12 border border-ink bg-primary px-5 text-14 font-bold">{r.text?.trim() ? r.text : t('emptyButton')}</span>
        </div>
      )
    case 'divider':
      return <div className="h-px bg-line" />
    case 'list':
      return items.length ? (
        <div className="flex flex-col gap-[6px] text-13">{items.map((x, i) => <span key={i}>✓ {itemLabel(x)}</span>)}</div>
      ) : <span className="text-13"><Empty>{t('emptyList')}</Empty></span>
    case 'social':
    case 'menu':
    case 'icons':
      return items.length ? (
        <div className="flex flex-wrap justify-center gap-[10px] text-12 font-bold">
          {items.map((x, i) => <span key={i} className={itemHref(x) ? '' : 'text-faint'}>{r.kind === 'icons' ? '● ' : ''}{itemLabel(x)}</span>)}
        </div>
      ) : <div className="text-center text-12"><Empty>{t('emptyItems')}</Empty></div>
    case 'html':
      return (
        <div className="overflow-hidden text-ellipsis whitespace-nowrap rounded-8 bg-ink p-[10px] font-mono text-11.5 text-tile">
          {r.html?.trim() ? `${r.html.trim().slice(0, 70)}${r.html.trim().length > 70 ? '…' : ''}` : t('emptyHtml')} · {t('sanitized')}
        </div>
      )
    case 'footer':
      return (
        <div className="text-center text-11 leading-[1.6] text-muted">
          {footer.address ? <>{footer.address} · </> : <span className="font-bold text-danger">{t('noAddress')} · </span>}
          {EMAIL_WORDS.nb.reason.replace('{name}', footer.sender || '—')}
          <br />
          <u>{EMAIL_WORDS.nb.unsubscribe}</u>{footer.stream ? <> · {t(`footerStream.${footer.stream}`)}</> : null}
        </div>
      )
  }
}
