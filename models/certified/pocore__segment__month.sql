{#
  pocore__segment__month — ONE ROW PER SEGMENT x MONTH-END (whole segments only).
  A plain time series: how big each segment was, how many people moved in and out that
  month, and how its people behaved afterwards (every KPI window as columns):
  gave_rate_<N>d (gave a qualifying gift), retained_rate_<N>d (still an active sustainer
  N days later: the one that matters for sustainers; 90+ days only), revenue_per_person_<N>d
  (average revenue per person in the window, each person capped at revenue_cap: for planning
  maths) and revenue_per_person_uncapped_<N>d (actual dollars: for "how much did they give").
  Use is_complete_<N>d to drop months whose window hasn't finished yet.

  THE GROUP'S OWN MEASURE (v0.3.7), so simple queries need no CASE over measure columns:
    primary_kpi, primary_window_days   the group's measure and headline window (as pocore__segment)
    primary_rate, primary_count,       that measure at that window: the headline number
    is_primary_complete
    primary_rate_<N>d, primary_count_<N>d   that measure at every window (null where the measure
                                       has no such window: retained at 30 days)
  e.g. trend:  select month_end_date, primary_rate from ... where segment_id = 'x' and is_primary_complete
  people_in_segment is a point-in-time count: don't add it across months.
  people_entering / people_leaving ARE monthly flows: adding them across months is fine.
  gave_count_<N>d / retained_count_<N>d are the numerators behind the rates, so a BI tool can
  pool rates correctly over any set of months: sum(gave_count_90d) / sum(people_in_segment)
  (filter is_complete_90d first). Never average the rate columns.
#}

{%- set windows = pocore_engine_config__kpi_windows() -%}
{%- set retained_windows = pocore_engine_config__kpi_windows('retained') -%}
{%- set measure_ids = pocore_engine_config__measure_ids() -%}

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
        max(case when kpi_id = 'started_monthly' and outcome_window_days = {{ w }} then value end)   as started_monthly_rate_{{ w }}d,
        cast(round(max(case when kpi_id = 'started_monthly' and outcome_window_days = {{ w }} then value * n end)) as {{ dbt.type_int() }}) as started_monthly_count_{{ w }}d,
        max(case when kpi_id = 'revenue_per_donor' and outcome_window_days = {{ w }} then value end) as revenue_per_person_{{ w }}d,
        max(case when kpi_id = 'revenue_per_donor' and outcome_window_days = {{ w }} then value_uncapped end) as revenue_per_person_uncapped_{{ w }}d,
        max(case when kpi_id = 'gave' and outcome_window_days = {{ w }}
                 then case when is_window_complete then 1 else 0 end end) = 1               as is_complete_{{ w }}d
        {%- endfor %}
    from {{ ref('pocore_group__baselines__month') }}
    group by segment_id, segment_label, segment_source, parent_segment_id, split_by, split_value,
             segment_set_id, anchor_date

),

primary_choices as (
    {{ pocore_sql__primary_choices() }}
),

-- the group's own measure at every window (picked from the columns above)
with_primary as (

    select
        o.*,
        pc.primary_kpi,
        pc.primary_window_days
        {%- for w in windows %},
        case pc.primary_kpi
            {%- for k in measure_ids if w in pocore_engine_config__kpi_windows(k) %}
            when '{{ k }}' then o.{{ k }}_rate_{{ w }}d
            {%- endfor %}
        end                                                                           as primary_rate_{{ w }}d,
        case pc.primary_kpi
            {%- for k in measure_ids if w in pocore_engine_config__kpi_windows(k) %}
            when '{{ k }}' then o.{{ k }}_count_{{ w }}d
            {%- endfor %}
        end                                                                           as primary_count_{{ w }}d
        {%- endfor %}
    from outcomes as o
    left join primary_choices as pc
        on pc.segment_id = coalesce(o.parent_segment_id, '__remainder__')

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
    f.donors_leaving                                                                  as people_leaving,
    o.primary_kpi,
    o.primary_window_days,
    case o.primary_window_days
        {%- for w in windows %}
        when {{ w }} then o.primary_rate_{{ w }}d
        {%- endfor %}
    end                                                                               as primary_rate,
    case o.primary_window_days
        {%- for w in windows %}
        when {{ w }} then o.primary_count_{{ w }}d
        {%- endfor %}
    end                                                                               as primary_count,
    case o.primary_window_days
        {%- for w in windows %}
        when {{ w }} then o.is_complete_{{ w }}d
        {%- endfor %}
    end                                                                               as is_primary_complete
    {%- for w in windows %},
    o.primary_rate_{{ w }}d,
    o.primary_count_{{ w }}d
    {%- endfor %}
    {%- for w in windows %},
    o.gave_rate_{{ w }}d,
    {%- if w in retained_windows %}
    o.retained_rate_{{ w }}d,
    o.retained_count_{{ w }}d,
    {%- endif %}
    o.gave_count_{{ w }}d,
    o.started_monthly_rate_{{ w }}d,
    o.started_monthly_count_{{ w }}d,
    o.revenue_per_person_{{ w }}d,
    o.revenue_per_person_uncapped_{{ w }}d,
    o.is_complete_{{ w }}d
    {%- endfor %}
from with_primary as o
left join {{ ref('pocore_group__flows__month') }} as f
    on  f.segment_id    = o.segment_id
    and f.snapshot_date = o.snapshot_date
