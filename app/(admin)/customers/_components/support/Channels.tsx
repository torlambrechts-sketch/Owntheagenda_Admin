'use client'

import { useState } from 'react'
import { useTranslations } from 'next-intl'
import { formatNumber, type NumberFormat } from '@/lib/format'
import type { Channels } from '@/lib/data/support-hub'
import { card, Why } from './bits'
import { shares } from './logic'

const chip = (on: boolean) => `cursor-pointer whitespace-nowrap rounded-999 border px-[11px] py-[6px] text-12 text-ink ${on ? 'border-ink bg-highlight font-bold' : 'border-line-strong bg-transparent font-medium'}`
const input = 'rounded-10 border-[1.5px] border-ink bg-surface px-[11px] text-13'

/**
 * Contact form and email (SupportHub.dc.html, v.channels). The form is Orgpuls' own: its four topics and where each now goes
 * (0081, F-S1). The channel shares come from tickets.channel over 30 days; the email facts are the ones that hold.
 */
export function ChannelsView({ data, productName, nf, since }: { data: Channels; productName: string; nf: NumberFormat; since: Record<string, string> }) {
  const t = useTranslations('supportHub.channels')
  const dash = useTranslations('common')('dash')
  const [topic, setTopic] = useState(data.topics[0]?.topic ?? null)
  const route = data.topics.find((x) => x.topic === topic) ?? null
  const pct = shares(data.channels.map((c) => c.tickets))
  return (
    <div className="grid items-start gap-[14px] [grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr))]">
      <div className={`${card} flex flex-col gap-[10px] px-[18px] py-4`}>
        <b className="text-15">{t('form.title', { product: productName })}</b>
        <div className="flex flex-col gap-2 rounded-16 border border-line bg-canvas p-[14px]">
          <div className="flex flex-wrap gap-[6px]" role="group" aria-label={t('form.topicsLabel')}>
            {data.topics.map((x) => (
              <button key={x.topic} type="button" aria-pressed={topic === x.topic} onClick={() => setTopic(x.topic)} className={chip(topic === x.topic)}>
                {t.has(`topics.${x.topic}`) ? t(`topics.${x.topic}`) : x.topic}
              </button>
            ))}
          </div>
          <input readOnly tabIndex={-1} placeholder={t('form.org')} aria-label={t('form.org')} className={`h-[38px] ${input}`} />
          <input readOnly tabIndex={-1} placeholder={t('form.email')} aria-label={t('form.email')} className={`h-[38px] ${input}`} />
          <textarea readOnly tabIndex={-1} placeholder={t('form.message')} aria-label={t('form.message')} className={`min-h-[70px] py-[9px] ${input}`} />
        </div>
        {route ? (
          <span className="text-12 leading-[1.5] text-muted">
            {route.privacy ? t('form.routePrivacy', { queue: route.queue }) : t('form.route', { queue: route.queue, category: route.category })}
            {' '}
            {/* a count only when it is true: the reader sees the queue, and the topic was recorded for the whole period */}
            {route.tickets !== null ? t('form.count', { n: route.tickets, days: data.days })
              : !route.visible ? t('form.countHidden', { days: data.days, queue: route.queue })
                : t('form.countSince', { days: data.days, date: since[route.topic] ?? '' })}
          </span>
        ) : <Why>{t('form.noTopics', { product: productName })}</Why>}
        <Why>{t('form.note')}</Why>
      </div>
      <div className="flex flex-col gap-3">
        <div className={`${card} overflow-hidden`}>
          <div className="border-b border-line px-[18px] py-[13px] text-15 font-bold">{t('list.title')}</div>
          {data.channels.map((c, i) => (
            <div key={c.channel} className="grid items-center gap-[10px] border-b border-line px-[18px] py-[10px] text-12.5 [grid-template-columns:minmax(0,1.3fr)_minmax(0,1fr)_70px]">
              <span className="flex flex-col"><b>{t(`list.${c.channel}.name`)}</b><span className="text-11.5 text-muted">{t(`list.${c.channel}.sub`)}</span></span>
              <span className="text-muted">→ {c.queues.length ? c.queues.join(' / ') : dash}</span>
              <b className="text-right">{pct[i] === null || pct[i] === undefined ? dash : `${formatNumber(pct[i]!, nf)} %`}</b>
            </div>
          ))}
          <div className="px-[18px] py-[9px]"><Why>{t('list.note', { n: data.total, days: data.days })}</Why></div>
        </div>
        <div className={`${card} flex flex-col gap-[6px] px-[18px] py-[14px]`}>
          <b className="text-14">{t('threading.title')}</b>
          <span className="text-12.5 leading-[1.5]">{t('threading.body')}</span>
          <Why>
            {!data.mail?.ready ? t('threading.mailOff', { product: productName })
              : data.mail.inbound_ok && data.mail.inbound_domain ? t('threading.inboundOk', { domain: data.mail.inbound_domain })
                : t('threading.inboundOff')}
          </Why>
        </div>
      </div>
    </div>
  )
}
