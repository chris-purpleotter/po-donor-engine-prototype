{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_next_gift — ONE ROW PER GROUP x MONTH-END x MONTH AFTER (1-12): of the
  people in the group at that month-end, how many made their FIRST qualifying gift after it in
  that calendar month (next_gave_date on pocore_foundation__person__month_end). For the report's
  "when they gave" bars: month 1 after Jul 31 = August, so a burst shows in the month it happened.
  Each person counts once, so months 1-12 add up to the group's "gave within 365 days"
  (twelve calendar months after a month-end = the 365-day window; in a leap year a gift on
  day 366 is in neither).
#}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

-- each member who gave within 365 days, with the calendar month (1-12 after the month-end) they first gave in
first_gifts as (

    select
        pocore_group__membership__month.group_id,
        pocore_group__membership__month.month_end_date,
        (extract(year from pocore_foundation__person__month_end.next_gave_date) * 12 + extract(month from pocore_foundation__person__month_end.next_gave_date))
          - (extract(year from pocore_group__membership__month.month_end_date) * 12 + extract(month from pocore_group__membership__month.month_end_date))
                                                                                    as months_after
    from pocore_group__membership__month
    inner join pocore_foundation__person__month_end
        on  pocore_foundation__person__month_end.person_id      = pocore_group__membership__month.person_id
        and pocore_foundation__person__month_end.month_end_date = pocore_group__membership__month.month_end_date
    where pocore_foundation__person__month_end.next_gave_date is not null

)

select group_id, month_end_date, months_after, count(*) as people
from first_gifts
group by group_id, month_end_date, months_after
