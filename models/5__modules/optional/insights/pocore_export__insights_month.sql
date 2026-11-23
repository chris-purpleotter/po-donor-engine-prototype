{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_month — ONE ROW PER CALENDAR MONTH (the last 36 up to as_of): what
  happened across the whole organisation that month. For the report's "What happened" tab.
  Individuals' KPI-eligible gifts, counted in the month they were made: these are events, so
  months add up (a quarter = its three months), except `donors` (distinct people that month).

    new_donors        first-ever gifts
    win_backs         gifts after more than 12 months without giving (pocore_engine_config__active_days)
    monthly_signups   first payments of new monthly plans
    gifts             gifts (refunds excluded)
    donors            distinct people who gave that month
    giving            net giving (refunds subtracted)
#}

with

pocore_foundation__gift as (select * from {{ ref('pocore_foundation__gift') }}),

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

pocore_foundation__date as (select * from {{ ref('pocore_foundation__date') }}),

months as (

    select distinct month_start_date
    from pocore_foundation__date
    where month_start_date >= cast({{ dbt.dateadd('month', -35, dbt.date_trunc('month', pocore_client_config__as_of_date())) }} as date)

),

gifts as (

    select pocore_foundation__date.month_start_date, pocore_foundation__gift.*
    from pocore_foundation__gift
    inner join pocore_foundation__date
        on pocore_foundation__date.date_day = pocore_foundation__gift.gift_date
    inner join pocore_foundation__person
        on pocore_foundation__person.person_id = pocore_foundation__gift.person_id
    where pocore_foundation__gift.is_kpi_eligible
      and pocore_foundation__person.person_type = 'individual'

)

select
    months.month_start_date,
    count(case when gifts.is_first_gift then 1 end)                          as new_donors,
    count(case when gifts.is_reactivation_gift then 1 end)                   as win_backs,
    count(case when gifts.is_first_recurring_payment then 1 end)             as monthly_signups,
    count(case when not gifts.is_refund then 1 end)                          as gifts,
    count(distinct case when not gifts.is_refund then gifts.person_id end)   as donors,
    coalesce(sum(gifts.amount), 0)                                           as giving
from months
left join gifts
    on gifts.month_start_date = months.month_start_date
group by months.month_start_date
