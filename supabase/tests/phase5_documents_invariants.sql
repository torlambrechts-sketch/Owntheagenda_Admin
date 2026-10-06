-- phase5_documents_invariants.sql — documents, templates, trackable links and e-signature (0032; DOC-01..06, UF-08, SF-20, SF-33).
\ir _helpers.psql
begin;

-- expect_detail(sql, message, detail): the statement must raise with this message and this detail
create or replace function pg_temp.expect_detail(p_sql text, p_message text, p_detail text, p_label text) returns void language plpgsql as $$
declare v_msg text; v_det text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg = p_message and coalesce(v_det, '') = coalesce(p_detail, '') then raise notice 'ok %', p_label; return; end if;
    raise exception 'FAIL %: expected «%» («%»), got «%» («%»)', p_label, p_message, p_detail, v_msg, v_det;
  end;
  raise exception 'FAIL %: expected «%», but it succeeded', p_label, p_message;
end $$;

-- ---------------------------------------------------------------------------
-- structure: closed tables, hashed tokens, no IP, workers for the service role only
create temp table t_tables as select unnest(array['document_templates', 'document_template_versions', 'document_counters', 'documents', 'document_links',
  'document_views', 'signature_requests', 'signature_signers', 'signature_fields', 'signature_events', 'drive_connections', 'document_storage_default']) t;
select pg_temp.check((select count(*) from pg_class c where c.relnamespace = 'app'::regnamespace and c.relkind = 'r' and c.relrowsecurity
                      and c.relname in (select t from t_tables)) = 12, 'all twelve documents tables exist with row level security on');
select pg_temp.check(not exists (select 1 from pg_policies where schemaname = 'app' and tablename in (select t from t_tables)), 'no documents table has a policy');
select pg_temp.check(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'app' and g.table_name in (select t from t_tables)
                                 and g.grantee in ('anon', 'authenticated', 'PUBLIC'))
                 and (select count(distinct g.table_name) from information_schema.role_table_grants g where g.table_schema = 'app'
                      and g.table_name in (select t from t_tables) and g.grantee = 'service_role') = 12, 'no client grant on a documents table; the service role has them');
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app'
                                 and table_name in ('document_views', 'document_links', 'signature_events', 'signature_signers', 'signature_requests')
                                 and column_name ~ '(^|_)(ip|ip_address|user_agent|city|country|location|address)($|_)'), 'views and signing evidence store no IP address or place');
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'app' and table_name in ('document_links', 'signature_signers')
                                 and column_name ~ '(token|otp)' and data_type <> 'bytea' and column_name not in ('otp_expires_at', 'otp_attempts')),
                     'link tokens, signing tokens and one-time codes are stored only as hashes');
select pg_temp.check(not has_function_privilege('authenticated', p, 'execute') and has_function_privilege('service_role', p, 'execute'), 'worker for the service role only: ' || p)
from unnest(array['public.worker_doc_view(text, text)', 'public.worker_doc_heartbeat(bigint, int)', 'public.worker_sign_invite(uuid)', 'public.worker_sign_view(text)',
                  'public.worker_sign_otp_send(text)', 'public.worker_sign_otp_verify(text, text)', 'public.worker_sign_submit(text, jsonb)',
                  'public.worker_sign_decline(text, text)', 'public.worker_sign_sealed(uuid, text, bytea, text)', 'public.worker_esign_status(text, text)',
                  'public.worker_document_stored(uuid, text, text, text, text, bytea)', 'public.worker_drive_connected(uuid, text, text, text)']) p;
select pg_temp.check(has_function_privilege('authenticated', 'public.document_create(uuid, uuid, text)', 'execute')
                 and not has_function_privilege('anon', 'public.document_create(uuid, uuid, text)', 'execute')
                 and not has_function_privilege('anon', 'public.document_link_create(uuid, uuid, text, timestamptz, boolean)', 'execute'),
                     'the document functions are for signed-in staff, never anon');
select pg_temp.check(exists (select 1 from app.entities where key = 'document' and scope = 'deals' and module = 'documents')
                 and exists (select 1 from app.entities where key = 'document_template' and scope = 'deals' and module = 'documents'), 'documents and templates are record types');

-- the merge registry: contexts and the document tokens (Q5)
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.check(public.merge_fields_get('document') @> '[{"token":"product.table","format":"block"},{"token":"organization.orgnr","format":"orgnr"},{"token":"Person.navn"}]'
                 and not public.merge_fields_get() @> '[{"token":"product.table"}]', 'document tokens are listed for documents, block tokens never for email');
select pg_temp.check(app.merge_render('[deal.title] [product.table] [document.number]', '{}'::jsonb) -> 'unknown' = '["document.number", "product.table"]'::jsonb,
                     'a document-only token is unknown in an email');

