-- Hand-calculated expected lifecycle stage for every fixture donor at as_of = 2026-09-30.
-- Returns rows where the engine disagrees (zero rows = pass).
--
-- D01 last gift 2024-12-10 -> 659 days            -> lapsed
-- D02 last gift 2023-03-02 (pledge G016 excluded) -> deep_lapsed
-- D03 last gift 2025-11-20 -> 314 days            -> active
-- D04 only gift 2025-09-01 (lost G017 excluded)   -> 394 days -> lapsed
-- D05 recurring 2026-09-01 -> 29 days <= 45       -> sustainer
-- D06 gift 2025-01-05, refunded (recency ignores refunds) -> 633 days -> lapsed
-- D07 no gifts, created 2026-05-12                -> prospect
-- D08 grant only (not KPI-eligible)               -> prospect  (note: orgs excluded by default group filter anyway)
-- D09 last gift 2021-04-18                        -> deep_lapsed
-- D10 capital-campaign gift excluded; 2025-06-01  -> 486 days -> lapsed

with expected as (
    select 'D01' as person_id, 'lapsed' as expected_stage union all
    select 'D02', 'deep_lapsed' union all
    select 'D03', 'active'      union all
    select 'D04', 'lapsed'      union all
    select 'D05', 'sustainer'   union all
    select 'D06', 'lapsed'      union all
    select 'D07', 'prospect'    union all
    select 'D08', 'prospect'    union all
    select 'D09', 'deep_lapsed' union all
    select 'D10', 'lapsed'
),

actual as (
    select person_id, lifecycle_stage
    from {{ ref('pocore_rollup__person__month_end_lookback') }}
    where snapshot_date = cast('2026-09-30' as date)
)

select e.person_id, e.expected_stage, a.lifecycle_stage as actual_stage
from expected as e
left join actual as a on a.person_id = e.person_id
where a.lifecycle_stage is null
   or a.lifecycle_stage != e.expected_stage
