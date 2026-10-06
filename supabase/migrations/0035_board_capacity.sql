-- 0035_board_capacity.sql — deal_board returned the deal_capacity option key («number») instead of the number
-- (found by the Settings follow-up). It now returns the stored number, or null when unlimited.

create or replace function public.deal_board(p_pipeline uuid, p_query jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_me uuid := app.require('deals', 'see');
  v_sandbox boolean := (select sandbox from app.admins where id = v_me);
  e app.entities := app.entity('deal');
  q jsonb := coalesce(p_query, '{}'::jsonb);
  v_where text; v_cards jsonb;
begin
  if not app.pipeline_visible(p_pipeline) then raise exception 'not_found' using errcode = 'no_data_found'; end if;
  v_where := format('where t.deleted_at is null and t.archived_at is null and t.pipeline_id = %L and %s', p_pipeline, app.vis_sql(e));
  if not v_sandbox then v_where := v_where || ' and not t.is_sample'; end if;
  if not coalesce((q ->> 'closed')::boolean, false) then v_where := v_where || ' and t.status = ''open'''; end if;
  v_where := v_where || app.filter_sql(e, q -> 'filters');
  execute format('select coalesce(jsonb_agg(app.deal_card(t) order by t.value desc, t.seq), ''[]''::jsonb) from app.deals t %s', v_where) into v_cards;
  perform app.log('record.listed', 'deal', null, jsonb_build_object('count', jsonb_array_length(v_cards), 'view', 'board'));
  return jsonb_build_object(
    'stages', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'probability', s.probability, 'rot_days', s.rot_days) order by s.ord, s.created_at)
                        from app.stages s where s.pipeline_id = p_pipeline), '[]'::jsonb),
    'cards', v_cards,
    -- the board's cap is the number stored with the «number» option; unlimited has none
    'capacity', case when app.setting('deal_capacity') = 'number'
                     then (select value_number from app.setting_values where key = 'deal_capacity' and scope_id = '')::int end);
end $fn$;