-- ---------------------------------------------------------------------------
-- fixture: an organisation, two people, three deals (one with items and its value from them, one private to tor)
select pg_temp.as_nobody();
create temp table t_ids as select gen_random_uuid() org, gen_random_uuid() person, gen_random_uuid() person2, gen_random_uuid() deal,
  gen_random_uuid() deal2, gen_random_uuid() deal_private,
  (select id from app.admins where email = 'ingrid@orgpuls.no') ingrid, (select id from app.admins where email = 'tor@orgpuls.no') tor;
insert into app.organizations (id, name, org_number, address, postal_code, city, owner_id)
select org, 'Fjordlys Testbedrift AS', '987654321', 'Strandgata 1', '5003', 'Bergen', ingrid from t_ids;
insert into app.people (id, name, email, organization_id, owner_id) select person, 'Kari Testesen', 'kari@fjordlys.example', org, ingrid from t_ids;
insert into app.people (id, name, organization_id, owner_id) select person2, 'Per Utenpost', org, ingrid from t_ids;
insert into app.deals (id, title, value, value_source, currency, pipeline_id, stage_id, person_id, organization_id, owner_id, visibility, product)
select x.id, x.title, x.value, x.vs, 'NOK', p.id, (select s.id from app.stages s where s.pipeline_id = p.id order by s.ord limit 1), x.person, i.org, x.owner, x.vis, 'orgpuls'
from t_ids i cross join app.pipelines p
cross join lateral (values (i.deal, 'Fjordlys — Orgpuls', 0, 'items', i.person, i.ingrid, 'all'),
                           (i.deal2, 'Fjordlys — tillegg', 10000, 'manual', i.person2, i.ingrid, 'all'),
                           (i.deal_private, 'Fjordlys — privat', 5000, 'manual', i.person, i.tor, 'owner')) x(id, title, value, vs, person, owner, vis)
where p.name = 'New business';
insert into app.deal_items (deal_id, name, quantity, unit_price, discount_pct, tax_rate, billing, billing_frequency, cycles, ord)
select deal, x.* from t_ids, (values ('Oppstart <og> opplæring', 1::numeric, 15000::numeric, 0::numeric, 25::numeric, 'one_off', null, null::int, 10),
                                     ('Orgpuls abonnement', 1, 3500, 10, 25, 'recurring', 'monthly', 12, 20),
                                     ('Kursmateriell', 2, 2000, 0, 0, 'one_off', null, null, 30)) x;
select app.deal_recalc(deal) from t_ids;
select pg_temp.check((select value from app.deals where id = (select deal from t_ids)) = 56800, 'the fixture deal is worth its items (TCV 56 800)');

-- ---------------------------------------------------------------------------
-- templates (DOC-01, §6)
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_tpl as select (public.doc_template_save(null, jsonb_build_object('name', 'Tilbud — test', 'category', 'quotes', 'language', 'nb',
  'validity_days', 14, 'number_prefix', 'QX-', 'product_table', jsonb_build_object('columns', jsonb_build_array('name', 'qty', 'price', 'discount', 'tax', 'total', 'period')),
  'body_html', '<h1>Tilbud [document.number] · [document.date]</h1><p>Til [person.name], [organization.name] · [organization.orgnr]</p>'
               || '<p>[organization.address], [organization.postal_code] [organization.city]</p><p>Gyldig til [document.valid_until]. Verdi [deal.value]</p>'
               || '[product.table]<p>[signer.1]</p>'))) r;
select pg_temp.check((select r -> 'placeholders' @> '["product.table", "signer.1", "organization.orgnr"]' and r -> 'unknown' = '[]' and (r ->> 'current_version')::int = 1 from t_tpl),
                     'a saved template lists its placeholders, signer anchors included, and knows every token');
select pg_temp.check(exists (select 1 from app.document_template_versions where template_id = (select (r ->> 'id')::uuid from t_tpl) and version = 1), 'the first save is version 1');
create temp table t_tplb as select public.doc_template_save(null, '{"name":"Avtale — prosjekt","category":"contracts","body_html":"<p>[person.email] [project.start] [deal.title]</p>"}') r;
select pg_temp.check((select r -> 'unknown' = '["project.start"]' from t_tplb), '[project.start] is flagged unknown until Projects, never filled');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"X","body_html":"<p onclick=\"x()\">[deal.title]</p>"}')$$, 'invalid', 'body_html', 'a body with an event handler is refused');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"X","body_html":"<script>alert(1)</script>"}')$$, 'invalid', 'body_html', 'a body with a script is refused');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"X","kind":"spreadsheet"}')$$, 'invalid', 'kind', 'a spreadsheet template comes only from a drive');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"X","product_table":{"columns":["name","margin"]}}')$$, 'invalid', 'product_table', 'an unknown product-table column is refused');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"Firma","share":"company"}')$$, 'forbidden', 'deals:configure', 'a company-wide template needs Deals › configure');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail($$select public.doc_template_save(null, '{"name":"Mine"}')$$, 'forbidden', 'deals:add', 'a read-only analyst cannot make templates');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_tplc as select (public.doc_template_save(null, '{"name":"Tilbud — firma","share":"company","category":"quotes","body_html":"<p>[deal.title] for [organization.name]</p>"}') ->> 'id')::uuid id;
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check(public.doc_templates_get(null) @> jsonb_build_array(jsonb_build_object('id', (select id from t_tplc), 'can_edit', false)), 'everyone sees a company template; only configure may change it');
select pg_temp.expect_detail(format($$select public.doc_template_save(%L, '{"name":"Endret"}')$$, (select id from t_tplc)), 'forbidden', 'deals:configure', 'changing a company template needs configure');
select pg_temp.expect_detail(format($$select public.rec_delete('document_template', array[%L]::uuid[])$$, (select id from t_tplc)), 'forbidden', 'deals:configure',
                             'the generic record path cannot delete a company template either');
