{#
  pocore_group__power — what an experiment on each segment could detect if launched now
  (SPEC §3.2). INTERNAL statistics: the full grid the certified tables read from.
  One row per segment_id x kpi_id x outcome_window_days x baseline_lookback_months x holdout_pct.
  Split and set segments are ordinary segments here, so "is this split big enough to test on
  its own?" is answered too.

    n_eligible         size at the latest anchor (the as_of month-end)
    baseline_value     pooled over the most recent N COMPLETE anchors: sum(value*n) / sum(n)
    baseline_recent    pooled over only the last few complete anchors: today's normal
    baseline_variance  pooled from each anchor's mean and variance (exact for rates: p(1-p))
    mde_abs            smallest absolute lift detectable with this holdout:
                       (z_{1-alpha/2} + z_{power}) * sqrt(variance * (1/n_treatment + 1/n_holdout))
    mde_abs_recent     the same, using today's normal (use this when is_unstable)
    baseline_same_season  pooled over the complete anchors 11-13 months before as_of: the
                       same season last year. A test launched now runs through the same months,
                       so this is the best guess at the control group's rate (year-end giving
                       makes "recent" misleading every autumn).
    baseline_planning  same-season if available, else recent (planning_basis says which).
                       mde_abs_planning / is_testable / the srv planning numbers use it.
    revenue_gap_recent rate KPIs: revenue_gap_per_success pooled over the recent anchors
                       (what one extra success has been worth); null for mean KPIs
    is_testable        detectable lift (vs the planning baseline) is no bigger than
                       max_plausible_relative_lift; otherwise a test will almost certainly
                       come back inconclusive
#}

