{#
  pocore_foundation__date — ONE ROW PER DAY: the CALENDAR DIMENSION of the foundation star.
  From the earliest gift or snapshot month (whichever is first) to as_of, every day, whether
  anything happened or not.

  Join a fact's date to date_day: foundation__gift.gift_date, foundation__person__month_end.month_end_date.
  Then group by month, fiscal year or quarter without re-deriving them in every query, and filter
  the month-end snapshot to one moment with is_latest_month_end.

    month_start_date / month_end_date   the calendar month the day falls in
    is_month_end                        the last day of its month (the snapshot's dates)
    is_latest_month_end                 the latest month-end on or before as_of (the report's "now")
    fiscal_year                         var fiscal_year_start_month; named by the year it ENDS in
#}

with

pocore_event__gift as (select * from {{ ref('pocore_event__gift') }}),

pocore_rollup__person__month_end_lookback as (select * from {{ ref('pocore_rollup__person__month_end_lookback') }}),

-- start at the earliest date any fact uses: the first gift, or the first month-end snapshot
bounds as (

    select cast(min(first_day) as date) as first_day
    from (
        select min(gift_date) as first_day from pocore_event__gift
        union all
        select cast({{ dbt.date_trunc('month', 'min(snapshot_date)') }} as date) from pocore_rollup__person__month_end_lookback
    ) as candidate_starts

),

days as (

    select
        {# generated_number is FLOAT64 on BigQuery (dbt builds it with power()); INTERVAL needs a whole number #}
        cast({{ dbt.dateadd('day', 'cast(series.generated_number as ' ~ dbt.type_int() ~ ') - 1', 'bounds.first_day') }} as date) as date_day
    from bounds
    cross join ({{ dbt.generate_series(40000) }}) as series     -- up to ~109 years of history

),

calendar as (

    select
        date_day,
        cast({{ dbt.date_trunc('month', 'date_day') }} as date)                        as month_start_date,
        cast({{ dbt.last_day('date_day', 'month') }} as date)                          as month_end_date,
        extract(year from date_day)                                                    as calendar_year,
        extract(quarter from date_day)                                                 as calendar_quarter,
        extract(month from date_day)                                                   as month_number,
        {{ pocore_helpers__fiscal_year('date_day') }}                                  as fiscal_year
    from days
    where date_day <= {{ pocore_client_config__as_of_date() }}

)

select
    calendar.*,
    (calendar.date_day = calendar.month_end_date)                                      as is_month_end,
    (calendar.date_day = max(case when calendar.date_day = calendar.month_end_date
                                  then calendar.date_day end) over ())                 as is_latest_month_end
from calendar
