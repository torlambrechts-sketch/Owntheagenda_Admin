-- 0004_audit_events.sql — who did what (audit), what changed (changelog), and what happened (outbox).
--
-- app.audit grows from «a command to a product» into the platform's single audit (D-12): every write,
-- and every read of customer data, is a row with an action, a target and a reason when one was typed.
-- It holds names, ids and counts, never a field's value: a customer's own words stay in their record.
-- The record history (app.changelog) holds the values, because the design's history tab shows them.
-- The outbox (app.events) carries CRM and outbound events to the workflow engine and webhooks (D-14).

alter table app.audit
  alter column product drop not null,
  alter column command drop not null,
  add column action      text check (action is null or action ~ '^[a-z_]+\.[a-z_]+$'),
  add column target_type text check (target_type is null or target_type ~ '^[a-z_]{2,40}$'),
  add column target_id   text check (target_id is null or char_length(target_id) <= 100),
  add column account_id  uuid,
  add column staff_id    uuid,
  add column reason      text check (reason is null or char_length(reason) <= 300),
  add column detail      jsonb check (detail is null or jsonb_typeof(detail) = 'object');
alter table app.audit add constraint audit_what check (command is not null or action is not null);
create index audit_target on app.audit (target_type, target_id, at desc);
create index audit_at on app.audit (at desc);

-- the audit cannot be emptied either (F-6)
create trigger audit_no_truncate before truncate on app.audit for each statement execute function app.audit_fixed();

-- the reason a caller typed, when the register asks for one (typed_reason). Set per call by the
-- functions that take p_reason; read by app.log.
create function app.log(p_action text, p_target_type text, p_target_id text, p_detail jsonb default null,
                        p_account uuid default null)
  returns void language sql volatile security definer set search_path = ''
as $fn$
  insert into app.audit (actor, staff_id, action, target_type, target_id, detail, account_id, ok, reason)
  values (coalesce(app.admin_email(), 'system'), app.me(), p_action, p_target_type, p_target_id, p_detail, p_account, true,
          nullif(current_setting('app.reason', true), ''));
$fn$;

-- ---------------------------------------------------------------------------
-- record history: one row per field that changed. Nobody changes a row; a row goes only with its record,
-- when the record is purged or a person is erased (app.purging set by those functions).
create table app.changelog (
  id        bigint generated always as identity primary key,
  entity    text not null check (entity ~ '^[a-z_]{2,40}$'),
  record_id uuid not null,
  field     text not null check (char_length(field) between 1 and 80),
  old_value jsonb,
  new_value jsonb,
  actor_id  uuid,
  source    text not null default 'ui' check (source in ('ui', 'api', 'import', 'workflow', 'assistant', 'product', 'system', 'merge')),
  at        timestamptz not null default now()
);
create index changelog_record on app.changelog (entity, record_id, at desc);

create function app.changelog_fixed() returns trigger
  language plpgsql set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' and current_setting('app.purging', true) = 'on' then
    return old;
  end if;
  raise exception 'the record history is append-only' using errcode = 'insufficient_privilege';
end $fn$;
create trigger changelog_fixed before update or delete on app.changelog for each row execute function app.changelog_fixed();
create trigger changelog_no_truncate before truncate on app.changelog for each statement execute function app.audit_fixed();

-- ---------------------------------------------------------------------------
-- the outbox: what happened in the platform, for the workflow engine, webhooks and the feed
create table app.events (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  subject_type text check (subject_type is null or subject_type ~ '^[a-z_]{2,40}$'),
  subject_id   uuid,
  actor_id     uuid,
  payload      jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  is_sample    boolean not null default false,
  created_at   timestamptz not null default now(),
  processed_at timestamptz
);
create index events_unprocessed on app.events (id) where processed_at is null;
create index events_subject on app.events (subject_type, subject_id, id desc);

create function app.emit(p_kind text, p_subject_type text, p_subject_id uuid, p_payload jsonb default '{}'::jsonb,
                         p_sample boolean default false)
  returns bigint language sql volatile security definer set search_path = ''
as $fn$
  insert into app.events (kind, subject_type, subject_id, actor_id, payload, is_sample)
  values (p_kind, p_subject_type, p_subject_id, app.me(), coalesce(p_payload, '{}'::jsonb), coalesce(p_sample, false))
  returning id;
$fn$;

do $$
declare t text;
begin
  foreach t in array array['changelog', 'events'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('revoke all on app.%I from public, anon, authenticated', t);
    execute format('grant all on app.%I to service_role', t);
  end loop;
end $$;
grant usage, select on all sequences in schema app to service_role;
revoke all on function app.log(text, text, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function app.emit(text, text, uuid, jsonb, boolean) from public, anon, authenticated;
revoke all on function app.changelog_fixed() from public, anon, authenticated;
