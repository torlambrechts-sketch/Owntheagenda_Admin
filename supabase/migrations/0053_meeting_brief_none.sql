-- 0053_meeting_brief_none.sql — a meeting without a brief answers «none» (R-MEETINGS-07).
--
-- 0042's meeting_brief tested FOUND after `perform app.log(…)`, which sets FOUND itself, so a meeting with no brief
-- (every uploaded transcript) answered with null state instead of {state: 'none', …}. The log now runs first.

create or replace function public.meeting_brief(p_id uuid) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m app.meetings := app.mtg_get(p_id); b app.meeting_briefs;
begin
  perform app.log('record.read', 'meeting', m.id::text, jsonb_build_object('part', 'brief'));
  select * into b from app.meeting_briefs where meeting_id = m.id;
  if not found then
    return jsonb_build_object('state', 'none', 'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0, 'ai', app.connected('ai'));
  end if;
  return jsonb_build_object(
    'state', b.state, 'generated_at', b.generated_at, 'since_at', b.since_at, 'last_contact_at', b.last_contact_at,
    'linked', num_nonnulls(m.deal_id, m.lead_id, m.person_id, m.organization_id) > 0,
    'changes', coalesce((select jsonb_agg(c || jsonb_build_object('checked', exists (select 1 from app.meeting_brief_checks k
                                                                                       where k.meeting_id = m.id and k.staff_id = app.me() and k.item_key = c ->> 'key')))
                         from jsonb_array_elements(b.changes) c where app.mtg_source_visible(c -> 'source')), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(p) from jsonb_array_elements(b.people) p where app.mtg_source_visible(p -> 'source')), '[]'::jsonb),
    'facts', coalesce((select jsonb_agg(f) from jsonb_array_elements(b.facts) f where app.mtg_source_visible(f -> 'source')), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(x) from jsonb_array_elements(b.quotes) x where app.mtg_source_visible(x -> 'record')), '[]'::jsonb),
    'quotes_state', b.quotes_state, 'ai', app.connected('ai'),
    'instructions_set', (select s.brief_instructions is not null from app.meeting_user_settings s where s.staff_id = app.me()));
end $fn$;
