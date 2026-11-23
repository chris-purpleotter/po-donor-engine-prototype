{{ config(enabled=pocore_client_config__module_enabled('cohort')) }}

{#
  pocore_cohort__person__sustainer_age — ONE ROW PER SUSTAINER x MONTH SINCE THEY STARTED.

    start_month    calendar month of the donor's first recurring payment (= month 1)
    month_number   1, 2, 3 ... up to the longest horizon in the sustainer vars
    gave           at least one real recurring payment that calendar month
    amount         net recurring revenue that month (refunds of recurring gifts subtract)
    is_observed    the month has fully happened (ends on or before as_of)

  Only months that have started by as_of get a row, so a sustainer who started this month
  still counts as a starter (one row, is_observed = false).

  Sustainer = donor-level, not schedule-level: a donor who stops and restarts (a new
  schedule) keeps their original start; their later payments count as "still giving".
  Revenue is recurring payments only (one-time gifts from sustainers are not sustainer LTV).
  Individuals only, KPI-eligible gifts only (consistent with the other metrics).
#}

{%- set max_months = (pocore_client_config__module('cohort').survival_months + pocore_client_config__module('cohort').ltv_horizons_months) | max -%}

with

pocore_foundation__gift as (select * from {{ ref('pocore_foundation__gift') }}),

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

recurring_gifts as (

    select
        pocore_foundation__gift.person_id,
        cast({{ dbt.date_trunc('month', 'pocore_foundation__gift.gift_date') }} as date)   as month_start,
        pocore_foundation__gift.amount,
        (not pocore_foundation__gift.is_refund and pocore_foundation__gift.amount > 0)                            as is_payment
    from pocore_foundation__gift
    inner join pocore_foundation__person as person
        on person.person_id = pocore_foundation__gift.person_id
    where pocore_foundation__gift.gift_type = 'recurring'
      and pocore_foundation__gift.is_kpi_eligible
      and person.person_type = 'individual'
      and pocore_foundation__gift.gift_date <= {{ pocore_client_config__as_of_date() }}

),

starts as (

    select person_id, min(month_start) as start_month
    from recurring_gifts
    where is_payment
    group by person_id

),

gift_months as (

    select
        person_id,
        month_start,
        sum(amount)                                   as amount,
        count(case when is_payment then 1 end)        as payments
    from recurring_gifts
    group by person_id, month_start

),

month_numbers as (

    select cast(generated_number as {{ dbt.type_int() }}) as month_number
    from ({{ dbt.generate_series(max_months) }}) as series

),

sustainer_months as (

    select
        starts.person_id,
        starts.start_month,
        month_numbers.month_number,
        cast({{ dbt.dateadd('month', '(month_numbers.month_number - 1)', 'starts.start_month') }} as date) as month_start
    from starts
    cross join month_numbers

)

select
    sustainer_months.person_id,
    sustainer_months.start_month,
    {{ pocore_helpers__fiscal_year('sustainer_months.start_month') }}                             as start_year,
    sustainer_months.month_number,
    sustainer_months.month_start,
    coalesce(gift_months.payments, 0) > 0                                         as gave,
    coalesce(gift_months.amount, 0)                                               as amount,
    -- month k is over when the first day of the NEXT month is at most the day after as_of
    cast({{ dbt.dateadd('month', 1, 'sustainer_months.month_start') }} as date)
        <= cast({{ dbt.dateadd('day', 1, pocore_client_config__as_of_date()) }} as date)          as is_observed
from sustainer_months
left join gift_months
    on  gift_months.person_id    = sustainer_months.person_id
    and gift_months.month_start = sustainer_months.month_start
where sustainer_months.month_start <= {{ pocore_client_config__as_of_date() }}
