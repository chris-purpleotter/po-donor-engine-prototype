-- Segments: rules over the backward-looking columns (layer: seg -> foundation)
-- A segment is just a filter on the snapshot, evaluated at every month-end
-- (standard rules in macros/pocore_standard_segments.sql; custom ones in the client's vars).
-- People can be in several segments at once (e.g. a custom segment overlapping a standard one).

-- query: which segments D04 and D05 were in, month by month (recent months)
select person_id, month_end_date, segment_id
from main_pocore_foundation.pocore_foundation__person__segment__month
where person_id in ('D04', 'D05') and month_end_date >= '2026-03-31'
order by person_id, month_end_date, segment_id;

-- query: the custom segments in this test project (from integration_tests/dbt_project.yml)
select distinct segment_id, segment_label, segment_source
from main_pocore_foundation.pocore_foundation__person__segment__month
order by segment_source desc, segment_id;
