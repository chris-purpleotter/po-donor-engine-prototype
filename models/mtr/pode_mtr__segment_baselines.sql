{#
  pode_mtr__segment_baselines — how each segment has historically performed (SPEC §3.1).
  INTERNAL metrics layer: the full long table that the srv models read from. Not exposed —
  it mixes whole-segment and slice rows, so naive aggregation double-counts.
  One row per segment_id x breakdown x breakdown_value x kpi_id x outcome_window_days x anchor_date.

  For every segment at every anchor date: who was in it (pode_seg__membership) and what
  they did afterwards (pode_ftr__kpi_outcomes), aggregated.
    kpi 'gave'              metric_type 'rate'  value = share who gave,  variance = p(1-p)
    kpi 'retained'          metric_type 'rate'  value = share still an active sustainer at window end
    kpi 'revenue_per_donor' metric_type 'mean'  value = capped mean,     variance = sample variance

  revenue_gap_per_success (rate KPIs only): capped revenue per donor among those who
  succeeded minus among those who didn't, over the same window. What one extra success has
  been worth, observationally; used for the srv opportunity estimate. Null for mean KPIs.

  Breakdowns (var `baseline_breakdowns`): each listed snapshot column also gets one row per
  value, e.g. breakdown = 'acquisition_channel', breakdown_value = 'Face to Face'.
  breakdown = 'all' is the whole segment. Missing values show as 'unknown'.
  Breakdown columns are current values: allowed only for attributes that don't change
  because of giving (D7).

  Rows whose window hasn't fully elapsed are kept but flagged (is_window_complete = false);
  they are partial and must never be pooled or reported as final.
#}

{%- set windows = var('kpi_windows_days') -%}
{%- set breakdowns = var('baseline_breakdowns') -%}
{%- set float_type = dbt.type_float() -%}

with joined as (

    -- o.* already includes donor_id and anchor_date (= m.snapshot_date by the join);
    -- selecting them again would duplicate column names, which BigQuery rejects.
    select
        m.segment_id,
        m.segment_label,
        m.segment_source,
        {%- for b in breakdowns %}
        coalesce(cast(s.{{ b }} as {{ dbt.type_string() }}), 'unknown') as bd_{{ b }},
        {%- endfor %}
        o.*
    from {{ ref('pode_seg__membership') }} as m
    inner join {{ ref('pode_ftr__kpi_outcomes') }} as o
        on  o.donor_id    = m.donor_id
        and o.anchor_date = m.snapshot_date
    inner join {{ ref('pode_ftr__donor_snapshot') }} as s
        on  s.donor_id    = m.donor_id
        and s.snapshot_date  = m.snapshot_date

),

-- One aggregation for the whole segment ('all') plus one per breakdown column.
aggregated as (
    {%- for b in ['all'] + breakdowns %}

    select
        segment_id,
        segment_label,
        segment_source,
        '{{ b }}'                                                as breakdown,
        {% if b == 'all' %}'all'{% else %}bd_{{ b }}{% endif %} as breakdown_value,
        anchor_date,
        count(*) as n,
        {%- for w in windows %}
        {%- for k in ['gave', 'retained'] %}
        avg(cast({{ k }}_{{ w }}d as {{ float_type }}))                                       as {{ k }}_{{ w }}d_rate,
        avg(case when {{ k }}_{{ w }}d = 1 then cast(revenue_{{ w }}d as {{ float_type }}) end)
            - coalesce(avg(case when {{ k }}_{{ w }}d = 0 then cast(revenue_{{ w }}d as {{ float_type }}) end), 0)
                                                                                           as {{ k }}_{{ w }}d_revenue_gap,
        {%- endfor %}
        avg(cast(revenue_{{ w }}d as {{ float_type }}))          as revenue_{{ w }}d_mean,
        var_samp(cast(revenue_{{ w }}d as {{ float_type }}))     as revenue_{{ w }}d_var,
        avg(cast(revenue_uncapped_{{ w }}d as {{ float_type }})) as revenue_uncapped_{{ w }}d_mean,
        max(case when is_complete_{{ w }}d then 1 else 0 end)    as complete_{{ w }}d
        {%- if not loop.last %},{% endif %}
        {%- endfor %}
    from joined
    -- (BigQuery rejects GROUP BY on a literal, so 'all' adds nothing to the grouping.)
    group by segment_id, segment_label, segment_source,
             {% if b != 'all' %}bd_{{ b }}, {% endif %}anchor_date
    {% if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}

)

{%- set rate_kpis = ['gave', 'retained'] %}
{% for w in windows %}
{%- for k in rate_kpis %}
select
    segment_id, segment_label, segment_source, breakdown, breakdown_value,
    '{{ k }}'                                                       as kpi_id,
    'rate'                                                          as metric_type,
    {{ w }}                                                         as outcome_window_days,
    anchor_date,
    n,
    {{ k }}_{{ w }}d_rate                                           as value,
    {{ k }}_{{ w }}d_rate * (1 - {{ k }}_{{ w }}d_rate)             as variance,
    cast(null as {{ float_type }})                                  as value_uncapped,
    {{ k }}_{{ w }}d_revenue_gap                                    as revenue_gap_per_success,
    cast({{ dbt.dateadd('day', w, 'anchor_date') }} as date)        as window_end,
    (complete_{{ w }}d = 1)                                         as is_window_complete
from aggregated

union all
{% endfor %}
select
    segment_id, segment_label, segment_source, breakdown, breakdown_value,
    'revenue_per_donor'                                             as kpi_id,
    'mean'                                                          as metric_type,
    {{ w }}                                                         as outcome_window_days,
    anchor_date,
    n,
    revenue_{{ w }}d_mean                                           as value,
    coalesce(revenue_{{ w }}d_var, 0)                               as variance,
    revenue_uncapped_{{ w }}d_mean                                  as value_uncapped,
    cast(null as {{ float_type }})                                  as revenue_gap_per_success,
    cast({{ dbt.dateadd('day', w, 'anchor_date') }} as date)        as window_end,
    (complete_{{ w }}d = 1)                                         as is_window_complete
from aggregated
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
