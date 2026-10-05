-- 0002_product_secrets.sql — the secrets a product shares with the platform, kept in this project's Vault.
--
-- A product's token secret (to sign commands) and webhook secret (to verify its events) are read by the
-- edge functions through public.product_secret, which only the service role may call. They arrive
-- through public.store_product_secrets, which needs a one-time intake number: an operator opens one with
-- app.open_intake() (SQL, fifteen minutes, used once), and the product's own database posts its secrets
-- to the secret-intake function with it. The values never pass through a person, a log or a repository.

create table app.intake_nonces (
  hash       bytea primary key,
  expires_at timestamptz not null
);
alter table app.intake_nonces enable row level security;
revoke all on app.intake_nonces from public, anon, authenticated;

create function app.open_intake() returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  delete from app.intake_nonces where expires_at < now();
  insert into app.intake_nonces (hash, expires_at) values (extensions.digest(v, 'sha256'), now() + interval '15 minutes');
  return v;
end $fn$;
revoke all on function app.open_intake() from public, anon, authenticated, service_role;

create function public.store_product_secrets(p_nonce text, p_secrets jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  k text;
  v text;
  n int := 0;
begin
  delete from app.intake_nonces where hash = extensions.digest(coalesce(p_nonce, ''), 'sha256') and expires_at > now();
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_secrets) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  for k, v in select key, value from jsonb_each_text(p_secrets) loop
    if k !~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$' or char_length(coalesce(v, '')) < 32 or char_length(v) > 500 then
      raise exception 'store_product_secrets: % is not a product secret', k using errcode = 'invalid_parameter_value';
    end if;
    if exists (select 1 from vault.secrets s where s.name = k) then
      perform vault.update_secret((select s.id from vault.secrets s where s.name = k), v);
    else
      perform vault.create_secret(v, k, 'A product''s shared secret (0002): read by the edge functions only.');
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'stored', n);
end $fn$;
revoke all on function public.store_product_secrets(text, jsonb) from public, anon, authenticated;
grant execute on function public.store_product_secrets(text, jsonb) to service_role;

create function public.product_secret(p_name text) returns text
  language sql stable security definer set search_path = ''
as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
  where s.name = p_name and p_name ~ '^[a-z][a-z0-9_]{1,30}_(token|webhook)_secret$'
$fn$;
revoke all on function public.product_secret(text) from public, anon, authenticated;
grant execute on function public.product_secret(text) to service_role;
