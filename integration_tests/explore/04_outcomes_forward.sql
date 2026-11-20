-- Looking FORWARD: what each person did in the N days AFTER each month-end (outcomes / KPIs)
-- The same rows as step 03, other columns. "Forward" means after the ROW's date, not after
-- today: for 2026-05-31 the engine already knows what happened in June-August.
-- (The SQL: gift_date > anchor_date and gift_date <= anchor_date + N days, in
--  models/ftr/pocore_ftr__person__month_lookahead.sql.)
-- D05's sign-up on 2026-07-01 is 1 day after 2026-06-30 (gave_30d = 1) but 31 days after
-- 2026-05-31 (gave_30d = 0, gave_90d = 1). is_complete_* is false when the window runs past as_of:
-- those outcomes are partial and are left out of every baseline.
-- Notice: once D05 is a sustainer (from 2026-07-31), gave_* is 0, because routine monthly payments
-- don't count as "gave". That's why sustainers are measured on retained_* instead.

-- query: D05 outcomes after each month-end
select person_id, month_end_date, lifecycle_stage,
       gave_30d, gave_90d, gave_365d, revenue_90d, retained_90d,
       is_complete_30d, is_complete_90d, is_complete_365d
from main_pocore_foundation.pocore_foundation__person__month
where person_id = 'D05' and month_end_date >= '2026-03-31'
order by month_end_date;
