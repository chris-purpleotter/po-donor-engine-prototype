{#
  pocore__person__year — ONE ROW PER PERSON x FISCAL YEAR (the donor JOURNEY), from the fiscal year the person
  first appears (created or first gift, whichever is earlier) to the current fiscal year.
  Individuals only (the same population as pocore__year and the segments); deceased people
  are kept, because they gave in those years.

  What happened in each person's year, and where they were on their journey:
    gave / gifts / amount_given   that year's KPI-eligible giving (SUMMABLE across years and people)
    movement_status               New / Second year / Continuing / Reactivated /
                                  Reactivated - second year (they gave), Lost (gave last year,
                                  not this year), Not giving (gave before, not last year or
                                  this year), Never given (no gift yet)
    stage                         lifecycle stage at stage_date: the fiscal year's last month-end
                                  (for the current year: the latest month-end)
    stage_1y_ago / _2y_ago / _3y_ago   the stage 12 / 24 / 36 months before stage_date
                                  (null before the snapshot history starts)

  The donor journey (Sankey): filter ONE fiscal_year and count people by stage_1y_ago -> stage.
  Clicking a flow gives the people behind it. Movement: counts by movement_status for one
  year match pocore__year (tested).
#}


with people as (

    select person_id, created_at, is_deceased, region, acquisition_channel, acquisition_theme
    from {{ ref('pocore_foundation__person') }}
    where person_type = 'individual'

),

giving as (

    select person_id, giving_year as fiscal_year, cohort_year, gifts, amount_given, donor_status
    from {{ ref('pocore_movement__person__year') }}

),

bounds as (
    select {{ pocore_helpers__fiscal_year(pocore_client_config__as_of_date()) }} as current_year
),

starts as (

    select
        p.person_id,
        case when g.first_gift_year is not null
                  and g.first_gift_year < {{ pocore_helpers__fiscal_year('p.created_at') }}
             then g.first_gift_year
             else {{ pocore_helpers__fiscal_year('p.created_at') }} end              as start_year,
        g.first_gift_year                                                   as cohort_year
    from people as p
    left join (
        select person_id, min(fiscal_year) as first_gift_year
        from giving
        group by person_id
    ) as g on g.person_id = p.person_id

),

-- Every person x every fiscal year from their start to now.
person_years as (

    select
        s.person_id,
        s.cohort_year,
        cast(s.start_year + (n.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
        b.current_year
    from starts as s
    cross join ({{ dbt.generate_series(200) }}) as n
    cross join bounds as b
    where s.start_year + (n.generated_number - 1) <= b.current_year

),

-- The month-end that represents each fiscal year: its last month-end in the snapshot history.
year_dates as (

    select {{ pocore_helpers__fiscal_year('month_end_date') }} as fiscal_year, max(month_end_date) as stage_date
    from (select distinct month_end_date from {{ ref('pocore_foundation__person__month_end') }}) as d
    group by {{ pocore_helpers__fiscal_year('month_end_date') }}

),

stages as (

    select person_id, month_end_date, lifecycle_stage
    from {{ ref('pocore_foundation__person__month_end') }}

),

with_giving as (

    select
        py.person_id,
        py.fiscal_year,
        py.cohort_year,
        g.donor_status,
        coalesce(g.gifts, 0)                                                    as gifts,
        coalesce(g.amount_given, 0)                                             as amount_given,
        (g.person_id is not null)                                               as gave,
        -- did they give last year / ever before this year?
        max(case when g.person_id is not null then py.fiscal_year end) over (
            partition by py.person_id order by py.fiscal_year
            rows between unbounded preceding and 1 preceding)                   as last_gave_year_before,
        (py.fiscal_year = py.current_year)                                      as is_partial_year
    from person_years as py
    left join giving as g
        on  g.person_id   = py.person_id
        and g.fiscal_year = py.fiscal_year

)

select
    w.person_id,
    w.fiscal_year,
    w.cohort_year,
    p.is_deceased,
    p.region,
    p.acquisition_channel,
    p.acquisition_theme,
    w.gave,
    w.gifts,
    w.amount_given,
    case
        when w.gave                                       then w.donor_status
        when w.last_gave_year_before = w.fiscal_year - 1  then 'Lost'
        when w.last_gave_year_before is not null          then 'Not giving'
        else 'Never given'
    end                                                                         as movement_status,
    yd.stage_date,
    s0.lifecycle_stage                                                          as stage,
    s1.lifecycle_stage                                                          as stage_1y_ago,
    s2.lifecycle_stage                                                          as stage_2y_ago,
    s3.lifecycle_stage                                                          as stage_3y_ago,
    w.is_partial_year
from with_giving as w
inner join people as p
    on p.person_id = w.person_id
left join year_dates as yd
    on yd.fiscal_year = w.fiscal_year
left join stages as s0
    on s0.person_id = w.person_id and s0.month_end_date = yd.stage_date
{%- for n in [1, 2, 3] %}
-- month-end N years earlier (month-end arithmetic: plain dateadd turns Feb 28 into Feb 28, not Feb 29)
left join stages as s{{ n }}
    on  s{{ n }}.person_id = w.person_id
    and s{{ n }}.month_end_date = cast({{ dbt.dateadd('day', -1,
            dbt.dateadd('month', 1 - 12 * n, dbt.date_trunc('month', 'yd.stage_date'))) }} as date)
{%- endfor %}
