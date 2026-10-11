-- 0075_form_days_oslo.sql — a form's views, starts and submissions are counted per Oslo day (0031: worker_form_event and
-- worker_form_submit write (now() at time zone 'Europe/Oslo')::date), but form_stats ended its days at the server's UTC
-- date and form_row started «this month» at the UTC month. From Oslo midnight until UTC midnight (two hours in summer,
-- one in winter) the day's own figures fell outside the window: the conversion read as nothing and a month's first
-- hours were missing. Both now count in Oslo days; nothing else changes.

create or replace function public.form_stats(p_id uuid, p_days int default 30) returns jsonb
  language plpgsql stable security definer set search_path = ''
as $fn$
declare f app.forms; v_days int := least(greatest(coalesce(p_days, 30), 1), 365); v_rows jsonb; v_today date := (now() at time zone 'Europe/Oslo')::date;
begin
  perform app.require('campaigns', 'see');
  perform app.require_module('leadgen');
  select * into f from app.forms where id = p_id and deleted_at is null;
  if not found or not app.visible(f.owner_id, f.visibility) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  select jsonb_agg(jsonb_build_object('day', g.day, 'views', coalesce(s.views, 0), 'starts', coalesce(s.starts, 0), 'submissions', coalesce(s.submissions, 0)) order by g.day)
  into v_rows
  from generate_series(v_today - (v_days - 1), v_today, interval '1 day') g(day)
  left join app.form_stats_daily s on s.form_id = p_id and s.day = g.day::date;
  return jsonb_build_object('days', v_rows,
    'views', (select coalesce(sum((r ->> 'views')::int), 0) from jsonb_array_elements(v_rows) r),
    'starts', (select coalesce(sum((r ->> 'starts')::int), 0) from jsonb_array_elements(v_rows) r),
    'submissions', (select coalesce(sum((r ->> 'submissions')::int), 0) from jsonb_array_elements(v_rows) r),
    'conversion', (select case when sum((r ->> 'views')::int) > 0 then round(sum((r ->> 'submissions')::int)::numeric / sum((r ->> 'views')::int), 4) end
                   from jsonb_array_elements(v_rows) r));
end $fn$;

create or replace function app.form_row(f app.forms) returns jsonb
  language sql stable security definer set search_path = ''
as $fn$
  select jsonb_build_object('id', f.id, 'name', f.name, 'kind', f.kind, 'language', f.language, 'status', f.status, 'current_version', f.current_version,
    'public_id', f.public_id, 'public_url', 'https://go.owntheagenda.com/f/' || f.public_id, 'version', f.version, 'updated_at', f.updated_at,
    'owner', (select jsonb_build_object('id', a.id, 'name', a.name, 'initials', a.initials) from app.admins a where a.id = f.owner_id),
    'submissions_month', (select coalesce(sum(s.submissions), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date),
    'views_month', (select coalesce(sum(s.views), 0) from app.form_stats_daily s where s.form_id = f.id and s.day >= date_trunc('month', (now() at time zone 'Europe/Oslo')::date)::date),
    -- the page the form is embedded on: the most frequent landing path of the last 30 days (only while form_tracking was on)
    -- and the host it was most often seen on, when a submission carried one (R-CAPTURE-04)
    'landing', (select concat(regexp_replace(mode() within group (order by x.tracking ->> 'landing_host'), '^www\.', ''), x.tracking ->> 'landing_path')
                from app.form_submissions x where x.form_id = f.id and x.created_at > now() - interval '30 days'
                and x.tracking ? 'landing_path' group by x.tracking ->> 'landing_path' order by count(*) desc limit 1))
$fn$;
