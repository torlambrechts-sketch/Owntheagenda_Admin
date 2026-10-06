-- settings_invariants.sql — the register (D-15, D-16): defaults, fixed rules, audit, modules.
\ir _helpers.psql
begin;

select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(app.setting('contact_rule') = 'no_rule', 'contact rule defaults to no rule');
select pg_temp.check(app.setting('visibility_default', 'deal') = 'all', 'visibility defaults to everyone');
select pg_temp.check(app.setting('session_idle') = 'on_30', 'the idle timeout is on by default (D-29)');
select pg_temp.expect_error($$select public.setting_set('firewall', 'fixed')$$, 'fixed_setting', 'the firewall cannot be changed');
select pg_temp.expect_error($$select public.setting_set('mfa', 'fixed')$$, 'fixed_setting', 'MFA cannot be changed');
select pg_temp.expect_error($$select public.setting_set('tracking', 'sometimes')$$, 'invalid', 'a value outside the options is refused');
select pg_temp.expect_error($$select public.setting_set('tracking', 'off', 'deal')$$, 'invalid', 'a platform setting takes no scope');
select public.setting_set('tracking', 'off');
select pg_temp.check(app.setting('tracking') = 'off', 'a change takes effect');
select pg_temp.check((select detail ->> 'from' from app.audit where action = 'setting.changed' order by id desc limit 1) = 'on', 'the change is audited with the old value');
select pg_temp.check((public.settings_log(1) -> 0 ->> 'actor') = 'Tor Lambrechts', 'the log names who changed it');
select public.setting_set('visibility_default', 'owner', 'organization');
create temp table t_o as select (public.rec_save('organization', null, '{"name":"Synlig AS"}') ->> 'id')::uuid id;
select pg_temp.check((select visibility from app.organizations where id = (select id from t_o)) = 'owner', 'the default visibility applies to new records');

-- modules: off hides the record type's functions
select pg_temp.check(app.module_on('leads'), 'modules are on by default');
select public.module_set('leads', false);
select pg_temp.check(not ((public.shell() -> 'modules' ->> 'leads')::boolean), 'the shell sees a module off');
select public.module_set('leads', true);

select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error($$select public.module_set('leads', false)$$, 'forbidden', 'sales cannot switch modules');
select pg_temp.check(jsonb_array_length(public.settings_get()) >= 15, 'every staff member can read the register');

rollback;
