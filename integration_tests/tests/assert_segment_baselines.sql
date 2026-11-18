-- Hand-calculated baselines at anchor 2025-09-30 (as_of = 2026-09-30). Zero rows = pass.
--
-- Stages at 2025-09-30: D01 active (294d), D03 lapsed (477d), D06 active (268d),
-- D10 active (121d; capital gift later is excluded), D04 new, D05 prospect;
-- D02 deep_lapsed; D08 org and D09 deceased excluded; D07 not yet created.
--
-- std_lapsed_v1, gave, 180d, all: {D03}; D03 gives 2025-11-20 (51d) -> n=1, rate 1.0
-- std_active_v1, gave, 365d, all: {D01, D06, D10}; no eligible gift by 2026-09-30
--                                 -> n=3, rate 0.0; window ends 2026-09-30 = as_of -> complete
-- Breakdown by acquisition_channel of std_active_v1: D01 Web, D06 Web, D10 Major Gifts
--   -> Web n=2, Major Gifts n=1 (both rate 0.0)

with expected as (
    select 'std_lapsed_v1' as segment_id, 'all' as breakdown, 'all' as breakdown_value, 'gave' as kpi_id, 180 as outcome_window_days, 1 as n, 1.0 as value, true as is_window_complete union all
    select 'std_active_v1', 'all',                 'all',         'gave', 365, 3, 0.0, true union all
    select 'std_active_v1', 'acquisition_channel', 'Web',         'gave', 365, 2, 0.0, true union all
    select 'std_active_v1', 'acquisition_channel', 'Major Gifts', 'gave', 365, 1, 0.0, true
)

select e.*, a.n as actual_n, a.value as actual_value, a.is_window_complete as actual_complete
from expected as e
left join {{ ref('pocore_mtr__segment_baselines') }} as a
    on  a.segment_id      = e.segment_id
    and a.breakdown       = e.breakdown
    and a.breakdown_value = e.breakdown_value
    and a.kpi_id          = e.kpi_id
    and a.outcome_window_days     = e.outcome_window_days
    and a.anchor_date     = cast('2025-09-30' as date)
where a.segment_id is null
   or a.n != e.n
   or abs(a.value - e.value) > 0.0001
   or a.is_window_complete != e.is_window_complete
