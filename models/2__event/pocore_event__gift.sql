{#
pocore_event__gift — ONE ROW PER GIFT (every gift in the contract, refunds and
ineligible gifts included). The gift's own columns plus the engine's gift-level
definitions. The single source for both: rollups and the foundation read gifts ONLY from
here, never from pocore_input__gifts, so the definitions can't drift. EVENT layer: one row
per thing that happened, labelled; no aggregation.
Column definitions: _pocore_event.yml.
#}
with
    pocore_input__gifts as (select * from {{ ref("pocore_input__gifts") }}),

    pocore_input__gifts_attr as (select * from {{ ref("pocore_input__gifts_attr") }}),

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
        from pocore_input__gifts
        where is_kpi_eligible and not is_refund

    ),

    -- First payment of each recurring schedule = the sign-up.
    schedule_starts as (

        select recurring_schedule_id, min(gift_date) as first_payment_date
        from pocore_input__gifts
        where is_kpi_eligible and gift_type = 'recurring' and not is_refund
        group by recurring_schedule_id

    )

select
    pocore_input__gifts.gift_id,
    pocore_input__gifts.person_id,
    pocore_input__gifts.gift_date,
    -- the gift as the contract has it (so person-level models need nothing else)
    pocore_input__gifts.amount,
    pocore_input__gifts.gift_type,
    pocore_input__gifts.is_refund,
    pocore_input__gifts.is_kpi_eligible,
    pocore_input__gifts.gift_category,
    pocore_input__gifts.recurring_schedule_id,
    pocore_input__gifts.exclusion_reason,
    pocore_input__gifts.source_system,
    pocore_input__gifts.source_record_id,
    {%- for c in var("gifts_extra_columns") %}
        pocore_input__gifts_attr.attr_{{ c }},
    {%- endfor %}
    -- the engine's definitions
    coalesce(
        pocore_input__gifts.is_kpi_eligible
        and not pocore_input__gifts.is_refund
        and (
            pocore_input__gifts.gift_type = 'one_time'
            or pocore_input__gifts.gift_date = schedule_starts.first_payment_date
        ),
        false
    ) as is_qualifying,  -- counts as "gave" -- eligible, not a refund, and one-time or first recurring gift in a schedule.
    (
        pocore_input__gifts.is_kpi_eligible
        and not pocore_input__gifts.is_refund
        and pocore_input__gifts.gift_type = 'recurring'
    ) as is_recurring_payment,
    coalesce(
        pocore_input__gifts.is_kpi_eligible
        and not pocore_input__gifts.is_refund
        and pocore_input__gifts.gift_type = 'recurring'
        and pocore_input__gifts.gift_date = schedule_starts.first_payment_date,
        false
    ) as is_first_recurring_payment,
    eligible_gifts.gift_number,
    coalesce(eligible_gifts.gift_number = 1, false) as is_first_gift,
    eligible_gifts.previous_gift_date,
    {{
        dbt.datediff(
            "eligible_gifts.previous_gift_date",
            "pocore_input__gifts.gift_date",
            "day",
        )
    }} as days_since_previous_gift,
    coalesce(
        eligible_gifts.previous_gift_date is not null
        and {{
            dbt.datediff(
                "eligible_gifts.previous_gift_date",
                "pocore_input__gifts.gift_date",
                "day",
            )
        }} > {{ pocore_engine_config__active_days() }},
        false
    ) as is_reactivation_gift  -- a win-back: more than 365 days (pocore_engine_config__active_days) since the person's previous gift; first gifts never count
from pocore_input__gifts
left join
    pocore_input__gifts_attr
    on pocore_input__gifts_attr.gift_id = pocore_input__gifts.gift_id
left join eligible_gifts on eligible_gifts.gift_id = pocore_input__gifts.gift_id
left join
    schedule_starts
    on schedule_starts.recurring_schedule_id = pocore_input__gifts.recurring_schedule_id
