{{ config(enabled=po_core.pocore_client_config__module_enabled('sustainers')) }}

-- Hand-calculated sustainer cohorts (as_of = 2026-09-30). Zero rows = pass.
-- Only sustainer: D05 (Face to Face), $20 recurring in Jul, Aug, Sep 2026; acquisition_cost 30.
--   cohort_year 2026; ages 1-3 (Jul-Sep) observed; age 4 (Oct) hasn't started -> no row.
--   survival 1/1 every month; ltv_to_date 20, 40, 60; CPA = 30 / 1 paid = 30;
--   ltv_to_cpa = 20/30, 40/30, 60/30.
-- D01 has a cost (10) but never paid a recurring gift: must not count as a paid sustainer.
-- The breakdown table has the same rows for breakdown_value 'Face to Face'.

with expected as (
    select 1 as age_months, 20.0 as ltv union all
    select 2, 40.0 union all
    select 3, 60.0
),

actual as (
    select 'all' as breakdown_value, cohort_type, cohort_year, age_months, sustainers_started,
           sustainers_observed, sustainers_giving, survival_rate, ltv_to_date,
           paid_sustainers_started, cost_per_new_sustainer, paid_ltv_to_date, ltv_to_cpa
    from {{ ref('pocore__cohort__age') }}
    union all
    select breakdown_value, cohort_type, cohort_year, age_months, sustainers_started,
           sustainers_observed, sustainers_giving, survival_rate, ltv_to_date,
           paid_sustainers_started, cost_per_new_sustainer, paid_ltv_to_date, ltv_to_cpa
    from {{ ref('pocore__cohort__age__breakdown') }}
),

wrong as (
    select a.breakdown_value, a.age_months, 'wrong values' as problem
    from actual as a
    left join expected as e on e.age_months = a.age_months
    where e.age_months is null
       or a.cohort_type is distinct from 'first_recurring'
       or a.cohort_year is distinct from 2026
       or a.breakdown_value not in ('all', 'Face to Face')
       or a.sustainers_started is distinct from 1
       or a.sustainers_observed is distinct from 1
       or a.sustainers_giving is distinct from 1
       or a.survival_rate is distinct from 1.0
       or abs(a.ltv_to_date - e.ltv) > 0.001
       or a.paid_sustainers_started is distinct from 1
       or abs(a.cost_per_new_sustainer - 30) > 0.001
       or abs(a.paid_ltv_to_date - e.ltv) > 0.001
       or abs(a.ltv_to_cpa - e.ltv / 30) > 0.001
),

row_counts as (
    select breakdown_value, cast(null as {{ dbt.type_int() }}) as age_months, 'expected 3 rows' as problem
    from actual
    group by breakdown_value
    having count(*) != 3
    union all
    select 'all', null, 'expected 6 rows in total' from (select count(*) as n from actual) as c where c.n != 6
)

select * from wrong
union all select * from row_counts
