-- channel_rules_invariants.sql — where a visit came from (app.channel_of over app.channel_rules, 0025, 0073, 0085): a visit
-- nobody sent is «direct»; a visit sent by a link — a referring site or a tag — is never «direct».
\ir _helpers.psql
begin;

select pg_temp.check(app.channel_of('{}'::jsonb) = 'direct', 'nothing to go on: direct');
select pg_temp.check(app.channel_of(x.touch::jsonb) = x.channel, x.touch || ' → ' || x.channel)
from (values
  ('{"referrer_host":"www.google.com"}', 'organic_search'),
  ('{"referrer_host":"www.google.no"}', 'organic_search'),
  ('{"referrer_host":"duckduckgo.com"}', 'organic_search'),
  ('{"referrer_host":"www.linkedin.com"}', 'social'),
  ('{"referrer_host":"lnkd.in"}', 'social'),
  ('{"referrer_host":"l.instagram.com"}', 'social'),
  ('{"referrer_host":"t.co"}', 'social'),
  ('{"referrer_host":"chatgpt.com"}', 'referral'),
  ('{"utm_source":"google-ads","utm_medium":"cpc"}', 'paid_search'),
  ('{"utm_source":"google","utm_medium":"ppc"}', 'paid_search'),
  ('{"utm_source":"linkedin","utm_medium":"paid_social"}', 'paid_social'),
  ('{"utm_source":"linkedin","utm_medium":"social"}', 'social'),
  ('{"utm_source":"linkedin"}', 'social'),
  ('{"utm_source":"Facebook","utm_medium":"social-media"}', 'social'),
  ('{"utm_source":"newsletter","utm_medium":"email"}', 'email'),
  ('{"utm_source":"brevo"}', 'email'),
  ('{"utm_source":"partner-acme"}', 'partner'),
  ('{"utm_source":"webinar","utm_medium":"event"}', 'referral'),
  ('{"utm_source":"other","utm_medium":"referral"}', 'referral'),
  ('{"utm_source":"podcast"}', 'referral'),
  ('{"utm_campaign":"q4"}', 'direct')
) x(touch, channel);

-- every link Sentral's own campaign builder makes lands outside «direct» (app.ad_utm, 0058)
select pg_temp.check(app.channel_of(jsonb_build_object('utm_source', u ->> 'source', 'utm_medium', u ->> 'medium')) <> 'direct',
                     'a ' || c || ' campaign link is not direct')
from unnest(array['google_ads', 'linkedin', 'facebook', 'newsletter', 'webinar', 'other']) c, lateral (select app.ad_utm(c) u) a;

-- the channels the screens name, and nothing else
select pg_temp.check((select bool_and(channel in ('organic_search', 'paid_search', 'direct', 'social', 'referral', 'partner', 'email', 'paid_social'))
                      from app.channel_rules), 'every rule names a channel the screens know');

rollback;
