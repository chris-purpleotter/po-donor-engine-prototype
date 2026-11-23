{#
  pocore_group__flows__month — movement into and out of each segment, month by month.
  One row per segment_id x snapshot_date.

    donors_entering  in the segment at this snapshot, not at the previous month-end
                     (newly acquired, newly lapsed, newly reactivated, newly created, ...)
    donors_leaving   in the segment at the previous month-end, not at this one

  The first snapshot in the window has no previous month to compare against, so its
  flows are null (otherwise everyone would look like they "entered").
#}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

membership as (

    select segment_id, person_id, month_end_date as snapshot_date
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

-- In the segment now, but not at the previous month-end.
entering as (

    select this_month.segment_id, this_month.snapshot_date, count(*) as donors_entering
    from membership as this_month
    inner join snapshots
        on snapshots.snapshot_date = this_month.snapshot_date
    left join membership as last_month
        on  last_month.segment_id    = this_month.segment_id
        and last_month.person_id      = this_month.person_id
        and last_month.snapshot_date = snapshots.previous_snapshot_date
    where last_month.person_id is null
    group by this_month.segment_id, this_month.snapshot_date

),

-- In the segment at the previous month-end, but not now (counted at the current month).
leaving as (

    select last_month.segment_id, snapshots.snapshot_date, count(*) as donors_leaving
    from membership as last_month
    inner join snapshots
        on snapshots.previous_snapshot_date = last_month.snapshot_date
    left join membership as this_month
        on  this_month.segment_id    = last_month.segment_id
        and this_month.person_id      = last_month.person_id
        and this_month.snapshot_date = snapshots.snapshot_date
    where this_month.person_id is null
    group by last_month.segment_id, snapshots.snapshot_date

),

segment_months as (

    select distinct segment_id, snapshot_date from membership

)

select
    segment_months.segment_id,
    segment_months.snapshot_date,
    case when segment_months.snapshot_date = first_snapshot.snapshot_date then null
         else coalesce(entering.donors_entering, 0) end           as donors_entering,
    case when segment_months.snapshot_date = first_snapshot.snapshot_date then null
         else coalesce(leaving.donors_leaving, 0) end            as donors_leaving
from segment_months
cross join first_snapshot
left join entering
    on entering.segment_id = segment_months.segment_id and entering.snapshot_date = segment_months.snapshot_date
left join leaving
    on leaving.segment_id = segment_months.segment_id and leaving.snapshot_date = segment_months.snapshot_date
