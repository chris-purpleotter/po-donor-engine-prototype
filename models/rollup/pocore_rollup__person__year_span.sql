{#
  pocore_rollup__person__year_span — ONE ROW PER PERSON x FISCAL YEAR IN WHICH THEY HAD
  KPI-ELIGIBLE ACTIVITY (a gift or a refund). Years with nothing are absent, not zero.

  A SPAN: only counts and sums of the gifts that fall INSIDE the fiscal year (var
  fiscal_year_start_month). Years don't overlap, so every column adds up freely, across people
  AND across years. Same columns as pocore_rollup__person__month_span.

  Reads gifts ONLY from pocore_fact__gift (the source rule).
#}

with gifts as (

    select
        person_id,
        {{ pocore_fiscal_year('gift_date') }} as fiscal_year,
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
    fiscal_year,
    count(case when not is_refund then 1 end)            as gifts,
    sum(amount)                                          as amount,
    count(case when is_qualifying then 1 end)            as qualifying_gifts,
    count(case when is_recurring_payment then 1 end)     as recurring_payments,
    count(case when is_first_gift then 1 end)            as first_gifts,
    count(case when is_reactivation_gift then 1 end)     as reactivation_gifts
from gifts
group by person_id, fiscal_year
