-- Hand-calculated cohorts (calendar years; as_of = 2026-09-30). Zero rows = pass.
-- 2023 cohort = {D01, D02} (size 2): 2023 total 2 (both New); 2024 total 1 (D01 Second year);
--   2025 total 0; 2026 total 0.
-- 2024 cohort = {D03} (size 1): 2024 New; 2025 Second year; 2026 none.

with expected as (
    select 2023 as cohort_year, 2023 as giving_year, 2 as cohort_size, 2 as total_donors, 2 as new_donors, 0 as second_year_donors union all
    select 2023, 2024, 2, 1, 0, 1 union all
    select 2023, 2025, 2, 0, 0, 0 union all
    select 2023, 2026, 2, 0, 0, 0 union all
    select 2024, 2024, 1, 1, 1, 0 union all
    select 2024, 2025, 1, 1, 0, 1 union all
    select 2024, 2026, 1, 0, 0, 0
)

select e.*, a.total_donors as a_total, a.new_donors as a_new, a.second_year_donors as a_second, a.cohort_size as a_size
from expected as e
left join {{ ref('pode_srv__donor_cohorts') }} as a
    on a.cohort_year = e.cohort_year and a.giving_year = e.giving_year
where a.cohort_year is null
   or a.cohort_size        != e.cohort_size
   or a.total_donors       != e.total_donors
   or a.new_donors         != e.new_donors
   or a.second_year_donors != e.second_year_donors
