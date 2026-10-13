-- 0088_demo_deal_market_paths.sql — a demo request opens a deal; the English and Swedish sign-up pages count as sign-up pages.
--
-- 1. A demo request opens a deal (Tor, 13 Oct 2026, after 0087: «ok» to demo requests opening a deal in the pipeline's
--    first stage, template downloads staying leads until someone qualifies them). When a pipeline exists, the lead 0087
--    makes for demo.requested is converted at once: a deal in the first stage of the first pipeline (app.capture_deal),
--    the lead marked converted to it, the ticket linked to both. Without a pipeline the lead stands, as before; a deal
--    that cannot be made never loses the ticket or the lead.
-- 2. The sign-up page by its market's address. Orgpuls' sites serve the sign-up at /registrer (Norway), /registrera
--    (Sweden, se.orgpuls.com, D-276) and /sign-up (Empvibe, www.empvibe.com, D-270); app.is_signup_path (0073) knew
--    /registrer, /signup, /kom-i-gang and /get-started, so a Swedish or English visit to the sign-up page was not counted
--    in the funnel's «reached sign-up» step.

create or replace function app.is_signup_path(p_path text) returns boolean
  language sql immutable set search_path = ''
as $fn$ select coalesce(p_path, '') ~* '^/(en/|sv/|da/|de/)?(registrer|registrera|signup|sign-up|kom-i-gang|get-started)(/|$)' $fn$;

create or replace function app.ticket_intake(p_event bigint) returns uuid
  language plpgsql security definer set search_path = ''
as $fn$
declare e app.events_in; v_id uuid; v_org uuid; v_cat text; v_person uuid; v_lead uuid; v_email text; v_req jsonb;
        v_topic text; v_message text; v_subject text; v_title text; v_template text; v_lang text; v_consent boolean;
        v_form jsonb; v_source text; v_deal uuid;
