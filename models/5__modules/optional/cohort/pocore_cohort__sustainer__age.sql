{{ config(enabled=pocore_client_config__module_enabled('sustainers')) }}

{#
  pocore_cohort__sustainer__age — ONE ROW PER SUSTAINER COHORT x BREAKDOWN x MONTH OF LIFE.
  INTERNAL: mixes whole-cohort rows (breakdown_by = 'all') and channel rows; the certified
  pocore__cohort__age and pocore__cohort__age__breakdown each select one kind.

    cohort_year        fiscal year of the first recurring payment
    age_months         1 = the month of the first recurring payment, 2 = the next month ...
                       up to the longest of sustainer_survival_months / sustainer_ltv_horizons_months
    sustainers_started cohort size (the same on every age row: a cohort-level count, don't sum it over ages)
    sustainers_observed  starters who have REACHED this month (the month has fully happened)
    sustainers_giving  observed starters who made a recurring payment this month
    revenue            net recurring revenue this month from observed starters
    ltv_to_date        sum over months 1..age of (revenue / observed): average recurring revenue
                       per starter through this month. Null when nobody has reached it.
  Cost (only when acquisition_cost is in people_extra_columns; otherwise null): the same for
  starters with acquisition_cost > 0, the cohort's cost per new sustainer, and ltv_to_cpa.
#}

{%- set max_months = (var('sustainer_survival_months') + var('sustainer_ltv_horizons_months')) | max -%}
{%- set has_cost = 'acquisition_cost' in var('people_extra_columns') -%}
{%- set float = dbt.type_float() -%}

with people as (

    select
        person_id,
        coalesce(acquisition_channel, 'unknown')                         as acquisition_channel,
        {%- if has_cost %}
        cast(attr_acquisition_cost as {{ float }})                       as acquisition_cost
        {%- else %}
        cast(null as {{ float }})                                        as acquisition_cost
        {%- endif %}
    from {{ ref('pocore_foundation__person') }}

),

tagged as (

    select sm.*, p.acquisition_channel, p.acquisition_cost
    from {{ ref('pocore_cohort__person__sustainer_age') }} as sm
    inner join people as p
        on p.person_id = sm.person_id
    where sm.month_number <= {{ max_months }}

),

-- Each row counted twice: whole cohort, and by acquisition channel.
expanded as (

    select start_year as cohort_year, 'all' as breakdown_by, 'all' as breakdown_value,
           person_id, month_number, gave, amount, is_observed, acquisition_cost
    from tagged
    union all
    select start_year as cohort_year, 'acquisition_channel' as breakdown_by, acquisition_channel as breakdown_value,
           person_id, month_number, gave, amount, is_observed, acquisition_cost
    from tagged

),

starters as (

    select
        cohort_year, breakdown_by, breakdown_value,
        count(*)                                                       as sustainers_started,
        count(case when acquisition_cost > 0 then 1 end)               as paid_sustainers_started,
        sum(case when acquisition_cost > 0 then acquisition_cost end)  as paid_acquisition_cost
    from expanded
    where month_number = 1
    group by cohort_year, breakdown_by, breakdown_value

),

months as (

    select
        cohort_year, breakdown_by, breakdown_value, month_number as age_months,
        count(case when is_observed then 1 end)                                       as sustainers_observed,
        count(case when is_observed and gave then 1 end)                              as sustainers_giving,
        coalesce(sum(case when is_observed then amount end), 0)                       as revenue,
        count(case when is_observed and acquisition_cost > 0 then 1 end)              as paid_sustainers_observed,
        coalesce(sum(case when is_observed and acquisition_cost > 0 then amount end), 0) as paid_revenue
    from expanded
    group by cohort_year, breakdown_by, breakdown_value, month_number

),

per_month as (

    select
        m.*,
        case when m.sustainers_observed > 0
             then cast(m.revenue as {{ float }}) / m.sustainers_observed end           as revenue_per_observed,
        case when m.paid_sustainers_observed > 0
             then cast(m.paid_revenue as {{ float }}) / m.paid_sustainers_observed end as paid_revenue_per_observed
    from months as m

)

select
    'first_recurring'                                                            as cohort_type,
    pm.cohort_year,
    pm.breakdown_by,
    pm.breakdown_value,
    pm.age_months,
    s.sustainers_started,
    pm.sustainers_observed,
    pm.sustainers_giving,
    case when pm.sustainers_observed > 0
         then cast(pm.sustainers_giving as {{ float }}) / pm.sustainers_observed end as survival_rate,
    pm.revenue,
    -- observation is monotone (reaching month N means months 1..N-1 were reached), so when
    -- month N is observed every earlier term exists
    case when pm.sustainers_observed > 0
         then sum(pm.revenue_per_observed) over (
                  partition by pm.cohort_year, pm.breakdown_by, pm.breakdown_value
                  order by pm.age_months rows between unbounded preceding and current row) end as ltv_to_date,
    {%- if has_cost %}
    s.paid_sustainers_started,
    pm.paid_sustainers_observed,
    pm.paid_revenue,
    cast(s.paid_acquisition_cost as {{ float }}) / nullif(s.paid_sustainers_started, 0) as cost_per_new_sustainer,
    case when pm.paid_sustainers_observed > 0
         then sum(pm.paid_revenue_per_observed) over (
                  partition by pm.cohort_year, pm.breakdown_by, pm.breakdown_value
                  order by pm.age_months rows between unbounded preceding and current row) end as paid_ltv_to_date
    {%- else %}
    cast(null as {{ dbt.type_int() }})                                           as paid_sustainers_started,
    cast(null as {{ dbt.type_int() }})                                           as paid_sustainers_observed,
    cast(null as {{ float }})                                                    as paid_revenue,
    cast(null as {{ float }})                                                    as cost_per_new_sustainer,
    cast(null as {{ float }})                                                    as paid_ltv_to_date
    {%- endif %}
from per_month as pm
inner join starters as s
    on  s.cohort_year     = pm.cohort_year
    and s.breakdown_by    = pm.breakdown_by
    and s.breakdown_value = pm.breakdown_value
