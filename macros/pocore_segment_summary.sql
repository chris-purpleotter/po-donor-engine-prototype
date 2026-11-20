{#
  The SQL behind pocore__segment: one row per segment (configured, split and set segments
  alike), so every population gets the same headline numbers.

  Headline numbers per segment, today:
    - each segment's PRIMARY window and PRIMARY KPI (pocore_standard_segments / custom
      primary_window_days, primary_kpi): 'gave' for most, 'retained' for sustainers.
      Split and set segments use their parent segment's; a set's remainder uses the defaults.
    - first baseline lookback, the summary_holdout_pct holdout

  Value (observational, approximate: sizing figures, not forecasts):
    revenue_per_extra_donor   what one extra success has been worth over the window
                              (revenue among donors who succeeded minus among those who didn't)
    value_per_point           people x 1 percentage point x revenue_per_extra_donor: what each
                              +1 point on the KPI is worth. The headline: grows with segment
                              size and doesn't depend on test design.
    value_of_detectable_lift  the same for the smallest provable lift (detectable_lift). Shrinks
                              as tests get more sensitive, so it's a floor for test planning,
                              NOT a ranking of where the money is.
#}

{% macro pocore_segment_summary() %}

{%- set lookback = var('baseline_lookback_months')[0] -%}
{%- set holdout = var('summary_holdout_pct') -%}
{%- set windows = pocore_kpi_windows() -%}
{%- set segments = pocore_all_segments() -%}

{%- if holdout not in var('holdout_grid') -%}
    {{ exceptions.raise_compiler_error("po_core: summary_holdout_pct " ~ holdout ~ " must be one of holdout_grid " ~ var('holdout_grid')) }}
{%- endif -%}
{%- for s in segments -%}
    {%- set allowed = pocore_kpi_windows('retained') if s.primary_kpi == 'retained' else windows -%}
    {%- if s.primary_window_days not in allowed -%}
        {{ exceptions.raise_compiler_error("po_core: segment " ~ s.id ~ " primary_window_days " ~ s.primary_window_days ~ " must be one of " ~ allowed ~ " for KPI " ~ s.primary_kpi) }}
    {%- endif -%}
{%- endfor -%}

with primary_choices as (
    {{ pocore_primary_choices_sql() }}
),

power as (

    select *
    from {{ ref('pocore_mtr__segment_power') }}
    where baseline_lookback_months = {{ lookback }}
      and holdout_pct = {{ holdout }}

),

headline as (
    select p.*
    from power as p
    inner join primary_choices as pc
        on  pc.segment_id          = coalesce(p.parent_segment_id, '__remainder__')
        and pc.primary_window_days = p.outcome_window_days
        and pc.primary_kpi         = p.kpi_id
),

revenue as (
    select segment_id, outcome_window_days, baseline_recent as revenue_recent
    from power
    where kpi_id = 'revenue_per_donor'
)

select
    h.segment_id,
    h.segment_label,
    h.segment_source,
    h.parent_segment_id,
    h.split_by,
    h.split_value,
    h.segment_set_id,
    h.latest_anchor_date                                as month_end_date,
    h.n_eligible                                        as people_in_segment,
    h.kpi_id                                            as primary_kpi,
    h.outcome_window_days,
    h.baseline_recent                                   as rate_recent,
    h.baseline_value                                    as rate_typical,
    h.baseline_same_season                              as rate_same_season,
    h.planning_basis,
    h.is_unstable,
    r.revenue_recent                                    as revenue_per_person_recent,
    {{ holdout }}                                       as holdout_pct,
    h.mde_abs_planning                                  as detectable_lift,
    h.mde_relative_planning                             as detectable_lift_relative,
    h.is_testable,
    h.readout_date_if_launched_now                      as readable_by,
    h.revenue_gap_recent                                as revenue_per_extra_donor,
    h.n_eligible * 0.01 * h.revenue_gap_recent          as value_per_point,
    h.n_eligible * h.mde_abs_planning                   as extra_donors_at_detectable_lift,
    h.n_eligible * h.mde_abs_planning * h.revenue_gap_recent as value_of_detectable_lift
from headline as h
left join revenue as r
    on  r.segment_id          = h.segment_id
    and r.outcome_window_days = h.outcome_window_days

{% endmacro %}
