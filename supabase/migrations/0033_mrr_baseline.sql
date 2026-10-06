-- 0033_mrr_baseline.sql — the first MRR snapshot is a baseline (requests/analytics.md R-2).
-- snapshot_mrr_tenants compared today's MRR with the last snapshot before the month began. On the platform's
-- first run there is none, so every paying customer became a «new» movement and the month showed the whole MRR
-- as new. A customer that existed before this month and has no earlier snapshot now gets no movement; a
-- customer that signed up this month is still new. Movements already booked by a first run are recomputed.

create or replace function app.snapshot_mrr_tenants() returns void
  language plpgsql volatile security definer set search_path = ''
as $fn$
declare m date := date_trunc('month', current_date)::date; r record; v_prev numeric;
begin
  insert into app.mrr_tenant_daily (day, product, tenant_id, mrr, status)
  select current_date, s.product, s.tenant_id, app.sub_mrr(s), app.sub_status(s)
  from app.subscriptions s join app.account_products ap on ap.product = s.product and ap.tenant_id = s.tenant_id
  on conflict (day, product, tenant_id) do update set mrr = excluded.mrr, status = excluded.status;
  -- movements this month: today's MRR against the last snapshot before the month began
  for r in select t.product, t.tenant_id, t.mrr,
                  (select p.mrr from app.mrr_tenant_daily p where p.product = t.product and p.tenant_id = t.tenant_id and p.day < m order by p.day desc limit 1) before,
                  exists (select 1 from app.mrr_tenant_daily p where p.product = t.product and p.tenant_id = t.tenant_id and p.day < m and p.mrr > 0) ever_paid,
                  (select s.payment_state from app.subscriptions s where s.product = t.product and s.tenant_id = t.tenant_id) pay,
                  (select ap.created_at < m from app.account_products ap where ap.product = t.product and ap.tenant_id = t.tenant_id) existed
           from app.mrr_tenant_daily t where t.day = current_date loop
    v_prev := coalesce(r.before, 0);
    delete from app.mrr_movements where month = m and product = r.product and tenant_id = r.tenant_id;
    -- the first snapshot of a customer that existed before this month is a baseline, not new MRR (R-2)
    continue when r.before is null and coalesce(r.existed, false);
    if v_prev = 0 and r.mrr > 0 then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, case when r.ever_paid then 'reactivation' else 'new' end, r.mrr);
    elsif v_prev > 0 and r.mrr = 0 then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'churn', -v_prev);
      insert into app.account_churns (product, tenant_id, churned_at, mrr_lost, payment_failure, reason_id)
      values (r.product, r.tenant_id, now(), v_prev, r.pay in ('past_due', 'suspended'),
              case when r.pay in ('past_due', 'suspended') then (select id from app.churn_reasons where code = 'payment_failure') end)
      on conflict do nothing;
    elsif r.mrr > v_prev then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'expansion', r.mrr - v_prev);
    elsif r.mrr < v_prev then
      insert into app.mrr_movements values (m, r.product, r.tenant_id, 'contraction', r.mrr - v_prev);
    end if;
  end loop;
end $fn$;

-- recompute this month's movements with the rule above (the snapshot itself is unchanged)
delete from app.mrr_movements mv
where mv.month = date_trunc('month', current_date)::date and mv.kind = 'new'
  and not exists (select 1 from app.mrr_tenant_daily p where p.product = mv.product and p.tenant_id = mv.tenant_id
                  and p.day < date_trunc('month', current_date)::date)
  and exists (select 1 from app.account_products ap where ap.product = mv.product and ap.tenant_id = mv.tenant_id
              and ap.created_at < date_trunc('month', current_date)::date);
