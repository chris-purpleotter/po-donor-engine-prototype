-- Reactivation features, point in time (as_of = 2026-09-30). Zero rows = pass.
-- A reactivation = an eligible, non-refund gift more than 365 days after the previous one.
--   D01: 2023-01-15, then 2024-12-10 (695 days later) -> a comeback on 2024-12-10.
--        2024-11-30: 0 comebacks yet.  2024-12-31: 1, 21 days ago.  2026-09-30: 1, 659 days ago.
--   D03: 2024-06-10, then 2025-11-20 (528 days later) -> a comeback on 2025-11-20; 2026-09-30: 1, 314 days.
--   D04: one gift only -> 0, never.

with expected as (
    select 'D01' as person_id, cast('2024-11-30' as date) as month_end_date, 0 as reactivations, cast(null as {{ dbt.type_int() }}) as days_since union all
    select 'D01', cast('2024-12-31' as date), 1, 21 union all
    select 'D01', cast('2026-09-30' as date), 1, 659 union all
    select 'D03', cast('2026-09-30' as date), 1, 314 union all
    select 'D04', cast('2026-09-30' as date), 0, null
)

select e.person_id, cast(e.month_end_date as {{ dbt.type_string() }}) as detail, 'person__month' as problem
from expected as e
left join {{ ref('pocore_foundation__person__month_end') }} as p
    on p.person_id = e.person_id and p.month_end_date = e.month_end_date
where p.person_id is null
   or p.reactivations_lifetime is distinct from e.reactivations
   or p.days_since_reactivation is distinct from e.days_since

