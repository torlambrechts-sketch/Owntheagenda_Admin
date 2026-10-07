-- 0041_web_salt_on_demand.sql — the cookieless tracker's daily salt (0025) was made only by the midnight cron job.
-- When that run is missed (the database was down at midnight, or the job was delayed), the day had no salt and
-- worker_web_salt() answered null until the next midnight: every visit that day would be refused or unhashed.
-- The tracker's read now makes today's salt when it is missing. Rotation still destroys the previous day's salt, so
-- there is never more than one, and a lock keeps two first readers from making two.
create or replace function public.worker_web_salt() returns text
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare v text;
begin
  select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'web_salt:' || current_date;
  if v is null then
    perform pg_advisory_xact_lock(hashtext('app.web_salt'));
    select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'web_salt:' || current_date;
    if v is null then
      perform app.web_salt_rotate();
      select s.decrypted_secret into v from vault.decrypted_secrets s where s.name = 'web_salt:' || current_date;
    end if;
  end if;
  return v;
end $fn$;
