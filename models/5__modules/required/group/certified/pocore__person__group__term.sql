{#
  pocore__person__group__term — ONE ROW PER PERSON x GROUP x TERM: each unbroken stretch of
  month-ends a person spent in a group, from the month they joined to the month they left.
  Someone who leaves and comes back has a second term (term_number 2).

  Built from pocore_group__membership__month: a term is a run of CONSECUTIVE month-ends in it.
  Membership is checked at month-ends, so dates are month-ends, not days: a prospect who gave
  on Aug 12 "left" at Aug 31.

    joined_month_end    the first month-end of the term
    left_month_end      the first month-end they were NOT in the group after it (null: still in)
    months_in_group     month-ends in the term
    is_joined_before_data   in the group at the first month-end the engine looks at, so the real
                            start is earlier and unknown (snapshot_lookback_months). Leave these
                            out of "people who joined in month X" counts.

  Agrees with pocore__group__month: terms joining at a month-end = people_entering, terms
  leaving at it = people_leaving (tested).
#}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

first_snapshot as (

    select min(month_end_date) as first_month_end_date
    from pocore_foundation__person__month_end

),

-- Consecutive month-ends share (month number - row number): that value marks one term.
numbered as (

    select
        group_id,
        person_id,
        month_end_date,
        extract(year from month_end_date) * 12 + extract(month from month_end_date)
          - row_number() over (partition by group_id, person_id order by month_end_date)  as term_key
    from pocore_group__membership__month

),

terms as (

    select
        group_id,
        person_id,
        min(month_end_date)     as joined_month_end,
        max(month_end_date)     as last_month_end_in,
        count(*)                as months_in_group
    from numbered
    group by group_id, person_id, term_key

),

latest as (

    select max(month_end_date) as latest_month_end_date
    from pocore_group__membership__month

)

select
    terms.person_id,
    terms.group_id,
    row_number() over (partition by terms.group_id, terms.person_id order by terms.joined_month_end)  as term_number,
    terms.joined_month_end,
    case when terms.last_month_end_in < latest.latest_month_end_date
         then cast({{ dbt.last_day(dbt.dateadd('month', 1, dbt.date_trunc('month', 'terms.last_month_end_in')), 'month') }} as date)
    end                                                                          as left_month_end,
    terms.months_in_group,
    (terms.joined_month_end = first_snapshot.first_month_end_date)               as is_joined_before_data
from terms
cross join latest
cross join first_snapshot
