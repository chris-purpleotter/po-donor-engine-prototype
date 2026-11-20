-- Gift flags, stage at gift, and the 30-day window (as_of = 2026-09-30). Zero rows = pass.
-- D05: prospect until monthly giving starts: G007 2026-07-01, G008 2026-08-01, G009 2026-09-01 ($20 each).
--   G007: the sign-up -> is_qualifying, first gift, gift_number 1; stage at 2026-06-30 = prospect.
--   G008: routine payment -> NOT qualifying, recurring payment, gift_number 2;
--         stage at 2026-07-31 = sustainer (recurring payment 30 days earlier, within 45).
-- 30-day window: from 2026-06-30 the sign-up (1 day later) counts -> gave_30d = 1;
--   from 2026-05-31 it is 31 days later -> gave_30d = 0, but gave_90d = 1.

with expected_gifts as (
    select 'G007' as gift_id, true as is_qualifying, true as is_recurring_payment, true as is_first_gift,
           1 as gift_number, 'prospect' as stage_at_gift
    union all
    select 'G008', false, true, false, 2, 'sustainer'
),

expected_windows as (
    select cast('2026-06-30' as date) as month_end_date, 1 as gave_30d, 1 as gave_90d union all
    select cast('2026-05-31' as date), 0, 1
)

select e.gift_id as detail, 'gift flags' as problem
from expected_gifts as e
left join {{ ref('pocore_foundation__gift') }} as g on g.gift_id = e.gift_id
where g.gift_id is null
   or g.is_qualifying is distinct from e.is_qualifying
   or g.is_recurring_payment is distinct from e.is_recurring_payment
   or g.is_first_gift is distinct from e.is_first_gift
   or g.gift_number is distinct from e.gift_number
   or coalesce(g.stage_at_gift, '') != e.stage_at_gift

union all

select cast(e.month_end_date as {{ dbt.type_string() }}), 'kpi windows'
from expected_windows as e
left join {{ ref('pocore_foundation__person__month_end') }} as p
    on p.person_id = 'D05' and p.month_end_date = e.month_end_date
where p.person_id is null
   or p.gave_30d is distinct from e.gave_30d
   or p.gave_90d is distinct from e.gave_90d
