-- Groups: rules over the backward-looking columns (layer: seg -> foundation)
-- A group is just a filter on the snapshot, evaluated at every month-end
-- (standard rules in macros/engine_config/pocore_engine_config__standard_groups.sql; custom ones in the client's vars).
-- People can be in several groups at once (e.g. a custom group overlapping a standard one).

-- query: which groups D04 and D05 were in, month by month (recent months)
select person_id, month_end_date, group_id
from main_pocore_foundation.pocore_group__membership__month
where person_id in ('D04', 'D05') and month_end_date >= '2026-03-31'
order by person_id, month_end_date, group_id;

-- query: the custom groups in this test project (from integration_tests/dbt_project.yml)
select distinct group_id, group_label, group_source
from main_pocore_foundation.pocore_group__membership__month
order by group_source desc, group_id;