select pg_temp.as_staff('eirik@orgpuls.no');
select pg_temp.check(not public.doc_templates_get(null) @> jsonb_build_array(jsonb_build_object('id', (select (r ->> 'id')::uuid from t_tpl))), 'a private template is its owner''s');

-- ---------------------------------------------------------------------------
-- a document from the template on the deal (DOC-01, DOC-02)
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_doc as select public.document_create((select (r ->> 'id')::uuid from t_tpl), (select deal from t_ids)) r;
create temp table t_d as select (r ->> 'id')::uuid id from t_doc;
select pg_temp.check((select number from app.documents where id = (select id from t_d)) = 'QX-1' and (select status from app.documents where id = (select id from t_d)) = 'draft',
                     'the document is numbered from its prefix counter and starts as a draft');
select pg_temp.check((select merge_missing = '{}' from app.documents where id = (select id from t_d)) and (select r -> 'missing' = '[]' from t_doc), 'every merge value is found');
select pg_temp.check((select body_html like '%Fjordlys Testbedrift AS · 987 654 321%' and body_html like '%Strandgata 1, 5003 Bergen%' and body_html like '%Til Kari Testesen%'
                             and body_html like '%Tilbud QX-1%' and body_html like '%Oppstart &lt;og&gt; opplæring%'
                             and body_html not like '%[person.%' and body_html not like '%[product.table]%' and body_html not like '%[document.%' and body_html like '%[signer.1]%'
                      from app.documents where id = (select id from t_d)), 'the body carries the deal''s data, escaped, with the org number formatted and the signer anchor kept');
select pg_temp.check((select (totals ->> 'tcv')::numeric = d.value and (totals ->> 'mrr')::numeric = round((app.deal_revenue(d.id) ->> 'mrr')::numeric, 2)
                             and (totals ->> 'one_off')::numeric = 19000 and jsonb_array_length(totals -> 'vat') = 2
                             and (totals ->> 'total_incl_vat')::numeric = 56800 + (15000 + 3150 * 12) * 0.25
                      from app.documents x join app.deals d on d.id = x.deal_id where x.id = (select id from t_d)),
                     'the product table''s total contract value equals deals.value, with per month, one-off and VAT by rate (DOC-02, Q13)');
select pg_temp.check((select body_html like '%' || app.doc_money(56800, 'NOK', 'nb') || '%' and body_html like '%Per måned%' and body_html like '%Mva 25 %%'
                      from app.documents where id = (select id from t_d)), 'the printed table shows the contract value and the VAT lines');
select pg_temp.check((select valid_until = (now() at time zone 'Europe/Oslo')::date + 14 and body_html like '%Gyldig til ' || app.doc_date(valid_until, 'nb') || '%'
                      from app.documents where id = (select id from t_d)), 'valid until is the creation date plus the template''s validity days');
select pg_temp.check(exists (select 1 from app.events e where e.kind = 'document.generated' and e.subject_type = 'deal' and e.subject_id = (select deal from t_ids)
                             and e.payload ->> 'document' = (select id::text from t_d)
                             and not exists (select 1 from jsonb_object_keys(e.payload) k where k not in ('document', '_run'))), 'document.generated is about the deal and carries ids only');
select pg_temp.check(exists (select 1 from app.changelog where entity = 'deal' and record_id = (select deal from t_ids) and field = 'document.generated'), 'the deal''s history shows the document');
create temp table t_d2 as select (public.document_create((select (r ->> 'id')::uuid from t_tpl), (select deal from t_ids), 'Tilbud nr. 2') ->> 'id')::uuid id;
select pg_temp.check((select number from app.documents where id = (select id from t_d2)) = 'QX-2', 'the next document takes the next number');
-- missing values are listed and block sending, not creation
create temp table t_dm as select public.document_create((select (r ->> 'id')::uuid from t_tplb), (select deal2 from t_ids)) r;
select pg_temp.check((select r -> 'missing' = '["person.email"]' and r -> 'unknown' = '["project.start"]' from t_dm)
                 and (select merge_missing @> array['person.email', 'project.start'] and number is null from app.documents where id = (select (r ->> 'id')::uuid from t_dm)),
                     'a missing value and an unknown token are stored on the document');
