-- Baselines: group membership x forward outcomes, aggregated (layer: mtr)
-- For every group at every month-end: how many people were in it (n) and what share of them
-- succeeded afterwards (value). It's literally steps 04 + 05 joined and averaged.
-- Example: prospects at 2026-06-30 were D05 and D07; D05 gave within 90 days, D07 didn't -> 0.5.

-- query: the prospect group's 90-day "gave" rate, month by month
select group_id, anchor_date, n, value as gave_rate_90d, is_window_complete
from main_pocore_internal.pocore_group__baselines__month
where group_id = 'std_prospect_v1' and kpi_id = 'gave' and outcome_window_days = 90
order by anchor_date desc
limit 8;

-- query: the same number rebuilt by hand from foundation (this is how anyone can check us)
select m.month_end_date, count(*) as n, avg(p.gave_90d) as gave_rate_90d, bool_and(p.is_complete_90d) as complete
from main_pocore_foundation.pocore_group__membership__month as m
join main_pocore_foundation.pocore_foundation__person__month_end as p
  on p.person_id = m.person_id and p.month_end_date = m.month_end_date
where m.group_id = 'std_prospect_v1'
group by m.month_end_date
order by m.month_end_date desc
limit 8;
