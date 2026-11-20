-- Hand-calculated segment membership for every fixture donor at as_of = 2026-09-30.
-- Fails on any missing OR unexpected row (zero rows = pass).
--
-- Stages (see assert_lifecycle_stages_2026_09_30): D01 lapsed, D02 deep_lapsed, D03 active,
-- D04 lapsed, D05 sustainer, D06 lapsed, D07 prospect, D08 prospect, D09 deep_lapsed, D10 lapsed.
-- Default filter: D08 is an organization, D09 is deceased -> in NO segment.
-- cust_lapsed_100_v1 (lapsed and lifetime >= $100):
--   D01 $125 yes; D04 $40 no; D06 $0 (refunded) no; D10 $250 (capital gift excluded) yes.
-- cust_board_v1 (attr_is_board_member, a client extra column): D10 only.
-- cust_givers_v1 (gift_count_lifetime > 0): D01-D06, D10 (D06's gift was refunded but still counts
--   as a gift made; D07 has none). Its split_by rows and set rows are checked in assert_splits_and_sets.
-- cust_big_gift_v1 (rollup_gift_count_100_plus_lifetime >= 1, v0.3.8): D03 ($100, $150) and D10 ($250);
--   D08's $10,000 is a grant (not eligible) and D08 is an organization anyway.

with expected as (
    select 'std_lapsed_v1' as segment_id, 'D01' as person_id union all
    select 'std_lapsed_v1',      'D04' union all
    select 'std_lapsed_v1',      'D06' union all
    select 'std_lapsed_v1',      'D10' union all
    select 'std_deep_lapsed_v1', 'D02' union all
    select 'std_active_v1',      'D03' union all
    select 'std_sustainer_v1',   'D05' union all
    select 'std_prospect_v1',    'D07' union all
    select 'cust_lapsed_100_v1', 'D01' union all
    select 'cust_lapsed_100_v1', 'D10' union all
    select 'cust_board_v1',      'D10' union all
    select 'cust_big_gift_v1',   'D03' union all
    select 'cust_big_gift_v1',   'D10' union all
    select 'cust_givers_v1',     'D01' union all
    select 'cust_givers_v1',     'D02' union all
    select 'cust_givers_v1',     'D03' union all
    select 'cust_givers_v1',     'D04' union all
    select 'cust_givers_v1',     'D05' union all
    select 'cust_givers_v1',     'D06' union all
    select 'cust_givers_v1',     'D10' union all
    -- cust_could_go_monthly_v1 (not is_recurring_active): everyone in the population except D05
    select 'cust_could_go_monthly_v1', 'D01' union all
    select 'cust_could_go_monthly_v1', 'D02' union all
    select 'cust_could_go_monthly_v1', 'D03' union all
    select 'cust_could_go_monthly_v1', 'D04' union all
    select 'cust_could_go_monthly_v1', 'D06' union all
    select 'cust_could_go_monthly_v1', 'D07' union all
    select 'cust_could_go_monthly_v1', 'D10'
),

actual as (
    select segment_id, person_id
    from {{ ref('pocore_seg__membership') }}
    where snapshot_date = cast('2026-09-30' as date)
      and split_by is null          -- configured segments only (splits and sets: their own test)
      and segment_set_id is null
)

select 'missing' as problem, e.segment_id, e.person_id
from expected as e
left join actual as a on a.segment_id = e.segment_id and a.person_id = e.person_id
where a.person_id is null

union all

select 'unexpected' as problem, a.segment_id, a.person_id
from actual as a
left join expected as e on e.segment_id = a.segment_id and e.person_id = a.person_id
where e.person_id is null
