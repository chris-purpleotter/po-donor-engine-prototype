-- Looking BACKWARD: what was true about each person at each month-end (features)
-- Every month-end is replayed as if it were "today", using only gifts ON OR BEFORE it
-- (the SQL: gift_date <= snapshot_date in models/ftr/pocore_ftr__person_snapshot.sql).
-- Watch D05 turn from prospect into a sustainer in July 2026, and D04 go new -> active -> lapsed.

-- query: D05, month by month (features as of each month-end)
select person_id, month_end_date, lifecycle_stage, gift_count_lifetime, net_giving_lifetime,
       days_since_last_gift, days_since_last_recurring, is_recurring_active
from main_pocore_foundation.pocore_foundation__person__month
where person_id = 'D05' and month_end_date >= '2026-03-31'
order by month_end_date;

-- query: D04, month by month
select person_id, month_end_date, lifecycle_stage, days_since_first_gift, days_since_last_gift, is_new_donor
from main_pocore_foundation.pocore_foundation__person__month
where person_id = 'D04'
order by month_end_date;