select pg_temp.expect_detail(format('select public.document_link_create(%L)', (select (r ->> 'id')::uuid from t_dm)), 'invalid', 'merge', 'a document with missing values cannot be sent');
select public.document_update((select (r ->> 'id')::uuid from t_dm), '{"body_html":"<p>[deal.title] [organization.city]</p>"}');
select pg_temp.check((select merge_missing = '{}' and body_html = '<p>Fjordlys — tillegg Bergen</p>' from app.documents where id = (select (r ->> 'id')::uuid from t_dm)),
                     'editing a draft''s body renders it again and clears what is no longer missing');
select pg_temp.check(not exists (select 1 from app.changelog where entity = 'document' and record_id = (select (r ->> 'id')::uuid from t_dm) and field = 'body_html'
                                 and (old_value is not null or new_value is not null)), 'the history names an edited body but never copies it');

-- visibility (SF-33): a document is seen through its deal
select pg_temp.expect_detail(format('select public.document_create(%L, %L)', (select (r ->> 'id')::uuid from t_tpl), (select deal_private from t_ids)),
                             'not_found', 'deal', 'a document cannot be made on a deal the caller cannot see');
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_dp as select (public.document_create((select id from t_tplc), (select deal_private from t_ids)) ->> 'id')::uuid id;
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_error(format('select public.document_get(%L)', (select id from t_dp)), 'not_found', 'ingrid cannot read a document on a deal she cannot see');
select pg_temp.expect_error(format('select public.rec_get(''document'', %L)', (select id from t_dp)), 'not_found', 'nor through the generic record path');
select pg_temp.expect_error(format('select public.document_file_url(%L)', (select id from t_dp)), 'not_found', 'nor fetch its file (CRM-05)');
select pg_temp.check(not (public.documents_get('{}') -> 'rows') @> jsonb_build_array(jsonb_build_object('id', (select id from t_dp)))
                 and (public.documents_get(jsonb_build_object('deal_id', (select deal from t_ids))) ->> 'total')::int = 2, 'the list holds only documents on visible deals');
select pg_temp.as_staff('ola@orgpuls.no');
select pg_temp.expect_detail(format('select public.document_create(%L, %L)', (select (r ->> 'id')::uuid from t_tpl), (select deal from t_ids)), 'forbidden', 'deals:add',
                             'a read-only analyst cannot create a document');
select pg_temp.check((public.documents_get(jsonb_build_object('deal_id', (select deal from t_ids))) ->> 'total')::int = 2, 'but sees the documents on deals they can see');
select pg_temp.expect_detail(format($$select public.document_link_create(%L)$$, (select id from t_d)), 'forbidden', 'deals:add', 'and cannot share them');
update app.modules set enabled = false where key = 'documents';
select pg_temp.expect_error($$select public.documents_get('{}')$$, 'module_off', 'a switched-off documents module refuses its functions');
update app.modules set enabled = true where key = 'documents';

-- ---------------------------------------------------------------------------
-- trackable links (DOC-04, Q1)
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_link as select public.document_link_create((select id from t_d), (select person from t_ids), 'Kari') r;
select pg_temp.check((select r ->> 'path' = '/d/' || (r ->> 'token') and char_length(r ->> 'token') >= 22 from t_link), 'the token comes back once, as a go.owntheagenda.com path');
select pg_temp.check(exists (select 1 from app.document_links l, t_link t where l.id = (t.r ->> 'id')::uuid and l.token_sha256 = sha256(convert_to(t.r ->> 'token', 'UTF8')))
                 and not exists (select 1 from app.document_links l, t_link t where to_jsonb(l)::text like '%' || (t.r ->> 'token') || '%'), 'only the token''s SHA-256 is stored');
select pg_temp.check((select status from app.documents where id = (select id from t_d)) = 'sent'
                 and exists (select 1 from app.events where kind = 'document.sent' and payload ->> 'link' = (select r ->> 'id' from t_link)), 'the first link sends the document');
select pg_temp.as_nobody();
create temp table t_v1 as select public.worker_doc_view((select r ->> 'token' from t_link), 'human') r;
select public.worker_doc_heartbeat((select (r ->> 'view')::bigint from t_v1), 240);
select public.worker_doc_heartbeat((select (r ->> 'view')::bigint from t_v1), 100);
select pg_temp.check((select duration_seconds from app.document_views where id = (select (r ->> 'view')::bigint from t_v1)) = 240, 'the heartbeat records how long the page stayed open');
select public.worker_doc_view((select r ->> 'token' from t_link), 'human');
select public.worker_doc_view((select r ->> 'token' from t_link), 'prefetch');
select pg_temp.check((select count(*) from app.events where kind = 'document.opened' and payload ->> 'link' = (select r ->> 'id' from t_link)) = 1,
                     'document.opened is emitted once per link per day');
