-- 0091_leaderpact_commands.sql — Sentral sends commands to LeaderPact.
--
-- LeaderPact's public.platform_command (leaderpact 0025) takes Orgpuls's 0205 contract: an HS256 token under its token
-- secret (Vault: leaderpact_token_secret), audience 'leaderpact', the one scope the command needs, a unique id, two minutes
-- of life from product-command. product-command now takes the product from the request (supabase/functions/_shared/
-- commands.ts); this migration gives the database the same registry so command_authorize and the Applications screen know
-- LeaderPact's commands (LeaderPact's REUSE_EVALUATION 6.2).
--
-- 1. **Installation scopes.** users:read and users:write join the closed list an installation may hold (users.deactivate,
--    users.resend_invite). The list lives in one function, app.installation_scopes(), which application_connect and
--    application_update now ask; the column's check holds the same list. LeaderPact's installation holds the scopes its
--    commands need.
-- 2. **LeaderPact's commands** in app.product_commands, mirroring _shared/leaderpact.ts (tests/product-commands.test.ts
--    asserts equality). modules.set_status is a feature-flag change, as Orgpuls's is.
-- 3. **LeaderPact's event kinds** and what each feeds. LeaderPact sends no organisation number and no respondent data:
--    organisations, their members, billing per group and daily counts.

-- ===========================================================================
-- 1. installation scopes
-- ===========================================================================
create or replace function app.installation_scopes() returns text[]
  language sql immutable set search_path = ''
as $fn$
  select array['orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write', 'modules:read',
               'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write', 'users:read', 'users:write']
$fn$;
revoke all on function app.installation_scopes() from public, anon, authenticated;

alter table app.installations drop constraint if exists installations_scopes_check;
alter table app.installations add constraint installations_scopes_check
  check (scopes <@ array['orgs:read', 'orgs:write', 'billing:read', 'billing:write', 'translations:read', 'translations:write', 'modules:read',
                         'modules:write', 'legal:read', 'legal:write', 'settings:read', 'settings:write', 'users:read', 'users:write']);

