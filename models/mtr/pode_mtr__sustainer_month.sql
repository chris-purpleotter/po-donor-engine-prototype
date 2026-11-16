{{ config(enabled=pode_module_enabled('sustainers')) }}

{#
  pode_mtr__sustainer_month — ONE ROW PER SUSTAINER x MONTH SINCE THEY STARTED.

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

{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}
{%- set max_months = (var('sustainer_survival_months') + var('sustainer_ltv_horizons_months')) | max -%}

with recurring_gifts as (

    select
        g.donor_id,
        cast({{ dbt.date_trunc('month', 'g.gift_date') }} as date)   as month_start,
        g.amount,
        (not g.is_refund and g.amount > 0)                            as is_payment
    from {{ ref('pode_can__gifts') }} as g
    inner join {{ ref('pode_can__donors') }} as d
        on d.donor_id = g.donor_id
    where g.gift_type = 'recurring'
      and g.is_kpi_eligible
      and d.donor_type = 'individual'
      and g.gift_date <= {{ as_of_sql }}

),

starts as (

    select donor_id, min(month_start) as start_month
    from recurring_gifts
    where is_payment
    group by donor_id

),

gift_months as (

    select
        donor_id,
        month_start,
        sum(amount)                                   as amount,
        count(case when is_payment then 1 end)        as payments
    from recurring_gifts
    group by donor_id, month_start

),

month_numbers as (

    select cast(generated_number as {{ dbt.type_int() }}) as month_number
    from ({{ dbt.generate_series(max_months) }}) as s

),

sustainer_months as (

    select
        s.donor_id,
        s.start_month,
        m.month_number,
        cast({{ dbt.dateadd('month', '(m.month_number - 1)', 's.start_month') }} as date) as month_start
    from starts as s
    cross join month_numbers as m

)

select
    sm.donor_id,
    sm.start_month,
    {{ pode_fiscal_year('sm.start_month') }}                             as start_year,
    sm.month_number,
    sm.month_start,
    coalesce(gm.payments, 0) > 0                                         as gave,
    coalesce(gm.amount, 0)                                               as amount,
    -- month k is over when the first day of the NEXT month is at most the day after as_of
    cast({{ dbt.dateadd('month', 1, 'sm.month_start') }} as date)
        <= cast({{ dbt.dateadd('day', 1, as_of_sql) }} as date)          as is_observed
from sustainer_months as sm
left join gift_months as gm
    on  gm.donor_id    = sm.donor_id
    and gm.month_start = sm.month_start
where sm.month_start <= {{ as_of_sql }}