select pg_temp.check((select status = 'opened' and first_opened_at is not null from app.documents where id = (select id from t_d)), 'the first view marks the document opened');
select pg_temp.check((select count(*) from app.notifications where staff_id = (select ingrid from t_ids) and key = 'document.opened') = 2
                 and (select count(*) from app.changelog where entity = 'deal' and record_id = (select deal from t_ids) and field = 'document.opened') = 2,
                     'every human open notifies the owner and is logged with its time on the deal; a link scanner is not');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((select (x ->> 'opens')::int from jsonb_array_elements(public.documents_get('{}') -> 'rows') x where x ->> 'id' = (select id::text from t_d)) = 2,
                     'opens count people, not prefetch');
select pg_temp.check(jsonb_array_length(public.document_views((select id from t_d))) = 3
                 and not exists (select 1 from jsonb_array_elements(public.document_views((select id from t_d))) x, jsonb_object_keys(x) k where k ~ '^(ip|ip_address|city|address|location)$'),
                     'the views list names the recipient, the time and the duration, and no place');
select public.document_link_revoke((select (r ->> 'id')::uuid from t_link));
select pg_temp.as_nobody();
select pg_temp.expect_detail(format('select public.worker_doc_view(%L)', (select r ->> 'token' from t_link)), 'not_found', 'revoked', 'a revoked link is refused at once');
select pg_temp.check((select status from app.documents where id = (select id from t_d)) = 'revoked'
                 and exists (select 1 from app.events where kind = 'document.revoked' and payload ->> 'link' = (select r ->> 'id' from t_link)), 'revoking the only link revokes the document');
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_link2 as select public.document_link_create((select id from t_d), null, null, now() + interval '1 hour') r;
select pg_temp.expect_detail(format($$select public.document_link_create(%L, null, null, now() - interval '1 hour')$$, (select id from t_d)), 'invalid', 'expires_at',
                             'a link cannot expire in the past');
select pg_temp.as_nobody();
update app.document_links set expires_at = now() - interval '1 minute' where id = (select (r ->> 'id')::uuid from t_link2);
select pg_temp.expect_detail(format('select public.worker_doc_view(%L)', (select r ->> 'token' from t_link2)), 'not_found', 'expired', 'an expired link is refused');
select pg_temp.expect_error($$select public.worker_doc_view('not-a-real-token-at-all-000')$$, 'not_found', 'an unknown token is not found');

-- ---------------------------------------------------------------------------
-- e-signature (DOC-05, SF-20)
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format('select public.document_file_url(%L)', (select id from t_d)), 'not_connected', 'pdf', 'without the PDF worker there is no file');
create temp table t_req as select (public.signature_request_save(null, (select id from t_d),
  '[{"name":"Kari Testesen","email":"kari@fjordlys.example"},{"name":"Ola Kunde","email":"Ola@Fjordlys.example","color":"#2F6FDE"}]',
  '[{"signer":1,"kind":"signature","page":1,"x":10,"y":80,"w":30,"h":8},{"signer":1,"kind":"date","page":1,"x":50,"y":80,"w":20,"h":5},
    {"signer":2,"kind":"date","page":1,"x":50,"y":90,"w":20,"h":5}]', 'Hei! Se avtalen.', 'nb', true, null, 'sequential') ->> 'id')::uuid id;
select pg_temp.check((select array_agg(email order by ord) from app.signature_signers where request_id = (select id from t_req)) = array['kari@fjordlys.example', 'ola@fjordlys.example'],
                     'signers are stored in order');
select pg_temp.expect_detail(format('select public.signature_request_send(%L)', (select id from t_req)), 'invalid', 'fields', 'a signer without a signature field cannot be sent');
create temp table t_fields as select '[{"signer":1,"kind":"signature","page":1,"x":10,"y":80,"w":30,"h":8},{"signer":1,"kind":"date","page":1,"x":50,"y":80,"w":20,"h":5},
    {"signer":2,"kind":"signature","page":1,"x":10,"y":90,"w":30,"h":8}]'::jsonb f,
  '[{"name":"Kari Testesen","email":"kari@fjordlys.example"},{"name":"Ola Kunde","email":"ola@fjordlys.example"}]'::jsonb s;
insert into app.setting_values (key, scope_id, value, value_number) values ('count_limits', '', 'number', 1)
on conflict (key, scope_id) do update set value = 'number', value_number = 1;
select pg_temp.expect_detail(format($$select public.signature_request_save(%L, null, %L, %L, null, 'nb', true, null, 'sequential')$$, (select id from t_req), (select s from t_fields), (select f from t_fields)),
                             'invalid', 'signers.limit', 'with count_limits set, the number of signers is capped (ENT-02)');
delete from app.setting_values where key = 'count_limits' and scope_id = '';
select public.signature_request_save((select id from t_req), null, (select s from t_fields), (select f from t_fields), 'Hei! Se avtalen.', 'nb', true, null, 'sequential');
select pg_temp.check((select count(*) from app.signature_signers where request_id = (select id from t_req)) = 2, 'without a limit there is no cap (Q24)');
select pg_temp.expect_detail(format('select public.signature_request_send(%L)', (select id from t_req)), 'not_connected', 'pdf', 'signing waits for the document''s PDF');
select pg_temp.as_nobody();
select public.worker_document_stored((select id from t_d), 'platform', null, null, (select deal from t_ids) || '/' || (select id from t_d) || '.pdf', sha256('pdf-bytes'::bytea));
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail(format('select public.signature_request_send(%L)', (select id from t_req)), 'not_connected', 'email',
                             'built-in signing needs the email provider for the invitations and codes');
