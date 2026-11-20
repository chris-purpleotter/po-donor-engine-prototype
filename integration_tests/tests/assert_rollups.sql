-- v0.3.8 custom rollups (integration_tests/dbt_project.yml `rollups`). Zero rows = pass.
--
-- 1. Known answers for rollup_gift_count_100_plus_lifetime (eligible, non-refund gifts of $100+):
--      D03  G004 $100 (2024-06-10), G005 $150 (2025-11-20)   -> 1 at 2025-06-30, 2 at 2026-09-30
--      D10  G015 $250 (2025-06-01); G014 $5,000 is a capital-campaign gift, not eligible
--                                                            -> 0 at 2025-05-31, 1 at 2025-06-30
--      D01  $50 + $75: never a single $100+ gift             -> 0 at 2026-09-30
-- 2. No peeking: a gift after a month-end never counts in it (D10 at 2025-05-31, D03 at 2025-06-30).
-- 3. Rollups that mirror standard columns must equal them on every row:
--      rollup_gift_sum_amount_12m              = net_giving_12m
--      rollup_gift_max_amount_lifetime         = largest_gift_lifetime
--      rollup_gift_days_since_recurring_lifetime = days_since_last_recurring
--      rollup_gift_any_ytd                     = (gift_count_ytd > 0), checked via foundation
-- 4. The segment using a rollup holds exactly the people with a $100+ gift.

with lookback as (
    select * from {{ ref('pocore_ftr__person__month_lookback') }}
),

expected as (
    select 'D03' as person_id, cast('2025-06-30' as date) as snapshot_date, 1 as expected_count union all
    select 'D03', cast('2026-09-30' as date), 2 union all
    select 'D10', cast('2025-05-31' as date), 0 union all
    select 'D10', cast('2025-06-30' as date), 1 union all
    select 'D01', cast('2026-09-30' as date), 0
),

known_answers as (
    select expected.person_id, cast(expected.snapshot_date as {{ dbt.type_string() }}) as detail,
           'rollup_gift_count_100_plus_lifetime wrong' as problem
    from expected
    left join lookback
        on lookback.person_id = expected.person_id
        and lookback.snapshot_date = expected.snapshot_date
    where lookback.rollup_gift_count_100_plus_lifetime is distinct from expected.expected_count
),

mirrors as (
    select person_id, cast(snapshot_date as {{ dbt.type_string() }}) as detail,
           'rollup differs from the standard column it mirrors' as problem
    from lookback
    where rollup_gift_sum_amount_12m is distinct from net_giving_12m
       or rollup_gift_max_amount_lifetime is distinct from largest_gift_lifetime
       or rollup_gift_days_since_recurring_lifetime is distinct from days_since_last_recurring
),

segment as (
    select person_id, cast(month_end_date as {{ dbt.type_string() }}) as detail,
           'cust_big_gift_v1 membership differs from the rollup' as problem
    from (
        select
            lookback.person_id,
            lookback.snapshot_date as month_end_date,
            lookback.rollup_gift_count_100_plus_lifetime >= 1 as should_be_in,
            membership.person_id is not null as is_in
        from lookback
        inner join {{ ref('pocore_can__people') }} as people
            on people.person_id = lookback.person_id
        left join {{ ref('pocore_foundation__person__segment__month') }} as membership
            on membership.person_id = lookback.person_id
            and membership.month_end_date = lookback.snapshot_date
            and membership.segment_id = 'cust_big_gift_v1'
        where people.person_type = 'individual' and not people.is_deceased
    ) as compared
    where should_be_in <> is_in
)

select * from known_answers
union all select * from mirrors
union all select * from segment
