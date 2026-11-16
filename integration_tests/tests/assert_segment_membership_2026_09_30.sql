-- Hand-calculated segment membership for every fixture donor at as_of = 2026-09-30.
-- Fails on any missing OR unexpected row (zero rows = pass).
--
-- Stages (see assert_lifecycle_stages_2026_09_30): D01 lapsed, D02 deep_lapsed, D03 active,
-- D04 lapsed, D05 sustainer, D06 lapsed, D07 prospect, D08 prospect, D09 deep_lapsed, D10 lapsed.
-- Default filter: D08 is an organization, D09 is deceased -> in NO segment.
-- cust_lapsed_100_v1 (lapsed and lifetime >= $100):
--   D01 $125 yes; D04 $40 no; D06 $0 (refunded) no; D10 $250 (capital gift excluded) yes.
-- cust_board_v1 (attr_is_board_member, a client extra column): D10 only.

with expected as (
    select 'std_lapsed_v1' as segment_id, 'D01' as donor_id union all
    select 'std_lapsed_v1',      'D04' union all
    select 'std_lapsed_v1',      'D06' union all
    select 'std_lapsed_v1',      'D10' union all
    select 'std_deep_lapsed_v1', 'D02' union all
    select 'std_active_v1',      'D03' union all
    select 'std_sustainer_v1',   'D05' union all
    select 'std_prospect_v1',    'D07' union all
    select 'cust_lapsed_100_v1', 'D01' union all
    select 'cust_lapsed_100_v1', 'D10' union all
    select 'cust_board_v1',      'D10'
),

actual as (
    select segment_id, donor_id
    from {{ ref('pode_seg__membership') }}
    where snapshot_date = cast('2026-09-30' as date)
)

select 'missing' as problem, e.segment_id, e.donor_id
from expected as e
left join actual as a on a.segment_id = e.segment_id and a.donor_id = e.donor_id
where a.donor_id is null

union all

select 'unexpected' as problem, a.segment_id, a.donor_id
from actual as a
left join expected as e on e.segment_id = a.segment_id and e.donor_id = a.donor_id
where e.donor_id is null
