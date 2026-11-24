{#
  pocore__group__test_option — ONE ROW PER GROUP x TEST OPTION (outcome window x holdout %),
  whole groups.
  "If we tested something on this group now, measured over this window, holding out
  this share: what could we detect, and when would we know?" Each row is one option to
  compare; nothing here should be added up.
  Each group is measured on its primary KPI (one of pocore_engine_config__measures(); 'gave' unless set).
#}

{%- set lookback = pocore_client_config__module('group').baseline_lookback_months[0] -%}

with

pocore_group__power as (select * from {{ ref('pocore_group__power') }}),

primary_kpis as (
    {% for s in pocore_client_config__all_groups() %}
    select '{{ s.id }}' as group_id, '{{ s.primary_kpi }}' as primary_kpi
    union all
    {% endfor %}
    -- a set's remainder has no parent group: the default KPI
    select '__remainder__', 'gave'
)

select
    pocore_group__power.group_id,
    pocore_group__power.group_label,
    pocore_group__power.group_source,
    pocore_group__power.parent_group_id,
    pocore_group__power.split_by,
    pocore_group__power.split_value,
    pocore_group__power.group_set_id,
    pocore_group__power.latest_anchor_date                          as month_end_date,
    pocore_group__power.kpi_id                                      as primary_kpi,
    pocore_group__power.outcome_window_days,
    pocore_group__power.holdout_pct,
    pocore_group__power.n_eligible                                  as people_in_group,
    round(pocore_group__power.n_holdout)                            as people_held_out,
    round(pocore_group__power.n_treatment)                          as people_treated,
    pocore_group__power.baseline_recent                             as rate_recent,
    pocore_group__power.baseline_value                              as rate_typical,
    pocore_group__power.baseline_same_season                        as rate_same_season,
    pocore_group__power.planning_basis,
    pocore_group__power.is_unstable,
    pocore_group__power.mde_abs_planning                            as detectable_lift,
    pocore_group__power.mde_relative_planning                       as detectable_lift_relative,
    pocore_group__power.is_testable,
    pocore_group__power.readout_date_if_launched_now                as readable_by
from pocore_group__power
inner join primary_kpis
    on  primary_kpis.group_id  = coalesce(pocore_group__power.parent_group_id, '__remainder__')
    and primary_kpis.primary_kpi = pocore_group__power.kpi_id
where pocore_group__power.baseline_lookback_months = {{ lookback }}
