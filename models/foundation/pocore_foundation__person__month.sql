{#
  pocore_foundation__person__month — ONE ROW PER PERSON x MONTH-END (the last
  `snapshot_lookback_months` month-ends up to as_of, from the month the person existed).

  Each row looks both ways from its month-end ("as of, no peeking"):
    BACKWARD (features): what was true about the person on that date, using only gifts on
      or before it. The ingredients sit next to the derived values (days_since_last_gift,
      gift_count_12m ... next to lifecycle_stage).
    FORWARD (outcomes): what the person did in the N days AFTER that date: gave_<N>d,
      started_monthly_<N>d (signed up to a new monthly plan),
      revenue_<N>d (capped), revenue_uncapped_<N>d, retained_<N>d, and is_complete_<N>d
      (false while the window hasn't fully happened yet: never treat those as final).

  This is the table every engine baseline is built from, and a leakage-safe training set
  for prediction models (features as of each month-end, outcomes after it).

  Not summable across rows: lifetime, 12-month, year-to-date and prior-year values are
  running totals as of each month-end. Summing them over months counts gifts many times.
  For giving per period use pocore_foundation__gift or pocore__person__year.
#}

{%- set windows = pocore_kpi_windows() -%}
{%- set retained_windows = pocore_kpi_windows('retained') -%}

select
    s.person_id,
    s.snapshot_date                        as month_end_date,

    -- person attributes (current values, D7) and state as of month_end_date: the shared column
    -- list (macros/pocore_snapshot_columns.sql), so this table and pocore_foundation__person match
    {%- for c in pocore_snapshot_columns('attributes') + pocore_snapshot_columns('state') %}
    s.{{ c }},
    {%- endfor %}

    -- outcomes after month_end_date
    {%- for w in windows %}
    o.gave_{{ w }}d,
    o.started_monthly_{{ w }}d,
    o.revenue_{{ w }}d,
    o.revenue_uncapped_{{ w }}d,
    {%- if w in retained_windows %}
    o.retained_{{ w }}d,
    {%- endif %}
    o.is_complete_{{ w }}d{{ ',' if not loop.last }}
    {%- endfor %}
from {{ ref('pocore_ftr__person_snapshot') }} as s
inner join {{ ref('pocore_ftr__kpi_outcomes') }} as o
    on  o.person_id   = s.person_id
    and o.anchor_date = s.snapshot_date
