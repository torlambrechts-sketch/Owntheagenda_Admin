# Orgpuls: tracking links (UTM) and the ads keyword list

Prepared 11 October 2026 for orgpuls.com. The links follow the convention Sentral already uses
(`AD_UTM` in `lib/data/simple-growth-shared.ts`, `app.channel_rules`), so every visit lands in the right
channel in Analytics › Web and Growth › Analytics without further setup.

## 1. How Sentral reads a link

| utm_medium / source | Channel in Sentral |
|---|---|
| `utm_medium=cpc` | Paid search |
| `utm_medium=paid_social` | Paid social |
| `utm_medium=email` or `utm_source=newsletter` | Email |
| `utm_source=partner-…` | Partner |
| no utm, referrer google / bing | Organic search |
| no utm, referrer linkedin / facebook | Social |
| anything else | Direct |

Rules of thumb:
- **Lower case, dashes, no spaces or æøå** in every value (`arbeidsmiljo`, not `Arbeidsmiljø`).
- **`utm_campaign` is the campaign's slug in Growth › Campaigns.** Create the campaign there first, then copy
  its tracking link. Spend you type in there is then set against the visits and signups of the same slug.
- **`utm_term` carries the search term.** Analytics › Web › «Paid search terms» shows which keyword
  brought each visit, and how far it got in signup.
