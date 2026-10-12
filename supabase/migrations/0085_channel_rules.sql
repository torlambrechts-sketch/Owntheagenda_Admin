-- 0085_channel_rules.sql — a tagged link no longer counts as «Direct».
--
-- app.channel_of reads app.channel_rules in order and falls back to «direct». The rules (0025, 0073) knew utm_medium
-- cpc, paid_social and email, utm_source newsletter and partner…, and Google, Bing, LinkedIn and Facebook as referrers.
-- Everything else carrying a tag fell through to «direct»: a LinkedIn post linked as utm_source=linkedin&utm_medium=social,
-- and Sentral's own campaign links for a webinar (utm_medium=event) and «other» (utm_medium=referral) — while «direct»
-- is meant to be a visit nobody sent. Checked on 12 Oct 2026 (Tor: «all sources is Direct — I find it hard to believe»):
-- the website sends the referring host and the database stores it; none of the first 61 sessions on orgpuls.com carried
-- a referrer or a tag, so their «Direct» stands. This makes the next tagged visits land where they belong.
--
-- New rules, by their order among the old ones (10 cpc … 90 partner…, 950 any referrer, 1000 direct):
-- - the common spellings of a paid search, a paid social, an e-mail and a social medium;
-- - more search engines and social sites as referrers (DuckDuckGo, Yahoo, Ecosia, Yandex; Instagram, X/Twitter,
--   YouTube, TikTok, LinkedIn's short links);
-- - a social network named as utm_source without a medium;
-- - utm_medium=referral or event, and then any other tagged visit, as «referral»: it was sent by a link, so not direct.
-- Rules are data; nothing else changes. Sessions already classed «direct» that carry a referrer or a tag are classed
-- again by the same function.

insert into app.channel_rules (ord, match, channel)
select v.ord, v.match::jsonb, v.channel
from (values
  (11, '{"utm_medium":"ppc"}', 'paid_search'),
  (12, '{"utm_medium":"paidsearch"}', 'paid_search'),
  (13, '{"utm_medium":"paid_search"}', 'paid_search'),
  (14, '{"utm_medium":"paid-search"}', 'paid_search'),
  (21, '{"utm_medium":"paidsocial"}', 'paid_social'),
  (22, '{"utm_medium":"paid-social"}', 'paid_social'),
  (31, '{"utm_medium":"e-mail"}', 'email'),
  (32, '{"utm_medium":"newsletter"}', 'email'),
  (33, '{"utm_source":"brevo"}', 'email'),
  (45, '{"utm_medium":"social"}', 'social'),
  (46, '{"utm_medium":"social-media"}', 'social'),
  (47, '{"utm_medium":"social_media"}', 'social'),
  (48, '{"utm_medium":"organic_social"}', 'social'),
  (61, '{"referrer_host":"%duckduckgo.%"}', 'organic_search'),
  (62, '{"referrer_host":"%search.yahoo.%"}', 'organic_search'),
  (63, '{"referrer_host":"%ecosia.%"}', 'organic_search'),
  (64, '{"referrer_host":"%yandex.%"}', 'organic_search'),
  (71, '{"referrer_host":"lnkd.in"}', 'social'),
  (81, '{"referrer_host":"%instagram.%"}', 'social'),
  (82, '{"referrer_host":"t.co"}', 'social'),
  (83, '{"referrer_host":"%twitter.%"}', 'social'),
  (84, '{"referrer_host":"x.com"}', 'social'),
  (85, '{"referrer_host":"%youtube.%"}', 'social'),
  (86, '{"referrer_host":"%tiktok.%"}', 'social'),
  (91, '{"utm_source":"linkedin%"}', 'social'),
  (92, '{"utm_source":"facebook%"}', 'social'),
  (93, '{"utm_source":"instagram%"}', 'social'),
  (94, '{"utm_source":"twitter%"}', 'social'),
  (95, '{"utm_source":"tiktok%"}', 'social'),
  (96, '{"utm_source":"youtube%"}', 'social'),
  (900, '{"utm_medium":"referral"}', 'referral'),
  (901, '{"utm_medium":"event"}', 'referral'),
  (940, '{"utm_source":"_%"}', 'referral'),
  (941, '{"utm_medium":"_%"}', 'referral')
) v(ord, match, channel)
where not exists (select 1 from app.channel_rules r where r.match = v.match::jsonb);

-- sessions classed «direct» that carry what the new rules read
update app.web_sessions s
set channel = app.channel_of(s.utm || jsonb_build_object('referrer_host', s.referrer_host))
where s.channel = 'direct' and (s.utm <> '{}'::jsonb or s.referrer_host is not null)
  and app.channel_of(s.utm || jsonb_build_object('referrer_host', s.referrer_host)) <> 'direct';
