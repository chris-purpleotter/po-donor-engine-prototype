{#
  pocore_mtr__segment_baselines — how each segment has historically performed (SPEC §3.1).
  INTERNAL metrics layer: the full long table that the srv models read from. Not exposed —
  it mixes whole-segment and slice rows, so naive aggregation double-counts.
  One row per segment_id x kpi_id x outcome_window_days x anchor_date.

  For every segment at every anchor date: who was in it and what they did afterwards,
  aggregated. Reads FOUNDATION (pocore_foundation__person__segment__month and
  pocore_foundation__person__month), so every number traces back to rows an analyst can query.
    kpi 'gave'              metric_type 'rate'  value = share who gave,  variance = p(1-p)
    kpi 'retained'          metric_type 'rate'  value = share still an active sustainer at window end
    kpi 'revenue_per_donor' metric_type 'mean'  value = capped mean,     variance = sample variance

  revenue_gap_per_success (rate KPIs only): capped revenue per donor among those who
  succeeded minus among those who didn't, over the same window. What one extra success has
  been worth, observationally; used for the srv opportunity estimate. Null for mean KPIs.

  Splits and sets are just more segments (see pocore_seg__membership): the descriptive
  columns parent_segment_id / split_by / split_value / segment_set_id are carried through.

  Rows whose window hasn't fully elapsed are kept but flagged (is_window_complete = false);
  they are partial and must never be pooled or reported as final.
#}

{%- set windows = pocore_kpi_windows() -%}
{%- set retained_windows = pocore_kpi_windows('retained') -%}
{%- set desc_cols = ['segment_label', 'segment_source', 'parent_segment_id', 'split_by', 'split_value', 'segment_set_id'] -%}
{%- set float_type = dbt.type_float() -%}

with joined as (

    -- Built from FOUNDATION: who was in each segment at each month-end, joined to what they
    -- did afterwards (outcomes).
    select
        m.segment_id,
        {%- for c in desc_cols %}
        m.{{ c }},
        {%- endfor %}
        p.person_id,
        p.month_end_date as anchor_date,
        {%- for w in windows %}
        p.gave_{{ w }}d,
        p.revenue_{{ w }}d,
        p.revenue_uncapped_{{ w }}d,
        {%- if w in retained_windows %}
        p.retained_{{ w }}d,
        {%- endif %}
        p.is_complete_{{ w }}d{{ ',' if not loop.last }}
        {%- endfor %}
    from {{ ref('pocore_foundation__person__segment__month') }} as m
    inner join {{ ref('pocore_foundation__person__month') }} as p
        on  p.person_id      = m.person_id
        and p.month_end_date = m.month_end_date

),

aggregated as (

    select
        segment_id,
        {%- for c in desc_cols %}
        {{ c }},
        {%- endfor %}
        anchor_date,
        count(*) as n,
        {%- for w in windows %}
        {%- for k in ['gave', 'retained'] if k == 'gave' or w in retained_windows %}
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
    group by segment_id, {{ desc_cols | join(', ') }}, anchor_date

)

{%- set rate_kpis = ['gave', 'retained'] %}
{% for w in windows %}
{%- for k in rate_kpis if k == 'gave' or w in retained_windows %}
select
    segment_id, {{ desc_cols | join(', ') }},
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
    segment_id, {{ desc_cols | join(', ') }},
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
