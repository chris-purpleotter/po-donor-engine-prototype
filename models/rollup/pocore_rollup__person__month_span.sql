{#
  pocore_rollup__person__month_span — ONE ROW PER PERSON x CALENDAR MONTH IN WHICH THEY HAD
  KPI-ELIGIBLE ACTIVITY (a gift or a refund). Months with nothing are absent, not zero.

  A SPAN: only counts and sums of the gifts that fall INSIDE the month. Months don't overlap,
  so every column adds up freely, across people AND across months (Jan + Feb + Mar = Q1).
  For "as of" values (lifetime, last 12 months, days since) use the month_end tables instead.

    gifts               eligible gifts, refunds excluded
    amount              net eligible giving (refunds subtracted)
    qualifying_gifts    gifts that count as "gave" (one-time, or the first payment of a schedule)
    recurring_payments  recurring payments
    first_gifts         the person's first-ever eligible gift (0 or 1 per person, once ever)
    reactivation_gifts  win-back gifts (more than 365 days after the previous one)

  Reads gifts ONLY from pocore_fact__gift (the source rule).
#}

with gifts as (

    select
        person_id,
        cast({{ dbt.date_trunc('month', 'gift_date') }} as date) as month_start_date,
        amount,
        is_refund,
        is_qualifying,
        is_recurring_payment,
        is_first_gift,
        is_reactivation_gift
    from {{ ref('pocore_fact__gift') }}
    where is_kpi_eligible

)

select
    person_id,
    month_start_date,
    count(case when not is_refund then 1 end)            as gifts,
    sum(amount)                                          as amount,
    count(case when is_qualifying then 1 end)            as qualifying_gifts,
    count(case when is_recurring_payment then 1 end)     as recurring_payments,
    count(case when is_first_gift then 1 end)            as first_gifts,
    count(case when is_reactivation_gift then 1 end)     as reactivation_gifts
from gifts
group by person_id, month_start_date
