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
    from {{ ref('pocore_ftr__person__month_lookback') }}

)

select
    p.person_id,
    -- who they are: from the contract, so people created after the latest month-end are here too
    {%- for c in pocore_snapshot_columns('attributes') %}
    {{ 'a.' if c.startswith('attr_') else 'p.' }}{{ c }},
    {%- endfor %}

    l.as_of_month_end,

    -- their state at the latest month-end: the shared column list (macros/pocore_snapshot_columns.sql)
    {%- for c in pocore_snapshot_columns('state') %}
    s.{{ c }}{{ ',' if not loop.last }}
    {%- endfor %}
from {{ ref('pocore_can__people') }} as p
cross join latest as l
left join {{ ref('pocore_can__person_attributes') }} as a
    on a.person_id = p.person_id
left join {{ ref('pocore_ftr__person__month_lookback') }} as s
    on  s.person_id     = p.person_id
    and s.snapshot_date = l.as_of_month_end
