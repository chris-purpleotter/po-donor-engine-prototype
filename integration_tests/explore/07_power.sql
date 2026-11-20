-- Power: pooled baselines -> "what lift could a test detect?" (layer: mtr)
-- Baselines from complete months are pooled (recent / typical / same season), then the
-- detectable lift is computed for each holdout % in holdout_grid. Tiny test data, so most
-- segments come out "not testable" here: that's the point of the check.

-- query: the lapsed segment's power rows for its primary KPI (gave, 180 days)
select segment_id, kpi_id, outcome_window_days, holdout_pct, n_eligible,
       baseline_recent, baseline_value as baseline_typical, baseline_same_season, planning_basis,
       mde_abs_planning as detectable_lift, is_testable
from main_pocore_internal.pocore_group__power
where segment_id = 'std_lapsed_v1' and kpi_id = 'gave'
  and outcome_window_days = 180 and baseline_lookback_months = 12
order by holdout_pct;
