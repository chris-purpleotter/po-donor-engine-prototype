{#
  pocore_foundation__gift — ONE ROW PER GIFT: every gift and refund in the `gifts` contract,
  eligible or not, so totals tie exactly to the input (checked in pocore_admin__health).

  The contract columns, the client's attr_* gift columns, and what only the engine knows
  (pocore_event__gift, the only gift source): whether the gift counts as "gave", its number in the person's
  giving history, reactivation, and the person's stage when they gave.

  A TRANSACTION FACT of the foundation star: events roll up to any period (revenue by month,
  first gifts by quarter, win-backs by fiscal year) and every amount adds up freely. Person
  attributes are NOT copied here: join pocore_foundation__person on person_id to group by them.
  source_system / source_record_id trace the gift back to its source record.

    stage_at_gift   the person's lifecycle stage at the last month-end BEFORE the gift
                    (null for gifts before the snapshot history starts)
#}

with

pocore_rollup__person__month_end_lookback as (select * from {{ ref('pocore_rollup__person__month_end_lookback') }}),

pocore_event__gift as (select * from {{ ref('pocore_event__gift') }}),

snapshots as (

    select person_id, snapshot_date, lifecycle_stage
    from pocore_rollup__person__month_end_lookback

),

-- The last month-end strictly before each gift (the month-end before the gift's month).
gift_months as (

    select
        gift_id,
        cast({{ dbt.dateadd('day', -1, dbt.date_trunc('month', 'gift_date')) }} as date) as previous_month_end
    from pocore_event__gift

)

select
    pocore_event__gift.gift_id,
    pocore_event__gift.person_id,
    pocore_event__gift.gift_date,
    pocore_event__gift.amount,
    pocore_event__gift.gift_type,
    pocore_event__gift.recurring_schedule_id,
    pocore_event__gift.is_refund,
    pocore_event__gift.gift_category,
    pocore_event__gift.is_kpi_eligible,
    pocore_event__gift.exclusion_reason,
    pocore_event__gift.source_system,
    pocore_event__gift.source_record_id,
    {%- for c in var('gifts_extra_columns') %}
    pocore_event__gift.attr_{{ c }},
    {%- endfor %}

    -- engine definitions
    pocore_event__gift.is_qualifying,
    pocore_event__gift.is_recurring_payment,
    pocore_event__gift.is_first_recurring_payment,
    pocore_event__gift.gift_number,
    pocore_event__gift.is_first_gift,
    pocore_event__gift.is_reactivation_gift,
    pocore_event__gift.previous_gift_date,
    pocore_event__gift.days_since_previous_gift,
    snapshots.lifecycle_stage                    as stage_at_gift
from pocore_event__gift
inner join gift_months
    on gift_months.gift_id = pocore_event__gift.gift_id
left join snapshots
    on  snapshots.person_id     = pocore_event__gift.person_id
    and snapshots.snapshot_date = gift_months.previous_month_end
