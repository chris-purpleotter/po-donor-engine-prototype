{#
  pocore__person__segment — ONE ROW PER PERSON x SEGMENT, as of the latest month-end.
  The roster: "who is in this segment right now?", the list someone acts on (mailing, calls,
  CRM tag). Counting rows for one segment = counting its people. A person can be in several
  segments (custom segments may overlap), so filter to one segment before counting.

  Person attributes and today's state are repeated for display and filtering; they come from
  pocore_foundation__person (one row per person) and are as of month_end_date.
#}

with latest as (

    select max(month_end_date) as month_end_date
    from {{ ref('pocore_foundation__person__segment__month') }}

)

select
    m.person_id,
    m.segment_id,
    m.segment_label,
    m.segment_source,
    m.month_end_date,
    p.lifecycle_stage,
    p.acquisition_channel,
    p.region,
    p.first_gift_date,
    p.first_gift_band,
    p.last_gift_date,
    p.days_since_last_gift,
    p.gift_count_lifetime,
    p.net_giving_lifetime,
    p.net_giving_12m,
    p.is_recurring_active,
    p.is_reactivated
    {%- for c in var('people_extra_columns') %},
    p.attr_{{ c }}
    {%- endfor %}
from {{ ref('pocore_foundation__person__segment__month') }} as m
inner join latest as l
    on m.month_end_date = l.month_end_date
inner join {{ ref('pocore_foundation__person') }} as p
    on p.person_id = m.person_id
