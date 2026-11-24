-- Split and set groups (as_of = 2026-09-30). Zero rows = pass.
-- Population at 2026-09-30 (individuals, not deceased, existing): D01-D07, D10 = 8 people.
--   std_lapsed_v1 = D01, D04, D06, D10.  cust_lapsed_100_v1 = D01 (125), D10 (250).
-- Set set_lapsed_value_v1 [cust_lapsed_100_v1, std_lapsed_v1] + remainder, first match wins:
--   __cust_lapsed_100_v1 = D01, D10 (2); __std_lapsed_v1 = D04, D06 (2);
--   __remainder = D02, D03, D05, D07 (4). Total 8 = the population: no overlap, nobody missing.
-- Split cust_givers_v1 by acquisition_channel: the split rows add up to the parent.
-- Set and split rows inherit their parent's KPI and window; the remainder gets the defaults.

with latest as (
    select person_id, group_id
    from {{ ref('pocore__person__group') }}
),

expected_set as (
    select 'set_lapsed_value_v1__cust_lapsed_100_v1' as group_id, 2 as people union all
    select 'set_lapsed_value_v1__std_lapsed_v1', 2 union all
    select 'set_lapsed_value_v1__remainder', 4
),

set_counts as (
    select e.group_id, 'set count' as problem
    from expected_set as e
    left join (select group_id, count(*) as n from latest group by group_id) as a
        on a.group_id = e.group_id
    where a.n is distinct from e.people
),

set_overlap as (
    select person_id as group_id, 'person in two set groups' as problem
    from latest
    where group_id like 'set_lapsed_value_v1__%'
    group by person_id
    having count(*) > 1
),

split_sums as (
    select 'cust_givers_v1' as group_id, 'splits do not add up to parent' as problem
    from (select count(*) as n from latest where group_id = 'cust_givers_v1') as parent
    cross join (select count(*) as n, count(distinct group_id) as k from latest
                where group_id like 'cust_givers_v1__%') as splits
    where parent.n is distinct from splits.n or splits.k < 2
),

summary_rows as (
    select s.group_id, 'summary columns' as problem
    from {{ ref('pocore__group') }} as s
    where (s.group_id = 'set_lapsed_value_v1__std_lapsed_v1'
            and (s.group_set_id is distinct from 'set_lapsed_value_v1'
                 or s.parent_group_id is distinct from 'std_lapsed_v1'
                 or s.outcome_window_days is distinct from 180))
       or (s.group_id = 'set_lapsed_value_v1__remainder'
            and (s.parent_group_id is not null or s.primary_kpi is distinct from 'gave'))
       or (s.group_id like 'cust_givers_v1__%'
            and (s.split_by is distinct from 'acquisition_channel' or s.parent_group_id is distinct from 'cust_givers_v1'))
),

-- Certified too: every split value must appear in pocore__group (a new value with no complete
-- history yet used to vanish), so the split rows add up to the parent there as well.
certified_split_sums as (
    select 'cust_givers_v1' as group_id, 'certified splits do not add up to parent' as problem
    from (select people_in_group as n from {{ ref('pocore__group') }} where group_id = 'cust_givers_v1') as parent
    cross join (select sum(people_in_group) as n from {{ ref('pocore__group') }}
                where parent_group_id = 'cust_givers_v1' and split_by is not null) as splits
    where parent.n is distinct from splits.n
),

-- standard_splits: std_lapsed_v1 by region at 2026-09-30: D01, D04, D06, D10 are all ON -> one
-- split group std_lapsed_v1__on with all 4, labelled "Lapsed donors (13-24 months) — ON".
standard_split as (
    select 'std_lapsed_v1__on' as group_id, 'standard split' as problem
    from (select count(*) as n from latest where group_id = 'std_lapsed_v1__on') as a
    where a.n <> 4
    union all
    select s.group_id, 'standard split columns'
    from {{ ref('pocore__group') }} as s
    where s.group_id = 'std_lapsed_v1__on'
      and (s.parent_group_id is distinct from 'std_lapsed_v1' or s.split_by is distinct from 'region'
           or s.group_label is distinct from 'Lapsed donors (13-24 months) — ON' or s.outcome_window_days is distinct from 180)
),

summary_present as (
    select e.group_id, 'missing from pocore__group' as problem
    from expected_set as e
    left join {{ ref('pocore__group') }} as s on s.group_id = e.group_id
    where s.group_id is null
)

select * from set_counts
union all select * from set_overlap
union all select * from split_sums
union all select * from summary_rows
union all select * from summary_present
union all select * from certified_split_sums
union all select * from standard_split
