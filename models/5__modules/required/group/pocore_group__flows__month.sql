{#
  pocore_group__flows__month — movement into and out of each group, month by month.
  One row per group_id x snapshot_date.

    donors_entering  in the group at this snapshot, not at the previous month-end
                     (newly acquired, newly lapsed, newly reactivated, newly created, ...)
    donors_leaving   in the group at the previous month-end, not at this one

  The first snapshot in the window has no previous month to compare against, so its
  flows are null (otherwise everyone would look like they "entered").
#}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

membership as (

    select group_id, person_id, month_end_date as snapshot_date
    from pocore_group__membership__month

),

snapshots as (

    select distinct
        snapshot_date,
        cast({{ dbt.dateadd('day', -1, dbt.date_trunc('month', 'snapshot_date')) }} as date) as previous_snapshot_date
    from membership

),

first_snapshot as (
    select min(snapshot_date) as snapshot_date from membership
),

-- In the group now, but not at the previous month-end.
entering as (

    select this_month.group_id, this_month.snapshot_date, count(*) as donors_entering
    from membership as this_month
    inner join snapshots
        on snapshots.snapshot_date = this_month.snapshot_date
    left join membership as last_month
        on  last_month.group_id    = this_month.group_id
        and last_month.person_id      = this_month.person_id
        and last_month.snapshot_date = snapshots.previous_snapshot_date
    where last_month.person_id is null
    group by this_month.group_id, this_month.snapshot_date

),

-- In the group at the previous month-end, but not now (counted at the current month).
leaving as (

    select last_month.group_id, snapshots.snapshot_date, count(*) as donors_leaving
    from membership as last_month
    inner join snapshots
        on snapshots.previous_snapshot_date = last_month.snapshot_date
    left join membership as this_month
        on  this_month.group_id    = last_month.group_id
        and this_month.person_id      = last_month.person_id
        and this_month.snapshot_date = snapshots.snapshot_date
    where this_month.person_id is null
    group by last_month.group_id, snapshots.snapshot_date

),

group_months as (

    select distinct group_id, snapshot_date from membership

)

select
    group_months.group_id,
    group_months.snapshot_date,
    case when group_months.snapshot_date = first_snapshot.snapshot_date then null
         else coalesce(entering.donors_entering, 0) end           as donors_entering,
    case when group_months.snapshot_date = first_snapshot.snapshot_date then null
         else coalesce(leaving.donors_leaving, 0) end            as donors_leaving
from group_months
cross join first_snapshot
left join entering
    on entering.group_id = group_months.group_id and entering.snapshot_date = group_months.snapshot_date
left join leaving
    on leaving.group_id = group_months.group_id and leaving.snapshot_date = group_months.snapshot_date
