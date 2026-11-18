{{ config(enabled=pocore_module_enabled('sustainers')) }}

{#
  pocore__cohort__age — ONE ROW PER SUSTAINER COHORT x MONTH OF LIFE (whole cohorts).
  cohort_type = 'first_recurring'; cohort_year = fiscal year of the first recurring payment;
  age_months 1 = that month. Survival and LTV curves, plus CPA and LTV:CPA when acquisition
  cost is supplied.

    survival_rate   sustainers_giving / sustainers_observed (pool: sum / sum)
    ltv_to_date     average recurring revenue per starter through this month (not summable)
    ltv_to_cpa      paid_ltv_to_date / cost_per_new_sustainer: "revenue returned per $1 of
                    acquisition cost by this month" (paid starters on both sides)
  sustainers_started is the cohort size, repeated on every age row: don't sum it over ages.
  First-gift cohorts by fiscal year: pocore__cohort__year. By acquisition channel:
  pocore__cohort__age__breakdown.
#}

select
    cohort_type,
    cohort_year,
    age_months,
    sustainers_started,
    sustainers_observed,
    sustainers_giving,
    survival_rate,
    revenue,
    ltv_to_date,
    paid_sustainers_started,
    paid_sustainers_observed,
    paid_revenue,
    cost_per_new_sustainer,
    paid_ltv_to_date,
    paid_ltv_to_date / nullif(cost_per_new_sustainer, 0) as ltv_to_cpa
from {{ ref('pocore_mtr__sustainer_cohort_month') }}
where breakdown_by = 'all'
