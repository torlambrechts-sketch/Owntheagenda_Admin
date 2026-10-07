-- 0049_webhook_export_right.sql — a webhook needs the export right of its event's area (V-P8P-28, Tor 2026-10-07).
--
-- A webhook sends every matching record, as it changes, to a URL outside the platform: it is an export that never
-- stops. 0044 let any staff member create one on the events they can see. Now:
--   * creating a webhook, changing its event or re-pointing its URL requires `<scope>:export`, where the scope is the
--     event's record type's own (app.entities.scope; an event without a record type, note.created, is `global`);
--   * the event picker (webhooks_get.kinds) offers only the events the caller may export;
--   * a delivery whose owner has lost the right since is written as skipped (`no_export`) and never sent — checked
--     when the attempt is queued, so a later change of permission set stops the stream at the next event.

create function app.webhook_scope(p_kind text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select coalesce((select e.scope from app.event_catalog c join app.entities e on e.key = c.entity where c.kind = p_kind), 'global')
$fn$;
revoke all on function app.webhook_scope(text) from public, anon, authenticated;

create or replace function public.webhook_save(p_id uuid, p_values jsonb, p_version int default null) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_staff(); w app.webhooks; v_kind text := btrim(p_values ->> 'event_kind'); v_url text := btrim(p_values ->> 'url');
  v_secret text; v_id uuid := gen_random_uuid(); v_limit numeric := app.count_limit();
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'values'; end if;
  if p_id is null or p_values ? 'event_kind' then
    if not exists (select 1 from app.event_catalog c where c.kind = v_kind and c.webhookable) then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'event_kind';
    end if;
  end if;
  if (p_id is null or p_values ? 'url') and not app.url_public(v_url) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'url'; end if;
  -- a webhook sends records out of the platform: the event's area must be one the caller may export (V-P8P-28)
  if p_id is null or p_values ? 'event_kind' then perform app.require(app.webhook_scope(v_kind), 'export'); end if;
  if p_id is null then
    if v_limit is not null and (select count(*) from app.webhooks where owner_id = v_me and state <> 'deleted') >= v_limit then
      raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'count_limit';
    end if;
    v_secret := app.random_token('whsec_', 32);
    insert into app.webhooks (id, owner_id, event_kind, url, vault_secret_id, is_sample)
    values (v_id, v_me, v_kind, v_url, vault.create_secret(v_secret, 'webhook:' || v_id, 'A webhook''s signing secret (0044): read only by the database to sign its deliveries.'),
            coalesce((select sandbox from app.admins where id = v_me), false));
    perform app.log('webhook.saved', 'webhook', v_id::text, jsonb_build_object('event_kind', v_kind, 'created', true));
    return jsonb_build_object('id', v_id, 'version', 1, 'secret', v_secret);
  end if;
  select * into w from app.webhooks where id = p_id and state <> 'deleted' for update;
  if not found then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if w.owner_id <> v_me and not app.can('global', 'configure') then raise exception 'forbidden' using errcode = 'insufficient_privilege', detail = 'global:configure'; end if;
  -- re-pointing a webhook is sending its records somewhere new: the export right for the kind it keeps
  if p_values ? 'url' and not (p_values ? 'event_kind') then perform app.require(app.webhook_scope(w.event_kind), 'export'); end if;
  if p_version is not null and p_version <> w.version then raise exception 'version_conflict' using errcode = 'serialization_failure', detail = w.version::text; end if;
  update app.webhooks set event_kind = case when p_values ? 'event_kind' then v_kind else event_kind end,
                          url = case when p_values ? 'url' then v_url else url end,
                          state = case when p_values ? 'url' and state = 'blocked' then 'active' else state end,
                          version = version + 1, updated_at = now()
  where id = p_id returning * into w;
  perform app.log('webhook.saved', 'webhook', p_id::text, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(p_values)))));
  return jsonb_build_object('id', w.id, 'version', w.version);
end $fn$;

create or replace function public.webhooks_get(p_filter jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare v_me uuid := app.require_staff(); v_all boolean := app.can('global', 'configure'); f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  return jsonb_build_object(
    'webhooks', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'owner_id', w.owner_id, 'owner', (select coalesce(a.name, a.email) from app.admins a where a.id = w.owner_id),
                            'event_kind', w.event_kind, 'url', w.url, 'state', w.state, 'banned_until', w.banned_until, 'retrying',
                            exists (select 1 from app.webhook_deliveries d where d.webhook_id = w.id and d.state = 'queued' and d.attempt > 1),
                            'last_success_at', w.last_success_at, 'failing_since', w.failing_since, 'created_at', w.created_at, 'version', w.version,
                            'mine', w.owner_id = v_me) order by w.created_at desc)
                          from app.webhooks w where w.state <> 'deleted' and (w.owner_id = v_me or v_all)
                            and (f ->> 'owner_id' is null or w.owner_id::text = f ->> 'owner_id')
                            and w.is_sample = coalesce((select sandbox from app.admins where id = v_me), false)), '[]'::jsonb),
    'deliveries', coalesce((select jsonb_agg(x.j order by x.at desc) from (
                     select d.scheduled_at at, jsonb_build_object('id', d.id, 'webhook_id', d.webhook_id, 'at', coalesce(d.sent_at, d.scheduled_at),
                              'event', w.event_kind, 'host', substring(w.url from '^https://(?:[^@/]*@)?([^:/?#]+)'), 'status', d.response_status,
                              'state', d.state, 'attempt', d.attempt, 'attempts', 4, 'error', d.error_code) j
                     from app.webhook_deliveries d join app.webhooks w on w.id = d.webhook_id
                     where (w.owner_id = v_me or v_all) and d.state <> 'queued' or (w.owner_id = v_me or v_all) and d.attempt > 1
                     order by d.scheduled_at desc limit 20) x), '[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(c.kind order by c.family, c.kind) from app.event_catalog c
                       where c.webhookable and app.can(app.webhook_scope(c.kind), 'export')), '[]'::jsonb),
    'limit', app.count_limit(),
    'count_limits', app.setting('count_limits'),
    'policy', app.webhook_policy(),
    'can_manage_all', v_all);
end $fn$;

create function app.webhook_delivery_export() returns trigger
  language plpgsql security definer set search_path = ''
as $fn$
declare v_owner uuid; v_kind text;
begin
  if new.state <> 'queued' then return new; end if;
  select w.owner_id, w.event_kind into v_owner, v_kind from app.webhooks w where w.id = new.webhook_id;
  if (select e.kind from app.events e where e.id = new.event_id) = 'webhook.ping' then return new; end if;
  if not app.can_for(v_owner, app.webhook_scope(v_kind), 'export') then
    new.state := 'skipped';
    new.error_code := 'no_export';
    new.claimed_at := now();
  end if;
  return new;
end $fn$;
revoke all on function app.webhook_delivery_export() from public, anon, authenticated;
create trigger webhook_delivery_export before insert on app.webhook_deliveries for each row execute function app.webhook_delivery_export();
