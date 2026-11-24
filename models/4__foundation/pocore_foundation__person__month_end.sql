{#
  pocore_foundation__person__month_end — ONE ROW PER PERSON x MONTH-END (the last
  `snapshot_lookback_months` month-ends up to as_of, from the month the person existed).
  The SNAPSHOT FACT of the foundation star: a MOMENT, so never sum across month-ends.

  Each row looks both ways from its month-end ("as of, no peeking"):
    BACKWARD (features): what was true about the person on that date, using only gifts on
      or before it. The ingredients sit next to the derived values (days_since_last_gift,
      gift_count_12m ... next to lifecycle_stage).
    FORWARD (outcomes): what the person did in the N days AFTER that date: gave_<N>d,
      started_monthly_<N>d (signed up to a new monthly plan),
      revenue_<N>d (capped), revenue_uncapped_<N>d, retained_<N>d, and is_complete_<N>d
      (false while the window hasn't fully happened yet: never treat those as final), and
      next_gave_date (the first qualifying gift in the 365 days after; null if none).

  This is the table every engine baseline is built from, and a leakage-safe training set
  for prediction models (features as of each month-end, outcomes after it).

  Not summable across month-ends: lifetime, 12-month, year-to-date and prior-year values are
  running totals as of each month-end, and outcome windows overlap. Sum across PEOPLE at one
  month-end only. For giving per period use pocore_foundation__gift.
  Who the person is (region, channel, attr_*): join pocore_foundation__person on person_id.
#}

{%- set windows = pocore_engine_config__kpi_windows() -%}
{%- set retained_windows = pocore_engine_config__kpi_windows('retained') -%}

with

pocore_rollup__person__month_end_lookback as (select * from {{ ref('pocore_rollup__person__month_end_lookback') }}),

pocore_rollup__person__month_end_lookahead as (select * from {{ ref('pocore_rollup__person__month_end_lookahead') }})

select
    pocore_rollup__person__month_end_lookback.person_id,
    pocore_rollup__person__month_end_lookback.snapshot_date                        as month_end_date,

    -- state as of month_end_date (looking back): the column list in macros/columns/pocore_columns__person_month_end.sql
    {%- for c in pocore_columns__person_month_end() %}
    pocore_rollup__person__month_end_lookback.{{ c }},
    {%- endfor %}

    -- outcomes after month_end_date
    pocore_rollup__person__month_end_lookahead.next_gave_date,
    {%- for w in windows %}
    pocore_rollup__person__month_end_lookahead.gave_{{ w }}d,
    pocore_rollup__person__month_end_lookahead.started_monthly_{{ w }}d,
    pocore_rollup__person__month_end_lookahead.revenue_{{ w }}d,
    pocore_rollup__person__month_end_lookahead.revenue_uncapped_{{ w }}d,
    {%- if w in retained_windows %}
    pocore_rollup__person__month_end_lookahead.retained_{{ w }}d,
    {%- endif %}
    pocore_rollup__person__month_end_lookahead.is_complete_{{ w }}d{{ ',' if not loop.last }}
    {%- endfor %}
from pocore_rollup__person__month_end_lookback
inner join pocore_rollup__person__month_end_lookahead
    on  pocore_rollup__person__month_end_lookahead.person_id   = pocore_rollup__person__month_end_lookback.person_id
    and pocore_rollup__person__month_end_lookahead.anchor_date = pocore_rollup__person__month_end_lookback.snapshot_date
