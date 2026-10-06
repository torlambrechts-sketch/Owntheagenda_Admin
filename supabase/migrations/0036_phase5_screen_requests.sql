-- 0036_phase5_screen_requests.sql — what the Lead capture and Documents screens asked for
-- (docs/crm-enrichment/requests/capture.md, documents.md), and the chat page rule the seed exposed.
--
--   * worker_chat_start: the most specific page pattern wins (exact, longest wildcard, then every page). The first
--     created used to win, so a catch-all «Snakk med oss» took /pris from the price-page playbook.
--   * R-CAPTURE-03: opening hours on a playbook (Europe/Oslo). Outside them the widget is offline, a live-chat
--     visitor gets the offline message at once and a queued chat returns to the bot. Hours are operational, so they
--     are read from the playbook, not from its published version, and are set with playbook_hours_set.
--   * R-CAPTURE-04: the host a form is embedded on, kept only when it is a tracked site's hostname.
--   * R-DOCUMENTS-01: document_get names the addressed person's email, to propose the first signer.
-- R-CAPTURE-05 needs no change: public.assignment_test({entity, source}) already names the first matching rule.

alter table app.chat_playbooks add column hours jsonb check (hours is null or jsonb_typeof(hours) = 'object');

-- {mon: ["08:00", "16:00"], ...}; a missing day is closed; no hours at all is always open
create function app.chat_in_hours(p_hours jsonb) returns boolean
  language sql stable set search_path = ''
as $fn$
  select p_hours is null or exists (
    select 1 from (select now() at time zone 'Europe/Oslo' t) n
    where (p_hours -> (array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])[extract(isodow from n.t)::int]) is not null
      and n.t::time >= ((p_hours -> (array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])[extract(isodow from n.t)::int]) ->> 0)::time
      and n.t::time <  ((p_hours -> (array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])[extract(isodow from n.t)::int]) ->> 1)::time)
$fn$;

