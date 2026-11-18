{#
  pocore_foundation__person — ONE ROW PER PERSON (everyone in the `people` contract,
  with or without gifts).

  Who each person is (contract attributes, client attr_* columns) and their state TODAY:
  the values from the latest month-end snapshot (as_of_month_end). People created after
  that month-end have null state columns until the next run.

  Foundation: tested facts and definitions to build on. The ingredients sit next to the
  derived values (days_since_last_gift, gift_count_12m ... next to lifecycle_stage), so a
  different definition of "lapsed" can be rebuilt from the same row.
#}

with latest as (

    select max(snapshot_date) as as_of_month_end
    from {{ ref('pocore_ftr__person_snapshot') }}

)

select
    p.person_id,
    p.created_at,
    p.person_type,
    p.is_deceased,
    p.region,
    p.acquisition_channel,
    p.acquisition_theme,
    {%- for c in var('people_extra_columns') %}
    a.attr_{{ c }},
    {%- endfor %}

    l.as_of_month_end,

    -- current state (derived)
    s.lifecycle_stage,
    s.is_new_donor,
    s.is_reactivated,
    s.is_recurring_active,
    s.gave_prior_year_not_ytd,

    -- ingredients
    s.first_gift_date,
    s.first_gift_amount,
    s.first_gift_band,
    s.last_gift_date,
    s.days_since_first_gift,
    s.days_since_last_gift,
    s.days_since_last_recurring,
    s.gift_count_12m,
    s.net_giving_12m,
    s.gift_count_lifetime,
    s.net_giving_lifetime,
    s.net_giving_ytd,
    s.net_giving_prior_year
from {{ ref('pocore_can__people') }} as p
cross join latest as l
left join {{ ref('pocore_can__person_attributes') }} as a
    on a.person_id = p.person_id
left join {{ ref('pocore_ftr__person_snapshot') }} as s
    on  s.person_id     = p.person_id
    and s.snapshot_date = l.as_of_month_end
