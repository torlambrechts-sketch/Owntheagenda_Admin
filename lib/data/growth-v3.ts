import 'server-only'
import { rpc } from '@/lib/rpc'
import { CampaignDetail, SendTimes, SequenceResults } from '@/lib/growth/v3'

/**
 * Growth v3's reads (0083), parsed here; a refusal comes back as its code. The campaign card's days, ads and keywords
 * (21 days to yesterday, Europe/Oslo); an email sequence's last 30 days per step; the application's open rate by send
 * weekday and hour over 90 days.
 */
export const loadCampaignDetail = (id: string) => rpc('ad_campaign_detail', { p_campaign: id, p_days: 21 }, CampaignDetail)

export const loadSequenceResults = (id: string) => rpc('simple_sequence_results', { p_id: id, p_days: 30 }, SequenceResults)

export const loadSendTimes = (product: string) => rpc('email_send_times', { p_product: product, p_days: 90 }, SendTimes)
