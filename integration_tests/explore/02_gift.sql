-- Gift-level definitions: what counts as "gave" (layer: ftr -> foundation)
-- pocore_fact__gift is the ONE place these definitions live; the snapshot, the KPI
-- outcomes and pocore_foundation__gift all read it, so they can never disagree.
--   is_qualifying         counts as "gave": one-time gift, or the FIRST payment of a monthly plan
--   is_recurring_payment  any real monthly payment (feeds sustainer status and "retained")
-- Look at D05: G007 (the sign-up) qualifies; G008 and G009 (routine payments) don't.

-- query: foundation gift table for D04 and D05 (flags + stage when they gave)
select gift_id, person_id, gift_date, amount, gift_type,
       is_qualifying, is_recurring_payment, gift_number, is_first_gift,
       is_reactivation_gift, days_since_previous_gift, stage_at_gift
from main_pocore_foundation.pocore_foundation__gift
where person_id in ('D04', 'D05')
order by person_id, gift_date;
