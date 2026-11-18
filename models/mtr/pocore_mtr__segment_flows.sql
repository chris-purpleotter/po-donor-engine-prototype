{#
  pocore_mtr__segment_flows — movement into and out of each segment, month by month.
  One row per segment_id x snapshot_date.

    donors_entering  in the segment at this snapshot, not at the previous month-end
                     (newly acquired, newly lapsed, newly reactivated, newly created, ...)
    donors_leaving   in the segment at the previous month-end, not at this one

  The first snapshot in the window has no previous month to compare against, so its
  flows are null (otherwise everyone would look like they "entered").
#}

with membership as (

    select segment_id, person_id, month_end_date as snapshot_date
    from {{ ref('pocore_foundation__person__segment__month') }}

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

    select cur.segment_id, cur.snapshot_date, count(*) as donors_entering
    from membership as cur
    inner join snapshots as s
        on s.snapshot_date = cur.snapshot_date
    left join membership as prev
        on  prev.segment_id    = cur.segment_id
        and prev.person_id      = cur.person_id
        and prev.snapshot_date = s.previous_snapshot_date
    where prev.person_id is null
    group by cur.segment_id, cur.snapshot_date

),

-- In the segment at the previous month-end, but not now (counted at the current month).
leaving as (

    select prev.segment_id, s.snapshot_date, count(*) as donors_leaving
    from membership as prev
    inner join snapshots as s
        on s.previous_snapshot_date = prev.snapshot_date
    left join membership as cur
        on  cur.segment_id    = prev.segment_id
        and cur.person_id      = prev.person_id
        and cur.snapshot_date = s.snapshot_date
    where cur.person_id is null
    group by prev.segment_id, s.snapshot_date

),

segment_months as (

    select distinct segment_id, snapshot_date from membership

)

select
    sm.segment_id,
    sm.snapshot_date,
    case when sm.snapshot_date = f.snapshot_date then null
         else coalesce(e.donors_entering, 0) end           as donors_entering,
    case when sm.snapshot_date = f.snapshot_date then null
         else coalesce(l.donors_leaving, 0) end            as donors_leaving
from segment_months as sm
cross join first_snapshot as f
left join entering as e
    on e.segment_id = sm.segment_id and e.snapshot_date = sm.snapshot_date
left join leaving as l
    on l.segment_id = sm.segment_id and l.snapshot_date = sm.snapshot_date