- A link in an app (LinkedIn's app, Outlook, Slack) usually loses its referrer, so **without utm it counts as
  Direct**. Always tag links you post or send yourself.

## 2. Google Ads: one setting covers every ad

In Google Ads go to **Account settings → Tracking → Final URL suffix** (or set it per campaign) and add:

```
utm_source=google-ads&utm_medium=cpc&utm_campaign={_kampanje}&utm_term={keyword}&utm_content={creative}
```

Then add a **custom parameter** `_kampanje` on each campaign, with the campaign slugs below. `{keyword}` and
`{creative}` are filled in by Google on every click. Keep auto-tagging (gclid) on; Sentral ignores it.

| Campaign (Google Ads) | `_kampanje` / Sentral slug | Final URL (landing page) |
|---|---|---|
| Lovkrav – kartlegging | `lovkrav-kartlegging` | https://www.orgpuls.com/lovkrav |
| Medarbeiderundersøkelse | `medarbeiderundersokelse` | https://www.orgpuls.com/ |
| Anonymitet | `anonym-undersokelse` | https://www.orgpuls.com/artikler/anonym-medarbeiderundersokelse |
| Verneombud | `verneombud` | https://www.orgpuls.com/verneombud |
| Små bedrifter | `sma-bedrifter` | https://www.orgpuls.com/smaa-bedrifter |
| Maler (templates) | `maler` | https://www.orgpuls.com/maler |
| Bransjer (one ad group per industry) | `bransjer` | the industry's page (below) |

Industry pages: `/handel`, `/kunnskap-og-kontor`, `/bygg-og-anlegg`, `/barnehage-og-skole`, `/helse-og-omsorg`.

## 3. Ready-made links for everything else

Paste these as they are. Create a campaign with the same slug in Growth › Campaigns if you want its spend and
results side by side.

| Where | Link |
|---|---|
| LinkedIn ad (HR / daglig leder) | `https://www.orgpuls.com/?utm_source=linkedin&utm_medium=paid_social&utm_campaign=linkedin-hr-q4` |
| LinkedIn ad, legal requirements angle | `https://www.orgpuls.com/lovkrav?utm_source=linkedin&utm_medium=paid_social&utm_campaign=linkedin-lovkrav-q4` |
| Facebook / Instagram ad (SMB owners) | `https://www.orgpuls.com/smaa-bedrifter?utm_source=facebook&utm_medium=paid_social&utm_campaign=meta-smb-q4` |
| Your own LinkedIn posts (organic) | `https://www.orgpuls.com/artikler/nye-regler-psykososialt-arbeidsmiljo-2026?utm_source=linkedin&utm_medium=social&utm_campaign=linkedin-poster` |
| Newsletter / Brevo campaign | `https://www.orgpuls.com/maler?utm_source=newsletter&utm_medium=email&utm_campaign=nyhetsbrev-oktober` |
| Email outreach with a template | `https://www.orgpuls.com/maler/kartleggingspakken?utm_source=brevo&utm_medium=email&utm_campaign=outreach-maler` |
| Occupational health / HR partner | `https://www.orgpuls.com/?utm_source=partner-NAVN&utm_medium=referral&utm_campaign=partner-NAVN` (replace NAVN) |
| Webinar invitation | `https://www.orgpuls.com/?utm_source=webinar&utm_medium=event&utm_campaign=webinar-nye-regler-2026` |
| Email signature | `https://www.orgpuls.com/?utm_source=signatur&utm_medium=email&utm_campaign=signatur` |
| Directory listing (Capterra, G2 …) | `https://www.orgpuls.com/?utm_source=capterra&utm_medium=referral&utm_campaign=katalog` |

Note: `utm_medium=social` has no rule in Sentral yet, so tagged organic posts show as Direct under
channels. They still show under their own name in «Referrers and campaigns». Giving them their own channel
takes one row in `app.channel_rules` (`utm_medium = social → social`). There is no screen for the rules, so it
goes in through a migration.

## 4. Keyword list for Google Ads

Start with **phrase match** ("…") and **exact match** ([…]); add broad match only after two weeks of search-term
data. The **Search Console** column shows what Google already shows orgpuls.com for (last 30 days to 8 October).
Those are proven searches where an ad covers the gap until the page ranks. I have no search volumes, so none are
given; Google Ads' Keyword Planner shows them when the campaign is set up.

### Ad group: Lovkrav – kartlegging → /lovkrav
| Keyword | Match | Search Console today |
|---|---|---|
| kartlegging psykososialt arbeidsmiljø | phrase, exact | – |
| krav til kartlegging av arbeidsmiljø | phrase | – |
| risikovurdering psykososialt arbeidsmiljø | phrase, exact | 5 impressions, position 81 |
| arbeidsmiljøkartlegging | exact | 3 impressions, position 70 |
| kartlegging av arbeidsmiljø | phrase | 3 impressions, position 40 |
| medarbeiderundersøkelse lovpålagt | phrase | 8 impressions, position 44 |
| nye regler psykososialt arbeidsmiljø 2026 | phrase | – |
| arbeidstilsynet krav arbeidsmiljø | phrase | – |
| arbeidsmiljøloven kartlegging | phrase | – |

### Ad group: Medarbeiderundersøkelse → /
| Keyword | Match | Search Console today |
|---|---|---|
| medarbeiderundersøkelse | exact | – |
| medarbeiderundersøkelse verktøy | phrase | – |
| medarbeiderundersøkelse små bedrifter | phrase | – |
| arbeidsmiljøundersøkelse | exact, phrase | – |
| psykososialt arbeidsmiljø undersøkelse | phrase | 1 impression, position 77 |
| medarbeidertilfredshetsundersøkelse | exact | 5 impressions, position 72 |
| pulsundersøkelse verktøy | phrase | 1 impression, position 59 |
| medarbeiderundersøkelse spørsmål | phrase → /artikler/medarbeiderundersokelse-sporsmal | 5 impressions, position 44 |

### Ad group: Anonymitet → /artikler/anonym-medarbeiderundersokelse
| Keyword | Match | Search Console today |
|---|---|---|
| anonym medarbeiderundersøkelse | exact, phrase | 8 impressions, position 15.6 |
| medarbeiderundersøkelse anonymitet | phrase | 9 impressions, position 12.6 |
| anonym undersøkelse ansatte | phrase | – |

These two are close to page one organically. An ad there is cheap insurance, and the article is worth
strengthening so it reaches the top five.

### Ad group: Verneombud → /verneombud
| Keyword | Match | Search Console today |
|---|---|---|
| verneombud psykososialt arbeidsmiljø | phrase | 16 impressions, position 60 (the most seen search) |
| verneombud kartlegging | phrase | – |
| verneombudets rolle arbeidsmiljø | phrase | – |
| amu arbeidsmiljøundersøkelse | phrase | – |

### Ad group: Maler → /maler (and the right template page)
| Keyword | Match | Landing page |
|---|---|---|
| medarbeiderundersøkelse mal | phrase | /maler |
| risikovurdering psykososialt arbeidsmiljø mal | phrase | /maler/risikovurdering-psykososialt-arbeidsmiljo |
| årshjul hms / årshjul arbeidsmiljø | phrase | /maler/arshjul-arbeidsmiljo |
| tiltaksplan arbeidsmiljø | phrase | /maler/tiltaksbank |
| qps nordic spørreskjema | phrase | /maler/qpsnordic-sporreskjema |

### Ad group per industry → the industry page
`arbeidsmiljøundersøkelse barnehage`, `arbeidsmiljø helse og omsorg kartlegging`,
`psykososialt arbeidsmiljø bygg og anlegg`, `medarbeiderundersøkelse butikk`,
`arbeidsmiljøkartlegging kontor`, all phrase match.

### Negative keywords (account level)
`jobb`, `stilling`, `ledig`, `lønn`, `kurs`, `utdanning`, `bachelor`, `oppgave`, `eksamen`, `pdf`, `wikipedia`,
`definisjon`, `hva er`, `nav`, `sykemelding`, `varsling advokat`, `tilsynsrapport`, `sintef`, `fafo`, `stami`.
Read the search-term report every week and add more.

### Starting setup
- **Budget:** start small and spread it across the first three ad groups (Lovkrav, Medarbeiderundersøkelse,
  Anonymitet). Move money towards the groups whose visits send an organisation number (Analytics › Web ›
  «Paid search terms», column «Org. no.»).
- **Location / language:** Norway, Norwegian. **Network:** search only (Display off).
- **Ad text:** lead with the legal requirement and «gratis å starte» (free to start); the pages already say
  it. One ad per group should mention «rapport klar til Arbeidstilsynet» (report ready for the Labour
  Inspection Authority).
- **Conversion:** until Google Ads conversion tracking is set up, judge it in Sentral by «Org. no.» and
  «Completed» per search term.

## 5. What to watch in Sentral

- **Analytics › Web:** referrers and campaigns, paid search terms, landing pages (bounce → org. no. →
  completed), where visits end, and recent signup attempts.
- **Growth › Analytics:** the short version. «Sent org. number» now counts only real attempts.
- **Growth › SEO:** the tracked keywords. Add the six from the Search Console column above.

## 6. More signup detail: what Orgpuls' site must send

Sentral (0068) accepts these events from the site's existing tracker (`s(name, value)` in the beacon). The value is
a short code (`a-z 0-9 _ -`, at most 40 characters), **never something the person typed**: no org. number, name or
email address. Sentral drops anything else.

| Event | Value | When |
|---|---|---|
| `signup_step` | `step1_shown` | the form is shown (step 1, organisation) |
| `signup_step` | `org_found` | Brønnøysund returned the company (before step 2) |
| `signup_step` | `step2_shown` | step 2 «Deg» is shown |
| `signup_step` | `sso_google` / `sso_microsoft` | the person chose Google or Microsoft sign-in |
| `signup_error` | `org_invalid` | the org. number failed the client check (not 9 digits) |
| `signup_error` | `lookup_not_found` | Brønnøysund has no such company |
| `signup_error` | `lookup_failed` | the lookup failed (network or timeout) |
| `signup_error` | `step2_<code>` | step 2 refused (for example `step2_email_taken`, `step2_weak_password`) |
| `signup_error` | `google_failed` / `microsoft_failed` | SSO came back with an error |
| `persona_click` | `daglig_leder` / `hr` / `avdelingsleder` / `verneombud` | a «Hvem er du?» card was pressed |

`signup_started` (org. number sent) and `signup_completed` are already sent and stay as they are.
Analytics › Web then shows each attempt's steps and the error it stopped on, and counts errors by code.
