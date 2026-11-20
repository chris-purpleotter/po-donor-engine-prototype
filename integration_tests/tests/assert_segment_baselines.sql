-- Hand-calculated baselines at anchor 2025-09-30 (as_of = 2026-09-30). Zero rows = pass.
--
-- Stages at 2025-09-30: D01 active (294d), D03 lapsed (477d), D06 active (268d),
-- D10 active (121d; capital gift later is excluded), D04 new, D05 prospect;
-- D02 deep_lapsed; D08 org and D09 deceased excluded; D07 not yet created.
--
-- std_lapsed_v1, gave, 180d, all: {D03}; D03 gives 2025-11-20 (51d) -> n=1, rate 1.0
-- std_active_v1, gave, 365d, all: {D01, D06, D10}; no eligible gift by 2026-09-30
--                                 -> n=3, rate 0.0; window ends 2026-09-30 = as_of -> complete
-- Split segments: cust_givers_v1 (has given) split by acquisition_channel. Givers at 2025-09-30:
--   Web = D01, D04, D06 (n=3); Major Gifts = D10 (n=1). None gives an eligible gift in the next
--   365 days -> rate 0.0 for both.

with expected as (
    select 'std_lapsed_v1' as segment_id, 'gave' as kpi_id, 180 as outcome_window_days, 1 as n, 1.0 as value, true as is_window_complete union all
    select 'std_active_v1',               'gave', 365, 3, 0.0, true union all
    select 'cust_givers_v1__web',         'gave', 365, 3, 0.0, true union all
    select 'cust_givers_v1__major_gifts', 'gave', 365, 1, 0.0, true
)

select e.*, a.n as actual_n, a.value as actual_value, a.is_window_complete as actual_complete
from expected as e
left join {{ ref('pocore_group__baselines__month') }} as a
    on  a.segment_id      = e.segment_id
    and a.kpi_id          = e.kpi_id
    and a.outcome_window_days     = e.outcome_window_days
    and a.anchor_date     = cast('2025-09-30' as date)
where a.segment_id is null
   or a.n != e.n
   or abs(a.value - e.value) > 0.0001
   or a.is_window_complete != e.is_window_complete