create function public.playbook_hours_set(p_id uuid, p_hours jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('campaigns', 'configure'); p app.chat_playbooks; k text;
begin
  perform app.require_module('leadgen');
  if p_hours is not null and jsonb_typeof(p_hours) = 'null' then p_hours := null; end if;
  if p_hours is not null then
    if jsonb_typeof(p_hours) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hours'; end if;
    for k in select jsonb_object_keys(p_hours) loop
      if k not in ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun') or jsonb_typeof(p_hours -> k) <> 'array' or jsonb_array_length(p_hours -> k) <> 2
         or coalesce(p_hours -> k ->> 0, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(p_hours -> k ->> 1, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$|^24:00$'
         or (p_hours -> k ->> 0) >= (p_hours -> k ->> 1) then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'hours.' || left(k, 10);
      end if;
    end loop;
  end if;
  select * into p from app.chat_playbooks where id = p_id and deleted_at is null for update;
  if not found or not app.visible(p.owner_id, p.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_version is not null and p.version <> p_version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = p.version::text; end if;
  update app.chat_playbooks set hours = p_hours, version = version + 1, updated_at = now(), updated_by = v_me where id = p_id;
  insert into app.changelog (entity, record_id, field, old_value, new_value, actor_id, source) values ('chat_playbook', p_id, 'hours', p.hours, p_hours, v_me, 'ui');
  perform app.log('record.updated', 'chat_playbook', p_id::text, jsonb_build_object('fields', jsonb_build_array('hours')));
  return jsonb_build_object('id', p_id, 'version', p.version + 1, 'hours', p_hours);
end $fn$;

create or replace function public.worker_chat_start(p_site_key text, p_page text, p_org_number text default null, p_language text default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  s app.web_sites; p app.chat_playbooks; d jsonb; v_token text; v_id uuid; v_org text;
  v_page text := case when p_page ~ '^/' then left(p_page, 500) else '/' end;
begin
  select * into s from app.web_sites where key = p_site_key and active and chat_enabled;
  if not found or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select * into p from app.chat_playbooks pb
  where pb.state = 'live' and pb.deleted_at is null and pb.current_version > 0 and (cardinality(pb.site_ids) = 0 or s.id = any (pb.site_ids))
    and (cardinality(pb.pages) = 0 or exists (select 1 from unnest(pb.pages) pt
                                              where v_page = pt or (right(pt, 1) = '*' and left(v_page, char_length(pt) - 1) = left(pt, char_length(pt) - 1))))
  -- the most specific page wins: an exact path, then the longest wildcard, then a playbook for every page
  order by (select max(case when v_page = pt then 1000 when right(pt, 1) = '*' and left(v_page, char_length(pt) - 1) = left(pt, char_length(pt) - 1)
                            then char_length(pt) else 0 end) from unnest(pb.pages) pt) desc nulls last, pb.created_at limit 1;
  if not found then raise exception 'not_found' using errcode = 'no_data_found', detail = 'playbook'; end if;
  select definition into d from app.chat_playbook_versions where playbook_id = p.id and version = p.current_version;
  -- the company, resolved from the IP in memory at the edge; never with identification off, never an ENK (Q16)
  v_org := case when app.setting('web_ident') = 'on' and p_org_number ~ '^\d{9}$'
                     and not exists (select 1 from app.web_companies w where w.org_number = p_org_number and w.excluded) then p_org_number end;
  v_token := app.token() || app.token();
  insert into app.chat_conversations (playbook_id, playbook_version, site_id, page_path, company_org_number, visitor_token_sha256, language, is_sample)
  values (p.id, p.current_version, s.id, v_page, v_org, app.token_hash(v_token),
          case when p_language in ('nb', 'nn', 'en', 'sv') then p_language when (d #>> '{profile,language}') in ('nb', 'nn', 'en', 'sv') then d #>> '{profile,language}' end,
          p.is_sample)
  returning id into v_id;
  if d ->> 'template' = 'live_chat' and jsonb_array_length(coalesce(d -> 'steps', '[]'::jsonb)) = 0 then
    -- outside the playbook's opening hours nobody is queued for: the offline message at once (R-CAPTURE-03)
    if app.chat_in_hours(p.hours) then
      update app.chat_conversations set state = 'queued', queued_at = now() where id = v_id;
    elsif nullif(d ->> 'offline_message', '') is not null then
      insert into app.chat_messages (conversation_id, sender, body) values (v_id, 'system', left(d ->> 'offline_message', 4000));
    end if;
  else
    perform app.chat_advance(v_id);
  end if;
  perform app.log('chat.started', 'chat', v_id::text, jsonb_build_object('playbook', p.id));
  return jsonb_build_object('token', v_token, 'theme', d -> 'theme', 'profile', d -> 'profile') || public.worker_chat_poll(v_token, 0);
end $fn$;

create or replace function public.worker_chat_poll(p_token text, p_since bigint default 0) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare c app.chat_conversations;
begin
  select * into c from app.chat_conversations where visitor_token_sha256 = app.token_hash(p_token);
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  return jsonb_build_object('state', c.state,
    'rep', (select split_part(a.name, ' ', 1) from app.admins a where a.id = c.claimed_by and c.state = 'live'),
    'online', exists (select 1 from app.chat_presence where online_until > now())
              and app.chat_in_hours((select pb.hours from app.chat_playbooks pb where pb.id = c.playbook_id)),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'sender', m.sender, 'body', m.body, 'at', m.at,
                                                              'staff', (select split_part(a.name, ' ', 1) from app.admins a where a.id = m.staff_id)) order by m.id), '[]'::jsonb)
                 from (select * from app.chat_messages where conversation_id = c.id and id > coalesce(p_since, 0) order by id limit 200) m));
end $fn$;

create or replace function app.chat_fallback() returns int
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare r record; n int := 0;
begin
  for r in select c.id, nullif(v.definition ->> 'offline_message', '') om from app.chat_conversations c
           left join app.chat_playbook_versions v on v.playbook_id = c.playbook_id and v.version = c.playbook_version
           left join app.chat_playbooks pb on pb.id = c.playbook_id
           where c.state = 'queued' and (c.queued_at < now() - make_interval(secs => coalesce((v.definition ->> 'queue_wait_seconds')::int, 60))
                                         or not app.chat_in_hours(pb.hours))
           for update of c skip locked loop
    update app.chat_conversations set state = 'bot', queued_at = null where id = r.id;
    if r.om is not null then insert into app.chat_messages (conversation_id, sender, body) values (r.id, 'system', left(r.om, 4000)); end if;
    n := n + 1;
  end loop;
  -- presence that ran out is gone
  delete from app.chat_presence where online_until < now() - interval '1 day';
  return n;
end $fn$;

create or replace function public.worker_form_submit(p_public_id text, p_answers jsonb, p_meta jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  f app.forms; d jsonb; a jsonb; fld jsonb; v jsonb; s text; k text; v_map text; v_type text;
  m jsonb := coalesce(p_meta, '{}'::jsonb);
  vals jsonb := '{}'::jsonb; c_person jsonb := '{}'::jsonb; c_org jsonb := '{}'::jsonb; c_lead jsonb := '{}'::jsonb;
  v_email text; v_name text; v_phone text; v_title text; v_org_nr text; v_org_name text; v_message text; v_consent boolean := false;
  v_fp bytea; v_dup app.form_submissions; v_sub uuid; v_person uuid; v_org uuid; v_lead uuid; v_deal uuid; v_ticket uuid;
  v_tracking jsonb := '{}'::jsonb; v_files jsonb := '[]'::jsonb; v_doi boolean; v_text app.consent_texts; v_token text; v_status text;
  v_day date := (now() at time zone 'Europe/Oslo')::date;
begin
  select * into f from app.forms where public_id = p_public_id and deleted_at is null;
  if not found or f.status <> 'active' or not app.module_on('leadgen') then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers'; end if;
  if jsonb_typeof(m) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'meta'; end if;
  select definition into d from app.form_versions where form_id = f.id and version = f.current_version;
  a := coalesce(d -> 'after_submit', '{}'::jsonb);

  -- spam: the honeypot, a fill time under two seconds, or the edge's per-day-hash rate limit. Stored as a state only.
  if coalesce(m ->> 'honeypot', '') <> '' or (case when (m ->> 'fill_ms') ~ '^\d{1,9}$' then (m ->> 'fill_ms')::int end) < 2000
     or coalesce(m ->> 'rate_limited', '') = 'true' then
    insert into app.form_submissions (form_id, form_version, state, is_sample) values (f.id, f.current_version, 'spam', f.is_sample) returning id into v_sub;
    perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'spam'));
    return jsonb_build_object('ok', true);
  end if;

  -- the values, checked against the version the form was published as (the edge checked them with Zod first)
  for k in select jsonb_object_keys(p_answers) loop
    if not exists (select 1 from jsonb_array_elements(d -> 'fields') x where x ->> 'key' = k and x ->> 'kind' <> 'file_upload') then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || left(k, 40);
    end if;
  end loop;
  for fld in select * from jsonb_array_elements(d -> 'fields') loop
    k := fld ->> 'key'; v := p_answers -> k; v_map := fld ->> 'map';
    continue when fld ->> 'kind' = 'file_upload';
    if fld ->> 'kind' = 'marketing_status' then
      if v is not null and jsonb_typeof(v) not in ('boolean', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_consent := coalesce(v = 'true'::jsonb, false);
      vals := vals || jsonb_build_object(k, v_consent);
      continue;
    end if;
    if v is not null and jsonb_typeof(v) not in ('string', 'number', 'null') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
    s := nullif(btrim(coalesce(v #>> '{}', '')), '');
    if s is null then
      if coalesce((fld ->> 'required')::boolean, false) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      continue;
    end if;
    if char_length(s) > (case when fld ->> 'kind' = 'message' then 5000 else 500 end) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k;
    end if;
    if v_map = 'person.email' then
      s := lower(s);
      if char_length(s) > 254 or s !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_email := s;
    elsif v_map = 'person.phone' then
      if char_length(s) > 40 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_phone := s;
    elsif v_map = 'person.name' then v_name := left(s, 200);
    elsif v_map = 'person.title' then v_title := left(s, 80);
    elsif v_map = 'organization.org_number' then
      s := regexp_replace(s, '\D', '', 'g');
      if s !~ '^\d{9}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k; end if;
      v_org_nr := s;
    elsif v_map = 'organization.name' then v_org_name := left(s, 200);
    elsif v_map like 'custom.%' then
      select x.type into v_type from app.fields x where x.entity = split_part(v_map, '.', 2) and x.key = split_part(v_map, '.', 3) and x.archived_at is null;
      v := case when v_type in ('numerical') and s ~ '^-?\d+(\.\d+)?$' then to_jsonb(s::numeric) else to_jsonb(s) end;
      begin
        perform app.check_custom(split_part(v_map, '.', 2), jsonb_build_object(split_part(v_map, '.', 3), v));
      exception when others then
        raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers.' || k;
      end;
      case split_part(v_map, '.', 2)
        when 'person' then c_person := c_person || jsonb_build_object(split_part(v_map, '.', 3), v);
        when 'organization' then c_org := c_org || jsonb_build_object(split_part(v_map, '.', 3), v);
        else c_lead := c_lead || jsonb_build_object(split_part(v_map, '.', 3), v);
      end case;
    elsif fld ->> 'kind' = 'message' then v_message := s;
    end if;
    vals := vals || jsonb_build_object(k, s);
  end loop;

  -- a duplicate: the same values on the same form within a day. Stored as a state, linked to the first.
  v_fp := extensions.digest(f.id::text || vals::text, 'sha256');
  select * into v_dup from app.form_submissions where form_id = f.id and state = 'accepted' and fingerprint = v_fp and created_at > now() - interval '24 hours'
  order by created_at desc limit 1;
  if found then
    insert into app.form_submissions (form_id, form_version, state, person_id, organization_id, lead_id, deal_id, ticket_id, is_sample)
    values (f.id, f.current_version, 'duplicate', v_dup.person_id, v_dup.organization_id, v_dup.lead_id, v_dup.deal_id, v_dup.ticket_id, f.is_sample) returning id into v_sub;
    perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'duplicate'));
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'thank_you', a ->> 'thank_you', 'redirect_url', a ->> 'redirect_url'));
  end if;

  -- the organization (Brønnøysund enrichment queued for a new one), then the person (SF-17 step 3)
  v_org := app.capture_org(v_org_nr, v_org_name, 'Web form', null, f.is_sample);
  v_person := app.capture_person(v_email, v_name, v_phone, v_org, 'Web form', null, f.is_sample);
  if v_person is null and v_org is null then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'answers'; end if;
  if v_person is not null and (v_title is not null or c_person <> '{}'::jsonb) then
    update app.people set title = coalesce(title, v_title), custom = c_person || custom, version = version + 1, updated_at = now() where id = v_person;
  end if;
  if v_org is not null and c_org <> '{}'::jsonb then
    update app.organizations set custom = c_org || custom, version = version + 1, updated_at = now() where id = v_org;
  end if;

  -- files of a file-upload form: paths in the private form-uploads bucket, written by the edge function
  if f.kind = 'file_upload' and jsonb_typeof(m -> 'files') = 'array' then
    select coalesce(jsonb_agg(jsonb_build_object('path', x ->> 'path', 'name', left(x ->> 'name', 200), 'size', (x ->> 'size')::bigint)), '[]'::jsonb) into v_files
    from (select x from jsonb_array_elements(m -> 'files') x limit 10) q
    where jsonb_typeof(x) = 'object' and (x ->> 'path') ~ '^form-uploads/[A-Za-z0-9/_.-]{1,300}$' and (x ->> 'path') not like '%..%'
      and (x ->> 'size') ~ '^\d{1,8}$' and (x ->> 'size')::bigint <= 26214400;
  end if;

  -- tracking only while form_tracking is on: UTM, referrer host, landing path and declared page variables (Q7)
  if app.setting('form_tracking') = 'on' and jsonb_typeof(m -> 'tracking') = 'object' then
    v_tracking := jsonb_strip_nulls(jsonb_build_object(
      'utm', case when jsonb_typeof(m #> '{tracking,utm}') = 'object' then
               (select nullif(coalesce(jsonb_object_agg(e.key, left(e.value, 120)), '{}'::jsonb), '{}'::jsonb) from jsonb_each_text(m #> '{tracking,utm}') e
                where e.key in ('utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content')) end,
      'referrer_host', case when (m #>> '{tracking,referrer_host}') ~ '^[a-z0-9.-]{1,200}$' then m #>> '{tracking,referrer_host}' end,
      'landing_path', case when (m #>> '{tracking,landing_path}') ~ '^/' then left(m #>> '{tracking,landing_path}', 500) end,
      -- the host the form is embedded on: only a tracked site's own hostname is kept (R-CAPTURE-04)
      'landing_host', (select w.hostname from app.web_sites w
                       where regexp_replace(w.hostname, '^www\.', '') = regexp_replace(lower(m #>> '{tracking,landing_host}'), '^www\.', '') limit 1),
      'page_vars', case when jsonb_typeof(m #> '{tracking,page_vars}') = 'object' then
                     (select nullif(coalesce(jsonb_object_agg(e.key, left(e.value, 120)), '{}'::jsonb), '{}'::jsonb)
                      from (select * from jsonb_each_text(m #> '{tracking,page_vars}') limit 20) e where e.key ~ '^[a-z][a-z0-9_]{0,40}$') end));
  end if;

  insert into app.form_submissions (form_id, form_version, state, field_values, fingerprint, tracking, person_id, organization_id, files, consent, is_sample)
  values (f.id, f.current_version, 'accepted', vals, v_fp, v_tracking, v_person, v_org, v_files, jsonb_build_object('given', v_consent), f.is_sample)
  returning id into v_sub;

  -- consent (step 4): only when the box was ticked; with double opt-in the status stays pending until the link is confirmed
  if v_consent and v_person is not null and v_email is not null then
    select * into v_text from app.consent_texts where key = d #>> '{consent,text_key}' and locale = f.language and id::text = m ->> 'consent_text_id';
    if v_text.id is null then
      select * into v_text from app.consent_texts where key = d #>> '{consent,text_key}' and locale = f.language order by version desc limit 1;
    end if;
    v_doi := app.setting('double_opt_in') = 'on' or (d #> '{consent,double_opt_in}') = 'true'::jsonb;
    v_status := (select marketing_status from app.people where id = v_person);
    if v_status <> 'subscribed' then
      if v_doi then
        perform app.consent_write(v_person, 'pending', 'Web form', 'consent', 'form_submission', v_sub, v_text.id, null, 'capture');
        v_token := app.token() || app.token();
        insert into app.consent_confirmations (token_sha256, person_id, email_sha256, submission_id, text_id, expires_at)
        values (app.token_hash(v_token), v_person, app.email_hash(v_email), v_sub, v_text.id, now() + interval '7 days');
        v_status := 'pending';
      else
        perform app.consent_write(v_person, 'subscribed', 'Web form', 'consent', 'form_submission', v_sub, v_text.id, null, 'capture');
        v_status := 'subscribed';
      end if;
    end if;
    update app.form_submissions set consent = jsonb_build_object('given', true, 'text_id', v_text.id, 'text_version', v_text.version, 'double_opt_in', v_doi, 'status', v_status)
    where id = v_sub;
  end if;

  -- the lead or the deal (step 5). A resubmission updates the open lead from the same form for the same person, owner kept.
  if a ->> 'creates' = 'deal' then
    v_deal := app.capture_deal(f.name || ' · ' || coalesce(v_org_name, v_name, v_email, v_org_nr), v_person, v_org, 'Web form', null,
                               (a ->> 'pipeline_id')::uuid, (a ->> 'stage_id')::uuid, f.is_sample);
  else
    if v_person is not null then
      select s2.lead_id into v_lead from app.form_submissions s2 join app.leads l on l.id = s2.lead_id
      where s2.form_id = f.id and s2.person_id = v_person and s2.id <> v_sub and l.deleted_at is null and l.archived_at is null and l.converted_deal_id is null
      order by s2.created_at desc limit 1;
    end if;
    if v_lead is not null then
      update app.leads set form_data = vals, custom = custom || c_lead, version = version + 1, updated_at = now() where id = v_lead;
      insert into app.changelog (entity, record_id, field, new_value, source) values ('lead', v_lead, '*resubmitted', jsonb_build_object('submission', v_sub), 'capture');
      perform app.emit('lead.updated', 'lead', v_lead, jsonb_build_object('fields', jsonb_build_array('form_data')), f.is_sample);
    else
      v_lead := app.capture_lead(f.name || ' · ' || coalesce(v_name, v_org_name, v_email, v_org_nr), v_person, v_org, 'Web form', null, vals, f.is_sample);
      if c_lead <> '{}'::jsonb then update app.leads set custom = c_lead where id = v_lead; end if;
    end if;
  end if;

  -- the ticket in Sales (step 6), on the path the products' contact.submitted also takes
  if coalesce((a ->> 'ticket')::boolean, false) then
    v_ticket := app.ticket_from_capture('sales', f.name, v_email, v_org, v_message, 'contact_form', v_sub, null, '{}'::jsonb, null, v_person, f.is_sample);
    if v_lead is not null then insert into app.ticket_links (ticket_id, kind, ref) values (v_ticket, 'lead', v_lead::text) on conflict do nothing; end if;
    if v_deal is not null then insert into app.ticket_links (ticket_id, kind, ref) values (v_ticket, 'deal', v_deal::text) on conflict do nothing; end if;
  end if;
  update app.form_submissions set lead_id = v_lead, deal_id = v_deal, ticket_id = v_ticket where id = v_sub;

  -- the sequence (SF-05): only an active one; a sequence that cannot start never loses the submission
  if v_lead is not null and (a ->> 'sequence_id') is not null then
    begin
      perform app.seq_enroll((a ->> 'sequence_id')::uuid, 'lead', v_lead, 'form', null);
    exception when others then
      perform app.log('form.sequence_skipped', 'form', f.id::text, jsonb_build_object('submission', v_sub));
    end;
  end if;

  insert into app.form_stats_daily (form_id, day, submissions) values (f.id, v_day, 1)
  on conflict (form_id, day) do update set submissions = app.form_stats_daily.submissions + 1;
  perform app.log('form.submitted', 'form', f.id::text, jsonb_build_object('submission', v_sub, 'state', 'accepted'));
  perform app.emit('form.submitted', case when v_deal is not null then 'deal' else 'lead' end, coalesce(v_deal, v_lead),
                   jsonb_strip_nulls(jsonb_build_object('form', f.id, 'submission', v_sub, 'person', v_person, 'organization', v_org, 'ticket', v_ticket)), f.is_sample);
  -- the confirmation link goes out by the email provider from the edge function; only its hash is stored here
  return jsonb_strip_nulls(jsonb_build_object('ok', true, 'thank_you', a ->> 'thank_you', 'redirect_url', a ->> 'redirect_url', 'asset_path', a ->> 'asset_path',
                                              'confirm_token', v_token, 'email_connected', case when v_token is not null then app.connected('email') end));
end $fn$;

create or replace function app.form_row(f app.forms) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', f.id, 'name', f.name, 'kind', f.kind, 'language', f.language, 'status', f.status, 'current_version', f.current_version,
    'public_id', f.public_id, 'public_url', 'https://go.owntheagenda.com/f/' || f.public_id, 'version', f.version, 'updated_at', f.updated_at,
    'owner', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = f.owner_id),
    'submissions_month', (select coalesce(sum(s.submissions), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', current_date)::date),
    'views_month', (select coalesce(sum(s.views), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', current_date)::date),
    -- the page the form is embedded on: the most frequent landing path of the last 30 days (only while form_tracking was on)
    -- and the host it was most often seen on, when a submission carried one (R-CAPTURE-04)
    'landing', (select concat(regexp_replace(mode() within group (order by x.tracking ->> 'landing_host'), '^www\.', ''), x.tracking ->> 'landing_path')
                from app.form_submissions x where x.form_id = f.id and x.created_at > now() - interval '30 days'
                and x.tracking ? 'landing_path' group by x.tracking ->> 'landing_path' order by count(*) desc limit 1))
$fn$;

create or replace function public.document_get(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v_me uuid := app.require('deals', 'see'); d app.documents;
begin
  perform app.require_module('documents');
  d := app.doc_row(p_id);
  insert into app.recents (staff_id, entity, record_id) values (v_me, 'document', d.id) on conflict (staff_id, entity, record_id) do update set at = now();
  perform app.log('record.read', 'document', d.id::text);
  return (to_jsonb(d) - 'pdf_sha256') || jsonb_build_object(
    'has_pdf', d.pdf_path is not null and d.pdf_sha256 is not null,
    'pdf_sha256', encode(d.pdf_sha256, 'hex'),
    'template', (select jsonb_build_object('id', t.id, 'name', t.name, 'category', t.category, 'language', t.language) from app.document_templates t where t.id = d.template_id),
    'deal', (select jsonb_build_object('id', dl.id, 'title', dl.title, 'value', dl.value, 'currency', dl.currency) from app.deals dl where dl.id = d.deal_id),
    'organization', (select jsonb_build_object('id', o.id, 'name', o.name, 'org_number', o.org_number) from app.organizations o where o.id = d.organization_id),
    'person', (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email) from app.people p where p.id = d.person_id),
    'owner_name', (select a.name from app.admins a where a.id = d.owner_id),
    'can_edit', d.owner_id = v_me or app.can('deals', 'edit_others'),
    'links', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'label', l.label, 'recipient_person_id', l.recipient_person_id,
                         'recipient_name', (select p.name from app.people p where p.id = l.recipient_person_id),
                         'created_at', l.created_at, 'expires_at', l.expires_at, 'revoked_at', l.revoked_at,
                         'active', l.revoked_at is null and (l.expires_at is null or l.expires_at > now()),
                         'opens', (select count(*) from app.document_views v where v.link_id = l.id and v.client_class <> 'prefetch')) order by l.created_at)
                       from app.document_links l where l.document_id = d.id), '[]'::jsonb),
    'opens', (select count(*) from app.document_views v where v.document_id = d.id and v.client_class <> 'prefetch'),
    'signature_requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'service', r.service, 'created_at', r.created_at,
                                      'sent_at', r.sent_at, 'completed_at', r.completed_at, 'sealed', r.sealed_pdf_path is not null) order by r.created_at)
                                    from app.signature_requests r where r.document_id = d.id), '[]'::jsonb));
end $fn$;

revoke all on function app.chat_in_hours(jsonb) from public, anon, authenticated;
revoke all on function public.playbook_hours_set(uuid, jsonb, int) from public, anon;
grant execute on function public.playbook_hours_set(uuid, jsonb, int) to authenticated;