begin
  select * into e from app.events_in where id = p_event;
  if not found or e.kind not in ('support.requested', 'contact.submitted', 'template.requested', 'demo.requested') then return null; end if;
  if exists (select 1 from app.tickets where source_event_id = p_event) then return null; end if;
  select o.id into v_org from app.organizations o join app.account_products ap on ap.account_id = o.account_id
  where ap.product = e.product and ap.tenant_id = e.tenant_id and o.deleted_at is null limit 1;
  -- the customer's words: Orgpuls' in-app Hjelp sends them as «body», the contact form as «message» (F-S1). A template or
  -- demo request has none in its registry (Orgpuls 0205, 0208), so anything else it carries is not read (0087).
  if e.kind in ('support.requested', 'contact.submitted') then
    v_message := coalesce(nullif(btrim(e.payload ->> 'message'), ''), nullif(btrim(e.payload ->> 'body'), ''));
  end if;
  -- the contact form's topic, when it is one (F-S1)
  if e.kind = 'contact.submitted' then
    v_topic := nullif(lower(btrim(coalesce(e.payload ->> 'topic', ''))), '');
    if v_topic !~ '^[a-z][a-z_]{1,30}$' then v_topic := null; end if;
  end if;
  -- what a template or demo form asked (0087): its own keys, checked by shape; never a message
  if e.kind in ('template.requested', 'demo.requested') then
    v_template := lower(nullif(btrim(e.payload ->> 'template'), ''));
    if v_template !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then v_template := null; end if;
    v_lang := lower(nullif(btrim(e.payload ->> 'lang'), ''));
    if v_lang !~ '^[a-z]{2}$' then v_lang := null; end if;
    v_consent := case when jsonb_typeof(e.payload -> 'consent') = 'boolean' then (e.payload ->> 'consent')::boolean
                      when lower(e.payload ->> 'consent') in ('true', 'false') then lower(e.payload ->> 'consent')::boolean end;
    v_form := jsonb_strip_nulls(jsonb_build_object(
      'template', v_template,
      'role', left(nullif(btrim(e.payload ->> 'role'), ''), 120),
      'organisation', left(coalesce(nullif(btrim(e.payload ->> 'organisation'), ''), nullif(btrim(e.payload ->> 'company'), '')), 200),
      'consent', v_consent,
      'lang', v_lang));
  end if;
  v_cat := coalesce(
    (select c.key from app.ticket_categories c where c.key = e.payload ->> 'category' and c.active),
    (select r.category_key from app.contact_topic_routes r join app.ticket_categories c on c.key = r.category_key and c.active
     where r.product = e.product and r.topic = v_topic),
    (select c.key from app.ticket_categories c where c.active
       and c.key = case e.kind when 'template.requested' then 'free_template' when 'demo.requested' then 'demo' end),
    case when e.kind in ('contact.submitted', 'template.requested', 'demo.requested') then 'sales' else 'getting_started' end);
  -- a lead's title, and a request's subject when it has no words of its own: the category, and for a template which one
  v_title := coalesce(nullif(btrim(e.payload ->> 'subject'), ''),
                      (select c.name from app.ticket_categories c where c.key = v_cat) || coalesce(': ' || v_template, ''), e.kind);
  v_subject := coalesce(nullif(btrim(e.payload ->> 'subject'), ''),
                        nullif(left(btrim(split_part(coalesce(v_message, ''), E'\n', 1)), 120), ''),
                        v_title);
  v_id := app.ticket_from_capture(v_cat, v_subject, e.payload ->> 'email', v_org, v_message,
                                  case e.kind when 'support.requested' then 'in_app' else 'contact_form' end, null, e.product,
                                  jsonb_strip_nulls(jsonb_build_object('role', e.payload ->> 'role', 'page', e.payload ->> 'page', 'browser', e.payload ->> 'browser',
                                                                       'app_version', e.payload ->> 'app_version'))
                                    || coalesce(v_form, '{}'::jsonb),
                                  p_event);
  if v_topic is not null then
    update app.tickets set topic = v_topic where id = v_id;
  end if;
  -- a request in the personvern category starts the 30-day clock (F-S1). The form does not say which right is asked for:
  -- it is recorded as access, the widest, until a person reads it (V-V3S-02).
  if v_cat = 'personvern' then
    insert into app.privacy_requests (ticket_id, organization_id, kind, requester_category, received_at)
    values (v_id, v_org, 'access', case e.kind when 'support.requested' then 'in_app' else 'contact_form' end, least(coalesce(e.occurred_at, now()), now()));
    insert into app.audit (actor, action, target_type, target_id, ok, detail)
    values ('system', 'privacy_request.received', 'ticket', v_id::text, true, jsonb_build_object('event', p_event));
  end if;
  if e.kind = 'support.requested' then
    v_req := app.ticket_request(e.payload -> 'request');
    if v_req is not null then
      update app.tickets set type = 'service_request', request = v_req where id = v_id;
    end if;
  end if;
  -- a contact, template or demo request routed to the Sales queue becomes a CRM lead. A support topic or a privacy request
  -- is not a sale. The lead's title is the form's subject or the category, never the message: a lead is read under
  -- deals:see, by roles that may not see the ticket's queue, and the message is the customer's own words (rule 6).
  if e.kind in ('contact.submitted', 'template.requested', 'demo.requested')
     and (select c.queue_key from app.ticket_categories c where c.key = v_cat) = 'sales' then
    begin
      v_source := case e.kind when 'template.requested' then 'Free template' when 'demo.requested' then 'Demo request' else 'Contact form' end;
      v_email := lower(nullif(btrim(e.payload ->> 'email'), ''));
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then v_email := null; end if;
      v_person := app.capture_person(v_email, case when v_email is not null then e.payload ->> 'name' end, null, v_org, v_source, null);
      if v_person is not null or v_org is not null then
        v_lead := app.capture_lead(v_title, v_person, v_org, v_source, null, nullif(v_form, '{}'::jsonb));
        insert into app.ticket_links (ticket_id, kind, ref) values (v_id, 'lead', v_lead::text) on conflict do nothing;
        update app.tickets set person_id = coalesce(person_id, v_person) where id = v_id;
        -- a demo request opens a deal in the first stage of the first pipeline, when there is one (0088)
        if e.kind = 'demo.requested' and exists (select 1 from app.pipelines p where p.archived_at is null and not p.is_sample) then
          begin
            v_deal := app.capture_deal(v_title, v_person, v_org, v_source, null, null, null);
            update app.leads set converted_deal_id = v_deal, converted_at = now(), version = version + 1, updated_at = now() where id = v_lead;
            insert into app.ticket_links (ticket_id, kind, ref) values (v_id, 'deal', v_deal::text) on conflict do nothing;
          exception when others then
            insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'deal.skipped', 'ticket', v_id::text, false, jsonb_build_object('event', p_event));
          end;
        end if;
      end if;
    exception when others then
      -- the ticket stands: a lead that cannot be made never loses the request
      insert into app.audit (actor, action, target_type, target_id, ok, detail) values ('system', 'lead.skipped', 'ticket', v_id::text, false, jsonb_build_object('event', p_event));
    end;
  end if;
  return v_id;
end $fn$;
