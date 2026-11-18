{#
  pocore_foundation__gift — ONE ROW PER GIFT: every gift and refund in the `gifts` contract,
  eligible or not, so totals tie exactly to the input (checked in pocore_admin__health).

  The contract columns, the client's attr_* gift columns, and what only the engine knows
  (pocore_ftr__gift_flags): whether the gift counts as "gave", its number in the person's
  giving history, reactivation, and the person's stage when they gave.

  Events roll up to any period: revenue by month, first gifts (new donors) by quarter,
  reactivation gifts by fiscal year. Person attributes are repeated on each row so you can
  group by them; no person-level MEASURES are repeated (they would be wrong to sum).

    stage_at_gift   the person's lifecycle stage at the last month-end BEFORE the gift
                    (null for gifts before the snapshot history starts)
#}

with snapshots as (

    select person_id, snapshot_date, lifecycle_stage
    from {{ ref('pocore_ftr__person_snapshot') }}

),

-- The last month-end strictly before each gift (the month-end before the gift's month).
gift_months as (

    select
        gift_id,
        cast({{ dbt.dateadd('day', -1, dbt.date_trunc('month', 'gift_date')) }} as date) as previous_month_end
    from {{ ref('pocore_can__gifts') }}

)

select
    g.gift_id,
    g.person_id,
    g.gift_date,
    g.amount,
    g.gift_type,
    g.recurring_schedule_id,
    g.is_refund,
    g.gift_category,
    g.is_kpi_eligible,
    g.exclusion_reason,
    {%- for c in var('gifts_extra_columns') %}
    ga.attr_{{ c }},
    {%- endfor %}

    -- engine definitions (pocore_ftr__gift_flags)
    f.is_qualifying,
    f.is_recurring_payment,
    f.gift_number,
    f.is_first_gift,
    f.is_reactivation_gift,
    f.previous_gift_date,
    f.days_since_previous_gift,
    s.lifecycle_stage                    as stage_at_gift,

    -- person attributes (repeated for grouping; never sum anything from here per person)
    p.person_type,
    p.region,
    p.acquisition_channel
from {{ ref('pocore_can__gifts') }} as g
inner join {{ ref('pocore_ftr__gift_flags') }} as f
    on f.gift_id = g.gift_id
inner join gift_months as gm
    on gm.gift_id = g.gift_id
left join snapshots as s
    on  s.person_id     = g.person_id
    and s.snapshot_date = gm.previous_month_end
left join {{ ref('pocore_can__gift_attributes') }} as ga
    on ga.gift_id = g.gift_id
left join {{ ref('pocore_can__people') }} as p
    on p.person_id = g.person_id
