# Database requests — Feed

Changes the Feed screen needs and leaves out until they exist. Each names the function and the behaviour.

## R-FEED-01 — the deal's owner in `feed_get`
Overlooked cards say «… · owner {first name}». `feed_get`'s `deal` object has no owner, so the screen shows the
signed-in staff member (the card's recipient), which is wrong once a deal changes owner. Add
`'owner_id', d.owner_id, 'owner', (select a.name from app.admins a where a.id = d.owner_id)` to the deal object.
Deviation V-FEED-13.

## R-FEED-02 — a score filter in `feed_get`
PRO-01 filters cards by stage, type and score. `feed_get(p_tab, p_filter)` reads `stage_ids` and `kinds`
only. Accept `score_min` / `score_max` (on `d.score`, ignored while `ai_scoring` is off, cards without a deal
excluded when set). Deviation V-FEED-16.

## R-FEED-03 — the thread subject in `enrichment_get.lookups`
The reverse-lookup card reads «{sender} wrote «{subject}»». Add `'subject', (select t.subject from
app.email_threads t where t.id = s.thread_id)` (and `'at', s.created_at`) to each lookup. Deviation V-FEED-30.

## R-FEED-04 — sequence name and step on `link_clicked` cards
«Tracked link in sequence «Trial nurture» step 3»: `app.sub_feed` stores the enrollment id only. Add
`'sequence', w.name, 'step', se.current_ord` to the params when `payload.enrollment` is set. Deviation V-FEED-09.

## R-FEED-05 — delete a scoring model
«＋ Model» creates a draft model, but nothing removes one (`score_models.deleted_at` exists, no function sets
it). Add `score_model_delete(p_id)` (deals:configure; refuses an active model or deactivates it first;
audited). Until then a model made by mistake can only be set to draft.

## R-FEED-06 — enrichment candidates and the sandbox
`enrichment_get.candidates` counts organizations without filtering `is_sample`, while the ids the screen sends
come from `rec_list` (which hides sample rows outside the sandbox), so the button's number can exceed what is
sent. Either filter `candidates` by the staff member's sandbox flag or return the candidate ids (first 100)
from `enrichment_get` and drop the `rec_list` lookup. Also: `credits.used_month` counts from the UTC month start
while `feed_progress` uses the staff member's time zone; one rule for both.
