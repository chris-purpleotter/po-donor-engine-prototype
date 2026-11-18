-- Certified: our opinion, reshaped for business users (schema: pocore)
-- Everything here is built from the foundation tables you've just walked through.

-- query: pocore__segment (one row per segment, today)
select segment_id, people_in_segment, primary_kpi, outcome_window_days,
       rate_recent, rate_same_season, detectable_lift, is_testable, value_per_point
from main_pocore.pocore__segment
order by segment_id;

-- query: pocore__person__year for D04 and D05 (the journey: stage now vs a year ago)
select person_id, fiscal_year, gave, amount_given, movement_status, stage_date, stage, stage_1y_ago
from main_pocore.pocore__person__year
where person_id in ('D04', 'D05')
order by person_id, fiscal_year;

-- query: a Sankey's data: last year's stage -> this year's, for the current fiscal year
select stage_1y_ago, stage, count(*) as people
from main_pocore.pocore__person__year
where fiscal_year = 2026
group by stage_1y_ago, stage
order by people desc;

-- query: pocore__year (the movement funnel) - matches counts of movement_status above
select fiscal_year, total_donors, new_donors, second_year_donors, lost_donors, revenue, overall_retention, is_partial_year
from main_pocore.pocore__year
order by fiscal_year;
