{#
  pocore__segment__test_option — ONE ROW PER SEGMENT x TEST OPTION (outcome window x holdout %),
  whole segments.
  "If we tested something on this segment now, measured over this window, holding out
  this share: what could we detect, and when would we know?" Each row is one option to
  compare; nothing here should be added up.
  Each segment is measured on its primary KPI (one of pocore_engine_config__measures(); 'gave' unless set).
#}

{%- set lookback = var('baseline_lookback_months')[0] -%}

with primary_kpis as (
    {% for s in pocore_client_config__all_segments() %}
    select '{{ s.id }}' as segment_id, '{{ s.primary_kpi }}' as primary_kpi
    union all
    {% endfor %}
    -- a set's remainder has no parent segment: the default KPI
    select '__remainder__', 'gave'
)

select
    p.segment_id,
    p.segment_label,
    p.segment_source,
    p.parent_segment_id,
    p.split_by,
    p.split_value,
    p.segment_set_id,
    p.latest_anchor_date                          as month_end_date,
    p.kpi_id                                      as primary_kpi,
    p.outcome_window_days,
    p.holdout_pct,
    p.n_eligible                                  as people_in_segment,
    round(p.n_holdout)                            as people_held_out,
    round(p.n_treatment)                          as people_treated,
    p.baseline_recent                             as rate_recent,
    p.baseline_value                              as rate_typical,
    p.baseline_same_season                        as rate_same_season,
    p.planning_basis,
    p.is_unstable,
    p.mde_abs_planning                            as detectable_lift,
    p.mde_relative_planning                       as detectable_lift_relative,
    p.is_testable,
    p.readout_date_if_launched_now                as readable_by
from {{ ref('pocore_group__power') }} as p
inner join primary_kpis as k
    on  k.segment_id  = coalesce(p.parent_segment_id, '__remainder__')
    and k.primary_kpi = p.kpi_id
where p.baseline_lookback_months = {{ lookback }}
