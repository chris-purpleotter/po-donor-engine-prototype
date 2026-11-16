{{ config(enabled=po_donor_engine.pode_module_enabled('sustainers')) }}

-- Hand-calculated sustainer LTV (as_of = 2026-09-30). Zero rows = pass.
-- Only sustainer: D05 (Face to Face), $20 recurring in Jul, Aug, Sep 2026; acquisition_cost 30.
--   Months 1-3 (Jul-Sep) observed; month 4 (Oct) hasn't started -> no row.
--   survival_m2 = 1/1 = 1.0;  survival_m6 = null (nobody has reached month 6)
--   ltv_3m = 20 + 20 + 20 = 60;  ltv_12m = null (never extrapolated)
--   CPA = 30 / 1 paid = 30;  ltv_to_cpa_3m = 60 / 30 = 2.0
-- D01 has a cost (10) but never paid a recurring gift: must not count as a paid sustainer.
-- Expected rows: (2026 | all) x (whole | Face to Face) = 4 rows, all identical.

with expected as (
    select '2026' as start_cohort, 'all' as slice_by, 'all' as slice union all
    select '2026', 'acquisition_channel', 'Face to Face' union all
    select 'all',  'all', 'all' union all
    select 'all',  'acquisition_channel', 'Face to Face'
),

actual as (
    select * from {{ ref('pode_srv__sustainer_ltv') }}
),

missing_or_wrong as (
    select e.start_cohort, e.slice_by, e.slice, 'wrong or missing' as problem
    from expected as e
    left join actual as a
        on a.start_cohort = e.start_cohort and a.slice_by = e.slice_by and a.slice = e.slice
    where a.start_cohort is null
       or a.sustainers_started      != 1
       or a.survival_m2             != 1.0
       or a.survival_m6             is not null
       or a.sustainers_reached_3m   != 1
       or abs(a.ltv_3m - 60) > 0.001
       or a.sustainers_reached_12m  != 0
       or a.ltv_12m                 is not null
       or a.paid_sustainers         != 1
       or abs(a.cost_per_new_sustainer - 30) > 0.001
       or abs(a.paid_ltv_3m - 60) > 0.001
       or abs(a.ltv_to_cpa_3m - 2) > 0.001
       or a.ltv_to_cpa_12m          is not null
),

unexpected as (
    select a.start_cohort, a.slice_by, a.slice, 'unexpected row' as problem
    from actual as a
    left join expected as e
        on a.start_cohort = e.start_cohort and a.slice_by = e.slice_by and a.slice = e.slice
    where e.start_cohort is null
),

month_rows as (
    select 'D05' as donor_id, 'month rows != 3' as problem
    from {{ ref('pode_mtr__sustainer_month') }}
    having count(*) != 3 or count(case when is_observed and gave then 1 end) != 3
)

select start_cohort, slice_by, slice, problem from missing_or_wrong
union all select start_cohort, slice_by, slice, problem from unexpected
union all select donor_id, null, null, problem from month_rows
