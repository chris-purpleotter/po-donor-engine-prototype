-- Hand-calculated donor movement (calendar years; as_of = 2026-09-30). Zero rows = pass.
--
-- Years each individual gave (eligible, non-refund gifts):
--   D01 2023, 2024 | D02 2023 | D03 2024, 2025 | D04 2025 | D05 2026 | D06 2025 (refunded,
--   but the original gift is real) | D09 2021 (deceased: included) | D10 2025 (2026 capital
--   gift excluded) | D07 none | D08 organization (excluded)
--
-- year  new  second  total  lost  new_retention
-- 2021   1     0       1     0     -
-- 2022   0     0       0     1     0/1 = 0      (D09 lost)
-- 2023   2     0       2     0     -            (D01, D02 new)
-- 2024   1     1       2     1     1/2 = 0.5    (D03 new, D01 second; D02 lost)
-- 2025   3     1       4     1     1/1 = 1.0    (D04, D06, D10 new; D03 second; D01 lost)
-- 2026   1     0       1     4     0/3 = 0      (D05 new; D03, D04, D06, D10 lost) partial year

with expected as (
    select 2021 as fiscal_year, 1 as new_donors, 0 as second_year_donors, 1 as total_donors, 0 as lost_donors, cast(null as double) as new_donor_retention, false as is_partial_year union all
    select 2022, 0, 0, 0, 1, 0.0, false union all
    select 2023, 2, 0, 2, 0, null, false union all
    select 2024, 1, 1, 2, 1, 0.5, false union all
    select 2025, 3, 1, 4, 1, 1.0, false union all
    select 2026, 1, 0, 1, 4, 0.0, true
)

select e.*, a.new_donors as a_new, a.second_year_donors as a_second, a.total_donors as a_total,
       a.lost_donors as a_lost, a.new_donor_retention as a_retention, a.is_partial_year as a_partial
from expected as e
left join {{ ref('pocore__year') }} as a
    on a.fiscal_year = e.fiscal_year
where a.fiscal_year is null
   or a.new_donors         != e.new_donors
   or a.second_year_donors != e.second_year_donors
   or a.total_donors       != e.total_donors
   or a.lost_donors        != e.lost_donors
   or a.is_partial_year    != e.is_partial_year
   or coalesce(abs(a.new_donor_retention - e.new_donor_retention), 0) > 0.0001
   or (a.new_donor_retention is null) != (e.new_donor_retention is null)
