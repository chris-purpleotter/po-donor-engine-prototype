-- Split and set segments (as_of = 2026-09-30). Zero rows = pass.
-- Population at 2026-09-30 (individuals, not deceased, existing): D01-D07, D10 = 8 people.
--   std_lapsed_v1 = D01, D04, D06, D10.  cust_lapsed_100_v1 = D01 (125), D10 (250).
-- Set set_lapsed_value_v1 [cust_lapsed_100_v1, std_lapsed_v1] + remainder, first match wins:
--   __cust_lapsed_100_v1 = D01, D10 (2); __std_lapsed_v1 = D04, D06 (2);
--   __remainder = D02, D03, D05, D07 (4). Total 8 = the population: no overlap, nobody missing.
-- Split cust_givers_v1 by acquisition_channel: the split rows add up to the parent.
-- Set and split rows inherit their parent's KPI and window; the remainder gets the defaults.

with latest as (
    select person_id, segment_id
    from {{ ref('pocore__person__segment') }}
),

expected_set as (
    select 'set_lapsed_value_v1__cust_lapsed_100_v1' as segment_id, 2 as people union all
    select 'set_lapsed_value_v1__std_lapsed_v1', 2 union all
    select 'set_lapsed_value_v1__remainder', 4
),

set_counts as (
    select e.segment_id, 'set count' as problem
    from expected_set as e
    left join (select segment_id, count(*) as n from latest group by segment_id) as a
        on a.segment_id = e.segment_id
    where a.n is distinct from e.people
),

set_overlap as (
    select person_id as segment_id, 'person in two set segments' as problem
    from latest
    where segment_id like 'set_lapsed_value_v1__%'
    group by person_id
    having count(*) > 1
),

split_sums as (
    select 'cust_givers_v1' as segment_id, 'splits do not add up to parent' as problem
    from (select count(*) as n from latest where segment_id = 'cust_givers_v1') as parent
    cross join (select count(*) as n, count(distinct segment_id) as k from latest
                where segment_id like 'cust_givers_v1__%') as splits
    where parent.n is distinct from splits.n or splits.k < 2
),

summary_rows as (
    select s.segment_id, 'summary columns' as problem
    from {{ ref('pocore__segment') }} as s
    where (s.segment_id = 'set_lapsed_value_v1__std_lapsed_v1'
            and (s.segment_set_id is distinct from 'set_lapsed_value_v1'
                 or s.parent_segment_id is distinct from 'std_lapsed_v1'
                 or s.outcome_window_days is distinct from 180))
       or (s.segment_id = 'set_lapsed_value_v1__remainder'
            and (s.parent_segment_id is not null or s.primary_kpi is distinct from 'gave'))
       or (s.segment_id like 'cust_givers_v1__%'
            and (s.split_by is distinct from 'acquisition_channel' or s.parent_segment_id is distinct from 'cust_givers_v1'))
),

-- Certified too: every split value must appear in pocore__segment (a new value with no complete
-- history yet used to vanish), so the split rows add up to the parent there as well.
certified_split_sums as (
    select 'cust_givers_v1' as segment_id, 'certified splits do not add up to parent' as problem
    from (select people_in_segment as n from {{ ref('pocore__segment') }} where segment_id = 'cust_givers_v1') as parent
    cross join (select sum(people_in_segment) as n from {{ ref('pocore__segment') }}
                where parent_segment_id = 'cust_givers_v1' and split_by is not null) as splits
    where parent.n is distinct from splits.n
),

-- standard_splits: std_lapsed_v1 by region at 2026-09-30: D01, D04, D06, D10 are all ON -> one
-- split segment std_lapsed_v1__on with all 4, labelled "Lapsed donors (13-24 months) — ON".
standard_split as (
    select 'std_lapsed_v1__on' as segment_id, 'standard split' as problem
    from (select count(*) as n from latest where segment_id = 'std_lapsed_v1__on') as a
    where a.n <> 4
    union all
    select s.segment_id, 'standard split columns'
    from {{ ref('pocore__segment') }} as s
    where s.segment_id = 'std_lapsed_v1__on'
      and (s.parent_segment_id is distinct from 'std_lapsed_v1' or s.split_by is distinct from 'region'
           or s.segment_label is distinct from 'Lapsed donors (13-24 months) — ON' or s.outcome_window_days is distinct from 180)
),

summary_present as (
    select e.segment_id, 'missing from pocore__segment' as problem
    from expected_set as e
    left join {{ ref('pocore__segment') }} as s on s.segment_id = e.segment_id
    where s.segment_id is null
)

select * from set_counts
union all select * from set_overlap
union all select * from split_sums
union all select * from summary_rows
union all select * from summary_present
union all select * from certified_split_sums
union all select * from standard_split
