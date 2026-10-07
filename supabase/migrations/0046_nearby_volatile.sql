-- 0046_nearby_volatile.sql — public.nearby (0044) was declared STABLE but writes the audit log. PostgREST runs a
-- STABLE or IMMUTABLE function in a read-only transaction, so every call from the app failed (25006) and the Mobile
-- screen's Nearby list could not load (R-MOBILE-01). The SQL suites run read-write and did not see it;
-- structure_invariants now refuses any public function that is not volatile and writes.
alter function public.nearby(numeric, numeric, numeric, text[], jsonb) volatile;
