-- 0062_campaign_product.sql — a campaign belongs to the application whose address sends it (as 0061 did for tickets).
--
-- A campaign is sent from the sender chosen on it (campaigns.sender_domain_id), and its layout is branded with its
-- application (campaigns.product). Nothing set the second, so an Orgpuls campaign sent from Orgpuls' address could carry
-- another name in its template. From here the application follows the sender: choosing an address that belongs to an
-- application makes the campaign that application's. An address with no application (staff mail) leaves it as it was.
-- The trigger is named to run before campaign_guard, so a scheduled or sent campaign still cannot change either.

create function app.campaign_sender_product() returns trigger
  language plpgsql set search_path = ''
as $fn$
declare v_product text;
begin
  if new.sender_domain_id is not null and (tg_op = 'INSERT' or new.sender_domain_id is distinct from old.sender_domain_id) then
    select d.product into v_product from app.sender_domains d where d.id = new.sender_domain_id;
    if v_product is not null then new.product := v_product; end if;
  end if;
  return new;
end $fn$;

create trigger campaign_0_sender_product before insert or update of sender_domain_id on app.campaigns
  for each row execute function app.campaign_sender_product();

-- drafts already pointing at an application's address take its application now
update app.campaigns c set product = d.product
from app.sender_domains d
where d.id = c.sender_domain_id and d.product is not null and c.product is distinct from d.product and c.status = 'draft';

revoke all on function app.campaign_sender_product() from public, anon, authenticated;

-- staff mail (invitations, alerts, reminders) is transactional: a marketing address is never its sender, even one with
-- no application (0061 put «no application» first and could pick a newsletter address)
create or replace function app.mail_sender() returns app.sender_domains
  language sql stable security definer set search_path = ''
as $fn$
  select d.* from app.sender_domains d
  where d.deleted_at is null and d.sends_here and app.domain_verified(d) and d.stream = 'transactional'
  order by (d.product is null) desc, d.created_at limit 1
$fn$;