{%- set alpha = var('alpha') | float -%}
{%- set power = var('power') | float -%}
{%- set z_total = pocore_helpers__z(1 - alpha / 2) + pocore_helpers__z(power) -%}
{%- set holdouts = var('holdout_grid') -%}
{%- set lookbacks = var('baseline_lookback_months') -%}
{%- set recent_anchors = var('baseline_recent_anchors') | int -%}
{%- set instability_threshold = var('baseline_instability_threshold') | float -%}
{%- set max_lift = var('max_plausible_relative_lift') | float -%}
{%- set float_type = dbt.type_float() -%}
{#- The keys that identify one baseline series (a segment, or a slice of one). -#}
{%- set keys = ['segment_id', 'kpi_id', 'outcome_window_days'] -%}
{%- set desc_cols = ['segment_label', 'segment_source', 'parent_segment_id', 'split_by', 'split_value', 'segment_set_id'] -%}

with

pocore_group__baselines__month as (select * from {{ ref('pocore_group__baselines__month') }}),

baselines as (

    select * from pocore_group__baselines__month

),

-- Size today = n at the LATEST month-end (as_of's), for every series; 0 when the segment
-- (or slice) has nobody now. Using each series' own latest anchor instead would show a
-- stale size for a segment that has since emptied. Window completeness doesn't matter for size.
latest as (
    select max(anchor_date) as latest_anchor_date from baselines
),

series as (
    select
        {{ keys | join(', ') }},
        {%- for c in desc_cols %}
        max({{ c }})        as {{ c }},
        {%- endfor %}
        max(metric_type)    as metric_type
    from baselines
    group by {{ keys | join(', ') }}
),

eligible as (

    select
        series.*,
        latest.latest_anchor_date,
        coalesce(baselines.n, 0)    as n_eligible
    from series
    cross join latest
    left join baselines
        on {% for k in keys %}baselines.{{ k }} = series.{{ k }} and {% endfor %}baselines.anchor_date = latest.latest_anchor_date

),

-- Most recent complete anchors first.
ranked as (

    select
        baselines.*,
        row_number() over (partition by {{ keys | join(', ') }} order by anchor_date desc) as recency_rank
    from baselines
    where baselines.is_window_complete

),

pooled as (
    {% for lb in lookbacks %}
    select
        {{ keys | join(', ') }},
        {{ lb }}                                                    as baseline_lookback_months,
        count(*)                                                    as anchors_used,
        min(value)                                                  as baseline_min,
        max(value)                                                  as baseline_max,
        sum(value * n) / sum(n)                                     as baseline_value,
        -- pooled second moment minus pooled mean squared
        sum(n * (variance + value * value)) / sum(n)
            - (sum(value * n) / sum(n)) * (sum(value * n) / sum(n)) as baseline_variance
    from ranked
    where recency_rank <= {{ lb }}
    group by {{ keys | join(', ') }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

-- Same season last year: complete anchors whose month is 11-13 months before as_of's month.
seasonal as (

    select
        {{ keys | join(', ') }},
        sum(value * n) / sum(n)                                     as baseline_same_season,
        sum(n * (variance + value * value)) / sum(n)
            - (sum(value * n) / sum(n)) * (sum(value * n) / sum(n)) as baseline_same_season_variance
    from ranked
    where cast({{ dbt.date_trunc('month', 'anchor_date') }} as date)
          between cast({{ dbt.dateadd('month', -13, dbt.date_trunc('month', pocore_client_config__as_of_date())) }} as date)
              and cast({{ dbt.dateadd('month', -11, dbt.date_trunc('month', pocore_client_config__as_of_date())) }} as date)
    group by {{ keys | join(', ') }}

),

-- "Today's normal": pooled over only the most recent few complete anchors.
recent as (

    select
        {{ keys | join(', ') }},
        sum(value * n) / sum(n)                                     as baseline_recent,
        sum(n * (variance + value * value)) / sum(n)
            - (sum(value * n) / sum(n)) * (sum(value * n) / sum(n)) as baseline_recent_variance,
        sum(revenue_gap_per_success * n)
            / nullif(sum(case when revenue_gap_per_success is not null then n end), 0) as revenue_gap_recent
    from ranked
    where recency_rank <= {{ recent_anchors }}
    group by {{ keys | join(', ') }}

),

-- Every lookback for every series, so a segment with NO complete history yet (a new custom
-- segment, a new split value) still gets rows: its size, with empty rates, instead of vanishing.
lookback_list as (
    {% for lb in lookbacks %}
    select {{ lb }} as baseline_lookback_months {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

holdouts as (
    {% for h in holdouts %}
    select {{ h }} as holdout_pct {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

sized as (

    select
        eligible.segment_id, {% for c in desc_cols %}eligible.{{ c }}, {% endfor %}
        eligible.kpi_id, eligible.metric_type, eligible.outcome_window_days,
        lookback_list.baseline_lookback_months,
        holdouts.holdout_pct,
        eligible.latest_anchor_date,
        eligible.n_eligible,
        coalesce(pooled.anchors_used, 0)                                         as anchors_used,
        (coalesce(pooled.anchors_used, 0) < lookback_list.baseline_lookback_months)         as is_short_history,
        pooled.baseline_value,
        recent.baseline_recent,
        recent.revenue_gap_recent,
        seasonal.baseline_same_season,
        coalesce(seasonal.baseline_same_season, recent.baseline_recent)               as baseline_planning,
        case when seasonal.baseline_same_season is not null then 'same_season'
             when recent.baseline_recent is not null then 'recent' end          as planning_basis,
        pooled.baseline_min,
        pooled.baseline_max,
        -- Unstable = today's normal differs a lot from the pooled history, or the
        -- history swings widely. Plan against baseline_recent when this is true.
        coalesce(
            (pooled.baseline_value > 0
                and abs(recent.baseline_recent - pooled.baseline_value) / pooled.baseline_value > {{ instability_threshold }})
            or (pooled.baseline_min > 0 and pooled.baseline_max / pooled.baseline_min > 2),
            false)                                                          as is_unstable,
        case when pooled.baseline_variance < 0 then 0 else pooled.baseline_variance end as baseline_variance,
        case when recent.baseline_recent_variance < 0 then 0 else recent.baseline_recent_variance end as baseline_recent_variance,
        {{ pocore_helpers__clamp("coalesce(case when seasonal.baseline_same_season is not null
                               then seasonal.baseline_same_season_variance end,
                          recent.baseline_recent_variance)", low=0) }}           as baseline_planning_variance,
        cast(eligible.n_eligible as {{ float_type }}) * holdouts.holdout_pct / 100        as n_holdout,
        cast(eligible.n_eligible as {{ float_type }}) * (100 - holdouts.holdout_pct) / 100 as n_treatment
    from eligible
    cross join lookback_list
    left join pooled
        on {% for k in keys %}pooled.{{ k }} = eligible.{{ k }} and {% endfor %}pooled.baseline_lookback_months = lookback_list.baseline_lookback_months
    left join recent
        on {% for k in keys %}recent.{{ k }} = eligible.{{ k }}{% if not loop.last %} and {% endif %}{% endfor %}
    left join seasonal
        on {% for k in keys %}seasonal.{{ k }} = eligible.{{ k }}{% if not loop.last %} and {% endif %}{% endfor %}
    cross join holdouts

),

with_mde as (

    select
        sized.*,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_variance * (1 / n_treatment + 1 / n_holdout)) end        as mde_abs,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_recent_variance * (1 / n_treatment + 1 / n_holdout)) end as mde_abs_recent,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_planning_variance * (1 / n_treatment + 1 / n_holdout)) end as mde_abs_planning
    from sized

)

select
    segment_id, {{ desc_cols | join(', ') }},
    kpi_id, metric_type, outcome_window_days,
    baseline_lookback_months, holdout_pct,
    latest_anchor_date, n_eligible, n_treatment, n_holdout,
    anchors_used, is_short_history,
    baseline_value, baseline_recent, baseline_same_season, baseline_planning, planning_basis,
    baseline_min, baseline_max, is_unstable,
    baseline_variance,
    revenue_gap_recent,
    {{ alpha }}                                                             as alpha,
    {{ power }}                                                             as power,
    mde_abs,
    case when baseline_value > 0 then mde_abs / baseline_value end          as mde_relative,
    mde_abs_recent,
    case when baseline_recent > 0 then mde_abs_recent / baseline_recent end as mde_relative_recent,
    mde_abs_planning,
    case when baseline_planning > 0 then mde_abs_planning / baseline_planning end as mde_relative_planning,
    coalesce(
        baseline_planning > 0 and mde_abs_planning / baseline_planning <= {{ max_lift }},
        false)                                                              as is_testable,
    cast({{ dbt.dateadd('day', 'outcome_window_days', pocore_client_config__as_of_date()) }} as date)        as readout_date_if_launched_now
from with_mde