create or replace function public.application_connect(p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_owner(); v jsonb := coalesce(p_values, '{}'::jsonb); v_key text := lower(btrim(v ->> 'key'));
  v_scopes text[] := case when jsonb_typeof(v -> 'scopes') = 'array' then array(select jsonb_array_elements_text(v -> 'scopes')) else '{}' end;
begin
  perform app.require_fresh_mfa(10);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key'; end if;
  if exists (select 1 from app.products where key = v_key) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'key_taken'; end if;
  if coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if coalesce(v ->> 'api_url', '') !~ '^https://[^\s/]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'api_url'; end if;
  if char_length(coalesce(v ->> 'public_key', '')) not between 20 and 2000 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'public_key'; end if;
  if not (v_scopes <@ app.installation_scopes()) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scopes';
  end if;
  if (v ? 'region') and char_length(coalesce(btrim(v ->> 'region'), '')) not between 1 and 60 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'region'; end if;
  if coalesce(v ->> 'stage', 'ga') not in ('ga', 'beta') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage'; end if;
  if (v ? 'description') and char_length(coalesce(v ->> 'description', '')) > 80 then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'description'; end if;
  insert into app.products (key, name, description, stage, ord)
  values (v_key, btrim(v ->> 'name'), nullif(btrim(v ->> 'description'), ''), coalesce(v ->> 'stage', 'ga'), (select coalesce(max(ord), 0) + 10 from app.products));
  insert into app.installations (product, api_url, public_key, enabled, region, scopes, connected_by)
  values (v_key, v ->> 'api_url', v ->> 'public_key', false, nullif(btrim(v ->> 'region'), ''), v_scopes, v_me);
  perform app.log('application.connected', 'product', v_key, jsonb_build_object('scopes', to_jsonb(v_scopes)));
  return jsonb_build_object('product', v_key, 'intake_code', app.open_product_intake(v_key), 'expires_in', 900);
end $fn$;

create or replace function public.application_update(p_product text, p_values jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require_owner(); v jsonb := coalesce(p_values, '{}'::jsonb);
  v_scopes text[] := case when jsonb_typeof(v -> 'scopes') = 'array' then array(select jsonb_array_elements_text(v -> 'scopes')) end;
begin
  if not exists (select 1 from app.products where key = p_product) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  if (v ? 'name') and (coalesce(btrim(v ->> 'name'), '') = '' or char_length(btrim(v ->> 'name')) > 80) then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'name'; end if;
  if (v ? 'stage') and v ->> 'stage' not in ('ga', 'beta') then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'stage'; end if;
  if (v ? 'api_url') and coalesce(v ->> 'api_url', '') !~ '^https://[^\s/]+$' then raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'api_url'; end if;
  if v_scopes is not null and not (v_scopes <@ app.installation_scopes()) then
    raise exception 'invalid' using errcode = 'invalid_parameter_value', detail = 'scopes';
  end if;
  update app.products set name = coalesce(nullif(btrim(v ->> 'name'), ''), name), stage = coalesce(v ->> 'stage', stage),
    description = case when v ? 'description' then nullif(btrim(v ->> 'description'), '') else description end where key = p_product;
  update app.installations set api_url = coalesce(v ->> 'api_url', api_url), region = case when v ? 'region' then nullif(btrim(v ->> 'region'), '') else region end,
    scopes = coalesce(v_scopes, scopes), enabled = coalesce((v ->> 'enabled')::boolean, enabled), updated_at = now() where product = p_product;
  perform app.log('application.updated', 'product', p_product, jsonb_build_object('fields', to_jsonb(array(select jsonb_object_keys(v)))));
  return jsonb_build_object('product', p_product);
end $fn$;

update app.installations set scopes = array['orgs:read', 'billing:write', 'users:write', 'modules:read', 'modules:write'], updated_at = now()
where product = 'leaderpact' and scopes = '{}';

-- ===========================================================================
-- 2. LeaderPact's commands (the allow-list in supabase/functions/_shared/leaderpact.ts) and what uses them
-- ===========================================================================
insert into app.product_commands (product, command, scope, used_by, destructive)
select 'leaderpact', c, s, u, d from (values
  ('orgs.list', 'orgs:read', array['applications', 'customers'], false), ('orgs.get', 'orgs:read', array['customers'], false),
  ('orgs.resync', 'orgs:read', array['applications', 'customers'], false),
  ('billing.cancel', 'billing:write', array['customers'], true), ('billing.cancel_withdraw', 'billing:write', array['customers'], false),
  ('billing.move_to_free', 'billing:write', array['customers'], true), ('billing.set_status', 'billing:write', array['customers'], false),
  ('users.deactivate', 'users:write', array['customers'], true), ('users.resend_invite', 'users:write', array['customers'], false),
  ('modules.list', 'modules:read', array['flags'], false), ('modules.set_status', 'modules:write', array['flags'], false)
) as x(c, s, u, d)
on conflict (product, command) do update set scope = excluded.scope, used_by = excluded.used_by, destructive = excluded.destructive;

insert into app.command_actions (product, command, action) values
  ('leaderpact', 'modules.set_status', 'flags.change')
on conflict (product, command) do nothing;

-- ===========================================================================
-- 3. what LeaderPact's event kinds feed
-- ===========================================================================
insert into app.product_event_kinds (product, kind, uses, label_key)
select 'leaderpact', k, u, 'platform.eventUse.' || replace(k, '.', '_') from (values
  ('org.created', array['crm', 'funnel', 'workflows']), ('org.deleted', array['crm', 'billing']),
  ('member.invited', array['crm', 'activation']), ('member.joined', array['crm', 'health']), ('member.left', array['crm', 'health']),
  ('billing.changed', array['billing', 'workflows']), ('usage.daily', array['usage', 'health'])
) as x(k, u)
on conflict (product, kind) do update set uses = excluded.uses, label_key = excluded.label_key;
