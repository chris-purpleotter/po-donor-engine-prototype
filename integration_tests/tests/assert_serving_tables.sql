-- Serving tables agree with the hand-calculated fixtures at the latest snapshot (2026-09-30).
-- Zero rows = pass.
--
-- std_lapsed_v1 at 2026-09-30 = {D01, D04, D06, D10} (see assert_segment_membership).
--   summary: donors_at_snapshot = 4, primary window 180
--   roster:  exactly those 4 donors
--   trend:   the 2026-09-30 row has donors_in_segment = 4

with checks as (

    select 'summary donors_at_snapshot' as check_name,
           (select donors_at_snapshot from {{ ref('pode_srv__segment_summary') }} where segment_id = 'std_lapsed_v1') as actual,
           4 as expected
    union all
    select 'summary outcome_window_days',
           (select outcome_window_days from {{ ref('pode_srv__segment_summary') }} where segment_id = 'std_lapsed_v1'),
           180
    union all
    select 'roster count',
           (select count(*) from {{ ref('pode_srv__segment_roster') }} where segment_id = 'std_lapsed_v1'),
           4
    union all
    select 'roster D01+D04+D06+D10',
           (select count(*) from {{ ref('pode_srv__segment_roster') }}
             where segment_id = 'std_lapsed_v1' and donor_id in ('D01', 'D04', 'D06', 'D10')),
           4
    union all
    -- Flows into std_lapsed_v1 at 2026-09-30 vs 2026-08-31:
    --   08-31 lapsed: D01, D06, D10. D04 was still active (only gift 2025-09-01 -> 364 days).
    --   09-30: D04 is at 394 days -> lapsed. So 1 donor ENTERS (D04) and nobody leaves.
    select 'flows entering lapsed 2026-09',
           (select donors_entering from {{ ref('pode_srv__segment_trend') }}
             where segment_id = 'std_lapsed_v1' and snapshot_date = cast('2026-09-30' as date)),
           1
    union all
    select 'flows leaving lapsed 2026-09',
           (select donors_leaving from {{ ref('pode_srv__segment_trend') }}
             where segment_id = 'std_lapsed_v1' and snapshot_date = cast('2026-09-30' as date)),
           0
    union all
    select 'trend donors_in_segment',
           (select donors_in_segment from {{ ref('pode_srv__segment_trend') }}
             where segment_id = 'std_lapsed_v1' and snapshot_date = cast('2026-09-30' as date)),
           4

)

select * from checks
where actual is null or actual != expected
