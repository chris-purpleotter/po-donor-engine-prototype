-- Hand-calculated KPI outcomes for chosen fixture anchors (as_of = 2026-09-30).
-- Zero rows = pass.
--
-- D01 @ 2024-09-30: G002 one-time $75 on 2024-12-10 (71 days)      -> gave 1/1/1, revenue 75/75/75
-- D03 @ 2025-09-30: G005 one-time $150 on 2025-11-20 (51 days)     -> gave 1/1/1, revenue 150/150/150
-- D05 @ 2026-06-30: G007 2026-07-01 = FIRST payment of RD-0001     -> qualifies (a sign-up): gave_90d 1
--                   revenue_90d = Jul+Aug+Sep payments = 60; 90d window ends 2026-09-28 -> complete
-- D05 @ 2026-07-31: only ROUTINE payments follow (Aug, Sep)        -> gave_90d 0 (routine payments don't count)
--                   revenue_90d = 40; window ends 2026-10-29 > as_of -> NOT complete
-- D10 @ 2026-02-28: next gift is the excluded capital-campaign gift -> gave_90d 0, revenue_90d 0

with expected as (
    select 'D01' as person_id, cast('2024-09-30' as date) as anchor_date, 1 as gave_90d, 1 as gave_365d, 75.0  as revenue_90d, true  as is_complete_90d union all
    select 'D03', cast('2025-09-30' as date), 1, 1, 150.0, true  union all
    select 'D05', cast('2026-06-30' as date), 1, 1, 60.0,  true  union all
    select 'D05', cast('2026-07-31' as date), 0, 0, 40.0,  false union all
    select 'D10', cast('2026-02-28' as date), 0, 0, 0.0,   true
)

select e.*, a.gave_90d as actual_gave_90d, a.gave_365d as actual_gave_365d,
       a.revenue_90d as actual_revenue_90d, a.is_complete_90d as actual_is_complete_90d
from expected as e
left join {{ ref('pocore_ftr__person__month_lookahead') }} as a
    on a.person_id = e.person_id and a.anchor_date = e.anchor_date
where a.person_id is null
   or a.gave_90d        != e.gave_90d
   or a.gave_365d       != e.gave_365d
   or a.revenue_90d     != e.revenue_90d
   or a.is_complete_90d != e.is_complete_90d
