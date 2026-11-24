{#
  The SQL behind pocore__group: one row per group (configured, split and set groups
  alike), so every population gets the same headline numbers.

  Headline numbers per group, today:
    - each group's PRIMARY window and PRIMARY KPI (pocore_engine_config__standard_groups / custom
      primary_window_days, primary_kpi): 'gave' for most, 'retained' for sustainers.
      Split and set groups use their parent group's; a set's remainder uses the defaults.
    - first baseline lookback, the summary_holdout_pct holdout

  Value (observational, approximate: sizing figures, not forecasts):
    revenue_per_extra_donor   what one extra success has been worth over the window
                              (revenue among donors who succeeded minus among those who didn't)
    value_per_point           people x 1 percentage point x revenue_per_extra_donor: what each
                              +1 point on the KPI is worth. The headline: grows with group
                              size and doesn't depend on test design.
    value_of_detectable_lift  the same for the smallest provable lift (detectable_lift). Shrinks
                              as tests get more sensitive, so it's a floor for test planning,
                              NOT a ranking of where the money is.
#}

{% macro pocore_sql__group_summary() %}

{%- set lookback = pocore_client_config__module('group').baseline_lookback_months[0] -%}
{%- set holdout = pocore_client_config__module('group').summary_holdout_pct -%}
{%- set windows = pocore_engine_config__kpi_windows() -%}
{%- set groups = pocore_client_config__all_groups() -%}

{%- if holdout not in pocore_client_config__module('group').holdout_grid -%}
    {{ exceptions.raise_compiler_error("po_core: summary_holdout_pct " ~ holdout ~ " must be one of holdout_grid " ~ pocore_client_config__module('group').holdout_grid) }}
{%- endif -%}
{%- for s in groups -%}
    {%- set allowed = pocore_engine_config__kpi_windows('retained') if s.primary_kpi == 'retained' else windows -%}
    {%- if s.primary_window_days not in allowed -%}
        {{ exceptions.raise_compiler_error("po_core: group " ~ s.id ~ " primary_window_days " ~ s.primary_window_days ~ " must be one of " ~ allowed ~ " for KPI " ~ s.primary_kpi) }}
    {%- endif -%}
{%- endfor -%}

with primary_choices as (
    {{ pocore_sql__primary_choices() }}
),

power as (

    select *
    from {{ ref('pocore_group__power') }}
    where baseline_lookback_months = {{ lookback }}
      and holdout_pct = {{ holdout }}

),

headline as (
    select power.*
    from power
    inner join primary_choices
        on  primary_choices.group_id          = coalesce(power.parent_group_id, '__remainder__')
        and primary_choices.primary_window_days = power.outcome_window_days
        and primary_choices.primary_kpi         = power.kpi_id
),

revenue as (
    select group_id, outcome_window_days, baseline_recent as revenue_recent
    from power
    where kpi_id = 'revenue_per_donor'
)

select
    headline.group_id,
    headline.group_label,
    headline.group_source,
    headline.parent_group_id,
    headline.split_by,
    headline.split_value,
    headline.group_set_id,
    headline.latest_anchor_date                                as month_end_date,
    headline.n_eligible                                        as people_in_group,
    headline.kpi_id                                            as primary_kpi,
    headline.outcome_window_days,
    headline.baseline_recent                                   as rate_recent,
    headline.baseline_value                                    as rate_typical,
    headline.baseline_same_season                              as rate_same_season,
    headline.planning_basis,
    headline.is_unstable,
    revenue.revenue_recent                                    as revenue_per_person_recent,
    {{ holdout }}                                       as holdout_pct,
    headline.mde_abs_planning                                  as detectable_lift,
    headline.mde_relative_planning                             as detectable_lift_relative,
    headline.is_testable,
    headline.readout_date_if_launched_now                      as readable_by,
    headline.revenue_gap_recent                                as revenue_per_extra_donor,
    headline.n_eligible * 0.01 * headline.revenue_gap_recent          as value_per_point,
    headline.n_eligible * headline.mde_abs_planning                   as extra_donors_at_detectable_lift,
    headline.n_eligible * headline.mde_abs_planning * headline.revenue_gap_recent as value_of_detectable_lift
from headline
left join revenue
    on  revenue.group_id          = headline.group_id
    and revenue.outcome_window_days = headline.outcome_window_days

{% endmacro %}
