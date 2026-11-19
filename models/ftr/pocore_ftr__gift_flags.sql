{#
  pocore_ftr__gift_flags — ONE ROW PER GIFT (every gift in the contract, refunds and
  ineligible gifts included). The single source of the engine's gift-level definitions, read
  by the person snapshot, the KPI outcomes and pocore_foundation__gift, so they can't drift.

    is_qualifying         counts as "gave" (KPI `gave`): an eligible, non-refund gift that is
                          one-time, or the FIRST payment of a recurring schedule (a new sign-up).
                          Routine recurring payments don't count.
    is_recurring_payment  an eligible, non-refund recurring payment (KPI `retained`, sustainer status)
    is_recurring_signup   the FIRST payment of a recurring schedule: a new monthly sign-up (KPI `started_monthly`)
    gift_number           1, 2, 3 ... among the person's eligible, non-refund gifts (null otherwise)
    is_first_gift         gift_number = 1
    previous_gift_date    the person's previous eligible, non-refund gift
    days_since_previous_gift
    is_reactivation_gift  an eligible, non-refund gift more than 365 days (pocore_active_days) after the previous one
#}

with gifts as (

    select * from {{ ref('pocore_can__gifts') }}

),

-- Eligible, real gifts: the ones that count as giving.
positive as (

    select
        gift_id,
        row_number() over (partition by person_id order by gift_date, gift_id) as gift_number,
        lag(gift_date) over (partition by person_id order by gift_date, gift_id) as previous_gift_date
    from gifts
    where is_kpi_eligible and not is_refund

),

-- First payment of each recurring schedule = the sign-up.
schedule_starts as (

    select recurring_schedule_id, min(gift_date) as first_payment_date
    from gifts
    where is_kpi_eligible and gift_type = 'recurring' and not is_refund
    group by recurring_schedule_id

)

select
    g.gift_id,
    g.person_id,
    g.gift_date,
    (g.is_kpi_eligible and not g.is_refund
        and (g.gift_type = 'one_time' or g.gift_date = s.first_payment_date))       as is_qualifying,
    (g.is_kpi_eligible and not g.is_refund and g.gift_type = 'recurring')           as is_recurring_payment,
    coalesce(g.is_kpi_eligible and not g.is_refund and g.gift_type = 'recurring'
             and g.gift_date = s.first_payment_date, false)                         as is_recurring_signup,
    p.gift_number,
    coalesce(p.gift_number = 1, false)                                               as is_first_gift,
    p.previous_gift_date,
    {{ dbt.datediff('p.previous_gift_date', 'g.gift_date', 'day') }}                 as days_since_previous_gift,
    coalesce(p.previous_gift_date is not null
        and {{ dbt.datediff('p.previous_gift_date', 'g.gift_date', 'day') }} > {{ pocore_active_days() }}, false) as is_reactivation_gift
from gifts as g
left join positive as p
    on p.gift_id = g.gift_id
left join schedule_starts as s
    on s.recurring_schedule_id = g.recurring_schedule_id
