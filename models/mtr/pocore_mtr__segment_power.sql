{#
  pocore_mtr__segment_power — what an experiment on each segment (or slice) could detect
  if launched now (SPEC §3.2). INTERNAL metrics layer: the full grid the srv models read from.
  One row per segment_id x breakdown x breakdown_value x kpi_id x outcome_window_days
  x baseline_lookback_months x holdout_pct.
  breakdown = 'all' is the whole segment; other rows are slices (e.g. face-to-face only),
  so "is this slice big enough to test on its own?" is answered too.

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
{%- set z_total = pocore_z(1 - alpha / 2) + pocore_z(power) -%}
{%- set holdouts = var('holdout_grid') -%}
{%- set lookbacks = var('baseline_lookback_months') -%}
{%- set recent_anchors = var('baseline_recent_anchors') | int -%}
{%- set instability_threshold = var('baseline_instability_threshold') | float -%}
{%- set max_lift = var('max_plausible_relative_lift') | float -%}
{%- set float_type = dbt.type_float() -%}
{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}
{#- The keys that identify one baseline series (a segment, or a slice of one). -#}
{%- set keys = ['segment_id', 'breakdown', 'breakdown_value', 'kpi_id', 'outcome_window_days'] -%}

with baselines as (

    select * from {{ ref('pocore_mtr__segment_baselines') }}

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
        max(segment_label)  as segment_label,
        max(segment_source) as segment_source,
        max(metric_type)    as metric_type
    from baselines
    group by {{ keys | join(', ') }}
),

eligible as (

    select
        s.*,
        l.latest_anchor_date,
        coalesce(b.n, 0)    as n_eligible
    from series as s
    cross join latest as l
    left join baselines as b
        on {% for k in keys %}b.{{ k }} = s.{{ k }} and {% endfor %}b.anchor_date = l.latest_anchor_date

),

-- Most recent complete anchors first.
ranked as (

    select
        b.*,
        row_number() over (partition by {{ keys | join(', ') }} order by anchor_date desc) as recency_rank
    from baselines as b
    where b.is_window_complete

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
          between cast({{ dbt.dateadd('month', -13, dbt.date_trunc('month', as_of_sql)) }} as date)
              and cast({{ dbt.dateadd('month', -11, dbt.date_trunc('month', as_of_sql)) }} as date)
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

holdouts as (
    {% for h in holdouts %}
    select {{ h }} as holdout_pct {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

sized as (

    select
        e.segment_id, e.segment_label, e.segment_source, e.breakdown, e.breakdown_value,
        e.kpi_id, e.metric_type, e.outcome_window_days,
        p.baseline_lookback_months,
        h.holdout_pct,
        e.latest_anchor_date,
        e.n_eligible,
        p.anchors_used,
        (p.anchors_used < p.baseline_lookback_months)                       as is_short_history,
        p.baseline_value,
        r.baseline_recent,
        r.revenue_gap_recent,
        ss.baseline_same_season,
        coalesce(ss.baseline_same_season, r.baseline_recent)               as baseline_planning,
        case when ss.baseline_same_season is not null then 'same_season'
             when r.baseline_recent is not null then 'recent' end          as planning_basis,
        p.baseline_min,
        p.baseline_max,
        -- Unstable = today's normal differs a lot from the pooled history, or the
        -- history swings widely. Plan against baseline_recent when this is true.
        coalesce(
            (p.baseline_value > 0
                and abs(r.baseline_recent - p.baseline_value) / p.baseline_value > {{ instability_threshold }})
            or (p.baseline_min > 0 and p.baseline_max / p.baseline_min > 2),
            false)                                                          as is_unstable,
        case when p.baseline_variance < 0 then 0 else p.baseline_variance end as baseline_variance,
        case when r.baseline_recent_variance < 0 then 0 else r.baseline_recent_variance end as baseline_recent_variance,
        {{ pocore_clamp("coalesce(case when ss.baseline_same_season is not null
                               then ss.baseline_same_season_variance end,
                          r.baseline_recent_variance)", low=0) }}           as baseline_planning_variance,
        cast(e.n_eligible as {{ float_type }}) * h.holdout_pct / 100        as n_holdout,
        cast(e.n_eligible as {{ float_type }}) * (100 - h.holdout_pct) / 100 as n_treatment
    from eligible as e
    inner join pooled as p
        on {% for k in keys %}p.{{ k }} = e.{{ k }}{% if not loop.last %} and {% endif %}{% endfor %}
    left join recent as r
        on {% for k in keys %}r.{{ k }} = e.{{ k }}{% if not loop.last %} and {% endif %}{% endfor %}
    left join seasonal as ss
        on {% for k in keys %}ss.{{ k }} = e.{{ k }}{% if not loop.last %} and {% endif %}{% endfor %}
    cross join holdouts as h

),

with_mde as (

    select
        s.*,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_variance * (1 / n_treatment + 1 / n_holdout)) end        as mde_abs,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_recent_variance * (1 / n_treatment + 1 / n_holdout)) end as mde_abs_recent,
        case when n_holdout >= 1 and n_treatment >= 1
             then {{ z_total }} * sqrt(baseline_planning_variance * (1 / n_treatment + 1 / n_holdout)) end as mde_abs_planning
    from sized as s

)

select
    segment_id, segment_label, segment_source, breakdown, breakdown_value,
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
    cast({{ dbt.dateadd('day', 'outcome_window_days', as_of_sql) }} as date)        as readout_date_if_launched_now
from with_mde
