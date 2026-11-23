{{ config(enabled=pocore_client_config__module_enabled('cohort')) }}

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

{%- set max_months = (pocore_client_config__module('cohort').survival_months + pocore_client_config__module('cohort').ltv_horizons_months) | max -%}
{%- set has_cost = 'acquisition_cost' in var('people_extra_columns') -%}
{%- set float = dbt.type_float() -%}

with

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

pocore_cohort__person__sustainer_age as (select * from {{ ref('pocore_cohort__person__sustainer_age') }}),

people as (

    select
        person_id,
        coalesce(acquisition_channel, 'unknown')                         as acquisition_channel,
        {%- if has_cost %}
        cast(attr_acquisition_cost as {{ float }})                       as acquisition_cost
        {%- else %}
        cast(null as {{ float }})                                        as acquisition_cost
        {%- endif %}
    from pocore_foundation__person

),

tagged as (

    select pocore_cohort__person__sustainer_age.*, people.acquisition_channel, people.acquisition_cost
    from pocore_cohort__person__sustainer_age
    inner join people
        on people.person_id = pocore_cohort__person__sustainer_age.person_id
    where pocore_cohort__person__sustainer_age.month_number <= {{ max_months }}

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
        months.*,
        case when months.sustainers_observed > 0
             then cast(months.revenue as {{ float }}) / months.sustainers_observed end           as revenue_per_observed,
        case when months.paid_sustainers_observed > 0
             then cast(months.paid_revenue as {{ float }}) / months.paid_sustainers_observed end as paid_revenue_per_observed
    from months

)

select
    'first_recurring'                                                            as cohort_type,
    per_month.cohort_year,
    per_month.breakdown_by,
    per_month.breakdown_value,
    per_month.age_months,
    starters.sustainers_started,
    per_month.sustainers_observed,
    per_month.sustainers_giving,
    case when per_month.sustainers_observed > 0
         then cast(per_month.sustainers_giving as {{ float }}) / per_month.sustainers_observed end as survival_rate,
    per_month.revenue,
    -- observation is monotone (reaching month N means months 1..N-1 were reached), so when
    -- month N is observed every earlier term exists
    case when per_month.sustainers_observed > 0
         then sum(per_month.revenue_per_observed) over (
                  partition by per_month.cohort_year, per_month.breakdown_by, per_month.breakdown_value
                  order by per_month.age_months rows between unbounded preceding and current row) end as ltv_to_date,
    {%- if has_cost %}
    starters.paid_sustainers_started,
    per_month.paid_sustainers_observed,
    per_month.paid_revenue,
    cast(starters.paid_acquisition_cost as {{ float }}) / nullif(starters.paid_sustainers_started, 0) as cost_per_new_sustainer,
    case when per_month.paid_sustainers_observed > 0
         then sum(per_month.paid_revenue_per_observed) over (
                  partition by per_month.cohort_year, per_month.breakdown_by, per_month.breakdown_value
                  order by per_month.age_months rows between unbounded preceding and current row) end as paid_ltv_to_date
    {%- else %}
    cast(null as {{ dbt.type_int() }})                                           as paid_sustainers_started,
    cast(null as {{ dbt.type_int() }})                                           as paid_sustainers_observed,
    cast(null as {{ float }})                                                    as paid_revenue,
    cast(null as {{ float }})                                                    as cost_per_new_sustainer,
    cast(null as {{ float }})                                                    as paid_ltv_to_date
    {%- endif %}
from per_month
inner join starters
    on  starters.cohort_year     = per_month.cohort_year
    and starters.breakdown_by    = per_month.breakdown_by
    and starters.breakdown_value = per_month.breakdown_value