update app.integration_connections set status = 'connected' where provider = 'email';
-- a workflow on deal with event document.completed (UF-08 step 6, full-kind matching)
select pg_temp.as_staff('tor@orgpuls.no');
create temp table t_wf as select (public.workflow_save(null, '{"name":"Signert → notat","trigger_type":"event","trigger_config":{"entity":"deal","event":"document.completed"}}',
  '{"steps":[{"key":"n1","kind":"add_note","config":{"body":"Kontrakten er signert"}}]}') ->> 'id')::uuid id;
select public.workflow_set_state((select id from t_wf), 'active');
select pg_temp.as_staff('ingrid@orgpuls.no');
select public.signature_request_send((select id from t_req));
select pg_temp.check((select r.status = 'sent' and r.original_sha256 = d.pdf_sha256 and d.status = 'awaiting_signature'
                      from app.signature_requests r join app.documents d on d.id = r.document_id where r.id = (select id from t_req)),
                     'sending freezes the document''s hash and the document awaits signatures');
select pg_temp.as_nobody();
select pg_temp.expect_detail(format($$select public.worker_document_stored(%L, null, null, null, 'other.pdf', sha256('x'::bytea))$$, (select id from t_d)), 'invalid', 'status',
                             'the PDF out for signature cannot be replaced');
create temp table t_sg as select id, ord from app.signature_signers where request_id = (select id from t_req);
select pg_temp.expect_detail(format('select public.worker_sign_invite(%L)', (select id from t_sg where ord = 2)), 'invalid', 'order', 'in a sequential request the second signer waits for the first');
create temp table t_s1 as select public.worker_sign_invite((select id from t_sg where ord = 1)) r;
select pg_temp.check((select s.token_sha256 = sha256(convert_to(t.r ->> 'token', 'UTF8')) and s.status = 'sent' and t.r ->> 'path' = '/s/' || (t.r ->> 'token')
                      from app.signature_signers s, t_s1 t where s.id = (select id from t_sg where ord = 1)), 'an invitation token is returned once and stored hashed');
select public.worker_sign_view((select r ->> 'token' from t_s1));
select pg_temp.check((select status from app.signature_requests where id = (select id from t_req)) = 'in_progress', 'the first opening puts the request in progress');
select pg_temp.expect_detail(format($$select public.worker_sign_submit(%L, '{}')$$, (select r ->> 'token' from t_s1)), 'invalid', 'otp', 'signing needs the one-time code first');
create temp table t_otp as select public.worker_sign_otp_send((select r ->> 'token' from t_s1)) r;
select pg_temp.check((select s.otp_hash = sha256(convert_to(s.id::text || ':' || (t.r ->> 'code'), 'UTF8')) and s.otp_hash <> sha256(convert_to(t.r ->> 'code', 'UTF8'))
                             and (t.r ->> 'code') ~ '^\d{6}$'
                      from app.signature_signers s, t_otp t where s.id = (select id from t_sg where ord = 1)), 'the one-time code is stored only as a salted hash');
create temp table t_wrong as select public.worker_sign_otp_verify((select r ->> 'token' from t_s1), case when (select r ->> 'code' from t_otp) = '000000' then '111111' else '000000' end) r
from generate_series(1, 5) n;
select pg_temp.check((select otp_attempts from app.signature_signers where id = (select id from t_sg where ord = 1)) = 5
                 and (select count(*) from t_wrong where r ->> 'verified' = 'false') = 5 and exists (select 1 from t_wrong where r ->> 'locked' = 'true')
                 and (select count(*) from app.signature_events where request_id = (select id from t_req) and kind = 'otp_failed') = 5, 'each wrong code is counted');
select pg_temp.expect_detail(format('select public.worker_sign_otp_verify(%L, %L)', (select r ->> 'token' from t_s1), (select r ->> 'code' from t_otp)), 'invalid', 'otp_locked',
                             'after five wrong codes even the right one is refused');
select pg_temp.expect_detail(format('select public.worker_sign_otp_send(%L)', (select r ->> 'token' from t_s1)), 'invalid', 'otp_locked', 'and no new code is sent while the old one is valid');
update app.signature_signers set otp_expires_at = now() - interval '1 minute' where id = (select id from t_sg where ord = 1);
create temp table t_otp2 as select public.worker_sign_otp_send((select r ->> 'token' from t_s1)) r;
create temp table t_ver as select public.worker_sign_otp_verify((select r ->> 'token' from t_s1), (select r ->> 'code' from t_otp2)) r;
select pg_temp.check((select r ->> 'verified' from t_ver) = 'true'
                 and (select status from app.signature_signers where id = (select id from t_sg where ord = 1)) = 'code_verified', 'once the code expired a new one verifies');
