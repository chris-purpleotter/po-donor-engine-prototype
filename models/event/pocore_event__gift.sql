{#
pocore_event__gift — ONE ROW PER GIFT (every gift in the contract, refunds and
ineligible gifts included). The gift's own columns plus the engine's gift-level
definitions. The single source for both: rollups and the foundation read gifts ONLY from
here, never from pocore_input__gifts, so the definitions can't drift. EVENT layer: one row
per thing that happened, labelled; no aggregation.
is_qualifying         counts as "gave" (KPI `gave`): an eligible, non-refund gift
that is
one-time, or the FIRST payment of a recurring schedule (a new sign-up).
Routine recurring payments don't count.
is_recurring_payment  an eligible, non-refund recurring payment (KPI `retained`,
sustainer status)
is_first_recurring_payment   the FIRST payment of a recurring schedule: a new monthly
sign-up (KPI `started_monthly`)
gift_number           1, 2, 3 ... among the person's eligible, non-refund gifts
(null otherwise)
is_first_gift         gift_number = 1
previous_gift_date    the person's previous eligible, non-refund gift
days_since_previous_gift
is_reactivation_gift  an eligible, non-refund gift more than 365 days
(pocore_engine_config__active_days) after the previous one
#}
with
    gifts as (select * from {{ ref("pocore_input__gifts") }}),

    -- Eligible, real gifts: the ones that count as giving.
    eligible_gifts as (

        select
            gift_id,
            row_number() over (
                partition by person_id order by gift_date, gift_id
            ) as gift_number,
            lag(gift_date) over (
                partition by person_id order by gift_date, gift_id
            ) as previous_gift_date
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
    gifts.gift_id,
    gifts.person_id,
    gifts.gift_date,
    -- the gift as the contract has it (so person-level models need nothing else)
    gifts.amount,
    gifts.gift_type,
    gifts.is_refund,
    gifts.is_kpi_eligible,
    gifts.gift_category,
    gifts.recurring_schedule_id,
    gifts.exclusion_reason,
    gifts.source_system,
    gifts.source_record_id,
    {%- for c in var('gifts_extra_columns') %}
    gift_attributes.attr_{{ c }},
    {%- endfor %}
    -- the engine's definitions
    coalesce(
        gifts.is_kpi_eligible
        and not gifts.is_refund
        and (
            gifts.gift_type = 'one_time'
            or gifts.gift_date = schedule_starts.first_payment_date
        ),
        false
    ) as is_qualifying,  -- counts as "gave" -- eligible, not a refund, and one-time or first recurring gift in a schedule.
    (
        gifts.is_kpi_eligible and not gifts.is_refund and gifts.gift_type = 'recurring'
    ) as is_recurring_payment,
    coalesce(
        gifts.is_kpi_eligible
        and not gifts.is_refund
        and gifts.gift_type = 'recurring'
        and gifts.gift_date = schedule_starts.first_payment_date,
        false
    ) as is_first_recurring_payment,
    eligible_gifts.gift_number,
    coalesce(eligible_gifts.gift_number = 1, false) as is_first_gift,
    eligible_gifts.previous_gift_date,
    {{
        dbt.datediff(
            "eligible_gifts.previous_gift_date",
            "gifts.gift_date",
            "day",
        )
    }} as days_since_previous_gift,
    coalesce(
        eligible_gifts.previous_gift_date is not null
        and {{
            dbt.datediff(
                "eligible_gifts.previous_gift_date",
                "gifts.gift_date",
                "day",
            )
        }} > {{ pocore_engine_config__active_days() }},
        false
    ) as is_reactivation_gift  -- a win-back: more than 365 days (pocore_engine_config__active_days) since the person's previous gift; first gifts never count
from gifts
left join {{ ref("pocore_input__gift_attributes") }} as gift_attributes
    on gift_attributes.gift_id = gifts.gift_id
left join eligible_gifts on eligible_gifts.gift_id = gifts.gift_id
left join
    schedule_starts
    on schedule_starts.recurring_schedule_id = gifts.recurring_schedule_id
