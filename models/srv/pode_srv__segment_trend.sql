{#
  pode_srv__segment_trend — ONE ROW PER SEGMENT PER MONTH-END (whole segments only).
  A plain time series: how big each segment was, how many donors moved in and out that
  month, and how its donors behaved afterwards (every KPI window as columns):
  gave_rate_<N>d (gave a qualifying gift), retained_rate_<N>d (still an active sustainer
  N days later: the one that matters for sustainers), revenue_per_donor_<N>d.
  Use is_complete_<N>d to drop months whose window hasn't finished yet.
  donors_in_segment is a point-in-time count: don't add it across months.
  donors_entering / donors_leaving ARE monthly flows: adding them across months is fine.
  gave_count_<N>d / retained_count_<N>d are the numerators behind the rates, so a BI tool can
  pool rates correctly over any set of months: sum(gave_count_90d) / sum(donors_in_segment)
  (filter is_complete_90d first). Never average the rate columns.
#}

{%- set windows = var('kpi_windows_days') -%}

with outcomes as (

    select
        segment_id,
        segment_label,
        segment_source,
        anchor_date                                                                       as snapshot_date,
        max(n)                                                                            as donors_in_segment
        {%- for w in windows %},
        max(case when kpi_id = 'gave' and outcome_window_days = {{ w }} then value end)              as gave_rate_{{ w }}d,
        max(case when kpi_id = 'retained' and outcome_window_days = {{ w }} then value end)          as retained_rate_{{ w }}d,
        cast(round(max(case when kpi_id = 'gave' and outcome_window_days = {{ w }} then value * n end)) as {{ dbt.type_int() }})     as gave_count_{{ w }}d,
        cast(round(max(case when kpi_id = 'retained' and outcome_window_days = {{ w }} then value * n end)) as {{ dbt.type_int() }}) as retained_count_{{ w }}d,
        max(case when kpi_id = 'revenue_per_donor' and outcome_window_days = {{ w }} then value end) as revenue_per_donor_{{ w }}d,
        max(case when kpi_id = 'gave' and outcome_window_days = {{ w }}
                 then case when is_window_complete then 1 else 0 end end) = 1               as is_complete_{{ w }}d
        {%- endfor %}
    from {{ ref('pode_mtr__segment_baselines') }}
    where breakdown = 'all'
    group by segment_id, segment_label, segment_source, anchor_date

)

select
    o.segment_id,
    o.segment_label,
    o.segment_source,
    o.snapshot_date,
    o.donors_in_segment,
    f.donors_entering,
    f.donors_leaving
    {%- for w in windows %},
    o.gave_rate_{{ w }}d,
    o.retained_rate_{{ w }}d,
    o.gave_count_{{ w }}d,
    o.retained_count_{{ w }}d,
    o.revenue_per_donor_{{ w }}d,
    o.is_complete_{{ w }}d
    {%- endfor %}
from outcomes as o
left join {{ ref('pode_mtr__segment_flows') }} as f
    on  f.segment_id    = o.segment_id
    and f.snapshot_date = o.snapshot_date
