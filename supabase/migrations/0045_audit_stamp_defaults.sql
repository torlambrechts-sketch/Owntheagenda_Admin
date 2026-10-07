-- 0045_audit_stamp_defaults.sql — 0043 stamps every new audit row with its source and principal from a before-insert
-- trigger and checks both are set. A session that runs with triggers off (session_replication_role = replica: the
-- seed, a restore) skipped the stamp and then failed the check. The same stamp is now also the columns' default,
-- which applies whatever the replication role; the trigger still refines the principal for a staff action.
alter table app.audit alter column source set default app.audit_source();
alter table app.audit alter column principal_kind set default app.audit_principal_kind();
alter table app.audit alter column principal_id set default app.audit_principal_id();