create temp table t_sub1 as select public.worker_sign_submit((select r ->> 'token' from t_s1),
  jsonb_build_object((select f.id::text from app.signature_fields f where f.signer_id = (select id from t_sg where ord = 1) and f.kind = 'signature'), 'Kari Testesen')) r;
select pg_temp.check((select r ->> 'completed' from t_sub1) = 'false' and (select status from app.signature_signers where id = (select id from t_sg where ord = 1)) = 'signed'
                 and (select value from app.signature_fields where signer_id = (select id from t_sg where ord = 1) and kind = 'date') = ((now() at time zone 'Europe/Oslo')::date)::text
                 and exists (select 1 from app.events where kind = 'document.signed' and payload ->> 'signer' = (select id::text from t_sg where ord = 1)),
                     'the first signer signs; the date field fills itself; document.signed is emitted');
select pg_temp.expect_error(format('select public.worker_sign_view(%L)', (select r ->> 'token' from t_s1)), 'not_found', 'a signer who has signed cannot sign again');
create temp table t_s2 as select public.worker_sign_invite((select id from t_sg where ord = 2)) r;
select public.worker_sign_view((select r ->> 'token' from t_s2));
create temp table t_otp3 as select public.worker_sign_otp_send((select r ->> 'token' from t_s2)) r;
select public.worker_sign_otp_verify((select r ->> 'token' from t_s2), (select r ->> 'code' from t_otp3));
create temp table t_sub2 as select public.worker_sign_submit((select r ->> 'token' from t_s2),
  jsonb_build_object((select f.id::text from app.signature_fields f where f.signer_id = (select id from t_sg where ord = 2) and f.kind = 'signature'), 'Ola Kunde')) r;
select pg_temp.check((select r ->> 'completed' from t_sub2) = 'true'
                 and (select r.status = 'completed' and r.completed_at is not null and d.status = 'signed' and d.signed_at is not null
                      from app.signature_requests r join app.documents d on d.id = r.document_id where r.id = (select id from t_req)),
                     'when every signer has signed the request completes and the document is signed');
select pg_temp.check((select count(*) from app.events e where e.kind = 'document.completed' and e.subject_type = 'deal' and e.subject_id = (select deal from t_ids)
                      and e.payload ->> 'request' = (select id::text from t_req)
                      and not exists (select 1 from jsonb_object_keys(e.payload) k where k not in ('document', 'request', '_run'))) = 1,
                     'document.completed is emitted once, about the deal, with ids only');
select pg_temp.check(not exists (select 1 from app.events where kind like 'document.%' and payload::text ~ '(Kari|Ola Kunde|Fjordlys)')
                 and not exists (select 1 from app.audit where target_type = 'document' and detail::text ~ '(Kari|Ola Kunde|Fjordlys|Strandgata)')
                 and not exists (select 1 from app.signature_events where request_id = (select id from t_req) and detail::text ~ '(Kari Testesen|Ola Kunde)'),
                     'no document body, signer name or typed signature reaches events, the audit or the evidence detail');
-- the workflow on deal + «document.completed» starts (full-kind matching); an existing suffix workflow still matches
select app.sub_workflows(e) from app.events e where e.kind = 'document.completed' and e.subject_id = (select deal from t_ids);
select pg_temp.check(exists (select 1 from app.workflow_runs r where r.workflow_id = (select id from t_wf) and r.subject_type = 'deal' and r.subject_id = (select deal from t_ids))
                 and exists (select 1 from app.notes n where n.entity = 'deal' and n.record_id = (select deal from t_ids) and n.body = 'Kontrakten er signert'),
                     'a workflow on deal with event document.completed runs when the contract is signed (UF-08)');
-- the hash chain
select pg_temp.check(app.signature_chain_ok((select id from t_req))
                 and (select min(seq) = 1 and max(seq) = count(*) and count(distinct seq) = count(*) from app.signature_events where request_id = (select id from t_req))
                 and (select kind from app.signature_events where request_id = (select id from t_req) order by seq desc limit 1) = 'completed',
                     'the evidence is one unbroken chain ending in «completed»');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.signature_request_get((select id from t_req)) ->> 'chain_ok')::boolean
                 and not (public.signature_request_get((select id from t_req)) -> 'signers' -> 0 ? 'otp_hash'), 'the request view verifies the chain and shows no hashes of codes');
select pg_temp.as_nobody();
select pg_temp.expect_error(format($$update app.signature_events set detail = '{}' where request_id = %L$$, (select id from t_req)), 'the signature evidence is append-only',
                            'a signature event cannot be changed');
select pg_temp.expect_error(format($$delete from app.signature_events where request_id = %L$$, (select id from t_req)), 'the signature evidence is append-only',
                            'a signature event cannot be deleted while its request exists');
