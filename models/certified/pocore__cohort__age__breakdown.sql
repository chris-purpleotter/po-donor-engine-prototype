{{ config(enabled=pocore_module_enabled('sustainers')) }}

{#
  pocore__cohort__age__breakdown — ONE ROW PER SUSTAINER COHORT x MONTH OF LIFE x BREAKDOWN
  VALUE. The same columns as pocore__cohort__age, split by acquisition channel
  (breakdown_by = 'acquisition_channel'): survival, LTV, CPA and LTV:CPA per channel.
  Within one breakdown_by the values add up to the cohort (counts and revenue).
#}

select
    cohort_type,
    cohort_year,
    age_months,
    breakdown_by,
    breakdown_value,
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
where breakdown_by <> 'all'
