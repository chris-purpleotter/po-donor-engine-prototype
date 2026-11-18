{#
  pocore__segment__month — ONE ROW PER SEGMENT x MONTH-END (whole segments only).
  A plain time series: how big each segment was, how many people moved in and out that
  month, and how its people behaved afterwards (every KPI window as columns):
  gave_rate_<N>d (gave a qualifying gift), retained_rate_<N>d (still an active sustainer
  N days later: the one that matters for sustainers; 90+ days only), revenue_per_person_<N>d.
  Use is_complete_<N>d to drop months whose window hasn't finished yet.
  people_in_segment is a point-in-time count: don't add it across months.
  people_entering / people_leaving ARE monthly flows: adding them across months is fine.
  gave_count_<N>d / retained_count_<N>d are the numerators behind the rates, so a BI tool can
  pool rates correctly over any set of months: sum(gave_count_90d) / sum(people_in_segment)
  (filter is_complete_90d first). Never average the rate columns.
#}

{%- set windows = pocore_kpi_windows() -%}
{%- set retained_windows = pocore_kpi_windows('retained') -%}

with outcomes as (

    select
        segment_id,
        segment_label,
        segment_source,
        parent_segment_id,
        split_by,
        split_value,
        segment_set_id,
        anchor_date                                                                       as snapshot_date,
        max(n)                                                                            as people_in_segment
        {%- for w in windows %},
        max(case when kpi_id = 'gave' and outcome_window_days = {{ w }} then value end)              as gave_rate_{{ w }}d,
        {%- if w in retained_windows %}
        max(case when kpi_id = 'retained' and outcome_window_days = {{ w }} then value end)          as retained_rate_{{ w }}d,
        cast(round(max(case when kpi_id = 'retained' and outcome_window_days = {{ w }} then value * n end)) as {{ dbt.type_int() }}) as retained_count_{{ w }}d,
        {%- endif %}
        cast(round(max(case when kpi_id = 'gave' and outcome_window_days = {{ w }} then value * n end)) as {{ dbt.type_int() }})     as gave_count_{{ w }}d,
        max(case when kpi_id = 'revenue_per_donor' and outcome_window_days = {{ w }} then value end) as revenue_per_person_{{ w }}d,
        max(case when kpi_id = 'gave' and outcome_window_days = {{ w }}
                 then case when is_window_complete then 1 else 0 end end) = 1               as is_complete_{{ w }}d
        {%- endfor %}
    from {{ ref('pocore_mtr__segment_baselines') }}
    group by segment_id, segment_label, segment_source, parent_segment_id, split_by, split_value,
             segment_set_id, anchor_date

)

select
    o.segment_id,
    o.segment_label,
    o.segment_source,
    o.parent_segment_id,
    o.split_by,
    o.split_value,
    o.segment_set_id,
    o.snapshot_date                                                                   as month_end_date,
    o.people_in_segment,
    f.donors_entering                                                                 as people_entering,
    f.donors_leaving                                                                  as people_leaving
    {%- for w in windows %},
    o.gave_rate_{{ w }}d,
    {%- if w in retained_windows %}
    o.retained_rate_{{ w }}d,
    o.retained_count_{{ w }}d,
    {%- endif %}
    o.gave_count_{{ w }}d,
    o.revenue_per_person_{{ w }}d,
    o.is_complete_{{ w }}d
    {%- endfor %}
from outcomes as o
left join {{ ref('pocore_mtr__segment_flows') }} as f
    on  f.segment_id    = o.segment_id
    and f.snapshot_date = o.snapshot_date
