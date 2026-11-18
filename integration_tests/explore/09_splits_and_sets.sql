-- Splits and sets: more segments from one line of config (v0.3.0)
-- In integration_tests/dbt_project.yml:
--   cust_givers_v1 has `split_by: acquisition_channel` -> one extra segment per channel.
--   set_lapsed_value_v1 lists [cust_lapsed_100_v1, std_lapsed_v1] with include_remainder:
--   each person lands in the FIRST segment they match, so the set's populations don't overlap
--   and add up to everyone (the 8 people in the population at 2026-09-30).
-- Every one of them gets the same numbers as any segment (rates, value per point, test options).
-- A new value with no finished outcome window yet (Face to Face here) still appears: size, empty rates.

-- query: split segments: they add up to their parent
select segment_id, segment_label, parent_segment_id, split_by, split_value, people_in_segment, rate_recent
from main_pocore.pocore__segment
where segment_id like 'cust_givers_v1%'
order by split_value nulls first;

-- query: a set: non-overlapping populations that add up to the whole population
select segment_id, segment_label, parent_segment_id, people_in_segment, primary_kpi, outcome_window_days
from main_pocore.pocore__segment
where segment_set_id = 'set_lapsed_value_v1'
order by segment_id;

-- query: compare: the standalone lapsed segment overlaps "$100+"; inside the set it doesn't
select segment_id, people_in_segment
from main_pocore.pocore__segment
where segment_id in ('std_lapsed_v1', 'cust_lapsed_100_v1', 'set_lapsed_value_v1__std_lapsed_v1', 'set_lapsed_value_v1__cust_lapsed_100_v1')
order by segment_id;