savepoint tamper;
alter table app.signature_events disable trigger signature_events_fixed;
update app.signature_events set at = at - interval '1 hour' where request_id = (select id from t_req) and kind = 'signed';
select pg_temp.check(not app.signature_chain_ok((select id from t_req)), 'a changed event breaks the chain');
rollback to savepoint tamper;
select pg_temp.check(app.signature_chain_ok((select id from t_req)), 'the untouched chain verifies again');
select public.worker_sign_sealed((select id from t_req), 'sealed/' || (select id from t_d) || '.pdf', sha256('sealed'::bytea), 'sealed/' || (select id from t_d) || '-evidence.pdf');
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.check((public.document_file_url((select id from t_d)) ->> 'sealed')::boolean and app.signature_chain_ok((select id from t_req)),
                     'the sealed PDF is the document''s file and the seal extends the chain (DOC-05)');
select pg_temp.expect_detail(format('select public.document_delete(array[%L]::uuid[])', (select id from t_d)), 'invalid', 'retention', 'a signed contract is kept (§10)');

-- a decline keeps its reason on the signer only; deleting the document takes its evidence with it
select pg_temp.as_nobody();
select public.worker_document_stored((select id from t_d2), 'platform', null, null, (select deal from t_ids) || '/' || (select id from t_d2) || '.pdf', sha256('pdf-2'::bytea));
select pg_temp.as_staff('ingrid@orgpuls.no');
create temp table t_req2 as select (public.signature_request_save(null, (select id from t_d2), '[{"name":"Kari Testesen","email":"kari@fjordlys.example"}]',
  '[{"signer":1,"kind":"signature","page":1,"x":10,"y":80,"w":30,"h":8}]') ->> 'id')::uuid id;
select public.signature_request_send((select id from t_req2));
select pg_temp.as_nobody();
create temp table t_s3 as select public.worker_sign_invite((select id from app.signature_signers where request_id = (select id from t_req2))) r;
select public.worker_sign_view((select r ->> 'token' from t_s3));
select public.worker_sign_decline((select r ->> 'token' from t_s3), 'Prisen er for høy for oss nå');
select pg_temp.check((select d.status = 'declined' and r.status = 'declined' and s.decline_reason = 'Prisen er for høy for oss nå'
                      from app.signature_requests r join app.documents d on d.id = r.document_id join app.signature_signers s on s.request_id = r.id where r.id = (select id from t_req2))
                 and exists (select 1 from app.events where kind = 'document.declined' and payload ->> 'request' = (select id::text from t_req2)),
                     'a decline closes the request and the document');
select pg_temp.check(not exists (select 1 from app.events where payload::text like '%Prisen%') and not exists (select 1 from app.audit where detail::text like '%Prisen%')
                 and not exists (select 1 from app.signature_events where detail::text like '%Prisen%') and not exists (select 1 from app.changelog where new_value::text like '%Prisen%'),
                     'the decline reason never reaches events, the audit, the history or the evidence');
delete from app.documents where id = (select id from t_d2);
select pg_temp.check(not exists (select 1 from app.signature_requests where id = (select id from t_req2))
                 and not exists (select 1 from app.signature_events where request_id = (select id from t_req2)), 'deleting the document cascades to its request and evidence');

-- ---------------------------------------------------------------------------
-- storage and drives (DOC-03): no drive adapter yet
select pg_temp.as_staff('ingrid@orgpuls.no');
select pg_temp.expect_detail($$select public.doc_storage_connect('google')$$, 'not_connected', 'google', 'connecting Google Drive is not connected');
select pg_temp.expect_detail($$select public.doc_storage_connect('microsoft')$$, 'not_connected', 'microsoft', 'connecting OneDrive or SharePoint is not connected');
select pg_temp.expect_detail($$select public.doc_template_import('microsoft', 'file-123')$$, 'not_connected', 'microsoft', 'importing a template needs the caller''s drive');
select pg_temp.expect_detail($$select public.doc_storage_set_default('google', '{"kind":"shared","label":"Salg/Tilbud"}')$$, 'forbidden', 'global:configure',
                             'the company default needs Global › configure');
select pg_temp.check((public.doc_storage_get() -> 'default' ->> 'provider') = 'platform' and public.doc_storage_get() ->> 'branding' = 'hidden',
                     'without a drive, documents are stored on the platform');
select pg_temp.as_staff('tor@orgpuls.no');
select pg_temp.expect_detail($$select public.doc_storage_set_default('google', '{"kind":"shared","label":"Salg/Tilbud"}')$$, 'not_connected', 'google',
                             'a drive becomes the default only once connected');
select pg_temp.as_nobody();
select public.worker_drive_connected((select tor from t_ids), 'google', 'tor@orgpuls.no', 'test-token-not-real');
select pg_temp.as_staff('tor@orgpuls.no');
select public.doc_storage_set_default('google', '{"kind":"shared","label":"Salg/Tilbud"}');
select pg_temp.check((public.doc_storage_get() -> 'default' ->> 'provider') = 'google'
                 and exists (select 1 from app.drive_connections c join vault.secrets s on s.id = c.vault_secret_id where c.staff_id = (select tor from t_ids) and c.status = 'connected'),
                     'a connected drive keeps its token in Vault and can be the default');

rollback;
