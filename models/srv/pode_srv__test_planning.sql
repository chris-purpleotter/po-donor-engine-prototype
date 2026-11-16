{#
  pode_srv__test_planning — ONE ROW PER SEGMENT x WINDOW x HOLDOUT OPTION (whole segments).
  "If we tested something on this segment now, measured over this window, holding out
  this share: what could we detect, and when would we know?" Each row is one option to
  compare; nothing here should be added up.
  Each segment is measured on its primary KPI ('gave', or 'retained' for sustainers).
#}

{%- set lookback = var('baseline_lookback_months')[0] -%}

with primary_kpis as (
    {% for s in pode_all_segments() %}
    select '{{ s.id }}' as segment_id, '{{ s.primary_kpi }}' as primary_kpi
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    p.segment_id,
    p.segment_label,
    p.segment_source,
    p.latest_anchor_date                          as snapshot_date,
    p.kpi_id                                      as primary_kpi,
    p.outcome_window_days,
    p.holdout_pct,
    p.n_eligible                                  as donors_at_snapshot,
    round(p.n_holdout)                            as donors_held_out,
    round(p.n_treatment)                          as donors_treated,
    p.baseline_recent                             as rate_recent,
    p.baseline_value                              as rate_typical,
    p.baseline_same_season                        as rate_same_season,
    p.planning_basis,
    p.is_unstable,
    p.mde_abs_planning                            as detectable_lift,
    p.mde_relative_planning                       as detectable_lift_relative,
    p.is_testable,
    p.readout_date_if_launched_now                as readable_by
from {{ ref('pode_mtr__segment_power') }} as p
inner join primary_kpis as k
    on  k.segment_id  = p.segment_id
    and k.primary_kpi = p.kpi_id
where p.breakdown = 'all'
  and p.baseline_lookback_months = {{ lookback }}
